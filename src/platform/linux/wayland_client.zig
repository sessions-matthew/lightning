//! Native Linux Wayland Client Backend (`src/platform/linux/wayland_client.zig`).
//!
//! Dynamically resolves `libwayland-client.so.0` and `libxkbcommon.so.0` at runtime via
//! `dlopen`/`dlsym` (zero `@cImport` and zero compile-time sysroot dependencies when
//! cross-compiling from macOS or Windows).
//!
//! Implements:
//!   - `wl_compositor`, `wl_surface`, `wl_shm`, `wl_shm_pool`, `wl_buffer` (`memfd_create` + `mmap`)
//!   - `xdg_wm_base`, `xdg_surface`, `xdg_toplevel` (resize, maximize, minimize, interactive titlebar drag, close)
//!   - `zxdg_decoration_manager_v1` / `zxdg_toplevel_decoration_v1` (client-side borderless titlebar)
//!   - `wl_seat`, `wl_pointer` (motion, left/right click, smooth/discrete scroll), `wl_keyboard` (`xkbcommon` + evdev fallback)

const std = @import("std");
const builtin = @import("builtin");
const app_api = @import("../app_api.zig");
const fs_util = @import("../fs_util.zig");
const objc = @import("../macos/objc.zig");

pub const wl_display = opaque {};
pub const wl_proxy = opaque {};

pub const wl_message = extern struct {
    name: [*:0]const u8,
    signature: [*:0]const u8,
    types: [*]const ?*const wl_interface,
};

pub const wl_interface = extern struct {
    name: [*:0]const u8,
    version: c_int,
    method_count: c_int,
    methods: ?[*]const wl_message,
    event_count: c_int,
    events: ?[*]const wl_message,
};

pub const wl_array = extern struct {
    size: usize,
    alloc: usize,
    data: ?*anyopaque,
};

pub const wl_argument = extern union {
    i: i32,
    u: u32,
    f: i32, // 24.8 fixed-point (`wl_fixed_t`)
    s: ?[*:0]const u8,
    o: ?*wl_proxy,
    n: u32,
    a: ?*const wl_array,
    h: i32,
};

pub inline fn wlFixedToF32(f: i32) f32 {
    return @as(f32, @floatFromInt(f)) / 256.0;
}

const WL_MARSHAL_FLAG_DESTROY: u32 = 1 << 0;
const WL_SHM_FORMAT_ARGB8888: u32 = 0;

const WL_SEAT_CAPABILITY_POINTER: u32 = 1 << 0;
const WL_SEAT_CAPABILITY_KEYBOARD: u32 = 1 << 1;

const BTN_LEFT: u32 = 0x110;
const BTN_RIGHT: u32 = 0x111;

// ============================================================================
// Static `xdg-shell` & `xdg-decoration-unstable-v1` Protocol Interfaces
// ============================================================================
const null_types = [8]?*const wl_interface{ null, null, null, null, null, null, null, null };

pub const xdg_positioner_interface: wl_interface = .{
    .name = "xdg_positioner",
    .version = 1,
    .method_count = 1,
    .methods = &[_]wl_message{
        .{ .name = "destroy", .signature = "", .types = &null_types },
    },
    .event_count = 0,
    .events = null,
};

const xdg_wm_base_create_positioner_types = [_]?*const wl_interface{&xdg_positioner_interface};
const xdg_wm_base_get_xdg_surface_types = [_]?*const wl_interface{ &xdg_surface_interface, null };

pub const xdg_wm_base_interface: wl_interface = .{
    .name = "xdg_wm_base",
    .version = 1,
    .method_count = 4,
    .methods = &[_]wl_message{
        .{ .name = "destroy", .signature = "", .types = &null_types },
        .{ .name = "create_positioner", .signature = "n", .types = &xdg_wm_base_create_positioner_types },
        .{ .name = "get_xdg_surface", .signature = "no", .types = &xdg_wm_base_get_xdg_surface_types },
        .{ .name = "pong", .signature = "u", .types = &null_types },
    },
    .event_count = 1,
    .events = &[_]wl_message{
        .{ .name = "ping", .signature = "u", .types = &null_types },
    },
};

const xdg_surface_get_toplevel_types = [_]?*const wl_interface{&xdg_toplevel_interface};

pub const xdg_surface_interface: wl_interface = .{
    .name = "xdg_surface",
    .version = 1,
    .method_count = 5,
    .methods = &[_]wl_message{
        .{ .name = "destroy", .signature = "", .types = &null_types },
        .{ .name = "get_toplevel", .signature = "n", .types = &xdg_surface_get_toplevel_types },
        .{ .name = "get_popup", .signature = "n?oo", .types = &null_types },
        .{ .name = "set_window_geometry", .signature = "iiii", .types = &null_types },
        .{ .name = "ack_configure", .signature = "u", .types = &null_types },
    },
    .event_count = 1,
    .events = &[_]wl_message{
        .{ .name = "configure", .signature = "u", .types = &null_types },
    },
};

const xdg_toplevel_set_parent_types = [_]?*const wl_interface{&xdg_toplevel_interface};

pub const xdg_toplevel_interface: wl_interface = .{
    .name = "xdg_toplevel",
    .version = 1,
    .method_count = 14,
    .methods = &[_]wl_message{
        .{ .name = "destroy", .signature = "", .types = &null_types },
        .{ .name = "set_parent", .signature = "?o", .types = &xdg_toplevel_set_parent_types },
        .{ .name = "set_title", .signature = "s", .types = &null_types },
        .{ .name = "set_app_id", .signature = "s", .types = &null_types },
        .{ .name = "show_window_menu", .signature = "ouii", .types = &null_types },
        .{ .name = "move", .signature = "ou", .types = &null_types },
        .{ .name = "resize", .signature = "ouu", .types = &null_types },
        .{ .name = "set_max_size", .signature = "ii", .types = &null_types },
        .{ .name = "set_min_size", .signature = "ii", .types = &null_types },
        .{ .name = "set_maximized", .signature = "", .types = &null_types },
        .{ .name = "unset_maximized", .signature = "", .types = &null_types },
        .{ .name = "set_fullscreen", .signature = "?o", .types = &null_types },
        .{ .name = "unset_fullscreen", .signature = "", .types = &null_types },
        .{ .name = "set_minimized", .signature = "", .types = &null_types },
    },
    .event_count = 2,
    .events = &[_]wl_message{
        .{ .name = "configure", .signature = "iia", .types = &null_types },
        .{ .name = "close", .signature = "", .types = &null_types },
    },
};

const zxdg_get_decoration_types = [_]?*const wl_interface{
    &zxdg_toplevel_decoration_v1_interface,
    &xdg_toplevel_interface,
};

