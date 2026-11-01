//! Reusable Card, Disclosure, Option, Split-Menu, Empty-State & Attachment Widgets (`src/ui/cards.zig`).
//! Extracted from `src/app/views/agent_panel.zig` so any view or plugin can compose them declaratively.

const std = @import("std");
const skia = @import("skia");
const root = @import("root.zig");
const layout = @import("layout.zig");
const virtual_list = @import("virtual_list.zig");
const c = skia.c;
const Color = skia.Color;
const Rect = skia.Rect;
const Context = root.Context;
const Padding = root.Padding;

pub const InlineStepRowResult = struct {
    clicked: bool = false,
    right_clicked: bool = false,
    rect: c.sk_rect_t = .{ .left = 0, .top = 0, .right = 0, .bottom = 0 },
};

pub const ThinkingDisclosureOptions = struct {
    toggle_slot: ?*u8 = null,
    id_salt: ?[]const u8 = null,
};

pub const ThinkingDisclosureResult = struct {
    toggled: bool = false,
    expanded: bool = false,
    right_clicked: bool = false,
    clicked_link: ?[]const u8 = null,
    header_rect: c.sk_rect_t = .{ .left = 0, .top = 0, .right = 0, .bottom = 0 },
};

pub const CommandCardStatus = union(enum) {
    pending_approval,
    running,
    exited_ok,
    exited_err: i16,
    rejected,

    pub fn fromExitCode(exit_code: i16) CommandCardStatus {
        if (exit_code == 0) return .exited_ok;
        if (exit_code > 0) return .{ .exited_err = exit_code };
        if (exit_code == -2) return .pending_approval;
        if (exit_code == -3) return .rejected;
        return .running;
    }
};

pub const CommandCardAction = enum(u8) {
    none = 0,
    accepted = 1,
    rejected = 2,
    toggled = 3,
    right_clicked = 4,
};

pub const CommandCardOptions = struct {
    summary: []const u8 = "",
    toggle_slot: ?*u8 = null,
    default_open: bool = false,
};

pub const CommandCardResult = struct {
    action: CommandCardAction = .none,
    toggled: bool = false,
    right_clicked: bool = false,
    expanded: bool = false,
    header_rect: c.sk_rect_t = .{ .left = 0, .top = 0, .right = 0, .bottom = 0 },
};

pub const SplitMenuItemResult = struct {
    row_clicked: bool = false,
    subtrigger_clicked: bool = false,
    subtrigger_hovered: bool = false,
    row_rect: c.sk_rect_t = .{ .left = 0, .top = 0, .right = 0, .bottom = 0 },
};

pub const AttachmentDisplayItem = struct {
    path: []const u8 = "",
    name: []const u8 = "",
    meta: []const u8 = "",
    width: u32 = 0,
    height: u32 = 0,
};

pub const AttachmentStripOptions = struct {
    removable: bool = false,
    align_right: bool = false,
    row_height: ?f32 = null,
    clicked_idx_out: ?*?usize = null,
    removed_idx_out: ?*?usize = null,
};

fn resolveDisclosureToggleSlot(uic: *Context, id_key: []const u8, idx: usize, external_slot: ?*u8) *u8 {
    if (external_slot) |slot| return slot;
    if (uic.platform_ctx != null) {
        return uic.useState(u8, uic.fmt("{s}_disc_{d}", .{ id_key, idx }), 0);
    }
    const h = uic.resolveIdAndLabel(uic.fmt("##disc_fb_{s}_{d}", .{ id_key, idx })).wid;
    const slot_idx: usize = @as(usize, @truncate(h ^ idx)) & (uic.fallback_disclosure_toggles.len - 1);
    return &uic.fallback_disclosure_toggles[slot_idx];
}

/// Renders a minimal inline step row (`› Read file  src/main.zig`) with optional clickable detail badge.
pub fn inlineStepRowEx(
    uic: *Context,
    raw_id: []const u8,
    icon: []const u8,
    icon_color: u32,
    label: []const u8,
    right_badge: []const u8,
) InlineStepRowResult {
    const r = uic.nextRect(0, 20.0);
    const has_detail = (right_badge.len > 0);
    const wid = uic.resolveIdAndLabel(raw_id).wid;
    const clicked = if (has_detail) uic.trackInteraction(wid, r, r) else false;
    const hovered = (has_detail and uic.hot_id == wid);

    if (hovered) {
        uic.setCursor(.pointing_hand);
    }
    const right_clicked = uic.rightClicked(r);

    if (uic.shouldPaint(r)) {
        if (hovered) {
            uic.paint.setStyle(.fill);
            uic.paint.setColor(Color.argb(28, 148, 163, 184));
            uic.canvas.drawRoundRect(r, 4.0, 4.0, uic.paint);
        }

        const save_cnt = uic.canvas.save();
        defer uic.canvas.restoreToCount(save_cnt);
        uic.canvas.clipRect(Rect.ltrb(r.left + 2.0, r.top, r.right - 4.0, r.bottom), .intersect, false);

        const by = r.top + 14.5;
        const icon_str = if (icon.len > 0) icon else "›";
        uic.paint.setStyle(.fill);
        uic.paint.setColor(icon_color);
        uic.drawTextCached(uic.font_body, icon_str, r.left + 4.0, by);

        uic.paint.setColor(if (hovered) Color.rgb(201, 209, 217) else Color.rgb(139, 148, 158));
        uic.drawTextCached(uic.font_body, label, r.left + 16.0, by);

        if (has_detail) {
            const name_w = uic.measureTextCached(uic.font_body, label);
            uic.paint.setColor(if (hovered) uic.theme.accent_hover else Color.rgb(110, 118, 129));
            uic.drawTextCached(uic.font_mono, right_badge, r.left + 24.0 + name_w, by);
        }
    }

    if (clicked) uic.invalidateWindow();
    return .{
        .clicked = clicked,
        .right_clicked = right_clicked,
        .rect = r,
    };
}

