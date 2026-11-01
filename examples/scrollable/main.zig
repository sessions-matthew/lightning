//! Dedicated Scrollable Containers & Virtualized List Showcase (`libexample_scrollable.dylib`).
//! Run with: `zig build run-scrollable` (and hot-reload live with `zig build example-scrollable`).

const std = @import("std");
const ui = @import("ui");
const platform = @import("platform");
const PlatformContext = platform.PlatformContext;

const STATE_VERSION: u64 = 0x2026_1019_5C82;

const FilterConfig = struct {
    item_count: f32 = 40.0,
    compact_rows: bool = false,
    show_dirty_overlay: bool = true,
};

const ScrollDemoState = struct {
    frame_arena: std.heap.ArenaAllocator,
    fonts: ui.FontSet,
    ui_ctx: ui.Context,
    config: FilterConfig = .{},

    pub fn init(self: *ScrollDemoState, ctx: *PlatformContext) void {
        self.fonts = ui.FontSet.init(ctx, .{});
        self.ui_ctx = self.fonts.initContext(self.frame_arena.allocator(), ctx);
    }

    pub fn deinit(self: *ScrollDemoState) void {
        self.ui_ctx.deinit();
        self.fonts.deinit();
        self.frame_arena.deinit();
    }
};

comptime {
    ui.exportPlugin(ScrollDemoState, "config", STATE_VERSION, buildUi);
}

fn buildUi(state: *ScrollDemoState, ctx: *PlatformContext) void {
    const uic = &state.ui_ctx;
    var scope = uic.scopedState("scrollable_demo");
    defer scope.end();

    const selected_item = uic.useState(usize, "selected_item", 0);

    // 1. Unified Titlebar
    uic.titlebar("Example: Scrollable Containers", &.{
        .{ .text = uic.fmt("SELECTED: #{d}", .{selected_item.*}), .accent = true },
        .{ .text = uic.fmt("HOOKS: {d}", .{ctx.stateEntryCount()}) },
    });

    // 2. Two Independent Side-by-Side Scrollable Containers
    var workspace = uic.row(.{ .preset = .workspace });
    defer workspace.end();

    // Left Scrollable Sidebar: Controls + 20 Inspector Items
    {
        var left = uic.scrollPanel("left_inspector_scroll", .{
            .w = .pixels(290),
            .preset = .panel_card,
        });
        defer left.end();

        uic.sectionHeader("SCROLL DEMO SETTINGS");
        _ = uic.sliderFloat("Right List Items", &state.config.item_count, 5.0, 120.0);
        _ = uic.checkbox("Show Scissor Outline", &state.config.show_dirty_overlay);

        uic.sectionHeader("SCROLLABLE INSPECTOR ITEMS");
        for (0..20) |idx| {
            var item_id = uic.scopedId(idx);
            defer item_id.end();
            const label_str = uic.fmt("Inspector Section #{d}", .{idx + 1});
            if (uic.tab(label_str, selected_item.* == idx)) {
                selected_item.* = idx;
            }
        }
    }

    // Right Scrollable Feed: Horizontal + Vertical (2D) Scrolling Showcase
    {
        var right = uic.scrollPanel("right_feed_scroll", .{
            .preset = .panel_card,
        });
        defer right.end();

        uic.heading("Independent 2D Scrollable Feed");
        uic.label("Use trackpad two-finger scroll (vertical & horizontal) or drag either scrollbar thumb.", null);

        uic.sectionHeader("HORIZONTAL SCROLL STRIP (WIDE PIPELINE STAGES)");
        {
            var h_strip = uic.scrollPanel("horizontal_pipeline_scroll", .{
                .direction = .row,
                .h = .pixels(68),
                .preset = .surface_card,
                .padding = ui.Padding.all(10),
                .gap = 10,
            });
            defer h_strip.end();

            const stages = [_][]const u8{
                "1. Input Pass (CPU)",
                "2. Layout & ID Stack",
                "3. Damage Union",
                "4. Metal CommandBuf",
                "5. Hardware Scissor",
                "6. SkTextBlob Cache",
                "7. Ganesh GPU Flush",
                "8. CAMetalDrawable",
            };
            for (stages, 0..) |stage, s_idx| {
                var stage_id = uic.scopedId(s_idx);
                defer stage_id.end();
                if (uic.btn(stage, .{ .w = .pixels(185), .h = 38 })) {
                    selected_item.* = s_idx;
                }
            }
        }

        uic.divider();
        uic.sectionHeader("VERTICAL FEED ITEMS");

        const count: usize = @intFromFloat(@round(state.config.item_count));
        for (0..count) |i| {
            var item_id = uic.scopedId(i);
            defer item_id.end();
            const btn_label = uic.fmt("Select Feed Item #{d}  —  Click to highlight in titlebar", .{i});
            if (uic.tab(btn_label, selected_item.* == i)) {
                selected_item.* = i;
            }
        }
    }
}