pub const zxdg_decoration_manager_v1_interface: wl_interface = .{
    .name = "zxdg_decoration_manager_v1",
    .version = 1,
    .method_count = 2,
    .methods = &[_]wl_message{
        .{ .name = "destroy", .signature = "", .types = &null_types },
        .{ .name = "get_toplevel_decoration", .signature = "no", .types = &zxdg_get_decoration_types },
    },
    .event_count = 0,
    .events = null,
};

pub const zxdg_toplevel_decoration_v1_interface: wl_interface = .{
    .name = "zxdg_toplevel_decoration_v1",
    .version = 1,
    .method_count = 3,
    .methods = &[_]wl_message{
        .{ .name = "destroy", .signature = "", .types = &null_types },
        .{ .name = "set_mode", .signature = "u", .types = &null_types },
        .{ .name = "unset_mode", .signature = "", .types = &null_types },
    },
    .event_count = 1,
    .events = &[_]wl_message{
        .{ .name = "configure", .signature = "u", .types = &null_types },
    },
};

// ============================================================================
// Linux Shared Memory Syscalls (`memfd_create` / `ftruncate` / `mmap` / `munmap`)
// ============================================================================
const linux_c = struct {
    const PROT_READ: c_int = 1;
    const PROT_WRITE: c_int = 2;
    const MAP_SHARED: c_int = 1;
    const MAP_PRIVATE: c_int = 2;
    const MFD_CLOEXEC: c_uint = 1;

    extern "c" fn memfd_create(name: [*:0]const u8, flags: c_uint) c_int;
    extern "c" fn ftruncate(fd: c_int, length: isize) c_int;
    extern "c" fn mmap(addr: ?*anyopaque, len: usize, prot: c_int, flags: c_int, fd: c_int, offset: isize) ?*anyopaque;
    extern "c" fn munmap(addr: *anyopaque, len: usize) c_int;
    extern "c" fn close(fd: c_int) c_int;
    extern "c" fn getuid() c_uint;
};

// ============================================================================
// Dynamic `libwayland-client.so.0` and `libxkbcommon.so.0` Function Tables
// ============================================================================
pub const WaylandApi = struct {
    handle: *anyopaque,
    wl_display_connect: *const fn (?[*:0]const u8) callconv(.c) ?*wl_display,
    wl_display_disconnect: *const fn (*wl_display) callconv(.c) void,
    wl_display_dispatch: *const fn (*wl_display) callconv(.c) c_int,
    wl_display_dispatch_pending: *const fn (*wl_display) callconv(.c) c_int,
    wl_display_roundtrip: *const fn (*wl_display) callconv(.c) c_int,
    wl_display_flush: *const fn (*wl_display) callconv(.c) c_int,
    wl_display_prepare_read: *const fn (*wl_display) callconv(.c) c_int,
    wl_display_read_events: *const fn (*wl_display) callconv(.c) c_int,
    wl_display_cancel_read: *const fn (*wl_display) callconv(.c) void,
    wl_display_get_fd: *const fn (*wl_display) callconv(.c) c_int,
    wl_proxy_marshal_array_flags: *const fn (*wl_proxy, u32, ?*const wl_interface, u32, u32, ?[*]wl_argument) callconv(.c) ?*wl_proxy,
    wl_proxy_add_listener: *const fn (*wl_proxy, [*]const ?*const anyopaque, ?*anyopaque) callconv(.c) c_int,
    wl_proxy_destroy: *const fn (*wl_proxy) callconv(.c) void,
    wl_proxy_get_version: *const fn (*wl_proxy) callconv(.c) u32,

    wl_registry_interface: *const wl_interface,
    wl_compositor_interface: *const wl_interface,
    wl_surface_interface: *const wl_interface,
    wl_shm_interface: *const wl_interface,
    wl_shm_pool_interface: *const wl_interface,
    wl_buffer_interface: *const wl_interface,
    wl_seat_interface: *const wl_interface,
    wl_pointer_interface: *const wl_interface,
    wl_keyboard_interface: *const wl_interface,

    pub fn load() ?WaylandApi {
        if (comptime builtin.os.tag != .linux) return null;
        const h = objc.dlopen("libwayland-client.so.0", objc.RTLD_NOW) orelse
            objc.dlopen("libwayland-client.so", objc.RTLD_NOW) orelse return null;
        return .{
            .handle = h,
            .wl_display_connect = @ptrCast(@alignCast(objc.dlsym(h, "wl_display_connect") orelse return null)),
            .wl_display_disconnect = @ptrCast(@alignCast(objc.dlsym(h, "wl_display_disconnect") orelse return null)),
            .wl_display_dispatch = @ptrCast(@alignCast(objc.dlsym(h, "wl_display_dispatch") orelse return null)),
            .wl_display_dispatch_pending = @ptrCast(@alignCast(objc.dlsym(h, "wl_display_dispatch_pending") orelse return null)),
            .wl_display_roundtrip = @ptrCast(@alignCast(objc.dlsym(h, "wl_display_roundtrip") orelse return null)),
            .wl_display_flush = @ptrCast(@alignCast(objc.dlsym(h, "wl_display_flush") orelse return null)),
            .wl_display_prepare_read = @ptrCast(@alignCast(objc.dlsym(h, "wl_display_prepare_read") orelse return null)),
            .wl_display_read_events = @ptrCast(@alignCast(objc.dlsym(h, "wl_display_read_events") orelse return null)),
            .wl_display_cancel_read = @ptrCast(@alignCast(objc.dlsym(h, "wl_display_cancel_read") orelse return null)),
            .wl_display_get_fd = @ptrCast(@alignCast(objc.dlsym(h, "wl_display_get_fd") orelse return null)),
            .wl_proxy_marshal_array_flags = @ptrCast(@alignCast(objc.dlsym(h, "wl_proxy_marshal_array_flags") orelse return null)),
            .wl_proxy_add_listener = @ptrCast(@alignCast(objc.dlsym(h, "wl_proxy_add_listener") orelse return null)),
            .wl_proxy_destroy = @ptrCast(@alignCast(objc.dlsym(h, "wl_proxy_destroy") orelse return null)),
            .wl_proxy_get_version = @ptrCast(@alignCast(objc.dlsym(h, "wl_proxy_get_version") orelse return null)),
            .wl_registry_interface = @ptrCast(@alignCast(objc.dlsym(h, "wl_registry_interface") orelse return null)),
            .wl_compositor_interface = @ptrCast(@alignCast(objc.dlsym(h, "wl_compositor_interface") orelse return null)),
            .wl_surface_interface = @ptrCast(@alignCast(objc.dlsym(h, "wl_surface_interface") orelse return null)),
            .wl_shm_interface = @ptrCast(@alignCast(objc.dlsym(h, "wl_shm_interface") orelse return null)),
            .wl_shm_pool_interface = @ptrCast(@alignCast(objc.dlsym(h, "wl_shm_pool_interface") orelse return null)),
            .wl_buffer_interface = @ptrCast(@alignCast(objc.dlsym(h, "wl_buffer_interface") orelse return null)),
            .wl_seat_interface = @ptrCast(@alignCast(objc.dlsym(h, "wl_seat_interface") orelse return null)),
            .wl_pointer_interface = @ptrCast(@alignCast(objc.dlsym(h, "wl_pointer_interface") orelse return null)),
            .wl_keyboard_interface = @ptrCast(@alignCast(objc.dlsym(h, "wl_keyboard_interface") orelse return null)),
        };
    }
};

