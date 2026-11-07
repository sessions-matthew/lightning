//! Entry point for the native window host (`lightning` / `skia-window`).
//! Supports `--dylib <path>`, `--workspace <dir>` (or positional `<dir>`), and `--title <title>`
//! to launch either the main Editor (`zig-out/lib/libeditor_app.dylib` on macOS,
//! `zig-out/bin/editor_app.dll` on Windows) or any example plugin from any working directory.

const std = @import("std");
const platform = @import("platform");
const fs_util = platform.fs_util;

fn expandHomePath(arena: std.mem.Allocator, raw: []const u8) ![:0]const u8 {
    if (std.mem.startsWith(u8, raw, "~/") or std.mem.eql(u8, raw, "~")) {
        const home_opt = fs_util.getenv("HOME") orelse fs_util.getenv("USERPROFILE");
        if (home_opt) |home_z| {
            const home = std.mem.sliceTo(home_z, 0);
            const rest = if (raw.len > 1) raw[1..] else "";
            return std.fmt.allocPrintSentinel(arena, "{s}{s}", .{ home, rest }, 0);
        }
    }
    return std.fmt.allocPrintSentinel(arena, "{s}", .{raw}, 0);
}

/// Resolves `raw_dylib` to an absolute path so that running `skia-window` from any directory
/// (or switching workspaces at runtime via `chdir`) always finds and hot-reloads the `.dylib`/`.dll`.
fn resolveDylibAbsolutePath(arena: std.mem.Allocator, raw_dylib: []const u8) ![:0]const u8 {
    const expanded = try expandHomePath(arena, raw_dylib);

    // 1. Check relative to current working directory first
    var resolved_buf: [std.fs.max_path_bytes]u8 = undefined;
    if (fs_util.realpath(expanded.ptr, &resolved_buf)) |res_z| {
        if (fs_util.pathExistsOnDisk(res_z)) {
            return std.fmt.allocPrintSentinel(arena, "{s}", .{std.mem.sliceTo(res_z, 0)}, 0);
        }
    }

    // 2. Resolve relative to the running `skia-window` executable (`<exe_dir>/<basename>`, `<exe_dir>/../lib/<basename>`, or `<exe_dir>/../../<raw>`)
    var exe_buf: [std.fs.max_path_bytes]u8 = undefined;
    var exe_len: u32 = exe_buf.len;
    if (fs_util._NSGetExecutablePath(&exe_buf, &exe_len) == 0) {
        var exe_real_buf: [std.fs.max_path_bytes]u8 = undefined;
        const exe_slice = if (fs_util.realpath(@ptrCast(&exe_buf), &exe_real_buf)) |rz|
            std.mem.sliceTo(rz, 0)
        else
            std.mem.sliceTo(exe_buf[0..], 0);

        if (std.fs.path.dirname(exe_slice)) |exe_dir| {
            const base_name = std.fs.path.basename(raw_dylib);
            const cand_bin = try std.fmt.allocPrintSentinel(arena, "{s}/{s}", .{ exe_dir, base_name }, 0);
            if (fs_util.realpath(cand_bin.ptr, &resolved_buf)) |res_z| {
                if (fs_util.pathExistsOnDisk(res_z)) {
                    return std.fmt.allocPrintSentinel(arena, "{s}", .{std.mem.sliceTo(res_z, 0)}, 0);
                }
            }
            const cand_lib = try std.fmt.allocPrintSentinel(arena, "{s}/../lib/{s}", .{ exe_dir, base_name }, 0);
            if (fs_util.realpath(cand_lib.ptr, &resolved_buf)) |res_z| {
                if (fs_util.pathExistsOnDisk(res_z)) {
                    return std.fmt.allocPrintSentinel(arena, "{s}", .{std.mem.sliceTo(res_z, 0)}, 0);
                }
            }
            const cand_root = try std.fmt.allocPrintSentinel(arena, "{s}/../../{s}", .{ exe_dir, raw_dylib }, 0);
            if (fs_util.realpath(cand_root.ptr, &resolved_buf)) |res_z| {
                if (fs_util.pathExistsOnDisk(res_z)) {
                    return std.fmt.allocPrintSentinel(arena, "{s}", .{std.mem.sliceTo(res_z, 0)}, 0);
                }
            }
        }
    }

    return expanded;
}

