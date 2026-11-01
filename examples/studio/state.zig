//! Persistent application state and GPU resource management for `libeditor_app.dylib`.
//!
//! Demonstrates the hybrid hot-reload state architecture:
//!   1. **Global Structured App State (`WorkspaceDocument`)**: Plain Zig struct accessed at native
//!      speed during rendering, serialized to JSON on `app_before_reload` and restored via
//!      `std.json.parseFromSlice(..., .{ .ignore_unknown_fields = true })` on `app_on_reload`.
//!      Adding or removing fields in `WorkspaceDocument` never corrupts memory across reloads!
//!   2. **Component UI State (`uic.useState`)**: Stored in the Host's Type-Hashed KV Store
//!      (see `src/app/views/sidebar.zig`), allowing local component state to be added, removed,
//!      or have its type changed on the fly like React Fast Refresh.

const std = @import("std");
const skia = @import("skia");
const ui = @import("ui");
const platform = @import("platform");
const PlatformContext = platform.PlatformContext;

pub const STATE_VERSION: u64 = 0x2026_1019_0007;

pub const StageStyleMode = enum(u8) {
    orbit,
    lattice,
    bloom,
};

pub const ACCENT_SWATCHES = [_]u32{
    skia.Color.rgb(99, 102, 241),
    skia.Color.rgb(236, 72, 153),
    skia.Color.rgb(14, 165, 233),
    skia.Color.rgb(34, 197, 94),
    skia.Color.rgb(245, 158, 11),
};

/// Structured global document state.
/// Automatically serialized to JSON before `.dylib` unload and parsed back with
/// `.ignore_unknown_fields = true` after reload—so you can freely add, remove, or reorder fields!
pub const WorkspaceDocument = struct {
    show_grid: bool = true,
    show_cursor_halo: bool = false,
    show_dirty_overlay: bool = true,
    style_mode: StageStyleMode = .orbit,
    accent_color: u32 = skia.Color.rgb(99, 102, 241),
    rotation_speed: f32 = 1.2,
    ring_count: f32 = 4.0,
    corner_radius: f32 = 44.0,
    zoom: f32 = 1.0,
    stroke_width: f32 = 5.0,
    spread_angle: f32 = 20.0,
    viewport: ui.Viewport2DState = .{},
};

pub const AppState = struct {
    frame_arena: std.heap.ArenaAllocator,
    fonts: ui.FontSet = undefined,
    paint: skia.Paint = undefined,
    font_title: skia.Font = undefined,
    font_body: skia.Font = undefined,
    font_mono: skia.Font = undefined,
    ui_ctx: ui.Context = undefined,

    // Persistent GPU resources (reused across frames to preserve Skia pipeline/uniform caches)
    ring_shader: ?skia.Shader = null,
    active_shader_accent: u32 = 0,
    grid_path: ?skia.Path = null,
    grid_w: f32 = 0,
    grid_h: f32 = 0,

    // Global structured document state (persisted via Reload-Boundary JSON Serialization)
    doc: WorkspaceDocument = .{},

    // Value-oriented notification toast queue (dlclose-safe InlineString storage)
    toasts: ui.ToastQueue(4) = .{},

    // Fine-grained damage tracking
    stage_full_dirty: bool = true,
    prev_mouse_x: f32 = -1,
    prev_mouse_y: f32 = -1,
    prev_reload_count: u32 = 0,

    pub fn initResources(state: *AppState, ctx: *PlatformContext) void {
        state.fonts = ui.FontSet.init(ctx, .{});
        state.paint = state.fonts.paint;
        state.font_title = state.fonts.title;
        state.font_body = state.fonts.body;
        state.font_mono = state.fonts.mono;

        state.rebuildRingShader(state.doc.accent_color);
        state.ui_ctx = state.fonts.initContext(state.frame_arena.allocator(), ctx);
    }

    pub fn rebuildRingShader(state: *AppState, primary_accent: u32) void {
        if (state.ring_shader) |existing| {
            if (state.active_shader_accent == primary_accent) return;
            existing.deinit();
            state.ring_shader = null;
        }
        const accent_colors = [_]u32{
            primary_accent,
            skia.Color.rgb(236, 72, 153),
            skia.Color.rgb(14, 165, 233),
        };
        state.ring_shader = skia.Shader.initLinearGradient(
            .{ .x = -160, .y = -160 },
            .{ .x = 160, .y = 160 },
            &accent_colors,
            null,
            .clamp,
        ) catch null;
        state.active_shader_accent = primary_accent;
    }

    pub fn onAfterReload(state: *AppState) void {
        state.rebuildRingShader(state.doc.accent_color);
        state.stage_full_dirty = true;
    }

    pub fn ensureGridPath(state: *AppState, stage_w: f32, stage_h: f32) ?skia.Path {
        if (state.grid_path) |existing| {
            if (state.grid_w == stage_w and state.grid_h == stage_h) {
                return existing;
            }
            existing.deinit();
            state.grid_path = null;
        }

        const pb = skia.PathBuilder.init() catch return null;
        defer pb.deinit();

        const step: f32 = 36.0;
        var gx: f32 = step;
        while (gx < stage_w) : (gx += step) {
            pb.moveTo(gx, 0);
            pb.lineTo(gx, stage_h);
        }
        var gy: f32 = step;
        while (gy < stage_h) : (gy += step) {
            pb.moveTo(0, gy);
            pb.lineTo(stage_w, gy);
        }

        state.grid_path = pb.detach() catch null;
        state.grid_w = stage_w;
        state.grid_h = stage_h;
        return state.grid_path;
    }

    pub fn deinitResources(state: *AppState) void {
        state.ui_ctx.deinit();
        if (state.ring_shader) |s| s.deinit();
        if (state.grid_path) |p| p.deinit();
        state.fonts.deinit();
        state.frame_arena.deinit();
    }
};
