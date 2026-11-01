//! Non-Blocking Language Server Protocol (LSP) Client & Source Intelligence Engine (`src/platform/lsp_client.zig`).
//!
//! Shared across native Zig `.dylib` language plugins (`plugins/cpp_lsp.zig`, `plugins/java_lsp.zig`,
//! `plugins/go_lsp.zig`).
//!
//! Capabilities:
//!   - **Non-Blocking Stdio JSON-RPC 2.0 Transport (`LspConnection`)**:
//!     Spawns external language server binaries (`clangd`, `jdtls`, `gopls`) over a pair of POSIX pipes
//!     (`O_NONBLOCK` stdout read fd), frames outgoing requests/notifications with `Content-Length: <N>\r\n\r\n`,
//!     and parses incoming `Content-Length` frames (`initialize` result, `textDocument/publishDiagnostics`)
//!     incrementally during `on_poll_io` with zero UI-thread stalls.
//!   - **Zero-Allocation Lexical Symbol Outline & Diagnostics Fallback**:
//!     Provides immediate, deterministic symbol extraction (`scanSymbols`), structural & style diagnostics
//!     (`scanLocalDiagnostics`), and brace-aware source formatting (`formatBraceSource`) so language plugins
//!     deliver rich IDE features immediately even while the LSP daemon is warming up or if the binary is not installed.

const std = @import("std");
const builtin = @import("builtin");
const is_windows = (builtin.os.tag == .windows);
const abi = @import("plugin_abi.zig");
const state_store = @import("state_store.zig");
pub const InlineString = state_store.InlineString;
pub const CompletionItemV1 = abi.CompletionItemV1;

const posix_c = struct {
    extern "c" fn pipe(fds: *[2]c_int) c_int;
    extern "c" fn fork() c_int;
    extern "c" fn dup2(oldfd: c_int, newfd: c_int) c_int;
    extern "c" fn execv(path: [*:0]const u8, argv: [*:null]const ?[*:0]const u8) c_int;
};

