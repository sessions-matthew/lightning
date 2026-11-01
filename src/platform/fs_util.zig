//! Cross-platform (macOS POSIX + Windows Win32/MSVCRT) filesystem, directory iteration,
//! file metadata (`stat`), and atomic file copy utilities (`src/platform/fs_util.zig`).
//!
//! Retains native macOS BSD `dirent`/`opendir`/`readdir`/`stat` C-ABI declarations,
//! `SF_DATALESS` iCloud Drive handling, and `_NSGetExecutablePath` on macOS builds,
//! while providing Win32/MSVCRT equivalents when cross-compiling for Windows.

const std = @import("std");
const builtin = @import("builtin");

pub const is_macos = (builtin.os.tag == .macos);
pub const is_windows = (builtin.os.tag == .windows);
pub const is_linux = (builtin.os.tag == .linux);

pub const SharedLibExt = if (is_windows) ".dll" else if (is_linux) ".so" else ".dylib";
pub const DefaultAppLibPath: [:0]const u8 = if (is_windows)
    "zig-out/bin/editor_app.dll"
else if (is_linux)
    "zig-out/lib/libeditor_app.so"
else
    "zig-out/lib/libeditor_app.dylib";

pub const dirent = extern struct {
    d_ino: u64 = 0,
    d_seekoff: u64 = 0,
    d_reclen: u16 = 0,
    d_namlen: u16 = 0,
    d_type: u8 = 0,
    d_name: [1024]u8 = @splat(0),
};

const LinuxDirent = extern struct {
    d_ino: u64 = 0,
    d_off: i64 = 0,
    d_reclen: u16 = 0,
    d_type: u8 = 0,
    d_name: [256]u8 = @splat(0),
};
var g_linux_entry: dirent = .{};

pub const DT_DIR: u8 = 4;
pub const DT_REG: u8 = 8;
pub const DT_LNK: u8 = 10;

const posix_c = struct {
    pub const PosixDIR = opaque {};
    extern "c" fn opendir(name: [*:0]const u8) ?*PosixDIR;
    extern "c" fn readdir(dirp: *PosixDIR) ?*dirent;
    extern "c" fn readdir64(dirp: *PosixDIR) ?*LinuxDirent;
    extern "c" fn closedir(dirp: *PosixDIR) c_int;
    extern "c" fn mkdir(path: [*:0]const u8, mode: u16) c_int;
    extern "c" fn unlink(path: [*:0]const u8) c_int;
    extern "c" fn rmdir(path: [*:0]const u8) c_int;
    extern "c" fn chdir(path: [*:0]const u8) c_int;
    extern "c" fn realpath(file_name: [*:0]const u8, resolved_name: ?[*]u8) ?[*:0]u8;
    extern "c" fn rename(old: [*:0]const u8, new: [*:0]const u8) c_int;
    extern "c" fn getcwd(buf: [*]u8, size: usize) ?[*]u8;
    extern "c" fn getenv(name: [*:0]const u8) ?[*:0]const u8;
    extern "c" fn _NSGetExecutablePath(buf: [*]u8, bufsize: *u32) c_int;
    extern "c" fn readlink(path: [*:0]const u8, buf: [*]u8, bufsiz: usize) isize;
    extern "c" fn fileno(stream: *std.c.FILE) c_int;
    extern "c" fn fsync(fd: c_int) c_int;
    extern "c" fn fork() c_int;
    extern "c" fn popen(command: [*:0]const u8, mode: [*:0]const u8) ?*std.c.FILE;
    extern "c" fn pclose(stream: *std.c.FILE) c_int;
};

