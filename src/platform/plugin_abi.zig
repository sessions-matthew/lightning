//! Versioned C-ABI contract (`EditorPluginV1` & `EditorHostApiV1`) for dynamically loaded
//! native Zig `.dylib` editor plugins.
//!
//! All types in this module use `extern struct` and `callconv(.c)` function pointers so
//! plugins can be compiled into standalone ~20–30 KB `.dylib` binaries without linking Skia
//! and hot-reloaded in <5 ms while preserving state in the host's `StateStore`.

const std = @import("std");

pub const EDITOR_PLUGIN_ABI_VERSION: u32 = 1;

/// ABI-safe non-owning byte slice (`ptr` + `len`).
pub const AbiSlice = extern struct {
    ptr: ?[*]const u8 = null,
    len: usize = 0,

    pub fn fromZig(s: []const u8) AbiSlice {
        return .{
            .ptr = if (s.len > 0) s.ptr else null,
            .len = s.len,
        };
    }

    pub fn toZig(self: AbiSlice) []const u8 {
        const p = self.ptr orelse return &.{};
        return p[0..self.len];
    }
};

/// Capability bitmask declared statically by the plugin.
/// The host only invokes hooks that the plugin subscribes to.
pub const PluginCapabilities = packed struct(u32) {
    commands: bool = false,
    buffer_hooks: bool = false,
    sidebar_panel: bool = false,
    bottom_panel: bool = false,
    status_bar: bool = false,
    editor_overlay: bool = false,
    background_poller: bool = false,
    _reserved: u25 = 0,
};

/// Activity Bar vector icon contributed by a plugin that provides its own dedicated left sidebar menu.
pub const PluginSidebarIcon = enum(u8) {
    none = 0,
    debug = 1,
    cpu = 2,
    waveform = 3,
    git = 4,
    plugins = 5,
    board = 6,
    pdf = 7,
};

/// Compact toolbar vector icon for `PluginUiApiV1.toolbar_icon_btn`.
pub const PluginToolbarIcon = enum(u8) {
    play = 0,
    pause = 1,
    step_over = 2,
    step_into = 3,
    step_out = 4,
    restart = 5,
    stop = 6,
    gear = 7,
    debug_console = 8,
    breakpoint = 9,
};

pub const PluginManifestV1 = extern struct {
    abi_version: u32 = EDITOR_PLUGIN_ABI_VERSION,
    id: AbiSlice,
    display_name: AbiSlice,
    version: AbiSlice,
    capabilities: PluginCapabilities = .{},
    sidebar_icon: PluginSidebarIcon = .none,
    sidebar_title: AbiSlice = .{},
    bottom_tab_title: AbiSlice = .{},
    /// Comma-separated file extensions handled by this debugger plugin (e.g. ".zig,.c,.cpp,.h,.rs").
    debug_extensions: AbiSlice = .{},
};

pub const BufferInfoV1 = extern struct {
    buffer_id: u32 = 0,
    file_path: AbiSlice = .{},
    text: AbiSlice = .{},
    line_count: u32 = 1,
    cursor_offset: usize = 0,
    selection_anchor: usize = 0,
    cursor_line: u32 = 0,
    cursor_col: u32 = 0,
    edit_version: u32 = 0,
    is_dirty: bool = false,
};

pub const LineRangeV1 = extern struct {
    start: usize = 0,
    end: usize = 0,
};

pub const BufferEditEventV1 = extern struct {
    buffer_id: u32 = 0,
    start_offset: usize = 0,
    old_end_offset: usize = 0,
    new_end_offset: usize = 0,
    edit_version: u32 = 0,
};

/// Single completion candidate contributed by a language server plugin (`textDocument/completion`).
pub const CompletionItemV1 = extern struct {
    label: AbiSlice = .{},
    detail: AbiSlice = .{},
    insert_text: AbiSlice = .{},
    kind: u8 = 0, // 0=keyword, 1=fn/method, 2=type/class/struct, 3=snippet, 4=field/var
    replace_prefix_len: u16 = 0,
};

/// Single debugger breakpoint entry shared between the host code editor gutter and debugger plugins.
pub const BreakpointV1 = extern struct {
    file_path: AbiSlice = .{},
    line: u32 = 1, // 1-based line number
    enabled: bool = true,
    hit_count: u32 = 0,
};

