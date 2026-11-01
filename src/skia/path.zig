//! Idiomatic wrappers for `Path` and `PathBuilder`.

const c = @import("c/root.zig");
const root = @import("root.zig");
const Error = root.Error;

pub const PathDirection = c.sk_path_direction_t;
pub const PathFillType = c.sk_path_filltype_t;

pub const Path = struct {
    ptr: *c.sk_path_t,

    pub fn init() Error!Path {
        const ptr = c.sk_path_new() orelse return Error.OutOfMemory;
        return .{ .ptr = ptr };
    }

    pub fn deinit(self: Path) void {
        c.sk_path_delete(self.ptr);
    }

    pub fn bounds(self: Path) c.sk_rect_t {
        var r: c.sk_rect_t = undefined;
        c.sk_path_get_bounds(self.ptr, &r);
        return r;
    }

    pub fn contains(self: Path, x: f32, y: f32) bool {
        return c.sk_path_contains(self.ptr, x, y);
    }

    pub fn parseSvg(self: Path, svg_z: [*:0]const u8) bool {
        return c.sk_path_parse_svg_string(self.ptr, svg_z);
    }
};

pub const PathBuilder = struct {
    ptr: *c.sk_pathbuilder_t,

    pub fn init() Error!PathBuilder {
        const ptr = c.sk_pathbuilder_new() orelse return Error.OutOfMemory;
        return .{ .ptr = ptr };
    }

    pub fn deinit(self: PathBuilder) void {
        c.sk_pathbuilder_delete(self.ptr);
    }

    pub fn moveTo(self: PathBuilder, x: f32, y: f32) void {
        c.sk_pathbuilder_move_to(self.ptr, x, y);
    }

    pub fn lineTo(self: PathBuilder, x: f32, y: f32) void {
        c.sk_pathbuilder_line_to(self.ptr, x, y);
    }

    pub fn quadTo(self: PathBuilder, x0: f32, y0: f32, x1: f32, y1: f32) void {
        c.sk_pathbuilder_quad_to(self.ptr, x0, y0, x1, y1);
    }

    pub fn cubicTo(self: PathBuilder, x0: f32, y0: f32, x1: f32, y1: f32, x2: f32, y2: f32) void {
        c.sk_pathbuilder_cubic_to(self.ptr, x0, y0, x1, y1, x2, y2);
    }

    pub fn close(self: PathBuilder) void {
        c.sk_pathbuilder_close(self.ptr);
    }

    pub fn addRect(self: PathBuilder, rect: c.sk_rect_t) void {
        var r = rect;
        c.sk_pathbuilder_add_rect(self.ptr, &r, .cw);
    }

    pub fn detach(self: PathBuilder) Error!Path {
        const path_ptr = c.sk_pathbuilder_detach_path(self.ptr) orelse return Error.OutOfMemory;
        return .{ .ptr = path_ptr };
    }
};