const xkb_context = opaque {};
const xkb_keymap = opaque {};
const xkb_state = opaque {};

pub const XkbApi = struct {
    handle: *anyopaque,
    xkb_context_new: *const fn (c_int) callconv(.c) ?*xkb_context,
    xkb_context_unref: *const fn (*xkb_context) callconv(.c) void,
    xkb_keymap_new_from_string: *const fn (*xkb_context, [*:0]const u8, c_int, c_int) callconv(.c) ?*xkb_keymap,
    xkb_keymap_unref: *const fn (*xkb_keymap) callconv(.c) void,
    xkb_state_new: *const fn (*xkb_keymap) callconv(.c) ?*xkb_state,
    xkb_state_unref: *const fn (*xkb_state) callconv(.c) void,
    xkb_state_update_mask: *const fn (*xkb_state, u32, u32, u32, u32, u32, u32) callconv(.c) c_int,
    xkb_state_key_get_one_sym: *const fn (*xkb_state, u32) callconv(.c) u32,
    xkb_state_key_get_utf8: *const fn (*xkb_state, u32, [*]u8, usize) callconv(.c) c_int,

    pub fn load() ?XkbApi {
        if (comptime builtin.os.tag != .linux) return null;
        const h = objc.dlopen("libxkbcommon.so.0", objc.RTLD_NOW) orelse
            objc.dlopen("libxkbcommon.so", objc.RTLD_NOW) orelse return null;
        return .{
            .handle = h,
            .xkb_context_new = @ptrCast(@alignCast(objc.dlsym(h, "xkb_context_new") orelse return null)),
            .xkb_context_unref = @ptrCast(@alignCast(objc.dlsym(h, "xkb_context_unref") orelse return null)),
            .xkb_keymap_new_from_string = @ptrCast(@alignCast(objc.dlsym(h, "xkb_keymap_new_from_string") orelse return null)),
            .xkb_keymap_unref = @ptrCast(@alignCast(objc.dlsym(h, "xkb_keymap_unref") orelse return null)),
            .xkb_state_new = @ptrCast(@alignCast(objc.dlsym(h, "xkb_state_new") orelse return null)),
            .xkb_state_unref = @ptrCast(@alignCast(objc.dlsym(h, "xkb_state_unref") orelse return null)),
            .xkb_state_update_mask = @ptrCast(@alignCast(objc.dlsym(h, "xkb_state_update_mask") orelse return null)),
            .xkb_state_key_get_one_sym = @ptrCast(@alignCast(objc.dlsym(h, "xkb_state_key_get_one_sym") orelse return null)),
            .xkb_state_key_get_utf8 = @ptrCast(@alignCast(objc.dlsym(h, "xkb_state_key_get_utf8") orelse return null)),
        };
    }
};

// ============================================================================
// Non-Blocking Socket Poll (`poll` syscall on `wl_display_get_fd`)
// ============================================================================
const pollfd = extern struct {
    fd: c_int,
    events: i16,
    revents: i16,
};
const POLLIN: i16 = 0x001;
extern "c" fn poll(fds: [*]pollfd, nfds: c_ulong, timeout: c_int) c_int;

