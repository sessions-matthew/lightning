//! Reusable Application-Agnostic Command, Shortcut, and Fuzzy-Search Registry (`command_registry.zig`).
//!
//! Provides:
//!   - `Shortcut`: Declarative keyboard shortcut specification with `matches` and human-readable `format`.
//!   - `CommandEntry`: Generic comptime command specification struct parameterized on `IdType`, `CategoryType`, and `StateType`.
//!   - `indexOfIgnoreCasePos`, `containsIgnoreCase`, `fuzzyScore`: Fast zero-allocation ASCII case-insensitive and subsequence matching.
//!   - `matchesCommandQuery` & `scoreCommandMatch`: Multi-field command palette query matching and ranking (prefix, word-boundary, substring, subsequence).
//!   - `matchShortcutInTable`: Generic table-driven shortcut dispatcher.

const std = @import("std");
const platform = @import("platform");
const root = @import("root.zig");
pub const Context = root.Context;
pub const KeyCode = platform.KeyCode;
pub const KeyEvent = platform.KeyEvent;

/// Declarative keyboard shortcut specification for `Context.shortcut(...)` and command tables.
pub const Shortcut = struct {
    key: KeyCode,
    cmd: bool = false,
    ctrl: bool = false,
    alt: bool = false,
    shift: bool = false,
    cmd_or_ctrl: bool = false,

    /// Returns `true` when `ev` matches this shortcut's key and modifier combination.
    pub fn matches(self: Shortcut, ev: KeyEvent) bool {
        if (ev.key != self.key) return false;
        if (ev.alt != self.alt) return false;
        if (ev.shift != self.shift) return false;
        if (self.cmd_or_ctrl) {
            return (ev.cmd or ev.ctrl);
        }
        if (ev.cmd != self.cmd) return false;
        if (ev.ctrl != self.ctrl) return false;
        return true;
    }

    /// Formats this shortcut into a human-readable string (e.g. `"Shift+Cmd+P"`, `"Ctrl+Alt+S"`, `"Alt+Z"`, `"F5"`)
    /// inside caller-provided `buf` with zero heap allocations.
    pub fn format(self: Shortcut, buf: []u8) []const u8 {
        var pos: usize = 0;
        if (self.ctrl) {
            pos = appendSliceBounded(buf, pos, "Ctrl+");
        }
        if (self.alt) {
            pos = appendSliceBounded(buf, pos, "Alt+");
        }
        if (self.shift) {
            pos = appendSliceBounded(buf, pos, "Shift+");
        }
        if (self.cmd or self.cmd_or_ctrl) {
            pos = appendSliceBounded(buf, pos, "Cmd+");
        }
        pos = appendSliceBounded(buf, pos, keyCodeDisplayName(self.key));
        return buf[0..pos];
    }

    /// Parses a single shortcut specification string (e.g. `"cmd+shift+b"`, `"shift+cmd+p"`, `"ctrl+alt+s"`, `"f5"`, `"alt+z"`).
    /// Returns `null` if the string cannot be parsed into a valid key and modifiers.
    pub fn parse(str: []const u8) ?Shortcut {
        const trimmed = std.mem.trim(u8, str, " \t\r\n");
        if (trimmed.len == 0) return null;

        var cmd = false;
        var ctrl = false;
        var alt = false;
        var shift = false;
        var cmd_or_ctrl = false;
        var key_opt: ?KeyCode = null;

        var it = std.mem.tokenizeScalar(u8, trimmed, '+');
        while (it.next()) |token| {
            const tok = std.mem.trim(u8, token, " \t\r\n");
            if (tok.len == 0) continue;
            if (std.ascii.eqlIgnoreCase(tok, "cmd") or std.ascii.eqlIgnoreCase(tok, "command") or
                std.ascii.eqlIgnoreCase(tok, "meta") or std.ascii.eqlIgnoreCase(tok, "super") or
                std.ascii.eqlIgnoreCase(tok, "win"))
            {
                cmd = true;
            } else if (std.ascii.eqlIgnoreCase(tok, "ctrl") or std.ascii.eqlIgnoreCase(tok, "control")) {
                ctrl = true;
            } else if (std.ascii.eqlIgnoreCase(tok, "shift")) {
                shift = true;
            } else if (std.ascii.eqlIgnoreCase(tok, "alt") or std.ascii.eqlIgnoreCase(tok, "opt") or
                std.ascii.eqlIgnoreCase(tok, "option"))
            {
                alt = true;
            } else if (std.ascii.eqlIgnoreCase(tok, "cmdorctrl") or std.ascii.eqlIgnoreCase(tok, "ctrlcmd") or
                std.ascii.eqlIgnoreCase(tok, "primary"))
            {
                cmd_or_ctrl = true;
            } else {
                if (key_opt != null) return null;
                key_opt = parseKeyCode(tok);
                if (key_opt == null) return null;
            }
        }

        const key = key_opt orelse return null;
        return Shortcut{
            .key = key,
            .cmd = cmd,
            .ctrl = ctrl,
            .alt = alt,
            .shift = shift,
            .cmd_or_ctrl = cmd_or_ctrl,
        };
    }
};

