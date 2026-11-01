//! Declarative Responsive Per-Pane Mode-Line & Status Strip Builder (`src/ui/mode_line.zig`).
//!
//! Provides a bidirectional (`cur_x` left-to-right, `right_x` right-to-left) layout & paint
//! builder (`ModeLine` / `uic.beginModeLine`) for Emacs/Doom-style window mode lines and
//! status strips. Automatically elides trailing right-side status pills when the pane is
//! too narrow (`right_x - w < cur_x + 8.0`) while preserving strict two-phase (`Pass.input`
//! == `Pass.paint`) layout determinism.

const std = @import("std");
const skia = @import("skia");
const root = @import("root.zig");
const layout = @import("layout.zig");
const icons = @import("icons.zig");

const c = skia.c;
const Color = skia.Color;
const Rect = skia.Rect;
const Context = root.Context;
const WidgetId = root.WidgetId;
const Icon = icons.Icon;

/// Configuration options for `Context.beginModeLine`.
pub const ModeLineOptions = struct {
    is_active_pane: bool = false,
    can_drag_vertical: bool = false,
    bg_color: ?u32 = null,
    top_border_color: ?u32 = null,
    bottom_border_color: ?u32 = null,
    accent_color: ?u32 = null,
    right_reserve: f32 = 0.0,
};

/// Result of an interactive mode-line segment (`drawGitBranchPill`, `drawRightStatusPill`, `drawTitle`).
pub const ModeLineClickResult = struct {
    clicked: bool = false,
    right_clicked: bool = false,
    hovered: bool = false,
    rect: c.sk_rect_t = .{ .left = 0, .top = 0, .right = 0, .bottom = 0 },
};

/// Built-in trailing action icon kinds for `ModeLine.drawRightIconAction`.
pub const ModeLineIconKind = enum {
    split_right,
    split_down,
    close,
};

