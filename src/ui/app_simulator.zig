//! Interactive App Simulator Component (`src/ui/app_simulator.zig`) for `ui.Context`.
//! Runs dynamic `.dylib` application payloads (e.g. `libskorepad_app.dylib`) inside an editor buffer
//! with live hot-reloading, mouse/touch event forwarding, viewport scaling, iOS device presets,
//! orientation toggle, and an interactive device dropdown menu.

const std = @import("std");
const skia = @import("skia");
const platform = @import("platform");
const root = @import("root.zig");
const c = skia.c;
const Color = skia.Color;
const Rect = skia.Rect;
const Font = skia.Font;
const Context = root.Context;
const id = root.id;

pub const Orientation = enum(u8) {
    portrait = 0,
    landscape = 1,

    pub fn label(self: Orientation) []const u8 {
        return switch (self) {
            .portrait => "Portrait ↕",
            .landscape => "Landscape ↔",
        };
    }

    pub fn shortLabel(self: Orientation) []const u8 {
        return switch (self) {
            .portrait => "↕ Port",
            .landscape => "↔ Land",
        };
    }

    pub fn toggle(self: Orientation) Orientation {
        return switch (self) {
            .portrait => .landscape,
            .landscape => .portrait,
        };
    }
};

pub const DeviceCategory = enum(u8) {
    ipad = 0,
    iphone = 1,
    display = 2,

    pub fn title(self: DeviceCategory) []const u8 {
        return switch (self) {
            .ipad => "IPADS",
            .iphone => "IPHONES",
            .display => "DISPLAYS & RESPONSIVE",
        };
    }
};

pub const DevicePreset = enum(u8) {
    // iPads
    ipad_air_11 = 0, // iPad Air / Pro 11" (820 × 1180) - Default
    ipad_pro_13 = 1, // iPad Pro 12.9" / 13" (1024 × 1366)
    ipad_10 = 2, // iPad 10.2" 9th gen (810 × 1080)
    ipad_mini = 3, // iPad Mini 8.3" (744 × 1133)

    // iPhones
    iphone_16_pro_max = 4, // iPhone 16/15 Pro Max & Plus (430 × 932)
    iphone_16_pro = 5, // iPhone 16/15 Pro & 16/15 (393 × 852)
    iphone_13 = 6, // iPhone 13/12/11/XR (390 × 844)
    iphone_se = 7, // iPhone SE / 8 (375 × 667)

    // Displays & Freeform
    desktop_720p = 8, // 1280 × 720
    desktop_1080p = 9, // 1920 × 1080
    fill_pane = 10, // Dynamic Fill Pane

    pub const ipad_portrait: DevicePreset = .ipad_air_11;
    pub const ipad_landscape: DevicePreset = .ipad_air_11;

    pub const ALL = [_]DevicePreset{
        .ipad_air_11,
        .ipad_pro_13,
        .ipad_10,
        .ipad_mini,
        .iphone_16_pro_max,
        .iphone_16_pro,
        .iphone_13,
        .iphone_se,
        .desktop_720p,
        .desktop_1080p,
        .fill_pane,
    };

    pub fn category(self: DevicePreset) DeviceCategory {
        return switch (self) {
            .ipad_air_11, .ipad_pro_13, .ipad_10, .ipad_mini => .ipad,
            .iphone_16_pro_max, .iphone_16_pro, .iphone_13, .iphone_se => .iphone,
            .desktop_720p, .desktop_1080p, .fill_pane => .display,
        };
    }

    pub fn isPhone(self: DevicePreset) bool {
        return self.category() == .iphone;
    }

    pub fn baseDimensions(self: DevicePreset) [2]f32 {
        return switch (self) {
            .ipad_air_11 => .{ 820.0, 1180.0 },
            .ipad_pro_13 => .{ 1024.0, 1366.0 },
            .ipad_10 => .{ 810.0, 1080.0 },
            .ipad_mini => .{ 744.0, 1133.0 },
            .iphone_16_pro_max => .{ 430.0, 932.0 },
            .iphone_16_pro => .{ 393.0, 852.0 },
            .iphone_13 => .{ 390.0, 844.0 },
            .iphone_se => .{ 375.0, 667.0 },
            .desktop_720p => .{ 1280.0, 720.0 },
            .desktop_1080p => .{ 1920.0, 1080.0 },
            .fill_pane => .{ 820.0, 1180.0 },
        };
    }

    pub fn dimensions(self: DevicePreset, orientation: Orientation, pane_w: f32, pane_h: f32) [2]f32 {
        if (self == .fill_pane) {
            return .{ @max(100.0, pane_w), @max(100.0, pane_h) };
        }
        const base = self.baseDimensions();
        if (self == .desktop_720p or self == .desktop_1080p) {
            return if (orientation == .portrait) .{ base[1], base[0] } else base;
        }
        return if (orientation == .landscape) .{ base[1], base[0] } else base;
    }

    pub fn deviceName(self: DevicePreset) []const u8 {
        return switch (self) {
            .ipad_air_11 => "iPad Air 11\"",
            .ipad_pro_13 => "iPad Pro 13\"",
            .ipad_10 => "iPad 10.2\"",
            .ipad_mini => "iPad Mini",
            .iphone_16_pro_max => "iPhone 16 Pro Max",
            .iphone_16_pro => "iPhone 16 Pro",
            .iphone_13 => "iPhone 13 / 12",
            .iphone_se => "iPhone SE",
            .desktop_720p => "720p HD",
            .desktop_1080p => "1080p FHD",
            .fill_pane => "Fill Pane",
        };
    }

    pub fn ratioLabel(self: DevicePreset, orientation: Orientation) []const u8 {
        return switch (self) {
            .ipad_air_11 => if (orientation == .landscape) "1180×820 · ~1.44" else "820×1180 · ~1.44",
            .ipad_pro_13 => if (orientation == .landscape) "1366×1024 · 4:3" else "1024×1366 · 3:4",
            .ipad_10 => if (orientation == .landscape) "1080×810 · 4:3" else "810×1080 · 3:4",
            .ipad_mini => if (orientation == .landscape) "1133×744 · ~1.52" else "744×1133 · ~1.52",
            .iphone_16_pro_max => if (orientation == .landscape) "932×430 · 19.5:9" else "430×932 · 19.5:9",
            .iphone_16_pro => if (orientation == .landscape) "852×393 · 19.5:9" else "393×852 · 19.5:9",
            .iphone_13 => if (orientation == .landscape) "844×390 · 19.5:9" else "390×844 · 19.5:9",
            .iphone_se => if (orientation == .landscape) "667×375 · 16:9" else "375×667 · 16:9",
            .desktop_720p => "1280×720 · 16:9",
            .desktop_1080p => "1920×1080 · 16:9",
            .fill_pane => "Dynamic",
        };
    }

    pub fn label(self: DevicePreset, orientation: Orientation) []const u8 {
        return switch (self) {
            .ipad_air_11 => if (orientation == .landscape) "iPad Air 11\" (1180×820)" else "iPad Air 11\" (820×1180)",
            .ipad_pro_13 => if (orientation == .landscape) "iPad Pro 13\" (1366×1024)" else "iPad Pro 13\" (1024×1366)",
            .ipad_10 => if (orientation == .landscape) "iPad 10.2\" (1080×810)" else "iPad 10.2\" (810×1080)",
            .ipad_mini => if (orientation == .landscape) "iPad Mini (1133×744)" else "iPad Mini (744×1133)",
            .iphone_16_pro_max => if (orientation == .landscape) "iPhone 16 Pro Max (932×430)" else "iPhone 16 Pro Max (430×932)",
            .iphone_16_pro => if (orientation == .landscape) "iPhone 16 Pro (852×393)" else "iPhone 16 Pro (393×852)",
            .iphone_13 => if (orientation == .landscape) "iPhone 13 / 12 (844×390)" else "iPhone 13 / 12 (390×844)",
            .iphone_se => if (orientation == .landscape) "iPhone SE (667×375)" else "iPhone SE (375×667)",
            .desktop_720p => "720p (1280×720)",
            .desktop_1080p => "1080p (1920×1080)",
            .fill_pane => "Fill Pane",
        };
    }
};

