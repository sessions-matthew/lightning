//! SkiaSharp C API Ganesh GPU context functions (`gr_context.h`).

const t = @import("types.zig");

pub extern "c" fn gr_recording_context_unref(context: *t.gr_recording_context_t) void;
pub extern "c" fn gr_direct_context_make_metal(device: *anyopaque, queue: *anyopaque) ?*t.gr_direct_context_t;
pub extern "c" fn gr_direct_context_flush(context: *t.gr_direct_context_t) void;
pub extern "c" fn gr_direct_context_submit(context: *t.gr_direct_context_t, syncCpu: bool) bool;
pub extern "c" fn gr_direct_context_flush_and_submit(context: *t.gr_direct_context_t, syncCpu: bool) void;
pub extern "c" fn gr_direct_context_flush_surface(context: *t.gr_direct_context_t, surface: *t.sk_surface_t) void;
pub extern "c" fn gr_direct_context_set_resource_cache_limit(context: *t.gr_direct_context_t, maxResourceBytes: usize) void;
pub extern "c" fn gr_direct_context_get_resource_cache_usage(context: *t.gr_direct_context_t, maxResources: *c_int, maxResourceBytes: *usize) void;
pub extern "c" fn gr_direct_context_purge_unlocked_resources(context: *t.gr_direct_context_t, scratchResourcesOnly: bool) void;
pub extern "c" fn gr_direct_context_perform_deferred_cleanup(context: *t.gr_direct_context_t, ms: c_longlong) void;
pub extern "c" fn gr_direct_context_free_gpu_resources(context: *t.gr_direct_context_t) void;
pub extern "c" fn gr_direct_context_release_resources_and_abandon_context(context: *t.gr_direct_context_t) void;
