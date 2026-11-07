//! Interactive Two-Phase Image & Vector Viewer (`src/ui/image_viewer.zig`).
//!
//! Features:
//!   - **Multi-Format Image Decoder & 8-Slot LRU `skia.Image` Cache**:
//!     - Native Skia codec decoding for `.png`, `.jpg`/`.jpeg`, `.webp`, `.gif`, `.bmp`, `.ico`, `.wbmp`.
//!     - Built-in Netpbm (`P1`–`P6` `.pbm`, `.pgm`, `.ppm`) ASCII & binary raster decoder.
//!     - Built-in lightweight `.svg` vector rasterizer (`<svg>`, `<path d="...">` via `skia.Path.parseSvg`,
//!       `<rect>`, `<circle>`, `<line>`, `<polyline>`, `<polygon>`).
//!     - 8-slot LRU texture cache keyed by path + file mtime/size + byte hash (`O(1)` in `Pass.paint`).
//!   - **Interactive Two-Phase (`Pass.input` / `Pass.paint`) Workbench Viewer (`renderImageViewer`)**:
//!     - Top toolbar: format badge, `W × H px` dimensions, file size, `Fit`, `1:1`, `-` / `Zoom %` / `+`,
//!       `Checker` / `Dark` / `Light` backdrop modes, `Smooth` / `Pixel` sampling filter, and `90°` rotation.
//!     - Live **Pixel Eyedropper Inspector**: hovering over any pixel displays its `(X, Y)` image coordinate,
//!       live color swatch, and `#RRGGBB` hex value (clicking copies the hex color to clipboard).
//!     - Smooth 2D axis-snapped trackpad scrolling, click-and-drag panning, and pixel grid at high zoom.

const std = @import("std");
const skia = @import("skia");
const platform = @import("platform");
const root = @import("root.zig");
const c = skia.c;
const Color = skia.Color;
const Rect = skia.Rect;
const Font = skia.Font;
const Context = root.Context;

pub const ImageBackdrop = enum(u8) {
    checker = 0,
    dark = 1,
    light = 2,

    pub fn label(self: ImageBackdrop) []const u8 {
        return switch (self) {
            .checker => "Checker",
            .dark => "Dark",
            .light => "Light",
        };
    }

    pub fn next(self: ImageBackdrop) ImageBackdrop {
        return switch (self) {
            .checker => .dark,
            .dark => .light,
            .light => .checker,
        };
    }
};

pub const ImageViewState = struct {
    /// Zoom scale (`1.0 == 100%`). When `fit_to_view` is true, automatically computed to fit viewport.
    zoom: f32 = 1.0,
    fit_to_view: bool = true,
    pan_x: f32 = 0.0,
    pan_y: f32 = 0.0,
    dragging: bool = false,
    drag_last_x: f32 = 0.0,
    drag_last_y: f32 = 0.0,
    backdrop: ImageBackdrop = .checker,
    nearest_sampling: bool = false,
    quarter_turns: u2 = 0,
    hovered_px_x: i32 = -1,
    hovered_px_y: i32 = -1,
    hovered_color: u32 = 0,
    has_hovered_pixel: bool = false,
    copied_hex_buf: [16]u8 = @splat(0),
    copied_hex_len: u8 = 0,
    last_path_hash: u64 = 0,

    pub fn resetView(self: *ImageViewState) void {
        self.zoom = 1.0;
        self.fit_to_view = true;
        self.pan_x = 0.0;
        self.pan_y = 0.0;
        self.dragging = false;
        self.quarter_turns = 0;
    }
};

pub const ImageViewerOptions = struct {
    file_path: []const u8 = "",
    raw_bytes: []const u8 = "",
};

pub const ImageViewerResult = struct {
    width: i32 = 0,
    height: i32 = 0,
    file_bytes: usize = 0,
    zoom_percent: u32 = 100,
    copied_color_hex: ?[]const u8 = null,
};

pub const SAMPLE_SVG_IMAGE: []const u8 =
    \\<svg width="320" height="200" viewBox="0 0 320 200">
    \\  <rect x="8" y="8" width="304" height="184" rx="12" fill="#141B26" stroke="#38BDF8" stroke-width="2"/>
    \\  <circle cx="84" cy="100" r="46" fill="#0EA5E9"/>
    \\  <circle cx="84" cy="100" r="22" fill="#0F172A"/>
    \\  <rect x="156" y="54" width="128" height="24" rx="6" fill="#22C55E"/>
    \\  <rect x="156" y="90" width="96" height="24" rx="6" fill="#F59E0B"/>
    \\  <rect x="156" y="126" width="112" height="24" rx="6" fill="#A855F7"/>
    \\</svg>
;

// ============================================================================
// 8-Slot LRU Decoded `skia.Image` Cache
// ============================================================================

const CacheSlots: usize = 8;

const CachedImageEntry = struct {
    key: u64 = 0,
    image: ?skia.Image = null,
    file_bytes: usize = 0,
    last_used: u64 = 0,
};

var g_image_cache: [CacheSlots]CachedImageEntry = @splat(.{});
var g_image_cache_clock: u64 = 1;

pub fn clearImageCache() void {
    for (&g_image_cache) |*slot| {
        if (slot.image) |img| img.deinit();
        slot.* = .{};
    }
}

pub fn isImagePath(path: []const u8) bool {
    if (path.len < 4) return false;
    const has_dot4 = (path[path.len - 4] == '.');
    const has_dot5 = (path.len >= 5 and path[path.len - 5] == '.');
    if (!has_dot4 and !has_dot5) return false;
    const exts = [_][]const u8{
        ".png",  ".jpg",  ".jpeg", ".gif",  ".webp", ".bmp",
        ".ico",  ".wbmp", ".svg",  ".ppm",  ".pgm",  ".pbm",
    };
    for (exts) |ext| {
        if (endsWithIgnoreCase(path, ext)) return true;
    }
    return false;
}

pub fn detectImageFormatBadge(path: []const u8, raw_bytes: []const u8) []const u8 {
    if (endsWithIgnoreCase(path, ".png") or std.mem.startsWith(u8, raw_bytes, "\x89PNG")) return "PNG";
    if (endsWithIgnoreCase(path, ".jpg") or endsWithIgnoreCase(path, ".jpeg") or std.mem.startsWith(u8, raw_bytes, "\xFF\xD8\xFF")) return "JPEG";
    if (endsWithIgnoreCase(path, ".webp") or (raw_bytes.len >= 12 and std.mem.eql(u8, raw_bytes[0..4], "RIFF") and std.mem.eql(u8, raw_bytes[8..12], "WEBP"))) return "WEBP";
    if (endsWithIgnoreCase(path, ".gif") or std.mem.startsWith(u8, raw_bytes, "GIF8")) return "GIF";
    if (endsWithIgnoreCase(path, ".bmp") or std.mem.startsWith(u8, raw_bytes, "BM")) return "BMP";
    if (endsWithIgnoreCase(path, ".ico")) return "ICO";
    if (endsWithIgnoreCase(path, ".svg") or std.mem.indexOf(u8, raw_bytes[0..@min(raw_bytes.len, 256)], "<svg") != null) return "SVG";
    if (endsWithIgnoreCase(path, ".ppm")) return "PPM";
    if (endsWithIgnoreCase(path, ".pgm")) return "PGM";
    if (endsWithIgnoreCase(path, ".pbm")) return "PBM";
    return "IMAGE";
}

fn endsWithIgnoreCase(haystack: []const u8, suffix: []const u8) bool {
    if (haystack.len < suffix.len) return false;
    return std.ascii.eqlIgnoreCase(haystack[haystack.len - suffix.len ..], suffix);
}

