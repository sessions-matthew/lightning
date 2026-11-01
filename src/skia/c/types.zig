//! SkiaSharp C API opaque handles, structs, enums, and callback types (from `sk_types.h`).

pub const sk_refcnt_t = opaque {};
pub const sk_nvrefcnt_t = opaque {};
pub const sk_flattenable_t = opaque {};
pub const sk_surfaceprops_t = opaque {};
pub const sk_canvas_t = opaque {};
pub const sk_nodraw_canvas_t = opaque {};
pub const sk_nway_canvas_t = opaque {};
pub const sk_overdraw_canvas_t = opaque {};
pub const sk_data_t = opaque {};
pub const sk_drawable_t = opaque {};
pub const sk_image_t = opaque {};
pub const sk_maskfilter_t = opaque {};
pub const sk_paint_t = opaque {};
pub const sk_font_t = opaque {};
pub const sk_path_t = opaque {};
pub const sk_pathbuilder_t = opaque {};
pub const sk_picture_t = opaque {};
pub const sk_picture_recorder_t = opaque {};
pub const sk_bbh_factory_t = opaque {};
pub const sk_rtree_factory_t = opaque {};
pub const sk_shader_t = opaque {};
pub const sk_surface_t = opaque {};
pub const sk_region_t = opaque {};
pub const sk_region_iterator_t = opaque {};
pub const sk_region_cliperator_t = opaque {};
pub const sk_region_spanerator_t = opaque {};
pub const sk_string_t = opaque {};
pub const sk_bitmap_t = opaque {};
pub const sk_pixmap_t = opaque {};
pub const sk_colorfilter_t = opaque {};
pub const sk_imagefilter_t = opaque {};
pub const sk_blender_t = opaque {};
pub const sk_typeface_t = opaque {};
pub const sk_fontmgr_t = opaque {};
pub const sk_fontstyle_t = opaque {};
pub const sk_fontstyleset_t = opaque {};
pub const sk_codec_t = opaque {};
pub const sk_colorspace_t = opaque {};
pub const sk_stream_t = opaque {};
pub const sk_stream_filestream_t = opaque {};
pub const sk_stream_asset_t = opaque {};
pub const sk_stream_memorystream_t = opaque {};
pub const sk_stream_streamrewindable_t = opaque {};
pub const sk_wstream_t = opaque {};
pub const sk_wstream_filestream_t = opaque {};
pub const sk_wstream_dynamicmemorystream_t = opaque {};
pub const sk_document_t = opaque {};
pub const sk_path_iterator_t = opaque {};
pub const sk_path_rawiterator_t = opaque {};
pub const sk_path_effect_t = opaque {};
pub const sk_opbuilder_t = opaque {};
pub const sk_pathmeasure_t = opaque {};
pub const sk_rrect_t = opaque {};
pub const sk_textblob_t = opaque {};
pub const sk_textblob_builder_t = opaque {};
pub const sk_runtimeeffect_t = opaque {};
pub const sk_vertices_t = opaque {};
pub const gr_direct_context_t = opaque {};
pub const gr_recording_context_t = opaque {};
pub const gr_backendrendertarget_t = opaque {};
pub const gr_backendtexture_t = opaque {};
pub const gr_glinterface_t = opaque {};

pub const sk_color_t = u32;
pub const sk_pmcolor_t = u32;
pub const sk_font_table_tag_t = u32;
pub const gr_mtl_handle_t = ?*const anyopaque;

pub const sk_color4f_t = extern struct {
    fR: f32,
    fG: f32,
    fB: f32,
    fA: f32,
};

pub const sk_point_t = extern struct {
    x: f32,
    y: f32,
};

pub const sk_vector_t = sk_point_t;

pub const sk_point3_t = extern struct {
    x: f32,
    y: f32,
    z: f32,
};

pub const sk_ipoint_t = extern struct {
    x: i32,
    y: i32,
};

pub const sk_size_t = extern struct {
    w: f32,
    h: f32,
};

pub const sk_isize_t = extern struct {
    w: i32,
    h: i32,
};

pub const sk_irect_t = extern struct {
    left: i32,
    top: i32,
    right: i32,
    bottom: i32,
};

pub const sk_rect_t = extern struct {
    left: f32,
    top: f32,
    right: f32,
    bottom: f32,
};