pub const AppSimulatorState = struct {
    dylib_path_buf: [512]u8 = @splat(0),
    dylib_path_len: usize = 0,
    preset: DevicePreset = .ipad_air_11,
    orientation: Orientation = .portrait,
    dropdown_open: bool = false,
    zoom_fit: bool = true,
    user_scale: f32 = 1.0,
    mouse_down_on_screen: bool = false,

    hot_dylib: platform.HotDylib = .{},
    sub_ctx: platform.PlatformContext = .{},
    sub_state_store: ?*platform.StateStore = null,
    sub_snapshot_buf: ?*platform.SnapshotBuffer = null,
    allocator: ?std.mem.Allocator = null,
    initialized: bool = false,
    reload_failed: bool = false,

    pub fn label(self: *const AppSimulatorState) []const u8 {
        return self.preset.label(self.orientation);
    }

    pub fn init(self: *AppSimulatorState, alloc: std.mem.Allocator, host_ctx: ?*platform.PlatformContext) void {
        if (self.initialized) return;
        self.allocator = alloc;

        const store = alloc.create(platform.StateStore) catch return;
        store.* = platform.StateStore.init(alloc);
        self.sub_state_store = store;

        const snap = alloc.create(platform.SnapshotBuffer) catch return;
        snap.* = platform.SnapshotBuffer.init(alloc);
        self.sub_snapshot_buf = snap;

        self.sub_ctx = .{};
        self.sub_ctx.bindHostStores(store, snap);

        if (host_ctx) |h| {
            self.sub_ctx.host_get_clipboard = h.host_get_clipboard;
            self.sub_ctx.host_set_clipboard = h.host_set_clipboard;
            self.sub_ctx.host_pick_folder = h.host_pick_folder;
            self.sub_ctx.host_pick_file = h.host_pick_file;
            self.sub_ctx.host_save_file = h.host_save_file;
            self.sub_ctx.host_window_action = h.host_window_action;
            self.sub_ctx.gr_context = h.gr_context;
            self.sub_ctx.font_mgr = h.font_mgr;
            self.sub_ctx.dpi_scale = h.dpi_scale;
        }

        self.initialized = true;
    }

    pub fn deinit(self: *AppSimulatorState) void {
        if (self.hot_dylib.handle != null) {
            self.hot_dylib.unload(&self.sub_ctx);
        }
        if (self.allocator) |alloc| {
            if (self.sub_state_store) |s| {
                s.deinit();
                alloc.destroy(s);
                self.sub_state_store = null;
            }
            if (self.sub_snapshot_buf) |b| {
                b.deinit();
                alloc.destroy(b);
                self.sub_snapshot_buf = null;
            }
        }
        self.initialized = false;
    }

    pub fn setDylibPath(self: *AppSimulatorState, path: []const u8) void {
        if (path.len == 0 or path.len >= self.dylib_path_buf.len - 1) return;
        @memcpy(self.dylib_path_buf[0..path.len], path);
        self.dylib_path_buf[path.len] = 0;
        self.dylib_path_len = path.len;
        self.hot_dylib.watch_path = @ptrCast(&self.dylib_path_buf);
        self.hot_dylib.last_mtime = 0; // Trigger reload check
        self.sub_ctx.force_full_redraw = true;
    }

    pub fn getDylibPath(self: *const AppSimulatorState) []const u8 {
        return self.dylib_path_buf[0..self.dylib_path_len];
    }

    pub fn resolveDefaultDylibPath(self: *AppSimulatorState) void {
        if (self.dylib_path_len > 0) return;

        const candidates = [_][]const u8{
            "zig-out/lib/libeditor_app.dylib",
            "zig-out/lib/libskorepad_app.dylib",
            "build/libeditor_app.dylib",
        };

        for (candidates) |cand| {
            var probe_z: [512:0]u8 = @splat(0);
            if (cand.len < probe_z.len) {
                @memcpy(probe_z[0..cand.len], cand);
                probe_z[cand.len] = 0;
                if (platform.fs_util.pathExistsOnDisk(&probe_z)) {
                    self.setDylibPath(cand);
                    return;
                }
            }
        }
    }

    pub fn triggerManualReload(self: *AppSimulatorState) bool {
        if (!self.initialized or self.dylib_path_len == 0) return false;
        self.hot_dylib.watch_path = @ptrCast(&self.dylib_path_buf);
        self.hot_dylib.last_mtime = 0; // Force mtime mismatch
        const ok = self.hot_dylib.checkAndReload(&self.sub_ctx);
        self.reload_failed = !ok and (self.hot_dylib.handle == null);
        self.sub_ctx.force_full_redraw = true;
        return ok;
    }
};