/// A single shortcut or a two-step keyboard chord sequence (e.g. `"cmd+k cmd+s"`),
/// matching the standard VS Code keybinding chord specification.
pub const KeyChord = struct {
    first: Shortcut,
    second: ?Shortcut = null,

    pub fn init(first: Shortcut, second: ?Shortcut) KeyChord {
        return .{ .first = first, .second = second };
    }

    pub fn single(sc: Shortcut) KeyChord {
        return .{ .first = sc, .second = null };
    }

    /// Parses a VS Code-style keybinding string, supporting single shortcuts (e.g. `"shift+cmd+b"`)
    /// or space-separated chords (e.g. `"cmd+k cmd+s"`).
    pub fn parse(str: []const u8) ?KeyChord {
        const trimmed = std.mem.trim(u8, str, " \t\r\n");
        if (trimmed.len == 0) return null;

        var it = std.mem.tokenizeScalar(u8, trimmed, ' ');
        const first_str = it.next() orelse return null;
        const first_sc = Shortcut.parse(first_str) orelse return null;

        if (it.next()) |second_str| {
            const second_sc = Shortcut.parse(second_str) orelse return null;
            return KeyChord{ .first = first_sc, .second = second_sc };
        }

        return KeyChord{ .first = first_sc, .second = null };
    }

    pub fn isChord(self: KeyChord) bool {
        return self.second != null;
    }

    pub fn matchesFirst(self: KeyChord, ev: KeyEvent) bool {
        return self.first.matches(ev);
    }

    pub fn matchesSecond(self: KeyChord, ev: KeyEvent) bool {
        if (self.second) |sc2| {
            return sc2.matches(ev);
        }
        return false;
    }

    /// Formats the key chord into human-readable text (e.g. `"Shift+Cmd+B"` or `"Cmd+K Cmd+S"`).
    pub fn format(self: KeyChord, buf: []u8) []const u8 {
        var first_buf: [32]u8 = undefined;
        const first_str = self.first.format(&first_buf);
        if (self.second) |sc2| {
            var second_buf: [32]u8 = undefined;
            const second_str = sc2.format(&second_buf);
            return std.fmt.bufPrint(buf, "{s} {s}", .{ first_str, second_str }) catch first_str;
        } else {
            const copy_len = @min(buf.len, first_str.len);
            @memcpy(buf[0..copy_len], first_str[0..copy_len]);
            return buf[0..copy_len];
        }
    }
};

fn appendSliceBounded(buf: []u8, pos: usize, text: []const u8) usize {
    if (pos >= buf.len or text.len == 0) return pos;
    const avail = buf.len - pos;
    const copy_len = @min(avail, text.len);
    @memcpy(buf[pos .. pos + copy_len], text[0..copy_len]);
    return pos + copy_len;
}

