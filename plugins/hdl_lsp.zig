//! Native Zig `.dylib` Editor Plugin: Hardware Description Languages — VHDL, Chisel (Scala), & DeviceTree (`plugins/hdl_lsp.zig`).
//!
//! Compiled into `zig-out/plugins/libhdl_lsp.dylib` (~159 KB, zero Skia linkage).
//!
//! Supports:
//!   - **VHDL (`.vhd`, `.vhdl`)**: `vhdl_ls` LSP + IEEE 1076 `entity`/`architecture`/`process` generators.
//!   - **Chisel 3 / Scala (`.scala`)**: `Module` / `IO(new Bundle)` / `RegInit` hardware generator.
//!   - **DeviceTree (`.dts`, `.dtsi`)**: SoC MMIO peripheral node, interrupt, and clock binding generator.

const std = @import("std");
const sdk = @import("plugin_sdk");

fn isHdlBuffer(buf: sdk.BufferInfo) bool {
    return sdk.lsp.LspLanguage.hdl.matchesPath(buf.file_path) or
        std.mem.indexOfPos(u8, buf.text, 0, "architecture ") != null or
        std.mem.indexOfPos(u8, buf.text, 0, "std_logic") != null or
        std.mem.indexOfPos(u8, buf.text, 0, "extends Module") != null or
        std.mem.indexOfPos(u8, buf.text, 0, "/dts-v1/;") != null;
}

const VHDL_ENTITY_SNIPPET =
    \\library ieee;
    \\use ieee.std_logic_1164.all;
    \\use ieee.numeric_std.all;
    \\
    \\entity sync_counter is
    \\    generic (
    \\        WIDTH : natural := 8
    \\    );
    \\    port (
    \\        clk     : in  std_logic;
    \\        rst_n   : in  std_logic;
    \\        en      : in  std_logic;
    \\        count_o : out std_logic_vector(WIDTH - 1 downto 0)
    \\    );
    \\end entity sync_counter;
    \\
    \\architecture rtl of sync_counter is
    \\    signal cnt_r : unsigned(WIDTH - 1 downto 0) := (others => '0');
    \\begin
    \\    process(clk, rst_n)
    \\    begin
    \\        if rst_n = '0' then
    \\            cnt_r <= (others => '0');
    \\        elsif rising_edge(clk) then
    \\            if en = '1' then
    \\                cnt_r <= cnt_r + 1;
    \\            end if;
    \\        end if;
    \\    end process;
    \\    count_o <= std_logic_vector(cnt_r);
    \\end architecture rtl;
    \\
;

const CHISEL_MODULE_SNIPPET =
    \\import chisel3._
    \\import chisel3.util._
    \\
    \\class AxiStreamCounter(width: Int = 8) extends Module {
    \\  val io = IO(new Bundle {
    \\    val enable = Input(Bool())
    \\    val valid  = Output(Bool())
    \\    val count  = Output(UInt(width.W))
    \\  })
    \\
    \\  val countReg = RegInit(0.U(width.W))
    \\  when(io.enable) {
    \\    countReg := countReg + 1.U
    \\  }
    \\  io.count := countReg
    \\  io.valid := io.enable
    \\}
    \\
;

const DEVICETREE_NODE_SNIPPET =
    \\/dts-v1/;
    \\
    \\/ {
    \\    compatible = "riscv,virt-soc";
    \\    #address-cells = <2>;
    \\    #size-cells = <2>;
    \\
    \\    soc {
    \\        compatible = "simple-bus";
    \\        #address-cells = <2>;
    \\        #size-cells = <2>;
    \\        ranges;
    \\
    \\        uart0: serial@10000000 {
    \\            compatible = "ns16550a";
    \\            reg = <0x0 0x10000000 0x0 0x100>;
    \\            clock-frequency = <3686400>;
    \\            status = "okay";
    \\        };
    \\    };
    \\};
    \\
;

comptime {
    sdk.exportLspLanguagePlugin(.{
        .id = "builtin.hdl_lsp",
        .display_name = "VHDL, Chisel & DeviceTree HDL",
        .version = "0.1.0",
        .sidebar_title = "HDL (VHDL / CHISEL / DTS)",
        .language = .hdl,
        .ready_status = "Ready (VHDL + Chisel + DeviceTree engine)",
        .is_buffer_match = isHdlBuffer,
        .commands = &.{
            .{
                .id = "hdl_lsp.insert_vhdl_entity",
                .title = "HDL (VHDL): Insert IEEE 1076 Entity & RTL Architecture",
                .category = "HDL / EDA",
                .hint = "VHDL",
                .snippet = VHDL_ENTITY_SNIPPET,
                .notice = "HDL: Inserted IEEE 1076 VHDL entity & RTL architecture",
                .btn_label = "+ VHDL##hdl_vhdl_btn",
                .btn_width = 78,
            },
            .{
                .id = "hdl_lsp.insert_chisel_module",
                .title = "HDL (Chisel 3): Insert Chisel Module & Decoupled IO Bundle",
                .category = "HDL / EDA",
                .hint = "Chisel",
                .snippet = CHISEL_MODULE_SNIPPET,
                .notice = "HDL: Inserted Chisel 3 Module & RegInit counter",
                .btn_label = "+ Chisel##hdl_ch_btn",
                .btn_width = 82,
            },
            .{
                .id = "hdl_lsp.insert_devicetree_node",
                .title = "HDL (DeviceTree): Insert SoC MMIO Peripheral .dts Node",
                .category = "HDL / EDA",
                .hint = "DTS",
                .snippet = DEVICETREE_NODE_SNIPPET,
                .notice = "HDL: Inserted DeviceTree (.dts) SoC peripheral node",
                .btn_label = "+ .dts##hdl_dts_btn",
                .btn_width = 76,
            },
        },
    });
}
