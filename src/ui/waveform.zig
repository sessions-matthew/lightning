//! Interactive Digital Waveform & Logic Analyzer Component (`src/ui/waveform.zig`) for `ui.Context`.
//!
//! Features:
//!   - **Zero-Allocation IEEE 1364 / IEEE 1800 Value Change Dump (`.vcd`) Parser (`parseVcd`)**:
//!     Parses `$timescale`, `$scope`, `$var`, `$enddefinitions`, `#<timestamp>`, scalar transitions
//!     (`0`, `1`, `x`, `z`), and multi-bit bus transitions (`b1010 <id>`).
//!   - **Built-in Demo RTL Trace (`SAMPLE_COUNTER_VCD`)**:
//!     Provides an immediate 8-signal SystemVerilog AXI/Counter waveform (`clk`, `rst_n`, `valid`,
//!     `ready`, `state[1:0]`, `count[7:0]`, `tx_data[15:0]`, `err_x`) when no `.vcd` buffer is open.
//!   - **Two-Phase (`Pass.input` / `Pass.paint`) Hardware-Accelerated Waveform Canvas**:
//!     - Interactive Time Ruler with primary & marker cursors (`T1`, `T2`, and `ΔT` readout).
//!     - Left Signal Hierarchy & Live Value Gutter at `cursor_time`.
//!     - Crisp 1-bit digital step traces (rising/falling edges, translucent green logic-1 fill),
//!       multi-bit bus hex/binary/decimal polygons with transition cross-hatches, and red/amber `X`/`Z` states.
//!     - Mouse wheel zoom (`zoom`), click-and-drag time cursor scrubbing, signal selection, and radix cycling.

const std = @import("std");
const skia = @import("skia");
const platform = @import("platform");
const root = @import("root.zig");
const c = skia.c;
const Color = skia.Color;
const Rect = skia.Rect;
const Font = skia.Font;
const Context = root.Context;
const Padding = root.Padding;

pub const MaxSignals: usize = 40;
pub const MaxTransitionsPerSignal: usize = 600;

pub const Radix = enum(u8) {
    hex = 0,
    bin = 1,
    unsigned_dec = 2,

    pub fn next(self: Radix) Radix {
        return switch (self) {
            .hex => .bin,
            .bin => .unsigned_dec,
            .unsigned_dec => .hex,
        };
    }

    pub fn label(self: Radix) []const u8 {
        return switch (self) {
            .hex => "HEX",
            .bin => "BIN",
            .unsigned_dec => "DEC",
        };
    }
};

pub const LogicState = enum(u8) {
    zero = 0,
    one = 1,
    unknown_x = 2,
    high_z = 3,
    bus = 4,
};

pub const Transition = struct {
    time: u64 = 0,
    state: LogicState = .zero,
    bus_val: u64 = 0,
};

pub const SignalTrace = struct {
    name: platform.InlineString(40) = .{},
    id_code: platform.InlineString(8) = .{},
    width: u16 = 1,
    transitions: [MaxTransitionsPerSignal]Transition = @splat(.{}),
    transition_count: usize = 0,

    pub fn addTransition(self: *SignalTrace, time: u64, state: LogicState, bus_val: u64) void {
        if (self.transition_count > 0) {
            const last = &self.transitions[self.transition_count - 1];
            if (last.time == time) {
                last.state = state;
                last.bus_val = bus_val;
                return;
            }
            if (last.state == state and last.bus_val == bus_val) {
                return;
            }
        }
        if (self.transition_count < MaxTransitionsPerSignal) {
            self.transitions[self.transition_count] = .{
                .time = time,
                .state = state,
                .bus_val = bus_val,
            };
            self.transition_count += 1;
        }
    }

    /// Evaluates the signal's logic state and bus value at `query_time` using binary search.
    pub fn sampleAt(self: *const SignalTrace, query_time: u64) Transition {
        if (self.transition_count == 0) return .{ .time = 0, .state = .zero, .bus_val = 0 };
        var lo: usize = 0;
        var hi: usize = self.transition_count;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            if (self.transitions[mid].time <= query_time) {
                lo = mid + 1;
            } else {
                hi = mid;
            }
        }
        const idx = if (lo > 0) lo - 1 else 0;
        return self.transitions[idx];
    }
};

pub const WaveformData = struct {
    timescale: platform.InlineString(16) = .{},
    signals: [MaxSignals]SignalTrace = @splat(.{}),
    signal_count: usize = 0,
    max_time: u64 = 100,

    pub fn formatValueAt(
        self: *const WaveformData,
        sig_idx: usize,
        query_time: u64,
        radix: Radix,
        buf: []u8,
    ) []const u8 {
        if (sig_idx >= self.signal_count) return "-";
        const sig = &self.signals[sig_idx];
        const samp = sig.sampleAt(query_time);
        if (sig.width <= 1 and samp.state != .bus) {
            return switch (samp.state) {
                .zero => "1'b0",
                .one => "1'b1",
                .unknown_x => "1'bx",
                .high_z => "1'bz",
                .bus => if (samp.bus_val == 0) "1'b0" else "1'b1",
            };
        }
        return switch (samp.state) {
            .unknown_x => "X",
            .high_z => "Z",
            else => switch (radix) {
                .hex => std.fmt.bufPrint(buf, "{d}'h{X}", .{ sig.width, samp.bus_val }) catch "?",
                .bin => std.fmt.bufPrint(buf, "{d}'b{b}", .{ sig.width, samp.bus_val }) catch "?",
                .unsigned_dec => std.fmt.bufPrint(buf, "{d}", .{samp.bus_val}) catch "?",
            },
        };
    }
};

pub const WaveformScrollAxis = enum(u8) {
    none = 0,
    horizontal = 1,
    vertical = 2,
};

