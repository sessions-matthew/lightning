//! Single-Line & Multi-Line Text Input State, Options & Results (`src/ui/text_input.zig`).
//!
//! Provides `TextInputState`, `TextFieldOptions`, `TextFieldResult`, `TextAreaOptions`,
//! and `TextAreaResult` for `ui.Context` text fields and multi-line text areas.

const std = @import("std");
const platform = @import("platform");
const layout_mod = @import("layout.zig");
const Size = layout_mod.Size;

pub const TextFieldOptions = struct {
    w: Size = .fill,
    h: f32 = 28.0,
    borderless: bool = false,
    use_body_font: bool = false,
    pad_x: ?f32 = null,
};

pub const TextFieldResult = struct {
    changed: bool = false,
    submitted: bool = false,
    escaped: bool = false,
    focused: bool = false,
    right_clicked: bool = false,
    arrow_up: bool = false,
    arrow_down: bool = false,
    tab_pressed: bool = false,
    pasted_image: ?platform.ClipboardImage = null,
};

pub const TextAreaOptions = struct {
    w: Size = .fill,
    h: f32 = 80.0,
    min_lines: usize = 1,
    max_lines: usize = 0,
    line_h: f32 = 16.0,
    pad_x: ?f32 = null,
    pad_y: f32 = 5.5,
    borderless: bool = false,
    use_body_font: bool = false,
    submit_on_enter: bool = false,
    allow_image_paste: bool = false,
    placeholder: []const u8 = "",
};

pub const TextAreaResult = TextFieldResult;

pub const WrappedLine = struct {
    start: usize,
    end: usize,
    hard_start: usize,
    hard_end: usize,
    is_hard_end: bool,
};

pub fn findVisualLineForOffset(vlines: []const WrappedLine, offset: usize) usize {
    for (vlines, 0..) |vl, i| {
        if (vl.is_hard_end) {
            if (offset >= vl.start and offset <= vl.end) return i;
        } else {
            if (offset >= vl.start and offset < vl.end) return i;
        }
    }
    return vlines.len - 1;
}

/// Steps a 0-based `selected_idx` with wrap-around when `tf.arrow_down`, `tf.tab_pressed`, or `tf.arrow_up`
/// occurs on a focused search/palette input. Returns `true` if `selected_idx` changed.
pub fn stepListSelection(selected_idx: *usize, count: usize, tf: TextFieldResult) bool {
    if (count == 0) {
        selected_idx.* = 0;
        return false;
    }
    if (selected_idx.* >= count) {
        selected_idx.* = count - 1;
    }
    if (tf.arrow_down or tf.tab_pressed) {
        selected_idx.* = (selected_idx.* + 1) % count;
        return true;
    } else if (tf.arrow_up) {
        selected_idx.* = if (selected_idx.* == 0) count - 1 else selected_idx.* - 1;
        return true;
    }
    return false;
}

