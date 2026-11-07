//! Workbench Modal Overlays & Inline Bars: Compact Find Bar (`Cmd+F`),
//! Unified Command/File/Symbol/Line Palette (`Cmd+P` / `Shift+Cmd+P`),
//! Open Workspace Folder Prompt (`Cmd+O`), Save As / New File Prompt (`Shift+Cmd+S`),
//! and Create New Folder Prompt.

const std = @import("std");
const skia = @import("skia");
const ui = @import("ui");
const platform = @import("platform");
const state_mod = @import("../state.zig");
const commands = @import("../commands.zig");
const tasks_mod = @import("../tasks.zig");
const EditorState = state_mod.EditorState;

pub fn buildFindBar(state: *EditorState, file_idx_opt: ?usize) void {
    const uic = &state.ui_ctx;
    const active_buf = if (file_idx_opt) |file_idx| &state.buffers[file_idx] else &state.scratch_buf;
    const active_pane_idx = state.activePaneIndex();
    const pdf_src_opt = state.resolvePdfSourceForPane(active_pane_idx);
    const pdf_doc_opt: ?*const ui.PdfDocumentData = if (pdf_src_opt) |pdf_src|
        uic.parsePdfCached(pdf_src.eff_bytes, pdf_src.eff_path)
    else
        null;
    const restore_focus_id: ui.WidgetId = if (pdf_src_opt != null) switch (@min(active_pane_idx, 3)) {
        0 => ui.id("workbench_pdf_preview_0"),
        1 => ui.id("workbench_pdf_preview_1"),
        2 => ui.id("workbench_pdf_preview_2"),
        else => ui.id("workbench_pdf_preview_3"),
    } else state.activeEditorWidgetId();

    var bar = uic.row(.{
        .h = .pixels(36),
        .padding = ui.Padding.xy(12, 4),
        .gap = 6,
        .bg_color = skia.Color.rgb(18, 23, 33),
    });
    defer bar.end();

    const tf = uic.textFieldInline(
        "##find_bar_input",
        &state.find_query,
        "Find...",
        .{ .w = .pixels(220) },
    );

    const query = state.findQuery();
    const match_count = if (pdf_doc_opt) |pdf_doc|
        pdf_doc.countTotalSearchMatches(query)
    else
        active_buf.countMatches(query);

    var shift_enter = false;
    var cmd_g_next = false;
    var cmd_g_prev = false;
    if (uic.pass == .input) {
        for (uic.key_events) |kev| {
            if (tf.focused and kev.key == .enter and kev.shift) {
                shift_enter = true;
            } else if (kev.key == .key_g and (kev.cmd or kev.ctrl)) {
                if (kev.shift) cmd_g_prev = true else cmd_g_next = true;
            }
        }
    }

    const pdf_slot = @min(active_pane_idx, state_mod.MaxEditorPanes - 1);

    if ((tf.changed or (tf.submitted and !shift_enter) or cmd_g_next) and query.len > 0) {
        if (pdf_doc_opt) |pdf_doc| {
            const pdf_src = pdf_src_opt.?;
            const pdf_view = state.pdfViewStateForPane(active_pane_idx, pdf_src.file_idx, pdf_src.is_direct_pdf);
            const step_from_cur = !tf.changed or tf.submitted or cmd_g_next;
            const cur_m_idx: ?usize = if (step_from_cur and pdf_view.has_active_match) pdf_view.active_match_index else null;
            if (pdf_doc.findMatch(cur_m_idx, pdf_view.current_page, query, true, step_from_cur)) |next_m| {
                pdf_view.jumpToSearchMatch(next_m);
                state.pdf_views[pdf_slot] = pdf_view.*;
            } else {
                pdf_view.has_active_match = false;
                state.pdf_views[pdf_slot].has_active_match = false;
            }
        } else {
            _ = active_buf.findNext(query, true);
        }
        uic.invalidateWindow();
    } else if ((shift_enter or cmd_g_prev) and query.len > 0) {
        if (pdf_doc_opt) |pdf_doc| {
            const pdf_src = pdf_src_opt.?;
            const pdf_view = state.pdfViewStateForPane(active_pane_idx, pdf_src.file_idx, pdf_src.is_direct_pdf);
            const cur_m_idx: ?usize = if (pdf_view.has_active_match) pdf_view.active_match_index else null;
            if (pdf_doc.findMatch(cur_m_idx, pdf_view.current_page, query, false, true)) |prev_m| {
                pdf_view.jumpToSearchMatch(prev_m);
                state.pdf_views[pdf_slot] = pdf_view.*;
            }
        } else {
            _ = active_buf.findNext(query, false);
        }
        uic.invalidateWindow();
    } else if (tf.escaped) {
        state.doc.show_find_bar = false;
        uic.focused_id = restore_focus_id;
        uic.invalidateWindow();
    }

    if (uic.btn("Prev##find", .{ .w = .pixels(48), .h = 26 })) {
        if (pdf_doc_opt) |pdf_doc| {
            const pdf_src = pdf_src_opt.?;
            const pdf_view = state.pdfViewStateForPane(active_pane_idx, pdf_src.file_idx, pdf_src.is_direct_pdf);
            const cur_m_idx: ?usize = if (pdf_view.has_active_match) pdf_view.active_match_index else null;
            if (pdf_doc.findMatch(cur_m_idx, pdf_view.current_page, query, false, true)) |prev_m| {
                pdf_view.jumpToSearchMatch(prev_m);
                state.pdf_views[pdf_slot] = pdf_view.*;
            }
        } else {
            _ = active_buf.findNext(query, false);
        }
        uic.focused_id = restore_focus_id;
        uic.invalidateWindow();
    }
    if (uic.btn("Next##find", .{ .w = .pixels(48), .h = 26 })) {
        if (pdf_doc_opt) |pdf_doc| {
            const pdf_src = pdf_src_opt.?;
            const pdf_view = state.pdfViewStateForPane(active_pane_idx, pdf_src.file_idx, pdf_src.is_direct_pdf);
            const cur_m_idx: ?usize = if (pdf_view.has_active_match) pdf_view.active_match_index else null;
            if (pdf_doc.findMatch(cur_m_idx, pdf_view.current_page, query, true, true)) |next_m| {
                pdf_view.jumpToSearchMatch(next_m);
                state.pdf_views[pdf_slot] = pdf_view.*;
            }
        } else {
            _ = active_buf.findNext(query, true);
        }
        uic.focused_id = restore_focus_id;
        uic.invalidateWindow();
    }
    if (uic.btn("×##find_close", .{ .w = .pixels(28), .h = 26 })) {
        state.doc.show_find_bar = false;
        uic.focused_id = restore_focus_id;
    }

    if (query.len > 0) {
        uic.label(uic.fmt("{d} found", .{match_count}), null);
    }
}