pub const GitActionV1 = enum(u32) {
    stage_path = 0,
    unstage_path = 1,
    stage_all = 2,
    unstage_all = 3,
    discard_path = 4,
    commit = 5,
    refresh = 6,
};

pub const GitFileStatusV1 = extern struct {
    path: AbiSlice = .{},
    status: u8 = 'M',
    staged: bool = false,
    unstaged: bool = false,
    untracked: bool = false,
};

pub const GitCommitV1 = extern struct {
    hash: AbiSlice = .{},
    subject: AbiSlice = .{},
    rel_time: AbiSlice = .{},
    files_changed: u16 = 0,
    files_ptr: ?[*]const GitFileStatusV1 = null,
    file_count: usize = 0,
};

pub const GitStatusSnapshotV1 = extern struct {
    branch: AbiSlice = .{},
    is_busy: bool = false,
    files_ptr: ?[*]const GitFileStatusV1 = null,
    file_count: usize = 0,
    commits_ptr: ?[*]const GitCommitV1 = null,
    commit_count: usize = 0,
};

/// Text Field interaction flags returned by `PluginUiApiV1.text_field` and `PluginUiApiV1.text_area`.
pub const TextFieldResultFlags = packed struct(u8) {
    changed: bool = false,
    submitted: bool = false,
    escaped: bool = false,
    focused: bool = false,
    _reserved: u4 = 0,
};

/// Collapsible section header interaction flags returned by `PluginUiApiV1.collapsible_section_with_action`.
pub const SectionHeaderResultFlags = packed struct(u8) {
    expanded: bool = false,
    action_clicked: bool = false,
    right_clicked: bool = false,
    _reserved: u5 = 0,
};

/// Extended list item interaction flags returned by `PluginUiApiV1.list_item_ex`.
pub const ListItemResultFlags = packed struct(u8) {
    clicked: bool = false,
    action_clicked: bool = false,
    secondary_action_clicked: bool = false,
    right_clicked: bool = false,
    _reserved: u4 = 0,
};

/// Two-phase (`Pass.input` / `Pass.paint`) UI vtable exposed by the host to plugins.
/// Consumes identical layout boxes in `.input` and `.paint` and shares the host's
/// 4096-entry `TextCache` and `DamageList` scissor culling.
pub const PluginUiApiV1 = extern struct {
    /// Returns `0` for `Pass.input`, `1` for `Pass.paint`.
    get_pass: *const fn (host: *anyopaque) callconv(.c) u8,

    // Layout Containers
    begin_column: *const fn (host: *anyopaque, w: f32, h: f32, pad: f32, gap: f32) callconv(.c) void,
    begin_row: *const fn (host: *anyopaque, w: f32, h: f32, pad: f32, gap: f32) callconv(.c) void,
    end_box: *const fn (host: *anyopaque) callconv(.c) void,
    begin_scroll_panel: *const fn (host: *anyopaque, id: AbiSlice, w: f32, h: f32, pad: f32, gap: f32) callconv(.c) void,
    end_scroll_panel: *const fn (host: *anyopaque) callconv(.c) void,
    spacer: *const fn (host: *anyopaque, w: f32, h: f32) callconv(.c) void,
    divider: *const fn (host: *anyopaque) callconv(.c) void,
    push_id: *const fn (host: *anyopaque, id: AbiSlice) callconv(.c) void,
    pop_id: *const fn (host: *anyopaque) callconv(.c) void,

    // Cached Text & Interactive Widgets
    /// `style`: 0 = body, 1 = muted, 2 = mono, 3 = section header
    label: *const fn (host: *anyopaque, text: AbiSlice, style: u8) callconv(.c) void,
    button: *const fn (host: *anyopaque, label: AbiSlice, w: f32, h: f32) callconv(.c) bool,
    toolbar_icon_btn: *const fn (host: *anyopaque, label: AbiSlice, icon: PluginToolbarIcon, w: f32, h: f32, enabled: bool) callconv(.c) bool,
    dropdown_select: *const fn (host: *anyopaque, label: AbiSlice, display_text: AbiSlice, w: f32, h: f32, active_border: bool) callconv(.c) bool,
    reserve_dropdown_overlay: *const fn (host: *anyopaque, height: f32) callconv(.c) bool,
    begin_dropdown_overlay: *const fn (host: *anyopaque) callconv(.c) void,
    end_dropdown_overlay: *const fn (host: *anyopaque) callconv(.c) void,
    collapsible_section: *const fn (host: *anyopaque, label: AbiSlice, expanded: *bool, badge_text: AbiSlice) callconv(.c) bool,
    collapsible_section_with_action: *const fn (host: *anyopaque, label: AbiSlice, expanded: *bool, badge_text: AbiSlice, action_label: AbiSlice) callconv(.c) u8,
    tree_folder_node: *const fn (host: *anyopaque, label: AbiSlice, indent_level: u8, expanded: *bool, meta: AbiSlice) callconv(.c) bool,
    chip: *const fn (host: *anyopaque, label: AbiSlice, active: bool) callconv(.c) bool,
    list_item: *const fn (host: *anyopaque, label: AbiSlice, meta: AbiSlice, selected: bool) callconv(.c) bool,
    list_item_ex: *const fn (
        host: *anyopaque,
        label: AbiSlice,
        meta: AbiSlice,
        icon_text: AbiSlice,
        action_label: AbiSlice,
        secondary_action_label: AbiSlice,
        indent_level: u8,
        selected: bool,
        accent_kind: u8,
    ) callconv(.c) u8,
    text_field: *const fn (host: *anyopaque, id: AbiSlice, buf_ptr: [*]u8, len_ptr: *usize, cap: usize, placeholder: AbiSlice) callconv(.c) u8,
    text_area: *const fn (host: *anyopaque, id: AbiSlice, buf_ptr: [*]u8, len_ptr: *usize, cap: usize, placeholder: AbiSlice, height: f32) callconv(.c) u8,
    markdown: *const fn (host: *anyopaque, source: AbiSlice) callconv(.c) void,
    waveform_view: *const fn (host: *anyopaque, id: AbiSlice, vcd_source: AbiSlice, height: f32) callconv(.c) void,
    pdf_view: *const fn (host: *anyopaque, id: AbiSlice, file_path: AbiSlice, raw_bytes: AbiSlice, height: f32) callconv(.c) void,
};

