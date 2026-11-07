//! Native Linux Wayland / X11 / Headless Skia Window Host (`src/platform/linux/linux_window.zig`).
//!
//! Dynamically resolves `libwayland-client.so.0` + `libxkbcommon.so.0` (Wayland) or `libX11.so.6` (X11)
//! at runtime via `dlopen`/`dlsym` (zero `@cImport` and zero compile-time sysroot dependencies when
//! cross-compiling from macOS or Windows) and falls back seamlessly to a headless Skia raster loop
//! when neither `WAYLAND_DISPLAY` nor `DISPLAY` is active (e.g., CI, `--bench`, or `--screenshot`).

const std = @import("std");
const skia = @import("skia");
const app_api = @import("../app_api.zig");
const state_store = @import("../state_store.zig");
const hot_dylib = @import("../hot_dylib.zig");
const profiler = @import("../profiler.zig");
const fs_util = @import("../fs_util.zig");
const objc = @import("../macos/objc.zig");
pub const wayland_client = @import("wayland_client.zig");

const HotDylib = hot_dylib.HotDylib;

pub const Config = struct {
    title: [*:0]const u8 = "Zig + Skia Window",
    width: f64 = 960.0,
    height: f64 = 640.0,
    dylib_path: [*:0]const u8 = "zig-out/lib/libeditor_app.so",
    max_frames: ?usize = null,
    bench: bool = false,
    metrics_json_path: ?[]const u8 = null,
    trace_path: ?[]const u8 = null,
    scenario: ?[]const u8 = null,
    screenshot_path: ?[]const u8 = null,
};

// ============================================================================
// Dynamic X11 C-ABI Bindings (`libX11.so.6` loaded at runtime via `dlopen`)
// ============================================================================
const Display = opaque {};
const Visual = opaque {};
const GC = opaque {};
const XID = c_ulong;
const Window = XID;
const Atom = c_ulong;
const KeySym = c_ulong;

const XImage = extern struct {
    width: c_int,
    height: c_int,
    xoffset: c_int,
    format: c_int,
    data: ?[*]u8,
    byte_order: c_int,
    bitmap_unit: c_int,
    bitmap_bit_order: c_int,
    bitmap_pad: c_int,
    depth: c_int,
    bytes_per_line: c_int,
    bits_per_pixel: c_int,
    red_mask: c_ulong,
    green_mask: c_ulong,
    blue_mask: c_ulong,
    obdata: ?*anyopaque,
    funcs: [8]?*anyopaque,
};

const XKeyEvent = extern struct {
    type: c_int,
    serial: c_ulong,
    send_event: c_int,
    display: ?*Display,
    window: Window,
    root: Window,
    subwindow: Window,
    time: c_ulong,
    x: c_int,
    y: c_int,
    x_root: c_int,
    y_root: c_int,
    state: c_uint,
    keycode: c_uint,
    same_screen: c_int,
};

const XButtonEvent = extern struct {
    type: c_int,
    serial: c_ulong,
    send_event: c_int,
    display: ?*Display,
    window: Window,
    root: Window,
    subwindow: Window,
    time: c_ulong,
    x: c_int,
    y: c_int,
    x_root: c_int,
    y_root: c_int,
    state: c_uint,
    button: c_uint,
    same_screen: c_int,
};

const XMotionEvent = extern struct {
    type: c_int,
    serial: c_ulong,
    send_event: c_int,
    display: ?*Display,
    window: Window,
    root: Window,
    subwindow: Window,
    time: c_ulong,
    x: c_int,
    y: c_int,
    x_root: c_int,
    y_root: c_int,
    state: c_uint,
    is_hint: u8,
    same_screen: c_int,
};

const XConfigureEvent = extern struct {
    type: c_int,
    serial: c_ulong,
    send_event: c_int,
    display: ?*Display,
    event: Window,
    window: Window,
    x: c_int,
    y: c_int,
    width: c_int,
    height: c_int,
    border_width: c_int,
    above: Window,
    override_redirect: c_int,
};

const XClientMessageEvent = extern struct {
    type: c_int,
    serial: c_ulong,
    send_event: c_int,
    display: ?*Display,
    window: Window,
    message_type: Atom,
    format: c_int,
    data_l: [5]c_long,
};

const XEvent = extern union {
    type: c_int,
    xkey: XKeyEvent,
    xbutton: XButtonEvent,
    xmotion: XMotionEvent,
    xconfigure: XConfigureEvent,
    xclient: XClientMessageEvent,
    pad: [24]c_long,
};

const MotifWmHints = extern struct {
    flags: c_ulong = 2, // MWM_HINTS_DECORATIONS
    functions: c_ulong = 0,
    decorations: c_ulong = 0, // Borderless custom titlebar
    input_mode: c_long = 0,
    status: c_ulong = 0,
};

const KeyPress: c_int = 2;
const KeyRelease: c_int = 3;
const ButtonPress: c_int = 4;
const ButtonRelease: c_int = 5;
const MotionNotify: c_int = 6;
const Expose: c_int = 12;
const ConfigureNotify: c_int = 22;
const ClientMessage: c_int = 33;

const KeyPressMask: c_long = 1 << 0;
const KeyReleaseMask: c_long = 1 << 1;
const ButtonPressMask: c_long = 1 << 2;
const ButtonReleaseMask: c_long = 1 << 3;
const PointerMotionMask: c_long = 1 << 6;
const ExposureMask: c_long = 1 << 15;
const StructureNotifyMask: c_long = 1 << 17;

