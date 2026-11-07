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

const ExplorerFlatNode = state_mod.ExplorerFlatNode;

const SubfolderRef = struct {
    name: []const u8,
    full_path: []const u8,
    from_folder_list: bool,
    item_idx: u32,
    path_len: u16,
};

fn computeExplorerTreeSignature(state: *const EditorState) u64 {
    var h = std.hash.Fnv1a_64.init();
    h.update(std.mem.asBytes(&state.file_count));
    h.update(std.mem.asBytes(&state.folder_count));
    h.update(std.mem.asBytes(&state.workspace_tree_gen));
    h.update(std.mem.asBytes(&state.doc.folder_default_expanded));
    h.update(std.mem.asBytes(&state.doc.collapsed_folder_count));
    const cnt = @min(@as(usize, state.doc.collapsed_folder_count), state_mod.MaxCollapsedFolders);
    if (cnt > 0) {
        h.update(std.mem.sliceAsBytes(state.doc.collapsed_folder_hashes[0..cnt]));
    }
    h.update(state.workspaceRoot());
    const final_h = h.final();
    return if (final_h == 0) 1 else final_h;
}

const TreeBuildScratch = struct {
    seen_dirs: std.StringHashMapUnmanaged(void) = .empty,
    child_subdirs: std.StringHashMapUnmanaged(std.ArrayListUnmanaged(SubfolderRef)) = .empty,
    folder_files: std.StringHashMapUnmanaged(std.ArrayListUnmanaged(u32)) = .empty,
    recursive_counts: std.StringHashMapUnmanaged(u32) = .empty,

    fn registerFolderHierarchy(
        self: *TreeBuildScratch,
        arena: std.mem.Allocator,
        full_folder_slice: []const u8,
        from_folder_list: bool,
        item_idx: u32,
    ) void {
        if (full_folder_slice.len == 0 or std.mem.eql(u8, full_folder_slice, ".")) return;
        var cur_len: usize = full_folder_slice.len;
        while (cur_len > 0) {
            const cur_path = full_folder_slice[0..cur_len];
            if (std.mem.eql(u8, cur_path, ".")) break;
            const seen_gop = self.seen_dirs.getOrPut(arena, cur_path) catch return;
            if (seen_gop.found_existing) break;

            const slash_opt = std.mem.lastIndexOfScalar(u8, cur_path, '/');
            const parent_path = if (slash_opt) |si| (if (si > 0) cur_path[0..si] else ".") else ".";
            const sub_gop = self.child_subdirs.getOrPut(arena, parent_path) catch return;
            if (!sub_gop.found_existing) {
                sub_gop.value_ptr.* = .empty;
            }
            sub_gop.value_ptr.append(arena, .{
                .name = ui.tree_view_mod.baseName(cur_path),
                .full_path = cur_path,
                .from_folder_list = from_folder_list,
                .item_idx = item_idx,
                .path_len = @intCast(@min(cur_len, std.math.maxInt(u16))),
            }) catch {};

            cur_len = slash_opt orelse 0;
        }
    }
};