/// Bidirectional responsive per-pane mode-line cursor initialized by `uic.beginModeLine(...)`.
pub const ModeLine = struct {
    uic: *Context,
    bar_r: layout.Rect,
    opts: ModeLineOptions,
    sash_wid: WidgetId,
    cur_x: f32,
    right_x: f32,
    baseline_y: f32,
    child_hovered: bool = false,
    title_click: ModeLineClickResult = .{},

    /// Draws the square Doom Emacs-style window number badge (`1`, `2`, ...) at `cur_x`.
    pub fn drawWindowNumberBadge(self: *ModeLine, num: u16, is_active: bool) void {
        const bar_h = self.bar_r.bottom - self.bar_r.top;
        const badge_w: f32 = 18.0;
        const badge_h: f32 = 16.0;
        const win_badge_r = Rect.xywh(
            self.cur_x,
            self.bar_r.top + (bar_h - badge_h) * 0.5,
            badge_w,
            badge_h,
        );
        self.cur_x += badge_w + 7.0;

        if (self.uic.shouldPaint(self.bar_r)) {
            self.uic.paint.setStyle(.fill);
            self.uic.paint.setColor(if (is_active)
                Color.argb(48, 56, 139, 253)
            else
                Color.argb(45, 100, 116, 139));
            self.uic.canvas.drawRoundRect(win_badge_r, 3.5, 3.5, self.uic.paint);

            if (is_active) {
                self.uic.paint.setStyle(.stroke);
                self.uic.paint.setStrokeWidth(1.0);
                self.uic.paint.setColor(Color.argb(140, 88, 166, 255));
                self.uic.canvas.drawRoundRect(win_badge_r, 3.5, 3.5, self.uic.paint);
                self.uic.paint.setStyle(.fill);
            }

            const win_num_str = self.uic.fmt("{d}", .{num});
            const win_num_w = self.uic.measureTextCached(self.uic.font_mono, win_num_str);
            self.uic.paint.setColor(if (is_active)
                Color.rgb(121, 192, 255)
            else
                self.uic.theme.text_muted);
            self.uic.drawTextCached(
                self.uic.font_mono,
                win_num_str,
                win_badge_r.left + (badge_w - win_num_w) * 0.5,
                self.baseline_y - 0.5,
            );
        }
    }

    /// Draws the interactive buffer/file title segment (`README.md`, `main.zig *`) at `cur_x`
    /// and records left/right click state in `self.title_click`.
    pub fn drawTitle(self: *ModeLine, title: []const u8, modified: bool, is_active: bool) void {
        const disp_name = if (modified) self.uic.fmt("{s} *", .{title}) else title;
        const name_w = self.uic.measureTextCached(self.uic.font_mono, disp_name);
        const bar_h = self.bar_r.bottom - self.bar_r.top;
        const hit_r = Rect.xywh(self.cur_x - 4.0, self.bar_r.top + 2.0, name_w + 8.0, @max(4.0, bar_h - 4.0));
        const name_wid = self.uic.resolveIdAndLabel("##emacs_modeline_bufname").wid;

        const hovered = self.uic.isHovered(hit_r);
        const left_clicked = self.uic.trackInteraction(name_wid, hit_r, self.bar_r);
        var right_clicked = false;
        if (hovered) {
            self.child_hovered = true;
            if (self.uic.pass == .input) {
                self.uic.setCursor(.pointing_hand);
                if (self.uic.right_mouse_pressed) {
                    right_clicked = true;
                    self.uic.markDirty(self.bar_r);
                }
            }
        }

        self.title_click = .{
            .clicked = left_clicked,
            .right_clicked = right_clicked,
            .hovered = hovered,
            .rect = hit_r,
        };

        if (self.uic.shouldPaint(self.bar_r) and self.cur_x < self.right_x) {
            const save_clip = self.uic.canvas.save();
            defer self.uic.canvas.restoreToCount(save_clip);
            self.uic.canvas.clipRect(
                Rect.ltrb(self.bar_r.left, self.bar_r.top, self.right_x, self.bar_r.bottom),
                .intersect,
                false,
            );

            if (self.uic.hot_id == name_wid) {
                self.uic.paint.setStyle(.fill);
                self.uic.paint.setColor(Color.argb(75, 100, 116, 139));
                self.uic.canvas.drawRoundRect(hit_r, 4.0, 4.0, self.uic.paint);
            }
            self.uic.paint.setStyle(.fill);
            self.uic.paint.setColor(if (modified)
                Color.rgb(251, 191, 36)
            else if (self.uic.hot_id == name_wid or is_active)
                self.uic.theme.text_primary
            else
                Color.rgb(165, 178, 196));
            self.uic.drawTextCached(self.uic.font_mono, disp_name, self.cur_x, self.baseline_y);
        }

        self.cur_x += name_w + 14.0;
    }

    /// Draws a compact rounded badge pill (e.g. `RO`, `[PREVIEW]`, `[WAVE]`, `[PDF]`, `[DIFF]`, `[TERM]`, `[AGENT]`).
    pub fn drawBadgePill(
        self: *ModeLine,
        text: []const u8,
        fg_color: u32,
        bg_color: u32,
        border_color: ?u32,
    ) void {
        if (text.len == 0) return;
        const tw = self.uic.measureTextCached(self.uic.font_mono, text);
        const pill_w = tw + 10.0;
        const pill_h: f32 = 16.0;
        const bar_h = self.bar_r.bottom - self.bar_r.top;
        const pill_r = Rect.xywh(
            self.cur_x,
            self.bar_r.top + (bar_h - pill_h) * 0.5,
            pill_w,
            pill_h,
        );

        if (self.uic.shouldPaint(self.bar_r) and self.cur_x + pill_w <= self.right_x) {
            self.uic.paint.setStyle(.fill);
            self.uic.paint.setColor(bg_color);
            self.uic.canvas.drawRoundRect(pill_r, 3.5, 3.5, self.uic.paint);

            if (border_color) |bc| {
                self.uic.paint.setStyle(.stroke);
                self.uic.paint.setStrokeWidth(1.0);
                self.uic.paint.setColor(bc);
                self.uic.canvas.drawRoundRect(pill_r, 3.5, 3.5, self.uic.paint);
            }

            self.uic.paint.setStyle(.fill);
            self.uic.paint.setColor(fg_color);
            self.uic.drawTextCached(self.uic.font_mono, text, pill_r.left + 5.0, self.baseline_y - 0.5);
        }

        self.cur_x += pill_w + 10.0;
    }

    /// Draws a plain text segment at `cur_x` and advances `cur_x` by `measureTextCached(font, text) + gap_after`.
    /// Accepts either `*const skia.Font`, `*skia.Font`, or `skia.Font` by value.
    pub fn drawText(
        self: *ModeLine,
        text: []const u8,
        font: anytype,
        color: u32,
        gap_after: f32,
    ) void {
        if (text.len == 0) return;
        const f: skia.Font = switch (@typeInfo(@TypeOf(font))) {
            .pointer => font.*,
            else => font,
        };
        const tw = self.uic.measureTextCached(f, text);

        if (self.uic.shouldPaint(self.bar_r) and self.cur_x < self.right_x) {
            const save_clip = self.uic.canvas.save();
            defer self.uic.canvas.restoreToCount(save_clip);
            self.uic.canvas.clipRect(
                Rect.ltrb(self.bar_r.left, self.bar_r.top, self.right_x, self.bar_r.bottom),
                .intersect,
                false,
            );
            self.uic.paint.setStyle(.fill);
            self.uic.paint.setColor(color);
            self.uic.drawTextCached(f, text, self.cur_x, self.baseline_y);
        }

        self.cur_x += tw + gap_after;
    }

    /// Draws an interactive clickable Git branch pill with a crisp `.git` vector icon at `cur_x`.
    pub fn drawGitBranchPill(
        self: *ModeLine,
        id_str: []const u8,
        branch_text: []const u8,
        is_dirty: bool,
        is_open: bool,
    ) ModeLineClickResult {
        const tw = self.uic.measureTextCached(self.uic.font_mono, branch_text);
        const pill_w = 20.0 + tw + 8.0;
        const pill_h: f32 = 18.0;
        const bar_h = self.bar_r.bottom - self.bar_r.top;
        const pill_r = Rect.xywh(
            self.cur_x,
            self.bar_r.top + (bar_h - pill_h) * 0.5,
            pill_w,
            pill_h,
        );
        self.cur_x += pill_w + 12.0;

        const wid = self.uic.resolveIdAndLabel(id_str).wid;
        const hovered = self.uic.isHovered(pill_r);
        const clicked = self.uic.trackInteraction(wid, pill_r, self.bar_r);
        var right_clicked = false;
        if (hovered) {
            self.child_hovered = true;
            if (self.uic.pass == .input) {
                self.uic.setCursor(.pointing_hand);
                if (self.uic.right_mouse_pressed) {
                    right_clicked = true;
                    self.uic.markDirty(self.bar_r);
                }
            }
        }
        if (clicked) self.uic.invalidateWindow();

        if (self.uic.shouldPaint(self.bar_r) and pill_r.left < self.right_x) {
            const save_clip = self.uic.canvas.save();
            defer self.uic.canvas.restoreToCount(save_clip);
            self.uic.canvas.clipRect(
                Rect.ltrb(self.bar_r.left, self.bar_r.top, self.right_x, self.bar_r.bottom),
                .intersect,
                false,
            );

            if (is_open or hovered) {
                self.uic.paint.setStyle(.fill);
                self.uic.paint.setColor(if (is_open)
                    Color.argb(75, 56, 139, 253)
                else
                    Color.argb(65, 100, 116, 139));
                self.uic.canvas.drawRoundRect(pill_r, 4.0, 4.0, self.uic.paint);
            }

            const fg = if (is_dirty)
                Color.rgb(251, 191, 36)
            else if (is_open or hovered)
                self.uic.theme.text_primary
            else if (self.opts.is_active_pane)
                Color.rgb(148, 163, 184)
            else
                self.uic.theme.text_muted;

            const icon_r = Rect.xywh(pill_r.left + 2.0, pill_r.top + 1.0, 14.0, 16.0);
            self.uic.drawIcon(.git, icon_r, fg);
            self.uic.paint.setStyle(.fill);
            self.uic.paint.setColor(fg);
            self.uic.drawTextCached(self.uic.font_mono, branch_text, pill_r.left + 20.0, self.baseline_y);
        }

        return .{
            .clicked = clicked,
            .right_clicked = right_clicked,
            .hovered = hovered,
            .rect = pill_r,
        };
    }

    /// Renders a trailing `18x18` vector icon action button at `right_x` and decrements `right_x`.
    pub fn drawRightIconAction(
        self: *ModeLine,
        id_str: []const u8,
        icon_kind: ModeLineIconKind,
        tooltip: []const u8,
    ) bool {
        _ = tooltip;
        const btn_size: f32 = 18.0;
        const bar_h = self.bar_r.bottom - self.bar_r.top;
        const btn_x = self.right_x - btn_size;
        const btn_y = self.bar_r.top + (bar_h - btn_size) * 0.5;
        const btn_r = Rect.xywh(btn_x, btn_y, btn_size, btn_size);
        self.right_x = btn_x - 4.0;

        const wid = self.uic.resolveIdAndLabel(id_str).wid;
        const hovered = self.uic.isHovered(btn_r);
        const clicked = self.uic.trackInteraction(wid, btn_r, self.bar_r);
        if (hovered) {
            self.child_hovered = true;
            if (self.uic.pass == .input) {
                self.uic.setCursor(.pointing_hand);
            }
        }
        if (clicked) self.uic.invalidateWindow();

        if (self.uic.shouldPaint(self.bar_r)) {
            if (hovered) {
                self.uic.paint.setStyle(.fill);
                self.uic.paint.setColor(Color.argb(75, 100, 116, 139));
                self.uic.canvas.drawRoundRect(btn_r, 4.0, 4.0, self.uic.paint);
            }
            const icon: Icon = switch (icon_kind) {
                .split_right => .split_horizontal,
                .split_down => .split_vertical,
                .close => .close,
            };
            const icon_col = if (hovered) self.uic.theme.text_primary else self.uic.theme.text_muted;
            self.uic.drawIcon(icon, btn_r, icon_col);
        }

        return clicked;
    }

    /// Renders a clickable right-side status pill at `right_x` if `right_x - w >= cur_x + 8.0`,
    /// automatically eliding when the pane is too narrow.
    pub fn drawRightStatusPill(
        self: *ModeLine,
        id_str: []const u8,
        dot_color: ?u32,
        label: []const u8,
        text_color: u32,
        active_bg: bool,
    ) ModeLineClickResult {
        if (label.len == 0) return .{};
        const tw = self.uic.measureTextCached(self.uic.font_mono, label);
        const dot_pad: f32 = if (dot_color != null) 14.0 else 0.0;
        const pill_w = tw + dot_pad + 12.0;
        const pill_h: f32 = 18.0;

        if (self.right_x - pill_w < self.cur_x + 8.0) {
            return .{};
        }

        const bar_h = self.bar_r.bottom - self.bar_r.top;
        const pill_x = self.right_x - pill_w;
        const pill_y = self.bar_r.top + (bar_h - pill_h) * 0.5;
        const pill_r = Rect.xywh(pill_x, pill_y, pill_w, pill_h);
        self.right_x = pill_x - 6.0;

        const wid = self.uic.resolveIdAndLabel(id_str).wid;
        const hovered = self.uic.isHovered(pill_r);
        const clicked = self.uic.trackInteraction(wid, pill_r, self.bar_r);
        var right_clicked = false;
        if (hovered) {
            self.child_hovered = true;
            if (self.uic.pass == .input) {
                self.uic.setCursor(.pointing_hand);
                if (self.uic.right_mouse_pressed) {
                    right_clicked = true;
                    self.uic.markDirty(self.bar_r);
                }
            }
        }
        if (clicked) self.uic.invalidateWindow();

        if (self.uic.shouldPaint(self.bar_r)) {
            if (active_bg or hovered) {
                self.uic.paint.setStyle(.fill);
                self.uic.paint.setColor(if (active_bg)
                    Color.argb(75, 56, 139, 253)
                else
                    Color.argb(65, 100, 116, 139));
                self.uic.canvas.drawRoundRect(pill_r, 4.0, 4.0, self.uic.paint);
            }

            var tx = pill_r.left + 6.0;
            if (dot_color) |dc| {
                self.uic.paint.setStyle(.fill);
                self.uic.paint.setColor(dc);
                self.uic.canvas.drawCircle(tx + 3.0, (pill_r.top + pill_r.bottom) * 0.5, 3.0, self.uic.paint);
                tx += 14.0;
            }

            self.uic.paint.setStyle(.fill);
            self.uic.paint.setColor(if (hovered) self.uic.theme.text_primary else text_color);
            self.uic.drawTextCached(self.uic.font_mono, label, tx, self.baseline_y);
        }

        return .{
            .clicked = clicked,
            .right_clicked = right_clicked,
            .hovered = hovered,
            .rect = pill_r,
        };
    }

    /// Returns `true` during `Pass.input` when the user is dragging the mode-line sash vertically.
    pub fn isDraggingVertical(self: *const ModeLine) bool {
        return self.uic.pass == .input and
            self.opts.can_drag_vertical and
            self.uic.active_id == self.sash_wid and
            self.uic.mouse_down;
    }

    /// Returns `true` during `Pass.input` when the mode-line background sash was pressed (not on a child pill/button).
    pub fn sashPressed(self: *const ModeLine) bool {
        return self.uic.pass == .input and
            !self.child_hovered and
            self.uic.mouse_pressed and
            self.uic.active_id == self.sash_wid;
    }

    /// Returns `true` during `Pass.input` when the mode-line background was right-clicked (not on a child pill/button).
    pub fn backgroundRightClicked(self: *const ModeLine) bool {
        return self.uic.pass == .input and
            !self.child_hovered and
            self.uic.right_mouse_pressed and
            self.uic.isHovered(self.bar_r);
    }
};

