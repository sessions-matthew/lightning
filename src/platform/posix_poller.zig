//! Reusable, non-blocking Subprocess & Pipe Poller (`src/platform/posix_poller.zig`).
//! Spawns child processes in non-blocking pipes and drains stdout into a fixed buffer
//! incrementally during `Pass.input` without stalling the 120 FPS UI thread.
//! Retains native POSIX `pipe`/`fork`/`poll` on macOS and uses Win32 `CreatePipe`/`PeekNamedPipe`/`CreateProcessA` on Windows.

const std = @import("std");
const builtin = @import("builtin");
const is_windows = (builtin.os.tag == .windows);

const posix_c = struct {
    extern "c" fn pipe(fds: *[2]c_int) c_int;
    extern "c" fn fork() c_int;
    extern "c" fn dup2(oldfd: c_int, newfd: c_int) c_int;
    extern "c" fn execv(path: [*:0]const u8, argv: [*:null]const ?[*:0]const u8) c_int;
};

const win32_proc = struct {
    pub const HANDLE = *anyopaque;
    pub const DWORD = u32;
    pub const BOOL = c_int;
    pub const HANDLE_FLAG_INHERIT: DWORD = 0x00000001;
    pub const STARTF_USESTDHANDLES: DWORD = 0x00000100;
    pub const CREATE_NO_WINDOW: DWORD = 0x08000000;
    pub const WAIT_OBJECT_0: DWORD = 0x00000000;

    pub const SECURITY_ATTRIBUTES = extern struct {
        nLength: DWORD = @sizeOf(SECURITY_ATTRIBUTES),
        lpSecurityDescriptor: ?*anyopaque = null,
        bInheritHandle: BOOL = 1,
    };

    pub const STARTUPINFOA = extern struct {
        cb: DWORD = @sizeOf(STARTUPINFOA),
        lpReserved: ?[*:0]u8 = null,
        lpDesktop: ?[*:0]u8 = null,
        lpTitle: ?[*:0]u8 = null,
        dwX: DWORD = 0,
        dwY: DWORD = 0,
        dwXSize: DWORD = 0,
        dwYSize: DWORD = 0,
        dwXCountChars: DWORD = 0,
        dwYCountChars: DWORD = 0,
        dwFillAttribute: DWORD = 0,
        dwFlags: DWORD = 0,
        wShowWindow: u16 = 0,
        cbReserved2: u16 = 0,
        lpReserved2: ?*u8 = null,
        hStdInput: ?HANDLE = null,
        hStdOutput: ?HANDLE = null,
        hStdError: ?HANDLE = null,
    };

    pub const PROCESS_INFORMATION = extern struct {
        hProcess: ?HANDLE = null,
        hThread: ?HANDLE = null,
        dwProcessId: DWORD = 0,
        dwThreadId: DWORD = 0,
    };

    extern "kernel32" fn CreatePipe(hReadPipe: *?HANDLE, hWritePipe: *?HANDLE, lpPipeAttributes: *const SECURITY_ATTRIBUTES, nSize: DWORD) callconv(.winapi) BOOL;
    extern "kernel32" fn SetHandleInformation(hObject: HANDLE, dwMask: DWORD, dwFlags: DWORD) callconv(.winapi) BOOL;
    extern "kernel32" fn CreateProcessA(
        lpApplicationName: ?[*:0]const u8,
        lpCommandLine: [*:0]u8,
        lpProcessAttributes: ?*anyopaque,
        lpThreadAttributes: ?*anyopaque,
        bInheritHandles: BOOL,
        dwCreationFlags: DWORD,
        lpEnvironment: ?*anyopaque,
        lpCurrentDirectory: ?[*:0]const u8,
        lpStartupInfo: *const STARTUPINFOA,
        lpProcessInformation: *PROCESS_INFORMATION,
    ) callconv(.winapi) BOOL;
    extern "kernel32" fn PeekNamedPipe(
        hNamedPipe: HANDLE,
        lpBuffer: ?*anyopaque,
        nBufferSize: DWORD,
        lpBytesRead: ?*DWORD,
        lpTotalBytesAvail: ?*DWORD,
        lpBytesLeftThisMessage: ?*DWORD,
    ) callconv(.winapi) BOOL;
    extern "kernel32" fn ReadFile(
        hFile: HANDLE,
        lpBuffer: [*]u8,
        nNumberOfBytesToRead: DWORD,
        lpNumberOfBytesRead: *DWORD,
        lpOverlapped: ?*anyopaque,
    ) callconv(.winapi) BOOL;
    extern "kernel32" fn WaitForSingleObject(hHandle: HANDLE, dwMilliseconds: DWORD) callconv(.winapi) DWORD;
    extern "kernel32" fn TerminateProcess(hProcess: HANDLE, uExitCode: c_uint) callconv(.winapi) BOOL;
    extern "kernel32" fn CloseHandle(hObject: HANDLE) callconv(.winapi) BOOL;
};

