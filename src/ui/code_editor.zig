//! Interactive Multi-Line Text & Code Editor Component for `ui.Context`.
//!
//! Features:
//!   - Hot-reload-safe fixed-capacity `CodeEditorBuffer(MaxBytes)` (`CodeEditorState` = 16 KB default)
//!   - Full cursor & selection navigation (Arrows, Word-jump `Alt+Left/Right`, Line `Cmd+Left/Right`, `Home/End`, `PageUp/Down`)
//!   - Mouse click cursor placement, click-and-drag text selection, and gutter line selection
//!   - Smart editing: `Enter` auto-indentation & brace expansion, `Tab`/`Shift+Tab` block indent/outdent,
//!     auto-closing bracket/quote pairs, `Cmd+/` line comment toggle, `Cmd+D` line duplication
//!   - Built-in Undo/Redo ring (`Cmd+Z` / `Cmd+Shift+Z`) and Copy/Cut/Paste (`Cmd+C`, `Cmd+X`, `Cmd+V`, `Cmd+A`)
//!   - Multi-language syntax highlighting (`zig`, `markdown`, `json`, `bash`, `plain`), indentation guides,
//!     interactive minimap, and integrated status bar

const std = @import("std");
const skia = @import("skia");
const platform = @import("platform");
const root = @import("root.zig");
const c = skia.c;
const Color = skia.Color;
const Rect = skia.Rect;
const Font = skia.Font;
const Context = root.Context;
const Padding = root.Padding;
const ScrollState = root.ScrollState;
const KeyCode = platform.KeyCode;
const KeyEvent = platform.KeyEvent;

pub const CodeLanguage = enum(u8) {
    zig,
    cpp,
    java,
    go,
    systemverilog,
    rust,
    python,
    typescript,
    vhdl,
    chisel,
    devicetree,
    markdown,
    json,
    bash,
    plain,

    pub fn label(self: CodeLanguage) []const u8 {
        return switch (self) {
            .zig => "Zig",
            .cpp => "C/C++",
            .java => "Java",
            .go => "Go",
            .systemverilog => "SystemVerilog",
            .rust => "Rust",
            .python => "Python",
            .typescript => "TypeScript",
            .vhdl => "VHDL",
            .chisel => "Chisel (Scala)",
            .devicetree => "DeviceTree",
            .markdown => "Markdown",
            .json => "JSON",
            .bash => "Shell",
            .plain => "Plain Text",
        };
    }

    pub fn commentPrefix(self: CodeLanguage) []const u8 {
        return switch (self) {
            .zig, .cpp, .java, .go, .systemverilog, .rust, .typescript, .chisel, .devicetree, .json => "// ",
            .bash, .python => "# ",
            .vhdl => "-- ",
            .markdown, .plain => "// ",
        };
    }

    pub fn fromPath(path: []const u8) CodeLanguage {
        if (std.mem.endsWith(u8, path, ".zig") or std.mem.endsWith(u8, path, ".zon")) return .zig;
        if (std.mem.endsWith(u8, path, ".c") or
            std.mem.endsWith(u8, path, ".cc") or
            std.mem.endsWith(u8, path, ".cpp") or
            std.mem.endsWith(u8, path, ".cxx") or
            std.mem.endsWith(u8, path, ".h") or
            std.mem.endsWith(u8, path, ".hpp") or
            std.mem.endsWith(u8, path, ".hxx"))
        {
            return .cpp;
        }
        if (std.mem.endsWith(u8, path, ".java")) return .java;
        if (std.mem.endsWith(u8, path, ".go")) return .go;
        if (std.mem.endsWith(u8, path, ".sv") or
            std.mem.endsWith(u8, path, ".svh") or
            std.mem.endsWith(u8, path, ".v") or
            std.mem.endsWith(u8, path, ".vh") or
            std.mem.endsWith(u8, path, ".systemverilog") or
            std.mem.endsWith(u8, path, ".verilog"))
        {
            return .systemverilog;
        }
        if (std.mem.endsWith(u8, path, ".rs")) return .rust;
        if (std.mem.endsWith(u8, path, ".py") or std.mem.endsWith(u8, path, ".pyi")) return .python;
        if (std.mem.endsWith(u8, path, ".ts") or
            std.mem.endsWith(u8, path, ".tsx") or
            std.mem.endsWith(u8, path, ".js") or
            std.mem.endsWith(u8, path, ".jsx") or
            std.mem.endsWith(u8, path, ".mjs"))
        {
            return .typescript;
        }
        if (std.mem.endsWith(u8, path, ".vhd") or std.mem.endsWith(u8, path, ".vhdl")) return .vhdl;
        if (std.mem.endsWith(u8, path, ".scala") or std.mem.endsWith(u8, path, ".sc")) return .chisel;
        if (std.mem.endsWith(u8, path, ".dts") or std.mem.endsWith(u8, path, ".dtsi")) return .devicetree;
        if (std.mem.endsWith(u8, path, ".md") or std.mem.endsWith(u8, path, ".markdown")) return .markdown;
        if (std.mem.endsWith(u8, path, ".json")) return .json;
        const base = std.fs.path.basename(path);
        if (std.mem.endsWith(u8, path, ".sh") or
            std.mem.endsWith(u8, path, ".bash") or
            std.mem.endsWith(u8, path, ".zsh") or
            std.mem.endsWith(u8, path, ".envrc") or
            std.mem.endsWith(u8, path, ".gitignore") or
            std.mem.endsWith(u8, path, ".cfg") or
            std.mem.endsWith(u8, path, ".gdb") or
            std.mem.endsWith(u8, path, ".mk") or
            std.mem.eql(u8, base, "Makefile") or
            std.mem.eql(u8, base, "makefile"))
        {
            return .bash;
        }
        return .plain;
    }

    pub fn fromFence(fence_info: []const u8) CodeLanguage {
        const trimmed = std.mem.trim(u8, fence_info, " \t\r\n");
        if (trimmed.len == 0) return .plain;
        if (std.ascii.startsWithIgnoreCase(trimmed, "system verilog")) return .systemverilog;

        var tok_end: usize = 0;
        while (tok_end < trimmed.len and
            trimmed[tok_end] != ' ' and
            trimmed[tok_end] != '\t' and
            trimmed[tok_end] != ',' and
            trimmed[tok_end] != '{' and
            trimmed[tok_end] != ';') : (tok_end += 1)
        {}
        var tok = trimmed[0..tok_end];
        if (std.mem.startsWith(u8, tok, ".")) tok = tok[1..];
        if (tok.len == 0) return .plain;

        if (std.ascii.eqlIgnoreCase(tok, "systemverilog") or
            std.ascii.eqlIgnoreCase(tok, "system-verilog") or
            std.ascii.eqlIgnoreCase(tok, "system_verilog") or
            std.ascii.eqlIgnoreCase(tok, "verilog") or
            std.ascii.eqlIgnoreCase(tok, "sv") or
            std.ascii.eqlIgnoreCase(tok, "svh") or
            std.ascii.eqlIgnoreCase(tok, "v") or
            std.ascii.eqlIgnoreCase(tok, "vh"))
        {
            return .systemverilog;
        }
        if (std.ascii.eqlIgnoreCase(tok, "zig") or std.ascii.eqlIgnoreCase(tok, "zon")) return .zig;
        if (std.ascii.eqlIgnoreCase(tok, "c") or
            std.ascii.eqlIgnoreCase(tok, "cc") or
            std.ascii.eqlIgnoreCase(tok, "cpp") or
            std.ascii.eqlIgnoreCase(tok, "c++") or
            std.ascii.eqlIgnoreCase(tok, "cxx") or
            std.ascii.eqlIgnoreCase(tok, "h") or
            std.ascii.eqlIgnoreCase(tok, "hpp") or
            std.ascii.eqlIgnoreCase(tok, "hxx") or
            std.ascii.eqlIgnoreCase(tok, "objc"))
        {
            return .cpp;
        }
        if (std.ascii.eqlIgnoreCase(tok, "java")) return .java;
        if (std.ascii.eqlIgnoreCase(tok, "go") or std.ascii.eqlIgnoreCase(tok, "golang")) return .go;
        if (std.ascii.eqlIgnoreCase(tok, "rs") or std.ascii.eqlIgnoreCase(tok, "rust")) return .rust;
        if (std.ascii.eqlIgnoreCase(tok, "py") or
            std.ascii.eqlIgnoreCase(tok, "pyi") or
            std.ascii.eqlIgnoreCase(tok, "python") or
            std.ascii.eqlIgnoreCase(tok, "python3"))
        {
            return .python;
        }
        if (std.ascii.eqlIgnoreCase(tok, "ts") or
            std.ascii.eqlIgnoreCase(tok, "tsx") or
            std.ascii.eqlIgnoreCase(tok, "js") or
            std.ascii.eqlIgnoreCase(tok, "jsx") or
            std.ascii.eqlIgnoreCase(tok, "mjs") or
            std.ascii.eqlIgnoreCase(tok, "typescript") or
            std.ascii.eqlIgnoreCase(tok, "javascript"))
        {
            return .typescript;
        }
        if (std.ascii.eqlIgnoreCase(tok, "vhd") or std.ascii.eqlIgnoreCase(tok, "vhdl")) return .vhdl;
        if (std.ascii.eqlIgnoreCase(tok, "scala") or
            std.ascii.eqlIgnoreCase(tok, "sc") or
            std.ascii.eqlIgnoreCase(tok, "chisel"))
        {
            return .chisel;
        }
        if (std.ascii.eqlIgnoreCase(tok, "dts") or
            std.ascii.eqlIgnoreCase(tok, "dtsi") or
            std.ascii.eqlIgnoreCase(tok, "devicetree"))
        {
            return .devicetree;
        }
        if (std.ascii.eqlIgnoreCase(tok, "md") or
            std.ascii.eqlIgnoreCase(tok, "markdown") or
            std.ascii.eqlIgnoreCase(tok, "gfm"))
        {
            return .markdown;
        }
        if (std.ascii.eqlIgnoreCase(tok, "json") or
            std.ascii.eqlIgnoreCase(tok, "jsonc") or
            std.ascii.eqlIgnoreCase(tok, "json5"))
        {
            return .json;
        }
        if (std.ascii.eqlIgnoreCase(tok, "sh") or
            std.ascii.eqlIgnoreCase(tok, "bash") or
            std.ascii.eqlIgnoreCase(tok, "zsh") or
            std.ascii.eqlIgnoreCase(tok, "shell") or
            std.ascii.eqlIgnoreCase(tok, "shellscript") or
            std.ascii.eqlIgnoreCase(tok, "console") or
            std.ascii.eqlIgnoreCase(tok, "terminal") or
            std.ascii.eqlIgnoreCase(tok, "make") or
            std.ascii.eqlIgnoreCase(tok, "makefile") or
            std.ascii.eqlIgnoreCase(tok, "mk") or
            std.ascii.eqlIgnoreCase(tok, "cfg") or
            std.ascii.eqlIgnoreCase(tok, "conf") or
            std.ascii.eqlIgnoreCase(tok, "ini") or
            std.ascii.eqlIgnoreCase(tok, "toml") or
            std.ascii.eqlIgnoreCase(tok, "yaml") or
            std.ascii.eqlIgnoreCase(tok, "yml") or
            std.ascii.eqlIgnoreCase(tok, "envrc") or
            std.ascii.eqlIgnoreCase(tok, "gitignore") or
            std.ascii.eqlIgnoreCase(tok, "gdb"))
        {
            return .bash;
        }
        if (std.ascii.eqlIgnoreCase(tok, "text") or
            std.ascii.eqlIgnoreCase(tok, "plaintext") or
            std.ascii.eqlIgnoreCase(tok, "txt") or
            std.ascii.eqlIgnoreCase(tok, "plain") or
            std.ascii.eqlIgnoreCase(tok, "none"))
        {
            return .plain;
        }
        return fromPath(tok);
    }
};

pub const CompletionPopupItem = struct {
    label: []const u8 = "",
    detail: []const u8 = "",
    insert_text: []const u8 = "",
    kind: u8 = 0, // 0=keyword, 1=fn/method, 2=type/class/struct, 3=snippet, 4=field/var
    replace_prefix_len: u16 = 0,
};

pub const CodeEditorOptions = struct {
    language: CodeLanguage = .zig,
    font: ?Font = null,
    line_height: f32 = 21.0,
    show_line_numbers: bool = true,
    show_breakpoint_gutter: bool = false,
    show_indent_guides: bool = true,
    show_minimap: bool = false,
    show_status_bar: bool = true,
    syntax_highlight: bool = true,
    auto_close_pairs: bool = true,
    read_only: bool = false,
    tab_width: u8 = 4,
    word_wrap: bool = false,
    search_query: []const u8 = "",
    ghost_text: []const u8 = "",
    ghost_delete_len: usize = 0,
    completions: []const CompletionPopupItem = &.{},
    selected_completion: usize = 0,
    breakpoint_lines: ?[]const u32 = null,
    active_debug_line: ?u32 = null,
    is_active_pane: bool = true,
    pane_index: ?u8 = null,
    scroll_state: ?*ScrollState = null,
};

pub const CodeEditorResult = struct {
    text_changed: bool = false,
    cursor_changed: bool = false,
    save_requested: bool = false,
    find_requested: bool = false,
    right_clicked: bool = false,
    ghost_accepted: bool = false,
    ghost_dismissed: bool = false,
    completion_accepted: bool = false,
    completion_dismissed: bool = false,
    completion_selection_changed: bool = false,
    selected_completion: usize = 0,
    toggled_breakpoint_line: ?u32 = null,
    focused: bool = false,
    cursor_line: usize = 1,
    cursor_col: usize = 1,
    line_count: usize = 1,
    selection_len: usize = 0,
};

pub const BreakpointGutterWidth: f32 = 20.0;

pub const DefaultBufferCapacity: usize = 8192;
pub const CodeEditorState = CodeEditorBuffer(DefaultBufferCapacity);

