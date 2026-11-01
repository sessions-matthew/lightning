//! Editor application state, disk I/O, live symbol outline & diagnostics scanner,
//! and workspace files (`libeditor_app.dylib`).

const std = @import("std");
const skia = @import("skia");
const ui = @import("ui");
const platform = @import("platform");
const PlatformContext = platform.PlatformContext;
pub const agy_client = @import("agy_client.zig");
pub const supercomplete_mod = @import("supercomplete.zig");
pub const git_client = @import("git_client.zig");
pub const analysis = @import("analysis.zig");
pub const workspace_defaults = @import("workspace_defaults.zig");
pub const workspace_fs = @import("workspace_fs.zig");
pub const plugin_manager = @import("plugin_manager.zig");
pub const hot_reload_stash = @import("hot_reload_stash.zig");
pub const workspace_search = @import("workspace_search.zig");

pub const STATE_VERSION: u64 = 0x2026_1022_B001;

const popen = platform.fs_util.popen;
const pclose = platform.fs_util.pclose;
const getcwd = workspace_fs.getcwd;
const getenv = workspace_fs.getenv;
pub const posix_dir = workspace_fs.posix_dir;

pub const MaxWorkspaceFiles: usize = 2048;
pub const MaxScannedWorkspaceFiles: usize = MaxWorkspaceFiles - 64;
pub const MaxWorkspaceFolders: usize = 512;
pub const MaxCollapsedFolders: usize = 512;
pub const GitFileStatus = git_client.GitFileStatus;
pub const GitCommitEntry = git_client.GitCommitEntry;

pub const MaxEditorPanes: usize = 6;
pub const MaxSplitNodes: usize = 2 * MaxEditorPanes - 1;
pub const MaxTabsPerPane: usize = 8;
pub const MaxOpenBuffers: usize = 24;
pub const MaxTerminalBuffers: usize = 8;
pub const MaxAgentBuffers: usize = 8;
pub const MaxOutputLines: usize = 128;

pub const OutputLine = struct {
    channel: platform.InlineString(24) = .{},
    text: platform.InlineString(256) = .{},
};

pub const PANE_EDITOR_IDS = [MaxEditorPanes][]const u8{
    "workbench_code_editor_0",
    "workbench_code_editor_1",
    "workbench_code_editor_2",
    "workbench_code_editor_3",
    "workbench_code_editor_4",
    "workbench_code_editor_5",
};

pub const PANE_TAB_SCROLL_IDS = [MaxEditorPanes][]const u8{
    "pane_tabs_scroll_0",
    "pane_tabs_scroll_1",
    "pane_tabs_scroll_2",
    "pane_tabs_scroll_3",
    "pane_tabs_scroll_4",
    "pane_tabs_scroll_5",
};

pub const SplitNode = ui.SplitNode;
pub const SplitDropZone = ui.DockDropZone;

/// Represents a single editor group / split pane holding an ordered list of open file tabs.
pub const EditorPaneGroup = ui.PaneTabGroup(MaxTabsPerPane);

/// Global structured editor preferences & workspace state (persisted across hot-reloads via JSON snapshot).
pub const EditorDocument = struct {
    show_sidebar: bool = false,
    active_sidebar_view: u8 = 0,
    show_bottom_panel: bool = false,
    show_agent_panel: bool = false,
    agy_include_context: bool = true,
    supercomplete_enabled: bool = true,
    show_minimap: bool = false,
    show_dirty_overlay: bool = false,
    show_find_bar: bool = false,
    show_command_palette: bool = false,
    word_wrap_md_preview: bool = true,
    cursor_line: u32 = 1,
    cursor_col: u32 = 1,
    sidebar_width: f32 = 236.0,
    agent_panel_width: f32 = 340.0,
    bottom_panel_height: f32 = 185.0,
    sec_open_editors: bool = true,
    sec_files: bool = true,
    sec_outline: bool = true,
    outline_group_fn: bool = false,
    outline_group_types: bool = false,
    folder_default_expanded: bool = false,
    collapsed_folder_hashes: [MaxCollapsedFolders]u64 = @splat(0),
    collapsed_folder_count: u16 = 0,
    folder_src: bool = false,
    folder_src_app: bool = false,
    folder_src_app_views: bool = false,
    folder_src_ui: bool = false,
    folder_src_platform: bool = false,
    folder_src_platform_macos: bool = false,
    folder_src_skia: bool = false,
    folder_src_skia_c: bool = false,
    folder_examples: bool = false,
    sec_vc_staged: bool = true,
    sec_vc_changes: bool = true,
    sec_vc_commits: bool = true,
    vc_tree_mode: bool = true,
    vc_staged_src: bool = true,
    vc_changes_src: bool = true,
    vc_changes_app: bool = true,
    vc_changes_views: bool = true,
    vc_changes_ui: bool = true,
    vc_changes_platform: bool = true,
    commit_expanded: [git_client.MaxCommits]bool = @splat(false),
    md_preview_source_idx: u16 = 0,
    waveform_preview_source_idx: u16 = 0,
    pdf_preview_source_idx: u16 = 0,
    git_diff_source_idx: u16 = 0,
    git_diff_staged: bool = false,
    disabled_plugin_hashes: [plugin_manager.MaxPlugins]u64 = @splat(0),
    disabled_plugin_count: u8 = 0,
    workspace_root_buf: [256]u8 = @splat(0),
    workspace_root_len: u8 = 0,
    open_buffers: [MaxOpenBuffers]u16 = @splat(0),
    open_buffer_count: u8 = 0,
    split_tree: ui.SplitTree(MaxEditorPanes) = .{},
    panes: [MaxEditorPanes]EditorPaneGroup = @splat(.{}),
};

pub const SampleFile = workspace_defaults.SampleFile;
pub const WORKSPACE_FILES = workspace_defaults.WORKSPACE_FILES;

pub const DynamicFileStorage = struct {
    path_buf: [256:0]u8 = @splat(0),
    path_len: u16 = 0,
    folder: platform.InlineString(256) = .{},
    custom_name: platform.InlineString(64) = .{},
    name_offset: u16 = 0,
    seen_on_disk: bool = false,
};

pub const SymbolItem = analysis.SymbolItem;
pub const DiagnosticSeverity = analysis.DiagnosticSeverity;
pub const DiagnosticItem = analysis.DiagnosticItem;

pub const ContextMenuTarget = enum(u8) {
    none,
    code_editor,
    pdf_viewer,
    terminal,
    explorer_file,
    explorer_folder,
    outline_symbol,
    search_match,
    git_change,
    git_commit,
    plugin_item,
    problem_item,
    agent_message,
    titlebar_pill,
    pane_modeline,
    titlebar_file_menu,
    titlebar_edit_menu,
    titlebar_view_menu,
};

pub const BufferCapacity: usize = 4096;
pub const MaxDiskFileBytes: usize = 512 * 1024;
pub const HotReloadStashCapacity = hot_reload_stash.HotReloadStashCapacity;
pub const MaxWorkspaceSearchMatches = workspace_search.MaxWorkspaceSearchMatches;
pub const WorkspaceSearchMatch = workspace_search.WorkspaceSearchMatch;
pub const WorkspaceSearchResult = workspace_search.WorkspaceSearchResult;
pub const MaxSpecialBuffers = hot_reload_stash.MaxSpecialBuffers;
pub const HotReloadPaneGroup = hot_reload_stash.HotReloadPaneGroup;
pub const HotReloadSpecialKind = hot_reload_stash.HotReloadSpecialKind;
pub const HotReloadSpecialEntry = hot_reload_stash.HotReloadSpecialEntry;
pub const HotReloadStashMeta = hot_reload_stash.HotReloadStashMeta;
pub const HotReloadBufferEntry = hot_reload_stash.HotReloadBufferEntry;

