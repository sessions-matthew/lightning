//! Standalone filesystem, POSIX directory traversal, iCloud placeholder, and workspace discovery
//! helpers extracted from `src/app/state.zig`.

const std = @import("std");
const ui = @import("ui");
const platform = @import("platform");

pub const getcwd = platform.fs_util.getcwd;
pub const getenv = platform.fs_util.getenv;
pub const posix_dir = platform.fs_util;
pub const isDatalessFileOnDisk = platform.fs_util.isDatalessFileOnDisk;
pub const triggerAsyncICloudDownload = platform.fs_util.triggerAsyncICloudDownload;

pub fn isSystemOrHomeDirectory(path: []const u8) bool {
    if (path.len == 0) return true;
    if (std.mem.eql(u8, path, "/")) return true;

    const system_dirs = [_][]const u8{
        "/System",
        "/Library",
        "/Applications",
        "/Volumes",
        "/private",
        "/var",
        "/tmp",
        "/dev",
        "/etc",
        "/bin",
        "/sbin",
        "/usr",
        "/Users",
        "/home",
    };
    for (system_dirs) |sys| {
        if (std.mem.eql(u8, path, sys)) return true;
    }

    if (getenv("HOME")) |home_z| {
        const home = std.mem.sliceTo(home_z, 0);
        if (std.mem.eql(u8, path, home)) return true;
    }

    if (std.mem.startsWith(u8, path, "/Users/")) {
        const rest = path[7..];
        if (rest.len > 0 and std.mem.indexOfScalar(u8, rest, '/') == null) return true;
    }
    if (std.mem.startsWith(u8, path, "/home/")) {
        const rest = path[6..];
        if (rest.len > 0 and std.mem.indexOfScalar(u8, rest, '/') == null) return true;
    }

    if (std.mem.indexOf(u8, path, ".app") != null) return true;

    return false;
}

pub fn detectLanguageForPath(rel_path: []const u8) ui.CodeLanguage {
    if (std.mem.endsWith(u8, rel_path, ".S") or
        std.mem.endsWith(u8, rel_path, ".s") or
        std.mem.endsWith(u8, rel_path, ".lds") or
        std.mem.endsWith(u8, rel_path, ".ld"))
    {
        return .cpp;
    }
    return ui.CodeLanguage.fromPath(rel_path);
}

pub fn isBinaryContent(probe: []const u8) bool {
    if (probe.len >= 4) {
        const magic = std.mem.readInt(u32, probe[0..4], .little);
        if (magic == 0xFEEDFACF or magic == 0xFEEDFACE or magic == 0xCAFEBABE or magic == 0x464C457F) {
            return true;
        }
    }
    for (probe) |b| {
        if (b == 0) return true;
    }
    return false;
}

pub fn isBinaryFileOnDisk(rel_path: []const u8) bool {
    var path_buf: [256]u8 = undefined;
    if (rel_path.len >= path_buf.len) return false;
    @memcpy(path_buf[0..rel_path.len], rel_path);
    path_buf[rel_path.len] = 0;
    const path_z: [*:0]const u8 = @ptrCast(path_buf[0..rel_path.len]);
    const fsize = regularFileSizeOnDisk(path_z) orelse return true;
    if (fsize > 1024 * 1024) return true;
    if (fsize == 0) return false;
    // Never synchronously open/read an iCloud `SF_DATALESS` file during directory scanning
    if (isDatalessFileOnDisk(path_z)) return false;
    if (std.c.fopen(path_z, "rb")) |fp| {
        defer _ = std.c.fclose(fp);
        var probe: [256]u8 = undefined;
        const n = std.c.fread(&probe, 1, probe.len, fp);
        return isBinaryContent(probe[0..n]);
    }
    return false;
}

pub fn isBinaryExtension(rel_path: []const u8) bool {
    const binary_exts = [_][]const u8{
        ".dylib",    ".a",        ".o",      ".bin",  ".so",    ".dll",   ".exe",   ".out",
        ".icns",     ".ttf",      ".otf",    ".woff", ".woff2",
        ".zip",      ".tar",      ".gz",     ".tgz",  ".bz2",   ".xz",    ".zst",   ".7z",    ".rar",
        ".asif",     ".dmg",      ".iso",    ".img",  ".qcow2", ".vmdk",  ".elf",
        ".axf",      ".pyc",      ".class",  ".wasm", ".rlib",  ".rmeta", ".db",    ".sqlite", ".keystore",
        ".docx",     ".pptx",     ".xlsx",   ".pages", ".key",  ".numbers",
        ".mp3",      ".wav",      ".flac",   ".ogg",  ".m4a",   ".mp4",   ".mov",   ".mkv",   ".avi",   ".webm",
    };
    for (binary_exts) |ext| {
        if (std.ascii.endsWithIgnoreCase(rel_path, ext)) return true;
    }
    return false;
}