pub fn CodeEditorBuffer(comptime MaxBytes: usize) type {
    return struct {
        const Self = @This();
        pub const Capacity = MaxBytes;
        const UndoInlineBytes: usize = @min(MaxBytes, 128);
        const MaxIndexedLines: usize = 2048;

        const UndoSlot = struct {
            offset: usize = 0,
            before_bytes: [UndoInlineBytes]u8 = @splat(0),
            after_bytes: [UndoInlineBytes]u8 = @splat(0),
            before_heap_ptr: ?[*]u8 = null,
            before_heap_cap: usize = 0,
            after_heap_ptr: ?[*]u8 = null,
            after_heap_cap: usize = 0,
            before_len: usize = 0,
            after_len: usize = 0,
            before_cursor: usize = 0,
            before_anchor: usize = 0,
            after_cursor: usize = 0,
            after_anchor: usize = 0,

            fn beforeSlice(self: *const UndoSlot) []const u8 {
                const ptr = self.before_heap_ptr orelse &self.before_bytes;
                return ptr[0..self.before_len];
            }

            fn afterSlice(self: *const UndoSlot) []const u8 {
                const ptr = self.after_heap_ptr orelse &self.after_bytes;
                return ptr[0..self.after_len];
            }

            fn storeBefore(self: *UndoSlot, src: []const u8) void {
                if (src.len <= UndoInlineBytes) {
                    if (src.len > 0) @memcpy(self.before_bytes[0..src.len], src);
                    self.before_len = src.len;
                    return;
                }
                if (src.len > self.before_heap_cap or self.before_heap_ptr == null) {
                    const new_cap = @max(src.len + (src.len / 4), 4096);
                    if (std.heap.c_allocator.alloc(u8, new_cap)) |new_buf| {
                        if (self.before_heap_ptr) |old_ptr| {
                            std.heap.c_allocator.free(old_ptr[0..self.before_heap_cap]);
                        }
                        self.before_heap_ptr = new_buf.ptr;
                        self.before_heap_cap = new_buf.len;
                    } else |_| {
                        const n = @min(src.len, UndoInlineBytes);
                        @memcpy(self.before_bytes[0..n], src[0..n]);
                        self.before_len = n;
                        return;
                    }
                }
                if (self.before_heap_ptr) |hp| {
                    @memcpy(hp[0..src.len], src);
                    self.before_len = src.len;
                }
            }

            fn storeAfter(self: *UndoSlot, src: []const u8) void {
                if (src.len <= UndoInlineBytes) {
                    if (src.len > 0) @memcpy(self.after_bytes[0..src.len], src);
                    self.after_len = src.len;
                    return;
                }
                if (src.len > self.after_heap_cap or self.after_heap_ptr == null) {
                    const new_cap = @max(src.len + (src.len / 4), 4096);
                    if (std.heap.c_allocator.alloc(u8, new_cap)) |new_buf| {
                        if (self.after_heap_ptr) |old_ptr| {
                            std.heap.c_allocator.free(old_ptr[0..self.after_heap_cap]);
                        }
                        self.after_heap_ptr = new_buf.ptr;
                        self.after_heap_cap = new_buf.len;
                    } else |_| {
                        const n = @min(src.len, UndoInlineBytes);
                        @memcpy(self.after_bytes[0..n], src[0..n]);
                        self.after_len = n;
                        return;
                    }
                }
                if (self.after_heap_ptr) |hp| {
                    @memcpy(hp[0..src.len], src);
                    self.after_len = src.len;
                }
            }

            fn deinit(self: *UndoSlot) void {
                if (self.before_heap_ptr) |hp| {
                    std.heap.c_allocator.free(hp[0..self.before_heap_cap]);
                    self.before_heap_ptr = null;
                    self.before_heap_cap = 0;
                }
                if (self.after_heap_ptr) |hp| {
                    std.heap.c_allocator.free(hp[0..self.after_heap_cap]);
                    self.after_heap_ptr = null;
                    self.after_heap_cap = 0;
                }
                self.before_len = 0;
                self.after_len = 0;
            }
        };

        buf: [MaxBytes]u8 = @splat(0),
        heap_ptr: ?[*]u8 = null,
        heap_cap: usize = 0,
        len: usize = 0,
        cursor: usize = 0,
        selection_anchor: usize = 0,
        preferred_col: ?usize = null,
        scroll_state: ScrollState = .{},
        split_scroll_states: [7]ScrollState = @splat(.{}),
        scroll_to_cursor_pending: bool = false,
        scroll_align_top: bool = false,
        flash_line: u32 = 0,
        flash_frames: u8 = 0,
        dragging_text: bool = false,
        drag_click_mode: u8 = 0, // 0 = char, 1 = word (double-click), 2 = line (triple-click)
        drag_origin_start: usize = 0,
        drag_origin_end: usize = 0,

        // Internal clipboard (256-byte inline fast path + dynamic heap overflow for larger copies/pastes)
        clipboard_buf: [256]u8 = @splat(0),
        clipboard_heap_ptr: ?[*]u8 = null,
        clipboard_heap_cap: usize = 0,
        clipboard_len: usize = 0,

        // Incremental Line-Start Offset Index (`lineStartsPtr()[i]` = byte offset of 0-based line `i`)
        line_starts: [MaxIndexedLines]u32 = @splat(0),
        line_starts_heap: ?[*]u32 = null,
        line_starts_cap: u32 = MaxIndexedLines,
        line_starts_len: u32 = 1,
        line_index_overflow: bool = false,
        max_line_cols: u32 = 0,

        // 16-slot Delta Undo/Redo history stack + typing-run coalescing
        undo_slots: [16]UndoSlot = @splat(.{}),
        undo_len: u8 = 0,
        undo_pos: u8 = 0,
        edit_version: u32 = 1,
        undo_checkpoint_pending: bool = false,
        suppress_undo_record: bool = false,
        pending_undo_cursor: usize = 0,
        pending_undo_anchor: usize = 0,
        typing_coalesce_active: bool = false,
        typing_coalesce_cursor: usize = 0,
        typing_coalesce_count: u8 = 0,

        // Inline per-buffer breakpoint lines (1-based) & gutter hover tracking
        bp_lines: [16]u32 = @splat(0),
        bp_count: u8 = 0,
        hovered_bp_line: u32 = 0,

        pub fn breakpointsSlice(self: *const Self) []const u32 {
            return self.bp_lines[0..self.bp_count];
        }

        pub fn hasBreakpoint(self: *const Self, line_1based: u32) bool {
            for (self.bp_lines[0..self.bp_count]) |ln| {
                if (ln == line_1based) return true;
            }
            return false;
        }

        pub fn toggleBreakpoint(self: *Self, line_1based: u32) bool {
            if (line_1based == 0) return false;
            var i: usize = 0;
            while (i < self.bp_count) : (i += 1) {
                if (self.bp_lines[i] == line_1based) {
                    var j = i;
                    while (j + 1 < self.bp_count) : (j += 1) {
                        self.bp_lines[j] = self.bp_lines[j + 1];
                    }
                    self.bp_count -= 1;
                    return false;
                }
            }
            if (self.bp_count < self.bp_lines.len) {
                self.bp_lines[self.bp_count] = line_1based;
                self.bp_count += 1;
                return true;
            }
            return false;
        }

        pub fn clearBreakpoints(self: *Self) void {
            self.bp_count = 0;
        }

        pub fn scrollStateForPane(self: *Self, pane_idx: usize) *ScrollState {
            if (pane_idx == 0) return &self.scroll_state;
            const slot = @min(pane_idx - 1, self.split_scroll_states.len - 1);
            return &self.split_scroll_states[slot];
        }

        pub fn copyScrollStateBetweenPanes(self: *Self, from_pane: usize, to_pane: usize) void {
            if (from_pane == to_pane) return;
            const src = self.scrollStateForPane(from_pane).*;
            const dst = self.scrollStateForPane(to_pane);
            dst.* = .{
                .scroll_x = src.scroll_x,
                .scroll_y = src.scroll_y,
                .content_width = src.content_width,
                .content_height = src.content_height,
            };
        }

        pub inline fn dataPtr(self: *Self) [*]u8 {
            return self.heap_ptr orelse &self.buf;
        }

        pub inline fn constDataPtr(self: *const Self) [*]const u8 {
            return self.heap_ptr orelse &self.buf;
        }

        pub inline fn capacity(self: *const Self) usize {
            return if (self.heap_ptr != null) self.heap_cap else MaxBytes;
        }

        pub inline fn lineStartsPtr(self: *Self) [*]u32 {
            return self.line_starts_heap orelse &self.line_starts;
        }

        pub inline fn constLineStartsPtr(self: *const Self) [*]const u32 {
            return self.line_starts_heap orelse &self.line_starts;
        }

        pub fn ensureLineCapacity(self: *Self, needed: usize) bool {
            if (needed <= self.line_starts_cap) return true;
            var new_cap: usize = @max(@as(usize, self.line_starts_cap), 4096);
            while (new_cap < needed) {
                new_cap = new_cap + (new_cap / 2) + 2048;
            }
            const new_slice = std.heap.c_allocator.alloc(u32, new_cap) catch return false;
            if (self.line_starts_len > 0) {
                @memcpy(new_slice[0..self.line_starts_len], self.constLineStartsPtr()[0..self.line_starts_len]);
            }
            if (self.line_starts_heap) |old_ptr| {
                std.heap.c_allocator.free(old_ptr[0..self.line_starts_cap]);
            }
            self.line_starts_heap = new_slice.ptr;
            self.line_starts_cap = @intCast(new_slice.len);
            return true;
        }

        pub fn ensureCapacity(self: *Self, needed: usize) bool {
            if (needed <= self.capacity()) return true;
            var new_cap = @max(self.capacity(), 65536);
            while (new_cap < needed) {
                new_cap = new_cap + (new_cap / 2) + 16384;
            }
            const new_slice = std.heap.c_allocator.alloc(u8, new_cap) catch return false;
            if (self.len > 0) {
                @memcpy(new_slice[0..self.len], self.constDataPtr()[0..self.len]);
            }
            if (self.heap_ptr) |old_ptr| {
                std.heap.c_allocator.free(old_ptr[0..self.heap_cap]);
            }
            self.heap_ptr = new_slice.ptr;
            self.heap_cap = new_slice.len;
            return true;
        }

        pub fn deinit(self: *Self) void {
            if (self.heap_ptr) |hp| {
                std.heap.c_allocator.free(hp[0..self.heap_cap]);
                self.heap_ptr = null;
                self.heap_cap = 0;
            }
            if (self.line_starts_heap) |lhp| {
                std.heap.c_allocator.free(lhp[0..self.line_starts_cap]);
                self.line_starts_heap = null;
                self.line_starts_cap = MaxIndexedLines;
            }
            if (self.clipboard_heap_ptr) |chp| {
                std.heap.c_allocator.free(chp[0..self.clipboard_heap_cap]);
                self.clipboard_heap_ptr = null;
                self.clipboard_heap_cap = 0;
            }
            for (&self.undo_slots) |*slot| {
                slot.deinit();
            }
            self.len = 0;
            self.clipboard_len = 0;
            self.line_starts_len = 1;
            self.undo_len = 0;
            self.undo_pos = 0;
        }

        pub fn initFromSlice(initial: []const u8) Self {
            var s = Self{};
            s.setText(initial);
            return s;
        }

        pub fn resetWithSlice(self: *Self, initial: []const u8) void {
            self.cursor = 0;
            self.selection_anchor = 0;
            self.preferred_col = null;
            self.scroll_state = .{};
            self.split_scroll_states = @splat(.{});
            self.scroll_to_cursor_pending = false;
            self.scroll_align_top = false;
            self.flash_line = 0;
            self.flash_frames = 0;
            self.dragging_text = false;
            self.undo_len = 0;
            self.undo_pos = 0;
            self.undo_checkpoint_pending = false;
            self.typing_coalesce_active = false;
            self.setText(initial);
        }

        pub fn setText(self: *Self, text: []const u8) void {
            _ = self.ensureCapacity(text.len);
            const copy_len = @min(text.len, self.capacity());
            if (self.undo_checkpoint_pending and !self.suppress_undo_record) {
                self.commitUndoDelta(0, self.slice(), text[0..copy_len], copy_len, copy_len);
                self.undo_checkpoint_pending = false;
            }
            if (copy_len > 0) {
                @memcpy(self.dataPtr()[0..copy_len], text[0..copy_len]);
            }
            self.len = copy_len;
            self.cursor = @min(self.cursor, copy_len);
            self.selection_anchor = self.cursor;
            self.preferred_col = null;
            self.typing_coalesce_active = false;
            self.edit_version +%= 1;
            if (self.edit_version == 0) self.edit_version = 1;
            self.rebuildLineIndex();
        }

        pub fn rebuildLineIndex(self: *Self) void {
            self.lineStartsPtr()[0] = 0;
            var count: usize = 1;
            var max_cols: usize = 0;
            self.line_index_overflow = false;
            const s = self.constDataPtr()[0..self.len];
            var pos: usize = 0;
            while (std.mem.indexOfScalarPos(u8, s, pos, '\n')) |nl_idx| {
                const line_len = nl_idx - pos;
                if (line_len > max_cols) max_cols = line_len;
                if (count >= self.line_starts_cap) {
                    self.line_starts_len = @intCast(count);
                    if (!self.ensureLineCapacity(count + 2048)) {
                        self.line_index_overflow = true;
                        break;
                    }
                }
                self.lineStartsPtr()[count] = @intCast(nl_idx + 1);
                count += 1;
                pos = nl_idx + 1;
            }
            if (self.len >= pos) {
                const tail_cols = self.len - pos;
                if (tail_cols > max_cols) max_cols = tail_cols;
            }
            self.line_starts_len = @intCast(count);
            self.max_line_cols = @intCast(max_cols);
        }

        pub fn slice(self: *const Self) []const u8 {
            return self.constDataPtr()[0..self.len];
        }

        pub fn hasSelection(self: *const Self) bool {
            return self.cursor != self.selection_anchor;
        }

        pub const ByteRange = struct { start: usize, end: usize };

        pub fn selectionRange(self: *const Self) ByteRange {
            return .{
                .start = @min(self.cursor, self.selection_anchor),
                .end = @max(self.cursor, self.selection_anchor),
            };
        }

        pub fn selectedSlice(self: *const Self) []const u8 {
            const r = self.selectionRange();
            return self.constDataPtr()[r.start..r.end];
        }

        pub fn lineCount(self: *const Self) usize {
            if (!self.line_index_overflow and self.line_starts_len > 0) {
                return self.line_starts_len;
            }
            var count: usize = 1;
            for (self.slice()) |b| {
                if (b == '\n') count += 1;
            }
            return count;
        }

        pub fn offsetToLineCol(self: *const Self, offset: usize) struct { line: usize, col: usize } {
            const clamped = @min(offset, self.len);
            if (!self.line_index_overflow and self.line_starts_len > 0) {
                const starts = self.constLineStartsPtr();
                var lo: usize = 0;
                var hi: usize = self.line_starts_len;
                while (lo + 1 < hi) {
                    const mid = lo + (hi - lo) / 2;
                    if (starts[mid] <= clamped) {
                        lo = mid;
                    } else {
                        hi = mid;
                    }
                }
                const line_start: usize = starts[lo];
                return .{ .line = lo, .col = clamped - line_start };
            }
            var line: usize = 0;
            var line_start: usize = 0;
            for (self.constDataPtr()[0..clamped], 0..) |b, idx| {
                if (b == '\n') {
                    line += 1;
                    line_start = idx + 1;
                }
            }
            return .{ .line = line, .col = clamped - line_start };
        }

        pub fn cursorLineCol(self: *const Self) struct { line: usize, col: usize } {
            const lc = self.offsetToLineCol(self.cursor);
            return .{ .line = lc.line + 1, .col = lc.col + 1 };
        }

        pub fn lineRangeAtOffset(self: *const Self, offset: usize) ByteRange {
            if (!self.line_index_overflow and self.line_starts_len > 0) {
                const lc = self.offsetToLineCol(offset);
                return self.lineRangeByIndex(lc.line);
            }
            const d = self.constDataPtr();
            const clamped = @min(offset, self.len);
            var start = clamped;
            while (start > 0 and d[start - 1] != '\n') {
                start -= 1;
            }
            var end = clamped;
            while (end < self.len and d[end] != '\n') {
                end += 1;
            }
            return .{ .start = start, .end = end };
        }

        pub fn lineRangeByIndex(self: *const Self, target_line: usize) ByteRange {
            if (!self.line_index_overflow and self.line_starts_len > 0) {
                const starts = self.constLineStartsPtr();
                const n: usize = self.line_starts_len;
                if (target_line >= n) {
                    const last_start: usize = starts[n - 1];
                    return .{ .start = last_start, .end = self.len };
                }
                const start: usize = starts[target_line];
                const end: usize = if (target_line + 1 < n)
                    @as(usize, starts[target_line + 1]) -| 1
                else
                    self.len;
                return .{ .start = start, .end = end };
            }
            const d = self.constDataPtr();
            var cur_line: usize = 0;
            var start: usize = 0;
            var i: usize = 0;
            while (i < self.len) : (i += 1) {
                if (cur_line == target_line) {
                    var end = i;
                    while (end < self.len and d[end] != '\n') : (end += 1) {}
                    return .{ .start = start, .end = end };
                }
                if (d[i] == '\n') {
                    cur_line += 1;
                    start = i + 1;
                }
            }
            return .{ .start = start, .end = self.len };
        }

        // ====================================================================
        // Delta Undo / Redo Checkpoints
        // ====================================================================

        pub fn saveUndoCheckpoint(self: *Self) void {
            self.undo_checkpoint_pending = true;
            self.typing_coalesce_active = false;
            self.pending_undo_cursor = self.cursor;
            self.pending_undo_anchor = self.selection_anchor;
        }

        fn commitUndoDelta(
            self: *Self,
            offset: usize,
            before_slice: []const u8,
            after_slice: []const u8,
            after_cursor: usize,
            after_anchor: usize,
        ) void {
            var slot_idx: usize = self.undo_pos;
            if (slot_idx >= self.undo_slots.len) {
                const recycled = self.undo_slots[0];
                for (0 .. self.undo_slots.len - 1) |idx| {
                    self.undo_slots[idx] = self.undo_slots[idx + 1];
                }
                self.undo_slots[self.undo_slots.len - 1] = recycled;
                slot_idx = self.undo_slots.len - 1;
            }
            var slot = &self.undo_slots[slot_idx];
            slot.offset = offset;
            slot.storeBefore(before_slice);
            slot.storeAfter(after_slice);
            slot.before_cursor = self.pending_undo_cursor;
            slot.before_anchor = self.pending_undo_anchor;
            slot.after_cursor = after_cursor;
            slot.after_anchor = after_anchor;

            self.undo_pos = @intCast(slot_idx + 1);
            self.undo_len = self.undo_pos;
        }

        pub fn undo(self: *Self) bool {
            if (self.undo_pos == 0) return false;
            self.undo_pos -= 1;
            const slot = &self.undo_slots[self.undo_pos];

            self.suppress_undo_record = true;
            defer self.suppress_undo_record = false;

            _ = self.replaceRange(slot.offset, slot.offset + slot.after_len, slot.beforeSlice());
            self.cursor = @min(slot.before_cursor, self.len);
            self.selection_anchor = @min(slot.before_anchor, self.len);
            self.preferred_col = null;
            self.scroll_to_cursor_pending = true;
            self.undo_checkpoint_pending = false;
            self.typing_coalesce_active = false;
            return true;
        }

        pub fn redo(self: *Self) bool {
            if (self.undo_pos >= self.undo_len) return false;
            const slot = &self.undo_slots[self.undo_pos];
            self.undo_pos += 1;

            self.suppress_undo_record = true;
            defer self.suppress_undo_record = false;

            _ = self.replaceRange(slot.offset, slot.offset + slot.before_len, slot.afterSlice());
            self.cursor = @min(slot.after_cursor, self.len);
            self.selection_anchor = @min(slot.after_anchor, self.len);
            self.preferred_col = null;
            self.scroll_to_cursor_pending = true;
            self.undo_checkpoint_pending = false;
            self.typing_coalesce_active = false;
            return true;
        }

        // ====================================================================
        // Low-Level Splice Mutation
        // ====================================================================

        pub fn replaceRange(self: *Self, start: usize, end: usize, replacement: []const u8) bool {
            const s = @min(start, self.len);
            const e = @max(s, @min(end, self.len));
            const removed_len = e - s;
            const tail_len = self.len - e;

            const needed = (self.len - removed_len) + replacement.len;
            _ = self.ensureCapacity(needed);

            const max_insert = self.capacity() - (self.len - removed_len);
            const insert_len = @min(replacement.len, max_insert);
            if (removed_len == 0 and insert_len == 0) return false;

            const d = self.dataPtr();
            const removed_has_nl = std.mem.indexOfScalar(u8, d[s..e], '\n') != null;
            const inserted_has_nl = std.mem.indexOfScalar(u8, replacement[0..insert_len], '\n') != null;

            // Record delta undo entry before overwriting `d[s..e]`
            if (!self.suppress_undo_record) {
                if (self.typing_coalesce_active and !self.undo_checkpoint_pending and self.undo_pos > 0 and removed_len == 0) {
                    var slot = &self.undo_slots[self.undo_pos - 1];
                    if (slot.offset + slot.after_len == s and slot.after_len + insert_len <= UndoInlineBytes and slot.after_heap_ptr == null) {
                        @memcpy(slot.after_bytes[slot.after_len .. slot.after_len + insert_len], replacement[0..insert_len]);
                        slot.after_len += insert_len;
                        slot.after_cursor = s + insert_len;
                        slot.after_anchor = s + insert_len;
                    } else {
                        self.pending_undo_cursor = self.cursor;
                        self.pending_undo_anchor = self.selection_anchor;
                        self.commitUndoDelta(s, d[s..e], replacement[0..insert_len], s + insert_len, s + insert_len);
                    }
                } else if (self.undo_checkpoint_pending) {
                    self.commitUndoDelta(s, d[s..e], replacement[0..insert_len], s + insert_len, s + insert_len);
                    self.undo_checkpoint_pending = false;
                }
            }

            const new_len = self.len - removed_len + insert_len;
            if (insert_len != removed_len and tail_len > 0) {
                @memmove(
                    d[s + insert_len .. s + insert_len + tail_len],
                    d[e .. e + tail_len],
                );
            }
            if (insert_len > 0) {
                @memcpy(d[s .. s + insert_len], replacement[0..insert_len]);
            }

            self.len = new_len;
            self.cursor = s + insert_len;
            self.selection_anchor = self.cursor;
            self.preferred_col = null;
            self.scroll_to_cursor_pending = true;
            self.edit_version +%= 1;
            if (self.edit_version == 0) self.edit_version = 1;

            if (!self.line_index_overflow and !removed_has_nl and !inserted_has_nl and self.line_starts_len > 0) {
                // Fast incremental shift of subsequent line-start offsets without rescanning buffer
                const lc = self.offsetToLineCol(s);
                const first_shifted = lc.line + 1;
                const starts = self.lineStartsPtr();
                if (insert_len >= removed_len) {
                    const add_off: u32 = @intCast(insert_len - removed_len);
                    for (starts[first_shifted..self.line_starts_len]) |*ls| {
                        ls.* += add_off;
                    }
                } else {
                    const sub_off: u32 = @intCast(removed_len - insert_len);
                    for (starts[first_shifted..self.line_starts_len]) |*ls| {
                        ls.* -|= sub_off;
                    }
                }
                const edited_lr = self.lineRangeByIndex(lc.line);
                const edited_cols: u32 = @intCast(edited_lr.end - edited_lr.start);
                if (edited_cols > self.max_line_cols) {
                    self.max_line_cols = edited_cols;
                }
            } else {
                self.rebuildLineIndex();
            }
            return true;
        }

        pub fn acceptGhostText(self: *Self, ghost_text: []const u8, delete_len: usize) bool {
            if (ghost_text.len == 0) return false;
            self.saveUndoCheckpoint();
            const start = self.cursor -| delete_len;
            return self.replaceRange(start, self.cursor, ghost_text);
        }

        pub fn deleteSelection(self: *Self) bool {
            if (!self.hasSelection()) return false;
            const r = self.selectionRange();
            return self.replaceRange(r.start, r.end, "");
        }

        // ====================================================================
        // Cursor & Selection Movement
        // ====================================================================

        fn finalizeMove(self: *Self, new_cursor: usize, extend_sel: bool, keep_preferred_col: bool) void {
            self.cursor = snapToGraphemeBoundary(self.slice(), @min(new_cursor, self.len));
            if (!extend_sel) {
                self.selection_anchor = self.cursor;
            }
            if (!keep_preferred_col) {
                self.preferred_col = null;
            }
            self.scroll_to_cursor_pending = true;
        }

        pub fn moveLeft(self: *Self, extend_sel: bool, by_word: bool, to_line_start: bool) void {
            if (!extend_sel and self.hasSelection() and !to_line_start and !by_word) {
                const r = self.selectionRange();
                self.finalizeMove(r.start, false, false);
                return;
            }
            const d = self.constDataPtr();
            if (to_line_start) {
                const lr = self.lineRangeAtOffset(self.cursor);
                // Toggle between first non-whitespace char and column 0
                var first_non_ws = lr.start;
                while (first_non_ws < lr.end and (d[first_non_ws] == ' ' or d[first_non_ws] == '\t')) : (first_non_ws += 1) {}
                const target = if (self.cursor == first_non_ws) lr.start else first_non_ws;
                self.finalizeMove(target, extend_sel, false);
                return;
            }
            if (by_word) {
                var pos = self.cursor;
                while (pos > 0 and !isWordChar(d[pos - 1])) : (pos -= 1) {}
                while (pos > 0 and isWordChar(d[pos - 1])) : (pos -= 1) {}
                self.finalizeMove(pos, extend_sel, false);
                return;
            }
            if (self.cursor > 0) {
                const pos = prevGraphemeBoundary(self.slice(), self.cursor);
                self.finalizeMove(pos, extend_sel, false);
            } else if (!extend_sel) {
                self.selection_anchor = self.cursor;
            }
        }

        pub fn moveRight(self: *Self, extend_sel: bool, by_word: bool, to_line_end: bool) void {
            if (!extend_sel and self.hasSelection() and !to_line_end and !by_word) {
                const r = self.selectionRange();
                self.finalizeMove(r.end, false, false);
                return;
            }
            const d = self.constDataPtr();
            if (to_line_end) {
                const lr = self.lineRangeAtOffset(self.cursor);
                self.finalizeMove(lr.end, extend_sel, false);
                return;
            }
            if (by_word) {
                var pos = self.cursor;
                while (pos < self.len and !isWordChar(d[pos])) : (pos += 1) {}
                while (pos < self.len and isWordChar(d[pos])) : (pos += 1) {}
                self.finalizeMove(pos, extend_sel, false);
                return;
            }
            if (self.cursor < self.len) {
                const pos = nextGraphemeBoundary(self.slice(), self.cursor);
                self.finalizeMove(pos, extend_sel, false);
            } else if (!extend_sel) {
                self.selection_anchor = self.cursor;
            }
        }

        pub fn moveUp(self: *Self, extend_sel: bool) void {
            const lc = self.offsetToLineCol(self.cursor);
            const target_col = self.preferred_col orelse lc.col;
            self.preferred_col = target_col;

            if (lc.line == 0) {
                self.finalizeMove(0, extend_sel, true);
                return;
            }
            const prev_lr = self.lineRangeByIndex(lc.line - 1);
            const prev_len = prev_lr.end - prev_lr.start;
            self.finalizeMove(prev_lr.start + @min(target_col, prev_len), extend_sel, true);
        }

        pub fn moveDown(self: *Self, extend_sel: bool) void {
            const lc = self.offsetToLineCol(self.cursor);
            const target_col = self.preferred_col orelse lc.col;
            self.preferred_col = target_col;

            const total_lines = self.lineCount();
            if (lc.line + 1 >= total_lines) {
                self.finalizeMove(self.len, extend_sel, true);
                return;
            }
            const next_lr = self.lineRangeByIndex(lc.line + 1);
            const next_len = next_lr.end - next_lr.start;
            self.finalizeMove(next_lr.start + @min(target_col, next_len), extend_sel, true);
        }

        pub fn movePage(self: *Self, delta_lines: isize, extend_sel: bool) void {
            const lc = self.offsetToLineCol(self.cursor);
            const target_col = self.preferred_col orelse lc.col;
            self.preferred_col = target_col;

            const total_lines: isize = @intCast(self.lineCount());
            const cur_line_i: isize = @intCast(lc.line);
            const dest_line: usize = @intCast(std.math.clamp(cur_line_i + delta_lines, 0, @max(0, total_lines - 1)));
            const dest_lr = self.lineRangeByIndex(dest_line);
            const dest_len = dest_lr.end - dest_lr.start;
            self.finalizeMove(dest_lr.start + @min(target_col, dest_len), extend_sel, true);
        }

        pub fn selectAll(self: *Self) void {
            self.selection_anchor = 0;
            self.cursor = self.len;
            self.preferred_col = null;
        }

        // ====================================================================
        // High-Level Editing Commands
        // ====================================================================

        pub fn insertText(self: *Self, text: []const u8, auto_pairs: bool) bool {
            if (text.len == 0) return false;
            const can_coalesce = (text.len == 1 and text[0] != '\n' and text[0] != ' ' and !self.hasSelection());
            if (can_coalesce) {
                if (!self.typing_coalesce_active or self.cursor != self.typing_coalesce_cursor or self.typing_coalesce_count >= 24) {
                    self.saveUndoCheckpoint();
                    self.typing_coalesce_active = true;
                    self.typing_coalesce_count = 0;
                }
                self.typing_coalesce_count += 1;
            } else {
                self.saveUndoCheckpoint();
            }

            // Single-character auto-closing bracket / quote pair handling
            if (auto_pairs and text.len == 1 and !self.hasSelection()) {
                const ch = text[0];
                const d = self.constDataPtr();
                const lr = self.lineRangeAtOffset(self.cursor);
                const prev_ch: u8 = if (self.cursor > lr.start) d[self.cursor - 1] else 0;
                const next_ch: u8 = if (self.cursor < lr.end) d[self.cursor] else 0;

                if (isSymmetricQuote(ch)) {
                    const count_before = countUnescapedQuote(d[lr.start..self.cursor], ch);
                    const count_after = countUnescapedQuote(d[self.cursor..lr.end], ch);

                    // Step over existing closing quote/backtick only when closing an open pair on this line
                    if (next_ch == ch and prev_ch != '\\' and (count_before % 2 == 1)) {
                        self.cursor += 1;
                        self.selection_anchor = self.cursor;
                        self.typing_coalesce_cursor = self.cursor;
                        self.scroll_to_cursor_pending = true;
                        return false;
                    }

                    // Auto-insert closing quote/backtick only when balanced and not part of `"""` / ```` ``` ```` or a word (`don't`)
                    if (prev_ch != ch and
                        prev_ch != '\\' and
                        !isWordChar(prev_ch) and
                        next_ch != ch and
                        !isWordChar(next_ch) and
                        (count_before + count_after) % 2 == 0)
                    {
                        const pair = [2]u8{ ch, ch };
                        if (self.replaceRange(self.cursor, self.cursor, &pair)) {
                            self.cursor -= 1;
                            self.selection_anchor = self.cursor;
                            self.typing_coalesce_cursor = self.cursor;
                            return true;
                        }
                    }
                } else {
                    // Step over existing closing bracket if typed directly
                    if ((ch == ')' or ch == ']' or ch == '}') and next_ch == ch and prev_ch != '\\') {
                        self.cursor += 1;
                        self.selection_anchor = self.cursor;
                        self.typing_coalesce_cursor = self.cursor;
                        self.scroll_to_cursor_pending = true;
                        return false;
                    }

                    if (closingPairFor(ch)) |close_ch| {
                        if (prev_ch != '\\' and (next_ch == 0 or !isWordChar(next_ch))) {
                            const pair = [2]u8{ ch, close_ch };
                            if (self.replaceRange(self.cursor, self.cursor, &pair)) {
                                self.cursor -= 1;
                                self.selection_anchor = self.cursor;
                                self.typing_coalesce_cursor = self.cursor;
                                return true;
                            }
                        }
                    }
                }
            }

            const r = self.selectionRange();
            const ok = self.replaceRange(r.start, r.end, text);
            if (ok and can_coalesce) {
                self.typing_coalesce_cursor = self.cursor;
            }
            return ok;
        }

        pub fn insertNewlineAutoIndent(self: *Self, tab_width: u8) bool {
            self.saveUndoCheckpoint();
            if (self.hasSelection()) {
                _ = self.deleteSelection();
            }

            const d = self.constDataPtr();
            const lr = self.lineRangeAtOffset(self.cursor);
            var indent_spaces: usize = 0;
            while (lr.start + indent_spaces < self.cursor and d[lr.start + indent_spaces] == ' ') {
                indent_spaces += 1;
            }

            const prev_char: u8 = if (self.cursor > lr.start) d[self.cursor - 1] else 0;
            const next_char: u8 = if (self.cursor < self.len) d[self.cursor] else 0;
            const opens_block = (prev_char == '{' or prev_char == '(' or prev_char == '[' or prev_char == ':');
            const between_braces = (prev_char == '{' and next_char == '}') or
                (prev_char == '(' and next_char == ')') or
                (prev_char == '[' and next_char == ']');

            var insert_buf: [128]u8 = undefined;
            var pos: usize = 0;
            insert_buf[pos] = '\n';
            pos += 1;

            const inner_indent = @min(indent_spaces + (if (opens_block) @as(usize, tab_width) else 0), 48);
            for (0..inner_indent) |_| {
                insert_buf[pos] = ' ';
                pos += 1;
            }

            const cursor_after = self.cursor + pos;

            if (between_braces) {
                insert_buf[pos] = '\n';
                pos += 1;
                const outer_indent = @min(indent_spaces, 48);
                for (0..outer_indent) |_| {
                    insert_buf[pos] = ' ';
                    pos += 1;
                }
            }

            const changed = self.replaceRange(self.cursor, self.cursor, insert_buf[0..pos]);
            if (changed) {
                self.cursor = @min(cursor_after, self.len);
                self.selection_anchor = self.cursor;
            }
            return changed;
        }

        pub fn deleteBackward(self: *Self, by_word: bool, to_line_start: bool, tab_width: u8) bool {
            if (self.hasSelection()) {
                self.saveUndoCheckpoint();
                return self.deleteSelection();
            }
            if (self.cursor == 0) return false;
            self.saveUndoCheckpoint();

            const d = self.constDataPtr();
            if (to_line_start) {
                const lr = self.lineRangeAtOffset(self.cursor);
                if (self.cursor > lr.start) {
                    return self.replaceRange(lr.start, self.cursor, "");
                }
                return self.replaceRange(self.cursor - 1, self.cursor, "");
            }

            if (by_word) {
                var pos = self.cursor;
                while (pos > 0 and !isWordChar(d[pos - 1])) : (pos -= 1) {}
                while (pos > 0 and isWordChar(d[pos - 1])) : (pos -= 1) {}
                return self.replaceRange(pos, self.cursor, "");
            }

            // Delete matching empty pair e.g. `{|}` -> `|`
            if (self.cursor < self.len) {
                const prev_ch = d[self.cursor - 1];
                const next_ch = d[self.cursor];
                if (closingPairFor(prev_ch)) |expected_close| {
                    if (next_ch == expected_close) {
                        return self.replaceRange(self.cursor - 1, self.cursor + 1, "");
                    }
                }
            }

            // Smart backspace in leading indentation deletes up to `tab_width` spaces
            const lr = self.lineRangeAtOffset(self.cursor);
            const col = self.cursor - lr.start;
            if (col > 0 and isAllSpaces(d[lr.start..self.cursor])) {
                const tw: usize = @max(1, tab_width);
                const step = if (col % tw == 0) tw else col % tw;
                return self.replaceRange(self.cursor - step, self.cursor, "");
            }

            const start = prevGraphemeBoundary(self.slice(), self.cursor);
            return self.replaceRange(start, self.cursor, "");
        }

        pub fn deleteForward(self: *Self, by_word: bool) bool {
            if (self.hasSelection()) {
                self.saveUndoCheckpoint();
                return self.deleteSelection();
            }
            if (self.cursor >= self.len) return false;
            self.saveUndoCheckpoint();

            const d = self.constDataPtr();
            if (by_word) {
                var pos = self.cursor;
                while (pos < self.len and !isWordChar(d[pos])) : (pos += 1) {}
                while (pos < self.len and isWordChar(d[pos])) : (pos += 1) {}
                return self.replaceRange(self.cursor, pos, "");
            }

            const end = nextGraphemeBoundary(self.slice(), self.cursor);
            return self.replaceRange(self.cursor, end, "");
        }

        pub fn indentOrInsertTab(self: *Self, tab_width: u8) bool {
            self.saveUndoCheckpoint();
            const tw: usize = @max(1, @min(tab_width, 8));
            const spaces = "        "[0..tw];

            if (!self.hasSelection()) {
                const lc = self.offsetToLineCol(self.cursor);
                const to_next_stop = tw - (lc.col % tw);
                return self.replaceRange(self.cursor, self.cursor, spaces[0..to_next_stop]);
            }

            const cursor_at_end = (self.cursor >= self.selection_anchor);
            const sel = self.selectionRange();
            const start_line = self.offsetToLineCol(sel.start).line;
            const end_lc = self.offsetToLineCol(sel.end);
            const end_line = if (end_lc.col == 0 and end_lc.line > start_line) end_lc.line - 1 else end_lc.line;

            var new_sel_start = sel.start;
            var new_sel_end = sel.end;
            var changed = false;
            var line_idx = start_line;
            while (line_idx <= end_line) : (line_idx += 1) {
                const lr = self.lineRangeByIndex(line_idx);
                const prev_len = self.len;
                if (self.replaceRange(lr.start, lr.start, spaces)) {
                    const added = self.len - prev_len;
                    if (line_idx == start_line and new_sel_start > lr.start) {
                        new_sel_start += added;
                    }
                    new_sel_end += added;
                    changed = true;
                }
            }

            new_sel_start = @min(new_sel_start, self.len);
            new_sel_end = @min(new_sel_end, self.len);
            if (cursor_at_end) {
                self.selection_anchor = new_sel_start;
                self.cursor = new_sel_end;
            } else {
                self.cursor = new_sel_start;
                self.selection_anchor = new_sel_end;
            }
            return changed;
        }

        pub fn outdentSelection(self: *Self, tab_width: u8) bool {
            self.saveUndoCheckpoint();
            const tw: usize = @max(1, @min(tab_width, 8));
            const has_sel = self.hasSelection();
            const cursor_at_end = (self.cursor >= self.selection_anchor);
            const sel = self.selectionRange();
            const start_line = self.offsetToLineCol(sel.start).line;
            const end_lc = self.offsetToLineCol(sel.end);
            const end_line = if (has_sel and end_lc.col == 0 and end_lc.line > start_line) end_lc.line - 1 else end_lc.line;

            var new_sel_start = sel.start;
            var new_sel_end = sel.end;
            var changed = false;
            var line_idx = start_line;
            while (line_idx <= end_line) : (line_idx += 1) {
                const lr = self.lineRangeByIndex(line_idx);
                var rem: usize = 0;
                while (rem < tw and lr.start + rem < lr.end and self.constDataPtr()[lr.start + rem] == ' ') {
                    rem += 1;
                }
                if (rem > 0) {
                    if (self.replaceRange(lr.start, lr.start + rem, "")) {
                        if (line_idx == start_line and new_sel_start > lr.start) {
                            const shift = @min(rem, new_sel_start - lr.start);
                            new_sel_start -= shift;
                        }
                        if (new_sel_end > lr.start) {
                            const shift_end = @min(rem, new_sel_end - lr.start);
                            new_sel_end -= shift_end;
                        }
                        changed = true;
                    }
                }
            }

            new_sel_start = @min(new_sel_start, self.len);
            new_sel_end = @max(new_sel_start, @min(new_sel_end, self.len));
            if (cursor_at_end) {
                self.selection_anchor = new_sel_start;
                self.cursor = new_sel_end;
            } else {
                self.cursor = new_sel_start;
                self.selection_anchor = new_sel_end;
            }
            return changed;
        }

        pub fn toggleLineComment(self: *Self, prefix: []const u8) bool {
            self.saveUndoCheckpoint();
            const d = self.constDataPtr();
            const lr = self.lineRangeAtOffset(self.cursor);
            var ws_end = lr.start;
            while (ws_end < lr.end and (d[ws_end] == ' ' or d[ws_end] == '\t')) : (ws_end += 1) {}

            const trimmed_prefix = std.mem.trimEnd(u8, prefix, " ");
            const rest = d[ws_end..lr.end];

            if (std.mem.startsWith(u8, rest, prefix)) {
                return self.replaceRange(ws_end, ws_end + prefix.len, "");
            } else if (std.mem.startsWith(u8, rest, trimmed_prefix)) {
                return self.replaceRange(ws_end, ws_end + trimmed_prefix.len, "");
            } else {
                return self.replaceRange(ws_end, ws_end, prefix);
            }
        }

        pub fn duplicateCurrentLine(self: *Self) bool {
            self.saveUndoCheckpoint();
            const lr = self.lineRangeAtOffset(self.cursor);
            const line_len = lr.end - lr.start;
            if (!self.ensureCapacity(self.len + line_len + 1)) return false;

            var stack_tmp: [1024]u8 = undefined;
            if (line_len + 1 <= stack_tmp.len) {
                stack_tmp[0] = '\n';
                @memcpy(stack_tmp[1 .. 1 + line_len], self.constDataPtr()[lr.start .. lr.start + line_len]);
                return self.replaceRange(lr.end, lr.end, stack_tmp[0 .. 1 + line_len]);
            }
            const heap_tmp = std.heap.c_allocator.alloc(u8, line_len + 1) catch return false;
            defer std.heap.c_allocator.free(heap_tmp);
            heap_tmp[0] = '\n';
            @memcpy(heap_tmp[1 .. 1 + line_len], self.constDataPtr()[lr.start .. lr.start + line_len]);
            return self.replaceRange(lr.end, lr.end, heap_tmp);
        }

        pub fn clipboardSlice(self: *const Self) []const u8 {
            if (self.clipboard_len > self.clipboard_buf.len) {
                if (self.clipboard_heap_ptr) |hp| {
                    return hp[0..self.clipboard_len];
                }
                return &.{};
            }
            return self.clipboard_buf[0..self.clipboard_len];
        }

        pub fn setClipboardSlice(self: *Self, src: []const u8) void {
            if (src.len <= self.clipboard_buf.len) {
                if (src.len > 0) {
                    @memcpy(self.clipboard_buf[0..src.len], src);
                }
                self.clipboard_len = src.len;
                return;
            }
            if (src.len > self.clipboard_heap_cap or self.clipboard_heap_ptr == null) {
                var new_cap = @max(self.clipboard_heap_cap, 16384);
                while (new_cap < src.len) {
                    new_cap = new_cap + (new_cap / 2) + 8192;
                }
                if (std.heap.c_allocator.alloc(u8, new_cap)) |new_buf| {
                    if (self.clipboard_heap_ptr) |old_ptr| {
                        std.heap.c_allocator.free(old_ptr[0..self.clipboard_heap_cap]);
                    }
                    self.clipboard_heap_ptr = new_buf.ptr;
                    self.clipboard_heap_cap = new_buf.len;
                } else |_| {
                    const n = @min(src.len, self.clipboard_buf.len);
                    @memcpy(self.clipboard_buf[0..n], src[0..n]);
                    self.clipboard_len = n;
                    return;
                }
            }
            if (self.clipboard_heap_ptr) |hp| {
                @memcpy(hp[0..src.len], src);
                self.clipboard_len = src.len;
            }
        }

        pub fn copySelection(self: *Self) void {
            const src = if (self.hasSelection()) blk: {
                break :blk self.selectedSlice();
            } else blk: {
                const lr = self.lineRangeAtOffset(self.cursor);
                break :blk self.constDataPtr()[lr.start..lr.end];
            };
            self.setClipboardSlice(src);
        }

        pub fn cutSelection(self: *Self) bool {
            self.copySelection();
            self.saveUndoCheckpoint();
            if (self.hasSelection()) {
                return self.deleteSelection();
            }
            const lr = self.lineRangeAtOffset(self.cursor);
            const del_end = if (lr.end < self.len and self.constDataPtr()[lr.end] == '\n') lr.end + 1 else lr.end;
            return self.replaceRange(lr.start, del_end, "");
        }

        pub fn pasteClipboard(self: *Self) bool {
            const clip = self.clipboardSlice();
            if (clip.len == 0) return false;
            self.saveUndoCheckpoint();
            const r = self.selectionRange();
            // Normalize CRLF ('\r\n') or standalone '\r' if present in external clipboard content
            if (std.mem.indexOfScalar(u8, clip, '\r') != null) {
                const norm_buf = std.heap.c_allocator.alloc(u8, clip.len) catch {
                    return self.replaceRange(r.start, r.end, clip);
                };
                defer std.heap.c_allocator.free(norm_buf);
                var out_len: usize = 0;
                var i: usize = 0;
                while (i < clip.len) : (i += 1) {
                    if (clip[i] == '\r') {
                        if (i + 1 < clip.len and clip[i + 1] == '\n') continue;
                        norm_buf[out_len] = '\n';
                        out_len += 1;
                    } else {
                        norm_buf[out_len] = clip[i];
                        out_len += 1;
                    }
                }
                return self.replaceRange(r.start, r.end, norm_buf[0..out_len]);
            }
            return self.replaceRange(r.start, r.end, clip);
        }

        /// Jumps cursor to the first non-whitespace column of 1-based `target_line` and requests viewport scroll to top.
        pub fn jumpToLine(self: *Self, target_line_1_based: usize) void {
            const d = self.constDataPtr();
            const idx = target_line_1_based -| 1;
            const lr = self.lineRangeByIndex(idx);
            var pos = lr.start;
            while (pos < lr.end and (d[pos] == ' ' or d[pos] == '\t')) : (pos += 1) {}
            self.cursor = pos;
            self.selection_anchor = pos;
            self.preferred_col = null;
            self.scroll_to_cursor_pending = true;
            self.scroll_align_top = true;
            self.flash_line = @intCast(@max(@as(usize, 1), target_line_1_based));
            self.flash_frames = 45;
        }

        /// Jumps to 1-based `target_line`, triggers a temporary line highlight flash, and selects the first occurrence of `match_query` on that line if non-empty.
        pub fn jumpToLineAndHighlight(self: *Self, target_line_1_based: usize, match_query: []const u8) void {
            self.jumpToLine(target_line_1_based);
            if (match_query.len == 0) return;
            const d = self.constDataPtr();
            const idx = target_line_1_based -| 1;
            const lr = self.lineRangeByIndex(idx);
            const line_slice = d[lr.start..lr.end];
            if (root.indexOfIgnoreCasePos(line_slice, 0, match_query)) |m_off| {
                self.selection_anchor = lr.start + m_off;
                self.cursor = lr.start + m_off + match_query.len;
            }
        }

        /// Counts total case-insensitive occurrences of `query` in the buffer.
        pub fn countMatches(self: *const Self, query: []const u8) usize {
            if (query.len == 0 or query.len > self.len) return 0;
            const d = self.slice();
            var count: usize = 0;
            var i: usize = 0;
            while (root.indexOfIgnoreCasePos(d, i, query)) |m_idx| {
                count += 1;
                i = m_idx + query.len;
            }
            return count;
        }

        /// Finds the next (or previous) case-insensitive match of `query`, selects it, and scrolls it into view.
        pub fn findNext(self: *Self, query: []const u8, forward: bool) bool {
            if (query.len == 0 or query.len > self.len) return false;
            const d = self.constDataPtr();
            const s = self.slice();
            const limit = self.len - query.len;

            if (forward) {
                const start_pos = if (self.hasSelection()) @min(self.selectionRange().start + 1, self.len) else self.cursor;
                if (root.indexOfIgnoreCasePos(s, start_pos, query)) |m_idx| {
                    self.selection_anchor = m_idx;
                    self.cursor = m_idx + query.len;
                    self.scroll_to_cursor_pending = true;
                    return true;
                }
                // Wrap around to beginning
                if (root.indexOfIgnoreCasePos(s[0..@min(start_pos + query.len - 1, s.len)], 0, query)) |m_idx| {
                    self.selection_anchor = m_idx;
                    self.cursor = m_idx + query.len;
                    self.scroll_to_cursor_pending = true;
                    return true;
                }
            } else {
                const cur_start = self.selectionRange().start;
                if (cur_start > 0) {
                    var i = @min(cur_start - 1, limit);
                    while (true) {
                        if (std.ascii.eqlIgnoreCase(d[i .. i + query.len], query)) {
                            self.selection_anchor = i;
                            self.cursor = i + query.len;
                            self.scroll_to_cursor_pending = true;
                            return true;
                        }
                        if (i == 0) break;
                        i -= 1;
                    }
                }
                // Wrap around to end
                var i = limit;
                while (i >= cur_start) {
                    if (std.ascii.eqlIgnoreCase(d[i .. i + query.len], query)) {
                        self.selection_anchor = i;
                        self.cursor = i + query.len;
                        self.scroll_to_cursor_pending = true;
                        return true;
                    }
                    if (i == 0) break;
                    i -= 1;
                }
            }
            return false;
        }
    };
}