const PaletteCommandId = commands.CommandId;

const PaletteItemAction = union(enum) {
    open_file: struct { file_idx: usize, line: ?usize },
    jump_line: struct { file_idx: usize, line: usize, col: usize },
    run_command: PaletteCommandId,
    run_plugin_command: struct { plugin_idx: usize, cmd_idx: usize },
    run_task: struct {
        name: platform.InlineString(64),
        command: platform.InlineString(256),
        source: platform.InlineString(64),
    },
    select_preview_app: struct {
        path: platform.InlineString(256),
        name: platform.InlineString(64),
    },
};

const PaletteEntry = struct {
    label: []const u8,
    meta: []const u8,
    icon_text: []const u8,
    icon_color: u32,
    score: i32,
    action: PaletteItemAction,
    mono: bool = false,
};

fn executePaletteAction(state: *EditorState, action: PaletteItemAction) void {
    const uic = &state.ui_ctx;
    switch (action) {
        .open_file => |of| {
            state.openFile(of.file_idx);
            if (of.line) |ln| {
                const pane_idx = state.activePaneIndex();
                if (state.resolvePdfSourceForPane(pane_idx)) |pdf_src| {
                    const pdf_view = state.pdfViewStateForPane(pane_idx, pdf_src.file_idx, pdf_src.is_direct_pdf);
                    pdf_view.current_page = ln -| 1;
                    state.pdf_views[@min(pane_idx, state_mod.MaxEditorPanes - 1)].current_page = ln -| 1;
                } else {
                    state.buffers[of.file_idx].jumpToLine(ln);
                    state.doc.cursor_line = @intCast(ln);
                    state.doc.cursor_col = 1;
                }
            }
            state.doc.show_command_palette = false;
            uic.focused_id = state.activeEditorWidgetId();
        },
        .jump_line => |jl| {
            state.openFile(jl.file_idx);
            const pane_idx = state.activePaneIndex();
            if (state.resolvePdfSourceForPane(pane_idx)) |pdf_src| {
                const pdf_view = state.pdfViewStateForPane(pane_idx, pdf_src.file_idx, pdf_src.is_direct_pdf);
                pdf_view.current_page = jl.line -| 1;
                state.pdf_views[@min(pane_idx, state_mod.MaxEditorPanes - 1)].current_page = jl.line -| 1;
            } else {
                state.buffers[jl.file_idx].jumpToLine(jl.line);
                state.doc.cursor_line = @intCast(jl.line);
                state.doc.cursor_col = @intCast(@max(1, jl.col));
            }
            state.doc.show_command_palette = false;
            uic.focused_id = state.activeEditorWidgetId();
        },
        .run_command => |cmd| {
            commands.execute(state, cmd, true, null);
        },
        .run_plugin_command => |pc| {
            state.doc.show_command_palette = false;
            state.plugins.executePluginCommand(state, pc.plugin_idx, pc.cmd_idx);
            uic.focused_id = state.activeEditorWidgetId();
        },
        .run_task => |rt| {
            // Do not force the bottom panel open; run tasks quietly in their background execution context.
            state.doc.bottom_panel_tab = 2; // Output Console tab
            state.output_channel_filter.set("Tasks");
            _ = state.task_runner.start(state, rt.name.slice(), rt.command.slice(), rt.source.slice());
            state.doc.show_command_palette = false;
            uic.focused_id = state.activeEditorWidgetId();
        },
        .select_preview_app => |app| {
            state.app_custom_path.set(app.path.slice());
            for (&state.app_views) |*v| {
                v.setDylibPath(app.path.slice());
            }
            var notice_buf: [256]u8 = undefined;
            const notice = std.fmt.bufPrint(&notice_buf, "Selected preview app: {s}", .{app.name.slice()}) catch "Selected preview app";
            state.setStatusNotice(notice);
            state.openAppPreviewBuffer(false);
            state.doc.show_command_palette = false;
            uic.focused_id = state.activeEditorWidgetId();
        },
    }
}

