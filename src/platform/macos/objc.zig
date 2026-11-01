//! Pure-Zig macOS Objective-C Runtime, AppKit, Metal, and CoreFoundation bindings (no `@cImport`),
//! plus cross-platform dynamic library (`dlopen`/`LoadLibraryA`) and monotonic clock helpers.

const builtin = @import("builtin");
pub const is_macos = (builtin.os.tag == .macos);
pub const is_windows = (builtin.os.tag == .windows);

pub const id = ?*anyopaque;
pub const Class = ?*anyopaque;
pub const SEL = ?*anyopaque;
pub const Protocol = ?*anyopaque;

pub const CGFloat = f64;

pub const NSPoint = extern struct {
    x: CGFloat,
    y: CGFloat,
};

pub const NSSize = extern struct {
    width: CGFloat,
    height: CGFloat,
};

pub const NSRect = extern struct {
    origin: NSPoint,
    size: NSSize,
};

pub extern "c" fn objc_getClass(name: [*:0]const u8) Class;
pub extern "c" fn objc_getProtocol(name: [*:0]const u8) Protocol;
pub extern "c" fn objc_allocateClassPair(superclass: Class, name: [*:0]const u8, extraBytes: usize) Class;
pub extern "c" fn objc_registerClassPair(cls: Class) void;
pub extern "c" fn class_addMethod(cls: Class, name: SEL, imp: *const anyopaque, types: [*:0]const u8) bool;
pub extern "c" fn class_addProtocol(cls: Class, protocol: Protocol) bool;
pub extern "c" fn protocol_getName(proto: Protocol) ?[*:0]const u8;
pub extern "c" fn sel_registerName(str: [*:0]const u8) SEL;
pub extern "c" fn objc_msgSend() void;
pub extern "c" fn objc_autoreleasePoolPush() ?*anyopaque;
pub extern "c" fn objc_autoreleasePoolPop(pool: ?*anyopaque) void;
pub extern "c" fn MTLCreateSystemDefaultDevice() id;
pub extern "c" fn CFRelease(cf: *const anyopaque) void;
pub extern "c" fn CFAbsoluteTimeGetCurrent() f64;
pub extern "c" fn clock_gettime_nsec_np(clock_id: c_uint) u64;

const win32_kernel = struct {
    extern "kernel32" fn QueryPerformanceCounter(lpPerformanceCount: *i64) callconv(.winapi) c_int;
    extern "kernel32" fn QueryPerformanceFrequency(lpFrequency: *i64) callconv(.winapi) c_int;
    extern "kernel32" fn LoadLibraryA(lpLibFileName: [*:0]const u8) callconv(.winapi) ?*anyopaque;
    extern "kernel32" fn GetProcAddress(hModule: *anyopaque, lpProcName: [*:0]const u8) callconv(.winapi) ?*anyopaque;
    extern "kernel32" fn FreeLibrary(hLibModule: *anyopaque) callconv(.winapi) c_int;
};

pub const CLOCK_UPTIME_RAW: c_uint = 8;
pub inline fn getMonotonicNs() u64 {
    if (comptime is_macos) {
        return clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    } else if (comptime is_windows) {
        var count: i64 = 0;
        var freq: i64 = 0;
        _ = win32_kernel.QueryPerformanceCounter(&count);
        _ = win32_kernel.QueryPerformanceFrequency(&freq);
        if (freq <= 0 or count <= 0) return 0;
        const c_u128: u128 = @intCast(count);
        const f_u128: u128 = @intCast(freq);
        return @intCast((c_u128 * 1_000_000_000) / f_u128);
    } else {
        const std = @import("std");
        var ts: std.c.timespec = undefined;
        if (std.c.clock_gettime(@enumFromInt(1), &ts) == 0) {
            const sec: u64 = @intCast(@max(0, ts.sec));
            const nsec: u64 = @intCast(@max(0, ts.nsec));
            return sec * 1_000_000_000 + nsec;
        }
        return 0;
    }
}

const posix_dl = struct {
    extern "c" fn dlopen(path: [*:0]const u8, mode: c_int) ?*anyopaque;
    extern "c" fn dlsym(handle: *anyopaque, symbol: [*:0]const u8) ?*anyopaque;
    extern "c" fn dlclose(handle: *anyopaque) c_int;
};

pub fn dlopen(path: [*:0]const u8, mode: c_int) ?*anyopaque {
    if (comptime is_windows) {
        return win32_kernel.LoadLibraryA(path);
    } else {
        return posix_dl.dlopen(path, mode);
    }
}