pub fn isWordChar(b: u8) bool {
    return std.ascii.isAlphanumeric(b) or b == '_' or b >= 0x80;
}

pub fn prevWordBoundary(s: []const u8, cur_pos: usize) usize {
    var pos = @min(cur_pos, s.len);
    while (pos > 0 and !isWordChar(s[pos - 1])) : (pos -= 1) {}
    while (pos > 0 and isWordChar(s[pos - 1])) : (pos -= 1) {}
    return snapToGraphemeBoundary(s, pos);
}

pub fn nextWordBoundary(s: []const u8, cur_pos: usize) usize {
    var pos = @min(cur_pos, s.len);
    while (pos < s.len and !isWordChar(s[pos])) : (pos += 1) {}
    while (pos < s.len and isWordChar(s[pos])) : (pos += 1) {}
    return snapToGraphemeBoundary(s, pos);
}

pub fn wordRangeAtOffset(s: []const u8, raw_offset: usize) struct { start: usize, end: usize } {
    if (s.len == 0) return .{ .start = 0, .end = 0 };
    const pos = @min(raw_offset, s.len);
    const probe = if (pos < s.len) pos else pos - 1;
    if (s[probe] == '\n') return .{ .start = pos, .end = pos };

    // Prefer a word character at `pos` or immediately preceding `pos`
    if (isWordChar(s[probe]) or (pos > 0 and isWordChar(s[pos - 1]))) {
        const seed = if (pos < s.len and isWordChar(s[pos])) pos else pos - 1;
        var start = seed;
        while (start > 0 and isWordChar(s[start - 1])) : (start -= 1) {}
        var end = seed + 1;
        while (end < s.len and isWordChar(s[end])) : (end += 1) {}
        return .{
            .start = snapToGraphemeBoundary(s, start),
            .end = snapToGraphemeBoundary(s, end),
        };
    }

    if (s[probe] == ' ' or s[probe] == '\t') {
        var start = probe;
        while (start > 0 and (s[start - 1] == ' ' or s[start - 1] == '\t')) : (start -= 1) {}
        var end = probe + 1;
        while (end < s.len and (s[end] == ' ' or s[end] == '\t')) : (end += 1) {}
        return .{ .start = start, .end = end };
    }

    var start = probe;
    while (start > 0 and !isWordChar(s[start - 1]) and s[start - 1] != ' ' and s[start - 1] != '\t' and s[start - 1] != '\n') : (start -= 1) {}
    var end = probe + 1;
    while (end < s.len and !isWordChar(s[end]) and s[end] != ' ' and s[end] != '\t' and s[end] != '\n') : (end += 1) {}
    return .{ .start = start, .end = end };
}

fn isGraphemeExtender(cp: u21) bool {
    return cp == 0xFE0E or // Variation Selector-15
        cp == 0xFE0F or // Variation Selector-16 (Emoji presentation)
        cp == 0x200D or // Zero-Width Joiner
        cp == 0x20E3 or // Combining Enclosing Keycap
        (cp >= 0x1F3FB and cp <= 0x1F3FF) or // Emoji skin-tone modifiers
        (cp >= 0x0300 and cp <= 0x036F) or // Combining diacritical marks
        (cp >= 0xE0100 and cp <= 0xE01EF);
}

fn decodeCodepointAt(s: []const u8, pos: usize) struct { cp: u21, len: usize } {
    if (pos >= s.len) return .{ .cp = 0, .len = 0 };
    const b0 = s[pos];
    if (b0 < 0x80) return .{ .cp = b0, .len = 1 };
    const seq_len = std.unicode.utf8ByteSequenceLength(b0) catch return .{ .cp = 0xFFFD, .len = 1 };
    if (pos + seq_len > s.len) return .{ .cp = 0xFFFD, .len = 1 };
    const cp = std.unicode.utf8Decode(s[pos .. pos + seq_len]) catch return .{ .cp = 0xFFFD, .len = 1 };
    return .{ .cp = cp, .len = seq_len };
}

pub fn snapToGraphemeBoundary(s: []const u8, raw_pos: usize) usize {
    if (raw_pos >= s.len) return s.len;
    var pos = raw_pos;
    // Step back from UTF-8 continuation bytes
    while (pos > 0 and (s[pos] & 0b1100_0000) == 0b1000_0000) : (pos -= 1) {}
    // Step back if we landed on an emoji modifier / variation selector / ZWJ continuation
    while (pos > 0) {
        const cur = decodeCodepointAt(s, pos);
        if (isGraphemeExtender(cur.cp)) {
            var prev = pos - 1;
            while (prev > 0 and (s[prev] & 0b1100_0000) == 0b1000_0000) : (prev -= 1) {}
            pos = prev;
            continue;
        }
        // Also check if preceded by a Zero-Width Joiner (`U+200D`, 3 bytes: 0xE2 0x80 0x8D)
        if (pos >= 3 and s[pos - 3] == 0xE2 and s[pos - 2] == 0x80 and s[pos - 1] == 0x8D) {
            var prev = pos - 3;
            if (prev > 0) {
                prev -= 1;
                while (prev > 0 and (s[prev] & 0b1100_0000) == 0b1000_0000) : (prev -= 1) {}
            }
            pos = prev;
            continue;
        }
        break;
    }
    return pos;
}

pub fn prevGraphemeBoundary(s: []const u8, cur_pos: usize) usize {
    if (cur_pos == 0) return 0;
    var pos = @min(cur_pos, s.len) - 1;
    while (pos > 0 and (s[pos] & 0b1100_0000) == 0b1000_0000) : (pos -= 1) {}
    return snapToGraphemeBoundary(s, pos);
}

pub fn nextGraphemeBoundary(s: []const u8, cur_pos: usize) usize {
    if (cur_pos >= s.len) return s.len;
    const first = decodeCodepointAt(s, cur_pos);
    var pos = cur_pos + @max(@as(usize, 1), first.len);
    while (pos < s.len) {
        const next_cp = decodeCodepointAt(s, pos);
        if (next_cp.len == 0) break;
        if (isGraphemeExtender(next_cp.cp)) {
            pos += next_cp.len;
            // If this extender was a ZWJ (`0x200D`), also consume the joined codepoint after it
            if (next_cp.cp == 0x200D and pos < s.len) {
                const joined = decodeCodepointAt(s, pos);
                pos += @max(@as(usize, 1), joined.len);
            }
            continue;
        }
        break;
    }
    return @min(pos, s.len);
}

fn isAllSpaces(s: []const u8) bool {
    for (s) |b| {
        if (b != ' ') return false;
    }
    return true;
}

fn isSymmetricQuote(ch: u8) bool {
    return ch == '"' or ch == '\'' or ch == '`';
}

fn countUnescapedQuote(slice: []const u8, quote: u8) usize {
    var count: usize = 0;
    var i: usize = 0;
    while (i < slice.len) : (i += 1) {
        if (slice[i] == '\\' and quote != '`') {
            i += 1;
            continue;
        }
        if (slice[i] == quote) count += 1;
    }
    return count;
}

fn closingPairFor(ch: u8) ?u8 {
    return switch (ch) {
        '(' => ')',
        '[' => ']',
        '{' => '}',
        '"' => '"',
        '\'' => '\'',
        '`' => '`',
        else => null,
    };
}

// ============================================================================
// Interactive Code Editor Widget (`render`)
// ============================================================================

