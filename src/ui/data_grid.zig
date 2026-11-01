//! Virtualized, sortable, resizable multi-column DataGrid widget (`DataGridColumn`, `DataGridState`, `DataGridResult`, `renderDataGrid`).

const std = @import("std");
const skia = @import("skia");
const platform = @import("platform");
const root = @import("root.zig");
const c = skia.c;
const Color = skia.Color;
const Rect = skia.Rect;
const Font = skia.Font;
const Context = root.Context;
const Padding = root.Padding;
const Size = root.Size;
const ScrollState = root.ScrollState;

pub const DataGridColumn = struct {
    title: []const u8,
    width: f32 = 120.0,
    min_width: f32 = 48.0,
    sortable: bool = true,
    align_right: bool = false,
};

pub fn DataGridState(comptime max_cols: usize) type {
    return struct {
        col_widths: [max_cols]f32 = @splat(0.0),
        widths_initialized: bool = false,
        sort_col: ?u8 = null,
        sort_ascending: bool = true,
        selected_row: ?usize = null,
        drag_col: ?u8 = null,
        drag_start_x: f32 = 0.0,
        drag_start_w: f32 = 0.0,
    };
}

pub const DataGridResult = struct {
    clicked_row: ?usize = null,
    double_clicked_row: ?usize = null,
    sort_changed: bool = false,
};

/// Truncates `text` on a valid UTF-8 codepoint boundary with an ellipsis (`…`) using `uic.arena`
/// when its width exceeds `max_width`.
fn truncateCellText(uic: *Context, font: Font, text: []const u8, max_width: f32) struct { str: []const u8, width: f32 } {
    if (text.len == 0 or max_width <= 4.0) return .{ .str = "", .width = 0.0 };
    const full_w = uic.measureTextCached(font, text);
    if (full_w <= max_width) {
        return .{ .str = text, .width = full_w };
    }

    const ellipsis = "…";
    const ellipsis_w = uic.measureTextCached(font, ellipsis);
    if (max_width <= ellipsis_w + 2.0) {
        return .{ .str = ellipsis, .width = ellipsis_w };
    }

    const target_w = max_width - ellipsis_w;
    var best_end: usize = 0;
    var idx: usize = 0;
    while (idx < text.len) {
        const cp_len = std.unicode.utf8ByteSequenceLength(text[idx]) catch 1;
        const next_idx = @min(text.len, idx + cp_len);
        const prefix_w = uic.measureTextCached(font, text[0..next_idx]);
        if (prefix_w > target_w) break;
        best_end = next_idx;
        idx = next_idx;
    }

    if (best_end == 0) {
        return .{ .str = ellipsis, .width = ellipsis_w };
    }
    const truncated = uic.fmt("{s}…", .{text[0..best_end]});
    const tw = uic.measureTextCached(font, truncated);
    return .{ .str = truncated, .width = tw };
}

