//! C-ABI boundary shared between the Window Host executable and the hot-reloadable App `.dylib`.
//!
//! Includes host-owned callbacks for:
//!   1. **React-style `useState` KV Store** (`pushScope`, `popScope`, `useState`, `removeState`)
//!   2. **Reload-Boundary JSON Serialization** (`writeReloadSnapshot`, `readReloadSnapshot`)
//!   3. **Safe Host String Duplication** (`dupeHostBytes` / `freeHostBytes`) to avoid `.rodata`
//!      string literal segfaults after `dlclose`.

const std = @import("std");
const builtin = @import("builtin");
const skia = @import("skia");
const c = skia.c;
const state_store = @import("state_store.zig");
const fs_util = @import("fs_util.zig");
const objc = @import("macos/objc.zig");

/// Decoded or encoded image payload read from the native OS clipboard (`NSPasteboard`).
pub const ClipboardImage = struct {
    /// Raw encoded image bytes (PNG, JPEG, WebP, GIF, BMP) allocated in caller's `allocator`.
    data: []const u8,
    /// Detected MIME type (e.g. `"image/png"`, `"image/jpeg"`, `"image/webp"`, `"image/gif"`).
    mime_type: []const u8,
    /// Original file path on disk when copied as a file in Finder, or `""` when copied as raw pixels/screenshot.
    source_path: []const u8 = "",
    /// Display filename (e.g. `"screenshot.png"` or the basename of `source_path`).
    filename: []const u8 = "screenshot.png",
};

var g_test_clipboard_image: ?ClipboardImage = null;
var g_test_picked_folder: ?[]const u8 = null;
var g_test_picked_file: ?[]const u8 = null;
var g_test_saved_file: ?[]const u8 = null;

/// Allows headless unit tests to simulate a copied screenshot or image file on the system clipboard.
pub fn setTestClipboardImage(img: ?ClipboardImage) void {
    g_test_clipboard_image = img;
}

/// Allows headless unit tests to simulate selecting a folder in the native folder-picker dialog.
pub fn setTestPickedFolder(path: ?[]const u8) void {
    g_test_picked_folder = path;
}

/// Allows headless unit tests to simulate selecting a file in the native file-open dialog.
pub fn setTestPickedFile(path: ?[]const u8) void {
    g_test_picked_file = path;
}

/// Allows headless unit tests to simulate choosing a destination path in the native file-save dialog.
pub fn setTestSavedFile(path: ?[]const u8) void {
    g_test_saved_file = path;
}

pub const StateStore = state_store.StateStore;
pub const SnapshotBuffer = state_store.SnapshotBuffer;
pub const computeTypeHash = state_store.computeTypeHash;

/// Virtual key codes normalized across the host platform boundary.
pub const KeyCode = enum(u8) {
    none = 0,
    left,
    right,
    up,
    down,
    home,
    end,
    page_up,
    page_down,
    backspace,
    delete_forward,
    enter,
    tab,
    escape,
    key_a,
    key_c,
    key_x,
    key_v,
    key_z,
    key_s,
    key_d,
    key_f,
    key_g,
    key_b,
    key_p,
    key_j,
    key_w,
    key_backslash,
    key_0,
    key_1,
    key_2,
    key_3,
    key_4,
    key_5,
    key_6,
    key_7,
    key_8,
    key_9,
    key_slash,
    key_e,
    key_h,
    key_i,
    key_k,
    key_l,
    key_m,
    key_n,
    key_o,
    key_q,
    key_r,
    key_t,
    key_u,
    key_y,
    key_lbracket,
    key_rbracket,
    key_minus,
    key_space,
    f1,
    f2,
    f3,
    f4,
    f5,
    f6,
    f7,
    f8,
    f9,
    f10,
    f11,
    f12,

    /// Maps `Ctrl+<key>` to its standard ASCII/POSIX terminal control byte (`0x00..0x1F`).
    pub fn toCtrlByte(self: KeyCode) ?u8 {
        return switch (self) {
            .key_space, .key_2 => 0x00, // Ctrl+Space / Ctrl+@
            .key_a => 0x01,
            .key_b => 0x02,
            .key_c => 0x03,
            .key_d => 0x04,
            .key_e => 0x05,
            .key_f => 0x06,
            .key_g => 0x07,
            .key_h => 0x08,
            .key_i => 0x09,
            .key_j => 0x0A,
            .key_k => 0x0B,
            .key_l => 0x0C,
            .key_m => 0x0D,
            .key_n => 0x0E,
            .key_o => 0x0F,
            .key_p => 0x10,
            .key_q => 0x11,
            .key_r => 0x12,
            .key_s => 0x13,
            .key_t => 0x14,
            .key_u => 0x15,
            .key_v => 0x16,
            .key_w => 0x17,
            .key_x => 0x18,
            .key_y => 0x19,
            .key_z => 0x1A,
            .key_lbracket, .escape => 0x1B, // Ctrl+[ -> ESC
            .key_backslash => 0x1C, // Ctrl+\ -> FS (SIGQUIT)
            .key_rbracket => 0x1D, // Ctrl+] -> GS (tag jump in vim)
            .key_6 => 0x1E, // Ctrl+^ / Ctrl+6 -> RS (alternate file in vim)
            .key_minus, .key_slash => 0x1F, // Ctrl+_ / Ctrl+/ -> US (undo in emacs/zsh)
            else => null,
        };
    }
};

