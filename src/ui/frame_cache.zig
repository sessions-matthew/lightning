//! Per-Frame Two-Phase Synchronization & Memoization Primitives (`FrameLatchTape`, `FrameCacheTable`,
//! and 4-Way LRU Preview Parse Caches) for `ui.Context`.
//!
//! Ensures 100% layout determinism between `Pass.input` and `Pass.paint` when input handlers
//! mutate application state mid-frame, and eliminates duplicate per-frame computation across passes
//! and split panes.

const std = @import("std");
const layout_mod = @import("layout.zig");
const waveform_mod = @import("waveform.zig");
const pdf_viewer_mod = @import("pdf_viewer.zig");

pub const Pass = layout_mod.Pass;
pub const WaveformData = waveform_mod.WaveformData;
pub const PdfDocumentData = pdf_viewer_mod.PdfDocumentData;

pub const MaxLatchSlots = 512;
pub const MaxFrameCacheSlots = 64;
pub const PreviewCacheWays = 4;

/// Per-frame sequential value tape that records scalar/small values (`bool`, integers, enums, floats
/// up to 8 bytes) during `Pass.input` and replays the exact recorded sequence during `Pass.paint`.
/// Prevents mid-frame state mutations in `Pass.input` from causing conditional branch divergence in `Pass.paint`.
pub const FrameLatchTape = struct {
    slots: [MaxLatchSlots]u64 = @splat(0),
    write_len: usize = 0,
    read_idx: usize = 0,

    pub fn resetForInput(self: *FrameLatchTape) void {
        self.write_len = 0;
        self.read_idx = 0;
    }

    pub fn rewindForPaint(self: *FrameLatchTape) void {
        self.read_idx = 0;
    }

    pub fn latch(self: *FrameLatchTape, comptime T: type, pass: Pass, val: T) T {
        comptime {
            std.debug.assert(@sizeOf(T) <= 8);
        }
        if (pass == .input) {
            if (self.write_len < MaxLatchSlots) {
                self.slots[self.write_len] = packValue(T, val);
                self.write_len += 1;
            }
            return val;
        } else {
            if (self.read_idx < self.write_len) {
                const raw = self.slots[self.read_idx];
                self.read_idx += 1;
                return unpackValue(T, raw);
            }
            return val;
        }
    }

    fn packValue(comptime T: type, val: T) u64 {
        var raw: u64 = 0;
        if (@sizeOf(T) > 0) {
            @memcpy(std.mem.asBytes(&raw)[0..@sizeOf(T)], std.mem.asBytes(&val));
        }
        return raw;
    }

    fn unpackValue(comptime T: type, raw: u64) T {
        var val: T = undefined;
        if (@sizeOf(T) > 0) {
            @memcpy(std.mem.asBytes(&val), std.mem.asBytes(&raw)[0..@sizeOf(T)]);
        }
        return val;
    }
};

pub const FrameCacheSlot = struct {
    key_hash: u64 = 0,
    type_hash: u64 = 0,
    ptr: ?*anyopaque = null,
};

/// Fixed-capacity per-frame memoization table storing arena-allocated pointers across `Pass.input`
/// and `Pass.paint` within the same frame. Cleared at the start of `Pass.input` when the frame arena resets.
pub const FrameCacheTable = struct {
    slots: [MaxFrameCacheSlots]FrameCacheSlot = @splat(.{}),
    len: usize = 0,

    pub fn clear(self: *FrameCacheTable) void {
        self.slots = @splat(.{});
        self.len = 0;
    }

    pub fn getOrCompute(
        self: *FrameCacheTable,
        comptime T: type,
        arena: std.mem.Allocator,
        key_hash: u64,
        ctx: anytype,
        comptime computeFn: anytype,
    ) *T {
        const thash = comptime std.hash.Fnv1a_64.hash(@typeName(T));
        for (self.slots[0..self.len]) |slot| {
            if (slot.key_hash == key_hash and slot.type_hash == thash) {
                if (slot.ptr) |p| {
                    return @ptrCast(@alignCast(p));
                }
            }
        }

        const fn_info = @typeInfo(@TypeOf(computeFn)).@"fn";
        const returns_ptr = comptime (fn_info.return_type == *T);

        const result_ptr: *T = if (returns_ptr)
            computeFn(arena, ctx)
        else blk: {
            const p = arena.create(T) catch @panic("useFrameCache: out of frame arena memory");
            p.* = computeFn(arena, ctx);
            break :blk p;
        };

        if (self.len < MaxFrameCacheSlots) {
            self.slots[self.len] = .{
                .key_hash = key_hash,
                .type_hash = thash,
                .ptr = @ptrCast(result_ptr),
            };
            self.len += 1;
        }
        return result_ptr;
    }
};

pub const VcdCacheSlot = struct {
    source_ptr: ?[*]const u8 = null,
    source_len: usize = 0,
    data: ?*const WaveformData = null,
    last_used_tick: u32 = 0,
};

pub const PdfCacheSlot = struct {
    bytes_ptr: ?[*]const u8 = null,
    bytes_len: usize = 0,
    path_ptr: ?[*]const u8 = null,
    path_len: usize = 0,
    data: ?*const PdfDocumentData = null,
    last_used_tick: u32 = 0,
};
