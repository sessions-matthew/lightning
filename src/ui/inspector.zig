//! Property Inspector Controls (`dragFloat`, `segmentedControl`, `colorSwatchPicker`),
//! Declarative Value Animation (`animateFloat`), and Notification Toasts (`ToastQueue`, `renderToasts`).

const std = @import("std");
const skia = @import("skia");
const platform = @import("platform");
const layout = @import("layout.zig");
const root = @import("root.zig");
const c = skia.c;
const Color = skia.Color;
const Rect = skia.Rect;
const Context = root.Context;
const WidgetId = root.WidgetId;

// ============================================================================
// Notification Toasts (`ToastSeverity`, `ToastQueue`, `renderToasts`)
// ============================================================================

pub const ToastSeverity = enum(u8) {
    info,
    success,
    warning,
    err,

    pub fn accentColor(self: ToastSeverity) u32 {
        return switch (self) {
            .info => Color.rgb(56, 189, 248),
            .success => Color.rgb(34, 197, 94),
            .warning => Color.rgb(245, 158, 11),
            .err => Color.rgb(239, 68, 68),
        };
    }

    pub fn badgeText(self: ToastSeverity) []const u8 {
        return switch (self) {
            .info => "INFO",
            .success => "OK",
            .warning => "WARN",
            .err => "ERR",
        };
    }
};

pub const ToastItem = struct {
    id: u32 = 0,
    message: platform.InlineString(128) = .{},
    severity: ToastSeverity = .info,
    ttl_frames: u16 = 0,
    max_ttl: u16 = 180,
};

/// Fixed-capacity, value-oriented notification toast queue.
/// Uses `platform.InlineString(128)` so it is 100% safe across `.dylib` hot-reloads (`dlclose`).
pub fn ToastQueue(comptime capacity: usize) type {
    return struct {
        const Self = @This();

        items: [capacity]ToastItem = @splat(.{}),
        len: usize = 0,
        next_id: u32 = 1,
        dirty_notice: bool = false,

        pub fn push(self: *Self, message: []const u8, severity: ToastSeverity, ttl_frames: u16) void {
            if (capacity == 0) return;
            if (self.len >= capacity) {
                var i: usize = 0;
                while (i + 1 < capacity) : (i += 1) {
                    self.items[i] = self.items[i + 1];
                }
                self.len = capacity - 1;
            }
            const eff_ttl = if (ttl_frames == 0) 180 else ttl_frames;
            self.items[self.len] = .{
                .id = self.next_id,
                .message = platform.InlineString(128).init(message),
                .severity = severity,
                .ttl_frames = eff_ttl,
                .max_ttl = eff_ttl,
            };
            self.next_id +%= 1;
            if (self.next_id == 0) self.next_id = 1;
            self.len += 1;
            self.dirty_notice = true;
        }

        pub fn dismissByIndex(self: *Self, idx: usize) void {
            if (idx >= self.len) return;
            var i: usize = idx;
            while (i + 1 < self.len) : (i += 1) {
                self.items[i] = self.items[i + 1];
            }
            self.items[self.len - 1] = .{};
            self.len -= 1;
            self.dirty_notice = true;
        }

        pub fn clear(self: *Self) void {
            if (self.len > 0) {
                self.dirty_notice = true;
            }
            self.len = 0;
        }

        pub fn activeCount(self: *const Self) usize {
            return self.len;
        }
    };
}

fn toastCardRect(viewport_rect: layout.Rect, slot_idx: usize) layout.Rect {
    const vp_w = viewport_rect.right - viewport_rect.left;
    const card_w = @min(316.0, @max(180.0, vp_w - 32.0));
    const card_h: f32 = 42.0;
    const gap: f32 = 8.0;
    const margin_r: f32 = 16.0;
    const margin_b: f32 = 16.0;

    const x = viewport_rect.right - margin_r - card_w;
    const y = viewport_rect.bottom - margin_b - card_h - @as(f32, @floatFromInt(slot_idx)) * (card_h + gap);
    return Rect.xywh(x, y, card_w, card_h);
}

