//! Ergonomic typography setup (`FontSet`) and 2-phase hardware scissor frame runner (`runTwoPhaseFrame`).
//! Eliminates repetitive font initialization and `Pass.input` / `Pass.paint` boilerplate across plugins.

const std = @import("std");
const skia = @import("skia");
const platform = @import("platform");
const root = @import("root.zig");
const PlatformContext = platform.PlatformContext;
const Context = root.Context;

pub const FontSizes = struct {
    h1: f32 = 21.0,
    h2: f32 = 17.0,
    h3: f32 = 14.5,
    title: f32 = 15.0,
    body: f32 = 13.5,
    mono: f32 = 12.0,
    code: f32 = 13.0,
};

/// Manages standard Sans, Bold, and Monospace typefaces + pre-configured subpixel anti-aliased `skia.Font`s
/// and a shared anti-aliased `skia.Paint`.
pub const FontSet = struct {
    paint: skia.Paint,
    typeface_sans: ?skia.Typeface = null,
    typeface_bold: ?skia.Typeface = null,
    typeface_mono: ?skia.Typeface = null,
    h1: skia.Font,
    h2: skia.Font,
    h3: skia.Font,
    title: skia.Font,
    body: skia.Font,
    mono: skia.Font,
    code: skia.Font,

    fn matchFirstFamily(font_mgr: skia.FontMgr, families: []const [:0]const u8, weight: i32) ?skia.Typeface {
        for (families) |fam| {
            if (font_mgr.matchFamilyStyle(fam, weight, 5, .upright) catch null) |tf| {
                return tf;
            }
        }
        return null;
    }

    fn matchFirstFile(font_mgr: skia.FontMgr, paths: []const [:0]const u8) ?skia.Typeface {
        for (paths) |p| {
            if (font_mgr.createFromFile(p)) |tf| {
                return tf;
            }
        }
        return null;
    }

    pub fn init(ctx: *const PlatformContext, sizes: FontSizes) FontSet {
        var tf_sans: ?skia.Typeface = null;
        var tf_bold: ?skia.Typeface = null;
        var tf_mono: ?skia.Typeface = null;

        const os_tag = @import("builtin").os.tag;
        const sans_families = if (comptime os_tag == .windows)
            &[_][:0]const u8{ "Segoe UI", "Arial", "Helvetica Neue" }
        else if (comptime os_tag == .linux)
            &[_][:0]const u8{ "Ubuntu", "Noto Sans", "DejaVu Sans", "Liberation Sans", "Cantarell", "Arial" }
        else
            &[_][:0]const u8{ "Helvetica Neue", "Segoe UI", "Arial" };
        const mono_families = if (comptime os_tag == .windows)
            &[_][:0]const u8{ "Cascadia Mono", "Consolas", "Courier New", "Menlo" }
        else if (comptime os_tag == .linux)
            &[_][:0]const u8{ "JetBrains Mono", "Ubuntu Mono", "DejaVu Sans Mono", "Liberation Mono", "Noto Sans Mono", "monospace" }
        else
            &[_][:0]const u8{ "Menlo", "SF Mono", "Monaco", "Consolas" };

        const linux_sans_files = [_][:0]const u8{
            "/usr/share/fonts/TTF/DejaVuSans.ttf",
            "/usr/share/fonts/liberation/LiberationSans-Regular.ttf",
            "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
            "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
            "/usr/share/fonts/noto/NotoSans-Regular.ttf",
        };
        const linux_bold_files = [_][:0]const u8{
            "/usr/share/fonts/TTF/DejaVuSans-Bold.ttf",
            "/usr/share/fonts/liberation/LiberationSans-Bold.ttf",
            "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
            "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
            "/usr/share/fonts/noto/NotoSans-Bold.ttf",
        };
        const linux_mono_files = [_][:0]const u8{
            "/usr/share/fonts/TTF/DejaVuSansMono.ttf",
            "/usr/share/fonts/liberation/LiberationMono-Regular.ttf",
            "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
            "/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf",
            "/usr/share/fonts/noto/NotoSansMono-Regular.ttf",
        };

        if (ctx.font_mgr) |font_mgr_ptr| {
            const font_mgr = skia.FontMgr{ .ptr = font_mgr_ptr };
            tf_sans = matchFirstFamily(font_mgr, sans_families, 400) orelse
                if (comptime os_tag == .linux) matchFirstFile(font_mgr, &linux_sans_files) else null;
            tf_bold = matchFirstFamily(font_mgr, sans_families, 700) orelse
                (if (comptime os_tag == .linux) matchFirstFile(font_mgr, &linux_bold_files) else null) orelse tf_sans;
            tf_mono = matchFirstFamily(font_mgr, mono_families, 400) orelse
                if (comptime os_tag == .linux) matchFirstFile(font_mgr, &linux_mono_files) else null;
        } else if (skia.FontMgr.initDefault() catch null) |owned_mgr| {
            defer owned_mgr.deinit();
            tf_sans = matchFirstFamily(owned_mgr, sans_families, 400) orelse
                if (comptime os_tag == .linux) matchFirstFile(owned_mgr, &linux_sans_files) else null;
            tf_bold = matchFirstFamily(owned_mgr, sans_families, 700) orelse
                (if (comptime os_tag == .linux) matchFirstFile(owned_mgr, &linux_bold_files) else null) orelse tf_sans;
            tf_mono = matchFirstFamily(owned_mgr, mono_families, 400) orelse
                if (comptime os_tag == .linux) matchFirstFile(owned_mgr, &linux_mono_files) else null;
        }

        const paint = skia.Paint.init() catch unreachable;
        paint.setAntiAlias(true);

        return .{
            .paint = paint,
            .typeface_sans = tf_sans,
            .typeface_bold = tf_bold,
            .typeface_mono = tf_mono,
            .h1 = makeFont(tf_bold orelse tf_sans, sizes.h1),
            .h2 = makeFont(tf_bold orelse tf_sans, sizes.h2),
            .h3 = makeFont(tf_bold orelse tf_sans, sizes.h3),
            .title = makeFont(tf_bold orelse tf_sans, sizes.title),
            .body = makeFont(tf_sans, sizes.body),
            .mono = makeFont(tf_mono orelse tf_sans, sizes.mono),
            .code = makeFont(tf_mono orelse tf_sans, sizes.code),
        };
    }

    pub fn initContext(self: *const FontSet, arena: std.mem.Allocator, ctx: *PlatformContext) Context {
        return .{
            .arena = arena,
            .canvas = undefined,
            .paint = self.paint,
            .font_title = self.title,
            .font_body = self.body,
            .font_mono = self.mono,
            .platform_ctx = ctx,
        };
    }

    pub fn deinit(self: *FontSet) void {
        self.paint.deinit();
        self.h1.deinit();
        self.h2.deinit();
        self.h3.deinit();
        self.title.deinit();
        self.body.deinit();
        self.mono.deinit();
        self.code.deinit();
        if (self.typeface_sans) |tf| tf.deinit();
        if (self.typeface_bold) |tf| tf.deinit();
        if (self.typeface_mono) |tf| tf.deinit();
    }

    fn makeFont(tf: ?skia.Typeface, size: f32) skia.Font {
        const f = skia.Font.init(tf, size) catch unreachable;
        f.setEdging(.antialias);
        f.setSubpixel(true);
        return f;
    }
};