pub fn inlineStepRow(
    uic: *Context,
    icon: []const u8,
    icon_color: u32,
    label: []const u8,
    right_badge: []const u8,
) void {
    const id_str = uic.fmt("##inline_step_{s}_{s}", .{ label, right_badge });
    _ = inlineStepRowEx(uic, id_str, icon, icon_color, label, right_badge);
}

/// Extracts a clean single-line plain-text summary from a thinking block for the collapsed disclosure header.
pub fn extractThinkingPreviewLine(thinking_text: []const u8, out_buf: *[96]u8) []const u8 {
    var rest = std.mem.trim(u8, thinking_text, " \t\r\n");
    while (rest.len > 0) {
        const nl = std.mem.indexOfScalar(u8, rest, '\n') orelse rest.len;
        const line = std.mem.trim(u8, rest[0..nl], " \t\r#:*->`");
        if (line.len > 0) {
            var pos: usize = 0;
            var prev_space = false;
            for (line) |ch| {
                if (pos >= out_buf.len) break;
                if (ch == '*' or ch == '`' or ch == '_') continue;
                if (ch == ' ' or ch == '\t') {
                    if (!prev_space and pos > 0) {
                        out_buf[pos] = ' ';
                        pos += 1;
                        prev_space = true;
                    }
                    continue;
                }
                prev_space = false;
                out_buf[pos] = ch;
                pos += 1;
            }
            const safe_end = root.code_editor_mod.snapToGraphemeBoundary(out_buf[0..pos], pos);
            return std.mem.trimEnd(u8, out_buf[0..safe_end], " ");
        }
        if (nl >= rest.len) break;
        rest = rest[nl + 1 ..];
    }
    return "";
}

/// Renders a collapsible thinking block dropdown (`▸ Thought for 5s · preview...` / `▾ Thought for 5s` + full Markdown body).
pub fn thinkingDisclosureEx(
    uic: *Context,
    id_key: []const u8,
    idx: usize,
    preview_title: []const u8,
    body_text: []const u8,
    default_open: bool,
    opts: ThinkingDisclosureOptions,
) ThinkingDisclosureResult {
    const r = uic.nextRect(0, 24.0);
    const wid = uic.resolveIdAndLabel(uic.fmt("##think_hdr_{s}_{d}", .{ id_key, idx })).wid;
    const clicked = uic.trackInteraction(wid, r, r);
    const hovered = (uic.hot_id == wid);
    if (hovered) {
        uic.setCursor(.pointing_hand);
    }

    const slot = resolveDisclosureToggleSlot(uic, id_key, idx, opts.toggle_slot);
    var toggled = false;
    if (clicked) {
        const prev_exp = switch (slot.*) {
            1 => false,
            2 => true,
            else => default_open,
        };
        slot.* = if (prev_exp) 1 else 2;
        toggled = true;
        uic.markDirty(Rect.ltrb(r.left - 20.0, uic.root_rect.top, r.right + 20.0, uic.root_rect.bottom));
        uic.invalidateWindow();
    }
    const right_clicked = if (!clicked) uic.rightClicked(r) else false;
    const expanded = switch (slot.*) {
        1 => false,
        2 => true,
        else => default_open,
    };

    if (uic.shouldPaint(r)) {
        if (expanded or hovered) {
            uic.paint.setStyle(.fill);
            uic.paint.setColor(if (hovered)
                Color.argb(38, 148, 163, 184)
            else
                Color.rgb(20, 26, 36));
            uic.canvas.drawRoundRect(r, 5.0, 5.0, uic.paint);
        }
        if (expanded) {
            uic.paint.setStyle(.stroke);
            uic.paint.setStrokeWidth(1.0);
            uic.paint.setColor(Color.rgb(42, 52, 66));
            uic.canvas.drawRoundRect(r, 5.0, 5.0, uic.paint);
        }

        const save_cnt = uic.canvas.save();
        defer uic.canvas.restoreToCount(save_cnt);
        uic.canvas.clipRect(Rect.ltrb(r.left + 4.0, r.top, r.right - 6.0, r.bottom), .intersect, false);

        const by = r.top + 16.5;
        uic.paint.setStyle(.fill);
        uic.paint.setColor(if (expanded or hovered) Color.rgb(88, 166, 255) else Color.rgb(139, 148, 158));
        uic.drawTextCached(uic.font_body, if (expanded) "▾" else "▸", r.left + 6.0, by);

        const hdr_lbl = if (preview_title.len > 0) preview_title else "Thought";
        uic.paint.setColor(if (expanded or hovered) Color.rgb(218, 226, 234) else Color.rgb(150, 160, 172));
        uic.drawTextCached(uic.font_body, hdr_lbl, r.left + 20.0, by);

        if (!expanded) {
            var preview_buf: [96]u8 = undefined;
            const preview = extractThinkingPreviewLine(body_text, &preview_buf);
            if (preview.len > 0) {
                const lbl_w = uic.measureTextCached(uic.font_body, hdr_lbl);
                const sep_txt = uic.fmt(" · {s}", .{preview});
                uic.paint.setColor(if (hovered) Color.rgb(139, 148, 158) else Color.rgb(104, 114, 126));
                uic.drawTextCached(uic.font_body, sep_txt, r.left + 20.0 + lbl_w, by);
            }
        }
    }

    var clicked_link: ?[]const u8 = null;
    if (expanded) {
        const trimmed = std.mem.trim(u8, body_text, " \t\r\n");
        if (trimmed.len > 0) {
            const salt = opts.id_salt orelse uic.fmt("{s}_think_md_{d}", .{ id_key, idx });
            const md_res = uic.markdownBubble(trimmed, .{
                .bg_color = Color.rgb(16, 21, 29),
                .text_color = Color.rgb(176, 186, 198),
                .border_color = Color.rgb(34, 43, 56),
                .border_width = 1.0,
                .left_accent_color = Color.rgb(68, 96, 136),
                .left_accent_width = 2.5,
                .pad_x = 12.0,
                .pad_y = 8.0,
                .line_height = 19.0,
                .blank_gap_h = 6.0,
                .corner_radius = 6.0,
                .id_salt = salt,
            });
            clicked_link = md_res.clicked_link;
        }
    }

    return .{
        .toggled = toggled,
        .expanded = expanded,
        .right_clicked = right_clicked,
        .clicked_link = clicked_link,
        .header_rect = r,
    };
}