const F_GETFL: c_int = 3;
const F_SETFL: c_int = 4;
const O_NONBLOCK: c_int = if (builtin.os.tag == .linux) 0x0800 else 0x0004;
const WNOHANG: c_int = 1;
const EAGAIN: c_int = if (builtin.os.tag == .linux) 11 else 35;
const EINTR: c_int = 4;

const POLLIN: i16 = 0x0001;
const POLLHUP: i16 = 0x0010;
const POLLERR: i16 = 0x0008;

const PollFd = extern struct {
    fd: c_int,
    events: i16,
    revents: i16,
};

const c_poll = struct {
    extern "c" fn poll(fds: [*]PollFd, nfds: c_uint, timeout: c_int) c_int;
};

pub fn SubprocessPoller(comptime capacity: usize) type {
    return struct {
        fd: c_int = -1,
        child_pid: c_int = -1,
        win_pipe: ?*anyopaque = null,
        win_proc: ?*anyopaque = null,
        zombie_pids: [8]c_int = @splat(-1),
        buf: [capacity]u8 = undefined,
        len: usize = 0,
        pending_cmd: [512:0]u8 = @splat(0),
        pending_len: usize = 0,

        const Self = @This();

        fn reapZombies(self: *Self) void {
            if (comptime is_windows) return;
            for (&self.zombie_pids) |*zpid| {
                if (zpid.* > 0) {
                    const rc = std.c.waitpid(zpid.*, null, WNOHANG);
                    if (rc != 0) {
                        zpid.* = -1;
                    }
                }
            }
        }

        fn retireChildPid(self: *Self, pid: c_int) void {
            if (comptime is_windows) return;
            if (pid <= 0) return;
            if (std.c.waitpid(pid, null, WNOHANG) != 0) return;
            for (&self.zombie_pids) |*zpid| {
                if (zpid.* <= 0) {
                    zpid.* = pid;
                    return;
                }
            }
        }

        pub fn isBusy(self: *const Self) bool {
            if (comptime is_windows) {
                return self.win_pipe != null or self.pending_len > 0;
            }
            return self.fd >= 0 or self.pending_len > 0;
        }

        /// Cheaply probes whether the active subprocess pipe (`fd`) has readable bytes or EOF
        /// ready without blocking (`poll` with `0` timeout).
        pub fn hasPendingData(self: *const Self) bool {
            if (comptime is_windows) {
                const pipe_h = self.win_pipe orelse return false;
                var avail: win32_proc.DWORD = 0;
                if (win32_proc.PeekNamedPipe(pipe_h, null, 0, null, &avail, null) == 0) {
                    return true; // Broken pipe / EOF
                }
                if (avail > 0) return true;
                if (self.win_proc) |proc_h| {
                    if (win32_proc.WaitForSingleObject(proc_h, 0) == win32_proc.WAIT_OBJECT_0) {
                        return true;
                    }
                }
                return false;
            } else {
                if (self.fd < 0) return false;
                var pfd = [1]PollFd{.{
                    .fd = self.fd,
                    .events = POLLIN,
                    .revents = 0,
                }};
                const rc = c_poll.poll(&pfd, 1, 0);
                return rc > 0 and (pfd[0].revents & (POLLIN | POLLHUP | POLLERR)) != 0;
            }
        }

        pub fn deinit(self: *Self) void {
            if (comptime is_windows) {
                if (self.win_pipe) |pipe_h| {
                    _ = win32_proc.CloseHandle(pipe_h);
                    self.win_pipe = null;
                }
                if (self.win_proc) |proc_h| {
                    _ = win32_proc.TerminateProcess(proc_h, 1);
                    _ = win32_proc.CloseHandle(proc_h);
                    self.win_proc = null;
                }
                self.len = 0;
                self.pending_len = 0;
            } else {
                if (self.fd >= 0) {
                    _ = std.c.close(self.fd);
                    self.fd = -1;
                }
                if (self.child_pid > 0) {
                    _ = std.c.kill(self.child_pid, std.posix.SIG.TERM);
                    self.retireChildPid(self.child_pid);
                    self.child_pid = -1;
                }
                self.reapZombies();
                self.len = 0;
                self.pending_len = 0;
            }
        }

        pub fn request(self: *Self, cmd: []const u8) void {
            self.reapZombies();
            if (cmd.len == 0 or cmd.len >= self.pending_cmd.len) return;
            if (comptime is_windows) {
                if (self.win_pipe != null or self.win_proc != null) {
                    @memcpy(self.pending_cmd[0..cmd.len], cmd);
                    self.pending_cmd[cmd.len] = 0;
                    self.pending_len = cmd.len;
                    return;
                }
            } else {
                if (self.fd >= 0 or self.child_pid > 0) {
                    @memcpy(self.pending_cmd[0..cmd.len], cmd);
                    self.pending_cmd[cmd.len] = 0;
                    self.pending_len = cmd.len;
                    return;
                }
            }
            self.startSpawn(cmd);
        }

        fn startSpawn(self: *Self, cmd: []const u8) void {
            self.len = 0;
            if (comptime is_windows) {
                var sa = win32_proc.SECURITY_ATTRIBUTES{};
                var rd_h: ?win32_proc.HANDLE = null;
                var wr_h: ?win32_proc.HANDLE = null;
                if (win32_proc.CreatePipe(&rd_h, &wr_h, &sa, 0) == 0) return;
                _ = win32_proc.SetHandleInformation(rd_h.?, win32_proc.HANDLE_FLAG_INHERIT, 0);

                var cmd_line: [600:0]u8 = @splat(0);
                const full = std.fmt.bufPrint(&cmd_line, "cmd.exe /C {s}", .{cmd}) catch {
                    _ = win32_proc.CloseHandle(rd_h.?);
                    _ = win32_proc.CloseHandle(wr_h.?);
                    return;
                };
                cmd_line[full.len] = 0;

                var si = win32_proc.STARTUPINFOA{
                    .dwFlags = win32_proc.STARTF_USESTDHANDLES,
                    .hStdInput = null,
                    .hStdOutput = wr_h,
                    .hStdError = null,
                };
                var pi = win32_proc.PROCESS_INFORMATION{};
                const ok = win32_proc.CreateProcessA(
                    null,
                    &cmd_line,
                    null,
                    null,
                    1,
                    win32_proc.CREATE_NO_WINDOW,
                    null,
                    null,
                    &si,
                    &pi,
                );
                _ = win32_proc.CloseHandle(wr_h.?);
                if (ok == 0) {
                    _ = win32_proc.CloseHandle(rd_h.?);
                    return;
                }
                if (pi.hThread) |th| _ = win32_proc.CloseHandle(th);
                self.win_pipe = rd_h;
                self.win_proc = pi.hProcess;
                self.pending_len = 0;
            } else {
                var fds: [2]c_int = .{ -1, -1 };
                if (posix_c.pipe(&fds) != 0) return;

                const pid = posix_c.fork();
                if (pid < 0) {
                    _ = std.c.close(fds[0]);
                    _ = std.c.close(fds[1]);
                    return;
                }

                if (pid == 0) {
                    _ = std.c.close(fds[0]);
                    _ = posix_c.dup2(fds[1], 1);
                    _ = std.c.close(fds[1]);
                    const devnull = std.c.open("/dev/null", .{ .ACCMODE = .WRONLY }, @as(c_uint, 0));
                    if (devnull >= 0) {
                        _ = posix_c.dup2(devnull, 2);
                        _ = std.c.close(devnull);
                    }

                    var cmd_z: [512:0]u8 = @splat(0);
                    const clen = @min(cmd.len, cmd_z.len - 1);
                    @memcpy(cmd_z[0..clen], cmd[0..clen]);
                    cmd_z[clen] = 0;

                    const argv = [_:null]?[*:0]const u8{ "/bin/sh", "-c", &cmd_z };
                    _ = posix_c.execv("/bin/sh", &argv);
                    std.c._exit(1);
                }

                _ = std.c.close(fds[1]);
                const flags = std.c.fcntl(fds[0], F_GETFL, @as(c_int, 0));
                if (flags >= 0) {
                    _ = std.c.fcntl(fds[0], F_SETFL, flags | O_NONBLOCK);
                }
                self.fd = fds[0];
                self.child_pid = pid;
                self.pending_len = 0;
            }
        }

        /// Polls the non-blocking pipe. Returns the accumulated payload slice when the child completes,
        /// or `null` if still in flight or idle.
        pub fn poll(self: *Self) ?[]const u8 {
            self.reapZombies();
            if (comptime is_windows) {
                if (self.win_pipe == null) {
                    if (self.pending_len > 0) {
                        const plen = self.pending_len;
                        self.pending_len = 0;
                        self.startSpawn(self.pending_cmd[0..plen]);
                    }
                    if (self.win_pipe == null) return null;
                }

                const pipe_h = self.win_pipe.?;
                while (self.len < self.buf.len) {
                    var avail: win32_proc.DWORD = 0;
                    if (win32_proc.PeekNamedPipe(pipe_h, null, 0, null, &avail, null) == 0) {
                        return self.finish();
                    }
                    if (avail == 0) {
                        if (self.win_proc) |proc_h| {
                            if (win32_proc.WaitForSingleObject(proc_h, 0) == win32_proc.WAIT_OBJECT_0) {
                                return self.finish();
                            }
                        }
                        return null;
                    }
                    const rem = self.buf[self.len..];
                    const to_read: win32_proc.DWORD = @intCast(@min(rem.len, @as(usize, avail)));
                    var bytes_read: win32_proc.DWORD = 0;
                    if (win32_proc.ReadFile(pipe_h, rem.ptr, to_read, &bytes_read, null) == 0 or bytes_read == 0) {
                        return self.finish();
                    }
                    self.len += @intCast(bytes_read);
                }
                return self.finish();
            } else {
                if (self.fd < 0) {
                    if (self.pending_len > 0) {
                        const plen = self.pending_len;
                        self.pending_len = 0;
                        self.startSpawn(self.pending_cmd[0..plen]);
                    }
                    if (self.fd < 0) return null;
                }

                while (self.len < self.buf.len) {
                    const rem = self.buf[self.len..];
                    const n = std.c.read(self.fd, rem.ptr, rem.len);
                    if (n > 0) {
                        self.len += @intCast(n);
                        continue;
                    }
                    if (n == 0) {
                        // EOF reached
                        return self.finish();
                    }
                    const err = std.c._errno().*;
                    if (err == EAGAIN or err == EINTR) {
                        return null;
                    }
                    self.deinit();
                    return null;
                }

                return self.finish();
            }
        }

        fn finish(self: *Self) []const u8 {
            if (comptime is_windows) {
                if (self.win_pipe) |pipe_h| {
                    _ = win32_proc.CloseHandle(pipe_h);
                    self.win_pipe = null;
                }
                if (self.win_proc) |proc_h| {
                    _ = win32_proc.CloseHandle(proc_h);
                    self.win_proc = null;
                }
            } else {
                if (self.fd >= 0) {
                    _ = std.c.close(self.fd);
                    self.fd = -1;
                }
                if (self.child_pid > 0) {
                    self.retireChildPid(self.child_pid);
                    self.child_pid = -1;
                }
                self.reapZombies();
            }
            const payload = self.buf[0..self.len];
            self.len = 0;

            if (self.pending_len > 0) {
                const plen = self.pending_len;
                self.pending_len = 0;
                self.startSpawn(self.pending_cmd[0..plen]);
            }

            return payload;
        }
    };
}

