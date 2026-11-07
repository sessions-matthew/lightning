//! Scriptable Frame Profiler, Telemetry Collector, and Chrome/Perfetto Trace Exporter.
//! Provides zero-overhead, completely headless profiling tools with machine-readable
//! JSON output, automated synthetic interaction scenarios, and microsecond phase timings.

const std = @import("std");
const builtin = @import("builtin");
const app_api = @import("app_api.zig");
const fs_util = @import("fs_util.zig");
const objc = @import("macos/objc.zig");
const PlatformContext = app_api.PlatformContext;
const is_windows = (builtin.os.tag == .windows);

/// Supported automated non-interactive interaction scenarios for headless benchmarking.
pub const ScenarioKind = enum {
    none,
    typing,
    scroll,
    idle,
    workbench,
    file_picker,
    file_menu,

    pub fn fromString(str: []const u8) ScenarioKind {
        if (std.mem.eql(u8, str, "typing")) return .typing;
        if (std.mem.eql(u8, str, "scroll")) return .scroll;
        if (std.mem.eql(u8, str, "idle")) return .idle;
        if (std.mem.eql(u8, str, "workbench")) return .workbench;
        if (std.mem.eql(u8, str, "file_picker")) return .file_picker;
        if (std.mem.eql(u8, str, "file_menu")) return .file_menu;
        return .none;
    }
};

/// High-resolution monotonic timestamp in nanoseconds.
pub inline fn nowNs() u64 {
    return objc.getMonotonicNs();
}

// Apple Instruments / XNU kernel tracepoints (`<sys/kdebug_signpost.h>`, `Points of Interest` track)
const xnu_signpost = struct {
    extern "c" fn kdebug_signpost_start(code: u32, arg1: usize, arg2: usize, arg3: usize, arg4: usize) c_int;
    extern "c" fn kdebug_signpost_end(code: u32, arg1: usize, arg2: usize, arg3: usize, arg4: usize) c_int;
};

pub const SignpostCode = enum(u32) {
    frame = 1,
    events = 2,
    app_tick = 3,
    gpu_flush = 4,
    metal_present = 5,
};

pub inline fn signpostStart(code: SignpostCode, arg1: usize) void {
    if (comptime @import("builtin").os.tag == .macos) {
        _ = xnu_signpost.kdebug_signpost_start(@intFromEnum(code), arg1, 0, 0, 0);
    }
}

pub inline fn signpostEnd(code: SignpostCode, arg1: usize) void {
    if (comptime @import("builtin").os.tag == .macos) {
        _ = xnu_signpost.kdebug_signpost_end(@intFromEnum(code), arg1, 0, 0, 0);
    }
}

fn writeBufferToFile(path: []const u8, data: []const u8) !void {
    var path_buf: [1024]u8 = undefined;
    if (path.len >= path_buf.len) return error.PathTooLong;
    @memcpy(path_buf[0..path.len], path);
    path_buf[path.len] = 0;
    const path_z: [*:0]const u8 = @ptrCast(path_buf[0..path.len]);

    const f = std.c.fopen(path_z, "wb") orelse return error.CannotOpenFile;
    defer _ = std.c.fclose(f);
    _ = std.c.fwrite(data.ptr, 1, data.len, f);
}

/// Chrome / Perfetto Catapult Trace Event.
pub const TraceEvent = struct {
    name: []const u8,
    cat: []const u8,
    ph: u8 = 'X', // 'X' = Complete event with ts and dur
    ts_us: u64,
    dur_us: u64,
    pid: u32 = 1,
    tid: u32 = 1,
};

/// Collects timeline events and exports them to standard Chrome / Perfetto JSON format.
pub const TraceCollector = struct {
    allocator: std.mem.Allocator,
    events: std.ArrayList(TraceEvent) = .empty,
    enabled: bool = false,
    base_ns: u64 = 0,

    pub fn init(allocator: std.mem.Allocator, enabled: bool) TraceCollector {
        return .{
            .allocator = allocator,
            .events = if (enabled) (std.ArrayList(TraceEvent).initCapacity(allocator, 16384) catch .empty) else .empty,
            .enabled = enabled,
            .base_ns = if (enabled) nowNs() else 0,
        };
    }

    pub fn deinit(self: *TraceCollector) void {
        self.events.deinit(self.allocator);
    }

    pub fn record(self: *TraceCollector, name: []const u8, cat: []const u8, start_ns: u64, end_ns: u64) void {
        if (!self.enabled) return;
        const ts_us = if (start_ns >= self.base_ns) (start_ns - self.base_ns) / 1000 else 0;
        const dur_us = if (end_ns >= start_ns) (end_ns - start_ns) / 1000 else 0;
        self.events.append(self.allocator, .{
            .name = name,
            .cat = cat,
            .ph = 'X',
            .ts_us = ts_us,
            .dur_us = dur_us,
            .pid = 1,
            .tid = 1,
        }) catch {};
    }

    pub fn startLive(self: *TraceCollector) void {
        self.events.clearRetainingCapacity();
        self.base_ns = nowNs();
        self.enabled = true;
    }

    pub fn stopAndWriteJsonFile(self: *TraceCollector, path: []const u8) !usize {
        const count = self.events.items.len;
        self.enabled = true;
        defer self.enabled = false;
        try self.writeJsonFileForce(path);
        return count;
    }

    pub fn writeJsonFile(self: *const TraceCollector, path: []const u8) !void {
        if (!self.enabled or self.events.items.len == 0) return;
        try self.writeJsonFileForce(path);
    }

    pub fn writeJsonFileForce(self: *const TraceCollector, path: []const u8) !void {
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(self.allocator);

        var buf: [256]u8 = undefined;
        try out.appendSlice(self.allocator, "{\"traceEvents\":[\n");
        for (self.events.items, 0..) |ev, idx| {
            if (idx > 0) try out.appendSlice(self.allocator, ",\n");
            const line = std.fmt.bufPrint(
                &buf,
                "  {{\"name\":\"{s}\",\"cat\":\"{s}\",\"ph\":\"{c}\",\"ts\":{d},\"dur\":{d},\"pid\":{d},\"tid\":{d}}}",
                .{ ev.name, ev.cat, ev.ph, ev.ts_us, ev.dur_us, ev.pid, ev.tid },
            ) catch continue;
            try out.appendSlice(self.allocator, line);
        }
        try out.appendSlice(self.allocator, "\n]}\n");
        try writeBufferToFile(path, out.items);
    }
};

/// Per-frame phase timestamps in nanoseconds.
pub const FrameSample = struct {
    total_ns: u64,
    events_ns: u64,
    input_ns: u64,
    paint_ns: u64,
    gpu_flush_ns: u64,
    metal_present_ns: u64,
    damage_pct: f32,
};