// ============================================================================
// Wayland Window & Event State
// ============================================================================
pub const WaylandState = struct {
    wl: WaylandApi,
    xkb: ?XkbApi = null,
    xkb_ctx: ?*xkb_context = null,
    xkb_map: ?*xkb_keymap = null,
    xkb_st: ?*xkb_state = null,

    display: *wl_display,
    registry: *wl_proxy,
    compositor: ?*wl_proxy = null,
    shm: ?*wl_proxy = null,
    wm_base: ?*wl_proxy = null,
    decoration_mgr: ?*wl_proxy = null,
    seat: ?*wl_proxy = null,
    pointer: ?*wl_proxy = null,
    keyboard: ?*wl_proxy = null,

    surface: ?*wl_proxy = null,
    xdg_surface: ?*wl_proxy = null,
    xdg_toplevel: ?*wl_proxy = null,
    toplevel_decoration: ?*wl_proxy = null,

    shm_fd: c_int = -1,
    shm_data: ?[*]u32 = null,
    shm_byte_len: usize = 0,
    shm_pool: ?*wl_proxy = null,
    shm_buffer: ?*wl_proxy = null,
    shm_w: i32 = 0,
    shm_h: i32 = 0,

    configured: bool = false,
    pending_w: i32 = 0,
    pending_h: i32 = 0,
    last_pointer_serial: u32 = 0,

    mod_shift: bool = false,
    mod_ctrl: bool = false,
    mod_alt: bool = false,
    mod_super: bool = false,

    ctx: *app_api.PlatformContext,
    win_w: *i32,
    win_h: *i32,
    quit_requested: *bool,
    is_maximized: *bool,
    had_event: *bool,
    mouse_down: *bool,
    right_mouse_down: *bool,
    saw_left_down: *bool,
    saw_left_up: *bool,
    saw_right_down: *bool,
    saw_right_up: *bool,
    translateKeySymFn: *const fn (c_ulong) app_api.KeyCode,

    pub fn init(
        ctx: *app_api.PlatformContext,
        title: [*:0]const u8,
        win_w: *i32,
        win_h: *i32,
        quit_requested: *bool,
        is_maximized: *bool,
        had_event: *bool,
        mouse_down: *bool,
        right_mouse_down: *bool,
        saw_left_down: *bool,
        saw_left_up: *bool,
        saw_right_down: *bool,
        saw_right_up: *bool,
        translateKeySymFn: *const fn (c_ulong) app_api.KeyCode,
        force_wayland: bool,
    ) ?*WaylandState {
        if (comptime builtin.os.tag != .linux) return null;

        const has_wl_env = (fs_util.getenv("WAYLAND_DISPLAY") != null);
        const has_x11_env = (fs_util.getenv("DISPLAY") != null);
        if (!has_wl_env and !force_wayland and has_x11_env) return null;

        const wl = WaylandApi.load() orelse return null;

        var dpy_opt = if (has_wl_env or fs_util.getenv("XDG_RUNTIME_DIR") != null)
            wl.wl_display_connect(null)
        else
            null;
        if (dpy_opt == null) {
            // If XDG_RUNTIME_DIR/WAYLAND_DISPLAY are unset (e.g. launched over SSH), probe `/run/user/<uid>/wayland-0`
            var sock_buf: [128:0]u8 = @splat(0);
            const uid = linux_c.getuid();
            if (std.fmt.bufPrint(sock_buf[0..126], "/run/user/{d}/wayland-0", .{uid})) |s| {
                sock_buf[s.len] = 0;
                if (fs_util.pathExistsOnDisk(&sock_buf)) {
                    dpy_opt = wl.wl_display_connect(&sock_buf);
                }
            } else |_| {}
        }
        const dpy = dpy_opt orelse return null;

        // `wl_display.get_registry` (opcode 1, signature "n")
        var reg_args = [_]wl_argument{.{ .n = 0 }};
        const reg = wl.wl_proxy_marshal_array_flags(
            @ptrCast(dpy),
            1,
            wl.wl_registry_interface,
            1,
            0,
            &reg_args,
        ) orelse {
            wl.wl_display_disconnect(dpy);
            return null;
        };

        const self = std.heap.c_allocator.create(WaylandState) catch {
            wl.wl_display_disconnect(dpy);
            return null;
        };
        self.* = .{
            .wl = wl,
            .xkb = XkbApi.load(),
            .display = dpy,
            .registry = reg,
            .ctx = ctx,
            .win_w = win_w,
            .win_h = win_h,
            .quit_requested = quit_requested,
            .is_maximized = is_maximized,
            .had_event = had_event,
            .mouse_down = mouse_down,
            .right_mouse_down = right_mouse_down,
            .saw_left_down = saw_left_down,
            .saw_left_up = saw_left_up,
            .saw_right_down = saw_right_down,
            .saw_right_up = saw_right_up,
            .translateKeySymFn = translateKeySymFn,
        };

        if (self.xkb) |xkb| {
            self.xkb_ctx = xkb.xkb_context_new(0);
        }

        _ = wl.wl_proxy_add_listener(reg, &registry_listener, self);
        _ = wl.wl_display_roundtrip(dpy);
        _ = wl.wl_display_roundtrip(dpy);

        const comp = self.compositor orelse {
            self.deinit();
            return null;
        };
        const wm_base = self.wm_base orelse {
            self.deinit();
            return null;
        };
        if (self.shm == null) {
            self.deinit();
            return null;
        }

        // `wl_compositor.create_surface` (opcode 0, signature "n")
        var surf_args = [_]wl_argument{.{ .n = 0 }};
        const surf = wl.wl_proxy_marshal_array_flags(
            comp,
            0,
            wl.wl_surface_interface,
            1,
            0,
            &surf_args,
        ) orelse {
            self.deinit();
            return null;
        };
        self.surface = surf;

        // `xdg_wm_base.get_xdg_surface` (opcode 2, signature "no")
        var xdg_surf_args = [_]wl_argument{
            .{ .n = 0 },
            .{ .o = surf },
        };
        const xdg_surf = wl.wl_proxy_marshal_array_flags(
            wm_base,
            2,
            &xdg_surface_interface,
            1,
            0,
            &xdg_surf_args,
        ) orelse {
            self.deinit();
            return null;
        };
        self.xdg_surface = xdg_surf;
        _ = wl.wl_proxy_add_listener(xdg_surf, &xdg_surface_listener, self);

        // `xdg_surface.get_toplevel` (opcode 1, signature "n")
        var top_args = [_]wl_argument{.{ .n = 0 }};
        const top = wl.wl_proxy_marshal_array_flags(
            xdg_surf,
            1,
            &xdg_toplevel_interface,
            1,
            0,
            &top_args,
        ) orelse {
            self.deinit();
            return null;
        };
        self.xdg_toplevel = top;
        _ = wl.wl_proxy_add_listener(top, &xdg_toplevel_listener, self);

        // Request client-side decorations (`MODE_CLIENT_SIDE = 1`) when `zxdg_decoration_manager_v1` is available
        if (self.decoration_mgr) |dmgr| {
            var dec_args = [_]wl_argument{
                .{ .n = 0 },
                .{ .o = top },
            };
            if (wl.wl_proxy_marshal_array_flags(
                dmgr,
                1,
                &zxdg_toplevel_decoration_v1_interface,
                1,
                0,
                &dec_args,
            )) |dec| {
                self.toplevel_decoration = dec;
                _ = wl.wl_proxy_add_listener(dec, &toplevel_decoration_listener, self);
                var mode_args = [_]wl_argument{.{ .u = 1 }}; // 1 = client-side decorations
                _ = wl.wl_proxy_marshal_array_flags(dec, 1, null, 1, 0, &mode_args);
            }
        }

        // `xdg_toplevel.set_title` (opcode 2, signature "s") & `set_app_id` (opcode 3, signature "s")
        var title_args = [_]wl_argument{.{ .s = title }};
        _ = wl.wl_proxy_marshal_array_flags(top, 2, null, 1, 0, &title_args);
        var app_args = [_]wl_argument{.{ .s = "lightning" }};
        _ = wl.wl_proxy_marshal_array_flags(top, 3, null, 1, 0, &app_args);

        // Initial `wl_surface.commit` (opcode 6) + roundtrip to receive initial `xdg_surface.configure`
        _ = wl.wl_proxy_marshal_array_flags(surf, 6, null, 1, 0, null);
        _ = wl.wl_display_roundtrip(dpy);

        return self;
    }

    pub fn deinit(self: *WaylandState) void {
        const wl = self.wl;
        self.destroyShmBuffer();
        if (self.toplevel_decoration) |d| _ = wl.wl_proxy_marshal_array_flags(d, 0, null, 1, WL_MARSHAL_FLAG_DESTROY, null);
        if (self.xdg_toplevel) |t| _ = wl.wl_proxy_marshal_array_flags(t, 0, null, 1, WL_MARSHAL_FLAG_DESTROY, null);
        if (self.xdg_surface) |s| _ = wl.wl_proxy_marshal_array_flags(s, 0, null, 1, WL_MARSHAL_FLAG_DESTROY, null);
        if (self.surface) |s| _ = wl.wl_proxy_marshal_array_flags(s, 0, null, 1, WL_MARSHAL_FLAG_DESTROY, null);
        if (self.pointer) |p| wl.wl_proxy_destroy(p);
        if (self.keyboard) |k| wl.wl_proxy_destroy(k);
        if (self.seat) |s| wl.wl_proxy_destroy(s);
        if (self.decoration_mgr) |m| _ = wl.wl_proxy_marshal_array_flags(m, 0, null, 1, WL_MARSHAL_FLAG_DESTROY, null);
        if (self.wm_base) |w| _ = wl.wl_proxy_marshal_array_flags(w, 0, null, 1, WL_MARSHAL_FLAG_DESTROY, null);
        if (self.shm) |s| wl.wl_proxy_destroy(s);
        if (self.compositor) |c| wl.wl_proxy_destroy(c);
        wl.wl_proxy_destroy(self.registry);

        if (self.xkb) |xkb| {
            if (self.xkb_st) |st| xkb.xkb_state_unref(st);
            if (self.xkb_map) |mp| xkb.xkb_keymap_unref(mp);
            if (self.xkb_ctx) |cx| xkb.xkb_context_unref(cx);
        }

        wl.wl_display_disconnect(self.display);
        std.heap.c_allocator.destroy(self);
    }

    fn destroyShmBuffer(self: *WaylandState) void {
        const wl = self.wl;
        if (self.shm_buffer) |b| {
            _ = wl.wl_proxy_marshal_array_flags(b, 0, null, 1, WL_MARSHAL_FLAG_DESTROY, null);
            self.shm_buffer = null;
        }
        if (self.shm_pool) |p| {
            _ = wl.wl_proxy_marshal_array_flags(p, 1, null, 1, WL_MARSHAL_FLAG_DESTROY, null);
            self.shm_pool = null;
        }
        if (self.shm_data) |ptr| {
            _ = linux_c.munmap(@ptrCast(ptr), self.shm_byte_len);
            self.shm_data = null;
        }
        if (self.shm_fd >= 0) {
            _ = linux_c.close(self.shm_fd);
            self.shm_fd = -1;
        }
        self.shm_byte_len = 0;
        self.shm_w = 0;
        self.shm_h = 0;
    }

    fn ensureShmBuffer(self: *WaylandState, w: i32, h: i32) bool {
        if (self.shm_buffer != null and self.shm_w == w and self.shm_h == h and self.shm_data != null) {
            return true;
        }
        self.destroyShmBuffer();

        const shm = self.shm orelse return false;
        const wl = self.wl;
        const stride: i32 = w * 4;
        const byte_len: usize = @intCast(stride * h);
        if (byte_len == 0) return false;

        const fd = linux_c.memfd_create("lightning-wl-shm", linux_c.MFD_CLOEXEC);
        if (fd < 0) return false;
        if (linux_c.ftruncate(fd, @intCast(byte_len)) != 0) {
            _ = linux_c.close(fd);
            return false;
        }

        const mapped = linux_c.mmap(
            null,
            byte_len,
            linux_c.PROT_READ | linux_c.PROT_WRITE,
            linux_c.MAP_SHARED,
            fd,
            0,
        );
        if (mapped == null or @intFromPtr(mapped.?) == std.math.maxInt(usize)) {
            _ = linux_c.close(fd);
            return false;
        }

        // `wl_shm.create_pool` (opcode 0, signature "nhi")
        var pool_args = [_]wl_argument{
            .{ .n = 0 },
            .{ .h = fd },
            .{ .i = @intCast(byte_len) },
        };
        const pool = wl.wl_proxy_marshal_array_flags(
            shm,
            0,
            wl.wl_shm_pool_interface,
            1,
            0,
            &pool_args,
        ) orelse {
            _ = linux_c.munmap(mapped.?, byte_len);
            _ = linux_c.close(fd);
            return false;
        };

        // `wl_shm_pool.create_buffer` (opcode 0, signature "niiiiu")
        var buf_args = [_]wl_argument{
            .{ .n = 0 },
            .{ .i = 0 },
            .{ .i = w },
            .{ .i = h },
            .{ .i = stride },
            .{ .u = WL_SHM_FORMAT_ARGB8888 },
        };
        const buf = wl.wl_proxy_marshal_array_flags(
            pool,
            0,
            wl.wl_buffer_interface,
            1,
            0,
            &buf_args,
        ) orelse {
            _ = wl.wl_proxy_marshal_array_flags(pool, 1, null, 1, WL_MARSHAL_FLAG_DESTROY, null);
            _ = linux_c.munmap(mapped.?, byte_len);
            _ = linux_c.close(fd);
            return false;
        };

        self.shm_fd = fd;
        self.shm_data = @ptrCast(@alignCast(mapped.?));
        self.shm_byte_len = byte_len;
        self.shm_pool = pool;
        self.shm_buffer = buf;
        self.shm_w = w;
        self.shm_h = h;
        return true;
    }

    /// Polls and dispatches any pending Wayland events without blocking the main render loop.
    pub fn pumpEvents(self: *WaylandState) void {
        const wl = self.wl;
        _ = wl.wl_display_dispatch_pending(self.display);
        _ = wl.wl_display_flush(self.display);

        if (wl.wl_display_prepare_read(self.display) == 0) {
            var pfd = [1]pollfd{.{
                .fd = wl.wl_display_get_fd(self.display),
                .events = POLLIN,
                .revents = 0,
            }};
            if (poll(&pfd, 1, 0) > 0 and (pfd[0].revents & POLLIN) != 0) {
                _ = wl.wl_display_read_events(self.display);
            } else {
                wl.wl_display_cancel_read(self.display);
            }
        }
        _ = wl.wl_display_dispatch_pending(self.display);
    }

    /// Presents the ARGB8888/BGRA8888 `pixel_storage` slice to the Wayland `wl_surface`.
    pub fn present(self: *WaylandState, pixels: []const u32, phys_w: i32, phys_h: i32) void {
        const surf = self.surface orelse return;
        if (!self.ensureShmBuffer(phys_w, phys_h)) return;
        const dst = self.shm_data orelse return;
        const count: usize = @intCast(phys_w * phys_h);
        const copy_n = @min(count, pixels.len);
        @memcpy(dst[0..copy_n], pixels[0..copy_n]);

        const wl = self.wl;
        // 1. `wl_surface.attach(buffer, 0, 0)` (opcode 1, signature "?oii")
        var attach_args = [_]wl_argument{
            .{ .o = self.shm_buffer },
            .{ .i = 0 },
            .{ .i = 0 },
        };
        _ = wl.wl_proxy_marshal_array_flags(surf, 1, null, 1, 0, &attach_args);

        // 2. `wl_surface.damage(0, 0, phys_w, phys_h)` (opcode 2, signature "iiii")
        var dmg_args = [_]wl_argument{
            .{ .i = 0 },
            .{ .i = 0 },
            .{ .i = phys_w },
            .{ .i = phys_h },
        };
        _ = wl.wl_proxy_marshal_array_flags(surf, 2, null, 1, 0, &dmg_args);

        // 3. `wl_surface.commit()` (opcode 6, signature "")
        _ = wl.wl_proxy_marshal_array_flags(surf, 6, null, 1, 0, null);
        _ = wl.wl_display_flush(self.display);
    }

    /// Executes window caption actions (Minimize = 10, Maximize/Restore = 11, Close = 12) on `xdg_toplevel`.
    pub fn executeWindowAction(self: *WaylandState, action: u32) void {
        const top = self.xdg_toplevel orelse return;
        const wl = self.wl;
        if (action == 10) {
            // `xdg_toplevel.set_minimized` (opcode 13)
            _ = wl.wl_proxy_marshal_array_flags(top, 13, null, 1, 0, null);
            if (self.surface) |s| _ = wl.wl_proxy_marshal_array_flags(s, 6, null, 1, 0, null);
            _ = wl.wl_display_flush(self.display);
        } else if (action == 11) {
            self.is_maximized.* = !self.is_maximized.*;
            // `xdg_toplevel.set_maximized` (opcode 9) / `unset_maximized` (opcode 10)
            const op: u32 = if (self.is_maximized.*) 9 else 10;
            _ = wl.wl_proxy_marshal_array_flags(top, op, null, 1, 0, null);
            if (self.surface) |s| _ = wl.wl_proxy_marshal_array_flags(s, 6, null, 1, 0, null);
            _ = wl.wl_display_flush(self.display);
        } else if (action == 12) {
            self.quit_requested.* = true;
        }
    }
};

