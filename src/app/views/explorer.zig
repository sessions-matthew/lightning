//! Primary Side Bar (236pt wide) with Explorer (File Tree + Symbol Outline),
//! Workspace Search, Plugins Browser, and dynamic plugin sidebars.

const std = @import("std");
const skia = @import("skia");
const platform = @import("platform");
const ui = @import("ui");
const state_mod = @import("../state.zig");
const EditorState = state_mod.EditorState;
const SymbolItem = state_mod.SymbolItem;

pub const ExplorerAction = struct {
    file_switched: bool = false,
};

pub const ExplorerInlineRenameState = struct {
    renaming_folder: bool = false,
    renaming_file: bool = false,
    target_folder: platform.InlineString(256) = .{},
    target_file_idx: usize = 0,
    input_buf: platform.InlineString(256) = .{},
};

fn isFolderCollapsed(state: *const EditorState, folder_path: []const u8) bool {
    return !state.isFolderExpanded(folder_path);
}

pub fn isPathVisibleInTree(state: *const EditorState, path: []const u8) bool {
    return ui.tree_view_mod.isPathVisibleInTree(path, state, isFolderCollapsed);
}

const FolderCountCache = struct {
    file_count: usize = 0,
    exact_counts: std.StringHashMapUnmanaged(usize) = .empty,
    recursive_counts: std.StringHashMapUnmanaged(usize) = .empty,

    fn build(arena: std.mem.Allocator, state: *const EditorState) *FolderCountCache {
        const wfs = state.workspaceFiles();
        const cache = arena.create(FolderCountCache) catch unreachable;
        cache.* = .{ .file_count = wfs.len };
        for (wfs) |file| {
            if (file.isSpecial()) continue;
            const folder = file.folder;
            const exact_gop = cache.exact_counts.getOrPut(arena, folder) catch unreachable;
            if (!exact_gop.found_existing) exact_gop.value_ptr.* = 0;
            exact_gop.value_ptr.* += 1;

            const rec_gop = cache.recursive_counts.getOrPut(arena, folder) catch unreachable;
            if (!rec_gop.found_existing) rec_gop.value_ptr.* = 0;
            rec_gop.value_ptr.* += 1;

            var cur = folder;
            while (ui.tree_view_mod.parentDirPath(cur)) |ancestor| : (cur = ancestor) {
                const anc_gop = cache.recursive_counts.getOrPut(arena, ancestor) catch unreachable;
                if (!anc_gop.found_existing) anc_gop.value_ptr.* = 0;
                anc_gop.value_ptr.* += 1;
            }
        }
        return cache;
    }

    fn count(self: *const FolderCountCache, prefix: []const u8, exact: bool) usize {
        if (exact) {
            return self.exact_counts.get(prefix) orelse 0;
        }
        return self.recursive_counts.get(prefix) orelse 0;
    }
};

pub fn build(
    state: *EditorState,
    active_activity: u8,
) ExplorerAction {
    const uic = &state.ui_ctx;
    var action = ExplorerAction{};

    var scope = uic.scopedState("explorer_sidebar");
    defer scope.end();

    const sidebar_w = std.math.clamp(state.doc.sidebar_width, 160.0, 420.0);
    var sidebar = uic.scrollPanel("vscode_sidebar_scroll", .{
        .w = .pixels(sidebar_w),
        .preset = .sidebar,
        .bg_color = skia.Color.rgb(18, 23, 33),
    });
    defer sidebar.end();

    switch (active_activity) {
        0 => buildExplorerView(state, &action),
        1 => buildSearchView(state, &action),
        2 => buildPluginsView(state),
        else => buildPluginSidebarView(state, active_activity - 3),
    }

    return action;
}

fn countFolderFiles(state: *EditorState, prefix: []const u8, exact: bool) usize {
    const cache = state.ui_ctx.useFrameCache(FolderCountCache, "folder_counts", state, FolderCountCache.build);
    if (cache.file_count != state.workspaceFiles().len) {
        cache.* = FolderCountCache.build(state.ui_ctx.arena, state).*;
    }
    return cache.count(prefix, exact);
}