pub fn render(
    uic: *Context,
    widget_id_str: []const u8,
    width: f32,
    height: f32,
    editor: anytype,
    options: CodeEditorOptions,
) CodeEditorResult {
    const wid = root.id(widget_id_str);
    const font = options.font orelse uic.font_mono;
    const outer_rect = uic.nextRect(width, height);

    const status_h: f32 = if (options.show_status_bar) 24.0 else 0.0;
    const body_h = @max(40.0, (outer_rect.bottom - outer_rect.top) - status_h);
    const minimap_w: f32 = if (options.show_minimap and (outer_rect.right - outer_rect.left) > 360.0) 82.0 else 0.0;
    const scroll_w = @max(80.0, (outer_rect.right - outer_rect.left) - minimap_w);

    const has_bp_gutter = options.show_line_numbers and options.show_breakpoint_gutter;
    const bp_zone_w: f32 = if (has_bp_gutter) BreakpointGutterWidth else 0.0;
    const base_gutter_w: f32 = if (editor.lineCount() >= 10000) 58.0 else 50.0;
    const gutter_w: f32 = if (options.show_line_numbers)
        (if (has_bp_gutter) (base_gutter_w + 10.0) else base_gutter_w)
    else
        12.0;
    const code_pad_left: f32 = gutter_w + 8.0;
    const pad_top: f32 = 8.0;
    const avail_code_w: f32 = @max(60.0, scroll_w - code_pad_left - 16.0);
    const char_advance: f32 = @max(6.0, uic.measureTextCached(font, "M"));
    const max_chars_per_line: usize = @max(10, @as(usize, @intFromFloat(@floor(avail_code_w / char_advance))));

    var res = CodeEditorResult{
        .focused = (uic.focused_id == wid),
        .selected_completion = if (options.completions.len > 0) @min(options.selected_completion, options.completions.len - 1) else 0,
    };

    const scroll_id_str = uic.fmt("{s}_scroll", .{widget_id_str});
    const inferred_pane_idx: usize = if (options.pane_index) |p_idx|
        p_idx
    else if (widget_id_str.len >= 2 and widget_id_str[widget_id_str.len - 2] == '_' and std.ascii.isDigit(widget_id_str[widget_id_str.len - 1]))
        @as(usize, widget_id_str[widget_id_str.len - 1] - '0')
    else
        0;
    const scroll_state: *ScrollState = options.scroll_state orelse editor.scrollStateForPane(inferred_pane_idx);

    // ------------------------------------------------------------------------
    // Pass 1 (`.input`): Focus, Keyboard Shortcuts, Text Insertion & Mouse Selection
    // ------------------------------------------------------------------------
    if (uic.pass == .input) {
        const v_bar_reserve: f32 = if (scroll_state.content_height > body_h + 0.5) 15.0 else 0.0;
        const h_bar_reserve: f32 = if (scroll_state.content_width > (scroll_w - v_bar_reserve) + 0.5) 15.0 else 0.0;
        const viewport_rect = Rect.xywh(
            outer_rect.left,
            outer_rect.top,
            @max(1.0, scroll_w - v_bar_reserve),
            @max(1.0, body_h - h_bar_reserve),
        );
        const minimap_rect = Rect.xywh(outer_rect.left + scroll_w, outer_rect.top, minimap_w, body_h);

        if (uic.mouse_pressed) {
            if (uic.isHovered(outer_rect)) {
                if (uic.focused_id != wid) {
                    uic.focused_id = wid;
                    res.focused = true;
                    uic.invalidateWindow();
                }
            } else if (uic.focused_id == wid) {
                editor.dragging_text = false;
            }
        }

        // Mouse click & drag inside text area (check floating autocomplete popup first)
        var clicked_completion_popup = false;
        if (uic.mouse_pressed and uic.focused_id == wid and options.completions.len > 0 and !options.read_only) {
            const cur_lc_pop = editor.offsetToLineCol(editor.cursor);
            const lr_pop = editor.lineRangeByIndex(cur_lc_pop.line);
            const col_clamped_pop = @min(cur_lc_pop.col, lr_pop.end - lr_pop.start);
            const caret_rel_x = uic.measureTextCached(font, editor.slice()[lr_pop.start .. lr_pop.start + col_clamped_pop]) - scroll_state.scroll_x;
            const caret_rel_y = (@as(f32, @floatFromInt(cur_lc_pop.line)) * options.line_height) - scroll_state.scroll_y;
            const pop_geom = computeCompletionPopupRect(outer_rect, body_h, code_pad_left, pad_top, caret_rel_x, caret_rel_y, options.line_height, options.completions.len);
            if (uic.isHovered(pop_geom.rect)) {
                clicked_completion_popup = true;
                const rel_item_y = uic.mouse_y - (pop_geom.rect.top + 4.0);
                if (rel_item_y >= 0.0) {
                    const idx: usize = @intFromFloat(@floor(rel_item_y / pop_geom.row_h));
                    if (idx < pop_geom.visible_count) {
                        const cand = options.completions[idx];
                        const ins = if (cand.insert_text.len > 0) cand.insert_text else cand.label;
                        const rep_start = editor.cursor -| @as(usize, cand.replace_prefix_len);
                        editor.saveUndoCheckpoint();
                        if (editor.replaceRange(rep_start, editor.cursor, ins)) {
                            res.selected_completion = idx;
                            res.completion_accepted = true;
                            res.text_changed = true;
                            res.cursor_changed = true;
                            uic.markDirty(outer_rect);
                        }
                    }
                }
            }
        }

        const in_bp_gutter = has_bp_gutter and uic.isHovered(viewport_rect) and (uic.mouse_x < outer_rect.left + bp_zone_w);
        const new_hovered_bp: u32 = if (in_bp_gutter) blk: {
            const rel_y = (uic.mouse_y - outer_rect.top - pad_top) + scroll_state.scroll_y;
            break :blk @intCast(findLineAtY(editor, rel_y, options.line_height, options.word_wrap, max_chars_per_line) + 1);
        } else 0;
        if (new_hovered_bp != editor.hovered_bp_line) {
            editor.hovered_bp_line = new_hovered_bp;
            uic.markDirty(Rect.xywh(outer_rect.left, outer_rect.top, gutter_w + 2.0, body_h));
        }

        if (in_bp_gutter) {
            uic.setCursor(.pointing_hand);
        } else if (uic.isHovered(viewport_rect) and uic.mouse_x >= outer_rect.left + gutter_w) {
            uic.setCursor(.ibeam);
        }
        if (!clicked_completion_popup and uic.right_mouse_pressed and uic.isHovered(viewport_rect)) {
            uic.focused_id = wid;
            res.right_clicked = true;
            if (uic.mouse_x >= outer_rect.left + gutter_w) {
                const rel_y = (uic.mouse_y - outer_rect.top - pad_top) + scroll_state.scroll_y;
                const clicked_line = findLineAtY(editor, rel_y, options.line_height, options.word_wrap, max_chars_per_line);
                const lr = editor.lineRangeByIndex(clicked_line);
                const rel_x = @max(0.0, (uic.mouse_x - (outer_rect.left + code_pad_left)) + scroll_state.scroll_x);
                const line_slice = editor.slice()[lr.start..lr.end];
                const line_top = computeLineY(editor, clicked_line, options.line_height, options.word_wrap, max_chars_per_line);
                const rel_y_in_line = @max(0.0, rel_y - line_top);
                const col_byte = resolveLineColByte(uic, font, line_slice, rel_x, rel_y_in_line, options.line_height, options.word_wrap, max_chars_per_line);
                const new_pos = lr.start + col_byte;
                const sel = editor.selectionRange();
                if (!editor.hasSelection() or new_pos < sel.start or new_pos > sel.end) {
                    editor.cursor = new_pos;
                    editor.selection_anchor = new_pos;
                    editor.preferred_col = null;
                    res.cursor_changed = true;
                }
            }
            uic.markDirty(outer_rect);
        }
        if (!clicked_completion_popup and uic.mouse_pressed and uic.isHovered(viewport_rect)) {
            const rel_y = (uic.mouse_y - outer_rect.top - pad_top) + scroll_state.scroll_y;
            const clicked_line = findLineAtY(editor, rel_y, options.line_height, options.word_wrap, max_chars_per_line);
            const lr = editor.lineRangeByIndex(clicked_line);
            const line_end_with_nl = if (lr.end < editor.len and editor.slice()[lr.end] == '\n') lr.end + 1 else lr.end;

            if (has_bp_gutter and uic.mouse_x < outer_rect.left + bp_zone_w) {
                // Clicking in the breakpoint gutter (to the left of the line numbers) toggles a breakpoint on this line
                const bp_line_1based: u32 = @intCast(clicked_line + 1);
                _ = editor.toggleBreakpoint(bp_line_1based);
                res.toggled_breakpoint_line = bp_line_1based;
                editor.dragging_text = false;
                uic.markDirty(outer_rect);
            } else if (options.show_line_numbers and uic.mouse_x < outer_rect.left + gutter_w) {
                // Clicking on the line number digits selects the entire line
                uic.active_id = wid;
                editor.dragging_text = true;
                editor.selection_anchor = lr.start;
                editor.cursor = line_end_with_nl;
                editor.drag_click_mode = 2;
                editor.drag_origin_start = lr.start;
                editor.drag_origin_end = line_end_with_nl;
                editor.preferred_col = null;
                res.cursor_changed = true;
                uic.markDirty(outer_rect);
            } else {
                uic.active_id = wid;
                editor.dragging_text = true;
                const rel_x = @max(0.0, (uic.mouse_x - (outer_rect.left + code_pad_left)) + scroll_state.scroll_x);
                const line_slice = editor.slice()[lr.start..lr.end];
                const line_top = computeLineY(editor, clicked_line, options.line_height, options.word_wrap, max_chars_per_line);
                const rel_y_in_line = @max(0.0, rel_y - line_top);
                const col_byte = resolveLineColByte(uic, font, line_slice, rel_x, rel_y_in_line, options.line_height, options.word_wrap, max_chars_per_line);
                const new_pos = lr.start + col_byte;

                if (uic.mouse_click_count >= 3) {
                    // Triple-click selects the entire line
                    editor.selection_anchor = lr.start;
                    editor.cursor = line_end_with_nl;
                    editor.drag_click_mode = 2;
                    editor.drag_origin_start = lr.start;
                    editor.drag_origin_end = line_end_with_nl;
                } else if (uic.mouse_click_count == 2) {
                    // Double-click selects the word (or whitespace/punctuation token) under the cursor
                    const wr = wordRangeAtOffset(line_slice, col_byte);
                    editor.selection_anchor = lr.start + wr.start;
                    editor.cursor = lr.start + wr.end;
                    editor.drag_click_mode = 1;
                    editor.drag_origin_start = editor.selection_anchor;
                    editor.drag_origin_end = editor.cursor;
                } else {
                    editor.drag_click_mode = 0;
                    editor.cursor = new_pos;
                    if (!uic.mouse_shift) {
                        editor.selection_anchor = new_pos;
                    }
                }
                editor.preferred_col = null;
                res.cursor_changed = true;
                uic.markDirty(outer_rect);
            }
        } else if (uic.active_id == wid and editor.dragging_text and uic.mouse_down) {
            const rel_y = (uic.mouse_y - outer_rect.top - pad_top) + scroll_state.scroll_y;
            const dragged_line = findLineAtY(editor, rel_y, options.line_height, options.word_wrap, max_chars_per_line);
            const lr = editor.lineRangeByIndex(dragged_line);
            const line_slice = editor.slice()[lr.start..lr.end];
            const rel_x = @max(0.0, (uic.mouse_x - (outer_rect.left + code_pad_left)) + scroll_state.scroll_x);
            const line_top = computeLineY(editor, dragged_line, options.line_height, options.word_wrap, max_chars_per_line);
            const rel_y_in_line = @max(0.0, rel_y - line_top);
            const col_byte = resolveLineColByte(uic, font, line_slice, rel_x, rel_y_in_line, options.line_height, options.word_wrap, max_chars_per_line);
            const new_pos = lr.start + col_byte;
            const prev_cursor = editor.cursor;
            const prev_anchor = editor.selection_anchor;

            if (editor.drag_click_mode == 2) {
                const line_end_with_nl = if (lr.end < editor.len and editor.slice()[lr.end] == '\n') lr.end + 1 else lr.end;
                if (lr.start < editor.drag_origin_start) {
                    editor.selection_anchor = editor.drag_origin_end;
                    editor.cursor = lr.start;
                } else {
                    editor.selection_anchor = editor.drag_origin_start;
                    editor.cursor = line_end_with_nl;
                }
            } else if (editor.drag_click_mode == 1) {
                const wr = wordRangeAtOffset(line_slice, col_byte);
                const w_start = lr.start + wr.start;
                const w_end = lr.start + wr.end;
                if (w_start < editor.drag_origin_start) {
                    editor.selection_anchor = editor.drag_origin_end;
                    editor.cursor = w_start;
                } else {
                    editor.selection_anchor = editor.drag_origin_start;
                    editor.cursor = w_end;
                }
            } else {
                editor.cursor = new_pos;
            }

            if (editor.cursor != prev_cursor or editor.selection_anchor != prev_anchor) {
                editor.preferred_col = null;
                res.cursor_changed = true;
                uic.markDirty(outer_rect);
            }
        } else if (!uic.mouse_down) {
            if (uic.active_id == wid) {
                uic.active_id = 0;
                editor.dragging_text = false;
            } else if (uic.focused_id == wid) {
                editor.dragging_text = false;
            }
        }

        // Interactive minimap click/drag scrolling
        if (minimap_w > 0 and uic.mouse_down and uic.isHovered(minimap_rect)) {
            const total_lines_f: f32 = @floatFromInt(@max(1, editor.lineCount()));
            const click_ratio = std.math.clamp((uic.mouse_y - minimap_rect.top - 8.0) / @max(1.0, body_h - 16.0), 0.0, 1.0);
            const max_scroll = @max(0.0, total_lines_f * options.line_height + 24.0 - body_h);
            const target_scroll = click_ratio * max_scroll;
            if (target_scroll != scroll_state.scroll_y) {
                scroll_state.scroll_y = target_scroll;
                uic.markDirty(outer_rect);
            }
        }

        // Keyboard events & text input when focused
        if (uic.focused_id == wid) {
            for (uic.key_events) |kev| {
                const prev_cursor = editor.cursor;
                const prev_anchor = editor.selection_anchor;
                var edited = false;

                const primary_mod = kev.cmd or kev.ctrl;
                const has_comp_popup = (options.completions.len > 0 and !options.read_only and !editor.hasSelection());
                switch (kev.key) {
                    .left => editor.moveLeft(kev.shift, kev.alt, kev.cmd),
                    .right => editor.moveRight(kev.shift, kev.alt, kev.cmd),
                    .up => if (has_comp_popup and !kev.cmd and !kev.shift and !kev.alt) {
                        const cur_sel = res.selected_completion;
                        res.selected_completion = if (cur_sel == 0) options.completions.len - 1 else cur_sel - 1;
                        res.completion_selection_changed = true;
                        uic.markDirty(outer_rect);
                    } else if (kev.cmd) {
                        editor.finalizeMove(0, kev.shift, false);
                    } else {
                        editor.moveUp(kev.shift);
                    },
                    .down => if (has_comp_popup and !kev.cmd and !kev.shift and !kev.alt) {
                        res.selected_completion = (res.selected_completion + 1) % options.completions.len;
                        res.completion_selection_changed = true;
                        uic.markDirty(outer_rect);
                    } else if (kev.cmd) {
                        editor.finalizeMove(editor.len, kev.shift, false);
                    } else {
                        editor.moveDown(kev.shift);
                    },
                    .home => editor.moveLeft(kev.shift, false, true),
                    .end => editor.moveRight(kev.shift, false, true),
                    .page_up => editor.movePage(-12, kev.shift),
                    .page_down => editor.movePage(12, kev.shift),
                    .key_a => if (primary_mod) editor.selectAll(),
                    .key_c => if (primary_mod) {
                        editor.copySelection();
                        if (uic.platform_ctx) |pctx| {
                            const clip = editor.clipboardSlice();
                            if (clip.len > 0) {
                                _ = pctx.setClipboardText(clip);
                            }
                        }
                    },
                    .key_x => if (primary_mod and !options.read_only) {
                        edited = editor.cutSelection();
                        if (uic.platform_ctx) |pctx| {
                            const clip = editor.clipboardSlice();
                            if (clip.len > 0) {
                                _ = pctx.setClipboardText(clip);
                            }
                        }
                    },
                    .key_v => if (primary_mod and !options.read_only) {
                        if (uic.platform_ctx) |pctx| {
                            if (pctx.getClipboardTextAlloc(uic.arena)) |sys_clip| {
                                editor.setClipboardSlice(sys_clip);
                            }
                        }
                        edited = editor.pasteClipboard();
                    },
                    .key_z => if (primary_mod and !options.read_only) {
                        edited = if (kev.shift) editor.redo() else editor.undo();
                    },
                    .key_d => if (primary_mod and !options.read_only) {
                        edited = editor.duplicateCurrentLine();
                    },
                    .key_s => if (primary_mod) {
                        res.save_requested = true;
                        uic.markDirty(outer_rect);
                    },
                    .key_f => if (primary_mod) {
                        res.find_requested = true;
                        uic.markDirty(outer_rect);
                    },
                    .key_g => if (primary_mod) {
                        if (options.search_query.len > 0) {
                            _ = editor.findNext(options.search_query, !kev.shift);
                        }
                    },
                    .key_slash => if (primary_mod and !options.read_only) {
                        edited = editor.toggleLineComment(options.language.commentPrefix());
                    },
                    .backspace => if (!options.read_only) {
                        edited = editor.deleteBackward(kev.alt, kev.cmd, options.tab_width);
                    },
                    .delete_forward => if (!options.read_only) {
                        edited = editor.deleteForward(kev.alt);
                    },
                    .enter => if (!options.read_only) {
                        if (has_comp_popup) {
                            const cand = options.completions[@min(res.selected_completion, options.completions.len - 1)];
                            const ins = if (cand.insert_text.len > 0) cand.insert_text else cand.label;
                            const rep_start = editor.cursor -| @as(usize, cand.replace_prefix_len);
                            editor.saveUndoCheckpoint();
                            edited = editor.replaceRange(rep_start, editor.cursor, ins);
                            if (edited) {
                                res.completion_accepted = true;
                            }
                        } else {
                            edited = editor.insertNewlineAutoIndent(options.tab_width);
                        }
                    },
                    .tab => if (!options.read_only) {
                        if (!kev.shift and has_comp_popup) {
                            const cand = options.completions[@min(res.selected_completion, options.completions.len - 1)];
                            const ins = if (cand.insert_text.len > 0) cand.insert_text else cand.label;
                            const rep_start = editor.cursor -| @as(usize, cand.replace_prefix_len);
                            editor.saveUndoCheckpoint();
                            edited = editor.replaceRange(rep_start, editor.cursor, ins);
                            if (edited) {
                                res.completion_accepted = true;
                            }
                        } else if (!kev.shift and options.ghost_text.len > 0 and !editor.hasSelection()) {
                            edited = editor.acceptGhostText(options.ghost_text, options.ghost_delete_len);
                            if (edited) {
                                res.ghost_accepted = true;
                            }
                        } else {
                            edited = if (kev.shift)
                                editor.outdentSelection(options.tab_width)
                            else
                                editor.indentOrInsertTab(options.tab_width);
                        }
                    },
                    .escape => {
                        if (options.completions.len > 0) {
                            res.completion_dismissed = true;
                            uic.markDirty(outer_rect);
                        }
                        if (options.ghost_text.len > 0) {
                            res.ghost_dismissed = true;
                            uic.markDirty(outer_rect);
                        }
                        if (editor.hasSelection()) {
                            editor.selection_anchor = editor.cursor;
                        }
                    },
                    .f9 => if (options.show_breakpoint_gutter) {
                        const bp_line_1based: u32 = @intCast(editor.offsetToLineCol(editor.cursor).line + 1);
                        _ = editor.toggleBreakpoint(bp_line_1based);
                        res.toggled_breakpoint_line = bp_line_1based;
                        uic.markDirty(outer_rect);
                    },
                    else => {},
                }

                if (edited) {
                    res.text_changed = true;
                    res.cursor_changed = true;
                    uic.markDirty(outer_rect);
                } else if (editor.cursor != prev_cursor or editor.selection_anchor != prev_anchor) {
                    res.cursor_changed = true;
                    uic.markDirty(outer_rect);
                }
            }

            if (!options.read_only and uic.text_input.len > 0) {
                if (editor.insertText(uic.text_input, options.auto_close_pairs)) {
                    res.text_changed = true;
                    res.cursor_changed = true;
                    uic.markDirty(outer_rect);
                } else {
                    // Could have stepped over closing delimiter
                    res.cursor_changed = true;
                    uic.markDirty(outer_rect);
                }
            }
        }

        // Pre-populate exact scroll content height so `scroll_to_cursor_pending` (e.g. `jumpToLine`)
        // is never clamped to 0 on the first frame before `endScrollBox` runs.
        const exact_content_h = pad_top + computeLineY(editor, @max(1, editor.lineCount()), options.line_height, options.word_wrap, max_chars_per_line) + 16.0;
        if (scroll_state.content_height < exact_content_h) {
            scroll_state.content_height = exact_content_h;
        }

        if (editor.flash_frames > 0) {
            uic.markDirty(outer_rect);
            if (uic.platform_ctx) |pctx| {
                pctx.needs_continuous_redraw = true;
            }
        }

        // Auto-scroll viewport vertically & horizontally to keep cursor visible
        if (editor.scroll_to_cursor_pending and (uic.focused_id == wid or options.is_active_pane)) {
            const align_top = editor.scroll_align_top;
            editor.scroll_to_cursor_pending = false;
            editor.scroll_align_top = false;
            const lc = editor.offsetToLineCol(editor.cursor);
            const cursor_top = computeLineY(editor, lc.line, options.line_height, options.word_wrap, max_chars_per_line);
            const cursor_bottom = computeLineY(editor, lc.line + 1, options.line_height, options.word_wrap, max_chars_per_line);
            const visible_h = @max(options.line_height, body_h - pad_top * 2.0 - 8.0);

            if (align_top) {
                const max_scroll_y = @max(0.0, scroll_state.content_height - body_h);
                const target_y = std.math.clamp(cursor_top, 0.0, max_scroll_y);
                if (scroll_state.scroll_y != target_y) {
                    scroll_state.scroll_y = target_y;
                    uic.markDirty(outer_rect);
                }
            } else if (cursor_top < scroll_state.scroll_y) {
                scroll_state.scroll_y = cursor_top;
                uic.markDirty(outer_rect);
            } else if (cursor_bottom > scroll_state.scroll_y + visible_h) {
                scroll_state.scroll_y = cursor_bottom - visible_h;
                uic.markDirty(outer_rect);
            }

            const lr = editor.lineRangeByIndex(lc.line);
            const col_clamped = @min(lc.col, lr.end - lr.start);
            const cursor_x = uic.measureTextCached(font, editor.slice()[lr.start .. lr.start + col_clamped]);
            const visible_code_w = @max(40.0, scroll_w - code_pad_left - 24.0);

            if (cursor_x < scroll_state.scroll_x) {
                scroll_state.scroll_x = @max(0.0, cursor_x - 16.0);
                uic.markDirty(outer_rect);
            } else if (cursor_x + 12.0 > scroll_state.scroll_x + visible_code_w) {
                scroll_state.scroll_x = (cursor_x + 12.0) - visible_code_w;
                uic.markDirty(outer_rect);
            }
        }
    }

    // Populate result metrics
    const cur_lc = editor.cursorLineCol();
    res.focused = (uic.focused_id == wid);
    res.cursor_line = cur_lc.line;
    res.cursor_col = cur_lc.col;
    res.line_count = editor.lineCount();
    const sel_range = editor.selectionRange();
    res.selection_len = sel_range.end - sel_range.start;

    // ------------------------------------------------------------------------
    // Layout & Paint Hierarchy (ScrollBox + Minimap + Status Bar)
    // ------------------------------------------------------------------------
    uic.pushContainer(outer_rect, .{
        .direction = .column,
        .padding = Padding.all(0),
        .gap = 0,
        .bg_color = Color.rgb(13, 17, 24),
    });
    defer uic.endBox();

    // Top row: Scrollable Editor Canvas + Optional Minimap
    _ = uic.beginBox(0, body_h, .{
        .direction = .row,
        .padding = Padding.all(0),
        .gap = 0,
    });
    {
        _ = uic.beginScrollBoxWithState(scroll_id_str, scroll_state, scroll_w, body_h, .{
            .direction = .column,
            .padding = Padding{ .left = 0, .top = pad_top, .right = 0, .bottom = 16.0 },
            .gap = 0,
        });
        {
            const text = editor.slice();
            const total_lines = @max(1, res.line_count);
            const avail_row_w = uic.availableWidth();
            const max_est_w = if (options.word_wrap)
                avail_row_w
            else
                @max(
                    avail_row_w,
                    code_pad_left + @as(f32, @floatFromInt(editor.max_line_cols)) * char_advance + 32.0,
                );
            const lh = @max(1.0, options.line_height);

            // Viewport virtualization: only emit layout rows for the visible window of lines!
            const first_vis_line: usize = findLineAtY(editor, scroll_state.scroll_y, lh, options.word_wrap, max_chars_per_line);
            const vis_count: usize = @as(usize, @intFromFloat(@ceil(body_h / lh))) + 3;
            const start_line = @min(first_vis_line -| 1, total_lines - 1);
            const end_line = @min(total_lines, start_line + vis_count);

            const top_skip_h = computeLineY(editor, start_line, lh, options.word_wrap, max_chars_per_line);
            if (top_skip_h > 0) {
                _ = uic.nextRect(max_est_w, top_skip_h);
            }

            var line_idx: usize = start_line;
            while (line_idx < end_line) : (line_idx += 1) {
                const lr = editor.lineRangeByIndex(line_idx);
                const line_slice = text[lr.start..lr.end];
                var seg_buf: [MaxWrapSegments]WrapSegment = undefined;
                const segments = if (options.word_wrap)
                    computeWrapSegments(line_slice, max_chars_per_line, &seg_buf)
                else
                    (&[_]WrapSegment{.{ .start = 0, .end = line_slice.len }})[0..1];

                const row_h = @as(f32, @floatFromInt(segments.len)) * options.line_height;
                const est_line_w = if (options.word_wrap)
                    avail_row_w
                else if (line_slice.len > 0)
                    code_pad_left + @as(f32, @floatFromInt(line_slice.len)) * char_advance + 32.0
                else
                    avail_row_w;
                const row_w = @max(max_est_w, est_line_w);

                const row_r = uic.nextRect(row_w, row_h);
                const paint_row_r = Rect.ltrb(
                    row_r.left,
                    row_r.top,
                    @max(row_r.right, row_r.left + scroll_state.scroll_x + avail_row_w),
                    row_r.bottom,
                );
                if (uic.shouldPaint(paint_row_r)) {
                    drawEditorLineRow(
                        uic,
                        font,
                        paint_row_r,
                        scroll_state.scroll_x,
                        line_idx,
                        lr.start,
                        lr.end,
                        line_slice,
                        segments,
                        editor,
                        res.focused,
                        gutter_w,
                        code_pad_left,
                        options,
                    );
                }
            }

            if (end_line < total_lines) {
                const bot_skip_h = computeLineY(editor, total_lines, lh, options.word_wrap, max_chars_per_line) -
                    computeLineY(editor, end_line, lh, options.word_wrap, max_chars_per_line);
                if (bot_skip_h > 0) {
                    _ = uic.nextRect(max_est_w, bot_skip_h);
                }
            }

            if (uic.pass == .paint and editor.flash_frames > 0) {
                editor.flash_frames -= 1;
                if (editor.flash_frames == 0) {
                    editor.flash_line = 0;
                }
            }
        }
        uic.endScrollBox();
        if (uic.platform_ctx == null) {
            uic.fallback_scroll_state = scroll_state.*;
        }

        if (minimap_w > 0) {
            const map_r = uic.beginBox(minimap_w, body_h, .{
                .direction = .column,
                .padding = Padding.all(6),
                .bg_color = Color.rgb(11, 15, 22),
            });
            if (uic.shouldPaint(map_r)) {
                drawEditorMinimap(uic, map_r, editor, scroll_state.scroll_y, body_h, options);
            }
            uic.endBox();
        }
    }
    uic.endBox();

    // Bottom Status Footer Bar
    if (options.show_status_bar) {
        const status_r = uic.beginBox(0, status_h, .{
            .direction = .row,
            .padding = Padding{ .left = 10, .top = 3, .right = 10, .bottom = 3 },
            .gap = 12,
            .bg_color = Color.rgb(18, 24, 36),
        });
        if (uic.shouldPaint(status_r)) {
            drawEditorStatusBar(uic, font, status_r, editor, res, options);
        }
        uic.endBox();
    }

    // Floating LSP / Intellisense Autocomplete Popup (drawn on top of editor lines)
    if (res.focused and options.completions.len > 0 and !options.read_only and !editor.hasSelection()) {
        const cur_lc_pop = editor.offsetToLineCol(editor.cursor);
        const lr_pop = editor.lineRangeByIndex(cur_lc_pop.line);
        const col_clamped_pop = @min(cur_lc_pop.col, lr_pop.end - lr_pop.start);
        const caret_rel_x = uic.measureTextCached(font, editor.slice()[lr_pop.start .. lr_pop.start + col_clamped_pop]) - scroll_state.scroll_x;
        const caret_rel_y = (@as(f32, @floatFromInt(cur_lc_pop.line)) * options.line_height) - scroll_state.scroll_y;
        const pop_geom = computeCompletionPopupRect(
            outer_rect,
            body_h,
            code_pad_left,
            pad_top,
            caret_rel_x,
            caret_rel_y,
            options.line_height,
            options.completions.len,
        );
        if (uic.shouldPaint(pop_geom.rect)) {
            drawCompletionPopup(uic, font, pop_geom, options.completions[0..pop_geom.visible_count], res.selected_completion);
        }
    }

    return res;
}

const CompletionPopupGeometry = struct {
    rect: c.sk_rect_t,
    row_h: f32,
    visible_count: usize,
};

fn computeCompletionPopupRect(
    outer_rect: c.sk_rect_t,
    body_h: f32,
    code_pad_left: f32,
    pad_top: f32,
    caret_rel_x: f32,
    caret_rel_y: f32,
    line_height: f32,
    total_items: usize,
) CompletionPopupGeometry {
    const visible_count = @min(total_items, 6);
    const row_h: f32 = 23.0;
    const footer_h: f32 = 18.0;
    const pop_w: f32 = @min(360.0, @max(220.0, (outer_rect.right - outer_rect.left) - 24.0));
    const pop_h: f32 = @as(f32, @floatFromInt(visible_count)) * row_h + footer_h + 8.0;

    const raw_x = outer_rect.left + code_pad_left + @max(0.0, caret_rel_x);
    const clamped_x = std.math.clamp(raw_x, outer_rect.left + 8.0, @max(outer_rect.left + 8.0, outer_rect.right - pop_w - 8.0));

    const below_y = outer_rect.top + pad_top + caret_rel_y + line_height + 3.0;
    const max_bottom = outer_rect.top + body_h - 4.0;
    const pop_y = if (below_y + pop_h <= max_bottom)
        below_y
    else
        @max(outer_rect.top + 4.0, (outer_rect.top + pad_top + caret_rel_y) - pop_h - 3.0);

    return .{
        .rect = Rect.xywh(clamped_x, pop_y, pop_w, pop_h),
        .row_h = row_h,
        .visible_count = visible_count,
    };
}