/// Discrete keyboard event with modifier flags captured during the frame.
pub const KeyEvent = extern struct {
    key: KeyCode = .none,
    shift: bool = false,
    cmd: bool = false,
    alt: bool = false,
    ctrl: bool = false,
};

// Host-side C-ABI callback signatures (always point to the Host executable's `.text` segment)
pub const HostPushScopeFn = *const fn (store: *anyopaque, name_ptr: [*]const u8, name_len: usize) callconv(.c) void;
pub const HostPopScopeFn = *const fn (store: *anyopaque) callconv(.c) void;
pub const HostResetScopesFn = *const fn (store: *anyopaque) callconv(.c) void;
pub const HostUseStateRawFn = *const fn (
    store: *anyopaque,
    key_ptr: [*]const u8,
    key_len: usize,
    size: usize,
    alignment_log2: u8,
    type_hash: u64,
    initialized_out: *bool,
) callconv(.c) [*]u8;
pub const HostRemoveStateFn = *const fn (store: *anyopaque, key_ptr: [*]const u8, key_len: usize) callconv(.c) bool;
pub const HostStateCountFn = *const fn (store: *const anyopaque) callconv(.c) usize;

pub const HostWriteSnapshotFn = *const fn (snap: *anyopaque, ptr: [*]const u8, len: usize) callconv(.c) void;
pub const HostReadSnapshotFn = *const fn (snap: *const anyopaque, len_out: *usize) callconv(.c) ?[*]const u8;

pub const HostGetClipboardFn = *const fn (buf_ptr: ?[*]u8, buf_cap: usize) callconv(.c) usize;
pub const HostSetClipboardFn = *const fn (ptr: [*]const u8, len: usize) callconv(.c) void;
pub const HostPickFolderFn = *const fn (buf_ptr: [*]u8, buf_cap: usize) callconv(.c) usize;
pub const HostWindowActionFn = *const fn (action: u32, x: f32, y: f32) callconv(.c) void;

/// Normalized mouse cursor shapes across the host platform boundary.
pub const CursorShape = enum(u8) {
    arrow = 0,
    pointing_hand,
    ibeam,
    resize_ew,
    resize_ns,
    crosshair,
    grab,
    grabbing,
    not_allowed,
};

