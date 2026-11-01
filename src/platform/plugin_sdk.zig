//! Ergonomic, zero-overhead Zig Authoring SDK for Editor Plugins (`EditorPluginV1`).
//!
//! Wraps the C-ABI `EditorHostApiV1` and `PluginUiApiV1` vtables in idiomatic Zig types,
//! providing:
//!   - `ctx.allocator()` & `ctx.fmt(...)` backed by the host's O(1) per-frame arena.
//!   - `ctx.useState(T, key, default)` backed by the host's hot-reload-safe `StateStore`.
//!   - `ctx.activeBuffer()`, `ctx.replaceBufferRange(...)`, `ctx.registerCommand(...)`.
//!   - `ctx.ui.*` declarative 2-phase widgets sharing the host's `TextCache` and `DamageList`.
//!   - `exportEditorPlugin(spec)` to generate the C-ABI `editor_plugin_entry_v1` export.

const std = @import("std");
pub const abi = @import("plugin_abi.zig");
pub const fs_util = @import("fs_util.zig");
pub const lsp = @import("lsp_client.zig");
pub const posix_poller = @import("posix_poller.zig");
const state_store = @import("state_store.zig");

pub const InlineString = state_store.InlineString;
pub const computeTypeHash = state_store.computeTypeHash;
pub const SubprocessPoller = posix_poller.SubprocessPoller;
pub const TextFieldResultFlags = abi.TextFieldResultFlags;
pub const SectionHeaderResultFlags = abi.SectionHeaderResultFlags;
pub const ListItemResultFlags = abi.ListItemResultFlags;
pub const PluginSidebarIcon = abi.PluginSidebarIcon;
pub const PluginToolbarIcon = abi.PluginToolbarIcon;
pub const LineRange = abi.LineRangeV1;
pub const BufferEditEvent = abi.BufferEditEventV1;
pub const CompletionItem = abi.CompletionItemV1;
pub const Breakpoint = abi.BreakpointV1;
pub const GitAction = abi.GitActionV1;
pub const GitFileStatus = abi.GitFileStatusV1;
pub const GitCommit = abi.GitCommitV1;
pub const GitStatusSnapshot = abi.GitStatusSnapshotV1;

pub const ListItemAccent = enum(u8) {
    default = 0,
    staged_green = 1,
    modified_amber = 2,
    info_cyan = 3,
};

pub const ListItemExOptions = struct {
    label: []const u8,
    meta: []const u8 = "",
    icon_text: []const u8 = "",
    action_label: []const u8 = "",
    secondary_action_label: []const u8 = "",
    indent_level: u8 = 0,
    selected: bool = false,
    accent: ListItemAccent = .default,
};

pub const BufferInfo = struct {
    buffer_id: u32,
    file_path: []const u8,
    text: []const u8,
    line_count: u32,
    cursor_offset: usize,
    selection_anchor: usize,
    cursor_line: u32,
    cursor_col: u32,
    edit_version: u32,
    is_dirty: bool,

    pub fn fromAbi(raw: abi.BufferInfoV1) BufferInfo {
        return .{
            .buffer_id = raw.buffer_id,
            .file_path = raw.file_path.toZig(),
            .text = raw.text.toZig(),
            .line_count = raw.line_count,
            .cursor_offset = raw.cursor_offset,
            .selection_anchor = raw.selection_anchor,
            .cursor_line = raw.cursor_line,
            .cursor_col = raw.cursor_col,
            .edit_version = raw.edit_version,
            .is_dirty = raw.is_dirty,
        };
    }
};

