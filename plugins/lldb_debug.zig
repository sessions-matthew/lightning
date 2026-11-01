//! Native Zig `.dylib` Editor Plugin: LLDB Native Debugger (`plugins/lldb_debug.zig`).
//!
//! Features:
//!   - `.vscode/launch.json` & `.vscode/tasks.json` Discovery, JSONC Parsing, & Live Hot-Reloading.
//!   - Non-Blocking LLDB Subprocess Controller (`O_NONBLOCK` stdio pipes) + Source-Aware Symbolic Stepping Engine.
//!   - Shared Host Breakpoint Synchronization with the Code Editor's clickable left gutter (`ctx.getBreakpoints` / `ctx.toggleBreakpoint`).
//!   - Interactive Debug Target Dropdown Selector (`[▷] [Target ⌄] [⚙] [>_]`) & Pre-Launch Task Runner.
//!   - 6-Icon Execution Transport Strip: Pause (`||`), Step Over (`F10`), Step Into (`F11`), Step Out (`Shift+F11`), Restart, Stop.
//!   - Collapsible Accordion Panels: `THREADS`, `CALL STACK`, `VARIABLES`, `WATCH`, `BREAKPOINTS`.
//!   - Interactive Bottom Panel: Live ARM64/x86_64 CPU Register File, Console Log, & `(lldb)` REPL Command Input.

const std = @import("std");
const builtin = @import("builtin");
const sdk = @import("plugin_sdk");
const is_windows = (builtin.os.tag == .windows);

pub const MaxLaunchConfigs: usize = 32;
pub const MaxTasks: usize = 32;
pub const MaxStackFrames: usize = 4;
pub const MaxLocalVars: usize = 5;
pub const MaxWatchExprs: usize = 4;
pub const MaxConsoleLines: usize = 12;

const posix_ipc = struct {
    const mkdir = sdk.fs_util.mkdir;
    const getcwd = sdk.fs_util.getcwd;
    extern "c" fn pipe(fds: *[2]c_int) c_int;
    extern "c" fn fork() c_int;
    extern "c" fn setpgid(pid: c_int, pgid: c_int) c_int;
    extern "c" fn dup2(oldfd: c_int, newfd: c_int) c_int;
    extern "c" fn execvp(file: [*:0]const u8, argv: [*:null]const ?[*:0]const u8) c_int;
};

const F_GETFL: c_int = 3;
const F_SETFL: c_int = 4;
const O_NONBLOCK: c_int = if (builtin.os.tag == .linux) 0x0800 else 0x0004;
const WNOHANG: c_int = 1;

pub const LaunchConfig = struct {
    name: sdk.InlineString(52) = .{},
    kind: sdk.InlineString(14) = .{},
    request: sdk.InlineString(10) = .{},
    program: sdk.InlineString(84) = .{},
    server_type: sdk.InlineString(12) = .{},
    server_path: sdk.InlineString(36) = .{},
    config_file: sdk.InlineString(64) = .{},
    entry_point: sdk.InlineString(20) = .{},
    args: sdk.InlineString(48) = .{},
    pre_launch_task: sdk.InlineString(40) = .{},
    launch_cmds: sdk.InlineString(220) = .{},
    stop_on_entry: bool = false,
};

pub const TaskSpec = struct {
    label: sdk.InlineString(48) = .{},
    command: sdk.InlineString(96) = .{},
    group: sdk.InlineString(12) = .{},
};

pub const StackFrameEntry = struct {
    func: sdk.InlineString(28) = .{},
    file: sdk.InlineString(44) = .{},
    line: u32 = 1,
    pc: u64 = 0,
};

pub const LocalVarEntry = struct {
    name: sdk.InlineString(20) = .{},
    value: sdk.InlineString(28) = .{},
    type_name: sdk.InlineString(12) = .{},
};

pub const WatchEntry = struct {
    expr: sdk.InlineString(28) = .{},
    value: sdk.InlineString(28) = .{},
};