/// Renders active notification toast cards stacked in the bottom-right corner of `viewport_rect`
/// with a colored severity accent bar, TTL progress strip, and interactive `×` dismiss button.
pub fn renderToasts(
    uic: *Context,
    comptime cap: usize,
    queue: *ToastQueue(cap),
    viewport_rect: layout.Rect,
) void {
    if (queue.len == 0 and !queue.dirty_notice) return;

    const max_stack_h = @as(f32, @floatFromInt(@max(@as(usize, 1), cap))) * 52.0 + 24.0;
    const stack_region = Rect.xywh(
        @max(viewport_rect.left, viewport_rect.right - 344.0),
        @max(viewport_rect.top, viewport_rect.bottom - max_stack_h),
        @min(344.0, viewport_rect.right - viewport_rect.left),
        @min(max_stack_h, viewport_rect.bottom - viewport_rect.top),
    );

    if (uic.pass == .input) {
        if (queue.dirty_notice) {
            queue.dirty_notice = false;
            uic.markDirty(stack_region);
        }

        var idx: usize = 0;
        while (idx < queue.len) {
            const card_r = toastCardRect(viewport_rect, idx);
            const close_r = Rect.xywh(card_r.right - 26.0, card_r.top + 11.0, 20.0, 20.0);
            const close_wid: WidgetId = 0x70A5_7000_0000_0000 ^ (@as(u64, queue.items[idx].id) *% 0x9E37_79B9_7F4A_7C15);

            const close_clicked = uic.trackInteraction(close_wid, close_r, stack_region);
            if (close_clicked) {
                queue.dismissByIndex(idx);
                uic.markDirty(stack_region);
                continue;
            }

            if (queue.items[idx].ttl_frames > 1) {
                queue.items[idx].ttl_frames -= 1;
                uic.animating_this_frame = true;
                uic.markDirty(card_r);
                idx += 1;
            } else {
                queue.dismissByIndex(idx);
                uic.markDirty(stack_region);
            }
        }
        return;
    }

    // Pass.paint
    var idx: usize = 0;
    while (idx < queue.len) : (idx += 1) {
        const item = &queue.items[idx];
        const card_r = toastCardRect(viewport_rect, idx);
        if (!uic.shouldPaint(Rect.outset(card_r, 6.0, 6.0))) continue;

        const save_cnt = uic.canvas.save();
        defer uic.canvas.restoreToCount(save_cnt);

        // Drop shadow
        uic.paint.setStyle(.fill);
        uic.paint.setColor(Color.argb(95, 2, 6, 23));
        uic.canvas.drawRoundRect(Rect.outset(card_r, 3.0, 3.0), 10.0, 10.0, uic.paint);

        // Elevated toast card body & border
        uic.paint.setColor(Color.rgb(22, 29, 43));
        uic.canvas.drawRoundRect(card_r, 8.0, 8.0, uic.paint);

        const accent = item.severity.accentColor();
        uic.paint.setStyle(.stroke);
        uic.paint.setStrokeWidth(1.0);
        uic.paint.setColor(Color.withAlpha(accent, 110));
        uic.canvas.drawRoundRect(card_r, 8.0, 8.0, uic.paint);

        // Left colored severity accent bar
        uic.paint.setStyle(.fill);
        uic.paint.setColor(accent);
        const bar_r = Rect.xywh(card_r.left + 4.0, card_r.top + 6.0, 4.0, (card_r.bottom - card_r.top) - 12.0);
        uic.canvas.drawRoundRect(bar_r, 2.0, 2.0, uic.paint);

        // Bottom TTL progress bar
        if (item.max_ttl > 0) {
            const ratio = std.math.clamp(
                @as(f32, @floatFromInt(item.ttl_frames)) / @as(f32, @floatFromInt(item.max_ttl)),
                0.0,
                1.0,
            );
            const prog_w = ((card_r.right - card_r.left) - 16.0) * ratio;
            if (prog_w > 1.0) {
                uic.paint.setColor(Color.withAlpha(accent, 90));
                uic.canvas.drawRect(Rect.xywh(card_r.left + 8.0, card_r.bottom - 2.5, prog_w, 1.5), uic.paint);
            }
        }

        // Message text clipped to card interior
        const close_r = Rect.xywh(card_r.right - 26.0, card_r.top + 11.0, 20.0, 20.0);
        {
            const text_save = uic.canvas.save();
            defer uic.canvas.restoreToCount(text_save);
            uic.canvas.clipRect(Rect.ltrb(card_r.left + 14.0, card_r.top, close_r.left - 4.0, card_r.bottom), .intersect, false);
            uic.paint.setStyle(.fill);
            uic.paint.setColor(uic.theme.text_primary);
            uic.drawTextCached(uic.font_body, item.message.slice(), card_r.left + 14.0, card_r.top + 25.5);
        }

        // Dismiss `×` button
        const close_wid: WidgetId = 0x70A5_7000_0000_0000 ^ (@as(u64, item.id) *% 0x9E37_79B9_7F4A_7C15);
        const close_hot = (uic.hot_id == close_wid);
        if (close_hot) {
            uic.paint.setStyle(.fill);
            uic.paint.setColor(Color.argb(55, 148, 163, 184));
            uic.canvas.drawRoundRect(close_r, 4.0, 4.0, uic.paint);
        }
        uic.paint.setStyle(.stroke);
        uic.paint.setStrokeWidth(1.5);
        uic.paint.setColor(if (close_hot) uic.theme.text_primary else uic.theme.text_muted);
        const cx = (close_r.left + close_r.right) * 0.5;
        const cy = (close_r.top + close_r.bottom) * 0.5;
        const d: f32 = 3.8;
        uic.canvas.drawLine(cx - d, cy - d, cx + d, cy + d, uic.paint);
        uic.canvas.drawLine(cx + d, cy - d, cx - d, cy + d, uic.paint);
    }
}