pub const sk_matrix_t = extern struct {
    scaleX: f32,
    skewX: f32,
    transX: f32,
    skewY: f32,
    scaleY: f32,
    transY: f32,
    persp0: f32,
    persp1: f32,
    persp2: f32,
};

pub const sk_matrix44_t = extern struct {
    m00: f32,
    m01: f32,
    m02: f32,
    m03: f32,
    m10: f32,
    m11: f32,
    m12: f32,
    m13: f32,
    m20: f32,
    m21: f32,
    m22: f32,
    m23: f32,
    m30: f32,
    m31: f32,
    m32: f32,
    m33: f32,
};

pub const sk_imageinfo_t = extern struct {
    colorspace: ?*sk_colorspace_t = null,
    width: i32,
    height: i32,
    colorType: sk_colortype_t,
    alphaType: sk_alphatype_t,
};

pub const sk_cubic_resampler_t = extern struct {
    fB: f32 = 0,
    fC: f32 = 0,
};

pub const sk_sampling_options_t = extern struct {
    fMaxAniso: c_int = 0,
    fUseCubic: bool = false,
    fCubic: sk_cubic_resampler_t = .{},
    fFilter: sk_filter_mode_t = .nearest,
    fMipmap: sk_mipmap_mode_t = .none,
};

pub const sk_fontmetrics_t = extern struct {
    fFlags: u32,
    fTop: f32,
    fAscent: f32,
    fDescent: f32,
    fBottom: f32,
    fLeading: f32,
    fAvgCharWidth: f32,
    fMaxCharWidth: f32,
    fXMin: f32,
    fXMax: f32,
    fXHeight: f32,
    fCapHeight: f32,
    fUnderlineThickness: f32,
    fUnderlinePosition: f32,
    fStrikeoutThickness: f32,
    fStrikeoutPosition: f32,
};

pub const sk_pngencoder_options_t = extern struct {
    fFilterFlags: sk_pngencoder_filterflags_t = .all,
    fZLibLevel: c_int = 6,
    fComments: ?*anyopaque = null,
    fGainmap: ?*const anyopaque = null,
    fGainmapInfo: ?*const anyopaque = null,
};

pub const sk_jpegencoder_options_t = extern struct {
    fQuality: c_int = 100,
    fDownsample: sk_jpegencoder_downsample_t = .downsample_420,
    fAlphaOption: sk_jpegencoder_alphaoption_t = .ignore,
    xmpMetadata: ?*const sk_data_t = null,
    fOrigin: i32 = 1,
    fHasOrigin: bool = false,
};

pub const sk_webpencoder_options_t = extern struct {
    fCompression: sk_webpencoder_compression_t = .lossy,
    fQuality: f32 = 100.0,
};

pub const sk_canvas_savelayerrec_t = extern struct {
    fBounds: ?*const sk_rect_t = null,
    fPaint: ?*const sk_paint_t = null,
    fBackdrop: ?*const sk_imagefilter_t = null,
    fFlags: u32 = 0,
};

pub const sk_textblob_builder_runbuffer_t = extern struct {
    glyphs: ?[*]u16 = null,
    pos: ?[*]f32 = null,
    utf8text: ?[*]u8 = null,
    clusters: ?[*]u32 = null,
};

pub const sk_colortype_t = enum(c_int) {
    unknown = 0,
    alpha_8,
    rgb_565,
    argb_4444,
    rgba_8888,
    rgb_888x,
    bgra_8888,
    rgba_1010102,
    bgra_1010102,
    rgb_101010x,
    bgr_101010x,
    bgr_101010x_xr,
    bgra_10101010_xr,
    rgba_10x6,
    gray_8,
    rgba_f16_norm,
    rgba_f16,
    rgb_f16f16f16x,
    rgba_f32,
    r8g8_unorm,
    a16_float,
    r16_float,
    r16g16_float,
    a16_unorm,
    r16_unorm,
    r16g16_unorm,
    r16g16b16a16_unorm,
    srgba_8888,
    r8_unorm,
};

pub const sk_alphatype_t = enum(c_int) {
    unknown = 0,
    @"opaque",
    premul,
    unpremul,
};

pub const sk_pixelgeometry_t = enum(c_int) {
    unknown = 0,
    rgb_h,
    bgr_h,
    rgb_v,
    bgr_v,
};