pub const AppSimulatorOptions = struct {
    dylib_path: []const u8 = "",
};

pub const AppSimulatorResult = struct {
    reloaded: bool = false,
    needs_continuous_redraw: bool = false,
    device_w: f32 = 820.0,
    device_h: f32 = 1180.0,
};

fn drawToolbarChip(uic: *Context, font: Font, r: c.sk_rect_t, label: []const u8, active: bool) void {
    const is_hovered = uic.isHovered(r);
    const bg = if (active)
        Color.argb(70, 56, 189, 248)
    else if (is_hovered)
        Color.argb(40, 255, 255, 255)
    else
        Color.argb(20, 255, 255, 255);
    uic.paint.setColor(bg);
    uic.canvas.drawRoundRect(r, 4.0, 4.0, uic.paint);

    if (active) {
        uic.paint.setStyle(.stroke);
        uic.paint.setStrokeWidth(1.0);
        uic.paint.setColor(Color.rgb(56, 189, 248));
        uic.canvas.drawRoundRect(r, 4.0, 4.0, uic.paint);
        uic.paint.setStyle(.fill);
    }

    const fg = if (active) Color.rgb(56, 189, 248) else uic.theme.text_muted;
    uic.paint.setColor(fg);
    const tw = uic.measureTextCached(font, label);
    uic.drawTextCached(font, label, r.left + (r.right - r.left - tw) * 0.5, r.top + (r.bottom - r.top + 10.0) * 0.5);
}

