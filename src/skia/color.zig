//! Color utilities and 32-bit ARGB helpers for Skia.

const c = @import("c/root.zig");

pub const ColorType = c.sk_colortype_t;
pub const AlphaType = c.sk_alphatype_t;
pub const Color4f = c.sk_color4f_t;

pub const Color = struct {
    pub const transparent: u32 = argb(0x00, 0x00, 0x00, 0x00);
    pub const black: u32 = argb(0xFF, 0x00, 0x00, 0x00);
    pub const white: u32 = argb(0xFF, 0xFF, 0xFF, 0xFF);
    pub const red: u32 = argb(0xFF, 0xFF, 0x00, 0x00);
    pub const green: u32 = argb(0xFF, 0x00, 0xFF, 0x00);
    pub const blue: u32 = argb(0xFF, 0x00, 0x00, 0xFF);

    pub inline fn argb(a: u8, r: u8, g: u8, b: u8) u32 {
        return (@as(u32, a) << 24) | (@as(u32, r) << 16) | (@as(u32, g) << 8) | @as(u32, b);
    }

    pub inline fn rgb(r: u8, g: u8, b: u8) u32 {
        return argb(0xFF, r, g, b);
    }

    pub inline fn withAlpha(color: u32, a: u8) u32 {
        return (@as(u32, a) << 24) | (color & 0x00FF_FFFF);
    }

    pub inline fn getA(color: u32) u8 {
        return @truncate((color >> 24) & 0xFF);
    }

    pub inline fn getR(color: u32) u8 {
        return @truncate((color >> 16) & 0xFF);
    }

    pub inline fn getG(color: u32) u8 {
        return @truncate((color >> 8) & 0xFF);
    }

    pub inline fn getB(color: u32) u8 {
        return @truncate(color & 0xFF);
    }
};
