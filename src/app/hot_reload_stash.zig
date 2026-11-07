//! Hot-reload state preservation (`onBeforeReload` / `onAfterReload`) for `EditorState`.
//!
//! Preserves live PTY-backed `VTerm` instances, Antigravity (`agy`) agent sessions,
//! special buffers (`*terminal-N*`, `*agent-N*`, previews), open buffer/tab indices,
//! custom preview payloads, and unsaved dirty buffers across `dlclose`/`dlopen` reloads.

const std = @import("std");
const ui = @import("ui");
const platform = @import("platform");
const PlatformContext = platform.PlatformContext;
const agy_client = @import("agy_client.zig");
const workspace_fs = @import("workspace_fs.zig");
const state_mod = @import("state.zig");

const EditorState = state_mod.EditorState;
const EditorDocument = state_mod.EditorDocument;
const SampleFile = state_mod.SampleFile;
const MaxEditorPanes = state_mod.MaxEditorPanes;
const MaxTabsPerPane = state_mod.MaxTabsPerPane;
const MaxOpenBuffers = state_mod.MaxOpenBuffers;
const MaxTerminalBuffers = state_mod.MaxTerminalBuffers;
const MaxAgentBuffers = state_mod.MaxAgentBuffers;
const MaxWorkspaceFiles = state_mod.MaxWorkspaceFiles;
const posix_dir = workspace_fs.posix_dir;
const isDirectoryOnDisk = workspace_fs.isDirectoryOnDisk;

pub const HotReloadStashCapacity: usize = 16384;
pub const MaxSpecialBuffers: usize = 24;
pub const HotReloadPaneGroup = ui.PaneTabGroup(MaxTabsPerPane);

pub const HotReloadSpecialKind = enum(u8) {
    none = 0,
    terminal,
    agent,
    markdown_preview,
    bound_markdown_preview,
    waveform_preview,
    pdf_preview,
    git_diff_preview,
    app_preview,
};

pub const HotReloadSpecialEntry = struct {
    kind: HotReloadSpecialKind = .none,
    slot: u16 = 0,
    name: platform.InlineString(64) = .{},
    path: platform.InlineString(256) = .{},
    language: ui.CodeLanguage = .plain,
};

pub const HotReloadStashMeta = struct {
    dirty_count: usize = 0,
    open_state_count: usize = 0,
    scratch_dirty: bool = false,
    scratch_word_wrap: bool = false,

    // Special buffer registrations (`*terminal-N*`, `*agent-N*`, `*Markdown Preview*`, `*Waveform Preview*`, `*PDF Preview*`, `*Git Diff*`)
    special_entries: [MaxSpecialBuffers]HotReloadSpecialEntry = @splat(.{}),
    special_count: usize = 0,

    // Stable path/name-based open buffer list & split-pane tab groups so index shifts across reload never drop or scramble tabs
    open_buffer_keys: [MaxOpenBuffers]platform.InlineString(256) = @splat(.{}),
    open_buffer_count: usize = 0,
    has_open_buffers: bool = false,

    pane_tab_keys: [MaxEditorPanes][MaxTabsPerPane]platform.InlineString(256) = @splat(@splat(.{})),
    pane_tab_counts: [MaxEditorPanes]u8 = @splat(0),
    pane_active_tabs: [MaxEditorPanes]u8 = @splat(0),
    has_pane_tabs: bool = false,

    // Preview source buffer keys (`md_source_idx`, `waveform_source_idx`, `pdf_source_idx`, `git_diff_source_idx`)
    md_source_key: platform.InlineString(256) = .{},
    waveform_source_key: platform.InlineString(256) = .{},
    pdf_source_key: platform.InlineString(256) = .{},
    git_diff_source_key: platform.InlineString(256) = .{},

    // Bottom terminal & terminal buffer slots
    has_bottom_vterm: bool = false,
    term_slot_count: usize = 0,
    next_term_number: u16 = 1,

    // Antigravity (`agy`) main side-panel & `*agent-N*` buffer slots
    has_agy_main: bool = false,
    agy_prompt: platform.InlineString(8192) = .{},
    agent_slot_count: usize = 0,
    next_agent_number: u16 = 1,

    // Custom preview payloads & view states across panes
    waveform_custom_vcd: platform.InlineString(4096) = .{},
    pdf_custom_path: platform.InlineString(256) = .{},
    pdf_custom_bytes: platform.InlineString(4096) = .{},
    pdf_views: [MaxEditorPanes]ui.PdfViewState = @splat(.{}),
    image_views: [MaxEditorPanes]ui.ImageViewState = @splat(.{}),
    audio_views: [MaxEditorPanes]ui.AudioPlayerState = @splat(.{}),
    video_views: [MaxEditorPanes]ui.VideoPlayerState = @splat(.{}),
    git_diff_custom_text: platform.InlineString(16384) = .{},
    git_diff_custom_path: platform.InlineString(128) = .{},
    git_diff_title: platform.InlineString(128) = .{},
    git_diff_commit: platform.InlineString(16) = .{},
    git_diff_views: [MaxEditorPanes]ui.DiffViewState = @splat(.{}),
    app_custom_path: platform.InlineString(256) = .{},
    app_presets: [MaxEditorPanes]ui.DevicePreset = @splat(.ipad_air_11),
    app_orientations: [MaxEditorPanes]ui.Orientation = @splat(.portrait),
    app_zoom_fits: [MaxEditorPanes]bool = @splat(true),

    focused_id: ui.WidgetId = 0,
};

pub const HotReloadBufferEntry = struct {
    path: platform.InlineString(256) = .{},
    content: platform.InlineString(HotReloadStashCapacity) = .{},
    cursor: usize = 0,
    selection_anchor: usize = 0,
    scroll_state: ui.ScrollState = .{},
    word_wrap: u8 = 0,
    edit_version: u32 = 1,
    saved_version: u32 = 1,
    loaded_from_disk: bool = false,
    is_dirty: bool = false,
};

