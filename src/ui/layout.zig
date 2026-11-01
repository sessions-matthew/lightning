//! Flex-like row/column and scrollable container layout primitives
//! (`Direction`, `Size`, `Padding`, `BoxStyle`, `ContainerPreset`, `ContainerConfig`, `ScrollState`, `LayoutContainer`).

const std = @import("std");
const skia = @import("skia");
const c = skia.c;
const Color = skia.Color;
pub const Rect = c.sk_rect_t;
const Theme = @import("theme.zig").Theme;

pub const Pass = enum {
    /// CPU-only pass: computes layout, processes mouse/scroll input, mutates state, and accumulates `dirty_rect`.
    input,
    /// GPU/Skia pass: draws only widgets and containers that intersect `clip_damage`.
    paint,
};

pub const Direction = enum {
    column,
    row,
    row_wrap,
};

/// Expressive dimension specification for layout containers and controls.
pub const Size = union(enum) {
    /// Fill remaining space along the axis in the active container.
    fill,
    /// Fill remaining space minus `fill_minus` reserved pixels at the trailing edge.
    fill_minus: f32,
    /// Fixed logical pixel dimension.
    px: f32,
    /// Fraction (`0.0..1.0`) of the parent container's total inner content size,
    /// automatically accounting for inter-item `gap` spacing.
    frac: f32,
    /// Intrinsic content sizing clamped to `[min, max]`.
    fit: struct { min: f32 = 0.0, max: f32 = 10000.0 },

    pub const Kind = std.meta.Tag(Size);

    pub const half: Size = .{ .frac = 0.5 };
    pub const third: Size = .{ .frac = 1.0 / 3.0 };
    pub const auto: Size = .{ .fit = .{} };

    pub fn pixels(v: f32) Size {
        return .{ .px = v };
    }

    pub fn fillMinus(reserved_px: f32) Size {
        return .{ .fill_minus = reserved_px };
    }

    pub fn fraction(f: f32) Size {
        return .{ .frac = f };
    }

    pub fn fitContent(min_px: f32, max_px: f32) Size {
        return .{ .fit = .{ .min = min_px, .max = max_px } };
    }

    pub fn eql(self: Size, other: Size) bool {
        if (std.meta.activeTag(self) != std.meta.activeTag(other)) return false;
        return switch (self) {
            .fill => true,
            .fill_minus => |v| v == other.fill_minus,
            .px => |v| v == other.px,
            .frac => |v| v == other.frac,
            .fit => |b| b.min == other.fit.min and b.max == other.fit.max,
        };
    }

    pub fn resolve(self: Size, avail: f32, parent_content_total: f32, parent_gap: f32) f32 {
        return switch (self) {
            .fill => avail,
            .fill_minus => |reserved| @max(0.0, avail - reserved),
            .px => |v| v,
            .frac => |f| blk: {
                if (f <= 0.0) break :blk 0.0;
                if (f >= 1.0) break :blk avail;
                const estimated_slots = @max(1.0, @round(1.0 / f));
                const total_gaps = (estimated_slots - 1.0) * parent_gap;
                break :blk @max(0.0, (parent_content_total - total_gaps) * f);
            },
            .fit => |bounds| @min(avail, bounds.max),
        };
    }

    pub fn resolveIntrinsic(self: Size, intrinsic_px: f32, avail: f32, parent_content_total: f32, parent_gap: f32) f32 {
        return switch (self) {
            .fit => |bounds| std.math.clamp(intrinsic_px, bounds.min, @min(avail, bounds.max)),
            else => self.resolve(avail, parent_content_total, parent_gap),
        };
    }
};

pub const Padding = struct {
    left: f32 = 0,
    top: f32 = 0,
    right: f32 = 0,
    bottom: f32 = 0,

    pub fn all(v: f32) Padding {
        return .{ .left = v, .top = v, .right = v, .bottom = v };
    }

    pub fn xy(x: f32, y: f32) Padding {
        return .{ .left = x, .top = y, .right = x, .bottom = y };
    }
};

