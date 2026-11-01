//! Interactive 2D Pan/Zoom/Grid Canvas Stage (`src/ui/stage.zig`).
//!
//! Provides:
//!   - `Viewport2DState`: Serializable 2D camera state (`pan_x`, `pan_y`, `zoom`, `min_zoom`, `max_zoom`)
//!     with `reset()`, `screenToWorld()`, and `worldToScreen()` coordinate transforms.
//!   - `CanvasStageOptions` & `CanvasStageScope`: Two-phase (`Pass.input` / `Pass.paint`) interactive
//!     2D canvas container supporting cursor-anchored wheel/pinch zoom, drag panning, procedural grid
//!     rendering, and automatic world-space Skia canvas transform.

const std = @import("std");
const skia = @import("skia");
const layout = @import("layout.zig");
const root = @import("root.zig");
const c = skia.c;
const Color = skia.Color;
const Rect = skia.Rect;
const Context = root.Context;

pub const Viewport2DState = struct {
    pan_x: f32 = 0.0,
    pan_y: f32 = 0.0,
    zoom: f32 = 1.0,
    min_zoom: f32 = 0.15,
    max_zoom: f32 = 8.0,
    is_panning: bool = false,
    pan_anchor_mx: f32 = 0.0,
    pan_anchor_my: f32 = 0.0,
    pan_orig_x: f32 = 0.0,
    pan_orig_y: f32 = 0.0,

    pub fn reset(self: *Viewport2DState) void {
        self.pan_x = 0.0;
        self.pan_y = 0.0;
        self.zoom = 1.0;
        self.is_panning = false;
    }

    /// Converts window coordinates `(sx, sy)` inside `stage_rect` (centered origin) to stage world coordinates.
    pub fn screenToWorld(self: Viewport2DState, stage_rect: layout.Rect, sx: f32, sy: f32) struct { x: f32, y: f32 } {
        const cx = (stage_rect.left + stage_rect.right) * 0.5;
        const cy = (stage_rect.top + stage_rect.bottom) * 0.5;
        const safe_zoom = @max(0.0001, self.zoom);
        return .{
            .x = (sx - cx - self.pan_x) / safe_zoom,
            .y = (sy - cy - self.pan_y) / safe_zoom,
        };
    }

    /// Converts stage world coordinates `(wx, wy)` to window coordinates inside `stage_rect`.
    pub fn worldToScreen(self: Viewport2DState, stage_rect: layout.Rect, wx: f32, wy: f32) struct { x: f32, y: f32 } {
        const cx = (stage_rect.left + stage_rect.right) * 0.5;
        const cy = (stage_rect.top + stage_rect.bottom) * 0.5;
        return .{
            .x = cx + self.pan_x + wx * self.zoom,
            .y = cy + self.pan_y + wy * self.zoom,
        };
    }
};

pub const CanvasStageOptions = struct {
    w: layout.Size = .fill,
    h: layout.Size = .fill,
    bg_color: ?u32 = null,
    border_color: ?u32 = null,
    corner_radius: f32 = 12.0,
    show_grid: bool = true,
    grid_step: f32 = 36.0,
    grid_color: ?u32 = null,
    apply_world_transform: bool = true,
    wheel_zooms: bool = true,
    left_drag_pans: bool = true,
};

pub const CanvasStageScope = struct {
    uic: *Context,
    rect: layout.Rect,
    vp: *Viewport2DState,
    opts: CanvasStageOptions,
    changed: bool = false,
    painting: bool = false,
    outer_save_count: c_int = 0,
    world_save_count: ?c_int = null,

    pub fn end(self: CanvasStageScope) void {
        if (self.painting) {
            if (self.world_save_count) |w_save| {
                self.uic.canvas.restoreToCount(w_save);
            }
            self.uic.canvas.restoreToCount(self.outer_save_count);

            const border_col = self.opts.border_color orelse self.uic.theme.border_subtle;
            if (border_col != Color.transparent) {
                self.uic.paint.setStyle(.stroke);
                self.uic.paint.setStrokeWidth(1.0);
                self.uic.paint.setColor(border_col);
                if (self.opts.corner_radius > 0.0) {
                    self.uic.canvas.drawRoundRect(self.rect, self.opts.corner_radius, self.opts.corner_radius, self.uic.paint);
                } else {
                    self.uic.canvas.drawRect(self.rect, self.uic.paint);
                }
            }
        }
        self.uic.endBox();
    }
};