const win32_lsp = struct {
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
    extern "kernel32" fn WriteFile(
        hFile: HANDLE,
        lpBuffer: [*]const u8,
        nNumberOfBytesToWrite: DWORD,
        lpNumberOfBytesWritten: *DWORD,
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

pub const LspLanguage = enum(u8) {
    cpp = 0,
    java = 1,
    go = 2,
    systemverilog = 3,
    zig = 4,
    rust = 5,
    python = 6,
    typescript = 7,
    hdl = 8,

    pub fn languageId(self: LspLanguage) []const u8 {
        return switch (self) {
            .cpp => "cpp",
            .java => "java",
            .go => "go",
            .systemverilog => "systemverilog",
            .zig => "zig",
            .rust => "rust",
            .python => "python",
            .typescript => "typescript",
            .hdl => "vhdl",
        };
    }

    pub fn serverBinary(self: LspLanguage) []const u8 {
        return switch (self) {
            .cpp => "clangd",
            .java => "jdtls",
            .go => "gopls",
            .systemverilog => "slang-server",
            .zig => "zls",
            .rust => "rust-analyzer",
            .python => "pyright-langserver",
            .typescript => "typescript-language-server",
            .hdl => "vhdl_ls",
        };
    }

    pub fn matchesPath(self: LspLanguage, path: []const u8) bool {
        return switch (self) {
            .cpp => std.mem.endsWith(u8, path, ".c") or
                std.mem.endsWith(u8, path, ".cc") or
                std.mem.endsWith(u8, path, ".cpp") or
                std.mem.endsWith(u8, path, ".cxx") or
                std.mem.endsWith(u8, path, ".h") or
                std.mem.endsWith(u8, path, ".hpp") or
                std.mem.endsWith(u8, path, ".hxx"),
            .java => std.mem.endsWith(u8, path, ".java"),
            .go => std.mem.endsWith(u8, path, ".go"),
            .systemverilog => std.mem.endsWith(u8, path, ".sv") or
                std.mem.endsWith(u8, path, ".svh") or
                std.mem.endsWith(u8, path, ".v") or
                std.mem.endsWith(u8, path, ".vh"),
            .zig => std.mem.endsWith(u8, path, ".zig") or std.mem.endsWith(u8, path, ".zon"),
            .rust => std.mem.endsWith(u8, path, ".rs"),
            .python => std.mem.endsWith(u8, path, ".py") or std.mem.endsWith(u8, path, ".pyi"),
            .typescript => std.mem.endsWith(u8, path, ".ts") or
                std.mem.endsWith(u8, path, ".tsx") or
                std.mem.endsWith(u8, path, ".js") or
                std.mem.endsWith(u8, path, ".jsx") or
                std.mem.endsWith(u8, path, ".mjs"),
            .hdl => std.mem.endsWith(u8, path, ".vhd") or
                std.mem.endsWith(u8, path, ".vhdl") or
                std.mem.endsWith(u8, path, ".scala") or
                std.mem.endsWith(u8, path, ".sc") or
                std.mem.endsWith(u8, path, ".dts") or
                std.mem.endsWith(u8, path, ".dtsi"),
        };
    }

    pub fn matchesBuffer(self: LspLanguage, path: []const u8, text: []const u8) bool {
        if (self.matchesPath(path)) return true;
        return switch (self) {
            .cpp => std.mem.indexOfPos(u8, text, 0, "#include") != null or
                std.mem.indexOfPos(u8, text, 0, "std::") != null or
                std.mem.indexOfPos(u8, text, 0, "namespace ") != null or
                std.mem.indexOfPos(u8, text, 0, "template<") != null,
            .java => std.mem.indexOfPos(u8, text, 0, "public class ") != null or
                std.mem.indexOfPos(u8, text, 0, "System.out.") != null or
                std.mem.indexOfPos(u8, text, 0, "import java.") != null,
            .go => std.mem.indexOfPos(u8, text, 0, "package ") != null or
                std.mem.indexOfPos(u8, text, 0, "func ") != null or
                std.mem.indexOfPos(u8, text, 0, "import (") != null,
            .systemverilog => std.mem.indexOfPos(u8, text, 0, "module ") != null or
                std.mem.indexOfPos(u8, text, 0, "always_ff") != null or
                std.mem.indexOfPos(u8, text, 0, "always_comb") != null or
                std.mem.indexOfPos(u8, text, 0, "endmodule") != null,
            .zig => std.mem.indexOfPos(u8, text, 0, "@import(") != null or
                std.mem.indexOfPos(u8, text, 0, "pub fn ") != null or
                std.mem.indexOfPos(u8, text, 0, "test ") != null,
            .rust => std.mem.indexOfPos(u8, text, 0, "fn ") != null or
                std.mem.indexOfPos(u8, text, 0, "use ") != null or
                std.mem.indexOfPos(u8, text, 0, "impl ") != null,
            .python => std.mem.indexOfPos(u8, text, 0, "def ") != null or
                std.mem.indexOfPos(u8, text, 0, "import ") != null or
                std.mem.indexOfPos(u8, text, 0, "class ") != null,
            .typescript => std.mem.indexOfPos(u8, text, 0, "const ") != null or
                std.mem.indexOfPos(u8, text, 0, "let ") != null or
                std.mem.indexOfPos(u8, text, 0, "function ") != null or
                std.mem.indexOfPos(u8, text, 0, "export ") != null or
                std.mem.indexOfPos(u8, text, 0, "interface ") != null or
                std.mem.indexOfPos(u8, text, 0, "console.") != null,
            .hdl => std.mem.indexOfPos(u8, text, 0, "architecture ") != null or
                std.mem.indexOfPos(u8, text, 0, "std_logic") != null or
                std.mem.indexOfPos(u8, text, 0, "extends Module") != null or
                std.mem.indexOfPos(u8, text, 0, "/dts-v1/;") != null or
                std.mem.indexOfPos(u8, text, 0, "entity ") != null,
        };
    }
};

pub const LspSeverity = enum(u8) {
    err = 1,
    warn = 2,
    info = 3,
    hint = 4,

    pub fn badge(self: LspSeverity) []const u8 {
        return switch (self) {
            .err => "ERR",
            .warn => "WARN",
            .info => "INFO",
            .hint => "HINT",
        };
    }
};

pub const LspDiagnostic = struct {
    line: u32 = 1, // 1-based line number
    col: u32 = 1, // 1-based column
    severity: LspSeverity = .err,
    message: InlineString(96) = .{},
};

pub const LspSymbol = struct {
    kind: InlineString(12) = .{}, // e.g. "class", "struct", "fn", "method", "iface", "type"
    name: InlineString(64) = .{},
    detail: InlineString(48) = .{},
    line: u32 = 1, // 1-based line number
};

pub const LspCompletionItem = struct {
    label: InlineString(40) = .{},
    detail: InlineString(40) = .{},
    insert_text: InlineString(48) = .{},
    kind: u8 = 0, // 0=keyword, 1=fn/method, 2=type/class/struct, 3=snippet, 4=field/var
    replace_prefix_len: u16 = 0,

    pub fn toAbi(self: *const LspCompletionItem) CompletionItemV1 {
        return .{
            .label = abi.AbiSlice.fromZig(self.label.slice()),
            .detail = abi.AbiSlice.fromZig(self.detail.slice()),
            .insert_text = abi.AbiSlice.fromZig(if (self.insert_text.len > 0) self.insert_text.slice() else self.label.slice()),
            .kind = self.kind,
            .replace_prefix_len = self.replace_prefix_len,
        };
    }
};

pub const MaxDiagnostics: usize = 8;
pub const MaxSymbols: usize = 24;
pub const MaxCompletions: usize = 8;

/// Hot-reload-safe state structure (`<= 1950` bytes) stored in the host's `StateStore` via `ctx.useState`.
pub const LspConnection = struct {
    language: LspLanguage = .cpp,
    stdin_fd: c_int = -1,
    stdout_fd: c_int = -1,
    child_pid: c_int = -1,
    win_stdin_h: ?*anyopaque = null,
    win_stdout_h: ?*anyopaque = null,
    win_proc_h: ?*anyopaque = null,

    server_available: bool = false,
    probe_attempted: bool = false,
    initialized: bool = false,
    doc_opened: bool = false,
    next_rpc_id: u32 = 1,
    rpc_sent: u32 = 0,
    rpc_received: u32 = 0,
    last_synced_version: u32 = 0,
    last_synced_buffer_id: u32 = 0xFFFFFFFF,

    server_status: InlineString(64) = .{},
    filter_query: InlineString(48) = .{},

    // Non-blocking stdout ring buffer for Content-Length JSON-RPC framing
    rx_buf: [512]u8 = @splat(0),
    rx_len: usize = 0,

    // Live diagnostics (populated from LSP `publishDiagnostics` or local structural analyzer)
    diagnostics: [MaxDiagnostics]LspDiagnostic = @splat(.{}),
    diagnostic_count: usize = 0,
    has_lsp_diagnostics: bool = false,

    // Live completion candidates (`textDocument/completion` + instant AST/stdlib intellisense)
    completions: [MaxCompletions]LspCompletionItem = @splat(.{}),
    completion_count: usize = 0,
    completion_buffer_id: u32 = 0xFFFFFFFF,
    completion_cursor_offset: usize = 0,
    completions_dirty: bool = false,

    pub fn isRunning(self: *const LspConnection) bool {
        if (comptime is_windows) {
            return self.win_stdin_h != null and self.win_stdout_h != null and self.win_proc_h != null;
        }
        return self.stdin_fd >= 0 and self.stdout_fd >= 0 and self.child_pid > 0;
    }

    pub fn stopServer(self: *LspConnection) void {
        if (comptime is_windows) {
            if (self.win_stdin_h) |h| {
                _ = win32_lsp.CloseHandle(h);
                self.win_stdin_h = null;
            }
            if (self.win_stdout_h) |h| {
                _ = win32_lsp.CloseHandle(h);
                self.win_stdout_h = null;
            }
            if (self.win_proc_h) |h| {
                _ = win32_lsp.TerminateProcess(h, 1);
                _ = win32_lsp.CloseHandle(h);
                self.win_proc_h = null;
            }
        } else {
            if (self.stdin_fd >= 0) {
                _ = std.c.close(self.stdin_fd);
                self.stdin_fd = -1;
            }
            if (self.stdout_fd >= 0) {
                _ = std.c.close(self.stdout_fd);
                self.stdout_fd = -1;
            }
            if (self.child_pid > 0) {
                _ = std.c.kill(self.child_pid, std.posix.SIG.TERM);
                if (std.c.waitpid(self.child_pid, null, WNOHANG) == 0) {
                    const ts = std.c.timespec{ .sec = 0, .nsec = 1_000_000 };
                    _ = std.c.nanosleep(&ts, null);
                    _ = std.c.waitpid(self.child_pid, null, WNOHANG);
                }
                self.child_pid = -1;
            }
        }
        self.initialized = false;
        self.doc_opened = false;
        self.rx_len = 0;
        self.server_status.set("Stopped");
    }

    /// Attempts to spawn the external language server binary (`clangd`, `jdtls`, or `gopls`)
    /// with non-blocking stdio pipes. If the binary is not installed, gracefully switches to
    /// the built-in zero-allocation lexical/AST analyzer without blocking.
    pub fn spawnServer(self: *LspConnection, lang: LspLanguage, custom_cmd_opt: ?[]const u8) bool {
        self.stopServer();
        self.language = lang;
        self.probe_attempted = true;

        if (comptime is_windows) {
            var sa = win32_lsp.SECURITY_ATTRIBUTES{};
            var in_rd: ?win32_lsp.HANDLE = null;
            var in_wr: ?win32_lsp.HANDLE = null;
            var out_rd: ?win32_lsp.HANDLE = null;
            var out_wr: ?win32_lsp.HANDLE = null;
            if (win32_lsp.CreatePipe(&in_rd, &in_wr, &sa, 0) == 0) {
                self.server_status.set("Pipe error (fallback active)");
                return false;
            }
            if (win32_lsp.CreatePipe(&out_rd, &out_wr, &sa, 0) == 0) {
                _ = win32_lsp.CloseHandle(in_rd.?);
                _ = win32_lsp.CloseHandle(in_wr.?);
                self.server_status.set("Pipe error (fallback active)");
                return false;
            }
            _ = win32_lsp.SetHandleInformation(in_wr.?, win32_lsp.HANDLE_FLAG_INHERIT, 0);
            _ = win32_lsp.SetHandleInformation(out_rd.?, win32_lsp.HANDLE_FLAG_INHERIT, 0);

            const raw_cmd = custom_cmd_opt orelse switch (lang) {
                .cpp => "clangd --log=error",
                .java => "jdtls",
                .go => "gopls serve",
                .systemverilog => "slang-server",
                .zig => "zls",
                .rust => "rust-analyzer",
                .python => "ruff server",
                .typescript => "typescript-language-server --stdio",
                .hdl => "vhdl_ls",
            };
            var cmd_line: [256:0]u8 = @splat(0);
            const full = std.fmt.bufPrint(&cmd_line, "cmd.exe /C {s}", .{raw_cmd}) catch {
                _ = win32_lsp.CloseHandle(in_rd.?);
                _ = win32_lsp.CloseHandle(in_wr.?);
                _ = win32_lsp.CloseHandle(out_rd.?);
                _ = win32_lsp.CloseHandle(out_wr.?);
                return false;
            };
            cmd_line[full.len] = 0;

            var si = win32_lsp.STARTUPINFOA{
                .dwFlags = win32_lsp.STARTF_USESTDHANDLES,
                .hStdInput = in_rd,
                .hStdOutput = out_wr,
                .hStdError = null,
            };
            var pi = win32_lsp.PROCESS_INFORMATION{};
            const ok = win32_lsp.CreateProcessA(
                null,
                &cmd_line,
                null,
                null,
                1,
                win32_lsp.CREATE_NO_WINDOW,
                null,
                null,
                &si,
                &pi,
            );
            _ = win32_lsp.CloseHandle(in_rd.?);
            _ = win32_lsp.CloseHandle(out_wr.?);
            if (ok == 0) {
                _ = win32_lsp.CloseHandle(in_wr.?);
                _ = win32_lsp.CloseHandle(out_rd.?);
                self.server_status.set("Built-in AST/Lexical Mode");
                return false;
            }
            if (pi.hThread) |th| _ = win32_lsp.CloseHandle(th);
            self.win_stdin_h = in_wr;
            self.win_stdout_h = out_rd;
            self.win_proc_h = pi.hProcess;
            self.server_available = true;
            self.server_status.set("Starting LSP server...");
            self.sendInitialize();
            return true;
        } else {
            var in_pipe: [2]c_int = .{ -1, -1 };
            var out_pipe: [2]c_int = .{ -1, -1 };
            if (posix_c.pipe(&in_pipe) != 0) {
                self.server_status.set("Pipe error (fallback active)");
                return false;
            }
            if (posix_c.pipe(&out_pipe) != 0) {
                _ = std.c.close(in_pipe[0]);
                _ = std.c.close(in_pipe[1]);
                self.server_status.set("Pipe error (fallback active)");
                return false;
            }

            const pid = posix_c.fork();
            if (pid < 0) {
                _ = std.c.close(in_pipe[0]);
                _ = std.c.close(in_pipe[1]);
                _ = std.c.close(out_pipe[0]);
                _ = std.c.close(out_pipe[1]);
                self.server_status.set("Fork error (fallback active)");
                return false;
            }

            if (pid == 0) {
                // Child process: connect stdin -> in_pipe[0], stdout -> out_pipe[1], silence stderr
                _ = std.c.close(in_pipe[1]);
                _ = std.c.close(out_pipe[0]);
                _ = posix_c.dup2(in_pipe[0], 0);
                _ = posix_c.dup2(out_pipe[1], 1);
                _ = std.c.close(in_pipe[0]);
                _ = std.c.close(out_pipe[1]);

                const devnull = std.c.open("/dev/null", .{ .ACCMODE = .WRONLY }, @as(c_uint, 0));
                if (devnull >= 0) {
                    _ = posix_c.dup2(devnull, 2);
                    _ = std.c.close(devnull);
                }

                var cmd_buf: [192:0]u8 = @splat(0);
                const raw_cmd = custom_cmd_opt orelse switch (lang) {
                    .cpp => "exec clangd --log=error",
                    .java => "exec jdtls",
                    .go => "exec gopls serve",
                    .systemverilog => "if command -v slang-server >/dev/null 2>&1; then exec slang-server; else exec svls; fi",
                    .zig => "if [ -x \"$ZLS_016_BIN\" ]; then exec \"$ZLS_016_BIN\"; else exec zls; fi",
                    .rust => "exec rust-analyzer",
                    .python => "if command -v ruff >/dev/null 2>&1; then exec ruff server; else exec pyright-langserver --stdio; fi",
                    .typescript => "if command -v typescript-language-server >/dev/null 2>&1; then exec typescript-language-server --stdio; else exec biome lsp-proxy; fi",
                    .hdl => "if command -v vhdl_ls >/dev/null 2>&1; then exec vhdl_ls; else exec verible-verilog-ls; fi",
                };
                const copy_len = @min(raw_cmd.len, cmd_buf.len - 1);
                @memcpy(cmd_buf[0..copy_len], raw_cmd[0..copy_len]);
                cmd_buf[copy_len] = 0;

                const cmd_ptr: [*:0]const u8 = @ptrCast(&cmd_buf);
                const argv = [_:null]?[*:0]const u8{ "/bin/sh", "-c", cmd_ptr };
                _ = posix_c.execv("/bin/sh", &argv);
                std.c._exit(127);
            }

            // Parent process: close unused ends and set non-blocking on both pipes
            _ = std.c.close(in_pipe[0]);
            _ = std.c.close(out_pipe[1]);

            const out_flags = std.c.fcntl(out_pipe[0], F_GETFL, @as(c_int, 0));
            if (out_flags >= 0) {
                _ = std.c.fcntl(out_pipe[0], F_SETFL, out_flags | O_NONBLOCK);
            }
            const in_flags = std.c.fcntl(in_pipe[1], F_GETFL, @as(c_int, 0));
            if (in_flags >= 0) {
                _ = std.c.fcntl(in_pipe[1], F_SETFL, in_flags | O_NONBLOCK);
            }

            self.stdin_fd = in_pipe[1];
            self.stdout_fd = out_pipe[0];
            self.child_pid = pid;
            self.server_available = true;
            self.server_status.set("Starting LSP server...");

            // Immediately send JSON-RPC `initialize` request
            self.sendInitialize();
            return true;
        }
    }

    /// Formats a JSON-RPC 2.0 payload with `Content-Length: <len>\r\n\r\n<body>` and writes it non-blockingly.
    pub fn sendFramedJsonRpc(self: *LspConnection, json_body: []const u8) bool {
        if (json_body.len == 0) return false;
        var header_buf: [64]u8 = undefined;
        const header = std.fmt.bufPrint(&header_buf, "Content-Length: {d}\r\n\r\n", .{json_body.len}) catch return false;
        if (comptime is_windows) {
            const h_in = self.win_stdin_h orelse return false;
            var h_written: win32_lsp.DWORD = 0;
            if (win32_lsp.WriteFile(h_in, header.ptr, @intCast(header.len), &h_written, null) == 0 or h_written == 0) return false;
            var b_written: win32_lsp.DWORD = 0;
            if (win32_lsp.WriteFile(h_in, json_body.ptr, @intCast(json_body.len), &b_written, null) != 0 and b_written > 0) {
                self.rpc_sent +|= 1;
                return true;
            }
            return false;
        } else {
            if (self.stdin_fd < 0) return false;
            const h_written = std.c.write(self.stdin_fd, header.ptr, header.len);
            if (h_written <= 0) return false;
            const b_written = std.c.write(self.stdin_fd, json_body.ptr, json_body.len);
            if (b_written > 0) {
                self.rpc_sent +|= 1;
                return true;
            }
            return false;
        }
    }

    pub fn sendInitialize(self: *LspConnection) void {
        const req_id = self.next_rpc_id;
        self.next_rpc_id +%= 1;
        var buf: [384]u8 = undefined;
        const body = std.fmt.bufPrint(
            &buf,
            "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"initialize\",\"params\":{{\"processId\":null,\"rootUri\":\"file:///workspace\",\"capabilities\":{{}}}}}}",
            .{req_id},
        ) catch return;
        _ = self.sendFramedJsonRpc(body);
    }

    pub fn sendInitializedNotification(self: *LspConnection) void {
        const body = "{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":{}}";
        _ = self.sendFramedJsonRpc(body);
    }

    /// Sends `textDocument/didOpen` or `textDocument/didChange` with JSON-escaped source text.
    pub fn notifyDocumentSync(
        self: *LspConnection,
        arena: std.mem.Allocator,
        file_path: []const u8,
        text: []const u8,
        version: u32,
    ) void {
        if (!self.isRunning()) return;
        const escaped = escapeJsonString(arena, text) catch return;
        const lang_id = self.language.languageId();

        if (!self.doc_opened) {
            const payload = std.fmt.allocPrint(
                arena,
                "{{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{{\"textDocument\":{{\"uri\":\"file:///workspace/{s}\",\"languageId\":\"{s}\",\"version\":{d},\"text\":\"{s}\"}}}}}}",
                .{ file_path, lang_id, version, escaped },
            ) catch return;
            if (self.sendFramedJsonRpc(payload)) {
                self.doc_opened = true;
            }
        } else {
            const payload = std.fmt.allocPrint(
                arena,
                "{{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didChange\",\"params\":{{\"textDocument\":{{\"uri\":\"file:///workspace/{s}\",\"version\":{d}}},\"contentChanges\":[{{\"text\":\"{s}\"}}]}}}}",
                .{ file_path, version, escaped },
            ) catch return;
            _ = self.sendFramedJsonRpc(payload);
        }
    }

    pub fn notifyDocumentSave(self: *LspConnection, arena: std.mem.Allocator, file_path: []const u8) void {
        if (!self.isRunning()) return;
        const payload = std.fmt.allocPrint(
            arena,
            "{{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didSave\",\"params\":{{\"textDocument\":{{\"uri\":\"file:///workspace/{s}\"}}}}}}",
            .{file_path},
        ) catch return;
        _ = self.sendFramedJsonRpc(payload);
    }

    /// Sends a non-blocking `textDocument/completion` JSON-RPC 2.0 request to the language server.
    pub fn requestCompletion(
        self: *LspConnection,
        arena: std.mem.Allocator,
        file_path: []const u8,
        line_1based: u32,
        col_1based: u32,
        buffer_id: u32,
        cursor_offset: usize,
    ) void {
        self.completion_buffer_id = buffer_id;
        self.completion_cursor_offset = cursor_offset;
        if (!self.isRunning()) return;

        const req_id = self.next_rpc_id;
        self.next_rpc_id +%= 1;
        const line0 = line_1based -| 1;
        const col0 = col_1based -| 1;
        const payload = std.fmt.allocPrint(
            arena,
            "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"textDocument/completion\",\"params\":{{\"textDocument\":{{\"uri\":\"file:///workspace/{s}\"}},\"position\":{{\"line\":{d},\"character\":{d}}}}}}}",
            .{ req_id, file_path, line0, col0 },
        ) catch return;
        _ = self.sendFramedJsonRpc(payload);
    }

    /// Computes instant context-aware completions (member access after `.`, `::`, `->`, buffer symbols,
    /// standard library APIs, and language keywords) and queues an async `textDocument/completion` request
    /// if the LSP daemon is running.
    pub fn updateCompletionsForCursor(
        self: *LspConnection,
        arena: std.mem.Allocator,
        file_path: []const u8,
        source: []const u8,
        cursor_offset: usize,
        line_1based: u32,
        col_1based: u32,
        buffer_id: u32,
    ) usize {
        self.completion_buffer_id = buffer_id;
        self.completion_cursor_offset = cursor_offset;
        self.completion_count = computeCompletions(source, cursor_offset, self.language, &self.completions);
        self.completions_dirty = true;

        if (self.isRunning() and self.completion_count > 0) {
            self.requestCompletion(arena, file_path, line_1based, col_1based, buffer_id, cursor_offset);
        }
        return self.completion_count;
    }

    /// Exports the active `completions` slice as `abi.CompletionItemV1` items in `out`.
    pub fn exportAbiCompletions(self: *const LspConnection, out: *[MaxCompletions]CompletionItemV1) []const CompletionItemV1 {
        const n = @min(self.completion_count, MaxCompletions);
        for (0..n) |i| {
            out[i] = self.completions[i].toAbi();
        }
        return out[0..n];
    }

    /// Polls the non-blocking stdout pipe for JSON-RPC responses and `publishDiagnostics` notifications.
    /// Returns `true` if any LSP messages were processed on this tick.
    pub fn pollIo(self: *LspConnection) bool {
        if (comptime is_windows) {
            const h_out = self.win_stdout_h orelse return false;
            var temp: [2048]u8 = undefined;
            var any_activity = false;
            var loops: usize = 0;

            while (loops < 4) : (loops += 1) {
                var avail: win32_lsp.DWORD = 0;
                if (win32_lsp.PeekNamedPipe(h_out, null, 0, null, &avail, null) == 0) {
                    self.stopServer();
                    self.server_available = false;
                    self.server_status.set("Built-in AST/Lexical Mode");
                    return true;
                }
                if (avail == 0) break;
                const to_read: win32_lsp.DWORD = @intCast(@min(temp.len, @as(usize, avail)));
                var bytes_read: win32_lsp.DWORD = 0;
                if (win32_lsp.ReadFile(h_out, &temp, to_read, &bytes_read, null) != 0 and bytes_read > 0) {
                    self.ingestBytes(temp[0..@intCast(bytes_read)]);
                    any_activity = true;
                } else {
                    break;
                }
            }

            if (self.win_proc_h) |proc_h| {
                if (win32_lsp.WaitForSingleObject(proc_h, 0) == win32_lsp.WAIT_OBJECT_0) {
                    self.stopServer();
                    self.server_available = false;
                    self.server_status.set("Built-in AST/Lexical Mode");
                    return true;
                }
            }
            return any_activity;
        } else {
            if (self.stdout_fd < 0) return false;

            var temp: [2048]u8 = undefined;
            var any_activity = false;
            var loops: usize = 0;

            while (loops < 4) : (loops += 1) {
                const n = std.c.read(self.stdout_fd, &temp, temp.len);
                if (n > 0) {
                    const u_n: usize = @intCast(n);
                    self.ingestBytes(temp[0..u_n]);
                    any_activity = true;
                } else if (n == 0) {
                    // Child process closed stdout (binary missing or exited)
                    self.stopServer();
                    self.server_available = false;
                    self.server_status.set("Built-in AST/Lexical Mode");
                    return true;
                } else {
                    break;
                }
            }

            if (self.child_pid > 0) {
                var status: c_int = 0;
                const w = std.c.waitpid(self.child_pid, &status, WNOHANG);
                if (w == self.child_pid) {
                    self.child_pid = -1;
                    self.stopServer();
                    self.server_available = false;
                    self.server_status.set("Built-in AST/Lexical Mode");
                    return true;
                }
            }

            return any_activity;
        }
    }

    /// Feeds raw LSP stream bytes into the parser, handling both complete `Content-Length` frames
    /// and large streaming notifications.
    pub fn ingestBytes(self: *LspConnection, chunk: []const u8) void {
        // Fast path only when `rx_buf` is empty and `chunk` starts a new frame directly
        if (self.rx_len == 0 and std.mem.indexOfPos(u8, chunk, 0, "Content-Length:") != null) {
            var rest = chunk;
            while (parseNextFramedMessage(rest)) |parsed| {
                if (parsed.body.len > 0) {
                    self.handleJsonRpcMessage(parsed.body);
                }
                rest = rest[parsed.consumed..];
            }
            const rem = @min(rest.len, self.rx_buf.len);
            if (rem > 0) {
                @memcpy(self.rx_buf[0..rem], rest[rest.len - rem ..]);
            }
            self.rx_len = rem;
            return;
        }

        const space = self.rx_buf.len - self.rx_len;
        const to_copy = @min(space, chunk.len);
        if (to_copy > 0) {
            @memcpy(self.rx_buf[self.rx_len .. self.rx_len + to_copy], chunk[0..to_copy]);
            self.rx_len += to_copy;
        }

        while (parseNextFramedMessage(self.rx_buf[0..self.rx_len])) |parsed| {
            if (parsed.body.len > 0) {
                self.handleJsonRpcMessage(parsed.body);
            }
            const rem = self.rx_len - parsed.consumed;
            if (rem > 0) {
                std.mem.copyForwards(u8, self.rx_buf[0..rem], self.rx_buf[parsed.consumed..self.rx_len]);
            }
            self.rx_len = rem;
        }
    }

    pub fn handleJsonRpcMessage(self: *LspConnection, json: []const u8) void {
        self.rpc_received +|= 1;

        if (!self.initialized and std.mem.indexOfPos(u8, json, 0, "\"capabilities\"") != null) {
            self.initialized = true;
            self.server_available = true;
            self.server_status.set("Connected (LSP Active)");
            self.sendInitializedNotification();
            return;
        }

        if (std.mem.indexOfPos(u8, json, 0, "publishDiagnostics") != null) {
            self.diagnostic_count = parsePublishDiagnostics(json, &self.diagnostics);
            self.has_lsp_diagnostics = true;
            self.server_status.set("Connected (Diagnostics Synced)");
            return;
        }

        // Parse `textDocument/completion` response (`"items":[...]` or `"result":[...]`)
        if (std.mem.indexOfPos(u8, json, 0, "\"label\"") != null and
            (std.mem.indexOfPos(u8, json, 0, "\"items\"") != null or std.mem.indexOfPos(u8, json, 0, "\"insertText\"") != null))
        {
            const parsed_n = parseCompletionItemsResponse(json, self.completion_InferredPrefixLen(), &self.completions);
            if (parsed_n > 0) {
                self.completion_count = parsed_n;
                self.completions_dirty = true;
                self.server_status.set("Connected (Completions Active)");
            }
        }
    }

    fn completion_InferredPrefixLen(self: *const LspConnection) u16 {
        if (self.completion_count > 0) return self.completions[0].replace_prefix_len;
        return 0;
    }
};

pub const FramedMessage = struct {
    body: []const u8,
    consumed: usize,
};

/// Parses a single `Content-Length: <N>\r\n\r\n<JSON>` frame from `stream`.
pub fn parseNextFramedMessage(stream: []const u8) ?FramedMessage {
    const cl_prefix = "Content-Length:";
    const cl_pos = std.mem.indexOfPos(u8, stream, 0, cl_prefix) orelse return null;
    const header_end = std.mem.indexOfPos(u8, stream, cl_pos, "\r\n\r\n") orelse return null;
    const body_start = header_end + 4;

    const len_slice = std.mem.trim(u8, stream[cl_pos + cl_prefix.len .. header_end], " \t\r\n");
    var digits_end: usize = 0;
    while (digits_end < len_slice.len and std.ascii.isDigit(len_slice[digits_end])) : (digits_end += 1) {}
    if (digits_end == 0) {
        return .{ .body = "", .consumed = body_start };
    }

    const body_len = std.fmt.parseInt(usize, len_slice[0..digits_end], 10) catch {
        return .{ .body = "", .consumed = body_start };
    };
    // Guard against corrupt/oversized Content-Length headers wedging the 8 KB rx_buf
    if (body_len > 65536) {
        return .{ .body = "", .consumed = body_start };
    }
    if (body_start + body_len > stream.len) return null;

    return .{
        .body = stream[body_start .. body_start + body_len],
        .consumed = body_start + body_len,
    };
}

/// Extracts diagnostics from an LSP `textDocument/publishDiagnostics` JSON payload without heap allocation.
pub fn parsePublishDiagnostics(json: []const u8, out: []LspDiagnostic) usize {
    const diag_arr_pos = std.mem.indexOfPos(u8, json, 0, "\"diagnostics\"") orelse return 0;
    var pos = diag_arr_pos + 13;
    var count: usize = 0;

    while (count < out.len and pos < json.len) {
        const msg_key = std.mem.indexOfPos(u8, json, pos, "\"message\"") orelse break;
        // Find `"line":` prior to or near `"message"`
        const search_start = if (msg_key > 240) msg_key - 240 else pos;
        const region = json[search_start..@min(json.len, msg_key + 240)];

        var line_1based: u32 = 1;
        var col_1based: u32 = 1;
        if (extractJsonUintField(region, "\"line\"")) |l0| {
            line_1based = l0 + 1;
        }
        if (extractJsonUintField(region, "\"character\"")) |c0| {
            col_1based = c0 + 1;
        }

        var sev: LspSeverity = .err;
        if (extractJsonUintField(region, "\"severity\"")) |s_val| {
            sev = switch (s_val) {
                1 => .err,
                2 => .warn,
                3 => .info,
                else => .hint,
            };
        }

        var diag = LspDiagnostic{
            .line = line_1based,
            .col = col_1based,
            .severity = sev,
        };
        if (extractJsonStringField(json[msg_key..], "\"message\"")) |msg_val| {
            diag.message.set(msg_val);
        } else {
            diag.message.set("LSP diagnostic issue");
        }

        out[count] = diag;
        count += 1;
        pos = msg_key + 9;
    }

    return count;
}

fn extractJsonUintField(src: []const u8, key: []const u8) ?u32 {
    const idx = std.mem.indexOfPos(u8, src, 0, key) orelse return null;
    var p = idx + key.len;
    while (p < src.len and (src[p] == ' ' or src[p] == '\t' or src[p] == ':')) : (p += 1) {}
    var end = p;
    while (end < src.len and std.ascii.isDigit(src[end])) : (end += 1) {}
    if (end == p) return null;
    return std.fmt.parseInt(u32, src[p..end], 10) catch null;
}

fn extractJsonStringField(src: []const u8, key: []const u8) ?[]const u8 {
    const idx = std.mem.indexOfPos(u8, src, 0, key) orelse return null;
    var p = idx + key.len;
    while (p < src.len and (src[p] == ' ' or src[p] == '\t' or src[p] == ':')) : (p += 1) {}
    if (p >= src.len or src[p] != '"') return null;
    p += 1;
    var end = p;
    while (end < src.len) : (end += 1) {
        if (src[end] == '\\' and end + 1 < src.len) {
            end += 1;
            continue;
        }
        if (src[end] == '"') break;
    }
    return src[p..end];
}

pub fn escapeJsonString(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var out = std.ArrayList(u8).empty;
    try out.ensureTotalCapacity(allocator, input.len + 32);
    for (input) |b| {
        switch (b) {
            '"' => try out.appendSlice(allocator, "\\\""),
            '\\' => try out.appendSlice(allocator, "\\\\"),
            '\n' => try out.appendSlice(allocator, "\\n"),
            '\r' => try out.appendSlice(allocator, "\\r"),
            '\t' => try out.appendSlice(allocator, "\\t"),
            else => {
                if (b >= 0x20) try out.append(allocator, b);
            },
        }
    }
    return out.items;
}

// ============================================================================
// LSP `textDocument/completion` Response Parser & Context-Aware Intellisense
// ============================================================================

/// Parses a JSON-RPC `textDocument/completion` response (`items` array) into `out`.
pub fn parseCompletionItemsResponse(json: []const u8, replace_prefix_len: u16, out: []LspCompletionItem) usize {
    var pos: usize = 0;
    var count: usize = 0;

    while (count < out.len and pos < json.len) {
        const lbl_key = std.mem.indexOfPos(u8, json, pos, "\"label\"") orelse break;
        const region_end = @min(json.len, lbl_key + 320);
        const region = json[lbl_key..region_end];

        if (extractJsonStringField(region, "\"label\"")) |lbl_val| {
            if (lbl_val.len > 0) {
                var item = LspCompletionItem{
                    .kind = 1,
                    .replace_prefix_len = replace_prefix_len,
                };
                item.label.set(lbl_val);
                if (extractJsonStringField(region, "\"detail\"")) |det_val| {
                    item.detail.set(det_val);
                } else {
                    item.detail.set("LSP completion");
                }
                if (extractJsonStringField(region, "\"insertText\"")) |ins_val| {
                    item.insert_text.set(ins_val);
                } else {
                    item.insert_text.set(lbl_val);
                }
                if (extractJsonUintField(region, "\"kind\"")) |lsp_kind| {
                    item.kind = switch (lsp_kind) {
                        2, 3 => 1, // Method / Function
                        7, 8, 22 => 2, // Class / Interface / Struct
                        14 => 0, // Keyword
                        15 => 3, // Snippet
                        else => 4,
                    };
                }
                out[count] = item;
                count += 1;
            }
        }
        pos = lbl_key + 7;
    }
    return count;
}

const BuiltinCandidate = struct {
    trigger: []const u8, // "" for general prefix match, or receiver prefix like "std::", "fmt.", "System.", "System.out."
    label: []const u8,
    detail: []const u8,
    insert_text: []const u8,
    kind: u8, // 0=kw, 1=fn, 2=type, 3=snippet, 4=field
};

const CPP_BUILTINS = [_]BuiltinCandidate{
    // `std::` member completions
    .{ .trigger = "std::", .label = "vector", .detail = "std::vector<T>", .insert_text = "vector<", .kind = 2 },
    .{ .trigger = "std::", .label = "string", .detail = "std::string", .insert_text = "string", .kind = 2 },
    .{ .trigger = "std::", .label = "string_view", .detail = "std::string_view", .insert_text = "string_view", .kind = 2 },
    .{ .trigger = "std::", .label = "unique_ptr", .detail = "std::unique_ptr<T>", .insert_text = "unique_ptr<", .kind = 2 },
    .{ .trigger = "std::", .label = "shared_ptr", .detail = "std::shared_ptr<T>", .insert_text = "shared_ptr<", .kind = 2 },
    .{ .trigger = "std::", .label = "make_unique", .detail = "std::make_unique<T>(...)", .insert_text = "make_unique<", .kind = 1 },
    .{ .trigger = "std::", .label = "cout", .detail = "std::ostream", .insert_text = "cout << ", .kind = 4 },
    .{ .trigger = "std::", .label = "endl", .detail = "std::ostream manipulator", .insert_text = "endl", .kind = 4 },
    .{ .trigger = "std::", .label = "move", .detail = "constexpr T&& std::move(T&&)", .insert_text = "move(", .kind = 1 },
    .{ .trigger = "std::", .label = "optional", .detail = "std::optional<T>", .insert_text = "optional<", .kind = 2 },
    .{ .trigger = "std::", .label = "unordered_map", .detail = "std::unordered_map<K, V>", .insert_text = "unordered_map<", .kind = 2 },
    // `.` or `->` container methods
    .{ .trigger = ".", .label = "push_back", .detail = "void push_back(const T&)", .insert_text = "push_back(", .kind = 1 },
    .{ .trigger = ".", .label = "emplace_back", .detail = "T& emplace_back(Args&&...)", .insert_text = "emplace_back(", .kind = 1 },
    .{ .trigger = ".", .label = "size", .detail = "size_t size() const noexcept", .insert_text = "size()", .kind = 1 },
    .{ .trigger = ".", .label = "empty", .detail = "bool empty() const noexcept", .insert_text = "empty()", .kind = 1 },
    .{ .trigger = ".", .label = "begin", .detail = "iterator begin() noexcept", .insert_text = "begin()", .kind = 1 },
    .{ .trigger = ".", .label = "end", .detail = "iterator end() noexcept", .insert_text = "end()", .kind = 1 },
    .{ .trigger = ".", .label = "clear", .detail = "void clear() noexcept", .insert_text = "clear()", .kind = 1 },
    // General C/C++ keywords & types
    .{ .trigger = "", .label = "#include", .detail = "preprocessor directive", .insert_text = "#include <", .kind = 3 },
    .{ .trigger = "", .label = "#pragma once", .detail = "header guard", .insert_text = "#pragma once\n", .kind = 3 },
    .{ .trigger = "", .label = "namespace", .detail = "C++ namespace declaration", .insert_text = "namespace ", .kind = 0 },
    .{ .trigger = "", .label = "class", .detail = "C++ class declaration", .insert_text = "class ", .kind = 0 },
    .{ .trigger = "", .label = "struct", .detail = "C/C++ struct declaration", .insert_text = "struct ", .kind = 0 },
    .{ .trigger = "", .label = "template", .detail = "template<typename T>", .insert_text = "template <typename T>\n", .kind = 3 },
    .{ .trigger = "", .label = "constexpr", .detail = "compile-time constant", .insert_text = "constexpr ", .kind = 0 },
    .{ .trigger = "", .label = "noexcept", .detail = "no-throw specifier", .insert_text = "noexcept", .kind = 0 },
    .{ .trigger = "", .label = "nullptr", .detail = "std::nullptr_t literal", .insert_text = "nullptr", .kind = 0 },
    .{ .trigger = "", .label = "override", .detail = "virtual method override", .insert_text = "override", .kind = 0 },
    .{ .trigger = "", .label = "std::vector", .detail = "<vector> dynamic array", .insert_text = "std::vector<", .kind = 2 },
    .{ .trigger = "", .label = "std::string", .detail = "<string> UTF-8 string", .insert_text = "std::string", .kind = 2 },
    .{ .trigger = "", .label = "uint32_t", .detail = "<cstdint> unsigned 32-bit int", .insert_text = "uint32_t", .kind = 2 },
    .{ .trigger = "", .label = "uint64_t", .detail = "<cstdint> unsigned 64-bit int", .insert_text = "uint64_t", .kind = 2 },
};

const JAVA_BUILTINS = [_]BuiltinCandidate{
    // `System.` and `System.out.` completions
    .{ .trigger = "System.out.", .label = "println", .detail = "void println(String x)", .insert_text = "println(\"", .kind = 1 },
    .{ .trigger = "System.out.", .label = "printf", .detail = "PrintStream printf(String fmt, ...)", .insert_text = "printf(\"", .kind = 1 },
    .{ .trigger = "System.", .label = "out.println", .detail = "PrintStream System.out", .insert_text = "out.println(\"", .kind = 1 },
    .{ .trigger = "System.", .label = "currentTimeMillis", .detail = "long currentTimeMillis()", .insert_text = "currentTimeMillis()", .kind = 1 },
    // `.` Java object/collection methods
    .{ .trigger = ".", .label = "stream", .detail = "Stream<E> stream()", .insert_text = "stream()", .kind = 1 },
    .{ .trigger = ".", .label = "toString", .detail = "String toString()", .insert_text = "toString()", .kind = 1 },
    .{ .trigger = ".", .label = "equals", .detail = "boolean equals(Object obj)", .insert_text = "equals(", .kind = 1 },
    .{ .trigger = ".", .label = "hashCode", .detail = "int hashCode()", .insert_text = "hashCode()", .kind = 1 },
    .{ .trigger = ".", .label = "size", .detail = "int size()", .insert_text = "size()", .kind = 1 },
    .{ .trigger = ".", .label = "length", .detail = "int length()", .insert_text = "length()", .kind = 1 },
    .{ .trigger = ".", .label = "isEmpty", .detail = "boolean isEmpty()", .insert_text = "isEmpty()", .kind = 1 },
    .{ .trigger = ".", .label = "add", .detail = "boolean add(E e)", .insert_text = "add(", .kind = 1 },
    .{ .trigger = ".", .label = "get", .detail = "E get(int index)", .insert_text = "get(", .kind = 1 },
    // General Java keywords, types & snippets
    .{ .trigger = "", .label = "public static void main", .detail = "main(String[] args) entrypoint", .insert_text = "public static void main(String[] args) {\n    ", .kind = 3 },
    .{ .trigger = "", .label = "System.out.println", .detail = "print line to stdout", .insert_text = "System.out.println(\"", .kind = 3 },
    .{ .trigger = "", .label = "public class", .detail = "Java class declaration", .insert_text = "public class ", .kind = 0 },
    .{ .trigger = "", .label = "public record", .detail = "Java immutable data record", .insert_text = "public record ", .kind = 0 },
    .{ .trigger = "", .label = "public interface", .detail = "Java interface declaration", .insert_text = "public interface ", .kind = 0 },
    .{ .trigger = "", .label = "private final", .detail = "immutable field modifier", .insert_text = "private final ", .kind = 0 },
    .{ .trigger = "", .label = "String", .detail = "java.lang.String", .insert_text = "String", .kind = 2 },
    .{ .trigger = "", .label = "List", .detail = "java.util.List<E>", .insert_text = "List<", .kind = 2 },
    .{ .trigger = "", .label = "Map", .detail = "java.util.Map<K, V>", .insert_text = "Map<", .kind = 2 },
    .{ .trigger = "", .label = "Optional", .detail = "java.util.Optional<T>", .insert_text = "Optional<", .kind = 2 },
    .{ .trigger = "", .label = "ArrayList", .detail = "java.util.ArrayList<E>", .insert_text = "ArrayList<", .kind = 2 },
    .{ .trigger = "", .label = "HashMap", .detail = "java.util.HashMap<K, V>", .insert_text = "HashMap<", .kind = 2 },
    .{ .trigger = "", .label = "@Override", .detail = "method override annotation", .insert_text = "@Override", .kind = 0 },
};

const GO_BUILTINS = [_]BuiltinCandidate{
    // `fmt.` package completions
    .{ .trigger = "fmt.", .label = "Printf", .detail = "func Printf(format string, a ...any)", .insert_text = "Printf(\"", .kind = 1 },
    .{ .trigger = "fmt.", .label = "Println", .detail = "func Println(a ...any)", .insert_text = "Println(", .kind = 1 },
    .{ .trigger = "fmt.", .label = "Sprintf", .detail = "func Sprintf(format string, a ...any) string", .insert_text = "Sprintf(\"", .kind = 1 },
    .{ .trigger = "fmt.", .label = "Errorf", .detail = "func Errorf(format string, a ...any) error", .insert_text = "Errorf(\"", .kind = 1 },
    // `context.` package completions
    .{ .trigger = "context.", .label = "Background", .detail = "func Background() Context", .insert_text = "Background()", .kind = 1 },
    .{ .trigger = "context.", .label = "WithCancel", .detail = "func WithCancel(parent Context)", .insert_text = "WithCancel(", .kind = 1 },
    .{ .trigger = "context.", .label = "WithTimeout", .detail = "func WithTimeout(parent Context, d Duration)", .insert_text = "WithTimeout(", .kind = 1 },
    .{ .trigger = "context.", .label = "Context", .detail = "type Context interface", .insert_text = "Context", .kind = 2 },
    // `http.` package completions
    .{ .trigger = "http.", .label = "ListenAndServe", .detail = "func ListenAndServe(addr string, h Handler) error", .insert_text = "ListenAndServe(\"", .kind = 1 },
    .{ .trigger = "http.", .label = "HandleFunc", .detail = "func HandleFunc(pattern string, h func)", .insert_text = "HandleFunc(\"", .kind = 1 },
    .{ .trigger = "http.", .label = "StatusOK", .detail = "const StatusOK = 200", .insert_text = "StatusOK", .kind = 4 },
    // `.` general Go methods
    .{ .trigger = ".", .label = "Error", .detail = "func (error) Error() string", .insert_text = "Error()", .kind = 1 },
    .{ .trigger = ".", .label = "Close", .detail = "func (io.Closer) Close() error", .insert_text = "Close()", .kind = 1 },
    .{ .trigger = ".", .label = "String", .detail = "func (fmt.Stringer) String() string", .insert_text = "String()", .kind = 1 },
    // General Go keywords, builtins & snippets
    .{ .trigger = "", .label = "if err != nil", .detail = "error check guard", .insert_text = "if err != nil {\n    return err\n}", .kind = 3 },
    .{ .trigger = "", .label = "func", .detail = "Go function declaration", .insert_text = "func ", .kind = 0 },
    .{ .trigger = "", .label = "type struct", .detail = "Go struct definition", .insert_text = "type Name struct {\n    ", .kind = 3 },
    .{ .trigger = "", .label = "type interface", .detail = "Go interface definition", .insert_text = "type Name interface {\n    ", .kind = 3 },
    .{ .trigger = "", .label = "package main", .detail = "executable package clause", .insert_text = "package main\n", .kind = 0 },
    .{ .trigger = "", .label = "defer", .detail = "deferred function call", .insert_text = "defer ", .kind = 0 },
    .{ .trigger = "", .label = "go func", .detail = "spawn goroutine", .insert_text = "go func() {\n    ", .kind = 3 },
    .{ .trigger = "", .label = "append", .detail = "func append(slice []T, elems ...T) []T", .insert_text = "append(", .kind = 1 },
    .{ .trigger = "", .label = "make", .detail = "func make(t Type, size ...IntegerType) Type", .insert_text = "make(", .kind = 1 },
    .{ .trigger = "", .label = "context.Context", .detail = "context cancellation interface", .insert_text = "context.Context", .kind = 2 },
    .{ .trigger = "", .label = "error", .detail = "built-in error interface", .insert_text = "error", .kind = 2 },
};

const SV_BUILTINS = [_]BuiltinCandidate{
    // SystemVerilog (`slang`) sequential & combinational blocks
    .{ .trigger = "", .label = "always_ff", .detail = "sequential flip-flop block (IEEE 1800)", .insert_text = "always_ff @(posedge clk or negedge rst_n) begin\n    ", .kind = 3 },
    .{ .trigger = "", .label = "always_comb", .detail = "combinational logic block (IEEE 1800)", .insert_text = "always_comb begin\n    ", .kind = 3 },
    .{ .trigger = "", .label = "always_latch", .detail = "latched logic block (IEEE 1800)", .insert_text = "always_latch begin\n    ", .kind = 3 },
    .{ .trigger = "", .label = "module", .detail = "SystemVerilog module declaration", .insert_text = "module ", .kind = 0 },
    .{ .trigger = "", .label = "endmodule", .detail = "close module declaration", .insert_text = "endmodule", .kind = 0 },
    .{ .trigger = "", .label = "interface", .detail = "SystemVerilog bus interface", .insert_text = "interface ", .kind = 0 },
    .{ .trigger = "", .label = "logic", .detail = "4-state synthesizable signal type", .insert_text = "logic ", .kind = 2 },
    .{ .trigger = "", .label = "bit", .detail = "2-state simulation type", .insert_text = "bit ", .kind = 2 },
    .{ .trigger = "", .label = "assign", .detail = "continuous combinational assignment", .insert_text = "assign ", .kind = 0 },
    .{ .trigger = "", .label = "parameter", .detail = "module parameter constant", .insert_text = "parameter int ", .kind = 0 },
    .{ .trigger = "", .label = "localparam", .detail = "local compile-time constant", .insert_text = "localparam int ", .kind = 0 },
    .{ .trigger = "", .label = "posedge", .detail = "rising clock edge trigger", .insert_text = "posedge clk", .kind = 0 },
    .{ .trigger = "", .label = "negedge", .detail = "falling reset edge trigger", .insert_text = "negedge rst_n", .kind = 0 },
    .{ .trigger = "", .label = "typedef enum", .detail = "synthesizable FSM state enum", .insert_text = "typedef enum logic [1:0] {\n    IDLE = 2'b00,\n    BUSY = 2'b01\n} state_t;", .kind = 3 },
    .{ .trigger = "", .label = "typedef struct packed", .detail = "packed hardware bundle struct", .insert_text = "typedef struct packed {\n    logic valid;\n    logic [7:0] data;\n} packet_t;", .kind = 3 },
    .{ .trigger = "", .label = "unique case", .detail = "parallel synthesizable case statement", .insert_text = "unique case (", .kind = 3 },
    .{ .trigger = "", .label = "assert property", .detail = "SVA concurrent assertion", .insert_text = "assert property (@(posedge clk) disable iff (!rst_n) ", .kind = 3 },
    // Compiler directives & VCD simulation tasks
    .{ .trigger = "", .label = "`timescale", .detail = "simulation time unit / precision", .insert_text = "`timescale 1ns / 1ps\n", .kind = 3 },
    .{ .trigger = "", .label = "`include", .detail = "preprocessor file include", .insert_text = "`include \"", .kind = 3 },
    .{ .trigger = "", .label = "`define", .detail = "preprocessor macro definition", .insert_text = "`define ", .kind = 3 },
    .{ .trigger = "", .label = "$dumpfile", .detail = "specify VCD waveform output file", .insert_text = "$dumpfile(\"sim.vcd\");", .kind = 1 },
    .{ .trigger = "", .label = "$dumpvars", .detail = "dump module signal hierarchy to VCD", .insert_text = "$dumpvars(0, ", .kind = 1 },
    .{ .trigger = "", .label = "$display", .detail = "print formatted simulation log", .insert_text = "$display(\"", .kind = 1 },
    .{ .trigger = "", .label = "$finish", .detail = "terminate simulation run", .insert_text = "$finish;", .kind = 1 },
    .{ .trigger = "", .label = "$clog2", .detail = "ceiling log2 bit-width function", .insert_text = "$clog2(", .kind = 1 },
};

const ZIG_BUILTINS = [_]BuiltinCandidate{
    // `std.` member completions
    .{ .trigger = "std.", .label = "mem.eql", .detail = "fn eql(comptime T, a, b) bool", .insert_text = "mem.eql(u8, ", .kind = 1 },
    .{ .trigger = "std.", .label = "mem.indexOfPos", .detail = "fn indexOfPos(comptime T, slice, start, needle)", .insert_text = "mem.indexOfPos(u8, ", .kind = 1 },
    .{ .trigger = "std.", .label = "fmt.bufPrint", .detail = "fn bufPrint(buf: []u8, comptime fmt, args)", .insert_text = "fmt.bufPrint(&buf, \"{}\", .{", .kind = 1 },
    .{ .trigger = "std.", .label = "fmt.allocPrint", .detail = "fn allocPrint(gpa, comptime fmt, args)", .insert_text = "fmt.allocPrint(allocator, \"{}\", .{", .kind = 1 },
    .{ .trigger = "std.", .label = "testing.expect", .detail = "fn expect(ok: bool) !void", .insert_text = "testing.expect(", .kind = 1 },
    .{ .trigger = "std.", .label = "testing.expectEqual", .detail = "fn expectEqual(expected, actual) !void", .insert_text = "testing.expectEqual(", .kind = 1 },
    .{ .trigger = "std.", .label = "testing.expectEqualStrings", .detail = "fn expectEqualStrings(expected, actual) !void", .insert_text = "testing.expectEqualStrings(", .kind = 1 },
    .{ .trigger = "std.", .label = "ArrayList", .detail = "std.ArrayList(T) unmanaged container", .insert_text = "ArrayList(u8).empty", .kind = 2 },
    .{ .trigger = "std.", .label = "debug.print", .detail = "fn print(comptime fmt, args) void", .insert_text = "debug.print(\"{}\\n\", .{", .kind = 1 },
    // `@` compiler builtins & general Zig keywords
    .{ .trigger = "", .label = "@import", .detail = "import module or file", .insert_text = "@import(\"", .kind = 1 },
    .{ .trigger = "", .label = "@intCast", .detail = "convert integer type safely", .insert_text = "@intCast(", .kind = 1 },
    .{ .trigger = "", .label = "@floatFromInt", .detail = "convert integer to float", .insert_text = "@floatFromInt(", .kind = 1 },
    .{ .trigger = "", .label = "@intFromFloat", .detail = "convert float to integer", .insert_text = "@intFromFloat(", .kind = 1 },
    .{ .trigger = "", .label = "@ptrCast", .detail = "convert pointer type", .insert_text = "@ptrCast(", .kind = 1 },
    .{ .trigger = "", .label = "@alignCast", .detail = "widen pointer alignment", .insert_text = "@alignCast(", .kind = 1 },
    .{ .trigger = "", .label = "@splat", .detail = "initialize array/vector with scalar", .insert_text = "@splat(", .kind = 1 },
    .{ .trigger = "", .label = "@This", .detail = "enclosing struct/union/enum type", .insert_text = "@This()", .kind = 2 },
    .{ .trigger = "", .label = "pub fn", .detail = "public Zig function declaration", .insert_text = "pub fn ", .kind = 0 },
    .{ .trigger = "", .label = "pub const", .detail = "public Zig constant / type declaration", .insert_text = "pub const ", .kind = 0 },
    .{ .trigger = "", .label = "errdefer", .detail = "execute on error return path", .insert_text = "errdefer ", .kind = 0 },
    .{ .trigger = "", .label = "comptime", .detail = "compile-time evaluation block", .insert_text = "comptime ", .kind = 0 },
};

const RUST_BUILTINS = [_]BuiltinCandidate{
    .{ .trigger = "std::", .label = "collections::HashMap", .detail = "std::collections::HashMap<K, V>", .insert_text = "collections::HashMap", .kind = 2 },
    .{ .trigger = "std::", .label = "sync::Arc", .detail = "thread-safe reference-counting pointer", .insert_text = "sync::Arc<", .kind = 2 },
    .{ .trigger = "std::", .label = "fs::read_to_string", .detail = "fn read_to_string(path) -> io::Result<String>", .insert_text = "fs::read_to_string(", .kind = 1 },
    .{ .trigger = ".", .label = "unwrap_or_else", .detail = "fn unwrap_or_else(self, op) -> T", .insert_text = "unwrap_or_else(|err| ", .kind = 1 },
    .{ .trigger = ".", .label = "map_err", .detail = "fn map_err(self, op) -> Result<T, F>", .insert_text = "map_err(|e| ", .kind = 1 },
    .{ .trigger = ".", .label = "iter", .detail = "fn iter(&self) -> Iter<'_, T>", .insert_text = "iter()", .kind = 1 },
    .{ .trigger = ".", .label = "collect", .detail = "fn collect<B: FromIterator>(self) -> B", .insert_text = "collect::<Vec<_>>()", .kind = 1 },
    .{ .trigger = "", .label = "pub fn", .detail = "public Rust function", .insert_text = "pub fn ", .kind = 0 },
    .{ .trigger = "", .label = "pub struct", .detail = "public Rust struct", .insert_text = "#[derive(Debug, Clone)]\npub struct ", .kind = 3 },
    .{ .trigger = "", .label = "pub enum", .detail = "public Rust algebraic enum", .insert_text = "#[derive(Debug, Clone, Copy, PartialEq, Eq)]\npub enum ", .kind = 3 },
    .{ .trigger = "", .label = "impl", .detail = "type or trait implementation block", .insert_text = "impl ", .kind = 0 },
    .{ .trigger = "", .label = "println!", .detail = "print formatted line to stdout", .insert_text = "println!(\"{}\", );", .kind = 1 },
    .{ .trigger = "", .label = "Result", .detail = "enum Result<T, E>", .insert_text = "Result<", .kind = 2 },
    .{ .trigger = "", .label = "Option", .detail = "enum Option<T>", .insert_text = "Option<", .kind = 2 },
    .{ .trigger = "", .label = "Vec", .detail = "std::vec::Vec<T> growable array", .insert_text = "Vec<", .kind = 2 },
};

const PYTHON_BUILTINS = [_]BuiltinCandidate{
    .{ .trigger = "self.", .label = "__init__", .detail = "def __init__(self) -> None", .insert_text = "__init__(self) -> None:\n        ", .kind = 1 },
    .{ .trigger = ".", .label = "append", .detail = "list.append(object) -> None", .insert_text = "append(", .kind = 1 },
    .{ .trigger = ".", .label = "items", .detail = "dict.items() -> dict_items", .insert_text = "items()", .kind = 1 },
    .{ .trigger = ".", .label = "strip", .detail = "str.strip([chars]) -> str", .insert_text = "strip()", .kind = 1 },
    .{ .trigger = "", .label = "def", .detail = "typed Python function definition", .insert_text = "def name() -> None:\n    ", .kind = 3 },
    .{ .trigger = "", .label = "async def", .detail = "async coroutine definition", .insert_text = "async def name() -> None:\n    ", .kind = 3 },
    .{ .trigger = "", .label = "class", .detail = "Python class definition", .insert_text = "class Name:\n    def __init__(self) -> None:\n        ", .kind = 3 },
    .{ .trigger = "", .label = "@dataclass", .detail = "dataclasses.dataclass decorator", .insert_text = "@dataclass\nclass ", .kind = 3 },
    .{ .trigger = "", .label = "if __name__", .detail = "module main entrypoint guard", .insert_text = "if __name__ == \"__main__\":\n    main()\n", .kind = 3 },
    .{ .trigger = "", .label = "isinstance", .detail = "isinstance(obj, class_or_tuple) -> bool", .insert_text = "isinstance(", .kind = 1 },
    .{ .trigger = "", .label = "enumerate", .detail = "enumerate(iterable, start=0)", .insert_text = "enumerate(", .kind = 1 },
};

const TS_BUILTINS = [_]BuiltinCandidate{
    .{ .trigger = "console.", .label = "log", .detail = "console.log(...data: any[]): void", .insert_text = "log(", .kind = 1 },
    .{ .trigger = "console.", .label = "error", .detail = "console.error(...data: any[]): void", .insert_text = "error(", .kind = 1 },
    .{ .trigger = ".", .label = "map", .detail = "Array<T>.map<U>(callbackfn): U[]", .insert_text = "map((item) => ", .kind = 1 },
    .{ .trigger = ".", .label = "filter", .detail = "Array<T>.filter(predicate): T[]", .insert_text = "filter((item) => ", .kind = 1 },
    .{ .trigger = "", .label = "export interface", .detail = "TypeScript exported interface", .insert_text = "export interface Name {\n    ", .kind = 3 },
    .{ .trigger = "", .label = "export type", .detail = "TypeScript exported type alias", .insert_text = "export type Name = ", .kind = 0 },
    .{ .trigger = "", .label = "export async function", .detail = "async TypeScript function", .insert_text = "export async function ", .kind = 3 },
    .{ .trigger = "", .label = "const", .detail = "lexical constant binding", .insert_text = "const ", .kind = 0 },
    .{ .trigger = "", .label = "Promise", .detail = "interface Promise<T>", .insert_text = "Promise<", .kind = 2 },
    .{ .trigger = "", .label = "Record", .detail = "type Record<K extends keyof any, T>", .insert_text = "Record<string, ", .kind = 2 },
};

const HDL_BUILTINS = [_]BuiltinCandidate{
    // VHDL (IEEE 1076)
    .{ .trigger = "", .label = "entity", .detail = "VHDL entity declaration", .insert_text = "entity name is\n    port (\n        clk : in std_logic;\n        rst : in std_logic\n    );\nend entity name;", .kind = 3 },
    .{ .trigger = "", .label = "architecture", .detail = "VHDL RTL architecture body", .insert_text = "architecture rtl of name is\nbegin\n", .kind = 3 },
    .{ .trigger = "", .label = "process", .detail = "VHDL synchronous clocked process", .insert_text = "process(clk)\nbegin\n    if rising_edge(clk) then\n        \n    end if;\nend process;", .kind = 3 },
    .{ .trigger = "", .label = "std_logic_vector", .detail = "IEEE std_logic_1164 bus vector", .insert_text = "std_logic_vector(7 downto 0)", .kind = 2 },
    .{ .trigger = "", .label = "rising_edge", .detail = "rising_edge(clk: std_logic) -> boolean", .insert_text = "rising_edge(clk)", .kind = 1 },
    // Chisel 3 / Scala Hardware Construction
    .{ .trigger = "", .label = "class extends Module", .detail = "Chisel hardware Module class", .insert_text = "class CounterModule extends Module {\n    val io = IO(new Bundle {\n        val en  = Input(Bool())\n        val out = Output(UInt(8.W))\n    })\n}", .kind = 3 },
    .{ .trigger = "", .label = "RegInit", .detail = "Chisel register with reset value", .insert_text = "RegInit(0.U(8.W))", .kind = 1 },
    .{ .trigger = "", .label = "WireDefault", .detail = "Chisel combinational wire with default", .insert_text = "WireDefault(0.U(8.W))", .kind = 1 },
    .{ .trigger = "", .label = "when", .detail = "Chisel conditional hardware block", .insert_text = "when (io.en) {\n    ", .kind = 3 },
    // DeviceTree (.dts / .dtsi)
    .{ .trigger = "", .label = "compatible", .detail = "DeviceTree driver binding property", .insert_text = "compatible = \"vendor,device\";", .kind = 4 },
    .{ .trigger = "", .label = "reg", .detail = "DeviceTree MMIO address/size tuple", .insert_text = "reg = <0x40000000 0x1000>;", .kind = 4 },
    .{ .trigger = "", .label = "status", .detail = "DeviceTree node enable status", .insert_text = "status = \"okay\";", .kind = 4 },
};

fn isIdentChar(b: u8) bool {
    return std.ascii.isAlphanumeric(b) or b == '_' or b == '#' or b == '`' or b == '$' or b == '@';
}

/// Computes up to `out.len` ranked autocomplete suggestions at `cursor_offset` in `source`.
pub fn computeCompletions(
    source: []const u8,
    cursor_offset: usize,
    lang: LspLanguage,
    out: []LspCompletionItem,
) usize {
    if (cursor_offset == 0 or cursor_offset > source.len or out.len == 0) return 0;

    // 1. Extract identifier prefix immediately preceding cursor (`word_prefix`)
    var word_start = cursor_offset;
    while (word_start > 0 and isIdentChar(source[word_start - 1])) : (word_start -= 1) {}
    const word_prefix = source[word_start..cursor_offset];
    const replace_len: u16 = @intCast(word_prefix.len);

    // 2. Check for member access trigger right before `word_start` (`std::`, `fmt.`, `System.out.`, `.`, `->`)
    const before_word = source[0..word_start];
    var member_trigger: []const u8 = "";
    if (std.mem.endsWith(u8, before_word, "System.out.")) {
        member_trigger = "System.out.";
    } else if (std.mem.endsWith(u8, before_word, "System.")) {
        member_trigger = "System.";
    } else if (std.mem.endsWith(u8, before_word, "std::")) {
        member_trigger = "std::";
    } else if (std.mem.endsWith(u8, before_word, "std.")) {
        member_trigger = "std.";
    } else if (std.mem.endsWith(u8, before_word, "self.")) {
        member_trigger = "self.";
    } else if (std.mem.endsWith(u8, before_word, "console.")) {
        member_trigger = "console.";
    } else if (std.mem.endsWith(u8, before_word, "fmt.")) {
        member_trigger = "fmt.";
    } else if (std.mem.endsWith(u8, before_word, "context.")) {
        member_trigger = "context.";
    } else if (std.mem.endsWith(u8, before_word, "http.")) {
        member_trigger = "http.";
    } else if (std.mem.endsWith(u8, before_word, ".") or std.mem.endsWith(u8, before_word, "->") or std.mem.endsWith(u8, before_word, "::")) {
        member_trigger = ".";
    }

    // Only open autocomplete popup if user typed at least 1 identifier char OR a member access trigger
    if (word_prefix.len == 0 and member_trigger.len == 0) return 0;

    var count: usize = 0;
    const table: []const BuiltinCandidate = switch (lang) {
        .cpp => &CPP_BUILTINS,
        .java => &JAVA_BUILTINS,
        .go => &GO_BUILTINS,
        .systemverilog => &SV_BUILTINS,
        .zig => &ZIG_BUILTINS,
        .rust => &RUST_BUILTINS,
        .python => &PYTHON_BUILTINS,
        .typescript => &TS_BUILTINS,
        .hdl => &HDL_BUILTINS,
    };

    // 3. If after a member trigger (`std::`, `fmt.`, `.`), prioritize member completions
    if (member_trigger.len > 0) {
        for (table) |cand| {
            if (count >= out.len) break;
            const trig_matches = std.mem.eql(u8, cand.trigger, member_trigger) or
                (std.mem.eql(u8, cand.trigger, ".") and member_trigger.len > 0);
            if (!trig_matches) continue;
            if (word_prefix.len > 0 and !startsWithIgnoreCase(cand.label, word_prefix)) continue;

            var item = LspCompletionItem{
                .kind = cand.kind,
                .replace_prefix_len = replace_len,
            };
            item.label.set(cand.label);
            item.detail.set(cand.detail);
            item.insert_text.set(cand.insert_text);
            out[count] = item;
            count += 1;
        }
        return count;
    }

    // 4. First rank: Symbols defined in the current buffer (`scanSymbols`) matching `word_prefix`
    var syms: [MaxSymbols]LspSymbol = undefined;
    const sym_count = scanSymbols(source, lang, "", &syms);
    for (syms[0..sym_count]) |sym| {
        if (count >= out.len) break;
        const sname = sym.name.slice();
        if (std.mem.eql(u8, sname, word_prefix)) continue; // Already typed in full
        if (startsWithIgnoreCase(sname, word_prefix)) {
            var item = LspCompletionItem{
                .kind = if (std.mem.eql(u8, sym.kind.slice(), "fn") or std.mem.eql(u8, sym.kind.slice(), "func") or std.mem.eql(u8, sym.kind.slice(), "method")) 1 else 2,
                .replace_prefix_len = replace_len,
            };
            item.label.set(sname);
            item.detail.set(sym.detail.slice());
            item.insert_text.set(sname);
            out[count] = item;
            count += 1;
        }
    }

    // 5. Second rank: Language standard library & keyword completions matching `word_prefix`
    for (table) |cand| {
        if (count >= out.len) break;
        if (cand.trigger.len != 0) continue;
        if (std.mem.eql(u8, cand.label, word_prefix)) continue;
        if (startsWithIgnoreCase(cand.label, word_prefix)) {
            var item = LspCompletionItem{
                .kind = cand.kind,
                .replace_prefix_len = replace_len,
            };
            item.label.set(cand.label);
            item.detail.set(cand.detail);
            item.insert_text.set(cand.insert_text);
            out[count] = item;
            count += 1;
        }
    }

    return count;
}

fn startsWithIgnoreCase(haystack: []const u8, prefix: []const u8) bool {
    if (prefix.len == 0) return true;
    if (prefix.len > haystack.len) return false;
    return std.ascii.eqlIgnoreCase(haystack[0..prefix.len], prefix);
}

// ============================================================================
// Zero-Allocation Lexical / AST Symbol Outline & Diagnostics Scanners
// ============================================================================

fn takeIdent(s: []const u8) []const u8 {
    var end: usize = 0;
    while (end < s.len and (std.ascii.isAlphanumeric(s[end]) or s[end] == '_' or s[end] == ':')) : (end += 1) {}
    return std.mem.trimEnd(u8, s[0..end], ":");
}

/// Extracts functions, methods, classes, structs, interfaces, and packages from C/C++, Java, or Go source code.
pub fn scanSymbols(source: []const u8, lang: LspLanguage, filter: []const u8, out: []LspSymbol) usize {
    var count: usize = 0;
    var line_it = std.mem.splitScalar(u8, source, '\n');
    var line_num: u32 = 1;

    while (line_it.next()) |raw_line| : (line_num += 1) {
        if (count >= out.len) break;
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0 or
            std.mem.startsWith(u8, line, "//") or
            std.mem.startsWith(u8, line, "/*") or
            std.mem.startsWith(u8, line, "*") or
            (lang == .python and std.mem.startsWith(u8, line, "#")) or
            (lang == .hdl and std.mem.startsWith(u8, line, "--")))
        {
            continue;
        }

        var sym_opt: ?LspSymbol = null;
        switch (lang) {
            .cpp => sym_opt = parseCppSymbolLine(line, line_num),
            .java => sym_opt = parseJavaSymbolLine(line, line_num),
            .go => sym_opt = parseGoSymbolLine(line, line_num),
            .systemverilog => sym_opt = parseSvSymbolLine(line, line_num),
            .zig => sym_opt = parseZigSymbolLine(line, line_num),
            .rust => sym_opt = parseRustSymbolLine(line, line_num),
            .python => sym_opt = parsePythonSymbolLine(line, line_num),
            .typescript => sym_opt = parseTsSymbolLine(line, line_num),
            .hdl => sym_opt = parseHdlSymbolLine(line, line_num),
        }

        if (sym_opt) |sym| {
            if (filter.len > 0 and !containsIgnoreCase(sym.name.slice(), filter) and !containsIgnoreCase(sym.kind.slice(), filter)) {
                continue;
            }
            out[count] = sym;
            count += 1;
        }
    }
    return count;
}

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[i .. i + needle.len], needle)) return true;
    }
    return false;
}

