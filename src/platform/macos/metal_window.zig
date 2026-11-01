//! Native macOS Cocoa + Metal GPU Window Host with live `.dylib` Hot-Reloading.
//! Features a full-bleed transparent unified dark titlebar, 0% idle CPU/GPU sleep,
//! and partial scissor updates on a persistent GPU backbuffer.

const std = @import("std");
const skia = @import("skia");
const app_api = @import("../app_api.zig");
const state_store = @import("../state_store.zig");
const HotDylib = @import("../hot_dylib.zig").HotDylib;
const objc = @import("objc.zig");

export const embedded_info_plist linksection("__TEXT,__info_plist") =
    \\<?xml version="1.0" encoding="UTF-8"?>
    \\<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    \\<plist version="1.0">
    \\<dict>
    \\    <key>CFBundleIdentifier</key>
    \\    <string>com.lightning.editor</string>
    \\    <key>CFBundleName</key>
    \\    <string>Lightning</string>
    \\    <key>CFBundleDisplayName</key>
    \\    <string>Lightning</string>
    \\    <key>CFBundleIconFile</key>
    \\    <string>Lightning.icns</string>
    \\    <key>NSHighResolutionCapable</key>
    \\    <true/>
    \\    <key>NSPrefersDisplaySafeAreaCompatibilityMode</key>
    \\    <false/>
    \\</dict>
    \\</plist>
.*;

pub const Config = struct {
    title: [*:0]const u8 = "Lightning",
    width: f64 = 1080,
    height: f64 = 700,
    dylib_path: [*:0]const u8 = "zig-out/lib/libeditor_app.dylib",
    max_frames: ?usize = null,
    bench: bool = false,
    metrics_json_path: ?[]const u8 = null,
    trace_path: ?[]const u8 = null,
    scenario: ?[]const u8 = null,
    screenshot_path: ?[]const u8 = null,
};

