//! Native Zig `.dylib` Plugin Manager (`src/app/plugin_manager.zig`).
//!
//! Discovers, loads, hot-reloads, sandboxes, and profiles dynamically loaded editor plugins
//! conforming to `platform.plugin_abi.EditorPluginV1`.
//!
//! Key Responsibilities:
//!   - Scans `zig-out/plugins/*.dylib` every 500ms using `std.c.stat` mtime checks.
//!   - Copies updated `.dylib` files to `/tmp/skia_editor_plugin_<name>_gen<N>.dylib` and loads
//!     them via `dlopen(..., RTLD_NOW | RTLD_LOCAL)`, invoking `before_reload` -> `dlclose` ->
//!     `dlopen` -> `on_reload` while preserving plugin state in the host `StateStore`.
//!   - Implements the `EditorHostApiV1` and `PluginUiApiV1` vtable backed by `EditorState` and `ui.Context`.
//!   - Tracks per-plugin CPU timings (`last_input_us`, `last_paint_us`, `peak_frame_us`) and reload counts.

const std = @import("std");
const skia = @import("skia");
const ui = @import("ui");
const platform = @import("platform");
const abi = platform.plugin_abi;
const sdk = platform.plugin_sdk;
const fs_util = platform.fs_util;
const git_client = @import("git_client.zig");
const state_mod = @import("state.zig");
const EditorState = state_mod.EditorState;

pub const MaxPlugins: usize = 20;
pub const MaxCommandsPerPlugin: usize = 8;
pub const MaxPluginCompletions: usize = 8;
pub const MaxBreakpoints: usize = 32;

pub const StoredBreakpoint = struct {
    file_path: platform.InlineString(160) = .{},
    line: u32 = 1, // 1-based line number
    enabled: bool = true,
    hit_count: u32 = 0,
};

pub const StoredCompletionItem = struct {
    label: platform.InlineString(48) = .{},
    detail: platform.InlineString(48) = .{},
    insert_text: platform.InlineString(64) = .{},
    kind: u8 = 0,
    replace_prefix_len: u16 = 0,
};

pub const PluginPriority = enum(u8) {
    bundled = 0, // <exe_dir>/../plugins (inside application bundle)
    workspace = 1, // zig-out/plugins (active workspace)
    user = 2, // ~/.lightning/plugins, ~/.config/lightning/plugins, ~/plugins (user home overrides)
};

pub const PluginSearchDir = struct {
    path_buf: [256:0]u8 = @splat(0),
    path_len: u16 = 0,
    priority: PluginPriority = .bundled,

    pub fn slice(self: *const PluginSearchDir) [:0]const u8 {
        return self.path_buf[0..self.path_len :0];
    }
};

pub const MaxPluginSearchDirs: usize = 8;

pub const PluginCommandEntry = struct {
    cmd_id: platform.InlineString(64) = .{},
    title: platform.InlineString(96) = .{},
    category: platform.InlineString(32) = .{},
    shortcut_hint: platform.InlineString(32) = .{},
};

pub const LoadedPlugin = struct {
    active: bool = false,
    enabled: bool = true,
    is_dynamic: bool = false,
    priority: PluginPriority = .bundled,
    is_user_override: bool = false,

    // Value-copied manifest strings (safe across dlclose)
    id: platform.InlineString(64) = .{},
    display_name: platform.InlineString(64) = .{},
    version: platform.InlineString(32) = .{},
    sidebar_title: platform.InlineString(48) = .{},
    bottom_tab_title: platform.InlineString(48) = .{},
    debug_extensions: platform.InlineString(96) = .{},
    sidebar_icon: abi.PluginSidebarIcon = .none,
    capabilities: abi.PluginCapabilities = .{},

    // Dynamic library hot-reload tracking
    dylib_path_buf: [256:0]u8 = @splat(0),
    dylib_path_len: usize = 0,
    temp_path_buf: [256:0]u8 = @splat(0),
    has_temp_path: bool = false,
    handle: ?*anyopaque = null,
    last_mtime: f64 = 0,
    generation: u32 = 0,

    descriptor: abi.EditorPluginV1 = .{
        .manifest = .{
            .id = .{},
            .display_name = .{},
            .version = .{},
        },
    },

    commands: [MaxCommandsPerPlugin]PluginCommandEntry = @splat(.{}),
    command_count: usize = 0,

    // Fallback state slot for headless unit tests where `PlatformContext.state_store` is null
    fallback_state_buf: [32768]u8 align(16) = @splat(0),
    fallback_state_hash: u64 = 0,
    fallback_state_init: bool = false,

    // Per-plugin CPU & lifecycle telemetry
    last_input_us: u32 = 0,
    last_paint_us: u32 = 0,
    peak_frame_us: u32 = 0,
    reload_count: u32 = 0,
    invocations: u64 = 0,

    pub fn dylibPathZ(self: *const LoadedPlugin) [*:0]const u8 {
        return @ptrCast(&self.dylib_path_buf);
    }

    pub fn tempPathZ(self: *const LoadedPlugin) [*:0]const u8 {
        return @ptrCast(&self.temp_path_buf);
    }
};

const HostCallbackCtx = struct {
    mgr: *PluginManager,
    state: *EditorState,
    plugin_idx: usize,
};