/// Renders a virtualized, sortable, column-resizable multi-column DataGrid.
/// Consumes strictly identical layout rects across `Pass.input` and `Pass.paint`.
pub fn renderDataGrid(
    uic: *Context,
    comptime max_cols: usize,
    id_str: []const u8,
    grid_state: *DataGridState(max_cols),
    columns: []const DataGridColumn,
    row_count: usize,
    row_height: f32,
    ctx: anytype,
    comptime cellTextFn: anytype,
) DataGridResult {
    var result = DataGridResult{};
    const grid_wid = uic.resolveIdAndLabel(id_str).wid;

    var scope = uic.scopedState(id_str);
    defer scope.end();

    const col_count = @min(columns.len, max_cols);
    if (!grid_state.widths_initialized) {
        for (0..col_count) |c_idx| {
            grid_state.col_widths[c_idx] = @max(columns[c_idx].min_width, columns[c_idx].width);
        }
        grid_state.widths_initialized = true;
    } else {
        for (0..col_count) |c_idx| {
            const min_w = @max(16.0, columns[c_idx].min_width);
            if (grid_state.col_widths[c_idx] < min_w) {
                grid_state.col_widths[c_idx] = @max(min_w, columns[c_idx].width);
            }
        }
    }

    if (row_count == 0) {
        grid_state.selected_row = null;
    } else if (grid_state.selected_row) |sel| {
        if (sel >= row_count) {
            grid_state.selected_row = row_count - 1;
        }
    }

    const eff_row_h = @max(16.0, row_height);
    const header_h: f32 = 28.0;

    var outer = uic.box(.{
        .direction = .column,
        .w = .fill,
        .h = .fill,
        .padding = Padding.all(0),
        .gap = 0,
        .bg_color = uic.theme.bg_panel,
        .border_color = uic.theme.border_subtle,
        .border_width = 1.0,
    });
    defer outer.end();
    const outer_rect = outer.rect;

    const scroll_state: *ScrollState = if (uic.platform_ctx != null)
        uic.useState(ScrollState, "##grid_scroll", .{})
    else
        &uic.fallback_scroll_state;

    // ------------------------------------------------------------------------
    // 1. Fixed Top Header Bar (28px high)
    // ------------------------------------------------------------------------
    const header_r = uic.nextRect(0, header_h);

    // 1a. Column-border 6px resize drag handles
    {
        var col_x: f32 = header_r.left - scroll_state.scroll_x;
        for (0..col_count) |c_idx| {
            const col_w = grid_state.col_widths[c_idx];
            const border_x = col_x + col_w;
            const handle_r = Rect.xywh(border_x - 3.0, header_r.top, 6.0, header_h);
            const handle_wid = grid_wid ^ (@as(u64, c_idx + 1) *% 0x636F_6C72_6573_697A);

            if (uic.pass == .input) {
                if (grid_state.drag_col == null) {
                    if (uic.isHovered(header_r) and uic.isHovered(handle_r)) {
                        uic.hot_id = handle_wid;
                        uic.setCursor(.resize_ew);
                        if (uic.mouse_pressed) {
                            uic.active_id = handle_wid;
                            uic.focused_id = grid_wid;
                            grid_state.drag_col = @intCast(c_idx);
                            grid_state.drag_start_x = uic.mouse_x;
                            grid_state.drag_start_w = col_w;
                            uic.markDirty(outer_rect);
                            uic.invalidateWindow();
                        }
                    }
                }

                if (grid_state.drag_col != null and grid_state.drag_col.? == @as(u8, @intCast(c_idx))) {
                    if (uic.mouse_down) {
                        uic.active_id = handle_wid;
                        uic.hot_id = handle_wid;
                        uic.setCursor(.resize_ew);
                        const min_w = @max(16.0, columns[c_idx].min_width);
                        const next_w = @max(min_w, grid_state.drag_start_w + (uic.mouse_x - grid_state.drag_start_x));
                        if (@abs(next_w - grid_state.col_widths[c_idx]) > 0.01) {
                            grid_state.col_widths[c_idx] = next_w;
                            uic.markDirty(outer_rect);
                            uic.invalidateWindow();
                        }
                    }
                    if (uic.mouse_released or !uic.mouse_down) {
                        grid_state.drag_col = null;
                        uic.markDirty(header_r);
                        uic.invalidateWindow();
                    }
                }
            }
            col_x += col_w;
        }
    }

    // 1b. Click-to-sort on sortable column headers (when not dragging a column resize handle)
    if (grid_state.drag_col == null) {
        var col_x: f32 = header_r.left - scroll_state.scroll_x;
        for (0..col_count) |c_idx| {
            const col = columns[c_idx];
            const col_w = grid_state.col_widths[c_idx];
            const left_inset: f32 = if (c_idx > 0) 3.0 else 0.0;
            const right_inset: f32 = 3.0;
            const hit_r = Rect.xywh(
                col_x + left_inset,
                header_r.top,
                @max(1.0, col_w - left_inset - right_inset),
                header_h,
            );
            const handle_r = Rect.xywh(col_x + col_w - 3.0, header_r.top, 6.0, header_h);
            const over_handle = uic.isHovered(handle_r);
            const hdr_wid = grid_wid ^ (@as(u64, c_idx + 1) *% 0x4844_525F_534F_5254);

            if (col.sortable and !over_handle) {
                const clicked = uic.trackInteraction(hdr_wid, hit_r, header_r);
                if (uic.pass == .input and clicked) {
                    uic.focused_id = grid_wid;
                    const col_u8: u8 = @intCast(c_idx);
                    if (grid_state.sort_col != null and grid_state.sort_col.? == col_u8) {
                        grid_state.sort_ascending = !grid_state.sort_ascending;
                    } else {
                        grid_state.sort_col = col_u8;
                        grid_state.sort_ascending = true;
                    }
                    result.sort_changed = true;
                    uic.markDirty(outer_rect);
                    uic.invalidateWindow();
                }
            }
            col_x += col_w;
        }
    }

    // 1c. Paint Header Bar
    if (uic.shouldPaint(header_r)) {
        const save_hdr = uic.canvas.save();
        defer uic.canvas.restoreToCount(save_hdr);
        uic.canvas.clipRect(header_r, .intersect, false);

        uic.paint.setStyle(.fill);
        uic.paint.setColor(Color.rgb(18, 24, 36));
        uic.canvas.drawRect(header_r, uic.paint);

        var col_x: f32 = header_r.left - scroll_state.scroll_x;
        for (0..col_count) |c_idx| {
            const col = columns[c_idx];
            const col_w = grid_state.col_widths[c_idx];
            const cell_r = Rect.xywh(col_x, header_r.top, col_w, header_h);
            const hdr_wid = grid_wid ^ (@as(u64, c_idx + 1) *% 0x4844_525F_534F_5254);
            const handle_wid = grid_wid ^ (@as(u64, c_idx + 1) *% 0x636F_6C72_6573_697A);

            const hdr_hovered = (uic.hot_id == hdr_wid);
            const is_sorted = (grid_state.sort_col != null and grid_state.sort_col.? == @as(u8, @intCast(c_idx)));
            if (hdr_hovered or is_sorted) {
                uic.paint.setStyle(.fill);
                uic.paint.setColor(if (hdr_hovered)
                    Color.rgb(26, 34, 50)
                else
                    Color.rgb(22, 29, 43));
                uic.canvas.drawRect(cell_r, uic.paint);
            }

            const pad_x: f32 = 8.0;
            const sort_reserve: f32 = if (is_sorted) 16.0 else 0.0;
            const max_title_w = @max(0.0, col_w - pad_x * 2.0 - sort_reserve);
            const trunc = truncateCellText(uic, uic.font_body, col.title, max_title_w);

            const save_cell = uic.canvas.save();
            uic.canvas.clipRect(Rect.ltrb(cell_r.left + 2.0, cell_r.top, cell_r.right - 2.0, cell_r.bottom), .intersect, false);

            uic.paint.setStyle(.fill);
            uic.paint.setColor(if (is_sorted or hdr_hovered) uic.theme.text_primary else uic.theme.text_muted);
            const text_y = header_r.top + 18.5;
            const text_x = if (col.align_right)
                @max(cell_r.left + pad_x, cell_r.right - pad_x - sort_reserve - trunc.width)
            else
                cell_r.left + pad_x;
            if (trunc.str.len > 0) {
                uic.drawTextCached(uic.font_body, trunc.str, text_x, text_y);
            }

            if (is_sorted) {
                const arrow = if (grid_state.sort_ascending) "▲" else "▼";
                uic.paint.setColor(uic.theme.accent_hover);
                uic.drawTextCached(uic.font_mono, arrow, cell_r.right - pad_x - 10.0, text_y - 0.5);
            }
            uic.canvas.restoreToCount(save_cell);

            // Column divider & resize handle highlight
            const handle_active = (grid_state.drag_col != null and grid_state.drag_col.? == @as(u8, @intCast(c_idx))) or
                (uic.hot_id == handle_wid);
            const div_w: f32 = if (handle_active) 2.0 else 1.0;
            uic.paint.setStyle(.fill);
            uic.paint.setColor(if (handle_active) uic.theme.accent else uic.theme.border_subtle);
            uic.canvas.drawRect(Rect.xywh(cell_r.right - div_w * 0.5, header_r.top + 3.0, div_w, header_h - 6.0), uic.paint);

            col_x += col_w;
        }

        // Bottom border of header bar
        uic.paint.setStyle(.fill);
        uic.paint.setColor(uic.theme.border_subtle);
        uic.canvas.drawRect(Rect.xywh(header_r.left, header_r.bottom - 1.0, header_r.right - header_r.left, 1.0), uic.paint);
    }

    // ------------------------------------------------------------------------
    // 2. Keyboard Up/Down Row Navigation (processed prior to beginScrollBox)
    // ------------------------------------------------------------------------
    const body_w = uic.availableWidth();
    const body_h = uic.availableHeight();

    if (uic.pass == .input and uic.focused_id == grid_wid and row_count > 0) {
        var nav_changed = false;
        for (uic.key_events) |kev| {
            switch (kev.key) {
                .up => {
                    const cur = grid_state.selected_row orelse 0;
                    const next_row = if (cur > 0) cur - 1 else 0;
                    if (grid_state.selected_row != next_row) {
                        grid_state.selected_row = next_row;
                        result.clicked_row = next_row;
                        nav_changed = true;
                    }
                },
                .down => {
                    const cur = grid_state.selected_row orelse 0;
                    const next_row = if (grid_state.selected_row == null) 0 else @min(row_count - 1, cur + 1);
                    if (grid_state.selected_row != next_row) {
                        grid_state.selected_row = next_row;
                        result.clicked_row = next_row;
                        nav_changed = true;
                    }
                },
                else => {},
            }
        }
        if (nav_changed) {
            if (grid_state.selected_row) |sel| {
                const sel_top = @as(f32, @floatFromInt(sel)) * eff_row_h;
                const sel_bot = sel_top + eff_row_h;
                const vp_h = @max(eff_row_h, body_h);
                if (sel_top < scroll_state.scroll_y) {
                    scroll_state.scroll_y = sel_top;
                } else if (sel_bot > scroll_state.scroll_y + vp_h) {
                    scroll_state.scroll_y = @max(0.0, sel_bot - vp_h);
                }
            }
            uic.markDirty(outer_rect);
            uic.invalidateWindow();
        }
    }

    // ------------------------------------------------------------------------
    // 3. Virtualized Scrollable Body
    // ------------------------------------------------------------------------
    var total_cols_w: f32 = 0.0;
    for (0..col_count) |c_idx| {
        total_cols_w += grid_state.col_widths[c_idx];
    }

    const body_rect = uic.beginScrollBoxWithState("##grid_scroll", scroll_state, body_w, body_h, .{
        .direction = .column,
        .padding = Padding.all(0),
        .gap = 0,
        .bg_color = uic.theme.bg_canvas,
    });
    defer uic.endScrollBox();

    const raw_vr = uic.computeVirtualRange(row_count, eff_row_h, 2);
    const first = uic.latch(usize, raw_vr.first);
    const end = uic.latch(usize, raw_vr.end);
    const top_spacer_h = uic.latch(f32, raw_vr.top_spacer_h);
    const bottom_spacer_h = uic.latch(f32, raw_vr.bottom_spacer_h);

    const row_draw_w = @max(body_rect.right - body_rect.left, total_cols_w);

    if (top_spacer_h > 0.0) {
        uic.spacer(top_spacer_h);
    }

    for (first..end) |row_idx| {
        const row_r = uic.nextRect(row_draw_w, eff_row_h);
        const row_wid = grid_wid ^ (@as(u64, row_idx + 1) *% 0x9E37_79B9_7F4A_7C15);
        const clicked = uic.trackInteraction(row_wid, row_r, row_r);

        if (uic.pass == .input) {
            const row_hovered = uic.isHovered(row_r);
            if ((row_hovered and uic.mouse_pressed) or clicked) {
                uic.focused_id = grid_wid;
                if (grid_state.selected_row != row_idx) {
                    grid_state.selected_row = row_idx;
                    uic.markDirty(body_rect);
                }
                result.clicked_row = row_idx;
                if (uic.mouse_click_count >= 2) {
                    result.double_clicked_row = row_idx;
                }
                uic.invalidateWindow();
            }
        }

        if (uic.shouldPaint(row_r)) {
            const is_selected = (grid_state.selected_row != null and grid_state.selected_row.? == row_idx);
            const is_hovered = (uic.hot_id == row_wid);
            const is_odd = (row_idx % 2 == 1);

            if (is_selected or is_hovered or is_odd) {
                uic.paint.setStyle(.fill);
                const bg = if (is_selected)
                    Color.argb(65, 56, 139, 253)
                else if (is_hovered)
                    Color.rgb(24, 32, 46)
                else
                    Color.argb(90, 18, 24, 36);
                uic.paint.setColor(bg);
                uic.canvas.drawRect(row_r, uic.paint);
            }

            if (is_selected) {
                uic.paint.setStyle(.fill);
                uic.paint.setColor(uic.theme.accent);
                uic.canvas.drawRect(Rect.xywh(row_r.left, row_r.top, 2.5, eff_row_h), uic.paint);
            }

            var cell_x: f32 = row_r.left;
            const pad_x: f32 = 8.0;
            const text_y = row_r.top + eff_row_h * 0.68;

            for (0..col_count) |c_idx| {
                const col = columns[c_idx];
                const col_w = grid_state.col_widths[c_idx];
                const cell_r = Rect.xywh(cell_x, row_r.top, col_w, eff_row_h);

                const raw_text = cellTextFn(uic.arena, ctx, row_idx, c_idx);
                const max_text_w = @max(0.0, col_w - pad_x * 2.0);
                const trunc = truncateCellText(uic, uic.font_mono, raw_text, max_text_w);

                if (trunc.str.len > 0) {
                    const save_cell = uic.canvas.save();
                    uic.canvas.clipRect(Rect.ltrb(cell_r.left + 2.0, cell_r.top, cell_r.right - 2.0, cell_r.bottom), .intersect, false);

                    uic.paint.setStyle(.fill);
                    uic.paint.setColor(if (is_selected) uic.theme.text_primary else Color.rgb(210, 218, 228));
                    const tx = if (col.align_right)
                        @max(cell_r.left + pad_x, cell_r.right - pad_x - trunc.width)
                    else
                        cell_r.left + pad_x;
                    uic.drawTextCached(uic.font_mono, trunc.str, tx, text_y);
                    uic.canvas.restoreToCount(save_cell);
                }

                // Subtle vertical cell divider
                uic.paint.setStyle(.fill);
                uic.paint.setColor(Color.argb(75, 48, 58, 74));
                uic.canvas.drawRect(Rect.xywh(cell_r.right - 0.5, row_r.top, 1.0, eff_row_h), uic.paint);

                cell_x += col_w;
            }
        }
    }

    if (bottom_spacer_h > 0.0) {
        uic.spacer(bottom_spacer_h);
    }

    return result;
}