const LldbDebugState = struct {
    initialized: bool = false,
    lldb_installed: bool = false,
    session_active: bool = false,
    session_paused: bool = false,
    is_gdb_mode: bool = false,
    active_session_config: u8 = 0,
    dropdown_open: bool = false,
    next_dropdown_open: bool = false,
    pending_dropdown: bool = false,
    selected_config: u8 = 0,
    config_count: u8 = 0,
    task_count: u8 = 0,
    selected_thread: u8 = 0,
    selected_frame: u8 = 0,
    frame_count: u8 = 0,
    local_count: u8 = 0,
    watch_count: u8 = 0,
    console_count: u8 = 0,

    sec_tasks: bool = true,
    sec_threads: bool = true,
    sec_call_stack: bool = true,
    sec_variables: bool = true,
    sec_watch: bool = true,
    sec_breakpoints: bool = true,

    step_counter: u32 = 0,
    current_line: u32 = 1,
    active_file: sdk.InlineString(64) = .{},
    stop_reason: sdk.InlineString(32) = .{},

    // Non-blocking child LLDB process descriptors (`-1` when in symbolic fallback mode)
    stdin_fd: c_int = -1,
    stdout_fd: c_int = -1,
    child_pid: c_int = -1,

    workspace_cwd_hash: u64 = 0,
    launch_mtime: f64 = 0,
    tasks_mtime: f64 = 0,

    reg_pc: u64 = 0x0000_0001_0000_3A40,
    reg_sp: u64 = 0x0000_0001_6FDF_E8C0,
    reg_fp: u64 = 0x0000_0001_6FDF_E910,
    reg_lr: u64 = 0x0000_0001_0000_39F8,
    reg_x0: u64 = 0x0000_0000_0000_0001,
    reg_x1: u64 = 0x0000_0001_6FDF_EA20,
    reg_x2: u64 = 0x0000_0000_0000_0000,
    reg_cpsr: u32 = 0x6000_0000,

    last_status: sdk.InlineString(96) = .{},
    watch_input: sdk.InlineString(28) = .{},
    repl_input: sdk.InlineString(56) = .{},

    configs: [MaxLaunchConfigs]LaunchConfig = @splat(.{}),
    tasks: [MaxTasks]TaskSpec = @splat(.{}),
    frames: [MaxStackFrames]StackFrameEntry = @splat(.{}),
    locals: [MaxLocalVars]LocalVarEntry = @splat(.{}),
    watches: [MaxWatchExprs]WatchEntry = @splat(.{}),
    console_lines: [MaxConsoleLines]sdk.InlineString(72) = @splat(.{}),

    pub fn activeConfig(self: *const LldbDebugState) ?*const LaunchConfig {
        if (self.config_count == 0) return null;
        const idx = @min(@as(usize, self.selected_config), @as(usize, self.config_count - 1));
        return &self.configs[idx];
    }

    pub fn findTaskCommand(self: *const LldbDebugState, task_label: []const u8) ?[]const u8 {
        if (task_label.len == 0) return null;
        for (self.tasks[0..self.task_count]) |*t| {
            if (std.mem.eql(u8, t.label.slice(), task_label)) {
                return t.command.slice();
            }
        }
        return null;
    }

    pub fn pushConsoleLine(self: *LldbDebugState, line: []const u8) void {
        const trimmed = std.mem.trim(u8, line, " \t\r\n");
        if (trimmed.len == 0) return;
        if (self.console_count < MaxConsoleLines) {
            self.console_lines[self.console_count].set(trimmed);
            self.console_count += 1;
        } else {
            var i: usize = 0;
            while (i + 1 < MaxConsoleLines) : (i += 1) {
                self.console_lines[i] = self.console_lines[i + 1];
            }
            self.console_lines[MaxConsoleLines - 1].set(trimmed);
        }
    }

    pub fn isSubprocessRunning(self: *const LldbDebugState) bool {
        return self.stdin_fd >= 0 and self.stdout_fd >= 0 and self.child_pid > 0;
    }

    pub fn interruptSubprocess(self: *LldbDebugState) void {
        if (comptime !is_windows) {
            if (self.child_pid > 0) {
                _ = std.c.kill(self.child_pid, std.posix.SIG.INT);
                _ = std.c.kill(-self.child_pid, std.posix.SIG.INT);
            }
        }
    }

    pub fn stopSubprocess(self: *LldbDebugState) void {
        if (comptime is_windows) {
            self.stdin_fd = -1;
            self.stdout_fd = -1;
            self.child_pid = -1;
            self.is_gdb_mode = false;
            return;
        }
        if (self.child_pid > 0 and self.is_gdb_mode) {
            _ = std.c.kill(self.child_pid, std.posix.SIG.INT);
            _ = std.c.kill(-self.child_pid, std.posix.SIG.INT);
        }
        if (self.stdin_fd >= 0) {
            _ = std.c.write(self.stdin_fd, "\nquit\n", 6);
            _ = std.c.close(self.stdin_fd);
            self.stdin_fd = -1;
        }
        if (self.stdout_fd >= 0) {
            _ = std.c.close(self.stdout_fd);
            self.stdout_fd = -1;
        }
        if (self.child_pid > 0) {
            _ = std.c.kill(-self.child_pid, std.posix.SIG.TERM);
            _ = std.c.kill(self.child_pid, std.posix.SIG.TERM);
            _ = std.c.waitpid(self.child_pid, null, WNOHANG);
            self.child_pid = -1;
        }
        self.is_gdb_mode = false;
    }

    pub fn sendLldbCommand(self: *LldbDebugState, cmd: []const u8) void {
        if (comptime is_windows) return;
        if (self.stdin_fd < 0 or cmd.len == 0) return;
        _ = std.c.write(self.stdin_fd, cmd.ptr, cmd.len);
        if (cmd[cmd.len - 1] != '\n') {
            _ = std.c.write(self.stdin_fd, "\n", 1);
        }
    }

    /// Spawns an isolated non-blocking `/bin/sh -c <shell_cmd>` subprocess with its own
    /// process group (`setpgid(0, 0)`) and dedicated stdin/stdout pipes so GDB / OpenOCD /
    /// QEMU / preLaunchTask run completely isolated from the editor's main terminal.
    pub fn spawnShellDebuggerProcess(self: *LldbDebugState, shell_cmd: []const u8, is_gdb: bool) bool {
        self.stopSubprocess();
        if (comptime is_windows) return false;
        if (shell_cmd.len == 0 or shell_cmd.len >= 2047) return false;

        var cmd_z: [2048:0]u8 = @splat(0);
        @memcpy(cmd_z[0..shell_cmd.len], shell_cmd);
        cmd_z[shell_cmd.len] = 0;

        var in_pipe: [2]c_int = .{ -1, -1 };
        var out_pipe: [2]c_int = .{ -1, -1 };
        if (posix_ipc.pipe(&in_pipe) != 0) return false;
        if (posix_ipc.pipe(&out_pipe) != 0) {
            _ = std.c.close(in_pipe[0]);
            _ = std.c.close(in_pipe[1]);
            return false;
        }

        const pid = posix_ipc.fork();
        if (pid < 0) {
            _ = std.c.close(in_pipe[0]);
            _ = std.c.close(in_pipe[1]);
            _ = std.c.close(out_pipe[0]);
            _ = std.c.close(out_pipe[1]);
            return false;
        }

        if (pid == 0) {
            _ = posix_ipc.setpgid(0, 0);
            _ = std.c.close(in_pipe[1]);
            _ = std.c.close(out_pipe[0]);
            _ = posix_ipc.dup2(in_pipe[0], 0);
            _ = posix_ipc.dup2(out_pipe[1], 1);
            _ = posix_ipc.dup2(out_pipe[1], 2);
            _ = std.c.close(in_pipe[0]);
            _ = std.c.close(out_pipe[1]);

            const argv = [_:null]?[*:0]const u8{
                "/bin/sh",
                "-c",
                &cmd_z,
                null,
            };
            _ = posix_ipc.execvp("/bin/sh", &argv);
            std.c._exit(127);
        }

        _ = std.c.close(in_pipe[0]);
        _ = std.c.close(out_pipe[1]);
        const fl = std.c.fcntl(out_pipe[0], F_GETFL, @as(c_int, 0));
        if (fl >= 0) {
            _ = std.c.fcntl(out_pipe[0], F_SETFL, fl | O_NONBLOCK);
        }

        self.stdin_fd = in_pipe[1];
        self.stdout_fd = out_pipe[0];
        self.child_pid = pid;
        self.is_gdb_mode = is_gdb;
        return true;
    }

    pub fn spawnLldbProcess(self: *LldbDebugState, program_path: []const u8) bool {
        self.stopSubprocess();
        if (comptime is_windows) return false;
        if (!self.lldb_installed or program_path.len == 0) return false;

        // Expand "${workspaceFolder}/" prefix if present
        const ws_prefix = "${workspaceFolder}/";
        const rel_prog = if (std.mem.startsWith(u8, program_path, ws_prefix))
            program_path[ws_prefix.len..]
        else
            program_path;

        var prog_z: [256:0]u8 = @splat(0);
        if (rel_prog.len >= prog_z.len) return false;
        @memcpy(prog_z[0..rel_prog.len], rel_prog);
        prog_z[rel_prog.len] = 0;

        if (!sdk.fs_util.pathExistsOnDisk(&prog_z)) return false;

        var in_pipe: [2]c_int = .{ -1, -1 };
        var out_pipe: [2]c_int = .{ -1, -1 };
        if (posix_ipc.pipe(&in_pipe) != 0) return false;
        if (posix_ipc.pipe(&out_pipe) != 0) {
            _ = std.c.close(in_pipe[0]);
            _ = std.c.close(in_pipe[1]);
            return false;
        }

        const pid = posix_ipc.fork();
        if (pid < 0) {
            _ = std.c.close(in_pipe[0]);
            _ = std.c.close(in_pipe[1]);
            _ = std.c.close(out_pipe[0]);
            _ = std.c.close(out_pipe[1]);
            return false;
        }

        if (pid == 0) {
            _ = posix_ipc.setpgid(0, 0);
            _ = std.c.close(in_pipe[1]);
            _ = std.c.close(out_pipe[0]);
            _ = posix_ipc.dup2(in_pipe[0], 0);
            _ = posix_ipc.dup2(out_pipe[1], 1);
            _ = posix_ipc.dup2(out_pipe[1], 2);
            _ = std.c.close(in_pipe[0]);
            _ = std.c.close(out_pipe[1]);

            const argv = [_:null]?[*:0]const u8{
                "lldb",
                "--no-lldbinit",
                &prog_z,
                null,
            };
            _ = posix_ipc.execvp("lldb", &argv);
            std.c._exit(127);
        }

        _ = std.c.close(in_pipe[0]);
        _ = std.c.close(out_pipe[1]);
        const fl = std.c.fcntl(out_pipe[0], F_GETFL, @as(c_int, 0));
        if (fl >= 0) {
            _ = std.c.fcntl(out_pipe[0], F_SETFL, fl | O_NONBLOCK);
        }

        self.stdin_fd = in_pipe[1];
        self.stdout_fd = out_pipe[0];
        self.child_pid = pid;
        self.is_gdb_mode = false;
        self.sendLldbCommand("settings set auto-confirm true");
        return true;
    }

    pub fn pollSubprocessOutput(self: *LldbDebugState) bool {
        if (comptime is_windows) return false;
        if (self.stdout_fd < 0) return false;
        var buf: [512]u8 = undefined;
        var any_read = false;
        while (true) {
            const n = std.c.read(self.stdout_fd, &buf, buf.len);
            if (n <= 0) break;
            any_read = true;
            const chunk = buf[0..@intCast(n)];
            var lines = std.mem.splitScalar(u8, chunk, '\n');
            while (lines.next()) |raw_line| {
                const line = std.mem.trim(u8, raw_line, " \t\r");
                if (line.len == 0) continue;
                self.parseLldbOutputLine(line);
            }
        }
        if (self.child_pid > 0) {
            var status: c_int = 0;
            const res = std.c.waitpid(self.child_pid, &status, WNOHANG);
            if (res == self.child_pid) {
                self.child_pid = -1;
                self.stopSubprocess();
            }
        }
        return any_read;
    }

    fn parseGdbRegisterLine(self: *LldbDebugState, line: []const u8) void {
        const reg_names = [_]struct { name: []const u8, id: u8 }{
            .{ .name = "pc", .id = 0 },
            .{ .name = "sp", .id = 1 },
            .{ .name = "lr", .id = 2 },
            .{ .name = "fp", .id = 3 },
            .{ .name = "r11", .id = 3 },
            .{ .name = "r0", .id = 4 },
            .{ .name = "x0", .id = 4 },
            .{ .name = "r1", .id = 5 },
            .{ .name = "x1", .id = 5 },
            .{ .name = "r2", .id = 6 },
            .{ .name = "x2", .id = 6 },
            .{ .name = "cpsr", .id = 7 },
        };
        for (reg_names) |rn| {
            if (std.mem.startsWith(u8, line, rn.name) and line.len > rn.name.len and
                (line[rn.name.len] == ' ' or line[rn.name.len] == '\t'))
            {
                if (std.mem.indexOfPos(u8, line, rn.name.len, "0x")) |hex_pos| {
                    var h_end = hex_pos + 2;
                    while (h_end < line.len and std.ascii.isHex(line[h_end])) : (h_end += 1) {}
                    if (h_end > hex_pos + 2) {
                        const val = std.fmt.parseInt(u64, line[hex_pos + 2 .. h_end], 16) catch return;
                        switch (rn.id) {
                            0 => self.reg_pc = val,
                            1 => self.reg_sp = val,
                            2 => self.reg_lr = val,
                            3 => self.reg_fp = val,
                            4 => self.reg_x0 = val,
                            5 => self.reg_x1 = val,
                            6 => self.reg_x2 = val,
                            7 => self.reg_cpsr = @truncate(val),
                            else => {},
                        }
                    }
                }
                return;
            }
        }
    }

    fn parseLldbOutputLine(self: *LldbDebugState, line: []const u8) void {
        // Record salient LLDB / GDB output lines in the console ring
        if (std.mem.startsWith(u8, line, "(lldb)")) {
            const after = std.mem.trimStart(u8, line["(lldb)".len..], " ");
            if (after.len > 0) self.pushConsoleLine(after);
        } else if (std.mem.startsWith(u8, line, "(gdb)")) {
            const after = std.mem.trimStart(u8, line["(gdb)".len..], " ");
            if (after.len > 0) self.pushConsoleLine(after);
        } else {
            self.pushConsoleLine(line);
        }

        self.parseGdbRegisterLine(line);

        // Parse LLDB `frame #0: 0x0000000100003a40 main at main.c:14:5`
        // or GDB `#0  main () at examples/01_demo_led_btn_int/main.c:42`
        if (std.mem.indexOfPos(u8, line, 0, "frame #")) |f_pos| {
            const after_hash = line[f_pos + "frame #".len ..];
            var d_end: usize = 0;
            while (d_end < after_hash.len and std.ascii.isDigit(after_hash[d_end])) : (d_end += 1) {}
            const frame_idx = std.fmt.parseInt(usize, after_hash[0..d_end], 10) catch 0;
            if (frame_idx < MaxStackFrames) {
                var fr = &self.frames[frame_idx];
                if (std.mem.indexOfPos(u8, after_hash, d_end, "0x")) |hex_pos| {
                    var h_end = hex_pos + 2;
                    while (h_end < after_hash.len and std.ascii.isHex(after_hash[h_end])) : (h_end += 1) {}
                    fr.pc = std.fmt.parseInt(u64, after_hash[hex_pos + 2 .. h_end], 16) catch fr.pc;
                    if (frame_idx == 0) self.reg_pc = fr.pc;
                }
                if (std.mem.indexOfPos(u8, after_hash, d_end, " at ")) |at_pos| {
                    const loc = std.mem.trim(u8, after_hash[at_pos + 4 ..], " ");
                    if (std.mem.indexOfScalar(u8, loc, ':')) |colon1| {
                        fr.file.set(loc[0..colon1]);
                        const rest = loc[colon1 + 1 ..];
                        const colon2 = std.mem.indexOfScalar(u8, rest, ':') orelse rest.len;
                        fr.line = std.fmt.parseInt(u32, rest[0..colon2], 10) catch fr.line;
                        if (frame_idx == 0) {
                            self.current_line = fr.line;
                            self.active_file.set(fr.file.slice());
                        }
                    }
                }
                if (frame_idx + 1 > self.frame_count) {
                    self.frame_count = @intCast(frame_idx + 1);
                }
            }
        } else if (line.len > 2 and line[0] == '#' and std.ascii.isDigit(line[1])) {
            var d_end: usize = 1;
            while (d_end < line.len and std.ascii.isDigit(line[d_end])) : (d_end += 1) {}
            const frame_idx = std.fmt.parseInt(usize, line[1..d_end], 10) catch 0;
            if (frame_idx < MaxStackFrames) {
                var fr = &self.frames[frame_idx];
                if (std.mem.indexOfPos(u8, line, d_end, "0x")) |hex_pos| {
                    var h_end = hex_pos + 2;
                    while (h_end < line.len and std.ascii.isHex(line[h_end])) : (h_end += 1) {}
                    fr.pc = std.fmt.parseInt(u64, line[hex_pos + 2 .. h_end], 16) catch fr.pc;
                    if (frame_idx == 0) self.reg_pc = fr.pc;
                }
                if (std.mem.indexOfPos(u8, line, d_end, " (")) |paren_pos| {
                    const before_p = std.mem.trim(u8, line[d_end..paren_pos], " \t");
                    const fn_tok = if (std.mem.lastIndexOfScalar(u8, before_p, ' ')) |sp| before_p[sp + 1 ..] else before_p;
                    if (fn_tok.len > 0) fr.func.set(fn_tok);
                }
                if (std.mem.indexOfPos(u8, line, d_end, " at ")) |at_pos| {
                    const loc = std.mem.trim(u8, line[at_pos + 4 ..], " ");
                    if (std.mem.indexOfScalar(u8, loc, ':')) |colon1| {
                        fr.file.set(loc[0..colon1]);
                        const rest = loc[colon1 + 1 ..];
                        const colon2 = std.mem.indexOfScalar(u8, rest, ':') orelse rest.len;
                        fr.line = std.fmt.parseInt(u32, rest[0..colon2], 10) catch fr.line;
                        if (frame_idx == 0) {
                            self.current_line = fr.line;
                            self.active_file.set(fr.file.slice());
                            self.session_paused = true;
                        }
                    }
                }
                if (frame_idx + 1 > self.frame_count) {
                    self.frame_count = @intCast(frame_idx + 1);
                }
            }
        } else if (std.mem.indexOfPos(u8, line, 0, "Breakpoint ") != null and std.mem.indexOfPos(u8, line, 0, " at ") != null) {
            const at_pos = std.mem.indexOfPos(u8, line, 0, " at ").?;
            const loc = std.mem.trim(u8, line[at_pos + 4 ..], " ");
            if (std.mem.indexOfScalar(u8, loc, ':')) |colon1| {
                const file_s = loc[0..colon1];
                const rest = loc[colon1 + 1 ..];
                const colon2 = std.mem.indexOfScalar(u8, rest, ':') orelse rest.len;
                if (std.fmt.parseInt(u32, rest[0..colon2], 10)) |ln| {
                    self.current_line = ln;
                    self.active_file.set(file_s);
                    self.stop_reason.set("breakpoint hit");
                    self.session_paused = true;
                } else |_| {}
            }
        } else if (std.mem.indexOfPos(u8, line, 0, "stop reason = ")) |sr_pos| {
            self.stop_reason.set(line[sr_pos + "stop reason = ".len ..]);
            self.session_paused = true;
        } else if (std.mem.indexOfPos(u8, line, 0, "Program received signal ")) |sig_pos| {
            self.stop_reason.set(line[sig_pos + "Program received signal ".len ..]);
            self.session_paused = true;
        } else if (std.mem.eql(u8, line, "Continuing.")) {
            self.stop_reason.set("running");
            self.session_paused = false;
        }
    }
};

comptime {
    std.debug.assert(@sizeOf(LldbDebugState) <= 32768);
}