pub fn shouldIgnoreScannedPath(rel_path: []const u8) bool {
    if (rel_path.len == 0 or rel_path.len >= 254) return true;
    if (std.mem.startsWith(u8, rel_path, "vendor/") or
        std.mem.startsWith(u8, rel_path, ".git/") or
        std.mem.startsWith(u8, rel_path, ".zig-cache/") or
        std.mem.startsWith(u8, rel_path, "zig-out/") or
        std.mem.startsWith(u8, rel_path, "build/"))
    {
        return true;
    }
    const base = std.fs.path.basename(rel_path);
    if (std.mem.eql(u8, base, ".DS_Store") or
        std.mem.endsWith(u8, base, ".icloud") or
        std.mem.endsWith(u8, base, ".editor_tmp"))
    {
        return true;
    }
    return false;
}

pub fn isSupportedWorkspaceFile(rel_path: []const u8) bool {
    return !shouldIgnoreScannedPath(rel_path);
}

pub fn unwrapICloudPlaceholder(name: []const u8) ?[]const u8 {
    if (name.len > 8 and name[0] == '.' and std.mem.endsWith(u8, name, ".icloud")) {
        const unwrapped = name[1 .. name.len - 7];
        if (unwrapped.len > 0 and unwrapped[0] != '.') {
            return unwrapped;
        }
    }
    return null;
}

pub fn getICloudPlaceholderPath(path: []const u8, buf: *[512:0]u8) ?[*:0]const u8 {
    if (path.len == 0 or path.len >= 490) return null;
    const dir = std.fs.path.dirname(path);
    const base = std.fs.path.basename(path);
    if (base.len == 0) return null;
    if (base.len > 8 and base[0] == '.' and std.mem.endsWith(u8, base, ".icloud")) return null;

    const formatted = if (dir) |d|
        std.fmt.bufPrint(buf[0..510], "{s}/.{s}.icloud", .{ d, base }) catch return null
    else
        std.fmt.bufPrint(buf[0..510], ".{s}.icloud", .{base}) catch return null;

    buf[formatted.len] = 0;
    return @ptrCast(buf[0..formatted.len :0]);
}

pub fn writeSliceToDiskAtomic(dest_path_z: [*:0]const u8, slice: []const u8) bool {
    const dest_slice = std.mem.sliceTo(dest_path_z, 0);
    if (dest_slice.len == 0) return false;

    // Write to sibling temporary file in the same directory so rename() is guaranteed
    // to be an atomic metadata swap within the same APFS / filesystem volume.
    var tmp_buf: [512:0]u8 = @splat(0);
    const dir = std.fs.path.dirname(dest_slice);
    const base = std.fs.path.basename(dest_slice);

    const tmp_slice = if (dir) |d|
        std.fmt.bufPrint(tmp_buf[0..510], "{s}/.{s}.editor_tmp", .{ d, base }) catch null
    else
        std.fmt.bufPrint(tmp_buf[0..510], ".{s}.editor_tmp", .{base}) catch null;

    if (tmp_slice) |tmp_str| {
        tmp_buf[tmp_str.len] = 0;
        const tmp_z: [*:0]const u8 = @ptrCast(tmp_buf[0..tmp_str.len :0]);
        if (std.c.fopen(tmp_z, "wb")) |fp| {
            var write_ok = true;
            if (slice.len > 0) {
                const written = std.c.fwrite(slice.ptr, 1, slice.len, fp);
                if (written != slice.len) write_ok = false;
            }
            if (write_ok) {
                const fd = posix_dir.fileno(fp);
                if (fd >= 0) {
                    _ = posix_dir.fsync(fd);
                }
            }
            _ = std.c.fclose(fp);

            if (write_ok) {
                if (posix_dir.rename(tmp_z, dest_path_z) == 0) {
                    return true;
                }
            }
            _ = posix_dir.unlink(tmp_z);
        }
    }

    // Direct write fallback
    const fp = std.c.fopen(dest_path_z, "wb") orelse return false;
    defer _ = std.c.fclose(fp);
    if (slice.len > 0) {
        const written = std.c.fwrite(slice.ptr, 1, slice.len, fp);
        if (written != slice.len) return false;
    }
    const fd = posix_dir.fileno(fp);
    if (fd >= 0) {
        _ = posix_dir.fsync(fd);
    }
    return true;
}

