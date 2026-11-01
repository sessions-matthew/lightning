//! Interactive Git Diff Viewer Component (`src/ui/diff_viewer.zig`) for `ui.Context`.
//!
//! Features:
//!   - **Zero-Allocation Unified & Split Diff Parser (`parseUnifiedDiff`)**:
//!     Parses standard `git diff` / `git show` unified diff text (`diff --git`, `@@ -a,b +c,d @@`,
//!     `+` additions, `-` deletions, ` ` context lines), tracking exact old/new line numbers and
//!     pairing consecutive deletion/addition blocks for side-by-side split view.
//!   - **Two-Phase (`Pass.input` / `Pass.paint`) Hardware-Accelerated Diff Canvas**:
//!     - Top toolbar with `STAGED` / `WORKING TREE` / `COMMIT` badge, `+additions` / `-deletions`
//!       counters, `Unified` vs `Split` view mode toggle, `↑ Hunk` / `↓ Hunk` navigation,
//!       `Stage`/`Unstage`, `↺` refresh, and `Open File` action.
//!     - Dual line-number gutter in Unified mode and side-by-side aligned columns in Split mode.
//!     - Click any diff row to select it; click the line number gutter (or `Open File`) to jump
//!       directly to that line in the source buffer.

const std = @import("std");
const skia = @import("skia");
const root = @import("root.zig");
const c = skia.c;
const Color = skia.Color;
const Rect = skia.Rect;
const Context = root.Context;
const Padding = root.Padding;

pub const MaxDiffLines: usize = 1024;
pub const MaxDiffHunks: usize = 64;

pub const DiffLineKind = enum(u8) {
    file_header = 0,
    hunk_header = 1,
    context = 2,
    addition = 3,
    deletion = 4,
};

pub const DiffLine = struct {
    kind: DiffLineKind = .context,
    old_line: u32 = 0,
    new_line: u32 = 0,
    text: []const u8 = "",
};

pub const DiffSplitRow = struct {
    is_header: bool = false,
    header_kind: DiffLineKind = .hunk_header,
    header_text: []const u8 = "",
    left_present: bool = false,
    left_kind: DiffLineKind = .context,
    left_line: u32 = 0,
    left_text: []const u8 = "",
    right_present: bool = false,
    right_kind: DiffLineKind = .context,
    right_line: u32 = 0,
    right_text: []const u8 = "",
};

pub const DiffStats = struct {
    additions: u32 = 0,
    deletions: u32 = 0,
    hunks: u32 = 0,
};

pub const DiffViewMode = enum(u8) {
    unified = 0,
    split = 1,
};

pub const DiffViewState = struct {
    mode: DiffViewMode = .unified,
    scroll_y: f32 = 0.0,
    scroll_x: f32 = 0.0,
    selected_row: u32 = 0,
    current_hunk: u32 = 0,
};

pub const DiffViewerOptions = struct {
    title: []const u8 = "",
    badge: []const u8 = "WORKING TREE",
    staged: bool = false,
    is_commit_view: bool = false,
};

pub const DiffViewResult = struct {
    open_file_requested: bool = false,
    stage_toggle_requested: bool = false,
    refresh_requested: bool = false,
    clicked_new_line: ?usize = null,
};

pub const ParsedDiff = struct {
    lines: [MaxDiffLines]DiffLine = undefined,
    line_count: usize = 0,
    split_rows: [MaxDiffLines]DiffSplitRow = undefined,
    split_row_count: usize = 0,
    hunk_unified_rows: [MaxDiffHunks]u32 = @splat(0),
    hunk_split_rows: [MaxDiffHunks]u32 = @splat(0),
    stats: DiffStats = .{},
};