/// Executes the standard 2-phase (`Pass.input` -> damage-rect calculation -> `Pass.paint` hardware scissor)
/// frame pipeline for a plugin's `app_tick`.
pub fn runTwoPhaseFrame(
    uic: *Context,
    ctx: *PlatformContext,
    frame_arena: *std.heap.ArenaAllocator,
    show_dirty_overlay: bool,
    state: anytype,
    comptime buildFn: anytype,
) bool {
    const canvas_ptr = ctx.canvas orelse return false;
    const canvas = skia.Canvas{ .ptr = canvas_ptr };

    _ = frame_arena.reset(.retain_capacity);
    ctx.needs_continuous_redraw = false;

    uic.platform_ctx = ctx;
    const win_rect = skia.Rect.xywh(0, 0, ctx.width, ctx.height);

    // Pass 1: CPU-only layout, input & damage-rect calculation
    const t_input_start = platform.objc.getMonotonicNs();
    uic.beginPass(
        .input,
        frame_arena.allocator(),
        canvas,
        win_rect,
        ctx.mouse_x,
        ctx.mouse_y,
        ctx.mouse_down,
        ctx.mouse_pressed,
        ctx.mouse_released,
    );
    callBuildFn(buildFn, state, ctx);
    uic.endPass();
    if (uic.animating_this_frame) ctx.needs_continuous_redraw = true;
    const t_input_end = platform.objc.getMonotonicNs();
    ctx.phase_input_us = @intCast((t_input_end - t_input_start) / 1000);

    if (ctx.force_full_redraw) {
        uic.dirty_rect = win_rect;
        uic.damage_list.clear();
        uic.damage_list.add(win_rect);
        ctx.force_full_redraw = false;
    }

    const raw_dmg = uic.dirty_rect orelse return false;
    const dmg = skia.c.sk_rect_t{
        .left = @max(0.0, raw_dmg.left),
        .top = @max(0.0, raw_dmg.top),
        .right = @min(ctx.width, raw_dmg.right),
        .bottom = @min(ctx.height, raw_dmg.bottom),
    };
    const total_area = @max(1.0, skia.Rect.area(win_rect));
    const dirty_pct = (@min(total_area, uic.dirtyArea()) / total_area) * 100.0;
    ctx.show_dirty_overlay = show_dirty_overlay and (dirty_pct < 99.0);
    ctx.last_dirty_rect = dmg;

    // Pass 2: Hardware scissor-clipped paint pass (clipped to exact disjoint rects in `damage_list`)
    const t_paint_start = platform.objc.getMonotonicNs();
    _ = canvas.save();
    defer canvas.restore();

    uic.clipCanvasToDamage(dmg);
    canvas.clear(uic.theme.bg_canvas);

    uic.clip_damage = dmg;
    uic.beginPass(
        .paint,
        frame_arena.allocator(),
        canvas,
        win_rect,
        ctx.mouse_x,
        ctx.mouse_y,
        ctx.mouse_down,
        ctx.mouse_pressed,
        ctx.mouse_released,
    );
    callBuildFn(buildFn, state, ctx);
    uic.endPass();
    const t_paint_end = platform.objc.getMonotonicNs();
    ctx.phase_paint_us = @intCast((t_paint_end - t_paint_start) / 1000);

    const tc_stats = uic.getTextCacheStats();
    ctx.text_cache_lookups = tc_stats.lookups;
    ctx.text_cache_hits = tc_stats.hits;
    ctx.text_cache_misses = tc_stats.misses;
    ctx.text_cache_evictions = tc_stats.evictions;

    return true;
}