pub fn regularFileSizeOnDisk(path_z: [*:0]const u8) ?usize {
    if (platform.fs_util.regularFileSizeOnDisk(path_z)) |sz| return sz;
    // If direct stat failed, check if macOS iCloud placeholder (.<filename>.icloud) exists
    var ph_buf: [512:0]u8 = @splat(0);
    const path_slice = std.mem.sliceTo(path_z, 0);
    if (getICloudPlaceholderPath(path_slice, &ph_buf)) |ph_z| {
        return platform.fs_util.regularFileSizeOnDisk(ph_z);
    }
    return null;
}

pub fn fileMtimeSec(sub_path: [*:0]const u8) i64 {
    if (platform.fs_util.fileMtimeSec(sub_path)) |sec_f| {
        return @intFromFloat(sec_f);
    }
    return 0;
}

pub fn statMtimeHash(sub_path: [*:0]const u8) u64 {
    return platform.fs_util.statMtimeHash(sub_path);
}

pub fn findProjectRootForFile(abs_file_path: []const u8) ?[]const u8 {
    var cur_dir = std.fs.path.dirname(abs_file_path) orelse return null;
    const markers = [_][]const u8{
        ".git",
        "build.zig",
        ".vscode",
        "Cargo.toml",
        "package.json",
        "pyproject.toml",
        "CMakeLists.txt",
        "examples",
        "Testing",
    };
    var depth: usize = 0;
    while (depth < 5 and cur_dir.len > 1) : (depth += 1) {
        if (std.mem.endsWith(u8, cur_dir, "/Projects") or
            std.mem.endsWith(u8, cur_dir, "/Documents") or
            std.mem.endsWith(u8, cur_dir, "/Desktop") or
            std.mem.eql(u8, cur_dir, "/Users") or
            std.mem.eql(u8, cur_dir, "/Volumes"))
        {
            break;
        }
        for (markers) |m| {
            var probe_z: [512:0]u8 = @splat(0);
            const probe = std.fmt.bufPrint(probe_z[0..510], "{s}/{s}", .{ cur_dir, m }) catch continue;
            probe_z[probe.len] = 0;
            if (platform.fs_util.pathExistsOnDisk(&probe_z)) {
                return cur_dir;
            }
        }
        cur_dir = std.fs.path.dirname(cur_dir) orelse break;
    }
    return std.fs.path.dirname(abs_file_path);
}

pub fn fileExistsOnDisk(rel_path: []const u8) bool {
    var path_buf: [256]u8 = undefined;
    if (rel_path.len >= path_buf.len) return false;
    @memcpy(path_buf[0..rel_path.len], rel_path);
    path_buf[rel_path.len] = 0;
    const path_z: [*:0]const u8 = @ptrCast(path_buf[0..rel_path.len]);
    return regularFileSizeOnDisk(path_z) != null;
}

pub fn shouldIgnoreDirectoryName(name: []const u8) bool {
    if (std.mem.eql(u8, name, ".vscode")) return false;
    if (name.len == 0 or name[0] == '.') return true;
    const ignored_dirs = [_][]const u8{
        "vendor",      "zig-out",     "node_modules", "target",   "__pycache__",
        "build",       "IAR",         "RVDS",         "Keil",     "CCS",
        "MPLAB",       "Renesas",     "Rowley",       "Softune",  "Tasking",
        "WizC",        "CodeWarrior", "oWatcom",      "SDCC",     "Paradigm",
        "BCC",         "MSP430X",
    };
    for (ignored_dirs) |ig| {
        if (std.mem.eql(u8, name, ig)) return true;
    }
    return false;
}

pub const shouldIgnoreDirName = shouldIgnoreDirectoryName;

