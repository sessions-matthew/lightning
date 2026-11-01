//! Idiomatic wrappers for `Surface`, `Canvas`, `Image`, and `Data`.

const c = @import("c/root.zig");
const root = @import("root.zig");
const Error = root.Error;
const ColorType = @import("color.zig").ColorType;
const Color4f = @import("color.zig").Color4f;
const ClipOp = @import("geometry.zig").ClipOp;
const ImageInfo = @import("geometry.zig").ImageInfo;
const Paint = @import("paint.zig").Paint;
const Path = @import("path.zig").Path;
const Font = @import("text.zig").Font;
const TextBlob = @import("text.zig").TextBlob;
const DirectContext = @import("gpu.zig").DirectContext;

pub const Surface = struct {
    ptr: *c.sk_surface_t,

    pub fn initRaster(info: c.sk_imageinfo_t) Error!Surface {
        var c_info = info;
        const ptr = c.sk_surface_new_raster(&c_info, 0, null) orelse return Error.InvalidSurface;
        return .{ .ptr = ptr };
    }

    pub fn initRasterDirect(info: c.sk_imageinfo_t, pixels: *anyopaque, row_bytes: usize) Error!Surface {
        var c_info = info;
        const ptr = c.sk_surface_new_raster_direct(&c_info, pixels, row_bytes, null, null, null) orelse return Error.InvalidSurface;
        return .{ .ptr = ptr };
    }

    pub fn initRasterN32Premul(width: i32, height: i32) Error!Surface {
        return initRaster(ImageInfo.initN32Premul(width, height));
    }

    pub fn initRenderTarget(
        context: DirectContext,
        info: c.sk_imageinfo_t,
        sample_count: i32,
    ) Error!Surface {
        var c_info = info;
        const ptr = c.sk_surface_new_render_target(
            @ptrCast(context.ptr),
            true,
            &c_info,
            sample_count,
            .top_left,
            null,
            false,
        ) orelse return Error.InvalidSurface;
        return .{ .ptr = ptr };
    }

    pub fn draw(self: Surface, target_canvas: Canvas, x: f32, y: f32, paint: ?Paint) void {
        c.sk_surface_draw(self.ptr, target_canvas.ptr, x, y, if (paint) |p| p.ptr else null);
    }

    pub fn initMetalLayer(
        context: DirectContext,
        layer: *const anyopaque,
        sample_count: i32,
        color_type: ColorType,
        drawable_out: *c.gr_mtl_handle_t,
    ) Error!Surface {
        drawable_out.* = null;
        const ptr = c.sk_surface_new_metal_layer(
            @ptrCast(context.ptr),
            layer,
            .top_left,
            sample_count,
            color_type,
            null,
            null,
            drawable_out,
        ) orelse return Error.InvalidSurface;
        return .{ .ptr = ptr };
    }

    pub fn deinit(self: Surface) void {
        c.sk_surface_unref(self.ptr);
    }

    pub fn canvas(self: Surface) Canvas {
        return .{ .ptr = c.sk_surface_get_canvas(self.ptr) };
    }

    pub fn makeImageSnapshot(self: Surface) Error!Image {
        const img_ptr = c.sk_surface_new_image_snapshot(self.ptr) orelse return Error.OutOfMemory;
        return .{ .ptr = img_ptr };
    }

    pub fn encodePng(self: Surface) Error!Data {
        const pixmap = c.sk_pixmap_new() orelse return Error.OutOfMemory;
        defer c.sk_pixmap_destructor(pixmap);

        if (!c.sk_surface_peek_pixels(self.ptr, pixmap)) {
            return Error.InvalidOperation;
        }

        const stream = c.sk_dynamicmemorywstream_new() orelse return Error.OutOfMemory;
        defer c.sk_dynamicmemorywstream_destroy(stream);

        const options: c.sk_pngencoder_options_t = .{};
        if (!c.sk_pngencoder_encode(@ptrCast(stream), pixmap, &options)) {
            return Error.EncodingFailed;
        }

        const data_ptr = c.sk_dynamicmemorywstream_detach_as_data(stream) orelse return Error.OutOfMemory;
        return .{ .ptr = data_ptr };
    }

    pub fn peekPixelColor(self: Surface, x: i32, y: i32) Error!u32 {
        const pixmap = c.sk_pixmap_new() orelse return Error.OutOfMemory;
        defer c.sk_pixmap_destructor(pixmap);

        if (!c.sk_surface_peek_pixels(self.ptr, pixmap)) {
            return Error.InvalidOperation;
        }
        return c.sk_pixmap_get_pixel_color(pixmap, x, y);
    }
};

