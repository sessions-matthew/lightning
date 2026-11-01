//! Live Symbol Outline & Diagnostics Analysis for Editor Buffers.
//! Pure, zero-allocation scanners over source slices (`extractSymbols`, `scanDiagnosticsSource`).

const std = @import("std");
const ui = @import("ui");
const platform = @import("platform");
const lsp = platform.lsp;

pub const SymbolItem = struct {
    kind: []const u8,
    name: []const u8,
    line: usize,
};

pub const DiagnosticSeverity = enum {
    err,
    warn,
    info,
};

pub const DiagnosticItem = struct {
    file_idx: usize,
    line: usize,
    severity: DiagnosticSeverity,
    message: []const u8,
};

fn toLspLanguage(lang: ui.CodeLanguage) ?lsp.LspLanguage {
    return switch (lang) {
        .zig => .zig,
        .cpp => .cpp,
        .python => .python,
        .rust => .rust,
        .go => .go,
        .typescript => .typescript,
        .systemverilog => .systemverilog,
        .vhdl, .chisel, .devicetree => .hdl,
        .java => .java,
        else => null,
    };
}

fn normalizeKind(raw: []const u8) []const u8 {
    if (std.mem.eql(u8, raw, "fn") or
        std.mem.eql(u8, raw, "func") or
        std.mem.eql(u8, raw, "method") or
        std.mem.eql(u8, raw, "task") or
        std.mem.eql(u8, raw, "proc"))
    {
        return "fn";
    }
    if (std.mem.eql(u8, raw, "struct") or
        std.mem.eql(u8, raw, "class") or
        std.mem.eql(u8, raw, "enum") or
        std.mem.eql(u8, raw, "type") or
        std.mem.eql(u8, raw, "interface") or
        std.mem.eql(u8, raw, "iface") or
        std.mem.eql(u8, raw, "record") or
        std.mem.eql(u8, raw, "union") or
        std.mem.eql(u8, raw, "trait") or
        std.mem.eql(u8, raw, "impl") or
        std.mem.eql(u8, raw, "module") or
        std.mem.eql(u8, raw, "entity") or
        std.mem.eql(u8, raw, "arch") or
        std.mem.eql(u8, raw, "obj") or
        std.mem.eql(u8, raw, "node") or
        std.mem.eql(u8, raw, "ns") or
        std.mem.eql(u8, raw, "pkg") or
        std.mem.eql(u8, raw, "mod") or
        std.mem.eql(u8, raw, "st"))
    {
        return "st";
    }
    if (std.mem.eql(u8, raw, "const") or
        std.mem.eql(u8, raw, "var") or
        std.mem.eql(u8, raw, "val") or
        std.mem.eql(u8, raw, "sig") or
        std.mem.eql(u8, raw, "signal") or
        std.mem.eql(u8, raw, "param") or
        std.mem.eql(u8, raw, "macro") or
        std.mem.eql(u8, raw, "ct"))
    {
        return "ct";
    }
    return "st";
}

fn takeZigIdent(s: []const u8) []const u8 {
    var end: usize = 0;
    while (end < s.len and (std.ascii.isAlphanumeric(s[end]) or s[end] == '_')) : (end += 1) {}
    return s[0..end];
}

fn isZigTypeRhs(rhs: []const u8) bool {
    const trimmed = std.mem.trimStart(u8, rhs, " \t");
    const type_kw = [_][]const u8{
        "struct",
        "packed struct",
        "extern struct",
        "enum",
        "union",
        "packed union",
        "extern union",
        "error{",
        "error {",
        "opaque",
    };
    for (type_kw) |kw| {
        if (std.mem.startsWith(u8, trimmed, kw)) {
            const after = trimmed[kw.len..];
            if (after.len == 0 or !std.ascii.isAlphanumeric(after[0])) return true;
        }
    }
    return false;
}

fn isPlainImportAliasRhs(rhs: []const u8) bool {
    const trimmed = std.mem.trim(u8, rhs, " \t\r;");
    if (trimmed.len == 0) return true;
    if (std.mem.startsWith(u8, trimmed, "@import(") or std.mem.startsWith(u8, trimmed, "@cImport(")) return true;
    // Check if `trimmed` is a simple dotted module/member alias like `platform.lsp` or `state_mod.EditorState`
    var saw_dot = false;
    for (trimmed) |ch| {
        if (ch == '.') {
            saw_dot = true;
        } else if (!std.ascii.isAlphanumeric(ch) and ch != '_') {
            return false;
        }
    }
    return saw_dot;
}