/// Persistent interactive state for the Waveform Viewer widget (safe across `.dylib` hot-reloads).
pub const WaveformViewState = struct {
    zoom: f32 = 1.0, // 1.0 = fit entire time span, >1.0 = zoomed in
    scroll_time_ratio: f32 = 0.0, // 0.0 .. 1.0 horizontal pan offset
    signal_scroll_y: f32 = 0.0, // vertical scroll offset for signal rows
    cursor_time: u64 = 35,
    marker_time: ?u64 = 80,
    selected_signal: usize = 0,
    radix: Radix = .hex,
    dragging_cursor: bool = false,
    dragging_h_scrollbar: bool = false,
    h_drag_grab_offset: f32 = 0.0,
    scroll_axis_lock: WaveformScrollAxis = .none,
    axis_bias_x: f32 = 0.0,
    axis_bias_y: f32 = 0.0,

    /// Strictly locks each 2D trackpad/wheel gesture to EITHER horizontal (time pan) OR vertical
    /// (zoom) with strong hysteresis (`2.2x` breakout threshold) so panning never accidentally
    /// zooms and zooming never accidentally shifts the horizontal time window.
    pub fn resolveLockedScroll(self: *WaveformViewState, raw_dx: f32, raw_dy: f32) root.ScrollDelta {
        const ax = @abs(raw_dx);
        const ay = @abs(raw_dy);
        if (ax <= 0.05 and ay <= 0.05) {
            self.decayScrollLock();
            return .{ .dx = 0.0, .dy = 0.0 };
        }

        self.axis_bias_x = self.axis_bias_x * 0.72 + ax * 0.28;
        self.axis_bias_y = self.axis_bias_y * 0.72 + ay * 0.28;

        switch (self.scroll_axis_lock) {
            .horizontal => {
                if (ay > ax * 2.2 and self.axis_bias_y > self.axis_bias_x * 1.4) {
                    self.scroll_axis_lock = .vertical;
                    self.axis_bias_x *= 0.2;
                }
            },
            .vertical => {
                if (ax > ay * 2.2 and self.axis_bias_x > self.axis_bias_y * 1.4) {
                    self.scroll_axis_lock = .horizontal;
                    self.axis_bias_y *= 0.2;
                }
            },
            .none => {
                self.scroll_axis_lock = if (ax >= ay * 0.85) .horizontal else .vertical;
            },
        }

        return switch (self.scroll_axis_lock) {
            .horizontal => blk: {
                self.axis_bias_y *= 0.25;
                break :blk .{ .dx = if (ax > 0.1) raw_dx else 0.0, .dy = 0.0 };
            },
            .vertical => blk: {
                self.axis_bias_x *= 0.25;
                break :blk .{ .dx = 0.0, .dy = if (ay > 0.1) raw_dy else 0.0 };
            },
            .none => .{ .dx = 0.0, .dy = 0.0 },
        };
    }

    pub fn decayScrollLock(self: *WaveformViewState) void {
        self.axis_bias_x *= 0.2;
        self.axis_bias_y *= 0.2;
        if (self.axis_bias_x < 0.08 and self.axis_bias_y < 0.08) {
            self.axis_bias_x = 0.0;
            self.axis_bias_y = 0.0;
            self.scroll_axis_lock = .none;
        }
    }
};

pub const SAMPLE_COUNTER_VCD =
    \\$timescale 1ns $end
    \\$scope module top_tb $end
    \\$var wire 1 ! clk $end
    \\$var wire 1 @ rst_n $end
    \\$var wire 1 # valid $end
    \\$var wire 1 $ ready $end
    \\$var wire 2 % fsm_state [1:0] $end
    \\$var wire 8 ^ count [7:0] $end
    \\$var wire 16 & axi_wdata [15:0] $end
    \\$var wire 1 * fifo_err $end
    \\$upscope $end
    \\$enddefinitions $end
    \\#0
    \\0!
    \\0@
    \\0#
    \\0$
    \\b00 %
    \\b00000000 ^
    \\b0000000000000000 &
    \\x*
    \\#10
    \\1!
    \\#20
    \\0!
    \\1@
    \\0*
    \\#30
    \\1!
    \\1#
    \\b01 %
    \\b00000001 ^
    \\b0000000010100101 &
    \\#40
    \\0!
    \\#50
    \\1!
    \\1$
    \\b10 %
    \\b00000010 ^
    \\b0001001000110100 &
    \\#60
    \\0!
    \\#70
    \\1!
    \\b00000011 ^
    \\b1010101111001101 &
    \\#80
    \\0!
    \\0$
    \\#90
    \\1!
    \\b11 %
    \\b00000100 ^
    \\b1101111010101101 &
    \\#100
    \\0!
    \\1$
    \\#110
    \\1!
    \\0#
    \\b00 %
    \\b00000101 ^
    \\b1111111011101101 &
    \\#120
    \\0!
    \\z*
    \\#130
    \\1!
    \\0*
    \\#140
    \\0!
;

/// Zero-allocation IEEE 1364 / IEEE 1800 Value Change Dump (`.vcd`) parser.
pub fn parseVcd(vcd_source: []const u8, out: *WaveformData) void {
    out.* = .{};
    out.timescale.set("1ns");

    var current_time: u64 = 0;
    var max_time: u64 = 0;

    var line_it = std.mem.splitScalar(u8, vcd_source, '\n');
    while (line_it.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;

        if (std.mem.startsWith(u8, line, "$timescale")) {
            const rest = std.mem.trim(u8, line["$timescale".len..], " \t");
            if (std.mem.indexOfPos(u8, rest, 0, "$end")) |end_idx| {
                const ts = std.mem.trim(u8, rest[0..end_idx], " \t");
                if (ts.len > 0) out.timescale.set(ts);
            }
            continue;
        }

        if (std.mem.startsWith(u8, line, "$var")) {
            if (out.signal_count >= MaxSignals) continue;
            // Format: `$var wire <width> <id_code> <name> [$end]`
            var tok_it = std.mem.tokenizeAny(u8, line, " \t");
            _ = tok_it.next(); // $var
            const var_type = tok_it.next() orelse continue; // var_type (wire/reg/logic/parameter)
            if (std.mem.eql(u8, var_type, "parameter")) continue;
            const width_str = tok_it.next() orelse continue;
            const id_str = tok_it.next() orelse continue;
            const name_str = tok_it.next() orelse continue;

            // Skip submodule port aliases that reuse an already-registered VCD identifier code
            var duplicate_id = false;
            for (0..out.signal_count) |existing_i| {
                if (std.mem.eql(u8, out.signals[existing_i].id_code.slice(), id_str)) {
                    duplicate_id = true;
                    break;
                }
            }
            if (duplicate_id) continue;

            const width = std.fmt.parseInt(u16, width_str, 10) catch 1;
            const maybe_range = tok_it.next();

            // Skip individual bit-blasted wires (`a [7]`) when a multi-bit vector bus (`a[7:0]`) is already present
            if (width == 1) {
                if (maybe_range) |rng| {
                    if (!std.mem.eql(u8, rng, "$end") and rng[0] == '[' and std.mem.indexOfScalar(u8, rng, ':') == null) {
                        var has_parent_bus = false;
                        for (0..out.signal_count) |existing_i| {
                            const ex_name = out.signals[existing_i].name.slice();
                            if (out.signals[existing_i].width > 1 and
                                std.mem.startsWith(u8, ex_name, name_str) and
                                ex_name.len > name_str.len and
                                ex_name[name_str.len] == '[')
                            {
                                has_parent_bus = true;
                                break;
                            }
                        }
                        if (has_parent_bus) continue;
                    }
                }
            }

            var sig = &out.signals[out.signal_count];
            sig.* = .{ .width = @max(1, width) };
            sig.id_code.set(id_str);

            // Check if next token is bit-range like `[7:0]`
            if (maybe_range) |rng| {
                if (!std.mem.eql(u8, rng, "$end") and rng[0] == '[') {
                    var full_buf: [40]u8 = undefined;
                    if (std.fmt.bufPrint(&full_buf, "{s}{s}", .{ name_str, rng })) |combined| {
                        sig.name.set(combined);
                    } else |_| {
                        sig.name.set(name_str);
                    }
                } else {
                    sig.name.set(name_str);
                }
            } else {
                sig.name.set(name_str);
            }
            out.signal_count += 1;
            continue;
        }

        if (line[0] == '$') continue;

        // Timestamp `#<time>`
        if (line[0] == '#') {
            current_time = std.fmt.parseInt(u64, line[1..], 10) catch current_time;
            if (current_time > max_time) max_time = current_time;
            continue;
        }

        // Vector / Bus change (`b1010 <id>` or `B1010 <id>`)
        if (line[0] == 'b' or line[0] == 'B') {
            var tok_it = std.mem.tokenizeAny(u8, line[1..], " \t");
            const bits_str = tok_it.next() orelse continue;
            const id_str = tok_it.next() orelse continue;

            var state: LogicState = .bus;
            var bus_val: u64 = 0;
            for (bits_str) |ch| {
                if (ch == 'x' or ch == 'X') {
                    state = .unknown_x;
                    break;
                } else if (ch == 'z' or ch == 'Z') {
                    state = .high_z;
                    break;
                } else if (ch == '0' or ch == '1') {
                    bus_val = (bus_val << 1) | @as(u64, ch - '0');
                }
            }

            for (0..out.signal_count) |s_idx| {
                if (std.mem.eql(u8, out.signals[s_idx].id_code.slice(), id_str)) {
                    out.signals[s_idx].addTransition(current_time, state, bus_val);
                    break;
                }
            }
            continue;
        }

        // Scalar change (`0!`, `1!`, `x!`, `z!`)
        if (line.len >= 2) {
            const val_ch = line[0];
            const id_str = std.mem.trim(u8, line[1..], " \t");
            const state: LogicState = switch (val_ch) {
                '0' => .zero,
                '1' => .one,
                'x', 'X' => .unknown_x,
                'z', 'Z' => .high_z,
                else => continue,
            };
            const bus_val: u64 = if (state == .one) 1 else 0;
            for (0..out.signal_count) |s_idx| {
                if (std.mem.eql(u8, out.signals[s_idx].id_code.slice(), id_str)) {
                    out.signals[s_idx].addTransition(current_time, state, bus_val);
                    break;
                }
            }
        }
    }

    out.max_time = @max(20, max_time);
}