fn emitExplorerTreeRecursive(
    state: *EditorState,
    parent_folder: []const u8,
    indent_level: usize,
    scratch: *TreeBuildScratch,
) void {
    if (indent_level > 16) return;
    const alloc = std.heap.c_allocator;
    const wfs = state.workspaceFiles();

    if (scratch.child_subdirs.getPtr(parent_folder)) |sub_list| {
        const subdirs = sub_list.items;
        if (subdirs.len > 1) {
            var i: usize = 1;
            while (i < subdirs.len) : (i += 1) {
                const cur = subdirs[i];
                var j: usize = i;
                while (j > 0 and asciiLessThanIgnoreCase(cur.name, subdirs[j - 1].name)) : (j -= 1) {
                    subdirs[j] = subdirs[j - 1];
                }
                subdirs[j] = cur;
            }
        }

        for (subdirs) |sub| {
            const sub_depth = ui.tree_view_mod.pathDepth(sub.full_path);
            const rec_cnt = scratch.recursive_counts.get(sub.full_path) orelse 0;
            var node = ExplorerFlatNode{
                .is_folder = true,
                .from_folder_list = sub.from_folder_list,
                .depth = @intCast(@min(sub_depth, 16)),
                .path_len = sub.path_len,
                .item_idx = sub.item_idx,
                .rec_file_count = rec_cnt,
            };
            if (std.fmt.bufPrint(&node.badge_buf, "{d}", .{rec_cnt})) |b_slice| {
                node.badge_len = @intCast(b_slice.len);
            } else |_| {}
            state.cached_tree_nodes_list.append(alloc, node) catch {};

            if (state.isFolderExpanded(sub.full_path)) {
                emitExplorerTreeRecursive(state, sub.full_path, sub_depth + 1, scratch);
            }
        }
    }

    if (scratch.folder_files.getPtr(parent_folder)) |f_list| {
        const matched_indices = f_list.items;
        if (matched_indices.len > 1) {
            var already_sorted = true;
            for (1..matched_indices.len) |i| {
                if (asciiLessThanIgnoreCase(wfs[matched_indices[i]].name, wfs[matched_indices[i - 1]].name)) {
                    already_sorted = false;
                    break;
                }
            }
            if (!already_sorted) {
                const SortCtx = struct {
                    files: []const state_mod.SampleFile,
                    pub fn lessThan(ctx: @This(), a: u32, b: u32) bool {
                        return asciiLessThanIgnoreCase(ctx.files[a].name, ctx.files[b].name);
                    }
                };
                std.mem.sort(u32, matched_indices, SortCtx{ .files = wfs }, SortCtx.lessThan);
            }
        }

        for (matched_indices) |f_idx| {
            state.cached_tree_nodes_list.append(alloc, .{
                .is_folder = false,
                .depth = @intCast(@min(indent_level, 16)),
                .item_idx = f_idx,
            }) catch {};
        }
    }
}

fn ensureExplorerTreeCache(state: *EditorState) []const ExplorerFlatNode {
    const uic = &state.ui_ctx;
    if (uic.pass == .input or state.cached_tree_sig == 0) {
        const sig = computeExplorerTreeSignature(state);
        if (state.cached_tree_sig != sig) {
            state.cached_tree_nodes_list.clearRetainingCapacity();
            const arena = uic.arena;
            const wfs = state.workspaceFiles();
            const wfolders = state.workspaceFolders();

            var scratch = TreeBuildScratch{};
            for (wfolders, 0..) |*dir_entry, d_idx| {
                scratch.registerFolderHierarchy(arena, dir_entry.slice(), true, @intCast(d_idx));
            }

            var non_special: usize = 0;
            var prev_folder: []const u8 = "";
            var prev_folder_count: u32 = 0;
            for (wfs, 0..) |*file, idx| {
                if (file.isSpecial()) continue;
                non_special += 1;
                const folder = file.folder;
                if (prev_folder.len == 0 or !std.mem.eql(u8, folder, prev_folder)) {
                    if (prev_folder_count > 0 and !std.mem.eql(u8, prev_folder, ".") and prev_folder.len > 0) {
                        if (scratch.recursive_counts.getOrPut(arena, prev_folder)) |rec_gop| {
                            if (!rec_gop.found_existing) rec_gop.value_ptr.* = 0;
                            rec_gop.value_ptr.* += prev_folder_count;
                        } else |_| {}
                        var cur = prev_folder;
                        while (ui.tree_view_mod.parentDirPath(cur)) |ancestor| : (cur = ancestor) {
                            const anc_gop = scratch.recursive_counts.getOrPut(arena, ancestor) catch break;
                            if (!anc_gop.found_existing) anc_gop.value_ptr.* = 0;
                            anc_gop.value_ptr.* += prev_folder_count;
                        }
                    }
                    prev_folder = folder;
                    prev_folder_count = 0;
                    scratch.registerFolderHierarchy(arena, folder, false, @intCast(idx));
                }
                prev_folder_count += 1;

                if (std.mem.eql(u8, folder, ".") or state.isFolderExpanded(folder)) {
                    const f_gop = scratch.folder_files.getOrPut(arena, folder) catch continue;
                    if (!f_gop.found_existing) {
                        f_gop.value_ptr.* = .empty;
                    }
                    f_gop.value_ptr.append(arena, @intCast(idx)) catch {};
                }
            }
            if (prev_folder_count > 0 and !std.mem.eql(u8, prev_folder, ".") and prev_folder.len > 0) {
                if (scratch.recursive_counts.getOrPut(arena, prev_folder)) |rec_gop| {
                    if (!rec_gop.found_existing) rec_gop.value_ptr.* = 0;
                    rec_gop.value_ptr.* += prev_folder_count;
                } else |_| {}
                var cur = prev_folder;
                while (ui.tree_view_mod.parentDirPath(cur)) |ancestor| : (cur = ancestor) {
                    const anc_gop = scratch.recursive_counts.getOrPut(arena, ancestor) catch break;
                    if (!anc_gop.found_existing) anc_gop.value_ptr.* = 0;
                    anc_gop.value_ptr.* += prev_folder_count;
                }
            }

            emitExplorerTreeRecursive(state, ".", 0, &scratch);
            state.cached_non_special_file_count = non_special;
            state.cached_tree_sig = sig;
        }
    }
    return state.cached_tree_nodes_list.items;
}

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

