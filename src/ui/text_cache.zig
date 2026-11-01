//! 4-Way Set-Associative `SkTextBlob` + glyph advance width cache (1024 sets × 4 ways = 4096 slots).
//! Eliminates per-frame UTF-8 text shaping, GPU glyph run buffer rebuilds, and direct-mapped hash thrashing.

const std = @import("std");
const skia = @import("skia");
const Font = skia.Font;
const TextBlob = skia.TextBlob;
const Canvas = skia.Canvas;
const Paint = skia.Paint;

pub const TextCacheEntry = struct {
    key: u64 = 0,
    width: f32 = 0,
    last_used: u32 = 0,
    blob: ?TextBlob = null,
};

pub const TextCacheStats = struct {
    lookups: usize = 0,
    hits: usize = 0,
    misses: usize = 0,
    evictions: usize = 0,

    pub fn hitRate(self: TextCacheStats) f32 {
        if (self.lookups == 0) return 100.0;
        return (@as(f32, @floatFromInt(self.hits)) / @as(f32, @floatFromInt(self.lookups))) * 100.0;
    }
};

pub const TextCacheSetCount: usize = 1024;
pub const TextCacheWays: usize = 4;
pub const TextCacheCapacity: usize = TextCacheSetCount * TextCacheWays;

pub const TextCache = struct {
    entries: [TextCacheCapacity]TextCacheEntry = @splat(.{}),
    access_tick: u32 = 0,
    stats: TextCacheStats = .{},

    pub fn deinit(self: *TextCache) void {
        for (&self.entries) |*entry| {
            if (entry.blob) |b| {
                b.deinit();
                entry.blob = null;
            }
            entry.key = 0;
            entry.last_used = 0;
        }
    }

    pub fn getStats(self: *const TextCache) TextCacheStats {
        return self.stats;
    }

    pub fn resetStats(self: *TextCache) void {
        self.stats = .{};
    }

    pub fn computeKey(font: Font, text: []const u8) u64 {
        var h = std.hash.Fnv1a_64.init();
        const fptr = @intFromPtr(font.ptr);
        h.update(std.mem.asBytes(&fptr));
        h.update(text);
        const val = h.final();
        return if (val == 0) 1 else val;
    }

    pub fn getOrPopulate(self: *TextCache, font: Font, text: []const u8) *TextCacheEntry {
        self.stats.lookups += 1;
        self.access_tick +%= 1;
        const tick = self.access_tick;

        const key = computeKey(font, text);
        const set_idx = @as(usize, @truncate(key)) & (TextCacheSetCount - 1);
        const base = set_idx * TextCacheWays;
        const set_ways = self.entries[base .. base + TextCacheWays];

        // 1. Check all 4 ways in the set for a key match
        for (set_ways) |*way| {
            if (way.key == key) {
                self.stats.hits += 1;
                way.last_used = tick;
                return way;
            }
        }

        // 2. Miss: select an empty way or the least-recently-used (LRU) way in this 4-way set
        self.stats.misses += 1;
        var victim: *TextCacheEntry = &set_ways[0];
        var max_age: u32 = 0;
        for (set_ways) |*way| {
            if (way.key == 0) {
                victim = way;
                break;
            }
            const age = tick -% way.last_used;
            if (age >= max_age) {
                max_age = age;
                victim = way;
            }
        }

        if (victim.blob) |old_blob| {
            self.stats.evictions += 1;
            old_blob.deinit();
        }
        if (TextBlob.initFromUtf8WithWidth(text, font)) |shaped| {
            victim.* = .{
                .key = key,
                .width = shaped.width,
                .last_used = tick,
                .blob = shaped.blob,
            };
        } else |_| {
            victim.* = .{
                .key = key,
                .width = font.measureText(text),
                .last_used = tick,
                .blob = null,
            };
        }
        return victim;
    }

    pub fn measure(self: *TextCache, font: Font, text: []const u8) f32 {
        if (text.len == 0) return 0;
        return self.getOrPopulate(font, text).width;
    }

    pub fn draw(self: *TextCache, canvas: Canvas, paint: Paint, font: Font, text: []const u8, x: f32, y: f32) void {
        if (text.len == 0) return;
        const entry = self.getOrPopulate(font, text);
        if (entry.blob) |blob| {
            canvas.drawTextBlob(blob, x, y, paint);
        } else {
            canvas.drawSimpleText(text, x, y, font, paint);
        }
    }
};

test "TextCache: 4-way set-associative cache prevents hash collision thrashing and evicts LRU" {
    const font = try Font.init(null, 13.0);
    defer font.deinit();

    var cache = TextCache{};
    defer cache.deinit();

    // Find 5 distinct strings that map to the exact same 10-bit set index
    var colliding: [5][16]u8 = undefined;
    var slices: [5][]const u8 = undefined;
    var found: usize = 0;
    var target_set: ?usize = null;
    var i: u32 = 0;
    while (found < 5 and i < 200_000) : (i += 1) {
        var buf: [16]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, "item_{d}", .{i}) catch unreachable;
        const k = TextCache.computeKey(font, s);
        const set_idx = @as(usize, @truncate(k)) & (TextCacheSetCount - 1);
        if (target_set == null) target_set = set_idx;
        if (set_idx == target_set.?) {
            @memcpy(colliding[found][0..s.len], s);
            slices[found] = colliding[found][0..s.len];
            found += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 5), found);

    // Populate 4 colliding entries into the same set: 0 evictions, and subsequent lookups are 100% hits!
    for (0..4) |w| {
        _ = cache.measure(font, slices[w]);
    }
    try std.testing.expectEqual(@as(usize, 0), cache.getStats().evictions);

    cache.resetStats();
    for (0..40) |iter| {
        _ = cache.measure(font, slices[iter & 3]);
    }
    try std.testing.expectEqual(@as(usize, 40), cache.getStats().hits);
    try std.testing.expectEqual(@as(usize, 0), cache.getStats().misses);

    // Touch ways 1, 2, 3 so way 0 (`slices[0]`) is the least-recently-used
    _ = cache.measure(font, slices[1]);
    _ = cache.measure(font, slices[2]);
    _ = cache.measure(font, slices[3]);

    // Inserting 5th colliding string evicts `slices[0]`, keeping `slices[1..4]` hot
    _ = cache.measure(font, slices[4]);
    try std.testing.expectEqual(@as(usize, 1), cache.getStats().evictions);

    const hits_before = cache.getStats().hits;
    _ = cache.measure(font, slices[1]);
    _ = cache.measure(font, slices[2]);
    _ = cache.measure(font, slices[3]);
    _ = cache.measure(font, slices[4]);
    try std.testing.expectEqual(hits_before + 4, cache.getStats().hits);
}