fn parseCppSymbolLine(line: []const u8, line_num: u32) ?LspSymbol {
    const prefixes = [_]struct { pfx: []const u8, kind: []const u8 }{
        .{ .pfx = "namespace ", .kind = "ns" },
        .{ .pfx = "class ", .kind = "class" },
        .{ .pfx = "struct ", .kind = "struct" },
        .{ .pfx = "enum class ", .kind = "enum" },
        .{ .pfx = "enum ", .kind = "enum" },
        .{ .pfx = "#define ", .kind = "macro" },
    };
    for (prefixes) |p| {
        if (std.mem.startsWith(u8, line, p.pfx)) {
            const ident = takeIdent(std.mem.trimStart(u8, line[p.pfx.len..], " \t"));
            if (ident.len > 0) {
                var sym = LspSymbol{ .line = line_num };
                sym.kind.set(p.kind);
                sym.name.set(ident);
                sym.detail.set("C/C++ type");
                return sym;
            }
        }
    }

    // Function or method definition (`ReturnType Class::method(args)` or `void foo(int x)`)
    if (std.mem.indexOfScalar(u8, line, '(')) |paren_idx| {
        if (std.mem.startsWith(u8, line, "if ") or
            std.mem.startsWith(u8, line, "if(") or
            std.mem.startsWith(u8, line, "for ") or
            std.mem.startsWith(u8, line, "for(") or
            std.mem.startsWith(u8, line, "while ") or
            std.mem.startsWith(u8, line, "while(") or
            std.mem.startsWith(u8, line, "switch ") or
            std.mem.startsWith(u8, line, "switch(") or
            std.mem.startsWith(u8, line, "return ") or
            std.mem.startsWith(u8, line, "#") or
            std.mem.indexOfScalar(u8, line[0..paren_idx], '=') != null)
        {
            return null;
        }
        const before = std.mem.trimEnd(u8, line[0..paren_idx], " \t");
        const space_idx = std.mem.lastIndexOfAny(u8, before, " \t*&") orelse return null;
        const fn_name = std.mem.trimStart(u8, before[space_idx + 1 ..], " \t*&");
        if (fn_name.len > 0 and (std.ascii.isAlphabetic(fn_name[0]) or fn_name[0] == '_' or fn_name[0] == '~')) {
            var sym = LspSymbol{ .line = line_num };
            sym.kind.set(if (std.mem.indexOfPos(u8, fn_name, 0, "::") != null) "method" else "fn");
            sym.name.set(fn_name);
            const ret_type = std.mem.trim(u8, before[0..space_idx], " \t");
            sym.detail.set(ret_type);
            return sym;
        }
    }
    return null;
}

