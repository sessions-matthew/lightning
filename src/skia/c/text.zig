//! SkiaSharp C API font, typeface, fontmgr, and textblob functions (`sk_font.h`, `sk_typeface.h`, `sk_textblob.h`).

const t = @import("types.zig");

pub extern "c" fn sk_font_new_with_values(typeface: ?*t.sk_typeface_t, size: f32, scaleX: f32, skewX: f32) ?*t.sk_font_t;
pub extern "c" fn sk_font_delete(font: *t.sk_font_t) void;
pub extern "c" fn sk_font_set_embedded_bitmaps(font: *t.sk_font_t, value: bool) void;
pub extern "c" fn sk_font_set_subpixel(font: *t.sk_font_t, value: bool) void;
pub extern "c" fn sk_font_is_subpixel(font: *const t.sk_font_t) bool;
pub extern "c" fn sk_font_get_edging(font: *const t.sk_font_t) t.sk_font_edging_t;
pub extern "c" fn sk_font_set_edging(font: *t.sk_font_t, value: t.sk_font_edging_t) void;
pub extern "c" fn sk_font_get_hinting(font: *const t.sk_font_t) t.sk_font_hinting_t;
pub extern "c" fn sk_font_set_hinting(font: *t.sk_font_t, value: t.sk_font_hinting_t) void;
pub extern "c" fn sk_font_get_size(font: *const t.sk_font_t) f32;
pub extern "c" fn sk_font_set_size(font: *t.sk_font_t, value: f32) void;
pub extern "c" fn sk_font_get_typeface(font: *const t.sk_font_t) ?*t.sk_typeface_t;
pub extern "c" fn sk_font_set_typeface(font: *t.sk_font_t, value: ?*t.sk_typeface_t) void;
pub extern "c" fn sk_font_measure_text(font: *const t.sk_font_t, text: *const anyopaque, byteLength: usize, encoding: t.sk_text_encoding_t, bounds: ?*t.sk_rect_t, paint: ?*const t.sk_paint_t) f32;
pub extern "c" fn sk_font_get_metrics(font: *const t.sk_font_t, metrics: ?*t.sk_fontmetrics_t) f32;
pub extern "c" fn sk_font_text_to_glyphs(font: *const t.sk_font_t, text: *const anyopaque, byteLength: usize, encoding: t.sk_text_encoding_t, glyphs: ?[*]u16, maxGlyphCount: c_int) c_int;
pub extern "c" fn sk_font_unichar_to_glyph(font: *const t.sk_font_t, uni: i32) u16;
pub extern "c" fn sk_font_unichars_to_glyphs(font: *const t.sk_font_t, uni: [*]const i32, count: c_int, glyphs: [*]u16) void;
pub extern "c" fn sk_font_get_widths_bounds(font: *const t.sk_font_t, glyphs: [*]const u16, count: c_int, widths: ?[*]f32, bounds: ?[*]t.sk_rect_t, paint: ?*const t.sk_paint_t) void;
pub extern "c" fn sk_font_get_xpos(font: *const t.sk_font_t, glyphs: [*]const u16, count: c_int, xpos: [*]f32, origin: f32) void;

pub extern "c" fn sk_textblob_ref(blob: *const t.sk_textblob_t) void;
pub extern "c" fn sk_textblob_unref(blob: *const t.sk_textblob_t) void;
pub extern "c" fn sk_textblob_builder_new() ?*t.sk_textblob_builder_t;
pub extern "c" fn sk_textblob_builder_delete(builder: *t.sk_textblob_builder_t) void;
pub extern "c" fn sk_textblob_builder_make(builder: *t.sk_textblob_builder_t) ?*t.sk_textblob_t;
pub extern "c" fn sk_textblob_builder_alloc_run_pos_h(builder: *t.sk_textblob_builder_t, font: *const t.sk_font_t, count: c_int, y: f32, bounds: ?*const t.sk_rect_t, runbuffer: *t.sk_textblob_builder_runbuffer_t) void;

pub extern "c" fn sk_typeface_unref(typeface: *t.sk_typeface_t) void;
pub extern "c" fn sk_typeface_create_empty() ?*t.sk_typeface_t;
pub extern "c" fn sk_typeface_unichar_to_glyph(typeface: *const t.sk_typeface_t, unichar: i32) u16;
pub extern "c" fn sk_typeface_get_family_name(typeface: *const t.sk_typeface_t) ?*t.sk_string_t;
pub extern "c" fn sk_typeface_get_units_per_em(typeface: *const t.sk_typeface_t) c_int;

pub extern "c" fn sk_fontmgr_create_default() ?*t.sk_fontmgr_t;
pub extern "c" fn sk_fontmgr_unref(fontmgr: *t.sk_fontmgr_t) void;
pub extern "c" fn sk_fontmgr_count_families(fontmgr: *t.sk_fontmgr_t) c_int;
pub extern "c" fn sk_fontmgr_match_family_style(fontmgr: *t.sk_fontmgr_t, familyName: ?[*:0]const u8, style: *t.sk_fontstyle_t) ?*t.sk_typeface_t;
pub extern "c" fn sk_fontmgr_match_family_style_character(fontmgr: *t.sk_fontmgr_t, familyName: ?[*:0]const u8, style: *t.sk_fontstyle_t, bcp47: ?[*]const [*:0]const u8, bcp47Count: c_int, character: i32) ?*t.sk_typeface_t;
pub extern "c" fn sk_fontmgr_create_from_data(fontmgr: *t.sk_fontmgr_t, data: *t.sk_data_t, index: c_int) ?*t.sk_typeface_t;
pub extern "c" fn sk_fontmgr_create_from_file(fontmgr: *t.sk_fontmgr_t, path: [*:0]const u8, index: c_int) ?*t.sk_typeface_t;

pub extern "c" fn sk_fontstyle_new(weight: c_int, width: c_int, slant: t.sk_font_style_slant_t) ?*t.sk_fontstyle_t;
pub extern "c" fn sk_fontstyle_delete(fs: *t.sk_fontstyle_t) void;
