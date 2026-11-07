//! Center Editor Workbench: Multi-Tab Editor Groups, Side-by-Side Splits (`Cmd+\`),
//! Tab Closing (`Cmd+W` / `×`), Breadcrumbs, Compact Find Bar (`Cmd+F`),
//! Quick Open (`Cmd+P`), Interactive Code Editor, Markdown Split Preview, and Bottom Panel (`Cmd+J`).

const std = @import("std");
const skia = @import("skia");
const ui = @import("ui");
const state_mod = @import("../state.zig");
const commands = @import("../commands.zig");
const tasks_mod = @import("../tasks.zig");
const bottom_panel = @import("bottom_panel.zig");
const agent_panel = @import("agent_panel.zig");
const modals = @import("modals.zig");
const context_menu = @import("context_menu.zig");
const EditorState = state_mod.EditorState;

pub const buildCommandPaletteOverlay = modals.buildCommandPaletteOverlay;
pub const buildOpenWorkspacePromptOverlay = modals.buildOpenWorkspacePromptOverlay;
pub const buildSaveAsPromptOverlay = modals.buildSaveAsPromptOverlay;
pub const buildNewFolderPromptOverlay = modals.buildNewFolderPromptOverlay;
pub const buildContextMenuOverlay = context_menu.buildContextMenuOverlay;

const PendingPaneOp = union(enum) {
    none,
    split_horizontal: usize,
    split_vertical: usize,
    close_pane: usize,
    close_tab: struct { pane: usize, tab: usize },
};

const SplitLeafBuilderCtx = struct {
    state: *EditorState,
    pending_op: *PendingPaneOp,
    center_bottom: f32,
    total_avail_h: f32,

    fn buildLeaf(ctx: *@This(), pane_idx: usize, pane_count: usize, pane_w: ui.Size, pane_h: f32) void {
        buildEditorGroupPane(ctx.state, pane_idx, pane_count, pane_w, pane_h, ctx.center_bottom, ctx.total_avail_h, ctx.pending_op);
    }
};

pub fn build(state: *EditorState) void {
    const uic = &state.ui_ctx;
    state.ensureValidSplitTree();

    var scope = uic.scopedState("editor_pane");
    defer scope.end();

    const active_panel_tab = &state.doc.bottom_panel_tab;

    // Sync active pane if the user clicked inside any split pane or focused its editor widget
    const cur_pane_count = state.paneCount();
    if (uic.pass == .input) {
        if (uic.mouse_pressed or uic.right_mouse_pressed) {
            for (0..cur_pane_count) |p_idx| {
                const pr = state.pane_rects[p_idx];
                if (pr.right > pr.left and pr.bottom > pr.top and uic.isHovered(pr)) {
                    activatePane(state, p_idx);
                    break;
                }
            }
        }
        for (0..cur_pane_count) |p_idx| {
            if (uic.focused_id == state_mod.EditorState.editorWidgetIdForPane(p_idx)) {
                state.doc.split_tree.active_pane = @intCast(p_idx);
                break;
            }
        }
    }

    // Declarative global workbench shortcuts via `commands.dispatchGlobalShortcuts(...)`
    _ = commands.dispatchGlobalShortcuts(state, active_panel_tab);
    const show_find_bar = uic.latch(bool, state.doc.show_find_bar);

    // Function-key debugger shortcuts (`F5`, `F10`, `F11`, `Shift+F11`) routed to the LLDB debugger plugin
    if (uic.pass == .input and !state.isTerminalFocused()) {
        for (uic.key_events) |kev| {
            switch (kev.key) {
                .f5 => {
                    if (kev.shift) {
                        _ = state.plugins.executePluginCommandById(state, "lldb_debug.stop");
                    } else {
                        _ = state.plugins.executePluginCommandById(state, "lldb_debug.start_or_continue");
                    }
                },
                .f10 => _ = state.plugins.executePluginCommandById(state, "lldb_debug.step_over"),
                .f11 => {
                    if (kev.shift) {
                        _ = state.plugins.executePluginCommandById(state, "lldb_debug.step_out");
                    } else {
                        _ = state.plugins.executePluginCommandById(state, "lldb_debug.step_into");
                    }
                },
                else => {},
            }
        }
    }

    const agent_reserve: f32 = if (state.doc.show_agent_panel)
        std.math.clamp(state.doc.agent_panel_width, 260.0, 560.0) + 5.0
    else
        0.0;
    const center_w = @max(180.0, uic.availableWidth() - agent_reserve);

    var center = uic.column(.{
        .w = .pixels(center_w),
        .gap = 0,
        .bg_color = uic.theme.bg_canvas,
    });
    defer center.end();

    // 1. Compact Find Bar (`Cmd+F`)
    if (show_find_bar) {
        modals.buildFindBar(state, state.activeFileIndex());
    }

    // 2. Recursive Binary Split Tree of Editor Groups via `uic.splitTree(...)`
    const total_avail_h = uic.availableHeight();
    const clamped_bottom_h = std.math.clamp(state.doc.bottom_panel_height, 96.0, @max(120.0, total_avail_h - 140.0));
    const panel_h: f32 = if (state.doc.show_bottom_panel) clamped_bottom_h else 0.0;
    const groups_h = @max(100.0, total_avail_h - panel_h);

    var pending_op: PendingPaneOp = .none;
    var leaf_ctx = SplitLeafBuilderCtx{
        .state = state,
        .pending_op = &pending_op,
        .center_bottom = center.rect.bottom,
        .total_avail_h = total_avail_h,
    };
    uic.splitTree(&state.doc.split_tree, groups_h, 0.18, 0.82, &leaf_ctx, SplitLeafBuilderCtx.buildLeaf);

    switch (pending_op) {
        .none => {},
        .split_horizontal => |p| {
            state.splitPaneHorizontal(p);
            uic.invalidateWindow();
        },
        .split_vertical => |p| {
            state.splitPaneVertical(p);
            uic.invalidateWindow();
        },
        .close_pane => |p| {
            state.closeSplitPane(p);
            uic.invalidateWindow();
        },
        .close_tab => |ct| {
            state.closeTabInPane(ct.pane, ct.tab);
            uic.invalidateWindow();
        },
    }

    // 3. Optional Bottom Panel (`Cmd+J`)
    if (state.doc.show_bottom_panel) {
        const diag_file = state.activeFileIndex() orelse 0;
        const diags = state.diagnosticsForFile(diag_file);
        bottom_panel.buildBottomPanel(state, diag_file, panel_h, active_panel_tab, diags);
    }
}

