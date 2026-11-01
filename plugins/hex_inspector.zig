//! Native Zig `.dylib` Editor Plugin: Bitfield / Register Decoder & Hex Inspector (`plugins/hex_inspector.zig`).
//!
//! Features:
//!   - Interactive 32-bit CSR / Register Bitfield Decoder (`[31:24]`, `[23:16]`, `[15:8]`, `[7:0]`,
//!     hex/dec/signed/bin readout, endianness byte-swap, and hex/binary literal parsing from cursor).
//!   - Live Hex + ASCII memory dump around the active buffer cursor offset.

const std = @import("std");
const sdk = @import("plugin_sdk");

const HexInspectorState = struct {
    initialized: bool = false,
    reg_value: u32 = 0x8000_05A3,
    objdump_installed: bool = false,
    otool_installed: bool = false,
    last_status: sdk.InlineString(160) = .{},
};

fn probeBinary(name: []const u8) bool {
    const io = std.Options.debug_io;
    var child = std.process.spawn(io, .{
        .argv = &.{ "which", name },
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .ignore,
    }) catch return false;
    const term = child.wait(io) catch return false;
    return switch (term) {
        .exited => |code| code == 0,
        else => false,
    };
}

fn ensureInitialized(state: *HexInspectorState) void {
    if (state.initialized) return;
    state.initialized = true;
    state.objdump_installed = probeBinary("llvm-objdump") or probeBinary("objdump");
    state.otool_installed = probeBinary("otool");
}

fn isTokenChar(ch: u8) bool {
    return std.ascii.isAlphanumeric(ch) or ch == '_' or ch == '\'';
}

fn parseCursorLiteral(text: []const u8, cursor_offset: usize) ?u32 {
    if (text.len == 0) return null;
    const pos = @min(cursor_offset, text.len - 1);
    var start = pos;
    while (start > 0 and isTokenChar(text[start - 1])) : (start -= 1) {}
    var end = pos;
    while (end < text.len and isTokenChar(text[end])) : (end += 1) {}
    if (start >= end) return null;

    const raw = text[start..end];
    var clean_buf: [64]u8 = undefined;
    var clean_len: usize = 0;
    for (raw) |ch| {
        if (ch != '_' and clean_len < clean_buf.len) {
            clean_buf[clean_len] = ch;
            clean_len += 1;
        }
    }
    const tok = clean_buf[0..clean_len];
    if (std.mem.startsWith(u8, tok, "0x") or std.mem.startsWith(u8, tok, "0X")) {
        return std.fmt.parseInt(u32, tok[2..], 16) catch null;
    }
    if (std.mem.startsWith(u8, tok, "0b") or std.mem.startsWith(u8, tok, "0B")) {
        return std.fmt.parseInt(u32, tok[2..], 2) catch null;
    }
    if (std.mem.indexOfPos(u8, tok, 0, "'h")) |h_idx| {
        return std.fmt.parseInt(u32, tok[h_idx + 2 ..], 16) catch null;
    }
    if (std.mem.indexOfPos(u8, tok, 0, "'b")) |b_idx| {
        return std.fmt.parseInt(u32, tok[b_idx + 2 ..], 2) catch null;
    }
    return std.fmt.parseInt(u32, tok, 10) catch null;
}

fn registerCommands(ctx: *sdk.PluginContext) void {
    ctx.registerCommand(
        "hex_inspector.decode_cursor",
        "Hex & Bitfield: Decode Literal at Cursor into CSR Register",
        "Systems & Hardware",
        "Decode",
    );
    ctx.registerCommand(
        "hex_inspector.byte_swap",
        "Hex & Bitfield: Byte-Swap Register Endianness (bswap32)",
        "Systems & Hardware",
        "bswap32",
    );
    ctx.registerCommand(
        "hex_inspector.insert_hex_mask",
        "Hex & Bitfield: Insert Current 32-Bit Hex Literal",
        "Systems & Hardware",
        "0xHEX",
    );
}

fn onInit(ctx: *sdk.PluginContext) void {
    registerCommands(ctx);
    const st = ctx.useState(HexInspectorState, "state", .{});
    ensureInitialized(st);
}

fn onReload(ctx: *sdk.PluginContext) void {
    registerCommands(ctx);
}

fn onCommand(ctx: *sdk.PluginContext, cmd_id: []const u8) void {
    const st = ctx.useState(HexInspectorState, "state", .{});
    ensureInitialized(st);

    if (std.mem.eql(u8, cmd_id, "hex_inspector.decode_cursor")) {
        if (ctx.activeBuffer()) |buf| {
            if (parseCursorLiteral(buf.text, buf.cursor_offset)) |val| {
                st.reg_value = val;
                const msg = ctx.fmt("Decoded CSR value: 0x{X:0>8} ({d})", .{ val, val });
                st.last_status.set(msg);
                ctx.setStatusNotice(msg);
            } else if (buf.cursor_offset < buf.text.len) {
                var acc: u32 = 0;
                var i: usize = 0;
                while (i < 4 and buf.cursor_offset + i < buf.text.len) : (i += 1) {
                    acc = (acc << 8) | @as(u32, buf.text[buf.cursor_offset + i]);
                }
                st.reg_value = acc;
                st.last_status.set("Loaded 4 buffer bytes at cursor into CSR register");
                ctx.setStatusNotice("Hex Inspector: Loaded 4 buffer bytes at cursor");
            }
        }
    } else if (std.mem.eql(u8, cmd_id, "hex_inspector.byte_swap")) {
        st.reg_value = @byteSwap(st.reg_value);
        const msg = ctx.fmt("Byte-swapped register -> 0x{X:0>8}", .{st.reg_value});
        st.last_status.set(msg);
        ctx.setStatusNotice(msg);
    } else if (std.mem.eql(u8, cmd_id, "hex_inspector.insert_hex_mask")) {
        if (ctx.activeBuffer()) |buf| {
            const literal = ctx.fmt("0x{X:0>8}", .{st.reg_value});
            if (ctx.replaceBufferRange(buf.buffer_id, buf.cursor_offset, buf.cursor_offset, literal)) {
                st.last_status.set("Inserted 32-bit hex literal at cursor");
                ctx.setStatusNotice("Hex Inspector: Inserted 32-bit hex literal");
            }
        }
    }
}