pub fn thinkingDisclosure(
    uic: *Context,
    id_key: []const u8,
    idx: usize,
    preview_title: []const u8,
    body_text: []const u8,
    default_open: bool,
) void {
    _ = thinkingDisclosureEx(uic, id_key, idx, preview_title, body_text, default_open, .{});
}

/// Renders a collapsible shell command (`run_command`) card supporting pending approval (`Accept` / `Reject`),
/// running, exited ok (`✓`), exited err (`✕ code`), and rejected states.
pub fn commandExecutionCardEx(
    uic: *Context,
    id_key: []const u8,
    idx: usize,
    cmd_line: []const u8,
    output_body: []const u8,
    status: CommandCardStatus,
    opts: CommandCardOptions,
) CommandCardResult {
    const r = uic.nextRect(0, 22.0);
    const wid = uic.resolveIdAndLabel(uic.fmt("##cmd_hdr_{s}_{d}", .{ id_key, idx })).wid;
    const clicked = uic.trackInteraction(wid, r, r);
    const hovered = (uic.hot_id == wid);
    if (hovered) {
        uic.setCursor(.pointing_hand);
    }

    const default_open = opts.default_open or (status == .pending_approval);
    const slot = resolveDisclosureToggleSlot(uic, id_key, idx, opts.toggle_slot);
    var action: CommandCardAction = .none;
    var toggled = false;
    if (clicked) {
        const prev_exp = switch (slot.*) {
            1 => false,
            2 => true,
            else => default_open,
        };
        slot.* = if (prev_exp) 1 else 2;
        toggled = true;
        action = .toggled;
        uic.markDirty(Rect.ltrb(r.left - 20.0, uic.root_rect.top, r.right + 20.0, uic.root_rect.bottom));
        uic.invalidateWindow();
    }
    const right_clicked = if (!clicked) uic.rightClicked(r) else false;
    if (right_clicked and action == .none) {
        action = .right_clicked;
    }

    const expanded = switch (slot.*) {
        1 => false,
        2 => true,
        else => default_open,
    };
    const display_summary = if (opts.summary.len > 0) opts.summary else cmd_line;

    if (uic.shouldPaint(r)) {
        if (expanded or hovered) {
            uic.paint.setStyle(.fill);
            uic.paint.setColor(if (hovered)
                Color.argb(34, 148, 163, 184)
            else
                Color.rgb(18, 24, 34));
            uic.canvas.drawRoundRect(r, 4.5, 4.5, uic.paint);
        }
        if (expanded) {
            uic.paint.setStyle(.stroke);
            uic.paint.setStrokeWidth(1.0);
            uic.paint.setColor(Color.rgb(40, 50, 64));
            uic.canvas.drawRoundRect(r, 4.5, 4.5, uic.paint);
        }

        const badge_str: []const u8 = switch (status) {
            .exited_ok => "✓",
            .exited_err => |code| uic.fmt("✕ {d}", .{code}),
            .pending_approval => "Pending",
            .running => "",
            .rejected => "Rejected",
        };
        const badge_w: f32 = if (badge_str.len > 0) uic.measureTextCached(uic.font_mono, badge_str) + 12.0 else 4.0;

        {
            const save_cnt = uic.canvas.save();
            defer uic.canvas.restoreToCount(save_cnt);
            uic.canvas.clipRect(Rect.ltrb(r.left + 2.0, r.top, @max(r.left + 24.0, r.right - badge_w), r.bottom), .intersect, false);

            const by = r.top + 15.5;
            uic.paint.setStyle(.fill);
            uic.paint.setColor(if (expanded or hovered) Color.rgb(88, 166, 255) else Color.rgb(110, 118, 129));
            uic.drawTextCached(uic.font_body, if (expanded) "▾" else "▸", r.left + 4.5, by);

            const tool_lbl = "run_command";
            uic.paint.setColor(if (expanded or hovered) Color.rgb(210, 218, 226) else Color.rgb(139, 148, 158));
            uic.drawTextCached(uic.font_body, tool_lbl, r.left + 17.0, by);

            if (display_summary.len > 0) {
                const name_w = uic.measureTextCached(uic.font_body, tool_lbl);
                uic.paint.setColor(if (expanded or hovered) uic.theme.accent_hover else Color.rgb(110, 118, 129));
                uic.drawTextCached(uic.font_mono, display_summary, r.left + 25.0 + name_w, by);
            }
        }

        if (badge_str.len > 0) {
            const bw = uic.measureTextCached(uic.font_mono, badge_str);
            uic.paint.setStyle(.fill);
            uic.paint.setColor(switch (status) {
                .exited_ok => Color.rgb(63, 185, 80),
                .exited_err, .rejected => Color.rgb(248, 81, 73),
                .pending_approval => Color.rgb(210, 153, 34),
                .running => Color.rgb(88, 166, 255),
            });
            uic.drawTextCached(uic.font_mono, badge_str, r.right - bw - 6.0, r.top + 15.5);
        }
    }

    if (expanded) {
        const card_w = @max(140.0, uic.availableWidth());
        const pad_x: f32 = 12.0;
        const pad_y: f32 = 8.0;
        const inner_w = @max(80.0, card_w - pad_x * 2.0);
        const line_h: f32 = 17.5;

        const clean_cmd = std.mem.trim(u8, if (cmd_line.len > 0) cmd_line else display_summary, " \t\r\n");
        const prompt_cmd = if (clean_cmd.len > 0) uic.fmt("$ {s}", .{clean_cmd}) else "$";
        const cmd_lines = virtual_list.wrapPlainText(uic, uic.font_mono, prompt_cmd, inner_w);

        const clean_out = std.mem.trim(u8, output_body, " \t\r\n");
        var out_lines: [18][]const u8 = undefined;
        var out_count: usize = 0;
        var total_out_lines: usize = 0;
        if (clean_out.len > 0) {
            var line_it = std.mem.splitScalar(u8, clean_out, '\n');
            while (line_it.next()) |raw_l| {
                const l = std.mem.trimEnd(u8, raw_l, "\r");
                total_out_lines += 1;
                if (out_count < 16) {
                    const max_chars = @min(l.len, 160);
                    const safe_len = root.code_editor_mod.snapToGraphemeBoundary(l, max_chars);
                    out_lines[out_count] = l[0..safe_len];
                    out_count += 1;
                }
            }
            if (total_out_lines > out_count and out_count < out_lines.len) {
                out_lines[out_count] = uic.fmt("... ({d} more lines)", .{total_out_lines - out_count});
                out_count += 1;
            }
        }

        const cmd_h = @as(f32, @floatFromInt(@max(cmd_lines.len, 1))) * line_h;
        const sep_h: f32 = if (out_count > 0) 9.0 else 0.0;
        const out_h = @as(f32, @floatFromInt(out_count)) * line_h;
        const total_card_h = pad_y * 2.0 + cmd_h + sep_h + out_h;

        const card_r = uic.nextRect(0, total_card_h);
        if (uic.shouldPaint(card_r)) {
            uic.paint.setStyle(.fill);
            uic.paint.setColor(Color.rgb(12, 16, 23));
            uic.canvas.drawRoundRect(card_r, 6.0, 6.0, uic.paint);

            uic.paint.setStyle(.stroke);
            uic.paint.setStrokeWidth(1.0);
            uic.paint.setColor(Color.rgb(36, 45, 58));
            uic.canvas.drawRoundRect(card_r, 6.0, 6.0, uic.paint);

            const stripe_col = switch (status) {
                .exited_ok => Color.rgb(63, 185, 80),
                .exited_err, .rejected => Color.rgb(248, 81, 73),
                .pending_approval => Color.rgb(210, 153, 34),
                .running => Color.rgb(88, 166, 255),
            };
            uic.paint.setStyle(.fill);
            uic.paint.setColor(stripe_col);
            uic.canvas.drawRoundRect(
                Rect.xywh(card_r.left, card_r.top + 3.0, 2.5, @max(1.0, (card_r.bottom - card_r.top) - 6.0)),
                1.25,
                1.25,
                uic.paint,
            );

            const save_cnt = uic.canvas.save();
            defer uic.canvas.restoreToCount(save_cnt);
            uic.canvas.clipRect(Rect.ltrb(card_r.left + pad_x - 2.0, card_r.top, card_r.right - 6.0, card_r.bottom), .intersect, false);

            var cur_y = card_r.top + pad_y;
            uic.paint.setColor(Color.rgb(125, 211, 252));
            for (cmd_lines) |cl| {
                uic.drawTextCached(uic.font_mono, cl, card_r.left + pad_x, cur_y + 13.0);
                cur_y += line_h;
            }

            if (out_count > 0) {
                const div_y = @floor(cur_y + 4.0);
                uic.paint.setColor(Color.rgb(30, 38, 50));
                uic.canvas.drawRect(Rect.xywh(card_r.left + pad_x, div_y, inner_w, 1.0), uic.paint);
                cur_y += sep_h;

                for (out_lines[0..out_count], 0..) |ol, o_idx| {
                    const is_more_line = (total_out_lines > 16 and o_idx + 1 == out_count);
                    uic.paint.setColor(if (is_more_line)
                        Color.rgb(110, 118, 129)
                    else
                        Color.rgb(185, 194, 204));
                    uic.drawTextCached(uic.font_mono, ol, card_r.left + pad_x, cur_y + 13.0);
                    cur_y += line_h;
                }
            }
        }

        if (status == .pending_approval) {
            var act_row = uic.row(.{
                .h = .pixels(26.0),
                .gap = 6.0,
            });
            defer act_row.end();

            if (uic.availableWidth() > 144.0) {
                uic.fillSpacer(138.0);
            }
            if (uic.chip(uic.fmt("Reject##cmd_rej_{s}_{d}", .{ id_key, idx }), .{
                .w = 62.0,
                .h = 24.0,
                .bordered = true,
            })) {
                action = .rejected;
            }
            if (uic.chip(uic.fmt("Accept##cmd_acc_{s}_{d}", .{ id_key, idx }), .{
                .w = 66.0,
                .h = 24.0,
                .active = true,
                .bordered = true,
            })) {
                action = .accepted;
            }
        }
    }

    return .{
        .action = action,
        .toggled = toggled,
        .right_clicked = right_clicked,
        .expanded = expanded,
        .header_rect = r,
    };
}