pub const PluginManager = struct {
    plugins: [MaxPlugins]LoadedPlugin = @splat(.{}),
    plugin_count: usize = 0,
    last_scan_ms: i64 = 0,
    initialized: bool = false,
    cached_search_dirs: [MaxPluginSearchDirs]PluginSearchDir = @splat(.{}),
    cached_search_dir_count: usize = 0,
    cached_search_dir_cwd_hash: u64 = 0,
    cached_search_dir_mtimes: [MaxPluginSearchDirs]u64 = @splat(0),

    // Active autocomplete popup items contributed by language server plugins
    completions: [MaxPluginCompletions]StoredCompletionItem = @splat(.{}),
    completion_count: usize = 0,
    completion_buffer_id: u32 = 0xFFFFFFFF,
    completion_cursor_offset: usize = 0,
    selected_completion: usize = 0,

    // Shared workspace breakpoints & active debugger execution location
    breakpoints: [MaxBreakpoints]StoredBreakpoint = @splat(.{}),
    breakpoint_count: usize = 0,
    breakpoint_revision: u32 = 1,
    debug_active: bool = false,
    debug_paused: bool = false,
    debug_file_path: platform.InlineString(160) = .{},
    debug_line: u32 = 0,

    pub fn pathsMatch(a: []const u8, b: []const u8) bool {
        if (a.len == 0 or b.len == 0) return false;
        if (std.mem.eql(u8, a, b)) return true;
        if (a.len > b.len and std.mem.endsWith(u8, a, b) and a[a.len - b.len - 1] == '/') return true;
        if (b.len > a.len and std.mem.endsWith(u8, b, a) and b[b.len - a.len - 1] == '/') return true;
        return std.mem.eql(u8, std.fs.path.basename(a), std.fs.path.basename(b));
    }

    /// Returns `true` if any active, enabled debugger plugin declares support for `file_path`'s extension.
    pub fn hasDebuggerForFile(self: *const PluginManager, file_path: []const u8) bool {
        if (file_path.len == 0 or file_path[0] == '*') return false;
        const ext = std.fs.path.extension(file_path);
        if (ext.len == 0) return false;

        for (0..self.plugin_count) |idx| {
            const p = &self.plugins[idx];
            if (!p.active or !p.enabled) continue;
            const exts = p.debug_extensions.slice();
            if (exts.len == 0) continue;

            var it = std.mem.splitScalar(u8, exts, ',');
            while (it.next()) |raw_tok| {
                const tok = std.mem.trim(u8, raw_tok, " \t");
                if (tok.len > 0 and std.ascii.eqlIgnoreCase(ext, tok)) {
                    return true;
                }
            }
        }
        return false;
    }

    pub fn toggleBreakpoint(self: *PluginManager, file_path: []const u8, line_1based: u32) bool {
        if (line_1based == 0) return false;
        const effective_path = if (file_path.len > 0) file_path else "*scratch*";
        var i: usize = 0;
        while (i < self.breakpoint_count) : (i += 1) {
            const bp = &self.breakpoints[i];
            if (bp.line == line_1based and pathsMatch(bp.file_path.slice(), effective_path)) {
                var j = i;
                while (j + 1 < self.breakpoint_count) : (j += 1) {
                    self.breakpoints[j] = self.breakpoints[j + 1];
                }
                self.breakpoint_count -= 1;
                self.breakpoint_revision +%= 1;
                return false;
            }
        }
        if (self.breakpoint_count < MaxBreakpoints) {
            var bp = &self.breakpoints[self.breakpoint_count];
            bp.* = .{
                .line = line_1based,
                .enabled = true,
                .hit_count = 0,
            };
            bp.file_path.set(effective_path);
            self.breakpoint_count += 1;
            self.breakpoint_revision +%= 1;
            return true;
        }
        return false;
    }

    pub fn clearBreakpoints(self: *PluginManager) void {
        self.breakpoint_count = 0;
        self.breakpoint_revision +%= 1;
    }

    pub fn breakpointLinesForFile(
        self: *const PluginManager,
        arena: std.mem.Allocator,
        file_path: []const u8,
    ) []const u32 {
        if (self.breakpoint_count == 0) return &.{};
        const effective_path = if (file_path.len > 0) file_path else "*scratch*";
        var count: usize = 0;
        for (self.breakpoints[0..self.breakpoint_count]) |*bp| {
            if (bp.enabled and pathsMatch(bp.file_path.slice(), effective_path)) {
                count += 1;
            }
        }
        if (count == 0) return &.{};
        const out = arena.alloc(u32, count) catch return &.{};
        var idx: usize = 0;
        for (self.breakpoints[0..self.breakpoint_count]) |*bp| {
            if (bp.enabled and pathsMatch(bp.file_path.slice(), effective_path)) {
                out[idx] = bp.line;
                idx += 1;
            }
        }
        return out;
    }

    pub fn activeDebugLineForFile(self: *const PluginManager, file_path: []const u8) ?u32 {
        if (!self.debug_active or !self.debug_paused or self.debug_line == 0) return null;
        const effective_path = if (file_path.len > 0) file_path else "*scratch*";
        if (self.debug_file_path.len == 0 or pathsMatch(self.debug_file_path.slice(), effective_path)) {
            return self.debug_line;
        }
        return null;
    }

    pub fn executePluginCommandById(self: *PluginManager, state: *EditorState, cmd_id: []const u8) bool {
        for (0..self.plugin_count) |p_idx| {
            const p = &self.plugins[p_idx];
            if (!p.active or !p.enabled) continue;
            for (0..p.command_count) |c_idx| {
                if (std.mem.eql(u8, p.commands[c_idx].cmd_id.slice(), cmd_id)) {
                    self.executePluginCommand(state, p_idx, c_idx);
                    return true;
                }
            }
        }
        return false;
    }

    pub fn clearCompletions(self: *PluginManager) void {
        self.completion_count = 0;
        self.selected_completion = 0;
    }

    pub fn activeCompletionsFor(
        self: *const PluginManager,
        arena: std.mem.Allocator,
        buffer_id: u32,
        cursor_offset: usize,
    ) []const ui.CompletionPopupItem {
        if (self.completion_count == 0 or self.completion_buffer_id != buffer_id or self.completion_cursor_offset != cursor_offset) {
            return &.{};
        }
        const n = @min(self.completion_count, MaxPluginCompletions);
        const slice = arena.alloc(ui.CompletionPopupItem, n) catch return &.{};
        for (0..n) |i| {
            const src = &self.completions[i];
            slice[i] = .{
                .label = src.label.slice(),
                .detail = src.detail.slice(),
                .insert_text = src.insert_text.slice(),
                .kind = src.kind,
                .replace_prefix_len = src.replace_prefix_len,
            };
        }
        return slice;
    }

    pub fn deinit(self: *PluginManager, state: *EditorState) void {
        for (0..self.plugin_count) |idx| {
            var p = &self.plugins[idx];
            if (!p.active) continue;
            if (p.descriptor.deinit) |deinit_fn| {
                self.invokeHook(state, idx, deinit_fn);
            }
            // Note: Keep dynamic `.dylib` handles mapped at process exit so `xctrace` can symbolicate plugin frames.
            p.handle = null;
            p.active = false;
        }
        self.plugin_count = 0;
    }

    /// Registers an in-memory `EditorPluginV1` descriptor (used for built-in plugins and unit tests).
    pub fn registerStaticPlugin(self: *PluginManager, state: *EditorState, desc: abi.EditorPluginV1) ?usize {
        if (desc.manifest.abi_version != abi.EDITOR_PLUGIN_ABI_VERSION) return null;
        const id_slice = desc.manifest.id.toZig();
        if (id_slice.len == 0) return null;

        // Check if already registered
        for (0..self.plugin_count) |idx| {
            if (self.plugins[idx].active and std.mem.eql(u8, self.plugins[idx].id.slice(), id_slice)) {
                self.bindDescriptor(state, idx, desc, true);
                return idx;
            }
        }

        if (self.plugin_count >= MaxPlugins) return null;
        const idx = self.plugin_count;
        self.plugin_count += 1;
        self.plugins[idx] = .{
            .active = true,
            .enabled = true,
            .is_dynamic = false,
        };
        self.bindDescriptor(state, idx, desc, false);
        return idx;
    }

    fn bindDescriptor(self: *PluginManager, state: *EditorState, idx: usize, desc: abi.EditorPluginV1, is_reload: bool) void {
        var p = &self.plugins[idx];
        p.descriptor = desc;
        p.id.set(desc.manifest.id.toZig());
        p.display_name.set(desc.manifest.display_name.toZig());
        p.version.set(desc.manifest.version.toZig());
        p.sidebar_title.set(if (desc.manifest.sidebar_title.len > 0) desc.manifest.sidebar_title.toZig() else desc.manifest.display_name.toZig());
        p.bottom_tab_title.set(if (desc.manifest.bottom_tab_title.len > 0) desc.manifest.bottom_tab_title.toZig() else desc.manifest.display_name.toZig());
        p.debug_extensions.set(desc.manifest.debug_extensions.toZig());
        p.sidebar_icon = desc.manifest.sidebar_icon;
        p.capabilities = desc.manifest.capabilities;
        p.command_count = 0;

        if (!is_reload) {
            p.enabled = state.isPluginEnabledInDoc(p.id.slice());
        }

        if (is_reload) {
            p.reload_count += 1;
            if (desc.init) |init_fn| {
                self.invokeHook(state, idx, init_fn);
            }
            if (desc.on_reload) |reload_fn| {
                self.invokeHook(state, idx, reload_fn);
            }
        } else {
            if (desc.init) |init_fn| {
                self.invokeHook(state, idx, init_fn);
            }
        }
    }

    fn queryFileMtime(path_z: [*:0]const u8) f64 {
        return fs_util.fileMtimeSec(path_z) orelse 0;
    }

    pub fn copyFilePosix(src_z: [*:0]const u8, dst_z: [*:0]const u8) bool {
        return fs_util.copyFileAtomic(src_z, dst_z);
    }

    /// Loads or hot-reloads a single `.dylib` file from disk with default workspace priority.
    pub fn loadOrReloadDylib(self: *PluginManager, state: *EditorState, dylib_path: []const u8) bool {
        return self.loadOrReloadDylibWithPriority(state, dylib_path, .workspace);
    }

    /// Loads or hot-reloads a `.dylib` plugin with explicit priority ranking.
    /// User plugins from `~/` (.user) take precedence over workspace (.workspace)
    /// and bundled application plugins (.bundled).
    pub fn loadOrReloadDylibWithPriority(
        self: *PluginManager,
        state: *EditorState,
        dylib_path: []const u8,
        priority: PluginPriority,
    ) bool {
        if (dylib_path.len == 0 or dylib_path.len >= 254) return false;

        var path_z: [256:0]u8 = @splat(0);
        @memcpy(path_z[0..dylib_path.len], dylib_path);
        path_z[dylib_path.len] = 0;

        const mtime = queryFileMtime(&path_z);
        if (mtime == 0) return false;

        // Find existing slot by dylib_path or basename, or allocate a new slot
        const req_base = std.fs.path.basename(dylib_path);
        var slot_opt: ?usize = null;
        for (0..self.plugin_count) |idx| {
            var p = &self.plugins[idx];
            if (p.active and p.is_dynamic) {
                const existing_path = p.dylib_path_buf[0..p.dylib_path_len];
                if (std.mem.eql(u8, existing_path, dylib_path) or
                    std.mem.eql(u8, std.fs.path.basename(existing_path), req_base))
                {
                    // If candidate has strictly LOWER priority than the existing active plugin,
                    // and the higher-priority file is still present on disk, ignore lower-priority candidate!
                    if (@intFromEnum(priority) < @intFromEnum(p.priority)) {
                        const existing_mtime = queryFileMtime(p.dylibPathZ());
                        if (existing_mtime > 0) {
                            return false; // Higher priority override is active and present on disk
                        }
                    }

                    const path_changed = !std.mem.eql(u8, existing_path, dylib_path);
                    if (path_changed) {
                        @memcpy(p.dylib_path_buf[0..dylib_path.len], dylib_path);
                        p.dylib_path_buf[dylib_path.len] = 0;
                        p.dylib_path_len = dylib_path.len;
                    }
                    p.priority = priority;
                    p.is_user_override = (priority == .user);

                    // If path did not change and mtime is identical, no reload needed
                    if (!path_changed and mtime == p.last_mtime) return false;
                    slot_opt = idx;
                    break;
                }
            }
        }

        const idx = slot_opt orelse blk: {
            if (self.plugin_count >= MaxPlugins) return false;
            const new_idx = self.plugin_count;
            self.plugin_count += 1;
            self.plugins[new_idx] = .{
                .active = true,
                .enabled = true,
                .is_dynamic = true,
                .priority = priority,
                .is_user_override = (priority == .user),
            };
            @memcpy(self.plugins[new_idx].dylib_path_buf[0..dylib_path.len], dylib_path);
            self.plugins[new_idx].dylib_path_buf[dylib_path.len] = 0;
            self.plugins[new_idx].dylib_path_len = dylib_path.len;
            break :blk new_idx;
        };

        var p = &self.plugins[idx];
        p.generation += 1;
        p.priority = priority;
        p.is_user_override = (priority == .user);

        const base_name = std.fs.path.stem(dylib_path);
        var temp_buf: [256:0]u8 = @splat(0);
        const temp_slice = std.fmt.bufPrint(
            &temp_buf,
            "{s}/skia_editor_plugin_{s}_gen{d}{s}",
            .{ fs_util.tempDirPath(), base_name, p.generation, fs_util.SharedLibExt },
        ) catch return false;
        temp_buf[temp_slice.len] = 0;

        if (!fs_util.copyFileAtomic(&path_z, &temp_buf)) return false;

        const new_handle = platform.objc.dlopen(&temp_buf, platform.objc.RTLD_NOW | platform.objc.RTLD_LOCAL) orelse return false;
        const entry_sym = platform.objc.dlsym(new_handle, abi.PLUGIN_ENTRY_SYMBOL) orelse {
            _ = platform.objc.dlclose(new_handle);
            return false;
        };

        const entry_fn: abi.PluginEntryFn = @ptrCast(@alignCast(entry_sym));
        const desc_ptr = entry_fn();
        if (desc_ptr.manifest.abi_version != abi.EDITOR_PLUGIN_ABI_VERSION) {
            _ = platform.objc.dlclose(new_handle);
            return false;
        }

        const is_reload = (p.handle != null);
        if (is_reload) {
            if (p.descriptor.before_reload) |before_fn| {
                self.invokeHook(state, idx, before_fn);
            }
            if (p.handle) |old_h| {
                _ = platform.objc.dlclose(old_h);
            }
            if (p.has_temp_path) {
                _ = fs_util.unlink(p.tempPathZ());
            }
        }

        @memcpy(p.temp_path_buf[0..temp_slice.len], temp_slice);
        p.temp_path_buf[temp_slice.len] = 0;
        p.has_temp_path = true;
        p.handle = new_handle;
        p.last_mtime = mtime;

        self.bindDescriptor(state, idx, desc_ptr.*, is_reload);

        // Deduplicate any other slot with the exact same manifest id
        const manifest_id = desc_ptr.manifest.id.toZig();
        for (0..self.plugin_count) |other_idx| {
            if (other_idx == idx) continue;
            var other_p = &self.plugins[other_idx];
            if (other_p.active and other_p.is_dynamic and std.mem.eql(u8, other_p.id.slice(), manifest_id)) {
                if (@intFromEnum(priority) >= @intFromEnum(other_p.priority)) {
                    other_p.active = false;
                    if (other_p.handle) |old_h| _ = platform.objc.dlclose(old_h);
                    other_p.handle = null;
                }
            }
        }

        var notice_buf: [128]u8 = undefined;
        if (p.is_user_override) {
            if (std.fmt.bufPrint(&notice_buf, "Loaded plugin '{s}' from ~/ (gen #{d})", .{ p.display_name.slice(), p.generation })) |msg| {
                state.status_notice.set(msg);
            } else |_| {}
        } else if (is_reload) {
            if (std.fmt.bufPrint(&notice_buf, "Hot-reloaded plugin '{s}' (gen #{d})", .{ p.display_name.slice(), p.generation })) |msg| {
                state.status_notice.set(msg);
            } else |_| {}
        }
        return true;
    }

    pub fn collectPluginSearchDirs(out: *[MaxPluginSearchDirs]PluginSearchDir) usize {
        var count: usize = 0;
        var real_buf: [std.fs.max_path_bytes]u8 = undefined;

        // 1. Explicit environment variable: LIGHTNING_PLUGIN_PATH (highest priority)
        if (fs_util.getenv("LIGHTNING_PLUGIN_PATH")) |env_p| {
            const s = std.mem.sliceTo(env_p, 0);
            if (s.len > 0 and s.len < 250) {
                if (fs_util.realpath(env_p, &real_buf)) |rz| {
                    const r = std.mem.sliceTo(rz, 0);
                    if (count < MaxPluginSearchDirs and r.len < 255) {
                        @memcpy(out[count].path_buf[0..r.len], r);
                        out[count].path_buf[r.len] = 0;
                        out[count].path_len = @intCast(r.len);
                        out[count].priority = .user;
                        count += 1;
                    }
                }
            }
        }

        // 2. User home directories: ~/.lightning/plugins, ~/.config/lightning/plugins,
        //    ~/Library/Application Support/Lightning/plugins, ~/plugins
        if (fs_util.getenv("HOME")) |home_z| {
            const home = std.mem.sliceTo(home_z, 0);
            if (home.len > 0 and home.len < 200) {
                const user_subdirs = [_][]const u8{
                    "/.lightning/plugins",
                    "/.config/lightning/plugins",
                    "/Library/Application Support/Lightning/plugins",
                    "/plugins",
                };
                for (user_subdirs) |sub| {
                    var cand_buf: [512:0]u8 = @splat(0);
                    if (std.fmt.bufPrint(&cand_buf, "{s}{s}", .{ home, sub })) |cand| {
                        cand_buf[cand.len] = 0;
                        if (fs_util.realpath(&cand_buf, &real_buf)) |rz| {
                            const r = std.mem.sliceTo(rz, 0);
                            var duplicate = false;
                            for (out[0..count]) |existing| {
                                if (std.mem.eql(u8, existing.slice(), r)) {
                                    duplicate = true;
                                    break;
                                }
                            }
                            if (!duplicate and count < MaxPluginSearchDirs and r.len < 255) {
                                @memcpy(out[count].path_buf[0..r.len], r);
                                out[count].path_buf[r.len] = 0;
                                out[count].path_len = @intCast(r.len);
                                out[count].priority = .user;
                                count += 1;
                            }
                        }
                    } else |_| {}
                }
            }
        }

        // 3. Local workspace development directory: zig-out/plugins
        if (fs_util.realpath("zig-out/plugins", &real_buf)) |rz| {
            const r = std.mem.sliceTo(rz, 0);
            var duplicate = false;
            for (out[0..count]) |existing| {
                if (std.mem.eql(u8, existing.slice(), r)) {
                    duplicate = true;
                    break;
                }
            }
            if (!duplicate and count < MaxPluginSearchDirs and r.len < 255) {
                @memcpy(out[count].path_buf[0..r.len], r);
                out[count].path_buf[r.len] = 0;
                out[count].path_len = @intCast(r.len);
                out[count].priority = .workspace;
                count += 1;
            }
        }

        // 4. Bundled application directory: <exe_dir>/../plugins (inside Lightning.app/Contents/plugins)
        var exe_buf: [std.fs.max_path_bytes]u8 = undefined;
        var exe_len: u32 = exe_buf.len;
        if (fs_util._NSGetExecutablePath(&exe_buf, &exe_len) == 0) {
            var exe_real_buf: [std.fs.max_path_bytes]u8 = undefined;
            const exe_slice = if (fs_util.realpath(@ptrCast(&exe_buf), &exe_real_buf)) |rz|
                std.mem.sliceTo(rz, 0)
            else
                std.mem.sliceTo(exe_buf[0..], 0);
            if (std.fs.path.dirname(exe_slice)) |exe_dir| {
                var cand_buf: [512:0]u8 = @splat(0);
                if (std.fmt.bufPrint(&cand_buf, "{s}/../plugins", .{exe_dir})) |cand| {
                    cand_buf[cand.len] = 0;
                    if (fs_util.realpath(&cand_buf, &real_buf)) |rz| {
                        const r = std.mem.sliceTo(rz, 0);
                        var duplicate = false;
                        for (out[0..count]) |existing| {
                            if (std.mem.eql(u8, existing.slice(), r)) {
                                duplicate = true;
                                break;
                            }
                        }
                        if (!duplicate and count < MaxPluginSearchDirs and r.len < 255) {
                            @memcpy(out[count].path_buf[0..r.len], r);
                            out[count].path_buf[r.len] = 0;
                            out[count].path_len = @intCast(r.len);
                            out[count].priority = .bundled;
                            count += 1;
                        }
                    }
                } else |_| {}
            }
        }

        return count;
    }

    pub fn getUserPluginsDirectory(out_buf: *[256:0]u8) ?[]const u8 {
        if (fs_util.getenv("HOME")) |home_z| {
            const home = std.mem.sliceTo(home_z, 0);
            if (home.len > 0 and home.len < 200) {
                if (std.fmt.bufPrint(out_buf[0..254], "{s}/.lightning/plugins", .{home})) |cand| {
                    out_buf[cand.len] = 0;
                    return out_buf[0..cand.len :0];
                } else |_| {}
            }
        }
        return null;
    }

    pub fn userPluginsDirectory(_: *const PluginManager, out_buf: *[256:0]u8) ?[]const u8 {
        return getUserPluginsDirectory(out_buf);
    }

    pub fn ensureUserPluginsDirectoryExistsStatic() ?[*:0]const u8 {
        if (fs_util.getenv("HOME")) |home_z| {
            const home = std.mem.sliceTo(home_z, 0);
            if (home.len > 0 and home.len < 200) {
                var dot_lightning_buf: [256:0]u8 = @splat(0);
                if (std.fmt.bufPrint(&dot_lightning_buf, "{s}/.lightning", .{home})) |p1| {
                    dot_lightning_buf[p1.len] = 0;
                    _ = fs_util.mkdir(&dot_lightning_buf, 0o755);
                } else |_| {}
                var plug_buf: [256:0]u8 = @splat(0);
                if (std.fmt.bufPrint(&plug_buf, "{s}/.lightning/plugins", .{home})) |p2| {
                    plug_buf[p2.len] = 0;
                    _ = fs_util.mkdir(&plug_buf, 0o755);
                    return @ptrCast(&plug_buf);
                } else |_| {}
            }
        }
        return null;
    }

    pub fn ensureUserPluginsDirectoryExists(_: *const PluginManager) ?[*:0]const u8 {
        return ensureUserPluginsDirectoryExistsStatic();
    }

    pub fn resolvePluginsDirectory(out_buf: *[256:0]u8) ?[]const u8 {
        var search_dirs: [MaxPluginSearchDirs]PluginSearchDir = undefined;
        const count = collectPluginSearchDirs(&search_dirs);
        if (count > 0) {
            const s = search_dirs[0].slice();
            @memcpy(out_buf[0..s.len], s);
            out_buf[s.len] = 0;
            return out_buf[0..s.len :0];
        }
        return null;
    }

    /// Scans plugin search directories (user ~/.lightning/plugins, zig-out/plugins, and bundled app plugins)
    /// and hot-reloads modified or upgraded plugins every 2000ms.
    pub fn scanAndReloadPlugins(self: *PluginManager, state: *EditorState, force: bool) bool {
        const now_ms: i64 = @intCast(platform.profiler.nowNs() / std.time.ns_per_ms);
        if (!force and self.initialized and (now_ms - self.last_scan_ms) < 2000) {
            return false;
        }
        self.last_scan_ms = now_ms;
        const was_init = self.initialized;
        self.initialized = true;

        const cwd_hash = std.hash.Fnv1a_64.hash(state.workspaceRoot());
        if (force or !was_init or self.cached_search_dir_count == 0 or cwd_hash != self.cached_search_dir_cwd_hash) {
            self.cached_search_dir_count = collectPluginSearchDirs(&self.cached_search_dirs);
            self.cached_search_dir_cwd_hash = cwd_hash;
            self.cached_search_dir_mtimes = @splat(0);
        }
        const dir_count = self.cached_search_dir_count;
        if (dir_count == 0) return false;

        var any_reloaded = false;
        for (self.cached_search_dirs[0..dir_count], 0..) |*sdir, d_idx| {
            var dir_buf: [256:0]u8 = @splat(0);
            @memcpy(dir_buf[0..sdir.path_len], sdir.slice());
            dir_buf[sdir.path_len] = 0;

            const dir_mtime = EditorState.statMtimeHash(&dir_buf);
            if (!force and was_init and dir_mtime != 0 and dir_mtime == self.cached_search_dir_mtimes[d_idx]) {
                continue;
            }
            self.cached_search_dir_mtimes[d_idx] = dir_mtime;

            const dir_handle = fs_util.opendir(&dir_buf) orelse continue;
            defer _ = fs_util.closedir(dir_handle);

            while (fs_util.readdir(dir_handle)) |entry| {
                const name = entry.d_name[0..entry.d_namlen];
                if (!std.mem.endsWith(u8, name, fs_util.SharedLibExt) and !std.mem.endsWith(u8, name, ".dylib")) continue;
                var full_buf: [256]u8 = undefined;
                const full_path = std.fmt.bufPrint(&full_buf, "{s}/{s}", .{ sdir.slice(), name }) catch continue;
                if (self.loadOrReloadDylibWithPriority(state, full_path, sdir.priority)) {
                    any_reloaded = true;
                }
            }
        }
        return any_reloaded;
    }

    // ========================================================================
    // Plugin Hook Dispatchers & Profiling
    // ========================================================================

    fn invokeHook(self: *PluginManager, state: *EditorState, idx: usize, hook_fn: abi.PluginHookFn) void {
        var p = &self.plugins[idx];
        var root_scope = state.ui_ctx.scopedState("__plugins");
        defer root_scope.end();
        var plug_scope = state.ui_ctx.scopedState(p.id.slice());
        defer plug_scope.end();

        var hctx = HostCallbackCtx{
            .mgr = self,
            .state = state,
            .plugin_idx = idx,
        };
        const t0 = platform.profiler.nowNs();
        hook_fn(&hctx, &HOST_API_V1);
        const elapsed_us: u32 = @intCast((platform.profiler.nowNs() - t0) / 1000);
        if (state.ui_ctx.pass == .paint) {
            p.last_paint_us = elapsed_us;
        } else {
            p.last_input_us = elapsed_us;
        }
        const total_us = p.last_input_us + p.last_paint_us;
        if (total_us > p.peak_frame_us) {
            p.peak_frame_us = total_us;
        }
        p.invocations += 1;
    }

    pub fn pollPluginsInputPass(self: *PluginManager, state: *EditorState) void {
        if (self.scanAndReloadPlugins(state, false)) {
            state.ui_ctx.invalidateWindow();
        }
        for (0..self.plugin_count) |idx| {
            const p = &self.plugins[idx];
            if (!p.active or !p.enabled or !p.capabilities.background_poller) continue;
            if (p.descriptor.on_poll_io) |poll_fn| {
                self.invokeHook(state, idx, poll_fn);
            }
        }
    }

    pub fn executePluginCommand(self: *PluginManager, state: *EditorState, plugin_idx: usize, cmd_idx: usize) void {
        if (plugin_idx >= self.plugin_count) return;
        const p = &self.plugins[plugin_idx];
        if (!p.active or !p.enabled or cmd_idx >= p.command_count) return;
        const cmd_fn = p.descriptor.on_command orelse return;

        var root_scope = state.ui_ctx.scopedState("__plugins");
        defer root_scope.end();
        var plug_scope = state.ui_ctx.scopedState(p.id.slice());
        defer plug_scope.end();

        var hctx = HostCallbackCtx{
            .mgr = self,
            .state = state,
            .plugin_idx = plugin_idx,
        };
        const t0 = platform.profiler.nowNs();
        cmd_fn(&hctx, &HOST_API_V1, abi.AbiSlice.fromZig(p.commands[cmd_idx].cmd_id.slice()));
        self.plugins[plugin_idx].last_input_us = @intCast((platform.profiler.nowNs() - t0) / 1000);
        self.plugins[plugin_idx].invocations += 1;
        state.ui_ctx.invalidateWindow();
    }

    pub fn notifyBufferOpen(self: *PluginManager, state: *EditorState, file_idx: usize) void {
        const info = buildBufferInfo(state, file_idx);
        for (0..self.plugin_count) |idx| {
            const p = &self.plugins[idx];
            if (!p.active or !p.enabled or !p.capabilities.buffer_hooks) continue;
            if (p.descriptor.on_buffer_open) |open_fn| {
                var root_scope = state.ui_ctx.scopedState("__plugins");
                defer root_scope.end();
                var plug_scope = state.ui_ctx.scopedState(p.id.slice());
                defer plug_scope.end();
                var hctx = HostCallbackCtx{ .mgr = self, .state = state, .plugin_idx = idx };
                open_fn(&hctx, &HOST_API_V1, &info);
                self.plugins[idx].invocations += 1;
            }
        }
    }

    pub fn notifyBufferSave(self: *PluginManager, state: *EditorState, file_idx: usize) void {
        const info = buildBufferInfo(state, file_idx);
        for (0..self.plugin_count) |idx| {
            const p = &self.plugins[idx];
            if (!p.active or !p.enabled or !p.capabilities.buffer_hooks) continue;
            if (p.descriptor.on_buffer_save) |save_fn| {
                var root_scope = state.ui_ctx.scopedState("__plugins");
                defer root_scope.end();
                var plug_scope = state.ui_ctx.scopedState(p.id.slice());
                defer plug_scope.end();
                var hctx = HostCallbackCtx{ .mgr = self, .state = state, .plugin_idx = idx };
                save_fn(&hctx, &HOST_API_V1, &info);
                self.plugins[idx].invocations += 1;
            }
        }
    }

    pub fn notifyBufferEdit(self: *PluginManager, state: *EditorState, file_idx: usize) void {
        const is_scratch = (file_idx >= state.file_count);
        const buf = if (is_scratch) &state.scratch_buf else &state.buffers[file_idx];
        const ev = abi.BufferEditEventV1{
            .buffer_id = if (is_scratch) 0xFFFF else @intCast(file_idx),
            .start_offset = buf.cursor,
            .old_end_offset = buf.cursor,
            .new_end_offset = buf.cursor,
            .edit_version = buf.edit_version,
        };
        // Clear stale completions before plugins publish fresh candidates for the new cursor position
        self.clearCompletions();
        for (0..self.plugin_count) |idx| {
            const p = &self.plugins[idx];
            if (!p.active or !p.enabled or !p.capabilities.buffer_hooks) continue;
            if (p.descriptor.on_buffer_edit) |edit_fn| {
                var root_scope = state.ui_ctx.scopedState("__plugins");
                defer root_scope.end();
                var plug_scope = state.ui_ctx.scopedState(p.id.slice());
                defer plug_scope.end();
                var hctx = HostCallbackCtx{ .mgr = self, .state = state, .plugin_idx = idx };
                edit_fn(&hctx, &HOST_API_V1, &ev);
                self.plugins[idx].invocations += 1;
            }
        }
    }

    pub fn setPluginEnabled(self: *PluginManager, state: *EditorState, idx: usize, enabled: bool) void {
        if (idx >= self.plugin_count) return;
        var p = &self.plugins[idx];
        if (!p.active) return;
        p.enabled = enabled;
        state.setPluginEnabledInDoc(p.id.slice(), enabled);
        if (!enabled and state.doc.active_sidebar_view == @as(u8, @intCast(3 + idx))) {
            state.doc.active_sidebar_view = 2;
        }
        state.ui_ctx.invalidateWindow();
    }

    pub fn renderPluginSidebar(self: *PluginManager, state: *EditorState, idx: usize) void {
        if (idx >= self.plugin_count) return;
        const p = &self.plugins[idx];
        if (!p.active or !p.enabled or !p.capabilities.sidebar_panel) return;
        if (p.descriptor.render_sidebar) |render_fn| {
            self.invokeHook(state, idx, render_fn);
        }
    }

    pub fn renderSidebarPanels(self: *PluginManager, state: *EditorState) void {
        for (0..self.plugin_count) |idx| {
            const p = &self.plugins[idx];
            if (!p.active or !p.enabled or !p.capabilities.sidebar_panel) continue;
            if (p.descriptor.render_sidebar) |render_fn| {
                self.invokeHook(state, idx, render_fn);
            }
        }
    }

    pub fn renderBottomPanels(self: *PluginManager, state: *EditorState, height: f32) void {
        var scroll = state.ui_ctx.scrollPanel("plugin_bottom_panels_scroll", .{
            .h = .pixels(height),
            .padding = ui.Padding.xy(10, 6),
            .gap = 6,
        });
        defer scroll.end();

        for (0..self.plugin_count) |idx| {
            const p = &self.plugins[idx];
            if (!p.active or !p.enabled or !p.capabilities.bottom_panel) continue;
            if (p.descriptor.render_bottom_panel) |render_fn| {
                self.invokeHook(state, idx, render_fn);
            }
        }
    }

    pub fn renderStatusBarItems(self: *PluginManager, state: *EditorState) void {
        for (0..self.plugin_count) |idx| {
            const p = &self.plugins[idx];
            if (!p.active or !p.enabled or !p.capabilities.status_bar) continue;
            if (p.descriptor.render_status_bar) |render_fn| {
                self.invokeHook(state, idx, render_fn);
            }
        }
    }

    fn buildBufferInfo(state: *EditorState, file_idx: usize) abi.BufferInfoV1 {
        if (file_idx >= state.file_count) {
            const sb = &state.scratch_buf;
            const lc = sb.cursorLineCol();
            return .{
                .buffer_id = 0xFFFF,
                .file_path = abi.AbiSlice.fromZig("*scratch*"),
                .text = abi.AbiSlice.fromZig(sb.slice()),
                .line_count = @intCast(sb.lineCount()),
                .cursor_offset = sb.cursor,
                .selection_anchor = sb.selection_anchor,
                .cursor_line = @intCast(lc.line),
                .cursor_col = @intCast(lc.col),
                .edit_version = sb.edit_version,
                .is_dirty = state.isScratchDirty(),
            };
        }
        const wfs = state.workspaceFiles();
        const raw_f = wfs[file_idx];
        if (raw_f.is_markdown_preview and state.isScratchMarkdownPreview(file_idx)) {
            const sb = &state.scratch_buf;
            const lc = sb.cursorLineCol();
            return .{
                .buffer_id = 0xFFFF,
                .file_path = abi.AbiSlice.fromZig("*scratch*"),
                .text = abi.AbiSlice.fromZig(sb.slice()),
                .line_count = @intCast(sb.lineCount()),
                .cursor_offset = sb.cursor,
                .selection_anchor = sb.selection_anchor,
                .cursor_line = @intCast(lc.line),
                .cursor_col = @intCast(lc.col),
                .edit_version = sb.edit_version,
                .is_dirty = state.isScratchDirty(),
            };
        }
        const eff_idx_opt: ?usize = if (raw_f.is_git_diff_preview)
            state.findGitDiffPreviewSourceIndex()
        else if (raw_f.is_markdown_preview)
            state.findMarkdownPreviewSourceIndexForBuffer(file_idx)
        else if (raw_f.is_waveform_preview)
            state.findWaveformPreviewSourceIndex()
        else if (raw_f.is_pdf_preview)
            state.findPdfPreviewSourceIndex()
        else
            file_idx;

        if (eff_idx_opt) |eff_idx| {
            const f = wfs[eff_idx];
            const b = &state.buffers[eff_idx];
            const lc = b.cursorLineCol();
            return .{
                .buffer_id = @intCast(eff_idx),
                .file_path = abi.AbiSlice.fromZig(f.path),
                .text = abi.AbiSlice.fromZig(b.slice()),
                .line_count = @intCast(b.lineCount()),
                .cursor_offset = b.cursor,
                .selection_anchor = b.selection_anchor,
                .cursor_line = @intCast(lc.line),
                .cursor_col = @intCast(lc.col),
                .edit_version = b.edit_version,
                .is_dirty = state.isFileDirty(eff_idx),
            };
        }

        const sb = &state.scratch_buf;
        const lc = sb.cursorLineCol();
        return .{
            .buffer_id = 0xFFFF,
            .file_path = abi.AbiSlice.fromZig("*scratch*"),
            .text = abi.AbiSlice.fromZig(sb.slice()),
            .line_count = @intCast(sb.lineCount()),
            .cursor_offset = sb.cursor,
            .selection_anchor = sb.selection_anchor,
            .cursor_line = @intCast(lc.line),
            .cursor_col = @intCast(lc.col),
            .edit_version = sb.edit_version,
            .is_dirty = state.isScratchDirty(),
        };
    }
};

