//! Headless Skia Raster Renderer & UI Framework Visual Verification CLI (`zig build run-raster-cli`).
//! Renders:
//!   1. `libexample_studio.dylib` (`render_studio.png`)
//!   2. Comprehensive UI Framework Primitives Gallery (`render_framework_showcase.png`)
//!   3. `libeditor_app.dylib` (`render_editor.png`)

const std = @import("std");
const skia = @import("skia");
const ui = @import("ui");
const platform = @import("platform");

extern "c" fn fopen(path: [*:0]const u8, mode: [*:0]const u8) ?*std.c.FILE;
extern "c" fn fwrite(ptr: *const anyopaque, size: usize, nitems: usize, stream: *std.c.FILE) usize;
extern "c" fn fclose(stream: *std.c.FILE) c_int;

fn writeFileBytes(path_z: [*:0]const u8, bytes: []const u8) !void {
    const f = fopen(path_z, "wb") orelse return error.OpenFailed;
    defer _ = fclose(f);
    const written = fwrite(bytes.ptr, 1, bytes.len, f);
    if (written != bytes.len) return error.WriteFailed;
}

const SyntheticStep = struct {
    mouse_x: f32 = 0,
    mouse_y: f32 = 0,
    click: bool = false,
    key: ?platform.KeyEvent = null,
    text: []const u8 = "",
};

fn renderDylibToPng(
    font_mgr: skia.FontMgr,
    dylib_path: [*:0]const u8,
    out_png_path: [*:0]const u8,
    logical_w: f32,
    logical_h: f32,
    scale: f32,
    steps: []const SyntheticStep,
) !usize {
    const phys_w: i32 = @intFromFloat(@round(logical_w * scale));
    const phys_h: i32 = @intFromFloat(@round(logical_h * scale));

    const surface = try skia.Surface.initRasterN32Premul(phys_w, phys_h);
    defer surface.deinit();

    var host_store = platform.StateStore.init(std.heap.c_allocator);
    defer host_store.deinit();

    var host_snapshot = platform.SnapshotBuffer.init(std.heap.c_allocator);
    defer host_snapshot.deinit();

    var ctx = platform.PlatformContext{
        .font_mgr = font_mgr.ptr,
        .width = logical_w,
        .height = logical_h,
        .dpi_scale = scale,
        .force_full_redraw = true,
    };
    ctx.bindHostStores(&host_store, &host_snapshot);

    var hot_lib = platform.HotDylib{
        .watch_path = dylib_path,
    };
    defer hot_lib.unload(&ctx);

    if (!hot_lib.checkAndReload(&ctx)) {
        return error.DylibLoadFailed;
    }

    const back_canvas = surface.canvas();

    // Frame 0: initial full paint
    {
        _ = back_canvas.save();
        back_canvas.scale(scale, scale);
        ctx.canvas = back_canvas.ptr;
        ctx.force_full_redraw = true;
        if (hot_lib.app_tick) |tick_fn| _ = tick_fn(&ctx);
        ctx.canvas = null;
        ctx.clearFrameInput();
        back_canvas.restore();
        ctx.frame_count += 1;
    }

    for (steps) |step| {
        if (step.click) {
            _ = back_canvas.save();
            back_canvas.scale(scale, scale);
            ctx.canvas = back_canvas.ptr;
            ctx.mouse_x = step.mouse_x;
            ctx.mouse_y = step.mouse_y;
            ctx.mouse_down = true;
            ctx.mouse_pressed = true;
            ctx.force_full_redraw = true;
            if (hot_lib.app_tick) |tick_fn| _ = tick_fn(&ctx);
            ctx.canvas = null;
            ctx.clearFrameInput();
            back_canvas.restore();
            ctx.frame_count += 1;

            _ = back_canvas.save();
            back_canvas.scale(scale, scale);
            ctx.canvas = back_canvas.ptr;
            ctx.mouse_x = step.mouse_x;
            ctx.mouse_y = step.mouse_y;
            ctx.mouse_down = false;
            ctx.mouse_released = true;
            ctx.force_full_redraw = true;
            if (hot_lib.app_tick) |tick_fn| _ = tick_fn(&ctx);
            ctx.canvas = null;
            ctx.clearFrameInput();
            back_canvas.restore();
            ctx.frame_count += 1;
        }
        if (step.key != null or step.text.len > 0) {
            _ = back_canvas.save();
            back_canvas.scale(scale, scale);
            ctx.canvas = back_canvas.ptr;
            ctx.mouse_x = step.mouse_x;
            ctx.mouse_y = step.mouse_y;
            if (step.key) |ke| {
                ctx.pushKeyEvent(ke);
            }
            if (step.text.len > 0) {
                ctx.pushTextInput(step.text);
            }
            ctx.force_full_redraw = true;
            if (hot_lib.app_tick) |tick_fn| _ = tick_fn(&ctx);
            ctx.canvas = null;
            ctx.clearFrameInput();
            back_canvas.restore();
            ctx.frame_count += 1;
        }
    }

    const png_data = try surface.encodePng();
    defer png_data.deinit();
    try writeFileBytes(out_png_path, png_data.slice());
    return png_data.slice().len;
}

