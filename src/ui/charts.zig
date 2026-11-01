//! Skia-Accelerated Data Visualization Widgets (`src/ui/charts.zig`).
//!
//! Provides:
//!   - `SparklineOptions` & `sparkline`: Compact inline polyline + gradient area sparklines with endpoint highlight dot.
//!   - `ChartSeries`, `LineChartOptions`, `LineChartResult`, & `lineChart`: Multi-series line/area chart card with Y-axis grid labels, legend, and interactive hover crosshair + tooltip pill.
//!   - `BarChartItem`, `BarChartOptions`, & `barChart`: Interactive vertical bar chart with rounded bars, value labels, hover states, and click selection.

const std = @import("std");
const skia = @import("skia");
const layout = @import("layout.zig");
const root = @import("root.zig");
const Color = skia.Color;
const Rect = skia.Rect;
const Context = root.Context;

// ============================================================================
// 1. Sparkline
// ============================================================================

pub const SparklineOptions = struct {
    w: layout.Size = .pixels(120),
    h: f32 = 28.0,
    color: ?u32 = null,
    fill_alpha: u8 = 45,
    stroke_width: f32 = 1.75,
    show_endpoint_dot: bool = true,
    label: []const u8 = "",
};

pub fn sparkline(
    uic: *Context,
    id_str: []const u8,
    values: []const f32,
    opts: SparklineOptions,
) void {
    const resolved = uic.resolveIdAndLabel(id_str);
    const w = uic.resolveWidth(opts.w);
    const h = @max(12.0, opts.h);
    const r = uic.nextRect(w, h);

    if (uic.pass == .input) {
        if (uic.isHovered(r)) {
            uic.hot_id = resolved.wid;
        }
    }

    if (!uic.shouldPaint(r)) return;
    if (r.right <= r.left or r.bottom <= r.top) return;

    const save_cnt = uic.canvas.save();
    defer uic.canvas.restoreToCount(save_cnt);
    uic.canvas.clipRect(r, .intersect, false);

    const stroke_col = opts.color orelse uic.theme.accent;

    if (values.len == 0) {
        if (opts.label.len > 0) {
            uic.paint.setStyle(.fill);
            uic.paint.setColor(uic.theme.text_muted);
            uic.drawTextCached(uic.font_mono, opts.label, r.left + 2.0, r.top + h * 0.65);
        }
        return;
    }

    var min_v: f32 = values[0];
    var max_v: f32 = values[0];
    for (values[1..]) |v| {
        if (v < min_v) min_v = v;
        if (v > max_v) max_v = v;
    }
    const raw_span = max_v - min_v;
    const span = if (raw_span > 0.0001) raw_span else 1.0;

    const pad_left: f32 = 2.0;
    const pad_right: f32 = if (opts.show_endpoint_dot) 4.5 else 2.0;
    const pad_top: f32 = if (opts.label.len > 0) 12.0 else 3.5;
    const pad_bottom: f32 = 3.0;

    const plot_left = r.left + pad_left;
    const plot_right = @max(plot_left + 2.0, r.right - pad_right);
    const plot_top = r.top + pad_top;
    const plot_bottom = @max(plot_top + 2.0, r.bottom - pad_bottom);
    const plot_w = plot_right - plot_left;
    const plot_h = plot_bottom - plot_top;

    var last_px: f32 = plot_right;
    var last_py: f32 = plot_top + plot_h * 0.5;

    const line_pb = skia.PathBuilder.init() catch return;
    defer line_pb.deinit();
    const area_pb = skia.PathBuilder.init() catch return;
    defer area_pb.deinit();

    for (values, 0..) |v, i| {
        const t: f32 = if (values.len > 1)
            @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(values.len - 1))
        else
            1.0;
        const norm: f32 = if (raw_span > 0.0001) (v - min_v) / span else 0.5;
        const px = plot_left + t * plot_w;
        const py = plot_bottom - std.math.clamp(norm, 0.0, 1.0) * plot_h;

        if (i == 0) {
            if (values.len == 1) {
                line_pb.moveTo(plot_left, py);
                line_pb.lineTo(px, py);
                area_pb.moveTo(plot_left, r.bottom);
                area_pb.lineTo(plot_left, py);
                area_pb.lineTo(px, py);
            } else {
                line_pb.moveTo(px, py);
                area_pb.moveTo(px, r.bottom);
                area_pb.lineTo(px, py);
            }
        } else {
            line_pb.lineTo(px, py);
            area_pb.lineTo(px, py);
        }
        last_px = px;
        last_py = py;
    }

    area_pb.lineTo(last_px, r.bottom);
    area_pb.close();

    if (opts.fill_alpha > 0) {
        if (area_pb.detach()) |area_path| {
            defer area_path.deinit();
            uic.paint.setStyle(.fill);
            const top_col = Color.withAlpha(stroke_col, opts.fill_alpha);
            const bot_col = Color.withAlpha(stroke_col, 2);
            const grad_colors = [2]u32{ top_col, bot_col };
            if (skia.Shader.initLinearGradient(
                .{ .x = r.left, .y = plot_top },
                .{ .x = r.left, .y = r.bottom },
                &grad_colors,
                null,
                .clamp,
            )) |shader| {
                defer shader.deinit();
                uic.paint.setShader(shader);
                uic.canvas.drawPath(area_path, uic.paint);
                uic.paint.setShader(null);
            } else |_| {
                uic.paint.setColor(top_col);
                uic.canvas.drawPath(area_path, uic.paint);
            }
        } else |_| {}
    }

    if (line_pb.detach()) |line_path| {
        defer line_path.deinit();
        uic.paint.setStyle(.stroke);
        uic.paint.setStrokeWidth(@max(0.5, opts.stroke_width));
        uic.paint.setStrokeJoin(.round);
        uic.paint.setStrokeCap(.round);
        uic.paint.setColor(stroke_col);
        uic.canvas.drawPath(line_path, uic.paint);
        uic.paint.setStrokeJoin(.miter);
        uic.paint.setStrokeCap(.butt);
    } else |_| {}

    if (opts.show_endpoint_dot) {
        uic.paint.setStyle(.fill);
        uic.paint.setColor(Color.withAlpha(stroke_col, 70));
        uic.canvas.drawCircle(last_px, last_py, 4.0, uic.paint);
        uic.paint.setColor(stroke_col);
        uic.canvas.drawCircle(last_px, last_py, 2.25, uic.paint);
    }

    if (opts.label.len > 0) {
        uic.paint.setStyle(.fill);
        uic.paint.setColor(uic.theme.text_muted);
        uic.drawTextCached(uic.font_mono, opts.label, r.left + 2.0, r.top + 10.5);
    }
}

