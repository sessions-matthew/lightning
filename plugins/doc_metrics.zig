//! Native Zig `.dylib` Editor Plugin: Document Metrics & Whitespace Cleaner (`plugins/doc_metrics.zig`).
//!
//! Compiled into `zig-out/plugins/libdoc_metrics.dylib` (~25 KB, zero Skia linkage) and dynamically
//! loaded + hot-reloaded by `src/app/plugin_manager.zig`.

const std = @import("std");
const sdk = @import("plugin_sdk");

/// Persistent plugin state stored in the host's `StateStore` (`"__plugins/builtin.doc_metrics/state"`).
/// Survives live `.dylib` hot-reloads without losing counters or user input!
const DocMetricsState = struct {
    note: sdk.InlineString(64) = .{},
    saves_observed: u32 = 0,
    edits_observed: u32 = 0,
    stripped_total_bytes: u32 = 0,
};

fn countWords(text: []const u8) usize {
    var words: usize = 0;
    var in_word = false;
    for (text) |b| {
        const is_ws = (b == ' ' or b == '\t' or b == '\n' or b == '\r');
        if (!is_ws and !in_word) {
            in_word = true;
            words += 1;
        } else if (is_ws) {
            in_word = false;
        }
    }
    return words;
}

fn registerCommands(ctx: *sdk.PluginContext) void {
    ctx.registerCommand(
        "doc_metrics.insert_stamp",
        "Plugin: Insert Document Metrics Stamp",
        "Plugins",
        "Metrics",
    );
    ctx.registerCommand(
        "doc_metrics.strip_trailing_ws",
        "Plugin: Strip Trailing Whitespace",
        "Plugins",
        "Clean",
    );
}

fn onInit(ctx: *sdk.PluginContext) void {
    registerCommands(ctx);
}

fn onReload(ctx: *sdk.PluginContext) void {
    registerCommands(ctx);
}

fn stripTrailingWhitespace(ctx: *sdk.PluginContext) void {
    const buf = ctx.activeBuffer() orelse return;
    if (buf.text.len == 0) return;

    var out = std.ArrayList(u8).empty;
    var removed: usize = 0;
    var it = std.mem.splitScalar(u8, buf.text, '\n');
    var first = true;
    while (it.next()) |line| {
        if (!first) {
            out.append(ctx.allocator(), '\n') catch return;
        }
        first = false;
        const trimmed = std.mem.trimEnd(u8, line, " \t\r");
        removed += (line.len - trimmed.len);
        out.appendSlice(ctx.allocator(), trimmed) catch return;
    }

    if (removed > 0) {
        if (ctx.replaceBufferRange(buf.buffer_id, 0, buf.text.len, out.items)) {
            const st = ctx.useState(DocMetricsState, "state", .{});
            st.stripped_total_bytes +|= @intCast(removed);
            ctx.setStatusNotice(ctx.fmt("Stripped {d} trailing whitespace bytes", .{removed}));
        }
    } else {
        ctx.setStatusNotice("No trailing whitespace found");
    }
}

fn insertMetricsStamp(ctx: *sdk.PluginContext) void {
    const buf = ctx.activeBuffer() orelse return;
    const words = countWords(buf.text);
    const est_tokens = (buf.text.len + 3) / 4;
    const stamp = ctx.fmt(
        "// [Metrics] {d} lines | {d} words | {d} bytes (~{d} tokens)\n",
        .{ buf.line_count, words, buf.text.len, est_tokens },
    );
    if (ctx.replaceBufferRange(buf.buffer_id, buf.cursor_offset, buf.cursor_offset, stamp)) {
        ctx.setStatusNotice("Inserted document metrics stamp");
    }
}

fn onCommand(ctx: *sdk.PluginContext, cmd_id: []const u8) void {
    if (std.mem.eql(u8, cmd_id, "doc_metrics.insert_stamp")) {
        insertMetricsStamp(ctx);
    } else if (std.mem.eql(u8, cmd_id, "doc_metrics.strip_trailing_ws")) {
        stripTrailingWhitespace(ctx);
    }
}

fn onBufferEdit(ctx: *sdk.PluginContext, _: sdk.BufferEditEvent) void {
    const st = ctx.useState(DocMetricsState, "state", .{});
    st.edits_observed +|= 1;
}

fn onBufferSave(ctx: *sdk.PluginContext, _: sdk.BufferInfo) void {
    const st = ctx.useState(DocMetricsState, "state", .{});
    st.saves_observed +|= 1;
}

fn renderStatusBar(ctx: *sdk.PluginContext) void {
    const buf = ctx.activeBuffer() orelse return;
    const words = countWords(buf.text);
    const est_tokens = (buf.text.len + 3) / 4;
    const label = ctx.fmt("{d}w · ~{d}tok##doc_metrics_chip", .{ words, est_tokens });
    if (ctx.ui.chip(label, false)) {
        stripTrailingWhitespace(ctx);
    }
}

fn renderSidebar(ctx: *sdk.PluginContext) void {
    const st = ctx.useState(DocMetricsState, "state", .{});
    ctx.ui.sectionLabel("DOCUMENT METRICS (.DYLIB)");

    if (ctx.activeBuffer()) |buf| {
        const words = countWords(buf.text);
        const est_tokens = (buf.text.len + 3) / 4;
        ctx.ui.monoLabel(ctx.fmt("File:    {s}", .{buf.file_path}));
        ctx.ui.monoLabel(ctx.fmt("Lines:   {d}   Words: {d}", .{ buf.line_count, words }));
        ctx.ui.monoLabel(ctx.fmt("Bytes:   {d}   ~Tokens: {d}", .{ buf.text.len, est_tokens }));
        ctx.ui.monoLabel(ctx.fmt("Edits:   {d}   Saves: {d}", .{ st.edits_observed, st.saves_observed }));
    }

    _ = ctx.ui.textFieldInline("##metrics_note", &st.note, "Scratch note (hot-reload safe)...");

    if (ctx.ui.button("Insert Metrics Stamp##plug_stamp", 0, 26)) {
        insertMetricsStamp(ctx);
    }
    if (ctx.ui.button("Strip Trailing Whitespace##plug_strip", 0, 26)) {
        stripTrailingWhitespace(ctx);
    }
}

comptime {
    sdk.exportEditorPlugin(.{
        .id = "builtin.doc_metrics",
        .display_name = "Document Metrics & Cleaner",
        .version = "1.0.0",
        .sidebar_title = "DOC METRICS",
        .init = onInit,
        .on_reload = onReload,
        .on_command = onCommand,
        .on_buffer_edit = onBufferEdit,
        .on_buffer_save = onBufferSave,
        .render_status_bar = renderStatusBar,
        .render_sidebar = renderSidebar,
    });
}