pub const UiBuilder = struct {
    host: *anyopaque,
    vtable: *const abi.PluginUiApiV1,

    pub fn isInputPass(self: UiBuilder) bool {
        return self.vtable.get_pass(self.host) == 0;
    }

    pub fn isPaintPass(self: UiBuilder) bool {
        return self.vtable.get_pass(self.host) == 1;
    }

    pub fn beginColumn(self: UiBuilder, w: f32, h: f32, pad: f32, gap: f32) void {
        self.vtable.begin_column(self.host, w, h, pad, gap);
    }

    pub fn beginRow(self: UiBuilder, w: f32, h: f32, pad: f32, gap: f32) void {
        self.vtable.begin_row(self.host, w, h, pad, gap);
    }

    pub fn endBox(self: UiBuilder) void {
        self.vtable.end_box(self.host);
    }

    pub fn beginScrollPanel(self: UiBuilder, id: []const u8, w: f32, h: f32, pad: f32, gap: f32) void {
        self.vtable.begin_scroll_panel(self.host, abi.AbiSlice.fromZig(id), w, h, pad, gap);
    }

    pub fn endScrollPanel(self: UiBuilder) void {
        self.vtable.end_scroll_panel(self.host);
    }

    pub fn spacer(self: UiBuilder, w: f32, h: f32) void {
        self.vtable.spacer(self.host, w, h);
    }

    pub fn divider(self: UiBuilder) void {
        self.vtable.divider(self.host);
    }

    pub fn pushId(self: UiBuilder, id: []const u8) void {
        self.vtable.push_id(self.host, abi.AbiSlice.fromZig(id));
    }

    pub fn popId(self: UiBuilder) void {
        self.vtable.pop_id(self.host);
    }

    pub fn label(self: UiBuilder, text: []const u8) void {
        self.vtable.label(self.host, abi.AbiSlice.fromZig(text), 0);
    }

    pub fn mutedLabel(self: UiBuilder, text: []const u8) void {
        self.vtable.label(self.host, abi.AbiSlice.fromZig(text), 1);
    }

    pub fn monoLabel(self: UiBuilder, text: []const u8) void {
        self.vtable.label(self.host, abi.AbiSlice.fromZig(text), 2);
    }

    pub fn sectionLabel(self: UiBuilder, text: []const u8) void {
        self.vtable.label(self.host, abi.AbiSlice.fromZig(text), 3);
    }

    pub fn button(self: UiBuilder, text: []const u8, w: f32, h: f32) bool {
        return self.vtable.button(self.host, abi.AbiSlice.fromZig(text), w, h);
    }

    pub fn toolbarIconBtn(self: UiBuilder, raw_label: []const u8, icon: PluginToolbarIcon, w: f32, h: f32, enabled: bool) bool {
        return self.vtable.toolbar_icon_btn(self.host, abi.AbiSlice.fromZig(raw_label), icon, w, h, enabled);
    }

    pub fn dropdownSelect(self: UiBuilder, raw_label: []const u8, display_text: []const u8, w: f32, h: f32, active_border: bool) bool {
        return self.vtable.dropdown_select(self.host, abi.AbiSlice.fromZig(raw_label), abi.AbiSlice.fromZig(display_text), w, h, active_border);
    }

    /// Reserves a floating dropdown overlay rectangle anchored directly beneath the last `dropdownSelect`
    /// widget, blocks hover/click events from reaching underlying widgets covered by the menu during
    /// `Pass.input`, and returns `true` if the user clicked outside the dropdown or pressed `Escape`.
    pub fn reserveDropdownOverlay(self: UiBuilder, height: f32) bool {
        return self.vtable.reserve_dropdown_overlay(self.host, height);
    }

    /// Begins laying out and painting the reserved floating dropdown menu overlay on top of prior content.
    pub fn beginDropdownOverlay(self: UiBuilder) void {
        self.vtable.begin_dropdown_overlay(self.host);
    }

    /// Ends a floating dropdown menu overlay started with `beginDropdownOverlay`.
    pub fn endDropdownOverlay(self: UiBuilder) void {
        self.vtable.end_dropdown_overlay(self.host);
    }

    pub fn collapsibleSection(self: UiBuilder, raw_label: []const u8, expanded: *bool, badge_text: []const u8) bool {
        return self.vtable.collapsible_section(self.host, abi.AbiSlice.fromZig(raw_label), expanded, abi.AbiSlice.fromZig(badge_text));
    }

    pub fn collapsibleSectionWithAction(
        self: UiBuilder,
        raw_label: []const u8,
        expanded: *bool,
        badge_text: []const u8,
        action_label: []const u8,
    ) SectionHeaderResultFlags {
        const raw = self.vtable.collapsible_section_with_action(
            self.host,
            abi.AbiSlice.fromZig(raw_label),
            expanded,
            abi.AbiSlice.fromZig(badge_text),
            abi.AbiSlice.fromZig(action_label),
        );
        return @bitCast(raw);
    }

    pub fn treeFolderNode(
        self: UiBuilder,
        raw_label: []const u8,
        indent_level: u8,
        expanded: *bool,
        meta: []const u8,
    ) bool {
        return self.vtable.tree_folder_node(
            self.host,
            abi.AbiSlice.fromZig(raw_label),
            indent_level,
            expanded,
            abi.AbiSlice.fromZig(meta),
        );
    }

    pub fn chip(self: UiBuilder, text: []const u8, active: bool) bool {
        return self.vtable.chip(self.host, abi.AbiSlice.fromZig(text), active);
    }

    pub fn listItem(self: UiBuilder, text: []const u8, meta: []const u8, selected: bool) bool {
        return self.vtable.list_item(self.host, abi.AbiSlice.fromZig(text), abi.AbiSlice.fromZig(meta), selected);
    }

    pub fn listItemEx(self: UiBuilder, opts: ListItemExOptions) ListItemResultFlags {
        const raw = self.vtable.list_item_ex(
            self.host,
            abi.AbiSlice.fromZig(opts.label),
            abi.AbiSlice.fromZig(opts.meta),
            abi.AbiSlice.fromZig(opts.icon_text),
            abi.AbiSlice.fromZig(opts.action_label),
            abi.AbiSlice.fromZig(opts.secondary_action_label),
            opts.indent_level,
            opts.selected,
            @intFromEnum(opts.accent),
        );
        return @bitCast(raw);
    }

    pub fn textField(self: UiBuilder, id: []const u8, buf: []u8, len: *usize, placeholder: []const u8) TextFieldResultFlags {
        const raw = self.vtable.text_field(
            self.host,
            abi.AbiSlice.fromZig(id),
            buf.ptr,
            len,
            buf.len,
            abi.AbiSlice.fromZig(placeholder),
        );
        return @bitCast(raw);
    }

    pub fn textFieldInline(self: UiBuilder, id: []const u8, inline_str: anytype, placeholder: []const u8) TextFieldResultFlags {
        return self.textField(id, &inline_str.buf, &inline_str.len, placeholder);
    }

    pub fn textArea(self: UiBuilder, id: []const u8, buf: []u8, len: *usize, placeholder: []const u8, height: f32) TextFieldResultFlags {
        const raw = self.vtable.text_area(
            self.host,
            abi.AbiSlice.fromZig(id),
            buf.ptr,
            len,
            buf.len,
            abi.AbiSlice.fromZig(placeholder),
            height,
        );
        return @bitCast(raw);
    }

    pub fn textAreaInline(self: UiBuilder, id: []const u8, inline_str: anytype, placeholder: []const u8, height: f32) TextFieldResultFlags {
        return self.textArea(id, &inline_str.buf, &inline_str.len, placeholder, height);
    }

    pub fn markdown(self: UiBuilder, source: []const u8) void {
        self.vtable.markdown(self.host, abi.AbiSlice.fromZig(source));
    }

    /// Renders an interactive 2-phase hardware-accelerated digital waveform & VCD logic analyzer.
    /// Pass `""` for `vcd_source` to automatically parse the active `.vcd` buffer or display the built-in RTL trace.
    pub fn waveform(self: UiBuilder, id: []const u8, vcd_source: []const u8, height: f32) void {
        self.vtable.waveform_view(self.host, abi.AbiSlice.fromZig(id), abi.AbiSlice.fromZig(vcd_source), height);
    }

    /// Renders an interactive 2-phase PDF page viewer & text inspector.
    /// Pass `""` for `file_path` and `raw_bytes` to automatically render the active `.pdf` buffer or built-in datasheet.
    pub fn pdfView(self: UiBuilder, id: []const u8, file_path: []const u8, raw_bytes: []const u8, height: f32) void {
        self.vtable.pdf_view(
            self.host,
            abi.AbiSlice.fromZig(id),
            abi.AbiSlice.fromZig(file_path),
            abi.AbiSlice.fromZig(raw_bytes),
            height,
        );
    }
};