pub const BorderEdges = struct {
    left: bool = true,
    top: bool = true,
    right: bool = true,
    bottom: bool = true,

    pub const all: BorderEdges = .{ .left = true, .top = true, .right = true, .bottom = true };
    pub const none: BorderEdges = .{ .left = false, .top = false, .right = false, .bottom = false };
    pub const left_only: BorderEdges = .{ .left = true, .top = false, .right = false, .bottom = false };
    pub const right_only: BorderEdges = .{ .left = false, .top = false, .right = true, .bottom = false };
    pub const top_only: BorderEdges = .{ .left = false, .top = true, .right = false, .bottom = false };
    pub const bottom_only: BorderEdges = .{ .left = false, .top = false, .right = false, .bottom = true };
    pub const horizontal: BorderEdges = .{ .left = false, .top = true, .right = false, .bottom = true };
    pub const vertical: BorderEdges = .{ .left = true, .top = false, .right = true, .bottom = false };

    pub fn isAll(self: BorderEdges) bool {
        return self.left and self.top and self.right and self.bottom;
    }

    pub fn isAny(self: BorderEdges) bool {
        return self.left or self.top or self.right or self.bottom;
    }
};

pub const BoxStyle = struct {
    direction: Direction = .column,
    padding: Padding = .{},
    gap: f32 = 8.0,
    bg_color: u32 = Color.transparent,
    border_color: u32 = Color.transparent,
    border_width: f32 = 0.0,
    border_edges: BorderEdges = .all,
    corner_radius: f32 = 0.0,
    allow_h_scroll: bool = true,
};

/// Semantic visual presets for common application containers.
pub const ContainerPreset = enum {
    none,
    /// Rounded panel card (`bg_panel`, 1pt subtle border, 12pt radius, 16pt padding, 10pt gap).
    panel_card,
    /// Elevated inner card (`bg_card`, 1pt subtle border, 8pt radius, 12pt padding, 8pt gap).
    surface_card,
    /// Flat workbench sidebar (`bg_panel`, 10pt padding, 4pt gap).
    sidebar,
    /// Horizontal toolbar strip (`rgb(16, 20, 28)`, `xy(12, 4)` padding, 8pt gap).
    toolbar,
    /// Main window workspace area below titlebar (`row`, 14pt padding, 14pt gap).
    workspace,
};

/// Declarative configuration for `uic.box()`, `uic.row()`, `uic.column()`, and `uic.scrollPanel()`.
pub const ContainerConfig = struct {
    w: Size = .fill,
    h: Size = .fill,
    direction: ?Direction = null,
    preset: ContainerPreset = .none,
    padding: ?Padding = null,
    gap: ?f32 = null,
    bg_color: ?u32 = null,
    border_color: ?u32 = null,
    border_width: ?f32 = null,
    border_edges: ?BorderEdges = null,
    corner_radius: ?f32 = null,
    allow_h_scroll: ?bool = null,

    pub fn toBoxStyle(self: ContainerConfig, default_dir: Direction, theme: Theme) BoxStyle {
        var base: BoxStyle = switch (self.preset) {
            .none => .{
                .direction = default_dir,
                .padding = Padding.all(0),
                .gap = 8.0,
            },
            .panel_card => .{
                .direction = default_dir,
                .padding = Padding.all(16),
                .gap = 10.0,
                .bg_color = theme.bg_panel,
                .border_color = theme.border_subtle,
                .border_width = 1.0,
                .corner_radius = 12.0,
            },
            .surface_card => .{
                .direction = default_dir,
                .padding = Padding.all(12),
                .gap = 8.0,
                .bg_color = theme.bg_card,
                .border_color = theme.border_subtle,
                .border_width = 1.0,
                .corner_radius = 8.0,
            },
            .sidebar => .{
                .direction = default_dir,
                .padding = Padding.all(10),
                .gap = 4.0,
                .bg_color = theme.bg_panel,
                .allow_h_scroll = false,
            },
            .toolbar => .{
                .direction = .row,
                .padding = Padding.xy(12, 4),
                .gap = 8.0,
                .bg_color = Color.rgb(16, 20, 28),
            },
            .workspace => .{
                .direction = .row,
                .padding = Padding.all(14),
                .gap = 14.0,
            },
        };

        if (self.direction) |d| base.direction = d;
        if (self.padding) |p| base.padding = p;
        if (self.gap) |g| base.gap = g;
        if (self.bg_color) |bg| base.bg_color = bg;
        if (self.border_color) |bc| base.border_color = bc;
        if (self.border_width) |bw| base.border_width = bw;
        if (self.border_edges) |be| {
            base.border_edges = be;
            if (self.border_width == null and base.border_width == 0.0) {
                base.border_width = 1.0;
            }
            if (self.border_color == null and base.border_color == Color.transparent) {
                base.border_color = theme.border_subtle;
            }
        }
        if (self.corner_radius) |cr| base.corner_radius = cr;
        if (self.allow_h_scroll) |ahs| base.allow_h_scroll = ahs;
        return base;
    }
};