pub const PlatformContext = extern struct {
    /// Opaque pointer to `.dylib`-owned runtime state (Skia fonts, GPU surfaces, caches, and active structs).
    state: ?*anyopaque = null,
    state_size: usize = 0,
    state_version: u64 = 0,

    /// Host-owned persistent `StateStore` (`*StateStore`) and `SnapshotBuffer` (`*SnapshotBuffer`).
    /// Survive across all `.dylib` reloads regardless of struct layout changes!
    state_store: ?*anyopaque = null,
    snapshot_buffer: ?*anyopaque = null,

    /// Host-provided C-ABI functions for `useState` hooks & JSON boundary snapshots
    host_push_scope: ?HostPushScopeFn = null,
    host_pop_scope: ?HostPopScopeFn = null,
    host_reset_scopes: ?HostResetScopesFn = null,
    host_use_state_raw: ?HostUseStateRawFn = null,
    host_remove_state: ?HostRemoveStateFn = null,
    host_state_count: ?HostStateCountFn = null,
    host_write_snapshot: ?HostWriteSnapshotFn = null,
    host_read_snapshot: ?HostReadSnapshotFn = null,
    host_get_clipboard: ?HostGetClipboardFn = null,
    host_set_clipboard: ?HostSetClipboardFn = null,
    host_pick_folder: ?HostPickFolderFn = null,
    host_pick_file: ?HostPickFolderFn = null,
    host_save_file: ?HostPickFolderFn = null,
    host_window_action: ?HostWindowActionFn = null,

    /// Incremented every time the host reloads `libeditor_app.dylib`.
    reload_count: u32 = 0,

    /// Desired cursor shape set by widgets during `.input` pass
    cursor_shape: CursorShape = .arrow,

    /// Window dimensions and Retina scale factor
    width: f32 = 0,
    height: f32 = 0,
    dpi_scale: f32 = 1.0,
    is_fullscreen: bool = false,

    /// Mouse input state in logical window coordinates
    mouse_x: f32 = 0,
    mouse_y: f32 = 0,
    scroll_dx: f32 = 0,
    scroll_dy: f32 = 0,
    mouse_down: bool = false,
    mouse_pressed: bool = false,
    mouse_released: bool = false,
    mouse_click_count: u8 = 0,
    mouse_shift: bool = false,
    mouse_alt: bool = false,
    right_mouse_down: bool = false,
    right_mouse_pressed: bool = false,
    right_mouse_released: bool = false,

    /// Per-frame keyboard events and UTF-8 typed text buffer
    key_events: [16]KeyEvent = @splat(.{}),
    key_event_count: u8 = 0,
    text_input_buf: [128]u8 = @splat(0),
    text_input_len: u8 = 0,

    /// Active text caret coordinates in logical window points (for macOS inline Emoji/IME popover positioning)
    ime_cursor_x: f32 = 120.0,
    ime_cursor_y: f32 = 120.0,
    ime_cursor_h: f32 = 20.0,

    /// Counter of actual GPU paints performed
    frame_count: u64 = 0,

    /// Set to true by the host on first frame, window resize, or hot-reload.
    force_full_redraw: bool = true,

    /// Set to true by `app_tick` when an animation is active and continuous 60fps redraws are needed.
    needs_continuous_redraw: bool = false,

    /// Optional debug paint-flashing overlay drawn on the swapchain drawable (not baked into backbuffer)
    show_dirty_overlay: bool = false,
    last_dirty_rect: c.sk_rect_t = .{ .left = 0, .top = 0, .right = 0, .bottom = 0 },

    /// Skia handles for the current frame (persistent GPU backbuffer canvas)
    canvas: ?*c.sk_canvas_t = null,
    gr_context: ?*c.gr_direct_context_t = null,
    font_mgr: ?*c.sk_fontmgr_t = null,

    /// Microsecond phase profiling timings recorded for the current frame
    phase_input_us: u32 = 0,
    phase_paint_us: u32 = 0,

    /// TextCache telemetry updated at end of frame
    text_cache_lookups: usize = 0,
    text_cache_hits: usize = 0,
    text_cache_misses: usize = 0,
    text_cache_evictions: usize = 0,

    /// Trackpad pinch-to-zoom magnification delta (`NSEventTypeMagnify`) for the current frame
    magnify_delta: f32 = 0,

    // ========================================================================
    // Ergonomic Zig Methods for `.dylib` Plugin Code
    // ========================================================================

    pub fn clearFrameInput(self: *PlatformContext) void {
        self.scroll_dx = 0;
        self.scroll_dy = 0;
        self.magnify_delta = 0;
        self.mouse_click_count = 0;
        self.mouse_shift = false;
        self.key_event_count = 0;
        self.text_input_len = 0;
    }

    pub fn pushKeyEvent(self: *PlatformContext, ev: KeyEvent) void {
        if (self.key_event_count < self.key_events.len) {
            self.key_events[self.key_event_count] = ev;
            self.key_event_count += 1;
        }
    }

    pub fn pushTextInput(self: *PlatformContext, text: []const u8) void {
        for (text) |b| {
            // Ignore ASCII control chars (< 0x20) and DEL (0x7F); handled via KeyEvent
            if (b < 0x20 or b == 0x7f) continue;
            if (self.text_input_len < self.text_input_buf.len) {
                self.text_input_buf[self.text_input_len] = b;
                self.text_input_len += 1;
            }
        }
    }

    pub fn keyEvents(self: *const PlatformContext) []const KeyEvent {
        return self.key_events[0..self.key_event_count];
    }

    pub fn textInput(self: *const PlatformContext) []const u8 {
        return self.text_input_buf[0..self.text_input_len];
    }

    /// Bind a host-owned `StateStore` and `SnapshotBuffer` to this `PlatformContext`.
    pub fn bindHostStores(self: *PlatformContext, store: *StateStore, snap: *SnapshotBuffer) void {
        self.state_store = store;
        self.snapshot_buffer = snap;
        self.host_push_scope = &hostPushScopeImpl;
        self.host_pop_scope = &hostPopScopeImpl;
        self.host_reset_scopes = &hostResetScopesImpl;
        self.host_use_state_raw = &hostUseStateRawImpl;
        self.host_remove_state = &hostRemoveStateImpl;
        self.host_state_count = &hostStateCountImpl;
        self.host_write_snapshot = &hostWriteSnapshotImpl;
        self.host_read_snapshot = &hostReadSnapshotImpl;
    }

    /// Push a hierarchical component scope (like a React component key or Dear ImGui `PushID`).
    pub fn pushScope(self: *PlatformContext, scope_name: []const u8) void {
        if (self.state_store) |store| {
            if (self.host_push_scope) |f| {
                f(store, scope_name.ptr, scope_name.len);
            }
        }
    }

    /// Pop the most recently pushed component scope.
    pub fn popScope(self: *PlatformContext) void {
        if (self.state_store) |store| {
            if (self.host_pop_scope) |f| {
                f(store);
            }
        }
    }

    /// Reset all component scopes (automatically called at the start of each pass).
    pub fn resetScopes(self: *PlatformContext) void {
        if (self.state_store) |store| {
            if (self.host_reset_scopes) |f| {
                f(store);
            }
        }
    }

    /// React Fast Refresh-style `useState`: returns a zero-overhead `*T` pointer allocated in Host memory.
    /// - Survives `.dylib` hot-reloads.
    /// - If `T`'s type or struct fields change, automatically frees the old value and initializes `default`.
    pub fn useState(self: *PlatformContext, comptime T: type, key: []const u8, default: T) *T {
        comptime {
            if (T == []const u8 or T == []u8) {
                @compileError("Do not store raw []const u8 slices in useState (causes .rodata segfault on dlclose). Use platform.InlineString(N) instead.");
            }
        }
        const store = self.state_store orelse @panic("PlatformContext.state_store is not bound");
        const use_fn = self.host_use_state_raw orelse @panic("PlatformContext.host_use_state_raw is not bound");

        var initialized = false;
        const raw_ptr = use_fn(
            store,
            key.ptr,
            key.len,
            @sizeOf(T),
            @ctz(@as(usize, @alignOf(T))),
            comptime computeTypeHash(T),
            &initialized,
        );
        const typed_ptr: *T = @ptrCast(@alignCast(raw_ptr));
        if (!initialized) {
            typed_ptr.* = default;
        }
        return typed_ptr;
    }

    /// Returns the number of live `useState` entries currently stored in the Host KV map.
    pub fn stateEntryCount(self: *const PlatformContext) usize {
        if (self.state_store) |store| {
            if (self.host_state_count) |f| {
                return f(store);
            }
        }
        return 0;
    }

    /// Triggers a native window host action (e.g. popup menu `1..3` or minimize/maximize/close `10..12` on Windows).
    pub fn triggerWindowAction(self: *const PlatformContext, action: u32, x: f32, y: f32) void {
        if (self.host_window_action) |fn_ptr| {
            fn_ptr(action, x, y);
        }
    }

    /// Reads UTF-8 text from the native system clipboard into `buf`, returning the copied slice.
    pub fn getClipboardText(self: *const PlatformContext, buf: []u8) ?[]const u8 {
        const get_fn = self.host_get_clipboard orelse return null;
        if (buf.len == 0) return null;
        const n = get_fn(buf.ptr, buf.len);
        if (n == 0) return null;
        return buf[0..@min(n, buf.len)];
    }

    /// Reads arbitrarily large UTF-8 text from the native system clipboard by querying the exact
    /// byte length from the host and allocating the slice in `allocator` (e.g. `uic.arena`).
    pub fn getClipboardTextAlloc(self: *const PlatformContext, allocator: std.mem.Allocator) ?[]const u8 {
        const get_fn = self.host_get_clipboard orelse return null;
        const total_len = get_fn(null, 0);
        if (total_len == 0) return null;
        const buf = allocator.alloc(u8, total_len) catch return null;
        const copied = get_fn(buf.ptr, buf.len);
        if (copied == 0) return null;
        return buf[0..@min(copied, buf.len)];
    }

    /// Writes UTF-8 text to the native system clipboard.
    pub fn setClipboardText(self: *const PlatformContext, text: []const u8) bool {
        const set_fn = self.host_set_clipboard orelse return false;
        set_fn(text.ptr, text.len);
        return true;
    }

    /// Reads an image (screenshot `public.png` / `public.tiff` or copied image file `public.file-url`)
    /// from the native system clipboard (`NSPasteboard`) and allocates its bytes in `allocator`.
    pub fn getClipboardImageAlloc(self: *const PlatformContext, allocator: std.mem.Allocator) ?ClipboardImage {
        if (g_test_clipboard_image) |mock| {
            return .{
                .data = allocator.dupe(u8, mock.data) catch return null,
                .mime_type = allocator.dupe(u8, mock.mime_type) catch return null,
                .source_path = if (mock.source_path.len > 0) (allocator.dupe(u8, mock.source_path) catch return null) else "",
                .filename = allocator.dupe(u8, mock.filename) catch return null,
            };
        }
        if (self.host_get_clipboard == null) return null;
        if (comptime builtin.os.tag == .macos) {
            return readMacPasteboardImageAlloc(allocator);
        }
        return null;
    }

    /// Opens a native OS folder-picker modal dialog (e.g. `NSOpenPanel` on macOS) and copies
    /// the selected directory's UTF-8 path into `out_buf`. Returns `null` if cancelled or unsupported.
    pub fn pickFolder(self: *const PlatformContext, out_buf: []u8) ?[]const u8 {
        if (g_test_picked_folder) |mock_path| {
            if (out_buf.len == 0 or mock_path.len == 0) return null;
            const n = @min(mock_path.len, out_buf.len);
            @memcpy(out_buf[0..n], mock_path[0..n]);
            return out_buf[0..n];
        }
        const pick_fn = self.host_pick_folder orelse return null;
        if (out_buf.len == 0) return null;
        const n = pick_fn(out_buf.ptr, out_buf.len);
        if (n == 0) return null;
        return out_buf[0..@min(n, out_buf.len)];
    }

    /// Alias for `pickFolder`.
    pub fn pickFolderDialog(self: *const PlatformContext, buf: []u8) ?[]const u8 {
        return self.pickFolder(buf);
    }

    /// Opens a native OS file-open modal dialog (e.g. `NSOpenPanel` on macOS) and copies
    /// the selected file's UTF-8 path into `out_buf`. Returns `null` if cancelled or unsupported.
    pub fn pickFile(self: *const PlatformContext, out_buf: []u8) ?[]const u8 {
        if (g_test_picked_file) |mock_path| {
            if (out_buf.len == 0 or mock_path.len == 0) return null;
            const n = @min(mock_path.len, out_buf.len);
            @memcpy(out_buf[0..n], mock_path[0..n]);
            return out_buf[0..n];
        }
        const pick_fn = self.host_pick_file orelse return null;
        if (out_buf.len == 0) return null;
        const n = pick_fn(out_buf.ptr, out_buf.len);
        if (n == 0) return null;
        return out_buf[0..@min(n, out_buf.len)];
    }

    /// Alias for `pickFile`.
    pub fn pickFileDialog(self: *const PlatformContext, buf: []u8) ?[]const u8 {
        return self.pickFile(buf);
    }

    /// Opens a native OS file-save modal dialog (e.g. `NSSavePanel` on macOS) and copies
    /// the chosen destination UTF-8 path into `out_buf`. Returns `null` if cancelled or unsupported.
    pub fn saveFile(self: *const PlatformContext, out_buf: []u8) ?[]const u8 {
        if (g_test_saved_file) |mock_path| {
            if (out_buf.len == 0 or mock_path.len == 0) return null;
            const n = @min(mock_path.len, out_buf.len);
            @memcpy(out_buf[0..n], mock_path[0..n]);
            return out_buf[0..n];
        }
        const save_fn = self.host_save_file orelse return null;
        if (out_buf.len == 0) return null;
        const n = save_fn(out_buf.ptr, out_buf.len);
        if (n == 0) return null;
        return out_buf[0..@min(n, out_buf.len)];
    }

    /// Alias for `saveFile`.
    pub fn saveFileDialog(self: *const PlatformContext, buf: []u8) ?[]const u8 {
        return self.saveFile(buf);
    }

    /// Serialize any Zig value `T` as JSON into the Host's reload-boundary snapshot buffer.
    /// Call this inside `app_before_reload` before the old `.dylib` is unloaded.
    pub fn saveSnapshotJson(self: *PlatformContext, allocator: std.mem.Allocator, value: anytype) !void {
        const snap = self.snapshot_buffer orelse return;
        const write_fn = self.host_write_snapshot orelse return;

        var out: std.Io.Writer.Allocating = .init(allocator);
        defer out.deinit();

        try std.json.Stringify.value(value, .{}, &out.writer);
        const written = out.written();
        write_fn(snap, written.ptr, written.len);
    }

    /// Deserialize a Zig struct `T` from the Host's reload-boundary JSON buffer with
    /// `.ignore_unknown_fields = true` so added fields use their defaults and removed fields are ignored.
    pub fn loadSnapshotJson(self: *const PlatformContext, comptime T: type, allocator: std.mem.Allocator) ?T {
        const snap = self.snapshot_buffer orelse return null;
        const read_fn = self.host_read_snapshot orelse return null;

        var len: usize = 0;
        const ptr = read_fn(snap, &len) orelse return null;
        if (len == 0) return null;

        const parsed = std.json.parseFromSlice(
            T,
            allocator,
            ptr[0..len],
            .{ .ignore_unknown_fields = true, .allocate = .alloc_always },
        ) catch return null;
        defer parsed.deinit();
        return parsed.value;
    }
};

