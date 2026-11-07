//! Minimal 22pt Status Bar (Branch, Save Notice, Cursor Ln/Col, Encoding, Language).

const skia = @import("skia");
const ui = @import("ui");
const platform = @import("platform");
const state_mod = @import("../state.zig");
const EditorState = state_mod.EditorState;
const PlatformContext = platform.PlatformContext;

pub fn build(state: *EditorState, ctx: *const PlatformContext) void {
    _ = ctx;
    const uic = &state.ui_ctx;
    const active_opt = state.activeFileIndex();

    var bar = uic.row(.{
        .h = .pixels(22),
        .padding = ui.Padding{ .left = 12, .top = 2, .right = 12, .bottom = 2 },
        .gap = 16,
        .bg_color = skia.Color.rgb(16, 20, 28),
        .border_color = uic.theme.border_subtle,
        .border_width = 1.0,
        .border_edges = .top_only,
    });
    defer bar.end();

    const dirty_total = state.dirtyFileCount();
    const branch_str = if (dirty_total > 0) "main*" else "main";
    const dot_color = if (dirty_total > 0)
        skia.Color.rgb(251, 191, 36)
    else
        skia.Color.rgb(52, 211, 153);
    uic.statusDotIndicator(dot_color, branch_str, null);

    const notice = state.statusNotice();
    if (notice.len > 0) {
        uic.statusTextSegment(notice, null);
    }

    if (active_opt) |idx| {
        const file = state.workspaceFiles()[idx];
        const active_buf = &state.buffers[idx];
        const sel = active_buf.selectionRange();
        const sel_len = sel.end - sel.start;
        const right_status = if (EditorState.isAudioCandidatePath(file.path))
            uic.fmt("Audio Player    {s}", .{file.name})
        else if (EditorState.isVideoCandidatePath(file.path))
            uic.fmt("Video Player    {s}", .{file.name})
        else if (EditorState.isImageCandidatePath(file.path))
            uic.fmt("Image Viewer    {s}", .{file.name})
        else if (sel_len > 0)
            uic.fmt("Ln {d}, Col {d} ({d} selected)    UTF-8    {s}", .{
                state.doc.cursor_line,
                state.doc.cursor_col,
                sel_len,
                file.language.label(),
            })
        else
            uic.fmt("Ln {d}, Col {d}    UTF-8    {s}", .{
                state.doc.cursor_line,
                state.doc.cursor_col,
                file.language.label(),
            });

        const rw = uic.measureTextCached(uic.font_mono, right_status);
        if (uic.availableWidth() > rw + 24.0) {
            uic.fillSpacer(rw);
            uic.statusTextSegment(right_status, null);
        }
    }
}