fn fileBadgeIcon(lang: ui.CodeLanguage, is_terminal: bool, is_agent: bool, is_preview: bool, is_waveform: bool, is_pdf: bool, is_image: bool, is_git_diff: bool) struct {
    text: []const u8,
    color: u32,
    bg: u32,
} {
    if (is_agent) return .{
        .text = "✦",
        .color = skia.Color.rgb(88, 166, 255),
        .bg = skia.Color.argb(45, 56, 139, 253),
    };
    if (is_terminal) return .{
        .text = "T",
        .color = skia.Color.rgb(52, 211, 153),
        .bg = skia.Color.argb(45, 52, 211, 153),
    };
    if (is_git_diff) return .{
        .text = "D",
        .color = skia.Color.rgb(52, 211, 153),
        .bg = skia.Color.argb(45, 52, 211, 153),
    };
    if (is_waveform) return .{
        .text = "W",
        .color = skia.Color.rgb(168, 85, 247),
        .bg = skia.Color.argb(45, 168, 85, 247),
    };
    if (is_pdf) return .{
        .text = "PDF",
        .color = skia.Color.rgb(244, 63, 94),
        .bg = skia.Color.argb(45, 244, 63, 94),
    };
    if (is_image) return .{
        .text = "IMG",
        .color = skia.Color.rgb(56, 189, 248),
        .bg = skia.Color.argb(45, 56, 189, 248),
    };
    if (is_preview) return .{
        .text = "P",
        .color = skia.Color.rgb(56, 189, 248),
        .bg = skia.Color.argb(45, 56, 189, 248),
    };
    return switch (lang) {
        .zig => .{ .text = "Z", .color = skia.Color.rgb(251, 191, 36), .bg = skia.Color.argb(45, 245, 158, 11) },
        .cpp => .{ .text = "C", .color = skia.Color.rgb(96, 165, 250), .bg = skia.Color.argb(45, 96, 165, 250) },
        .java => .{ .text = "J", .color = skia.Color.rgb(248, 113, 113), .bg = skia.Color.argb(45, 248, 113, 113) },
        .go => .{ .text = "G", .color = skia.Color.rgb(34, 211, 238), .bg = skia.Color.argb(45, 34, 211, 238) },
        .systemverilog => .{ .text = "SV", .color = skia.Color.rgb(168, 85, 247), .bg = skia.Color.argb(45, 168, 85, 247) },
        .rust => .{ .text = "Rs", .color = skia.Color.rgb(251, 146, 60), .bg = skia.Color.argb(45, 251, 146, 60) },
        .python => .{ .text = "Py", .color = skia.Color.rgb(250, 204, 21), .bg = skia.Color.argb(45, 250, 204, 21) },
        .typescript => .{ .text = "TS", .color = skia.Color.rgb(59, 130, 246), .bg = skia.Color.argb(45, 59, 130, 246) },
        .vhdl => .{ .text = "VH", .color = skia.Color.rgb(168, 85, 247), .bg = skia.Color.argb(45, 168, 85, 247) },
        .chisel => .{ .text = "Ch", .color = skia.Color.rgb(244, 63, 94), .bg = skia.Color.argb(45, 244, 63, 94) },
        .devicetree => .{ .text = "DT", .color = skia.Color.rgb(52, 211, 153), .bg = skia.Color.argb(45, 52, 211, 153) },
        .markdown => .{ .text = "M", .color = skia.Color.rgb(56, 189, 248), .bg = skia.Color.argb(45, 56, 189, 248) },
        .json => .{ .text = "{}", .color = skia.Color.rgb(192, 132, 252), .bg = skia.Color.argb(45, 192, 132, 252) },
        .bash => .{ .text = "$", .color = skia.Color.rgb(52, 211, 153), .bg = skia.Color.argb(45, 52, 211, 153) },
        .plain => .{ .text = "·", .color = skia.Color.rgb(148, 163, 184), .bg = skia.Color.argb(45, 148, 163, 184) },
    };
}

fn asciiLessThanIgnoreCase(a: []const u8, b: []const u8) bool {
    const min_len = @min(a.len, b.len);
    for (0..min_len) |i| {
        const ca = std.ascii.toLower(a[i]);
        const cb = std.ascii.toLower(b[i]);
        if (ca != cb) return ca < cb;
    }
    if (a.len != b.len) return a.len < b.len;
    return std.mem.order(u8, a, b) == .lt;
}

const SubfolderEntry = struct {
    name: []const u8,
    full_path: []const u8,
};