// ============================================================================
// C-ABI Host VTable Implementation (`HOST_API_V1` & `UI_API_V1`)
// ============================================================================

fn hostFrameAlloc(host_opaque: *anyopaque, size: usize, alignment_log2: u8) callconv(.c) ?[*]u8 {
    const hctx: *HostCallbackCtx = @ptrCast(@alignCast(host_opaque));
    const align_enum: std.mem.Alignment = @enumFromInt(@min(alignment_log2, 4));
    return hctx.state.ui_ctx.arena.rawAlloc(size, align_enum, @returnAddress());
}

fn hostUseStateRaw(
    host_opaque: *anyopaque,
    key: abi.AbiSlice,
    size: usize,
    alignment_log2: u8,
    type_hash: u64,
    initialized_out: *bool,
) callconv(.c) [*]u8 {
    const hctx: *HostCallbackCtx = @ptrCast(@alignCast(host_opaque));
    var p = &hctx.mgr.plugins[hctx.plugin_idx];
    if (hctx.state.ui_ctx.platform_ctx) |pctx| {
        if (pctx.state_store) |store_opaque| {
            const store: *platform.StateStore = @ptrCast(@alignCast(store_opaque));
            const saved_scope_len = store.scope_len;
            store.scope_len = 0;
            defer store.scope_len = saved_scope_len;
            store.pushScope("__plugins");
            store.pushScope(p.id.slice());
            const k = key.toZig();
            return store.getOrAllocRaw(if (k.len > 0) k else "default", size, alignment_log2, type_hash, initialized_out);
        }
    }
    std.debug.assert(size <= p.fallback_state_buf.len);
    if (!p.fallback_state_init or p.fallback_state_hash != type_hash) {
        @memset(&p.fallback_state_buf, 0);
        p.fallback_state_hash = type_hash;
        p.fallback_state_init = true;
        initialized_out.* = false;
    } else {
        initialized_out.* = true;
    }
    return &p.fallback_state_buf;
}