const ModeLineHeight: f32 = 24.0;

fn activatePane(state: *EditorState, pane_idx: usize) void {
    const uic = &state.ui_ctx;
    const target_wid = state_mod.EditorState.editorWidgetIdForPane(pane_idx);
    if (state.doc.split_tree.active_pane != pane_idx or uic.focused_id != target_wid) {
        state.doc.split_tree.active_pane = @intCast(pane_idx);
        if (state.paneActiveFile(pane_idx)) |f_idx| {
            state.syncCursorTelemetry(f_idx);
        }
        uic.focused_id = target_wid;
        uic.invalidateWindow();
    }
}

fn buildEditorGroupPane(
    state: *EditorState,
    pane_idx: usize,
    pane_count: usize,
    pane_w: ui.Size,
    pane_h: f32,
    center_bottom: f32,
    total_avail_h: f32,
    pending_op: *PendingPaneOp,
) void {
    const uic = &state.ui_ctx;
    var pane_scope = uic.scopedId(pane_idx + 10);
    defer pane_scope.end();

    var group_col = uic.column(.{
        .w = pane_w,
        .h = .pixels(pane_h),
        .gap = 0,
        .bg_color = uic.theme.bg_canvas,
    });
    defer group_col.end();

    state.pane_rects[pane_idx] = group_col.rect;
    if (uic.pass == .input and (uic.mouse_pressed or uic.right_mouse_pressed) and uic.isHovered(group_col.rect)) {
        activatePane(state, pane_idx);
    }
    const is_active_pane = (state.activePaneIndex() == pane_idx);
    const code_area_h = @max(1.0, pane_h - ModeLineHeight);

    // 1. Active Buffer Content Area (fills top of split window directly, Emacs-style)
    if (state.paneActiveFile(pane_idx)) |file_idx| {
        state.ensureFileLoaded(file_idx);
        const active_file = state.workspaceFiles()[file_idx];
        const active_buf = &state.buffers[file_idx];
        const active_search = if (state.doc.show_find_bar)
            state.findQuery()
        else if (state.doc.show_sidebar and state.doc.active_sidebar_view == 1)
            state.workspaceSearchQuery()
        else
            "";

        {
            var code_row = uic.row(.{
                .h = .pixels(code_area_h),
                .gap = 0,
            });
            defer code_row.end();

            if (active_file.is_markdown_preview) {
                const is_scratch_src = state.isScratchMarkdownPreview(file_idx);
                const src_idx = if (is_scratch_src) 0 else state.markdownPreviewSourceIndexForBuffer(file_idx);
                if (!is_scratch_src) {
                    state.ensureFileLoaded(src_idx);
                }
                const src_key: usize = if (is_scratch_src) 0xFFFF else src_idx;
                const preview_scroll_id = uic.fmt("workbench_md_preview_{d}_{d}_{d}", .{ pane_idx, file_idx, src_key });
                var md_preview = uic.scrollPanel(preview_scroll_id, .{
                    .h = .pixels(code_area_h),
                    .padding = ui.Padding.all(18),
                    .gap = 10,
                    .bg_color = uic.theme.bg_panel,
                });
                if (uic.pass == .input and uic.mouse_pressed and uic.isHovered(md_preview.rect)) {
                    activatePane(state, pane_idx);
                }
                const target_heading = state.pending_md_heading.slice();
                const md_slice = if (is_scratch_src) state.scratch_buf.slice() else state.buffers[src_idx].slice();
                const md_res = uic.markdownEx(md_slice, .{
                    .id_salt = uic.fmt("md_prev_{d}_{d}", .{ pane_idx, file_idx }),
                    .scroll_to_heading = target_heading,
                });
                md_preview.end();
                if (uic.pass == .input) {
                    if (md_res.target_scroll_y) |target_y| {
                        const preview_scroll = uic.useState(ui.ScrollState, preview_scroll_id, .{});
                        const max_y = @max(0.0, preview_scroll.content_height - @max(1.0, code_area_h - 36.0));
                        preview_scroll.scroll_y = std.math.clamp(target_y, 0.0, max_y);
                        state.pending_md_heading.clear();
                        uic.invalidateWindow();
                    } else if (target_heading.len > 0) {
                        state.pending_md_heading.clear();
                    }
                }
                if (md_res.clicked_link) |link_url| {
                    _ = state.openLinkOrFileUrl(link_url);
                }
            } else if (active_file.is_waveform_preview or EditorState.isVcdCandidatePath(active_file.path)) {
                const is_direct_vcd = !active_file.is_waveform_preview and EditorState.isVcdCandidatePath(active_file.path);
                const src_idx = if (is_direct_vcd) file_idx else state.waveformPreviewSourceIndex();
                state.ensureFileLoaded(src_idx);
                const src_wf = state.workspaceFiles()[src_idx];
                const src_slice = state.buffers[src_idx].slice();
                const is_vcd = EditorState.isVcdCandidatePath(src_wf.path) or
                    (std.mem.indexOfPos(u8, src_slice, 0, "$var") != null and
                        std.mem.indexOfPos(u8, src_slice, 0, "$enddefinitions") != null);
                const custom_vcd = state.waveform_custom_vcd.slice();
                const vcd_src = if (is_direct_vcd and src_slice.len > 0)
                    src_slice
                else if (custom_vcd.len > 0)
                    custom_vcd
                else if (is_vcd and src_slice.len > 0)
                    src_slice
                else
                    ui.SAMPLE_COUNTER_VCD;

                const wave_id = switch (@min(pane_idx, 3)) {
                    0 => "workbench_wave_preview_0",
                    1 => "workbench_wave_preview_1",
                    2 => "workbench_wave_preview_2",
                    else => "workbench_wave_preview_3",
                };
                const wave_data = uic.parseVcdCached(vcd_src);
                const wave_state_id = uic.fmt("workbench_wave_state_{d}_{d}", .{ pane_idx, src_idx });
                const wave_view = uic.useState(ui.WaveformViewState, wave_state_id, .{});
                uic.waveformViewer(wave_id, 0.0, code_area_h, wave_data, wave_view);
                if (uic.pass == .input and uic.mouse_pressed and uic.isHovered(code_row.rect)) {
                    activatePane(state, pane_idx);
                }
            } else if (state.resolvePdfSourceForPane(pane_idx)) |pdf_src| {
                const pdf_id = switch (@min(pane_idx, 3)) {
                    0 => "workbench_pdf_preview_0",
                    1 => "workbench_pdf_preview_1",
                    2 => "workbench_pdf_preview_2",
                    else => "workbench_pdf_preview_3",
                };
                const pdf_slot = @min(pane_idx, state_mod.MaxEditorPanes - 1);
                const pdf_doc = uic.parsePdfCached(pdf_src.eff_bytes, pdf_src.eff_path);
                const pdf_view = state.pdfViewStateForPane(pane_idx, file_idx, pdf_src.is_direct_pdf);
                if (uic.pass == .input and uic.mouse_pressed and uic.isHovered(code_row.rect)) {
                    activatePane(state, pane_idx);
                }
                const pdf_res = uic.pdfViewer(pdf_id, 0.0, code_area_h, pdf_doc, pdf_view, .{
                    .file_path = pdf_src.eff_path,
                    .raw_bytes = pdf_src.eff_bytes,
                    .search_query = active_search,
                    .extra_focus_id = state_mod.EditorState.editorWidgetIdForPane(pane_idx),
                });
                state.pdf_views[pdf_slot] = pdf_view.*;
                if (pdf_res.find_requested) {
                    state.openFindBar();
                }
                if (pdf_res.copied_text) |copied| {
                    var notice_buf: [80]u8 = undefined;
                    const msg = std.fmt.bufPrint(&notice_buf, "Copied {d} byte(s) of PDF text to clipboard", .{copied.len}) catch "Copied PDF text to clipboard";
                    state.setStatusNotice(msg);
                    uic.invalidateWindow();
                }
                if (uic.rightClicked(code_row.rect)) {
                    state.openContextMenu(.pdf_viewer, pane_idx, file_idx, false);
                }
            } else if (EditorState.isImageCandidatePath(active_file.path)) {
                const img_id = switch (@min(pane_idx, 3)) {
                    0 => "workbench_image_preview_0",
                    1 => "workbench_image_preview_1",
                    2 => "workbench_image_preview_2",
                    else => "workbench_image_preview_3",
                };
                const img_slot = @min(pane_idx, state_mod.MaxEditorPanes - 1);
                const img_view: *ui.ImageViewState = if (uic.platform_ctx != null)
                    uic.useState(ui.ImageViewState, uic.fmt("workbench_img_state_{d}_{d}", .{ pane_idx, file_idx }), .{})
                else
                    &state.image_views[img_slot];
                const img_res = uic.imageViewer(img_id, 0.0, code_area_h, img_view, .{
                    .file_path = active_file.path,
                    .raw_bytes = active_buf.slice(),
                });
                state.image_views[img_slot].zoom = img_view.zoom;
                if (img_res.copied_color_hex) |hex_col| {
                    var notice_buf: [64]u8 = undefined;
                    const msg = std.fmt.bufPrint(&notice_buf, "Copied pixel color {s} to clipboard", .{hex_col}) catch "Copied pixel color";
                    state.setStatusNotice(msg);
                    uic.invalidateWindow();
                }
                if (uic.pass == .input and uic.mouse_pressed and uic.isHovered(code_row.rect)) {
                    activatePane(state, pane_idx);
                }
            } else if (EditorState.isAudioCandidatePath(active_file.path)) {
                const aud_id = switch (@min(pane_idx, 3)) {
                    0 => "workbench_audio_player_0",
                    1 => "workbench_audio_player_1",
                    2 => "workbench_audio_player_2",
                    else => "workbench_audio_player_3",
                };
                const aud_slot = @min(pane_idx, state_mod.MaxEditorPanes - 1);
                const aud_view: *ui.AudioPlayerState = if (uic.platform_ctx != null)
                    uic.useState(ui.AudioPlayerState, uic.fmt("workbench_aud_state_{d}_{d}", .{ pane_idx, file_idx }), .{})
                else
                    &state.audio_views[aud_slot];
                const aud_res = uic.audioPlayer(aud_id, 0.0, code_area_h, aud_view, .{
                    .file_path = active_file.path,
                    .raw_bytes = active_buf.slice(),
                });
                state.audio_views[aud_slot] = aud_view.*;
                if (aud_res.needs_continuous_redraw) {
                    if (uic.platform_ctx) |pctx| pctx.needs_continuous_redraw = true;
                }
                if (uic.pass == .input and uic.mouse_pressed and uic.isHovered(code_row.rect)) {
                    activatePane(state, pane_idx);
                }
            } else if (EditorState.isVideoCandidatePath(active_file.path)) {
                const vid_id = switch (@min(pane_idx, 3)) {
                    0 => "workbench_video_player_0",
                    1 => "workbench_video_player_1",
                    2 => "workbench_video_player_2",
                    else => "workbench_video_player_3",
                };
                const vid_slot = @min(pane_idx, state_mod.MaxEditorPanes - 1);
                // Always use `state.video_views[slot]` directly as the authoritative VideoPlayerState.
                // Using `useState` keyed on `file_idx` is unsafe: file indices shift when the workspace
                // file list changes (files added/removed), leaving `native_generator_handle` pointing at
                // a retained ObjC object owned by a stale state slot that then gets extracted from.
                const vid_view = &state.video_views[vid_slot];
                const vid_res = uic.videoPlayer(vid_id, 0.0, code_area_h, vid_view, .{
                    .file_path = active_file.path,
                    .raw_bytes = active_buf.slice(),
                });
                // `vid_view` is already a pointer into `state.video_views[vid_slot]`; no copy needed.
                _ = vid_res.needs_continuous_redraw; // suppress unused warning
                if (vid_res.needs_continuous_redraw) {
                    if (uic.platform_ctx) |pctx| pctx.needs_continuous_redraw = true;
                }
                if (uic.pass == .input and uic.mouse_pressed and uic.isHovered(code_row.rect)) {
                    activatePane(state, pane_idx);
                }
            } else if (active_file.is_app_preview or EditorState.isAppCandidatePath(active_file.path)) {
                const is_direct_dylib = !active_file.is_app_preview and EditorState.isAppCandidatePath(active_file.path);
                var detected_buf: [512]u8 = undefined;
                const detected_dylib = if (!is_direct_dylib) tasks_mod.detectPreviewAppDylib(state, &detected_buf) else null;
                const dylib_path = if (is_direct_dylib)
                    active_file.path
                else if (detected_dylib) |dp|
                    dp
                else
                    "";

                const app_id = switch (@min(pane_idx, 3)) {
                    0 => "workbench_app_sim_0",
                    1 => "workbench_app_sim_1",
                    2 => "workbench_app_sim_2",
                    else => "workbench_app_sim_3",
                };
                const app_slot = @min(pane_idx, state_mod.MaxEditorPanes - 1);
                const sim = &state.app_views[app_slot];
                const app_res = uic.appSimulator(app_id, 0.0, code_area_h, sim, .{
                    .dylib_path = dylib_path,
                });
                if (app_res.needs_continuous_redraw) {
                    if (uic.platform_ctx) |pctx| pctx.needs_continuous_redraw = true;
                }
                if (uic.pass == .input and uic.mouse_pressed and uic.isHovered(code_row.rect)) {
                    activatePane(state, pane_idx);
                }
            } else if (active_file.is_git_diff_preview) {
                const src_idx = state.gitDiffPreviewSourceIndex();
                const src_wf = state.workspaceFiles()[src_idx];
                const custom_diff = state.git_diff_custom_text.slice();
                const commit_sha = state.git_diff_commit.slice();
                const is_commit = commit_sha.len > 0;
                const is_staged = state.doc.git_diff_staged;
                const badge_str = if (is_commit)
                    uic.fmt("COMMIT {s}", .{commit_sha})
                else if (is_staged)
                    "STAGED"
                else
                    "WORKING TREE";
                const title_str = if (state.git_diff_title.len > 0)
                    state.git_diff_title.slice()
                else
                    src_wf.path;

                const diff_id = switch (@min(pane_idx, 3)) {
                    0 => "workbench_git_diff_0",
                    1 => "workbench_git_diff_1",
                    2 => "workbench_git_diff_2",
                    else => "workbench_git_diff_3",
                };
                const diff_view = &state.git_diff_views[@min(pane_idx, state_mod.MaxEditorPanes - 1)];
                const diff_res = uic.diffViewer(diff_id, 0.0, code_area_h, custom_diff, diff_view, .{
                    .title = title_str,
                    .badge = badge_str,
                    .staged = is_staged,
                    .is_commit_view = is_commit,
                });
                if (diff_res.refresh_requested) {
                    state.refreshActiveGitDiffContent();
                    uic.invalidateWindow();
                }
                if (diff_res.stage_toggle_requested) {
                    if (is_staged) {
                        state.unstageFile(src_idx);
                        state.doc.git_diff_staged = false;
                    } else {
                        state.stageFile(src_idx);
                        state.doc.git_diff_staged = true;
                    }
                    state.refreshActiveGitDiffContent();
                    uic.invalidateWindow();
                }
                if (diff_res.open_file_requested) {
                    state.openFileInPane(pane_idx, src_idx);
                    if (diff_res.clicked_new_line) |ln| {
                        state.buffers[src_idx].jumpToLine(ln);
                        state.doc.cursor_line = @intCast(ln);
                        state.doc.cursor_col = 1;
                    }
                    uic.invalidateWindow();
                }
                if (uic.pass == .input and uic.mouse_pressed and uic.isHovered(code_row.rect)) {
                    activatePane(state, pane_idx);
                }
            } else if (active_file.is_terminal) {
                const editor_id = state_mod.PANE_EDITOR_IDS[@min(pane_idx, state_mod.MaxEditorPanes - 1)];
                const t_slot = state.ensureTerminalSlot(active_file.terminal_slot);
                if (uic.vterm(editor_id, 0, code_area_h, &state.term_vterms[t_slot], state.font_mono)) {
                    uic.invalidateWindow();
                }
                if (uic.rightClicked(code_row.rect)) {
                    state.doc.split_tree.active_pane = @intCast(pane_idx);
                    state.openContextMenu(.terminal, pane_idx, file_idx, false);
                }
            } else if (active_file.is_agent) {
                agent_panel.buildBuffer(state, pane_idx, active_file.agent_slot, code_area_h);
            } else {
                renderCodeBufferWithSupercomplete(
                    state,
                    pane_idx,
                    pane_count,
                    is_active_pane,
                    code_area_h,
                    active_search,
                    file_idx,
                    active_buf,
                    active_file.language,
                );
            }
        }

        // 2. Emacs-Style Bottom Mode Line for this Split Window
        drawEmacsModeLine(state, pane_idx, pane_count, file_idx, is_active_pane, center_bottom, total_avail_h, pending_op);
    } else {
        // Editable *scratch* buffer when no file is open in this pane
        const active_search = if (state.doc.show_find_bar)
            state.findQuery()
        else if (state.doc.show_sidebar and state.doc.active_sidebar_view == 1)
            state.workspaceSearchQuery()
        else
            "";
        {
            var code_row = uic.row(.{
                .h = .pixels(code_area_h),
                .gap = 0,
            });
            defer code_row.end();

            renderCodeBufferWithSupercomplete(
                state,
                pane_idx,
                pane_count,
                is_active_pane,
                code_area_h,
                active_search,
                null,
                &state.scratch_buf,
                .markdown,
            );
        }
        drawEmacsModeLine(state, pane_idx, pane_count, null, is_active_pane, center_bottom, total_avail_h, pending_op);
    }
}