fn computeCacheKey(file_path: []const u8, raw_bytes: []const u8, disk_stat_out: *usize) u64 {
    var h = std.hash.Wyhash.init(0x71A6_E001_55AA_33CC);
    h.update(file_path);
    if (raw_bytes.len > 0) {
        var len_b: [8]u8 = undefined;
        std.mem.writeInt(u64, &len_b, raw_bytes.len, .little);
        h.update(&len_b);
        const head_n = @min(raw_bytes.len, 512);
        h.update(raw_bytes[0..head_n]);
        if (raw_bytes.len > 512) {
            h.update(raw_bytes[raw_bytes.len - 256 ..]);
        }
        disk_stat_out.* = raw_bytes.len;
    } else if (file_path.len > 0 and file_path.len < 500) {
        var path_z: [512:0]u8 = @splat(0);
        @memcpy(path_z[0..file_path.len], file_path);
        path_z[file_path.len] = 0;
        if (comptime @import("builtin").os.tag == .macos) {
            var st: std.c.Stat = undefined;
            if (std.c.stat(&path_z, &st) == 0) {
                const sz: usize = if (st.size > 0) @intCast(st.size) else 0;
                disk_stat_out.* = sz;
                const mt = st.mtime();
                const flags: u32 = if (@import("builtin").os.tag == .macos) st.flags else 0;
                var meta_b: [28]u8 = undefined;
                std.mem.writeInt(u64, meta_b[0..8], sz, .little);
                std.mem.writeInt(i64, meta_b[8..16], @intCast(mt.sec), .little);
                std.mem.writeInt(i64, meta_b[16..24], @intCast(mt.nsec), .little);
                std.mem.writeInt(u32, meta_b[24..28], flags, .little);
                h.update(&meta_b);
            }
        } else {
            if (platform.fs_util.regularFileSizeOnDisk(&path_z)) |sz| {
                disk_stat_out.* = sz;
                var meta_b: [16]u8 = @splat(0);
                std.mem.writeInt(u64, meta_b[0..8], sz, .little);
                if (platform.fs_util.fileMtimeNs(&path_z)) |mt_ns| {
                    std.mem.writeInt(i64, meta_b[8..16], @truncate(mt_ns), .little);
                }
                h.update(&meta_b);
            }
        }
    }
    return h.final() | 1;
}

pub const ImageDimensions = struct {
    width: u32 = 0,
    height: u32 = 0,
    file_bytes: usize = 0,
};

/// Decodes (or retrieves from the 8-slot LRU cache) an image from `file_path` or `raw_bytes`
/// and returns its pixel dimensions and byte size.
pub fn queryImageDimensions(file_path: []const u8, raw_bytes: []const u8) ?ImageDimensions {
    var file_bytes: usize = 0;
    const img = getOrDecodeImage(file_path, raw_bytes, &file_bytes) orelse return null;
    return .{
        .width = @intCast(@max(0, img.width())),
        .height = @intCast(@max(0, img.height())),
        .file_bytes = file_bytes,
    };
}

/// Renders an aspect-preserving thumbnail preview of `file_path` / `raw_bytes` inside `rect`
/// using the 8-slot LRU decoded `skia.Image` cache. Safe to call in `Pass.paint`.
pub fn drawImageThumbnail(
    uic: *Context,
    rect: c.sk_rect_t,
    file_path: []const u8,
    raw_bytes: []const u8,
    corner_radius: f32,
) bool {
    if (uic.pass != .paint or !uic.shouldPaint(rect)) return false;

    var file_bytes: usize = 0;
    const img = getOrDecodeImage(file_path, raw_bytes, &file_bytes) orelse return false;
    const iw = @max(1, img.width());
    const ih = @max(1, img.height());

    const save_cnt = uic.canvas.save();
    defer uic.canvas.restoreToCount(save_cnt);
    uic.canvas.clipRect(rect, .intersect, false);

    uic.paint.setStyle(.fill);
    uic.paint.setColor(Color.rgb(12, 16, 23));
    uic.canvas.drawRoundRect(rect, corner_radius, corner_radius, uic.paint);

    const avail_w = @max(4.0, (rect.right - rect.left) - 4.0);
    const avail_h = @max(4.0, (rect.bottom - rect.top) - 4.0);
    const scale_x = avail_w / @as(f32, @floatFromInt(iw));
    const scale_y = avail_h / @as(f32, @floatFromInt(ih));
    const scale = @min(scale_x, scale_y);
    const dst_w = @max(1.0, @as(f32, @floatFromInt(iw)) * scale);
    const dst_h = @max(1.0, @as(f32, @floatFromInt(ih)) * scale);
    const cx = (rect.left + rect.right) * 0.5;
    const cy = (rect.top + rect.bottom) * 0.5;
    const dst_rect = Rect.xywh(cx - dst_w * 0.5, cy - dst_h * 0.5, dst_w, dst_h);

    uic.canvas.drawImageRectSampling(img, dst_rect, false, null);

    uic.paint.setStyle(.stroke);
    uic.paint.setStrokeWidth(1.0);
    uic.paint.setColor(Color.argb(90, 148, 163, 184));
    uic.canvas.drawRoundRect(rect, corner_radius, corner_radius, uic.paint);
    uic.paint.setStyle(.fill);
    return true;
}

fn getOrDecodeImage(file_path: []const u8, raw_bytes: []const u8, file_bytes_out: *usize) ?skia.Image {
    var disk_size: usize = raw_bytes.len;
    const key = computeCacheKey(file_path, raw_bytes, &disk_size);

    g_image_cache_clock +%= 1;
    for (&g_image_cache) |*slot| {
        if (slot.key == key and slot.image != null) {
            slot.last_used = g_image_cache_clock;
            file_bytes_out.* = slot.file_bytes;
            return slot.image;
        }
    }

    const decoded = decodeImageFromSource(file_path, raw_bytes, &disk_size) orelse return null;
    file_bytes_out.* = disk_size;

    // Insert into LRU cache slot
    var victim_idx: usize = 0;
    var oldest_tick: u64 = std.math.maxInt(u64);
    for (g_image_cache, 0..) |slot, i| {
        if (slot.image == null) {
            victim_idx = i;
            break;
        }
        if (slot.last_used < oldest_tick) {
            oldest_tick = slot.last_used;
            victim_idx = i;
        }
    }

    if (g_image_cache[victim_idx].image) |old_img| {
        old_img.deinit();
    }
    g_image_cache[victim_idx] = .{
        .key = key,
        .image = decoded,
        .file_bytes = disk_size,
        .last_used = g_image_cache_clock,
    };
    return decoded;
}

fn decodeImageFromSource(file_path: []const u8, raw_bytes: []const u8, file_bytes_inout: *usize) ?skia.Image {
    // 1. If in-memory bytes are provided, decode directly from memory
    if (raw_bytes.len > 0) {
        file_bytes_inout.* = raw_bytes.len;
        if (decodeSpecialFormatBytes(file_path, raw_bytes)) |img| return img;
        if (skia.Image.initFromEncodedBytes(raw_bytes)) |img| return img else |_| {}
    }

    // 2. Load from disk file if `file_path` exists
    if (file_path.len > 0 and file_path.len < 500) {
        var path_z: [512:0]u8 = @splat(0);
        @memcpy(path_z[0..file_path.len], file_path);
        path_z[file_path.len] = 0;

        if (platform.fs_util.isDatalessFileOnDisk(&path_z)) {
            platform.fs_util.triggerAsyncICloudDownload(&path_z);
            return null;
        }

        if (endsWithIgnoreCase(file_path, ".svg") or
            endsWithIgnoreCase(file_path, ".ppm") or
            endsWithIgnoreCase(file_path, ".pgm") or
            endsWithIgnoreCase(file_path, ".pbm"))
        {
            if (skia.Data.initFromFile(&path_z)) |data| {
                defer data.deinit();
                const bytes = data.slice();
                file_bytes_inout.* = bytes.len;
                if (decodeSpecialFormatBytes(file_path, bytes)) |img| return img;
            } else |_| {}
        }

        if (skia.Image.initFromFile(&path_z)) |img| {
            return img;
        } else |_| {}

        if (skia.Data.initFromFile(&path_z)) |data| {
            defer data.deinit();
            const bytes = data.slice();
            file_bytes_inout.* = bytes.len;
            if (decodeSpecialFormatBytes(file_path, bytes)) |img| return img;
            if (skia.Image.initFromEncoded(data)) |img| return img else |_| {}
        } else |_| {}
    }

    return null;
}