fn hostGetActiveBuffer(host_opaque: *anyopaque, out: *abi.BufferInfoV1) callconv(.c) bool {
    const hctx: *HostCallbackCtx = @ptrCast(@alignCast(host_opaque));
    const file_idx = hctx.state.activeFileIndex() orelse 0xFFFF;
    out.* = PluginManager.buildBufferInfo(hctx.state, file_idx);
    return true;
}

fn hostGetLineRange(host_opaque: *anyopaque, buffer_id: u32, line_idx: u32) callconv(.c) abi.LineRangeV1 {
    const hctx: *HostCallbackCtx = @ptrCast(@alignCast(host_opaque));
    const buf = if (buffer_id < hctx.state.file_count) &hctx.state.buffers[buffer_id] else &hctx.state.scratch_buf;
    const lr = buf.lineRangeByIndex(line_idx);
    return .{ .start = lr.start, .end = lr.end };
}

fn hostOffsetToLineCol(host_opaque: *anyopaque, buffer_id: u32, offset: usize, line_out: *u32, col_out: *u32) callconv(.c) void {
    const hctx: *HostCallbackCtx = @ptrCast(@alignCast(host_opaque));
    const buf = if (buffer_id < hctx.state.file_count) &hctx.state.buffers[buffer_id] else &hctx.state.scratch_buf;
    const lc = buf.offsetToLineCol(offset);
    line_out.* = @intCast(lc.line);
    col_out.* = @intCast(lc.col);
}

fn hostReplaceBufferRange(host_opaque: *anyopaque, buffer_id: u32, start: usize, end: usize, new_text: abi.AbiSlice) callconv(.c) bool {
    const hctx: *HostCallbackCtx = @ptrCast(@alignCast(host_opaque));
    const buf = if (buffer_id < hctx.state.file_count) &hctx.state.buffers[buffer_id] else &hctx.state.scratch_buf;
    buf.saveUndoCheckpoint();
    const ok = buf.replaceRange(start, end, new_text.toZig());
    if (ok) {
        hctx.state.ui_ctx.invalidateWindow();
    }
    return ok;
}

fn hostSetCursorAndScroll(host_opaque: *anyopaque, buffer_id: u32, cursor: usize, anchor: usize) callconv(.c) void {
    const hctx: *HostCallbackCtx = @ptrCast(@alignCast(host_opaque));
    const buf = if (buffer_id < hctx.state.file_count) &hctx.state.buffers[buffer_id] else &hctx.state.scratch_buf;
    buf.cursor = @min(cursor, buf.len);
    buf.selection_anchor = @min(anchor, buf.len);
    buf.scroll_to_cursor_pending = true;
    buf.scroll_align_top = true;
    hctx.state.ui_ctx.invalidateWindow();
}

fn hostRegisterCommand(
    host_opaque: *anyopaque,
    cmd_id: abi.AbiSlice,
    title: abi.AbiSlice,
    category: abi.AbiSlice,
    shortcut_hint: abi.AbiSlice,
) callconv(.c) bool {
    const hctx: *HostCallbackCtx = @ptrCast(@alignCast(host_opaque));
    var p = &hctx.mgr.plugins[hctx.plugin_idx];
    const cid = cmd_id.toZig();
    for (0..p.command_count) |i| {
        if (std.mem.eql(u8, p.commands[i].cmd_id.slice(), cid)) {
            p.commands[i].title.set(title.toZig());
            p.commands[i].category.set(category.toZig());
            p.commands[i].shortcut_hint.set(shortcut_hint.toZig());
            return true;
        }
    }
    if (p.command_count >= MaxCommandsPerPlugin) return false;
    var entry = &p.commands[p.command_count];
    entry.cmd_id.set(cid);
    entry.title.set(title.toZig());
    entry.category.set(if (category.len > 0) category.toZig() else "Plugin");
    entry.shortcut_hint.set(shortcut_hint.toZig());
    p.command_count += 1;
    return true;
}

fn hostSetCompletions(
    host_opaque: *anyopaque,
    buffer_id: u32,
    cursor_offset: usize,
    items_ptr: ?[*]const abi.CompletionItemV1,
    item_count: usize,
) callconv(.c) void {
    const hctx: *HostCallbackCtx = @ptrCast(@alignCast(host_opaque));
    var mgr = hctx.mgr;
    if (items_ptr == null or item_count == 0) {
        if (mgr.completion_buffer_id == buffer_id) {
            mgr.clearCompletions();
        }
        return;
    }
    const items = items_ptr.?[0..@min(item_count, MaxPluginCompletions)];
    mgr.completion_buffer_id = buffer_id;
    mgr.completion_cursor_offset = cursor_offset;
    mgr.completion_count = items.len;
    mgr.selected_completion = 0;
    for (items, 0..) |it, idx| {
        mgr.completions[idx] = .{
            .kind = it.kind,
            .replace_prefix_len = it.replace_prefix_len,
        };
        mgr.completions[idx].label.set(it.label.toZig());
        mgr.completions[idx].detail.set(it.detail.toZig());
        mgr.completions[idx].insert_text.set(if (it.insert_text.len > 0) it.insert_text.toZig() else it.label.toZig());
    }
    hctx.state.ui_ctx.invalidateWindow();
}

fn hostSetStatusNotice(host_opaque: *anyopaque, msg: abi.AbiSlice) callconv(.c) void {
    const hctx: *HostCallbackCtx = @ptrCast(@alignCast(host_opaque));
    const s = msg.toZig();
    hctx.state.status_notice.set(s);
    if (s.len > 0) {
        const channel = if (hctx.plugin_idx < hctx.mgr.plugin_count)
            hctx.mgr.plugins[hctx.plugin_idx].display_name.slice()
        else
            "Plugin";
        hctx.state.appendOutput(channel, s);
    }
    hctx.state.ui_ctx.invalidateWindow();
}

fn hostRequestContinuousRedraw(host_opaque: *anyopaque) callconv(.c) void {
    const hctx: *HostCallbackCtx = @ptrCast(@alignCast(host_opaque));
    if (hctx.state.ui_ctx.platform_ctx) |pctx| {
        pctx.needs_continuous_redraw = true;
    }
}

fn hostOpenWaveformPreview(host_opaque: *anyopaque, vcd_source: abi.AbiSlice, split_to_side: bool) callconv(.c) void {
    const hctx: *HostCallbackCtx = @ptrCast(@alignCast(host_opaque));
    hctx.state.openWaveformPreviewWithSource(vcd_source.toZig(), split_to_side);
}

fn hostOpenPdfPreview(host_opaque: *anyopaque, file_path: abi.AbiSlice, raw_bytes: abi.AbiSlice, split_to_side: bool) callconv(.c) void {
    const hctx: *HostCallbackCtx = @ptrCast(@alignCast(host_opaque));
    hctx.state.openPdfPreviewWithSource(file_path.toZig(), raw_bytes.toZig(), split_to_side);
}

fn hostOpenGitDiff(
    host_opaque: *anyopaque,
    file_path: abi.AbiSlice,
    commit_sha: abi.AbiSlice,
    staged: bool,
    split_to_side: bool,
) callconv(.c) void {
    const hctx: *HostCallbackCtx = @ptrCast(@alignCast(host_opaque));
    hctx.state.openGitDiffForFile(file_path.toZig(), commit_sha.toZig(), staged, split_to_side);
}

fn hostOpenFilePath(host_opaque: *anyopaque, path: abi.AbiSlice) callconv(.c) bool {
    const hctx: *HostCallbackCtx = @ptrCast(@alignCast(host_opaque));
    const p = path.toZig();
    if (p.len == 0) return false;
    if (std.mem.eql(u8, p, "*open_workspace*")) {
        hctx.state.openWorkspacePrompt();
        return true;
    }
    return hctx.state.openLinkOrFileUrl(p);
}

fn hostSyncWorkspaceGit(host_opaque: *anyopaque, save_dirty: bool, reload_from_disk: bool) callconv(.c) void {
    const hctx: *HostCallbackCtx = @ptrCast(@alignCast(host_opaque));
    if (save_dirty) {
        _ = hctx.state.saveAllDirtyFiles();
    }
    if (reload_from_disk) {
        _ = hctx.state.reloadModifiedOpenFiles();
    }
    hctx.state.refreshGitStatus();
    hctx.state.refreshActiveGitDiffContent();
    hctx.state.ui_ctx.invalidateWindow();
}

fn hostGetGitStatus(host_opaque: *anyopaque, out: *abi.GitStatusSnapshotV1) callconv(.c) bool {
    const hctx: *HostCallbackCtx = @ptrCast(@alignCast(host_opaque));
    const state = hctx.state;
    const allocator = state.frame_arena.allocator();

    const wfs = state.workspaceFiles();
    var entry_count: usize = 0;
    for (wfs, 0..) |*wf, idx| {
        if (wf.isSpecial()) continue;
        if (idx < state.git_file_statuses.len) {
            const fs = state.git_file_statuses[idx];
            if (fs.staged) entry_count += 1;
            if (fs.unstaged or fs.untracked) entry_count += 1;
        }
    }

    var files_slice: []abi.GitFileStatusV1 = &.{};
    if (entry_count > 0) {
        files_slice = allocator.alloc(abi.GitFileStatusV1, entry_count) catch return false;
        var out_idx: usize = 0;
        for (wfs, 0..) |*wf, idx| {
            if (wf.isSpecial()) continue;
            if (idx < state.git_file_statuses.len) {
                const fs = state.git_file_statuses[idx];
                if (fs.staged) {
                    files_slice[out_idx] = .{
                        .path = abi.AbiSlice.fromZig(wf.path),
                        .status = if (fs.staged_char != ' ' and fs.staged_char != 0) fs.staged_char else 'M',
                        .staged = true,
                        .unstaged = false,
                        .untracked = false,
                    };
                    out_idx += 1;
                }
                if (fs.unstaged or fs.untracked) {
                    const st_char: u8 = if (fs.untracked)
                        '?'
                    else if (fs.unstaged_char != ' ' and fs.unstaged_char != 0)
                        fs.unstaged_char
                    else
                        'M';
                    files_slice[out_idx] = .{
                        .path = abi.AbiSlice.fromZig(wf.path),
                        .status = st_char,
                        .staged = false,
                        .unstaged = fs.unstaged,
                        .untracked = fs.untracked,
                    };
                    out_idx += 1;
                }
            }
        }
    }

    var commits_slice: []abi.GitCommitV1 = &.{};
    if (state.git_commit_count > 0) {
        commits_slice = allocator.alloc(abi.GitCommitV1, state.git_commit_count) catch return false;
        for (0..state.git_commit_count) |i| {
            const c = &state.git_commits[i];
            var c_files: []abi.GitFileStatusV1 = &.{};
            if (c.file_count > 0) {
                c_files = allocator.alloc(abi.GitFileStatusV1, c.file_count) catch return false;
                for (0..c.file_count) |f_i| {
                    const st_char = c.file_statuses[f_i];
                    c_files[f_i] = .{
                        .path = abi.AbiSlice.fromZig(c.files[f_i].slice()),
                        .status = st_char,
                        .staged = false,
                        .unstaged = true,
                        .untracked = (st_char == '?'),
                    };
                }
            }
            commits_slice[i] = .{
                .hash = abi.AbiSlice.fromZig(c.hash()),
                .subject = abi.AbiSlice.fromZig(c.subject()),
                .rel_time = abi.AbiSlice.fromZig(c.relTime()),
                .files_changed = c.files_changed,
                .files_ptr = if (c_files.len > 0) c_files.ptr else null,
                .file_count = c_files.len,
            };
        }
    }

    out.* = .{
        .branch = abi.AbiSlice.fromZig(state.git_branch.slice()),
        .is_busy = state.git_poller.isBusy(),
        .files_ptr = if (files_slice.len > 0) files_slice.ptr else null,
        .file_count = files_slice.len,
        .commits_ptr = if (commits_slice.len > 0) commits_slice.ptr else null,
        .commit_count = commits_slice.len,
    };
    return true;
}