const win32_c = struct {
    pub const INVALID_HANDLE_VALUE: ?*anyopaque = @ptrFromInt(std.math.maxInt(usize));
    pub const FILE_ATTRIBUTE_DIRECTORY: u32 = 0x10;
    pub const FILE_ATTRIBUTE_REPARSE_POINT: u32 = 0x400;
    pub const MOVEFILE_REPLACE_EXISTING: u32 = 0x1;

    pub const FILETIME = extern struct {
        dwLowDateTime: u32 = 0,
        dwHighDateTime: u32 = 0,
    };

    pub const WIN32_FIND_DATAA = extern struct {
        dwFileAttributes: u32 = 0,
        ftCreationTime: FILETIME = .{},
        ftLastAccessTime: FILETIME = .{},
        ftLastWriteTime: FILETIME = .{},
        nFileSizeHigh: u32 = 0,
        nFileSizeLow: u32 = 0,
        dwReserved0: u32 = 0,
        dwReserved1: u32 = 0,
        cFileName: [260]u8 = @splat(0),
        cAlternateFileName: [14]u8 = @splat(0),
    };

    pub const WIN32_FILE_ATTRIBUTE_DATA = extern struct {
        dwFileAttributes: u32 = 0,
        ftCreationTime: FILETIME = .{},
        ftLastAccessTime: FILETIME = .{},
        ftLastWriteTime: FILETIME = .{},
        nFileSizeHigh: u32 = 0,
        nFileSizeLow: u32 = 0,
    };

    pub const WinDirState = struct {
        handle: ?*anyopaque = null,
        first_pending: bool = true,
        find_data: WIN32_FIND_DATAA = .{},
        entry: dirent = .{},
    };

    extern "kernel32" fn FindFirstFileA(lpFileName: [*:0]const u8, lpFindFileData: *WIN32_FIND_DATAA) callconv(.winapi) ?*anyopaque;
    extern "kernel32" fn FindNextFileA(hFindFile: *anyopaque, lpFindFileData: *WIN32_FIND_DATAA) callconv(.winapi) c_int;
    extern "kernel32" fn FindClose(hFindFile: *anyopaque) callconv(.winapi) c_int;
    extern "kernel32" fn GetFileAttributesExA(lpFileName: [*:0]const u8, fInfoLevelId: c_int, lpFileInformation: *WIN32_FILE_ATTRIBUTE_DATA) callconv(.winapi) c_int;
    extern "kernel32" fn GetModuleFileNameA(hModule: ?*anyopaque, lpFilename: [*]u8, nSize: u32) callconv(.winapi) u32;
    extern "kernel32" fn MoveFileExA(lpExistingFileName: [*:0]const u8, lpNewFileName: [*:0]const u8, dwFlags: u32) callconv(.winapi) c_int;

    pub const HANDLE_FLAG_INHERIT: u32 = 0x00000001;
    pub const STARTF_USESTDHANDLES: u32 = 0x00000100;
    pub const CREATE_NO_WINDOW: u32 = 0x08000000;

    pub const SECURITY_ATTRIBUTES = extern struct {
        nLength: u32 = @sizeOf(SECURITY_ATTRIBUTES),
        lpSecurityDescriptor: ?*anyopaque = null,
        bInheritHandle: c_int = 1,
    };

    pub const STARTUPINFOA = extern struct {
        cb: u32 = @sizeOf(STARTUPINFOA),
        lpReserved: ?[*:0]u8 = null,
        lpDesktop: ?[*:0]u8 = null,
        lpTitle: ?[*:0]u8 = null,
        dwX: u32 = 0,
        dwY: u32 = 0,
        dwXSize: u32 = 0,
        dwYSize: u32 = 0,
        dwXCountChars: u32 = 0,
        dwYCountChars: u32 = 0,
        dwFillAttribute: u32 = 0,
        dwFlags: u32 = 0,
        wShowWindow: u16 = 0,
        cbReserved2: u16 = 0,
        lpReserved2: ?*u8 = null,
        hStdInput: ?*anyopaque = null,
        hStdOutput: ?*anyopaque = null,
        hStdError: ?*anyopaque = null,
    };

    pub const PROCESS_INFORMATION = extern struct {
        hProcess: ?*anyopaque = null,
        hThread: ?*anyopaque = null,
        dwProcessId: u32 = 0,
        dwThreadId: u32 = 0,
    };

    extern "kernel32" fn CreatePipe(hReadPipe: *?*anyopaque, hWritePipe: *?*anyopaque, lpPipeAttributes: *const SECURITY_ATTRIBUTES, nSize: u32) callconv(.winapi) c_int;
    extern "kernel32" fn SetHandleInformation(hObject: *anyopaque, dwMask: u32, dwFlags: u32) callconv(.winapi) c_int;
    extern "kernel32" fn CreateProcessA(
        lpApplicationName: ?[*:0]const u8,
        lpCommandLine: [*:0]u8,
        lpProcessAttributes: ?*anyopaque,
        lpThreadAttributes: ?*anyopaque,
        bInheritHandles: c_int,
        dwCreationFlags: u32,
        lpEnvironment: ?*anyopaque,
        lpCurrentDirectory: ?[*:0]const u8,
        lpStartupInfo: *const STARTUPINFOA,
        lpProcessInformation: *PROCESS_INFORMATION,
    ) callconv(.winapi) c_int;
    extern "kernel32" fn WaitForSingleObject(hHandle: *anyopaque, dwMilliseconds: u32) callconv(.winapi) u32;
    extern "kernel32" fn GetExitCodeProcess(hProcess: *anyopaque, lpExitCode: *u32) callconv(.winapi) c_int;
    extern "kernel32" fn CloseHandle(hObject: *anyopaque) callconv(.winapi) c_int;

    extern "c" fn _mkdir(path: [*:0]const u8) c_int;
    extern "c" fn _unlink(path: [*:0]const u8) c_int;
    extern "c" fn _rmdir(path: [*:0]const u8) c_int;
    extern "c" fn _chdir(path: [*:0]const u8) c_int;
    extern "c" fn _fullpath(absPath: ?[*]u8, relPath: [*:0]const u8, maxLength: usize) ?[*:0]u8;
    extern "c" fn _getcwd(buf: [*]u8, size: c_int) ?[*]u8;
    extern "c" fn _fileno(stream: *std.c.FILE) c_int;
    extern "c" fn _commit(fd: c_int) c_int;
    extern "c" fn _open_osfhandle(osfhandle: isize, flags: c_int) c_int;
    extern "c" fn _fdopen(fd: c_int, mode: [*:0]const u8) ?*std.c.FILE;
    extern "c" fn _close(fd: c_int) c_int;
    extern "c" fn _popen(command: [*:0]const u8, mode: [*:0]const u8) ?*std.c.FILE;
    extern "c" fn _pclose(stream: *std.c.FILE) c_int;
    extern "c" fn getenv(name: [*:0]const u8) ?[*:0]const u8;

    pub const WinPopenEntry = struct {
        fp: ?*std.c.FILE = null,
        proc: ?*anyopaque = null,
    };
    pub var popen_table: [16]WinPopenEntry = @splat(.{});

    fn filetimeToUnixNs(ft: FILETIME) i128 {
        const ticks: u64 = (@as(u64, ft.dwHighDateTime) << 32) | @as(u64, ft.dwLowDateTime);
        const epoch_diff: u64 = 116444736000000000;
        if (ticks <= epoch_diff) return 0;
        return @as(i128, @intCast(ticks - epoch_diff)) * 100;
    }
};