// ============================================================================
// Wayland Protocol Listener Callbacks (`callconv(.c)`)
// ============================================================================
fn registryGlobal(
    data: ?*anyopaque,
    registry: *wl_proxy,
    name: u32,
    interface_z: [*:0]const u8,
    version: u32,
) callconv(.c) void {
    _ = version;
    const self: *WaylandState = @ptrCast(@alignCast(data orelse return));
    const wl = self.wl;
    const iface = std.mem.sliceTo(interface_z, 0);

    if (std.mem.eql(u8, iface, "wl_compositor")) {
        var args = [_]wl_argument{
            .{ .u = name },
            .{ .s = wl.wl_compositor_interface.name },
            .{ .u = 1 },
            .{ .n = 0 },
        };
        self.compositor = wl.wl_proxy_marshal_array_flags(registry, 0, wl.wl_compositor_interface, 1, 0, &args);
    } else if (std.mem.eql(u8, iface, "wl_shm")) {
        var args = [_]wl_argument{
            .{ .u = name },
            .{ .s = wl.wl_shm_interface.name },
            .{ .u = 1 },
            .{ .n = 0 },
        };
        self.shm = wl.wl_proxy_marshal_array_flags(registry, 0, wl.wl_shm_interface, 1, 0, &args);
    } else if (std.mem.eql(u8, iface, "xdg_wm_base")) {
        var args = [_]wl_argument{
            .{ .u = name },
            .{ .s = xdg_wm_base_interface.name },
            .{ .u = 1 },
            .{ .n = 0 },
        };
        if (wl.wl_proxy_marshal_array_flags(registry, 0, &xdg_wm_base_interface, 1, 0, &args)) |wm| {
            self.wm_base = wm;
            _ = wl.wl_proxy_add_listener(wm, &wm_base_listener, self);
        }
    } else if (std.mem.eql(u8, iface, "zxdg_decoration_manager_v1")) {
        var args = [_]wl_argument{
            .{ .u = name },
            .{ .s = zxdg_decoration_manager_v1_interface.name },
            .{ .u = 1 },
            .{ .n = 0 },
        };
        self.decoration_mgr = wl.wl_proxy_marshal_array_flags(registry, 0, &zxdg_decoration_manager_v1_interface, 1, 0, &args);
    } else if (std.mem.eql(u8, iface, "wl_seat") and self.seat == null) {
        var args = [_]wl_argument{
            .{ .u = name },
            .{ .s = wl.wl_seat_interface.name },
            .{ .u = 1 },
            .{ .n = 0 },
        };
        if (wl.wl_proxy_marshal_array_flags(registry, 0, wl.wl_seat_interface, 1, 0, &args)) |st| {
            self.seat = st;
            _ = wl.wl_proxy_add_listener(st, &seat_listener, self);
        }
    }
}