fn hostGitAction(host_opaque: *anyopaque, action: abi.GitActionV1, path_or_msg: abi.AbiSlice) callconv(.c) bool {
    const hctx: *HostCallbackCtx = @ptrCast(@alignCast(host_opaque));
    const state = hctx.state;
    const arg = path_or_msg.toZig();

    switch (action) {
        .stage_path => {
            if (arg.len == 0) return false;
            git_client.stagePath(arg);
            state.refreshGitStatusSync();
            state.ui_ctx.invalidateWindow();
            return true;
        },
        .unstage_path => {
            if (arg.len == 0) return false;
            git_client.unstagePath(arg);
            state.refreshGitStatusSync();
            state.ui_ctx.invalidateWindow();
            return true;
        },
        .stage_all => {
            git_client.stageAll();
            state.refreshGitStatusSync();
            state.ui_ctx.invalidateWindow();
            return true;
        },
        .unstage_all => {
            git_client.unstageAll();
            state.refreshGitStatusSync();
            state.ui_ctx.invalidateWindow();
            return true;
        },
        .discard_path => {
            if (arg.len == 0) return false;
            git_client.discardPath(arg);
            state.refreshGitStatusSync();
            state.ui_ctx.invalidateWindow();
            return true;
        },
        .commit => {
            if (arg.len == 0) return false;
            for (0..state.fileCount()) |idx| {
                if (state.isFileStaged(idx) and state.isFileDirty(idx)) {
                    _ = state.saveFileToDisk(idx);
                    git_client.stagePath(state.workspaceFiles()[idx].path);
                }
            }
            git_client.commitWithMessage(arg) catch return false;
            state.refreshGitStatusSync();
            state.refreshActiveGitDiffContent();
            state.ui_ctx.invalidateWindow();
            return true;
        },
        .refresh => {
            state.refreshGitStatusSync();
            state.ui_ctx.invalidateWindow();
            return true;
        },
    }
}

fn hostRunTerminalCommand(host_opaque: *anyopaque, cmd: abi.AbiSlice) callconv(.c) void {
    const hctx: *HostCallbackCtx = @ptrCast(@alignCast(host_opaque));
    const c = cmd.toZig();
    if (c.len == 0) return;
    hctx.state.doc.show_bottom_panel = true;
    hctx.state.vterm.writeInput(c);
    hctx.state.vterm.writeInput("\n");
    hctx.state.ui_ctx.invalidateWindow();
}

fn hostToggleBottomPanel(host_opaque: *anyopaque) callconv(.c) void {
    const hctx: *HostCallbackCtx = @ptrCast(@alignCast(host_opaque));
    hctx.state.doc.show_bottom_panel = !hctx.state.doc.show_bottom_panel;
    hctx.state.ui_ctx.invalidateWindow();
}

fn hostToggleBreakpoint(host_opaque: *anyopaque, file_path: abi.AbiSlice, line_1based: u32) callconv(.c) bool {
    const hctx: *HostCallbackCtx = @ptrCast(@alignCast(host_opaque));
    const raw_path = file_path.toZig();
    const effective_path = if (raw_path.len > 0) raw_path else blk: {
        if (hctx.state.activeFileIndex()) |f_idx| {
            break :blk hctx.state.workspaceFiles()[f_idx].path;
        }
        break :blk "*scratch*";
    };
    const added = hctx.mgr.toggleBreakpoint(effective_path, line_1based);
    hctx.state.ui_ctx.invalidateWindow();
    return added;
}

fn hostClearBreakpoints(host_opaque: *anyopaque) callconv(.c) void {
    const hctx: *HostCallbackCtx = @ptrCast(@alignCast(host_opaque));
    hctx.mgr.clearBreakpoints();
    hctx.state.ui_ctx.invalidateWindow();
}

fn hostGetBreakpoints(host_opaque: *anyopaque, out_ptr: ?[*]abi.BreakpointV1, max_count: usize) callconv(.c) usize {
    const hctx: *HostCallbackCtx = @ptrCast(@alignCast(host_opaque));
    const n = @min(hctx.mgr.breakpoint_count, max_count);
    if (out_ptr) |out| {
        for (0..n) |i| {
            const bp = &hctx.mgr.breakpoints[i];
            out[i] = .{
                .file_path = abi.AbiSlice.fromZig(bp.file_path.slice()),
                .line = bp.line,
                .enabled = bp.enabled,
                .hit_count = bp.hit_count,
            };
        }
    }
    return hctx.mgr.breakpoint_count;
}

fn hostSetDebugLocation(
    host_opaque: *anyopaque,
    active: bool,
    paused: bool,
    file_path: abi.AbiSlice,
    line_1based: u32,
    jump_to_line: bool,
) callconv(.c) void {
    const hctx: *HostCallbackCtx = @ptrCast(@alignCast(host_opaque));
    const path = file_path.toZig();
    hctx.mgr.debug_active = active;
    hctx.mgr.debug_paused = paused;
    hctx.mgr.debug_file_path.set(path);
    hctx.mgr.debug_line = if (active and paused) line_1based else 0;

    if (jump_to_line and active and paused and line_1based > 0) {
        if (path.len > 0 and !std.mem.eql(u8, path, "*scratch*")) {
            const wfs = hctx.state.workspaceFiles();
            for (wfs, 0..) |wf, idx| {
                if (PluginManager.pathsMatch(wf.path, path)) {
                    hctx.state.openFile(idx);
                    hctx.state.buffers[idx].jumpToLine(line_1based);
                    hctx.state.doc.cursor_line = line_1based;
                    break;
                }
            }
        } else if (hctx.state.activeFileIndex()) |f_idx| {
            hctx.state.buffers[f_idx].jumpToLine(line_1based);
            hctx.state.doc.cursor_line = line_1based;
        } else {
            hctx.state.scratch_buf.jumpToLine(line_1based);
            hctx.state.doc.cursor_line = line_1based;
        }
    }
    hctx.state.ui_ctx.invalidateWindow();
}

fn uiGetPass(host_opaque: *anyopaque) callconv(.c) u8 {
    const hctx: *HostCallbackCtx = @ptrCast(@alignCast(host_opaque));
    return if (hctx.state.ui_ctx.pass == .input) 0 else 1;
}

fn uiBeginColumn(host_opaque: *anyopaque, w: f32, h: f32, pad: f32, gap: f32) callconv(.c) void {
    const hctx: *HostCallbackCtx = @ptrCast(@alignCast(host_opaque));
    _ = hctx.state.ui_ctx.beginBox(w, h, .{
        .direction = .column,
        .padding = ui.Padding.all(pad),
        .gap = gap,
    });
}

fn uiBeginRow(host_opaque: *anyopaque, w: f32, h: f32, pad: f32, gap: f32) callconv(.c) void {
    const hctx: *HostCallbackCtx = @ptrCast(@alignCast(host_opaque));
    _ = hctx.state.ui_ctx.beginBox(w, h, .{
        .direction = .row,
        .padding = ui.Padding.all(pad),
        .gap = gap,
    });
}

fn uiEndBox(host_opaque: *anyopaque) callconv(.c) void {
    const hctx: *HostCallbackCtx = @ptrCast(@alignCast(host_opaque));
    hctx.state.ui_ctx.endBox();
}

fn uiBeginScrollPanel(host_opaque: *anyopaque, id: abi.AbiSlice, w: f32, h: f32, pad: f32, gap: f32) callconv(.c) void {
    const hctx: *HostCallbackCtx = @ptrCast(@alignCast(host_opaque));
    _ = hctx.state.ui_ctx.beginScrollBox(id.toZig(), w, h, .{
        .direction = .column,
        .padding = ui.Padding.all(pad),
        .gap = gap,
    });
}

fn uiEndScrollPanel(host_opaque: *anyopaque) callconv(.c) void {
    const hctx: *HostCallbackCtx = @ptrCast(@alignCast(host_opaque));
    hctx.state.ui_ctx.endScrollBox();
}

fn uiSpacer(host_opaque: *anyopaque, w: f32, h: f32) callconv(.c) void {
    const hctx: *HostCallbackCtx = @ptrCast(@alignCast(host_opaque));
    _ = w;
    hctx.state.ui_ctx.spacer(h);
}

fn uiDivider(host_opaque: *anyopaque) callconv(.c) void {
    const hctx: *HostCallbackCtx = @ptrCast(@alignCast(host_opaque));
    hctx.state.ui_ctx.divider();
}

fn uiPushId(host_opaque: *anyopaque, id: abi.AbiSlice) callconv(.c) void {
    const hctx: *HostCallbackCtx = @ptrCast(@alignCast(host_opaque));
    hctx.state.ui_ctx.pushId(id.toZig());
}

fn uiPopId(host_opaque: *anyopaque) callconv(.c) void {
    const hctx: *HostCallbackCtx = @ptrCast(@alignCast(host_opaque));
    hctx.state.ui_ctx.popId();
}

fn uiLabel(host_opaque: *anyopaque, text: abi.AbiSlice, style: u8) callconv(.c) void {
    const hctx: *HostCallbackCtx = @ptrCast(@alignCast(host_opaque));
    const uic = &hctx.state.ui_ctx;
    const s = text.toZig();
    switch (style) {
        0 => uic.label(s, uic.theme.text_primary),
        1 => uic.label(s, null),
        2 => uic.monoLabel(s, null),
        3 => uic.sectionHeader(s),
        else => uic.label(s, null),
    }
}

fn uiButton(host_opaque: *anyopaque, label: abi.AbiSlice, w: f32, h: f32) callconv(.c) bool {
    const hctx: *HostCallbackCtx = @ptrCast(@alignCast(host_opaque));
    const lbl = label.toZig();
    const is_toolbar = (w > 0 and w <= 104.0);

    var icon_opt: ?ui.Icon = null;
    var icon_col: ?u32 = null;
    if (ui.containsIgnoreCase(lbl, "Launch") or ui.containsIgnoreCase(lbl, "Continue") or ui.containsIgnoreCase(lbl, "Run")) {
        icon_opt = .play;
        icon_col = skia.Color.rgb(52, 211, 153);
    } else if (ui.containsIgnoreCase(lbl, "Step Over") or ui.containsIgnoreCase(lbl, "Next")) {
        icon_opt = .step_over;
        icon_col = skia.Color.rgb(56, 189, 248);
    } else if (ui.containsIgnoreCase(lbl, "Step Into") or ui.containsIgnoreCase(lbl, "Step")) {
        icon_opt = .step_into;
        icon_col = skia.Color.rgb(56, 189, 248);
    } else if (ui.containsIgnoreCase(lbl, "Step Out")) {
        icon_opt = .step_out;
        icon_col = skia.Color.rgb(56, 189, 248);
    } else if (ui.containsIgnoreCase(lbl, "Breakpoint") or ui.containsIgnoreCase(lbl, "Break")) {
        icon_opt = .breakpoint;
        icon_col = skia.Color.rgb(248, 81, 73);
    } else if (ui.containsIgnoreCase(lbl, "Waveform")) {
        icon_opt = .waveform;
        icon_col = skia.Color.rgb(168, 85, 247);
    } else if (ui.containsIgnoreCase(lbl, "PDF") or ui.containsIgnoreCase(lbl, "Datasheet")) {
        icon_opt = .pdf;
        icon_col = skia.Color.rgb(244, 63, 94);
    } else if (ui.containsIgnoreCase(lbl, "Estimate") or ui.containsIgnoreCase(lbl, "Format") or ui.containsIgnoreCase(lbl, "Decode")) {
        icon_opt = .bolt;
        icon_col = skia.Color.rgb(251, 191, 36);
    } else if (ui.containsIgnoreCase(lbl, "Swap") or ui.containsIgnoreCase(lbl, "Reload")) {
        icon_opt = .refresh;
        icon_col = skia.Color.rgb(129, 140, 248);
    }

    return hctx.state.ui_ctx.btn(lbl, .{
        .w = if (w <= 0) .fill else .pixels(w),
        .h = if (h <= 0) 28.0 else h,
        .variant = if (is_toolbar) .toolbar else .secondary,
        .icon = icon_opt,
        .icon_color = icon_col,
    });
}

fn uiToolbarIconBtn(
    host_opaque: *anyopaque,
    label: abi.AbiSlice,
    icon: abi.PluginToolbarIcon,
    w: f32,
    h: f32,
    enabled: bool,
) callconv(.c) bool {
    const hctx: *HostCallbackCtx = @ptrCast(@alignCast(host_opaque));
    const ui_icon: ui.Icon = switch (icon) {
        .play => .play_outline,
        .pause => .pause,
        .step_over => .step_over,
        .step_into => .step_into,
        .step_out => .step_out,
        .restart => .restart,
        .stop => .stop,
        .gear => .gear,
        .debug_console => .debug_console,
        .breakpoint => .breakpoint,
    };
    const color_override: ?u32 = switch (icon) {
        .play => skia.Color.rgb(74, 222, 128), // Classic green outlined play button
        .breakpoint => skia.Color.rgb(248, 81, 73),
        else => null,
    };
    return hctx.state.ui_ctx.toolbarIconBtn(
        label.toZig(),
        ui_icon,
        if (w <= 0) 26.0 else w,
        if (h <= 0) 24.0 else h,
        enabled,
        color_override,
    );
}

fn uiDropdownSelect(
    host_opaque: *anyopaque,
    label: abi.AbiSlice,
    display_text: abi.AbiSlice,
    w: f32,
    h: f32,
    active_border: bool,
) callconv(.c) bool {
    const hctx: *HostCallbackCtx = @ptrCast(@alignCast(host_opaque));
    return hctx.state.ui_ctx.dropdownSelect(
        label.toZig(),
        display_text.toZig(),
        w,
        if (h <= 0) 24.0 else h,
        active_border,
    );
}

fn uiReserveDropdownOverlay(host_opaque: *anyopaque, height: f32) callconv(.c) bool {
    const hctx: *HostCallbackCtx = @ptrCast(@alignCast(host_opaque));
    return hctx.state.ui_ctx.reserveDropdownOverlay(height);
}