/// Renders an interactive Two-Phase (`Pass.input` / `Pass.paint`) Digital Waveform Viewer.
pub fn renderWaveformViewer(
    uic: *Context,
    id_str: []const u8,
    width: f32,
    height: f32,
    data: *const WaveformData,
    view: *WaveformViewState,
) void {
    var scope = uic.scopedId(0x564344); // 'VCD'
    defer scope.end();

    const outer_rect = uic.beginBox(width, height, .{
        .direction = .column,
        .padding = Padding.all(0),
        .gap = 0,
        .bg_color = Color.rgb(12, 16, 23),
    });
    defer uic.endBox();

    const max_t_f: f32 = @floatFromInt(@max(1, data.max_time));
    const max_zoom: f32 = @max(64.0, max_t_f);

    // 1. Top Toolbar: Zoom Controls, Radix Selector, Cursor T1 / T2 / ΔT Telemetry
    const toolbar_h: f32 = 30.0;
    {
        _ = uic.beginBox(0, toolbar_h, .{
            .direction = .row,
            .padding = Padding.xy(10, 3),
            .gap = 6,
            .bg_color = Color.rgb(18, 24, 36),
        });
        defer uic.endBox();

        if (uic.btn("Zoom +##wf_zin", .{ .w = .pixels(62), .h = 22 })) {
            const old_span = @max(1.0, max_t_f / @max(1.0, view.zoom));
            const old_max_start = @max(0.0, max_t_f - old_span);
            const old_start = std.math.clamp(view.scroll_time_ratio, 0.0, 1.0) * old_max_start;
            const c_f: f32 = @floatFromInt(@min(view.cursor_time, data.max_time));
            const anchor_t = if (c_f >= old_start and c_f <= old_start + old_span) c_f else (old_start + old_span * 0.5);

            view.zoom = std.math.clamp(view.zoom * 1.5, 1.0, max_zoom);
            const new_span = @max(1.0, max_t_f / @max(1.0, view.zoom));
            const new_max_start = @max(0.0, max_t_f - new_span);
            if (new_max_start > 0.0001) {
                const new_start = std.math.clamp(anchor_t - new_span * 0.5, 0.0, new_max_start);
                view.scroll_time_ratio = new_start / new_max_start;
            }
            uic.invalidateWindow();
        }
        if (uic.btn("Zoom -##wf_zout", .{ .w = .pixels(62), .h = 22 })) {
            const old_span = @max(1.0, max_t_f / @max(1.0, view.zoom));
            const old_max_start = @max(0.0, max_t_f - old_span);
            const old_start = std.math.clamp(view.scroll_time_ratio, 0.0, 1.0) * old_max_start;
            const anchor_t = old_start + old_span * 0.5;

            view.zoom = std.math.clamp(view.zoom / 1.5, 1.0, max_zoom);
            if (view.zoom <= 1.01) {
                view.zoom = 1.0;
                view.scroll_time_ratio = 0.0;
            } else {
                const new_span = @max(1.0, max_t_f / @max(1.0, view.zoom));
                const new_max_start = @max(0.0, max_t_f - new_span);
                if (new_max_start > 0.0001) {
                    const new_start = std.math.clamp(anchor_t - new_span * 0.5, 0.0, new_max_start);
                    view.scroll_time_ratio = new_start / new_max_start;
                }
            }
            uic.invalidateWindow();
        }
        if (uic.btn("Fit##wf_fit", .{ .w = .pixels(44), .h = 22 })) {
            view.zoom = 1.0;
            view.scroll_time_ratio = 0.0;
            uic.invalidateWindow();
        }
        if (uic.btn("◀ Pan##wf_pan_l", .{ .w = .pixels(54), .h = 22 })) {
            view.scroll_time_ratio = std.math.clamp(view.scroll_time_ratio - 0.25 / @max(1.0, view.zoom), 0.0, 1.0);
            uic.invalidateWindow();
        }
        if (uic.btn("Pan ▶##wf_pan_r", .{ .w = .pixels(54), .h = 22 })) {
            view.scroll_time_ratio = std.math.clamp(view.scroll_time_ratio + 0.25 / @max(1.0, view.zoom), 0.0, 1.0);
            uic.invalidateWindow();
        }

        const radix_lbl = uic.fmt("Radix: {s}##wf_radix", .{view.radix.label()});
        if (uic.chip(radix_lbl, .{ .active = true, .bordered = true, .mono = true })) {
            view.radix = view.radix.next();
            uic.invalidateWindow();
        }

        const ts = data.timescale.slice();
        const delta_str = if (view.marker_time) |m_t| blk: {
            const diff = if (view.cursor_time >= m_t) view.cursor_time - m_t else m_t - view.cursor_time;
            break :blk uic.fmt("T1: {d}{s}  |  T2: {d}{s}  |  ΔT: {d}{s}  |  Zoom: {d:.1}x", .{
                view.cursor_time,
                ts,
                m_t,
                ts,
                diff,
                ts,
                view.zoom,
            });
        } else uic.fmt("T1: {d}{s}  (Right-click to place T2 marker)  |  Zoom: {d:.1}x", .{
            view.cursor_time,
            ts,
            view.zoom,
        });
        uic.monoLabel(delta_str, Color.rgb(148, 163, 184));
    }

    // 2. Waveform Canvas Area (Ruler + Signal Rows)
    const canvas_h = @max(40.0, (outer_rect.bottom - outer_rect.top) - toolbar_h);
    const canvas_r = uic.nextRect(0, canvas_h);
    const resolved = uic.resolveIdAndLabel(id_str);

    const name_col_w: f32 = 136.0;
    const val_col_w: f32 = 96.0;
    const gutter_w: f32 = name_col_w + val_col_w;
    const ruler_h: f32 = 24.0;
    const row_h: f32 = 26.0;

    const trace_left = canvas_r.left + gutter_w;
    const trace_w = @max(60.0, canvas_r.right - trace_left - 8.0);
    const trace_rect = Rect.xywh(trace_left, canvas_r.top, trace_w, canvas_h);

    const vis_span_f: f32 = @max(1.0, max_t_f / @max(1.0, view.zoom));
    const max_start_f: f32 = @max(0.0, max_t_f - vis_span_f);
    const start_t_f: f32 = std.math.clamp(view.scroll_time_ratio, 0.0, 1.0) * max_start_f;
    const end_t_f: f32 = start_t_f + vis_span_f;

    const rows_viewport_h = @max(1.0, canvas_h - ruler_h);
    const total_rows_h = @as(f32, @floatFromInt(data.signal_count)) * row_h;
    const max_sig_scroll_y = @max(0.0, total_rows_h - rows_viewport_h);
    view.signal_scroll_y = std.math.clamp(view.signal_scroll_y, 0.0, max_sig_scroll_y);

    // Horizontal timeline scrollbar geometry (active when zoomed in)
    const has_h_scrollbar = (view.zoom > 1.01 and max_start_f > 0.01);
    const h_track_h: f32 = 5.0;
    const h_track_y = canvas_r.bottom - h_track_h - 3.0;
    const h_track_left = trace_left + 4.0;
    const h_track_w = @max(24.0, trace_w - 8.0);
    const vis_ratio_x = std.math.clamp(vis_span_f / max_t_f, 0.04, 1.0);
    const h_thumb_w = @max(20.0, h_track_w * vis_ratio_x);
    const h_scrollable_w = @max(1.0, h_track_w - h_thumb_w);
    const h_thumb_x = h_track_left + std.math.clamp(view.scroll_time_ratio, 0.0, 1.0) * h_scrollable_w;
    const h_sb_hit_rect = Rect.xywh(h_track_left, h_track_y - 5.0, h_track_w, h_track_h + 8.0);

    // Pass 1 (`.input`): Mouse click/drag time cursor, right-click marker, wheel zoom, row selection
    if (uic.pass == .input) {
        const over_h_sb = has_h_scrollbar and uic.isHovered(h_sb_hit_rect);
        if (over_h_sb and uic.mouse_pressed) {
            uic.active_id = resolved.wid ^ 0x5746_4853;
            view.dragging_h_scrollbar = true;
            if (uic.mouse_x >= h_thumb_x and uic.mouse_x <= h_thumb_x + h_thumb_w) {
                view.h_drag_grab_offset = uic.mouse_x - h_thumb_x;
            } else {
                view.h_drag_grab_offset = h_thumb_w * 0.5;
            }
            uic.markDirty(canvas_r);
        }
        if (view.dragging_h_scrollbar and uic.mouse_down) {
            const target_left = uic.mouse_x - view.h_drag_grab_offset;
            const new_ratio = std.math.clamp((target_left - h_track_left) / h_scrollable_w, 0.0, 1.0);
            if (new_ratio != view.scroll_time_ratio) {
                view.scroll_time_ratio = new_ratio;
                uic.markDirty(canvas_r);
            }
        } else if (!uic.mouse_down and view.dragging_h_scrollbar) {
            view.dragging_h_scrollbar = false;
            if (uic.active_id == (resolved.wid ^ 0x5746_4853)) {
                uic.active_id = 0;
            }
        }

        if (uic.isHovered(canvas_r) and uic.mouse_x < trace_left and @abs(uic.scroll_dy) > 0.1) {
            const next_sy = std.math.clamp(view.signal_scroll_y - uic.scroll_dy, 0.0, max_sig_scroll_y);
            if (next_sy != view.signal_scroll_y) {
                view.signal_scroll_y = next_sy;
                uic.markDirty(canvas_r);
            }
        } else if (uic.isHovered(trace_rect)) {
            uic.setCursor(if (over_h_sb) .pointing_hand else .ibeam);
            if (@abs(uic.magnify_delta) > 0.001) {
                const factor = std.math.clamp(1.0 + uic.magnify_delta, 0.25, 4.0);
                view.zoom = std.math.clamp(view.zoom * factor, 1.0, max_zoom);
                if (view.zoom <= 1.005) {
                    view.zoom = 1.0;
                    view.scroll_time_ratio = 0.0;
                }
                uic.markDirty(canvas_r);
            }
            const locked = view.resolveLockedScroll(uic.scroll_dx, uic.scroll_dy);
            if (@abs(locked.dy) > 0.25) {
                const step = std.math.clamp(locked.dy * 0.015, -0.22, 0.22);
                const factor: f32 = if (step >= 0.0) (1.0 + step) else (1.0 / (1.0 - step));
                view.zoom = std.math.clamp(view.zoom * factor, 1.0, max_zoom);
                if (view.zoom <= 1.005) {
                    view.zoom = 1.0;
                    view.scroll_time_ratio = 0.0;
                }
                uic.markDirty(canvas_r);
            } else if (@abs(locked.dx) > 0.1) {
                view.scroll_time_ratio = std.math.clamp(view.scroll_time_ratio - (locked.dx * 0.003) / view.zoom, 0.0, 1.0);
                uic.markDirty(canvas_r);
            }
        } else {
            view.decayScrollLock();
        }

        if (uic.mouse_pressed and uic.isHovered(canvas_r) and !over_h_sb) {
            // Check signal row selection
            if (uic.mouse_y > canvas_r.top + ruler_h) {
                const clicked_row: usize = @intFromFloat(@floor(((uic.mouse_y - (canvas_r.top + ruler_h)) + view.signal_scroll_y) / row_h));
                if (clicked_row < data.signal_count) {
                    view.selected_signal = clicked_row;
                    uic.markDirty(canvas_r);
                }
            }
            // Check time cursor placement inside trace area
            if (uic.mouse_x >= trace_left) {
                uic.active_id = resolved.wid;
                view.dragging_cursor = true;
                const ratio = std.math.clamp((uic.mouse_x - trace_left) / trace_w, 0.0, 1.0);
                const t_clicked: u64 = @intFromFloat(@round(start_t_f + ratio * vis_span_f));
                view.cursor_time = @min(t_clicked, data.max_time);
                uic.markDirty(canvas_r);
            }
        } else if (uic.right_mouse_pressed and uic.isHovered(trace_rect)) {
            const ratio = std.math.clamp((uic.mouse_x - trace_left) / trace_w, 0.0, 1.0);
            const t_clicked: u64 = @intFromFloat(@round(start_t_f + ratio * vis_span_f));
            view.marker_time = @min(t_clicked, data.max_time);
            uic.markDirty(canvas_r);
        } else if (uic.active_id == resolved.wid and view.dragging_cursor and uic.mouse_down) {
            const ratio = std.math.clamp((uic.mouse_x - trace_left) / trace_w, 0.0, 1.0);
            const t_dragged: u64 = @intFromFloat(@round(start_t_f + ratio * vis_span_f));
            const clamped_t = @min(t_dragged, data.max_time);
            if (clamped_t != view.cursor_time) {
                view.cursor_time = clamped_t;
                uic.markDirty(canvas_r);
            }
        } else if (!uic.mouse_down and uic.active_id == resolved.wid) {
            uic.active_id = 0;
            view.dragging_cursor = false;
        }
    }

    // Pass 2 (`.paint`): Hardware-accelerated Skia waveform rendering
    if (!uic.shouldPaint(canvas_r)) return;

    const paint = uic.paint;
    const canvas = uic.canvas;
    const font = uic.font_mono;

    const save_clip = canvas.save();
    defer canvas.restoreToCount(save_clip);
    canvas.clipRect(canvas_r, .intersect, false);

    // 1. Ruler Header Background & Borders
    paint.setStyle(.fill);
    paint.setColor(Color.rgb(16, 22, 33));
    canvas.drawRect(Rect.xywh(canvas_r.left, canvas_r.top, canvas_r.right - canvas_r.left, ruler_h), paint);

    paint.setColor(uic.theme.border_subtle);
    canvas.drawRect(Rect.xywh(canvas_r.left, canvas_r.top, canvas_r.right - canvas_r.left, 1.0), paint);
    canvas.drawRect(Rect.xywh(canvas_r.left, canvas_r.top + ruler_h - 1.0, canvas_r.right - canvas_r.left, 1.0), paint);

    paint.setColor(Color.rgb(148, 163, 184));
    uic.drawTextCached(font, "SIGNAL", canvas_r.left + 10.0, canvas_r.top + 16.5);
    uic.drawTextCached(font, "VALUE @ T1", canvas_r.left + name_col_w + 8.0, canvas_r.top + 16.5);

    // 2. Time Ruler Ticks & Vertical Grid Lines
    const tick_count: usize = 8;
    for (0..tick_count + 1) |t_i| {
        const frac = @as(f32, @floatFromInt(t_i)) / @as(f32, @floatFromInt(tick_count));
        const tx = trace_left + frac * trace_w;
        const t_val: u64 = @intFromFloat(@round(start_t_f + frac * vis_span_f));

        // Vertical grid line
        paint.setStyle(.fill);
        paint.setColor(Color.argb(26, 148, 163, 184));
        canvas.drawRect(Rect.xywh(tx, canvas_r.top + ruler_h, 1.0, canvas_h - ruler_h), paint);

        // Tick mark & time label
        paint.setColor(Color.rgb(100, 116, 139));
        canvas.drawRect(Rect.xywh(tx, canvas_r.top + ruler_h - 5.0, 1.0, 5.0), paint);
        if (t_i < tick_count) {
            const t_exact = start_t_f + frac * vis_span_f;
            const lbl = if (vis_span_f < 8.0 and @abs(t_exact - @round(t_exact)) > 0.05)
                uic.fmt("{d:.1}{s}", .{ t_exact, data.timescale.slice() })
            else
                uic.fmt("{d}{s}", .{ t_val, data.timescale.slice() });
            uic.drawTextCached(font, lbl, tx + 3.0, canvas_r.top + 15.5);
        }
    }

    // 3. Signal Rows & Digital / Bus Traces (clipped below ruler header)
    const rows_clip = canvas.save();
    canvas.clipRect(Rect.xywh(canvas_r.left, canvas_r.top + ruler_h, canvas_r.right - canvas_r.left, rows_viewport_h), .intersect, false);
    var val_buf: [32]u8 = undefined;
    for (0..data.signal_count) |s_idx| {
        const row_top = canvas_r.top + ruler_h + @as(f32, @floatFromInt(s_idx)) * row_h - view.signal_scroll_y;
        if (row_top + row_h < canvas_r.top + ruler_h) continue;
        if (row_top >= canvas_r.bottom) break;
        const row_r = Rect.xywh(canvas_r.left, row_top, canvas_r.right - canvas_r.left, row_h);

        // Alternating row background & selection highlight
        paint.setStyle(.fill);
        if (s_idx == view.selected_signal) {
            paint.setColor(Color.argb(42, 56, 139, 253));
            canvas.drawRect(row_r, paint);
        } else if (s_idx % 2 == 1) {
            paint.setColor(Color.argb(18, 30, 41, 59));
            canvas.drawRect(row_r, paint);
        }

        // Row bottom divider
        paint.setColor(Color.argb(28, 100, 116, 139));
        canvas.drawRect(Rect.xywh(row_r.left, row_r.bottom - 1.0, row_r.right - row_r.left, 1.0), paint);

        const sig = &data.signals[s_idx];
        const text_y = row_top + row_h * 0.68;

        // Signal Name
        paint.setColor(if (s_idx == view.selected_signal) Color.rgb(255, 255, 255) else Color.rgb(226, 232, 240));
        uic.drawTextCached(font, sig.name.slice(), canvas_r.left + 10.0, text_y);

        // Sampled Value at T1
        const val_str = data.formatValueAt(s_idx, view.cursor_time, view.radix, &val_buf);
        const samp_at_t1 = sig.sampleAt(view.cursor_time);
        const val_col = switch (samp_at_t1.state) {
            .unknown_x => Color.rgb(248, 113, 113),
            .high_z => Color.rgb(251, 191, 36),
            .one => Color.rgb(52, 211, 153),
            .bus => Color.rgb(56, 189, 248),
            .zero => Color.rgb(148, 163, 184),
        };
        paint.setColor(val_col);
        uic.drawTextCached(font, val_str, canvas_r.left + name_col_w + 8.0, text_y);

        // Clip to right-hand trace lane
        const trace_clip = canvas.save();
        canvas.clipRect(Rect.xywh(trace_left, row_top, trace_w, row_h), .intersect, false);
        drawSignalTraceRow(uic, font, sig, view.radix, trace_left, trace_w, row_top, row_h, start_t_f, end_t_f, data.max_time);
        canvas.restoreToCount(trace_clip);
    }
    canvas.restoreToCount(rows_clip);

    // Horizontal timeline scrollbar overlay when zoomed in
    if (has_h_scrollbar) {
        paint.setStyle(.fill);
        paint.setColor(Color.argb(60, 15, 23, 42));
        canvas.drawRoundRect(Rect.xywh(h_track_left, h_track_y, h_track_w, h_track_h), h_track_h * 0.5, h_track_h * 0.5, paint);

        const h_col = if (view.dragging_h_scrollbar)
            uic.theme.accent
        else
            Color.argb(150, 100, 116, 139);
        paint.setColor(h_col);
        canvas.drawRoundRect(Rect.xywh(h_thumb_x, h_track_y, h_thumb_w, h_track_h), h_track_h * 0.5, h_track_h * 0.5, paint);
    }

    // Gutter vertical dividers
    paint.setStyle(.fill);
    paint.setColor(uic.theme.border_subtle);
    canvas.drawRect(Rect.xywh(canvas_r.left + name_col_w, canvas_r.top, 1.0, canvas_h), paint);
    canvas.drawRect(Rect.xywh(trace_left, canvas_r.top, 1.0, canvas_h), paint);

    // 4. Secondary Marker Cursor (T2, amber dashed/solid line)
    if (view.marker_time) |m_t| {
        const m_f: f32 = @floatFromInt(m_t);
        if (m_f >= start_t_f and m_f <= end_t_f) {
            const mx = trace_left + ((m_f - start_t_f) / vis_span_f) * trace_w;
            paint.setStyle(.fill);
            paint.setColor(Color.argb(190, 245, 158, 11));
            canvas.drawRect(Rect.xywh(mx - 0.5, canvas_r.top, 1.5, canvas_h), paint);

            const m_badge = Rect.xywh(mx - 10.0, canvas_r.top + 2.0, 20.0, 13.0);
            canvas.drawRoundRect(m_badge, 3.0, 3.0, paint);
            paint.setColor(Color.rgb(15, 23, 42));
            uic.drawTextCached(font, "T2", mx - 7.0, canvas_r.top + 12.0);
        }
    }

    // 5. Primary Cursor (T1, crisp cyan/indigo line)
    const c_f: f32 = @floatFromInt(view.cursor_time);
    if (c_f >= start_t_f and c_f <= end_t_f) {
        const cx = trace_left + ((c_f - start_t_f) / vis_span_f) * trace_w;
        paint.setStyle(.fill);
        paint.setColor(Color.rgb(56, 189, 248));
        canvas.drawRect(Rect.xywh(cx - 0.75, canvas_r.top, 1.8, canvas_h), paint);

        const c_badge = Rect.xywh(cx - 10.0, canvas_r.top + 2.0, 20.0, 13.0);
        canvas.drawRoundRect(c_badge, 3.0, 3.0, paint);
        paint.setColor(Color.rgb(15, 23, 42));
        uic.drawTextCached(font, "T1", cx - 7.0, canvas_r.top + 12.0);
    }
}

