//! Built-in Crisp Vector Icons (`src/ui/icons.zig`) for `ui.Context`.
//!
//! Renders resolution-independent Skia vector icons for activity bars, debug toolbars,
//! file trees, split pane controls, and modal actions without external image assets.

const std = @import("std");
const skia = @import("skia");
const c = skia.c;
const Color = skia.Color;
const Rect = skia.Rect;
const Canvas = skia.Canvas;
const Paint = skia.Paint;

/// Built-in crisp vector icons drawn via Skia primitives.
pub const Icon = enum(u8) {
    files,
    search,
    git,
    plugins,
    debug,
    cpu,
    board,
    waveform,
    pdf,
    play,
    play_outline,
    pause,
    step_over,
    step_into,
    step_out,
    restart,
    stop,
    gear,
    debug_console,
    breakpoint,
    refresh,
    bolt,
    terminal,
    agent,
    split_horizontal,
    split_vertical,
    arrow_left,
    arrow_right,
    chevron_right,
    chevron_down,
    folder,
    folder_open,
    close,
};

pub const IconButtonOptions = struct {
    w: f32 = 28.0,
    h: f32 = 34.0,
    active: bool = false,
    show_active_bar: bool = false,
    accent_color: ?u32 = null,
};

/// Draws a crisp Skia vector `Icon` centered inside `r` using `ctx.canvas` and `ctx.paint`.
pub fn drawIcon(ctx: anytype, icon: Icon, r: c.sk_rect_t, color: u32) void {
    drawIconCanvas(ctx.canvas, ctx.paint, icon, r, color);
}