pub const SAMPLE_GIT_DIFF =
    \\diff --git a/src/app/main.zig b/src/app/main.zig
    \\@@ -28,6 +28,9 @@ fn buildWorkbench(state: *EditorState, ctx: *PlatformContext) void {
    \\     const uic = &state.ui_ctx;
    \\     state.pollWorkspaceWatch();
    \\
    \\-    const legacy_git_tab = 2;
    \\+    // Native .dylib Git Source Control & Diff Viewer integration
    \\+    const active_activity = &state.doc.active_sidebar_view;
    \\+
    \\     var scope = uic.scopedState("vscode_workbench");
    \\     defer scope.end();
;

fn parseHunkStartNumbers(header: []const u8) struct { old_start: u32, new_start: u32 } {
    var old_start: u32 = 1;
    var new_start: u32 = 1;
    // Format: @@ -old_start[,old_count] +new_start[,new_count] @@
    if (std.mem.indexOfScalar(u8, header, '-')) |minus_idx| {
        const after_minus = header[minus_idx + 1 ..];
        var d_end: usize = 0;
        while (d_end < after_minus.len and std.ascii.isDigit(after_minus[d_end])) : (d_end += 1) {}
        if (d_end > 0) {
            old_start = std.fmt.parseInt(u32, after_minus[0..d_end], 10) catch 1;
        }
    }
    if (std.mem.indexOfScalar(u8, header, '+')) |plus_idx| {
        const after_plus = header[plus_idx + 1 ..];
        var d_end: usize = 0;
        while (d_end < after_plus.len and std.ascii.isDigit(after_plus[d_end])) : (d_end += 1) {}
        if (d_end > 0) {
            new_start = std.fmt.parseInt(u32, after_plus[0..d_end], 10) catch 1;
        }
    }
    return .{ .old_start = old_start, .new_start = new_start };
}

/// Zero-allocation parser that populates `out.lines` (for Unified mode) and `out.split_rows`
/// (for Side-by-Side Split mode) directly from `diff_text`.
pub fn parseUnifiedDiff(diff_text: []const u8, out: *ParsedDiff) void {
    out.line_count = 0;
    out.split_row_count = 0;
    out.stats = .{};

    var cur_old_line: u32 = 1;
    var cur_new_line: u32 = 1;
    var in_hunk = false;

    var line_it = std.mem.splitScalar(u8, diff_text, '\n');
    while (line_it.next()) |raw_line| {
        if (out.line_count >= MaxDiffLines) break;
        const line = std.mem.trimEnd(u8, raw_line, "\r");
        if (line.len == 0 and !in_hunk) continue;

        if (std.mem.startsWith(u8, line, "diff --git ")) {
            in_hunk = false;
            var header_label = line["diff --git ".len..];
            if (std.mem.indexOf(u8, header_label, " b/")) |b_idx| {
                header_label = header_label[b_idx + 3 ..];
            }
            out.lines[out.line_count] = .{
                .kind = .file_header,
                .old_line = 0,
                .new_line = 0,
                .text = header_label,
            };
            out.line_count += 1;
            continue;
        }

        if (std.mem.startsWith(u8, line, "index ") or
            std.mem.startsWith(u8, line, "--- ") or
            std.mem.startsWith(u8, line, "+++ ") or
            std.mem.startsWith(u8, line, "new file mode ") or
            std.mem.startsWith(u8, line, "deleted file mode "))
        {
            continue;
        }

        if (std.mem.startsWith(u8, line, "@@")) {
            in_hunk = true;
            const starts = parseHunkStartNumbers(line);
            cur_old_line = starts.old_start;
            cur_new_line = starts.new_start;
            if (out.stats.hunks < MaxDiffHunks) {
                out.hunk_unified_rows[out.stats.hunks] = @intCast(out.line_count);
            }
            out.stats.hunks += 1;
            out.lines[out.line_count] = .{
                .kind = .hunk_header,
                .old_line = cur_old_line,
                .new_line = cur_new_line,
                .text = line,
            };
            out.line_count += 1;
            continue;
        }

        if (!in_hunk) {
            if (std.mem.startsWith(u8, line, "commit ") or
                std.mem.startsWith(u8, line, "Author:") or
                std.mem.startsWith(u8, line, "Date:"))
            {
                out.lines[out.line_count] = .{
                    .kind = .file_header,
                    .old_line = 0,
                    .new_line = 0,
                    .text = line,
                };
                out.line_count += 1;
            }
            continue;
        }

        if (std.mem.startsWith(u8, line, "\\ No newline")) continue;

        if (line.len > 0 and line[0] == '+') {
            out.lines[out.line_count] = .{
                .kind = .addition,
                .old_line = 0,
                .new_line = cur_new_line,
                .text = line[1..],
            };
            cur_new_line += 1;
            out.stats.additions += 1;
            out.line_count += 1;
        } else if (line.len > 0 and line[0] == '-') {
            out.lines[out.line_count] = .{
                .kind = .deletion,
                .old_line = cur_old_line,
                .new_line = 0,
                .text = line[1..],
            };
            cur_old_line += 1;
            out.stats.deletions += 1;
            out.line_count += 1;
        } else {
            const content = if (line.len > 0 and line[0] == ' ') line[1..] else line;
            out.lines[out.line_count] = .{
                .kind = .context,
                .old_line = cur_old_line,
                .new_line = cur_new_line,
                .text = content,
            };
            cur_old_line += 1;
            cur_new_line += 1;
            out.line_count += 1;
        }
    }

    // Build aligned Side-by-Side (`split_rows`) by pairing contiguous deletion + addition runs
    var i: usize = 0;
    var hunk_idx: usize = 0;
    while (i < out.line_count and out.split_row_count < MaxDiffLines) {
        const dl = out.lines[i];
        if (dl.kind == .file_header or dl.kind == .hunk_header) {
            if (dl.kind == .hunk_header and hunk_idx < MaxDiffHunks) {
                out.hunk_split_rows[hunk_idx] = @intCast(out.split_row_count);
                hunk_idx += 1;
            }
            out.split_rows[out.split_row_count] = .{
                .is_header = true,
                .header_kind = dl.kind,
                .header_text = dl.text,
                .left_line = dl.old_line,
                .right_line = dl.new_line,
            };
            out.split_row_count += 1;
            i += 1;
            continue;
        }

        if (dl.kind == .context) {
            out.split_rows[out.split_row_count] = .{
                .left_present = true,
                .left_kind = .context,
                .left_line = dl.old_line,
                .left_text = dl.text,
                .right_present = true,
                .right_kind = .context,
                .right_line = dl.new_line,
                .right_text = dl.text,
            };
            out.split_row_count += 1;
            i += 1;
            continue;
        }

        // Collect contiguous deletions followed by contiguous additions
        const del_start = i;
        while (i < out.line_count and out.lines[i].kind == .deletion) : (i += 1) {}
        const del_end = i;

        const add_start = i;
        while (i < out.line_count and out.lines[i].kind == .addition) : (i += 1) {}
        const add_end = i;

        const del_cnt = del_end - del_start;
        const add_cnt = add_end - add_start;
        const pair_cnt = @max(del_cnt, add_cnt);

        for (0..pair_cnt) |p_idx| {
            if (out.split_row_count >= MaxDiffLines) break;
            var row = DiffSplitRow{};
            if (p_idx < del_cnt) {
                const d = out.lines[del_start + p_idx];
                row.left_present = true;
                row.left_kind = .deletion;
                row.left_line = d.old_line;
                row.left_text = d.text;
            }
            if (p_idx < add_cnt) {
                const a = out.lines[add_start + p_idx];
                row.right_present = true;
                row.right_kind = .addition;
                row.right_line = a.new_line;
                row.right_text = a.text;
            }
            out.split_rows[out.split_row_count] = row;
            out.split_row_count += 1;
        }
    }
}

pub fn renderDiffViewer(
    uic: *Context,
    raw_id: []const u8,
    w_override: f32,
    h_override: f32,
    diff_text: []const u8,
    view_state: *DiffViewState,
    opts: DiffViewerOptions,
) DiffViewResult {
    var result = DiffViewResult{};
    var scope = uic.scopedState(raw_id);
    defer scope.end();

    const parsed = uic.parseDiffCached(diff_text);

    const total_w = if (w_override > 0) w_override else uic.availableWidth();
    const total_h = if (h_override > 0) h_override else uic.availableHeight();
    const toolbar_h: f32 = 34.0;
    const canvas_h = @max(40.0, total_h - toolbar_h);

    var outer = uic.column(.{
        .w = .pixels(total_w),
        .h = .pixels(total_h),
        .gap = 0,
        .bg_color = uic.theme.bg_canvas,
    });
    defer outer.end();

    // 1. Top Diff Viewer Toolbar
    {
        var bar = uic.row(.{
            .h = .pixels(toolbar_h),
            .padding = Padding.xy(10, 4),
            .gap = 6,
            .bg_color = Color.rgb(18, 23, 33),
            .border_color = uic.theme.border_subtle,
            .border_width = 1.0,
            .border_edges = .bottom_only,
        });
        defer bar.end();

        const badge_col = if (opts.is_commit_view)
            Color.rgb(56, 189, 248)
        else if (opts.staged)
            Color.rgb(52, 211, 153)
        else
            Color.rgb(251, 191, 36);

        const compact_bar = total_w < 780.0;
        const badge_text = if (total_w < 640.0 and std.mem.eql(u8, opts.badge, "WORKING TREE"))
            "MOD"
        else
            opts.badge;
        uic.label(badge_text, badge_col);

        const raw_title = if (opts.title.len > 0) opts.title else "Git Working Tree Diff";
        const title_str = if (total_w < 640.0) blk: {
            if (std.mem.lastIndexOfScalar(u8, raw_title, '/')) |slash| {
                break :blk raw_title[slash + 1 ..];
            }
            break :blk raw_title;
        } else raw_title;
        uic.monoLabel(title_str, uic.theme.text_primary);

        const stats_str = if (compact_bar)
            uic.fmt("+{d} -{d}", .{ parsed.stats.additions, parsed.stats.deletions })
        else
            uic.fmt("+{d}  -{d}  ({d} hunks)", .{
                parsed.stats.additions,
                parsed.stats.deletions,
                parsed.stats.hunks,
            });
        uic.monoLabel(stats_str, if (parsed.stats.additions >= parsed.stats.deletions)
            Color.rgb(52, 211, 153)
        else
            Color.rgb(248, 113, 113));

        const right_controls_w: f32 = if (compact_bar)
            (if (opts.is_commit_view) 256.0 else 310.0)
        else
            (if (opts.is_commit_view) 366.0 else 434.0);
        if (uic.availableWidth() > right_controls_w) {
            uic.spacer(uic.availableWidth() - right_controls_w);
        }

        if (uic.chip("Unified##diff_mode_uni", .{ .active = view_state.mode == .unified })) {
            view_state.mode = .unified;
            view_state.scroll_y = 0;
        }
        if (uic.chip("Split##diff_mode_split", .{ .active = view_state.mode == .split })) {
            view_state.mode = .split;
            view_state.scroll_y = 0;
        }

        const prev_label = if (compact_bar) "↑##diff_prev_hunk" else "↑ Hunk##diff_prev_hunk";
        const next_label = if (compact_bar) "↓##diff_next_hunk" else "↓ Hunk##diff_next_hunk";
        const hunk_btn_w: f32 = if (compact_bar) 24.0 else 56.0;

        if (uic.btn(prev_label, .{ .w = .pixels(hunk_btn_w), .h = 24 })) {
            if (parsed.stats.hunks > 0) {
                view_state.current_hunk = if (view_state.current_hunk > 0)
                    view_state.current_hunk - 1
                else
                    parsed.stats.hunks - 1;
                const h_idx = @min(@as(usize, view_state.current_hunk), MaxDiffHunks - 1);
                const target_row = if (view_state.mode == .unified)
                    parsed.hunk_unified_rows[h_idx]
                else
                    parsed.hunk_split_rows[h_idx];
                view_state.selected_row = target_row;
                view_state.scroll_y = @as(f32, @floatFromInt(target_row)) * 21.0;
            }
        }
        if (uic.btn(next_label, .{ .w = .pixels(hunk_btn_w), .h = 24 })) {
            if (parsed.stats.hunks > 0) {
                view_state.current_hunk = (view_state.current_hunk + 1) % parsed.stats.hunks;
                const h_idx = @min(@as(usize, view_state.current_hunk), MaxDiffHunks - 1);
                const target_row = if (view_state.mode == .unified)
                    parsed.hunk_unified_rows[h_idx]
                else
                    parsed.hunk_split_rows[h_idx];
                view_state.selected_row = target_row;
                view_state.scroll_y = @as(f32, @floatFromInt(target_row)) * 21.0;
            }
        }

        if (!opts.is_commit_view) {
            const stage_btn_label = if (opts.staged) "Unstage##diff_stage_btn" else "Stage##diff_stage_btn";
            const stage_w: f32 = if (compact_bar) 48.0 else 62.0;
            if (uic.btn(stage_btn_label, .{ .w = .pixels(stage_w), .h = 24 })) {
                result.stage_toggle_requested = true;
            }
        }

        if (uic.btn("↺##diff_refresh_btn", .{ .w = .pixels(24), .h = 24 })) {
            result.refresh_requested = true;
        }

        const open_label = if (compact_bar) "File##diff_open_file_btn" else "Open File##diff_open_file_btn";
        const open_w: f32 = if (compact_bar) 38.0 else 74.0;
        if (uic.btn(open_label, .{ .w = .pixels(open_w), .h = 24 })) {
            result.open_file_requested = true;
            const target_line = resolveSelectedNewLine(parsed, view_state);
            if (target_line > 0) {
                result.clicked_new_line = target_line;
            }
        }
    }

    // 2. Scrollable Diff Canvas
    const resolved_canvas = uic.resolveIdAndLabel("##diff_viewer_canvas");
    const canvas_rect = uic.nextRect(total_w, canvas_h);
    const row_h: f32 = 21.0;
    const total_rows = if (view_state.mode == .unified) parsed.line_count else parsed.split_row_count;
    const content_h = @as(f32, @floatFromInt(@max(@as(usize, 1), total_rows))) * row_h + 24.0;
    const max_scroll_y = @max(0.0, content_h - canvas_h);

    if (uic.pass == .input) {
        const hovered = uic.isHovered(canvas_rect);
        if (hovered) {
            uic.hot_id = resolved_canvas.wid;
            if (uic.scroll_dy != 0.0 or uic.scroll_dx != 0.0) {
                const snapped = root.snapScrollAxis(uic.scroll_dx, uic.scroll_dy);
                const next_y = std.math.clamp(view_state.scroll_y - snapped.dy, 0.0, max_scroll_y);
                const next_x = @max(0.0, view_state.scroll_x - snapped.dx);
                if (next_y != view_state.scroll_y or next_x != view_state.scroll_x) {
                    view_state.scroll_y = next_y;
                    view_state.scroll_x = next_x;
                    uic.markDirty(canvas_rect);
                    uic.invalidateWindow();
                }
            }
            if (uic.mouse_pressed and total_rows > 0) {
                uic.focused_id = resolved_canvas.wid;
                const rel_y = @max(0.0, (uic.mouse_y - canvas_rect.top) + view_state.scroll_y);
                const clicked_row: usize = @min(total_rows - 1, @as(usize, @intFromFloat(@floor(rel_y / row_h))));
                view_state.selected_row = @intCast(clicked_row);

                // Clicking inside the line-number gutter jumps to that line in the file
                const rel_x = uic.mouse_x - canvas_rect.left;
                const half_w = @floor((canvas_rect.right - canvas_rect.left) * 0.5);
                const clicked_gutter = (view_state.mode == .unified and rel_x <= 78.0) or
                    (view_state.mode == .split and (rel_x <= 42.0 or (rel_x >= half_w and rel_x <= half_w + 42.0)));
                const ln = resolveRowNewLine(parsed, view_state.mode, clicked_row);
                if (clicked_gutter and ln > 0) {
                    result.open_file_requested = true;
                    result.clicked_new_line = ln;
                }
                uic.markDirty(canvas_rect);
                uic.invalidateWindow();
            }
        }
        view_state.scroll_y = std.math.clamp(view_state.scroll_y, 0.0, max_scroll_y);
    }

    if (uic.shouldPaint(canvas_rect)) {
        const save_clip = uic.canvas.save();
        defer uic.canvas.restoreToCount(save_clip);
        uic.canvas.clipRect(canvas_rect, .intersect, false);

        uic.paint.setStyle(.fill);
        uic.paint.setColor(Color.rgb(13, 17, 23));
        uic.canvas.drawRect(canvas_rect, uic.paint);

        if (total_rows == 0) {
            uic.paint.setColor(uic.theme.text_muted);
            uic.drawTextCached(
                uic.font_mono,
                "No diff hunks — working tree matches HEAD.",
                canvas_rect.left + 20.0,
                canvas_rect.top + 34.0,
            );
        } else if (view_state.mode == .unified) {
            paintUnifiedRows(uic, canvas_rect, parsed, view_state, row_h);
        } else {
            paintSplitRows(uic, canvas_rect, parsed, view_state, row_h);
        }

        // Draw subtle vertical scrollbar thumb when content overflows
        if (content_h > canvas_h + 1.0) {
            const track_h = canvas_h - 8.0;
            const thumb_h = @max(24.0, track_h * (canvas_h / content_h));
            const thumb_y = canvas_rect.top + 4.0 + (track_h - thumb_h) * (view_state.scroll_y / max_scroll_y);
            uic.paint.setStyle(.fill);
            uic.paint.setColor(Color.argb(90, 100, 116, 139));
            uic.canvas.drawRoundRect(Rect.xywh(canvas_rect.right - 7.0, thumb_y, 4.0, thumb_h), 2.0, 2.0, uic.paint);
        }
    }

    return result;
}

fn resolveRowNewLine(parsed: *const ParsedDiff, mode: DiffViewMode, row_idx: usize) usize {
    if (mode == .unified) {
        if (row_idx >= parsed.line_count) return 0;
        const dl = parsed.lines[row_idx];
        return if (dl.new_line > 0) dl.new_line else dl.old_line;
    } else {
        if (row_idx >= parsed.split_row_count) return 0;
        const sr = parsed.split_rows[row_idx];
        return if (sr.right_line > 0) sr.right_line else sr.left_line;
    }
}

fn resolveSelectedNewLine(parsed: *const ParsedDiff, view_state: *const DiffViewState) usize {
    const ln = resolveRowNewLine(parsed, view_state.mode, view_state.selected_row);
    if (ln > 0) return ln;
    if (parsed.stats.hunks > 0) {
        const h_row = parsed.hunk_unified_rows[0];
        if (h_row < parsed.line_count) {
            return parsed.lines[h_row].new_line;
        }
    }
    return 1;
}

fn paintUnifiedRows(
    uic: *Context,
    canvas_rect: c.sk_rect_t,
    parsed: *const ParsedDiff,
    view_state: *const DiffViewState,
    row_h: f32,
) void {
    const gutter_w: f32 = 76.0;
    const first_row: usize = @intFromFloat(@floor(@max(0.0, view_state.scroll_y / row_h)));
    const visible_count: usize = @as(usize, @intFromFloat(@ceil((canvas_rect.bottom - canvas_rect.top) / row_h))) + 2;
    const end_row = @min(parsed.line_count, first_row + visible_count);

    // Gutter background
    uic.paint.setStyle(.fill);
    uic.paint.setColor(Color.rgb(16, 21, 30));
    uic.canvas.drawRect(Rect.xywh(canvas_rect.left, canvas_rect.top, gutter_w, canvas_rect.bottom - canvas_rect.top), uic.paint);

    for (first_row..end_row) |r_idx| {
        const dl = parsed.lines[r_idx];
        const ry = canvas_rect.top + @as(f32, @floatFromInt(r_idx)) * row_h - view_state.scroll_y;
        const row_rect = Rect.xywh(canvas_rect.left, ry, canvas_rect.right - canvas_rect.left, row_h);
        const is_selected = (view_state.selected_row == r_idx);
        const baseline_y = ry + 15.0;

        switch (dl.kind) {
            .file_header => {
                uic.paint.setStyle(.fill);
                uic.paint.setColor(Color.rgb(24, 32, 46));
                uic.canvas.drawRect(row_rect, uic.paint);
                uic.paint.setColor(Color.rgb(121, 192, 255));
                uic.drawTextCached(uic.font_mono, uic.fmt("--- a/{s}   +++ b/{s}", .{ dl.text, dl.text }), canvas_rect.left + 12.0, baseline_y);
            },
            .hunk_header => {
                uic.paint.setStyle(.fill);
                uic.paint.setColor(Color.argb(42, 56, 139, 253));
                uic.canvas.drawRect(row_rect, uic.paint);
                uic.paint.setColor(Color.rgb(56, 139, 253));
                uic.canvas.drawRect(Rect.xywh(canvas_rect.left, ry, 3.0, row_h), uic.paint);
                uic.paint.setColor(Color.rgb(121, 192, 255));
                uic.drawTextCached(uic.font_mono, dl.text, canvas_rect.left + gutter_w + 10.0, baseline_y);
            },
            .addition => {
                uic.paint.setStyle(.fill);
                uic.paint.setColor(if (is_selected) Color.argb(68, 46, 160, 67) else Color.argb(36, 46, 160, 67));
                uic.canvas.drawRect(row_rect, uic.paint);
                uic.paint.setColor(Color.rgb(52, 211, 153));
                uic.canvas.drawRect(Rect.xywh(canvas_rect.left, ry, 3.0, row_h), uic.paint);

                const new_ln_str = uic.fmt("{d:>4}", .{dl.new_line});
                uic.paint.setColor(Color.rgb(52, 211, 153));
                uic.drawTextCached(uic.font_mono, new_ln_str, canvas_rect.left + 38.0, baseline_y);
                uic.drawTextCached(uic.font_mono, "+", canvas_rect.left + gutter_w + 6.0, baseline_y);

                uic.paint.setColor(Color.rgb(187, 247, 208));
                uic.drawTextCached(uic.font_mono, dl.text, canvas_rect.left + gutter_w + 22.0 - view_state.scroll_x, baseline_y);
            },
            .deletion => {
                uic.paint.setStyle(.fill);
                uic.paint.setColor(if (is_selected) Color.argb(68, 248, 81, 73) else Color.argb(36, 248, 81, 73));
                uic.canvas.drawRect(row_rect, uic.paint);
                uic.paint.setColor(Color.rgb(248, 113, 113));
                uic.canvas.drawRect(Rect.xywh(canvas_rect.left, ry, 3.0, row_h), uic.paint);

                const old_ln_str = uic.fmt("{d:>4}", .{dl.old_line});
                uic.paint.setColor(Color.rgb(248, 113, 113));
                uic.drawTextCached(uic.font_mono, old_ln_str, canvas_rect.left + 6.0, baseline_y);
                uic.drawTextCached(uic.font_mono, "-", canvas_rect.left + gutter_w + 6.0, baseline_y);

                uic.paint.setColor(Color.rgb(254, 202, 202));
                uic.drawTextCached(uic.font_mono, dl.text, canvas_rect.left + gutter_w + 22.0 - view_state.scroll_x, baseline_y);
            },
            .context => {
                if (is_selected) {
                    uic.paint.setStyle(.fill);
                    uic.paint.setColor(Color.argb(40, 56, 139, 253));
                    uic.canvas.drawRect(row_rect, uic.paint);
                }
                uic.paint.setColor(uic.theme.text_muted);
                if (dl.old_line > 0) {
                    uic.drawTextCached(uic.font_mono, uic.fmt("{d:>4}", .{dl.old_line}), canvas_rect.left + 6.0, baseline_y);
                }
                if (dl.new_line > 0) {
                    uic.drawTextCached(uic.font_mono, uic.fmt("{d:>4}", .{dl.new_line}), canvas_rect.left + 38.0, baseline_y);
                }
                uic.paint.setColor(Color.rgb(201, 209, 217));
                uic.drawTextCached(uic.font_mono, dl.text, canvas_rect.left + gutter_w + 22.0 - view_state.scroll_x, baseline_y);
            },
        }
    }

    // Gutter separator line
    uic.paint.setStyle(.fill);
    uic.paint.setColor(uic.theme.border_subtle);
    uic.canvas.drawRect(Rect.xywh(canvas_rect.left + gutter_w, canvas_rect.top, 1.0, canvas_rect.bottom - canvas_rect.top), uic.paint);
}

fn paintSplitRows(
    uic: *Context,
    canvas_rect: c.sk_rect_t,
    parsed: *const ParsedDiff,
    view_state: *const DiffViewState,
    row_h: f32,
) void {
    const total_w = canvas_rect.right - canvas_rect.left;
    const half_w = @floor(total_w * 0.5);
    const left_x = canvas_rect.left;
    const right_x = canvas_rect.left + half_w;
    const side_gutter_w: f32 = 42.0;

    const first_row: usize = @intFromFloat(@floor(@max(0.0, view_state.scroll_y / row_h)));
    const visible_count: usize = @as(usize, @intFromFloat(@ceil((canvas_rect.bottom - canvas_rect.top) / row_h))) + 2;
    const end_row = @min(parsed.split_row_count, first_row + visible_count);

    for (first_row..end_row) |r_idx| {
        const sr = parsed.split_rows[r_idx];
        const ry = canvas_rect.top + @as(f32, @floatFromInt(r_idx)) * row_h - view_state.scroll_y;
        const baseline_y = ry + 15.0;

        if (sr.is_header) {
            const full_rect = Rect.xywh(canvas_rect.left, ry, total_w, row_h);
            uic.paint.setStyle(.fill);
            uic.paint.setColor(if (sr.header_kind == .file_header)
                Color.rgb(24, 32, 46)
            else
                Color.argb(42, 56, 139, 253));
            uic.canvas.drawRect(full_rect, uic.paint);
            if (sr.header_kind == .hunk_header) {
                uic.paint.setColor(Color.rgb(56, 139, 253));
                uic.canvas.drawRect(Rect.xywh(canvas_rect.left, ry, 3.0, row_h), uic.paint);
            }
            uic.paint.setColor(Color.rgb(121, 192, 255));
            const hdr_str = if (sr.header_kind == .file_header)
                uic.fmt("--- a/{s}   +++ b/{s}", .{ sr.header_text, sr.header_text })
            else
                sr.header_text;
            uic.drawTextCached(uic.font_mono, hdr_str, canvas_rect.left + 12.0, baseline_y);
            continue;
        }

        // Left pane (HEAD / Old)
        {
            const l_rect = Rect.xywh(left_x, ry, half_w - 4.0, row_h);
            const save_l = uic.canvas.save();
            defer uic.canvas.restoreToCount(save_l);
            uic.canvas.clipRect(l_rect, .intersect, false);

            uic.paint.setStyle(.fill);
            if (!sr.left_present) {
                uic.paint.setColor(Color.argb(55, 22, 27, 36));
                uic.canvas.drawRect(Rect.xywh(left_x, ry, half_w, row_h), uic.paint);
            } else if (sr.left_kind == .deletion) {
                uic.paint.setColor(Color.argb(38, 248, 81, 73));
                uic.canvas.drawRect(Rect.xywh(left_x, ry, half_w, row_h), uic.paint);
                uic.paint.setColor(Color.rgb(248, 113, 113));
                uic.canvas.drawRect(Rect.xywh(left_x, ry, 2.5, row_h), uic.paint);
                uic.drawTextCached(uic.font_mono, uic.fmt("{d:>4}", .{sr.left_line}), left_x + 4.0, baseline_y);
                uic.drawTextCached(uic.font_mono, "-", left_x + side_gutter_w + 4.0, baseline_y);
                uic.paint.setColor(Color.rgb(254, 202, 202));
                uic.drawTextCached(uic.font_mono, sr.left_text, left_x + side_gutter_w + 18.0 - view_state.scroll_x, baseline_y);
            } else {
                uic.paint.setColor(uic.theme.text_muted);
                uic.drawTextCached(uic.font_mono, uic.fmt("{d:>4}", .{sr.left_line}), left_x + 4.0, baseline_y);
                uic.paint.setColor(Color.rgb(201, 209, 217));
                uic.drawTextCached(uic.font_mono, sr.left_text, left_x + side_gutter_w + 18.0 - view_state.scroll_x, baseline_y);
            }
        }

        // Right pane (Modified / New)
        {
            const r_rect = Rect.xywh(right_x, ry, (total_w - half_w) - 8.0, row_h);
            const save_r = uic.canvas.save();
            defer uic.canvas.restoreToCount(save_r);
            uic.canvas.clipRect(r_rect, .intersect, false);

            uic.paint.setStyle(.fill);
            if (!sr.right_present) {
                uic.paint.setColor(Color.argb(55, 22, 27, 36));
                uic.canvas.drawRect(Rect.xywh(right_x, ry, total_w - half_w, row_h), uic.paint);
            } else if (sr.right_kind == .addition) {
                uic.paint.setColor(Color.argb(38, 46, 160, 67));
                uic.canvas.drawRect(Rect.xywh(right_x, ry, total_w - half_w, row_h), uic.paint);
                uic.paint.setColor(Color.rgb(52, 211, 153));
                uic.canvas.drawRect(Rect.xywh(right_x, ry, 2.5, row_h), uic.paint);
                uic.drawTextCached(uic.font_mono, uic.fmt("{d:>4}", .{sr.right_line}), right_x + 4.0, baseline_y);
                uic.drawTextCached(uic.font_mono, "+", right_x + side_gutter_w + 4.0, baseline_y);
                uic.paint.setColor(Color.rgb(187, 247, 208));
                uic.drawTextCached(uic.font_mono, sr.right_text, right_x + side_gutter_w + 18.0 - view_state.scroll_x, baseline_y);
            } else {
                uic.paint.setColor(uic.theme.text_muted);
                uic.drawTextCached(uic.font_mono, uic.fmt("{d:>4}", .{sr.right_line}), right_x + 4.0, baseline_y);
                uic.paint.setColor(Color.rgb(201, 209, 217));
                uic.drawTextCached(uic.font_mono, sr.right_text, right_x + side_gutter_w + 18.0 - view_state.scroll_x, baseline_y);
            }
        }
    }

    // Gutter & center split dividers
    uic.paint.setStyle(.fill);
    uic.paint.setColor(uic.theme.border_subtle);
    uic.canvas.drawRect(Rect.xywh(left_x + side_gutter_w, canvas_rect.top, 1.0, canvas_rect.bottom - canvas_rect.top), uic.paint);
    uic.canvas.drawRect(Rect.xywh(right_x, canvas_rect.top, 1.0, canvas_rect.bottom - canvas_rect.top), uic.paint);
    uic.canvas.drawRect(Rect.xywh(right_x + side_gutter_w, canvas_rect.top, 1.0, canvas_rect.bottom - canvas_rect.top), uic.paint);
}

test "DiffViewer: parseUnifiedDiff and 2-phase Pass.input -> Pass.paint layout determinism" {
    var parsed = ParsedDiff{};
    parseUnifiedDiff(SAMPLE_GIT_DIFF, &parsed);
    try std.testing.expectEqual(@as(u32, 3), parsed.stats.additions);
    try std.testing.expectEqual(@as(u32, 1), parsed.stats.deletions);
    try std.testing.expectEqual(@as(u32, 1), parsed.stats.hunks);
    try std.testing.expect(parsed.line_count >= 8);
    try std.testing.expect(parsed.split_row_count >= 7);

    const surface = try skia.Surface.initRasterN32Premul(900, 600);
    defer surface.deinit();

    var pctx = @import("platform").PlatformContext{ .width = 900.0, .height = 600.0 };
    var fonts = root.FontSet.init(&pctx, .{});
    defer fonts.deinit();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var uic = fonts.initContext(arena.allocator(), &pctx);
    defer uic.deinit();

    var state = DiffViewState{ .mode = .unified };
    const win_rect = Rect.xywh(0, 0, 900, 600);

    // 1. Unified mode 2-phase determinism
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 20, 80, false, false, false);
    _ = renderDiffViewer(&uic, "test_diff", 900, 600, SAMPLE_GIT_DIFF, &state, .{ .title = "src/app/main.zig" });
    uic.endPass();

    uic.invalidateWindow();
    uic.clip_damage = win_rect;
    uic.beginPass(.paint, arena.allocator(), surface.canvas(), win_rect, 20, 80, false, false, false);
    _ = renderDiffViewer(&uic, "test_diff", 900, 600, SAMPLE_GIT_DIFF, &state, .{ .title = "src/app/main.zig" });
    uic.endPass();
    try std.testing.expectEqual(uic.last_input_rect_count, uic.last_paint_rect_count);

    // 2. Split mode 2-phase determinism
    state.mode = .split;
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 20, 80, false, false, false);
    _ = renderDiffViewer(&uic, "test_diff", 900, 600, SAMPLE_GIT_DIFF, &state, .{ .title = "src/app/main.zig" });
    uic.endPass();

    uic.invalidateWindow();
    uic.clip_damage = win_rect;
    uic.beginPass(.paint, arena.allocator(), surface.canvas(), win_rect, 20, 80, false, false, false);
    _ = renderDiffViewer(&uic, "test_diff", 900, 600, SAMPLE_GIT_DIFF, &state, .{ .title = "src/app/main.zig" });
    uic.endPass();
    try std.testing.expectEqual(uic.last_input_rect_count, uic.last_paint_rect_count);
}
