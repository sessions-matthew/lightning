//! Workbench Right-Click Context Menu Overlay (`buildContextMenuOverlay`) across all 14 targets:
//! `.code_editor`, `.pdf_viewer`, `.terminal`, `.explorer_file`, `.pane_modeline`, `.explorer_folder`,
//! `.outline_symbol`, `.search_match`, `.git_change`, `.git_commit`, `.plugin_item`,
//! `.problem_item`, `.agent_message`, and `.titlebar_pill`.

const std = @import("std");
const ui = @import("ui");
const state_mod = @import("../state.zig");
const commands = @import("../commands.zig");
const EditorState = state_mod.EditorState;

const CodeEditorAction = enum {
    cut,
    copy,
    paste,
    select_all,
    undo,
    redo,
    toggle_comment,
    duplicate_line,
    toggle_breakpoint,
    find_in_buffer,
    send_to_agy,
    split_right,
    split_down,
};

const PdfViewerAction = enum {
    copy,
    copy_page,
    select_all,
    clear_selection,
    find_in_pdf,
    send_to_agy,
    split_right,
    split_down,
};

const TerminalAction = enum {
    copy,
    paste,
    select_all,
    clear_terminal,
    send_sigint,
    scroll_to_bottom,
    send_to_agy,
    new_terminal,
    split_terminal_side,
};

const ExplorerFileAction = enum {
    open_file,
    open_side,
    open_below,
    new_file_in_folder,
    new_folder,
    copy_relative_path,
    send_to_agy,
    save,
    discard,
    close_buffer,
    delete,
};

const PaneModelineAction = enum {
    next_buffer,
    prev_buffer,
    split_right,
    split_below,
    move_next_split,
    save,
    kill_buffer,
    close_split,
};

const ExplorerFolderAction = enum {
    open_workspace,
    new_file,
    new_folder,
    search_in_folder,
    copy_folder_path,
    expand_all,
    collapse_all,
    refresh_workspace,
    delete,
};

const OutlineSymbolAction = enum {
    jump_to_symbol,
    open_symbol_side,
    copy_symbol_name,
    search_symbol,
    ask_agy,
};

const SearchMatchAction = enum {
    open_match,
    open_match_side,
    copy_reference,
    copy_line,
    send_to_agy,
};

const GitChangeAction = enum {
    open_file,
    open_side,
    toggle_stage,
    discard,
    copy_relative_path,
};

const GitCommitAction = enum {
    toggle_files,
    copy_hash,
    copy_subject,
    refresh_status,
};

const PluginItemAction = enum {
    toggle_enabled,
    hot_reload_all,
    open_user_folder,
    copy_plugin_id,
    copy_dylib_path,
};

const ProblemItemAction = enum {
    jump_to_line,
    fix_with_agy,
    copy_message,
};

const AgentMessageAction = enum {
    copy_message,
    insert_into_buffer,
    new_conversation,
    new_agent_side,
    handoff_terminal,
};

const TitlebarPillAction = enum {
    open_workspace,
    quick_open,
    command_palette,
    goto_symbol,
    goto_line,
    copy_active_path,
    save_as,
};

const TitlebarFileMenuAction = enum {
    new_file,
    new_folder,
    open_workspace,
    quick_open,
    save,
    save_as,
    save_all,
    revert_file,
    refresh_workspace,
    close_buffer,
    close_split,
};

const TitlebarEditMenuAction = enum {
    undo,
    redo,
    cut,
    copy,
    paste,
    select_all,
    toggle_comment,
    duplicate_line,
    find_in_file,
    find_in_workspace,
    goto_line,
    goto_symbol,
};

const TitlebarViewMenuAction = enum {
    command_palette,
    toggle_sidebar,
    toggle_terminal_panel,
    toggle_agent_panel,
    toggle_minimap,
    toggle_word_wrap,
    split_right,
    split_down,
    new_terminal_buffer,
    new_agent_buffer,
    open_markdown_preview,
    open_git_diff_preview,
    toggle_dirty_overlay,
};