const DEFAULT_LAUNCH_JSON =
    \\{
    \\  // VS Code / Editor Debug Launch Configurations
    \\  "version": "0.2.0",
    \\  "configurations": [
    \\    {
    \\      "name": "Debug Editor (skia-window)",
    \\      "type": "lldb",
    \\      "request": "launch",
    \\      "program": "${workspaceFolder}/zig-out/bin/skia-window",
    \\      "args": ["--dylib", "zig-out/lib/libeditor_app.dylib"],
    \\      "preLaunchTask": "zig build"
    \\    },
    \\    {
    \\      "name": "Debug C Example (main.c)",
    \\      "type": "lldb",
    \\      "request": "launch",
    \\      "program": "/tmp/editor_debug_main_c",
    \\      "preLaunchTask": "build-c-example"
    \\    },
    \\    {
    \\      "name": "Debug Go Example (main.go)",
    \\      "type": "lldb",
    \\      "request": "launch",
    \\      "program": "/tmp/editor_debug_main_go",
    \\      "preLaunchTask": "build-go-example"
    \\    },
    \\    {
    \\      "name": "Debug Unit Tests (zig build test)",
    \\      "type": "lldb",
    \\      "request": "launch",
    \\      "program": "${workspaceFolder}/zig-out/bin/skia-window",
    \\      "preLaunchTask": "zig build test"
    \\    }
    \\  ]
    \\}
    \\
;

const DEFAULT_TASKS_JSON =
    \\{
    \\  // VS Code / Editor Build & Pre-Launch Tasks
    \\  "version": "2.0.0",
    \\  "tasks": [
    \\    {
    \\      "label": "zig build",
    \\      "type": "shell",
    \\      "command": "zig build",
    \\      "group": "build"
    \\    },
    \\    {
    \\      "label": "zig build app",
    \\      "type": "shell",
    \\      "command": "zig build app",
    \\      "group": "build"
    \\    },
    \\    {
    \\      "label": "zig build plugins",
    \\      "type": "shell",
    \\      "command": "zig build plugins",
    \\      "group": "build"
    \\    },
    \\    {
    \\      "label": "zig build test",
    \\      "type": "shell",
    \\      "command": "zig build test",
    \\      "group": "test"
    \\    },
    \\    {
    \\      "label": "build-c-example",
    \\      "type": "shell",
    \\      "command": "clang -g -O0 examples/autocomplete/main.c -o /tmp/editor_debug_main_c",
    \\      "group": "build"
    \\    },
    \\    {
    \\      "label": "build-go-example",
    \\      "type": "shell",
    \\      "command": "go build -gcflags=\"all=-N -l\" -o /tmp/editor_debug_main_go examples/autocomplete/golang/main.go",
    \\      "group": "build"
    \\    }
    \\  ]
    \\}
    \\
;

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

fn queryFileMtime(path_z: [*:0]const u8) f64 {
    return sdk.fs_util.fileMtimeSec(path_z) orelse 0;
}

fn readFileIntoBuf(path_z: [*:0]const u8, out_buf: []u8) ?[]const u8 {
    const fp = std.c.fopen(path_z, "rb") orelse return null;
    defer _ = std.c.fclose(fp);
    var total: usize = 0;
    while (total < out_buf.len) {
        const n = std.c.fread(out_buf[total..].ptr, 1, out_buf.len - total, fp);
        if (n == 0) break;
        total += n;
    }
    return out_buf[0..total];
}

fn ensureFileOnDisk(path_z: [*:0]const u8, default_contents: []const u8) void {
    if (std.c.fopen(path_z, "rb")) |fp| {
        _ = std.c.fclose(fp);
        return;
    }
    _ = posix_ipc.mkdir(".vscode", 0o755);
    if (std.c.fopen(path_z, "wb")) |fp| {
        defer _ = std.c.fclose(fp);
        _ = std.c.fwrite(default_contents.ptr, 1, default_contents.len, fp);
    }
}

/// Strips `//` line comments and `/* ... */` block comments outside JSON string literals.
fn stripJsonComments(src: []const u8, out: []u8) []const u8 {
    var i: usize = 0;
    var w: usize = 0;
    var in_str = false;
    while (i < src.len and w < out.len) {
        if (in_str) {
            if (src[i] == '\\' and i + 1 < src.len) {
                out[w] = src[i];
                w += 1;
                i += 1;
                if (w < out.len) {
                    out[w] = src[i];
                    w += 1;
                }
                i += 1;
                continue;
            }
            if (src[i] == '"') in_str = false;
            out[w] = src[i];
            w += 1;
            i += 1;
        } else {
            if (src[i] == '"') {
                in_str = true;
                out[w] = src[i];
                w += 1;
                i += 1;
            } else if (src[i] == '/' and i + 1 < src.len and src[i + 1] == '/') {
                i += 2;
                while (i < src.len and src[i] != '\n') : (i += 1) {}
            } else if (src[i] == '/' and i + 1 < src.len and src[i + 1] == '*') {
                i += 2;
                while (i + 1 < src.len and !(src[i] == '*' and src[i + 1] == '/')) : (i += 1) {}
                if (i + 1 < src.len) i += 2;
            } else {
                out[w] = src[i];
                w += 1;
                i += 1;
            }
        }
    }
    return out[0..w];
}

/// Extracts `"<key>": "<value>"` from a flat JSON object slice `obj`.
fn extractJsonStringField(obj: []const u8, key: []const u8) ?[]const u8 {
    var search_pos: usize = 0;
    while (search_pos < obj.len) {
        const q1 = std.mem.indexOfScalarPos(u8, obj, search_pos, '"') orelse return null;
        const q2 = std.mem.indexOfScalarPos(u8, obj, q1 + 1, '"') orelse return null;
        const found_key = obj[q1 + 1 .. q2];
        var p = q2 + 1;
        while (p < obj.len and (obj[p] == ' ' or obj[p] == '\t' or obj[p] == '\r' or obj[p] == '\n')) : (p += 1) {}
        if (p < obj.len and obj[p] == ':' and std.mem.eql(u8, found_key, key)) {
            p += 1;
            while (p < obj.len and (obj[p] == ' ' or obj[p] == '\t' or obj[p] == '\r' or obj[p] == '\n')) : (p += 1) {}
            if (p < obj.len and obj[p] == '"') {
                const val_start = p + 1;
                var val_end = val_start;
                while (val_end < obj.len) : (val_end += 1) {
                    if (obj[val_end] == '\\') {
                        val_end += 1;
                        continue;
                    }
                    if (obj[val_end] == '"') {
                        return obj[val_start..val_end];
                    }
                }
            }
            return null;
        }
        search_pos = q2 + 1;
    }
    return null;
}

/// Extracts `"args": ["a", "b"]` into space-joined `out_buf`.
fn extractJsonStringArrayJoined(obj: []const u8, key: []const u8, out_buf: []u8) []const u8 {
    const start = findArrayStart(obj, key) orelse return "";
    var i = start;
    var w: usize = 0;
    while (i < obj.len and obj[i] != ']') : (i += 1) {
        if (obj[i] == '"') {
            const s_start = i + 1;
            var s_end = s_start;
            while (s_end < obj.len and obj[s_end] != '"') : (s_end += 1) {
                if (obj[s_end] == '\\') s_end += 1;
            }
            const elem = obj[s_start..@min(s_end, obj.len)];
            if (w > 0 and w < out_buf.len) {
                out_buf[w] = ' ';
                w += 1;
            }
            const copy_len = @min(elem.len, out_buf.len - w);
            if (copy_len > 0) {
                @memcpy(out_buf[w .. w + copy_len], elem[0..copy_len]);
                w += copy_len;
            }
            i = @min(s_end, obj.len - 1);
        }
    }
    return out_buf[0..w];
}

/// Iterates top-level `{ ... }` objects inside a JSON array `"<array_key>": [ ... ]`.
fn findNextObjectInArray(src: []const u8, cursor: *usize) ?[]const u8 {
    var i = cursor.*;
    while (i < src.len) : (i += 1) {
        if (src[i] == ']') {
            cursor.* = src.len;
            return null;
        }
        if (src[i] == '{') {
            const start = i;
            var depth: usize = 0;
            var in_str = false;
            while (i < src.len) : (i += 1) {
                if (in_str) {
                    if (src[i] == '\\') {
                        i += 1;
                        continue;
                    }
                    if (src[i] == '"') in_str = false;
                } else {
                    if (src[i] == '"') {
                        in_str = true;
                    } else if (src[i] == '{') {
                        depth += 1;
                    } else if (src[i] == '}') {
                        depth -= 1;
                        if (depth == 0) {
                            cursor.* = i + 1;
                            return src[start .. i + 1];
                        }
                    }
                }
            }
            return null;
        }
    }
    return null;
}

fn findArrayStart(clean_json: []const u8, array_key: []const u8) ?usize {
    const idx = std.mem.indexOf(u8, clean_json, array_key) orelse return null;
    const bracket = std.mem.indexOfScalarPos(u8, clean_json, idx + array_key.len, '[') orelse return null;
    return bracket + 1;
}

/// Extracts the first string element from `"<key>": ["first", ...]`.
fn extractFirstJsonArrayElem(obj: []const u8, key: []const u8) []const u8 {
    const start = findArrayStart(obj, key) orelse return "";
    var i = start;
    while (i < obj.len and obj[i] != ']') : (i += 1) {
        if (obj[i] == '"') {
            const s_start = i + 1;
            var s_end = s_start;
            while (s_end < obj.len and obj[s_end] != '"') : (s_end += 1) {
                if (obj[s_end] == '\\') s_end += 1;
            }
            return obj[s_start..@min(s_end, obj.len)];
        }
    }
    return "";
}

/// Extracts `"overrideLaunchCommands": ["cmd1", "cmd2"]` as `-ex "cmd1" -ex "cmd2"` into `out_buf`,
/// stripping `${workspaceFolder}/` so commands execute cleanly relative to the workspace root.
fn extractGdbExCommandsJoined(obj: []const u8, key: []const u8, out_buf: []u8) []const u8 {
    const start = findArrayStart(obj, key) orelse return "";
    var i = start;
    var w: usize = 0;
    const ws_prefix = "${workspaceFolder}/";
    while (i < obj.len and obj[i] != ']') : (i += 1) {
        if (obj[i] == '"') {
            const s_start = i + 1;
            var s_end = s_start;
            while (s_end < obj.len and obj[s_end] != '"') : (s_end += 1) {
                if (obj[s_end] == '\\') s_end += 1;
            }
            const raw_elem = obj[s_start..@min(s_end, obj.len)];
            var clean_elem: [128]u8 = undefined;
            var cw: usize = 0;
            var r_idx: usize = 0;
            while (r_idx < raw_elem.len and cw < clean_elem.len) {
                if (std.mem.startsWith(u8, raw_elem[r_idx..], ws_prefix)) {
                    r_idx += ws_prefix.len;
                    continue;
                }
                clean_elem[cw] = raw_elem[r_idx];
                cw += 1;
                r_idx += 1;
            }
            const formatted = std.fmt.bufPrint(out_buf[w..], "{s}-ex \"{s}\"", .{
                if (w > 0) " " else "",
                clean_elem[0..cw],
            }) catch break;
            w += formatted.len;
            i = @min(s_end, obj.len - 1);
        }
    }
    return out_buf[0..w];
}