pub const ScrollDelta = struct {
    dx: f32 = 0,
    dy: f32 = 0,
};

/// Lightly snaps a 2D scroll delta (`raw_dx`, `raw_dy`) toward the dominant vertical or horizontal
/// axis when the movement lies within the snap cone (`snap_ratio_x` / `snap_ratio_y`), while
/// smoothly ramping in the minor axis for intentional diagonal scrolling.
pub fn snapScrollAxisWithRatio(raw_dx: f32, raw_dy: f32, snap_ratio_x: f32, snap_ratio_y: f32) ScrollDelta {
    if (raw_dx == 0 or raw_dy == 0) return .{ .dx = raw_dx, .dy = raw_dy };
    const ax = @abs(raw_dx);
    const ay = @abs(raw_dy);

    if (ay >= ax * snap_ratio_y) {
        return .{ .dx = 0, .dy = raw_dy };
    }
    if (ax >= ay * snap_ratio_x) {
        return .{ .dx = raw_dx, .dy = 0 };
    }

    if (ay >= ax) {
        const min_frac = 1.0 / @max(1.01, snap_ratio_y);
        const t = std.math.clamp((ax / ay - min_frac) / (1.0 - min_frac), 0.0, 1.0);
        return .{ .dx = raw_dx * t, .dy = raw_dy };
    } else {
        const min_frac = 1.0 / @max(1.01, snap_ratio_x);
        const t = std.math.clamp((ay / ax - min_frac) / (1.0 - min_frac), 0.0, 1.0);
        return .{ .dx = raw_dx, .dy = raw_dy * t };
    }
}

pub fn snapScrollAxis(raw_dx: f32, raw_dy: f32) ScrollDelta {
    return snapScrollAxisWithRatio(raw_dx, raw_dy, 1.75, 1.75);
}