fn parseJavaSymbolLine(line: []const u8, line_num: u32) ?LspSymbol {
    if (std.mem.startsWith(u8, line, "package ")) {
        const pkg = std.mem.trim(u8, line["package ".len..], " ;\t\r");
        if (pkg.len > 0) {
            var sym = LspSymbol{ .line = line_num };
            sym.kind.set("pkg");
            sym.name.set(pkg);
            sym.detail.set("package");
            return sym;
        }
    }

    const type_tokens = [_]struct { token: []const u8, kind: []const u8 }{
        .{ .token = "class ", .kind = "class" },
        .{ .token = "interface ", .kind = "iface" },
        .{ .token = "enum ", .kind = "enum" },
        .{ .token = "record ", .kind = "record" },
    };
    for (type_tokens) |tt| {
        if (std.mem.indexOfPos(u8, line, 0, tt.token)) |pos| {
            if (pos == 0 or line[pos - 1] == ' ') {
                const rest = std.mem.trimStart(u8, line[pos + tt.token.len ..], " \t");
                const ident = takeIdent(rest);
                if (ident.len > 0) {
                    var sym = LspSymbol{ .line = line_num };
                    sym.kind.set(tt.kind);
                    sym.name.set(ident);
                    sym.detail.set("Java type");
                    return sym;
                }
            }
        }
    }

    if (std.mem.indexOfScalar(u8, line, '(')) |paren_idx| {
        if (std.mem.startsWith(u8, line, "if ") or
            std.mem.startsWith(u8, line, "if(") or
            std.mem.startsWith(u8, line, "for ") or
            std.mem.startsWith(u8, line, "for(") or
            std.mem.startsWith(u8, line, "while ") or
            std.mem.startsWith(u8, line, "while(") or
            std.mem.startsWith(u8, line, "switch ") or
            std.mem.startsWith(u8, line, "return ") or
            std.mem.startsWith(u8, line, "new ") or
            std.mem.indexOfScalar(u8, line[0..paren_idx], '=') != null or
            std.mem.indexOfScalar(u8, line[0..paren_idx], '.') != null)
        {
            return null;
        }
        const before = std.mem.trimEnd(u8, line[0..paren_idx], " \t");
        const space_idx = std.mem.lastIndexOfScalar(u8, before, ' ') orelse return null;
        const method_name = before[space_idx + 1 ..];
        if (method_name.len > 0 and (std.ascii.isAlphabetic(method_name[0]) or method_name[0] == '_')) {
            var sym = LspSymbol{ .line = line_num };
            sym.kind.set("method");
            sym.name.set(method_name);
            sym.detail.set(std.mem.trim(u8, before[0..space_idx], " \t"));
            return sym;
        }
    }
    return null;
}

