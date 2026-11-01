//! Idiomatic wrappers for `Font`, `TextBlob`, `Typeface`, and `FontMgr` with
//! automatic multi-font Unicode & Color Emoji fallback (`Apple Color Emoji`, `Apple Symbols`,
//! `Menlo`, `PingFang SC`, and system character matching via `SkFontMgr`).

const std = @import("std");
const c = @import("c/root.zig");
const root = @import("root.zig");
const Error = root.Error;

pub const FontEdging = c.sk_font_edging_t;
pub const FontHinting = c.sk_font_hinting_t;
pub const FontSlant = c.sk_font_style_slant_t;

/// Process-wide lazily initialized fallback typeface bank for Emoji & Unicode symbols.
const FallbackFontBank = struct {
    initialized: bool = false,
    font_mgr: ?*c.sk_fontmgr_t = null,
    style_normal: ?*c.sk_fontstyle_t = null,
    emoji_tf: ?*c.sk_typeface_t = null,
    symbols_tf: ?*c.sk_typeface_t = null,
    menlo_tf: ?*c.sk_typeface_t = null,
    cjk_tf: ?*c.sk_typeface_t = null,
    dynamic_tfs: [16]*c.sk_typeface_t = undefined,
    dynamic_len: usize = 0,

    fn ensureInit(self: *FallbackFontBank) void {
        if (self.initialized) return;
        self.initialized = true;

        const mgr = c.sk_fontmgr_create_default() orelse return;
        self.font_mgr = mgr;
        const style = c.sk_fontstyle_new(400, 5, .upright) orelse return;
        self.style_normal = style;

        self.emoji_tf = c.sk_fontmgr_match_family_style(mgr, "Apple Color Emoji", style) orelse
            c.sk_fontmgr_match_family_style(mgr, "Segoe UI Emoji", style) orelse
            c.sk_fontmgr_match_family_style(mgr, "Noto Color Emoji", style);
        self.symbols_tf = c.sk_fontmgr_match_family_style(mgr, "Apple Symbols", style) orelse
            c.sk_fontmgr_match_family_style(mgr, "Segoe UI Symbol", style) orelse
            c.sk_fontmgr_match_family_style(mgr, "Noto Sans Symbols", style) orelse
            c.sk_fontmgr_match_family_style(mgr, "DejaVu Sans", style);
        self.menlo_tf = c.sk_fontmgr_match_family_style(mgr, "Menlo", style) orelse
            c.sk_fontmgr_match_family_style(mgr, "Cascadia Mono", style) orelse
            c.sk_fontmgr_match_family_style(mgr, "Consolas", style) orelse
            c.sk_fontmgr_match_family_style(mgr, "DejaVu Sans Mono", style);
        self.cjk_tf = c.sk_fontmgr_match_family_style(mgr, "PingFang SC", style) orelse
            c.sk_fontmgr_match_family_style(mgr, "Microsoft YaHei", style) orelse
            c.sk_fontmgr_match_family_style(mgr, "Noto Sans CJK SC", style);

        if (self.symbols_tf == null) {
            const sym_paths = [_][:0]const u8{
                "/usr/share/fonts/TTF/SymbolsNerdFont-Regular.ttf",
                "/usr/share/fonts/TTF/DejaVuSans.ttf",
                "/usr/share/fonts/liberation/LiberationSans-Regular.ttf",
                "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
            };
            for (sym_paths) |p| {
                if (c.sk_fontmgr_create_from_file(mgr, p.ptr, 0)) |tf| {
                    self.symbols_tf = tf;
                    break;
                }
            }
        }
        if (self.menlo_tf == null) {
            const mono_paths = [_][:0]const u8{
                "/usr/share/fonts/TTF/DejaVuSansMono.ttf",
                "/usr/share/fonts/liberation/LiberationMono-Regular.ttf",
                "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
                "/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf",
            };
            for (mono_paths) |p| {
                if (c.sk_fontmgr_create_from_file(mgr, p.ptr, 0)) |tf| {
                    self.menlo_tf = tf;
                    break;
                }
            }
        }
    }

    fn resolveGlyph(
        self: *FallbackFontBank,
        primary_font: *c.sk_font_t,
        cp: u21,
        prefer_emoji: bool,
    ) struct { glyph: u16, tf: ?*c.sk_typeface_t } {
        self.ensureInit();
        const uni: i32 = @intCast(cp);

        // 1. If emoji presentation is requested (or supplementary emoji block), try Apple Color Emoji first
        if (prefer_emoji) {
            if (self.emoji_tf) |etf| {
                const g = c.sk_typeface_unichar_to_glyph(etf, uni);
                if (g != 0) return .{ .glyph = g, .tf = etf };
            }
        }

        // 2. Try caller's primary font
        const primary_g = c.sk_font_unichar_to_glyph(primary_font, uni);
        if (primary_g != 0) {
            return .{ .glyph = primary_g, .tf = null };
        }

        // 3. Try cached primary fallback typefaces (Symbols, Menlo, Emoji, CJK)
        const static_fallbacks = [_]?*c.sk_typeface_t{
            self.symbols_tf,
            self.menlo_tf,
            self.emoji_tf,
            self.cjk_tf,
        };
        for (static_fallbacks) |maybe_tf| {
            if (maybe_tf) |tf| {
                const g = c.sk_typeface_unichar_to_glyph(tf, uni);
                if (g != 0) return .{ .glyph = g, .tf = tf };
            }
        }

        // 4. Try previously discovered dynamic system fallback typefaces
        for (self.dynamic_tfs[0..self.dynamic_len]) |dtf| {
            const g = c.sk_typeface_unichar_to_glyph(dtf, uni);
            if (g != 0) return .{ .glyph = g, .tf = dtf };
        }

        // 5. Query OS FontMgr for a typeface covering this specific Unicode codepoint
        if (self.font_mgr) |mgr| {
            if (self.style_normal) |style| {
                if (c.sk_fontmgr_match_family_style_character(mgr, null, style, null, 0, uni)) |matched_tf| {
                    const g = c.sk_typeface_unichar_to_glyph(matched_tf, uni);
                    if (self.dynamic_len < self.dynamic_tfs.len) {
                        self.dynamic_tfs[self.dynamic_len] = matched_tf;
                        self.dynamic_len += 1;
                    }
                    if (g != 0) return .{ .glyph = g, .tf = matched_tf };
                }
            }
        }

        return .{ .glyph = 0, .tf = null };
    }
};