/// Returns a concise human-readable keycap name for `key`.
pub fn keyCodeDisplayName(key: KeyCode) []const u8 {
    return switch (key) {
        .none => "",
        .left => "Left",
        .right => "Right",
        .up => "Up",
        .down => "Down",
        .home => "Home",
        .end => "End",
        .page_up => "PageUp",
        .page_down => "PageDown",
        .backspace => "Backspace",
        .delete_forward => "Delete",
        .enter => "Enter",
        .tab => "Tab",
        .escape => "Esc",
        .key_a => "A",
        .key_b => "B",
        .key_c => "C",
        .key_d => "D",
        .key_e => "E",
        .key_f => "F",
        .key_g => "G",
        .key_h => "H",
        .key_i => "I",
        .key_j => "J",
        .key_k => "K",
        .key_l => "L",
        .key_m => "M",
        .key_n => "N",
        .key_o => "O",
        .key_p => "P",
        .key_q => "Q",
        .key_r => "R",
        .key_s => "S",
        .key_t => "T",
        .key_u => "U",
        .key_v => "V",
        .key_w => "W",
        .key_x => "X",
        .key_y => "Y",
        .key_z => "Z",
        .key_0 => "0",
        .key_1 => "1",
        .key_2 => "2",
        .key_3 => "3",
        .key_4 => "4",
        .key_5 => "5",
        .key_6 => "6",
        .key_7 => "7",
        .key_8 => "8",
        .key_9 => "9",
        .key_backslash => "\\",
        .key_slash => "/",
        .key_lbracket => "[",
        .key_rbracket => "]",
        .key_minus => "-",
        .key_space => "Space",
        .f1 => "F1",
        .f2 => "F2",
        .f3 => "F3",
        .f4 => "F4",
        .f5 => "F5",
        .f6 => "F6",
        .f7 => "F7",
        .f8 => "F8",
        .f9 => "F9",
        .f10 => "F10",
        .f11 => "F11",
        .f12 => "F12",
    };
}

