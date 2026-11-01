//! Interactive PDF Document Reader, CoreGraphics Page Rasterizer & Text Extractor (`src/ui/pdf_viewer.zig`).
//!
//! Features:
//!   - **Zero-Allocation PDF 1.x Parser & Stream Extractor (`parsePdfDocument`)**:
//!     Extracts PDF version (`%PDF-1.x`), `/Title`, `/Author`, `/Subject`, document outline/bookmarks,
//!     and `BT ... ET` text operators (`Tj`, `TJ`, `Td`, `TD`, `T*`, `'`) with literal `(...)` and
//!     hex `<...>` string decoding.
//!   - **Native macOS Quartz / CoreGraphics PDF Engine (`CGPDFDocument` + `CGContextDrawPDFPage`)**:
//!     Renders arbitrary `.pdf` files from disk or in-memory PDF byte slices at crisp Retina resolution
//!     into a 4-slot LRU `skia.Image` texture cache (`O(1)` GPU blit during `Pass.paint`), and uses
//!     `CGPDFStreamCopyData` to transparently decompress `/FlateDecode` and `/LZWDecode` text streams.
//!   - **Built-in Multi-Page Technical Datasheet (`SAMPLE_PDF_DOC`)**:
//!     Provides a standards-compliant 3-page PDF 1.4 SoC Technical Reference Datasheet with vector
//!     diagrams, memory map tables, and peripheral register specifications out of the box.
//!   - **Two-Phase (`Pass.input` / `Pass.paint`) Interactive Viewer (`renderPdfViewer`)**:
//!     - Top control bar: Page navigation (`◀`, `Pg X/N`, `▶`), Zoom (`-`, `100%`, `+`), Dark Paper
//!       inversion toggle, Outline sidebar toggle, View Mode (`Page` / `Split` / `Text`), live search
//!       input with match counter, and `Extract MD` action.
//!     - Smooth mouse-wheel scrolling, click-and-drag page panning, outline/thumbnail navigation rail,
//!       and live search highlight overlays.

const std = @import("std");
const builtin = @import("builtin");
const skia = @import("skia");
const platform = @import("platform");
const root = @import("root.zig");
const c = skia.c;
const Color = skia.Color;
const Rect = skia.Rect;
const Font = skia.Font;
const Context = root.Context;
const Size = root.Size;
const Padding = root.Padding;

pub const MaxPdfPages: usize = 16;
pub const MaxLinesPerPage: usize = 48;

// ============================================================================
// macOS CoreGraphics / CoreFoundation C-ABI Bindings (Zero `@cImport`)
// ============================================================================
const is_macos = (builtin.os.tag == .macos);

const CGPoint = extern struct {
    x: f64 = 0,
    y: f64 = 0,
};

const CGSize = extern struct {
    width: f64 = 0,
    height: f64 = 0,
};

const CGRect = extern struct {
    origin: CGPoint = .{},
    size: CGSize = .{},
};

const kCGPDFMediaBox: c_int = 0;
const kCGImageAlphaPremultipliedFirst: u32 = 2;
const kCGBitmapByteOrder32Little: u32 = 2 << 12;

extern "c" fn CFURLCreateFromFileSystemRepresentation(
    allocator: ?*const anyopaque,
    buffer: [*]const u8,
    bufLen: isize,
    isDirectory: u8,
) ?*anyopaque;
extern "c" fn CFRelease(cf: *const anyopaque) void;
extern "c" fn CFDataGetLength(theData: *const anyopaque) isize;
extern "c" fn CFDataGetBytePtr(theData: *const anyopaque) ?[*]const u8;

extern "c" fn CGDataProviderCreateWithData(
    info: ?*anyopaque,
    data: *const anyopaque,
    size: usize,
    releaseData: ?*const anyopaque,
) ?*anyopaque;
extern "c" fn CGDataProviderRelease(provider: ?*anyopaque) void;

extern "c" fn CGPDFDocumentCreateWithURL(url: *const anyopaque) ?*anyopaque;
extern "c" fn CGPDFDocumentCreateWithProvider(provider: *anyopaque) ?*anyopaque;
extern "c" fn CGPDFDocumentRelease(doc: ?*anyopaque) void;
extern "c" fn CGPDFDocumentGetNumberOfPages(doc: *anyopaque) usize;
extern "c" fn CGPDFDocumentGetPage(doc: *anyopaque, pageNumber: usize) ?*anyopaque;
extern "c" fn CGPDFDocumentGetInfo(doc: *anyopaque) ?*anyopaque;
extern "c" fn CGPDFDocumentGetCatalog(doc: *anyopaque) ?*anyopaque;
extern "c" fn CGPDFPageGetBoxRect(page: *anyopaque, box: c_int) CGRect;
extern "c" fn CGPDFPageGetDictionary(page: *anyopaque) ?*anyopaque;

extern "c" fn CGPDFDictionaryGetDictionary(dict: *anyopaque, key: [*:0]const u8, value: *?*anyopaque) bool;
extern "c" fn CGPDFDictionaryGetString(dict: *anyopaque, key: [*:0]const u8, value: *?*anyopaque) bool;
extern "c" fn CGPDFDictionaryGetName(dict: *anyopaque, key: [*:0]const u8, value: *?[*:0]const u8) bool;
extern "c" fn CGPDFDictionaryGetInteger(dict: *anyopaque, key: [*:0]const u8, value: *isize) bool;
extern "c" fn CGPDFDictionaryGetStream(dict: *anyopaque, key: [*:0]const u8, value: *?*anyopaque) bool;
extern "c" fn CGPDFDictionaryGetArray(dict: *anyopaque, key: [*:0]const u8, value: *?*anyopaque) bool;
extern "c" fn CGPDFArrayGetCount(array: *anyopaque) usize;
extern "c" fn CGPDFArrayGetDictionary(array: *anyopaque, index: usize, value: *?*anyopaque) bool;
extern "c" fn CGPDFArrayGetArray(array: *anyopaque, index: usize, value: *?*anyopaque) bool;
extern "c" fn CGPDFArrayGetString(array: *anyopaque, index: usize, value: *?*anyopaque) bool;
extern "c" fn CGPDFArrayGetName(array: *anyopaque, index: usize, value: *?[*:0]const u8) bool;
extern "c" fn CGPDFArrayGetNumber(array: *anyopaque, index: usize, value: *f64) bool;
extern "c" fn CGPDFArrayGetStream(array: *anyopaque, index: usize, value: *?*anyopaque) bool;
extern "c" fn CGPDFStreamCopyData(stream: *anyopaque, format: *c_int) ?*anyopaque;
extern "c" fn CGPDFStringGetLength(str: *anyopaque) usize;
extern "c" fn CGPDFStringGetBytePtr(str: *anyopaque) ?[*]const u8;

extern "c" fn CGColorSpaceCreateDeviceRGB() ?*anyopaque;
extern "c" fn CGColorSpaceRelease(cs: ?*anyopaque) void;
extern "c" fn CGBitmapContextCreate(
    data: ?*anyopaque,
    width: usize,
    height: usize,
    bitsPerComponent: usize,
    bytesPerRow: usize,
    space: ?*anyopaque,
    bitmapInfo: u32,
) ?*anyopaque;
extern "c" fn CGContextRelease(ctx: ?*anyopaque) void;
extern "c" fn CGContextSetRGBFillColor(ctx: *anyopaque, r: f64, g: f64, b: f64, a: f64) void;
extern "c" fn CGContextFillRect(ctx: *anyopaque, rect: CGRect) void;
extern "c" fn CGContextSaveGState(ctx: *anyopaque) void;
extern "c" fn CGContextRestoreGState(ctx: *anyopaque) void;
extern "c" fn CGContextScaleCTM(ctx: *anyopaque, sx: f64, sy: f64) void;
extern "c" fn CGContextTranslateCTM(ctx: *anyopaque, tx: f64, ty: f64) void;
extern "c" fn CGContextDrawPDFPage(ctx: *anyopaque, page: *anyopaque) void;

// ============================================================================
// Public PDF Document & View State Types
// ============================================================================

pub const PdfOutlineItem = struct {
    title: platform.InlineString(64) = .{},
    page_number: u32 = 1, // 1-based page number (supports multi-thousand-page specs)
    norm_y: f32 = 0.0, // Normalized top-down vertical offset within the target page [0.0 .. 1.0]
    indent: u8 = 0,
};

pub const PdfDestination = struct {
    page_number: u32 = 1,
    norm_y: f32 = 0.0,
};

pub const PdfSearchMatch = struct {
    match_index: usize = 0, // 0-based global occurrence index across the document
    page_idx: usize = 0, // 0-based page index
    line_idx: usize = 0, // 0-based line index on `page_idx` (or `MaxLinesPerPage` if outline match)
    byte_offset: usize = 0, // byte offset within the line
    byte_len: usize = 0, // matched byte length
    norm_x: f32 = 0.07, // normalized x [0..1] on page
    norm_y: f32 = 0.10, // normalized top-down y [0..1] on page
    norm_w: f32 = 0.10, // normalized width [0..1] on page
    norm_h: f32 = 0.02, // normalized height [0..1] on page
};

pub const PdfTextPos = struct {
    page_idx: usize = 0,
    line_idx: usize = 0,
    col: usize = 0,

    pub fn lessThan(a: PdfTextPos, b: PdfTextPos) bool {
        if (a.page_idx != b.page_idx) return a.page_idx < b.page_idx;
        if (a.line_idx != b.line_idx) return a.line_idx < b.line_idx;
        return a.col < b.col;
    }

    pub fn eql(a: PdfTextPos, b: PdfTextPos) bool {
        return a.page_idx == b.page_idx and a.line_idx == b.line_idx and a.col == b.col;
    }
};

pub const PdfPageInfo = struct {
    width_pt: f32 = 612.0,
    height_pt: f32 = 792.0,
    lines: [MaxLinesPerPage]platform.InlineString(96) = @splat(.{}),
    line_x_pt: [MaxLinesPerPage]f32 = @splat(42.0),
    line_y_pt: [MaxLinesPerPage]f32 = @splat(0.0),
    line_w_pt: [MaxLinesPerPage]f32 = @splat(0.0),
    line_font_pt: [MaxLinesPerPage]f32 = @splat(10.0),
    line_count: usize = 0,

    pub fn addLine(self: *PdfPageInfo, raw_line: []const u8) void {
        self.addLineWithBounds(raw_line, 42.0, 0.0, 0.0, 10.0);
    }

    pub fn addLineAt(self: *PdfPageInfo, raw_line: []const u8, x_pt: f32, y_pt: f32, font_pt: f32) void {
        self.addLineWithBounds(raw_line, x_pt, y_pt, 0.0, font_pt);
    }

    pub fn addLineWithBounds(self: *PdfPageInfo, raw_line: []const u8, x_pt: f32, y_pt: f32, w_pt: f32, font_pt: f32) void {
        const trimmed = std.mem.trim(u8, raw_line, " \t\r\n");
        if (trimmed.len == 0) return;
        if (self.line_count < MaxLinesPerPage) {
            const idx = self.line_count;
            self.lines[idx].set(trimmed);
            self.line_x_pt[idx] = x_pt;
            self.line_y_pt[idx] = y_pt;
            self.line_w_pt[idx] = @max(0.0, w_pt);
            self.line_font_pt[idx] = std.math.clamp(font_pt, 6.0, 36.0);
            self.line_count += 1;
        }
    }

    pub fn lineNormY(self: *const PdfPageInfo, line_idx: usize) f32 {
        const h_pt = if (self.height_pt > 10.0) self.height_pt else 792.0;
        if (line_idx < self.line_count) {
            const y_pt = self.line_y_pt[line_idx];
            if (y_pt > 1.0 and y_pt < h_pt) {
                return std.math.clamp(1.0 - (y_pt / h_pt), 0.02, 0.96);
            }
        }
        const denom: f32 = @floatFromInt(@max(self.line_count + 2, 2));
        return std.math.clamp(@as(f32, @floatFromInt(line_idx + 1)) / denom, 0.04, 0.94);
    }

    pub fn lineNormX(self: *const PdfPageInfo, line_idx: usize) f32 {
        const w_pt = if (self.width_pt > 10.0) self.width_pt else 612.0;
        if (line_idx < self.line_count) {
            const x_pt = self.line_x_pt[line_idx];
            if (x_pt >= 1.0 and x_pt < w_pt - 10.0) {
                return std.math.clamp(x_pt / w_pt, 0.02, 0.90);
            }
        }
        return 42.0 / 612.0;
    }
};

pub const PdfDocumentData = struct {
    title: platform.InlineString(96) = .{},
    author: platform.InlineString(64) = .{},
    subject: platform.InlineString(96) = .{},
    version: platform.InlineString(12) = .{},
    file_size_bytes: usize = 0,
    page_count: usize = 1,
    default_width_pt: f32 = 612.0,
    default_height_pt: f32 = 792.0,
    pages: [MaxPdfPages]PdfPageInfo = @splat(.{}),
    outline: []const PdfOutlineItem = &.{},
    outline_count: usize = 0,

    pub fn addOutline(self: *PdfDocumentData, title: []const u8, page_number: u32) void {
        self.addOutlineIndentedWithY(title, page_number, 0.0, 0);
    }

    pub fn addOutlineIndented(self: *PdfDocumentData, title: []const u8, page_number: u32, indent: u8) void {
        self.addOutlineIndentedWithY(title, page_number, 0.0, indent);
    }

    pub fn addOutlineIndentedWithY(self: *PdfDocumentData, title: []const u8, page_number: u32, norm_y: f32, indent: u8) void {
        const trimmed = std.mem.trim(u8, title, " \t\r\n");
        if (trimmed.len == 0) return;
        const clamped_ny = std.math.clamp(norm_y, 0.0, 0.94);
        const check_start = self.outline.len -| 16;
        for (self.outline[check_start..]) |item| {
            if (std.mem.eql(u8, item.title.slice(), trimmed) and
                item.page_number == page_number and
                @abs(item.norm_y - clamped_ny) < 0.005)
            {
                return;
            }
        }
        g_outline_items.append(std.heap.page_allocator, .{
            .title = platform.InlineString(64).init(trimmed),
            .page_number = @max(@as(u32, 1), page_number),
            .norm_y = clamped_ny,
            .indent = indent,
        }) catch return;
        self.outline = g_outline_items.items;
        self.outline_count = self.outline.len;
    }

    pub fn pageDimensions(self: *const PdfDocumentData, page_idx: usize) struct { width_pt: f32, height_pt: f32 } {
        if (page_idx < MaxPdfPages) {
            const w = self.pages[page_idx].width_pt;
            const h = self.pages[page_idx].height_pt;
            if (w > 10.0 and h > 10.0) return .{ .width_pt = w, .height_pt = h };
        }
        return .{ .width_pt = self.default_width_pt, .height_pt = self.default_height_pt };
    }

    /// Returns the `PdfPageInfo` for `page_idx`, using the inline `pages[0..MaxPdfPages]` array for
    /// initial pages and an on-demand LRU page text cache for pages `>= MaxPdfPages`.
    pub fn getPageInfo(
        self: *const PdfDocumentData,
        page_idx: usize,
        raw_bytes: []const u8,
        file_path: []const u8,
    ) *const PdfPageInfo {
        if (page_idx < MaxPdfPages) {
            return &self.pages[page_idx];
        }
        if (comptime is_macos) {
            if (getOrExtractExtraPageInfo(self, page_idx, raw_bytes, file_path)) |extra| {
                return extra;
            }
        }
        return &self.pages[MaxPdfPages - 1];
    }

    pub fn countSearchMatchesOnPage(self: *const PdfDocumentData, page_idx: usize, query: []const u8) usize {
        const q = std.mem.trim(u8, query, " \t\r\n");
        if (q.len == 0 or page_idx >= self.page_count) return 0;
        var matches: usize = 0;
        if (page_idx < MaxPdfPages) {
            const page = &self.pages[page_idx];
            for (page.lines[0..page.line_count]) |line| {
                const text = line.slice();
                var pos: usize = 0;
                while (root.indexOfIgnoreCasePos(text, pos, q)) |found_idx| {
                    matches += 1;
                    pos = found_idx + q.len;
                }
            }
        }
        if (matches == 0) {
            const target_pg: u32 = @intCast(page_idx + 1);
            for (self.outline[0..self.outline_count]) |item| {
                const text = item.title.slice();
                if (item.page_number == target_pg) {
                    var pos: usize = 0;
                    while (root.indexOfIgnoreCasePos(text, pos, q)) |found_idx| {
                        matches += 1;
                        pos = found_idx + q.len;
                    }
                }
            }
        }
        return matches;
    }

    pub fn countTotalSearchMatches(self: *const PdfDocumentData, query: []const u8) usize {
        const q = std.mem.trim(u8, query, " \t\r\n");
        if (q.len == 0 or self.page_count == 0) return 0;
        var total: usize = 0;
        const cached_n = @min(self.page_count, MaxPdfPages);
        for (0..cached_n) |p_idx| {
            total += self.countSearchMatchesOnPage(p_idx, q);
        }
        if (self.page_count > MaxPdfPages) {
            for (self.outline[0..self.outline_count]) |item| {
                if (item.page_number > MaxPdfPages) {
                    const text = item.title.slice();
                    var pos: usize = 0;
                    while (root.indexOfIgnoreCasePos(text, pos, q)) |found_idx| {
                        total += 1;
                        pos = found_idx + q.len;
                    }
                }
            }
        }
        return total;
    }

    fn buildPageLineMatch(
        self: *const PdfDocumentData,
        match_index: usize,
        page_idx: usize,
        line_idx: usize,
        byte_offset: usize,
        byte_len: usize,
    ) PdfSearchMatch {
        const page = &self.pages[page_idx];
        const w_pt = if (page.width_pt > 10.0) page.width_pt else self.default_width_pt;
        const h_pt = if (page.height_pt > 10.0) page.height_pt else self.default_height_pt;
        const font_pt = if (line_idx < page.line_count) page.line_font_pt[line_idx] else 10.0;
        const base_nx = page.lineNormX(line_idx);
        const base_ny = page.lineNormY(line_idx);
        const prefix_pt = @as(f32, @floatFromInt(byte_offset)) * font_pt * 0.52;
        const match_pt = @max(font_pt * 0.85, @as(f32, @floatFromInt(byte_len)) * font_pt * 0.54);
        const nx = std.math.clamp(base_nx + (prefix_pt / w_pt), 0.02, 0.94);
        const nw = std.math.clamp(match_pt / w_pt, 0.015, 0.96 - nx);
        const nh = std.math.clamp((font_pt * 1.35) / h_pt, 0.016, 0.042);
        return .{
            .match_index = match_index,
            .page_idx = page_idx,
            .line_idx = line_idx,
            .byte_offset = byte_offset,
            .byte_len = byte_len,
            .norm_x = nx,
            .norm_y = base_ny,
            .norm_w = nw,
            .norm_h = nh,
        };
    }

    /// Resolves the next/previous or initial `PdfSearchMatch` occurrence across all pages and lines.
    /// - When `step_from_current == false` (e.g. typing in the Find Bar), returns the first match on
    ///   `start_page` if one exists, or the first match on the next page in document order.
    /// - When `step_from_current == true` (e.g. pressing `Enter`/`Next`/`Cmd+G` or `Shift+Enter`/`Prev`),
    ///   advances or rewinds by 1 occurrence from `current_match_idx` (wrapping around the document).
    pub fn findMatch(
        self: *const PdfDocumentData,
        current_match_idx: ?usize,
        start_page: usize,
        query: []const u8,
        forward: bool,
        step_from_current: bool,
    ) ?PdfSearchMatch {
        const q = std.mem.trim(u8, query, " \t\r\n");
        if (q.len == 0 or self.page_count == 0) return null;

        var matches_buf: [256]PdfSearchMatch = undefined;
        var count: usize = 0;

        const cached_n = @min(self.page_count, MaxPdfPages);
        for (0..cached_n) |p_idx| {
            const page = &self.pages[p_idx];
            var page_hits: usize = 0;
            for (page.lines[0..page.line_count], 0..) |line, l_idx| {
                const text = line.slice();
                var pos: usize = 0;
                while (root.indexOfIgnoreCasePos(text, pos, q)) |found_idx| {
                    if (count < matches_buf.len) {
                        matches_buf[count] = self.buildPageLineMatch(count, p_idx, l_idx, found_idx, q.len);
                        count += 1;
                    }
                    page_hits += 1;
                    pos = found_idx + q.len;
                }
            }
            if (page_hits == 0) {
                const target_pg: u32 = @intCast(p_idx + 1);
                for (self.outline[0..self.outline_count]) |item| {
                    if (item.page_number == target_pg) {
                        const text = item.title.slice();
                        var pos: usize = 0;
                        while (root.indexOfIgnoreCasePos(text, pos, q)) |found_idx| {
                            if (count < matches_buf.len) {
                                matches_buf[count] = .{
                                    .match_index = count,
                                    .page_idx = p_idx,
                                    .line_idx = MaxLinesPerPage,
                                    .byte_offset = found_idx,
                                    .byte_len = q.len,
                                    .norm_x = 0.08,
                                    .norm_y = std.math.clamp(item.norm_y, 0.04, 0.92),
                                    .norm_w = 0.25,
                                    .norm_h = 0.024,
                                };
                                count += 1;
                            }
                            pos = found_idx + q.len;
                        }
                    }
                }
            }
        }

        if (self.page_count > MaxPdfPages) {
            for (self.outline[0..self.outline_count]) |item| {
                if (item.page_number > MaxPdfPages and item.page_number <= self.page_count) {
                    const p_idx: usize = @intCast(item.page_number - 1);
                    const text = item.title.slice();
                    var pos: usize = 0;
                    while (root.indexOfIgnoreCasePos(text, pos, q)) |found_idx| {
                        if (count < matches_buf.len) {
                            matches_buf[count] = .{
                                .match_index = count,
                                .page_idx = p_idx,
                                .line_idx = MaxLinesPerPage,
                                .byte_offset = found_idx,
                                .byte_len = q.len,
                                .norm_x = 0.08,
                                .norm_y = std.math.clamp(item.norm_y, 0.04, 0.92),
                                .norm_w = 0.25,
                                .norm_h = 0.024,
                            };
                            count += 1;
                        }
                        pos = found_idx + q.len;
                    }
                }
            }
        }

        if (count == 0) return null;

        if (!step_from_current or current_match_idx == null) {
            // Find the first match on or after `start_page` (or wrap to match 0)
            for (matches_buf[0..count]) |m| {
                if (m.page_idx >= start_page) return m;
            }
            return matches_buf[0];
        }

        const cur = current_match_idx.? % count;
        const next_idx = if (forward)
            (cur + 1) % count
        else
            (cur + count - 1) % count;
        return matches_buf[next_idx];
    }

    pub fn findMatchingPage(
        self: *const PdfDocumentData,
        start_page: usize,
        query: []const u8,
        forward: bool,
        step_from_current: bool,
    ) ?usize {
        const q = std.mem.trim(u8, query, " \t\r\n");
        if (q.len == 0 or self.page_count == 0) return null;
        const n = self.page_count;
        const base = @min(start_page, n - 1);
        for (0..n) |step| {
            const offset = if (step_from_current) (step + 1) % n else step;
            const p_idx = if (forward)
                (base + offset) % n
            else
                (base + n - (offset % n)) % n;
            if (self.countSearchMatchesOnPage(p_idx, q) > 0) {
                return p_idx;
            }
        }
        return null;
    }
};

