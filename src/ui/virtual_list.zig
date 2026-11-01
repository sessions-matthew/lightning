//! Variable-height virtualized list caching (`VariableHeightCache`) and deterministic
//! UTF-8 word-wrapping (`wrapPlainText`, `wrappedLabel`) for `ui.Context`.

const std = @import("std");
const skia = @import("skia");
const root = @import("root.zig");
const c = skia.c;
const Color = skia.Color;
const Rect = skia.Rect;
const Font = skia.Font;
const Context = root.Context;
const Padding = root.Padding;

pub const WrappedLabelOptions = struct {
    color: ?u32 = null,
    font: ?Font = null,
    mono: bool = false,
    line_height: f32 = 18.0,
    max_width: ?f32 = null,
    pad_x: f32 = 0.0,
    pad_y: f32 = 0.0,
};

/// Word-wraps `text` into lines that fit within `max_width` using `font` (or `*const skia.Font`) and `uic.arena`.
/// Deterministic across `Pass.input` and `Pass.paint` and safe on UTF-8 codepoint boundaries.
pub fn wrapPlainText(uic: *Context, font_or_ptr: anytype, text: []const u8, max_width: f32) []const []const u8 {
    const font: Font = switch (@typeInfo(@TypeOf(font_or_ptr))) {
        .pointer => font_or_ptr.*,
        else => font_or_ptr,
    };

    const trimmed = std.mem.trim(u8, text, " \t\r\n");
    if (trimmed.len == 0) {
        const empty = uic.arena.alloc([]const u8, 1) catch return &.{""};
        empty[0] = "";
        return empty;
    }

    var lines: std.ArrayList([]const u8) = .empty;
    const limit_w = @max(60.0, max_width);

    var para_it = std.mem.splitScalar(u8, trimmed, '\n');
    while (para_it.next()) |raw_para| {
        const para = std.mem.trim(u8, raw_para, " \t\r");
        if (para.len == 0) continue;

        var line_start: usize = 0;
        var line_end: usize = 0;
        var pos: usize = 0;

        while (pos < para.len) {
            while (pos < para.len and para[pos] == ' ') : (pos += 1) {}
            if (pos >= para.len) break;

            var word_end = pos;
            while (word_end < para.len and para[word_end] != ' ') : (word_end += 1) {}

            const candidate_start = if (line_end > line_start) line_start else pos;
            const candidate = para[candidate_start..word_end];
            const cand_w = uic.measureTextCached(font, candidate);

            if (line_end > line_start and cand_w > limit_w) {
                lines.append(uic.arena, para[line_start..line_end]) catch break;
                line_start = pos;
                line_end = word_end;
            } else {
                if (line_end == line_start) line_start = pos;
                line_end = word_end;
            }

            // Hard-wrap single ultra-long tokens that exceed `limit_w`
            while (line_end > line_start and uic.measureTextCached(font, para[line_start..line_end]) > limit_w and (line_end - line_start) > 6) {
                var split_idx = line_start + @min(line_end - line_start - 1, 24);
                split_idx = root.code_editor_mod.snapToGraphemeBoundary(para, split_idx);
                if (split_idx <= line_start) split_idx = line_end;
                lines.append(uic.arena, para[line_start..split_idx]) catch break;
                line_start = split_idx;
            }

            pos = word_end;
        }

        if (line_end > line_start) {
            lines.append(uic.arena, para[line_start..line_end]) catch {};
        }
    }

    if (lines.items.len == 0) {
        lines.append(uic.arena, trimmed) catch return &.{trimmed};
    }
    return lines.items;
}

/// Wraps `text` using `uic.wrapText`, reserves a deterministic `uic.box` for the wrapped lines
/// in both passes, and draws each line in `Pass.paint` when `uic.shouldPaint(rect)`.
pub fn wrappedLabel(uic: *Context, text: []const u8, opts: WrappedLabelOptions) void {
    const font = opts.font orelse (if (opts.mono) uic.font_mono else uic.font_body);
    const avail_w = opts.max_width orelse @max(60.0, uic.availableWidth() - opts.pad_x * 2.0);
    const lines = wrapPlainText(uic, font, text, avail_w);
    const line_h = @max(10.0, opts.line_height);
    const total_h = @as(f32, @floatFromInt(@max(@as(usize, 1), lines.len))) * line_h + opts.pad_y * 2.0;

    var b = uic.box(.{
        .direction = .column,
        .h = .pixels(total_h),
        .padding = Padding.xy(opts.pad_x, opts.pad_y),
        .gap = 0,
    });
    defer b.end();

    const rect = b.rect;
    if (uic.shouldPaint(rect)) {
        uic.paint.setStyle(.fill);
        uic.paint.setColor(opts.color orelse uic.theme.text_primary);
        for (lines, 0..) |line_str, idx| {
            const by = rect.top + opts.pad_y + line_h * 0.78 + @as(f32, @floatFromInt(idx)) * line_h;
            uic.drawTextCached(font, line_str, rect.left + opts.pad_x, by);
        }
    }
}