fn drawCompletionPopup(
    uic: *Context,
    font: Font,
    geom: CompletionPopupGeometry,
    items: []const CompletionPopupItem,
    selected_idx: usize,
) void {
    const paint = uic.paint;
    const canvas = uic.canvas;
    const r = geom.rect;

    const save_cnt = canvas.save();
    defer canvas.restoreToCount(save_cnt);
    canvas.clipRect(r, .intersect, true);

    // Shadow & elevated dark surface
    paint.setStyle(.fill);
    paint.setColor(Color.rgb(18, 24, 36));
    canvas.drawRoundRect(r, 6.0, 6.0, paint);

    const sel_clamped = if (items.len > 0) @min(selected_idx, items.len - 1) else 0;
    var row_y = r.top + 4.0;

    for (items, 0..) |item, idx| {
        const item_r = Rect.xywh(r.left + 4.0, row_y, (r.right - r.left) - 8.0, geom.row_h);
        const is_sel = (idx == sel_clamped);
        if (is_sel) {
            paint.setStyle(.fill);
            paint.setColor(Color.argb(95, 56, 139, 253));
            canvas.drawRoundRect(item_r, 4.0, 4.0, paint);
        }

        // Kind badge (`fn`, `ty`, `kw`, `sn`, `fd`)
        const kind_badge = switch (item.kind) {
            0 => "kw",
            1 => "fn",
            2 => "ty",
            3 => "sn",
            else => "fd",
        };
        const kind_col = switch (item.kind) {
            0 => Color.rgb(255, 123, 114),
            1 => Color.rgb(210, 168, 255),
            2 => Color.rgb(121, 192, 255),
            3 => Color.rgb(52, 211, 153),
            else => Color.rgb(251, 191, 36),
        };
        const badge_r = Rect.xywh(item_r.left + 4.0, row_y + 3.0, 22.0, geom.row_h - 6.0);
        paint.setStyle(.fill);
        paint.setColor(Color.argb(40, 148, 163, 184));
        canvas.drawRoundRect(badge_r, 3.0, 3.0, paint);

        const text_y = row_y + geom.row_h * 0.72;
        paint.setColor(kind_col);
        uic.drawTextCached(uic.font_mono, kind_badge, badge_r.left + 3.5, text_y);

        // Label
        const label_x = badge_r.right + 7.0;
        paint.setColor(if (is_sel) Color.rgb(255, 255, 255) else Color.rgb(226, 232, 240));
        uic.drawTextCached(font, item.label, label_x, text_y);

        // Right-aligned signature/detail
        if (item.detail.len > 0) {
            const label_w = uic.measureTextCached(font, item.label);
            const det_w = uic.measureTextCached(uic.font_mono, item.detail);
            const det_x = item_r.right - det_w - 6.0;
            if (det_x > label_x + label_w + 12.0) {
                paint.setColor(Color.rgb(125, 138, 158));
                uic.drawTextCached(uic.font_mono, item.detail, det_x, text_y);
            }
        }

        row_y += geom.row_h;
    }

    // Bottom hint bar (`↑↓ Navigate · Tab/Enter Accept · Esc Dismiss`)
    const footer_y = r.bottom - 18.0;
    paint.setStyle(.fill);
    paint.setColor(Color.rgb(14, 19, 29));
    canvas.drawRect(Rect.xywh(r.left, footer_y, r.right - r.left, 18.0), paint);
    paint.setColor(Color.rgb(100, 116, 139));
    uic.drawTextCached(uic.font_mono, "↑↓ select · Tab/↵ insert · Esc close", r.left + 8.0, footer_y + 13.0);

    // Crisp outer border
    paint.setStyle(.stroke);
    paint.setStrokeWidth(1.1);
    paint.setColor(Color.rgb(56, 139, 253));
    canvas.drawRoundRect(r, 6.0, 6.0, paint);
}

// ============================================================================
// Line & Token Rendering Helpers
// ============================================================================

pub const MaxWrapSegments: usize = 64;

pub const WrapSegment = struct {
    start: usize,
    end: usize,
};

pub fn computeWrapSegments(
    line: []const u8,
    max_chars: usize,
    buf: *[MaxWrapSegments]WrapSegment,
) []const WrapSegment {
    if (line.len == 0) {
        buf[0] = .{ .start = 0, .end = 0 };
        return buf[0..1];
    }
    const safe_max = @max(8, max_chars);
    var count: usize = 0;
    var start: usize = 0;
    while (start < line.len and count < MaxWrapSegments) {
        const rem = line.len - start;
        if (rem <= safe_max or count == MaxWrapSegments - 1) {
            buf[count] = .{ .start = start, .end = line.len };
            count += 1;
            break;
        }

        // Look for the last space/tab/hyphen break before `start + safe_max`
        var break_pos: ?usize = null;
        var p = start + safe_max - 1;
        while (p > start) : (p -= 1) {
            if (line[p] == ' ' or line[p] == '\t' or line[p] == '-') {
                break_pos = p + 1; // Break after space/hyphen so it stays on current sub-row
                break;
            }
        }

        const next_end = if (break_pos) |bp| bp else start + safe_max;
        buf[count] = .{ .start = start, .end = next_end };
        count += 1;
        start = next_end;
    }
    return buf[0..count];
}

fn computeLineY(editor: anytype, target_line: usize, line_height: f32, word_wrap: bool, max_chars: usize) f32 {
    if (!word_wrap or max_chars == 0) {
        return @as(f32, @floatFromInt(target_line)) * line_height;
    }
    var y: f32 = 0.0;
    const limit = @min(target_line, editor.lineCount());
    for (0..limit) |idx| {
        const lr = editor.lineRangeByIndex(idx);
        var seg_buf: [MaxWrapSegments]WrapSegment = undefined;
        const line_slice = editor.slice()[lr.start..lr.end];
        const segs = computeWrapSegments(line_slice, max_chars, &seg_buf);
        y += @as(f32, @floatFromInt(segs.len)) * line_height;
    }
    return y;
}

fn findLineAtY(editor: anytype, rel_y: f32, line_height: f32, word_wrap: bool, max_chars: usize) usize {
    if (rel_y <= 0) return 0;
    const total = editor.lineCount();
    if (total == 0) return 0;
    if (!word_wrap or max_chars == 0) {
        const raw_line: usize = @intFromFloat(@floor(rel_y / @max(1.0, line_height)));
        return @min(raw_line, total - 1);
    }
    var acc_y: f32 = 0.0;
    for (0..total) |idx| {
        const lr = editor.lineRangeByIndex(idx);
        var seg_buf: [MaxWrapSegments]WrapSegment = undefined;
        const line_slice = editor.slice()[lr.start..lr.end];
        const segs = computeWrapSegments(line_slice, max_chars, &seg_buf);
        const lh = @as(f32, @floatFromInt(segs.len)) * line_height;
        if (rel_y < acc_y + lh) return idx;
        acc_y += lh;
    }
    return total - 1;
}

fn resolveLineColByte(
    uic: *Context,
    font: Font,
    line_slice: []const u8,
    rel_x: f32,
    rel_y_in_line: f32,
    line_height: f32,
    word_wrap: bool,
    max_chars: usize,
) usize {
    if (!word_wrap or max_chars == 0) {
        return findColumnAtX(uic, font, line_slice, rel_x);
    }
    var seg_buf: [MaxWrapSegments]WrapSegment = undefined;
    const segments = computeWrapSegments(line_slice, max_chars, &seg_buf);
    if (segments.len <= 1) {
        return findColumnAtX(uic, font, line_slice, rel_x);
    }
    const sub_k = @min(segments.len - 1, @as(usize, @intFromFloat(@max(0.0, @floor(rel_y_in_line / line_height)))));
    const seg = segments[sub_k];
    const sub_slice = line_slice[seg.start..seg.end];
    return seg.start + findColumnAtX(uic, font, sub_slice, rel_x);
}

fn hasBreakpointOnLine(bp_lines: []const u32, line_1based: u32) bool {
    for (bp_lines) |ln| {
        if (ln == line_1based) return true;
    }
    return false;
}

fn drawEditorLineRow(
    uic: *Context,
    font: Font,
    row_r: c.sk_rect_t,
    scroll_x: f32,
    line_idx: usize,
    line_start: usize,
    line_end: usize,
    line_text: []const u8,
    segments: []const WrapSegment,
    editor: anytype,
    is_focused: bool,
    gutter_w: f32,
    code_pad_left: f32,
    options: CodeEditorOptions,
) void {
    const paint = uic.paint;
    const canvas = uic.canvas;
    const cur_lc = editor.offsetToLineCol(editor.cursor);
    const is_active_line = (cur_lc.line == line_idx);
    const line_1based: u32 = @intCast(line_idx + 1);
    const has_bp_gutter = options.show_line_numbers and options.show_breakpoint_gutter;
    const effective_bps = if (has_bp_gutter) (options.breakpoint_lines orelse editor.breakpointsSlice()) else &.{};
    const has_bp = has_bp_gutter and hasBreakpointOnLine(effective_bps, line_1based);
    const is_debug_line = has_bp_gutter and (options.active_debug_line != null and options.active_debug_line.? == line_1based);
    const is_bp_hovered = has_bp_gutter and (editor.hovered_bp_line == line_1based);
    const baseline_y = row_r.top + options.line_height * 0.74;
    const viewport_left = row_r.left + scroll_x;
    const code_x = row_r.left + code_pad_left;

    // 1. Active debugger execution line, breakpoint tint, or active cursor line background highlight
    if (is_debug_line) {
        paint.setStyle(.fill);
        paint.setColor(Color.argb(46, 251, 191, 36));
        canvas.drawRect(row_r, paint);
    } else if (has_bp) {
        paint.setStyle(.fill);
        paint.setColor(if (is_active_line) Color.argb(34, 248, 81, 73) else Color.argb(18, 248, 81, 73));
        canvas.drawRect(row_r, paint);
    } else if (is_active_line) {
        paint.setStyle(.fill);
        paint.setColor(if (is_focused) Color.argb(36, 99, 102, 241) else Color.argb(18, 148, 163, 184));
        canvas.drawRect(row_r, paint);
    }

    // 1b. Temporary jump-to-line flash highlight band
    if (editor.flash_line == line_1based and editor.flash_frames > 0) {
        const alpha: u8 = @intCast(@min(@as(u32, 110), (@as(u32, editor.flash_frames) * 110) / 45));
        paint.setStyle(.fill);
        paint.setColor(Color.argb(alpha, 245, 158, 11));
        canvas.drawRect(row_r, paint);
        const border_alpha: u8 = @intCast(@min(@as(u32, 180), (@as(u32, editor.flash_frames) * 180) / 45));
        paint.setColor(Color.argb(border_alpha, 251, 191, 36));
        canvas.drawRect(Rect.xywh(row_r.left, row_r.top, row_r.right - row_r.left, 1.0), paint);
        canvas.drawRect(Rect.xywh(row_r.left, row_r.bottom - 1.0, row_r.right - row_r.left, 1.0), paint);
    }

    if (segments.len <= 1) {
        // Fast path: single un-wrapped line
        // 2. Search query match highlights on this line
        if (options.search_query.len > 0 and options.search_query.len <= line_text.len) {
            const qlen = options.search_query.len;
            var m_idx: usize = 0;
            var line_hits: usize = 0;
            while (line_hits < 24) {
                const found_idx = root.indexOfIgnoreCasePos(line_text, m_idx, options.search_query) orelse break;
                const mx0 = code_x + uic.measureTextCached(font, line_text[0..found_idx]);
                const mx1 = code_x + uic.measureTextCached(font, line_text[0 .. found_idx + qlen]);
                paint.setStyle(.fill);
                paint.setColor(Color.argb(110, 245, 158, 11));
                canvas.drawRoundRect(Rect.xywh(mx0 - 1.0, row_r.top + 1.5, (mx1 - mx0) + 2.0, options.line_height - 3.0), 3.0, 3.0, paint);
                m_idx = found_idx + qlen;
                line_hits += 1;
            }
        }

        // 2b. Selection range highlight on this line
        if (editor.hasSelection()) {
            const sel = editor.selectionRange();
            if (sel.start <= line_end and sel.end >= line_start) {
                const sel_col_start = if (sel.start > line_start) sel.start - line_start else 0;
                const sel_col_end = if (sel.end < line_end) sel.end - line_start else line_text.len;

                const x0 = code_x + uic.measureTextCached(font, line_text[0..@min(sel_col_start, line_text.len)]);
                var x1 = code_x + uic.measureTextCached(font, line_text[0..@min(sel_col_end, line_text.len)]);
                if (sel.end > line_end) {
                    x1 += 7.0; // Show newline selection continuation
                }
                if (x1 > x0) {
                    paint.setStyle(.fill);
                    paint.setColor(if (is_focused) Color.argb(95, 56, 139, 253) else Color.argb(55, 100, 116, 139));
                    canvas.drawRoundRect(Rect.xywh(x0, row_r.top + 1.0, x1 - x0, options.line_height - 2.0), 3.0, 3.0, paint);
                }
            }
        }

        // 3. Indentation guides (every `tab_width` leading spaces)
        if (options.show_indent_guides and line_text.len >= options.tab_width) {
            var ws_count: usize = 0;
            while (ws_count < line_text.len and line_text[ws_count] == ' ') : (ws_count += 1) {}
            const tw: usize = @max(2, options.tab_width);
            if (ws_count >= tw) {
                const space_w = uic.measureTextCached(font, " ");
                paint.setStyle(.fill);
                paint.setColor(Color.argb(35, 148, 163, 184));
                var guide_col: usize = tw;
                while (guide_col <= ws_count) : (guide_col += tw) {
                    const gx = code_x + @as(f32, @floatFromInt(guide_col - tw)) * space_w;
                    canvas.drawRect(Rect.xywh(gx, row_r.top + 2.0, 1.0, options.line_height - 4.0), paint);
                }
            }
        }

        // 4. Syntax-highlighted or plain line text
        if (options.syntax_highlight and options.language != .plain) {
            drawSyntaxHighlightedLine(uic, font, line_text, code_x, baseline_y, options.language);
        } else {
            paint.setStyle(.fill);
            paint.setColor(Color.rgb(230, 237, 243));
            uic.drawTextCached(font, line_text, code_x, baseline_y);
        }

        // 5. Cursor Caret & Bracket Highlight on active line
        if (is_active_line and is_focused) {
            const col_clamped = @min(cur_lc.col, line_text.len);
            const caret_x = code_x + uic.measureTextCached(font, line_text[0..col_clamped]);

            // Highlight bracket under cursor if any
            if (col_clamped < line_text.len) {
                const ch = line_text[col_clamped];
                if (ch == '(' or ch == ')' or ch == '[' or ch == ']' or ch == '{' or ch == '}') {
                    const ch_w = uic.measureTextCached(font, line_text[col_clamped .. col_clamped + 1]);
                    paint.setStyle(.stroke);
                    paint.setStrokeWidth(1.2);
                    paint.setColor(uic.theme.accent_hover);
                    canvas.drawRoundRect(Rect.xywh(caret_x - 1.0, row_r.top + 2.0, ch_w + 2.0, options.line_height - 4.0), 2.5, 2.5, paint);
                }
            }

            // Crisp 2pt vertical cursor caret
            if (uic.platform_ctx) |pctx| {
                pctx.ime_cursor_x = caret_x;
                pctx.ime_cursor_y = row_r.top;
                pctx.ime_cursor_h = options.line_height;
            }
            paint.setStyle(.fill);
            paint.setColor(Color.rgb(129, 140, 248));
            canvas.drawRoundRect(Rect.xywh(caret_x, row_r.top + 2.5, 2.2, options.line_height - 5.0), 1.0, 1.0, paint);

            // 5b. Antigravity Supercomplete Inline Ghost Text (when active on cursor line)
            if (options.ghost_text.len > 0 and !editor.hasSelection()) {
                const first_nl = std.mem.indexOfScalar(u8, options.ghost_text, '\n');
                const first_line = if (first_nl) |nl| options.ghost_text[0..nl] else options.ghost_text;
                const ghost_x = if (col_clamped >= line_text.len)
                    caret_x + 3.0
                else
                    code_x + uic.measureTextCached(font, line_text) + 12.0;

                if (first_line.len > 0) {
                    paint.setStyle(.fill);
                    paint.setColor(Color.argb(145, 148, 163, 184));
                    uic.drawTextCached(font, first_line, ghost_x, baseline_y);
                }

                const first_w = uic.measureTextCached(font, first_line);
                const badge_x = ghost_x + first_w + 8.0;
                const badge_text = if (first_nl != null) "Tab ↵+" else "Tab";
                const badge_tw = uic.measureTextCached(uic.font_mono, badge_text);
                const badge_r = Rect.xywh(badge_x, row_r.top + 3.0, badge_tw + 8.0, options.line_height - 6.0);
                paint.setStyle(.fill);
                paint.setColor(Color.argb(55, 56, 139, 253));
                canvas.drawRoundRect(badge_r, 3.0, 3.0, paint);
                paint.setColor(Color.argb(200, 148, 163, 184));
                uic.drawTextCached(uic.font_mono, badge_text, badge_r.left + 4.0, baseline_y - 1.0);
            }
        }
    } else {
        // Multi-row word wrapped line: render each wrapped sub-row
        for (segments, 0..) |seg, k| {
            const sub_top = row_r.top + @as(f32, @floatFromInt(k)) * options.line_height;
            const sub_baseline_y = sub_top + options.line_height * 0.74;
            const sub_text = line_text[seg.start..seg.end];

            // Search query match highlights within this sub-segment
            if (options.search_query.len > 0 and options.search_query.len <= sub_text.len) {
                const qlen = options.search_query.len;
                var m_idx: usize = 0;
                var seg_hits: usize = 0;
                while (seg_hits < 24) {
                    const found_idx = root.indexOfIgnoreCasePos(sub_text, m_idx, options.search_query) orelse break;
                    const mx0 = code_x + uic.measureTextCached(font, sub_text[0..found_idx]);
                    const mx1 = code_x + uic.measureTextCached(font, sub_text[0 .. found_idx + qlen]);
                    paint.setStyle(.fill);
                    paint.setColor(Color.argb(110, 245, 158, 11));
                    canvas.drawRoundRect(Rect.xywh(mx0 - 1.0, sub_top + 1.5, (mx1 - mx0) + 2.0, options.line_height - 3.0), 3.0, 3.0, paint);
                    m_idx = found_idx + qlen;
                    seg_hits += 1;
                }
            }

            // Selection range within this sub-segment
            if (editor.hasSelection()) {
                const sel = editor.selectionRange();
                const seg_abs_start = line_start + seg.start;
                const seg_abs_end = line_start + seg.end;
                if (sel.start <= seg_abs_end and sel.end >= seg_abs_start) {
                    const sel_col_start = if (sel.start > seg_abs_start) sel.start - seg_abs_start else 0;
                    const sel_col_end = if (sel.end < seg_abs_end) sel.end - seg_abs_start else sub_text.len;

                    const x0 = code_x + uic.measureTextCached(font, sub_text[0..@min(sel_col_start, sub_text.len)]);
                    var x1 = code_x + uic.measureTextCached(font, sub_text[0..@min(sel_col_end, sub_text.len)]);
                    if (sel.end > seg_abs_end and k == segments.len - 1) {
                        x1 += 7.0;
                    }
                    if (x1 > x0) {
                        paint.setStyle(.fill);
                        paint.setColor(if (is_focused) Color.argb(95, 56, 139, 253) else Color.argb(55, 100, 116, 139));
                        canvas.drawRoundRect(Rect.xywh(x0, sub_top + 1.0, x1 - x0, options.line_height - 2.0), 3.0, 3.0, paint);
                    }
                }
            }

            // Syntax highlighting or plain text
            if (options.syntax_highlight and options.language != .plain) {
                drawSyntaxHighlightedLine(uic, font, sub_text, code_x, sub_baseline_y, options.language);
            } else {
                paint.setStyle(.fill);
                paint.setColor(Color.rgb(230, 237, 243));
                uic.drawTextCached(font, sub_text, code_x, sub_baseline_y);
            }

            // Cursor caret on this sub-segment
            if (is_active_line and is_focused) {
                const is_in_seg = if (k == segments.len - 1)
                    (cur_lc.col >= seg.start and cur_lc.col <= seg.end)
                else
                    (cur_lc.col >= seg.start and cur_lc.col < seg.end);

                if (is_in_seg) {
                    const col_in_seg = @min(cur_lc.col - seg.start, sub_text.len);
                    const caret_x = code_x + uic.measureTextCached(font, sub_text[0..col_in_seg]);

                    if (col_in_seg < sub_text.len) {
                        const ch = sub_text[col_in_seg];
                        if (ch == '(' or ch == ')' or ch == '[' or ch == ']' or ch == '{' or ch == '}') {
                            const ch_w = uic.measureTextCached(font, sub_text[col_in_seg .. col_in_seg + 1]);
                            paint.setStyle(.stroke);
                            paint.setStrokeWidth(1.2);
                            paint.setColor(uic.theme.accent_hover);
                            canvas.drawRoundRect(Rect.xywh(caret_x - 1.0, sub_top + 2.0, ch_w + 2.0, options.line_height - 4.0), 2.5, 2.5, paint);
                        }
                    }

                    if (uic.platform_ctx) |pctx| {
                        pctx.ime_cursor_x = caret_x;
                        pctx.ime_cursor_y = sub_top;
                        pctx.ime_cursor_h = options.line_height;
                    }
                    paint.setStyle(.fill);
                    paint.setColor(Color.rgb(129, 140, 248));
                    canvas.drawRoundRect(Rect.xywh(caret_x, sub_top + 2.5, 2.2, options.line_height - 5.0), 1.0, 1.0, paint);

                    // Ghost text on the last sub-segment
                    if (options.ghost_text.len > 0 and !editor.hasSelection() and k == segments.len - 1) {
                        const first_nl = std.mem.indexOfScalar(u8, options.ghost_text, '\n');
                        const first_line = if (first_nl) |nl| options.ghost_text[0..nl] else options.ghost_text;
                        const ghost_x = if (cur_lc.col >= line_text.len)
                            caret_x + 3.0
                        else
                            code_x + uic.measureTextCached(font, sub_text) + 12.0;

                        if (first_line.len > 0) {
                            paint.setStyle(.fill);
                            paint.setColor(Color.argb(145, 148, 163, 184));
                            uic.drawTextCached(font, first_line, ghost_x, sub_baseline_y);
                        }

                        const first_w = uic.measureTextCached(font, first_line);
                        const badge_x = ghost_x + first_w + 8.0;
                        const badge_text = if (first_nl != null) "Tab ↵+" else "Tab";
                        const badge_tw = uic.measureTextCached(uic.font_mono, badge_text);
                        const badge_r = Rect.xywh(badge_x, sub_top + 3.0, badge_tw + 8.0, options.line_height - 6.0);
                        paint.setStyle(.fill);
                        paint.setColor(Color.argb(55, 56, 139, 253));
                        canvas.drawRoundRect(badge_r, 3.0, 3.0, paint);
                        paint.setColor(Color.argb(200, 148, 163, 184));
                        uic.drawTextCached(uic.font_mono, badge_text, badge_r.left + 4.0, sub_baseline_y - 1.0);
                    }
                }
            }
        }
    }

    // 6. Sticky Gutter: Clickable Breakpoint Slot (left of line numbers) + Line Numbers + Separator
    if (options.show_line_numbers) {
        paint.setStyle(.fill);
        if (scroll_x > 0.5) {
            paint.setColor(Color.rgb(13, 17, 24));
            canvas.drawRect(Rect.xywh(viewport_left, row_r.top, gutter_w, row_r.bottom - row_r.top), paint);
            if (is_debug_line) {
                paint.setColor(Color.argb(46, 251, 191, 36));
                canvas.drawRect(Rect.xywh(viewport_left, row_r.top, gutter_w, row_r.bottom - row_r.top), paint);
            } else if (has_bp) {
                paint.setColor(if (is_active_line) Color.argb(34, 248, 81, 73) else Color.argb(18, 248, 81, 73));
                canvas.drawRect(Rect.xywh(viewport_left, row_r.top, gutter_w, row_r.bottom - row_r.top), paint);
            } else if (is_active_line) {
                paint.setColor(if (is_focused) Color.argb(36, 99, 102, 241) else Color.argb(18, 148, 163, 184));
                canvas.drawRect(Rect.xywh(viewport_left, row_r.top, gutter_w, row_r.bottom - row_r.top), paint);
            }
        }

        if (is_debug_line) {
            paint.setStyle(.fill);
            paint.setColor(Color.rgb(251, 191, 36));
            canvas.drawRect(Rect.xywh(viewport_left + 1.0, row_r.top, 2.5, row_r.bottom - row_r.top), paint);
        } else if (is_active_line and is_focused) {
            paint.setStyle(.fill);
            paint.setColor(uic.theme.accent);
            canvas.drawRect(Rect.xywh(viewport_left + 1.0, row_r.top, 2.5, row_r.bottom - row_r.top), paint);
        }

        // Clickable Breakpoint Indicator to the left of the line number (`viewport_left .. viewport_left + 20`)
        // Only shown when `options.show_breakpoint_gutter` is true for this file type.
        if (has_bp_gutter) {
            const bp_cx = viewport_left + 10.5;
            const bp_cy = row_r.top + options.line_height * 0.5;
            if (has_bp) {
                paint.setStyle(.fill);
                paint.setColor(Color.argb(75, 248, 81, 73));
                canvas.drawCircle(bp_cx, bp_cy, 6.2, paint);
                paint.setColor(Color.rgb(239, 68, 68));
                canvas.drawCircle(bp_cx, bp_cy, 4.8, paint);
                paint.setStyle(.stroke);
                paint.setStrokeWidth(1.0);
                paint.setColor(Color.argb(200, 254, 202, 202));
                canvas.drawCircle(bp_cx, bp_cy, 4.8, paint);
            } else if (is_bp_hovered) {
                paint.setStyle(.fill);
                paint.setColor(Color.argb(120, 248, 81, 73));
                canvas.drawCircle(bp_cx, bp_cy, 4.6, paint);
                paint.setStyle(.stroke);
                paint.setStrokeWidth(1.2);
                paint.setColor(Color.argb(215, 248, 81, 73));
                canvas.drawCircle(bp_cx, bp_cy, 4.6, paint);
            }

            if (is_debug_line) {
                paint.setStyle(.stroke);
                paint.setStrokeWidth(1.6);
                paint.setColor(Color.rgb(251, 191, 36));
                canvas.drawCircle(bp_cx, bp_cy, 6.2, paint);
            }
        }

        paint.setStyle(.fill);
        const num_str = uic.fmt("{d:>4}", .{line_idx + 1});
        paint.setColor(if (is_debug_line)
            Color.rgb(251, 191, 36)
        else if (has_bp)
            Color.rgb(248, 113, 113)
        else if (is_active_line)
            uic.theme.text_primary
        else
            Color.rgb(75, 88, 110));
        const num_x = viewport_left + (if (has_bp_gutter) BreakpointGutterWidth else 10.0);
        uic.drawTextCached(font, num_str, num_x, baseline_y);

        paint.setColor(if (scroll_x > 0.5) Color.argb(85, 100, 116, 139) else Color.argb(40, 100, 116, 139));
        canvas.drawRect(Rect.xywh(viewport_left + gutter_w, row_r.top, 1.0, row_r.bottom - row_r.top), paint);
    } else if (is_active_line and is_focused) {
        paint.setStyle(.fill);
        paint.setColor(uic.theme.accent);
        canvas.drawRect(Rect.xywh(viewport_left + 1.0, row_r.top, 2.5, row_r.bottom - row_r.top), paint);
    }
}