// ============================================================================
// Host-Side Callback Implementations
// ============================================================================

fn hostPushScopeImpl(store_opaque: *anyopaque, name_ptr: [*]const u8, name_len: usize) callconv(.c) void {
    const store: *StateStore = @ptrCast(@alignCast(store_opaque));
    store.pushScope(name_ptr[0..name_len]);
}

fn hostPopScopeImpl(store_opaque: *anyopaque) callconv(.c) void {
    const store: *StateStore = @ptrCast(@alignCast(store_opaque));
    store.popScope();
}

fn hostResetScopesImpl(store_opaque: *anyopaque) callconv(.c) void {
    const store: *StateStore = @ptrCast(@alignCast(store_opaque));
    store.resetScopes();
}

fn hostUseStateRawImpl(
    store_opaque: *anyopaque,
    key_ptr: [*]const u8,
    key_len: usize,
    size: usize,
    alignment_log2: u8,
    type_hash: u64,
    initialized_out: *bool,
) callconv(.c) [*]u8 {
    const store: *StateStore = @ptrCast(@alignCast(store_opaque));
    return store.getOrAllocRaw(key_ptr[0..key_len], size, alignment_log2, type_hash, initialized_out);
}

fn hostRemoveStateImpl(store_opaque: *anyopaque, key_ptr: [*]const u8, key_len: usize) callconv(.c) bool {
    const store: *StateStore = @ptrCast(@alignCast(store_opaque));
    return store.remove(key_ptr[0..key_len]);
}

