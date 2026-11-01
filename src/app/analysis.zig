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
        std.mem.eql(u8, raw, "method") or
        std.mem.eql(u8, raw, "task"))
    {
        return "fn";
    }
    if (std.mem.eql(u8, raw, "struct") or
        std.mem.eql(u8, raw, "class") or
        std.mem.eql(u8, raw, "enum") or
        std.mem.eql(u8, raw, "type") or
        std.mem.eql(u8, raw, "interface") or
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
    return raw;
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

    const lsp_lang = toLspLanguage(language) orelse return 0;
    var lsp_syms: [128]lsp.LspSymbol = undefined;
    const lsp_count = lsp.scanSymbols(source, lsp_lang, "", &lsp_syms);
    const n = @min(lsp_count, out.len);
    for (0..n) |i| {
        const s = &lsp_syms[i];
        out[i] = .{
            .kind = normalizeKind(s.kind.slice()),
            .name = s.name.slice(),
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
    try std.testing.expectEqual(@as(usize, 3), n);
    try std.testing.expectEqualStrings("st", syms[0].kind);
    try std.testing.expectEqualStrings("Config", syms[0].name);
    try std.testing.expectEqual(@as(usize, 1), syms[0].line);
    try std.testing.expectEqualStrings("ct", syms[1].kind);
    try std.testing.expectEqualStrings("MAX_ITEMS", syms[1].name);
    try std.testing.expectEqualStrings("fn", syms[2].kind);
    try std.testing.expectEqualStrings("computeLayout", syms[2].name);

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