/// Persistent state for a scrollable container (`beginScrollBox` / `endScrollBox`),
/// automatically stored in the Host's `useState` KV Store if `platform_ctx` is bound.
pub const ScrollState = struct {
    scroll_x: f32 = 0,
    scroll_y: f32 = 0,
    content_width: f32 = 0,
    content_height: f32 = 0,
    viewport_width: f32 = 0,
    viewport_height: f32 = 0,
    drag_grab_offset_x: f32 = 0,
    drag_grab_offset: f32 = 0,
    axis_bias_x: f32 = 0,
    axis_bias_y: f32 = 0,
    auto_scroll_pinned: bool = true,
    prev_content_h: f32 = 0.0,
    scroll_to_bottom_frames: u8 = 0,

    pub fn maxScrollX(self: *const ScrollState) f32 {
        if (self.viewport_width > 0.0) {
            return @max(0.0, self.content_width - self.viewport_width);
        }
        return @max(0.0, self.content_width);
    }

    pub fn maxScrollY(self: *const ScrollState) f32 {
        if (self.viewport_height > 0.0) {
            return @max(0.0, self.content_height - self.viewport_height);
        }
        return @max(0.0, self.content_height);
    }

    /// Requests that the scroll container pin to the bottom for at least `frames` consecutive frames.
    pub fn requestScrollToBottom(self: *ScrollState, frames: u8) void {
        self.auto_scroll_pinned = true;
        self.scroll_to_bottom_frames = @max(self.scroll_to_bottom_frames, frames);
    }

    /// Programmatically scrolls to `target_y` (clamped to `[0, maxScrollY()]`) and unpins tail auto-scroll.
    pub fn scrollToY(self: *ScrollState, target_y: f32) void {
        self.scroll_y = std.math.clamp(target_y, 0.0, self.maxScrollY());
        self.auto_scroll_pinned = false;
        self.scroll_to_bottom_frames = 0;
    }

    /// Updates sticky tail-pinned scrolling state before beginning a scroll container:
    ///   - Unpins when `hovered` and upward scroll wheel input (`scroll_dy > 0.5`) occurs
    ///   - Re-pins when within `unpin_threshold` (e.g. `36.0`) of `maxScrollY()` or when `scroll_to_bottom_frames >= 3`
    ///   - Snaps `scroll_y` to `maxScrollY()` when `content_height` grows while pinned or while `scroll_to_bottom_frames > 0`
    /// Returns `true` if `scroll_y` was snapped to the bottom during this update.
    pub fn updateTailPin(
        self: *ScrollState,
        hovered: bool,
        scroll_dy: f32,
        force_keep_pinned: bool,
        unpin_threshold: f32,
    ) bool {
        const max_sy = self.maxScrollY();
        if (self.scroll_to_bottom_frames >= 3) {
            self.auto_scroll_pinned = true;
        } else if (hovered and scroll_dy > 0.5 and max_sy > 4.0) {
            self.auto_scroll_pinned = false;
            self.scroll_to_bottom_frames = 0;
        } else if (self.scroll_y + unpin_threshold >= max_sy) {
            self.auto_scroll_pinned = true;
        }

        if (self.auto_scroll_pinned) {
            if (self.scroll_to_bottom_frames > 0 or
                (force_keep_pinned and @abs(self.content_height - self.prev_content_h) > 0.5) or
                (self.content_height > self.prev_content_h + 0.5))
            {
                self.scroll_y = max_sy;
                if (self.scroll_to_bottom_frames > 0) {
                    self.scroll_to_bottom_frames -= 1;
                }
                return true;
            }
        } else {
            self.scroll_to_bottom_frames = 0;
        }
        return false;
    }

    /// Finalizes tail-pinned scrolling after `endScrollBox` updates `content_height`.
    /// Snaps `scroll_y` to `maxScrollY()` if pinned and returns `true` when `scroll_to_bottom_frames > 0`
    /// so the caller can request a continuous redraw frame.
    pub fn finishTailPinPass(self: *ScrollState, force_keep_pinned: bool) bool {
        if (self.auto_scroll_pinned) {
            if (self.content_height > self.prev_content_h + 0.5) {
                if (force_keep_pinned or self.scroll_to_bottom_frames > 0) {
                    self.scroll_to_bottom_frames = @max(self.scroll_to_bottom_frames, 1);
                }
                self.scroll_y = self.maxScrollY();
            } else if (force_keep_pinned or self.scroll_to_bottom_frames > 0) {
                self.scroll_y = self.maxScrollY();
            }
        }
        self.prev_content_h = self.content_height;
        return self.scroll_to_bottom_frames > 0;
    }

    /// Applies light axis-snapping with short-term gesture momentum bias so predominantly
    /// vertical or horizontal trackpad swipes stay locked to their axis without cross-axis drift.
    pub fn snapDelta(self: *ScrollState, raw_dx: f32, raw_dy: f32) ScrollDelta {
        if (raw_dx == 0 and raw_dy == 0) {
            self.decayAxisBias();
            return .{ .dx = 0, .dy = 0 };
        }

        const ax = @abs(raw_dx);
        const ay = @abs(raw_dy);

        // If the instantaneous input strongly favors the opposite axis, release prior bias immediately
        if (ax >= ay * 1.75) {
            self.axis_bias_y *= 0.2;
        } else if (ay >= ax * 1.75) {
            self.axis_bias_x *= 0.2;
        }

        self.axis_bias_x = self.axis_bias_x * 0.65 + ax * 0.35;
        self.axis_bias_y = self.axis_bias_y * 0.65 + ay * 0.35;

        const snap_ratio_x: f32 = if (self.axis_bias_x > self.axis_bias_y * 1.5) 1.35 else 1.75;
        const snap_ratio_y: f32 = if (self.axis_bias_y > self.axis_bias_x * 1.5) 1.35 else 1.75;

        const res = snapScrollAxisWithRatio(raw_dx, raw_dy, snap_ratio_x, snap_ratio_y);
        if (res.dx == 0 and res.dy != 0) {
            self.axis_bias_x *= 0.35;
        } else if (res.dy == 0 and res.dx != 0) {
            self.axis_bias_y *= 0.35;
        }
        return res;
    }

    pub fn decayAxisBias(self: *ScrollState) void {
        self.axis_bias_x *= 0.25;
        self.axis_bias_y *= 0.25;
        if (self.axis_bias_x < 0.05) self.axis_bias_x = 0;
        if (self.axis_bias_y < 0.05) self.axis_bias_y = 0;
    }
};