const DemoMode = enum {
    orbit,
    lattice,
    pulse,
};

const DemoRow = struct {
    id: []const u8,
    module: []const u8,
    latency: []const u8,
    status: []const u8,
};

const DEMO_ROWS = [_]DemoRow{
    .{ .id = "01", .module = "ui.data_grid", .latency = "42 us", .status = "Active" },
    .{ .id = "02", .module = "ui.stage (Viewport2D)", .latency = "18 us", .status = "Ready" },
    .{ .id = "03", .module = "ui.inspector", .latency = "29 us", .status = "Active" },
    .{ .id = "04", .module = "ui.virtual_list", .latency = "15 us", .status = "Pinned" },
    .{ .id = "05", .module = "ui.cards", .latency = "31 us", .status = "Ready" },
    .{ .id = "06", .module = "ui.overlays", .latency = "12 us", .status = "Ready" },
    .{ .id = "07", .module = "ui.command_registry", .latency = "9 us", .status = "Indexed" },
    .{ .id = "08", .module = "platform.async_task", .latency = "4 ns", .status = "Idle" },
};

fn demoCellText(_: std.mem.Allocator, _: void, row_idx: usize, col_idx: usize) []const u8 {
    const r = DEMO_ROWS[row_idx % DEMO_ROWS.len];
    return switch (col_idx) {
        0 => r.id,
        1 => r.module,
        2 => r.latency,
        3 => r.status,
        else => "",
    };
}