pub fn beginCanvasStage(
    uic: *Context,
    id_str: []const u8,
    vp: *Viewport2DState,
    opts: CanvasStageOptions,
) CanvasStageScope {
    const resolved = uic.resolveIdAndLabel(id_str);
    const w = uic.resolveWidth(opts.w);
    const h = uic.resolveHeight(opts.h);
    const stage_rect = uic.beginBox(w, h, .{
        .direction = .column,
        .padding = layout.Padding.all(0),
        .bg_color = Color.transparent,
    });

    var changed = false;

    if (uic.pass == .input) {
        const hovered = uic.isHovered(stage_rect);
        if (hovered) {
            uic.hot_id = resolved.wid;
        }

        // 1. Scroll-wheel / trackpad zoom anchored around cursor position
        if (hovered) {
            var cmd_or_ctrl = false;
            for (uic.key_events) |kev| {
                if (kev.cmd or kev.ctrl) {
                    cmd_or_ctrl = true;
                    break;
                }
            }
            const should_zoom = (uic.magnify_delta != 0.0) or
                (uic.scroll_dy != 0.0 and (opts.wheel_zooms or cmd_or_ctrl));

            if (should_zoom) {
                const zoom_factor: f32 = if (uic.magnify_delta != 0.0)
                    std.math.clamp(1.0 + uic.magnify_delta, 0.5, 2.0)
                else
                    1.0 + std.math.clamp(uic.scroll_dy * 0.01, -0.35, 0.35);

                const old_zoom = @max(0.0001, vp.zoom);
                const new_zoom = std.math.clamp(old_zoom * zoom_factor, vp.min_zoom, vp.max_zoom);
                if (@abs(new_zoom - old_zoom) > 0.0001) {
                    const world_pt = vp.screenToWorld(stage_rect, uic.mouse_x, uic.mouse_y);
                    const cx = (stage_rect.left + stage_rect.right) * 0.5;
                    const cy = (stage_rect.top + stage_rect.bottom) * 0.5;
                    vp.zoom = new_zoom;
                    vp.pan_x = (uic.mouse_x - cx) - world_pt.x * new_zoom;
                    vp.pan_y = (uic.mouse_y - cy) - world_pt.y * new_zoom;
                    changed = true;
                }
            } else if (!opts.wheel_zooms and (uic.scroll_dx != 0.0 or uic.scroll_dy != 0.0)) {
                vp.pan_x += uic.scroll_dx;
                vp.pan_y += uic.scroll_dy;
                changed = true;
            }
        }

        // 2. Drag-panning (right-click drag, or left-click drag when `opts.left_drag_pans` is true)
        const start_drag = hovered and (uic.right_mouse_pressed or (opts.left_drag_pans and uic.mouse_pressed));
        if (start_drag) {
            vp.is_panning = true;
            vp.pan_anchor_mx = uic.mouse_x;
            vp.pan_anchor_my = uic.mouse_y;
            vp.pan_orig_x = vp.pan_x;
            vp.pan_orig_y = vp.pan_y;
            uic.active_id = resolved.wid;
        }

        if (vp.is_panning) {
            const drag_held = uic.right_mouse_down or (opts.left_drag_pans and uic.mouse_down);
            if (drag_held) {
                const next_px = vp.pan_orig_x + (uic.mouse_x - vp.pan_anchor_mx);
                const next_py = vp.pan_orig_y + (uic.mouse_y - vp.pan_anchor_my);
                if (next_px != vp.pan_x or next_py != vp.pan_y) {
                    vp.pan_x = next_px;
                    vp.pan_y = next_py;
                    changed = true;
                }
                uic.setCursor(.pointing_hand);
            } else {
                vp.is_panning = false;
            }
        }

        if (changed) {
            uic.markDirty(stage_rect);
        }
    }

    var scope = CanvasStageScope{
        .uic = uic,
        .rect = stage_rect,
        .vp = vp,
        .opts = opts,
        .changed = changed,
    };

    if (uic.shouldPaint(stage_rect)) {
        const stage_w = stage_rect.right - stage_rect.left;
        const stage_h = stage_rect.bottom - stage_rect.top;
        if (stage_w > 0.0 and stage_h > 0.0) {
            scope.painting = true;
            scope.outer_save_count = uic.canvas.save();

            uic.canvas.clipRect(stage_rect, .intersect, false);

            // Background fill
            const bg = opts.bg_color orelse uic.theme.bg_panel;
            if (bg != Color.transparent) {
                uic.paint.setStyle(.fill);
                uic.paint.setColor(bg);
                if (opts.corner_radius > 0.0) {
                    uic.canvas.drawRoundRect(stage_rect, opts.corner_radius, opts.corner_radius, uic.paint);
                } else {
                    uic.canvas.drawRect(stage_rect, uic.paint);
                }
            }

            const cx = (stage_rect.left + stage_rect.right) * 0.5 + vp.pan_x;
            const cy = (stage_rect.top + stage_rect.bottom) * 0.5 + vp.pan_y;

            // Optional procedural grid scaled by zoom and offset by pan
            if (opts.show_grid and opts.grid_step > 0.0) {
                var step = opts.grid_step * @max(0.05, vp.zoom);
                while (step < 10.0) {
                    step *= 2.0;
                }
                const grid_col = opts.grid_color orelse Color.argb(28, 148, 163, 184);
                uic.paint.setStyle(.stroke);
                uic.paint.setStrokeWidth(0.0);
                uic.paint.setColor(grid_col);

                var gx = stage_rect.left + @mod(cx - stage_rect.left, step);
                while (gx < stage_rect.right) : (gx += step) {
                    uic.canvas.drawLine(gx, stage_rect.top, gx, stage_rect.bottom, uic.paint);
                }

                var gy = stage_rect.top + @mod(cy - stage_rect.top, step);
                while (gy < stage_rect.bottom) : (gy += step) {
                    uic.canvas.drawLine(stage_rect.left, gy, stage_rect.right, gy, uic.paint);
                }

                // Subtle origin crosshairs
                uic.paint.setColor(Color.argb(52, 148, 163, 184));
                if (cx >= stage_rect.left and cx <= stage_rect.right) {
                    uic.canvas.drawLine(cx, stage_rect.top, cx, stage_rect.bottom, uic.paint);
                }
                if (cy >= stage_rect.top and cy <= stage_rect.bottom) {
                    uic.canvas.drawLine(stage_rect.left, cy, stage_rect.right, cy, uic.paint);
                }
            }

            if (opts.apply_world_transform) {
                scope.world_save_count = uic.canvas.save();
                uic.canvas.translate(cx, cy);
                uic.canvas.scale(vp.zoom, vp.zoom);
            }
        }
    }

    return scope;
}

