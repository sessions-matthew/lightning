//! Generic Recursive Binary Split Tree, 5-Zone Dock Drop Target Detection,
//! and Live Tab Drag-and-Drop Reordering for `src/ui/`.

const std = @import("std");
const skia = @import("skia");
const root = @import("root.zig");
const c = skia.c;
const Color = skia.Color;
const Rect = skia.Rect;
const Context = root.Context;
const Size = root.Size;
const WidgetId = root.WidgetId;

/// Node in a recursive binary split tree.
/// - `is_split == false`: leaf node rendering `pane_idx`.
/// - `is_split == true`: internal split branch dividing `first` and `second` child nodes
///   either horizontally (`vertical == false`, left/right) or vertically (`vertical == true`, top/bottom).
pub const SplitNode = struct {
    is_split: bool = false,
    vertical: bool = false,
    pane_idx: u8 = 0,
    first: u8 = 0,
    second: u8 = 0,
    ratio: f32 = 0.5,
};

/// 5-zone dock drop regions within a target split pane.
pub const DockDropZone = enum {
    center,
    left,
    right,
    top,
    bottom,
};

/// Result of hit-testing a dragged tab/panel against open split panes.
pub const DockDropTarget = struct {
    target_pane: usize,
    zone: DockDropZone,
    preview_rect: c.sk_rect_t,
};

/// Completed cross-pane or edge-split tab drop operation.
pub const CompletedTabDrop = struct {
    src_pane: usize,
    src_tab: usize,
    drop: DockDropTarget,
};

/// Pair of tab indices inside a pane to swap during live horizontal tab-bar dragging.
pub const TabReorderSwap = struct {
    idx_a: usize,
    idx_b: usize,
};

/// Generic fixed-capacity tab group for a single split pane.
/// Serializable directly via `std.json` for hot-reload persistence.
pub fn PaneTabGroup(comptime max_tabs: usize) type {
    return struct {
        const Self = @This();
        pub const MaxTabs = max_tabs;

        tabs: [max_tabs]u16 = @splat(0),
        tab_count: u8 = 0,
        active_tab: u8 = 0,

        pub fn count(self: *const Self) usize {
            return @min(@as(usize, self.tab_count), max_tabs);
        }

        pub fn activeSlot(self: *const Self) ?usize {
            const n = self.count();
            if (n == 0) return null;
            return @min(@as(usize, self.active_tab), n - 1);
        }

        pub fn activeItem(self: *const Self, total_items: usize) ?usize {
            const slot = self.activeSlot() orelse return null;
            if (total_items == 0) return null;
            return @as(usize, self.tabs[slot]) % total_items;
        }

        pub fn setSingleItem(self: *Self, item_id: u16) void {
            self.tabs[0] = item_id;
            self.tab_count = 1;
            self.active_tab = 0;
        }

        pub fn clear(self: *Self) void {
            self.tab_count = 0;
            self.active_tab = 0;
        }

        pub fn removeTabSlot(self: *Self, tab_idx: usize) bool {
            const n = self.count();
            if (tab_idx >= n) return false;
            var i = tab_idx;
            while (i + 1 < n) : (i += 1) {
                self.tabs[i] = self.tabs[i + 1];
            }
            self.tab_count = @intCast(n - 1);
            if (self.tab_count == 0) {
                self.active_tab = 0;
            } else if (self.active_tab >= self.tab_count) {
                self.active_tab = self.tab_count - 1;
            } else if (tab_idx < self.active_tab and self.active_tab > 0) {
                self.active_tab -= 1;
            }
            return true;
        }

        pub fn swapTabs(self: *Self, idx_a: usize, idx_b: usize) bool {
            const n = self.count();
            if (idx_a >= n or idx_b >= n or idx_a == idx_b) return false;
            const tmp = self.tabs[idx_a];
            self.tabs[idx_a] = self.tabs[idx_b];
            self.tabs[idx_b] = tmp;

            if (self.active_tab == idx_a) {
                self.active_tab = @intCast(idx_b);
            } else if (self.active_tab == idx_b) {
                self.active_tab = @intCast(idx_a);
            }
            return true;
        }
    };
}