pub const DIR = opaque {};

pub fn opendir(name: [*:0]const u8) ?*DIR {
    if (comptime is_windows) {
        const name_slice = std.mem.sliceTo(name, 0);
        if (name_slice.len == 0 or name_slice.len >= 490) return null;
        var pat_buf: [512:0]u8 = @splat(0);
        @memcpy(pat_buf[0..name_slice.len], name_slice);
        var plen = name_slice.len;
        if (pat_buf[plen - 1] != '/' and pat_buf[plen - 1] != '\\') {
            pat_buf[plen] = '\\';
            plen += 1;
        }
        pat_buf[plen] = '*';
        pat_buf[plen + 1] = 0;

        const st = std.heap.c_allocator.create(win32_c.WinDirState) catch return null;
        st.* = .{};
        const h = win32_c.FindFirstFileA(&pat_buf, &st.find_data);
        if (h == null or h == win32_c.INVALID_HANDLE_VALUE) {
            std.heap.c_allocator.destroy(st);
            return null;
        }
        st.handle = h;
        st.first_pending = true;
        return @ptrCast(st);
    } else {
        return @ptrCast(posix_c.opendir(name));
    }
}

pub fn readdir(dirp: *DIR) ?*dirent {
    if (comptime is_windows) {
        const st: *win32_c.WinDirState = @ptrCast(@alignCast(dirp));
        const h = st.handle orelse return null;
        if (st.first_pending) {
            st.first_pending = false;
        } else {
            if (win32_c.FindNextFileA(h, &st.find_data) == 0) return null;
        }
        st.entry = .{};
        const cname = std.mem.sliceTo(st.find_data.cFileName[0..], 0);
        const nlen = @min(cname.len, st.entry.d_name.len - 1);
        @memcpy(st.entry.d_name[0..nlen], cname[0..nlen]);
        st.entry.d_name[nlen] = 0;
        st.entry.d_namlen = @intCast(nlen);
        if ((st.find_data.dwFileAttributes & win32_c.FILE_ATTRIBUTE_REPARSE_POINT) != 0) {
            st.entry.d_type = DT_LNK;
        } else if ((st.find_data.dwFileAttributes & win32_c.FILE_ATTRIBUTE_DIRECTORY) != 0) {
            st.entry.d_type = DT_DIR;
        } else {
            st.entry.d_type = DT_REG;
        }
        return &st.entry;
    } else if (comptime is_linux) {
        const raw = posix_c.readdir64(@ptrCast(dirp)) orelse return null;
        g_linux_entry = .{
            .d_ino = raw.d_ino,
            .d_reclen = raw.d_reclen,
            .d_type = raw.d_type,
        };
        const cname = std.mem.sliceTo(raw.d_name[0..], 0);
        const nlen = @min(cname.len, g_linux_entry.d_name.len - 1);
        @memcpy(g_linux_entry.d_name[0..nlen], cname[0..nlen]);
        g_linux_entry.d_name[nlen] = 0;
        g_linux_entry.d_namlen = @intCast(nlen);
        return &g_linux_entry;
    } else {
        return posix_c.readdir(@ptrCast(dirp));
    }
}

pub fn direntName(ent: *const dirent) []const u8 {
    return ent.d_name[0..ent.d_namlen];
}