pub fn run(config: Config) !void {
    const pool = objc.objc_autoreleasePoolPush();
    defer objc.objc_autoreleasePoolPop(pool);

    // 1. Initialize NSApplication & NSWindow with Full-Bleed Unified Titlebar
    const NSApplication = objc.objc_getClass("NSApplication");
    const app = objc.msgSend0(NSApplication, objc.id, "sharedApplication");
    _ = objc.msgSend1(app, bool, "setActivationPolicy:", @as(isize, 0));

    const NSWindow = createWindowClass();
    const win_alloc = objc.msgSend0(NSWindow, objc.id, "alloc");
    const initial_rect = objc.NSRect{
        .origin = .{ .x = 100, .y = 100 },
        .size = .{ .width = config.width, .height = config.height },
    };
    const style_mask = objc.NSWindowStyleMaskTitled |
        objc.NSWindowStyleMaskClosable |
        objc.NSWindowStyleMaskMiniaturizable |
        objc.NSWindowStyleMaskResizable |
        objc.NSWindowStyleMaskFullSizeContentView;

    const window = objc.msgSend4(
        win_alloc,
        objc.id,
        "initWithContentRect:styleMask:backing:defer:",
        initial_rect,
        style_mask,
        @as(usize, 2), // NSBackingStoreBuffered
        false,
    );

    // Force Dark Aqua appearance and seamless transparent unified titlebar
    const NSAppearance = objc.objc_getClass("NSAppearance");
    const dark_aqua = objc.msgSend1(NSAppearance, objc.id, "appearanceNamed:", objc.nsString("NSAppearanceNameDarkAqua"));
    if (dark_aqua != null) {
        _ = objc.msgSend1(window, void, "setAppearance:", dark_aqua);
    }

    const NSColor = objc.objc_getClass("NSColor");
    const win_bg = objc.msgSend4(
        NSColor,
        objc.id,
        "colorWithSRGBRed:green:blue:alpha:",
        @as(objc.CGFloat, 11.0 / 255.0),
        @as(objc.CGFloat, 15.0 / 255.0),
        @as(objc.CGFloat, 25.0 / 255.0),
        @as(objc.CGFloat, 1.0),
    );
    _ = objc.msgSend1(window, void, "setBackgroundColor:", win_bg);
    _ = objc.msgSend1(window, void, "setTitle:", objc.nsString(config.title));
    _ = objc.msgSend1(window, void, "setTitlebarAppearsTransparent:", true);
    _ = objc.msgSend1(window, void, "setTitleVisibility:", @as(isize, 1)); // NSWindowTitleHidden = 1
    _ = objc.msgSend1(window, void, "setMovableByWindowBackground:", false);
    _ = objc.msgSend1(window, void, "setCollectionBehavior:", objc.NSWindowCollectionBehaviorFullScreenPrimary);

    _ = objc.msgSend0(window, void, "center");
    _ = objc.msgSend1(window, void, "setReleasedWhenClosed:", false);
    _ = objc.msgSend1(window, void, "setAcceptsMouseMovedEvents:", true);

    // 2. Initialize Metal Device, Queue, CAMetalLayer, and NSTextInputClient Content View
    const mtl_device = objc.MTLCreateSystemDefaultDevice() orelse return error.MetalNotSupported;
    const mtl_queue = objc.msgSend0(mtl_device, objc.id, "newCommandQueue") orelse return error.MetalNotSupported;

    const CAMetalLayer = objc.objc_getClass("CAMetalLayer");
    const metal_layer = objc.msgSend0(CAMetalLayer, objc.id, "layer") orelse return error.MetalNotSupported;
    _ = objc.msgSend1(metal_layer, void, "setDevice:", mtl_device);
    _ = objc.msgSend1(metal_layer, void, "setPixelFormat:", @as(usize, 80)); // BGRA8Unorm
    _ = objc.msgSend1(metal_layer, void, "setFramebufferOnly:", false);
    _ = objc.msgSend1(metal_layer, void, "setDisplaySyncEnabled:", !config.bench);
    _ = objc.msgSend1(metal_layer, void, "setMaximumDrawableCount:", @as(usize, 2)); // Double-buffered swapchain (saves ~12MB IOSurface)
    _ = objc.msgSend1(metal_layer, void, "setAllowsNextDrawableTimeout:", true);

    const ContentViewClass = createContentViewClass();
    const cv_alloc = objc.msgSend0(ContentViewClass, objc.id, "alloc");
    const content_view = objc.msgSend1(cv_alloc, objc.id, "initWithFrame:", initial_rect);
    _ = objc.msgSend1(window, void, "setContentView:", content_view);
    _ = objc.msgSend1(content_view, void, "setWantsLayer:", true);
    _ = objc.msgSend1(content_view, void, "setLayer:", metal_layer);
    // Ensure CAMetalLayer automatically resizes during smooth macOS fullscreen & window resize animations
    _ = objc.msgSend1(content_view, void, "setLayerContentsRedrawPolicy:", @as(isize, 1)); // NSViewLayerContentsRedrawDuringViewResize
    _ = objc.msgSend1(metal_layer, void, "setAutoresizingMask:", @as(c_uint, (1 << 1) | (1 << 4))); // kCALayerWidthSizable | kCALayerHeightSizable

    const delegate_obj = createWindowResizeDelegate();
    if (delegate_obj != null) {
        _ = objc.msgSend1(window, void, "setDelegate:", delegate_obj);
        setupMainMenu(app, delegate_obj, config.title);
    }

    _ = objc.msgSend1(window, bool, "makeFirstResponder:", content_view);
    _ = objc.msgSend1(window, void, "makeKeyAndOrderFront:", @as(objc.id, null));
    _ = objc.msgSend1(app, void, "activateIgnoringOtherApps:", true);
    _ = objc.msgSend0(app, void, "finishLaunching");
    if (objc.msgSend0(content_view, objc.id, "inputContext")) |input_ctx| {
        _ = objc.msgSend0(input_ctx, void, "activate");
    }

    // 3. Create Skia GPU DirectContext & FontMgr owned by Host
    const gr_context = try skia.DirectContext.initMetal(mtl_device, mtl_queue);
    defer gr_context.deinit();

    // Right-size Skia's GPU resource cache limit to 32 MB for Retina surfaces, text blobs, and path masks
    gr_context.setResourceCacheLimit(32 * 1024 * 1024);

    const font_mgr = try skia.FontMgr.initDefault();
    defer font_mgr.deinit();

    const debug_paint = try skia.Paint.init();
    defer debug_paint.deinit();
    debug_paint.setAntiAlias(true);
    debug_paint.setStyle(.stroke);
    debug_paint.setStrokeWidth(1.5);
    debug_paint.setColor(skia.Color.argb(220, 16, 185, 129));

    // Host-owned persistent KV store (for React-style `useState`) & JSON snapshot buffer
    var host_store = state_store.StateStore.init(std.heap.c_allocator);
    defer host_store.deinit();

    var host_snapshot = state_store.SnapshotBuffer.init(std.heap.c_allocator);
    defer host_snapshot.deinit();

    var ctx = app_api.PlatformContext{
        .gr_context = gr_context.ptr,
        .font_mgr = font_mgr.ptr,
        .host_get_clipboard = &macGetClipboardImpl,
        .host_set_clipboard = &macSetClipboardImpl,
        .host_pick_folder = &macPickFolderImpl,
        .host_pick_file = &macPickFileImpl,
        .host_save_file = &macSaveFileImpl,
    };
    ctx.bindHostStores(&host_store, &host_snapshot);
    var prev_cursor_shape: app_api.CursorShape = .arrow;

    var hot_lib = HotDylib{
        .watch_path = config.dylib_path,
    };
    defer hot_lib.unload(&ctx);

    if (!hot_lib.checkAndReload(&ctx)) {
        std.debug.print("Failed to load {s}\n", .{hot_lib.watch_path});
        return error.DylibLoadFailed;
    }

    const profiler = @import("../profiler.zig");
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

    const scenario = if (config.scenario) |s| profiler.ScenarioKind.fromString(s) else .none;
    const effective_max_frames: ?usize = config.max_frames orelse if (config.bench) 300 else null;

    const NSDate = objc.objc_getClass("NSDate");
    const NSEvent = objc.objc_getClass("NSEvent");
    var prev_mouse_down = false;
    var prev_right_mouse_down = false;
    var titlebar_drag_armed = false;
    var redraw_frames_remaining: u8 = 2;
    var prev_w: f32 = 0;
    var prev_h: f32 = 0;
    var prev_scale: f32 = 0;
    var prev_fullscreen = false;
    var purged_for_idle = false;
    var last_frame_time: f64 = 0;
    var last_idle_poll_time: f64 = 0;
    var cached_mouse_screen_x: f64 = -99999.0;
    var cached_mouse_screen_y: f64 = -99999.0;
    var cached_cursor_over_our_window = true;
    const min_frame_interval: f64 = 1.0 / 60.0; // Pace animation & drag loop to 60Hz VSync

    // Persistent GPU render-target surface that retains rendered pixels across frames
    var backbuffer_surface: ?skia.Surface = null;
    defer if (backbuffer_surface) |s| s.deinit();

    // Register & attach an NSWindowDelegate (`windowDidResize:`) so the window re-layouts and
    // re-renders on the GPU continuously while inside AppKit's modal live-resize drag loop.
    var live_resize_hook = LiveResizeHook{
        .window = window,
        .content_view = content_view,
        .metal_layer = metal_layer,
        .mtl_queue = mtl_queue,
        .gr_context = gr_context,
        .debug_paint = debug_paint,
        .ctx = &ctx,
        .hot_lib = &hot_lib,
        .backbuffer_surface = &backbuffer_surface,
        .prev_w = &prev_w,
        .prev_h = &prev_h,
        .prev_scale = &prev_scale,
        .prev_fullscreen = &prev_fullscreen,
        .redraw_frames_remaining = &redraw_frames_remaining,
        .last_frame_time = &last_frame_time,
    };
    g_live_resize_hook = &live_resize_hook;
    defer g_live_resize_hook = null;

    // 4. Event-Driven Idle-Sleeping & Partial Scissor Render Loop
    while (true) {
        const t_frame_start = profiler.nowNs();
        const frame_pool = objc.objc_autoreleasePoolPush();
        defer objc.objc_autoreleasePoolPop(frame_pool);

        // When idle (no animation & no pending state transition frames), purge all unlocked
        // scratch GPU resources and sleep inside the OS event queue for up to 400ms (0% CPU / 0% GPU).
        const should_sleep = (scenario == .none) and !ctx.needs_continuous_redraw and (redraw_frames_remaining == 0) and (effective_max_frames == null);
        if (should_sleep and !purged_for_idle) {
            gr_context.purgeUnlockedResources(false);
            gr_context.freeGpuResources();
            purged_for_idle = true;
        } else if (!should_sleep) {
            purged_for_idle = false;
        }

        const now = objc.CFAbsoluteTimeGetCurrent();
        const elapsed = now - last_frame_time;
        var wait_until = if (should_sleep)
            objc.msgSend1(NSDate, objc.id, "dateWithTimeIntervalSinceNow:", @as(f64, 1.0))
        else if (elapsed < min_frame_interval and effective_max_frames == null and !config.bench)
            objc.msgSend1(NSDate, objc.id, "dateWithTimeIntervalSinceNow:", min_frame_interval - elapsed)
        else
            objc.msgSend0(NSDate, objc.id, "distantPast");

        var had_event = false;
        var saw_left_down = false;
        var saw_left_up = false;
        var saw_right_down = false;
        var saw_right_up = false;

        if (scenario != .none) {
            profiler.runScenarioTick(scenario, ctx.frame_count, &ctx);
            redraw_frames_remaining = 2;
        }

        const NSWindowClass = objc.objc_getClass("NSWindow");
        const my_win_num = objc.msgSend0(window, isize, "windowNumber");

        const t_events_start = profiler.nowNs();
        while (true) {
            const event = objc.msgSend4(
                app,
                objc.id,
                "nextEventMatchingMask:untilDate:inMode:dequeue:",
                @as(usize, std.math.maxInt(usize)),
                wait_until,
                objc.NSDefaultRunLoopMode,
                true,
            );
            if (event == null) break;

            // Subsequent iterations drain remaining queued events without blocking
            wait_until = objc.msgSend0(NSDate, objc.id, "distantPast");

            // Forward events belonging to auxiliary panels (e.g., macOS Emoji & Symbols picker)
            // directly to AppKit so they never trigger clicks, scrolling, or key actions in our window.
            const event_window = objc.msgSend0(event, objc.id, "window");
            if (event_window != null and event_window != window) {
                redraw_frames_remaining = @max(redraw_frames_remaining, 30);
                _ = objc.msgSend1(app, void, "sendEvent:", event);
                _ = objc.msgSend0(app, void, "updateWindows");
                continue;
            }

            const bounds_now = objc.msgSend0(content_view, objc.NSRect, "bounds");
            const cur_h: f32 = @floatCast(bounds_now.size.height);

            const event_type = objc.msgSend0(event, usize, "type");
            const screen_pt = objc.msgSend0(NSEvent, objc.NSPoint, "mouseLocation");
            if (screen_pt.x != cached_mouse_screen_x or
                screen_pt.y != cached_mouse_screen_y or
                event_type == objc.NSEventTypeLeftMouseDown or
                event_type == objc.NSEventTypeRightMouseDown)
            {
                cached_mouse_screen_x = screen_pt.x;
                cached_mouse_screen_y = screen_pt.y;
                const top_win_at_event = objc.msgSend2(
                    NSWindowClass,
                    isize,
                    "windowNumberAtPoint:belowWindowWithWindowNumber:",
                    screen_pt,
                    @as(isize, 0),
                );
                const now_over = (my_win_num <= 0) or (top_win_at_event == my_win_num);
                if (now_over or cached_cursor_over_our_window) {
                    had_event = true;
                }
                cached_cursor_over_our_window = now_over;
            } else if (cached_cursor_over_our_window or prev_mouse_down or prev_right_mouse_down or event_type == objc.NSEventTypeKeyDown or event_type == objc.NSEventTypeKeyUp or event_type == objc.NSEventTypeFlagsChanged) {
                had_event = true;
            }
            const event_over_our_window = cached_cursor_over_our_window;

            // Support dragging & double-click maximizing the window from our 36pt custom titlebar strip
            if (event_type == objc.NSEventTypeRightMouseDown) {
                if (event_window == window and event_over_our_window) {
                    saw_right_down = true;
                    prev_right_mouse_down = true;
                }
            } else if (event_type == objc.NSEventTypeRightMouseUp) {
                if (prev_right_mouse_down or saw_right_down) {
                    saw_right_up = true;
                }
                prev_right_mouse_down = false;
            } else if (event_type == objc.NSEventTypeLeftMouseDown) {
                titlebar_drag_armed = false;
                if (event_window == window and event_over_our_window) {
                    const cur_style = objc.msgSend0(window, usize, "styleMask");
                    const in_fullscreen = ((cur_style & objc.NSWindowStyleMaskFullScreen) != 0) or live_resize_hook.in_fullscreen_enter;
                    const loc = objc.msgSend0(event, objc.NSPoint, "locationInWindow");
                    const click_x: f32 = @floatCast(loc.x);
                    const click_y: f32 = cur_h - @as(f32, @floatCast(loc.y));
                    const cur_w: f32 = @floatCast(bounds_now.size.width);
                    if (!in_fullscreen) {
                        const pill_left = (cur_w - 300.0) * 0.5;
                        const pill_right = pill_left + 300.0;
                        const in_center_pill = (click_x >= pill_left and click_x <= pill_right and click_y >= 5.0 and click_y <= 31.0);
                        // Exclude the top (y < 6pt) and right (x >= cur_w - 8pt) resize borders so AppKit handles edge/corner resizing natively
                        if (click_y >= 6.0 and click_y <= 36.0 and click_x > 78.0 and click_x < cur_w - 8.0 and !in_center_pill) {
                            const click_count = objc.msgSend0(event, isize, "clickCount");
                            if (click_count >= 2) {
                                _ = objc.msgSend1(window, void, "zoom:", @as(objc.id, null));
                                continue;
                            }
                            titlebar_drag_armed = true;
                        }
                    }
                    if (click_x >= 0 and click_x <= cur_w and click_y >= 0 and click_y <= cur_h) {
                        saw_left_down = true;
                        prev_mouse_down = true;
                        const raw_clicks = objc.msgSend0(event, isize, "clickCount");
                        ctx.mouse_click_count = @intCast(std.math.clamp(raw_clicks, 1, 4));
                        const flags = objc.msgSend0(event, usize, "modifierFlags");
                        ctx.mouse_shift = (flags & objc.NSEventModifierFlagShift) != 0;
                    }
                }
            } else if (event_type == objc.NSEventTypeLeftMouseDragged) {
                if (titlebar_drag_armed) {
                    titlebar_drag_armed = false;
                    prev_mouse_down = false;
                    saw_left_down = false;
                    _ = objc.msgSend1(window, void, "performWindowDragWithEvent:", event);
                    continue;
                }
            } else if (event_type == objc.NSEventTypeLeftMouseUp) {
                titlebar_drag_armed = false;
                if (prev_mouse_down or saw_left_down) {
                    saw_left_up = true;
                }
                prev_mouse_down = false;
            } else if (event_type == objc.NSEventTypeScrollWheel) {
                if (event_window == window and event_over_our_window) {
                    const has_precise = objc.msgSend0(event, bool, "hasPreciseScrollingDeltas");
                    const raw_dx: f32 = @floatCast(objc.msgSend0(event, objc.CGFloat, "scrollingDeltaX"));
                    const raw_dy: f32 = @floatCast(objc.msgSend0(event, objc.CGFloat, "scrollingDeltaY"));
                    const flags = objc.msgSend0(event, usize, "modifierFlags");
                    ctx.mouse_shift = (flags & objc.NSEventModifierFlagShift) != 0;
                    const mult: f32 = if (has_precise) 1.0 else 14.0;
                    ctx.scroll_dx += raw_dx * mult;
                    ctx.scroll_dy += raw_dy * mult;
                }
            } else if (event_type == objc.NSEventTypeMagnify) {
                if (event_window == window and event_over_our_window) {
                    const raw_mag: f32 = @floatCast(objc.msgSend0(event, objc.CGFloat, "magnification"));
                    ctx.magnify_delta += raw_mag;
                }
            } else if (event_type == objc.NSEventTypeSmartMagnify) {
                if (event_window == window and event_over_our_window) {
                    ctx.magnify_delta += 0.35;
                }
            } else if (event_type == objc.NSEventTypeKeyDown) {
                if (handleMacKeyDown(&ctx, event)) {
                    continue;
                }
            }

            _ = objc.msgSend1(app, void, "sendEvent:", event);
            _ = objc.msgSend0(app, void, "updateWindows");
        }

        const t_events_end = profiler.nowNs();
        const events_ns = t_events_end - t_events_start;
        trace_collector.record("AppKit.Events", "event", t_events_start, t_events_end);

        if (!objc.msgSend0(window, bool, "isVisible")) break;
        if (effective_max_frames) |limit| {
            if (ctx.frame_count >= limit) break;
        }

        // Check for hot-reloaded dylib (every ~15 frames when animating, or on every 400ms idle wakeup)
        if (should_sleep or ctx.frame_count % 15 == 0) {
            if (hot_lib.checkAndReload(&ctx)) {
                ctx.force_full_redraw = true;
                redraw_frames_remaining = 2;
            }
        }

        const bounds = objc.msgSend0(content_view, objc.NSRect, "bounds");
        const scale = objc.msgSend0(window, objc.CGFloat, "backingScaleFactor");
        if (bounds.size.width <= 0 or bounds.size.height <= 0) continue;

        const cur_style_mask = objc.msgSend0(window, usize, "styleMask");
        const is_fullscreen = (((cur_style_mask & objc.NSWindowStyleMaskFullScreen) != 0) or live_resize_hook.in_fullscreen_enter) and !live_resize_hook.in_fullscreen_exit;
        if (is_fullscreen) {
            live_resize_hook.enforceFullScreenFrame();
        }
        if (is_fullscreen != prev_fullscreen) {
            prev_fullscreen = is_fullscreen;
            ctx.force_full_redraw = true;
            redraw_frames_remaining = 4;
        }

        ctx.width = @floatCast(bounds.size.width);
        ctx.height = @floatCast(bounds.size.height);
        ctx.dpi_scale = @floatCast(scale);
        ctx.is_fullscreen = is_fullscreen;

        const size_changed = (ctx.width != prev_w) or (ctx.height != prev_h) or (ctx.dpi_scale != prev_scale);
        if (size_changed or backbuffer_surface == null) {
            const phys_w: i32 = @intFromFloat(@round(bounds.size.width * scale));
            const phys_h: i32 = @intFromFloat(@round(bounds.size.height * scale));
            if (backbuffer_surface) |old_s| old_s.deinit();
            backbuffer_surface = try skia.Surface.initRenderTarget(
                gr_context,
                skia.ImageInfo.initBgra8888Premul(phys_w, phys_h),
                1,
            );
            _ = objc.msgSend1(metal_layer, void, "setFrame:", bounds);
            _ = objc.msgSend1(metal_layer, void, "setContentsScale:", scale);
            _ = objc.msgSend1(metal_layer, void, "setDrawableSize:", objc.NSSize{
                .width = bounds.size.width * scale,
                .height = bounds.size.height * scale,
            });
            ctx.force_full_redraw = true;
            redraw_frames_remaining = 4;
            prev_w = ctx.width;
            prev_h = ctx.height;
            prev_scale = ctx.dpi_scale;
        } else if (had_event or ctx.text_input_len > 0 or ctx.key_event_count > 0) {
            redraw_frames_remaining = @max(redraw_frames_remaining, 2);
        }

        if (redraw_frames_remaining > 0) {
            redraw_frames_remaining -= 1;
        }

        const has_user_input = had_event or
            saw_left_down or saw_left_up or
            saw_right_down or saw_right_up or
            ctx.text_input_len > 0 or
            ctx.key_event_count > 0 or
            ctx.scroll_dx != 0 or
            ctx.scroll_dy != 0 or
            ctx.magnify_delta != 0;

        // When sleeping with zero relevant user/window events, throttle background `Pass.input` polling
        // to at most once every 0.9s so background AppKit events or cursor movement on other windows cost 0% CPU.
        if (should_sleep and !has_user_input and !size_changed and !ctx.force_full_redraw and !ctx.needs_continuous_redraw and redraw_frames_remaining == 0) {
            if (now - last_idle_poll_time < 0.9) {
                continue;
            }
            last_idle_poll_time = now;
        } else {
            last_idle_poll_time = now;
        }

        // Update mouse position & button transitions
        const screen_mouse_loc = objc.msgSend0(NSEvent, objc.NSPoint, "mouseLocation");
        if (screen_mouse_loc.x != cached_mouse_screen_x or screen_mouse_loc.y != cached_mouse_screen_y) {
            cached_mouse_screen_x = screen_mouse_loc.x;
            cached_mouse_screen_y = screen_mouse_loc.y;
            const top_win_num = objc.msgSend2(
                NSWindowClass,
                isize,
                "windowNumberAtPoint:belowWindowWithWindowNumber:",
                screen_mouse_loc,
                @as(isize, 0),
            );
            cached_cursor_over_our_window = (my_win_num <= 0) or (top_win_num == my_win_num);
        }
        const cursor_over_our_window = cached_cursor_over_our_window;

        const pressed_mask = objc.msgSend0(NSEvent, usize, "pressedMouseButtons");
        if (prev_mouse_down and (pressed_mask & 1) == 0) {
            prev_mouse_down = false;
            saw_left_up = true;
        }
        if (prev_right_mouse_down and (pressed_mask & 2) == 0) {
            prev_right_mouse_down = false;
            saw_right_up = true;
        }

        ctx.mouse_down = prev_mouse_down or saw_left_down;
        ctx.mouse_pressed = saw_left_down;
        ctx.mouse_released = saw_left_up;

        ctx.right_mouse_down = prev_right_mouse_down or saw_right_down;
        ctx.right_mouse_pressed = saw_right_down;
        ctx.right_mouse_released = saw_right_up;

        if (cursor_over_our_window or ctx.mouse_down or ctx.right_mouse_down) {
            const mouse_loc = objc.msgSend0(window, objc.NSPoint, "mouseLocationOutsideOfEventStream");
            ctx.mouse_x = @floatCast(mouse_loc.x);
            ctx.mouse_y = ctx.height - @as(f32, @floatCast(mouse_loc.y));
        } else {
            ctx.mouse_x = -10000.0;
            ctx.mouse_y = -10000.0;
        }

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

        if (ctx.cursor_shape != prev_cursor_shape) {
            prev_cursor_shape = ctx.cursor_shape;
            applyMacCursorShape(ctx.cursor_shape);
        }

        back_canvas.restore();

        // If Pass 1 (.input) determined nothing visually changed (e.g. mouse moved over empty space),
        // skip acquiring a CAMetalDrawable and skip GPU submission completely!
        if (!did_paint and effective_max_frames == null) {
            last_frame_time = objc.CFAbsoluteTimeGetCurrent();
            continue;
        }

        // Blit the persistent GPU backbuffer onto the current CAMetalDrawable and present
        var drawable_handle: skia.c.gr_mtl_handle_t = null;
        const drawable_surface = skia.Surface.initMetalLayer(
            gr_context,
            metal_layer,
            1,
            .bgra_8888,
            &drawable_handle,
        ) catch continue;
        defer drawable_surface.deinit();

        const drawable_canvas = drawable_surface.canvas();
        backbuffer.draw(drawable_canvas, 0, 0, null);

        if (ctx.show_dirty_overlay) {
            _ = drawable_canvas.save();
            drawable_canvas.scale(ctx.dpi_scale, ctx.dpi_scale);
            drawable_canvas.drawRect(ctx.last_dirty_rect, debug_paint);
            drawable_canvas.restore();
        }

        const t_flush_start = profiler.nowNs();
        profiler.signpostStart(.gpu_flush, @intCast(ctx.frame_count));
        gr_context.flushAndSubmit(false);
        profiler.signpostEnd(.gpu_flush, @intCast(ctx.frame_count));
        const t_flush_end = profiler.nowNs();
        trace_collector.record("Skia.FlushAndSubmit", "gpu", t_flush_start, t_flush_end);
        last_frame_time = objc.CFAbsoluteTimeGetCurrent();

        // Periodically evict stale GPU staging/tessellation buffers older than 2s during continuous animation
        if (ctx.frame_count % 120 == 0) {
            gr_context.performDeferredCleanup(2000);
        }

        var t_present_start: u64 = 0;
        var t_present_end: u64 = 0;
        if (drawable_handle) |drawable_ptr| {
            t_present_start = profiler.nowNs();
            profiler.signpostStart(.metal_present, @intCast(ctx.frame_count));
            const drawable: objc.id = @constCast(drawable_ptr);
            const cmd_buf = objc.msgSend0(mtl_queue, objc.id, "commandBuffer");
            _ = objc.msgSend1(cmd_buf, void, "presentDrawable:", drawable);
            _ = objc.msgSend0(cmd_buf, void, "commit");
            profiler.signpostEnd(.metal_present, @intCast(ctx.frame_count));
            t_present_end = profiler.nowNs();
            trace_collector.record("Metal.Present", "gpu", t_present_start, t_present_end);
            objc.CFRelease(drawable_ptr);
        }

        const t_frame_end = profiler.nowNs();
        trace_collector.record("Frame", "frame", t_frame_start, t_frame_end);

        const gpu_usage = gr_context.getResourceCacheUsage();
        const total_win_area = @max(1.0, ctx.width * ctx.height);
        const dirty_area = skia.Rect.area(ctx.last_dirty_rect);
        metrics_collector.recordFrame(
            .{
                .total_ns = t_frame_end - t_frame_start,
                .events_ns = events_ns,
                .input_ns = @as(u64, ctx.phase_input_us) * 1000,
                .paint_ns = @as(u64, ctx.phase_paint_us) * 1000,
                .gpu_flush_ns = t_flush_end - t_flush_start,
                .metal_present_ns = if (t_present_end >= t_present_start) t_present_end - t_present_start else 0,
                .damage_pct = @floatCast((dirty_area / total_win_area) * 100.0),
            },
            gpu_usage.bytes,
            gpu_usage.resources,
            &ctx,
        );

        ctx.frame_count += 1;
    }
}