fn parseGoSymbolLine(line: []const u8, line_num: u32) ?LspSymbol {
    if (std.mem.startsWith(u8, line, "package ")) {
        const pkg = takeIdent(std.mem.trimStart(u8, line["package ".len..], " \t"));
        if (pkg.len > 0) {
            var sym = LspSymbol{ .line = line_num };
            sym.kind.set("pkg");
            sym.name.set(pkg);
            sym.detail.set("package");
            return sym;
        }
    }

    if (std.mem.startsWith(u8, line, "func ")) {
        var rest = std.mem.trimStart(u8, line["func ".len..], " \t");
        var receiver_detail: []const u8 = "func";
        if (rest.len > 0 and rest[0] == '(') {
            if (std.mem.indexOfScalar(u8, rest, ')')) |close_idx| {
                receiver_detail = rest[0 .. close_idx + 1];
                rest = std.mem.trimStart(u8, rest[close_idx + 1 ..], " \t");
            }
        }
        const ident = takeIdent(rest);
        if (ident.len > 0) {
            var sym = LspSymbol{ .line = line_num };
            sym.kind.set(if (receiver_detail.len > 4) "method" else "func");
            sym.name.set(ident);
            sym.detail.set(receiver_detail);
            return sym;
        }
    }

    if (std.mem.startsWith(u8, line, "type ")) {
        const rest = std.mem.trimStart(u8, line["type ".len..], " \t");
        const ident = takeIdent(rest);
        if (ident.len > 0) {
            var sym = LspSymbol{ .line = line_num };
            const is_iface = std.mem.indexOfPos(u8, rest, 0, "interface") != null;
            const is_struct = std.mem.indexOfPos(u8, rest, 0, "struct") != null;
            sym.kind.set(if (is_iface) "iface" else if (is_struct) "struct" else "type");
            sym.name.set(ident);
            sym.detail.set(if (is_iface) "interface" else if (is_struct) "struct" else "type alias");
            return sym;
        }
    }

    return null;
}