/// Parses a string representation of a key into a `KeyCode`.
/// Supports letters (`"a"`..`"z"`), digits (`"0"`..`"9"`), function keys (`"f1"`..`"f12"`),
/// special keys (`"enter"`, `"escape"`, `"tab"`, `"space"`, `"backspace"`, `"delete"`),
/// arrow keys, and punctuation.
pub fn parseKeyCode(name: []const u8) ?KeyCode {
    const s = std.mem.trim(u8, name, " \t\r\n");
    if (s.len == 0) return null;
    if (s.len == 1) {
        const ch = std.ascii.toLower(s[0]);
        return switch (ch) {
            'a' => .key_a,
            'b' => .key_b,
            'c' => .key_c,
            'd' => .key_d,
            'e' => .key_e,
            'f' => .key_f,
            'g' => .key_g,
            'h' => .key_h,
            'i' => .key_i,
            'j' => .key_j,
            'k' => .key_k,
            'l' => .key_l,
            'm' => .key_m,
            'n' => .key_n,
            'o' => .key_o,
            'p' => .key_p,
            'q' => .key_q,
            'r' => .key_r,
            's' => .key_s,
            't' => .key_t,
            'u' => .key_u,
            'v' => .key_v,
            'w' => .key_w,
            'x' => .key_x,
            'y' => .key_y,
            'z' => .key_z,
            '0' => .key_0,
            '1' => .key_1,
            '2' => .key_2,
            '3' => .key_3,
            '4' => .key_4,
            '5' => .key_5,
            '6' => .key_6,
            '7' => .key_7,
            '8' => .key_8,
            '9' => .key_9,
            '\\' => .key_backslash,
            '/' => .key_slash,
            '[' => .key_lbracket,
            ']' => .key_rbracket,
            '-' => .key_minus,
            ' ' => .key_space,
            else => null,
        };
    }

    if (std.ascii.eqlIgnoreCase(s, "enter") or std.ascii.eqlIgnoreCase(s, "return")) return .enter;
    if (std.ascii.eqlIgnoreCase(s, "escape") or std.ascii.eqlIgnoreCase(s, "esc")) return .escape;
    if (std.ascii.eqlIgnoreCase(s, "tab")) return .tab;
    if (std.ascii.eqlIgnoreCase(s, "space") or std.ascii.eqlIgnoreCase(s, "spacebar")) return .key_space;
    if (std.ascii.eqlIgnoreCase(s, "backspace") or std.ascii.eqlIgnoreCase(s, "bksp")) return .backspace;
    if (std.ascii.eqlIgnoreCase(s, "delete") or std.ascii.eqlIgnoreCase(s, "del")) return .delete_forward;
    if (std.ascii.eqlIgnoreCase(s, "left")) return .left;
    if (std.ascii.eqlIgnoreCase(s, "right")) return .right;
    if (std.ascii.eqlIgnoreCase(s, "up")) return .up;
    if (std.ascii.eqlIgnoreCase(s, "down")) return .down;
    if (std.ascii.eqlIgnoreCase(s, "home")) return .home;
    if (std.ascii.eqlIgnoreCase(s, "end")) return .end;
    if (std.ascii.eqlIgnoreCase(s, "pageup") or std.ascii.eqlIgnoreCase(s, "page_up")) return .page_up;
    if (std.ascii.eqlIgnoreCase(s, "pagedown") or std.ascii.eqlIgnoreCase(s, "page_down")) return .page_down;
    if (std.ascii.eqlIgnoreCase(s, "backslash")) return .key_backslash;
    if (std.ascii.eqlIgnoreCase(s, "slash")) return .key_slash;
    if (std.ascii.eqlIgnoreCase(s, "lbracket") or std.ascii.eqlIgnoreCase(s, "bracketleft")) return .key_lbracket;
    if (std.ascii.eqlIgnoreCase(s, "rbracket") or std.ascii.eqlIgnoreCase(s, "bracketright")) return .key_rbracket;
    if (std.ascii.eqlIgnoreCase(s, "minus")) return .key_minus;
    if (std.ascii.eqlIgnoreCase(s, "f1")) return .f1;
    if (std.ascii.eqlIgnoreCase(s, "f2")) return .f2;
    if (std.ascii.eqlIgnoreCase(s, "f3")) return .f3;
    if (std.ascii.eqlIgnoreCase(s, "f4")) return .f4;
    if (std.ascii.eqlIgnoreCase(s, "f5")) return .f5;
    if (std.ascii.eqlIgnoreCase(s, "f6")) return .f6;
    if (std.ascii.eqlIgnoreCase(s, "f7")) return .f7;
    if (std.ascii.eqlIgnoreCase(s, "f8")) return .f8;
    if (std.ascii.eqlIgnoreCase(s, "f9")) return .f9;
    if (std.ascii.eqlIgnoreCase(s, "f10")) return .f10;
    if (std.ascii.eqlIgnoreCase(s, "f11")) return .f11;
    if (std.ascii.eqlIgnoreCase(s, "f12")) return .f12;

    return null;
}

/// Generic comptime command specification struct for building application command registries and palettes.
pub fn CommandEntry(comptime IdType: type, comptime CategoryType: type, comptime StateType: type) type {
    return struct {
        id: IdType,
        title: []const u8,
        category: CategoryType,
        shortcut_label: []const u8 = "",
        shortcut: ?Shortcut = null,
        handler: ?*const fn (state: *StateType, uic: *Context) void = null,
    };
}