/// Tracks interactive tab dragging across both horizontal tab strips (for live in-bar reordering)
/// and split panes (for cross-pane moving and edge-dock splitting).
pub const TabDragState = struct {
    active: bool = false,
    moved: bool = false,
    pane: u8 = 0,
    tab_idx: u8 = 0,
    wid: WidgetId = 0,
    start_x: f32 = 0,
    start_y: f32 = 0,

    pub fn begin(
        self: *TabDragState,
        pane_idx: usize,
        tab_idx: usize,
        wid: WidgetId,
        mouse_x: f32,
        mouse_y: f32,
    ) void {
        self.active = true;
        self.moved = false;
        self.pane = @intCast(pane_idx);
        self.tab_idx = @intCast(tab_idx);
        self.wid = wid;
        self.start_x = mouse_x;
        self.start_y = mouse_y;
    }

    pub fn reset(self: *TabDragState) void {
        self.active = false;
        self.moved = false;
        self.wid = 0;
    }

    /// Checks if the user is dragging a tab horizontally inside `pane_idx`'s tab strip
    /// and crosses the midpoint of a neighboring tab. Updates `self.tab_idx` and returns the
    /// pair of tab indices to swap when a reorder occurs.
    pub fn checkBarReorder(
        self: *TabDragState,
        uic: *Context,
        pane_idx: usize,
        bar_rect: c.sk_rect_t,
        tab_rects: []const c.sk_rect_t,
    ) ?TabReorderSwap {
        if (uic.pass != .input or !self.active or !self.moved or !uic.mouse_down) return null;
        if (self.pane != pane_idx) return null;
        if (uic.mouse_y < bar_rect.top - 10.0 or uic.mouse_y > bar_rect.bottom + 14.0) return null;

        const cur_idx: usize = self.tab_idx;
        if (cur_idx >= tab_rects.len) return null;

        for (tab_rects, 0..) |tr, other_idx| {
            if (other_idx == cur_idx) continue;
            const mid_x = (tr.left + tr.right) * 0.5;
            if ((cur_idx < other_idx and uic.mouse_x > mid_x and uic.mouse_x <= tr.right) or
                (cur_idx > other_idx and uic.mouse_x < mid_x and uic.mouse_x >= tr.left))
            {
                self.tab_idx = @intCast(other_idx);
                uic.invalidateWindow();
                return .{ .idx_a = cur_idx, .idx_b = other_idx };
            }
        }
        return null;
    }

    /// Advances the drag state machine during `Pass.input`.
    /// When the user releases the mouse after dragging past the 5pt hysteresis threshold,
    /// returns `CompletedTabDrop` if released over a valid dock drop zone.
    pub fn updateInput(
        self: *TabDragState,
        uic: *Context,
        pane_rects: []const c.sk_rect_t,
        header_height: f32,
    ) ?CompletedTabDrop {
        if (!self.active or uic.pass != .input) return null;

        if (uic.mouse_down) {
            if (!self.moved and
                (@abs(uic.mouse_x - self.start_x) > 5.0 or @abs(uic.mouse_y - self.start_y) > 5.0))
            {
                self.moved = true;
                uic.invalidateWindow();
            } else if (self.moved) {
                uic.invalidateWindow();
            }
            return null;
        }

        var result: ?CompletedTabDrop = null;
        if (self.moved) {
            if (detectDockDropTarget(uic.mouse_x, uic.mouse_y, pane_rects, header_height, self.pane)) |drop| {
                result = .{
                    .src_pane = self.pane,
                    .src_tab = self.tab_idx,
                    .drop = drop,
                };
            }
        }
        self.reset();
        uic.invalidateWindow();
        return result;
    }
};

