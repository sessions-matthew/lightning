//! Interactive 2D Node Graph / DAG Canvas (`src/ui/node_graph.zig`).
//!
//! Built on top of `Viewport2DState` and `beginCanvasStage` (`src/ui/stage.zig`), supporting:
//!   - Pan & cursor-anchored zoom across a procedural 2D grid stage
//!   - Draggable node cards (`GraphNode`) with titles, subtitles, status badges, and typed input/output pins (`GraphPin`)
//!   - Cubic Bézier connection wires (`GraphEdge`) with active glow and midpoint directional indicators
//!   - Top-most node hit-testing, click selection, and world-space node dragging that suppresses background stage panning

const std = @import("std");
const skia = @import("skia");
const layout = @import("layout.zig");
const stage_mod = @import("stage.zig");
const root = @import("root.zig");
const Color = skia.Color;
const Rect = skia.Rect;
const Context = root.Context;

pub const GraphPin = struct {
    label: []const u8,
    color: u32 = 0,
};

pub const GraphNode = struct {
    id: u16,
    title: []const u8,
    subtitle: []const u8 = "",
    default_x: f32 = 0.0,
    default_y: f32 = 0.0,
    width: f32 = 164.0,
    accent_color: u32 = 0,
    inputs: []const GraphPin = &.{},
    outputs: []const GraphPin = &.{},
    status_badge: []const u8 = "",
};

pub const GraphEdge = struct {
    from_node: u16,
    from_pin: u8 = 0,
    to_node: u16,
    to_pin: u8 = 0,
    color: ?u32 = null,
    active: bool = false,
};

pub fn NodeGraphState(comptime max_nodes: usize) type {
    return struct {
        viewport: stage_mod.Viewport2DState = .{},
        node_x: [max_nodes]f32 = @splat(0.0),
        node_y: [max_nodes]f32 = @splat(0.0),
        initialized_count: usize = 0,
        selected_node: ?u16 = null,
        dragging_node_idx: ?usize = null,
        drag_start_world_x: f32 = 0.0,
        drag_start_world_y: f32 = 0.0,
        drag_orig_node_x: f32 = 0.0,
        drag_orig_node_y: f32 = 0.0,

        pub fn reset(self: *@This()) void {
            self.viewport.reset();
            self.initialized_count = 0;
            self.selected_node = null;
            self.dragging_node_idx = null;
        }
    };
}

pub const NodeGraphOptions = struct {
    w: layout.Size = .fill,
    h: layout.Size = .fill,
    bg_color: ?u32 = null,
    border_color: ?u32 = null,
    corner_radius: f32 = 12.0,
    show_grid: bool = true,
    grid_step: f32 = 36.0,
    wheel_zooms: bool = true,
};

pub const NodeGraphResult = struct {
    selected_node: ?u16 = null,
    clicked_node: ?u16 = null,
    hovered_node: ?u16 = null,
    dragged_node: ?u16 = null,
    rect: layout.Rect = .{ .left = 0, .top = 0, .right = 0, .bottom = 0 },
};

const NODE_PIN_ROW_H: f32 = 22.0;
const NODE_BODY_PAD_Y: f32 = 8.0;

pub fn nodeHeaderHeight(node: GraphNode) f32 {
    return if (node.subtitle.len > 0) 42.0 else 28.0;
}

pub fn measureNodeHeight(node: GraphNode) f32 {
    const hdr_h = nodeHeaderHeight(node);
    const pin_rows = @max(node.inputs.len, node.outputs.len);
    const body_pad = if (pin_rows > 0) NODE_BODY_PAD_Y else 5.0;
    return hdr_h + body_pad * 2.0 + @as(f32, @floatFromInt(pin_rows)) * NODE_PIN_ROW_H;
}