fn isAllDigits(s: []const u8) bool {
    if (s.len == 0) return false;
    for (s) |ch| {
        if (ch < '0' or ch > '9') return false;
    }
    return true;
}

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    var dylib_raw: []const u8 = std.mem.sliceTo(fs_util.DefaultAppLibPath, 0);
    var workspace_arg: ?[]const u8 = null;
    var title: [:0]const u8 = "Lightning";
    var max_frames: ?usize = null;
    var bench: bool = false;
    var metrics_json_path: ?[]const u8 = null;
    var trace_path: ?[]const u8 = null;
    var scenario: ?[]const u8 = null;
    var screenshot_path: ?[]const u8 = null;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--attach")) {
            var target_opt: ?[]const u8 = null;
            var cmd_start: usize = i + 1;
            if (cmd_start < args.len) {
                const first = args[cmd_start];
                if (std.mem.eql(u8, first, "list") or
                    isAllDigits(first) or
                    std.mem.startsWith(u8, first, "/") or
                    std.mem.endsWith(u8, first, ".sock"))
                {
                    target_opt = first;
                    cmd_start += 1;
                } else if (std.mem.eql(u8, first, "auto")) {
                    target_opt = null;
                    cmd_start += 1;
                }
            }
            var cmd_buf: std.ArrayList(u8) = .empty;
            defer cmd_buf.deinit(arena);
            for (args[cmd_start..], 0..) |tok, tidx| {
                if (tidx > 0) try cmd_buf.append(arena, ' ');
                try cmd_buf.appendSlice(arena, tok);
            }
            const cmd_slice = if (cmd_buf.items.len > 0) cmd_buf.items else "status";
            try platform.profiler.runAttachCli(arena, target_opt, cmd_slice);
            return;
        } else if (std.mem.eql(u8, args[i], "--frames") and i + 1 < args.len) {
            max_frames = try std.fmt.parseInt(usize, args[i + 1], 10);
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--screenshot") and i + 1 < args.len) {
            screenshot_path = args[i + 1];
            i += 1;
        } else if ((std.mem.eql(u8, args[i], "--dylib") or std.mem.eql(u8, args[i], "--lib")) and i + 1 < args.len) {
            dylib_raw = args[i + 1];
            i += 1;
        } else if ((std.mem.eql(u8, args[i], "--workspace") or std.mem.eql(u8, args[i], "-C")) and i + 1 < args.len) {
            workspace_arg = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--title") and i + 1 < args.len) {
            title = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--bench")) {
            bench = true;
        } else if (std.mem.eql(u8, args[i], "--metrics-json") and i + 1 < args.len) {
            metrics_json_path = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--trace") and i + 1 < args.len) {
            trace_path = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--scenario") and i + 1 < args.len) {
            scenario = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--help") or std.mem.eql(u8, args[i], "-h")) {
            std.debug.print(
                \\Usage: lightning [options] [workspace_dir]
                \\
                \\Options:
                \\  --workspace, -C <dir>   Open workspace directory on startup (or pass <dir> positionally)
                \\  --dylib <path>          Path to plugin .dylib/.dll (default: {s})
                \\  --title <string>        Window title
                \\  --frames <N>            Exit after rendering N frames (useful for headless CI/profiling)
                \\  --bench                 Run in automated benchmark mode (outputs ASCII summary on exit)
                \\  --metrics-json <path>   Export machine-readable frame performance metrics to JSON file
                \\  --trace <path>          Export Chrome/Perfetto JSON trace event file (view in ui.perfetto.dev)
                \\  --scenario <name>       Run scripted synthetic input scenario: typing | scroll | idle
                \\  --attach [pid] [cmd]    Connect to a running editor instance to debug live performance:
                \\                            status | metrics | frames [N] | trace start | trace stop [path] |
                \\                            overlay [on|off|toggle] | redraw | reset | list | help
                \\  -h, --help              Show this help message
                \\
            , .{fs_util.DefaultAppLibPath});
            return;
        } else if (args[i].len > 0 and args[i][0] != '-' and workspace_arg == null) {
            workspace_arg = args[i];
        }
    }

    const dylib_path = try resolveDylibAbsolutePath(arena, dylib_raw);

    if (workspace_arg) |ws_raw| {
        const ws_expanded = try expandHomePath(arena, ws_raw);
        if (fs_util.chdir(ws_expanded.ptr) != 0) {
            std.debug.print("Warning: could not chdir to workspace '{s}'\n", .{ws_expanded});
        }
    }

    try platform.window_host.run(.{
        .title = title.ptr,
        .width = 1080,
        .height = 700,
        .dylib_path = dylib_path.ptr,
        .max_frames = max_frames,
        .bench = bench,
        .metrics_json_path = metrics_json_path,
        .trace_path = trace_path,
        .scenario = scenario,
        .screenshot_path = screenshot_path,
    });
}