/// Begins laying out and rendering a responsive per-pane mode-line inside `bar_r`.
pub fn beginModeLine(
    uic: *Context,
    id_str: []const u8,
    bar_r: layout.Rect,
    opts: ModeLineOptions,
) ModeLine {
    const sash_wid = uic.resolveIdAndLabel(id_str).wid;
    _ = uic.trackInteraction(sash_wid, bar_r, bar_r);

    const is_dragging = (uic.active_id == sash_wid and uic.mouse_down);
    const is_hovered = (uic.hot_id == sash_wid or is_dragging);
    if (uic.pass == .input and opts.can_drag_vertical and is_hovered) {
        uic.setCursor(.resize_ns);
    }

    const bar_w = @max(0.0, bar_r.right - bar_r.left);
    const bar_h = @max(0.0, bar_r.bottom - bar_r.top);

    if (uic.shouldPaint(bar_r)) {
        const bg_col = opts.bg_color orelse if (opts.is_active_pane)
            Color.rgb(33, 43, 60)
        else
            Color.rgb(17, 22, 31);
        uic.paint.setStyle(.fill);
        uic.paint.setColor(bg_col);
        uic.canvas.drawRect(bar_r, uic.paint);

        // Top & bottom subtle 1px border lines
        const top_col = opts.top_border_color orelse if (opts.is_active_pane)
            Color.argb(140, 56, 139, 253)
        else
            uic.theme.border_subtle;
        uic.paint.setColor(top_col);
        uic.canvas.drawRect(Rect.xywh(bar_r.left, bar_r.top, bar_w, 1.0), uic.paint);

        const bot_col = opts.bottom_border_color orelse uic.theme.border_subtle;
        uic.paint.setColor(bot_col);
        uic.canvas.drawRect(Rect.xywh(bar_r.left, bar_r.bottom - 1.0, bar_w, 1.0), uic.paint);

        // Active-pane 3px left accent bar
        if (opts.is_active_pane) {
            uic.paint.setColor(opts.accent_color orelse Color.rgb(56, 139, 253));
            uic.canvas.drawRect(Rect.xywh(bar_r.left, bar_r.top, 3.0, bar_h), uic.paint);
        }
    }

    return .{
        .uic = uic,
        .bar_r = bar_r,
        .opts = opts,
        .sash_wid = sash_wid,
        .cur_x = bar_r.left + 7.0,
        .right_x = bar_r.right - 6.0 - opts.right_reserve,
        .baseline_y = bar_r.top + @floor(bar_h * 0.5) + 4.0,
    };
}