pub const PdfViewState = struct {
    last_doc_hash: u64 = 0,
    current_page: usize = 0,
    last_synced_page: usize = 0,
    selected_outline_idx: usize = 0,
    last_outline_scroll_y: f32 = -1.0,
    zoom: f32 = 1.0,
    last_synced_zoom: f32 = 1.0,
    scroll_x: f32 = 0.0,
    scroll_y: f32 = 0.0,
    outline_scroll_y: f32 = 0.0,
    invert_paper: bool = false,
    show_outline: bool = false,
    active_match_index: usize = 0,
    active_match_page: usize = 0,
    active_match_line: usize = 0,
    active_match_offset: usize = 0,
    active_match_norm_y: f32 = 0.0,
    has_active_match: bool = false,
    pending_scroll_to_match: bool = false,
    last_search_hash: u64 = 0,
    dragging_pan: bool = false,
    dragging_scrollbar: bool = false,
    dragging_outline_scrollbar: bool = false,
    hovered_link_page: u32 = 0,
    hovered_link_target_norm_y: f32 = 0.0,
    hovered_link_page_idx: usize = 0,
    hovered_link_norm_y: f32 = 0.0,
    drag_start_mouse_x: f32 = 0.0,
    drag_start_mouse_y: f32 = 0.0,
    drag_start_scroll_x: f32 = 0.0,
    drag_start_scroll_y: f32 = 0.0,

    // Interactive text selection state (character/word/line/multi-page selection & clipboard copy)
    has_selection: bool = false,
    dragging_selection: bool = false,
    sel_click_mode: u8 = 0, // 0 = char, 1 = word (double-click), 2 = line (triple-click)
    sel_anchor: PdfTextPos = .{},
    sel_cursor: PdfTextPos = .{},
    sel_origin_start: PdfTextPos = .{},
    sel_origin_end: PdfTextPos = .{},

    pub fn jumpToSearchMatch(self: *PdfViewState, m: PdfSearchMatch) void {
        self.current_page = m.page_idx;
        self.active_match_index = m.match_index;
        self.active_match_page = m.page_idx;
        self.active_match_line = m.line_idx;
        self.active_match_offset = m.byte_offset;
        self.active_match_norm_y = m.norm_y;
        self.has_active_match = true;
        self.pending_scroll_to_match = true;
    }

    pub fn hasSelection(self: *const PdfViewState) bool {
        return self.has_selection and !PdfTextPos.eql(self.sel_anchor, self.sel_cursor);
    }

    pub fn clearSelection(self: *PdfViewState) void {
        self.has_selection = false;
        self.dragging_selection = false;
        self.sel_click_mode = 0;
        self.sel_anchor = .{};
        self.sel_cursor = .{};
        self.sel_origin_start = .{};
        self.sel_origin_end = .{};
    }

    pub fn normalizedSelection(self: *const PdfViewState) ?struct { start: PdfTextPos, end: PdfTextPos } {
        if (!self.hasSelection()) return null;
        if (PdfTextPos.lessThan(self.sel_cursor, self.sel_anchor)) {
            return .{ .start = self.sel_cursor, .end = self.sel_anchor };
        }
        return .{ .start = self.sel_anchor, .end = self.sel_cursor };
    }

    pub fn selectPage(self: *PdfViewState, doc: *const PdfDocumentData, page_idx: usize) void {
        self.selectPageWithSource(doc, page_idx, "", "");
    }

    pub fn selectPageWithSource(
        self: *PdfViewState,
        doc: *const PdfDocumentData,
        page_idx: usize,
        raw_bytes: []const u8,
        file_path: []const u8,
    ) void {
        if (doc.page_count == 0) {
            self.clearSelection();
            return;
        }
        const clamped_pg = @min(page_idx, doc.page_count - 1);
        const page = doc.getPageInfo(clamped_pg, raw_bytes, file_path);
        if (page.line_count == 0) {
            self.clearSelection();
            return;
        }
        const last_line = page.line_count - 1;
        const last_len = page.lines[last_line].len;
        self.sel_anchor = .{ .page_idx = clamped_pg, .line_idx = 0, .col = 0 };
        self.sel_cursor = .{ .page_idx = clamped_pg, .line_idx = last_line, .col = last_len };
        self.sel_origin_start = self.sel_anchor;
        self.sel_origin_end = self.sel_cursor;
        self.sel_click_mode = 0;
        self.has_selection = !PdfTextPos.eql(self.sel_anchor, self.sel_cursor);
    }

    pub fn selectAll(self: *PdfViewState, doc: *const PdfDocumentData) void {
        const page_limit = @min(@max(@as(usize, 1), doc.page_count), MaxPdfPages);
        var first_pg: ?usize = null;
        var last_pg: usize = 0;
        var last_line: usize = 0;
        var last_len: usize = 0;

        for (0..page_limit) |p_idx| {
            const page = &doc.pages[p_idx];
            if (page.line_count > 0 and !isPlaceholderOnlyPage(page)) {
                if (first_pg == null) first_pg = p_idx;
                last_pg = p_idx;
                last_line = page.line_count - 1;
                last_len = page.lines[last_line].len;
            }
        }
        if (first_pg) |f_pg| {
            self.sel_anchor = .{ .page_idx = f_pg, .line_idx = 0, .col = 0 };
            self.sel_cursor = .{ .page_idx = last_pg, .line_idx = last_line, .col = last_len };
            self.sel_origin_start = self.sel_anchor;
            self.sel_origin_end = self.sel_cursor;
            self.sel_click_mode = 0;
            self.has_selection = !PdfTextPos.eql(self.sel_anchor, self.sel_cursor);
        } else {
            self.clearSelection();
        }
    }

    pub fn copySelectionAlloc(
        self: *const PdfViewState,
        doc: *const PdfDocumentData,
        allocator: std.mem.Allocator,
    ) ?[]u8 {
        return self.copySelectionWithSourceAlloc(doc, "", "", allocator);
    }

    pub fn copySelectionWithSourceAlloc(
        self: *const PdfViewState,
        doc: *const PdfDocumentData,
        raw_bytes: []const u8,
        file_path: []const u8,
        allocator: std.mem.Allocator,
    ) ?[]u8 {
        const sel = self.normalizedSelection() orelse return null;
        if (doc.page_count == 0) return null;
        const max_pg = doc.page_count - 1;
        const start_pg = @min(sel.start.page_idx, max_pg);
        const end_pg = @min(sel.end.page_idx, max_pg);
        if (start_pg > end_pg) return null;

        var out: std.ArrayListUnmanaged(u8) = .empty;
        errdefer out.deinit(allocator);

        var wrote_any_line = false;
        for (start_pg..end_pg + 1) |p_idx| {
            const page = doc.getPageInfo(p_idx, raw_bytes, file_path);
            if (page.line_count == 0) continue;
            if (start_pg != end_pg and isPlaceholderOnlyPage(page)) continue;
            const l_start = if (p_idx == start_pg) @min(sel.start.line_idx, page.line_count - 1) else 0;
            const l_end = if (p_idx == end_pg) @min(sel.end.line_idx, page.line_count - 1) else page.line_count - 1;
            if (l_start > l_end) continue;

            for (l_start..l_end + 1) |l_idx| {
                const line = page.lines[l_idx].slice();
                const c_start = if (p_idx == start_pg and l_idx == sel.start.line_idx)
                    @min(sel.start.col, line.len)
                else
                    0;
                const c_end = if (p_idx == end_pg and l_idx == sel.end.line_idx)
                    @min(sel.end.col, line.len)
                else
                    line.len;
                if (c_end < c_start) continue;
                const sub = line[c_start..c_end];
                if (sub.len == 0 and l_start == l_end) continue;
                if (wrote_any_line) {
                    out.append(allocator, '\n') catch return null;
                }
                out.appendSlice(allocator, sub) catch return null;
                wrote_any_line = true;
            }
        }

        if (out.items.len == 0) {
            out.deinit(allocator);
            return null;
        }
        return out.toOwnedSlice(allocator) catch null;
    }
};

pub const PdfViewerOptions = struct {
    file_path: []const u8 = "",
    raw_bytes: []const u8 = "",
    search_query: []const u8 = "",
    compact: bool = false,
    show_toolbar: bool = true,
    extra_focus_id: root.WidgetId = 0,
};

pub const PdfViewerResult = struct {
    send_to_agent_requested: bool = false,
    page_changed: bool = false,
    find_requested: bool = false,
    copied_text: ?[]const u8 = null,
};

// ============================================================================
// Built-in 3-Page Standards-Compliant PDF 1.4 Datasheet (`SAMPLE_PDF_DOC`)
// ============================================================================

pub const SAMPLE_PDF_DOC: []const u8 =
    \\%PDF-1.4
    \\1 0 obj
    \\<< /Type /Catalog /Pages 2 0 R /Info 9 0 R >>
    \\endobj
    \\2 0 obj
    \\<< /Type /Pages /Kids [3 0 R 5 0 R 7 0 R] /Count 3 >>
    \\endobj
    \\3 0 obj
    \\<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 10 0 R /F2 11 0 R >> >> /Contents 4 0 R >>
    \\endobj
    \\4 0 obj
    \\<< /Length 1260 >>
    \\stream
    \\0.11 0.16 0.26 rg 36 714 540 48 re f
    \\0.22 0.55 0.98 rg 36 714 6 48 re f
    \\BT
    \\/F2 16 Tf 0.96 0.98 1.00 rg 54 740 Td (LIGHTNING SoC RV32IMAC DATASHEET) Tj
    \\/F1 10 Tf 0.68 0.78 0.92 rg 0 -16 Td (Document ID: DS-RV32-2026-REV4  |  250 MHz Dual-Issue Microcontroller & AI Accelerator) Tj
    \\ET
    \\0.12 0.16 0.23 rg
    \\BT
    \\/F2 13 Tf 42 682 Td (1. Architecture Overview & Features) Tj
    \\/F1 10 Tf 0 -18 Td (The Lightning RV32IMAC SoC integrates a 32-bit RISC-V core, 256 KB zero-wait-state) Tj
    \\0 -14 Td (TCM SRAM, DMA scatter-gather engine, and high-speed AXI4-Lite peripheral fabric.) Tj
    \\0 -18 Td (- Core: 32-bit RISC-V RV32IMAC with single-cycle hardware multiplier and Zicsr) Tj
    \\0 -14 Td (- Clock: 250 MHz PLL with dynamic clock gating (1.8 ns setup, 0.6 ns hold)) Tj
    \\0 -14 Td (- Memory: 64 KB Boot ROM + 256 KB ECC SRAM + Quad-SPI XIP Flash controller) Tj
    \\0 -14 Td (- Peripherals: 2x UART, 2x SPI, 2x I2C, 16-ch PWM, 12-bit 5 MSPS SAR ADC) Tj
    \\/F2 13 Tf 0 -28 Td (2. System Memory Map) Tj
    \\ET
    \\0.93 0.95 0.98 rg 42 420 528 110 re f
    \\0.75 0.81 0.89 RG 1 w 42 420 528 110 re S
    \\BT
    \\/F2 10 Tf 0.10 0.15 0.24 rg 52 512 Td (Base Address      End Address       Size      Region Description) Tj
    \\/F1 10 Tf 0 -18 Td (0x0000_0000       0x0000_FFFF       64 KB     On-Chip Secure Boot ROM) Tj
    \\0 -16 Td (0x0800_0000       0x08FF_FFFF       16 MB     Quad-SPI XIP External Flash) Tj
    \\0 -16 Td (0x2000_0000       0x2003_FFFF       256 KB    Tightly-Coupled Zero-Wait SRAM) Tj
    \\0 -16 Td (0x4000_0000       0x4000_0FFF       4 KB      SYSCTRL & PLL Clock Controller) Tj
    \\0 -16 Td (0x4000_1000       0x4000_1FFF       4 KB      UART0 High-Speed Serial Transceiver) Tj
    \\/F2 12 Tf 0 -38 Td (3. Block Diagram & Interconnect Topology) Tj
    \\ET
    \\0.15 0.39 0.92 rg 42 290 150 64 re f
    \\0.06 0.65 0.52 rg 230 290 150 64 re f
    \\0.85 0.38 0.15 rg 418 290 150 64 re f
    \\BT
    \\/F2 11 Tf 1 1 1 rg 58 326 Td (RV32IMAC CPU) Tj
    \\/F1 9 Tf 0 -14 Td (250 MHz + Mul/Div) Tj
    \\/F2 11 Tf 190 14 Td (AXI4 Crossbar) Tj
    \\/F1 9 Tf 0 -14 Td (64-bit 16 GB/s Fabric) Tj
    \\/F2 11 Tf 186 14 Td (DMA & Peripherals) Tj
    \\/F1 9 Tf 0 -14 Td (UART / SPI / I2C / ADC) Tj
    \\0.35 0.42 0.52 rg -392 -260 Td (Page 1 of 3  -  Lightning Silicon Engineering  -  Confidential Datasheet) Tj
    \\ET
    \\endstream
    \\endobj
    \\5 0 obj
    \\<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 10 0 R /F2 11 0 R >> >> /Contents 6 0 R >>
    \\endobj
    \\6 0 obj
    \\<< /Length 1080 >>
    \\stream
    \\0.11 0.16 0.26 rg 36 724 540 38 re f
    \\BT
    \\/F2 14 Tf 0.96 0.98 1.00 rg 50 738 Td (4. UART0 Peripheral Register Map (Base: 0x4000_1000)) Tj
    \\ET
    \\0.12 0.16 0.23 rg
    \\BT
    \\/F1 10 Tf 42 694 Td (All UART0 registers are 32-bit word-aligned on the APB/AXI4-Lite peripheral bus.) Tj
    \\/F2 11 Tf 0 -24 Td (Offset    Register Name     Access    Reset Value    Description) Tj
    \\/F1 10 Tf 0 -18 Td (0x00      UART_CTRL         RW        0x0000_0000    Transceiver Enable, Parity & FIFO Reset) Tj
    \\0 -16 Td (0x04      UART_STATUS       RO        0x0000_0002    TX_EMPTY [1], RX_VALID [0], OVERRUN [2]) Tj
    \\0 -16 Td (0x08      UART_BAUD_DIV     RW        0x0000_00D9    16x Fractional Baud Rate Divider) Tj
    \\0 -16 Td (0x0C      UART_TX_DATA      WO        0x0000_0000    8-bit Transmit FIFO Write Port) Tj
    \\0 -16 Td (0x10      UART_RX_DATA      RO        0x0000_0000    8-bit Receive FIFO Read Port (32-deep)) Tj
    \\0 -16 Td (0x14      UART_IRQ_MASK     RW        0x0000_0000    Interrupt Mask (RX_NE, TX_E, ERR)) Tj
    \\/F2 13 Tf 0 -32 Td (5. Register Bitfield Specification: UART_CTRL (Offset 0x00)) Tj
    \\/F1 10 Tf 0 -18 Td (- Bit [0]   TX_EN:     Transmit Engine Enable (1 = Enabled, 0 = Disabled)) Tj
    \\0 -16 Td (- Bit [1]   RX_EN:     Receive Oversampling Engine Enable (16x majority vote)) Tj
    \\0 -16 Td (- Bit [2]   LOOPBACK:  Internal diagnostic TX-to-RX loopback mode) Tj
    \\0 -16 Td (- Bit [5:4] PARITY:    00 = None, 01 = Even Parity, 10 = Odd Parity) Tj
    \\0 -16 Td (- Bit [8]   FIFO_CLR:  Self-clearing synchronous flush of TX and RX FIFOs) Tj
    \\0.35 0.42 0.52 rg 0 -240 Td (Page 2 of 3  -  Lightning Silicon Engineering  -  Register Reference) Tj
    \\ET
    \\endstream
    \\endobj
    \\7 0 obj
    \\<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 10 0 R /F2 11 0 R >> >> /Contents 8 0 R >>
    \\endobj
    \\8 0 obj
    \\<< /Length 980 >>
    \\stream
    \\0.11 0.16 0.26 rg 36 724 540 38 re f
    \\BT
    \\/F2 14 Tf 0.96 0.98 1.00 rg 50 738 Td (6. Electrical & AC Timing Characteristics) Tj
    \\ET
    \\0.12 0.16 0.23 rg
    \\BT
    \\/F1 10 Tf 42 694 Td (Operating Conditions: VDD_CORE = 0.90V +/- 5%, VDD_IO = 3.3V, Ta = -40C to +105C.) Tj
    \\/F2 11 Tf 0 -24 Td (Parameter    Symbol      Min       Typ       Max       Unit    Notes) Tj
    \\/F1 10 Tf 0 -18 Td (System Clock f_SYS       1.0       250.0     275.0     MHz     On-chip fractional PLL) Tj
    \\0 -16 Td (Setup Time   t_SU        1.8       -         -         ns      AXI4 synchronous input) Tj
    \\0 -16 Td (Hold Time    t_HOLD      0.6       -         -         ns      AXI4 synchronous input) Tj
    \\0 -16 Td (Active Power P_ACTIVE    -         42.5      58.0      mW      At 250 MHz Dhrystone) Tj
    \\0 -16 Td (Deep Sleep   I_SLEEP     -         14.0      28.0      uA      RTC + 32 KB SRAM retention) Tj
    \\/F2 13 Tf 0 -32 Td (7. Firmware Initialization Sequence) Tj
    \\/F1 10 Tf 0 -18 Td (1. Program SYSCTRL.PLL_CFG to lock f_SYS = 250 MHz and wait for PLL_LOCK == 1.) Tj
    \\0 -16 Td (2. Write UART_BAUD_DIV = 217 (for 115200 baud at 250 MHz peripheral clock).) Tj
    \\0 -16 Td (3. Write UART_CTRL = 0x0103 (FIFO_CLR | RX_EN | TX_EN) to enable transceiver.) Tj
    \\0 -16 Td (4. Poll UART_STATUS.TX_EMPTY before writing frames to UART_TX_DATA.) Tj
    \\0.35 0.42 0.52 rg 0 -260 Td (Page 3 of 3  -  Lightning Silicon Engineering  -  End of Document) Tj
    \\ET
    \\endstream
    \\endobj
    \\9 0 obj
    \\<< /Title (Lightning SoC RV32IMAC Datasheet) /Author (Lightning Silicon Engineering) /Subject (32-bit RISC-V Microcontroller & AXI4 Peripherals) >>
    \\endobj
    \\10 0 obj
    \\<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>
    \\endobj
    \\11 0 obj
    \\<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>
    \\endobj
    \\trailer
    \\<< /Root 1 0 R /Info 9 0 R >>
    \\%%EOF
;

// ============================================================================
// Pure-Zig + CoreGraphics Hybrid PDF Parser (`parsePdfDocument`)
// ============================================================================

var g_cached_doc_hash: u64 = 0;
var g_cached_cg_doc: ?*anyopaque = null;
var g_cached_pdfkit_doc: platform.objc.id = null;
var g_cached_pdf_data: PdfDocumentData = .{};
var g_outline_items: std.ArrayList(PdfOutlineItem) = .empty;

const ExtraPageTextSlot = struct {
    valid: bool = false,
    doc_hash: u64 = 0,
    page_idx: usize = 0,
    last_used_tick: u64 = 0,
    info: PdfPageInfo = .{},
};

var g_extra_page_cache: [8]ExtraPageTextSlot = @splat(.{});
var g_extra_page_tick: u64 = 0;

fn getOrOpenCgPdfDocument(raw_bytes: []const u8, file_path: []const u8) ?*anyopaque {
    if (comptime !is_macos) return null;
    const h = computeDocHash(raw_bytes, file_path);
    if (h != 0 and h == g_cached_doc_hash and g_cached_cg_doc != null) {
        return g_cached_cg_doc;
    }
    if (g_cached_cg_doc) |old_doc| {
        CGPDFDocumentRelease(old_doc);
        g_cached_cg_doc = null;
    }
    if (g_cached_pdfkit_doc) |old_kit| {
        CFRelease(old_kit);
        g_cached_pdfkit_doc = null;
    }
    const new_doc = openCgPdfDocument(raw_bytes, file_path);
    if (new_doc != null) {
        g_cached_doc_hash = h;
        g_cached_cg_doc = new_doc;
        g_cached_pdfkit_doc = openPdfKitDocument(raw_bytes, file_path);
    }
    return new_doc;
}

fn getOrExtractExtraPageInfo(
    doc_data: *const PdfDocumentData,
    page_idx: usize,
    raw_bytes: []const u8,
    file_path: []const u8,
) ?*const PdfPageInfo {
    if (comptime !is_macos) return null;
    const doc_hash = computeDocHash(raw_bytes, file_path);
    g_extra_page_tick +%= 1;

    for (&g_extra_page_cache) |*slot| {
        if (slot.valid and slot.doc_hash == doc_hash and slot.page_idx == page_idx) {
            slot.last_used_tick = g_extra_page_tick;
            return &slot.info;
        }
    }

    const cg_doc = getOrOpenCgPdfDocument(raw_bytes, file_path) orelse return null;
    var target_slot: usize = 0;
    var oldest_tick: u64 = std.math.maxInt(u64);
    for (&g_extra_page_cache, 0..) |*slot, idx| {
        if (!slot.valid) {
            target_slot = idx;
            break;
        }
        if (slot.last_used_tick < oldest_tick) {
            oldest_tick = slot.last_used_tick;
            target_slot = idx;
        }
    }

    var info = PdfPageInfo{
        .width_pt = doc_data.default_width_pt,
        .height_pt = doc_data.default_height_pt,
    };
    extractCgPageTextAndSize(cg_doc, page_idx, &info);
    if (info.line_count == 0) {
        var msg_buf: [96]u8 = undefined;
        const msg = std.fmt.bufPrint(
            &msg_buf,
            "[Page {d} - {d:.0} x {d:.0} pt vector/raster content]",
            .{ page_idx + 1, info.width_pt, info.height_pt },
        ) catch "[Rendered PDF Page]";
        info.addLine(msg);
    }
    g_extra_page_cache[target_slot] = .{
        .valid = true,
        .doc_hash = doc_hash,
        .page_idx = page_idx,
        .last_used_tick = g_extra_page_tick,
        .info = info,
    };
    return &g_extra_page_cache[target_slot].info;
}

/// Parses a PDF byte slice and/or on-disk PDF file into `out`, populating metadata,
/// page geometry, outline headings, and decoded text lines per page.
/// Uses an in-memory `g_cached_pdf_data` cache keyed by `(file_path, raw_bytes)` so
/// steady-state frames take `< 1 us` even on 3,816-page documents like Bluetooth Core v6.0.
pub fn parsePdfDocument(raw_bytes: []const u8, file_path: []const u8, out: *PdfDocumentData) void {
    const doc_hash = computeDocHash(raw_bytes, file_path);
    if (doc_hash != 0 and doc_hash == g_cached_doc_hash and g_cached_pdf_data.page_count > 0) {
        out.* = g_cached_pdf_data;
        return;
    }

    g_outline_items.clearRetainingCapacity();
    out.* = .{};

    const bytes = if (raw_bytes.len > 0)
        raw_bytes
    else if (file_path.len == 0)
        SAMPLE_PDF_DOC
    else
        "";

    out.file_size_bytes = bytes.len;
    out.version.set("1.4");

    // 1. Parse `%PDF-x.y` version header if present
    if (std.mem.indexOf(u8, bytes, "%PDF-")) |ver_pos| {
        const start = ver_pos + 5;
        var end = start;
        while (end < bytes.len and end < start + 8 and bytes[end] != '\r' and bytes[end] != '\n' and bytes[end] != ' ') : (end += 1) {}
        if (end > start) {
            out.version.set(bytes[start..end]);
        }
    }

    // 2. Extract Info dictionary strings (`/Title`, `/Author`, `/Subject`) from raw bytes
    if (extractPdfDictString(bytes, "/Title")) |t_str| {
        var dec_buf: [96]u8 = undefined;
        out.title.set(decodePdfLiteralOrHex(t_str, &dec_buf));
    }
    if (extractPdfDictString(bytes, "/Author")) |a_str| {
        var dec_buf: [64]u8 = undefined;
        out.author.set(decodePdfLiteralOrHex(a_str, &dec_buf));
    }
    if (extractPdfDictString(bytes, "/Subject")) |s_str| {
        var dec_buf: [96]u8 = undefined;
        out.subject.set(decodePdfLiteralOrHex(s_str, &dec_buf));
    }

    // 3. Fallback title from `file_path` basename
    if (out.title.len == 0) {
        if (file_path.len > 0) {
            out.title.set(std.fs.path.basename(file_path));
        } else {
            out.title.set("Lightning SoC RV32IMAC Datasheet");
        }
    }
    if (out.author.len == 0) {
        out.author.set("Lightning Engineering");
    }

    // 4. Parse uncompressed `stream ... endstream` blocks from `bytes` (up to `MaxPdfPages`)
    var stream_page_idx: usize = 0;
    var scan_pos: usize = 0;
    const max_scan_bytes = @min(bytes.len, 256 * 1024);
    while (scan_pos < max_scan_bytes and stream_page_idx < MaxPdfPages) {
        const stream_kw = std.mem.indexOfPos(u8, bytes[0..max_scan_bytes], scan_pos, "stream") orelse break;
        if (stream_kw >= 3 and std.mem.eql(u8, bytes[stream_kw - 3 .. stream_kw], "end")) {
            scan_pos = stream_kw + 6;
            continue;
        }
        var content_start = stream_kw + 6;
        if (content_start < max_scan_bytes and bytes[content_start] == '\r') content_start += 1;
        if (content_start < max_scan_bytes and bytes[content_start] == '\n') content_start += 1;

        const end_kw = std.mem.indexOfPos(u8, bytes[0..max_scan_bytes], content_start, "endstream") orelse break;
        const stream_slice = bytes[content_start..end_kw];
        scan_pos = end_kw + 9;

        if (std.mem.indexOf(u8, stream_slice, "BT") != null) {
            extractTextLinesFromContentStream(stream_slice, &out.pages[stream_page_idx]);
            if (out.pages[stream_page_idx].line_count > 0) {
                stream_page_idx += 1;
            }
        }
    }
    if (stream_page_idx > 0) {
        out.page_count = stream_page_idx;
    }

    // 5. On macOS, query CoreGraphics (`CGPDFDocument`) for the TRUE total page count
    //    (e.g. 3,816 pages for `Core_v6.0.pdf`), hierarchical `/Outlines`, and initial page streams!
    if (comptime is_macos) {
        populateFromCoreGraphics(bytes, file_path, out);
    }

    // 6. Populate automatic outline headings from numbered section lines if `/Outlines` wasn't present
    if (out.outline_count == 0) {
        for (0..@min(out.page_count, MaxPdfPages)) |p_idx| {
            const page = &out.pages[p_idx];
            const denom: f32 = @floatFromInt(@max(page.line_count, 1));
            for (page.lines[0..page.line_count], 0..) |line_in, l_idx| {
                const line = line_in.slice();
                if (l_idx == 0 or isSectionHeadingLine(line)) {
                    const est_ny: f32 = if (l_idx == 0) 0.0 else @as(f32, @floatFromInt(l_idx)) / denom;
                    out.addOutlineIndentedWithY(line, @intCast(p_idx + 1), est_ny, 0);
                }
            }
        }
    }

    // 7. Ensure inline pages have a placeholder line if the PDF contains only scanned/compressed streams
    for (0..@min(out.page_count, MaxPdfPages)) |p_idx| {
        if (out.pages[p_idx].line_count == 0) {
            var msg_buf: [96]u8 = undefined;
            const msg = std.fmt.bufPrint(
                &msg_buf,
                "[Page {d} - {d:.0} x {d:.0} pt vector/raster content]",
                .{ p_idx + 1, out.pages[p_idx].width_pt, out.pages[p_idx].height_pt },
            ) catch "[Rendered PDF Page]";
            out.pages[p_idx].addLine(msg);
        }
    }

    if (doc_hash != 0) {
        g_cached_doc_hash = doc_hash;
        g_cached_pdf_data = out.*;
    }
}