fn registryGlobalRemove(_: ?*anyopaque, _: *wl_proxy, _: u32) callconv(.c) void {}

const registry_listener = [_]?*const anyopaque{
    @ptrCast(&registryGlobal),
    @ptrCast(&registryGlobalRemove),
};

fn wmBasePing(data: ?*anyopaque, wm_base: *wl_proxy, serial: u32) callconv(.c) void {
    const self: *WaylandState = @ptrCast(@alignCast(data orelse return));
    var args = [_]wl_argument{.{ .u = serial }};
    _ = self.wl.wl_proxy_marshal_array_flags(wm_base, 3, null, 1, 0, &args);
}

const wm_base_listener = [_]?*const anyopaque{
    @ptrCast(&wmBasePing),
};

fn xdgSurfaceConfigure(data: ?*anyopaque, xdg_surface: *wl_proxy, serial: u32) callconv(.c) void {
    const self: *WaylandState = @ptrCast(@alignCast(data orelse return));
    var args = [_]wl_argument{.{ .u = serial }};
    _ = self.wl.wl_proxy_marshal_array_flags(xdg_surface, 4, null, 1, 0, &args);
    if (self.pending_w > 0 and self.pending_h > 0) {
        self.win_w.* = self.pending_w;
        self.win_h.* = self.pending_h;
    }
    self.configured = true;
    self.ctx.force_full_redraw = true;
    self.had_event.* = true;
}

const xdg_surface_listener = [_]?*const anyopaque{
    @ptrCast(&xdgSurfaceConfigure),
};

fn xdgToplevelConfigure(data: ?*anyopaque, _: *wl_proxy, width: i32, height: i32, _: ?*const wl_array) callconv(.c) void {
    const self: *WaylandState = @ptrCast(@alignCast(data orelse return));
    if (width > 0 and height > 0) {
        self.pending_w = width;
        self.pending_h = height;
    }
}

fn xdgToplevelClose(data: ?*anyopaque, _: *wl_proxy) callconv(.c) void {
    const self: *WaylandState = @ptrCast(@alignCast(data orelse return));
    self.quit_requested.* = true;
    self.had_event.* = true;
}