/// Computes statistical distributions (percentiles, mean, stddev) over collected frame metrics.
pub const FrameMetricsCollector = struct {
    pub const RecentWindowCapacity: usize = 256;
    pub const MaxRetainedSamples: usize = 65536;

    allocator: std.mem.Allocator,
    samples: std.ArrayList(FrameSample) = .empty,
    start_time_ns: u64 = 0,
    end_time_ns: u64 = 0,

    // Zero-allocation rolling ring buffer for the most recent 256 painted frames
    recent_ring: [RecentWindowCapacity]FrameSample = @splat(std.mem.zeroes(FrameSample)),
    recent_head: usize = 0,
    recent_count: usize = 0,
    recent_start_ns: u64 = 0,
    last_damage_pct: f32 = 0.0,

    // Idle sleep & wakeup diagnostics
    idle_wakeups: usize = 0,
    continuous_redraw_frames: usize = 0,

    // Resource metrics
    peak_vram_bytes: usize = 0,
    final_vram_bytes: usize = 0,
    peak_gpu_resources: i32 = 0,
    final_gpu_resources: i32 = 0,

    text_lookups: usize = 0,
    text_hits: usize = 0,
    text_misses: usize = 0,
    text_evictions: usize = 0,

    pub fn init(allocator: std.mem.Allocator) FrameMetricsCollector {
        const now = nowNs();
        return .{
            .allocator = allocator,
            .samples = .empty,
            .start_time_ns = now,
            .end_time_ns = now,
            .recent_start_ns = now,
        };
    }

    pub fn deinit(self: *FrameMetricsCollector) void {
        self.samples.deinit(self.allocator);
    }

    pub fn reset(self: *FrameMetricsCollector) void {
        const now = nowNs();
        self.samples.clearRetainingCapacity();
        self.start_time_ns = now;
        self.end_time_ns = now;
        self.recent_head = 0;
        self.recent_count = 0;
        self.recent_start_ns = now;
        self.last_damage_pct = 0.0;
        self.idle_wakeups = 0;
        self.continuous_redraw_frames = 0;
        self.peak_vram_bytes = self.final_vram_bytes;
        self.peak_gpu_resources = self.final_gpu_resources;
    }

    pub fn recordIdleWakeup(self: *FrameMetricsCollector, ctx: *const PlatformContext) void {
        self.idle_wakeups += 1;
        if (ctx.needs_continuous_redraw) {
            self.continuous_redraw_frames += 1;
        }
        self.text_lookups = ctx.text_cache_lookups;
        self.text_hits = ctx.text_cache_hits;
        self.text_misses = ctx.text_cache_misses;
        self.text_evictions = ctx.text_cache_evictions;
    }

    pub fn recordFrame(
        self: *FrameMetricsCollector,
        sample: FrameSample,
        vram_bytes: usize,
        vram_resources: i32,
        ctx: *const PlatformContext,
    ) void {
        const now = nowNs();
        if (self.samples.items.len < MaxRetainedSamples) {
            self.samples.append(self.allocator, sample) catch {};
        }
        if (self.recent_count == 0) {
            self.recent_start_ns = now;
        }
        self.recent_ring[self.recent_head] = sample;
        self.recent_head = (self.recent_head + 1) % RecentWindowCapacity;
        if (self.recent_count < RecentWindowCapacity) {
            self.recent_count += 1;
        }
        self.last_damage_pct = sample.damage_pct;
        if (ctx.needs_continuous_redraw) {
            self.continuous_redraw_frames += 1;
        }

        if (vram_bytes > self.peak_vram_bytes) {
            self.peak_vram_bytes = vram_bytes;
        }
        self.final_vram_bytes = vram_bytes;
        if (vram_resources > self.peak_gpu_resources) {
            self.peak_gpu_resources = vram_resources;
        }
        self.final_gpu_resources = vram_resources;

        self.text_lookups = ctx.text_cache_lookups;
        self.text_hits = ctx.text_cache_hits;
        self.text_misses = ctx.text_cache_misses;
        self.text_evictions = ctx.text_cache_evictions;
        self.end_time_ns = now;
    }

    /// Copies the most recent `min(out.len, self.recent_count)` frames into `out` in chronological order (oldest -> newest).
    pub fn getRecentSamplesChronological(self: *const FrameMetricsCollector, out: []FrameSample) usize {
        const n = @min(out.len, self.recent_count);
        if (n == 0) return 0;
        const oldest_idx = (self.recent_head + RecentWindowCapacity - n) % RecentWindowCapacity;
        for (0..n) |i| {
            out[i] = self.recent_ring[(oldest_idx + i) % RecentWindowCapacity];
        }
        return n;
    }

    pub const Stats = struct {
        frame_count: usize,
        total_time_ms: f64,
        avg_fps: f64,
        mean_damage_pct: f64 = 0.0,
        latency_ms: struct {
            min: f64,
            mean: f64,
            p50: f64,
            p95: f64,
            p99: f64,
            max: f64,
            stddev: f64,
        },
        jank: struct {
            frames_over_16ms: usize,
            frames_over_8ms: usize,
            jank_rate_pct: f64,
        },
        phases_mean_us: struct {
            events: f64,
            input_layout: f64,
            paint_record: f64,
            gpu_flush: f64,
            metal_present: f64,
        },
        text_cache: struct {
            lookups: usize,
            hits: usize,
            misses: usize,
            evictions: usize,
            hit_ratio_pct: f64,
        },
        gpu_vram: struct {
            peak_bytes: usize,
            final_bytes: usize,
            peak_resources: i32,
            final_resources: i32 = 0,
        },
    };

    fn computeStatsFromSlice(
        self: *const FrameMetricsCollector,
        slice: []const FrameSample,
        wall_start_ns: u64,
        wall_end_ns: u64,
    ) Stats {
        const count = slice.len;
        if (count == 0) {
            return std.mem.zeroes(Stats);
        }

        const total_wall_ns = if (wall_end_ns > wall_start_ns)
            wall_end_ns - wall_start_ns
        else
            1;
        const total_time_ms = @as(f64, @floatFromInt(total_wall_ns)) / 1_000_000.0;
        const avg_fps = if (total_time_ms > 0) (@as(f64, @floatFromInt(count)) / (total_time_ms / 1000.0)) else 0;

        var stack_latencies: [RecentWindowCapacity]u64 = undefined;
        const heap_latencies = if (count > RecentWindowCapacity)
            (self.allocator.alloc(u64, count) catch return std.mem.zeroes(Stats))
        else
            null;
        defer if (heap_latencies) |hl| self.allocator.free(hl);
        const latencies_ns: []u64 = if (heap_latencies) |hl| hl else stack_latencies[0..count];

        var total_lat_ns: u64 = 0;
        var sum_events: u64 = 0;
        var sum_input: u64 = 0;
        var sum_paint: u64 = 0;
        var sum_flush: u64 = 0;
        var sum_present: u64 = 0;
        var sum_damage_pct: f64 = 0.0;
        var jank_16ms: usize = 0;
        var jank_8ms: usize = 0;

        for (slice, 0..) |s, i| {
            latencies_ns[i] = s.total_ns;
            total_lat_ns += s.total_ns;
            sum_events += s.events_ns;
            sum_input += s.input_ns;
            sum_paint += s.paint_ns;
            sum_flush += s.gpu_flush_ns;
            sum_present += s.metal_present_ns;
            sum_damage_pct += @as(f64, s.damage_pct);
            if (s.total_ns > 16_666_667) jank_16ms += 1;
            if (s.total_ns > 8_333_333) jank_8ms += 1;
        }

        std.mem.sort(u64, latencies_ns, {}, std.sort.asc(u64));

        const min_ms = @as(f64, @floatFromInt(latencies_ns[0])) / 1_000_000.0;
        const max_ms = @as(f64, @floatFromInt(latencies_ns[count - 1])) / 1_000_000.0;
        const mean_ms = (@as(f64, @floatFromInt(total_lat_ns)) / @as(f64, @floatFromInt(count))) / 1_000_000.0;

        const p50_idx = (count * 50) / 100;
        const p95_idx = (count * 95) / 100;
        const p99_idx = (count * 99) / 100;

        const p50_ms = @as(f64, @floatFromInt(latencies_ns[p50_idx])) / 1_000_000.0;
        const p95_ms = @as(f64, @floatFromInt(latencies_ns[@min(p95_idx, count - 1)])) / 1_000_000.0;
        const p99_ms = @as(f64, @floatFromInt(latencies_ns[@min(p99_idx, count - 1)])) / 1_000_000.0;

        var variance_sum: f64 = 0;
        for (latencies_ns) |lat| {
            const lat_ms = @as(f64, @floatFromInt(lat)) / 1_000_000.0;
            const diff = lat_ms - mean_ms;
            variance_sum += diff * diff;
        }
        const stddev_ms = @sqrt(variance_sum / @as(f64, @floatFromInt(count)));

        const c_f64 = @as(f64, @floatFromInt(count));
        const hit_pct = if (self.text_lookups > 0)
            (@as(f64, @floatFromInt(self.text_hits)) / @as(f64, @floatFromInt(self.text_lookups))) * 100.0
        else
            100.0;

        return .{
            .frame_count = count,
            .total_time_ms = total_time_ms,
            .avg_fps = avg_fps,
            .mean_damage_pct = sum_damage_pct / c_f64,
            .latency_ms = .{
                .min = min_ms,
                .mean = mean_ms,
                .p50 = p50_ms,
                .p95 = p95_ms,
                .p99 = p99_ms,
                .max = max_ms,
                .stddev = stddev_ms,
            },
            .jank = .{
                .frames_over_16ms = jank_16ms,
                .frames_over_8ms = jank_8ms,
                .jank_rate_pct = (@as(f64, @floatFromInt(jank_16ms)) / c_f64) * 100.0,
            },
            .phases_mean_us = .{
                .events = (@as(f64, @floatFromInt(sum_events)) / c_f64) / 1000.0,
                .input_layout = (@as(f64, @floatFromInt(sum_input)) / c_f64) / 1000.0,
                .paint_record = (@as(f64, @floatFromInt(sum_paint)) / c_f64) / 1000.0,
                .gpu_flush = (@as(f64, @floatFromInt(sum_flush)) / c_f64) / 1000.0,
                .metal_present = (@as(f64, @floatFromInt(sum_present)) / c_f64) / 1000.0,
            },
            .text_cache = .{
                .lookups = self.text_lookups,
                .hits = self.text_hits,
                .misses = self.text_misses,
                .evictions = self.text_evictions,
                .hit_ratio_pct = hit_pct,
            },
            .gpu_vram = .{
                .peak_bytes = self.peak_vram_bytes,
                .final_bytes = self.final_vram_bytes,
                .peak_resources = self.peak_gpu_resources,
                .final_resources = self.final_gpu_resources,
            },
        };
    }

    pub fn computeStats(self: *const FrameMetricsCollector) Stats {
        return self.computeStatsFromSlice(self.samples.items, self.start_time_ns, self.end_time_ns);
    }

    pub fn computeRecentStats(self: *const FrameMetricsCollector) Stats {
        return self.computeStatsFromSlice(self.recent_ring[0..self.recent_count], self.recent_start_ns, self.end_time_ns);
    }

    pub fn writeJsonFile(self: *const FrameMetricsCollector, path: []const u8) !void {
        const stats = self.computeStats();
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(self.allocator);

        var buf: [1024]u8 = undefined;
        const json_slice = std.fmt.bufPrint(
            &buf,
            \\{{
            \\  "benchmark": "skia_editor",
            \\  "frame_count": {d},
            \\  "total_time_ms": {d:.2},
            \\  "avg_fps": {d:.2},
            \\  "latency_ms": {{
            \\    "min": {d:.3},
            \\    "mean": {d:.3},
            \\    "p50": {d:.3},
            \\    "p95": {d:.3},
            \\    "p99": {d:.3},
            \\    "max": {d:.3},
            \\    "stddev": {d:.3}
            \\  }},
            \\  "jank": {{
            \\    "frames_over_16ms": {d},
            \\    "frames_over_8ms": {d},
            \\    "jank_rate_pct": {d:.2}
            \\  }},
            \\  "phases_mean_us": {{
            \\    "events": {d:.1},
            \\    "input_layout": {d:.1},
            \\    "paint_record": {d:.1},
            \\    "gpu_flush": {d:.1},
            \\    "metal_present": {d:.1}
            \\  }},
            \\  "text_cache": {{
            \\    "lookups": {d},
            \\    "hits": {d},
            \\    "misses": {d},
            \\    "evictions": {d},
            \\    "hit_ratio_pct": {d:.2}
            \\  }},
            \\  "gpu_vram": {{
            \\    "peak_bytes": {d},
            \\    "final_bytes": {d},
            \\    "peak_resources": {d}
            \\  }}
            \\}}
            \\
        ,
            .{
                stats.frame_count,
                stats.total_time_ms,
                stats.avg_fps,
                stats.latency_ms.min,
                stats.latency_ms.mean,
                stats.latency_ms.p50,
                stats.latency_ms.p95,
                stats.latency_ms.p99,
                stats.latency_ms.max,
                stats.latency_ms.stddev,
                stats.jank.frames_over_16ms,
                stats.jank.frames_over_8ms,
                stats.jank.jank_rate_pct,
                stats.phases_mean_us.events,
                stats.phases_mean_us.input_layout,
                stats.phases_mean_us.paint_record,
                stats.phases_mean_us.gpu_flush,
                stats.phases_mean_us.metal_present,
                stats.text_cache.lookups,
                stats.text_cache.hits,
                stats.text_cache.misses,
                stats.text_cache.evictions,
                stats.text_cache.hit_ratio_pct,
                stats.gpu_vram.peak_bytes,
                stats.gpu_vram.final_bytes,
                stats.gpu_vram.peak_resources,
            },
        ) catch return error.BufferTooSmall;
        try writeBufferToFile(path, json_slice);
    }

    pub fn printSummary(self: *const FrameMetricsCollector) void {
        const stats = self.computeStats();
        std.debug.print(
            \\================================================================================
            \\EDITOR SCRIPTABLE PERFORMANCE BENCHMARK SUMMARY
            \\================================================================================
            \\Frames Rendered:      {d}
            \\Total Elapsed Time:   {d:.1} ms
            \\Average Throughput:   {d:.2} FPS
            \\
            \\Frame Latencies (ms):
            \\  Min:                {d:.3} ms
            \\  Mean:               {d:.3} ms
            \\  P50 (Median):       {d:.3} ms
            \\  P95:                {d:.3} ms
            \\  P99:                {d:.3} ms
            \\  Max:                {d:.3} ms
            \\  StdDev:             {d:.3} ms
            \\
            \\Frame Budget & Jank:
            \\  Frames > 16.6ms (60Hz):  {d} ({d:.2}%)
            \\  Frames > 8.33ms (120Hz): {d}
            \\
            \\Phase Breakdown (average µs / frame):
            \\  AppKit Event Drain: {d:.1} µs
            \\  Layout & Input:     {d:.1} µs
            \\  Skia Paint Record:  {d:.1} µs
            \\  Ganesh GPU Flush:   {d:.1} µs
            \\  CAMetal Present:    {d:.1} µs
            \\
            \\TextCache Telemetry:
            \\  Total Lookups:      {d}
            \\  Cache Hits:         {d} ({d:.2}%)
            \\  Cache Misses:       {d}
            \\  Evictions:          {d}
            \\
            \\GPU VRAM Usage (Skia Ganesh DirectContext):
            \\  Peak VRAM:          {d:.2} MB ({d} bytes)
            \\  Final VRAM:         {d:.2} MB
            \\  Active Resources:   {d}
            \\================================================================================
            \\
        ,
            .{
                stats.frame_count,
                stats.total_time_ms,
                stats.avg_fps,
                stats.latency_ms.min,
                stats.latency_ms.mean,
                stats.latency_ms.p50,
                stats.latency_ms.p95,
                stats.latency_ms.p99,
                stats.latency_ms.max,
                stats.latency_ms.stddev,
                stats.jank.frames_over_16ms,
                stats.jank.jank_rate_pct,
                stats.jank.frames_over_8ms,
                stats.phases_mean_us.events,
                stats.phases_mean_us.input_layout,
                stats.phases_mean_us.paint_record,
                stats.phases_mean_us.gpu_flush,
                stats.phases_mean_us.metal_present,
                stats.text_cache.lookups,
                stats.text_cache.hits,
                stats.text_cache.hit_ratio_pct,
                stats.text_cache.misses,
                stats.text_cache.evictions,
                @as(f64, @floatFromInt(stats.gpu_vram.peak_bytes)) / (1024.0 * 1024.0),
                stats.gpu_vram.peak_bytes,
                @as(f64, @floatFromInt(stats.gpu_vram.final_bytes)) / (1024.0 * 1024.0),
                stats.gpu_vram.peak_resources,
            },
        );
    }
};

