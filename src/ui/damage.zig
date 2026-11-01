//! Multi-Rect Disjoint Damage Region Tracking (`src/ui/damage.zig`).
//!
//! Accumulates dirty rectangles during `Pass.input` (`DamageList`, up to `MaxDamageRects` disjoint
//! regions) and culls unchanged widgets + clips hardware scissor regions during `Pass.paint`.

const std = @import("std");
const skia = @import("skia");
const c = skia.c;
const Rect = skia.Rect;

pub const MaxDamageRects: usize = 8;

/// Multi-rect disjoint damage region list (`SkRegion`-style).
/// Prevents two small distant updates (e.g. top-left cursor blink + bottom-right status badge)
/// from unioning into a 100% full-window repaint.
pub const DamageList = struct {
    rects: [MaxDamageRects]c.sk_rect_t = undefined,
    len: usize = 0,

    pub fn clear(self: *DamageList) void {
        self.len = 0;
    }

    pub fn add(self: *DamageList, r: c.sk_rect_t) void {
        if (r.right <= r.left or r.bottom <= r.top) return;
        const pad = Rect.outset(r, 8.0, 8.0);
        for (self.rects[0..self.len]) |*existing| {
            if (Rect.intersects(existing.*, pad)) {
                existing.* = Rect.unionRect(existing.*, r);
                return;
            }
        }
        if (self.len < MaxDamageRects) {
            self.rects[self.len] = r;
            self.len += 1;
            return;
        }
        var best_idx: usize = 0;
        var best_delta: f32 = std.math.floatMax(f32);
        for (self.rects[0..self.len], 0..) |existing, i| {
            const u = Rect.unionRect(existing, r);
            const delta = Rect.area(u) - Rect.area(existing);
            if (delta < best_delta) {
                best_delta = delta;
                best_idx = i;
            }
        }
        self.rects[best_idx] = Rect.unionRect(self.rects[best_idx], r);
    }

    pub fn intersects(self: *const DamageList, r: c.sk_rect_t) bool {
        for (self.rects[0..self.len]) |d| {
            if (Rect.intersects(r, d)) return true;
        }
        return false;
    }

    pub fn totalArea(self: *const DamageList) f32 {
        var sum: f32 = 0;
        for (self.rects[0..self.len]) |d| {
            sum += Rect.area(d);
        }
        return sum;
    }
};

test "DamageList: coalesces nearby rects, preserves distant rects, and merges minimal-delta rect at capacity" {
    var dl = DamageList{};
    try std.testing.expectEqual(@as(usize, 0), dl.len);

    // Ignore empty or inverted rects
    dl.add(Rect.xywh(10, 10, 0, 10));
    try std.testing.expectEqual(@as(usize, 0), dl.len);

    // Distant rects stay separate
    dl.add(Rect.xywh(10, 10, 20, 20));
    dl.add(Rect.xywh(500, 400, 30, 20));
    try std.testing.expectEqual(@as(usize, 2), dl.len);
    try std.testing.expectApproxEqAbs(@as(f32, 1000.0), dl.totalArea(), 0.01);
    try std.testing.expect(dl.intersects(Rect.xywh(15, 15, 5, 5)));
    try std.testing.expect(!dl.intersects(Rect.xywh(200, 200, 50, 50)));

    // Nearby rect (within 8pt outset) coalesces into existing rect 0
    dl.add(Rect.xywh(34, 10, 16, 20));
    try std.testing.expectEqual(@as(usize, 2), dl.len);
    try std.testing.expectEqual(@as(f32, 50.0), dl.rects[0].right);

    // Fill up to MaxDamageRects and add one more -> merges into closest rect without exceeding MaxDamageRects
    dl.clear();
    for (0..MaxDamageRects + 2) |i| {
        const x = @as(f32, @floatFromInt(i)) * 100.0;
        dl.add(Rect.xywh(x, 10.0, 20.0, 20.0));
    }
    try std.testing.expectEqual(MaxDamageRects, dl.len);
}