pub fn closedir(dirp: *DIR) c_int {
    if (comptime is_windows) {
        const st: *win32_c.WinDirState = @ptrCast(@alignCast(dirp));
        if (st.handle) |h| {
            _ = win32_c.FindClose(h);
        }
        std.heap.c_allocator.destroy(st);
        return 0;
    } else {
        return posix_c.closedir(@ptrCast(dirp));
    }
}

pub fn mkdir(path: [*:0]const u8, mode: u16) c_int {
    if (comptime is_windows) {
        return win32_c._mkdir(path);
    } else {
        return posix_c.mkdir(path, mode);
    }
}

pub fn unlink(path: [*:0]const u8) c_int {
    if (comptime is_windows) {
        return win32_c._unlink(path);
    } else {
        return posix_c.unlink(path);
    }
}

pub fn rmdir(path: [*:0]const u8) c_int {
    if (comptime is_windows) {
        return win32_c._rmdir(path);
    } else {
        return posix_c.rmdir(path);
    }
}

pub fn chdir(path: [*:0]const u8) c_int {
    if (comptime is_windows) {
        return win32_c._chdir(path);
    } else {
        return posix_c.chdir(path);
    }
}

pub fn realpath(file_name: [*:0]const u8, resolved_name: ?[*]u8) ?[*:0]u8 {
    if (comptime is_windows) {
        var attr: win32_c.WIN32_FILE_ATTRIBUTE_DATA = .{};
        if (win32_c.GetFileAttributesExA(file_name, 0, &attr) == 0) return null;
        const res = win32_c._fullpath(resolved_name, file_name, 1024) orelse return null;
        // Normalize backslashes to forward slashes for internal editor path consistency
        var i: usize = 0;
        while (res[i] != 0 and i < 1024) : (i += 1) {
            if (res[i] == '\\') res[i] = '/';
        }
        while (i > 3 and res[i - 1] == '/') {
            i -= 1;
            res[i] = 0;
        }
        return res;
    } else {
        return posix_c.realpath(file_name, resolved_name);
    }
}

pub fn rename(old: [*:0]const u8, new: [*:0]const u8) c_int {
    if (comptime is_windows) {
        return if (win32_c.MoveFileExA(old, new, win32_c.MOVEFILE_REPLACE_EXISTING) != 0) 0 else -1;
    } else {
        return posix_c.rename(old, new);
    }
}

pub fn getcwd(buf: [*]u8, size: usize) ?[*:0]u8 {
    if (comptime is_windows) {
        const ptr = win32_c._getcwd(buf, @intCast(@min(size, 32767))) orelse return null;
        var i: usize = 0;
        while (ptr[i] != 0 and i < size) : (i += 1) {
            if (ptr[i] == '\\') ptr[i] = '/';
        }
        return @ptrCast(ptr);
    } else {
        const ptr = posix_c.getcwd(buf, size) orelse return null;
        return @ptrCast(ptr);
    }
}

pub fn getenv(name: [*:0]const u8) ?[*:0]const u8 {
    if (comptime is_windows) {
        if (win32_c.getenv(name)) |v| return v;
        if (std.mem.eql(u8, std.mem.sliceTo(name, 0), "HOME")) {
            return win32_c.getenv("USERPROFILE");
        }
        return null;
    } else {
        return posix_c.getenv(name);
    }
}

pub fn _NSGetExecutablePath(buf: [*]u8, bufsize: *u32) c_int {
    if (comptime is_macos) {
        return posix_c._NSGetExecutablePath(buf, bufsize);
    } else if (comptime is_windows) {
        const len = win32_c.GetModuleFileNameA(null, buf, bufsize.*);
        if (len == 0 or len >= bufsize.*) return -1;
        var i: usize = 0;
        while (i < len) : (i += 1) {
            if (buf[i] == '\\') buf[i] = '/';
        }
        buf[len] = 0;
        bufsize.* = len;
        return 0;
    } else if (comptime is_linux) {
        if (bufsize.* <= 1) return -1;
        const n = posix_c.readlink("/proc/self/exe", buf, bufsize.* - 1);
        if (n <= 0) return -1;
        const ulen: usize = @intCast(n);
        buf[ulen] = 0;
        bufsize.* = @intCast(ulen);
        return 0;
    } else {
        return -1;
    }
}

pub fn fileno(stream: *std.c.FILE) c_int {
    if (comptime is_windows) {
        return win32_c._fileno(stream);
    } else {
        return posix_c.fileno(stream);
    }
}

pub fn fsync(fd: c_int) c_int {
    if (comptime is_windows) {
        return win32_c._commit(fd);
    } else {
        return posix_c.fsync(fd);
    }
}