pub fn drawSyntaxHighlightedLine(
    uic: *Context,
    font: Font,
    line: []const u8,
    start_x: f32,
    baseline_y: f32,
    language: CodeLanguage,
) void {
    const paint = uic.paint;
    paint.setStyle(.fill);

    if (language == .plain) {
        paint.setColor(Color.rgb(226, 232, 240));
        uic.drawTextCached(font, line, start_x, baseline_y);
        return;
    }

    if (language == .markdown) {
        const trimmed = std.mem.trimStart(u8, line, " ");
        const md_col = if (std.mem.startsWith(u8, trimmed, "#"))
            Color.rgb(129, 140, 248)
        else if (std.mem.startsWith(u8, trimmed, ">"))
            Color.rgb(56, 189, 248)
        else if (std.mem.startsWith(u8, trimmed, "```"))
            Color.rgb(251, 191, 36)
        else if (std.mem.startsWith(u8, trimmed, "|"))
            Color.rgb(192, 132, 252)
        else if (std.mem.startsWith(u8, trimmed, "- ") or std.mem.startsWith(u8, trimmed, "* "))
            Color.rgb(52, 211, 153)
        else
            Color.rgb(226, 232, 240);
        paint.setColor(md_col);
        uic.drawTextCached(font, line, start_x, baseline_y);
        return;
    }

    var cursor_x = start_x;
    var i: usize = 0;

    while (i < line.len) {
        if (line[i] == ' ' or line[i] == '\t') {
            var end = i + 1;
            while (end < line.len and (line[end] == ' ' or line[end] == '\t')) : (end += 1) {}
            cursor_x += uic.measureTextCached(font, line[i..end]);
            i = end;
            continue;
        }

        // Line comments (`//`, `#` in Shell/Python, `--` in VHDL) & C/C++/DeviceTree preprocessor directives
        if ((i + 1 < line.len and line[i] == '/' and line[i + 1] == '/') or
            ((language == .bash or language == .python) and line[i] == '#') or
            (language == .vhdl and i + 1 < line.len and line[i] == '-' and line[i + 1] == '-'))
        {
            paint.setColor(Color.rgb(110, 118, 129));
            uic.drawTextCached(font, line[i..], cursor_x, baseline_y);
            break;
        }
        // Inline block comments (`/* ... */`)
        if (i + 1 < line.len and line[i] == '/' and line[i + 1] == '*' and
            language != .bash and language != .python and language != .vhdl)
        {
            const close_pos = std.mem.indexOfPos(u8, line, i + 2, "*/");
            const end = if (close_pos) |cp| cp + 2 else line.len;
            const cmt = line[i..end];
            paint.setColor(Color.rgb(110, 118, 129));
            uic.drawTextCached(font, cmt, cursor_x, baseline_y);
            cursor_x += uic.measureTextCached(font, cmt);
            i = end;
            continue;
        }
        if ((language == .cpp or language == .devicetree) and line[i] == '#') {
            paint.setColor(Color.rgb(210, 168, 255));
            uic.drawTextCached(font, line[i..], cursor_x, baseline_y);
            break;
        }
        // SystemVerilog compiler directives (`timescale, `include, `define, `ifdef) and system tasks ($dumpfile, $finish, $test$plusargs)
        if (language == .systemverilog and (line[i] == '`' or line[i] == '$')) {
            const lead = line[i];
            var end = i + 1;
            while (end < line.len and (std.ascii.isAlphanumeric(line[end]) or line[end] == '_' or (lead == '$' and line[end] == '$'))) : (end += 1) {}
            const dir_tok = line[i..end];
            paint.setColor(Color.rgb(210, 168, 255));
            uic.drawTextCached(font, dir_tok, cursor_x, baseline_y);
            cursor_x += uic.measureTextCached(font, dir_tok);
            i = end;
            continue;
        }

        // String literals (including Go/Markdown raw backtick strings)
        if (line[i] == '"' or (line[i] == '\'' and language != .systemverilog) or (language == .go and line[i] == '`')) {
            const quote = line[i];
            var end = i + 1;
            while (end < line.len) : (end += 1) {
                if (line[end] == '\\' and end + 1 < line.len) {
                    end += 1;
                    continue;
                }
                if (line[end] == quote) {
                    end += 1;
                    break;
                }
            }
            const s = line[i..end];
            // In JSON, keys before ':' get a distinct cyan tint
            const is_json_key = (language == .json and end < line.len and line[end] == ':');
            paint.setColor(if (is_json_key) Color.rgb(121, 192, 255) else Color.rgb(165, 214, 255));
            uic.drawTextCached(font, s, cursor_x, baseline_y);
            cursor_x += uic.measureTextCached(font, s);
            i = end;
            continue;
        }

        // Identifiers, Keywords, Builtins
        if (std.ascii.isAlphabetic(line[i]) or line[i] == '_' or line[i] == '@') {
            var end = i + 1;
            while (end < line.len and (std.ascii.isAlphanumeric(line[end]) or line[end] == '_')) : (end += 1) {}
            const word = line[i..end];
            const is_sv_cast = (language == .systemverilog and end + 1 < line.len and line[end] == '\'' and line[end + 1] == '(');
            const is_scope_prefix = (end + 1 < line.len and line[end] == ':' and line[end + 1] == ':');

            const col = if (word[0] == '@')
                Color.rgb(210, 168, 255)
            else if (isKeyword(word))
                Color.rgb(255, 123, 114)
            else if (isPrimitiveType(word) or std.ascii.isUpper(word[0]) or is_sv_cast or is_scope_prefix)
                Color.rgb(121, 192, 255)
            else if (end < line.len and line[end] == '(')
                Color.rgb(210, 168, 255)
            else
                Color.rgb(230, 237, 243);

            paint.setColor(col);
            uic.drawTextCached(font, word, cursor_x, baseline_y);
            cursor_x += uic.measureTextCached(font, word);
            i = end;
            continue;
        }

        // Numbers (including SystemVerilog sized/unsized literals like `8'hFF`, `1'b0`, `'0`, `'z`, `4'b10??`)
        const is_sv_unsized_lit = (language == .systemverilog and line[i] == '\'' and i + 1 < line.len and (std.ascii.isAlphanumeric(line[i + 1]) or line[i + 1] == '?'));
        if (std.ascii.isDigit(line[i]) or is_sv_unsized_lit) {
            var end = i + 1;
            while (end < line.len) : (end += 1) {
                const ch = line[end];
                if (std.ascii.isAlphanumeric(ch) or ch == '.' or ch == '_' or (language == .systemverilog and ch == '?')) {
                    continue;
                }
                if (language == .systemverilog and ch == '\'' and end + 1 < line.len and (std.ascii.isAlphanumeric(line[end + 1]) or line[end + 1] == '?')) {
                    continue;
                }
                break;
            }
            const num = line[i..end];
            paint.setColor(Color.rgb(121, 192, 255));
            uic.drawTextCached(font, num, cursor_x, baseline_y);
            cursor_x += uic.measureTextCached(font, num);
            i = end;
            continue;
        }

        // Non-ASCII UTF-8 (Emoji & Unicode runs)
        if (line[i] >= 0x80) {
            var end = nextGraphemeBoundary(line, i);
            while (end < line.len and line[end] >= 0x80) {
                end = nextGraphemeBoundary(line, end);
            }
            const uni_slice = line[i..end];
            paint.setColor(Color.rgb(230, 237, 243));
            uic.drawTextCached(font, uni_slice, cursor_x, baseline_y);
            cursor_x += uic.measureTextCached(font, uni_slice);
            i = end;
            continue;
        }

        // Operators / Punctuation
        var end = i + 1;
        while (end < line.len and
            line[end] < 0x80 and
            !std.ascii.isAlphanumeric(line[end]) and
            line[end] != '_' and
            line[end] != ' ' and
            line[end] != '\t' and
            line[end] != '"' and
            line[end] != '@' and
            !(line[end] == '\'' and (language != .systemverilog or (end + 1 < line.len and (std.ascii.isAlphanumeric(line[end + 1]) or line[end + 1] == '?')))) and
            !(language == .systemverilog and (line[end] == '$' or line[end] == '`')) and
            !(language == .go and line[end] == '`') and
            !((language == .bash or language == .python or language == .cpp or language == .devicetree) and line[end] == '#') and
            !(language == .vhdl and end + 1 < line.len and line[end] == '-' and line[end + 1] == '-') and
            !(end + 1 < line.len and line[end] == '/' and (line[end + 1] == '/' or line[end + 1] == '*'))) : (end += 1)
        {}
        const punct = line[i..end];
        paint.setColor(Color.rgb(148, 163, 184));
        uic.drawTextCached(font, punct, cursor_x, baseline_y);
        cursor_x += uic.measureTextCached(font, punct);
        i = end;
    }
}

fn drawEditorMinimap(
    uic: *Context,
    map_r: c.sk_rect_t,
    editor: anytype,
    scroll_y: f32,
    viewport_h: f32,
    options: CodeEditorOptions,
) void {
    const paint = uic.paint;
    const canvas = uic.canvas;

    paint.setStyle(.fill);
    paint.setColor(Color.argb(45, 100, 116, 139));
    canvas.drawRect(Rect.xywh(map_r.left, map_r.top, 1.0, map_r.bottom - map_r.top), paint);

    const total_lines = @max(1, editor.lineCount());
    const content_h = @as(f32, @floatFromInt(total_lines)) * options.line_height;
    const map_avail_h = (map_r.bottom - map_r.top) - 12.0;

    // Viewport lens box
    const lens_top_ratio = std.math.clamp(scroll_y / @max(1.0, content_h), 0.0, 1.0);
    const lens_h_ratio = std.math.clamp(viewport_h / @max(1.0, content_h), 0.12, 1.0);
    const max_visual_h = @min(map_avail_h, @as(f32, @floatFromInt(total_lines)) * 4.0);
    const lens_y = map_r.top + 6.0 + lens_top_ratio * @max(0.0, max_visual_h * (1.0 - lens_h_ratio));
    const lens_h = @max(18.0, max_visual_h * lens_h_ratio);

    paint.setColor(Color.argb(32, 129, 140, 248));
    canvas.drawRoundRect(Rect.xywh(map_r.left + 4.0, lens_y, (map_r.right - map_r.left) - 8.0, lens_h), 3.0, 3.0, paint);

    const cur_line = editor.offsetToLineCol(editor.cursor).line;
    const text = editor.slice();
    const max_rows = @max(1, @as(usize, @intFromFloat(@floor(@max(4.0, map_avail_h - 4.0) / 4.0))));
    const row_count = @min(total_lines, max_rows);
    const active_row = if (total_lines > row_count)
        (cur_line * row_count) / total_lines
    else
        cur_line;

    var y = map_r.top + 8.0;
    for (0..row_count) |r_idx| {
        if (y + 3.0 > map_r.bottom - 6.0) break;
        const line_idx = if (total_lines > row_count)
            (r_idx * total_lines) / row_count
        else
            r_idx;
        const lr = editor.lineRangeByIndex(line_idx);
        const line = text[lr.start..lr.end];
        const trimmed = std.mem.trimStart(u8, line, " ");
        const indent_spaces = line.len - trimmed.len;

        if (r_idx == active_row) {
            paint.setColor(uic.theme.accent);
            canvas.drawRect(Rect.xywh(map_r.left + 2.0, y - 0.5, 3.0, 3.5), paint);
        }
        if (options.show_breakpoint_gutter) {
            const effective_bps = options.breakpoint_lines orelse editor.breakpointsSlice();
            if (hasBreakpointOnLine(effective_bps, @intCast(line_idx + 1))) {
                paint.setColor(Color.rgb(239, 68, 68));
                canvas.drawCircle(map_r.left + 4.5, y + 1.0, 2.0, paint);
            }
        }

        if (trimmed.len > 0) {
            const x = map_r.left + 8.0 + @min(24.0, @as(f32, @floatFromInt(indent_spaces)) * 1.2);
            const bar_w = @min((map_r.right - 6.0) - x, @as(f32, @floatFromInt(trimmed.len)) * 1.15);
            if (bar_w > 1.0) {
                const bar_col = if (std.mem.startsWith(u8, trimmed, "//") or std.mem.startsWith(u8, trimmed, "#"))
                    Color.rgb(90, 102, 120)
                else if (std.mem.startsWith(u8, trimmed, "pub ") or std.mem.startsWith(u8, trimmed, "const ") or std.mem.startsWith(u8, trimmed, "fn "))
                    Color.rgb(255, 123, 114)
                else
                    Color.rgb(148, 163, 184);
                paint.setColor(bar_col);
                canvas.drawRect(Rect.xywh(x, y, bar_w, 2.0), paint);
            }
        }
        y += 4.0;
    }
}

fn drawEditorStatusBar(
    uic: *Context,
    font: Font,
    status_r: c.sk_rect_t,
    editor: anytype,
    res: CodeEditorResult,
    options: CodeEditorOptions,
) void {
    const paint = uic.paint;
    const canvas = uic.canvas;

    // Top border line
    paint.setStyle(.fill);
    paint.setColor(uic.theme.border_subtle);
    canvas.drawRect(Rect.xywh(status_r.left, status_r.top, status_r.right - status_r.left, 1.0), paint);

    const baseline_y = status_r.top + 16.0;

    // Focus status dot + label
    paint.setColor(if (res.focused) uic.theme.success else uic.theme.text_muted);
    canvas.drawCircle(status_r.left + 14.0, status_r.top + 12.0, 3.5, paint);

    const mode_label = if (options.read_only) "READ-ONLY" else if (res.focused) "EDITING" else "CLICK TO FOCUS";
    paint.setColor(if (res.focused) uic.theme.text_primary else uic.theme.text_muted);
    uic.drawTextCached(font, mode_label, status_r.left + 23.0, baseline_y);

    // Cursor Ln/Col & Selection info
    const pos_str = if (res.selection_len > 0)
        uic.fmt("Ln {d}, Col {d}  ({d} selected)", .{ res.cursor_line, res.cursor_col, res.selection_len })
    else
        uic.fmt("Ln {d}, Col {d}", .{ res.cursor_line, res.cursor_col });

    paint.setColor(uic.theme.text_muted);
    uic.drawTextCached(font, pos_str, status_r.left + 140.0, baseline_y);

    // Right-aligned buffer metrics & language
    const meta_str = uic.fmt("{d} lines  |  {d} B  |  {s}  |  UTF-8", .{
        res.line_count,
        editor.len,
        options.language.label(),
    });
    const meta_w = uic.measureTextCached(font, meta_str);
    if (status_r.right - meta_w - 12.0 > status_r.left + 280.0) {
        paint.setColor(uic.theme.accent_hover);
        uic.drawTextCached(font, meta_str, status_r.right - meta_w - 12.0, baseline_y);
    }
}

pub fn findColumnAtX(uic: *Context, font: Font, line_text: []const u8, rel_x: f32) usize {
    if (rel_x <= 0 or line_text.len == 0) return 0;
    var best_col: usize = 0;
    var prev_w: f32 = 0;
    var i: usize = 0;
    while (i < line_text.len) {
        const next_i = nextGraphemeBoundary(line_text, i);
        const w = uic.measureTextCached(font, line_text[0..next_i]);
        const mid = (prev_w + w) * 0.5;
        if (rel_x < mid) {
            return best_col;
        }
        best_col = next_i;
        prev_w = w;
        i = next_i;
    }
    return line_text.len;
}

fn isKeyword(word: []const u8) bool {
    const keywords = [_][]const u8{
        // Zig
        "const",     "var",       "pub",        "fn",         "return",     "try",        "catch",
        "defer",     "errdefer",  "if",         "else",       "switch",     "while",      "for",
        "break",     "continue",  "struct",     "enum",       "union",      "opaque",     "export",
        "extern",    "comptime",  "inline",     "test",       "true",       "false",      "null",
        "undefined", "and",       "or",         "orelse",     "unreachable",
        // C / C++
        "class",     "namespace", "template",   "typename",   "virtual",    "override",   "final",
        "constexpr", "noexcept",  "static",     "auto",       "nullptr",    "new",        "delete",
        "using",     "typedef",   "sizeof",     "alignof",    "public",     "private",    "protected",
        "friend",    "mutable",   "explicit",   "operator",   "case",       "default",    "do",
        // Java
        "package",   "import",    "interface",  "extends",    "implements", "abstract",   "synchronized",
        "volatile",  "transient", "throws",     "throw",      "finally",    "instanceof", "super",
        "this",      "record",    "sealed",     "permits",
        // Go
        "func",      "type",      "chan",       "go",         "select",     "range",      "fallthrough",
        "map",       "nil",       "make",       "append",     "len",        "cap",        "panic",
        "recover",
        // SystemVerilog (IEEE 1800)
        "module",    "endmodule", "interface",  "endinterface", "package",  "endpackage", "always_ff",
        "always_comb", "always_latch", "always", "initial",   "posedge",    "negedge",    "assign",
        "begin",     "end",       "endcase",    "casex",      "casez",      "generate",   "endgenerate",
        "function",  "endfunction", "task",     "endtask",    "parameter",  "localparam", "modport",
        "clocking",  "endclocking", "property", "endproperty", "assert",    "assume",     "cover",
        "iff",       "unique",    "priority",   "forever",    "repeat",     "wait",       "fork",
        "join",      "join_any",  "join_none",  "genvar",     "automatic",
        // Rust
        "let",       "mut",       "impl",       "trait",      "use",        "mod",        "match",
        "async",     "await",     "where",      "crate",      "super",      "self",       "Self",
        "ref",       "move",      "unsafe",     "dyn",        "loop",       "in",         "as",
        // Python
        "def",       "from",      "elif",       "except",     "pass",       "raise",      "with",
        "yield",     "lambda",    "nonlocal",   "global",     "del",        "not",        "is",
        "None",      "True",      "False",
        // TypeScript / JavaScript
        "readonly",  "keyof",     "typeof",     "instanceof", "declare",    "namespace",  "Satisfies",
        // VHDL / Chisel (Scala) / DeviceTree
        "entity",    "architecture", "of",      "port",       "generic",    "signal",     "variable",
        "constant",  "process",   "library",    "downto",     "to",         "others",     "rising_edge",
        "falling_edge", "object", "val",        "when",       "elsewhen",   "otherwise",  "compatible",
        "status",    "interrupts", "clocks",
    };
    for (keywords) |kw| {
        if (std.mem.eql(u8, word, kw)) return true;
    }
    return false;
}

fn isPrimitiveType(word: []const u8) bool {
    const types = [_][]const u8{
        // Zig
        "u8",        "u16",       "u32",       "u64",     "usize",    "i8",       "i16",
        "i32",       "i64",       "isize",     "f32",     "f64",      "bool",     "void",
        "type",      "anytype",   "anyopaque", "c_int",   "c_uint",
        // C / C++ / Java / Go
        "int",       "long",      "short",     "char",    "float",    "double",   "unsigned",
        "signed",    "size_t",    "ssize_t",   "uint8_t", "uint16_t", "uint32_t", "uint64_t",
        "int8_t",    "int16_t",   "int32_t",   "int64_t", "boolean",  "byte",     "String",
        "Object",    "Integer",   "Long",      "Double",  "List",     "Map",      "Optional",
        "string",    "int8",      "int16",     "int32",   "int64",    "uint",     "uint8",
        "uint16",    "uint32",    "uint64",    "uintptr", "float32",  "float64",  "rune",
        "error",     "any",       "vector",    "string_view",
        // SystemVerilog
        "logic",     "bit",       "reg",       "wire",    "tri",      "shortint", "longint",
        "integer",   "time",      "real",      "shortreal", "realtime", "input",  "output",
        "inout",     "ref",       "packed",    "chandle", "event",
        // Rust / Python / TypeScript / VHDL / Chisel
        "u128",      "i128",      "str",       "Vec",     "Box",      "Rc",       "Arc",
        "Option",    "Result",    "Some",      "Ok",      "Err",      "dict",     "list",
        "tuple",     "set",       "bytes",     "number",  "unknown",  "never",    "Promise",
        "Record",    "Array",     "std_logic", "std_logic_vector",    "UInt",     "SInt",
        "Bool",      "Bundle",    "Module",    "IO",      "RegInit",  "RegNext",  "Wire",
    };
    for (types) |t| {
        if (std.mem.eql(u8, word, t)) return true;
    }
    return false;
}

// ============================================================================
// Unit Tests
// ============================================================================

test "CodeEditorBuffer: insertion, auto-pairs, auto-indent, comment toggle, and undo/redo" {
    var buf = CodeEditorBuffer(1024).initFromSlice("const x = 10;");
    try std.testing.expectEqualStrings("const x = 10;", buf.slice());

    // Move cursor to end and insert newline
    buf.moveRight(false, false, true);
    _ = buf.insertNewlineAutoIndent(4);
    _ = buf.insertText("if (x > 0) ", true);
    _ = buf.insertText("{", true);
    // Auto-pair should have inserted closing `}` after cursor!
    try std.testing.expectEqualStrings("const x = 10;\nif (x > 0) {}", buf.slice());

    // Pressing Enter between `{|}` expands block with 4-space indentation
    _ = buf.insertNewlineAutoIndent(4);
    try std.testing.expectEqualStrings("const x = 10;\nif (x > 0) {\n    \n}", buf.slice());
    try std.testing.expectEqual(@as(usize, 3), buf.cursorLineCol().line);
    try std.testing.expectEqual(@as(usize, 5), buf.cursorLineCol().col);

    // Toggle line comment on line 1
    buf.cursor = 0;
    buf.selection_anchor = 0;
    _ = buf.toggleLineComment("// ");
    try std.testing.expect(std.mem.startsWith(u8, buf.slice(), "// const x = 10;"));

    // Undo restores prior state
    try std.testing.expect(buf.undo());
    try std.testing.expect(std.mem.startsWith(u8, buf.slice(), "const x = 10;"));

    // Redo re-applies comment
    try std.testing.expect(buf.redo());
    try std.testing.expect(std.mem.startsWith(u8, buf.slice(), "// const x = 10;"));

    // Mid-buffer Backspace (regression test for overlapping left-shift copyForwards vs copyBackwards)
    var mid_buf = CodeEditorBuffer(1024).initFromSlice("abcdef\n123456");
    mid_buf.cursor = 3; // right after "abc"
    mid_buf.selection_anchor = 3;
    try std.testing.expect(mid_buf.deleteBackward(false, false, 4));
    try std.testing.expectEqualStrings("abdef\n123456", mid_buf.slice());
    try std.testing.expectEqual(@as(usize, 2), mid_buf.cursor);

    // Mid-buffer Forward Delete
    try std.testing.expect(mid_buf.deleteForward(false));
    try std.testing.expectEqualStrings("abef\n123456", mid_buf.slice());

    // Multi-line selection Tab / Shift+Tab preserves selection
    var tab_buf = CodeEditorBuffer(1024).initFromSlice("line1\nline2\nline3");
    tab_buf.selection_anchor = 0;
    tab_buf.cursor = tab_buf.len;
    try std.testing.expect(tab_buf.hasSelection());

    try std.testing.expect(tab_buf.indentOrInsertTab(4));
    try std.testing.expectEqualStrings("    line1\n    line2\n    line3", tab_buf.slice());
    try std.testing.expect(tab_buf.hasSelection());
    try std.testing.expectEqualStrings("    line1\n    line2\n    line3", tab_buf.selectedSlice());

    try std.testing.expect(tab_buf.outdentSelection(4));
    try std.testing.expectEqualStrings("line1\nline2\nline3", tab_buf.slice());
    try std.testing.expect(tab_buf.hasSelection());
    try std.testing.expectEqualStrings("line1\nline2\nline3", tab_buf.selectedSlice());

    // Find & Jump to Line
    try std.testing.expectEqual(@as(usize, 3), tab_buf.countMatches("line"));
    tab_buf.jumpToLine(2);
    try std.testing.expectEqual(@as(usize, 2), tab_buf.cursorLineCol().line);
    try std.testing.expect(tab_buf.findNext("LINE3", true));
    try std.testing.expectEqualStrings("line3", tab_buf.selectedSlice());
    try std.testing.expect(tab_buf.findNext("line1", false));
    try std.testing.expectEqualStrings("line1", tab_buf.selectedSlice());
}

