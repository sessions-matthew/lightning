//! Geometric primitives (`Point`, `Rect`, `IRect`, `Size`, `ImageInfo`).

const c = @import("c/root.zig");

pub const Point = c.sk_point_t;
pub const IPoint = c.sk_ipoint_t;
pub const Size = c.sk_size_t;
pub const ISize = c.sk_isize_t;
pub const ClipOp = c.sk_clipop_t;

pub const Rect = struct {
    pub fn ltrb(left: f32, top: f32, right: f32, bottom: f32) c.sk_rect_t {
        return .{ .left = left, .top = top, .right = right, .bottom = bottom };
    }

    pub fn xywh(x: f32, y: f32, w: f32, h: f32) c.sk_rect_t {
        return .{ .left = x, .top = y, .right = x + w, .bottom = y + h };
    }

    pub fn outset(r: c.sk_rect_t, dx: f32, dy: f32) c.sk_rect_t {
        return .{
            .left = r.left - dx,
            .top = r.top - dy,
            .right = r.right + dx,
            .bottom = r.bottom + dy,
        };
    }

    pub fn unionRect(a: c.sk_rect_t, b: c.sk_rect_t) c.sk_rect_t {
        return .{
            .left = @min(a.left, b.left),
            .top = @min(a.top, b.top),
            .right = @max(a.right, b.right),
            .bottom = @max(a.bottom, b.bottom),
        };
    }

    pub fn intersects(a: c.sk_rect_t, b: c.sk_rect_t) bool {
        return a.left < b.right and a.right > b.left and a.top < b.bottom and a.bottom > b.top;
    }

    pub fn area(r: c.sk_rect_t) f32 {
        return @max(0.0, r.right - r.left) * @max(0.0, r.bottom - r.top);
    }
};

pub const IRect = struct {
    pub fn ltrb(left: i32, top: i32, right: i32, bottom: i32) c.sk_irect_t {
        return .{ .left = left, .top = top, .right = right, .bottom = bottom };
    }

    pub fn xywh(x: i32, y: i32, w: i32, h: i32) c.sk_irect_t {
        return .{ .left = x, .top = y, .right = x + w, .bottom = y + h };
    }
};

pub const ImageInfo = struct {
    pub fn initN32Premul(width: i32, height: i32) c.sk_imageinfo_t {
        return .{
            .colorspace = null,
            .width = width,
            .height = height,
            .colorType = .rgba_8888,
            .alphaType = .premul,
        };
    }

    pub fn initBgra8888Premul(width: i32, height: i32) c.sk_imageinfo_t {
        return .{
            .colorspace = null,
            .width = width,
            .height = height,
            .colorType = .bgra_8888,
            .alphaType = .premul,
        };
    }
};