fn renderFrameworkShowcaseToPng(
    font_mgr: skia.FontMgr,
    out_png_path: [*:0]const u8,
) !usize {
    const logical_w: f32 = 1280.0;
    const logical_h: f32 = 840.0;
    const scale: f32 = 2.0;
    const phys_w: i32 = @intFromFloat(logical_w * scale);
    const phys_h: i32 = @intFromFloat(logical_h * scale);

    const surface = try skia.Surface.initRasterN32Premul(phys_w, phys_h);
    defer surface.deinit();

    var host_store = platform.StateStore.init(std.heap.c_allocator);
    defer host_store.deinit();
    var host_snapshot = platform.SnapshotBuffer.init(std.heap.c_allocator);
    defer host_snapshot.deinit();

    var pctx = platform.PlatformContext{
        .font_mgr = font_mgr.ptr,
        .width = logical_w,
        .height = logical_h,
        .dpi_scale = scale,
        .force_full_redraw = true,
    };
    pctx.bindHostStores(&host_store, &host_snapshot);

    var fonts = ui.FontSet.init(&pctx, .{});
    defer fonts.deinit();

    const paint = try skia.Paint.init();
    defer paint.deinit();
    paint.setAntiAlias(true);

    var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena.deinit();

    var uic = ui.Context{
        .arena = arena.allocator(),
        .canvas = surface.canvas(),
        .paint = paint,
        .font_title = fonts.title,
        .font_body = fonts.body,
        .font_mono = fonts.mono,
        .platform_ctx = &pctx,
    };
    defer uic.deinit();

    var grid_state = ui.DataGridState(4){
        .sort_col = 1,
        .sort_ascending = true,
        .selected_row = 2,
    };
    var seg_mode: DemoMode = .lattice;
    var drag_speed: f32 = 2.45;
    var drag_zoom: f32 = 1.25;
    var active_color: u32 = skia.Color.rgb(56, 189, 248);
    var search_buf = platform.InlineString(64).init("virtual_list");
    var prompt_buf = platform.InlineString(128).init("src/ui/data_grid.zig");
    var toasts = ui.ToastQueue(4){};
    toasts.push("DataGrid & Inspector initialized", .success, 180);
    toasts.push("AsyncTask worker pool ready (0% idle CPU)", .info, 180);

    const canvas = surface.canvas();
    _ = canvas.save();
    canvas.scale(scale, scale);

    const win_rect = skia.Rect.xywh(0, 0, logical_w, logical_h);

    var right_col_rect: skia.c.sk_rect_t = win_rect;

    const passes = [_]ui.Pass{ .input, .paint };
    for (passes) |pass| {
        if (pass == .paint) {
            canvas.clear(uic.theme.bg_canvas);
        }
        host_store.resetScopes();
        uic.beginPass(pass, arena.allocator(), canvas, win_rect, 400, 300, false, false, false);
        if (pass == .input) {
            uic.markDirty(win_rect);
        } else {
            uic.clip_damage = win_rect;
        }

        var root_col = uic.column(.{
            .w = .fill,
            .h = .fill,
            .padding = ui.Padding.all(12),
            .gap = 10,
            .bg_color = uic.theme.bg_canvas,
        });

        // Top Body Row (3 Columns)
        {
            var body_row = uic.row(.{
                .w = .fill,
                .h = .fillMinus(34),
                .gap = 12,
            });
            defer body_row.end();

            // Column 1: DataGrid, Size.fillMinus Search Bar, & flowWrap Chips
            {
                var left_col = uic.column(.{
                    .w = .pixels(412),
                    .h = .fill,
                    .preset = .panel_card,
                    .padding = ui.Padding.all(12),
                    .gap = 10,
                });
                defer left_col.end();

                uic.sectionHeader("VIRTUALIZED DATAGRID & FLOW-WRAP LAYOUT");

                // Search bar using Size.fillMinus(78) + trailing Filter button
                {
                    var search_row = uic.row(.{ .w = .fill, .h = .pixels(30), .gap = 6 });
                    defer search_row.end();
                    _ = uic.textFieldInline("##grid_search", &search_buf, "Filter modules...", .{ .w = .fillMinus(78) });
                    _ = uic.btn("Search##btn_s", .{ .w = .pixels(72), .h = 28.0 });
                }

                // FlowWrap container of filter chips
                {
                    var wrap = uic.flowWrap(.{
                        .w = .fill,
                        .gap = 6,
                        .padding = ui.Padding.xy(2, 2),
                    });
                    defer wrap.end();
                    _ = uic.chip("Layer 0: Skia", .{ .bordered = true });
                    _ = uic.chip("Layer 1: Platform", .{ .bordered = true });
                    _ = uic.chip("Layer 2: UI Toolkit", .{ .active = true, .bordered = true });
                    _ = uic.chip("Layer 3: Editor App", .{ .bordered = true });
                    _ = uic.chip("2-Phase Deterministic", .{ .active = true, .bordered = true });
                    _ = uic.chip("Zero-Alloc TextCache", .{ .bordered = true });
                }

                const cols = [_]ui.DataGridColumn{
                    .{ .title = "ID", .width = 40, .min_width = 36 },
                    .{ .title = "Module", .width = 160, .min_width = 90 },
                    .{ .title = "Frame Cost", .width = 90, .min_width = 64, .align_right = true },
                    .{ .title = "State", .width = 82, .min_width = 60 },
                };
                _ = uic.dataGrid(4, "showcase_grid", &grid_state, &cols, DEMO_ROWS.len, 26.0, {}, demoCellText);
            }

            // Column 2: Reusable Cards, Disclosures, Option Cards & Attachment Strip
            {
                var mid_col = uic.column(.{
                    .w = .pixels(420),
                    .h = .fill,
                    .preset = .panel_card,
                    .padding = ui.Padding.all(12),
                    .gap = 10,
                });
                defer mid_col.end();

                uic.sectionHeader("CARDS, DISCLOSURES & SELECTABLE OPTIONS");

                _ = uic.inlineStepRowEx(
                    "##step_1",
                    "✓",
                    uic.theme.success,
                    "Extracted UI modules",
                    "virtual_list.zig • cards.zig",
                );

                _ = uic.thinkingDisclosureEx(
                    "demo_think",
                    0,
                    "Analyzing 2-phase layout rect determinism",
                    "Verified Pass.input and Pass.paint consume identical layout rects across all newly extracted widgets.",
                    true,
                    .{},
                );

                _ = uic.commandExecutionCardEx(
                    "demo_cmd_ok",
                    0,
                    "zig build test && zig build microbench",
                    "[1. TextCache] hit_rate=99.95% evictions=0\n[2. DamageList] damage_area=0.17% painted=3/100",
                    .exited_ok,
                    .{ .default_open = true },
                );

                _ = uic.commandExecutionCardEx(
                    "demo_cmd_pend",
                    1,
                    "zig build package --release=fast",
                    "",
                    .pending_approval,
                    .{},
                );

                const card_max_w: f32 = 340.0;
                _ = uic.selectableOptionCard(
                    "##opt_1",
                    "Use VariableHeightCache for heterogeneous chat streams",
                    true,
                    true,
                    false,
                    card_max_w,
                );
                _ = uic.selectableOptionCard(
                    "##opt_2",
                    "Use uniform computeVirtualRange for fixed-height tables",
                    false,
                    false,
                    false,
                    card_max_w,
                );
            }

            // Column 3: Inspector Controls, Split Subtrigger Menu, Prompt Modal & Toasts
            {
                var right_col = uic.column(.{
                    .w = .fill,
                    .h = .fill,
                    .preset = .panel_card,
                    .padding = ui.Padding.all(12),
                    .gap = 10,
                });
                defer right_col.end();
                right_col_rect = right_col.rect;

                uic.sectionHeader("INSPECTOR, FLYOUT MENU & PROMPT MODAL");

                _ = uic.segmentedControl(DemoMode, "##demo_seg_mode", &seg_mode);
                _ = uic.dragFloat("Rotation Speed##df_spd", &drag_speed, 0.02, 0.0, 10.0, 2);
                _ = uic.dragFloat("Viewport Zoom##df_zm", &drag_zoom, 0.01, 0.15, 8.0, 2);

                const palette = [_]u32{
                    skia.Color.rgb(56, 189, 248),
                    skia.Color.rgb(129, 140, 248),
                    skia.Color.rgb(52, 211, 153),
                    skia.Color.rgb(244, 114, 182),
                    skia.Color.rgb(251, 191, 36),
                };
                _ = uic.colorSwatchPicker("##demo_swatches", &active_color, &palette);

                _ = uic.menuItemWithSubtrigger("##menu_sub_1", "Claude Opus 4.6", true, "High ▸", true);
                _ = uic.menuItemWithSubtrigger("##menu_sub_2", "Gemini 3.1 Pro", false, "Medium ▸", false);

                const attachments = [_]ui.AttachmentDisplayItem{
                    .{ .name = "architecture.png", .meta = "2560×1600", .width = 2560, .height = 1600 },
                    .{ .name = "bench_trace.json", .meta = "42 KB" },
                };
                _ = uic.attachmentGallery("##demo_att", &attachments, .{ .removable = true });
            }
        }

        // Bottom Status Bar using `statusDotIndicator` and `statusTextSegment`
        {
            var status_bar = uic.row(.{
                .w = .fill,
                .h = .pixels(24),
                .preset = .toolbar,
                .padding = ui.Padding.xy(10, 3),
                .gap = 16,
            });
            defer status_bar.end();

            uic.statusDotIndicator(uic.theme.success, "Framework Verification Suite: PASS", uic.theme.text_primary);
            uic.statusTextSegment("4 Layers • 2-Phase Skia GPU • 0% Idle CPU", uic.theme.text_muted);
        }

        root_col.end();

        // Render floating `uic.promptModal` inside lower half of Column 3
        const modal_rect = skia.Rect.xywh(
            right_col_rect.left + 14,
            right_col_rect.top + 380,
            (right_col_rect.right - right_col_rect.left) - 28,
            132,
        );
        _ = uic.promptModal(128, "demo_prompt_modal", modal_rect, &prompt_buf, .{
            .title = "SAVE SNAPSHOT AS",
            .placeholder = "Enter file path...",
            .confirm_label = "Save",
            .hint = "Enter to save • Esc to cancel",
        });

        // Render bottom-right Toast notifications
        uic.renderToasts(4, &toasts, win_rect);

        uic.endPass();
    }

    canvas.restore();

    const png_data = try surface.encodePng();
    defer png_data.deinit();
    try writeFileBytes(out_png_path, png_data.slice());
    return png_data.slice().len;
}