fn parseSvSymbolLine(line: []const u8, line_num: u32) ?LspSymbol {
    const decl_prefixes = [_]struct { pfx: []const u8, kind: []const u8, detail: []const u8 }{
        .{ .pfx = "module ", .kind = "module", .detail = "SystemVerilog module" },
        .{ .pfx = "interface ", .kind = "iface", .detail = "SV interface" },
        .{ .pfx = "package ", .kind = "pkg", .detail = "SV package" },
        .{ .pfx = "function ", .kind = "fn", .detail = "SV function" },
        .{ .pfx = "task ", .kind = "task", .detail = "SV task" },
        .{ .pfx = "parameter ", .kind = "param", .detail = "module parameter" },
        .{ .pfx = "localparam ", .kind = "param", .detail = "local constant" },
    };
    for (decl_prefixes) |dp| {
        if (std.mem.startsWith(u8, line, dp.pfx)) {
            var rest = std.mem.trimStart(u8, line[dp.pfx.len..], " \t");
            // Skip optional `automatic`, `int`, `logic [...]` before identifier in parameter/function
            if (std.mem.startsWith(u8, rest, "automatic ")) {
                rest = std.mem.trimStart(u8, rest["automatic ".len..], " \t");
            }
            if (std.mem.startsWith(u8, rest, "int ") or std.mem.startsWith(u8, rest, "logic ")) {
                const sp = std.mem.indexOfScalar(u8, rest, ' ').?;
                rest = std.mem.trimStart(u8, rest[sp + 1 ..], " \t");
                if (rest.len > 0 and rest[0] == '[') {
                    if (std.mem.indexOfScalar(u8, rest, ']')) |rb| {
                        rest = std.mem.trimStart(u8, rest[rb + 1 ..], " \t");
                    }
                }
            }
            const ident = takeIdent(rest);
            if (ident.len > 0) {
                var sym = LspSymbol{ .line = line_num };
                sym.kind.set(dp.kind);
                sym.name.set(ident);
                sym.detail.set(dp.detail);
                return sym;
            }
        }
    }

    // Extract port/signal declarations (`input logic clk`, `output logic [7:0] count`, `logic [3:0] state`)
    const sig_prefixes = [_]struct { pfx: []const u8, detail: []const u8 }{
        .{ .pfx = "input ", .detail = "input port" },
        .{ .pfx = "output ", .detail = "output port" },
        .{ .pfx = "inout ", .detail = "inout port" },
        .{ .pfx = "logic ", .detail = "logic signal" },
        .{ .pfx = "wire ", .detail = "wire net" },
        .{ .pfx = "reg ", .detail = "reg variable" },
    };
    for (sig_prefixes) |sp| {
        if (std.mem.startsWith(u8, line, sp.pfx)) {
            var rest = std.mem.trimStart(u8, line[sp.pfx.len..], " \t");
            for ([_][]const u8{ "logic ", "wire ", "reg ", "bit ", "signed ", "unsigned " }) |qual| {
                if (std.mem.startsWith(u8, rest, qual)) {
                    rest = std.mem.trimStart(u8, rest[qual.len..], " \t");
                }
            }
            if (rest.len > 0 and rest[0] == '[') {
                if (std.mem.indexOfScalar(u8, rest, ']')) |rb| {
                    rest = std.mem.trimStart(u8, rest[rb + 1 ..], " \t");
                }
            }
            const ident = takeIdent(rest);
            if (ident.len > 0) {
                var sym = LspSymbol{ .line = line_num };
                sym.kind.set("sig");
                sym.name.set(ident);
                sym.detail.set(sp.detail);
                return sym;
            }
        }
    }

    if (std.mem.startsWith(u8, line, "always_ff") or std.mem.startsWith(u8, line, "always_comb") or std.mem.startsWith(u8, line, "always_latch")) {
        const proc_name = takeIdent(line);
        var sym = LspSymbol{ .line = line_num };
        sym.kind.set("proc");
        sym.name.set(proc_name);
        sym.detail.set("RTL process block");
        return sym;
    }

    return null;
}

fn parseZigSymbolLine(line: []const u8, line_num: u32) ?LspSymbol {
    const fn_prefixes = [_][]const u8{ "pub fn ", "export fn ", "fn " };
    for (fn_prefixes) |pfx| {
        if (std.mem.startsWith(u8, line, pfx)) {
            const ident = takeIdent(std.mem.trimStart(u8, line[pfx.len..], " \t"));
            if (ident.len > 0) {
                var sym = LspSymbol{ .line = line_num };
                sym.kind.set("fn");
                sym.name.set(ident);
                sym.detail.set("Zig function");
                return sym;
            }
        }
    }
    const decl_prefixes = [_][]const u8{ "pub const ", "const ", "pub var ", "var " };
    for (decl_prefixes) |pfx| {
        if (std.mem.startsWith(u8, line, pfx)) {
            const rest = std.mem.trimStart(u8, line[pfx.len..], " \t");
            const ident = takeIdent(rest);
            if (ident.len > 0) {
                const is_struct = std.mem.indexOfPos(u8, rest, 0, "struct") != null;
                const is_enum = std.mem.indexOfPos(u8, rest, 0, "enum") != null;
                var sym = LspSymbol{ .line = line_num };
                sym.kind.set(if (is_struct) "struct" else if (is_enum) "enum" else "const");
                sym.name.set(ident);
                sym.detail.set(if (is_struct or is_enum) "Zig type" else "Zig binding");
                return sym;
            }
        }
    }
    return null;
}

fn parseRustSymbolLine(line: []const u8, line_num: u32) ?LspSymbol {
    const prefixes = [_]struct { pfx: []const u8, kind: []const u8, detail: []const u8 }{
        .{ .pfx = "pub async fn ", .kind = "fn", .detail = "async Rust fn" },
        .{ .pfx = "async fn ", .kind = "fn", .detail = "async Rust fn" },
        .{ .pfx = "pub fn ", .kind = "fn", .detail = "pub Rust fn" },
        .{ .pfx = "fn ", .kind = "fn", .detail = "Rust fn" },
        .{ .pfx = "pub struct ", .kind = "struct", .detail = "Rust struct" },
        .{ .pfx = "struct ", .kind = "struct", .detail = "Rust struct" },
        .{ .pfx = "pub enum ", .kind = "enum", .detail = "Rust enum" },
        .{ .pfx = "enum ", .kind = "enum", .detail = "Rust enum" },
        .{ .pfx = "pub trait ", .kind = "trait", .detail = "Rust trait" },
        .{ .pfx = "trait ", .kind = "trait", .detail = "Rust trait" },
        .{ .pfx = "impl ", .kind = "impl", .detail = "Rust impl block" },
        .{ .pfx = "pub mod ", .kind = "mod", .detail = "Rust module" },
        .{ .pfx = "mod ", .kind = "mod", .detail = "Rust module" },
    };
    for (prefixes) |p| {
        if (std.mem.startsWith(u8, line, p.pfx)) {
            const ident = takeIdent(std.mem.trimStart(u8, line[p.pfx.len..], " \t"));
            if (ident.len > 0) {
                var sym = LspSymbol{ .line = line_num };
                sym.kind.set(p.kind);
                sym.name.set(ident);
                sym.detail.set(p.detail);
                return sym;
            }
        }
    }
    return null;
}

fn parsePythonSymbolLine(line: []const u8, line_num: u32) ?LspSymbol {
    const prefixes = [_]struct { pfx: []const u8, kind: []const u8, detail: []const u8 }{
        .{ .pfx = "async def ", .kind = "fn", .detail = "async Python def" },
        .{ .pfx = "def ", .kind = "fn", .detail = "Python def" },
        .{ .pfx = "class ", .kind = "class", .detail = "Python class" },
    };
    for (prefixes) |p| {
        if (std.mem.startsWith(u8, line, p.pfx)) {
            const ident = takeIdent(std.mem.trimStart(u8, line[p.pfx.len..], " \t"));
            if (ident.len > 0) {
                var sym = LspSymbol{ .line = line_num };
                sym.kind.set(p.kind);
                sym.name.set(ident);
                sym.detail.set(p.detail);
                return sym;
            }
        }
    }
    return null;
}

fn parseTsSymbolLine(line: []const u8, line_num: u32) ?LspSymbol {
    const prefixes = [_]struct { pfx: []const u8, kind: []const u8, detail: []const u8 }{
        .{ .pfx = "export async function ", .kind = "fn", .detail = "async TS function" },
        .{ .pfx = "export function ", .kind = "fn", .detail = "TS function" },
        .{ .pfx = "async function ", .kind = "fn", .detail = "async TS function" },
        .{ .pfx = "function ", .kind = "fn", .detail = "TS function" },
        .{ .pfx = "export interface ", .kind = "iface", .detail = "TS interface" },
        .{ .pfx = "interface ", .kind = "iface", .detail = "TS interface" },
        .{ .pfx = "export type ", .kind = "type", .detail = "TS type alias" },
        .{ .pfx = "type ", .kind = "type", .detail = "TS type alias" },
        .{ .pfx = "export class ", .kind = "class", .detail = "TS class" },
        .{ .pfx = "class ", .kind = "class", .detail = "TS class" },
    };
    for (prefixes) |p| {
        if (std.mem.startsWith(u8, line, p.pfx)) {
            const ident = takeIdent(std.mem.trimStart(u8, line[p.pfx.len..], " \t"));
            if (ident.len > 0) {
                var sym = LspSymbol{ .line = line_num };
                sym.kind.set(p.kind);
                sym.name.set(ident);
                sym.detail.set(p.detail);
                return sym;
            }
        }
    }
    return null;
}

fn parseHdlSymbolLine(line: []const u8, line_num: u32) ?LspSymbol {
    const prefixes = [_]struct { pfx: []const u8, kind: []const u8, detail: []const u8 }{
        .{ .pfx = "entity ", .kind = "entity", .detail = "VHDL entity" },
        .{ .pfx = "architecture ", .kind = "arch", .detail = "VHDL architecture" },
        .{ .pfx = "signal ", .kind = "sig", .detail = "VHDL signal" },
        .{ .pfx = "class ", .kind = "module", .detail = "Chisel Module" },
        .{ .pfx = "object ", .kind = "obj", .detail = "Chisel object" },
        .{ .pfx = "val ", .kind = "val", .detail = "Chisel hardware val" },
    };
    for (prefixes) |p| {
        if (std.mem.startsWith(u8, line, p.pfx)) {
            const ident = takeIdent(std.mem.trimStart(u8, line[p.pfx.len..], " \t"));
            if (ident.len > 0) {
                var sym = LspSymbol{ .line = line_num };
                sym.kind.set(p.kind);
                sym.name.set(ident);
                sym.detail.set(p.detail);
                return sym;
            }
        }
    }
    // DeviceTree node line (`uart0: serial@40001000 {` or `cpus {`)
    if (std.mem.endsWith(u8, line, "{") and !std.mem.startsWith(u8, line, "/")) {
        const node_head = std.mem.trim(u8, line[0 .. line.len - 1], " \t");
        if (node_head.len > 0) {
            var sym = LspSymbol{ .line = line_num };
            sym.kind.set("node");
            sym.name.set(node_head);
            sym.detail.set("DeviceTree node");
            return sym;
        }
    }
    return null;
}

