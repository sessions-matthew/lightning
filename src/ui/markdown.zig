//! Rich Markdown Parser & Skia Renderer Component for `ui.Context`.
//!
//! Supported Markdown features:
//!   - ATX Headings (`# H1` through `#### H4`) with section divider rules
//!   - Word-wrapped Paragraphs with inline formatting:
//!     `**bold**`, `*italic*`, `` `inline code` ``, `[links](url)`, and `~~strikethrough~~`
//!   - GitHub-style Callout Alerts (`> [!NOTE]`, `> [!TIP]`, `> [!IMPORTANT]`, `> [!WARNING]`, `> [!CAUTION]`)
//!   - Blockquotes (`> quote`) with vertical accent bars
//!   - Unordered Lists (`-`, `*`, `+`), Ordered Lists (`1.`, `2.`), and Task Lists (`- [ ]`, `- [x]`)
//!   - Fenced Code Blocks (` ```zig ... ``` `) with language header badge, line numbers & syntax highlighting
//!   - Pipe Tables (`| Col A | Col B |`) with column alignment (`:---`, `:---:`, `---:`) and alternating rows
//!   - Horizontal Rules (`---`, `***`, `___`)

const std = @import("std");
const skia = @import("skia");
const root = @import("root.zig");
const c = skia.c;
const Color = skia.Color;
const Rect = skia.Rect;
const Font = skia.Font;
const PathBuilder = skia.PathBuilder;
const Context = root.Context;
const Padding = root.Padding;

pub const MarkdownOptions = struct {
    font_h1: ?Font = null,
    font_h2: ?Font = null,
    font_h3: ?Font = null,
    font_body: ?Font = null,
    font_mono: ?Font = null,
    line_height: f32 = 22.0,
    code_line_height: f32 = 20.0,
    show_code_line_numbers: bool = true,
    syntax_highlight_code: bool = true,
    id_salt: []const u8 = "md",
    scroll_to_heading: []const u8 = "",
};

pub const MarkdownBubbleOptions = struct {
    bg_color: u32 = Color.rgb(28, 33, 43),
    text_color: ?u32 = null,
    border_color: u32 = Color.transparent,
    border_width: f32 = 0.0,
    left_accent_color: u32 = Color.transparent,
    left_accent_width: f32 = 0.0,
    pad_x: f32 = 14.0,
    pad_y: f32 = 10.0,
    line_height: f32 = 20.0,
    blank_gap_h: f32 = 8.0,
    corner_radius: f32 = 10.0,
    id_salt: []const u8 = "md_bubble",
};

pub const MarkdownResult = struct {
    clicked_link: ?[]const u8 = null,
    hovered_link: ?[]const u8 = null,
    block_count: usize = 0,
    target_scroll_y: ?f32 = null,
};

pub const InlineStyle = enum {
    plain,
    bold,
    italic,
    code,
    link,
    strikethrough,
};

pub const InlineSpan = struct {
    style: InlineStyle,
    text: []const u8,
    link_url: []const u8 = "",
};

pub const CalloutKind = enum {
    note,
    tip,
    important,
    warning,
    caution,

    pub fn label(self: CalloutKind) []const u8 {
        return switch (self) {
            .note => "NOTE",
            .tip => "TIP",
            .important => "IMPORTANT",
            .warning => "WARNING",
            .caution => "CAUTION",
        };
    }

    pub fn accentColor(self: CalloutKind) u32 {
        return switch (self) {
            .note => Color.rgb(56, 189, 248),
            .tip => Color.rgb(16, 185, 129),
            .important => Color.rgb(168, 85, 247),
            .warning => Color.rgb(245, 158, 11),
            .caution => Color.rgb(244, 63, 94),
        };
    }

    pub fn bgColor(self: CalloutKind) u32 {
        return switch (self) {
            .note => Color.argb(28, 56, 189, 248),
            .tip => Color.argb(28, 16, 185, 129),
            .important => Color.argb(28, 168, 85, 247),
            .warning => Color.argb(28, 245, 158, 11),
            .caution => Color.argb(28, 244, 63, 94),
        };
    }
};

pub const TableAlign = enum {
    left,
    center,
    right,
};

pub const ListMarker = union(enum) {
    bullet,
    ordered: u32,
    task: bool,
};

pub const Block = union(enum) {
    heading: struct {
        level: u8,
        text: []const u8,
        cached_width_q: i32 = 0,
        cached_wrapped: []const WrappedLine = &.{},
        cached_height: f32 = 0.0,
    },
    paragraph: struct {
        text: []const u8,
        cached_width_q: i32 = 0,
        cached_wrapped: []const WrappedLine = &.{},
        cached_height: f32 = 0.0,
    },
    blockquote: struct {
        callout: ?CalloutKind,
        lines: []const []const u8,
        cached_width_q: i32 = 0,
        cached_wrapped: []const WrappedLine = &.{},
        cached_height: f32 = 0.0,
    },
    list_item: struct {
        indent: u8,
        marker: ListMarker,
        text: []const u8,
        cached_width_q: i32 = 0,
        cached_wrapped: []const WrappedLine = &.{},
        cached_height: f32 = 0.0,
    },
    code_block: struct {
        language: []const u8,
        lines: []const []const u8,
        cached_max_line_w: f32 = -1.0,
    },
    table: struct {
        headers: []const []const u8,
        alignments: []const TableAlign,
        rows: []const []const []const u8,
        is_header_row: []const bool = &.{},
        cached_width_q: i32 = 0,
        cached_height: f32 = 0.0,
    },
    thematic_break,
};

pub const WrappedFragment = struct {
    style: InlineStyle,
    text: []const u8,
    link_url: []const u8,
    x_offset: f32,
    width: f32,
};

pub const WrappedLine = struct {
    fragments: []const WrappedFragment,
    total_width: f32,
};

pub const BubbleLineItem = union(enum) {
    blank,
    wrapped: WrappedLine,
    code_header: []const u8,
    code_line: struct {
        line_num: u32,
        text: []const u8,
        lang: root.CodeLanguage,
    },
};

pub const MdBlockCacheSlot = struct {
    source_ptr: ?[*]const u8 = null,
    source_len: usize = 0,
    blocks: []Block = &.{},
};

pub const MdBubbleCacheSlot = struct {
    source_ptr: ?[*]const u8 = null,
    source_len: usize = 0,
    text_max_w_q: i32 = 0,
    items: []const BubbleLineItem = &.{},
    total_content_h: f32 = 0.0,
};

pub const CodeBlockScrollState = struct {
    scroll_x: f32 = 0.0,
    drag_grab_offset_x: f32 = 0.0,
};

// ============================================================================
// Public Entry Points
// ============================================================================

fn lookupOrParseBlocks(uic: *Context, source: []const u8) []Block {
    if (uic.last_md_source_ptr == source.ptr and uic.last_md_source_len == source.len and uic.last_md_blocks.len > 0) {
        return uic.last_md_blocks;
    }
    for (&uic.md_cache_slots) |*slot| {
        if (slot.source_ptr == source.ptr and slot.source_len == source.len and slot.blocks.len > 0) {
            uic.last_md_source_ptr = source.ptr;
            uic.last_md_source_len = source.len;
            uic.last_md_blocks = slot.blocks;
            return slot.blocks;
        }
    }
    const parsed = parseBlocks(uic.arena, source) catch return &.{};
    uic.last_md_source_ptr = source.ptr;
    uic.last_md_source_len = source.len;
    uic.last_md_blocks = parsed;
    const slot_idx = uic.md_cache_next % @as(u8, @intCast(uic.md_cache_slots.len));
    uic.md_cache_next +%= 1;
    uic.md_cache_slots[slot_idx] = .{
        .source_ptr = source.ptr,
        .source_len = source.len,
        .blocks = parsed,
    };
    return parsed;
}

pub fn render(uic: *Context, source: []const u8, options: MarkdownOptions) MarkdownResult {
    const blocks = lookupOrParseBlocks(uic, source);
    var result = MarkdownResult{
        .block_count = blocks.len,
    };

    const font_h1 = options.font_h1 orelse uic.font_title;
    const font_h2 = options.font_h2 orelse uic.font_title;
    const font_h3 = options.font_h3 orelse uic.font_body;
    const font_body = options.font_body orelse uic.font_body;
    const font_mono = options.font_mono orelse uic.font_mono;

    const has_col_parent = (uic.stack_len > 0 and uic.stack[uic.stack_len - 1].direction == .column);
    const saved_gap: f32 = if (has_col_parent) uic.stack[uic.stack_len - 1].gap else 0.0;
    defer if (has_col_parent) {
        uic.stack[uic.stack_len - 1].gap = saved_gap;
    };

    for (blocks, 0..) |*block, block_idx| {
        if (has_col_parent and block_idx > 0) {
            const prev = blocks[block_idx - 1];
            const base_gap: f32 = if (saved_gap > 0.0) saved_gap else 8.0;
            uic.stack[uic.stack_len - 1].gap = switch (block.*) {
                .list_item => |cur_li| switch (prev) {
                    .list_item => |prev_li| if (cur_li.indent > 0)
                        4.0
                    else if (prev_li.indent > 0)
                        @max(base_gap, 10.0)
                    else
                        6.0,
                    .paragraph => @min(base_gap, 6.0),
                    else => base_gap,
                },
                .heading => @max(base_gap, 12.0),
                else => saved_gap,
            };
        }
        switch (block.*) {
            .heading => |*h| renderHeading(uic, h, font_h1, font_h2, font_h3, font_mono, options, block_idx, &result),
            .paragraph => |*p| renderParagraph(uic, p, font_body, font_mono, options, block_idx, &result),
            .blockquote => |*bq| renderBlockquote(uic, bq, font_body, font_mono, options, block_idx, &result),
            .list_item => |*li| renderListItem(uic, li, font_body, font_mono, options, block_idx, &result),
            .code_block => |*cb| renderCodeBlock(uic, cb, font_mono, options, block_idx),
            .table => |*tbl| renderTable(uic, tbl, font_body, font_mono, options, block_idx, &result),
            .thematic_break => renderThematicBreak(uic),
        }
    }

    return result;
}

/// Renders a padded, rounded message bubble containing word-wrapped inline Markdown lines
/// (such as chat prompt bubbles with `` `code` ``, **bold**, and clickable `file://` links).
pub fn renderBubble(uic: *Context, source: []const u8, opts: MarkdownBubbleOptions) MarkdownResult {
    const trimmed = std.mem.trim(u8, source, " \t\r\n");
    if (trimmed.len == 0) return .{};

    const avail_w = @max(120.0, uic.availableWidth());
    const text_max_w = @max(80.0, avail_w - opts.pad_x * 2.0);
    const text_max_w_q: i32 = @intFromFloat(@round(text_max_w * 4.0));

    var cached_items: ?[]const BubbleLineItem = null;
    var total_content_h: f32 = 0;

    for (&uic.md_bubble_slots) |*slot| {
        if (slot.source_ptr == trimmed.ptr and slot.source_len == trimmed.len and slot.text_max_w_q == text_max_w_q and slot.items.len > 0) {
            cached_items = slot.items;
            total_content_h = slot.total_content_h;
            break;
        }
    }

    const line_items: []const BubbleLineItem = cached_items orelse blk: {
        var items: std.ArrayListUnmanaged(BubbleLineItem) = .empty;
        var line_it = std.mem.splitScalar(u8, trimmed, '\n');
        var in_fence = false;
        var fence_ch: u8 = '`';
        var fence_len: usize = 3;
        var fence_lang: root.CodeLanguage = .plain;
        var code_line_num: u32 = 0;

        while (line_it.next()) |raw_line| {
            const no_cr = std.mem.trimEnd(u8, raw_line, "\r");
            const clean_line = std.mem.trim(u8, no_cr, " \t");

            if (!in_fence and (std.mem.startsWith(u8, clean_line, "```") or std.mem.startsWith(u8, clean_line, "~~~"))) {
                fence_ch = clean_line[0];
                fence_len = 0;
                while (fence_len < clean_line.len and clean_line[fence_len] == fence_ch) : (fence_len += 1) {}
                const lang_str = std.mem.trim(u8, clean_line[fence_len..], " \t");
                fence_lang = if (lang_str.len > 0) root.CodeLanguage.fromFence(lang_str) else .zig;
                code_line_num = 0;
                in_fence = true;
                items.append(uic.arena, .{ .code_header = if (lang_str.len > 0) lang_str else "text" }) catch {};
                total_content_h += opts.line_height + 4.0;
                continue;
            }

            if (in_fence) {
                if (isClosingFence(clean_line, fence_ch, fence_len)) {
                    in_fence = false;
                    continue;
                }
                code_line_num += 1;
                items.append(uic.arena, .{
                    .code_line = .{
                        .line_num = code_line_num,
                        .text = no_cr,
                        .lang = fence_lang,
                    },
                }) catch {};
                total_content_h += opts.line_height;
                continue;
            }

            if (clean_line.len == 0) {
                if (items.items.len > 0 and items.items[items.items.len - 1] != .blank) {
                    items.append(uic.arena, .blank) catch {};
                    total_content_h += opts.blank_gap_h;
                }
                continue;
            }
            const spans = parseInlineSpans(uic.arena, clean_line) catch continue;
            const wlines = wrapInlineSpans(uic, spans, uic.font_body, uic.font_mono, text_max_w);
            for (wlines) |wl| {
                items.append(uic.arena, .{ .wrapped = wl }) catch {};
                total_content_h += opts.line_height;
            }
        }
        while (items.items.len > 0 and items.items[items.items.len - 1] == .blank) {
            _ = items.pop();
            total_content_h = @max(0.0, total_content_h - opts.blank_gap_h);
        }
        const slice = items.items;
        if (slice.len > 0) {
            const slot_idx = uic.md_bubble_next % @as(u8, @intCast(uic.md_bubble_slots.len));
            uic.md_bubble_next +%= 1;
            uic.md_bubble_slots[slot_idx] = .{
                .source_ptr = trimmed.ptr,
                .source_len = trimmed.len,
                .text_max_w_q = text_max_w_q,
                .items = slice,
                .total_content_h = total_content_h,
            };
        }
        break :blk slice;
    };

    if (line_items.len == 0) return .{};

    const bubble_h: f32 = total_content_h + opts.pad_y * 2.0;
    const r = uic.nextRect(0, bubble_h);
    if (!uic.isRectInViewport(r)) return .{ .block_count = 1 };

    if (uic.shouldPaint(r)) {
        uic.paint.setStyle(.fill);
        uic.paint.setColor(opts.bg_color);
        uic.canvas.drawRoundRect(r, opts.corner_radius, opts.corner_radius, uic.paint);

        if (opts.border_width > 0.0 and opts.border_color != Color.transparent) {
            uic.paint.setStyle(.stroke);
            uic.paint.setStrokeWidth(opts.border_width);
            uic.paint.setColor(opts.border_color);
            uic.canvas.drawRoundRect(r, opts.corner_radius, opts.corner_radius, uic.paint);
        }

        if (opts.left_accent_width > 0.0 and opts.left_accent_color != Color.transparent) {
            uic.paint.setStyle(.fill);
            uic.paint.setColor(opts.left_accent_color);
            uic.canvas.drawRoundRect(
                Rect.xywh(r.left, r.top + 3.0, opts.left_accent_width, @max(1.0, (r.bottom - r.top) - 6.0)),
                opts.left_accent_width * 0.5,
                opts.left_accent_width * 0.5,
                uic.paint,
            );
        }
    }

    const md_opts = MarkdownOptions{
        .line_height = opts.line_height,
        .id_salt = opts.id_salt,
    };
    var md_res = MarkdownResult{ .block_count = 1 };
    const fg = opts.text_color orelse uic.theme.text_primary;
    const vp = uic.activeViewportY();

    var cur_y: f32 = r.top + opts.pad_y;
    for (line_items, 0..) |item, line_idx| {
        switch (item) {
            .blank => {
                cur_y += opts.blank_gap_h;
            },
            .wrapped => |wl| {
                if (cur_y + opts.line_height >= vp.top and cur_y <= vp.bottom) {
                    drawWrappedLine(
                        uic,
                        wl,
                        r.left + opts.pad_x,
                        cur_y,
                        opts.line_height,
                        fg,
                        false,
                        uic.font_body,
                        uic.font_mono,
                        md_opts,
                        0,
                        line_idx,
                        &md_res,
                    );
                }
                cur_y += opts.line_height;
            },
            .code_header => |lang_lbl| {
                const hdr_h = opts.line_height + 4.0;
                if (cur_y + hdr_h >= vp.top and cur_y <= vp.bottom) {
                    const hdr_r = Rect.xywh(r.left + opts.pad_x, cur_y + 1.0, text_max_w, hdr_h - 1.0);
                    if (uic.shouldPaint(hdr_r)) {
                        uic.paint.setStyle(.fill);
                        uic.paint.setColor(Color.rgb(22, 29, 44));
                        uic.canvas.drawRoundRect(hdr_r, 5.0, 5.0, uic.paint);
                        uic.canvas.drawRect(Rect.xywh(hdr_r.left, hdr_r.bottom - 5.0, text_max_w, 5.0), uic.paint);
                        uic.paint.setColor(uic.theme.accent_hover);
                        uic.canvas.drawCircle(hdr_r.left + 10.0, cur_y + hdr_h * 0.5, 3.0, uic.paint);
                        uic.paint.setColor(uic.theme.text_primary);
                        uic.drawTextCached(uic.font_mono, lang_lbl, hdr_r.left + 18.0, cur_y + hdr_h * 0.72);
                    }
                }
                cur_y += hdr_h;
            },
            .code_line => |cl| {
                if (cur_y + opts.line_height >= vp.top and cur_y <= vp.bottom) {
                    const row_r = Rect.xywh(r.left + opts.pad_x, cur_y, text_max_w, opts.line_height);
                    if (uic.shouldPaint(row_r)) {
                        uic.paint.setStyle(.fill);
                        uic.paint.setColor(Color.rgb(13, 18, 28));
                        uic.canvas.drawRect(row_r, uic.paint);

                        const by = cur_y + opts.line_height * 0.74;
                        const num_str = uic.fmt("{d:>2}", .{cl.line_num});
                        uic.paint.setColor(Color.rgb(84, 96, 118));
                        uic.drawTextCached(uic.font_mono, num_str, row_r.left + 8.0, by);

                        const code_x = row_r.left + 32.0;
                        const clip_r = Rect.ltrb(code_x - 2.0, cur_y, row_r.right - 4.0, cur_y + opts.line_height);
                        const save_cnt = uic.canvas.save();
                        uic.canvas.clipRect(clip_r, .intersect, false);
                        if (cl.lang != .plain) {
                            root.drawSyntaxHighlightedLine(uic, uic.font_mono, cl.text, code_x, by, cl.lang);
                        } else {
                            uic.paint.setStyle(.fill);
                            uic.paint.setColor(Color.rgb(226, 232, 240));
                            uic.drawTextCached(uic.font_mono, cl.text, code_x, by);
                        }
                        uic.canvas.restoreToCount(save_cnt);
                    }
                }
                cur_y += opts.line_height;
            },
        }
    }

    return md_res;
}

// ============================================================================
// Block-Level Markdown Parser
// ============================================================================