fn decodeSpecialFormatBytes(file_path: []const u8, bytes: []const u8) ?skia.Image {
    if (bytes.len == 0) return null;
    if (endsWithIgnoreCase(file_path, ".ppm") or
        endsWithIgnoreCase(file_path, ".pgm") or
        endsWithIgnoreCase(file_path, ".pbm") or
        (bytes.len >= 3 and bytes[0] == 'P' and bytes[1] >= '1' and bytes[1] <= '6' and std.ascii.isWhitespace(bytes[2])))
    {
        if (decodeNetpbmImage(bytes)) |img| return img;
    }
    if (endsWithIgnoreCase(file_path, ".svg") or std.mem.indexOf(u8, bytes[0..@min(bytes.len, 512)], "<svg") != null) {
        if (rasterizeSvgBytes(bytes)) |img| return img;
    }
    return null;
}

// ============================================================================
// Pure-Zig Netpbm (`P1`..`P6` PBM / PGM / PPM) Decoder
// ============================================================================

fn nextNetpbmToken(bytes: []const u8, pos: *usize) ?[]const u8 {
    while (pos.* < bytes.len) {
        const ch = bytes[pos.*];
        if (ch == '#') {
            while (pos.* < bytes.len and bytes[pos.*] != '\n') : (pos.* += 1) {}
        } else if (std.ascii.isWhitespace(ch)) {
            pos.* += 1;
        } else {
            break;
        }
    }
    if (pos.* >= bytes.len) return null;
    const start = pos.*;
    while (pos.* < bytes.len and !std.ascii.isWhitespace(bytes[pos.*]) and bytes[pos.*] != '#') : (pos.* += 1) {}
    return bytes[start..pos.*];
}

pub fn decodeNetpbmImage(bytes: []const u8) ?skia.Image {
    var pos: usize = 0;
    const magic = nextNetpbmToken(bytes, &pos) orelse return null;
    if (magic.len != 2 or magic[0] != 'P' or magic[1] < '1' or magic[1] > '6') return null;
    const kind = magic[1];

    const w_tok = nextNetpbmToken(bytes, &pos) orelse return null;
    const h_tok = nextNetpbmToken(bytes, &pos) orelse return null;
    const w = std.fmt.parseInt(u32, w_tok, 10) catch return null;
    const h = std.fmt.parseInt(u32, h_tok, 10) catch return null;
    if (w == 0 or h == 0 or w > 4096 or h > 4096) return null;

    const max_val: u32 = if (kind == '1' or kind == '4') 1 else blk: {
        const mv_tok = nextNetpbmToken(bytes, &pos) orelse return null;
        break :blk std.fmt.parseInt(u32, mv_tok, 10) catch return null;
    };
    if (max_val == 0) return null;

    // Skip single whitespace character before binary payload
    if (pos < bytes.len and std.ascii.isWhitespace(bytes[pos])) {
        pos += 1;
    }

    const total_pixels = @as(usize, w) * @as(usize, h);
    const pixels = std.heap.c_allocator.alloc(u32, total_pixels) catch return null;
    defer std.heap.c_allocator.free(pixels);

    if (kind == '6') {
        // Binary RGB PPM
        for (0..total_pixels) |i| {
            if (pos + 3 > bytes.len) return null;
            const r = (@as(u32, bytes[pos]) * 255) / max_val;
            const g = (@as(u32, bytes[pos + 1]) * 255) / max_val;
            const b = (@as(u32, bytes[pos + 2]) * 255) / max_val;
            pos += 3;
            pixels[i] = Color.argb(255, @intCast(@min(255, r)), @intCast(@min(255, g)), @intCast(@min(255, b)));
        }
    } else if (kind == '5') {
        // Binary Grayscale PGM
        for (0..total_pixels) |i| {
            if (pos >= bytes.len) return null;
            const lum: u8 = @intCast(@min(255, (@as(u32, bytes[pos]) * 255) / max_val));
            pos += 1;
            pixels[i] = Color.argb(255, lum, lum, lum);
        }
    } else if (kind == '3') {
        // ASCII RGB PPM
        for (0..total_pixels) |i| {
            const rt = nextNetpbmToken(bytes, &pos) orelse return null;
            const gt = nextNetpbmToken(bytes, &pos) orelse return null;
            const bt = nextNetpbmToken(bytes, &pos) orelse return null;
            const r = ((std.fmt.parseInt(u32, rt, 10) catch 0) * 255) / max_val;
            const g = ((std.fmt.parseInt(u32, gt, 10) catch 0) * 255) / max_val;
            const b = ((std.fmt.parseInt(u32, bt, 10) catch 0) * 255) / max_val;
            pixels[i] = Color.argb(255, @intCast(@min(255, r)), @intCast(@min(255, g)), @intCast(@min(255, b)));
        }
    } else if (kind == '2' or kind == '1') {
        // ASCII Grayscale PGM / Bitmap PBM
        for (0..total_pixels) |i| {
            const vt = nextNetpbmToken(bytes, &pos) orelse return null;
            const raw_v = std.fmt.parseInt(u32, vt, 10) catch 0;
            const lum: u8 = if (kind == '1')
                (if (raw_v == 0) 255 else 0)
            else
                @intCast(@min(255, (raw_v * 255) / max_val));
            pixels[i] = Color.argb(255, lum, lum, lum);
        }
    } else {
        return null;
    }

    const info = skia.ImageInfo.initBgra8888Premul(@intCast(w), @intCast(h));
    return skia.Image.initRasterCopy(info, pixels.ptr, @as(usize, w) * 4) catch null;
}

// ============================================================================
// Lightweight `.svg` Vector Rasterizer (`<svg>`, `<rect>`, `<circle>`, `<line>`, `<path>`)
// ============================================================================

fn extractXmlAttr(tag: []const u8, attr_name: []const u8) ?[]const u8 {
    var pos: usize = 0;
    while (pos + attr_name.len + 2 < tag.len) {
        const idx = std.mem.indexOfPos(u8, tag, pos, attr_name) orelse return null;
        pos = idx + attr_name.len;
        if (idx > 0 and !std.ascii.isWhitespace(tag[idx - 1]) and tag[idx - 1] != '<') continue;
        while (pos < tag.len and std.ascii.isWhitespace(tag[pos])) : (pos += 1) {}
        if (pos >= tag.len or tag[pos] != '=') continue;
        pos += 1;
        while (pos < tag.len and std.ascii.isWhitespace(tag[pos])) : (pos += 1) {}
        if (pos >= tag.len) return null;
        const quote = tag[pos];
        if (quote != '"' and quote != '\'') continue;
        pos += 1;
        const val_start = pos;
        const val_end = std.mem.indexOfScalarPos(u8, tag, val_start, quote) orelse return null;
        return tag[val_start..val_end];
    }
    return null;
}

fn parseSvgNumber(raw: []const u8) ?f32 {
    const trimmed = std.mem.trim(u8, raw, " \t\r\npxpt%");
    if (trimmed.len == 0) return null;
    return std.fmt.parseFloat(f32, trimmed) catch null;
}

