//! Idiomatic wrappers for `Paint` and `Shader`.

const c = @import("c/root.zig");
const root = @import("root.zig");
const Error = root.Error;
const Point = @import("geometry.zig").Point;

pub const BlendMode = c.sk_blendmode_t;
pub const PaintStyle = c.sk_paint_style_t;
pub const StrokeCap = c.sk_stroke_cap_t;
pub const StrokeJoin = c.sk_stroke_join_t;
pub const TileMode = c.sk_shader_tilemode_t;

pub const Paint = struct {
    ptr: *c.sk_paint_t,

    pub fn init() Error!Paint {
        const ptr = c.sk_paint_new() orelse return Error.OutOfMemory;
        return .{ .ptr = ptr };
    }

    pub fn deinit(self: Paint) void {
        c.sk_paint_delete(self.ptr);
    }

    pub fn setAntiAlias(self: Paint, aa: bool) void {
        c.sk_paint_set_antialias(self.ptr, aa);
    }

    pub fn setColor(self: Paint, color: u32) void {
        c.sk_paint_set_color(self.ptr, color);
    }

    pub fn getColor(self: Paint) u32 {
        return c.sk_paint_get_color(self.ptr);
    }

    pub fn setStyle(self: Paint, style: PaintStyle) void {
        c.sk_paint_set_style(self.ptr, style);
    }

    pub fn setStrokeWidth(self: Paint, width: f32) void {
        c.sk_paint_set_stroke_width(self.ptr, width);
    }

    pub fn setStrokeCap(self: Paint, cap: StrokeCap) void {
        c.sk_paint_set_stroke_cap(self.ptr, cap);
    }

    pub fn setStrokeJoin(self: Paint, join: StrokeJoin) void {
        c.sk_paint_set_stroke_join(self.ptr, join);
    }

    pub fn setBlendMode(self: Paint, mode: BlendMode) void {
        c.sk_paint_set_blendmode(self.ptr, mode);
    }

    pub fn setShader(self: Paint, shader: ?Shader) void {
        c.sk_paint_set_shader(self.ptr, if (shader) |s| s.ptr else null);
    }
};

pub const Shader = struct {
    ptr: *c.sk_shader_t,

    pub fn initLinearGradient(
        p0: Point,
        p1: Point,
        colors: []const u32,
        positions: ?[]const f32,
        tile_mode: TileMode,
    ) Error!Shader {
        const pts: [2]Point = .{ p0, p1 };
        const pos_ptr: ?[*]const f32 = if (positions) |p| p.ptr else null;
        const ptr = c.sk_shader_new_linear_gradient(
            &pts,
            colors.ptr,
            pos_ptr,
            @intCast(colors.len),
            tile_mode,
            null,
        ) orelse return Error.OutOfMemory;
        return .{ .ptr = ptr };
    }

    pub fn deinit(self: Shader) void {
        c.sk_shader_unref(self.ptr);
    }
};
