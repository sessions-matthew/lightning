//! Scriptable Frame Profiler, Telemetry Collector, and Chrome/Perfetto Trace Exporter.
//! Provides zero-overhead, completely headless profiling tools with machine-readable
//! JSON output, automated synthetic interaction scenarios, and microsecond phase timings.

const std = @import("std");
const app_api = @import("app_api.zig");
const objc = @import("macos/objc.zig");
const PlatformContext = app_api.PlatformContext;

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

    pub fn writeJsonFile(self: *const TraceCollector, path: []const u8) !void {
        if (!self.enabled or self.events.items.len == 0) return;
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
    allocator: std.mem.Allocator,
    samples: std.ArrayList(FrameSample) = .empty,
    start_time_ns: u64 = 0,
    end_time_ns: u64 = 0,

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
        return .{
            .allocator = allocator,
            .samples = .empty,
            .start_time_ns = nowNs(),
        };
    }

    pub fn deinit(self: *FrameMetricsCollector) void {
        self.samples.deinit(self.allocator);
    }

    pub fn recordFrame(
        self: *FrameMetricsCollector,
        sample: FrameSample,
        vram_bytes: usize,
        vram_resources: i32,
        ctx: *const PlatformContext,
    ) void {
        self.samples.append(self.allocator, sample) catch {};
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
        self.end_time_ns = nowNs();
    }

    pub const Stats = struct {
        frame_count: usize,
        total_time_ms: f64,
        avg_fps: f64,
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
        },
    };

    pub fn computeStats(self: *const FrameMetricsCollector) Stats {
        const count = self.samples.items.len;
        if (count == 0) {
            return std.mem.zeroes(Stats);
        }

        const total_wall_ns = if (self.end_time_ns >= self.start_time_ns)
            self.end_time_ns - self.start_time_ns
        else
            1;
        const total_time_ms = @as(f64, @floatFromInt(total_wall_ns)) / 1_000_000.0;
        const avg_fps = if (total_time_ms > 0) (@as(f64, @floatFromInt(count)) / (total_time_ms / 1000.0)) else 0;

        var latencies_ns = self.allocator.alloc(u64, count) catch return std.mem.zeroes(Stats);
        defer self.allocator.free(latencies_ns);

        var total_lat_ns: u64 = 0;
        var sum_events: u64 = 0;
        var sum_input: u64 = 0;
        var sum_paint: u64 = 0;
        var sum_flush: u64 = 0;
        var sum_present: u64 = 0;
        var jank_16ms: usize = 0;
        var jank_8ms: usize = 0;

        for (self.samples.items, 0..) |s, i| {
            latencies_ns[i] = s.total_ns;
            total_lat_ns += s.total_ns;
            sum_events += s.events_ns;
            sum_input += s.input_ns;
            sum_paint += s.paint_ns;
            sum_flush += s.gpu_flush_ns;
            sum_present += s.metal_present_ns;
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
            },
        };
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