fn handleMacKeyDown(ctx: *app_api.PlatformContext, event: objc.id) bool {
    const flags = objc.msgSend0(event, usize, "modifierFlags");
    const shift = (flags & objc.NSEventModifierFlagShift) != 0;
    const ctrl = (flags & objc.NSEventModifierFlagControl) != 0;
    const alt = (flags & objc.NSEventModifierFlagOption) != 0;
    const cmd = (flags & objc.NSEventModifierFlagCommand) != 0;

    const hw_keycode = objc.msgSend0(event, u16, "keyCode");

    // Allow Cmd+Q (12) to pass through to AppKit for standard application termination
    if (cmd and hw_keycode == 12) {
        return false;
    }

    // Standard macOS Fullscreen toggle shortcut: Ctrl+Cmd+F (keyCode 3)
    if (cmd and ctrl and hw_keycode == 3) {
        if (g_live_resize_hook) |hook| {
            _ = objc.msgSend1(hook.window, void, "toggleFullScreen:", @as(objc.id, null));
        }
        return true;
    }

    const mapped_key: app_api.KeyCode = switch (hw_keycode) {
        123 => .left,
        124 => .right,
        125 => .down,
        126 => .up,
        115 => .home,
        119 => .end,
        116 => .page_up,
        121 => .page_down,
        51 => .backspace,
        117 => .delete_forward,
        36, 76 => .enter,
        48 => .tab,
        53 => .escape,
        0 => if (cmd or ctrl) .key_a else .none,
        1 => if (cmd or ctrl) .key_s else .none,
        2 => if (cmd or ctrl) .key_d else .none,
        3 => if (cmd or ctrl) .key_f else .none,
        4 => if (cmd or ctrl) .key_h else .none,
        5 => if (cmd or ctrl) .key_g else .none,
        6 => if (cmd or ctrl) .key_z else .none,
        7 => if (cmd or ctrl) .key_x else .none,
        8 => if (cmd or ctrl) .key_c else .none,
        9 => if (cmd or ctrl) .key_v else .none,
        11 => if (cmd or ctrl) .key_b else .none,
        12 => if (cmd or ctrl) .key_q else .none,
        13 => if (cmd or ctrl) .key_w else .none,
        14 => if (cmd or ctrl) .key_e else .none,
        15 => if (cmd or ctrl) .key_r else .none,
        16 => if (cmd or ctrl) .key_y else .none,
        17 => if (cmd or ctrl) .key_t else .none,
        18 => if (cmd or ctrl) .key_1 else .none,
        19 => if (cmd or ctrl) .key_2 else .none,
        22 => if (cmd or ctrl) .key_6 else .none,
        27 => if (cmd or ctrl) .key_minus else .none,
        30 => if (cmd or ctrl) .key_rbracket else .none,
        31 => if (cmd or ctrl) .key_o else .none,
        32 => if (cmd or ctrl) .key_u else .none,
        33 => if (cmd or ctrl) .key_lbracket else .none,
        34 => if (cmd or ctrl) .key_i else .none,
        35 => if (cmd or ctrl) .key_p else .none,
        37 => if (cmd or ctrl) .key_l else .none,
        38 => if (cmd or ctrl) .key_j else .none,
        40 => if (cmd or ctrl) .key_k else .none,
        42 => if (cmd or ctrl) .key_backslash else .none,
        44 => if (cmd or ctrl) .key_slash else .none,
        45 => if (cmd or ctrl) .key_n else .none,
        46 => if (cmd or ctrl) .key_m else .none,
        49 => if (cmd or ctrl) .key_space else .none,
        96 => .f5,
        101 => .f9,
        109 => .f10,
        103 => .f11,
        else => .none,
    };

    if (mapped_key != .none) {
        ctx.pushKeyEvent(.{
            .key = mapped_key,
            .shift = shift,
            .cmd = cmd,
            .alt = alt,
            .ctrl = ctrl,
        });
        return true;
    }

    if (!cmd and !ctrl) {
        const chars_ns = objc.msgSend0(event, objc.id, "characters");
        if (chars_ns != null) {
            if (objc.msgSend0(chars_ns, ?[*:0]const u8, "UTF8String")) |c_str| {
                const slice = std.mem.span(c_str);
                // Filter out macOS Private Use Area function keys (0xEF 0x9C ...)
                if (slice.len >= 3 and slice[0] == 0xEF and slice[1] == 0x9C) {
                    return true;
                }
                ctx.pushTextInput(slice);
                return true;
            }
        }
    }

    return true;
}