pub fn commandExecutionCard(
    uic: *Context,
    id_key: []const u8,
    idx: usize,
    cmd_line: []const u8,
    output_body: []const u8,
    status: CommandCardStatus,
) CommandCardAction {
    return commandExecutionCardEx(uic, id_key, idx, cmd_line, output_body, status, .{}).action;
}

/// Strips a leading `"(Recommended)"` prefix from an option label and returns the cleaned label + `is_recommended`.
pub fn parseRecommendedOptionLabel(raw_text: []const u8) struct { label: []const u8, is_recommended: bool } {
    const trimmed = std.mem.trim(u8, raw_text, " \t\r\n");
    const prefix = "(Recommended)";
    if (std.mem.startsWith(u8, trimmed, prefix)) {
        const rest = std.mem.trimStart(u8, trimmed[prefix.len..], " \t:-");
        if (rest.len > 0) {
            return .{ .label = rest, .is_recommended = true };
        }
    }
    return .{ .label = raw_text, .is_recommended = false };
}

pub fn measureSelectableOptionCardHeight(
    uic: *Context,
    opt_label: []const u8,
    is_recommended: bool,
    max_text_w: f32,
) f32 {
    const badge_reserve: f32 = if (is_recommended) 84.0 else 0.0;
    const base_w = if (max_text_w > 0.0) max_text_w else @max(80.0, uic.availableWidth() - 34.0);
    const eff_w = @max(60.0, base_w - badge_reserve);
    const o_lines = virtual_list.wrapPlainText(uic, uic.font_body, opt_label, eff_w);
    const opt_line_h: f32 = 17.5;
    return @as(f32, @floatFromInt(@max(o_lines.len, 1))) * opt_line_h + 10.0;
}