pub fn parseBlocks(arena: std.mem.Allocator, source: []const u8) ![]Block {
    var blocks: std.ArrayListUnmanaged(Block) = .empty;
    var lines_list: std.ArrayListUnmanaged([]const u8) = .empty;
    try lines_list.ensureTotalCapacity(arena, @max(16, source.len / 48));
    try blocks.ensureTotalCapacity(arena, @max(16, source.len / 96));

    var line_it = std.mem.splitScalar(u8, source, '\n');
    while (line_it.next()) |raw_line| {
        const line = std.mem.trimEnd(u8, raw_line, "\r");
        try lines_list.append(arena, line);
    }

    const lines = lines_list.items;
    var i: usize = 0;

    while (i < lines.len) {
        const line = lines[i];
        const trimmed = std.mem.trim(u8, line, " \t");

        // 1. Skip blank lines
        if (trimmed.len == 0) {
            i += 1;
            continue;
        }

        // 2. Fenced Code Block (``` or ~~~)
        if (std.mem.startsWith(u8, trimmed, "```") or std.mem.startsWith(u8, trimmed, "~~~")) {
            const fence_ch = trimmed[0];
            var fence_len: usize = 0;
            while (fence_len < trimmed.len and trimmed[fence_len] == fence_ch) : (fence_len += 1) {}
            const lang = std.mem.trim(u8, trimmed[fence_len..], " \t");
            var fence_indent: usize = 0;
            while (fence_indent < line.len and line[fence_indent] == ' ') : (fence_indent += 1) {}
            i += 1;
            var code_lines: std.ArrayListUnmanaged([]const u8) = .empty;
            while (i < lines.len) {
                const candidate = std.mem.trim(u8, lines[i], " \t");
                if (isClosingFence(candidate, fence_ch, fence_len)) {
                    i += 1;
                    break;
                }
                var strip_n: usize = 0;
                while (strip_n < fence_indent and strip_n < lines[i].len and lines[i][strip_n] == ' ') : (strip_n += 1) {}
                try code_lines.append(arena, lines[i][strip_n..]);
                i += 1;
            }
            try blocks.append(arena, .{
                .code_block = .{
                    .language = lang,
                    .lines = code_lines.items,
                },
            });
            continue;
        }

        // 2b. Display Math Block ($$ ... $$ or \[ ... \])
        if (std.mem.startsWith(u8, trimmed, "$$") or std.mem.startsWith(u8, trimmed, "\\[")) {
            const close_delim: []const u8 = if (std.mem.startsWith(u8, trimmed, "$$")) "$$" else "\\]";
            const after_open = std.mem.trim(u8, trimmed[2..], " \t");
            if (after_open.len >= close_delim.len and std.mem.endsWith(u8, after_open, close_delim)) {
                const inner_math = std.mem.trim(u8, after_open[0 .. after_open.len - close_delim.len], " \t");
                const formatted = try formatLatexMath(arena, inner_math);
                if (formatted.len > 0) {
                    try blocks.append(arena, .{ .paragraph = .{ .text = formatted } });
                }
                i += 1;
                continue;
            }
            i += 1;
            var math_parts: std.ArrayListUnmanaged([]const u8) = .empty;
            if (after_open.len > 0) {
                try math_parts.append(arena, after_open);
            }
            while (i < lines.len) {
                const m_trimmed = std.mem.trim(u8, lines[i], " \t");
                if (std.mem.endsWith(u8, m_trimmed, close_delim)) {
                    const before_close = std.mem.trim(u8, m_trimmed[0 .. m_trimmed.len - close_delim.len], " \t");
                    if (before_close.len > 0) {
                        try math_parts.append(arena, before_close);
                    }
                    i += 1;
                    break;
                }
                if (m_trimmed.len > 0) {
                    try math_parts.append(arena, m_trimmed);
                }
                i += 1;
            }
            const joined_math = try joinWithSpaces(arena, math_parts.items);
            const formatted = try formatLatexMath(arena, joined_math);
            if (formatted.len > 0) {
                try blocks.append(arena, .{ .paragraph = .{ .text = formatted } });
            }
            continue;
        }

        // 3. ATX Heading (# to ####)
        if (parseHeadingLine(trimmed)) |h| {
            try blocks.append(arena, .{
                .heading = .{
                    .level = h.level,
                    .text = h.text,
                },
            });
            i += 1;
            continue;
        }

        // 4. Thematic Break (---, ***, ___)
        if (isThematicBreak(trimmed)) {
            try blocks.append(arena, .thematic_break);
            i += 1;
            continue;
        }

        // 5. Pipe Table (| Header | ... followed by | --- | ... OR consecutive | Row | lines)
        if (isTableRow(trimmed) and i + 1 < lines.len and (isTableSeparatorRow(std.mem.trim(u8, lines[i + 1], " \t")) or isTableRow(std.mem.trim(u8, lines[i + 1], " \t")))) {
            const has_sep = isTableSeparatorRow(std.mem.trim(u8, lines[i + 1], " \t"));
            const headers = try parseTableCells(arena, trimmed);
            const alignments = if (has_sep)
                try parseTableAlignments(arena, std.mem.trim(u8, lines[i + 1], " \t"), headers.len)
            else blk: {
                const aligns = try arena.alloc(TableAlign, headers.len);
                @memset(aligns, .left);
                break :blk aligns;
            };
            i += if (has_sep) 2 else 1;

            var table_rows: std.ArrayListUnmanaged([]const []const u8) = .empty;
            var is_header_list: std.ArrayListUnmanaged(bool) = .empty;
            while (i < lines.len) {
                const row_trimmed = std.mem.trim(u8, lines[i], " \t");
                if (!isTableRow(row_trimmed)) break;
                if (isTableSeparatorRow(row_trimmed)) {
                    i += 1;
                    continue;
                }

                var is_hdr = false;
                if (i + 1 < lines.len and isTableSeparatorRow(std.mem.trim(u8, lines[i + 1], " \t"))) {
                    is_hdr = true;
                }

                const cells = try parseTableCells(arena, row_trimmed);
                try table_rows.append(arena, cells);
                try is_header_list.append(arena, is_hdr);
                i += if (is_hdr) 2 else 1;
            }

            try blocks.append(arena, .{
                .table = .{
                    .headers = headers,
                    .alignments = alignments,
                    .rows = table_rows.items,
                    .is_header_row = is_header_list.items,
                },
            });
            continue;
        }

        // 6. Blockquote / Callout Alert (> ...)
        if (std.mem.startsWith(u8, trimmed, ">")) {
            var raw_items: std.ArrayListUnmanaged([]const u8) = .empty;
            var callout: ?CalloutKind = null;

            while (i < lines.len) {
                const cur_line = lines[i];
                var lead_idx: usize = 0;
                while (lead_idx < cur_line.len and (cur_line[lead_idx] == ' ' or cur_line[lead_idx] == '\t')) {
                    lead_idx += 1;
                }
                if (lead_idx >= cur_line.len or cur_line[lead_idx] != '>') break;

                // Content after '>'
                var after_gt = cur_line[lead_idx + 1 ..];
                if (after_gt.len > 0 and (after_gt[0] == ' ' or after_gt[0] == '\t')) {
                    after_gt = after_gt[1..];
                }

                // Check for Callout header (e.g. > [!TIP], > [!NOTE]) on the first line
                const trimmed_content = std.mem.trim(u8, after_gt, " \t\r");
                if (raw_items.items.len == 0 and callout == null) {
                    if (parseCalloutTag(trimmed_content)) |parsed_callout| {
                        callout = parsed_callout.kind;
                        if (parsed_callout.remainder.len > 0) {
                            try raw_items.append(arena, parsed_callout.remainder);
                        }
                        i += 1;
                        continue;
                    }
                }

                const no_cr = if (after_gt.len > 0 and after_gt[after_gt.len - 1] == '\r')
                    after_gt[0 .. after_gt.len - 1]
                else
                    after_gt;
                try raw_items.append(arena, no_cr);
                i += 1;
            }

            var quote_lines: std.ArrayListUnmanaged([]const u8) = .empty;
            var cur_buf: ?[]const u8 = null;

            for (raw_items.items) |raw_item| {
                const item_trimmed = std.mem.trim(u8, raw_item, " \t");
                if (item_trimmed.len == 0) {
                    if (cur_buf) |cb| {
                        const trimmed_cb = if (cb.len >= 1 and cb[cb.len - 1] == '\\')
                            cb[0 .. cb.len - 1]
                        else
                            std.mem.trimEnd(u8, cb, " ");
                        try quote_lines.append(arena, trimmed_cb);
                        cur_buf = null;
                    }
                    try quote_lines.append(arena, "");
                    continue;
                }

                const is_list = (parseListItemLine(item_trimmed) != null);
                const is_heading = (parseHeadingLine(item_trimmed) != null);

                if (cur_buf) |cb| {
                    const prev_hard_break = (cb.len >= 2 and cb[cb.len - 1] == ' ' and cb[cb.len - 2] == ' ') or
                        (cb.len >= 1 and cb[cb.len - 1] == '\\');

                    if (is_list or is_heading or prev_hard_break) {
                        const trimmed_cb = if (cb.len >= 1 and cb[cb.len - 1] == '\\')
                            cb[0 .. cb.len - 1]
                        else
                            std.mem.trimEnd(u8, cb, " ");
                        try quote_lines.append(arena, trimmed_cb);
                        cur_buf = raw_item;
                    } else {
                        const joined = try std.fmt.allocPrint(arena, "{s} {s}", .{ std.mem.trimEnd(u8, cb, " \t"), item_trimmed });
                        cur_buf = joined;
                    }
                } else {
                    cur_buf = raw_item;
                }
            }

            if (cur_buf) |cb| {
                const trimmed_cb = if (cb.len >= 1 and cb[cb.len - 1] == '\\')
                    cb[0 .. cb.len - 1]
                else
                    std.mem.trimEnd(u8, cb, " ");
                try quote_lines.append(arena, trimmed_cb);
            }

            try blocks.append(arena, .{
                .blockquote = .{
                    .callout = callout,
                    .lines = quote_lines.items,
                },
            });
            continue;
        }

        // 7. List Item (-, *, +, 1., - [ ], - [x])
        if (parseListItemLine(line)) |li| {
            i += 1;
            // Fast path: check if next line is an indented or lazy continuation line before allocating `item_parts`
            var item_parts: std.ArrayListUnmanaged([]const u8) = .empty;
            while (i < lines.len) {
                const next_line = lines[i];
                const next_trimmed = std.mem.trim(u8, next_line, " \t");
                if (next_trimmed.len == 0) break;
                if (std.mem.startsWith(u8, next_trimmed, "```") or std.mem.startsWith(u8, next_trimmed, "~~~")) break;
                if (std.mem.startsWith(u8, next_trimmed, "$$") or std.mem.startsWith(u8, next_trimmed, "\\[")) break;
                if (parseHeadingLine(next_trimmed) != null) break;
                if (isThematicBreak(next_trimmed)) break;
                if (std.mem.startsWith(u8, next_trimmed, ">")) break;
                if (parseListItemLine(next_line) != null) break;
                if (isTableRow(next_trimmed)) break;

                if (item_parts.items.len == 0 and li.text.len > 0) {
                    try item_parts.append(arena, li.text);
                }
                try item_parts.append(arena, next_trimmed);
                i += 1;
            }
            const joined_item = if (item_parts.items.len == 0) li.text else try joinWithSpaces(arena, item_parts.items);
            try blocks.append(arena, .{
                .list_item = .{
                    .indent = li.indent,
                    .marker = li.marker,
                    .text = joined_item,
                },
            });
            continue;
        }

        // 8. Paragraph (accumulate consecutive non-special lines; zero-alloc fast path for single-line paragraphs)
        const first_para_line = trimmed;
        i += 1;
        var para_parts: std.ArrayListUnmanaged([]const u8) = .empty;
        while (i < lines.len) {
            const p_line = lines[i];
            const p_trimmed = std.mem.trim(u8, p_line, " \t");
            if (p_trimmed.len == 0) break;
            if (std.mem.startsWith(u8, p_trimmed, "```") or std.mem.startsWith(u8, p_trimmed, "~~~")) break;
            if (std.mem.startsWith(u8, p_trimmed, "$$") or std.mem.startsWith(u8, p_trimmed, "\\[")) break;
            if (parseHeadingLine(p_trimmed) != null) break;
            if (isThematicBreak(p_trimmed)) break;
            if (std.mem.startsWith(u8, p_trimmed, ">")) break;
            if (parseListItemLine(p_line) != null) break;
            if (isTableRow(p_trimmed) and i + 1 < lines.len and isTableSeparatorRow(std.mem.trim(u8, lines[i + 1], " \t"))) break;

            if (para_parts.items.len == 0) {
                try para_parts.append(arena, first_para_line);
            }
            try para_parts.append(arena, p_trimmed);
            i += 1;
        }

        const para_text = if (para_parts.items.len == 0) first_para_line else try joinWithSpaces(arena, para_parts.items);
        if (para_text.len > 0) {
            try blocks.append(arena, .{
                .paragraph = .{ .text = para_text },
            });
        }
    }

    return blocks.items;
}

fn isClosingFence(candidate: []const u8, fence_ch: u8, min_len: usize) bool {
    if (candidate.len < min_len) return false;
    var count: usize = 0;
    while (count < candidate.len and candidate[count] == fence_ch) : (count += 1) {}
    if (count < min_len) return false;
    const rest = std.mem.trim(u8, candidate[count..], " \t\r");
    return rest.len == 0;
}

fn inferUntaggedCodeLanguage(lines: []const []const u8) root.CodeLanguage {
    for (lines) |raw_line| {
        const t = std.mem.trimStart(u8, raw_line, " \t");
        if (std.mem.startsWith(u8, t, "module ") or
            std.mem.startsWith(u8, t, "endmodule") or
            std.mem.startsWith(u8, t, "package ") or
            std.mem.startsWith(u8, t, "endpackage") or
            std.mem.startsWith(u8, t, "always_ff") or
            std.mem.startsWith(u8, t, "always_comb") or
            std.mem.startsWith(u8, t, "always_latch") or
            std.mem.startsWith(u8, t, "logic ") or
            std.mem.startsWith(u8, t, "assign ") or
            std.mem.indexOf(u8, t, "$display(") != null or
            std.mem.indexOf(u8, t, "$finish") != null)
        {
            return .systemverilog;
        }
    }
    return .zig;
}

fn parseHeadingLine(trimmed: []const u8) ?struct { level: u8, text: []const u8 } {
    var hashes: u8 = 0;
    while (hashes < trimmed.len and hashes < 6 and trimmed[hashes] == '#') {
        hashes += 1;
    }
    if (hashes == 0 or hashes >= trimmed.len) return null;
    if (trimmed[hashes] != ' ' and trimmed[hashes] != '\t') return null;
    const text = std.mem.trim(u8, trimmed[hashes..], " \t#");
    if (text.len == 0) return null;
    return .{ .level = @min(hashes, 4), .text = text };
}

fn normalizeSlugBuf(input: []const u8, out_buf: *[192]u8) []const u8 {
    var len: usize = 0;
    var prev_dash = true;
    for (input) |ch| {
        if (std.ascii.isAlphanumeric(ch)) {
            if (len < out_buf.len) {
                out_buf[len] = std.ascii.toLower(ch);
                len += 1;
            }
            prev_dash = false;
        } else if ((ch == ' ' or ch == '-' or ch == '_') and !prev_dash) {
            if (len < out_buf.len) {
                out_buf[len] = '-';
                len += 1;
            }
            prev_dash = true;
        }
    }
    while (len > 0 and out_buf[len - 1] == '-') {
        len -= 1;
    }
    return out_buf[0..len];
}

/// Checks whether a Markdown heading title (`heading_text`) matches a target heading title or `#anchor` slug.
pub fn headingMatchesSlug(heading_text: []const u8, target: []const u8) bool {
    const clean_target = std.mem.trim(u8, target, " \t\r\n#");
    const clean_heading = std.mem.trim(u8, heading_text, " \t\r\n#");
    if (clean_target.len == 0 or clean_heading.len == 0) return false;
    if (std.ascii.eqlIgnoreCase(clean_heading, clean_target)) return true;

    var h_buf: [192]u8 = undefined;
    var t_buf: [192]u8 = undefined;
    const h_slug = normalizeSlugBuf(clean_heading, &h_buf);
    const t_slug = normalizeSlugBuf(clean_target, &t_buf);
    if (h_slug.len == 0 or t_slug.len == 0) return false;
    return std.mem.eql(u8, h_slug, t_slug);
}

/// Finds the 1-based line number of the first ATX heading in `source` matching `target_slug_or_title`
/// (skipping lines inside fenced code blocks).
pub fn findHeadingLine(source: []const u8, target_slug_or_title: []const u8) ?usize {
    const clean_target = std.mem.trim(u8, target_slug_or_title, " \t\r\n#");
    if (clean_target.len == 0) return null;

    var in_fence = false;
    var fence_prefix: [3]u8 = .{ '`', '`', '`' };
    var line_it = std.mem.splitScalar(u8, source, '\n');
    var line_num: usize = 1;
    while (line_it.next()) |raw_line| : (line_num += 1) {
        const trimmed = std.mem.trim(u8, raw_line, " \t\r");
        if (std.mem.startsWith(u8, trimmed, "```") or std.mem.startsWith(u8, trimmed, "~~~")) {
            if (!in_fence) {
                in_fence = true;
                @memcpy(&fence_prefix, trimmed[0..3]);
            } else if (std.mem.startsWith(u8, trimmed, &fence_prefix)) {
                in_fence = false;
            }
            continue;
        }
        if (in_fence) continue;
        if (parseHeadingLine(trimmed)) |h| {
            if (headingMatchesSlug(h.text, clean_target)) return line_num;
        }
    }
    return null;
}

fn isThematicBreak(trimmed: []const u8) bool {
    if (trimmed.len < 3) return false;
    const ch = trimmed[0];
    if (ch != '-' and ch != '*' and ch != '_') return false;
    var count: usize = 0;
    for (trimmed) |c_byte| {
        if (c_byte == ch) {
            count += 1;
        } else if (c_byte != ' ' and c_byte != '\t') {
            return false;
        }
    }
    return count >= 3;
}

fn parseCalloutTag(text: []const u8) ?struct { kind: CalloutKind, remainder: []const u8 } {
    const tags = [_]struct { prefix: []const u8, kind: CalloutKind }{
        .{ .prefix = "[!NOTE]", .kind = .note },
        .{ .prefix = "[!TIP]", .kind = .tip },
        .{ .prefix = "[!IMPORTANT]", .kind = .important },
        .{ .prefix = "[!WARNING]", .kind = .warning },
        .{ .prefix = "[!CAUTION]", .kind = .caution },
    };
    for (tags) |t| {
        if (std.ascii.startsWithIgnoreCase(text, t.prefix)) {
            const rem = std.mem.trim(u8, text[t.prefix.len..], " \t");
            return .{ .kind = t.kind, .remainder = rem };
        }
    }
    return null;
}

fn parseListItemLine(raw_line: []const u8) ?struct { indent: u8, marker: ListMarker, text: []const u8 } {
    var spaces: usize = 0;
    var visual_cols: usize = 0;
    while (spaces < raw_line.len and (raw_line[spaces] == ' ' or raw_line[spaces] == '\t')) {
        visual_cols += if (raw_line[spaces] == '\t') 4 else 1;
        spaces += 1;
    }
    const indent: u8 = if (visual_cols < 2)
        0
    else if (visual_cols <= 4)
        1
    else if (visual_cols <= 8)
        2
    else if (visual_cols <= 12)
        3
    else
        4;
    const rest = raw_line[spaces..];
    if (rest.len < 2) return null;

    // Unordered or Task list (-, *, +)
    if ((rest[0] == '-' or rest[0] == '*' or rest[0] == '+') and (rest[1] == ' ' or rest[1] == '\t')) {
        const after_bullet = std.mem.trimStart(u8, rest[2..], " \t");
        if (after_bullet.len >= 3 and after_bullet[0] == '[' and after_bullet[2] == ']') {
            const check_ch = after_bullet[1];
            if (check_ch == ' ' or check_ch == 'x' or check_ch == 'X') {
                const task_text = std.mem.trim(u8, after_bullet[3..], " \t");
                return .{
                    .indent = indent,
                    .marker = .{ .task = (check_ch == 'x' or check_ch == 'X') },
                    .text = task_text,
                };
            }
        }
        return .{
            .indent = indent,
            .marker = .bullet,
            .text = std.mem.trim(u8, after_bullet, " \t"),
        };
    }

    // Ordered list (1. , 2. , etc.)
    var digit_end: usize = 0;
    while (digit_end < rest.len and std.ascii.isDigit(rest[digit_end])) {
        digit_end += 1;
    }
    if (digit_end > 0 and digit_end + 1 < rest.len and (rest[digit_end] == '.' or rest[digit_end] == ')') and (rest[digit_end + 1] == ' ' or rest[digit_end + 1] == '\t')) {
        const num = std.fmt.parseInt(u32, rest[0..digit_end], 10) catch 1;
        const item_text = std.mem.trim(u8, rest[digit_end + 2 ..], " \t");
        return .{
            .indent = indent,
            .marker = .{ .ordered = num },
            .text = item_text,
        };
    }

    return null;
}

fn isTableRow(trimmed: []const u8) bool {
    if (trimmed.len < 3) return false;
    return trimmed[0] == '|' and std.mem.indexOfScalarPos(u8, trimmed, 1, '|') != null;
}

fn isTableSeparatorRow(trimmed: []const u8) bool {
    if (!isTableRow(trimmed)) return false;
    var has_dash = false;
    for (trimmed) |ch| {
        switch (ch) {
            '-' => has_dash = true,
            '|', ':', ' ', '\t' => {},
            else => return false,
        }
    }
    return has_dash;
}

fn unescapeTablePipe(arena: std.mem.Allocator, cell: []const u8) ![]const u8 {
    if (std.mem.indexOf(u8, cell, "\\|") == null) return cell;
    var out: std.ArrayListUnmanaged(u8) = .empty;
    var i: usize = 0;
    while (i < cell.len) {
        if (cell[i] == '\\' and i + 1 < cell.len and cell[i + 1] == '|') {
            try out.append(arena, '|');
            i += 2;
        } else {
            try out.append(arena, cell[i]);
            i += 1;
        }
    }
    return out.items;
}

fn parseTableCells(arena: std.mem.Allocator, trimmed: []const u8) ![]const []const u8 {
    var inner = trimmed;
    if (std.mem.startsWith(u8, inner, "|")) inner = inner[1..];
    if (std.mem.endsWith(u8, inner, "|") and (inner.len < 2 or inner[inner.len - 2] != '\\')) {
        inner = inner[0 .. inner.len - 1];
    }

    var cells: std.ArrayListUnmanaged([]const u8) = .empty;
    var cell_start: usize = 0;
    var i: usize = 0;
    while (i < inner.len) {
        if (inner[i] == '\\' and i + 1 < inner.len) {
            i += 2;
            continue;
        }
        if (inner[i] == '`') {
            var tick_len: usize = 1;
            while (i + tick_len < inner.len and inner[i + tick_len] == '`') : (tick_len += 1) {}
            if (findBacktickRun(inner, i + tick_len, tick_len)) |close_tick| {
                i = close_tick + tick_len;
                continue;
            }
            i += tick_len;
            continue;
        }
        if (inner[i] == '|') {
            const raw_cell = std.mem.trim(u8, inner[cell_start..i], " \t");
            try cells.append(arena, try unescapeTablePipe(arena, raw_cell));
            cell_start = i + 1;
        }
        i += 1;
    }
    const last_cell = std.mem.trim(u8, inner[cell_start..], " \t");
    try cells.append(arena, try unescapeTablePipe(arena, last_cell));
    return cells.items;
}