pub const sk_blendmode_t = enum(c_int) {
    clear = 0,
    src,
    dst,
    src_over,
    dst_over,
    src_in,
    dst_in,
    src_out,
    dst_out,
    src_atop,
    dst_atop,
    @"xor",
    plus,
    modulate,
    screen,
    overlay,
    darken,
    lighten,
    color_dodge,
    color_burn,
    hard_light,
    soft_light,
    difference,
    exclusion,
    multiply,
    hue,
    saturation,
    color,
    luminosity,
};

pub const sk_point_mode_t = enum(c_int) {
    points = 0,
    lines,
    polygon,
};

pub const sk_text_align_t = enum(c_int) {
    left = 0,
    center,
    right,
};

pub const sk_text_encoding_t = enum(c_int) {
    utf8 = 0,
    utf16,
    utf32,
    glyph_id,
};

pub const sk_path_filltype_t = enum(c_int) {
    winding = 0,
    even_odd,
    inverse_winding,
    inverse_even_odd,
};

pub const sk_font_style_slant_t = enum(c_int) {
    upright = 0,
    italic = 1,
    oblique = 2,
};

pub const sk_clipop_t = enum(c_int) {
    difference = 0,
    intersect = 1,
};

pub const sk_stroke_cap_t = enum(c_int) {
    butt = 0,
    round,
    square,
};

pub const sk_stroke_join_t = enum(c_int) {
    miter = 0,
    round,
    bevel,
};

pub const sk_shader_tilemode_t = enum(c_int) {
    clamp = 0,
    repeat,
    mirror,
    decal,
};

pub const sk_blurstyle_t = enum(c_int) {
    normal = 0,
    solid,
    outer,
    inner,
};

pub const sk_path_direction_t = enum(c_int) {
    cw = 0,
    ccw,
};

pub const sk_path_arc_size_t = enum(c_int) {
    small = 0,
    large,
};

pub const sk_paint_style_t = enum(c_int) {
    fill = 0,
    stroke,
    stroke_and_fill,
};

pub const sk_font_hinting_t = enum(c_int) {
    none = 0,
    slight,
    normal,
    full,
};

pub const sk_font_edging_t = enum(c_int) {
    alias = 0,
    antialias,
    subpixel_antialias,
};

pub const sk_filter_mode_t = enum(c_int) {
    nearest = 0,
    linear,
};

pub const sk_mipmap_mode_t = enum(c_int) {
    none = 0,
    nearest,
    linear,
};

pub const sk_path_add_mode_t = enum(c_int) {
    append = 0,
    extend,
};

pub const sk_pathop_t = enum(c_int) {
    difference = 0,
    intersect,
    @"union",
    @"xor",
    reverse_difference,
};

pub const sk_pngencoder_filterflags_t = enum(c_int) {
    zero = 0x00,
    none = 0x08,
    sub = 0x10,
    up = 0x20,
    avg = 0x40,
    paeth = 0x80,
    all = 0x08 | 0x10 | 0x20 | 0x40 | 0x80,
};

pub const sk_jpegencoder_downsample_t = enum(c_int) {
    downsample_420 = 0,
    downsample_422,
    downsample_444,
};

pub const sk_jpegencoder_alphaoption_t = enum(c_int) {
    ignore = 0,
    blend_on_black,
};

pub const sk_webpencoder_compression_t = enum(c_int) {
    lossy = 0,
    lossless,
};

pub const sk_rrect_type_t = enum(c_int) {
    empty = 0,
    rect,
    oval,
    simple,
    nine_patch,
    complex,
};

pub const sk_rrect_corner_t = enum(c_int) {
    upper_left = 0,
    upper_right,
    lower_right,
    lower_left,
};

pub const sk_image_caching_hint_t = enum(c_int) {
    allow = 0,
    disallow,
};

pub const gr_surfaceorigin_t = enum(c_int) {
    top_left = 0,
    bottom_left = 1,
};

pub const sk_surface_raster_release_proc = ?*const fn (addr: ?*anyopaque, context: ?*anyopaque) callconv(.c) void;
pub const sk_data_release_proc = ?*const fn (ptr: ?*const anyopaque, context: ?*anyopaque) callconv(.c) void;
pub const sk_image_raster_release_proc = ?*const fn (addr: ?*const anyopaque, context: ?*anyopaque) callconv(.c) void;