pub fn effectiveNodeWidth(uic: *Context, node: GraphNode) f32 {
    var min_w = node.width;
    const title_w = uic.measureTextCached(uic.font_body, node.title);
    const badge_w = if (node.status_badge.len > 0)
        uic.measureTextCached(uic.font_mono, node.status_badge) + 18.0
    else
        0.0;
    min_w = @max(min_w, title_w + badge_w + 24.0);

    if (node.subtitle.len > 0) {
        const sub_w = uic.measureTextCached(uic.font_mono, node.subtitle) + 20.0;
        min_w = @max(min_w, sub_w);
    }

    const pin_rows = @max(node.inputs.len, node.outputs.len);
    for (0..pin_rows) |r_idx| {
        const in_w = if (r_idx < node.inputs.len and node.inputs[r_idx].label.len > 0)
            uic.measureTextCached(uic.font_mono, node.inputs[r_idx].label)
        else
            0.0;
        const out_w = if (r_idx < node.outputs.len and node.outputs[r_idx].label.len > 0)
            uic.measureTextCached(uic.font_mono, node.outputs[r_idx].label)
        else
            0.0;
        const gap: f32 = if (in_w > 0.0 and out_w > 0.0) 36.0 else 22.0;
        min_w = @max(min_w, in_w + out_w + gap);
    }
    return min_w;
}

pub fn nodeWorldRect(node: GraphNode, x: f32, y: f32) layout.Rect {
    return Rect.xywh(x, y, node.width, measureNodeHeight(node));
}

pub fn inputPinWorldPos(node: GraphNode, nx: f32, ny: f32, pin_idx: usize) struct { x: f32, y: f32 } {
    const hdr_h = nodeHeaderHeight(node);
    return .{
        .x = nx,
        .y = ny + hdr_h + NODE_BODY_PAD_Y + (@as(f32, @floatFromInt(pin_idx)) + 0.5) * NODE_PIN_ROW_H,
    };
}

pub fn outputPinWorldPos(node: GraphNode, nx: f32, ny: f32, pin_idx: usize) struct { x: f32, y: f32 } {
    return outputPinWorldPosWithWidth(node, nx, ny, node.width, pin_idx);
}

pub fn outputPinWorldPosWithWidth(node: GraphNode, nx: f32, ny: f32, node_w: f32, pin_idx: usize) struct { x: f32, y: f32 } {
    const hdr_h = nodeHeaderHeight(node);
    return .{
        .x = nx + node_w,
        .y = ny + hdr_h + NODE_BODY_PAD_Y + (@as(f32, @floatFromInt(pin_idx)) + 0.5) * NODE_PIN_ROW_H,
    };
}

fn findNodeIndexById(nodes: []const GraphNode, node_count: usize, id: u16) ?usize {
    for (nodes[0..node_count], 0..) |n, idx| {
        if (n.id == id) return idx;
    }
    return null;
}