fn drawSignalTraceRow(
    uic: *Context,
    font: Font,
    sig: *const SignalTrace,
    radix: Radix,
    trace_left: f32,
    trace_w: f32,
    row_top: f32,
    row_h: f32,
    start_t_f: f32,
    end_t_f: f32,
    max_time: u64,
) void {
    const paint = uic.paint;
    const canvas = uic.canvas;
    const span_f = @max(1.0, end_t_f - start_t_f);

    const y_high = row_top + 5.0;
    const y_low = row_top + row_h - 5.0;
    const y_mid = (y_high + y_low) * 0.5;
    const wave_h = y_low - y_high;

    const count = sig.transition_count;
    if (count == 0) return;

    var idx: usize = 0;
    while (idx < count) : (idx += 1) {
        const cur = sig.transitions[idx];
        const next_t: u64 = if (idx + 1 < count) sig.transitions[idx + 1].time else @max(max_time, cur.time + 10);

        const t0_f: f32 = @floatFromInt(cur.time);
        const t1_f: f32 = @floatFromInt(next_t);
        if (t1_f < start_t_f or t0_f > end_t_f) continue;

        const x0 = trace_left + std.math.clamp((t0_f - start_t_f) / span_f, 0.0, 1.0) * trace_w;
        const x1 = trace_left + std.math.clamp((t1_f - start_t_f) / span_f, 0.0, 1.0) * trace_w;
        const seg_w = @max(1.0, x1 - x0);

        if (sig.width <= 1 and cur.state != .bus) {
            // 1-Bit Digital Logic Trace
            switch (cur.state) {
                .one => {
                    // Subtle green shaded fill under logic-1
                    paint.setStyle(.fill);
                    paint.setColor(Color.argb(38, 52, 211, 153));
                    canvas.drawRect(Rect.xywh(x0, y_high, seg_w, wave_h), paint);

                    paint.setColor(Color.rgb(52, 211, 153));
                    canvas.drawRect(Rect.xywh(x0, y_high, seg_w, 1.8), paint);
                },
                .zero => {
                    paint.setStyle(.fill);
                    paint.setColor(Color.rgb(52, 211, 153));
                    canvas.drawRect(Rect.xywh(x0, y_low - 1.5, seg_w, 1.6), paint);
                },
                .unknown_x => {
                    paint.setStyle(.fill);
                    paint.setColor(Color.argb(65, 248, 113, 113));
                    canvas.drawRect(Rect.xywh(x0, y_high, seg_w, wave_h), paint);
                    paint.setColor(Color.rgb(248, 113, 113));
                    canvas.drawRect(Rect.xywh(x0, y_high, seg_w, 1.5), paint);
                    canvas.drawRect(Rect.xywh(x0, y_low - 1.5, seg_w, 1.5), paint);
                },
                .high_z => {
                    paint.setStyle(.fill);
                    paint.setColor(Color.rgb(251, 191, 36));
                    canvas.drawRect(Rect.xywh(x0, y_mid - 0.8, seg_w, 1.6), paint);
                },
                .bus => {},
            }

            // Vertical rising/falling edge transition line if previous state differed
            if (idx > 0 and t0_f >= start_t_f) {
                const prev = sig.transitions[idx - 1];
                if (prev.state != cur.state) {
                    paint.setStyle(.fill);
                    paint.setColor(Color.rgb(52, 211, 153));
                    canvas.drawRect(Rect.xywh(x0 - 0.8, y_high, 1.6, wave_h), paint);
                }
            }
        } else {
            // Multi-Bit Bus Trace (`[N:0]`)
            const is_x = (cur.state == .unknown_x);
            const is_z = (cur.state == .high_z);
            const bus_stroke = if (is_x)
                Color.rgb(248, 113, 113)
            else if (is_z)
                Color.rgb(251, 191, 36)
            else
                Color.rgb(56, 189, 248);
            const bus_fill = if (is_x)
                Color.argb(55, 248, 113, 113)
            else if (is_z)
                Color.argb(40, 251, 191, 36)
            else
                Color.argb(36, 56, 189, 248);

            const inset: f32 = if (seg_w > 6.0) 2.0 else 0.5;
            const box_r = Rect.xywh(x0 + inset, y_high, @max(1.0, seg_w - inset * 2.0), wave_h);
            paint.setStyle(.fill);
            paint.setColor(bus_fill);
            canvas.drawRoundRect(box_r, 3.0, 3.0, paint);

            paint.setStyle(.stroke);
            paint.setStrokeWidth(1.3);
            paint.setColor(bus_stroke);
            canvas.drawRoundRect(box_r, 3.0, 3.0, paint);

            // Bus value label inside segment when wide enough (falls back to compact hex/bin digits without `0x`/`0b` prefix on narrow segments)
            if (seg_w >= 10.0) {
                var b_buf: [32]u8 = undefined;
                const val_txt = if (is_x)
                    "X"
                else if (is_z)
                    "Z"
                else switch (radix) {
                    .hex => std.fmt.bufPrint(&b_buf, "0x{X}", .{cur.bus_val}) catch "?",
                    .bin => std.fmt.bufPrint(&b_buf, "0b{b}", .{cur.bus_val}) catch "?",
                    .unsigned_dec => std.fmt.bufPrint(&b_buf, "{d}", .{cur.bus_val}) catch "?",
                };
                const tw = uic.measureTextCached(font, val_txt);
                if (tw + 4.0 <= seg_w) {
                    paint.setStyle(.fill);
                    paint.setColor(Color.rgb(226, 232, 240));
                    uic.drawTextCached(font, val_txt, x0 + (seg_w - tw) * 0.5, row_top + row_h * 0.68);
                } else if (!is_x and !is_z and (radix == .hex or radix == .bin)) {
                    const short_txt = if (radix == .hex) (if (val_txt.len > 2) val_txt[2..] else val_txt) else (if (val_txt.len > 2) val_txt[2..] else val_txt);
                    const tw_short = uic.measureTextCached(font, short_txt);
                    if (tw_short + 3.0 <= seg_w) {
                        paint.setStyle(.fill);
                        paint.setColor(Color.rgb(226, 232, 240));
                        uic.drawTextCached(font, short_txt, x0 + (seg_w - tw_short) * 0.5, row_top + row_h * 0.68);
                    }
                }
            }
        }
    }
}