pub const EditorState = struct {
    frame_arena: std.heap.ArenaAllocator,
    fonts: ui.FontSet = undefined,
    paint: skia.Paint = undefined,
    font_title: skia.Font = undefined,
    font_body: skia.Font = undefined,
    font_mono: skia.Font = undefined,
    font_code: skia.Font = undefined,
    ui_ctx: ui.Context = undefined,

    doc: EditorDocument = .{},
    file_storage: []DynamicFileStorage = &.{},
    file_storage_list: std.ArrayListUnmanaged(DynamicFileStorage) = .empty,
    files: []SampleFile = &.{},
    files_list: std.ArrayListUnmanaged(SampleFile) = .empty,
    file_count: usize = 0,
    folder_storage: []platform.InlineString(256) = &.{},
    folder_list: std.ArrayListUnmanaged(platform.InlineString(256)) = .empty,
    folder_count: usize = 0,
    buffers: []ui.CodeEditorBuffer(BufferCapacity) = &.{},
    buffers_list: std.ArrayListUnmanaged(ui.CodeEditorBuffer(BufferCapacity)) = .empty,
    buffer_initialized: []bool = &.{},
    buffer_initialized_list: std.ArrayListUnmanaged(bool) = .empty,
    saved_versions: []u32 = &.{},
    saved_versions_list: std.ArrayListUnmanaged(u32) = .empty,
    loaded_from_disk: []bool = &.{},
    loaded_from_disk_list: std.ArrayListUnmanaged(bool) = .empty,
    disk_mtime_hashes: []u64 = &.{},
    disk_mtime_hashes_list: std.ArrayListUnmanaged(u64) = .empty,
    buffer_word_wrap: []u8 = &.{},
    buffer_word_wrap_list: std.ArrayListUnmanaged(u8) = .empty,
    scratch_word_wrap: bool = false,
    scratch_buf: ui.CodeEditorBuffer(BufferCapacity) = .{},
    scratch_saved_version: u32 = 1,
    has_opened_workspace: bool = false,
    buffers_initialized: bool = false,
    prev_reload_count: u32 = 0,
    last_watch_poll_ms: i64 = 0,
    last_watch_sig: u64 = 0,

    // Interactive Find Bar (`Cmd+F`), Workspace Search, Command Palette (`Cmd+P`), Save As, & Git Commit inputs
    find_query: platform.InlineString(256) = .{},
    workspace_search: platform.InlineString(256) = .{},
    plugin_search: platform.InlineString(128) = .{},
    waveform_custom_vcd: platform.InlineString(4096) = .{},
    pdf_custom_path: platform.InlineString(256) = .{},
    pdf_custom_bytes: platform.InlineString(4096) = .{},
    pdf_views: [MaxEditorPanes]ui.PdfViewState = @splat(.{}),
    image_views: [MaxEditorPanes]ui.ImageViewState = @splat(.{}),
    git_diff_custom_text: platform.InlineString(16384) = .{},
    git_diff_custom_path: platform.InlineString(128) = .{},
    git_diff_title: platform.InlineString(128) = .{},
    git_diff_commit: platform.InlineString(16) = .{},
    git_diff_views: [MaxEditorPanes]ui.DiffViewState = @splat(.{}),
    palette_query: platform.InlineString(256) = .{},
    palette_selected_idx: usize = 0,
    save_as_path: platform.InlineString(256) = .{},
    show_save_as_prompt: bool = false,
    save_as_create_empty: bool = false,
    new_folder_path: platform.InlineString(256) = .{},
    show_new_folder_prompt: bool = false,
    open_workspace_path: platform.InlineString(256) = .{},
    show_open_workspace_prompt: bool = false,
    pending_native_folder_pick: bool = false,
    open_workspace_selected_idx: usize = 0,
    commit_msg: platform.InlineString(2048) = .{},
    show_stage_all_prompt: bool = false,
    git_file_statuses: []GitFileStatus = &.{},
    git_file_statuses_list: std.ArrayListUnmanaged(GitFileStatus) = .empty,
    git_commits: [git_client.MaxCommits]GitCommitEntry = @splat(.{}),
    git_commit_count: usize = 0,
    git_branch: platform.InlineString(64) = .{},

    // Status notification & PTY-backed VTerm instances (bottom panel + dedicated terminal buffers)
    status_notice: platform.InlineString(96) = .{},
    output_lines: [MaxOutputLines]OutputLine = undefined,
    output_line_count: usize = 0,
    vterm: ui.VTerm = undefined,
    term_vterms: []ui.VTerm = &.{},
    term_vterms_list: std.ArrayListUnmanaged(ui.VTerm) = .empty,
    term_slot_used: []bool = &.{},
    term_slot_used_list: std.ArrayListUnmanaged(bool) = .empty,
    next_term_number: u16 = 1,

    // Antigravity (`agy`) bidirectional Local Socket Agent sessions (side panel + dedicated `*agent-N*` buffers)
    agy: agy_client.AgySession = agy_client.AgySession.init(),
    agy_prompt: platform.InlineString(8192) = .{},
    agent_sessions: []agy_client.AgySession = &.{},
    agent_sessions_list: std.ArrayListUnmanaged(agy_client.AgySession) = .empty,
    agent_prompts: []platform.InlineString(8192) = &.{},
    agent_prompts_list: std.ArrayListUnmanaged(platform.InlineString(8192)) = .empty,
    agent_slot_used: []bool = &.{},
    agent_slot_used_list: std.ArrayListUnmanaged(bool) = .empty,
    next_agent_number: u16 = 1,
    context_menu_agent_slot: ?u16 = null,

    // Antigravity Supercomplete inline ghost-text engine (ConnectRPC over HTTP/1.1)
    supercomplete: supercomplete_mod.SupercompleteClient = supercomplete_mod.SupercompleteClient.init(),

    // Non-blocking asynchronous Git status & commit history poller (`O_NONBLOCK` pipe state machine)
    git_poller: git_client.GitStatusPoller = .{},

    // Native Zig `.dylib` Plugin Manager (hot-reloads `zig-out/plugins/*.dylib` and dispatches hooks)
    plugins: plugin_manager.PluginManager = .{},

    // Live tab drag-and-drop reorganization tracking via `ui.TabDragState`
    tab_drag: ui.TabDragState = .{},
    pane_rects: [MaxEditorPanes]skia.c.sk_rect_t = @splat(.{ .left = 0, .top = 0, .right = 0, .bottom = 0 }),

    // Floating right-click context menu state across the workbench
    context_menu: ui.ContextMenuState = .{},
    context_menu_target: ContextMenuTarget = .none,
    context_menu_pane: usize = 0,
    context_menu_file: ?usize = null,
    context_menu_line: usize = 1,
    context_menu_index: usize = 0,
    context_menu_is_bottom_term: bool = false,
    context_menu_is_staged: bool = false,
    context_menu_folder: platform.InlineString(128) = .{},
    context_menu_label: platform.InlineString(128) = .{},
    pending_md_heading: platform.InlineString(128) = .{},

    // Version-memoized symbol outline & diagnostics caches (O(1) on frames without buffer edits)
    cached_symbols: [32]SymbolItem = undefined,
    cached_symbol_count: usize = 0,
    cached_symbol_file: usize = std.math.maxInt(usize),
    cached_symbol_version: u32 = 0,

    cached_diags: [16]DiagnosticItem = undefined,
    cached_diag_count: usize = 0,
    cached_diag_file: usize = std.math.maxInt(usize),
    cached_diag_version: u32 = 0,

    // Memoized Workspace Search cache (O(1) on steady frames; avoids re-scanning workspace files on every input/paint pass)
    cached_search_query: platform.InlineString(256) = .{},
    cached_search_matches: [MaxWorkspaceSearchMatches]WorkspaceSearchMatch = @splat(.{}),
    cached_search_match_count: usize = 0,
    cached_search_sig: u64 = 0,

    pub fn syncDynamicSlices(self: *EditorState) void {
        self.file_storage = self.file_storage_list.items;
        self.files = self.files_list.items;
        self.folder_storage = self.folder_list.items;
        self.buffers = self.buffers_list.items;
        self.buffer_initialized = self.buffer_initialized_list.items;
        self.saved_versions = self.saved_versions_list.items;
        self.loaded_from_disk = self.loaded_from_disk_list.items;
        self.disk_mtime_hashes = self.disk_mtime_hashes_list.items;
        self.buffer_word_wrap = self.buffer_word_wrap_list.items;
        self.git_file_statuses = self.git_file_statuses_list.items;
        self.term_vterms = self.term_vterms_list.items;
        self.term_slot_used = self.term_slot_used_list.items;
        self.agent_sessions = self.agent_sessions_list.items;
        self.agent_prompts = self.agent_prompts_list.items;
        self.agent_slot_used = self.agent_slot_used_list.items;
    }

    pub fn ensureFileSlot(self: *EditorState, idx: usize) void {
        const alloc = std.heap.c_allocator;
        const old_storage_ptr = self.file_storage_list.items.ptr;
        while (self.files_list.items.len <= idx) {
            self.file_storage_list.append(alloc, .{}) catch break;
            self.files_list.append(alloc, .{ .name = "", .path = "", .folder = ".", .initial_source = "" }) catch break;
            self.buffers_list.append(alloc, undefined) catch break;
            self.buffer_initialized_list.append(alloc, false) catch break;
            self.saved_versions_list.append(alloc, 1) catch break;
            self.loaded_from_disk_list.append(alloc, false) catch break;
            self.disk_mtime_hashes_list.append(alloc, 0) catch break;
            self.buffer_word_wrap_list.append(alloc, 0) catch break;
            self.git_file_statuses_list.append(alloc, .{}) catch break;
        }
        self.syncDynamicSlices();
        if (self.file_storage_list.items.ptr != old_storage_ptr and self.file_count > 0) {
            self.rebindDynamicFileSlices();
        }
    }

    pub fn ensureFolderSlot(self: *EditorState, idx: usize) void {
        const alloc = std.heap.c_allocator;
        while (self.folder_list.items.len <= idx) {
            self.folder_list.append(alloc, .{}) catch break;
        }
        self.folder_storage = self.folder_list.items;
    }

    pub fn ensureTerminalSlot(self: *EditorState, t_slot: usize) usize {
        const alloc = std.heap.c_allocator;
        while (self.term_vterms_list.items.len <= t_slot) {
            self.term_vterms_list.append(alloc, ui.VTerm.init()) catch break;
            self.term_slot_used_list.append(alloc, false) catch break;
        }
        self.term_vterms = self.term_vterms_list.items;
        self.term_slot_used = self.term_slot_used_list.items;
        return if (self.term_vterms.len > 0) @min(t_slot, self.term_vterms.len - 1) else 0;
    }

    pub fn allocTerminalSlot(self: *EditorState) usize {
        for (self.term_slot_used, 0..) |used, i| {
            if (!used) return i;
        }
        const new_slot = self.term_vterms_list.items.len;
        return self.ensureTerminalSlot(new_slot);
    }

    pub fn ensureAgentSlot(self: *EditorState, a_slot: usize) usize {
        const alloc = std.heap.c_allocator;
        while (self.agent_sessions_list.items.len <= a_slot) {
            self.agent_sessions_list.append(alloc, agy_client.AgySession.init()) catch break;
            self.agent_prompts_list.append(alloc, .{}) catch break;
            self.agent_slot_used_list.append(alloc, false) catch break;
        }
        self.agent_sessions = self.agent_sessions_list.items;
        self.agent_prompts = self.agent_prompts_list.items;
        self.agent_slot_used = self.agent_slot_used_list.items;
        return if (self.agent_sessions.len > 0) @min(a_slot, self.agent_sessions.len - 1) else 0;
    }

    pub fn allocAgentSlot(self: *EditorState) usize {
        for (self.agent_slot_used, 0..) |used, i| {
            if (!used) return i;
        }
        const new_slot = self.agent_sessions_list.items.len;
        return self.ensureAgentSlot(new_slot);
    }

    pub fn ensureBufferSlotInit(self: *EditorState, idx: usize) *ui.CodeEditorBuffer(BufferCapacity) {
        self.ensureFileSlot(idx);
        if (!self.buffer_initialized[idx]) {
            self.buffers[idx] = .{};
            self.buffer_initialized[idx] = true;
        }
        return &self.buffers[idx];
    }

    pub fn initEmpty(self: *EditorState) void {
        self.file_count = 0;
        self.folder_count = 0;
        self.output_line_count = 0;
        self.syncDynamicSlices();
        for (0..self.buffer_initialized.len) |i| {
            if (self.buffer_initialized[i]) {
                self.buffers[i].deinit();
                self.buffer_initialized[i] = false;
            }
        }
        @memset(self.saved_versions, 1);
        @memset(self.loaded_from_disk, false);
        @memset(self.disk_mtime_hashes, 0);
        @memset(self.buffer_word_wrap, 0);
        for (self.file_storage) |*st| st.* = .{};
        for (self.folder_storage) |*fs| fs.* = .{};
        for (self.git_file_statuses) |*g| g.* = .{};
        for (&self.output_lines) |*o| o.* = .{};
        self.vterm = ui.VTerm.init();
        for (self.term_vterms, 0..) |*vt, i| {
            vt.* = ui.VTerm.init();
            self.term_slot_used[i] = false;
        }
        for (self.agent_sessions, 0..) |*as, i| {
            as.* = agy_client.AgySession.init();
            self.agent_prompts[i] = .{};
            self.agent_slot_used[i] = false;
        }
        self.next_agent_number = 1;
        self.context_menu_agent_slot = null;
    }

    pub fn initResources(self: *EditorState, ctx: *PlatformContext) void {
        self.fonts = ui.FontSet.init(ctx, .{
            .title = 14.0,
            .body = 12.5,
            .mono = 11.5,
            .code = 13.0,
        });
        self.paint = self.fonts.paint;
        self.font_title = self.fonts.title;
        self.font_body = self.fonts.body;
        self.font_mono = self.fonts.mono;
        self.font_code = self.fonts.code;

        self.ui_ctx = self.fonts.initContext(self.frame_arena.allocator(), ctx);
        self.ui_ctx.theme = .{
            .bg_canvas = skia.Color.rgb(13, 17, 23),
            .bg_panel = skia.Color.rgb(18, 23, 33),
            .bg_card = skia.Color.rgb(28, 36, 51),
            .border_subtle = skia.Color.argb(65, 100, 116, 139),
            .text_primary = skia.Color.rgb(230, 237, 243),
            .text_muted = skia.Color.rgb(125, 133, 144),
            .accent = skia.Color.rgb(56, 139, 253),
            .accent_hover = skia.Color.rgb(88, 166, 255),
            .accent_active = skia.Color.rgb(31, 111, 235),
            .control_bg = skia.Color.rgb(33, 41, 58),
            .control_hover = skia.Color.rgb(48, 59, 82),
            .success = skia.Color.rgb(46, 160, 67),
        };

        if (!self.buffers_initialized) {
            self.initEmpty();
            self.syncWorkspaceRootFromCwd();
            self.scratch_buf.resetWithSlice("");
            self.scratch_saved_version = self.scratch_buf.edit_version;
            self.refreshWorkspaceFiles(false);
            self.agy.syncWorkspaceRoot(self.workspaceRoot());
            self.buffers_initialized = true;
            self.ui_ctx.focused_id = ui.id("workbench_code_editor_0");
            const now_ms: i64 = @intCast(platform.profiler.nowNs() / std.time.ns_per_ms);
            if (self.supercomplete.attach(now_ms)) {
                self.agy.ls_port = self.supercomplete.ls_port;
                self.agy.alt_port = self.supercomplete.alt_port;
                self.agy.csrf_buf = self.supercomplete.csrf_buf;
                self.agy.csrf_len = self.supercomplete.csrf_len;
                self.agy.setStatus("Connected to Hub");
                self.syncAgyHubState();
            }
        }
    }

    pub fn deinitResources(self: *EditorState) void {
        const alloc = std.heap.c_allocator;
        self.scratch_buf.deinit();
        for (0..self.buffer_initialized.len) |i| {
            if (self.buffer_initialized[i]) {
                self.buffers[i].deinit();
                self.buffer_initialized[i] = false;
            }
        }
        for (self.term_vterms) |*tv| {
            tv.deinit();
        }
        for (self.agent_sessions) |*as| {
            as.deinit();
        }
        self.file_storage_list.deinit(alloc);
        self.files_list.deinit(alloc);
        self.folder_list.deinit(alloc);
        self.buffers_list.deinit(alloc);
        self.buffer_initialized_list.deinit(alloc);
        self.saved_versions_list.deinit(alloc);
        self.loaded_from_disk_list.deinit(alloc);
        self.disk_mtime_hashes_list.deinit(alloc);
        self.buffer_word_wrap_list.deinit(alloc);
        self.git_file_statuses_list.deinit(alloc);
        self.term_vterms_list.deinit(alloc);
        self.term_slot_used_list.deinit(alloc);
        self.agent_sessions_list.deinit(alloc);
        self.agent_prompts_list.deinit(alloc);
        self.agent_slot_used_list.deinit(alloc);
        self.syncDynamicSlices();
        self.vterm.deinit();
        self.agy.deinit();
        self.supercomplete.deinit();
        self.git_poller.deinit();
        self.plugins.deinit(self);
        self.ui_ctx.deinit();
        self.fonts.deinit();
        self.frame_arena.deinit();
    }

    pub const bufferReloadKey = hot_reload_stash.bufferReloadKey;

    pub fn findBufferIndexByReloadKey(self: *const EditorState, key: []const u8) ?usize {
        return hot_reload_stash.findBufferIndexByReloadKey(self, key);
    }

    pub fn restoreSpecialBufferSlot(self: *EditorState, sp: HotReloadSpecialEntry) ?usize {
        return hot_reload_stash.restoreSpecialBufferSlot(self, sp);
    }

    pub fn onBeforeReload(self: *EditorState, pctx: *PlatformContext) void {
        hot_reload_stash.onBeforeReload(self, pctx);
    }

    pub fn onAfterReload(self: *EditorState) void {
        hot_reload_stash.onAfterReload(self);
    }

    pub const isSystemOrHomeDirectory = workspace_fs.isSystemOrHomeDirectory;

    pub fn hasOpenedWorkspace(self: *const EditorState) bool {
        return self.has_opened_workspace;
    }

    pub fn syncWorkspaceRootFromCwd(self: *EditorState) void {
        var cwd_buf: [512]u8 = undefined;
        if (getcwd(&cwd_buf, cwd_buf.len) != null) {
            const s = std.mem.sliceTo(cwd_buf[0..], 0);
            if (isSystemOrHomeDirectory(s)) {
                self.doc.workspace_root_buf[0] = 0;
                self.doc.workspace_root_len = 0;
                self.has_opened_workspace = false;
                return;
            }
            const n = @min(s.len, self.doc.workspace_root_buf.len - 1);
            @memcpy(self.doc.workspace_root_buf[0..n], s[0..n]);
            self.doc.workspace_root_buf[n] = 0;
            self.doc.workspace_root_len = @intCast(n);
            self.has_opened_workspace = true;
        }
    }

    pub fn workspaceRoot(self: *const EditorState) []const u8 {
        if (self.doc.workspace_root_len > 0) {
            return self.doc.workspace_root_buf[0..self.doc.workspace_root_len];
        }
        return ".";
    }

    pub fn workspaceName(self: *const EditorState) []const u8 {
        if (!self.has_opened_workspace) return "No Folder Opened";
        const root = self.workspaceRoot();
        const base = std.fs.path.basename(root);
        return if (base.len > 0 and !std.mem.eql(u8, base, ".")) base else "workspace";
    }

    pub fn openWorkspacePath(self: *const EditorState) []const u8 {
        return self.open_workspace_path.slice();
    }

    pub fn openWorkspacePrompt(self: *EditorState) void {
        self.show_save_as_prompt = false;
        self.save_as_create_empty = false;
        self.show_new_folder_prompt = false;
        self.doc.show_command_palette = false;
        self.show_stage_all_prompt = false;
        self.context_menu.close();

        if (self.ui_ctx.platform_ctx) |pctx| {
            if (pctx.host_pick_folder != null) {
                self.show_open_workspace_prompt = false;
                self.pending_native_folder_pick = true;
                pctx.needs_continuous_redraw = true;
                self.ui_ctx.invalidateWindow();
                return;
            }
        }

        self.show_open_workspace_prompt = true;
        self.open_workspace_selected_idx = 0;
        if (self.open_workspace_path.isEmpty()) {
            self.open_workspace_path.set(self.workspaceRoot());
        }
        self.ui_ctx.focusAndSelectAll(ui.scopedIdPath(&.{ "vscode_workbench", "editor_pane" }, "##open_workspace_input"));
        self.ui_ctx.invalidateWindow();
    }

    pub fn openWorkspaceFromPrompt(self: *EditorState) bool {
        return self.openWorkspaceDirectory(self.openWorkspacePath());
    }

    /// Switches the active editor workspace to `raw_path` (supporting absolute paths, `~/...`,
    /// or relative directory paths), saving any dirty buffers first, changing the working directory,
    /// re-indexing all workspace files and folders, and opening the primary project entry file.
    pub fn openWorkspaceDirectory(self: *EditorState, raw_path: []const u8) bool {
        const trimmed = std.mem.trim(u8, raw_path, " \t\r\n\"'");
        if (trimmed.len == 0 or trimmed.len >= 248) {
            self.setStatusNotice("Open Workspace failed: enter a directory path");
            return false;
        }

        var expanded_buf: [512:0]u8 = @splat(0);
        var cand_slice: []const u8 = trimmed;
        if (std.mem.startsWith(u8, trimmed, "~/") or std.mem.eql(u8, trimmed, "~")) {
            if (getenv("HOME")) |home_z| {
                const home = std.mem.sliceTo(home_z, 0);
                const rest = if (trimmed.len > 1) trimmed[1..] else "";
                if (std.fmt.bufPrint(expanded_buf[0..510], "{s}{s}", .{ home, rest })) |s| {
                    expanded_buf[s.len] = 0;
                    cand_slice = s;
                } else |_| {}
            }
        } else {
            @memcpy(expanded_buf[0..trimmed.len], trimmed);
            expanded_buf[trimmed.len] = 0;
        }

        var resolved_buf: [std.fs.max_path_bytes]u8 = undefined;
        const resolved_z: [*:0]const u8 = posix_dir.realpath(&expanded_buf, &resolved_buf) orelse &expanded_buf;
        const resolved_slice = std.mem.sliceTo(resolved_z, 0);
        if (resolved_slice.len == 0 or resolved_slice.len >= 255) {
            self.setStatusNotice("Open Workspace failed: path too long");
            return false;
        }

        // If the user selected a file inside a workspace (rather than the folder itself),
        // resolve its enclosing workspace root (or parent directory) and open that file.
        if (!isDirectoryOnDisk(resolved_z)) {
            if (regularFileSizeOnDisk(resolved_z) != null) {
                var target_file_buf: [256]u8 = undefined;
                @memcpy(target_file_buf[0..resolved_slice.len], resolved_slice);
                const target_file = target_file_buf[0..resolved_slice.len];

                const cur_root = self.workspaceRoot();
                const inside_current = cur_root.len > 1 and
                    std.mem.startsWith(u8, target_file, cur_root) and
                    target_file.len > cur_root.len and
                    target_file[cur_root.len] == '/';
                if (!inside_current) {
                    const parent_dir = findProjectRootForFile(target_file) orelse
                        (std.fs.path.dirname(target_file) orelse return false);
                    if (!self.openWorkspaceDirectory(parent_dir)) return false;
                }
                self.show_open_workspace_prompt = false;
                _ = self.openLinkOrFileUrl(target_file);
                return true;
            }
            self.setStatusNotice("Open Workspace failed: directory does not exist");
            return false;
        }

        // Save any modified buffers in the outgoing workspace before switching
        _ = self.saveAllDirtyFiles();

        if (posix_dir.chdir(resolved_z) != 0) {
            self.setStatusNotice("Open Workspace failed: could not chdir to directory");
            return false;
        }

        self.has_opened_workspace = true;
        const n = @min(resolved_slice.len, self.doc.workspace_root_buf.len - 1);
        @memcpy(self.doc.workspace_root_buf[0..n], resolved_slice[0..n]);
        self.doc.workspace_root_buf[n] = 0;
        self.doc.workspace_root_len = @intCast(n);

        // Tear down existing workspace buffers and reset file/folder/pane tables
        for (0..self.file_count) |i| {
            if (self.files[i].is_terminal) {
                const t_slot = self.files[i].terminal_slot;
                if (t_slot < self.term_vterms.len) {
                    self.term_vterms[t_slot].deinit();
                    self.term_vterms[t_slot] = ui.VTerm.init();
                    self.term_slot_used[t_slot] = false;
                }
            }
            if (self.files[i].is_agent) {
                const a_slot = self.files[i].agent_slot;
                if (a_slot < self.agent_sessions.len) {
                    self.agent_sessions[a_slot].deinit();
                    self.agent_sessions[a_slot] = agy_client.AgySession.init();
                    self.agent_prompts[a_slot].clear();
                    self.agent_slot_used[a_slot] = false;
                }
            }
            if (self.buffer_initialized[i]) {
                self.buffers[i].deinit();
                self.buffer_initialized[i] = false;
            }
            self.saved_versions[i] = 1;
            self.loaded_from_disk[i] = false;
            self.disk_mtime_hashes[i] = 0;
        }
        for (self.file_count..self.buffer_initialized.len) |i| {
            if (self.buffer_initialized[i]) {
                self.buffers[i].deinit();
                self.buffer_initialized[i] = false;
            }
        }
        for (0..self.term_slot_used.len) |t_i| {
            if (self.term_slot_used[t_i]) {
                self.term_vterms[t_i].deinit();
                self.term_vterms[t_i] = ui.VTerm.init();
                self.term_slot_used[t_i] = false;
            }
        }
        self.next_term_number = 1;
        for (0..self.agent_slot_used.len) |a_i| {
            if (self.agent_slot_used[a_i]) {
                self.agent_sessions[a_i].deinit();
                self.agent_sessions[a_i] = agy_client.AgySession.init();
                self.agent_prompts[a_i].clear();
                self.agent_slot_used[a_i] = false;
            }
        }
        self.next_agent_number = 1;
        self.file_count = 0;
        self.folder_count = 0;
        self.doc.open_buffer_count = 0;
        self.doc.open_buffers = @splat(0);
        self.doc.split_tree = .{};
        self.doc.panes = @splat(.{});
        self.doc.collapsed_folder_hashes = @splat(0);
        self.doc.collapsed_folder_count = 0;
        self.doc.folder_default_expanded = false;
        @memset(self.git_file_statuses, .{});
        self.git_commit_count = 0;
        self.cached_symbol_file = std.math.maxInt(usize);
        self.cached_diag_file = std.math.maxInt(usize);
        self.cached_search_sig = 0;
        self.last_watch_sig = 0;

        self.refreshWorkspaceFiles(false);
        self.agy.syncWorkspaceRoot(self.workspaceRoot());
        self.syncAgyHubState();

        // Open the first non-special file in the newly opened workspace
        for (self.workspaceFiles(), 0..) |wf, idx| {
            if (!wf.isSpecial()) {
                self.openFile(idx);
                break;
            }
        }

        // If the integrated bottom terminal has a live shell, switch its working directory too
        if (self.vterm.master_fd >= 0) {
            var cd_buf: [320]u8 = undefined;
            const line_end = if (comptime (@import("builtin").os.tag == .windows)) "\r\n" else "\n";
            if (std.fmt.bufPrint(&cd_buf, "cd \"{s}\"{s}", .{ self.workspaceRoot(), line_end })) |cd_cmd| {
                self.vterm.writeInput(cd_cmd);
            } else |_| {}
        }

        self.show_open_workspace_prompt = false;
        self.doc.show_command_palette = false;
        self.open_workspace_path.set(self.workspaceRoot());

        var msg_buf: [96]u8 = undefined;
        const msg = std.fmt.bufPrint(
            &msg_buf,
            "Opened workspace '{s}' ({d} files)",
            .{ self.workspaceName(), self.nonSpecialFileCount() },
        ) catch "Opened workspace";
        self.setStatusNotice(msg);
        self.ui_ctx.focused_id = self.activeEditorWidgetId();
        self.ui_ctx.invalidateWindow();
        return true;
    }

    /// Returns the symbol outline for `file_idx`, memoized by `(file_idx, buf.edit_version)` so
    /// frames without edits do zero source scanning.
    pub fn symbolsForFile(self: *EditorState, file_idx: usize) []const SymbolItem {
        const wfs = self.workspaceFiles();
        if (wfs.len == 0) return &.{};
        const raw_clamped = file_idx % wfs.len;
        if (wfs[raw_clamped].is_markdown_preview and self.isScratchMarkdownPreview(raw_clamped)) {
            const buf = &self.scratch_buf;
            if (self.cached_symbol_file != 0xFFFF or self.cached_symbol_version != buf.edit_version) {
                self.cached_symbol_count = analysis.extractSymbols(buf.slice(), .markdown, &self.cached_symbols);
                self.cached_symbol_file = 0xFFFF;
                self.cached_symbol_version = buf.edit_version;
            }
            return self.cached_symbols[0..self.cached_symbol_count];
        }
        const clamped = if (wfs[raw_clamped].is_markdown_preview)
            self.markdownPreviewSourceIndexForBuffer(raw_clamped)
        else if (wfs[raw_clamped].is_waveform_preview)
            self.waveformPreviewSourceIndex()
        else if (wfs[raw_clamped].is_pdf_preview)
            self.pdfPreviewSourceIndex()
        else if (wfs[raw_clamped].is_git_diff_preview)
            self.gitDiffPreviewSourceIndex()
        else
            raw_clamped;
        self.ensureFileLoaded(clamped);
        const buf = &self.buffers[clamped];
        if (self.cached_symbol_file != clamped or self.cached_symbol_version != buf.edit_version) {
            self.cached_symbol_count = analysis.extractSymbols(buf.slice(), wfs[clamped].language, &self.cached_symbols);
            self.cached_symbol_file = clamped;
            self.cached_symbol_version = buf.edit_version;
        }
        return self.cached_symbols[0..self.cached_symbol_count];
    }

    /// Returns diagnostics for `file_idx`, memoized by `(file_idx, buf.edit_version)` so
    /// frames without edits do zero source scanning.
    pub fn diagnosticsForFile(self: *EditorState, file_idx: usize) []const DiagnosticItem {
        const wfs = self.workspaceFiles();
        if (wfs.len == 0) return &.{};
        const clamped = file_idx % wfs.len;
        self.ensureFileLoaded(clamped);
        const buf = &self.buffers[clamped];
        if (self.cached_diag_file != clamped or self.cached_diag_version != buf.edit_version) {
            self.cached_diag_count = analysis.scanDiagnosticsSource(buf.slice(), wfs[clamped].language, clamped, &self.cached_diags);
            self.cached_diag_file = clamped;
            self.cached_diag_version = buf.edit_version;
        }
        return self.cached_diags[0..self.cached_diag_count];
    }

    pub fn workspaceSearchMatches(self: *EditorState) []const WorkspaceSearchMatch {
        return workspace_search.workspaceSearchMatches(self);
    }

    pub fn performWorkspaceSearch(self: *EditorState) []const WorkspaceSearchMatch {
        return workspace_search.performWorkspaceSearch(self);
    }

    pub fn openWorkspaceSearchResult(self: *EditorState, match: WorkspaceSearchMatch) void {
        workspace_search.openWorkspaceSearchResult(self, match);
    }

    pub fn replaceInWorkspace(self: *EditorState, query: []const u8, replacement: []const u8) usize {
        return workspace_search.replaceInWorkspace(self, query, replacement);
    }

    // ========================================================================
    // Dynamic Workspace Directory Scanner & `.gitignore`-Aware Watcher
    // ========================================================================

    pub fn workspaceFiles(self: *const EditorState) []const SampleFile {
        return self.files[0..self.file_count];
    }

    pub fn workspaceFolders(self: *const EditorState) []const platform.InlineString(256) {
        return self.folder_storage[0..self.folder_count];
    }

    pub fn fileCount(self: *const EditorState) usize {
        return self.file_count;
    }

    pub fn nonSpecialFileCount(self: *const EditorState) usize {
        var count: usize = 0;
        for (self.workspaceFiles()) |wf| {
            if (!wf.isSpecial()) count += 1;
        }
        return count;
    }

    pub fn findWorkspaceFileIndexByPath(self: *const EditorState, rel_path: []const u8) ?usize {
        for (self.workspaceFiles(), 0..) |wf, idx| {
            if (!wf.isSpecial() and std.mem.eql(u8, wf.path, rel_path)) return idx;
        }
        return null;
    }

    /// Allocates and returns a dynamic slot in `self.files` for new buffers
    /// (`*terminal-N*`, `*agent-N*`, previews, or newly opened files), growing the backing lists on demand.
    pub fn ensureFreeDynamicFileSlot(self: *EditorState) ?usize {
        const idx = self.file_count;
        self.ensureFileSlot(idx);
        return if (idx < self.files.len) idx else null;
    }

    pub fn markdownPreviewBufferIndex(self: *EditorState) usize {
        const wfs = self.workspaceFiles();
        for (wfs, 0..) |wf, idx| {
            if (wf.is_markdown_preview and !wf.is_bound_markdown_preview) return idx;
        }
        if (self.ensureFreeDynamicFileSlot()) |idx| {
            self.storeDynamicFileSlot(idx, "*Markdown Preview*", .markdown, true, false, "");
            self.file_count += 1;
            return idx;
        }
        return if (self.file_count > 0) self.file_count - 1 else 0;
    }

    pub fn waveformPreviewBufferIndex(self: *EditorState) usize {
        const wfs = self.workspaceFiles();
        for (wfs, 0..) |wf, idx| {
            if (wf.is_waveform_preview) return idx;
        }
        if (self.ensureFreeDynamicFileSlot()) |idx| {
            self.storeDynamicFileSlot(idx, "sim_trace.vcd", .systemverilog, false, true, "");
            self.files[idx].name = "*Waveform Preview*";
            self.file_count += 1;
            return idx;
        }
        return if (self.file_count > 0) self.file_count - 1 else 0;
    }

    pub fn pdfPreviewBufferIndex(self: *EditorState) usize {
        const wfs = self.workspaceFiles();
        for (wfs, 0..) |wf, idx| {
            if (wf.is_pdf_preview) return idx;
        }
        if (self.ensureFreeDynamicFileSlot()) |idx| {
            self.storeDynamicFileSlot(idx, "datasheet_rv32.pdf", .markdown, false, false, "");
            self.files[idx].is_pdf_preview = true;
            self.files[idx].name = "*PDF Preview*";
            self.file_storage[idx].folder.set("*special*");
            self.files[idx].folder = self.file_storage[idx].folder.slice();
            self.file_count += 1;
            return idx;
        }
        return if (self.file_count > 0) self.file_count - 1 else 0;
    }

    pub fn gitDiffPreviewBufferIndex(self: *EditorState) usize {
        const wfs = self.workspaceFiles();
        for (wfs, 0..) |wf, idx| {
            if (wf.is_git_diff_preview) return idx;
        }
        if (self.ensureFreeDynamicFileSlot()) |idx| {
            self.storeDynamicFileSlot(idx, "*Git Diff*", .zig, false, false, "");
            self.files[idx].is_git_diff_preview = true;
            self.file_count += 1;
            return idx;
        }
        return if (self.file_count > 0) self.file_count - 1 else 0;
    }

    pub const detectLanguageForPath = workspace_fs.detectLanguageForPath;
    pub const shouldIgnoreScannedPath = workspace_fs.shouldIgnoreScannedPath;
    pub const isSupportedWorkspaceFile = workspace_fs.isSupportedWorkspaceFile;
    pub const unwrapICloudPlaceholder = workspace_fs.unwrapICloudPlaceholder;
    pub const getICloudPlaceholderPath = workspace_fs.getICloudPlaceholderPath;
    pub const writeSliceToDiskAtomic = workspace_fs.writeSliceToDiskAtomic;
    pub const regularFileSizeOnDisk = workspace_fs.regularFileSizeOnDisk;
    pub const fileMtimeSec = workspace_fs.fileMtimeSec;
    pub const findProjectRootForFile = workspace_fs.findProjectRootForFile;
    pub const isBinaryContent = workspace_fs.isBinaryContent;
    pub const isBinaryFileOnDisk = workspace_fs.isBinaryFileOnDisk;
    pub const fileExistsOnDisk = workspace_fs.fileExistsOnDisk;
    pub const isDatalessFileOnDisk = workspace_fs.isDatalessFileOnDisk;
    pub const triggerAsyncICloudDownload = workspace_fs.triggerAsyncICloudDownload;

    pub fn storeDynamicFileSlot(
        self: *EditorState,
        slot: usize,
        rel_path: []const u8,
        lang: ui.CodeLanguage,
        is_preview: bool,
        is_waveform: bool,
        initial_source: []const u8,
    ) void {
        _ = self.ensureBufferSlotInit(slot);
        var st = &self.file_storage[slot];
        st.* = .{};
        const p_len = @min(rel_path.len, st.path_buf.len - 1);
        @memcpy(st.path_buf[0..p_len], rel_path[0..p_len]);
        st.path_buf[p_len] = 0;
        st.path_len = @intCast(p_len);

        if (is_preview or is_waveform) {
            st.folder.set("*special*");
            st.name_offset = 0;
        } else if (std.mem.lastIndexOfScalar(u8, st.path_buf[0..p_len], '/')) |slash_idx| {
            st.folder.set(st.path_buf[0..slash_idx]);
            st.name_offset = @intCast(@min(p_len, slash_idx + 1));
        } else {
            st.folder.set(".");
            st.name_offset = 0;
        }

        self.files[slot] = .{
            .name = if (is_preview)
                "*Markdown Preview*"
            else if (is_waveform)
                "*Waveform Preview*"
            else
                st.path_buf[st.name_offset..p_len],
            .path = st.path_buf[0..p_len :0],
            .folder = st.folder.slice(),
            .language = lang,
            .is_markdown_preview = is_preview,
            .is_waveform_preview = is_waveform,
            .initial_source = initial_source,
        };
    }

    fn rebindDynamicFileSlices(self: *EditorState) void {
        const limit = @min(self.file_count, self.files.len);
        for (0..limit) |slot| {
            const st = &self.file_storage[slot];
            const p_len: usize = st.path_len;
            const is_prev = self.files[slot].is_markdown_preview;
            const is_bound_prev = self.files[slot].is_bound_markdown_preview;
            const is_wave = self.files[slot].is_waveform_preview;
            const is_pdf = self.files[slot].is_pdf_preview;
            const is_diff = self.files[slot].is_git_diff_preview;
            const is_term = self.files[slot].is_terminal;
            const is_agt = self.files[slot].is_agent;
            if (is_prev or is_wave or is_pdf or is_diff or is_term or is_agt) {
                st.folder.set("*special*");
            }
            self.files[slot].name = if (is_bound_prev and st.custom_name.len > 0)
                st.custom_name.slice()
            else if (is_prev)
                "*Markdown Preview*"
            else if (is_wave)
                "*Waveform Preview*"
            else if (is_pdf)
                "*PDF Preview*"
            else if (is_diff)
                "*Git Diff*"
            else if (is_term or is_agt)
                st.path_buf[0..p_len]
            else
                st.path_buf[st.name_offset..p_len];
            self.files[slot].path = st.path_buf[0..p_len :0];
            self.files[slot].folder = st.folder.slice();
        }
    }

    fn removeWorkspaceFileSlot(self: *EditorState, remove_idx: usize) void {
        if (remove_idx >= self.file_count or self.file_count <= 1) return;
        if (self.files[remove_idx].is_terminal) {
            const t_slot = self.files[remove_idx].terminal_slot;
            if (t_slot < self.term_vterms.len) {
                self.term_vterms[t_slot].deinit();
                self.term_vterms[t_slot] = ui.VTerm.init();
                self.term_slot_used[t_slot] = false;
            }
        }
        if (self.files[remove_idx].is_agent) {
            const a_slot = self.files[remove_idx].agent_slot;
            if (a_slot < self.agent_sessions.len) {
                self.agent_sessions[a_slot].deinit();
                self.agent_sessions[a_slot] = agy_client.AgySession.init();
                self.agent_prompts[a_slot].clear();
                self.agent_slot_used[a_slot] = false;
            }
        }
        self.killBufferWithoutRemovingSlot(remove_idx);
        if (self.buffer_initialized[remove_idx]) {
            self.buffers[remove_idx].deinit();
            self.buffer_initialized[remove_idx] = false;
        }

        var i = remove_idx;
        while (i + 1 < self.file_count) : (i += 1) {
            self.file_storage[i] = self.file_storage[i + 1];
            self.files[i] = self.files[i + 1];
            self.buffers[i] = self.buffers[i + 1];
            self.buffer_initialized[i] = self.buffer_initialized[i + 1];
            self.saved_versions[i] = self.saved_versions[i + 1];
            self.loaded_from_disk[i] = self.loaded_from_disk[i + 1];
            self.disk_mtime_hashes[i] = self.disk_mtime_hashes[i + 1];
            self.buffer_word_wrap[i] = self.buffer_word_wrap[i + 1];
            self.git_file_statuses[i] = self.git_file_statuses[i + 1];
        }
        self.buffer_initialized[self.file_count - 1] = false;
        self.disk_mtime_hashes[self.file_count - 1] = 0;
        self.buffer_word_wrap[self.file_count - 1] = 0;
        self.git_file_statuses[self.file_count - 1] = .{};
        self.file_count -= 1;
        self.rebindDynamicFileSlices();

        // Adjust any open buffer / pane tab indices above `remove_idx`
        const open_n = self.openBufferCount();
        for (0..open_n) |b_i| {
            if (self.doc.open_buffers[b_i] > remove_idx) {
                self.doc.open_buffers[b_i] -= 1;
            }
        }
        for (0..MaxEditorPanes) |p_i| {
            const t_n = @min(@as(usize, self.doc.panes[p_i].tab_count), MaxTabsPerPane);
            for (0..t_n) |t_i| {
                if (self.doc.panes[p_i].tabs[t_i] > remove_idx) {
                    self.doc.panes[p_i].tabs[t_i] -= 1;
                }
            }
        }
        if (self.doc.md_preview_source_idx > remove_idx) {
            self.doc.md_preview_source_idx -= 1;
        }
        if (self.doc.waveform_preview_source_idx > remove_idx) {
            self.doc.waveform_preview_source_idx -= 1;
        }
        if (self.doc.pdf_preview_source_idx > remove_idx) {
            self.doc.pdf_preview_source_idx -= 1;
        }
        if (self.doc.git_diff_source_idx > remove_idx) {
            self.doc.git_diff_source_idx -= 1;
        }
        for (0..self.file_count) |f_i| {
            if (self.files[f_i].is_bound_markdown_preview and
                self.files[f_i].md_preview_source_idx != 0xFFFF and
                self.files[f_i].md_preview_source_idx > remove_idx)
            {
                self.files[f_i].md_preview_source_idx -= 1;
            }
        }
    }

    fn registerDiscoveredWorkspaceFile(self: *EditorState, rel_path: []const u8) void {
        if (rel_path.len == 0 or rel_path.len >= 254) return;

        var existing_opt: ?usize = null;
        for (self.files[0..self.file_count], 0..) |wf, idx| {
            if (!wf.isSpecial() and std.mem.eql(u8, wf.path, rel_path)) {
                existing_opt = idx;
                break;
            }
        }

        if (shouldIgnoreScannedPath(rel_path)) return;

        if (existing_opt) |idx| {
            self.file_storage[idx].seen_on_disk = true;
            if (!self.isFileDirty(idx) and (self.isBufferOpen(idx) or self.bufferVisibleInPane(idx) != null)) {
                _ = self.reloadFileFromDiskIfChanged(idx);
            }
        } else {
            const new_idx = self.file_count;
            const lang = detectLanguageForPath(rel_path);
            self.storeDynamicFileSlot(new_idx, rel_path, lang, false, false, "");
            const buf = self.ensureBufferSlotInit(new_idx);
            self.saved_versions[new_idx] = buf.edit_version;
            self.loaded_from_disk[new_idx] = false;
            self.disk_mtime_hashes[new_idx] = 0;
            self.git_file_statuses[new_idx] = .{};
            self.file_storage[new_idx].seen_on_disk = true;
            self.file_count += 1;
        }
    }

    /// Scans the workspace directory tree in breadth-first alphabetical order so shallow project
    /// files (root files, `src/`, `examples/`, `scripts/`, `Testing/`) are always indexed first,
    /// growing `self.files_list` and `self.folder_list` dynamically on demand.
    pub fn refreshWorkspaceFiles(self: *EditorState, show_notice: bool) void {
        self.syncWorkspaceRootFromCwd();
        if (!self.has_opened_workspace) {
            var dst: usize = 0;
            for (0..self.file_count) |src| {
                if (self.files[src].isSpecial()) {
                    if (dst != src) {
                        self.file_storage[dst] = self.file_storage[src];
                        self.files[dst] = self.files[src];
                        self.buffers[dst] = self.buffers[src];
                        self.buffer_initialized[dst] = self.buffer_initialized[src];
                        self.saved_versions[dst] = self.saved_versions[src];
                        self.loaded_from_disk[dst] = self.loaded_from_disk[src];
                        self.disk_mtime_hashes[dst] = self.disk_mtime_hashes[src];
                        self.buffer_word_wrap[dst] = self.buffer_word_wrap[src];
                        self.git_file_statuses[dst] = self.git_file_statuses[src];
                        self.buffer_initialized[src] = false;
                    }
                    dst += 1;
                } else if (self.buffer_initialized[src]) {
                    self.buffers[src].deinit();
                    self.buffer_initialized[src] = false;
                }
            }
            self.file_count = dst;
            self.rebindDynamicFileSlices();
            self.folder_count = 0;
            self.git_commit_count = 0;
            return;
        }
        if (self.file_count == 0) {
            for (WORKSPACE_FILES) |seed| {
                if (!seed.isSpecial() and !fileExistsOnDisk(seed.path)) continue;
                const idx = self.file_count;
                self.storeDynamicFileSlot(idx, seed.path, seed.language, seed.is_markdown_preview, seed.is_waveform_preview, seed.initial_source);
                if (seed.is_pdf_preview) {
                    self.files[idx].is_pdf_preview = true;
                    self.files[idx].name = "*PDF Preview*";
                    self.file_storage[idx].folder.set("*special*");
                    self.files[idx].folder = self.file_storage[idx].folder.slice();
                }
                if (seed.is_git_diff_preview) {
                    self.files[idx].is_git_diff_preview = true;
                    self.files[idx].name = "*Git Diff*";
                    self.file_storage[idx].folder.set("*special*");
                    self.files[idx].folder = self.file_storage[idx].folder.slice();
                }
                self.file_count = idx + 1;
                self.loadFileFromDiskOrFallback(idx);
            }
        } else {
            self.rebindDynamicFileSlices();
        }

        for (0..self.file_count) |i| {
            self.file_storage[i].seen_on_disk = false;
        }

        // Walk the workspace directory tree on disk in breadth-first sorted order so both empty
        // directories and source files up to depth 16 are discovered deterministically.
        self.scanWorkspaceDirectories(true);

        // Remove any workspace files that were deleted from disk
        var any_seen = false;
        for (0..self.file_count) |i| {
            if (self.file_storage[i].seen_on_disk) {
                any_seen = true;
                break;
            }
        }
        if (any_seen) {
            var idx: usize = self.file_count;
            while (idx > 0) {
                idx -= 1;
                const wf = self.files[idx];
                if (wf.isSpecial()) continue;
                if (!self.file_storage[idx].seen_on_disk and !fileExistsOnDisk(wf.path)) {
                    self.removeWorkspaceFileSlot(idx);
                }
            }
        } else {
            var idx: usize = self.file_count;
            while (idx > 0) {
                idx -= 1;
                const wf = self.files[idx];
                if (wf.isSpecial()) continue;
                if (!fileExistsOnDisk(wf.path)) {
                    self.removeWorkspaceFileSlot(idx);
                }
            }
        }

        _ = self.reloadModifiedOpenFiles();
        self.refreshGitStatus();
        self.last_watch_sig = self.computeWorkspaceWatchSignature();

        if (show_notice) {
            var msg_buf: [96]u8 = undefined;
            const msg = std.fmt.bufPrint(
                &msg_buf,
                "Refreshed workspace ({d} files)",
                .{self.nonSpecialFileCount()},
            ) catch "Refreshed workspace files";
            self.setStatusNotice(msg);
        }
    }

    pub const shouldIgnoreDirectoryName = workspace_fs.shouldIgnoreDirectoryName;
    pub const shouldIgnoreDirName = workspace_fs.shouldIgnoreDirName;
    pub const isDirectoryOnDisk = workspace_fs.isDirectoryOnDisk;
    pub const asciiLessThanIgnoreCaseSlice = workspace_fs.asciiLessThanIgnoreCaseSlice;

    fn scanSingleDirectoryLevel(
        self: *EditorState,
        rel_dir: []const u8,
        depth: usize,
        collect_files: bool,
    ) void {
        if (depth > 16) return;

        var dir_z: [256:0]u8 = @splat(0);
        if (rel_dir.len == 0) {
            dir_z[0] = '.';
            dir_z[1] = 0;
        } else {
            if (rel_dir.len >= 254) return;
            @memcpy(dir_z[0..rel_dir.len], rel_dir);
            dir_z[rel_dir.len] = 0;
        }

        const dirp = posix_dir.opendir(&dir_z) orelse return;
        defer _ = posix_dir.closedir(dirp);

        const alloc = std.heap.c_allocator;
        var file_names: std.ArrayListUnmanaged(platform.InlineString(256)) = .empty;
        defer file_names.deinit(alloc);
        var dir_names: std.ArrayListUnmanaged(platform.InlineString(256)) = .empty;
        defer dir_names.deinit(alloc);

        while (posix_dir.readdir(dirp)) |ent| {
            const namlen: usize = @min(@as(usize, ent.d_namlen), ent.d_name.len);
            const name = ent.d_name[0..namlen];
            if (name.len == 0 or std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;
            // Skip symbolic links so we never traverse links to external volumes (e.g. /Volumes/...)
            if (ent.d_type == posix_dir.DT_LNK) continue;
            if (!collect_files and ent.d_type == posix_dir.DT_REG) continue;

            const effective_name = unwrapICloudPlaceholder(name) orelse name;

            var child_buf: [256:0]u8 = @splat(0);
            const child_slice = if (rel_dir.len == 0)
                std.fmt.bufPrint(child_buf[0..254], "{s}", .{effective_name}) catch continue
            else
                std.fmt.bufPrint(child_buf[0..254], "{s}/{s}", .{ rel_dir, effective_name }) catch continue;
            child_buf[child_slice.len] = 0;

            const is_dir = if (ent.d_type == posix_dir.DT_DIR)
                true
            else if (ent.d_type == 0)
                isDirectoryOnDisk(&child_buf)
            else
                false;

            if (is_dir) {
                if (shouldIgnoreDirectoryName(name)) continue;
                if (name.len < 256) {
                    var dn: platform.InlineString(256) = .{};
                    dn.set(name);
                    dir_names.append(alloc, dn) catch {};
                }
            } else if (collect_files) {
                if (effective_name.len < 256) {
                    var already_present = false;
                    for (file_names.items) |*fn_entry| {
                        if (std.mem.eql(u8, fn_entry.slice(), effective_name)) {
                            already_present = true;
                            break;
                        }
                    }
                    if (!already_present) {
                        var fn_item: platform.InlineString(256) = .{};
                        fn_item.set(effective_name);
                        file_names.append(alloc, fn_item) catch {};
                    }
                }
            }
        }

        // 1. Sort and register all immediate files in `rel_dir` FIRST so shallow files are prioritized
        if (collect_files and file_names.items.len > 0) {
            if (file_names.items.len > 1) {
                var i: usize = 1;
                while (i < file_names.items.len) : (i += 1) {
                    const cur = file_names.items[i];
                    var j: usize = i;
                    while (j > 0 and asciiLessThanIgnoreCaseSlice(cur.slice(), file_names.items[j - 1].slice())) : (j -= 1) {
                        file_names.items[j] = file_names.items[j - 1];
                    }
                    file_names.items[j] = cur;
                }
            }
            for (file_names.items) |*fn_entry| {
                var child_buf: [256:0]u8 = @splat(0);
                const child_slice = if (rel_dir.len == 0)
                    std.fmt.bufPrint(child_buf[0..254], "{s}", .{fn_entry.slice()}) catch continue
                else
                    std.fmt.bufPrint(child_buf[0..254], "{s}/{s}", .{ rel_dir, fn_entry.slice() }) catch continue;
                self.registerDiscoveredWorkspaceFile(child_slice);
            }
        }

        // 2. Sort and queue immediate subdirectories into `self.folder_storage` for breadth-first traversal
        if (depth < 16 and dir_names.items.len > 0) {
            if (dir_names.items.len > 1) {
                var i: usize = 1;
                while (i < dir_names.items.len) : (i += 1) {
                    const cur = dir_names.items[i];
                    var j: usize = i;
                    while (j > 0 and asciiLessThanIgnoreCaseSlice(cur.slice(), dir_names.items[j - 1].slice())) : (j -= 1) {
                        dir_names.items[j] = dir_names.items[j - 1];
                    }
                    dir_names.items[j] = cur;
                }
            }
            for (dir_names.items) |*dn_entry| {
                var child_buf: [256:0]u8 = @splat(0);
                const child_slice = if (rel_dir.len == 0)
                    std.fmt.bufPrint(child_buf[0..254], "{s}", .{dn_entry.slice()}) catch continue
                else
                    std.fmt.bufPrint(child_buf[0..254], "{s}/{s}", .{ rel_dir, dn_entry.slice() }) catch continue;

                var exists = false;
                for (self.folder_storage[0..self.folder_count]) |*existing| {
                    if (existing.eql(child_slice)) {
                        exists = true;
                        break;
                    }
                }
                if (!exists) {
                    const f_idx = self.folder_count;
                    self.ensureFolderSlot(f_idx);
                    if (f_idx < self.folder_storage.len) {
                        self.folder_storage[f_idx].set(child_slice);
                        self.folder_count = f_idx + 1;
                    }
                }
            }
        }
    }

    pub fn scanWorkspaceDirectories(self: *EditorState, collect_files: bool) void {
        self.folder_count = 0;
        self.scanSingleDirectoryLevel("", 0, collect_files);
        var q_idx: usize = 0;
        while (q_idx < self.folder_count) : (q_idx += 1) {
            var dir_buf: [256]u8 = undefined;
            const dslice = self.folder_storage[q_idx].slice();
            const dlen = @min(dslice.len, dir_buf.len);
            @memcpy(dir_buf[0..dlen], dslice[0..dlen]);
            const depth = 1 + std.mem.count(u8, dir_buf[0..dlen], "/");
            // Always scan expanded directories, shallow directories (depth <= 1), and all project
            // directories while total indexed files < 4096; unexpanded deep vendor/archive folders
            // in massive workspaces (e.g. Desktop) are scanned lazily on expand (`setFolderExpanded`).
            if (collect_files and self.file_count >= 4096 and depth > 1 and !self.isFolderExpanded(dir_buf[0..dlen])) {
                continue;
            }
            self.scanSingleDirectoryLevel(dir_buf[0..dlen], depth, collect_files);
        }
    }

    pub const statMtimeHash = workspace_fs.statMtimeHash;

    fn computeWorkspaceWatchSignature(self: *const EditorState) u64 {
        const base_watched_paths = [_][*:0]const u8{
            ".",
            ".gitignore",
            ".git/index",
            ".git/HEAD",
            ".git/logs/HEAD",
            ".git/COMMIT_EDITMSG",
        };
        var sig: u64 = 0x9E37_79B9_7F4A_7C15;
        for (base_watched_paths, 0..) |wp, idx| {
            const h = statMtimeHash(wp);
            sig = (sig ^ (h +% (@as(u64, @intCast(idx)) *% 0x517C_C1B7_2722_0A95))) *% 0xBF58_476D_1CE4_E5B9;
        }
        // Stat up to 16 expanded workspace directories so newly created or deleted files in visible folders trigger a refresh without heavy syscall overhead on external volumes
        var watched_dirs: usize = 0;
        for (self.folder_storage[0..self.folder_count], 0..) |*dir_entry, idx| {
            if (watched_dirs >= 16) break;
            const dslice = dir_entry.slice();
            if (!self.isFolderExpanded(dslice)) continue;
            if (dslice.len > 0 and dslice.len < 127) {
                var dir_z: [128:0]u8 = @splat(0);
                @memcpy(dir_z[0..dslice.len], dslice);
                dir_z[dslice.len] = 0;
                const dh = statMtimeHash(&dir_z);
                sig = (sig ^ (dh +% (@as(u64, @intCast(idx + 8)) *% 0x517C_C1B7_2722_0A95))) *% 0xBF58_476D_1CE4_E5B9;
                watched_dirs += 1;
            }
        }
        // Stat any open buffer files so external edits/deletions of open files are detected immediately
        for (0..self.file_count) |f_idx| {
            if (!self.files[f_idx].isSpecial() and (self.isBufferOpen(f_idx) or self.bufferVisibleInPane(f_idx) != null or self.isFileReferencedByOpenPreview(f_idx))) {
                var fh = statMtimeHash(self.files[f_idx].path.ptr);
                if (fh == 0 and fileExistsOnDisk(self.files[f_idx].path)) {
                    fh = 0xA5A5_5A5A_F0F0_0F0F;
                }
                sig = (sig ^ (fh +% (@as(u64, @intCast(f_idx + 192)) *% 0x94D0_49BB_1331_11EB))) *% 0xBF58_476D_1CE4_E5B9;
            }
        }
        return sig;
    }

    /// Lightweight filesystem watcher polled during input frames (~800ms interval).
    /// Uses fast `stat` and file-existence checks on workspace directories, `.gitignore`, and tracked
    /// files, triggering `refreshWorkspaceFiles(false)` automatically when files are added, deleted, or ignored.
    pub fn pollWorkspaceWatch(self: *EditorState) void {
        if (self.ui_ctx.pass != .input) return;
        if (self.pending_native_folder_pick) {
            self.pending_native_folder_pick = false;
            if (self.ui_ctx.platform_ctx) |pctx| {
                // Consume any in-flight shortcut key events before and after the modal dialog
                // so a single Cmd+O or menu click can never re-trigger the dialog a second time.
                pctx.clearFrameInput();
                self.ui_ctx.key_events = &.{};
                var picked_buf: [512]u8 = undefined;
                if (pctx.pickFolderDialog(&picked_buf)) |picked| {
                    _ = self.openWorkspaceDirectory(picked);
                }
                pctx.clearFrameInput();
                self.ui_ctx.key_events = &.{};
                pctx.force_full_redraw = true;
                self.ui_ctx.invalidateWindow();
            }
        }
        if (self.file_count > 0 and self.files[0].path.ptr != @as([*:0]const u8, @ptrCast(&self.file_storage[0].path_buf))) {
            self.rebindDynamicFileSlices();
        }

        const now_ms: i64 = @intCast(platform.profiler.nowNs() / std.time.ns_per_ms);
        const is_scrolling = (self.ui_ctx.scroll_dy != 0 or self.ui_ctx.scroll_dx != 0);

        // Poll Antigravity (`agy`) local socket stream every input frame across the side panel and all active `*agent-N*` buffers
        self.syncAgyHubState();
        if (!@import("builtin").is_test and !self.anyAgyModelsAttempted()) {
            self.agy.ensureModelsLoaded();
        }
        var any_agy_changed = self.agy.pollWithHint(now_ms, is_scrolling);
        var any_agy_active = (self.agy.is_running_turn and !self.agy.pending_question.active) or
            self.agy.sock_fd >= 0 or
            self.agy.active_poll_frames > 0 or
            self.agy.scroll_to_bottom_frames > 0;
        var any_turn_completed = self.agy.turn_completed_flag;
        if (self.agy.turn_completed_flag) self.agy.turn_completed_flag = false;

        for (0..self.agent_slot_used.len) |a_i| {
            if (!self.agent_slot_used[a_i]) continue;
            var sess = &self.agent_sessions[a_i];
            if (sess.pollWithHint(now_ms, is_scrolling)) {
                any_agy_changed = true;
            }
            if ((sess.is_running_turn and !sess.pending_question.active) or
                sess.sock_fd >= 0 or
                sess.active_poll_frames > 0 or
                sess.scroll_to_bottom_frames > 0)
            {
                any_agy_active = true;
            }
            if (sess.turn_completed_flag) {
                sess.turn_completed_flag = false;
                any_turn_completed = true;
            }
        }
        self.syncAgyHubState();

        if (any_agy_changed) {
            self.ui_ctx.invalidateWindow();
        }
        if (any_agy_active) {
            if (self.ui_ctx.platform_ctx) |pctx| pctx.needs_continuous_redraw = true;
        }
        if (any_turn_completed) {
            if (self.has_opened_workspace) {
                self.refreshWorkspaceFiles(false);
                self.agy.syncWorkspaceRoot(self.workspaceRoot());
                self.syncAgyHubState();
            }
            self.ui_ctx.invalidateWindow();
        }

        // When no workspace directory is opened, do not watch or poll filesystem/git
        if (!self.has_opened_workspace) return;

        // Poll non-blocking Git status / commit log pipe every input frame
        if (self.git_poller.poll(
            self.workspaceFiles(),
            &self.git_branch,
            self.git_file_statuses[0..self.file_count],
            &self.git_commits,
            &self.git_commit_count,
        )) {
            // Re-snapshot watch signature after `git status` finishes so `.git/index` stat-cache updates
            // from our own git status poller do not trigger a redundant `refreshWorkspaceFiles` loop.
            self.last_watch_sig = self.computeWorkspaceWatchSignature();
            self.ui_ctx.invalidateWindow();
        }
        if (self.git_poller.isBusy()) {
            if (self.ui_ctx.platform_ctx) |pctx| pctx.needs_continuous_redraw = true;
        }

        // Poll Antigravity Supercomplete only when a debounced trigger or active socket stream is in flight
        self.supercomplete.enabled = self.doc.supercomplete_enabled;
        if (self.supercomplete.enabled and (self.supercomplete.pending_trigger_ms > 0 or self.supercomplete.sock_fd >= 0 or self.supercomplete.active_poll_frames > 0)) {
            if (self.activeFileIndex()) |f_idx| {
                const wf = self.workspaceFiles()[f_idx];
                if (!wf.isSpecial()) {
                    const buf = &self.buffers[f_idx];
                    const lc = buf.offsetToLineCol(buf.cursor);
                    var uri_buf: [384]u8 = undefined;
                    const ws_root = self.workspaceRoot();
                    const uri_prefix = if (ws_root.len > 0 and ws_root[0] == '/') "file://" else "file:///";
                    const abs_uri = std.fmt.bufPrint(&uri_buf, "{s}{s}/{s}", .{ uri_prefix, ws_root, wf.path }) catch "file:///workspace/file";
                    const lang_id = switch (wf.language) {
                        .zig => "zig",
                        .cpp => "cpp",
                        .java => "java",
                        .go => "go",
                        .systemverilog => "systemverilog",
                        .rust => "rust",
                        .python => "python",
                        .typescript => "typescript",
                        .vhdl => "vhdl",
                        .chisel => "scala",
                        .devicetree => "devicetree",
                        .markdown => "markdown",
                        .json => "json",
                        .bash => "shellscript",
                        .plain => "plaintext",
                    };
                    if (self.supercomplete.poll(
                        now_ms,
                        f_idx,
                        abs_uri,
                        lang_id,
                        buf.slice(),
                        buf.cursor,
                        lc.line,
                        lc.col,
                        buf.edit_version,
                    )) {
                        self.ui_ctx.invalidateWindow();
                    }
                }
            } else {
                const buf = &self.scratch_buf;
                const lc = buf.offsetToLineCol(buf.cursor);
                var scratch_uri_buf: [384]u8 = undefined;
                const ws_root = self.workspaceRoot();
                const uri_prefix = if (ws_root.len > 0 and ws_root[0] == '/') "file://" else "file:///";
                const scratch_uri = std.fmt.bufPrint(&scratch_uri_buf, "{s}{s}/scratch.md", .{ uri_prefix, ws_root }) catch "file:///workspace/scratch.md";
                if (self.supercomplete.poll(
                    now_ms,
                    999,
                    scratch_uri,
                    "markdown",
                    buf.slice(),
                    buf.cursor,
                    lc.line,
                    lc.col,
                    buf.edit_version,
                )) {
                    self.ui_ctx.invalidateWindow();
                }
            }
            if (self.supercomplete.sock_fd >= 0 or self.supercomplete.pending_trigger_ms > 0 or self.supercomplete.active_poll_frames > 0) {
                if (self.ui_ctx.platform_ctx) |pctx| pctx.needs_continuous_redraw = true;
            }
        }

        // Poll dynamically loaded `.dylib` plugins (hot-reload check + non-blocking I/O pollers)
        self.plugins.pollPluginsInputPass(self);

        // Defer synchronous filesystem/directory sweeps while the user is actively scrolling a buffer
        if (is_scrolling) return;

        const watch_interval_ms: i64 = if (any_agy_active) 4000 else 2000;
        if (self.last_watch_poll_ms != 0 and now_ms - self.last_watch_poll_ms < watch_interval_ms) return;
        self.last_watch_poll_ms = now_ms;

        const reloaded = self.reloadModifiedOpenFiles();
        const sig = self.computeWorkspaceWatchSignature();
        if (self.last_watch_sig == 0) {
            self.last_watch_sig = sig;
            if (reloaded > 0) {
                self.refreshGitStatus();
                self.ui_ctx.invalidateWindow();
            }
            return;
        }
        if (sig != self.last_watch_sig) {
            self.last_watch_sig = sig;
            self.refreshWorkspaceFiles(false);
            self.agy.syncWorkspaceRoot(self.workspaceRoot());
            self.ui_ctx.invalidateWindow();
        } else if (reloaded > 0) {
            self.refreshGitStatus();
            self.ui_ctx.invalidateWindow();
        }
    }

    // ========================================================================
    // Multi-Tab & Recursive Binary Split Tree Management
    // ========================================================================

    pub fn paneCount(self: *const EditorState) usize {
        return std.math.clamp(@as(usize, self.doc.split_tree.pane_count), 1, MaxEditorPanes);
    }

    pub fn activePaneIndex(self: *const EditorState) usize {
        return self.doc.split_tree.activePaneIndex();
    }

    pub fn editorWidgetIdForPane(pane_idx: usize) ui.WidgetId {
        const clamped = @min(pane_idx, MaxEditorPanes - 1);
        return ui.id(PANE_EDITOR_IDS[clamped]);
    }

    pub fn activeEditorWidgetId(self: *const EditorState) ui.WidgetId {
        return editorWidgetIdForPane(self.activePaneIndex());
    }

    /// Returns `true` when keyboard focus is inside the bottom-panel `VTerm` (`workbench_vterm`)
    /// or inside a split editor pane whose active buffer is a `*terminal-N*` buffer.
    pub fn isTerminalFocused(self: *const EditorState) bool {
        const fid = self.ui_ctx.focused_id;
        if (fid == ui.id("workbench_vterm")) return true;
        const p_count = self.paneCount();
        const wfs = self.workspaceFiles();
        for (0..p_count) |p_idx| {
            if (fid == editorWidgetIdForPane(p_idx)) {
                if (self.paneActiveFile(p_idx)) |f_idx| {
                    if (f_idx < wfs.len and wfs[f_idx].is_terminal) return true;
                }
            }
        }
        return false;
    }

    pub fn ensureValidSplitTree(self: *EditorState) void {
        self.doc.split_tree.ensureValid();
    }

    pub fn paneActiveFile(self: *const EditorState, pane_idx: usize) ?usize {
        if (pane_idx >= MaxEditorPanes) return null;
        return self.doc.panes[pane_idx].activeItem(self.fileCount());
    }

    pub fn activeFileIndex(self: *const EditorState) ?usize {
        return self.paneActiveFile(self.activePaneIndex());
    }

    pub fn isBufferWordWrap(self: *const EditorState, file_idx_opt: ?usize) bool {
        if (file_idx_opt) |f_idx| {
            if (f_idx < self.files.len) {
                const override = self.buffer_word_wrap[f_idx];
                if (override == 1) return false;
                if (override == 2) return true;
                return self.files[f_idx].language == .markdown;
            }
        }
        return self.scratch_word_wrap;
    }

    pub fn toggleBufferWordWrap(self: *EditorState, file_idx_opt: ?usize) bool {
        const cur = self.isBufferWordWrap(file_idx_opt);
        const new_val = !cur;
        if (file_idx_opt) |f_idx| {
            if (f_idx < self.files.len) {
                self.buffer_word_wrap[f_idx] = if (new_val) 2 else 1;
            }
        } else {
            self.scratch_word_wrap = new_val;
        }
        return new_val;
    }

    pub fn activeEditorBuffer(self: *EditorState) *ui.CodeEditorBuffer(BufferCapacity) {
        if (self.activeFileIndex()) |f_idx| {
            const clamped = f_idx % self.fileCount();
            self.ensureFileLoaded(clamped);
            return &self.buffers[clamped];
        }
        return &self.scratch_buf;
    }

    pub fn openBufferCount(self: *const EditorState) usize {
        return @min(@as(usize, self.doc.open_buffer_count), @min(MaxOpenBuffers, self.fileCount()));
    }

    pub fn isBufferOpen(self: *const EditorState, file_idx: usize) bool {
        const count = self.openBufferCount();
        const total = self.fileCount();
        for (0..count) |i| {
            if (@as(usize, self.doc.open_buffers[i]) % total == file_idx) return true;
        }
        return false;
    }

    /// Returns the 1-based window index (`1..pane_count`) if `file_idx` is currently displayed in any split pane.
    pub fn bufferVisibleInPane(self: *const EditorState, file_idx: usize) ?usize {
        const p_count = self.paneCount();
        for (0..p_count) |p_idx| {
            if (self.paneActiveFile(p_idx)) |f| {
                if (f == file_idx) return p_idx;
            }
        }
        return null;
    }

    pub fn ensureBufferInOpenList(self: *EditorState, file_idx_raw: usize) void {
        const total = self.fileCount();
        if (total == 0) return;
        const file_idx: u16 = @intCast(file_idx_raw % total);
        self.ensureFileLoaded(file_idx);
        const count = self.openBufferCount();
        for (0..count) |i| {
            if (self.doc.open_buffers[i] == file_idx) return;
        }
        if (count < @min(MaxOpenBuffers, total)) {
            self.doc.open_buffers[count] = file_idx;
            self.doc.open_buffer_count = @intCast(count + 1);
        } else if (count > 0) {
            self.doc.open_buffers[count - 1] = file_idx;
        }
    }

    /// Kills/closes `file_idx` from the global open buffers list and switches any split window
    /// displaying `file_idx` to the next open buffer.
    pub fn killBuffer(self: *EditorState, file_idx_raw: usize) void {
        const total = self.fileCount();
        if (total == 0) return;
        const file_idx = file_idx_raw % total;
        if (file_idx < self.file_count and (self.files[file_idx].is_terminal or self.files[file_idx].is_agent or self.files[file_idx].is_bound_markdown_preview) and self.file_count > 1) {
            self.removeWorkspaceFileSlot(file_idx);
            return;
        }
        self.killBufferWithoutRemovingSlot(file_idx);
    }

    fn killBufferWithoutRemovingSlot(self: *EditorState, file_idx_raw: usize) void {
        const file_idx: u16 = @intCast(file_idx_raw % self.fileCount());
        const count = self.openBufferCount();
        var found_slot: ?usize = null;
        for (0..count) |i| {
            if (self.doc.open_buffers[i] == file_idx) {
                found_slot = i;
                break;
            }
        }

        if (found_slot) |slot| {
            var i = slot;
            while (i + 1 < count) : (i += 1) {
                self.doc.open_buffers[i] = self.doc.open_buffers[i + 1];
            }
            self.doc.open_buffer_count = @intCast(count - 1);
        }

        const new_count = self.openBufferCount();
        const p_count = self.paneCount();
        for (0..p_count) |p_idx| {
            if (self.paneActiveFile(p_idx) == @as(usize, file_idx)) {
                if (new_count > 0) {
                    const replacement_slot = if (found_slot) |s| @min(s, new_count - 1) else 0;
                    const next_file = self.doc.open_buffers[replacement_slot];
                    self.doc.panes[p_idx].setSingleItem(next_file);
                } else {
                    self.doc.panes[p_idx].clear();
                }
            }
        }

        if (self.activeFileIndex()) |f_idx| {
            self.syncCursorTelemetry(f_idx);
        }
        self.ui_ctx.focused_id = self.activeEditorWidgetId();
    }

    /// Switches the buffer shown in the currently focused split window (`openFile`).
    pub fn openFile(self: *EditorState, file_idx: usize) void {
        self.openFileInPane(self.activePaneIndex(), file_idx);
    }

    /// Switches `pane_idx` to display `file_idx` (and adds `file_idx` to the open buffers list if needed).
    pub fn openFileInPane(self: *EditorState, pane_idx_raw: usize, file_idx_raw: usize) void {
        self.ensureValidSplitTree();
        const total = self.fileCount();
        if (total == 0) return;
        const pane_idx = @min(pane_idx_raw, self.paneCount() - 1);
        const file_idx: u16 = @intCast(file_idx_raw % total);
        self.doc.split_tree.active_pane = @intCast(pane_idx);

        const wf = self.workspaceFiles()[file_idx];
        if (wf.language == .markdown and !wf.is_markdown_preview) {
            self.doc.md_preview_source_idx = file_idx;
        }
        if (isWaveformCandidatePath(wf.path) and !wf.is_waveform_preview) {
            self.doc.waveform_preview_source_idx = file_idx;
            if (std.mem.endsWith(u8, wf.path, ".vcd")) {
                self.waveform_custom_vcd.clear();
            }
        }
        if (isPdfCandidatePath(wf.path) and !wf.is_pdf_preview) {
            self.doc.pdf_preview_source_idx = file_idx;
            self.pdf_custom_path.set(wf.path);
            self.pdf_custom_bytes.clear();
        }

        const was_open = self.isBufferOpen(file_idx) or self.bufferVisibleInPane(file_idx) != null;
        self.ensureBufferInOpenList(file_idx);

        self.doc.panes[pane_idx].setSingleItem(file_idx);
        if (!was_open and self.loaded_from_disk[file_idx] and !self.isFileDirty(file_idx)) {
            _ = self.reloadFileFromDiskIfChanged(file_idx);
        }

        self.syncCursorTelemetry(file_idx);
        self.plugins.notifyBufferOpen(self, file_idx);
        self.ui_ctx.focused_id = self.activeEditorWidgetId();
        self.ui_ctx.invalidateWindow();
    }

    /// Creates a new interactive PTY-backed `*terminal-N*` buffer either in the active split window
    /// (`split_to_side == false`) or in a new horizontal split window to the right (`split_to_side == true`).
    pub fn createTerminalBuffer(self: *EditorState, split_to_side: bool) void {
        if (self.file_count == 0) {
            self.refreshWorkspaceFiles(false);
            self.agy.syncWorkspaceRoot(self.workspaceRoot());
        }

        const new_idx = self.ensureFreeDynamicFileSlot() orelse return;
        const t_slot = self.allocTerminalSlot();
        self.term_vterms[t_slot].deinit();
        self.term_vterms[t_slot] = ui.VTerm.init();
        self.term_slot_used[t_slot] = true;

        var name_buf: [32]u8 = undefined;
        const term_name = std.fmt.bufPrint(&name_buf, "*terminal-{d}*", .{self.next_term_number}) catch "*terminal*";
        self.next_term_number +%= 1;
        if (self.next_term_number == 0) self.next_term_number = 1;

        self.storeDynamicFileSlot(new_idx, term_name, .bash, false, false, "");
        self.files[new_idx].is_terminal = true;
        self.files[new_idx].terminal_slot = @intCast(t_slot);
        self.file_storage[new_idx].folder.set("*special*");
        self.files[new_idx].folder = self.file_storage[new_idx].folder.slice();
        self.files[new_idx].name = self.file_storage[new_idx].path_buf[0..self.file_storage[new_idx].path_len];
        const term_buf = self.ensureBufferSlotInit(new_idx);
        term_buf.resetWithSlice("");
        self.saved_versions[new_idx] = term_buf.edit_version;
        self.loaded_from_disk[new_idx] = false;
        self.disk_mtime_hashes[new_idx] = 0;
        if (new_idx >= self.file_count) self.file_count = new_idx + 1;

        self.ensureBufferInOpenList(new_idx);
        if (split_to_side) {
            self.splitPaneDirection(self.activePaneIndex(), false, false, new_idx, null);
        } else {
            self.openFile(new_idx);
        }

        var msg_buf: [64]u8 = undefined;
        const msg = std.fmt.bufPrint(&msg_buf, "Created {s}", .{term_name}) catch "Created terminal buffer";
        self.setStatusNotice(msg);
    }

    /// Creates a new interactive Antigravity `*agent-N*` buffer sharing the same `agy` process hub
    /// either in the active split window (`split_to_side == false`) or in a new horizontal split window
    /// to the right (`split_to_side == true`).
    pub fn createAgentBuffer(self: *EditorState, split_to_side: bool) void {
        if (self.file_count == 0) {
            self.refreshWorkspaceFiles(false);
            self.agy.syncWorkspaceRoot(self.workspaceRoot());
            self.syncAgyHubState();
        }

        const new_idx = self.ensureFreeDynamicFileSlot() orelse return;
        const a_slot = self.allocAgentSlot();
        self.agent_sessions[a_slot].deinit();
        self.agent_sessions[a_slot] = agy_client.AgySession.init();
        self.agent_sessions[a_slot].mode = self.agy.mode;
        self.agent_sessions[a_slot].effort = self.agy.effort;
        self.agent_sessions[a_slot].selected_model_idx = self.agy.selected_model_idx;
        self.agent_sessions[a_slot].shareHubStateFrom(&self.agy);
        self.agent_prompts[a_slot].clear();
        self.agent_slot_used[a_slot] = true;
        self.syncAgyHubState();

        var name_buf: [32]u8 = undefined;
        const agent_name = std.fmt.bufPrint(&name_buf, "*agent-{d}*", .{self.next_agent_number}) catch "*agent*";
        self.next_agent_number +%= 1;
        if (self.next_agent_number == 0) self.next_agent_number = 1;

        self.storeDynamicFileSlot(new_idx, agent_name, .markdown, false, false, "");
        self.files[new_idx].is_agent = true;
        self.files[new_idx].agent_slot = @intCast(a_slot);
        self.file_storage[new_idx].folder.set("*special*");
        self.files[new_idx].folder = self.file_storage[new_idx].folder.slice();
        self.files[new_idx].name = self.file_storage[new_idx].path_buf[0..self.file_storage[new_idx].path_len];
        const agent_buf = self.ensureBufferSlotInit(new_idx);
        agent_buf.resetWithSlice("");
        self.saved_versions[new_idx] = agent_buf.edit_version;
        self.loaded_from_disk[new_idx] = false;
        self.disk_mtime_hashes[new_idx] = 0;
        if (new_idx >= self.file_count) self.file_count = new_idx + 1;

        self.ensureBufferInOpenList(new_idx);
        if (split_to_side) {
            self.splitPaneDirection(self.activePaneIndex(), false, false, new_idx, null);
        } else {
            self.openFile(new_idx);
        }

        var msg_buf: [64]u8 = undefined;
        const msg = std.fmt.bufPrint(&msg_buf, "Created {s}", .{agent_name}) catch "Created agent buffer";
        self.setStatusNotice(msg);
    }

    /// Creates/opens the `*Markdown Preview*` buffer either in the active split window (`split_to_side == false`)
    /// or in a new horizontal split window to the right (`split_to_side == true`).
    pub fn openMarkdownPreviewBuffer(self: *EditorState, split_to_side: bool) void {
        if (self.activeFileIndex()) |cur_idx| {
            const cur_wf = self.workspaceFiles()[cur_idx];
            if (cur_wf.language == .markdown and !cur_wf.is_markdown_preview) {
                self.doc.md_preview_source_idx = @intCast(cur_idx);
            }
        }
        const preview_idx = self.markdownPreviewBufferIndex();
        self.ensureBufferInOpenList(preview_idx);
        if (split_to_side) {
            self.splitPaneDirection(self.activePaneIndex(), false, false, preview_idx, null);
        } else {
            self.openFile(preview_idx);
        }
        self.setStatusNotice("Opened *Markdown Preview* buffer");
    }

    /// Creates/opens a Markdown preview buffer that is permanently tied to the currently open buffer
    /// (unlike the global `*Markdown Preview*`, which switches whenever a different Markdown file is opened).
    pub fn createBoundMarkdownPreviewBuffer(self: *EditorState, split_to_side: bool) void {
        if (self.file_count == 0) {
            self.refreshWorkspaceFiles(false);
            self.agy.syncWorkspaceRoot(self.workspaceRoot());
        }

        const wfs = self.workspaceFiles();
        const target_idx_opt: ?usize = if (self.activeFileIndex()) |cur_idx| blk: {
            if (cur_idx >= wfs.len) break :blk null;
            const cur_wf = wfs[cur_idx];
            if (cur_wf.is_markdown_preview) {
                if (self.isScratchMarkdownPreview(cur_idx)) break :blk null;
                break :blk self.findMarkdownPreviewSourceIndexForBuffer(cur_idx);
            }
            if (cur_wf.is_git_diff_preview) break :blk self.findGitDiffPreviewSourceIndex();
            if (cur_wf.is_waveform_preview) break :blk self.findWaveformPreviewSourceIndex();
            if (cur_wf.is_pdf_preview) break :blk self.findPdfPreviewSourceIndex();
            if (cur_wf.isSpecial()) break :blk self.findMarkdownPreviewSourceIndex();
            break :blk cur_idx;
        } else null;

        const target_path: []const u8 = if (target_idx_opt) |t_idx| self.files[t_idx].path else "*scratch*";
        const target_name: []const u8 = if (target_idx_opt) |t_idx| self.files[t_idx].name else "*scratch*";
        const bound_src_val: u16 = if (target_idx_opt) |t_idx| @intCast(t_idx) else 0xFFFF;

        var existing_preview_idx: ?usize = null;
        for (self.files[0..self.file_count], 0..) |wf, idx| {
            if (wf.is_markdown_preview and wf.is_bound_markdown_preview) {
                if (target_idx_opt != null) {
                    if (wf.md_preview_source_idx == bound_src_val or std.mem.eql(u8, wf.path, target_path)) {
                        existing_preview_idx = idx;
                        break;
                    }
                } else if (wf.md_preview_source_idx == 0xFFFF or std.mem.eql(u8, wf.path, "*scratch*")) {
                    existing_preview_idx = idx;
                    break;
                }
            }
        }

        const preview_idx: usize = if (existing_preview_idx) |ex_idx| blk: {
            self.files[ex_idx].md_preview_source_idx = bound_src_val;
            break :blk ex_idx;
        } else if (self.ensureFreeDynamicFileSlot()) |new_idx| blk: {
            var name_buf: [64]u8 = undefined;
            var preview_name = std.fmt.bufPrint(&name_buf, "*Markdown Preview: {s}*", .{target_name}) catch "*Markdown Preview (Pinned)*";
            for (self.files[0..self.file_count]) |wf| {
                if (wf.isSpecial() and std.mem.eql(u8, wf.name, preview_name)) {
                    preview_name = std.fmt.bufPrint(&name_buf, "*Markdown Preview: {s}*", .{target_path}) catch "*Markdown Preview (Pinned)*";
                    break;
                }
            }
            self.storeDynamicFileSlot(new_idx, target_path, .markdown, true, false, "");
            self.files[new_idx].is_markdown_preview = true;
            self.files[new_idx].is_bound_markdown_preview = true;
            self.files[new_idx].md_preview_source_idx = bound_src_val;
            self.file_storage[new_idx].folder.set("*special*");
            self.file_storage[new_idx].custom_name.set(preview_name);
            self.files[new_idx].folder = self.file_storage[new_idx].folder.slice();
            self.files[new_idx].name = self.file_storage[new_idx].custom_name.slice();
            const p_buf = self.ensureBufferSlotInit(new_idx);
            p_buf.resetWithSlice("");
            self.saved_versions[new_idx] = p_buf.edit_version;
            self.loaded_from_disk[new_idx] = false;
            self.disk_mtime_hashes[new_idx] = 0;
            self.git_file_statuses[new_idx] = .{};
            self.file_count += 1;
            break :blk new_idx;
        } else self.markdownPreviewBufferIndex();

        self.ensureBufferInOpenList(preview_idx);
        if (split_to_side) {
            self.splitPaneDirection(self.activePaneIndex(), false, false, preview_idx, null);
        } else {
            self.openFile(preview_idx);
        }
        var msg_buf: [96]u8 = undefined;
        const msg = std.fmt.bufPrint(&msg_buf, "Opened {s} (tied to {s})", .{ self.files[preview_idx].name, target_name }) catch "Opened tied Markdown preview buffer";
        self.setStatusNotice(msg);
    }

    pub fn isScratchMarkdownPreview(self: *const EditorState, preview_file_idx: usize) bool {
        const wfs = self.workspaceFiles();
        if (preview_file_idx >= wfs.len) return false;
        const wf = wfs[preview_file_idx];
        return wf.is_markdown_preview and wf.is_bound_markdown_preview and
            (wf.md_preview_source_idx == 0xFFFF or std.mem.eql(u8, wf.path, "*scratch*"));
    }

    pub fn findMarkdownPreviewSourceIndexForBuffer(self: *const EditorState, preview_file_idx: usize) ?usize {
        const wfs = self.workspaceFiles();
        if (wfs.len == 0) return null;
        if (preview_file_idx < wfs.len) {
            const wf = wfs[preview_file_idx];
            if (wf.is_markdown_preview and wf.is_bound_markdown_preview) {
                if (wf.md_preview_source_idx == 0xFFFF or std.mem.eql(u8, wf.path, "*scratch*")) {
                    return null;
                }
                const bound_idx: usize = wf.md_preview_source_idx;
                if (bound_idx < wfs.len and !wfs[bound_idx].isSpecial() and std.mem.eql(u8, wfs[bound_idx].path, wf.path)) {
                    return bound_idx;
                }
                if (self.findWorkspaceFileIndexByPath(wf.path)) |by_path| {
                    return by_path;
                }
                if (bound_idx < wfs.len and !wfs[bound_idx].isSpecial()) {
                    return bound_idx;
                }
            }
        }
        return self.findMarkdownPreviewSourceIndex();
    }

    pub fn markdownPreviewSourceIndexForBuffer(self: *const EditorState, preview_file_idx: usize) usize {
        return self.findMarkdownPreviewSourceIndexForBuffer(preview_file_idx) orelse 0;
    }

    pub fn markdownPreviewSourceName(self: *const EditorState, preview_file_idx: usize) []const u8 {
        if (self.isScratchMarkdownPreview(preview_file_idx)) return "*scratch*";
        const wfs = self.workspaceFiles();
        if (wfs.len == 0) return "*scratch*";
        const src_idx = self.markdownPreviewSourceIndexForBuffer(preview_file_idx);
        return wfs[src_idx % wfs.len].name;
    }

    pub fn markdownPreviewSourcePath(self: *const EditorState, preview_file_idx: usize) []const u8 {
        if (self.isScratchMarkdownPreview(preview_file_idx)) return "*scratch*";
        const wfs = self.workspaceFiles();
        if (wfs.len == 0) return "*scratch*";
        const src_idx = self.markdownPreviewSourceIndexForBuffer(preview_file_idx);
        return wfs[src_idx % wfs.len].path;
    }

    pub fn isFileReferencedByOpenPreview(self: *const EditorState, file_idx: usize) bool {
        const wfs = self.workspaceFiles();
        for (wfs, 0..) |wf, p_idx| {
            if (!wf.is_markdown_preview) continue;
            if (!self.isBufferOpen(p_idx) and self.bufferVisibleInPane(p_idx) == null) continue;
            if (self.findMarkdownPreviewSourceIndexForBuffer(p_idx)) |src_idx| {
                if (src_idx == file_idx) return true;
            }
        }
        return false;
    }

    pub fn findMarkdownPreviewSourceIndex(self: *const EditorState) ?usize {
        const wfs = self.workspaceFiles();
        if (wfs.len == 0) return null;
        const idx: usize = @as(usize, self.doc.md_preview_source_idx) % wfs.len;
        if (wfs[idx].language == .markdown and !wfs[idx].is_markdown_preview) {
            return idx;
        }
        for (wfs, 0..) |wf, i| {
            if (wf.language == .markdown and !wf.isSpecial()) {
                return i;
            }
        }
        if (self.activeFileIndex()) |active_idx| {
            if (active_idx < wfs.len and !wfs[active_idx].is_markdown_preview) {
                return active_idx;
            }
        }
        return null;
    }

    pub fn markdownPreviewSourceIndex(self: *const EditorState) usize {
        return self.findMarkdownPreviewSourceIndex() orelse 0;
    }

    pub const isWaveformCandidatePath = workspace_fs.isWaveformCandidatePath;

    /// Creates/opens the `*Waveform Preview*` buffer either in the active split window (`split_to_side == false`)
    /// or in a new horizontal split window to the right (`split_to_side == true`).
    pub fn openWaveformPreviewBuffer(self: *EditorState, split_to_side: bool) void {
        if (self.activeFileIndex()) |cur_idx| {
            const cur_wf = self.workspaceFiles()[cur_idx];
            if (isWaveformCandidatePath(cur_wf.path) and !cur_wf.is_waveform_preview) {
                self.doc.waveform_preview_source_idx = @intCast(cur_idx);
                if (std.mem.endsWith(u8, cur_wf.path, ".vcd")) {
                    self.waveform_custom_vcd.clear();
                }
            }
        }
        const preview_idx = self.waveformPreviewBufferIndex();
        self.ensureBufferInOpenList(preview_idx);
        if (split_to_side) {
            self.splitPaneDirection(self.activePaneIndex(), false, false, preview_idx, null);
        } else {
            self.openFile(preview_idx);
        }
        self.setStatusNotice("Opened *Waveform Preview* buffer");
    }

    /// Opens `*Waveform Preview*` with an explicit VCD trace payload (e.g., from a simulator plugin).
    pub fn openWaveformPreviewWithSource(self: *EditorState, vcd_source: []const u8, split_to_side: bool) void {
        if (vcd_source.len > 0) {
            self.waveform_custom_vcd.set(vcd_source);
        }
        self.openWaveformPreviewBuffer(split_to_side);
    }

    pub fn findWaveformPreviewSourceIndex(self: *const EditorState) ?usize {
        const wfs = self.workspaceFiles();
        if (wfs.len == 0) return null;
        const idx: usize = @as(usize, self.doc.waveform_preview_source_idx) % wfs.len;
        if (isWaveformCandidatePath(wfs[idx].path) and !wfs[idx].is_waveform_preview) {
            return idx;
        }
        for (wfs, 0..) |wf, i| {
            if (std.mem.endsWith(u8, wf.path, ".vcd") and !wf.is_waveform_preview) return i;
        }
        for (wfs, 0..) |wf, i| {
            if (isWaveformCandidatePath(wf.path) and !wf.is_waveform_preview) return i;
        }
        return null;
    }

    pub fn waveformPreviewSourceIndex(self: *const EditorState) usize {
        return self.findWaveformPreviewSourceIndex() orelse 0;
    }

    pub const isVcdCandidatePath = workspace_fs.isVcdCandidatePath;
    pub const isPdfCandidatePath = workspace_fs.isPdfCandidatePath;
    pub const isImageCandidatePath = workspace_fs.isImageCandidatePath;

    /// Creates/opens the `*PDF Preview*` buffer either in the active split window (`split_to_side == false`)
    /// or in a new horizontal split window to the right (`split_to_side == true`).
    pub fn openPdfPreviewBuffer(self: *EditorState, split_to_side: bool) void {
        if (self.activeFileIndex()) |cur_idx| {
            const cur_wf = self.workspaceFiles()[cur_idx];
            if (isPdfCandidatePath(cur_wf.path) and !cur_wf.is_pdf_preview) {
                self.doc.pdf_preview_source_idx = @intCast(cur_idx);
                self.pdf_custom_path.set(cur_wf.path);
                self.pdf_custom_bytes.clear();
            }
        }
        const preview_idx = self.pdfPreviewBufferIndex();
        self.ensureBufferInOpenList(preview_idx);
        if (split_to_side) {
            self.splitPaneDirection(self.activePaneIndex(), false, false, preview_idx, null);
        } else {
            self.openFile(preview_idx);
        }
        self.setStatusNotice("Opened *PDF Preview* buffer");
    }

    /// Opens `*PDF Preview*` with an explicit file path or in-memory PDF payload (e.g., from `pdf_reader` plugin).
    pub fn openPdfPreviewWithSource(self: *EditorState, file_path: []const u8, raw_bytes: []const u8, split_to_side: bool) void {
        if (file_path.len > 0) {
            self.pdf_custom_path.set(file_path);
            if (self.findWorkspaceFileIndexByPath(file_path)) |f_idx| {
                self.doc.pdf_preview_source_idx = @intCast(f_idx);
            }
        }
        if (raw_bytes.len > 0) {
            self.pdf_custom_bytes.set(raw_bytes);
        } else if (file_path.len > 0) {
            self.pdf_custom_bytes.clear();
        }
        self.openPdfPreviewBuffer(split_to_side);
    }

    pub fn findPdfPreviewSourceIndex(self: *const EditorState) ?usize {
        const wfs = self.workspaceFiles();
        if (wfs.len == 0) return null;
        const idx: usize = @as(usize, self.doc.pdf_preview_source_idx) % wfs.len;
        if (isPdfCandidatePath(wfs[idx].path) and !wfs[idx].is_pdf_preview) {
            return idx;
        }
        for (wfs, 0..) |wf, i| {
            if (isPdfCandidatePath(wf.path) and !wf.is_pdf_preview) return i;
        }
        return null;
    }

    pub fn pdfPreviewSourceIndex(self: *const EditorState) usize {
        return self.findPdfPreviewSourceIndex() orelse 0;
    }

    pub const PdfPaneSource = struct {
        file_idx: usize,
        eff_path: []const u8,
        eff_bytes: []const u8,
        is_direct_pdf: bool,
    };

    /// Returns the resolved PDF file/bytes source if `pane_idx` is currently displaying a PDF
    /// (`*PDF Preview*` or a `.pdf` workspace file), or `null` if the pane is showing another buffer type.
    pub fn resolvePdfSourceForPane(self: *EditorState, pane_idx: usize) ?PdfPaneSource {
        const file_idx = self.paneActiveFile(pane_idx) orelse return null;
        const wfs = self.workspaceFiles();
        if (file_idx >= wfs.len) return null;
        const active_file = wfs[file_idx];
        if (!active_file.is_pdf_preview and !isPdfCandidatePath(active_file.path)) return null;

        const is_direct_pdf = !active_file.is_pdf_preview and isPdfCandidatePath(active_file.path);
        const src_idx = if (is_direct_pdf) file_idx else self.pdfPreviewSourceIndex();
        self.ensureFileLoaded(src_idx);
        const src_wf = self.workspaceFiles()[src_idx];
        const src_slice = self.buffers[src_idx].slice();
        const is_pdf_file = isPdfCandidatePath(src_wf.path) or std.mem.startsWith(u8, src_slice, "%PDF-");

        const custom_path = self.pdf_custom_path.slice();
        const custom_bytes = self.pdf_custom_bytes.slice();
        const eff_path = if (is_direct_pdf)
            active_file.path
        else if (custom_path.len > 0)
            custom_path
        else if (is_pdf_file)
            src_wf.path
        else
            "";
        const eff_bytes = if (is_direct_pdf)
            src_slice
        else if (custom_bytes.len > 0)
            custom_bytes
        else if (eff_path.len > 0)
            src_slice
        else
            ui.SAMPLE_PDF_DOC;

        return .{
            .file_idx = file_idx,
            .eff_path = eff_path,
            .eff_bytes = eff_bytes,
            .is_direct_pdf = is_direct_pdf,
        };
    }

    pub fn pdfViewStateForPane(
        self: *EditorState,
        pane_idx: usize,
        file_idx: usize,
        is_direct_pdf: bool,
    ) *ui.PdfViewState {
        const pdf_slot = @min(pane_idx, MaxEditorPanes - 1);
        if (is_direct_pdf and self.ui_ctx.platform_ctx != null) {
            return self.ui_ctx.useState(
                ui.PdfViewState,
                self.ui_ctx.fmt("workbench_pdf_state_{d}_{d}", .{ pane_idx, file_idx }),
                .{},
            );
        }
        return &self.pdf_views[pdf_slot];
    }

    pub fn findGitDiffPreviewSourceIndex(self: *const EditorState) ?usize {
        const wfs = self.workspaceFiles();
        if (wfs.len == 0) return null;
        const idx: usize = @as(usize, self.doc.git_diff_source_idx) % wfs.len;
        if (!wfs[idx].isSpecial()) return idx;
        for (wfs, 0..) |wf, i| {
            if (!wf.isSpecial()) return i;
        }
        return null;
    }

    pub fn gitDiffPreviewSourceIndex(self: *const EditorState) usize {
        return self.findGitDiffPreviewSourceIndex() orelse 0;
    }

    pub fn refreshActiveGitDiffContent(self: *EditorState) void {
        const src_idx = self.gitDiffPreviewSourceIndex();
        const wfs = self.workspaceFiles();
        const commit_sha = self.git_diff_commit.slice();
        const custom_path = self.git_diff_custom_path.slice();
        const rel_path = if (custom_path.len > 0)
            custom_path
        else if (commit_sha.len > 0)
            ""
        else if (src_idx < wfs.len and !wfs[src_idx].isSpecial())
            wfs[src_idx].path
        else
            "";

        const err_null = if (@import("builtin").os.tag == .windows) "2>NUL" else "2>/dev/null";
        var cmd_buf: [512]u8 = undefined;
        const cmd_slice = if (commit_sha.len > 0 and rel_path.len > 0)
            std.fmt.bufPrint(&cmd_buf, "git show --format=short -U4 \"{s}\" -- \"{s}\" " ++ err_null ++ "\x00", .{ commit_sha, rel_path }) catch return
        else if (commit_sha.len > 0)
            std.fmt.bufPrint(&cmd_buf, "git show --format=short -U4 \"{s}\" " ++ err_null ++ "\x00", .{commit_sha}) catch return
        else if (self.doc.git_diff_staged and rel_path.len > 0)
            std.fmt.bufPrint(&cmd_buf, "git diff --cached -U4 -- \"{s}\" " ++ err_null ++ "\x00", .{rel_path}) catch return
        else if (rel_path.len > 0)
            std.fmt.bufPrint(&cmd_buf, "git diff -U4 -- \"{s}\" " ++ err_null ++ "\x00", .{rel_path}) catch return
        else
            std.fmt.bufPrint(&cmd_buf, "git diff -U4 " ++ err_null ++ "\x00", .{}) catch return;

        var out_buf: [16384]u8 = undefined;
        var total_read: usize = 0;
        const cmd_z: [*:0]const u8 = @ptrCast(cmd_slice.ptr);
        if (popen(cmd_z, "r")) |fp| {
            defer _ = pclose(fp);
            while (total_read < out_buf.len) {
                const n = std.c.fread(out_buf[total_read..].ptr, 1, out_buf.len - total_read, fp);
                if (n == 0) break;
                total_read += n;
            }
        }

        // If working-tree diff is empty and we are not viewing a commit, also check `git diff HEAD`
        if (total_read == 0 and commit_sha.len == 0 and rel_path.len > 0) {
            if (std.fmt.bufPrint(&cmd_buf, "git diff HEAD -U4 -- \"{s}\" " ++ err_null ++ "\x00", .{rel_path})) |head_cmd| {
                const head_z: [*:0]const u8 = @ptrCast(head_cmd.ptr);
                if (popen(head_z, "r")) |fp| {
                    defer _ = pclose(fp);
                    while (total_read < out_buf.len) {
                        const n = std.c.fread(out_buf[total_read..].ptr, 1, out_buf.len - total_read, fp);
                        if (n == 0) break;
                        total_read += n;
                    }
                }
            } else |_| {}
        }

        self.git_diff_custom_text.set(out_buf[0..total_read]);

        var title_buf: [128]u8 = undefined;
        const title_str = if (commit_sha.len > 0 and rel_path.len > 0)
            std.fmt.bufPrint(&title_buf, "{s} @ {s}", .{ rel_path, commit_sha }) catch rel_path
        else if (commit_sha.len > 0)
            std.fmt.bufPrint(&title_buf, "commit {s}", .{commit_sha}) catch commit_sha
        else if (rel_path.len > 0)
            rel_path
        else
            "Workspace Diff";
        self.git_diff_title.set(title_str);
        for (&self.git_diff_views) |*dv| {
            dv.scroll_y = 0;
            dv.scroll_x = 0;
            dv.current_hunk = 0;
            dv.selected_row = 0;
        }
    }

    /// Creates/opens the `*Git Diff*` buffer either in the active split window (`split_to_side == false`)
    /// or in a new horizontal split window to the right (`split_to_side == true`).
    pub fn openGitDiffPreviewBuffer(self: *EditorState, split_to_side: bool) void {
        if (self.activeFileIndex()) |cur_idx| {
            const cur_wf = self.workspaceFiles()[cur_idx];
            if (!cur_wf.isSpecial()) {
                self.doc.git_diff_source_idx = @intCast(cur_idx);
                self.doc.git_diff_staged = self.isFileStaged(cur_idx) and !self.isFileUnstagedChange(cur_idx);
                self.git_diff_commit.clear();
                self.git_diff_custom_path.clear();
            }
        }
        self.refreshActiveGitDiffContent();
        const preview_idx = self.gitDiffPreviewBufferIndex();
        self.ensureBufferInOpenList(preview_idx);
        if (split_to_side) {
            self.splitPaneDirection(self.activePaneIndex(), false, false, preview_idx, null);
        } else {
            self.openFile(preview_idx);
        }
        self.setStatusNotice("Opened *Git Diff* buffer");
    }

    /// Opens `*Git Diff*` for a specific workspace path, staged/unstaged state, or commit SHA.
    pub fn openGitDiffForFile(
        self: *EditorState,
        rel_path: []const u8,
        commit_sha: []const u8,
        staged: bool,
        split_to_side: bool,
    ) void {
        self.git_diff_custom_path.set(rel_path);
        if (rel_path.len > 0) {
            if (self.findWorkspaceFileIndexByPath(rel_path)) |f_idx| {
                self.doc.git_diff_source_idx = @intCast(f_idx);
            }
        } else if (commit_sha.len == 0) {
            if (self.activeFileIndex()) |cur_idx| {
                if (!self.workspaceFiles()[cur_idx].isSpecial()) {
                    self.doc.git_diff_source_idx = @intCast(cur_idx);
                }
            }
        }
        self.doc.git_diff_staged = staged;
        self.git_diff_commit.set(commit_sha);
        self.refreshActiveGitDiffContent();

        const preview_idx = self.gitDiffPreviewBufferIndex();
        self.ensureBufferInOpenList(preview_idx);
        if (split_to_side) {
            self.splitPaneDirection(self.activePaneIndex(), false, false, preview_idx, null);
        } else {
            self.openFile(preview_idx);
        }
        self.setStatusNotice("Opened *Git Diff* buffer");
        self.ui_ctx.invalidateWindow();
    }

    pub fn pluginIdHash(id: []const u8) u64 {
        return std.hash.Fnv1a_64.hash(id);
    }

    pub fn isPluginEnabledInDoc(self: *const EditorState, id: []const u8) bool {
        const h = pluginIdHash(id);
        const count = @min(@as(usize, self.doc.disabled_plugin_count), self.doc.disabled_plugin_hashes.len);
        for (self.doc.disabled_plugin_hashes[0..count]) |dh| {
            if (dh == h) return false;
        }
        return true;
    }

    pub fn setPluginEnabledInDoc(self: *EditorState, id: []const u8, enabled: bool) void {
        const h = pluginIdHash(id);
        var count: usize = @min(@as(usize, self.doc.disabled_plugin_count), self.doc.disabled_plugin_hashes.len);
        if (enabled) {
            var i: usize = 0;
            while (i < count) {
                if (self.doc.disabled_plugin_hashes[i] == h) {
                    var j = i;
                    while (j + 1 < count) : (j += 1) {
                        self.doc.disabled_plugin_hashes[j] = self.doc.disabled_plugin_hashes[j + 1];
                    }
                    self.doc.disabled_plugin_hashes[count - 1] = 0;
                    count -= 1;
                } else {
                    i += 1;
                }
            }
            self.doc.disabled_plugin_count = @intCast(count);
        } else {
            for (self.doc.disabled_plugin_hashes[0..count]) |dh| {
                if (dh == h) return;
            }
            if (count < self.doc.disabled_plugin_hashes.len) {
                self.doc.disabled_plugin_hashes[count] = h;
                self.doc.disabled_plugin_count = @intCast(count + 1);
            }
        }
    }

    /// Cycles the buffer displayed in `pane_idx_raw` forward (`delta > 0`) or backward (`delta < 0`)
    /// through the open buffers list (like Emacs mode-line left-click / right-click on the buffer name).
    pub fn cyclePaneBuffer(self: *EditorState, pane_idx_raw: usize, delta: isize) void {
        self.ensureValidSplitTree();
        const pane_idx = @min(pane_idx_raw, self.paneCount() - 1);
        self.doc.split_tree.active_pane = @intCast(pane_idx);

        const open_count = self.openBufferCount();
        if (open_count == 0) return;

        const cur_file = self.paneActiveFile(pane_idx) orelse self.doc.open_buffers[0];
        const total = self.fileCount();

        if (open_count > 1 and self.paneActiveFile(pane_idx) != null) {
            var cur_slot: usize = 0;
            for (0..open_count) |i| {
                if (@as(usize, self.doc.open_buffers[i]) % total == cur_file) {
                    cur_slot = i;
                    break;
                }
            }
            const next_slot: usize = if (delta >= 0)
                (cur_slot + 1) % open_count
            else
                (cur_slot + open_count - 1) % open_count;
            const next_file: u16 = self.doc.open_buffers[next_slot] % @as(u16, @intCast(total));
            self.doc.panes[pane_idx].setSingleItem(next_file);
            self.syncCursorTelemetry(next_file);
        } else {
            const next_file: u16 = self.doc.open_buffers[0] % @as(u16, @intCast(total));
            self.doc.panes[pane_idx].setSingleItem(next_file);
            self.syncCursorTelemetry(next_file);
        }
        self.ui_ctx.focused_id = self.activeEditorWidgetId();
    }

    /// Closes tab `tab_idx` in `pane_idx`. Collapses the split pane automatically if it becomes empty and `pane_count > 1`.
    pub fn closeTabInPane(self: *EditorState, pane_idx: usize, tab_idx: usize) void {
        self.ensureValidSplitTree();
        if (pane_idx >= self.paneCount()) return;
        const pane = &self.doc.panes[pane_idx];
        if (!pane.removeTabSlot(tab_idx)) return;

        if (pane.tab_count == 0 and self.paneCount() > 1) {
            self.closeSplitPane(pane_idx);
            return;
        }

        if (self.activeFileIndex()) |f_idx| {
            self.syncCursorTelemetry(f_idx);
        }
        self.ui_ctx.focused_id = self.activeEditorWidgetId();
    }

    /// Closes the active split window if `pane_count > 1` (`C-x 0`), or kills the active buffer (`Cmd+W`).
    pub fn closeActiveTab(self: *EditorState) void {
        const p_idx = self.activePaneIndex();
        if (self.paneCount() > 1) {
            self.closeSplitPane(p_idx);
        } else if (self.paneActiveFile(p_idx)) |f_idx| {
            self.killBuffer(f_idx);
        }
    }

    /// Splits `target_pane_raw` either horizontally (`vertical == false`, left/right) or vertically (`vertical == true`, top/bottom)
    /// via `ui.SplitTree.splitLeaf`.
    pub fn splitPaneDirection(
        self: *EditorState,
        target_pane_raw: usize,
        vertical: bool,
        place_new_first: bool,
        explicit_file: ?usize,
        remove_tab_from_target: ?usize,
    ) void {
        self.ensureValidSplitTree();
        const target_pane = @min(target_pane_raw, self.paneCount() - 1);
        const src_pane_ptr = &self.doc.panes[target_pane];
        const default_tab_slot: ?usize = if (explicit_file == null and src_pane_ptr.tab_count > 1)
            @min(@as(usize, src_pane_ptr.active_tab), @as(usize, src_pane_ptr.tab_count - 1))
        else
            remove_tab_from_target;

        const opt_file = explicit_file orelse self.paneActiveFile(target_pane);

        const new_pane_idx = self.doc.split_tree.splitLeaf(target_pane, vertical, place_new_first) orelse {
            if (opt_file) |raw_file| {
                self.openFileInPane(target_pane, raw_file);
            }
            return;
        };

        if (default_tab_slot) |rem_slot| {
            if (src_pane_ptr.tab_count > 1) {
                _ = src_pane_ptr.removeTabSlot(rem_slot);
            }
        }

        if (opt_file) |raw_file| {
            if (self.fileCount() > 0) {
                const file_idx: u16 = @intCast(raw_file % self.fileCount());
                self.doc.panes[new_pane_idx] = .{};
                self.doc.panes[new_pane_idx].setSingleItem(file_idx);
                if (self.buffer_initialized[file_idx] and explicit_file == null) {
                    self.buffers[file_idx].copyScrollStateBetweenPanes(target_pane, new_pane_idx);
                }
                self.syncCursorTelemetry(file_idx);
            } else {
                self.doc.panes[new_pane_idx] = .{};
            }
        } else {
            self.doc.panes[new_pane_idx] = .{};
            self.scratch_buf.copyScrollStateBetweenPanes(target_pane, new_pane_idx);
        }

        self.ui_ctx.focused_id = self.activeEditorWidgetId();
    }

    /// Splits `pane_idx` horizontally (left/right).
    pub fn splitPaneHorizontal(self: *EditorState, pane_idx: usize) void {
        self.splitPaneDirection(pane_idx, false, false, null, null);
    }

    /// Splits `pane_idx` vertically (top/bottom).
    pub fn splitPaneVertical(self: *EditorState, pane_idx: usize) void {
        self.splitPaneDirection(pane_idx, true, false, null, null);
    }

    /// Splits the currently active editor pane horizontally (`Cmd+\`).
    pub fn splitEditorRight(self: *EditorState) void {
        self.splitPaneHorizontal(self.activePaneIndex());
    }

    /// Splits the currently active editor pane vertically (`Shift+Cmd+\`).
    pub fn splitEditorDown(self: *EditorState) void {
        self.splitPaneVertical(self.activePaneIndex());
    }

    /// Closes split pane `close_pane_idx` via `ui.SplitTree.removeLeaf` and shifts `doc.panes`.
    pub fn closeSplitPane(self: *EditorState, close_pane_idx: usize) void {
        const old_pane_count = self.paneCount();
        if (!self.doc.split_tree.removeLeaf(close_pane_idx)) return;

        var i: usize = close_pane_idx;
        while (i + 1 < old_pane_count) : (i += 1) {
            self.doc.panes[i] = self.doc.panes[i + 1];
            self.git_diff_views[i] = self.git_diff_views[i + 1];
            self.pdf_views[i] = self.pdf_views[i + 1];
            self.image_views[i] = self.image_views[i + 1];
            self.scratch_buf.copyScrollStateBetweenPanes(i + 1, i);
            for (0..self.file_count) |f_i| {
                if (self.buffer_initialized[f_i]) {
                    self.buffers[f_i].copyScrollStateBetweenPanes(i + 1, i);
                }
            }
        }

        if (self.activeFileIndex()) |f_idx| {
            self.syncCursorTelemetry(f_idx);
        }
        self.ui_ctx.focused_id = self.activeEditorWidgetId();
    }

    pub fn focusPane(self: *EditorState, pane_idx: usize) void {
        if (pane_idx < self.paneCount()) {
            self.doc.split_tree.active_pane = @intCast(pane_idx);
            if (self.activeFileIndex()) |f_idx| {
                self.syncCursorTelemetry(f_idx);
            }
            self.ui_ctx.focused_id = self.activeEditorWidgetId();
        }
    }

    /// Swaps two tabs inside `pane_idx` (used for live drag-to-reorder tabs).
    pub fn swapTabsInPane(self: *EditorState, pane_idx: usize, idx_a: usize, idx_b: usize) void {
        if (pane_idx >= self.paneCount()) return;
        _ = self.doc.panes[pane_idx].swapTabs(idx_a, idx_b);
    }

    /// Moves a tab from `src_pane` (`src_tab_idx`) to `dst_pane` (collapsing `src_pane` if it had only 1 tab).
    pub fn moveTabBetweenPanes(self: *EditorState, src_pane: usize, src_tab_idx: usize, dst_pane: usize) void {
        self.ensureValidSplitTree();
        const p_count = self.paneCount();
        if (src_pane == dst_pane or src_pane >= p_count or dst_pane >= p_count) return;
        const pane = &self.doc.panes[src_pane];
        const count: usize = @min(@as(usize, pane.tab_count), MaxTabsPerPane);
        if (src_tab_idx >= count) return;

        const file_idx = pane.tabs[src_tab_idx];
        const src_had_multiple = (pane.tab_count > 1);
        self.openFileInPane(dst_pane, file_idx);

        if (self.paneCount() > 1) {
            self.closeTabInPane(src_pane, src_tab_idx);
            if (src_had_multiple and self.paneCount() > 1) {
                const adj_dst = if (!src_had_multiple and src_pane < dst_pane) dst_pane - 1 else dst_pane;
                self.doc.split_tree.active_pane = @intCast(@min(adj_dst, self.paneCount() - 1));
            }
            self.syncCursorTelemetry(file_idx);
            self.ui_ctx.focused_id = self.activeEditorWidgetId();
        }
    }

    /// Handles dropping a dragged tab (`src_pane`, `src_tab_idx`) onto `target_pane` in `zone`.
    pub fn dropTabOnPane(
        self: *EditorState,
        src_pane: usize,
        src_tab_idx: usize,
        target_pane: usize,
        zone: SplitDropZone,
    ) void {
        self.ensureValidSplitTree();
        const p_count = self.paneCount();
        if (src_pane >= p_count or target_pane >= p_count) return;
        const src_p = &self.doc.panes[src_pane];
        const count: usize = @min(@as(usize, src_p.tab_count), MaxTabsPerPane);
        if (src_tab_idx >= count) return;

        if (zone == .center) {
            if (src_pane != target_pane) {
                self.moveTabBetweenPanes(src_pane, src_tab_idx, target_pane);
            }
            return;
        }

        const vertical = (zone == .top or zone == .bottom);
        const place_new_first = (zone == .left or zone == .top);
        const file_idx = src_p.tabs[src_tab_idx];

        if (src_pane == target_pane) {
            const rem_slot: ?usize = if (src_p.tab_count > 1) src_tab_idx else null;
            self.splitPaneDirection(target_pane, vertical, place_new_first, file_idx, rem_slot);
            return;
        }

        if (src_p.tab_count <= 1 and p_count > 1) {
            const adj_target = if (src_pane < target_pane) target_pane - 1 else target_pane;
            self.closeSplitPane(src_pane);
            self.splitPaneDirection(adj_target, vertical, place_new_first, file_idx, null);
        } else {
            _ = src_p.removeTabSlot(src_tab_idx);
            self.splitPaneDirection(target_pane, vertical, place_new_first, file_idx, null);
        }
    }

    /// Moves the currently active tab to the next split pane (or splits right if only 1 pane is open).
    pub fn moveActiveTabToOtherSplit(self: *EditorState) void {
        self.ensureValidSplitTree();
        const cur_pane = self.activePaneIndex();
        const pane = &self.doc.panes[cur_pane];
        const active_t = pane.activeSlot() orelse return;

        const p_count = self.paneCount();
        if (p_count < 2) {
            self.dropTabOnPane(cur_pane, active_t, cur_pane, .right);
        } else {
            const target_pane: usize = (cur_pane + 1) % p_count;
            self.moveTabBetweenPanes(cur_pane, active_t, target_pane);
        }
    }

    pub fn syncCursorTelemetry(self: *EditorState, file_idx: usize) void {
        const clamped = file_idx % self.fileCount();
        self.ensureFileLoaded(clamped);
        const lc = self.buffers[clamped].cursorLineCol();
        self.doc.cursor_line = @intCast(lc.line);
        self.doc.cursor_col = @intCast(lc.col);
    }

    // ========================================================================
    // Disk File Loading, Saving & Dirty State
    // ========================================================================

    pub fn ensureFileLoaded(self: *EditorState, idx: usize) void {
        if (idx >= self.file_count) return;
        _ = self.ensureBufferSlotInit(idx);
        if (!self.loaded_from_disk[idx] and !self.isFileDirty(idx) and !self.files[idx].isSpecial()) {
            if (self.disk_mtime_hashes[idx] != 0 and isDatalessFileOnDisk(self.files[idx].path.ptr)) {
                return;
            }
            self.loadFileFromDiskOrFallback(idx);
        }
    }

    pub fn loadFileFromDiskOrFallback(self: *EditorState, idx: usize) void {
        const buf = self.ensureBufferSlotInit(idx);
        const file = self.workspaceFiles()[idx];
        if (file.is_markdown_preview or file.is_waveform_preview or file.is_pdf_preview or file.is_git_diff_preview) {
            buf.resetWithSlice(file.initial_source);
            self.saved_versions[idx] = buf.edit_version;
            self.loaded_from_disk[idx] = false;
            self.disk_mtime_hashes[idx] = 0;
            return;
        }
        const was_loaded = self.loaded_from_disk[idx];
        var prev_cursor_line: usize = 0;
        var prev_cursor_col: usize = 0;
        var prev_anchor_line: usize = 0;
        var prev_anchor_col: usize = 0;
        if (was_loaded) {
            const clc = buf.offsetToLineCol(buf.cursor);
            prev_cursor_line = clc.line;
            prev_cursor_col = clc.col;
            const alc = buf.offsetToLineCol(buf.selection_anchor);
            prev_anchor_line = alc.line;
            prev_anchor_col = alc.col;
        }
        const prev_len = buf.len;
        const prev_content_hash: u64 = if (was_loaded) std.hash.Wyhash.hash(0, buf.slice()) else 0;

        if (regularFileSizeOnDisk(file.path.ptr)) |disk_size| {
            // Guard against macOS FileProvider / iCloud Drive `SF_DATALESS` files so synchronous
            // `fopen`/`fread` never stalls the 120 FPS UI thread waiting on network download.
            if (isDatalessFileOnDisk(file.path.ptr)) {
                if (was_loaded) {
                    self.disk_mtime_hashes[idx] = statMtimeHash(file.path.ptr);
                    return;
                }
                triggerAsyncICloudDownload(file.path.ptr);
                buf.resetWithSlice(file.initial_source);
                self.saved_versions[idx] = buf.edit_version;
                self.loaded_from_disk[idx] = false;
                self.disk_mtime_hashes[idx] = statMtimeHash(file.path.ptr);
                self.setStatusNotice("Downloading file from iCloud Drive in background...");
                return;
            }
            // For `.pdf` and raster image files larger than 32 KB on disk, the native viewers stream directly
            // from `file.path`, avoiding reading megabytes of binary bytes into a text `CodeEditorBuffer`.
            if ((isPdfCandidatePath(file.path) or isImageCandidatePath(file.path)) and disk_size > 32 * 1024) {
                buf.resetWithSlice("");
                self.saved_versions[idx] = buf.edit_version;
                self.loaded_from_disk[idx] = true;
                self.disk_mtime_hashes[idx] = statMtimeHash(file.path.ptr);
                return;
            }
            if (std.c.fopen(file.path.ptr, "rb")) |fp| {
                defer _ = std.c.fclose(fp);
                const file_size: usize = @min(disk_size, MaxDiskFileBytes);
                _ = buf.ensureCapacity(file_size);
                const read_cap = @min(file_size, buf.capacity());
                const dst = buf.dataPtr();
                var total_read: usize = 0;
                while (total_read < read_cap) {
                    const n = std.c.fread(dst + total_read, 1, read_cap - total_read, fp);
                    if (n == 0) break;
                    total_read += n;
                }
                const new_mtime_hash = statMtimeHash(file.path.ptr);
                if (was_loaded and total_read == prev_len and std.hash.Wyhash.hash(0, dst[0..total_read]) == prev_content_hash) {
                    buf.len = total_read;
                    self.disk_mtime_hashes[idx] = new_mtime_hash;
                    return;
                }
                buf.len = total_read;
                buf.preferred_col = null;
                buf.scroll_to_cursor_pending = false;
                buf.scroll_align_top = false;
                buf.dragging_text = false;
                buf.undo_len = 0;
                buf.undo_pos = 0;
                buf.undo_checkpoint_pending = false;
                buf.typing_coalesce_active = false;
                buf.edit_version +%= 1;
                if (buf.edit_version == 0) buf.edit_version = 1;
                buf.rebuildLineIndex();
                if (was_loaded) {
                    const c_range = buf.lineRangeByIndex(prev_cursor_line);
                    const c_raw = @min(c_range.start + prev_cursor_col, c_range.end);
                    buf.cursor = ui.code_editor_mod.snapToGraphemeBoundary(buf.slice(), c_raw);
                    const a_range = buf.lineRangeByIndex(prev_anchor_line);
                    const a_raw = @min(a_range.start + prev_anchor_col, a_range.end);
                    buf.selection_anchor = ui.code_editor_mod.snapToGraphemeBoundary(buf.slice(), a_raw);
                } else {
                    buf.cursor = 0;
                    buf.selection_anchor = 0;
                    buf.scroll_state = .{};
                    buf.split_scroll_states = @splat(.{});
                }
                self.saved_versions[idx] = buf.edit_version;
                self.loaded_from_disk[idx] = true;
                self.disk_mtime_hashes[idx] = new_mtime_hash;
                return;
            } else {
                // Direct open failed; check if this was an evicted iCloud placeholder
                var ph_buf: [512:0]u8 = @splat(0);
                if (getICloudPlaceholderPath(file.path, &ph_buf)) |ph_z| {
                    if (platform.fs_util.pathExistsOnDisk(ph_z)) {
                        self.setStatusNotice("File is stored in iCloud Drive. Download in Finder to edit.");
                    }
                }
                if (was_loaded) return;
            }
        } else if (was_loaded) {
            return;
        }
        buf.resetWithSlice(file.initial_source);
        self.saved_versions[idx] = buf.edit_version;
        self.loaded_from_disk[idx] = false;
        self.disk_mtime_hashes[idx] = 0;
    }

    /// Reloads workspace file `idx` from disk if it is unmodified in the editor and its on-disk
    /// metadata (`statMtimeHash`) or contents have changed since it was loaded or saved.
    /// Returns `true` if the buffer was reloaded with new content.
    pub fn reloadFileFromDiskIfChanged(self: *EditorState, idx: usize) bool {
        if (idx >= self.file_count) return false;
        const file = self.workspaceFiles()[idx];
        if (file.isSpecial() or self.isFileDirty(idx)) return false;

        if (isDatalessFileOnDisk(file.path.ptr)) {
            if (self.loaded_from_disk[idx]) {
                self.disk_mtime_hashes[idx] = statMtimeHash(file.path.ptr);
            }
            return false;
        }

        if (!self.loaded_from_disk[idx]) {
            if (self.bufferVisibleInPane(idx) == null) return false;
            if (!fileExistsOnDisk(file.path)) return false;
            self.loadFileFromDiskOrFallback(idx);
            return self.loaded_from_disk[idx];
        }

        const cur_hash = statMtimeHash(file.path.ptr);
        if (cur_hash == 0 or cur_hash == self.disk_mtime_hashes[idx]) return false;

        const disk_size = regularFileSizeOnDisk(file.path.ptr) orelse return false;
        if ((isPdfCandidatePath(file.path) or isImageCandidatePath(file.path)) and disk_size > 32 * 1024) {
            const buf = self.ensureBufferSlotInit(idx);
            buf.edit_version +%= 1;
            if (buf.edit_version == 0) buf.edit_version = 1;
            self.saved_versions[idx] = buf.edit_version;
            self.disk_mtime_hashes[idx] = cur_hash;
            return true;
        }

        const buf = self.ensureBufferSlotInit(idx);
        const prev_ver = buf.edit_version;
        self.loadFileFromDiskOrFallback(idx);
        return buf.edit_version != prev_ver;
    }

    /// Checks all open unmodified workspace files against disk and reloads any whose
    /// on-disk contents have changed. Returns the number of buffers reloaded.
    pub fn reloadModifiedOpenFiles(self: *EditorState) usize {
        var reloaded: usize = 0;
        for (0..self.file_count) |idx| {
            if (self.files[idx].isSpecial() or self.isFileDirty(idx)) continue;
            if (self.isBufferOpen(idx) or self.bufferVisibleInPane(idx) != null or self.isFileReferencedByOpenPreview(idx)) {
                if (self.reloadFileFromDiskIfChanged(idx)) {
                    reloaded += 1;
                }
            }
        }
        if (reloaded > 0) {
            self.cached_search_sig = 0;
            if (self.activeFileIndex()) |active_idx| {
                self.syncCursorTelemetry(active_idx);
            }
            if (self.git_diff_commit.len == 0) {
                for (self.workspaceFiles(), 0..) |wf, i| {
                    if (wf.is_git_diff_preview and (self.isBufferOpen(i) or self.bufferVisibleInPane(i) != null)) {
                        self.refreshActiveGitDiffContent();
                        break;
                    }
                }
            }
            self.ui_ctx.invalidateWindow();
        }
        return reloaded;
    }

    pub fn saveFileToDisk(self: *EditorState, idx: usize) bool {
        const file = self.workspaceFiles()[idx];
        if (file.is_markdown_preview) {
            if (self.isScratchMarkdownPreview(idx)) {
                self.openSaveAsPrompt();
                return false;
            }
            if (self.findMarkdownPreviewSourceIndexForBuffer(idx)) |src_idx| {
                return self.saveFileToDisk(src_idx);
            }
            return false;
        }
        if (file.is_waveform_preview) {
            return self.saveFileToDisk(self.waveformPreviewSourceIndex());
        }
        if (file.is_pdf_preview or isPdfCandidatePath(file.path)) {
            self.setStatusNotice("PDF documents are read-only in PDF Viewer");
            return false;
        }
        if (isImageCandidatePath(file.path)) {
            self.setStatusNotice("Image files are read-only in Image Viewer");
            return false;
        }
        if (file.is_git_diff_preview) {
            return self.saveFileToDisk(self.gitDiffPreviewSourceIndex());
        }
        const buf = self.ensureBufferSlotInit(idx);
        const slice = buf.slice();
        if (!writeSliceToDiskAtomic(file.path.ptr, slice)) {
            self.setStatusNotice("Save failed: could not write file");
            return false;
        }
        self.saved_versions[idx] = buf.edit_version;
        self.loaded_from_disk[idx] = true;
        self.disk_mtime_hashes[idx] = statMtimeHash(file.path.ptr);
        self.refreshGitStatus();
        self.last_watch_sig = self.computeWorkspaceWatchSignature();
        if (self.git_diff_commit.len == 0 and self.gitDiffPreviewSourceIndex() == idx) {
            self.refreshActiveGitDiffContent();
        }
        self.plugins.notifyBufferSave(self, idx);
        var msg_buf: [96]u8 = undefined;
        const msg = std.fmt.bufPrint(&msg_buf, "Saved {s} ({d} B)", .{ file.path, slice.len }) catch "Saved file";
        self.setStatusNotice(msg);
        return true;
    }

    pub fn saveAllDirtyFiles(self: *EditorState) usize {
        var saved: usize = 0;
        for (0..self.fileCount()) |idx| {
            if (self.isFileDirty(idx)) {
                if (self.saveFileToDisk(idx)) saved += 1;
            }
        }
        return saved;
    }

    pub fn isFileDirty(self: *const EditorState, idx: usize) bool {
        if (!self.buffer_initialized[idx]) return false;
        if (idx < self.file_count and (self.files[idx].is_pdf_preview or isPdfCandidatePath(self.files[idx].path) or isImageCandidatePath(self.files[idx].path))) return false;
        if (!self.loaded_from_disk[idx] and self.buffers[idx].len == 0) return false;
        return self.buffers[idx].edit_version != self.saved_versions[idx];
    }

    pub fn isScratchDirty(self: *const EditorState) bool {
        return self.scratch_buf.edit_version != self.scratch_saved_version and self.scratch_buf.len > 0;
    }

    pub fn saveAsPath(self: *const EditorState) []const u8 {
        return self.save_as_path.slice();
    }

    pub fn newFolderPath(self: *const EditorState) []const u8 {
        return self.new_folder_path.slice();
    }

    pub fn openSaveAsPrompt(self: *EditorState) void {
        self.show_save_as_prompt = true;
        self.save_as_create_empty = false;
        self.show_new_folder_prompt = false;
        self.doc.show_command_palette = false;
        self.show_stage_all_prompt = false;
        if (self.save_as_path.isEmpty()) {
            if (self.activeFileIndex()) |f_idx| {
                const wf = self.workspaceFiles()[f_idx];
                if (!wf.isSpecial()) {
                    self.save_as_path.set(wf.path);
                }
            }
        }
        self.ui_ctx.focusAndSelectAll(ui.scopedIdPath(&.{ "vscode_workbench", "editor_pane" }, "##save_as_input"));
        self.ui_ctx.invalidateWindow();
    }

    pub fn openScratchInActivePane(self: *EditorState) void {
        self.ensureValidSplitTree();
        const p_idx = self.activePaneIndex();
        self.doc.panes[p_idx].clear();
        const lc = self.scratch_buf.cursorLineCol();
        self.doc.cursor_line = @intCast(lc.line);
        self.doc.cursor_col = @intCast(lc.col);
        self.ui_ctx.focused_id = self.activeEditorWidgetId();
        self.ui_ctx.invalidateWindow();
    }

    pub fn saveActiveOrScratchToNewFile(self: *EditorState) bool {
        var rel_path = std.mem.trim(u8, self.saveAsPath(), " \t\r\n\"'");
        while (std.mem.startsWith(u8, rel_path, "./")) {
            rel_path = rel_path[2..];
        }
        if (rel_path.len == 0 or rel_path.len >= 254 or rel_path[0] == '/' or std.mem.indexOfPos(u8, rel_path, 0, "..") != null) {
            self.setStatusNotice("Save failed: enter a valid relative file path");
            return false;
        }

        // Create parent directories if `rel_path` contains `/`
        if (std.mem.lastIndexOfScalar(u8, rel_path, '/')) |slash_idx| {
            const dir_part = rel_path[0..slash_idx];
            if (dir_part.len > 0 and dir_part.len < 254) {
                _ = mkdirRecursive(dir_part);
                self.expandFolderAndAncestors(dir_part);
            }
        }

        var path_z_buf: [256:0]u8 = @splat(0);
        @memcpy(path_z_buf[0..rel_path.len], rel_path);
        path_z_buf[rel_path.len] = 0;

        const create_empty = self.save_as_create_empty;
        const src_buf = if (self.activeFileIndex()) |f_idx| &self.buffers[f_idx] else &self.scratch_buf;
        const slice: []const u8 = if (create_empty) "" else src_buf.slice();
        const saved_cursor: usize = if (create_empty) 0 else src_buf.cursor;

        if (!writeSliceToDiskAtomic(&path_z_buf, slice)) {
            self.setStatusNotice("Save failed: could not open path for writing");
            return false;
        }

        if (self.file_count == 0) {
            self.refreshWorkspaceFiles(false);
        self.agy.syncWorkspaceRoot(self.workspaceRoot());
        }
        var target_idx_opt: ?usize = null;
        for (self.files[0..self.file_count], 0..) |wf, idx| {
            if (!wf.isSpecial() and std.mem.eql(u8, wf.path, rel_path)) {
                target_idx_opt = idx;
                break;
            }
        }

        if (target_idx_opt == null) {
            if (self.ensureFreeDynamicFileSlot()) |new_idx| {
                const lang = detectLanguageForPath(rel_path);
                self.storeDynamicFileSlot(new_idx, rel_path, lang, false, false, "");
                self.file_count += 1;
                target_idx_opt = new_idx;
            } else {
                self.refreshWorkspaceFiles(false);
        self.agy.syncWorkspaceRoot(self.workspaceRoot());
                for (self.files[0..self.file_count], 0..) |wf, idx| {
                    if (!wf.isSpecial() and std.mem.eql(u8, wf.path, rel_path)) {
                        target_idx_opt = idx;
                        break;
                    }
                }
            }
        }

        const was_scratch = (!create_empty and self.activeFileIndex() == null);
        if (target_idx_opt) |target_idx| {
            const target_buf = self.ensureBufferSlotInit(target_idx);
            target_buf.resetWithSlice(slice);
            target_buf.cursor = @min(saved_cursor, target_buf.len);
            target_buf.selection_anchor = target_buf.cursor;
            self.saved_versions[target_idx] = target_buf.edit_version;
            self.loaded_from_disk[target_idx] = true;
            self.disk_mtime_hashes[target_idx] = statMtimeHash(self.files[target_idx].path.ptr);
            if (was_scratch) {
                self.scratch_buf.resetWithSlice("");
                self.scratch_saved_version = self.scratch_buf.edit_version;
            }
            self.openFile(target_idx);
        }

        self.show_save_as_prompt = false;
        self.save_as_create_empty = false;
        self.save_as_path.clear();
        self.scanWorkspaceDirectories(false);
        _ = self.reloadModifiedOpenFiles();
        self.refreshGitStatus();
        self.last_watch_sig = self.computeWorkspaceWatchSignature();

        var msg_buf: [96]u8 = undefined;
        const msg = if (create_empty)
            std.fmt.bufPrint(&msg_buf, "Created {s}", .{rel_path}) catch "Created new file"
        else
            std.fmt.bufPrint(&msg_buf, "Saved {s} ({d} B)", .{ rel_path, slice.len }) catch "Saved new file";
        self.setStatusNotice(msg);
        self.ui_ctx.focused_id = self.activeEditorWidgetId();
        self.ui_ctx.invalidateWindow();
        return true;
    }

    /// Opens a file referenced by a `file://` URL, absolute path, or workspace-relative path,
    /// optionally jumping to a `#L<line>` or `:<line>` anchor (e.g. `file:///.../test.md#L3-L19`).
    pub fn openLinkOrFileUrl(self: *EditorState, raw_url: []const u8) bool {
        var path_part = std.mem.trim(u8, raw_url, " \t\r\n\"'`");
        if (path_part.len == 0) return false;

        if (std.mem.startsWith(u8, path_part, "file://")) {
            path_part = path_part["file://".len..];
            if (path_part.len >= 3 and path_part[0] == '/' and std.ascii.isAlphabetic(path_part[1]) and path_part[2] == ':') {
                path_part = path_part[1..];
            }
        } else if (std.mem.startsWith(u8, path_part, "http://") or std.mem.startsWith(u8, path_part, "https://")) {
            return false;
        }

        var target_line: ?usize = null;
        var heading_frag: []const u8 = "";

        // 1. Parse `#L10` / `#L3-L19` / `#10` or `#heading-slug` fragment if present
        if (std.mem.indexOfScalar(u8, path_part, '#')) |hash_idx| {
            const raw_frag = std.mem.trim(u8, path_part[hash_idx + 1 ..], " \t\r\n");
            var frag = raw_frag;
            path_part = path_part[0..hash_idx];
            if (frag.len > 0 and (frag[0] == 'L' or frag[0] == 'l')) {
                frag = frag[1..];
            }
            var d_end: usize = 0;
            while (d_end < frag.len and std.ascii.isDigit(frag[d_end])) : (d_end += 1) {}
            if (d_end > 0 and (d_end == frag.len or frag[d_end] == '-' or frag[d_end] == 'L' or frag[d_end] == 'l')) {
                target_line = std.fmt.parseInt(usize, frag[0..d_end], 10) catch null;
            }
            if (target_line == null and raw_frag.len > 0) {
                heading_frag = raw_frag;
            }
        }

        // 2. Parse `:10` or `:10:4` suffix if present (skipping Windows drive letter `C:`)
        if (target_line == null) {
            const colon_search_start: usize = if (path_part.len >= 2 and std.ascii.isAlphabetic(path_part[0]) and path_part[1] == ':') 2 else 0;
            if (std.mem.indexOfScalarPos(u8, path_part, colon_search_start, ':')) |colon_idx| {
                const after = path_part[colon_idx + 1 ..];
                var d_end: usize = 0;
                while (d_end < after.len and std.ascii.isDigit(after[d_end])) : (d_end += 1) {}
                if (d_end > 0) {
                    target_line = std.fmt.parseInt(usize, after[0..d_end], 10) catch null;
                    path_part = path_part[0..colon_idx];
                }
            }
        }

        var slash_norm_buf: [512]u8 = undefined;
        if (std.mem.indexOfScalar(u8, path_part, '\\') != null and path_part.len <= slash_norm_buf.len) {
            for (path_part, 0..) |c, i| {
                slash_norm_buf[i] = if (c == '\\') '/' else c;
            }
            path_part = slash_norm_buf[0..path_part.len];
        }

        // 3. Expand leading `~/` and strip leading `./` or workspace cwd prefix if absolute path
        var home_exp_buf: [512]u8 = undefined;
        if (std.mem.startsWith(u8, path_part, "~/") or std.mem.eql(u8, path_part, "~")) {
            if (getenv("HOME")) |home_z| {
                const home = std.mem.sliceTo(home_z, 0);
                const rest = if (path_part.len > 1) path_part[1..] else "";
                if (std.fmt.bufPrint(&home_exp_buf, "{s}{s}", .{ home, rest })) |s| {
                    path_part = s;
                } else |_| {}
            }
        }
        while (std.mem.startsWith(u8, path_part, "./")) {
            path_part = path_part[2..];
        }

        // If `path_part` points directly to a directory on disk, switch the active workspace to it
        if (path_part.len > 0 and path_part.len < 250 and !std.mem.eql(u8, path_part, ".")) {
            var dir_check_z: [256:0]u8 = @splat(0);
            @memcpy(dir_check_z[0..path_part.len], path_part);
            dir_check_z[path_part.len] = 0;
            if (isDirectoryOnDisk(&dir_check_z)) {
                return self.openWorkspaceDirectory(path_part);
            }
        }

        var cwd_buf: [512]u8 = undefined;
        var rel_candidate = path_part;
        const is_abs = std.mem.startsWith(u8, path_part, "/") or
            (path_part.len >= 3 and std.ascii.isAlphabetic(path_part[0]) and path_part[1] == ':' and path_part[2] == '/');
        if (is_abs) {
            if (getcwd(&cwd_buf, cwd_buf.len) != null) {
                var cwd_norm_buf: [512]u8 = undefined;
                const cwd_raw = std.mem.sliceTo(cwd_buf[0..], 0);
                for (cwd_raw, 0..) |c, i| {
                    cwd_norm_buf[i] = if (c == '\\') '/' else c;
                }
                const cwd_slice = cwd_norm_buf[0..cwd_raw.len];
                if (std.mem.startsWith(u8, path_part, cwd_slice)) {
                    var rem = path_part[cwd_slice.len..];
                    while (std.mem.startsWith(u8, rem, "/")) {
                        rem = rem[1..];
                    }
                    if (rem.len > 0) {
                        rel_candidate = rem;
                    }
                }
            }
        }

        if (self.file_count == 0) {
            self.refreshWorkspaceFiles(false);
        self.agy.syncWorkspaceRoot(self.workspaceRoot());
        }

        const wfs = self.workspaceFiles();
        var match_idx: ?usize = null;
        const active_opt = self.activeFileIndex();
        const active_src_idx: ?usize = if (active_opt) |af|
            (if (wfs[af].is_markdown_preview) self.findMarkdownPreviewSourceIndexForBuffer(af) else af)
        else
            null;

        // Pure in-document fragment link (e.g. `#Variables` or `#L20`)
        if (path_part.len == 0) {
            match_idx = active_src_idx;
        }

        // Exact relative path match first
        if (match_idx == null) {
            for (wfs, 0..) |wf, idx| {
                if (wf.isSpecial()) continue;
                if (std.mem.eql(u8, wf.path, rel_candidate) or std.mem.eql(u8, wf.path, path_part)) {
                    match_idx = idx;
                    break;
                }
            }
        }

        // Resolve relative to the current active file's directory (e.g. `langref/01-introduction.md` inside `docs/README.md`)
        var joined_rel_buf: [256]u8 = undefined;
        var joined_rel: []const u8 = "";
        if (match_idx == null and rel_candidate.len > 0) {
            if (active_src_idx) |src_i| {
                const cur_folder = wfs[src_i].folder;
                if (!std.mem.eql(u8, cur_folder, ".") and cur_folder.len > 0) {
                    joined_rel = std.fmt.bufPrint(&joined_rel_buf, "{s}/{s}", .{ cur_folder, rel_candidate }) catch "";
                    if (joined_rel.len > 0) {
                        for (wfs, 0..) |wf, idx| {
                            if (wf.isSpecial()) continue;
                            if (std.mem.eql(u8, wf.path, joined_rel)) {
                                match_idx = idx;
                                break;
                            }
                        }
                    }
                }
            }
        }

        // Fallback: suffix path match or exact filename match
        if (match_idx == null) {
            for (wfs, 0..) |wf, idx| {
                if (wf.isSpecial()) continue;
                if (std.mem.endsWith(u8, path_part, wf.path) and
                    path_part.len > wf.path.len and
                    path_part[path_part.len - wf.path.len - 1] == '/')
                {
                    match_idx = idx;
                    break;
                }
            }
        }
        if (match_idx == null) {
            const base = if (std.mem.lastIndexOfScalar(u8, rel_candidate, '/')) |s| rel_candidate[s + 1 ..] else rel_candidate;
            for (wfs, 0..) |wf, idx| {
                if (wf.isSpecial()) continue;
                if (std.mem.eql(u8, wf.name, base)) {
                    match_idx = idx;
                    break;
                }
            }
        }

        // If still not in workspace list, check if `joined_rel` or `rel_candidate` exists on disk and register it dynamically
        if (match_idx == null) {
            const disk_candidates = [_][]const u8{ joined_rel, rel_candidate };
            for (disk_candidates) |cand| {
                if (cand.len == 0 or cand.len >= 254) continue;
                if (fileExistsOnDisk(cand)) {
                    if (self.ensureFreeDynamicFileSlot()) |new_idx| {
                        const lang = detectLanguageForPath(cand);
                        self.storeDynamicFileSlot(new_idx, cand, lang, false, false, "");
                        self.file_count += 1;
                        self.loadFileFromDiskOrFallback(new_idx);
                        match_idx = new_idx;
                    }
                    break;
                }
            }
        }

        const idx = match_idx orelse return false;
        const keep_md_preview = (path_part.len == 0 and active_opt != null and wfs[active_opt.?].is_markdown_preview and active_src_idx == idx);
        if (!keep_md_preview) {
            if (active_opt != null and wfs[active_opt.?].is_markdown_preview and !wfs[active_opt.?].is_bound_markdown_preview and self.workspaceFiles()[idx].language == .markdown) {
                self.doc.md_preview_source_idx = @intCast(idx);
                self.ensureBufferInOpenList(idx);
            } else {
                self.openFile(idx);
            }
        }
        if (heading_frag.len > 0) {
            self.pending_md_heading.set(heading_frag);
            if (target_line == null) {
                target_line = ui.markdown_mod.findHeadingLine(self.buffers[idx].slice(), heading_frag);
            }
        }
        if (target_line) |ln| {
            if (ln > 0) {
                self.buffers[idx].jumpToLine(ln);
                self.doc.cursor_line = @intCast(ln);
                self.doc.cursor_col = 1;
            }
        }
        self.ui_ctx.focused_id = self.activeEditorWidgetId();
        self.ui_ctx.invalidateWindow();
        return true;
    }

    pub fn isFileModifiedInGit(self: *const EditorState, idx: usize) bool {
        if (idx >= self.fileCount()) return false;
        return self.isFileDirty(idx) or self.git_file_statuses[idx].unstaged or self.git_file_statuses[idx].untracked;
    }

    pub fn isFileStaged(self: *const EditorState, idx: usize) bool {
        if (idx >= self.fileCount()) return false;
        return self.git_file_statuses[idx].staged;
    }

    pub fn isFileUnstagedChange(self: *const EditorState, idx: usize) bool {
        return self.isFileModifiedInGit(idx);
    }

    pub fn stagedFileCount(self: *const EditorState) usize {
        var count: usize = 0;
        for (0..self.fileCount()) |idx| {
            if (self.isFileStaged(idx)) count += 1;
        }
        return count;
    }

    pub fn unstagedChangeCount(self: *const EditorState) usize {
        var count: usize = 0;
        for (0..self.fileCount()) |idx| {
            if (self.isFileUnstagedChange(idx)) count += 1;
        }
        return count;
    }

    pub fn dirtyFileCount(self: *const EditorState) usize {
        var count: usize = 0;
        for (0..self.fileCount()) |idx| {
            if (self.isFileModifiedInGit(idx) or self.isFileStaged(idx)) count += 1;
        }
        return count;
    }

    pub fn stageFile(self: *EditorState, idx: usize) void {
        if (idx >= self.fileCount()) return;
        if (self.isFileDirty(idx)) {
            _ = self.saveFileToDisk(idx);
        }
        git_client.stagePath(self.workspaceFiles()[idx].path);
        self.refreshGitStatusSync();
        self.setStatusNotice("Staged file for commit");
    }

    pub fn unstageFile(self: *EditorState, idx: usize) void {
        if (idx >= self.fileCount()) return;
        git_client.unstagePath(self.workspaceFiles()[idx].path);
        self.refreshGitStatusSync();
        self.setStatusNotice("Unstaged file");
    }

    pub fn stageAllChanges(self: *EditorState) void {
        for (0..self.fileCount()) |idx| {
            if (self.isFileDirty(idx)) {
                _ = self.saveFileToDisk(idx);
            }
        }
        git_client.stageAll();
        self.refreshGitStatusSync();
        self.setStatusNotice("Staged all modified files");
    }

    pub fn unstageAllChanges(self: *EditorState) void {
        git_client.unstageAll();
        self.refreshGitStatusSync();
        self.setStatusNotice("Unstaged all files");
    }

    pub fn discardFileChanges(self: *EditorState, idx: usize) void {
        if (idx >= self.fileCount()) return;
        git_client.discardPath(self.workspaceFiles()[idx].path);
        self.loadFileFromDiskOrFallback(idx);
        self.refreshGitStatusSync();
        self.setStatusNotice("Discarded changes");
    }

    pub fn commitMessage(self: *const EditorState) []const u8 {
        return self.commit_msg.slice();
    }

    pub fn requestCommit(self: *EditorState) void {
        if (self.stagedFileCount() > 0) {
            _ = self.commitStagedChanges();
            self.ui_ctx.focused_id = self.activeEditorWidgetId();
        } else if (self.unstagedChangeCount() > 0) {
            self.show_stage_all_prompt = true;
            self.ui_ctx.invalidateWindow();
        } else {
            self.setStatusNotice("No changes to commit");
        }
    }

    pub fn commitStagedChanges(self: *EditorState) bool {
        // Save any open editor buffers that are staged before running `git commit`
        for (0..self.fileCount()) |idx| {
            if (self.isFileStaged(idx) and self.isFileDirty(idx)) {
                _ = self.saveFileToDisk(idx);
                git_client.stagePath(self.workspaceFiles()[idx].path);
            }
        }

        if (self.stagedFileCount() == 0) {
            self.stageAllChanges();
        }
        if (self.stagedFileCount() == 0) {
            self.setStatusNotice("No changes to commit");
            return false;
        }

        const msg_raw = std.mem.trim(u8, self.commitMessage(), " \t\r\n");
        const full_msg = if (msg_raw.len > 0) msg_raw else "Update workspace files";

        git_client.commitWithMessage(full_msg) catch |err| {
            self.refreshGitStatusSync();
            self.setStatusNotice(switch (err) {
                error.WriteMessageFailed => "Failed to write commit message",
                error.GitCommitFailed => "Git commit failed",
            });
            return false;
        };

        self.commit_msg.clear();
        self.refreshGitStatusSync();
        self.refreshActiveGitDiffContent();
        self.doc.commit_expanded[0] = true;
        var notice_buf: [96]u8 = undefined;
        const branch_name = self.git_branch.slice();
        const notice = if (branch_name.len > 0)
            std.fmt.bufPrint(&notice_buf, "Committed staged changes to {s}", .{branch_name}) catch "Committed staged changes"
        else
            "Committed staged changes";
        self.setStatusNotice(notice);
        return true;
    }

    pub fn refreshGitStatus(self: *EditorState) void {
        self.git_poller.requestRefresh();
    }

    pub fn refreshGitStatusSync(self: *EditorState) void {
        self.git_poller.deinit();
        _ = git_client.queryBranch(&self.git_branch);
        _ = git_client.queryStatus(self.workspaceFiles(), self.git_file_statuses[0..self.file_count]);
        if (git_client.queryRecentCommits(self.workspaceFiles(), &self.git_commits)) |c_count| {
            self.git_commit_count = c_count;
        }
        self.git_poller.requestRefresh();
    }

    pub fn findQuery(self: *const EditorState) []const u8 {
        return self.find_query.slice();
    }

    pub fn workspaceSearchQuery(self: *const EditorState) []const u8 {
        return workspace_search.workspaceSearchQuery(self);
    }

    pub fn paletteQuery(self: *const EditorState) []const u8 {
        return self.palette_query.slice();
    }

    pub fn setPaletteQuery(self: *EditorState, prefix: []const u8) void {
        self.palette_query.set(prefix);
        self.palette_selected_idx = 0;
    }

    pub fn openPaletteWithPrefix(self: *EditorState, prefix: []const u8) void {
        self.doc.show_command_palette = true;
        self.setPaletteQuery(prefix);
    }

    /// Returns the single-line selected text slice from the active code editor buffer (if non-empty and free of newlines).
    pub fn activeSingleLineSelection(self: *const EditorState) ?[]const u8 {
        const active_buf = if (self.activeFileIndex()) |f_idx| blk: {
            const wf = self.workspaceFiles()[f_idx];
            if (wf.isSpecial()) return null;
            break :blk &self.buffers[f_idx];
        } else &self.scratch_buf;

        if (!active_buf.hasSelection()) return null;
        const sel = active_buf.selectionRange();
        const text = active_buf.slice();
        if (sel.end <= sel.start or sel.end > text.len) return null;
        const sel_slice = text[sel.start..sel.end];
        if (std.mem.indexOfScalar(u8, sel_slice, '\n') != null or
            std.mem.indexOfScalar(u8, sel_slice, '\r') != null)
        {
            return null;
        }
        return sel_slice;
    }

    /// Opens the Find Bar (`Cmd+F`), pre-populating `find_query` from the active buffer's
    /// single-line selection (if any), and focuses `##find_bar_input` with all text selected.
    pub fn openFindBar(self: *EditorState) void {
        self.doc.show_command_palette = false;
        self.doc.show_find_bar = true;

        if (self.activeSingleLineSelection()) |sel_slice| {
            if (sel_slice.len <= self.find_query.buf.len) {
                self.find_query.set(sel_slice);
            }
        }

        const find_wid = if (self.ui_ctx.id_stack_len > 0)
            self.ui_ctx.resolveIdAndLabel("##find_bar_input").wid
        else
            ui.scopedIdPath(&.{ "vscode_workbench", "editor_pane" }, "##find_bar_input");
        self.ui_ctx.focusAndSelectAll(find_wid);
        self.ui_ctx.invalidateWindow();
    }

    /// Opens the Workspace Search sidebar (`Shift+Cmd+F`), pre-populating `workspace_search` from the
    /// active buffer's single-line selection (if any), and focuses `##workspace_search_input` with all text selected.
    pub fn openWorkspaceSearch(self: *EditorState) void {
        workspace_search.openWorkspaceSearch(self);
    }

    // ========================================================================
    // Antigravity (`agy`) Contextual Prompts (§6) & TUI Handoff (§5.4)
    // ========================================================================

    /// Synchronizes shared `agy` process hub connection credentials (`ls_port`, `alt_port`, `csrf_buf`),
    /// synced workspace root, model catalog, and conversation history list across `self.agy` and all
    /// `*agent-N*` buffer sessions (`self.agent_sessions`) so every agent buffer communicates with the
    /// same `agy` process without redundant process scans or duplicate catalog RPCs.
    pub fn syncAgyHubState(self: *EditorState) void {
        var hub_src: *const agy_client.AgySession = &self.agy;
        if (hub_src.ls_port == 0 or hub_src.csrf_len == 0) {
            for (0..self.agent_slot_used.len) |i| {
                if (self.agent_slot_used[i] and self.agent_sessions[i].ls_port != 0 and self.agent_sessions[i].csrf_len > 0) {
                    hub_src = &self.agent_sessions[i];
                    break;
                }
            }
        }
        var model_src: *const agy_client.AgySession = &self.agy;
        for (0..self.agent_slot_used.len) |i| {
            if (self.agent_slot_used[i] and self.agent_sessions[i].model_count > model_src.model_count) {
                model_src = &self.agent_sessions[i];
            }
        }
        var conv_src: *const agy_client.AgySession = &self.agy;
        for (0..self.agent_slot_used.len) |i| {
            if (self.agent_slot_used[i] and self.agent_sessions[i].conversation_count > conv_src.conversation_count) {
                conv_src = &self.agent_sessions[i];
            }
        }

        if (hub_src != &self.agy) self.agy.shareHubStateFrom(hub_src);
        if (model_src != &self.agy) self.agy.shareHubStateFrom(model_src);
        if (conv_src != &self.agy) self.agy.shareHubStateFrom(conv_src);
        for (0..self.agent_slot_used.len) |i| {
            if (self.agent_slot_used[i]) {
                const sess = &self.agent_sessions[i];
                if (sess.models_fetched or sess.active_rpc == .get_models) {
                    self.agy.models_attempted = true;
                }
                if (sess.conversations_fetched or sess.active_rpc == .list_conversations or sess.active_rpc == .search_conversations) {
                    self.agy.conversations_attempted = true;
                }
            }
        }

        for (0..self.agent_sessions.len) |i| {
            self.agent_sessions[i].shareHubStateFrom(&self.agy);
        }
    }

    pub fn anyAgyModelsAttempted(self: *const EditorState) bool {
        if (self.agy.models_attempted) return true;
        for (0..self.agent_slot_used.len) |i| {
            if (self.agent_slot_used[i] and self.agent_sessions[i].models_attempted) return true;
        }
        return false;
    }

    pub fn anyAgyConversationsAttempted(self: *const EditorState) bool {
        if (self.agy.conversations_attempted) return true;
        for (0..self.agent_slot_used.len) |i| {
            if (self.agent_slot_used[i] and self.agent_sessions[i].conversations_attempted) return true;
        }
        return false;
    }

    pub fn refreshAllAgyConversations(self: *EditorState) void {
        self.agy.conversations_fetched = false;
        self.agy.conversations_attempted = false;
        self.agy.conversation_count = 0;
        for (0..self.agent_sessions.len) |i| {
            self.agent_sessions[i].conversations_fetched = false;
            self.agent_sessions[i].conversations_attempted = false;
            self.agent_sessions[i].conversation_count = 0;
        }
        if (!self.agy.isBusy()) {
            self.agy.refreshConversations();
            self.syncAgyHubState();
            return;
        }
        for (0..self.agent_slot_used.len) |i| {
            if (self.agent_slot_used[i] and !self.agent_sessions[i].isBusy()) {
                self.agent_sessions[i].refreshConversations();
                self.syncAgyHubState();
                return;
            }
        }
    }

    /// Returns the `AgySession` for the currently active `*agent-N*` buffer if the focused pane
    /// is displaying an agent buffer; otherwise returns `&self.agy` (the right-side Agent Panel).
    pub fn activeAgySession(self: *EditorState) *agy_client.AgySession {
        if (self.activeFileIndex()) |f_idx| {
            const wf = self.workspaceFiles()[f_idx];
            if (wf.is_agent) {
                const slot = self.ensureAgentSlot(wf.agent_slot);
                return &self.agent_sessions[slot];
            }
        }
        return &self.agy;
    }

    pub fn activeAgyPrompt(self: *EditorState) *platform.InlineString(8192) {
        if (self.activeFileIndex()) |f_idx| {
            const wf = self.workspaceFiles()[f_idx];
            if (wf.is_agent) {
                const slot = self.ensureAgentSlot(wf.agent_slot);
                return &self.agent_prompts[slot];
            }
        }
        return &self.agy_prompt;
    }

    pub fn contextMenuAgySession(self: *EditorState) *agy_client.AgySession {
        if (self.context_menu_agent_slot) |slot| {
            if (slot < self.agent_sessions.len) return &self.agent_sessions[slot];
        }
        return &self.agy;
    }

    /// Resolves the best non-special source file index to attach as `@file` context for an agent prompt.
    /// Checks the active pane first, then any visible split pane, and finally the open buffers list.
    pub fn contextFileIndexForAgent(self: *const EditorState) ?usize {
        if (self.activeFileIndex()) |f_idx| {
            const wf = self.workspaceFiles()[f_idx];
            if (!wf.isSpecial()) return f_idx;
        }
        const p_count = self.paneCount();
        for (0..p_count) |p_idx| {
            if (self.paneActiveFile(p_idx)) |f_idx| {
                const wf = self.workspaceFiles()[f_idx];
                if (!wf.isSpecial()) return f_idx;
            }
        }
        const open_n = self.openBufferCount();
        for (0..open_n) |i| {
            const f_idx: usize = self.doc.open_buffers[i];
            if (f_idx < self.fileCount()) {
                const wf = self.workspaceFiles()[f_idx];
                if (!wf.isSpecial()) return f_idx;
            }
        }
        return null;
    }

    pub fn agyPrompt(self: *const EditorState) []const u8 {
        return self.agy_prompt.slice();
    }

    fn langFenceTag(lang: ui.CodeLanguage) []const u8 {
        return switch (lang) {
            .zig => "zig",
            .cpp => "cpp",
            .java => "java",
            .go => "go",
            .systemverilog => "systemverilog",
            .rust => "rust",
            .python => "python",
            .typescript => "ts",
            .vhdl => "vhdl",
            .chisel => "scala",
            .devicetree => "dts",
            .markdown => "markdown",
            .json => "json",
            .bash => "sh",
            .plain => "",
        };
    }

    fn formatContextualPrompt(self: *EditorState, instruction: []const u8, include_context: bool) []const u8 {
        if (!include_context) return instruction;
        if (self.ui_ctx.focused_id == ui.id("workbench_vterm") and self.vterm.hasSelection()) {
            if (self.vterm.copySelectionAlloc(self.frame_arena.allocator())) |term_sel| {
                return std.fmt.allocPrint(
                    self.frame_arena.allocator(),
                    "Terminal (`*terminal*`):\n```sh\n{s}\n```\n\n{s}",
                    .{ term_sel, instruction },
                ) catch instruction;
            }
        }
        if (self.activeFileIndex()) |active_idx| {
            const active_wf = self.workspaceFiles()[active_idx];
            if (active_wf.is_terminal) {
                const t_slot = self.ensureTerminalSlot(active_wf.terminal_slot);
                const vt = &self.term_vterms[t_slot];
                if (vt.hasSelection()) {
                    if (vt.copySelectionAlloc(self.frame_arena.allocator())) |term_sel| {
                        return std.fmt.allocPrint(
                            self.frame_arena.allocator(),
                            "Terminal (`{s}`):\n```sh\n{s}\n```\n\n{s}",
                            .{ active_wf.name, term_sel, instruction },
                        ) catch instruction;
                    }
                }
                return instruction;
            }
        }
        if (self.resolvePdfSourceForPane(self.activePaneIndex())) |pdf_src| {
            const pdf_doc = self.ui_ctx.parsePdfCached(pdf_src.eff_bytes, pdf_src.eff_path);
            const pdf_view = self.pdfViewStateForPane(self.activePaneIndex(), pdf_src.file_idx, pdf_src.is_direct_pdf);
            const label = if (pdf_src.eff_path.len > 0) pdf_src.eff_path else pdf_doc.title.slice();
            if (pdf_view.hasSelection()) {
                if (pdf_view.copySelectionWithSourceAlloc(pdf_doc, pdf_src.eff_bytes, pdf_src.eff_path, self.frame_arena.allocator())) |pdf_sel| {
                    const sel = pdf_view.normalizedSelection().?;
                    return std.fmt.allocPrint(
                        self.frame_arena.allocator(),
                        "PDF (`{s}`, page {d}-{d}):\n```text\n{s}\n```\n\n{s}",
                        .{ label, sel.start.page_idx + 1, sel.end.page_idx + 1, pdf_sel, instruction },
                    ) catch instruction;
                }
            }
            var page_tmp = pdf_view.*;
            page_tmp.selectPageWithSource(pdf_doc, pdf_view.current_page, pdf_src.eff_bytes, pdf_src.eff_path);
            if (page_tmp.copySelectionWithSourceAlloc(pdf_doc, pdf_src.eff_bytes, pdf_src.eff_path, self.frame_arena.allocator())) |page_txt| {
                return std.fmt.allocPrint(
                    self.frame_arena.allocator(),
                    "PDF (`{s}`, page {d} of {d}):\n```text\n{s}\n```\n\n{s}",
                    .{ label, pdf_view.current_page + 1, pdf_doc.page_count, page_txt, instruction },
                ) catch instruction;
            }
        }
        const f_idx = self.contextFileIndexForAgent() orelse return instruction;
        const wf = self.workspaceFiles()[f_idx];
        if (wf.isSpecial()) return instruction;

        const buf = &self.buffers[f_idx];
        if (buf.hasSelection()) {
            const sel_range = buf.selectionRange();
            const start_lc = buf.offsetToLineCol(sel_range.start);
            const end_lc = buf.offsetToLineCol(sel_range.end);
            const sel_slice = buf.selectedSlice();
            const fence = langFenceTag(wf.language);
            return std.fmt.allocPrint(
                self.frame_arena.allocator(),
                "File: `{s}` (lines {d}-{d}):\n```{s}\n{s}\n```\n\n{s}",
                .{ wf.path, start_lc.line + 1, end_lc.line + 1, fence, sel_slice, instruction },
            ) catch instruction;
        }
        return std.fmt.allocPrint(
            self.frame_arena.allocator(),
            "Target file: `{s}`\n\n{s}",
            .{ wf.path, instruction },
        ) catch instruction;
    }

    pub fn attachClipboardImageToAgySession(
        self: *EditorState,
        session: *agy_client.AgySession,
        clip_img: platform.ClipboardImage,
    ) bool {
        const dims = ui.queryImageDimensions(clip_img.source_path, clip_img.data) orelse ui.ImageDimensions{
            .width = 0,
            .height = 0,
        };
        if (!session.addImageAttachmentFromBytes(
            clip_img.data,
            clip_img.mime_type,
            clip_img.filename,
            clip_img.source_path,
            dims.width,
            dims.height,
        )) return false;

        const att_slice = session.pendingAttachments();
        const att_name = if (att_slice.len > 0) att_slice[att_slice.len - 1].name() else "image.png";
        var msg_buf: [128]u8 = undefined;
        const msg = if (dims.width > 0 and dims.height > 0)
            std.fmt.bufPrint(&msg_buf, "Attached image {s} ({d}×{d} px)", .{ att_name, dims.width, dims.height }) catch "Attached image to chat"
        else
            std.fmt.bufPrint(&msg_buf, "Attached image {s}", .{att_name}) catch "Attached image to chat";
        self.setStatusNotice(msg);
        self.ui_ctx.invalidateWindow();
        return true;
    }

    pub fn sendAgyPromptFromSession(
        self: *EditorState,
        session: *agy_client.AgySession,
        prompt: *platform.InlineString(8192),
        agent_slot_opt: ?usize,
    ) void {
        const user_msg = prompt.trim(" \t\r\n");
        const has_attachments = (session.pendingAttachments().len > 0);
        if (user_msg.len == 0 and !has_attachments) return;

        if (agent_slot_opt == null) {
            self.doc.show_agent_panel = true;
        }
        self.syncAgyHubState();
        if (session.pending_question.active and session.pending_question.question_count > 0 and !has_attachments) {
            var q0 = &session.pending_question.questions[0];
            q0.write_in.set(user_msg);
            q0.use_write_in = true;
            if (!q0.is_multi_select) q0.selected_mask = 0;
            prompt.clear();
            self.submitAgyQuestionResponseFor(session, false);
            return;
        }
        const payload = if (user_msg.len > 0)
            self.formatContextualPrompt(user_msg, self.doc.agy_include_context)
        else
            "";
        if (session.sendUserPrompt(payload)) {
            prompt.clear();
            self.syncAgyHubState();
            if (self.ui_ctx.platform_ctx) |pctx| pctx.needs_continuous_redraw = true;
            self.ui_ctx.invalidateWindow();
        }
    }

    pub fn submitAgyQuestionResponseFor(self: *EditorState, session: *agy_client.AgySession, skip_all: bool) void {
        self.syncAgyHubState();
        if (session.submitQuestionResponse(skip_all)) {
            self.syncAgyHubState();
            if (self.ui_ctx.platform_ctx) |pctx| pctx.needs_continuous_redraw = true;
            self.ui_ctx.invalidateWindow();
        }
    }

    /// Submits (or skips) the currently active `ask_question` interaction in the active Agent session.
    pub fn submitAgyQuestionResponse(self: *EditorState, skip_all: bool) void {
        self.submitAgyQuestionResponseFor(self.activeAgySession(), skip_all);
    }

    pub fn loadAgyConversationInto(
        self: *EditorState,
        session: *agy_client.AgySession,
        cascade_id: []const u8,
        agent_slot_opt: ?usize,
    ) void {
        if (agent_slot_opt == null) {
            self.doc.show_agent_panel = true;
        }
        self.syncAgyHubState();
        if (session.loadConversation(cascade_id)) {
            self.syncAgyHubState();
            if (self.ui_ctx.platform_ctx) |pctx| pctx.needs_continuous_redraw = true;
            const title = session.activeTitle();
            if (title.len > 0) {
                var msg_buf: [128]u8 = undefined;
                const msg = std.fmt.bufPrint(&msg_buf, "Resumed conversation: {s}", .{title}) catch "Resumed conversation";
                self.setStatusNotice(msg);
            } else {
                self.setStatusNotice("Resumed Antigravity conversation");
            }
            if (agent_slot_opt == null) {
                self.ui_ctx.focused_id = ui.scopedIdPath(&.{ "vscode_workbench", "agy_agent_panel" }, "##agy_prompt_input");
            }
            self.ui_ctx.invalidateWindow();
        }
    }

    /// Loads and resumes an existing Antigravity conversation by `cascadeId` in the active Agent session.
    pub fn loadAgyConversation(self: *EditorState, cascade_id: []const u8) void {
        if (self.activeFileIndex()) |f_idx| {
            const wf = self.workspaceFiles()[f_idx];
            if (wf.is_agent) {
                const slot = self.ensureAgentSlot(wf.agent_slot);
                self.loadAgyConversationInto(&self.agent_sessions[slot], cascade_id, slot);
                return;
            }
        }
        self.loadAgyConversationInto(&self.agy, cascade_id, null);
    }

    /// Opens the Agent Panel (or active `*agent-N*` buffer) and pops open the Conversation History switcher.
    pub fn openAgyConversationPicker(self: *EditorState) void {
        self.syncAgyHubState();
        if (self.activeFileIndex()) |f_idx| {
            const wf = self.workspaceFiles()[f_idx];
            if (wf.is_agent) {
                const slot = self.ensureAgentSlot(wf.agent_slot);
                var sess = &self.agent_sessions[slot];
                sess.open_picker_requested = true;
                sess.refreshConversations();
                self.syncAgyHubState();
                if (self.ui_ctx.platform_ctx) |pctx| pctx.needs_continuous_redraw = true;
                self.ui_ctx.invalidateWindow();
                return;
            }
        }
        self.doc.show_agent_panel = true;
        self.agy.open_picker_requested = true;
        self.agy.refreshConversations();
        self.syncAgyHubState();
        if (self.ui_ctx.platform_ctx) |pctx| pctx.needs_continuous_redraw = true;
        self.ui_ctx.invalidateWindow();
    }

    /// Formats and dispatches the current `agy_prompt` text to `self.agy.sendUserPrompt(...)`.
    /// When `self.doc.agy_include_context` is enabled and an active code buffer is open, automatically
    /// prepends the selected code region (§6.1) or target file reference (§6.2).
    pub fn sendAgyPromptFromInput(self: *EditorState) void {
        if (self.activeFileIndex()) |f_idx| {
            const wf = self.workspaceFiles()[f_idx];
            if (wf.is_agent) {
                const slot = self.ensureAgentSlot(wf.agent_slot);
                self.sendAgyPromptFromSession(&self.agent_sessions[slot], &self.agent_prompts[slot], slot);
                return;
            }
        }
        self.sendAgyPromptFromSession(&self.agy, &self.agy_prompt, null);
    }

    /// Sends a contextual prompt for the active selection (§6.1) or active file (§6.2), using either
    /// the typed prompt in `agy_prompt` or `fallback_instruction`.
    pub fn sendAgySelectionOrFilePrompt(self: *EditorState, fallback_instruction: []const u8) void {
        var target_sess: *agy_client.AgySession = &self.agy;
        var target_prompt: *platform.InlineString(8192) = &self.agy_prompt;
        var found_agent_pane = false;

        const p_count = self.paneCount();
        for (0..p_count) |p_idx| {
            if (self.paneActiveFile(p_idx)) |f_idx| {
                const wf = self.workspaceFiles()[f_idx];
                if (wf.is_agent) {
                    const slot = self.ensureAgentSlot(wf.agent_slot);
                    target_sess = &self.agent_sessions[slot];
                    target_prompt = &self.agent_prompts[slot];
                    found_agent_pane = true;
                    break;
                }
            }
        }
        if (!found_agent_pane) {
            self.doc.show_agent_panel = true;
        }
        self.syncAgyHubState();
        const typed = target_prompt.trim(" \t\r\n");
        const instruction = if (typed.len > 0) typed else fallback_instruction;
        const payload = self.formatContextualPrompt(instruction, true);
        if (target_sess.sendUserPrompt(payload)) {
            target_prompt.clear();
            self.syncAgyHubState();
            if (self.ui_ctx.platform_ctx) |pctx| pctx.needs_continuous_redraw = true;
            self.ui_ctx.invalidateWindow();
        }
    }

    /// Formats and sends diagnostics for the active buffer following `AGY_PROTOCOL.md` §6.3.
    pub fn sendAgyDiagnosticsPrompt(self: *EditorState) void {
        const f_idx = self.contextFileIndexForAgent() orelse {
            self.setStatusNotice("No active file for diagnostics prompt");
            return;
        };
        const wf = self.workspaceFiles()[f_idx];
        if (wf.isSpecial()) {
            self.setStatusNotice("Select a source file to send diagnostics");
            return;
        }

        var diags_buf: [16]DiagnosticItem = undefined;
        const diag_count = scanDiagnostics(self, f_idx, &diags_buf);
        if (diag_count == 0) {
            self.setStatusNotice("No diagnostics found in active file");
            return;
        }

        var prompt_list: std.ArrayList(u8) = .empty;
        const arena = self.frame_arena.allocator();
        const header = std.fmt.allocPrint(arena, "Fix the following diagnostics in `{s}`:\n", .{wf.path}) catch return;
        prompt_list.appendSlice(arena, header) catch return;

        for (diags_buf[0..diag_count]) |d| {
            const sev_tag = switch (d.severity) {
                .err => "error",
                .warn => "warning",
                .info => "note",
            };
            const line_entry = std.fmt.allocPrint(
                arena,
                "- Line {d} [{s}]: {s}\n",
                .{ d.line, sev_tag, d.message },
            ) catch continue;
            prompt_list.appendSlice(arena, line_entry) catch continue;
        }

        var target_sess: *agy_client.AgySession = &self.agy;
        var found_agent_pane = false;
        const p_count = self.paneCount();
        for (0..p_count) |p_idx| {
            if (self.paneActiveFile(p_idx)) |pf_idx| {
                const pwf = self.workspaceFiles()[pf_idx];
                if (pwf.is_agent) {
                    const slot = self.ensureAgentSlot(pwf.agent_slot);
                    target_sess = &self.agent_sessions[slot];
                    found_agent_pane = true;
                    break;
                }
            }
        }
        if (!found_agent_pane) {
            self.doc.show_agent_panel = true;
        }
        self.syncAgyHubState();
        if (target_sess.sendUserPrompt(prompt_list.items)) {
            self.syncAgyHubState();
            if (self.ui_ctx.platform_ctx) |pctx| pctx.needs_continuous_redraw = true;
            self.ui_ctx.invalidateWindow();
        }
    }

    pub fn handoffAgySessionToTerminal(self: *EditorState, session: *agy_client.AgySession) void {
        if (session.isProcessAlive()) {
            session.interruptTurn();
        }

        self.createTerminalBuffer(false);
        const f_idx = self.activeFileIndex() orelse return;
        const wf = self.workspaceFiles()[f_idx];
        if (!wf.is_terminal) return;

        const t_slot = self.ensureTerminalSlot(wf.terminal_slot);
        var vt = &self.term_vterms[t_slot];
        _ = vt.spawnShell(28, 90);

        var cmd_buf: [160]u8 = undefined;
        const cid = session.conversationId();
        const cmd = if (cid.len > 0)
            std.fmt.bufPrint(&cmd_buf, "agy --conversation {s}\n", .{cid}) catch "agy\n"
        else
            "agy\n";
        vt.writeInput(cmd);
        self.setStatusNotice("Launched interactive agy TUI in terminal buffer");
        self.ui_ctx.invalidateWindow();
    }

    pub fn handoffAgyToTerminal(self: *EditorState) void {
        self.handoffAgySessionToTerminal(self.activeAgySession());
    }

    // ========================================================================
    // Antigravity Supercomplete Commands (`toggle`, `restart`, `trigger`)
    // ========================================================================

    pub fn toggleSupercomplete(self: *EditorState) void {
        self.doc.supercomplete_enabled = !self.doc.supercomplete_enabled;
        self.supercomplete.enabled = self.doc.supercomplete_enabled;
        if (!self.doc.supercomplete_enabled) {
            self.supercomplete.onDismissed();
            self.setStatusNotice("Antigravity Supercomplete: Disabled");
        } else {
            const now_ms: i64 = @intCast(platform.profiler.nowNs() / std.time.ns_per_ms);
            if (!self.supercomplete.isConnected()) {
                _ = self.supercomplete.attach(now_ms);
            }
            self.setStatusNotice("Antigravity Supercomplete: Enabled");
        }
        self.ui_ctx.invalidateWindow();
    }

    pub fn reconnectSupercomplete(self: *EditorState) void {
        const now_ms: i64 = @intCast(platform.profiler.nowNs() / std.time.ns_per_ms);
        const ok = self.supercomplete.attach(now_ms);
        if (ok) {
            var msg_buf: [80]u8 = undefined;
            const msg = std.fmt.bufPrint(&msg_buf, "Supercomplete: Connected (port {d})", .{self.supercomplete.ls_port}) catch "Supercomplete: Connected";
            self.setStatusNotice(msg);
        } else {
            self.setStatusNotice("Supercomplete: Waiting for Antigravity Hub");
        }
        self.ui_ctx.invalidateWindow();
    }

    pub fn triggerSupercomplete(self: *EditorState) void {
        const f_idx = self.activeFileIndex() orelse return;
        const wf = self.workspaceFiles()[f_idx];
        if (wf.isSpecial()) return;

        self.doc.supercomplete_enabled = true;
        const now_ms: i64 = @intCast(platform.profiler.nowNs() / std.time.ns_per_ms);
        if (!self.supercomplete.isConnected()) {
            _ = self.supercomplete.attach(now_ms);
        }
        const buf = &self.buffers[f_idx];
        self.supercomplete.triggerExplicit(now_ms, f_idx, buf.cursor, buf.edit_version);
        if (self.ui_ctx.platform_ctx) |pctx| pctx.needs_continuous_redraw = true;
        self.setStatusNotice("Supercomplete: Triggered inline suggestion");
        self.ui_ctx.invalidateWindow();
    }

    pub fn statusNotice(self: *const EditorState) []const u8 {
        return self.status_notice.slice();
    }

    pub fn setStatusNotice(self: *EditorState, msg: []const u8) void {
        self.status_notice.set(msg);
        if (msg.len > 0) {
            self.appendOutput("Notice", msg);
        }
    }

    pub fn appendOutput(self: *EditorState, channel: []const u8, text: []const u8) void {
        const trimmed = std.mem.trim(u8, text, " \t\r\n");
        if (trimmed.len == 0) return;
        if (self.output_line_count < MaxOutputLines) {
            var entry = &self.output_lines[self.output_line_count];
            entry.* = .{};
            entry.channel.set(channel);
            entry.text.set(trimmed);
            self.output_line_count += 1;
        } else {
            for (0..MaxOutputLines - 1) |i| {
                self.output_lines[i] = self.output_lines[i + 1];
            }
            var entry = &self.output_lines[MaxOutputLines - 1];
            entry.* = .{};
            entry.channel.set(channel);
            entry.text.set(trimmed);
        }
    }

    pub fn clearOutput(self: *EditorState) void {
        self.output_line_count = 0;
    }

    pub const folderPathHash = workspace_fs.folderPathHash;

    pub fn isFolderExpanded(self: *const EditorState, folder_path: []const u8) bool {
        const h = folderPathHash(folder_path);
        const cnt = @min(@as(usize, self.doc.collapsed_folder_count), MaxCollapsedFolders);
        for (self.doc.collapsed_folder_hashes[0..cnt]) |entry_h| {
            if (entry_h == h) return !self.doc.folder_default_expanded;
        }
        return self.doc.folder_default_expanded;
    }

    pub fn setFolderExpanded(self: *EditorState, folder_path: []const u8, expanded: bool) void {
        const h = folderPathHash(folder_path);
        const cnt = @min(@as(usize, self.doc.collapsed_folder_count), MaxCollapsedFolders);
        const differs_from_default = (expanded != self.doc.folder_default_expanded);

        var found_idx: ?usize = null;
        for (self.doc.collapsed_folder_hashes[0..cnt], 0..) |entry_h, idx| {
            if (entry_h == h) {
                found_idx = idx;
                break;
            }
        }

        if (differs_from_default) {
            if (found_idx == null and cnt < MaxCollapsedFolders) {
                self.doc.collapsed_folder_hashes[cnt] = h;
                self.doc.collapsed_folder_count = @intCast(cnt + 1);
            }
        } else {
            if (found_idx) |rem_idx| {
                var i = rem_idx;
                while (i + 1 < cnt) : (i += 1) {
                    self.doc.collapsed_folder_hashes[i] = self.doc.collapsed_folder_hashes[i + 1];
                }
                self.doc.collapsed_folder_hashes[cnt - 1] = 0;
                self.doc.collapsed_folder_count = @intCast(cnt - 1);
            }
        }

        if (expanded and self.has_opened_workspace and folder_path.len > 0 and !std.mem.eql(u8, folder_path, ".")) {
            const depth = 1 + std.mem.count(u8, folder_path, "/");
            self.scanSingleDirectoryLevel(folder_path, depth, true);
        }
    }

    pub fn setAllFolderNodesExpanded(self: *EditorState, expanded: bool) void {
        self.doc.folder_default_expanded = expanded;
        self.doc.collapsed_folder_hashes = @splat(0);
        self.doc.collapsed_folder_count = 0;
        self.doc.folder_src = expanded;
        self.doc.folder_src_app = expanded;
        self.doc.folder_src_app_views = expanded;
        self.doc.folder_src_ui = expanded;
        self.doc.folder_src_platform = expanded;
        self.doc.folder_src_platform_macos = expanded;
        self.doc.folder_src_skia = expanded;
        self.doc.folder_src_skia_c = expanded;
        self.doc.folder_examples = expanded;
    }

    pub fn expandFolderAndAncestors(self: *EditorState, folder_path: []const u8) void {
        if (folder_path.len == 0 or std.mem.eql(u8, folder_path, ".")) return;
        var i: usize = 0;
        while (i <= folder_path.len) : (i += 1) {
            if (i == folder_path.len or folder_path[i] == '/') {
                if (i > 0) {
                    self.setFolderExpanded(folder_path[0..i], true);
                }
            }
        }
    }

    pub const mkdirRecursive = workspace_fs.mkdirRecursive;
    pub const removeDirectoryRecursive = workspace_fs.removeDirectoryRecursive;

    pub fn openSaveAsPromptInFolder(self: *EditorState, folder: []const u8) void {
        self.show_save_as_prompt = true;
        self.save_as_create_empty = true;
        self.show_new_folder_prompt = false;
        self.doc.show_command_palette = false;
        self.show_stage_all_prompt = false;
        self.save_as_path.clear();
        if (folder.len > 0 and !std.mem.eql(u8, folder, ".")) {
            var tmp: [256]u8 = undefined;
            const s = std.fmt.bufPrint(&tmp, "{s}/new_file.zig", .{folder}) catch "new_file.zig";
            self.save_as_path.set(s);
        } else {
            self.save_as_path.set("new_file.zig");
        }
        self.ui_ctx.focusAndSelectAll(ui.scopedIdPath(&.{ "vscode_workbench", "editor_pane" }, "##save_as_input"));
        self.ui_ctx.invalidateWindow();
    }

    pub fn openNewFolderPromptInFolder(self: *EditorState, folder: []const u8) void {
        self.show_new_folder_prompt = true;
        self.show_save_as_prompt = false;
        self.save_as_create_empty = false;
        self.doc.show_command_palette = false;
        self.show_stage_all_prompt = false;
        self.new_folder_path.clear();
        if (folder.len > 0 and !std.mem.eql(u8, folder, ".")) {
            var tmp: [256]u8 = undefined;
            const s = std.fmt.bufPrint(&tmp, "{s}/new_folder", .{folder}) catch "new_folder";
            self.new_folder_path.set(s);
        } else {
            self.new_folder_path.set("new_folder");
        }
        self.ui_ctx.focusAndSelectAll(ui.scopedIdPath(&.{ "vscode_workbench", "editor_pane" }, "##new_folder_input"));
        self.ui_ctx.invalidateWindow();
    }

    pub fn createWorkspaceDirectory(self: *EditorState, raw_path: []const u8) bool {
        var rel_path = std.mem.trim(u8, raw_path, " \t\r\n\"'");
        while (std.mem.startsWith(u8, rel_path, "./")) {
            rel_path = rel_path[2..];
        }
        while (rel_path.len > 0 and rel_path[rel_path.len - 1] == '/') {
            rel_path = rel_path[0 .. rel_path.len - 1];
        }
        if (rel_path.len == 0 or rel_path.len >= 254 or std.mem.eql(u8, rel_path, ".") or std.mem.eql(u8, rel_path, "..") or rel_path[0] == '/' or std.mem.indexOfPos(u8, rel_path, 0, "..") != null) {
            self.setStatusNotice("Create folder failed: enter a valid relative folder path");
            return false;
        }

        var path_copy_buf: [256]u8 = undefined;
        @memcpy(path_copy_buf[0..rel_path.len], rel_path);
        const clean_path = path_copy_buf[0..rel_path.len];

        if (!mkdirRecursive(clean_path)) {
            self.setStatusNotice("Create folder failed: could not create directory on disk");
            return false;
        }

        self.expandFolderAndAncestors(clean_path);
        self.show_new_folder_prompt = false;
        self.new_folder_path.clear();
        self.scanWorkspaceDirectories(false);
        self.last_watch_sig = self.computeWorkspaceWatchSignature();

        var msg_buf: [96]u8 = undefined;
        const msg = std.fmt.bufPrint(&msg_buf, "Created folder {s}", .{clean_path}) catch "Created folder";
        self.setStatusNotice(msg);
        self.ui_ctx.focused_id = self.activeEditorWidgetId();
        self.ui_ctx.invalidateWindow();
        return true;
    }

    pub fn createNewFolderFromPrompt(self: *EditorState) bool {
        return self.createWorkspaceDirectory(self.newFolderPath());
    }

    pub fn deleteWorkspaceFile(self: *EditorState, idx: usize) bool {
        if (self.file_count == 0) {
            self.refreshWorkspaceFiles(false);
        self.agy.syncWorkspaceRoot(self.workspaceRoot());
        }
        if (idx >= self.file_count or self.file_count <= 1) return false;
        const wf = self.files[idx];
        if (wf.isSpecial() or wf.path.len == 0 or wf.path.len >= 254) return false;

        var path_z_buf: [256:0]u8 = @splat(0);
        const p_len = wf.path.len;
        @memcpy(path_z_buf[0..p_len], wf.path);
        path_z_buf[p_len] = 0;
        const deleted_path = path_z_buf[0..p_len];

        _ = posix_dir.unlink(&path_z_buf);
        if (fileExistsOnDisk(deleted_path)) {
            self.setStatusNotice("Delete failed: could not remove file from disk");
            return false;
        }

        self.removeWorkspaceFileSlot(idx);
        self.scanWorkspaceDirectories(false);
        _ = self.reloadModifiedOpenFiles();
        self.refreshGitStatus();
        self.last_watch_sig = self.computeWorkspaceWatchSignature();

        var msg_buf: [96]u8 = undefined;
        const msg = std.fmt.bufPrint(&msg_buf, "Deleted {s}", .{deleted_path}) catch "Deleted file";
        self.setStatusNotice(msg);
        self.ui_ctx.invalidateWindow();
        return true;
    }

    pub fn deleteWorkspaceDirectory(self: *EditorState, raw_folder: []const u8) bool {
        var rel_dir = std.mem.trim(u8, raw_folder, " \t\r\n\"'");
        while (std.mem.startsWith(u8, rel_dir, "./")) {
            rel_dir = rel_dir[2..];
        }
        while (rel_dir.len > 0 and rel_dir[rel_dir.len - 1] == '/') {
            rel_dir = rel_dir[0 .. rel_dir.len - 1];
        }
        if (rel_dir.len == 0 or rel_dir.len >= 254 or std.mem.eql(u8, rel_dir, ".") or std.mem.eql(u8, rel_dir, "..") or rel_dir[0] == '/' or std.mem.indexOfPos(u8, rel_dir, 0, "..") != null) {
            self.setStatusNotice("Cannot delete workspace root directory");
            return false;
        }

        var dir_copy_buf: [256]u8 = undefined;
        @memcpy(dir_copy_buf[0..rel_dir.len], rel_dir);
        const clean_dir = dir_copy_buf[0..rel_dir.len];

        if (!removeDirectoryRecursive(clean_dir, 0)) {
            self.setStatusNotice("Delete folder failed: could not remove directory");
            return false;
        }

        if (self.file_count == 0) {
            self.refreshWorkspaceFiles(false);
        self.agy.syncWorkspaceRoot(self.workspaceRoot());
        }
        var idx: usize = self.file_count;
        while (idx > 0) {
            idx -= 1;
            const wf = self.files[idx];
            if (wf.isSpecial()) continue;
            const in_folder = std.mem.eql(u8, wf.folder, clean_dir) or
                (std.mem.startsWith(u8, wf.folder, clean_dir) and
                    wf.folder.len > clean_dir.len and
                    wf.folder[clean_dir.len] == '/');
            if (in_folder and self.file_count > 1) {
                self.removeWorkspaceFileSlot(idx);
            }
        }

        self.setFolderExpanded(clean_dir, self.doc.folder_default_expanded);
        self.scanWorkspaceDirectories(false);
        _ = self.reloadModifiedOpenFiles();
        self.refreshGitStatus();
        self.last_watch_sig = self.computeWorkspaceWatchSignature();

        var msg_buf: [96]u8 = undefined;
        const msg = std.fmt.bufPrint(&msg_buf, "Deleted folder {s}", .{clean_dir}) catch "Deleted folder";
        self.setStatusNotice(msg);
        self.ui_ctx.invalidateWindow();
        return true;
    }

    pub fn openContextMenu(
        self: *EditorState,
        target: ContextMenuTarget,
        pane_idx: usize,
        file_idx: ?usize,
        is_bottom_term: bool,
    ) void {
        self.openContextMenuAt(
            target,
            pane_idx,
            file_idx,
            is_bottom_term,
            self.ui_ctx.mouse_x,
            self.ui_ctx.mouse_y,
        );
    }

    pub fn openContextMenuAt(
        self: *EditorState,
        target: ContextMenuTarget,
        pane_idx: usize,
        file_idx: ?usize,
        is_bottom_term: bool,
        anchor_x: f32,
        anchor_y: f32,
    ) void {
        self.doc.show_command_palette = false;
        self.show_open_workspace_prompt = false;
        self.show_save_as_prompt = false;
        self.show_new_folder_prompt = false;
        self.show_stage_all_prompt = false;
        self.context_menu_target = target;
        self.context_menu_pane = pane_idx;
        self.context_menu_file = file_idx;
        self.context_menu_is_bottom_term = is_bottom_term;
        self.context_menu_is_staged = false;
        self.context_menu.openAt(
            anchor_x,
            anchor_y,
            @intFromEnum(target),
        );
        self.ui_ctx.invalidateWindow();
    }
};

// ============================================================================
// Live Symbol Outline & Diagnostics Analysis (delegated to `src/app/analysis.zig`)
// ============================================================================

pub const extractSymbols = analysis.extractSymbols;

pub fn scanDiagnostics(state: *const EditorState, active_file_idx: usize, out: []DiagnosticItem) usize {
    const wfs = state.workspaceFiles();
    const clamped_idx = active_file_idx % wfs.len;
    const source = state.buffers[clamped_idx].slice();
    const lang = wfs[clamped_idx].language;
    return analysis.scanDiagnosticsSource(source, lang, active_file_idx, out);
}

test "EditorState & EditorDocument: JSON hot-reload snapshot round-trip, split panes, tab lifecycle, and language detection" {
    // 1. Language detection across all 15 CodeLanguage modes
    try std.testing.expectEqual(ui.CodeLanguage.zig, EditorState.detectLanguageForPath("src/app/state.zig"));
    try std.testing.expectEqual(ui.CodeLanguage.cpp, EditorState.detectLanguageForPath("include/engine.hpp"));
    try std.testing.expectEqual(ui.CodeLanguage.java, EditorState.detectLanguageForPath("src/Main.java"));
    try std.testing.expectEqual(ui.CodeLanguage.go, EditorState.detectLanguageForPath("cmd/server/main.go"));
    try std.testing.expectEqual(ui.CodeLanguage.systemverilog, EditorState.detectLanguageForPath("rtl/axi_fifo.sv"));
    try std.testing.expectEqual(ui.CodeLanguage.rust, EditorState.detectLanguageForPath("crates/core/lib.rs"));
    try std.testing.expectEqual(ui.CodeLanguage.python, EditorState.detectLanguageForPath("scripts/eval.py"));
    try std.testing.expectEqual(ui.CodeLanguage.typescript, EditorState.detectLanguageForPath("web/index.tsx"));
    try std.testing.expectEqual(ui.CodeLanguage.vhdl, EditorState.detectLanguageForPath("rtl/uart.vhdl"));
    try std.testing.expectEqual(ui.CodeLanguage.chisel, EditorState.detectLanguageForPath("chisel/Core.scala"));
    try std.testing.expectEqual(ui.CodeLanguage.devicetree, EditorState.detectLanguageForPath("board/soc.dtsi"));
    try std.testing.expectEqual(ui.CodeLanguage.markdown, EditorState.detectLanguageForPath("README.md"));
    try std.testing.expectEqual(ui.CodeLanguage.json, EditorState.detectLanguageForPath("package.json"));
    try std.testing.expectEqual(ui.CodeLanguage.bash, EditorState.detectLanguageForPath(".envrc"));
    try std.testing.expectEqual(ui.CodeLanguage.plain, EditorState.detectLanguageForPath("notes.txt"));

    // 2. Initialize EditorState and test split-pane + tab lifecycle
    var store = platform.StateStore.init(std.testing.allocator);
    defer store.deinit();
    var snap = platform.SnapshotBuffer.init(std.testing.allocator);
    defer snap.deinit();
    var pctx = platform.PlatformContext{ .width = 1280.0, .height = 800.0 };
    pctx.bindHostStores(&store, &snap);

    const state = try std.testing.allocator.create(EditorState);
    defer std.testing.allocator.destroy(state);
    state.* = .{
        .frame_arena = std.heap.ArenaAllocator.init(std.testing.allocator),
        .fonts = undefined,
        .ui_ctx = undefined,
    };
    state.initResources(&pctx);
    defer state.deinitResources();

    // Open file 0, then split horizontally and open file 1 in the new pane
    state.openFile(0);
    try std.testing.expectEqual(@as(usize, 1), state.paneCount());
    try std.testing.expectEqual(@as(?usize, 0), state.activeFileIndex());

    state.splitPaneHorizontal(0);
    try std.testing.expectEqual(@as(usize, 2), state.paneCount());
    state.openFile(1);
    try std.testing.expectEqual(@as(?usize, 1), state.activeFileIndex());

    // Modify EditorDocument preferences & serialize via PlatformContext JSON snapshot
    state.doc.show_sidebar = true;
    state.doc.show_bottom_panel = true;
    state.doc.show_agent_panel = true;
    state.doc.sidebar_width = 288.0;
    try pctx.saveSnapshotJson(std.testing.allocator, state.doc);

    const restored = pctx.loadSnapshotJson(EditorDocument, std.testing.allocator) orelse return error.SnapshotRestoreFailed;
    try std.testing.expect(restored.show_sidebar);
    try std.testing.expect(restored.show_bottom_panel);
    try std.testing.expect(restored.show_agent_panel);
    try std.testing.expectEqual(@as(f32, 288.0), restored.sidebar_width);
    try std.testing.expectEqual(@as(u8, 2), restored.split_tree.pane_count);

    // Closing the active tab in pane 1 collapses back to 1 pane
    state.closeTabInPane(1, 0);
    try std.testing.expectEqual(@as(usize, 1), state.paneCount());

    // 3. Verify dynamic folder expansion state (arbitrary directory paths default to collapsed)
    try std.testing.expect(!state.isFolderExpanded("src"));
    try std.testing.expect(!state.isFolderExpanded("examples/autocomplete"));
    try std.testing.expect(!state.isFolderExpanded("plugins"));

    state.setFolderExpanded("examples/autocomplete", true);
    try std.testing.expect(state.isFolderExpanded("examples/autocomplete"));
    try std.testing.expect(!state.isFolderExpanded("examples"));

    state.setAllFolderNodesExpanded(true);
    try std.testing.expect(state.isFolderExpanded("src"));
    try std.testing.expect(state.isFolderExpanded("plugins"));

    state.setFolderExpanded("plugins", false);
    try std.testing.expect(!state.isFolderExpanded("plugins"));
    try std.testing.expect(state.isFolderExpanded("src"));

    // 4. Verify workspace directory and file scanner discovers all files and directories on disk
    try std.testing.expect(state.workspaceFolders().len > 0);
    try std.testing.expect(state.workspaceFiles().len > 150);
    try std.testing.expect(state.findWorkspaceFileIndexByPath("src/app/views/explorer.zig") != null);
    try std.testing.expect(state.findWorkspaceFileIndexByPath("src/app/commands.zig") != null);
    try std.testing.expect(state.findWorkspaceFileIndexByPath("plugins/doc_metrics.zig") != null);
    try std.testing.expect(state.findWorkspaceFileIndexByPath("examples/studio/main.zig") != null);

    // 5. Verify creating a directory, creating a file inside it, deleting the file, and deleting the directory
    const test_dir = "tmp_explorer_test_dir/sub";
    const test_file = "tmp_explorer_test_dir/sub/hello.zig";
    defer _ = state.deleteWorkspaceDirectory("tmp_explorer_test_dir");

    try std.testing.expect(state.createWorkspaceDirectory(test_dir));
    state.openSaveAsPromptInFolder(test_dir);
    state.save_as_path.set(test_file);
    try std.testing.expect(state.saveActiveOrScratchToNewFile());

    const created_idx = state.findWorkspaceFileIndexByPath(test_file) orelse return error.TestFileNotRegistered;
    try std.testing.expect(state.deleteWorkspaceFile(created_idx));
    try std.testing.expect(state.findWorkspaceFileIndexByPath(test_file) == null);
    try std.testing.expect(state.deleteWorkspaceDirectory("tmp_explorer_test_dir"));

    // 6. Verify switching workspaces at runtime using a temporary directory
    var orig_cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
    const orig_root = if (posix_dir.realpath(".", &orig_cwd_buf)) |cz|
        std.mem.sliceTo(cz, 0)
    else
        state.doc.workspace_root_buf[0..state.doc.workspace_root_len];

    try std.testing.expect(state.createWorkspaceDirectory("tmp_ws_switch_test"));
    defer {
        _ = state.openWorkspaceDirectory(orig_root);
        _ = state.deleteWorkspaceDirectory("tmp_ws_switch_test");
    }
    state.openSaveAsPromptInFolder("tmp_ws_switch_test");
    state.save_as_path.set("tmp_ws_switch_test/main.c");
    try std.testing.expect(state.saveActiveOrScratchToNewFile());

    try std.testing.expect(state.openWorkspaceDirectory("tmp_ws_switch_test"));
    try std.testing.expectEqualStrings("tmp_ws_switch_test", state.workspaceName());
    try std.testing.expect(state.findWorkspaceFileIndexByPath("main.c") != null);

    // 7. Verify deep nested directories (>8 levels) and large workspace scanning (`~/Projects/beaglebone` if present)
    const deep_dir = "a/b/c/d/e/f/g/h/i";
    const deep_file = "a/b/c/d/e/f/g/h/i/deep_driver.h";
    try std.testing.expect(state.createWorkspaceDirectory(deep_dir));
    state.openSaveAsPromptInFolder(deep_dir);
    state.save_as_path.set(deep_file);
    try std.testing.expect(state.saveActiveOrScratchToNewFile());
    state.refreshWorkspaceFiles(false);
    try std.testing.expect(state.findWorkspaceFileIndexByPath(deep_file) != null);

    if (state.openWorkspaceDirectory("~/Projects/beaglebone")) {
        try std.testing.expect(state.nonSpecialFileCount() >= 900);
        try std.testing.expect(state.findWorkspaceFileIndexByPath("README.md") != null);
        try std.testing.expect(state.findWorkspaceFileIndexByPath("AGENTS.md") != null);
        try std.testing.expect(state.findWorkspaceFileIndexByPath("Makefile") != null);
        try std.testing.expect(state.findWorkspaceFileIndexByPath("examples/01_demo_led_btn_int/main.c") != null);
        try std.testing.expect(state.findWorkspaceFileIndexByPath("freertos/portable/GCC/BBB/drivers/include/hw/hw_lcdc.h") != null);
        try std.testing.expect(state.findWorkspaceFileIndexByPath("resources/freertos/portable/GCC/BBB/drivers/include/armv7a/am335x/bbblack.h") != null);
    }

    // Switch back to the original workspace
    try std.testing.expect(state.openWorkspaceDirectory(orig_root));
    try std.testing.expect(state.findWorkspaceFileIndexByPath("src/app/state.zig") != null);
}

test "iCloud file handling: placeholder unwrapping, atomic writes, and cloud dataless sizing" {
    // 1. Placeholder unwrapping
    try std.testing.expectEqualStrings("hw2.md", EditorState.unwrapICloudPlaceholder(".hw2.md.icloud") orelse return error.UnwrapFailed);
    try std.testing.expectEqualStrings("notes.txt", EditorState.unwrapICloudPlaceholder(".notes.txt.icloud") orelse return error.UnwrapFailed);
    try std.testing.expect(EditorState.unwrapICloudPlaceholder("hw2.md") == null);
    try std.testing.expect(EditorState.unwrapICloudPlaceholder(".icloud") == null);
    try std.testing.expect(EditorState.unwrapICloudPlaceholder("..icloud") == null);
    try std.testing.expect(EditorState.unwrapICloudPlaceholder(".DS_Store") == null);

    // 2. Placeholder path generation
    var ph_buf: [512:0]u8 = @splat(0);
    const ph1 = EditorState.getICloudPlaceholderPath("hw2.md", &ph_buf) orelse return error.PlaceholderFailed;
    try std.testing.expectEqualStrings(".hw2.md.icloud", std.mem.sliceTo(ph1, 0));

    const ph2 = EditorState.getICloudPlaceholderPath("folder/sub/notes.txt", &ph_buf) orelse return error.PlaceholderFailed;
    try std.testing.expectEqualStrings("folder/sub/.notes.txt.icloud", std.mem.sliceTo(ph2, 0));

    const ph3 = EditorState.getICloudPlaceholderPath("/Users/test/Documents/hw2.md", &ph_buf) orelse return error.PlaceholderFailed;
    try std.testing.expectEqualStrings("/Users/test/Documents/.hw2.md.icloud", std.mem.sliceTo(ph3, 0));

    try std.testing.expect(EditorState.getICloudPlaceholderPath(".already.icloud", &ph_buf) == null);

    // 3. Atomic file write & replacement
    const test_path_z: [*:0]const u8 = "tmp_icloud_atomic_test.txt";
    defer _ = posix_dir.unlink(test_path_z);
    const initial_data = "Hello from iCloud test\nLine 2";
    try std.testing.expect(EditorState.writeSliceToDiskAtomic(test_path_z, initial_data));

    // Verify file size and content
    const sz1 = EditorState.regularFileSizeOnDisk(test_path_z) orelse return error.SizeFailed;
    try std.testing.expectEqual(initial_data.len, sz1);

    // Atomic update
    const updated_data = "Updated content in atomic swap mode\nLine 2\nLine 3";
    try std.testing.expect(EditorState.writeSliceToDiskAtomic(test_path_z, updated_data));
    const sz2 = EditorState.regularFileSizeOnDisk(test_path_z) orelse return error.SizeFailed;
    try std.testing.expectEqual(updated_data.len, sz2);

    // Verify temporary file was cleaned up
    var tmp_check_buf: [512:0]u8 = @splat(0);
    const tmp_str = std.fmt.bufPrint(tmp_check_buf[0..510], ".{s}.editor_tmp", .{std.mem.sliceTo(test_path_z, 0)}) catch return error.FormatFailed;
    tmp_check_buf[tmp_str.len] = 0;
    var tmp_st: std.c.Stat = undefined;
    try std.testing.expect(std.c.stat(&tmp_check_buf, &tmp_st) != 0);

    // 4. Verify fileExistsOnDisk reads our temporary file
    try std.testing.expect(EditorState.fileExistsOnDisk(std.mem.sliceTo(test_path_z, 0)));

    // 5. Evicted placeholder detection: simulated .evicted.md.icloud file
    const evicted_ph: [*:0]const u8 = ".evicted_test.md.icloud";
    defer _ = posix_dir.unlink(evicted_ph);
    if (std.c.fopen(evicted_ph, "wb")) |fp| {
        _ = std.c.fwrite("plist_metadata", 1, 14, fp);
        _ = std.c.fclose(fp);
    }
    try std.testing.expect(EditorState.fileExistsOnDisk("evicted_test.md"));
}

test {
    _ = workspace_fs;
    _ = hot_reload_stash;
    _ = workspace_search;
}

test "EditorState: automatic reload of open unmodified files when changed on disk (while preserving dirty buffers)" {
    var store = platform.StateStore.init(std.testing.allocator);
    defer store.deinit();
    var snap = platform.SnapshotBuffer.init(std.testing.allocator);
    defer snap.deinit();
    var pctx = platform.PlatformContext{ .width = 1280.0, .height = 800.0 };
    pctx.bindHostStores(&store, &snap);

    const state = try std.testing.allocator.create(EditorState);
    defer std.testing.allocator.destroy(state);
    state.* = .{
        .frame_arena = std.heap.ArenaAllocator.init(std.testing.allocator),
        .fonts = undefined,
        .ui_ctx = undefined,
    };
    state.initResources(&pctx);
    defer state.deinitResources();

    const test_rel = "tmp_auto_reload_test.zig";
    const test_path_z: [*:0]const u8 = "tmp_auto_reload_test.zig";
    defer _ = posix_dir.unlink(test_path_z);

    // 1. Create a file on disk and open it in the editor
    const v1_content = "// line 1\nconst x: u32 = 10;\n// line 3\n";
    try std.testing.expect(EditorState.writeSliceToDiskAtomic(test_path_z, v1_content));
    state.refreshWorkspaceFiles(false);

    const f_idx = state.findWorkspaceFileIndexByPath(test_rel) orelse return error.TestFileNotRegistered;
    state.openFile(f_idx);
    try std.testing.expectEqualStrings(v1_content, state.buffers[f_idx].slice());
    try std.testing.expect(!state.isFileDirty(f_idx));

    // Place cursor on line 2, col 7 (0-based line 1, col 6)
    state.buffers[f_idx].jumpToLine(2);
    state.buffers[f_idx].cursor += 6;
    state.buffers[f_idx].selection_anchor = state.buffers[f_idx].cursor;
    const before_lc = state.buffers[f_idx].offsetToLineCol(state.buffers[f_idx].cursor);
    try std.testing.expectEqual(@as(usize, 1), before_lc.line);
    try std.testing.expectEqual(@as(usize, 6), before_lc.col);

    // 2. Modify the file externally on disk while the buffer in the editor is unmodified
    const v2_content = "// line 1\nconst x: u32 = 42;\nconst y: u32 = 99;\n";
    try std.testing.expect(EditorState.writeSliceToDiskAtomic(test_path_z, v2_content));

    state.ui_ctx.pass = .input;
    state.last_watch_poll_ms = 0;
    state.pollWorkspaceWatch();

    try std.testing.expectEqualStrings(v2_content, state.buffers[f_idx].slice());
    try std.testing.expect(!state.isFileDirty(f_idx));
    const after_lc = state.buffers[f_idx].offsetToLineCol(state.buffers[f_idx].cursor);
    try std.testing.expectEqual(@as(usize, 1), after_lc.line);
    try std.testing.expectEqual(@as(usize, 6), after_lc.col);

    // 3. Make an unsaved edit in the editor (`isFileDirty == true`), then modify the file on disk:
    //    verify the user's unsaved in-memory buffer is NOT overwritten
    const dirty_in_memory = "// unsaved local edit\nconst x: u32 = 777;\n";
    state.buffers[f_idx].resetWithSlice(dirty_in_memory);
    try std.testing.expect(state.isFileDirty(f_idx));

    const v3_disk_content = "// external disk edit while buffer is dirty\n";
    try std.testing.expect(EditorState.writeSliceToDiskAtomic(test_path_z, v3_disk_content));

    state.last_watch_poll_ms = 0;
    state.pollWorkspaceWatch();
    try std.testing.expectEqualStrings(dirty_in_memory, state.buffers[f_idx].slice());
    try std.testing.expect(state.isFileDirty(f_idx));
}

test "EditorState.pollWorkspaceWatch: zero redundant open-file reloads or window invalidations while idle" {
    var store = platform.StateStore.init(std.testing.allocator);
    defer store.deinit();
    var snap = platform.SnapshotBuffer.init(std.testing.allocator);
    defer snap.deinit();
    var pctx = platform.PlatformContext{ .width = 1280.0, .height = 800.0 };
    pctx.bindHostStores(&store, &snap);

    const state = try std.testing.allocator.create(EditorState);
    defer std.testing.allocator.destroy(state);
    state.* = .{
        .frame_arena = std.heap.ArenaAllocator.init(std.testing.allocator),
        .fonts = undefined,
        .ui_ctx = undefined,
    };
    state.initResources(&pctx);
    defer state.deinitResources();

    const build_idx = state.findWorkspaceFileIndexByPath("build.zig") orelse 0;
    state.openFile(build_idx);
    try std.testing.expect(state.disk_mtime_hashes[build_idx] != 0);

    // Wait for initial async git status poller to settle and run initial frame-1 plugin discovery
    state.ui_ctx.pass = .input;
    state.pollWorkspaceWatch();
    state.git_poller.deinit();
    state.last_watch_sig = state.computeWorkspaceWatchSignature();

    // 1. Unchanged open file must return `false` from `reloadFileFromDiskIfChanged` without re-reading disk
    try std.testing.expect(!state.reloadFileFromDiskIfChanged(build_idx));
    try std.testing.expectEqual(@as(usize, 0), state.reloadModifiedOpenFiles());

    // 2. Across subsequent idle `pollWorkspaceWatch()` ticks, `dirty_rect` stays null and `needs_continuous_redraw` stays false
    state.ui_ctx.dirty_rect = null;
    state.ui_ctx.damage_list.clear();
    pctx.needs_continuous_redraw = false;
    state.last_watch_poll_ms = 1; // Force watch signature evaluation on next poll
    state.plugins.last_scan_ms = 1; // Force plugin directory mtime check on next poll
    state.pollWorkspaceWatch();
    try std.testing.expect(state.ui_ctx.dirty_rect == null);
    try std.testing.expect(!pctx.needs_continuous_redraw);

    // 3. Cached plugin search directories skip redundant `opendir` when directory mtime is unchanged
    try std.testing.expect(state.plugins.cached_search_dir_count > 0);
    state.plugins.last_scan_ms = 1;
    try std.testing.expect(!state.plugins.scanAndReloadPlugins(state, false));
}

test "EditorState: dynamic growth of workspace file slots, terminal buffers, and agent buffers without fixed capacity limits" {
    var store = platform.StateStore.init(std.testing.allocator);
    defer store.deinit();
    var snap = platform.SnapshotBuffer.init(std.testing.allocator);
    defer snap.deinit();
    var pctx = platform.PlatformContext{ .width = 1280.0, .height = 800.0 };
    pctx.bindHostStores(&store, &snap);

    const state = try std.testing.allocator.create(EditorState);
    defer std.testing.allocator.destroy(state);
    state.* = .{
        .frame_arena = std.heap.ArenaAllocator.init(std.testing.allocator),
        .fonts = undefined,
        .ui_ctx = undefined,
    };
    state.initResources(&pctx);
    defer state.deinitResources();

    // Verify EditorState struct size is compact (< 10 MB instead of > 100 MB fixed arrays)
    try std.testing.expect(@sizeOf(EditorState) < 10 * 1024 * 1024);

    // Dynamically grow workspace file slots beyond 1,200 entries and verify slice rebinding
    for (0..1200) |i| {
        var path_buf: [64]u8 = undefined;
        const rel = try std.fmt.bufPrint(&path_buf, "synthetic/dir_{d}/file_{d}.zig", .{ i / 50, i });
        state.registerDiscoveredWorkspaceFile(rel);
    }
    try std.testing.expect(state.file_count >= 1200);

    // Create 12 terminal buffers and 12 agent buffers (exceeding the old limit of 8) on top of the 1200+ file workspace
    for (0..12) |_| {
        state.createTerminalBuffer(false);
        state.createAgentBuffer(false);
    }
    try std.testing.expect(state.term_vterms.len >= 12);
    try std.testing.expect(state.agent_sessions.len >= 12);
    try std.testing.expect(state.findBufferIndexByReloadKey("*terminal-12*") != null);
    try std.testing.expect(state.findBufferIndexByReloadKey("*agent-12*") != null);
}



