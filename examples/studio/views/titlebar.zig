//! Custom unified macOS dark titlebar view (top 46pt).
//! Reads component-scoped `useState` hooks and Host KV store metrics.

const skia = @import("skia");
const ui = @import("ui");
const platform = @import("platform");
const AppState = @import("../state.zig").AppState;
const PlatformContext = platform.PlatformContext;

pub fn build(
    state: *AppState,
    ctx: *const PlatformContext,
    animate: bool,
    click_count: u32,
) skia.c.sk_rect_t {
    const uic = &state.ui_ctx;
    const canvas = uic.canvas;

    const left_pad: f32 = if (ctx.is_fullscreen) 16.0 else 88.0;
    const titlebar_rect = uic.beginBox(0, 46, .{
        .direction = .row,
        .padding = ui.Padding{ .left = left_pad, .top = 11, .right = 16, .bottom = 11 },
        .gap = 10,
        .bg_color = skia.Color.rgb(15, 20, 32),
    });
    {
        if (uic.pass == .input and ctx.reload_count != state.prev_reload_count) {
            state.prev_reload_count = ctx.reload_count;
            uic.markDirty(titlebar_rect);
        }

        if (uic.shouldPaint(titlebar_rect)) {
            drawDecorations(state, ctx, canvas, titlebar_rect);
        }

        _ = uic.beginBox(170, 24, .{ .direction = .row, .gap = 0 });
        uic.endBox();

        const right_badges_width: f32 = 340;
        const avail = uic.availableWidth();
        if (avail > right_badges_width) {
            uic.spacer(avail - right_badges_width);
        }

        if (animate) {
            uic.badge(
                "60 FPS",
                skia.Color.argb(45, 245, 158, 11),
                skia.Color.rgb(251, 191, 36),
            );
        } else {
            uic.badge(
                "IDLE SLEEP",
                skia.Color.argb(40, 14, 165, 233),
                skia.Color.rgb(56, 189, 248),
            );
        }

        uic.badge(
            uic.fmt("HOOKS: {d}", .{ctx.stateEntryCount()}),
            uic.theme.bg_card,
            uic.theme.text_muted,
        );

        uic.badge(
            uic.fmt("CLICKS: {d}", .{click_count}),
            skia.Color.argb(45, 99, 102, 241),
            skia.Color.rgb(165, 180, 252),
        );
    }
    uic.endBox();

    const hairline = skia.Rect.xywh(0, titlebar_rect.bottom, ctx.width, 1);
    if (uic.shouldPaint(hairline)) {
        state.paint.setStyle(.fill);
        state.paint.setColor(skia.Color.argb(70, 100, 116, 139));
        canvas.drawRect(hairline, state.paint);
    }

    return titlebar_rect;
}

fn drawDecorations(
    state: *AppState,
    ctx: *const PlatformContext,
    canvas: skia.Canvas,
    bar: skia.c.sk_rect_t,
) void {
    const paint = state.paint;
    const uic = &state.ui_ctx;

    const left_pad: f32 = if (ctx.is_fullscreen) 16.0 else 88.0;
    paint.setStyle(.fill);
    if (!ctx.is_fullscreen) {
        paint.setColor(skia.Color.argb(65, 100, 116, 139));
        canvas.drawRect(skia.Rect.xywh(82, 13, 1, 20), paint);
    }

    paint.setColor(uic.theme.accent);
    canvas.drawRoundRect(skia.Rect.xywh(left_pad + 8, 16, 14, 14), 4, 4, paint);

    paint.setColor(uic.theme.text_primary);
    uic.drawTextCached(state.font_title, "Zig + Skia Studio", left_pad + 30, 28.5);

    const pill_w: f32 = 300;
    const pill_h: f32 = 26;
    const pill_x = (ctx.width - pill_w) * 0.5;
    if (pill_x > 265 and pill_x + pill_w < ctx.width - 355) {
        const pill_rect = skia.Rect.xywh(pill_x, bar.top + 10, pill_w, pill_h);

        paint.setStyle(.fill);
        paint.setColor(skia.Color.rgb(23, 31, 48));
        canvas.drawRoundRect(pill_rect, 7, 7, paint);

        paint.setStyle(.stroke);
        paint.setStrokeWidth(1.0);
        paint.setColor(skia.Color.argb(75, 100, 116, 139));
        canvas.drawRoundRect(pill_rect, 7, 7, paint);

        const pill_text = uic.fmt("useState + JSON Snapshot  (Reload #{d})", .{ctx.reload_count});
        const tw = uic.measureTextCached(state.font_mono, pill_text);
        paint.setStyle(.fill);
        paint.setColor(uic.theme.text_muted);
        uic.drawTextCached(
            state.font_mono,
            pill_text,
            pill_x + (pill_w - tw) * 0.5,
            pill_rect.top + 17.5,
        );
    }
}