pub fn popen(command: [*:0]const u8, mode: [*:0]const u8) ?*std.c.FILE {
    if (comptime is_windows) {
        const cmd_slice = std.mem.sliceTo(command, 0);
        const mode_slice = std.mem.sliceTo(mode, 0);
        const is_write = (mode_slice.len > 0 and mode_slice[0] == 'w');

        var sa = win32_c.SECURITY_ATTRIBUTES{};
        var rd_h: ?*anyopaque = null;
        var wr_h: ?*anyopaque = null;
        if (win32_c.CreatePipe(&rd_h, &wr_h, &sa, 0) == 0) return null;

        if (is_write) {
            _ = win32_c.SetHandleInformation(wr_h.?, win32_c.HANDLE_FLAG_INHERIT, 0);
        } else {
            _ = win32_c.SetHandleInformation(rd_h.?, win32_c.HANDLE_FLAG_INHERIT, 0);
        }

        var cmd_line: [1024:0]u8 = @splat(0);
        const full = std.fmt.bufPrint(&cmd_line, "cmd.exe /C {s}", .{cmd_slice}) catch {
            _ = win32_c.CloseHandle(rd_h.?);
            _ = win32_c.CloseHandle(wr_h.?);
            return null;
        };
        cmd_line[full.len] = 0;

        var si = win32_c.STARTUPINFOA{
            .dwFlags = win32_c.STARTF_USESTDHANDLES,
            .hStdInput = if (is_write) rd_h else null,
            .hStdOutput = if (is_write) null else wr_h,
            .hStdError = null,
        };
        var pi = win32_c.PROCESS_INFORMATION{};
        const ok = win32_c.CreateProcessA(
            null,
            &cmd_line,
            null,
            null,
            1,
            win32_c.CREATE_NO_WINDOW,
            null,
            null,
            &si,
            &pi,
        );
        if (is_write) {
            _ = win32_c.CloseHandle(rd_h.?);
        } else {
            _ = win32_c.CloseHandle(wr_h.?);
        }
        if (ok == 0) {
            _ = win32_c.CloseHandle(if (is_write) wr_h.? else rd_h.?);
            return null;
        }
        if (pi.hThread) |th| _ = win32_c.CloseHandle(th);

        const parent_h = if (is_write) wr_h.? else rd_h.?;
        const fd = win32_c._open_osfhandle(@intCast(@intFromPtr(parent_h)), 0);
        if (fd < 0) {
            _ = win32_c.CloseHandle(parent_h);
            if (pi.hProcess) |ph| _ = win32_c.CloseHandle(ph);
            return null;
        }
        const fp = win32_c._fdopen(fd, if (is_write) "wb" else "rb") orelse {
            _ = win32_c._close(fd);
            if (pi.hProcess) |ph| _ = win32_c.CloseHandle(ph);
            return null;
        };
        var stored = false;
        for (&win32_c.popen_table) |*slot| {
            if (slot.fp == null) {
                slot.fp = fp;
                slot.proc = pi.hProcess;
                stored = true;
                break;
            }
        }
        if (!stored) {
            if (pi.hProcess) |ph| _ = win32_c.CloseHandle(ph);
        }
        return fp;
    } else {
        return posix_c.popen(command, mode);
    }
}

pub fn pclose(stream: *std.c.FILE) c_int {
    if (comptime is_windows) {
        var proc_h: ?*anyopaque = null;
        for (&win32_c.popen_table) |*slot| {
            if (slot.fp == stream) {
                proc_h = slot.proc;
                slot.fp = null;
                slot.proc = null;
                break;
            }
        }
        _ = std.c.fclose(stream);
        if (proc_h) |ph| {
            _ = win32_c.WaitForSingleObject(ph, 5000);
            var exit_code: u32 = 0;
            _ = win32_c.GetExitCodeProcess(ph, &exit_code);
            _ = win32_c.CloseHandle(ph);
            return @intCast(exit_code);
        }
        return 0;
    } else {
        return posix_c.pclose(stream);
    }
}

var win_temp_dir_buf: [256]u8 = @splat(0);

pub fn tempDirPath() []const u8 {
    if (comptime is_windows) {
        const raw = if (win32_c.getenv("TEMP")) |t|
            std.mem.sliceTo(t, 0)
        else if (win32_c.getenv("TMP")) |t|
            std.mem.sliceTo(t, 0)
        else
            return ".";
        const n = @min(raw.len, win_temp_dir_buf.len);
        for (raw[0..n], 0..) |ch, i| {
            win_temp_dir_buf[i] = if (ch == '\\') '/' else ch;
        }
        var clean = win_temp_dir_buf[0..n];
        while (clean.len > 1 and clean[clean.len - 1] == '/') {
            clean = clean[0 .. clean.len - 1];
        }
        return clean;
    } else {
        return "/tmp";
    }
}

/// macOS BSD file flag (`<sys/stat.h>`) indicating an APFS / FileProvider dataless inode
/// whose payload is stored in iCloud Drive and not yet materialized on local storage.
pub const SF_DATALESS: u32 = 0x40000000;