/// Injects synthetic inputs into PlatformContext for automated scriptable stress testing.
pub fn runScenarioTick(scenario: ScenarioKind, frame: u64, ctx: *PlatformContext) void {
    switch (scenario) {
        .none, .idle => {},
        .typing => {
            const sample_tokens = "pub fn executeWorkload(val: u32) !void {\n    const res = val * 2;\n    return res;\n}\n";
            const idx = @as(usize, @intCast(frame % sample_tokens.len));
            const char = sample_tokens[idx];

            if (char == '\n') {
                ctx.pushKeyEvent(.{ .key = .enter });
            } else if (char == ' ') {
                ctx.pushTextInput(" ");
            } else {
                const char_slice: [1]u8 = .{char};
                ctx.pushTextInput(&char_slice);
            }

            if (frame % 30 == 0) {
                ctx.pushKeyEvent(.{ .key = .left });
            }
        },
        .scroll => {
            const phase = @as(f32, @floatFromInt(frame % 120));
            const dy: f32 = if (phase < 60.0) -16.0 else 16.0;
            ctx.scroll_dy = dy;
        },
        .workbench => {
            if (frame == 1) {
                // Toggle Explorer sidebar (Cmd/Ctrl+B)
                ctx.pushKeyEvent(.{ .key = .key_b, .cmd = true, .ctrl = true });
            } else if (frame == 2) {
                // Open Quick Open / Command Palette (Cmd/Ctrl+P)
                ctx.pushKeyEvent(.{ .key = .key_p, .cmd = true, .ctrl = true });
            } else if (frame == 4) {
                // Select first workspace file
                ctx.pushKeyEvent(.{ .key = .enter });
            }
        },
        .file_picker => {
            if (frame == 1) {
                ctx.pushKeyEvent(.{ .key = .key_b, .cmd = true, .ctrl = true });
            } else if (frame == 2) {
                // Open in-app File & Workspace Folder Picker (Cmd/Ctrl+O)
                ctx.pushKeyEvent(.{ .key = .key_o, .cmd = true, .ctrl = true });
            }
        },
        .file_menu => {
            if (frame == 1) {
                ctx.pushKeyEvent(.{ .key = .key_b, .cmd = true, .ctrl = true });
                ctx.pushKeyEvent(.{ .key = .key_p, .cmd = true, .ctrl = true });
            } else if (frame == 2) {
                ctx.pushKeyEvent(.{ .key = .enter });
            } else if (frame == 3) {
                // Click the titlebar "File" menu button at (24, 18)
                ctx.mouse_x = 24.0;
                ctx.mouse_y = 18.0;
                ctx.mouse_down = true;
                ctx.mouse_pressed = true;
            }
        },
    }
}