pub fn buildCommandPaletteOverlay(state: *EditorState, overlay_rect: skia.c.sk_rect_t) void {
    const uic = &state.ui_ctx;
    var scope = uic.scopedState("editor_pane");
    defer scope.end();

    // Dismiss the palette if the user clicks outside the floating overlay card (below the titlebar)
    if (uic.isClickedOutsideOverlay(overlay_rect, 36.0)) {
        state.doc.show_command_palette = false;
        uic.focused_id = state.activeEditorWidgetId();
        uic.invalidateWindow();
        return;
    }

    const active_opt = state.activeFileIndex();
    const palette_input_wid = uic.resolveIdAndLabel("##palette_input").wid;

    // Ensure the palette input has focus when the palette is open
    uic.ensureOverlayInputFocus(palette_input_wid, &.{
        ui.id("workbench_palette_input"),
        ui.scopedIdPath(&.{"vscode_workbench"}, "##palette_input"),
        ui.scopedIdPath(&.{ "vscode_workbench", "editor_pane" }, "workbench_palette_input"),
        state.activeEditorWidgetId(),
    });

    var palette = uic.overlayBox(overlay_rect, .{
        .padding = ui.Padding.xy(14, 8),
        .gap = 4,
        .bg_color = skia.Color.rgb(20, 26, 38),
        .border_color = skia.Color.argb(140, 100, 116, 139),
        .border_width = 1.0,
        .corner_radius = 8.0,
    });
    defer palette.end();

    // 1. Mode Switcher Bar (`Files`, `> Commands`, `@ Symbols`, `: Go to Line`) + Hint
    const raw_q = state.paletteQuery();
    const is_cmd_mode = std.mem.startsWith(u8, raw_q, ">");
    const is_sym_mode = std.mem.startsWith(u8, raw_q, "@");
    const is_line_mode = std.mem.startsWith(u8, raw_q, ":");
    const is_file_mode = !is_cmd_mode and !is_sym_mode and !is_line_mode;

    {
        var mode_row = uic.row(.{
            .h = .pixels(24),
            .gap = 6,
        });
        defer mode_row.end();

        if (uic.panelTab("Files (Cmd+P)##pal_m0", is_file_mode)) {
            state.setPaletteQuery("");
            uic.focused_id = palette_input_wid;
        }
        if (uic.panelTab("> Commands##pal_m1", is_cmd_mode)) {
            state.setPaletteQuery(">");
            uic.focused_id = palette_input_wid;
        }
        if (uic.panelTab("@ Symbols##pal_m2", is_sym_mode)) {
            state.setPaletteQuery("@");
            uic.focused_id = palette_input_wid;
        }
        if (uic.panelTab(": Line##pal_m3", is_line_mode)) {
            state.setPaletteQuery(":");
            uic.focused_id = palette_input_wid;
        }
        if (uic.availableWidth() > 180.0) {
            uic.fillSpacer(165.0);
            uic.label("↑↓ Navigate · ↵ Select · Esc", null);
        }
    }

    // 2. Search Input Box
    const tf = uic.textFieldInline(
        "##palette_input",
        &state.palette_query,
        "Type file name, '>' for commands, '@' for symbols, or ':line'...",
        .{ .w = .fill },
    );

    if (tf.changed) {
        state.palette_selected_idx = 0;
        uic.invalidateWindow();
    }
    if (tf.escaped) {
        state.doc.show_command_palette = false;
        uic.focused_id = state.activeEditorWidgetId();
        uic.invalidateWindow();
        return;
    }

    // 3. Build & Rank Matching Entries for the Active Mode
    const wfs = state.workspaceFiles();
    var entries: [96]PaletteEntry = undefined;
    var entry_count: usize = 0;

    const q = state.paletteQuery();
    if (std.mem.startsWith(u8, q, ">")) {
        const sub_q = std.mem.trim(u8, q[1..], " \t");
        for (commands.COMMANDS) |cmd| {
            if (!cmd.show_in_palette) continue;
            if (!commands.matchesQuery(cmd, sub_q)) continue;
            const sc = commands.scoreQuery(cmd, sub_q) orelse continue;
            if (entry_count < entries.len) {
                entries[entry_count] = .{
                    .label = cmd.label,
                    .meta = state.shortcutDisplayForCommand(cmd.id, cmd.shortcut_display),
                    .icon_text = cmd.icon_text,
                    .icon_color = skia.Color.rgb(129, 140, 248),
                    .score = sc,
                    .action = .{ .run_command = cmd.id },
                };
                entry_count += 1;
            }
        }
        // Include commands registered by dynamically loaded `.dylib` plugins
        for (0..state.plugins.plugin_count) |p_idx| {
            const plug = &state.plugins.plugins[p_idx];
            if (!plug.active or !plug.enabled) continue;
            for (0..plug.command_count) |c_idx| {
                const pcmd = &plug.commands[c_idx];
                if (!ui.matchesCommandQuery(pcmd.title.slice(), pcmd.category.slice(), pcmd.shortcut_hint.slice(), sub_q)) continue;
                const sc = ui.scoreCommandMatch(pcmd.title.slice(), pcmd.category.slice(), pcmd.shortcut_hint.slice(), sub_q) orelse continue;
                if (entry_count < entries.len) {
                    entries[entry_count] = .{
                        .label = pcmd.title.slice(),
                        .meta = pcmd.shortcut_hint.slice(),
                        .icon_text = "⚙",
                        .icon_color = skia.Color.rgb(52, 211, 153),
                        .score = sc,
                        .action = .{ .run_plugin_command = .{ .plugin_idx = p_idx, .cmd_idx = c_idx } },
                    };
                    entry_count += 1;
                }
            }
        }

        // Include workspace tasks declared in `.vscode/tasks.json`, `.vscode/launch.json`, or project manifests
        var ws_tasks: [32]tasks_mod.TaskEntry = undefined;
        const task_count = tasks_mod.listWorkspaceTasks(state, &ws_tasks);
        for (ws_tasks[0..task_count]) |task| {
            if (entry_count >= entries.len) break;
            const t_name = task.nameSlice();
            const t_cmd = task.commandSlice();
            const t_label = uic.fmt("Tasks: Run Task — {s}", .{t_name});

            var matched = false;
            var sc: i32 = 0;

            if (sub_q.len == 0) {
                matched = true;
                sc = 40;
            } else if (std.mem.startsWith(u8, sub_q, "task:") or std.mem.startsWith(u8, sub_q, "tasks:")) {
                const colon_pos = std.mem.indexOfScalar(u8, sub_q, ':').?;
                const after_colon = std.mem.trim(u8, sub_q[colon_pos + 1 ..], " \t");
                if (after_colon.len == 0) {
                    matched = true;
                    sc = 80;
                } else if (ui.fuzzyScore(t_name, after_colon)) |s| {
                    matched = true;
                    sc = s + 50;
                } else if (ui.fuzzyScore(t_cmd, after_colon)) |s| {
                    matched = true;
                    sc = s + 30;
                }
            } else if (ui.fuzzyScore(t_label, sub_q)) |s| {
                matched = true;
                sc = s;
            } else if (ui.fuzzyScore(t_name, sub_q)) |s| {
                matched = true;
                sc = s + 25;
            } else if (ui.fuzzyScore(t_cmd, sub_q)) |s| {
                matched = true;
                sc = s;
            }

            if (matched and entry_count < entries.len) {
                entries[entry_count] = .{
                    .label = t_label,
                    .meta = t_cmd,
                    .icon_text = "⚡",
                    .icon_color = skia.Color.rgb(56, 189, 248),
                    .score = sc,
                    .action = .{ .run_task = .{
                        .name = platform.InlineString(64).init(t_name),
                        .command = platform.InlineString(256).init(t_cmd),
                        .source = platform.InlineString(64).init(task.sourceSlice()),
                    } },
                };
                entry_count += 1;
            }
        }
    } else if (std.mem.startsWith(u8, q, "task:") or std.mem.startsWith(u8, q, "tasks:")) {
        const colon_pos = std.mem.indexOfScalar(u8, q, ':').?;
        const sub_q = std.mem.trim(u8, q[colon_pos + 1 ..], " \t");
        var ws_tasks: [32]tasks_mod.TaskEntry = undefined;
        const task_count = tasks_mod.listWorkspaceTasks(state, &ws_tasks);
        for (ws_tasks[0..task_count]) |task| {
            if (entry_count >= entries.len) break;
            const t_name = task.nameSlice();
            const t_cmd = task.commandSlice();
            const t_label = uic.fmt("Tasks: Run Task — {s}", .{t_name});

            var matched = false;
            var sc: i32 = 80;
            if (sub_q.len == 0) {
                matched = true;
            } else if (ui.fuzzyScore(t_name, sub_q)) |s| {
                matched = true;
                sc = s + 50;
            } else if (ui.fuzzyScore(t_cmd, sub_q)) |s| {
                matched = true;
                sc = s + 20;
            }

            if (matched and entry_count < entries.len) {
                entries[entry_count] = .{
                    .label = t_label,
                    .meta = t_cmd,
                    .icon_text = "⚡",
                    .icon_color = skia.Color.rgb(56, 189, 248),
                    .score = sc,
                    .action = .{ .run_task = .{
                        .name = platform.InlineString(64).init(t_name),
                        .command = platform.InlineString(256).init(t_cmd),
                        .source = platform.InlineString(64).init(task.sourceSlice()),
                    } },
                };
                entry_count += 1;
            }
        }
    } else if (std.mem.startsWith(u8, q, "app:") or std.mem.startsWith(u8, q, "preview app:")) {
        const colon_pos = std.mem.indexOfScalar(u8, q, ':').?;
        const sub_q = std.mem.trim(u8, q[colon_pos + 1 ..], " \t");
        var app_dylibs: [32]tasks_mod.AppDylibEntry = undefined;
        const dylib_count = tasks_mod.listWorkspaceAppDylibs(state, &app_dylibs);
        for (app_dylibs[0..dylib_count]) |cand| {
            if (entry_count >= entries.len) break;
            const c_name = cand.nameSlice();
            const c_path = cand.pathSlice();
            const c_label = uic.fmt("App Preview: {s}", .{c_name});

            var matched = false;
            var sc: i32 = 80;
            if (sub_q.len == 0) {
                matched = true;
            } else if (ui.fuzzyScore(c_name, sub_q)) |s| {
                matched = true;
                sc = s + 50;
            } else if (ui.fuzzyScore(c_path, sub_q)) |s| {
                matched = true;
                sc = s + 20;
            }

            if (matched and entry_count < entries.len) {
                entries[entry_count] = .{
                    .label = c_label,
                    .meta = c_path,
                    .icon_text = "📱",
                    .icon_color = skia.Color.rgb(168, 85, 247),
                    .score = sc,
                    .action = .{ .select_preview_app = .{
                        .path = platform.InlineString(256).init(c_path),
                        .name = platform.InlineString(64).init(c_name),
                    } },
                };
                entry_count += 1;
            }
        }
    } else if (std.mem.startsWith(u8, q, "@")) {
        const sub_q = std.mem.trim(u8, q[1..], " \t");
        const target_f = (active_opt orelse 0) % wfs.len;
        const active_file = wfs[target_f];
        if (state.resolvePdfSourceForPane(state.activePaneIndex())) |pdf_src| {
            const pdf_doc = uic.parsePdfCached(pdf_src.eff_bytes, pdf_src.eff_path);
            for (pdf_doc.outline[0..pdf_doc.outline_count]) |item| {
                const title = item.title.slice();
                const sc = ui.fuzzyScore(title, sub_q) orelse continue;
                if (entry_count < entries.len) {
                    entries[entry_count] = .{
                        .label = title,
                        .meta = uic.fmt("{s}:p.{d}", .{ active_file.name, item.page_number }),
                        .icon_text = "§",
                        .icon_color = skia.Color.rgb(56, 189, 248),
                        .score = sc,
                        .action = .{ .jump_line = .{ .file_idx = target_f, .line = @max(@as(usize, 1), item.page_number), .col = 1 } },
                        .mono = true,
                    };
                    entry_count += 1;
                }
            }
        } else {
            const syms = state.symbolsForFile(target_f);

            for (syms) |sym| {
                const sc = ui.fuzzyScore(sym.name, sub_q) orelse (ui.fuzzyScore(sym.kind, sub_q) orelse continue);
                if (entry_count < entries.len) {
                    const is_fn = std.mem.eql(u8, sym.kind, "fn");
                    const is_heading = (sym.kind[0] == 'h');
                    const icon_col = if (is_fn)
                        skia.Color.rgb(210, 168, 255)
                    else if (is_heading)
                        skia.Color.rgb(56, 189, 248)
                    else
                        skia.Color.rgb(121, 192, 255);

                    entries[entry_count] = .{
                        .label = sym.name,
                        .meta = uic.fmt("{s}:{d}", .{ active_file.name, sym.line }),
                        .icon_text = sym.kind,
                        .icon_color = icon_col,
                        .score = sc,
                        .action = .{ .jump_line = .{ .file_idx = target_f, .line = sym.line, .col = 1 } },
                        .mono = true,
                    };
                    entry_count += 1;
                }
            }
        }
    } else if (std.mem.startsWith(u8, q, ":")) {
        const sub_q = std.mem.trim(u8, q[1..], " \t");
        const target_f = (active_opt orelse 0) % wfs.len;
        if (state.resolvePdfSourceForPane(state.activePaneIndex())) |pdf_src| {
            const pdf_doc = uic.parsePdfCached(pdf_src.eff_bytes, pdf_src.eff_path);
            const total_pages = @max(1, pdf_doc.page_count);
            const pdf_view = state.pdfViewStateForPane(state.activePaneIndex(), pdf_src.file_idx, pdf_src.is_direct_pdf);
            var parsed_pg: usize = pdf_view.current_page + 1;
            if (sub_q.len > 0) {
                parsed_pg = std.fmt.parseInt(usize, sub_q, 10) catch 1;
            }
            const clamped_pg = std.math.clamp(parsed_pg, 1, total_pages);
            entries[0] = .{
                .label = uic.fmt("Go to PDF Page {d} of {d}  —  {s}", .{ clamped_pg, total_pages, pdf_doc.title.slice() }),
                .meta = uic.fmt("1..{d}", .{total_pages}),
                .icon_text = "P",
                .icon_color = skia.Color.rgb(244, 63, 94),
                .score = 100,
                .action = .{ .jump_line = .{ .file_idx = target_f, .line = clamped_pg, .col = 1 } },
                .mono = true,
            };
            entry_count = 1;
        } else {
            const buf = &state.buffers[target_f];
            const total_lines = @max(1, buf.lineCount());

            var parsed_line: usize = state.doc.cursor_line;
            var parsed_col: usize = 1;
            if (sub_q.len > 0) {
                if (std.mem.indexOfScalar(u8, sub_q, ':')) |c_sep| {
                    parsed_line = std.fmt.parseInt(usize, sub_q[0..c_sep], 10) catch 1;
                    parsed_col = std.fmt.parseInt(usize, sub_q[c_sep + 1 ..], 10) catch 1;
                } else {
                    parsed_line = std.fmt.parseInt(usize, sub_q, 10) catch 1;
                }
            }
            const clamped_line = std.math.clamp(parsed_line, 1, total_lines);
            const lr = buf.lineRangeByIndex(clamped_line - 1);
            const raw_line = std.mem.trim(u8, buf.slice()[lr.start..lr.end], " \t\r");
            const preview = if (raw_line.len > 48) raw_line[0..48] else raw_line;

            entries[0] = .{
                .label = uic.fmt("Go to Line {d}, Column {d}  —  {s}", .{ clamped_line, parsed_col, preview }),
                .meta = uic.fmt("1..{d}", .{total_lines}),
                .icon_text = ":",
                .icon_color = skia.Color.rgb(52, 211, 153),
                .score = 100,
                .action = .{ .jump_line = .{ .file_idx = target_f, .line = clamped_line, .col = parsed_col } },
                .mono = true,
            };
            entry_count = 1;
        }
    } else {
        // File Quick Open Mode (also supports `file:line`, e.g. `root.zig:120`)
        var file_q = std.mem.trim(u8, q, " \t");
        var opt_line: ?usize = null;
        if (std.mem.indexOfScalar(u8, file_q, ':')) |colon_idx| {
            const after = file_q[colon_idx + 1 ..];
            if (after.len > 0) {
                opt_line = std.fmt.parseInt(usize, after, 10) catch null;
            }
            file_q = file_q[0..colon_idx];
        }

        for (wfs, 0..) |file, idx| {
            if (file.is_markdown_preview and !state.isBufferOpen(idx)) continue;
            const name_sc = ui.fuzzyScore(file.name, file_q);
            const path_sc = ui.fuzzyScore(file.path, file_q);
            if (name_sc == null and path_sc == null) continue;
            var best_sc = @max(name_sc orelse -999, path_sc orelse -999);
            if (name_sc) |ns| {
                best_sc = @max(best_sc, ns + 15);
            }
            if (active_opt != null and active_opt.? == idx) {
                best_sc += 5;
            }

            const dirty = state.isFileDirty(idx);
            const is_md = (file.language == .markdown);
            const label_txt = if (opt_line) |ln|
                uic.fmt("{s}:{d}", .{ file.name, ln })
            else if (dirty)
                uic.fmt("{s} ●", .{file.name})
            else
                file.name;

            const cand = PaletteEntry{
                .label = label_txt,
                .meta = if (file.is_terminal)
                    "zsh"
                else if (file.is_agent)
                    "Antigravity Agent"
                else if (file.is_markdown_preview)
                    state.markdownPreviewSourceName(idx)
                else
                    file.path,
                .icon_text = if (file.is_agent) "✦" else if (file.is_terminal) "T" else if (file.is_app_preview) "⚡" else if (file.is_waveform_preview) "W" else if (file.is_markdown_preview) "P" else if (is_md) "M" else "Z",
                .icon_color = if (file.is_agent)
                    skia.Color.rgb(88, 166, 255)
                else if (file.is_terminal)
                    skia.Color.rgb(52, 211, 153)
                else if (file.is_app_preview)
                    skia.Color.rgb(245, 158, 11)
                else if (file.is_waveform_preview)
                    skia.Color.rgb(168, 85, 247)
                else if (is_md)
                    skia.Color.rgb(56, 189, 248)
                else
                    skia.Color.rgb(251, 191, 36),
                .score = best_sc,
                .action = .{ .open_file = .{ .file_idx = idx, .line = opt_line } },
            };
            if (entry_count < entries.len) {
                entries[entry_count] = cand;
                entry_count += 1;
            } else {
                var min_i: usize = 0;
                for (1..entries.len) |e_i| {
                    if (entries[e_i].score < entries[min_i].score) min_i = e_i;
                }
                if (best_sc > entries[min_i].score) {
                    entries[min_i] = cand;
                }
            }
        }

        // If query is empty, also append top commands right below the workspace files for easy discovery
        if (file_q.len == 0 and opt_line == null) {
            var added_cmds: usize = 0;
            for (commands.COMMANDS) |cmd| {
                if (!cmd.show_in_palette) continue;
                if (entry_count >= entries.len or added_cmds >= 6) break;
                entries[entry_count] = .{
                    .label = cmd.label,
                    .meta = state.shortcutDisplayForCommand(cmd.id, cmd.shortcut_display),
                    .icon_text = cmd.icon_text,
                    .icon_color = skia.Color.rgb(129, 140, 248),
                    .score = -10,
                    .action = .{ .run_command = cmd.id },
                };
                entry_count += 1;
                added_cmds += 1;
            }
        }
    }

    // Sort matching entries descending by fuzzy score when query is non-empty
    if (q.len > 0) {
        ui.sortByScoreDesc(PaletteEntry, entries[0..entry_count]);
    }

    // 4. Keyboard Up / Down / Tab navigation & Enter execution
    if (ui.stepListSelection(&state.palette_selected_idx, entry_count, tf)) {
        uic.invalidateWindow();
    }

    // 5. Scrollable Results List
    var clicked_action: ?PaletteItemAction = null;
    {
        var list_scroll = uic.scrollPanel("palette_results_scroll", .{
            .h = .pixels(184),
            .gap = 2,
            .bg_color = skia.Color.rgb(15, 20, 29),
            .padding = ui.Padding.xy(4, 4),
        });
        defer list_scroll.end();

        if (entry_count == 0) {
            uic.label("No matching files, commands, or symbols.", null);
        } else {
            const vr = uic.computeVirtualRange(entry_count, 26.0, 2);
            if (vr.top_spacer_h > 0) uic.spacer(vr.top_spacer_h);
            for (entries[vr.first..vr.end], vr.first..) |entry, e_idx| {
                var eid = uic.scopedId(e_idx + 2000);
                defer eid.end();

                const is_sel = (e_idx == state.palette_selected_idx);
                if (uic.listItem(.{
                    .label = entry.label,
                    .meta = entry.meta,
                    .icon_text = entry.icon_text,
                    .icon_color = entry.icon_color,
                    .selected = is_sel,
                    .height = 24.0,
                    .mono_label = entry.mono,
                })) {
                    state.palette_selected_idx = e_idx;
                    clicked_action = entry.action;
                }
            }
            if (vr.bottom_spacer_h > 0) uic.spacer(vr.bottom_spacer_h);
        }
    }

    if (clicked_action) |act| {
        executePaletteAction(state, act);
        uic.invalidateWindow();
        return;
    }

    if (tf.submitted) {
        if (entry_count > 0) {
            const sel = @min(state.palette_selected_idx, entry_count - 1);
            executePaletteAction(state, entries[sel].action);
        } else {
            state.doc.show_command_palette = false;
            uic.focused_id = state.activeEditorWidgetId();
        }
        uic.invalidateWindow();
    }
}