fn renderFolderFiles(
    state: *EditorState,
    folder: []const u8,
    exact: bool,
    indent_level: usize,
    active_opt: ?usize,
    action: *ExplorerAction,
) void {
    const uic = &state.ui_ctx;
    const wfs = state.workspaceFiles();
    var matched_indices_list: std.ArrayListUnmanaged(usize) = .empty;

    for (wfs, 0..) |file, idx| {
        if (file.isSpecial()) continue;
        const matches = if (exact)
            std.mem.eql(u8, file.folder, folder)
        else
            (std.mem.eql(u8, file.folder, folder) or
                (std.mem.startsWith(u8, file.folder, folder) and file.folder.len > folder.len and file.folder[folder.len] == '/'));
        if (!matches) continue;
        matched_indices_list.append(uic.arena, idx) catch {};
    }

    const matched_indices = matched_indices_list.items;
    const match_count = matched_indices.len;

    // Insertion-sort files alphabetically by filename (case-insensitive)
    if (match_count > 1) {
        var i: usize = 1;
        while (i < match_count) : (i += 1) {
            const cur_idx = matched_indices[i];
            const cur_name = wfs[cur_idx].name;
            var j: usize = i;
            while (j > 0 and asciiLessThanIgnoreCase(cur_name, wfs[matched_indices[j - 1]].name)) : (j -= 1) {
                matched_indices[j] = matched_indices[j - 1];
            }
            matched_indices[j] = cur_idx;
        }
    }

    const rename_st_opt: ?*ExplorerInlineRenameState = if (uic.platform_ctx != null)
        uic.useState(ExplorerInlineRenameState, "inline_rename", .{})
    else
        null;

    for (matched_indices) |idx| {
        const file = wfs[idx];
        var item_id = uic.scopedId(idx + 10_000);
        defer item_id.end();

        const badge = fileBadgeIcon(file.language, file.is_terminal, file.is_agent, file.is_markdown_preview, file.is_waveform_preview or EditorState.isVcdCandidatePath(file.path), file.is_pdf_preview or EditorState.isPdfCandidatePath(file.path), EditorState.isImageCandidatePath(file.path), file.is_git_diff_preview);
        const is_renaming_file = uic.latch(
            bool,
            rename_st_opt != null and rename_st_opt.?.renaming_file and rename_st_opt.?.target_file_idx == idx,
        );
        if (is_renaming_file) {
            const rst = rename_st_opt.?;
            switch (uic.treeInlineInputRow(
                256,
                "##explorer_rename_file_input",
                indent_level,
                badge.text,
                badge.color,
                &rst.input_buf,
                "File name...",
                .{},
            )) {
                .submitted, .cancelled => {
                    rst.renaming_file = false;
                },
                .none => {},
            }
            continue;
        }

        const dirty = state.isFileDirty(idx);
        const git_mod = state.isFileModifiedInGit(idx);
        const sub_meta = if (!exact and file.folder.len > folder.len + 1)
            file.folder[folder.len + 1 ..]
        else if (dirty)
            "M ●"
        else if (git_mod)
            "M"
        else
            "";

        const item_res = uic.listItemEx(.{
            .label = ui.tree_view_mod.baseName(file.path),
            .meta = sub_meta,
            .meta_color = if (dirty or git_mod) skia.Color.rgb(251, 191, 36) else null,
            .icon_text = badge.text,
            .icon_color = badge.color,
            .icon_bg = badge.bg,
            .selected = (active_opt != null and active_opt.? == idx),
            .height = 23.0,
            .indent_level = indent_level,
        });
        if (item_res.clicked) {
            state.openFile(idx);
            action.file_switched = true;
        } else if (item_res.right_clicked) {
            state.openContextMenu(.explorer_file, state.activePaneIndex(), idx, false);
        }
    }
}