fn extractZigSymbols(source: []const u8, out: []SymbolItem) usize {
    var count: usize = 0;
    var line_it = std.mem.splitScalar(u8, source, '\n');
    var line_num: usize = 1;

    while (line_it.next()) |raw_line| : (line_num += 1) {
        if (count >= out.len) break;
        const line_no_cr = std.mem.trimEnd(u8, raw_line, "\r");
        const line = std.mem.trimStart(u8, line_no_cr, " \t");
        if (line.len == 0 or std.mem.startsWith(u8, line, "//") or std.mem.startsWith(u8, line, "\\\\")) continue;
        const is_top_level = (line.len == line_no_cr.len);

        const fn_prefixes = [_][]const u8{
            "pub inline fn ",
            "pub fn ",
            "export fn ",
            "inline fn ",
            "fn ",
        };
        var matched_fn = false;
        for (fn_prefixes) |pfx| {
            if (std.mem.startsWith(u8, line, pfx)) {
                const ident = takeZigIdent(std.mem.trimStart(u8, line[pfx.len..], " \t"));
                if (ident.len > 0) {
                    out[count] = .{ .kind = "fn", .name = ident, .line = line_num };
                    count += 1;
                    matched_fn = true;
                }
                break;
            }
        }
        if (matched_fn) continue;

        const decl_prefixes = [_]struct { pfx: []const u8, is_pub: bool }{
            .{ .pfx = "pub const ", .is_pub = true },
            .{ .pfx = "pub var ", .is_pub = true },
            .{ .pfx = "const ", .is_pub = false },
            .{ .pfx = "var ", .is_pub = false },
        };
        for (decl_prefixes) |dp| {
            if (std.mem.startsWith(u8, line, dp.pfx)) {
                const rest = std.mem.trimStart(u8, line[dp.pfx.len..], " \t");
                const ident = takeZigIdent(rest);
                if (ident.len == 0) break;

                const after_ident = std.mem.trimStart(u8, rest[ident.len..], " \t");
                const eq_pos = std.mem.indexOfScalar(u8, after_ident, '=');
                const has_type_annot = (after_ident.len > 0 and after_ident[0] == ':');
                const rhs = if (eq_pos) |ep|
                    (if (ep + 1 < after_ident.len and after_ident[ep + 1] != '=') after_ident[ep + 1 ..] else "")
                else
                    "";

                if (isZigTypeRhs(rhs)) {
                    // Include public types, top-level types, and PascalCase container types (`const UndoSlot = struct`)
                    if (dp.is_pub or is_top_level or std.ascii.isUpper(ident[0])) {
                        out[count] = .{ .kind = "st", .name = ident, .line = line_num };
                        count += 1;
                    }
                    break;
                }

                // Skip `@import` bindings and local variables inside function bodies
                if (std.mem.indexOfPos(u8, rest, 0, "@import(") != null or
                    std.mem.indexOfPos(u8, rest, 0, "@cImport(") != null)
                {
                    break;
                }
                if (!dp.is_pub and !is_top_level) break;
                if (!dp.is_pub and !has_type_annot and isPlainImportAliasRhs(rhs)) break;

                out[count] = .{ .kind = "ct", .name = ident, .line = line_num };
                count += 1;
                break;
            }
        }
    }
    return count;
}

