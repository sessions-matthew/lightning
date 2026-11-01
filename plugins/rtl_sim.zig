//! Standalone Native `.dylib` Plugin: Digital Waveform & VCD Viewer (`librtl_sim.dylib`).
//!
//! Features:
//!   - **Native VCD Waveform Preview & Split Pane Integration**:
//!     Opens `.vcd` value-change dump files from the workspace in the `*Waveform Preview*` center
//!     editor buffer or side-by-side split pane, like `pdf_reader.zig`.
//!   - **Hot-Reload Safe (`StateStore`)**:
//!     All persistent state is stored in value-copied `sdk.InlineString` fields.

const std = @import("std");
const sdk = @import("plugin_sdk");

const WaveformViewerState = struct {
    initialized: bool = false,
    custom_path: sdk.InlineString(128) = .{},
    vcd_trace: sdk.InlineString(4096) = .{},
};

comptime {
    std.debug.assert(@sizeOf(WaveformViewerState) <= 8192);
}

fn getState(ctx: *sdk.PluginContext) *WaveformViewerState {
    const st = ctx.useState(WaveformViewerState, "state", .{});
    if (!st.initialized) {
        st.initialized = true;
    }
    return st;
}

fn registerCommands(ctx: *sdk.PluginContext) void {
    ctx.registerCommand(
        "rtl_sim.open_preview",
        "Waveform Viewer: Open Waveform Preview Buffer",
        "Waveform Viewer",
        "Waveform",
    );
    ctx.registerCommand(
        "rtl_sim.open_preview_side",
        "Waveform Viewer: Open Waveform Preview to the Side",
        "Waveform Viewer",
        "Split Wave",
    );
}

fn onInit(ctx: *sdk.PluginContext) void {
    _ = getState(ctx);
    registerCommands(ctx);
}

fn onReload(ctx: *sdk.PluginContext) void {
    _ = getState(ctx);
    registerCommands(ctx);
}

fn onBufferOpen(ctx: *sdk.PluginContext, info: sdk.BufferInfo) void {
    if (std.mem.endsWith(u8, info.file_path, ".vcd") or std.mem.endsWith(u8, info.file_path, ".VCD")) {
        const st = getState(ctx);
        st.custom_path.set(info.file_path);
        st.vcd_trace.set(info.text);
    }
}

fn onCommand(ctx: *sdk.PluginContext, cmd_id: []const u8) void {
    const st = getState(ctx);
    if (std.mem.eql(u8, cmd_id, "rtl_sim.open_preview")) {
        ctx.openWaveformPreview(st.vcd_trace.slice(), false);
    } else if (std.mem.eql(u8, cmd_id, "rtl_sim.open_preview_side")) {
        ctx.openWaveformPreview(st.vcd_trace.slice(), true);
    }
}

comptime {
    sdk.exportEditorPlugin(.{
        .id = "builtin.rtl_sim",
        .display_name = "Waveform & VCD Viewer",
        .version = "1.0.0",
        .sidebar_icon = .none,
        .sidebar_title = "",
        .bottom_tab_title = "",
        .init = &onInit,
        .on_reload = &onReload,
        .on_command = &onCommand,
        .on_buffer_open = &onBufferOpen,
    });
}