// ============================================================================
// Unit Tests
// ============================================================================

test "Size.fillMinus and Direction.row_wrap (flowWrap) 2-phase layout determinism" {
    const surface = try skia.Surface.initRasterN32Premul(320, 240);
    defer surface.deinit();
    const paint = try skia.Paint.init();
    defer paint.deinit();
    const font = try Font.init(null, 13.0);
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

    const SceneOut = struct {
        fill_minus_w: f32 = 0,
        trailing_left: f32 = 0,
        chip_rects: [5]c.sk_rect_t = undefined,
        after_wrap_y: f32 = 0,
    };

    const buildScene = struct {
        fn build(ctx: *Context, out: *SceneOut) void {
            // 1. Row with Size.fillMinus(68.0) + trailing 60px button (gap = 8)
            {
                var r = ctx.row(.{
                    .w = .pixels(300),
                    .h = .pixels(32),
                    .gap = 8.0,
                });
                defer r.end();

                var lead = ctx.box(.{
                    .w = Size.fillMinus(68.0),
                    .h = .pixels(32),
                });
                out.fill_minus_w = lead.rect.right - lead.rect.left;
                lead.end();

                var trail = ctx.box(.{
                    .w = .pixels(60.0),
                    .h = .pixels(32),
                });
                out.trailing_left = trail.rect.left;
                trail.end();
            }

            // 2. flowWrap container (200px wide, gap = 8px) with 5 items of 60x24px
            //    Line 1 fits 3 items: x=0..60, 68..128, 136..196 (y=40..64)
            //    Line 2 wraps 2 items: x=0..60, 68..128 (y=72..96)
            {
                var wrap = ctx.flowWrap(.{
                    .w = .pixels(200),
                    .gap = 8.0,
                });
                defer wrap.end();

                for (0..5) |i| {
                    out.chip_rects[i] = ctx.nextRect(60.0, 24.0);
                }
            }

            out.after_wrap_y = ctx.nextCursorY();
        }
    }.build;

    var out_in = SceneOut{};
    var out_paint = SceneOut{};

    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 320, 240), 0, 0, false, false, false);
    buildScene(&uic, &out_in);
    uic.endPass();

    uic.clip_damage = Rect.xywh(0, 0, 320, 240);
    uic.beginPass(.paint, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 320, 240), 0, 0, false, false, false);
    buildScene(&uic, &out_paint);
    uic.endPass();

    // Verify Size.fillMinus(68.0) in 300px row -> 232px wide, trailing box at x = 240
    try std.testing.expectApproxEqAbs(@as(f32, 232.0), out_in.fill_minus_w, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 240.0), out_in.trailing_left, 0.01);

    // Verify flowWrap line 1 vs line 2 wrapping
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), out_in.chip_rects[0].left, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 68.0), out_in.chip_rects[1].left, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 136.0), out_in.chip_rects[2].left, 0.01);
    try std.testing.expectApproxEqAbs(out_in.chip_rects[0].top, out_in.chip_rects[2].top, 0.01);

    // Item 3 wrapped to line 2 at x = 0, y = line1_top + 24 + 8
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), out_in.chip_rects[3].left, 0.01);
    try std.testing.expectApproxEqAbs(out_in.chip_rects[0].top + 32.0, out_in.chip_rects[3].top, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 68.0), out_in.chip_rects[4].left, 0.01);
    try std.testing.expectApproxEqAbs(out_in.chip_rects[3].top, out_in.chip_rects[4].top, 0.01);

    // Verify endBox included row_line_max_h in total height
    try std.testing.expectApproxEqAbs(out_in.chip_rects[3].bottom, out_in.after_wrap_y, 0.01);
    try std.testing.expectApproxEqAbs(out_in.after_wrap_y, out_paint.after_wrap_y, 0.01);
    try std.testing.expectEqual(uic.last_input_rect_count, uic.last_paint_rect_count);
}