/// Recursively builds the directory tree from `state.workspaceFolders()` and `state.workspaceFiles()`
/// starting at `parent_folder` (`"."` for the workspace root), rendering sorted subdirectories first
/// (including newly created empty directories) followed by sorted files.
fn renderDirectoryTreeRecursive(
    state: *EditorState,
    parent_folder: []const u8,
    indent_level: usize,
    active_opt: ?usize,
    action: *ExplorerAction,
) void {
    if (indent_level > 16) return;
    const uic = &state.ui_ctx;
    const wfs = state.workspaceFiles();
    const wfolders = state.workspaceFolders();
    const is_root = std.mem.eql(u8, parent_folder, ".");

    var subdirs_list: std.ArrayListUnmanaged(SubfolderEntry) = .empty;

    const addFolderCandidate = struct {
        fn add(
            arena: std.mem.Allocator,
            folder_path: []const u8,
            parent: []const u8,
            root: bool,
            list: *std.ArrayListUnmanaged(SubfolderEntry),
        ) void {
            if (std.mem.eql(u8, folder_path, ".") or folder_path.len == 0) return;
            var rem: []const u8 = undefined;
            if (root) {
                rem = folder_path;
            } else {
                if (!std.mem.startsWith(u8, folder_path, parent)) return;
                if (folder_path.len <= parent.len or folder_path[parent.len] != '/') return;
                rem = folder_path[parent.len + 1 ..];
            }
            if (rem.len == 0) return;

            const seg_len = std.mem.indexOfScalar(u8, rem, '/') orelse rem.len;
            const child_full = if (root)
                folder_path[0..seg_len]
            else
                folder_path[0 .. parent.len + 1 + seg_len];
            const child_name = ui.tree_view_mod.baseName(child_full);

            for (list.items) |existing| {
                if (std.mem.eql(u8, existing.full_path, child_full)) return;
            }
            list.append(arena, .{
                .name = child_name,
                .full_path = child_full,
            }) catch {};
        }
    }.add;

    for (wfolders) |*dir_entry| {
        addFolderCandidate(uic.arena, dir_entry.slice(), parent_folder, is_root, &subdirs_list);
    }
    var prev_file_folder: []const u8 = "";
    for (wfs) |file| {
        if (file.isSpecial()) continue;
        if (prev_file_folder.len > 0 and std.mem.eql(u8, file.folder, prev_file_folder)) continue;
        prev_file_folder = file.folder;
        addFolderCandidate(uic.arena, file.folder, parent_folder, is_root, &subdirs_list);
    }

    const subdirs = subdirs_list.items;
    const subdir_count = subdirs.len;

    // Sort immediate subdirectories alphabetically (case-insensitive)
    if (subdir_count > 1) {
        var i: usize = 1;
        while (i < subdir_count) : (i += 1) {
            const cur = subdirs[i];
            var j: usize = i;
            while (j > 0 and asciiLessThanIgnoreCase(cur.name, subdirs[j - 1].name)) : (j -= 1) {
                subdirs[j] = subdirs[j - 1];
            }
            subdirs[j] = cur;
        }
    }

    const rename_st_opt: ?*ExplorerInlineRenameState = if (uic.platform_ctx != null)
        uic.useState(ExplorerInlineRenameState, "inline_rename", .{})
    else
        null;

    // 1. Render subdirectories recursively
    for (subdirs) |sub| {
        const sub_depth = ui.tree_view_mod.pathDepth(sub.full_path);
        const sub_cnt = countFolderFiles(state, sub.full_path, false);
        var exp = state.isFolderExpanded(sub.full_path);
        const prev_exp = exp;
        const is_renaming_dir = uic.latch(
            bool,
            rename_st_opt != null and rename_st_opt.?.renaming_folder and std.mem.eql(u8, rename_st_opt.?.target_folder.slice(), sub.full_path),
        );
        if (is_renaming_dir) {
            const rst = rename_st_opt.?;
            switch (uic.treeInlineInputRow(
                256,
                "##explorer_rename_folder_input",
                sub_depth,
                if (exp) "▾" else "▸",
                skia.Color.rgb(96, 165, 250),
                &rst.input_buf,
                "Folder name...",
                .{},
            )) {
                .submitted, .cancelled => {
                    rst.renaming_folder = false;
                },
                .none => {},
            }
        } else {
            const node_label = uic.fmt("{s}##dir_{s}", .{ sub.name, sub.full_path });
            const node_res = uic.treeFolderNodeEx(node_label, sub_depth, &exp, uic.fmt("{d}", .{sub_cnt}));
            if (exp != prev_exp) {
                state.setFolderExpanded(sub.full_path, exp);
            }
            if (node_res.right_clicked) {
                state.context_menu_folder.set(sub.full_path);
                state.openContextMenu(.explorer_folder, state.activePaneIndex(), null, false);
            }
        }
        if (exp) {
            renderDirectoryTreeRecursive(state, sub.full_path, sub_depth + 1, active_opt, action);
        }
    }

    // 2. Render files residing directly inside `parent_folder`
    renderFolderFiles(state, parent_folder, true, indent_level, active_opt, action);
}