fn applyMacCursorShape(shape: app_api.CursorShape) void {
    const NSCursor = objc.objc_getClass("NSCursor");
    if (NSCursor == null) return;
    const cursor_obj: objc.id = switch (shape) {
        .arrow => objc.msgSend0(NSCursor, objc.id, "arrowCursor"),
        .pointing_hand => objc.msgSend0(NSCursor, objc.id, "pointingHandCursor"),
        .ibeam => objc.msgSend0(NSCursor, objc.id, "IBeamCursor"),
        .resize_ew => objc.msgSend0(NSCursor, objc.id, "resizeLeftRightCursor"),
        .resize_ns => objc.msgSend0(NSCursor, objc.id, "resizeUpDownCursor"),
        .crosshair => objc.msgSend0(NSCursor, objc.id, "crosshairCursor"),
        .grab => objc.msgSend0(NSCursor, objc.id, "openHandCursor"),
        .grabbing => objc.msgSend0(NSCursor, objc.id, "closedHandCursor"),
        .not_allowed => objc.msgSend0(NSCursor, objc.id, "operationNotAllowedCursor"),
    };
    if (cursor_obj != null) {
        _ = objc.msgSend0(cursor_obj, void, "set");
    }
}

fn macGetClipboardImpl(buf_ptr: ?[*]u8, buf_cap: usize) callconv(.c) usize {
    const NSPasteboard = objc.objc_getClass("NSPasteboard");
    if (NSPasteboard == null) return 0;
    const pb = objc.msgSend0(NSPasteboard, objc.id, "generalPasteboard");
    if (pb == null) return 0;
    const ns_str = objc.msgSend1(pb, objc.id, "stringForType:", objc.nsString("public.utf8-plain-text"));
    if (ns_str == null) return 0;
    const c_str = objc.msgSend0(ns_str, ?[*:0]const u8, "UTF8String") orelse return 0;
    const slice = std.mem.span(c_str);
    if (buf_ptr) |bp| {
        if (buf_cap > 0) {
            const n = @min(slice.len, buf_cap);
            @memcpy(bp[0..n], slice[0..n]);
        }
    }
    return slice.len;
}

fn macSetClipboardImpl(ptr: [*]const u8, len: usize) callconv(.c) void {
    const NSPasteboard = objc.objc_getClass("NSPasteboard");
    if (NSPasteboard == null) return;
    const pb = objc.msgSend0(NSPasteboard, objc.id, "generalPasteboard");
    if (pb == null) return;
    _ = objc.msgSend0(pb, isize, "clearContents");

    const NSString = objc.objc_getClass("NSString");
    const str_alloc = objc.msgSend0(NSString, objc.id, "alloc");
    const ns_str = objc.msgSend3(
        str_alloc,
        objc.id,
        "initWithBytes:length:encoding:",
        ptr,
        len,
        @as(usize, 4), // NSUTF8StringEncoding = 4
    );
    if (ns_str != null) {
        _ = objc.msgSend2(pb, bool, "setString:forType:", ns_str, objc.nsString("public.utf8-plain-text"));
    }
}

extern "c" fn getcwd(buf: [*]u8, size: usize) ?[*:0]u8;

fn macPickFolderImpl(buf_ptr: [*]u8, buf_cap: usize) callconv(.c) usize {
    if (buf_cap == 0) return 0;
    const pool = objc.objc_autoreleasePoolPush();
    defer objc.objc_autoreleasePoolPop(pool);

    // 1. Drain any pending menu-tracking / key-up events in NSDefaultRunLoopMode before launching
    // the XPC-backed NSOpenPanel modal session so Carbon HIRunLoop does not stall.
    const NSApplication = objc.objc_getClass("NSApplication");
    const NSDate = objc.objc_getClass("NSDate");
    const default_mode = objc.nsString("kCFRunLoopDefaultMode");
    if (NSApplication != null and NSDate != null) {
        const app = objc.msgSend0(NSApplication, objc.id, "sharedApplication");
        const distant_past = objc.msgSend0(NSDate, objc.id, "distantPast");
        if (app != null) {
            var drain_i: usize = 0;
            while (drain_i < 16) : (drain_i += 1) {
                const ev = objc.msgSend4(
                    app,
                    objc.id,
                    "nextEventMatchingMask:untilDate:inMode:dequeue:",
                    @as(usize, std.math.maxInt(usize)),
                    distant_past,
                    default_mode,
                    true,
                );
                if (ev == null) break;
                _ = objc.msgSend1(app, void, "sendEvent:", ev);
            }
        }
    }

    // 2. Determine a fast local starting directory (prefer parent of current workspace, e.g. ~/Projects,
    // avoiding iCloud-backed ~/Documents or ~/Desktop where evicted cloud files can stall Finder/OpenPanel).
    var cwd_buf: [512]u8 = undefined;
    var start_dir_z_buf: [512:0]u8 = @splat(0);
    var has_start_dir = false;
    if (getcwd(&cwd_buf, cwd_buf.len)) |cwd_z| {
        const cwd_slice: []const u8 = std.mem.sliceTo(cwd_z, 0);
        if (cwd_slice.len > 0 and cwd_slice.len < 500) {
            var chosen: []const u8 = cwd_slice;
            if (std.fs.path.dirname(cwd_slice)) |parent| {
                if (parent.len > 1 and
                    !std.mem.endsWith(u8, parent, "/Documents") and
                    !std.mem.endsWith(u8, parent, "/Desktop"))
                {
                    chosen = parent;
                }
            }
            if (std.mem.endsWith(u8, chosen, "/Documents") or std.mem.endsWith(u8, chosen, "/Desktop")) {
                if (std.fs.path.dirname(chosen)) |up| {
                    if (up.len > 1) chosen = up;
                }
            }
            @memcpy(start_dir_z_buf[0..chosen.len], chosen);
            start_dir_z_buf[chosen.len] = 0;
            has_start_dir = true;
        }
    }

    // Clear any stale security-scoped bookmark in NSOSPLastRootDirectory before `[NSOpenPanel openPanel]`
    // initializes openAndSavePanelService (which otherwise resolves the bookmark during `_initBridgeAndStuff`).
    if (objc.objc_getClass("NSUserDefaults")) |NSUserDefaults| {
        const defaults = objc.msgSend0(NSUserDefaults, objc.id, "standardUserDefaults");
        if (defaults != null) {
            _ = objc.msgSend1(defaults, void, "removeObjectForKey:", objc.nsString("NSOSPLastRootDirectory"));
            if (has_start_dir) {
                const start_ns = objc.nsString(&start_dir_z_buf);
                _ = objc.msgSend2(defaults, void, "setObject:forKey:", start_ns, objc.nsString("NSNavLastRootDirectory"));
            }
        }
    }

    const NSOpenPanel = objc.objc_getClass("NSOpenPanel");
    if (NSOpenPanel == null) return 0;
    const panel = objc.msgSend0(NSOpenPanel, objc.id, "openPanel");
    if (panel == null) return 0;

    // Allow choosing both directories AND files so files inside folders are never greyed out,
    // and selecting either a folder or a file inside a project opens that workspace/file cleanly.
    _ = objc.msgSend1(panel, void, "setCanChooseFiles:", true);
    _ = objc.msgSend1(panel, void, "setCanChooseDirectories:", true);
    _ = objc.msgSend1(panel, void, "setAllowsMultipleSelection:", false);
    _ = objc.msgSend1(panel, void, "setCanCreateDirectories:", true);
    _ = objc.msgSend1(panel, void, "setResolvesAliases:", true);
    _ = objc.msgSend1(panel, void, "setTitle:", objc.nsString("Open Workspace Folder or File"));
    _ = objc.msgSend1(panel, void, "setPrompt:", objc.nsString("Open"));

    if (has_start_dir) {
        if (objc.objc_getClass("NSURL")) |NSURL| {
            const dir_url = objc.msgSend2(
                NSURL,
                objc.id,
                "fileURLWithPath:isDirectory:",
                objc.nsString(&start_dir_z_buf),
                true,
            );
            if (dir_url != null) {
                _ = objc.msgSend1(panel, void, "setDirectoryURL:", dir_url);
            }
        }
    }

    const prev_in_cb = if (g_live_resize_hook) |hook| blk: {
        const prev = hook.in_callback;
        hook.in_callback = true;
        hook.ctx.clearFrameInput();
        hook.ctx.mouse_down = false;
        break :blk prev;
    } else false;

    const resp = objc.msgSend0(panel, isize, "runModal");
    _ = objc.msgSend1(panel, void, "orderOut:", @as(objc.id, null));

    if (g_live_resize_hook) |hook| {
        hook.in_callback = prev_in_cb;
        _ = objc.msgSend1(hook.window, void, "makeKeyAndOrderFront:", @as(objc.id, null));
        hook.ctx.clearFrameInput();
        hook.ctx.mouse_down = false;
        hook.ctx.mouse_pressed = false;
        hook.ctx.mouse_released = false;
        hook.ctx.force_full_redraw = true;
        hook.redraw_frames_remaining.* = 4;
    }
    if (resp != 1) return 0; // NSModalResponseOK == 1

    const url = objc.msgSend0(panel, objc.id, "URL");
    if (url == null) return 0;
    const path_ns = objc.msgSend0(url, objc.id, "path");
    if (path_ns == null) return 0;
    const c_str = objc.msgSend0(path_ns, ?[*:0]const u8, "UTF8String") orelse return 0;
    const slice = std.mem.span(c_str);
    const n = @min(slice.len, buf_cap);
    @memcpy(buf_ptr[0..n], slice[0..n]);
    return n;
}