/// Persistent per-widget state for `textFieldEx` and `textArea`, stored via `useState`.
/// Tracks caret position, selection anchor, scroll offsets, mouse multi-click drag mode,
/// and a single-slot undo/redo snapshot buffer.
pub const TextInputState = struct {
    cursor: u32 = 0,
    anchor: u32 = 0,
    scroll_x: f32 = 0,
    scroll_line: u32 = 0,
    last_len: u32 = 0,
    initialized: bool = false,
    drag_mode: u8 = 0, // 0 = none, 1 = char, 2 = word, 3 = line/all
    drag_origin_start: u32 = 0,
    drag_origin_end: u32 = 0,
    undo_valid: bool = false,
    undo_len: u16 = 0,
    undo_cursor: u32 = 0,
    undo_buf: [4096]u8 = undefined,
    ctx_menu_open: bool = false,
    ctx_menu_opened_this_frame: bool = false,
    ctx_menu_x: f32 = 0,
    ctx_menu_y: f32 = 0,
    last_box_h: f32 = 0,

    pub fn syncExternalLen(self: *TextInputState, cur_len: usize) void {
        const clen: u32 = @intCast(cur_len);
        if (!self.initialized or self.last_len != clen or self.cursor > clen or self.anchor > clen) {
            self.cursor = clen;
            self.anchor = clen;
            self.last_len = clen;
            self.initialized = true;
        }
    }

    pub fn hasSelection(self: *const TextInputState) bool {
        return self.cursor != self.anchor;
    }

    pub fn selStart(self: *const TextInputState) usize {
        return @min(self.cursor, self.anchor);
    }

    pub fn selEnd(self: *const TextInputState) usize {
        return @max(self.cursor, self.anchor);
    }

    pub fn selectAll(self: *TextInputState, len: usize) void {
        self.anchor = 0;
        self.cursor = @intCast(len);
    }

    pub fn saveUndo(self: *TextInputState, buf: []const u8, len: usize) void {
        const n = @min(len, self.undo_buf.len);
        @memcpy(self.undo_buf[0..n], buf[0..n]);
        self.undo_len = @intCast(n);
        self.undo_cursor = self.cursor;
        self.undo_valid = true;
    }

    pub fn performUndoSwap(self: *TextInputState, buf: []u8, len: *usize) bool {
        if (!self.undo_valid) return false;
        var tmp: [4096]u8 = undefined;
        const cur_n = @min(len.*, tmp.len);
        const cur_cursor = self.cursor;
        @memcpy(tmp[0..cur_n], buf[0..cur_n]);

        const restore_n = @min(@as(usize, self.undo_len), buf.len);
        @memcpy(buf[0..restore_n], self.undo_buf[0..restore_n]);
        len.* = restore_n;
        self.cursor = @min(self.undo_cursor, @as(u32, @intCast(restore_n)));
        self.anchor = self.cursor;
        self.last_len = @intCast(restore_n);

        @memcpy(self.undo_buf[0..cur_n], tmp[0..cur_n]);
        self.undo_len = @intCast(cur_n);
        self.undo_cursor = cur_cursor;
        return true;
    }

    pub fn deleteRange(self: *TextInputState, buf: []u8, len: *usize, start: usize, end: usize) bool {
        const s = @min(start, len.*);
        const e = @min(end, len.*);
        if (e <= s) {
            self.cursor = @intCast(s);
            self.anchor = @intCast(s);
            return false;
        }
        const rem = len.* - e;
        if (rem > 0) {
            std.mem.copyForwards(u8, buf[s .. s + rem], buf[e..len.*]);
        }
        len.* -= (e - s);
        self.cursor = @intCast(s);
        self.anchor = @intCast(s);
        self.last_len = @intCast(len.*);
        return true;
    }

    pub fn deleteSelection(self: *TextInputState, buf: []u8, len: *usize) bool {
        return self.deleteRange(buf, len, self.selStart(), self.selEnd());
    }

    pub fn insertBytes(self: *TextInputState, buf: []u8, len: *usize, bytes: []const u8, allow_newlines: bool) bool {
        var changed = false;
        if (self.hasSelection()) {
            changed = self.deleteSelection(buf, len);
        }
        const cur: usize = @min(@as(usize, self.cursor), len.*);
        const avail = buf.len -| len.*;
        if (avail == 0 or bytes.len == 0) {
            self.cursor = @intCast(cur);
            self.anchor = @intCast(cur);
            self.last_len = @intCast(len.*);
            return changed;
        }

        // Count how many sanitized bytes will be inserted so we shift the tail in a single O(N) memmove
        var insert_count: usize = 0;
        for (bytes, 0..) |b, i| {
            if (insert_count >= avail) break;
            if (b == '\r') {
                if (i + 1 < bytes.len and bytes[i + 1] == '\n') continue;
                insert_count += 1;
            } else if (b == '\n' or b == '\t' or (b >= 0x20 and b != 0x7f)) {
                insert_count += 1;
            }
        }
        if (insert_count == 0) {
            self.cursor = @intCast(cur);
            self.anchor = @intCast(cur);
            self.last_len = @intCast(len.*);
            return changed;
        }

        // Avoid splitting a multi-byte UTF-8 sequence if truncated at buffer capacity
        while (insert_count > 0 and insert_count < bytes.len and (bytes[insert_count] & 0b1100_0000) == 0b1000_0000) {
            insert_count -= 1;
        }
        if (insert_count == 0) return changed;

        if (cur < len.*) {
            std.mem.copyBackwards(u8, buf[cur + insert_count .. len.* + insert_count], buf[cur..len.*]);
        }

        var write_idx: usize = cur;
        const end_write = cur + insert_count;
        for (bytes, 0..) |b, i| {
            if (write_idx >= end_write) break;
            if (b == '\r') {
                if (i + 1 < bytes.len and bytes[i + 1] == '\n') continue;
                buf[write_idx] = if (allow_newlines) '\n' else ' ';
                write_idx += 1;
            } else if (b == '\n') {
                buf[write_idx] = if (allow_newlines) '\n' else ' ';
                write_idx += 1;
            } else if (b == '\t') {
                buf[write_idx] = ' ';
                write_idx += 1;
            } else if (b >= 0x20 and b != 0x7f) {
                buf[write_idx] = b;
                write_idx += 1;
            }
        }

        len.* += (write_idx - cur);
        self.cursor = @intCast(write_idx);
        self.anchor = @intCast(write_idx);
        self.last_len = @intCast(len.*);
        return true;
    }
};

test "TextInputState: selection, insertBytes, deleteSelection, undo swap, and stepListSelection" {
    var st = TextInputState{};
    var buf: [32]u8 = undefined;
    var len: usize = 5;
    @memcpy(buf[0..5], "hello");

    st.syncExternalLen(len);
    try std.testing.expectEqual(@as(u32, 5), st.cursor);

    st.saveUndo(&buf, len);
    try std.testing.expect(st.insertBytes(&buf, &len, " world", false));
    try std.testing.expectEqualStrings("hello world", buf[0..len]);

    try std.testing.expect(st.performUndoSwap(&buf, &len));
    try std.testing.expectEqualStrings("hello", buf[0..len]);

    try std.testing.expect(st.performUndoSwap(&buf, &len));
    try std.testing.expectEqualStrings("hello world", buf[0..len]);

    st.selectAll(len);
    try std.testing.expect(st.hasSelection());
    try std.testing.expect(st.deleteSelection(&buf, &len));
    try std.testing.expectEqual(@as(usize, 0), len);

    var sel_idx: usize = 0;
    try std.testing.expect(stepListSelection(&sel_idx, 3, .{ .arrow_down = true }));
    try std.testing.expectEqual(@as(usize, 1), sel_idx);
    try std.testing.expect(stepListSelection(&sel_idx, 3, .{ .arrow_up = true }));
    try std.testing.expectEqual(@as(usize, 0), sel_idx);
    try std.testing.expect(stepListSelection(&sel_idx, 3, .{ .arrow_up = true }));
    try std.testing.expectEqual(@as(usize, 2), sel_idx);
}