test "SubprocessPoller: request and poll echo output" {
    var poller = SubprocessPoller(256){};
    defer poller.deinit();

    poller.request("printf 'poller_test_output'");
    try std.testing.expect(poller.isBusy());

    var result: ?[]const u8 = null;
    var attempts: usize = 0;
    while (attempts < 1000) : (attempts += 1) {
        if (poller.poll()) |payload| {
            result = payload;
            break;
        }
        const ts = std.c.timespec{ .sec = 0, .nsec = 1_000_000 };
        _ = std.c.nanosleep(&ts, null);
    }

    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("poller_test_output", result.?);
}

test "SubprocessPoller: hasPendingData non-blocking readiness probe" {
    var poller = SubprocessPoller(256){};
    defer poller.deinit();

    try std.testing.expect(!poller.hasPendingData());

    poller.request("printf 'ready_probe_bytes'");
    try std.testing.expect(poller.isBusy());

    var saw_pending = false;
    var attempts: usize = 0;
    while (attempts < 1000) : (attempts += 1) {
        if (poller.hasPendingData()) {
            saw_pending = true;
            break;
        }
        const ts = std.c.timespec{ .sec = 0, .nsec = 1_000_000 };
        _ = std.c.nanosleep(&ts, null);
    }
    try std.testing.expect(saw_pending);

    var payload: ?[]const u8 = null;
    attempts = 0;
    while (attempts < 1000) : (attempts += 1) {
        if (poller.poll()) |p| {
            payload = p;
            break;
        }
        const ts = std.c.timespec{ .sec = 0, .nsec = 1_000_000 };
        _ = std.c.nanosleep(&ts, null);
    }
    try std.testing.expect(payload != null);
    try std.testing.expectEqualStrings("ready_probe_bytes", payload.?);
    try std.testing.expect(!poller.hasPendingData());
}