fn parseTableAlignments(arena: std.mem.Allocator, sep_row: []const u8, expected_cols: usize) ![]const TableAlign {
    const raw_cells = try parseTableCells(arena, sep_row);
    var aligns = try arena.alloc(TableAlign, @max(expected_cols, raw_cells.len));
    for (0..aligns.len) |col_idx| {
        if (col_idx < raw_cells.len) {
            const cell = raw_cells[col_idx];
            const left_colon = std.mem.startsWith(u8, cell, ":");
            const right_colon = std.mem.endsWith(u8, cell, ":");
            aligns[col_idx] = if (left_colon and right_colon)
                .center
            else if (right_colon)
                .right
            else
                .left;
        } else {
            aligns[col_idx] = .left;
        }
    }
    return aligns;
}

fn joinWithSpaces(arena: std.mem.Allocator, parts: []const []const u8) ![]const u8 {
    if (parts.len == 0) return "";
    if (parts.len == 1) return parts[0];
    var total_len: usize = 0;
    for (parts, 0..) |p, idx| {
        total_len += p.len;
        if (idx + 1 < parts.len) total_len += 1;
    }
    var buf = try arena.alloc(u8, total_len);
    var pos: usize = 0;
    for (parts, 0..) |p, idx| {
        @memcpy(buf[pos .. pos + p.len], p);
        pos += p.len;
        if (idx + 1 < parts.len) {
            buf[pos] = ' ';
            pos += 1;
        }
    }
    return buf;
}

// ============================================================================
// Inline Span Parser (`**bold**`, `*italic*`, `` `code` ``, `[link](url)`, `~~strike~~`)
// ============================================================================

pub fn parseInlineSpans(arena: std.mem.Allocator, text: []const u8) ![]const InlineSpan {
    var spans: std.ArrayListUnmanaged(InlineSpan) = .empty;
    try parseInlineSpansInto(arena, text, .plain, &spans);
    return spans.items;
}

fn appendOrCoalesceSpan(
    arena: std.mem.Allocator,
    spans: *std.ArrayListUnmanaged(InlineSpan),
    new_span: InlineSpan,
) !void {
    if (new_span.text.len == 0) return;
    if (new_span.style != .code and new_span.style != .link and spans.items.len > 0) {
        const last = &spans.items[spans.items.len - 1];
        if (last.style == new_span.style and last.link_url.len == 0) {
            const combined = try arena.alloc(u8, last.text.len + new_span.text.len);
            @memcpy(combined[0..last.text.len], last.text);
            @memcpy(combined[last.text.len..], new_span.text);
            last.text = combined;
            return;
        }
    }
    try spans.append(arena, new_span);
}

const MatchedMath = struct {
    content: []const u8,
    end_pos: usize,
};

fn matchInlineMath(text: []const u8, start: usize) ?MatchedMath {
    if (start >= text.len) return null;

    // 1. Display/inline math `$$...$$`
    if (text[start] == '$' and start + 1 < text.len and text[start + 1] == '$') {
        if (start > 0 and text[start - 1] == '\\') return null;
        var i: usize = start + 2;
        while (i + 1 < text.len) : (i += 1) {
            if (text[i] == '\\') {
                i += 1;
                continue;
            }
            if (text[i] == '$' and text[i + 1] == '$') {
                const inner = std.mem.trim(u8, text[start + 2 .. i], " \t");
                if (inner.len > 0) {
                    return .{ .content = inner, .end_pos = i + 2 };
                }
                return null;
            }
        }
        return null;
    }

    // 2. LaTeX inline `\( ... \)` or display `\[ ... \]`
    if (text[start] == '\\' and start + 1 < text.len and (text[start + 1] == '(' or text[start + 1] == '[')) {
        const close_ch: u8 = if (text[start + 1] == '(') ')' else ']';
        var i: usize = start + 2;
        while (i + 1 < text.len) : (i += 1) {
            if (text[i] == '\\' and text[i + 1] == close_ch) {
                const inner = std.mem.trim(u8, text[start + 2 .. i], " \t");
                if (inner.len > 0) {
                    return .{ .content = inner, .end_pos = i + 2 };
                }
                return null;
            }
        }
        return null;
    }

    // 3. Single-dollar inline math `$...$`
    if (text[start] == '$') {
        if (start > 0 and (text[start - 1] == '\\' or text[start - 1] == '$' or std.ascii.isAlphanumeric(text[start - 1]))) {
            return null;
        }
        if (start + 1 >= text.len) return null;
        const first_ch = text[start + 1];
        if (first_ch == ' ' or first_ch == '\t' or first_ch == '\n' or first_ch == '\r' or first_ch == '$' or first_ch == '`') {
            return null;
        }

        var i: usize = start + 1;
        var has_space = false;
        var has_math_indicator = false;
        while (i < text.len) : (i += 1) {
            const ch = text[i];
            if (ch == '\n' or ch == '\r' or ch == '`') return null;
            if (ch == '\\') {
                has_math_indicator = true;
                i += 1;
                continue;
            }
            if (ch == ' ' or ch == '\t') {
                has_space = true;
                continue;
            }
            if (ch == '^' or ch == '_' or ch == '=' or ch == '<' or ch == '>' or ch == '+' or ch == '-' or ch == '*' or ch == '/' or ch == '(' or ch == ')' or ch == '{' or ch == '}') {
                has_math_indicator = true;
            }
            if (ch == '$') {
                if (text[i - 1] == ' ' or text[i - 1] == '\t') return null;
                if (i + 1 < text.len and (std.ascii.isAlphanumeric(text[i + 1]) or text[i + 1] == '_' or text[i + 1] == '$')) return null;
                // Guard against prose currency pairs like "$100 and $200"
                if (std.ascii.isDigit(first_ch) and has_space and !has_math_indicator) return null;
                return .{
                    .content = text[start + 1 .. i],
                    .end_pos = i + 1,
                };
            }
        }
    }

    return null;
}

fn extractBracedGroup(text: []const u8, start: usize) ?struct { inner: []const u8, end_pos: usize } {
    var i = start;
    while (i < text.len and (text[i] == ' ' or text[i] == '\t')) : (i += 1) {}
    if (i >= text.len or text[i] != '{') return null;
    var depth: usize = 1;
    const content_start = i + 1;
    i += 1;
    while (i < text.len) : (i += 1) {
        if (text[i] == '\\') {
            i += 1;
            continue;
        }
        if (text[i] == '{') {
            depth += 1;
        } else if (text[i] == '}') {
            depth -= 1;
            if (depth == 0) {
                return .{ .inner = text[content_start..i], .end_pos = i + 1 };
            }
        }
    }
    return null;
}

fn mapSuperscriptChar(ch: u8) ?[]const u8 {
    return switch (ch) {
        '0' => "⁰",
        '1' => "¹",
        '2' => "²",
        '3' => "³",
        '4' => "⁴",
        '5' => "⁵",
        '6' => "⁶",
        '7' => "⁷",
        '8' => "⁸",
        '9' => "⁹",
        '+' => "⁺",
        '-' => "⁻",
        '=' => "⁼",
        '(' => "⁽",
        ')' => "⁾",
        'n' => "ⁿ",
        'i' => "ⁱ",
        'k' => "ᵏ",
        'm' => "ᵐ",
        'T' => "ᵀ",
        else => null,
    };
}

fn mapSubscriptChar(ch: u8) ?[]const u8 {
    return switch (ch) {
        '0' => "₀",
        '1' => "₁",
        '2' => "₂",
        '3' => "₃",
        '4' => "₄",
        '5' => "₅",
        '6' => "₆",
        '7' => "₇",
        '8' => "₈",
        '9' => "₉",
        '+' => "₊",
        '-' => "₋",
        '=' => "₌",
        '(' => "₍",
        ')' => "₎",
        'a' => "ₐ",
        'e' => "ₑ",
        'h' => "ₕ",
        'i' => "ᵢ",
        'j' => "ⱼ",
        'k' => "ₖ",
        'l' => "ₗ",
        'm' => "ₘ",
        'n' => "ₙ",
        'o' => "ₒ",
        'p' => "ₚ",
        'r' => "ᵣ",
        's' => "ₛ",
        't' => "ₜ",
        'u' => "ᵤ",
        'v' => "ᵥ",
        'x' => "ₓ",
        else => null,
    };
}

const LatexSymbolEntry = struct {
    cmd: []const u8,
    repl: []const u8,
    is_relation: bool = false,
};

const LATEX_SYMBOLS = [_]LatexSymbolEntry{
    // Arrows
    .{ .cmd = "rightarrow", .repl = "→", .is_relation = true },
    .{ .cmd = "to", .repl = "→", .is_relation = true },
    .{ .cmd = "longrightarrow", .repl = "→", .is_relation = true },
    .{ .cmd = "leftarrow", .repl = "←", .is_relation = true },
    .{ .cmd = "gets", .repl = "←", .is_relation = true },
    .{ .cmd = "longleftarrow", .repl = "←", .is_relation = true },
    .{ .cmd = "leftrightarrow", .repl = "↔", .is_relation = true },
    .{ .cmd = "longleftrightarrow", .repl = "↔", .is_relation = true },
    .{ .cmd = "Rightarrow", .repl = "⇒", .is_relation = true },
    .{ .cmd = "implies", .repl = "⇒", .is_relation = true },
    .{ .cmd = "Longrightarrow", .repl = "⇒", .is_relation = true },
    .{ .cmd = "Leftarrow", .repl = "⇐", .is_relation = true },
    .{ .cmd = "impliedby", .repl = "⇐", .is_relation = true },
    .{ .cmd = "Longleftarrow", .repl = "⇐", .is_relation = true },
    .{ .cmd = "Leftrightarrow", .repl = "⇔", .is_relation = true },
    .{ .cmd = "iff", .repl = "⇔", .is_relation = true },
    .{ .cmd = "Longleftrightarrow", .repl = "⇔", .is_relation = true },
    .{ .cmd = "mapsto", .repl = "↦", .is_relation = true },
    .{ .cmd = "longmapsto", .repl = "↦", .is_relation = true },
    .{ .cmd = "uparrow", .repl = "↑" },
    .{ .cmd = "downarrow", .repl = "↓" },
    .{ .cmd = "updownarrow", .repl = "↕" },
    .{ .cmd = "hookrightarrow", .repl = "↪", .is_relation = true },
    .{ .cmd = "hookleftarrow", .repl = "↩", .is_relation = true },
    .{ .cmd = "nearrow", .repl = "↗" },
    .{ .cmd = "searrow", .repl = "↘" },
    .{ .cmd = "swarrow", .repl = "↙" },
    .{ .cmd = "nwarrow", .repl = "↖" },
    // Binary operators & relations
    .{ .cmd = "times", .repl = "×", .is_relation = true },
    .{ .cmd = "cdot", .repl = "·", .is_relation = true },
    .{ .cmd = "bullet", .repl = "•" },
    .{ .cmd = "div", .repl = "÷", .is_relation = true },
    .{ .cmd = "pm", .repl = "±" },
    .{ .cmd = "mp", .repl = "∓" },
    .{ .cmd = "le", .repl = "≤", .is_relation = true },
    .{ .cmd = "leq", .repl = "≤", .is_relation = true },
    .{ .cmd = "leqslant", .repl = "≤", .is_relation = true },
    .{ .cmd = "ge", .repl = "≥", .is_relation = true },
    .{ .cmd = "geq", .repl = "≥", .is_relation = true },
    .{ .cmd = "geqslant", .repl = "≥", .is_relation = true },
    .{ .cmd = "ne", .repl = "≠", .is_relation = true },
    .{ .cmd = "neq", .repl = "≠", .is_relation = true },
    .{ .cmd = "approx", .repl = "≈", .is_relation = true },
    .{ .cmd = "thickapprox", .repl = "≈", .is_relation = true },
    .{ .cmd = "equiv", .repl = "≡", .is_relation = true },
    .{ .cmd = "sim", .repl = "∼", .is_relation = true },
    .{ .cmd = "thicksim", .repl = "∼", .is_relation = true },
    .{ .cmd = "simeq", .repl = "≃", .is_relation = true },
    .{ .cmd = "cong", .repl = "≅", .is_relation = true },
    .{ .cmd = "propto", .repl = "∝", .is_relation = true },
    .{ .cmd = "ll", .repl = "≪", .is_relation = true },
    .{ .cmd = "gg", .repl = "≫", .is_relation = true },
    .{ .cmd = "prec", .repl = "≺", .is_relation = true },
    .{ .cmd = "succ", .repl = "≻", .is_relation = true },
    .{ .cmd = "preceq", .repl = "≼", .is_relation = true },
    .{ .cmd = "succeq", .repl = "≽", .is_relation = true },
    .{ .cmd = "oplus", .repl = "⊕", .is_relation = true },
    .{ .cmd = "ominus", .repl = "⊖", .is_relation = true },
    .{ .cmd = "otimes", .repl = "⊗", .is_relation = true },
    .{ .cmd = "odot", .repl = "⊙", .is_relation = true },
    .{ .cmd = "land", .repl = "∧", .is_relation = true },
    .{ .cmd = "wedge", .repl = "∧", .is_relation = true },
    .{ .cmd = "lor", .repl = "∨", .is_relation = true },
    .{ .cmd = "vee", .repl = "∨", .is_relation = true },
    .{ .cmd = "neg", .repl = "¬" },
    .{ .cmd = "lnot", .repl = "¬" },
    .{ .cmd = "forall", .repl = "∀" },
    .{ .cmd = "exists", .repl = "∃" },
    .{ .cmd = "nexists", .repl = "∄" },
    .{ .cmd = "in", .repl = "∈", .is_relation = true },
    .{ .cmd = "notin", .repl = "∉", .is_relation = true },
    .{ .cmd = "ni", .repl = "∋", .is_relation = true },
    .{ .cmd = "subset", .repl = "⊂", .is_relation = true },
    .{ .cmd = "supset", .repl = "⊃", .is_relation = true },
    .{ .cmd = "subseteq", .repl = "⊆", .is_relation = true },
    .{ .cmd = "supseteq", .repl = "⊇", .is_relation = true },
    .{ .cmd = "cup", .repl = "∪", .is_relation = true },
    .{ .cmd = "cap", .repl = "∩", .is_relation = true },
    .{ .cmd = "setminus", .repl = "∖", .is_relation = true },
    .{ .cmd = "emptyset", .repl = "∅" },
    .{ .cmd = "varnothing", .repl = "∅" },
    .{ .cmd = "infty", .repl = "∞" },
    .{ .cmd = "partial", .repl = "∂" },
    .{ .cmd = "nabla", .repl = "∇" },
    .{ .cmd = "sum", .repl = "∑" },
    .{ .cmd = "prod", .repl = "∏" },
    .{ .cmd = "int", .repl = "∫" },
    .{ .cmd = "oint", .repl = "∮" },
    .{ .cmd = "mid", .repl = "∣", .is_relation = true },
    .{ .cmd = "parallel", .repl = "∥", .is_relation = true },
    .{ .cmd = "perp", .repl = "⊥", .is_relation = true },
    .{ .cmd = "angle", .repl = "∠" },
    .{ .cmd = "dots", .repl = "…" },
    .{ .cmd = "ldots", .repl = "…" },
    .{ .cmd = "cdots", .repl = "⋯" },
    .{ .cmd = "lceil", .repl = "⌈" },
    .{ .cmd = "rceil", .repl = "⌉" },
    .{ .cmd = "lfloor", .repl = "⌊" },
    .{ .cmd = "rfloor", .repl = "⌋" },
    .{ .cmd = "langle", .repl = "⟨" },
    .{ .cmd = "rangle", .repl = "⟩" },
    .{ .cmd = "circ", .repl = "∘" },
    .{ .cmd = "degree", .repl = "°" },
    .{ .cmd = "star", .repl = "⋆" },
    .{ .cmd = "ast", .repl = "∗" },
    .{ .cmd = "checkmark", .repl = "✓" },
    .{ .cmd = "dagger", .repl = "†" },
    .{ .cmd = "ddagger", .repl = "‡" },
    // Named math functions
    .{ .cmd = "log", .repl = "log" },
    .{ .cmd = "ln", .repl = "ln" },
    .{ .cmd = "lg", .repl = "lg" },
    .{ .cmd = "exp", .repl = "exp" },
    .{ .cmd = "sin", .repl = "sin" },
    .{ .cmd = "cos", .repl = "cos" },
    .{ .cmd = "tan", .repl = "tan" },
    .{ .cmd = "sec", .repl = "sec" },
    .{ .cmd = "csc", .repl = "csc" },
    .{ .cmd = "cot", .repl = "cot" },
    .{ .cmd = "arcsin", .repl = "arcsin" },
    .{ .cmd = "arccos", .repl = "arccos" },
    .{ .cmd = "arctan", .repl = "arctan" },
    .{ .cmd = "sinh", .repl = "sinh" },
    .{ .cmd = "cosh", .repl = "cosh" },
    .{ .cmd = "tanh", .repl = "tanh" },
    .{ .cmd = "min", .repl = "min" },
    .{ .cmd = "max", .repl = "max" },
    .{ .cmd = "sup", .repl = "sup" },
    .{ .cmd = "inf", .repl = "inf" },
    .{ .cmd = "lim", .repl = "lim" },
    .{ .cmd = "det", .repl = "det" },
    .{ .cmd = "dim", .repl = "dim" },
    .{ .cmd = "ker", .repl = "ker" },
    .{ .cmd = "deg", .repl = "deg" },
    .{ .cmd = "gcd", .repl = "gcd" },
    .{ .cmd = "lcm", .repl = "lcm" },
    .{ .cmd = "mod", .repl = "mod" },
    .{ .cmd = "bmod", .repl = " mod " },
    .{ .cmd = "pmod", .repl = " mod " },
    // Lowercase Greek
    .{ .cmd = "alpha", .repl = "α" },
    .{ .cmd = "beta", .repl = "β" },
    .{ .cmd = "gamma", .repl = "γ" },
    .{ .cmd = "delta", .repl = "δ" },
    .{ .cmd = "epsilon", .repl = "ε" },
    .{ .cmd = "varepsilon", .repl = "ε" },
    .{ .cmd = "zeta", .repl = "ζ" },
    .{ .cmd = "eta", .repl = "η" },
    .{ .cmd = "theta", .repl = "θ" },
    .{ .cmd = "vartheta", .repl = "ϑ" },
    .{ .cmd = "iota", .repl = "ι" },
    .{ .cmd = "kappa", .repl = "κ" },
    .{ .cmd = "lambda", .repl = "λ" },
    .{ .cmd = "mu", .repl = "μ" },
    .{ .cmd = "nu", .repl = "ν" },
    .{ .cmd = "xi", .repl = "ξ" },
    .{ .cmd = "pi", .repl = "π" },
    .{ .cmd = "varpi", .repl = "ϖ" },
    .{ .cmd = "rho", .repl = "ρ" },
    .{ .cmd = "varrho", .repl = "ϱ" },
    .{ .cmd = "sigma", .repl = "σ" },
    .{ .cmd = "varsigma", .repl = "ς" },
    .{ .cmd = "tau", .repl = "τ" },
    .{ .cmd = "upsilon", .repl = "υ" },
    .{ .cmd = "phi", .repl = "φ" },
    .{ .cmd = "varphi", .repl = "ϕ" },
    .{ .cmd = "chi", .repl = "χ" },
    .{ .cmd = "psi", .repl = "ψ" },
    .{ .cmd = "omega", .repl = "ω" },
    // Uppercase Greek
    .{ .cmd = "Gamma", .repl = "Γ" },
    .{ .cmd = "Delta", .repl = "Δ" },
    .{ .cmd = "Theta", .repl = "Θ" },
    .{ .cmd = "Lambda", .repl = "Λ" },
    .{ .cmd = "Xi", .repl = "Ξ" },
    .{ .cmd = "Pi", .repl = "Π" },
    .{ .cmd = "Sigma", .repl = "Σ" },
    .{ .cmd = "Upsilon", .repl = "Υ" },
    .{ .cmd = "Phi", .repl = "Φ" },
    .{ .cmd = "Psi", .repl = "Ψ" },
    .{ .cmd = "Omega", .repl = "Ω" },
    // Spacing
    .{ .cmd = "quad", .repl = "  " },
    .{ .cmd = "qquad", .repl = "    " },
    .{ .cmd = "enspace", .repl = " " },
    .{ .cmd = "thinspace", .repl = " " },
    .{ .cmd = "colon", .repl = ":" },
};