fn prepareMacModalPanelStartDir(start_dir_z_buf: *[512:0]u8) bool {
    const NSApplication = objc.objc_getClass("NSApplication");
    const NSDate = objc.objc_getClass("NSDate");
    const default_mode = objc.nsString("kCFRunLoopDefaultMode");
    if (NSApplication != null and NSDate != null) {
        const app = objc.msgSend0(NSApplication, objc.id, "sharedApplication");
        const distant_past = objc.msgSend0(NSDate, objc.id, "distantPast");
        if (app != null) {
            var drain_i: usize = 0;
            while (drain_i < 16) : (drain_i += 1) {
                const ev = objc.msgSend4(
                    app,
                    objc.id,
                    "nextEventMatchingMask:untilDate:inMode:dequeue:",
                    @as(usize, std.math.maxInt(usize)),
                    distant_past,
                    default_mode,
                    true,
                );
                if (ev == null) break;
                _ = objc.msgSend1(app, void, "sendEvent:", ev);
            }
        }
    }

    var cwd_buf: [512]u8 = undefined;
    var has_start_dir = false;
    if (getcwd(&cwd_buf, cwd_buf.len)) |cwd_z| {
        const cwd_slice: []const u8 = std.mem.sliceTo(cwd_z, 0);
        if (cwd_slice.len > 0 and cwd_slice.len < 500) {
            var chosen: []const u8 = cwd_slice;
            if (std.mem.endsWith(u8, chosen, "/Documents") or std.mem.endsWith(u8, chosen, "/Desktop")) {
                if (std.fs.path.dirname(chosen)) |up| {
                    if (up.len > 1) chosen = up;
                }
            }
            @memcpy(start_dir_z_buf[0..chosen.len], chosen);
            start_dir_z_buf[chosen.len] = 0;
            has_start_dir = true;
        }
    }

    if (objc.objc_getClass("NSUserDefaults")) |NSUserDefaults| {
        const defaults = objc.msgSend0(NSUserDefaults, objc.id, "standardUserDefaults");
        if (defaults != null) {
            _ = objc.msgSend1(defaults, void, "removeObjectForKey:", objc.nsString("NSOSPLastRootDirectory"));
            if (has_start_dir) {
                const start_ns = objc.nsString(start_dir_z_buf);
                _ = objc.msgSend2(defaults, void, "setObject:forKey:", start_ns, objc.nsString("NSNavLastRootDirectory"));
            }
        }
    }
    return has_start_dir;
}

fn runMacModalPanelAndCopyUrlPath(
    panel: objc.id,
    has_start_dir: bool,
    start_dir_z_buf: *const [512:0]u8,
    buf_ptr: [*]u8,
    buf_cap: usize,
) usize {
    if (has_start_dir) {
        if (objc.objc_getClass("NSURL")) |NSURL| {
            const dir_url = objc.msgSend2(
                NSURL,
                objc.id,
                "fileURLWithPath:isDirectory:",
                objc.nsString(start_dir_z_buf),
                true,
            );
            if (dir_url != null) {
                _ = objc.msgSend1(panel, void, "setDirectoryURL:", dir_url);
            }
        }
    }

    const prev_in_cb = if (g_live_resize_hook) |hook| blk: {
        const prev = hook.in_callback;
        hook.in_callback = true;
        hook.ctx.clearFrameInput();
        hook.ctx.mouse_down = false;
        break :blk prev;
    } else false;

    const resp = objc.msgSend0(panel, isize, "runModal");
    _ = objc.msgSend1(panel, void, "orderOut:", @as(objc.id, null));

    if (g_live_resize_hook) |hook| {
        hook.in_callback = prev_in_cb;
        _ = objc.msgSend1(hook.window, void, "makeKeyAndOrderFront:", @as(objc.id, null));
        hook.ctx.clearFrameInput();
        hook.ctx.mouse_down = false;
        hook.ctx.mouse_pressed = false;
        hook.ctx.mouse_released = false;
        hook.ctx.force_full_redraw = true;
        hook.redraw_frames_remaining.* = 4;
    }
    if (resp != 1) return 0; // NSModalResponseOK == 1

    const url = objc.msgSend0(panel, objc.id, "URL");
    if (url == null) return 0;
    const path_ns = objc.msgSend0(url, objc.id, "path");
    if (path_ns == null) return 0;
    const c_str = objc.msgSend0(path_ns, ?[*:0]const u8, "UTF8String") orelse return 0;
    const slice = std.mem.span(c_str);
    const n = @min(slice.len, buf_cap);
    @memcpy(buf_ptr[0..n], slice[0..n]);
    return n;
}

fn macPickFileImpl(buf_ptr: [*]u8, buf_cap: usize) callconv(.c) usize {
    if (buf_cap == 0) return 0;
    const pool = objc.objc_autoreleasePoolPush();
    defer objc.objc_autoreleasePoolPop(pool);

    var start_dir_z_buf: [512:0]u8 = @splat(0);
    const has_start_dir = prepareMacModalPanelStartDir(&start_dir_z_buf);

    const NSOpenPanel = objc.objc_getClass("NSOpenPanel");
    if (NSOpenPanel == null) return 0;
    const panel = objc.msgSend0(NSOpenPanel, objc.id, "openPanel");
    if (panel == null) return 0;

    _ = objc.msgSend1(panel, void, "setCanChooseFiles:", true);
    _ = objc.msgSend1(panel, void, "setCanChooseDirectories:", false);
    _ = objc.msgSend1(panel, void, "setAllowsMultipleSelection:", false);
    _ = objc.msgSend1(panel, void, "setCanCreateDirectories:", false);
    _ = objc.msgSend1(panel, void, "setResolvesAliases:", true);
    _ = objc.msgSend1(panel, void, "setTitle:", objc.nsString("Open File"));
    _ = objc.msgSend1(panel, void, "setPrompt:", objc.nsString("Open"));

    return runMacModalPanelAndCopyUrlPath(panel, has_start_dir, &start_dir_z_buf, buf_ptr, buf_cap);
}

fn macSaveFileImpl(buf_ptr: [*]u8, buf_cap: usize) callconv(.c) usize {
    if (buf_cap == 0) return 0;
    const pool = objc.objc_autoreleasePoolPush();
    defer objc.objc_autoreleasePoolPop(pool);

    var start_dir_z_buf: [512:0]u8 = @splat(0);
    const has_start_dir = prepareMacModalPanelStartDir(&start_dir_z_buf);

    const NSSavePanel = objc.objc_getClass("NSSavePanel");
    if (NSSavePanel == null) return 0;
    const panel = objc.msgSend0(NSSavePanel, objc.id, "savePanel");
    if (panel == null) return 0;

    _ = objc.msgSend1(panel, void, "setCanCreateDirectories:", true);
    _ = objc.msgSend1(panel, void, "setTitle:", objc.nsString("Save File"));
    _ = objc.msgSend1(panel, void, "setPrompt:", objc.nsString("Save"));

    return runMacModalPanelAndCopyUrlPath(panel, has_start_dir, &start_dir_z_buf, buf_ptr, buf_cap);
}