/// Generic comptime-bounded recursive binary split tree state.
/// Serializable directly via `std.json` for hot-reload persistence.
pub fn SplitTree(comptime max_panes: usize) type {
    const max_nodes = 2 * max_panes - 1;
    return struct {
        const Self = @This();
        pub const MaxPanes = max_panes;
        pub const MaxNodes = max_nodes;

        pane_count: u8 = 1,
        active_pane: u8 = 0,
        node_count: u8 = 1,
        nodes: [max_nodes]SplitNode = initDefaultNodes(),

        fn initDefaultNodes() [max_nodes]SplitNode {
            var arr: [max_nodes]SplitNode = @splat(.{});
            arr[0] = .{ .is_split = false, .pane_idx = 0 };
            return arr;
        }

        pub fn ensureValid(self: *Self) void {
            if (self.pane_count == 0 or self.pane_count > max_panes) {
                self.pane_count = 1;
            }
            if (self.node_count == 0 or self.node_count > max_nodes or
                (self.pane_count == 1 and self.nodes[0].is_split))
            {
                self.node_count = 1;
                self.nodes[0] = .{ .is_split = false, .pane_idx = 0 };
            }
        }

        pub fn activePaneIndex(self: *const Self) usize {
            const count = std.math.clamp(@as(usize, self.pane_count), 1, max_panes);
            return @min(@as(usize, self.active_pane), count - 1);
        }

        pub fn findLeafNodeForPane(self: *const Self, target_pane: usize) ?usize {
            const n_count = @min(@as(usize, self.node_count), max_nodes);
            for (0..n_count) |n_idx| {
                const node = self.nodes[n_idx];
                if (!node.is_split and node.pane_idx == target_pane) {
                    return n_idx;
                }
            }
            return null;
        }

        pub fn subtreeContainsPane(self: *const Self, node_idx: u8, target_pane: usize, depth: u8) bool {
            if (node_idx >= self.node_count or node_idx >= max_nodes or depth > max_nodes) return false;
            const node = self.nodes[node_idx];
            if (!node.is_split) {
                return node.pane_idx == target_pane;
            }
            return self.subtreeContainsPane(node.first, target_pane, depth + 1) or
                self.subtreeContainsPane(node.second, target_pane, depth + 1);
        }

        /// Finds the deepest vertical split node (`node.vertical == true`) where `target_pane`
        /// lies along the bottom boundary of its top (`first`) subtree.
        /// Dragging `target_pane`'s bottom mode line resizes this split node.
        pub fn findVerticalSplitBelowPane(self: *const Self, target_pane: usize) ?usize {
            const n_count = @min(@as(usize, self.node_count), max_nodes);
            var candidate: ?usize = null;
            var cur_idx: u8 = 0;
            var depth: u8 = 0;
            while (cur_idx < n_count and depth <= max_nodes) : (depth += 1) {
                const node = self.nodes[cur_idx];
                if (!node.is_split) break;
                if (self.subtreeContainsPane(node.first, target_pane, 0)) {
                    if (node.vertical) {
                        candidate = cur_idx;
                    }
                    cur_idx = node.first;
                } else if (self.subtreeContainsPane(node.second, target_pane, 0)) {
                    cur_idx = node.second;
                } else {
                    break;
                }
            }
            return candidate;
        }

        /// Computes the vertical `(top, bottom)` span of `node_idx` from the rendered leaf `pane_rects`.
        pub fn nodeVerticalBounds(
            self: *const Self,
            node_idx: u8,
            pane_rects: []const c.sk_rect_t,
            depth: u8,
        ) ?struct { top: f32, bottom: f32 } {
            if (node_idx >= self.node_count or node_idx >= max_nodes or depth > max_nodes) return null;
            const node = self.nodes[node_idx];
            if (!node.is_split) {
                const p_idx: usize = node.pane_idx;
                if (p_idx < pane_rects.len) {
                    const pr = pane_rects[p_idx];
                    if (pr.bottom > pr.top) {
                        return .{ .top = pr.top, .bottom = pr.bottom };
                    }
                }
                return null;
            }
            const b1 = self.nodeVerticalBounds(node.first, pane_rects, depth + 1);
            const b2 = self.nodeVerticalBounds(node.second, pane_rects, depth + 1);
            if (b1 != null and b2 != null) {
                return .{
                    .top = @min(b1.?.top, b2.?.top),
                    .bottom = @max(b1.?.bottom, b2.?.bottom),
                };
            }
            return b1 orelse b2;
        }

        fn compactNodeRecursive(
            old_nodes: *const [max_nodes]SplitNode,
            old_idx: u8,
            new_nodes: *[max_nodes]SplitNode,
            new_len: *u8,
            depth: u8,
        ) u8 {
            if (old_idx >= max_nodes or new_len.* >= max_nodes or depth > max_nodes) return 0;
            const my_idx = new_len.*;
            new_len.* += 1;
            const node = old_nodes[old_idx];
            new_nodes[my_idx] = node;
            if (node.is_split) {
                new_nodes[my_idx].first = compactNodeRecursive(old_nodes, node.first, new_nodes, new_len, depth + 1);
                new_nodes[my_idx].second = compactNodeRecursive(old_nodes, node.second, new_nodes, new_len, depth + 1);
            }
            return my_idx;
        }

        pub fn compact(self: *Self) void {
            var new_nodes: [max_nodes]SplitNode = @splat(.{});
            var new_len: u8 = 0;
            _ = compactNodeRecursive(&self.nodes, 0, &new_nodes, &new_len, 0);
            if (new_len == 0) {
                new_nodes[0] = .{ .is_split = false, .pane_idx = 0 };
                new_len = 1;
            }
            self.nodes = new_nodes;
            self.node_count = new_len;
        }

        /// Splits `target_pane` into two child leaves in the binary tree (`vertical == false` for left/right,
        /// `vertical == true` for top/bottom). Returns the newly allocated pane index (`0 .. max_panes - 1`),
        /// or `null` if the tree is already at capacity.
        pub fn splitLeaf(
            self: *Self,
            target_pane_raw: usize,
            vertical: bool,
            place_new_first: bool,
        ) ?usize {
            self.ensureValid();
            if (self.pane_count >= max_panes or self.node_count + 2 > max_nodes) {
                return null;
            }

            const target_pane = @min(target_pane_raw, @as(usize, self.pane_count -| 1));
            const leaf_idx = self.findLeafNodeForPane(target_pane) orelse 0;

            const new_pane_idx: u8 = self.pane_count;
            self.pane_count += 1;

            const child_a: u8 = self.node_count;
            const child_b: u8 = self.node_count + 1;
            self.node_count += 2;

            const existing_leaf = SplitNode{ .is_split = false, .pane_idx = @intCast(target_pane) };
            const new_leaf = SplitNode{ .is_split = false, .pane_idx = new_pane_idx };

            self.nodes[child_a] = if (place_new_first) new_leaf else existing_leaf;
            self.nodes[child_b] = if (place_new_first) existing_leaf else new_leaf;
            self.nodes[leaf_idx] = .{
                .is_split = true,
                .vertical = vertical,
                .ratio = 0.5,
                .first = child_a,
                .second = child_b,
            };

            self.active_pane = new_pane_idx;
            return new_pane_idx;
        }

        /// Removes leaf `close_pane_idx` from the binary split tree, promotes its sibling subtree,
        /// decrements higher pane indices, and compacts the node array.
        /// Returns `true` if the leaf was removed.
        pub fn removeLeaf(self: *Self, close_pane_idx: usize) bool {
            self.ensureValid();
            if (self.pane_count <= 1 or close_pane_idx >= self.pane_count) return false;

            if (self.findLeafNodeForPane(close_pane_idx)) |leaf_idx| {
                const n_count = @min(@as(usize, self.node_count), max_nodes);
                for (0..n_count) |p_idx| {
                    const p_node = self.nodes[p_idx];
                    if (p_node.is_split and (p_node.first == leaf_idx or p_node.second == leaf_idx)) {
                        const sibling_idx = if (p_node.first == leaf_idx) p_node.second else p_node.first;
                        if (sibling_idx < max_nodes) {
                            self.nodes[p_idx] = self.nodes[sibling_idx];
                        }
                        break;
                    }
                }
            }

            self.pane_count -= 1;

            const n_count = @min(@as(usize, self.node_count), max_nodes);
            for (0..n_count) |n_idx| {
                if (!self.nodes[n_idx].is_split and self.nodes[n_idx].pane_idx > close_pane_idx) {
                    self.nodes[n_idx].pane_idx -= 1;
                }
            }
            self.compact();

            if (self.active_pane >= self.pane_count) {
                self.active_pane = self.pane_count - 1;
            } else if (self.active_pane > close_pane_idx) {
                self.active_pane -= 1;
            }
            return true;
        }
    };
}