fn fileBadgeIcon(lang: ui.CodeLanguage, is_terminal: bool, is_agent: bool, is_preview: bool, is_waveform: bool, is_pdf: bool, is_image: bool, is_audio: bool, is_video: bool, is_git_diff: bool, is_app: bool) struct {
    text: []const u8,
    color: u32,
    bg: u32,
} {
    if (is_app) return .{
        .text = "APP",
        .color = skia.Color.rgb(245, 158, 11),
        .bg = skia.Color.argb(45, 245, 158, 11),
    };
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
    if (is_video) return .{
        .text = "VID",
        .color = skia.Color.rgb(251, 146, 60),
        .bg = skia.Color.argb(45, 251, 146, 60),
    };
    if (is_audio) return .{
        .text = "AUD",
        .color = skia.Color.rgb(192, 132, 252),
        .bg = skia.Color.argb(45, 192, 132, 252),
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

fn renderWorkspaceTreeVirtual(
    state: *EditorState,
    active_opt: ?usize,
    action: *ExplorerAction,
    deferred_open_f_idx: *?usize,
) void {
    const uic = &state.ui_ctx;
    const nodes = ensureExplorerTreeCache(state);
    if (nodes.len == 0) return;

    const wfs = state.workspaceFiles();
    const wfolders = state.workspaceFolders();

    const rename_st_opt: ?*ExplorerInlineRenameState = if (uic.platform_ctx != null)
        uic.useState(ExplorerInlineRenameState, "inline_rename", .{})
    else
        null;

    const any_inline_rename = uic.latch(
        bool,
        rename_st_opt != null and (rename_st_opt.?.renaming_folder or rename_st_opt.?.renaming_file),
    );
    const vr = if (!any_inline_rename)
        uic.computeVirtualRange(nodes.len, 28.0, 4)
    else
        ui.VirtualRange{
            .first = 0,
            .end = nodes.len,
            .top_spacer_h = 0,
            .bottom_spacer_h = 0,
        };

    if (vr.top_spacer_h > 0) uic.spacer(vr.top_spacer_h);

    for (nodes[vr.first..vr.end]) |node| {
        if (node.is_folder) {
            const full_path: []const u8 = if (node.from_folder_list) blk: {
                if (node.item_idx >= wfolders.len) continue;
                const dslice = wfolders[node.item_idx].slice();
                break :blk dslice[0..@min(@as(usize, node.path_len), dslice.len)];
            } else blk: {
                if (node.item_idx >= wfs.len) continue;
                const ffolder = wfs[node.item_idx].folder;
                break :blk ffolder[0..@min(@as(usize, node.path_len), ffolder.len)];
            };
            const sub_name = ui.tree_view_mod.baseName(full_path);
            const sub_depth: usize = node.depth;
            var exp = state.isFolderExpanded(full_path);
            const prev_exp = exp;

            const is_renaming_dir = if (any_inline_rename)
                uic.latch(
                    bool,
                    rename_st_opt != null and rename_st_opt.?.renaming_folder and std.mem.eql(u8, rename_st_opt.?.target_folder.slice(), full_path),
                )
            else
                false;
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
                const node_label = uic.fmt("{s}##dir_{s}", .{ sub_name, full_path });
                const node_res = uic.treeFolderNodeEx(node_label, sub_depth, &exp, node.badgeSlice());
                if (exp != prev_exp) {
                    state.setFolderExpanded(full_path, exp);
                }
                if (node_res.right_clicked) {
                    state.context_menu_folder.set(full_path);
                    state.openContextMenu(.explorer_folder, state.activePaneIndex(), null, false);
                }
            }
        } else {
            const idx: usize = node.item_idx;
            if (idx >= wfs.len) continue;
            const file = wfs[idx];
            const indent_level: usize = node.depth;

            var item_id = uic.scopedId(idx + 10_000);
            defer item_id.end();

            const badge = fileBadgeIcon(
                file.language,
                file.is_terminal,
                file.is_agent,
                file.is_markdown_preview,
                file.is_waveform_preview or EditorState.isVcdCandidatePath(file.path),
                file.is_pdf_preview or EditorState.isPdfCandidatePath(file.path),
                EditorState.isImageCandidatePath(file.path),
                EditorState.isAudioCandidatePath(file.path),
                EditorState.isVideoCandidatePath(file.path),
                file.is_git_diff_preview,
                file.is_app_preview or EditorState.isAppCandidatePath(file.path),
            );
            const is_renaming_file = if (any_inline_rename)
                uic.latch(
                    bool,
                    rename_st_opt != null and rename_st_opt.?.renaming_file and rename_st_opt.?.target_file_idx == idx,
                )
            else
                false;
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
            const sub_meta = if (dirty)
                "M ●"
            else if (git_mod)
                "M"
            else
                "";

            const item_res = uic.listItemEx(.{
                .label = file.name,
                .meta = sub_meta,
                .meta_color = if (dirty or git_mod) skia.Color.rgb(251, 191, 36) else null,
                .icon_text = badge.text,
                .icon_color = badge.color,
                .icon_bg = badge.bg,
                .selected = (active_opt != null and active_opt.? == idx),
                .height = 24.0,
                .indent_level = indent_level,
            });
            if (item_res.clicked) {
                deferred_open_f_idx.* = idx;
                action.file_switched = true;
            } else if (item_res.right_clicked) {
                state.openContextMenu(.explorer_file, state.activePaneIndex(), idx, false);
            }
        }
    }

    if (vr.bottom_spacer_h > 0) uic.spacer(vr.bottom_spacer_h);
}

fn buildExplorerView(
    state: *EditorState,
    action: *ExplorerAction,
) void {
    const uic = &state.ui_ctx;
    const wfs = state.workspaceFiles();
    const raw_active_opt = state.activeFileIndex();
    const has_active = uic.latch(bool, raw_active_opt != null and raw_active_opt.? < wfs.len);
    const latched_active_idx = uic.latch(usize, if (raw_active_opt) |idx| idx else 0);
    const active_opt: ?usize = if (has_active and wfs.len > 0) @min(latched_active_idx, wfs.len - 1) else null;

    var deferred_open_f_idx: ?usize = null;
    var deferred_kill_f_idx: ?usize = null;
    var deferred_refresh_ws: bool = false;

    // 1. Collapsible OPEN BUFFERS Section (Emacs-style Buffer List across split windows)
    const open_count = @min(state.openBufferCount(), uic.latch(usize, state.openBufferCount()));
    const pane_count = uic.latch(usize, state.paneCount());
    const open_badge = uic.fmt("{d}", .{open_count});
    if (uic.collapsibleSection("OPEN BUFFERS##sec_open", &state.doc.sec_open_editors, open_badge)) {
        if (open_count == 0) {
            uic.label("No open buffers", null);
        } else {
            for (0..open_count) |b_idx| {
                const f_idx: usize = @as(usize, state.doc.open_buffers[b_idx]) % wfs.len;
                const file = &wfs[f_idx];
                const dirty = state.isFileDirty(f_idx);
                const is_selected = (active_opt != null and active_opt.? == f_idx);
                const vis_pane = state.bufferVisibleInPane(f_idx);

                var open_id = uic.scopedId(b_idx + 1);
                defer open_id.end();

                const meta_str = if (file.is_terminal)
                    (if (pane_count > 1 and vis_pane != null) uic.fmt("W{d} · zsh", .{vis_pane.? + 1}) else "zsh")
                else if (file.is_agent)
                    (if (pane_count > 1 and vis_pane != null) uic.fmt("W{d} · agy", .{vis_pane.? + 1}) else "agy")
                else if (file.is_markdown_preview) blk: {
                    const src_md_name = state.markdownPreviewSourceName(f_idx);
                    break :blk if (pane_count > 1 and vis_pane != null) uic.fmt("W{d} · {s}", .{ vis_pane.? + 1, src_md_name }) else src_md_name;
                } else if (file.is_waveform_preview) blk: {
                    const src_wave_name = wfs[state.waveformPreviewSourceIndex()].name;
                    break :blk if (pane_count > 1 and vis_pane != null) uic.fmt("W{d} · {s}", .{ vis_pane.? + 1, src_wave_name }) else src_wave_name;
                } else if (file.is_pdf_preview)
                    (if (pane_count > 1 and vis_pane != null) uic.fmt("W{d} · PDF", .{vis_pane.? + 1}) else "PDF")
                else if (file.is_git_diff_preview) blk: {
                    const src_diff_name = wfs[state.gitDiffPreviewSourceIndex()].name;
                    break :blk if (pane_count > 1 and vis_pane != null) uic.fmt("W{d} · {s}", .{ vis_pane.? + 1, src_diff_name }) else src_diff_name;
                } else if (pane_count > 1 and vis_pane != null)
                    (if (dirty) uic.fmt("* W{d}", .{vis_pane.? + 1}) else uic.fmt("W{d}", .{vis_pane.? + 1}))
                else blk: {
                    const byte_len = state.fileByteSize(f_idx);
                    break :blk if (dirty) uic.fmt("* {d}B", .{byte_len}) else uic.fmt("{d}B", .{byte_len});
                };

                const f_badge = fileBadgeIcon(file.language, file.is_terminal, file.is_agent, file.is_markdown_preview, file.is_waveform_preview or EditorState.isVcdCandidatePath(file.path), file.is_pdf_preview or EditorState.isPdfCandidatePath(file.path), EditorState.isImageCandidatePath(file.path), EditorState.isAudioCandidatePath(file.path), EditorState.isVideoCandidatePath(file.path), file.is_git_diff_preview, file.is_app_preview or EditorState.isAppCandidatePath(file.path));
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
                    deferred_kill_f_idx = f_idx;
                } else if (open_res.clicked) {
                    deferred_open_f_idx = f_idx;
                    action.file_switched = true;
                } else if (open_res.right_clicked) {
                    state.openContextMenu(.explorer_file, state.activePaneIndex(), f_idx, false);
                }
            }
        }
    }

    // 2. Collapsible Hierarchical WORKSPACE File Browser Tree with Manual Refresh (`↺`) Button
    const has_opened_ws = uic.latch(bool, state.hasOpenedWorkspace());
    if (!has_opened_ws) {
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
        _ = ensureExplorerTreeCache(state);
        const ws_title = uic.fmt("WORKSPACE ({s})##sec_files", .{state.workspaceName()});
        const files_badge = uic.fmt("{d}", .{state.cached_non_special_file_count});
        const ws_sec = uic.collapsibleSectionWithAction(ws_title, &state.doc.sec_files, files_badge, "↺");
        if (ws_sec.action_clicked) {
            deferred_refresh_ws = true;
            action.file_switched = true;
        } else if (ws_sec.right_clicked) {
            state.context_menu_folder.set(".");
            state.openContextMenu(.explorer_folder, state.activePaneIndex(), null, false);
        }
        if (ws_sec.expanded) {
            renderWorkspaceTreeVirtual(state, active_opt, action, &deferred_open_f_idx);
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
        const latched_has_syms = uic.latch(bool, sym_count > 0);
        const latched_is_md = uic.latch(bool, active_file.language == .markdown);

        const sym_badge = uic.fmt("{d}", .{sym_count});
        if (uic.collapsibleSection("OUTLINE##sec_outline", &state.doc.sec_outline, sym_badge)) {
            if (!latched_has_syms or sym_count == 0) {
                uic.label("No symbols in active file", null);
            } else if (latched_is_md) {
                const cur_line = active_buf.cursorLineCol().line;
                const vr = uic.computeVirtualRange(symbols.len, 27.0, 4);
                if (vr.top_spacer_h > 0) uic.spacer(vr.top_spacer_h);
                for (symbols[vr.first..vr.end], vr.first..) |sym, sidx| {
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
                if (vr.bottom_spacer_h > 0) uic.spacer(vr.bottom_spacer_h);
            } else {
                const cur_line = active_buf.cursorLineCol().line;
                var fn_indices: std.ArrayListUnmanaged(usize) = .empty;
                var type_indices: std.ArrayListUnmanaged(usize) = .empty;
                for (symbols, 0..) |sym, sidx| {
                    if (std.mem.eql(u8, sym.kind, "fn")) {
                        fn_indices.append(uic.arena, sidx) catch {};
                    } else {
                        type_indices.append(uic.arena, sidx) catch {};
                    }
                }

                const has_fn_syms = uic.latch(bool, fn_indices.items.len > 0);
                if (has_fn_syms) {
                    const fn_meta = uic.fmt("{d}", .{fn_indices.items.len});
                    if (uic.treeFolderNode("Functions##outline_fns", 0, &state.doc.outline_group_fn, fn_meta)) {
                        var fn_scope = uic.scopedId(1);
                        defer fn_scope.end();
                        const vr = uic.computeVirtualRange(fn_indices.items.len, 27.0, 4);
                        if (vr.top_spacer_h > 0) uic.spacer(vr.top_spacer_h);
                        for (fn_indices.items[vr.first..vr.end]) |sidx| {
                            const sym = symbols[sidx];
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
                        if (vr.bottom_spacer_h > 0) uic.spacer(vr.bottom_spacer_h);
                    }
                }

                const has_type_syms = uic.latch(bool, type_indices.items.len > 0);
                if (has_type_syms) {
                    const type_meta = uic.fmt("{d}", .{type_indices.items.len});
                    if (uic.treeFolderNode("Types & Constants##outline_types", 0, &state.doc.outline_group_types, type_meta)) {
                        var type_scope = uic.scopedId(2);
                        defer type_scope.end();
                        const vr = uic.computeVirtualRange(type_indices.items.len, 27.0, 4);
                        if (vr.top_spacer_h > 0) uic.spacer(vr.top_spacer_h);
                        for (type_indices.items[vr.first..vr.end]) |sidx| {
                            const sym = symbols[sidx];
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
                        if (vr.bottom_spacer_h > 0) uic.spacer(vr.bottom_spacer_h);
                    }
                }
            }
        }
    }

    if (deferred_kill_f_idx) |kill_idx| {
        state.killBuffer(kill_idx);
        action.file_switched = true;
    }
    if (deferred_open_f_idx) |open_idx| {
        state.openFile(open_idx);
        action.file_switched = true;
    }
    if (deferred_refresh_ws) {
        state.refreshWorkspaceFiles(true);
        action.file_switched = true;
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
    if (matches.len == 0) {
        uic.label("No results.", null);
        return;
    }

    const vr = uic.computeVirtualRange(matches.len, 28.0, 4);
    if (vr.top_spacer_h > 0) uic.spacer(vr.top_spacer_h);

    for (matches[vr.first..vr.end]) |*m| {
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

    if (vr.bottom_spacer_h > 0) uic.spacer(vr.bottom_spacer_h);
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