pub const PluginContext = struct {
    host: *anyopaque,
    api: *const abi.EditorHostApiV1,
    ui: UiBuilder,

    pub fn init(host: *anyopaque, api: *const abi.EditorHostApiV1) PluginContext {
        return .{
            .host = host,
            .api = api,
            .ui = .{
                .host = host,
                .vtable = api.ui,
            },
        };
    }

    /// Returns a `std.mem.Allocator` backed by the host's O(1) per-frame arena.
    pub fn allocator(self: *PluginContext) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &frame_alloc_vtable,
        };
    }

    const frame_alloc_vtable = std.mem.Allocator.VTable{
        .alloc = frameAllocImpl,
        .resize = std.mem.Allocator.noResize,
        .remap = std.mem.Allocator.noRemap,
        .free = std.mem.Allocator.noFree,
    };

    fn frameAllocImpl(ctx_opaque: *anyopaque, len: usize, alignment: std.mem.Alignment, _: usize) ?[*]u8 {
        const self: *PluginContext = @ptrCast(@alignCast(ctx_opaque));
        return self.api.frame_alloc(self.host, len, @intFromEnum(alignment));
    }

    /// Formats a temporary string into the host's per-frame arena (valid for the current frame).
    pub fn fmt(self: *PluginContext, comptime format: []const u8, args: anytype) []const u8 {
        return std.fmt.allocPrint(self.allocator(), format, args) catch "";
    }

    /// Retrieves or initializes persistent plugin state in the host's `StateStore`.
    /// Automatically scoped to `"plugin:<plugin_id>"` and preserved across `.dylib` hot-reloads!
    pub fn useState(self: *PluginContext, comptime T: type, key: []const u8, default: T) *T {
        comptime {
            if (T == []const u8 or T == []u8) {
                @compileError("Do not store raw []const u8 slices in useState (causes .rodata segfault on dlclose). Use sdk.InlineString(N) instead.");
            }
        }
        var initialized = false;
        const raw_ptr = self.api.use_state_raw(
            self.host,
            abi.AbiSlice.fromZig(key),
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

    pub fn activeBuffer(self: *PluginContext) ?BufferInfo {
        var raw = abi.BufferInfoV1{};
        if (!self.api.get_active_buffer(self.host, &raw)) return null;
        return BufferInfo.fromAbi(raw);
    }

    pub fn lineRange(self: *PluginContext, buffer_id: u32, line_idx: u32) LineRange {
        return self.api.get_line_range(self.host, buffer_id, line_idx);
    }

    pub fn offsetToLineCol(self: *PluginContext, buffer_id: u32, offset: usize) struct { line: u32, col: u32 } {
        var l: u32 = 0;
        var c: u32 = 0;
        self.api.offset_to_line_col(self.host, buffer_id, offset, &l, &c);
        return .{ .line = l, .col = c };
    }

    pub fn replaceBufferRange(self: *PluginContext, buffer_id: u32, start: usize, end: usize, new_text: []const u8) bool {
        return self.api.replace_buffer_range(self.host, buffer_id, start, end, abi.AbiSlice.fromZig(new_text));
    }

    pub fn setCursorAndScroll(self: *PluginContext, buffer_id: u32, cursor: usize, anchor: usize) void {
        self.api.set_cursor_and_scroll(self.host, buffer_id, cursor, anchor);
    }

    pub fn registerCommand(self: *PluginContext, cmd_id: []const u8, title: []const u8, category: []const u8, shortcut_hint: []const u8) void {
        _ = self.api.register_command(
            self.host,
            abi.AbiSlice.fromZig(cmd_id),
            abi.AbiSlice.fromZig(title),
            abi.AbiSlice.fromZig(category),
            abi.AbiSlice.fromZig(shortcut_hint),
        );
    }

    pub fn setStatusNotice(self: *PluginContext, msg: []const u8) void {
        self.api.set_status_notice(self.host, abi.AbiSlice.fromZig(msg));
    }

    pub fn setCompletions(self: *PluginContext, buffer_id: u32, cursor_offset: usize, items: []const CompletionItem) void {
        self.api.set_completions(
            self.host,
            buffer_id,
            cursor_offset,
            if (items.len > 0) items.ptr else null,
            items.len,
        );
    }

    /// Opens the `*Waveform Preview*` editor buffer (either in the active split pane or split to the side,
    /// matching how `*Markdown Preview*` works). Pass `""` for `vcd_source` to preview the active `.vcd` buffer.
    pub fn openWaveformPreview(self: *PluginContext, vcd_source: []const u8, split_to_side: bool) void {
        self.api.open_waveform_preview(self.host, abi.AbiSlice.fromZig(vcd_source), split_to_side);
    }

    /// Opens the `*PDF Preview*` editor buffer (either in the active split pane or split to the side).
    /// Pass `""` for `file_path` and `raw_bytes` to preview the active `.pdf` buffer or built-in datasheet.
    pub fn openPdfPreview(self: *PluginContext, file_path: []const u8, raw_bytes: []const u8, split_to_side: bool) void {
        self.api.open_pdf_preview(
            self.host,
            abi.AbiSlice.fromZig(file_path),
            abi.AbiSlice.fromZig(raw_bytes),
            split_to_side,
        );
    }

    /// Opens the `*Git Diff*` editor buffer for `file_path` (working-tree diff when `staged == false`,
    /// `--cached` staged diff when `staged == true`, or commit diff when `commit_sha` is non-empty).
    pub fn openGitDiff(self: *PluginContext, file_path: []const u8, commit_sha: []const u8, staged: bool, split_to_side: bool) void {
        self.api.open_git_diff(
            self.host,
            abi.AbiSlice.fromZig(file_path),
            abi.AbiSlice.fromZig(commit_sha),
            staged,
            split_to_side,
        );
    }

    /// Opens a workspace file by relative path (e.g. `.vscode/launch.json` or `.vscode/tasks.json`) in the active editor pane.
    pub fn openFilePath(self: *PluginContext, path: []const u8) bool {
        return self.api.open_file_path(self.host, abi.AbiSlice.fromZig(path));
    }

    /// Synchronizes open host buffers with Git working-tree operations (`save_dirty` before stage/commit,
    /// `reload_from_disk` after discarding changes, and triggers a host git status refresh).
    pub fn syncWorkspaceGit(self: *PluginContext, save_dirty: bool, reload_from_disk: bool) void {
        self.api.sync_workspace_git(self.host, save_dirty, reload_from_disk);
    }

    /// Queries the host's memoized Git status snapshot (current branch, changed files, and recent commit history).
    pub fn getGitStatus(self: *PluginContext, out: *GitStatusSnapshot) bool {
        return self.api.get_git_status(self.host, out);
    }

    /// Performs a Git working-tree action through the host (stage, unstage, stage_all, unstage_all, discard, commit, refresh).
    pub fn gitAction(self: *PluginContext, action: GitAction, path_or_msg: []const u8) bool {
        return self.api.git_action(self.host, action, abi.AbiSlice.fromZig(path_or_msg));
    }

    /// Sends a shell command to the integrated terminal (`state.vterm`) and shows the bottom panel.
    pub fn runTerminalCommand(self: *PluginContext, cmd: []const u8) void {
        self.api.run_terminal_command(self.host, abi.AbiSlice.fromZig(cmd));
    }

    pub fn toggleBottomPanel(self: *PluginContext) void {
        self.api.toggle_bottom_panel(self.host);
    }

    pub fn requestContinuousRedraw(self: *PluginContext) void {
        self.api.request_continuous_redraw(self.host);
    }

    /// Toggles a breakpoint at `line_1based` in `file_path` inside the shared host breakpoint store.
    /// Returns `true` if the breakpoint was added, `false` if it was cleared.
    pub fn toggleBreakpoint(self: *PluginContext, file_path: []const u8, line_1based: u32) bool {
        return self.api.toggle_breakpoint(self.host, abi.AbiSlice.fromZig(file_path), line_1based);
    }

    /// Clears all breakpoints in the shared host breakpoint store.
    pub fn clearBreakpoints(self: *PluginContext) void {
        self.api.clear_breakpoints(self.host);
    }

    /// Copies up to `out_buf.len` active breakpoints from the host into `out_buf`.
    pub fn getBreakpoints(self: *PluginContext, out_buf: []Breakpoint) []const Breakpoint {
        const count = self.api.get_breakpoints(
            self.host,
            if (out_buf.len > 0) out_buf.ptr else null,
            out_buf.len,
        );
        return out_buf[0..@min(count, out_buf.len)];
    }

    /// Updates the active debugger execution line highlight in the code editor and optionally opens/scrolls to `file_path:line_1based`.
    pub fn setDebugLocation(
        self: *PluginContext,
        active: bool,
        paused: bool,
        file_path: []const u8,
        line_1based: u32,
        jump_to_line: bool,
    ) void {
        self.api.set_debug_location(
            self.host,
            active,
            paused,
            abi.AbiSlice.fromZig(file_path),
            line_1based,
            jump_to_line,
        );
    }
};

pub const PluginSpec = struct {
    id: []const u8,
    display_name: []const u8,
    version: []const u8 = "0.1.0",
    sidebar_icon: PluginSidebarIcon = .none,
    sidebar_title: []const u8 = "",
    bottom_tab_title: []const u8 = "",
    debug_extensions: []const u8 = "",

    init: ?*const fn (ctx: *PluginContext) void = null,
    before_reload: ?*const fn (ctx: *PluginContext) void = null,
    on_reload: ?*const fn (ctx: *PluginContext) void = null,
    deinit: ?*const fn (ctx: *PluginContext) void = null,

    on_poll_io: ?*const fn (ctx: *PluginContext) void = null,
    on_command: ?*const fn (ctx: *PluginContext, cmd_id: []const u8) void = null,
    on_buffer_open: ?*const fn (ctx: *PluginContext, info: BufferInfo) void = null,
    on_buffer_edit: ?*const fn (ctx: *PluginContext, ev: BufferEditEvent) void = null,
    on_buffer_save: ?*const fn (ctx: *PluginContext, info: BufferInfo) void = null,

    render_sidebar: ?*const fn (ctx: *PluginContext) void = null,
    render_bottom_panel: ?*const fn (ctx: *PluginContext) void = null,
    render_status_bar: ?*const fn (ctx: *PluginContext) void = null,
};

/// Constructs a compile-time `abi.EditorPluginV1` descriptor from an idiomatic `PluginSpec`.
/// Can be registered directly in-memory for tests or exported from a `.dylib` via `exportEditorPlugin`.
pub fn createPluginDescriptor(comptime spec: PluginSpec) abi.EditorPluginV1 {
    const Wrapper = struct {
        fn wrapHook(comptime f: ?*const fn (*PluginContext) void) ?abi.PluginHookFn {
            const fn_ptr = f orelse return null;
            return &struct {
                fn cb(host: *anyopaque, api: *const abi.EditorHostApiV1) callconv(.c) void {
                    var ctx = PluginContext.init(host, api);
                    fn_ptr(&ctx);
                }
            }.cb;
        }

        fn wrapCommand(comptime f: ?*const fn (*PluginContext, []const u8) void) ?abi.PluginCommandFn {
            const fn_ptr = f orelse return null;
            return &struct {
                fn cb(host: *anyopaque, api: *const abi.EditorHostApiV1, cmd_id: abi.AbiSlice) callconv(.c) void {
                    var ctx = PluginContext.init(host, api);
                    fn_ptr(&ctx, cmd_id.toZig());
                }
            }.cb;
        }

        fn wrapBufferInfo(comptime f: ?*const fn (*PluginContext, BufferInfo) void) ?abi.PluginBufferInfoFn {
            const fn_ptr = f orelse return null;
            return &struct {
                fn cb(host: *anyopaque, api: *const abi.EditorHostApiV1, info: *const abi.BufferInfoV1) callconv(.c) void {
                    var ctx = PluginContext.init(host, api);
                    fn_ptr(&ctx, BufferInfo.fromAbi(info.*));
                }
            }.cb;
        }

        fn wrapBufferEdit(comptime f: ?*const fn (*PluginContext, BufferEditEvent) void) ?abi.PluginBufferEditFn {
            const fn_ptr = f orelse return null;
            return &struct {
                fn cb(host: *anyopaque, api: *const abi.EditorHostApiV1, ev: *const abi.BufferEditEventV1) callconv(.c) void {
                    var ctx = PluginContext.init(host, api);
                    fn_ptr(&ctx, ev.*);
                }
            }.cb;
        }
    };

    const caps = abi.PluginCapabilities{
        .commands = (spec.on_command != null),
        .buffer_hooks = (spec.on_buffer_open != null or spec.on_buffer_edit != null or spec.on_buffer_save != null),
        .sidebar_panel = (spec.render_sidebar != null),
        .bottom_panel = (spec.render_bottom_panel != null),
        .status_bar = (spec.render_status_bar != null),
        .background_poller = (spec.on_poll_io != null),
    };

    return .{
        .manifest = .{
            .abi_version = abi.EDITOR_PLUGIN_ABI_VERSION,
            .id = abi.AbiSlice.fromZig(spec.id),
            .display_name = abi.AbiSlice.fromZig(spec.display_name),
            .version = abi.AbiSlice.fromZig(spec.version),
            .capabilities = caps,
            .sidebar_icon = spec.sidebar_icon,
            .sidebar_title = abi.AbiSlice.fromZig(spec.sidebar_title),
            .bottom_tab_title = abi.AbiSlice.fromZig(spec.bottom_tab_title),
            .debug_extensions = abi.AbiSlice.fromZig(spec.debug_extensions),
        },
        .init = Wrapper.wrapHook(spec.init),
        .before_reload = Wrapper.wrapHook(spec.before_reload),
        .on_reload = Wrapper.wrapHook(spec.on_reload),
        .deinit = Wrapper.wrapHook(spec.deinit),
        .on_poll_io = Wrapper.wrapHook(spec.on_poll_io),
        .on_command = Wrapper.wrapCommand(spec.on_command),
        .on_buffer_open = Wrapper.wrapBufferInfo(spec.on_buffer_open),
        .on_buffer_edit = Wrapper.wrapBufferEdit(spec.on_buffer_edit),
        .on_buffer_save = Wrapper.wrapBufferInfo(spec.on_buffer_save),
        .render_sidebar = Wrapper.wrapHook(spec.render_sidebar),
        .render_bottom_panel = Wrapper.wrapHook(spec.render_bottom_panel),
        .render_status_bar = Wrapper.wrapHook(spec.render_status_bar),
    };
}

/// Comptime generator that exports `editor_plugin_entry_v1` for a standalone `.dylib` plugin.
pub fn exportEditorPlugin(comptime spec: PluginSpec) void {
    const Exported = struct {
        const descriptor: abi.EditorPluginV1 = createPluginDescriptor(spec);

        pub fn entry() callconv(.c) *const abi.EditorPluginV1 {
            return &descriptor;
        }
    };

    @export(&Exported.entry, .{ .name = abi.PLUGIN_ENTRY_SYMBOL, .linkage = .strong });
}

pub const LspCommandSpec = struct {
    id: []const u8,
    title: []const u8,
    category: []const u8,
    hint: []const u8 = "",
    snippet: []const u8 = "",
    notice: []const u8 = "",
    handler: ?*const fn (*PluginContext) void = null,
    btn_label: []const u8 = "",
    btn_width: f32 = 0,
};

pub const LspPluginSpec = struct {
    id: []const u8,
    display_name: []const u8,
    version: []const u8 = "0.1.0",
    sidebar_title: []const u8 = "",
    bottom_tab_title: []const u8 = "",
    language: lsp.LspLanguage,
    ready_status: []const u8 = "",
    format_indent: ?u8 = null,
    format_label: []const u8 = "Format",
    format_notice: []const u8 = "Formatted active buffer",
    commands: []const LspCommandSpec = &.{},
    is_buffer_match: ?*const fn (buf: BufferInfo) bool = null,
    custom_format: ?*const fn (*PluginContext, []const u8) ?[]const u8 = null,
    custom_on_command: ?*const fn (*PluginContext, []const u8) bool = null,
    custom_render_sidebar: ?*const fn (*PluginContext) void = null,
    render_bottom_panel: ?*const fn (*PluginContext) void = null,
    on_save_hook: ?*const fn (*PluginContext, BufferInfo) void = null,
};

/// High-level comptime template generator for standalone `.dylib` language server plugins.
/// Eliminates ~150 lines of repetitive LSP lifecycle, sync, completion, and diagnostic boilerplate.
pub fn exportLspLanguagePlugin(comptime spec: LspPluginSpec) void {
    const Gen = struct {
        pub fn getState(ctx: *PluginContext) *lsp.LspConnection {
            return ctx.useState(lsp.LspConnection, spec.id ++ "_state", .{ .language = spec.language });
        }

        fn isMatchingBuffer(buf: BufferInfo) bool {
            if (spec.is_buffer_match) |matcher| {
                return matcher(buf);
            }
            return spec.language.matchesBuffer(buf.file_path, buf.text);
        }

        fn formatActiveBuffer(ctx: *PluginContext) void {
            const buf = ctx.activeBuffer() orelse return;
            if (buf.text.len == 0) return;
            var formatted_opt: ?[]const u8 = null;
            if (spec.custom_format) |custom_fmt| {
                formatted_opt = custom_fmt(ctx, buf.text);
            } else if (spec.format_indent) |indent| {
                formatted_opt = lsp.formatBraceSource(ctx.allocator(), buf.text, indent) catch null;
            }
            if (formatted_opt) |formatted| {
                if (!std.mem.eql(u8, buf.text, formatted)) {
                    if (ctx.replaceBufferRange(buf.buffer_id, 0, buf.text.len, formatted)) {
                        ctx.setStatusNotice(spec.format_notice);
                    }
                }
            }
        }

        fn registerCommands(ctx: *PluginContext) void {
            if (spec.format_indent != null or spec.custom_format != null) {
                ctx.registerCommand(spec.id ++ ".format", spec.display_name ++ ": Format Active Buffer", spec.sidebar_title, spec.format_label);
            }
            for (spec.commands) |cmd| {
                ctx.registerCommand(cmd.id, cmd.title, cmd.category, cmd.hint);
            }
            ctx.registerCommand(spec.id ++ ".restart_server", spec.display_name ++ ": Start / Restart Language Server", spec.sidebar_title, "LSP");
        }

        fn onInit(ctx: *PluginContext) void {
            const st = getState(ctx);
            st.language = spec.language;
            if (st.server_status.len == 0 and spec.ready_status.len > 0) {
                st.server_status.set(spec.ready_status);
            }
            registerCommands(ctx);
        }

        fn onReload(ctx: *PluginContext) void {
            registerCommands(ctx);
        }

        fn onDeinit(ctx: *PluginContext) void {
            getState(ctx).stopServer();
        }

        fn onPollIo(ctx: *PluginContext) void {
            const st = getState(ctx);
            if (st.pollIo()) {
                if (st.completions_dirty) {
                    st.completions_dirty = false;
                    var abi_items: [lsp.MaxCompletions]CompletionItem = undefined;
                    const items = st.exportAbiCompletions(&abi_items);
                    ctx.setCompletions(st.completion_buffer_id, st.completion_cursor_offset, items);
                }
                ctx.requestContinuousRedraw();
            }
        }

        fn triggerCompletions(ctx: *PluginContext, buf: BufferInfo) void {
            const st = getState(ctx);
            const n = st.updateCompletionsForCursor(
                ctx.allocator(),
                buf.file_path,
                buf.text,
                buf.cursor_offset,
                buf.cursor_line,
                buf.cursor_col,
                buf.buffer_id,
            );
            var abi_items: [lsp.MaxCompletions]CompletionItem = undefined;
            const items = st.exportAbiCompletions(&abi_items);
            ctx.setCompletions(buf.buffer_id, buf.cursor_offset, items[0..n]);
            st.completions_dirty = false;
        }

        fn syncBuffer(ctx: *PluginContext, buf: BufferInfo) void {
            const st = getState(ctx);
            if (!st.probe_attempted and isMatchingBuffer(buf)) {
                _ = st.spawnServer(spec.language, null);
            }
            if (st.isRunning()) {
                st.notifyDocumentSync(ctx.allocator(), buf.file_path, buf.text, buf.edit_version);
            }
            if (!st.has_lsp_diagnostics) {
                st.diagnostic_count = lsp.scanLocalDiagnostics(buf.text, spec.language, &st.diagnostics);
            }
            st.last_synced_version = buf.edit_version;
            st.last_synced_buffer_id = buf.buffer_id;
        }

        fn onBufferOpen(ctx: *PluginContext, info: BufferInfo) void {
            if (isMatchingBuffer(info)) syncBuffer(ctx, info);
        }

        fn onBufferEdit(ctx: *PluginContext, _: BufferEditEvent) void {
            const buf = ctx.activeBuffer() orelse return;
            if (isMatchingBuffer(buf)) {
                syncBuffer(ctx, buf);
                triggerCompletions(ctx, buf);
            }
        }

        fn onBufferSave(ctx: *PluginContext, info: BufferInfo) void {
            if (!isMatchingBuffer(info)) return;
            const st = getState(ctx);
            if (st.isRunning()) st.notifyDocumentSave(ctx.allocator(), info.file_path);
            if (spec.on_save_hook) |hook| {
                hook(ctx, info);
            } else {
                syncBuffer(ctx, info);
            }
        }

        fn onCommand(ctx: *PluginContext, cmd_id: []const u8) void {
            if ((spec.format_indent != null or spec.custom_format != null) and std.mem.eql(u8, cmd_id, spec.id ++ ".format")) {
                formatActiveBuffer(ctx);
                return;
            }
            if (std.mem.eql(u8, cmd_id, spec.id ++ ".restart_server")) {
                _ = getState(ctx).spawnServer(spec.language, null);
                ctx.setStatusNotice(spec.display_name ++ ": Restarted server");
                return;
            }
            for (spec.commands) |cmd| {
                if (std.mem.eql(u8, cmd_id, cmd.id)) {
                    if (cmd.handler) |h| {
                        h(ctx);
                        return;
                    }
                    if (cmd.snippet.len > 0) {
                        const buf = ctx.activeBuffer() orelse return;
                        if (ctx.replaceBufferRange(buf.buffer_id, buf.cursor_offset, buf.cursor_offset, cmd.snippet)) {
                            if (cmd.notice.len > 0) ctx.setStatusNotice(cmd.notice);
                        }
                    }
                    return;
                }
            }
            if (spec.custom_on_command) |custom_cmd| {
                _ = custom_cmd(ctx, cmd_id);
            }
        }

        fn renderStatusBar(ctx: *PluginContext) void {
            const buf = ctx.activeBuffer() orelse return;
            if (!isMatchingBuffer(buf)) return;
            const st = getState(ctx);
            const mode = if (st.isRunning()) ctx.fmt("{s} ●", .{spec.language.serverBinary()}) else ctx.fmt("{s} AST ○", .{spec.language.languageId()});
            const chip_clicked = ctx.ui.chip(ctx.fmt("{s} ({d} diag)##{s}_chip", .{ mode, st.diagnostic_count, spec.id }), st.diagnostic_count == 0);
            if (chip_clicked and (spec.format_indent != null or spec.custom_format != null)) {
                formatActiveBuffer(ctx);
            }
        }

        fn jumpToLine(ctx: *PluginContext, buffer_id: u32, line_1based: u32) void {
            const idx = line_1based -| 1;
            const lr = ctx.lineRange(buffer_id, idx);
            ctx.setCursorAndScroll(buffer_id, lr.start, lr.start);
        }

        fn renderSidebar(ctx: *PluginContext) void {
            const st = getState(ctx);
            ctx.ui.divider();
            ctx.ui.sectionLabel(spec.sidebar_title);
            ctx.ui.monoLabel(ctx.fmt("Status: {s}", .{st.server_status.slice()}));

            if (spec.format_indent != null or spec.custom_format != null or spec.commands.len > 0) {
                ctx.ui.beginRow(0, 26, 0, 6);
                if (spec.format_indent != null or spec.custom_format != null) {
                    if (ctx.ui.button(ctx.fmt("{s}##{s}_fmt_btn", .{ spec.format_label, spec.id }), 84, 24)) {
                        formatActiveBuffer(ctx);
                    }
                }
                for (spec.commands) |cmd| {
                    if (cmd.btn_label.len > 0) {
                        const width = if (cmd.btn_width > 0) cmd.btn_width else 80;
                        if (ctx.ui.button(cmd.btn_label, width, 24)) {
                            if (cmd.handler) |h| {
                                h(ctx);
                            } else if (cmd.snippet.len > 0) {
                                const buf = ctx.activeBuffer() orelse continue;
                                if (ctx.replaceBufferRange(buf.buffer_id, buf.cursor_offset, buf.cursor_offset, cmd.snippet)) {
                                    if (cmd.notice.len > 0) ctx.setStatusNotice(cmd.notice);
                                }
                            }
                        }
                    } else if (cmd.snippet.len > 0 and cmd.hint.len > 0) {
                        if (ctx.ui.button(ctx.fmt("+ {s}##{s}_btn", .{ cmd.hint, cmd.id }), 88, 24)) {
                            const buf = ctx.activeBuffer() orelse continue;
                            if (ctx.replaceBufferRange(buf.buffer_id, buf.cursor_offset, buf.cursor_offset, cmd.snippet)) {
                                if (cmd.notice.len > 0) ctx.setStatusNotice(cmd.notice);
                            }
                        }
                    }
                }
                ctx.ui.endBox();
            }

            if (spec.custom_render_sidebar) |custom_sidebar| {
                custom_sidebar(ctx);
            }

            if (ctx.activeBuffer()) |buf| {
                if (isMatchingBuffer(buf)) {
                    if (!st.has_lsp_diagnostics and (st.last_synced_version != buf.edit_version or st.last_synced_buffer_id != buf.buffer_id)) {
                        st.diagnostic_count = lsp.scanLocalDiagnostics(buf.text, spec.language, &st.diagnostics);
                        st.last_synced_version = buf.edit_version;
                        st.last_synced_buffer_id = buf.buffer_id;
                    }

                    _ = ctx.ui.textFieldInline(spec.id ++ "_sym_filter", &st.filter_query, "Filter symbols...");

                    var syms: [lsp.MaxSymbols]lsp.LspSymbol = undefined;
                    const sym_count = lsp.scanSymbols(buf.text, spec.language, st.filter_query.slice(), &syms);

                    ctx.ui.mutedLabel(ctx.fmt("Symbols ({d}) · Diagnostics ({d})", .{ sym_count, st.diagnostic_count }));

                    for (syms[0..@min(sym_count, 8)], 0..) |sym, i| {
                        ctx.ui.pushId(ctx.fmt("{s}_s_{d}", .{ spec.id, i }));
                        const item_label = ctx.fmt("[{s}] {s}", .{ sym.kind.slice(), sym.name.slice() });
                        const meta = ctx.fmt("L{d}", .{sym.line});
                        if (ctx.ui.listItem(item_label, meta, buf.cursor_line == sym.line)) {
                            jumpToLine(ctx, buf.buffer_id, sym.line);
                        }
                        ctx.ui.popId();
                    }

                    for (st.diagnostics[0..@min(st.diagnostic_count, 4)], 0..) |d, i| {
                        ctx.ui.pushId(ctx.fmt("{s}_d_{d}", .{ spec.id, i }));
                        const d_label = ctx.fmt("[{s}] {s}", .{ d.severity.badge(), d.message.slice() });
                        const d_meta = ctx.fmt("L{d}", .{d.line});
                        if (ctx.ui.listItem(d_label, d_meta, buf.cursor_line == d.line)) {
                            jumpToLine(ctx, buf.buffer_id, d.line);
                        }
                        ctx.ui.popId();
                    }
                }
            }
        }
    };

    exportEditorPlugin(.{
        .id = spec.id,
        .display_name = spec.display_name,
        .version = spec.version,
        .sidebar_title = spec.sidebar_title,
        .bottom_tab_title = spec.bottom_tab_title,
        .init = &Gen.onInit,
        .on_reload = &Gen.onReload,
        .deinit = &Gen.onDeinit,
        .on_poll_io = &Gen.onPollIo,
        .on_command = &Gen.onCommand,
        .on_buffer_open = &Gen.onBufferOpen,
        .on_buffer_edit = &Gen.onBufferEdit,
        .on_buffer_save = &Gen.onBufferSave,
        .render_sidebar = &Gen.renderSidebar,
        .render_bottom_panel = spec.render_bottom_panel,
        .render_status_bar = &Gen.renderStatusBar,
    });
}