/// Two-phase variable-height list item cache with direct-mapped index slots, 2-way associative
/// content-signature hash table (so heights survive conversation/list switches), and a deterministic
/// per-frame `culled_mask` bitset shared from `Pass.input` to `Pass.paint`.
pub fn VariableHeightCache(comptime max_entries: usize) type {
    const mask_words = @max(1, (max_entries + 63) / 64);
    return struct {
        const Self = @This();
        pub const capacity = max_entries;

        sig: [max_entries]u64 = @splat(0),
        height: [max_entries]f32 = @splat(-1.0),
        hash_sig: [512]u64 = @splat(0),
        hash_height: [512]f32 = @splat(-1.0),
        culled_mask: [mask_words]u64 = @splat(0),
        width_px: i32 = 0,

        /// Invalidates cached heights if the container width changed, and clears `culled_mask`
        /// at the start of `Pass.input`. Accepts either `i32` or `f32` width.
        pub fn syncWidthAndResetCullMask(self: *Self, width: anytype) void {
            const width_px: i32 = switch (@typeInfo(@TypeOf(width))) {
                .float, .comptime_float => @intFromFloat(@round(width)),
                else => @intCast(width),
            };
            if (self.width_px != width_px) {
                self.sig = @splat(0);
                self.height = @splat(-1.0);
                self.hash_sig = @splat(0);
                self.hash_height = @splat(-1.0);
                self.width_px = width_px;
            }
            self.culled_mask = @splat(0);
        }

        pub fn lookupHeight(self: *Self, idx: usize, sig: u64) ?f32 {
            if (idx >= max_entries or sig == 0) return null;
            if (self.sig[idx] == sig and self.height[idx] > 0.0) {
                return self.height[idx];
            }
            const slot0: usize = @as(usize, @truncate(sig)) & 511;
            if (self.hash_sig[slot0] == sig and self.hash_height[slot0] > 0.0) {
                const h = self.hash_height[slot0];
                self.sig[idx] = sig;
                self.height[idx] = h;
                return h;
            }
            const slot1: usize = (slot0 + 1) & 511;
            if (self.hash_sig[slot1] == sig and self.hash_height[slot1] > 0.0) {
                const h = self.hash_height[slot1];
                self.sig[idx] = sig;
                self.height[idx] = h;
                return h;
            }
            return null;
        }

        pub fn lookupAny(self: *const Self, idx: usize) ?f32 {
            if (idx >= max_entries) return null;
            const h = self.height[idx];
            return if (h > 0.0) h else null;
        }

        pub fn recordHeight(self: *Self, idx: usize, sig: u64, measured_h: f32) void {
            if (idx >= max_entries) return;
            if (measured_h > 0.0 and sig != 0) {
                self.sig[idx] = sig;
                self.height[idx] = measured_h;
                const slot0: usize = @as(usize, @truncate(sig)) & 511;
                if (self.hash_sig[slot0] == 0 or self.hash_sig[slot0] == sig) {
                    self.hash_sig[slot0] = sig;
                    self.hash_height[slot0] = measured_h;
                } else {
                    const slot1: usize = (slot0 + 1) & 511;
                    self.hash_sig[slot1] = sig;
                    self.hash_height[slot1] = measured_h;
                }
            } else {
                self.sig[idx] = 0;
                self.height[idx] = -1.0;
            }
        }

        pub fn isCulled(self: *const Self, idx: usize) bool {
            if (idx >= max_entries) return false;
            const word = idx >> 6;
            const bit: u6 = @intCast(idx & 63);
            return (self.culled_mask[word] & (@as(u64, 1) << bit)) != 0;
        }

        pub fn setCulled(self: *Self, idx: usize, skip: bool) void {
            if (idx >= max_entries) return;
            const word = idx >> 6;
            const bit: u6 = @intCast(idx & 63);
            if (skip) {
                self.culled_mask[word] |= (@as(u64, 1) << bit);
            } else {
                self.culled_mask[word] &= ~(@as(u64, 1) << bit);
            }
        }

        /// Two-phase deterministic culling check:
        ///   - During `Pass.input`, looks up cached height for `(idx, sig)`, checks if `[cur_rel_y, cur_rel_y + h]`
        ///     lies outside `[vp_top, vp_bot]`, records the decision via `setCulled(idx, skip)`, and returns
        ///     `cached_h` if culled (or `null` if the item should be rendered).
        ///   - During `Pass.paint`, checks `isCulled(idx)` and returns `lookupAny(idx)` if culled.
        pub fn shouldCullItem(
            self: *Self,
            uic: *Context,
            idx: usize,
            sig: u64,
            cur_rel_y: f32,
            vp_top: f32,
            vp_bot: f32,
        ) ?f32 {
            if (idx >= max_entries) return null;
            if (uic.pass == .input) {
                if (self.lookupHeight(idx, sig)) |cached_h| {
                    const skip = (cur_rel_y + cached_h < vp_top) or (cur_rel_y > vp_bot);
                    self.setCulled(idx, skip);
                    if (skip) return cached_h;
                } else {
                    self.setCulled(idx, false);
                }
                return null;
            } else {
                if (self.isCulled(idx)) {
                    return self.lookupAny(idx);
                }
                return null;
            }
        }

        /// Evaluates `shouldCullItem`; when the item is culled, reserves a deterministic `uic.box`
        /// of height `cached_h` in both passes and returns its `Rect` (or `null` when the item should be rendered).
        pub fn cullOrBeginItem(
            self: *Self,
            uic: *Context,
            idx: usize,
            sig: u64,
            cur_rel_y: f32,
            vp_top: f32,
            vp_bot: f32,
        ) ?c.sk_rect_t {
            if (self.shouldCullItem(uic, idx, sig, cur_rel_y, vp_top, vp_bot)) |cached_h| {
                var placeholder = uic.box(.{
                    .h = .pixels(cached_h),
                    .padding = Padding.all(0),
                    .gap = 0,
                });
                placeholder.end();
                return placeholder.rect;
            }
            return null;
        }
    };
}

