//! Color palette and visual styling constants for the UI widget toolkit.

const skia = @import("skia");
const Color = skia.Color;

pub const Theme = struct {
    bg_canvas: u32 = Color.rgb(11, 15, 25),
    bg_panel: u32 = Color.rgb(20, 26, 41),
    bg_card: u32 = Color.rgb(30, 41, 59),
    border_subtle: u32 = Color.argb(90, 100, 116, 139),
    text_primary: u32 = Color.rgb(248, 250, 252),
    text_muted: u32 = Color.rgb(148, 163, 184),
    accent: u32 = Color.rgb(99, 102, 241),
    accent_hover: u32 = Color.rgb(129, 140, 248),
    accent_active: u32 = Color.rgb(79, 70, 229),
    control_bg: u32 = Color.rgb(41, 53, 72),
    control_hover: u32 = Color.rgb(56, 71, 97),
    success: u32 = Color.rgb(16, 185, 129),
};