/// Renders a rounded selectable option card with wrapped label lines, optional `Recommended` pill badge,
/// and radio circle or multi-select checkbox indicator (`✓`), returning `true` when clicked.
pub fn selectableOptionCard(
    uic: *Context,
    id_str: []const u8,
    opt_label: []const u8,
    is_recommended: bool,
    is_selected: bool,
    is_multi: bool,
    max_text_w: f32,
) bool {
    const opt_line_h: f32 = 17.5;
    const badge_reserve: f32 = if (is_recommended) 84.0 else 0.0;
    const base_w = if (max_text_w > 0.0) max_text_w else @max(80.0, uic.availableWidth() - 34.0);
    const eff_w = @max(60.0, base_w - badge_reserve);
    const o_lines = virtual_list.wrapPlainText(uic, uic.font_body, opt_label, eff_w);
    const o_h = @as(f32, @floatFromInt(@max(o_lines.len, 1))) * opt_line_h + 10.0;

    const opt_r = uic.nextRect(0, o_h);
    const opt_wid = uic.resolveIdAndLabel(id_str).wid;
    const clicked = uic.trackInteraction(opt_wid, opt_r, opt_r);
    const hovered = (uic.hot_id == opt_wid);
    if (hovered) uic.setCursor(.pointing_hand);
    if (clicked) uic.invalidateWindow();

    if (uic.shouldPaint(opt_r)) {
        uic.paint.setStyle(.fill);
        uic.paint.setColor(if (is_selected)
            Color.argb(46, 56, 139, 253)
        else if (hovered)
            Color.rgb(28, 35, 48)
        else
            Color.rgb(15, 20, 28));
        uic.canvas.drawRoundRect(opt_r, 6.0, 6.0, uic.paint);

        uic.paint.setStyle(.stroke);
        uic.paint.setStrokeWidth(1.0);
        uic.paint.setColor(if (is_selected)
            Color.argb(180, 88, 166, 255)
        else if (hovered)
            Color.rgb(58, 68, 84)
        else
            Color.rgb(36, 43, 55));
        uic.canvas.drawRoundRect(opt_r, 6.0, 6.0, uic.paint);

        const ind_cx = opt_r.left + 14.0;
        const ind_cy = opt_r.top + 14.0;
        if (is_multi) {
            const box_r = Rect.xywh(ind_cx - 6.0, ind_cy - 6.0, 12.0, 12.0);
            if (is_selected) {
                uic.paint.setStyle(.fill);
                uic.paint.setColor(uic.theme.accent);
                uic.canvas.drawRoundRect(box_r, 3.0, 3.0, uic.paint);
                uic.paint.setColor(Color.white);
                uic.drawTextCached(uic.font_body, "✓", box_r.left + 1.5, box_r.top + 10.5);
            } else {
                uic.paint.setStyle(.stroke);
                uic.paint.setStrokeWidth(1.2);
                uic.paint.setColor(Color.rgb(110, 118, 129));
                uic.canvas.drawRoundRect(box_r, 3.0, 3.0, uic.paint);
            }
        } else {
            uic.paint.setStyle(.stroke);
            uic.paint.setStrokeWidth(1.3);
            uic.paint.setColor(if (is_selected) uic.theme.accent_hover else Color.rgb(110, 118, 129));
            uic.canvas.drawCircle(ind_cx, ind_cy, 5.5, uic.paint);
            if (is_selected) {
                uic.paint.setStyle(.fill);
                uic.paint.setColor(uic.theme.accent_hover);
                uic.canvas.drawCircle(ind_cx, ind_cy, 2.8, uic.paint);
            }
        }

        var text_clip_right = opt_r.right - 6.0;
        if (is_recommended) {
            const rec_txt = "Recommended";
            const rec_tw = uic.measureTextCached(uic.font_mono, rec_txt);
            const pill_w = rec_tw + 10.0;
            const pill_r = Rect.xywh(opt_r.right - pill_w - 6.0, opt_r.top + 5.0, pill_w, 17.5);
            text_clip_right = @max(opt_r.left + 32.0, pill_r.left - 4.0);

            uic.paint.setStyle(.fill);
            uic.paint.setColor(Color.argb(42, 56, 139, 253));
            uic.canvas.drawRoundRect(pill_r, 4.0, 4.0, uic.paint);

            uic.paint.setStyle(.stroke);
            uic.paint.setStrokeWidth(1.0);
            uic.paint.setColor(Color.argb(120, 88, 166, 255));
            uic.canvas.drawRoundRect(pill_r, 4.0, 4.0, uic.paint);

            uic.paint.setStyle(.fill);
            uic.paint.setColor(Color.rgb(121, 192, 255));
            uic.drawTextCached(uic.font_mono, rec_txt, pill_r.left + 5.0, pill_r.top + 13.0);
        }

        const save_cnt = uic.canvas.save();
        defer uic.canvas.restoreToCount(save_cnt);
        uic.canvas.clipRect(Rect.ltrb(opt_r.left + 24.0, opt_r.top, text_clip_right, opt_r.bottom), .intersect, false);

        uic.paint.setStyle(.fill);
        uic.paint.setColor(if (is_selected or hovered) Color.rgb(240, 246, 252) else Color.rgb(201, 209, 217));
        for (o_lines, 0..) |oline, ol_idx| {
            const oy = opt_r.top + 18.0 + @as(f32, @floatFromInt(ol_idx)) * opt_line_h;
            uic.drawTextCached(uic.font_body, oline, opt_r.left + 26.0, oy);
        }
    }

    return clicked;
}