pub const EntryHeightCache = VariableHeightCache(256);

test "virtual_list: wrapPlainText, wrappedLabel, and VariableHeightCache 2-phase determinism" {
    const surface = try skia.Surface.initRasterN32Premul(320, 240);
    defer surface.deinit();
    const paint = try skia.Paint.init();
    defer paint.deinit();
    const font = try Font.init(null, 13.0);
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

    // 1. wrapPlainText handles both value and pointer font arguments and wraps long text
    const lines_val = uic.wrapText(uic.font_body, "A multi-word sentence that wraps cleanly across lines", 110.0);
    const lines_ptr = wrapPlainText(&uic, &uic.font_body, "A multi-word sentence that wraps cleanly across lines", 110.0);
    try std.testing.expect(lines_val.len >= 2);
    try std.testing.expectEqual(lines_val.len, lines_ptr.len);

    // 2. VariableHeightCache + wrappedLabel 2-phase input & paint determinism
    var cache = EntryHeightCache{};
    const buildScene = struct {
        fn build(ctx: *Context, vcache: *EntryHeightCache, culled_count_out: *usize) void {
            var sp = ctx.scrollPanel("vlist_scroll", .{
                .w = .pixels(240),
                .h = .pixels(100),
                .padding = Padding.all(4),
                .gap = 4.0,
            });
            defer sp.end();

            if (ctx.pass == .input) {
                vcache.syncWidthAndResetCullMask(240);
            }
            const vp_top = sp.rect.top - 20.0;
            const vp_bot = sp.rect.bottom + 20.0;
            var culled: usize = 0;

            for (0..12) |idx| {
                var id_g = ctx.scopedId(idx);
                defer id_g.end();
                const item_top_y = ctx.nextCursorY();
                const sig: u64 = @as(u64, idx + 1) * 0x9E37_79B9;
                if (vcache.cullOrBeginItem(ctx, idx, sig, item_top_y, vp_top, vp_bot) != null) {
                    culled += 1;
                    continue;
                }
                ctx.wrappedLabel("Wrapped item row inside virtualized scroll list", .{
                    .max_width = 200.0,
                });
                const bot_y = ctx.stack[ctx.stack_len - 1].cursor_y;
                if (ctx.pass == .input) {
                    vcache.recordHeight(idx, sig, bot_y - item_top_y);
                }
            }
            culled_count_out.* = culled;
        }
    }.build;

    // Frame 1: Initial measurement pass (0 items culled since cache is cold)
    var culled_in: usize = 0;
    var culled_paint: usize = 0;
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 320, 240), 0, 0, false, false, false);
    buildScene(&uic, &cache, &culled_in);
    uic.endPass();
    try std.testing.expectEqual(@as(usize, 0), culled_in);

    uic.clip_damage = Rect.xywh(0, 0, 320, 240);
    uic.beginPass(.paint, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 320, 240), 0, 0, false, false, false);
    buildScene(&uic, &cache, &culled_paint);
    uic.endPass();
    try std.testing.expectEqual(uic.last_input_rect_count, uic.last_paint_rect_count);

    // Frame 2: Warm cache culls off-screen bottom items identically in Pass.input and Pass.paint
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 320, 240), 0, 0, false, false, false);
    buildScene(&uic, &cache, &culled_in);
    uic.endPass();
    try std.testing.expect(culled_in > 0);

    uic.clip_damage = Rect.xywh(0, 0, 320, 240);
    uic.beginPass(.paint, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 320, 240), 0, 0, false, false, false);
    buildScene(&uic, &cache, &culled_paint);
    uic.endPass();
    try std.testing.expectEqual(culled_in, culled_paint);
    try std.testing.expectEqual(uic.last_input_rect_count, uic.last_paint_rect_count);
}
