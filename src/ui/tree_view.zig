//! Hierarchical TreeView Path Utilities, Indent Guide Renderer, and Inline-Rename Tree Row (`src/ui/tree_view.zig`).
//!
//! Provides general-purpose hierarchical path functions (`pathDepth`, `parentDirPath`, `baseName`,
//! `isPathVisibleInTree`), vertical indent guide drawing (`drawTreeIndentGuides`), and declarative
//! inline text-input tree rows (`treeInlineInputRow`) for renaming or creating folders/files.

const std = @import("std");
const skia = @import("skia");
const platform = @import("platform");
const root = @import("root.zig");
const layout_mod = @import("layout.zig");
const Color = skia.Color;
const Rect = skia.Rect;
const Context = root.Context;
const Padding = layout_mod.Padding;

pub const TreeInlineInputAction = enum {
    none,
    submitted,
    cancelled,
};

pub const TreeInlineInputOptions = struct {
    row_height: f32 = 26.0,
    input_height: f32 = 22.0,
    base_pad: f32 = 8.0,
    indent_step: f32 = 13.0,
    guide_base_pad: f32 = 9.0,
    auto_focus: bool = true,
    select_all_on_focus: bool = true,
    draw_indent_guides: bool = true,
    require_non_empty: bool = true,
};

fn normalizeRelativePath(path: []const u8) []const u8 {
    var clean = path;
    while (std.mem.startsWith(u8, clean, "./")) {
        clean = clean[2..];
    }
    while (clean.len > 0 and clean[clean.len - 1] == '/') {
        clean = clean[0 .. clean.len - 1];
    }
    if (std.mem.eql(u8, clean, ".")) return "";
    return clean;
}

/// Returns the hierarchical nesting depth of `path` by counting `'/'` separators.
pub fn pathDepth(path: []const u8) usize {
    const clean = normalizeRelativePath(path);
    if (clean.len == 0) return 0;
    return std.mem.count(u8, clean, "/");
}

/// Returns the parent directory slice before the last `'/'`, or `null` if `path` is top-level.
pub fn parentDirPath(path: []const u8) ?[]const u8 {
    const clean = normalizeRelativePath(path);
    if (clean.len == 0) return null;
    const slash_idx = std.mem.lastIndexOfScalar(u8, clean, '/') orelse return null;
    if (slash_idx == 0) return null;
    return clean[0..slash_idx];
}

/// Returns the leaf filename or directory name after the last `'/'`.
pub fn baseName(path: []const u8) []const u8 {
    const clean = normalizeRelativePath(path);
    if (clean.len == 0) return path;
    if (std.mem.lastIndexOfScalar(u8, clean, '/')) |slash_idx| {
        return clean[slash_idx + 1 ..];
    }
    return clean;
}

/// Walks up every ancestor directory of `path` and returns `false` if
/// `isFolderCollapsedFn(ctx, ancestor)` returns `true` for any ancestor.
pub fn isPathVisibleInTree(
    path: []const u8,
    ctx: anytype,
    comptime isFolderCollapsedFn: anytype,
) bool {
    var cur = normalizeRelativePath(path);
    while (parentDirPath(cur)) |ancestor| {
        if (isFolderCollapsedFn(ctx, ancestor)) return false;
        cur = ancestor;
    }
    return true;
}

/// Draws subtle vertical indent guide lines at each ancestor depth level inside `row_rect`
/// when `uic.shouldPaint(row_rect)`.
pub fn drawTreeIndentGuides(
    uic: *Context,
    row_rect: layout_mod.Rect,
    depth: usize,
    base_pad: f32,
    step_px: f32,
) void {
    if (depth == 0 or !uic.shouldPaint(row_rect)) return;
    const h = row_rect.bottom - row_rect.top;
    if (h <= 0.0) return;
    uic.paint.setStyle(.fill);
    uic.paint.setColor(Color.argb(42, 148, 163, 184));
    for (0..depth) |lvl| {
        const gx = row_rect.left + base_pad + @as(f32, @floatFromInt(lvl)) * step_px;
        uic.canvas.drawRect(Rect.xywh(gx, row_rect.top, 1.0, h), uic.paint);
    }
}