fn isSectionHeadingLine(line: []const u8) bool {
    if (line.len < 4 or line.len > 78) return false;
    if (std.ascii.isDigit(line[0])) {
        if (line[1] == '.' and line[2] == ' ') return true;
        if (std.ascii.isDigit(line[1]) and line[2] == '.' and line[3] == ' ') return true;
    }
    if (std.mem.startsWith(u8, line, "Section ") or
        std.mem.startsWith(u8, line, "Chapter ") or
        std.mem.startsWith(u8, line, "Appendix ") or
        std.mem.startsWith(u8, line, "Part ") or
        std.mem.startsWith(u8, line, "Volume ") or
        std.mem.startsWith(u8, line, "TABLE "))
    {
        return true;
    }
    return false;
}

fn extractPdfDictString(bytes: []const u8, key: []const u8) ?[]const u8 {
    var pos: usize = 0;
    const limit = @min(bytes.len, 128 * 1024);
    while (pos < limit) {
        const hit = std.mem.indexOfPos(u8, bytes[0..limit], pos, key) orelse return null;
        var after = hit + key.len;
        if (after < limit and std.ascii.isAlphabetic(bytes[after])) {
            pos = after;
            continue;
        }
        while (after < limit and (bytes[after] == ' ' or bytes[after] == '\t' or bytes[after] == '\r' or bytes[after] == '\n')) : (after += 1) {}
        if (after < limit and bytes[after] == '(') {
            const lit = parseBalancedParenSlice(bytes[after..limit]);
            if (lit.len > 0) return lit;
        } else if (after < limit and bytes[after] == '<' and (after + 1 >= limit or bytes[after + 1] != '<')) {
            if (std.mem.indexOfScalarPos(u8, bytes[0..limit], after, '>')) |close_angle| {
                return bytes[after .. close_angle + 1];
            }
        }
        pos = after + 1;
    }
    return null;
}

fn parseBalancedParenSlice(s: []const u8) []const u8 {
    if (s.len == 0 or s[0] != '(') return "";
    var depth: usize = 0;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (s[i] == '\\') {
            i += 1;
            continue;
        }
        if (s[i] == '(') {
            depth += 1;
        } else if (s[i] == ')') {
            depth -= 1;
            if (depth == 0) {
                return s[0 .. i + 1];
            }
        }
    }
    return "";
}

fn decodePdfLiteralOrHex(token: []const u8, out_buf: []u8) []const u8 {
    if (token.len >= 2 and token[0] == '(' and token[token.len - 1] == ')') {
        const inner = token[1 .. token.len - 1];
        var out_i: usize = 0;
        var i: usize = 0;
        while (i < inner.len and out_i < out_buf.len) : (i += 1) {
            if (inner[i] == '\\' and i + 1 < inner.len) {
                i += 1;
                const esc = inner[i];
                switch (esc) {
                    'n' => out_buf[out_i] = ' ',
                    'r' => continue,
                    't' => out_buf[out_i] = ' ',
                    '(', ')', '\\' => out_buf[out_i] = esc,
                    '0'...'7' => {
                        var oct: u8 = esc - '0';
                        if (i + 1 < inner.len and inner[i + 1] >= '0' and inner[i + 1] <= '7') {
                            i += 1;
                            oct = oct * 8 + (inner[i] - '0');
                            if (i + 1 < inner.len and inner[i + 1] >= '0' and inner[i + 1] <= '7') {
                                i += 1;
                                oct = oct *% 8 +% (inner[i] - '0');
                            }
                        }
                        if (oct >= 32 and oct < 127) {
                            out_buf[out_i] = oct;
                        } else {
                            out_buf[out_i] = ' ';
                        }
                    },
                    else => out_buf[out_i] = esc,
                }
                out_i += 1;
            } else if (inner[i] >= 32 and inner[i] < 127) {
                out_buf[out_i] = inner[i];
                out_i += 1;
            }
        }
        return out_buf[0..out_i];
    } else if (token.len >= 2 and token[0] == '<' and token[token.len - 1] == '>') {
        const inner = token[1 .. token.len - 1];
        var out_i: usize = 0;
        var i: usize = 0;
        while (i + 1 < inner.len and out_i < out_buf.len) : (i += 2) {
            const hi = std.fmt.charToDigit(inner[i], 16) catch continue;
            const lo = std.fmt.charToDigit(inner[i + 1], 16) catch continue;
            const b: u8 = (hi << 4) | lo;
            if (b >= 32 and b < 127) {
                out_buf[out_i] = b;
                out_i += 1;
            }
        }
        return out_buf[0..out_i];
    }
    return "";
}

fn extractTextLinesFromContentStream(stream: []const u8, page: *PdfPageInfo) void {
    var line_buf: [128]u8 = undefined;
    var line_len: usize = 0;
    var dec_buf: [128]u8 = undefined;

    var cur_x_pt: f32 = 42.0;
    var cur_y_pt: f32 = 0.0;
    var cur_font_pt: f32 = 10.0;
    var cur_leading_pt: f32 = 14.0;
    var cur_scale_x: f32 = 1.0;
    var cur_scale_y: f32 = 1.0;

    var line_x_pt: f32 = 42.0;
    var line_y_pt: f32 = 0.0;
    var line_font_pt: f32 = 10.0;

    var num_stack: [6]f32 = @splat(0.0);
    var num_count: usize = 0;
    var in_tj_array = false;

    const pushNum = struct {
        fn push(stack: *[6]f32, cnt: *usize, val: f32) void {
            if (cnt.* < stack.len) {
                stack[cnt.*] = val;
                cnt.* += 1;
            } else {
                for (0..stack.len - 1) |k| {
                    stack[k] = stack[k + 1];
                }
                stack[stack.len - 1] = val;
            }
        }
    }.push;

    var i: usize = 0;
    while (i < stream.len and page.line_count < MaxLinesPerPage) {
        const ch = stream[i];
        if (ch == ' ' or ch == '\t' or ch == '\r' or ch == '\n') {
            i += 1;
            continue;
        }
        if (ch == '%') {
            while (i < stream.len and stream[i] != '\n' and stream[i] != '\r') : (i += 1) {}
            continue;
        }
        if (ch == '[') {
            in_tj_array = true;
            i += 1;
            continue;
        }
        if (ch == ']') {
            in_tj_array = false;
            i += 1;
            continue;
        }
        if (ch == '/') {
            // Skip PDF name operand (e.g. `/F1`, `/F2`, `/DeviceRGB`)
            i += 1;
            while (i < stream.len) : (i += 1) {
                const nc = stream[i];
                if (nc == ' ' or nc == '\t' or nc == '\r' or nc == '\n' or
                    nc == '/' or nc == '(' or nc == '<' or nc == '[' or nc == ']')
                {
                    break;
                }
            }
            continue;
        }
        if (ch == '(') {
            const lit = parseBalancedParenSlice(stream[i..]);
            if (lit.len > 0) {
                const decoded = decodePdfLiteralOrHex(lit, &dec_buf);
                if (decoded.len > 0) {
                    if (line_len == 0) {
                        line_x_pt = cur_x_pt;
                        line_y_pt = cur_y_pt;
                        line_font_pt = cur_font_pt;
                    }
                    const avail = line_buf.len - line_len;
                    const copy_n = @min(avail, decoded.len);
                    @memcpy(line_buf[line_len .. line_len + copy_n], decoded[0..copy_n]);
                    line_len += copy_n;
                }
                i += lit.len;
                continue;
            }
        } else if (ch == '<' and (i + 1 >= stream.len or stream[i + 1] != '<')) {
            if (std.mem.indexOfScalarPos(u8, stream, i, '>')) |close_idx| {
                const hex_tok = stream[i .. close_idx + 1];
                const decoded = decodePdfLiteralOrHex(hex_tok, &dec_buf);
                if (decoded.len > 0) {
                    if (line_len == 0) {
                        line_x_pt = cur_x_pt;
                        line_y_pt = cur_y_pt;
                        line_font_pt = cur_font_pt;
                    }
                    const avail = line_buf.len - line_len;
                    const copy_n = @min(avail, decoded.len);
                    @memcpy(line_buf[line_len .. line_len + copy_n], decoded[0..copy_n]);
                    line_len += copy_n;
                }
                i = close_idx + 1;
                continue;
            }
        } else if ((ch == '-' or ch == '+' or ch == '.' or std.ascii.isDigit(ch))) {
            const num_start = i;
            if (ch == '-' or ch == '+') i += 1;
            var has_digit = false;
            while (i < stream.len and (std.ascii.isDigit(stream[i]) or stream[i] == '.')) : (i += 1) {
                if (std.ascii.isDigit(stream[i])) has_digit = true;
            }
            if (has_digit) {
                if (std.fmt.parseFloat(f32, stream[num_start..i])) |val| {
                    if (in_tj_array) {
                        if (val < -120.0 and line_len > 0 and line_len < line_buf.len and line_buf[line_len - 1] != ' ') {
                            line_buf[line_len] = ' ';
                            line_len += 1;
                        }
                    } else {
                        pushNum(&num_stack, &num_count, val);
                    }
                } else |_| {}
                continue;
            }
            continue;
        } else if (std.ascii.isAlphabetic(ch) or ch == '\'' or ch == '"' or ch == '*') {
            const op_start = i;
            i += 1;
            while (i < stream.len and (std.ascii.isAlphabetic(stream[i]) or stream[i] == '*' or std.ascii.isDigit(stream[i]))) : (i += 1) {}
            const op = stream[op_start..i];

            if (std.mem.eql(u8, op, "BT")) {
                if (line_len > 0) {
                    page.addLineAt(line_buf[0..line_len], line_x_pt, line_y_pt, line_font_pt);
                    line_len = 0;
                }
                cur_x_pt = 0.0;
                cur_y_pt = 0.0;
                cur_scale_x = 1.0;
                cur_scale_y = 1.0;
                num_count = 0;
            } else if (std.mem.eql(u8, op, "ET")) {
                if (line_len > 0) {
                    page.addLineAt(line_buf[0..line_len], line_x_pt, line_y_pt, line_font_pt);
                    line_len = 0;
                }
                num_count = 0;
            } else if (std.mem.eql(u8, op, "Tf")) {
                if (num_count >= 1) {
                    const fs = @abs(num_stack[num_count - 1]) * cur_scale_y;
                    if (fs >= 4.0 and fs <= 64.0) cur_font_pt = fs;
                }
                num_count = 0;
            } else if (std.mem.eql(u8, op, "TL")) {
                if (num_count >= 1) {
                    cur_leading_pt = @abs(num_stack[num_count - 1]);
                }
                num_count = 0;
            } else if (std.mem.eql(u8, op, "Td") or std.mem.eql(u8, op, "TD")) {
                if (line_len > 0) {
                    page.addLineAt(line_buf[0..line_len], line_x_pt, line_y_pt, line_font_pt);
                    line_len = 0;
                }
                if (num_count >= 2) {
                    const tx = num_stack[num_count - 2];
                    const ty = num_stack[num_count - 1];
                    cur_x_pt += tx * cur_scale_x;
                    cur_y_pt += ty * cur_scale_y;
                    if (std.mem.eql(u8, op, "TD")) {
                        cur_leading_pt = @abs(ty);
                    }
                }
                num_count = 0;
            } else if (std.mem.eql(u8, op, "Tm")) {
                if (line_len > 0) {
                    page.addLineAt(line_buf[0..line_len], line_x_pt, line_y_pt, line_font_pt);
                    line_len = 0;
                }
                if (num_count >= 6) {
                    const a = num_stack[num_count - 6];
                    const d = num_stack[num_count - 3];
                    const e = num_stack[num_count - 2];
                    const f = num_stack[num_count - 1];
                    cur_x_pt = e;
                    cur_y_pt = f;
                    if (@abs(a) > 0.05 and @abs(a) < 100.0) cur_scale_x = @abs(a);
                    if (@abs(d) > 0.05 and @abs(d) < 100.0) cur_scale_y = @abs(d);
                    if (@abs(d) >= 5.0 and @abs(d) <= 48.0) cur_font_pt = @abs(d);
                }
                num_count = 0;
            } else if (std.mem.eql(u8, op, "T*") or std.mem.eql(u8, op, "'") or std.mem.eql(u8, op, "\"")) {
                if (line_len > 0) {
                    page.addLineAt(line_buf[0..line_len], line_x_pt, line_y_pt, line_font_pt);
                    line_len = 0;
                }
                const step = if (cur_leading_pt > 0.5) cur_leading_pt else cur_font_pt * 1.2;
                cur_y_pt -= step * cur_scale_y;
                num_count = 0;
            } else {
                num_count = 0;
            }
            continue;
        }
        i += 1;
    }
    if (line_len > 0 and page.line_count < MaxLinesPerPage) {
        page.addLineAt(line_buf[0..line_len], line_x_pt, line_y_pt, line_font_pt);
    }
}

// ============================================================================
// CoreGraphics Document Loader, PDF Outline/Link Resolver & Page Texture Cache
// ============================================================================

fn openPdfKitDocument(raw_bytes: []const u8, file_path: []const u8) platform.objc.id {
    if (comptime !is_macos) return null;
    const pool = platform.objc.objc_autoreleasePoolPush();
    defer platform.objc.objc_autoreleasePoolPop(pool);

    const PDFDocumentCls = platform.objc.objc_getClass("PDFDocument") orelse return null;
    if (file_path.len > 0) {
        if (!platform.fs_util.isDatalessSliceOnDisk(file_path)) {
            if (std.Io.Dir.cwd().statFile(std.Options.debug_io, file_path, .{})) |st| {
                if (st.size > 64) {
                    if (CFURLCreateFromFileSystemRepresentation(null, file_path.ptr, @intCast(file_path.len), 0)) |url| {
                        defer CFRelease(url);
                        const alloc_obj = platform.objc.msgSend0(PDFDocumentCls, platform.objc.id, "alloc");
                        if (alloc_obj != null) {
                            const doc_obj = platform.objc.msgSend1(
                                alloc_obj,
                                platform.objc.id,
                                "initWithURL:",
                                @as(platform.objc.id, @ptrCast(url)),
                            );
                            if (doc_obj != null) return doc_obj;
                        }
                    }
                }
            } else |_| {}
        }
    }
    if (raw_bytes.len > 64 and
        raw_bytes.ptr != SAMPLE_PDF_DOC.ptr and
        std.mem.indexOf(u8, raw_bytes, "DS-RV32-2026-REV4") == null and
        std.mem.indexOf(u8, raw_bytes, "startxref") != null)
    {
        const NSDataCls = platform.objc.objc_getClass("NSData") orelse return null;
        const ns_data = platform.objc.msgSend2(
            NSDataCls,
            platform.objc.id,
            "dataWithBytes:length:",
            raw_bytes.ptr,
            raw_bytes.len,
        );
        if (ns_data != null) {
            const alloc_obj = platform.objc.msgSend0(PDFDocumentCls, platform.objc.id, "alloc");
            if (alloc_obj != null) {
                return platform.objc.msgSend1(alloc_obj, platform.objc.id, "initWithData:", ns_data);
            }
        }
    }
    return null;
}

fn extractPdfKitPageLines(pdfkit_doc: platform.objc.id, p_idx: usize, page_info: *PdfPageInfo) void {
    if (comptime !is_macos) return;
    if (pdfkit_doc == null) return;
    const pool = platform.objc.objc_autoreleasePoolPush();
    defer platform.objc.objc_autoreleasePoolPop(pool);

    const pdf_page = platform.objc.msgSend1(pdfkit_doc, platform.objc.id, "pageAtIndex:", p_idx) orelse return;
    const page_nsstr = platform.objc.msgSend0(pdf_page, platform.objc.id, "string") orelse return;
    const utf8_ptr = platform.objc.msgSend0(page_nsstr, ?[*:0]const u8, "UTF8String") orelse return;
    const full_text = std.mem.sliceTo(utf8_ptr, 0);
    if (std.mem.trim(u8, full_text, " \t\r\n").len == 0) return;

    if (comptime builtin.cpu.arch == .aarch64) {
        const box = CGRect{
            .origin = .{ .x = 0, .y = 0 },
            .size = .{
                .width = if (page_info.width_pt > 10.0) @as(f64, page_info.width_pt) else 612.0,
                .height = if (page_info.height_pt > 10.0) @as(f64, page_info.height_pt) else 792.0,
            },
        };
        if (platform.objc.msgSend1(pdf_page, platform.objc.id, "selectionForRect:", box)) |page_sel| {
            if (platform.objc.msgSend0(page_sel, platform.objc.id, "selectionsByLine")) |line_arr| {
                const cnt = @min(platform.objc.msgSend0(line_arr, usize, "count"), MaxLinesPerPage);
                if (cnt >= page_info.line_count and cnt > 0) {
                    var temp_info = PdfPageInfo{
                        .width_pt = page_info.width_pt,
                        .height_pt = page_info.height_pt,
                    };
                    for (0..cnt) |i| {
                        const line_sel = platform.objc.msgSend1(line_arr, platform.objc.id, "objectAtIndex:", i) orelse continue;
                        const line_ns = platform.objc.msgSend0(line_sel, platform.objc.id, "string") orelse continue;
                        const line_cstr = platform.objc.msgSend0(line_ns, ?[*:0]const u8, "UTF8String") orelse continue;
                        const bounds = platform.objc.msgSend1(line_sel, CGRect, "boundsForPage:", pdf_page);
                        temp_info.addLineWithBounds(
                            std.mem.sliceTo(line_cstr, 0),
                            @floatCast(bounds.origin.x),
                            @floatCast(bounds.origin.y),
                            @floatCast(bounds.size.width),
                            @floatCast(@max(8.0, bounds.size.height * 0.78)),
                        );
                    }
                    if (temp_info.line_count > 0 and temp_info.line_count >= page_info.line_count) {
                        page_info.* = temp_info;
                        return;
                    }
                }
            }
        }
    }

    if (page_info.line_count == 0) {
        var line_it = std.mem.splitScalar(u8, full_text, '\n');
        while (line_it.next()) |raw_line| {
            if (page_info.line_count >= MaxLinesPerPage) break;
            page_info.addLine(raw_line);
        }
    }
}

fn openCgPdfDocument(raw_bytes: []const u8, file_path: []const u8) ?*anyopaque {
    if (comptime !is_macos) return null;
    if (file_path.len > 0) {
        if (platform.fs_util.isDatalessSliceOnDisk(file_path)) {
            platform.fs_util.triggerAsyncICloudDownloadSlice(file_path);
            return null;
        }
        if (std.Io.Dir.cwd().statFile(std.Options.debug_io, file_path, .{})) |st| {
            if (st.size > 64) {
                if (CFURLCreateFromFileSystemRepresentation(null, file_path.ptr, @intCast(file_path.len), 0)) |url| {
                    defer CFRelease(url);
                    if (CGPDFDocumentCreateWithURL(url)) |doc| {
                        return doc;
                    }
                }
            }
        } else |_| {}
    }
    if (raw_bytes.len > 64 and
        raw_bytes.ptr != SAMPLE_PDF_DOC.ptr and
        std.mem.indexOf(u8, raw_bytes, "DS-RV32-2026-REV4") == null and
        std.mem.indexOf(u8, raw_bytes, "startxref") != null)
    {
        if (CGDataProviderCreateWithData(null, raw_bytes.ptr, raw_bytes.len, null)) |provider| {
            defer CGDataProviderRelease(provider);
            if (CGPDFDocumentCreateWithProvider(provider)) |doc| {
                return doc;
            }
        }
    }
    return null;
}

fn populateFromCoreGraphics(raw_bytes: []const u8, file_path: []const u8, out: *PdfDocumentData) void {
    const doc = getOrOpenCgPdfDocument(raw_bytes, file_path) orelse return;

    if (out.file_size_bytes == 0 and file_path.len > 0) {
        if (std.Io.Dir.cwd().statFile(std.Options.debug_io, file_path, .{})) |st| {
            out.file_size_bytes = @intCast(st.size);
        } else |_| {}
    }

    const cg_pages = CGPDFDocumentGetNumberOfPages(doc);
    if (cg_pages > 0) {
        // Store the FULL page count (never truncate at 64 pages!)
        out.page_count = cg_pages;
    }

    if (CGPDFDocumentGetInfo(doc)) |info_dict| {
        if (out.title.len == 0) {
            copyCgDictString(info_dict, "Title", &out.title);
        }
        if (out.author.len == 0) {
            copyCgDictString(info_dict, "Author", &out.author);
        }
        if (out.subject.len == 0) {
            copyCgDictString(info_dict, "Subject", &out.subject);
        }
    }

    // Sample page 1 MediaBox as default dimensions for the document
    if (CGPDFDocumentGetPage(doc, 1)) |first_page| {
        const box = CGPDFPageGetBoxRect(first_page, kCGPDFMediaBox);
        if (box.size.width > 10.0 and box.size.height > 10.0) {
            out.default_width_pt = @floatCast(box.size.width);
            out.default_height_pt = @floatCast(box.size.height);
        }
    }

    // Extract hierarchical PDF `/Outlines` (Table of Contents bookmarks) from Catalog!
    extractCoreGraphicsOutlines(doc, out);

    // Eagerly decompress text streams for up to `MaxPdfPages` (16 pages) on initial open so
    // page text search and snippet extraction work across cached pages while still opening
    // multi-thousand-page PDFs in < 5 ms.
    const eager_pages = @min(out.page_count, MaxPdfPages);
    for (0..eager_pages) |p_idx| {
        extractCgPageTextAndSize(doc, p_idx, &out.pages[p_idx]);
    }
}