pub fn extractSymbols(source: []const u8, language: ui.CodeLanguage, out: []SymbolItem) usize {
    if (language == .markdown) {
        var count: usize = 0;
        var line_it = std.mem.splitScalar(u8, source, '\n');
        var line_num: usize = 1;
        while (line_it.next()) |raw_line| : (line_num += 1) {
            if (count >= out.len) break;
            const line = std.mem.trimStart(u8, raw_line, " \t");
            if (line.len == 0) continue;
            if (std.mem.startsWith(u8, line, "### ")) {
                out[count] = .{ .kind = "h3", .name = std.mem.trim(u8, line[4..], " \r"), .line = line_num };
                count += 1;
            } else if (std.mem.startsWith(u8, line, "## ")) {
                out[count] = .{ .kind = "h2", .name = std.mem.trim(u8, line[3..], " \r"), .line = line_num };
                count += 1;
            } else if (std.mem.startsWith(u8, line, "# ")) {
                out[count] = .{ .kind = "h1", .name = std.mem.trim(u8, line[2..], " \r"), .line = line_num };
                count += 1;
            }
        }
        return count;
    }

    if (language == .zig) {
        return extractZigSymbols(source, out);
    }

    const lsp_lang = toLspLanguage(language) orelse return 0;
    var lsp_syms: [128]lsp.LspSymbolSlice = undefined;
    const lsp_count = lsp.scanSymbolSlices(source, lsp_lang, "", &lsp_syms);
    const n = @min(lsp_count, out.len);
    for (0..n) |i| {
        const s = lsp_syms[i];
        out[i] = .{
            .kind = normalizeKind(s.kind),
            .name = s.name,
            .line = s.line,
        };
    }
    return n;
}

pub fn scanDiagnosticsSource(
    source: []const u8,
    lang: ui.CodeLanguage,
    file_idx: usize,
    out: []DiagnosticItem,
) usize {
    var count: usize = 0;
    var line_it = std.mem.splitScalar(u8, source, '\n');
    var line_num: usize = 1;
    var brace_depth: isize = 0;
    var last_open_brace_line: usize = 1;

    while (line_it.next()) |line| : (line_num += 1) {
        if (count >= out.len) break;

        if (std.mem.indexOfPos(u8, line, 0, "TODO") != null or std.mem.indexOfPos(u8, line, 0, "FIXME") != null) {
            out[count] = .{
                .file_idx = file_idx,
                .line = line_num,
                .severity = .info,
                .message = "TODO / FIXME note in source comment",
            };
            count += 1;
            if (count >= out.len) break;
        }

        if (lang == .zig or lang == .cpp or lang == .java or lang == .go or lang == .json) {
            var in_str = false;
            var idx: usize = 0;
            while (idx < line.len) : (idx += 1) {
                const ch = line[idx];
                if (!in_str and idx + 1 < line.len and ch == '/' and line[idx + 1] == '/') break;
                if (ch == '"' and (idx == 0 or line[idx - 1] != '\\')) {
                    in_str = !in_str;
                    continue;
                }
                if (in_str) continue;
                if (ch == '{') {
                    if (brace_depth == 0) last_open_brace_line = line_num;
                    brace_depth += 1;
                } else if (ch == '}') {
                    brace_depth -= 1;
                    if (brace_depth < 0 and count < out.len) {
                        out[count] = .{
                            .file_idx = file_idx,
                            .line = line_num,
                            .severity = .err,
                            .message = "Unmatched closing brace '}'",
                        };
                        count += 1;
                        brace_depth = 0;
                    }
                }
            }
        }
    }

    if (brace_depth > 0 and count < out.len) {
        out[count] = .{
            .file_idx = file_idx,
            .line = last_open_brace_line,
            .severity = .warn,
            .message = "Unclosed block brace '{' detected in buffer",
        };
        count += 1;
    }

    return count;
}