/// Scans `source` for unmatched braces, language-specific anti-patterns, and `TODO`/`FIXME` notes.
pub fn scanLocalDiagnostics(source: []const u8, lang: LspLanguage, out: []LspDiagnostic) usize {
    var count: usize = 0;
    var line_it = std.mem.splitScalar(u8, source, '\n');
    var line_num: u32 = 1;
    var brace_depth: isize = 0;
    var first_open_brace_line: u32 = 1;
    var saw_java_or_go_pkg = false;

    // SystemVerilog (`slang`) structural & synthesis lint state
    var sv_module_depth: isize = 0;
    var sv_begin_depth: isize = 0;
    var sv_first_module_line: u32 = 1;
    var sv_first_begin_line: u32 = 1;
    var sv_always_mode: u8 = 0; // 0 = none, 1 = always_ff, 2 = always_comb

    while (line_it.next()) |raw_line| : (line_num += 1) {
        if (count >= out.len) break;
        const line = std.mem.trimEnd(u8, raw_line, "\r");
        const trimmed = std.mem.trimStart(u8, line, " \t");

        if (std.mem.startsWith(u8, trimmed, "package ")) {
            saw_java_or_go_pkg = true;
        }

        if (std.mem.indexOfPos(u8, line, 0, "TODO") != null or std.mem.indexOfPos(u8, line, 0, "FIXME") != null) {
            var d = LspDiagnostic{
                .line = line_num,
                .col = 1,
                .severity = .info,
            };
            d.message.set("TODO / FIXME marker in source");
            out[count] = d;
            count += 1;
            if (count >= out.len) break;
        }

        if (lang == .cpp and std.mem.startsWith(u8, trimmed, "using namespace std;")) {
            var d = LspDiagnostic{
                .line = line_num,
                .col = 1,
                .severity = .hint,
            };
            d.message.set("clang-tidy: avoid global 'using namespace std;' in headers");
            out[count] = d;
            count += 1;
            if (count >= out.len) break;
        }

        if (lang == .java and std.mem.indexOfPos(u8, trimmed, 0, "System.err.println") != null) {
            var d = LspDiagnostic{
                .line = line_num,
                .col = 1,
                .severity = .hint,
            };
            d.message.set("jdtls: prefer structured Logger over System.err.println");
            out[count] = d;
            count += 1;
            if (count >= out.len) break;
        }

        if (lang == .rust and std.mem.indexOfPos(u8, trimmed, 0, ".unwrap()") != null) {
            var d = LspDiagnostic{
                .line = line_num,
                .col = 1,
                .severity = .hint,
            };
            d.message.set("clippy::unwrap_used: prefer '?' or 'expect(...)' over '.unwrap()'");
            out[count] = d;
            count += 1;
            if (count >= out.len) break;
        }

        if (lang == .python and (std.mem.startsWith(u8, trimmed, "except:") or std.mem.startsWith(u8, trimmed, "except :"))) {
            var d = LspDiagnostic{
                .line = line_num,
                .col = 1,
                .severity = .warn,
            };
            d.message.set("ruff [E722]: do not use bare 'except:'; specify 'except Exception:'");
            out[count] = d;
            count += 1;
            if (count >= out.len) break;
        }

        if (lang == .typescript and std.mem.indexOfPos(u8, trimmed, 0, ": any") != null) {
            var d = LspDiagnostic{
                .line = line_num,
                .col = 1,
                .severity = .hint,
            };
            d.message.set("tsserver: avoid explicit ': any'; prefer 'unknown' or a concrete interface");
            out[count] = d;
            count += 1;
            if (count >= out.len) break;
        }

        if (lang == .systemverilog and !std.mem.startsWith(u8, trimmed, "//")) {
            // Strip inline comment before checking SV tokens
            const code_part = if (std.mem.indexOfPos(u8, trimmed, 0, "//")) |c_pos|
                std.mem.trimEnd(u8, trimmed[0..c_pos], " \t")
            else
                trimmed;

            if (std.mem.startsWith(u8, code_part, "module ") or std.mem.eql(u8, code_part, "module")) {
                if (sv_module_depth == 0) sv_first_module_line = line_num;
                sv_module_depth += 1;
            } else if (std.mem.startsWith(u8, code_part, "endmodule")) {
                sv_module_depth -= 1;
                sv_always_mode = 0;
                if (sv_module_depth < 0 and count < out.len) {
                    var d = LspDiagnostic{ .line = line_num, .col = 1, .severity = .err };
                    d.message.set("slang: unmatched 'endmodule' without opening 'module'");
                    out[count] = d;
                    count += 1;
                    sv_module_depth = 0;
                }
            }

            if (std.mem.startsWith(u8, code_part, "always_ff")) {
                sv_always_mode = 1;
            } else if (std.mem.startsWith(u8, code_part, "always_comb")) {
                sv_always_mode = 2;
            } else if (std.mem.startsWith(u8, code_part, "assign ") or std.mem.startsWith(u8, code_part, "initial")) {
                sv_always_mode = 0;
            }

            if (hasSvWordToken(code_part, "begin")) {
                if (sv_begin_depth == 0) sv_first_begin_line = line_num;
                sv_begin_depth += 1;
            }
            if (hasSvWordToken(code_part, "end")) {
                sv_begin_depth -= 1;
                if (sv_begin_depth <= 0) sv_always_mode = 0;
                if (sv_begin_depth < 0 and count < out.len) {
                    var d = LspDiagnostic{ .line = line_num, .col = 1, .severity = .err };
                    d.message.set("slang: unmatched 'end' without matching 'begin'");
                    out[count] = d;
                    count += 1;
                    sv_begin_depth = 0;
                }
            }

            // slang synthesis rule: blocking '=' inside always_ff
            if (sv_always_mode == 1 and
                !std.mem.startsWith(u8, code_part, "always_ff") and
                !std.mem.startsWith(u8, code_part, "for ") and
                !std.mem.startsWith(u8, code_part, "for(") and
                hasBlockingAssignment(code_part) and
                count < out.len)
            {
                var d = LspDiagnostic{ .line = line_num, .col = 1, .severity = .warn };
                d.message.set("slang [-Wblocking-in-ff]: use non-blocking '<=' in always_ff sequential block");
                out[count] = d;
                count += 1;
            }

            // slang synthesis rule: non-blocking '<=' inside always_comb
            if (sv_always_mode == 2 and
                !std.mem.startsWith(u8, code_part, "if ") and
                !std.mem.startsWith(u8, code_part, "if(") and
                std.mem.indexOfPos(u8, code_part, 0, "<=") != null and
                count < out.len)
            {
                var d = LspDiagnostic{ .line = line_num, .col = 1, .severity = .warn };
                d.message.set("slang [-Wnonblocking-in-comb]: use blocking '=' in always_comb combinational block");
                out[count] = d;
                count += 1;
            }
        }

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
                if (brace_depth == 0) first_open_brace_line = line_num;
                brace_depth += 1;
            } else if (ch == '}') {
                brace_depth -= 1;
                if (brace_depth < 0 and count < out.len) {
                    var d = LspDiagnostic{
                        .line = line_num,
                        .col = @intCast(idx + 1),
                        .severity = .err,
                    };
                    d.message.set("Unmatched closing brace '}'");
                    out[count] = d;
                    count += 1;
                    brace_depth = 0;
                }
            }
        }
    }

    if (lang == .go and source.len > 0 and !saw_java_or_go_pkg and count < out.len) {
        var d = LspDiagnostic{
            .line = 1,
            .col = 1,
            .severity = .warn,
        };
        d.message.set("gopls: Go source file should begin with a 'package <name>' clause");
        out[count] = d;
        count += 1;
    }

    if (lang == .systemverilog) {
        if (sv_begin_depth > 0 and count < out.len) {
            var d = LspDiagnostic{ .line = sv_first_begin_line, .col = 1, .severity = .err };
            d.message.set("slang: unclosed 'begin' block (missing 'end')");
            out[count] = d;
            count += 1;
        }
        if (sv_module_depth > 0 and count < out.len) {
            var d = LspDiagnostic{ .line = sv_first_module_line, .col = 1, .severity = .err };
            d.message.set("slang: unclosed 'module' declaration (missing 'endmodule')");
            out[count] = d;
            count += 1;
        }
    }

    if (brace_depth > 0 and count < out.len) {
        var d = LspDiagnostic{
            .line = first_open_brace_line,
            .col = 1,
            .severity = .err,
        };
        d.message.set("Unclosed block brace '{' in document");
        out[count] = d;
        count += 1;
    }

    return count;
}

fn hasSvWordToken(line: []const u8, word: []const u8) bool {
    var pos: usize = 0;
    while (std.mem.indexOfPos(u8, line, pos, word)) |idx| {
        const before_ok = (idx == 0) or !(std.ascii.isAlphanumeric(line[idx - 1]) or line[idx - 1] == '_');
        const end = idx + word.len;
        const after_ok = (end >= line.len) or !(std.ascii.isAlphanumeric(line[end]) or line[end] == '_');
        if (before_ok and after_ok) return true;
        pos = idx + 1;
    }
    return false;
}

fn hasBlockingAssignment(line: []const u8) bool {
    var i: usize = 0;
    while (i < line.len) : (i += 1) {
        if (line[i] == '=') {
            const prev: u8 = if (i > 0) line[i - 1] else 0;
            const next: u8 = if (i + 1 < line.len) line[i + 1] else 0;
            if (prev != '<' and prev != '>' and prev != '=' and prev != '!' and next != '=') {
                return true;
            }
        }
    }
    return false;
}

/// Formats SystemVerilog (`slang` / IEEE 1800) source code by normalizing `module`/`endmodule`,
/// `begin`/`end`, `case`/`endcase`, `function`/`endfunction`, and parenthesis block indentation.
pub fn formatSvSource(allocator: std.mem.Allocator, source: []const u8, indent_spaces: usize) ![]const u8 {
    var out = std.ArrayList(u8).empty;
    try out.ensureTotalCapacity(allocator, source.len + 64);

    var depth: usize = 0;
    var it = std.mem.splitScalar(u8, source, '\n');
    var first = true;

    while (it.next()) |raw_line| {
        if (!first) try out.append(allocator, '\n');
        first = false;

        const trimmed = std.mem.trim(u8, raw_line, " \t\r");
        if (trimmed.len == 0) continue;

        const code_part = if (std.mem.indexOfPos(u8, trimmed, 0, "//")) |c_pos|
            std.mem.trimEnd(u8, trimmed[0..c_pos], " \t")
        else
            trimmed;

        const starts_close = std.mem.startsWith(u8, code_part, "endmodule") or
            std.mem.startsWith(u8, code_part, "endinterface") or
            std.mem.startsWith(u8, code_part, "endpackage") or
            std.mem.startsWith(u8, code_part, "endfunction") or
            std.mem.startsWith(u8, code_part, "endtask") or
            std.mem.startsWith(u8, code_part, "endcase") or
            std.mem.startsWith(u8, code_part, "endgenerate") or
            hasSvWordToken(code_part, "end") or
            code_part[0] == ')' or
            code_part[0] == '}';

        if (starts_close) {
            depth -|= 1;
        }

        const is_directive = (trimmed[0] == '`');
        if (!is_directive) {
            const total_spaces = depth * indent_spaces;
            for (0..total_spaces) |_| {
                try out.append(allocator, ' ');
            }
        }
        try out.appendSlice(allocator, trimmed);

        const opens_block = std.mem.startsWith(u8, code_part, "module ") or
            std.mem.startsWith(u8, code_part, "interface ") or
            std.mem.startsWith(u8, code_part, "package ") or
            std.mem.startsWith(u8, code_part, "function ") or
            std.mem.startsWith(u8, code_part, "task ") or
            std.mem.startsWith(u8, code_part, "case ") or
            std.mem.startsWith(u8, code_part, "case(") or
            std.mem.startsWith(u8, code_part, "unique case") or
            hasSvWordToken(code_part, "begin") or
            std.mem.endsWith(u8, code_part, "(") or
            std.mem.endsWith(u8, code_part, "{");

        if (opens_block) {
            depth += 1;
        }
    }

    return out.items;
}

/// Formats C/C++, Java, or Go source code by normalizing brace indentation and stripping trailing whitespace.
pub fn formatBraceSource(allocator: std.mem.Allocator, source: []const u8, indent_spaces: usize) ![]const u8 {
    var out = std.ArrayList(u8).empty;
    try out.ensureTotalCapacity(allocator, source.len + 64);

    var depth: usize = 0;
    var it = std.mem.splitScalar(u8, source, '\n');
    var first = true;

    while (it.next()) |raw_line| {
        if (!first) try out.append(allocator, '\n');
        first = false;

        const trimmed = std.mem.trim(u8, raw_line, " \t\r");
        if (trimmed.len == 0) continue;

        // Outdent before printing if line starts with closing brace
        if (trimmed[0] == '}' or std.mem.startsWith(u8, trimmed, "case ") or std.mem.startsWith(u8, trimmed, "default:")) {
            depth -|= 1;
        }

        // Preprocessor directives in C/C++ stay at column 0
        const is_preproc = (trimmed[0] == '#');
        if (!is_preproc) {
            const total_spaces = depth * indent_spaces;
            var s: usize = 0;
            while (s < total_spaces) : (s += 1) {
                try out.append(allocator, ' ');
            }
        }
        try out.appendSlice(allocator, trimmed);

        // Compute net brace change on this line
        var in_str = false;
        var i: usize = 0;
        var open_count: usize = 0;
        var close_count: usize = 0;
        while (i < trimmed.len) : (i += 1) {
            const ch = trimmed[i];
            if (!in_str and i + 1 < trimmed.len and ch == '/' and trimmed[i + 1] == '/') break;
            if (ch == '"' and (i == 0 or trimmed[i - 1] != '\\')) {
                in_str = !in_str;
                continue;
            }
            if (in_str) continue;
            if (ch == '{') open_count += 1;
            if (ch == '}') close_count += 1;
        }

        // Restore depth if we pre-decremented for leading `}` or `case`
        if (trimmed[0] == '}' and close_count > 0) {
            close_count -= 1;
        } else if (std.mem.startsWith(u8, trimmed, "case ") or std.mem.startsWith(u8, trimmed, "default:")) {
            depth += 1;
        }

        depth = (depth + open_count) -| close_count;
    }

    return out.items;
}