fn parseSvgColor(raw_opt: ?[]const u8, default_color: ?u32) ?u32 {
    const raw = std.mem.trim(u8, raw_opt orelse return default_color, " \t\r\n");
    if (raw.len == 0) return default_color;
    if (std.ascii.eqlIgnoreCase(raw, "none") or std.ascii.eqlIgnoreCase(raw, "transparent")) return null;
    if (raw[0] == '#') {
        const hex = raw[1..];
        if (hex.len == 6) {
            const v = std.fmt.parseInt(u32, hex, 16) catch return default_color;
            return 0xFF00_0000 | v;
        } else if (hex.len == 3) {
            const r = std.fmt.parseInt(u32, hex[0..1], 16) catch return default_color;
            const g = std.fmt.parseInt(u32, hex[1..2], 16) catch return default_color;
            const b = std.fmt.parseInt(u32, hex[2..3], 16) catch return default_color;
            return Color.argb(255, @intCast(r * 17), @intCast(g * 17), @intCast(b * 17));
        }
    }
    if (std.ascii.eqlIgnoreCase(raw, "white")) return Color.rgb(255, 255, 255);
    if (std.ascii.eqlIgnoreCase(raw, "black")) return Color.rgb(0, 0, 0);
    if (std.ascii.eqlIgnoreCase(raw, "red")) return Color.rgb(239, 68, 68);
    if (std.ascii.eqlIgnoreCase(raw, "green")) return Color.rgb(34, 197, 94);
    if (std.ascii.eqlIgnoreCase(raw, "blue")) return Color.rgb(59, 130, 246);
    if (std.ascii.eqlIgnoreCase(raw, "yellow")) return Color.rgb(250, 204, 21);
    if (std.ascii.eqlIgnoreCase(raw, "cyan")) return Color.rgb(6, 182, 212);
    if (std.ascii.eqlIgnoreCase(raw, "magenta")) return Color.rgb(217, 70, 239);
    if (std.ascii.eqlIgnoreCase(raw, "orange")) return Color.rgb(249, 115, 22);
    if (std.ascii.eqlIgnoreCase(raw, "gray") or std.ascii.eqlIgnoreCase(raw, "grey")) return Color.rgb(148, 163, 184);
    if (std.ascii.eqlIgnoreCase(raw, "currentColor")) return Color.rgb(226, 232, 240);
    return default_color;
}

pub fn rasterizeSvgBytes(bytes: []const u8) ?skia.Image {
    const svg_start = std.mem.indexOf(u8, bytes, "<svg") orelse return null;
    const svg_tag_end = std.mem.indexOfScalarPos(u8, bytes, svg_start, '>') orelse return null;
    const svg_tag = bytes[svg_start .. svg_tag_end + 1];

    var vb_x: f32 = 0.0;
    var vb_y: f32 = 0.0;
    var vb_w: f32 = 256.0;
    var vb_h: f32 = 256.0;

    if (extractXmlAttr(svg_tag, "viewBox")) |vb_str| {
        var it = std.mem.tokenizeAny(u8, vb_str, " ,\t\r\n");
        if (it.next()) |s0| vb_x = std.fmt.parseFloat(f32, s0) catch 0.0;
        if (it.next()) |s1| vb_y = std.fmt.parseFloat(f32, s1) catch 0.0;
        if (it.next()) |s2| vb_w = @max(1.0, std.fmt.parseFloat(f32, s2) catch 256.0);
        if (it.next()) |s3| vb_h = @max(1.0, std.fmt.parseFloat(f32, s3) catch 256.0);
    }
    const raw_w = if (extractXmlAttr(svg_tag, "width")) |ws| (parseSvgNumber(ws) orelse vb_w) else vb_w;
    const raw_h = if (extractXmlAttr(svg_tag, "height")) |hs| (parseSvgNumber(hs) orelse vb_h) else vb_h;
    if (extractXmlAttr(svg_tag, "viewBox") == null) {
        vb_w = @max(1.0, raw_w);
        vb_h = @max(1.0, raw_h);
    }

    const target_w: i32 = @intFromFloat(std.math.clamp(@round(raw_w), 16.0, 2048.0));
    const target_h: i32 = @intFromFloat(std.math.clamp(@round(raw_h), 16.0, 2048.0));

    const surface = skia.Surface.initRasterN32Premul(target_w, target_h) catch return null;
    defer surface.deinit();
    const canvas = surface.canvas();
    canvas.clear(Color.transparent);

    const paint = skia.Paint.init() catch return null;
    defer paint.deinit();
    paint.setAntiAlias(true);

    const sx = @as(f32, @floatFromInt(target_w)) / @max(1.0, vb_w);
    const sy = @as(f32, @floatFromInt(target_h)) / @max(1.0, vb_h);
    _ = canvas.save();
    canvas.scale(sx, sy);
    canvas.translate(-vb_x, -vb_y);

    var pos: usize = svg_tag_end + 1;
    while (pos < bytes.len) {
        const lt = std.mem.indexOfScalarPos(u8, bytes, pos, '<') orelse break;
        const gt = std.mem.indexOfScalarPos(u8, bytes, lt, '>') orelse break;
        pos = gt + 1;
        const tag = bytes[lt .. gt + 1];
        if (tag.len < 3 or tag[1] == '/' or tag[1] == '!' or tag[1] == '?') continue;

        var name_end: usize = 1;
        while (name_end < tag.len and !std.ascii.isWhitespace(tag[name_end]) and tag[name_end] != '>' and tag[name_end] != '/') : (name_end += 1) {}
        const tag_name = tag[1..name_end];

        const fill_opt = parseSvgColor(extractXmlAttr(tag, "fill"), Color.rgb(226, 232, 240));
        const stroke_opt = parseSvgColor(extractXmlAttr(tag, "stroke"), null);
        const stroke_w = if (extractXmlAttr(tag, "stroke-width")) |sw| (parseSvgNumber(sw) orelse 1.5) else 1.5;

        if (std.mem.eql(u8, tag_name, "rect")) {
            const x = if (extractXmlAttr(tag, "x")) |v| (parseSvgNumber(v) orelse 0.0) else 0.0;
            const y = if (extractXmlAttr(tag, "y")) |v| (parseSvgNumber(v) orelse 0.0) else 0.0;
            const w = if (extractXmlAttr(tag, "width")) |v| (parseSvgNumber(v) orelse 0.0) else 0.0;
            const h = if (extractXmlAttr(tag, "height")) |v| (parseSvgNumber(v) orelse 0.0) else 0.0;
            const rx = if (extractXmlAttr(tag, "rx")) |v| (parseSvgNumber(v) orelse 0.0) else 0.0;
            const ry = if (extractXmlAttr(tag, "ry")) |v| (parseSvgNumber(v) orelse rx) else rx;
            if (w > 0 and h > 0) {
                const r = Rect.xywh(x, y, w, h);
                if (fill_opt) |fc| {
                    paint.setStyle(.fill);
                    paint.setColor(fc);
                    if (rx > 0 or ry > 0) canvas.drawRoundRect(r, rx, ry, paint) else canvas.drawRect(r, paint);
                }
                if (stroke_opt) |sc| {
                    paint.setStyle(.stroke);
                    paint.setStrokeWidth(stroke_w);
                    paint.setColor(sc);
                    if (rx > 0 or ry > 0) canvas.drawRoundRect(r, rx, ry, paint) else canvas.drawRect(r, paint);
                }
            }
        } else if (std.mem.eql(u8, tag_name, "circle")) {
            const cx = if (extractXmlAttr(tag, "cx")) |v| (parseSvgNumber(v) orelse 0.0) else 0.0;
            const cy = if (extractXmlAttr(tag, "cy")) |v| (parseSvgNumber(v) orelse 0.0) else 0.0;
            const rad = if (extractXmlAttr(tag, "r")) |v| (parseSvgNumber(v) orelse 0.0) else 0.0;
            if (rad > 0) {
                if (fill_opt) |fc| {
                    paint.setStyle(.fill);
                    paint.setColor(fc);
                    canvas.drawCircle(cx, cy, rad, paint);
                }
                if (stroke_opt) |sc| {
                    paint.setStyle(.stroke);
                    paint.setStrokeWidth(stroke_w);
                    paint.setColor(sc);
                    canvas.drawCircle(cx, cy, rad, paint);
                }
            }
        } else if (std.mem.eql(u8, tag_name, "line")) {
            const x1 = if (extractXmlAttr(tag, "x1")) |v| (parseSvgNumber(v) orelse 0.0) else 0.0;
            const y1 = if (extractXmlAttr(tag, "y1")) |v| (parseSvgNumber(v) orelse 0.0) else 0.0;
            const x2 = if (extractXmlAttr(tag, "x2")) |v| (parseSvgNumber(v) orelse 0.0) else 0.0;
            const y2 = if (extractXmlAttr(tag, "y2")) |v| (parseSvgNumber(v) orelse 0.0) else 0.0;
            if (stroke_opt orelse fill_opt) |sc| {
                paint.setStyle(.stroke);
                paint.setStrokeWidth(stroke_w);
                paint.setColor(sc);
                canvas.drawLine(x1, y1, x2, y2, paint);
            }
        } else if (std.mem.eql(u8, tag_name, "path")) {
            if (extractXmlAttr(tag, "d")) |d_attr| {
                if (d_attr.len > 0 and d_attr.len < 4000) {
                    var d_z: [4096:0]u8 = @splat(0);
                    @memcpy(d_z[0..d_attr.len], d_attr);
                    d_z[d_attr.len] = 0;
                    if (skia.Path.init()) |sk_path| {
                        defer sk_path.deinit();
                        if (sk_path.parseSvg(&d_z)) {
                            if (fill_opt) |fc| {
                                paint.setStyle(.fill);
                                paint.setColor(fc);
                                canvas.drawPath(sk_path, paint);
                            }
                            if (stroke_opt) |sc| {
                                paint.setStyle(.stroke);
                                paint.setStrokeWidth(stroke_w);
                                paint.setColor(sc);
                                canvas.drawPath(sk_path, paint);
                            }
                        }
                    } else |_| {}
                }
            }
        }
    }

    canvas.restore();
    return surface.makeImageSnapshot() catch null;
}