/// Finds the first command entry in `table` whose `.shortcut` matches `ev` and returns its index.
pub fn matchShortcutInTable(comptime CmdT: type, table: []const CmdT, ev: KeyEvent) ?usize {
    for (table, 0..) |entry, idx| {
        const sc_field = entry.shortcut;
        const sc_type_info = @typeInfo(@TypeOf(sc_field));
        if (sc_type_info == .optional) {
            if (sc_field) |sc| {
                if (sc.matches(ev)) return idx;
            }
        } else {
            if (sc_field.matches(ev)) return idx;
        }
    }
    return null;
}

/// Returns the first byte index `>= start_index` where `needle` occurs case-insensitively in `haystack`.
/// Uses a fast first-character lower/upper reject before checking remaining bytes.
pub fn indexOfIgnoreCasePos(haystack: []const u8, start_index: usize, needle: []const u8) ?usize {
    if (needle.len == 0 or start_index + needle.len > haystack.len) return null;
    const first_low = std.ascii.toLower(needle[0]);
    const first_up = std.ascii.toUpper(needle[0]);
    const tail = needle[1..];
    const limit = haystack.len - needle.len;
    var i: usize = start_index;
    while (i <= limit) : (i += 1) {
        const ch = haystack[i];
        if (ch == first_low or ch == first_up) {
            if (tail.len == 0 or std.ascii.eqlIgnoreCase(haystack[i + 1 .. i + needle.len], tail)) {
                return i;
            }
        }
    }
    return null;
}

/// Case-insensitive ASCII substring search helper across the UI toolkit and apps.
pub fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    return indexOfIgnoreCasePos(haystack, 0, needle) != null;
}

fn isWordBoundaryChar(ch: u8) bool {
    return ch == '/' or ch == '_' or ch == '-' or ch == '.' or ch == ' ' or ch == ':' or ch == '+';
}

/// Computes a fuzzy subsequence match score (`?i32`) for `query` against `candidate`.
/// Returns `null` if not all non-space characters of `query` appear in order in `candidate`.
/// Awards bonuses for consecutive character runs, word-boundary hits (`/`, `_`, `.`, `-`, `:`, space, camelCase),
/// and early matches.
pub fn fuzzyScore(candidate: []const u8, query: []const u8) ?i32 {
    const trimmed = std.mem.trim(u8, query, " \t");
    if (trimmed.len == 0) return 0;
    if (trimmed.len > candidate.len) return null;

    var score: i32 = 0;
    if (containsIgnoreCase(candidate, trimmed)) {
        score += 60;
    }

    var c_idx: usize = 0;
    var prev_match_idx: ?usize = null;

    for (trimmed) |q_ch| {
        if (q_ch == ' ') continue;
        const q_low = std.ascii.toLower(q_ch);
        var found = false;
        while (c_idx < candidate.len) : (c_idx += 1) {
            const c_ch = candidate[c_idx];
            if (std.ascii.toLower(c_ch) == q_low) {
                score += 10;
                if (c_idx == 0) {
                    score += 18;
                } else {
                    const prev_c = candidate[c_idx - 1];
                    if (isWordBoundaryChar(prev_c)) {
                        score += 15;
                    } else if (std.ascii.isLower(prev_c) and std.ascii.isUpper(c_ch)) {
                        score += 12;
                    }
                }
                if (prev_match_idx) |pm| {
                    if (c_idx == pm + 1) {
                        score += 14;
                    } else {
                        score -= @intCast(@min(@as(usize, 8), c_idx - pm - 1));
                    }
                }
                prev_match_idx = c_idx;
                c_idx += 1;
                found = true;
                break;
            }
        }
        if (!found) return null;
    }
    return score;
}

fn normalizeCommandQuery(raw_query: []const u8) []const u8 {
    var q = std.mem.trim(u8, raw_query, " \t");
    if (std.mem.startsWith(u8, q, ">")) {
        q = std.mem.trim(u8, q[1..], " \t");
    }
    return q;
}