pub fn bufferReloadKey(wf: SampleFile) []const u8 {
    if (wf.isSpecial()) return wf.name;
    return wf.path;
}

pub fn findBufferIndexByReloadKey(self: *const EditorState, key: []const u8) ?usize {
    if (key.len == 0) return null;
    for (0..self.file_count) |i| {
        const wf = self.files[i];
        if (wf.isSpecial()) {
            if (std.mem.eql(u8, wf.name, key)) return i;
        } else {
            if (std.mem.eql(u8, wf.path, key)) return i;
        }
    }
    return self.findWorkspaceFileIndexByPath(key);
}

pub fn restoreSpecialBufferSlot(self: *EditorState, sp: HotReloadSpecialEntry) ?usize {
    const name_slice = sp.name.slice();
    if (name_slice.len == 0) return null;
    if (findBufferIndexByReloadKey(self, name_slice)) |existing_idx| {
        switch (sp.kind) {
            .terminal => {
                self.files[existing_idx].is_terminal = true;
                self.files[existing_idx].terminal_slot = sp.slot;
            },
            .agent => {
                self.files[existing_idx].is_agent = true;
                self.files[existing_idx].agent_slot = sp.slot;
            },
            .markdown_preview => self.files[existing_idx].is_markdown_preview = true,
            .bound_markdown_preview => {
                self.files[existing_idx].is_markdown_preview = true;
                self.files[existing_idx].is_bound_markdown_preview = true;
                self.file_storage[existing_idx].custom_name.set(name_slice);
                self.files[existing_idx].name = self.file_storage[existing_idx].custom_name.slice();
                const p_slice = sp.path.slice();
                if (std.mem.eql(u8, p_slice, "*scratch*")) {
                    self.files[existing_idx].md_preview_source_idx = 0xFFFF;
                } else if (self.findWorkspaceFileIndexByPath(p_slice)) |src_i| {
                    self.files[existing_idx].md_preview_source_idx = @intCast(src_i);
                }
            },
            .waveform_preview => self.files[existing_idx].is_waveform_preview = true,
            .pdf_preview => self.files[existing_idx].is_pdf_preview = true,
            .git_diff_preview => self.files[existing_idx].is_git_diff_preview = true,
            .app_preview => self.files[existing_idx].is_app_preview = true,
            .none => {},
        }
        return existing_idx;
    }

    const idx = self.file_count;
    const path_slice = if (sp.path.slice().len > 0) sp.path.slice() else name_slice;
    const is_md = (sp.kind == .markdown_preview or sp.kind == .bound_markdown_preview);
    const is_wave = (sp.kind == .waveform_preview);
    self.storeDynamicFileSlot(idx, path_slice, sp.language, is_md, is_wave, "");
    self.file_storage[idx].folder.set("*special*");
    self.files[idx].folder = self.file_storage[idx].folder.slice();

    switch (sp.kind) {
        .terminal => {
            _ = self.ensureTerminalSlot(sp.slot);
            self.files[idx].is_terminal = true;
            self.files[idx].terminal_slot = sp.slot;
            self.files[idx].name = self.file_storage[idx].path_buf[0..self.file_storage[idx].path_len];
        },
        .agent => {
            _ = self.ensureAgentSlot(sp.slot);
            self.files[idx].is_agent = true;
            self.files[idx].agent_slot = sp.slot;
            self.files[idx].name = self.file_storage[idx].path_buf[0..self.file_storage[idx].path_len];
        },
        .markdown_preview => {
            self.files[idx].is_markdown_preview = true;
            self.files[idx].name = "*Markdown Preview*";
        },
        .bound_markdown_preview => {
            self.files[idx].is_markdown_preview = true;
            self.files[idx].is_bound_markdown_preview = true;
            self.file_storage[idx].custom_name.set(name_slice);
            self.files[idx].name = self.file_storage[idx].custom_name.slice();
            if (std.mem.eql(u8, path_slice, "*scratch*")) {
                self.files[idx].md_preview_source_idx = 0xFFFF;
            } else if (self.findWorkspaceFileIndexByPath(path_slice)) |src_i| {
                self.files[idx].md_preview_source_idx = @intCast(src_i);
            }
        },
        .waveform_preview => {
            self.files[idx].is_waveform_preview = true;
            self.files[idx].name = "*Waveform Preview*";
        },
        .pdf_preview => {
            self.files[idx].is_pdf_preview = true;
            self.files[idx].name = "*PDF Preview*";
        },
        .git_diff_preview => {
            self.files[idx].is_git_diff_preview = true;
            self.files[idx].name = "*Git Diff*";
        },
        .app_preview => {
            self.files[idx].is_app_preview = true;
            self.files[idx].name = "*App Preview*";
        },
        .none => {},
    }

    const buf = self.ensureBufferSlotInit(idx);
    buf.resetWithSlice("");
    self.saved_versions[idx] = buf.edit_version;
    self.loaded_from_disk[idx] = true;
    self.disk_mtime_hashes[idx] = 0;
    self.git_file_statuses[idx] = .{};
    self.file_count = idx + 1;
    return idx;
}