const ShiftMask: c_uint = 1 << 0;
const ControlMask: c_uint = 1 << 2;
const Mod1Mask: c_uint = 1 << 3; // Alt
const Mod4Mask: c_uint = 1 << 6; // Super
const ZPixmap: c_int = 2;
const PropModeReplace: c_int = 0;
const SubstructureRedirectMask: c_long = 1 << 20;
const SubstructureNotifyMask: c_long = 1 << 19;

const X11Api = struct {
    handle: *anyopaque,
    XOpenDisplay: *const fn (?[*:0]const u8) callconv(.c) ?*Display,
    XCloseDisplay: *const fn (*Display) callconv(.c) c_int,
    XDefaultScreen: *const fn (*Display) callconv(.c) c_int,
    XRootWindow: *const fn (*Display, c_int) callconv(.c) Window,
    XCreateSimpleWindow: *const fn (*Display, Window, c_int, c_int, c_uint, c_uint, c_uint, c_ulong, c_ulong) callconv(.c) Window,
    XSelectInput: *const fn (*Display, Window, c_long) callconv(.c) c_int,
    XMapWindow: *const fn (*Display, Window) callconv(.c) c_int,
    XStoreName: *const fn (*Display, Window, [*:0]const u8) callconv(.c) c_int,
    XInternAtom: *const fn (*Display, [*:0]const u8, c_int) callconv(.c) Atom,
    XSetWMProtocols: *const fn (*Display, Window, *Atom, c_int) callconv(.c) c_int,
    XChangeProperty: *const fn (*Display, Window, Atom, Atom, c_int, c_int, *const anyopaque, c_int) callconv(.c) c_int,
    XPending: *const fn (*Display) callconv(.c) c_int,
    XNextEvent: *const fn (*Display, *XEvent) callconv(.c) c_int,
    XLookupString: *const fn (*XKeyEvent, [*]u8, c_int, ?*KeySym, ?*anyopaque) callconv(.c) c_int,
    XLookupKeysym: *const fn (*XKeyEvent, c_int) callconv(.c) KeySym,
    XDefaultGC: *const fn (*Display, c_int) callconv(.c) *GC,
    XDefaultVisual: *const fn (*Display, c_int) callconv(.c) *Visual,
    XDefaultDepth: *const fn (*Display, c_int) callconv(.c) c_int,
    XCreateImage: *const fn (*Display, *Visual, c_uint, c_int, c_int, ?[*]u8, c_uint, c_uint, c_int, c_int) callconv(.c) ?*XImage,
    XPutImage: *const fn (*Display, Window, *GC, *XImage, c_int, c_int, c_int, c_int, c_uint, c_uint) callconv(.c) c_int,
    XFlush: *const fn (*Display) callconv(.c) c_int,
    XDestroyWindow: *const fn (*Display, Window) callconv(.c) c_int,
    XIconifyWindow: *const fn (*Display, Window, c_int) callconv(.c) c_int,
    XSendEvent: *const fn (*Display, Window, c_int, c_long, *XEvent) callconv(.c) c_int,

    fn load() ?X11Api {
        const h = objc.dlopen("libX11.so.6", objc.RTLD_NOW) orelse
            objc.dlopen("libX11.so", objc.RTLD_NOW) orelse return null;
        return .{
            .handle = h,
            .XOpenDisplay = @ptrCast(@alignCast(objc.dlsym(h, "XOpenDisplay") orelse return null)),
            .XCloseDisplay = @ptrCast(@alignCast(objc.dlsym(h, "XCloseDisplay") orelse return null)),
            .XDefaultScreen = @ptrCast(@alignCast(objc.dlsym(h, "XDefaultScreen") orelse return null)),
            .XRootWindow = @ptrCast(@alignCast(objc.dlsym(h, "XRootWindow") orelse return null)),
            .XCreateSimpleWindow = @ptrCast(@alignCast(objc.dlsym(h, "XCreateSimpleWindow") orelse return null)),
            .XSelectInput = @ptrCast(@alignCast(objc.dlsym(h, "XSelectInput") orelse return null)),
            .XMapWindow = @ptrCast(@alignCast(objc.dlsym(h, "XMapWindow") orelse return null)),
            .XStoreName = @ptrCast(@alignCast(objc.dlsym(h, "XStoreName") orelse return null)),
            .XInternAtom = @ptrCast(@alignCast(objc.dlsym(h, "XInternAtom") orelse return null)),
            .XSetWMProtocols = @ptrCast(@alignCast(objc.dlsym(h, "XSetWMProtocols") orelse return null)),
            .XChangeProperty = @ptrCast(@alignCast(objc.dlsym(h, "XChangeProperty") orelse return null)),
            .XPending = @ptrCast(@alignCast(objc.dlsym(h, "XPending") orelse return null)),
            .XNextEvent = @ptrCast(@alignCast(objc.dlsym(h, "XNextEvent") orelse return null)),
            .XLookupString = @ptrCast(@alignCast(objc.dlsym(h, "XLookupString") orelse return null)),
            .XLookupKeysym = @ptrCast(@alignCast(objc.dlsym(h, "XLookupKeysym") orelse return null)),
            .XDefaultGC = @ptrCast(@alignCast(objc.dlsym(h, "XDefaultGC") orelse return null)),
            .XDefaultVisual = @ptrCast(@alignCast(objc.dlsym(h, "XDefaultVisual") orelse return null)),
            .XDefaultDepth = @ptrCast(@alignCast(objc.dlsym(h, "XDefaultDepth") orelse return null)),
            .XCreateImage = @ptrCast(@alignCast(objc.dlsym(h, "XCreateImage") orelse return null)),
            .XPutImage = @ptrCast(@alignCast(objc.dlsym(h, "XPutImage") orelse return null)),
            .XFlush = @ptrCast(@alignCast(objc.dlsym(h, "XFlush") orelse return null)),
            .XDestroyWindow = @ptrCast(@alignCast(objc.dlsym(h, "XDestroyWindow") orelse return null)),
            .XIconifyWindow = @ptrCast(@alignCast(objc.dlsym(h, "XIconifyWindow") orelse return null)),
            .XSendEvent = @ptrCast(@alignCast(objc.dlsym(h, "XSendEvent") orelse return null)),
        };
    }
};