const xdg_toplevel_listener = [_]?*const anyopaque{
    @ptrCast(&xdgToplevelConfigure),
    @ptrCast(&xdgToplevelClose),
};

fn toplevelDecorationConfigure(_: ?*anyopaque, _: *wl_proxy, _: u32) callconv(.c) void {}

const toplevel_decoration_listener = [_]?*const anyopaque{
    @ptrCast(&toplevelDecorationConfigure),
};

fn seatCapabilities(data: ?*anyopaque, seat: *wl_proxy, caps: u32) callconv(.c) void {
    const self: *WaylandState = @ptrCast(@alignCast(data orelse return));
    const wl = self.wl;
    if ((caps & WL_SEAT_CAPABILITY_POINTER) != 0 and self.pointer == null) {
        var args = [_]wl_argument{.{ .n = 0 }};
        if (wl.wl_proxy_marshal_array_flags(seat, 0, wl.wl_pointer_interface, 1, 0, &args)) |ptr| {
            self.pointer = ptr;
            _ = wl.wl_proxy_add_listener(ptr, &pointer_listener, self);
        }
    }
    if ((caps & WL_SEAT_CAPABILITY_KEYBOARD) != 0 and self.keyboard == null) {
        var args = [_]wl_argument{.{ .n = 0 }};
        if (wl.wl_proxy_marshal_array_flags(seat, 1, wl.wl_keyboard_interface, 1, 0, &args)) |kbd| {
            self.keyboard = kbd;
            _ = wl.wl_proxy_add_listener(kbd, &keyboard_listener, self);
        }
    }
}

fn seatName(_: ?*anyopaque, _: *wl_proxy, _: [*:0]const u8) callconv(.c) void {}

const seat_listener = [_]?*const anyopaque{
    @ptrCast(&seatCapabilities),
    @ptrCast(&seatName),
};

fn pointerEnter(data: ?*anyopaque, _: *wl_proxy, serial: u32, _: ?*wl_proxy, sx: i32, sy: i32) callconv(.c) void {
    const self: *WaylandState = @ptrCast(@alignCast(data orelse return));
    self.last_pointer_serial = serial;
    self.ctx.mouse_x = wlFixedToF32(sx);
    self.ctx.mouse_y = wlFixedToF32(sy);
    self.had_event.* = true;
}

fn pointerLeave(data: ?*anyopaque, _: *wl_proxy, serial: u32, _: ?*wl_proxy) callconv(.c) void {
    const self: *WaylandState = @ptrCast(@alignCast(data orelse return));
    self.last_pointer_serial = serial;
    self.had_event.* = true;
}

fn pointerMotion(data: ?*anyopaque, _: *wl_proxy, _: u32, sx: i32, sy: i32) callconv(.c) void {
    const self: *WaylandState = @ptrCast(@alignCast(data orelse return));
    self.ctx.mouse_x = wlFixedToF32(sx);
    self.ctx.mouse_y = wlFixedToF32(sy);
    self.ctx.mouse_shift = self.mod_shift;
    self.had_event.* = true;
}

fn pointerButton(data: ?*anyopaque, _: *wl_proxy, serial: u32, _: u32, button: u32, state: u32) callconv(.c) void {
    const self: *WaylandState = @ptrCast(@alignCast(data orelse return));
    self.last_pointer_serial = serial;
    self.ctx.mouse_shift = self.mod_shift;
    self.had_event.* = true;

    if (button == BTN_LEFT) {
        if (state == 1) {
            const win_w_f: f32 = @floatFromInt(self.win_w.*);
            const pill_left = (win_w_f - 300.0) * 0.5;
            const pill_right = (win_w_f + 300.0) * 0.5;
            if (self.ctx.mouse_y >= 0.0 and self.ctx.mouse_y < 36.0 and
                self.ctx.mouse_x >= 144.0 and (self.ctx.mouse_x < pill_left or self.ctx.mouse_x > pill_right) and
                self.ctx.mouse_x < win_w_f - 138.0)
            {
                if (self.xdg_toplevel) |top| {
                    if (self.seat) |seat| {
                        // `xdg_toplevel.move(seat, serial)` (opcode 5, signature "ou")
                        var move_args = [_]wl_argument{
                            .{ .o = seat },
                            .{ .u = serial },
                        };
                        _ = self.wl.wl_proxy_marshal_array_flags(top, 5, null, 1, 0, &move_args);
                        _ = self.wl.wl_display_flush(self.display);
                        return;
                    }
                }
            }
            self.ctx.mouse_click_count = 1;
            self.saw_left_down.* = true;
            self.mouse_down.* = true;
        } else {
            self.saw_left_up.* = true;
            self.mouse_down.* = false;
        }
    } else if (button == BTN_RIGHT) {
        if (state == 1) {
            self.saw_right_down.* = true;
            self.right_mouse_down.* = true;
        } else {
            self.saw_right_up.* = true;
            self.right_mouse_down.* = false;
        }
    }
}

fn pointerAxis(data: ?*anyopaque, _: *wl_proxy, _: u32, axis: u32, value: i32) callconv(.c) void {
    const self: *WaylandState = @ptrCast(@alignCast(data orelse return));
    const delta = wlFixedToF32(value) * 2.4;
    if (axis == 0) {
        self.ctx.scroll_dy -= delta;
    } else if (axis == 1) {
        self.ctx.scroll_dx -= delta;
    }
    self.had_event.* = true;
}

const pointer_listener = [_]?*const anyopaque{
    @ptrCast(&pointerEnter),
    @ptrCast(&pointerLeave),
    @ptrCast(&pointerMotion),
    @ptrCast(&pointerButton),
    @ptrCast(&pointerAxis),
};

fn keyboardKeymap(data: ?*anyopaque, _: *wl_proxy, format: u32, fd: i32, size: u32) callconv(.c) void {
    defer if (fd >= 0) {
        _ = linux_c.close(fd);
    };
    const self: *WaylandState = @ptrCast(@alignCast(data orelse return));
    if (format != 1 or size == 0) return;
    const xkb = self.xkb orelse return;
    const xkb_ctx = self.xkb_ctx orelse return;

    const map_ptr = linux_c.mmap(null, size, linux_c.PROT_READ, linux_c.MAP_PRIVATE, fd, 0);
    if (map_ptr == null or @intFromPtr(map_ptr.?) == std.math.maxInt(usize)) return;
    defer _ = linux_c.munmap(map_ptr.?, size);

    if (self.xkb_st) |st| {
        xkb.xkb_state_unref(st);
        self.xkb_st = null;
    }
    if (self.xkb_map) |mp| {
        xkb.xkb_keymap_unref(mp);
        self.xkb_map = null;
    }

    if (xkb.xkb_keymap_new_from_string(xkb_ctx, @ptrCast(map_ptr.?), 1, 0)) |mp| {
        self.xkb_map = mp;
        self.xkb_st = xkb.xkb_state_new(mp);
    }
}