var g_fallback_bank: FallbackFontBank = .{};

fn isColorEmojiCodepoint(cp: u21) bool {
    return (cp >= 0x1F000 and cp <= 0x1FAFF) or
        (cp >= 0x1F300 and cp <= 0x1F9FF) or
        cp == 0x2705 or // ✅
        cp == 0x2728 or // ✨
        cp == 0x274C or // ❌
        cp == 0x274E or // ❎
        cp == 0x26A1 or // ⚡
        cp == 0x26A0 or // ⚠
        (cp >= 0x23E9 and cp <= 0x23FA);
}

fn isIgnorableFormatCodepoint(cp: u21) bool {
    return cp == 0xFE0E or cp == 0xFE0F or cp == 0x200D or cp == 0x200B;
}

/// Decodes one UTF-8 codepoint starting at `text[idx]`, advancing `idx.*`.
/// Gracefully handles malformed UTF-8 bytes by returning `U+FFFD` and advancing by 1 byte.
pub fn decodeUtf8Next(text: []const u8, idx: *usize) u21 {
    if (idx.* >= text.len) return 0;
    const b0 = text[idx.*];
    if (b0 < 0x80) {
        idx.* += 1;
        return b0;
    }
    const seq_len = std.unicode.utf8ByteSequenceLength(b0) catch {
        idx.* += 1;
        return 0xFFFD;
    };
    if (idx.* + seq_len > text.len) {
        idx.* += 1;
        return 0xFFFD;
    }
    const cp = std.unicode.utf8Decode(text[idx.* .. idx.* + seq_len]) catch {
        idx.* += 1;
        return 0xFFFD;
    };
    idx.* += seq_len;
    return cp;
}