fn buildExplorerView(
    state: *EditorState,
    action: *ExplorerAction,
) void {
    const uic = &state.ui_ctx;
    const active_opt = state.activeFileIndex();
    const wfs = state.workspaceFiles();

    // 1. Collapsible OPEN BUFFERS Section (Emacs-style Buffer List across split windows)
    const open_count = state.openBufferCount();
    const pane_count = state.paneCount();
    const open_badge = uic.fmt("{d}", .{open_count});
    if (uic.collapsibleSection("OPEN BUFFERS##sec_open", &state.doc.sec_open_editors, open_badge)) {
        if (open_count == 0) {
            uic.label("No open buffers", null);
        } else {
            for (0..open_count) |b_idx| {
                const f_idx: usize = @as(usize, state.doc.open_buffers[b_idx]) % wfs.len;
                const file = wfs[f_idx];
                const dirty = state.isFileDirty(f_idx);
                const is_selected = (active_opt != null and active_opt.? == f_idx);
                const vis_pane = state.bufferVisibleInPane(f_idx);
                const byte_len = if (state.loaded_from_disk[f_idx] or file.isSpecial() or dirty)
                    state.buffers[f_idx].slice().len
                else
                    (EditorState.regularFileSizeOnDisk(file.path.ptr) orelse 0);

                var open_id = uic.scopedId(b_idx + 1);
                defer open_id.end();

                const src_md_name = state.markdownPreviewSourceName(f_idx);
                const src_wave_name = wfs[state.waveformPreviewSourceIndex()].name;
                const src_diff_name = wfs[state.gitDiffPreviewSourceIndex()].name;
                const meta_str = if (file.is_terminal)
                    (if (pane_count > 1 and vis_pane != null) uic.fmt("W{d} · zsh", .{vis_pane.? + 1}) else "zsh")
                else if (file.is_agent)
                    (if (pane_count > 1 and vis_pane != null) uic.fmt("W{d} · agy", .{vis_pane.? + 1}) else "agy")
                else if (file.is_markdown_preview)
                    (if (pane_count > 1 and vis_pane != null) uic.fmt("W{d} · {s}", .{ vis_pane.? + 1, src_md_name }) else src_md_name)
                else if (file.is_waveform_preview)
                    (if (pane_count > 1 and vis_pane != null) uic.fmt("W{d} · {s}", .{ vis_pane.? + 1, src_wave_name }) else src_wave_name)
                else if (file.is_pdf_preview)
                    (if (pane_count > 1 and vis_pane != null) uic.fmt("W{d} · PDF", .{vis_pane.? + 1}) else "PDF")
                else if (file.is_git_diff_preview)
                    (if (pane_count > 1 and vis_pane != null) uic.fmt("W{d} · {s}", .{ vis_pane.? + 1, src_diff_name }) else src_diff_name)
                else if (pane_count > 1 and vis_pane != null)
                    (if (dirty) uic.fmt("* W{d}", .{vis_pane.? + 1}) else uic.fmt("W{d}", .{vis_pane.? + 1}))
                else if (dirty)
                    uic.fmt("* {d}B", .{byte_len})
                else
                    uic.fmt("{d}B", .{byte_len});

                const f_badge = fileBadgeIcon(file.language, file.is_terminal, file.is_agent, file.is_markdown_preview, file.is_waveform_preview or EditorState.isVcdCandidatePath(file.path), file.is_pdf_preview or EditorState.isPdfCandidatePath(file.path), EditorState.isImageCandidatePath(file.path), file.is_git_diff_preview);
                const open_res = uic.listItemEx(.{
                    .label = file.name,
                    .meta = meta_str,
                    .meta_color = if (dirty)
                        skia.Color.rgb(251, 191, 36)
                    else if (vis_pane != null and pane_count > 1)
                        skia.Color.rgb(56, 189, 248)
                    else
                        null,
                    .icon_text = f_badge.text,
                    .icon_color = f_badge.color,
                    .selected = is_selected,
                    .height = 23.0,
                    .action_label = "×",
                });
                if (open_res.action_clicked) {
                    state.killBuffer(f_idx);
                    action.file_switched = true;
                    return;
                } else if (open_res.clicked) {
                    state.openFile(f_idx);
                    action.file_switched = true;
                } else if (open_res.right_clicked) {
                    state.openContextMenu(.explorer_file, state.activePaneIndex(), f_idx, false);
                }
            }
        }
    }

    // 2. Collapsible Hierarchical WORKSPACE File Browser Tree with Manual Refresh (`↺`) Button
    if (!state.hasOpenedWorkspace()) {
        if (uic.collapsibleSection("NO FOLDER OPENED##sec_no_folder", &state.doc.sec_files, "")) {
            var col = uic.column(.{
                .padding = ui.Padding.xy(14, 10),
                .gap = 8,
            });
            defer col.end();
            uic.label("You have not yet opened a folder.", uic.theme.text_muted);
            if (uic.btn("Open Folder...", .{ .variant = .primary, .h = 30.0 })) {
                state.openWorkspacePrompt();
            }
        }
    } else {
        const ws_title = uic.fmt("WORKSPACE ({s})##sec_files", .{state.workspaceName()});
        const files_badge = uic.fmt("{d}", .{state.nonSpecialFileCount()});
        const ws_sec = uic.collapsibleSectionWithAction(ws_title, &state.doc.sec_files, files_badge, "↺");
        if (ws_sec.action_clicked) {
            state.refreshWorkspaceFiles(true);
            action.file_switched = true;
        } else if (ws_sec.right_clicked) {
            state.context_menu_folder.set(".");
            state.openContextMenu(.explorer_folder, state.activePaneIndex(), null, false);
        }
        if (ws_sec.expanded) {
            renderDirectoryTreeRecursive(state, ".", 0, active_opt, action);
        }
    }

    // 3. Collapsible LIVE SYMBOL OUTLINE Section (with collapsible symbol groups)
    if (active_opt) |f_idx| {
        const is_scratch_md_prev = wfs[f_idx].is_markdown_preview and state.isScratchMarkdownPreview(f_idx);
        const outline_f_idx = if (wfs[f_idx].is_markdown_preview and !is_scratch_md_prev)
            state.markdownPreviewSourceIndexForBuffer(f_idx)
        else if (wfs[f_idx].is_waveform_preview)
            state.waveformPreviewSourceIndex()
        else if (wfs[f_idx].is_git_diff_preview)
            state.gitDiffPreviewSourceIndex()
        else
            f_idx;
        const active_file = wfs[outline_f_idx];
        const active_buf = if (is_scratch_md_prev) &state.scratch_buf else &state.buffers[outline_f_idx];
        const symbols = state.symbolsForFile(f_idx);
        const sym_count = symbols.len;

        const sym_badge = uic.fmt("{d}", .{sym_count});
        if (uic.collapsibleSection("OUTLINE##sec_outline", &state.doc.sec_outline, sym_badge)) {
            if (sym_count == 0) {
                uic.label("No symbols in active file", null);
            } else if (active_file.language == .markdown) {
                const cur_line = active_buf.cursorLineCol().line;
                for (symbols, 0..) |sym, sidx| {
                    var sym_id = uic.scopedId(sidx + 1000);
                    defer sym_id.end();

                    const depth: usize = if (std.mem.eql(u8, sym.kind, "h3"))
                        2
                    else if (std.mem.eql(u8, sym.kind, "h2"))
                        1
                    else
                        0;

                    const res = uic.listItemEx(.{
                        .label = sym.name,
                        .meta = uic.fmt(":{d}", .{sym.line}),
                        .icon_text = sym.kind,
                        .icon_color = skia.Color.rgb(56, 189, 248),
                        .selected = (cur_line == sym.line),
                        .height = 23.0,
                        .mono_label = true,
                        .indent_level = depth,
                    });
                    if (res.clicked) {
                        active_buf.jumpToLine(sym.line);
                        state.pending_md_heading.set(sym.name);
                        state.doc.cursor_line = @intCast(sym.line);
                        state.doc.cursor_col = 1;
                        uic.focused_id = state.activeEditorWidgetId();
                        action.file_switched = true;
                    } else if (res.right_clicked) {
                        state.context_menu_line = sym.line;
                        state.context_menu_label.set(sym.name);
                        state.openContextMenu(.outline_symbol, state.activePaneIndex(), outline_f_idx, false);
                    }
                }
            } else {
                const cur_line = active_buf.cursorLineCol().line;
                var fn_count: usize = 0;
                var type_count: usize = 0;
                for (symbols) |sym| {
                    if (std.mem.eql(u8, sym.kind, "fn")) {
                        fn_count += 1;
                    } else {
                        type_count += 1;
                    }
                }

                if (fn_count > 0) {
                    const fn_meta = uic.fmt("{d}", .{fn_count});
                    if (uic.treeFolderNode("Functions##outline_fns", 0, &state.doc.outline_group_fn, fn_meta)) {
                        for (symbols, 0..) |sym, sidx| {
                            if (!std.mem.eql(u8, sym.kind, "fn")) continue;
                            var sym_id = uic.scopedId(sidx + 1000);
                            defer sym_id.end();

                            const res = uic.listItemEx(.{
                                .label = sym.name,
                                .meta = uic.fmt(":{d}", .{sym.line}),
                                .icon_text = sym.kind,
                                .icon_color = skia.Color.rgb(210, 168, 255),
                                .selected = (cur_line == sym.line),
                                .height = 23.0,
                                .mono_label = true,
                                .indent_level = 1,
                            });
                            if (res.clicked) {
                                active_buf.jumpToLine(sym.line);
                                state.doc.cursor_line = @intCast(sym.line);
                                state.doc.cursor_col = 1;
                                uic.focused_id = state.activeEditorWidgetId();
                                action.file_switched = true;
                            } else if (res.right_clicked) {
                                state.context_menu_line = sym.line;
                                state.context_menu_label.set(sym.name);
                                state.openContextMenu(.outline_symbol, state.activePaneIndex(), f_idx, false);
                            }
                        }
                    }
                }

                if (type_count > 0) {
                    const type_meta = uic.fmt("{d}", .{type_count});
                    if (uic.treeFolderNode("Types & Constants##outline_types", 0, &state.doc.outline_group_types, type_meta)) {
                        for (symbols, 0..) |sym, sidx| {
                            if (std.mem.eql(u8, sym.kind, "fn")) continue;
                            var sym_id = uic.scopedId(sidx + 1200);
                            defer sym_id.end();

                            const res = uic.listItemEx(.{
                                .label = sym.name,
                                .meta = uic.fmt(":{d}", .{sym.line}),
                                .icon_text = sym.kind,
                                .icon_color = skia.Color.rgb(121, 192, 255),
                                .selected = (cur_line == sym.line),
                                .height = 23.0,
                                .mono_label = true,
                                .indent_level = 1,
                            });
                            if (res.clicked) {
                                active_buf.jumpToLine(sym.line);
                                state.doc.cursor_line = @intCast(sym.line);
                                state.doc.cursor_col = 1;
                                uic.focused_id = state.activeEditorWidgetId();
                                action.file_switched = true;
                            } else if (res.right_clicked) {
                                state.context_menu_line = sym.line;
                                state.context_menu_label.set(sym.name);
                                state.openContextMenu(.outline_symbol, state.activePaneIndex(), f_idx, false);
                            }
                        }
                    }
                }
            }
        }
    }
}