/// Options for `renderSplitTreeEx` / `Context.splitTreeEx`.
pub const SplitTreeOptions = struct {
    min_ratio: f32 = 0.18,
    max_ratio: f32 = 0.82,
    enable_vertical_sash: bool = false,
};

/// Recursively renders a `SplitTree` into `uic` with interactive `splitterSash` handles
/// at every internal branch, calling `buildLeafFn(ctx, pane_idx, pane_count, w_spec, h_px)` for each leaf.
pub fn renderSplitTree(
    uic: *Context,
    tree: anytype,
    height: f32,
    min_ratio: f32,
    max_ratio: f32,
    ctx: anytype,
    comptime buildLeafFn: fn (@TypeOf(ctx), usize, usize, Size, f32) void,
) void {
    renderSplitTreeEx(uic, tree, height, .{
        .min_ratio = min_ratio,
        .max_ratio = max_ratio,
        .enable_vertical_sash = false,
    }, ctx, buildLeafFn);
}

/// Recursively renders a `SplitTree` into `uic` with configurable `SplitTreeOptions`
/// (including optional interactive horizontal splitter sashes for vertical splits).
pub fn renderSplitTreeEx(
    uic: *Context,
    tree: anytype,
    height: f32,
    opts: SplitTreeOptions,
    ctx: anytype,
    comptime buildLeafFn: fn (@TypeOf(ctx), usize, usize, Size, f32) void,
) void {
    tree.ensureValid();
    const TreeType = @TypeOf(tree.*);
    const pane_count = std.math.clamp(@as(usize, tree.pane_count), 1, TreeType.MaxPanes);
    renderSplitTreeNode(uic, tree, 0, pane_count, .fill, height, opts, 0, ctx, buildLeafFn);
}

