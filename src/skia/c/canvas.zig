//! SkiaSharp C API surface, canvas, image, pixmap, data, and stream functions.

const t = @import("types.zig");

// Surface (sk_surface.h)
pub extern "c" fn sk_surface_new_null(width: c_int, height: c_int) ?*t.sk_surface_t;
pub extern "c" fn sk_surface_new_raster(info: *const t.sk_imageinfo_t, rowBytes: usize, props: ?*const t.sk_surfaceprops_t) ?*t.sk_surface_t;
pub extern "c" fn sk_surface_new_raster_direct(info: *const t.sk_imageinfo_t, pixels: *anyopaque, rowBytes: usize, releaseProc: t.sk_surface_raster_release_proc, context: ?*anyopaque, props: ?*const t.sk_surfaceprops_t) ?*t.sk_surface_t;
pub extern "c" fn sk_surface_new_render_target(context: *t.gr_recording_context_t, budgeted: bool, cinfo: *const t.sk_imageinfo_t, sampleCount: c_int, origin: t.gr_surfaceorigin_t, props: ?*const t.sk_surfaceprops_t, shouldCreateWithMips: bool) ?*t.sk_surface_t;
pub extern "c" fn sk_surface_new_metal_layer(context: *t.gr_recording_context_t, layer: t.gr_mtl_handle_t, origin: t.gr_surfaceorigin_t, sampleCount: c_int, colorType: t.sk_colortype_t, colorspace: ?*t.sk_colorspace_t, props: ?*const t.sk_surfaceprops_t, drawable: *t.gr_mtl_handle_t) ?*t.sk_surface_t;
pub extern "c" fn sk_surface_unref(surface: *t.sk_surface_t) void;
pub extern "c" fn sk_surface_get_canvas(surface: *t.sk_surface_t) *t.sk_canvas_t;
pub extern "c" fn sk_surface_new_image_snapshot(surface: *t.sk_surface_t) ?*t.sk_image_t;
pub extern "c" fn sk_surface_new_image_snapshot_with_crop(surface: *t.sk_surface_t, bounds: *const t.sk_irect_t) ?*t.sk_image_t;
pub extern "c" fn sk_surface_draw(surface: *t.sk_surface_t, canvas: *t.sk_canvas_t, x: f32, y: f32, paint: ?*const t.sk_paint_t) void;
pub extern "c" fn sk_surface_draw_with_sampling(surface: *t.sk_surface_t, canvas: *t.sk_canvas_t, x: f32, y: f32, sampling: *const t.sk_sampling_options_t, paint: ?*const t.sk_paint_t) void;
pub extern "c" fn sk_surface_peek_pixels(surface: *t.sk_surface_t, pixmap: *t.sk_pixmap_t) bool;
pub extern "c" fn sk_surface_read_pixels(surface: *t.sk_surface_t, dstInfo: *t.sk_imageinfo_t, dstPixels: *anyopaque, dstRowBytes: usize, srcX: c_int, srcY: c_int) bool;
pub extern "c" fn sk_surfaceprops_new(flags: u32, geometry: t.sk_pixelgeometry_t) ?*t.sk_surfaceprops_t;
pub extern "c" fn sk_surfaceprops_delete(props: *t.sk_surfaceprops_t) void;