test "DataGrid: 10,000-row virtualization, header sorting, column resize, row selection, and keyboard navigation" {
    const surface = try skia.Surface.initRasterN32Premul(420, 220);
    defer surface.deinit();
    const paint = try skia.Paint.init();
    defer paint.deinit();
    const font = try Font.init(null, 13.0);
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

    const cols = [_]DataGridColumn{
        .{ .title = "ID", .width = 80.0, .min_width = 48.0, .sortable = true },
        .{ .title = "Symbol Name", .width = 180.0, .min_width = 60.0, .sortable = true },
        .{ .title = "Size (B)", .width = 100.0, .min_width = 50.0, .sortable = true, .align_right = true },
    };

    var grid_state = DataGridState(8){};
    const GridTestCtx = struct {
        cell_calls: usize = 0,
        fn getCell(alloc: std.mem.Allocator, self: *@This(), row_idx: usize, col_idx: usize) []const u8 {
            self.cell_calls += 1;
            return switch (col_idx) {
                0 => std.fmt.allocPrint(alloc, "#{d}", .{row_idx}) catch "",
                1 => std.fmt.allocPrint(alloc, "fn_extremely_long_symbol_identifier_{d}", .{row_idx}) catch "",
                else => std.fmt.allocPrint(alloc, "{d}", .{row_idx * 64}) catch "",
            };
        }
    };
    var gctx = GridTestCtx{};

    // 1. Render 10,000 rows in a 420x220 viewport (row_height = 24px -> < 15 rows materialized)
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 420, 220), 0, 0, false, false, false);
    _ = uic.dataGrid(8, "##perf_grid", &grid_state, &cols, 10_000, 24.0, &gctx, GridTestCtx.getCell);
    uic.endPass();

    uic.clip_damage = Rect.xywh(0, 0, 420, 220);
    uic.beginPass(.paint, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 420, 220), 0, 0, false, false, false);
    _ = uic.dataGrid(8, "##perf_grid", &grid_state, &cols, 10_000, 24.0, &gctx, GridTestCtx.getCell);
    uic.endPass();

    try std.testing.expect(grid_state.widths_initialized);
    try std.testing.expectEqual(@as(f32, 80.0), grid_state.col_widths[0]);
    try std.testing.expectEqual(uic.last_input_rect_count, uic.last_paint_rect_count);
    // 10,000 rows must be virtualized (< 25 total layout rects and < 60 cell formatting calls)
    try std.testing.expect(uic.last_input_rect_count < 25);
    try std.testing.expect(gctx.cell_calls > 0 and gctx.cell_calls < 60);
    try std.testing.expectApproxEqAbs(@as(f32, 240_000.0), uic.fallback_scroll_state.content_height, 1.0);

    // 2. Click column 0 header (x = 40, y = 14) to sort ascending, then click again to toggle descending
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 420, 220), 40, 14, true, true, false);
    _ = uic.dataGrid(8, "##perf_grid", &grid_state, &cols, 10_000, 24.0, &gctx, GridTestCtx.getCell);
    uic.endPass();

    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 420, 220), 40, 14, false, false, true);
    const sort_res1 = uic.dataGrid(8, "##perf_grid", &grid_state, &cols, 10_000, 24.0, &gctx, GridTestCtx.getCell);
    uic.endPass();
    try std.testing.expect(sort_res1.sort_changed);
    try std.testing.expectEqual(@as(?u8, 0), grid_state.sort_col);
    try std.testing.expect(grid_state.sort_ascending);

    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 420, 220), 40, 14, true, true, true);
    const sort_res2 = uic.dataGrid(8, "##perf_grid", &grid_state, &cols, 10_000, 24.0, &gctx, GridTestCtx.getCell);
    uic.endPass();
    try std.testing.expect(sort_res2.sort_changed);
    try std.testing.expectEqual(@as(?u8, 0), grid_state.sort_col);
    try std.testing.expect(!grid_state.sort_ascending);

    // 3. Drag column 0 resize handle at x = 80, y = 14 to x = 130 -> widens col_widths[0] to 130.0
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 420, 220), 80, 14, true, true, false);
    _ = uic.dataGrid(8, "##perf_grid", &grid_state, &cols, 10_000, 24.0, &gctx, GridTestCtx.getCell);
    uic.endPass();
    try std.testing.expectEqual(@as(?u8, 0), grid_state.drag_col);

    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 420, 220), 130, 14, true, false, false);
    _ = uic.dataGrid(8, "##perf_grid", &grid_state, &cols, 10_000, 24.0, &gctx, GridTestCtx.getCell);
    uic.endPass();
    try std.testing.expectApproxEqAbs(@as(f32, 130.0), grid_state.col_widths[0], 0.01);

    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 420, 220), 130, 14, false, false, true);
    _ = uic.dataGrid(8, "##perf_grid", &grid_state, &cols, 10_000, 24.0, &gctx, GridTestCtx.getCell);
    uic.endPass();
    try std.testing.expectEqual(@as(?u8, null), grid_state.drag_col);

    // 4. Click row 1 (y = 28 + 36 = 64) to select it, then press Down arrow to advance to row 2
    _ = arena.reset(.retain_capacity);
    uic.mouse_click_count = 2;
    uic.beginPass(.input, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 420, 220), 50, 64, true, true, true);
    const row_res = uic.dataGrid(8, "##perf_grid", &grid_state, &cols, 10_000, 24.0, &gctx, GridTestCtx.getCell);
    uic.endPass();
    uic.mouse_click_count = 1;
    try std.testing.expectEqual(@as(?usize, 1), grid_state.selected_row);
    try std.testing.expectEqual(@as(?usize, 1), row_res.clicked_row);
    try std.testing.expectEqual(@as(?usize, 1), row_res.double_clicked_row);

    const down_ev = [_]platform.KeyEvent{.{ .key = .down }};
    uic.key_events = &down_ev;
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 420, 220), 0, 0, false, false, false);
    const nav_res = uic.dataGrid(8, "##perf_grid", &grid_state, &cols, 10_000, 24.0, &gctx, GridTestCtx.getCell);
    uic.endPass();
    uic.key_events = &.{};

    uic.clip_damage = Rect.xywh(0, 0, 420, 220);
    uic.beginPass(.paint, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 420, 220), 0, 0, false, false, false);
    _ = uic.dataGrid(8, "##perf_grid", &grid_state, &cols, 10_000, 24.0, &gctx, GridTestCtx.getCell);
    uic.endPass();

    try std.testing.expectEqual(@as(?usize, 2), grid_state.selected_row);
    try std.testing.expectEqual(@as(?usize, 2), nav_res.clicked_row);
    try std.testing.expectEqual(uic.last_input_rect_count, uic.last_paint_rect_count);
}