fn renderSplitTreeNode(
    uic: *Context,
    tree: anytype,
    node_idx: u8,
    pane_count: usize,
    w_spec: Size,
    h_px: f32,
    opts: SplitTreeOptions,
    depth: u8,
    ctx: anytype,
    comptime buildLeafFn: fn (@TypeOf(ctx), usize, usize, Size, f32) void,
) void {
    const TreeType = @TypeOf(tree.*);
    if (node_idx >= tree.node_count or node_idx >= TreeType.MaxNodes or depth > TreeType.MaxNodes) {
        return;
    }

    const node = tree.nodes[node_idx];
    if (!node.is_split) {
        const p_idx = @min(@as(usize, node.pane_idx), TreeType.MaxPanes - 1);
        buildLeafFn(ctx, p_idx, pane_count, w_spec, h_px);
        return;
    }

    var node_scope = uic.scopedId(@as(usize, node_idx) + 500);
    defer node_scope.end();

    var split_box = uic.box(.{
        .direction = if (node.vertical) .column else .row,
        .w = w_spec,
        .h = .pixels(h_px),
        .gap = 0,
    });
    defer split_box.end();

    const rect = split_box.rect;
    const avail_w = @max(1.0, rect.right - rect.left);
    const avail_h = @max(1.0, rect.bottom - rect.top);
    const r_clamped = std.math.clamp(node.ratio, opts.min_ratio, opts.max_ratio);

    if (node.vertical) {
        if (opts.enable_vertical_sash) {
            const usable_h = @max(1.0, avail_h - 5.0);
            const first_h: f32 = @floor(usable_h * r_clamped);
            renderSplitTreeNode(uic, tree, node.first, pane_count, .fill, first_h, opts, depth + 1, ctx, buildLeafFn);

            const sash = uic.splitterSash(
                "##split_tree_v_sash",
                false,
                avail_w,
            );
            if (uic.pass == .input and sash.dragging) {
                const new_r = (uic.mouse_y - rect.top - 2.5) / usable_h;
                tree.nodes[node_idx].ratio = std.math.clamp(new_r, opts.min_ratio, opts.max_ratio);
                uic.invalidateWindow();
            }

            const second_h: f32 = @max(1.0, usable_h - first_h);
            renderSplitTreeNode(uic, tree, node.second, pane_count, .fill, second_h, opts, depth + 1, ctx, buildLeafFn);
        } else {
            const first_h: f32 = @floor(avail_h * r_clamped);
            renderSplitTreeNode(uic, tree, node.first, pane_count, .fill, first_h, opts, depth + 1, ctx, buildLeafFn);

            const second_h: f32 = @max(1.0, avail_h - first_h);
            renderSplitTreeNode(uic, tree, node.second, pane_count, .fill, second_h, opts, depth + 1, ctx, buildLeafFn);
        }
    } else {
        const first_w: Size = .pixels(@floor((avail_w - 5.0) * r_clamped));
        renderSplitTreeNode(uic, tree, node.first, pane_count, first_w, avail_h, opts, depth + 1, ctx, buildLeafFn);

        const sash = uic.splitterSash(
            "##split_tree_sash",
            true,
            avail_h,
        );
        if (uic.pass == .input and sash.dragging) {
            const new_r = (uic.mouse_x - rect.left - 2.5) / @max(1.0, avail_w - 5.0);
            tree.nodes[node_idx].ratio = std.math.clamp(new_r, opts.min_ratio, opts.max_ratio);
            uic.invalidateWindow();
        }

        renderSplitTreeNode(uic, tree, node.second, pane_count, .fill, avail_h, opts, depth + 1, ctx, buildLeafFn);
    }
}