test "analysis: extractSymbols parses Zig and Markdown symbols" {
    const zig_src =
        \\pub const Config = struct {
        \\    enabled: bool = true,
        \\};
        \\const MAX_ITEMS: usize = 16;
        \\pub fn computeLayout(x: f32) void {
        \\    _ = x;
        \\}
    ;
    var syms: [8]SymbolItem = undefined;
    const n = extractSymbols(zig_src, .zig, &syms);

    // Clobber stack memory to ensure returned symbol slices never dangle into extractSymbols' stack frame
    const clobberStack = struct {
        noinline fn run() u8 {
            var scratch: [32768]u8 = @splat(0xAA);
            std.mem.doNotOptimizeAway(&scratch);
            return scratch[1234];
        }
    }.run;
    try std.testing.expectEqual(@as(u8, 0xAA), clobberStack());

    try std.testing.expectEqual(@as(usize, 3), n);
    try std.testing.expectEqualStrings("st", syms[0].kind);
    try std.testing.expectEqualStrings("Config", syms[0].name);
    try std.testing.expectEqual(@as(usize, 1), syms[0].line);
    try std.testing.expectEqualStrings("ct", syms[1].kind);
    try std.testing.expectEqualStrings("MAX_ITEMS", syms[1].name);
    try std.testing.expectEqualStrings("fn", syms[2].kind);
    try std.testing.expectEqualStrings("computeLayout", syms[2].name);
    for (syms[0..n]) |s| {
        const name_addr = @intFromPtr(s.name.ptr);
        const src_start = @intFromPtr(zig_src.ptr);
        const src_end = src_start + zig_src.len;
        try std.testing.expect(name_addr >= src_start and name_addr + s.name.len <= src_end);
    }

    const md_src = "# Overview\n## Architecture\n### Details\n";
    const md_n = extractSymbols(md_src, .markdown, &syms);
    try std.testing.expectEqual(@as(usize, 3), md_n);
    try std.testing.expectEqualStrings("h1", syms[0].kind);
    try std.testing.expectEqualStrings("Overview", syms[0].name);
}

test "analysis: scanDiagnosticsSource detects TODOs and unmatched braces" {
    const src =
        \\pub fn broken() void {
        \\    // TODO: fix brace
        \\    if (true) {
        \\}
    ;
    var diags: [8]DiagnosticItem = undefined;
    const n = scanDiagnosticsSource(src, .zig, 2, &diags);
    try std.testing.expectEqual(@as(usize, 2), n);
    try std.testing.expectEqual(DiagnosticSeverity.info, diags[0].severity);
    try std.testing.expectEqual(@as(usize, 2), diags[0].line);
    try std.testing.expectEqual(DiagnosticSeverity.warn, diags[1].severity);
    try std.testing.expectEqual(@as(usize, 1), diags[1].line);
}

test "analysis: extractSymbols for Rust, Python, TypeScript, SystemVerilog, VHDL, and Chisel" {
    var syms: [8]SymbolItem = undefined;

    const rust_src = "pub struct Engine {}\nimpl Engine {}\npub async fn serve() {}\n";
    const rust_n = extractSymbols(rust_src, .rust, &syms);
    try std.testing.expectEqual(@as(usize, 3), rust_n);
    try std.testing.expectEqualStrings("Engine", syms[0].name);
    try std.testing.expectEqualStrings("serve", syms[2].name);

    const py_src = "class WorkerPool:\n    def __init__(self):\n        pass\n    async def run_job(self):\n        pass\n";
    const py_n = extractSymbols(py_src, .python, &syms);
    try std.testing.expectEqual(@as(usize, 3), py_n);
    try std.testing.expectEqualStrings("WorkerPool", syms[0].name);
    try std.testing.expectEqualStrings("__init__", syms[1].name);
    try std.testing.expectEqualStrings("run_job", syms[2].name);

    const ts_src = "export interface ApiResponse {}\nexport async function fetchUser() {}\n";
    const ts_n = extractSymbols(ts_src, .typescript, &syms);
    try std.testing.expectEqual(@as(usize, 2), ts_n);
    try std.testing.expectEqualStrings("ApiResponse", syms[0].name);
    try std.testing.expectEqualStrings("fetchUser", syms[1].name);

    const vhdl_src = "entity fifo_ctrl is\nend entity;\narchitecture rtl of fifo_ctrl is\nbegin\nend architecture;\n";
    const vhdl_n = extractSymbols(vhdl_src, .vhdl, &syms);
    try std.testing.expectEqual(@as(usize, 2), vhdl_n);
    try std.testing.expectEqualStrings("fifo_ctrl", syms[0].name);
    try std.testing.expectEqualStrings("rtl", syms[1].name);

    const chisel_src = "class ArbiterUnit extends Module {}\nobject ArbiterMain {}\n";
    const chisel_n = extractSymbols(chisel_src, .chisel, &syms);
    try std.testing.expectEqual(@as(usize, 2), chisel_n);
    try std.testing.expectEqualStrings("ArbiterUnit", syms[0].name);
    try std.testing.expectEqualStrings("ArbiterMain", syms[1].name);
}