// ============================================================================
// Property Inspector Controls (`dragFloat`, `segmentedControl`, `colorSwatchPicker`)
// ============================================================================

/// Scrubbable numeric value box for property inspectors:
/// renders `label` on the left and a rounded drag-value pill on the right with a proportional fill bar
/// and formatted numeric value. Dragging horizontally scrubs `value.*` clamped to `[min_val, max_val]`
/// (with `.resize_ew` cursor and `0.1x` fine step when `Shift` is held).
pub fn dragFloat(
    uic: *Context,
    label: []const u8,
    value: *f32,
    speed: f32,
    min_val: f32,
    max_val: f32,
    decimals: u8,
) bool {
    const resolved = uic.resolveIdAndLabel(label);
    const r = uic.nextRect(0, 28.0);

    const row_w = r.right - r.left;
    const pill_w = @min(108.0, @max(68.0, row_w * 0.44));
    const pill_h: f32 = 22.0;
    const pill_r = Rect.xywh(r.right - pill_w, r.top + (28.0 - pill_h) * 0.5, pill_w, pill_h);

    _ = uic.trackInteraction(resolved.wid, r, r);
    const is_dragging = (uic.active_id == resolved.wid and uic.mouse_down);
    const hovered = (uic.hot_id == resolved.wid or is_dragging);

    var changed = false;
    if (uic.pass == .input) {
        if (hovered) {
            uic.setCursor(.resize_ew);
        }
        if (is_dragging) {
            if (uic.mouse_pressed or uic.drag_float_active_wid != resolved.wid) {
                uic.drag_float_active_wid = resolved.wid;
                uic.drag_float_last_mx = uic.mouse_x;
            } else {
                const dx = uic.mouse_x - uic.drag_float_last_mx;
                uic.drag_float_last_mx = uic.mouse_x;
                const eff_speed = (if (speed > 0.0) speed else 0.1) * (if (uic.mouse_shift) @as(f32, 0.1) else @as(f32, 1.0));
                if (dx != 0.0) {
                    const lo = @min(min_val, max_val);
                    const hi = @max(min_val, max_val);
                    const next_val = std.math.clamp(value.* + dx * eff_speed, lo, hi);
                    if (next_val != value.*) {
                        value.* = next_val;
                        changed = true;
                        uic.invalidateWindow();
                    }
                }
            }
        } else if (uic.drag_float_active_wid == resolved.wid) {
            uic.drag_float_active_wid = 0;
        }
    }

    if (uic.shouldPaint(r)) {
        // Left label
        uic.paint.setStyle(.fill);
        uic.paint.setColor(if (hovered) uic.theme.text_primary else uic.theme.text_muted);
        uic.drawTextCached(uic.font_body, resolved.display, r.left, r.top + 18.5);

        // Right scrub pill background
        uic.paint.setStyle(.fill);
        uic.paint.setColor(if (is_dragging) Color.rgb(20, 29, 46) else uic.theme.control_bg);
        uic.canvas.drawRoundRect(pill_r, 5.5, 5.5, uic.paint);

        // Proportional fill bar inside pill
        const range = max_val - min_val;
        if (range > 0.0) {
            const norm = std.math.clamp((value.* - min_val) / range, 0.0, 1.0);
            const fill_w = (pill_w - 2.0) * norm;
            if (fill_w > 1.0) {
                const save_cnt = uic.canvas.save();
                defer uic.canvas.restoreToCount(save_cnt);
                uic.canvas.clipRect(Rect.xywh(pill_r.left + 1.0, pill_r.top + 1.0, fill_w, pill_h - 2.0), .intersect, false);
                uic.paint.setStyle(.fill);
                uic.paint.setColor(Color.withAlpha(uic.theme.accent, if (is_dragging) 95 else 55));
                uic.canvas.drawRoundRect(Rect.outset(pill_r, -1.0, -1.0), 4.5, 4.5, uic.paint);
            }
        }

        // Pill border
        uic.paint.setStyle(.stroke);
        uic.paint.setStrokeWidth(1.0);
        uic.paint.setColor(if (is_dragging)
            uic.theme.accent
        else if (hovered)
            uic.theme.accent_hover
        else
            uic.theme.border_subtle);
        uic.canvas.drawRoundRect(pill_r, 5.5, 5.5, uic.paint);

        // Formatted value text
        const val_str = switch (decimals) {
            0 => uic.fmt("{d:.0}", .{value.*}),
            1 => uic.fmt("{d:.1}", .{value.*}),
            2 => uic.fmt("{d:.2}", .{value.*}),
            3 => uic.fmt("{d:.3}", .{value.*}),
            else => uic.fmt("{d:.2}", .{value.*}),
        };
        const tw = uic.measureTextCached(uic.font_mono, val_str);
        uic.paint.setStyle(.fill);
        uic.paint.setColor(uic.theme.text_primary);
        uic.drawTextCached(uic.font_mono, val_str, pill_r.left + (pill_w - tw) * 0.5, pill_r.top + 15.0);
    }

    return changed;
}