// ============================================================================
// Runtime Host State & Native Linux Callbacks
// ============================================================================
const LinuxEventState = struct {
    ctx: *app_api.PlatformContext,
    wayland: ?*wayland_client.WaylandState = null,
    x11: ?X11Api = null,
    display: ?*Display = null,
    screen: c_int = 0,
    root_win: Window = 0,
    window: Window = 0,
    wm_delete_window: Atom = 0,
    net_wm_state: Atom = 0,
    net_wm_state_max_horz: Atom = 0,
    net_wm_state_max_vert: Atom = 0,
    net_wm_moveresize: Atom = 0,
    quit_requested: bool = false,
    is_maximized: bool = false,
    had_event: bool = false,
    mouse_down: bool = false,
    right_mouse_down: bool = false,
    saw_left_down: bool = false,
    saw_left_up: bool = false,
    saw_right_down: bool = false,
    saw_right_up: bool = false,
    pending_window_action: u32 = 0,
    win_w: i32 = 1080,
    win_h: i32 = 700,
};

var g_linux_state: ?*LinuxEventState = null;
var g_clipboard_buf: [65536]u8 = @splat(0);
var g_dialog_path_buf: [4096]u8 = @splat(0);

fn linuxGetClipboardImpl(buf_ptr: ?[*]u8, buf_cap: usize) callconv(.c) usize {
    const cmds = [_][*:0]const u8{
        "wl-paste --no-newline 2>/dev/null",
        "xclip -selection clipboard -o 2>/dev/null",
        "xsel --clipboard --output 2>/dev/null",
    };
    for (cmds) |cmd| {
        if (fs_util.popen(cmd, "r")) |fp| {
            const n = std.c.fread(&g_clipboard_buf, 1, g_clipboard_buf.len - 1, fp);
            const rc = fs_util.pclose(fp);
            if (rc == 0 and n > 0) {
                if (buf_ptr) |bp| {
                    if (buf_cap > 0) {
                        const copy_n = @min(n, buf_cap);
                        @memcpy(bp[0..copy_n], g_clipboard_buf[0..copy_n]);
                    }
                }
                return n;
            }
        }
    }
    return 0;
}

fn linuxSetClipboardImpl(ptr: [*]const u8, len: usize) callconv(.c) void {
    const cmds = [_][*:0]const u8{
        "wl-copy 2>/dev/null",
        "xclip -selection clipboard -i 2>/dev/null",
        "xsel --clipboard --input 2>/dev/null",
    };
    for (cmds) |cmd| {
        if (fs_util.popen(cmd, "w")) |fp| {
            _ = std.c.fwrite(ptr, 1, len, fp);
            if (fs_util.pclose(fp) == 0) return;
        }
    }
}

fn hasLinuxGuiDialogTool() bool {
    if (fs_util.getenv("DISPLAY") == null and fs_util.getenv("WAYLAND_DISPLAY") == null) return false;
    const candidates = [_][*:0]const u8{
        "/usr/bin/zenity",
        "/usr/local/bin/zenity",
        "/bin/zenity",
        "/usr/bin/kdialog",
        "/usr/local/bin/kdialog",
        "/bin/kdialog",
    };
    for (candidates) |path_z| {
        if (fs_util.regularFileSizeOnDisk(path_z) != null) return true;
    }
    return false;
}

fn runZenityDialogIntoBuf(cmd: [*:0]const u8, buf_ptr: [*]u8, buf_cap: usize) usize {
    if (buf_cap == 0) return 0;
    const fp = fs_util.popen(cmd, "r") orelse return 0;
    const n = std.c.fread(&g_dialog_path_buf, 1, g_dialog_path_buf.len - 1, fp);
    _ = fs_util.pclose(fp);
    var len = n;
    while (len > 0 and (g_dialog_path_buf[len - 1] == '\n' or g_dialog_path_buf[len - 1] == '\r')) {
        len -= 1;
    }
    if (len == 0) return 0;
    const copy_n = @min(len, buf_cap);
    @memcpy(buf_ptr[0..copy_n], g_dialog_path_buf[0..copy_n]);
    return copy_n;
}

fn linuxPickFolderImpl(buf_ptr: [*]u8, buf_cap: usize) callconv(.c) usize {
    return runZenityDialogIntoBuf(
        "zenity --file-selection --directory --title='Open Workspace Folder' 2>/dev/null || kdialog --getexistingdirectory . 2>/dev/null",
        buf_ptr,
        buf_cap,
    );
}