pub fn nodeGraph(
    uic: *Context,
    comptime max_nodes: usize,
    id_str: []const u8,
    state: *NodeGraphState(max_nodes),
    nodes: []const GraphNode,
    edges: []const GraphEdge,
    opts: NodeGraphOptions,
) NodeGraphResult {
    const node_count = @min(nodes.len, max_nodes);

    if (state.initialized_count < node_count) {
        for (state.initialized_count..node_count) |i| {
            state.node_x[i] = nodes[i].default_x;
            state.node_y[i] = nodes[i].default_y;
        }
        state.initialized_count = node_count;
    }

    const stage = uic.beginCanvasStage(id_str, &state.viewport, .{
        .w = opts.w,
        .h = opts.h,
        .bg_color = opts.bg_color,
        .border_color = opts.border_color,
        .corner_radius = opts.corner_radius,
        .show_grid = opts.show_grid,
        .grid_step = opts.grid_step,
        .apply_world_transform = true,
        .wheel_zooms = opts.wheel_zooms,
        .left_drag_pans = (state.dragging_node_idx == null),
    });
    defer stage.end();

    const stage_rect = stage.rect;
    var result = NodeGraphResult{
        .selected_node = state.selected_node,
        .rect = stage_rect,
    };

    if (uic.pass == .input) {
        const world_pt = state.viewport.screenToWorld(stage_rect, uic.mouse_x, uic.mouse_y);
        const stage_hovered = uic.isHovered(stage_rect);

        var hit_idx: ?usize = null;
        if (stage_hovered and node_count > 0) {
            var rev: usize = node_count;
            while (rev > 0) {
                rev -= 1;
                const nw = effectiveNodeWidth(uic, nodes[rev]);
                const nr = Rect.xywh(state.node_x[rev], state.node_y[rev], nw, measureNodeHeight(nodes[rev]));
                if (world_pt.x >= nr.left and world_pt.x <= nr.right and
                    world_pt.y >= nr.top and world_pt.y <= nr.bottom)
                {
                    hit_idx = rev;
                    break;
                }
            }
        }

        if (hit_idx) |h_idx| {
            result.hovered_node = nodes[h_idx].id;
            uic.setCursor(.pointing_hand);

            if (uic.mouse_pressed) {
                state.selected_node = nodes[h_idx].id;
                result.selected_node = nodes[h_idx].id;
                result.clicked_node = nodes[h_idx].id;
                state.dragging_node_idx = h_idx;
                state.drag_start_world_x = world_pt.x;
                state.drag_start_world_y = world_pt.y;
                state.drag_orig_node_x = state.node_x[h_idx];
                state.drag_orig_node_y = state.node_y[h_idx];

                // Prevent background stage panning while clicking/dragging a node
                state.viewport.is_panning = false;
                state.viewport.pan_x = state.viewport.pan_orig_x;
                state.viewport.pan_y = state.viewport.pan_orig_y;
                uic.markDirty(stage_rect);
            }
        }

        if (state.dragging_node_idx) |d_idx| {
            if (d_idx < node_count and uic.mouse_down) {
                state.viewport.is_panning = false;
                const next_nx = state.drag_orig_node_x + (world_pt.x - state.drag_start_world_x);
                const next_ny = state.drag_orig_node_y + (world_pt.y - state.drag_start_world_y);
                if (@abs(next_nx - state.node_x[d_idx]) > 0.001 or @abs(next_ny - state.node_y[d_idx]) > 0.001) {
                    state.node_x[d_idx] = next_nx;
                    state.node_y[d_idx] = next_ny;
                    uic.markDirty(stage_rect);
                }
                result.dragged_node = nodes[d_idx].id;
                uic.setCursor(.pointing_hand);
            }
            if (uic.mouse_released or !uic.mouse_down) {
                state.dragging_node_idx = null;
                uic.markDirty(stage_rect);
            }
        }
    }

    if (stage.painting) {
        // 1. Draw Cubic Bézier Connection Wires
        for (edges) |edge| {
            const from_idx = findNodeIndexById(nodes, node_count, edge.from_node) orelse continue;
            const to_idx = findNodeIndexById(nodes, node_count, edge.to_node) orelse continue;

            const from_node = nodes[from_idx];
            const to_node = nodes[to_idx];
            const from_w = effectiveNodeWidth(uic, from_node);
            const p0 = outputPinWorldPosWithWidth(from_node, state.node_x[from_idx], state.node_y[from_idx], from_w, edge.from_pin);
            const p1 = inputPinWorldPos(to_node, state.node_x[to_idx], state.node_y[to_idx], edge.to_pin);

            const x0 = p0.x;
            const y0 = p0.y;
            const x1 = p1.x;
            const y1 = p1.y;
            const ctrl_dx = @max(44.0, @abs(x1 - x0) * 0.45);

            const pb = skia.PathBuilder.init() catch continue;
            defer pb.deinit();
            pb.moveTo(x0, y0);
            pb.cubicTo(x0 + ctrl_dx, y0, x1 - ctrl_dx, y1, x1, y1);

            const pin_col: u32 = if (edge.from_pin < from_node.outputs.len and from_node.outputs[edge.from_pin].color != 0)
                from_node.outputs[edge.from_pin].color
            else if (from_node.accent_color != 0)
                from_node.accent_color
            else
                uic.theme.accent;
            const wire_col = edge.color orelse pin_col;

            if (pb.detach()) |wire_path| {
                defer wire_path.deinit();
                uic.paint.setStyle(.stroke);
                uic.paint.setStrokeCap(.round);
                uic.paint.setStrokeJoin(.round);

                if (edge.active) {
                    uic.paint.setStrokeWidth(6.0);
                    uic.paint.setColor(Color.withAlpha(wire_col, 55));
                    uic.canvas.drawPath(wire_path, uic.paint);

                    uic.paint.setStrokeWidth(2.4);
                    uic.paint.setColor(wire_col);
                    uic.canvas.drawPath(wire_path, uic.paint);
                } else {
                    uic.paint.setStrokeWidth(1.75);
                    uic.paint.setColor(Color.withAlpha(wire_col, 195));
                    uic.canvas.drawPath(wire_path, uic.paint);
                }

                uic.paint.setStrokeCap(.butt);
                uic.paint.setStrokeJoin(.miter);
            } else |_| {}

            // Midpoint directional dot (t = 0.5 on symmetric horizontal-tangent cubic Bézier)
            const mid_x = (x0 + x1) * 0.5;
            const mid_y = (y0 + y1) * 0.5;
            uic.paint.setStyle(.fill);
            if (edge.active) {
                uic.paint.setColor(Color.withAlpha(wire_col, 85));
                uic.canvas.drawCircle(mid_x, mid_y, 5.0, uic.paint);
                uic.paint.setColor(Color.white);
                uic.canvas.drawCircle(mid_x, mid_y, 2.5, uic.paint);
            } else {
                uic.paint.setColor(wire_col);
                uic.canvas.drawCircle(mid_x, mid_y, 2.5, uic.paint);
            }
        }

        // 2. Draw Node Cards
        for (nodes[0..node_count], 0..) |node, i| {
            const nx = state.node_x[i];
            const ny = state.node_y[i];
            const node_w = effectiveNodeWidth(uic, node);
            const node_h = measureNodeHeight(node);
            const hdr_h = nodeHeaderHeight(node);
            const node_r = Rect.xywh(nx, ny, node_w, node_h);
            const is_selected = (state.selected_node != null and state.selected_node.? == node.id);
            const is_dragging = (state.dragging_node_idx != null and state.dragging_node_idx.? == i);
            const accent = if (node.accent_color != 0) node.accent_color else uic.theme.accent;

            // Drop shadow
            uic.paint.setStyle(.fill);
            uic.paint.setColor(Color.argb(95, 2, 6, 23));
            uic.canvas.drawRoundRect(Rect.xywh(nx + 2.0, ny + 4.0, node_w, node_h), 8.0, 8.0, uic.paint);

            // Dark rounded card body
            uic.paint.setColor(Color.rgb(22, 29, 44));
            uic.canvas.drawRoundRect(node_r, 8.0, 8.0, uic.paint);

            // Colored top header banner
            {
                const hdr_save = uic.canvas.save();
                defer uic.canvas.restoreToCount(hdr_save);
                uic.canvas.clipRect(Rect.xywh(nx, ny, node_w, hdr_h), .intersect, false);

                uic.paint.setStyle(.fill);
                uic.paint.setColor(Color.withAlpha(accent, 52));
                uic.canvas.drawRoundRect(node_r, 8.0, 8.0, uic.paint);

                uic.paint.setColor(accent);
                uic.canvas.drawRect(Rect.xywh(nx, ny, node_w, 2.5), uic.paint);

                uic.paint.setColor(Color.argb(80, 100, 116, 139));
                uic.canvas.drawRect(Rect.xywh(nx, ny + hdr_h - 1.0, node_w, 1.0), uic.paint);

                uic.paint.setColor(uic.theme.text_primary);
                uic.drawTextCached(uic.font_body, node.title, nx + 10.0, ny + 18.0);

                if (node.status_badge.len > 0) {
                    const bw = uic.measureTextCached(uic.font_mono, node.status_badge) + 10.0;
                    const badge_r = Rect.xywh(nx + node_w - bw - 8.0, ny + 6.0, bw, 16.0);
                    uic.paint.setColor(Color.withAlpha(accent, 85));
                    uic.canvas.drawRoundRect(badge_r, 4.0, 4.0, uic.paint);
                    uic.paint.setColor(uic.theme.text_primary);
                    uic.drawTextCached(uic.font_mono, node.status_badge, badge_r.left + 5.0, badge_r.top + 12.0);
                }

                if (node.subtitle.len > 0) {
                    uic.paint.setColor(uic.theme.text_muted);
                    uic.drawTextCached(uic.font_mono, node.subtitle, nx + 10.0, ny + 34.0);
                }
            }

            // Input pins on left edge
            for (node.inputs, 0..) |pin, p_idx| {
                const pt = inputPinWorldPos(node, nx, ny, p_idx);
                const pin_col = if (pin.color != 0) pin.color else accent;

                uic.paint.setStyle(.fill);
                uic.paint.setColor(Color.rgb(15, 23, 42));
                uic.canvas.drawCircle(pt.x, pt.y, 5.5, uic.paint);
                uic.paint.setColor(pin_col);
                uic.canvas.drawCircle(pt.x, pt.y, 3.75, uic.paint);

                if (pin.label.len > 0) {
                    uic.paint.setColor(Color.rgb(203, 213, 225));
                    uic.drawTextCached(uic.font_mono, pin.label, nx + 9.0, pt.y + 4.0);
                }
            }

            // Output pins on right edge
            for (node.outputs, 0..) |pin, p_idx| {
                const pt = outputPinWorldPosWithWidth(node, nx, ny, node_w, p_idx);
                const pin_col = if (pin.color != 0) pin.color else accent;

                uic.paint.setStyle(.fill);
                uic.paint.setColor(Color.rgb(15, 23, 42));
                uic.canvas.drawCircle(pt.x, pt.y, 5.5, uic.paint);
                uic.paint.setColor(pin_col);
                uic.canvas.drawCircle(pt.x, pt.y, 3.75, uic.paint);

                if (pin.label.len > 0) {
                    const lw = uic.measureTextCached(uic.font_mono, pin.label);
                    uic.paint.setColor(Color.rgb(203, 213, 225));
                    uic.drawTextCached(uic.font_mono, pin.label, nx + node_w - 9.0 - lw, pt.y + 4.0);
                }
            }

            // Border & selection accent ring
            uic.paint.setStyle(.stroke);
            if (is_selected or is_dragging) {
                uic.paint.setStrokeWidth(3.5);
                uic.paint.setColor(Color.withAlpha(accent, 90));
                uic.canvas.drawRoundRect(Rect.outset(node_r, 1.5, 1.5), 9.0, 9.0, uic.paint);

                uic.paint.setStrokeWidth(1.75);
                uic.paint.setColor(accent);
                uic.canvas.drawRoundRect(node_r, 8.0, 8.0, uic.paint);
            } else {
                uic.paint.setStrokeWidth(1.0);
                uic.paint.setColor(uic.theme.border_subtle);
                uic.canvas.drawRoundRect(node_r, 8.0, 8.0, uic.paint);
            }
        }
    }

    return result;
}