fn renderCodeBufferWithSupercomplete(
    state: *EditorState,
    pane_idx: usize,
    pane_count: usize,
    is_active_pane: bool,
    code_area_h: f32,
    active_search: []const u8,
    file_idx_opt: ?usize,
    buf: *ui.CodeEditorBuffer(state_mod.BufferCapacity),
    language: ui.CodeLanguage,
) void {
    const uic = &state.ui_ctx;
    const editor_id = state_mod.PANE_EDITOR_IDS[@min(pane_idx, state_mod.MaxEditorPanes - 1)];
    const sc_file_key: usize = file_idx_opt orelse 999;
    const plugin_buf_id: u32 = if (file_idx_opt) |f_idx| @intCast(f_idx) else 0xFFFF;
    const comp_items = if (is_active_pane)
        state.plugins.activeCompletionsFor(uic.arena, plugin_buf_id, buf.cursor)
    else
        &.{};
    const ghost_opt = if (is_active_pane and comp_items.len == 0)
        state.supercomplete.activeGhostFor(sc_file_key, buf.cursor, buf.edit_version)
    else
        null;

    const file_path = if (file_idx_opt) |f_idx| state.workspaceFiles()[f_idx].path else "*scratch*";
    const has_debugger = state.plugins.hasDebuggerForFile(file_path);
    const bp_lines = if (has_debugger) state.plugins.breakpointLinesForFile(uic.arena, file_path) else &.{};
    const active_dbg_line = if (has_debugger) state.plugins.activeDebugLineForFile(file_path) else null;

    const ed_res = uic.codeEditor(editor_id, 0.0, code_area_h, buf, .{
        .language = language,
        .font = state.font_code,
        .line_height = 21.0,
        .show_line_numbers = true,
        .show_breakpoint_gutter = has_debugger,
        .show_indent_guides = true,
        .show_minimap = state.doc.show_minimap and pane_count == 1,
        .show_status_bar = false,
        .syntax_highlight = true,
        .auto_close_pairs = true,
        .word_wrap = state.isBufferWordWrap(file_idx_opt),
        .search_query = active_search,
        .ghost_text = if (ghost_opt) |g| g.text else "",
        .ghost_delete_len = if (ghost_opt) |g| g.delete_len else 0,
        .completions = comp_items,
        .selected_completion = state.plugins.selected_completion,
        .breakpoint_lines = bp_lines,
        .active_debug_line = active_dbg_line,
        .is_active_pane = is_active_pane,
        .pane_index = @intCast(@min(pane_idx, state_mod.MaxEditorPanes - 1)),
    });

    if (ed_res.toggled_breakpoint_line) |bp_ln| {
        const added = state.plugins.toggleBreakpoint(file_path, bp_ln);
        state.status_notice.set(uic.fmt("{s} breakpoint at {s}:{d} ({d} total)", .{
            if (added) "Set" else "Cleared",
            std.fs.path.basename(file_path),
            bp_ln,
            state.plugins.breakpoint_count,
        }));
        uic.invalidateWindow();
    }

    const now_ms: i64 = @intCast(@import("platform").profiler.nowNs() / std.time.ns_per_ms);
    if (ed_res.completion_selection_changed) {
        state.plugins.selected_completion = ed_res.selected_completion;
        uic.invalidateWindow();
    }
    if (ed_res.completion_accepted) {
        state.plugins.clearCompletions();
        state.plugins.notifyBufferEdit(state, file_idx_opt orelse 0xFFFF);
        uic.invalidateWindow();
    } else if (ed_res.completion_dismissed) {
        state.plugins.clearCompletions();
        uic.invalidateWindow();
    } else if (ed_res.ghost_accepted) {
        state.supercomplete.onAccepted(now_ms);
    } else if (ed_res.ghost_dismissed) {
        state.supercomplete.onDismissed();
    } else if (ed_res.text_changed) {
        state.supercomplete.onUserTextChanged(
            now_ms,
            sc_file_key,
            buf.slice(),
            buf.cursor,
            buf.edit_version,
        );
        state.plugins.notifyBufferEdit(state, file_idx_opt orelse 0xFFFF);
        if (uic.platform_ctx) |pctx| pctx.needs_continuous_redraw = true;
    } else if (ed_res.cursor_changed) {
        state.supercomplete.onDismissed();
        state.plugins.clearCompletions();
    }

    if (ed_res.focused or is_active_pane) {
        state.doc.cursor_line = @intCast(ed_res.cursor_line);
        state.doc.cursor_col = @intCast(ed_res.cursor_col);
    }
    if (ed_res.save_requested) {
        if (file_idx_opt) |f_idx| {
            _ = state.saveFileToDisk(f_idx);
        } else {
            state.openSaveAsPrompt();
        }
    }
    if (ed_res.find_requested) {
        state.openFindBar();
    }
    if (ed_res.right_clicked) {
        state.doc.split_tree.active_pane = @intCast(pane_idx);
        state.openContextMenu(.code_editor, pane_idx, file_idx_opt, false);
    }
    if (ed_res.cursor_changed or ed_res.text_changed or ed_res.save_requested or ed_res.find_requested or ed_res.right_clicked or ed_res.ghost_accepted or ed_res.ghost_dismissed) {
        uic.invalidateWindow();
    }
}