/// Renders a horizontal segmented pill bar with one segment per label in `labels`.
/// Clicking a segment updates `selected_idx.*`, marks the control dirty, and returns `true`.
pub fn segmentedControlLabels(
    uic: *Context,
    id_str: []const u8,
    labels: []const []const u8,
    selected_idx: *usize,
) bool {
    const resolved = uic.resolveIdAndLabel(id_str);
    const r = uic.nextRect(0, 28.0);
    if (labels.len == 0) return false;

    const total_w = @max(1.0, (r.right - r.left) - 4.0);
    const seg_w = total_w / @as(f32, @floatFromInt(labels.len));
    var changed = false;

    for (labels, 0..) |_, idx| {
        const seg_r = Rect.xywh(r.left + 2.0 + @as(f32, @floatFromInt(idx)) * seg_w, r.top + 2.0, seg_w, 24.0);
        const seg_wid = resolved.wid ^ (@as(u64, idx + 1) *% 0x9E37_79B9_7F4A_7C15);
        if (uic.trackInteraction(seg_wid, seg_r, r)) {
            if (selected_idx.* != idx) {
                selected_idx.* = idx;
                changed = true;
                uic.invalidateWindow();
            }
        }
    }

    if (uic.shouldPaint(r)) {
        // Outer track
        uic.paint.setStyle(.fill);
        uic.paint.setColor(Color.rgb(17, 23, 35));
        uic.canvas.drawRoundRect(r, 6.5, 6.5, uic.paint);

        uic.paint.setStyle(.stroke);
        uic.paint.setStrokeWidth(1.0);
        uic.paint.setColor(uic.theme.border_subtle);
        uic.canvas.drawRoundRect(r, 6.5, 6.5, uic.paint);

        for (labels, 0..) |seg_label, idx| {
            const seg_r = Rect.xywh(r.left + 2.0 + @as(f32, @floatFromInt(idx)) * seg_w, r.top + 2.0, seg_w, 24.0);
            const seg_wid = resolved.wid ^ (@as(u64, idx + 1) *% 0x9E37_79B9_7F4A_7C15);
            const is_sel = (selected_idx.* == idx);
            const is_hot = (uic.hot_id == seg_wid);

            if (is_sel or is_hot) {
                uic.paint.setStyle(.fill);
                uic.paint.setColor(if (is_sel) uic.theme.accent else Color.argb(45, 148, 163, 184));
                uic.canvas.drawRoundRect(seg_r, 5.0, 5.0, uic.paint);
            }

            const tw = uic.measureTextCached(uic.font_body, seg_label);
            uic.paint.setStyle(.fill);
            uic.paint.setColor(if (is_sel or is_hot) uic.theme.text_primary else uic.theme.text_muted);
            uic.drawTextCached(uic.font_body, seg_label, seg_r.left + (seg_w - tw) * 0.5, seg_r.top + 16.5);
        }
    }

    return changed;
}