/// Renders a menu row with an optional right-side secondary pill button (`High ▸`),
/// returning `.{ .row_clicked, .subtrigger_clicked, .subtrigger_hovered, .row_rect }`.
pub fn menuItemWithSubtrigger(
    uic: *Context,
    id_str: []const u8,
    label: []const u8,
    selected: bool,
    subtrigger_label: ?[]const u8,
    subtrigger_open: bool,
) SplitMenuItemResult {
    const resolved = uic.resolveIdAndLabel(id_str);
    const display_lbl = if (label.len > 0) uic.resolveIdAndLabel(label).display else resolved.display;
    const effort_wid = resolved.wid ^ 0xEFF0_8711;
    const r = uic.nextRect(0, 28.0);

    const pill_lbl = if (subtrigger_label) |sub_txt|
        (if (sub_txt.len == 0)
            ""
        else if (std.mem.indexOf(u8, sub_txt, "▸") != null)
            sub_txt
        else
            uic.fmt("{s} ▸", .{sub_txt}))
    else
        "";
    const has_sub = pill_lbl.len > 0;
    const pill_tw = if (has_sub) uic.measureTextCached(uic.font_body, pill_lbl) else 0.0;
    const eff_w = @max(50.0, pill_tw + 14.0);
    const eff_rect = Rect.xywh(r.right - eff_w - 4.0, r.top + 3.0, eff_w, 22.0);
    const main_rect = if (has_sub)
        Rect.ltrb(r.left, r.top, eff_rect.left - 2.0, r.bottom)
    else
        r;

    const subtrigger_clicked = if (has_sub) uic.trackInteraction(effort_wid, eff_rect, r) else false;
    const subtrigger_hovered = if (has_sub) uic.isHovered(eff_rect) else false;
    const row_clicked = if (!subtrigger_clicked and !subtrigger_hovered)
        uic.trackInteraction(resolved.wid, main_rect, r)
    else
        false;

    if (uic.shouldPaint(r)) {
        const row_hov = (uic.hot_id == resolved.wid or subtrigger_hovered or subtrigger_open);
        if (row_hov or selected) {
            uic.paint.setStyle(.fill);
            uic.paint.setColor(if (row_hov) Color.rgb(34, 41, 54) else Color.argb(40, 56, 139, 253));
            uic.canvas.drawRoundRect(r, 5.0, 5.0, uic.paint);
        }

        const by = r.top + 18.5;
        uic.paint.setStyle(.fill);
        if (selected) {
            uic.paint.setColor(Color.rgb(88, 166, 255));
            uic.drawTextCached(uic.font_body, "✓", r.left + 7.0, by);
        }

        {
            const save_cnt = uic.canvas.save();
            defer uic.canvas.restoreToCount(save_cnt);
            const clip_r = if (has_sub) eff_rect.left - 4.0 else r.right - 6.0;
            uic.canvas.clipRect(Rect.ltrb(r.left + 20.0, r.top, clip_r, r.bottom), .intersect, false);

            uic.paint.setColor(if (selected or row_hov) Color.rgb(240, 246, 252) else Color.rgb(185, 194, 204));
            uic.drawTextCached(uic.font_body, display_lbl, r.left + 22.0, by);
        }

        if (has_sub) {
            uic.paint.setStyle(.fill);
            uic.paint.setColor(if (subtrigger_hovered or subtrigger_open)
                Color.argb(75, 56, 139, 253)
            else
                Color.rgb(28, 34, 45));
            uic.canvas.drawRoundRect(eff_rect, 4.5, 4.5, uic.paint);

            uic.paint.setStyle(.stroke);
            uic.paint.setStrokeWidth(1.0);
            uic.paint.setColor(if (subtrigger_hovered or subtrigger_open)
                Color.argb(140, 88, 166, 255)
            else
                Color.rgb(48, 56, 68));
            uic.canvas.drawRoundRect(eff_rect, 4.5, 4.5, uic.paint);

            uic.paint.setStyle(.fill);
            uic.paint.setColor(if (subtrigger_hovered or subtrigger_open)
                Color.rgb(121, 192, 255)
            else
                Color.rgb(139, 148, 158));
            uic.drawTextCached(
                uic.font_body,
                pill_lbl,
                eff_rect.left + @max(4.0, (eff_w - pill_tw) * 0.5),
                r.top + 18.0,
            );
        }
    }

    if (row_clicked or subtrigger_clicked) uic.invalidateWindow();
    return .{
        .row_clicked = row_clicked,
        .subtrigger_clicked = subtrigger_clicked,
        .subtrigger_hovered = subtrigger_hovered,
        .row_rect = r,
    };
}