pub const LayoutContainer = struct {
    bounds: c.sk_rect_t,
    content_bounds: c.sk_rect_t,
    cursor_x: f32,
    cursor_y: f32,
    max_child_right: f32 = 0,
    max_child_bottom: f32 = 0,
    row_line_max_h: f32 = 0,
    direction: Direction,
    gap: f32,
    item_count: usize = 0,
    auto_height: bool = false,

    // Scroll container metadata
    is_scroll: bool = false,
    style: BoxStyle = .{},
    scroll_id: u64 = 0,
    scroll_state: ?*ScrollState = null,
    canvas_save_count: i32 = 0,
};

test "Size.fillMinus and Size.eql resolution" {
    const s1 = Size.fillMinus(64.0);
    const s2 = Size.fillMinus(64.0);
    const s3 = Size.fillMinus(32.0);
    try std.testing.expect(s1.eql(s2));
    try std.testing.expect(!s1.eql(s3));
    try std.testing.expect(!s1.eql(.fill));

    try std.testing.expectApproxEqAbs(@as(f32, 136.0), s1.resolve(200.0, 200.0, 8.0), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), s1.resolve(40.0, 200.0, 8.0), 0.001);
}

test "ScrollState tail-pinning and programmatic scroll helpers" {
    var ss = ScrollState{
        .content_height = 500.0,
        .viewport_height = 200.0,
    };
    try std.testing.expectEqual(@as(f32, 300.0), ss.maxScrollY());
    try std.testing.expect(ss.auto_scroll_pinned);

    // Initial tail pin snaps to maxScrollY (300.0) when content_height > prev_content_h
    try std.testing.expect(ss.updateTailPin(false, 0.0, true, 36.0));
    try std.testing.expectEqual(@as(f32, 300.0), ss.scroll_y);
    _ = ss.finishTailPinPass(true);
    try std.testing.expectEqual(@as(f32, 500.0), ss.prev_content_h);

    // Upward user scroll wheel while hovered unpins auto-scroll
    ss.scroll_y = 180.0;
    try std.testing.expect(!ss.updateTailPin(true, 12.0, true, 36.0));
    try std.testing.expect(!ss.auto_scroll_pinned);

    // Programmatic scrollToY clamps to [0, maxScrollY()] and stays unpinned
    ss.scrollToY(120.0);
    try std.testing.expectEqual(@as(f32, 120.0), ss.scroll_y);
    try std.testing.expect(!ss.auto_scroll_pinned);

    // Scrolling back within unpin_threshold (36.0) of maxScrollY (300.0) re-pins
    ss.scroll_y = 270.0;
    _ = ss.updateTailPin(false, 0.0, false, 36.0);
    try std.testing.expect(ss.auto_scroll_pinned);

    // requestScrollToBottom forces re-pinning and snaps to bottom
    ss.scrollToY(50.0);
    try std.testing.expect(!ss.auto_scroll_pinned);
    ss.requestScrollToBottom(3);
    try std.testing.expect(ss.auto_scroll_pinned);
    try std.testing.expect(ss.updateTailPin(true, 10.0, false, 36.0));
    try std.testing.expectEqual(@as(f32, 300.0), ss.scroll_y);
    try std.testing.expectEqual(@as(u8, 2), ss.scroll_to_bottom_frames);
}