fn renderChartsAndNodeGraphToPng(
    font_mgr: skia.FontMgr,
    out_png_path: [*:0]const u8,
) !usize {
    const logical_w: f32 = 1280.0;
    const logical_h: f32 = 840.0;
    const scale: f32 = 2.0;
    const phys_w: i32 = @intFromFloat(logical_w * scale);
    const phys_h: i32 = @intFromFloat(logical_h * scale);

    const surface = try skia.Surface.initRasterN32Premul(phys_w, phys_h);
    defer surface.deinit();

    var host_store = platform.StateStore.init(std.heap.c_allocator);
    defer host_store.deinit();
    var host_snapshot = platform.SnapshotBuffer.init(std.heap.c_allocator);
    defer host_snapshot.deinit();

    var pctx = platform.PlatformContext{
        .font_mgr = font_mgr.ptr,
        .width = logical_w,
        .height = logical_h,
        .dpi_scale = scale,
        .force_full_redraw = true,
    };
    pctx.bindHostStores(&host_store, &host_snapshot);

    var fonts = ui.FontSet.init(&pctx, .{});
    defer fonts.deinit();

    const paint = try skia.Paint.init();
    defer paint.deinit();
    paint.setAntiAlias(true);

    var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena.deinit();

    var uic = ui.Context{
        .arena = arena.allocator(),
        .canvas = surface.canvas(),
        .paint = paint,
        .font_title = fonts.title,
        .font_body = fonts.body,
        .font_mono = fonts.mono,
        .platform_ctx = &pctx,
    };
    defer uic.deinit();

    var graph_state = ui.NodeGraphState(8){
        .selected_node = 3,
    };
    var rename_buf = platform.InlineString(64).init("node_graph.zig");

    const canvas = surface.canvas();
    _ = canvas.save();
    canvas.scale(scale, scale);

    const win_rect = skia.Rect.xywh(0, 0, logical_w, logical_h);

    const passes = [_]ui.Pass{ .input, .paint };
    for (passes) |pass| {
        if (pass == .paint) {
            canvas.clear(uic.theme.bg_canvas);
        }
        host_store.resetScopes();
        // Position mouse over the lineChart at (240, 260) so the interactive hover crosshair & tooltip render!
        uic.beginPass(pass, arena.allocator(), canvas, win_rect, 240.0, 260.0, false, false, false);
        if (pass == .input) {
            uic.markDirty(win_rect);
        } else {
            uic.clip_damage = win_rect;
        }

        var root_col = uic.column(.{
            .w = .fill,
            .h = .fill,
            .padding = ui.Padding.all(12),
            .gap = 10,
            .bg_color = uic.theme.bg_canvas,
        });

        {
            var body_row = uic.row(.{
                .w = .fill,
                .h = .fillMinus(34),
                .gap = 12,
            });
            defer body_row.end();

            // Left Column: Sparklines, Multi-Series LineChart, BarChart, and TreeView Inline Rename
            {
                var left_col = uic.column(.{
                    .w = .pixels(500),
                    .h = .fill,
                    .preset = .panel_card,
                    .padding = ui.Padding.all(12),
                    .gap = 10,
                });
                defer left_col.end();

                uic.sectionHeader("SKIA CHARTS, SPARKLINES & TREE INLINE RENAME");

                // Row of 3 Sparklines
                {
                    var spark_row = uic.row(.{ .w = .fill, .h = .pixels(44), .gap = 10 });
                    defer spark_row.end();

                    const s1 = [_]f32{ 420, 390, 410, 360, 340, 315, 295, 310, 280, 265 };
                    const s2 = [_]f32{ 98.2, 98.9, 99.1, 99.4, 99.6, 99.8, 99.9, 99.95, 99.95, 99.98 };
                    const s3 = [_]f32{ 12.0, 12.4, 12.2, 11.8, 11.5, 11.6, 11.4, 11.2, 11.1, 11.0 };

                    uic.sparkline("##sp_1", &s1, .{
                        .w = .pixels(148),
                        .h = 40.0,
                        .color = skia.Color.rgb(56, 189, 248),
                        .label = "Frame: 265 us",
                    });
                    uic.sparkline("##sp_2", &s2, .{
                        .w = .pixels(148),
                        .h = 40.0,
                        .color = skia.Color.rgb(52, 211, 153),
                        .label = "Cache: 99.95%",
                    });
                    uic.sparkline("##sp_3", &s3, .{
                        .w = .pixels(148),
                        .h = 40.0,
                        .color = skia.Color.rgb(167, 139, 250),
                        .label = "VRAM: 11.0 MB",
                    });
                }

                // Multi-Series LineChart with interactive crosshair
                const input_us = [_]f32{ 140, 155, 132, 168, 145, 128, 136, 122, 118, 115, 112, 108 };
                const paint_us = [_]f32{ 310, 295, 340, 280, 260, 245, 250, 225, 210, 198, 192, 185 };
                const series = [_]ui.ChartSeries{
                    .{ .name = "Pass.paint", .values = &paint_us, .color = skia.Color.rgb(99, 102, 241), .fill_area = true },
                    .{ .name = "Pass.input", .values = &input_us, .color = skia.Color.rgb(52, 211, 153), .fill_area = true },
                };
                _ = uic.lineChart("##demo_line_chart", &series, .{
                    .w = .fill,
                    .h = 210.0,
                    .title = "2-Phase Frame Time (Pass.input vs Pass.paint)",
                    .unit_suffix = " us",
                });

                // Interactive Vertical BarChart
                const bars = [_]ui.BarChartItem{
                    .{ .label = "TextCache", .value = 99.9, .color = skia.Color.rgb(52, 211, 153) },
                    .{ .label = "DamageCull", .value = 97.0, .color = skia.Color.rgb(56, 189, 248) },
                    .{ .label = "VirtList", .value = 94.5, .color = skia.Color.rgb(129, 140, 248) },
                    .{ .label = "DataGrid", .value = 98.2, .color = skia.Color.rgb(244, 114, 182) },
                    .{ .label = "AsyncTask", .value = 99.5, .color = skia.Color.rgb(251, 191, 36) },
                };
                _ = uic.barChart("##demo_bar_chart", &bars, .{
                    .w = .fill,
                    .h = 185.0,
                    .title = "Subsystem Efficiency Score (%)",
                    .y_max = 100.0,
                    .unit_suffix = "%",
                    .selected_index = 2,
                });

                uic.sectionHeader("HIERARCHICAL TREEVIEW INLINE RENAME");
                var folder_expanded: bool = true;
                _ = uic.treeFolderNode("src/ui", 1, &folder_expanded, "19");
                _ = uic.treeInlineInputRow(
                    64,
                    "##demo_tree_rename",
                    2,
                    "Z",
                    skia.Color.rgb(245, 158, 11),
                    &rename_buf,
                    "Rename file...",
                    .{},
                );
            }

            // Right Column: Interactive 2D Node Graph / DAG Canvas (`src/ui/node_graph.zig`)
            {
                var right_col = uic.column(.{
                    .w = .fill,
                    .h = .fill,
                    .preset = .panel_card,
                    .padding = ui.Padding.all(12),
                    .gap = 10,
                });
                defer right_col.end();

                uic.sectionHeader("INTERACTIVE 2D NODE GRAPH / LAYERED DAG CANVAS");

                const n1_out = [_]ui.GraphPin{
                    .{ .label = "Surface", .color = skia.Color.rgb(56, 189, 248) },
                    .{ .label = "Canvas", .color = skia.Color.rgb(52, 211, 153) },
                };
                const n2_in = [_]ui.GraphPin{
                    .{ .label = "Surface", .color = skia.Color.rgb(56, 189, 248) },
                };
                const n2_out = [_]ui.GraphPin{
                    .{ .label = "PlatformCtx", .color = skia.Color.rgb(251, 191, 36) },
                    .{ .label = "StateStore", .color = skia.Color.rgb(167, 139, 250) },
                };
                const n3_in = [_]ui.GraphPin{
                    .{ .label = "Canvas", .color = skia.Color.rgb(52, 211, 153) },
                    .{ .label = "PlatformCtx", .color = skia.Color.rgb(251, 191, 36) },
                    .{ .label = "StateStore", .color = skia.Color.rgb(167, 139, 250) },
                };
                const n3_out = [_]ui.GraphPin{
                    .{ .label = "ui.Context", .color = skia.Color.rgb(99, 102, 241) },
                    .{ .label = "DamageList", .color = skia.Color.rgb(244, 114, 182) },
                };
                const n4_in = [_]ui.GraphPin{
                    .{ .label = "ui.Context", .color = skia.Color.rgb(99, 102, 241) },
                    .{ .label = "DamageList", .color = skia.Color.rgb(244, 114, 182) },
                };
                const n4_out = [_]ui.GraphPin{
                    .{ .label = "120 FPS Frame", .color = skia.Color.rgb(52, 211, 153) },
                };

                const nodes = [_]ui.GraphNode{
                    .{
                        .id = 1,
                        .title = "Layer 0: src/skia",
                        .subtitle = "C-ABI & GPU RAII",
                        .default_x = -325.0,
                        .default_y = -135.0,
                        .width = 180.0,
                        .accent_color = skia.Color.rgb(56, 189, 248),
                        .outputs = &n1_out,
                        .status_badge = "0 alloc",
                    },
                    .{
                        .id = 2,
                        .title = "Layer 1: src/platform",
                        .subtitle = "Metal Host & AsyncTask",
                        .default_x = -325.0,
                        .default_y = 65.0,
                        .width = 180.0,
                        .accent_color = skia.Color.rgb(251, 191, 36),
                        .inputs = &n2_in,
                        .outputs = &n2_out,
                        .status_badge = "dlopen",
                    },
                    .{
                        .id = 3,
                        .title = "Layer 2: src/ui",
                        .subtitle = "2-Phase Hybrid Toolkit",
                        .default_x = -75.0,
                        .default_y = -130.0,
                        .width = 190.0,
                        .accent_color = skia.Color.rgb(99, 102, 241),
                        .inputs = &n3_in,
                        .outputs = &n3_out,
                        .status_badge = "ACTIVE",
                    },
                    .{
                        .id = 4,
                        .title = "Layer 3: src/app",
                        .subtitle = "Declarative Workbench",
                        .default_x = 115.0,
                        .default_y = 55.0,
                        .width = 190.0,
                        .accent_color = skia.Color.rgb(52, 211, 153),
                        .inputs = &n4_in,
                        .outputs = &n4_out,
                        .status_badge = "69 KB",
                    },
                };

                const edges = [_]ui.GraphEdge{
                    .{ .from_node = 1, .from_pin = 0, .to_node = 2, .to_pin = 0, .active = true },
                    .{ .from_node = 1, .from_pin = 1, .to_node = 3, .to_pin = 0, .active = true },
                    .{ .from_node = 2, .from_pin = 0, .to_node = 3, .to_pin = 1, .active = true },
                    .{ .from_node = 2, .from_pin = 1, .to_node = 3, .to_pin = 2, .active = false },
                    .{ .from_node = 3, .from_pin = 0, .to_node = 4, .to_pin = 0, .active = true },
                    .{ .from_node = 3, .from_pin = 1, .to_node = 4, .to_pin = 1, .active = true },
                };

                _ = uic.nodeGraph(8, "##demo_node_graph", &graph_state, &nodes, &edges, .{
                    .w = .fill,
                    .h = .fill,
                });
            }
        }

        // Bottom Responsive Mode-Line (`src/ui/mode_line.zig`)
        {
            const ml_rect = uic.nextRect(uic.resolveSize(.fill, true), 26.0);
            var ml = uic.beginModeLine("##demo_modeline", ml_rect, .{
                .is_active_pane = true,
            });
            ml.drawWindowNumberBadge(1, true);
            ml.drawTitle("src/ui/node_graph.zig", true, true);
            ml.drawBadgePill(
                "DAG",
                skia.Color.rgb(56, 189, 248),
                skia.Color.argb(45, 56, 189, 248),
                skia.Color.argb(120, 56, 189, 248),
            );
            ml.drawText("Top L1:1", uic.font_mono, uic.theme.text_primary, 14.0);
            _ = ml.drawGitBranchPill("##ml_git", "main*", true, false);
            ml.drawText("(Zig • 4 Nodes • 6 Edges)", uic.font_mono, uic.theme.text_muted, 12.0);

            _ = ml.drawRightIconAction("##ml_split_v", .split_down, "Split Down");
            _ = ml.drawRightIconAction("##ml_split_h", .split_right, "Split Right");
            _ = ml.drawRightStatusPill("##ml_lsp", uic.theme.success, "ZLS: 0 Errors", uic.theme.text_primary, false);
            _ = ml.drawRightStatusPill("##ml_sc", skia.Color.rgb(52, 211, 153), "Supercomplete", skia.Color.rgb(52, 211, 153), false);
        }

        root_col.end();
        uic.endPass();
    }

    canvas.restore();

    const png_data = try surface.encodePng();
    defer png_data.deinit();
    try writeFileBytes(out_png_path, png_data.slice());
    return png_data.slice().len;
}

