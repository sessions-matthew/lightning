//! Dynamic library (`dlopen`/`dlsym`) hot-reloader for `libeditor_app.dylib`.
//! Invokes `app_before_reload` on the outgoing `.dylib` prior to `dlclose` so global state
//! can be serialized to JSON and `.dylib`-owned Skia resources are cleanly released.

const std = @import("std");
const app_api = @import("app_api.zig");
const fs_util = @import("fs_util.zig");
const objc = @import("macos/objc.zig");

pub const HotDylib = struct {
    watch_path: [*:0]const u8 = fs_util.DefaultAppLibPath,
    handle: ?*anyopaque = null,
    last_mtime: f64 = 0,
    generation: u32 = 0,
    loaded_temp_path: [256]u8 = undefined,
    has_temp_path: bool = false,

    app_init: ?app_api.AppInitFn = null,
    app_before_reload: ?app_api.AppBeforeReloadFn = null,
    app_on_reload: ?app_api.AppOnReloadFn = null,
    app_tick: ?app_api.AppTickFn = null,
    app_deinit: ?app_api.AppDeinitFn = null,

    fn queryMtime(self: *const HotDylib) f64 {
        return fs_util.fileMtimeSec(self.watch_path) orelse 0;
    }

    pub fn checkAndReload(self: *HotDylib, ctx: *app_api.PlatformContext) bool {
        const mtime = self.queryMtime();
        if (mtime == 0 or mtime == self.last_mtime) return false;

        self.generation += 1;
        var temp_buf: [256]u8 = undefined;
        const temp_raw = std.fmt.bufPrint(
            &temp_buf,
            "{s}/libeditor_app_hot_{d}{s}\x00",
            .{ fs_util.tempDirPath(), self.generation, fs_util.SharedLibExt },
        ) catch return false;
        const temp_slice: [:0]const u8 = temp_raw[0 .. temp_raw.len - 1 :0];

        if (!fs_util.copyFileAtomic(self.watch_path, temp_slice.ptr)) return false;

        const new_handle = objc.dlopen(temp_slice.ptr, objc.RTLD_NOW | objc.RTLD_LOCAL) orelse return false;

        const init_sym = objc.dlsym(new_handle, "app_init") orelse {
            _ = objc.dlclose(new_handle);
            return false;
        };
        const before_reload_sym = objc.dlsym(new_handle, "app_before_reload");
        const reload_sym = objc.dlsym(new_handle, "app_on_reload") orelse {
            _ = objc.dlclose(new_handle);
            return false;
        };
        const tick_sym = objc.dlsym(new_handle, "app_tick") orelse {
            _ = objc.dlclose(new_handle);
            return false;
        };
        const deinit_sym = objc.dlsym(new_handle, "app_deinit") orelse {
            _ = objc.dlclose(new_handle);
            return false;
        };

        const is_first_load = (self.handle == null);

        // Give the outgoing `.dylib` a chance to serialize global state to JSON and release its resources
        if (!is_first_load) {
            if (self.app_before_reload) |before_fn| {
                before_fn(ctx);
            }
        }

        if (self.handle) |old_handle| {
            _ = objc.dlclose(old_handle);
        }
        if (self.has_temp_path) {
            const old_path: [*:0]const u8 = @ptrCast(&self.loaded_temp_path);
            _ = fs_util.unlink(old_path);
        }

        @memcpy(self.loaded_temp_path[0 .. temp_slice.len + 1], temp_slice[0 .. temp_slice.len + 1]);
        self.has_temp_path = true;
        self.handle = new_handle;
        self.last_mtime = mtime;

        self.app_init = @ptrCast(@alignCast(init_sym));
        self.app_before_reload = if (before_reload_sym) |s| @ptrCast(@alignCast(s)) else null;
        self.app_on_reload = @ptrCast(@alignCast(reload_sym));
        self.app_tick = @ptrCast(@alignCast(tick_sym));
        self.app_deinit = @ptrCast(@alignCast(deinit_sym));

        if (is_first_load) {
            self.app_init.?(ctx);
        } else {
            ctx.reload_count += 1;
            self.app_on_reload.?(ctx);
            std.debug.print(
                "[hot-reload] Reloaded libeditor_app.dylib (gen #{d}, {d} useState hooks preserved)\n",
                .{ ctx.reload_count, ctx.stateEntryCount() },
            );
        }
        return true;
    }

    pub fn unload(self: *HotDylib, ctx: *app_api.PlatformContext) void {
        if (self.app_deinit) |deinit_fn| {
            deinit_fn(ctx);
        }
        // Keep `self.handle` mapped and `/tmp/libeditor_app_hot_{gen}.dylib` on disk at process exit
        // so Apple Instruments (`xctrace`) and macOS crash reporters can symbolicate all plugin frames.
        self.handle = null;
        self.has_temp_path = false;
    }
};