pub const isDirectoryOnDisk = platform.fs_util.isDirectoryOnDisk;

pub fn asciiLessThanIgnoreCaseSlice(a: []const u8, b: []const u8) bool {
    const min_len = @min(a.len, b.len);
    for (0..min_len) |i| {
        const ca = std.ascii.toLower(a[i]);
        const cb = std.ascii.toLower(b[i]);
        if (ca != cb) return ca < cb;
    }
    if (a.len != b.len) return a.len < b.len;
    return std.mem.order(u8, a, b) == .lt;
}

pub fn isVcdCandidatePath(path: []const u8) bool {
    return std.mem.endsWith(u8, path, ".vcd") or std.mem.endsWith(u8, path, ".VCD");
}

pub fn isWaveformCandidatePath(path: []const u8) bool {
    return isVcdCandidatePath(path) or
        std.mem.endsWith(u8, path, ".sv") or
        std.mem.endsWith(u8, path, ".svh") or
        std.mem.endsWith(u8, path, ".v") or
        std.mem.endsWith(u8, path, ".vh") or
        std.mem.endsWith(u8, path, ".vhd") or
        std.mem.endsWith(u8, path, ".vhdl");
}

pub fn isPdfCandidatePath(path: []const u8) bool {
    return std.mem.endsWith(u8, path, ".pdf") or std.mem.endsWith(u8, path, ".PDF");
}

pub fn isImageCandidatePath(path: []const u8) bool {
    return ui.isImagePath(path);
}

pub fn isAudioCandidatePath(path: []const u8) bool {
    return ui.isAudioPath(path);
}

pub fn isVideoCandidatePath(path: []const u8) bool {
    return ui.isVideoPath(path);
}

pub fn isMediaCandidatePath(path: []const u8) bool {
    return isAudioCandidatePath(path) or isVideoCandidatePath(path);
}

pub fn folderPathHash(folder_path: []const u8) u64 {
    const h = std.hash.Wyhash.hash(0xF01D_E29A_C357_1101, folder_path);
    return if (h == 0) 1 else h;
}

pub fn mkdirRecursive(rel_path: []const u8) bool {
    if (rel_path.len == 0 or rel_path.len >= 254 or rel_path[0] == '/' or std.mem.indexOfPos(u8, rel_path, 0, "..") != null) {
        return false;
    }
    var buf: [256:0]u8 = @splat(0);
    var i: usize = 0;
    while (i <= rel_path.len) : (i += 1) {
        if (i == rel_path.len or rel_path[i] == '/') {
            if (i > 0) {
                @memcpy(buf[0..i], rel_path[0..i]);
                buf[i] = 0;
                _ = posix_dir.mkdir(&buf, 0o755);
            }
        }
    }
    @memcpy(buf[0..rel_path.len], rel_path);
    buf[rel_path.len] = 0;
    return isDirectoryOnDisk(&buf);
}