// ============================================================================
// Unit Tests
// ============================================================================

test "Viewport2DState: screenToWorld, worldToScreen roundtrip, and reset" {
    var vp = Viewport2DState{
        .pan_x = 30.0,
        .pan_y = -20.0,
        .zoom = 2.0,
    };
    const stage_rect = Rect.xywh(100.0, 50.0, 400.0, 300.0);
    // Stage center is (300, 200). With pan (30, -20) and zoom 2.0:
    // World (0, 0) -> Screen (330, 180)
    const screen_origin = vp.worldToScreen(stage_rect, 0.0, 0.0);
    try std.testing.expectApproxEqAbs(@as(f32, 330.0), screen_origin.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 180.0), screen_origin.y, 0.001);

    // Round-trip arbitrary world coordinate (45, -15)
    const s_pt = vp.worldToScreen(stage_rect, 45.0, -15.0);
    const w_pt = vp.screenToWorld(stage_rect, s_pt.x, s_pt.y);
    try std.testing.expectApproxEqAbs(@as(f32, 45.0), w_pt.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, -15.0), w_pt.y, 0.001);

    vp.reset();
    try std.testing.expectEqual(@as(f32, 0.0), vp.pan_x);
    try std.testing.expectEqual(@as(f32, 0.0), vp.pan_y);
    try std.testing.expectEqual(@as(f32, 1.0), vp.zoom);
    try std.testing.expect(!vp.is_panning);
}

test "beginCanvasStage: cursor-anchored zoom, drag-panning, and two-phase layout determinism" {
    const surface = try skia.Surface.initRasterN32Premul(400, 300);
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

    var vp = Viewport2DState{};
    const win_rect = Rect.xywh(0, 0, 400, 300);

    // 1. Scroll-wheel zoom at off-center cursor (260, 190) preserves world point under cursor
    uic.scroll_dy = 20.0;
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 260.0, 190.0, false, false, false);
    const world_before = vp.screenToWorld(win_rect, 260.0, 190.0);
    {
        const stage = uic.beginCanvasStage("main_stage", &vp, .{});
        defer stage.end();
        try std.testing.expect(stage.changed);
    }
    uic.endPass();
    uic.scroll_dy = 0.0;

    try std.testing.expect(vp.zoom > 1.0);
    try std.testing.expect(uic.dirty_rect != null);
    const world_after = vp.screenToWorld(win_rect, 260.0, 190.0);
    try std.testing.expectApproxEqAbs(world_before.x, world_after.x, 0.01);
    try std.testing.expectApproxEqAbs(world_before.y, world_after.y, 0.01);

    // Replay paint pass and verify layout rect count matches
    uic.clip_damage = win_rect;
    uic.beginPass(.paint, arena.allocator(), surface.canvas(), win_rect, 260.0, 190.0, false, false, false);
    {
        const stage = uic.beginCanvasStage("main_stage", &vp, .{});
        defer stage.end();
    }
    uic.endPass();
    try std.testing.expectEqual(uic.last_input_rect_count, uic.last_paint_rect_count);

    // 2. Left-drag panning shifts pan_x and pan_y by exact drag delta
    const orig_pan_x = vp.pan_x;
    const orig_pan_y = vp.pan_y;

    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 150.0, 120.0, true, true, false);
    {
        const stage = uic.beginCanvasStage("main_stage", &vp, .{});
        defer stage.end();
    }
    uic.endPass();
    try std.testing.expect(vp.is_panning);

    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 185.0, 145.0, true, false, false);
    {
        const stage = uic.beginCanvasStage("main_stage", &vp, .{});
        defer stage.end();
        try std.testing.expect(stage.changed);
    }
    uic.endPass();
    try std.testing.expectApproxEqAbs(orig_pan_x + 35.0, vp.pan_x, 0.01);
    try std.testing.expectApproxEqAbs(orig_pan_y + 25.0, vp.pan_y, 0.01);

    // Release mouse ends panning
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 185.0, 145.0, false, false, true);
    {
        const stage = uic.beginCanvasStage("main_stage", &vp, .{});
        defer stage.end();
    }
    uic.endPass();
    try std.testing.expect(!vp.is_panning);
}