// ============================================================================
// Two-Phase (`Pass.input` / `Pass.paint`) Image Viewer Widget
// ============================================================================

pub fn renderImageViewer(
    uic: *Context,
    id_str: []const u8,
    width: f32,
    height: f32,
    view: *ImageViewState,
    options: ImageViewerOptions,
) ImageViewerResult {
    const resolved = uic.resolveIdAndLabel(id_str);
    const full_r = uic.nextRect(width, height);
    const w = @max(1.0, full_r.right - full_r.left);
    const h = @max(1.0, full_r.bottom - full_r.top);

    const path_hash = std.hash.Wyhash.hash(0, options.file_path);
    if (view.last_path_hash != path_hash) {
        view.last_path_hash = path_hash;
        view.resetView();
    }

    const eff_bytes = if (options.raw_bytes.len > 0)
        options.raw_bytes
    else if (options.file_path.len == 0)
        SAMPLE_SVG_IMAGE
    else
        "";

    var file_bytes: usize = 0;
    const img_opt = getOrDecodeImage(options.file_path, eff_bytes, &file_bytes);
    const raw_img_w: i32 = if (img_opt) |img| img.width() else 0;
    const raw_img_h: i32 = if (img_opt) |img| img.height() else 0;
    const rotated_90 = (view.quarter_turns % 2) == 1;
    const disp_img_w: f32 = @floatFromInt(@max(1, if (rotated_90) raw_img_h else raw_img_w));
    const disp_img_h: f32 = @floatFromInt(@max(1, if (rotated_90) raw_img_w else raw_img_h));

    const toolbar_h: f32 = 34.0;
    const canvas_r = Rect.xywh(full_r.left, full_r.top + toolbar_h, w, @max(1.0, h - toolbar_h));
    const pad_margin: f32 = 28.0;
    const avail_w = @max(32.0, (canvas_r.right - canvas_r.left) - pad_margin * 2.0);
    const avail_h = @max(32.0, (canvas_r.bottom - canvas_r.top) - pad_margin * 2.0);

    const fit_zoom = std.math.clamp(@min(avail_w / disp_img_w, avail_h / disp_img_h), 0.05, 8.0);
    if (view.fit_to_view) {
        view.zoom = fit_zoom;
        view.pan_x = 0.0;
        view.pan_y = 0.0;
    }

    // Button hit rects in top toolbar
    const btn_y = full_r.top + 5.0;
    const btn_h: f32 = 24.0;
    const fit_btn_r = Rect.xywh(full_r.left + 218.0, btn_y, 38.0, btn_h);
    const one_btn_r = Rect.xywh(fit_btn_r.right + 4.0, btn_y, 38.0, btn_h);
    const z_out_r = Rect.xywh(one_btn_r.right + 8.0, btn_y, 24.0, btn_h);
    const z_lbl_r = Rect.xywh(z_out_r.right + 2.0, btn_y, 52.0, btn_h);
    const z_in_r = Rect.xywh(z_lbl_r.right + 2.0, btn_y, 24.0, btn_h);
    const bg_btn_r = Rect.xywh(z_in_r.right + 10.0, btn_y, 64.0, btn_h);
    const filt_btn_r = Rect.xywh(bg_btn_r.right + 6.0, btn_y, 58.0, btn_h);
    const rot_btn_r = Rect.xywh(filt_btn_r.right + 6.0, btn_y, 36.0, btn_h);

    var result = ImageViewerResult{
        .width = raw_img_w,
        .height = raw_img_h,
        .file_bytes = file_bytes,
        .zoom_percent = @intFromFloat(@round(view.zoom * 100.0)),
    };

    const dst_w = disp_img_w * view.zoom;
    const dst_h = disp_img_h * view.zoom;
    const cx = (canvas_r.left + canvas_r.right) * 0.5 + view.pan_x;
    const cy = (canvas_r.top + canvas_r.bottom) * 0.5 + view.pan_y;
    const img_rect = Rect.xywh(cx - dst_w * 0.5, cy - dst_h * 0.5, dst_w, dst_h);

    // ------------------------------------------------------------------------
    // Pass 1 (`.input`): Toolbar Clicks, Zoom/Pan Gestures & Pixel Eyedropper
    // ------------------------------------------------------------------------
    if (uic.pass == .input) {
        const hovered_canvas = uic.isHovered(canvas_r);
        if (hovered_canvas) {
            uic.hot_id = resolved.wid;
        }

        if (uic.mouse_pressed and uic.isHovered(full_r)) {
            if (uic.isHovered(fit_btn_r)) {
                view.fit_to_view = true;
                view.zoom = fit_zoom;
                view.pan_x = 0.0;
                view.pan_y = 0.0;
                uic.markDirty(full_r);
            } else if (uic.isHovered(one_btn_r)) {
                view.fit_to_view = false;
                view.zoom = 1.0;
                view.pan_x = 0.0;
                view.pan_y = 0.0;
                uic.markDirty(full_r);
            } else if (uic.isHovered(z_out_r)) {
                view.fit_to_view = false;
                view.zoom = std.math.clamp(view.zoom / 1.25, 0.05, 32.0);
                uic.markDirty(full_r);
            } else if (uic.isHovered(z_in_r)) {
                view.fit_to_view = false;
                view.zoom = std.math.clamp(view.zoom * 1.25, 0.05, 32.0);
                uic.markDirty(full_r);
            } else if (uic.isHovered(bg_btn_r)) {
                view.backdrop = view.backdrop.next();
                uic.markDirty(full_r);
            } else if (uic.isHovered(filt_btn_r)) {
                view.nearest_sampling = !view.nearest_sampling;
                uic.markDirty(full_r);
            } else if (uic.isHovered(rot_btn_r)) {
                view.quarter_turns +%= 1;
                uic.markDirty(full_r);
            } else if (hovered_canvas) {
                view.dragging = true;
                view.drag_last_x = uic.mouse_x;
                view.drag_last_y = uic.mouse_y;
                uic.active_id = resolved.wid;
                if (view.has_hovered_pixel) {
                    const r_ch: u8 = @intCast((view.hovered_color >> 16) & 0xFF);
                    const g_ch: u8 = @intCast((view.hovered_color >> 8) & 0xFF);
                    const b_ch: u8 = @intCast(view.hovered_color & 0xFF);
                    if (std.fmt.bufPrint(&view.copied_hex_buf, "#{X:0>2}{X:0>2}{X:0>2}", .{ r_ch, g_ch, b_ch })) |hex_s| {
                        view.copied_hex_len = @intCast(hex_s.len);
                        result.copied_color_hex = hex_s;
                        if (uic.platform_ctx) |pctx| {
                            _ = pctx.setClipboardText(hex_s);
                        }
                    } else |_| {}
                }
                uic.markDirty(full_r);
            }
        }

        if (view.dragging) {
            if (uic.mouse_down) {
                const dx = uic.mouse_x - view.drag_last_x;
                const dy = uic.mouse_y - view.drag_last_y;
                if (@abs(dx) > 0.5 or @abs(dy) > 0.5) {
                    view.fit_to_view = false;
                    view.pan_x += dx;
                    view.pan_y += dy;
                    view.drag_last_x = uic.mouse_x;
                    view.drag_last_y = uic.mouse_y;
                    uic.markDirty(canvas_r);
                }
            } else {
                view.dragging = false;
                if (uic.active_id == resolved.wid) uic.active_id = 0;
            }
        }

        // Trackpad pinch-to-zoom (`uic.magnify_delta`), anchored around the cursor position `(mouse_x, mouse_y)`
        if (hovered_canvas and @abs(uic.magnify_delta) > 0.001) {
            const old_zoom = @max(0.05, view.zoom);
            const scale_factor = std.math.clamp(1.0 + uic.magnify_delta, 0.25, 4.0);
            const new_zoom = std.math.clamp(old_zoom * scale_factor, 0.05, 32.0);
            if (@abs(new_zoom - old_zoom) > 0.0005) {
                const ratio = new_zoom / old_zoom;
                view.fit_to_view = false;
                view.pan_x += (uic.mouse_x - cx) * (1.0 - ratio);
                view.pan_y += (uic.mouse_y - cy) * (1.0 - ratio);
                view.zoom = new_zoom;
                uic.markDirty(full_r);
            }
        }

        // Scroll wheel / trackpad: zoom when holding Shift or when `fit_to_view` is active and scrolling vertically,
        // or 2D axis-snapped pan when zoomed larger than viewport.
        if (hovered_canvas and (uic.scroll_dx != 0 or uic.scroll_dy != 0)) {
            const snapped = root.snapScrollAxis(uic.scroll_dx, uic.scroll_dy);
            const exceeds_viewport = (dst_w > (canvas_r.right - canvas_r.left) + 4.0) or
                (dst_h > (canvas_r.bottom - canvas_r.top) + 4.0);
            if (uic.mouse_shift or !exceeds_viewport) {
                if (@abs(snapped.dy) > 0.1) {
                    view.fit_to_view = false;
                    const zoom_factor: f32 = if (snapped.dy > 0) 1.08 else (1.0 / 1.08);
                    view.zoom = std.math.clamp(view.zoom * zoom_factor, 0.05, 32.0);
                    uic.markDirty(full_r);
                }
            } else {
                view.fit_to_view = false;
                const max_pan_x = @max(0.0, (dst_w - (canvas_r.right - canvas_r.left)) * 0.5 + 48.0);
                const max_pan_y = @max(0.0, (dst_h - (canvas_r.bottom - canvas_r.top)) * 0.5 + 48.0);
                view.pan_x = std.math.clamp(view.pan_x + snapped.dx, -max_pan_x, max_pan_x);
                view.pan_y = std.math.clamp(view.pan_y + snapped.dy, -max_pan_y, max_pan_y);
                uic.markDirty(canvas_r);
            }
        }

        // Live Pixel Eyedropper Inspector under cursor
        var new_has_px = false;
        var new_px_x: i32 = -1;
        var new_px_y: i32 = -1;
        var new_px_col: u32 = 0;
        if (img_opt) |img| {
            if (hovered_canvas and uic.isHovered(img_rect) and raw_img_w > 0 and raw_img_h > 0 and view.quarter_turns == 0) {
                const norm_x = (uic.mouse_x - img_rect.left) / @max(1.0, img_rect.right - img_rect.left);
                const norm_y = (uic.mouse_y - img_rect.top) / @max(1.0, img_rect.bottom - img_rect.top);
                const ix: i32 = std.math.clamp(@as(i32, @intFromFloat(@floor(norm_x * @as(f32, @floatFromInt(raw_img_w))))), 0, raw_img_w - 1);
                const iy: i32 = std.math.clamp(@as(i32, @intFromFloat(@floor(norm_y * @as(f32, @floatFromInt(raw_img_h))))), 0, raw_img_h - 1);
                if (img.peekPixelColor(ix, iy)) |col| {
                    new_has_px = true;
                    new_px_x = ix;
                    new_px_y = iy;
                    new_px_col = col;
                }
            }
        }
        if (new_has_px != view.has_hovered_pixel or new_px_x != view.hovered_px_x or new_px_y != view.hovered_px_y) {
            view.has_hovered_pixel = new_has_px;
            view.hovered_px_x = new_px_x;
            view.hovered_px_y = new_px_y;
            view.hovered_color = new_px_col;
            uic.markDirty(Rect.xywh(full_r.left, full_r.top, w, toolbar_h));
        }
    }

    result.zoom_percent = @intFromFloat(@round(view.zoom * 100.0));

    // ------------------------------------------------------------------------
    // Pass 2 (`.paint`): Top Control Strip + Scissor-Clipped Image Canvas
    // ------------------------------------------------------------------------
    if (uic.pass == .paint and uic.shouldPaint(full_r)) {
        const theme = uic.theme;
        const font_body = uic.font_body;
        const font_mono = uic.font_mono;

        // 1. Top Toolbar Background
        const toolbar_r = Rect.xywh(full_r.left, full_r.top, w, toolbar_h);
        uic.paint.setStyle(.fill);
        uic.paint.setColor(Color.rgb(16, 21, 30));
        uic.canvas.drawRect(toolbar_r, uic.paint);
        uic.paint.setColor(theme.border_subtle);
        uic.canvas.drawRect(Rect.xywh(full_r.left, toolbar_r.bottom - 1.0, w, 1.0), uic.paint);

        // Format badge + dimensions + file size
        const fmt_badge = detectImageFormatBadge(options.file_path, eff_bytes);
        const badge_r = Rect.xywh(full_r.left + 10.0, btn_y + 2.0, 44.0, 20.0);
        uic.paint.setColor(Color.argb(45, 56, 189, 248));
        uic.canvas.drawRoundRect(badge_r, 4.0, 4.0, uic.paint);
        uic.paint.setColor(Color.rgb(56, 189, 248));
        const bw = uic.measureTextCached(font_mono, fmt_badge);
        uic.drawTextCached(font_mono, fmt_badge, badge_r.left + (44.0 - bw) * 0.5, badge_r.top + 14.0);

        const dim_str = if (raw_img_w > 0 and raw_img_h > 0) blk: {
            if (file_bytes >= 1024) {
                break :blk uic.fmt("{d}×{d} px  •  {d:.1} KB", .{ raw_img_w, raw_img_h, @as(f32, @floatFromInt(file_bytes)) / 1024.0 });
            }
            break :blk uic.fmt("{d}×{d} px", .{ raw_img_w, raw_img_h });
        } else "Invalid Image";
        uic.paint.setColor(theme.text_muted);
        uic.drawTextCached(font_mono, dim_str, badge_r.right + 8.0, btn_y + 16.0);

        // Toolbar buttons
        drawToolbarChip(uic, font_body, fit_btn_r, "Fit", view.fit_to_view);
        drawToolbarChip(uic, font_body, one_btn_r, "1:1", !view.fit_to_view and @abs(view.zoom - 1.0) < 0.01);
        drawToolbarChip(uic, font_body, z_out_r, "-", false);
        const zoom_lbl = uic.fmt("{d}%", .{result.zoom_percent});
        drawToolbarChip(uic, font_mono, z_lbl_r, zoom_lbl, false);
        drawToolbarChip(uic, font_body, z_in_r, "+", false);
        drawToolbarChip(uic, font_body, bg_btn_r, view.backdrop.label(), false);
        const use_nearest = view.nearest_sampling or (view.zoom >= 4.0);
        drawToolbarChip(uic, font_body, filt_btn_r, if (use_nearest) "Pixel" else "Smooth", use_nearest);
        drawToolbarChip(uic, font_body, rot_btn_r, "90°", view.quarter_turns != 0);

        // Right-aligned live Eyedropper Pixel Inspector pill
        if (view.has_hovered_pixel and w > 640.0) {
            const r_ch: u8 = @intCast((view.hovered_color >> 16) & 0xFF);
            const g_ch: u8 = @intCast((view.hovered_color >> 8) & 0xFF);
            const b_ch: u8 = @intCast(view.hovered_color & 0xFF);
            const a_ch: u8 = @intCast((view.hovered_color >> 24) & 0xFF);
            const px_txt = uic.fmt("({d}, {d})  #{X:0>2}{X:0>2}{X:0>2}  α:{d}", .{
                view.hovered_px_x,
                view.hovered_px_y,
                r_ch,
                g_ch,
                b_ch,
                a_ch,
            });
            const txt_w = uic.measureTextCached(font_mono, px_txt);
            const pill_w = txt_w + 30.0;
            const pill_r = Rect.xywh(full_r.right - pill_w - 10.0, btn_y + 1.0, pill_w, 22.0);
            uic.paint.setStyle(.fill);
            uic.paint.setColor(Color.rgb(22, 29, 42));
            uic.canvas.drawRoundRect(pill_r, 5.0, 5.0, uic.paint);
            // Color swatch square
            const swatch_r = Rect.xywh(pill_r.left + 5.0, pill_r.top + 4.0, 14.0, 14.0);
            uic.paint.setColor(view.hovered_color | 0xFF00_0000);
            uic.canvas.drawRoundRect(swatch_r, 3.0, 3.0, uic.paint);
            uic.paint.setStyle(.stroke);
            uic.paint.setStrokeWidth(1.0);
            uic.paint.setColor(Color.argb(140, 255, 255, 255));
            uic.canvas.drawRoundRect(swatch_r, 3.0, 3.0, uic.paint);
            uic.paint.setStyle(.fill);
            uic.paint.setColor(theme.text_primary);
            uic.drawTextCached(font_mono, px_txt, swatch_r.right + 6.0, pill_r.top + 15.0);
        }

        // 2. Scissor-Clipped Image Viewport
        if (uic.shouldPaint(canvas_r)) {
            const save_cnt = uic.canvas.save();
            defer uic.canvas.restoreToCount(save_cnt);
            uic.canvas.clipRect(canvas_r, .intersect, false);

            uic.paint.setStyle(.fill);
            uic.paint.setColor(Color.rgb(11, 15, 22));
            uic.canvas.drawRect(canvas_r, uic.paint);

            if (img_opt) |img| {
                const clipped_img_r = Rect.ltrb(
                    @max(canvas_r.left, img_rect.left),
                    @max(canvas_r.top, img_rect.top),
                    @min(canvas_r.right, img_rect.right),
                    @min(canvas_r.bottom, img_rect.bottom),
                );

                // Backdrop behind the image bounds (Checkerboard / Dark / Light)
                if (clipped_img_r.right > clipped_img_r.left and clipped_img_r.bottom > clipped_img_r.top) {
                    switch (view.backdrop) {
                        .dark => {
                            uic.paint.setColor(Color.rgb(18, 23, 33));
                            uic.canvas.drawRect(clipped_img_r, uic.paint);
                        },
                        .light => {
                            uic.paint.setColor(Color.rgb(241, 245, 249));
                            uic.canvas.drawRect(clipped_img_r, uic.paint);
                        },
                        .checker => {
                            drawCheckerboardBackdrop(uic, clipped_img_r, img_rect.left, img_rect.top);
                        },
                    }
                }

                // Draw the image with rotation and selected filter mode
                const img_save = uic.canvas.save();
                uic.canvas.translate(cx, cy);
                if (view.quarter_turns != 0) {
                    uic.canvas.rotateDegrees(@as(f32, @floatFromInt(view.quarter_turns)) * 90.0);
                }
                const unrot_w = @as(f32, @floatFromInt(raw_img_w)) * view.zoom;
                const unrot_h = @as(f32, @floatFromInt(raw_img_h)) * view.zoom;
                const local_dst = Rect.xywh(-unrot_w * 0.5, -unrot_h * 0.5, unrot_w, unrot_h);
                uic.canvas.drawImageRectSampling(img, local_dst, use_nearest, null);
                uic.canvas.restoreToCount(img_save);

                // Optional pixel grid when zoomed >= 800% in Pixel mode
                if (use_nearest and view.zoom >= 8.0 and view.quarter_turns == 0) {
                    drawZoomedPixelGrid(uic, img_rect, clipped_img_r, raw_img_w, raw_img_h, view.zoom);
                }

                // Crisp 1pt frame around the image canvas
                uic.paint.setStyle(.stroke);
                uic.paint.setStrokeWidth(1.0);
                uic.paint.setColor(Color.argb(110, 148, 163, 184));
                uic.canvas.drawRect(img_rect, uic.paint);
                uic.paint.setStyle(.fill);
            } else {
                const msg = "Unable to decode image file";
                const mw = uic.measureTextCached(font_body, msg);
                uic.paint.setColor(theme.text_muted);
                uic.drawTextCached(font_body, msg, (canvas_r.left + canvas_r.right - mw) * 0.5, (canvas_r.top + canvas_r.bottom) * 0.5);
            }
        }
    }

    return result;
}