fn comptimeEnumLabel(comptime raw_name: []const u8) []const u8 {
    if (raw_name.len == 0) return raw_name;
    comptime {
        var buf: [raw_name.len]u8 = undefined;
        for (raw_name, 0..) |ch, i| {
            if (i == 0) {
                buf[i] = std.ascii.toUpper(ch);
            } else if (ch == '_') {
                buf[i] = ' ';
            } else {
                buf[i] = ch;
            }
        }
        const final = buf;
        return &final;
    }
}

/// Renders a horizontal segmented pill bar with one segment per field of `EnumT`.
/// Clicking a segment updates `value.*`, marks the control dirty, and returns `true`.
pub fn segmentedControl(
    uic: *Context,
    comptime EnumT: type,
    id_str: []const u8,
    value: *EnumT,
) bool {
    const enum_info = @typeInfo(EnumT).@"enum";
    var labels: [enum_info.field_names.len][]const u8 = undefined;
    var selected_idx: usize = 0;

    inline for (enum_info.field_names, enum_info.field_values, 0..) |fname, fval, i| {
        const enum_val: EnumT = @enumFromInt(fval);
        if (@hasDecl(EnumT, "label")) {
            labels[i] = enum_val.label();
        } else {
            labels[i] = comptime comptimeEnumLabel(fname);
        }
        if (value.* == enum_val) {
            selected_idx = i;
        }
    }

    if (segmentedControlLabels(uic, id_str, &labels, &selected_idx)) {
        inline for (enum_info.field_values, 0..) |fval, i| {
            if (selected_idx == i) {
                value.* = @enumFromInt(fval);
            }
        }
        return true;
    }
    return false;
}