pub const Canvas = struct {
    ptr: *c.sk_canvas_t,

    pub fn clear(self: Canvas, color: u32) void {
        c.sk_canvas_clear(self.ptr, color);
    }

    pub fn clearColor4f(self: Canvas, color: Color4f) void {
        c.sk_canvas_clear_color4f(self.ptr, color);
    }

    pub fn save(self: Canvas) i32 {
        return c.sk_canvas_save(self.ptr);
    }

    pub fn restore(self: Canvas) void {
        c.sk_canvas_restore(self.ptr);
    }

    pub fn restoreToCount(self: Canvas, save_count: i32) void {
        c.sk_canvas_restore_to_count(self.ptr, save_count);
    }

    pub fn translate(self: Canvas, dx: f32, dy: f32) void {
        c.sk_canvas_translate(self.ptr, dx, dy);
    }

    pub fn scale(self: Canvas, sx: f32, sy: f32) void {
        c.sk_canvas_scale(self.ptr, sx, sy);
    }

    pub fn rotateDegrees(self: Canvas, degrees: f32) void {
        c.sk_canvas_rotate_degrees(self.ptr, degrees);
    }

    pub fn clipRect(self: Canvas, rect: c.sk_rect_t, op: ClipOp, anti_alias: bool) void {
        var r = rect;
        c.sk_canvas_clip_rect_with_operation(self.ptr, &r, op, anti_alias);
    }

    pub fn clipPath(self: Canvas, path: Path, op: ClipOp, anti_alias: bool) void {
        c.sk_canvas_clip_path_with_operation(self.ptr, path.ptr, op, anti_alias);
    }

    pub fn quickReject(self: Canvas, rect: c.sk_rect_t) bool {
        var r = rect;
        return c.sk_canvas_quick_reject(self.ptr, &r);
    }

    pub fn drawRect(self: Canvas, rect: c.sk_rect_t, paint: Paint) void {
        var r = rect;
        c.sk_canvas_draw_rect(self.ptr, &r, paint.ptr);
    }

    pub fn drawRoundRect(self: Canvas, rect: c.sk_rect_t, rx: f32, ry: f32, paint: Paint) void {
        var r = rect;
        c.sk_canvas_draw_round_rect(self.ptr, &r, rx, ry, paint.ptr);
    }

    pub fn drawCircle(self: Canvas, cx: f32, cy: f32, radius: f32, paint: Paint) void {
        c.sk_canvas_draw_circle(self.ptr, cx, cy, radius, paint.ptr);
    }

    pub fn drawLine(self: Canvas, x0: f32, y0: f32, x1: f32, y1: f32, paint: Paint) void {
        c.sk_canvas_draw_line(self.ptr, x0, y0, x1, y1, paint.ptr);
    }

    pub fn drawPath(self: Canvas, path: Path, paint: Paint) void {
        c.sk_canvas_draw_path(self.ptr, path.ptr, paint.ptr);
    }

    pub fn drawSimpleText(self: Canvas, text: []const u8, x: f32, y: f32, font: Font, paint: Paint) void {
        c.sk_canvas_draw_simple_text(self.ptr, text.ptr, text.len, .utf8, x, y, font.ptr, paint.ptr);
    }

    pub fn drawTextBlob(self: Canvas, blob: TextBlob, x: f32, y: f32, paint: Paint) void {
        c.sk_canvas_draw_text_blob(self.ptr, blob.ptr, x, y, paint.ptr);
    }

    pub fn drawImage(self: Canvas, image: Image, x: f32, y: f32, paint: ?Paint) void {
        const sampling: c.sk_sampling_options_t = .{ .fFilter = .linear, .fMipmap = .none };
        c.sk_canvas_draw_image(self.ptr, image.ptr, x, y, &sampling, if (paint) |p| p.ptr else null);
    }

    pub fn drawImageRect(self: Canvas, image: Image, dst: c.sk_rect_t, paint: ?Paint) void {
        var d = dst;
        const sampling: c.sk_sampling_options_t = .{ .fFilter = .linear, .fMipmap = .none };
        c.sk_canvas_draw_image_rect(self.ptr, image.ptr, null, &d, &sampling, if (paint) |p| p.ptr else null);
    }

    pub fn drawImageRectSampling(self: Canvas, image: Image, dst: c.sk_rect_t, nearest: bool, paint: ?Paint) void {
        var d = dst;
        const sampling: c.sk_sampling_options_t = .{
            .fFilter = if (nearest) .nearest else .linear,
            .fMipmap = .none,
        };
        c.sk_canvas_draw_image_rect(self.ptr, image.ptr, null, &d, &sampling, if (paint) |p| p.ptr else null);
    }
};