fn hostStateCountImpl(store_opaque: *const anyopaque) callconv(.c) usize {
    const store: *const StateStore = @ptrCast(@alignCast(store_opaque));
    return store.count();
}

fn hostWriteSnapshotImpl(snap_opaque: *anyopaque, ptr: [*]const u8, len: usize) callconv(.c) void {
    const snap: *SnapshotBuffer = @ptrCast(@alignCast(snap_opaque));
    snap.write(ptr[0..len]);
}

fn hostReadSnapshotImpl(snap_opaque: *const anyopaque, len_out: *usize) callconv(.c) ?[*]const u8 {
    const snap: *const SnapshotBuffer = @ptrCast(@alignCast(snap_opaque));
    const s = snap.slice();
    len_out.* = s.len;
    return if (s.len > 0) s.ptr else null;
}

fn endsWithIgnoreCaseAscii(haystack: []const u8, suffix: []const u8) bool {
    if (haystack.len < suffix.len) return false;
    return std.ascii.eqlIgnoreCase(haystack[haystack.len - suffix.len ..], suffix);
}

pub fn detectImageMimeFromPath(path: []const u8) ?[]const u8 {
    if (endsWithIgnoreCaseAscii(path, ".png")) return "image/png";
    if (endsWithIgnoreCaseAscii(path, ".jpg") or endsWithIgnoreCaseAscii(path, ".jpeg")) return "image/jpeg";
    if (endsWithIgnoreCaseAscii(path, ".webp")) return "image/webp";
    if (endsWithIgnoreCaseAscii(path, ".gif")) return "image/gif";
    if (endsWithIgnoreCaseAscii(path, ".bmp")) return "image/bmp";
    return null;
}