test "LspClient: Content-Length JSON-RPC framing, publishDiagnostics, completion parser, and C++/Java/Go intellisense" {
    const body = "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/publishDiagnostics\",\"params\":{\"uri\":\"file:///main.cpp\",\"diagnostics\":[{\"range\":{\"start\":{\"line\":11,\"character\":4}},\"severity\":1,\"message\":\"Undeclared identifier 'foo'\"}]}}";
    var raw_rpc_buf: [512]u8 = undefined;
    const raw_rpc = try std.fmt.bufPrint(&raw_rpc_buf, "Content-Length: {d}\r\n\r\n{s}", .{ body.len, body });

    var conn = LspConnection{ .language = .cpp };
    conn.ingestBytes(raw_rpc);
    try std.testing.expect(conn.has_lsp_diagnostics);
    try std.testing.expectEqual(@as(usize, 1), conn.diagnostic_count);
    try std.testing.expectEqual(@as(u32, 12), conn.diagnostics[0].line);
    try std.testing.expectEqual(@as(u32, 5), conn.diagnostics[0].col);
    try std.testing.expectEqual(LspSeverity.err, conn.diagnostics[0].severity);
    try std.testing.expectEqualStrings("Undeclared identifier 'foo'", conn.diagnostics[0].message.slice());

    // Test LSP `textDocument/completion` response parsing
    const comp_body = "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"isIncomplete\":false,\"items\":[{\"label\":\"push_back\",\"kind\":2,\"detail\":\"void push_back(const T&)\",\"insertText\":\"push_back(\"}]}}";
    const comp_rpc = try std.fmt.bufPrint(&raw_rpc_buf, "Content-Length: {d}\r\n\r\n{s}", .{ comp_body.len, comp_body });
    conn.ingestBytes(comp_rpc);
    try std.testing.expectEqual(@as(usize, 1), conn.completion_count);
    try std.testing.expectEqualStrings("push_back", conn.completions[0].label.slice());
    try std.testing.expectEqualStrings("push_back(", conn.completions[0].insert_text.slice());

    // C++ symbol extraction & std:: completion
    const cpp_src =
        \\#include <vector>
        \\namespace engine {
        \\class Renderer {
        \\public:
        \\    void drawFrame(int width, int height) {
        \\        std::vec
        \\    }
        \\};
        \\}
    ;
    var syms: [8]LspSymbol = undefined;
    const cpp_n = scanSymbols(cpp_src, .cpp, "", &syms);
    try std.testing.expectEqual(@as(usize, 3), cpp_n);
    try std.testing.expectEqualStrings("ns", syms[0].kind.slice());
    try std.testing.expectEqualStrings("engine", syms[0].name.slice());
    try std.testing.expectEqualStrings("class", syms[1].kind.slice());
    try std.testing.expectEqualStrings("Renderer", syms[1].name.slice());
    try std.testing.expectEqualStrings("fn", syms[2].kind.slice());
    try std.testing.expectEqualStrings("drawFrame", syms[2].name.slice());

    var comps: [MaxCompletions]LspCompletionItem = undefined;
    const std_vec_pos = std.mem.indexOfPos(u8, cpp_src, 0, "std::vec").? + 8;
    const cpp_comp_n = computeCompletions(cpp_src, std_vec_pos, .cpp, &comps);
    try std.testing.expect(cpp_comp_n >= 1);
    try std.testing.expectEqualStrings("vector", comps[0].label.slice());
    try std.testing.expectEqual(@as(u16, 3), comps[0].replace_prefix_len);

    // Java symbol extraction & System.out. completion
    const java_src =
        \\package com.editor.lsp;
        \\public class OrderService {
        \\    public static void main(String[] args) {
        \\        System.out.pr
        \\    }
        \\}
    ;
    const java_n = scanSymbols(java_src, .java, "", &syms);
    try std.testing.expectEqual(@as(usize, 3), java_n);
    const sys_pos = std.mem.indexOfPos(u8, java_src, 0, "System.out.pr").? + 13;
    const java_comp_n = computeCompletions(java_src, sys_pos, .java, &comps);
    try std.testing.expect(java_comp_n >= 1);
    try std.testing.expectEqualStrings("println", comps[0].label.slice());

    // Go symbol extraction & fmt. completion
    const go_src =
        \\package main
        \\type Server struct {
        \\    Port int
        \\}
        \\func (s *Server) Start() error {
        \\    fmt.Pr
        \\    return nil
        \\}
    ;
    const go_n = scanSymbols(go_src, .go, "", &syms);
    try std.testing.expectEqual(@as(usize, 3), go_n);
    const fmt_pos = std.mem.indexOfPos(u8, go_src, 0, "fmt.Pr").? + 6;
    const go_comp_n = computeCompletions(go_src, fmt_pos, .go, &comps);
    try std.testing.expect(go_comp_n >= 1);
    try std.testing.expectEqualStrings("Printf", comps[0].label.slice());

    // Brace formatter test
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const unformatted = "class Demo {\nvoid run() {\nint x = 1;\n}\n}";
    const formatted = try formatBraceSource(arena.allocator(), unformatted, 4);
    try std.testing.expectEqualStrings("class Demo {\n    void run() {\n        int x = 1;\n    }\n}", formatted);

    // SystemVerilog (`slang`) symbol extraction, autocomplete, and blocking-in-ff lint
    const sv_src =
        \\module axi_counter (
        \\    input logic clk,
        \\    output logic [7:0] count
        \\);
        \\    always_ff @(posedge clk) begin
        \\        count = count + 1;
        \\        alw
        \\    end
        \\endmodule
    ;
    const sv_n = scanSymbols(sv_src, .systemverilog, "", &syms);
    try std.testing.expect(sv_n >= 3);
    try std.testing.expectEqualStrings("module", syms[0].kind.slice());
    try std.testing.expectEqualStrings("axi_counter", syms[0].name.slice());

    var sv_diags: [8]LspDiagnostic = undefined;
    const sv_diag_n = scanLocalDiagnostics(sv_src, .systemverilog, &sv_diags);
    try std.testing.expectEqual(@as(usize, 1), sv_diag_n);
    try std.testing.expect(std.mem.indexOfPos(u8, sv_diags[0].message.slice(), 0, "always_ff") != null);

    const alw_pos = std.mem.indexOfPos(u8, sv_src, 0, "alw").? + 3;
    const sv_comp_n = computeCompletions(sv_src, alw_pos, .systemverilog, &comps);
    try std.testing.expect(sv_comp_n >= 2);
    try std.testing.expectEqualStrings("always_ff", comps[0].label.slice());
}

test "LspClient: Zig, Rust, Python, TypeScript, and HDL (VHDL/Chisel/DeviceTree) symbols, diagnostics, and completions" {
    var syms: [16]LspSymbol = undefined;
    var diags: [8]LspDiagnostic = undefined;
    var comps: [MaxCompletions]LspCompletionItem = undefined;

    // 1. Zig symbols, path matching, and `std.` / `@` completions
    try std.testing.expect(LspLanguage.zig.matchesPath("src/app/state.zig"));
    try std.testing.expect(LspLanguage.zig.matchesPath("build.zig.zon"));
    const zig_src =
        \\const std = @import("std");
        \\pub const PacketHeader = struct {
        \\    len: u32 = 0,
        \\};
        \\pub fn encodePacket(hdr: PacketHeader) usize {
        \\    std.me
        \\    @sp
        \\    return hdr.len;
        \\}
        \\test "packet encoding" {}
    ;
    const zig_sym_n = scanSymbols(zig_src, .zig, "", &syms);
    try std.testing.expectEqual(@as(usize, 3), zig_sym_n);
    try std.testing.expectEqualStrings("std", syms[0].name.slice());
    try std.testing.expectEqualStrings("PacketHeader", syms[1].name.slice());
    try std.testing.expectEqualStrings("encodePacket", syms[2].name.slice());

    const zig_std_pos = std.mem.indexOfPos(u8, zig_src, 0, "std.me").? + 6;
    const zig_comp1 = computeCompletions(zig_src, zig_std_pos, .zig, &comps);
    try std.testing.expect(zig_comp1 >= 1);
    try std.testing.expectEqualStrings("mem.eql", comps[0].label.slice());

    const zig_at_pos = std.mem.indexOfPos(u8, zig_src, 0, "@sp").? + 3;
    const zig_comp2 = computeCompletions(zig_src, zig_at_pos, .zig, &comps);
    try std.testing.expect(zig_comp2 >= 1);
    try std.testing.expectEqualStrings("@splat", comps[0].label.slice());

    // 2. Rust symbols, clippy::unwrap_used lint, and `std::` / `.` completions
    try std.testing.expect(LspLanguage.rust.matchesPath("crates/core/src/lib.rs"));
    const rust_src =
        \\pub struct RingBuffer {
        \\    cap: usize,
        \\}
        \\pub enum FrameKind { Data, Ack }
        \\impl RingBuffer {
        \\    pub fn push_item(&mut self) {
        \\        let v = Some(42).unwrap();
        \\        std::sync
        \\    }
        \\}
    ;
    const rust_sym_n = scanSymbols(rust_src, .rust, "", &syms);
    try std.testing.expectEqual(@as(usize, 4), rust_sym_n);
    try std.testing.expectEqualStrings("RingBuffer", syms[0].name.slice());
    try std.testing.expectEqualStrings("FrameKind", syms[1].name.slice());

    const rust_diag_n = scanLocalDiagnostics(rust_src, .rust, &diags);
    try std.testing.expectEqual(@as(usize, 1), rust_diag_n);
    try std.testing.expect(std.mem.indexOfPos(u8, diags[0].message.slice(), 0, "clippy::unwrap_used") != null);

    const rust_std_pos = std.mem.indexOfPos(u8, rust_src, 0, "std::sync").? + 9;
    const rust_comp_n = computeCompletions(rust_src, rust_std_pos, .rust, &comps);
    try std.testing.expect(rust_comp_n >= 1);
    try std.testing.expectEqualStrings("sync::Arc", comps[0].label.slice());

    // 3. Python symbols, ruff E722 bare except warning, and `self.` / `@dataclass` completions
    try std.testing.expect(LspLanguage.python.matchesPath("scripts/train.py"));
    const py_src =
        \\class PipelineRunner:
        \\    def __init__(self) -> None:
        \\        self.__in
        \\    async def execute_batch(self) -> int:
        \\        try:
        \\            return 1
        \\        except:
        \\            return 0
    ;
    const py_sym_n = scanSymbols(py_src, .python, "", &syms);
    try std.testing.expectEqual(@as(usize, 3), py_sym_n);
    try std.testing.expectEqualStrings("PipelineRunner", syms[0].name.slice());
    try std.testing.expectEqualStrings("__init__", syms[1].name.slice());
    try std.testing.expectEqualStrings("execute_batch", syms[2].name.slice());

    const py_diag_n = scanLocalDiagnostics(py_src, .python, &diags);
    try std.testing.expectEqual(@as(usize, 1), py_diag_n);
    try std.testing.expect(std.mem.indexOfPos(u8, diags[0].message.slice(), 0, "E722") != null);

    const py_self_pos = std.mem.indexOfPos(u8, py_src, 0, "self.__in").? + 9;
    const py_comp_n = computeCompletions(py_src, py_self_pos, .python, &comps);
    try std.testing.expect(py_comp_n >= 1);
    try std.testing.expectEqualStrings("__init__", comps[0].label.slice());

    // 4. TypeScript symbols, `: any` lint hint, and `console.` / `.map` completions
    try std.testing.expect(LspLanguage.typescript.matchesPath("web/app.tsx"));
    const ts_src =
        \\export interface TelemetryEvent {
        \\    payload: any;
        \\}
        \\export async function dispatchEvent(ev: TelemetryEvent) {
        \\    console.er
        \\}
    ;
    const ts_sym_n = scanSymbols(ts_src, .typescript, "", &syms);
    try std.testing.expectEqual(@as(usize, 2), ts_sym_n);
    try std.testing.expectEqualStrings("TelemetryEvent", syms[0].name.slice());
    try std.testing.expectEqualStrings("dispatchEvent", syms[1].name.slice());

    const ts_diag_n = scanLocalDiagnostics(ts_src, .typescript, &diags);
    try std.testing.expectEqual(@as(usize, 1), ts_diag_n);
    try std.testing.expect(std.mem.indexOfPos(u8, diags[0].message.slice(), 0, ": any") != null);

    const ts_con_pos = std.mem.indexOfPos(u8, ts_src, 0, "console.er").? + 10;
    const ts_comp_n = computeCompletions(ts_src, ts_con_pos, .typescript, &comps);
    try std.testing.expect(ts_comp_n >= 1);
    try std.testing.expectEqualStrings("error", comps[0].label.slice());

    // 5. HDL (VHDL / Chisel / DeviceTree) symbols and completions
    try std.testing.expect(LspLanguage.hdl.matchesPath("rtl/uart_rx.vhd"));
    try std.testing.expect(LspLanguage.hdl.matchesPath("chisel/Tile.scala"));
    try std.testing.expect(LspLanguage.hdl.matchesPath("board/soc.dts"));
    const hdl_src =
        \\entity uart_rx is
        \\end entity uart_rx;
        \\architecture rtl of uart_rx is
        \\    signal rx_vec : std_logic_v
        \\begin
        \\end architecture rtl;
        \\class CrossbarSwitch extends Module {
        \\    val r = RegIn
        \\}
        \\uart0: serial@10000000 {
        \\    compat
        \\};
    ;
    const hdl_sym_n = scanSymbols(hdl_src, .hdl, "", &syms);
    try std.testing.expect(hdl_sym_n >= 4);
    try std.testing.expectEqualStrings("uart_rx", syms[0].name.slice());
    try std.testing.expectEqualStrings("rtl", syms[1].name.slice());

    const hdl_reg_pos = std.mem.indexOfPos(u8, hdl_src, 0, "RegIn").? + 5;
    const hdl_comp_n = computeCompletions(hdl_src, hdl_reg_pos, .hdl, &comps);
    try std.testing.expect(hdl_comp_n >= 1);
    try std.testing.expectEqualStrings("RegInit", comps[0].label.slice());

    // 6. SystemVerilog formatter & non-blocking in always_comb lint
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const unformatted_sv = "module top;\nalways_comb begin\ny <= a & b;\nend\nendmodule";
    const formatted_sv = try formatSvSource(arena.allocator(), unformatted_sv, 4);
    try std.testing.expectEqualStrings("module top;\n    always_comb begin\n        y <= a & b;\n    end\nendmodule", formatted_sv);

    const comb_diag_n = scanLocalDiagnostics(unformatted_sv, .systemverilog, &diags);
    try std.testing.expectEqual(@as(usize, 1), comb_diag_n);
    try std.testing.expect(std.mem.indexOfPos(u8, diags[0].message.slice(), 0, "always_comb") != null);
}

test "LspClient Fuzzer: 1-byte chunked JSON-RPC streaming, escaped quotes, and malformed header recovery" {
    var conn = LspConnection{ .language = .rust };

    // Feed garbage prefix + oversized Content-Length + valid publishDiagnostics 1 byte at a time
    const msg1 = "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/publishDiagnostics\",\"params\":{\"uri\":\"file:///lib.rs\",\"diagnostics\":[{\"range\":{\"start\":{\"line\":4,\"character\":2}},\"severity\":2,\"message\":\"unused variable \\\"count\\\"\"}]}}";
    var stream_buf: [1024]u8 = undefined;
    const stream = try std.fmt.bufPrint(
        &stream_buf,
        "GARBAGE_BYTES\r\nContent-Length: 99999999\r\n\r\nContent-Length: {d}\r\n\r\n{s}",
        .{ msg1.len, msg1 },
    );

    for (stream) |b| {
        const one: [1]u8 = .{b};
        conn.ingestBytes(&one);
    }

    try std.testing.expect(conn.has_lsp_diagnostics);
    try std.testing.expectEqual(@as(usize, 1), conn.diagnostic_count);
    try std.testing.expectEqual(@as(u32, 5), conn.diagnostics[0].line);
    try std.testing.expectEqual(LspSeverity.warn, conn.diagnostics[0].severity);
}