fn drawToolbarChip(uic: *Context, font: Font, r: c.sk_rect_t, label: []const u8, active: bool) void {
    const hovered = uic.isHovered(r);
    uic.paint.setStyle(.fill);
    uic.paint.setColor(if (active)
        Color.argb(60, 56, 189, 248)
    else if (hovered)
        Color.rgb(32, 41, 58)
    else
        Color.rgb(23, 30, 44));
    uic.canvas.drawRoundRect(r, 5.0, 5.0, uic.paint);

    uic.paint.setStyle(.stroke);
    uic.paint.setStrokeWidth(1.0);
    uic.paint.setColor(if (active) Color.rgb(56, 189, 248) else uic.theme.border_subtle);
    uic.canvas.drawRoundRect(r, 5.0, 5.0, uic.paint);

    uic.paint.setStyle(.fill);
    uic.paint.setColor(if (active) Color.rgb(125, 211, 252) else uic.theme.text_primary);
    const tw = uic.measureTextCached(font, label);
    const tx = r.left + ((r.right - r.left) - tw) * 0.5;
    const ty = r.top + (r.bottom - r.top) * 0.5 + 4.0;
    uic.drawTextCached(font, label, tx, ty);
}

fn drawCheckerboardBackdrop(uic: *Context, clip_r: c.sk_rect_t, origin_x: f32, origin_y: f32) void {
    const cell: f32 = 12.0;
    uic.paint.setStyle(.fill);
    uic.paint.setColor(Color.rgb(24, 30, 42));
    uic.canvas.drawRect(clip_r, uic.paint);

    uic.paint.setColor(Color.rgb(34, 42, 58));
    const start_col: i32 = @intFromFloat(@floor((clip_r.left - origin_x) / cell));
    const end_col: i32 = @intFromFloat(@ceil((clip_r.right - origin_x) / cell));
    const start_row: i32 = @intFromFloat(@floor((clip_r.top - origin_y) / cell));
    const end_row: i32 = @intFromFloat(@ceil((clip_r.bottom - origin_y) / cell));

    var row = start_row;
    while (row < end_row) : (row += 1) {
        var col = start_col;
        while (col < end_col) : (col += 1) {
            if (@mod(row + col, 2) == 0) continue;
            const x0 = @max(clip_r.left, origin_x + @as(f32, @floatFromInt(col)) * cell);
            const y0 = @max(clip_r.top, origin_y + @as(f32, @floatFromInt(row)) * cell);
            const x1 = @min(clip_r.right, origin_x + @as(f32, @floatFromInt(col + 1)) * cell);
            const y1 = @min(clip_r.bottom, origin_y + @as(f32, @floatFromInt(row + 1)) * cell);
            if (x1 > x0 and y1 > y0) {
                uic.canvas.drawRect(Rect.ltrb(x0, y0, x1, y1), uic.paint);
            }
        }
    }
}