// ============================================================================
// Live Out-of-Band Performance Debug Socket Server & Attach Client
// ============================================================================

const posix_sock = if (!is_windows) struct {
    pub const AF_UNIX: c_int = 1;
    pub const SOCK_STREAM: c_int = 1;
    pub const F_GETFL: c_int = 3;
    pub const F_SETFL: c_int = 4;
    pub const O_NONBLOCK: c_int = if (builtin.os.tag == .linux) 0x0800 else 0x0004;
    pub const SOL_SOCKET: c_int = 0xffff;
    pub const SO_NOSIGPIPE: c_int = 0x1022;
    pub const POLLIN: i16 = 0x0001;
    pub const POLLHUP: i16 = 0x0010;
    pub const POLLERR: i16 = 0x0008;

    pub const PollFd = extern struct {
        fd: c_int,
        events: i16,
        revents: i16,
    };

    pub const sockaddr_un = if (builtin.os.tag == .linux) extern struct {
        sun_family: u16 = 1,
        sun_path: [108]u8 = @splat(0),
    } else extern struct {
        sun_len: u8 = @sizeOf(sockaddr_un),
        sun_family: u8 = 1,
        sun_path: [104]u8 = @splat(0),
    };

    extern "c" fn getpid() c_int;
    extern "c" fn socket(domain: c_int, sock_type: c_int, protocol: c_int) c_int;
    extern "c" fn bind(sockfd: c_int, addr: *const sockaddr_un, addrlen: u32) c_int;
    extern "c" fn listen(sockfd: c_int, backlog: c_int) c_int;
    extern "c" fn accept(sockfd: c_int, addr: ?*sockaddr_un, addrlen: ?*u32) c_int;
    extern "c" fn connect(sockfd: c_int, addr: *const sockaddr_un, addrlen: u32) c_int;
    extern "c" fn setsockopt(sockfd: c_int, level: c_int, optname: c_int, optval: *const anyopaque, optlen: u32) c_int;
    extern "c" fn unlink(path: [*:0]const u8) c_int;
    extern "c" fn poll(fds: [*]PollFd, nfds: c_uint, timeout: c_int) c_int;
} else struct {};

fn setSocketNonBlockingAndNoSigpipe(fd: c_int) void {
    if (comptime is_windows) return;
    if (comptime builtin.os.tag == .macos) {
        var one: c_int = 1;
        _ = posix_sock.setsockopt(fd, posix_sock.SOL_SOCKET, posix_sock.SO_NOSIGPIPE, &one, @sizeOf(c_int));
    }
    const flags = std.c.fcntl(fd, posix_sock.F_GETFL, @as(c_int, 0));
    if (flags >= 0) {
        _ = std.c.fcntl(fd, posix_sock.F_SETFL, flags | posix_sock.O_NONBLOCK);
    }
}

fn fillSockaddrUn(path: []const u8) ?posix_sock.sockaddr_un {
    if (comptime is_windows) return null;
    var addr = posix_sock.sockaddr_un{};
    if (path.len == 0 or path.len >= addr.sun_path.len) return null;
    @memcpy(addr.sun_path[0..path.len], path);
    addr.sun_path[path.len] = 0;
    return addr;
}

fn writeAllToSocket(fd: c_int, data: []const u8) void {
    if (comptime is_windows) return;
    var written: usize = 0;
    var retries: usize = 0;
    while (written < data.len and retries < 50) {
        const rc = std.c.write(fd, data[written..].ptr, data.len - written);
        if (rc > 0) {
            written += @intCast(rc);
            retries = 0;
        } else {
            var pfd = [1]posix_sock.PollFd{.{
                .fd = fd,
                .events = 0x0004, // POLLOUT
                .revents = 0,
            }};
            _ = posix_sock.poll(&pfd, 1, 2);
            retries += 1;
        }
    }
}