/// Renders a row of clickable rounded/circular color swatches plus a `#RRGGBB` hex badge
/// for the active color; clicking a preset selects it, marks dirty, and returns `true`.
pub fn colorSwatchPicker(
    uic: *Context,
    id_str: []const u8,
    color: *u32,
    presets: []const u32,
) bool {
    const resolved = uic.resolveIdAndLabel(id_str);
    const r = uic.nextRect(0, 28.0);

    const swatch_size: f32 = 20.0;
    const swatch_gap: f32 = 6.0;
    const cy = (r.top + r.bottom) * 0.5;
    var changed = false;

    for (presets, 0..) |preset_col, idx| {
        const sx = r.left + @as(f32, @floatFromInt(idx)) * (swatch_size + swatch_gap);
        const swatch_r = Rect.xywh(sx, cy - swatch_size * 0.5, swatch_size, swatch_size);
        const swatch_wid = resolved.wid ^ (@as(u64, idx + 1) *% 0x9E37_79B9_7F4A_7C15);

        if (uic.trackInteraction(swatch_wid, swatch_r, r)) {
            if (color.* != preset_col) {
                color.* = preset_col;
                changed = true;
                uic.invalidateWindow();
            }
        }
    }

    if (uic.shouldPaint(r)) {
        for (presets, 0..) |preset_col, idx| {
            const sx = r.left + @as(f32, @floatFromInt(idx)) * (swatch_size + swatch_gap);
            const scx = sx + swatch_size * 0.5;
            const swatch_wid = resolved.wid ^ (@as(u64, idx + 1) *% 0x9E37_79B9_7F4A_7C15);
            const is_active = ((color.* & 0x00FF_FFFF) == (preset_col & 0x00FF_FFFF));
            const is_hot = (uic.hot_id == swatch_wid);

            uic.paint.setStyle(.fill);
            uic.paint.setColor(preset_col | 0xFF00_0000);
            uic.canvas.drawCircle(scx, cy, if (is_hot or is_active) 9.0 else 8.0, uic.paint);

            if (is_active) {
                uic.paint.setStyle(.stroke);
                uic.paint.setStrokeWidth(2.0);
                uic.paint.setColor(Color.white);
                uic.canvas.drawCircle(scx, cy, 10.5, uic.paint);
            } else if (is_hot) {
                uic.paint.setStyle(.stroke);
                uic.paint.setStrokeWidth(1.2);
                uic.paint.setColor(uic.theme.text_muted);
                uic.canvas.drawCircle(scx, cy, 10.0, uic.paint);
            }
        }

        // Right-aligned `#RRGGBB` hex pill badge
        const red: u8 = @intCast((color.* >> 16) & 0xFF);
        const green: u8 = @intCast((color.* >> 8) & 0xFF);
        const blue: u8 = @intCast(color.* & 0xFF);
        const hex_str = uic.fmt("#{X:0>2}{X:0>2}{X:0>2}", .{ red, green, blue });
        const tw = uic.measureTextCached(uic.font_mono, hex_str);
        const badge_w = tw + 16.0;
        const badge_r = Rect.xywh(r.right - badge_w, r.top + 3.0, badge_w, 22.0);

        uic.paint.setStyle(.fill);
        uic.paint.setColor(uic.theme.control_bg);
        uic.canvas.drawRoundRect(badge_r, 5.5, 5.5, uic.paint);

        uic.paint.setStyle(.stroke);
        uic.paint.setStrokeWidth(1.0);
        uic.paint.setColor(uic.theme.border_subtle);
        uic.canvas.drawRoundRect(badge_r, 5.5, 5.5, uic.paint);

        uic.paint.setStyle(.fill);
        uic.paint.setColor(uic.theme.text_muted);
        uic.drawTextCached(uic.font_mono, hex_str, badge_r.left + 8.0, badge_r.top + 15.0);
    }

    return changed;
}

// ============================================================================
// Declarative Value Animation (`animateFloat`)
// ============================================================================

/// Smoothly interpolates a persistent `f32` toward `target` by `lerp_factor` during `Pass.input`.
/// Automatically sets `uic.animating_this_frame = true` while in flight and stops requesting
/// redraws once `cur.* == target` (preserving 0% idle CPU/GPU usage).
pub fn animateFloat(
    uic: *Context,
    id_str: []const u8,
    target: f32,
    lerp_factor: f32,
) f32 {
    const cur: *f32 = if (uic.platform_ctx != null)
        uic.useState(f32, id_str, target)
    else blk: {
        const resolved = uic.resolveIdAndLabel(id_str);
        const slot_idx: usize = @intCast(resolved.wid % uic.fallback_anim_slots.len);
        const slot = &uic.fallback_anim_slots[slot_idx];
        if (slot.wid != resolved.wid) {
            slot.wid = resolved.wid;
            slot.value = target;
        }
        break :blk &slot.value;
    };

    if (uic.pass == .input) {
        if (@abs(cur.* - target) > 0.001) {
            const factor = std.math.clamp(lerp_factor, 0.05, 1.0);
            cur.* += (target - cur.*) * factor;
            if (@abs(cur.* - target) <= 0.001) {
                cur.* = target;
            }
            uic.animating_this_frame = true;
            uic.invalidateWindow();
        } else {
            cur.* = target;
        }
    }

    return cur.*;
}