/// Converts inline/display LaTeX math (`\rightarrow`, `O(\log L)`, `2^8`, `x_0`, `\frac{a}{b}`, etc.)
/// into clean UTF-8 Unicode math text for Skia rendering.
pub fn formatLatexMath(arena: std.mem.Allocator, raw_math: []const u8) ![]const u8 {
    var out: std.ArrayListUnmanaged(u8) = .empty;
    var i: usize = 0;

    while (i < raw_math.len) {
        const ch = raw_math[i];

        // 1. LaTeX control sequences (`\command` or `\{`, `\,`, etc.)
        if (ch == '\\') {
            if (i + 1 >= raw_math.len) {
                i += 1;
                break;
            }
            const next_ch = raw_math[i + 1];
            if (!std.ascii.isAlphabetic(next_ch)) {
                switch (next_ch) {
                    '{', '}', '_', '%', '&', '#', '$' => try out.append(arena, next_ch),
                    ',', ';', ':', ' ' => try out.append(arena, ' '),
                    '!' => {},
                    '|' => try out.appendSlice(arena, "∥"),
                    '\\' => try out.append(arena, ' '),
                    else => try out.append(arena, next_ch),
                }
                i += 2;
                continue;
            }

            var cmd_end = i + 1;
            while (cmd_end < raw_math.len and std.ascii.isAlphabetic(raw_math[cmd_end])) : (cmd_end += 1) {}
            const cmd = raw_math[i + 1 .. cmd_end];
            i = cmd_end;

            // Sizing modifiers (`\left`, `\right`, `\big`, `\Big`, `\bigg`, `\Bigg`)
            if (std.mem.eql(u8, cmd, "left") or std.mem.eql(u8, cmd, "right") or
                std.mem.eql(u8, cmd, "big") or std.mem.eql(u8, cmd, "Big") or
                std.mem.eql(u8, cmd, "bigg") or std.mem.eql(u8, cmd, "Bigg") or
                std.mem.eql(u8, cmd, "bigl") or std.mem.eql(u8, cmd, "bigr"))
            {
                while (i < raw_math.len and (raw_math[i] == ' ' or raw_math[i] == '\t')) : (i += 1) {}
                if (i < raw_math.len and raw_math[i] == '.') {
                    i += 1;
                }
                continue;
            }

            // Fractions (`\frac{num}{den}`, `\dfrac`, `\tfrac`, `\cfrac`)
            if (std.mem.eql(u8, cmd, "frac") or std.mem.eql(u8, cmd, "dfrac") or
                std.mem.eql(u8, cmd, "tfrac") or std.mem.eql(u8, cmd, "cfrac"))
            {
                if (extractBracedGroup(raw_math, i)) |num_grp| {
                    if (extractBracedGroup(raw_math, num_grp.end_pos)) |den_grp| {
                        const num_str = try formatLatexMath(arena, num_grp.inner);
                        const den_str = try formatLatexMath(arena, den_grp.inner);
                        const wrap_num = std.mem.indexOfAny(u8, num_str, " +-") != null;
                        const wrap_den = std.mem.indexOfAny(u8, den_str, " +-*/") != null;
                        if (wrap_num) try out.append(arena, '(');
                        try out.appendSlice(arena, num_str);
                        if (wrap_num) try out.append(arena, ')');
                        try out.append(arena, '/');
                        if (wrap_den) try out.append(arena, '(');
                        try out.appendSlice(arena, den_str);
                        if (wrap_den) try out.append(arena, ')');
                        i = den_grp.end_pos;
                        continue;
                    }
                }
            }

            // Square / nth root (`\sqrt{x}` or `\sqrt[n]{x}`)
            if (std.mem.eql(u8, cmd, "sqrt")) {
                var root_idx = i;
                while (root_idx < raw_math.len and (raw_math[root_idx] == ' ' or raw_math[root_idx] == '\t')) : (root_idx += 1) {}
                if (root_idx < raw_math.len and raw_math[root_idx] == '[') {
                    if (std.mem.indexOfScalarPos(u8, raw_math, root_idx + 1, ']')) |close_br| {
                        const deg_raw = raw_math[root_idx + 1 .. close_br];
                        for (deg_raw) |dch| {
                            if (mapSuperscriptChar(dch)) |sup| {
                                try out.appendSlice(arena, sup);
                            }
                        }
                        root_idx = close_br + 1;
                    }
                }
                try out.appendSlice(arena, "√");
                if (extractBracedGroup(raw_math, root_idx)) |rad_grp| {
                    const rad_str = try formatLatexMath(arena, rad_grp.inner);
                    const needs_parens = rad_str.len > 2 and std.mem.indexOfAny(u8, rad_str, " +-*/=") != null;
                    if (needs_parens) try out.append(arena, '(');
                    try out.appendSlice(arena, rad_str);
                    if (needs_parens) try out.append(arena, ')');
                    i = rad_grp.end_pos;
                }
                continue;
            }

            // Blackboard bold (`\mathbb{R}`, `\mathbb{Z}`, etc.)
            if (std.mem.eql(u8, cmd, "mathbb")) {
                if (extractBracedGroup(raw_math, i)) |grp| {
                    const inner = std.mem.trim(u8, grp.inner, " \t");
                    const bb = if (std.mem.eql(u8, inner, "R"))
                        "ℝ"
                    else if (std.mem.eql(u8, inner, "N"))
                        "ℕ"
                    else if (std.mem.eql(u8, inner, "Z"))
                        "ℤ"
                    else if (std.mem.eql(u8, inner, "Q"))
                        "ℚ"
                    else if (std.mem.eql(u8, inner, "C"))
                        "ℂ"
                    else if (std.mem.eql(u8, inner, "F"))
                        "𝔽"
                    else if (std.mem.eql(u8, inner, "E"))
                        "𝔼"
                    else if (std.mem.eql(u8, inner, "P"))
                        "ℙ"
                    else
                        inner;
                    try out.appendSlice(arena, bb);
                    i = grp.end_pos;
                    continue;
                }
            }

            // Combining accents (`\hat{x}`, `\bar{x}`, `\overline{x}`, `\tilde{x}`, `\vec{x}`)
            if (std.mem.eql(u8, cmd, "hat") or std.mem.eql(u8, cmd, "bar") or
                std.mem.eql(u8, cmd, "overline") or std.mem.eql(u8, cmd, "tilde") or
                std.mem.eql(u8, cmd, "vec"))
            {
                if (extractBracedGroup(raw_math, i)) |grp| {
                    const inner_fmt = try formatLatexMath(arena, grp.inner);
                    try out.appendSlice(arena, inner_fmt);
                    if (inner_fmt.len == 1) {
                        const comb = if (std.mem.eql(u8, cmd, "hat"))
                            "\u{0302}"
                        else if (std.mem.eql(u8, cmd, "tilde"))
                            "\u{0303}"
                        else if (std.mem.eql(u8, cmd, "vec"))
                            "\u{20D7}"
                        else
                            "\u{0304}";
                        try out.appendSlice(arena, comb);
                    }
                    i = grp.end_pos;
                    continue;
                }
            }

            // Text & font style wrappers (`\text{...}`, `\mathrm{...}`, `\mathbf{...}`, `\mathtt{...}`, etc.)
            if (std.mem.eql(u8, cmd, "text") or std.mem.eql(u8, cmd, "textrm") or
                std.mem.eql(u8, cmd, "textbf") or std.mem.eql(u8, cmd, "textit") or
                std.mem.eql(u8, cmd, "texttt") or std.mem.eql(u8, cmd, "mathrm") or
                std.mem.eql(u8, cmd, "mathbf") or std.mem.eql(u8, cmd, "mathit") or
                std.mem.eql(u8, cmd, "mathsf") or std.mem.eql(u8, cmd, "mathtt") or
                std.mem.eql(u8, cmd, "mathcal") or std.mem.eql(u8, cmd, "mathfrak") or
                std.mem.eql(u8, cmd, "bm") or std.mem.eql(u8, cmd, "boldsymbol") or
                std.mem.eql(u8, cmd, "operatorname") or std.mem.eql(u8, cmd, "underline"))
            {
                if (extractBracedGroup(raw_math, i)) |grp| {
                    if (std.mem.startsWith(u8, cmd, "text")) {
                        try out.appendSlice(arena, grp.inner);
                    } else {
                        const inner_fmt = try formatLatexMath(arena, grp.inner);
                        try out.appendSlice(arena, inner_fmt);
                    }
                    i = grp.end_pos;
                    continue;
                }
            }

            // Lookup in symbol table
            var matched_sym: ?LatexSymbolEntry = null;
            for (LATEX_SYMBOLS) |entry| {
                if (std.mem.eql(u8, cmd, entry.cmd)) {
                    matched_sym = entry;
                    break;
                }
            }
            if (matched_sym) |sym| {
                if (sym.is_relation and out.items.len > 0) {
                    const prev = out.items[out.items.len - 1];
                    if (prev != ' ' and prev != '(' and prev != '[' and prev != '{') {
                        try out.append(arena, ' ');
                    }
                }
                try out.appendSlice(arena, sym.repl);
                if (sym.is_relation and i < raw_math.len) {
                    const next_c = raw_math[i];
                    if (next_c != ' ' and next_c != '\t' and next_c != ')' and next_c != ']' and next_c != '}' and next_c != ',' and next_c != ';' and next_c != '_' and next_c != '^') {
                        try out.append(arena, ' ');
                    }
                }
            } else {
                // Unknown macro: if followed by `{...}`, unwrap group; otherwise emit command name
                if (extractBracedGroup(raw_math, i)) |grp| {
                    const inner_fmt = try formatLatexMath(arena, grp.inner);
                    try out.appendSlice(arena, inner_fmt);
                    i = grp.end_pos;
                } else {
                    try out.appendSlice(arena, cmd);
                }
            }
            continue;
        }

        // 2. Superscripts (`^`) and Subscripts (`_`)
        if (ch == '^' or ch == '_') {
            const is_sup = (ch == '^');
            i += 1;
            while (i < raw_math.len and (raw_math[i] == ' ' or raw_math[i] == '\t')) : (i += 1) {}
            if (i >= raw_math.len) break;

            var target_slice: []const u8 = "";
            if (raw_math[i] == '{') {
                if (extractBracedGroup(raw_math, i)) |grp| {
                    target_slice = try formatLatexMath(arena, grp.inner);
                    i = grp.end_pos;
                }
            } else if (raw_math[i] == '\\') {
                var c_end = i + 1;
                while (c_end < raw_math.len and std.ascii.isAlphabetic(raw_math[c_end])) : (c_end += 1) {}
                target_slice = try formatLatexMath(arena, raw_math[i..c_end]);
                i = c_end;
            } else {
                target_slice = raw_math[i .. i + 1];
                i += 1;
            }

            if (target_slice.len > 0) {
                var all_mappable = true;
                for (target_slice) |tch| {
                    const mapped = if (is_sup) mapSuperscriptChar(tch) else mapSubscriptChar(tch);
                    if (mapped == null) {
                        all_mappable = false;
                        break;
                    }
                }
                if (all_mappable) {
                    for (target_slice) |tch| {
                        const mapped = if (is_sup) mapSuperscriptChar(tch).? else mapSubscriptChar(tch).?;
                        try out.appendSlice(arena, mapped);
                    }
                } else {
                    try out.append(arena, ch);
                    if (target_slice.len > 1 and is_sup) {
                        try out.append(arena, '(');
                        try out.appendSlice(arena, target_slice);
                        try out.append(arena, ')');
                    } else {
                        try out.appendSlice(arena, target_slice);
                    }
                }
            }
            continue;
        }

        // 3. Unwrap bare `{` and `}` grouping braces in math mode
        if (ch == '{' or ch == '}') {
            i += 1;
            continue;
        }

        // 4. Non-breaking tilde `~` in math mode -> space
        if (ch == '~') {
            try out.append(arena, ' ');
            i += 1;
            continue;
        }

        try out.append(arena, ch);
        i += 1;
    }

    return out.items;
}

fn findBacktickRun(text: []const u8, start: usize, tick_len: usize) ?usize {
    var i = start;
    while (i + tick_len <= text.len) {
        if (text[i] == '`') {
            var run: usize = 1;
            while (i + run < text.len and text[i + run] == '`') : (run += 1) {}
            if (run == tick_len) return i;
            i += run;
        } else {
            i += 1;
        }
    }
    return null;
}

const MatchedLink = struct {
    label: []const u8,
    url: []const u8,
    end_pos: usize,
};

fn matchMarkdownLink(text: []const u8, start_bracket: usize) ?MatchedLink {
    if (start_bracket >= text.len or text[start_bracket] != '[') return null;

    // Find matching `]` that is followed by `(`, skipping nested `[...]` and `` `...` ``
    var i: usize = start_bracket + 1;
    var bracket_depth: usize = 1;
    var close_bracket_opt: ?usize = null;

    while (i < text.len) {
        if (text[i] == '`') {
            var tick_len: usize = 1;
            while (i + tick_len < text.len and text[i + tick_len] == '`') : (tick_len += 1) {}
            if (findBacktickRun(text, i + tick_len, tick_len)) |close_tick| {
                i = close_tick + tick_len;
                continue;
            }
            i += tick_len;
            continue;
        }
        if (text[i] == '[') {
            bracket_depth += 1;
        } else if (text[i] == ']') {
            bracket_depth -= 1;
            if (bracket_depth == 0) {
                close_bracket_opt = i;
                break;
            }
        }
        i += 1;
    }

    const close_bracket = close_bracket_opt orelse return null;
    if (close_bracket + 1 >= text.len or text[close_bracket + 1] != '(') return null;

    // Find matching `)` for URL, supporting balanced parentheses inside the URL
    var p = close_bracket + 2;
    var paren_depth: usize = 1;
    var close_paren_opt: ?usize = null;
    while (p < text.len) : (p += 1) {
        if (text[p] == '\n' or text[p] == '\r') return null;
        if (text[p] == '(') {
            paren_depth += 1;
        } else if (text[p] == ')') {
            paren_depth -= 1;
            if (paren_depth == 0) {
                close_paren_opt = p;
                break;
            }
        }
    }

    const close_paren = close_paren_opt orelse return null;
    return .{
        .label = text[start_bracket + 1 .. close_bracket],
        .url = std.mem.trim(u8, text[close_bracket + 2 .. close_paren], " \t"),
        .end_pos = close_paren + 1,
    };
}

fn cleanLinkLabel(arena: std.mem.Allocator, raw_label: []const u8) ![]const u8 {
    var trimmed = std.mem.trim(u8, raw_label, " \t");
    if (trimmed.len >= 2 and trimmed[0] == '`' and trimmed[trimmed.len - 1] == '`') {
        trimmed = trimmed[1 .. trimmed.len - 1];
    }
    if (trimmed.len >= 4 and
        ((std.mem.startsWith(u8, trimmed, "**") and std.mem.endsWith(u8, trimmed, "**")) or
            (std.mem.startsWith(u8, trimmed, "__") and std.mem.endsWith(u8, trimmed, "__"))))
    {
        trimmed = trimmed[2 .. trimmed.len - 2];
    }
    if (std.mem.indexOfScalar(u8, trimmed, '`') == null) return trimmed;

    var out: std.ArrayListUnmanaged(u8) = .empty;
    for (trimmed) |ch| {
        if (ch != '`') try out.append(arena, ch);
    }
    return out.items;
}

/// Finds the closing delimiter `delim` (`***`, `___`, `**`, `__`, `~~`, `*`, `_`) starting at `start`,
/// skipping over inline code spans (`` `...` ``), markdown links (`[...](...)`), and inline math (`$...$`)
/// so characters inside URLs, math, or code spans never prematurely close emphasis.
fn findClosingDelimiter(text: []const u8, start: usize, delim: []const u8) ?usize {
    var i = start;
    while (i + delim.len <= text.len) {
        if (text[i] == '\\' and i + 1 < text.len) {
            if (matchInlineMath(text, i)) |m| {
                i = m.end_pos;
                continue;
            }
            i += 2;
            continue;
        }
        if (text[i] == '`') {
            var tick_len: usize = 1;
            while (i + tick_len < text.len and text[i + tick_len] == '`') : (tick_len += 1) {}
            if (findBacktickRun(text, i + tick_len, tick_len)) |close_tick| {
                i = close_tick + tick_len;
                continue;
            }
            i += tick_len;
            continue;
        }
        if (text[i] == '[') {
            if (matchMarkdownLink(text, i)) |lnk| {
                i = lnk.end_pos;
                continue;
            }
        }
        if (text[i] == '$') {
            if (matchInlineMath(text, i)) |m| {
                i = m.end_pos;
                continue;
            }
        }
        if (std.mem.eql(u8, text[i .. i + delim.len], delim)) {
            if (i > start and (text[i - 1] == ' ' or text[i - 1] == '\t')) {
                i += 1;
                continue;
            }
            // For single `*` or `_`, don't match `**` or `__` as a single closing delimiter
            if (delim.len == 1) {
                if (i + 1 < text.len and text[i + 1] == delim[0]) {
                    i += 2;
                    continue;
                }
                if (delim[0] == '_' and i + 1 < text.len and std.ascii.isAlphanumeric(text[i + 1])) {
                    i += 1;
                    continue;
                }
            } else if (delim.len == 2 and (delim[0] == '*' or delim[0] == '_')) {
                if (delim[0] == '_' and i + 2 < text.len and std.ascii.isAlphanumeric(text[i + 2])) {
                    i += 1;
                    continue;
                }
            }
            return i;
        }
        i += 1;
    }
    return null;
}

fn parseInlineSpansInto(
    arena: std.mem.Allocator,
    text: []const u8,
    default_style: InlineStyle,
    spans: *std.ArrayListUnmanaged(InlineSpan),
) !void {
    var plain_start: usize = 0;
    var i: usize = 0;

    while (i < text.len) {
        // 0. Backslash escapes (`\$`, `\*`, `\_`, etc.) and LaTeX inline math (`\(...\)`, `\[...\]`)
        if (text[i] == '\\' and i + 1 < text.len) {
            if (matchInlineMath(text, i)) |m| {
                if (i > plain_start) {
                    try appendOrCoalesceSpan(arena, spans, .{ .style = default_style, .text = text[plain_start..i] });
                }
                const formatted = try formatLatexMath(arena, m.content);
                if (formatted.len > 0) {
                    try appendOrCoalesceSpan(arena, spans, .{ .style = default_style, .text = formatted });
                }
                i = m.end_pos;
                plain_start = i;
                continue;
            }
            const next_ch = text[i + 1];
            if (next_ch == '$' or next_ch == '*' or next_ch == '_' or next_ch == '~' or next_ch == '`' or next_ch == '\\' or next_ch == '[' or next_ch == ']') {
                if (i > plain_start) {
                    try appendOrCoalesceSpan(arena, spans, .{ .style = default_style, .text = text[plain_start..i] });
                }
                try appendOrCoalesceSpan(arena, spans, .{ .style = default_style, .text = text[i + 1 .. i + 2] });
                i += 2;
                plain_start = i;
                continue;
            }
        }

        // 1. Inline code (`...` or ``...``)
        if (text[i] == '`') {
            var tick_len: usize = 1;
            while (i + tick_len < text.len and text[i + tick_len] == '`') : (tick_len += 1) {}
            if (findBacktickRun(text, i + tick_len, tick_len)) |close_idx| {
                if (i > plain_start) {
                    try appendOrCoalesceSpan(arena, spans, .{ .style = default_style, .text = text[plain_start..i] });
                }
                var code_slice = text[i + tick_len .. close_idx];
                if (tick_len > 1 and code_slice.len >= 2 and code_slice[0] == ' ' and code_slice[code_slice.len - 1] == ' ') {
                    code_slice = code_slice[1 .. code_slice.len - 1];
                }
                try spans.append(arena, .{ .style = .code, .text = code_slice });
                i = close_idx + tick_len;
                plain_start = i;
                continue;
            }
            i += tick_len;
            continue;
        }

        // 1b. Inline LaTeX math (`$...$` or `$$...$$`)
        if (text[i] == '$') {
            if (matchInlineMath(text, i)) |m| {
                if (i > plain_start) {
                    try appendOrCoalesceSpan(arena, spans, .{ .style = default_style, .text = text[plain_start..i] });
                }
                const formatted = try formatLatexMath(arena, m.content);
                if (formatted.len > 0) {
                    try appendOrCoalesceSpan(arena, spans, .{ .style = default_style, .text = formatted });
                }
                i = m.end_pos;
                plain_start = i;
                continue;
            }
        }

        // 2. Link ([label](url))
        if (text[i] == '[') {
            if (matchMarkdownLink(text, i)) |lnk| {
                if (i > plain_start) {
                    try appendOrCoalesceSpan(arena, spans, .{ .style = default_style, .text = text[plain_start..i] });
                }
                const label = try cleanLinkLabel(arena, lnk.label);
                try spans.append(arena, .{
                    .style = .link,
                    .text = if (label.len > 0) label else lnk.url,
                    .link_url = lnk.url,
                });
                i = lnk.end_pos;
                plain_start = i;
                continue;
            }
        }

        // 2b. Bold-Italic (***...*** or ___...___)
        if (i + 2 < text.len and ((text[i] == '*' and text[i + 1] == '*' and text[i + 2] == '*') or (text[i] == '_' and text[i + 1] == '_' and text[i + 2] == '_'))) {
            const is_underscore = (text[i] == '_');
            const word_boundary_ok = !is_underscore or (i == 0 or !std.ascii.isAlphanumeric(text[i - 1]));
            if (word_boundary_ok and i + 3 < text.len and text[i + 3] != ' ' and text[i + 3] != '\t') {
                const delim3 = text[i .. i + 3];
                if (findClosingDelimiter(text, i + 3, delim3)) |close_idx| {
                    if (close_idx > i + 3) {
                        if (i > plain_start) {
                            try appendOrCoalesceSpan(arena, spans, .{ .style = default_style, .text = text[plain_start..i] });
                        }
                        try parseInlineSpansInto(arena, text[i + 3 .. close_idx], .bold, spans);
                        i = close_idx + 3;
                        plain_start = i;
                        continue;
                    }
                }
            }
        }

        // 3. Bold (**...** or __...__) — recursively parses links, math & code inside bold!
        if (i + 1 < text.len and ((text[i] == '*' and text[i + 1] == '*') or (text[i] == '_' and text[i + 1] == '_'))) {
            const is_underscore = (text[i] == '_');
            const word_boundary_ok = !is_underscore or (i == 0 or !std.ascii.isAlphanumeric(text[i - 1]));
            if (word_boundary_ok and i + 2 < text.len and text[i + 2] != ' ' and text[i + 2] != '\t') {
                const delim = text[i .. i + 2];
                if (findClosingDelimiter(text, i + 2, delim)) |close_idx| {
                    if (close_idx > i + 2) {
                        if (i > plain_start) {
                            try appendOrCoalesceSpan(arena, spans, .{ .style = default_style, .text = text[plain_start..i] });
                        }
                        try parseInlineSpansInto(arena, text[i + 2 .. close_idx], .bold, spans);
                        i = close_idx + 2;
                        plain_start = i;
                        continue;
                    }
                }
            }
        }

        // 4. Strikethrough (~~...~~)
        if (i + 1 < text.len and text[i] == '~' and text[i + 1] == '~') {
            if (i + 2 < text.len and text[i + 2] != ' ' and text[i + 2] != '\t') {
                if (findClosingDelimiter(text, i + 2, "~~")) |close_idx| {
                    if (close_idx > i + 2) {
                        if (i > plain_start) {
                            try appendOrCoalesceSpan(arena, spans, .{ .style = default_style, .text = text[plain_start..i] });
                        }
                        try parseInlineSpansInto(arena, text[i + 2 .. close_idx], .strikethrough, spans);
                        i = close_idx + 2;
                        plain_start = i;
                        continue;
                    }
                }
            }
        }

        // 5. Italic (*...* or _..._) — avoids intraword `snake_case` underscores
        if (text[i] == '*' or text[i] == '_') {
            const delim_ch = text[i];
            const word_boundary_ok = (delim_ch != '_') or (i == 0 or !std.ascii.isAlphanumeric(text[i - 1]));
            if (word_boundary_ok and i + 1 < text.len and text[i + 1] != ' ' and text[i + 1] != '\t' and text[i + 1] != delim_ch) {
                if (findClosingDelimiter(text, i + 1, text[i .. i + 1])) |close_idx| {
                    if (close_idx > i + 1) {
                        if (i > plain_start) {
                            try appendOrCoalesceSpan(arena, spans, .{ .style = default_style, .text = text[plain_start..i] });
                        }
                        try parseInlineSpansInto(arena, text[i + 1 .. close_idx], .italic, spans);
                        i = close_idx + 1;
                        plain_start = i;
                        continue;
                    }
                }
            }
        }

        i += 1;
    }

    if (plain_start < text.len) {
        try appendOrCoalesceSpan(arena, spans, .{ .style = default_style, .text = text[plain_start..] });
    }
}

