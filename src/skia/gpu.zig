//! Idiomatic wrapper for Skia's Ganesh GPU `DirectContext`.

const c = @import("c/root.zig");
const root = @import("root.zig");
const Error = root.Error;

pub const DirectContext = struct {
    ptr: *c.gr_direct_context_t,

    pub fn initMetal(device: *anyopaque, queue: *anyopaque) Error!DirectContext {
        const ptr = c.gr_direct_context_make_metal(device, queue) orelse return Error.InvalidSurface;
        return .{ .ptr = ptr };
    }

    pub fn deinit(self: DirectContext) void {
        c.gr_recording_context_unref(@ptrCast(self.ptr));
    }

    pub fn flushAndSubmit(self: DirectContext, sync_cpu: bool) void {
        c.gr_direct_context_flush_and_submit(self.ptr, sync_cpu);
    }

    pub fn setResourceCacheLimit(self: DirectContext, max_bytes: usize) void {
        c.gr_direct_context_set_resource_cache_limit(self.ptr, max_bytes);
    }

    pub fn getResourceCacheUsage(self: DirectContext) struct { resources: i32, bytes: usize } {
        var res: c_int = 0;
        var bytes: usize = 0;
        c.gr_direct_context_get_resource_cache_usage(self.ptr, &res, &bytes);
        return .{ .resources = res, .bytes = bytes };
    }

    pub fn purgeUnlockedResources(self: DirectContext, scratch_only: bool) void {
        c.gr_direct_context_purge_unlocked_resources(self.ptr, scratch_only);
    }

    pub fn performDeferredCleanup(self: DirectContext, ms_not_used: i64) void {
        c.gr_direct_context_perform_deferred_cleanup(self.ptr, ms_not_used);
    }

    pub fn freeGpuResources(self: DirectContext) void {
        c.gr_direct_context_free_gpu_resources(self.ptr);
    }
};
