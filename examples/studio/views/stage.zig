//! Interactive vector stage viewport rendered directly into the persistent GPU backbuffer
//! using dual hardware scissor clipping (window-level `clip_damage` + stage-local `stage_rect`).
//!
//! Why this avoids a second offscreen `stage_surface`:
//!   - Saves ~18 MB of dedicated GPU texture memory + Copy-on-Write (`SkSurface::MakeImageSnapshot`)
//!     shadow textures during 60 FPS animation.
//!   - Because the window's `backbuffer_surface` already retains all pixels across frames, intersecting
//!     `clip_damage` with `stage_rect` isolates stage repaints to the tight animated ring bounds (~15%
//!     of window) while leaving the titlebar, sidebar, and outer stage untouched.

const skia = @import("skia");
const ui = @import("ui");
const platform = @import("platform");
const AppState = @import("../state.zig").AppState;
const PlatformContext = platform.PlatformContext;

/// Computes the tight bounding box (in window coordinates) of the animated rings inside `stage_rect`.
pub fn computeAnimatedRingBounds(state: *const AppState, stage_rect: skia.c.sk_rect_t, eff_zoom: f32) skia.c.sk_rect_t {
    const cx = (stage_rect.left + stage_rect.right) * 0.5 + state.doc.viewport.pan_x;
    const cy = (stage_rect.top + stage_rect.bottom) * 0.5 + state.doc.viewport.pan_y;
    // Max diagonal of 250x250 rounded rect is ~177px + stroke width
    const radius = 184.0 * eff_zoom * state.doc.viewport.zoom;
    return .{
        .left = @max(stage_rect.left + 2.0, cx - radius),
        .top = @max(stage_rect.top + 2.0, cy - radius),
        .right = @min(stage_rect.right - 2.0, cx + radius),
        .bottom = @min(stage_rect.bottom - 2.0, cy + radius),
    };
}

pub fn build(
    state: *AppState,
    ctx: *PlatformContext,
    animate: bool,
    stage_params_changed: bool,
    titlebar_dirty: bool,
    titlebar_rect: skia.c.sk_rect_t,
) void {
    const uic = &state.ui_ctx;
    const canvas = uic.canvas;

    uic.pushScope("stage");
    defer uic.popScope();

    // Animation phase lives in the Host KV store under ("stage", "anim_phase")
    const anim_phase = uic.useState(f32, "anim_phase", 0.35);
    const smooth_zoom = uic.animateFloat("smooth_zoom", state.doc.zoom, 0.28);

    const stage_scope = uic.beginCanvasStage("vector_stage", &state.doc.viewport, .{
        .show_grid = state.doc.show_grid,
        .apply_world_transform = false,
    });
    defer stage_scope.end();
    const stage_rect = stage_scope.rect;

    var stage_damage_win: ?skia.c.sk_rect_t = null;

    if (uic.pass == .input) {
        if (animate) {
            anim_phase.* += 0.02 * state.doc.rotation_speed;
        }

        if (state.stage_full_dirty or stage_scope.changed) {
            stage_damage_win = stage_rect;
        } else if (animate or stage_params_changed or uic.animating_this_frame) {
            // Only mark the tight animated ring square (~15% of window) dirty!
            stage_damage_win = computeAnimatedRingBounds(state, stage_rect, smooth_zoom);
        }

        if (state.doc.show_cursor_halo) {
            const mouse_moved = (ctx.mouse_x != state.prev_mouse_x) or (ctx.mouse_y != state.prev_mouse_y);
            const curr_in = uic.isHovered(stage_rect);
            const prev_in = state.prev_mouse_x >= stage_rect.left and state.prev_mouse_x <= stage_rect.right and
                state.prev_mouse_y >= stage_rect.top and state.prev_mouse_y <= stage_rect.bottom;
            if (mouse_moved and (curr_in or prev_in)) {
                if (prev_in) {
                    const r_old = skia.Rect.xywh(state.prev_mouse_x - 40, state.prev_mouse_y - 40, 80, 80);
                    stage_damage_win = if (stage_damage_win) |d| skia.Rect.unionRect(d, r_old) else r_old;
                }
                if (curr_in) {
                    const r_new = skia.Rect.xywh(ctx.mouse_x - 40, ctx.mouse_y - 40, 80, 80);
                    stage_damage_win = if (stage_damage_win) |d| skia.Rect.unionRect(d, r_new) else r_new;
                }
            }
        }

        if (stage_damage_win) |dmg_w| {
            uic.markDirty(dmg_w);
        }
        if (titlebar_dirty) {
            uic.markDirty(titlebar_rect);
        }
        state.prev_mouse_x = ctx.mouse_x;
        state.prev_mouse_y = ctx.mouse_y;
    }

    if (uic.shouldPaint(stage_rect)) {
        paintStageDirect(state, ctx, canvas, stage_rect, anim_phase.*, smooth_zoom);
    }
}

