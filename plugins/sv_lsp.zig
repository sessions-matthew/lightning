//! Native Zig `.dylib` Editor Plugin: SystemVerilog (`slang`) Language Server & Digital Waveform Analyzer (`plugins/sv_lsp.zig`).
//!
//! Compiled into `zig-out/plugins/libsv_lsp.dylib` (~137 KB, zero Skia linkage).
//!
//! Features:
//!   - Spawns & communicates with `slang-server` / `svls` over non-blocking (`O_NONBLOCK`) JSON-RPC 2.0 stdio pipes
//!     (`initialize`, `textDocument/didOpen`, `didChange`, `didSave`, `textDocument/completion`, `publishDiagnostics`).
//!   - Built-in zero-allocation SystemVerilog (`slang` / IEEE 1800) lexical & RTL synthesis lint engine
//!     (detects blocking `=` in `always_ff`, non-blocking `<=` in `always_comb`, and unmatched `module`/`endmodule` or `begin`/`end`).
//!   - Interactive Hardware-Accelerated Digital Waveform & VCD Logic Analyzer (`ctx.ui.waveform(...)`)
//!     embedded in both the plugin sidebar and bottom panel.
//!   - SystemVerilog RTL Module & VCD Testbench code generators and `begin`/`end`-aware formatter.

const std = @import("std");
const sdk = @import("plugin_sdk");

fn isSvBuffer(buf: sdk.BufferInfo) bool {
    return sdk.lsp.LspLanguage.systemverilog.matchesPath(buf.file_path) or
        std.mem.indexOfPos(u8, buf.text, 0, "module ") != null or
        std.mem.indexOfPos(u8, buf.text, 0, "always_ff") != null or
        std.mem.indexOfPos(u8, buf.text, 0, "always_comb") != null or
        std.mem.indexOfPos(u8, buf.text, 0, "endmodule") != null;
}

fn formatSv(ctx: *sdk.PluginContext, text: []const u8) ?[]const u8 {
    return sdk.lsp.formatSvSource(ctx.allocator(), text, 4) catch null;
}

fn renderBottomPanel(ctx: *sdk.PluginContext) void {
    ctx.ui.waveform("sv_plugin_bottom_waveform", "", 195.0);
}

fn renderSidebarExtras(ctx: *sdk.PluginContext) void {
    if (ctx.ui.button("Open Waveform Preview to the Side##sv_open_wave_btn", 0, 26)) {
        ctx.openWaveformPreview("", true);
    }
}

const SV_MODULE_SNIPPET =
    \\`timescale 1ns / 1ps
    \\
    \\module axi_stream_counter #(
    \\    parameter int WIDTH = 8
    \\) (
    \\    input  logic             clk,
    \\    input  logic             rst_n,
    \\    input  logic             enable,
    \\    output logic             valid_o,
    \\    output logic [WIDTH-1:0] count_o
    \\);
    \\
    \\    always_ff @(posedge clk or negedge rst_n) begin
    \\        if (!rst_n) begin
    \\            count_o <= '0;
    \\            valid_o <= 1'b0;
    \\        end else if (enable) begin
    \\            count_o <= count_o + 1'b1;
    \\            valid_o <= 1'b1;
    \\        end else begin
    \\            valid_o <= 1'b0;
    \\        end
    \\    end
    \\
    \\endmodule
    \\
;

const SV_TB_SNIPPET =
    \\`timescale 1ns / 1ps
    \\
    \\module tb_axi_counter;
    \\    logic       clk = 1'b0;
    \\    logic       rst_n = 1'b0;
    \\    logic       enable = 1'b0;
    \\    logic       valid_o;
    \\    logic [7:0] count_o;
    \\
    \\    always #5 clk = ~clk;
    \\
    \\    initial begin
    \\        $dumpfile("counter_sim.vcd");
    \\        $dumpvars(0, tb_axi_counter);
    \\        #10 rst_n = 1'b1;
    \\        #10 enable = 1'b1;
    \\        #80 enable = 1'b0;
    \\        #20 $finish;
    \\    end
    \\endmodule
    \\
;

comptime {
    sdk.exportLspLanguagePlugin(.{
        .id = "builtin.sv_lsp",
        .display_name = "SystemVerilog (slang) & Waveform",
        .version = "0.1.0",
        .sidebar_title = "SYSTEMVERILOG (SLANG) & WAVEFORM",
        .bottom_tab_title = "SV WAVEFORM",
        .language = .systemverilog,
        .ready_status = "Ready (slang RTL + VCD engine)",
        .custom_format = formatSv,
        .format_label = "Format SV",
        .format_notice = "slang: Formatted SystemVerilog RTL buffer (IEEE 1800 style)",
        .is_buffer_match = isSvBuffer,
        .custom_render_sidebar = renderSidebarExtras,
        .render_bottom_panel = renderBottomPanel,
        .commands = &.{
            .{
                .id = "sv_lsp.insert_module",
                .title = "SystemVerilog (slang): Insert Synthesizable RTL Module & always_ff",
                .category = "SystemVerilog",
                .hint = "Module",
                .snippet = SV_MODULE_SNIPPET,
                .notice = "slang: Inserted synthesizable SystemVerilog module & always_ff",
                .btn_label = "+ Module##sv_mod_btn",
                .btn_width = 84,
            },
            .{
                .id = "sv_lsp.insert_testbench",
                .title = "SystemVerilog (slang): Insert VCD Testbench ($dumpfile / $dumpvars)",
                .category = "SystemVerilog",
                .hint = "VCD TB",
                .snippet = SV_TB_SNIPPET,
                .notice = "slang: Inserted SystemVerilog VCD testbench ($dumpfile / $dumpvars)",
                .btn_label = "+ VCD TB##sv_tb_btn",
                .btn_width = 84,
            },
        },
    });
}