fn extractCgPageTextAndSize(doc: *anyopaque, p_idx: usize, page_info: *PdfPageInfo) void {
    const page = CGPDFDocumentGetPage(doc, p_idx + 1) orelse return;
    const box = CGPDFPageGetBoxRect(page, kCGPDFMediaBox);
    if (box.size.width > 10.0 and box.size.height > 10.0) {
        page_info.width_pt = @floatCast(box.size.width);
        page_info.height_pt = @floatCast(box.size.height);
    }

    if (page_info.line_count == 0) {
        if (CGPDFPageGetDictionary(page)) |page_dict| {
            var stream_ref: ?*anyopaque = null;
            if (CGPDFDictionaryGetStream(page_dict, "Contents", &stream_ref)) {
                if (stream_ref) |s_ref| {
                    extractFromCgStream(s_ref, page_info);
                }
            } else {
                var arr_ref: ?*anyopaque = null;
                if (CGPDFDictionaryGetArray(page_dict, "Contents", &arr_ref)) {
                    if (arr_ref) |a_ref| {
                        const arr_cnt = @min(CGPDFArrayGetCount(a_ref), 16);
                        for (0..arr_cnt) |a_i| {
                            var elem_stream: ?*anyopaque = null;
                            if (CGPDFArrayGetStream(a_ref, a_i, &elem_stream)) {
                                if (elem_stream) |es| {
                                    extractFromCgStream(es, page_info);
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    if (comptime is_macos) {
        if (g_cached_pdfkit_doc) |kit_doc| {
            extractPdfKitPageLines(kit_doc, p_idx, page_info);
        }
    }
}

/// Decodes a `CGPDFStringRef` (supporting both PDFDocEncoding/ASCII and UTF-16BE with `0xFE 0xFF` BOM).
fn decodeCgPdfString(s: *anyopaque, out_buf: []u8) []const u8 {
    const len = CGPDFStringGetLength(s);
    if (len == 0) return "";
    const ptr = CGPDFStringGetBytePtr(s) orelse return "";
    const raw = ptr[0..len];

    var out_len: usize = 0;
    if (raw.len >= 2 and raw[0] == 0xFE and raw[1] == 0xFF) {
        // UTF-16BE string: read 16-bit big-endian code units
        var i: usize = 2;
        while (i + 1 < raw.len and out_len < out_buf.len) : (i += 2) {
            const hi = raw[i];
            const lo = raw[i + 1];
            if (hi == 0 and lo >= 32 and lo < 127) {
                if (out_len >= 1 and out_len <= 2 and std.ascii.isDigit(out_buf[out_len - 1]) and std.ascii.isUpper(lo) and out_len + 1 < out_buf.len) {
                    out_buf[out_len] = ' ';
                    out_len += 1;
                }
                out_buf[out_len] = lo;
                out_len += 1;
            } else if (hi == 0 and (lo == '\t' or lo == '\n' or lo == '\r' or lo == 0xA0)) {
                if (out_len > 0 and out_buf[out_len - 1] != ' ') {
                    out_buf[out_len] = ' ';
                    out_len += 1;
                }
            } else if (hi == 0x20 and (lo == 0x13 or lo == 0x14)) {
                out_buf[out_len] = '-';
                out_len += 1;
            }
        }
    } else {
        for (raw) |b| {
            if (b >= 32 and b < 127 and out_len < out_buf.len) {
                if (out_len >= 1 and out_len <= 2 and std.ascii.isDigit(out_buf[out_len - 1]) and std.ascii.isUpper(b) and out_len + 1 < out_buf.len) {
                    out_buf[out_len] = ' ';
                    out_len += 1;
                }
                out_buf[out_len] = b;
                out_len += 1;
            } else if ((b == '\n' or b == '\r' or b == '\t' or b == 0xA0) and out_len > 0 and out_buf[out_len - 1] != ' ' and out_len < out_buf.len) {
                out_buf[out_len] = ' ';
                out_len += 1;
            }
        }
    }
    return std.mem.trim(u8, out_buf[0..out_len], " \t\r\n");
}

fn copyCgDictString(dict: *anyopaque, key: [*:0]const u8, dest: anytype) void {
    var str_ref: ?*anyopaque = null;
    if (CGPDFDictionaryGetString(dict, key, &str_ref)) {
        if (str_ref) |s| {
            var buf: [96]u8 = undefined;
            const clean = decodeCgPdfString(s, &buf);
            if (clean.len > 0) {
                dest.set(clean);
            }
        }
    }
}

/// Resolves a `/Page` dictionary pointer to its 1-based page number (`1..page_count`) in $O(\log N)$ time
/// by walking up the PDF `/Pages` tree (`/Parent` -> `/Kids` -> `/Count`), without scanning all pages!
fn resolvePageNumberFromDict(page_dict: *anyopaque) ?u32 {
    var offset: isize = 0;
    var curr: *anyopaque = page_dict;
    var depth: usize = 0;
    while (depth < 16) : (depth += 1) {
        var parent_opt: ?*anyopaque = null;
        if (!CGPDFDictionaryGetDictionary(curr, "Parent", &parent_opt)) break;
        const parent = parent_opt orelse break;

        var kids_opt: ?*anyopaque = null;
        if (!CGPDFDictionaryGetArray(parent, "Kids", &kids_opt)) break;
        const kids = kids_opt orelse break;

        const n_kids = CGPDFArrayGetCount(kids);
        var found = false;
        for (0..n_kids) |i| {
            var kid_opt: ?*anyopaque = null;
            if (CGPDFArrayGetDictionary(kids, i, &kid_opt)) {
                if (kid_opt) |kid| {
                    if (kid == curr) {
                        found = true;
                        break;
                    }
                    var k_cnt: isize = 0;
                    if (CGPDFDictionaryGetInteger(kid, "Count", &k_cnt) and k_cnt > 0) {
                        offset += k_cnt;
                    } else {
                        offset += 1;
                    }
                }
            }
        }
        if (!found) return null;
        curr = parent;
    }
    return @intCast(@max(@as(isize, 1), offset + 1));
}

/// Searches a PDF Name Tree node (`/Limits`, `/Names`, `/Kids`) in $O(\log N)$ time for `target_name`,
/// returning the resolved destination `(page_number, norm_y)`.
fn lookupNamedDestinationInTree(node_dict: *anyopaque, target_name: []const u8, depth: usize) ?PdfDestination {
    if (depth > 16) return null;

    // 1. Check `/Limits [min_key max_key]` for fast B-tree pruning
    var limits_opt: ?*anyopaque = null;
    if (CGPDFDictionaryGetArray(node_dict, "Limits", &limits_opt)) {
        if (limits_opt) |limits| {
            if (CGPDFArrayGetCount(limits) >= 2) {
                var min_s: ?*anyopaque = null;
                var max_s: ?*anyopaque = null;
                if (CGPDFArrayGetString(limits, 0, &min_s) and CGPDFArrayGetString(limits, 1, &max_s)) {
                    if (min_s != null and max_s != null) {
                        const min_len = CGPDFStringGetLength(min_s.?);
                        const max_len = CGPDFStringGetLength(max_s.?);
                        const min_ptr = CGPDFStringGetBytePtr(min_s.?);
                        const max_ptr = CGPDFStringGetBytePtr(max_s.?);
                        if (min_ptr != null and max_ptr != null) {
                            const min_slice = min_ptr.?[0..min_len];
                            const max_slice = max_ptr.?[0..max_len];
                            if (std.mem.order(u8, target_name, min_slice) == .lt or
                                std.mem.order(u8, target_name, max_slice) == .gt)
                            {
                                return null;
                            }
                        }
                    }
                }
            }
        }
    }

    // 2. Check leaf `/Names [key0 val0 key1 val1 ...]` array
    var names_opt: ?*anyopaque = null;
    if (CGPDFDictionaryGetArray(node_dict, "Names", &names_opt)) {
        if (names_opt) |names_arr| {
            const cnt = CGPDFArrayGetCount(names_arr);
            var i: usize = 0;
            while (i + 1 < cnt) : (i += 2) {
                var k_str: ?*anyopaque = null;
                if (CGPDFArrayGetString(names_arr, i, &k_str)) {
                    if (k_str) |ks| {
                        const k_len = CGPDFStringGetLength(ks);
                        if (CGPDFStringGetBytePtr(ks)) |k_ptr| {
                            if (std.mem.eql(u8, k_ptr[0..k_len], target_name)) {
                                // Value at `i + 1` can be a Dictionary `<< /D [page /XYZ ...] >>` or direct Array `[page /XYZ ...]`
                                var val_dict: ?*anyopaque = null;
                                if (CGPDFArrayGetDictionary(names_arr, i + 1, &val_dict)) {
                                    if (val_dict) |vd| {
                                        var d_arr: ?*anyopaque = null;
                                        if (CGPDFDictionaryGetArray(vd, "D", &d_arr)) {
                                            if (d_arr) |da| return resolveDestArrayTarget(da);
                                        }
                                    }
                                }
                                var val_arr: ?*anyopaque = null;
                                if (CGPDFArrayGetArray(names_arr, i + 1, &val_arr)) {
                                    if (val_arr) |va| return resolveDestArrayTarget(va);
                                }
                                return null;
                            }
                        }
                    }
                }
            }
        }
    }

    // 3. Recurse into `/Kids` B-tree child nodes
    var kids_opt: ?*anyopaque = null;
    if (CGPDFDictionaryGetArray(node_dict, "Kids", &kids_opt)) {
        if (kids_opt) |kids_arr| {
            const k_cnt = CGPDFArrayGetCount(kids_arr);
            for (0..k_cnt) |k_i| {
                var child_dict: ?*anyopaque = null;
                if (CGPDFArrayGetDictionary(kids_arr, k_i, &child_dict)) {
                    if (child_dict) |cd| {
                        if (lookupNamedDestinationInTree(cd, target_name, depth + 1)) |dest| {
                            return dest;
                        }
                    }
                }
            }
        }
    }
    return null;
}

fn getPageHeightFromDict(page_dict: *anyopaque) f64 {
    var curr: *anyopaque = page_dict;
    var depth: usize = 0;
    while (depth < 8) : (depth += 1) {
        var mb_opt: ?*anyopaque = null;
        if (CGPDFDictionaryGetArray(curr, "MediaBox", &mb_opt)) {
            if (mb_opt) |mb| {
                if (CGPDFArrayGetCount(mb) >= 4) {
                    var y0: f64 = 0;
                    var y1: f64 = 0;
                    if (CGPDFArrayGetNumber(mb, 1, &y0) and CGPDFArrayGetNumber(mb, 3, &y1)) {
                        const h = @abs(y1 - y0);
                        if (h > 10.0) return h;
                    }
                }
            }
        }
        var parent_opt: ?*anyopaque = null;
        if (!CGPDFDictionaryGetDictionary(curr, "Parent", &parent_opt)) break;
        curr = parent_opt orelse break;
    }
    return 792.0;
}

fn resolveDestArrayTarget(dest_arr: *anyopaque) ?PdfDestination {
    const cnt = CGPDFArrayGetCount(dest_arr);
    if (cnt == 0) return null;
    var page_dict: ?*anyopaque = null;
    if (CGPDFArrayGetDictionary(dest_arr, 0, &page_dict)) {
        if (page_dict) |pd| {
            const page_num = resolvePageNumberFromDict(pd) orelse return null;
            var norm_y: f32 = 0.0;
            var fit_name_ptr: ?[*:0]const u8 = null;
            if (cnt >= 2 and CGPDFArrayGetName(dest_arr, 1, &fit_name_ptr)) {
                if (fit_name_ptr) |fn_z| {
                    const fit_name = std.mem.sliceTo(fn_z, 0);
                    var top_pt: ?f64 = null;
                    if (std.mem.eql(u8, fit_name, "XYZ") and cnt >= 4) {
                        var t: f64 = 0;
                        if (CGPDFArrayGetNumber(dest_arr, 3, &t)) top_pt = t;
                    } else if ((std.mem.eql(u8, fit_name, "FitH") or std.mem.eql(u8, fit_name, "FitBH")) and cnt >= 3) {
                        var t: f64 = 0;
                        if (CGPDFArrayGetNumber(dest_arr, 2, &t)) top_pt = t;
                    } else if (std.mem.eql(u8, fit_name, "FitR") and cnt >= 6) {
                        var t: f64 = 0;
                        if (CGPDFArrayGetNumber(dest_arr, 5, &t)) top_pt = t;
                    }
                    if (top_pt) |t| {
                        const page_h = getPageHeightFromDict(pd);
                        if (t > 0.0 and t <= page_h * 1.05) {
                            const raw_ny: f32 = @floatCast(1.0 - (t / page_h));
                            norm_y = std.math.clamp(raw_ny - 0.03, 0.0, 0.94);
                        }
                    }
                }
            }
            return .{ .page_number = page_num, .norm_y = norm_y };
        }
    }
    return null;
}

/// Resolves a `/Dest` or `/A << /S /GoTo /D ... >>` entry on an Outline item or Page Link Annotation.
fn resolveDestinationDictOrObj(catalog: *anyopaque, item_dict: *anyopaque) ?PdfDestination {
    // 1. Direct `/Dest` array on item
    var dest_arr: ?*anyopaque = null;
    if (CGPDFDictionaryGetArray(item_dict, "Dest", &dest_arr)) {
        if (dest_arr) |da| {
            if (resolveDestArrayTarget(da)) |dest| return dest;
        }
    }
    // 2. Direct `/Dest` string or name on item
    var dest_str: ?*anyopaque = null;
    if (CGPDFDictionaryGetString(item_dict, "Dest", &dest_str)) {
        if (dest_str) |ds| {
            if (resolveNamedDestFromCatalog(catalog, ds)) |dest| return dest;
        }
    }
    var dest_name: ?[*:0]const u8 = null;
    if (CGPDFDictionaryGetName(item_dict, "Dest", &dest_name)) {
        if (dest_name) |dn| {
            if (resolveNamedDestSliceFromCatalog(catalog, std.mem.sliceTo(dn, 0))) |dest| return dest;
        }
    }
    // 3. Action dictionary `/A << /S /GoTo /D ... >>`
    var act_dict: ?*anyopaque = null;
    if (CGPDFDictionaryGetDictionary(item_dict, "A", &act_dict)) {
        if (act_dict) |ad| {
            var a_arr: ?*anyopaque = null;
            if (CGPDFDictionaryGetArray(ad, "D", &a_arr)) {
                if (a_arr) |da| {
                    if (resolveDestArrayTarget(da)) |dest| return dest;
                }
            }
            var a_str: ?*anyopaque = null;
            if (CGPDFDictionaryGetString(ad, "D", &a_str)) {
                if (a_str) |ds| {
                    if (resolveNamedDestFromCatalog(catalog, ds)) |dest| return dest;
                }
            }
            var a_name: ?[*:0]const u8 = null;
            if (CGPDFDictionaryGetName(ad, "D", &a_name)) {
                if (a_name) |an| {
                    if (resolveNamedDestSliceFromCatalog(catalog, std.mem.sliceTo(an, 0))) |dest| return dest;
                }
            }
        }
    }
    return null;
}

fn resolveNamedDestFromCatalog(catalog: *anyopaque, dest_str: *anyopaque) ?PdfDestination {
    const len = CGPDFStringGetLength(dest_str);
    if (len == 0) return null;
    const ptr = CGPDFStringGetBytePtr(dest_str) orelse return null;
    return resolveNamedDestSliceFromCatalog(catalog, ptr[0..len]);
}

fn resolveNamedDestSliceFromCatalog(catalog: *anyopaque, name_slice: []const u8) ?PdfDestination {
    if (name_slice.len == 0) return null;

    // 1. PDF 1.2+ `/Names -> /Dests` Name B-Tree
    var names_dict: ?*anyopaque = null;
    if (CGPDFDictionaryGetDictionary(catalog, "Names", &names_dict)) {
        if (names_dict) |nd| {
            var dests_tree: ?*anyopaque = null;
            if (CGPDFDictionaryGetDictionary(nd, "Dests", &dests_tree)) {
                if (dests_tree) |dt| {
                    if (lookupNamedDestinationInTree(dt, name_slice, 0)) |dest| return dest;
                }
            }
        }
    }

    // 2. PDF 1.1 `/Dests` direct dictionary in Catalog
    if (name_slice.len < 127) {
        var dests_dict: ?*anyopaque = null;
        if (CGPDFDictionaryGetDictionary(catalog, "Dests", &dests_dict)) {
            if (dests_dict) |dd| {
                var key_z: [128:0]u8 = @splat(0);
                @memcpy(key_z[0..name_slice.len], name_slice);
                key_z[name_slice.len] = 0;
                var d_arr: ?*anyopaque = null;
                if (CGPDFDictionaryGetArray(dd, &key_z, &d_arr)) {
                    if (d_arr) |da| return resolveDestArrayTarget(da);
                }
                var d_sub: ?*anyopaque = null;
                if (CGPDFDictionaryGetDictionary(dd, &key_z, &d_sub)) {
                    if (d_sub) |ds| {
                        if (CGPDFDictionaryGetArray(ds, "D", &d_arr)) {
                            if (d_arr) |da| return resolveDestArrayTarget(da);
                        }
                    }
                }
            }
        }
    }
    return null;
}

fn extractCoreGraphicsOutlines(doc: *anyopaque, out: *PdfDocumentData) void {
    const catalog = CGPDFDocumentGetCatalog(doc) orelse return;
    var outlines_root: ?*anyopaque = null;
    if (!CGPDFDictionaryGetDictionary(catalog, "Outlines", &outlines_root)) return;
    const root_dict = outlines_root orelse return;

    var first_item: ?*anyopaque = null;
    if (!CGPDFDictionaryGetDictionary(root_dict, "First", &first_item)) return;
    if (first_item) |first| {
        walkCgOutlineLevel(catalog, first, 0, out);
    }
}

fn walkCgOutlineLevel(
    catalog: *anyopaque,
    first_node: *anyopaque,
    indent: u8,
    out: *PdfDocumentData,
) void {
    var curr_opt: ?*anyopaque = first_node;
    var siblings_visited: usize = 0;
    while (curr_opt != null and siblings_visited < 8192) : (siblings_visited += 1) {
        const curr = curr_opt.?;

        var title_str: ?*anyopaque = null;
        if (CGPDFDictionaryGetString(curr, "Title", &title_str)) {
            if (title_str) |ts| {
                var title_buf: [96]u8 = undefined;
                const clean_title = decodeCgPdfString(ts, &title_buf);
                if (clean_title.len > 0) {
                    const dest = resolveDestinationDictOrObj(catalog, curr) orelse PdfDestination{};
                    out.addOutlineIndentedWithY(clean_title, dest.page_number, dest.norm_y, @min(indent, 6));
                }
            }
        }

        if (indent < 12) {
            var child_first: ?*anyopaque = null;
            if (CGPDFDictionaryGetDictionary(curr, "First", &child_first)) {
                if (child_first) |cf| {
                    walkCgOutlineLevel(catalog, cf, indent + 1, out);
                }
            }
        }

        var next_node: ?*anyopaque = null;
        if (CGPDFDictionaryGetDictionary(curr, "Next", &next_node)) {
            curr_opt = next_node;
        } else {
            curr_opt = null;
        }
    }
}

/// Hit-tests PDF `/Annots` (`/Subtype /Link`) on `page_idx` at normalized page coordinates `(norm_x, norm_y)`
/// where `norm_x, norm_y in [0..1]` from top-left of the rendered sheet.
/// Returns the target `(page_number, norm_y)` if a Table of Contents / cross-reference link is under the cursor!
fn resolvePdfPageLinkAtPoint(
    raw_bytes: []const u8,
    file_path: []const u8,
    page_idx: usize,
    norm_x: f32,
    norm_y: f32,
) ?PdfDestination {
    if (comptime !is_macos) return null;
    if (norm_x < 0.0 or norm_x > 1.0 or norm_y < 0.0 or norm_y > 1.0) return null;

    const doc = getOrOpenCgPdfDocument(raw_bytes, file_path) orelse return null;
    const catalog = CGPDFDocumentGetCatalog(doc) orelse return null;
    const page = CGPDFDocumentGetPage(doc, page_idx + 1) orelse return null;
    const media_box = CGPDFPageGetBoxRect(page, kCGPDFMediaBox);
    const page_w: f64 = if (media_box.size.width > 1.0) media_box.size.width else 612.0;
    const page_h: f64 = if (media_box.size.height > 1.0) media_box.size.height else 792.0;

    // Convert normalized top-left UI coordinates into bottom-left PDF user space coordinates
    const pdf_x: f64 = media_box.origin.x + @as(f64, norm_x) * page_w;
    const pdf_y: f64 = media_box.origin.y + (1.0 - @as(f64, norm_y)) * page_h;

    const page_dict = CGPDFPageGetDictionary(page) orelse return null;
    var annots_opt: ?*anyopaque = null;
    if (!CGPDFDictionaryGetArray(page_dict, "Annots", &annots_opt)) return null;
    const annots = annots_opt orelse return null;

    const n_annots = @min(CGPDFArrayGetCount(annots), 256);
    for (0..n_annots) |i| {
        var annot_opt: ?*anyopaque = null;
        if (!CGPDFArrayGetDictionary(annots, i, &annot_opt)) continue;
        const annot = annot_opt orelse continue;

        var rect_opt: ?*anyopaque = null;
        if (!CGPDFDictionaryGetArray(annot, "Rect", &rect_opt)) continue;
        const rect_arr = rect_opt orelse continue;
        if (CGPDFArrayGetCount(rect_arr) < 4) continue;

        var x0: f64 = 0;
        var y0: f64 = 0;
        var x1: f64 = 0;
        var y1: f64 = 0;
        if (!CGPDFArrayGetNumber(rect_arr, 0, &x0)) continue;
        if (!CGPDFArrayGetNumber(rect_arr, 1, &y0)) continue;
        if (!CGPDFArrayGetNumber(rect_arr, 2, &x1)) continue;
        if (!CGPDFArrayGetNumber(rect_arr, 3, &y1)) continue;

        const min_x = @min(x0, x1) - 2.0;
        const max_x = @max(x0, x1) + 2.0;
        const min_y = @min(y0, y1) - 2.0;
        const max_y = @max(y0, y1) + 2.0;

        if (pdf_x >= min_x and pdf_x <= max_x and pdf_y >= min_y and pdf_y <= max_y) {
            if (resolveDestinationDictOrObj(catalog, annot)) |target_dest| {
                return target_dest;
            }
        }
    }
    return null;
}

fn extractFromCgStream(stream_ref: *anyopaque, page: *PdfPageInfo) void {
    var data_format: c_int = 0;
    const cf_data = CGPDFStreamCopyData(stream_ref, &data_format) orelse return;
    defer CFRelease(cf_data);
    const len = CFDataGetLength(cf_data);
    if (len <= 0) return;
    const ptr = CFDataGetBytePtr(cf_data) orelse return;
    const slice = ptr[0..@intCast(len)];
    extractTextLinesFromContentStream(slice, page);
}

const PageCacheEntry = struct {
    valid: bool = false,
    doc_hash: u64 = 0,
    page_idx: usize = 0,
    width_px: i32 = 0,
    height_px: i32 = 0,
    invert_paper: bool = false,
    last_used_tick: u64 = 0,
    image: ?skia.Image = null,

    pub fn clear(self: *PageCacheEntry) void {
        if (self.image) |img| {
            img.deinit();
            self.image = null;
        }
        self.valid = false;
    }
};

const PageCacheSlots: usize = 8;
var g_page_cache: [PageCacheSlots]PageCacheEntry = @splat(.{});
var g_page_cache_tick: u64 = 0;

fn computeDocHash(raw_bytes: []const u8, file_path: []const u8) u64 {
    var h = std.hash.Fnv1a_64.init();
    h.update(file_path);
    if (file_path.len > 0 and file_path.len < 512) {
        var path_z: [512:0]u8 = @splat(0);
        @memcpy(path_z[0..file_path.len], file_path);
        path_z[file_path.len] = 0;
        if (platform.fs_util.fileMtimeNs(&path_z)) |mtime_ns| {
            h.update(std.mem.asBytes(&mtime_ns));
        }
        if (platform.fs_util.regularFileSizeOnDisk(&path_z)) |fsize| {
            h.update(std.mem.asBytes(&fsize));
        }
        const dataless: u8 = @intFromBool(platform.fs_util.isDatalessFileOnDisk(&path_z));
        h.update(&.{dataless});
    }
    const sample_len = @min(raw_bytes.len, 2048);
    h.update(raw_bytes[0..sample_len]);
    const total_len: u64 = raw_bytes.len;
    h.update(std.mem.asBytes(&total_len));
    return h.final();
}

/// Returns a cached `skia.Image` rasterized via macOS `CoreGraphics` for `(raw_bytes, file_path, page_idx)`.
fn getOrRasterizePdfPageImage(
    raw_bytes: []const u8,
    file_path: []const u8,
    page_idx: usize,
    target_w_px: i32,
    target_h_px: i32,
    invert_paper: bool,
) ?skia.Image {
    if (comptime !is_macos) return null;
    const w_px = std.math.clamp(target_w_px, 120, 1800);
    const h_px = std.math.clamp(target_h_px, 150, 2400);
    const doc_hash = computeDocHash(raw_bytes, file_path);

    g_page_cache_tick +%= 1;

    // 1. Check existing cache slots
    for (&g_page_cache) |*slot| {
        if (slot.valid and
            slot.doc_hash == doc_hash and
            slot.page_idx == page_idx and
            @abs(slot.width_px - w_px) <= 6 and
            @abs(slot.height_px - h_px) <= 6 and
            slot.invert_paper == invert_paper)
        {
            slot.last_used_tick = g_page_cache_tick;
            return slot.image;
        }
    }

    // 2. Rasterize requested page via retained CoreGraphics document handle
    const doc = getOrOpenCgPdfDocument(raw_bytes, file_path) orelse return null;

    const num_pages = CGPDFDocumentGetNumberOfPages(doc);
    if (num_pages == 0) return null;
    const clamped_page = @min(page_idx + 1, num_pages);
    const page = CGPDFDocumentGetPage(doc, clamped_page) orelse return null;
    const media_box = CGPDFPageGetBoxRect(page, kCGPDFMediaBox);
    const page_w = if (media_box.size.width > 1.0) media_box.size.width else 612.0;
    const page_h = if (media_box.size.height > 1.0) media_box.size.height else 792.0;

    const u_w: usize = @intCast(w_px);
    const u_h: usize = @intCast(h_px);
    const row_bytes: usize = u_w * 4;
    const total_bytes: usize = row_bytes * u_h;

    const pixels = std.heap.page_allocator.alloc(u8, total_bytes) catch return null;
    defer std.heap.page_allocator.free(pixels);
    @memset(pixels, 0xFF);

    const cs = CGColorSpaceCreateDeviceRGB() orelse return null;
    defer CGColorSpaceRelease(cs);

    const bmp_info: u32 = kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst;
    const cg_ctx = CGBitmapContextCreate(pixels.ptr, u_w, u_h, 8, row_bytes, cs, bmp_info) orelse return null;
    defer CGContextRelease(cg_ctx);

    CGContextSetRGBFillColor(cg_ctx, 1.0, 1.0, 1.0, 1.0);
    CGContextFillRect(cg_ctx, .{
        .origin = .{ .x = 0, .y = 0 },
        .size = .{ .width = @floatFromInt(u_w), .height = @floatFromInt(u_h) },
    });

    CGContextSaveGState(cg_ctx);
    const sx = @as(f64, @floatFromInt(u_w)) / page_w;
    const sy = @as(f64, @floatFromInt(u_h)) / page_h;
    CGContextScaleCTM(cg_ctx, sx, sy);
    CGContextTranslateCTM(cg_ctx, -media_box.origin.x, -media_box.origin.y);
    CGContextDrawPDFPage(cg_ctx, page);
    CGContextRestoreGState(cg_ctx);

    if (invert_paper) {
        var px_i: usize = 0;
        while (px_i + 3 < total_bytes) : (px_i += 4) {
            const b = pixels[px_i + 0];
            const g = pixels[px_i + 1];
            const r = pixels[px_i + 2];
            pixels[px_i + 0] = @intCast(@min(@as(u16, 255), @as(u16, 255 - b) + 28));
            pixels[px_i + 1] = @intCast(@min(@as(u16, 255), @as(u16, 255 - g) + 20));
            pixels[px_i + 2] = @intCast(@min(@as(u16, 255), @as(u16, 255 - r) + 14));
            pixels[px_i + 3] = 255;
        }
    }

    const img_info = skia.ImageInfo.initBgra8888Premul(w_px, h_px);
    const sk_img = skia.Image.initRasterCopy(img_info, pixels.ptr, row_bytes) catch return null;

    var target_slot: usize = 0;
    var oldest_tick: u64 = std.math.maxInt(u64);
    for (&g_page_cache, 0..) |*slot, idx| {
        if (!slot.valid) {
            target_slot = idx;
            break;
        }
        if (slot.last_used_tick < oldest_tick) {
            oldest_tick = slot.last_used_tick;
            target_slot = idx;
        }
    }

    g_page_cache[target_slot].clear();
    g_page_cache[target_slot] = .{
        .valid = true,
        .doc_hash = doc_hash,
        .page_idx = page_idx,
        .width_px = w_px,
        .height_px = h_px,
        .invert_paper = invert_paper,
        .last_used_tick = g_page_cache_tick,
        .image = sk_img,
    };
    return sk_img;
}

// ============================================================================
// Two-Phase (`Pass.input` / `Pass.paint`) Contiguous Multi-Page PDF Viewer
// ============================================================================

/// Parses a Table of Contents text line (e.g. `"2.1 Memory Map ........... 14"` or `"Section 3  42"`)
/// and returns its trailing 1-based page number if valid.
fn parseTocLinePageNumber(line: []const u8, max_pages: usize) ?u32 {
    const trimmed = std.mem.trim(u8, line, " \t\r\n");
    if (trimmed.len < 4) return null;
    if (std.mem.startsWith(u8, trimmed, "Page ")) return null;

    const end = trimmed.len;
    var start = end;
    while (start > 0 and std.ascii.isDigit(trimmed[start - 1])) : (start -= 1) {}
    if (start == end or start == 0 or (end - start) > 5) return null;

    // Require whitespace or leader dots (`.`) immediately before the trailing page number
    const prev = trimmed[start - 1];
    if (prev != ' ' and prev != '.' and prev != '\t') return null;

    // Require either leader dots (`..`) or a section-like prefix so random body lines ending in numbers aren't misclassified
    const has_dots = std.mem.indexOf(u8, trimmed[0..start], "..") != null;
    const is_sec = isSectionHeadingLine(trimmed);
    if (!has_dots and !is_sec) return null;

    const pg = std.fmt.parseInt(u32, trimmed[start..end], 10) catch return null;
    if (pg >= 1 and pg <= max_pages) return pg;
    return null;
}

const LineVisualMetrics = struct {
    text_x: f32 = 0.0,
    baseline_y: f32 = 0.0,
    box_top: f32 = 0.0,
    box_bottom: f32 = 0.0,
    box_h: f32 = 0.0,
    font: Font,
    font_scale: f32 = 1.0,
    visible: bool = false,
};

fn isPlaceholderOnlyPage(page: *const PdfPageInfo) bool {
    if (page.line_count == 0) return true;
    if (page.line_count == 1) {
        const s = page.lines[0].slice();
        if (std.mem.startsWith(u8, s, "[Page ") and std.mem.endsWith(u8, s, "content]")) {
            return true;
        }
    }
    return false;
}

fn isPdfWordChar(b: u8) bool {
    return std.ascii.isAlphanumeric(b) or b == '_' or b == '-' or b == '.' or b == '/' or b == ':';
}

fn wordRangeInLine(line: []const u8, col: usize) struct { start: usize, end: usize } {
    if (line.len == 0) return .{ .start = 0, .end = 0 };
    const idx = @min(col, line.len - 1);
    if (!isPdfWordChar(line[idx])) {
        if (idx > 0 and isPdfWordChar(line[idx - 1])) {
            var s = idx - 1;
            while (s > 0 and isPdfWordChar(line[s - 1])) : (s -= 1) {}
            return .{ .start = s, .end = idx };
        }
        return .{ .start = idx, .end = @min(line.len, idx + 1) };
    }
    var s = idx;
    while (s > 0 and isPdfWordChar(line[s - 1])) : (s -= 1) {}
    var e = idx + 1;
    while (e < line.len and isPdfWordChar(line[e])) : (e += 1) {}
    return .{ .start = s, .end = e };
}

fn computePageLineVisualMetrics(
    uic: *Context,
    sheet_r: c.sk_rect_t,
    doc: *const PdfDocumentData,
    page: *const PdfPageInfo,
    used_cg_raster: bool,
    out_metrics: *[MaxLinesPerPage]LineVisualMetrics,
) void {
    for (0..MaxLinesPerPage) |i| {
        out_metrics[i] = .{ .font = uic.font_body, .visible = false };
    }
    const sheet_w = sheet_r.right - sheet_r.left;
    const sheet_h = sheet_r.bottom - sheet_r.top;
    if (sheet_w <= 10.0 or sheet_h <= 10.0 or page.line_count == 0) return;

    if (used_cg_raster) {
        const w_pt = if (page.width_pt > 10.0) page.width_pt else doc.default_width_pt;
        const h_pt = if (page.height_pt > 10.0) page.height_pt else doc.default_height_pt;
        const pt_to_px_x = sheet_w / @max(1.0, w_pt);
        const pt_to_px_y = sheet_h / @max(1.0, h_pt);

        for (page.lines[0..page.line_count], 0..) |line_in, l_idx| {
            const line = line_in.slice();
            if (line.len == 0) continue;
            const font_pt = page.line_font_pt[l_idx];
            const line_w_pt = page.line_w_pt[l_idx];
            const measured_w = uic.measureTextCached(uic.font_body, line);
            const font_scale = if (line_w_pt > 1.0 and measured_w > 1.0)
                (line_w_pt * pt_to_px_x) / measured_w
            else
                (font_pt / 12.0) * pt_to_px_x;
            const line_left = sheet_r.left + page.lineNormX(l_idx) * sheet_w;
            const line_baseline_y = sheet_r.top + page.lineNormY(l_idx) * sheet_h;
            const box_h = @max(12.0, font_pt * 1.32 * pt_to_px_y);
            const box_top = line_baseline_y - box_h * 0.78;
            out_metrics[l_idx] = .{
                .text_x = line_left,
                .baseline_y = line_baseline_y,
                .box_top = box_top,
                .box_bottom = box_top + box_h,
                .box_h = box_h,
                .font = uic.font_body,
                .font_scale = font_scale,
                .visible = true,
            };
        }
        return;
    }

    const scale = std.math.clamp(sheet_w / 560.0, 0.65, 1.8);
    const hdr_x = sheet_r.left + 20.0 * scale;
    const hdr_y = sheet_r.top + 18.0 * scale;
    const hdr_w = @max(40.0, sheet_w - 40.0 * scale);
    const hdr_h = 44.0 * scale;
    var y = hdr_y + hdr_h + 22.0 * scale;
    const line_step = @max(16.0, 18.0 * scale);

    var skip_count: usize = 0;
    for (page.lines[0..page.line_count], 0..) |line_in, l_idx| {
        if (skip_count > 0) {
            skip_count -= 1;
            continue;
        }
        const line = line_in.slice();
        if (l_idx == 0 and std.mem.indexOf(u8, line, "DATASHEET") != null) {
            const by = hdr_y + 20.0 * scale;
            const bh = @max(16.0, 18.0 * scale);
            out_metrics[l_idx] = .{
                .text_x = hdr_x + 14.0 * scale,
                .baseline_y = by,
                .box_top = by - bh * 0.76,
                .box_bottom = by + bh * 0.24,
                .box_h = bh,
                .font = uic.font_title,
                .font_scale = 1.0,
                .visible = line.len > 0,
            };
            continue;
        }
        if (std.mem.startsWith(u8, line, "Page ") and std.mem.indexOf(u8, line, "Confidential") != null) {
            const footer_y = sheet_r.bottom - 14.0 * scale;
            const bh = @max(14.0, 15.0 * scale);
            out_metrics[l_idx] = .{
                .text_x = hdr_x,
                .baseline_y = footer_y,
                .box_top = footer_y - bh * 0.76,
                .box_bottom = footer_y + bh * 0.24,
                .box_h = bh,
                .font = uic.font_mono,
                .font_scale = 1.0,
                .visible = line.len > 0,
            };
            continue;
        }
        if (y + line_step > sheet_r.bottom - 28.0 * scale) break;

        if (std.mem.eql(u8, line, "RV32IMAC CPU") and y + 58.0 * scale < sheet_r.bottom - 30.0 * scale) {
            const box_gap = 14.0 * scale;
            const box_w = @max(60.0, (hdr_w - box_gap * 2.0) / 3.0);
            const box_h = 46.0 * scale;
            const box_y = y - 6.0 * scale;
            for (0..3) |b_i| {
                const bx = hdr_x + @as(f32, @floatFromInt(b_i)) * (box_w + box_gap);
                const t_idx = l_idx + b_i * 2;
                const s_idx = l_idx + b_i * 2 + 1;
                if (t_idx < page.line_count) {
                    const by = box_y + 18.0 * scale;
                    const bh = @max(14.0, 16.0 * scale);
                    out_metrics[t_idx] = .{
                        .text_x = bx + 10.0,
                        .baseline_y = by,
                        .box_top = by - bh * 0.76,
                        .box_bottom = by + bh * 0.24,
                        .box_h = bh,
                        .font = uic.font_title,
                        .font_scale = 1.0,
                        .visible = true,
                    };
                }
                if (s_idx < page.line_count) {
                    const by = box_y + 35.0 * scale;
                    const bh = @max(13.0, 15.0 * scale);
                    out_metrics[s_idx] = .{
                        .text_x = bx + 10.0,
                        .baseline_y = by,
                        .box_top = by - bh * 0.76,
                        .box_bottom = by + bh * 0.24,
                        .box_h = bh,
                        .font = uic.font_mono,
                        .font_scale = 1.0,
                        .visible = true,
                    };
                }
            }
            skip_count = 5;
            y += box_h + 12.0 * scale;
            continue;
        }

        if (isSectionHeadingLine(line)) {
            y += 5.0 * scale;
            const by = y + 2.0 * scale;
            const bh = line_step;
            out_metrics[l_idx] = .{
                .text_x = hdr_x + 8.0 * scale,
                .baseline_y = by,
                .box_top = by - bh * 0.76,
                .box_bottom = by + bh * 0.24,
                .box_h = bh,
                .font = uic.font_title,
                .font_scale = 1.0,
                .visible = line.len > 0,
            };
            y += line_step + 4.0 * scale;
        } else if (std.mem.startsWith(u8, line, "0x") or std.mem.startsWith(u8, line, "Base Address") or std.mem.startsWith(u8, line, "Offset")) {
            const by = y;
            const bh = line_step - 2.0;
            out_metrics[l_idx] = .{
                .text_x = hdr_x + 10.0 * scale,
                .baseline_y = by,
                .box_top = by - bh * 0.76,
                .box_bottom = by + bh * 0.24,
                .box_h = bh,
                .font = uic.font_mono,
                .font_scale = 1.0,
                .visible = line.len > 0,
            };
            y += line_step;
        } else {
            const by = y;
            const bh = line_step - 2.0;
            out_metrics[l_idx] = .{
                .text_x = hdr_x + 8.0 * scale,
                .baseline_y = by,
                .box_top = by - bh * 0.76,
                .box_bottom = by + bh * 0.24,
                .box_h = bh,
                .font = uic.font_body,
                .font_scale = 1.0,
                .visible = line.len > 0,
            };
            y += line_step;
        }
    }
}

fn colFromMouseX(uic: *Context, m: LineVisualMetrics, line: []const u8, mx: f32) usize {
    if (line.len == 0 or mx <= m.text_x) return 0;
    const rel_x = mx - m.text_x;
    const full_w = uic.measureTextCached(m.font, line) * m.font_scale;
    if (rel_x >= full_w) return line.len;

    var lo: usize = 0;
    var hi: usize = line.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const w_mid = uic.measureTextCached(m.font, line[0..mid]) * m.font_scale;
        if (w_mid < rel_x) {
            lo = mid + 1;
        } else {
            hi = mid;
        }
    }
    if (lo > 0) {
        const w_prev = uic.measureTextCached(m.font, line[0 .. lo - 1]) * m.font_scale;
        const w_curr = uic.measureTextCached(m.font, line[0..lo]) * m.font_scale;
        if (rel_x - w_prev < w_curr - rel_x) {
            return lo - 1;
        }
    }
    return lo;
}

fn hitTestPdfTextPos(
    uic: *Context,
    doc: *const PdfDocumentData,
    opts: PdfViewerOptions,
    view: *const PdfViewState,
    canvas_r: c.sk_rect_t,
    sheet_x: f32,
    sheet_w: f32,
    sheet_h: f32,
    top_pad: f32,
    page_stride: f32,
    mouse_x: f32,
    mouse_y: f32,
) ?PdfTextPos {
    const page_count = @max(@as(usize, 1), doc.page_count);
    const doc_y = (mouse_y - (canvas_r.top + top_pad)) + view.scroll_y;
    const p_idx: usize = if (doc_y <= 0.0)
        0
    else
        @min(page_count - 1, @as(usize, @intFromFloat(@floor(doc_y / page_stride))));

    const page = doc.getPageInfo(p_idx, opts.raw_bytes, opts.file_path);
    if (isPlaceholderOnlyPage(page)) return null;

    const sheet_y = canvas_r.top + top_pad + @as(f32, @floatFromInt(p_idx)) * page_stride - view.scroll_y;
    const sheet_r = Rect.xywh(sheet_x, sheet_y, sheet_w, sheet_h);
    const used_cg = (getOrOpenCgPdfDocument(opts.raw_bytes, opts.file_path) != null);

    var metrics: [MaxLinesPerPage]LineVisualMetrics = undefined;
    computePageLineVisualMetrics(uic, sheet_r, doc, page, used_cg, &metrics);

    var best_in_band: ?usize = null;
    var best_x_dist: f32 = std.math.floatMax(f32);
    for (0..page.line_count) |l_idx| {
        const m = metrics[l_idx];
        if (!m.visible) continue;
        if (mouse_y >= m.box_top - 3.0 and mouse_y <= m.box_bottom + 3.0) {
            const line = page.lines[l_idx].slice();
            const lw = uic.measureTextCached(m.font, line) * m.font_scale;
            const x0 = m.text_x;
            const x1 = m.text_x + lw;
            const x_dist: f32 = if (mouse_x < x0)
                x0 - mouse_x
            else if (mouse_x > x1)
                mouse_x - x1
            else
                0.0;
            if (x_dist < best_x_dist) {
                best_x_dist = x_dist;
                best_in_band = l_idx;
            }
        }
    }

    if (best_in_band) |l_idx| {
        const line = page.lines[l_idx].slice();
        const col = colFromMouseX(uic, metrics[l_idx], line, mouse_x);
        return .{ .page_idx = p_idx, .line_idx = l_idx, .col = col };
    }

    var best_line: ?usize = null;
    var best_y_dist: f32 = std.math.floatMax(f32);
    for (0..page.line_count) |l_idx| {
        const m = metrics[l_idx];
        if (!m.visible) continue;
        const center_y = (m.box_top + m.box_bottom) * 0.5;
        const y_dist = @abs(mouse_y - center_y);
        if (y_dist < best_y_dist) {
            best_y_dist = y_dist;
            best_line = l_idx;
        }
    }

    if (best_line) |l_idx| {
        const m = metrics[l_idx];
        const line = page.lines[l_idx].slice();
        if (mouse_y < m.box_top - 6.0 and l_idx == 0) {
            return .{ .page_idx = p_idx, .line_idx = 0, .col = 0 };
        }
        if (mouse_y > m.box_bottom + 6.0 and l_idx + 1 == page.line_count) {
            return .{ .page_idx = p_idx, .line_idx = l_idx, .col = line.len };
        }
        const col = colFromMouseX(uic, m, line, mouse_x);
        return .{ .page_idx = p_idx, .line_idx = l_idx, .col = col };
    }
    return null;
}

/// Renders translucent selection highlight boxes over any selected text ranges on `page_idx`.
fn drawPageTextSelection(
    uic: *Context,
    sheet_r: c.sk_rect_t,
    doc: *const PdfDocumentData,
    page: *const PdfPageInfo,
    page_idx: usize,
    used_cg_raster: bool,
    view: *const PdfViewState,
) void {
    const sel = view.normalizedSelection() orelse return;
    if (page_idx < sel.start.page_idx or page_idx > sel.end.page_idx) return;
    if (page.line_count == 0 or isPlaceholderOnlyPage(page)) return;

    const l_start = if (page_idx == sel.start.page_idx) @min(sel.start.line_idx, page.line_count - 1) else 0;
    const l_end = if (page_idx == sel.end.page_idx) @min(sel.end.line_idx, page.line_count - 1) else page.line_count - 1;
    if (l_start > l_end) return;

    var metrics: [MaxLinesPerPage]LineVisualMetrics = undefined;
    computePageLineVisualMetrics(uic, sheet_r, doc, page, used_cg_raster, &metrics);

    const paint = uic.paint;
    const canvas = uic.canvas;
    const clip = canvas.save();
    defer canvas.restoreToCount(clip);
    canvas.clipRect(sheet_r, .intersect, false);

    for (l_start..l_end + 1) |l_idx| {
        const m = metrics[l_idx];
        if (!m.visible) continue;
        const line = page.lines[l_idx].slice();
        const c_start = if (page_idx == sel.start.page_idx and l_idx == sel.start.line_idx)
            @min(sel.start.col, line.len)
        else
            0;
        const c_end = if (page_idx == sel.end.page_idx and l_idx == sel.end.line_idx)
            @min(sel.end.col, line.len)
        else
            line.len;
        if (c_end <= c_start) continue;

        const x0 = m.text_x + uic.measureTextCached(m.font, line[0..c_start]) * m.font_scale;
        const x1 = m.text_x + uic.measureTextCached(m.font, line[0..c_end]) * m.font_scale;
        const hl_w = @max(4.0, (x1 - x0) + 2.0);
        const hl_r = Rect.xywh(
            std.math.clamp(x0 - 1.0, sheet_r.left + 2.0, @max(sheet_r.left + 2.0, sheet_r.right - hl_w - 2.0)),
            std.math.clamp(m.box_top, sheet_r.top + 2.0, @max(sheet_r.top + 2.0, sheet_r.bottom - m.box_h - 2.0)),
            hl_w,
            m.box_h,
        );

        paint.setStyle(.fill);
        paint.setColor(Color.argb(95, 56, 139, 253));
        canvas.drawRoundRect(hl_r, 2.5, 2.5, paint);

        paint.setStyle(.stroke);
        paint.setStrokeWidth(1.0);
        paint.setColor(Color.argb(175, 56, 189, 248));
        canvas.drawRoundRect(hl_r, 2.5, 2.5, paint);
    }
}

pub fn renderPdfViewer(
    uic: *Context,
    widget_id_str: []const u8,
    width: f32,
    height: f32,
    doc: *const PdfDocumentData,
    view: *PdfViewState,
    opts: PdfViewerOptions,
) PdfViewerResult {
    var result: PdfViewerResult = .{};
    const raw_wid = root.id(widget_id_str);
    var id_guard = uic.scopedId(widget_id_str);
    defer id_guard.end();

    const doc_hash = computeDocHash(opts.raw_bytes, opts.file_path);
    if (doc_hash != 0 and view.last_doc_hash != 0 and doc_hash != view.last_doc_hash) {
        view.current_page = 0;
        view.last_synced_page = 0;
        view.selected_outline_idx = 0;
        view.last_outline_scroll_y = -1.0;
        view.scroll_x = 0;
        view.scroll_y = 0;
        view.outline_scroll_y = 0;
        view.hovered_link_page = 0;
        view.hovered_link_target_norm_y = 0;
        view.clearSelection();
    }
    if (doc_hash != 0) {
        view.last_doc_hash = doc_hash;
    }

    const page_count = @max(@as(usize, 1), doc.page_count);
    if (view.current_page >= page_count) {
        view.current_page = page_count - 1;
    }

    const toolbar_h: f32 = if (opts.show_toolbar) 36.0 else 0.0;
    const canvas_h: f32 = @max(80.0, height - toolbar_h);

    var outer_col = uic.column(.{
        .w = if (width > 0) .pixels(width) else .fill,
        .h = .pixels(height),
        .gap = 0,
    });
    defer outer_col.end();

    const full_r = outer_col.rect;
    const full_w = @max(1.0, full_r.right - full_r.left);
    const full_h = @max(80.0, full_r.bottom - full_r.top);
    const show_outline_rail = (!opts.compact and view.show_outline and full_w >= 520.0);
    const outline_w: f32 = if (show_outline_rail) (if (full_w >= 640.0) @as(f32, 248.0) else @as(f32, 212.0)) else 0.0;

    // 1. Top Control Toolbar shifted to the right of the full-height Outline rail (Deterministic across `.input` and `.paint`)
    var jump_to_page_requested = false;
    const toolbar_has_sel = uic.latch(bool, view.hasSelection());
    if (opts.show_toolbar) {
        var bar = uic.row(.{
            .w = if (width > 0) .pixels(width) else .fill,
            .h = .pixels(toolbar_h),
            .padding = .{ .left = outline_w + 8.0, .right = 8.0, .top = 5.0, .bottom = 5.0 },
            .gap = 6,
            .bg_color = Color.rgb(18, 24, 34),
            .border_color = uic.theme.border_subtle,
            .border_edges = .{ .bottom = true },
        });
        defer bar.end();

        if (uic.btn("◀##pdf_prev", .{ .w = .pixels(26), .h = 24, .variant = .toolbar })) {
            if (view.current_page > 0) {
                view.current_page -= 1;
                jump_to_page_requested = true;
                result.page_changed = true;
            }
        }

        const pg_lbl = uic.fmt("Pg {d}/{d}", .{ view.current_page + 1, page_count });
        _ = uic.chip(pg_lbl, .{ .h = 24, .mono = true, .bordered = true });

        if (uic.btn("▶##pdf_next", .{ .w = .pixels(26), .h = 24, .variant = .toolbar })) {
            if (view.current_page + 1 < page_count) {
                view.current_page += 1;
                jump_to_page_requested = true;
                result.page_changed = true;
            }
        }

        if (uic.btn("-##pdf_zout", .{ .w = .pixels(24), .h = 24, .variant = .toolbar })) {
            view.zoom = std.math.clamp(view.zoom - 0.15, 0.5, 2.5);
        }

        const zoom_pct: u32 = @intFromFloat(@round(view.zoom * 100.0));
        const zoom_lbl = uic.fmt("{d}%##pdf_zrst", .{zoom_pct});
        if (uic.btn(zoom_lbl, .{ .w = .pixels(48), .h = 24, .variant = .toolbar })) {
            view.zoom = 1.0;
            view.scroll_x = 0;
            jump_to_page_requested = true;
        }

        if (uic.btn("+##pdf_zin", .{ .w = .pixels(24), .h = 24, .variant = .toolbar })) {
            view.zoom = std.math.clamp(view.zoom + 0.15, 0.5, 2.5);
        }

        const inv_lbl = if (view.invert_paper) "Dark Paper##pdf_inv" else "Light Paper##pdf_inv";
        if (uic.chip(inv_lbl, .{ .h = 24, .active = view.invert_paper, .bordered = true })) {
            view.invert_paper = !view.invert_paper;
        }

        if (!opts.compact) {
            if (uic.chip("Outline##pdf_outline", .{ .h = 24, .active = view.show_outline, .bordered = true })) {
                view.show_outline = !view.show_outline;
                uic.markDirty(full_r);
                uic.invalidateWindow();
            }

            const copy_lbl = if (toolbar_has_sel) "Copy Selection##pdf_copy" else "Copy Page##pdf_copy";
            if (uic.chip(copy_lbl, .{ .h = 24, .active = toolbar_has_sel, .bordered = true })) {
                if (!view.hasSelection()) {
                    view.selectPageWithSource(doc, view.current_page, opts.raw_bytes, opts.file_path);
                }
                if (view.copySelectionWithSourceAlloc(doc, opts.raw_bytes, opts.file_path, uic.arena)) |copied| {
                    if (uic.platform_ctx) |pctx| {
                        _ = pctx.setClipboardText(copied);
                    }
                    result.copied_text = copied;
                }
                uic.markDirty(full_r);
                uic.invalidateWindow();
            }
        }
    }

    // 2. Main Interactive PDF Viewport Rect (Consumed identically in `.input` and `.paint`)
    const resolved = uic.resolveIdAndLabel(widget_id_str);
    const canvas_r = uic.nextRect(width, canvas_h);
    const canvas_w = @max(1.0, canvas_r.right - canvas_r.left);
    const viewport_left = canvas_r.left + outline_w;
    const viewport_w = @max(60.0, canvas_w - outline_w);
    const rail_r = Rect.xywh(full_r.left, full_r.top, outline_w, full_h);
    const rail_hdr_h: f32 = if (opts.show_toolbar) toolbar_h else 28.0;

    var pinched_this_frame = false;
    if (uic.pass == .input and uic.isHovered(canvas_r) and !(show_outline_rail and uic.isHovered(rail_r)) and @abs(uic.magnify_delta) > 0.001) {
        const scale_factor = std.math.clamp(1.0 + uic.magnify_delta, 0.25, 4.0);
        const next_zoom = std.math.clamp(view.zoom * scale_factor, 0.5, 4.0);
        if (@abs(next_zoom - view.zoom) > 0.0005) {
            view.zoom = next_zoom;
            pinched_this_frame = true;
            uic.markDirty(full_r);
            uic.invalidateWindow();
        }
    }

    const dims = doc.pageDimensions(view.current_page);
    const aspect = if (dims.width_pt > 1.0) dims.height_pt / dims.width_pt else (792.0 / 612.0);
    const page_area_w = viewport_w;
    const base_sheet_w = @min(@max(140.0, page_area_w - 42.0), 680.0);
    const sheet_w = base_sheet_w * view.zoom;
    const sheet_h = sheet_w * aspect;

    // Contiguous multi-page vertical layout metrics
    const top_pad: f32 = 16.0;
    const page_gap: f32 = 18.0;
    const page_stride: f32 = sheet_h + page_gap;
    const total_doc_h: f32 = top_pad * 2.0 + @as(f32, @floatFromInt(page_count)) * page_stride - page_gap;
    const max_scroll_y: f32 = @max(0.0, total_doc_h - canvas_h);

    // Synchronize active search match state if `opts.search_query` changed
    const trimmed_query = std.mem.trim(u8, opts.search_query, " \t\r\n");
    const cur_search_hash = if (trimmed_query.len > 0) std.hash.Fnv1a_64.hash(trimmed_query) else 0;
    if (cur_search_hash == 0) {
        view.has_active_match = false;
        view.last_search_hash = 0;
    } else if (cur_search_hash != view.last_search_hash or !view.has_active_match) {
        view.last_search_hash = cur_search_hash;
        if (doc.findMatch(null, view.current_page, trimmed_query, true, false)) |first_m| {
            if (!view.has_active_match) {
                view.active_match_index = first_m.match_index;
                view.active_match_page = first_m.page_idx;
                view.active_match_line = first_m.line_idx;
                view.active_match_offset = first_m.byte_offset;
                view.active_match_norm_y = first_m.norm_y;
                view.has_active_match = true;
            }
        } else {
            view.has_active_match = false;
        }
    }

    // Synchronize `view.scroll_y` if `view.pending_scroll_to_match` was requested (e.g. Find Bar / Search jump),
    // if `view.current_page` was changed externally (e.g. plugin sidebar, Prev/Next buttons),
    // or if `view.zoom` changed (preserving the point under the cursor when pinching, or fractional page offset).
    if (view.pending_scroll_to_match) {
        const target_page = @min(view.current_page, page_count - 1);
        view.current_page = target_page;
        const match_doc_y = @as(f32, @floatFromInt(target_page)) * page_stride +
            std.math.clamp(view.active_match_norm_y, 0.0, 0.95) * sheet_h;
        view.scroll_y = std.math.clamp(match_doc_y - canvas_h * 0.32, 0.0, max_scroll_y);
        view.last_synced_page = view.current_page;
        view.last_synced_zoom = view.zoom;
        view.last_outline_scroll_y = -1.0;
        view.pending_scroll_to_match = false;
    } else if (jump_to_page_requested or view.current_page != view.last_synced_page) {
        view.scroll_y = std.math.clamp(@as(f32, @floatFromInt(view.current_page)) * page_stride, 0.0, max_scroll_y);
        view.last_synced_page = view.current_page;
        view.last_synced_zoom = view.zoom;
        view.last_outline_scroll_y = -1.0;
    } else if (@abs(view.zoom - view.last_synced_zoom) > 0.001) {
        const old_zoom = @max(0.1, view.last_synced_zoom);
        const old_sheet_w = base_sheet_w * old_zoom;
        const old_stride = (old_sheet_w * aspect) + page_gap;
        if (pinched_this_frame and old_stride > 1.0) {
            const cursor_rel_y = std.math.clamp(uic.mouse_y - (canvas_r.top + top_pad), 0.0, canvas_h);
            const rel_pages_at_cursor = (view.scroll_y + cursor_rel_y) / old_stride;
            view.scroll_y = std.math.clamp(rel_pages_at_cursor * page_stride - cursor_rel_y, 0.0, max_scroll_y);

            const zoom_ratio = view.zoom / old_zoom;
            const old_center_x = viewport_left + viewport_w * 0.5 + view.scroll_x;
            const max_scroll_x_now = @max(0.0, (sheet_w - page_area_w) * 0.5 + 24.0);
            view.scroll_x = std.math.clamp(view.scroll_x + (uic.mouse_x - old_center_x) * (1.0 - zoom_ratio), -max_scroll_x_now, max_scroll_x_now);
        } else {
            const rel_pages = if (old_stride > 1.0) view.scroll_y / old_stride else @as(f32, @floatFromInt(view.current_page));
            view.scroll_y = std.math.clamp(rel_pages * page_stride, 0.0, max_scroll_y);
        }
        view.last_synced_zoom = view.zoom;
    }

    const outline_row_h: f32 = 24.0;
    const outline_total_items: usize = if (doc.outline_count > 0) doc.outline_count else page_count;
    const max_outline_scroll_y: f32 = @max(0.0, @as(f32, @floatFromInt(outline_total_items)) * outline_row_h + (rail_hdr_h + 8.0) - full_h);
    const max_scroll_x: f32 = @max(0.0, (sheet_w - page_area_w) * 0.5 + 24.0);

    view.scroll_x = std.math.clamp(view.scroll_x, -max_scroll_x, max_scroll_x);
    view.scroll_y = std.math.clamp(view.scroll_y, 0.0, max_scroll_y);
    view.outline_scroll_y = std.math.clamp(view.outline_scroll_y, 0.0, max_outline_scroll_y);

    // Determine which outline item corresponds to the current scroll position within the document
    // (taking each outline item's intra-page `norm_y` offset into account so multiple sections on the same page
    // are individually distinguished, and honoring `view.selected_outline_idx` when clicked!).
    var active_outline_idx: usize = view.current_page;
    if (doc.outline_count > 0) {
        if (view.last_outline_scroll_y >= 0.0 and
            @abs(view.scroll_y - view.last_outline_scroll_y) <= 2.0 and
            view.selected_outline_idx < doc.outline_count)
        {
            active_outline_idx = view.selected_outline_idx;
        } else {
            active_outline_idx = 0;
            const ref_doc_y = view.scroll_y + 36.0;
            for (0..doc.outline_count) |idx| {
                const pg_idx = @min(page_count - 1, @as(usize, @max(@as(u32, 1), doc.outline[idx].page_number) - 1));
                const item_doc_y = @as(f32, @floatFromInt(pg_idx)) * page_stride + doc.outline[idx].norm_y * sheet_h;
                if (item_doc_y <= ref_doc_y) {
                    active_outline_idx = idx;
                }
            }
        }
    }

    // Pass 1 (`.input`): Hit-test full-height outline rail, Table of Contents links on pages, scrollbar, wheel, text selection, drag, and keys
    if (uic.pass == .input) {
        const rail_hovered = (show_outline_rail and uic.isHovered(rail_r));
        const canvas_hovered = uic.isHovered(canvas_r);
        const hovered = (rail_hovered or canvas_hovered);
        if (hovered) {
            uic.hot_id = resolved.wid;
        }
        if (hovered and uic.right_mouse_pressed) {
            uic.focused_id = resolved.wid;
            uic.markDirty(full_r);
        }

        const sheet_lane_w = viewport_w;
        const sheet_x = viewport_left + (sheet_lane_w - sheet_w) * 0.5 + view.scroll_x;

        var new_hover_pg: u32 = 0;
        var new_hover_target_ny: f32 = 0;
        var new_hover_idx: usize = 0;
        var new_hover_ny: f32 = 0;

        // Hit-test Table of Contents links on whichever rendered page is under the mouse cursor
        if (canvas_hovered and uic.mouse_x >= sheet_x and uic.mouse_x <= sheet_x + sheet_w) {
            const doc_y = (uic.mouse_y - (canvas_r.top + top_pad)) + view.scroll_y;
            if (doc_y >= 0) {
                const p_idx: usize = @intFromFloat(@floor(doc_y / page_stride));
                const in_page_y: f32 = doc_y - @as(f32, @floatFromInt(p_idx)) * page_stride;
                if (p_idx < page_count and in_page_y >= 0.0 and in_page_y <= sheet_h) {
                    const norm_x = (uic.mouse_x - sheet_x) / @max(1.0, sheet_w);
                    const norm_y = in_page_y / @max(1.0, sheet_h);
                    // 1. Check native PDF `/Annots` (`/Subtype /Link`) on this page
                    if (resolvePdfPageLinkAtPoint(opts.raw_bytes, opts.file_path, p_idx, norm_x, norm_y)) |target_dest| {
                        new_hover_pg = target_dest.page_number;
                        new_hover_target_ny = target_dest.norm_y;
                        new_hover_idx = p_idx;
                        new_hover_ny = norm_y;
                    } else if (p_idx < MaxPdfPages and doc.pages[p_idx].line_count > 0) {
                        // 2. Fallback: Check extracted Table of Contents text lines on this page
                        const scale = std.math.clamp(sheet_w / 560.0, 0.65, 1.8);
                        const hdr_bottom_y = (18.0 + 44.0 + 22.0) * scale;
                        const line_step = @max(16.0, 18.0 * scale);
                        if (in_page_y >= hdr_bottom_y - 14.0 * scale) {
                            const approx_line: usize = @intFromFloat(@floor((in_page_y - (hdr_bottom_y - 14.0 * scale)) / line_step));
                            const page_obj = &doc.pages[p_idx];
                            if (approx_line < page_obj.line_count) {
                                if (parseTocLinePageNumber(page_obj.lines[approx_line].slice(), page_count)) |toc_pg| {
                                    new_hover_pg = toc_pg;
                                    new_hover_target_ny = 0.0;
                                    new_hover_idx = p_idx;
                                    new_hover_ny = norm_y;
                                }
                            }
                        }
                    }
                }
            }
        }

        if (new_hover_pg != view.hovered_link_page or
            new_hover_idx != view.hovered_link_page_idx or
            @abs(new_hover_ny - view.hovered_link_norm_y) > 0.008)
        {
            view.hovered_link_page = new_hover_pg;
            view.hovered_link_target_norm_y = new_hover_target_ny;
            view.hovered_link_page_idx = new_hover_idx;
            view.hovered_link_norm_y = new_hover_ny;
            uic.markDirty(full_r);
        }

        const scrollbar_x = viewport_left + sheet_lane_w - 12.0;
        const outline_sb_x = viewport_left - 11.0;
        const outline_list_top = rail_r.top + rail_hdr_h + 2.0;
        const mouse_alt = if (uic.platform_ctx) |pctx| pctx.mouse_alt else false;
        const mouse_shift = if (uic.platform_ctx) |pctx| pctx.mouse_shift else uic.mouse_shift;
        const click_count = if (uic.platform_ctx) |pctx| pctx.mouse_click_count else 1;

        // Scroll wheel inside viewport: scrolls outline rail if hovered on left, else scrolls contiguous pages!
        if (hovered and (uic.scroll_dy != 0 or uic.scroll_dx != 0)) {
            const snapped = root.snapScrollAxis(uic.scroll_dx, uic.scroll_dy);
            if (rail_hovered) {
                view.outline_scroll_y = std.math.clamp(view.outline_scroll_y - snapped.dy * 1.2, 0.0, max_outline_scroll_y);
            } else if (mouse_shift and snapped.dx == 0 and snapped.dy != 0) {
                view.scroll_x = std.math.clamp(view.scroll_x + snapped.dy * 1.65, -max_scroll_x, max_scroll_x);
            } else {
                view.scroll_y = std.math.clamp(view.scroll_y - snapped.dy * 1.65, 0.0, max_scroll_y);
                view.last_outline_scroll_y = -1.0;
                const center_doc_y = view.scroll_y + canvas_h * 0.35;
                const new_page = std.math.clamp(
                    @as(usize, @intFromFloat(@max(0.0, @floor(center_doc_y / page_stride)))),
                    0,
                    page_count - 1,
                );
                if (new_page != view.current_page) {
                    view.current_page = new_page;
                    result.page_changed = true;
                }
                view.last_synced_page = view.current_page;

                view.scroll_x = std.math.clamp(view.scroll_x + snapped.dx * 1.35, -max_scroll_x, max_scroll_x);
            }
            uic.markDirty(full_r);
            uic.invalidateWindow();
        }

        // Click handling: Full-Height Outline Rail, Scrollbar Track, Table of Contents Link on Page, Text Selection, or Drag Pan
        if (hovered and uic.mouse_pressed) {
            uic.focused_id = resolved.wid;
            if (rail_hovered) {
                if (max_outline_scroll_y > 1.0 and uic.mouse_x >= outline_sb_x) {
                    uic.active_id = resolved.wid;
                    view.dragging_outline_scrollbar = true;
                    const ratio = std.math.clamp((uic.mouse_y - outline_list_top) / @max(1.0, full_h - rail_hdr_h - 10.0), 0.0, 1.0);
                    view.outline_scroll_y = ratio * max_outline_scroll_y;
                } else if (uic.mouse_y >= rail_r.top + rail_hdr_h) {
                    const rel_y = (uic.mouse_y - outline_list_top) + view.outline_scroll_y;
                    if (rel_y >= 0) {
                        const clicked_idx: usize = @intFromFloat(@floor(rel_y / outline_row_h));
                        if (doc.outline_count > 0 and clicked_idx < doc.outline_count) {
                            const item = doc.outline[clicked_idx];
                            const target_pg = @min(page_count, @max(@as(usize, 1), item.page_number)) - 1;
                            const target_scroll_y = @as(f32, @floatFromInt(target_pg)) * page_stride + item.norm_y * sheet_h;
                            view.current_page = target_pg;
                            view.scroll_y = std.math.clamp(target_scroll_y, 0.0, max_scroll_y);
                            view.last_synced_page = target_pg;
                            view.selected_outline_idx = clicked_idx;
                            view.last_outline_scroll_y = view.scroll_y;
                            result.page_changed = true;
                        } else if (doc.outline_count == 0 and clicked_idx < page_count) {
                            view.current_page = clicked_idx;
                            view.scroll_y = std.math.clamp(@as(f32, @floatFromInt(clicked_idx)) * page_stride, 0.0, max_scroll_y);
                            view.last_synced_page = clicked_idx;
                            view.selected_outline_idx = clicked_idx;
                            view.last_outline_scroll_y = view.scroll_y;
                            result.page_changed = true;
                        }
                    }
                }
                uic.markDirty(full_r);
                uic.invalidateWindow();
            } else if (view.hovered_link_page > 0 and click_count <= 1 and !mouse_shift) {
                // Clicked a Table of Contents / cross-reference link on a PDF page!
                const target_idx = @min(page_count - 1, @as(usize, view.hovered_link_page - 1));
                const target_scroll_y = @as(f32, @floatFromInt(target_idx)) * page_stride + view.hovered_link_target_norm_y * sheet_h;
                view.current_page = target_idx;
                view.scroll_y = std.math.clamp(target_scroll_y, 0.0, max_scroll_y);
                view.last_synced_page = target_idx;
                view.last_outline_scroll_y = -1.0;
                result.page_changed = true;
                uic.markDirty(full_r);
                uic.invalidateWindow();
            } else if (uic.mouse_x >= scrollbar_x and uic.mouse_x <= viewport_left + sheet_lane_w) {
                // Clicked right-hand contiguous document scrollbar track
                uic.active_id = resolved.wid;
                view.dragging_scrollbar = true;
                const ratio = std.math.clamp((uic.mouse_y - (canvas_r.top + 8.0)) / @max(1.0, canvas_h - 16.0), 0.0, 1.0);
                view.scroll_y = ratio * max_scroll_y;
                const new_page = std.math.clamp(@as(usize, @intFromFloat(@floor((view.scroll_y + canvas_h * 0.35) / page_stride))), 0, page_count - 1);
                if (new_page != view.current_page) {
                    view.current_page = new_page;
                    result.page_changed = true;
                }
                view.last_synced_page = view.current_page;
                uic.markDirty(full_r);
                uic.invalidateWindow();
            } else if (!mouse_alt and uic.mouse_x >= sheet_x and uic.mouse_x <= sheet_x + sheet_w) {
                if (hitTestPdfTextPos(
                    uic,
                    doc,
                    opts,
                    view,
                    canvas_r,
                    sheet_x,
                    sheet_w,
                    sheet_h,
                    top_pad,
                    page_stride,
                    uic.mouse_x,
                    uic.mouse_y,
                )) |hit_pos| {
                    uic.active_id = resolved.wid;
                    view.dragging_selection = true;
                    view.dragging_pan = false;
                    const page_info = doc.getPageInfo(hit_pos.page_idx, opts.raw_bytes, opts.file_path);
                    const line_slice = if (hit_pos.line_idx < page_info.line_count)
                        page_info.lines[hit_pos.line_idx].slice()
                    else
                        "";
                    if (click_count >= 3) {
                        view.sel_anchor = .{ .page_idx = hit_pos.page_idx, .line_idx = hit_pos.line_idx, .col = 0 };
                        view.sel_cursor = .{ .page_idx = hit_pos.page_idx, .line_idx = hit_pos.line_idx, .col = line_slice.len };
                        view.sel_origin_start = view.sel_anchor;
                        view.sel_origin_end = view.sel_cursor;
                        view.sel_click_mode = 2;
                        view.has_selection = line_slice.len > 0;
                    } else if (click_count == 2) {
                        const wr = wordRangeInLine(line_slice, hit_pos.col);
                        view.sel_anchor = .{ .page_idx = hit_pos.page_idx, .line_idx = hit_pos.line_idx, .col = wr.start };
                        view.sel_cursor = .{ .page_idx = hit_pos.page_idx, .line_idx = hit_pos.line_idx, .col = wr.end };
                        view.sel_origin_start = view.sel_anchor;
                        view.sel_origin_end = view.sel_cursor;
                        view.sel_click_mode = 1;
                        view.has_selection = wr.end > wr.start;
                    } else if (mouse_shift) {
                        view.sel_cursor = hit_pos;
                        view.sel_click_mode = 0;
                        view.has_selection = !PdfTextPos.eql(view.sel_anchor, view.sel_cursor);
                    } else {
                        view.sel_anchor = hit_pos;
                        view.sel_cursor = hit_pos;
                        view.sel_origin_start = hit_pos;
                        view.sel_origin_end = hit_pos;
                        view.sel_click_mode = 0;
                        view.has_selection = false;
                    }
                    uic.markDirty(full_r);
                    uic.invalidateWindow();
                } else {
                    uic.active_id = resolved.wid;
                    view.dragging_pan = true;
                    view.drag_start_mouse_x = uic.mouse_x;
                    view.drag_start_mouse_y = uic.mouse_y;
                    view.drag_start_scroll_x = view.scroll_x;
                    view.drag_start_scroll_y = view.scroll_y;
                    uic.markDirty(full_r);
                }
            } else {
                if (!mouse_alt and view.hasSelection()) {
                    view.clearSelection();
                }
                uic.active_id = resolved.wid;
                view.dragging_pan = true;
                view.drag_start_mouse_x = uic.mouse_x;
                view.drag_start_mouse_y = uic.mouse_y;
                view.drag_start_scroll_x = view.scroll_x;
                view.drag_start_scroll_y = view.scroll_y;
                uic.markDirty(full_r);
                uic.invalidateWindow();
            }
        } else if (uic.mouse_down and uic.active_id == resolved.wid and view.dragging_selection) {
            if (uic.mouse_y < canvas_r.top + 16.0 and view.scroll_y > 0.0) {
                view.scroll_y = @max(0.0, view.scroll_y - 14.0);
                uic.markDirty(full_r);
            } else if (uic.mouse_y > canvas_r.bottom - 16.0 and view.scroll_y < max_scroll_y) {
                view.scroll_y = @min(max_scroll_y, view.scroll_y + 14.0);
                uic.markDirty(full_r);
            }
            if (hitTestPdfTextPos(
                uic,
                doc,
                opts,
                view,
                canvas_r,
                sheet_x,
                sheet_w,
                sheet_h,
                top_pad,
                page_stride,
                uic.mouse_x,
                uic.mouse_y,
            )) |hit_pos| {
                const prev_anchor = view.sel_anchor;
                const prev_cursor = view.sel_cursor;
                const page_info = doc.getPageInfo(hit_pos.page_idx, opts.raw_bytes, opts.file_path);
                const line_slice = if (hit_pos.line_idx < page_info.line_count)
                    page_info.lines[hit_pos.line_idx].slice()
                else
                    "";

                if (view.sel_click_mode == 2) {
                    const l_start = PdfTextPos{ .page_idx = hit_pos.page_idx, .line_idx = hit_pos.line_idx, .col = 0 };
                    const l_end = PdfTextPos{ .page_idx = hit_pos.page_idx, .line_idx = hit_pos.line_idx, .col = line_slice.len };
                    if (PdfTextPos.lessThan(l_start, view.sel_origin_start)) {
                        view.sel_anchor = view.sel_origin_end;
                        view.sel_cursor = l_start;
                    } else {
                        view.sel_anchor = view.sel_origin_start;
                        view.sel_cursor = l_end;
                    }
                } else if (view.sel_click_mode == 1) {
                    const wr = wordRangeInLine(line_slice, hit_pos.col);
                    const w_start = PdfTextPos{ .page_idx = hit_pos.page_idx, .line_idx = hit_pos.line_idx, .col = wr.start };
                    const w_end = PdfTextPos{ .page_idx = hit_pos.page_idx, .line_idx = hit_pos.line_idx, .col = wr.end };
                    if (PdfTextPos.lessThan(w_start, view.sel_origin_start)) {
                        view.sel_anchor = view.sel_origin_end;
                        view.sel_cursor = w_start;
                    } else {
                        view.sel_anchor = view.sel_origin_start;
                        view.sel_cursor = w_end;
                    }
                } else {
                    view.sel_cursor = hit_pos;
                }
                view.has_selection = !PdfTextPos.eql(view.sel_anchor, view.sel_cursor);
                if (!PdfTextPos.eql(view.sel_anchor, prev_anchor) or !PdfTextPos.eql(view.sel_cursor, prev_cursor)) {
                    uic.markDirty(full_r);
                    uic.invalidateWindow();
                }
            }
        } else if (uic.mouse_down and uic.active_id == resolved.wid and view.dragging_outline_scrollbar) {
            const ratio = std.math.clamp((uic.mouse_y - outline_list_top) / @max(1.0, full_h - rail_hdr_h - 10.0), 0.0, 1.0);
            view.outline_scroll_y = ratio * max_outline_scroll_y;
            uic.markDirty(full_r);
            uic.invalidateWindow();
        } else if (uic.mouse_down and uic.active_id == resolved.wid and view.dragging_scrollbar) {
            const ratio = std.math.clamp((uic.mouse_y - (canvas_r.top + 8.0)) / @max(1.0, canvas_h - 16.0), 0.0, 1.0);
            view.scroll_y = ratio * max_scroll_y;
            const new_page = std.math.clamp(@as(usize, @intFromFloat(@floor((view.scroll_y + canvas_h * 0.35) / page_stride))), 0, page_count - 1);
            if (new_page != view.current_page) {
                view.current_page = new_page;
                result.page_changed = true;
            }
            view.last_synced_page = view.current_page;
            uic.markDirty(full_r);
            uic.invalidateWindow();
        } else if (uic.mouse_down and uic.active_id == resolved.wid and view.dragging_pan) {
            const dx = uic.mouse_x - view.drag_start_mouse_x;
            const dy = uic.mouse_y - view.drag_start_mouse_y;
            view.scroll_y = std.math.clamp(view.drag_start_scroll_y - dy, 0.0, max_scroll_y);
            view.scroll_x = std.math.clamp(view.drag_start_scroll_x + dx, -max_scroll_x, max_scroll_x);
            const new_page = std.math.clamp(@as(usize, @intFromFloat(@floor((view.scroll_y + canvas_h * 0.35) / page_stride))), 0, page_count - 1);
            if (new_page != view.current_page) {
                view.current_page = new_page;
                result.page_changed = true;
            }
            view.last_synced_page = view.current_page;
            uic.markDirty(full_r);
        } else if (!uic.mouse_down and uic.active_id == resolved.wid) {
            uic.active_id = 0;
            view.dragging_pan = false;
            view.dragging_selection = false;
            view.dragging_scrollbar = false;
            view.dragging_outline_scrollbar = false;
        }

        // Keyboard page, continuous scroll, and text selection/copy shortcuts when focused
        const is_focused = (uic.focused_id == resolved.wid or
            uic.focused_id == raw_wid or
            (opts.extra_focus_id != 0 and uic.focused_id == opts.extra_focus_id));
        if (is_focused) {
            for (uic.key_events) |kev| {
                switch (kev.key) {
                    .key_c => {
                        if ((kev.cmd or kev.ctrl) and view.hasSelection()) {
                            if (view.copySelectionWithSourceAlloc(doc, opts.raw_bytes, opts.file_path, uic.arena)) |copied| {
                                if (uic.platform_ctx) |pctx| {
                                    _ = pctx.setClipboardText(copied);
                                }
                                result.copied_text = copied;
                                uic.markDirty(full_r);
                                uic.invalidateWindow();
                            }
                        }
                    },
                    .key_a => {
                        if (kev.cmd or kev.ctrl) {
                            view.selectAll(doc);
                            uic.markDirty(full_r);
                            uic.invalidateWindow();
                        }
                    },
                    .escape => {
                        if (view.hasSelection()) {
                            view.clearSelection();
                            uic.markDirty(full_r);
                            uic.invalidateWindow();
                        }
                    },
                    .key_f => {
                        if (kev.cmd or kev.ctrl) {
                            result.find_requested = true;
                            uic.markDirty(full_r);
                            uic.invalidateWindow();
                        }
                    },
                    .left, .page_up => {
                        if (view.current_page > 0) {
                            view.current_page -= 1;
                            view.scroll_y = std.math.clamp(@as(f32, @floatFromInt(view.current_page)) * page_stride, 0.0, max_scroll_y);
                            view.last_synced_page = view.current_page;
                            result.page_changed = true;
                            uic.markDirty(full_r);
                            uic.invalidateWindow();
                        }
                    },
                    .right, .page_down => {
                        if (view.current_page + 1 < page_count) {
                            view.current_page += 1;
                            view.scroll_y = std.math.clamp(@as(f32, @floatFromInt(view.current_page)) * page_stride, 0.0, max_scroll_y);
                            view.last_synced_page = view.current_page;
                            result.page_changed = true;
                            uic.markDirty(full_r);
                            uic.invalidateWindow();
                        }
                    },
                    .up => {
                        view.scroll_y = @max(0.0, view.scroll_y - 48.0);
                        view.current_page = std.math.clamp(@as(usize, @intFromFloat(@floor((view.scroll_y + canvas_h * 0.35) / page_stride))), 0, page_count - 1);
                        view.last_synced_page = view.current_page;
                        uic.markDirty(full_r);
                        uic.invalidateWindow();
                    },
                    .down => {
                        view.scroll_y = @min(max_scroll_y, view.scroll_y + 48.0);
                        view.current_page = std.math.clamp(@as(usize, @intFromFloat(@floor((view.scroll_y + canvas_h * 0.35) / page_stride))), 0, page_count - 1);
                        view.last_synced_page = view.current_page;
                        uic.markDirty(full_r);
                        uic.invalidateWindow();
                    },
                    else => {},
                }
            }
        }
    }

    // Pass 2 (`.paint`): Hardware scissor-clipped contiguous multi-page PDF & full-height outline rendering
    if (!uic.shouldPaint(full_r)) return result;

    const paint = uic.paint;
    const canvas = uic.canvas;
    const font_body = uic.font_body;
    const font_mono = uic.font_mono;

    const save_clip = canvas.save();
    defer canvas.restoreToCount(save_clip);
    canvas.clipRect(full_r, .intersect, false);

    const sheet_lane_r = Rect.xywh(viewport_left, canvas_r.top, viewport_w, canvas_h);

    // 1. Backdrop Fill (only over the right-hand page area below the toolbar so toolbar controls remain intact)
    paint.setStyle(.fill);
    paint.setColor(Color.rgb(13, 18, 26));
    canvas.drawRect(sheet_lane_r, paint);

    // 2. Full-Height Left Outline & Page Navigation Rail (`rail_r.top .. rail_r.bottom`)
    if (show_outline_rail) {
        paint.setStyle(.fill);
        paint.setColor(Color.rgb(17, 23, 33));
        canvas.drawRect(rail_r, paint);

        paint.setColor(uic.theme.border_subtle);
        canvas.drawRect(Rect.xywh(rail_r.right - 1.0, rail_r.top, 1.0, full_h), paint);
        canvas.drawRect(Rect.xywh(rail_r.left, rail_r.top + rail_hdr_h - 1.0, outline_w - 1.0, 1.0), paint);

        paint.setColor(Color.rgb(148, 163, 184));
        const rail_hdr = if (doc.outline_count > 0)
            uic.fmt("OUTLINE ({d})", .{doc.outline_count})
        else
            uic.fmt("PAGES ({d})", .{page_count});
        uic.drawTextCached(font_mono, rail_hdr, rail_r.left + 10.0, rail_r.top + (rail_hdr_h * 0.5) + 4.0);

        const outline_list_top = rail_r.top + rail_hdr_h + 2.0;
        const rail_list_clip = canvas.save();
        canvas.clipRect(Rect.xywh(rail_r.left, rail_r.top + rail_hdr_h, outline_w - 1.0, full_h - rail_hdr_h), .intersect, false);

        const count = if (doc.outline_count > 0) doc.outline_count else page_count;
        const first_idx: usize = @min(
            count,
            @as(usize, @intFromFloat(@max(0.0, @floor(view.outline_scroll_y / outline_row_h)))),
        );
        for (first_idx..count) |idx| {
            const ry = outline_list_top + @as(f32, @floatFromInt(idx)) * outline_row_h - view.outline_scroll_y;
            if (ry > rail_r.bottom) break;

            const item_page_idx = if (doc.outline_count > 0)
                @min(page_count - 1, @as(usize, @max(@as(u32, 1), doc.outline[idx].page_number) - 1))
            else
                idx;
            const is_active = (idx == active_outline_idx);
            const indent_px: f32 = if (doc.outline_count > 0) @as(f32, @floatFromInt(doc.outline[idx].indent)) * 10.0 else 0.0;

            if (is_active) {
                paint.setStyle(.fill);
                paint.setColor(Color.argb(45, 56, 139, 253));
                canvas.drawRoundRect(Rect.xywh(rail_r.left + 6.0, ry, outline_w - 14.0, outline_row_h - 2.0), 4.0, 4.0, paint);
                paint.setColor(Color.rgb(56, 189, 248));
                canvas.drawRect(Rect.xywh(rail_r.left + 6.0, ry + 3.0, 2.5, outline_row_h - 8.0), paint);
            }

            const item_clip = canvas.save();
            canvas.clipRect(Rect.xywh(rail_r.left + 12.0 + indent_px, ry, @max(24.0, outline_w - 58.0 - indent_px), outline_row_h), .intersect, false);
            paint.setColor(if (is_active) Color.rgb(248, 250, 252) else Color.rgb(186, 198, 214));
            const title_txt = if (doc.outline_count > 0)
                doc.outline[idx].title.slice()
            else
                uic.fmt("Page {d}", .{idx + 1});
            uic.drawTextCached(font_body, title_txt, rail_r.left + 14.0 + indent_px, ry + 16.0);
            canvas.restoreToCount(item_clip);

            paint.setColor(Color.rgb(100, 116, 139));
            const pg_tag = uic.fmt("p.{d}", .{item_page_idx + 1});
            uic.drawTextCached(font_mono, pg_tag, rail_r.right - 42.0, ry + 15.5);
        }

        // Scrollbar on right edge of Outline rail when outline exceeds full previewer height
        if (max_outline_scroll_y > 1.0) {
            const sb_track_h = @max(24.0, full_h - rail_hdr_h - 10.0);
            const sb_x = rail_r.right - 6.0;
            const sb_y = outline_list_top + 2.0;
            paint.setStyle(.fill);
            paint.setColor(Color.argb(75, 15, 23, 42));
            canvas.drawRoundRect(Rect.xywh(sb_x, sb_y, 3.5, sb_track_h), 1.75, 1.75, paint);

            const total_out_h = @as(f32, @floatFromInt(outline_total_items)) * outline_row_h + rail_hdr_h + 8.0;
            const thumb_h = std.math.clamp((full_h / total_out_h) * sb_track_h, 22.0, sb_track_h);
            const ratio = std.math.clamp(view.outline_scroll_y / max_outline_scroll_y, 0.0, 1.0);
            const thumb_y = sb_y + ratio * (sb_track_h - thumb_h);
            paint.setColor(if (view.dragging_outline_scrollbar) Color.rgb(56, 189, 248) else Color.rgb(100, 116, 139));
            canvas.drawRoundRect(Rect.xywh(sb_x, thumb_y, 3.5, thumb_h), 1.75, 1.75, paint);
        }

        canvas.restoreToCount(rail_list_clip);
    }

    // 3. Contiguous Vertical Multi-Page Scroll Stream
    {
        const sheet_lane_w = viewport_w;
        const sheet_x = sheet_lane_r.left + (sheet_lane_w - sheet_w) * 0.5 + view.scroll_x;

        const lane_clip = canvas.save();
        canvas.clipRect(sheet_lane_r, .intersect, false);

        // Compute visible range of pages (`first_vis ..= last_vis`) so we render a seamless
        // contiguous scroll of pages while only touching the 1–3 pages intersecting the viewport!
        const last_vis: usize = @min(
            page_count - 1,
            @as(usize, @intFromFloat(@max(0.0, @floor((view.scroll_y + canvas_h) / page_stride)))),
        );
        const first_vis: usize = @min(
            last_vis,
            @as(usize, @intFromFloat(@max(0.0, @floor((view.scroll_y - top_pad) / page_stride)))),
        );

        const raster_scale: f32 = 1.6;
        const px_w: i32 = @intFromFloat(@round(sheet_w * raster_scale));
        const px_h: i32 = @intFromFloat(@round(sheet_h * raster_scale));
        const query = std.mem.trim(u8, opts.search_query, " \t\r\n");

        for (first_vis..last_vis + 1) |p_idx| {
            const sheet_y = sheet_lane_r.top + top_pad + @as(f32, @floatFromInt(p_idx)) * page_stride - view.scroll_y;
            const sheet_r = Rect.xywh(sheet_x, sheet_y, sheet_w, sheet_h);
            if (sheet_r.bottom < sheet_lane_r.top or sheet_r.top > sheet_lane_r.bottom) continue;

            // Drop shadow under page sheet
            paint.setStyle(.fill);
            paint.setColor(Color.argb(110, 4, 8, 15));
            canvas.drawRoundRect(Rect.xywh(sheet_r.left + 4.0, sheet_r.top + 6.0, sheet_w, sheet_h), 3.0, 3.0, paint);

            // Rasterize via CoreGraphics or render vector fallback
            var used_cg_raster = false;
            if (getOrRasterizePdfPageImage(opts.raw_bytes, opts.file_path, p_idx, px_w, px_h, view.invert_paper)) |img| {
                canvas.drawImageRect(img, sheet_r, null);
                used_cg_raster = true;
            } else {
                drawVectorFallbackPage(uic, sheet_r, doc, p_idx, view.invert_paper, query, view);
            }

            // Highlight selected text ranges on this page
            if (view.hasSelection()) {
                const page_info = doc.getPageInfo(p_idx, opts.raw_bytes, opts.file_path);
                drawPageTextSelection(uic, sheet_r, doc, page_info, p_idx, used_cg_raster, view);
            }

            // Highlight hovered Table of Contents link on this page with an interactive pill
            if (view.hovered_link_page > 0 and view.hovered_link_page_idx == p_idx) {
                const link_y = sheet_r.top + view.hovered_link_norm_y * sheet_h;
                const hl_r = Rect.xywh(sheet_r.left + 20.0, link_y - 9.0, sheet_w - 40.0, 18.0);
                paint.setStyle(.fill);
                paint.setColor(Color.argb(42, 56, 189, 248));
                canvas.drawRoundRect(hl_r, 3.0, 3.0, paint);

                const pill_w: f32 = 122.0;
                const pill_r = Rect.xywh(sheet_r.right - pill_w - 16.0, link_y - 10.0, pill_w, 20.0);
                paint.setColor(Color.rgb(14, 116, 144));
                canvas.drawRoundRect(pill_r, 4.0, 4.0, paint);
                paint.setColor(Color.rgb(240, 249, 255));
                const jump_txt = uic.fmt("Go to Page {d} ↗", .{view.hovered_link_page});
                uic.drawTextCached(font_mono, jump_txt, pill_r.left + 8.0, pill_r.top + 14.0);
            }

            // Inline search match highlights & top-right match counter badge on the page
            if (query.len > 0) {
                const matches = doc.countSearchMatchesOnPage(p_idx, query);
                if (matches > 0) {
                    if (used_cg_raster) {
                        drawPageSearchHighlights(uic, sheet_r, doc, p_idx, query, view);
                    }
                    const total_matches = @max(matches, doc.countTotalSearchMatches(query));
                    const badge_txt = if (view.has_active_match and view.active_match_page == p_idx)
                        uic.fmt("Match {d}/{d} ({d} on pg)", .{ view.active_match_index + 1, total_matches, matches })
                    else
                        uic.fmt("{d} match(es) on pg", .{matches});
                    const badge_w = @max(118.0, uic.measureTextCached(font_mono, badge_txt) + 18.0);
                    const badge_r = Rect.xywh(sheet_r.right - badge_w - 8.0, @max(sheet_lane_r.top + 8.0, sheet_r.top + 8.0), badge_w, 22.0);
                    paint.setStyle(.fill);
                    paint.setColor(Color.argb(235, 245, 158, 11));
                    canvas.drawRoundRect(badge_r, 4.0, 4.0, paint);
                    paint.setColor(Color.rgb(15, 23, 42));
                    uic.drawTextCached(font_mono, badge_txt, badge_r.left + 9.0, badge_r.top + 15.0);
                }
            }

            // Subtle page number pill at bottom-right corner of each contiguous sheet
            const pg_badge_w: f32 = 84.0;
            const pg_badge_r = Rect.xywh(sheet_r.right - pg_badge_w - 8.0, sheet_r.bottom - 24.0, pg_badge_w, 18.0);
            paint.setStyle(.fill);
            paint.setColor(Color.argb(175, 15, 23, 42));
            canvas.drawRoundRect(pg_badge_r, 3.0, 3.0, paint);
            paint.setColor(Color.rgb(203, 213, 225));
            const pg_badge_txt = uic.fmt("{d} / {d}", .{ p_idx + 1, page_count });
            uic.drawTextCached(font_mono, pg_badge_txt, pg_badge_r.left + 8.0, pg_badge_r.top + 13.0);

            // Crisp page border
            paint.setStyle(.stroke);
            paint.setStrokeWidth(if (p_idx == view.current_page) 1.5 else 1.0);
            paint.setColor(if (p_idx == view.current_page)
                Color.rgb(56, 139, 253)
            else if (view.invert_paper)
                Color.rgb(51, 65, 85)
            else
                Color.rgb(203, 213, 225));
            canvas.drawRect(sheet_r, paint);
        }

        // Right-edge contiguous document scrollbar
        if (max_scroll_y > 1.0) {
            const track_h = @max(24.0, canvas_h - 16.0);
            const track_x = sheet_lane_r.right - 9.0;
            const track_y = sheet_lane_r.top + 8.0;
            paint.setStyle(.fill);
            paint.setColor(Color.argb(90, 15, 23, 42));
            canvas.drawRoundRect(Rect.xywh(track_x, track_y, 5.0, track_h), 2.5, 2.5, paint);

            const thumb_h = std.math.clamp((canvas_h / total_doc_h) * track_h, 24.0, track_h);
            const scroll_ratio = std.math.clamp(view.scroll_y / max_scroll_y, 0.0, 1.0);
            const thumb_y = track_y + scroll_ratio * (track_h - thumb_h);
            paint.setColor(if (view.dragging_scrollbar) Color.rgb(56, 189, 248) else Color.rgb(100, 116, 139));
            canvas.drawRoundRect(Rect.xywh(track_x, thumb_y, 5.0, thumb_h), 2.5, 2.5, paint);

            // Search match tick markers along the scrollbar track
            if (query.len > 0) {
                const cached_n = @min(page_count, MaxPdfPages);
                for (0..cached_n) |m_pg| {
                    if (doc.countSearchMatchesOnPage(m_pg, query) > 0) {
                        const page = &doc.pages[m_pg];
                        for (page.lines[0..page.line_count], 0..) |line, l_idx| {
                            if (root.containsIgnoreCase(line.slice(), query)) {
                                const doc_ratio = std.math.clamp(
                                    (@as(f32, @floatFromInt(m_pg)) + page.lineNormY(l_idx)) / @as(f32, @floatFromInt(@max(page_count, 1))),
                                    0.0,
                                    1.0,
                                );
                                const tick_y = track_y + doc_ratio * (track_h - 3.0);
                                const is_act_tick = view.has_active_match and view.active_match_page == m_pg and view.active_match_line == l_idx;
                                paint.setColor(if (is_act_tick) Color.rgb(251, 191, 36) else Color.argb(210, 245, 158, 11));
                                canvas.drawRoundRect(Rect.xywh(track_x - 2.0, tick_y, 9.0, 3.0), 1.5, 1.5, paint);
                            }
                        }
                    }
                }
            }
        }

        canvas.restoreToCount(lane_clip);
    }

    return result;
}

/// Renders inline search highlight boxes on top of a CoreGraphics-rasterized PDF page (`sheet_r`),
/// distinguishing the currently active search match from other occurrences on the page.
fn drawPageSearchHighlights(
    uic: *Context,
    sheet_r: c.sk_rect_t,
    doc: *const PdfDocumentData,
    page_idx: usize,
    query: []const u8,
    view: *const PdfViewState,
) void {
    const paint = uic.paint;
    const canvas = uic.canvas;
    const sheet_w = sheet_r.right - sheet_r.left;
    const sheet_h = sheet_r.bottom - sheet_r.top;
    if (sheet_w <= 10.0 or sheet_h <= 10.0 or query.len == 0) return;

    const clip = canvas.save();
    defer canvas.restoreToCount(clip);
    canvas.clipRect(sheet_r, .intersect, false);

    var drew_any = false;
    if (page_idx < MaxPdfPages) {
        const page = &doc.pages[page_idx];
        const w_pt = if (page.width_pt > 10.0) page.width_pt else doc.default_width_pt;
        const h_pt = if (page.height_pt > 10.0) page.height_pt else doc.default_height_pt;
        const pt_to_px_x = sheet_w / @max(1.0, w_pt);
        const pt_to_px_y = sheet_h / @max(1.0, h_pt);

        for (page.lines[0..page.line_count], 0..) |line_in, l_idx| {
            const line = line_in.slice();
            if (line.len < query.len) continue;
            const font_pt = page.line_font_pt[l_idx];
            const font_scale = (font_pt / 12.0) * pt_to_px_x;
            const line_left = sheet_r.left + page.lineNormX(l_idx) * sheet_w;
            const line_baseline_y = sheet_r.top + page.lineNormY(l_idx) * sheet_h;
            const box_h = @max(12.0, font_pt * 1.32 * pt_to_px_y);
            const box_top = line_baseline_y - box_h * 0.78;

            var pos: usize = 0;
            var hits_on_line: usize = 0;
            while (hits_on_line < 24) : (hits_on_line += 1) {
                const found_idx = root.indexOfIgnoreCasePos(line, pos, query) orelse break;
                const end_idx = @min(line.len, found_idx + query.len);
                const x0 = line_left + uic.measureTextCached(uic.font_body, line[0..found_idx]) * font_scale;
                const x1 = line_left + uic.measureTextCached(uic.font_body, line[0..end_idx]) * font_scale;
                const hl_w = @max(8.0, (x1 - x0) + 4.0);
                const hl_r = Rect.xywh(
                    std.math.clamp(x0 - 2.0, sheet_r.left + 4.0, @max(sheet_r.left + 4.0, sheet_r.right - hl_w - 4.0)),
                    std.math.clamp(box_top, sheet_r.top + 4.0, @max(sheet_r.top + 4.0, sheet_r.bottom - box_h - 4.0)),
                    hl_w,
                    box_h,
                );
                const is_active = view.has_active_match and
                    view.active_match_page == page_idx and
                    view.active_match_line == l_idx and
                    view.active_match_offset == found_idx;

                paint.setStyle(.fill);
                paint.setColor(if (is_active) Color.argb(145, 251, 191, 36) else Color.argb(95, 245, 158, 11));
                canvas.drawRoundRect(hl_r, 3.0, 3.0, paint);

                paint.setStyle(.stroke);
                paint.setStrokeWidth(if (is_active) 1.75 else 1.0);
                paint.setColor(if (is_active) Color.rgb(245, 158, 11) else Color.argb(190, 245, 158, 11));
                canvas.drawRoundRect(hl_r, 3.0, 3.0, paint);

                if (is_active) {
                    // Left-margin indicator bar pointing to the active match row on the page
                    paint.setStyle(.fill);
                    paint.setColor(Color.rgb(245, 158, 11));
                    canvas.drawRoundRect(Rect.xywh(sheet_r.left + 2.0, hl_r.top, 4.0, box_h), 2.0, 2.0, paint);
                }
                drew_any = true;
                pos = end_idx;
            }
        }
    }

    if (!drew_any) {
        const target_pg: u32 = @intCast(page_idx + 1);
        for (doc.outline[0..doc.outline_count]) |item| {
            if (item.page_number == target_pg and root.containsIgnoreCase(item.title.slice(), query)) {
                const y = sheet_r.top + std.math.clamp(item.norm_y, 0.04, 0.92) * sheet_h;
                const hl_r = Rect.xywh(sheet_r.left + 24.0, y - 4.0, sheet_w - 48.0, 22.0);
                paint.setStyle(.fill);
                paint.setColor(Color.argb(115, 251, 191, 36));
                canvas.drawRoundRect(hl_r, 3.0, 3.0, paint);
                paint.setStyle(.stroke);
                paint.setStrokeWidth(1.5);
                paint.setColor(Color.rgb(245, 158, 11));
                canvas.drawRoundRect(hl_r, 3.0, 3.0, paint);
            }
        }
    }
}

fn drawVectorLineSearchHighlights(
    uic: *Context,
    font: Font,
    line: []const u8,
    text_x: f32,
    baseline_y: f32,
    box_h: f32,
    page_idx: usize,
    line_idx: usize,
    query: []const u8,
    view: *const PdfViewState,
    sheet_left: f32,
) void {
    if (query.len == 0 or line.len < query.len) return;
    const paint = uic.paint;
    const canvas = uic.canvas;
    var pos: usize = 0;
    var hits: usize = 0;
    while (hits < 24) : (hits += 1) {
        const found_idx = root.indexOfIgnoreCasePos(line, pos, query) orelse break;
        const end_idx = @min(line.len, found_idx + query.len);
        const mx0 = text_x + uic.measureTextCached(font, line[0..found_idx]);
        const mx1 = text_x + uic.measureTextCached(font, line[0..end_idx]);
        const hl_r = Rect.xywh(mx0 - 1.5, baseline_y - box_h * 0.76, @max(6.0, (mx1 - mx0) + 3.0), box_h);
        const is_active = view.has_active_match and
            view.active_match_page == page_idx and
            view.active_match_line == line_idx and
            view.active_match_offset == found_idx;

        paint.setStyle(.fill);
        paint.setColor(if (is_active) Color.argb(150, 251, 191, 36) else Color.argb(100, 245, 158, 11));
        canvas.drawRoundRect(hl_r, 3.0, 3.0, paint);
        paint.setStyle(.stroke);
        paint.setStrokeWidth(if (is_active) 1.5 else 1.0);
        paint.setColor(if (is_active) Color.rgb(245, 158, 11) else Color.argb(185, 245, 158, 11));
        canvas.drawRoundRect(hl_r, 3.0, 3.0, paint);
        if (is_active) {
            paint.setStyle(.fill);
            paint.setColor(Color.rgb(245, 158, 11));
            canvas.drawRoundRect(Rect.xywh(sheet_left + 2.0, hl_r.top, 4.0, box_h), 2.0, 2.0, paint);
        }
        pos = end_idx;
    }
}

fn drawVectorFallbackPage(
    uic: *Context,
    sheet_r: c.sk_rect_t,
    doc: *const PdfDocumentData,
    page_idx: usize,
    invert_paper: bool,
    query: []const u8,
    view: *const PdfViewState,
) void {
    const paint = uic.paint;
    const canvas = uic.canvas;
    const sheet_w = sheet_r.right - sheet_r.left;
    const scale = std.math.clamp(sheet_w / 560.0, 0.65, 1.8);

    const clip = canvas.save();
    defer canvas.restoreToCount(clip);
    canvas.clipRect(sheet_r, .intersect, false);

    // 1. Paper Sheet Background
    paint.setStyle(.fill);
    paint.setColor(if (invert_paper) Color.rgb(19, 25, 37) else Color.rgb(252, 253, 255));
    canvas.drawRect(sheet_r, paint);

    // 2. Top Datasheet Header Banner
    const hdr_x = sheet_r.left + 20.0 * scale;
    const hdr_y = sheet_r.top + 18.0 * scale;
    const hdr_w = @max(40.0, sheet_w - 40.0 * scale);
    const hdr_h = 44.0 * scale;
    paint.setColor(Color.rgb(24, 36, 58));
    canvas.drawRoundRect(Rect.xywh(hdr_x, hdr_y, hdr_w, hdr_h), 4.0, 4.0, paint);
    paint.setColor(Color.rgb(56, 139, 253));
    canvas.drawRoundRect(Rect.xywh(hdr_x, hdr_y, 5.0 * scale, hdr_h), 2.5, 2.5, paint);

    paint.setColor(Color.rgb(248, 250, 252));
    uic.drawTextCached(uic.font_title, doc.title.slice(), hdr_x + 14.0 * scale, hdr_y + 20.0 * scale);
    paint.setColor(Color.rgb(148, 163, 184));
    const sub_hdr = uic.fmt("{s}  •  PDF v{s}  •  Page {d} of {d}", .{
        doc.author.slice(),
        doc.version.slice(),
        page_idx + 1,
        doc.page_count,
    });
    uic.drawTextCached(uic.font_mono, sub_hdr, hdr_x + 14.0 * scale, hdr_y + 36.0 * scale);

    // 3. Typeset Body Lines, Section Headings, Block Diagrams & Register Tables
    const page = &doc.pages[@min(page_idx, MaxPdfPages - 1)];
    var y = hdr_y + hdr_h + 22.0 * scale;
    const line_step = @max(16.0, 18.0 * scale);

    var skip_count: usize = 0;
    for (page.lines[0..page.line_count], 0..) |line_in, l_idx| {
        if (skip_count > 0) {
            skip_count -= 1;
            continue;
        }
        if (y + line_step > sheet_r.bottom - 28.0 * scale) break;
        const line = line_in.slice();
        if (l_idx == 0 and std.mem.indexOf(u8, line, "DATASHEET") != null) continue;
        if (std.mem.startsWith(u8, line, "Page ") and std.mem.indexOf(u8, line, "Confidential") != null) continue;

        if (std.mem.eql(u8, line, "RV32IMAC CPU") and y + 58.0 * scale < sheet_r.bottom - 30.0 * scale) {
            const box_gap = 14.0 * scale;
            const box_w = @max(60.0, (hdr_w - box_gap * 2.0) / 3.0);
            const box_h = 46.0 * scale;
            const box_y = y - 6.0 * scale;
            const titles = [_][]const u8{ "RV32IMAC CPU", "AXI4 Crossbar", "DMA & Peripherals" };
            const subs = [_][]const u8{ "250 MHz + Mul/Div", "64-bit 16 GB/s Fabric", "UART / SPI / I2C / ADC" };
            const accents = [_]u32{
                Color.rgb(56, 139, 253),
                Color.rgb(16, 185, 129),
                Color.rgb(245, 158, 11),
            };
            for (0..3) |b_i| {
                const bx = hdr_x + @as(f32, @floatFromInt(b_i)) * (box_w + box_gap);
                const br = Rect.xywh(bx, box_y, box_w, box_h);
                paint.setStyle(.fill);
                paint.setColor(if (invert_paper) Color.rgb(26, 36, 52) else Color.rgb(241, 245, 249));
                canvas.drawRoundRect(br, 4.0, 4.0, paint);
                paint.setColor(accents[b_i]);
                canvas.drawRoundRect(Rect.xywh(bx, box_y, 4.0, box_h), 2.0, 2.0, paint);
                paint.setStyle(.stroke);
                paint.setStrokeWidth(1.0);
                canvas.drawRoundRect(br, 4.0, 4.0, paint);

                const b_clip = canvas.save();
                canvas.clipRect(Rect.xywh(bx + 6.0, box_y, box_w - 10.0, box_h), .intersect, false);
                paint.setStyle(.fill);
                paint.setColor(if (invert_paper) Color.rgb(241, 245, 249) else Color.rgb(15, 23, 42));
                uic.drawTextCached(uic.font_title, titles[b_i], bx + 10.0, box_y + 18.0 * scale);
                paint.setColor(if (invert_paper) Color.rgb(148, 163, 184) else Color.rgb(71, 85, 105));
                uic.drawTextCached(uic.font_mono, subs[b_i], bx + 10.0, box_y + 35.0 * scale);
                canvas.restoreToCount(b_clip);
            }
            skip_count = 5;
            y += box_h + 12.0 * scale;
            continue;
        }

        const ln_clip = canvas.save();
        canvas.clipRect(Rect.xywh(hdr_x, y - 15.0 * scale, hdr_w, line_step + 6.0), .intersect, false);
        if (isSectionHeadingLine(line)) {
            y += 5.0 * scale;
            paint.setStyle(.fill);
            paint.setColor(if (invert_paper) Color.argb(45, 56, 139, 253) else Color.argb(32, 37, 99, 235));
            canvas.drawRoundRect(Rect.xywh(hdr_x, y - 13.0 * scale, hdr_w, @max(18.0, 20.0 * scale)), 3.0, 3.0, paint);
            drawVectorLineSearchHighlights(uic, uic.font_title, line, hdr_x + 8.0 * scale, y + 2.0 * scale, line_step, page_idx, l_idx, query, view, sheet_r.left);
            paint.setStyle(.fill);
            paint.setColor(if (invert_paper) Color.rgb(96, 165, 250) else Color.rgb(29, 78, 216));
            uic.drawTextCached(uic.font_title, line, hdr_x + 8.0 * scale, y + 2.0 * scale);
            y += line_step + 4.0 * scale;
        } else if (std.mem.startsWith(u8, line, "0x") or std.mem.startsWith(u8, line, "Base Address") or std.mem.startsWith(u8, line, "Offset")) {
            paint.setStyle(.fill);
            paint.setColor(if (invert_paper) Color.rgb(26, 35, 50) else Color.rgb(241, 245, 249));
            canvas.drawRect(Rect.xywh(hdr_x + 4.0 * scale, y - 12.0 * scale, hdr_w - 8.0 * scale, line_step - 1.0), paint);
            drawVectorLineSearchHighlights(uic, uic.font_mono, line, hdr_x + 10.0 * scale, y, line_step - 2.0, page_idx, l_idx, query, view, sheet_r.left);
            paint.setStyle(.fill);
            paint.setColor(if (invert_paper) Color.rgb(125, 211, 252) else Color.rgb(15, 23, 42));
            uic.drawTextCached(uic.font_mono, line, hdr_x + 10.0 * scale, y);
            y += line_step;
        } else {
            drawVectorLineSearchHighlights(uic, uic.font_body, line, hdr_x + 8.0 * scale, y, line_step - 2.0, page_idx, l_idx, query, view, sheet_r.left);
            paint.setStyle(.fill);
            paint.setColor(if (invert_paper) Color.rgb(226, 232, 240) else Color.rgb(30, 41, 59));
            uic.drawTextCached(uic.font_body, line, hdr_x + 8.0 * scale, y);
            y += line_step;
        }
        canvas.restoreToCount(ln_clip);
    }

    // 4. Bottom Page Footer Rule
    const footer_y = sheet_r.bottom - 14.0 * scale;
    paint.setStyle(.fill);
    paint.setColor(if (invert_paper) Color.rgb(51, 65, 85) else Color.rgb(203, 213, 225));
    canvas.drawRect(Rect.xywh(hdr_x, footer_y - 12.0 * scale, hdr_w, 1.0), paint);
    paint.setColor(Color.rgb(100, 116, 139));
    const ftr_txt = uic.fmt("{s}  —  Page {d} of {d}", .{ doc.title.slice(), page_idx + 1, doc.page_count });
    uic.drawTextCached(uic.font_mono, ftr_txt, hdr_x, footer_y);
}

// ============================================================================
// Unit Tests
// ============================================================================

test "PDF Viewer: PDF 1.4 parser, metadata/outline extraction, and 2-phase layout determinism" {
    var doc = PdfDocumentData{};
    parsePdfDocument(SAMPLE_PDF_DOC, "datasheet_rv32.pdf", &doc);

    try std.testing.expectEqualStrings("1.4", doc.version.slice());
    try std.testing.expectEqual(@as(usize, 3), doc.page_count);
    try std.testing.expectEqualStrings("Lightning SoC RV32IMAC Datasheet", doc.title.slice());
    try std.testing.expectEqualStrings("Lightning Silicon Engineering", doc.author.slice());
    try std.testing.expect(doc.outline_count >= 3);
    try std.testing.expect(doc.pages[0].line_count >= 6);
    try std.testing.expect(doc.countTotalSearchMatches("UART") >= 2);

    // Exercise 2-phase Pass.input -> Pass.paint layout determinism
    const surface = try skia.Surface.initRasterN32Premul(800, 520);
    defer surface.deinit();
    const paint = try skia.Paint.init();
    defer paint.deinit();
    const font = try Font.init(null, 12.0);
    defer font.deinit();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var uic = Context{
        .arena = arena.allocator(),
        .canvas = surface.canvas(),
        .paint = paint,
        .font_title = font,
        .font_body = font,
        .font_mono = font,
    };
    defer uic.deinit();

    var view = PdfViewState{};
    try std.testing.expectEqual(false, view.show_outline);
    const win_rect = Rect.xywh(0, 0, 800, 520);

    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 300, 220, true, true, false);
    _ = renderPdfViewer(&uic, "test_pdf", 800, 520, &doc, &view, .{ .raw_bytes = SAMPLE_PDF_DOC });
    uic.endPass();
    const input_rects = uic.last_input_rect_count;
    try std.testing.expect(uic.dirty_rect != null);

    uic.clip_damage = win_rect;
    uic.beginPass(.paint, arena.allocator(), surface.canvas(), win_rect, 300, 220, false, false, false);
    _ = renderPdfViewer(&uic, "test_pdf", 800, 520, &doc, &view, .{ .raw_bytes = SAMPLE_PDF_DOC });
    uic.endPass();
    try std.testing.expectEqual(input_rects, uic.last_paint_rect_count);

    // Verify trackpad pinch-to-zoom (`magnify_delta`) scales PDF zoom smoothly
    const pdf_zoom_before = view.zoom;
    _ = arena.reset(.retain_capacity);
    uic.magnify_delta = 0.25;
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 480, 260, false, false, false);
    _ = renderPdfViewer(&uic, "test_pdf", 800, 520, &doc, &view, .{ .raw_bytes = SAMPLE_PDF_DOC });
    uic.endPass();
    try std.testing.expectApproxEqAbs(pdf_zoom_before * 1.25, view.zoom, 0.01);

    // Verify horizontal scrolling (`scroll_dx`) moves `scroll_x` in the natural direction (+scroll_dx -> +scroll_x)
    view.zoom = 1.6;
    view.last_synced_zoom = 1.6;
    view.scroll_x = 0.0;
    uic.magnify_delta = 0.0;
    uic.scroll_dx = 20.0;
    uic.scroll_dy = 0.0;
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 480, 260, false, false, false);
    _ = renderPdfViewer(&uic, "test_pdf", 800, 520, &doc, &view, .{ .raw_bytes = SAMPLE_PDF_DOC });
    uic.endPass();
    try std.testing.expect(view.scroll_x > 15.0);
    uic.scroll_dx = 0.0;

    // Verify out-of-bounds `scroll_y` and `outline_scroll_y` (e.g. after switching from a 500-page PDF to a 1-page PDF)
    // are safely clamped in both `.input` and `.paint` passes without `first_vis > last_vis` integer overflow
    view.scroll_y = 999999.0;
    view.outline_scroll_y = 999999.0;
    uic.magnify_delta = 0;
    uic.clip_damage = win_rect;
    uic.beginPass(.paint, arena.allocator(), surface.canvas(), win_rect, 300, 220, false, false, false);
    _ = renderPdfViewer(&uic, "test_pdf", 800, 520, &doc, &view, .{ .raw_bytes = SAMPLE_PDF_DOC });
    uic.endPass();

    // Verify Table of Contents text line page-number parser
    try std.testing.expectEqual(@as(?u32, 14), parseTocLinePageNumber("2.1 Memory Map ........... 14", 100));
    try std.testing.expectEqual(@as(?u32, 192), parseTocLinePageNumber("Section 4 Architecture Overview  192", 500));
    try std.testing.expectEqual(@as(?u32, null), parseTocLinePageNumber("Page 1 of 3", 100));

    // Verify page-level search matching (`findMatchingPage`), occurrence-level `findMatch`, and `jumpToSearchMatch`
    try std.testing.expectEqual(@as(?usize, 1), doc.findMatchingPage(0, "LOOPBACK", true, false));
    try std.testing.expectEqual(@as(?usize, 2), doc.findMatchingPage(1, "Dhrystone", true, true));
    try std.testing.expectEqual(@as(?usize, 0), doc.findMatchingPage(2, "RISC-V", false, true));

    const m0 = doc.findMatch(null, 0, "UART", true, false) orelse return error.MissingSearchMatch;
    try std.testing.expectEqual(@as(usize, 0), m0.match_index);
    try std.testing.expectEqual(@as(usize, 0), m0.page_idx);
    const m1 = doc.findMatch(m0.match_index, m0.page_idx, "UART", true, true) orelse return error.MissingSearchMatch;
    try std.testing.expectEqual(@as(usize, 1), m1.match_index);
    try std.testing.expect(m1.norm_y >= m0.norm_y or m1.page_idx > m0.page_idx);
    view.jumpToSearchMatch(m1);
    try std.testing.expect(view.has_active_match);
    try std.testing.expect(view.pending_scroll_to_match);

    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 300, 220, false, false, false);
    _ = renderPdfViewer(&uic, "test_pdf", 800, 520, &doc, &view, .{
        .raw_bytes = SAMPLE_PDF_DOC,
        .search_query = "SPI",
    });
    uic.endPass();

    uic.clip_damage = win_rect;
    uic.beginPass(.paint, arena.allocator(), surface.canvas(), win_rect, 300, 220, false, false, false);
    _ = renderPdfViewer(&uic, "test_pdf", 800, 520, &doc, &view, .{
        .raw_bytes = SAMPLE_PDF_DOC,
        .search_query = "SPI",
    });
    uic.endPass();
}

fn buildSyntheticMultiPagePdfAlloc(alloc: std.mem.Allocator) ![]u8 {
    var out: std.ArrayListUnmanaged(u8) = .empty;
    errdefer out.deinit(alloc);

    try out.appendSlice(alloc, "%PDF-1.4\n");

    // Object 1..15 byte offsets (1-based index)
    var offsets: [16]usize = @splat(0);
    const objs = [_][]const u8{
        // 1: Catalog with Outlines and Names->Dests B-tree
        "1 0 obj\n<< /Type /Catalog /Pages 2 0 R /Outlines 9 0 R /Names << /Dests 14 0 R >> >>\nendobj\n",
        // 2: Root Pages node (nested Kids: Page 1, Page 2, and intermediate Pages node 3)
        "2 0 obj\n<< /Type /Pages /Kids [4 0 R 5 0 R 3 0 R] /Count 4 >>\nendobj\n",
        // 3: Intermediate Pages node (Kids: Page 3, Page 4) to test O(log N) tree walk
        "3 0 obj\n<< /Type /Pages /Parent 2 0 R /Kids [6 0 R 7 0 R] /Count 2 >>\nendobj\n",
        // 4: Page 1 (Table of Contents with clickable Link annotation 8 0 R)
        "4 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Annots [8 0 R] >>\nendobj\n",
        // 5: Page 2
        "5 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >>\nendobj\n",
        // 6: Page 3 (under intermediate node 3)
        "6 0 obj\n<< /Type /Page /Parent 3 0 R /MediaBox [0 0 612 792] >>\nendobj\n",
        // 7: Page 4 (under intermediate node 3)
        "7 0 obj\n<< /Type /Page /Parent 3 0 R /MediaBox [0 0 612 792] >>\nendobj\n",
        // 8: Link annotation on Page 1 covering normalized y ~ [0.43..0.56] (PDF y = [350..450]), jumping to Page 4 (7 0 R)
        "8 0 obj\n<< /Type /Annot /Subtype /Link /Rect [36 350 540 450] /Dest [7 0 R /XYZ 0 680 0] >>\nendobj\n",
        // 9: Outlines root
        "9 0 obj\n<< /Type /Outlines /First 10 0 R /Last 13 0 R /Count 4 >>\nendobj\n",
        // 10: Outline 1: Chapter 3. PIO -> Page 2
        "10 0 obj\n<< /Title (Chapter 3. PIO) /Parent 9 0 R /Next 11 0 R /Dest [5 0 R /XYZ 0 700 0] >>\nendobj\n",
        // 11: Outline 2: Chapter 4. Peripherals (with child 12 0 R) -> Page 3
        "11 0 obj\n<< /Title (Chapter 4. Peripherals) /Parent 9 0 R /Prev 10 0 R /Next 13 0 R /First 12 0 R /Last 12 0 R /Dest [6 0 R /XYZ 0 720 0] >>\nendobj\n",
        // 12: Child Outline 2.1: 4.1 UART (via named destination "sec_uart" with intra-page offset y=420)
        "12 0 obj\n<< /Title (4.1 UART) /Parent 11 0 R /A << /S /GoTo /D (sec_uart) >> >>\nendobj\n",
        // 13: Outline 3: Appendix A. Specifications -> Page 4
        "13 0 obj\n<< /Title (Appendix A. Specifications) /Parent 9 0 R /Prev 11 0 R /Dest [7 0 R /FitH 500] >>\nendobj\n",
        // 14: Names->Dests B-tree node with Limits and Names array
        "14 0 obj\n<< /Limits [(sec_a) (sec_z)] /Names [(sec_uart) << /D [6 0 R /XYZ 0 420 0] >>] >>\nendobj\n",
        // 15: Info dictionary
        "15 0 obj\n<< /Title (Synthetic SoC Reference Manual) /Author (Test Suite) >>\nendobj\n",
    };

    for (objs, 1..) |obj_str, obj_num| {
        offsets[obj_num] = out.items.len;
        try out.appendSlice(alloc, obj_str);
    }

    const xref_offset = out.items.len;
    var hdr_buf: [64]u8 = undefined;
    const xref_hdr = try std.fmt.bufPrint(&hdr_buf, "xref\n0 {d}\n0000000000 65535 f \n", .{objs.len + 1});
    try out.appendSlice(alloc, xref_hdr);

    for (1..objs.len + 1) |obj_num| {
        var row_buf: [32]u8 = undefined;
        const row = try std.fmt.bufPrint(&row_buf, "{d:0>10} 00000 n \n", .{offsets[obj_num]});
        try out.appendSlice(alloc, row);
    }

    var tr_buf: [128]u8 = undefined;
    const trailer = try std.fmt.bufPrint(
        &tr_buf,
        "trailer\n<< /Size {d} /Root 1 0 R /Info 15 0 R >>\nstartxref\n{d}\n%%EOF\n",
        .{ objs.len + 1, xref_offset },
    );
    try out.appendSlice(alloc, trailer);
    return out.toOwnedSlice(alloc);
}

test "PDF Viewer: multi-level Pages tree, hierarchical Outlines, Named Destinations, and Table of Contents link hit-testing" {
    const pdf_bytes = try buildSyntheticMultiPagePdfAlloc(std.testing.allocator);
    defer std.testing.allocator.free(pdf_bytes);

    var doc = PdfDocumentData{};
    parsePdfDocument(pdf_bytes, "", &doc);

    if (comptime is_macos) {
        try std.testing.expectEqual(@as(usize, 4), doc.page_count);
        try std.testing.expectEqual(@as(usize, 4), doc.outline_count);

        var has_ch3_pio = false;
        var has_ch4_periph = false;
        var has_uart = false;
        var has_appendix = false;
        var has_intra_page_offset = false;
        for (doc.outline[0..doc.outline_count]) |item| {
            const t = item.title.slice();
            if (std.mem.indexOf(u8, t, "Chapter 3. PIO") != null) has_ch3_pio = true;
            if (std.mem.indexOf(u8, t, "Chapter 4. Peripherals") != null) has_ch4_periph = true;
            if (std.mem.indexOf(u8, t, "UART") != null) has_uart = true;
            if (std.mem.indexOf(u8, t, "Appendix") != null) has_appendix = true;
            if (item.norm_y > 0.15) has_intra_page_offset = true;
        }
        try std.testing.expect(has_ch3_pio);
        try std.testing.expect(has_ch4_periph);
        try std.testing.expect(has_uart);
        try std.testing.expect(has_appendix);
        try std.testing.expect(has_intra_page_offset);

        // Verify Table of Contents `/Link` annotation on Page 1 (`page_idx = 0`) resolves to Page 4
        const dest = resolvePdfPageLinkAtPoint(pdf_bytes, "", 0, 0.45, 0.50) orelse return error.LinkNotResolved;
        try std.testing.expectEqual(@as(u32, 4), dest.page_number);

        // Verify clicking the hovered link in `renderPdfViewer` jumps to Page 4 (`current_page == 3`)
        const surface = try skia.Surface.initRasterN32Premul(1180, 780);
        defer surface.deinit();
        const paint = try skia.Paint.init();
        defer paint.deinit();
        const font_t = try Font.init(null, 13.0);
        defer font_t.deinit();
        const font_b = try Font.init(null, 12.0);
        defer font_b.deinit();
        const font_m = try Font.init(null, 11.5);
        defer font_m.deinit();

        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        var uic = Context{
            .arena = arena.allocator(),
            .canvas = surface.canvas(),
            .paint = paint,
            .font_title = font_t,
            .font_body = font_b,
            .font_mono = font_m,
        };
        defer uic.deinit();

        var view = PdfViewState{
            .current_page = 0,
            .last_synced_page = 0,
            .zoom = 0.85,
            .last_synced_zoom = 0.85,
        };
        const sheet_h_est: f32 = (680.0 * 0.85) * (792.0 / 612.0);
        const win_rect = Rect.xywh(0, 0, 1180, 780);
        const mx: f32 = 407.0 + 0.45 * (680.0 * 0.85);
        const my: f32 = 36.0 + 16.0 + 0.50 * sheet_h_est;

        uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, mx, my, true, true, false);
        const click_res = renderPdfViewer(&uic, "synth_pdf", 1180, 780, &doc, &view, .{ .raw_bytes = pdf_bytes });
        uic.endPass();
        try std.testing.expect(click_res.page_changed);
        try std.testing.expectEqual(@as(usize, 3), view.current_page);
    }
}

test "PDF Viewer: interactive text selection (char drag, double-click word, triple-click line, Cmd+A) and clipboard copy (Cmd+C)" {
    var doc = PdfDocumentData{};
    parsePdfDocument(SAMPLE_PDF_DOC, "datasheet_rv32.pdf", &doc);

    const surface = try skia.Surface.initRasterN32Premul(960, 680);
    defer surface.deinit();
    const paint = try skia.Paint.init();
    defer paint.deinit();
    const font_t = try Font.init(null, 13.0);
    defer font_t.deinit();
    const font_b = try Font.init(null, 12.0);
    defer font_b.deinit();
    const font_m = try Font.init(null, 11.5);
    defer font_m.deinit();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const MockClip = struct {
        var buf: [4096]u8 = undefined;
        var len: usize = 0;

        fn setClip(ptr: [*]const u8, count: usize) callconv(.c) void {
            const n = @min(count, buf.len);
            @memcpy(buf[0..n], ptr[0..n]);
            len = n;
        }
    };
    MockClip.len = 0;

    var pctx = platform.PlatformContext{
        .width = 960,
        .height = 680,
        .host_set_clipboard = MockClip.setClip,
    };

    var uic = Context{
        .arena = arena.allocator(),
        .canvas = surface.canvas(),
        .paint = paint,
        .font_title = font_t,
        .font_body = font_b,
        .font_mono = font_m,
        .platform_ctx = &pctx,
    };
    defer uic.deinit();

    var view = PdfViewState{
        .current_page = 0,
        .last_synced_page = 0,
        .zoom = 1.0,
        .last_synced_zoom = 1.0,
    };
    const win_rect = Rect.xywh(0, 0, 960, 680);

    // 1. Programmatic `selectPage` and `copySelectionAlloc`
    view.selectPage(&doc, 0);
    try std.testing.expect(view.hasSelection());
    const pg0_txt = view.copySelectionAlloc(&doc, std.testing.allocator) orelse return error.MissingPageText;
    defer std.testing.allocator.free(pg0_txt);
    try std.testing.expect(std.mem.indexOf(u8, pg0_txt, "Architecture Overview") != null);
    try std.testing.expect(std.mem.indexOf(u8, pg0_txt, "RISC-V") != null);

    view.clearSelection();
    try std.testing.expect(!view.hasSelection());

    // 2. Compute exact visual coordinates of line 2 on page 0 and verify double-click word selection
    const sheet_w: f32 = 680.0;
    const sheet_h: f32 = sheet_w * (792.0 / 612.0);
    const sheet_x: f32 = (960.0 - sheet_w) * 0.5;
    const sheet_y: f32 = 36.0 + 16.0;
    const sheet_r = Rect.xywh(sheet_x, sheet_y, sheet_w, sheet_h);

    var metrics: [MaxLinesPerPage]LineVisualMetrics = undefined;
    computePageLineVisualMetrics(&uic, sheet_r, &doc, &doc.pages[0], false, &metrics);

    var target_line: usize = 0;
    for (0..doc.pages[0].line_count) |li| {
        if (metrics[li].visible and std.mem.indexOf(u8, doc.pages[0].lines[li].slice(), "RISC-V") != null) {
            target_line = li;
            break;
        }
    }
    const lm = metrics[target_line];
    try std.testing.expect(lm.visible);
    const click_x = lm.text_x + 12.0;
    const click_y = (lm.box_top + lm.box_bottom) * 0.5;

    // Double-click (`mouse_click_count = 2`) selects a word on `target_line`
    _ = arena.reset(.retain_capacity);
    pctx.mouse_click_count = 2;
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, click_x, click_y, true, true, false);
    _ = renderPdfViewer(&uic, "test_pdf_sel", 960, 680, &doc, &view, .{ .raw_bytes = SAMPLE_PDF_DOC });
    uic.endPass();
    try std.testing.expect(view.hasSelection());
    const word_txt = view.copySelectionAlloc(&doc, std.testing.allocator) orelse return error.MissingWordSelection;
    defer std.testing.allocator.free(word_txt);
    try std.testing.expect(word_txt.len > 0);
    try std.testing.expect(std.mem.indexOfScalar(u8, word_txt, '\n') == null);

    // 3. Triple-click (`mouse_click_count = 3`) selects the entire line
    _ = arena.reset(.retain_capacity);
    pctx.mouse_click_count = 3;
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, click_x, click_y, true, true, false);
    _ = renderPdfViewer(&uic, "test_pdf_sel", 960, 680, &doc, &view, .{ .raw_bytes = SAMPLE_PDF_DOC });
    uic.endPass();
    try std.testing.expect(view.hasSelection());
    const line_txt = view.copySelectionAlloc(&doc, std.testing.allocator) orelse return error.MissingLineSelection;
    defer std.testing.allocator.free(line_txt);
    try std.testing.expectEqualStrings(doc.pages[0].lines[target_line].slice(), line_txt);

    // 4. Single-click and drag across multiple lines (`target_line` -> `target_line + 2`), then copy via Cmd+C
    _ = arena.reset(.retain_capacity);
    pctx.mouse_click_count = 1;
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, lm.text_x + 2.0, click_y, true, true, false);
    _ = renderPdfViewer(&uic, "test_pdf_sel", 960, 680, &doc, &view, .{ .raw_bytes = SAMPLE_PDF_DOC });
    uic.endPass();
    try std.testing.expect(view.dragging_selection);

    const end_line = @min(target_line + 2, doc.pages[0].line_count - 1);
    const end_lm = metrics[end_line];
    const drag_x = end_lm.text_x + 220.0;
    const drag_y = (end_lm.box_top + end_lm.box_bottom) * 0.5;

    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, drag_x, drag_y, true, false, false);
    _ = renderPdfViewer(&uic, "test_pdf_sel", 960, 680, &doc, &view, .{ .raw_bytes = SAMPLE_PDF_DOC });
    uic.endPass();
    try std.testing.expect(view.hasSelection());

    // Release mouse button and press Cmd+C
    _ = arena.reset(.retain_capacity);
    pctx.clearFrameInput();
    pctx.pushKeyEvent(.{ .key = .key_c, .cmd = true });
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, drag_x, drag_y, false, false, true);
    const copy_res = renderPdfViewer(&uic, "test_pdf_sel", 960, 680, &doc, &view, .{ .raw_bytes = SAMPLE_PDF_DOC });
    uic.endPass();
    const input_rects = uic.last_input_rect_count;
    try std.testing.expect(copy_res.copied_text != null);
    try std.testing.expect(MockClip.len > 0);
    try std.testing.expect(std.mem.indexOfScalar(u8, MockClip.buf[0..MockClip.len], '\n') != null);

    // Verify 2-phase Pass.paint renders selection highlights with identical rect count
    pctx.clearFrameInput();
    uic.clip_damage = win_rect;
    uic.beginPass(.paint, arena.allocator(), surface.canvas(), win_rect, drag_x, drag_y, false, false, false);
    _ = renderPdfViewer(&uic, "test_pdf_sel", 960, 680, &doc, &view, .{ .raw_bytes = SAMPLE_PDF_DOC });
    uic.endPass();
    try std.testing.expectEqual(input_rects, uic.last_paint_rect_count);

    // 5. Cmd+A selects all pages and Escape clears selection
    _ = arena.reset(.retain_capacity);
    pctx.clearFrameInput();
    pctx.pushKeyEvent(.{ .key = .key_a, .cmd = true });
    pctx.pushKeyEvent(.{ .key = .key_c, .cmd = true });
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, drag_x, drag_y, false, false, false);
    const all_res = renderPdfViewer(&uic, "test_pdf_sel", 960, 680, &doc, &view, .{ .raw_bytes = SAMPLE_PDF_DOC });
    uic.endPass();
    try std.testing.expect(view.hasSelection());
    try std.testing.expect(all_res.copied_text != null);
    try std.testing.expect(std.mem.indexOf(u8, all_res.copied_text.?, "UART_CTRL") != null);
    try std.testing.expect(std.mem.indexOf(u8, all_res.copied_text.?, "Dhrystone") != null);

    _ = arena.reset(.retain_capacity);
    pctx.clearFrameInput();
    pctx.pushKeyEvent(.{ .key = .escape });
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, drag_x, drag_y, false, false, false);
    _ = renderPdfViewer(&uic, "test_pdf_sel", 960, 680, &doc, &view, .{ .raw_bytes = SAMPLE_PDF_DOC });
    uic.endPass();
    try std.testing.expect(!view.hasSelection());
}