fn drawZoomedPixelGrid(uic: *Context, img_rect: c.sk_rect_t, clip_r: c.sk_rect_t, img_w: i32, img_h: i32, zoom: f32) void {
    uic.paint.setStyle(.stroke);
    uic.paint.setStrokeWidth(1.0);
    uic.paint.setColor(Color.argb(45, 255, 255, 255));

    const first_x: i32 = @max(0, @as(i32, @intFromFloat(@floor((clip_r.left - img_rect.left) / zoom))));
    const last_x: i32 = @min(img_w, @as(i32, @intFromFloat(@ceil((clip_r.right - img_rect.left) / zoom))));
    var ix = first_x;
    while (ix <= last_x) : (ix += 1) {
        const x = img_rect.left + @as(f32, @floatFromInt(ix)) * zoom;
        uic.canvas.drawLine(x, clip_r.top, x, clip_r.bottom, uic.paint);
    }

    const first_y: i32 = @max(0, @as(i32, @intFromFloat(@floor((clip_r.top - img_rect.top) / zoom))));
    const last_y: i32 = @min(img_h, @as(i32, @intFromFloat(@ceil((clip_r.bottom - img_rect.top) / zoom))));
    var iy = first_y;
    while (iy <= last_y) : (iy += 1) {
        const y = img_rect.top + @as(f32, @floatFromInt(iy)) * zoom;
        uic.canvas.drawLine(clip_r.left, y, clip_r.right, y, uic.paint);
    }
    uic.paint.setStyle(.fill);
}