// ============================================================================
// Word-Wrapping Inline Layout Engine
// ============================================================================

fn attachedSuffixWidth(uic: *Context, spans: []const InlineSpan, after_idx: usize, font_body: Font) f32 {
    if (after_idx >= spans.len) return 0.0;
    const next_span = spans[after_idx];
    if (next_span.style == .code or next_span.text.len == 0 or next_span.text[0] == ' ') return 0.0;
    var end: usize = 0;
    while (end < next_span.text.len and next_span.text[end] != ' ') : (end += 1) {}
    if (end == 0 or end > 6) return 0.0;
    return uic.measureTextCached(font_body, next_span.text[0..end]);
}

pub fn wrapInlineSpans(
    uic: *Context,
    spans: []const InlineSpan,
    font_body: Font,
    font_mono: Font,
    max_width: f32,
) []const WrappedLine {
    const safe_max_w = @max(60.0, max_width);
    const space_w = uic.measureTextCached(font_body, " ");

    var lines: std.ArrayListUnmanaged(WrappedLine) = .empty;
    var cur_frags: std.ArrayListUnmanaged(WrappedFragment) = .empty;
    var cursor_x: f32 = 0;

    for (spans, 0..) |span, span_idx| {
        if (span.text.len == 0) continue;

        if (span.style == .code) {
            const code_text_w = uic.measureTextCached(font_mono, span.text);
            const suffix_w = attachedSuffixWidth(uic, spans, span_idx + 1, font_body);
            const inline_left_margin: f32 = if (cursor_x > 0.5) 2.0 else 0.0;
            const inline_pill_w = code_text_w + 9.0 + inline_left_margin + 2.0;

            if (cursor_x > 0 and cursor_x + inline_pill_w + suffix_w > safe_max_w) {
                var carried_prefix: ?WrappedFragment = null;
                if (cur_frags.items.len > 0) {
                    const last_f = cur_frags.items[cur_frags.items.len - 1];
                    if (last_f.style != .code and
                        last_f.x_offset + last_f.width >= cursor_x - 0.1 and
                        last_f.text.len >= 1 and last_f.text.len <= 2 and
                        (last_f.text[0] == '(' or last_f.text[0] == '['))
                    {
                        carried_prefix = cur_frags.pop();
                        cursor_x = last_f.x_offset;
                    }
                }
                if (cur_frags.items.len > 0) {
                    lines.append(uic.arena, .{
                        .fragments = cur_frags.toOwnedSlice(uic.arena) catch &.{},
                        .total_width = cursor_x,
                    }) catch {};
                    cur_frags = .empty;
                }
                cursor_x = 0;
                if (carried_prefix) |cp| {
                    cur_frags.append(uic.arena, .{
                        .style = cp.style,
                        .text = cp.text,
                        .link_url = cp.link_url,
                        .x_offset = 0,
                        .width = cp.width,
                    }) catch {};
                    cursor_x = cp.width;
                }
            }

            const left_margin: f32 = if (cursor_x > 0.5) 2.0 else 0.0;
            const pill_w = code_text_w + 9.0 + left_margin + 2.0;

            cur_frags.append(uic.arena, .{
                .style = .code,
                .text = span.text,
                .link_url = "",
                .x_offset = cursor_x,
                .width = pill_w,
            }) catch {};
            cursor_x += pill_w;
            continue;
        }

        // Group consecutive words of this span that fit on the current line into a single slice
        var pos: usize = 0;
        var run_start: ?usize = null;
        var run_end: usize = 0;
        var run_x: f32 = cursor_x;
        var run_w: f32 = 0;

        while (pos < span.text.len) {
            // Preserve leading space if at the start of a span after another inline span
            if (span.text[pos] == ' ') {
                if (run_start == null and cursor_x > 0) {
                    cursor_x += space_w;
                    run_x = cursor_x;
                }
                pos += 1;
                continue;
            }

            var word_end = pos;
            while (word_end < span.text.len and span.text[word_end] != ' ') {
                word_end += 1;
            }
            const has_trailing_space = (word_end < span.text.len and span.text[word_end] == ' ');
            const word_slice = span.text[pos..word_end];

            // If this word is a trailing opening parenthesis/bracket right before a `.code` span,
            // flush the preceding words in `run_start` first so the opening delimiter can wrap with `.code`.
            if (!has_trailing_space and word_end == span.text.len and
                span_idx + 1 < spans.len and spans[span_idx + 1].style == .code and
                word_slice.len >= 1 and word_slice.len <= 2 and
                (word_slice[0] == '(' or word_slice[0] == '[') and
                run_start != null)
            {
                cur_frags.append(uic.arena, .{
                    .style = span.style,
                    .text = span.text[run_start.?..run_end],
                    .link_url = span.link_url,
                    .x_offset = run_x,
                    .width = run_w,
                }) catch {};
                cursor_x = run_x + run_w + space_w;
                run_start = null;
                run_x = cursor_x;
                run_w = 0;
            }

            const candidate_start = run_start orelse pos;
            const candidate_slice = span.text[candidate_start..word_end];
            const bold_pad: f32 = if (span.style == .bold) 0.5 else 0.0;
            const candidate_w = uic.measureTextCached(font_body, candidate_slice) + bold_pad;

            if (run_x + candidate_w > safe_max_w and (run_start != null or cursor_x > 0)) {
                // Flush active run if any
                if (run_start) |rs| {
                    cur_frags.append(uic.arena, .{
                        .style = span.style,
                        .text = span.text[rs..run_end],
                        .link_url = span.link_url,
                        .x_offset = run_x,
                        .width = run_w,
                    }) catch {};
                    cursor_x = run_x + run_w;
                }

                // Flush current line and wrap to next line
                lines.append(uic.arena, .{
                    .fragments = cur_frags.toOwnedSlice(uic.arena) catch &.{},
                    .total_width = cursor_x,
                }) catch {};
                cur_frags = .empty;
                cursor_x = 0;

                // Start new run on the new line with the current word
                run_start = pos;
                run_end = word_end;
                run_x = 0;
                run_w = uic.measureTextCached(font_body, word_slice) + bold_pad;
            } else {
                run_start = candidate_start;
                run_end = word_end;
                run_w = candidate_w;
            }

            // If a single word on a fresh line still exceeds `safe_max_w`, split it at grapheme boundaries
            if (run_start != null and run_start.? == pos and run_x == 0 and run_w > safe_max_w) {
                var sub_start = pos;
                while (sub_start < word_end) {
                    const rem = span.text[sub_start..word_end];
                    const rem_w = uic.measureTextCached(font_body, rem);
                    if (rem_w <= safe_max_w) {
                        run_start = sub_start;
                        run_end = word_end;
                        run_x = 0;
                        run_w = rem_w;
                        break;
                    }
                    var split_pos = root.code_editor_mod.nextGraphemeBoundary(span.text, sub_start);
                    var fit_end = split_pos;
                    var fit_w = uic.measureTextCached(font_body, span.text[sub_start..fit_end]);
                    while (split_pos < word_end) {
                        const next_p = root.code_editor_mod.nextGraphemeBoundary(span.text, split_pos);
                        const w = uic.measureTextCached(font_body, span.text[sub_start..next_p]);
                        if (w > safe_max_w) break;
                        fit_end = next_p;
                        fit_w = w;
                        split_pos = next_p;
                    }
                    cur_frags.append(uic.arena, .{
                        .style = span.style,
                        .text = span.text[sub_start..fit_end],
                        .link_url = span.link_url,
                        .x_offset = 0,
                        .width = fit_w,
                    }) catch {};
                    lines.append(uic.arena, .{
                        .fragments = cur_frags.toOwnedSlice(uic.arena) catch &.{},
                        .total_width = fit_w,
                    }) catch {};
                    cur_frags = .empty;
                    cursor_x = 0;
                    sub_start = fit_end;
                }
                if (sub_start >= word_end) {
                    run_start = null;
                }
            }

            pos = word_end;
            if (has_trailing_space) {
                while (pos < span.text.len and span.text[pos] == ' ') {
                    pos += 1;
                }
                if (pos == span.text.len) {
                    // Trailing space(s) at the very end of the span
                    if (run_start) |rs| {
                        cur_frags.append(uic.arena, .{
                            .style = span.style,
                            .text = span.text[rs..run_end],
                            .link_url = span.link_url,
                            .x_offset = run_x,
                            .width = run_w,
                        }) catch {};
                        cursor_x = run_x + run_w + space_w;
                        run_start = null;
                    }
                }
            }
        }

        if (run_start) |rs| {
            cur_frags.append(uic.arena, .{
                .style = span.style,
                .text = span.text[rs..run_end],
                .link_url = span.link_url,
                .x_offset = run_x,
                .width = run_w,
            }) catch {};
            cursor_x = run_x + run_w;
        }
    }

    if (cur_frags.items.len > 0) {
        lines.append(uic.arena, .{
            .fragments = cur_frags.toOwnedSlice(uic.arena) catch &.{},
            .total_width = cursor_x,
        }) catch {};
    }

    return lines.items;
}

pub fn drawWrappedLine(
    uic: *Context,
    wline: WrappedLine,
    base_x: f32,
    row_top: f32,
    line_height: f32,
    default_text_color: u32,
    force_bold: bool,
    font_body: Font,
    font_mono: Font,
    options: MarkdownOptions,
    block_idx: usize,
    line_idx: usize,
    result: *MarkdownResult,
) void {
    const baseline_y = row_top + line_height * 0.72;
    const paint = uic.paint;
    const canvas = uic.canvas;

    for (wline.fragments, 0..) |frag, frag_idx| {
        if (uic.pass == .input and frag.style != .link) continue;
        const fx = base_x + frag.x_offset;

        if (frag.style == .link) {
            const link_rect = Rect.xywh(fx, row_top, frag.width, line_height);
            const link_wid = root.id(uic.fmt("{s}_lnk_{d}_{d}_{d}", .{ options.id_salt, block_idx, line_idx, frag_idx }));
            const clicked = uic.trackInteraction(link_wid, link_rect, link_rect);
            const hovered = (uic.hot_id == link_wid);
            if (hovered) {
                result.hovered_link = frag.link_url;
                uic.setCursor(.pointing_hand);
            }
            if (clicked) {
                result.clicked_link = frag.link_url;
                uic.invalidateWindow();
            }

            if (uic.shouldPaint(link_rect)) {
                const link_color = if (hovered) Color.rgb(165, 180, 252) else uic.theme.accent_hover;
                paint.setStyle(.fill);
                paint.setColor(link_color);
                uic.drawTextCached(font_body, frag.text, fx, baseline_y);

                // Underline
                const underline_y = baseline_y + 2.5;
                paint.setColor( if (hovered) link_color else Color.argb(150, 129, 140, 248));
                canvas.drawRect(Rect.xywh(fx, underline_y, frag.width, 1.2), paint);
            }
            continue;
        }

        const frag_rect = Rect.xywh(fx, row_top, frag.width, line_height);
        if (!uic.shouldPaint(frag_rect)) continue;

        switch (frag.style) {
            .plain => {
                paint.setStyle(.fill);
                paint.setColor(default_text_color);
                uic.drawTextCached(font_body, frag.text, fx, baseline_y);
                if (force_bold) {
                    uic.drawTextCached(font_body, frag.text, fx + 0.45, baseline_y);
                }
            },
            .bold => {
                paint.setStyle(.fill);
                paint.setColor(Color.white);
                uic.drawTextCached(font_body, frag.text, fx, baseline_y);
                // Crisp synthetic subpixel bold pass
                uic.drawTextCached(font_body, frag.text, fx + 0.45, baseline_y);
            },
            .italic => {
                paint.setStyle(.fill);
                paint.setColor(Color.rgb(199, 210, 254));
                uic.drawTextCached(font_body, frag.text, fx, baseline_y);
            },
            .code => {
                const left_margin: f32 = if (frag.x_offset > 0.5) 2.0 else 0.0;
                const right_margin: f32 = 2.0;
                const pill_r = Rect.xywh(
                    fx + left_margin,
                    row_top + 2.0,
                    @max(8.0, frag.width - left_margin - right_margin),
                    line_height - 4.0,
                );
                paint.setStyle(.fill);
                paint.setColor(Color.rgb(30, 41, 59));
                canvas.drawRoundRect(pill_r, 4.5, 4.5, paint);

                paint.setStyle(.stroke);
                paint.setStrokeWidth(1.0);
                paint.setColor(Color.argb(95, 100, 116, 139));
                canvas.drawRoundRect(pill_r, 4.5, 4.5, paint);

                paint.setStyle(.fill);
                paint.setColor(Color.rgb(125, 211, 252));
                uic.drawTextCached(font_mono, frag.text, fx + left_margin + 4.5, baseline_y - 0.5);
            },
            .strikethrough => {
                paint.setStyle(.fill);
                paint.setColor(uic.theme.text_muted);
                uic.drawTextCached(font_body, frag.text, fx, baseline_y);
                const strike_y = baseline_y - 4.5;
                canvas.drawRect(Rect.xywh(fx, strike_y, frag.width, 1.2), paint);
            },
            .link => unreachable,
        }
    }
}

// ============================================================================
// Block Renderers
// ============================================================================

fn renderHeading(
    uic: *Context,
    h: anytype,
    font_h1: Font,
    font_h2: Font,
    font_h3: Font,
    font_mono: Font,
    options: MarkdownOptions,
    block_idx: usize,
    result: *MarkdownResult,
) void {
    const level = h.level;
    const text = h.text;
    const row_h: f32 = switch (level) {
        1 => 34.0,
        2 => 30.0,
        3 => 25.0,
        else => 23.0,
    };
    const font = switch (level) {
        1 => font_h1,
        2 => font_h2,
        else => font_h3,
    };
    const left_inset: f32 = switch (level) {
        1 => 12.0,
        2 => 10.0,
        else => 0.0,
    };
    const avail_w = @max(60.0, uic.availableWidth() - left_inset);
    const width_q: i32 = @intFromFloat(@round(avail_w * 4.0));

    if (h.cached_width_q != width_q or h.cached_height <= 0.0) {
        const spans = parseInlineSpans(uic.arena, text) catch &[_]InlineSpan{.{ .style = .plain, .text = text }};
        const wrapped = wrapInlineSpans(uic, spans, font, font_mono, avail_w);
        const line_count = @max(wrapped.len, 1);
        const extra_bottom: f32 = if (level <= 2) 4.0 else 0.0;
        h.cached_width_q = width_q;
        h.cached_wrapped = wrapped;
        h.cached_height = @as(f32, @floatFromInt(line_count)) * row_h + extra_bottom;
    }

    const total_h = h.cached_height;
    const wrapped = h.cached_wrapped;

    const r = uic.nextRect(0, total_h);
    if (options.scroll_to_heading.len > 0 and result.target_scroll_y == null) {
        if (headingMatchesSlug(text, options.scroll_to_heading)) {
            result.target_scroll_y = uic.scrollOffsetForRectTop(r.top);
        }
    }
    if (!uic.isRectInViewport(r)) return;
    if (uic.pass == .paint and !uic.shouldPaint(r)) return;

    const paint = uic.paint;
    const canvas = uic.canvas;

    if (uic.shouldPaint(r)) {
        // Left accent bar for H1 and H2
        if (level == 1) {
            paint.setStyle(.fill);
            paint.setColor(uic.theme.accent);
            canvas.drawRoundRect(Rect.xywh(r.left, r.top + 5.0, 4.0, @max(12.0, total_h - 12.0)), 2.0, 2.0, paint);
        } else if (level == 2) {
            paint.setStyle(.fill);
            paint.setColor(uic.theme.accent_hover);
            canvas.drawRoundRect(Rect.xywh(r.left, r.top + 6.0, 3.0, @max(10.0, total_h - 13.0)), 1.5, 1.5, paint);
        }
    }

    const fg = if (level <= 2) uic.theme.text_primary else Color.rgb(226, 232, 240);
    for (wrapped, 0..) |wline, line_idx| {
        const line_top = r.top + @as(f32, @floatFromInt(line_idx)) * row_h;
        drawWrappedLine(
            uic,
            wline,
            r.left + left_inset,
            line_top,
            row_h,
            fg,
            level <= 2,
            font,
            font_mono,
            options,
            block_idx,
            line_idx,
            result,
        );
    }

    // Subtle bottom divider rule for H1 and H2
    if (level <= 2 and uic.shouldPaint(r)) {
        paint.setStyle(.fill);
        paint.setColor(uic.theme.border_subtle);
        canvas.drawRect(Rect.xywh(r.left, r.bottom - 1.0, r.right - r.left, 1.0), paint);
    }
}

/// Fast zero-allocation line count estimator for off-screen blocks.
/// Returns `1` in O(1) when `text.len` cannot wrap within `avail_w`, or counts visible characters
/// (excluding Markdown link URLs and delimiter characters) for longer off-screen paragraphs.
fn estimateWrappedLineCount(text: []const u8, avail_w: f32) usize {
    if (text.len == 0) return 0;
    const safe_w = @max(60.0, avail_w);
    if (@as(f32, @floatFromInt(text.len)) * 8.5 + 16.0 <= safe_w) return 1;

    var vis_chars: usize = 0;
    var i: usize = 0;
    while (i < text.len) {
        if (text[i] == ']' and i + 1 < text.len and text[i + 1] == '(') {
            if (std.mem.indexOfScalarPos(u8, text, i + 2, ')')) |close_paren| {
                i = close_paren + 1;
                continue;
            }
        }
        if (text[i] != '*' and text[i] != '`' and text[i] != '~' and text[i] != '[' and text[i] != ']') {
            vis_chars += 1;
        }
        i += 1;
    }
    const chars_per_line = @max(8.0, @floor(safe_w / 7.5));
    const lines_f = @ceil(@as(f32, @floatFromInt(@max(vis_chars, 1))) / chars_per_line);
    return @max(1, @as(usize, @intFromFloat(lines_f)));
}

fn isBlockNearViewport(uic: *const Context, est_height: f32) bool {
    const vp = uic.activeViewportY();
    const cur_y = uic.nextCursorY();
    const margin: f32 = 240.0;
    return (cur_y + est_height >= vp.top - margin) and (cur_y <= vp.bottom + margin);
}