// Canvas (sk_canvas.h)
pub extern "c" fn sk_canvas_destroy(canvas: *t.sk_canvas_t) void;
pub extern "c" fn sk_canvas_clear(canvas: *t.sk_canvas_t, color: t.sk_color_t) void;
pub extern "c" fn sk_canvas_clear_color4f(canvas: *t.sk_canvas_t, color: t.sk_color4f_t) void;
pub extern "c" fn sk_canvas_discard(canvas: *t.sk_canvas_t) void;
pub extern "c" fn sk_canvas_get_save_count(canvas: *t.sk_canvas_t) c_int;
pub extern "c" fn sk_canvas_restore_to_count(canvas: *t.sk_canvas_t, saveCount: c_int) void;
pub extern "c" fn sk_canvas_draw_color(canvas: *t.sk_canvas_t, color: t.sk_color_t, mode: t.sk_blendmode_t) void;
pub extern "c" fn sk_canvas_draw_color4f(canvas: *t.sk_canvas_t, color: t.sk_color4f_t, mode: t.sk_blendmode_t) void;
pub extern "c" fn sk_canvas_draw_points(canvas: *t.sk_canvas_t, pointMode: t.sk_point_mode_t, count: usize, points: [*]const t.sk_point_t, paint: *const t.sk_paint_t) void;
pub extern "c" fn sk_canvas_draw_point(canvas: *t.sk_canvas_t, x: f32, y: f32, paint: *const t.sk_paint_t) void;
pub extern "c" fn sk_canvas_draw_line(canvas: *t.sk_canvas_t, x0: f32, y0: f32, x1: f32, y1: f32, paint: *t.sk_paint_t) void;
pub extern "c" fn sk_canvas_draw_simple_text(canvas: *t.sk_canvas_t, text: *const anyopaque, byte_length: usize, encoding: t.sk_text_encoding_t, x: f32, y: f32, font: *const t.sk_font_t, paint: *const t.sk_paint_t) void;
pub extern "c" fn sk_canvas_draw_text_blob(canvas: *t.sk_canvas_t, text: *t.sk_textblob_t, x: f32, y: f32, paint: *const t.sk_paint_t) void;
pub extern "c" fn sk_canvas_reset_matrix(canvas: *t.sk_canvas_t) void;
pub extern "c" fn sk_canvas_set_matrix(canvas: *t.sk_canvas_t, matrix: *const t.sk_matrix44_t) void;
pub extern "c" fn sk_canvas_get_matrix(canvas: *t.sk_canvas_t, matrix: *t.sk_matrix44_t) void;
pub extern "c" fn sk_canvas_draw_round_rect(canvas: *t.sk_canvas_t, rect: *const t.sk_rect_t, rx: f32, ry: f32, paint: *const t.sk_paint_t) void;
pub extern "c" fn sk_canvas_clip_rect_with_operation(canvas: *t.sk_canvas_t, rect: *const t.sk_rect_t, op: t.sk_clipop_t, doAA: bool) void;
pub extern "c" fn sk_canvas_clip_path_with_operation(canvas: *t.sk_canvas_t, path: *const t.sk_path_t, op: t.sk_clipop_t, doAA: bool) void;
pub extern "c" fn sk_canvas_clip_rrect_with_operation(canvas: *t.sk_canvas_t, rect: *const t.sk_rrect_t, op: t.sk_clipop_t, doAA: bool) void;
pub extern "c" fn sk_canvas_get_local_clip_bounds(canvas: *t.sk_canvas_t, bounds: *t.sk_rect_t) bool;
pub extern "c" fn sk_canvas_get_device_clip_bounds(canvas: *t.sk_canvas_t, bounds: *t.sk_irect_t) bool;
pub extern "c" fn sk_canvas_save(canvas: *t.sk_canvas_t) c_int;
pub extern "c" fn sk_canvas_save_layer(canvas: *t.sk_canvas_t, rect: ?*const t.sk_rect_t, paint: ?*const t.sk_paint_t) c_int;
pub extern "c" fn sk_canvas_save_layer_rec(canvas: *t.sk_canvas_t, rec: *const t.sk_canvas_savelayerrec_t) c_int;
pub extern "c" fn sk_canvas_restore(canvas: *t.sk_canvas_t) void;
pub extern "c" fn sk_canvas_translate(canvas: *t.sk_canvas_t, dx: f32, dy: f32) void;
pub extern "c" fn sk_canvas_scale(canvas: *t.sk_canvas_t, sx: f32, sy: f32) void;
pub extern "c" fn sk_canvas_rotate_degrees(canvas: *t.sk_canvas_t, degrees: f32) void;
pub extern "c" fn sk_canvas_rotate_radians(canvas: *t.sk_canvas_t, radians: f32) void;
pub extern "c" fn sk_canvas_skew(canvas: *t.sk_canvas_t, sx: f32, sy: f32) void;
pub extern "c" fn sk_canvas_concat(canvas: *t.sk_canvas_t, matrix: *const t.sk_matrix44_t) void;
pub extern "c" fn sk_canvas_quick_reject(canvas: *t.sk_canvas_t, rect: *const t.sk_rect_t) bool;
pub extern "c" fn sk_canvas_draw_paint(canvas: *t.sk_canvas_t, paint: *const t.sk_paint_t) void;
pub extern "c" fn sk_canvas_draw_rect(canvas: *t.sk_canvas_t, rect: *const t.sk_rect_t, paint: *const t.sk_paint_t) void;
pub extern "c" fn sk_canvas_draw_rrect(canvas: *t.sk_canvas_t, rect: *const t.sk_rrect_t, paint: *const t.sk_paint_t) void;
pub extern "c" fn sk_canvas_draw_circle(canvas: *t.sk_canvas_t, cx: f32, cy: f32, rad: f32, paint: *const t.sk_paint_t) void;
pub extern "c" fn sk_canvas_draw_oval(canvas: *t.sk_canvas_t, rect: *const t.sk_rect_t, paint: *const t.sk_paint_t) void;
pub extern "c" fn sk_canvas_draw_path(canvas: *t.sk_canvas_t, path: *const t.sk_path_t, paint: *const t.sk_paint_t) void;
pub extern "c" fn sk_canvas_draw_image(canvas: *t.sk_canvas_t, image: *const t.sk_image_t, x: f32, y: f32, sampling: *const t.sk_sampling_options_t, paint: ?*const t.sk_paint_t) void;
pub extern "c" fn sk_canvas_draw_image_rect(canvas: *t.sk_canvas_t, image: *const t.sk_image_t, srcR: ?*const t.sk_rect_t, dstR: *const t.sk_rect_t, sampling: *const t.sk_sampling_options_t, paint: ?*const t.sk_paint_t) void;
pub extern "c" fn sk_canvas_draw_arc(canvas: *t.sk_canvas_t, oval: *const t.sk_rect_t, startAngle: f32, sweepAngle: f32, useCenter: bool, paint: *const t.sk_paint_t) void;
pub extern "c" fn sk_canvas_draw_drrect(canvas: *t.sk_canvas_t, outer: *const t.sk_rrect_t, inner: *const t.sk_rrect_t, paint: *const t.sk_paint_t) void;