pub fn buildSaveAsPromptOverlay(state: *EditorState, overlay_rect: skia.c.sk_rect_t) void {
    const uic = &state.ui_ctx;
    var scope = uic.scopedState("editor_pane");
    defer scope.end();

    const active_opt = state.activeFileIndex();
    const title_txt = if (state.save_as_create_empty)
        "Create New File"
    else if (active_opt != null)
        "Save Buffer As New File"
    else
        "Save *scratch* Buffer to File";

    switch (uic.promptModal(256, "save_as", overlay_rect, &state.save_as_path, .{
        .title = title_txt,
        .placeholder = "path/to/new_file.zig or notes.md...",
        .hint = if (state.save_as_create_empty)
            "Relative to workspace root · Enter to Create · Esc to Cancel"
        else
            "Relative to workspace root · Enter to Save · Esc to Cancel",
        .confirm_label = if (state.save_as_create_empty) "Create" else "Save",
        .input_id = "##save_as_input",
        .outside_click_min_y = 36.0,
    })) {
        .confirmed => {
            _ = state.saveActiveOrScratchToNewFile();
            uic.invalidateWindow();
        },
        .cancelled => {
            state.show_save_as_prompt = false;
            state.save_as_create_empty = false;
            uic.focused_id = state.activeEditorWidgetId();
            uic.invalidateWindow();
        },
        .none => {},
    }
}