pub fn onBeforeReload(self: *EditorState, ctx: *PlatformContext) void {
    self.ui_ctx.platform_ctx = ctx;
    var scope = self.ui_ctx.scopedState("editor_hot_reload_stash");
    defer scope.end();

    const meta = self.ui_ctx.useState(HotReloadStashMeta, "meta", .{});
    meta.* = .{};

    // 1. Preserve live PTY-backed VTerm instances (bottom panel + `*terminal-N*` buffers) across hot-reload
    // by transferring ownership of their `master_fd` and `child_pid` into `StateStore` so `deinitResources()`
    // does not close the PTY descriptors or send SIGHUP to running shell processes.
    meta.has_bottom_vterm = true;
    const bottom_vt_stash = self.ui_ctx.useState(ui.VTerm, "vterm_bottom", .{});
    bottom_vt_stash.* = self.vterm;
    self.vterm.master_fd = -1;
    self.vterm.child_pid = -1;
    self.vterm.win_hpc = null;
    self.vterm.win_in_write = null;
    self.vterm.win_out_read = null;
    self.vterm.win_proc = null;

    meta.term_slot_count = self.term_slot_used.len;
    meta.next_term_number = self.next_term_number;
    for (0..self.term_slot_used.len) |t_i| {
        var used_key_buf: [32]u8 = undefined;
        if (std.fmt.bufPrint(&used_key_buf, "term_used_{d}", .{t_i})) |used_key| {
            const used_stash = self.ui_ctx.useState(bool, used_key, false);
            used_stash.* = self.term_slot_used[t_i];
        } else |_| {}
        if (self.term_slot_used[t_i]) {
            var vt_key_buf: [32]u8 = undefined;
            if (std.fmt.bufPrint(&vt_key_buf, "vterm_slot_{d}", .{t_i})) |vt_key| {
                const slot_vt_stash = self.ui_ctx.useState(ui.VTerm, vt_key, .{});
                slot_vt_stash.* = self.term_vterms[t_i];
                self.term_vterms[t_i].master_fd = -1;
                self.term_vterms[t_i].child_pid = -1;
                self.term_vterms[t_i].win_hpc = null;
                self.term_vterms[t_i].win_in_write = null;
                self.term_vterms[t_i].win_out_read = null;
                self.term_vterms[t_i].win_proc = null;
            } else |_| {}
        }
    }

    // 2. Preserve Antigravity (`agy`) main side-panel and `*agent-N*` buffer sessions & prompts.
    // Call `deinit()` first to close any transient non-blocking socket and free temporary `tx_buf`/`rx_buf`
    // heap buffers while keeping the entire value-copied conversation transcript, entries, models, and CSRF state.
    meta.has_agy_main = true;
    meta.agy_prompt = self.agy_prompt;
    self.agy.deinit();
    self.agy.tx_buf = .empty;
    self.agy.rx_buf = .empty;
    self.agy.json_scratch = .empty;
    const agy_main_stash = self.ui_ctx.useState(agy_client.AgySession, "agy_main", .{});
    agy_main_stash.* = self.agy;

    meta.agent_slot_count = self.agent_slot_used.len;
    meta.next_agent_number = self.next_agent_number;
    for (0..self.agent_slot_used.len) |a_i| {
        var used_key_buf: [32]u8 = undefined;
        if (std.fmt.bufPrint(&used_key_buf, "agy_used_{d}", .{a_i})) |used_key| {
            const used_stash = self.ui_ctx.useState(bool, used_key, false);
            used_stash.* = self.agent_slot_used[a_i];
        } else |_| {}
        var prompt_key_buf: [32]u8 = undefined;
        if (std.fmt.bufPrint(&prompt_key_buf, "agy_prompt_{d}", .{a_i})) |prompt_key| {
            const prompt_stash = self.ui_ctx.useState(platform.InlineString(8192), prompt_key, .{});
            prompt_stash.* = self.agent_prompts[a_i];
        } else |_| {}
        if (self.agent_slot_used[a_i]) {
            self.agent_sessions[a_i].deinit();
            self.agent_sessions[a_i].tx_buf = .empty;
            self.agent_sessions[a_i].rx_buf = .empty;
            self.agent_sessions[a_i].json_scratch = .empty;
            var ag_key_buf: [32]u8 = undefined;
            if (std.fmt.bufPrint(&ag_key_buf, "agy_slot_{d}", .{a_i})) |ag_key| {
                const slot_ag_stash = self.ui_ctx.useState(agy_client.AgySession, ag_key, .{});
                slot_ag_stash.* = self.agent_sessions[a_i];
            } else |_| {}
        }
    }

    // 3. Record all special buffers (`*terminal-N*`, `*agent-N*`, `*Markdown Preview*`, `*Waveform Preview*`,
    // `*PDF Preview*`, `*Git Diff*`) so they are recreated in `self.files` after workspace rescan.
    var special_count: usize = 0;
    for (0..self.file_count) |idx| {
        if (special_count >= MaxSpecialBuffers) break;
        const wf = self.files[idx];
        if (!wf.isSpecial()) continue;
        var kind: HotReloadSpecialKind = .none;
        var slot: u16 = 0;
        if (wf.is_terminal) {
            kind = .terminal;
            slot = wf.terminal_slot;
        } else if (wf.is_agent) {
            kind = .agent;
            slot = wf.agent_slot;
        } else if (wf.is_bound_markdown_preview) {
            kind = .bound_markdown_preview;
        } else if (wf.is_markdown_preview) {
            kind = .markdown_preview;
        } else if (wf.is_waveform_preview) {
            kind = .waveform_preview;
        } else if (wf.is_pdf_preview) {
            kind = .pdf_preview;
        } else if (wf.is_git_diff_preview) {
            kind = .git_diff_preview;
        } else if (wf.is_app_preview) {
            kind = .app_preview;
        }
        if (kind == .none) continue;

        var sp_entry = HotReloadSpecialEntry{
            .kind = kind,
            .slot = slot,
            .language = wf.language,
        };
        sp_entry.name.set(wf.name);
        sp_entry.path.set(wf.path);
        meta.special_entries[special_count] = sp_entry;
        special_count += 1;
    }
    meta.special_count = special_count;

    // 4. Record stable keys for `open_buffers`, `panes[p].tabs`, and preview source indices
    // so that special buffers and any index changes on disk never drop or scramble open tabs.
    meta.has_open_buffers = true;
    var ob_count: usize = 0;
    const max_ob = @min(self.doc.open_buffer_count, MaxOpenBuffers);
    for (0..max_ob) |ob_i| {
        const f_idx = self.doc.open_buffers[ob_i];
        if (f_idx < self.file_count) {
            const bkey = bufferReloadKey(self.files[f_idx]);
            if (bkey.len > 0) {
                meta.open_buffer_keys[ob_count].set(bkey);
                ob_count += 1;
            }
        }
    }
    meta.open_buffer_count = ob_count;

    meta.has_pane_tabs = true;
    for (0..MaxEditorPanes) |p_i| {
        const pane = &self.doc.panes[p_i];
        var pt_count: u8 = 0;
        var remapped_active: u8 = 0;
        const max_t = @min(@as(usize, pane.tab_count), MaxTabsPerPane);
        for (0..max_t) |t_i| {
            const f_idx: usize = pane.tabs[t_i];
            if (f_idx < self.file_count) {
                const bkey = bufferReloadKey(self.files[f_idx]);
                if (bkey.len > 0) {
                    if (t_i == pane.active_tab) {
                        remapped_active = pt_count;
                    }
                    meta.pane_tab_keys[p_i][pt_count].set(bkey);
                    pt_count += 1;
                }
            }
        }
        meta.pane_tab_counts[p_i] = pt_count;
        meta.pane_active_tabs[p_i] = if (pt_count > 0) @min(remapped_active, pt_count - 1) else 0;
    }

    if (self.doc.md_preview_source_idx < self.file_count) {
        meta.md_source_key.set(bufferReloadKey(self.files[self.doc.md_preview_source_idx]));
    }
    if (self.doc.waveform_preview_source_idx < self.file_count) {
        meta.waveform_source_key.set(bufferReloadKey(self.files[self.doc.waveform_preview_source_idx]));
    }
    if (self.doc.pdf_preview_source_idx < self.file_count) {
        meta.pdf_source_key.set(bufferReloadKey(self.files[self.doc.pdf_preview_source_idx]));
    }
    if (self.doc.git_diff_source_idx < self.file_count) {
        meta.git_diff_source_key.set(bufferReloadKey(self.files[self.doc.git_diff_source_idx]));
    }

    // 5. Preserve custom preview payloads, view states, and focused widget ID
    meta.waveform_custom_vcd = self.waveform_custom_vcd;
    meta.pdf_custom_path = self.pdf_custom_path;
    meta.pdf_custom_bytes = self.pdf_custom_bytes;
    meta.pdf_views = self.pdf_views;
    meta.image_views = self.image_views;
    meta.audio_views = self.audio_views;
    // Clear ObjC generator handles before copying so the stash snapshot never
    // holds raw ARC-managed pointers that may be freed during dlclose/dlopen.
    for (0..MaxEditorPanes) |vp| {
        self.video_views[vp].clearNativeHandles();
    }
    meta.video_views = self.video_views;
    meta.git_diff_custom_text = self.git_diff_custom_text;
    meta.git_diff_custom_path = self.git_diff_custom_path;
    meta.git_diff_title = self.git_diff_title;
    meta.git_diff_commit = self.git_diff_commit;
    meta.git_diff_views = self.git_diff_views;
    meta.app_custom_path = self.app_custom_path;
    for (0..MaxEditorPanes) |p| {
        meta.app_presets[p] = self.app_views[p].preset;
        meta.app_orientations[p] = self.app_views[p].orientation;
        meta.app_zoom_fits[p] = self.app_views[p].zoom_fit;
    }
    meta.focused_id = self.ui_ctx.focused_id;
    meta.scratch_word_wrap = self.scratch_word_wrap;

    // 6. Preserve dirty buffers AND cursor/scroll/word-wrap state of open buffers
    var dirty_count: usize = 0;
    var open_state_count: usize = 0;

    for (0..self.file_count) |idx| {
        if (!self.buffer_initialized[idx]) continue;
        const wf = self.files[idx];
        const bkey = bufferReloadKey(wf);
        if (bkey.len == 0) continue;

        const is_dirty = !wf.isSpecial() and self.isFileDirty(idx);
        const is_open = self.isBufferOpen(idx);
        if (!is_dirty and !is_open) continue;

        if (is_dirty and dirty_count < MaxOpenBuffers) {
            var key_buf: [32]u8 = undefined;
            const key = std.fmt.bufPrint(&key_buf, "dirty_buf_{d}", .{dirty_count}) catch continue;
            const entry = self.ui_ctx.useState(HotReloadBufferEntry, key, .{});
            entry.path.set(bkey);
            entry.content.set(self.buffers[idx].slice());
            entry.cursor = self.buffers[idx].cursor;
            entry.selection_anchor = self.buffers[idx].selection_anchor;
            entry.scroll_state = self.buffers[idx].scroll_state;
            entry.word_wrap = self.buffer_word_wrap[idx];
            entry.edit_version = self.buffers[idx].edit_version;
            entry.saved_version = self.saved_versions[idx];
            entry.loaded_from_disk = self.loaded_from_disk[idx];
            entry.is_dirty = true;
            dirty_count += 1;
        } else if (is_open and open_state_count < MaxOpenBuffers) {
            var key_buf: [32]u8 = undefined;
            const key = std.fmt.bufPrint(&key_buf, "open_buf_{d}", .{open_state_count}) catch continue;
            const entry = self.ui_ctx.useState(HotReloadBufferEntry, key, .{});
            entry.path.set(bkey);
            entry.content.clear();
            entry.cursor = self.buffers[idx].cursor;
            entry.selection_anchor = self.buffers[idx].selection_anchor;
            entry.scroll_state = self.buffers[idx].scroll_state;
            entry.word_wrap = self.buffer_word_wrap[idx];
            entry.edit_version = self.buffers[idx].edit_version;
            entry.saved_version = self.saved_versions[idx];
            entry.loaded_from_disk = self.loaded_from_disk[idx];
            entry.is_dirty = false;
            open_state_count += 1;
        }
    }

    meta.dirty_count = dirty_count;
    meta.open_state_count = open_state_count;
    if (self.isScratchDirty() or self.scratch_buf.cursor > 0) {
        meta.scratch_dirty = self.isScratchDirty();
        const scratch_entry = self.ui_ctx.useState(HotReloadBufferEntry, "dirty_scratch", .{});
        scratch_entry.path.set("*scratch*");
        scratch_entry.content.set(self.scratch_buf.slice());
        scratch_entry.cursor = self.scratch_buf.cursor;
        scratch_entry.selection_anchor = self.scratch_buf.selection_anchor;
        scratch_entry.scroll_state = self.scratch_buf.scroll_state;
        scratch_entry.edit_version = self.scratch_buf.edit_version;
        scratch_entry.saved_version = self.scratch_saved_version;
        scratch_entry.loaded_from_disk = false;
        scratch_entry.is_dirty = self.isScratchDirty();
    } else {
        meta.scratch_dirty = false;
    }
}