fn buildSearchView(
    state: *EditorState,
    action: *ExplorerAction,
) void {
    const uic = &state.ui_ctx;
    const active_opt = state.activeFileIndex();

    uic.label("SEARCH", null);
    uic.spacer(2);

    _ = uic.textFieldInline(
        "##workspace_search_input",
        &state.workspace_search,
        "Search files...",
        .{ .w = .fill },
    );

    const query = state.workspaceSearchQuery();
    if (query.len == 0) return;

    uic.spacer(4);

    const wfs = state.workspaceFiles();
    const matches = state.workspaceSearchMatches();
    for (matches) |*m| {
        const f_idx: usize = @intCast(m.file_idx);
        if (f_idx >= wfs.len) continue;
        const file = wfs[f_idx];
        const line_num: usize = @intCast(m.line_num);

        var match_id = uic.scopedId(f_idx * 10000 + line_num);
        defer match_id.end();

        const is_pdf_file = file.is_pdf_preview or EditorState.isPdfCandidatePath(file.path);
        const item_label = if (is_pdf_file)
            uic.fmt("{s}:p.{d}  {s}", .{ file.name, line_num, m.snippet.slice() })
        else
            uic.fmt("{s}:{d}  {s}", .{ file.name, line_num, m.snippet.slice() });

        const res = uic.listItemEx(.{
            .label = item_label,
            .selected = (active_opt != null and active_opt.? == f_idx and state.doc.cursor_line == line_num),
            .height = 24.0,
            .mono_label = true,
        });
        if (res.clicked) {
            state.openFile(f_idx);
            state.find_query.set(query);

            if (is_pdf_file) {
                const pane_idx = state.activePaneIndex();
                if (state.resolvePdfSourceForPane(pane_idx)) |pdf_src| {
                    var pdf_doc = ui.PdfDocumentData{};
                    ui.parsePdfDocument(pdf_src.eff_bytes, pdf_src.eff_path, &pdf_doc);
                    const pdf_view = state.pdfViewStateForPane(pane_idx, pdf_src.file_idx, pdf_src.is_direct_pdf);
                    if (pdf_doc.findMatch(null, line_num -| 1, query, true, false)) |pdf_m| {
                        pdf_view.jumpToSearchMatch(pdf_m);
                    } else {
                        pdf_view.current_page = line_num -| 1;
                    }
                    state.pdf_views[@min(pane_idx, state_mod.MaxEditorPanes - 1)] = pdf_view.*;
                }
                state.doc.cursor_line = @intCast(line_num);
                state.doc.cursor_col = 1;
            } else {
                state.buffers[f_idx].jumpToLineAndHighlight(line_num, query);
                const cur_lc = state.buffers[f_idx].cursorLineCol();
                state.doc.cursor_line = @intCast(cur_lc.line);
                state.doc.cursor_col = @intCast(cur_lc.col);
            }
            uic.focused_id = state.activeEditorWidgetId();
            action.file_switched = true;
        } else if (res.right_clicked) {
            state.context_menu_line = line_num;
            state.context_menu_label.set(m.trimmed_line.slice());
            state.openContextMenu(.search_match, state.activePaneIndex(), f_idx, false);
        }
    }

    if (matches.len == 0) {
        uic.label("No results.", null);
    }
}