/// Draws a crisp Skia vector `Icon` centered inside `r` directly on `canvas` with `paint`.
pub fn drawIconCanvas(canvas: Canvas, paint: Paint, icon: Icon, r: c.sk_rect_t, color: u32) void {
    const cx = (r.left + r.right) * 0.5;
    const cy = (r.top + r.bottom) * 0.5;
    paint.setStyle(.stroke);
    paint.setStrokeWidth(1.45);
    paint.setStrokeCap(.round);
    paint.setStrokeJoin(.round);
    paint.setColor(color);
    defer {
        paint.setStrokeCap(.butt);
        paint.setStrokeJoin(.miter);
    }

    switch (icon) {
        .files => {
            canvas.drawRoundRect(Rect.xywh(cx - 6.0, cy - 7.0, 12.0, 14.0), 2.0, 2.0, paint);
            canvas.drawLine(cx - 3.0, cy - 2.0, cx + 3.0, cy - 2.0, paint);
            canvas.drawLine(cx - 3.0, cy + 2.0, cx + 3.0, cy + 2.0, paint);
        },
        .search => {
            canvas.drawCircle(cx - 1.5, cy - 1.5, 5.5, paint);
            canvas.drawLine(cx + 2.5, cy + 2.5, cx + 7.0, cy + 7.0, paint);
        },
        .git => {
            canvas.drawCircle(cx - 4.0, cy - 5.0, 2.2, paint);
            canvas.drawCircle(cx - 4.0, cy + 5.0, 2.2, paint);
            canvas.drawCircle(cx + 4.0, cy - 1.0, 2.2, paint);
            canvas.drawLine(cx - 4.0, cy - 2.8, cx - 4.0, cy + 2.8, paint);
            canvas.drawLine(cx - 4.0, cy + 1.0, cx + 1.8, cy - 1.0, paint);
        },
        .plugins => {
            // 4-block extension grid with highlighted detached top-right block
            canvas.drawRoundRect(Rect.xywh(cx - 6.5, cy - 6.5, 5.5, 5.5), 1.4, 1.4, paint);
            canvas.drawRoundRect(Rect.xywh(cx - 6.5, cy + 1.0, 5.5, 5.5), 1.4, 1.4, paint);
            canvas.drawRoundRect(Rect.xywh(cx + 1.0, cy + 1.0, 5.5, 5.5), 1.4, 1.4, paint);
            const top_r = Rect.xywh(cx + 2.0, cy - 7.5, 5.5, 5.5);
            paint.setStyle(.fill);
            paint.setColor(Color.withAlpha(color, 50));
            canvas.drawRoundRect(top_r, 1.4, 1.4, paint);
            paint.setStyle(.stroke);
            paint.setColor(color);
            canvas.drawRoundRect(top_r, 1.4, 1.4, paint);
        },
        .debug => {
            // Iconic Run & Debug icon: crisp beetle carapace with jointed legs + top-left Play triangle badge
            const bx = cx + 1.6;
            const by = cy + 1.2;

            // 1. Bug carapace body (subtle tinted fill + rounded outline + wing division)
            const body_r = Rect.xywh(bx - 3.6, by - 2.6, 7.2, 8.8);
            paint.setStyle(.fill);
            paint.setColor(Color.withAlpha(color, 42));
            canvas.drawRoundRect(body_r, 3.6, 3.6, paint);

            // Bug head dome (filled)
            paint.setColor(color);
            canvas.drawCircle(bx, by - 3.4, 1.7, paint);

            paint.setStyle(.stroke);
            paint.setStrokeWidth(1.4);
            canvas.drawRoundRect(body_r, 3.6, 3.6, paint);
            // Thorax line & central wing split
            canvas.drawLine(bx - 3.2, by - 0.2, bx + 3.2, by - 0.2, paint);
            canvas.drawLine(bx, by - 0.2, bx, by + 5.8, paint);

            // Antennae
            canvas.drawLine(bx - 0.9, by - 4.6, bx - 2.3, by - 6.3, paint);
            canvas.drawLine(bx + 0.9, by - 4.6, bx + 2.5, by - 6.3, paint);

            // 3 pairs of angled bug legs
            canvas.drawLine(bx - 3.6, by - 0.8, bx - 6.0, by - 2.0, paint);
            canvas.drawLine(bx + 3.6, by - 0.8, bx + 6.0, by - 2.0, paint);
            canvas.drawLine(bx - 3.8, by + 1.8, bx - 6.4, by + 1.8, paint);
            canvas.drawLine(bx + 3.8, by + 1.8, bx + 6.4, by + 1.8, paint);
            canvas.drawLine(bx - 3.4, by + 4.4, bx - 5.8, by + 5.8, paint);
            canvas.drawLine(bx + 3.4, by + 4.4, bx + 5.8, by + 5.8, paint);

            // 2. Top-left Play triangle badge
            if (skia.PathBuilder.init()) |pb| {
                defer pb.deinit();
                pb.moveTo(cx - 7.8, cy - 7.2);
                pb.lineTo(cx - 2.2, cy - 3.8);
                pb.lineTo(cx - 7.8, cy - 0.4);
                pb.close();
                if (pb.detach()) |path| {
                    defer path.deinit();
                    paint.setStyle(.fill);
                    paint.setColor(color);
                    canvas.drawPath(path, paint);
                } else |_| {}
            } else |_| {}
        },
        .cpu => {
            // Hardware IC package + inner silicon die + 3 pins per side
            const pkg_r = Rect.xywh(cx - 4.8, cy - 4.8, 9.6, 9.6);
            const die_r = Rect.xywh(cx - 2.1, cy - 2.1, 4.2, 4.2);
            paint.setStyle(.fill);
            paint.setColor(Color.withAlpha(color, 50));
            canvas.drawRoundRect(die_r, 0.8, 0.8, paint);
            paint.setStyle(.stroke);
            paint.setColor(color);
            canvas.drawRoundRect(pkg_r, 1.8, 1.8, paint);
            canvas.drawRoundRect(die_r, 0.8, 0.8, paint);

            const offsets = [_]f32{ -2.6, 0.0, 2.6 };
            for (offsets) |off| {
                canvas.drawLine(cx + off, cy - 7.4, cx + off, cy - 4.8, paint);
                canvas.drawLine(cx + off, cy + 4.8, cx + off, cy + 7.4, paint);
                canvas.drawLine(cx - 7.4, cy + off, cx - 4.8, cy + off, paint);
                canvas.drawLine(cx + 4.8, cy + off, cx + 7.4, cy + off, paint);
            }
        },
        .board => {
            // Single-Board Computer (BeagleBone Black) outline + dual P8/P9 headers + AM335x SoC + USR0-3 LEDs
            const pcb_r = Rect.xywh(cx - 7.2, cy - 6.0, 14.4, 12.0);
            const soc_r = Rect.xywh(cx - 2.3, cy - 2.1, 4.6, 4.6);
            paint.setStyle(.fill);
            paint.setColor(Color.withAlpha(color, 42));
            canvas.drawRoundRect(soc_r, 0.8, 0.8, paint);
            paint.setStyle(.stroke);
            paint.setStrokeWidth(1.35);
            paint.setColor(color);
            canvas.drawRoundRect(pcb_r, 2.2, 2.2, paint);
            canvas.drawRoundRect(soc_r, 0.8, 0.8, paint);

            // Dual P8 (top) & P9 (bottom) expansion header rails
            canvas.drawLine(cx - 4.8, cy - 4.0, cx + 4.8, cy - 4.0, paint);
            canvas.drawLine(cx - 4.8, cy + 4.0, cx + 4.8, cy + 4.0, paint);

            // 4 USR LEDs along the right board edge
            paint.setStyle(.fill);
            const led_ys = [_]f32{ -2.7, -0.9, 0.9, 2.7 };
            for (led_ys) |ly| {
                canvas.drawCircle(cx + 5.0, cy + ly, 0.75, paint);
            }
        },
        .waveform => {
            // Digital logic analyzer: top clock pulse train + bottom bus transition
            if (skia.PathBuilder.init()) |pb| {
                defer pb.deinit();
                pb.moveTo(cx - 7.2, cy - 0.5);
                pb.lineTo(cx - 4.5, cy - 0.5);
                pb.lineTo(cx - 4.5, cy - 5.5);
                pb.lineTo(cx - 0.5, cy - 5.5);
                pb.lineTo(cx - 0.5, cy - 0.5);
                pb.lineTo(cx + 3.5, cy - 0.5);
                pb.lineTo(cx + 3.5, cy - 5.5);
                pb.lineTo(cx + 7.2, cy - 5.5);
                if (pb.detach()) |path| {
                    defer path.deinit();
                    paint.setStyle(.stroke);
                    canvas.drawPath(path, paint);
                } else |_| {}
            } else |_| {}
            // Bottom bus hex envelope with X transition
            canvas.drawLine(cx - 7.2, cy + 2.5, cx - 1.5, cy + 2.5, paint);
            canvas.drawLine(cx - 7.2, cy + 6.0, cx - 1.5, cy + 6.0, paint);
            canvas.drawLine(cx - 1.5, cy + 2.5, cx + 1.5, cy + 6.0, paint);
            canvas.drawLine(cx - 1.5, cy + 6.0, cx + 1.5, cy + 2.5, paint);
            canvas.drawLine(cx + 1.5, cy + 2.5, cx + 7.2, cy + 2.5, paint);
            canvas.drawLine(cx + 1.5, cy + 6.0, cx + 7.2, cy + 6.0, paint);
        },
        .pdf => {
            // Document sheet with folded top-right corner + tinted header band + text rules
            const sheet_r = Rect.xywh(cx - 6.0, cy - 7.2, 12.0, 14.4);
            paint.setStyle(.fill);
            paint.setColor(Color.withAlpha(color, 38));
            canvas.drawRoundRect(Rect.xywh(cx - 6.0, cy - 7.2, 12.0, 4.6), 1.6, 1.6, paint);
            paint.setStyle(.stroke);
            paint.setStrokeWidth(1.4);
            paint.setColor(color);
            canvas.drawRoundRect(sheet_r, 1.8, 1.8, paint);
            // Top-right dog-ear fold & text lines
            canvas.drawLine(cx + 2.2, cy - 7.2, cx + 2.2, cy - 3.4, paint);
            canvas.drawLine(cx + 2.2, cy - 3.4, cx + 6.0, cy - 3.4, paint);
            canvas.drawLine(cx - 3.4, cy - 0.5, cx + 3.4, cy - 0.5, paint);
            canvas.drawLine(cx - 3.4, cy + 2.3, cx + 3.4, cy + 2.3, paint);
            canvas.drawLine(cx - 3.4, cy + 5.0, cx + 1.4, cy + 5.0, paint);
        },
        .play => {
            if (skia.PathBuilder.init()) |pb| {
                defer pb.deinit();
                pb.moveTo(cx - 3.8, cy - 4.8);
                pb.lineTo(cx + 4.6, cy);
                pb.lineTo(cx - 3.8, cy + 4.8);
                pb.close();
                if (pb.detach()) |path| {
                    defer path.deinit();
                    paint.setStyle(.fill);
                    paint.setColor(color);
                    canvas.drawPath(path, paint);
                } else |_| {}
            } else |_| {}
        },
        .play_outline => {
            if (skia.PathBuilder.init()) |pb| {
                defer pb.deinit();
                pb.moveTo(cx - 4.2, cy - 5.2);
                pb.lineTo(cx + 4.8, cy);
                pb.lineTo(cx - 4.2, cy + 5.2);
                pb.close();
                if (pb.detach()) |path| {
                    defer path.deinit();
                    paint.setStyle(.stroke);
                    paint.setStrokeWidth(1.5);
                    paint.setColor(color);
                    canvas.drawPath(path, paint);
                } else |_| {}
            } else |_| {}
        },
        .pause => {
            paint.setStyle(.stroke);
            paint.setStrokeWidth(1.6);
            canvas.drawLine(cx - 2.6, cy - 4.8, cx - 2.6, cy + 4.8, paint);
            canvas.drawLine(cx + 2.6, cy - 4.8, cx + 2.6, cy + 4.8, paint);
        },
        .restart => {
            paint.setStyle(.stroke);
            canvas.drawCircle(cx, cy + 0.5, 4.6, paint);
            canvas.drawLine(cx - 3.6, cy - 4.2, cx - 0.8, cy - 4.2, paint);
            canvas.drawLine(cx - 3.6, cy - 4.2, cx - 3.6, cy - 1.4, paint);
        },
        .stop => {
            paint.setStyle(.stroke);
            canvas.drawRoundRect(Rect.xywh(cx - 4.4, cy - 4.4, 8.8, 8.8), 1.2, 1.2, paint);
        },
        .gear => {
            paint.setStyle(.stroke);
            paint.setStrokeWidth(1.35);
            canvas.drawCircle(cx, cy, 2.2, paint);
            canvas.drawCircle(cx, cy, 4.4, paint);
            // 8 radial cog teeth (cardinal + diagonal)
            canvas.drawLine(cx, cy - 6.2, cx, cy - 4.4, paint);
            canvas.drawLine(cx, cy + 4.4, cx, cy + 6.2, paint);
            canvas.drawLine(cx - 6.2, cy, cx - 4.4, cy, paint);
            canvas.drawLine(cx + 4.4, cy, cx + 6.2, cy, paint);
            canvas.drawLine(cx - 4.4, cy - 4.4, cx - 3.1, cy - 3.1, paint);
            canvas.drawLine(cx + 3.1, cy + 3.1, cx + 4.4, cy + 4.4, paint);
            canvas.drawLine(cx + 4.4, cy - 4.4, cx + 3.1, cy - 3.1, paint);
            canvas.drawLine(cx - 3.1, cy + 3.1, cx - 4.4, cy + 4.4, paint);
        },
        .debug_console => {
            // Rounded console square with `>_` prompt inside
            paint.setStyle(.stroke);
            paint.setStrokeWidth(1.35);
            canvas.drawRoundRect(Rect.xywh(cx - 6.2, cy - 5.6, 12.4, 11.2), 2.0, 2.0, paint);
            canvas.drawLine(cx - 3.4, cy - 2.2, cx - 0.8, cy, paint);
            canvas.drawLine(cx - 0.8, cy, cx - 3.4, cy + 2.2, paint);
            canvas.drawLine(cx + 0.6, cy + 2.4, cx + 3.6, cy + 2.4, paint);
        },
        .step_over => {
            // Statement dot + curved arc jumping over it with right arrowhead
            paint.setStyle(.fill);
            canvas.drawCircle(cx, cy + 3.2, 1.8, paint);
            paint.setStyle(.stroke);
            if (skia.PathBuilder.init()) |pb| {
                defer pb.deinit();
                pb.moveTo(cx - 5.2, cy + 1.0);
                pb.quadTo(cx, cy - 6.2, cx + 5.2, cy + 1.0);
                if (pb.detach()) |path| {
                    defer path.deinit();
                    canvas.drawPath(path, paint);
                } else |_| {}
            } else |_| {}
            canvas.drawLine(cx + 2.4, cy + 0.6, cx + 5.2, cy + 1.0, paint);
            canvas.drawLine(cx + 4.6, cy - 2.0, cx + 5.2, cy + 1.0, paint);
        },
        .step_into => {
            // Downward arrow pointing into target dot
            paint.setStyle(.fill);
            canvas.drawCircle(cx, cy + 4.5, 1.8, paint);
            paint.setStyle(.stroke);
            canvas.drawLine(cx, cy - 5.5, cx, cy + 1.2, paint);
            canvas.drawLine(cx - 3.0, cy - 1.5, cx, cy + 1.5, paint);
            canvas.drawLine(cx + 3.0, cy - 1.5, cx, cy + 1.5, paint);
        },
        .step_out => {
            // Upward arrow leaving target dot
            paint.setStyle(.fill);
            canvas.drawCircle(cx, cy + 4.5, 1.8, paint);
            paint.setStyle(.stroke);
            canvas.drawLine(cx, cy + 1.5, cx, cy - 5.2, paint);
            canvas.drawLine(cx - 3.0, cy - 2.2, cx, cy - 5.2, paint);
            canvas.drawLine(cx + 3.0, cy - 2.2, cx, cy - 5.2, paint);
        },
        .breakpoint => {
            paint.setStyle(.fill);
            paint.setColor(Color.withAlpha(color, 65));
            canvas.drawCircle(cx, cy, 5.2, paint);
            paint.setColor(color);
            canvas.drawCircle(cx, cy, 3.2, paint);
        },
        .refresh => {
            canvas.drawCircle(cx, cy, 4.8, paint);
            canvas.drawLine(cx + 2.2, cy - 4.8, cx + 5.2, cy - 4.8, paint);
            canvas.drawLine(cx + 5.2, cy - 4.8, cx + 5.2, cy - 1.8, paint);
        },
        .bolt => {
            if (skia.PathBuilder.init()) |pb| {
                defer pb.deinit();
                pb.moveTo(cx + 1.0, cy - 5.8);
                pb.lineTo(cx - 4.0, cy + 0.5);
                pb.lineTo(cx + 0.2, cy + 0.5);
                pb.lineTo(cx - 1.0, cy + 5.8);
                pb.lineTo(cx + 4.0, cy - 0.5);
                pb.lineTo(cx - 0.2, cy - 0.5);
                pb.close();
                if (pb.detach()) |path| {
                    defer path.deinit();
                    paint.setStyle(.fill);
                    canvas.drawPath(path, paint);
                } else |_| {}
            } else |_| {}
        },
        .terminal => {
            canvas.drawRoundRect(Rect.xywh(cx - 7.0, cy - 5.0, 14.0, 10.0), 2.0, 2.0, paint);
            canvas.drawLine(cx - 7.0, cy + 1.0, cx + 7.0, cy + 1.0, paint);
        },
        .agent => {
            // Sparkle / AI Agent icon: central diamond + top-right star accent
            canvas.drawLine(cx, cy - 6.5, cx + 2.2, cy - 2.2, paint);
            canvas.drawLine(cx + 2.2, cy - 2.2, cx + 6.5, cy, paint);
            canvas.drawLine(cx + 6.5, cy, cx + 2.2, cy + 2.2, paint);
            canvas.drawLine(cx + 2.2, cy + 2.2, cx, cy + 6.5, paint);
            canvas.drawLine(cx, cy + 6.5, cx - 2.2, cy + 2.2, paint);
            canvas.drawLine(cx - 2.2, cy + 2.2, cx - 6.5, cy, paint);
            canvas.drawLine(cx - 6.5, cy, cx - 2.2, cy - 2.2, paint);
            canvas.drawLine(cx - 2.2, cy - 2.2, cx, cy - 6.5, paint);
            // Small top-right sparkle cross
            canvas.drawLine(cx + 5.0, cy - 6.5, cx + 5.0, cy - 3.5, paint);
            canvas.drawLine(cx + 3.5, cy - 5.0, cx + 6.5, cy - 5.0, paint);
        },
        .split_horizontal => {
            const icon_r = Rect.xywh(cx - 7.0, cy - 6.5, 14.0, 13.0);
            canvas.drawRoundRect(icon_r, 2.0, 2.0, paint);
            canvas.drawLine(cx, icon_r.top, cx, icon_r.bottom, paint);
        },
        .split_vertical => {
            const icon_r = Rect.xywh(cx - 7.0, cy - 6.5, 14.0, 13.0);
            canvas.drawRoundRect(icon_r, 2.0, 2.0, paint);
            canvas.drawLine(icon_r.left, cy, icon_r.right, cy, paint);
        },
        .arrow_right => {
            canvas.drawLine(cx - 5.0, cy, cx + 4.5, cy, paint);
            canvas.drawLine(cx + 1.0, cy - 3.5, cx + 4.5, cy, paint);
            canvas.drawLine(cx + 1.0, cy + 3.5, cx + 4.5, cy, paint);
        },
        .arrow_left => {
            canvas.drawLine(cx + 5.0, cy, cx - 4.5, cy, paint);
            canvas.drawLine(cx - 1.0, cy - 3.5, cx - 4.5, cy, paint);
            canvas.drawLine(cx - 1.0, cy + 3.5, cx - 4.5, cy, paint);
        },
        .chevron_right => {
            canvas.drawLine(cx - 2.2, cy - 4.0, cx + 2.3, cy, paint);
            canvas.drawLine(cx + 2.3, cy, cx - 2.2, cy + 4.0, paint);
        },
        .chevron_down => {
            canvas.drawLine(cx - 4.0, cy - 2.0, cx, cy + 2.5, paint);
            canvas.drawLine(cx, cy + 2.5, cx + 4.0, cy - 2.0, paint);
        },
        .folder => {
            canvas.drawRoundRect(Rect.xywh(cx - 6.5, cy - 3.5, 13.0, 9.0), 1.6, 1.6, paint);
            canvas.drawLine(cx - 6.0, cy - 5.2, cx - 1.5, cy - 5.2, paint);
            canvas.drawLine(cx - 1.5, cy - 5.2, cx + 0.5, cy - 3.5, paint);
        },
        .folder_open => {
            canvas.drawRoundRect(Rect.xywh(cx - 6.5, cy - 2.5, 13.0, 8.0), 1.6, 1.6, paint);
            canvas.drawLine(cx - 6.0, cy - 5.0, cx - 1.2, cy - 5.0, paint);
            canvas.drawLine(cx - 1.2, cy - 5.0, cx + 0.8, cy - 2.5, paint);
            canvas.drawLine(cx - 4.5, cy + 1.5, cx + 4.5, cy + 1.5, paint);
        },
        .close => {
            const d: f32 = 3.8;
            canvas.drawLine(cx - d, cy - d, cx + d, cy + d, paint);
            canvas.drawLine(cx + d, cy - d, cx - d, cy + d, paint);
        },
    }
}

test "Icon: drawIcon renders all built-in vector icon variants" {
    const surface = try skia.Surface.initRasterN32Premul(128, 128);
    defer surface.deinit();
    const paint = try Paint.init();
    defer paint.deinit();
    paint.setAntiAlias(true);

    const DummyCtx = struct {
        canvas: Canvas,
        paint: Paint,
    };
    const dummy = DummyCtx{
        .canvas = surface.canvas(),
        .paint = paint,
    };

    for (std.enums.values(Icon)) |icon| {
        drawIcon(dummy, icon, Rect.xywh(8, 8, 28, 28), Color.white);
    }
}