pub fn onAfterReload(self: *EditorState) void {
    if (self.doc.workspace_root_len > 0) {
        var dir_z: [256:0]u8 = @splat(0);
        const len: usize = @min(@as(usize, self.doc.workspace_root_len), 255);
        @memcpy(dir_z[0..len], self.doc.workspace_root_buf[0..len]);
        dir_z[len] = 0;
        if (isDirectoryOnDisk(&dir_z)) {
            _ = posix_dir.chdir(&dir_z);
        }
    }
    self.syncWorkspaceRootFromCwd();
    self.cached_symbol_file = std.math.maxInt(usize);
    self.cached_diag_file = std.math.maxInt(usize);
    self.refreshWorkspaceFiles(false);
    self.agy.syncWorkspaceRoot(self.workspaceRoot());

    if (self.ui_ctx.platform_ctx != null) {
        var scope = self.ui_ctx.scopedState("editor_hot_reload_stash");
        defer scope.end();

        const meta = self.ui_ctx.useState(HotReloadStashMeta, "meta", .{});

        // 1. Restore live PTY-backed VTerm instances (bottom panel + `*terminal-N*` buffers)
        if (meta.has_bottom_vterm) {
            const bottom_vt_stash = self.ui_ctx.useState(ui.VTerm, "vterm_bottom", .{});
            self.vterm.deinit();
            self.vterm = bottom_vt_stash.*;
            bottom_vt_stash.master_fd = -1;
            bottom_vt_stash.child_pid = -1;
            meta.has_bottom_vterm = false;
        }
        self.next_term_number = @max(@as(u16, 1), meta.next_term_number);
        if (meta.term_slot_count > 0) {
            _ = self.ensureTerminalSlot(meta.term_slot_count - 1);
        }
        for (0..meta.term_slot_count) |t_i| {
            var used = false;
            var used_key_buf: [32]u8 = undefined;
            if (std.fmt.bufPrint(&used_key_buf, "term_used_{d}", .{t_i})) |used_key| {
                used = self.ui_ctx.useState(bool, used_key, false).*;
            } else |_| {}
            self.term_slot_used[t_i] = used;
            if (used) {
                var vt_key_buf: [32]u8 = undefined;
                if (std.fmt.bufPrint(&vt_key_buf, "vterm_slot_{d}", .{t_i})) |vt_key| {
                    const slot_vt_stash = self.ui_ctx.useState(ui.VTerm, vt_key, .{});
                    self.term_vterms[t_i].deinit();
                    self.term_vterms[t_i] = slot_vt_stash.*;
                    slot_vt_stash.master_fd = -1;
                    slot_vt_stash.child_pid = -1;
                    slot_vt_stash.win_hpc = null;
                    slot_vt_stash.win_in_write = null;
                    slot_vt_stash.win_out_read = null;
                    slot_vt_stash.win_proc = null;
                } else |_| {}
            }
        }

        // 2. Restore Antigravity (`agy`) main side-panel and `*agent-N*` buffer sessions & prompts
        if (meta.has_agy_main) {
            const agy_main_stash = self.ui_ctx.useState(agy_client.AgySession, "agy_main", .{});
            const fresh_ls_port = self.agy.ls_port;
            const fresh_alt_port = self.agy.alt_port;
            const fresh_csrf_buf = self.agy.csrf_buf;
            const fresh_csrf_len = self.agy.csrf_len;
            self.agy.deinit();
            self.agy = agy_main_stash.*;
            self.agy.tx_buf = .empty;
            self.agy.rx_buf = .empty;
            self.agy.json_scratch = .empty;
            if (fresh_ls_port != 0 and fresh_csrf_len > 0) {
                self.agy.ls_port = fresh_ls_port;
                self.agy.alt_port = fresh_alt_port;
                self.agy.csrf_buf = fresh_csrf_buf;
                self.agy.csrf_len = fresh_csrf_len;
            }
            self.agy.syncWorkspaceRoot(self.workspaceRoot());
            self.agy_prompt = meta.agy_prompt;
            meta.has_agy_main = false;
        }

        self.next_agent_number = @max(@as(u16, 1), meta.next_agent_number);
        if (meta.agent_slot_count > 0) {
            _ = self.ensureAgentSlot(meta.agent_slot_count - 1);
        }
        for (0..meta.agent_slot_count) |a_i| {
            var used = false;
            var used_key_buf: [32]u8 = undefined;
            if (std.fmt.bufPrint(&used_key_buf, "agy_used_{d}", .{a_i})) |used_key| {
                used = self.ui_ctx.useState(bool, used_key, false).*;
            } else |_| {}
            self.agent_slot_used[a_i] = used;
            var prompt_key_buf: [32]u8 = undefined;
            if (std.fmt.bufPrint(&prompt_key_buf, "agy_prompt_{d}", .{a_i})) |prompt_key| {
                self.agent_prompts[a_i] = self.ui_ctx.useState(platform.InlineString(8192), prompt_key, .{}).*;
            } else |_| {}
            if (used) {
                var ag_key_buf: [32]u8 = undefined;
                if (std.fmt.bufPrint(&ag_key_buf, "agy_slot_{d}", .{a_i})) |ag_key| {
                    const slot_ag_stash = self.ui_ctx.useState(agy_client.AgySession, ag_key, .{});
                    self.agent_sessions[a_i].deinit();
                    self.agent_sessions[a_i] = slot_ag_stash.*;
                    self.agent_sessions[a_i].tx_buf = .empty;
                    self.agent_sessions[a_i].rx_buf = .empty;
                    self.agent_sessions[a_i].json_scratch = .empty;
                    if (self.agy.ls_port != 0 and self.agy.csrf_len > 0) {
                        self.agent_sessions[a_i].ls_port = self.agy.ls_port;
                        self.agent_sessions[a_i].alt_port = self.agy.alt_port;
                        self.agent_sessions[a_i].csrf_buf = self.agy.csrf_buf;
                        self.agent_sessions[a_i].csrf_len = self.agy.csrf_len;
                    }
                    self.agent_sessions[a_i].syncWorkspaceRoot(self.workspaceRoot());
                } else |_| {}
            }
        }

        // 3. Recreate all special buffers (`*terminal-N*`, `*agent-N*`, previews) in `self.files`
        const sp_count = @min(meta.special_count, MaxSpecialBuffers);
        for (0..sp_count) |sp_i| {
            _ = restoreSpecialBufferSlot(self, meta.special_entries[sp_i]);
        }
        meta.special_count = 0;

        // 4. Remap `open_buffers`, `panes[p].tabs`, and preview source indices by stable buffer keys
        if (meta.has_open_buffers) {
            var new_ob_count: usize = 0;
            const max_ob = @min(meta.open_buffer_count, MaxOpenBuffers);
            for (0..max_ob) |ob_i| {
                const bkey = meta.open_buffer_keys[ob_i].slice();
                if (findBufferIndexByReloadKey(self, bkey)) |f_idx| {
                    var dup = false;
                    for (0..new_ob_count) |k| {
                        if (self.doc.open_buffers[k] == f_idx) {
                            dup = true;
                            break;
                        }
                    }
                    if (!dup and new_ob_count < MaxOpenBuffers) {
                        self.doc.open_buffers[new_ob_count] = @intCast(f_idx);
                        new_ob_count += 1;
                    }
                }
            }
            self.doc.open_buffer_count = @intCast(new_ob_count);
            meta.has_open_buffers = false;
        }

        if (meta.has_pane_tabs) {
            for (0..MaxEditorPanes) |p_i| {
                const pt_count = @min(@as(usize, meta.pane_tab_counts[p_i]), MaxTabsPerPane);
                const saved_active = meta.pane_active_tabs[p_i];
                var new_tabs = HotReloadPaneGroup{};
                var new_active: u8 = 0;
                for (0..pt_count) |t_i| {
                    const bkey = meta.pane_tab_keys[p_i][t_i].slice();
                    if (findBufferIndexByReloadKey(self, bkey)) |f_idx| {
                        if (t_i == saved_active) {
                            new_active = new_tabs.tab_count;
                        }
                        if (new_tabs.tab_count < MaxTabsPerPane) {
                            new_tabs.tabs[new_tabs.tab_count] = @intCast(f_idx);
                            new_tabs.tab_count += 1;
                        }
                    }
                }
                if (new_tabs.tab_count > 0) {
                    new_tabs.active_tab = @min(new_active, new_tabs.tab_count - 1);
                }
                self.doc.panes[p_i] = new_tabs;
            }
            meta.has_pane_tabs = false;
        }

        if (meta.md_source_key.slice().len > 0) {
            if (findBufferIndexByReloadKey(self, meta.md_source_key.slice())) |idx| {
                self.doc.md_preview_source_idx = @intCast(idx);
            }
        }
        if (meta.waveform_source_key.slice().len > 0) {
            if (findBufferIndexByReloadKey(self, meta.waveform_source_key.slice())) |idx| {
                self.doc.waveform_preview_source_idx = @intCast(idx);
            }
        }
        if (meta.pdf_source_key.slice().len > 0) {
            if (findBufferIndexByReloadKey(self, meta.pdf_source_key.slice())) |idx| {
                self.doc.pdf_preview_source_idx = @intCast(idx);
            }
        }
        if (meta.git_diff_source_key.slice().len > 0) {
            if (findBufferIndexByReloadKey(self, meta.git_diff_source_key.slice())) |idx| {
                self.doc.git_diff_source_idx = @intCast(idx);
            }
        }

        // 5. Restore custom preview payloads, view states, and focused widget ID
        self.waveform_custom_vcd = meta.waveform_custom_vcd;
        self.pdf_custom_path = meta.pdf_custom_path;
        self.pdf_custom_bytes = meta.pdf_custom_bytes;
        self.pdf_views = meta.pdf_views;
        self.image_views = meta.image_views;
        self.audio_views = meta.audio_views;
        // Defensively clear ObjC handles on the restored copy so the new
        // dylib never dereferences a pointer from the unloaded old image.
        self.video_views = meta.video_views;
        for (0..MaxEditorPanes) |vp| {
            self.video_views[vp].clearNativeHandles();
        }
        self.git_diff_custom_text = meta.git_diff_custom_text;
        self.git_diff_custom_path = meta.git_diff_custom_path;
        self.git_diff_title = meta.git_diff_title;
        self.git_diff_commit = meta.git_diff_commit;
        self.git_diff_views = meta.git_diff_views;
        self.app_custom_path = meta.app_custom_path;
        for (0..MaxEditorPanes) |p| {
            self.app_views[p].preset = meta.app_presets[p];
            self.app_views[p].orientation = meta.app_orientations[p];
            self.app_views[p].zoom_fit = meta.app_zoom_fits[p];
            if (self.app_custom_path.slice().len > 0) {
                self.app_views[p].setDylibPath(self.app_custom_path.slice());
            }
        }
        self.scratch_word_wrap = meta.scratch_word_wrap;
        if (meta.focused_id != 0) {
            self.ui_ctx.focused_id = meta.focused_id;
        }

        // 6. Restore dirty buffers and open buffer cursor/scroll/word-wrap states
        const count = @min(meta.dirty_count, MaxOpenBuffers);
        for (0..count) |slot_i| {
            var key_buf: [32]u8 = undefined;
            const key = std.fmt.bufPrint(&key_buf, "dirty_buf_{d}", .{slot_i}) catch continue;
            const entry = self.ui_ctx.useState(HotReloadBufferEntry, key, .{});
            const rel_path = entry.path.slice();
            if (rel_path.len == 0) continue;
            if (findBufferIndexByReloadKey(self, rel_path)) |f_idx| {
                const buf = self.ensureBufferSlotInit(f_idx);
                buf.resetWithSlice(entry.content.slice());
                buf.cursor = @min(entry.cursor, buf.len);
                buf.selection_anchor = @min(entry.selection_anchor, buf.len);
                buf.scroll_state = entry.scroll_state;
                self.buffer_word_wrap[f_idx] = entry.word_wrap;
                self.saved_versions[f_idx] = entry.saved_version;
                if (entry.edit_version != entry.saved_version) {
                    buf.edit_version = entry.edit_version;
                } else {
                    buf.edit_version = entry.saved_version +% 1;
                    if (buf.edit_version == 0) buf.edit_version = 1;
                }
                self.loaded_from_disk[f_idx] = entry.loaded_from_disk;
            }
        }

        const open_count = @min(meta.open_state_count, MaxOpenBuffers);
        for (0..open_count) |slot_i| {
            var key_buf: [32]u8 = undefined;
            const key = std.fmt.bufPrint(&key_buf, "open_buf_{d}", .{slot_i}) catch continue;
            const entry = self.ui_ctx.useState(HotReloadBufferEntry, key, .{});
            const rel_path = entry.path.slice();
            if (rel_path.len == 0) continue;
            if (findBufferIndexByReloadKey(self, rel_path)) |f_idx| {
                if (!self.loaded_from_disk[f_idx] and !self.files[f_idx].isSpecial()) {
                    self.loadFileFromDiskOrFallback(f_idx);
                }
                const buf = self.ensureBufferSlotInit(f_idx);
                buf.cursor = @min(entry.cursor, buf.len);
                buf.selection_anchor = @min(entry.selection_anchor, buf.len);
                buf.scroll_state = entry.scroll_state;
                self.buffer_word_wrap[f_idx] = entry.word_wrap;
            }
        }

        if (meta.scratch_dirty) {
            const scratch_entry = self.ui_ctx.useState(HotReloadBufferEntry, "dirty_scratch", .{});
            self.scratch_buf.resetWithSlice(scratch_entry.content.slice());
            self.scratch_buf.cursor = @min(scratch_entry.cursor, self.scratch_buf.len);
            self.scratch_buf.selection_anchor = @min(scratch_entry.selection_anchor, self.scratch_buf.len);
            self.scratch_buf.scroll_state = scratch_entry.scroll_state;
            self.scratch_saved_version = scratch_entry.saved_version;
            if (scratch_entry.edit_version != scratch_entry.saved_version) {
                self.scratch_buf.edit_version = scratch_entry.edit_version;
            } else {
                self.scratch_buf.edit_version = scratch_entry.saved_version +% 1;
                if (self.scratch_buf.edit_version == 0) self.scratch_buf.edit_version = 1;
            }
        }
        meta.dirty_count = 0;
        meta.open_state_count = 0;
        meta.scratch_dirty = false;
    }
}