test "Waveform: VCD parser, binary-search signal sampling, and 2-phase rendering" {
    var data = WaveformData{};
    parseVcd(SAMPLE_COUNTER_VCD, &data);

    try std.testing.expectEqualStrings("1ns", data.timescale.slice());
    try std.testing.expectEqual(@as(usize, 8), data.signal_count);
    try std.testing.expectEqual(@as(u64, 140), data.max_time);
    try std.testing.expectEqualStrings("clk", data.signals[0].name.slice());
    try std.testing.expectEqualStrings("count[7:0]", data.signals[5].name.slice());

    // Sample `count[7:0]` at t=35ns -> 1, at t=95ns -> 4
    try std.testing.expectEqual(@as(u64, 1), data.signals[5].sampleAt(35).bus_val);
    try std.testing.expectEqual(@as(u64, 4), data.signals[5].sampleAt(95).bus_val);

    // Exercise 2-phase Pass.input and Pass.paint
    const surface = try skia.Surface.initRasterN32Premul(640, 260);
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

    var view = WaveformViewState{};
    const win_rect = Rect.xywh(0, 0, 640, 260);

    // Pass 1 (.input): click inside trace lane at x=400, y=60
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 400, 60, true, true, false);
    renderWaveformViewer(&uic, "test_wf", 640, 260, &data, &view);
    uic.endPass();
    try std.testing.expect(uic.dirty_rect != null);

    // Pass 2 (.paint)
    uic.clip_damage = win_rect;
    uic.beginPass(.paint, arena.allocator(), surface.canvas(), win_rect, 400, 60, false, false, false);
    renderWaveformViewer(&uic, "test_wf", 640, 260, &data, &view);
    uic.endPass();
}