/// Renders an indented inline tree text-input row (for renaming or creating a folder/file)
/// with optional leading badge/chevron, indent guides, auto-focus + select-all, and
/// `Enter` submit / `Escape` or outside-click cancel detection.
/// Consumes strictly identical layout rectangles in both `Pass.input` and `Pass.paint`.
pub fn treeInlineInputRow(
    uic: *Context,
    comptime cap: usize,
    id_str: []const u8,
    depth: usize,
    prefix_badge: []const u8,
    prefix_color: u32,
    buf: *platform.InlineString(cap),
    placeholder: []const u8,
    opts: TreeInlineInputOptions,
) TreeInlineInputAction {
    const indent_px = opts.base_pad + @as(f32, @floatFromInt(depth)) * opts.indent_step;
    var rename_row = uic.row(.{
        .h = .pixels(opts.row_height),
        .padding = Padding{ .left = indent_px, .right = 6.0, .top = 2.0, .bottom = 2.0 },
        .gap = 6.0,
        .bg_color = Color.argb(40, 56, 139, 253),
        .corner_radius = 4.0,
    });

    if (opts.draw_indent_guides) {
        drawTreeIndentGuides(uic, rename_row.rect, depth, opts.guide_base_pad, opts.indent_step);
    }

    if (prefix_badge.len > 0) {
        uic.monoLabel(prefix_badge, prefix_color);
    }

    const rename_wid = uic.resolveIdAndLabel(id_str).wid;
    if (opts.auto_focus and uic.focused_id != rename_wid) {
        if (opts.select_all_on_focus) {
            uic.focusAndSelectAll(rename_wid);
        } else {
            uic.focused_id = rename_wid;
        }
    }

    const tf = uic.textFieldInline(id_str, buf, placeholder, .{
        .w = .fill,
        .h = opts.input_height,
    });

    rename_row.end();

    var escaped = tf.escaped;
    if (!escaped and uic.pass == .input) {
        for (uic.key_events) |kev| {
            if (kev.key == .escape) {
                escaped = true;
                break;
            }
        }
    }

    if (escaped or uic.clickedOutside(&.{rename_row.rect})) {
        uic.invalidateWindow();
        return .cancelled;
    }

    if (tf.submitted) {
        const trimmed = std.mem.trim(u8, buf.slice(), " \t\r\n");
        if (!opts.require_non_empty or trimmed.len > 0) {
            uic.invalidateWindow();
            return .submitted;
        }
        uic.invalidateWindow();
        return .cancelled;
    }

    return .none;
}

test "tree_view: pathDepth, parentDirPath, baseName, and isPathVisibleInTree" {
    try std.testing.expectEqual(@as(usize, 0), pathDepth(""));
    try std.testing.expectEqual(@as(usize, 0), pathDepth("."));
    try std.testing.expectEqual(@as(usize, 0), pathDepth("build.zig"));
    try std.testing.expectEqual(@as(usize, 1), pathDepth("src/main.zig"));
    try std.testing.expectEqual(@as(usize, 2), pathDepth("src/ui/tree_view.zig"));
    try std.testing.expectEqual(@as(usize, 3), pathDepth("./src/app/views/explorer.zig/"));

    try std.testing.expect(parentDirPath("") == null);
    try std.testing.expect(parentDirPath(".") == null);
    try std.testing.expect(parentDirPath("build.zig") == null);
    try std.testing.expectEqualStrings("src", parentDirPath("src/main.zig").?);
    try std.testing.expectEqualStrings("src/app/views", parentDirPath("src/app/views/explorer.zig").?);
    try std.testing.expectEqualStrings("src/ui", parentDirPath("./src/ui/tree_view.zig/").?);

    try std.testing.expectEqualStrings("", baseName(""));
    try std.testing.expectEqualStrings(".", baseName("."));
    try std.testing.expectEqualStrings("build.zig", baseName("build.zig"));
    try std.testing.expectEqualStrings("explorer.zig", baseName("src/app/views/explorer.zig"));
    try std.testing.expectEqualStrings("views", baseName("src/app/views/"));

    const MockTreeState = struct {
        collapsed_dir: []const u8,
        fn isCollapsed(self: @This(), folder: []const u8) bool {
            return std.mem.eql(u8, folder, self.collapsed_dir);
        }
    };

    try std.testing.expect(isPathVisibleInTree(
        "src/app/views/explorer.zig",
        MockTreeState{ .collapsed_dir = "examples" },
        MockTreeState.isCollapsed,
    ));
    try std.testing.expect(!isPathVisibleInTree(
        "src/app/views/explorer.zig",
        MockTreeState{ .collapsed_dir = "src/app" },
        MockTreeState.isCollapsed,
    ));
    try std.testing.expect(!isPathVisibleInTree(
        "src/app/views/explorer.zig",
        MockTreeState{ .collapsed_dir = "src" },
        MockTreeState.isCollapsed,
    ));
    try std.testing.expect(isPathVisibleInTree(
        "README.md",
        MockTreeState{ .collapsed_dir = "src" },
        MockTreeState.isCollapsed,
    ));
}