fn linuxPickFileImpl(buf_ptr: [*]u8, buf_cap: usize) callconv(.c) usize {
    return runZenityDialogIntoBuf(
        "zenity --file-selection --title='Open File' 2>/dev/null || kdialog --getopenfilename . 2>/dev/null",
        buf_ptr,
        buf_cap,
    );
}

fn linuxSaveFileImpl(buf_ptr: [*]u8, buf_cap: usize) callconv(.c) usize {
    return runZenityDialogIntoBuf(
        "zenity --file-selection --save --confirm-overwrite --title='Save File As' 2>/dev/null || kdialog --getsavefilename . 2>/dev/null",
        buf_ptr,
        buf_cap,
    );
}

fn linuxWindowActionImpl(action: u32, x: f32, y: f32) callconv(.c) void {
    _ = x;
    _ = y;
    const st = g_linux_state orelse return;
    st.pending_window_action = action;
}

fn executePendingLinuxWindowAction(st: *LinuxEventState) void {
    const action = st.pending_window_action;
    if (action == 0) return;
    st.pending_window_action = 0;

    if (action == 1) {
        st.ctx.pushKeyEvent(.{ .key = .key_o, .ctrl = true, .cmd = true });
        st.had_event = true;
        return;
    } else if (action == 2 or action == 3) {
        st.ctx.pushKeyEvent(.{ .key = .key_p, .shift = true, .ctrl = true, .cmd = true });
        st.had_event = true;
        return;
    }

    if (st.wayland) |wl_state| {
        wl_state.executeWindowAction(action);
        return;
    }

    const x11 = st.x11 orelse return;
    const dpy = st.display orelse return;
    if (action == 10) {
        _ = x11.XIconifyWindow(dpy, st.window, st.screen);
    } else if (action == 11) {
        st.is_maximized = !st.is_maximized;
        var ev: XEvent = .{ .xclient = .{
            .type = ClientMessage,
            .serial = 0,
            .send_event = 1,
            .display = dpy,
            .window = st.window,
            .message_type = st.net_wm_state,
            .format = 32,
            .data_l = .{
                2, // _NET_WM_STATE_TOGGLE
                @intCast(st.net_wm_state_max_horz),
                @intCast(st.net_wm_state_max_vert),
                1,
                0,
            },
        } };
        _ = x11.XSendEvent(dpy, st.root_win, 0, SubstructureRedirectMask | SubstructureNotifyMask, &ev);
        _ = x11.XFlush(dpy);
    } else if (action == 12) {
        st.quit_requested = true;
    }
}

fn translateKeySym(ks: KeySym) app_api.KeyCode {
    return switch (ks) {
        0xff08 => .backspace,
        0xff09, 0xfe20 => .tab,
        0xff0d, 0xff8d => .enter,
        0xff1b => .escape,
        0xffff => .delete_forward,
        0xff51 => .left,
        0xff52 => .up,
        0xff53 => .right,
        0xff54 => .down,
        0xff50 => .home,
        0xff57 => .end,
        0xff55 => .page_up,
        0xff56 => .page_down,
        0xffbe => .f5,
        0xffc2 => .f5,
        0xffc6 => .f9,
        0xffc7 => .f10,
        0xffc8 => .f11,
        'a', 'A' => .key_a,
        'b', 'B' => .key_b,
        'c', 'C' => .key_c,
        'd', 'D' => .key_d,
        'e', 'E' => .key_e,
        'f', 'F' => .key_f,
        'g', 'G' => .key_g,
        'h', 'H' => .key_h,
        'i', 'I' => .key_i,
        'j', 'J' => .key_j,
        'k', 'K' => .key_k,
        'l', 'L' => .key_l,
        'm', 'M' => .key_m,
        'n', 'N' => .key_n,
        'o', 'O' => .key_o,
        'p', 'P' => .key_p,
        'q', 'Q' => .key_q,
        'r', 'R' => .key_r,
        's', 'S' => .key_s,
        't', 'T' => .key_t,
        'u', 'U' => .key_u,
        'v', 'V' => .key_v,
        'w', 'W' => .key_w,
        'x', 'X' => .key_x,
        'y', 'Y' => .key_y,
        'z', 'Z' => .key_z,
        '1', '!' => .key_1,
        '2', '@' => .key_2,
        '6', '^' => .key_6,
        ' ' => .key_space,
        '\\', '|' => .key_backslash,
        '/', '?' => .key_slash,
        '[', '{' => .key_lbracket,
        ']', '}' => .key_rbracket,
        '-', '_' => .key_minus,
        else => .none,
    };
}