test "Waveform: X/Z high-impedance states, multi-radix formatting (Hex/Bin/Dec), and T2 delta cursor" {
    const custom_vcd =
        \\$timescale 100ps $end
        \\$scope module soc_top $end
        \\$var wire 1 ! irq_n $end
        \\$var wire 16 " axi_rdata [15:0] $end
        \\$upscope $end
        \\$enddefinitions $end
        \\#0
        \\x!
        \\bx "
        \\#20
        \\z!
        \\bz "
        \\#50
        \\1!
        \\b1010111100001111 "
        \\#100
        \\0!
        \\b0000000000101010 "
    ;
    var data = WaveformData{};
    parseVcd(custom_vcd, &data);

    try std.testing.expectEqualStrings("100ps", data.timescale.slice());
    try std.testing.expectEqual(@as(usize, 2), data.signal_count);
    try std.testing.expectEqual(@as(u64, 100), data.max_time);

    // Sample `irq_n` across X -> Z -> 1 -> 0
    try std.testing.expect(data.signals[0].sampleAt(0).state == .unknown_x);
    try std.testing.expect(data.signals[0].sampleAt(10).state == .unknown_x);
    try std.testing.expect(data.signals[0].sampleAt(20).state == .high_z);
    try std.testing.expect(data.signals[0].sampleAt(50).state == .one);
    try std.testing.expect(data.signals[0].sampleAt(150).state == .zero);

    // Format `axi_rdata[15:0]` at t=50 in Hex, Bin, and Unsigned Decimal, and at t=0 / t=20
    var buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings("X", data.formatValueAt(1, 0, .hex, &buf));
    try std.testing.expectEqualStrings("Z", data.formatValueAt(1, 25, .hex, &buf));
    try std.testing.expectEqualStrings("16'hAF0F", data.formatValueAt(1, 60, .hex, &buf));
    try std.testing.expectEqualStrings("44815", data.formatValueAt(1, 60, .unsigned_dec, &buf));
    try std.testing.expectEqualStrings("16'b101010", data.formatValueAt(1, 100, .bin, &buf));
}