var g_inflight_downloads: [8]u64 = @splat(0);
var g_inflight_slot: usize = 0;

/// Returns `true` if `path_z` has the macOS FileProvider / iCloud Drive `SF_DATALESS`
/// (`0x40000000`) flag set on its inode, meaning synchronous `open`/`read` calls on the
/// UI thread would block inside the kernel waiting for network download.
pub fn isDatalessFileOnDisk(path_z: [*:0]const u8) bool {
    if (comptime !is_macos) return false;
    var st: std.c.Stat = undefined;
    if (std.c.stat(path_z, &st) == 0) {
        return (st.flags & SF_DATALESS) != 0;
    }
    return false;
}

/// Slice wrapper around `isDatalessFileOnDisk`.
pub fn isDatalessSliceOnDisk(path: []const u8) bool {
    if (path.len == 0 or path.len >= 511) return false;
    var path_z: [512:0]u8 = @splat(0);
    @memcpy(path_z[0..path.len], path);
    path_z[path.len] = 0;
    return isDatalessFileOnDisk(&path_z);
}

/// Triggers an asynchronous, non-blocking background materialization of a macOS `SF_DATALESS`
/// iCloud file using a double-forked helper process (reaped immediately so zero zombie
/// processes are left behind). Deduplicates requests per path+ctime.
pub fn triggerAsyncICloudDownload(path_z: [*:0]const u8) void {
    if (comptime !is_macos) return;
    var st: std.c.Stat = undefined;
    if (std.c.stat(path_z, &st) != 0) return;
    if ((st.flags & SF_DATALESS) == 0) return;

    const path_slice = std.mem.sliceTo(path_z, 0);
    var h = std.hash.Wyhash.init(0xD47A_1E55_1C10_0D01);
    h.update(path_slice);
    const ino: u64 = @intCast(st.ino);
    h.update(std.mem.asBytes(&ino));
    const key = h.final() | 1;

    for (g_inflight_downloads) |existing| {
        if (existing == key) return;
    }
    g_inflight_downloads[g_inflight_slot % g_inflight_downloads.len] = key;
    g_inflight_slot +%= 1;

    const pid1 = posix_c.fork();
    if (pid1 < 0) return;
    if (pid1 == 0) {
        const pid2 = posix_c.fork();
        if (pid2 == 0) {
            if (std.c.fopen(path_z, "rb")) |fp| {
                var byte_buf: [1]u8 = undefined;
                _ = std.c.fread(&byte_buf, 1, 1, fp);
                _ = std.c.fclose(fp);
            }
        }
        std.c._exit(0);
    }
    _ = std.c.waitpid(pid1, null, 0);
}

/// Slice wrapper around `triggerAsyncICloudDownload`.
pub fn triggerAsyncICloudDownloadSlice(path: []const u8) void {
    if (path.len == 0 or path.len >= 511) return;
    var path_z: [512:0]u8 = @splat(0);
    @memcpy(path_z[0..path.len], path);
    path_z[path.len] = 0;
    triggerAsyncICloudDownload(&path_z);
}

/// Returns `true` if `path_z` exists on disk (file or directory).
pub fn pathExistsOnDisk(path_z: [*:0]const u8) bool {
    if (comptime is_windows) {
        var attr: win32_c.WIN32_FILE_ATTRIBUTE_DATA = .{};
        return win32_c.GetFileAttributesExA(path_z, 0, &attr) != 0;
    } else if (comptime is_linux) {
        var stx: std.os.linux.Statx = undefined;
        return std.os.linux.statx(std.os.linux.AT.FDCWD, path_z, 0, @bitCast(@as(u32, 0x07ff)), &stx) == 0;
    } else {
        var st: std.c.Stat = undefined;
        return std.c.stat(path_z, &st) == 0;
    }
}