test "mode_line: beginModeLine, left/right segment layout, narrow-pane elision, and click interactions across .input and .paint" {
    const surface = try skia.Surface.initRasterN32Premul(800, 120);
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

    const win_rect = Rect.xywh(0, 0, 800, 120);
    const wide_bar = Rect.xywh(0, 40, 760, 24);

    // 1. Wide pane: both left and right status pills fit and advance cursors cleanly across .input and .paint
    var git_pill_rect: c.sk_rect_t = undefined;
    var sc_pill_rect: c.sk_rect_t = undefined;
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 10, 10, false, false, false);
    {
        var ml = uic.beginModeLine("##test_ml_wide", wide_bar, .{
            .is_active_pane = true,
            .can_drag_vertical = true,
        });
        const start_left = ml.cur_x;
        const start_right = ml.right_x;
        ml.drawWindowNumberBadge(1, true);
        ml.drawTitle("editor_pane.zig", true, true);
        ml.drawBadgePill("[DIFF]", Color.rgb(121, 192, 255), Color.argb(45, 56, 139, 253), null);
        ml.drawText("42% L120:8", &uic.font_mono, Color.rgb(203, 213, 225), 14.0);
        const git_res = ml.drawGitBranchPill("##git_branch", "main*", true, false);
        git_pill_rect = git_res.rect;

        _ = ml.drawRightIconAction("##split_down", .split_down, "Split Down");
        _ = ml.drawRightIconAction("##split_right", .split_right, "Split Right");
        const sc_res = ml.drawRightStatusPill("##sc_status", Color.rgb(115, 201, 145), "Supercomplete", Color.rgb(115, 201, 145), false);
        sc_pill_rect = sc_res.rect;

        try std.testing.expect(ml.cur_x > start_left + 120.0);
        try std.testing.expect(ml.right_x < start_right - 60.0);
        try std.testing.expect(sc_pill_rect.right > sc_pill_rect.left);
    }
    uic.endPass();

    uic.clip_damage = win_rect;
    uic.beginPass(.paint, arena.allocator(), surface.canvas(), win_rect, 10, 10, false, false, false);
    {
        var ml = uic.beginModeLine("##test_ml_wide", wide_bar, .{
            .is_active_pane = true,
            .can_drag_vertical = true,
        });
        ml.drawWindowNumberBadge(1, true);
        ml.drawTitle("editor_pane.zig", true, true);
        ml.drawBadgePill("[DIFF]", Color.rgb(121, 192, 255), Color.argb(45, 56, 139, 253), null);
        ml.drawText("42% L120:8", &uic.font_mono, Color.rgb(203, 213, 225), 14.0);
        _ = ml.drawGitBranchPill("##git_branch", "main*", true, false);
        _ = ml.drawRightIconAction("##split_down", .split_down, "Split Down");
        _ = ml.drawRightIconAction("##split_right", .split_right, "Split Right");
        _ = ml.drawRightStatusPill("##sc_status", Color.rgb(115, 201, 145), "Supercomplete", Color.rgb(115, 201, 145), false);
    }
    uic.endPass();
    try std.testing.expectEqual(uic.last_input_rect_count, uic.last_paint_rect_count);

    // 2. Click on the Git branch pill (press + release) triggers `.clicked = true`
    const gx = (git_pill_rect.left + git_pill_rect.right) * 0.5;
    const gy = (git_pill_rect.top + git_pill_rect.bottom) * 0.5;
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, gx, gy, true, true, false);
    {
        var ml = uic.beginModeLine("##test_ml_wide", wide_bar, .{ .is_active_pane = true });
        ml.drawWindowNumberBadge(1, true);
        ml.drawTitle("editor_pane.zig", true, true);
        ml.drawBadgePill("[DIFF]", Color.rgb(121, 192, 255), Color.argb(45, 56, 139, 253), null);
        ml.drawText("42% L120:8", &uic.font_mono, Color.rgb(203, 213, 225), 14.0);
        _ = ml.drawGitBranchPill("##git_branch", "main*", true, false);
    }
    uic.endPass();

    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, gx, gy, false, false, true);
    var git_clicked = false;
    {
        var ml = uic.beginModeLine("##test_ml_wide", wide_bar, .{ .is_active_pane = true });
        ml.drawWindowNumberBadge(1, true);
        ml.drawTitle("editor_pane.zig", true, true);
        ml.drawBadgePill("[DIFF]", Color.rgb(121, 192, 255), Color.argb(45, 56, 139, 253), null);
        ml.drawText("42% L120:8", &uic.font_mono, Color.rgb(203, 213, 225), 14.0);
        const git_res = ml.drawGitBranchPill("##git_branch", "main*", true, false);
        git_clicked = git_res.clicked;
    }
    uic.endPass();
    try std.testing.expect(git_clicked);

    // 3. Narrow pane: `drawRightStatusPill` automatically elides when `right_x - w < cur_x + 8.0`
    const narrow_bar = Rect.xywh(0, 40, 180, 24);
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 10, 10, false, false, false);
    {
        var ml = uic.beginModeLine("##test_ml_narrow", narrow_bar, .{ .is_active_pane = false });
        ml.drawWindowNumberBadge(2, false);
        ml.drawTitle("long_filename_test.zig", false, false);
        _ = ml.drawRightIconAction("##split_right_narrow", .split_right, "Split Right");
        const r_before = ml.right_x;
        const elided = ml.drawRightStatusPill("##elided_pill", Color.rgb(115, 201, 145), "Supercomplete Status", Color.rgb(115, 201, 145), false);
        try std.testing.expect(!elided.clicked);
        try std.testing.expectEqual(@as(f32, 0.0), elided.rect.right - elided.rect.left);
        try std.testing.expectApproxEqAbs(r_before, ml.right_x, 0.001);
    }
    uic.endPass();
}