fn renderParagraph(
    uic: *Context,
    p: anytype,
    font_body: Font,
    font_mono: Font,
    options: MarkdownOptions,
    block_idx: usize,
    result: *MarkdownResult,
) void {
    const text = p.text;
    const avail_w = uic.availableWidth();
    const width_q: i32 = @intFromFloat(@round(avail_w * 4.0));

    if (p.cached_width_q == width_q and p.cached_height > 0.0) {
        if (p.cached_wrapped.len == 0) {
            _ = uic.nextRect(0, p.cached_height);
            return;
        }
        const r = uic.nextRect(0, p.cached_height);
        if (!uic.isRectInViewport(r)) return;
        if (uic.pass == .paint and !uic.shouldPaint(r)) return;
        for (p.cached_wrapped, 0..) |wline, line_idx| {
            const row_top = r.top + @as(f32, @floatFromInt(line_idx)) * options.line_height;
            drawWrappedLine(
                uic,
                wline,
                r.left,
                row_top,
                options.line_height,
                Color.rgb(226, 232, 240),
                false,
                font_body,
                font_mono,
                options,
                block_idx,
                line_idx,
                result,
            );
        }
        return;
    }

    const est_lines = estimateWrappedLineCount(text, avail_w);
    if (est_lines == 0) return;
    const est_h = @as(f32, @floatFromInt(est_lines)) * options.line_height;
    if (!isBlockNearViewport(uic, est_h)) {
        p.cached_width_q = width_q;
        p.cached_wrapped = &.{};
        p.cached_height = est_h;
        _ = uic.nextRect(0, est_h);
        return;
    }

    const spans = parseInlineSpans(uic.arena, text) catch return;
    const wrapped = wrapInlineSpans(uic, spans, font_body, font_mono, avail_w);
    if (wrapped.len == 0) return;

    const total_h = @as(f32, @floatFromInt(wrapped.len)) * options.line_height;
    p.cached_width_q = width_q;
    p.cached_wrapped = wrapped;
    p.cached_height = total_h;

    const r = uic.nextRect(0, total_h);
    if (!uic.isRectInViewport(r)) return;
    if (uic.pass == .paint and !uic.shouldPaint(r)) return;

    for (wrapped, 0..) |wline, line_idx| {
        const row_top = r.top + @as(f32, @floatFromInt(line_idx)) * options.line_height;
        drawWrappedLine(
            uic,
            wline,
            r.left,
            row_top,
            options.line_height,
            Color.rgb(226, 232, 240),
            false,
            font_body,
            font_mono,
            options,
            block_idx,
            line_idx,
            result,
        );
    }
}

fn renderBlockquote(
    uic: *Context,
    bq: anytype,
    font_body: Font,
    font_mono: Font,
    options: MarkdownOptions,
    block_idx: usize,
    result: *MarkdownResult,
) void {
    const callout = bq.callout;
    const lines = bq.lines;
    const avail_w = uic.availableWidth();
    const inner_pad_x: f32 = 16.0;
    const inner_pad_y: f32 = 10.0;
    const header_h: f32 = if (callout != null) 24.0 else 0.0;
    const text_avail_w = avail_w - inner_pad_x * 2.0;
    const width_q: i32 = @intFromFloat(@round(avail_w * 4.0));

    if (bq.cached_width_q != width_q or bq.cached_height <= 0.0) {
        var est_lines: usize = 0;
        for (lines) |line| {
            if (line.len == 0) {
                est_lines += 1;
            } else {
                est_lines += @max(estimateWrappedLineCount(line, text_avail_w), 1);
            }
        }
        const est_h = inner_pad_y * 2.0 + header_h + @as(f32, @floatFromInt(@max(est_lines, 1))) * options.line_height;
        if (!isBlockNearViewport(uic, est_h)) {
            bq.cached_width_q = width_q;
            bq.cached_wrapped = &.{};
            bq.cached_height = est_h;
            _ = uic.nextRect(0, est_h);
            return;
        }

        var all_wrapped: std.ArrayListUnmanaged(WrappedLine) = .empty;
        for (lines) |line| {
            if (line.len == 0) {
                all_wrapped.append(uic.arena, .{
                    .fragments = &.{},
                    .total_width = 0,
                }) catch {};
                continue;
            }
            const spans = parseInlineSpans(uic.arena, line) catch continue;
            const wlines = wrapInlineSpans(uic, spans, font_body, font_mono, text_avail_w);
            if (wlines.len == 0) {
                all_wrapped.append(uic.arena, .{
                    .fragments = &.{},
                    .total_width = 0,
                }) catch {};
            } else {
                all_wrapped.appendSlice(uic.arena, wlines) catch {};
            }
        }
        const wrapped_slice = all_wrapped.items;
        const line_count = @max(wrapped_slice.len, 1);
        const body_h = @as(f32, @floatFromInt(line_count)) * options.line_height;
        bq.cached_width_q = width_q;
        bq.cached_wrapped = wrapped_slice;
        bq.cached_height = inner_pad_y * 2.0 + header_h + body_h;
    }

    if (bq.cached_wrapped.len == 0) {
        _ = uic.nextRect(0, bq.cached_height);
        return;
    }

    const r = uic.nextRect(0, bq.cached_height);
    if (!uic.isRectInViewport(r)) return;
    if (uic.pass == .paint and !uic.shouldPaint(r)) return;
    const paint = uic.paint;
    const canvas = uic.canvas;

    const accent_col = if (callout) |ck| ck.accentColor() else uic.theme.accent;
    const bg_col = if (callout) |ck| ck.bgColor() else Color.argb(35, 30, 41, 59);

    if (uic.shouldPaint(r)) {
        paint.setStyle(.fill);
        paint.setColor(bg_col);
        canvas.drawRoundRect(r, 8, 8, paint);

        // Left vertical accent bar
        paint.setColor(accent_col);
        canvas.drawRoundRect(Rect.xywh(r.left, r.top, 4.0, r.bottom - r.top), 2.0, 2.0, paint);

        if (callout) |ck| {
            // Draw semantic callout badge/title
            paint.setColor(accent_col);
            canvas.drawCircle(r.left + inner_pad_x + 5.0, r.top + inner_pad_y + 9.0, 4.5, paint);
            uic.drawTextCached(font_mono, ck.label(), r.left + inner_pad_x + 15.0, r.top + inner_pad_y + 13.5);
        }
    }

    const text_top = r.top + inner_pad_y + header_h;
    const text_col = if (callout != null) uic.theme.text_primary else uic.theme.text_muted;
    for (bq.cached_wrapped, 0..) |wline, line_idx| {
        if (wline.fragments.len == 0) continue;
        const row_top = text_top + @as(f32, @floatFromInt(line_idx)) * options.line_height;
        drawWrappedLine(
            uic,
            wline,
            r.left + inner_pad_x,
            row_top,
            options.line_height,
            text_col,
            false,
            font_body,
            font_mono,
            options,
            block_idx,
            line_idx,
            result,
        );
    }
}

fn renderListItem(
    uic: *Context,
    li: anytype,
    font_body: Font,
    font_mono: Font,
    options: MarkdownOptions,
    block_idx: usize,
    result: *MarkdownResult,
) void {
    const indent = li.indent;
    const marker = li.marker;
    const text = li.text;
    const avail_w = uic.availableWidth();
    const indent_px: f32 = @as(f32, @floatFromInt(indent)) * 18.0;
    const gutter_w: f32 = 24.0;
    const text_avail_w = @max(60.0, avail_w - indent_px - gutter_w);
    const width_q: i32 = @intFromFloat(@round(avail_w * 4.0));

    if (li.cached_width_q != width_q or li.cached_height <= 0.0) {
        const est_lines = @max(estimateWrappedLineCount(text, text_avail_w), 1);
        const est_h = @as(f32, @floatFromInt(est_lines)) * options.line_height;
        if (!isBlockNearViewport(uic, est_h)) {
            li.cached_width_q = width_q;
            li.cached_wrapped = &.{};
            li.cached_height = est_h;
            _ = uic.nextRect(0, est_h);
            return;
        }

        const spans = parseInlineSpans(uic.arena, text) catch return;
        const wrapped = wrapInlineSpans(uic, spans, font_body, font_mono, text_avail_w);
        const line_count = @max(wrapped.len, 1);
        li.cached_width_q = width_q;
        li.cached_wrapped = wrapped;
        li.cached_height = @as(f32, @floatFromInt(line_count)) * options.line_height;
    }

    if (li.cached_wrapped.len == 0) {
        _ = uic.nextRect(0, li.cached_height);
        return;
    }

    const r = uic.nextRect(0, li.cached_height);
    if (!uic.isRectInViewport(r)) return;
    if (uic.pass == .paint and !uic.shouldPaint(r)) return;
    const marker_x = r.left + indent_px;
    const text_x = marker_x + gutter_w;

    if (uic.shouldPaint(r)) {
        const paint = uic.paint;
        const canvas = uic.canvas;

        switch (marker) {
            .bullet => {
                paint.setStyle(.fill);
                paint.setColor(uic.theme.accent_hover);
                const cy = r.top + options.line_height * 0.52;
                if (indent == 0) {
                    canvas.drawCircle(marker_x + 8.0, cy, 3.2, paint);
                } else {
                    paint.setStyle(.stroke);
                    paint.setStrokeWidth(1.5);
                    canvas.drawCircle(marker_x + 8.0, cy, 2.8, paint);
                }
            },
            .ordered => |num| {
                const num_str = uic.fmt("{d}.", .{num});
                paint.setStyle(.fill);
                paint.setColor(uic.theme.accent_hover);
                const by = r.top + options.line_height * 0.72;
                uic.drawTextCached(font_mono, num_str, marker_x + 2.0, by);
                uic.drawTextCached(font_mono, num_str, marker_x + 2.4, by);
            },
            .task => |checked| {
                const box_size: f32 = 14.0;
                const box_x = marker_x + 3.0;
                const box_y = r.top + (options.line_height - box_size) * 0.5;
                const box_r = Rect.xywh(box_x, box_y, box_size, box_size);

                if (checked) {
                    paint.setStyle(.fill);
                    paint.setColor(uic.theme.success);
                    canvas.drawRoundRect(box_r, 3.5, 3.5, paint);

                    // Vector checkmark inside task checkbox
                    if (PathBuilder.init()) |pb| {
                        defer pb.deinit();
                        pb.moveTo(box_x + 3.2, box_y + 7.2);
                        pb.lineTo(box_x + 6.0, box_y + 10.0);
                        pb.lineTo(box_x + 11.0, box_y + 4.2);
                        if (pb.detach()) |check_path| {
                            defer check_path.deinit();
                            paint.setStyle(.stroke);
                            paint.setStrokeWidth(1.8);
                            paint.setColor(Color.white);
                            canvas.drawPath(check_path, paint);
                        } else |_| {}
                    } else |_| {}
                } else {
                    paint.setStyle(.fill);
                    paint.setColor(uic.theme.control_bg);
                    canvas.drawRoundRect(box_r, 3.5, 3.5, paint);

                    paint.setStyle(.stroke);
                    paint.setStrokeWidth(1.2);
                    paint.setColor(uic.theme.border_subtle);
                    canvas.drawRoundRect(box_r, 3.5, 3.5, paint);
                }
            },
        }
    }

    const default_col = switch (marker) {
        .task => |checked| if (checked) uic.theme.text_muted else Color.rgb(226, 232, 240),
        else => Color.rgb(226, 232, 240),
    };

    for (li.cached_wrapped, 0..) |wline, line_idx| {
        const row_top = r.top + @as(f32, @floatFromInt(line_idx)) * options.line_height;
        drawWrappedLine(
            uic,
            wline,
            text_x,
            row_top,
            options.line_height,
            default_col,
            false,
            font_body,
            font_mono,
            options,
            block_idx,
            line_idx,
            result,
        );
    }
}

fn renderCodeBlock(
    uic: *Context,
    cb: anytype,
    font_mono: Font,
    options: MarkdownOptions,
    block_idx: usize,
) void {
    const language = cb.language;
    const lines = cb.lines;
    const header_h: f32 = 28.0;
    const pad_y: f32 = 8.0;
    const body_h = @as(f32, @floatFromInt(@max(lines.len, 1))) * options.code_line_height + pad_y * 2.0;
    const total_h = header_h + body_h;

    const r = uic.nextRect(0, total_h);
    if (!uic.isRectInViewport(r)) return;
    if (uic.pass == .paint and !uic.shouldPaint(r)) return;

    if (cb.cached_max_line_w < 0.0) {
        var max_w: f32 = 0.0;
        for (lines) |code_line| {
            if (code_line.len > 0) {
                max_w = @max(max_w, uic.measureTextCached(font_mono, code_line));
            }
        }
        cb.cached_max_line_w = max_w;
    }

    const gutter_w: f32 = if (options.show_code_line_numbers) 44.0 else 12.0;
    const code_start_x = r.left + gutter_w + 4.0;
    const code_right_pad: f32 = 12.0;
    const code_viewport_w = @max(1.0, (r.right - code_start_x) - code_right_pad);
    const max_scroll_x = @max(0.0, cb.cached_max_line_w - code_viewport_w);
    const has_h_overflow = (max_scroll_x > 0.5);

    var scroll_x: f32 = 0.0;
    var h_thumb_wid: root.WidgetId = 0;
    var h_track_left: f32 = 0.0;
    var h_track_y: f32 = 0.0;
    var h_track_w: f32 = 0.0;
    const h_track_h: f32 = 4.5;
    var thumb_x: f32 = 0.0;
    var thumb_w: f32 = 0.0;

    if (has_h_overflow) {
        const scroll_id_str = uic.fmt("{s}_cb_scroll_{d}", .{ options.id_salt, block_idx });
        const scroll_wid = root.id(scroll_id_str);
        const scroll_state: *CodeBlockScrollState = if (uic.platform_ctx != null)
            uic.useState(CodeBlockScrollState, scroll_id_str, .{})
        else
            &uic.fallback_code_block_scroll_state;

        h_track_y = r.bottom - h_track_h - 3.0;
        h_track_left = code_start_x;
        const h_track_right = @max(h_track_left + 16.0, r.right - 8.0);
        h_track_w = @max(16.0, h_track_right - h_track_left);

        const visible_ratio_x = std.math.clamp(code_viewport_w / @max(1.0, cb.cached_max_line_w), 0.1, 1.0);
        thumb_w = @max(24.0, h_track_w * visible_ratio_x);
        const scrollable_track_w = @max(1.0, h_track_w - thumb_w);

        h_thumb_wid = scroll_wid ^ 0x4342_4853;
        const h_thumb_hit_rect = Rect.xywh(h_track_left, h_track_y - 5.0, h_track_w, h_track_h + 8.0);

        if (uic.pass == .input) {
            const clamped_sx = std.math.clamp(scroll_state.scroll_x, 0.0, max_scroll_x);
            if (clamped_sx != scroll_state.scroll_x) {
                scroll_state.scroll_x = clamped_sx;
                uic.markDirty(r);
            }

            if (uic.isHovered(r)) {
                const eff_dx: f32 = if (uic.scroll_dx != 0.0)
                    root.snapScrollAxis(uic.scroll_dx, uic.scroll_dy).dx
                else if (uic.mouse_shift and uic.scroll_dy != 0.0)
                    uic.scroll_dy
                else
                    0.0;
                if (eff_dx != 0.0) {
                    const next_sx = std.math.clamp(scroll_state.scroll_x - eff_dx, 0.0, max_scroll_x);
                    if (next_sx != scroll_state.scroll_x) {
                        scroll_state.scroll_x = next_sx;
                        uic.markDirty(r);
                    }
                }
            }

            const cur_norm = if (max_scroll_x > 0.0) std.math.clamp(scroll_state.scroll_x / max_scroll_x, 0.0, 1.0) else 0.0;
            const cur_thumb_x = h_track_left + cur_norm * scrollable_track_w;
            const hovered_h = uic.isHovered(h_thumb_hit_rect);
            if (hovered_h) {
                uic.hot_id = h_thumb_wid;
                if (uic.mouse_pressed) {
                    uic.active_id = h_thumb_wid;
                    if (uic.mouse_x >= cur_thumb_x and uic.mouse_x <= cur_thumb_x + thumb_w) {
                        scroll_state.drag_grab_offset_x = uic.mouse_x - cur_thumb_x;
                    } else {
                        scroll_state.drag_grab_offset_x = thumb_w * 0.5;
                    }
                }
            }

            const hover_changed = (hovered_h and uic.prev_hot_id != h_thumb_wid) or (!hovered_h and uic.prev_hot_id == h_thumb_wid);
            const active_changed = (uic.active_id == h_thumb_wid and uic.mouse_pressed) or
                (uic.prev_active_id == h_thumb_wid and uic.mouse_released);
            if (hover_changed or active_changed) {
                uic.markDirty(h_thumb_hit_rect);
            }

            if (uic.active_id == h_thumb_wid and uic.mouse_down) {
                const target_thumb_left = uic.mouse_x - scroll_state.drag_grab_offset_x;
                const drag_norm = std.math.clamp((target_thumb_left - h_track_left) / scrollable_track_w, 0.0, 1.0);
                const new_sx = drag_norm * max_scroll_x;
                if (new_sx != scroll_state.scroll_x) {
                    scroll_state.scroll_x = new_sx;
                    uic.markDirty(r);
                }
            }
        }

        scroll_x = std.math.clamp(scroll_state.scroll_x, 0.0, max_scroll_x);
        const scroll_norm_x = if (max_scroll_x > 0.0) std.math.clamp(scroll_x / max_scroll_x, 0.0, 1.0) else 0.0;
        thumb_x = h_track_left + scroll_norm_x * scrollable_track_w;
    }

    if (!uic.shouldPaint(r)) return;

    const paint = uic.paint;
    const canvas = uic.canvas;

    // 1. Code block card container
    paint.setStyle(.fill);
    paint.setColor(Color.rgb(13, 18, 28));
    canvas.drawRoundRect(r, 8, 8, paint);

    // 2. Top header bar
    const header_r = Rect.xywh(r.left, r.top, r.right - r.left, header_h);
    paint.setColor(Color.rgb(22, 29, 44));
    canvas.drawRoundRect(header_r, 8, 8, paint);
    // Square off bottom corners of header
    canvas.drawRect(Rect.xywh(r.left, r.top + header_h - 8, r.right - r.left, 8), paint);

    // Header separator line
    paint.setColor(uic.theme.border_subtle);
    canvas.drawRect(Rect.xywh(r.left, r.top + header_h, r.right - r.left, 1.0), paint);

    // Language pill + line count in header
    const lang_display = if (language.len > 0) language else "text";
    paint.setColor(uic.theme.accent_hover);
    canvas.drawCircle(r.left + 14.0, r.top + 14.0, 3.5, paint);
    paint.setColor(uic.theme.text_primary);
    uic.drawTextCached(font_mono, lang_display, r.left + 24.0, r.top + 18.5);

    const lines_badge = uic.fmt("{d} lines", .{lines.len});
    const badge_w = uic.measureTextCached(font_mono, lines_badge);
    paint.setColor(uic.theme.text_muted);
    uic.drawTextCached(font_mono, lines_badge, r.right - badge_w - 12.0, r.top + 18.5);

    // 3. Code lines with optional gutter numbers & syntax highlighting (virtualized to visible viewport rows)
    if (options.show_code_line_numbers) {
        paint.setColor(Color.argb(45, 100, 116, 139));
        canvas.drawRect(Rect.xywh(r.left + gutter_w - 6.0, r.top + header_h + 1.0, 1.0, body_h - 1.0), paint);
    }

    const vp = uic.activeViewportY();
    const lines_base_y = r.top + header_h + pad_y;
    const start_idx: usize = if (vp.top > lines_base_y)
        @min(lines.len, @as(usize, @intFromFloat(@floor((vp.top - lines_base_y) / options.code_line_height))))
    else
        0;
    const end_idx: usize = if (vp.bottom > lines_base_y)
        @min(lines.len, @as(usize, @intFromFloat(@ceil((vp.bottom - lines_base_y) / options.code_line_height))) + 1)
    else
        0;

    if (options.show_code_line_numbers) {
        paint.setStyle(.fill);
        paint.setColor(Color.rgb(84, 96, 118));
        for (start_idx..end_idx) |line_idx| {
            const line_top = lines_base_y + @as(f32, @floatFromInt(line_idx)) * options.code_line_height;
            const baseline_y = line_top + options.code_line_height * 0.74;
            const num_str = uic.fmt("{d:>2}", .{line_idx + 1});
            uic.drawTextCached(font_mono, num_str, r.left + 12.0, baseline_y);
        }
    }

    const code_lang: root.CodeLanguage = if (options.syntax_highlight_code)
        (if (language.len > 0) root.CodeLanguage.fromFence(language) else inferUntaggedCodeLanguage(lines))
    else
        .plain;

    const code_clip_left = if (options.show_code_line_numbers) r.left + gutter_w - 5.0 else r.left + 2.0;
    const code_clip_r = Rect.ltrb(
        code_clip_left,
        r.top + header_h + 1.0,
        @max(code_clip_left + 1.0, r.right - 2.0),
        r.bottom - 2.0,
    );
    const code_save = canvas.save();
    canvas.clipRect(code_clip_r, .intersect, false);
    for (lines[start_idx..end_idx], start_idx..) |code_line, line_idx| {
        const line_top = lines_base_y + @as(f32, @floatFromInt(line_idx)) * options.code_line_height;
        const baseline_y = line_top + options.code_line_height * 0.74;
        const code_x = code_start_x - scroll_x;
        if (options.syntax_highlight_code and code_lang != .plain) {
            root.drawSyntaxHighlightedLine(uic, font_mono, code_line, code_x, baseline_y, code_lang);
        } else {
            paint.setStyle(.fill);
            paint.setColor(Color.rgb(226, 232, 240));
            uic.drawTextCached(font_mono, code_line, code_x, baseline_y);
        }
    }
    canvas.restoreToCount(code_save);

    // 3b. Horizontal scrollbar indicator & interactive thumb when code lines overflow horizontally
    if (has_h_overflow) {
        const h_track_rect = Rect.xywh(h_track_left, h_track_y, h_track_w, h_track_h);
        paint.setStyle(.fill);
        paint.setColor(Color.argb(45, 15, 23, 42));
        canvas.drawRoundRect(h_track_rect, h_track_h * 0.5, h_track_h * 0.5, paint);

        const h_thumb_rect = Rect.xywh(thumb_x, h_track_y, thumb_w, h_track_h);
        const is_h_dragging = (uic.active_id == h_thumb_wid and uic.mouse_down);
        const is_h_hovered = (uic.hot_id == h_thumb_wid);
        const h_thumb_color = if (is_h_dragging)
            uic.theme.accent
        else if (is_h_hovered)
            Color.argb(210, 148, 163, 184)
        else
            Color.argb(130, 100, 116, 139);
        paint.setColor(h_thumb_color);
        canvas.drawRoundRect(h_thumb_rect, h_track_h * 0.5, h_track_h * 0.5, paint);
    }

    // 4. Outer card border
    paint.setStyle(.stroke);
    paint.setStrokeWidth(1.0);
    paint.setColor(uic.theme.border_subtle);
    canvas.drawRoundRect(r, 8, 8, paint);
}