/// Scores a command entry (`title`, `category_str`, `shortcut_label`) against `query`.
/// Ranks prefix matches highest, followed by word-boundary substring matches, general substring matches,
/// fuzzy subsequence matches across `title` or `category: title`, and shortcut matches.
/// Returns `null` if the command does not match `query`.
pub fn scoreCommandMatch(
    title: []const u8,
    category_str: []const u8,
    shortcut_label: []const u8,
    query: []const u8,
) ?i32 {
    const q = normalizeCommandQuery(query);
    if (q.len == 0) return 0;

    var best: ?i32 = null;

    // 1. Score against `title` directly
    if (fuzzyScore(title, q)) |title_sc| {
        var s = title_sc;
        if (title.len >= q.len and std.ascii.eqlIgnoreCase(title[0..q.len], q)) {
            // Exact case-insensitive prefix of title
            s += 100;
        } else if (indexOfIgnoreCasePos(title, 0, q)) |sub_pos| {
            // Substring match inside title: check if it starts on a word boundary (e.g. after "View: " or space)
            if (sub_pos == 0 or isWordBoundaryChar(title[sub_pos - 1])) {
                s += 55;
            } else {
                s += 20;
            }
        }
        best = s;
    }

    // 2. If `title` has a `"Category: Action"` prefix, also check prefix match on the action part after `": "`
    if (std.mem.indexOfPos(u8, title, 0, ": ")) |colon_pos| {
        const action_part = title[colon_pos + 2 ..];
        if (action_part.len >= q.len and std.ascii.eqlIgnoreCase(action_part[0..q.len], q)) {
            const action_sc = (fuzzyScore(action_part, q) orelse 0) + 90;
            best = if (best) |b| @max(b, action_sc) else action_sc;
        }
    }

    // 3. Score against `category_str` and `category_str: title` combined (for multi-word queries spanning category + title)
    if (category_str.len > 0) {
        if (fuzzyScore(category_str, q)) |cat_sc| {
            const weighted_cat = @divTrunc(cat_sc, 3);
            best = if (best) |b| @max(b, weighted_cat) else weighted_cat;
        } else if (!std.mem.startsWith(u8, title, category_str)) {
            var combined_buf: [256]u8 = undefined;
            var pos: usize = 0;
            pos = appendSliceBounded(&combined_buf, pos, category_str);
            pos = appendSliceBounded(&combined_buf, pos, ": ");
            pos = appendSliceBounded(&combined_buf, pos, title);
            const combined = combined_buf[0..pos];
            if (fuzzyScore(combined, q)) |comb_sc| {
                best = if (best) |b| @max(b, comb_sc) else comb_sc;
            }
        }
    }

    // 4. Score against `shortcut_label`
    if (shortcut_label.len > 0) {
        if (containsIgnoreCase(shortcut_label, q)) {
            const sc_score: i32 = if (std.ascii.eqlIgnoreCase(shortcut_label, q)) 95 else 45;
            best = if (best) |b| @max(b, sc_score) else sc_score;
        } else if (fuzzyScore(shortcut_label, q)) |sc_fuzzy| {
            const weighted_sc = sc_fuzzy - 20;
            best = if (best) |b| @max(b, weighted_sc) else weighted_sc;
        }
    }

    return best;
}

/// Returns `true` if a command (`title`, `category_str`, `shortcut_label`) matches `query`
/// via substring or fuzzy subsequence matching.
pub fn matchesCommandQuery(
    title: []const u8,
    category_str: []const u8,
    shortcut_label: []const u8,
    query: []const u8,
) bool {
    return scoreCommandMatch(title, category_str, shortcut_label, query) != null;
}

// ============================================================================
// Unit Tests
// ============================================================================