fn setupMainMenu(app: objc.id, delegate_obj: objc.id, app_name: [*:0]const u8) void {
    const NSMenu = objc.objc_getClass("NSMenu");
    const NSMenuItem = objc.objc_getClass("NSMenuItem");
    if (NSMenu == null or NSMenuItem == null) return;

    const main_menu = objc.msgSend0(objc.msgSend0(NSMenu, objc.id, "alloc"), objc.id, "init");
    if (main_menu == null) return;

    // 1. Application Menu
    const app_menu_item = objc.msgSend0(objc.msgSend0(NSMenuItem, objc.id, "alloc"), objc.id, "init");
    const app_menu = objc.msgSend1(objc.msgSend0(NSMenu, objc.id, "alloc"), objc.id, "initWithTitle:", objc.nsString(app_name));

    var quit_title_buf: [128]u8 = undefined;
    const quit_title = std.fmt.bufPrintSentinel(&quit_title_buf, "Quit {s}", .{std.mem.sliceTo(app_name, 0)}, 0) catch "Quit";
    const quit_item = objc.msgSend3(
        objc.msgSend0(NSMenuItem, objc.id, "alloc"),
        objc.id,
        "initWithTitle:action:keyEquivalent:",
        objc.nsString(quit_title),
        objc.sel_registerName("terminate:"),
        objc.nsString("q"),
    );
    _ = objc.msgSend1(quit_item, void, "setTarget:", app);
    _ = objc.msgSend1(app_menu, void, "addItem:", quit_item);
    _ = objc.msgSend1(app_menu_item, void, "setSubmenu:", app_menu);
    _ = objc.msgSend1(main_menu, void, "addItem:", app_menu_item);

    // 2. File Menu
    const file_menu_item = objc.msgSend0(objc.msgSend0(NSMenuItem, objc.id, "alloc"), objc.id, "init");
    const file_menu = objc.msgSend1(objc.msgSend0(NSMenu, objc.id, "alloc"), objc.id, "initWithTitle:", objc.nsString("File"));

    const open_ws_item = objc.msgSend3(
        objc.msgSend0(NSMenuItem, objc.id, "alloc"),
        objc.id,
        "initWithTitle:action:keyEquivalent:",
        objc.nsString("Open Workspace Folder..."),
        objc.sel_registerName("onMenuOpenWorkspace:"),
        objc.nsString("o"),
    );
    _ = objc.msgSend1(open_ws_item, void, "setTarget:", delegate_obj);
    _ = objc.msgSend1(file_menu, void, "addItem:", open_ws_item);

    _ = objc.msgSend1(file_menu, void, "addItem:", objc.msgSend0(NSMenuItem, objc.id, "separatorItem"));

    const save_item = objc.msgSend3(
        objc.msgSend0(NSMenuItem, objc.id, "alloc"),
        objc.id,
        "initWithTitle:action:keyEquivalent:",
        objc.nsString("Save"),
        objc.sel_registerName("onMenuSave:"),
        objc.nsString("s"),
    );
    _ = objc.msgSend1(save_item, void, "setTarget:", delegate_obj);
    _ = objc.msgSend1(file_menu, void, "addItem:", save_item);

    const save_as_item = objc.msgSend3(
        objc.msgSend0(NSMenuItem, objc.id, "alloc"),
        objc.id,
        "initWithTitle:action:keyEquivalent:",
        objc.nsString("Save As..."),
        objc.sel_registerName("onMenuSaveAs:"),
        objc.nsString("S"),
    );
    _ = objc.msgSend1(save_as_item, void, "setTarget:", delegate_obj);
    _ = objc.msgSend1(file_menu, void, "addItem:", save_as_item);

    _ = objc.msgSend1(file_menu, void, "addItem:", objc.msgSend0(NSMenuItem, objc.id, "separatorItem"));

    const close_tab_item = objc.msgSend3(
        objc.msgSend0(NSMenuItem, objc.id, "alloc"),
        objc.id,
        "initWithTitle:action:keyEquivalent:",
        objc.nsString("Close Editor"),
        objc.sel_registerName("onMenuCloseTab:"),
        objc.nsString("w"),
    );
    _ = objc.msgSend1(close_tab_item, void, "setTarget:", delegate_obj);
    _ = objc.msgSend1(file_menu, void, "addItem:", close_tab_item);

    _ = objc.msgSend1(file_menu_item, void, "setSubmenu:", file_menu);
    _ = objc.msgSend1(main_menu, void, "addItem:", file_menu_item);

    _ = objc.msgSend1(app, void, "setMainMenu:", main_menu);
}

const LiveResizeHook = struct {
    window: objc.id,
    content_view: objc.id,
    metal_layer: *anyopaque,
    mtl_queue: objc.id,
    gr_context: skia.DirectContext,
    debug_paint: skia.Paint,
    ctx: *app_api.PlatformContext,
    hot_lib: *HotDylib,
    backbuffer_surface: *?skia.Surface,
    prev_w: *f32,
    prev_h: *f32,
    prev_scale: *f32,
    prev_fullscreen: *bool,
    redraw_frames_remaining: *u8,
    last_frame_time: *f64,
    saved_windowed_frame: objc.NSRect = .{
        .origin = .{ .x = 100, .y = 100 },
        .size = .{ .width = 1080, .height = 700 },
    },
    has_saved_windowed_frame: bool = false,
    in_fullscreen_enter: bool = false,
    in_fullscreen_exit: bool = false,
    enforcing_frame: bool = false,
    in_callback: bool = false,

    fn isFullScreenActive(self: *const LiveResizeHook) bool {
        if (self.in_fullscreen_exit) return false;
        if (self.in_fullscreen_enter) return true;
        const cur_style = objc.msgSend0(self.window, usize, "styleMask");
        return (cur_style & objc.NSWindowStyleMaskFullScreen) != 0;
    }

    fn enforceFullScreenFrame(self: *LiveResizeHook) void {
        if (self.enforcing_frame or !self.isFullScreenActive()) return;
        const screen = objc.msgSend0(self.window, objc.id, "screen");
        if (screen == null) return;
        const screen_frame = objc.msgSend0(screen, objc.NSRect, "frame");
        const cur_frame = objc.msgSend0(self.window, objc.NSRect, "frame");
        const cv_frame = objc.msgSend0(self.content_view, objc.NSRect, "frame");
        const cur_level = objc.msgSend0(self.window, isize, "level");
        const target_level: isize = 25; // NSStatusWindowLevel (above Fullscreen Space level-24 notch mask)

        const frame_mismatch = @abs(cur_frame.origin.x - screen_frame.origin.x) > 0.5 or
            @abs(cur_frame.origin.y - screen_frame.origin.y) > 0.5 or
            @abs(cur_frame.size.width - screen_frame.size.width) > 0.5 or
            @abs(cur_frame.size.height - screen_frame.size.height) > 0.5;
        const cv_mismatch = @abs(cv_frame.origin.x) > 0.5 or
            @abs(cv_frame.origin.y) > 0.5 or
            @abs(cv_frame.size.width - screen_frame.size.width) > 0.5 or
            @abs(cv_frame.size.height - screen_frame.size.height) > 0.5;

        if (frame_mismatch or cv_mismatch or cur_level != target_level) {
            self.enforcing_frame = true;
            defer self.enforcing_frame = false;

            const cur_style = objc.msgSend0(self.window, usize, "styleMask");
            if ((cur_style & objc.NSWindowStyleMaskFullSizeContentView) == 0) {
                _ = objc.msgSend1(self.window, void, "setStyleMask:", cur_style | objc.NSWindowStyleMaskFullSizeContentView);
            }
            _ = objc.msgSend1(self.window, void, "setTitlebarAppearsTransparent:", true);
            _ = objc.msgSend1(self.window, void, "setTitleVisibility:", @as(isize, 1));
            if (cur_level != target_level) {
                _ = objc.msgSend1(self.window, void, "setLevel:", target_level);
            }
            if (frame_mismatch) {
                _ = objc.msgSend2(self.window, void, "setFrame:display:", screen_frame, true);
            }
            const full_cv = objc.NSRect{
                .origin = .{ .x = 0, .y = 0 },
                .size = screen_frame.size,
            };
            _ = objc.msgSend1(self.content_view, void, "setFrame:", full_cv);
        }
    }

    fn renderOnResize(self: *LiveResizeHook) void {
        if (self.in_callback) return;
        self.in_callback = true;
        defer self.in_callback = false;

        const pool = objc.objc_autoreleasePoolPush();
        defer objc.objc_autoreleasePoolPop(pool);

        if (self.isFullScreenActive()) {
            self.enforceFullScreenFrame();
        }

        const bounds = objc.msgSend0(self.content_view, objc.NSRect, "bounds");
        const scale = objc.msgSend0(self.window, objc.CGFloat, "backingScaleFactor");
        if (bounds.size.width <= 0 or bounds.size.height <= 0) return;

        const is_fullscreen = self.isFullScreenActive();
        self.prev_fullscreen.* = is_fullscreen;

        self.ctx.width = @floatCast(bounds.size.width);
        self.ctx.height = @floatCast(bounds.size.height);
        self.ctx.dpi_scale = @floatCast(scale);
        self.ctx.is_fullscreen = is_fullscreen;

        const phys_w: i32 = @intFromFloat(@round(bounds.size.width * scale));
        const phys_h: i32 = @intFromFloat(@round(bounds.size.height * scale));
        if (self.backbuffer_surface.*) |old_s| old_s.deinit();
        self.backbuffer_surface.* = skia.Surface.initRenderTarget(
            self.gr_context,
            skia.ImageInfo.initBgra8888Premul(phys_w, phys_h),
            1,
        ) catch return;

        _ = objc.msgSend1(self.metal_layer, void, "setFrame:", bounds);
        _ = objc.msgSend1(self.metal_layer, void, "setContentsScale:", scale);
        _ = objc.msgSend1(self.metal_layer, void, "setDrawableSize:", objc.NSSize{
            .width = bounds.size.width * scale,
            .height = bounds.size.height * scale,
        });

        self.ctx.force_full_redraw = true;
        self.redraw_frames_remaining.* = 2;
        self.prev_w.* = self.ctx.width;
        self.prev_h.* = self.ctx.height;
        self.prev_scale.* = self.ctx.dpi_scale;

        const mouse_loc = objc.msgSend0(self.window, objc.NSPoint, "mouseLocationOutsideOfEventStream");
        self.ctx.mouse_x = @floatCast(mouse_loc.x);
        self.ctx.mouse_y = self.ctx.height - @as(f32, @floatCast(mouse_loc.y));

        const backbuffer = self.backbuffer_surface.*.?;
        const back_canvas = backbuffer.canvas();
        _ = back_canvas.save();
        back_canvas.scale(self.ctx.dpi_scale, self.ctx.dpi_scale);

        self.ctx.canvas = back_canvas.ptr;
        self.ctx.phase_input_us = 0;
        self.ctx.phase_paint_us = 0;
        if (self.hot_lib.app_tick) |tick_fn| {
            _ = tick_fn(self.ctx);
        }
        self.ctx.canvas = null;
        self.ctx.clearFrameInput();
        back_canvas.restore();

        var drawable_handle: skia.c.gr_mtl_handle_t = null;
        const drawable_surface = skia.Surface.initMetalLayer(
            self.gr_context,
            self.metal_layer,
            1,
            .bgra_8888,
            &drawable_handle,
        ) catch return;
        defer drawable_surface.deinit();

        const drawable_canvas = drawable_surface.canvas();
        backbuffer.draw(drawable_canvas, 0, 0, null);

        if (self.ctx.show_dirty_overlay) {
            _ = drawable_canvas.save();
            drawable_canvas.scale(self.ctx.dpi_scale, self.ctx.dpi_scale);
            drawable_canvas.drawRect(self.ctx.last_dirty_rect, self.debug_paint);
            drawable_canvas.restore();
        }

        self.gr_context.flushAndSubmit(false);
        self.last_frame_time.* = objc.CFAbsoluteTimeGetCurrent();

        if (drawable_handle) |drawable_ptr| {
            const drawable: objc.id = @constCast(drawable_ptr);
            const cmd_buf = objc.msgSend0(self.mtl_queue, objc.id, "commandBuffer");
            _ = objc.msgSend1(cmd_buf, void, "presentDrawable:", drawable);
            _ = objc.msgSend0(cmd_buf, void, "commit");
            _ = objc.msgSend0(cmd_buf, void, "waitUntilScheduled");
            objc.CFRelease(drawable_ptr);
        }
        self.ctx.frame_count += 1;
    }
};

var g_live_resize_hook: ?*LiveResizeHook = null;