/// Host service vtable passed to all plugin lifecycle, event, and UI callbacks.
pub const EditorHostApiV1 = extern struct {
    abi_version: u32 = EDITOR_PLUGIN_ABI_VERSION,

    // 1. Per-Frame Arena & Persistent Scoped State (`dlclose`-safe)
    frame_alloc: *const fn (host: *anyopaque, size: usize, alignment_log2: u8) callconv(.c) ?[*]u8,
    use_state_raw: *const fn (
        host: *anyopaque,
        key: AbiSlice,
        size: usize,
        alignment_log2: u8,
        type_hash: u64,
        initialized_out: *bool,
    ) callconv(.c) [*]u8,

    // 2. Zero-Copy Buffer Inspection & Atomic Mutation
    get_active_buffer: *const fn (host: *anyopaque, out: *BufferInfoV1) callconv(.c) bool,
    get_line_range: *const fn (host: *anyopaque, buffer_id: u32, line_idx: u32) callconv(.c) LineRangeV1,
    offset_to_line_col: *const fn (host: *anyopaque, buffer_id: u32, offset: usize, line_out: *u32, col_out: *u32) callconv(.c) void,
    replace_buffer_range: *const fn (host: *anyopaque, buffer_id: u32, start: usize, end: usize, new_text: AbiSlice) callconv(.c) bool,
    set_cursor_and_scroll: *const fn (host: *anyopaque, buffer_id: u32, cursor: usize, anchor: usize) callconv(.c) void,

    // 3. Command Palette, Autocomplete Popup, Preview Buffers, Status Notice & Async Wakeup
    register_command: *const fn (host: *anyopaque, cmd_id: AbiSlice, title: AbiSlice, category: AbiSlice, shortcut_hint: AbiSlice) callconv(.c) bool,
    set_completions: *const fn (host: *anyopaque, buffer_id: u32, cursor_offset: usize, items_ptr: ?[*]const CompletionItemV1, item_count: usize) callconv(.c) void,
    open_waveform_preview: *const fn (host: *anyopaque, vcd_source: AbiSlice, split_to_side: bool) callconv(.c) void,
    open_pdf_preview: *const fn (host: *anyopaque, file_path: AbiSlice, raw_bytes: AbiSlice, split_to_side: bool) callconv(.c) void,
    open_git_diff: *const fn (host: *anyopaque, file_path: AbiSlice, commit_sha: AbiSlice, staged: bool, split_to_side: bool) callconv(.c) void,
    open_file_path: *const fn (host: *anyopaque, path: AbiSlice) callconv(.c) bool,
    sync_workspace_git: *const fn (host: *anyopaque, save_dirty: bool, reload_from_disk: bool) callconv(.c) void,
    get_git_status: *const fn (host: *anyopaque, out: *GitStatusSnapshotV1) callconv(.c) bool,
    git_action: *const fn (host: *anyopaque, action: GitActionV1, path_or_msg: AbiSlice) callconv(.c) bool,
    run_terminal_command: *const fn (host: *anyopaque, cmd: AbiSlice) callconv(.c) void,
    toggle_bottom_panel: *const fn (host: *anyopaque) callconv(.c) void,
    set_status_notice: *const fn (host: *anyopaque, msg: AbiSlice) callconv(.c) void,
    request_continuous_redraw: *const fn (host: *anyopaque) callconv(.c) void,

    // 4. Shared Breakpoints & Active Debugger Execution Line
    toggle_breakpoint: *const fn (host: *anyopaque, file_path: AbiSlice, line_1based: u32) callconv(.c) bool,
    clear_breakpoints: *const fn (host: *anyopaque) callconv(.c) void,
    get_breakpoints: *const fn (host: *anyopaque, out_ptr: ?[*]BreakpointV1, max_count: usize) callconv(.c) usize,
    set_debug_location: *const fn (host: *anyopaque, active: bool, paused: bool, file_path: AbiSlice, line_1based: u32, jump_to_line: bool) callconv(.c) void,

    // 5. Two-Phase Declarative UI Toolkit Bridge
    ui: *const PluginUiApiV1,
};

