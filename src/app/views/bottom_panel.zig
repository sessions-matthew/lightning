//! Workbench Bottom Panel (`Cmd+J`): Integrated VTerm Terminal, Problems/Diagnostics list,
//! and multi-channel Output Console.

const std = @import("std");
const skia = @import("skia");
const ui = @import("ui");
const state_mod = @import("../state.zig");
const EditorState = state_mod.EditorState;
const DiagnosticItem = state_mod.DiagnosticItem;

pub fn buildBottomPanel(
    state: *EditorState,
    file_idx: usize,
    height: f32,
    active_tab: *u8,
    diags: []const DiagnosticItem,
) void {
    const uic = &state.ui_ctx;
    const wfs = state.workspaceFiles();
    const active_file_name = if (wfs.len > 0) wfs[file_idx % wfs.len].name else "*scratch*";
    const active_buf = if (wfs.len > 0) &state.buffers[file_idx % wfs.len] else &state.scratch_buf;

    var panel = uic.column(.{
        .h = .pixels(height),
        .gap = 0,
        .bg_color = skia.Color.rgb(16, 20, 28),
    });
    defer panel.end();

    uic.divider();

    {
        var header = uic.row(.{
            .h = .pixels(28),
            .padding = ui.Padding.xy(12, 2),
            .gap = 12,
        });
        defer header.end();

        const problems_label = uic.fmt("PROBLEMS ({d})##prob_tab", .{diags.len});
        if (uic.panelTab("TERMINAL", active_tab.* == 0)) {
            active_tab.* = 0;
            uic.focused_id = ui.id("workbench_vterm");
        }
        if (uic.panelTab(problems_label, active_tab.* == 1)) active_tab.* = 1;
        const output_label = if (state.output_line_count > 0)
            uic.fmt("OUTPUT ({d})##output_tab", .{state.output_line_count})
        else
            "OUTPUT##output_tab";
        if (uic.panelTab(output_label, active_tab.* == 2)) active_tab.* = 2;
    }

    uic.divider();

    const body_h = @max(60.0, height - 30.0);
    if (active_tab.* == 0) {
        const term_top = panel.rect.top + 30.0;
        const term_rect = skia.Rect.xywh(panel.rect.left, term_top, panel.rect.right - panel.rect.left, body_h);
        _ = uic.vterm("workbench_vterm", 0, 0, &state.vterm, state.font_mono);
        if (uic.rightClicked(term_rect)) {
            state.openContextMenu(.terminal, state.activePaneIndex(), null, true);
        }
    } else if (active_tab.* == 1) {
        var prob_scroll = uic.scrollPanel("bottom_problems_scroll", .{
            .padding = ui.Padding.xy(14, 6),
            .gap = 3,
        });
        defer prob_scroll.end();

        if (diags.len == 0) {
            uic.label("No problems detected.", null);
        } else {
            const vr = uic.computeVirtualRange(diags.len, 25.0, 2);
            if (vr.top_spacer_h > 0) uic.spacer(vr.top_spacer_h);
            for (diags[vr.first..vr.end], vr.first..) |d, didx| {
                var d_id = uic.scopedId(didx);
                defer d_id.end();

                const icon_str = switch (d.severity) {
                    .err => "E",
                    .warn => "W",
                    .info => "i",
                };
                const icon_col = switch (d.severity) {
                    .err => skia.Color.rgb(248, 81, 73),
                    .warn => skia.Color.rgb(245, 158, 11),
                    .info => skia.Color.rgb(56, 189, 248),
                };
                const label_str = uic.fmt("{s}:{d}  {s}", .{ active_file_name, d.line, d.message });
                const p_res = uic.listItemEx(.{
                    .label = label_str,
                    .icon_text = icon_str,
                    .icon_color = icon_col,
                    .height = 22.0,
                    .mono_label = true,
                });
                if (p_res.clicked) {
                    active_buf.jumpToLine(d.line);
                    state.doc.cursor_line = @intCast(d.line);
                    uic.focused_id = state.activeEditorWidgetId();
                } else if (p_res.right_clicked) {
                    state.context_menu_line = d.line;
                    state.context_menu_label.set(d.message);
                    state.openContextMenu(.problem_item, state.activePaneIndex(), file_idx, false);
                }
            }
            if (vr.bottom_spacer_h > 0) uic.spacer(vr.bottom_spacer_h);
        }
    } else {
        // Output Console: Channel filtering, live task execution status, copy/clear controls, and monospace log stream
        const filter_slice = state.output_channel_filter.slice();
        const is_all = (filter_slice.len == 0 or std.ascii.eqlIgnoreCase(filter_slice, "ALL"));
        const is_tasks = std.ascii.eqlIgnoreCase(filter_slice, "Tasks");
        const is_git = std.ascii.eqlIgnoreCase(filter_slice, "Git");
        const is_editor = std.ascii.eqlIgnoreCase(filter_slice, "Editor");
        const is_notice = std.ascii.eqlIgnoreCase(filter_slice, "Notice");

        {
            var out_header = uic.row(.{
                .h = .pixels(26),
                .padding = ui.Padding.xy(12, 2),
                .gap = 6,
            });
            defer out_header.end();

            uic.label("Channel:", uic.theme.text_muted);

            if (uic.chip("ALL##out_ch_all", .{ .active = is_all, .h = 20 })) {
                state.output_channel_filter.set("ALL");
                uic.invalidateWindow();
            }
            if (uic.chip("Tasks##out_ch_tasks", .{ .active = is_tasks, .h = 20 })) {
                state.output_channel_filter.set("Tasks");
                uic.invalidateWindow();
            }
            if (uic.chip("Git##out_ch_git", .{ .active = is_git, .h = 20 })) {
                state.output_channel_filter.set("Git");
                uic.invalidateWindow();
            }
            if (uic.chip("Editor##out_ch_editor", .{ .active = is_editor, .h = 20 })) {
                state.output_channel_filter.set("Editor");
                uic.invalidateWindow();
            }
            if (uic.chip("Notice##out_ch_notice", .{ .active = is_notice, .h = 20 })) {
                state.output_channel_filter.set("Notice");
                uic.invalidateWindow();
            }

            if (state.task_runner.is_running) {
                const cmd_txt = state.task_runner.command_line.slice();
                const run_label = if (cmd_txt.len > 24)
                    uic.fmt("● Running: {s}...##run_task_lbl", .{cmd_txt[0..24]})
                else
                    uic.fmt("● Running: {s}##run_task_lbl", .{cmd_txt});
                uic.label(run_label, skia.Color.rgb(251, 191, 36));

                if (uic.btn("Stop Task##stop_task_btn", .{ .w = .pixels(76), .h = 20 })) {
                    state.task_runner.terminate();
                    state.appendOutput("Tasks", "[Tasks] Stopped by user.");
                    uic.invalidateWindow();
                }
            }

            if (uic.btn("Copy Output##copy_out_btn", .{ .w = .pixels(86), .h = 20 })) {
                if (uic.platform_ctx) |pctx| {
                    var copy_buf = std.ArrayListUnmanaged(u8).empty;
                    defer copy_buf.deinit(uic.arena);
                    for (0..state.output_line_count) |i| {
                        const line = &state.output_lines[i];
                        if (is_all or std.ascii.eqlIgnoreCase(line.channel.slice(), filter_slice)) {
                            copy_buf.appendSlice(uic.arena, "[") catch break;
                            copy_buf.appendSlice(uic.arena, line.channel.slice()) catch break;
                            copy_buf.appendSlice(uic.arena, "] ") catch break;
                            copy_buf.appendSlice(uic.arena, line.text.slice()) catch break;
                            copy_buf.append(uic.arena, '\n') catch break;
                        }
                    }
                    if (copy_buf.items.len > 0) {
                        _ = pctx.setClipboardText(copy_buf.items);
                        state.setStatusNotice("Output copied to clipboard.");
                    }
                }
                uic.invalidateWindow();
            }

            if (uic.btn("Clear Output##clear_out_btn", .{ .w = .pixels(86), .h = 20 })) {
                state.clearOutput();
                uic.invalidateWindow();
            }
        }

        const scroll_state: *ui.ScrollState = if (uic.platform_ctx != null)
            uic.useState(ui.ScrollState, "bottom_output_scroll", .{})
        else
            &uic.fallback_scroll_state;

        if (state.output_scroll_to_bottom) {
            state.output_scroll_to_bottom = false;
            scroll_state.scroll_y = @max(0.0, scroll_state.content_height - scroll_state.viewport_height);
        }

        var out_scroll = uic.scrollPanel("bottom_output_scroll", .{
            .padding = ui.Padding.xy(14, 4),
            .gap = 2,
            .allow_h_scroll = true,
        });
        defer out_scroll.end();

        var matching_indices = std.ArrayListUnmanaged(usize).empty;
        for (0..state.output_line_count) |i| {
            const line = &state.output_lines[i];
            if (is_all or std.ascii.eqlIgnoreCase(line.channel.slice(), filter_slice)) {
                matching_indices.append(uic.arena, i) catch break;
            }
        }

        if (matching_indices.items.len == 0) {
            uic.label("No output logged yet.", uic.theme.text_muted);
        } else {
            const vr = uic.computeVirtualRange(matching_indices.items.len, 22.0, 3);
            if (vr.top_spacer_h > 0) uic.spacer(vr.top_spacer_h);
            for (vr.first..vr.end) |m_idx| {
                var row_scope = uic.scopedId(m_idx);
                defer row_scope.end();

                const line_idx = matching_indices.items[m_idx];
                const line = &state.output_lines[line_idx];
                const ch = if (line.channel.len > 0) line.channel.slice() else "Editor";
                const text_slice = line.text.slice();

                const badge_col: u32 = if (std.ascii.eqlIgnoreCase(ch, "Tasks"))
                    skia.Color.rgb(56, 189, 248) // cyan
                else if (std.ascii.eqlIgnoreCase(ch, "Git"))
                    skia.Color.rgb(192, 132, 252) // purple
                else if (std.ascii.eqlIgnoreCase(ch, "Notice"))
                    skia.Color.rgb(96, 165, 250) // blue
                else
                    skia.Color.rgb(156, 163, 175); // gray

                const text_col: ?u32 = if (std.mem.startsWith(u8, text_slice, "[Done]") or
                    std.mem.indexOf(u8, text_slice, "Finished") != null or
                    std.mem.indexOf(u8, text_slice, "successfully") != null)
                    skia.Color.rgb(74, 222, 128) // green
                else if (std.mem.startsWith(u8, text_slice, "[Failed]") or
                    std.mem.indexOf(u8, text_slice, "error:") != null or
                    std.mem.indexOf(u8, text_slice, "Error:") != null)
                    skia.Color.rgb(248, 113, 113) // red
                else if (std.mem.indexOf(u8, text_slice, "warning:") != null or
                    std.mem.indexOf(u8, text_slice, "Warning:") != null)
                    skia.Color.rgb(251, 191, 36) // amber
                else if (std.mem.startsWith(u8, text_slice, ">>>"))
                    skia.Color.rgb(125, 211, 252) // sky blue
                else
                    null;

                var line_row = uic.row(.{
                    .h = .pixels(20),
                    .gap = 8,
                });
                defer line_row.end();

                const badge_str = uic.fmt("[{s}]", .{ch});
                uic.monoLabel(badge_str, badge_col);
                uic.monoLabel(text_slice, text_col);
            }
            if (vr.bottom_spacer_h > 0) uic.spacer(vr.bottom_spacer_h);
        }
    }
}