fn measureInlineMarkdownWidth(uic: *Context, text: []const u8, font_body: Font, font_mono: Font) f32 {
    if (text.len == 0) return 0.0;
    const spans = parseInlineSpans(uic.arena, text) catch return uic.measureTextCached(font_body, text);
    var total_w: f32 = 0.0;
    for (spans) |span| {
        if (span.text.len == 0) continue;
        if (span.style == .code) {
            total_w += uic.measureTextCached(font_mono, span.text) + 16.0;
        } else {
            total_w += uic.measureTextCached(font_body, span.text);
        }
    }
    return total_w;
}

fn renderTable(
    uic: *Context,
    tbl: anytype,
    font_body: Font,
    font_mono: Font,
    options: MarkdownOptions,
    block_idx: usize,
    result: *MarkdownResult,
) void {
    const headers = tbl.headers;
    const alignments = tbl.alignments;
    const rows = tbl.rows;
    const is_header_row = tbl.is_header_row;
    var col_count = headers.len;
    for (rows) |row_cells| {
        col_count = @max(col_count, row_cells.len);
    }
    if (col_count == 0) return;

    const avail_w = uic.availableWidth();
    const width_q: i32 = @intFromFloat(@round(avail_w * 4.0));
    const margin_bottom: f32 = 12.0;

    if (uic.pass == .paint and tbl.cached_width_q == width_q and tbl.cached_height > 0.0) {
        const full_r_fast = uic.nextRect(0, tbl.cached_height + margin_bottom);
        const r_fast = Rect.xywh(full_r_fast.left, full_r_fast.top, full_r_fast.right - full_r_fast.left, tbl.cached_height);
        if (!uic.isRectInViewport(r_fast) or !uic.shouldPaint(r_fast)) return;
        // Rewind pass_rect_count and cursor_y so full table paint path below consumes the exact same rect
        uic.pass_rect_count -= 1;
        if (uic.stack_len > 0) {
            uic.stack[uic.stack_len - 1].cursor_y = full_r_fast.top;
        }
    }

    const pad_x: f32 = 10.0;
    const min_col_w: f32 = 36.0;

    // 1. Content-aware column width measurement (using parsed inline span widths rather than raw URL strings)
    const desired_widths = uic.arena.alloc(f32, col_count) catch return;
    var sum_desired: f32 = 0.0;
    for (0..col_count) |c_idx| {
        var max_tw: f32 = 0.0;
        if (c_idx < headers.len and headers[c_idx].len > 0) {
            max_tw = @max(max_tw, measureInlineMarkdownWidth(uic, headers[c_idx], font_body, font_mono));
        }
        for (rows) |r_cells| {
            if (c_idx < r_cells.len and r_cells[c_idx].len > 0) {
                max_tw = @max(max_tw, measureInlineMarkdownWidth(uic, r_cells[c_idx], font_body, font_mono));
            }
        }
        const dw = @max(min_col_w, max_tw + pad_x * 2.0);
        desired_widths[c_idx] = dw;
        sum_desired += dw;
    }

    // 2. Proportionally distribute widths across avail_w
    const col_widths = uic.arena.alloc(f32, col_count) catch return;
    if (sum_desired <= avail_w and sum_desired > 0.0) {
        const excess = avail_w - sum_desired;
        var acc_w: f32 = 0.0;
        for (0..col_count) |col_i| {
            if (col_i == col_count - 1) {
                col_widths[col_i] = @max(min_col_w, avail_w - acc_w);
            } else {
                const add = excess * (desired_widths[col_i] / sum_desired);
                const w = @floor(desired_widths[col_i] + add);
                col_widths[col_i] = w;
                acc_w += w;
            }
        }
    } else if (sum_desired > 0.0) {
        var acc_w: f32 = 0.0;
        for (0..col_count) |col_i| {
            if (col_i == col_count - 1) {
                col_widths[col_i] = @max(min_col_w, avail_w - acc_w);
            } else {
                const w = @floor(@max(min_col_w, avail_w * (desired_widths[col_i] / sum_desired)));
                col_widths[col_i] = w;
                acc_w += w;
            }
        }
    } else {
        const uniform_w = avail_w / @as(f32, @floatFromInt(col_count));
        @memset(col_widths, uniform_w);
    }

    // 3. Dynamic row heights based on multi-line text wrapping
    const line_h: f32 = 18.0;

    var max_header_lines: usize = 1;
    for (0..col_count) |c_idx| {
        if (c_idx < headers.len and headers[c_idx].len > 0) {
            const spans = parseInlineSpans(uic.arena, headers[c_idx]) catch continue;
            const wrapped = wrapInlineSpans(uic, spans, font_body, font_mono, @max(20.0, col_widths[c_idx] - pad_x * 2.0));
            max_header_lines = @max(max_header_lines, wrapped.len);
        }
    }
    const header_h = @max(30.0, 10.0 + @as(f32, @floatFromInt(max_header_lines)) * line_h);

    const row_heights = uic.arena.alloc(f32, rows.len) catch return;
    var total_h: f32 = header_h;
    for (rows, 0..) |row_cells, r_idx| {
        var max_row_lines: usize = 1;
        for (0..col_count) |c_idx| {
            if (c_idx < row_cells.len and row_cells[c_idx].len > 0) {
                const spans = parseInlineSpans(uic.arena, row_cells[c_idx]) catch continue;
                const wrapped = wrapInlineSpans(uic, spans, font_body, font_mono, @max(20.0, col_widths[c_idx] - pad_x * 2.0));
                max_row_lines = @max(max_row_lines, wrapped.len);
            }
        }
        const rh = @max(30.0, 10.0 + @as(f32, @floatFromInt(max_row_lines)) * line_h);
        row_heights[r_idx] = rh;
        total_h += rh;
    }

    tbl.cached_width_q = width_q;
    tbl.cached_height = total_h;
    const full_r = uic.nextRect(0, total_h + margin_bottom);
    const r = Rect.xywh(full_r.left, full_r.top, full_r.right - full_r.left, total_h);

    const col_x = uic.arena.alloc(f32, col_count) catch return;
    var cur_col_x = r.left;
    for (0..col_count) |col_i| {
        col_x[col_i] = cur_col_x;
        cur_col_x += col_widths[col_i];
    }

    if (!uic.isRectInViewport(r)) return;
    if (uic.pass == .paint and !uic.shouldPaint(r)) return;

    const paint = uic.paint;
    const canvas = uic.canvas;

    if (uic.shouldPaint(r)) {
        // Table background
        paint.setStyle(.fill);
        paint.setColor(Color.rgb(16, 22, 35));
        canvas.drawRoundRect(r, 8, 8, paint);

        // Header row background
        const header_r = Rect.xywh(r.left, r.top, r.right - r.left, header_h);
        paint.setColor(Color.rgb(26, 35, 54));
        canvas.drawRoundRect(header_r, 8, 8, paint);
        if (rows.len > 0) {
            canvas.drawRect(Rect.xywh(r.left, r.top + header_h - 8, r.right - r.left, 8), paint);
        }
    }

    // Draw header cells
    const header_row_r = Rect.xywh(r.left, r.top, r.right - r.left, header_h);
    if (uic.isRectInViewport(header_row_r)) {
        for (0..col_count) |col_idx| {
            const h_text = if (col_idx < headers.len) headers[col_idx] else "";
            const cell_x = col_x[col_idx];
            const cell_w = col_widths[col_idx];
            const align_mode = if (col_idx < alignments.len) alignments[col_idx] else .left;
            drawTableCell(
                uic,
                h_text,
                cell_x,
                r.top,
                cell_w,
                header_h,
                align_mode,
                true,
                font_body,
                font_mono,
                options,
                block_idx,
                col_idx,
                result,
            );
        }
    }

    // Draw body rows
    var cur_y = r.top + header_h;
    for (rows, 0..) |row_cells, row_idx| {
        const row_h = row_heights[row_idx];
        const row_r = Rect.xywh(r.left, cur_y, r.right - r.left, row_h);
        const is_hdr = if (row_idx < is_header_row.len) is_header_row[row_idx] else false;

        if (uic.isRectInViewport(row_r)) {
            if (uic.shouldPaint(row_r)) {
                if (is_hdr) {
                    paint.setStyle(.fill);
                    paint.setColor(Color.rgb(26, 35, 54));
                    canvas.drawRect(row_r, paint);
                } else if (row_idx % 2 == 1) {
                    paint.setStyle(.fill);
                    paint.setColor(Color.argb(30, 30, 41, 59));
                    canvas.drawRect(row_r, paint);
                }
                // Top horizontal row border
                paint.setStyle(.fill);
                paint.setColor(uic.theme.border_subtle);
                canvas.drawRect(Rect.xywh(r.left, cur_y, r.right - r.left, 1.0), paint);

                if (is_hdr) {
                    canvas.drawRect(Rect.xywh(r.left, cur_y + row_h - 1.0, r.right - r.left, 1.0), paint);
                }
            }

            for (0..col_count) |col_idx| {
                const cell_text = if (col_idx < row_cells.len) row_cells[col_idx] else "";
                const cell_x = col_x[col_idx];
                const cell_w = col_widths[col_idx];
                const align_mode = if (col_idx < alignments.len) alignments[col_idx] else .left;
                drawTableCell(
                    uic,
                    cell_text,
                    cell_x,
                    cur_y,
                    cell_w,
                    row_h,
                    align_mode,
                    is_hdr,
                    font_body,
                    font_mono,
                    options,
                    block_idx,
                    (row_idx + 1) * col_count + col_idx,
                    result,
                );
            }
        }
        cur_y += row_h;
    }

    if (uic.shouldPaint(r)) {
        paint.setStyle(.fill);
        paint.setColor(uic.theme.border_subtle);

        // Header vertical dividers
        for (1..col_count) |col_idx| {
            canvas.drawRect(Rect.xywh(col_x[col_idx], r.top, 1.0, header_h), paint);
        }

        // Body vertical dividers per row
        var div_y = r.top + header_h;
        for (rows, 0..) |row_cells, row_idx| {
            const rh = row_heights[row_idx];
            var last_non_empty: usize = 0;
            for (row_cells, 0..) |c_text, c_idx| {
                if (c_text.len > 0) last_non_empty = c_idx;
            }
            const div_limit = @min(col_count, last_non_empty + 1);
            for (1..div_limit) |col_idx| {
                canvas.drawRect(Rect.xywh(col_x[col_idx], div_y, 1.0, rh), paint);
            }
            div_y += rh;
        }

        // Outer table border
        paint.setStyle(.stroke);
        paint.setStrokeWidth(1.0);
        paint.setColor(uic.theme.border_subtle);
        canvas.drawRoundRect(r, 8, 8, paint);
    }
}

fn drawTableCell(
    uic: *Context,
    cell_text: []const u8,
    cell_x: f32,
    cell_top: f32,
    cell_w: f32,
    cell_h: f32,
    align_mode: TableAlign,
    is_header: bool,
    font_body: Font,
    font_mono: Font,
    options: MarkdownOptions,
    block_idx: usize,
    cell_id: usize,
    result: *MarkdownResult,
) void {
    if (cell_text.len == 0) return;
    const pad_x: f32 = 10.0;
    const spans = parseInlineSpans(uic.arena, cell_text) catch return;
    const wrapped = wrapInlineSpans(uic, spans, font_body, font_mono, @max(20.0, cell_w - pad_x * 2.0));
    if (wrapped.len == 0) return;

    const line_h: f32 = 18.0;
    const total_text_h = @as(f32, @floatFromInt(wrapped.len)) * line_h;
    const base_y = cell_top + @max(4.0, (cell_h - total_text_h) * 0.5);

    const text_col = if (is_header) Color.white else Color.rgb(226, 232, 240);
    for (wrapped, 0..) |w_line, line_idx| {
        const line_y = base_y + @as(f32, @floatFromInt(line_idx)) * line_h;
        const start_x = switch (align_mode) {
            .left => cell_x + pad_x,
            .center => cell_x + @max(pad_x, (cell_w - w_line.total_width) * 0.5),
            .right => cell_x + @max(pad_x, cell_w - pad_x - w_line.total_width),
        };
        drawWrappedLine(
            uic,
            w_line,
            start_x,
            line_y,
            line_h,
            text_col,
            is_header,
            font_body,
            font_mono,
            options,
            block_idx,
            cell_id * 100 + line_idx,
            result,
        );
    }
}

fn renderThematicBreak(uic: *Context) void {
    const r = uic.nextRect(0, 12.0);
    if (!uic.shouldPaint(r)) return;
    const mid_y = r.top + 6.0;
    uic.paint.setStyle(.fill);
    uic.paint.setColor(uic.theme.border_subtle);
    uic.canvas.drawRect(Rect.xywh(r.left, mid_y, r.right - r.left, 1.0), uic.paint);
}


// ============================================================================
// Unit Tests
// ============================================================================

test "markdown parser: blocks, callouts, lists, tables, and inline spans" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const sample_md =
        \\# Heading One
        \\
        \\Paragraph with **bold text**, *italic*, `inline_code()`, and [Skia Docs](https://skia.org).
        \\
        \\> [!TIP]
        \\> Use `zig build run-markdown` for live hot-reloading.
        \\
        \\- [x] Task completed
        \\- [ ] Task pending
        \\1. Ordered item
        \\
        \\| Module | Pass |
        \\| :--- | :---: |
        \\| `ui` | 2-phase |
        \\
        \\```zig
        \\const x: u32 = 42;
        \\```
        \\
        \\---
    ;

    const blocks = try parseBlocks(arena.allocator(), sample_md);
    try std.testing.expectEqual(@as(usize, 9), blocks.len);

    try std.testing.expect(blocks[0] == .heading);
    try std.testing.expectEqual(@as(u8, 1), blocks[0].heading.level);
    try std.testing.expectEqualStrings("Heading One", blocks[0].heading.text);

    try std.testing.expect(blocks[1] == .paragraph);
    const spans = try parseInlineSpans(arena.allocator(), blocks[1].paragraph.text);
    try std.testing.expect(spans.len >= 7);

    try std.testing.expect(blocks[2] == .blockquote);
    try std.testing.expectEqual(CalloutKind.tip, blocks[2].blockquote.callout.?);

    try std.testing.expect(blocks[3] == .list_item);
    try std.testing.expectEqual(ListMarker{ .task = true }, blocks[3].list_item.marker);

    try std.testing.expect(blocks[6] == .table);
    try std.testing.expectEqual(@as(usize, 2), blocks[6].table.headers.len);
    try std.testing.expectEqual(TableAlign.center, blocks[6].table.alignments[1]);

    try std.testing.expect(blocks[7] == .code_block);
    try std.testing.expectEqualStrings("zig", blocks[7].code_block.language);

    try std.testing.expect(blocks[8] == .thematic_break);
}

test "markdown component rendering and link click interaction" {
    const surface = try skia.Surface.initRasterN32Premul(480, 640);
    defer surface.deinit();

    const paint = try skia.Paint.init();
    defer paint.deinit();
    paint.setAntiAlias(true);

    const font = try Font.init(null, 14.0);
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

    const doc =
        \\# Markdown Component
        \\Click [Open Docs](https://ziglang.org) or review the table below.
        \\> [!NOTE]
        \\> Hardware scissor clipping active.
        \\```zig
        \\pub fn main() void {}
        \\```
    ;

    const root_rect = Rect.xywh(0, 0, 480, 640);

    // Input pass + Paint pass
    uic.beginPass(.input, arena.allocator(), surface.canvas(), root_rect, 10, 10, false, false, false);
    const res_input = uic.markdownEx(doc, .{});
    uic.endPass();
    try std.testing.expectEqual(@as(usize, 4), res_input.block_count);

    uic.beginPass(.paint, arena.allocator(), surface.canvas(), root_rect, 10, 10, false, false, false);
    const res_paint = uic.markdownEx(doc, .{});
    uic.endPass();
    try std.testing.expectEqual(@as(usize, 4), res_paint.block_count);

    // Nested link inside bold `**Heading ([lines 3–19](file:///.../test.md#L3-L19))**` and backtick link label `[`EditorState`](file:///...)`
    const nested = "**Markdown Headings ([lines 3–19](file:///workspace/project/test.md#L3-L19))**: See [`EditorState`](file:///src/app/state.zig#L10) and read_file_name.";
    const nested_spans = try parseInlineSpans(arena.allocator(), nested);
    try std.testing.expectEqual(@as(usize, 6), nested_spans.len);
    try std.testing.expectEqual(InlineStyle.bold, nested_spans[0].style);
    try std.testing.expectEqualStrings("Markdown Headings (", nested_spans[0].text);
    try std.testing.expectEqual(InlineStyle.link, nested_spans[1].style);
    try std.testing.expectEqualStrings("lines 3–19", nested_spans[1].text);
    try std.testing.expectEqualStrings("file:///workspace/project/test.md#L3-L19", nested_spans[1].link_url);
    try std.testing.expectEqual(InlineStyle.bold, nested_spans[2].style);
    try std.testing.expectEqualStrings(")", nested_spans[2].text);
    try std.testing.expectEqual(InlineStyle.link, nested_spans[4].style);
    try std.testing.expectEqualStrings("EditorState", nested_spans[4].text);

    // Heading slug matching & line lookup
    const multi_sec =
        \\# Top Title
        \\Intro text
        \\```zig
        \\# Not A Heading Inside Fence
        \\```
        \\## Zig Standard Library
        \\Details here
    ;
    try std.testing.expect(headingMatchesSlug("Zig Standard Library", "#Zig-Standard-Library"));
    try std.testing.expectEqual(@as(?usize, 6), findHeadingLine(multi_sec, "#Zig-Standard-Library"));
}

test "markdown blockquotes: separate lines for ordered lists, hard breaks, and paragraphs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    // 1. User's ordered list within blockquote: must preserve separate lines
    const list_md =
        \\> 1. Prediction
        \\> 2. Caching
        \\> 3. Replication
    ;
    const list_blocks = try parseBlocks(arena.allocator(), list_md);
    try std.testing.expectEqual(@as(usize, 1), list_blocks.len);
    try std.testing.expect(list_blocks[0] == .blockquote);
    const bq_lines = list_blocks[0].blockquote.lines;
    try std.testing.expectEqual(@as(usize, 3), bq_lines.len);
    try std.testing.expectEqualStrings("1. Prediction", bq_lines[0]);
    try std.testing.expectEqualStrings("2. Caching", bq_lines[1]);
    try std.testing.expectEqualStrings("3. Replication", bq_lines[2]);

    // 2. Soft wrap joining vs hard break
    const soft_md =
        \\> First line of quote
        \\> that continues on second line
    ;
    const soft_blocks = try parseBlocks(arena.allocator(), soft_md);
    try std.testing.expectEqual(@as(usize, 1), soft_blocks.len);
    try std.testing.expectEqual(@as(usize, 1), soft_blocks[0].blockquote.lines.len);
    try std.testing.expectEqualStrings("First line of quote that continues on second line", soft_blocks[0].blockquote.lines[0]);

    // 3. Hard break with 2 trailing spaces
    const hard_md =
        \\> Line one  
        \\> Line two
    ;
    const hard_blocks = try parseBlocks(arena.allocator(), hard_md);
    try std.testing.expectEqual(@as(usize, 1), hard_blocks.len);
    try std.testing.expectEqual(@as(usize, 2), hard_blocks[0].blockquote.lines.len);
    try std.testing.expectEqualStrings("Line one", hard_blocks[0].blockquote.lines[0]);
    try std.testing.expectEqualStrings("Line two", hard_blocks[0].blockquote.lines[1]);

    // 4. Two-phase rendering determinism (Pass.input == Pass.paint)
    const surface = try skia.Surface.initRasterN32Premul(480, 640);
    defer surface.deinit();
    const paint = try skia.Paint.init();
    defer paint.deinit();
    const font = try Font.init(null, 14.0);
    defer font.deinit();

    var uic = Context{
        .arena = arena.allocator(),
        .canvas = surface.canvas(),
        .paint = paint,
        .font_title = font,
        .font_body = font,
        .font_mono = font,
    };
    defer uic.deinit();

    const root_rect = Rect.xywh(0, 0, 480, 640);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), root_rect, 10, 10, false, false, false);
    _ = uic.markdownEx(list_md, .{});
    const input_rects = uic.last_input_rect_count;
    uic.endPass();

    uic.beginPass(.paint, arena.allocator(), surface.canvas(), root_rect, 10, 10, false, false, false);
    _ = uic.markdownEx(list_md, .{});
    const paint_rects = uic.last_paint_rect_count;
    uic.endPass();

    try std.testing.expectEqual(input_rects, paint_rects);
}