/// Hit-tests `(mx, my)` against `pane_rects` to determine a 5-zone dock drop target
/// (`.center` for tab bar or body center on another pane, or `.left`/`.right`/`.top`/`.bottom`
/// when hovering within 26% of any pane's outer body edges).
pub fn detectDockDropTarget(
    mx: f32,
    my: f32,
    pane_rects: []const c.sk_rect_t,
    header_height: f32,
    source_pane: usize,
) ?DockDropTarget {
    for (pane_rects, 0..) |pr, target_p| {
        if (mx < pr.left or mx > pr.right or my < pr.top or my > pr.bottom) continue;

        const body_top = @min(pr.bottom, pr.top + header_height);
        if (my <= body_top) {
            if (target_p != source_pane) {
                return .{
                    .target_pane = target_p,
                    .zone = .center,
                    .preview_rect = Rect.ltrb(pr.left + 3.0, pr.top + 2.0, pr.right - 3.0, pr.bottom - 3.0),
                };
            }
            return null;
        }

        const pw = @max(1.0, pr.right - pr.left);
        const bh = @max(1.0, pr.bottom - body_top);
        const rel_x = (mx - pr.left) / pw;
        const rel_y = (my - body_top) / bh;

        const edge_thresh: f32 = 0.26;
        if (rel_x < edge_thresh or rel_x > (1.0 - edge_thresh) or
            rel_y < edge_thresh or rel_y > (1.0 - edge_thresh))
        {
            const d_left = rel_x;
            const d_right = 1.0 - rel_x;
            const d_top = rel_y;
            const d_bottom = 1.0 - rel_y;
            const min_d = @min(@min(d_left, d_right), @min(d_top, d_bottom));

            if (min_d == d_left) {
                return .{
                    .target_pane = target_p,
                    .zone = .left,
                    .preview_rect = Rect.ltrb(pr.left + 3.0, body_top, pr.left + pw * 0.5, pr.bottom - 3.0),
                };
            } else if (min_d == d_right) {
                return .{
                    .target_pane = target_p,
                    .zone = .right,
                    .preview_rect = Rect.ltrb(pr.left + pw * 0.5, body_top, pr.right - 3.0, pr.bottom - 3.0),
                };
            } else if (min_d == d_top) {
                return .{
                    .target_pane = target_p,
                    .zone = .top,
                    .preview_rect = Rect.ltrb(pr.left + 3.0, body_top, pr.right - 3.0, body_top + bh * 0.5),
                };
            } else {
                return .{
                    .target_pane = target_p,
                    .zone = .bottom,
                    .preview_rect = Rect.ltrb(pr.left + 3.0, body_top + bh * 0.5, pr.right - 3.0, pr.bottom - 3.0),
                };
            }
        }

        if (target_p != source_pane) {
            return .{
                .target_pane = target_p,
                .zone = .center,
                .preview_rect = Rect.ltrb(pr.left + 3.0, body_top, pr.right - 3.0, pr.bottom - 3.0),
            };
        }
        return null;
    }
    return null;
}