/// Non-blocking Unix domain socket debug server (`/tmp/lightning-debug-<pid>.sock`)
/// that allows attaching to a running editor instance to inspect live frame metrics,
/// scissor damage rects, `TextCache` hit/eviction rates, GPU VRAM residency,
/// idle-sleep health, and capture Chrome/Perfetto traces on the fly.
pub const LiveDebugServer = struct {
    allocator: std.mem.Allocator,
    listen_fd: c_int = -1,
    client_fd: c_int = -1,
    pid: i32 = 0,
    sock_path: [104:0]u8 = @splat(0),
    sock_path_len: usize = 0,
    req_buf: [512]u8 = undefined,
    req_len: usize = 0,

    pub fn init(allocator: std.mem.Allocator) LiveDebugServer {
        if (comptime is_windows) {
            return .{ .allocator = allocator };
        }
        const pid = posix_sock.getpid();
        var path_buf: [100]u8 = undefined;
        const default_path = std.fmt.bufPrint(&path_buf, "/tmp/lightning-debug-{d}.sock", .{pid}) catch {
            return .{ .allocator = allocator, .pid = pid };
        };
        var srv = initWithPath(allocator, default_path);
        srv.pid = pid;
        return srv;
    }

    pub fn initWithPath(allocator: std.mem.Allocator, custom_path: []const u8) LiveDebugServer {
        var self = LiveDebugServer{
            .allocator = allocator,
            .pid = if (comptime !is_windows) posix_sock.getpid() else 0,
        };
        if (comptime is_windows) return self;

        const addr = fillSockaddrUn(custom_path) orelse return self;
        @memcpy(self.sock_path[0..custom_path.len], custom_path);
        self.sock_path[custom_path.len] = 0;
        self.sock_path_len = custom_path.len;

        _ = posix_sock.unlink(&self.sock_path);

        const fd = posix_sock.socket(posix_sock.AF_UNIX, posix_sock.SOCK_STREAM, 0);
        if (fd < 0) return self;

        setSocketNonBlockingAndNoSigpipe(fd);

        if (posix_sock.bind(fd, &addr, @sizeOf(posix_sock.sockaddr_un)) != 0) {
            _ = std.c.close(fd);
            return self;
        }
        if (posix_sock.listen(fd, 8) != 0) {
            _ = std.c.close(fd);
            _ = posix_sock.unlink(&self.sock_path);
            return self;
        }
        self.listen_fd = fd;
        return self;
    }

    pub fn deinit(self: *LiveDebugServer) void {
        if (comptime is_windows) return;
        if (self.client_fd >= 0) {
            _ = std.c.close(self.client_fd);
            self.client_fd = -1;
        }
        if (self.listen_fd >= 0) {
            _ = std.c.close(self.listen_fd);
            self.listen_fd = -1;
        }
        if (self.sock_path_len > 0) {
            _ = posix_sock.unlink(&self.sock_path);
            self.sock_path_len = 0;
        }
    }

    pub fn socketPath(self: *const LiveDebugServer) []const u8 {
        return self.sock_path[0..self.sock_path_len];
    }

    /// Cheap non-blocking poll called once per event-loop wakeup.
    /// Returns `true` if a debug command requested an immediate visual redraw.
    pub fn poll(
        self: *LiveDebugServer,
        ctx: *PlatformContext,
        metrics: *FrameMetricsCollector,
        tracer: *TraceCollector,
    ) bool {
        if (comptime is_windows) return false;
        if (self.listen_fd < 0) return false;

        var needs_redraw = false;

        // Accept new client if none is currently mid-request
        if (self.client_fd < 0) {
            const cfd = posix_sock.accept(self.listen_fd, null, null);
            if (cfd >= 0) {
                setSocketNonBlockingAndNoSigpipe(cfd);
                self.client_fd = cfd;
                self.req_len = 0;

                // Wait up to 5ms if client just connected so single-shot CLI requests complete in 1 tick
                var pfd = [1]posix_sock.PollFd{.{
                    .fd = cfd,
                    .events = posix_sock.POLLIN,
                    .revents = 0,
                }};
                _ = posix_sock.poll(&pfd, 1, 5);
            }
        }

        if (self.client_fd >= 0) {
            const cfd = self.client_fd;
            while (self.req_len < self.req_buf.len) {
                const rc = std.c.read(cfd, self.req_buf[self.req_len..].ptr, self.req_buf.len - self.req_len);
                if (rc > 0) {
                    self.req_len += @intCast(rc);
                    if (std.mem.indexOfScalar(u8, self.req_buf[0..self.req_len], '\n') != null) {
                        break;
                    }
                } else if (rc == 0) {
                    // Client sent EOF (e.g. `echo "status" | nc -U ...`)
                    break;
                } else {
                    // EAGAIN / would block
                    if (std.mem.indexOfScalar(u8, self.req_buf[0..self.req_len], '\n') == null) {
                        return needs_redraw;
                    }
                    break;
                }
            }

            const raw_line = std.mem.trim(u8, self.req_buf[0..self.req_len], " \t\r\n");
            var out: std.ArrayList(u8) = .empty;
            defer out.deinit(self.allocator);

            if (self.handleCommand(raw_line, ctx, metrics, tracer, &out)) |redraw| {
                if (redraw) needs_redraw = true;
            } else |_| {}

            if (out.items.len > 0) {
                writeAllToSocket(cfd, out.items);
            }
            _ = std.c.close(cfd);
            self.client_fd = -1;
            self.req_len = 0;
        }

        return needs_redraw;
    }

    pub fn handleCommand(
        self: *LiveDebugServer,
        raw_cmd: []const u8,
        ctx: *PlatformContext,
        metrics: *FrameMetricsCollector,
        tracer: *TraceCollector,
        out: *std.ArrayList(u8),
    ) !bool {
        const cmd = std.mem.trim(u8, raw_cmd, " \t\r\n");
        if (cmd.len == 0 or std.mem.eql(u8, cmd, "status")) {
            try self.writeStatusReport(ctx, metrics, tracer, out);
            return false;
        }
        if (std.mem.eql(u8, cmd, "metrics") or std.mem.eql(u8, cmd, "json")) {
            try self.writeMetricsJson(ctx, metrics, tracer, out);
            return false;
        }
        if (std.mem.eql(u8, cmd, "frames") or std.mem.startsWith(u8, cmd, "frames ")) {
            var limit: usize = 20;
            if (cmd.len > "frames ".len) {
                const arg = std.mem.trim(u8, cmd["frames ".len..], " \t");
                limit = std.fmt.parseInt(usize, arg, 10) catch 20;
            }
            try self.writeRecentFramesReport(ctx, metrics, @min(limit, 64), out);
            return false;
        }
        if (std.mem.eql(u8, cmd, "trace start")) {
            tracer.startLive();
            ctx.force_full_redraw = true;
            var buf: [256]u8 = undefined;
            const msg = std.fmt.bufPrint(
                &buf,
                "{{\"ok\":true,\"trace_enabled\":true,\"pid\":{d},\"message\":\"Live Perfetto trace recording started. Run `--attach trace stop [path]` to export.\"}}\n",
                .{self.pid},
            ) catch return true;
            try out.appendSlice(self.allocator, msg);
            return true;
        }
        if (std.mem.eql(u8, cmd, "trace status")) {
            var buf: [256]u8 = undefined;
            const msg = std.fmt.bufPrint(
                &buf,
                "{{\"ok\":true,\"trace_enabled\":{},\"events_buffered\":{d},\"pid\":{d}}}\n",
                .{ tracer.enabled, tracer.events.items.len, self.pid },
            ) catch return false;
            try out.appendSlice(self.allocator, msg);
            return false;
        }
        if (std.mem.eql(u8, cmd, "trace stop") or std.mem.startsWith(u8, cmd, "trace stop ")) {
            var default_path_buf: [128]u8 = undefined;
            const default_path = std.fmt.bufPrint(&default_path_buf, "/tmp/lightning-trace-{d}.json", .{self.pid}) catch "/tmp/lightning-trace.json";
            const custom_path = if (cmd.len > "trace stop ".len)
                std.mem.trim(u8, cmd["trace stop ".len..], " \t")
            else
                "";
            const target_path = if (custom_path.len > 0) custom_path else default_path;

            const ev_count = tracer.stopAndWriteJsonFile(target_path) catch |err| {
                var err_buf: [256]u8 = undefined;
                const msg = std.fmt.bufPrint(
                    &err_buf,
                    "{{\"ok\":false,\"error\":\"{s}\",\"path\":\"{s}\"}}\n",
                    .{ @errorName(err), target_path },
                ) catch return false;
                try out.appendSlice(self.allocator, msg);
                return false;
            };
            var buf: [384]u8 = undefined;
            const msg = std.fmt.bufPrint(
                &buf,
                "{{\"ok\":true,\"trace_enabled\":false,\"events_written\":{d},\"path\":\"{s}\"}}\n",
                .{ ev_count, target_path },
            ) catch return false;
            try out.appendSlice(self.allocator, msg);
            return false;
        }
        if (std.mem.eql(u8, cmd, "overlay") or std.mem.startsWith(u8, cmd, "overlay ")) {
            const sub = if (cmd.len > "overlay ".len)
                std.mem.trim(u8, cmd["overlay ".len..], " \t")
            else
                "toggle";
            if (std.mem.eql(u8, sub, "on") or std.mem.eql(u8, sub, "true") or std.mem.eql(u8, sub, "1")) {
                ctx.show_dirty_overlay = true;
            } else if (std.mem.eql(u8, sub, "off") or std.mem.eql(u8, sub, "false") or std.mem.eql(u8, sub, "0")) {
                ctx.show_dirty_overlay = false;
            } else {
                ctx.show_dirty_overlay = !ctx.show_dirty_overlay;
            }
            ctx.force_full_redraw = true;
            var buf: [192]u8 = undefined;
            const msg = std.fmt.bufPrint(
                &buf,
                "{{\"ok\":true,\"show_dirty_overlay\":{}}}\n",
                .{ctx.show_dirty_overlay},
            ) catch return true;
            try out.appendSlice(self.allocator, msg);
            return true;
        }
        if (std.mem.eql(u8, cmd, "redraw")) {
            ctx.force_full_redraw = true;
            try out.appendSlice(self.allocator, "{\"ok\":true,\"force_full_redraw\":true}\n");
            return true;
        }
        if (std.mem.eql(u8, cmd, "reset")) {
            metrics.reset();
            try out.appendSlice(self.allocator, "{\"ok\":true,\"metrics_reset\":true}\n");
            return false;
        }
        if (std.mem.eql(u8, cmd, "help")) {
            try out.appendSlice(
                self.allocator,
                \\Lightning Live Performance Debugger Commands:
                \\  status                 Live performance dashboard (rolling p50/p95/p99, phases, idle health, VRAM, TextCache)
                \\  metrics | json         Machine-readable JSON telemetry snapshot (rolling + lifetime + health)
                \\  frames [N]             Inspect last N raw painted frames from the rolling ring buffer (default: 20, max: 64)
                \\  trace start            Start recording Chrome/Perfetto timeline trace events on the running editor
                \\  trace status           Check active trace recording state and buffered event count
                \\  trace stop [path]      Stop trace recording and write Perfetto JSON file (default: /tmp/lightning-trace-<pid>.json)
                \\  overlay [on|off|toggle] Toggle green scissor damage-rect visualization overlay on the live window
                \\  redraw                 Force a full-window repaint on the next frame
                \\  reset                  Reset collected frame metrics and rolling window counters
                \\
            );
            return false;
        }

        var err_buf: [256]u8 = undefined;
        const msg = std.fmt.bufPrint(
            &err_buf,
            "{{\"ok\":false,\"error\":\"unknown_command\",\"command\":\"{s}\",\"hint\":\"Use 'status', 'metrics', 'frames', 'trace start', 'trace stop', 'overlay toggle', 'redraw', 'reset', or 'help'\"}}\n",
            .{cmd},
        ) catch return false;
        try out.appendSlice(self.allocator, msg);
        return false;
    }

    fn writeStatusReport(
        self: *const LiveDebugServer,
        ctx: *const PlatformContext,
        metrics: *const FrameMetricsCollector,
        tracer: *const TraceCollector,
        out: *std.ArrayList(u8),
    ) !void {
        const recent = metrics.computeRecentStats();
        const life = metrics.computeStats();
        const state_entries = ctx.stateEntryCount();
        const idle_sleep_state: []const u8 = if (ctx.needs_continuous_redraw)
            "AWAKE (needs_continuous_redraw = true)"
        else
            "SLEEPING (0% idle CPU/GPU)";

        var buf: [2048]u8 = undefined;
        const part1 = std.fmt.bufPrint(
            &buf,
            \\================================================================================
            \\LIGHTNING LIVE PERFORMANCE TELEMETRY (PID {d})
            \\================================================================================
            \\Socket:                 {s}
            \\Window:                 {d:.0}x{d:.0} pt (@{d:.1}x Retina, fullscreen: {})
            \\Hot-Reloads:            {d}   |   StateStore Keys: {d}
            \\Idle Power State:       {s}
            \\Dirty Scissor Overlay:  {}
            \\Live Perfetto Trace:    {s} ({d} events buffered)
            \\
            \\Wakeup & Scissor Damage Health:
            \\  Painted GPU Frames:   {d} (lifetime) / {d} (rolling window)
            \\  Idle Early-Exits:     {d} (Pass.input skipped Pass.paint)
            \\  Continuous Frames:    {d} (frames requesting 60Hz animation)
            \\  Last Frame Damage:    {d:.2}%  [{d:.0},{d:.0} -> {d:.0},{d:.0}]
            \\  Rolling Mean Damage:  {d:.2}%
            \\
        ,
            .{
                self.pid,
                self.socketPath(),
                ctx.width,
                ctx.height,
                ctx.dpi_scale,
                ctx.is_fullscreen,
                ctx.reload_count,
                state_entries,
                idle_sleep_state,
                ctx.show_dirty_overlay,
                if (tracer.enabled) "RECORDING" else "inactive",
                tracer.events.items.len,
                ctx.frame_count,
                recent.frame_count,
                metrics.idle_wakeups,
                metrics.continuous_redraw_frames,
                metrics.last_damage_pct,
                ctx.last_dirty_rect.left,
                ctx.last_dirty_rect.top,
                ctx.last_dirty_rect.right,
                ctx.last_dirty_rect.bottom,
                recent.mean_damage_pct,
            },
        ) catch return error.BufferTooSmall;
        try out.appendSlice(self.allocator, part1);

        const part2 = std.fmt.bufPrint(
            &buf,
            \\Rolling Window Latencies (last {d} painted frames, {d:.2} FPS):
            \\  Min:                  {d:.3} ms
            \\  Mean:                 {d:.3} ms
            \\  P50 (Median):         {d:.3} ms
            \\  P95:                  {d:.3} ms
            \\  P99:                  {d:.3} ms
            \\  Max:                  {d:.3} ms   (Lifetime Max: {d:.3} ms)
            \\  StdDev:               {d:.3} ms
            \\  Jank > 8.33ms (120Hz): {d} frames
            \\  Jank > 16.6ms (60Hz):  {d} frames ({d:.2}%)
            \\
            \\Rolling Phase Breakdown (average µs / painted frame):
            \\  OS Event Drain:       {d:.1} µs
            \\  Pass.input (Layout):  {d:.1} µs
            \\  Pass.paint (Record):  {d:.1} µs
            \\  Skia GPU Flush:       {d:.1} µs
            \\  Swapchain Present:    {d:.1} µs
            \\
            \\TextCache (4096-entry 4-way Set-Associative LRU):
            \\  Lookups:              {d}   |   Hits: {d} ({d:.2}%)
            \\  Misses:               {d}   |   Evictions: {d}
            \\
            \\Skia Ganesh GPU Resource Cache:
            \\  Current VRAM:         {d:.2} MB ({d} bytes, {d} resources)
            \\  Peak VRAM:            {d:.2} MB ({d} bytes, {d} peak resources)
            \\================================================================================
            \\
        ,
            .{
                recent.frame_count,
                recent.avg_fps,
                recent.latency_ms.min,
                recent.latency_ms.mean,
                recent.latency_ms.p50,
                recent.latency_ms.p95,
                recent.latency_ms.p99,
                recent.latency_ms.max,
                life.latency_ms.max,
                recent.latency_ms.stddev,
                recent.jank.frames_over_8ms,
                recent.jank.frames_over_16ms,
                recent.jank.jank_rate_pct,
                recent.phases_mean_us.events,
                recent.phases_mean_us.input_layout,
                recent.phases_mean_us.paint_record,
                recent.phases_mean_us.gpu_flush,
                recent.phases_mean_us.metal_present,
                recent.text_cache.lookups,
                recent.text_cache.hits,
                recent.text_cache.hit_ratio_pct,
                recent.text_cache.misses,
                recent.text_cache.evictions,
                @as(f64, @floatFromInt(recent.gpu_vram.final_bytes)) / (1024.0 * 1024.0),
                recent.gpu_vram.final_bytes,
                recent.gpu_vram.final_resources,
                @as(f64, @floatFromInt(recent.gpu_vram.peak_bytes)) / (1024.0 * 1024.0),
                recent.gpu_vram.peak_bytes,
                recent.gpu_vram.peak_resources,
            },
        ) catch return error.BufferTooSmall;
        try out.appendSlice(self.allocator, part2);
    }

    fn writeMetricsJson(
        self: *const LiveDebugServer,
        ctx: *const PlatformContext,
        metrics: *const FrameMetricsCollector,
        tracer: *const TraceCollector,
        out: *std.ArrayList(u8),
    ) !void {
        const recent = metrics.computeRecentStats();
        const life = metrics.computeStats();
        var buf: [2048]u8 = undefined;
        const part1 = std.fmt.bufPrint(
            &buf,
            \\{{
            \\  "pid": {d},
            \\  "socket": "{s}",
            \\  "window": {{
            \\    "width": {d:.1},
            \\    "height": {d:.1},
            \\    "dpi_scale": {d:.2},
            \\    "fullscreen": {}
            \\  }},
            \\  "health": {{
            \\    "needs_continuous_redraw": {},
            \\    "show_dirty_overlay": {},
            \\    "painted_frames": {d},
            \\    "idle_wakeups": {d},
            \\    "continuous_redraw_frames": {d},
            \\    "reload_count": {d},
            \\    "state_store_keys": {d},
            \\    "last_damage_pct": {d:.2},
            \\    "last_dirty_rect": [{d:.1}, {d:.1}, {d:.1}, {d:.1}],
            \\    "trace_enabled": {},
            \\    "trace_events_buffered": {d}
            \\  }},
            \\
        ,
            .{
                self.pid,
                self.socketPath(),
                ctx.width,
                ctx.height,
                ctx.dpi_scale,
                ctx.is_fullscreen,
                ctx.needs_continuous_redraw,
                ctx.show_dirty_overlay,
                ctx.frame_count,
                metrics.idle_wakeups,
                metrics.continuous_redraw_frames,
                ctx.reload_count,
                ctx.stateEntryCount(),
                metrics.last_damage_pct,
                ctx.last_dirty_rect.left,
                ctx.last_dirty_rect.top,
                ctx.last_dirty_rect.right,
                ctx.last_dirty_rect.bottom,
                tracer.enabled,
                tracer.events.items.len,
            },
        ) catch return error.BufferTooSmall;
        try out.appendSlice(self.allocator, part1);

        const part2 = std.fmt.bufPrint(
            &buf,
            \\  "recent": {{
            \\    "frame_count": {d},
            \\    "avg_fps": {d:.2},
            \\    "mean_damage_pct": {d:.2},
            \\    "latency_ms": {{
            \\      "min": {d:.3},
            \\      "mean": {d:.3},
            \\      "p50": {d:.3},
            \\      "p95": {d:.3},
            \\      "p99": {d:.3},
            \\      "max": {d:.3},
            \\      "stddev": {d:.3}
            \\    }},
            \\    "jank": {{
            \\      "frames_over_16ms": {d},
            \\      "frames_over_8ms": {d},
            \\      "jank_rate_pct": {d:.2}
            \\    }},
            \\    "phases_mean_us": {{
            \\      "events": {d:.1},
            \\      "input_layout": {d:.1},
            \\      "paint_record": {d:.1},
            \\      "gpu_flush": {d:.1},
            \\      "metal_present": {d:.1}
            \\    }}
            \\  }},
            \\  "lifetime": {{
            \\    "frame_count": {d},
            \\    "avg_fps": {d:.2},
            \\    "max_latency_ms": {d:.3},
            \\    "p99_latency_ms": {d:.3},
            \\    "frames_over_16ms": {d}
            \\  }},
            \\  "text_cache": {{
            \\    "lookups": {d},
            \\    "hits": {d},
            \\    "misses": {d},
            \\    "evictions": {d},
            \\    "hit_ratio_pct": {d:.2}
            \\  }},
            \\  "gpu_vram": {{
            \\    "final_bytes": {d},
            \\    "peak_bytes": {d},
            \\    "final_resources": {d},
            \\    "peak_resources": {d}
            \\  }}
            \\}}
            \\
        ,
            .{
                recent.frame_count,
                recent.avg_fps,
                recent.mean_damage_pct,
                recent.latency_ms.min,
                recent.latency_ms.mean,
                recent.latency_ms.p50,
                recent.latency_ms.p95,
                recent.latency_ms.p99,
                recent.latency_ms.max,
                recent.latency_ms.stddev,
                recent.jank.frames_over_16ms,
                recent.jank.frames_over_8ms,
                recent.jank.jank_rate_pct,
                recent.phases_mean_us.events,
                recent.phases_mean_us.input_layout,
                recent.phases_mean_us.paint_record,
                recent.phases_mean_us.gpu_flush,
                recent.phases_mean_us.metal_present,
                life.frame_count,
                life.avg_fps,
                life.latency_ms.max,
                life.latency_ms.p99,
                life.jank.frames_over_16ms,
                recent.text_cache.lookups,
                recent.text_cache.hits,
                recent.text_cache.misses,
                recent.text_cache.evictions,
                recent.text_cache.hit_ratio_pct,
                recent.gpu_vram.final_bytes,
                recent.gpu_vram.peak_bytes,
                recent.gpu_vram.final_resources,
                recent.gpu_vram.peak_resources,
            },
        ) catch return error.BufferTooSmall;
        try out.appendSlice(self.allocator, part2);
    }

    fn writeRecentFramesReport(
        self: *const LiveDebugServer,
        ctx: *const PlatformContext,
        metrics: *const FrameMetricsCollector,
        limit: usize,
        out: *std.ArrayList(u8),
    ) !void {
        var samples_buf: [64]FrameSample = undefined;
        const count = metrics.getRecentSamplesChronological(samples_buf[0..@min(limit, 64)]);
        var hdr_buf: [256]u8 = undefined;
        const hdr = std.fmt.bufPrint(
            &hdr_buf,
            "Recent {d} Painted Frames (current frame_count = {d}):\n" ++
                "  #     Total(ms)  Events(µs)  Input(µs)  Paint(µs)  Flush(µs)  Present(µs)  Damage(%)\n" ++
                "---------------------------------------------------------------------------------------\n",
            .{ count, ctx.frame_count },
        ) catch return;
        try out.appendSlice(self.allocator, hdr);

        var row_buf: [192]u8 = undefined;
        for (samples_buf[0..count], 0..) |s, i| {
            const rel_idx: isize = @as(isize, @intCast(i)) - @as(isize, @intCast(count));
            const line = std.fmt.bufPrint(
                &row_buf,
                "{d:>4}    {d:>8.3}    {d:>8.1}   {d:>8.1}   {d:>8.1}   {d:>8.1}     {d:>8.1}     {d:>6.2}%\n",
                .{
                    rel_idx,
                    @as(f64, @floatFromInt(s.total_ns)) / 1_000_000.0,
                    @as(f64, @floatFromInt(s.events_ns)) / 1000.0,
                    @as(f64, @floatFromInt(s.input_ns)) / 1000.0,
                    @as(f64, @floatFromInt(s.paint_ns)) / 1000.0,
                    @as(f64, @floatFromInt(s.gpu_flush_ns)) / 1000.0,
                    @as(f64, @floatFromInt(s.metal_present_ns)) / 1000.0,
                    s.damage_pct,
                },
            ) catch continue;
            try out.appendSlice(self.allocator, line);
        }
    }
};