// ============================================================================
// Unit Tests
// ============================================================================

test "ImageViewer decodes PNG, Netpbm PPM, and SVG and executes 2-phase Pass.input -> Pass.paint deterministically" {
    defer clearImageCache();

    // 1. Test Netpbm ASCII PPM decoding (`P3`)
    const ppm_src =
        \\P3
        \\# 2x2 test image
        \\2 2
        \\255
        \\255 0 0   0 255 0
        \\0 0 255   255 255 255
    ;
    const ppm_img = decodeNetpbmImage(ppm_src) orelse return error.InvalidOperation;
    defer ppm_img.deinit();
    try std.testing.expectEqual(@as(i32, 2), ppm_img.width());
    try std.testing.expectEqual(@as(i32, 2), ppm_img.height());
    try std.testing.expectEqual(Color.rgb(255, 0, 0), ppm_img.peekPixelColor(0, 0).?);
    try std.testing.expectEqual(Color.rgb(0, 255, 0), ppm_img.peekPixelColor(1, 0).?);

    // 2. Test SVG vector rasterization
    const svg_img = rasterizeSvgBytes(SAMPLE_SVG_IMAGE) orelse return error.InvalidOperation;
    defer svg_img.deinit();
    try std.testing.expectEqual(@as(i32, 320), svg_img.width());
    try std.testing.expectEqual(@as(i32, 200), svg_img.height());

    // 3. Encode a Skia surface to PNG and verify 2-phase `renderImageViewer`
    const surf = try skia.Surface.initRasterN32Premul(64, 48);
    defer surf.deinit();
    surf.canvas().clear(Color.rgb(40, 120, 220));
    const png_data = try surf.encodePng();
    defer png_data.deinit();

    const win_surf = try skia.Surface.initRasterN32Premul(720, 420);
    defer win_surf.deinit();
    const paint = try skia.Paint.init();
    defer paint.deinit();
    const font = try Font.init(null, 12.0);
    defer font.deinit();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var uic = Context{
        .arena = arena.allocator(),
        .canvas = win_surf.canvas(),
        .paint = paint,
        .font_title = font,
        .font_body = font,
        .font_mono = font,
    };
    defer uic.deinit();

    var view_state = ImageViewState{};
    const win_r = Rect.xywh(0, 0, 720, 420);

    // Pass 1: `.input` pass hovering over center of image
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), win_surf.canvas(), win_r, 360.0, 220.0, false, false, false);
    const res_in = uic.imageViewer("test_img_viewer", 720.0, 420.0, &view_state, .{
        .file_path = "test_plot.png",
        .raw_bytes = png_data.slice(),
    });
    uic.endPass();
    try std.testing.expectEqual(@as(i32, 64), res_in.width);
    try std.testing.expectEqual(@as(i32, 48), res_in.height);
    try std.testing.expect(view_state.has_hovered_pixel);
    try std.testing.expectEqual(Color.rgb(40, 120, 220), view_state.hovered_color);

    // Pass 2: `.paint` pass
    uic.invalidateWindow();
    uic.clip_damage = win_r;
    uic.beginPass(.paint, arena.allocator(), win_surf.canvas(), win_r, 360.0, 220.0, false, false, false);
    const res_paint = uic.imageViewer("test_img_viewer", 720.0, 420.0, &view_state, .{
        .file_path = "test_plot.png",
        .raw_bytes = png_data.slice(),
    });
    uic.endPass();
    try std.testing.expectEqual(res_in.width, res_paint.width);
    try std.testing.expectEqual(res_in.height, res_paint.height);

    // 4. Test trackpad pinch-to-zoom (`magnify_delta`) anchored around cursor
    const zoom_before = view_state.zoom;
    _ = arena.reset(.retain_capacity);
    uic.magnify_delta = 0.5;
    uic.beginPass(.input, arena.allocator(), win_surf.canvas(), win_r, 400.0, 240.0, false, false, false);
    _ = uic.imageViewer("test_img_viewer", 720.0, 420.0, &view_state, .{
        .file_path = "test_plot.png",
        .raw_bytes = png_data.slice(),
    });
    uic.endPass();
    try std.testing.expect(!view_state.fit_to_view);
    try std.testing.expectApproxEqAbs(zoom_before * 1.5, view_state.zoom, 0.01);
}