test "tree_view: drawTreeIndentGuides and treeInlineInputRow submit/cancel across 2-phase Pass.input and Pass.paint" {
    const surface = try skia.Surface.initRasterN32Premul(320, 160);
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

    var name_buf = platform.InlineString(128).init("explorer.zig");

    // 1. Initial frame: auto-focuses input and selects all; verify 2-phase layout rect count determinism
    uic.beginPass(.input, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 320, 160), 20, 12, false, false, false);
    drawTreeIndentGuides(&uic, Rect.xywh(0, 0, 240, 24), 2, 9.0, 13.0);
    const act_idle = uic.treeInlineInputRow(128, "##rename_file_input", 2, "Z", Color.rgb(251, 191, 36), &name_buf, "File name...", .{});
    uic.endPass();

    try std.testing.expectEqual(TreeInlineInputAction.none, act_idle);
    try std.testing.expect(uic.focused_id != 0);

    uic.clip_damage = Rect.xywh(0, 0, 320, 160);
    uic.beginPass(.paint, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 320, 160), 20, 12, false, false, false);
    drawTreeIndentGuides(&uic, Rect.xywh(0, 0, 240, 24), 2, 9.0, 13.0);
    _ = uic.treeInlineInputRow(128, "##rename_file_input", 2, "Z", Color.rgb(251, 191, 36), &name_buf, "File name...", .{});
    uic.endPass();
    try std.testing.expectEqual(uic.last_input_rect_count, uic.last_paint_rect_count);

    // 2. Enter key submits non-empty value
    const enter_ev = [_]platform.KeyEvent{.{ .key = .enter }};
    uic.key_events = &enter_ev;
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 320, 160), 20, 12, false, false, false);
    const act_submit = uic.treeInlineInputRow(128, "##rename_file_input", 2, "Z", Color.rgb(251, 191, 36), &name_buf, "File name...", .{});
    uic.endPass();
    try std.testing.expectEqual(TreeInlineInputAction.submitted, act_submit);

    // 3. Escape key cancels
    const esc_ev = [_]platform.KeyEvent{.{ .key = .escape }};
    uic.key_events = &esc_ev;
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 320, 160), 20, 12, false, false, false);
    const act_esc = uic.treeInlineInputRow(128, "##rename_file_input", 2, "Z", Color.rgb(251, 191, 36), &name_buf, "File name...", .{});
    uic.endPass();
    try std.testing.expectEqual(TreeInlineInputAction.cancelled, act_esc);

    // 4. Outside click cancels
    uic.key_events = &.{};
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 320, 160), 200, 140, true, true, false);
    const act_outside = uic.treeInlineInputRow(128, "##rename_file_input", 2, "Z", Color.rgb(251, 191, 36), &name_buf, "File name...", .{});
    uic.endPass();
    try std.testing.expectEqual(TreeInlineInputAction.cancelled, act_outside);
}