// ============================================================================
// 2. Multi-Series Line / Area Chart
// ============================================================================

pub const ChartSeries = struct {
    name: []const u8,
    values: []const f32,
    color: u32,
    fill_area: bool = true,
};

pub const LineChartOptions = struct {
    w: layout.Size = .fill,
    h: f32 = 180.0,
    title: []const u8 = "",
    y_min: ?f32 = null,
    y_max: ?f32 = null,
    grid_lines: u8 = 4,
    show_legend: bool = true,
    unit_suffix: []const u8 = "",
};

pub const LineChartResult = struct {
    hovered_index: ?usize = null,
    rect: layout.Rect,
};

const LineChartHoverState = struct {
    last_hovered: ?usize = null,
};

fn formatChartNumber(uic: *Context, val: f32, unit_suffix: []const u8) []const u8 {
    const abs_v = @abs(val);
    if (abs_v >= 100.0 or @abs(val - @round(val)) < 0.05) {
        return uic.fmt("{d:.0}{s}", .{ val, unit_suffix });
    }
    return uic.fmt("{d:.1}{s}", .{ val, unit_suffix });
}

pub fn lineChart(
    uic: *Context,
    id_str: []const u8,
    series: []const ChartSeries,
    opts: LineChartOptions,
) LineChartResult {
    const resolved = uic.resolveIdAndLabel(id_str);
    const w = uic.resolveWidth(opts.w);
    const h = @max(64.0, opts.h);
    const r = uic.nextRect(w, h);

    var max_samples: usize = 0;
    for (series) |s| {
        if (s.values.len > max_samples) max_samples = s.values.len;
    }

    const has_header = opts.title.len > 0 or (opts.show_legend and series.len > 0);
    const header_h: f32 = if (has_header) 30.0 else 10.0;
    const left_axis_w: f32 = 46.0;
    const right_pad: f32 = 14.0;
    const bottom_pad: f32 = 14.0;

    const plot_r = Rect.ltrb(
        r.left + left_axis_w,
        r.top + header_h,
        @max(r.left + left_axis_w + 8.0, r.right - right_pad),
        @max(r.top + header_h + 8.0, r.bottom - bottom_pad),
    );

    var hovered_index: ?usize = null;
    if (max_samples > 0 and uic.isHovered(r)) {
        const plot_w = @max(1.0, plot_r.right - plot_r.left);
        const rel_x = std.math.clamp((uic.mouse_x - plot_r.left) / plot_w, 0.0, 1.0);
        if (max_samples == 1) {
            hovered_index = 0;
        } else {
            const idx_f = @round(rel_x * @as(f32, @floatFromInt(max_samples - 1)));
            hovered_index = @min(max_samples - 1, @as(usize, @intFromFloat(@max(0.0, idx_f))));
        }
    }

    if (uic.pass == .input) {
        if (uic.platform_ctx != null) {
            var scope = uic.scopedState(id_str);
            defer scope.end();
            const h_state = uic.useState(LineChartHoverState, "##hover_state", .{});
            if (h_state.last_hovered != hovered_index) {
                h_state.last_hovered = hovered_index;
                uic.markDirty(r);
            }
        } else if (hovered_index != null or uic.hot_id == resolved.wid) {
            uic.markDirty(r);
        }
        if (hovered_index != null) {
            uic.hot_id = resolved.wid;
        }
    }

    if (uic.shouldPaint(r) and r.right > r.left and r.bottom > r.top) {
        const save_cnt = uic.canvas.save();
        defer uic.canvas.restoreToCount(save_cnt);
        uic.canvas.clipRect(r, .intersect, false);

        // 1. Card background & border
        uic.paint.setStyle(.fill);
        uic.paint.setColor(uic.theme.bg_panel);
        uic.canvas.drawRoundRect(r, 8.0, 8.0, uic.paint);

        uic.paint.setStyle(.stroke);
        uic.paint.setStrokeWidth(1.0);
        uic.paint.setColor(uic.theme.border_subtle);
        uic.canvas.drawRoundRect(r, 8.0, 8.0, uic.paint);

        // 2. Title & Top-Right Legend
        if (opts.title.len > 0) {
            uic.paint.setStyle(.fill);
            uic.paint.setColor(uic.theme.text_primary);
            uic.drawTextCached(uic.font_body, opts.title, r.left + 12.0, r.top + 19.0);
        }

        if (opts.show_legend and series.len > 0) {
            var legend_x = r.right - 12.0;
            var s_idx = series.len;
            while (s_idx > 0) {
                s_idx -= 1;
                const s = series[s_idx];
                const name_w = uic.measureTextCached(uic.font_body, s.name);
                const item_w = 12.0 + name_w;
                if (legend_x - item_w < r.left + 100.0 and opts.title.len > 0) break;

                legend_x -= name_w;
                uic.paint.setStyle(.fill);
                uic.paint.setColor(uic.theme.text_muted);
                uic.drawTextCached(uic.font_body, s.name, legend_x, r.top + 19.0);

                legend_x -= 8.0;
                uic.paint.setColor(s.color);
                uic.canvas.drawCircle(legend_x, r.top + 15.0, 3.5, uic.paint);
                legend_x -= 10.0;
            }
        }

        // 3. Compute Y-axis range [min_v, max_v]
        var auto_min: f32 = std.math.inf(f32);
        var auto_max: f32 = -std.math.inf(f32);
        for (series) |s| {
            for (s.values) |v| {
                if (v < auto_min) auto_min = v;
                if (v > auto_max) auto_max = v;
            }
        }
        if (!std.math.isFinite(auto_min)) {
            auto_min = 0.0;
            auto_max = 100.0;
        }
        const min_v = opts.y_min orelse auto_min;
        var max_v = opts.y_max orelse auto_max;
        if (max_v - min_v < 0.0001) {
            max_v = min_v + 1.0;
        }
        const span = max_v - min_v;

        const plot_w = plot_r.right - plot_r.left;
        const plot_h = plot_r.bottom - plot_r.top;

        // 4. Horizontal Grid Lines & Y-Axis Labels
        const grid_count: usize = @max(@as(usize, 1), @as(usize, opts.grid_lines));
        for (0..(grid_count + 1)) |gi| {
            const frac = @as(f32, @floatFromInt(gi)) / @as(f32, @floatFromInt(grid_count));
            const gy = plot_r.top + frac * plot_h;
            const g_val = max_v - frac * span;

            uic.paint.setStyle(.stroke);
            uic.paint.setStrokeWidth(1.0);
            uic.paint.setColor(Color.argb(38, 148, 163, 184));
            uic.canvas.drawLine(plot_r.left, gy, plot_r.right, gy, uic.paint);

            const y_label = formatChartNumber(uic, g_val, opts.unit_suffix);
            const lw = uic.measureTextCached(uic.font_mono, y_label);
            uic.paint.setStyle(.fill);
            uic.paint.setColor(uic.theme.text_muted);
            uic.drawTextCached(uic.font_mono, y_label, @max(r.left + 4.0, plot_r.left - lw - 6.0), gy + 4.0);
        }

        // 5. Series Area Fills & Polylines
        for (series) |s| {
            if (s.values.len == 0) continue;

            const line_pb = skia.PathBuilder.init() catch continue;
            defer line_pb.deinit();
            const area_pb = skia.PathBuilder.init() catch continue;
            defer area_pb.deinit();

            var last_px: f32 = plot_r.left;
            const denom = @max(@as(usize, 1), max_samples - 1);

            for (s.values, 0..) |v, i| {
                const t: f32 = if (max_samples > 1)
                    @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(denom))
                else
                    0.5;
                const norm = std.math.clamp((v - min_v) / span, 0.0, 1.0);
                const px = plot_r.left + t * plot_w;
                const py = plot_r.bottom - norm * plot_h;

                if (i == 0) {
                    line_pb.moveTo(px, py);
                    area_pb.moveTo(px, plot_r.bottom);
                    area_pb.lineTo(px, py);
                } else {
                    line_pb.lineTo(px, py);
                    area_pb.lineTo(px, py);
                }
                last_px = px;
            }

            area_pb.lineTo(last_px, plot_r.bottom);
            area_pb.close();

            if (s.fill_area and s.values.len > 1) {
                if (area_pb.detach()) |area_path| {
                    defer area_path.deinit();
                    uic.paint.setStyle(.fill);
                    const grad_colors = [2]u32{
                        Color.withAlpha(s.color, 56),
                        Color.withAlpha(s.color, 4),
                    };
                    if (skia.Shader.initLinearGradient(
                        .{ .x = plot_r.left, .y = plot_r.top },
                        .{ .x = plot_r.left, .y = plot_r.bottom },
                        &grad_colors,
                        null,
                        .clamp,
                    )) |shader| {
                        defer shader.deinit();
                        uic.paint.setShader(shader);
                        uic.canvas.drawPath(area_path, uic.paint);
                        uic.paint.setShader(null);
                    } else |_| {
                        uic.paint.setColor(grad_colors[0]);
                        uic.canvas.drawPath(area_path, uic.paint);
                    }
                } else |_| {}
            }

            if (line_pb.detach()) |line_path| {
                defer line_path.deinit();
                uic.paint.setStyle(.stroke);
                uic.paint.setStrokeWidth(2.0);
                uic.paint.setStrokeJoin(.round);
                uic.paint.setStrokeCap(.round);
                uic.paint.setColor(s.color);
                uic.canvas.drawPath(line_path, uic.paint);
                uic.paint.setStrokeJoin(.miter);
                uic.paint.setStrokeCap(.butt);
            } else |_| {}
        }

        // 6. Interactive Crosshair & Floating Tooltip Pill
        if (hovered_index) |h_idx| {
            const denom = @max(@as(usize, 1), max_samples - 1);
            const t: f32 = if (max_samples > 1)
                @as(f32, @floatFromInt(h_idx)) / @as(f32, @floatFromInt(denom))
            else
                0.5;
            const cross_x = plot_r.left + t * plot_w;

            uic.paint.setStyle(.stroke);
            uic.paint.setStrokeWidth(1.0);
            uic.paint.setColor(Color.argb(150, 226, 232, 240));
            uic.canvas.drawLine(cross_x, plot_r.top, cross_x, plot_r.bottom, uic.paint);

            var active_series_count: usize = 0;
            var max_row_w: f32 = 64.0;
            for (series) |s| {
                if (h_idx < s.values.len) {
                    const norm = std.math.clamp((s.values[h_idx] - min_v) / span, 0.0, 1.0);
                    const py = plot_r.bottom - norm * plot_h;
                    uic.paint.setStyle(.fill);
                    uic.paint.setColor(Color.withAlpha(s.color, 75));
                    uic.canvas.drawCircle(cross_x, py, 5.5, uic.paint);
                    uic.paint.setColor(s.color);
                    uic.canvas.drawCircle(cross_x, py, 3.25, uic.paint);
                    uic.paint.setColor(Color.white);
                    uic.canvas.drawCircle(cross_x, py, 1.25, uic.paint);

                    const val_str = formatChartNumber(uic, s.values[h_idx], opts.unit_suffix);
                    const row_text = uic.fmt("{s}: {s}", .{ s.name, val_str });
                    const rw = 18.0 + uic.measureTextCached(uic.font_mono, row_text);
                    if (rw > max_row_w) max_row_w = rw;
                    active_series_count += 1;
                }
            }

            if (active_series_count > 0) {
                const pill_w = max_row_w + 14.0;
                const pill_h = 20.0 + @as(f32, @floatFromInt(active_series_count)) * 16.0;
                const prefer_right = cross_x + 10.0 + pill_w <= r.right - 6.0;
                const pill_x = if (prefer_right)
                    cross_x + 10.0
                else
                    @max(r.left + 6.0, cross_x - pill_w - 10.0);
                const pill_y = @max(plot_r.top + 4.0, @min(plot_r.bottom - pill_h - 4.0, plot_r.top + 8.0));
                const pill_r = Rect.xywh(pill_x, pill_y, pill_w, pill_h);

                uic.paint.setStyle(.fill);
                uic.paint.setColor(Color.argb(235, 15, 23, 42));
                uic.canvas.drawRoundRect(pill_r, 6.0, 6.0, uic.paint);

                uic.paint.setStyle(.stroke);
                uic.paint.setStrokeWidth(1.0);
                uic.paint.setColor(uic.theme.border_subtle);
                uic.canvas.drawRoundRect(pill_r, 6.0, 6.0, uic.paint);

                uic.paint.setStyle(.fill);
                uic.paint.setColor(uic.theme.text_muted);
                const idx_hdr = uic.fmt("Sample #{d}", .{h_idx});
                uic.drawTextCached(uic.font_mono, idx_hdr, pill_x + 8.0, pill_y + 14.0);

                var row_y: f32 = pill_y + 30.0;
                for (series) |s| {
                    if (h_idx < s.values.len) {
                        uic.paint.setColor(s.color);
                        uic.canvas.drawCircle(pill_x + 11.0, row_y - 4.0, 3.0, uic.paint);

                        const val_str = formatChartNumber(uic, s.values[h_idx], opts.unit_suffix);
                        const row_text = uic.fmt("{s}: {s}", .{ s.name, val_str });
                        uic.paint.setColor(uic.theme.text_primary);
                        uic.drawTextCached(uic.font_mono, row_text, pill_x + 18.0, row_y);
                        row_y += 16.0;
                    }
                }
            }
        }
    }

    return .{
        .hovered_index = hovered_index,
        .rect = r,
    };
}