/// Computes a fast 64-bit metadata hash combining mtime, ctime, byte size, inode, and macOS flags.
pub fn statMtimeHash(path_z: [*:0]const u8) u64 {
    if (comptime is_windows) {
        var attr: win32_c.WIN32_FILE_ATTRIBUTE_DATA = .{};
        if (win32_c.GetFileAttributesExA(path_z, 0, &attr) != 0) {
            const m_ns: u64 = @intCast(@max(@as(i128, 0), win32_c.filetimeToUnixNs(attr.ftLastWriteTime)));
            const c_ns: u64 = @intCast(@max(@as(i128, 0), win32_c.filetimeToUnixNs(attr.ftCreationTime)));
            const sz: u64 = (@as(u64, attr.nFileSizeHigh) << 32) | @as(u64, attr.nFileSizeLow);
            const flags: u64 = attr.dwFileAttributes;
            return (m_ns ^ (c_ns << 13) ^ (sz *% 0x9E37_79B9) ^ (flags *% 0xC2B2_AE3D_27D4_EB4F)) | 1;
        }
        return 0;
    } else if (comptime is_linux) {
        var stx: std.os.linux.Statx = undefined;
        if (std.os.linux.statx(std.os.linux.AT.FDCWD, path_z, 0, @bitCast(@as(u32, 0x07ff)), &stx) == 0) {
            const sec: u64 = @bitCast(stx.mtime.sec);
            const nsec: u64 = stx.mtime.nsec;
            const csec: u64 = @bitCast(stx.ctime.sec);
            const cnsec: u64 = stx.ctime.nsec;
            const sz: u64 = stx.size;
            const nlink: u64 = stx.nlink;
            const ino: u64 = stx.ino;
            return (sec ^ (nsec << 16) ^ (csec << 8) ^ (cnsec << 24) ^ (sz *% 0x9E37_79B9) ^ (nlink *% 0x517C_C1B7) ^ (ino *% 0x94D0_49BB_1331_11EB)) | 1;
        }
        return 0;
    } else {
        var st: std.c.Stat = undefined;
        if (std.c.stat(path_z, &st) == 0) {
            const mt = st.mtime();
            const ct = st.ctime();
            const sec: u64 = @bitCast(@as(i64, @intCast(mt.sec)));
            const nsec: u64 = @bitCast(@as(i64, @intCast(mt.nsec)));
            const csec: u64 = @bitCast(@as(i64, @intCast(ct.sec)));
            const cnsec: u64 = @bitCast(@as(i64, @intCast(ct.nsec)));
            const sz: u64 = @bitCast(@as(i64, @intCast(st.size)));
            const nlink: u64 = @intCast(st.nlink);
            const ino: u64 = @intCast(st.ino);
            const flags: u64 = if (is_macos) @intCast(st.flags) else 0;
            return (sec ^ (nsec << 16) ^ (csec << 8) ^ (cnsec << 24) ^ (sz *% 0x9E37_79B9) ^ (nlink *% 0x517C_C1B7) ^ (ino *% 0x94D0_49BB_1331_11EB) ^ (flags *% 0xC2B2_AE3D_27D4_EB4F)) | 1;
        }
        return 0;
    }
}

/// Returns the modification timestamp of `path_z` in nanoseconds since the Unix epoch,
/// or `null` if `stat` fails.
pub fn fileMtimeNs(path_z: [*:0]const u8) ?i128 {
    if (comptime is_windows) {
        var attr: win32_c.WIN32_FILE_ATTRIBUTE_DATA = .{};
        if (win32_c.GetFileAttributesExA(path_z, 0, &attr) == 0) return null;
        return win32_c.filetimeToUnixNs(attr.ftLastWriteTime);
    } else if (comptime is_linux) {
        var stx: std.os.linux.Statx = undefined;
        if (std.os.linux.statx(std.os.linux.AT.FDCWD, path_z, 0, @bitCast(@as(u32, 0x07ff)), &stx) != 0) return null;
        return @as(i128, stx.mtime.sec) * 1_000_000_000 + @as(i128, stx.mtime.nsec);
    } else {
        var st: std.c.Stat = undefined;
        if (std.c.stat(path_z, &st) != 0) return null;
        const mt = st.mtime();
        const sec: i128 = @intCast(mt.sec);
        const nsec: i128 = @intCast(mt.nsec);
        return sec * 1_000_000_000 + nsec;
    }
}

/// Returns the modification timestamp of `path_z` in seconds as a `f64`,
/// or `null` if `stat` fails.
pub fn fileMtimeSec(path_z: [*:0]const u8) ?f64 {
    if (comptime is_windows or is_linux) {
        const ns = fileMtimeNs(path_z) orelse return null;
        return @as(f64, @floatFromInt(ns)) * 1e-9;
    } else {
        var st: std.c.Stat = undefined;
        if (std.c.stat(path_z, &st) != 0) return null;
        const mt = st.mtime();
        const sec: f64 = @floatFromInt(mt.sec);
        const nsec: f64 = @floatFromInt(mt.nsec);
        return sec + nsec * 1e-9;
    }
}

/// Returns `true` if `path_z` exists on disk and is a directory (`S_IFDIR`).
pub fn isDirectoryOnDisk(path_z: [*:0]const u8) bool {
    if (comptime is_windows) {
        var attr: win32_c.WIN32_FILE_ATTRIBUTE_DATA = .{};
        if (win32_c.GetFileAttributesExA(path_z, 0, &attr) != 0) {
            return (attr.dwFileAttributes & win32_c.FILE_ATTRIBUTE_DIRECTORY) != 0;
        }
        return false;
    } else if (comptime is_linux) {
        var stx: std.os.linux.Statx = undefined;
        if (std.os.linux.statx(std.os.linux.AT.FDCWD, path_z, 0, @bitCast(@as(u32, 0x07ff)), &stx) == 0) {
            return (stx.mode & 0o170000) == 0o040000;
        }
        return false;
    } else {
        var st: std.c.Stat = undefined;
        if (std.c.stat(path_z, &st) == 0) {
            return (st.mode & 0o170000) == 0o040000;
        }
        return false;
    }
}