/// Connects to a running editor's Unix domain debug socket, sends `command`, and returns the response.
pub fn queryDebugSocket(
    allocator: std.mem.Allocator,
    sock_path: []const u8,
    command: []const u8,
    timeout_ms: i32,
) ![]u8 {
    if (comptime is_windows) return error.UnsupportedPlatform;
    const addr = fillSockaddrUn(sock_path) orelse return error.InvalidSocketPath;

    const fd = posix_sock.socket(posix_sock.AF_UNIX, posix_sock.SOCK_STREAM, 0);
    if (fd < 0) return error.SocketCreateFailed;
    defer _ = std.c.close(fd);

    if (comptime builtin.os.tag == .macos) {
        var one: c_int = 1;
        _ = posix_sock.setsockopt(fd, posix_sock.SOL_SOCKET, posix_sock.SO_NOSIGPIPE, &one, @sizeOf(c_int));
    }

    if (posix_sock.connect(fd, &addr, @sizeOf(posix_sock.sockaddr_un)) != 0) {
        return error.ConnectionRefused;
    }

    var req_buf: [512]u8 = undefined;
    const cmd_trimmed = std.mem.trim(u8, command, " \t\r\n");
    const req = std.fmt.bufPrint(&req_buf, "{s}\n", .{if (cmd_trimmed.len > 0) cmd_trimmed else "status"}) catch return error.CommandTooLong;
    writeAllToSocket(fd, req);

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    var pfd = [1]posix_sock.PollFd{.{
        .fd = fd,
        .events = posix_sock.POLLIN,
        .revents = 0,
    }};

    var waited_ms: i32 = 0;
    const step_ms: i32 = 50;
    var read_buf: [1024]u8 = undefined;

    while (waited_ms <= timeout_ms) {
        const prc = posix_sock.poll(&pfd, 1, step_ms);
        if (prc > 0) {
            const n = std.c.read(fd, &read_buf, read_buf.len);
            if (n > 0) {
                try out.appendSlice(allocator, read_buf[0..@intCast(n)]);
                continue;
            } else if (n == 0) {
                break;
            }
        }
        if (out.items.len > 0 and prc == 0) {
            break;
        }
        waited_ms += step_ms;
    }

    if (out.items.len == 0) return error.TimedOut;
    return out.toOwnedSlice(allocator);
}