pub fn renderAppSimulator(
    uic: *Context,
    id_str: []const u8,
    width: f32,
    height: f32,
    sim: *AppSimulatorState,
    options: AppSimulatorOptions,
) AppSimulatorResult {
    const resolved = uic.resolveIdAndLabel(id_str);
    const full_r = uic.nextRect(width, height);
    const w = @max(1.0, full_r.right - full_r.left);
    const h = @max(1.0, full_r.bottom - full_r.top);

    sim.init(std.heap.c_allocator, uic.platform_ctx);

    if (options.dylib_path.len > 0 and sim.dylib_path_len == 0) {
        sim.setDylibPath(options.dylib_path);
    } else if (sim.dylib_path_len == 0) {
        sim.resolveDefaultDylibPath();
    }

    const toolbar_h: f32 = 34.0;
    const canvas_r = Rect.xywh(full_r.left, full_r.top + toolbar_h, w, @max(1.0, h - toolbar_h));

    const canvas_w = canvas_r.right - canvas_r.left;
    const canvas_h = canvas_r.bottom - canvas_r.top;
    const dims = sim.preset.dimensions(sim.orientation, canvas_w, canvas_h);
    const virtual_w = dims[0];
    const virtual_h = dims[1];

    // Compute fit scaling
    const margin: f32 = if (sim.preset == .fill_pane) 0.0 else 16.0;
    const avail_w = @max(32.0, canvas_w - margin * 2.0);
    const avail_h = @max(32.0, canvas_h - margin * 2.0);

    const fit_scale_x = avail_w / virtual_w;
    const fit_scale_y = avail_h / virtual_h;
    const fit_scale: f32 = if (sim.zoom_fit) @min(fit_scale_x, fit_scale_y) else sim.user_scale;

    const draw_w = @round(virtual_w * fit_scale);
    const draw_h = @round(virtual_h * fit_scale);
    const draw_x = @round(canvas_r.left + (canvas_w - draw_w) * 0.5);
    const draw_y = @round(canvas_r.top + (canvas_h - draw_h) * 0.5);

    // Toolbar buttons
    const btn_y = full_r.top + 5.0;
    const btn_h: f32 = 24.0;

    const badge_r = Rect.xywh(full_r.left + 10.0, btn_y + 2.0, 48.0, 20.0);
    const dd_btn_r = Rect.xywh(badge_r.right + 8.0, btn_y, 160.0, btn_h);
    const orient_btn_r = Rect.xywh(dd_btn_r.right + 6.0, btn_y, 74.0, btn_h);
    const fit_btn_r = Rect.xywh(orient_btn_r.right + 6.0, btn_y, 40.0, btn_h);
    const one_btn_r = Rect.xywh(fit_btn_r.right + 4.0, btn_y, 36.0, btn_h);
    const reload_btn_r = Rect.xywh(one_btn_r.right + 8.0, btn_y, 88.0, btn_h);

    // Floating dropdown overlay placement
    const menu_w: f32 = 296.0;
    const menu_h: f32 = 384.0;
    const menu_x = dd_btn_r.left;
    const menu_y = @min(dd_btn_r.bottom + 4.0, @max(full_r.top + 34.0, full_r.bottom - menu_h - 10.0));
    const menu_r = Rect.xywh(menu_x, menu_y, menu_w, menu_h);

    const had_dropdown_open = sim.dropdown_open;
    if (had_dropdown_open) {
        uic.setBlockingOverlay(menu_r);
    }
    defer if (had_dropdown_open) uic.setBlockingOverlay(null);

    var result = AppSimulatorResult{
        .device_w = virtual_w,
        .device_h = virtual_h,
    };

    // ------------------------------------------------------------------------
    // Pass 1 (`.input`): Dropdown menu, toolbar clicks, mouse coordinate translation
    // ------------------------------------------------------------------------
    if (uic.pass == .input) {
        if (uic.isHovered(canvas_r)) {
            uic.hot_id = resolved.wid;
        }

        // Detect dimensions change (preset switch or window resize)
        if (sim.sub_ctx.width != virtual_w or sim.sub_ctx.height != virtual_h) {
            sim.sub_ctx.width = virtual_w;
            sim.sub_ctx.height = virtual_h;
            sim.sub_ctx.force_full_redraw = true;
            uic.markDirty(full_r);
        }

        var dropdown_just_closed = false;

        // 1. Dropdown interactions when open
        if (sim.dropdown_open) {
            const prev_in_overlay = uic.in_overlay;
            uic.in_overlay = true;
            defer uic.in_overlay = prev_in_overlay;

            // Escape key dismisses
            for (uic.key_events) |kev| {
                if (kev.key == .escape) {
                    sim.dropdown_open = false;
                    dropdown_just_closed = true;
                    uic.markDirty(full_r);
                    uic.invalidateWindow();
                    break;
                }
            }

            // Click outside dismisses (checks both dd_btn_r and menu_r)
            if (!dropdown_just_closed and uic.clickedOutside(&.{ dd_btn_r, menu_r })) {
                sim.dropdown_open = false;
                dropdown_just_closed = true;
                uic.markDirty(full_r);
                uic.invalidateWindow();
            }

            // Check item clicks & hover tracking in dropdown
            if (!dropdown_just_closed) {
                var cur_y = menu_y + 6.0;
                var cur_cat: ?DeviceCategory = null;
                for (DevicePreset.ALL) |preset| {
                    const cat = preset.category();
                    if (cur_cat == null or cur_cat.? != cat) {
                        cur_cat = cat;
                        cur_y += 18.0; // Section header height
                    }
                    const item_r = Rect.xywh(menu_x + 6.0, cur_y, menu_w - 12.0, 24.0);
                    const item_wid = id(preset.deviceName());
                    const hovered = uic.isHovered(item_r);
                    if (hovered) {
                        uic.setCursor(.pointing_hand);
                    }
                    _ = uic.trackInteraction(item_wid, item_r, full_r);

                    if (hovered and (uic.mouse_released or uic.mouse_pressed)) {
                        sim.preset = preset;
                        sim.dropdown_open = false;
                        dropdown_just_closed = true;
                        sim.sub_ctx.force_full_redraw = true;
                        uic.active_id = 0;
                        uic.markDirty(full_r);
                        uic.invalidateWindow();
                        break;
                    }
                    cur_y += 24.0;
                }

                // Rotate button row inside dropdown
                if (!dropdown_just_closed) {
                    const rotate_r = Rect.xywh(menu_x + 6.0, cur_y + 6.0, menu_w - 12.0, 26.0);
                    const rot_wid = id("sim_item_rotate");
                    const rot_hovered = uic.isHovered(rotate_r);
                    if (rot_hovered) {
                        uic.setCursor(.pointing_hand);
                    }
                    _ = uic.trackInteraction(rot_wid, rotate_r, full_r);

                    if (rot_hovered and (uic.mouse_released or uic.mouse_pressed)) {
                        sim.orientation = sim.orientation.toggle();
                        sim.dropdown_open = false;
                        dropdown_just_closed = true;
                        sim.sub_ctx.force_full_redraw = true;
                        uic.active_id = 0;
                        uic.markDirty(full_r);
                        uic.invalidateWindow();
                    }
                }
            }
        }

        // 2. Toolbar interactions
        if (!dropdown_just_closed) {
            if (!sim.dropdown_open) {
                _ = uic.trackInteraction(id("sim_tb_dd"), dd_btn_r, full_r);
                _ = uic.trackInteraction(id("sim_tb_orient"), orient_btn_r, full_r);
                _ = uic.trackInteraction(id("sim_tb_fit"), fit_btn_r, full_r);
                _ = uic.trackInteraction(id("sim_tb_one"), one_btn_r, full_r);
                _ = uic.trackInteraction(id("sim_tb_reload"), reload_btn_r, full_r);

                if (uic.isHovered(dd_btn_r) or uic.isHovered(orient_btn_r) or
                    uic.isHovered(fit_btn_r) or uic.isHovered(one_btn_r) or
                    uic.isHovered(reload_btn_r))
                {
                    uic.setCursor(.pointing_hand);
                }
            }

            if (uic.mouse_pressed and uic.isHovered(full_r)) {
                if (uic.isHovered(dd_btn_r)) {
                    sim.dropdown_open = !sim.dropdown_open;
                    uic.markDirty(full_r);
                    uic.invalidateWindow();
                } else if (!sim.dropdown_open and uic.isHovered(orient_btn_r)) {
                    sim.orientation = sim.orientation.toggle();
                    sim.sub_ctx.force_full_redraw = true;
                    uic.markDirty(full_r);
                    uic.invalidateWindow();
                } else if (!sim.dropdown_open and uic.isHovered(fit_btn_r)) {
                    sim.zoom_fit = true;
                    sim.sub_ctx.force_full_redraw = true;
                    uic.markDirty(full_r);
                    uic.invalidateWindow();
                } else if (!sim.dropdown_open and uic.isHovered(one_btn_r)) {
                    sim.zoom_fit = false;
                    sim.user_scale = 1.0;
                    sim.sub_ctx.force_full_redraw = true;
                    uic.markDirty(full_r);
                    uic.invalidateWindow();
                } else if (!sim.dropdown_open and uic.isHovered(reload_btn_r)) {
                    _ = sim.triggerManualReload();
                    sim.sub_ctx.force_full_redraw = true;
                    result.reloaded = true;
                    uic.markDirty(full_r);
                    uic.invalidateWindow();
                }
            }
        }

        // Automatic file modification check on disk
        if (sim.hot_dylib.checkAndReload(&sim.sub_ctx)) {
            sim.sub_ctx.force_full_redraw = true;
            result.reloaded = true;
            uic.markDirty(full_r);
        }

        // Map mouse coordinates to the virtual device viewport (only when not interacting with dropdown)
        const is_screen_hovered = (uic.mouse_x >= draw_x and uic.mouse_x < draw_x + draw_w and
            uic.mouse_y >= draw_y and uic.mouse_y < draw_y + draw_h) and !sim.dropdown_open and !dropdown_just_closed;

        if (is_screen_hovered and fit_scale > 0.0) {
            sim.sub_ctx.mouse_x = (uic.mouse_x - draw_x) / fit_scale;
            sim.sub_ctx.mouse_y = (uic.mouse_y - draw_y) / fit_scale;
            if (uic.mouse_pressed) {
                sim.mouse_down_on_screen = true;
            }
            sim.sub_ctx.mouse_down = uic.mouse_down and sim.mouse_down_on_screen;
            sim.sub_ctx.mouse_pressed = uic.mouse_pressed and sim.mouse_down_on_screen;
            sim.sub_ctx.mouse_released = uic.mouse_released and sim.mouse_down_on_screen;
            if (uic.mouse_released) {
                sim.mouse_down_on_screen = false;
            }
            sim.sub_ctx.mouse_click_count = uic.mouse_click_count;
            sim.sub_ctx.right_mouse_down = uic.right_mouse_down;
            sim.sub_ctx.right_mouse_pressed = uic.right_mouse_pressed;
            sim.sub_ctx.right_mouse_released = uic.right_mouse_released;
            sim.sub_ctx.scroll_dx = uic.scroll_dx;
            sim.sub_ctx.scroll_dy = uic.scroll_dy;

            // Forward click & drag dirty signals so .paint always runs!
            if (uic.mouse_pressed) {
                uic.focused_id = resolved.wid;
                sim.sub_ctx.force_full_redraw = true;
                uic.markDirty(full_r);
            } else if (uic.mouse_down or uic.mouse_released or uic.scroll_dx != 0 or uic.scroll_dy != 0) {
                uic.markDirty(full_r);
            }
        } else {
            sim.sub_ctx.mouse_x = -1.0;
            sim.sub_ctx.mouse_y = -1.0;
            sim.sub_ctx.mouse_down = false;
            sim.sub_ctx.mouse_pressed = false;
            sim.sub_ctx.mouse_released = false;
            sim.sub_ctx.mouse_click_count = 0;
            sim.sub_ctx.right_mouse_down = false;
            sim.sub_ctx.right_mouse_pressed = false;
            sim.sub_ctx.right_mouse_released = false;
            sim.sub_ctx.scroll_dx = 0;
            sim.sub_ctx.scroll_dy = 0;
            if (uic.mouse_released) {
                sim.mouse_down_on_screen = false;
            }
        }

        // Forward keyboard input if focused
        if (uic.focused_id == resolved.wid and !sim.dropdown_open) {
            if (uic.platform_ctx) |hctx| {
                sim.sub_ctx.key_events = hctx.key_events;
                sim.sub_ctx.key_event_count = hctx.key_event_count;
                sim.sub_ctx.text_input_buf = hctx.text_input_buf;
                sim.sub_ctx.text_input_len = hctx.text_input_len;
                if (hctx.key_event_count > 0 or hctx.text_input_len > 0) {
                    sim.sub_ctx.force_full_redraw = true;
                    uic.markDirty(full_r);
                }
            }
        }

        // If continuous redraw or full redraw is requested, keep dirtying and notify host
        if (sim.sub_ctx.needs_continuous_redraw or sim.sub_ctx.force_full_redraw) {
            result.needs_continuous_redraw = true;
            uic.markDirty(full_r);
            if (uic.platform_ctx) |hctx| {
                hctx.needs_continuous_redraw = true;
            }
        }
    }

    // ------------------------------------------------------------------------
    // Pass 2 (`.paint`): Top toolbar, device bezel, scissor-clipped Skia canvas execution
    // ------------------------------------------------------------------------
    if (uic.pass == .paint and uic.shouldPaint(full_r)) {
        const theme = uic.theme;
        const font_body = uic.font_body;
        const font_mono = uic.font_mono;

        // 1. Toolbar Background
        const toolbar_r = Rect.xywh(full_r.left, full_r.top, w, toolbar_h);
        uic.paint.setStyle(.fill);
        uic.paint.setColor(Color.rgb(16, 21, 30));
        uic.canvas.drawRect(toolbar_r, uic.paint);
        uic.paint.setColor(theme.border_subtle);
        uic.canvas.drawRect(Rect.xywh(full_r.left, toolbar_r.bottom - 1.0, w, 1.0), uic.paint);

        // Badge [APP]
        uic.paint.setColor(Color.argb(45, 245, 158, 11));
        uic.canvas.drawRoundRect(badge_r, 4.0, 4.0, uic.paint);
        uic.paint.setColor(Color.rgb(245, 158, 11));
        const bw = uic.measureTextCached(font_mono, "APP");
        uic.drawTextCached(font_mono, "APP", badge_r.left + (badge_r.right - badge_r.left - bw) * 0.5, badge_r.top + 14.0);

        // Dropdown Trigger Button
        const dd_label = uic.fmt("{s} ⌄", .{sim.preset.deviceName()});
        drawToolbarChip(uic, font_mono, dd_btn_r, dd_label, sim.dropdown_open);

        // Orientation Toggle Button
        const orient_active = (sim.orientation == .landscape);
        drawToolbarChip(uic, font_mono, orient_btn_r, sim.orientation.shortLabel(), orient_active);

        // Scale Buttons
        drawToolbarChip(uic, font_body, fit_btn_r, "Fit", sim.zoom_fit);
        drawToolbarChip(uic, font_body, one_btn_r, "1:1", !sim.zoom_fit and @abs(sim.user_scale - 1.0) < 0.01);

        // Reload Pill
        const is_live = (sim.hot_dylib.handle != null);
        const reload_label = if (is_live)
            uic.fmt("● Gen #{d}", .{sim.hot_dylib.generation})
        else
            "○ Offline";
        const reload_bg = if (is_live) Color.argb(45, 34, 197, 94) else Color.argb(45, 239, 68, 68);
        const reload_fg = if (is_live) Color.rgb(34, 197, 94) else Color.rgb(239, 68, 68);
        uic.paint.setColor(reload_bg);
        uic.canvas.drawRoundRect(reload_btn_r, 4.0, 4.0, uic.paint);
        uic.paint.setColor(reload_fg);
        const rlw = uic.measureTextCached(font_mono, reload_label);
        uic.drawTextCached(font_mono, reload_label, reload_btn_r.left + (reload_btn_r.right - reload_btn_r.left - rlw) * 0.5, reload_btn_r.top + 16.0);

        // Path indicator on right side
        const dylib_slice = sim.getDylibPath();
        if (dylib_slice.len > 0) {
            const basename = if (std.mem.lastIndexOfScalar(u8, dylib_slice, '/')) |slash|
                dylib_slice[slash + 1 ..]
            else
                dylib_slice;
            const path_str = uic.fmt("{s}", .{basename});
            uic.paint.setColor(theme.text_muted);
            const pw = uic.measureTextCached(font_mono, path_str);
            if (full_r.right - pw - 12.0 > reload_btn_r.right + 20.0) {
                uic.drawTextCached(font_mono, path_str, full_r.right - pw - 12.0, btn_y + 16.0);
            }
        }

        // 2. Viewport Backdrop
        uic.paint.setColor(Color.rgb(10, 14, 20));
        uic.canvas.drawRect(canvas_r, uic.paint);

        // 3. Tablet / Phone Bezel (when not fill_pane)
        if (sim.preset != .fill_pane) {
            const corner_radius: f32 = if (sim.preset.isPhone()) 24.0 else if (sim.preset == .desktop_720p or sim.preset == .desktop_1080p) 4.0 else 12.0;
            const bezel_radius: f32 = if (sim.preset.isPhone()) 32.0 else if (sim.preset == .desktop_720p or sim.preset == .desktop_1080p) 6.0 else 16.0;
            const bezel_pad: f32 = if (sim.preset.isPhone()) 9.0 else if (sim.preset == .desktop_720p or sim.preset == .desktop_1080p) 4.0 else 8.0;

            const bezel_r = Rect.xywh(
                draw_x - bezel_pad,
                draw_y - bezel_pad,
                draw_w + bezel_pad * 2.0,
                draw_h + bezel_pad * 2.0,
            );
            // Drop shadow
            uic.paint.setColor(Color.argb(70, 0, 0, 0));
            uic.canvas.drawRoundRect(Rect.xywh(bezel_r.left, bezel_r.top + 3.0, bezel_r.right - bezel_r.left, bezel_r.bottom - bezel_r.top), bezel_radius, bezel_radius, uic.paint);
            // Bezel frame
            uic.paint.setColor(Color.rgb(30, 36, 48));
            uic.canvas.drawRoundRect(bezel_r, bezel_radius, bezel_radius, uic.paint);
            uic.paint.setStyle(.stroke);
            uic.paint.setStrokeWidth(1.0);
            uic.paint.setColor(Color.rgb(55, 65, 81));
            uic.canvas.drawRoundRect(bezel_r, bezel_radius, bezel_radius, uic.paint);
            uic.paint.setStyle(.fill);
            _ = corner_radius;
        }

        // 4. Scissor-Clipped Skia Viewport Rendering
        const canvas_ptr = uic.canvas.ptr;
        _ = c.sk_canvas_save(canvas_ptr);

        const clip_r = c.sk_rect_t{
            .left = draw_x,
            .top = draw_y,
            .right = draw_x + draw_w,
            .bottom = draw_y + draw_h,
        };
        uic.canvas.clipRect(clip_r, .intersect, true);

        c.sk_canvas_translate(canvas_ptr, draw_x, draw_y);
        c.sk_canvas_scale(canvas_ptr, fit_scale, fit_scale);

        // Update sub-context handles
        sim.sub_ctx.width = virtual_w;
        sim.sub_ctx.height = virtual_h;
        sim.sub_ctx.canvas = canvas_ptr;
        sim.sub_ctx.gr_context = if (uic.platform_ctx) |pc| pc.gr_context else null;
        sim.sub_ctx.font_mgr = if (uic.platform_ctx) |pc| pc.font_mgr else null;
        sim.sub_ctx.dpi_scale = if (uic.platform_ctx) |pc| pc.dpi_scale else 1.0;
        sim.sub_ctx.frame_count = if (uic.platform_ctx) |pc| pc.frame_count else 0;

        // Force child app to render its full stage when host paints
        sim.sub_ctx.force_full_redraw = true;

        if (sim.hot_dylib.app_tick) |tick_fn| {
            const needs_redraw = tick_fn(&sim.sub_ctx);
            if (needs_redraw or sim.sub_ctx.needs_continuous_redraw) {
                result.needs_continuous_redraw = true;
                if (uic.platform_ctx) |hctx| {
                    hctx.needs_continuous_redraw = true;
                }
                uic.invalidateWindow();
            }
            // Consume transient inputs
            sim.sub_ctx.mouse_pressed = false;
            sim.sub_ctx.mouse_released = false;
            sim.sub_ctx.key_event_count = 0;
            sim.sub_ctx.text_input_len = 0;
        } else {
            // Draw placeholder screen
            const scr_r = Rect.xywh(0.0, 0.0, virtual_w, virtual_h);
            uic.paint.setColor(Color.rgb(18, 24, 38));
            uic.canvas.drawRect(scr_r, uic.paint);

            uic.paint.setColor(Color.rgb(245, 158, 11));
            const msg1 = "⚡ App Simulator";
            const w1 = uic.measureTextCached(font_body, msg1);
            uic.drawTextCached(font_body, msg1, (virtual_w - w1) * 0.5, virtual_h * 0.45);

            uic.paint.setColor(theme.text_muted);
            const msg2 = if (sim.dylib_path_len > 0)
                sim.getDylibPath()
            else
                "No .dylib loaded. Build your project or configure preview in tasks.json / launch.json";
            const w2 = uic.measureTextCached(font_mono, msg2);
            uic.drawTextCached(font_mono, msg2, (virtual_w - w2) * 0.5, virtual_h * 0.45 + 28.0);
        }

        c.sk_canvas_restore(canvas_ptr);

        // 5. Floating Device Dropdown Overlay (rendered on top of everything)
        if (sim.dropdown_open) {
            const prev_in_overlay = uic.in_overlay;
            uic.in_overlay = true;
            defer uic.in_overlay = prev_in_overlay;

            // Drop shadow
            uic.paint.setColor(Color.argb(140, 0, 0, 0));
            uic.canvas.drawRoundRect(Rect.xywh(menu_r.left, menu_r.top + 4.0, menu_w, menu_h), 8.0, 8.0, uic.paint);

            // Card background
            uic.paint.setStyle(.fill);
            uic.paint.setColor(Color.rgb(20, 26, 38));
            uic.canvas.drawRoundRect(menu_r, 8.0, 8.0, uic.paint);

            // Card border
            uic.paint.setStyle(.stroke);
            uic.paint.setStrokeWidth(1.0);
            uic.paint.setColor(Color.rgb(56, 75, 105));
            uic.canvas.drawRoundRect(menu_r, 8.0, 8.0, uic.paint);
            uic.paint.setStyle(.fill);

            var cur_y = menu_y + 6.0;
            var cur_cat: ?DeviceCategory = null;

            for (DevicePreset.ALL) |preset| {
                const cat = preset.category();
                if (cur_cat == null or cur_cat.? != cat) {
                    cur_cat = cat;
                    // Section header
                    uic.paint.setColor(Color.rgb(56, 189, 248));
                    uic.drawTextCached(font_mono, cat.title(), menu_x + 10.0, cur_y + 13.0);
                    cur_y += 18.0;
                }

                const item_r = Rect.xywh(menu_x + 6.0, cur_y, menu_w - 12.0, 24.0);
                const item_wid = id(preset.deviceName());
                const is_sel = (sim.preset == preset);
                const is_hover = (uic.hot_id == item_wid) or uic.isHovered(item_r);

                if (is_sel or is_hover) {
                    uic.paint.setColor(if (is_sel) Color.argb(60, 56, 139, 253) else Color.rgb(32, 41, 58));
                    uic.canvas.drawRoundRect(item_r, 4.0, 4.0, uic.paint);
                }

                // Checkmark if selected
                if (is_sel) {
                    uic.paint.setColor(Color.rgb(56, 189, 248));
                    uic.drawTextCached(font_mono, "✓", item_r.left + 6.0, cur_y + 16.0);
                }

                // Device title
                const name_x = if (is_sel) item_r.left + 22.0 else item_r.left + 10.0;
                uic.paint.setColor(if (is_sel) Color.rgb(255, 255, 255) else if (is_hover) Color.rgb(240, 246, 252) else Color.rgb(200, 210, 225));
                uic.drawTextCached(font_body, preset.deviceName(), name_x, cur_y + 16.5);

                // Ratio / dimension badge on right
                const ratio_str = preset.ratioLabel(sim.orientation);
                uic.paint.setColor(if (is_sel) Color.rgb(148, 163, 184) else Color.rgb(110, 122, 140));
                const rw = uic.measureTextCached(font_mono, ratio_str);
                uic.drawTextCached(font_mono, ratio_str, item_r.right - rw - 8.0, cur_y + 16.0);

                cur_y += 24.0;
            }

            // Divider
            uic.paint.setColor(Color.rgb(42, 52, 70));
            uic.canvas.drawRect(Rect.xywh(menu_x + 8.0, cur_y + 3.0, menu_w - 16.0, 1.0), uic.paint);

            // Rotate row
            const rotate_r = Rect.xywh(menu_x + 6.0, cur_y + 6.0, menu_w - 12.0, 26.0);
            const rot_wid = id("sim_item_rotate");
            const rot_hover = (uic.hot_id == rot_wid) or uic.isHovered(rotate_r);
            if (rot_hover) {
                uic.paint.setColor(Color.rgb(32, 41, 58));
                uic.canvas.drawRoundRect(rotate_r, 4.0, 4.0, uic.paint);
            }
            const rot_target = sim.orientation.toggle();
            const rot_dims = sim.preset.dimensions(rot_target, canvas_w, canvas_h);
            const rot_label = uic.fmt("↻ Rotate to {s} ({d}×{d})", .{
                rot_target.label(),
                @as(u32, @intFromFloat(rot_dims[0])),
                @as(u32, @intFromFloat(rot_dims[1])),
            });
            uic.paint.setColor(if (rot_hover) Color.rgb(56, 189, 248) else Color.rgb(148, 163, 184));
            uic.drawTextCached(font_body, rot_label, rotate_r.left + 10.0, rotate_r.top + 17.5);
        }
    }

    return result;
}