// ============================================================================
// Unit Tests
// ============================================================================

test "inspector: dragFloat, segmentedControl, colorSwatchPicker across Pass.input and Pass.paint" {
    const surface = try skia.Surface.initRasterN32Premul(320, 240);
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

    const Mode = enum(u8) {
        orbit,
        spiral,
        bloom,
    };
    const presets = [_]u32{
        Color.rgb(99, 102, 241),
        Color.rgb(236, 72, 153),
        Color.rgb(14, 165, 233),
    };

    var speed_val: f32 = 1.0;
    var mode_val: Mode = .orbit;
    var active_col: u32 = presets[0];
    const win_rect = Rect.xywh(0, 0, 320, 240);

    // 1. Scrub dragFloat across 2 frames: press at (240, 14), drag to (260, 14)
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 240.0, 14.0, true, true, false);
    _ = uic.dragFloat("Speed##df_speed", &speed_val, 0.05, 0.0, 4.0, 2);
    _ = uic.segmentedControl(Mode, "##seg_mode", &mode_val);
    _ = uic.colorSwatchPicker("##swatch_col", &active_col, &presets);
    uic.endPass();

    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 260.0, 14.0, true, false, false);
    const dragged = uic.dragFloat("Speed##df_speed", &speed_val, 0.05, 0.0, 4.0, 2);
    _ = uic.segmentedControl(Mode, "##seg_mode", &mode_val);
    _ = uic.colorSwatchPicker("##swatch_col", &active_col, &presets);
    uic.endPass();

    try std.testing.expect(dragged);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), speed_val, 0.01);

    // 2. Click second segment ("Spiral") in segmentedControl at y = 28 + 8 + 14 = 50, x = 160
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 160.0, 50.0, true, true, true);
    _ = uic.dragFloat("Speed##df_speed", &speed_val, 0.05, 0.0, 4.0, 2);
    const seg_clicked = uic.segmentedControl(Mode, "##seg_mode", &mode_val);
    _ = uic.colorSwatchPicker("##swatch_col", &active_col, &presets);
    uic.endPass();

    try std.testing.expect(seg_clicked);
    try std.testing.expectEqual(Mode.spiral, mode_val);

    // 3. Click second swatch in colorSwatchPicker at y = 28 + 28 + 14 = 70, x = 36
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 36.0, 70.0, true, true, true);
    _ = uic.dragFloat("Speed##df_speed", &speed_val, 0.05, 0.0, 4.0, 2);
    _ = uic.segmentedControl(Mode, "##seg_mode", &mode_val);
    const swatch_clicked = uic.colorSwatchPicker("##swatch_col", &active_col, &presets);
    uic.endPass();

    try std.testing.expect(swatch_clicked);
    try std.testing.expectEqual(presets[1], active_col);

    // 4. Replay Paint pass and verify layout rect count matches Input pass
    uic.clip_damage = win_rect;
    uic.beginPass(.paint, arena.allocator(), surface.canvas(), win_rect, 36.0, 70.0, false, false, false);
    _ = uic.dragFloat("Speed##df_speed", &speed_val, 0.05, 0.0, 4.0, 2);
    _ = uic.segmentedControl(Mode, "##seg_mode", &mode_val);
    _ = uic.colorSwatchPicker("##swatch_col", &active_col, &presets);
    uic.endPass();

    try std.testing.expectEqual(uic.last_input_rect_count, uic.last_paint_rect_count);
}