// Image & Pixmap (sk_image.h, sk_pixmap.h)
pub extern "c" fn sk_image_ref(image: *const t.sk_image_t) void;
pub extern "c" fn sk_image_unref(image: *const t.sk_image_t) void;
pub extern "c" fn sk_image_new_raster_copy(info: *const t.sk_imageinfo_t, pixels: *const anyopaque, rowBytes: usize) ?*t.sk_image_t;
pub extern "c" fn sk_image_new_raster_copy_with_pixmap(pixmap: *const t.sk_pixmap_t) ?*t.sk_image_t;
pub extern "c" fn sk_image_new_from_encoded(data: *const t.sk_data_t) ?*t.sk_image_t;
pub extern "c" fn sk_image_get_width(image: *const t.sk_image_t) c_int;
pub extern "c" fn sk_image_get_height(image: *const t.sk_image_t) c_int;
pub extern "c" fn sk_image_get_unique_id(image: *const t.sk_image_t) u32;
pub extern "c" fn sk_image_get_alpha_type(image: *const t.sk_image_t) t.sk_alphatype_t;
pub extern "c" fn sk_image_get_color_type(image: *const t.sk_image_t) t.sk_colortype_t;
pub extern "c" fn sk_image_peek_pixels(image: *const t.sk_image_t, pixmap: *t.sk_pixmap_t) bool;
pub extern "c" fn sk_image_read_pixels(image: *const t.sk_image_t, dstInfo: *const t.sk_imageinfo_t, dstPixels: *anyopaque, dstRowBytes: usize, srcX: c_int, srcY: c_int, cachingHint: t.sk_image_caching_hint_t) bool;