fn readDiskFileBytesAlloc(allocator: std.mem.Allocator, file_path: []const u8, max_bytes: usize) ?[]const u8 {
    if (file_path.len == 0 or file_path.len >= 500) return null;
    var path_z: [512:0]u8 = @splat(0);
    @memcpy(path_z[0..file_path.len], file_path);
    path_z[file_path.len] = 0;

    const sz = fs_util.regularFileSizeOnDisk(&path_z) orelse return null;
    if (sz == 0 or sz > max_bytes) return null;

    const fp = std.c.fopen(&path_z, "rb") orelse return null;
    defer _ = std.c.fclose(fp);

    const buf = allocator.alloc(u8, sz) catch return null;
    const n = std.c.fread(buf.ptr, 1, sz, fp);
    if (n == 0) return null;
    return buf[0..n];
}

fn readMacPasteboardImageAlloc(allocator: std.mem.Allocator) ?ClipboardImage {
    const max_image_bytes: usize = 20 * 1024 * 1024;
    const pool = objc.objc_autoreleasePoolPush();
    defer objc.objc_autoreleasePoolPop(pool);

    const NSPasteboard = objc.objc_getClass("NSPasteboard");
    if (NSPasteboard == null) return null;
    const pb = objc.msgSend0(NSPasteboard, objc.id, "generalPasteboard");
    if (pb == null) return null;

    // 1. Check if a file URL was copied in Finder (`public.file-url`).
    //    When any file is copied in Finder, macOS also places the file's generic Finder icon into
    //    `public.tiff`. Checking `public.file-url` first ensures we read the actual image file when
    //    an image file is copied, and return `null` (falling back to text paste) when a non-image
    //    file is copied in Finder.
    const file_url_str = objc.msgSend1(pb, objc.id, "stringForType:", objc.nsString("public.file-url"));
    if (file_url_str != null) {
        const NSURL = objc.objc_getClass("NSURL");
        if (NSURL != null) {
            const ns_url = objc.msgSend1(NSURL, objc.id, "URLFromPasteboard:", pb);
            if (ns_url != null) {
                const path_ns = objc.msgSend0(ns_url, objc.id, "path");
                if (path_ns != null) {
                    if (objc.msgSend0(path_ns, ?[*:0]const u8, "UTF8String")) |c_path| {
                        const path_slice = std.mem.span(c_path);
                        if (detectImageMimeFromPath(path_slice)) |mime| {
                            if (readDiskFileBytesAlloc(allocator, path_slice, max_image_bytes)) |file_bytes| {
                                const src_copy = allocator.dupe(u8, path_slice) catch return null;
                                const base = std.fs.path.basename(src_copy);
                                return .{
                                    .data = file_bytes,
                                    .mime_type = mime,
                                    .source_path = src_copy,
                                    .filename = if (base.len > 0) base else "image.png",
                                };
                            }
                        }
                    }
                }
            }
        }
        return null;
    }

    // 2. Direct PNG image data on `NSPasteboard` (`public.png` — macOS screenshots, browsers, Preview)
    const png_data = objc.msgSend1(pb, objc.id, "dataForType:", objc.nsString("public.png"));
    if (png_data != null) {
        const len = objc.msgSend0(png_data, usize, "length");
        const ptr = objc.msgSend0(png_data, ?[*]const u8, "bytes");
        if (len > 0 and len <= max_image_bytes and ptr != null) {
            const duped = allocator.dupe(u8, ptr.?[0..len]) catch return null;
            return .{
                .data = duped,
                .mime_type = "image/png",
                .source_path = "",
                .filename = "screenshot.png",
            };
        }
    }

    // 3. Direct JPEG image data on `NSPasteboard` (`public.jpeg`)
    const jpeg_data = objc.msgSend1(pb, objc.id, "dataForType:", objc.nsString("public.jpeg"));
    if (jpeg_data != null) {
        const len = objc.msgSend0(jpeg_data, usize, "length");
        const ptr = objc.msgSend0(jpeg_data, ?[*]const u8, "bytes");
        if (len > 0 and len <= max_image_bytes and ptr != null) {
            const duped = allocator.dupe(u8, ptr.?[0..len]) catch return null;
            return .{
                .data = duped,
                .mime_type = "image/jpeg",
                .source_path = "",
                .filename = "clipboard.jpg",
            };
        }
    }

    // 4. TIFF image data on `NSPasteboard` (`public.tiff`), converted to PNG via `NSBitmapImageRep`
    const tiff_data = objc.msgSend1(pb, objc.id, "dataForType:", objc.nsString("public.tiff"));
    if (tiff_data != null) {
        const NSBitmapImageRep = objc.objc_getClass("NSBitmapImageRep");
        const NSDictionary = objc.objc_getClass("NSDictionary");
        if (NSBitmapImageRep != null and NSDictionary != null) {
            const rep = objc.msgSend1(NSBitmapImageRep, objc.id, "imageRepWithData:", tiff_data);
            if (rep != null) {
                const empty_dict = objc.msgSend0(NSDictionary, objc.id, "dictionary");
                // NSBitmapImageFileTypePNG = 4
                const converted_png = objc.msgSend2(
                    rep,
                    objc.id,
                    "representationUsingType:properties:",
                    @as(usize, 4),
                    empty_dict,
                );
                if (converted_png != null) {
                    const len = objc.msgSend0(converted_png, usize, "length");
                    const ptr = objc.msgSend0(converted_png, ?[*]const u8, "bytes");
                    if (len > 0 and len <= max_image_bytes and ptr != null) {
                        const duped = allocator.dupe(u8, ptr.?[0..len]) catch return null;
                        return .{
                            .data = duped,
                            .mime_type = "image/png",
                            .source_path = "",
                            .filename = "screenshot.png",
                        };
                    }
                }
            }
        }
    }

    return null;
}