/// Draws an Emacs-style Mode Line at the bottom of a split window (`-:---  README.md   18% L12   Git-main  (GFM)`).
/// Dragging the mode line vertically resizes the vertical split (or bottom panel) below this window.
fn drawEmacsModeLine(
    state: *EditorState,
    pane_idx: usize,
    pane_count: usize,
    file_idx_opt: ?usize,
    is_active_pane: bool,
    center_bottom: f32,
    total_avail_h: f32,
    pending_op: *PendingPaneOp,
) void {
    const uic = &state.ui_ctx;

    const v_split_node = state.doc.split_tree.findVerticalSplitBelowPane(pane_idx);
    const can_resize_bottom_panel = (v_split_node == null and state.doc.show_bottom_panel);
    const can_resize_vertical = (v_split_node != null or can_resize_bottom_panel);

    const bar_r = uic.nextRect(0.0, ModeLineHeight);
    var ml = uic.beginModeLine("##emacs_modeline_sash", bar_r, .{
        .is_active_pane = is_active_pane,
        .can_drag_vertical = can_resize_vertical,
    });

    // Right-aligned Split Right (`[|]`), Split Down (`[-]`), and Delete Window (`×`) controls
    if (pane_count > 1) {
        if (ml.drawRightIconAction("##close_split_btn", .close, "Delete Window")) {
            pending_op.* = .{ .close_pane = pane_idx };
        }
    }
    if (ml.drawRightIconAction("##split_down_btn", .split_down, "Split Window Below")) {
        pending_op.* = .{ .split_vertical = pane_idx };
    }
    if (ml.drawRightIconAction("##split_right_btn", .split_right, "Split Window Right")) {
        pending_op.* = .{ .split_horizontal = pane_idx };
    }

    // 0. Doom Emacs-style Window Number Badge (`1`, `2`, ...) matching `Cmd+1` / `Cmd+2` focus shortcuts
    ml.drawWindowNumberBadge(@intCast(pane_idx + 1), is_active_pane);

    const pos_color = if (is_active_pane) skia.Color.rgb(203, 213, 225) else uic.theme.text_muted;

    if (file_idx_opt) |file_idx| {
        const wfs = state.workspaceFiles();
        const file = wfs[file_idx];
        const buf = &state.buffers[file_idx];
        const dirty = state.isFileDirty(file_idx);
        const staged = state.isFileStaged(file_idx);
        const git_mod = state.isFileModifiedInGit(file_idx);
        const lc = buf.cursorLineCol();
        const total_lines = @max(@as(usize, 1), buf.lineCount());
        const pane_scroll = buf.scrollStateForPane(pane_idx);
        const scroll_line: usize = if (pane_scroll.content_height > 0.0 and pane_scroll.scroll_y > 0.5)
            @min(total_lines, @as(usize, @intFromFloat(@floor(pane_scroll.scroll_y / 21.0))) + 1)
        else if (pane_scroll.content_height > 0.0)
            1
        else
            lc.line;
        const pct: usize = if (total_lines <= 1) 100 else @min(@as(usize, 100), (scroll_line * 100) / total_lines);

        // 1. Buffer Name (`README.md`, `main.zig`) — left-click next buffer, right-click previous buffer
        ml.drawTitle(file.name, dirty, is_active_pane);

        // 2. Special Buffer Mode Badge (`[PREVIEW]`, `[WAVE]`, `[PDF]`, `[DIFF]`, `[TERM]`, `[AGENT]`)
        if (file.is_markdown_preview) {
            ml.drawBadgePill("[PREVIEW]", skia.Color.rgb(121, 192, 255), skia.Color.argb(45, 56, 139, 253), null);
        } else if (file.is_waveform_preview or EditorState.isVcdCandidatePath(file.path)) {
            ml.drawBadgePill("[WAVE]", skia.Color.rgb(52, 211, 153), skia.Color.argb(45, 16, 185, 129), null);
        } else if (file.is_pdf_preview or EditorState.isPdfCandidatePath(file.path)) {
            ml.drawBadgePill("[PDF]", skia.Color.rgb(251, 146, 60), skia.Color.argb(45, 249, 115, 22), null);
        } else if (file.is_git_diff_preview) {
            ml.drawBadgePill("[DIFF]", skia.Color.rgb(129, 140, 248), skia.Color.argb(45, 99, 102, 241), null);
        } else if (file.is_app_preview or EditorState.isAppCandidatePath(file.path)) {
            ml.drawBadgePill("[APP]", skia.Color.rgb(245, 158, 11), skia.Color.argb(45, 217, 119, 6), null);
        } else if (file.is_terminal) {
            ml.drawBadgePill("[TERM]", skia.Color.rgb(52, 211, 153), skia.Color.argb(45, 16, 185, 129), null);
        } else if (file.is_agent) {
            ml.drawBadgePill("[AGENT]", skia.Color.rgb(192, 132, 252), skia.Color.argb(45, 168, 85, 247), null);
        }

        // 3. Position & Line Number (`All L1` / `18% L12` / `100x24` for VTerm / `N msgs` for Agent)
        const t_slot: usize = if (file.is_terminal) state.ensureTerminalSlot(file.terminal_slot) else 0;
        const a_slot: usize = if (file.is_agent) state.ensureAgentSlot(file.agent_slot) else 0;
        const pos_str = if (file.is_terminal)
            uic.fmt("{d}x{d}", .{ state.term_vterms[t_slot].cols, state.term_vterms[t_slot].rows })
        else if (file.is_agent)
            (if (state.agent_sessions[a_slot].is_running_turn)
                "Streaming"
            else
                uic.fmt("{d} msgs", .{state.agent_sessions[a_slot].entry_count}))
        else if (total_lines <= 25)
            uic.fmt("All L{d}:{d}", .{ lc.line, lc.col })
        else if (scroll_line <= 1)
            uic.fmt("Top L{d}:{d}", .{ lc.line, lc.col })
        else if (scroll_line >= total_lines)
            uic.fmt("Bot L{d}:{d}", .{ lc.line, lc.col })
        else
            uic.fmt("{d}% L{d}:{d}", .{ pct, lc.line, lc.col });
        ml.drawText(pos_str, &uic.font_mono, pos_color, 14.0);

        // 4. Interactive Git branch pill (`main` / `main*` / `main+`)
        const git_str = if (staged) "main+" else if (git_mod) "main*" else "main";
        const git_res = ml.drawGitBranchPill("##modeline_git_branch", git_str, staged or git_mod, false);
        if (git_res.clicked) {
            state.openGitDiffForFile(file.path, "", staged, false);
            uic.invalidateWindow();
        }

        // 5. Major mode & directory (`(Zig · src/app)` / `(Preview · README.md)` / `(VTerm · zsh)` / `(Agent · Model)`)
        const mode_name = switch (file.language) {
            .zig => "Zig",
            .cpp => "C/C++",
            .java => "Java",
            .go => "Go",
            .systemverilog => "SystemVerilog",
            .rust => "Rust",
            .python => "Python",
            .typescript => "TypeScript",
            .vhdl => "VHDL",
            .chisel => "Chisel",
            .devicetree => "DeviceTree",
            .markdown => "GFM",
            .json => "JSON",
            .bash => "Shell",
            .plain => "Fundamental",
        };
        const is_wrapped = state.isBufferWordWrap(file_idx_opt);
        const agt_sess = if (file.is_agent) &state.agent_sessions[a_slot] else &state.agy;
        const agt_base = agt_sess.activeBaseModelLabel();
        const agt_mode_tag = switch (agt_sess.mode) {
            .plan => "Plan",
            .accept_edits => "Fast",
            .auto => "Auto",
        };
        const mode_str = if (file.is_terminal)
            (if (comptime (@import("builtin").os.tag == .windows)) "(VTerm · pwsh)" else "(VTerm · zsh)")
        else if (file.is_agent)
            uic.fmt("(Agent · {s} · {s})", .{ agt_base[0..@min(agt_base.len, 14)], agt_mode_tag })
        else if (file.is_markdown_preview)
            uic.fmt("({s} · {s})", .{
                if (file.is_bound_markdown_preview) "Pinned Preview" else "Preview",
                state.markdownPreviewSourceName(file_idx),
            })
        else if (file.is_waveform_preview or EditorState.isVcdCandidatePath(file.path))
            uic.fmt("(Waveform · {s})", .{if (file.is_waveform_preview) wfs[state.waveformPreviewSourceIndex()].name else file.name})
        else if (file.is_pdf_preview or EditorState.isPdfCandidatePath(file.path))
            uic.fmt("(PDF · Pg {d})", .{state.pdf_views[@min(pane_idx, state_mod.MaxEditorPanes - 1)].current_page + 1})
        else if (EditorState.isImageCandidatePath(file.path))
            uic.fmt("(Image · {d}%)", .{@as(u32, @intFromFloat(@round(state.image_views[@min(pane_idx, state_mod.MaxEditorPanes - 1)].zoom * 100.0)))})
        else if (EditorState.isAudioCandidatePath(file.path))
            uic.fmt("(Audio · {s})", .{state.audio_views[@min(pane_idx, state_mod.MaxEditorPanes - 1)].statusLabel()})
        else if (EditorState.isVideoCandidatePath(file.path))
            uic.fmt("(Video · {s})", .{state.video_views[@min(pane_idx, state_mod.MaxEditorPanes - 1)].statusLabel()})
        else if (file.is_git_diff_preview)
            uic.fmt("(Diff · {s})", .{wfs[state.gitDiffPreviewSourceIndex()].name})
        else if (file.is_app_preview or EditorState.isAppCandidatePath(file.path))
            uic.fmt("(App · {s})", .{state.app_views[@min(pane_idx, state_mod.MaxEditorPanes - 1)].label()})
        else if (is_wrapped)
            (if (std.mem.eql(u8, file.folder, ".")) uic.fmt("({s} · Wrap)", .{mode_name}) else uic.fmt("({s} · Wrap · {s})", .{ mode_name, file.folder }))
        else if (std.mem.eql(u8, file.folder, "."))
            uic.fmt("({s})", .{mode_name})
        else
            uic.fmt("({s} · {s})", .{ mode_name, file.folder });
        ml.drawText(mode_str, &uic.font_mono, uic.theme.text_muted, 14.0);

        // 6. Responsive right-side Antigravity Supercomplete status pill (auto-elides on narrow panes)
        if (!file.isSpecial()) {
            const sc_label = if (!state.doc.supercomplete_enabled)
                "Supercomplete Off"
            else
                "Supercomplete";
            const sc_color = if (!state.doc.supercomplete_enabled)
                skia.Color.rgb(224, 108, 117)
            else if (state.supercomplete.isConnected())
                skia.Color.rgb(115, 201, 145)
            else
                uic.theme.text_muted;
            const sc_res = ml.drawRightStatusPill("##modeline_supercomplete", sc_color, sc_label, sc_color, false);
            if (sc_res.clicked) {
                state.doc.supercomplete_enabled = !state.doc.supercomplete_enabled;
                uic.invalidateWindow();
            }
        }
    } else {
        const dirty = state.isScratchDirty();
        const lc = state.scratch_buf.cursorLineCol();
        const total_lines = @max(@as(usize, 1), state.scratch_buf.lineCount());
        const pct: usize = if (total_lines <= 1) 100 else @min(@as(usize, 100), (lc.line * 100) / total_lines);

        ml.drawTitle("*scratch*", dirty, is_active_pane);

        const pos_str = if (total_lines <= 25)
            uic.fmt("All L{d}:{d}", .{ lc.line, lc.col })
        else if (lc.line <= 1)
            uic.fmt("Top L{d}:{d}", .{ lc.line, lc.col })
        else if (lc.line >= total_lines)
            uic.fmt("Bot L{d}:{d}", .{ lc.line, lc.col })
        else
            uic.fmt("{d}% L{d}:{d}", .{ pct, lc.line, lc.col });
        ml.drawText(pos_str, &uic.font_mono, pos_color, 14.0);
        ml.drawText("(Scratch · Cmd+S to Save)", &uic.font_mono, uic.theme.text_muted, 14.0);

        const sc_label = if (!state.doc.supercomplete_enabled)
            "Supercomplete Off"
        else
            "Supercomplete";
        const sc_color = if (!state.doc.supercomplete_enabled)
            skia.Color.rgb(224, 108, 117)
        else if (state.supercomplete.isConnected())
            skia.Color.rgb(115, 201, 145)
        else
            uic.theme.text_muted;
        const sc_res = ml.drawRightStatusPill("##modeline_supercomplete", sc_color, sc_label, sc_color, false);
        if (sc_res.clicked) {
            state.doc.supercomplete_enabled = !state.doc.supercomplete_enabled;
            uic.invalidateWindow();
        }
    }

    const notice = state.statusNotice();
    if (is_active_pane and notice.len > 0) {
        ml.drawText(notice, &uic.font_mono, skia.Color.rgb(148, 163, 184), 10.0);
    }

    if (uic.pass == .input) {
        if (ml.title_click.clicked) {
            if (file_idx_opt == null and state.openBufferCount() == 0) {
                state.openSaveAsPrompt();
            } else {
                state.cyclePaneBuffer(pane_idx, 1);
            }
            uic.invalidateWindow();
        } else if (ml.title_click.right_clicked) {
            state.cyclePaneBuffer(pane_idx, -1);
            uic.invalidateWindow();
        } else if (ml.backgroundRightClicked()) {
            state.doc.split_tree.active_pane = @intCast(pane_idx);
            state.openContextMenu(.pane_modeline, pane_idx, file_idx_opt, false);
        } else if (ml.sashPressed()) {
            state.doc.split_tree.active_pane = @intCast(pane_idx);
            if (file_idx_opt) |f_idx| {
                state.syncCursorTelemetry(f_idx);
            }
            uic.focused_id = state.activeEditorWidgetId();
            uic.invalidateWindow();
        }

        if (ml.isDraggingVertical()) {
            const target_bottom_y = uic.mouse_y + ModeLineHeight * 0.5;
            if (v_split_node) |v_idx| {
                if (state.doc.split_tree.nodeVerticalBounds(@intCast(v_idx), state.pane_rects[0..pane_count], 0)) |bounds| {
                    const span_h = @max(1.0, bounds.bottom - bounds.top);
                    const new_r = (target_bottom_y - bounds.top) / span_h;
                    state.doc.split_tree.nodes[v_idx].ratio = std.math.clamp(new_r, 0.18, 0.82);
                    uic.invalidateWindow();
                }
            } else if (can_resize_bottom_panel) {
                state.doc.bottom_panel_height = std.math.clamp(
                    center_bottom - target_bottom_y,
                    96.0,
                    @max(120.0, total_avail_h - 140.0),
                );
                uic.invalidateWindow();
            }
        }
    }
}