test "Shortcut.matches and Shortcut.format" {
    const cmd_shift_p = Shortcut{ .key = .key_p, .cmd = true, .shift = true };
    try std.testing.expect(cmd_shift_p.matches(.{ .key = .key_p, .cmd = true, .shift = true }));
    try std.testing.expect(!cmd_shift_p.matches(.{ .key = .key_p, .cmd = true, .shift = false }));
    try std.testing.expect(!cmd_shift_p.matches(.{ .key = .key_p, .ctrl = true, .shift = true }));
    try std.testing.expect(!cmd_shift_p.matches(.{ .key = .key_o, .cmd = true, .shift = true }));

    var fmt_buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("Shift+Cmd+P", cmd_shift_p.format(&fmt_buf));

    const ctrl_alt_s = Shortcut{ .key = .key_s, .ctrl = true, .alt = true };
    try std.testing.expect(ctrl_alt_s.matches(.{ .key = .key_s, .ctrl = true, .alt = true }));
    try std.testing.expect(!ctrl_alt_s.matches(.{ .key = .key_s, .cmd = true, .alt = true }));
    try std.testing.expectEqualStrings("Ctrl+Alt+S", ctrl_alt_s.format(&fmt_buf));

    const alt_z = Shortcut{ .key = .key_z, .alt = true };
    try std.testing.expect(alt_z.matches(.{ .key = .key_z, .alt = true }));
    try std.testing.expect(!alt_z.matches(.{ .key = .key_z }));
    try std.testing.expectEqualStrings("Alt+Z", alt_z.format(&fmt_buf));

    const bare_f5 = Shortcut{ .key = .f5 };
    try std.testing.expect(bare_f5.matches(.{ .key = .f5 }));
    try std.testing.expect(!bare_f5.matches(.{ .key = .f5, .shift = true }));
    try std.testing.expectEqualStrings("F5", bare_f5.format(&fmt_buf));
}

test "CommandEntry and matchShortcutInTable" {
    const TestId = enum { save, save_as, split_right, refresh };
    const TestCat = enum { file, view };
    const DummyState = struct { count: usize = 0 };
    const Entry = CommandEntry(TestId, TestCat, DummyState);

    const table = [_]Entry{
        .{
            .id = .save_as,
            .title = "Save As New File...",
            .category = .file,
            .shortcut_label = "Shift+Cmd+S",
            .shortcut = .{ .key = .key_s, .cmd = true, .shift = true },
        },
        .{
            .id = .save,
            .title = "Save Active File",
            .category = .file,
            .shortcut_label = "Cmd+S",
            .shortcut = .{ .key = .key_s, .cmd = true },
        },
        .{
            .id = .split_right,
            .title = "Split Editor Right",
            .category = .view,
            .shortcut_label = "Cmd+\\",
            .shortcut = .{ .key = .key_backslash, .cmd = true },
        },
        .{
            .id = .refresh,
            .title = "Refresh Explorer",
            .category = .view,
        },
    };

    try std.testing.expectEqual(@as(?usize, 0), matchShortcutInTable(Entry, &table, .{ .key = .key_s, .cmd = true, .shift = true }));
    try std.testing.expectEqual(@as(?usize, 1), matchShortcutInTable(Entry, &table, .{ .key = .key_s, .cmd = true }));
    try std.testing.expectEqual(@as(?usize, 2), matchShortcutInTable(Entry, &table, .{ .key = .key_backslash, .cmd = true }));
    try std.testing.expectEqual(@as(?usize, null), matchShortcutInTable(Entry, &table, .{ .key = .key_r, .cmd = true }));
}