pub const Font = struct {
    ptr: *c.sk_font_t,

    pub fn init(typeface: ?Typeface, size: f32) Error!Font {
        const tf_ptr = if (typeface) |tf| tf.ptr else null;
        const ptr = c.sk_font_new_with_values(tf_ptr, size, 1.0, 0.0) orelse return Error.OutOfMemory;
        c.sk_font_set_embedded_bitmaps(ptr, true);
        return .{ .ptr = ptr };
    }

    pub fn deinit(self: Font) void {
        c.sk_font_delete(self.ptr);
    }

    pub fn setEdging(self: Font, edging: FontEdging) void {
        c.sk_font_set_edging(self.ptr, edging);
    }

    pub fn setSubpixel(self: Font, subpixel: bool) void {
        c.sk_font_set_subpixel(self.ptr, subpixel);
    }

    pub fn getSize(self: Font) f32 {
        return c.sk_font_get_size(self.ptr);
    }

    pub fn measureText(self: Font, text: []const u8) f32 {
        if (text.len == 0) return 0;
        if (TextBlob.shapeUtf8(text, self, false)) |res| {
            return res.width;
        } else |_| {
            return c.sk_font_measure_text(self.ptr, text.ptr, text.len, .utf8, null, null);
        }
    }

    pub fn getMetrics(self: Font) c.sk_fontmetrics_t {
        var m: c.sk_fontmetrics_t = undefined;
        _ = c.sk_font_get_metrics(self.ptr, &m);
        return m;
    }
};

pub const ShapedText = struct {
    blob: ?TextBlob,
    width: f32,
};