/// Scans `/tmp` for live `lightning-debug-<pid>.sock` sockets, unlinking stale ones from dead processes.
pub fn discoverRunningSockets(allocator: std.mem.Allocator) ![][]u8 {
    var list: std.ArrayList([]u8) = .empty;
    errdefer {
        for (list.items) |item| allocator.free(item);
        list.deinit(allocator);
    }
    if (comptime is_windows) return list.toOwnedSlice(allocator);

    const dir = fs_util.opendir("/tmp") orelse return list.toOwnedSlice(allocator);
    defer _ = fs_util.closedir(dir);

    while (fs_util.readdir(dir)) |entry| {
        const name = entry.d_name[0..entry.d_namlen];
        if (!std.mem.startsWith(u8, name, "lightning-debug-") or !std.mem.endsWith(u8, name, ".sock")) {
            continue;
        }
        var full_buf: [128:0]u8 = @splat(0);
        const full_slice = std.fmt.bufPrint(&full_buf, "/tmp/{s}", .{name}) catch continue;
        full_buf[full_slice.len] = 0;

        // Verify socket is actively listening by testing connect()
        if (fillSockaddrUn(full_slice)) |addr| {
            const fd = posix_sock.socket(posix_sock.AF_UNIX, posix_sock.SOCK_STREAM, 0);
            if (fd >= 0) {
                const ok = (posix_sock.connect(fd, &addr, @sizeOf(posix_sock.sockaddr_un)) == 0);
                _ = std.c.close(fd);
                if (ok) {
                    const duped = try allocator.dupe(u8, full_slice);
                    try list.append(allocator, duped);
                } else {
                    // Clean up stale socket left by a killed process
                    _ = posix_sock.unlink(&full_buf);
                }
            }
        }
    }

    return list.toOwnedSlice(allocator);
}

/// Entrypoint for `lightning --attach [pid|sock|list] [command...]`.
pub fn runAttachCli(
    allocator: std.mem.Allocator,
    target_opt: ?[]const u8,
    command: []const u8,
) !void {
    if (target_opt) |t| {
        if (std.mem.eql(u8, t, "list")) {
            const socks = try discoverRunningSockets(allocator);
            defer {
                for (socks) |s| allocator.free(s);
                allocator.free(socks);
            }
            if (socks.len == 0) {
                std.debug.print("No running Lightning instances found in /tmp/lightning-debug-*.sock\n", .{});
                return;
            }
            std.debug.print("Active Lightning debug sockets ({d}):\n", .{socks.len});
            for (socks) |s| {
                std.debug.print("  {s}\n", .{s});
            }
            return;
        }
    }

    var sock_buf: [128]u8 = undefined;
    var resolved_sock: []const u8 = "";
    var owned_socks: ?[][]u8 = null;
    defer if (owned_socks) |socks| {
        for (socks) |s| allocator.free(s);
        allocator.free(socks);
    };

    if (target_opt) |target| {
        if (std.mem.startsWith(u8, target, "/") or std.mem.endsWith(u8, target, ".sock")) {
            resolved_sock = target;
        } else {
            resolved_sock = try std.fmt.bufPrint(&sock_buf, "/tmp/lightning-debug-{s}.sock", .{target});
        }
    } else {
        const socks = try discoverRunningSockets(allocator);
        owned_socks = socks;
        if (socks.len == 0) {
            std.debug.print("Error: No running Lightning editor instance found in /tmp/lightning-debug-*.sock\n", .{});
            return error.NoRunningInstance;
        }
        // Pick the most recently created / highest PID socket
        resolved_sock = socks[socks.len - 1];
    }

    const resp = queryDebugSocket(allocator, resolved_sock, command, 2500) catch |err| {
        std.debug.print("Error attaching to '{s}': {s}\n", .{ resolved_sock, @errorName(err) });
        return err;
    };
    defer allocator.free(resp);
    std.debug.print("{s}", .{resp});
}