test "matchesCommandQuery and scoreCommandMatch ranking" {
    // Empty or '>' query matches everything with score 0
    try std.testing.expect(matchesCommandQuery("File: Save Active File", "File", "Cmd+S", ""));
    try std.testing.expect(matchesCommandQuery("File: Save Active File", "File", "Cmd+S", "   >  "));
    try std.testing.expectEqual(@as(?i32, 0), scoreCommandMatch("File: Save Active File", "File", "Cmd+S", ""));

    // Matching by title, category, combined category+title, and shortcut label
    try std.testing.expect(matchesCommandQuery("Save Active File", "File", "Cmd+S", "save"));
    try std.testing.expect(matchesCommandQuery("Save Active File", "File", "Cmd+S", "file save"));
    try std.testing.expect(matchesCommandQuery("Save Active File", "File", "Cmd+S", "cmd+s"));
    try std.testing.expect(matchesCommandQuery("Toggle Word Wrap", "View", "Alt+Z", "twr"));
    try std.testing.expect(!matchesCommandQuery("Save Active File", "File", "Cmd+S", "nonexistent_xyz"));

    // Verify ranking order: prefix match > word-boundary match > fuzzy subsequence match > category-only match
    const prefix_score = scoreCommandMatch("Save Active File", "File", "Cmd+S", "Save").?;
    const word_boundary_score = scoreCommandMatch("Auto Save Settings", "File", "", "Save").?;
    const subsequence_score = scoreCommandMatch("Split Active View Editor", "View", "", "save").?;
    const category_only_score = scoreCommandMatch("Open Recent", "Save", "", "Save").?;

    try std.testing.expect(prefix_score > word_boundary_score);
    try std.testing.expect(word_boundary_score > subsequence_score);
    try std.testing.expect(subsequence_score > category_only_score);
}

test "Shortcut.parse and KeyChord.parse for VS Code keybindings" {
    // 1. Single shortcut parsing
    const sc_build = Shortcut.parse("command+shift+b").?;
    try std.testing.expectEqual(KeyCode.key_b, sc_build.key);
    try std.testing.expect(sc_build.cmd);
    try std.testing.expect(sc_build.shift);
    try std.testing.expect(!sc_build.alt);
    try std.testing.expect(!sc_build.ctrl);

    const sc_build2 = Shortcut.parse("shift+cmd+b").?;
    try std.testing.expectEqual(KeyCode.key_b, sc_build2.key);
    try std.testing.expect(sc_build2.cmd);
    try std.testing.expect(sc_build2.shift);

    const sc_ctrl_b = Shortcut.parse("ctrl+shift+b").?;
    try std.testing.expectEqual(KeyCode.key_b, sc_ctrl_b.key);
    try std.testing.expect(sc_ctrl_b.ctrl);
    try std.testing.expect(sc_ctrl_b.shift);
    try std.testing.expect(!sc_ctrl_b.cmd);

    const sc_f5 = Shortcut.parse("F5").?;
    try std.testing.expectEqual(KeyCode.f5, sc_f5.key);
    try std.testing.expect(!sc_f5.cmd);

    const sc_alt_z = Shortcut.parse("alt+z").?;
    try std.testing.expectEqual(KeyCode.key_z, sc_alt_z.key);
    try std.testing.expect(sc_alt_z.alt);

    // 2. Chords
    const chord_single = KeyChord.parse("cmd+shift+b").?;
    try std.testing.expect(!chord_single.isChord());
    var fmt_buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("Shift+Cmd+B", chord_single.format(&fmt_buf));

    const chord_seq = KeyChord.parse("cmd+k cmd+s").?;
    try std.testing.expect(chord_seq.isChord());
    try std.testing.expectEqual(KeyCode.key_k, chord_seq.first.key);
    try std.testing.expect(chord_seq.first.cmd);
    try std.testing.expectEqual(KeyCode.key_s, chord_seq.second.?.key);
    try std.testing.expect(chord_seq.second.?.cmd);
    try std.testing.expectEqualStrings("Cmd+K Cmd+S", chord_seq.format(&fmt_buf));

    // 3. parseKeyCode
    try std.testing.expectEqual(KeyCode.enter, parseKeyCode("enter").?);
    try std.testing.expectEqual(KeyCode.escape, parseKeyCode("esc").?);
    try std.testing.expectEqual(KeyCode.tab, parseKeyCode("tab").?);
    try std.testing.expectEqual(KeyCode.key_backslash, parseKeyCode("\\").?);
}