fn onWindowConstrainFrameRect(window: objc.id, _: objc.SEL, frame_rect: objc.NSRect, screen: objc.id) callconv(.c) objc.NSRect {
    if (g_live_resize_hook) |hook| {
        if (hook.isFullScreenActive()) {
            const target_screen = if (screen != null) screen else objc.msgSend0(window, objc.id, "screen");
            if (target_screen != null) {
                return objc.msgSend0(target_screen, objc.NSRect, "frame");
            }
            return frame_rect;
        }
    }
    if (screen != null) {
        const vis = objc.msgSend0(screen, objc.NSRect, "visibleFrame");
        var r = frame_rect;
        const max_top = vis.origin.y + vis.size.height;
        if (r.origin.y + r.size.height > max_top) {
            r.origin.y = max_top - r.size.height;
        }
        return r;
    }
    return frame_rect;
}

fn onWindowCanBecomeKey(_: objc.id, _: objc.SEL) callconv(.c) bool {
    return true;
}

const NSRange = extern struct {
    location: usize,
    length: usize,
};

fn pushInsertedObjcString(str_or_attr: objc.id) void {
    if (str_or_attr == null) return;
    const hook = g_live_resize_hook orelse return;
    var ns_str = str_or_attr;
    const sel_utf8 = objc.sel_registerName("UTF8String");
    if (!objc.msgSend1(ns_str, bool, "respondsToSelector:", sel_utf8)) {
        const sel_string = objc.sel_registerName("string");
        if (objc.msgSend1(ns_str, bool, "respondsToSelector:", sel_string)) {
            ns_str = objc.msgSend0(ns_str, objc.id, "string");
        } else {
            return;
        }
    }
    if (ns_str == null) return;
    if (objc.msgSend0(ns_str, ?[*:0]const u8, "UTF8String")) |c_str| {
        const slice = std.mem.span(c_str);
        if (slice.len > 0) {
            hook.ctx.pushTextInput(slice);
            hook.redraw_frames_remaining.* = 2;
        }
    }
}

fn onWindowInsertText(_: objc.id, _: objc.SEL, text_obj: objc.id) callconv(.c) void {
    pushInsertedObjcString(text_obj);
}

fn onWindowInsertTextReplacementRange(_: objc.id, _: objc.SEL, text_obj: objc.id, _: NSRange) callconv(.c) void {
    pushInsertedObjcString(text_obj);
}

fn onViewConformsToProtocol(_: objc.id, _: objc.SEL, protocol: objc.id) callconv(.c) bool {
    if (protocol != null) {
        if (objc.objc_getProtocol("NSTextInputClient")) |ti_proto| {
            if (protocol == ti_proto) return true;
        }
        if (objc.protocol_getName(protocol)) |name_ptr| {
            const name = std.mem.span(name_ptr);
            if (std.mem.eql(u8, name, "NSTextInputClient") or std.mem.eql(u8, name, "NSTextInput")) {
                return true;
            }
        }
    }
    return false;
}

fn onViewDoCommandBySelector(_: objc.id, _: objc.SEL, _: objc.SEL) callconv(.c) void {}

fn onViewSetMarkedText(_: objc.id, _: objc.SEL, _: objc.id, _: NSRange, _: NSRange) callconv(.c) void {}

fn onViewUnmarkText(_: objc.id, _: objc.SEL) callconv(.c) void {}

fn onViewSelectedRange(_: objc.id, _: objc.SEL) callconv(.c) NSRange {
    return .{ .location = 0, .length = 0 };
}

fn onViewMarkedRange(_: objc.id, _: objc.SEL) callconv(.c) NSRange {
    return .{ .location = 0x7fffffffffffffff, .length = 0 };
}

fn onViewHasMarkedText(_: objc.id, _: objc.SEL) callconv(.c) bool {
    return false;
}

fn onViewAttributedSubstring(_: objc.id, _: objc.SEL, _: NSRange, _: ?*NSRange) callconv(.c) objc.id {
    return null;
}

fn onViewValidAttributesForMarkedText(_: objc.id, _: objc.SEL) callconv(.c) objc.id {
    return objc.msgSend0(objc.objc_getClass("NSArray"), objc.id, "array");
}

fn onViewFirstRectForCharacterRange(self: objc.id, _: objc.SEL, _: NSRange, actual_range: ?*NSRange) callconv(.c) objc.NSRect {
    if (actual_range) |ar| {
        ar.* = .{ .location = 0, .length = 0 };
    }
    if (g_live_resize_hook) |hook| {
        const bounds = objc.msgSend0(self, objc.NSRect, "bounds");
        const cur_h: f64 = bounds.size.height;
        const cx: f64 = @floatCast(hook.ctx.ime_cursor_x);
        const cy_top: f64 = @floatCast(hook.ctx.ime_cursor_y);
        const ch: f64 = @max(16.0, @as(f64, @floatCast(hook.ctx.ime_cursor_h)));
        const local_rect = objc.NSRect{
            .origin = .{
                .x = std.math.clamp(cx, 16.0, @max(16.0, bounds.size.width - 16.0)),
                .y = std.math.clamp(cur_h - (cy_top + ch), 16.0, @max(16.0, cur_h - 16.0)),
            },
            .size = .{ .width = 2.0, .height = ch },
        };
        return objc.msgSend1(hook.window, objc.NSRect, "convertRectToScreen:", local_rect);
    }
    return .{ .origin = .{ .x = 200, .y = 200 }, .size = .{ .width = 2, .height = 20 } };
}

var g_text_input_context: objc.id = null;

fn onViewInputContext(self: objc.id, _: objc.SEL) callconv(.c) objc.id {
    if (g_text_input_context == null) {
        const NSTextInputContext = objc.objc_getClass("NSTextInputContext");
        if (NSTextInputContext != null) {
            const alloc = objc.msgSend0(NSTextInputContext, objc.id, "alloc");
            g_text_input_context = objc.msgSend1(alloc, objc.id, "initWithClient:", self);
        }
    }
    return g_text_input_context;
}

fn onViewCharacterIndexForPoint(_: objc.id, _: objc.SEL, _: objc.NSPoint) callconv(.c) usize {
    return 0;
}

fn onViewMouseDownCanMoveWindow(_: objc.id, _: objc.SEL) callconv(.c) bool {
    return false;
}

fn createContentViewClass() objc.Class {
    const class_name = "ZSkiaContentView";
    var cls = objc.objc_getClass(class_name);
    if (cls == null) {
        const NSView = objc.objc_getClass("NSView");
        cls = objc.objc_allocateClassPair(NSView, class_name, 0);
        if (cls != null) {
            if (objc.objc_getProtocol("NSTextInputClient")) |proto| {
                _ = objc.class_addProtocol(cls, proto);
            }
            _ = objc.class_addMethod(
                cls,
                objc.sel_registerName("mouseDownCanMoveWindow"),
                @ptrCast(&onViewMouseDownCanMoveWindow),
                "B@:",
            );
            _ = objc.class_addMethod(
                cls,
                objc.sel_registerName("conformsToProtocol:"),
                @ptrCast(&onViewConformsToProtocol),
                "B@:@",
            );
            _ = objc.class_addMethod(
                cls,
                objc.sel_registerName("inputContext"),
                @ptrCast(&onViewInputContext),
                "@@:",
            );
            _ = objc.class_addMethod(
                cls,
                objc.sel_registerName("acceptsFirstResponder"),
                @ptrCast(&onWindowCanBecomeKey),
                "B@:",
            );
            _ = objc.class_addMethod(
                cls,
                objc.sel_registerName("insertText:"),
                @ptrCast(&onWindowInsertText),
                "v@:@",
            );
            _ = objc.class_addMethod(
                cls,
                objc.sel_registerName("insertText:replacementRange:"),
                @ptrCast(&onWindowInsertTextReplacementRange),
                "v@:@{_NSRange=QQ}",
            );
            _ = objc.class_addMethod(
                cls,
                objc.sel_registerName("doCommandBySelector:"),
                @ptrCast(&onViewDoCommandBySelector),
                "v@::",
            );
            _ = objc.class_addMethod(
                cls,
                objc.sel_registerName("setMarkedText:selectedRange:replacementRange:"),
                @ptrCast(&onViewSetMarkedText),
                "v@:@{_NSRange=QQ}{_NSRange=QQ}",
            );
            _ = objc.class_addMethod(
                cls,
                objc.sel_registerName("unmarkText"),
                @ptrCast(&onViewUnmarkText),
                "v@:",
            );
            _ = objc.class_addMethod(
                cls,
                objc.sel_registerName("selectedRange"),
                @ptrCast(&onViewSelectedRange),
                "{_NSRange=QQ}@:",
            );
            _ = objc.class_addMethod(
                cls,
                objc.sel_registerName("markedRange"),
                @ptrCast(&onViewMarkedRange),
                "{_NSRange=QQ}@:",
            );
            _ = objc.class_addMethod(
                cls,
                objc.sel_registerName("hasMarkedText"),
                @ptrCast(&onViewHasMarkedText),
                "B@:",
            );
            _ = objc.class_addMethod(
                cls,
                objc.sel_registerName("attributedSubstringForProposedRange:actualRange:"),
                @ptrCast(&onViewAttributedSubstring),
                "@@:{_NSRange=QQ}^{_NSRange=QQ}",
            );
            _ = objc.class_addMethod(
                cls,
                objc.sel_registerName("validAttributesForMarkedText"),
                @ptrCast(&onViewValidAttributesForMarkedText),
                "@@:",
            );
            _ = objc.class_addMethod(
                cls,
                objc.sel_registerName("firstRectForCharacterRange:actualRange:"),
                @ptrCast(&onViewFirstRectForCharacterRange),
                "{CGRect={CGPoint=dd}{CGSize=dd}}@:{_NSRange=QQ}^{_NSRange=QQ}",
            );
            _ = objc.class_addMethod(
                cls,
                objc.sel_registerName("characterIndexForPoint:"),
                @ptrCast(&onViewCharacterIndexForPoint),
                "Q@:{CGPoint=dd}",
            );
            objc.objc_registerClassPair(cls);
        }
    }
    return cls orelse objc.objc_getClass("NSView");
}

fn createWindowClass() objc.Class {
    const class_name = "ZSkiaWindow";
    var cls = objc.objc_getClass(class_name);
    if (cls == null) {
        const NSWindow = objc.objc_getClass("NSWindow");
        cls = objc.objc_allocateClassPair(NSWindow, class_name, 0);
        if (cls != null) {
            _ = objc.class_addMethod(
                cls,
                objc.sel_registerName("constrainFrameRect:toScreen:"),
                @ptrCast(&onWindowConstrainFrameRect),
                "{CGRect={CGPoint=dd}{CGSize=dd}}@:{CGRect={CGPoint=dd}{CGSize=dd}}@",
            );
            _ = objc.class_addMethod(
                cls,
                objc.sel_registerName("canBecomeKeyWindow"),
                @ptrCast(&onWindowCanBecomeKey),
                "B@:",
            );
            _ = objc.class_addMethod(
                cls,
                objc.sel_registerName("canBecomeMainWindow"),
                @ptrCast(&onWindowCanBecomeKey),
                "B@:",
            );
            _ = objc.class_addMethod(
                cls,
                objc.sel_registerName("insertText:"),
                @ptrCast(&onWindowInsertText),
                "v@:@",
            );
            _ = objc.class_addMethod(
                cls,
                objc.sel_registerName("insertText:replacementRange:"),
                @ptrCast(&onWindowInsertTextReplacementRange),
                "v@:@{_NSRange=QQ}",
            );
            objc.objc_registerClassPair(cls);
        }
    }
    return cls orelse objc.objc_getClass("NSWindow");
}