// ============================================================================
// Plugin `.dylib` Exported Lifecycle Signatures
// ============================================================================

pub const AppInitFn = *const fn (ctx: *PlatformContext) callconv(.c) void;
/// Optional hook called on the old `.dylib` right before `dlclose` to serialize global state to JSON
/// and release `.dylib`-owned Skia resources.
pub const AppBeforeReloadFn = *const fn (ctx: *PlatformContext) callconv(.c) void;
/// Hook called on the newly loaded `.dylib` right after `dlopen` to restore global state from JSON.
pub const AppOnReloadFn = *const fn (ctx: *PlatformContext) callconv(.c) void;
/// Returns `true` if any dirty region was painted into `ctx.canvas`, or `false` if the frame was a no-op.
pub const AppTickFn = *const fn (ctx: *PlatformContext) callconv(.c) bool;
pub const AppDeinitFn = *const fn (ctx: *PlatformContext) callconv(.c) void;

test "PlatformContext JSON boundary serialization tolerates added and removed struct fields" {
    var store = StateStore.init(std.testing.allocator);
    defer store.deinit();

    var snap = SnapshotBuffer.init(std.testing.allocator);
    defer snap.deinit();

    var ctx = PlatformContext{};
    ctx.bindHostStores(&store, &snap);

    const DocumentV1 = struct {
        zoom: f32 = 1.0,
        show_grid: bool = true,
        obsolete_flag: i32 = 99,
    };

    const DocumentV2 = struct {
        zoom: f32 = 1.0,
        show_grid: bool = true,
        // `obsolete_flag` removed, `author_tag` added with default value!
        new_feature_enabled: bool = true,
        default_rings: u32 = 6,
    };

    // Simulate app_before_reload saving DocumentV1
    const doc_v1 = DocumentV1{ .zoom = 1.75, .show_grid = false, .obsolete_flag = 123 };
    try ctx.saveSnapshotJson(std.testing.allocator, doc_v1);

    // Simulate app_on_reload loading into DocumentV2
    const doc_v2 = ctx.loadSnapshotJson(DocumentV2, std.testing.allocator).?;
    try std.testing.expectEqual(@as(f32, 1.75), doc_v2.zoom);
    try std.testing.expectEqual(false, doc_v2.show_grid);
    try std.testing.expectEqual(true, doc_v2.new_feature_enabled);
    try std.testing.expectEqual(@as(u32, 6), doc_v2.default_rings);
}