/// Renders either a thumbnail gallery row (`opts.removable == false`) or a compact removable attachment
/// pill strip (`opts.removable == true`), returning the 0-based index of the removed/clicked item (or `null`).
pub fn attachmentGallery(
    uic: *Context,
    id_prefix: []const u8,
    items: []const AttachmentDisplayItem,
    opts: AttachmentStripOptions,
) ?usize {
    if (items.len == 0) return null;

    var clicked_idx: ?usize = null;
    var removed_idx: ?usize = null;

    if (opts.removable) {
        const strip_h = opts.row_height orelse 46.0;
        const strip_r = uic.nextRect(0, strip_h);
        const avail_w = @max(80.0, strip_r.right - strip_r.left);
        const gap: f32 = 6.0;
        const f_count: f32 = @floatFromInt(items.len);
        const pill_w = @min(176.0, @max(92.0, (avail_w - gap * (f_count - 1.0)) / f_count));
        const pill_h: f32 = @max(24.0, strip_h - 2.0);

        for (items, 0..) |att, idx| {
            const px = strip_r.left + @as(f32, @floatFromInt(idx)) * (pill_w + gap);
            const pill_r = Rect.xywh(px, strip_r.top + 1.0, pill_w, pill_h);
            const close_r = Rect.xywh(pill_r.right - 20.0, pill_r.top + 4.0, 16.0, 16.0);
            const body_r = Rect.ltrb(pill_r.left, pill_r.top, close_r.left - 2.0, pill_r.bottom);

            const close_wid = uic.resolveIdAndLabel(uic.fmt("##{s}_rm_{d}", .{ id_prefix, idx })).wid;
            const body_wid = uic.resolveIdAndLabel(uic.fmt("##{s}_open_{d}", .{ id_prefix, idx })).wid;

            const close_clicked = uic.trackInteraction(close_wid, close_r, strip_r);
            const close_hovered = (uic.hot_id == close_wid);
            const body_clicked = if (!close_clicked and !close_hovered)
                uic.trackInteraction(body_wid, body_r, strip_r)
            else
                false;
            const body_hovered = (uic.hot_id == body_wid);

            if (close_hovered or body_hovered) uic.setCursor(.pointing_hand);
            if (close_clicked) {
                removed_idx = idx;
                uic.invalidateWindow();
            } else if (body_clicked) {
                clicked_idx = idx;
                uic.invalidateWindow();
            }

            if (uic.shouldPaint(strip_r)) {
                uic.paint.setStyle(.fill);
                uic.paint.setColor(if (body_hovered) Color.rgb(28, 35, 47) else Color.rgb(16, 21, 29));
                uic.canvas.drawRoundRect(pill_r, 6.0, 6.0, uic.paint);

                uic.paint.setStyle(.stroke);
                uic.paint.setStrokeWidth(1.0);
                uic.paint.setColor(if (body_hovered) uic.theme.accent else Color.rgb(46, 55, 68));
                uic.canvas.drawRoundRect(pill_r, 6.0, 6.0, uic.paint);

                const thumb_r = Rect.xywh(pill_r.left + 4.0, pill_r.top + 4.0, 36.0, 36.0);
                _ = root.drawImageThumbnail(uic, thumb_r, att.path, "", 4.5);

                const text_left = thumb_r.right + 6.0;
                const text_right = close_r.left - 2.0;
                if (text_right > text_left) {
                    const save_c = uic.canvas.save();
                    defer uic.canvas.restoreToCount(save_c);
                    uic.canvas.clipRect(Rect.ltrb(text_left, pill_r.top, text_right, pill_r.bottom), .intersect, false);

                    const disp_name = if (att.name.len > 0)
                        att.name
                    else if (std.mem.lastIndexOfScalar(u8, att.path, '/')) |slash|
                        (if (slash + 1 < att.path.len) att.path[slash + 1 ..] else att.path)
                    else
                        att.path;

                    uic.paint.setStyle(.fill);
                    uic.paint.setColor(Color.rgb(230, 237, 243));
                    uic.drawTextCached(uic.font_body, disp_name, text_left, pill_r.top + 18.0);

                    const meta_str = if (att.meta.len > 0)
                        att.meta
                    else if (att.width > 0 and att.height > 0)
                        uic.fmt("{d}×{d}", .{ att.width, att.height })
                    else
                        "Image";
                    uic.paint.setColor(Color.rgb(125, 133, 144));
                    uic.drawTextCached(uic.font_mono, meta_str, text_left, pill_r.top + 34.0);
                }

                if (close_hovered) {
                    uic.paint.setStyle(.fill);
                    uic.paint.setColor(Color.argb(90, 248, 81, 73));
                    uic.canvas.drawRoundRect(close_r, 4.0, 4.0, uic.paint);
                }
                uic.drawIcon(
                    .close,
                    Rect.ltrb(close_r.left + 2.5, close_r.top + 2.5, close_r.right - 2.5, close_r.bottom - 2.5),
                    if (close_hovered) Color.rgb(255, 123, 114) else Color.rgb(139, 148, 158),
                );
            }
        }
    } else {
        const row_h = opts.row_height orelse 88.0;
        const row_r = uic.nextRect(0, row_h);
        const avail_w = @max(80.0, row_r.right - row_r.left);
        const gap: f32 = 8.0;
        const f_count: f32 = @floatFromInt(items.len);
        const card_w = @min(138.0, @max(76.0, (avail_w - gap * (f_count - 1.0)) / f_count));
        const card_h: f32 = @max(28.0, row_h - 4.0);
        const total_w = card_w * f_count + gap * (f_count - 1.0);
        const start_x = if (opts.align_right)
            @max(row_r.left, row_r.right - total_w)
        else
            row_r.left;

        for (items, 0..) |att, i| {
            const cx = start_x + @as(f32, @floatFromInt(i)) * (card_w + gap);
            const card_r = Rect.xywh(cx, row_r.top + 2.0, card_w, card_h);
            const wid = uic.resolveIdAndLabel(uic.fmt("##{s}_media_{d}", .{ id_prefix, i })).wid;
            const clicked = uic.trackInteraction(wid, card_r, row_r);
            const hovered = (uic.hot_id == wid);
            if (hovered) uic.setCursor(.pointing_hand);
            if (clicked) {
                clicked_idx = i;
                uic.invalidateWindow();
            }

            if (uic.shouldPaint(row_r)) {
                uic.paint.setStyle(.fill);
                uic.paint.setColor(Color.rgb(18, 24, 33));
                uic.canvas.drawRoundRect(card_r, 7.0, 7.0, uic.paint);

                const inner_r = Rect.ltrb(card_r.left + 2.0, card_r.top + 2.0, card_r.right - 2.0, card_r.bottom - 2.0);
                _ = root.drawImageThumbnail(uic, inner_r, att.path, "", 5.5);

                const base_name = if (att.name.len > 0)
                    att.name
                else if (std.mem.lastIndexOfScalar(u8, att.path, '/')) |slash|
                    (if (slash + 1 < att.path.len) att.path[slash + 1 ..] else att.path)
                else
                    att.path;
                const scrim_r = Rect.ltrb(card_r.left + 2.0, card_r.bottom - 19.0, card_r.right - 2.0, card_r.bottom - 2.0);
                uic.paint.setStyle(.fill);
                uic.paint.setColor(Color.argb(185, 10, 14, 20));
                uic.canvas.drawRoundRect(scrim_r, 4.0, 4.0, uic.paint);

                const save_c = uic.canvas.save();
                defer uic.canvas.restoreToCount(save_c);
                uic.canvas.clipRect(Rect.ltrb(scrim_r.left + 4.0, scrim_r.top, scrim_r.right - 4.0, scrim_r.bottom), .intersect, false);
                uic.paint.setColor(Color.rgb(218, 226, 235));
                uic.drawTextCached(uic.font_mono, base_name, scrim_r.left + 5.0, scrim_r.bottom - 4.5);

                uic.paint.setStyle(.stroke);
                uic.paint.setStrokeWidth(if (hovered) 1.3 else 1.0);
                uic.paint.setColor(if (hovered) uic.theme.accent else Color.argb(145, 68, 80, 98));
                uic.canvas.drawRoundRect(card_r, 7.0, 7.0, uic.paint);
            }
        }
    }

    if (opts.removed_idx_out) |rm_out| rm_out.* = removed_idx;
    if (opts.clicked_idx_out) |cl_out| cl_out.* = clicked_idx;
    return removed_idx orelse clicked_idx;
}