test "markdown split tables and tables without delimiter rows: parsing, proportional columns, and 2-phase rendering" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const split_tables_md =
        \\| Bit 7 | Bit 6 | Bit 5 | Bit 4 | Bit 3 | Bit 2 | Bit 1 | Bit 0 |
        \\| ----- | ----- | ----- | ----- | ----- | ----- | ----- | ----- |
        \\| 1 | 0 | 0 | 1 | 1 | 0 | 0 | 1 |
        \\| IO Mode = 1 |  * Mode * | Mode (Mode 0 == 00) | Port A |
        \\
        \\| Bit 3 | Bit 2 | Bit 1 | Bit 0 |
        \\| 1 | 0 | 0 | 1 |
        \\| Port B Control (Bit 1) | Port C Upper Control (Bit 2) | Port C Lower Control (Bit 0) |
    ;

    // 1. Verify parseBlocks correctly identifies BOTH tables
    const blocks = try parseBlocks(arena.allocator(), split_tables_md);
    try std.testing.expectEqual(@as(usize, 2), blocks.len);

    // Table 1 (with standard separator row and variable column counts)
    try std.testing.expect(blocks[0] == .table);
    const tbl1 = blocks[0].table;
    try std.testing.expectEqual(@as(usize, 8), tbl1.headers.len);
    try std.testing.expectEqualStrings("Bit 7", tbl1.headers[0]);
    try std.testing.expectEqualStrings("Bit 0", tbl1.headers[7]);
    try std.testing.expectEqual(@as(usize, 2), tbl1.rows.len);
    try std.testing.expectEqual(@as(usize, 8), tbl1.rows[0].len);
    try std.testing.expectEqualStrings("1", tbl1.rows[0][0]);
    try std.testing.expectEqual(@as(usize, 4), tbl1.rows[1].len);
    try std.testing.expectEqualStrings("IO Mode = 1", tbl1.rows[1][0]);
    try std.testing.expectEqualStrings("* Mode *", tbl1.rows[1][1]);
    try std.testing.expectEqualStrings("Mode (Mode 0 == 00)", tbl1.rows[1][2]);
    try std.testing.expectEqualStrings("Port A", tbl1.rows[1][3]);

    // Table 2 (omitted separator row, split/continuation table)
    try std.testing.expect(blocks[1] == .table);
    const tbl2 = blocks[1].table;
    try std.testing.expectEqual(@as(usize, 4), tbl2.headers.len);
    try std.testing.expectEqualStrings("Bit 3", tbl2.headers[0]);
    try std.testing.expectEqualStrings("Bit 0", tbl2.headers[3]);
    try std.testing.expectEqual(@as(usize, 2), tbl2.rows.len);
    try std.testing.expectEqual(@as(usize, 4), tbl2.rows[0].len);
    try std.testing.expectEqualStrings("1", tbl2.rows[0][0]);
    try std.testing.expectEqualStrings("1", tbl2.rows[0][3]);
    try std.testing.expectEqual(@as(usize, 3), tbl2.rows[1].len);
    try std.testing.expectEqualStrings("Port B Control (Bit 1)", tbl2.rows[1][0]);
    try std.testing.expectEqualStrings("Port C Upper Control (Bit 2)", tbl2.rows[1][1]);
    try std.testing.expectEqualStrings("Port C Lower Control (Bit 0)", tbl2.rows[1][2]);

    // 2. Two-phase rendering determinism (Pass.input == Pass.paint)
    const surface = try skia.Surface.initRasterN32Premul(640, 600);
    defer surface.deinit();
    const paint = try skia.Paint.init();
    defer paint.deinit();
    const font = try Font.init(null, 13.0);
    defer font.deinit();

    var uic = Context{
        .arena = arena.allocator(),
        .canvas = surface.canvas(),
        .paint = paint,
        .font_title = font,
        .font_body = font,
        .font_mono = font,
    };
    defer uic.deinit();

    const root_rect = Rect.xywh(0, 0, 640, 600);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), root_rect, 10, 10, false, false, false);
    _ = uic.markdownEx(split_tables_md, .{});
    uic.endPass();
    const input_rects = uic.last_input_rect_count;

    uic.beginPass(.paint, arena.allocator(), surface.canvas(), root_rect, 10, 10, false, false, false);
    _ = uic.markdownEx(split_tables_md, .{});
    uic.endPass();
    const paint_rects = uic.last_paint_rect_count;

    try std.testing.expectEqual(input_rects, paint_rects);
    try std.testing.expect(input_rects > 0);
}

test "markdown split tables with intermediate highlighted header row" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const split_table_single_md =
        \\| Bit 7 | Bit 6 | Bit 5 | Bit 4 |
        \\| ----- | ----- | ----- | ----- |
        \\| 1 | 0 | 0 | 1 |
        \\| IO Mode = 1 |  * Mode * | Mode (Mode 0 == 00) | Port A |
        \\| Bit 3 | Bit 2 | Bit 1 | Bit 0 |
        \\| ----- | ----- | ----- | ----- |
        \\| 1 | 0 | 0 | 1 |
        \\| Port B Control (Bit 1) | Port C Upper Control (Bit 2) | Port C Lower Control (Bit 0) | - |
    ;

    const blocks = try parseBlocks(arena.allocator(), split_table_single_md);
    try std.testing.expectEqual(@as(usize, 1), blocks.len);
    try std.testing.expect(blocks[0] == .table);
    const tbl = blocks[0].table;

    // Header 0
    try std.testing.expectEqual(@as(usize, 4), tbl.headers.len);
    try std.testing.expectEqualStrings("Bit 7", tbl.headers[0]);
    try std.testing.expectEqualStrings("Bit 4", tbl.headers[3]);

    // Rows: 5 rows total
    try std.testing.expectEqual(@as(usize, 5), tbl.rows.len);
    try std.testing.expectEqual(@as(usize, 5), tbl.is_header_row.len);

    // Row 0: body
    try std.testing.expectEqual(false, tbl.is_header_row[0]);
    try std.testing.expectEqualStrings("1", tbl.rows[0][0]);

    // Row 1: body
    try std.testing.expectEqual(false, tbl.is_header_row[1]);
    try std.testing.expectEqualStrings("IO Mode = 1", tbl.rows[1][0]);

    // Row 2: intermediate highlighted header row ("Bit 3 | Bit 2 | Bit 1 | Bit 0")
    try std.testing.expectEqual(true, tbl.is_header_row[2]);
    try std.testing.expectEqualStrings("Bit 3", tbl.rows[2][0]);
    try std.testing.expectEqualStrings("Bit 2", tbl.rows[2][1]);
    try std.testing.expectEqualStrings("Bit 1", tbl.rows[2][2]);
    try std.testing.expectEqualStrings("Bit 0", tbl.rows[2][3]);

    // Row 3: body
    try std.testing.expectEqual(false, tbl.is_header_row[3]);
    try std.testing.expectEqualStrings("1", tbl.rows[3][0]);

    // Row 4: body
    try std.testing.expectEqual(false, tbl.is_header_row[4]);
    try std.testing.expectEqualStrings("Port B Control (Bit 1)", tbl.rows[4][0]);
    try std.testing.expectEqualStrings("-", tbl.rows[4][3]);

    // 2-phase determinism
    const surface = try skia.Surface.initRasterN32Premul(640, 600);
    defer surface.deinit();
    const paint = try skia.Paint.init();
    defer paint.deinit();
    const font = try Font.init(null, 13.0);
    defer font.deinit();

    var uic = Context{
        .arena = arena.allocator(),
        .canvas = surface.canvas(),
        .paint = paint,
        .font_title = font,
        .font_body = font,
        .font_mono = font,
    };
    defer uic.deinit();

    const root_rect = Rect.xywh(0, 0, 640, 600);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), root_rect, 10, 10, false, false, false);
    _ = uic.markdownEx(split_table_single_md, .{});
    uic.endPass();
    const in_rects = uic.last_input_rect_count;

    uic.beginPass(.paint, arena.allocator(), surface.canvas(), root_rect, 10, 10, false, false, false);
    _ = uic.markdownEx(split_table_single_md, .{});
    uic.endPass();
    const pt_rects = uic.last_paint_rect_count;

    try std.testing.expectEqual(in_rects, pt_rects);
    try std.testing.expect(in_rects > 0);
}

test "markdown LaTeX math (\\rightarrow, O(\\log L), superscripts/subscripts), nested list indentation, and code pill wrapping" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    // 1. Direct LaTeX math formatting checks
    try std.testing.expectEqualStrings("→", try formatLatexMath(arena.allocator(), "\\rightarrow"));
    try std.testing.expectEqualStrings("O(log L)", try formatLatexMath(arena.allocator(), "O(\\log L)"));
    try std.testing.expectEqualStrings("2⁸ - 1", try formatLatexMath(arena.allocator(), "2^8 - 1"));
    try std.testing.expectEqualStrings("x₀ + x₁ ≤ yₙ", try formatLatexMath(arena.allocator(), "x_0 + x_1 \\le y_n"));
    try std.testing.expectEqualStrings("(a + b)/c", try formatLatexMath(arena.allocator(), "\\frac{a + b}{c}"));
    try std.testing.expectEqualStrings("√(x² + y²)", try formatLatexMath(arena.allocator(), "\\sqrt{x^2 + y^2}"));

    // 2. Inline spans with `\rightarrow` inside bold & plain text + currency preservation
    const rbs_line = "**`8'h00 - 8'h00` $\\rightarrow$ `diff = 8'h00, bout = 0` (All-Zeros / `borrow[0]` Check)**";
    const rbs_spans = try parseInlineSpans(arena.allocator(), rbs_line);
    try std.testing.expectEqual(@as(usize, 6), rbs_spans.len);
    try std.testing.expectEqual(InlineStyle.code, rbs_spans[0].style);
    try std.testing.expectEqualStrings("8'h00 - 8'h00", rbs_spans[0].text);
    try std.testing.expectEqual(InlineStyle.bold, rbs_spans[1].style);
    try std.testing.expectEqualStrings(" → ", rbs_spans[1].text);
    try std.testing.expectEqual(InlineStyle.code, rbs_spans[2].style);
    try std.testing.expectEqualStrings("diff = 8'h00, bout = 0", rbs_spans[2].text);

    const currency_line = "Costs $100 and $200 or \\$50 in total.";
    const currency_spans = try parseInlineSpans(arena.allocator(), currency_line);
    try std.testing.expectEqual(@as(usize, 1), currency_spans.len);
    try std.testing.expectEqualStrings("Costs $100 and $200 or $50 in total.", currency_spans[0].text);

    // 3. Table cells containing bitwise OR inside backticks (`a | b`) and escaped pipe (`\|`)
    const tbl_md =
        \\| Expression | Meaning |
        \\| :--- | :--- |
        \\| `(~a & b) | bin` | Borrow out \| carry |
    ;
    const tbl_blocks = try parseBlocks(arena.allocator(), tbl_md);
    try std.testing.expectEqual(@as(usize, 1), tbl_blocks.len);
    try std.testing.expect(tbl_blocks[0] == .table);
    try std.testing.expectEqual(@as(usize, 2), tbl_blocks[0].table.rows[0].len);
    try std.testing.expectEqualStrings("`(~a & b) | bin`", tbl_blocks[0].table.rows[0][0]);
    try std.testing.expectEqualStrings("Borrow out | carry", tbl_blocks[0].table.rows[0][1]);

    // 4. Full Ripple-Borrow Subtractor markdown (2-phase Pass.input & Pass.paint determinism)
    const rbs_doc =
        \\Here is what each of the 4 directed corner cases in [`tb_nbitRBS.sv`](file:///tb_nbitRBS.sv) specifically tests inside an 8-bit ripple-borrow chain:
        \\
        \\1. **`8'h00 - 8'h00` $\rightarrow$ `diff = 8'h00, bout = 0` (All-Zeros / `borrow[0]` Check)**
        \\   - **What it tests:** Every bit stage gets `a=0, b=0`.
        \\   - **What bug it catches:** If `borrow[0]` (the initial borrow-in to bit 0) were accidentally tied to `1` or left floating (`x`), `0 - 0` would fail immediately.
        \\
        \\2. **`8'hFF - 8'hFF` $\rightarrow$ `diff = 8'h00, bout = 0` (All-Ones Cancellation)**
        \\    - **What it tests:** Every bit stage gets `a=1, b=1, bin=0`.
        \\    - **What bug it catches:** Verifies that subtracting identical `1`s cancels to `0` at every bit position and never generates a false borrow (`(~a & b)` must be `0` when `a=1, b=1`).
    ;
    const rbs_blocks = try parseBlocks(arena.allocator(), rbs_doc);
    try std.testing.expectEqual(@as(usize, 7), rbs_blocks.len);
    try std.testing.expectEqual(@as(u8, 0), rbs_blocks[1].list_item.indent);
    try std.testing.expectEqual(@as(u8, 1), rbs_blocks[2].list_item.indent);
    try std.testing.expectEqual(@as(u8, 1), rbs_blocks[5].list_item.indent);

    const surface = try skia.Surface.initRasterN32Premul(420, 600);
    defer surface.deinit();
    const paint = try skia.Paint.init();
    defer paint.deinit();
    const font = try Font.init(null, 13.0);
    defer font.deinit();

    var uic = Context{
        .arena = arena.allocator(),
        .canvas = surface.canvas(),
        .paint = paint,
        .font_title = font,
        .font_body = font,
        .font_mono = font,
    };
    defer uic.deinit();

    const root_rect = Rect.xywh(0, 0, 420, 600);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), root_rect, 10, 10, false, false, false);
    _ = uic.markdownEx(rbs_doc, .{});
    uic.endPass();
    const in_cnt = uic.last_input_rect_count;

    uic.beginPass(.paint, arena.allocator(), surface.canvas(), root_rect, 10, 10, false, false, false);
    _ = uic.markdownEx(rbs_doc, .{});
    uic.endPass();
    const pt_cnt = uic.last_paint_rect_count;

    try std.testing.expectEqual(in_cnt, pt_cnt);
    try std.testing.expect(in_cnt > 0);
}

test "markdown overflowing code block horizontal scrolling (scroll_dx and Shift+scroll_dy) and 2-phase determinism" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const surface = try skia.Surface.initRasterN32Premul(320, 400);
    defer surface.deinit();
    const paint = try skia.Paint.init();
    defer paint.deinit();
    const font = try Font.init(null, 13.0);
    defer font.deinit();

    var uic = Context{
        .arena = arena.allocator(),
        .canvas = surface.canvas(),
        .paint = paint,
        .font_title = font,
        .font_body = font,
        .font_mono = font,
    };
    defer uic.deinit();

    const code_md =
        \\```zig
        \\pub fn extremelyLongFunctionDeclarationThatOverflowsTheNarrowViewportHorizontally(param_a: usize, param_b: []const u8, param_c: u64) !void {
        \\    return;
        \\}
        \\```
    ;

    const root_rect = Rect.xywh(0, 0, 320, 400);

    // Frame 1: Initial render (scroll_x starts at 0)
    uic.beginPass(.input, arena.allocator(), surface.canvas(), root_rect, 100, 50, false, false, false);
    _ = uic.markdownEx(code_md, .{});
    uic.endPass();
    try std.testing.expectEqual(@as(f32, 0.0), uic.fallback_code_block_scroll_state.scroll_x);

    uic.beginPass(.paint, arena.allocator(), surface.canvas(), root_rect, 100, 50, false, false, false);
    _ = uic.markdownEx(code_md, .{});
    uic.endPass();
    try std.testing.expectEqual(uic.last_input_rect_count, uic.last_paint_rect_count);

    // Frame 2: Horizontal trackpad scroll (`scroll_dx < 0` scrolls right) while hovering the code block
    uic.beginPass(.input, arena.allocator(), surface.canvas(), root_rect, 100, 50, false, false, false);
    uic.scroll_dx = -48.0;
    uic.scroll_dy = 0.0;
    _ = uic.markdownEx(code_md, .{});
    uic.endPass();
    try std.testing.expectApproxEqAbs(@as(f32, 48.0), uic.fallback_code_block_scroll_state.scroll_x, 0.1);
    try std.testing.expect(uic.dirty_rect != null);

    uic.beginPass(.paint, arena.allocator(), surface.canvas(), root_rect, 100, 50, false, false, false);
    _ = uic.markdownEx(code_md, .{});
    uic.endPass();
    try std.testing.expectEqual(uic.last_input_rect_count, uic.last_paint_rect_count);

    // Frame 3: Shift + vertical scroll wheel (`mouse_shift = true`, `scroll_dy < 0`) scrolls further right
    uic.beginPass(.input, arena.allocator(), surface.canvas(), root_rect, 100, 50, false, false, false);
    uic.scroll_dx = 0.0;
    uic.scroll_dy = -32.0;
    uic.mouse_shift = true;
    _ = uic.markdownEx(code_md, .{});
    uic.endPass();
    uic.mouse_shift = false;
    try std.testing.expectApproxEqAbs(@as(f32, 80.0), uic.fallback_code_block_scroll_state.scroll_x, 0.1);
}

test "markdown SystemVerilog fenced code blocks (systemverilog, system verilog, sv, verilog) and bubble code rendering" {
    try std.testing.expectEqual(root.CodeLanguage.systemverilog, root.CodeLanguage.fromFence("systemverilog"));
    try std.testing.expectEqual(root.CodeLanguage.systemverilog, root.CodeLanguage.fromFence("SystemVerilog"));
    try std.testing.expectEqual(root.CodeLanguage.systemverilog, root.CodeLanguage.fromFence("system verilog"));
    try std.testing.expectEqual(root.CodeLanguage.systemverilog, root.CodeLanguage.fromFence("system-verilog"));
    try std.testing.expectEqual(root.CodeLanguage.systemverilog, root.CodeLanguage.fromFence("system_verilog"));
    try std.testing.expectEqual(root.CodeLanguage.systemverilog, root.CodeLanguage.fromFence("verilog"));
    try std.testing.expectEqual(root.CodeLanguage.systemverilog, root.CodeLanguage.fromFence("sv"));
    try std.testing.expectEqual(root.CodeLanguage.plain, root.CodeLanguage.fromFence("text"));

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const sv_md =
        \\## D1: Fixed-Length Array Semantics
        \\
        \\```systemverilog
        \\logic [3:0] a [0:7];
        \\logic [$clog2(8)-1:0] idx;
        \\initial begin
        \\    a = '{default: 4'h3};
        \\    a[0] = op_e'(3'd2);
        \\    $display("%0d %0d", $size(a), $dimensions(a));
        \\end
        \\```
        \\
        \\```text
        \\TODO
        \\```
    ;

    const blocks = try parseBlocks(arena.allocator(), sv_md);
    try std.testing.expectEqual(@as(usize, 3), blocks.len);
    try std.testing.expect(blocks[1] == .code_block);
    try std.testing.expectEqualStrings("systemverilog", blocks[1].code_block.language);
    try std.testing.expectEqual(@as(usize, 7), blocks[1].code_block.lines.len);

    const surface = try skia.Surface.initRasterN32Premul(520, 480);
    defer surface.deinit();
    const paint = try skia.Paint.init();
    defer paint.deinit();
    const font = try Font.init(null, 13.0);
    defer font.deinit();

    var uic = Context{
        .arena = arena.allocator(),
        .canvas = surface.canvas(),
        .paint = paint,
        .font_title = font,
        .font_body = font,
        .font_mono = font,
    };
    defer uic.deinit();

    const root_rect = Rect.xywh(0, 0, 520, 480);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), root_rect, 20, 20, false, false, false);
    _ = uic.markdownEx(sv_md, .{});
    _ = uic.markdownBubble(sv_md, .{});
    uic.endPass();
    const in_rects = uic.last_input_rect_count;

    uic.beginPass(.paint, arena.allocator(), surface.canvas(), root_rect, 20, 20, false, false, false);
    _ = uic.markdownEx(sv_md, .{});
    _ = uic.markdownBubble(sv_md, .{});
    uic.endPass();
    const pt_rects = uic.last_paint_rect_count;

    try std.testing.expectEqual(in_rects, pt_rects);
}