test "Waveform Fuzzer: malformed VCD tokens, signal/transition capacity overflow (>MaxSignals, >MaxTransitions)" {
    var data = WaveformData{};
    // 1. Empty / truncated / malformed VCD tokens should never panic
    parseVcd("", &data);
    parseVcd("$timescale\n$var wire", &data);
    parseVcd("#notanumber\nbXYZ !\n9!\n", &data);

    // 2. Overflow >MaxSignals and >MaxTransitionsPerSignal
    var big_vcd: std.ArrayList(u8) = .empty;
    defer big_vcd.deinit(std.testing.allocator);
    try big_vcd.appendSlice(std.testing.allocator, "$timescale 1ns $end\n");
    for (0..(MaxSignals + 8)) |s_i| {
        const id_ch: u8 = @intCast('!' + s_i);
        const line = try std.fmt.allocPrint(std.testing.allocator, "$var wire 8 {c} sig_{d} [7:0] $end\n", .{ id_ch, s_i });
        defer std.testing.allocator.free(line);
        try big_vcd.appendSlice(std.testing.allocator, line);
    }
    try big_vcd.appendSlice(std.testing.allocator, "$enddefinitions $end\n");
    for (0..(MaxTransitionsPerSignal + 40)) |t_i| {
        const line = try std.fmt.allocPrint(std.testing.allocator, "#{d}\nb{b:0>8} !\n", .{ t_i * 5, @as(u8, @truncate(t_i)) });
        defer std.testing.allocator.free(line);
        try big_vcd.appendSlice(std.testing.allocator, line);
    }

    parseVcd(big_vcd.items, &data);
    try std.testing.expectEqual(MaxSignals, data.signal_count);
    try std.testing.expectEqual(MaxTransitionsPerSignal, data.signals[0].transition_count);
}