pub const Image = struct {
    ptr: *c.sk_image_t,

    pub fn initRasterCopy(info: c.sk_imageinfo_t, pixels: *const anyopaque, row_bytes: usize) Error!Image {
        var c_info = info;
        const img_ptr = c.sk_image_new_raster_copy(&c_info, pixels, row_bytes) orelse return Error.OutOfMemory;
        return .{ .ptr = img_ptr };
    }

    pub fn initFromEncoded(data: Data) Error!Image {
        const img_ptr = c.sk_image_new_from_encoded(data.ptr) orelse return Error.InvalidOperation;
        return .{ .ptr = img_ptr };
    }

    pub fn initFromEncodedBytes(bytes: []const u8) Error!Image {
        if (bytes.len == 0) return Error.InvalidOperation;
        const data = try Data.initWithCopy(bytes);
        defer data.deinit();
        return initFromEncoded(data);
    }

    pub fn initFromFile(path_z: [*:0]const u8) Error!Image {
        const data = try Data.initFromFile(path_z);
        defer data.deinit();
        return initFromEncoded(data);
    }

    pub fn deinit(self: Image) void {
        c.sk_image_unref(self.ptr);
    }

    pub fn width(self: Image) i32 {
        return c.sk_image_get_width(self.ptr);
    }

    pub fn height(self: Image) i32 {
        return c.sk_image_get_height(self.ptr);
    }

    pub fn peekPixelColor(self: Image, x: i32, y: i32) ?u32 {
        const w = self.width();
        const h = self.height();
        if (x < 0 or y < 0 or x >= w or y >= h) return null;

        const pixmap = c.sk_pixmap_new() orelse return null;
        defer c.sk_pixmap_destructor(pixmap);
        if (c.sk_image_peek_pixels(self.ptr, pixmap)) {
            return c.sk_pixmap_get_pixel_color(pixmap, x, y);
        }

        // Fallback for lazy-decoded images: read a single 1x1 BGRA8888 pixel at (x, y)
        var pixel_bytes: [4]u8 = .{ 0, 0, 0, 0 };
        const info = ImageInfo.initBgra8888Premul(1, 1);
        if (c.sk_image_read_pixels(self.ptr, &info, &pixel_bytes, 4, x, y, .allow)) {
            const b: u32 = pixel_bytes[0];
            const g: u32 = pixel_bytes[1];
            const r: u32 = pixel_bytes[2];
            const a: u32 = pixel_bytes[3];
            return (a << 24) | (r << 16) | (g << 8) | b;
        }
        return null;
    }
};

pub const Data = struct {
    ptr: *c.sk_data_t,

    pub fn initWithCopy(bytes: []const u8) Error!Data {
        if (bytes.len == 0) {
            const ptr = c.sk_data_new_empty() orelse return Error.OutOfMemory;
            return .{ .ptr = ptr };
        }
        const ptr = c.sk_data_new_with_copy(bytes.ptr, bytes.len) orelse return Error.OutOfMemory;
        return .{ .ptr = ptr };
    }

    pub fn initFromFile(path_z: [*:0]const u8) Error!Data {
        const ptr = c.sk_data_new_from_file(path_z) orelse return Error.InvalidOperation;
        return .{ .ptr = ptr };
    }

    pub fn deinit(self: Data) void {
        c.sk_data_unref(self.ptr);
    }

    pub fn slice(self: Data) []const u8 {
        const size = c.sk_data_get_size(self.ptr);
        if (size == 0) return &.{};
        const bytes = c.sk_data_get_bytes(self.ptr) orelse return &.{};
        return bytes[0..size];
    }
};