pub fn removeDirectoryRecursive(rel_dir: []const u8, depth: usize) bool {
    if (depth > 12 or rel_dir.len == 0 or rel_dir.len >= 254) return false;
    if (std.mem.eql(u8, rel_dir, ".") or std.mem.eql(u8, rel_dir, "..") or rel_dir[0] == '/' or std.mem.indexOfPos(u8, rel_dir, 0, "..") != null) {
        return false;
    }

    var dir_z: [256:0]u8 = @splat(0);
    @memcpy(dir_z[0..rel_dir.len], rel_dir);
    dir_z[rel_dir.len] = 0;

    {
        const dirp = posix_dir.opendir(&dir_z) orelse return false;
        defer _ = posix_dir.closedir(dirp);

        while (posix_dir.readdir(dirp)) |ent| {
            const namlen: usize = @min(@as(usize, ent.d_namlen), ent.d_name.len);
            const name = ent.d_name[0..namlen];
            if (name.len == 0 or std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;

            var child_buf: [256:0]u8 = @splat(0);
            const child_slice = std.fmt.bufPrint(child_buf[0..254], "{s}/{s}", .{ rel_dir, name }) catch continue;
            child_buf[child_slice.len] = 0;

            const is_dir = if (ent.d_type == posix_dir.DT_DIR)
                true
            else if (ent.d_type == 0)
                isDirectoryOnDisk(&child_buf)
            else
                false;

            if (is_dir) {
                _ = removeDirectoryRecursive(child_slice, depth + 1);
            } else {
                _ = posix_dir.unlink(&child_buf);
            }
        }
    }

    return posix_dir.rmdir(&dir_z) == 0;
}

test "workspace_fs: directory filtering, binary content checks, mtime, and candidate path helpers" {
    try std.testing.expect(isSystemOrHomeDirectory("/"));
    try std.testing.expect(isSystemOrHomeDirectory("/Users"));
    try std.testing.expect(isSystemOrHomeDirectory("/Users/someone"));
    try std.testing.expect(!isSystemOrHomeDirectory("/Users/someone/Projects/editor"));

    try std.testing.expect(shouldIgnoreDirName(".git"));
    try std.testing.expect(shouldIgnoreDirName("zig-out"));
    try std.testing.expect(shouldIgnoreDirName("node_modules"));
    try std.testing.expect(!shouldIgnoreDirName(".vscode"));
    try std.testing.expect(!shouldIgnoreDirName("src"));

    try std.testing.expect(isSupportedWorkspaceFile("src/app/state.zig"));
    try std.testing.expect(isSupportedWorkspaceFile("archive/tb_popcnt.do"));
    try std.testing.expect(isSupportedWorkspaceFile("scripts/synth.tcl"));
    try std.testing.expect(isSupportedWorkspaceFile("docs/report.docx"));
    try std.testing.expect(isSupportedWorkspaceFile("slides/lecture.pptx"));
    try std.testing.expect(isSupportedWorkspaceFile("hw3/submission.zip"));
    try std.testing.expect(isSupportedWorkspaceFile("fw/image.bin"));
    try std.testing.expect(isSupportedWorkspaceFile("fw/boot.elf"));
    try std.testing.expect(isSupportedWorkspaceFile("data/results.sqlite"));
    try std.testing.expect(!isSupportedWorkspaceFile("zig-out/lib/libeditor_app.dylib"));
    try std.testing.expect(!isSupportedWorkspaceFile(".git/HEAD"));
    try std.testing.expect(!isSupportedWorkspaceFile(".DS_Store"));

    try std.testing.expect(isBinaryContent(&.{ 0xCF, 0xFA, 0xED, 0xFE, 0x01 }));
    try std.testing.expect(isBinaryContent("hello\x00world"));
    try std.testing.expect(!isBinaryContent("const x: usize = 42;\n"));

    try std.testing.expect(isPdfCandidatePath("docs/spec.pdf"));
    try std.testing.expect(isPdfCandidatePath("docs/SPEC.PDF"));
    try std.testing.expect(!isPdfCandidatePath("docs/spec.md"));

    try std.testing.expect(isImageCandidatePath("plots/waveform.png"));
    try std.testing.expect(isImageCandidatePath("assets/logo.SVG"));
    try std.testing.expect(isImageCandidatePath("out/frame.ppm"));
    try std.testing.expect(isSupportedWorkspaceFile("plots/waveform.png"));
    try std.testing.expect(!isImageCandidatePath("src/main.zig"));

    try std.testing.expect(isAudioCandidatePath("audio/podcast.mp3"));
    try std.testing.expect(isAudioCandidatePath("sounds/effect.wav"));
    try std.testing.expect(isAudioCandidatePath("music/track.flac"));
    try std.testing.expect(!isAudioCandidatePath("src/main.zig"));

    try std.testing.expect(isVideoCandidatePath("videos/demo.mp4"));
    try std.testing.expect(isVideoCandidatePath("media/clip.mov"));
    try std.testing.expect(isVideoCandidatePath("streams/output.webm"));
    try std.testing.expect(!isVideoCandidatePath("src/main.zig"));
    try std.testing.expect(isMediaCandidatePath("videos/demo.mp4"));
    try std.testing.expect(isMediaCandidatePath("audio/podcast.mp3"));

    try std.testing.expect(isWaveformCandidatePath("sim/trace.vcd"));
    try std.testing.expect(isWaveformCandidatePath("rtl/top.sv"));
    try std.testing.expect(!isWaveformCandidatePath("src/main.zig"));

    try std.testing.expect(isDirectoryOnDisk("src"));
    try std.testing.expect(!isDirectoryOnDisk("build.zig"));
    try std.testing.expect(fileMtimeSec("build.zig") > 0);
}