test "PlatformContext pickFolder, pickFile, saveFile headless hooks and CursorShape variants" {
    const ctx = PlatformContext{};
    var buf: [256]u8 = undefined;

    // Without hooks or test overrides, dialogs return null
    try std.testing.expect(ctx.pickFolder(&buf) == null);
    try std.testing.expect(ctx.pickFile(&buf) == null);
    try std.testing.expect(ctx.saveFile(&buf) == null);

    // Test setTestPickedFolder
    setTestPickedFolder("/tmp/workspace_dir");
    defer setTestPickedFolder(null);
    try std.testing.expectEqualStrings("/tmp/workspace_dir", ctx.pickFolder(&buf).?);
    try std.testing.expectEqualStrings("/tmp/workspace_dir", ctx.pickFolderDialog(&buf).?);

    // Test setTestPickedFile
    setTestPickedFile("/tmp/workspace_dir/board.kicad_pcb");
    defer setTestPickedFile(null);
    try std.testing.expectEqualStrings("/tmp/workspace_dir/board.kicad_pcb", ctx.pickFile(&buf).?);
    try std.testing.expectEqualStrings("/tmp/workspace_dir/board.kicad_pcb", ctx.pickFileDialog(&buf).?);

    // Test setTestSavedFile
    setTestSavedFile("/tmp/workspace_dir/export.dsn");
    defer setTestSavedFile(null);
    try std.testing.expectEqualStrings("/tmp/workspace_dir/export.dsn", ctx.saveFile(&buf).?);
    try std.testing.expectEqualStrings("/tmp/workspace_dir/export.dsn", ctx.saveFileDialog(&buf).?);

    // Verify all CursorShape enum variants
    const shapes = [_]CursorShape{
        .arrow,
        .pointing_hand,
        .ibeam,
        .resize_ew,
        .resize_ns,
        .crosshair,
        .grab,
        .grabbing,
        .not_allowed,
    };
    try std.testing.expectEqual(@as(usize, 9), shapes.len);
}