fn buildPluginsView(state: *EditorState) void {
    const uic = &state.ui_ctx;

    var enabled_count: usize = 0;
    var active_count: usize = 0;
    for (0..state.plugins.plugin_count) |idx| {
        const p = &state.plugins.plugins[idx];
        if (!p.active) continue;
        active_count += 1;
        if (p.enabled) enabled_count += 1;
    }

    var hdr = uic.row(.{ .h = .pixels(24), .gap = 6 });
    uic.label(uic.fmt("PLUGINS ({d}/{d})", .{ enabled_count, active_count }), null);
    if (uic.availableWidth() > 54) {
        uic.spacer(uic.availableWidth() - 54);
    }
    if (uic.btn("Reload##scan_plugins_btn", .{ .w = .pixels(50), .h = 22 })) {
        _ = state.plugins.scanAndReloadPlugins(state, true);
        state.setStatusNotice("Scanned plugins (~/.lightning/plugins, zig-out/plugins)");
    }
    hdr.end();

    _ = uic.textFieldInline(
        "##plugin_search_input",
        &state.plugin_search,
        "Filter plugins...",
        .{ .w = .fill },
    );

    if (state.plugins.plugin_count == 0) {
        uic.label("No .dylib plugins loaded.", null);
        uic.monoLabel("Locations: ~/.lightning/plugins or zig-out/plugins", null);
        return;
    }

    const filter_q = std.mem.trim(u8, state.plugin_search.slice(), " \t\r\n");

    for (0..state.plugins.plugin_count) |idx| {
        const p = &state.plugins.plugins[idx];
        if (!p.active) continue;

        if (filter_q.len > 0 and
            !ui.containsIgnoreCase(p.display_name.slice(), filter_q) and
            !ui.containsIgnoreCase(p.id.slice(), filter_q))
        {
            continue;
        }

        var id_guard = uic.scopedId(idx);
        defer id_guard.end();

        const has_sidebar_icon = p.capabilities.sidebar_panel and p.sidebar_icon != .none;
        const origin_str = if (p.is_user_override) " [user]" else "";
        const meta_str = if (has_sidebar_icon)
            uic.fmt("v{s}{s} · sidebar", .{ p.version.slice(), origin_str })
        else
            uic.fmt("v{s}{s}", .{ p.version.slice(), origin_str });

        const item = uic.listItemEx(.{
            .label = p.display_name.slice(),
            .meta = meta_str,
            .icon_text = if (p.enabled) "●" else "○",
            .icon_color = if (p.enabled) skia.Color.rgb(52, 211, 153) else uic.theme.text_muted,
            .selected = p.enabled,
            .action_label = if (p.enabled) "Disable" else "Enable",
        });
        if (item.action_clicked) {
            state.plugins.setPluginEnabled(state, idx, !p.enabled);
        } else if (item.clicked) {
            if (has_sidebar_icon and p.enabled) {
                state.doc.active_sidebar_view = @intCast(3 + idx);
                uic.invalidateWindow();
            } else {
                state.plugins.setPluginEnabled(state, idx, !p.enabled);
            }
        } else if (item.right_clicked) {
            state.context_menu_index = idx;
            state.openContextMenu(.plugin_item, state.activePaneIndex(), null, false);
        }
    }
}

fn buildPluginSidebarView(state: *EditorState, plugin_idx: usize) void {
    if (plugin_idx >= state.plugins.plugin_count) {
        buildPluginsView(state);
        return;
    }
    const p = &state.plugins.plugins[plugin_idx];
    if (!p.active or !p.enabled or !p.capabilities.sidebar_panel) {
        buildPluginsView(state);
        return;
    }
    state.plugins.renderPluginSidebar(state, plugin_idx);
}
