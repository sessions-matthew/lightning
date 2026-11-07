//! Minimal compact macOS titlebar (top 28pt) with centered file / Quick Open pill (`Cmd+P`).

const skia = @import("skia");
const ui = @import("ui");
const platform = @import("platform");
const builtin = @import("builtin");
const state_mod = @import("../state.zig");
const EditorState = state_mod.EditorState;
const PlatformContext = platform.PlatformContext;
const is_windows = (builtin.os.tag != .macos);

pub const TitlebarHeight: f32 = 36.0;

pub fn build(
    state: *EditorState,
    ctx: *const PlatformContext,
) skia.c.sk_rect_t {
    const uic = &state.ui_ctx;
    const active_opt = state.activeFileIndex();

    const bar_rect = uic.beginBox(0, TitlebarHeight, .{
        .direction = .row,
        .padding = ui.Padding.all(0),
        .gap = 0,
        .bg_color = skia.Color.rgb(16, 20, 28),
        .border_color = uic.theme.border_subtle,
        .border_width = 1.0,
        .border_edges = .bottom_only,
    });
    defer uic.endBox();

    if (comptime is_windows) {
        // Left: Integrated VS Code-style File / Edit / View menu bar items
        const menus = [_]struct {
            label: []const u8,
            target: state_mod.ContextMenuTarget,
            w: f32,
        }{
            .{ .label = "File", .target = .titlebar_file_menu, .w = 38.0 },
            .{ .label = "Edit", .target = .titlebar_edit_menu, .w = 38.0 },
            .{ .label = "View", .target = .titlebar_view_menu, .w = 42.0 },
        };
        const any_titlebar_menu_open = state.context_menu.open and
            (state.context_menu_target == .titlebar_file_menu or
                state.context_menu_target == .titlebar_edit_menu or
                state.context_menu_target == .titlebar_view_menu);
        var mx: f32 = bar_rect.left + 8.0;
        for (menus) |m| {
            const mr = skia.Rect.xywh(mx, bar_rect.top + 6.0, m.w, 24.0);
            const wid = ui.id(m.label);
            _ = uic.trackInteraction(wid, mr, bar_rect);
            const hovered = uic.isHovered(mr);
            const is_open = state.context_menu.open and state.context_menu_target == m.target;
            if (uic.pass == .input) {
                if (hovered) uic.setCursor(.pointing_hand);
                if (hovered and uic.mouse_pressed) {
                    if (is_open) {
                        state.context_menu.close();
                        uic.invalidateWindow();
                    } else {
                        state.openContextMenuAt(
                            m.target,
                            state.doc.split_tree.active_pane,
                            active_opt,
                            false,
                            mr.left,
                            bar_rect.bottom,
                        );
                    }
                } else if (hovered and any_titlebar_menu_open and !is_open) {
                    state.openContextMenuAt(
                        m.target,
                        state.doc.split_tree.active_pane,
                        active_opt,
                        false,
                        mr.left,
                        bar_rect.bottom,
                    );
                }
            } else if (uic.shouldPaint(mr)) {
                if (hovered or is_open) {
                    uic.paint.setStyle(.fill);
                    uic.paint.setColor(if (is_open) uic.theme.control_bg else skia.Color.rgb(30, 36, 48));
                    uic.canvas.drawRoundRect(mr, 4.0, 4.0, uic.paint);
                }
                uic.paint.setStyle(.fill);
                uic.paint.setColor(if (hovered or is_open) skia.Color.white else skia.Color.rgb(190, 198, 210));
                const tw = uic.measureTextCached(uic.font_body, m.label);
                uic.drawTextCached(uic.font_body, m.label, mr.left + (m.w - tw) * 0.5, mr.top + 16.5);
            }
            mx += m.w + 2.0;
        }

        // Right: Integrated Windows Caption Controls (Minimize, Maximize/Restore, Close)
        const cap_w: f32 = 46.0;
        const cap_h: f32 = TitlebarHeight - 1.0;
        const cap_actions = [_]u32{ 10, 11, 12 };
        const cap_ids = [_][]const u8{ "win_cap_min", "win_cap_max", "win_cap_close" };
        for (cap_actions, 0..) |act, idx| {
            const cx = bar_rect.right - @as(f32, @floatFromInt(3 - idx)) * cap_w;
            const cr = skia.Rect.xywh(cx, bar_rect.top, cap_w, cap_h);
            const wid = ui.id(cap_ids[idx]);
            const clicked = uic.trackInteraction(wid, cr, bar_rect);
            const hovered = uic.isHovered(cr);
            if (uic.pass == .input) {
                if (clicked) {
                    ctx.triggerWindowAction(act, 0, 0);
                }
            } else if (uic.shouldPaint(cr)) {
                if (hovered) {
                    uic.paint.setStyle(.fill);
                    uic.paint.setColor(if (act == 12) skia.Color.rgb(232, 17, 35) else skia.Color.argb(28, 255, 255, 255));
                    uic.canvas.drawRect(cr, uic.paint);
                }
                const icon_col = if (hovered) skia.Color.white else skia.Color.rgb(190, 198, 210);
                const mid_x = cr.left + cap_w * 0.5;
                const mid_y = cr.top + cap_h * 0.5;
                uic.paint.setColor(icon_col);
                if (act == 10) {
                    // Minimize bar (`─`)
                    uic.paint.setStyle(.fill);
                    uic.canvas.drawRect(skia.Rect.xywh(mid_x - 5.0, mid_y, 10.0, 1.2), uic.paint);
                } else if (act == 11) {
                    // Maximize box (`□`)
                    uic.paint.setStyle(.stroke);
                    uic.paint.setStrokeWidth(1.2);
                    uic.canvas.drawRect(skia.Rect.xywh(mid_x - 4.5, mid_y - 4.5, 9.0, 9.0), uic.paint);
                } else {
                    // Close cross (`×`)
                    uic.paint.setStyle(.stroke);
                    uic.paint.setStrokeWidth(1.3);
                    uic.canvas.drawLine(mid_x - 4.5, mid_y - 4.5, mid_x + 4.5, mid_y + 4.5, uic.paint);
                    uic.canvas.drawLine(mid_x + 4.5, mid_y - 4.5, mid_x - 4.5, mid_y + 4.5, uic.paint);
                }
            }
        }
    }

    const ws_name = state.workspaceName();
    const mod_label = if (comptime is_windows) "Ctrl" else "Cmd";
    const label_str = if (ctx.is_fullscreen)
        mod_label ++ "+P"
    else if (active_opt) |f_idx| blk: {
        const wfs = state.workspaceFiles();
        const file = wfs[f_idx];
        if (file.is_agent) {
            const a_slot = state.ensureAgentSlot(file.agent_slot);
            const conv_title = state.agent_sessions[a_slot].activeTitle();
            break :blk if (conv_title.len > 0)
                uic.fmt("{s} · {s} — {s}", .{ ws_name, file.name, conv_title })
            else
                uic.fmt("{s} — {s}", .{ ws_name, file.name });
        }
        if (file.is_git_diff_preview) {
            break :blk uic.fmt("{s} · *Git Diff* — {s}", .{ ws_name, wfs[state.gitDiffPreviewSourceIndex()].path });
        }
        if (file.is_markdown_preview) {
            break :blk uic.fmt("{s} · {s} — {s}", .{ ws_name, file.name, state.markdownPreviewSourcePath(f_idx) });
        }
        if (file.is_waveform_preview) {
            break :blk uic.fmt("{s} · *Waveform Preview* — {s}", .{ ws_name, wfs[state.waveformPreviewSourceIndex()].path });
        }
        if (file.is_app_preview) {
            break :blk uic.fmt("{s} · *App Simulator*", .{ws_name});
        }
        break :blk if (state.isFileDirty(f_idx))
            uic.fmt("{s} — {s} ●", .{ ws_name, file.path })
        else
            uic.fmt("{s} — {s}", .{ ws_name, file.path });
    } else if (!state.hasOpenedWorkspace())
        (if (state.isScratchDirty())
            "Lightning · *scratch* ●  (" ++ mod_label ++ "+S)"
        else
            "Lightning  (" ++ mod_label ++ "+O to Open Folder)")
    else if (state.isScratchDirty())
        uic.fmt("{s} — *scratch* ●  (" ++ mod_label ++ "+S)", .{ws_name})
    else
        uic.fmt("{s} — *scratch*  (" ++ mod_label ++ "+P / " ++ mod_label ++ "+O)", .{ws_name});

    const text_w = uic.measureTextCached(uic.font_body, label_str);
    const pill_w: f32 = if (ctx.is_fullscreen)
        @max(64.0, text_w + 20.0)
    else
        @min(@max(300.0, ctx.width - 240.0), @max(300.0, text_w + 28.0));
    const pill_h: f32 = 24.0;
    const pill_x: f32 = if (ctx.is_fullscreen)
        ctx.width - pill_w - 12.0
    else
        (ctx.width - pill_w) * 0.5;
    const show_pill = if (ctx.is_fullscreen)
        (pill_x > ctx.width * 0.5 + 110.0)
    else
        (pill_x > 90 and pill_x + pill_w < ctx.width - 90);
    const pill_rect = skia.Rect.xywh(pill_x, bar_rect.top + 6, pill_w, pill_h);

    if (show_pill) {

        if (uic.searchPill(
            "titlebar_command_palette_pill",
            label_str,
            state.doc.show_command_palette,
            pill_rect,
            bar_rect,
        )) {
            state.doc.show_command_palette = !state.doc.show_command_palette;
            if (state.doc.show_command_palette) {
                state.setPaletteQuery("");
                uic.focusScoped(&.{"vscode_workbench"}, "##palette_input");
            } else {
                uic.focused_id = state.activeEditorWidgetId();
            }
        } else if (uic.rightClicked(pill_rect)) {
            state.openContextMenu(.titlebar_pill, state.activePaneIndex(), active_opt, false);
        }
    }

    return bar_rect;
}