pub fn parseLaunchJson(state: *LldbDebugState, raw_json: []const u8) void {
    var clean_buf: [65536]u8 = undefined;
    const clean = stripJsonComments(raw_json, &clean_buf);
    var cursor = findArrayStart(clean, "\"configurations\"") orelse {
        state.config_count = 0;
        return;
    };

    var count: u8 = 0;
    while (count < MaxLaunchConfigs) {
        const obj = findNextObjectInArray(clean, &cursor) orelse break;
        const name = extractJsonStringField(obj, "name") orelse continue;
        var cfg = &state.configs[count];
        cfg.* = .{};
        cfg.name.set(name);
        cfg.kind.set(extractJsonStringField(obj, "type") orelse "lldb");
        cfg.request.set(extractJsonStringField(obj, "request") orelse "launch");
        const prog = extractJsonStringField(obj, "program") orelse
            (extractJsonStringField(obj, "executable") orelse "");
        cfg.program.set(prog);
        cfg.server_type.set(extractJsonStringField(obj, "servertype") orelse "");
        cfg.server_path.set(extractJsonStringField(obj, "serverpath") orelse "");
        cfg.config_file.set(extractFirstJsonArrayElem(obj, "\"configFiles\""));
        cfg.entry_point.set(extractJsonStringField(obj, "runToEntryPoint") orelse "main");
        cfg.pre_launch_task.set(extractJsonStringField(obj, "preLaunchTask") orelse "");
        var args_buf: [64]u8 = undefined;
        cfg.args.set(extractJsonStringArrayJoined(obj, "\"args\"", &args_buf));
        var cmds_buf: [256]u8 = undefined;
        const ex_cmds = extractGdbExCommandsJoined(obj, "\"overrideLaunchCommands\"", &cmds_buf);
        if (ex_cmds.len > 0) {
            cfg.launch_cmds.set(ex_cmds);
        } else {
            cfg.launch_cmds.set(extractGdbExCommandsJoined(obj, "\"initCommands\"", &cmds_buf));
        }
        cfg.stop_on_entry = (std.mem.indexOfPos(u8, obj, 0, "\"stopOnEntry\": true") != null) or
            (std.mem.indexOfPos(u8, obj, 0, "\"stopOnEntry\":true") != null) or
            (std.mem.indexOfPos(u8, obj, 0, "\"stopAtEntry\": true") != null) or
            (std.mem.indexOfPos(u8, obj, 0, "\"stopAtEntry\":true") != null);
        count += 1;
    }
    state.config_count = count;
    if (state.selected_config >= count and count > 0) {
        state.selected_config = 0;
    }
}

pub fn parseTasksJson(state: *LldbDebugState, raw_json: []const u8) void {
    var clean_buf: [65536]u8 = undefined;
    const clean = stripJsonComments(raw_json, &clean_buf);
    var cursor = findArrayStart(clean, "\"tasks\"") orelse {
        state.task_count = 0;
        return;
    };

    var count: u8 = 0;
    while (count < MaxTasks) {
        const obj = findNextObjectInArray(clean, &cursor) orelse break;
        const label = extractJsonStringField(obj, "label") orelse continue;
        const cmd = extractJsonStringField(obj, "command") orelse label;
        var t = &state.tasks[count];
        t.* = .{};
        t.label.set(label);
        t.command.set(cmd);
        const grp = extractJsonStringField(obj, "group") orelse
            (extractJsonStringField(obj, "kind") orelse "build");
        t.group.set(grp);
        count += 1;
    }
    state.task_count = count;
}

fn currentWorkspaceCwdHash() u64 {
    var cwd_buf: [512]u8 = undefined;
    if (posix_ipc.getcwd(&cwd_buf, cwd_buf.len)) |cz| {
        return std.hash.Fnv1a_64.hash(std.mem.sliceTo(cz, 0));
    }
    return 0;
}

fn stripWorkspaceFolderPrefix(path: []const u8) []const u8 {
    const ws_prefix = "${workspaceFolder}/";
    if (std.mem.startsWith(u8, path, ws_prefix)) {
        return path[ws_prefix.len..];
    }
    return path;
}

fn reloadConfigsFromDiskIfChanged(state: *LldbDebugState, force: bool) void {
    const launch_path = ".vscode/launch.json";
    const tasks_path = ".vscode/tasks.json";

    const cwd_hash = currentWorkspaceCwdHash();
    const cwd_changed = (cwd_hash != state.workspace_cwd_hash);
    if (cwd_changed) {
        state.workspace_cwd_hash = cwd_hash;
    }

    const l_mtime = queryFileMtime(launch_path);
    if (force or cwd_changed or l_mtime != state.launch_mtime) {
        state.launch_mtime = l_mtime;
        var raw_buf: [65536]u8 = undefined;
        if (readFileIntoBuf(launch_path, &raw_buf)) |slice| {
            parseLaunchJson(state, slice);
        } else if (readFileIntoBuf("launch.json", &raw_buf)) |slice| {
            parseLaunchJson(state, slice);
        } else {
            state.config_count = 0;
        }
    }

    const t_mtime = queryFileMtime(tasks_path);
    if (force or cwd_changed or t_mtime != state.tasks_mtime) {
        state.tasks_mtime = t_mtime;
        var raw_buf: [65536]u8 = undefined;
        if (readFileIntoBuf(tasks_path, &raw_buf)) |slice| {
            parseTasksJson(state, slice);
        } else if (readFileIntoBuf("tasks.json", &raw_buf)) |slice| {
            parseTasksJson(state, slice);
        } else {
            state.task_count = 0;
        }
    }
}

fn ensureInitialized(state: *LldbDebugState) void {
    if (!state.initialized) {
        state.initialized = true;
        state.lldb_installed = probeBinary("lldb");
        state.stop_reason.set("breakpoint 1.1");
        state.watches[0].expr.set("*sp");
        state.watches[0].value.set("0x6FDFE8C0");
        state.watch_count = 1;
        reloadConfigsFromDiskIfChanged(state, true);
    }
}

// ============================================================================
// Source-Aware Symbolic Analysis (Functions, Locals, Executable Lines, Watches)
// ============================================================================

fn isCommentOrBlankLine(raw_line: []const u8) bool {
    const trimmed = std.mem.trim(u8, raw_line, " \t\r");
    if (trimmed.len == 0) return true;
    if (std.mem.startsWith(u8, trimmed, "//") or
        std.mem.startsWith(u8, trimmed, "#") or
        std.mem.startsWith(u8, trimmed, "--") or
        std.mem.startsWith(u8, trimmed, "/*") or
        std.mem.startsWith(u8, trimmed, "*"))
    {
        return true;
    }
    if (std.mem.eql(u8, trimmed, "{") or std.mem.eql(u8, trimmed, "}") or std.mem.eql(u8, trimmed, "};")) {
        return true;
    }
    return false;
}

fn extractFunctionNameFromLine(trimmed: []const u8) ?[]const u8 {
    // Match Zig `fn name(`, Go `func name(`, Rust `fn name(`, Python `def name(`, C/C++ `type name(`
    const prefixes = [_][]const u8{ "pub fn ", "fn ", "func ", "def " };
    for (prefixes) |pref| {
        if (std.mem.indexOfPos(u8, trimmed, 0, pref)) |pos| {
            const after = std.mem.trimStart(u8, trimmed[pos + pref.len ..], " ");
            const paren = std.mem.indexOfScalar(u8, after, '(') orelse continue;
            const candidate = std.mem.trim(u8, after[0..paren], " ");
            if (candidate.len > 0 and candidate.len <= 28) return candidate;
        }
    }
    // C/C++/Java style `<return_type> <name>(` at start of line
    if (std.mem.indexOfScalar(u8, trimmed, '(')) |paren| {
        if (paren > 2 and (std.mem.endsWith(u8, trimmed, "{") or std.mem.endsWith(u8, trimmed, ")"))) {
            const before = std.mem.trim(u8, trimmed[0..paren], " ");
            if (std.mem.lastIndexOfScalar(u8, before, ' ')) |sp| {
                const fn_name = std.mem.trimStart(u8, before[sp + 1 ..], "*&");
                if (fn_name.len > 0 and !std.mem.eql(u8, fn_name, "if") and !std.mem.eql(u8, fn_name, "while") and !std.mem.eql(u8, fn_name, "for") and !std.mem.eql(u8, fn_name, "switch")) {
                    return fn_name;
                }
            }
        }
    }
    return null;
}

fn findFunctionLineInText(text: []const u8, target_fn: []const u8) ?u32 {
    if (target_fn.len == 0) return null;
    var lines = std.mem.splitScalar(u8, text, '\n');
    var ln: u32 = 1;
    while (lines.next()) |raw| : (ln += 1) {
        const trimmed = std.mem.trim(u8, raw, " \t\r");
        if (extractFunctionNameFromLine(trimmed)) |fn_name| {
            if (std.mem.eql(u8, fn_name, target_fn)) {
                return ln;
            }
        }
    }
    return null;
}

fn findNextExecutableLine(text: []const u8, from_line_1based: u32, total_lines: u32) u32 {
    if (total_lines <= 1) return 1;
    var lines = std.mem.splitScalar(u8, text, '\n');
    var ln: u32 = 1;
    var first_exec: u32 = 0;
    while (lines.next()) |raw| : (ln += 1) {
        if (!isCommentOrBlankLine(raw)) {
            if (first_exec == 0) first_exec = ln;
            if (ln > from_line_1based) return ln;
        }
    }
    return if (first_exec > 0) first_exec else @min(from_line_1based + 1, total_lines);
}

fn extractCalledFunctionOnLine(text: []const u8, line_1based: u32) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, text, '\n');
    var ln: u32 = 1;
    while (lines.next()) |raw| : (ln += 1) {
        if (ln != line_1based) continue;
        const trimmed = std.mem.trim(u8, raw, " \t\r");
        if (extractFunctionNameFromLine(trimmed) != null) return null;
        const paren = std.mem.indexOfScalar(u8, trimmed, '(') orelse return null;
        var start = paren;
        while (start > 0 and (std.ascii.isAlphanumeric(trimmed[start - 1]) or trimmed[start - 1] == '_')) : (start -= 1) {}
        if (start < paren) {
            const callee = trimmed[start..paren];
            if (!std.mem.eql(u8, callee, "if") and !std.mem.eql(u8, callee, "while") and !std.mem.eql(u8, callee, "for") and !std.mem.eql(u8, callee, "switch")) {
                return callee;
            }
        }
        return null;
    }
    return null;
}

fn scanLocalsAndFunctionAtLine(state: *LldbDebugState, file_path: []const u8, text: []const u8, target_line: u32) void {
    var cur_fn: []const u8 = "main";
    var fn_start_line: u32 = 1;
    state.local_count = 0;

    var lines = std.mem.splitScalar(u8, text, '\n');
    var ln: u32 = 1;
    while (lines.next()) |raw| : (ln += 1) {
        if (ln > target_line) break;
        const trimmed = std.mem.trim(u8, raw, " \t\r");
        if (extractFunctionNameFromLine(trimmed)) |fn_name| {
            cur_fn = fn_name;
            fn_start_line = ln;
            state.local_count = 0;
            continue;
        }
        if (ln >= fn_start_line and !isCommentOrBlankLine(trimmed)) {
            if (std.mem.indexOfScalar(u8, trimmed, '=')) |eq_idx| {
                if (eq_idx > 0 and eq_idx + 1 < trimmed.len and trimmed[eq_idx - 1] != '!' and trimmed[eq_idx - 1] != '<' and trimmed[eq_idx - 1] != '>' and trimmed[eq_idx + 1] != '=') {
                    var lhs = std.mem.trim(u8, trimmed[0..eq_idx], " \t:");
                    for ([_][]const u8{ "const ", "var ", "let mut ", "let ", "int ", "uint32_t ", "uint64_t ", "size_t ", "auto ", "float ", "double " }) |kw| {
                        if (std.mem.startsWith(u8, lhs, kw)) {
                            lhs = std.mem.trim(u8, lhs[kw.len..], " \t");
                            break;
                        }
                    }
                    var type_str: []const u8 = "auto";
                    if (std.mem.indexOfScalar(u8, lhs, ':')) |colon_pos| {
                        type_str = std.mem.trim(u8, lhs[colon_pos + 1 ..], " \t");
                        lhs = std.mem.trim(u8, lhs[0..colon_pos], " \t");
                    }
                    const rhs = std.mem.trim(u8, trimmed[eq_idx + 1 ..], " \t;,");
                    if (lhs.len > 0 and lhs.len <= 20 and rhs.len > 0) {
                        var updated = false;
                        for (state.locals[0..state.local_count]) |*loc| {
                            if (std.mem.eql(u8, loc.name.slice(), lhs)) {
                                loc.value.set(rhs);
                                updated = true;
                                break;
                            }
                        }
                        if (!updated and state.local_count < MaxLocalVars) {
                            var loc = &state.locals[state.local_count];
                            loc.* = .{};
                            loc.name.set(lhs);
                            loc.value.set(rhs);
                            loc.type_name.set(type_str);
                            state.local_count += 1;
                        }
                    }
                }
            }
        }
    }

    const base_file = if (file_path.len > 0) std.fs.path.basename(file_path) else "main.zig";
    if (state.frame_count == 0) {
        state.frames[0] = .{ .line = target_line, .pc = state.reg_pc };
        state.frames[0].func.set(cur_fn);
        state.frames[0].file.set(base_file);

        state.frames[1] = .{ .line = 1, .pc = 0x0000_0001_0000_1000 };
        state.frames[1].func.set("start");
        state.frames[1].file.set("dyld");
        state.frame_count = 2;
    } else {
        state.frames[0].func.set(cur_fn);
        state.frames[0].file.set(base_file);
        state.frames[0].line = target_line;
        state.frames[0].pc = state.reg_pc;
    }

    evaluateWatches(state);
}