fn onWindowDidResize(_: objc.id, _: objc.SEL, _: objc.id) callconv(.c) void {
    if (g_live_resize_hook) |hook| {
        hook.enforceFullScreenFrame();
        hook.renderOnResize();
    }
}

fn onWindowDidMove(_: objc.id, _: objc.SEL, _: objc.id) callconv(.c) void {
    if (g_live_resize_hook) |hook| {
        if (hook.isFullScreenActive()) {
            hook.enforceFullScreenFrame();
            hook.renderOnResize();
        }
    }
}

fn onWindowWillEnterFullScreen(_: objc.id, _: objc.SEL, _: objc.id) callconv(.c) void {
    if (g_live_resize_hook) |hook| {
        const cur_style = objc.msgSend0(hook.window, usize, "styleMask");
        if ((cur_style & objc.NSWindowStyleMaskFullScreen) == 0) {
            hook.saved_windowed_frame = objc.msgSend0(hook.window, objc.NSRect, "frame");
            hook.has_saved_windowed_frame = true;
        }
        hook.in_fullscreen_enter = true;
        hook.in_fullscreen_exit = false;
    }
}

fn onCustomWindowsToEnterFullScreen(_: objc.id, _: objc.SEL, window: objc.id) callconv(.c) objc.id {
    const NSArray = objc.objc_getClass("NSArray");
    return objc.msgSend1(NSArray, objc.id, "arrayWithObject:", window);
}

fn onStartCustomEnterFullScreen(_: objc.id, _: objc.SEL, window: objc.id, duration: f64) callconv(.c) void {
    _ = duration;
    if (g_live_resize_hook) |hook| {
        if (!hook.has_saved_windowed_frame) {
            hook.saved_windowed_frame = objc.msgSend0(window, objc.NSRect, "frame");
            hook.has_saved_windowed_frame = true;
        }
        hook.in_fullscreen_enter = true;
        hook.in_fullscreen_exit = false;
        const cur_style = objc.msgSend0(window, usize, "styleMask");
        _ = objc.msgSend1(
            window,
            void,
            "setStyleMask:",
            cur_style | objc.NSWindowStyleMaskFullScreen | objc.NSWindowStyleMaskFullSizeContentView,
        );
        hook.enforceFullScreenFrame();
        hook.renderOnResize();
    }
}

fn onWindowDidEnterFullScreen(_: objc.id, _: objc.SEL, _: objc.id) callconv(.c) void {
    if (g_live_resize_hook) |hook| {
        hook.in_fullscreen_enter = false;
        hook.in_fullscreen_exit = false;
        hook.enforceFullScreenFrame();
        hook.renderOnResize();
        hook.redraw_frames_remaining.* = 6;
    }
}

fn onWindowWillExitFullScreen(_: objc.id, _: objc.SEL, _: objc.id) callconv(.c) void {
    if (g_live_resize_hook) |hook| {
        hook.in_fullscreen_enter = false;
        hook.in_fullscreen_exit = true;
        _ = objc.msgSend1(hook.window, void, "setLevel:", @as(isize, 0));
    }
}

fn onCustomWindowsToExitFullScreen(_: objc.id, _: objc.SEL, window: objc.id) callconv(.c) objc.id {
    const NSArray = objc.objc_getClass("NSArray");
    return objc.msgSend1(NSArray, objc.id, "arrayWithObject:", window);
}

fn onStartCustomExitFullScreen(_: objc.id, _: objc.SEL, window: objc.id, duration: f64) callconv(.c) void {
    _ = duration;
    if (g_live_resize_hook) |hook| {
        hook.in_fullscreen_enter = false;
        hook.in_fullscreen_exit = true;
        _ = objc.msgSend1(window, void, "setLevel:", @as(isize, 0));
        const cur_style = objc.msgSend0(window, usize, "styleMask");
        _ = objc.msgSend1(
            window,
            void,
            "setStyleMask:",
            (cur_style & ~objc.NSWindowStyleMaskFullScreen) | objc.NSWindowStyleMaskFullSizeContentView,
        );
        if (hook.has_saved_windowed_frame) {
            _ = objc.msgSend2(window, void, "setFrame:display:", hook.saved_windowed_frame, true);
        }
        hook.renderOnResize();
    }
}

fn onWindowDidExitFullScreen(_: objc.id, _: objc.SEL, _: objc.id) callconv(.c) void {
    if (g_live_resize_hook) |hook| {
        hook.in_fullscreen_enter = false;
        hook.in_fullscreen_exit = false;
        _ = objc.msgSend1(hook.window, void, "setLevel:", @as(isize, 0));
        if (hook.has_saved_windowed_frame) {
            _ = objc.msgSend2(hook.window, void, "setFrame:display:", hook.saved_windowed_frame, true);
        }
        hook.renderOnResize();
    }
}

fn onWillUseFullScreenPresentationOptions(_: objc.id, _: objc.SEL, _: objc.id, proposed_options: usize) callconv(.c) usize {
    // NSApplicationPresentationAutoHideDock (1 << 0) | NSApplicationPresentationAutoHideMenuBar (1 << 2) | NSApplicationPresentationFullScreen (1 << 10)
    return proposed_options | (1 << 0) | (1 << 2) | (1 << 10);
}

fn onMenuOpenWorkspace(_: objc.id, _: objc.SEL, _: objc.id) callconv(.c) void {
    if (g_live_resize_hook) |hook| {
        hook.ctx.pushKeyEvent(.{ .key = .key_o, .cmd = true });
        hook.ctx.force_full_redraw = true;
        hook.redraw_frames_remaining.* = 4;
    }
}

fn onMenuSave(_: objc.id, _: objc.SEL, _: objc.id) callconv(.c) void {
    if (g_live_resize_hook) |hook| {
        hook.ctx.pushKeyEvent(.{ .key = .key_s, .cmd = true });
        hook.ctx.force_full_redraw = true;
        hook.redraw_frames_remaining.* = 4;
    }
}

fn onMenuSaveAs(_: objc.id, _: objc.SEL, _: objc.id) callconv(.c) void {
    if (g_live_resize_hook) |hook| {
        hook.ctx.pushKeyEvent(.{ .key = .key_s, .cmd = true, .shift = true });
        hook.ctx.force_full_redraw = true;
        hook.redraw_frames_remaining.* = 4;
    }
}

fn onMenuCloseTab(_: objc.id, _: objc.SEL, _: objc.id) callconv(.c) void {
    if (g_live_resize_hook) |hook| {
        hook.ctx.pushKeyEvent(.{ .key = .key_w, .cmd = true });
        hook.ctx.force_full_redraw = true;
        hook.redraw_frames_remaining.* = 4;
    }
}

fn createWindowResizeDelegate() objc.id {
    const class_name = "ZSkiaWindowDelegate";
    var cls = objc.objc_getClass(class_name);
    if (cls == null) {
        const NSObject = objc.objc_getClass("NSObject");
        cls = objc.objc_allocateClassPair(NSObject, class_name, 0);
        if (cls != null) {
            _ = objc.class_addMethod(
                cls,
                objc.sel_registerName("windowDidResize:"),
                @ptrCast(&onWindowDidResize),
                "v@:@",
            );
            _ = objc.class_addMethod(
                cls,
                objc.sel_registerName("windowDidMove:"),
                @ptrCast(&onWindowDidMove),
                "v@:@",
            );
            _ = objc.class_addMethod(
                cls,
                objc.sel_registerName("windowWillEnterFullScreen:"),
                @ptrCast(&onWindowWillEnterFullScreen),
                "v@:@",
            );
            _ = objc.class_addMethod(
                cls,
                objc.sel_registerName("customWindowsToEnterFullScreenForWindow:"),
                @ptrCast(&onCustomWindowsToEnterFullScreen),
                "@@:@",
            );
            _ = objc.class_addMethod(
                cls,
                objc.sel_registerName("window:startCustomAnimationToEnterFullScreenWithDuration:"),
                @ptrCast(&onStartCustomEnterFullScreen),
                "v@:@d",
            );
            _ = objc.class_addMethod(
                cls,
                objc.sel_registerName("windowDidEnterFullScreen:"),
                @ptrCast(&onWindowDidEnterFullScreen),
                "v@:@",
            );
            _ = objc.class_addMethod(
                cls,
                objc.sel_registerName("windowWillExitFullScreen:"),
                @ptrCast(&onWindowWillExitFullScreen),
                "v@:@",
            );
            _ = objc.class_addMethod(
                cls,
                objc.sel_registerName("customWindowsToExitFullScreenForWindow:"),
                @ptrCast(&onCustomWindowsToExitFullScreen),
                "@@:@",
            );
            _ = objc.class_addMethod(
                cls,
                objc.sel_registerName("window:startCustomAnimationToExitFullScreenWithDuration:"),
                @ptrCast(&onStartCustomExitFullScreen),
                "v@:@d",
            );
            _ = objc.class_addMethod(
                cls,
                objc.sel_registerName("windowDidExitFullScreen:"),
                @ptrCast(&onWindowDidExitFullScreen),
                "v@:@",
            );
            _ = objc.class_addMethod(
                cls,
                objc.sel_registerName("window:willUseFullScreenPresentationOptions:"),
                @ptrCast(&onWillUseFullScreenPresentationOptions),
                "Q@:@Q",
            );
            _ = objc.class_addMethod(
                cls,
                objc.sel_registerName("onMenuOpenWorkspace:"),
                @ptrCast(&onMenuOpenWorkspace),
                "v@:@",
            );
            _ = objc.class_addMethod(
                cls,
                objc.sel_registerName("onMenuSave:"),
                @ptrCast(&onMenuSave),
                "v@:@",
            );
            _ = objc.class_addMethod(
                cls,
                objc.sel_registerName("onMenuSaveAs:"),
                @ptrCast(&onMenuSaveAs),
                "v@:@",
            );
            _ = objc.class_addMethod(
                cls,
                objc.sel_registerName("onMenuCloseTab:"),
                @ptrCast(&onMenuCloseTab),
                "v@:@",
            );
            objc.objc_registerClassPair(cls);
        }
    }
    if (cls == null) return null;
    const alloc = objc.msgSend0(cls, objc.id, "alloc");
    return objc.msgSend0(alloc, objc.id, "init");
}