pub extern "c" fn sk_pixmap_destructor(pixmap: *t.sk_pixmap_t) void;
pub extern "c" fn sk_pixmap_new() ?*t.sk_pixmap_t;
pub extern "c" fn sk_pixmap_new_with_params(info: *const t.sk_imageinfo_t, addr: *const anyopaque, rowBytes: usize) ?*t.sk_pixmap_t;
pub extern "c" fn sk_pixmap_get_info(pixmap: *const t.sk_pixmap_t, info: *t.sk_imageinfo_t) void;
pub extern "c" fn sk_pixmap_get_row_bytes(pixmap: *const t.sk_pixmap_t) usize;
pub extern "c" fn sk_pixmap_get_pixel_color(pixmap: *const t.sk_pixmap_t, x: c_int, y: c_int) t.sk_color_t;
pub extern "c" fn sk_pixmap_get_writable_addr(pixmap: *const t.sk_pixmap_t) ?*anyopaque;
pub extern "c" fn sk_pngencoder_encode(dst: *t.sk_wstream_t, src: *const t.sk_pixmap_t, options: *const t.sk_pngencoder_options_t) bool;
pub extern "c" fn sk_jpegencoder_encode(dst: *t.sk_wstream_t, src: *const t.sk_pixmap_t, options: *const t.sk_jpegencoder_options_t) bool;
pub extern "c" fn sk_webpencoder_encode(dst: *t.sk_wstream_t, src: *const t.sk_pixmap_t, options: *const t.sk_webpencoder_options_t) bool;

// Data, Stream & String (sk_data.h, sk_stream.h, sk_string.h)
pub extern "c" fn sk_data_new_empty() ?*t.sk_data_t;
pub extern "c" fn sk_data_new_with_copy(src: *const anyopaque, length: usize) ?*t.sk_data_t;
pub extern "c" fn sk_data_ref(data: *const t.sk_data_t) void;
pub extern "c" fn sk_data_unref(data: *const t.sk_data_t) void;
pub extern "c" fn sk_data_get_size(data: *const t.sk_data_t) usize;
pub extern "c" fn sk_data_get_data(data: *const t.sk_data_t) ?*const anyopaque;
pub extern "c" fn sk_data_get_bytes(data: *const t.sk_data_t) ?[*]const u8;
pub extern "c" fn sk_data_new_from_file(path: [*:0]const u8) ?*t.sk_data_t;

pub extern "c" fn sk_dynamicmemorywstream_new() ?*t.sk_wstream_dynamicmemorystream_t;
pub extern "c" fn sk_dynamicmemorywstream_detach_as_data(stream: *t.sk_wstream_dynamicmemorystream_t) ?*t.sk_data_t;
pub extern "c" fn sk_dynamicmemorywstream_destroy(stream: *t.sk_wstream_dynamicmemorystream_t) void;
pub extern "c" fn sk_filewstream_new(path: [*:0]const u8) ?*t.sk_wstream_filestream_t;
pub extern "c" fn sk_filewstream_destroy(stream: *t.sk_wstream_filestream_t) void;
pub extern "c" fn sk_filewstream_is_valid(stream: *t.sk_wstream_filestream_t) bool;

pub extern "c" fn sk_string_new_empty() ?*t.sk_string_t;
pub extern "c" fn sk_string_new_with_copy(src: [*]const u8, length: usize) ?*t.sk_string_t;
pub extern "c" fn sk_string_destructor(str: *const t.sk_string_t) void;
pub extern "c" fn sk_string_get_size(str: *const t.sk_string_t) usize;
pub extern "c" fn sk_string_get_c_str(str: *const t.sk_string_t) [*:0]const u8;