test "Profiler: FrameMetricsCollector p50/p95/p99 latency stats, jank tracking, TraceCollector Perfetto JSON, and ScenarioRunner" {
    var pctx = PlatformContext{ .width = 800.0, .height = 600.0 };
    pctx.text_cache_lookups = 200;
    pctx.text_cache_hits = 195;
    pctx.text_cache_misses = 5;

    var collector = FrameMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    // Record 19 fast frames (1.0 ms) and 1 jank frame (20.0 ms > 16.6ms)
    for (0..19) |_| {
        collector.recordFrame(.{
            .total_ns = 1_000_000,
            .events_ns = 50_000,
            .input_ns = 250_000,
            .paint_ns = 400_000,
            .gpu_flush_ns = 200_000,
            .metal_present_ns = 100_000,
            .damage_pct = 5.0,
        }, 4 * 1024 * 1024, 18, &pctx);
    }
    collector.recordFrame(.{
        .total_ns = 20_000_000,
        .events_ns = 100_000,
        .input_ns = 4_900_000,
        .paint_ns = 10_000_000,
        .gpu_flush_ns = 3_000_000,
        .metal_present_ns = 2_000_000,
        .damage_pct = 100.0,
    }, 8 * 1024 * 1024, 32, &pctx);

    const stats = collector.computeStats();
    try std.testing.expectEqual(@as(usize, 20), stats.frame_count);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), stats.latency_ms.min, 0.01);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), stats.latency_ms.p50, 0.01);
    try std.testing.expectApproxEqAbs(@as(f64, 20.0), stats.latency_ms.max, 0.01);
    try std.testing.expectEqual(@as(usize, 1), stats.jank.frames_over_16ms);
    try std.testing.expectEqual(@as(usize, 8 * 1024 * 1024), stats.gpu_vram.peak_bytes);
    try std.testing.expectApproxEqAbs(@as(f64, 97.5), stats.text_cache.hit_ratio_pct, 0.01);

    // TraceCollector Perfetto JSON output
    var tracer = TraceCollector.init(std.testing.allocator, true);
    defer tracer.deinit();
    tracer.record("Pass.input", "ui", tracer.base_ns + 10_000, tracer.base_ns + 260_000);
    tracer.record("Pass.paint", "gpu", tracer.base_ns + 260_000, tracer.base_ns + 660_000);
    try std.testing.expectEqual(@as(usize, 2), tracer.events.items.len);
    try std.testing.expectEqual(@as(u64, 250), tracer.events.items[0].dur_us);

    const trace_path = "/tmp/skia_editor_test_trace.json";
    try tracer.writeJsonFile(trace_path);

    // ScenarioRunner synthetic event injection
    try std.testing.expectEqual(ScenarioKind.typing, ScenarioKind.fromString("typing"));
    try std.testing.expectEqual(ScenarioKind.scroll, ScenarioKind.fromString("scroll"));
    runScenarioTick(.typing, 0, &pctx);
    try std.testing.expect(pctx.text_input_len > 0 or pctx.key_event_count > 0);
    runScenarioTick(.scroll, 10, &pctx);
    try std.testing.expectEqual(@as(f32, -16.0), pctx.scroll_dy);
}

test "Profiler: LiveDebugServer Unix domain socket attach, rolling ring buffer, live trace capture, and overlay toggle" {
    if (comptime is_windows) return;

    var pctx = PlatformContext{
        .width = 1280.0,
        .height = 800.0,
        .dpi_scale = 2.0,
        .frame_count = 4,
    };
    pctx.text_cache_lookups = 500;
    pctx.text_cache_hits = 490;
    pctx.text_cache_misses = 10;

    var collector = FrameMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    var tracer = TraceCollector.init(std.testing.allocator, false);
    defer tracer.deinit();

    collector.recordIdleWakeup(&pctx);
    collector.recordFrame(.{
        .total_ns = 1_200_000,
        .events_ns = 40_000,
        .input_ns = 300_000,
        .paint_ns = 500_000,
        .gpu_flush_ns = 260_000,
        .metal_present_ns = 100_000,
        .damage_pct = 12.5,
    }, 6 * 1024 * 1024, 24, &pctx);

    const recent_stats = collector.computeRecentStats();
    try std.testing.expectEqual(@as(usize, 1), recent_stats.frame_count);
    try std.testing.expectApproxEqAbs(@as(f64, 12.5), recent_stats.mean_damage_pct, 0.01);
    try std.testing.expectEqual(@as(usize, 1), collector.idle_wakeups);

    var sock_buf: [96]u8 = undefined;
    const test_sock = try std.fmt.bufPrint(&sock_buf, "/tmp/lightning-test-dbg-{d}.sock", .{posix_sock.getpid()});

    var server = LiveDebugServer.initWithPath(std.testing.allocator, test_sock);
    defer server.deinit();
    try std.testing.expect(server.listen_fd >= 0);

    // Helper for single-threaded non-blocking client->server->client socket roundtrip
    const Helper = struct {
        fn roundtrip(
            alloc: std.mem.Allocator,
            srv: *LiveDebugServer,
            path: []const u8,
            cmd: []const u8,
            ctx_ptr: *PlatformContext,
            m_ptr: *FrameMetricsCollector,
            t_ptr: *TraceCollector,
        ) !struct { resp: []u8, redrew: bool } {
            const addr = fillSockaddrUn(path).?;
            const cfd = posix_sock.socket(posix_sock.AF_UNIX, posix_sock.SOCK_STREAM, 0);
            try std.testing.expect(cfd >= 0);
            defer _ = std.c.close(cfd);

            try std.testing.expectEqual(@as(c_int, 0), posix_sock.connect(cfd, &addr, @sizeOf(posix_sock.sockaddr_un)));
            writeAllToSocket(cfd, cmd);

            const redrew = srv.poll(ctx_ptr, m_ptr, t_ptr);

            var out: std.ArrayList(u8) = .empty;
            errdefer out.deinit(alloc);
            var rbuf: [1024]u8 = undefined;
            while (true) {
                const n = std.c.read(cfd, &rbuf, rbuf.len);
                if (n > 0) {
                    try out.appendSlice(alloc, rbuf[0..@intCast(n)]);
                } else break;
            }
            return .{ .resp = try out.toOwnedSlice(alloc), .redrew = redrew };
        }
    };

    // 1. Query `status`
    {
        const res = try Helper.roundtrip(std.testing.allocator, &server, test_sock, "status\n", &pctx, &collector, &tracer);
        defer std.testing.allocator.free(res.resp);
        try std.testing.expect(!res.redrew);
        try std.testing.expect(std.mem.indexOf(u8, res.resp, "LIGHTNING LIVE PERFORMANCE TELEMETRY") != null);
        try std.testing.expect(std.mem.indexOf(u8, res.resp, "12.50%") != null);
    }

    // 2. Query `metrics` JSON
    {
        const res = try Helper.roundtrip(std.testing.allocator, &server, test_sock, "metrics\n", &pctx, &collector, &tracer);
        defer std.testing.allocator.free(res.resp);
        try std.testing.expect(std.mem.indexOf(u8, res.resp, "\"last_damage_pct\": 12.50") != null);
        try std.testing.expect(std.mem.indexOf(u8, res.resp, "\"idle_wakeups\": 1") != null);
    }

    // 3. Query `frames 5`
    {
        const res = try Helper.roundtrip(std.testing.allocator, &server, test_sock, "frames 5\n", &pctx, &collector, &tracer);
        defer std.testing.allocator.free(res.resp);
        try std.testing.expect(std.mem.indexOf(u8, res.resp, "Recent 1 Painted Frames") != null);
    }

    // 4. Live `trace start` -> record event -> `trace stop`
    {
        try std.testing.expect(!tracer.enabled);
        const r_start = try Helper.roundtrip(std.testing.allocator, &server, test_sock, "trace start\n", &pctx, &collector, &tracer);
        defer std.testing.allocator.free(r_start.resp);
        try std.testing.expect(r_start.redrew);
        try std.testing.expect(tracer.enabled);

        tracer.record("Pass.input", "layout", tracer.base_ns + 1000, tracer.base_ns + 51000);
        const trace_out_path = "/tmp/lightning-test-live-trace.json";
        const r_stop = try Helper.roundtrip(std.testing.allocator, &server, test_sock, "trace stop /tmp/lightning-test-live-trace.json\n", &pctx, &collector, &tracer);
        defer std.testing.allocator.free(r_stop.resp);
        try std.testing.expect(!tracer.enabled);
        try std.testing.expect(std.mem.indexOf(u8, r_stop.resp, "\"events_written\":1") != null);
        _ = posix_sock.unlink(trace_out_path);
    }

    // 5. Toggle dirty scissor overlay remotely
    {
        try std.testing.expect(!pctx.show_dirty_overlay);
        const r_ov = try Helper.roundtrip(std.testing.allocator, &server, test_sock, "overlay toggle\n", &pctx, &collector, &tracer);
        defer std.testing.allocator.free(r_ov.resp);
        try std.testing.expect(r_ov.redrew);
        try std.testing.expect(pctx.show_dirty_overlay);
    }

    // 6. Reset metrics
    {
        const r_rst = try Helper.roundtrip(std.testing.allocator, &server, test_sock, "reset\n", &pctx, &collector, &tracer);
        defer std.testing.allocator.free(r_rst.resp);
        try std.testing.expectEqual(@as(usize, 0), collector.recent_count);
    }
}
