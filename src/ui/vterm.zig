//! PTY-backed VT100 / xterm Virtual Terminal Emulator Component (`VTerm`) for `ui.Context`.
//!
//! Spawns a real interactive macOS shell (`/bin/zsh` or `$SHELL`) inside a POSIX pseudo-terminal
//! (`forkpty`), parses VT100 / ANSI CSI & OSC escape sequences (cursor positioning, line/screen
//! erase, character insert/delete, scrollback history, 16-color / 256-color / 24-bit TrueColor SGR),
//! forwards keyboard input (including Tab completion, arrow keys, `Ctrl+C`, `Ctrl+D`, `Ctrl+L`),
//! and dynamically resizes the PTY window via `TIOCSWINSZ`.

const std = @import("std");
const builtin = @import("builtin");
const skia = @import("skia");
const platform = @import("platform");
const root = @import("root.zig");
const c = skia.c;
const Color = skia.Color;
const Rect = skia.Rect;
const Font = skia.Font;
const Context = root.Context;

const is_windows = (builtin.os.tag == .windows);

const posix_c = if (!is_windows) struct {
    pub const winsize = std.posix.winsize;

    pub const F_GETFL: c_int = 3;
    pub const F_SETFL: c_int = 4;
    pub const O_NONBLOCK: c_int = if (builtin.os.tag == .linux) 0x0800 else 0x0004;
    pub const TIOCSWINSZ: c_ulong = if (builtin.os.tag == .linux) 0x5414 else 0x80087467;
    pub const WNOHANG: c_int = 1;

    extern "c" fn forkpty(amaster: *c_int, name: ?[*]u8, termp: ?*const anyopaque, winp: *const winsize) c_int;
    extern "c" fn ioctl(fd: c_int, request: c_ulong, ...) c_int;
    extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
    extern "c" fn execv(path: [*:0]const u8, argv: [*:null]const ?[*:0]const u8) c_int;
} else struct {
    pub const HANDLE = *anyopaque;
    pub const HPCON = *anyopaque;
    pub const DWORD = u32;
    pub const BOOL = c_int;
    pub const HRESULT = i32;
    pub const EXTENDED_STARTUPINFO_PRESENT: DWORD = 0x00080000;
    pub const STARTF_USESTDHANDLES: DWORD = 0x00000100;
    pub const CREATE_NO_WINDOW: DWORD = 0x08000000;
    pub const HANDLE_FLAG_INHERIT: DWORD = 0x00000001;
    pub const PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE: usize = 0x00020016;

    pub const COORD = extern struct {
        X: i16,
        Y: i16,
    };

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

    pub const STARTUPINFOEXA = extern struct {
        StartupInfo: STARTUPINFOA = .{ .cb = @sizeOf(STARTUPINFOEXA) },
        lpAttributeList: ?*anyopaque = null,
    };

    pub const PROCESS_INFORMATION = extern struct {
        hProcess: ?HANDLE = null,
        hThread: ?HANDLE = null,
        dwProcessId: DWORD = 0,
        dwThreadId: DWORD = 0,
    };

    extern "kernel32" fn CreatePipe(hReadPipe: *?HANDLE, hWritePipe: *?HANDLE, lpPipeAttributes: *const SECURITY_ATTRIBUTES, nSize: DWORD) callconv(.winapi) BOOL;
    extern "kernel32" fn SetHandleInformation(hObject: HANDLE, dwMask: DWORD, dwFlags: DWORD) callconv(.winapi) BOOL;
    extern "kernel32" fn CreatePseudoConsole(size: COORD, hInput: HANDLE, hOutput: HANDLE, dwFlags: DWORD, phPC: *?HPCON) callconv(.winapi) HRESULT;
    extern "kernel32" fn ResizePseudoConsole(hPC: HPCON, size: COORD) callconv(.winapi) HRESULT;
    extern "kernel32" fn ClosePseudoConsole(hPC: HPCON) callconv(.winapi) void;
    extern "kernel32" fn InitializeProcThreadAttributeList(lpAttributeList: ?*anyopaque, dwAttributeCount: DWORD, dwFlags: DWORD, lpSize: *usize) callconv(.winapi) BOOL;
    extern "kernel32" fn UpdateProcThreadAttribute(
        lpAttributeList: *anyopaque,
        dwFlags: DWORD,
        Attribute: usize,
        lpValue: *const anyopaque,
        cbSize: usize,
        lpPreviousValue: ?*anyopaque,
        lpReturnSize: ?*usize,
    ) callconv(.winapi) BOOL;
    extern "kernel32" fn DeleteProcThreadAttributeList(lpAttributeList: *anyopaque) callconv(.winapi) void;
    extern "kernel32" fn CreateProcessA(
        lpApplicationName: ?[*:0]const u8,
        lpCommandLine: [*:0]u8,
        lpProcessAttributes: ?*anyopaque,
        lpThreadAttributes: ?*anyopaque,
        bInheritHandles: BOOL,
        dwCreationFlags: DWORD,
        lpEnvironment: ?*anyopaque,
        lpCurrentDirectory: ?[*:0]const u8,
        lpStartupInfo: *const anyopaque,
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
    extern "kernel32" fn WriteFile(
        hFile: HANDLE,
        lpBuffer: [*]const u8,
        nNumberOfBytesToWrite: DWORD,
        lpNumberOfBytesWritten: *DWORD,
        lpOverlapped: ?*anyopaque,
    ) callconv(.winapi) BOOL;
    extern "kernel32" fn TerminateProcess(hProcess: HANDLE, uExitCode: c_uint) callconv(.winapi) BOOL;
    extern "kernel32" fn CloseHandle(hObject: HANDLE) callconv(.winapi) BOOL;
};

pub const DefaultFg: u32 = Color.rgb(212, 218, 226);
pub const DefaultBg: u32 = Color.transparent;

pub const Cell = struct {
    ch: u8 = ' ',
    fg: u32 = DefaultFg,
    bg: u32 = DefaultBg,
    bold: bool = false,
};

const ParserState = enum {
    ground,
    esc,
    esc_charset,
    csi,
    osc,
    osc_esc,
    dcs,
    dcs_esc,
};

pub const MaxCols: usize = 160;
pub const MaxRows: usize = 64;
pub const ScrollbackLines: usize = 256;

pub const Pos = struct {
    row: usize = 0,
    col: usize = 0,
};

pub fn posLessThan(a: Pos, b: Pos) bool {
    if (a.row != b.row) return a.row < b.row;
    return a.col < b.col;
}

pub fn posEqual(a: Pos, b: Pos) bool {
    return a.row == b.row and a.col == b.col;
}

pub const VTerm = struct {
    // Active screen grid (`rows` x `cols`, up to `MaxRows` x `MaxCols`) + saved main screen for `?1049h` TUI apps (vim/htop/less)
    grid: [MaxRows][MaxCols]Cell = @splat(@splat(.{})),
    alt_grid: [MaxRows][MaxCols]Cell = @splat(@splat(.{})),
    rows: usize = 24,
    cols: usize = 100,
    in_alt_screen: bool = false,

    // Scrollback history ring buffer (lines scrolled off top of normal screen)
    scrollback: [ScrollbackLines][MaxCols]Cell = @splat(@splat(.{})),
    scrollback_head: usize = 0,
    scrollback_count: usize = 0,
    scroll_offset: usize = 0, // 0 = pinned to live bottom, >0 = viewing history
    scroll_px_accum: f32 = 0.0, // Sub-row pixel accumulator so scroll speed matches other buffers (1 row per cell_h px)
    split_scroll_offsets: [7]usize = @splat(0),
    split_scroll_px_accums: [7]f32 = @splat(0.0),

    // Top and bottom scrolling margins (`DECSTBM`: `\x1b[<top>;<bottom>r`, 0-based inclusive)
    scroll_top: usize = 0,
    scroll_bottom: usize = 23,

    // Cursor & SGR attributes
    cursor_row: usize = 0,
    cursor_col: usize = 0,
    saved_row: usize = 0,
    saved_col: usize = 0,
    main_saved_row: usize = 0,
    main_saved_col: usize = 0,
    cursor_visible: bool = true,
    pending_wrap: bool = false,
    app_cursor_keys: bool = false,
    bracketed_paste: bool = false,
    charset_g0_graphics: bool = false,
    esc_charset_slot: u8 = '(',
    last_char: u8 = ' ',

    cur_fg: u32 = DefaultFg,
    cur_bg: u32 = DefaultBg,
    cur_bold: bool = false,
    cur_inverse: bool = false,

    // Interactive mouse & keyboard selection state (virtual row `0..scrollback_count + rows - 1`, col `0..cols`)
    sel_active: bool = false,
    sel_dragging: bool = false,
    sel_click_mode: u8 = 0, // 0 = char drag, 1 = double-click word drag, 2 = triple-click line drag
    sel_anchor: Pos = .{},
    sel_cursor: Pos = .{},
    sel_origin_start: Pos = .{},
    sel_origin_end: Pos = .{},

    // Escape sequence parser state
    state: ParserState = .ground,
    csi_params: [16]u16 = @splat(0),
    csi_param_count: usize = 0,
    csi_has_digit: bool = false,
    csi_private: bool = false,
    csi_prefix: u8 = 0,
    csi_intermediate: u8 = 0,
    osc_buf: [64]u8 = @splat(0),
    osc_len: usize = 0,
    dcs_buf: [64]u8 = @splat(0),
    dcs_len: usize = 0,
    utf8_cp: u21 = 0,
    utf8_expected: u2 = 0,
    utf8_seen: u2 = 0,

    // POSIX PTY & Windows ConPTY handles
    master_fd: c_int = -1,
    child_pid: c_int = -1,
    win_hpc: ?*anyopaque = null,
    win_in_write: ?*anyopaque = null,
    win_out_read: ?*anyopaque = null,
    win_proc: ?*anyopaque = null,
    active_poll_frames: u32 = 0,
    headless_loopback: bool = false,

    pub fn init() VTerm {
        return VTerm{};
    }

    /// Spawns a live interactive shell (`/bin/zsh -f` or `$SHELL` on macOS, or ConPTY `powershell.exe` / `cmd.exe` on Windows).
    pub fn spawnShell(self: *VTerm, initial_rows: usize, initial_cols: usize) bool {
        if (self.master_fd >= 0 or self.headless_loopback) return true;

        self.rows = std.math.clamp(initial_rows, 4, MaxRows);
        self.cols = std.math.clamp(initial_cols, 20, MaxCols);
        self.clearScreen();

        if (comptime is_windows) {
            var sa = posix_c.SECURITY_ATTRIBUTES{};
            var pty_in_read: ?posix_c.HANDLE = null;
            var win_in_write: ?posix_c.HANDLE = null;
            if (posix_c.CreatePipe(&pty_in_read, &win_in_write, &sa, 0) == 0) {
                self.headless_loopback = true;
                return true;
            }
            var win_out_read: ?posix_c.HANDLE = null;
            var pty_out_write: ?posix_c.HANDLE = null;
            if (posix_c.CreatePipe(&win_out_read, &pty_out_write, &sa, 0) == 0) {
                _ = posix_c.CloseHandle(pty_in_read.?);
                _ = posix_c.CloseHandle(win_in_write.?);
                self.headless_loopback = true;
                return true;
            }
            _ = posix_c.SetHandleInformation(win_in_write.?, posix_c.HANDLE_FLAG_INHERIT, 0);
            _ = posix_c.SetHandleInformation(win_out_read.?, posix_c.HANDLE_FLAG_INHERIT, 0);

            const coord = posix_c.COORD{
                .X = @intCast(self.cols),
                .Y = @intCast(self.rows),
            };
            var hpc: ?posix_c.HPCON = null;
            if (posix_c.CreatePseudoConsole(coord, pty_in_read.?, pty_out_write.?, 0, &hpc) == 0 and hpc != null) {
                var attr_buf: [128]u8 align(8) = @splat(0);
                var attr_size: usize = attr_buf.len;
                _ = posix_c.InitializeProcThreadAttributeList(null, 1, 0, &attr_size);
                if (posix_c.InitializeProcThreadAttributeList(&attr_buf, 1, 0, &attr_size) != 0) {
                    defer posix_c.DeleteProcThreadAttributeList(&attr_buf);
                    if (posix_c.UpdateProcThreadAttribute(
                        &attr_buf,
                        0,
                        posix_c.PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE,
                        hpc.?,
                        @sizeOf(usize),
                        null,
                        null,
                    ) != 0) {
                        var si_ex = posix_c.STARTUPINFOEXA{
                            .StartupInfo = .{
                                .cb = @sizeOf(posix_c.STARTUPINFOEXA),
                                .dwFlags = posix_c.STARTF_USESTDHANDLES,
                                .hStdInput = null,
                                .hStdOutput = null,
                                .hStdError = null,
                            },
                            .lpAttributeList = &attr_buf,
                        };
                        var pi = posix_c.PROCESS_INFORMATION{};
                        var cmd_buf: [64:0]u8 = @splat(0);
                        const ps_cmd = "powershell.exe -NoLogo";
                        @memcpy(cmd_buf[0..ps_cmd.len], ps_cmd);
                        var ok = posix_c.CreateProcessA(
                            null,
                            &cmd_buf,
                            null,
                            null,
                            0,
                            posix_c.EXTENDED_STARTUPINFO_PRESENT,
                            null,
                            null,
                            &si_ex,
                            &pi,
                        );
                        if (ok == 0) {
                            cmd_buf = @splat(0);
                            const fb_cmd = "cmd.exe";
                            @memcpy(cmd_buf[0..fb_cmd.len], fb_cmd);
                            ok = posix_c.CreateProcessA(
                                null,
                                &cmd_buf,
                                null,
                                null,
                                0,
                                posix_c.EXTENDED_STARTUPINFO_PRESENT,
                                null,
                                null,
                                &si_ex,
                                &pi,
                            );
                        }
                        if (ok != 0) {
                            _ = posix_c.CloseHandle(pty_in_read.?);
                            _ = posix_c.CloseHandle(pty_out_write.?);
                            if (pi.hThread) |th| _ = posix_c.CloseHandle(th);
                            self.win_hpc = hpc;
                            self.win_in_write = win_in_write;
                            self.win_out_read = win_out_read;
                            self.win_proc = pi.hProcess;
                            self.master_fd = 1;
                            self.child_pid = @intCast(pi.dwProcessId);
                            self.active_poll_frames = 120;
                            return true;
                        }
                    }
                }
                posix_c.ClosePseudoConsole(hpc.?);
            }

            // Fallback: standard pipe-backed `cmd.exe` if ConPTY fails
            var si = posix_c.STARTUPINFOA{
                .dwFlags = posix_c.STARTF_USESTDHANDLES,
                .hStdInput = pty_in_read,
                .hStdOutput = pty_out_write,
                .hStdError = pty_out_write,
            };
            var pi = posix_c.PROCESS_INFORMATION{};
            var cmd_buf: [32:0]u8 = @splat(0);
            const fb_cmd = "cmd.exe";
            @memcpy(cmd_buf[0..fb_cmd.len], fb_cmd);
            const ok = posix_c.CreateProcessA(
                null,
                &cmd_buf,
                null,
                null,
                1,
                posix_c.CREATE_NO_WINDOW,
                null,
                null,
                &si,
                &pi,
            );
            _ = posix_c.CloseHandle(pty_in_read.?);
            _ = posix_c.CloseHandle(pty_out_write.?);
            if (ok != 0) {
                if (pi.hThread) |th| _ = posix_c.CloseHandle(th);
                self.win_in_write = win_in_write;
                self.win_out_read = win_out_read;
                self.win_proc = pi.hProcess;
                self.master_fd = 1;
                self.child_pid = @intCast(pi.dwProcessId);
                self.active_poll_frames = 120;
                return true;
            }
            _ = posix_c.CloseHandle(win_in_write.?);
            _ = posix_c.CloseHandle(win_out_read.?);
            self.headless_loopback = true;
            return true;
        }

        const ws = posix_c.winsize{
            .row = @intCast(self.rows),
            .col = @intCast(self.cols),
            .xpixel = 0,
            .ypixel = 0,
        };

        var master: c_int = -1;
        const pid = posix_c.forkpty(&master, null, null, &ws);
        if (pid < 0) {
            return false;
        }

        if (pid == 0) {
            // Child process: configure environment for clean VT100/ANSI prompt & color output
            _ = posix_c.setenv("TERM", "xterm-256color", 1);
            _ = posix_c.setenv("COLORTERM", "truecolor", 1);
            _ = posix_c.setenv("CLICOLOR", "1", 1);
            _ = posix_c.setenv("PROMPT", "%F{cyan}%1~%f %F{blue}$%f ", 1);
            _ = posix_c.setenv("PS1", "\\W $ ", 1);

            const shell: [*:0]const u8 = if (std.c.getenv("SHELL")) |s| s else "/bin/zsh";
            const shell_argv = [_:null]?[*:0]const u8{ shell, "-i" };
            _ = posix_c.execv(shell, &shell_argv);

            const sh_argv = [_:null]?[*:0]const u8{ "/bin/sh", "-i" };
            _ = posix_c.execv("/bin/sh", &sh_argv);
            std.c._exit(1);
        }

        // Parent process: make `master_fd` non-blocking via variadic `std.c.fcntl`
        const flags = std.c.fcntl(master, posix_c.F_GETFL, @as(c_int, 0));
        if (flags >= 0) {
            _ = std.c.fcntl(master, posix_c.F_SETFL, flags | posix_c.O_NONBLOCK);
        }

        self.master_fd = master;
        self.child_pid = pid;
        self.active_poll_frames = 90;
        return true;
    }

    pub fn deinit(self: *VTerm) void {
        if (comptime is_windows) {
            if (self.win_in_write) |h| {
                _ = posix_c.CloseHandle(h);
                self.win_in_write = null;
            }
            if (self.win_out_read) |h| {
                _ = posix_c.CloseHandle(h);
                self.win_out_read = null;
            }
            if (self.win_hpc) |hpc| {
                posix_c.ClosePseudoConsole(hpc);
                self.win_hpc = null;
            }
            if (self.win_proc) |proc| {
                _ = posix_c.TerminateProcess(proc, 1);
                _ = posix_c.CloseHandle(proc);
                self.win_proc = null;
            }
            self.master_fd = -1;
            self.child_pid = -1;
            return;
        }
        if (self.master_fd >= 0) {
            _ = std.c.close(self.master_fd);
            self.master_fd = -1;
        }
        if (self.child_pid > 0) {
            _ = std.c.kill(self.child_pid, std.posix.SIG.HUP);
            _ = std.c.waitpid(self.child_pid, null, posix_c.WNOHANG);
            self.child_pid = -1;
        }
    }

    /// Resizes the active screen grid and notifies the PTY child process via `TIOCSWINSZ` or `ResizePseudoConsole`.
    pub fn resize(self: *VTerm, new_rows_raw: usize, new_cols_raw: usize) void {
        const new_rows = std.math.clamp(new_rows_raw, 4, MaxRows);
        const new_cols = std.math.clamp(new_cols_raw, 20, MaxCols);
        if (new_rows == self.rows and new_cols == self.cols) return;

        const old_rows = self.rows;
        self.rows = new_rows;
        self.cols = new_cols;
        if (self.scroll_bottom >= old_rows -| 1 or self.scroll_bottom >= self.rows) {
            self.scroll_bottom = self.rows - 1;
        }
        self.scroll_top = @min(self.scroll_top, self.scroll_bottom);
        self.cursor_row = @min(self.cursor_row, self.rows - 1);
        self.cursor_col = @min(self.cursor_col, self.cols - 1);
        self.pending_wrap = false;

        if (comptime is_windows) {
            if (self.win_hpc) |hpc| {
                const coord = posix_c.COORD{
                    .X = @intCast(self.cols),
                    .Y = @intCast(self.rows),
                };
                _ = posix_c.ResizePseudoConsole(hpc, coord);
                self.active_poll_frames = @max(self.active_poll_frames, 60);
            }
        } else {
            if (self.master_fd >= 0) {
                const ws = posix_c.winsize{
                    .row = @intCast(self.rows),
                    .col = @intCast(self.cols),
                    .xpixel = 0,
                    .ypixel = 0,
                };
                _ = posix_c.ioctl(self.master_fd, posix_c.TIOCSWINSZ, &ws);
            }
        }
    }

    /// Non-blocking poll of the PTY master descriptor; feeds any available output into the VT100 parser.
    pub fn poll(self: *VTerm) bool {
        if (comptime is_windows) {
            const out_h = self.win_out_read orelse return false;
            var buf: [4096]u8 = undefined;
            var any_read = false;
            var loops: usize = 0;

            while (loops < 16) : (loops += 1) {
                var avail: posix_c.DWORD = 0;
                if (posix_c.PeekNamedPipe(out_h, null, 0, null, &avail, null) == 0 or avail == 0) break;
                const want: posix_c.DWORD = @min(avail, @as(posix_c.DWORD, @intCast(buf.len)));
                var n_read: posix_c.DWORD = 0;
                if (posix_c.ReadFile(out_h, &buf, want, &n_read, null) == 0 or n_read == 0) break;
                self.feedBytes(buf[0..n_read]);
                any_read = true;
            }

            if (any_read) {
                self.active_poll_frames = 90;
            } else if (self.active_poll_frames > 0) {
                self.active_poll_frames -= 1;
            }
            return any_read;
        }
        if (self.master_fd < 0) return false;

        var buf: [4096]u8 = undefined;
        var any_read = false;
        var loops: usize = 0;

        while (loops < 16) : (loops += 1) {
            const n = std.c.read(self.master_fd, &buf, buf.len);
            if (n <= 0) break;
            const u_n: usize = @intCast(n);
            self.feedBytes(buf[0..u_n]);
            any_read = true;
        }

        if (any_read) {
            self.active_poll_frames = 90;
        } else if (self.active_poll_frames > 0) {
            self.active_poll_frames -= 1;
        }

        return any_read;
    }

    /// Writes raw input bytes directly to the PTY master file descriptor.
    pub fn writeInput(self: *VTerm, bytes: []const u8) void {
        if (bytes.len == 0) return;
        if (self.headless_loopback and self.master_fd < 0) {
            self.feedBytes(bytes);
            self.scroll_offset = 0;
            return;
        }
        if (comptime is_windows) {
            const in_h = self.win_in_write orelse return;
            var written: posix_c.DWORD = 0;
            _ = posix_c.WriteFile(in_h, bytes.ptr, @intCast(bytes.len), &written, null);
            self.scroll_offset = 0;
            self.active_poll_frames = 120;
            return;
        }
        if (self.master_fd < 0) return;
        _ = std.c.write(self.master_fd, bytes.ptr, bytes.len);
        self.scroll_offset = 0;
        self.active_poll_frames = 120;
    }

    /// Pastes text into the terminal (wrapping in `\x1b[200~...\x1b[201~` when bracketed paste mode `?2004h` is active).
    pub fn pasteText(self: *VTerm, text: []const u8) void {
        if (text.len == 0) return;
        self.clearSelection();
        if (self.bracketed_paste) self.writeInput("\x1b[200~");
        self.writeInput(text);
        if (self.bracketed_paste) self.writeInput("\x1b[201~");
    }

    // ========================================================================
    // Virtual Coordinate & Selection / Copy Helpers
    // ========================================================================

    pub fn totalVirtualRows(self: *const VTerm) usize {
        return if (self.in_alt_screen) self.rows else self.scrollback_count + self.rows;
    }

    pub fn screenRowToVirtualRow(self: *const VTerm, screen_row: usize) usize {
        const clamped = @min(screen_row, self.rows -| 1);
        if (self.in_alt_screen) return clamped;
        return (self.scrollback_count + clamped) -| self.scroll_offset;
    }

    pub fn getVirtualRowCells(self: *const VTerm, virtual_row: usize) *const [MaxCols]Cell {
        if (!self.in_alt_screen and virtual_row < self.scrollback_count) {
            const oldest = (self.scrollback_head + ScrollbackLines - self.scrollback_count) % ScrollbackLines;
            const ring_idx = (oldest + virtual_row) % ScrollbackLines;
            return &self.scrollback[ring_idx];
        }
        const base = if (self.in_alt_screen) 0 else self.scrollback_count;
        const grid_idx = @min(virtual_row -| base, self.rows -| 1);
        return &self.grid[grid_idx];
    }

    pub fn clearSelection(self: *VTerm) void {
        self.sel_active = false;
        self.sel_dragging = false;
        self.sel_click_mode = 0;
        self.sel_anchor = .{};
        self.sel_cursor = .{};
    }

    pub fn hasSelection(self: *const VTerm) bool {
        return self.sel_active and !posEqual(self.sel_anchor, self.sel_cursor);
    }

    pub fn selectionRange(self: *const VTerm) struct { start: Pos, end: Pos } {
        if (!self.sel_active) return .{ .start = .{}, .end = .{} };
        if (posLessThan(self.sel_cursor, self.sel_anchor)) {
            return .{ .start = self.sel_cursor, .end = self.sel_anchor };
        }
        return .{ .start = self.sel_anchor, .end = self.sel_cursor };
    }

    pub fn selectAll(self: *VTerm) void {
        const total_r = @max(@as(usize, 1), self.totalVirtualRows());
        var last_non_empty_row: usize = 0;
        for (0..total_r) |vr| {
            const cells = self.getVirtualRowCells(vr);
            if (rowContentLength(cells, self.cols) > 0) {
                last_non_empty_row = vr;
            }
        }
        self.sel_active = true;
        self.sel_dragging = false;
        self.sel_click_mode = 0;
        self.sel_anchor = .{ .row = 0, .col = 0 };
        self.sel_cursor = .{ .row = last_non_empty_row, .col = self.cols };
    }

    /// Extracts the currently highlighted terminal text into an allocator-backed slice,
    /// stripping trailing grid padding spaces from each line.
    pub fn copySelectionAlloc(self: *const VTerm, allocator: std.mem.Allocator) ?[]u8 {
        if (!self.hasSelection()) return null;
        const sel = self.selectionRange();
        const total_r = @max(@as(usize, 1), self.totalVirtualRows());
        const start_r = @min(sel.start.row, total_r - 1);
        const end_r = @min(sel.end.row, total_r - 1);
        if (end_r < start_r) return null;

        const row_span = (end_r - start_r) + 1;
        const max_bytes = row_span * (self.cols + 1);
        const buf = allocator.alloc(u8, max_bytes) catch return null;
        var out_len: usize = 0;

        var r = start_r;
        while (r <= end_r) : (r += 1) {
            if (r > start_r and r == end_r and sel.end.col == 0) break;
            if (r > start_r) {
                buf[out_len] = '\n';
                out_len += 1;
            }
            const cells = self.getVirtualRowCells(r);
            const content_end = rowContentLength(cells, self.cols);
            const c0 = @min(if (r == start_r) sel.start.col else 0, self.cols);
            const c1 = @min(if (r == end_r) sel.end.col else self.cols, self.cols);
            const effective_end = if (c1 > content_end) @max(c0, content_end) else c1;
            var col = c0;
            while (col < effective_end) : (col += 1) {
                buf[out_len] = if (cells[col].ch == 0) ' ' else cells[col].ch;
                out_len += 1;
            }
        }

        return buf[0..out_len];
    }

    fn writePtyResponse(self: *VTerm, bytes: []const u8) void {
        if (comptime is_windows) {
            if (self.win_in_write) |in_h| {
                if (bytes.len > 0) {
                    var written: posix_c.DWORD = 0;
                    _ = posix_c.WriteFile(in_h, bytes.ptr, @intCast(bytes.len), &written, null);
                }
            }
            return;
        }
        if (self.master_fd < 0 or bytes.len == 0) return;
        _ = std.c.write(self.master_fd, bytes.ptr, bytes.len);
    }

    // ========================================================================
    // VT100 / xterm Escape Sequence State Machine
    // ========================================================================

    pub fn feedBytes(self: *VTerm, data: []const u8) void {
        for (data) |b| {
            self.feedByte(b);
        }
    }

    fn feedByte(self: *VTerm, b: u8) void {
        // Handle C0 control characters even if received mid-CSI/ESC (standard VT100 behavior)
        if (self.state == .csi or self.state == .esc or self.state == .esc_charset) {
            switch (b) {
                0x08 => {
                    self.pending_wrap = false;
                    if (self.cursor_col > 0) self.cursor_col -= 1;
                    return;
                },
                0x09 => {
                    self.pending_wrap = false;
                    const next_tab = ((self.cursor_col / 8) + 1) * 8;
                    self.cursor_col = @min(next_tab, self.cols - 1);
                    return;
                },
                0x0A, 0x0B, 0x0C => {
                    self.lineFeed();
                    return;
                },
                0x0D => {
                    self.pending_wrap = false;
                    self.cursor_col = 0;
                    return;
                },
                else => {},
            }
        }

        switch (self.state) {
            .ground => {
                if (self.utf8_expected > 0) {
                    if ((b & 0b1100_0000) == 0b1000_0000) {
                        self.utf8_cp = (self.utf8_cp << 6) | @as(u21, b & 0b0011_1111);
                        self.utf8_seen += 1;
                        if (self.utf8_seen >= self.utf8_expected) {
                            const glyph = unicodeToAsciiGlyph(self.utf8_cp);
                            self.utf8_expected = 0;
                            self.utf8_seen = 0;
                            self.putChar(glyph);
                        }
                        return;
                    }
                    // Interrupted UTF-8 sequence: flush fallback and process `b` normally
                    self.utf8_expected = 0;
                    self.utf8_seen = 0;
                }

                switch (b) {
                    0x00...0x06, 0x10...0x1A, 0x1C...0x1F => {},
                    0x07 => {}, // BEL
                    0x08 => { // BS (Backspace)
                        self.pending_wrap = false;
                        if (self.cursor_col > 0) self.cursor_col -= 1;
                    },
                    0x09 => { // TAB
                        self.pending_wrap = false;
                        const next_tab = ((self.cursor_col / 8) + 1) * 8;
                        self.cursor_col = @min(next_tab, self.cols - 1);
                    },
                    0x0A, 0x0B, 0x0C => { // LF, VT, FF
                        self.lineFeed();
                    },
                    0x0D => { // CR
                        self.pending_wrap = false;
                        self.cursor_col = 0;
                    },
                    0x0E => {}, // SO (Shift Out)
                    0x0F => { // SI (Shift In -> G0 standard)
                        self.charset_g0_graphics = false;
                    },
                    0x1B => { // ESC
                        self.state = .esc;
                    },
                    else => {
                        if (b >= 0x20 and b < 0x7F) {
                            const mapped = if (self.charset_g0_graphics) mapDecSpecialGraphics(b) else b;
                            self.putChar(mapped);
                        } else if ((b & 0b1110_0000) == 0b1100_0000) {
                            self.utf8_cp = @as(u21, b & 0b0001_1111);
                            self.utf8_expected = 1;
                            self.utf8_seen = 0;
                        } else if ((b & 0b1111_0000) == 0b1110_0000) {
                            self.utf8_cp = @as(u21, b & 0b0000_1111);
                            self.utf8_expected = 2;
                            self.utf8_seen = 0;
                        } else if ((b & 0b1111_1000) == 0b1111_0000) {
                            self.utf8_cp = @as(u21, b & 0b0000_0111);
                            self.utf8_expected = 3;
                            self.utf8_seen = 0;
                        }
                    },
                }
            },
            .esc => {
                switch (b) {
                    '[' => {
                        self.state = .csi;
                        self.csi_params = @splat(0);
                        self.csi_param_count = 0;
                        self.csi_has_digit = false;
                        self.csi_private = false;
                        self.csi_prefix = 0;
                        self.csi_intermediate = 0;
                    },
                    ']' => {
                        self.state = .osc;
                        self.osc_len = 0;
                    },
                    'P', 'X', '^', '_' => { // DCS, SOS, PM, APC (consumed until ST `\x1b\\` or BEL)
                        self.state = .dcs;
                        self.dcs_len = 0;
                    },
                    '(', ')', '*', '+' => {
                        self.esc_charset_slot = b;
                        self.state = .esc_charset;
                    },
                    '7' => { // DECSC - Save Cursor
                        self.saved_row = self.cursor_row;
                        self.saved_col = self.cursor_col;
                        self.state = .ground;
                    },
                    '8' => { // DECRC - Restore Cursor
                        self.cursor_row = @min(self.saved_row, self.rows - 1);
                        self.cursor_col = @min(self.saved_col, self.cols - 1);
                        self.pending_wrap = false;
                        self.state = .ground;
                    },
                    'D' => { // IND - Index (move down 1 line, scrolling region up at bottom margin)
                        self.lineFeed();
                        self.state = .ground;
                    },
                    'E' => { // NEL - Next Line
                        self.cursor_col = 0;
                        self.lineFeed();
                        self.state = .ground;
                    },
                    'M' => { // RI - Reverse Index (move up 1 line, scrolling region down at top margin)
                        const top = self.effectiveScrollTop();
                        const bot = self.effectiveScrollBottom();
                        self.pending_wrap = false;
                        if (self.cursor_row == top) {
                            self.scrollRegionDown(top, bot, 1);
                        } else if (self.cursor_row > 0) {
                            self.cursor_row -= 1;
                        }
                        self.state = .ground;
                    },
                    'c' => { // RIS - Full Reset
                        self.in_alt_screen = false;
                        self.app_cursor_keys = false;
                        self.bracketed_paste = false;
                        self.charset_g0_graphics = false;
                        self.cursor_visible = true;
                        self.resetSgr();
                        self.clearScreen();
                        self.state = .ground;
                    },
                    else => {
                        self.state = .ground;
                    },
                }
            },
            .esc_charset => {
                if (self.esc_charset_slot == '(') {
                    self.charset_g0_graphics = (b == '0');
                }
                self.state = .ground;
            },
            .osc => {
                if (b == 0x07) {
                    self.handleOscComplete();
                    self.state = .ground;
                } else if (b == 0x1B) {
                    self.state = .osc_esc;
                } else if (self.osc_len < self.osc_buf.len) {
                    self.osc_buf[self.osc_len] = b;
                    self.osc_len += 1;
                }
            },
            .osc_esc => {
                if (b == '\\') {
                    self.handleOscComplete();
                }
                self.state = .ground;
            },
            .dcs => {
                if (b == 0x07) {
                    self.handleDcsComplete();
                    self.state = .ground;
                } else if (b == 0x1B) {
                    self.state = .dcs_esc;
                } else if (self.dcs_len < self.dcs_buf.len) {
                    self.dcs_buf[self.dcs_len] = b;
                    self.dcs_len += 1;
                }
            },
            .dcs_esc => {
                if (b == '\\') {
                    self.handleDcsComplete();
                }
                self.state = .ground;
            },
            .csi => {
                if (b == 0x1B) {
                    self.state = .esc;
                    return;
                }
                if (b == '?' or b == '>' or b == '<' or b == '=') {
                    self.csi_private = true;
                    if (self.csi_prefix == 0) self.csi_prefix = b;
                    return;
                }
                if (b >= '0' and b <= '9') {
                    if (self.csi_param_count == 0) self.csi_param_count = 1;
                    const idx = self.csi_param_count - 1;
                    if (idx < self.csi_params.len) {
                        self.csi_params[idx] = self.csi_params[idx] *| 10 +| (b - '0');
                    }
                    self.csi_has_digit = true;
                    return;
                }
                if (b == ';' or b == ':') {
                    if (self.csi_param_count == 0) self.csi_param_count = 1;
                    if (self.csi_param_count < self.csi_params.len) {
                        self.csi_param_count += 1;
                    }
                    self.csi_has_digit = false;
                    return;
                }
                if (b >= 0x20 and b <= 0x2F) {
                    self.csi_intermediate = b;
                    return;
                }
                if (b >= 0x40 and b <= 0x7E) {
                    self.dispatchCsi(b);
                    self.state = .ground;
                }
            },
        }
    }

    fn handleOscComplete(self: *VTerm) void {
        const payload = self.osc_buf[0..self.osc_len];
        if (std.mem.eql(u8, payload, "10;?")) {
            self.writePtyResponse("\x1b]10;rgb:d4d4/dada/e2e2\x1b\\");
        } else if (std.mem.eql(u8, payload, "11;?")) {
            self.writePtyResponse("\x1b]11;rgb:0d0d/1111/1818\x1b\\");
        }
    }

    fn handleDcsComplete(self: *VTerm) void {
        const payload = self.dcs_buf[0..self.dcs_len];
        if (std.mem.startsWith(u8, payload, "+q")) {
            // XTGETTCAP query from vim/neovim: respond with "not found" (`0+r`) so vim doesn't block
            self.writePtyResponse("\x1bP0+r\x1b\\");
        }
    }

    fn blankCell(self: *const VTerm) Cell {
        return .{
            .ch = ' ',
            .fg = DefaultFg,
            .bg = self.cur_bg,
            .bold = false,
        };
    }

    fn blankRow(self: *const VTerm) [MaxCols]Cell {
        return @splat(self.blankCell());
    }

    fn effectiveScrollBottom(self: *const VTerm) usize {
        return @min(self.scroll_bottom, self.rows - 1);
    }

    fn effectiveScrollTop(self: *const VTerm) usize {
        return @min(self.scroll_top, self.effectiveScrollBottom());
    }

    fn enterAltScreen(self: *VTerm) void {
        if (!self.in_alt_screen) {
            self.main_saved_row = self.cursor_row;
            self.main_saved_col = self.cursor_col;
            self.alt_grid = self.grid;
            self.in_alt_screen = true;
            self.scroll_offset = 0;
        }
        self.clearSelection();
        self.resetSgr();
        self.clearScreen();
    }

    fn exitAltScreen(self: *VTerm) void {
        if (self.in_alt_screen) {
            self.grid = self.alt_grid;
            self.cursor_row = @min(self.main_saved_row, self.rows - 1);
            self.cursor_col = @min(self.main_saved_col, self.cols - 1);
            self.in_alt_screen = false;
            self.scroll_top = 0;
            self.scroll_bottom = self.rows - 1;
            self.pending_wrap = false;
            self.clearSelection();
            self.resetSgr();
        }
    }

    fn putChar(self: *VTerm, ch: u8) void {
        self.last_char = ch;
        if (self.pending_wrap) {
            self.cursor_col = 0;
            self.lineFeed();
            self.pending_wrap = false;
        }

        const r = @min(self.cursor_row, self.rows - 1);
        const col = @min(self.cursor_col, self.cols - 1);

        const fg = if (self.cur_inverse) (if (self.cur_bg == DefaultBg) Color.rgb(16, 20, 28) else self.cur_bg) else self.cur_fg;
        const bg = if (self.cur_inverse) self.cur_fg else self.cur_bg;

        self.grid[r][col] = .{
            .ch = ch,
            .fg = fg,
            .bg = bg,
            .bold = self.cur_bold,
        };

        if (self.cursor_col + 1 < self.cols) {
            self.cursor_col += 1;
        } else {
            self.pending_wrap = true;
        }
    }

    fn lineFeed(self: *VTerm) void {
        self.pending_wrap = false;
        const top = self.effectiveScrollTop();
        const bot = self.effectiveScrollBottom();
        if (self.cursor_row == bot) {
            self.scrollRegionUp(top, bot, 1, true);
        } else if (self.cursor_row + 1 < self.rows) {
            self.cursor_row += 1;
        }
    }

    fn scrollRegionUp(self: *VTerm, top: usize, bottom: usize, count: usize, allow_scrollback: bool) void {
        if (top > bottom or bottom >= self.rows) return;
        const span = (bottom - top) + 1;
        const n = @min(count, span);
        const blank = self.blankRow();
        for (0..n) |_| {
            if (allow_scrollback and !self.in_alt_screen and top == 0 and bottom + 1 == self.rows) {
                self.scrollback[self.scrollback_head] = self.grid[0];
                self.scrollback_head = (self.scrollback_head + 1) % ScrollbackLines;
                if (self.scrollback_count < ScrollbackLines) {
                    self.scrollback_count += 1;
                } else if (self.sel_active) {
                    self.sel_anchor.row -|= 1;
                    self.sel_cursor.row -|= 1;
                    self.sel_origin_start.row -|= 1;
                    self.sel_origin_end.row -|= 1;
                }
            }

            var r: usize = top;
            while (r < bottom) : (r += 1) {
                self.grid[r] = self.grid[r + 1];
            }
            self.grid[bottom] = blank;
        }
    }

    fn scrollRegionDown(self: *VTerm, top: usize, bottom: usize, count: usize) void {
        if (top > bottom or bottom >= self.rows) return;
        const span = (bottom - top) + 1;
        const n = @min(count, span);
        const blank = self.blankRow();
        for (0..n) |_| {
            var r: usize = bottom;
            while (r > top) : (r -= 1) {
                self.grid[r] = self.grid[r - 1];
            }
            self.grid[top] = blank;
        }
    }

    fn eraseAllCells(self: *VTerm) void {
        const blank = self.blankRow();
        for (0..MaxRows) |r| {
            self.grid[r] = blank;
        }
        self.pending_wrap = false;
    }

    pub fn clearScreen(self: *VTerm) void {
        for (0..MaxRows) |r| {
            self.grid[r] = @splat(.{});
        }
        self.cursor_row = 0;
        self.cursor_col = 0;
        self.scroll_top = 0;
        self.scroll_bottom = self.rows -| 1;
        self.pending_wrap = false;
        self.clearSelection();
    }

    fn csiParam(self: *const VTerm, idx: usize, default_val: u16) usize {
        if (idx >= self.csi_param_count) return default_val;
        const v = self.csi_params[idx];
        return if (v == 0) default_val else v;
    }

    fn dispatchCsi(self: *VTerm, final_byte: u8) void {
        self.pending_wrap = false;

        if (self.csi_intermediate != 0) {
            if (self.csi_intermediate == '!' and final_byte == 'p') {
                // DECSTR - Soft Terminal Reset
                self.scroll_top = 0;
                self.scroll_bottom = self.rows -| 1;
                self.app_cursor_keys = false;
                self.cursor_visible = true;
                self.charset_g0_graphics = false;
                self.resetSgr();
            }
            return;
        }

        if (self.csi_prefix == '?') {
            const count = @max(@as(usize, 1), self.csi_param_count);
            const is_set = (final_byte == 'h');
            if (final_byte == 'h' or final_byte == 'l') {
                for (0..count) |i| {
                    const mode = self.csiParam(i, 0);
                    switch (mode) {
                        1 => self.app_cursor_keys = is_set, // DECCKM - Application Cursor Keys
                        25 => self.cursor_visible = is_set, // DECTCEM - Text Cursor Enable
                        47, 1047, 1049 => {
                            if (is_set) self.enterAltScreen() else self.exitAltScreen();
                        },
                        2004 => self.bracketed_paste = is_set,
                        else => {},
                    }
                }
            }
            return;
        }

        if (self.csi_prefix == '>') {
            if (final_byte == 'c') {
                // DA2 - Secondary Device Attributes (xterm patch 276)
                self.writePtyResponse("\x1b[>0;276;0c");
            }
            return;
        }

        if (self.csi_prefix != 0) {
            // Ignore `<` and `=` private sequences (e.g. Kitty keyboard protocol `\x1b[=1u`, `\x1b[<u`)
            return;
        }

        switch (final_byte) {
            'A' => { // CUU - Cursor Up
                const n = self.csiParam(0, 1);
                const top = self.effectiveScrollTop();
                const min_row = if (self.cursor_row >= top) top else 0;
                self.cursor_row = @max(min_row, self.cursor_row -| n);
            },
            'B' => { // CUD - Cursor Down
                const n = self.csiParam(0, 1);
                const bot = self.effectiveScrollBottom();
                const max_row = if (self.cursor_row <= bot) bot else self.rows - 1;
                self.cursor_row = @min(max_row, self.cursor_row + n);
            },
            'C' => { // CUF - Cursor Forward
                const n = self.csiParam(0, 1);
                self.cursor_col = @min(self.cursor_col + n, self.cols - 1);
            },
            'D' => { // CUB - Cursor Back
                const n = self.csiParam(0, 1);
                self.cursor_col -|= n;
            },
            'E' => { // CNL - Cursor Next Line
                const n = self.csiParam(0, 1);
                self.cursor_row = @min(self.cursor_row + n, self.rows - 1);
                self.cursor_col = 0;
            },
            'F' => { // CPL - Cursor Prev Line
                const n = self.csiParam(0, 1);
                self.cursor_row -|= n;
                self.cursor_col = 0;
            },
            'G', '`' => { // CHA / HPA - Cursor Horizontal Absolute (1-based)
                const col_1 = self.csiParam(0, 1);
                self.cursor_col = @min(col_1 -| 1, self.cols - 1);
            },
            'd' => { // VPA - Vertical Line Position Absolute (1-based)
                const row_1 = self.csiParam(0, 1);
                self.cursor_row = @min(row_1 -| 1, self.rows - 1);
            },
            'H', 'f' => { // CUP - Cursor Position (1-based row;col)
                const row_1 = self.csiParam(0, 1);
                const col_1 = self.csiParam(1, 1);
                self.cursor_row = @min(row_1 -| 1, self.rows - 1);
                self.cursor_col = @min(col_1 -| 1, self.cols - 1);
            },
            'I' => { // CHT - Cursor Forward Tabulation
                const n = self.csiParam(0, 1);
                for (0..n) |_| {
                    const next_tab = ((self.cursor_col / 8) + 1) * 8;
                    self.cursor_col = @min(next_tab, self.cols - 1);
                }
            },
            'Z' => { // CBT - Cursor Backward Tabulation
                const n = self.csiParam(0, 1);
                for (0..n) |_| {
                    if (self.cursor_col == 0) break;
                    self.cursor_col = ((self.cursor_col - 1) / 8) * 8;
                }
            },
            'b' => { // REP - Repeat preceding graphic character `n` times
                const n = @min(self.csiParam(0, 1), MaxCols * MaxRows);
                const ch = self.last_char;
                for (0..n) |_| {
                    self.putChar(ch);
                }
            },
            'J' => { // ED - Erase in Display (with Background Color Erase)
                const mode = if (self.csi_param_count == 0) 0 else self.csi_params[0];
                const blank_cell = self.blankCell();
                const blank_row = self.blankRow();
                const r_cur = @min(self.cursor_row, self.rows - 1);
                if (mode == 0) {
                    for (self.cursor_col..MaxCols) |col| {
                        self.grid[r_cur][col] = blank_cell;
                    }
                    for (r_cur + 1 .. self.rows) |r| {
                        self.grid[r] = blank_row;
                    }
                } else if (mode == 1) {
                    for (0..r_cur) |r| {
                        self.grid[r] = blank_row;
                    }
                    for (0 .. @min(self.cursor_col + 1, MaxCols)) |col| {
                        self.grid[r_cur][col] = blank_cell;
                    }
                } else if (mode == 2 or mode == 3) {
                    self.eraseAllCells();
                    if (mode == 3) {
                        self.scrollback_count = 0;
                        self.scrollback_head = 0;
                    }
                }
            },
            'K' => { // EL - Erase in Line (with Background Color Erase)
                const mode = if (self.csi_param_count == 0) 0 else self.csi_params[0];
                const r = @min(self.cursor_row, self.rows - 1);
                const blank_cell = self.blankCell();
                if (mode == 0) {
                    for (self.cursor_col..MaxCols) |col| {
                        self.grid[r][col] = blank_cell;
                    }
                } else if (mode == 1) {
                    for (0 .. @min(self.cursor_col + 1, MaxCols)) |col| {
                        self.grid[r][col] = blank_cell;
                    }
                } else if (mode == 2) {
                    self.grid[r] = self.blankRow();
                }
            },
            'L' => { // IL - Insert `n` Blank Lines at cursor row within scroll region
                const top = self.effectiveScrollTop();
                const bot = self.effectiveScrollBottom();
                if (self.cursor_row >= top and self.cursor_row <= bot) {
                    self.scrollRegionDown(self.cursor_row, bot, self.csiParam(0, 1));
                    self.cursor_col = 0;
                }
            },
            'M' => { // DL - Delete `n` Lines at cursor row within scroll region
                const top = self.effectiveScrollTop();
                const bot = self.effectiveScrollBottom();
                if (self.cursor_row >= top and self.cursor_row <= bot) {
                    self.scrollRegionUp(self.cursor_row, bot, self.csiParam(0, 1), false);
                    self.cursor_col = 0;
                }
            },
            'S' => { // SU - Scroll Up `n` Lines within scroll region
                const top = self.effectiveScrollTop();
                const bot = self.effectiveScrollBottom();
                self.scrollRegionUp(top, bot, self.csiParam(0, 1), false);
            },
            'T' => { // SD - Scroll Down `n` Lines within scroll region
                const top = self.effectiveScrollTop();
                const bot = self.effectiveScrollBottom();
                self.scrollRegionDown(top, bot, self.csiParam(0, 1));
            },
            'P' => { // DCH - Delete Characters on current line (shifts remainder left)
                const n = @min(self.csiParam(0, 1), self.cols - self.cursor_col);
                const r = @min(self.cursor_row, self.rows - 1);
                const blank_cell = self.blankCell();
                var col = self.cursor_col;
                while (col + n < self.cols) : (col += 1) {
                    self.grid[r][col] = self.grid[r][col + n];
                }
                while (col < MaxCols) : (col += 1) {
                    self.grid[r][col] = blank_cell;
                }
            },
            '@' => { // ICH - Insert Blank Characters on current line
                const n = @min(self.csiParam(0, 1), self.cols - self.cursor_col);
                const r = @min(self.cursor_row, self.rows - 1);
                const blank_cell = self.blankCell();
                var col = self.cols - 1;
                while (col >= self.cursor_col + n) : (col -= 1) {
                    self.grid[r][col] = self.grid[r][col - n];
                }
                for (self.cursor_col .. self.cursor_col + n) |c_idx| {
                    self.grid[r][c_idx] = blank_cell;
                }
            },
            'X' => { // ECH - Erase Characters
                const n = @min(self.csiParam(0, 1), self.cols - self.cursor_col);
                const r = @min(self.cursor_row, self.rows - 1);
                const blank_cell = self.blankCell();
                for (self.cursor_col .. self.cursor_col + n) |c_idx| {
                    self.grid[r][c_idx] = blank_cell;
                }
            },
            'r' => { // DECSTBM - Set Top and Bottom Margins (1-based)
                const top_1 = self.csiParam(0, 1);
                const bot_1 = self.csiParam(1, @intCast(self.rows));
                const top_0 = @min(top_1 -| 1, self.rows - 1);
                const bot_0 = @min(bot_1 -| 1, self.rows - 1);
                if (top_0 < bot_0) {
                    self.scroll_top = top_0;
                    self.scroll_bottom = bot_0;
                } else {
                    self.scroll_top = 0;
                    self.scroll_bottom = self.rows - 1;
                }
                self.cursor_row = 0;
                self.cursor_col = 0;
            },
            's' => {
                self.saved_row = self.cursor_row;
                self.saved_col = self.cursor_col;
            },
            'u' => {
                self.cursor_row = @min(self.saved_row, self.rows - 1);
                self.cursor_col = @min(self.saved_col, self.cols - 1);
            },
            'c' => { // DA1 - Primary Device Attributes
                self.writePtyResponse("\x1b[?62;22c");
            },
            'n' => { // DSR - Device Status Report / Cursor Position Report
                const mode = self.csiParam(0, 0);
                if (mode == 5) {
                    self.writePtyResponse("\x1b[0n");
                } else if (mode == 6) {
                    var cpr_buf: [32]u8 = undefined;
                    const cpr = std.fmt.bufPrint(&cpr_buf, "\x1b[{d};{d}R", .{
                        @min(self.cursor_row, self.rows - 1) + 1,
                        @min(self.cursor_col, self.cols - 1) + 1,
                    }) catch "\x1b[1;1R";
                    self.writePtyResponse(cpr);
                }
            },
            'm' => {
                self.applySgr();
            },
            else => {},
        }
    }

    fn applySgr(self: *VTerm) void {
        if (self.csi_param_count == 0) {
            self.resetSgr();
            return;
        }

        var i: usize = 0;
        while (i < self.csi_param_count) : (i += 1) {
            const code = self.csi_params[i];
            switch (code) {
                0 => self.resetSgr(),
                1 => self.cur_bold = true,
                7 => self.cur_inverse = true,
                22 => self.cur_bold = false,
                27 => self.cur_inverse = false,
                30...37 => self.cur_fg = ansi16Color(@intCast(code - 30), self.cur_bold),
                39 => self.cur_fg = DefaultFg,
                40...47 => self.cur_bg = ansi16Color(@intCast(code - 40), false),
                49 => self.cur_bg = DefaultBg,
                90...97 => self.cur_fg = ansi16Color(@intCast(code - 90), true),
                100...107 => self.cur_bg = ansi16Color(@intCast(code - 100), true),
                38, 48 => {
                    const is_fg = (code == 38);
                    if (i + 2 < self.csi_param_count and self.csi_params[i + 1] == 5) {
                        const col = xterm256Color(@truncate(self.csi_params[i + 2]));
                        if (is_fg) self.cur_fg = col else self.cur_bg = col;
                        i += 2;
                    } else if (i + 4 < self.csi_param_count and self.csi_params[i + 1] == 2) {
                        const r: u8 = @truncate(@min(255, self.csi_params[i + 2]));
                        const g: u8 = @truncate(@min(255, self.csi_params[i + 3]));
                        const b: u8 = @truncate(@min(255, self.csi_params[i + 4]));
                        const col = Color.rgb(r, g, b);
                        if (is_fg) self.cur_fg = col else self.cur_bg = col;
                        i += 4;
                    }
                },
                else => {},
            }
        }
    }

    fn resetSgr(self: *VTerm) void {
        self.cur_fg = DefaultFg;
        self.cur_bg = DefaultBg;
        self.cur_bold = false;
        self.cur_inverse = false;
    }
};

fn mapDecSpecialGraphics(b: u8) u8 {
    return switch (b) {
        'q' => '-', // horizontal line
        'x' => '|', // vertical line
        'j', 'k', 'l', 'm', 'n', 't', 'u', 'v', 'w' => '+', // corners & tees
        'a' => '#', // checkerboard
        'f', 'g', 'z', 'y' => '*',
        '~' => '.',
        else => b,
    };
}

fn unicodeToAsciiGlyph(cp: u21) u8 {
    return switch (cp) {
        0x00A0 => ' ', // NBSP
        0x2010...0x2015, 0x2500, 0x2501, 0x2504, 0x2505, 0x2508, 0x2509, 0x254C, 0x254D, 0x2550, 0x2574, 0x2576, 0x2578, 0x257A => '-',
        0x2502, 0x2503, 0x2506, 0x2507, 0x250A, 0x250B, 0x254E, 0x254F, 0x2551, 0x2575, 0x2577, 0x2579, 0x257B => '|',
        0x250C...0x254B, 0x2552...0x2573 => '+',
        0x2580...0x259F => '#',
        0x2022, 0x25CF, 0x25CB, 0x25AA, 0x25AB, 0x2713, 0x2714 => '*',
        0x25B6, 0x25B8, 0x276F, 0x2192 => '>',
        0x2190 => '<',
        0x2191 => '^',
        0x2193 => 'v',
        else => '?',
    };
}

fn ansi16Color(idx: u4, bright: bool) u32 {
    return if (!bright) switch (idx) {
        0 => Color.rgb(30, 37, 48), // Black
        1 => Color.rgb(248, 81, 73), // Red
        2 => Color.rgb(52, 211, 153), // Green
        3 => Color.rgb(251, 191, 36), // Yellow
        4 => Color.rgb(88, 166, 255), // Blue
        5 => Color.rgb(210, 168, 255), // Magenta
        6 => Color.rgb(56, 189, 248), // Cyan
        else => Color.rgb(212, 218, 226), // White
    } else switch (idx) {
        0 => Color.rgb(110, 118, 129), // Bright Black (Gray)
        1 => Color.rgb(255, 123, 114), // Bright Red
        2 => Color.rgb(86, 211, 100), // Bright Green
        3 => Color.rgb(252, 211, 77), // Bright Yellow
        4 => Color.rgb(121, 192, 255), // Bright Blue
        5 => Color.rgb(232, 196, 255), // Bright Magenta
        6 => Color.rgb(125, 211, 252), // Bright Cyan
        else => Color.rgb(248, 250, 252), // Bright White
    };
}

fn xterm256Color(idx: u8) u32 {
    if (idx < 8) return ansi16Color(@intCast(idx), false);
    if (idx < 16) return ansi16Color(@intCast(idx - 8), true);
    if (idx >= 232) {
        const gray: u8 = @intCast(8 + @as(u16, idx - 232) * 10);
        return Color.rgb(gray, gray, gray);
    }
    const cube = idx - 16;
    const r_idx = cube / 36;
    const g_idx = (cube % 36) / 6;
    const b_idx = cube % 6;
    const levels = [6]u8{ 0, 95, 135, 175, 215, 255 };
    return Color.rgb(levels[r_idx], levels[g_idx], levels[b_idx]);
}

// ============================================================================
// Skia VTerm Widget Renderer (`render`)
// ============================================================================

pub fn render(
    uic: *Context,
    widget_id_str: []const u8,
    width: f32,
    height: f32,
    vt: *VTerm,
    font_override: ?Font,
) bool {
    const wid = root.id(widget_id_str);
    const font = font_override orelse uic.font_mono;
    const rect = uic.nextRect(width, height);

    const pane_slot: usize = if (widget_id_str.len >= 2 and widget_id_str[widget_id_str.len - 2] == '_' and std.ascii.isDigit(widget_id_str[widget_id_str.len - 1]))
        @as(usize, widget_id_str[widget_id_str.len - 1] - '0')
    else
        0;
    const saved_scroll_off = vt.scroll_offset;
    const saved_scroll_px = vt.scroll_px_accum;
    if (pane_slot > 0) {
        const s_idx = @min(pane_slot - 1, vt.split_scroll_offsets.len - 1);
        vt.scroll_offset = @min(vt.split_scroll_offsets[s_idx], vt.scrollback_count);
        vt.scroll_px_accum = vt.split_scroll_px_accums[s_idx];
    }
    defer if (pane_slot > 0) {
        const s_idx = @min(pane_slot - 1, vt.split_scroll_offsets.len - 1);
        vt.split_scroll_offsets[s_idx] = vt.scroll_offset;
        vt.split_scroll_px_accums[s_idx] = vt.scroll_px_accum;
        vt.scroll_offset = saved_scroll_off;
        vt.scroll_px_accum = saved_scroll_px;
    };

    const pad_x: f32 = 12.0;
    const pad_y: f32 = 6.0;
    const cell_w = @max(6.5, uic.measureTextCached(font, "M"));
    const cell_h: f32 = 18.0;

    const inner_w = @max(40.0, (rect.right - rect.left) - pad_x * 2.0);
    const inner_h = @max(24.0, (rect.bottom - rect.top) - pad_y * 2.0);
    const fit_cols: usize = @intFromFloat(@floor(inner_w / cell_w));
    const fit_rows: usize = @intFromFloat(@floor(inner_h / cell_h));

    if (uic.pass == .input) {
        _ = vt.spawnShell(fit_rows, fit_cols);
        vt.resize(fit_rows, fit_cols);

        if (vt.poll()) {
            uic.markDirty(rect);
        }

        if (uic.isHovered(rect)) {
            uic.setCursor(.ibeam);
        }

        // Convert mouse coordinates into terminal cell coordinates
        const rel_x = uic.mouse_x - (rect.left + pad_x);
        const rel_y = uic.mouse_y - (rect.top + pad_y);
        const screen_row: usize = if (rel_y <= 0)
            0
        else
            @min(@as(usize, @intFromFloat(@floor(rel_y / cell_h))), vt.rows -| 1);
        const cell_col: usize = if (rel_x <= 0)
            0
        else
            @min(@as(usize, @intFromFloat(@floor(rel_x / cell_w))), vt.cols -| 1);
        const snap_col: usize = if (rel_x + cell_w * 0.5 <= 0)
            0
        else
            @min(@as(usize, @intFromFloat(@floor((rel_x + cell_w * 0.5) / cell_w))), vt.cols);

        if (uic.mouse_pressed and uic.isHovered(rect)) {
            uic.focused_id = wid;
            uic.active_id = wid;
            vt.sel_dragging = true;
            const v_row = vt.screenRowToVirtualRow(screen_row);

            if (uic.mouse_click_count >= 3) {
                vt.sel_active = true;
                vt.sel_click_mode = 2;
                vt.sel_anchor = .{ .row = v_row, .col = 0 };
                vt.sel_cursor = .{ .row = v_row, .col = vt.cols };
                vt.sel_origin_start = vt.sel_anchor;
                vt.sel_origin_end = vt.sel_cursor;
            } else if (uic.mouse_click_count == 2) {
                const wr = wordRangeInRow(vt.getVirtualRowCells(v_row), vt.cols, cell_col);
                vt.sel_active = true;
                vt.sel_click_mode = 1;
                vt.sel_anchor = .{ .row = v_row, .col = wr.start };
                vt.sel_cursor = .{ .row = v_row, .col = wr.end };
                vt.sel_origin_start = vt.sel_anchor;
                vt.sel_origin_end = vt.sel_cursor;
            } else {
                const click_pos = Pos{ .row = v_row, .col = snap_col };
                vt.sel_click_mode = 0;
                if (!uic.mouse_shift or !vt.sel_active) {
                    vt.sel_anchor = click_pos;
                }
                vt.sel_cursor = click_pos;
                vt.sel_active = true;
            }
            uic.markDirty(rect);
        } else if (uic.active_id == wid and vt.sel_dragging and uic.mouse_down) {
            // Auto-scroll scrollback when dragging above/below viewport bounds
            if (!vt.in_alt_screen) {
                if (uic.mouse_y < rect.top and vt.scroll_offset < vt.scrollback_count) {
                    vt.scroll_offset += 1;
                    uic.markDirty(rect);
                } else if (uic.mouse_y > rect.bottom and vt.scroll_offset > 0) {
                    vt.scroll_offset -= 1;
                    uic.markDirty(rect);
                }
            }

            const v_row = vt.screenRowToVirtualRow(screen_row);
            const prev_anchor = vt.sel_anchor;
            const prev_cursor = vt.sel_cursor;

            if (vt.sel_click_mode == 2) {
                if (v_row < vt.sel_origin_start.row) {
                    vt.sel_anchor = vt.sel_origin_end;
                    vt.sel_cursor = .{ .row = v_row, .col = 0 };
                } else {
                    vt.sel_anchor = vt.sel_origin_start;
                    vt.sel_cursor = .{ .row = v_row, .col = vt.cols };
                }
            } else if (vt.sel_click_mode == 1) {
                const wr = wordRangeInRow(vt.getVirtualRowCells(v_row), vt.cols, cell_col);
                const w_start = Pos{ .row = v_row, .col = wr.start };
                const w_end = Pos{ .row = v_row, .col = wr.end };
                if (posLessThan(w_start, vt.sel_origin_start)) {
                    vt.sel_anchor = vt.sel_origin_end;
                    vt.sel_cursor = w_start;
                } else {
                    vt.sel_anchor = vt.sel_origin_start;
                    vt.sel_cursor = w_end;
                }
            } else {
                vt.sel_cursor = .{ .row = v_row, .col = snap_col };
            }

            if (!posEqual(vt.sel_anchor, prev_anchor) or !posEqual(vt.sel_cursor, prev_cursor)) {
                uic.markDirty(rect);
            }
        } else if (!uic.mouse_down) {
            if (uic.active_id == wid) {
                uic.active_id = 0;
            }
            vt.sel_dragging = false;
        }

        if (uic.right_mouse_pressed and uic.isHovered(rect)) {
            uic.focused_id = wid;
            uic.markDirty(rect);
        }

        // Scrollback wheel navigation (or arrow-key forwarding when a full-screen TUI like vim/less is active).
        // Accumulates `uic.scroll_dy` in logical pixels and steps 1 row per `cell_h` pixels so terminal
        // scroll speed matches `beginScrollBox` and `CodeEditor` across trackpads and mouse wheels.
        if (uic.scroll_dy != 0 and uic.isHovered(rect)) {
            if ((uic.scroll_dy > 0 and vt.scroll_px_accum < 0) or (uic.scroll_dy < 0 and vt.scroll_px_accum > 0)) {
                vt.scroll_px_accum = 0.0;
            }
            vt.scroll_px_accum += uic.scroll_dy;
            const whole_rows: isize = @intFromFloat(@trunc(vt.scroll_px_accum / cell_h));
            if (whole_rows != 0) {
                vt.scroll_px_accum -= @as(f32, @floatFromInt(whole_rows)) * cell_h;
                if (vt.in_alt_screen) {
                    const up_seq = if (vt.app_cursor_keys) "\x1bOA" else "\x1b[A";
                    const down_seq = if (vt.app_cursor_keys) "\x1bOB" else "\x1b[B";
                    const seq = if (whole_rows > 0) up_seq else down_seq;
                    const steps: usize = @min(@as(usize, @intCast(@abs(whole_rows))), 8);
                    for (0..steps) |_| {
                        vt.writeInput(seq);
                    }
                    uic.markDirty(rect);
                } else {
                    const cur_off: isize = @intCast(vt.scroll_offset);
                    const max_off: isize = @intCast(vt.scrollback_count);
                    const next_off: usize = @intCast(std.math.clamp(cur_off + whole_rows, 0, max_off));
                    if (next_off != vt.scroll_offset) {
                        vt.scroll_offset = next_off;
                        uic.markDirty(rect);
                    }
                    if (next_off == 0 or next_off == vt.scrollback_count) {
                        vt.scroll_px_accum = 0.0;
                    }
                }
            }
        }

        if (uic.focused_id == wid) {
            for (uic.key_events) |kev| {
                // Copy selection: Cmd+C or Ctrl+Shift+C (on Windows, plain Ctrl+C copies only if a selection is active; otherwise it sends SIGINT \x03)
                if ((kev.cmd and kev.key == .key_c and (!is_windows or kev.shift or vt.hasSelection())) or
                    (kev.ctrl and kev.shift and !kev.cmd and kev.key == .key_c))
                {
                    if (vt.copySelectionAlloc(uic.arena)) |copied| {
                        if (uic.platform_ctx) |pctx| {
                            _ = pctx.setClipboardText(copied);
                        }
                    }
                    if (comptime is_windows) {
                        if (!kev.shift) vt.clearSelection();
                    }
                    uic.markDirty(rect);
                    continue;
                }

                // Paste from clipboard: Cmd+V or Ctrl+Shift+V
                if ((kev.cmd and kev.key == .key_v) or (kev.ctrl and kev.shift and !kev.cmd and kev.key == .key_v)) {
                    if (uic.platform_ctx) |pctx| {
                        if (pctx.getClipboardTextAlloc(uic.arena)) |clip| {
                            vt.pasteText(clip);
                            uic.markDirty(rect);
                        }
                    }
                    continue;
                }

                // Select All: Cmd+A or Ctrl+Shift+A
                if ((kev.cmd and kev.key == .key_a and (!is_windows or kev.shift)) or
                    (kev.ctrl and kev.shift and !kev.cmd and kev.key == .key_a))
                {
                    vt.selectAll();
                    uic.markDirty(rect);
                    continue;
                }

                // Clear terminal & scrollback: Cmd+K
                if (kev.cmd and kev.key == .key_k) {
                    vt.clearSelection();
                    vt.scrollback_count = 0;
                    vt.scrollback_head = 0;
                    vt.scroll_offset = 0;
                    vt.scroll_px_accum = 0.0;
                    vt.writeInput("\x0c");
                    uic.markDirty(rect);
                    continue;
                }

                if (kev.ctrl and (!kev.cmd or (is_windows and !kev.shift))) {
                    vt.clearSelection();
                    if (kev.key.toCtrlByte()) |cb| {
                        const ctrl_seq: [1]u8 = .{cb};
                        vt.writeInput(&ctrl_seq);
                    }
                    uic.markDirty(rect);
                    continue;
                }

                if (kev.cmd and kev.key != .backspace and kev.key != .left and kev.key != .right) {
                    continue;
                }

                if (kev.key == .escape and vt.hasSelection()) {
                    vt.clearSelection();
                    uic.markDirty(rect);
                    continue;
                }

                const up_seq = if (vt.app_cursor_keys) "\x1bOA" else "\x1b[A";
                const down_seq = if (vt.app_cursor_keys) "\x1bOB" else "\x1b[B";
                const right_seq = if (vt.app_cursor_keys) "\x1bOC" else "\x1b[C";
                const left_seq = if (vt.app_cursor_keys) "\x1bOD" else "\x1b[D";
                const home_seq = if (vt.app_cursor_keys) "\x1bOH" else "\x1b[H";
                const end_seq = if (vt.app_cursor_keys) "\x1bOF" else "\x1b[F";

                vt.clearSelection();
                switch (kev.key) {
                    .enter => vt.writeInput("\r"),
                    .backspace => if (kev.cmd) vt.writeInput("\x15") else vt.writeInput("\x7f"),
                    .delete_forward => vt.writeInput("\x1b[3~"),
                    .tab => if (kev.shift) vt.writeInput("\x1b[Z") else vt.writeInput("\t"),
                    .up => vt.writeInput(up_seq),
                    .down => vt.writeInput(down_seq),
                    .right => if (kev.alt) vt.writeInput("\x1bf") else if (kev.cmd) vt.writeInput("\x05") else vt.writeInput(right_seq),
                    .left => if (kev.alt) vt.writeInput("\x1bb") else if (kev.cmd) vt.writeInput("\x01") else vt.writeInput(left_seq),
                    .home => vt.writeInput(home_seq),
                    .end => vt.writeInput(end_seq),
                    .page_up => vt.writeInput("\x1b[5~"),
                    .page_down => vt.writeInput("\x1b[6~"),
                    .escape => vt.writeInput("\x1b"),
                    else => {},
                }
                uic.markDirty(rect);
            }

            if (uic.text_input.len > 0) {
                vt.clearSelection();
                vt.writeInput(uic.text_input);
                uic.markDirty(rect);
            }
        }

        if (vt.active_poll_frames > 0) {
            if (uic.platform_ctx) |pctx| {
                pctx.needs_continuous_redraw = true;
            }
        }
    }

    const is_focused = (uic.focused_id == wid);

    if (uic.shouldPaint(rect)) {
        const canvas = uic.canvas;
        const paint = uic.paint;

        _ = canvas.save();
        defer canvas.restore();
        canvas.clipRect(rect, .intersect, false);

        paint.setStyle(.fill);
        paint.setColor(Color.rgb(13, 17, 24));
        canvas.drawRect(rect, paint);

        const has_sel = vt.hasSelection();
        const sel = vt.selectionRange();

        var row_idx: usize = 0;
        while (row_idx < vt.rows) : (row_idx += 1) {
            const v_row = vt.screenRowToVirtualRow(row_idx);
            const row_cells: *const [MaxCols]Cell = vt.getVirtualRowCells(v_row);
            const row_top = rect.top + pad_y + @as(f32, @floatFromInt(row_idx)) * cell_h;
            const baseline_y = row_top + 13.5;

            // 1. Draw non-transparent cell background spans
            var col: usize = 0;
            while (col < vt.cols) {
                const bg = row_cells[col].bg;
                if (bg == DefaultBg) {
                    col += 1;
                    continue;
                }
                var end_col = col + 1;
                while (end_col < vt.cols and row_cells[end_col].bg == bg) : (end_col += 1) {}
                const bg_x = rect.left + pad_x + @as(f32, @floatFromInt(col)) * cell_w;
                const bg_w = @as(f32, @floatFromInt(end_col - col)) * cell_w;
                paint.setStyle(.fill);
                paint.setColor(bg);
                canvas.drawRect(Rect.xywh(bg_x, row_top, bg_w, cell_h), paint);
                col = end_col;
            }

            // 1b. Draw selection highlight span on this row
            if (has_sel and v_row >= sel.start.row and v_row <= sel.end.row) {
                const sel_c0 = if (v_row == sel.start.row) @min(sel.start.col, vt.cols) else 0;
                const sel_c1 = if (v_row == sel.end.row) @min(sel.end.col, vt.cols) else vt.cols;
                if (sel_c1 > sel_c0) {
                    const sel_x = rect.left + pad_x + @as(f32, @floatFromInt(sel_c0)) * cell_w;
                    const sel_w = @as(f32, @floatFromInt(sel_c1 - sel_c0)) * cell_w;
                    paint.setStyle(.fill);
                    paint.setColor(if (is_focused) Color.argb(110, 56, 139, 253) else Color.argb(65, 100, 116, 139));
                    canvas.drawRoundRect(Rect.xywh(sel_x, row_top + 0.5, sel_w, cell_h - 1.0), 2.5, 2.5, paint);
                }
            }

            // 2. Batch contiguous ASCII runs with identical foreground color
            var run_buf: [MaxCols]u8 = undefined;
            col = 0;
            while (col < vt.cols) {
                while (col < vt.cols and row_cells[col].ch == ' ') : (col += 1) {}
                if (col >= vt.cols) break;

                const fg = row_cells[col].fg;
                const start_col = col;
                var run_len: usize = 0;

                while (col < vt.cols and row_cells[col].fg == fg) : (col += 1) {
                    if (row_cells[col].ch == ' ' and col + 1 < vt.cols and row_cells[col + 1].ch == ' ') break;
                    run_buf[run_len] = row_cells[col].ch;
                    run_len += 1;
                }

                // Trim trailing spaces from batch run
                while (run_len > 0 and run_buf[run_len - 1] == ' ') {
                    run_len -= 1;
                }

                if (run_len > 0) {
                    const text_x = rect.left + pad_x + @as(f32, @floatFromInt(start_col)) * cell_w;
                    paint.setStyle(.fill);
                    paint.setColor(fg);
                    uic.drawTextCached(font, run_buf[0..run_len], text_x, baseline_y);
                }
            }
        }

        // 3. Draw block/hollow cursor when viewing live screen (`scroll_offset == 0`)
        if (vt.scroll_offset == 0 and vt.cursor_visible) {
            const c_row = @min(vt.cursor_row, vt.rows - 1);
            const c_col = @min(vt.cursor_col, vt.cols - 1);
            const cx = rect.left + pad_x + @as(f32, @floatFromInt(c_col)) * cell_w;
            const cy = rect.top + pad_y + @as(f32, @floatFromInt(c_row)) * cell_h;
            const cursor_rect = Rect.xywh(cx, cy + 1.5, cell_w, cell_h - 3.0);

            if (is_focused) {
                paint.setStyle(.fill);
                paint.setColor(Color.argb(185, 88, 166, 255));
                canvas.drawRoundRect(cursor_rect, 1.5, 1.5, paint);
            } else {
                paint.setStyle(.stroke);
                paint.setStrokeWidth(1.2);
                paint.setColor(Color.argb(160, 125, 133, 144));
                canvas.drawRoundRect(cursor_rect, 1.5, 1.5, paint);
            }
        }
    }

    return is_focused;
}

fn rowContentLength(cells: *const [MaxCols]Cell, cols: usize) usize {
    const limit = @min(cols, MaxCols);
    var end: usize = limit;
    while (end > 0 and (cells[end - 1].ch == ' ' or cells[end - 1].ch == 0)) : (end -= 1) {}
    return end;
}

fn isTerminalWordChar(b: u8) bool {
    return std.ascii.isAlphanumeric(b) or b == '_' or b == '-' or b == '.' or b == '/' or b == '~';
}

fn wordRangeInRow(cells: *const [MaxCols]Cell, cols: usize, col_raw: usize) struct { start: usize, end: usize } {
    const limit = @min(cols, MaxCols);
    if (limit == 0) return .{ .start = 0, .end = 0 };
    const col = @min(col_raw, limit - 1);
    const ch = cells[col].ch;

    if (isTerminalWordChar(ch)) {
        var start = col;
        while (start > 0 and isTerminalWordChar(cells[start - 1].ch)) : (start -= 1) {}
        var end = col + 1;
        while (end < limit and isTerminalWordChar(cells[end].ch)) : (end += 1) {}
        return .{ .start = start, .end = end };
    }

    if (ch == ' ' or ch == 0) {
        var start = col;
        while (start > 0 and (cells[start - 1].ch == ' ' or cells[start - 1].ch == 0)) : (start -= 1) {}
        var end = col + 1;
        while (end < limit and (cells[end].ch == ' ' or cells[end].ch == 0)) : (end += 1) {}
        return .{ .start = start, .end = end };
    }

    var start = col;
    while (start > 0 and !isTerminalWordChar(cells[start - 1].ch) and cells[start - 1].ch != ' ' and cells[start - 1].ch != 0) : (start -= 1) {}
    var end = col + 1;
    while (end < limit and !isTerminalWordChar(cells[end].ch) and cells[end].ch != ' ' and cells[end].ch != 0) : (end += 1) {}
    return .{ .start = start, .end = end };
}

fn getDisplayRow(vt: *const VTerm, screen_row: usize) *const [MaxCols]Cell {
    return vt.getVirtualRowCells(vt.screenRowToVirtualRow(screen_row));
}

// ============================================================================
// Unit Tests
// ============================================================================

test "VTerm VT100/ANSI parser: cursor motion, SGR colors, erase, and DCH" {
    var vt = VTerm.init();
    vt.rows = 10;
    vt.cols = 40;
    vt.clearScreen();

    vt.feedBytes("\x1b[32mhello\x1b[0m world\r\nline2\x08\x1b[P!");
    try std.testing.expectEqual(@as(u8, 'h'), vt.grid[0][0].ch);
    try std.testing.expectEqual(Color.rgb(52, 211, 153), vt.grid[0][0].fg);
    try std.testing.expectEqual(@as(u8, 'w'), vt.grid[0][6].ch);
    try std.testing.expectEqual(DefaultFg, vt.grid[0][6].fg);

    // Line 2 had "line2", then BS (\x08) moved cursor to '2', DCH (\x1b[P) deleted '2', and '!' overwrote it -> "line!"
    try std.testing.expectEqual(@as(u8, 'l'), vt.grid[1][0].ch);
    try std.testing.expectEqual(@as(u8, 'e'), vt.grid[1][3].ch);
    try std.testing.expectEqual(@as(u8, '!'), vt.grid[1][4].ch);
}

test "VTerm PTY shell spawn, non-blocking poll, and command execution" {
    var vt = VTerm.init();
    defer vt.deinit();

    try std.testing.expect(vt.spawnShell(24, 80));
    try std.testing.expect(vt.master_fd >= 0);

    vt.writeInput("echo vterm_pty_ok\r");

    const ts = std.c.timespec{ .sec = 0, .nsec = 15_000_000 };
    var found = false;
    var row_buf: [80]u8 = undefined;

    for (0..40) |_| {
        _ = std.c.nanosleep(&ts, null);
        _ = vt.poll();

        for (0..vt.rows) |r| {
            for (0..80) |col| {
                row_buf[col] = vt.grid[r][col].ch;
            }
            if (std.mem.indexOfPos(u8, &row_buf, 0, "can't open input file") != null) {
                return error.ZshCantOpenInputFileError;
            }
            if (std.mem.indexOfPos(u8, &row_buf, 0, "vterm_pty_ok") != null) {
                found = true;
            }
        }
        if (found) break;
    }

    try std.testing.expect(found);
}

test "VTerm Fuzzer: 1-byte chunked CSI/OSC escape sequences, TrueColor SGR, and out-of-bounds cursor clamping" {
    var vt = VTerm.init();
    vt.rows = 12;
    vt.cols = 32;
    vt.clearScreen();

    // Feed TrueColor SGR, 256-color SGR, out-of-bounds CUP (\x1b[999;999H), scroll regions, and OSC title 1 byte at a time
    const seq = "\x1b]0;Custom Title\x07\x1b[38;2;255;64;128;48;5;235mRGB\x1b[999;999H!\x1b[1;5r\x1b[999A\x1b[999D@\x1b[0m";
    for (seq) |b| {
        const one: [1]u8 = .{b};
        vt.feedBytes(&one);
    }

    try std.testing.expect(vt.cursor_row < vt.rows);
    try std.testing.expect(vt.cursor_col < vt.cols);
    try std.testing.expectEqual(@as(u8, '@'), vt.grid[0][0].ch);
    try std.testing.expectEqual(@as(u8, '!'), vt.grid[vt.rows - 1][vt.cols - 1].ch);
}

test "VTerm TUI & Vim emulation: alternate screen (?1049h/l), DECSTBM scroll regions, IL/DL/SU/SD, XTGETTCAP DCS, and REP" {
    var vt = VTerm.init();
    vt.rows = 6;
    vt.cols = 30;
    vt.clearScreen();

    // 1. Write shell prompt on main screen before entering Vim alternate screen
    vt.feedBytes("zsh$ vim file.zig");
    try std.testing.expectEqual(@as(u8, 'z'), vt.grid[0][0].ch);

    // 2. Enter alternate screen (?1049h) + Application Cursor Keys (?1h) + XTGETTCAP DCS + Kitty keyboard query
    vt.feedBytes("\x1b[?1049;1h\x1bP+q544e\x1b\\\x1b[>4;2m\x1b[=1u\x1b[2 q");
    try std.testing.expect(vt.in_alt_screen);
    try std.testing.expect(vt.app_cursor_keys);
    // Ensure XTGETTCAP payload `+q544e` was swallowed by DCS state and not printed onto grid
    try std.testing.expectEqual(@as(u8, ' '), vt.grid[0][0].ch);

    // 3. Draw 4 buffer lines (rows 0..3) and statusline on row 5
    vt.feedBytes("\x1b[1;1HLine1\x1b[2;1HLine2\x1b[3;1HLine3\x1b[4;1H~\x1b[3b\x1b[6;1H-- NORMAL --");
    try std.testing.expectEqual(@as(u8, '1'), vt.grid[0][4].ch);
    try std.testing.expectEqual(@as(u8, '2'), vt.grid[1][4].ch);
    try std.testing.expectEqual(@as(u8, '3'), vt.grid[2][4].ch);
    // REP (\x1b[3b) repeated '~' 3 additional times on row 3 (cols 0..3)
    try std.testing.expectEqual(@as(u8, '~'), vt.grid[3][3].ch);
    try std.testing.expectEqual(@as(u8, 'N'), vt.grid[5][3].ch);

    // 4. Set DECSTBM scroll region to rows 1..4 (1-based `\x1b[1;4r`) so row 5 (`-- NORMAL --`) stays pinned
    vt.feedBytes("\x1b[1;4r");
    // Delete Line 2 (`\x1b[2;1H\x1b[M`): Line 3 shifts up to row 1, while row 5 (`-- NORMAL --`) is untouched!
    vt.feedBytes("\x1b[2;1H\x1b[M");
    try std.testing.expectEqual(@as(u8, '1'), vt.grid[0][4].ch);
    try std.testing.expectEqual(@as(u8, '3'), vt.grid[1][4].ch);
    try std.testing.expectEqual(@as(u8, 'N'), vt.grid[5][3].ch);

    // Insert Line at row 1 (`\x1b[2;1H\x1b[LNew2`): pushes Line 3 back down to row 2
    vt.feedBytes("\x1b[2;1H\x1b[LNew2");
    try std.testing.expectEqual(@as(u8, 'w'), vt.grid[1][2].ch);
    try std.testing.expectEqual(@as(u8, '3'), vt.grid[2][4].ch);
    try std.testing.expectEqual(@as(u8, 'N'), vt.grid[5][3].ch);

    // 5. Exit alternate screen (`\x1b[?1049l\x1b[?1l`): restores original `zsh$ vim file.zig` screen!
    vt.feedBytes("\x1b[?1049;1l");
    try std.testing.expect(!vt.in_alt_screen);
    try std.testing.expect(!vt.app_cursor_keys);
    try std.testing.expectEqual(@as(u8, 'z'), vt.grid[0][0].ch);
    try std.testing.expectEqual(@as(u8, 'v'), vt.grid[0][5].ch);
}

test "VTerm PTY interactive Vim session: launch vim, insert text, Escape to normal mode, and :q! back to shell" {
    var vt = VTerm.init();
    defer vt.deinit();

    try std.testing.expect(vt.spawnShell(24, 80));
    // Launch clean vim in non-compatible mode without swapfile, insert text, Escape, and quit
    vt.writeInput("vim -Nu NONE -n\r");

    const ts = std.c.timespec{ .sec = 0, .nsec = 20_000_000 };
    var entered_alt = false;
    for (0..45) |_| {
        _ = std.c.nanosleep(&ts, null);
        _ = vt.poll();
        if (vt.in_alt_screen) {
            entered_alt = true;
            break;
        }
    }
    try std.testing.expect(entered_alt);

    // Enter Insert mode (`i`), type "VIM_BUFFER_OK", press Escape (`\x1b`)
    vt.writeInput("iVIM_BUFFER_OK\x1b");
    var saw_buffer_text = false;
    var row_buf: [80]u8 = undefined;
    for (0..45) |_| {
        _ = std.c.nanosleep(&ts, null);
        _ = vt.poll();
        for (0..vt.rows) |r| {
            for (0..80) |col| row_buf[col] = vt.grid[r][col].ch;
            if (std.mem.indexOfPos(u8, &row_buf, 0, "VIM_BUFFER_OK") != null) {
                saw_buffer_text = true;
                break;
            }
        }
        if (saw_buffer_text) break;
    }
    try std.testing.expect(saw_buffer_text);

    // Quit vim (`:q!\r`) and verify VTerm exits the alternate screen back to the shell
    vt.writeInput(":q!\r");
    var exited_alt = false;
    for (0..45) |_| {
        _ = std.c.nanosleep(&ts, null);
        _ = vt.poll();
        if (!vt.in_alt_screen) {
            exited_alt = true;
            break;
        }
    }
    try std.testing.expect(exited_alt);
}

test "VTerm highlight, mouse drag, double/triple-click, Cmd+A select-all, Cmd+C copy, and Cmd+V paste across input & paint passes" {
    const MockClipboard = struct {
        var buf: [512]u8 = @splat(0);
        var len: usize = 0;

        fn getClipboard(out_ptr: ?[*]u8, cap: usize) callconv(.c) usize {
            if (out_ptr) |dst| {
                const n = @min(len, cap);
                if (n > 0) @memcpy(dst[0..n], buf[0..n]);
                return n;
            }
            return len;
        }

        fn setClipboard(ptr: [*]const u8, in_len: usize) callconv(.c) void {
            const n = @min(in_len, buf.len);
            if (n > 0) @memcpy(buf[0..n], ptr[0..n]);
            len = n;
        }

        fn slice() []const u8 {
            return buf[0..len];
        }
    };

    const surface = try skia.Surface.initRasterN32Premul(640, 320);
    defer surface.deinit();
    const paint = try skia.Paint.init();
    defer paint.deinit();
    const font = try Font.init(null, 13.0);
    defer font.deinit();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var pctx = platform.PlatformContext{
        .width = 640.0,
        .height = 320.0,
        .host_get_clipboard = MockClipboard.getClipboard,
        .host_set_clipboard = MockClipboard.setClipboard,
    };

    var uic = Context{
        .arena = arena.allocator(),
        .canvas = surface.canvas(),
        .paint = paint,
        .font_title = font,
        .font_body = font,
        .font_mono = font,
        .platform_ctx = &pctx,
    };
    defer uic.deinit();

    var vt = VTerm.init();
    vt.headless_loopback = true;
    vt.rows = 12;
    vt.cols = 60;
    vt.clearScreen();
    vt.feedBytes("alpha src/ui/vterm.zig omega\r\nsecond line output\r\nthird line");

    const cell_w = @max(6.5, uic.measureTextCached(font, "M"));
    const pad_x: f32 = 12.0;
    const pad_y: f32 = 6.0;
    const cell_h: f32 = 18.0;

    // 1. Double-click on "src/ui/vterm.zig" (row 0, col 8) -> selects "src/ui/vterm.zig" (cols 6..22)
    const dbl_x = pad_x + 8.5 * cell_w;
    const row0_y = pad_y + 0.5 * cell_h;
    pctx.mouse_click_count = 2;
    pctx.mouse_shift = false;
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 640, 320), dbl_x, row0_y, true, true, false);
    _ = render(&uic, "test_vterm", 640, 320, &vt, font);
    uic.endPass();

    try std.testing.expect(vt.hasSelection());
    const word_copied = vt.copySelectionAlloc(arena.allocator()).?;
    try std.testing.expectEqualStrings("src/ui/vterm.zig", word_copied);

    // Paint pass with active highlight
    uic.clip_damage = uic.dirty_rect;
    uic.beginPass(.paint, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 640, 320), dbl_x, row0_y, true, false, false);
    _ = render(&uic, "test_vterm", 640, 320, &vt, font);
    uic.endPass();
    try std.testing.expectEqual(uic.last_input_rect_count, uic.last_paint_rect_count);

    // 2. Press Cmd+C while focused -> copies "src/ui/vterm.zig" to system clipboard
    pctx.mouse_click_count = 1;
    pctx.clearFrameInput();
    pctx.pushKeyEvent(.{ .key = .key_c, .cmd = true });
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 640, 320), dbl_x, row0_y, false, false, true);
    _ = render(&uic, "test_vterm", 640, 320, &vt, font);
    uic.endPass();
    try std.testing.expectEqualStrings("src/ui/vterm.zig", MockClipboard.slice());

    // 3. Triple-click on row 1 ("second line output") -> selects entire line without trailing grid padding spaces
    const row1_y = pad_y + 1.5 * cell_h;
    pctx.clearFrameInput();
    pctx.mouse_click_count = 3;
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 640, 320), dbl_x, row1_y, true, true, false);
    _ = render(&uic, "test_vterm", 640, 320, &vt, font);
    uic.endPass();
    const line_copied = vt.copySelectionAlloc(arena.allocator()).?;
    try std.testing.expectEqualStrings("second line output", line_copied);

    // 4. Single-click drag from row 0 col 0 ("alpha...") to row 1 col 6 ("second") -> multi-line highlight
    pctx.mouse_click_count = 1;
    const start_x = pad_x + 0.1 * cell_w;
    const end_x = pad_x + 6.0 * cell_w;
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 640, 320), start_x, row0_y, true, true, false);
    _ = render(&uic, "test_vterm", 640, 320, &vt, font);
    uic.endPass();

    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 640, 320), end_x, row1_y, true, false, false);
    _ = render(&uic, "test_vterm", 640, 320, &vt, font);
    uic.endPass();

    const drag_copied = vt.copySelectionAlloc(arena.allocator()).?;
    try std.testing.expectEqualStrings("alpha src/ui/vterm.zig omega\nsecond", drag_copied);

    // 5. Cmd+A selects all non-empty lines and Cmd+C copies them
    pctx.clearFrameInput();
    pctx.pushKeyEvent(.{ .key = .key_a, .cmd = true });
    pctx.pushKeyEvent(.{ .key = .key_c, .cmd = true });
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 640, 320), end_x, row1_y, false, false, true);
    _ = render(&uic, "test_vterm", 640, 320, &vt, font);
    uic.endPass();
    try std.testing.expectEqualStrings("alpha src/ui/vterm.zig omega\nsecond line output\nthird line", MockClipboard.slice());

    // 6. Cmd+V pastes clipboard text into the terminal (and clears active selection)
    MockClipboard.setClipboard(" + pasted_ok", 12);
    pctx.clearFrameInput();
    pctx.pushKeyEvent(.{ .key = .key_v, .cmd = true });
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 640, 320), end_x, row1_y, false, false, false);
    _ = render(&uic, "test_vterm", 640, 320, &vt, font);
    uic.endPass();

    try std.testing.expect(!vt.hasSelection());
    vt.selectAll();
    const after_paste = vt.copySelectionAlloc(arena.allocator()).?;
    try std.testing.expectEqualStrings("alpha src/ui/vterm.zig omega\nsecond line output\nthird line + pasted_ok", after_paste);

    // 7. Pixel-accumulated scroll speed: sub-row deltas accumulate smoothly (1 row per cell_h = 18px)
    for (0..30) |_| {
        vt.feedBytes("\r\nscrollback line");
    }
    try std.testing.expect(vt.scrollback_count >= 10);
    try std.testing.expectEqual(@as(usize, 0), vt.scroll_offset);

    // Two 9px trackpad deltas (= 18px = 1 cell_h) advance scroll_offset by exactly 1 row
    pctx.clearFrameInput();
    pctx.scroll_dy = 9.0;
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 640, 320), end_x, row1_y, false, false, false);
    _ = render(&uic, "test_vterm", 640, 320, &vt, font);
    uic.endPass();
    try std.testing.expectEqual(@as(usize, 0), vt.scroll_offset);

    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 640, 320), end_x, row1_y, false, false, false);
    _ = render(&uic, "test_vterm", 640, 320, &vt, font);
    uic.endPass();
    try std.testing.expectEqual(@as(usize, 1), vt.scroll_offset);

    // A 54px scroll delta (= 3 * cell_h) advances scroll_offset by 3 rows -> total 4
    pctx.scroll_dy = 54.0;
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 640, 320), end_x, row1_y, false, false, false);
    _ = render(&uic, "test_vterm", 640, 320, &vt, font);
    uic.endPass();
    try std.testing.expectEqual(@as(usize, 4), vt.scroll_offset);
}