fn uiBeginDropdownOverlay(host_opaque: *anyopaque) callconv(.c) void {
    const hctx: *HostCallbackCtx = @ptrCast(@alignCast(host_opaque));
    _ = hctx.state.ui_ctx.beginDropdownOverlay();
}

fn uiEndDropdownOverlay(host_opaque: *anyopaque) callconv(.c) void {
    const hctx: *HostCallbackCtx = @ptrCast(@alignCast(host_opaque));
    hctx.state.ui_ctx.endDropdownOverlay();
}

fn uiCollapsibleSection(
    host_opaque: *anyopaque,
    label: abi.AbiSlice,
    expanded: *bool,
    badge_text: abi.AbiSlice,
) callconv(.c) bool {
    const hctx: *HostCallbackCtx = @ptrCast(@alignCast(host_opaque));
    return hctx.state.ui_ctx.collapsibleSection(label.toZig(), expanded, badge_text.toZig());
}

fn uiCollapsibleSectionWithAction(
    host_opaque: *anyopaque,
    label: abi.AbiSlice,
    expanded: *bool,
    badge_text: abi.AbiSlice,
    action_label: abi.AbiSlice,
) callconv(.c) u8 {
    const hctx: *HostCallbackCtx = @ptrCast(@alignCast(host_opaque));
    const res = hctx.state.ui_ctx.collapsibleSectionWithAction(
        label.toZig(),
        expanded,
        badge_text.toZig(),
        action_label.toZig(),
    );
    const flags = abi.SectionHeaderResultFlags{
        .expanded = res.expanded,
        .action_clicked = res.action_clicked,
        .right_clicked = res.right_clicked,
    };
    return @bitCast(flags);
}

fn uiTreeFolderNode(
    host_opaque: *anyopaque,
    label: abi.AbiSlice,
    indent_level: u8,
    expanded: *bool,
    meta: abi.AbiSlice,
) callconv(.c) bool {
    const hctx: *HostCallbackCtx = @ptrCast(@alignCast(host_opaque));
    return hctx.state.ui_ctx.treeFolderNode(label.toZig(), indent_level, expanded, meta.toZig());
}

fn uiChip(host_opaque: *anyopaque, label: abi.AbiSlice, active: bool) callconv(.c) bool {
    const hctx: *HostCallbackCtx = @ptrCast(@alignCast(host_opaque));
    return hctx.state.ui_ctx.chip(label.toZig(), .{
        .active = active,
        .bordered = true,
        .mono = true,
    });
}

fn uiListItem(host_opaque: *anyopaque, label: abi.AbiSlice, meta: abi.AbiSlice, selected: bool) callconv(.c) bool {
    const hctx: *HostCallbackCtx = @ptrCast(@alignCast(host_opaque));
    return hctx.state.ui_ctx.listItemEx(.{
        .label = label.toZig(),
        .meta = meta.toZig(),
        .selected = selected,
    }).clicked;
}

fn uiListItemEx(
    host_opaque: *anyopaque,
    label: abi.AbiSlice,
    meta: abi.AbiSlice,
    icon_text: abi.AbiSlice,
    action_label: abi.AbiSlice,
    secondary_action_label: abi.AbiSlice,
    indent_level: u8,
    selected: bool,
    accent_kind: u8,
) callconv(.c) u8 {
    const hctx: *HostCallbackCtx = @ptrCast(@alignCast(host_opaque));
    const accent_color: ?u32 = switch (accent_kind) {
        1 => skia.Color.rgb(52, 211, 153),
        2 => skia.Color.rgb(251, 191, 36),
        3 => skia.Color.rgb(56, 189, 248),
        else => null,
    };
    const res = hctx.state.ui_ctx.listItemEx(.{
        .label = label.toZig(),
        .meta = meta.toZig(),
        .meta_color = accent_color,
        .icon_text = icon_text.toZig(),
        .icon_color = accent_color,
        .action_label = action_label.toZig(),
        .secondary_action_label = secondary_action_label.toZig(),
        .indent_level = indent_level,
        .selected = selected,
        .height = 23.0,
    });
    const flags = abi.ListItemResultFlags{
        .clicked = res.clicked,
        .action_clicked = res.action_clicked,
        .secondary_action_clicked = res.secondary_action_clicked,
        .right_clicked = res.right_clicked,
    };
    return @bitCast(flags);
}

fn uiTextField(
    host_opaque: *anyopaque,
    id: abi.AbiSlice,
    buf_ptr: [*]u8,
    len_ptr: *usize,
    cap: usize,
    placeholder: abi.AbiSlice,
) callconv(.c) u8 {
    const hctx: *HostCallbackCtx = @ptrCast(@alignCast(host_opaque));
    const res = hctx.state.ui_ctx.textFieldEx(
        id.toZig(),
        buf_ptr[0..cap],
        len_ptr,
        placeholder.toZig(),
        .{},
    );
    const flags = abi.TextFieldResultFlags{
        .changed = res.changed,
        .submitted = res.submitted,
        .escaped = res.escaped,
        .focused = res.focused,
    };
    return @bitCast(flags);
}

fn uiTextArea(
    host_opaque: *anyopaque,
    id: abi.AbiSlice,
    buf_ptr: [*]u8,
    len_ptr: *usize,
    cap: usize,
    placeholder: abi.AbiSlice,
    height: f32,
) callconv(.c) u8 {
    const hctx: *HostCallbackCtx = @ptrCast(@alignCast(host_opaque));
    const res = hctx.state.ui_ctx.textArea(
        id.toZig(),
        buf_ptr[0..cap],
        len_ptr,
        placeholder.toZig(),
        .fill,
        if (height <= 0) 64.0 else height,
    );
    const flags = abi.TextFieldResultFlags{
        .changed = res.changed,
        .submitted = res.submitted,
        .escaped = res.escaped,
        .focused = res.focused,
    };
    return @bitCast(flags);
}

fn uiMarkdown(host_opaque: *anyopaque, source: abi.AbiSlice) callconv(.c) void {
    const hctx: *HostCallbackCtx = @ptrCast(@alignCast(host_opaque));
    hctx.state.ui_ctx.markdown(source.toZig());
}

fn uiWaveformView(host_opaque: *anyopaque, id: abi.AbiSlice, vcd_source: abi.AbiSlice, height: f32) callconv(.c) void {
    const hctx: *HostCallbackCtx = @ptrCast(@alignCast(host_opaque));
    const state = hctx.state;
    const raw_src = vcd_source.toZig();
    const effective_src = if (raw_src.len > 0) raw_src else blk: {
        if (state.activeFileIndex()) |f_idx| {
            const wf = state.workspaceFiles()[f_idx];
            const buf_slice = state.buffers[f_idx].slice();
            if (std.mem.endsWith(u8, wf.path, ".vcd") or
                (std.mem.indexOfPos(u8, buf_slice, 0, "$var") != null and
                    std.mem.indexOfPos(u8, buf_slice, 0, "$enddefinitions") != null))
            {
                break :blk buf_slice;
            }
        }
        break :blk ui.SAMPLE_COUNTER_VCD;
    };
    const wave_data = state.ui_ctx.parseVcdCached(effective_src);
    const id_str = id.toZig();
    const view_state = if (state.ui_ctx.platform_ctx) |pctx|
        pctx.useState(ui.WaveformViewState, id_str, .{})
    else
        &state.ui_ctx.fallback_waveform_state;
    state.ui_ctx.waveformViewer(id_str, 0.0, if (height <= 0) 200.0 else height, wave_data, view_state);
}

fn uiPdfView(host_opaque: *anyopaque, id: abi.AbiSlice, file_path: abi.AbiSlice, raw_bytes: abi.AbiSlice, height: f32) callconv(.c) void {
    const hctx: *HostCallbackCtx = @ptrCast(@alignCast(host_opaque));
    const state = hctx.state;
    const req_path = file_path.toZig();
    const req_bytes = raw_bytes.toZig();

    var eff_path: []const u8 = req_path;
    var eff_bytes: []const u8 = req_bytes;

    if (eff_path.len == 0 and eff_bytes.len == 0) {
        if (state.activeFileIndex()) |f_idx| {
            const wf = state.workspaceFiles()[f_idx];
            const buf_slice = state.buffers[f_idx].slice();
            if (EditorState.isPdfCandidatePath(wf.path) or std.mem.startsWith(u8, buf_slice, "%PDF-")) {
                eff_path = wf.path;
                eff_bytes = buf_slice;
            }
        }
    }
    if (eff_path.len == 0 and eff_bytes.len == 0) {
        if (state.pdf_custom_path.len > 0) eff_path = state.pdf_custom_path.slice();
        if (state.pdf_custom_bytes.len > 0) eff_bytes = state.pdf_custom_bytes.slice();
    }
    if (eff_bytes.len == 0) {
        eff_bytes = ui.SAMPLE_PDF_DOC;
    }

    var pdf_doc = ui.PdfDocumentData{};
    ui.parsePdfDocument(eff_bytes, eff_path, &pdf_doc);

    const id_str = id.toZig();
    const view_state = if (state.ui_ctx.platform_ctx) |pctx|
        pctx.useState(ui.PdfViewState, id_str, .{})
    else
        &state.ui_ctx.fallback_pdf_state;
    _ = state.ui_ctx.pdfViewer(id_str, 0.0, if (height <= 0) 240.0 else height, &pdf_doc, view_state, .{
        .file_path = eff_path,
        .raw_bytes = eff_bytes,
        .compact = (height > 0 and height < 280.0),
    });
}

pub const UI_API_V1 = abi.PluginUiApiV1{
    .get_pass = &uiGetPass,
    .begin_column = &uiBeginColumn,
    .begin_row = &uiBeginRow,
    .end_box = &uiEndBox,
    .begin_scroll_panel = &uiBeginScrollPanel,
    .end_scroll_panel = &uiEndScrollPanel,
    .spacer = &uiSpacer,
    .divider = &uiDivider,
    .push_id = &uiPushId,
    .pop_id = &uiPopId,
    .label = &uiLabel,
    .button = &uiButton,
    .toolbar_icon_btn = &uiToolbarIconBtn,
    .dropdown_select = &uiDropdownSelect,
    .reserve_dropdown_overlay = &uiReserveDropdownOverlay,
    .begin_dropdown_overlay = &uiBeginDropdownOverlay,
    .end_dropdown_overlay = &uiEndDropdownOverlay,
    .collapsible_section = &uiCollapsibleSection,
    .collapsible_section_with_action = &uiCollapsibleSectionWithAction,
    .tree_folder_node = &uiTreeFolderNode,
    .chip = &uiChip,
    .list_item = &uiListItem,
    .list_item_ex = &uiListItemEx,
    .text_field = &uiTextField,
    .text_area = &uiTextArea,
    .markdown = &uiMarkdown,
    .waveform_view = &uiWaveformView,
    .pdf_view = &uiPdfView,
};

pub const HOST_API_V1 = abi.EditorHostApiV1{
    .abi_version = abi.EDITOR_PLUGIN_ABI_VERSION,
    .frame_alloc = &hostFrameAlloc,
    .use_state_raw = &hostUseStateRaw,
    .get_active_buffer = &hostGetActiveBuffer,
    .get_line_range = &hostGetLineRange,
    .offset_to_line_col = &hostOffsetToLineCol,
    .replace_buffer_range = &hostReplaceBufferRange,
    .set_cursor_and_scroll = &hostSetCursorAndScroll,
    .register_command = &hostRegisterCommand,
    .set_completions = &hostSetCompletions,
    .set_status_notice = &hostSetStatusNotice,
    .request_continuous_redraw = &hostRequestContinuousRedraw,
    .open_waveform_preview = &hostOpenWaveformPreview,
    .open_pdf_preview = &hostOpenPdfPreview,
    .open_git_diff = &hostOpenGitDiff,
    .open_file_path = &hostOpenFilePath,
    .sync_workspace_git = &hostSyncWorkspaceGit,
    .get_git_status = &hostGetGitStatus,
    .git_action = &hostGitAction,
    .run_terminal_command = &hostRunTerminalCommand,
    .toggle_bottom_panel = &hostToggleBottomPanel,
    .toggle_breakpoint = &hostToggleBreakpoint,
    .clear_breakpoints = &hostClearBreakpoints,
    .get_breakpoints = &hostGetBreakpoints,
    .set_debug_location = &hostSetDebugLocation,
    .ui = &UI_API_V1,
};