test "Waveform: strong single-axis scroll lock prevents cross-axis zoom/pan jitter" {
    var data = WaveformData{};
    parseVcd(SAMPLE_COUNTER_VCD, &data);

    const surface = try skia.Surface.initRasterN32Premul(640, 260);
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

    var view = WaveformViewState{
        .zoom = 2.0,
        .scroll_time_ratio = 0.25,
    };
    const win_rect = Rect.xywh(0, 0, 640, 260);

    // 1. Horizontal pan gesture (`dx = -24.0`, vertical finger drift `dy = 6.0`) -> locks strictly to horizontal; zoom stays 2.0
    _ = arena.reset(.retain_capacity);
    uic.scroll_dx = -24.0;
    uic.scroll_dy = 6.0;
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 400, 120, false, false, false);
    renderWaveformViewer(&uic, "test_wf_lock", 640, 260, &data, &view);
    uic.endPass();
    try std.testing.expectEqual(WaveformScrollAxis.horizontal, view.scroll_axis_lock);
    try std.testing.expectEqual(@as(f32, 2.0), view.zoom);
    try std.testing.expect(view.scroll_time_ratio > 0.25);
    const pan_after_h = view.scroll_time_ratio;

    // 2. Subsequent frame during horizontal swipe with even larger vertical wobble (`dx = -10.0, dy = 14.0` < 2.2x) stays locked to horizontal!
    _ = arena.reset(.retain_capacity);
    uic.scroll_dx = -10.0;
    uic.scroll_dy = 14.0;
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 400, 120, false, false, false);
    renderWaveformViewer(&uic, "test_wf_lock", 640, 260, &data, &view);
    uic.endPass();
    try std.testing.expectEqual(WaveformScrollAxis.horizontal, view.scroll_axis_lock);
    try std.testing.expectEqual(@as(f32, 2.0), view.zoom);
    try std.testing.expect(view.scroll_time_ratio > pan_after_h);

    // 3. Idle frames decay the lock back to `.none`, then vertical zoom (`dy = 18.0`, horizontal drift `dx = -5.0`) locks strictly to vertical
    for (0..3) |_| {
        view.decayScrollLock();
    }
    try std.testing.expectEqual(WaveformScrollAxis.none, view.scroll_axis_lock);
    const fixed_pan = view.scroll_time_ratio;

    _ = arena.reset(.retain_capacity);
    uic.scroll_dx = -5.0;
    uic.scroll_dy = 18.0;
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 400, 120, false, false, false);
    renderWaveformViewer(&uic, "test_wf_lock", 640, 260, &data, &view);
    uic.endPass();
    try std.testing.expectEqual(WaveformScrollAxis.vertical, view.scroll_axis_lock);
    try std.testing.expect(view.zoom > 2.0);
    try std.testing.expectEqual(fixed_pan, view.scroll_time_ratio);

    // 4. Paint pass replay
    uic.clip_damage = win_rect;
    uic.beginPass(.paint, arena.allocator(), surface.canvas(), win_rect, 400, 120, false, false, false);
    renderWaveformViewer(&uic, "test_wf_lock", 640, 260, &data, &view);
    uic.endPass();

    // 5. Verify deep zoom (`> 16x` up to `max_time`) on a 500ns VCD with 1ns-wide single-clock transitions
    var long_vcd: std.ArrayList(u8) = .empty;
    defer long_vcd.deinit(std.testing.allocator);
    try long_vcd.appendSlice(std.testing.allocator, "$timescale 1ns $end\n$var reg 8 % a [7:0] $end\n$enddefinitions $end\n");
    for (0..520) |t_i| {
        const line = try std.fmt.allocPrint(std.testing.allocator, "#{d}\nb{b:0>8} %\n", .{ t_i, @as(u8, @truncate(t_i *% 37 +% 1)) });
        defer std.testing.allocator.free(line);
        try long_vcd.appendSlice(std.testing.allocator, line);
    }
    parseVcd(long_vcd.items, &data);
    try std.testing.expectEqual(@as(u64, 519), data.max_time);
    try std.testing.expectEqual(@as(usize, 520), data.signals[0].transition_count);

    view.zoom = 120.0;
    view.scroll_time_ratio = 0.5;
    _ = arena.reset(.retain_capacity);
    uic.magnify_delta = 0.5;
    uic.scroll_dx = 0.0;
    uic.scroll_dy = 0.0;
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 400, 120, false, false, false);
    renderWaveformViewer(&uic, "test_wf_deep_zoom", 640, 260, &data, &view);
    uic.endPass();
    try std.testing.expectApproxEqAbs(@as(f32, 180.0), view.zoom, 0.1);

    uic.clip_damage = win_rect;
    uic.beginPass(.paint, arena.allocator(), surface.canvas(), win_rect, 400, 120, false, false, false);
    renderWaveformViewer(&uic, "test_wf_deep_zoom", 640, 260, &data, &view);
    uic.endPass();
    try std.testing.expectEqual(uic.last_input_rect_count, uic.last_paint_rect_count);
}