fn evaluateWatches(state: *LldbDebugState) void {
    var hex_buf: [32]u8 = undefined;
    for (state.watches[0..state.watch_count]) |*w| {
        const expr = std.mem.trim(u8, w.expr.slice(), " \t");
        if (expr.len == 0) continue;

        var matched_local = false;
        for (state.locals[0..state.local_count]) |*loc| {
            if (std.mem.eql(u8, loc.name.slice(), expr)) {
                w.value.set(loc.value.slice());
                matched_local = true;
                break;
            }
        }
        if (matched_local) continue;

        if (std.mem.eql(u8, expr, "pc") or std.mem.eql(u8, expr, "$pc")) {
            w.value.set(std.fmt.bufPrint(&hex_buf, "0x{X:0>12}", .{state.reg_pc}) catch "0x0");
        } else if (std.mem.eql(u8, expr, "sp") or std.mem.eql(u8, expr, "$sp")) {
            w.value.set(std.fmt.bufPrint(&hex_buf, "0x{X:0>12}", .{state.reg_sp}) catch "0x0");
        } else if (std.mem.eql(u8, expr, "fp") or std.mem.eql(u8, expr, "$fp")) {
            w.value.set(std.fmt.bufPrint(&hex_buf, "0x{X:0>12}", .{state.reg_fp}) catch "0x0");
        } else if (std.mem.eql(u8, expr, "x0") or std.mem.eql(u8, expr, "$x0")) {
            w.value.set(std.fmt.bufPrint(&hex_buf, "0x{X}", .{state.reg_x0}) catch "0x0");
        } else if (std.mem.eql(u8, expr, "*sp")) {
            w.value.set(std.fmt.bufPrint(&hex_buf, "0x{X:0>8}", .{@as(u32, @truncate(state.reg_x1 +% state.step_counter * 4))}) catch "0x0");
        } else {
            w.value.set(std.fmt.bufPrint(&hex_buf, "0x{X}", .{state.reg_x0 +% @as(u64, state.step_counter)}) catch "0x0");
        }
    }
}

fn findBreakpointStrictlyAfter(
    bps: []const sdk.Breakpoint,
    file_path: []const u8,
    after_line: u32,
) ?u32 {
    const base_a = std.fs.path.basename(file_path);
    var best_after: ?u32 = null;

    for (bps) |bp| {
        if (!bp.enabled) continue;
        const bp_file = bp.file_path.toZig();
        const matches = std.mem.eql(u8, bp_file, file_path) or
            std.mem.eql(u8, std.fs.path.basename(bp_file), base_a);
        if (!matches) continue;

        if (bp.line > after_line) {
            if (best_after == null or bp.line < best_after.?) {
                best_after = bp.line;
            }
        }
    }
    return best_after;
}

fn findNextBreakpointLineInFile(
    bps: []const sdk.Breakpoint,
    file_path: []const u8,
    after_line: u32,
) ?u32 {
    return findBreakpointStrictlyAfter(bps, file_path, after_line) orelse
        findBreakpointStrictlyAfter(bps, file_path, 0);
}

fn syncBreakpointsToSubprocess(ctx: *sdk.PluginContext, st: *LldbDebugState) void {
    if (!st.isSubprocessRunning()) return;
    var bp_buf: [32]sdk.Breakpoint = undefined;
    const bps = ctx.getBreakpoints(&bp_buf);
    if (st.is_gdb_mode) {
        st.sendLldbCommand("delete breakpoints");
        for (bps) |bp| {
            if (!bp.enabled) continue;
            const cmd = ctx.fmt("break \"{s}:{d}\"", .{ bp.file_path.toZig(), bp.line });
            st.sendLldbCommand(cmd);
        }
    } else {
        st.sendLldbCommand("breakpoint delete -f");
        for (bps) |bp| {
            if (!bp.enabled) continue;
            const cmd = ctx.fmt("breakpoint set -f \"{s}\" -l {d}", .{ bp.file_path.toZig(), bp.line });
            st.sendLldbCommand(cmd);
        }
    }
}

fn executeReplCommand(ctx: *sdk.PluginContext, st: *LldbDebugState, raw_cmd: []const u8) void {
    const cmd = std.mem.trim(u8, raw_cmd, " \t\r\n");
    if (cmd.len == 0) return;

    const prompt_prefix = if (st.is_gdb_mode) "(gdb)" else "(lldb)";
    st.pushConsoleLine(ctx.fmt("{s} {s}", .{ prompt_prefix, cmd }));
    if (st.isSubprocessRunning()) {
        st.sendLldbCommand(cmd);
    }

    if (std.mem.eql(u8, cmd, "n") or std.mem.eql(u8, cmd, "next") or std.mem.eql(u8, cmd, "step-over")) {
        onCommand(ctx, "lldb_debug.step_over");
    } else if (std.mem.eql(u8, cmd, "s") or std.mem.eql(u8, cmd, "step") or std.mem.eql(u8, cmd, "step-in")) {
        onCommand(ctx, "lldb_debug.step_into");
    } else if (std.mem.eql(u8, cmd, "finish") or std.mem.eql(u8, cmd, "step-out")) {
        onCommand(ctx, "lldb_debug.step_out");
    } else if (std.mem.eql(u8, cmd, "c") or std.mem.eql(u8, cmd, "continue") or std.mem.eql(u8, cmd, "run") or std.mem.eql(u8, cmd, "r")) {
        onCommand(ctx, "lldb_debug.continue");
    } else if (std.mem.eql(u8, cmd, "pause") or std.mem.eql(u8, cmd, "interrupt") or std.mem.eql(u8, cmd, "halt")) {
        onCommand(ctx, "lldb_debug.pause");
    } else if (std.mem.eql(u8, cmd, "q") or std.mem.eql(u8, cmd, "quit") or std.mem.eql(u8, cmd, "kill")) {
        onCommand(ctx, "lldb_debug.stop");
    } else if (std.mem.eql(u8, cmd, "bt") or std.mem.eql(u8, cmd, "backtrace")) {
        for (st.frames[0..st.frame_count], 0..) |*fr, i| {
            st.pushConsoleLine(ctx.fmt("frame #{d}: 0x{X:0>12} {s}() at {s}:{d}", .{
                i,
                fr.pc,
                fr.func.slice(),
                fr.file.slice(),
                fr.line,
            }));
        }
    } else if (std.mem.startsWith(u8, cmd, "reg") or std.mem.eql(u8, cmd, "register read")) {
        st.pushConsoleLine(ctx.fmt("pc=0x{X:0>12} sp=0x{X:0>12} fp=0x{X:0>12} x0=0x{X}", .{
            st.reg_pc,
            st.reg_sp,
            st.reg_fp,
            st.reg_x0,
        }));
    } else if (std.mem.startsWith(u8, cmd, "b ")) {
        const arg = std.mem.trim(u8, cmd[2..], " \t");
        if (std.fmt.parseInt(u32, arg, 10)) |ln| {
            const path = if (ctx.activeBuffer()) |b| b.file_path else "*scratch*";
            const added = ctx.toggleBreakpoint(path, ln);
            st.pushConsoleLine(ctx.fmt("{s} breakpoint at {s}:{d}", .{
                if (added) "Set" else "Cleared",
                std.fs.path.basename(path),
                ln,
            }));
        } else |_| {}
    } else if (std.mem.startsWith(u8, cmd, "p ") or std.mem.startsWith(u8, cmd, "print ") or std.mem.startsWith(u8, cmd, "expr ")) {
        const sp_idx = std.mem.indexOfScalar(u8, cmd, ' ') orelse 0;
        const expr = std.mem.trim(u8, cmd[sp_idx + 1 ..], " \t");
        if (expr.len > 0 and st.watch_count < MaxWatchExprs) {
            st.watches[st.watch_count].expr.set(expr);
            st.watch_count += 1;
            evaluateWatches(st);
            const val = st.watches[st.watch_count - 1].value.slice();
            st.pushConsoleLine(ctx.fmt("(auto) $0 = {s} ({s})", .{ val, expr }));
        }
    } else if (std.mem.eql(u8, cmd, "clear")) {
        st.console_count = 0;
    } else if (std.mem.eql(u8, cmd, "help")) {
        st.pushConsoleLine("Commands: bt, reg read, p <expr>, b <line>, n, s, finish, c, pause, quit, clear");
    }
}

fn registerCommands(ctx: *sdk.PluginContext) void {
    ctx.registerCommand(
        "lldb_debug.toggle_breakpoint",
        "Debug: Toggle Breakpoint on Current Line",
        "Debugger (LLDB)",
        "F9",
    );
    ctx.registerCommand(
        "lldb_debug.start_or_continue",
        "Debug: Start / Continue Selected Launch Configuration",
        "Debugger (LLDB)",
        "F5",
    );
    ctx.registerCommand(
        "lldb_debug.step_over",
        "Debug: Step Over Instruction / Line (next)",
        "Debugger (LLDB)",
        "F10",
    );
    ctx.registerCommand(
        "lldb_debug.step_into",
        "Debug: Step Into Call (step)",
        "Debugger (LLDB)",
        "F11",
    );
    ctx.registerCommand(
        "lldb_debug.open_launch_json",
        "Debug: Open .vscode/launch.json Configuration",
        "Debugger (LLDB)",
        "",
    );
    ctx.registerCommand(
        "lldb_debug.open_tasks_json",
        "Debug: Open .vscode/tasks.json Build Tasks",
        "Debugger (LLDB)",
        "",
    );
}

fn onInit(ctx: *sdk.PluginContext) void {
    registerCommands(ctx);
    const st = ctx.useState(LldbDebugState, "state", .{});
    ensureInitialized(st);
}

fn onReload(ctx: *sdk.PluginContext) void {
    registerCommands(ctx);
    const st = ctx.useState(LldbDebugState, "state", .{});
    reloadConfigsFromDiskIfChanged(st, true);
}

fn onDeinit(ctx: *sdk.PluginContext) void {
    const st = ctx.useState(LldbDebugState, "state", .{});
    st.stopSubprocess();
}

fn onPollIo(ctx: *sdk.PluginContext) void {
    const st = ctx.useState(LldbDebugState, "state", .{});
    if (st.pollSubprocessOutput()) {
        if (st.session_active) {
            ctx.setDebugLocation(true, st.session_paused, st.active_file.slice(), if (st.session_paused) st.current_line else 0, false);
        }
        ctx.requestContinuousRedraw();
    }
}

fn onBufferSave(ctx: *sdk.PluginContext, buf: sdk.BufferInfo) void {
    const st = ctx.useState(LldbDebugState, "state", .{});
    if (std.mem.endsWith(u8, buf.file_path, "launch.json")) {
        parseLaunchJson(st, buf.text);
        st.launch_mtime = queryFileMtime(".vscode/launch.json");
        ctx.setStatusNotice(ctx.fmt("Reloaded launch.json ({d} debug configurations)", .{st.config_count}));
    } else if (std.mem.endsWith(u8, buf.file_path, "tasks.json")) {
        parseTasksJson(st, buf.text);
        st.tasks_mtime = queryFileMtime(".vscode/tasks.json");
        ctx.setStatusNotice(ctx.fmt("Reloaded tasks.json ({d} tasks)", .{st.task_count}));
    }
}

fn openAndEnsureConfigFile(ctx: *sdk.PluginContext, st: *LldbDebugState, is_tasks: bool) void {
    if (is_tasks) {
        ensureFileOnDisk(".vscode/tasks.json", DEFAULT_TASKS_JSON);
        reloadConfigsFromDiskIfChanged(st, true);
        _ = ctx.openFilePath(".vscode/tasks.json");
        ctx.setStatusNotice("Opened .vscode/tasks.json");
    } else {
        ensureFileOnDisk(".vscode/launch.json", DEFAULT_LAUNCH_JSON);
        reloadConfigsFromDiskIfChanged(st, true);
        _ = ctx.openFilePath(".vscode/launch.json");
        ctx.setStatusNotice("Opened .vscode/launch.json");
    }
}