pub fn buildNewFolderPromptOverlay(state: *EditorState, overlay_rect: skia.c.sk_rect_t) void {
    const uic = &state.ui_ctx;
    var scope = uic.scopedState("editor_pane");
    defer scope.end();

    switch (uic.promptModal(256, "new_folder", overlay_rect, &state.new_folder_path, .{
        .title = "Create New Folder",
        .placeholder = "path/to/new_folder...",
        .hint = "Relative to workspace root · Enter to Create · Esc to Cancel",
        .confirm_label = "Create",
        .input_id = "##new_folder_input",
        .outside_click_min_y = 36.0,
    })) {
        .confirmed => {
            _ = state.createNewFolderFromPrompt();
            uic.invalidateWindow();
        },
        .cancelled => {
            state.show_new_folder_prompt = false;
            uic.focused_id = state.activeEditorWidgetId();
            uic.invalidateWindow();
        },
        .none => {},
    }
}

pub fn buildOpenWorkspacePromptOverlay(state: *EditorState, overlay_rect: skia.c.sk_rect_t) void {
    const uic = &state.ui_ctx;
    var scope = uic.scopedState("editor_pane");
    defer scope.end();

    switch (uic.filePickerModal(256, "open_workspace", overlay_rect, &state.open_workspace_path, &state.open_workspace_selected_idx, .{
        .title = uic.fmt("Open File / Folder  —  {s}", .{state.workspaceName()}),
        .placeholder = "Enter file or workspace folder path (or ~/...)",
        .hint = "Click folder to browse · Enter to Open · Esc to Cancel",
        .confirm_label = "Open",
        .input_id = "##open_workspace_input",
        .outside_click_min_y = 36.0,
        .show_files = true,
        .padding = ui.Padding.xy(16, 10),
        .gap = 6.0,
    })) {
        .confirmed => {
            if (state.openWorkspaceFromPrompt()) {
                state.show_open_workspace_prompt = false;
                uic.focused_id = state.activeEditorWidgetId();
            }
            uic.invalidateWindow();
        },
        .cancelled => {
            state.show_open_workspace_prompt = false;
            uic.focused_id = state.activeEditorWidgetId();
            uic.invalidateWindow();
        },
        .none => {},
    }
}