test "PluginManager & PluginSDK: C-ABI vtable, buffer mutation, useState hot-reload persistence, and 2-phase UI" {
    const surface = try skia.Surface.initRasterN32Premul(320, 240);
    defer surface.deinit();
    const paint = try skia.Paint.init();
    defer paint.deinit();
    const font = try skia.Font.init(null, 13.0);
    defer font.deinit();

    const state = try std.testing.allocator.create(EditorState);
    defer std.testing.allocator.destroy(state);
    state.* = .{
        .frame_arena = std.heap.ArenaAllocator.init(std.testing.allocator),
        .paint = paint,
        .font_title = font,
        .font_body = font,
        .font_mono = font,
        .font_code = font,
        .ui_ctx = .{
            .arena = undefined,
            .canvas = surface.canvas(),
            .paint = paint,
            .font_title = font,
            .font_body = font,
            .font_mono = font,
        },
    };
    state.initEmpty();
    defer {
        state.plugins.deinit(state);
        state.scratch_buf.deinit();
        state.ui_ctx.deinit();
        state.frame_arena.deinit();
    }
    state.ui_ctx.arena = state.frame_arena.allocator();
    state.scratch_buf.resetWithSlice("hello world   \nsecond line  ");

    const SamplePlugin = struct {
        const CounterState = struct {
            runs: u32 = 0,
        };

        fn onInit(ctx: *sdk.PluginContext) void {
            ctx.registerCommand("test.uppercase_first", "Test: Uppercase Header", "Test", "Cmd+T");
        }

        fn onCommand(ctx: *sdk.PluginContext, cmd_id: []const u8) void {
            if (std.mem.eql(u8, cmd_id, "test.uppercase_first")) {
                const st = ctx.useState(CounterState, "counter", .{});
                st.runs += 1;
                if (ctx.activeBuffer()) |buf| {
                    const msg = ctx.fmt("// Runs={d}\n", .{st.runs});
                    _ = ctx.replaceBufferRange(buf.buffer_id, 0, 0, msg);
                    ctx.setStatusNotice("Executed test.uppercase_first");
                }
            }
        }

        fn renderSidebar(ctx: *sdk.PluginContext) void {
            const st = ctx.useState(CounterState, "counter", .{});
            ctx.ui.sectionLabel("TEST PLUGIN");
            ctx.ui.monoLabel(ctx.fmt("Runs: {d}", .{st.runs}));
            _ = ctx.ui.button("Run Action##test_plug_btn", 0, 26);
        }
    };

    const desc = sdk.createPluginDescriptor(.{
        .id = "test.sample_plugin",
        .display_name = "Sample Test Plugin",
        .version = "0.2.0",
        .init = SamplePlugin.onInit,
        .on_command = SamplePlugin.onCommand,
        .render_sidebar = SamplePlugin.renderSidebar,
    });

    const p_idx = state.plugins.registerStaticPlugin(state, desc).?;
    try std.testing.expectEqual(@as(usize, 1), state.plugins.plugin_count);
    try std.testing.expectEqual(@as(usize, 1), state.plugins.plugins[p_idx].command_count);

    // Execute plugin command -> mutates scratch buffer and increments CounterState.runs in useState
    state.plugins.executePluginCommand(state, p_idx, 0);
    try std.testing.expect(std.mem.startsWith(u8, state.scratch_buf.slice(), "// Runs=1\n"));
    try std.testing.expectEqualStrings("Executed test.uppercase_first", state.statusNotice());

    // Simulate hot-reload of the plugin -> CounterState.runs persists across reload!
    _ = state.plugins.registerStaticPlugin(state, desc);
    try std.testing.expectEqual(@as(u32, 1), state.plugins.plugins[p_idx].reload_count);
    state.plugins.executePluginCommand(state, p_idx, 0);
    try std.testing.expect(std.mem.startsWith(u8, state.scratch_buf.slice(), "// Runs=2\n"));

    // Exercise 2-phase Pass.input and Pass.paint on plugin sidebar
    const win_rect = skia.Rect.xywh(0, 0, 320, 240);
    _ = state.frame_arena.reset(.retain_capacity);
    state.ui_ctx.beginPass(.input, state.frame_arena.allocator(), surface.canvas(), win_rect, 10, 10, false, false, false);
    state.plugins.renderSidebarPanels(state);
    state.ui_ctx.endPass();

    state.ui_ctx.invalidateWindow();
    state.ui_ctx.clip_damage = win_rect;
    state.ui_ctx.beginPass(.paint, state.frame_arena.allocator(), surface.canvas(), win_rect, 10, 10, false, false, false);
    state.plugins.renderSidebarPanels(state);
    state.ui_ctx.endPass();

    // If `zig-out/plugins/libdoc_metrics.dylib` is built on disk, verify real `dlopen` loading & command execution
    if (state.plugins.loadOrReloadDylib(state, "zig-out/plugins/libdoc_metrics.dylib")) {
        try std.testing.expectEqual(@as(usize, 2), state.plugins.plugin_count);
        const dm_idx: usize = 1;
        try std.testing.expectEqualStrings("builtin.doc_metrics", state.plugins.plugins[dm_idx].id.slice());
        try std.testing.expectEqual(@as(usize, 2), state.plugins.plugins[dm_idx].command_count);

        // Execute "doc_metrics.strip_trailing_ws" (command index 1) on scratch_buf ("hello world   \nsecond line  ")
        state.plugins.executePluginCommand(state, dm_idx, 1);
        try std.testing.expect(std.mem.endsWith(u8, state.scratch_buf.slice(), "hello world\nsecond line"));
    }

    // Verify real `dlopen` loading & command execution for C/C++, Java, and Go LSP `.dylib` plugins
    if (state.plugins.loadOrReloadDylib(state, "zig-out/plugins/libcpp_lsp.dylib")) {
        const cpp_idx = state.plugins.plugin_count - 1;
        try std.testing.expectEqualStrings("builtin.cpp_lsp", state.plugins.plugins[cpp_idx].id.slice());
        try std.testing.expectEqual(@as(usize, 4), state.plugins.plugins[cpp_idx].command_count);
        state.scratch_buf.resetWithSlice("namespace demo {\nclass Widget {\nvoid render() {\nint x = 1;\n}\n};\n}");
        // Execute "cpp_lsp.format" (command index 0)
        state.plugins.executePluginCommand(state, cpp_idx, 0);
        try std.testing.expect(std.mem.indexOfPos(u8, state.scratch_buf.slice(), 0, "    class Widget {") != null);

        // Simulate typing `std::vec` in C++ scratch buffer and verify `set_completions` populates autocomplete popup
        state.scratch_buf.resetWithSlice("#include <vector>\nvoid f() {\n    std::vec");
        state.scratch_buf.cursor = state.scratch_buf.len;
        state.scratch_buf.selection_anchor = state.scratch_buf.len;
        state.plugins.notifyBufferEdit(state, 0xFFFF);
        const cpp_comps = state.plugins.activeCompletionsFor(state.frame_arena.allocator(), 0xFFFF, state.scratch_buf.cursor);
        try std.testing.expect(cpp_comps.len >= 1);
        try std.testing.expectEqualStrings("vector", cpp_comps[0].label);
    }

    if (state.plugins.loadOrReloadDylib(state, "zig-out/plugins/libjava_lsp.dylib")) {
        const java_idx = state.plugins.plugin_count - 1;
        try std.testing.expectEqualStrings("builtin.java_lsp", state.plugins.plugins[java_idx].id.slice());
        try std.testing.expectEqual(@as(usize, 4), state.plugins.plugins[java_idx].command_count);
        state.scratch_buf.resetWithSlice("");
        // Execute "java_lsp.insert_record" (command index 2)
        state.plugins.executePluginCommand(state, java_idx, 2);
        try std.testing.expect(std.mem.indexOfPos(u8, state.scratch_buf.slice(), 0, "public record ServiceConfig") != null);

        // Simulate typing `System.out.pr` in Java scratch buffer
        state.scratch_buf.resetWithSlice("public class Main {\n    void run() {\n        System.out.pr");
        state.scratch_buf.cursor = state.scratch_buf.len;
        state.scratch_buf.selection_anchor = state.scratch_buf.len;
        state.plugins.notifyBufferEdit(state, 0xFFFF);
        const java_comps = state.plugins.activeCompletionsFor(state.frame_arena.allocator(), 0xFFFF, state.scratch_buf.cursor);
        try std.testing.expect(java_comps.len >= 1);
        try std.testing.expectEqualStrings("println", java_comps[0].label);
    }

    if (state.plugins.loadOrReloadDylib(state, "zig-out/plugins/libgo_lsp.dylib")) {
        const go_idx = state.plugins.plugin_count - 1;
        try std.testing.expectEqualStrings("builtin.go_lsp", state.plugins.plugins[go_idx].id.slice());
        try std.testing.expectEqual(@as(usize, 4), state.plugins.plugins[go_idx].command_count);
        state.scratch_buf.resetWithSlice("");
        // Execute "go_lsp.insert_package_main" (command index 2)
        state.plugins.executePluginCommand(state, go_idx, 2);
        try std.testing.expect(std.mem.startsWith(u8, state.scratch_buf.slice(), "package main"));

        // Simulate typing `fmt.Pr` in Go scratch buffer
        state.scratch_buf.resetWithSlice("package main\nfunc main() {\n    fmt.Pr");
        state.scratch_buf.cursor = state.scratch_buf.len;
        state.scratch_buf.selection_anchor = state.scratch_buf.len;
        state.plugins.notifyBufferEdit(state, 0xFFFF);
        const go_comps = state.plugins.activeCompletionsFor(state.frame_arena.allocator(), 0xFFFF, state.scratch_buf.cursor);
        try std.testing.expect(go_comps.len >= 1);
        try std.testing.expectEqualStrings("Printf", go_comps[0].label);
    }

    if (state.plugins.loadOrReloadDylib(state, "zig-out/plugins/libsv_lsp.dylib")) {
        const sv_idx = state.plugins.plugin_count - 1;
        try std.testing.expectEqualStrings("builtin.sv_lsp", state.plugins.plugins[sv_idx].id.slice());
        try std.testing.expectEqual(@as(usize, 4), state.plugins.plugins[sv_idx].command_count);
        state.scratch_buf.resetWithSlice("");
        state.scratch_buf.cursor = 0;
        state.scratch_buf.selection_anchor = 0;
        // Execute "sv_lsp.insert_module" (command index 1)
        state.plugins.executePluginCommand(state, sv_idx, 1);
        try std.testing.expect(std.mem.indexOfPos(u8, state.scratch_buf.slice(), 0, "module axi_stream_counter") != null);

        // Simulate typing `always_f` in SystemVerilog scratch buffer
        state.scratch_buf.resetWithSlice("module demo;\n    always_f");
        state.scratch_buf.cursor = state.scratch_buf.len;
        state.scratch_buf.selection_anchor = state.scratch_buf.len;
        state.plugins.notifyBufferEdit(state, 0xFFFF);
        const sv_comps = state.plugins.activeCompletionsFor(state.frame_arena.allocator(), 0xFFFF, state.scratch_buf.cursor);
        try std.testing.expect(sv_comps.len >= 1);
        try std.testing.expectEqualStrings("always_ff", sv_comps[0].label);

        // Exercise 2-phase Pass.input + Pass.paint on sv_lsp's embedded waveform viewer
        _ = state.frame_arena.reset(.retain_capacity);
        state.ui_ctx.beginPass(.input, state.frame_arena.allocator(), surface.canvas(), win_rect, 10, 10, false, false, false);
        state.plugins.renderBottomPanels(state, 200.0);
        state.ui_ctx.endPass();

        state.ui_ctx.invalidateWindow();
        state.ui_ctx.clip_damage = win_rect;
        state.ui_ctx.beginPass(.paint, state.frame_arena.allocator(), surface.canvas(), win_rect, 10, 10, false, false, false);
        state.plugins.renderBottomPanels(state, 200.0);
        state.ui_ctx.endPass();
    }

    if (state.plugins.loadOrReloadDylib(state, "zig-out/plugins/libzig_lsp.dylib")) {
        const zig_idx = state.plugins.plugin_count - 1;
        try std.testing.expectEqualStrings("builtin.zig_lsp", state.plugins.plugins[zig_idx].id.slice());
        state.scratch_buf.resetWithSlice("const std = @import(\"std\");\npub fn run() void {\n    std.ArrayL");
        state.scratch_buf.cursor = state.scratch_buf.len;
        state.scratch_buf.selection_anchor = state.scratch_buf.len;
        state.plugins.notifyBufferEdit(state, 0xFFFF);
        const zig_comps = state.plugins.activeCompletionsFor(state.frame_arena.allocator(), 0xFFFF, state.scratch_buf.cursor);
        try std.testing.expect(zig_comps.len >= 1);
        try std.testing.expectEqualStrings("ArrayList", zig_comps[0].label);
    }

    if (state.plugins.loadOrReloadDylib(state, "zig-out/plugins/librust_lsp.dylib")) {
        const rust_idx = state.plugins.plugin_count - 1;
        try std.testing.expectEqualStrings("builtin.rust_lsp", state.plugins.plugins[rust_idx].id.slice());
        state.scratch_buf.resetWithSlice("fn main() {\n    std::c");
        state.scratch_buf.cursor = state.scratch_buf.len;
        state.scratch_buf.selection_anchor = state.scratch_buf.len;
        state.plugins.notifyBufferEdit(state, 0xFFFF);
        const rust_comps = state.plugins.activeCompletionsFor(state.frame_arena.allocator(), 0xFFFF, state.scratch_buf.cursor);
        try std.testing.expect(rust_comps.len >= 1);
        try std.testing.expectEqualStrings("collections::HashMap", rust_comps[0].label);
    }

    if (state.plugins.loadOrReloadDylib(state, "zig-out/plugins/libpython_lsp.dylib")) {
        const py_idx = state.plugins.plugin_count - 1;
        try std.testing.expectEqualStrings("builtin.python_lsp", state.plugins.plugins[py_idx].id.slice());
        state.scratch_buf.resetWithSlice("import dataclasses\n@datac");
        state.scratch_buf.cursor = state.scratch_buf.len;
        state.scratch_buf.selection_anchor = state.scratch_buf.len;
        state.plugins.notifyBufferEdit(state, 0xFFFF);
        const py_comps = state.plugins.activeCompletionsFor(state.frame_arena.allocator(), 0xFFFF, state.scratch_buf.cursor);
        try std.testing.expect(py_comps.len >= 1);
        try std.testing.expectEqualStrings("@dataclass", py_comps[0].label);
    }

    if (state.plugins.loadOrReloadDylib(state, "zig-out/plugins/libts_lsp.dylib")) {
        const ts_idx = state.plugins.plugin_count - 1;
        try std.testing.expectEqualStrings("builtin.ts_lsp", state.plugins.plugins[ts_idx].id.slice());
        state.scratch_buf.resetWithSlice("console.lo");
        state.scratch_buf.cursor = state.scratch_buf.len;
        state.scratch_buf.selection_anchor = state.scratch_buf.len;
        state.plugins.notifyBufferEdit(state, 0xFFFF);
        const ts_comps = state.plugins.activeCompletionsFor(state.frame_arena.allocator(), 0xFFFF, state.scratch_buf.cursor);
        try std.testing.expect(ts_comps.len >= 1);
        try std.testing.expectEqualStrings("log", ts_comps[0].label);
    }

    if (state.plugins.loadOrReloadDylib(state, "zig-out/plugins/libhdl_lsp.dylib")) {
        const hdl_idx = state.plugins.plugin_count - 1;
        try std.testing.expectEqualStrings("builtin.hdl_lsp", state.plugins.plugins[hdl_idx].id.slice());
        state.scratch_buf.resetWithSlice("std_logic_v");
        state.scratch_buf.cursor = state.scratch_buf.len;
        state.scratch_buf.selection_anchor = state.scratch_buf.len;
        state.plugins.notifyBufferEdit(state, 0xFFFF);
        const hdl_comps = state.plugins.activeCompletionsFor(state.frame_arena.allocator(), 0xFFFF, state.scratch_buf.cursor);
        try std.testing.expect(hdl_comps.len >= 1);
        try std.testing.expectEqualStrings("std_logic_vector", hdl_comps[0].label);
    }

    if (state.plugins.loadOrReloadDylib(state, "zig-out/plugins/librtl_sim.dylib")) {
        const rtl_idx = state.plugins.plugin_count - 1;
        try std.testing.expectEqualStrings("builtin.rtl_sim", state.plugins.plugins[rtl_idx].id.slice());
        try std.testing.expectEqual(abi.PluginSidebarIcon.none, state.plugins.plugins[rtl_idx].sidebar_icon);
        try std.testing.expect(!state.plugins.plugins[rtl_idx].capabilities.sidebar_panel);
        try std.testing.expect(!state.plugins.plugins[rtl_idx].capabilities.bottom_panel);
        try std.testing.expect(!state.plugins.plugins[rtl_idx].capabilities.status_bar);
        try std.testing.expectEqual(@as(usize, 2), state.plugins.plugins[rtl_idx].command_count);
        state.plugins.executePluginCommand(state, rtl_idx, 0); // open_preview
        state.plugins.executePluginCommand(state, rtl_idx, 1); // open_preview_side
    }

    if (state.plugins.loadOrReloadDylib(state, "zig-out/plugins/libhex_inspector.dylib")) {
        const hex_idx = state.plugins.plugin_count - 1;
        try std.testing.expectEqualStrings("builtin.hex_inspector", state.plugins.plugins[hex_idx].id.slice());
        try std.testing.expectEqual(@as(usize, 3), state.plugins.plugins[hex_idx].command_count);
        state.scratch_buf.resetWithSlice("0xCAFE_BABE ");
        state.scratch_buf.cursor = 4;
        state.scratch_buf.selection_anchor = 4;
        state.plugins.executePluginCommand(state, hex_idx, 0); // decode_cursor -> 0xCAFEBABE
        state.plugins.executePluginCommand(state, hex_idx, 1); // byte_swap -> 0xBEBAFECA
        state.scratch_buf.cursor = state.scratch_buf.len;
        state.scratch_buf.selection_anchor = state.scratch_buf.len;
        state.plugins.executePluginCommand(state, hex_idx, 2); // insert_hex_mask
        try std.testing.expect(std.mem.indexOfPos(u8, state.scratch_buf.slice(), 0, "0xBEBAFECA") != null);
    }

    if (state.plugins.loadOrReloadDylib(state, "zig-out/plugins/liblldb_debug.dylib")) {
        const lldb_idx = state.plugins.plugin_count - 1;
        try std.testing.expectEqualStrings("builtin.lldb_debug", state.plugins.plugins[lldb_idx].id.slice());
        try std.testing.expectEqual(@as(usize, 6), state.plugins.plugins[lldb_idx].command_count);
        try std.testing.expect(state.plugins.hasDebuggerForFile("examples/autocomplete/main.c"));
        try std.testing.expect(state.plugins.hasDebuggerForFile("src/app/state.zig"));
        try std.testing.expect(state.plugins.hasDebuggerForFile("examples/autocomplete/main.rs"));
        try std.testing.expect(!state.plugins.hasDebuggerForFile("README.md"));
        try std.testing.expect(!state.plugins.hasDebuggerForFile(".vscode/launch.json"));
        try std.testing.expect(!state.plugins.hasDebuggerForFile("examples/autocomplete/main.py"));
        try std.testing.expect(!state.plugins.hasDebuggerForFile("examples/autocomplete/counter.sv"));
        try std.testing.expect(!state.plugins.hasDebuggerForFile("*scratch*"));

        // Clear breakpoints and verify start -> paused at entry -> continue (running) -> pause -> step_over
        state.plugins.clearBreakpoints();
        state.plugins.executePluginCommand(state, lldb_idx, 1); // start_or_continue (1st: starts & pauses at entry)
        try std.testing.expect(state.plugins.debug_active);
        try std.testing.expect(state.plugins.debug_paused);

        state.plugins.executePluginCommand(state, lldb_idx, 1); // start_or_continue (2nd: continues -> running!)
        try std.testing.expect(state.plugins.debug_active);
        try std.testing.expect(!state.plugins.debug_paused);

        state.plugins.executePluginCommand(state, lldb_idx, 1); // start_or_continue (3rd: pauses running target!)
        try std.testing.expect(state.plugins.debug_active);
        try std.testing.expect(state.plugins.debug_paused);

        state.plugins.executePluginCommand(state, lldb_idx, 0); // toggle_breakpoint
        state.plugins.executePluginCommand(state, lldb_idx, 2); // step_over
        state.plugins.executePluginCommand(state, lldb_idx, 3); // step_into
    }

    if (state.plugins.loadOrReloadDylib(state, "zig-out/plugins/libgit_lens.dylib")) {
        const git_idx = state.plugins.plugin_count - 1;
        try std.testing.expectEqualStrings("builtin.git_lens", state.plugins.plugins[git_idx].id.slice());
        try std.testing.expectEqual(abi.PluginSidebarIcon.git, state.plugins.plugins[git_idx].sidebar_icon);
        try std.testing.expectEqual(@as(usize, 5), state.plugins.plugins[git_idx].command_count);
        state.plugins.executePluginCommand(state, git_idx, 0); // blame_line
        state.plugins.executePluginCommand(state, git_idx, 1); // diff_file
        state.plugins.executePluginCommand(state, git_idx, 4); // refresh_status

        // Verify Host Git status query and action via C-ABI vtable
        var hctx = HostCallbackCtx{ .mgr = &state.plugins, .state = state, .plugin_idx = git_idx };
        var snap: abi.GitStatusSnapshotV1 = undefined;
        try std.testing.expect(HOST_API_V1.get_git_status(&hctx, &snap));
        try std.testing.expect(snap.branch.len > 0);
        try std.testing.expect(HOST_API_V1.git_action(&hctx, .refresh, abi.AbiSlice.fromZig("")));

        // Verify git_lens sidebar clears staged/unstaged file list when statuses transition from dirty -> clean (post-commit)
        const saved_file_count = state.file_count;
        const saved_file_0 = state.files[0];
        defer {
            state.files[0] = saved_file_0;
            state.file_count = saved_file_count;
        }
        state.files[0] = .{ .name = "main.zig", .path = "src/app/main.zig", .folder = "src/app", .initial_source = "" };
        state.file_count = 1;
        @memset(state.git_file_statuses, .{});
        state.git_file_statuses[0] = .{ .staged = true, .unstaged = true };
        _ = state.frame_arena.reset(.retain_capacity);
        state.ui_ctx.beginPass(.input, state.frame_arena.allocator(), surface.canvas(), win_rect, 12, 12, false, false, false);
        state.plugins.renderPluginSidebar(state, git_idx);
        state.ui_ctx.endPass();
        const dirty_rects = state.ui_ctx.last_input_rect_count;

        @memset(state.git_file_statuses, .{});
        var test_commit = git_client.GitCommitEntry{};
        test_commit.hash_str.set("abc1234");
        test_commit.subject_str.set("Test commit with files");
        test_commit.rel_time_str.set("just now");
        test_commit.files[0].set("src/app/main.zig");
        test_commit.file_statuses[0] = 'M';
        test_commit.files[1].set("src/ui/root.zig");
        test_commit.file_statuses[1] = 'A';
        test_commit.file_count = 2;
        test_commit.files_changed = 2;
        state.git_commits[0] = test_commit;
        state.git_commit_count = 1;

        _ = state.frame_arena.reset(.retain_capacity);
        try std.testing.expect(HOST_API_V1.get_git_status(&hctx, &snap));
        try std.testing.expectEqual(@as(usize, 1), snap.commit_count);
        try std.testing.expectEqual(@as(usize, 2), snap.commits_ptr.?[0].file_count);
        try std.testing.expectEqualStrings("src/app/main.zig", snap.commits_ptr.?[0].files_ptr.?[0].path.toZig());
        try std.testing.expectEqual(@as(u8, 'M'), snap.commits_ptr.?[0].files_ptr.?[0].status);

        _ = state.frame_arena.reset(.retain_capacity);
        state.ui_ctx.beginPass(.input, state.frame_arena.allocator(), surface.canvas(), win_rect, 12, 12, false, false, false);
        state.plugins.renderPluginSidebar(state, git_idx);
        state.ui_ctx.endPass();
        const clean_rects = state.ui_ctx.last_input_rect_count;
        try std.testing.expect(clean_rects < dirty_rects);
    }

    if (state.plugins.loadOrReloadDylib(state, "zig-out/plugins/libpdf_reader.dylib")) {
        const pdf_idx = state.plugins.plugin_count - 1;
        try std.testing.expectEqualStrings("builtin.pdf_reader", state.plugins.plugins[pdf_idx].id.slice());
        try std.testing.expectEqual(abi.PluginSidebarIcon.none, state.plugins.plugins[pdf_idx].sidebar_icon);
        try std.testing.expect(!state.plugins.plugins[pdf_idx].capabilities.sidebar_panel);
        try std.testing.expectEqual(@as(usize, 4), state.plugins.plugins[pdf_idx].command_count);

        state.scratch_buf.resetWithSlice("");
        state.scratch_buf.cursor = 0;
        state.scratch_buf.selection_anchor = 0;
        state.plugins.executePluginCommand(state, pdf_idx, 2); // insert_citation
        try std.testing.expect(std.mem.indexOfPos(u8, state.scratch_buf.slice(), 0, "Lightning SoC RV32IMAC Datasheet") != null);
    }

    // Exercise 2-phase Pass.input + Pass.paint across all 15 loaded plugins simultaneously
    _ = state.frame_arena.reset(.retain_capacity);
    state.ui_ctx.beginPass(.input, state.frame_arena.allocator(), surface.canvas(), win_rect, 12, 12, false, false, false);
    state.plugins.renderStatusBarItems(state);
    state.plugins.renderSidebarPanels(state);
    state.plugins.renderBottomPanels(state, 220.0);
    state.ui_ctx.endPass();

    state.ui_ctx.invalidateWindow();
    state.ui_ctx.clip_damage = win_rect;
    state.ui_ctx.beginPass(.paint, state.frame_arena.allocator(), surface.canvas(), win_rect, 12, 12, false, false, false);
    state.plugins.renderStatusBarItems(state);
    state.plugins.renderSidebarPanels(state);
    state.plugins.renderBottomPanels(state, 220.0);
    state.ui_ctx.endPass();
}