test "EditorState: lazy CodeEditorBuffer initialization and hot-reload dirty buffer preservation (onBeforeReload -> onAfterReload)" {
    var store = platform.StateStore.init(std.testing.allocator);
    defer store.deinit();
    var snap = platform.SnapshotBuffer.init(std.testing.allocator);
    defer snap.deinit();
    var pctx = platform.PlatformContext{ .width = 1280.0, .height = 800.0 };
    pctx.bindHostStores(&store, &snap);

    const state_before = try std.testing.allocator.create(EditorState);
    defer std.testing.allocator.destroy(state_before);
    state_before.* = .{
        .frame_arena = std.heap.ArenaAllocator.init(std.testing.allocator),
        .fonts = undefined,
        .ui_ctx = undefined,
    };
    state_before.initResources(&pctx);
    defer state_before.deinitResources();

    // 1. Verify lazy buffer initialization: slots in `0..file_count` are initialized
    try std.testing.expect(state_before.file_count > 0);
    try std.testing.expectEqual(state_before.file_count, state_before.buffer_initialized.len);
    for (0..state_before.file_count) |i| {
        try std.testing.expect(state_before.buffer_initialized[i]);
    }

    // 2. Open a file and make an unsaved edit, plus edit the scratch buffer
    const target_idx = state_before.findWorkspaceFileIndexByPath("build.zig") orelse 0;
    state_before.openFile(target_idx);
    const unsaved_text = "// UNSAVED_HOT_RELOAD_EDIT_MARKER\npub fn build() void {}\n";
    state_before.buffers[target_idx].resetWithSlice(unsaved_text);
    state_before.buffers[target_idx].cursor = 12;
    state_before.buffers[target_idx].selection_anchor = 4;
    try std.testing.expect(state_before.isFileDirty(target_idx));

    state_before.scratch_buf.resetWithSlice("scratch notes across reload");
    state_before.scratch_buf.cursor = 7;
    try std.testing.expect(state_before.isScratchDirty());

    // 2b. Create a `*terminal-1*` buffer (with terminal grid output), an `*agent-1*` buffer (with prompt),
    // and open `*Markdown Preview*` in a split pane to verify special buffers survive hot-reload.
    state_before.createTerminalBuffer(false);
    const term_before_idx = state_before.findBufferIndexByReloadKey("*terminal-1*") orelse return error.MissingTerminalBuffer;
    try std.testing.expect(state_before.files[term_before_idx].is_terminal);
    const term_slot = state_before.files[term_before_idx].terminal_slot;
    state_before.term_vterms[term_slot].feedBytes("HOT_RELOAD_TERMINAL_SURVIVED\r\n");

    state_before.createAgentBuffer(true);
    const agent_before_idx = state_before.findBufferIndexByReloadKey("*agent-1*") orelse return error.MissingAgentBuffer;
    try std.testing.expect(state_before.files[agent_before_idx].is_agent);
    const agent_slot = state_before.files[agent_before_idx].agent_slot;
    state_before.agent_prompts[agent_slot].set("draft agent prompt across hot reload");

    state_before.openMarkdownPreviewBuffer(false);
    try std.testing.expect(state_before.findBufferIndexByReloadKey("*Markdown Preview*") != null);

    // 3. Simulate `app_before_reload` (`onBeforeReload` + `saveSnapshotJson`)
    state_before.onBeforeReload(&pctx);
    try pctx.saveSnapshotJson(std.testing.allocator, state_before.doc);

    // 4. Simulate `app_on_reload` on a freshly allocated EditorState sharing the host `PlatformContext` (`StateStore` + `SnapshotBuffer`)
    const state_after = try std.testing.allocator.create(EditorState);
    defer std.testing.allocator.destroy(state_after);
    state_after.* = .{
        .frame_arena = std.heap.ArenaAllocator.init(std.testing.allocator),
        .fonts = undefined,
        .ui_ctx = undefined,
    };
    state_after.initResources(&pctx);
    defer state_after.deinitResources();

    if (pctx.loadSnapshotJson(EditorDocument, std.testing.allocator)) |restored_doc| {
        state_after.doc = restored_doc;
    }
    state_after.onAfterReload();

    // 5. Verify unsaved buffer contents, cursor, selection, and dirty state survived hot-reload
    const restored_idx = state_after.findWorkspaceFileIndexByPath("build.zig") orelse 0;
    try std.testing.expectEqualStrings(unsaved_text, state_after.buffers[restored_idx].slice());
    try std.testing.expectEqual(@as(usize, 12), state_after.buffers[restored_idx].cursor);
    try std.testing.expectEqual(@as(usize, 4), state_after.buffers[restored_idx].selection_anchor);
    try std.testing.expect(state_after.isFileDirty(restored_idx));

    try std.testing.expectEqualStrings("scratch notes across reload", state_after.scratch_buf.slice());
    try std.testing.expectEqual(@as(usize, 7), state_after.scratch_buf.cursor);
    try std.testing.expect(state_after.isScratchDirty());

    // 6. Verify `*terminal-1*`, `*agent-1*`, and `*Markdown Preview*` buffers, VTerm screen grid,
    // agent prompt, open_buffers, and split-pane tabs survived hot-reload.
    const term_after_idx = state_after.findBufferIndexByReloadKey("*terminal-1*") orelse return error.MissingRestoredTerminalBuffer;
    try std.testing.expect(state_after.files[term_after_idx].is_terminal);
    try std.testing.expectEqual(term_slot, state_after.files[term_after_idx].terminal_slot);
    try std.testing.expect(state_after.term_slot_used[term_slot]);
    try std.testing.expectEqual(@as(u16, 2), state_after.next_term_number);
    try std.testing.expectEqual(@as(u21, 'H'), state_after.term_vterms[term_slot].grid[0][0].ch);
    try std.testing.expectEqual(@as(u21, 'O'), state_after.term_vterms[term_slot].grid[0][1].ch);
    try std.testing.expectEqual(@as(u21, 'T'), state_after.term_vterms[term_slot].grid[0][2].ch);
    try std.testing.expect(state_after.isBufferOpen(term_after_idx));

    const agent_after_idx = state_after.findBufferIndexByReloadKey("*agent-1*") orelse return error.MissingRestoredAgentBuffer;
    try std.testing.expect(state_after.files[agent_after_idx].is_agent);
    try std.testing.expectEqual(agent_slot, state_after.files[agent_after_idx].agent_slot);
    try std.testing.expect(state_after.agent_slot_used[agent_slot]);
    try std.testing.expectEqual(@as(u16, 2), state_after.next_agent_number);
    try std.testing.expectEqualStrings("draft agent prompt across hot reload", state_after.agent_prompts[agent_slot].slice());
    try std.testing.expect(state_after.isBufferOpen(agent_after_idx));

    const md_after_idx = state_after.findBufferIndexByReloadKey("*Markdown Preview*") orelse return error.MissingRestoredMarkdownPreview;
    try std.testing.expect(state_after.files[md_after_idx].is_markdown_preview);
    try std.testing.expect(state_after.isBufferOpen(md_after_idx));
    try std.testing.expectEqual(@as(usize, 2), state_after.paneCount());
}