fn keyboardEnter(data: ?*anyopaque, _: *wl_proxy, _: u32, _: ?*wl_proxy, _: ?*const wl_array) callconv(.c) void {
    const self: *WaylandState = @ptrCast(@alignCast(data orelse return));
    self.had_event.* = true;
}

fn keyboardLeave(data: ?*anyopaque, _: *wl_proxy, _: u32, _: ?*wl_proxy) callconv(.c) void {
    const self: *WaylandState = @ptrCast(@alignCast(data orelse return));
    self.mod_shift = false;
    self.mod_ctrl = false;
    self.mod_alt = false;
    self.mod_super = false;
    self.had_event.* = true;
}

fn translateEvdevKeycode(evdev_key: u32) app_api.KeyCode {
    return switch (evdev_key) {
        1 => .escape,
        2 => .key_1,
        3 => .key_2,
        7 => .key_6,
        12 => .key_minus,
        14 => .backspace,
        15 => .tab,
        16 => .key_q,
        17 => .key_w,
        18 => .key_e,
        19 => .key_r,
        20 => .key_t,
        21 => .key_y,
        22 => .key_u,
        23 => .key_i,
        24 => .key_o,
        25 => .key_p,
        26 => .key_lbracket,
        27 => .key_rbracket,
        28, 96 => .enter,
        30 => .key_a,
        31 => .key_s,
        32 => .key_d,
        33 => .key_f,
        34 => .key_g,
        35 => .key_h,
        36 => .key_j,
        37 => .key_k,
        38 => .key_l,
        43 => .key_backslash,
        44 => .key_z,
        45 => .key_x,
        46 => .key_c,
        47 => .key_v,
        48 => .key_b,
        49 => .key_n,
        50 => .key_m,
        53 => .key_slash,
        57 => .key_space,
        63 => .f5,
        67 => .f9,
        68 => .f10,
        87 => .f11,
        102 => .home,
        103 => .up,
        104 => .page_up,
        105 => .left,
        106 => .right,
        107 => .end,
        108 => .down,
        109 => .page_down,
        111 => .delete_forward,
        else => .none,
    };
}

fn keyboardKey(data: ?*anyopaque, _: *wl_proxy, _: u32, _: u32, key: u32, state: u32) callconv(.c) void {
    const self: *WaylandState = @ptrCast(@alignCast(data orelse return));
    self.had_event.* = true;

    const pressed = (state == 1);
    if (key == 42 or key == 54) self.mod_shift = pressed;
    if (key == 29 or key == 97) self.mod_ctrl = pressed;
    if (key == 56 or key == 100) self.mod_alt = pressed;
    if (key == 125 or key == 126) self.mod_super = pressed;

    if (!pressed) return;

    var kc: app_api.KeyCode = .none;
    var utf8_buf: [32]u8 = undefined;
    var utf8_len: usize = 0;

    if (self.xkb) |xkb| {
        if (self.xkb_st) |xkb_st| {
            const xkb_keycode: u32 = key + 8;
            const sym = xkb.xkb_state_key_get_one_sym(xkb_st, xkb_keycode);
            kc = self.translateKeySymFn(@intCast(sym));
            const n = xkb.xkb_state_key_get_utf8(xkb_st, xkb_keycode, &utf8_buf, utf8_buf.len);
            if (n > 0) utf8_len = @intCast(@min(n, @as(c_int, @intCast(utf8_buf.len))));
        }
    }
    if (kc == .none) {
        kc = translateEvdevKeycode(key);
    }

    if (kc != .none) {
        self.ctx.pushKeyEvent(.{
            .key = kc,
            .shift = self.mod_shift,
            .ctrl = self.mod_ctrl,
            .alt = self.mod_alt,
            .cmd = self.mod_ctrl or self.mod_super,
        });
    }

    if (!self.mod_ctrl and !self.mod_alt and !self.mod_super and utf8_len > 0) {
        var clean_buf: [32]u8 = undefined;
        var clean_len: usize = 0;
        for (utf8_buf[0..utf8_len]) |ch| {
            if (ch >= 0x20 and ch != 0x7f) {
                clean_buf[clean_len] = ch;
                clean_len += 1;
            }
        }
        if (clean_len > 0) {
            self.ctx.pushTextInput(clean_buf[0..clean_len]);
        }
    }
}

fn keyboardModifiers(
    data: ?*anyopaque,
    _: *wl_proxy,
    _: u32,
    mods_depressed: u32,
    mods_latched: u32,
    mods_locked: u32,
    group: u32,
) callconv(.c) void {
    const self: *WaylandState = @ptrCast(@alignCast(data orelse return));
    if (self.xkb) |xkb| {
        if (self.xkb_st) |xkb_st| {
            _ = xkb.xkb_state_update_mask(xkb_st, mods_depressed, mods_latched, mods_locked, 0, 0, group);
        }
    }
    self.mod_shift = (mods_depressed & (1 << 0)) != 0;
    self.mod_ctrl = (mods_depressed & (1 << 2)) != 0;
    self.mod_alt = (mods_depressed & (1 << 3)) != 0;
    self.mod_super = (mods_depressed & (1 << 6)) != 0;
    self.had_event.* = true;
}

fn keyboardRepeatInfo(_: ?*anyopaque, _: *wl_proxy, _: i32, _: i32) callconv(.c) void {}

const keyboard_listener = [_]?*const anyopaque{
    @ptrCast(&keyboardKeymap),
    @ptrCast(&keyboardEnter),
    @ptrCast(&keyboardLeave),
    @ptrCast(&keyboardKey),
    @ptrCast(&keyboardModifiers),
    @ptrCast(&keyboardRepeatInfo),
};

test "wayland_client: wlFixedToF32 and evdev keycode translation" {
    try std.testing.expectApproxEqAbs(@as(f32, 128.5), wlFixedToF32(128 * 256 + 128), 0.001);
    try std.testing.expectEqual(app_api.KeyCode.escape, translateEvdevKeycode(1));
    try std.testing.expectEqual(app_api.KeyCode.enter, translateEvdevKeycode(28));
    try std.testing.expectEqual(app_api.KeyCode.key_p, translateEvdevKeycode(25));
    try std.testing.expectEqual(app_api.KeyCode.left, translateEvdevKeycode(105));
    try std.testing.expectEqual(app_api.KeyCode.right, translateEvdevKeycode(106));
}