test "PluginManager: multi-directory priority ranking and user directory (~/) overrides" {
    var search_dirs: [MaxPluginSearchDirs]PluginSearchDir = undefined;
    const count = PluginManager.collectPluginSearchDirs(&search_dirs);
    try std.testing.expect(count > 0);

    // Verify user directory path resolution helper
    var user_dir_buf: [256:0]u8 = @splat(0);
    if (PluginManager.getUserPluginsDirectory(&user_dir_buf)) |udir| {
        try std.testing.expect(std.mem.indexOfPos(u8, udir, 0, ".lightning/plugins") != null);
    }

    // Verify priority ranking logic with dylibs
    const surface = try skia.Surface.initRasterN32Premul(100, 100);
    defer surface.deinit();
    const paint = try skia.Paint.init();
    defer paint.deinit();
    const font = try skia.Font.init(null, 13.0);
    defer font.deinit();

    const state = try std.testing.allocator.create(EditorState);
    defer std.testing.allocator.destroy(state);
    state.* = .{
        .frame_arena = std.heap.ArenaAllocator.init(std.testing.allocator),
        .paint = paint,
        .font_title = font,
        .font_body = font,
        .font_mono = font,
        .font_code = font,
        .ui_ctx = .{
            .arena = undefined,
            .canvas = surface.canvas(),
            .paint = paint,
            .font_title = font,
            .font_body = font,
            .font_mono = font,
        },
    };
    state.initEmpty();
    defer {
        state.plugins.deinit(state);
        state.scratch_buf.deinit();
        state.ui_ctx.deinit();
        state.frame_arena.deinit();
    }
    state.ui_ctx.arena = state.frame_arena.allocator();

    const dylib_file = "zig-out/plugins/libdoc_metrics.dylib";
    var st: std.c.Stat = undefined;
    if (std.c.stat(dylib_file, &st) == 0) {
        // 1. Load as bundled application plugin (.bundled priority)
        try std.testing.expect(state.plugins.loadOrReloadDylibWithPriority(state, dylib_file, .bundled));
        const idx = state.plugins.plugin_count - 1;
        try std.testing.expectEqual(PluginPriority.bundled, state.plugins.plugins[idx].priority);
        try std.testing.expect(!state.plugins.plugins[idx].is_user_override);

        // 2. Upgrade to user directory override (.user priority)
        // Simulate a user plugin file with matching base name in /tmp
        const user_fake_dylib = "/tmp/libdoc_metrics.dylib";
        try std.testing.expect(PluginManager.copyFilePosix(dylib_file, user_fake_dylib));
        defer _ = fs_util.unlink(user_fake_dylib);

        try std.testing.expect(state.plugins.loadOrReloadDylibWithPriority(state, user_fake_dylib, .user));
        try std.testing.expectEqual(PluginPriority.user, state.plugins.plugins[idx].priority);
        try std.testing.expect(state.plugins.plugins[idx].is_user_override);

        // 3. Bundled candidate cannot downgrade or overwrite active user override
        const rejected = state.plugins.loadOrReloadDylibWithPriority(state, dylib_file, .bundled);
        try std.testing.expect(!rejected);
        try std.testing.expectEqual(PluginPriority.user, state.plugins.plugins[idx].priority);
        try std.testing.expect(state.plugins.plugins[idx].is_user_override);
    }
}