/// Renders and dispatches the active right-click context menu overlay across the Workbench.
pub fn buildContextMenuOverlay(state: *EditorState) void {
    if (!state.context_menu.open or state.context_menu_target == .none) return;
    const uic = &state.ui_ctx;
    var scope = uic.scopedState("editor_pane");
    defer scope.end();

    const wfs = state.workspaceFiles();
    switch (state.context_menu_target) {
        .none => {},
        .code_editor => {
            const Item = ui.ActionMenuItem(CodeEditorAction);
            const p_idx = @min(state.context_menu_pane, state.paneCount() - 1);
            const f_opt = state.context_menu_file;
            const f_path = if (f_opt) |fi| wfs[fi % wfs.len].path else "*scratch*";
            const can_debug_file = state.plugins.hasDebuggerForFile(f_path);
            const buf = if (f_opt) |fi| &state.buffers[fi % wfs.len] else &state.scratch_buf;
            const lang: ui.CodeLanguage = if (f_opt) |fi| wfs[fi % wfs.len].language else .markdown;
            const has_sel = buf.hasSelection();
            const can_split = state.paneCount() < state_mod.MaxEditorPanes;
            const items = [_]Item{
                Item.itemOpts(.cut, "Cut", "Cmd+X", .{ .disabled = !has_sel }),
                Item.itemOpts(.copy, "Copy", "Cmd+C", .{ .disabled = !has_sel }),
                Item.item(.paste, "Paste", "Cmd+V"),
                Item.itemOpts(.select_all, "Select All", "Cmd+A", .{ .disabled = buf.len == 0 }),
                Item.sep(),
                Item.itemOpts(.undo, "Undo", "Cmd+Z", .{ .disabled = buf.undo_pos == 0 }),
                Item.itemOpts(.redo, "Redo", "Shift+Cmd+Z", .{ .disabled = buf.undo_pos >= buf.undo_len }),
                Item.sep(),
                Item.item(.toggle_comment, "Toggle Line Comment", "Cmd+/"),
                Item.item(.duplicate_line, "Duplicate Line", "Cmd+D"),
                Item.itemOpts(.toggle_breakpoint, "Toggle Breakpoint", "F9", .{ .disabled = !can_debug_file }),
                Item.item(.find_in_buffer, "Find in File...", "Cmd+F"),
                Item.sep(),
                Item.item(.send_to_agy, if (has_sel) "Send Selection to Antigravity" else "Send File to Antigravity", "Cmd+L"),
                Item.sep(),
                Item.itemOpts(.split_right, "Split Editor Right", "Cmd+\\", .{ .disabled = !can_split }),
                Item.itemOpts(.split_down, "Split Editor Down", "Shift+Cmd+\\", .{ .disabled = !can_split }),
            };
            if (uic.contextMenuActions(CodeEditorAction, "workbench_ctx_code_editor", &state.context_menu, &items)) |act| {
                state.doc.split_tree.active_pane = @intCast(p_idx);
                uic.focused_id = state.activeEditorWidgetId();
                switch (act) {
                    .cut => {
                        if (buf.cutSelection()) {
                            if (uic.platform_ctx) |pctx| {
                                const clip = buf.clipboardSlice();
                                if (clip.len > 0) _ = pctx.setClipboardText(clip);
                            }
                            state.plugins.notifyBufferEdit(state, if (f_opt) |fi| @intCast(fi) else 0xFFFF);
                        }
                    },
                    .copy => {
                        buf.copySelection();
                        if (uic.platform_ctx) |pctx| {
                            const clip = buf.clipboardSlice();
                            if (clip.len > 0) _ = pctx.setClipboardText(clip);
                        }
                    },
                    .paste => {
                        if (uic.platform_ctx) |pctx| {
                            if (pctx.getClipboardTextAlloc(uic.arena)) |sys_clip| {
                                buf.setClipboardSlice(sys_clip);
                            }
                        }
                        if (buf.pasteClipboard()) {
                            state.plugins.notifyBufferEdit(state, if (f_opt) |fi| @intCast(fi) else 0xFFFF);
                        }
                    },
                    .select_all => buf.selectAll(),
                    .undo => _ = buf.undo(),
                    .redo => _ = buf.redo(),
                    .toggle_comment => _ = buf.toggleLineComment(lang.commentPrefix()),
                    .duplicate_line => _ = buf.duplicateCurrentLine(),
                    .toggle_breakpoint => if (can_debug_file) {
                        const cur_ln: u32 = @intCast(buf.cursorLineCol().line);
                        _ = buf.toggleBreakpoint(cur_ln);
                        const added = state.plugins.toggleBreakpoint(f_path, cur_ln);
                        state.status_notice.set(uic.fmt("{s} breakpoint at {s}:{d}", .{
                            if (added) "Set" else "Cleared",
                            std.fs.path.basename(f_path),
                            cur_ln,
                        }));
                    },
                    .find_in_buffer => state.openFindBar(),
                    .send_to_agy => state.sendAgySelectionOrFilePrompt("Explain and review this code."),
                    .split_right => state.splitPaneHorizontal(p_idx),
                    .split_down => state.splitPaneVertical(p_idx),
                }
                uic.invalidateWindow();
            }
        },
        .pdf_viewer => {
            const Item = ui.ActionMenuItem(PdfViewerAction);
            const p_idx = @min(state.context_menu_pane, state.paneCount() - 1);
            const pdf_slot = @min(p_idx, state_mod.MaxEditorPanes - 1);
            const pdf_src = state.resolvePdfSourceForPane(p_idx) orelse state_mod.EditorState.PdfPaneSource{
                .file_idx = state.context_menu_file orelse 0,
                .eff_path = "",
                .eff_bytes = ui.SAMPLE_PDF_DOC,
                .is_direct_pdf = false,
            };
            const pdf_doc = uic.parsePdfCached(pdf_src.eff_bytes, pdf_src.eff_path);
            const pdf_view = state.pdfViewStateForPane(p_idx, pdf_src.file_idx, pdf_src.is_direct_pdf);
            const has_sel = pdf_view.hasSelection();
            const can_split = state.paneCount() < state_mod.MaxEditorPanes;
            const items = [_]Item{
                Item.itemOpts(.copy, "Copy Selection", "Cmd+C", .{ .disabled = !has_sel }),
                Item.item(.copy_page, "Copy Current Page Text", ""),
                Item.item(.select_all, "Select All", "Cmd+A"),
                Item.itemOpts(.clear_selection, "Clear Selection", "Esc", .{ .disabled = !has_sel }),
                Item.sep(),
                Item.item(.find_in_pdf, "Find in PDF...", "Cmd+F"),
                Item.item(.send_to_agy, if (has_sel) "Send Selection to Antigravity" else "Send Page to Antigravity", "Cmd+L"),
                Item.sep(),
                Item.itemOpts(.split_right, "Split Editor Right", "Cmd+\\", .{ .disabled = !can_split }),
                Item.itemOpts(.split_down, "Split Editor Down", "Shift+Cmd+\\", .{ .disabled = !can_split }),
            };
            if (uic.contextMenuActions(PdfViewerAction, "workbench_ctx_pdf_viewer", &state.context_menu, &items)) |act| {
                state.doc.split_tree.active_pane = @intCast(p_idx);
                uic.focused_id = state.activeEditorWidgetId();
                switch (act) {
                    .copy => {
                        if (pdf_view.copySelectionWithSourceAlloc(pdf_doc, pdf_src.eff_bytes, pdf_src.eff_path, uic.arena)) |copied| {
                            if (uic.platform_ctx) |pctx| _ = pctx.setClipboardText(copied);
                            var notice_buf: [80]u8 = undefined;
                            const msg = std.fmt.bufPrint(&notice_buf, "Copied {d} byte(s) of PDF text to clipboard", .{copied.len}) catch "Copied PDF text to clipboard";
                            state.setStatusNotice(msg);
                        }
                    },
                    .copy_page => {
                        var page_tmp = pdf_view.*;
                        page_tmp.selectPageWithSource(pdf_doc, pdf_view.current_page, pdf_src.eff_bytes, pdf_src.eff_path);
                        if (page_tmp.copySelectionWithSourceAlloc(pdf_doc, pdf_src.eff_bytes, pdf_src.eff_path, uic.arena)) |copied| {
                            if (uic.platform_ctx) |pctx| _ = pctx.setClipboardText(copied);
                            var notice_buf: [80]u8 = undefined;
                            const msg = std.fmt.bufPrint(&notice_buf, "Copied page {d} ({d} bytes) to clipboard", .{ pdf_view.current_page + 1, copied.len }) catch "Copied PDF page to clipboard";
                            state.setStatusNotice(msg);
                        }
                    },
                    .select_all => {
                        pdf_view.selectAll(pdf_doc);
                        state.pdf_views[pdf_slot] = pdf_view.*;
                    },
                    .clear_selection => {
                        pdf_view.clearSelection();
                        state.pdf_views[pdf_slot] = pdf_view.*;
                    },
                    .find_in_pdf => state.openFindBar(),
                    .send_to_agy => state.sendAgySelectionOrFilePrompt("Summarize and explain this PDF section."),
                    .split_right => state.splitPaneHorizontal(p_idx),
                    .split_down => state.splitPaneVertical(p_idx),
                }
                uic.invalidateWindow();
            }
        },
        .terminal => {
            const Item = ui.ActionMenuItem(TerminalAction);
            const is_bot = state.context_menu_is_bottom_term;
            const p_idx = @min(state.context_menu_pane, state.paneCount() - 1);
            const f_opt = state.context_menu_file;
            const vt: *ui.VTerm = if (is_bot)
                &state.vterm
            else if (f_opt) |fi| blk: {
                const wf = wfs[fi % wfs.len];
                const t_slot = state.ensureTerminalSlot(wf.terminal_slot);
                break :blk &state.term_vterms[t_slot];
            } else &state.vterm;

            const has_sel = vt.hasSelection();
            const items = [_]Item{
                Item.itemOpts(.copy, "Copy", "Cmd+C", .{ .disabled = !has_sel }),
                Item.item(.paste, "Paste", "Cmd+V"),
                Item.item(.select_all, "Select All", "Cmd+A"),
                Item.sep(),
                Item.item(.clear_terminal, "Clear Terminal", "Cmd+K / Ctrl+L"),
                Item.item(.send_sigint, "Send Interrupt (SIGINT)", "Ctrl+C"),
                Item.itemOpts(.scroll_to_bottom, "Scroll to Bottom", "", .{ .disabled = vt.scroll_offset == 0 }),
                Item.sep(),
                Item.itemOpts(.send_to_agy, "Send Selection to Antigravity", "Cmd+L", .{ .disabled = !has_sel }),
                Item.sep(),
                Item.item(.new_terminal, "New Terminal Buffer", "Ctrl+Shift+`"),
                Item.itemOpts(.split_terminal_side, "Split Terminal to the Side", "", .{ .disabled = state.paneCount() >= state_mod.MaxEditorPanes }),
            };
            if (uic.contextMenuActions(TerminalAction, "workbench_ctx_terminal", &state.context_menu, &items)) |act| {
                uic.focused_id = if (is_bot) ui.id("workbench_vterm") else state_mod.EditorState.editorWidgetIdForPane(p_idx);
                switch (act) {
                    .copy => {
                        if (vt.copySelectionAlloc(uic.arena)) |copied| {
                            if (uic.platform_ctx) |pctx| {
                                _ = pctx.setClipboardText(copied);
                            }
                        }
                    },
                    .paste => {
                        if (uic.platform_ctx) |pctx| {
                            if (pctx.getClipboardTextAlloc(uic.arena)) |clip| {
                                vt.pasteText(clip);
                            }
                        }
                    },
                    .select_all => vt.selectAll(),
                    .clear_terminal => {
                        vt.clearSelection();
                        vt.scrollback_count = 0;
                        vt.scrollback_head = 0;
                        vt.scroll_offset = 0;
                        vt.writeInput("\x0c");
                    },
                    .send_sigint => {
                        vt.clearSelection();
                        vt.writeInput("\x03");
                    },
                    .scroll_to_bottom => vt.scroll_offset = 0,
                    .send_to_agy => state.sendAgySelectionOrFilePrompt("Analyze this terminal output."),
                    .new_terminal => state.createTerminalBuffer(false),
                    .split_terminal_side => state.createTerminalBuffer(true),
                }
                uic.invalidateWindow();
            }
        },
        .explorer_file => {
            const Item = ui.ActionMenuItem(ExplorerFileAction);
            const f_idx = (state.context_menu_file orelse 0) % wfs.len;
            const wf = wfs[f_idx];
            const is_dirty = state.isFileDirty(f_idx);
            const is_open = state.isBufferOpen(f_idx);
            const is_spec = wf.isSpecial();
            const can_split = state.paneCount() < state_mod.MaxEditorPanes;
            const items = [_]Item{
                Item.item(.open_file, "Open File", "Enter"),
                Item.itemOpts(.open_side, "Open to the Side", "Cmd+\\", .{ .disabled = !can_split }),
                Item.itemOpts(.open_below, "Open Below", "Shift+Cmd+\\", .{ .disabled = !can_split }),
                Item.sep(),
                Item.itemOpts(.new_file_in_folder, "New File in Folder...", "", .{ .disabled = is_spec }),
                Item.itemOpts(.new_folder, "New Folder...", "", .{ .disabled = is_spec }),
                Item.sep(),
                Item.item(.copy_relative_path, "Copy Relative Path", ""),
                Item.itemOpts(.send_to_agy, "Send File to Antigravity", "", .{ .disabled = is_spec }),
                Item.sep(),
                Item.itemOpts(.save, "Save File", "Cmd+S", .{ .disabled = is_spec or !is_dirty }),
                Item.itemOpts(.discard, "Revert / Discard Changes", "", .{ .disabled = is_spec or !is_dirty, .danger = true }),
                Item.itemOpts(.close_buffer, "Close / Kill Buffer", "Cmd+W", .{ .disabled = !is_open }),
                Item.itemOpts(.delete, "Delete File", "", .{ .disabled = is_spec, .danger = true }),
            };
            if (uic.contextMenuActions(ExplorerFileAction, "workbench_ctx_explorer", &state.context_menu, &items)) |act| {
                switch (act) {
                    .open_file => state.openFile(f_idx),
                    .open_side => {
                        state.ensureBufferInOpenList(f_idx);
                        state.splitPaneDirection(state.activePaneIndex(), false, false, f_idx, null);
                    },
                    .open_below => {
                        state.ensureBufferInOpenList(f_idx);
                        state.splitPaneDirection(state.activePaneIndex(), true, false, f_idx, null);
                    },
                    .new_file_in_folder => state.openSaveAsPromptInFolder(wf.folder),
                    .new_folder => state.openNewFolderPromptInFolder(wf.folder),
                    .copy_relative_path => {
                        if (uic.platform_ctx) |pctx| {
                            _ = pctx.setClipboardText(wf.path);
                        }
                        state.setStatusNotice("Copied relative file path to clipboard");
                    },
                    .send_to_agy => {
                        state.openFile(f_idx);
                        state.sendAgySelectionOrFilePrompt("Summarize and review this file.");
                    },
                    .save => _ = state.saveFileToDisk(f_idx),
                    .discard => state.discardFileChanges(f_idx),
                    .close_buffer => state.killBuffer(f_idx),
                    .delete => _ = state.deleteWorkspaceFile(f_idx),
                }
                uic.invalidateWindow();
            }
        },
        .pane_modeline => {
            const Item = ui.ActionMenuItem(PaneModelineAction);
            const p_idx = @min(state.context_menu_pane, state.paneCount() - 1);
            const f_opt = state.context_menu_file;
            const open_cnt = state.openBufferCount();
            const can_split = state.paneCount() < state_mod.MaxEditorPanes;
            const items = [_]Item{
                Item.itemOpts(.next_buffer, "Next Buffer", "Click Name", .{ .disabled = open_cnt <= 1 }),
                Item.itemOpts(.prev_buffer, "Previous Buffer", "Right-Click Name", .{ .disabled = open_cnt <= 1 }),
                Item.sep(),
                Item.itemOpts(.split_right, "Split Window Right", "Cmd+\\", .{ .disabled = !can_split }),
                Item.itemOpts(.split_below, "Split Window Below", "Shift+Cmd+\\", .{ .disabled = !can_split }),
                Item.itemOpts(.move_next_split, "Move Buffer to Next Split", "Alt+Cmd+Right", .{ .disabled = state.paneCount() <= 1 or f_opt == null }),
                Item.sep(),
                Item.item(.save, "Save Buffer", "Cmd+S"),
                Item.itemOpts(.kill_buffer, "Kill Buffer", "", .{ .disabled = f_opt == null, .danger = true }),
                Item.itemOpts(.close_split, "Close Split Window", "Cmd+W", .{ .disabled = state.paneCount() <= 1, .danger = true }),
            };
            if (uic.contextMenuActions(PaneModelineAction, "workbench_ctx_modeline", &state.context_menu, &items)) |act| {
                state.doc.split_tree.active_pane = @intCast(p_idx);
                switch (act) {
                    .next_buffer => state.cyclePaneBuffer(p_idx, 1),
                    .prev_buffer => state.cyclePaneBuffer(p_idx, -1),
                    .split_right => state.splitPaneHorizontal(p_idx),
                    .split_below => state.splitPaneVertical(p_idx),
                    .move_next_split => {
                        if (state.paneCount() > 1) {
                            const next_p = (p_idx + 1) % state.paneCount();
                            state.moveTabBetweenPanes(p_idx, 0, next_p);
                        }
                    },
                    .save => {
                        if (f_opt) |fi| {
                            _ = state.saveFileToDisk(fi);
                        } else {
                            state.openSaveAsPrompt();
                        }
                    },
                    .kill_buffer => {
                        if (f_opt) |fi| state.killBuffer(fi);
                    },
                    .close_split => state.closeSplitPane(p_idx),
                }
                uic.invalidateWindow();
            }
        },
        .explorer_folder => {
            const Item = ui.ActionMenuItem(ExplorerFolderAction);
            const folder = state.context_menu_folder.slice();
            const is_root = (folder.len == 0 or std.mem.eql(u8, folder, "."));
            const items = [_]Item{
                Item.item(.open_workspace, "Open Workspace Folder...", "Cmd+O"),
                Item.item(.new_file, if (is_root) "New File in Workspace..." else "New File in Folder...", "Shift+Cmd+S"),
                Item.item(.new_folder, if (is_root) "New Folder in Workspace..." else "New Folder in Folder...", ""),
                Item.sep(),
                Item.item(.search_in_folder, "Search in Folder...", "Shift+Cmd+F"),
                Item.item(.copy_folder_path, "Copy Folder Path", ""),
                Item.sep(),
                Item.item(.expand_all, "Expand All Folders", ""),
                Item.item(.collapse_all, "Collapse All Folders", ""),
                Item.item(.refresh_workspace, "Refresh Workspace Files", ""),
                Item.sep(),
                Item.itemOpts(.delete, "Delete Folder", "", .{ .disabled = is_root, .danger = true }),
            };
            if (uic.contextMenuActions(ExplorerFolderAction, "workbench_ctx_explorer_folder", &state.context_menu, &items)) |act| {
                switch (act) {
                    .open_workspace => state.openWorkspacePrompt(),
                    .new_file => state.openSaveAsPromptInFolder(folder),
                    .new_folder => state.openNewFolderPromptInFolder(folder),
                    .search_in_folder => {
                        state.doc.show_sidebar = true;
                        state.doc.active_sidebar_view = 1;
                        state.workspace_search.set(if (is_root) "" else folder);
                        uic.focusAndSelectAll(ui.scopedIdPath(&.{ "vscode_workbench", "explorer_sidebar" }, "##workspace_search_input"));
                    },
                    .copy_folder_path => {
                        if (uic.platform_ctx) |pctx| {
                            _ = pctx.setClipboardText(if (is_root) state.workspaceRoot() else folder);
                        }
                        state.setStatusNotice("Copied folder path to clipboard");
                    },
                    .expand_all => state.setAllFolderNodesExpanded(true),
                    .collapse_all => state.setAllFolderNodesExpanded(false),
                    .refresh_workspace => state.refreshWorkspaceFiles(true),
                    .delete => _ = state.deleteWorkspaceDirectory(folder),
                }
                uic.invalidateWindow();
            }
        },
        .outline_symbol => {
            const Item = ui.ActionMenuItem(OutlineSymbolAction);
            const f_idx = (state.context_menu_file orelse 0) % wfs.len;
            const sym_line = @max(@as(usize, 1), state.context_menu_line);
            const sym_name = state.context_menu_label.slice();
            const no_sym = (sym_name.len == 0);
            const items = [_]Item{
                Item.item(.jump_to_symbol, "Jump to Symbol", "Enter"),
                Item.itemOpts(.open_symbol_side, "Open Symbol to the Side", "Cmd+\\", .{ .disabled = state.paneCount() >= state_mod.MaxEditorPanes }),
                Item.sep(),
                Item.itemOpts(.copy_symbol_name, "Copy Symbol Name", "", .{ .disabled = no_sym }),
                Item.itemOpts(.search_symbol, "Search Symbol in Workspace", "Shift+Cmd+F", .{ .disabled = no_sym }),
                Item.itemOpts(.ask_agy, "Ask Antigravity About Symbol", "Cmd+L", .{ .disabled = no_sym }),
            };
            if (uic.contextMenuActions(OutlineSymbolAction, "workbench_ctx_outline_sym", &state.context_menu, &items)) |act| {
                switch (act) {
                    .jump_to_symbol => {
                        state.openFile(f_idx);
                        state.buffers[f_idx].jumpToLine(sym_line);
                        state.doc.cursor_line = @intCast(sym_line);
                        state.doc.cursor_col = 1;
                        uic.focused_id = state.activeEditorWidgetId();
                    },
                    .open_symbol_side => {
                        state.ensureBufferInOpenList(f_idx);
                        state.splitPaneDirection(state.activePaneIndex(), false, false, f_idx, null);
                        state.buffers[f_idx].jumpToLine(sym_line);
                        state.doc.cursor_line = @intCast(sym_line);
                    },
                    .copy_symbol_name => {
                        if (uic.platform_ctx) |pctx| {
                            _ = pctx.setClipboardText(sym_name);
                        }
                        state.setStatusNotice("Copied symbol name to clipboard");
                    },
                    .search_symbol => {
                        state.doc.show_sidebar = true;
                        state.doc.active_sidebar_view = 1;
                        state.workspace_search.set(sym_name);
                        uic.focusAndSelectAll(ui.scopedIdPath(&.{ "vscode_workbench", "explorer_sidebar" }, "##workspace_search_input"));
                    },
                    .ask_agy => {
                        state.openFile(f_idx);
                        state.buffers[f_idx].jumpToLine(sym_line);
                        state.doc.cursor_line = @intCast(sym_line);
                        state.sendAgySelectionOrFilePrompt(uic.fmt("Explain the symbol `{s}` at line {d}.", .{ sym_name, sym_line }));
                    },
                }
                uic.invalidateWindow();
            }
        },
        .search_match => {
            const Item = ui.ActionMenuItem(SearchMatchAction);
            const f_idx = (state.context_menu_file orelse 0) % wfs.len;
            const wf = wfs[f_idx];
            const match_line = @max(@as(usize, 1), state.context_menu_line);
            const snippet = state.context_menu_label.slice();
            const items = [_]Item{
                Item.item(.open_match, "Open Match", "Enter"),
                Item.itemOpts(.open_match_side, "Open Match to the Side", "Cmd+\\", .{ .disabled = state.paneCount() >= state_mod.MaxEditorPanes }),
                Item.sep(),
                Item.item(.copy_reference, "Copy File:Line Reference", ""),
                Item.itemOpts(.copy_line, "Copy Matched Line", "", .{ .disabled = snippet.len == 0 }),
                Item.item(.send_to_agy, "Send Match to Antigravity", "Cmd+L"),
            };
            if (uic.contextMenuActions(SearchMatchAction, "workbench_ctx_search_match", &state.context_menu, &items)) |act| {
                switch (act) {
                    .open_match => {
                        state.openFile(f_idx);
                        state.buffers[f_idx].jumpToLineAndHighlight(match_line, state.workspaceSearchQuery());
                        const cur_lc = state.buffers[f_idx].cursorLineCol();
                        state.doc.cursor_line = @intCast(cur_lc.line);
                        state.doc.cursor_col = @intCast(cur_lc.col);
                        uic.focused_id = state.activeEditorWidgetId();
                    },
                    .open_match_side => {
                        state.ensureBufferInOpenList(f_idx);
                        state.splitPaneDirection(state.activePaneIndex(), false, false, f_idx, null);
                        state.buffers[f_idx].jumpToLineAndHighlight(match_line, state.workspaceSearchQuery());
                        const cur_lc = state.buffers[f_idx].cursorLineCol();
                        state.doc.cursor_line = @intCast(cur_lc.line);
                        state.doc.cursor_col = @intCast(cur_lc.col);
                    },
                    .copy_reference => {
                        const ref_str = uic.fmt("{s}:{d}", .{ wf.path, match_line });
                        if (uic.platform_ctx) |pctx| {
                            _ = pctx.setClipboardText(ref_str);
                        }
                        state.setStatusNotice("Copied file:line reference");
                    },
                    .copy_line => {
                        if (uic.platform_ctx) |pctx| {
                            _ = pctx.setClipboardText(snippet);
                        }
                        state.setStatusNotice("Copied matched line to clipboard");
                    },
                    .send_to_agy => {
                        state.openFile(f_idx);
                        state.buffers[f_idx].jumpToLineAndHighlight(match_line, state.workspaceSearchQuery());
                        const cur_lc = state.buffers[f_idx].cursorLineCol();
                        state.doc.cursor_line = @intCast(cur_lc.line);
                        state.doc.cursor_col = @intCast(cur_lc.col);
                        state.sendAgySelectionOrFilePrompt(uic.fmt("Examine `{s}:{d}`: `{s}`", .{ wf.path, match_line, snippet }));
                    },
                }
                uic.invalidateWindow();
            }
        },
        .git_change => {
            const Item = ui.ActionMenuItem(GitChangeAction);
            const f_idx = (state.context_menu_file orelse 0) % wfs.len;
            const wf = wfs[f_idx];
            const is_staged = state.context_menu_is_staged;
            const items = [_]Item{
                Item.item(.open_file, "Open File", "Enter"),
                Item.itemOpts(.open_side, "Open to the Side", "Cmd+\\", .{ .disabled = state.paneCount() >= state_mod.MaxEditorPanes }),
                Item.sep(),
                Item.item(.toggle_stage, if (is_staged) "Unstage File" else "Stage File", if (is_staged) "-" else "+"),
                Item.itemOpts(.discard, "Discard Changes", "↺", .{ .disabled = is_staged, .danger = true }),
                Item.sep(),
                Item.item(.copy_relative_path, "Copy Relative Path", ""),
            };
            if (uic.contextMenuActions(GitChangeAction, "workbench_ctx_git_change", &state.context_menu, &items)) |act| {
                switch (act) {
                    .open_file => state.openFile(f_idx),
                    .open_side => {
                        state.ensureBufferInOpenList(f_idx);
                        state.splitPaneDirection(state.activePaneIndex(), false, false, f_idx, null);
                    },
                    .toggle_stage => {
                        if (is_staged) state.unstageFile(f_idx) else state.stageFile(f_idx);
                    },
                    .discard => state.discardFileChanges(f_idx),
                    .copy_relative_path => {
                        if (uic.platform_ctx) |pctx| {
                            _ = pctx.setClipboardText(wf.path);
                        }
                        state.setStatusNotice("Copied relative file path to clipboard");
                    },
                }
                uic.invalidateWindow();
            }
        },
        .git_commit => {
            const Item = ui.ActionMenuItem(GitCommitAction);
            const c_idx = if (state.git_commit_count > 0)
                @min(state.context_menu_index, state.git_commit_count - 1)
            else
                0;
            const has_commit = (state.git_commit_count > 0);
            const commit = &state.git_commits[c_idx];
            const items = [_]Item{
                Item.itemOpts(.toggle_files, "Toggle Commit Files", "Enter", .{ .disabled = !has_commit }),
                Item.sep(),
                Item.itemOpts(.copy_hash, "Copy Commit Hash", "", .{ .disabled = !has_commit }),
                Item.itemOpts(.copy_subject, "Copy Commit Subject", "", .{ .disabled = !has_commit }),
                Item.sep(),
                Item.item(.refresh_status, "Refresh Git Status", ""),
            };
            if (uic.contextMenuActions(GitCommitAction, "workbench_ctx_git_commit", &state.context_menu, &items)) |act| {
                switch (act) {
                    .toggle_files => {
                        if (has_commit) state.doc.commit_expanded[c_idx] = !state.doc.commit_expanded[c_idx];
                    },
                    .copy_hash => {
                        if (has_commit) {
                            if (uic.platform_ctx) |pctx| _ = pctx.setClipboardText(commit.hash());
                            state.setStatusNotice("Copied commit hash to clipboard");
                        }
                    },
                    .copy_subject => {
                        if (has_commit) {
                            if (uic.platform_ctx) |pctx| _ = pctx.setClipboardText(commit.subject());
                            state.setStatusNotice("Copied commit subject to clipboard");
                        }
                    },
                    .refresh_status => state.refreshGitStatus(),
                }
                uic.invalidateWindow();
            }
        },
        .plugin_item => {
            const Item = ui.ActionMenuItem(PluginItemAction);
            const p_cnt = state.plugins.plugin_count;
            const p_idx = if (p_cnt > 0) @min(state.context_menu_index, p_cnt - 1) else 0;
            const has_p = (p_cnt > 0 and state.plugins.plugins[p_idx].active);
            const is_en = if (has_p) state.plugins.plugins[p_idx].enabled else false;
            const is_user = if (has_p) state.plugins.plugins[p_idx].is_user_override else false;
            const items = [_]Item{
                Item.itemOpts(.toggle_enabled, if (is_en) "Disable Plugin" else "Enable Plugin", "", .{ .disabled = !has_p }),
                Item.item(.hot_reload_all, "Hot-Reload All Plugins", ""),
                Item.item(.open_user_folder, "Open User Plugins Folder (~/.lightning/plugins)", ""),
                Item.sep(),
                Item.info(if (is_user) "Origin: ~/.lightning/plugins [User Override]" else "Origin: Bundled / Workspace"),
                Item.itemOpts(.copy_plugin_id, "Copy Plugin ID", "", .{ .disabled = !has_p }),
                Item.itemOpts(.copy_dylib_path, "Copy .dylib Path", "", .{ .disabled = !has_p }),
            };
            if (uic.contextMenuActions(PluginItemAction, "workbench_ctx_plugin_item", &state.context_menu, &items)) |act| {
                switch (act) {
                    .toggle_enabled => {
                        if (has_p) state.plugins.setPluginEnabled(state, p_idx, !state.plugins.plugins[p_idx].enabled);
                    },
                    .hot_reload_all => {
                        _ = state.plugins.scanAndReloadPlugins(state, true);
                        state.setStatusNotice("Scanned plugins (~/.lightning/plugins, zig-out/plugins)");
                    },
                    .open_user_folder => {
                        _ = state.plugins.ensureUserPluginsDirectoryExists();
                        var dir_buf: [256:0]u8 = @splat(0);
                        if (state.plugins.userPluginsDirectory(&dir_buf)) |dir_slice| {
                            const io = std.Options.debug_io;
                            var child = std.process.spawn(io, .{
                                .argv = &.{ "open", dir_slice },
                                .stdin = .ignore,
                                .stdout = .ignore,
                                .stderr = .ignore,
                            }) catch null;
                            if (child) |*c| _ = c.wait(io) catch null;
                            state.setStatusNotice("Opened ~/.lightning/plugins");
                        }
                    },
                    .copy_plugin_id => {
                        if (has_p) {
                            if (uic.platform_ctx) |pctx| _ = pctx.setClipboardText(state.plugins.plugins[p_idx].id.slice());
                            state.setStatusNotice("Copied plugin ID to clipboard");
                        }
                    },
                    .copy_dylib_path => {
                        if (has_p) {
                            const p = &state.plugins.plugins[p_idx];
                            const dpath = p.dylib_path_buf[0..p.dylib_path_len];
                            if (uic.platform_ctx) |pctx| _ = pctx.setClipboardText(dpath);
                            state.setStatusNotice("Copied plugin .dylib path");
                        }
                    },
                }
                uic.invalidateWindow();
            }
        },
        .problem_item => {
            const Item = ui.ActionMenuItem(ProblemItemAction);
            const f_idx = (state.context_menu_file orelse 0) % wfs.len;
            const diag_line = @max(@as(usize, 1), state.context_menu_line);
            const diag_msg = state.context_menu_label.slice();
            const items = [_]Item{
                Item.item(.jump_to_line, "Jump to Problem Line", "Enter"),
                Item.item(.fix_with_agy, "Fix with Antigravity Agent", "Cmd+L"),
                Item.sep(),
                Item.itemOpts(.copy_message, "Copy Diagnostic Message", "", .{ .disabled = diag_msg.len == 0 }),
            };
            if (uic.contextMenuActions(ProblemItemAction, "workbench_ctx_problem_item", &state.context_menu, &items)) |act| {
                switch (act) {
                    .jump_to_line => {
                        state.openFile(f_idx);
                        state.buffers[f_idx].jumpToLine(diag_line);
                        state.doc.cursor_line = @intCast(diag_line);
                        uic.focused_id = state.activeEditorWidgetId();
                    },
                    .fix_with_agy => {
                        state.openFile(f_idx);
                        state.buffers[f_idx].jumpToLine(diag_line);
                        state.doc.cursor_line = @intCast(diag_line);
                        state.sendAgyDiagnosticsPrompt();
                    },
                    .copy_message => {
                        if (uic.platform_ctx) |pctx| {
                            _ = pctx.setClipboardText(diag_msg);
                        }
                        state.setStatusNotice("Copied diagnostic message");
                    },
                }
                uic.invalidateWindow();
            }
        },
        .agent_message => {
            const Item = ui.ActionMenuItem(AgentMessageAction);
            const agt_sess = state.contextMenuAgySession();
            const entries = agt_sess.chatEntries();
            const has_entries = (entries.len > 0);
            const e_idx = if (has_entries) @min(state.context_menu_index, entries.len - 1) else 0;
            const msg_txt = if (has_entries) agt_sess.entryText(entries[e_idx]) else "";
            const no_msg = (msg_txt.len == 0);
            const items = [_]Item{
                Item.itemOpts(.copy_message, "Copy Message Text", "Cmd+C", .{ .disabled = no_msg }),
                Item.itemOpts(.insert_into_buffer, "Insert into Active Buffer", "", .{ .disabled = no_msg }),
                Item.sep(),
                Item.item(.new_conversation, "New Conversation", ""),
                Item.item(.new_agent_side, "New Agent Buffer to the Side", ""),
                Item.item(.handoff_terminal, "Handoff to Terminal (agy TUI)", ""),
            };
            if (uic.contextMenuActions(AgentMessageAction, "workbench_ctx_agent_msg", &state.context_menu, &items)) |act| {
                switch (act) {
                    .copy_message => {
                        if (uic.platform_ctx) |pctx| {
                            _ = pctx.setClipboardText(msg_txt);
                        }
                        state.setStatusNotice("Copied agent message to clipboard");
                    },
                    .insert_into_buffer => {
                        const buf = state.activeEditorBuffer();
                        _ = buf.insertText(msg_txt, false);
                        uic.focused_id = state.activeEditorWidgetId();
                    },
                    .new_conversation => agt_sess.resetConversation(),
                    .new_agent_side => state.createAgentBuffer(true),
                    .handoff_terminal => state.handoffAgySessionToTerminal(agt_sess),
                }
                uic.invalidateWindow();
            }
        },
        .titlebar_pill => {
            const Item = ui.ActionMenuItem(TitlebarPillAction);
            const active_opt = state.activeFileIndex();
            const items = [_]Item{
                Item.item(.open_workspace, "Open Workspace Folder...", "Cmd+O"),
                Item.item(.quick_open, "Quick Open File...", "Cmd+P"),
                Item.item(.command_palette, "Command Palette...", "Shift+Cmd+P"),
                Item.item(.goto_symbol, "Go to Symbol in File...", "@"),
                Item.item(.goto_line, "Go to Line...", "Ctrl+G"),
                Item.sep(),
                Item.itemOpts(.copy_active_path, "Copy Active File Path", "", .{ .disabled = active_opt == null }),
                Item.item(.save_as, "Save Buffer As...", "Shift+Cmd+S"),
            };
            if (uic.contextMenuActions(TitlebarPillAction, "workbench_ctx_titlebar_pill", &state.context_menu, &items)) |act| {
                switch (act) {
                    .open_workspace => state.openWorkspacePrompt(),
                    .quick_open => {
                        state.doc.show_command_palette = true;
                        state.setPaletteQuery("");
                        uic.focusScoped(&.{"vscode_workbench"}, "##palette_input");
                    },
                    .command_palette => {
                        state.doc.show_command_palette = true;
                        state.setPaletteQuery(">");
                        uic.focusScoped(&.{"vscode_workbench"}, "##palette_input");
                    },
                    .goto_symbol => {
                        state.doc.show_command_palette = true;
                        state.setPaletteQuery("@");
                        uic.focusScoped(&.{"vscode_workbench"}, "##palette_input");
                    },
                    .goto_line => {
                        state.doc.show_command_palette = true;
                        state.setPaletteQuery(":");
                        uic.focusScoped(&.{"vscode_workbench"}, "##palette_input");
                    },
                    .copy_active_path => {
                        if (active_opt) |fi| {
                            if (uic.platform_ctx) |pctx| _ = pctx.setClipboardText(wfs[fi % wfs.len].path);
                            state.setStatusNotice("Copied active file path to clipboard");
                        }
                    },
                    .save_as => state.openSaveAsPrompt(),
                }
                uic.invalidateWindow();
            }
        },
        .titlebar_file_menu => {
            const Item = ui.ActionMenuItem(TitlebarFileMenuAction);
            const active_opt = state.activeFileIndex();
            const can_close_split = state.paneCount() > 1;
            const items = [_]Item{
                Item.item(.new_file, "New File...", "Ctrl+N"),
                Item.item(.new_folder, "New Folder...", ""),
                Item.sep(),
                Item.item(.open_workspace, "Open File / Workspace Folder...", "Ctrl+O"),
                Item.item(.quick_open, "Quick Open File...", "Ctrl+P"),
                Item.sep(),
                Item.item(.save, "Save", "Ctrl+S"),
                Item.item(.save_as, "Save As...", "Shift+Ctrl+S"),
                Item.item(.save_all, "Save All Modified Files", "Alt+Ctrl+S"),
                Item.itemOpts(.revert_file, "Revert File from Disk", "", .{ .disabled = active_opt == null }),
                Item.sep(),
                Item.item(.refresh_workspace, "Refresh Workspace Explorer", ""),
                Item.sep(),
                Item.itemOpts(.close_buffer, "Close Active Buffer", "Ctrl+W", .{ .disabled = active_opt == null }),
                Item.itemOpts(.close_split, "Close Active Split Pane", "", .{ .disabled = !can_close_split }),
            };
            if (uic.contextMenuActions(TitlebarFileMenuAction, "workbench_ctx_titlebar_file", &state.context_menu, &items)) |act| {
                switch (act) {
                    .new_file => state.openSaveAsPromptInFolder(""),
                    .new_folder => state.openNewFolderPromptInFolder(""),
                    .open_workspace => state.openWorkspacePrompt(),
                    .quick_open => commands.execute(state, .quick_open, false, null),
                    .save => commands.execute(state, .save_file, false, null),
                    .save_as => state.openSaveAsPrompt(),
                    .save_all => commands.execute(state, .save_all_files, false, null),
                    .revert_file => commands.execute(state, .revert_file, false, null),
                    .refresh_workspace => commands.execute(state, .refresh_workspace, false, null),
                    .close_buffer => commands.execute(state, .close_active_tab, false, null),
                    .close_split => commands.execute(state, .close_active_split, false, null),
                }
                uic.invalidateWindow();
            }
        },
        .titlebar_edit_menu => {
            const Item = ui.ActionMenuItem(TitlebarEditMenuAction);
            const active_opt = state.activeFileIndex();
            const buf = state.activeEditorBuffer();
            const lang: ui.CodeLanguage = if (active_opt) |fi| wfs[fi % wfs.len].language else .markdown;
            const has_sel = buf.hasSelection();
            const items = [_]Item{
                Item.itemOpts(.undo, "Undo", "Ctrl+Z", .{ .disabled = buf.undo_pos == 0 }),
                Item.itemOpts(.redo, "Redo", "Shift+Ctrl+Z", .{ .disabled = buf.undo_pos >= buf.undo_len }),
                Item.sep(),
                Item.itemOpts(.cut, "Cut", "Ctrl+X", .{ .disabled = !has_sel }),
                Item.itemOpts(.copy, "Copy", "Ctrl+C", .{ .disabled = !has_sel }),
                Item.item(.paste, "Paste", "Ctrl+V"),
                Item.itemOpts(.select_all, "Select All", "Ctrl+A", .{ .disabled = buf.len == 0 }),
                Item.sep(),
                Item.item(.toggle_comment, "Toggle Line Comment", "Ctrl+/"),
                Item.item(.duplicate_line, "Duplicate Line", "Ctrl+D"),
                Item.sep(),
                Item.item(.find_in_file, "Find in File...", "Ctrl+F"),
                Item.item(.find_in_workspace, "Find in Workspace...", "Shift+Ctrl+F"),
                Item.item(.goto_line, "Go to Line...", "Ctrl+G"),
                Item.item(.goto_symbol, "Go to Symbol in File...", "Shift+Ctrl+O"),
            };
            if (uic.contextMenuActions(TitlebarEditMenuAction, "workbench_ctx_titlebar_edit", &state.context_menu, &items)) |act| {
                uic.focused_id = state.activeEditorWidgetId();
                switch (act) {
                    .undo => _ = buf.undo(),
                    .redo => _ = buf.redo(),
                    .cut => {
                        if (buf.cutSelection()) {
                            if (uic.platform_ctx) |pctx| {
                                const clip = buf.clipboardSlice();
                                if (clip.len > 0) _ = pctx.setClipboardText(clip);
                            }
                            state.plugins.notifyBufferEdit(state, if (active_opt) |fi| @intCast(fi) else 0xFFFF);
                        }
                    },
                    .copy => {
                        buf.copySelection();
                        if (uic.platform_ctx) |pctx| {
                            const clip = buf.clipboardSlice();
                            if (clip.len > 0) _ = pctx.setClipboardText(clip);
                        }
                    },
                    .paste => {
                        if (uic.platform_ctx) |pctx| {
                            if (pctx.getClipboardTextAlloc(uic.arena)) |sys_clip| {
                                buf.setClipboardSlice(sys_clip);
                            }
                        }
                        if (buf.pasteClipboard()) {
                            state.plugins.notifyBufferEdit(state, if (active_opt) |fi| @intCast(fi) else 0xFFFF);
                        }
                    },
                    .select_all => buf.selectAll(),
                    .toggle_comment => _ = buf.toggleLineComment(lang.commentPrefix()),
                    .duplicate_line => _ = buf.duplicateCurrentLine(),
                    .find_in_file => commands.execute(state, .find_in_file, false, null),
                    .find_in_workspace => commands.execute(state, .find_in_workspace, false, null),
                    .goto_line => commands.execute(state, .goto_line_mode, false, null),
                    .goto_symbol => commands.execute(state, .goto_symbol_mode, false, null),
                }
                uic.invalidateWindow();
            }
        },
        .titlebar_view_menu => {
            const Item = ui.ActionMenuItem(TitlebarViewMenuAction);
            const active_opt = state.activeFileIndex();
            const is_wrapped = state.isBufferWordWrap(active_opt);
            const can_split = state.paneCount() < state_mod.MaxEditorPanes;
            const items = [_]Item{
                Item.item(.command_palette, "Command Palette...", "Shift+Ctrl+P"),
                Item.sep(),
                Item.item(.toggle_sidebar, if (state.doc.show_sidebar) "Hide Primary Sidebar" else "Show Primary Sidebar", "Ctrl+B"),
                Item.item(.toggle_terminal_panel, if (state.doc.show_bottom_panel) "Hide Bottom Panel" else "Show Bottom Panel", "Ctrl+J"),
                Item.item(.toggle_agent_panel, if (state.doc.show_agent_panel) "Hide Antigravity Agent Panel" else "Show Antigravity Agent Panel", "Shift+Ctrl+A"),
                Item.sep(),
                Item.item(.toggle_minimap, if (state.doc.show_minimap) "Hide Code Minimap" else "Show Code Minimap", ""),
                Item.item(.toggle_word_wrap, if (is_wrapped) "Disable Soft Word Wrap" else "Enable Soft Word Wrap", "Alt+Z"),
                Item.sep(),
                Item.itemOpts(.split_right, "Split Editor Right", "Ctrl+\\", .{ .disabled = !can_split }),
                Item.itemOpts(.split_down, "Split Editor Down", "Shift+Ctrl+\\", .{ .disabled = !can_split }),
                Item.sep(),
                Item.item(.new_terminal_buffer, "New Integrated Terminal Buffer", ""),
                Item.item(.new_agent_buffer, "New Antigravity Agent Buffer", ""),
                Item.item(.open_markdown_preview, "Open Markdown Preview to Side", ""),
                Item.item(.open_git_diff_preview, "Open Git Diff Viewer to Side", ""),
                Item.sep(),
                Item.item(.toggle_dirty_overlay, "Toggle Dirty-Rect Inspector", ""),
            };
            if (uic.contextMenuActions(TitlebarViewMenuAction, "workbench_ctx_titlebar_view", &state.context_menu, &items)) |act| {
                switch (act) {
                    .command_palette => commands.execute(state, .command_palette, false, null),
                    .toggle_sidebar => commands.execute(state, .toggle_sidebar, false, null),
                    .toggle_terminal_panel => commands.execute(state, .toggle_terminal_panel, false, null),
                    .toggle_agent_panel => commands.execute(state, .agy_toggle_panel, false, null),
                    .toggle_minimap => commands.execute(state, .toggle_minimap, false, null),
                    .toggle_word_wrap => commands.execute(state, .toggle_word_wrap, false, null),
                    .split_right => commands.execute(state, .split_right, false, null),
                    .split_down => commands.execute(state, .split_down, false, null),
                    .new_terminal_buffer => commands.execute(state, .new_terminal_buffer, false, null),
                    .new_agent_buffer => commands.execute(state, .new_agent_buffer, false, null),
                    .open_markdown_preview => commands.execute(state, .create_bound_markdown_preview_side, false, null),
                    .open_git_diff_preview => commands.execute(state, .open_git_diff_preview_side, false, null),
                    .toggle_dirty_overlay => commands.execute(state, .toggle_dirty_overlay, false, null),
                }
                uic.invalidateWindow();
            }
        },
    }
}