pub fn dlsym(handle: *anyopaque, symbol: [*:0]const u8) ?*anyopaque {
    if (comptime is_windows) {
        return win32_kernel.GetProcAddress(handle, symbol);
    } else {
        return posix_dl.dlsym(handle, symbol);
    }
}

pub fn dlclose(handle: *anyopaque) c_int {
    if (comptime is_windows) {
        return if (win32_kernel.FreeLibrary(handle) != 0) 0 else -1;
    } else {
        return posix_dl.dlclose(handle);
    }
}

pub const RTLD_NOW: c_int = 0x2;
pub const RTLD_LOCAL: c_int = if (builtin.os.tag == .linux) 0x0 else 0x4;

// NSWindowStyleMask flags
pub const NSWindowStyleMaskTitled: usize = 1 << 0;
pub const NSWindowStyleMaskClosable: usize = 1 << 1;
pub const NSWindowStyleMaskMiniaturizable: usize = 1 << 2;
pub const NSWindowStyleMaskResizable: usize = 1 << 3;
pub const NSWindowStyleMaskFullScreen: usize = 1 << 14;
pub const NSWindowStyleMaskFullSizeContentView: usize = 1 << 15;

// NSWindowCollectionBehavior flags
pub const NSWindowCollectionBehaviorFullScreenPrimary: usize = 1 << 7;

// NSEventType constants
pub const NSEventTypeLeftMouseDown: usize = 1;
pub const NSEventTypeLeftMouseUp: usize = 2;
pub const NSEventTypeRightMouseDown: usize = 3;
pub const NSEventTypeRightMouseUp: usize = 4;
pub const NSEventTypeLeftMouseDragged: usize = 6;
pub const NSEventTypeKeyDown: usize = 10;
pub const NSEventTypeKeyUp: usize = 11;
pub const NSEventTypeFlagsChanged: usize = 12;
pub const NSEventTypeScrollWheel: usize = 22;
pub const NSEventTypeMagnify: usize = 30;
pub const NSEventTypeSmartMagnify: usize = 32;

// NSEventModifierFlags constants
pub const NSEventModifierFlagShift: usize = 1 << 17;
pub const NSEventModifierFlagControl: usize = 1 << 18;
pub const NSEventModifierFlagOption: usize = 1 << 19;
pub const NSEventModifierFlagCommand: usize = 1 << 20;

pub extern "c" const NSDefaultRunLoopMode: id;

pub fn msgSend0(recv: id, comptime Ret: type, sel_name: [*:0]const u8) Ret {
    const fn_ptr: *const fn (id, SEL) callconv(.c) Ret = @ptrCast(&objc_msgSend);
    return fn_ptr(recv, sel_registerName(sel_name));
}

pub fn msgSend1(recv: id, comptime Ret: type, sel_name: [*:0]const u8, a1: anytype) Ret {
    const fn_ptr: *const fn (id, SEL, @TypeOf(a1)) callconv(.c) Ret = @ptrCast(&objc_msgSend);
    return fn_ptr(recv, sel_registerName(sel_name), a1);
}

pub fn msgSend2(recv: id, comptime Ret: type, sel_name: [*:0]const u8, a1: anytype, a2: anytype) Ret {
    const fn_ptr: *const fn (id, SEL, @TypeOf(a1), @TypeOf(a2)) callconv(.c) Ret = @ptrCast(&objc_msgSend);
    return fn_ptr(recv, sel_registerName(sel_name), a1, a2);
}

pub fn msgSend3(recv: id, comptime Ret: type, sel_name: [*:0]const u8, a1: anytype, a2: anytype, a3: anytype) Ret {
    const fn_ptr: *const fn (id, SEL, @TypeOf(a1), @TypeOf(a2), @TypeOf(a3)) callconv(.c) Ret = @ptrCast(&objc_msgSend);
    return fn_ptr(recv, sel_registerName(sel_name), a1, a2, a3);
}

pub fn msgSend4(
    recv: id,
    comptime Ret: type,
    sel_name: [*:0]const u8,
    a1: anytype,
    a2: anytype,
    a3: anytype,
    a4: anytype,
) Ret {
    const fn_ptr: *const fn (id, SEL, @TypeOf(a1), @TypeOf(a2), @TypeOf(a3), @TypeOf(a4)) callconv(.c) Ret = @ptrCast(&objc_msgSend);
    return fn_ptr(recv, sel_registerName(sel_name), a1, a2, a3, a4);
}

pub fn nsString(utf8: [*:0]const u8) id {
    const NSString = objc_getClass("NSString");
    return msgSend1(NSString, id, "stringWithUTF8String:", utf8);
}