pub const TextBlob = struct {
    ptr: *c.sk_textblob_t,

    pub fn initFromUtf8(text: []const u8, font: Font) Error!TextBlob {
        const shaped = try shapeUtf8(text, font, true);
        return shaped.blob orelse Error.InvalidOperation;
    }

    pub fn initFromUtf8WithWidth(text: []const u8, font: Font) Error!ShapedText {
        return shapeUtf8(text, font, true);
    }

    /// Shapes UTF-8 `text` into positioned glyph runs with automatic fallback to `Apple Color Emoji`
    /// and system Unicode fonts whenever the primary `font` lacks a glyph (`glyph == 0`) or encounters
    /// color emoji codepoints. Returns both the `TextBlob` (when `build_blob` is true) and exact advance width.
    pub fn shapeUtf8(text: []const u8, font: Font, build_blob: bool) Error!ShapedText {
        if (text.len == 0) return Error.InvalidOperation;

        // Fast path check: pure ASCII or single-font UTF-8 text with no missing glyphs and no emoji selectors
        var has_emoji_or_format = false;
        var scan_idx: usize = 0;
        while (scan_idx < text.len) {
            if (text[scan_idx] < 0x80) {
                scan_idx += 1;
                continue;
            }
            const cp = decodeUtf8Next(text, &scan_idx);
            if (cp == 0xFFFD or isIgnorableFormatCodepoint(cp) or isColorEmojiCodepoint(cp) or (cp >= 0x1F3FB and cp <= 0x1F3FF)) {
                has_emoji_or_format = true;
                break;
            }
        }

        var glyphs_buf: [512]u16 = undefined;
        var xpos_buf: [512]f32 = undefined;

        if (!has_emoji_or_format and text.len <= glyphs_buf.len) {
            const count = c.sk_font_text_to_glyphs(
                font.ptr,
                text.ptr,
                text.len,
                .utf8,
                &glyphs_buf,
                glyphs_buf.len,
            );
            if (count > 0) {
                const glyph_count: usize = @intCast(@min(count, @as(c_int, glyphs_buf.len)));
                var all_present = true;
                for (glyphs_buf[0..glyph_count]) |g| {
                    if (g == 0) {
                        all_present = false;
                        break;
                    }
                }
                if (all_present) {
                    const w = c.sk_font_measure_text(font.ptr, text.ptr, text.len, .utf8, null, null);
                    if (!build_blob) {
                        return .{ .blob = null, .width = w };
                    }
                    c.sk_font_get_xpos(font.ptr, &glyphs_buf, @intCast(glyph_count), &xpos_buf, 0.0);
                    const builder = c.sk_textblob_builder_new() orelse return Error.OutOfMemory;
                    defer c.sk_textblob_builder_delete(builder);

                    var runbuf: c.sk_textblob_builder_runbuffer_t = .{};
                    c.sk_textblob_builder_alloc_run_pos_h(builder, font.ptr, @intCast(glyph_count), 0.0, null, &runbuf);
                    if (runbuf.glyphs) |g_dst| {
                        @memcpy(g_dst[0..glyph_count], glyphs_buf[0..glyph_count]);
                    }
                    if (runbuf.pos) |p_dst| {
                        @memcpy(p_dst[0..glyph_count], xpos_buf[0..glyph_count]);
                    }
                    const blob = c.sk_textblob_builder_make(builder) orelse return Error.OutOfMemory;
                    return .{ .blob = .{ .ptr = blob }, .width = w };
                }
            }
        }

        // Multi-font Unicode & Emoji fallback shaping path
        var run_tfs: [512]?*c.sk_typeface_t = undefined;
        var out_len: usize = 0;
        var cur_x: f32 = 0.0;
        const font_size = c.sk_font_get_size(font.ptr);

        var idx: usize = 0;
        while (idx < text.len and out_len < glyphs_buf.len) {
            const cp = decodeUtf8Next(text, &idx);
            if (isIgnorableFormatCodepoint(cp)) continue;

            // Peek ahead for Variation Selector-16 (`U+FE0F`) or skin-tone / ZWJ modifiers
            var prefer_emoji = isColorEmojiCodepoint(cp);
            var peek_idx = idx;
            while (peek_idx < text.len) {
                const next_cp = decodeUtf8Next(text, &peek_idx);
                if (next_cp == 0xFE0F) {
                    prefer_emoji = true;
                    idx = peek_idx;
                } else if (next_cp == 0xFE0E or (next_cp >= 0x1F3FB and next_cp <= 0x1F3FF)) {
                    // Consume variation selector or skin-tone modifier attached to base emoji
                    if (next_cp >= 0x1F3FB and next_cp <= 0x1F3FF) prefer_emoji = true;
                    idx = peek_idx;
                } else {
                    break;
                }
            }

            const resolved = g_fallback_bank.resolveGlyph(font.ptr, cp, prefer_emoji);
            const g: u16 = resolved.glyph;

            var advance: f32 = font_size * 0.6;
            if (resolved.tf) |fb_tf| {
                if (c.sk_font_new_with_values(fb_tf, font_size, 1.0, 0.0)) |fb_font| {
                    defer c.sk_font_delete(fb_font);
                    c.sk_font_set_embedded_bitmaps(fb_font, true);
                    var g_arr = [1]u16{g};
                    var w_arr = [1]f32{0.0};
                    c.sk_font_get_widths_bounds(fb_font, &g_arr, 1, &w_arr, null, null);
                    if (w_arr[0] > 0.0) advance = w_arr[0];
                }
            } else if (g != 0) {
                var g_arr = [1]u16{g};
                var w_arr = [1]f32{0.0};
                c.sk_font_get_widths_bounds(font.ptr, &g_arr, 1, &w_arr, null, null);
                if (w_arr[0] > 0.0) advance = w_arr[0];
            }

            glyphs_buf[out_len] = g;
            xpos_buf[out_len] = cur_x;
            run_tfs[out_len] = resolved.tf;
            out_len += 1;
            cur_x += advance;
        }

        if (out_len == 0) return Error.InvalidOperation;
        if (!build_blob) {
            return .{ .blob = null, .width = cur_x };
        }

        const builder = c.sk_textblob_builder_new() orelse return Error.OutOfMemory;
        defer c.sk_textblob_builder_delete(builder);

        var run_start: usize = 0;
        while (run_start < out_len) {
            const tf = run_tfs[run_start];
            var run_end = run_start + 1;
            while (run_end < out_len and run_tfs[run_end] == tf) : (run_end += 1) {}
            const run_count = run_end - run_start;

            if (tf) |fb_tf| {
                const fb_font = c.sk_font_new_with_values(fb_tf, font_size, 1.0, 0.0) orelse return Error.OutOfMemory;
                defer c.sk_font_delete(fb_font);
                c.sk_font_set_edging(fb_font, .antialias);
                c.sk_font_set_subpixel(fb_font, true);
                c.sk_font_set_embedded_bitmaps(fb_font, true);

                var runbuf: c.sk_textblob_builder_runbuffer_t = .{};
                c.sk_textblob_builder_alloc_run_pos_h(builder, fb_font, @intCast(run_count), 0.0, null, &runbuf);
                if (runbuf.glyphs) |g_dst| {
                    @memcpy(g_dst[0..run_count], glyphs_buf[run_start..run_end]);
                }
                if (runbuf.pos) |p_dst| {
                    @memcpy(p_dst[0..run_count], xpos_buf[run_start..run_end]);
                }
            } else {
                var runbuf: c.sk_textblob_builder_runbuffer_t = .{};
                c.sk_textblob_builder_alloc_run_pos_h(builder, font.ptr, @intCast(run_count), 0.0, null, &runbuf);
                if (runbuf.glyphs) |g_dst| {
                    @memcpy(g_dst[0..run_count], glyphs_buf[run_start..run_end]);
                }
                if (runbuf.pos) |p_dst| {
                    @memcpy(p_dst[0..run_count], xpos_buf[run_start..run_end]);
                }
            }

            run_start = run_end;
        }

        const blob = c.sk_textblob_builder_make(builder) orelse return Error.OutOfMemory;
        return .{ .blob = .{ .ptr = blob }, .width = cur_x };
    }

    pub fn deinit(self: TextBlob) void {
        c.sk_textblob_unref(self.ptr);
    }
};