// ============================================================================
// 3. Interactive Vertical Bar Chart
// ============================================================================

pub const BarChartItem = struct {
    label: []const u8,
    value: f32,
    color: ?u32 = null,
};

pub const BarChartOptions = struct {
    w: layout.Size = .fill,
    h: f32 = 160.0,
    title: []const u8 = "",
    y_max: ?f32 = null,
    show_values: bool = true,
    unit_suffix: []const u8 = "",
    selected_index: ?usize = null,
    bar_radius: f32 = 4.0,
};

pub fn barChart(
    uic: *Context,
    id_str: []const u8,
    items: []const BarChartItem,
    opts: BarChartOptions,
) ?usize {
    const resolved = uic.resolveIdAndLabel(id_str);
    const w = uic.resolveWidth(opts.w);
    const h = @max(64.0, opts.h);
    const r = uic.nextRect(w, h);

    const header_h: f32 = if (opts.title.len > 0) 28.0 else 10.0;
    const top_val_h: f32 = if (opts.show_values) 16.0 else 4.0;
    const bottom_h: f32 = 24.0;
    const pad_x: f32 = 14.0;

    const plot_r = Rect.ltrb(
        r.left + pad_x,
        r.top + header_h + top_val_h,
        @max(r.left + pad_x + 8.0, r.right - pad_x),
        @max(r.top + header_h + top_val_h + 8.0, r.bottom - bottom_h),
    );

    var clicked_index: ?usize = null;
    if (items.len > 0) {
        const slot_w = (plot_r.right - plot_r.left) / @as(f32, @floatFromInt(items.len));
        for (0..items.len) |i| {
            const slot_left = plot_r.left + @as(f32, @floatFromInt(i)) * slot_w;
            const slot_hit_r = Rect.ltrb(slot_left, r.top + header_h, slot_left + slot_w, r.bottom - 2.0);
            const bar_wid = resolved.wid ^ (@as(u64, i + 1) *% 0x9E37_79B9_7F4A_7C15);
            if (uic.trackInteraction(bar_wid, slot_hit_r, r)) {
                clicked_index = i;
            }
        }
    }

    if (uic.shouldPaint(r) and r.right > r.left and r.bottom > r.top) {
        const save_cnt = uic.canvas.save();
        defer uic.canvas.restoreToCount(save_cnt);
        uic.canvas.clipRect(r, .intersect, false);

        // Card background & border
        uic.paint.setStyle(.fill);
        uic.paint.setColor(uic.theme.bg_panel);
        uic.canvas.drawRoundRect(r, 8.0, 8.0, uic.paint);

        uic.paint.setStyle(.stroke);
        uic.paint.setStrokeWidth(1.0);
        uic.paint.setColor(uic.theme.border_subtle);
        uic.canvas.drawRoundRect(r, 8.0, 8.0, uic.paint);

        if (opts.title.len > 0) {
            uic.paint.setStyle(.fill);
            uic.paint.setColor(uic.theme.text_primary);
            uic.drawTextCached(uic.font_body, opts.title, r.left + 12.0, r.top + 19.0);
        }

        if (items.len > 0) {
            var auto_max: f32 = 0.0;
            for (items) |it| {
                if (it.value > auto_max) auto_max = it.value;
            }
            const max_v = @max(0.0001, opts.y_max orelse (if (auto_max > 0.0) auto_max else 1.0));
            const plot_h = plot_r.bottom - plot_r.top;
            const slot_w = (plot_r.right - plot_r.left) / @as(f32, @floatFromInt(items.len));
            const bar_w = std.math.clamp(slot_w * 0.58, 6.0, 52.0);

            // Subtle horizontal guide lines
            uic.paint.setStyle(.stroke);
            uic.paint.setStrokeWidth(1.0);
            uic.paint.setColor(Color.argb(32, 148, 163, 184));
            uic.canvas.drawLine(plot_r.left, plot_r.top, plot_r.right, plot_r.top, uic.paint);
            uic.canvas.drawLine(plot_r.left, plot_r.top + plot_h * 0.5, plot_r.right, plot_r.top + plot_h * 0.5, uic.paint);
            uic.paint.setColor(Color.argb(70, 148, 163, 184));
            uic.canvas.drawLine(plot_r.left, plot_r.bottom, plot_r.right, plot_r.bottom, uic.paint);

            for (items, 0..) |it, i| {
                const bar_wid = resolved.wid ^ (@as(u64, i + 1) *% 0x9E37_79B9_7F4A_7C15);
                const is_hovered = (uic.hot_id == bar_wid);
                const is_selected = (opts.selected_index != null and opts.selected_index.? == i);

                const slot_left = plot_r.left + @as(f32, @floatFromInt(i)) * slot_w;
                const slot_cx = slot_left + slot_w * 0.5;

                if (is_hovered or is_selected) {
                    uic.paint.setStyle(.fill);
                    uic.paint.setColor(if (is_selected)
                        Color.argb(38, 99, 102, 241)
                    else
                        Color.argb(24, 148, 163, 184));
                    uic.canvas.drawRoundRect(
                        Rect.xywh(slot_left + 2.0, r.top + header_h + 2.0, @max(2.0, slot_w - 4.0), (r.bottom - 4.0) - (r.top + header_h + 2.0)),
                        5.0,
                        5.0,
                        uic.paint,
                    );
                }

                const norm = std.math.clamp(@max(0.0, it.value) / max_v, 0.0, 1.0);
                const bar_h = @max(2.0, norm * plot_h);
                const bar_rect = Rect.xywh(slot_cx - bar_w * 0.5, plot_r.bottom - bar_h, bar_w, bar_h);

                const base_col = it.color orelse uic.theme.accent;
                const draw_col = if (is_hovered or is_selected)
                    Color.argb(
                        255,
                        @min(255, @as(u16, Color.getR(base_col)) + 28),
                        @min(255, @as(u16, Color.getG(base_col)) + 28),
                        @min(255, @as(u16, Color.getB(base_col)) + 28),
                    )
                else
                    base_col;

                uic.paint.setStyle(.fill);
                uic.paint.setColor(draw_col);
                uic.canvas.drawRoundRect(bar_rect, opts.bar_radius, opts.bar_radius, uic.paint);

                if (is_selected) {
                    uic.paint.setStyle(.stroke);
                    uic.paint.setStrokeWidth(1.5);
                    uic.paint.setColor(Color.white);
                    uic.canvas.drawRoundRect(bar_rect, opts.bar_radius, opts.bar_radius, uic.paint);
                }

                // Value label above bar
                if (opts.show_values) {
                    const val_str = formatChartNumber(uic, it.value, opts.unit_suffix);
                    const vw = uic.measureTextCached(uic.font_mono, val_str);
                    uic.paint.setStyle(.fill);
                    uic.paint.setColor(if (is_hovered or is_selected) uic.theme.text_primary else uic.theme.text_muted);
                    uic.drawTextCached(uic.font_mono, val_str, slot_cx - vw * 0.5, bar_rect.top - 4.0);
                }

                // Category label below baseline
                if (it.label.len > 0) {
                    const lw = uic.measureTextCached(uic.font_body, it.label);
                    uic.paint.setStyle(.fill);
                    uic.paint.setColor(if (is_hovered or is_selected) uic.theme.text_primary else uic.theme.text_muted);
                    uic.drawTextCached(uic.font_body, it.label, slot_cx - lw * 0.5, plot_r.bottom + 16.0);
                }
            }
        }
    }

    return clicked_index;
}