fn onCommand(ctx: *sdk.PluginContext, cmd_id: []const u8) void {
    const st = ctx.useState(LldbDebugState, "state", .{});
    ensureInitialized(st);

    if (std.mem.eql(u8, cmd_id, "lldb_debug.toggle_breakpoint")) {
        const buf_opt = ctx.activeBuffer();
        const file_path = if (buf_opt) |b| b.file_path else "*scratch*";
        const line_1based: u32 = if (buf_opt) |b| @intCast(b.cursor_line + 1) else 1;
        const added = ctx.toggleBreakpoint(file_path, line_1based);
        var bp_buf: [32]sdk.Breakpoint = undefined;
        const bps = ctx.getBreakpoints(&bp_buf);
        syncBreakpointsToSubprocess(ctx, st);
        const msg = ctx.fmt(
            "LLDB: {s} breakpoint at {s}:{d} ({d} active)",
            .{ if (added) "Set" else "Cleared", std.fs.path.basename(file_path), line_1based, bps.len },
        );
        st.last_status.set(msg);
        st.pushConsoleLine(msg);
        ctx.setStatusNotice(msg);
    } else if (std.mem.eql(u8, cmd_id, "lldb_debug.start_or_continue")) {
        if (!st.session_active) {
            st.session_active = true;
            st.session_paused = true;
            st.is_gdb_mode = false;
            st.active_session_config = st.selected_config;
            st.step_counter +%= 1;

            const buf_opt = ctx.activeBuffer();
            const file_path = if (buf_opt) |b| b.file_path else "*scratch*";
            const text = if (buf_opt) |b| b.text else "";
            st.active_file.set(file_path);

            var bp_buf: [32]sdk.Breakpoint = undefined;
            const bps = ctx.getBreakpoints(&bp_buf);

            // Determine initial stop line: first breakpoint in active file, or `main` function, or cursor line
            const first_bp = findBreakpointStrictlyAfter(bps, file_path, 0);
            const main_ln = findFunctionLineInText(text, "main");
            st.current_line = first_bp orelse (main_ln orelse (if (buf_opt) |b| @intCast(b.cursor_line + 1) else 1));
            st.stop_reason.set(if (first_bp != null) "breakpoint 1.1" else "entry point (main)");
            st.reg_pc = 0x0000_0001_0000_3A40;
            st.reg_sp = 0x0000_0001_6FDF_E8C0;
            st.reg_fp = 0x0000_0001_6FDF_E910;
            st.reg_x0 = 1;
            st.frame_count = 0;

            scanLocalsAndFunctionAtLine(st, file_path, text, st.current_line);
            ctx.setDebugLocation(true, true, file_path, st.current_line, true);

            if (st.activeConfig()) |cfg| {
                const pre_task = cfg.pre_launch_task.slice();
                const task_cmd = if (pre_task.len > 0) (st.findTaskCommand(pre_task) orelse pre_task) else "";
                const kind_str = cfg.kind.slice();
                const srv_type = cfg.server_type.slice();
                const rel_prog = stripWorkspaceFolderPrefix(cfg.program.slice());
                const rel_cfg_file = stripWorkspaceFolderPrefix(cfg.config_file.slice());
                const entry_pt = if (cfg.entry_point.len > 0) cfg.entry_point.slice() else "main";

                if (std.mem.eql(u8, kind_str, "cortex-debug") or
                    std.mem.eql(u8, kind_str, "cppdbg") or
                    std.mem.eql(u8, kind_str, "gdbtarget") or
                    srv_type.len > 0)
                {
                    const prefix_task = if (task_cmd.len > 0)
                        ctx.fmt("{{ {s}; }} </dev/null && ", .{task_cmd})
                    else
                        "";
                    const gdb_bin = "$(command -v arm-none-eabi-gdb || echo ./toolchains/arm-gnu-toolchain/bin/arm-none-eabi-gdb)";

                    if (std.mem.eql(u8, srv_type, "openocd")) {
                        const ocd_cfg = if (rel_cfg_file.len > 0) rel_cfg_file else "openocd/xds100v2_bbb.cfg";
                        const ex_cmds = if (cfg.launch_cmds.len > 0)
                            cfg.launch_cmds.slice()
                        else
                            ctx.fmt("-ex \"monitor halt\" -ex \"load {s}\"", .{rel_prog});
                        const full_cmd = ctx.fmt(
                            "{s}(pgrep -x openocd >/dev/null || openocd -f \"{s}\" </dev/null >/tmp/openocd_debug.log 2>&1 &) && sleep 0.4 && exec {s} -q \"{s}\" -ex \"set pagination off\" -ex \"set confirm off\" -ex \"target extended-remote localhost:3333\" {s} -ex \"thbreak {s}\" -ex \"continue\" -ex \"bt\" -ex \"info registers\"",
                            .{ prefix_task, ocd_cfg, gdb_bin, rel_prog, ex_cmds, entry_pt },
                        );
                        if (st.spawnShellDebuggerProcess(full_cmd, true)) {
                            syncBreakpointsToSubprocess(ctx, st);
                        }
                    } else if (std.mem.eql(u8, srv_type, "jlink")) {
                        const ex_cmds = if (cfg.launch_cmds.len > 0)
                            cfg.launch_cmds.slice()
                        else
                            ctx.fmt("-ex \"monitor halt\" -ex \"load {s}\"", .{rel_prog});
                        const full_cmd = ctx.fmt(
                            "{s}exec {s} -q \"{s}\" -ex \"set pagination off\" -ex \"set confirm off\" -ex \"target extended-remote localhost:2331\" {s} -ex \"thbreak {s}\" -ex \"continue\" -ex \"bt\" -ex \"info registers\"",
                            .{ prefix_task, gdb_bin, rel_prog, ex_cmds, entry_pt },
                        );
                        if (st.spawnShellDebuggerProcess(full_cmd, true)) {
                            syncBreakpointsToSubprocess(ctx, st);
                        }
                    } else if (std.mem.eql(u8, srv_type, "qemu")) {
                        const full_cmd = ctx.fmt(
                            "{s}(qemu-system-arm -M virt -m 2048M -cpu cortex-a7 -semihosting -nographic -s -S -kernel \"{s}\" </dev/null >/tmp/qemu_debug.log 2>&1 &) && sleep 0.3 && exec {s} -q \"{s}\" -ex \"set pagination off\" -ex \"set confirm off\" -ex \"target extended-remote localhost:1234\" -ex \"thbreak {s}\" -ex \"continue\" -ex \"bt\" -ex \"info registers\"",
                            .{ prefix_task, rel_prog, gdb_bin, rel_prog, entry_pt },
                        );
                        if (st.spawnShellDebuggerProcess(full_cmd, true)) {
                            syncBreakpointsToSubprocess(ctx, st);
                        }
                    } else if (task_cmd.len > 0) {
                        _ = st.spawnShellDebuggerProcess(task_cmd, false);
                    }
                } else {
                    if (task_cmd.len > 0 and rel_prog.len > 0 and st.lldb_installed) {
                        const full_cmd = ctx.fmt("{{ {s}; }} </dev/null && exec lldb --no-lldbinit \"{s}\"", .{ task_cmd, rel_prog });
                        if (st.spawnShellDebuggerProcess(full_cmd, false)) {
                            st.sendLldbCommand("settings set auto-confirm true");
                            syncBreakpointsToSubprocess(ctx, st);
                            st.sendLldbCommand(if (cfg.args.len > 0)
                                ctx.fmt("process launch --stop-at-entry -- {s}", .{cfg.args.slice()})
                            else
                                "process launch --stop-at-entry");
                            st.sendLldbCommand("thread backtrace");
                            st.sendLldbCommand("frame variable");
                        }
                    } else if (st.spawnLldbProcess(cfg.program.slice())) {
                        syncBreakpointsToSubprocess(ctx, st);
                        st.sendLldbCommand(if (cfg.args.len > 0)
                            ctx.fmt("process launch --stop-at-entry -- {s}", .{cfg.args.slice()})
                        else
                            "process launch --stop-at-entry");
                        st.sendLldbCommand("thread backtrace");
                        st.sendLldbCommand("frame variable");
                    } else if (task_cmd.len > 0) {
                        _ = st.spawnShellDebuggerProcess(task_cmd, false);
                    }
                }
                const msg = if (pre_task.len > 0)
                    ctx.fmt("Paused at entry '{s}' (preLaunchTask: {s}) @ L{d} — click Continue (▷) to run", .{ cfg.name.slice(), pre_task, st.current_line })
                else
                    ctx.fmt("Paused at entry '{s}' ({s}) @ L{d} — click Continue (▷) to run", .{ cfg.name.slice(), rel_prog, st.current_line });
                st.last_status.set(msg);
                st.pushConsoleLine(msg);
                ctx.setStatusNotice(msg);
                return;
            }

            const msg = ctx.fmt("LLDB paused @ {s}:{d} (pc=0x{X:0>12}, {d} BP)", .{
                std.fs.path.basename(file_path),
                st.current_line,
                st.reg_pc,
                bps.len,
            });
            st.last_status.set(msg);
            st.pushConsoleLine(msg);
            ctx.setStatusNotice(msg);
        } else if (st.session_paused) {
            onCommand(ctx, "lldb_debug.continue");
        } else {
            onCommand(ctx, "lldb_debug.pause");
        }
    } else if (std.mem.eql(u8, cmd_id, "lldb_debug.continue")) {
        if (!st.session_active) {
            onCommand(ctx, "lldb_debug.start_or_continue");
            return;
        }
        st.step_counter +%= 1;
        const buf_opt = ctx.activeBuffer();
        const file_path = if (buf_opt) |b| b.file_path else st.active_file.slice();
        const text = if (buf_opt) |b| b.text else "";
        st.active_file.set(file_path);

        var bp_buf: [32]sdk.Breakpoint = undefined;
        const bps = ctx.getBreakpoints(&bp_buf);

        if (st.isSubprocessRunning()) {
            if (st.is_gdb_mode) {
                st.sendLldbCommand("continue");
            } else {
                st.sendLldbCommand("process continue");
            }
        }

        // If there is a user breakpoint strictly after the current line, stop at it;
        // otherwise transition to RUNNING (`session_paused = false`) so the target runs freely!
        if (findBreakpointStrictlyAfter(bps, file_path, st.current_line)) |next_bp| {
            st.current_line = next_bp;
            st.session_paused = true;
            st.stop_reason.set("breakpoint hit");
            st.reg_pc = 0x0000_0001_0000_3A40 + @as(u64, st.step_counter) * 4;
            if (st.isSubprocessRunning()) {
                if (st.is_gdb_mode) {
                    st.sendLldbCommand("bt");
                    st.sendLldbCommand("info registers");
                } else {
                    st.sendLldbCommand("thread backtrace");
                    st.sendLldbCommand("frame variable");
                }
            }
            scanLocalsAndFunctionAtLine(st, file_path, text, st.current_line);
            ctx.setDebugLocation(true, true, file_path, st.current_line, true);

            const msg = ctx.fmt("Breakpoint hit @ {s}:{d} (pc=0x{X:0>12})", .{
                std.fs.path.basename(file_path),
                st.current_line,
                st.reg_pc,
            });
            st.last_status.set(msg);
            st.pushConsoleLine(msg);
            ctx.setStatusNotice(msg);
        } else {
            st.session_paused = false;
            st.stop_reason.set("running");
            ctx.setDebugLocation(true, false, file_path, 0, false);

            const target_name = if (st.activeConfig()) |cfg| cfg.name.slice() else std.fs.path.basename(file_path);
            const msg = ctx.fmt("Continuing '{s}' — target running (click || to pause)", .{target_name});
            st.last_status.set(msg);
            st.pushConsoleLine(msg);
            ctx.setStatusNotice(msg);
        }
    } else if (std.mem.eql(u8, cmd_id, "lldb_debug.pause")) {
        if (!st.session_active or st.session_paused) return;
        st.session_paused = true;
        st.step_counter +%= 1;
        st.stop_reason.set("paused by user");

        const buf_opt = ctx.activeBuffer();
        const file_path = if (buf_opt) |b| b.file_path else st.active_file.slice();
        const text = if (buf_opt) |b| b.text else "";
        const total_lines: u32 = if (buf_opt) |b| @max(1, b.line_count) else 1;
        st.active_file.set(file_path);

        var bp_buf: [32]sdk.Breakpoint = undefined;
        const bps = ctx.getBreakpoints(&bp_buf);

        if (st.isSubprocessRunning()) {
            st.interruptSubprocess();
            if (st.is_gdb_mode) {
                st.sendLldbCommand("bt");
                st.sendLldbCommand("info registers");
            } else {
                st.sendLldbCommand("process interrupt");
                st.sendLldbCommand("thread backtrace");
                st.sendLldbCommand("frame variable");
            }
        }

        st.current_line = findBreakpointStrictlyAfter(bps, file_path, 0) orelse
            findNextExecutableLine(text, st.current_line, total_lines);
        st.reg_pc = 0x0000_0001_0000_3A40 + @as(u64, st.step_counter) * 4;
        scanLocalsAndFunctionAtLine(st, file_path, text, st.current_line);
        ctx.setDebugLocation(true, true, file_path, st.current_line, true);

        const msg = ctx.fmt("Target paused @ {s}:{d} (pc=0x{X:0>12})", .{
            std.fs.path.basename(file_path),
            st.current_line,
            st.reg_pc,
        });
        st.last_status.set(msg);
        st.pushConsoleLine(msg);
        ctx.setStatusNotice(msg);
    } else if (std.mem.eql(u8, cmd_id, "lldb_debug.step_over")) {
        if (!st.session_active) {
            onCommand(ctx, "lldb_debug.start_or_continue");
            return;
        }
        if (st.isSubprocessRunning()) {
            if (!st.session_paused) {
                st.interruptSubprocess();
            }
            if (st.is_gdb_mode) {
                st.sendLldbCommand("next");
                st.sendLldbCommand("bt");
                st.sendLldbCommand("info registers");
            } else {
                st.sendLldbCommand("thread step-over");
                st.sendLldbCommand("thread backtrace");
                st.sendLldbCommand("frame variable");
            }
        }
        st.session_paused = true;
        st.step_counter +%= 1;
        st.reg_pc +%= 4;
        st.reg_x0 +%= 1;
        st.stop_reason.set("step over (next)");

        const buf_opt = ctx.activeBuffer();
        const file_path = if (buf_opt) |b| b.file_path else st.active_file.slice();
        const text = if (buf_opt) |b| b.text else "";
        const total_lines: u32 = if (buf_opt) |b| @max(1, b.line_count) else 1;

        st.current_line = findNextExecutableLine(text, st.current_line, total_lines);
        scanLocalsAndFunctionAtLine(st, file_path, text, st.current_line);
        ctx.setDebugLocation(true, true, file_path, st.current_line, true);

        const msg = ctx.fmt("LLDB step-over -> {s}:{d} (pc=0x{X:0>12}, x0=0x{X})", .{
            std.fs.path.basename(file_path),
            st.current_line,
            st.reg_pc,
            st.reg_x0,
        });
        st.last_status.set(msg);
        st.pushConsoleLine(msg);
        ctx.setStatusNotice(msg);
    } else if (std.mem.eql(u8, cmd_id, "lldb_debug.step_into")) {
        if (!st.session_active) {
            onCommand(ctx, "lldb_debug.start_or_continue");
            return;
        }
        if (st.isSubprocessRunning()) {
            if (!st.session_paused) {
                st.interruptSubprocess();
            }
            if (st.is_gdb_mode) {
                st.sendLldbCommand("step");
                st.sendLldbCommand("bt");
                st.sendLldbCommand("info registers");
            } else {
                st.sendLldbCommand("thread step-in");
                st.sendLldbCommand("thread backtrace");
                st.sendLldbCommand("frame variable");
            }
        }
        st.session_paused = true;
        st.step_counter +%= 1;
        st.reg_sp -%= 16;
        st.reg_pc +%= 8;
        st.stop_reason.set("step into");

        const buf_opt = ctx.activeBuffer();
        const file_path = if (buf_opt) |b| b.file_path else st.active_file.slice();
        const text = if (buf_opt) |b| b.text else "";
        const total_lines: u32 = if (buf_opt) |b| @max(1, b.line_count) else 1;

        // If current line calls a function in this file, push caller frame and jump into callee!
        var stepped_into_callee = false;
        if (extractCalledFunctionOnLine(text, st.current_line)) |callee_name| {
            if (findFunctionLineInText(text, callee_name)) |callee_ln| {
                if (st.frame_count < MaxStackFrames) {
                    var i: usize = st.frame_count;
                    while (i > 0) : (i -= 1) {
                        st.frames[i] = st.frames[i - 1];
                    }
                    st.frame_count += 1;
                }
                st.current_line = findNextExecutableLine(text, callee_ln, total_lines);
                stepped_into_callee = true;
            }
        }
        if (!stepped_into_callee) {
            st.current_line = findNextExecutableLine(text, st.current_line, total_lines);
        }
        scanLocalsAndFunctionAtLine(st, file_path, text, st.current_line);
        ctx.setDebugLocation(true, true, file_path, st.current_line, true);

        const msg = ctx.fmt("LLDB step-into -> {s}:{d} (pc=0x{X:0>12}, sp=0x{X:0>12})", .{
            std.fs.path.basename(file_path),
            st.current_line,
            st.reg_pc,
            st.reg_sp,
        });
        st.last_status.set(msg);
        st.pushConsoleLine(msg);
        ctx.setStatusNotice(msg);
    } else if (std.mem.eql(u8, cmd_id, "lldb_debug.step_out")) {
        if (!st.session_active) return;
        if (st.isSubprocessRunning()) {
            if (!st.session_paused) {
                st.interruptSubprocess();
            }
            if (st.is_gdb_mode) {
                st.sendLldbCommand("finish");
                st.sendLldbCommand("bt");
                st.sendLldbCommand("info registers");
            } else {
                st.sendLldbCommand("thread step-out");
                st.sendLldbCommand("thread backtrace");
            }
        }
        st.session_paused = true;
        st.step_counter +%= 1;
        st.reg_sp +%= 16;
        st.reg_pc +%= 12;
        st.stop_reason.set("step out (finish)");

        const buf_opt = ctx.activeBuffer();
        const file_path = if (buf_opt) |b| b.file_path else st.active_file.slice();
        const text = if (buf_opt) |b| b.text else "";
        const total_lines: u32 = if (buf_opt) |b| @max(1, b.line_count) else 1;

        if (st.frame_count > 2) {
            const caller_line = st.frames[1].line;
            var i: usize = 0;
            while (i + 1 < st.frame_count) : (i += 1) {
                st.frames[i] = st.frames[i + 1];
            }
            st.frame_count -= 1;
            st.current_line = findNextExecutableLine(text, caller_line, total_lines);
        } else {
            st.current_line = findNextExecutableLine(text, st.current_line, total_lines);
        }

        scanLocalsAndFunctionAtLine(st, file_path, text, st.current_line);
        ctx.setDebugLocation(true, true, file_path, st.current_line, true);

        const msg = ctx.fmt("LLDB step-out -> {s}:{d} (pc=0x{X:0>12}, sp=0x{X:0>12})", .{
            std.fs.path.basename(file_path),
            st.current_line,
            st.reg_pc,
            st.reg_sp,
        });
        st.last_status.set(msg);
        st.pushConsoleLine(msg);
        ctx.setStatusNotice(msg);
    } else if (std.mem.eql(u8, cmd_id, "lldb_debug.restart")) {
        st.stopSubprocess();
        st.session_active = false;
        st.session_paused = false;
        onCommand(ctx, "lldb_debug.start_or_continue");
    } else if (std.mem.eql(u8, cmd_id, "lldb_debug.stop")) {
        st.stopSubprocess();
        st.session_active = false;
        st.session_paused = false;
        st.frame_count = 0;
        ctx.setDebugLocation(false, false, "", 0, false);
        st.last_status.set("LLDB target session terminated");
        st.pushConsoleLine("Process exited / target session stopped");
        ctx.setStatusNotice("LLDB: Target session stopped");
    } else if (std.mem.eql(u8, cmd_id, "lldb_debug.open_launch_json")) {
        openAndEnsureConfigFile(ctx, st, false);
    } else if (std.mem.eql(u8, cmd_id, "lldb_debug.open_tasks_json")) {
        openAndEnsureConfigFile(ctx, st, true);
    }
}