pub const Typeface = struct {
    ptr: *c.sk_typeface_t,

    pub fn deinit(self: Typeface) void {
        c.sk_typeface_unref(self.ptr);
    }
};

pub const FontMgr = struct {
    ptr: *c.sk_fontmgr_t,

    pub fn initDefault() Error!FontMgr {
        const ptr = c.sk_fontmgr_create_default() orelse return Error.OutOfMemory;
        return .{ .ptr = ptr };
    }

    pub fn deinit(self: FontMgr) void {
        c.sk_fontmgr_unref(self.ptr);
    }

    pub fn matchFamilyStyle(self: FontMgr, family_name: ?[:0]const u8, weight: i32, width: i32, slant: FontSlant) Error!?Typeface {
        const style = c.sk_fontstyle_new(weight, width, slant) orelse return Error.OutOfMemory;
        defer c.sk_fontstyle_delete(style);

        const fam_ptr: ?[*:0]const u8 = if (family_name) |f| f.ptr else null;
        if (c.sk_fontmgr_match_family_style(self.ptr, fam_ptr, style)) |tf_ptr| {
            return .{ .ptr = tf_ptr };
        }
        return null;
    }

    pub fn createFromFile(self: FontMgr, path: [:0]const u8) ?Typeface {
        if (c.sk_fontmgr_create_from_file(self.ptr, path.ptr, 0)) |tf_ptr| {
            return .{ .ptr = tf_ptr };
        }
        return null;
    }
};