test "inspector: animateFloat converges to target and stops requesting redraws when settled" {
    const surface = try skia.Surface.initRasterN32Premul(240, 120);
    defer surface.deinit();

    var store = platform.StateStore.init(std.testing.allocator);
    defer store.deinit();
    var snap = platform.SnapshotBuffer.init(std.testing.allocator);
    defer snap.deinit();
    var pctx = platform.PlatformContext{ .width = 240.0, .height = 120.0 };
    pctx.bindHostStores(&store, &snap);
    pctx.canvas = surface.canvas().ptr;

    var fonts = root.FontSet.init(&pctx, .{});
    defer fonts.deinit();
    var frame_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer frame_arena.deinit();
    var uic = fonts.initContext(frame_arena.allocator(), &pctx);
    defer uic.deinit();

    const win_rect = Rect.xywh(0, 0, 240, 120);

    // Frame 1: initialize at 0.0 -> already at target, so animating_this_frame must be false!
    uic.beginPass(.input, frame_arena.allocator(), surface.canvas(), win_rect, 0, 0, false, false, false);
    const v0 = uic.animateFloat("zoom_anim", 0.0, 0.5);
    uic.endPass();
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), v0, 0.001);
    try std.testing.expect(!uic.animating_this_frame);

    // Frame 2: change target to 10.0 with lerp_factor = 0.5 -> steps to 5.0 and sets animating_this_frame = true
    uic.beginPass(.input, frame_arena.allocator(), surface.canvas(), win_rect, 0, 0, false, false, false);
    const v1 = uic.animateFloat("zoom_anim", 10.0, 0.5);
    uic.endPass();
    try std.testing.expectApproxEqAbs(@as(f32, 5.0), v1, 0.001);
    try std.testing.expect(uic.animating_this_frame);

    // Step until settled at 10.0
    var frames: usize = 0;
    while (frames < 30) : (frames += 1) {
        uic.beginPass(.input, frame_arena.allocator(), surface.canvas(), win_rect, 0, 0, false, false, false);
        _ = uic.animateFloat("zoom_anim", 10.0, 0.5);
        uic.endPass();
        if (!uic.animating_this_frame) break;
    }
    try std.testing.expect(!uic.animating_this_frame);
}

test "inspector: ToastQueue push, TTL countdown, and renderToasts dismiss button" {
    const surface = try skia.Surface.initRasterN32Premul(480, 320);
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

    var toasts = ToastQueue(4){};
    toasts.push("Saved workspace settings", .success, 3);
    toasts.push("Reset parameters to defaults", .info, 60);
    try std.testing.expectEqual(@as(usize, 2), toasts.activeCount());

    const win_rect = Rect.xywh(0, 0, 480, 320);

    // Frame 1: TTL of first toast decrements from 3 -> 2
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 0, 0, false, false, false);
    uic.renderToasts(4, &toasts, win_rect);
    uic.endPass();

    uic.clip_damage = win_rect;
    uic.beginPass(.paint, arena.allocator(), surface.canvas(), win_rect, 0, 0, false, false, false);
    uic.renderToasts(4, &toasts, win_rect);
    uic.endPass();
    try std.testing.expectEqual(@as(usize, 2), toasts.activeCount());
    try std.testing.expectEqual(@as(u16, 2), toasts.items[0].ttl_frames);
    try std.testing.expectEqual(uic.last_input_rect_count, uic.last_paint_rect_count);

    // Frame 2: TTL of first toast decrements from 2 -> 1
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 0, 0, false, false, false);
    uic.renderToasts(4, &toasts, win_rect);
    uic.endPass();
    try std.testing.expectEqual(@as(usize, 2), toasts.activeCount());

    // Frame 3: first toast expires and is removed automatically
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 0, 0, false, false, false);
    uic.renderToasts(4, &toasts, win_rect);
    uic.endPass();
    try std.testing.expectEqual(@as(usize, 1), toasts.activeCount());
    try std.testing.expectEqualStrings("Reset parameters to defaults", toasts.items[0].message.slice());

    // Frame 4: click dismiss `×` button on remaining toast at slot 0
    const card_0 = toastCardRect(win_rect, 0);
    const close_x = card_0.right - 16.0;
    const close_y = card_0.top + 21.0;
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, close_x, close_y, true, true, true);
    uic.renderToasts(4, &toasts, win_rect);
    uic.endPass();
    try std.testing.expectEqual(@as(usize, 0), toasts.activeCount());
}