pub fn run(config: Config) !void {
    const font_mgr = try skia.FontMgr.initDefault();
    defer font_mgr.deinit();

    const debug_paint = try skia.Paint.init();
    defer debug_paint.deinit();
    debug_paint.setAntiAlias(true);
    debug_paint.setStyle(.stroke);
    debug_paint.setStrokeWidth(1.5);
    debug_paint.setColor(skia.Color.argb(220, 16, 185, 129));

    var host_store = state_store.StateStore.init(std.heap.c_allocator);
    defer host_store.deinit();

    var host_snapshot = state_store.SnapshotBuffer.init(std.heap.c_allocator);
    defer host_snapshot.deinit();

    const use_native_dialogs = (config.screenshot_path == null) and hasLinuxGuiDialogTool();
    var ctx = app_api.PlatformContext{
        .gr_context = null,
        .font_mgr = font_mgr.ptr,
        .host_get_clipboard = &linuxGetClipboardImpl,
        .host_set_clipboard = &linuxSetClipboardImpl,
        .host_pick_folder = if (use_native_dialogs) &linuxPickFolderImpl else null,
        .host_pick_file = if (use_native_dialogs) &linuxPickFileImpl else null,
        .host_save_file = if (use_native_dialogs) &linuxSaveFileImpl else null,
        .host_window_action = &linuxWindowActionImpl,
    };
    ctx.bindHostStores(&host_store, &host_snapshot);

    var hot_lib = HotDylib{
        .watch_path = config.dylib_path,
    };
    defer hot_lib.unload(&ctx);

    if (!hot_lib.checkAndReload(&ctx)) {
        std.debug.print("Failed to load {s}\n", .{hot_lib.watch_path});
        return error.DylibLoadFailed;
    }

    var trace_collector = profiler.TraceCollector.init(std.heap.c_allocator, config.trace_path != null);
    defer {
        if (config.trace_path) |tp| {
            trace_collector.writeJsonFile(tp) catch {};
        }
        trace_collector.deinit();
    }

    var metrics_collector = profiler.FrameMetricsCollector.init(std.heap.c_allocator);
    defer {
        if (config.bench) {
            metrics_collector.printSummary();
        }
        if (config.metrics_json_path) |mp| {
            metrics_collector.writeJsonFile(mp) catch {};
        }
        metrics_collector.deinit();
    }

    var debug_server = profiler.LiveDebugServer.init(std.heap.c_allocator);
    defer debug_server.deinit();

    const scenario = if (config.scenario) |s| profiler.ScenarioKind.fromString(s) else .none;
    const effective_max_frames: ?usize = config.max_frames orelse if (config.bench) 300 else null;

    var event_state = LinuxEventState{
        .ctx = &ctx,
        .win_w = @max(1, @as(i32, @intFromFloat(config.width))),
        .win_h = @max(1, @as(i32, @intFromFloat(config.height))),
    };
    g_linux_state = &event_state;
    defer g_linux_state = null;

    const backend_env: []const u8 = if (fs_util.getenv("LIGHTNING_BACKEND")) |b_z|
        std.mem.sliceTo(b_z, 0)
    else
        "";
    const force_wayland = std.mem.eql(u8, backend_env, "wayland");
    const force_x11 = std.mem.eql(u8, backend_env, "x11");
    const force_headless = std.mem.eql(u8, backend_env, "headless");

    // 1. Prefer native Wayland (`libwayland-client.so.0`) when `WAYLAND_DISPLAY` is set (or `LIGHTNING_BACKEND=wayland`)
    if (!force_headless and !force_x11) {
        event_state.wayland = wayland_client.WaylandState.init(
            &ctx,
            config.title,
            &event_state.win_w,
            &event_state.win_h,
            &event_state.quit_requested,
            &event_state.is_maximized,
            &event_state.had_event,
            &event_state.mouse_down,
            &event_state.right_mouse_down,
            &event_state.saw_left_down,
            &event_state.saw_left_up,
            &event_state.saw_right_down,
            &event_state.saw_right_up,
            &translateKeySym,
            force_wayland,
        );
    }

    // 2. Fall back to X11 (`libX11.so.6`) when Wayland is not active and `DISPLAY` is set
    if (!force_headless and event_state.wayland == null and fs_util.getenv("DISPLAY") != null) {
        if (X11Api.load()) |x11| {
            if (x11.XOpenDisplay(null)) |dpy| {
                const scr = x11.XDefaultScreen(dpy);
                const root = x11.XRootWindow(dpy, scr);
                const win = x11.XCreateSimpleWindow(
                    dpy,
                    root,
                    80,
                    60,
                    @intCast(event_state.win_w),
                    @intCast(event_state.win_h),
                    0,
                    0,
                    0x0b0f19,
                );
                _ = x11.XStoreName(dpy, win, config.title);
                _ = x11.XSelectInput(
                    dpy,
                    win,
                    KeyPressMask | KeyReleaseMask | ButtonPressMask | ButtonReleaseMask |
                        PointerMotionMask | ExposureMask | StructureNotifyMask,
                );

                // Remove default window manager frame decorations (`_MOTIF_WM_HINTS`)
                const motif_atom = x11.XInternAtom(dpy, "_MOTIF_WM_HINTS", 0);
                if (motif_atom != 0) {
                    const hints = MotifWmHints{};
                    _ = x11.XChangeProperty(dpy, win, motif_atom, motif_atom, 32, PropModeReplace, &hints, 5);
                }

                var wm_del = x11.XInternAtom(dpy, "WM_DELETE_WINDOW", 0);
                _ = x11.XSetWMProtocols(dpy, win, &wm_del, 1);

                event_state.x11 = x11;
                event_state.display = dpy;
                event_state.screen = scr;
                event_state.root_win = root;
                event_state.window = win;
                event_state.wm_delete_window = wm_del;
                event_state.net_wm_state = x11.XInternAtom(dpy, "_NET_WM_STATE", 0);
                event_state.net_wm_state_max_horz = x11.XInternAtom(dpy, "_NET_WM_STATE_MAXIMIZED_HORZ", 0);
                event_state.net_wm_state_max_vert = x11.XInternAtom(dpy, "_NET_WM_STATE_MAXIMIZED_VERT", 0);
                event_state.net_wm_moveresize = x11.XInternAtom(dpy, "_NET_WM_MOVERESIZE", 0);

                _ = x11.XMapWindow(dpy, win);
                _ = x11.XFlush(dpy);
            }
        }
    }
    defer {
        if (event_state.wayland) |wl_state| {
            wl_state.deinit();
        }
        if (event_state.x11) |x11| {
            if (event_state.display) |dpy| {
                if (event_state.window != 0) _ = x11.XDestroyWindow(dpy, event_state.window);
                _ = x11.XCloseDisplay(dpy);
            }
        }
    }

    var redraw_frames_remaining: u8 = 2;
    var prev_phys_w: i32 = 0;
    var prev_phys_h: i32 = 0;
    var pixel_storage: []u32 = &.{};
    defer if (pixel_storage.len > 0) std.heap.c_allocator.free(pixel_storage);

    var backbuffer_surface: ?skia.Surface = null;
    defer if (backbuffer_surface) |s| s.deinit();

    var last_frame_ns: u64 = profiler.nowNs();
    const min_frame_interval_ns: u64 = 16_666_667;

    while (!event_state.quit_requested) {
        const t_frame_start = profiler.nowNs();

        const should_sleep = (scenario == .none) and !ctx.needs_continuous_redraw and (redraw_frames_remaining == 0) and (effective_max_frames == null);
        if (should_sleep) {
            const sleep_ts = std.c.timespec{ .sec = 0, .nsec = 16_000_000 };
            _ = std.c.nanosleep(&sleep_ts, null);
        } else if (effective_max_frames == null and !config.bench) {
            const elapsed_ns = t_frame_start -| last_frame_ns;
            if (elapsed_ns < min_frame_interval_ns) {
                const wait_ns = min_frame_interval_ns - elapsed_ns;
                const sleep_ts = std.c.timespec{ .sec = 0, .nsec = @intCast(wait_ns) };
                _ = std.c.nanosleep(&sleep_ts, null);
            }
        }

        event_state.had_event = false;
        event_state.saw_left_down = false;
        event_state.saw_left_up = false;
        event_state.saw_right_down = false;
        event_state.saw_right_up = false;
        ctx.mouse_down = false;
        ctx.mouse_pressed = false;
        ctx.mouse_released = false;
        ctx.right_mouse_down = false;
        ctx.right_mouse_pressed = false;
        ctx.right_mouse_released = false;

        if (scenario != .none) {
            profiler.runScenarioTick(scenario, ctx.frame_count, &ctx);
            redraw_frames_remaining = 2;
        }

        const t_events_start = profiler.nowNs();
        if (event_state.wayland) |wl_state| {
            wl_state.pumpEvents();
        } else if (event_state.x11) |x11| {
            if (event_state.display) |dpy| {
                while (x11.XPending(dpy) > 0) {
                    var ev: XEvent = undefined;
                    _ = x11.XNextEvent(dpy, &ev);
                    switch (ev.type) {
                        Expose => {
                            ctx.force_full_redraw = true;
                            event_state.had_event = true;
                        },
                        ConfigureNotify => {
                            const nw = @max(1, ev.xconfigure.width);
                            const nh = @max(1, ev.xconfigure.height);
                            if (nw != event_state.win_w or nh != event_state.win_h) {
                                event_state.win_w = nw;
                                event_state.win_h = nh;
                                ctx.force_full_redraw = true;
                                event_state.had_event = true;
                            }
                        },
                        MotionNotify => {
                            ctx.mouse_x = @floatFromInt(ev.xmotion.x);
                            ctx.mouse_y = @floatFromInt(ev.xmotion.y);
                            ctx.mouse_shift = (ev.xmotion.state & ShiftMask) != 0;
                            event_state.had_event = true;
                        },
                        ButtonPress => {
                            ctx.mouse_x = @floatFromInt(ev.xbutton.x);
                            ctx.mouse_y = @floatFromInt(ev.xbutton.y);
                            ctx.mouse_shift = (ev.xbutton.state & ShiftMask) != 0;
                            event_state.had_event = true;
                            if (ev.xbutton.button == 1) {
                                // Allow dragging the custom caption bar (`y < 36.0` outside menu/pill/window-controls) via `_NET_WM_MOVERESIZE`
                                const win_w_f: f32 = @floatFromInt(event_state.win_w);
                                const pill_left = (win_w_f - 300.0) * 0.5;
                                const pill_right = (win_w_f + 300.0) * 0.5;
                                if (ctx.mouse_y >= 0.0 and ctx.mouse_y < 36.0 and
                                    ctx.mouse_x >= 144.0 and (ctx.mouse_x < pill_left or ctx.mouse_x > pill_right) and
                                    ctx.mouse_x < win_w_f - 138.0 and event_state.net_wm_moveresize != 0)
                                {
                                    var mrev: XEvent = .{ .xclient = .{
                                        .type = ClientMessage,
                                        .serial = 0,
                                        .send_event = 1,
                                        .display = dpy,
                                        .window = event_state.window,
                                        .message_type = event_state.net_wm_moveresize,
                                        .format = 32,
                                        .data_l = .{
                                            ev.xbutton.x_root,
                                            ev.xbutton.y_root,
                                            8, // _NET_WM_MOVERESIZE_MOVE
                                            1, // Button1
                                            1,
                                        },
                                    } };
                                    _ = x11.XSendEvent(dpy, event_state.root_win, 0, SubstructureRedirectMask | SubstructureNotifyMask, &mrev);
                                    _ = x11.XFlush(dpy);
                                } else {
                                    ctx.mouse_click_count = 1;
                                    event_state.saw_left_down = true;
                                    event_state.mouse_down = true;
                                }
                            } else if (ev.xbutton.button == 3) {
                                event_state.saw_right_down = true;
                                event_state.right_mouse_down = true;
                            } else if (ev.xbutton.button == 4) {
                                ctx.scroll_dy += 36.0;
                            } else if (ev.xbutton.button == 5) {
                                ctx.scroll_dy -= 36.0;
                            } else if (ev.xbutton.button == 6) {
                                ctx.scroll_dx += 36.0;
                            } else if (ev.xbutton.button == 7) {
                                ctx.scroll_dx -= 36.0;
                            }
                        },
                        ButtonRelease => {
                            ctx.mouse_x = @floatFromInt(ev.xbutton.x);
                            ctx.mouse_y = @floatFromInt(ev.xbutton.y);
                            event_state.had_event = true;
                            if (ev.xbutton.button == 1) {
                                event_state.saw_left_up = true;
                                event_state.mouse_down = false;
                            } else if (ev.xbutton.button == 3) {
                                event_state.saw_right_up = true;
                                event_state.right_mouse_down = false;
                            }
                        },
                        KeyPress => {
                            event_state.had_event = true;
                            var ks: KeySym = 0;
                            var str_buf: [32]u8 = undefined;
                            const n_chars = x11.XLookupString(&ev.xkey, &str_buf, str_buf.len, &ks, null);
                            if (ks == 0) ks = x11.XLookupKeysym(&ev.xkey, 0);
                            const shift = (ev.xkey.state & ShiftMask) != 0;
                            const ctrl = (ev.xkey.state & ControlMask) != 0;
                            const alt = (ev.xkey.state & Mod1Mask) != 0;
                            const super = (ev.xkey.state & Mod4Mask) != 0;
                            const kc = translateKeySym(ks);
                            if (kc != .none) {
                                ctx.pushKeyEvent(.{
                                    .key = kc,
                                    .shift = shift,
                                    .ctrl = ctrl,
                                    .alt = alt,
                                    .cmd = ctrl or super,
                                });
                            }
                            if (!ctrl and !alt and !super and n_chars > 0) {
                                const slice = str_buf[0..@intCast(n_chars)];
                                var clean_buf: [32]u8 = undefined;
                                var clean_len: usize = 0;
                                for (slice) |ch| {
                                    if (ch >= 0x20 and ch != 0x7f) {
                                        clean_buf[clean_len] = ch;
                                        clean_len += 1;
                                    }
                                }
                                if (clean_len > 0) {
                                    ctx.pushTextInput(clean_buf[0..clean_len]);
                                }
                            }
                        },
                        ClientMessage => {
                            if (@as(Atom, @intCast(ev.xclient.data_l[0])) == event_state.wm_delete_window) {
                                event_state.quit_requested = true;
                            }
                        },
                        else => {},
                    }
                }
            }
        }
        const t_events_end = profiler.nowNs();
        const events_ns = t_events_end - t_events_start;
        trace_collector.record("Linux.Events", "event", t_events_start, t_events_end);

        if (debug_server.poll(&ctx, &metrics_collector, &trace_collector)) {
            redraw_frames_remaining = @max(redraw_frames_remaining, 2);
        }

        if (event_state.quit_requested) break;
        if (effective_max_frames) |limit| {
            if (ctx.frame_count >= limit) break;
        }

        if (should_sleep or ctx.frame_count % 15 == 0) {
            if (hot_lib.checkAndReload(&ctx)) {
                ctx.force_full_redraw = true;
                redraw_frames_remaining = 2;
            }
        }

        const phys_w: i32 = @max(1, event_state.win_w);
        const phys_h: i32 = @max(1, event_state.win_h);
        ctx.dpi_scale = 1.0;
        ctx.width = @floatFromInt(phys_w);
        ctx.height = @floatFromInt(phys_h);

        const size_changed = (phys_w != prev_phys_w) or (phys_h != prev_phys_h) or (backbuffer_surface == null);
        if (size_changed) {
            if (backbuffer_surface) |old_s| old_s.deinit();
            if (pixel_storage.len > 0) std.heap.c_allocator.free(pixel_storage);

            const total_pixels: usize = @intCast(phys_w * phys_h);
            pixel_storage = try std.heap.c_allocator.alloc(u32, total_pixels);
            @memset(pixel_storage, 0xFF0B0F19);

            const info = skia.ImageInfo.initBgra8888Premul(phys_w, phys_h);
            backbuffer_surface = try skia.Surface.initRasterDirect(
                info,
                @ptrCast(pixel_storage.ptr),
                @as(usize, @intCast(phys_w)) * @sizeOf(u32),
            );
            ctx.force_full_redraw = true;
            redraw_frames_remaining = 4;
            prev_phys_w = phys_w;
            prev_phys_h = phys_h;
        } else if (event_state.had_event or ctx.text_input_len > 0 or ctx.key_event_count > 0) {
            redraw_frames_remaining = @max(redraw_frames_remaining, 2);
        }

        if (redraw_frames_remaining > 0) {
            redraw_frames_remaining -= 1;
        }

        ctx.mouse_down = ctx.mouse_down or event_state.mouse_down or event_state.saw_left_down;
        ctx.mouse_pressed = ctx.mouse_pressed or event_state.saw_left_down;
        ctx.mouse_released = ctx.mouse_released or event_state.saw_left_up;
        ctx.right_mouse_down = ctx.right_mouse_down or event_state.right_mouse_down or event_state.saw_right_down;
        ctx.right_mouse_pressed = ctx.right_mouse_pressed or event_state.saw_right_down;
        ctx.right_mouse_released = ctx.right_mouse_released or event_state.saw_right_up;

        const backbuffer = backbuffer_surface.?;
        const back_canvas = backbuffer.canvas();
        _ = back_canvas.save();
        back_canvas.scale(ctx.dpi_scale, ctx.dpi_scale);

        ctx.canvas = back_canvas.ptr;
        ctx.cursor_shape = .arrow;
        ctx.phase_input_us = 0;
        ctx.phase_paint_us = 0;

        const t_tick_start = profiler.nowNs();
        profiler.signpostStart(.app_tick, @intCast(ctx.frame_count));
        const did_paint = if (hot_lib.app_tick) |tick_fn| tick_fn(&ctx) else false;
        profiler.signpostEnd(.app_tick, @intCast(ctx.frame_count));
        const t_tick_end = profiler.nowNs();

        if (ctx.show_dirty_overlay and did_paint) {
            back_canvas.drawRect(ctx.last_dirty_rect, debug_paint);
        }
        back_canvas.restore();

        ctx.canvas = null;
        ctx.clearFrameInput();

        if (ctx.phase_input_us > 0) {
            const input_dur_ns = @as(u64, ctx.phase_input_us) * 1000;
            trace_collector.record("Pass.input", "layout", t_tick_start, t_tick_start + input_dur_ns);
        }
        if (ctx.phase_paint_us > 0) {
            const paint_dur_ns = @as(u64, ctx.phase_paint_us) * 1000;
            trace_collector.record("Pass.paint", "render", t_tick_end - paint_dur_ns, t_tick_end);
        }

        if (event_state.pending_window_action != 0) {
            executePendingLinuxWindowAction(&event_state);
            redraw_frames_remaining = @max(redraw_frames_remaining, 2);
        }

        if (!did_paint and effective_max_frames == null) {
            metrics_collector.recordIdleWakeup(&ctx);
            last_frame_ns = profiler.nowNs();
            continue;
        }

        const t_present_start = profiler.nowNs();
        if (event_state.wayland) |wl_state| {
            wl_state.present(pixel_storage, phys_w, phys_h);
        } else if (event_state.x11) |x11| {
            if (event_state.display) |dpy| {
                const gc = x11.XDefaultGC(dpy, event_state.screen);
                const vis = x11.XDefaultVisual(dpy, event_state.screen);
                const depth: c_uint = @intCast(x11.XDefaultDepth(dpy, event_state.screen));
                if (x11.XCreateImage(
                    dpy,
                    vis,
                    depth,
                    ZPixmap,
                    0,
                    @ptrCast(pixel_storage.ptr),
                    @intCast(phys_w),
                    @intCast(phys_h),
                    32,
                    phys_w * 4,
                )) |ximg| {
                    _ = x11.XPutImage(
                        dpy,
                        event_state.window,
                        gc,
                        ximg,
                        0,
                        0,
                        0,
                        0,
                        @intCast(phys_w),
                        @intCast(phys_h),
                    );
                    ximg.data = null;
                    std.c.free(ximg);
                    _ = x11.XFlush(dpy);
                }
            }
        }
        const t_present_end = profiler.nowNs();
        trace_collector.record("Linux.XPutImage", "gpu", t_present_start, t_present_end);
        last_frame_ns = t_present_end;

        const t_frame_end = profiler.nowNs();
        trace_collector.record("Frame", "frame", t_frame_start, t_frame_end);

        const total_win_area = @max(1.0, ctx.width * ctx.height);
        const dirty_area = skia.Rect.area(ctx.last_dirty_rect);
        metrics_collector.recordFrame(
            .{
                .total_ns = t_frame_end - t_frame_start,
                .events_ns = events_ns,
                .input_ns = @as(u64, ctx.phase_input_us) * 1000,
                .paint_ns = @as(u64, ctx.phase_paint_us) * 1000,
                .gpu_flush_ns = 0,
                .metal_present_ns = t_present_end - t_present_start,
                .damage_pct = @floatCast((dirty_area / total_win_area) * 100.0),
            },
            pixel_storage.len * @sizeOf(u32),
            1,
            &ctx,
        );

        ctx.frame_count += 1;
    }

    if (config.screenshot_path) |shot_path| {
        if (backbuffer_surface) |surf| {
            if (surf.encodePng()) |png_data| {
                defer png_data.deinit();
                var path_z: [1024:0]u8 = @splat(0);
                if (shot_path.len < path_z.len) {
                    @memcpy(path_z[0..shot_path.len], shot_path);
                    path_z[shot_path.len] = 0;
                    if (std.c.fopen(&path_z, "wb")) |fp| {
                        const bytes = png_data.slice();
                        _ = std.c.fwrite(bytes.ptr, 1, bytes.len, fp);
                        _ = std.c.fclose(fp);
                    }
                }
            } else |_| {}
        }
    }
}