pub fn main() !void {
    const font_mgr = try skia.FontMgr.initDefault();
    defer font_mgr.deinit();

    const studio_png = "zig-out/render_studio.png";
    const showcase_png = "zig-out/render_framework_showcase.png";
    const editor_png = "zig-out/render_editor.png";

    // 1. Render Studio with taller window (1200x960) so full sidebar + "+ Increment Counter" toast are visible
    const studio_steps = [_]SyntheticStep{
        .{ .mouse_x = 122.0, .mouse_y = 262.0, .click = true }, // Click "Lattice" segment
        .{ .mouse_x = 122.0, .mouse_y = 928.0, .click = true }, // Click "+ Increment Counter" to push toast
    };
    const studio_bytes = try renderDylibToPng(
        font_mgr,
        "zig-out/lib/libexample_studio.dylib",
        studio_png,
        1200.0,
        960.0,
        2.0,
        &studio_steps,
    );
    std.debug.print("1. Rendered Studio Showcase -> {s} ({d} bytes)\n", .{ studio_png, studio_bytes });

    // 2. Render Comprehensive Framework Primitives Gallery
    const showcase_bytes = try renderFrameworkShowcaseToPng(font_mgr, showcase_png);
    std.debug.print("2. Rendered UI Framework Primitives Gallery -> {s} ({d} bytes)\n", .{ showcase_png, showcase_bytes });

    // 3. Render Editor Workbench: Toggle Explorer sidebar (Cmd+B), open Agent Panel (Cmd+Shift+A), and open Command Palette (Cmd+Shift+P)
    const editor_steps = [_]SyntheticStep{
        .{ .key = .{ .key = .key_b, .cmd = true } }, // Toggle Explorer sidebar open
        .{ .mouse_x = 18.0, .mouse_y = 716.0, .click = true }, // Click Agent Sparkle icon on activity bar
        .{ .key = .{ .key = .key_p, .cmd = true, .shift = true } }, // Open Command Palette overlay
        .{ .text = "split" }, // Filter Command Palette by "split" to show ranked fuzzy matches
    };
    const editor_bytes = try renderDylibToPng(
        font_mgr,
        "zig-out/lib/libeditor_app.dylib",
        editor_png,
        1280.0,
        800.0,
        2.0,
        &editor_steps,
    );
    std.debug.print("3. Rendered Lightning Editor Workbench -> {s} ({d} bytes)\n", .{ editor_png, editor_bytes });

    // 4. Render Charts, Node Graph, TreeView & ModeLine Showcase
    const charts_graph_png = "zig-out/render_charts_and_node_graph.png";
    const charts_graph_bytes = try renderChartsAndNodeGraphToPng(font_mgr, charts_graph_png);
    std.debug.print("4. Rendered Charts & NodeGraph Showcase -> {s} ({d} bytes)\n", .{ charts_graph_png, charts_graph_bytes });
}