// ============================================================================
// Unit Tests
// ============================================================================

test "charts: sparkline, lineChart crosshair hover, and barChart click selection across 2-phase frames" {
    const surface = try skia.Surface.initRasterN32Premul(480, 520);
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

    const win_rect = Rect.xywh(0, 0, 480, 520);
    const spark_vals = [_]f32{ 12.0, 18.0, 15.0, 26.0, 22.0, 34.0 };
    const series = [_]ChartSeries{
        .{ .name = "Frame Time", .values = &[_]f32{ 4.2, 5.1, 3.8, 6.4, 4.9 }, .color = Color.rgb(99, 102, 241), .fill_area = true },
        .{ .name = "GPU Pass", .values = &[_]f32{ 1.8, 2.1, 1.5, 2.9, 2.0 }, .color = Color.rgb(16, 185, 129), .fill_area = false },
    };
    const bars = [_]BarChartItem{
        .{ .label = "Skia", .value = 42.0, .color = Color.rgb(59, 130, 246) },
        .{ .label = "Layout", .value = 18.0, .color = Color.rgb(16, 185, 129) },
        .{ .label = "Syntax", .value = 27.0, .color = Color.rgb(245, 158, 11) },
    };

    // 1. Hover over the middle of the lineChart (around x=252, y=110) and verify hovered_index snaps
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 252.0, 110.0, false, false, false);
    uic.sparkline("##cpu_spark", &spark_vals, .{ .w = .pixels(160), .h = 32.0, .label = "CPU" });
    const lc_in = uic.lineChart("##perf_line", &series, .{ .h = 180.0, .title = "Frame Telemetry", .unit_suffix = "ms" });
    const bc_in = uic.barChart("##subsys_bars", &bars, .{ .h = 160.0, .title = "Subsystem Cost" });
    uic.endPass();

    try std.testing.expectEqual(@as(?usize, 2), lc_in.hovered_index);
    try std.testing.expectEqual(@as(?usize, null), bc_in);
    try std.testing.expect(uic.dirty_rect != null);

    uic.clip_damage = win_rect;
    uic.beginPass(.paint, arena.allocator(), surface.canvas(), win_rect, 252.0, 110.0, false, false, false);
    uic.sparkline("##cpu_spark", &spark_vals, .{ .w = .pixels(160), .h = 32.0, .label = "CPU" });
    const lc_paint = uic.lineChart("##perf_line", &series, .{ .h = 180.0, .title = "Frame Telemetry", .unit_suffix = "ms" });
    _ = uic.barChart("##subsys_bars", &bars, .{ .h = 160.0, .title = "Subsystem Cost" });
    uic.endPass();

    try std.testing.expectEqual(lc_in.hovered_index, lc_paint.hovered_index);
    try std.testing.expectEqual(uic.last_input_rect_count, uic.last_paint_rect_count);

    // 2. Click on the second bar (index 1, around x=240, y=300) in barChart
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 240.0, 300.0, true, true, false);
    uic.sparkline("##cpu_spark", &spark_vals, .{ .w = .pixels(160), .h = 32.0, .label = "CPU" });
    _ = uic.lineChart("##perf_line", &series, .{ .h = 180.0, .title = "Frame Telemetry", .unit_suffix = "ms" });
    _ = uic.barChart("##subsys_bars", &bars, .{ .h = 160.0, .title = "Subsystem Cost" });
    uic.endPass();

    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 240.0, 300.0, false, false, true);
    uic.sparkline("##cpu_spark", &spark_vals, .{ .w = .pixels(160), .h = 32.0, .label = "CPU" });
    _ = uic.lineChart("##perf_line", &series, .{ .h = 180.0, .title = "Frame Telemetry", .unit_suffix = "ms" });
    const clicked_bar = uic.barChart("##subsys_bars", &bars, .{ .h = 160.0, .title = "Subsystem Cost", .selected_index = 1 });
    uic.endPass();

    try std.testing.expectEqual(@as(?usize, 1), clicked_bar);

    uic.clip_damage = win_rect;
    uic.beginPass(.paint, arena.allocator(), surface.canvas(), win_rect, 240.0, 300.0, false, false, false);
    uic.sparkline("##cpu_spark", &spark_vals, .{ .w = .pixels(160), .h = 32.0, .label = "CPU" });
    _ = uic.lineChart("##perf_line", &series, .{ .h = 180.0, .title = "Frame Telemetry", .unit_suffix = "ms" });
    _ = uic.barChart("##subsys_bars", &bars, .{ .h = 160.0, .title = "Subsystem Cost", .selected_index = 1 });
    uic.endPass();

    try std.testing.expectEqual(uic.last_input_rect_count, uic.last_paint_rect_count);
}