test "CodeEditor widget: focus, keyboard input, and 2-phase rendering" {
    const surface = try skia.Surface.initRasterN32Premul(640, 400);
    defer surface.deinit();

    const paint = try skia.Paint.init();
    defer paint.deinit();
    paint.setAntiAlias(true);

    const font = try Font.init(null, 13.0);
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

    var editor = CodeEditorBuffer(1024).initFromSlice("pub fn demo() void {\n    return;\n}");
    const root_rect = Rect.xywh(0, 0, 640, 400);

    // Frame 1: Click inside editor at (100, 30) to focus and place cursor, plus type text
    uic.text_input = "// ";
    uic.beginPass(.input, arena.allocator(), surface.canvas(), root_rect, 100, 30, true, true, false);
    const res1 = uic.codeEditor("test_editor", 0, 0, &editor, .{});
    uic.endPass();
    try std.testing.expect(res1.focused);
    try std.testing.expect(res1.text_changed);
    try std.testing.expect(uic.dirty_rect != null);

    // Paint pass
    uic.text_input = "";
    uic.beginPass(.paint, arena.allocator(), surface.canvas(), root_rect, 100, 30, true, true, false);
    _ = uic.codeEditor("test_editor", 0, 0, &editor, .{});
    uic.endPass();
}

test "CodeEditorBuffer: dynamic heap expansion and undo/redo for large files beyond inline capacity" {
    var large_buf = CodeEditorBuffer(1024){};
    defer large_buf.deinit();

    const chunk = "// Large file test line 0123456789abcdefghijklmnopqrstuvwxyz\n";
    const repeat_count: usize = 2500; // ~152 KB (> 1024 B inline capacity)
    const full_size = chunk.len * repeat_count;
    const input = try std.testing.allocator.alloc(u8, full_size);
    defer std.testing.allocator.free(input);

    for (0..repeat_count) |i| {
        @memcpy(input[i * chunk.len .. (i + 1) * chunk.len], chunk);
    }

    large_buf.resetWithSlice(input);
    try std.testing.expectEqual(full_size, large_buf.slice().len);
    try std.testing.expect(large_buf.heap_ptr != null);

    // Edit at the very end of the 152 KB buffer and verify Undo/Redo preserves all bytes
    large_buf.cursor = large_buf.len;
    large_buf.selection_anchor = large_buf.len;
    try std.testing.expect(large_buf.insertText("pub const EOF_MARKER = 42;\n", false));
    try std.testing.expectEqual(full_size + 27, large_buf.slice().len);
    try std.testing.expect(std.mem.endsWith(u8, large_buf.slice(), "pub const EOF_MARKER = 42;\n"));

    try std.testing.expect(large_buf.undo());
    try std.testing.expectEqual(full_size, large_buf.slice().len);

    try std.testing.expect(large_buf.redo());
    try std.testing.expectEqual(full_size + 27, large_buf.slice().len);
}

test "CodeEditorBuffer & Skia: emoji and unicode grapheme cluster navigation, deletion, and fallback shaping" {
    // "🚀" (4B) + "⚙️" (6B: U+2699 + U+FE0F) + "👍🏽" (8B: U+1F44D + U+1F3FD)
    var buf = CodeEditorBuffer(1024).initFromSlice("🚀⚙️👍🏽\nabcdef");
    defer buf.deinit();

    // Step right across the 3 emoji grapheme clusters
    buf.cursor = 0;
    buf.selection_anchor = 0;
    buf.moveRight(false, false, false);
    try std.testing.expectEqual(@as(usize, 4), buf.cursor); // after 🚀
    buf.moveRight(false, false, false);
    try std.testing.expectEqual(@as(usize, 10), buf.cursor); // after ⚙️ (includes U+FE0F)
    buf.moveRight(false, false, false);
    try std.testing.expectEqual(@as(usize, 18), buf.cursor); // after 👍🏽 (includes skin tone modifier)

    // Moving down then up from column 2 (which is mid-emoji on line 0) snaps cleanly to grapheme boundary
    buf.cursor = 19 + 2; // 'c' on line 1 (col 2)
    buf.selection_anchor = buf.cursor;
    buf.moveUp(false);
    try std.testing.expectEqual(@as(usize, 0), buf.cursor); // snapped to start of 🚀, not mid-UTF8!

    // Delete backward removes the entire 👍🏽 grapheme cluster (8 bytes) in a single Backspace
    buf.cursor = 18;
    buf.selection_anchor = 18;
    try std.testing.expect(buf.deleteBackward(false, false, 4));
    try std.testing.expectEqualStrings("🚀⚙️\nabcdef", buf.slice());

    // Verify Skia fallback shaping produces a valid TextBlob and positive advance width for emojis
    const font = try Font.init(null, 13.0);
    defer font.deinit();
    const shaped = try skia.TextBlob.initFromUtf8WithWidth("Hello 🚀 ⚙️ ✨ 日本語", font);
    defer if (shaped.blob) |b| b.deinit();
    try std.testing.expect(shaped.blob != null);
    try std.testing.expect(shaped.width > 40.0);

    // Verify typing ``` produces 3 backticks (not 4), while typing `code` still auto-pairs cleanly
    var md_buf = CodeEditorBuffer(256).initFromSlice("");
    defer md_buf.deinit();
    _ = md_buf.insertText("`", true);
    try std.testing.expectEqualStrings("``", md_buf.slice());
    try std.testing.expectEqual(@as(usize, 1), md_buf.cursor);
    _ = md_buf.insertText("`", true); // steps over 2nd backtick
    try std.testing.expectEqualStrings("``", md_buf.slice());
    try std.testing.expectEqual(@as(usize, 2), md_buf.cursor);
    _ = md_buf.insertText("`", true); // inserts 3rd backtick without auto-pairing a 4th!
    try std.testing.expectEqualStrings("```", md_buf.slice());
    try std.testing.expectEqual(@as(usize, 3), md_buf.cursor);
    _ = md_buf.insertText("zig", true);
    try std.testing.expectEqualStrings("```zig", md_buf.slice());
}

test "CodeEditorBuffer: incremental line-start index O(log L) lookup and typing undo coalescing" {
    var buf = CodeEditorBuffer(1024).initFromSlice("alpha\nbeta\ngamma\ndelta");
    defer buf.deinit();

    try std.testing.expectEqual(@as(usize, 4), buf.lineCount());
    const lc2 = buf.offsetToLineCol(13); // 'm' in "gamma"
    try std.testing.expectEqual(@as(usize, 2), lc2.line);
    try std.testing.expectEqual(@as(usize, 2), lc2.col);

    // Insert characters on line 0 without newlines -> incremental shift updates line 1..3 offsets
    buf.cursor = 5;
    buf.selection_anchor = 5;
    _ = buf.insertText("_1", false);
    const lr2 = buf.lineRangeByIndex(2);
    try std.testing.expectEqualStrings("gamma", buf.slice()[lr2.start..lr2.end]);

    // Consecutive single-char typing coalesces into one undo step
    var coalesce_buf = CodeEditorBuffer(512).initFromSlice("start:");
    defer coalesce_buf.deinit();
    coalesce_buf.cursor = coalesce_buf.len;
    coalesce_buf.selection_anchor = coalesce_buf.len;
    for ("hello") |ch| {
        const s = [1]u8{ch};
        _ = coalesce_buf.insertText(&s, false);
    }
    try std.testing.expectEqualStrings("start:hello", coalesce_buf.slice());
    // A single undo reverts the entire coalesced word "hello"!
    try std.testing.expect(coalesce_buf.undo());
    try std.testing.expectEqualStrings("start:", coalesce_buf.slice());
}

test "CodeEditorBuffer: heap-growable line_starts index (>2,048 lines) and viewport virtualization" {
    var huge_buf = CodeEditorBuffer(4096).initFromSlice("");
    defer huge_buf.deinit();

    var text_list: std.ArrayList(u8) = .empty;
    defer text_list.deinit(std.testing.allocator);
    for (0..5000) |line_i| {
        const line = try std.fmt.allocPrint(std.testing.allocator, "line_{d:0>4}\n", .{line_i});
        defer std.testing.allocator.free(line);
        try text_list.appendSlice(std.testing.allocator, line);
    }
    huge_buf.resetWithSlice(text_list.items);

    try std.testing.expectEqual(@as(usize, 5001), huge_buf.lineCount());
    try std.testing.expect(huge_buf.line_starts_heap != null);

    // O(1) lineRangeByIndex and O(log L) offsetToLineCol at line 4,200 (beyond 2,048 inline cap)
    const lr = huge_buf.lineRangeByIndex(4200);
    try std.testing.expectEqualStrings("line_4200", huge_buf.slice()[lr.start..lr.end]);
    const lc = huge_buf.offsetToLineCol(lr.start + 5);
    try std.testing.expectEqual(@as(usize, 4200), lc.line);
    try std.testing.expectEqual(@as(usize, 5), lc.col);

    // Jump to line 3,500 and verify 2-phase virtualized rendering
    huge_buf.jumpToLine(3500);
    const surface = try skia.Surface.initRasterN32Premul(800, 600);
    defer surface.deinit();
    const paint = try skia.Paint.init();
    defer paint.deinit();
    const font = try Font.init(null, 13.0);
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

    const win_rect = Rect.xywh(0, 0, 800, 600);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 100, 100, false, false, false);
    const r_in = uic.codeEditor("test_huge_ed", 800, 600, &huge_buf, .{ .show_minimap = true });
    uic.endPass();
    try std.testing.expectEqual(@as(usize, 3500), r_in.cursor_line);
    // jumpToLine(3500) aligns 0-based line 3499 right at the top of the viewport (3499 * 21.0 = 73479.0)
    try std.testing.expectEqual(@as(f32, 3499.0 * 21.0), uic.fallback_scroll_state.scroll_y);

    uic.invalidateWindow();
    uic.clip_damage = win_rect;
    uic.beginPass(.paint, arena.allocator(), surface.canvas(), win_rect, 100, 100, false, false, false);
    const r_out = uic.codeEditor("test_huge_ed", 800, 600, &huge_buf, .{ .show_minimap = true });
    uic.endPass();
    try std.testing.expectEqual(@as(usize, 3500), r_out.cursor_line);
}

test "CodeEditor: double-click word selection, triple-click line selection, Shift-click, and Cmd+Up/Down" {
    var ed_buf = CodeEditorBuffer(1024).initFromSlice("const alpha_beta = 42;\nreturn alpha_beta;\n");
    defer ed_buf.deinit();

    const surface = try skia.Surface.initRasterN32Premul(600, 300);
    defer surface.deinit();
    const paint = try skia.Paint.init();
    defer paint.deinit();
    const font = try Font.init(null, 13.0);
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

    const win_rect = Rect.xywh(0, 0, 600, 300);

    // 1. Double-click on "alpha_beta" on line 0 (x = 120, y = 16)
    uic.mouse_click_count = 2;
    uic.mouse_shift = false;
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 120, 16, true, true, false);
    _ = uic.codeEditor("test_clicks", 600, 300, &ed_buf, .{});
    uic.endPass();
    const sel1 = ed_buf.selectionRange();
    try std.testing.expectEqualStrings("alpha_beta", ed_buf.slice()[sel1.start..sel1.end]);

    // 2. Triple-click on line 0 (x = 120, y = 16) -> selects entire line 0 including '\n'
    uic.mouse_click_count = 3;
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 120, 16, true, true, false);
    _ = uic.codeEditor("test_clicks", 600, 300, &ed_buf, .{});
    uic.endPass();
    const sel2 = ed_buf.selectionRange();
    try std.testing.expectEqualStrings("const alpha_beta = 42;\n", ed_buf.slice()[sel2.start..sel2.end]);

    // 3. Cmd+Down jumps to end of document, Cmd+Up with Shift selects entire document
    uic.mouse_click_count = 1;
    const cmd_down_then_shift_cmd_up = [_]platform.KeyEvent{
        .{ .key = .down, .cmd = true },
        .{ .key = .up, .cmd = true, .shift = true },
    };
    uic.key_events = &cmd_down_then_shift_cmd_up;
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 120, 16, false, false, false);
    _ = uic.codeEditor("test_clicks", 600, 300, &ed_buf, .{});
    uic.endPass();
    try std.testing.expectEqual(@as(usize, 0), ed_buf.cursor);
    try std.testing.expectEqual(ed_buf.len, ed_buf.selection_anchor);
}

test "CodeEditorBuffer & PlatformContext: large 128 KB copy, cut, paste, CRLF normalization, and undo/redo" {
    var ed_buf = CodeEditorBuffer(4096).initFromSlice("header\nfooter\n");
    defer ed_buf.deinit();

    // Build a 128 KB multi-line payload (32x larger than the 4 KB inline clipboard_buf)
    var large_text: std.ArrayList(u8) = .empty;
    defer large_text.deinit(std.testing.allocator);
    for (0..4000) |i| {
        const line = try std.fmt.allocPrint(std.testing.allocator, "const item_{d:0>4} = {d};\r\n", .{ i, i * 3 });
        defer std.testing.allocator.free(line);
        try large_text.appendSlice(std.testing.allocator, line);
    }
    try std.testing.expect(large_text.items.len > 90_000);

    // Place caret between "header\n" and "footer\n", set clipboard, and paste
    ed_buf.cursor = 7;
    ed_buf.selection_anchor = 7;
    ed_buf.setClipboardSlice(large_text.items);
    try std.testing.expectEqual(large_text.items.len, ed_buf.clipboardSlice().len);
    try std.testing.expect(ed_buf.clipboard_heap_ptr != null);

    try std.testing.expect(ed_buf.pasteClipboard());
    // CRLF ('\r\n') should be normalized to '\n' (4000 fewer bytes)
    const expected_normalized_len = large_text.items.len - 4000;
    try std.testing.expectEqual(14 + expected_normalized_len, ed_buf.len);
    try std.testing.expectEqual(@as(usize, 4003), ed_buf.lineCount());

    // Select all, copy back to clipboard -> full 90+ KB buffer copied without 4 KB truncation
    ed_buf.selectAll();
    ed_buf.copySelection();
    try std.testing.expectEqual(ed_buf.len, ed_buf.clipboardSlice().len);

    // Undo the 90+ KB paste -> back to "header\nfooter\n"
    try std.testing.expect(ed_buf.undo());
    try std.testing.expectEqualStrings("header\nfooter\n", ed_buf.slice());

    // Redo the 90+ KB paste -> restored in full
    try std.testing.expect(ed_buf.redo());
    try std.testing.expectEqual(14 + expected_normalized_len, ed_buf.len);
}

test "CodeEditor: multi-language comment toggling (# / -- / //), keyword/type tables, and 2-phase rendering" {
    try std.testing.expectEqualStrings("// ", CodeLanguage.rust.commentPrefix());
    try std.testing.expectEqualStrings("# ", CodeLanguage.python.commentPrefix());
    try std.testing.expectEqualStrings("// ", CodeLanguage.typescript.commentPrefix());
    try std.testing.expectEqualStrings("-- ", CodeLanguage.vhdl.commentPrefix());
    try std.testing.expectEqualStrings("// ", CodeLanguage.chisel.commentPrefix());
    try std.testing.expectEqualStrings("// ", CodeLanguage.devicetree.commentPrefix());

    try std.testing.expect(isKeyword("impl") and isKeyword("def") and isKeyword("entity") and isKeyword("elsewhen"));
    try std.testing.expect(isPrimitiveType("Option") and isPrimitiveType("Promise") and isPrimitiveType("std_logic_vector") and isPrimitiveType("UInt"));

    // Toggle VHDL `-- ` comment and Python `# ` comment
    var ed_buf = CodeEditorBuffer(512).initFromSlice("signal clk : std_logic;");
    defer ed_buf.deinit();
    try std.testing.expect(ed_buf.toggleLineComment(CodeLanguage.vhdl.commentPrefix()));
    try std.testing.expectEqualStrings("-- signal clk : std_logic;", ed_buf.slice());
    try std.testing.expect(ed_buf.toggleLineComment(CodeLanguage.vhdl.commentPrefix()));
    try std.testing.expectEqualStrings("signal clk : std_logic;", ed_buf.slice());

    ed_buf.resetWithSlice("def run_task() -> int:");
    try std.testing.expect(ed_buf.toggleLineComment(CodeLanguage.python.commentPrefix()));
    try std.testing.expectEqualStrings("# def run_task() -> int:", ed_buf.slice());

    // Render 2-phase frames for Rust, Python, TypeScript, VHDL, Chisel, and DeviceTree
    const surface = try skia.Surface.initRasterN32Premul(600, 240);
    defer surface.deinit();
    const paint = try skia.Paint.init();
    defer paint.deinit();
    const font = try Font.init(null, 12.0);
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
    const win_rect = Rect.xywh(0, 0, 600, 240);

    const langs = [_]struct { lang: CodeLanguage, sample: []const u8 }{
        .{ .lang = .rust, .sample = "// Rust\npub struct Node { val: Option<u32> }\n" },
        .{ .lang = .python, .sample = "# Python\ndef compute(x: int) -> bool:\n    return True\n" },
        .{ .lang = .typescript, .sample = "// TS\nexport interface Config { readonly port: number; }\n" },
        .{ .lang = .vhdl, .sample = "-- VHDL\nsignal bus_a : std_logic_vector(7 downto 0);\n" },
        .{ .lang = .chisel, .sample = "// Chisel\nval reg_a = RegInit(0.U(8.W))\n" },
        .{ .lang = .devicetree, .sample = "#include \"soc.dtsi\"\nuart0: serial@10000000 { status = \"okay\"; };\n" },
    };
    for (langs) |entry| {
        ed_buf.resetWithSlice(entry.sample);
        _ = arena.reset(.retain_capacity);
        uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 40, 40, false, false, false);
        _ = uic.codeEditor("lang_test_ed", 600, 240, &ed_buf, .{ .language = entry.lang });
        uic.endPass();

        uic.invalidateWindow();
        uic.clip_damage = win_rect;
        uic.beginPass(.paint, arena.allocator(), surface.canvas(), win_rect, 40, 40, false, false, false);
        _ = uic.codeEditor("lang_test_ed", 600, 240, &ed_buf, .{ .language = entry.lang });
        uic.endPass();
    }
}

test "CodeEditor: LSP autocomplete popup keyboard navigation (Up/Down/Tab/Escape) and Supercomplete ghost-text acceptance" {
    var ed_buf = CodeEditorBuffer(512).initFromSlice("std::vec");
    defer ed_buf.deinit();
    ed_buf.cursor = ed_buf.len;
    ed_buf.selection_anchor = ed_buf.len;

    const surface = try skia.Surface.initRasterN32Premul(600, 260);
    defer surface.deinit();
    const paint = try skia.Paint.init();
    defer paint.deinit();
    const font = try Font.init(null, 12.0);
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
    const win_rect = Rect.xywh(0, 0, 600, 260);
    uic.focused_id = uic.resolveIdAndLabel("comp_test_ed").wid;

    const popup_items = [_]CompletionPopupItem{
        .{ .label = "vector", .detail = "std::vector<T>", .insert_text = "vector<", .kind = 2, .replace_prefix_len = 3 },
        .{ .label = "variant", .detail = "std::variant<Ts...>", .insert_text = "variant<", .kind = 2, .replace_prefix_len = 3 },
    };

    // 1. Down arrow moves selection from 0 -> 1
    const down_key = [_]platform.KeyEvent{.{ .key = .down }};
    uic.key_events = &down_key;
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 40, 40, false, false, false);
    const res1 = uic.codeEditor("comp_test_ed", 600, 260, &ed_buf, .{
        .language = .cpp,
        .completions = &popup_items,
        .selected_completion = 0,
    });
    uic.endPass();
    try std.testing.expect(res1.completion_selection_changed);
    try std.testing.expectEqual(@as(usize, 1), res1.selected_completion);

    // 2. Tab accepts selected completion item
    const tab_key = [_]platform.KeyEvent{.{ .key = .tab }};
    uic.key_events = &tab_key;
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 40, 40, false, false, false);
    const res2 = uic.codeEditor("comp_test_ed", 600, 260, &ed_buf, .{
        .language = .cpp,
        .completions = &popup_items,
        .selected_completion = 1,
    });
    uic.endPass();
    try std.testing.expect(res2.completion_accepted);

    // 3. Escape dismisses autocomplete popup
    const esc_key = [_]platform.KeyEvent{.{ .key = .escape }};
    uic.key_events = &esc_key;
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 40, 40, false, false, false);
    const res3 = uic.codeEditor("comp_test_ed", 600, 260, &ed_buf, .{
        .language = .cpp,
        .completions = &popup_items,
        .selected_completion = 0,
    });
    uic.endPass();
    try std.testing.expect(res3.completion_dismissed);

    // 4. Supercomplete inline ghost-text acceptance via Tab when popup is closed
    uic.key_events = &tab_key;
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 40, 40, false, false, false);
    const res4 = uic.codeEditor("comp_test_ed", 600, 260, &ed_buf, .{
        .language = .cpp,
        .ghost_text = "int>(16);",
    });
    uic.endPass();
    try std.testing.expect(res4.ghost_accepted);
}

test "CodeEditorBuffer Fuzzer: 600 random edits, UTF-8/emoji grapheme invariants, O(log L) line-index vs ground-truth scan, and undo/redo" {
    var ed = CodeEditorBuffer(2048).initFromSlice("pub fn start() void {\n    const x = 1;\n}\n");
    defer ed.deinit();

    var prng = std.Random.DefaultPrng.init(0x2026_1020_BEEF_CAFE);
    const rand = prng.random();

    const snippets = [_][]const u8{
        "a",
        "\n",
        "    if (ok) {\n        return true;\n    }\n",
        "🚀",
        "👨‍👩‍👧‍👦",
        "std::vector<int> v;\n",
        "// comment line\n",
        "{}",
        "()",
        "\t",
    };

    for (0..600) |_| {
        const op = rand.uintLessThan(u8, 12);
        switch (op) {
            0, 1, 2 => {
                const snip = snippets[rand.uintLessThan(usize, snippets.len)];
                _ = ed.insertText(snip, true);
            },
            3 => _ = ed.deleteBackward(rand.boolean(), false, 4),
            4 => _ = ed.deleteForward(rand.boolean()),
            5 => {
                if (rand.boolean()) {
                    _ = ed.indentOrInsertTab(4);
                } else {
                    _ = ed.outdentSelection(4);
                }
            },
            6 => _ = ed.toggleLineComment("// "),
            7 => _ = ed.duplicateCurrentLine(),
            8 => {
                if (ed.len > 0) {
                    const raw_c = rand.uintLessThan(usize, ed.len + 1);
                    const raw_a = rand.uintLessThan(usize, ed.len + 1);
                    ed.cursor = snapToGraphemeBoundary(ed.slice(), raw_c);
                    ed.selection_anchor = snapToGraphemeBoundary(ed.slice(), raw_a);
                }
            },
            9 => ed.moveLeft(rand.boolean(), rand.boolean(), rand.boolean()),
            10 => ed.moveRight(rand.boolean(), rand.boolean(), rand.boolean()),
            11 => {
                if (rand.boolean()) {
                    _ = ed.undo();
                } else {
                    _ = ed.redo();
                }
            },
            else => {},
        }

        // Invariant 1: cursor and selection_anchor within bounds and on valid UTF-8 grapheme boundaries
        const text = ed.slice();
        try std.testing.expect(ed.cursor <= text.len);
        try std.testing.expect(ed.selection_anchor <= text.len);
        try std.testing.expectEqual(ed.cursor, snapToGraphemeBoundary(text, ed.cursor));
        try std.testing.expectEqual(ed.selection_anchor, snapToGraphemeBoundary(text, ed.selection_anchor));

        // Invariant 2: O(log L) offsetToLineCol matches ground-truth linear scan at cursor, anchor, and end
        const check_offsets = [_]usize{ 0, ed.cursor, ed.selection_anchor, text.len };
        for (check_offsets) |off| {
            var gt_line: usize = 0;
            var gt_col: usize = 0;
            for (text[0..off]) |b| {
                if (b == '\n') {
                    gt_line += 1;
                    gt_col = 0;
                } else {
                    gt_col += 1;
                }
            }
            const indexed = ed.offsetToLineCol(off);
            try std.testing.expectEqual(gt_line, indexed.line);
            try std.testing.expectEqual(gt_col, indexed.col);
        }

        // Invariant 3: lineCount() and lineRangeByIndex() match ground-truth newline splits
        var line_idx: usize = 0;
        var it = std.mem.splitScalar(u8, text, '\n');
        var byte_pos: usize = 0;
        while (it.next()) |gt_slice| : (line_idx += 1) {
            const lr = ed.lineRangeByIndex(line_idx);
            try std.testing.expectEqual(byte_pos, lr.start);
            try std.testing.expectEqual(byte_pos + gt_slice.len, lr.end);
            byte_pos += gt_slice.len + 1;
        }
        try std.testing.expectEqual(line_idx, ed.lineCount());
    }

    // Invariant 4: Drain undo() N steps and re-apply redo() N steps -> exact final state restored
    const final_copy = try std.testing.allocator.dupe(u8, ed.slice());
    defer std.testing.allocator.free(final_copy);
    const final_cursor = ed.cursor;

    var undone_steps: usize = 0;
    while (undone_steps < 16 and ed.undo()) : (undone_steps += 1) {}
    for (0..undone_steps) |_| {
        try std.testing.expect(ed.redo());
    }
    try std.testing.expectEqualStrings(final_copy, ed.slice());
    try std.testing.expectEqual(final_cursor, ed.cursor);
}