/// Renders a centered empty-state hero block inside `rect` with `title`, optional `subtitle`, and optional `hint`.
pub fn emptyStateHero(
    uic: *Context,
    rect: layout.Rect,
    title: []const u8,
    subtitle: []const u8,
    hint: ?[]const u8,
) void {
    if (!uic.shouldPaint(rect)) return;

    const cx = (rect.left + rect.right) * 0.5;
    const has_sub = subtitle.len > 0;
    const has_hint = if (hint) |h| h.len > 0 else false;

    uic.paint.setStyle(.fill);
    if (!has_sub and !has_hint) {
        const tw = uic.measureTextCached(uic.font_body, title);
        const by = rect.top + (rect.bottom - rect.top) * 0.5 + 4.0;
        uic.paint.setColor(Color.rgb(139, 148, 158));
        uic.drawTextCached(uic.font_body, title, cx - tw * 0.5, by);
        return;
    }

    const tw = uic.measureTextCached(uic.font_body, title);
    uic.paint.setColor(Color.rgb(230, 237, 243));
    uic.drawTextCached(uic.font_body, title, cx - tw * 0.5, rect.top + 20.0);

    if (has_sub) {
        const sw = uic.measureTextCached(uic.font_body, subtitle);
        uic.paint.setColor(Color.rgb(110, 118, 129));
        uic.drawTextCached(uic.font_body, subtitle, cx - sw * 0.5, rect.top + 38.0);
    }

    if (hint) |h_str| {
        if (h_str.len > 0) {
            const hw = uic.measureTextCached(uic.font_mono, h_str);
            uic.paint.setColor(Color.rgb(92, 100, 112));
            uic.drawTextCached(uic.font_mono, h_str, cx - hw * 0.5, rect.top + (if (has_sub) @as(f32, 54.0) else @as(f32, 38.0)));
        }
    }
}

test "cards: inlineStepRow, thinkingDisclosure, commandExecutionCard, selectableOptionCard, menuItemWithSubtrigger, attachmentGallery, emptyStateHero 2-phase determinism" {
    const surface = try skia.Surface.initRasterN32Premul(360, 480);
    defer surface.deinit();
    const paint = try skia.Paint.init();
    defer paint.deinit();
    const font = try skia.Font.init(null, 13.0);
    defer font.deinit();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var uic = Context{
        .arena = arena.allocator(),
        .canvas = surface.canvas(),
        .paint = paint,
        .font_title = font,
        .font_body = font,
        .font_mono = font,
    };
    defer uic.deinit();

    const attachments = [_]AttachmentDisplayItem{
        .{ .path = "assets/preview.png", .name = "preview.png", .width = 640, .height = 480 },
    };

    const buildCardsScene = struct {
        fn build(ctx: *Context, att_items: []const AttachmentDisplayItem, out_cmd_act: *CommandCardAction) void {
            ctx.inlineStepRow("›", Color.rgb(110, 118, 129), "read_file", "src/ui/root.zig");
            ctx.thinkingDisclosure("test_think", 0, "Thought for 2s", "Analyzing layout invariants\n- Step 1\n- Step 2", true);
            out_cmd_act.* = ctx.commandExecutionCard("test_cmd", 1, "zig build test", "All tests passed.", .pending_approval);
            _ = ctx.selectableOptionCard("##opt_0", "Use two-phase layout engine", true, true, false, 240.0);
            _ = ctx.selectableOptionCard("##opt_1", "Support multi-select checkboxes", false, false, true, 240.0);
            _ = ctx.menuItemWithSubtrigger("##model_row", "Claude Sonnet 4.5", true, "High", false);
            _ = ctx.attachmentGallery("usr_gal", att_items, .{ .removable = false, .align_right = true });
            _ = ctx.attachmentGallery("comp_strip", att_items, .{ .removable = true });
            const hero_r = ctx.nextRect(0, 56.0);
            ctx.emptyStateHero(hero_r, "What can I help you build?", "Ask a question or reference files with @", "Cmd+L to focus");
        }
    }.build;

    var cmd_action: CommandCardAction = .none;
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 360, 480), 20, 20, false, false, false);
    buildCardsScene(&uic, &attachments, &cmd_action);
    uic.endPass();

    uic.clip_damage = Rect.xywh(0, 0, 360, 480);
    uic.beginPass(.paint, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 360, 480), 20, 20, false, false, false);
    buildCardsScene(&uic, &attachments, &cmd_action);
    uic.endPass();

    try std.testing.expectEqual(uic.last_input_rect_count, uic.last_paint_rect_count);
}
