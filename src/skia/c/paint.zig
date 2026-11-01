//! SkiaSharp C API paint and shader functions (`sk_paint.h`, `sk_shader.h`).

const t = @import("types.zig");

pub extern "c" fn sk_paint_new() ?*t.sk_paint_t;
pub extern "c" fn sk_paint_clone(paint: *t.sk_paint_t) ?*t.sk_paint_t;
pub extern "c" fn sk_paint_delete(paint: *t.sk_paint_t) void;
pub extern "c" fn sk_paint_reset(paint: *t.sk_paint_t) void;
pub extern "c" fn sk_paint_is_antialias(paint: *const t.sk_paint_t) bool;
pub extern "c" fn sk_paint_set_antialias(paint: *t.sk_paint_t, aa: bool) void;
pub extern "c" fn sk_paint_get_color(paint: *const t.sk_paint_t) t.sk_color_t;
pub extern "c" fn sk_paint_get_color4f(paint: *const t.sk_paint_t, color: *t.sk_color4f_t) void;
pub extern "c" fn sk_paint_set_color(paint: *t.sk_paint_t, color: t.sk_color_t) void;
pub extern "c" fn sk_paint_set_color4f(paint: *t.sk_paint_t, color: *t.sk_color4f_t, colorspace: ?*t.sk_colorspace_t) void;
pub extern "c" fn sk_paint_get_style(paint: *const t.sk_paint_t) t.sk_paint_style_t;
pub extern "c" fn sk_paint_set_style(paint: *t.sk_paint_t, style: t.sk_paint_style_t) void;
pub extern "c" fn sk_paint_get_stroke_width(paint: *const t.sk_paint_t) f32;
pub extern "c" fn sk_paint_set_stroke_width(paint: *t.sk_paint_t, width: f32) void;
pub extern "c" fn sk_paint_get_stroke_miter(paint: *const t.sk_paint_t) f32;
pub extern "c" fn sk_paint_set_stroke_miter(paint: *t.sk_paint_t, miter: f32) void;
pub extern "c" fn sk_paint_get_stroke_cap(paint: *const t.sk_paint_t) t.sk_stroke_cap_t;
pub extern "c" fn sk_paint_set_stroke_cap(paint: *t.sk_paint_t, cap: t.sk_stroke_cap_t) void;
pub extern "c" fn sk_paint_get_stroke_join(paint: *const t.sk_paint_t) t.sk_stroke_join_t;
pub extern "c" fn sk_paint_set_stroke_join(paint: *t.sk_paint_t, join: t.sk_stroke_join_t) void;
pub extern "c" fn sk_paint_set_shader(paint: *t.sk_paint_t, shader: ?*t.sk_shader_t) void;
pub extern "c" fn sk_paint_get_shader(paint: *t.sk_paint_t) ?*t.sk_shader_t;
pub extern "c" fn sk_paint_set_maskfilter(paint: *t.sk_paint_t, filter: ?*t.sk_maskfilter_t) void;
pub extern "c" fn sk_paint_get_maskfilter(paint: *t.sk_paint_t) ?*t.sk_maskfilter_t;
pub extern "c" fn sk_paint_set_blendmode(paint: *t.sk_paint_t, mode: t.sk_blendmode_t) void;
pub extern "c" fn sk_paint_get_blendmode(paint: *t.sk_paint_t) t.sk_blendmode_t;
pub extern "c" fn sk_paint_is_dither(paint: *const t.sk_paint_t) bool;
pub extern "c" fn sk_paint_set_dither(paint: *t.sk_paint_t, dither: bool) void;
pub extern "c" fn sk_paint_set_colorfilter(paint: *t.sk_paint_t, filter: ?*t.sk_colorfilter_t) void;
pub extern "c" fn sk_paint_get_colorfilter(paint: *t.sk_paint_t) ?*t.sk_colorfilter_t;
pub extern "c" fn sk_paint_set_imagefilter(paint: *t.sk_paint_t, filter: ?*t.sk_imagefilter_t) void;
pub extern "c" fn sk_paint_get_imagefilter(paint: *t.sk_paint_t) ?*t.sk_imagefilter_t;
pub extern "c" fn sk_paint_set_path_effect(paint: *t.sk_paint_t, effect: ?*t.sk_path_effect_t) void;
pub extern "c" fn sk_paint_get_path_effect(paint: *t.sk_paint_t) ?*t.sk_path_effect_t;

pub extern "c" fn sk_shader_ref(shader: *t.sk_shader_t) void;
pub extern "c" fn sk_shader_unref(shader: *t.sk_shader_t) void;
pub extern "c" fn sk_shader_new_linear_gradient(points: *const [2]t.sk_point_t, colors: [*]const t.sk_color_t, colorPos: ?[*]const f32, colorCount: c_int, tileMode: t.sk_shader_tilemode_t, localMatrix: ?*const t.sk_matrix_t) ?*t.sk_shader_t;
pub extern "c" fn sk_shader_new_radial_gradient(center: *const t.sk_point_t, radius: f32, colors: [*]const t.sk_color_t, colorPos: ?[*]const f32, colorCount: c_int, tileMode: t.sk_shader_tilemode_t, localMatrix: ?*const t.sk_matrix_t) ?*t.sk_shader_t;