fn callBuildFn(comptime buildFn: anytype, state: anytype, ctx: *PlatformContext) void {
    const fn_info = @typeInfo(@TypeOf(buildFn)).@"fn";
    if (fn_info.param_types.len == 1) {
        buildFn(state);
    } else {
        buildFn(state, ctx);
    }
}

/// Comptime generator that exports the standard 5 hot-reload C-ABI plugin symbols
/// (`app_init`, `app_before_reload`, `app_on_reload`, `app_deinit`, `app_tick`)
/// for a plugin state struct `StateType`.
///
/// `StateType` must have:
///   - `frame_arena: std.heap.ArenaAllocator`
///   - `ui_ctx: ui.Context`
///   - `snapshot_field`: struct field (e.g. `"doc"` or `"config"`) serialized across reloads,
///     containing `.show_dirty_overlay: bool`
///   - `init(self: *StateType, ctx: *PlatformContext) void` (or `initResources`)
///   - `deinit(self: *StateType) void` (or `deinitResources`)
///   - optional `onBeforeReload(self: *StateType, ctx: *PlatformContext) void` (or 1-arg `onBeforeReload(self: *StateType) void`)
///   - optional `onAfterReload(self: *StateType) void`
pub fn exportPlugin(
    comptime StateType: type,
    comptime snapshot_field: []const u8,
    comptime state_version: u64,
    comptime buildFn: anytype,
) void {
    const SnapshotType = @FieldType(StateType, snapshot_field);

    const Hooks = struct {
        fn app_init(ctx: *PlatformContext) callconv(.c) void {
            const state = std.heap.c_allocator.create(StateType) catch return;
            state.* = .{
                .frame_arena = std.heap.ArenaAllocator.init(std.heap.c_allocator),
                .fonts = undefined,
                .ui_ctx = undefined,
            };
            if (@hasDecl(StateType, "init")) {
                state.init(ctx);
            } else {
                state.initResources(ctx);
            }

            ctx.state = state;
            ctx.state_size = @sizeOf(StateType);
            ctx.state_version = state_version;
            ctx.force_full_redraw = true;
        }

        fn app_before_reload(ctx: *PlatformContext) callconv(.c) void {
            const ptr = ctx.state orelse return;
            const state: *StateType = @ptrCast(@alignCast(ptr));
            if (@hasDecl(StateType, "onBeforeReload")) {
                const fn_info = @typeInfo(@TypeOf(StateType.onBeforeReload)).@"fn";
                if (fn_info.param_types.len == 1) {
                    state.onBeforeReload();
                } else {
                    state.onBeforeReload(ctx);
                }
            }
            ctx.saveSnapshotJson(std.heap.c_allocator, @field(state, snapshot_field)) catch {};
            if (@hasDecl(StateType, "deinit")) {
                state.deinit();
            } else {
                state.deinitResources();
            }
            std.heap.c_allocator.destroy(state);
            ctx.state = null;
        }

        fn app_on_reload(ctx: *PlatformContext) callconv(.c) void {
            if (ctx.state == null) {
                app_init(ctx);
            }
            if (ctx.state) |ptr| {
                const state: *StateType = @ptrCast(@alignCast(ptr));
                if (ctx.loadSnapshotJson(SnapshotType, std.heap.c_allocator)) |restored| {
                    @field(state, snapshot_field) = restored;
                }
                if (@hasDecl(StateType, "onAfterReload")) {
                    state.onAfterReload();
                }
            }
            ctx.force_full_redraw = true;
        }

        fn app_deinit(ctx: *PlatformContext) callconv(.c) void {
            const ptr = ctx.state orelse return;
            const state: *StateType = @ptrCast(@alignCast(ptr));
            if (@hasDecl(StateType, "deinit")) {
                state.deinit();
            } else {
                state.deinitResources();
            }
            std.heap.c_allocator.destroy(state);
            ctx.state = null;
        }

        fn app_tick(ctx: *PlatformContext) callconv(.c) bool {
            const state_ptr = ctx.state orelse return false;
            const state: *StateType = @ptrCast(@alignCast(state_ptr));
            return runTwoPhaseFrame(
                &state.ui_ctx,
                ctx,
                &state.frame_arena,
                @field(state, snapshot_field).show_dirty_overlay,
                state,
                buildFn,
            );
        }
    };

    @export(&Hooks.app_init, .{ .name = "app_init", .linkage = .strong });
    @export(&Hooks.app_before_reload, .{ .name = "app_before_reload", .linkage = .strong });
    @export(&Hooks.app_on_reload, .{ .name = "app_on_reload", .linkage = .strong });
    @export(&Hooks.app_deinit, .{ .name = "app_deinit", .linkage = .strong });
    @export(&Hooks.app_tick, .{ .name = "app_tick", .linkage = .strong });
}