test "CodeEditor: clickable breakpoint gutter to the left of line numbers, F9 toggle, and active debug line 2-phase rendering" {
    var ed_buf = CodeEditorBuffer(512).initFromSlice("fn main() void {\n    const a = 1;\n    const b = 2;\n}\n");
    defer ed_buf.deinit();

    const surface = try skia.Surface.initRasterN32Premul(600, 240);
    defer surface.deinit();
    const paint = try skia.Paint.init();
    defer paint.deinit();
    const font = try Font.init(null, 13.0);
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
    const win_rect = Rect.xywh(0, 0, 600, 240);

    // 0. When `show_breakpoint_gutter` is false (default for file types without a debugger),
    // clicking at x = 8 selects the line instead of toggling a breakpoint.
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 8.0, 36.0, true, true, false);
    const res0 = uic.codeEditor("bp_test_ed", 600, 240, &ed_buf, .{ .show_breakpoint_gutter = false });
    uic.endPass();
    try std.testing.expectEqual(@as(?u32, null), res0.toggled_breakpoint_line);
    try std.testing.expect(!ed_buf.hasBreakpoint(2));
    try std.testing.expect(ed_buf.hasSelection());
    ed_buf.selection_anchor = ed_buf.cursor;

    // 1. Click in the breakpoint margin to the left of line numbers when `show_breakpoint_gutter = true`
    // (x = 8 < BreakpointGutterWidth = 20, y = 36 -> line 2)
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 8.0, 36.0, true, true, false);
    const res1 = uic.codeEditor("bp_test_ed", 600, 240, &ed_buf, .{ .show_breakpoint_gutter = true });
    uic.endPass();
    try std.testing.expectEqual(@as(?u32, 2), res1.toggled_breakpoint_line);
    try std.testing.expect(ed_buf.hasBreakpoint(2));
    try std.testing.expect(!ed_buf.hasSelection());

    // Paint pass with breakpoint on line 2 and active debug line on line 2
    uic.invalidateWindow();
    uic.clip_damage = win_rect;
    uic.beginPass(.paint, arena.allocator(), surface.canvas(), win_rect, 8.0, 36.0, false, false, false);
    _ = uic.codeEditor("bp_test_ed", 600, 240, &ed_buf, .{ .show_breakpoint_gutter = true, .active_debug_line = 2, .show_minimap = true });
    uic.endPass();

    // 2. Click on the line number digits (x = 35, between 20 and 60) -> selects line 2 without toggling breakpoint
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 35.0, 36.0, true, true, false);
    const res2 = uic.codeEditor("bp_test_ed", 600, 240, &ed_buf, .{ .show_breakpoint_gutter = true });
    uic.endPass();
    try std.testing.expectEqual(@as(?u32, null), res2.toggled_breakpoint_line);
    try std.testing.expect(ed_buf.hasBreakpoint(2));
    try std.testing.expect(ed_buf.hasSelection());

    // 3. Click again in the breakpoint margin on line 2 (x = 8, y = 36) -> clears breakpoint on line 2
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 8.0, 36.0, true, true, false);
    const res3 = uic.codeEditor("bp_test_ed", 600, 240, &ed_buf, .{ .show_breakpoint_gutter = true });
    uic.endPass();
    try std.testing.expectEqual(@as(?u32, 2), res3.toggled_breakpoint_line);
    try std.testing.expect(!ed_buf.hasBreakpoint(2));

    // 4. Press F9 while focused -> toggles breakpoint on the current cursor line
    const f9_key = [_]platform.KeyEvent{.{ .key = .f9 }};
    uic.key_events = &f9_key;
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 100.0, 36.0, false, false, false);
    const res4 = uic.codeEditor("bp_test_ed", 600, 240, &ed_buf, .{ .show_breakpoint_gutter = true });
    uic.endPass();
    try std.testing.expect(res4.toggled_breakpoint_line != null);
    try std.testing.expect(ed_buf.hasBreakpoint(res4.toggled_breakpoint_line.?));
}

test "CodeEditor: Word wrap segmentation, multi-row line layout, and 2-phase determinism" {
    // 1. Unit test computeWrapSegments directly
    var seg_buf: [MaxWrapSegments]WrapSegment = undefined;

    // Empty line
    const empty_segs = computeWrapSegments("", 20, &seg_buf);
    try std.testing.expectEqual(@as(usize, 1), empty_segs.len);
    try std.testing.expectEqual(@as(usize, 0), empty_segs[0].start);
    try std.testing.expectEqual(@as(usize, 0), empty_segs[0].end);

    // Short line
    const short_line = "Hello world";
    const short_segs = computeWrapSegments(short_line, 20, &seg_buf);
    try std.testing.expectEqual(@as(usize, 1), short_segs.len);
    try std.testing.expectEqualStrings("Hello world", short_line[short_segs[0].start..short_segs[0].end]);

    // Space-delimited wrapping
    const prose = "The quick brown fox jumps over the lazy dog";
    const prose_segs = computeWrapSegments(prose, 16, &seg_buf);
    try std.testing.expect(prose_segs.len >= 3);
    // Verify contiguity across all segments
    try std.testing.expectEqual(@as(usize, 0), prose_segs[0].start);
    for (0..prose_segs.len - 1) |i| {
        try std.testing.expectEqual(prose_segs[i].end, prose_segs[i + 1].start);
    }
    try std.testing.expectEqual(prose.len, prose_segs[prose_segs.len - 1].end);

    // Continuous word with no spaces
    const long_word = "abcdefghijklmnopqrstuvwxyz0123456789";
    const word_segs = computeWrapSegments(long_word, 10, &seg_buf);
    try std.testing.expect(word_segs.len >= 4);
    for (0..word_segs.len - 1) |i| {
        try std.testing.expectEqual(word_segs[i].end, word_segs[i + 1].start);
        try std.testing.expect(word_segs[i].end - word_segs[i].start <= 10);
    }
    try std.testing.expectEqual(long_word.len, word_segs[word_segs.len - 1].end);

    // 2. Multi-line editor buffer with word wrap
    var ed_buf = CodeEditorBuffer(1024).initFromSlice(
        "Line 1 short\n" ++
            "Line 2 is extremely long and will definitely wrap across multiple sub-rows in the editor viewport!\n" ++
            "Line 3 short\n",
    );
    defer ed_buf.deinit();

    // Verify computeLineY and findLineAtY with word_wrap = true vs false
    const lh: f32 = 20.0;
    const max_chars: usize = 20;
    const y0 = computeLineY(&ed_buf, 0, lh, true, max_chars);
    try std.testing.expectEqual(@as(f32, 0.0), y0);

    const y1 = computeLineY(&ed_buf, 1, lh, true, max_chars);
    try std.testing.expectEqual(@as(f32, 20.0), y1);

    const y2 = computeLineY(&ed_buf, 2, lh, true, max_chars);
    // Line 1 is ~98 chars, wrapping into 5-6 segments at 20 chars per line, so y2 > 20.0 + 20.0
    try std.testing.expect(y2 >= 80.0);

    // findLineAtY
    try std.testing.expectEqual(@as(usize, 0), findLineAtY(&ed_buf, 10.0, lh, true, max_chars));
    try std.testing.expectEqual(@as(usize, 1), findLineAtY(&ed_buf, 35.0, lh, true, max_chars));
    try std.testing.expectEqual(@as(usize, 1), findLineAtY(&ed_buf, y2 - 5.0, lh, true, max_chars));
    try std.testing.expectEqual(@as(usize, 2), findLineAtY(&ed_buf, y2 + 5.0, lh, true, max_chars));

    // 3. 2-Phase rendering with word_wrap = true
    const surface = try skia.Surface.initRasterN32Premul(600, 300);
    defer surface.deinit();
    const paint = try skia.Paint.init();
    defer paint.deinit();
    const font = try Font.init(null, 12.0);
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
    const win_rect = Rect.xywh(0, 0, 600, 300);

    // Pass 1: Input pass
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 100.0, 50.0, true, true, false);
    const res_input = uic.codeEditor("wrap_ed_test", 600, 300, &ed_buf, .{
        .word_wrap = true,
        .line_height = lh,
        .show_line_numbers = true,
    });
    uic.endPass();
    try std.testing.expectEqual(@as(usize, 4), res_input.line_count);

    // Pass 2: Paint pass (must replay exactly identical layout without assertion or draw errors)
    uic.invalidateWindow();
    uic.clip_damage = win_rect;
    uic.beginPass(.paint, arena.allocator(), surface.canvas(), win_rect, 100.0, 50.0, false, false, false);
    const res_paint = uic.codeEditor("wrap_ed_test", 600, 300, &ed_buf, .{
        .word_wrap = true,
        .line_height = lh,
        .show_line_numbers = true,
    });
    uic.endPass();
    try std.testing.expectEqual(res_input.line_count, res_paint.line_count);
}

test "CodeEditor 2D buffer scrolling lightly snaps to dominant vertical or horizontal axis" {
    var ed_buf = CodeEditorBuffer(4096).initFromSlice("");
    defer ed_buf.deinit();

    // Populate 40 long lines so both vertical and horizontal scroll ranges exceed the viewport
    for (0..40) |_| {
        _ = ed_buf.insertText("pub fn exampleLongFunctionSignatureWithManyParametersAndReturnType(alpha: usize, beta: usize, gamma: usize) usize {\n", false);
    }
    ed_buf.scroll_to_cursor_pending = false;

    const surface = try skia.Surface.initRasterN32Premul(320, 180);
    defer surface.deinit();
    const paint = try skia.Paint.init();
    defer paint.deinit();
    const font = try Font.init(null, 12.0);
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
    const win_rect = Rect.xywh(0, 0, 320, 180);

    // Frame 0: Measure content_width and content_height (both passes)
    _ = arena.reset(.retain_capacity);
    uic.fallback_scroll_state = .{};
    uic.scroll_dx = 0;
    uic.scroll_dy = 0;
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 80.0, 60.0, false, false, false);
    _ = uic.codeEditor("snap_scroll_ed", 320, 180, &ed_buf, .{ .word_wrap = false });
    uic.endPass();
    uic.invalidateWindow();
    uic.clip_damage = win_rect;
    uic.beginPass(.paint, arena.allocator(), surface.canvas(), win_rect, 80.0, 60.0, false, false, false);
    _ = uic.codeEditor("snap_scroll_ed", 320, 180, &ed_buf, .{ .word_wrap = false });
    uic.endPass();
    try std.testing.expect(uic.fallback_scroll_state.content_width > 400.0);
    try std.testing.expect(uic.fallback_scroll_state.content_height > 400.0);

    // Frame 1: Vertical-dominant scroll (`dy = -30`, slight horizontal drift `dx = -8`) -> snaps purely to vertical (`scroll_x == 0`)
    _ = arena.reset(.retain_capacity);
    uic.scroll_dx = -8.0;
    uic.scroll_dy = -30.0;
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 80.0, 60.0, false, false, false);
    _ = uic.codeEditor("snap_scroll_ed", 320, 180, &ed_buf, .{ .word_wrap = false });
    uic.endPass();
    try std.testing.expectEqual(@as(f32, 0.0), uic.fallback_scroll_state.scroll_x);
    try std.testing.expectEqual(@as(f32, 30.0), uic.fallback_scroll_state.scroll_y);

    // Frame 2: Horizontal-dominant scroll (`dx = -35`, slight vertical drift `dy = -10`) -> snaps purely to horizontal (`scroll_y` unchanged at 30)
    _ = arena.reset(.retain_capacity);
    uic.scroll_dx = -35.0;
    uic.scroll_dy = -10.0;
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 80.0, 60.0, false, false, false);
    _ = uic.codeEditor("snap_scroll_ed", 320, 180, &ed_buf, .{ .word_wrap = false });
    uic.endPass();
    try std.testing.expectEqual(@as(f32, 35.0), uic.fallback_scroll_state.scroll_x);
    try std.testing.expectEqual(@as(f32, 30.0), uic.fallback_scroll_state.scroll_y);

    // Frame 3: Intentional 45-degree diagonal scroll (`dx = -25`, `dy = -25`) -> scrolls both axes
    _ = arena.reset(.retain_capacity);
    uic.scroll_dx = -25.0;
    uic.scroll_dy = -25.0;
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 80.0, 60.0, false, false, false);
    _ = uic.codeEditor("snap_scroll_ed", 320, 180, &ed_buf, .{ .word_wrap = false });
    uic.endPass();
    try std.testing.expectEqual(@as(f32, 60.0), uic.fallback_scroll_state.scroll_x);
    try std.testing.expectEqual(@as(f32, 55.0), uic.fallback_scroll_state.scroll_y);
}

test "CodeEditorBuffer: each buffer preserves its own independent scroll_x and scroll_y when switching buffers in the same pane" {
    const surface = try skia.Surface.initRasterN32Premul(400, 220);
    defer surface.deinit();
    const paint = try skia.Paint.init();
    defer paint.deinit();
    const font = try Font.init(null, 13.0);
    defer font.deinit();

    var store = platform.StateStore.init(std.testing.allocator);
    defer store.deinit();
    var snap = platform.SnapshotBuffer.init(std.testing.allocator);
    defer snap.deinit();
    var pctx = platform.PlatformContext{ .width = 400.0, .height = 220.0 };
    pctx.bindHostStores(&store, &snap);

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var uic = Context{
        .arena = arena.allocator(),
        .platform_ctx = &pctx,
        .canvas = surface.canvas(),
        .paint = paint,
        .font_title = font,
        .font_body = font,
        .font_mono = font,
    };
    defer uic.deinit();

    var buf_a = CodeEditorBuffer(8192){};
    defer buf_a.deinit();
    var buf_b = CodeEditorBuffer(8192){};
    defer buf_b.deinit();

    for (0..60) |_| {
        _ = buf_a.insertText("pub fn alpha_buffer_long_line_content() void {}\n", false);
        _ = buf_b.insertText("pub fn beta_buffer_long_line_content() void {}\n", false);
    }
    buf_a.cursor = 0;
    buf_a.selection_anchor = 0;
    buf_a.scroll_to_cursor_pending = false;
    buf_b.cursor = 0;
    buf_b.selection_anchor = 0;
    buf_b.scroll_to_cursor_pending = false;

    const win_rect = Rect.xywh(0, 0, 400, 220);

    // 1. Render buf_a via "workbench_code_editor_0" and scroll it to y = 120
    _ = arena.reset(.retain_capacity);
    pctx.scroll_dx = 0;
    pctx.scroll_dy = 0;
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 80.0, 60.0, false, false, false);
    _ = uic.codeEditor("workbench_code_editor_0", 380, 200, &buf_a, .{ .word_wrap = false });
    uic.endPass();

    pctx.scroll_dy = -120.0;
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 80.0, 60.0, false, false, false);
    _ = uic.codeEditor("workbench_code_editor_0", 380, 200, &buf_a, .{ .word_wrap = false });
    uic.endPass();
    uic.clip_damage = win_rect;
    uic.beginPass(.paint, arena.allocator(), surface.canvas(), win_rect, 80.0, 60.0, false, false, false);
    _ = uic.codeEditor("workbench_code_editor_0", 380, 200, &buf_a, .{ .word_wrap = false });
    uic.endPass();
    try std.testing.expectEqual(uic.last_input_rect_count, uic.last_paint_rect_count);
    try std.testing.expectEqual(@as(f32, 120.0), buf_a.scroll_state.scroll_y);

    // 2. Switch the same pane ("workbench_code_editor_0") to buf_b -> buf_b starts at scroll_y = 0, then scrolls to y = 45
    _ = arena.reset(.retain_capacity);
    pctx.scroll_dy = 0;
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 80.0, 60.0, false, false, false);
    _ = uic.codeEditor("workbench_code_editor_0", 380, 200, &buf_b, .{ .word_wrap = false });
    uic.endPass();
    try std.testing.expectEqual(@as(f32, 0.0), buf_b.scroll_state.scroll_y);
    try std.testing.expectEqual(@as(f32, 120.0), buf_a.scroll_state.scroll_y);

    pctx.scroll_dy = -45.0;
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 80.0, 60.0, false, false, false);
    _ = uic.codeEditor("workbench_code_editor_0", 380, 200, &buf_b, .{ .word_wrap = false });
    uic.endPass();
    uic.clip_damage = win_rect;
    uic.beginPass(.paint, arena.allocator(), surface.canvas(), win_rect, 80.0, 60.0, false, false, false);
    _ = uic.codeEditor("workbench_code_editor_0", 380, 200, &buf_b, .{ .word_wrap = false });
    uic.endPass();
    try std.testing.expectEqual(uic.last_input_rect_count, uic.last_paint_rect_count);
    try std.testing.expectEqual(@as(f32, 45.0), buf_b.scroll_state.scroll_y);
    try std.testing.expectEqual(@as(f32, 120.0), buf_a.scroll_state.scroll_y);

    // 3. Switch back to buf_a -> buf_a still has scroll_y == 120.0!
    _ = arena.reset(.retain_capacity);
    pctx.scroll_dy = 0;
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 80.0, 60.0, false, false, false);
    _ = uic.codeEditor("workbench_code_editor_0", 380, 200, &buf_a, .{ .word_wrap = false });
    uic.endPass();
    try std.testing.expectEqual(@as(f32, 120.0), buf_a.scroll_state.scroll_y);
    try std.testing.expectEqual(@as(f32, 45.0), buf_b.scroll_state.scroll_y);
}

test "CodeEditorBuffer.jumpToLineAndHighlight selects match, scrolls into view, and temporarily flashes target line" {
    const surface = try skia.Surface.initRasterN32Premul(420, 240);
    defer surface.deinit();
    const paint = try skia.Paint.init();
    defer paint.deinit();
    const font = try Font.init(null, 13.0);
    defer font.deinit();

    var store = platform.StateStore.init(std.testing.allocator);
    defer store.deinit();
    var snap = platform.SnapshotBuffer.init(std.testing.allocator);
    defer snap.deinit();
    var pctx = platform.PlatformContext{ .width = 420.0, .height = 240.0 };
    pctx.bindHostStores(&store, &snap);

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var uic = Context{
        .arena = arena.allocator(),
        .platform_ctx = &pctx,
        .canvas = surface.canvas(),
        .paint = paint,
        .font_title = font,
        .font_body = font,
        .font_mono = font,
    };
    defer uic.deinit();

    var buf = CodeEditorBuffer(8192){};
    defer buf.deinit();
    for (0..40) |idx| {
        if (idx == 24) {
            _ = buf.insertText("    const magic_target = 42;\n", false);
        } else {
            _ = buf.insertText("    const filler_line = 0;\n", false);
        }
    }
    buf.cursor = 0;
    buf.selection_anchor = 0;
    buf.scroll_to_cursor_pending = false;

    // Jump to 1-based line 25 and highlight "magic_target"
    buf.jumpToLineAndHighlight(25, "magic_target");
    try std.testing.expectEqual(@as(u32, 25), buf.flash_line);
    try std.testing.expectEqual(@as(u8, 45), buf.flash_frames);
    try std.testing.expect(buf.hasSelection());
    const sel = buf.selectionRange();
    try std.testing.expectEqualStrings("magic_target", buf.slice()[sel.start..sel.end]);

    const win_rect = Rect.xywh(0, 0, 400, 220);

    // Run input + paint pass: scroll position should jump to line 25 (index 24) and flash_frames should decrement by 1
    pctx.needs_continuous_redraw = false;
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 80.0, 60.0, false, false, false);
    _ = uic.codeEditor("flash_test_editor", 380, 200, &buf, .{ .word_wrap = false, .search_query = "magic_target" });
    uic.endPass();
    try std.testing.expect(pctx.needs_continuous_redraw);
    try std.testing.expect(uic.dirty_rect != null);
    try std.testing.expect(buf.scroll_state.scroll_y > 0.0);

    uic.clip_damage = win_rect;
    uic.beginPass(.paint, arena.allocator(), surface.canvas(), win_rect, 80.0, 60.0, false, false, false);
    _ = uic.codeEditor("flash_test_editor", 380, 200, &buf, .{ .word_wrap = false, .search_query = "magic_target" });
    uic.endPass();
    try std.testing.expectEqual(uic.last_input_rect_count, uic.last_paint_rect_count);
    try std.testing.expectEqual(@as(u8, 44), buf.flash_frames);
    try std.testing.expectEqual(@as(u32, 25), buf.flash_line);

    // Fast-forward remaining frames and verify flash_line clears to 0 when flash_frames hits 0
    buf.flash_frames = 1;
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 80.0, 60.0, false, false, false);
    _ = uic.codeEditor("flash_test_editor", 380, 200, &buf, .{ .word_wrap = false, .search_query = "magic_target" });
    uic.endPass();
    uic.clip_damage = win_rect;
    uic.beginPass(.paint, arena.allocator(), surface.canvas(), win_rect, 80.0, 60.0, false, false, false);
    _ = uic.codeEditor("flash_test_editor", 380, 200, &buf, .{ .word_wrap = false, .search_query = "magic_target" });
    uic.endPass();
    try std.testing.expectEqual(uic.last_input_rect_count, uic.last_paint_rect_count);
    try std.testing.expectEqual(@as(u8, 0), buf.flash_frames);
    try std.testing.expectEqual(@as(u32, 0), buf.flash_line);
}

test "CodeEditorBuffer: same buffer open in multiple split panes maintains independent scroll positions per split" {
    const surface = try skia.Surface.initRasterN32Premul(840, 260);
    defer surface.deinit();
    const paint = try skia.Paint.init();
    defer paint.deinit();
    const font = try Font.init(null, 13.0);
    defer font.deinit();

    var store = platform.StateStore.init(std.testing.allocator);
    defer store.deinit();
    var snap = platform.SnapshotBuffer.init(std.testing.allocator);
    defer snap.deinit();
    var pctx = platform.PlatformContext{ .width = 840.0, .height = 260.0 };
    pctx.bindHostStores(&store, &snap);

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var uic = Context{
        .arena = arena.allocator(),
        .platform_ctx = &pctx,
        .canvas = surface.canvas(),
        .paint = paint,
        .font_title = font,
        .font_body = font,
        .font_mono = font,
    };
    defer uic.deinit();

    var shared_buf = CodeEditorBuffer(8192){};
    defer shared_buf.deinit();
    for (0..60) |_| {
        _ = shared_buf.insertText("pub fn splitScrollLine() void { return; }\n", false);
    }
    shared_buf.cursor = 0;
    shared_buf.selection_anchor = 0;
    shared_buf.scroll_to_cursor_pending = false;

    const win_rect = Rect.xywh(0, 0, 840, 260);
    const renderTwoSplits = struct {
        fn run(u: *Context, b: *CodeEditorBuffer(8192), active_pane: usize) void {
            var r = u.row(.{ .h = .pixels(240.0), .gap = 4.0 });
            defer r.end();
            _ = u.codeEditor("workbench_code_editor_0", 400.0, 240.0, b, .{
                .word_wrap = false,
                .is_active_pane = (active_pane == 0),
                .pane_index = 0,
            });
            _ = u.codeEditor("workbench_code_editor_1", 400.0, 240.0, b, .{
                .word_wrap = false,
                .is_active_pane = (active_pane == 1),
                .pane_index = 1,
            });
        }
    }.run;

    // 1. Scroll Pane 0 (left split, x=100) down by 140px while Pane 1 (right split) remains at scroll_y = 0
    _ = arena.reset(.retain_capacity);
    pctx.scroll_dy = -140.0;
    pctx.scroll_dx = 0.0;
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 100.0, 100.0, false, false, false);
    renderTwoSplits(&uic, &shared_buf, 0);
    uic.endPass();
    uic.clip_damage = win_rect;
    uic.beginPass(.paint, arena.allocator(), surface.canvas(), win_rect, 100.0, 100.0, false, false, false);
    renderTwoSplits(&uic, &shared_buf, 0);
    uic.endPass();
    try std.testing.expectEqual(uic.last_input_rect_count, uic.last_paint_rect_count);
    try std.testing.expectEqual(@as(f32, 140.0), shared_buf.scrollStateForPane(0).scroll_y);
    try std.testing.expectEqual(@as(f32, 0.0), shared_buf.scrollStateForPane(1).scroll_y);

    // 2. Scroll Pane 1 (right split, x=520) down by 310px -> Pane 0 stays at 140.0, Pane 1 becomes 310.0
    _ = arena.reset(.retain_capacity);
    pctx.scroll_dy = -310.0;
    pctx.scroll_dx = 0.0;
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 520.0, 100.0, false, false, false);
    renderTwoSplits(&uic, &shared_buf, 1);
    uic.endPass();
    uic.clip_damage = win_rect;
    uic.beginPass(.paint, arena.allocator(), surface.canvas(), win_rect, 520.0, 100.0, false, false, false);
    renderTwoSplits(&uic, &shared_buf, 1);
    uic.endPass();
    try std.testing.expectEqual(uic.last_input_rect_count, uic.last_paint_rect_count);
    try std.testing.expectEqual(@as(f32, 140.0), shared_buf.scrollStateForPane(0).scroll_y);
    try std.testing.expectEqual(@as(f32, 310.0), shared_buf.scrollStateForPane(1).scroll_y);

    // 3. Jumping to line 50 while Pane 1 is the active pane only scrolls Pane 1, leaving Pane 0 at 140.0
    shared_buf.jumpToLine(50);
    _ = arena.reset(.retain_capacity);
    pctx.scroll_dy = 0.0;
    pctx.scroll_dx = 0.0;
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 520.0, 100.0, false, false, false);
    renderTwoSplits(&uic, &shared_buf, 1);
    uic.endPass();
    try std.testing.expectEqual(@as(f32, 140.0), shared_buf.scrollStateForPane(0).scroll_y);
    try std.testing.expect(shared_buf.scrollStateForPane(1).scroll_y > 600.0);
}