/// Returns the byte size of `path_z` if it exists on disk and is a regular file (`S_IFREG`),
/// or `null` otherwise.
pub fn regularFileSizeOnDisk(path_z: [*:0]const u8) ?usize {
    if (comptime is_windows) {
        var attr: win32_c.WIN32_FILE_ATTRIBUTE_DATA = .{};
        if (win32_c.GetFileAttributesExA(path_z, 0, &attr) != 0) {
            if ((attr.dwFileAttributes & win32_c.FILE_ATTRIBUTE_DIRECTORY) != 0) return null;
            const sz: u64 = (@as(u64, attr.nFileSizeHigh) << 32) | @as(u64, attr.nFileSizeLow);
            return @intCast(sz);
        }
        return null;
    } else if (comptime is_linux) {
        var stx: std.os.linux.Statx = undefined;
        if (std.os.linux.statx(std.os.linux.AT.FDCWD, path_z, 0, @bitCast(@as(u32, 0x07ff)), &stx) == 0) {
            if ((stx.mode & 0o170000) != 0o100000) return null;
            return @intCast(stx.size);
        }
        return null;
    } else {
        var st: std.c.Stat = undefined;
        if (std.c.stat(path_z, &st) == 0) {
            if ((st.mode & 0o170000) != 0o100000) return null;
            if (st.size < 0) return 0;
            return @intCast(st.size);
        }
        return null;
    }
}

/// Copies the contents of `src_z` to `dst_z` (unlinking any existing file at `dst_z` first
/// so mapped dynamic libraries are not mutated in place).
pub fn copyFileAtomic(src_z: [*:0]const u8, dst_z: [*:0]const u8) bool {
    const src_f = std.c.fopen(src_z, "rb") orelse return false;
    defer _ = std.c.fclose(src_f);

    _ = unlink(dst_z);
    const dst_f = std.c.fopen(dst_z, "wb") orelse return false;
    defer _ = std.c.fclose(dst_f);

    var buf: [16384]u8 = undefined;
    while (true) {
        const n = std.c.fread(&buf, 1, buf.len, src_f);
        if (n == 0) break;
        if (std.c.fwrite(&buf, 1, n, dst_f) != n) return false;
    }
    return true;
}

test "fs_util: isDirectoryOnDisk, regularFileSizeOnDisk, fileMtimeNs, and copyFileAtomic" {
    try std.testing.expect(isDirectoryOnDisk("/tmp"));
    try std.testing.expect(!isDirectoryOnDisk("/tmp/__nonexistent_dir_fs_util_test__"));

    const src_path: [*:0]const u8 = "/tmp/skia_fs_util_test_src.tmp";
    const dst_path: [*:0]const u8 = "/tmp/skia_fs_util_test_dst.tmp";
    _ = unlink(src_path);
    _ = unlink(dst_path);
    defer {
        _ = unlink(src_path);
        _ = unlink(dst_path);
    }

    const payload = "platform fs_util atomic copy verification payload\n";
    {
        const fp = std.c.fopen(src_path, "wb") orelse return error.OpenFailed;
        defer _ = std.c.fclose(fp);
        try std.testing.expectEqual(payload.len, std.c.fwrite(payload.ptr, 1, payload.len, fp));
    }

    try std.testing.expect(!isDirectoryOnDisk(src_path));
    try std.testing.expect(!isDatalessFileOnDisk(src_path));
    try std.testing.expect(!isDatalessSliceOnDisk("/tmp/skia_fs_util_test_src.tmp"));
    try std.testing.expectEqual(@as(?usize, payload.len), regularFileSizeOnDisk(src_path));
    try std.testing.expect(fileMtimeNs(src_path) != null);
    try std.testing.expect(fileMtimeNs(src_path).? > 0);
    try std.testing.expect(fileMtimeSec(src_path) != null);
    try std.testing.expect(fileMtimeSec(src_path).? > 0);

    try std.testing.expect(copyFileAtomic(src_path, dst_path));
    try std.testing.expectEqual(@as(?usize, payload.len), regularFileSizeOnDisk(dst_path));

    const dst_fp = std.c.fopen(dst_path, "rb") orelse return error.OpenFailed;
    defer _ = std.c.fclose(dst_fp);
    var read_buf: [128]u8 = undefined;
    const n = std.c.fread(&read_buf, 1, read_buf.len, dst_fp);
    try std.testing.expectEqualStrings(payload, read_buf[0..n]);
}