/// Renders a translucent accent highlight rectangle for a dock drop target zone.
pub fn drawDockDropPreview(uic: *Context, preview_rect: c.sk_rect_t) void {
    uic.paint.setStyle(.fill);
    uic.paint.setColor(Color.argb(45, 56, 139, 253));
    uic.canvas.drawRoundRect(preview_rect, 6.0, 6.0, uic.paint);

    uic.paint.setStyle(.stroke);
    uic.paint.setStrokeWidth(1.5);
    uic.paint.setColor(uic.theme.accent);
    uic.canvas.drawRoundRect(preview_rect, 6.0, 6.0, uic.paint);
}

/// Renders a floating ghost tab pill next to the mouse cursor while dragging a tab.
pub fn drawDragGhostPill(uic: *Context, label: []const u8, dot_color: u32) void {
    const tw = uic.measureTextCached(uic.font_body, label) + 34.0;
    const pill_r = Rect.xywh(uic.mouse_x + 10.0, uic.mouse_y - 14.0, tw, 26.0);

    uic.paint.setStyle(.fill);
    uic.paint.setColor(Color.argb(230, 22, 28, 39));
    uic.canvas.drawRoundRect(pill_r, 5.0, 5.0, uic.paint);

    uic.paint.setStyle(.stroke);
    uic.paint.setStrokeWidth(1.2);
    uic.paint.setColor(uic.theme.accent);
    uic.canvas.drawRoundRect(pill_r, 5.0, 5.0, uic.paint);

    uic.paint.setStyle(.fill);
    uic.paint.setColor(dot_color);
    uic.canvas.drawCircle(pill_r.left + 12.0, pill_r.top + 13.0, 3.2, uic.paint);

    uic.paint.setColor(uic.theme.text_primary);
    uic.drawTextCached(uic.font_body, label, pill_r.left + 21.0, pill_r.top + 17.0);
}

test "SplitTree recursive horizontal and vertical splitting, removal, and compaction" {
    var tree = SplitTree(6){};
    try std.testing.expectEqual(@as(u8, 1), tree.pane_count);

    // Split pane 0 horizontally -> creates pane 1
    const p1 = tree.splitLeaf(0, false, false).?;
    try std.testing.expectEqual(@as(usize, 1), p1);
    try std.testing.expectEqual(@as(u8, 2), tree.pane_count);
    try std.testing.expect(tree.nodes[0].is_split);
    try std.testing.expect(!tree.nodes[0].vertical);

    // Split pane 1 vertically -> creates pane 2
    const p2 = tree.splitLeaf(1, true, false).?;
    try std.testing.expectEqual(@as(usize, 2), p2);
    try std.testing.expectEqual(@as(u8, 3), tree.pane_count);

    // Remove middle pane 1 -> promotes pane 2 (shifted to index 1)
    try std.testing.expect(tree.removeLeaf(1));
    try std.testing.expectEqual(@as(u8, 2), tree.pane_count);
    try std.testing.expect(tree.findLeafNodeForPane(0) != null);
    try std.testing.expect(tree.findLeafNodeForPane(1) != null);
}

