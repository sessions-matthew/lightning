//! Idiomatic Zig wrapper around SkiaSharp (`libSkiaSharp`) C bindings.
//! Domain-split under `src/skia/` with zero `@cImport` dependencies.

const std = @import("std");
pub const c = @import("c/root.zig");

const color_mod = @import("color.zig");
const geom_mod = @import("geometry.zig");
const paint_mod = @import("paint.zig");
const path_mod = @import("path.zig");
const text_mod = @import("text.zig");
const gpu_mod = @import("gpu.zig");
const surface_mod = @import("surface.zig");

pub const Error = error{
    OutOfMemory,
    InvalidSurface,
    InvalidOperation,
    EncodingFailed,
};

// Color & Enums
pub const ColorType = color_mod.ColorType;
pub const AlphaType = color_mod.AlphaType;
pub const Color = color_mod.Color;
pub const Color4f = color_mod.Color4f;

// Geometry
pub const Point = geom_mod.Point;
pub const IPoint = geom_mod.IPoint;
pub const Size = geom_mod.Size;
pub const ISize = geom_mod.ISize;
pub const Rect = geom_mod.Rect;
pub const IRect = geom_mod.IRect;
pub const ImageInfo = geom_mod.ImageInfo;
pub const ClipOp = geom_mod.ClipOp;

// Paint & Shader
pub const BlendMode = paint_mod.BlendMode;
pub const PaintStyle = paint_mod.PaintStyle;
pub const StrokeCap = paint_mod.StrokeCap;
pub const StrokeJoin = paint_mod.StrokeJoin;
pub const TileMode = paint_mod.TileMode;
pub const Paint = paint_mod.Paint;
pub const Shader = paint_mod.Shader;

// Path & PathBuilder
pub const PathDirection = path_mod.PathDirection;
pub const PathFillType = path_mod.PathFillType;
pub const Path = path_mod.Path;
pub const PathBuilder = path_mod.PathBuilder;

// Font, TextBlob, Typeface & FontMgr
pub const FontEdging = text_mod.FontEdging;
pub const FontHinting = text_mod.FontHinting;
pub const FontSlant = text_mod.FontSlant;
pub const Font = text_mod.Font;
pub const TextBlob = text_mod.TextBlob;
pub const Typeface = text_mod.Typeface;
pub const FontMgr = text_mod.FontMgr;

// GPU DirectContext
pub const DirectContext = gpu_mod.DirectContext;

// Surface, Canvas, Image & Data
pub const Surface = surface_mod.Surface;
pub const Canvas = surface_mod.Canvas;
pub const Image = surface_mod.Image;
pub const Data = surface_mod.Data;

test "raster surface, canvas drawing, pathbuilder, and png encoding" {
    const surface = try Surface.initRasterN32Premul(128, 128);
    defer surface.deinit();

    const canvas = surface.canvas();
    canvas.clear(Color.rgb(20, 24, 32));

    // Verify background pixel color
    const bg_pixel = try surface.peekPixelColor(10, 10);
    try std.testing.expectEqual(Color.rgb(20, 24, 32), bg_pixel);

    // Draw a filled red rectangle in the center
    const paint = try Paint.init();
    defer paint.deinit();
    paint.setAntiAlias(true);
    paint.setColor(Color.rgb(255, 64, 64));
    canvas.drawRect(Rect.xywh(32, 32, 64, 64), paint);

    const center_pixel = try surface.peekPixelColor(64, 64);
    try std.testing.expectEqual(Color.rgb(255, 64, 64), center_pixel);

    // Build and draw a triangle path
    const pb = try PathBuilder.init();
    defer pb.deinit();
    pb.moveTo(16, 112);
    pb.lineTo(64, 16);
    pb.lineTo(112, 112);
    pb.close();

    const path = try pb.detach();
    defer path.deinit();
    try std.testing.expect(path.contains(64, 80));

    // Encode surface to PNG and verify PNG signature
    const png_data = try surface.encodePng();
    defer png_data.deinit();

    const png_bytes = png_data.slice();
    try std.testing.expect(png_bytes.len > 8);
    try std.testing.expectEqualSlices(u8, "\x89PNG\r\n\x1a\n", png_bytes[0..8]);
}