pub const renderNodeGraph = nodeGraph;

// ============================================================================
// Unit Tests
// ============================================================================

test "nodeGraph: default initialization, node hit-testing, click selection, and world-space dragging without background pan" {
    const surface = try skia.Surface.initRasterN32Premul(600, 400);
    defer surface.deinit();
    const paint = try skia.Paint.init();
    defer paint.deinit();
    const font = try skia.Font.init(null, 13.0);
    defer font.deinit();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var uic = Context{
        .arena = arena.allocator(),
        .canvas = surface.canvas(),
        .paint = paint,
        .font_title = font,
        .font_body = font,
        .font_mono = font,
    };
    defer uic.deinit();

    const win_rect = Rect.xywh(0, 0, 600, 400);
    var graph_state = NodeGraphState(16){};

    const nodes = [_]GraphNode{
        .{
            .id = 10,
            .title = "Source Tokenizer",
            .subtitle = "zig_lexer.zig",
            .default_x = -180.0,
            .default_y = -60.0,
            .width = 160.0,
            .accent_color = Color.rgb(59, 130, 246),
            .outputs = &[_]GraphPin{.{ .label = "tokens", .color = Color.rgb(59, 130, 246) }},
            .status_badge = "OK",
        },
        .{
            .id = 20,
            .title = "AST Parser",
            .subtitle = "ast_builder.zig",
            .default_x = 40.0,
            .default_y = -40.0,
            .width = 164.0,
            .accent_color = Color.rgb(16, 185, 129),
            .inputs = &[_]GraphPin{.{ .label = "tokens", .color = Color.rgb(59, 130, 246) }},
            .outputs = &[_]GraphPin{.{ .label = "ast", .color = Color.rgb(16, 185, 129) }},
            .status_badge = "1.2ms",
        },
    };
    const edges = [_]GraphEdge{
        .{ .from_node = 10, .from_pin = 0, .to_node = 20, .to_pin = 0, .active = true },
    };

    // 1. First frame: initializes node positions from default_x / default_y
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 0, 0, false, false, false);
    _ = uic.nodeGraph(16, "##dag_canvas", &graph_state, &nodes, &edges, .{});
    uic.endPass();

    try std.testing.expectEqual(@as(usize, 2), graph_state.initialized_count);
    try std.testing.expectApproxEqAbs(@as(f32, -180.0), graph_state.node_x[0], 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, -60.0), graph_state.node_y[0], 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 40.0), graph_state.node_x[1], 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, -40.0), graph_state.node_y[1], 0.01);

    // 2. Press on Node 1 (id = 20, world rect x = 40..204, y = -40..+36 -> screen center is (300, 200), so screen (380, 180) is world (80, -20))
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 380.0, 180.0, true, true, false);
    const press_res = uic.nodeGraph(16, "##dag_canvas", &graph_state, &nodes, &edges, .{});
    uic.endPass();

    try std.testing.expectEqual(@as(?u16, 20), graph_state.selected_node);
    try std.testing.expectEqual(@as(?u16, 20), press_res.clicked_node);
    try std.testing.expectEqual(@as(?usize, 1), graph_state.dragging_node_idx);
    try std.testing.expect(!graph_state.viewport.is_panning);

    // 3. Drag mouse by (+50, +30) to screen (430, 210) -> moves Node 1 to (90, -10) while keeping viewport pan at (0, 0)
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 430.0, 210.0, true, false, false);
    const drag_res = uic.nodeGraph(16, "##dag_canvas", &graph_state, &nodes, &edges, .{});
    uic.endPass();

    try std.testing.expectEqual(@as(?u16, 20), drag_res.dragged_node);
    try std.testing.expectApproxEqAbs(@as(f32, 90.0), graph_state.node_x[1], 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, -10.0), graph_state.node_y[1], 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), graph_state.viewport.pan_x, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), graph_state.viewport.pan_y, 0.01);

    // Replay paint pass and verify two-phase layout rect count determinism
    uic.clip_damage = win_rect;
    uic.beginPass(.paint, arena.allocator(), surface.canvas(), win_rect, 430.0, 210.0, true, false, false);
    _ = uic.nodeGraph(16, "##dag_canvas", &graph_state, &nodes, &edges, .{});
    uic.endPass();
    try std.testing.expectEqual(uic.last_input_rect_count, uic.last_paint_rect_count);

    // 4. Release mouse ends node dragging
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 430.0, 210.0, false, false, true);
    _ = uic.nodeGraph(16, "##dag_canvas", &graph_state, &nodes, &edges, .{});
    uic.endPass();
    try std.testing.expectEqual(@as(?usize, null), graph_state.dragging_node_idx);
}