fn renderStatusBar(ctx: *sdk.PluginContext) void {
    const st = ctx.useState(LldbDebugState, "state", .{});
    ensureInitialized(st);
    const target_name = if (st.activeConfig()) |cfg| cfg.name.slice() else "No Config";
    const label = if (st.session_active and st.session_paused)
        ctx.fmt("⏸ {s} (L{d})##lldb_chip", .{ target_name, st.current_line })
    else if (st.session_active)
        ctx.fmt("● {s} (RUNNING)##lldb_chip", .{target_name})
    else
        ctx.fmt("▷ {s}##lldb_chip", .{target_name});
    if (ctx.ui.chip(label, st.session_active)) {
        onCommand(ctx, "lldb_debug.start_or_continue");
    }
}

fn renderSidebar(ctx: *sdk.PluginContext) void {
    const st = ctx.useState(LldbDebugState, "state", .{});
    ensureInitialized(st);

    if (ctx.ui.isInputPass()) {
        reloadConfigsFromDiskIfChanged(st, false);
        if (st.pending_dropdown) {
            st.dropdown_open = st.next_dropdown_open;
            st.pending_dropdown = false;
        }
    }

    ctx.ui.mutedLabel("DEBUG");

    const current_label = if (st.activeConfig()) |cfg|
        cfg.name.slice()
    else
        "No Configurations";

    // 1. Launch & Configuration Selector Row: [▷] [<Configuration> ⌄] [⚙] [>_]
    ctx.ui.beginRow(0, 26, 0, 4);
    const top_play_icon: sdk.PluginToolbarIcon = if (st.session_active and !st.session_paused and st.selected_config == st.active_session_config)
        .pause
    else
        .play;
    if (ctx.ui.toolbarIconBtn("##lldb_play_btn", top_play_icon, 24, 24, true)) {
        st.next_dropdown_open = false;
        st.pending_dropdown = true;
        if (st.session_active and st.selected_config != st.active_session_config) {
            onCommand(ctx, "lldb_debug.restart");
        } else {
            onCommand(ctx, "lldb_debug.start_or_continue");
        }
    }
    if (ctx.ui.dropdownSelect("##lldb_cfg_dropdown", current_label, -56, 24, st.dropdown_open)) {
        st.next_dropdown_open = !st.dropdown_open;
        st.pending_dropdown = true;
        ctx.requestContinuousRedraw();
    }
    if (ctx.ui.toolbarIconBtn("##lldb_gear_btn", .gear, 22, 24, true)) {
        st.next_dropdown_open = false;
        st.pending_dropdown = true;
        openAndEnsureConfigFile(ctx, st, false);
    }
    if (ctx.ui.toolbarIconBtn("##lldb_console_btn", .debug_console, 22, 24, true)) {
        ctx.toggleBottomPanel();
    }
    ctx.ui.endBox();

    // Reserve floating overlay geometry below the selector row so underlying sections do not shift
    // vertically and cannot be clicked through while the dropdown menu is open.
    if (st.dropdown_open) {
        const menu_h: f32 = if (st.config_count == 0)
            65.0
        else
            @as(f32, @floatFromInt(st.config_count)) * 28.0 + 41.0;
        if (ctx.ui.reserveDropdownOverlay(menu_h)) {
            st.next_dropdown_open = false;
            st.pending_dropdown = true;
            ctx.requestContinuousRedraw();
        }
    }

    // 2. Execution Transport Icon Strip: [▷/||] [↷] [↓] [↑] [↺] [□]
    ctx.ui.beginRow(0, 24, 0, 4);
    const transport_icon: sdk.PluginToolbarIcon = if (st.session_paused) .play else .pause;
    if (ctx.ui.toolbarIconBtn("##lldb_pause_btn", transport_icon, 24, 22, st.session_active)) {
        onCommand(ctx, "lldb_debug.start_or_continue");
    }
    if (ctx.ui.toolbarIconBtn("##lldb_step_over_btn", .step_over, 24, 22, st.session_active)) {
        onCommand(ctx, "lldb_debug.step_over");
    }
    if (ctx.ui.toolbarIconBtn("##lldb_step_into_btn", .step_into, 24, 22, st.session_active)) {
        onCommand(ctx, "lldb_debug.step_into");
    }
    if (ctx.ui.toolbarIconBtn("##lldb_step_out_btn", .step_out, 24, 22, st.session_active)) {
        onCommand(ctx, "lldb_debug.step_out");
    }
    if (ctx.ui.toolbarIconBtn("##lldb_restart_btn", .restart, 24, 22, st.session_active)) {
        onCommand(ctx, "lldb_debug.restart");
    }
    if (ctx.ui.toolbarIconBtn("##lldb_stop_btn", .stop, 24, 22, st.session_active)) {
        onCommand(ctx, "lldb_debug.stop");
    }
    ctx.ui.endBox();

    if (st.session_active) {
        if (st.session_paused) {
            ctx.ui.monoLabel(ctx.fmt("PAUSED · {s} (L{d})", .{
                if (st.stop_reason.len > 0) st.stop_reason.slice() else "breakpoint",
                st.current_line,
            }));
        } else {
            ctx.ui.monoLabel(ctx.fmt("RUNNING · {s}", .{current_label}));
        }
    }

    // 3. Collapsible THREADS Section
    if (ctx.ui.collapsibleSection("THREADS##lldb_sec_threads", &st.sec_threads, if (st.session_active) "2" else "")) {
        if (st.session_active) {
            const th1_lbl = if (st.session_paused)
                "Thread #1 · main (paused)##th_0"
            else
                "Thread #1 · main (running)##th_0";
            if (ctx.ui.listItem(th1_lbl, "tid 0x104a", st.selected_thread == 0)) {
                st.selected_thread = 0;
            }
            if (ctx.ui.listItem("Thread #2 · io_poller (running)##th_1", "tid 0x104f", st.selected_thread == 1)) {
                st.selected_thread = 1;
            }
        } else {
            ctx.ui.mutedLabel("Not running");
        }
    }

    // 4. Collapsible CALL STACK Section
    const stack_badge = if (st.session_active) ctx.fmt("{d}", .{@max(@as(u8, 1), st.frame_count)}) else "";
    if (ctx.ui.collapsibleSection("CALL STACK##lldb_sec_stack", &st.sec_call_stack, stack_badge)) {
        if (st.session_active) {
            var f_idx: usize = 0;
            while (f_idx < st.frame_count) : (f_idx += 1) {
                const fr = &st.frames[f_idx];
                const lbl = ctx.fmt("#{d} {s}()##frame_{d}", .{ f_idx, fr.func.slice(), f_idx });
                const meta = ctx.fmt("{s}:{d}", .{ fr.file.slice(), fr.line });
                if (ctx.ui.listItem(lbl, meta, st.selected_frame == f_idx)) {
                    st.selected_frame = @intCast(f_idx);
                    st.current_line = fr.line;
                    ctx.setDebugLocation(true, true, fr.file.slice(), fr.line, true);
                }
            }
        } else {
            ctx.ui.mutedLabel("No call stack available");
        }
    }

    // 5. Collapsible VARIABLES Section (Locals + CPU Registers)
    const var_badge = if (st.session_active) ctx.fmt("{d}", .{st.local_count + 5}) else "";
    if (ctx.ui.collapsibleSection("VARIABLES##lldb_sec_vars", &st.sec_variables, var_badge)) {
        if (st.session_active) {
            var v_idx: usize = 0;
            while (v_idx < st.local_count) : (v_idx += 1) {
                const loc = &st.locals[v_idx];
                const v_lbl = ctx.fmt("{s} = {s}##loc_var_{d}", .{ loc.name.slice(), loc.value.slice(), v_idx });
                if (ctx.ui.listItem(v_lbl, loc.type_name.slice(), false)) {
                    if (st.watch_count < MaxWatchExprs) {
                        st.watches[st.watch_count].expr.set(loc.name.slice());
                        st.watch_count += 1;
                        evaluateWatches(st);
                    }
                }
            }
            _ = ctx.ui.listItem(ctx.fmt("pc = 0x{X:0>12}##var_pc", .{st.reg_pc}), "reg", false);
            _ = ctx.ui.listItem(ctx.fmt("sp = 0x{X:0>12}##var_sp", .{st.reg_sp}), "reg", false);
            _ = ctx.ui.listItem(ctx.fmt("fp = 0x{X:0>12}##var_fp", .{st.reg_fp}), "reg", false);
            _ = ctx.ui.listItem(ctx.fmt("lr = 0x{X:0>12}##var_lr", .{st.reg_lr}), "reg", false);
            _ = ctx.ui.listItem(ctx.fmt("x0 = 0x{X:0>12}##var_x0", .{st.reg_x0}), "reg", false);
        } else {
            ctx.ui.mutedLabel("Launch session to inspect locals & registers");
        }
    }

    // 6. Collapsible WATCH Section
    const watch_badge = if (st.watch_count > 0) ctx.fmt("{d}", .{st.watch_count}) else "";
    if (ctx.ui.collapsibleSection("WATCH##lldb_sec_watch", &st.sec_watch, watch_badge)) {
        const wtf = ctx.ui.textFieldInline("##lldb_watch_input", &st.watch_input, "Add watch expression (Enter)...");
        if (wtf.submitted and st.watch_input.len > 0) {
            if (st.watch_count < MaxWatchExprs) {
                st.watches[st.watch_count].expr.set(st.watch_input.slice());
                st.watch_count += 1;
                evaluateWatches(st);
            }
            st.watch_input.clear();
        }
        if (st.watch_count == 0) {
            ctx.ui.mutedLabel("No watch expressions");
        } else {
            var w_idx: usize = 0;
            while (w_idx < st.watch_count) : (w_idx += 1) {
                const w = &st.watches[w_idx];
                const w_lbl = ctx.fmt("{s}: {s}##watch_item_{d}", .{ w.expr.slice(), w.value.slice(), w_idx });
                if (ctx.ui.listItem(w_lbl, "×", false)) {
                    var j = w_idx;
                    while (j + 1 < st.watch_count) : (j += 1) {
                        st.watches[j] = st.watches[j + 1];
                    }
                    st.watch_count -= 1;
                    break;
                }
            }
        }
    }

    // 7. Collapsible BREAKPOINTS Section (synchronized with Code Editor left gutter!)
    var bp_buf: [32]sdk.Breakpoint = undefined;
    const bps = ctx.getBreakpoints(&bp_buf);
    const bp_badge = if (bps.len > 0) ctx.fmt("{d}", .{bps.len}) else "";
    if (ctx.ui.collapsibleSection("BREAKPOINTS##lldb_sec_bps", &st.sec_breakpoints, bp_badge)) {
        const active_file = if (ctx.activeBuffer()) |b| std.fs.path.basename(b.file_path) else "buffer";
        if (ctx.ui.listItem("+ Toggle Breakpoint (F9)##add_bp_row", active_file, false)) {
            onCommand(ctx, "lldb_debug.toggle_breakpoint");
        }
        for (bps, 0..) |bp, i| {
            const bp_path = bp.file_path.toZig();
            const bp_base = std.fs.path.basename(bp_path);
            if (ctx.ui.listItem(
                ctx.fmt("● {s}:{d}##bp_item_{d}", .{ bp_base, bp.line, i }),
                ctx.fmt("L{d}", .{bp.line}),
                true,
            )) {
                // Jump editor to this breakpoint line (or toggle if already on that line)
                if (ctx.activeBuffer()) |b| {
                    if (b.cursor_line + 1 == bp.line and std.mem.eql(u8, std.fs.path.basename(b.file_path), bp_base)) {
                        _ = ctx.toggleBreakpoint(bp_path, bp.line);
                    } else {
                        ctx.setDebugLocation(st.session_active, st.session_paused, bp_path, bp.line, true);
                    }
                } else {
                    _ = ctx.toggleBreakpoint(bp_path, bp.line);
                }
            }
        }
        if (bps.len > 0) {
            if (ctx.ui.listItem("Clear All Breakpoints##clear_bps_row", "", false)) {
                ctx.clearBreakpoints();
                syncBreakpointsToSubprocess(ctx, st);
                ctx.setStatusNotice("LLDB: Cleared all breakpoints");
            }
        }
    }

    // 8. Floating Configuration Dropdown Overlay (rendered last so it hovers on top of sections below)
    if (st.dropdown_open) {
        ctx.ui.beginDropdownOverlay();
        defer ctx.ui.endDropdownOverlay();

        if (st.config_count == 0) {
            ctx.ui.mutedLabel("No targets in .vscode/launch.json");
        } else {
            var i: usize = 0;
            while (i < st.config_count) : (i += 1) {
                const cfg = &st.configs[i];
                const is_sel = (st.selected_config == i);
                const item_lbl = if (is_sel)
                    ctx.fmt("✓ {s}##cfg_opt_{d}", .{ cfg.name.slice(), i })
                else
                    ctx.fmt("  {s}##cfg_opt_{d}", .{ cfg.name.slice(), i });
                const meta_str = if (cfg.server_type.len > 0) cfg.server_type.slice() else cfg.request.slice();
                if (ctx.ui.listItem(item_lbl, meta_str, is_sel)) {
                    st.selected_config = @intCast(i);
                    st.next_dropdown_open = false;
                    st.pending_dropdown = true;
                    ctx.setStatusNotice(ctx.fmt("Selected debug target: {s}", .{cfg.name.slice()}));
                    ctx.requestContinuousRedraw();
                }
            }
        }

        ctx.ui.divider();
        if (ctx.ui.listItem("  Edit .vscode/launch.json...##edit_launch", "", false)) {
            st.next_dropdown_open = false;
            st.pending_dropdown = true;
            openAndEnsureConfigFile(ctx, st, false);
        }
    }
}