/// Renders the vector stage directly into `window_canvas` within the intersection of
/// `uic.clip_damage` and `stage_rect` (zero intermediate offscreen texture or CoW copy).
fn paintStageDirect(
    state: *AppState,
    ctx: *PlatformContext,
    window_canvas: skia.Canvas,
    stage_rect: skia.c.sk_rect_t,
    anim_phase: f32,
    smooth_zoom: f32,
) void {
    const stage_w = stage_rect.right - stage_rect.left;
    const stage_h = stage_rect.bottom - stage_rect.top;
    if (stage_w <= 0 or stage_h <= 0) return;

    const uic = &state.ui_ctx;
    const paint = state.paint;

    _ = window_canvas.save();
    defer window_canvas.restore();

    window_canvas.translate(stage_rect.left, stage_rect.top);

    const cx = stage_w * 0.5 + state.doc.viewport.pan_x;
    const cy = stage_h * 0.5 + state.doc.viewport.pan_y;
    const total_zoom = smooth_zoom * state.doc.viewport.zoom;

    _ = window_canvas.save();
    window_canvas.translate(cx, cy);
    window_canvas.scale(total_zoom, total_zoom);
    window_canvas.rotateDegrees(anim_phase * 28.0);

    if (state.ring_shader) |shader| {
        paint.setShader(shader);
        paint.setStyle(.stroke);
        paint.setStrokeWidth(state.doc.stroke_width);

        const count: usize = @intFromFloat(@round(state.doc.ring_count));
        var i: usize = 0;
        while (i < count) : (i += 1) {
            _ = window_canvas.save();
            const angle_step = 180.0 / @as(f32, @floatFromInt(@max(1, count)));
            window_canvas.rotateDegrees(@as(f32, @floatFromInt(i)) * angle_step + @sin(anim_phase) * state.doc.spread_angle);
            switch (state.doc.style_mode) {
                .orbit => {
                    window_canvas.drawRoundRect(
                        skia.Rect.xywh(-125, -125, 250, 250),
                        state.doc.corner_radius,
                        state.doc.corner_radius,
                        paint,
                    );
                },
                .lattice => {
                    const inset = @as(f32, @floatFromInt(i)) * 12.0;
                    const side = @max(40.0, 250.0 - inset * 2.0);
                    window_canvas.drawRoundRect(
                        skia.Rect.xywh(-side * 0.5, -side * 0.5, side, side),
                        @min(state.doc.corner_radius, side * 0.45),
                        @min(state.doc.corner_radius, side * 0.45),
                        paint,
                    );
                },
                .bloom => {
                    window_canvas.drawRoundRect(
                        skia.Rect.xywh(-135, -70, 270, 140),
                        70.0,
                        70.0,
                        paint,
                    );
                },
            }
            window_canvas.restore();
        }
        paint.setShader(null);
    }
    window_canvas.restore();

    if (state.doc.show_cursor_halo and uic.isHovered(stage_rect)) {
        const mx = ctx.mouse_x - stage_rect.left;
        const my = ctx.mouse_y - stage_rect.top;
        paint.setStyle(.fill);
        paint.setColor(skia.Color.withAlpha(state.doc.accent_color, 45));
        window_canvas.drawCircle(mx, my, 34.0, paint);

        paint.setStyle(.stroke);
        paint.setStrokeWidth(1.5);
        paint.setColor(skia.Color.withAlpha(state.doc.accent_color, 210));
        window_canvas.drawCircle(mx, my, 10.0, paint);
    }

    state.stage_full_dirty = false;
}