test "detectDockDropTarget identifies edge split zones and center tab zone" {
    const rects = [_]c.sk_rect_t{
        Rect.xywh(0, 0, 400, 300),
        Rect.xywh(400, 0, 400, 300),
    };

    // Hovering right edge of pane 0 (even when source_pane == 0) triggers .right split zone
    const right_split = detectDockDropTarget(380, 150, &rects, 36.0, 0).?;
    try std.testing.expectEqual(@as(usize, 0), right_split.target_pane);
    try std.testing.expectEqual(DockDropZone.right, right_split.zone);

    // Hovering bottom edge of pane 0 triggers .bottom split zone
    const bottom_split = detectDockDropTarget(200, 285, &rects, 36.0, 0).?;
    try std.testing.expectEqual(@as(usize, 0), bottom_split.target_pane);
    try std.testing.expectEqual(DockDropZone.bottom, bottom_split.zone);

    // Hovering center of pane 1 when dragging from pane 0 triggers .center move zone
    const center_move = detectDockDropTarget(600, 150, &rects, 36.0, 0).?;
    try std.testing.expectEqual(@as(usize, 1), center_move.target_pane);
    try std.testing.expectEqual(DockDropZone.center, center_move.zone);
}

test "PaneTabGroup manages single-item, multi-tab removal, and tab swapping" {
    var group = PaneTabGroup(8){};
    try std.testing.expectEqual(@as(?usize, null), group.activeItem(10));

    group.setSingleItem(3);
    try std.testing.expectEqual(@as(usize, 1), group.count());
    try std.testing.expectEqual(@as(?usize, 3), group.activeItem(10));

    group.tabs[1] = 7;
    group.tab_count = 2;
    group.active_tab = 1;
    try std.testing.expect(group.swapTabs(0, 1));
    try std.testing.expectEqual(@as(u8, 0), group.active_tab);
    try std.testing.expectEqual(@as(?usize, 7), group.activeItem(10));

    try std.testing.expect(group.removeTabSlot(0));
    try std.testing.expectEqual(@as(usize, 1), group.count());
    try std.testing.expectEqual(@as(?usize, 3), group.activeItem(10));
}

test "SplitTree findVerticalSplitBelowPane and nodeVerticalBounds resolve vertical split hierarchy" {
    var tree = SplitTree(6){};
    try std.testing.expectEqual(@as(?usize, null), tree.findVerticalSplitBelowPane(0));

    // Split pane 0 vertically (top = pane 0, bottom = pane 1) at root node 0
    const p1 = tree.splitLeaf(0, true, false).?;
    try std.testing.expectEqual(@as(usize, 1), p1);
    try std.testing.expectEqual(@as(?usize, 0), tree.findVerticalSplitBelowPane(0));
    try std.testing.expectEqual(@as(?usize, null), tree.findVerticalSplitBelowPane(1));

    // Split top pane 0 horizontally (left = pane 0, right = pane 2) at node 1
    const p2 = tree.splitLeaf(0, false, false).?;
    try std.testing.expectEqual(@as(usize, 2), p2);
    // Both top-left (pane 0) and top-right (pane 2) sit above root vertical split (node 0)
    try std.testing.expectEqual(@as(?usize, 0), tree.findVerticalSplitBelowPane(0));
    try std.testing.expectEqual(@as(?usize, 0), tree.findVerticalSplitBelowPane(2));
    try std.testing.expectEqual(@as(?usize, null), tree.findVerticalSplitBelowPane(1));

    const pane_rects = [_]c.sk_rect_t{
        Rect.xywh(0, 20, 300, 180), // pane 0: top=20, bottom=200
        Rect.xywh(0, 200, 600, 220), // pane 1: top=200, bottom=420
        Rect.xywh(300, 20, 300, 180), // pane 2: top=20, bottom=200
    };
    const root_bounds = tree.nodeVerticalBounds(0, &pane_rects, 0).?;
    try std.testing.expectEqual(@as(f32, 20.0), root_bounds.top);
    try std.testing.expectEqual(@as(f32, 420.0), root_bounds.bottom);

    const top_branch_bounds = tree.nodeVerticalBounds(tree.nodes[0].first, &pane_rects, 0).?;
    try std.testing.expectEqual(@as(f32, 20.0), top_branch_bounds.top);
    try std.testing.expectEqual(@as(f32, 200.0), top_branch_bounds.bottom);
}