test "app_runner: runTwoPhaseFrame early-exit 0% idle GPU optimization and disjoint scissor damage" {
    const surface = try skia.Surface.initRasterN32Premul(480, 320);
    defer surface.deinit();

    var store = platform.StateStore.init(std.testing.allocator);
    defer store.deinit();
    var snap = platform.SnapshotBuffer.init(std.testing.allocator);
    defer snap.deinit();
    var pctx = PlatformContext{ .width = 480.0, .height = 320.0 };
    pctx.bindHostStores(&store, &snap);
    pctx.canvas = surface.canvas().ptr;

    var fonts = FontSet.init(&pctx, .{});
    defer fonts.deinit();

    var frame_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer frame_arena.deinit();

    var uic = fonts.initContext(frame_arena.allocator(), &pctx);
    defer uic.deinit();

    const StatefulApp = struct {
        uic: *Context,
        input_passes: usize = 0,
        paint_passes: usize = 0,
        clicks: usize = 0,

        fn build(self: *@This(), _: *PlatformContext) void {
            if (self.uic.pass == .input) {
                self.input_passes += 1;
            } else {
                self.paint_passes += 1;
            }
            var col = self.uic.column(.{ .w = .pixels(200), .h = .pixels(100), .padding = root.Padding.all(8) });
            defer col.end();
            if (self.uic.btn("Click Me##runner_btn", .{ .w = .pixels(120), .h = 32 })) {
                self.clicks += 1;
            }
        }
    };

    var app = StatefulApp{ .uic = &uic };

    // Frame 1: force_full_redraw = true -> runs BOTH .input and .paint and returns true
    pctx.force_full_redraw = true;
    const painted_1 = runTwoPhaseFrame(&uic, &pctx, &frame_arena, false, &app, StatefulApp.build);
    try std.testing.expect(painted_1);
    try std.testing.expectEqual(@as(usize, 1), app.input_passes);
    try std.testing.expectEqual(@as(usize, 1), app.paint_passes);

    // Frame 2: Idle (no mouse move, no click, force_full_redraw = false) -> early-exits after .input (0% GPU!)
    const painted_2 = runTwoPhaseFrame(&uic, &pctx, &frame_arena, false, &app, StatefulApp.build);
    try std.testing.expect(!painted_2);
    try std.testing.expectEqual(@as(usize, 2), app.input_passes);
    try std.testing.expectEqual(@as(usize, 1), app.paint_passes);

    // Frame 3: Click inside button at (30, 20) -> marks button rect dirty, runs .paint, increments clicks
    pctx.mouse_x = 30.0;
    pctx.mouse_y = 20.0;
    pctx.mouse_down = true;
    pctx.mouse_pressed = true;
    pctx.mouse_released = true;
    const painted_3 = runTwoPhaseFrame(&uic, &pctx, &frame_arena, true, &app, StatefulApp.build);
    try std.testing.expect(painted_3);
    try std.testing.expectEqual(@as(usize, 3), app.input_passes);
    try std.testing.expectEqual(@as(usize, 2), app.paint_passes);
    try std.testing.expectEqual(@as(usize, 1), app.clicks);
}