fn renderStatusBar(ctx: *sdk.PluginContext) void {
    const st = ctx.useState(HexInspectorState, "state", .{});
    ensureInitialized(st);
    const label = ctx.fmt("CSR 0x{X:0>8}##hex_csr_chip", .{st.reg_value});
    if (ctx.ui.chip(label, false)) {
        onCommand(ctx, "hex_inspector.decode_cursor");
    }
}

fn renderSidebar(ctx: *sdk.PluginContext) void {
    const st = ctx.useState(HexInspectorState, "state", .{});
    ensureInitialized(st);

    ctx.ui.sectionLabel("32-BIT CSR BITFIELD & HEX INSPECTOR");
    const val = st.reg_value;
    const signed_val: i32 = @bitCast(val);
    const b3: u8 = @truncate(val >> 24);
    const b2: u8 = @truncate(val >> 16);
    const b1: u8 = @truncate(val >> 8);
    const b0: u8 = @truncate(val);

    ctx.ui.monoLabel(ctx.fmt("HEX: 0x{X:0>8}   UINT: {d}", .{ val, val }));
    ctx.ui.monoLabel(ctx.fmt("INT: {d}   DISASM: {s}", .{
        signed_val,
        if (st.otool_installed or st.objdump_installed) "READY" else "HEX",
    }));
    ctx.ui.monoLabel(ctx.fmt("BIN: {b:0>8}_{b:0>8}_{b:0>8}_{b:0>8}", .{ b3, b2, b1, b0 }));
    ctx.ui.monoLabel(ctx.fmt("[31:24]=0x{X:0>2} [23:16]=0x{X:0>2} [15:8]=0x{X:0>2} [7:0]=0x{X:0>2}", .{ b3, b2, b1, b0 }));

    if (ctx.ui.button("Decode Literal @ Cursor##hex_dec", 0, 26)) {
        onCommand(ctx, "hex_inspector.decode_cursor");
    }
    if (ctx.ui.button("Byte-Swap Endianness (bswap32)##hex_bswap", 0, 26)) {
        onCommand(ctx, "hex_inspector.byte_swap");
    }
    if (ctx.ui.button("Insert 0xHEX Literal##hex_ins", 0, 26)) {
        onCommand(ctx, "hex_inspector.insert_hex_mask");
    }

    if (ctx.activeBuffer()) |buf| {
        ctx.ui.sectionLabel("BUFFER HEX / ASCII (@ CURSOR)");
        const bytes = buf.text;
        const base_off = if (bytes.len > 0) @min(buf.cursor_offset & ~@as(usize, 0x7), bytes.len - 1) else 0;
        var row: usize = 0;
        while (row < 4) : (row += 1) {
            const row_off = base_off + row * 8;
            var line_buf: [96]u8 = undefined;
            var pos: usize = 0;
            const prefix = std.fmt.bufPrint(line_buf[pos..], "{X:0>4}: ", .{row_off}) catch "";
            pos += prefix.len;
            var col: usize = 0;
            while (col < 8) : (col += 1) {
                if (row_off + col < bytes.len) {
                    const h = std.fmt.bufPrint(line_buf[pos..], "{X:0>2} ", .{bytes[row_off + col]}) catch "";
                    pos += h.len;
                } else {
                    const pad = std.fmt.bufPrint(line_buf[pos..], "   ", .{}) catch "";
                    pos += pad.len;
                }
            }
            if (pos + 10 < line_buf.len) {
                line_buf[pos] = '|';
                pos += 1;
                col = 0;
                while (col < 8) : (col += 1) {
                    const ch: u8 = if (row_off + col < bytes.len) bytes[row_off + col] else ' ';
                    line_buf[pos] = if (ch >= 0x20 and ch <= 0x7E) ch else '.';
                    pos += 1;
                }
                line_buf[pos] = '|';
                pos += 1;
            }
            ctx.ui.monoLabel(line_buf[0..pos]);
        }
    }
}

comptime {
    sdk.exportEditorPlugin(.{
        .id = "builtin.hex_inspector",
        .display_name = "Bitfield & Hex Inspector",
        .version = "1.0.0",
        .sidebar_title = "HEX & BITFIELD",
        .sidebar_icon = .cpu,
        .init = onInit,
        .on_reload = onReload,
        .on_command = onCommand,
        .render_status_bar = renderStatusBar,
        .render_sidebar = renderSidebar,
    });
}
