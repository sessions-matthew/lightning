//! Workbench Bottom Panel (`Cmd+J`): Integrated VTerm Terminal, Problems/Diagnostics list,
//! and multi-channel Output Console.

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
            for (diags, 0..) |d, didx| {
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
        }
    } else {
        // Output Console: Header bar with line count & Clear button, plus scrollable monospace output stream
        {
            var out_header = uic.row(.{
                .h = .pixels(26),
                .padding = ui.Padding.xy(14, 2),
                .gap = 10,
            });
            defer out_header.end();

            uic.label(uic.fmt("Output Channels: Editor · Git · LSP · Tasks ({d} lines)", .{state.output_line_count}), uic.theme.text_muted);
            if (uic.btn("Clear Output##clear_out_btn", .{ .w = .pixels(96), .h = 22 })) {
                state.clearOutput();
                uic.invalidateWindow();
            }
        }

        var out_scroll = uic.scrollPanel("bottom_output_scroll", .{
            .padding = ui.Padding.xy(14, 4),
            .gap = 3,
        });
        defer out_scroll.end();

        if (state.output_line_count == 0) {
            uic.label("No output logged yet.", uic.theme.text_muted);
        } else {
            for (0..state.output_line_count) |idx| {
                const line = &state.output_lines[idx];
                const ch = if (line.channel.len > 0) line.channel.slice() else "Editor";
                const line_str = uic.fmt("[{s}]  {s}", .{ ch, line.text.slice() });
                uic.monoLabel(line_str, null);
            }
        }
    }
}