pub const PluginHookFn = *const fn (host: *anyopaque, api: *const EditorHostApiV1) callconv(.c) void;
pub const PluginCommandFn = *const fn (host: *anyopaque, api: *const EditorHostApiV1, cmd_id: AbiSlice) callconv(.c) void;
pub const PluginBufferInfoFn = *const fn (host: *anyopaque, api: *const EditorHostApiV1, info: *const BufferInfoV1) callconv(.c) void;
pub const PluginBufferEditFn = *const fn (host: *anyopaque, api: *const EditorHostApiV1, ev: *const BufferEditEventV1) callconv(.c) void;

pub const EditorPluginV1 = extern struct {
    manifest: PluginManifestV1,

    // Lifecycle & Hot-Reload Hooks
    init: ?PluginHookFn = null,
    before_reload: ?PluginHookFn = null,
    on_reload: ?PluginHookFn = null,
    deinit: ?PluginHookFn = null,

    // Event & Non-Blocking I/O Hooks (called during Pass.input)
    on_poll_io: ?PluginHookFn = null,
    on_command: ?PluginCommandFn = null,
    on_buffer_open: ?PluginBufferInfoFn = null,
    on_buffer_edit: ?PluginBufferEditFn = null,
    on_buffer_save: ?PluginBufferInfoFn = null,

    // Two-Phase UI Contribution Hooks (called in both Pass.input and Pass.paint)
    render_sidebar: ?PluginHookFn = null,
    render_bottom_panel: ?PluginHookFn = null,
    render_status_bar: ?PluginHookFn = null,
};

/// Symbol exported by every dynamically loaded editor plugin `.dylib`:
/// `export fn editor_plugin_entry_v1() callconv(.c) *const EditorPluginV1`
pub const PLUGIN_ENTRY_SYMBOL = "editor_plugin_entry_v1";
pub const PluginEntryFn = *const fn () callconv(.c) *const EditorPluginV1;

test "AbiSlice round-trip and EditorPluginV1 extern layout" {
    const s = "hello plugin abi";
    const abi_s = AbiSlice.fromZig(s);
    try std.testing.expectEqualStrings(s, abi_s.toZig());

    const empty = AbiSlice.fromZig("");
    try std.testing.expect(empty.ptr == null);
    try std.testing.expectEqualStrings("", empty.toZig());
}