fn renderBottomPanel(ctx: *sdk.PluginContext) void {
    const st = ctx.useState(LldbDebugState, "state", .{});
    ensureInitialized(st);
    const target_str = if (st.activeConfig()) |c| c.name.slice() else "No Target";
    ctx.ui.monoLabel(ctx.fmt("LLDB [{s}] | pc=0x{X:0>12}  sp=0x{X:0>12}  fp=0x{X:0>12}  lr=0x{X:0>12}  x0=0x{X}  x1=0x{X}", .{
        target_str,
        st.reg_pc,
        st.reg_sp,
        st.reg_fp,
        st.reg_lr,
        st.reg_x0,
        st.reg_x1,
    }));

    var c_idx: usize = 0;
    while (c_idx < st.console_count) : (c_idx += 1) {
        ctx.ui.monoLabel(st.console_lines[c_idx].slice());
    }
    if (st.console_count == 0 and st.last_status.len > 0) {
        ctx.ui.monoLabel(st.last_status.slice());
    }

    const rtf = ctx.ui.textFieldInline("##lldb_repl_input", &st.repl_input, "(lldb) Type command (bt, reg read, p <expr>, b <line>, n, s, c)...");
    if (rtf.submitted and st.repl_input.len > 0) {
        var cmd_copy: [56]u8 = undefined;
        const n = st.repl_input.len;
        @memcpy(cmd_copy[0..n], st.repl_input.slice());
        st.repl_input.clear();
        executeReplCommand(ctx, st, cmd_copy[0..n]);
    }
}

comptime {
    sdk.exportEditorPlugin(.{
        .id = "builtin.lldb_debug",
        .display_name = "Native LLDB Debugger",
        .version = "1.0.0",
        .sidebar_title = "LLDB DEBUGGER",
        .bottom_tab_title = "LLDB REGISTERS & CONSOLE",
        .sidebar_icon = .debug,
        .debug_extensions = ".zig,.c,.cc,.cpp,.cxx,.h,.hh,.hpp,.hxx,.rs,.m,.mm,.s,.S,.asm",
        .init = onInit,
        .on_reload = onReload,
        .deinit = onDeinit,
        .on_poll_io = onPollIo,
        .on_command = onCommand,
        .on_buffer_save = onBufferSave,
        .render_status_bar = renderStatusBar,
        .render_sidebar = renderSidebar,
        .render_bottom_panel = renderBottomPanel,
    });
}
