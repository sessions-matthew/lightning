//! Workbench Task Execution Context & Build System (`tasks.zig`).
//!
//! Provides VS Code-compatible task execution:
//!   - Resolves build commands from `.vscode/tasks.json` (build group, matching `preLaunchTask`, args).
//!   - Resolves debug pre-launch build tasks from `.vscode/launch.json` (`preLaunchTask`, `buildCommand`).
//!   - Falls back to project build system auto-detection (`build.zig`, `Cargo.toml`, `package.json`, etc.).
//!   - Runs tasks in their own dedicated non-blocking subprocess execution context (`TaskRunner`),
//!     streaming stdout and stderr directly into the Workbench Output Console tab in real-time.

const std = @import("std");
const builtin = @import("builtin");
const ui = @import("ui");
const platform = @import("platform");
const state_mod = @import("state.zig");
const EditorState = state_mod.EditorState;

const is_windows = (builtin.os.tag == .windows);

const posix_c = struct {
    extern "c" fn pipe(fds: *[2]c_int) c_int;
    extern "c" fn fork() c_int;
    extern "c" fn dup2(oldfd: c_int, newfd: c_int) c_int;
    extern "c" fn chdir(path: [*:0]const u8) c_int;
    extern "c" fn execv(path: [*:0]const u8, argv: [*:null]const ?[*:0]const u8) c_int;
    extern "c" fn close(fd: c_int) c_int;
    extern "c" fn read(fd: c_int, buf: [*]u8, count: usize) isize;
    extern "c" fn fcntl(fd: c_int, cmd: c_int, ...) c_int;
    extern "c" fn waitpid(pid: c_int, status: ?*c_int, options: c_int) c_int;
    extern "c" fn kill(pid: c_int, sig: c_int) c_int;
    extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
    extern "c" fn _exit(status: c_int) noreturn;
};

const F_GETFL: c_int = 3;
const F_SETFL: c_int = 4;
const O_NONBLOCK: c_int = if (builtin.os.tag == .linux) 0x0800 else 0x0004;
const WNOHANG: c_int = 1;
const EAGAIN: c_int = if (builtin.os.tag == .linux) 11 else 35;
const EINTR: c_int = 4;
const SIGTERM: c_int = 15;
const SIGKILL: c_int = 9;

pub const TaskInfo = struct {
    command: []const u8,
    source: []const u8,
};

pub const TaskEntry = struct {
    name: [64]u8 = undefined,
    name_len: usize = 0,
    command: [256]u8 = undefined,
    command_len: usize = 0,
    source: [64]u8 = undefined,
    source_len: usize = 0,
    group: [32]u8 = undefined,
    group_len: usize = 0,

    pub fn nameSlice(self: *const TaskEntry) []const u8 {
        return self.name[0..self.name_len];
    }
    pub fn commandSlice(self: *const TaskEntry) []const u8 {
        return self.command[0..self.command_len];
    }
    pub fn sourceSlice(self: *const TaskEntry) []const u8 {
        return self.source[0..self.source_len];
    }
    pub fn groupSlice(self: *const TaskEntry) []const u8 {
        return self.group[0..self.group_len];
    }

    pub fn set(self: *TaskEntry, name_str: []const u8, cmd_str: []const u8, src_str: []const u8, grp_str: []const u8) void {
        const nl = @min(name_str.len, self.name.len);
        @memcpy(self.name[0..nl], name_str[0..nl]);
        self.name_len = nl;

        const cl = @min(cmd_str.len, self.command.len);
        @memcpy(self.command[0..cl], cmd_str[0..cl]);
        self.command_len = cl;

        const sl = @min(src_str.len, self.source.len);
        @memcpy(self.source[0..sl], src_str[0..sl]);
        self.source_len = sl;

        const gl = @min(grp_str.len, self.group.len);
        @memcpy(self.group[0..gl], grp_str[0..gl]);
        self.group_len = gl;
    }
};

/// Strips line comments (`// ...`), block comments (`/* ... */`), and trailing commas from JSONC text,
/// returning standard RFC 8259 JSON accepted by `std.json.parseFromSlice`.
pub fn cleanJsonc(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var out = try allocator.alloc(u8, input.len);
    errdefer allocator.free(out);

    var i: usize = 0;
    var out_len: usize = 0;
    var in_string = false;
    var escaped = false;

    while (i < input.len) {
        const c = input[i];

        if (in_string) {
            out[out_len] = c;
            out_len += 1;
            if (escaped) {
                escaped = false;
            } else if (c == '\\') {
                escaped = true;
            } else if (c == '"') {
                in_string = false;
            }
            i += 1;
            continue;
        }

        if (c == '"') {
            in_string = true;
            escaped = false;
            out[out_len] = c;
            out_len += 1;
            i += 1;
            continue;
        }

        // Line comment: // ...
        if (c == '/' and i + 1 < input.len and input[i + 1] == '/') {
            i += 2;
            while (i < input.len and input[i] != '\n') : (i += 1) {}
            if (i < input.len and input[i] == '\n') {
                out[out_len] = '\n';
                out_len += 1;
                i += 1;
            }
            continue;
        }

        // Block comment: /* ... */
        if (c == '/' and i + 1 < input.len and input[i + 1] == '*') {
            i += 2;
            while (i + 1 < input.len and !(input[i] == '*' and input[i + 1] == '/')) {
                if (input[i] == '\n') {
                    out[out_len] = '\n';
                    out_len += 1;
                }
                i += 1;
            }
            if (i + 1 < input.len) i += 2;
            continue;
        }

        // Trailing comma before '}' or ']'
        if (c == ',') {
            var j = i + 1;
            while (j < input.len) : (j += 1) {
                const jc = input[j];
                if (jc == ' ' or jc == '\t' or jc == '\r' or jc == '\n') continue;
                if (jc == '/' and j + 1 < input.len and input[j + 1] == '/') {
                    j += 2;
                    while (j < input.len and input[j] != '\n') : (j += 1) {}
                    continue;
                }
                if (jc == '/' and j + 1 < input.len and input[j + 1] == '*') {
                    j += 2;
                    while (j + 1 < input.len and !(input[j] == '*' and input[j + 1] == '/')) : (j += 1) {}
                    if (j + 1 < input.len) j += 1;
                    continue;
                }
                break;
            }
            if (j < input.len and (input[j] == '}' or input[j] == ']')) {
                // Skip the trailing comma
                out[out_len] = ' ';
                out_len += 1;
                i += 1;
                continue;
            }
        }

        out[out_len] = c;
        out_len += 1;
        i += 1;
    }

    return out[0..out_len];
}

/// Parses a `.vscode/launch.json` document looking for `preLaunchTask` or build commands.
/// Copies the task name into `out_buf` and returns the slice.
pub fn parseLaunchJson(json_text: []const u8, out_buf: []u8) ?[]const u8 {
    const cleaned = cleanJsonc(std.heap.c_allocator, json_text) catch return null;
    defer std.heap.c_allocator.free(cleaned);

    var parsed = std.json.parseFromSlice(std.json.Value, std.heap.c_allocator, cleaned, .{}) catch return null;
    defer parsed.deinit();

    if (parsed.value != .object) return null;
    const configs_val = parsed.value.object.get("configurations") orelse return null;
    if (configs_val != .array or configs_val.array.items.len == 0) return null;

    for (configs_val.array.items) |cfg_item| {
        if (cfg_item != .object) continue;
        const cfg_obj = cfg_item.object;

        if (cfg_obj.get("preLaunchTask")) |plt| {
            if (plt == .string and plt.string.len > 0) {
                return copyToOutBuf(plt.string, out_buf);
            }
        }
        if (cfg_obj.get("buildCommand")) |bc| {
            if (bc == .string and bc.string.len > 0) {
                return copyToOutBuf(bc.string, out_buf);
            }
        }
        if (cfg_obj.get("command")) |c| {
            if (c == .string and c.string.len > 0) {
                return copyToOutBuf(c.string, out_buf);
            }
        }
    }

    return null;
}

/// Parses a `.vscode/tasks.json` payload looking for a build task matching `match_label_opt`,
/// a default build task (`group: "build"` or `group.kind: "build"`), or a task with `"build"` in label.
/// Joins `command` and optional `args` into `out_buf`.
pub fn parseTasksJsonBuildCommand(json_text: []const u8, match_label_opt: ?[]const u8, out_buf: []u8) ?TaskInfo {
    const cleaned = cleanJsonc(std.heap.c_allocator, json_text) catch return null;
    defer std.heap.c_allocator.free(cleaned);

    var parsed = std.json.parseFromSlice(std.json.Value, std.heap.c_allocator, cleaned, .{}) catch return null;
    defer parsed.deinit();

    if (parsed.value != .object) return null;
    const tasks_val = parsed.value.object.get("tasks") orelse return null;
    if (tasks_val != .array or tasks_val.array.items.len == 0) return null;

    const candidate_source: []const u8 = ".vscode/tasks.json";

    // 1. If a specific task label is requested (e.g. from launch.json `preLaunchTask`), match it first
    if (match_label_opt) |target_lbl| {
        for (tasks_val.array.items) |item| {
            if (item != .object) continue;
            const obj = item.object;
            const cmd_val = obj.get("command") orelse continue;
            if (cmd_val != .string or cmd_val.string.len == 0) continue;

            if (obj.get("label")) |lbl| {
                if (lbl == .string and std.ascii.eqlIgnoreCase(lbl.string, target_lbl)) {
                    if (formatTaskCommandLine(obj, cmd_val.string, out_buf)) |full_cmd| {
                        return .{ .command = full_cmd, .source = ".vscode/tasks.json (via launch.json preLaunchTask)" };
                    }
                }
            }
        }
    }

    var default_build_cmd: ?TaskInfo = null;
    var any_build_cmd: ?TaskInfo = null;
    var first_cmd: ?TaskInfo = null;

    for (tasks_val.array.items) |item| {
        if (item != .object) continue;
        const obj = item.object;

        const cmd_val = obj.get("command") orelse continue;
        if (cmd_val != .string or cmd_val.string.len == 0) continue;

        var is_default = false;
        var is_build = false;

        if (obj.get("group")) |grp| {
            if (grp == .string and std.ascii.eqlIgnoreCase(grp.string, "build")) {
                is_build = true;
            } else if (grp == .object) {
                if (grp.object.get("kind")) |kind_val| {
                    if (kind_val == .string and std.ascii.eqlIgnoreCase(kind_val.string, "build")) {
                        is_build = true;
                    }
                }
                if (grp.object.get("isDefault")) |def_val| {
                    if (def_val == .bool and def_val.bool) {
                        is_default = true;
                    }
                }
            }
        }

        if (obj.get("label")) |lbl| {
            if (lbl == .string and ui.command_registry_mod.containsIgnoreCase(lbl.string, "build")) {
                is_build = true;
            }
        }

        if (is_build and is_default and default_build_cmd == null) {
            if (formatTaskCommandLine(obj, cmd_val.string, out_buf)) |full_cmd| {
                default_build_cmd = .{ .command = full_cmd, .source = ".vscode/tasks.json" };
            }
        } else if (is_build and any_build_cmd == null) {
            // Buffer to candidate if default_build not found
            var tmp_buf: [512]u8 = undefined;
            if (formatTaskCommandLine(obj, cmd_val.string, &tmp_buf)) |c| {
                if (copyToOutBuf(c, out_buf)) |full_cmd| {
                    any_build_cmd = .{ .command = full_cmd, .source = ".vscode/tasks.json" };
                }
            }
        }

        if (first_cmd == null) {
            var tmp_buf: [512]u8 = undefined;
            if (formatTaskCommandLine(obj, cmd_val.string, &tmp_buf)) |c| {
                if (copyToOutBuf(c, out_buf)) |full_cmd| {
                    first_cmd = .{ .command = full_cmd, .source = candidate_source };
                }
            }
        }
    }

    if (default_build_cmd) |info| return info;
    if (any_build_cmd) |info| return info;
    if (first_cmd) |info| return info;

    return null;
}

fn formatTaskCommandLine(task_obj: std.json.ObjectMap, base_command: []const u8, out_buf: []u8) ?[]const u8 {
    var pos: usize = 0;
    const base_copy = @min(base_command.len, out_buf.len);
    @memcpy(out_buf[0..base_copy], base_command[0..base_copy]);
    pos += base_copy;

    // Append optional `args: [ "...", ... ]`
    if (task_obj.get("args")) |args_val| {
        if (args_val == .array) {
            for (args_val.array.items) |arg_item| {
                if (arg_item != .string or arg_item.string.len == 0) continue;
                if (pos + 1 >= out_buf.len) break;
                out_buf[pos] = ' ';
                pos += 1;

                const arg_str = arg_item.string;
                const needs_quotes = std.mem.indexOfScalar(u8, arg_str, ' ') != null and arg_str[0] != '"';
                if (needs_quotes and pos + 1 < out_buf.len) {
                    out_buf[pos] = '"';
                    pos += 1;
                }

                const copy_l = @min(arg_str.len, out_buf.len - pos);
                @memcpy(out_buf[pos .. pos + copy_l], arg_str[0..copy_l]);
                pos += copy_l;

                if (needs_quotes and pos < out_buf.len) {
                    out_buf[pos] = '"';
                    pos += 1;
                }
            }
        }
    }

    return out_buf[0..pos];
}

fn copyToOutBuf(src: []const u8, out_buf: []u8) ?[]const u8 {
    if (src.len == 0 or out_buf.len == 0) return null;
    const copy_len = @min(src.len, out_buf.len);
    @memcpy(out_buf[0..copy_len], src[0..copy_len]);
    return out_buf[0..copy_len];
}

/// Reads the contents of a workspace file either from an open editor buffer or from disk.
pub fn readWorkspaceFileText(state: *const EditorState, rel_path: []const u8, disk_read_buf: []u8) ?[]const u8 {
    if (state.findWorkspaceFileIndexByPath(rel_path)) |idx| {
        const text = state.buffers[idx].slice();
        if (text.len > 0) return text;
    }

    var disk_path_buf: [512]u8 = undefined;
    const ws = state.workspaceRoot();
    const full_p = std.fmt.bufPrint(&disk_path_buf, "{s}/{s}\x00", .{ ws, rel_path }) catch return null;
    const full_p_z: [*:0]const u8 = @ptrCast(full_p.ptr);

    if (std.c.fopen(full_p_z, "rb")) |fp| {
        defer _ = std.c.fclose(fp);
        const bytes_read = std.c.fread(disk_read_buf.ptr, 1, disk_read_buf.len, fp);
        if (bytes_read > 0) {
            return disk_read_buf[0..bytes_read];
        }
    }
    return null;
}

/// Detects the build command for `state` by checking:
///   1. `.vscode/launch.json` for `preLaunchTask`
///   2. `.vscode/tasks.json` matching `preLaunchTask` or default build groups
///   3. `launch.json` preLaunchTask if formatted as a direct command
///   4. Project file auto-detection (`build.zig`, `Cargo.toml`, `package.json`, `Makefile`, etc.)
pub fn detectBuildTask(state: *const EditorState, out_buf: []u8) TaskInfo {
    var pre_launch_buf: [128]u8 = undefined;
    var pre_launch_task: ?[]const u8 = null;
    var disk_file_buf: [16384]u8 = undefined;

    // 1. Check `.vscode/launch.json`
    if (readWorkspaceFileText(state, ".vscode/launch.json", &disk_file_buf)) |text| {
        pre_launch_task = parseLaunchJson(text, &pre_launch_buf);
    }

    // 2. Check `.vscode/tasks.json`
    if (readWorkspaceFileText(state, ".vscode/tasks.json", &disk_file_buf)) |text| {
        if (parseTasksJsonBuildCommand(text, pre_launch_task, out_buf)) |info| {
            return info;
        }
    }

    // 3. If tasks.json was missing but launch.json specified preLaunchTask that looks like a command
    if (pre_launch_task) |plt| {
        if (std.mem.indexOfScalar(u8, plt, ' ') != null or
            std.ascii.eqlIgnoreCase(plt, "make") or
            std.ascii.eqlIgnoreCase(plt, "build"))
        {
            if (copyToOutBuf(plt, out_buf)) |cmd| {
                return .{ .command = cmd, .source = ".vscode/launch.json (preLaunchTask)" };
            }
        }
    }

    // 4. Scan workspace files for project build systems
    const wfs = state.workspaceFiles();
    for (wfs) |wf| {
        if (std.mem.eql(u8, wf.path, "build.zig") or std.mem.endsWith(u8, wf.path, "/build.zig")) {
            return .{ .command = "zig build", .source = "build.zig" };
        }
    }
    for (wfs) |wf| {
        if (std.mem.eql(u8, wf.path, "Cargo.toml") or std.mem.endsWith(u8, wf.path, "/Cargo.toml")) {
            return .{ .command = "cargo build", .source = "Cargo.toml" };
        }
    }
    for (wfs) |wf| {
        if (std.mem.eql(u8, wf.path, "package.json") or std.mem.endsWith(u8, wf.path, "/package.json")) {
            var has_bun = false;
            var has_pnpm = false;
            var has_yarn = false;
            for (wfs) |w2| {
                if (std.mem.eql(u8, w2.name, "bun.lockb") or std.mem.eql(u8, w2.name, "bun.lock")) has_bun = true;
                if (std.mem.eql(u8, w2.name, "pnpm-lock.yaml")) has_pnpm = true;
                if (std.mem.eql(u8, w2.name, "yarn.lock")) has_yarn = true;
            }
            if (has_bun) return .{ .command = "bun run build", .source = "package.json (bun)" };
            if (has_pnpm) return .{ .command = "pnpm build", .source = "package.json (pnpm)" };
            if (has_yarn) return .{ .command = "yarn build", .source = "package.json (yarn)" };
            return .{ .command = "npm run build", .source = "package.json" };
        }
    }
    for (wfs) |wf| {
        if (std.mem.eql(u8, wf.path, "Makefile") or std.mem.eql(u8, wf.path, "makefile")) {
            return .{ .command = "make", .source = "Makefile" };
        }
        if (std.mem.eql(u8, wf.path, "CMakeLists.txt")) {
            return .{ .command = "cmake --build build", .source = "CMakeLists.txt" };
        }
        if (std.mem.eql(u8, wf.path, "go.mod")) {
            return .{ .command = "go build ./...", .source = "go.mod" };
        }
        if (std.mem.eql(u8, wf.path, "pyproject.toml")) {
            return .{ .command = "uv run pytest", .source = "pyproject.toml" };
        }
    }

    return .{ .command = "zig build", .source = "default" };
}

/// Enumerates all runnable workspace tasks declared in `.vscode/tasks.json` (and `launch.json`),
/// or falls back to project build auto-detection if no JSON configuration exists.
/// Used to populate runnable tasks in the Command Palette.
pub fn listWorkspaceTasks(state: *const EditorState, out: []TaskEntry) usize {
    var count: usize = 0;
    var disk_buf: [16384]u8 = undefined;

    // 1. Read `.vscode/tasks.json`
    if (readWorkspaceFileText(state, ".vscode/tasks.json", &disk_buf)) |raw_json| {
        if (cleanJsonc(std.heap.c_allocator, raw_json)) |cleaned| {
            defer std.heap.c_allocator.free(cleaned);

            if (std.json.parseFromSlice(std.json.Value, std.heap.c_allocator, cleaned, .{})) |parsed| {
                defer parsed.deinit();

                if (parsed.value == .object) {
                    if (parsed.value.object.get("tasks")) |tasks_val| {
                        if (tasks_val == .array) {
                            for (tasks_val.array.items) |item| {
                                if (count >= out.len) break;
                                if (item != .object) continue;
                                const obj = item.object;

                                const cmd_val = obj.get("command") orelse continue;
                                if (cmd_val != .string or cmd_val.string.len == 0) continue;

                                const label_str: []const u8 = if (obj.get("label")) |lbl|
                                    (if (lbl == .string and lbl.string.len > 0) lbl.string else cmd_val.string)
                                else
                                    cmd_val.string;

                                var grp_str: []const u8 = "";
                                if (obj.get("group")) |grp| {
                                    if (grp == .string) {
                                        grp_str = grp.string;
                                    } else if (grp == .object) {
                                        if (grp.object.get("kind")) |k| {
                                            if (k == .string) grp_str = k.string;
                                        }
                                    }
                                }

                                var full_cmd_buf: [512]u8 = undefined;
                                const full_cmd = formatTaskCommandLine(obj, cmd_val.string, &full_cmd_buf) orelse cmd_val.string;

                                out[count].set(label_str, full_cmd, ".vscode/tasks.json", grp_str);
                                count += 1;
                            }
                        }
                    }
                }
            } else |_| {}
        } else |_| {}
    }

    // 2. Also check `.vscode/launch.json` for preLaunchTask or buildCommand if not already in list
    if (readWorkspaceFileText(state, ".vscode/launch.json", &disk_buf)) |raw_launch| {
        var pre_launch_buf: [128]u8 = undefined;
        if (parseLaunchJson(raw_launch, &pre_launch_buf)) |plt| {
            var exists = false;
            for (out[0..count]) |entry| {
                if (std.ascii.eqlIgnoreCase(entry.nameSlice(), plt)) {
                    exists = true;
                    break;
                }
            }
            if (!exists and count < out.len) {
                out[count].set(plt, plt, ".vscode/launch.json (preLaunchTask)", "build");
                count += 1;
            }
        }
    }

    // 3. If tasks list is still empty, scan project build systems
    if (count == 0) {
        var detect_buf: [256]u8 = undefined;
        const info = detectBuildTask(state, &detect_buf);
        if (count < out.len) {
            out[count].set(info.command, info.command, info.source, "build");
            count += 1;
        }
    }

    return count;
}

pub const AppDylibEntry = struct {
    path: platform.InlineString(256) = .{},
    name: platform.InlineString(64) = .{},

    pub fn set(self: *AppDylibEntry, p: []const u8, n: []const u8) void {
        self.path.set(p);
        self.name.set(n);
    }

    pub fn pathSlice(self: *const AppDylibEntry) []const u8 {
        return self.path.slice();
    }

    pub fn nameSlice(self: *const AppDylibEntry) []const u8 {
        return self.name.slice();
    }
};

/// Resolves a workspace-relative path or `${workspaceFolder}` path into an absolute or workspace-rooted path.
pub fn resolveWorkspaceRelativePath(ws_root: []const u8, raw: []const u8, out_buf: []u8) ?[]const u8 {
    var trimmed = std.mem.trim(u8, raw, " \t\r\n\"");
    if (trimmed.len == 0) return null;

    const ws_var1 = "${workspaceFolder}";
    const ws_var2 = "${workspaceRoot}";
    if (std.mem.startsWith(u8, trimmed, ws_var1)) {
        trimmed = trimmed[ws_var1.len..];
        if (std.mem.startsWith(u8, trimmed, "/")) trimmed = trimmed[1..];
    } else if (std.mem.startsWith(u8, trimmed, ws_var2)) {
        trimmed = trimmed[ws_var2.len..];
        if (std.mem.startsWith(u8, trimmed, "/")) trimmed = trimmed[1..];
    }

    const is_abs = std.mem.startsWith(u8, trimmed, "/") or
        (trimmed.len >= 3 and trimmed[1] == ':' and (trimmed[2] == '/' or trimmed[2] == '\\'));
    if (is_abs) {
        if (trimmed.len <= out_buf.len) {
            @memcpy(out_buf[0..trimmed.len], trimmed);
            return out_buf[0..trimmed.len];
        }
        return null;
    }

    if (ws_root.len == 0) {
        if (trimmed.len <= out_buf.len) {
            @memcpy(out_buf[0..trimmed.len], trimmed);
            return out_buf[0..trimmed.len];
        }
        return null;
    }

    return std.fmt.bufPrint(out_buf, "{s}/{s}", .{ ws_root, trimmed }) catch null;
}

/// Enumerates candidate application `.dylib` or `.so` libraries found in standard build output directories
/// (`zig-out/lib`, `zig-out/bin`, `build`, `target/debug`) of the workspace.
pub fn listWorkspaceAppDylibs(state: *const EditorState, out: []AppDylibEntry) usize {
    var count: usize = 0;
    const ws_root = state.workspaceRoot();
    if (ws_root.len == 0) return 0;

    const candidate_subdirs = [_][]const u8{
        "zig-out/lib",
        "zig-out/bin",
        "build",
        "target/debug",
    };

    var dir_path_buf: [512]u8 = undefined;
    for (candidate_subdirs) |sub| {
        const full_sub = std.fmt.bufPrint(&dir_path_buf, "{s}/{s}", .{ ws_root, sub }) catch continue;
        var sub_z: [512:0]u8 = @splat(0);
        if (full_sub.len >= sub_z.len) continue;
        @memcpy(sub_z[0..full_sub.len], full_sub);
        sub_z[full_sub.len] = 0;

        const dirp = platform.fs_util.opendir(&sub_z) orelse continue;
        defer _ = platform.fs_util.closedir(dirp);

        while (platform.fs_util.readdir(dirp)) |ent| {
            const name = platform.fs_util.direntName(ent);
            const is_dylib = std.mem.endsWith(u8, name, ".dylib") or std.mem.endsWith(u8, name, ".so");
            if (!is_dylib) continue;

            // Filter out SkiaSharp, editor host, and LSP extensions
            if (std.mem.indexOf(u8, name, "SkiaSharp") != null) continue;
            if (std.mem.indexOf(u8, name, "_lsp") != null) continue;

            var full_path_buf: [512]u8 = undefined;
            const full_path = std.fmt.bufPrint(&full_path_buf, "{s}/{s}", .{ full_sub, name }) catch continue;

            if (count < out.len) {
                out[count].set(full_path, name);
                count += 1;
            }
        }
    }

    return count;
}

/// Probes the workspace for candidate application dylibs, prioritizing libraries with "app" in their filename.
pub fn findWorkspaceCandidateAppDylib(state: *const EditorState, out_buf: []u8) ?[]const u8 {
    var entries: [16]AppDylibEntry = undefined;
    const count = listWorkspaceAppDylibs(state, &entries);
    if (count == 0) return null;

    // 1. Look for dylibs with "app" in their filename (e.g. libskorepad_app.dylib)
    for (entries[0..count]) |entry| {
        if (std.mem.indexOf(u8, entry.nameSlice(), "app") != null) {
            const p = entry.pathSlice();
            if (p.len <= out_buf.len) {
                @memcpy(out_buf[0..p.len], p);
                return out_buf[0..p.len];
            }
        }
    }

    // 2. Otherwise pick the first candidate dylib
    const p = entries[0].pathSlice();
    if (p.len <= out_buf.len) {
        @memcpy(out_buf[0..p.len], p);
        return out_buf[0..p.len];
    }
    return null;
}

/// Detects the target preview application `.dylib` path for the current workspace.
/// Resolution hierarchy:
/// 1. `state.app_custom_path` (explicitly selected by user via command palette or argument)
/// 2. `.vscode/settings.json` (`"app.previewDylib"`, `"app.preview"`, `"app.previewPath"`, `"editor.appPreview"`)
/// 3. `.vscode/launch.json` (`"dylib"`, `"program"` ending in `.dylib`, or `"args": ["--dylib", "..."]`)
/// 4. `.vscode/tasks.json` (`"previewApp"`, `"app"`, or `"dylib"` on task objects)
/// 5. Automatically discovered candidate from workspace build output (`findWorkspaceCandidateAppDylib`)
pub fn detectPreviewAppDylib(state: *const EditorState, out_buf: []u8) ?[]const u8 {
    if (state.app_custom_path.len > 0) {
        const p = state.app_custom_path.slice();
        if (p.len <= out_buf.len) {
            @memcpy(out_buf[0..p.len], p);
            return out_buf[0..p.len];
        }
    }

    const ws_root = state.workspaceRoot();
    var disk_buf: [16384]u8 = undefined;

    // 2. Check `.vscode/settings.json`
    if (readWorkspaceFileText(state, ".vscode/settings.json", &disk_buf)) |raw_settings| {
        if (cleanJsonc(std.heap.c_allocator, raw_settings)) |cleaned| {
            defer std.heap.c_allocator.free(cleaned);
            if (std.json.parseFromSlice(std.json.Value, std.heap.c_allocator, cleaned, .{})) |parsed| {
                defer parsed.deinit();
                if (parsed.value == .object) {
                    const keys = [_][]const u8{ "app.previewDylib", "app.preview", "app.previewPath", "editor.appPreview" };
                    for (keys) |key| {
                        if (parsed.value.object.get(key)) |val| {
                            if (val == .string and val.string.len > 0) {
                                if (resolveWorkspaceRelativePath(ws_root, val.string, out_buf)) |resolved| {
                                    return resolved;
                                }
                            }
                        }
                    }
                }
            } else |_| {}
        } else |_| {}
    }

    // 3. Check `.vscode/launch.json`
    if (readWorkspaceFileText(state, ".vscode/launch.json", &disk_buf)) |raw_launch| {
        if (cleanJsonc(std.heap.c_allocator, raw_launch)) |cleaned| {
            defer std.heap.c_allocator.free(cleaned);
            if (std.json.parseFromSlice(std.json.Value, std.heap.c_allocator, cleaned, .{})) |parsed| {
                defer parsed.deinit();
                if (parsed.value == .object) {
                    if (parsed.value.object.get("configurations")) |cfgs| {
                        if (cfgs == .array) {
                            for (cfgs.array.items) |item| {
                                if (item != .object) continue;
                                const obj = item.object;
                                // Check "dylib" property
                                if (obj.get("dylib")) |d| {
                                    if (d == .string and d.string.len > 0) {
                                        if (resolveWorkspaceRelativePath(ws_root, d.string, out_buf)) |resolved| {
                                            return resolved;
                                        }
                                    }
                                }
                                // Check "program" ending in .dylib
                                if (obj.get("program")) |prog| {
                                    if (prog == .string and (std.mem.endsWith(u8, prog.string, ".dylib") or std.mem.endsWith(u8, prog.string, ".so"))) {
                                        if (resolveWorkspaceRelativePath(ws_root, prog.string, out_buf)) |resolved| {
                                            return resolved;
                                        }
                                    }
                                }
                                // Check "args" containing "--dylib <path>"
                                if (obj.get("args")) |args| {
                                    if (args == .array) {
                                        var next_is_dylib = false;
                                        for (args.array.items) |arg| {
                                            if (arg != .string) continue;
                                            if (next_is_dylib) {
                                                if (resolveWorkspaceRelativePath(ws_root, arg.string, out_buf)) |resolved| {
                                                    return resolved;
                                                }
                                                next_is_dylib = false;
                                            } else if (std.mem.eql(u8, arg.string, "--dylib")) {
                                                next_is_dylib = true;
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            } else |_| {}
        } else |_| {}
    }

    // 4. Check `.vscode/tasks.json`
    if (readWorkspaceFileText(state, ".vscode/tasks.json", &disk_buf)) |raw_tasks| {
        if (cleanJsonc(std.heap.c_allocator, raw_tasks)) |cleaned| {
            defer std.heap.c_allocator.free(cleaned);
            if (std.json.parseFromSlice(std.json.Value, std.heap.c_allocator, cleaned, .{})) |parsed| {
                defer parsed.deinit();
                if (parsed.value == .object) {
                    if (parsed.value.object.get("tasks")) |tasks_val| {
                        if (tasks_val == .array) {
                            for (tasks_val.array.items) |item| {
                                if (item != .object) continue;
                                const obj = item.object;
                                const app_keys = [_][]const u8{ "previewApp", "app", "dylib" };
                                for (app_keys) |k| {
                                    if (obj.get(k)) |val| {
                                        if (val == .string and val.string.len > 0) {
                                            if (resolveWorkspaceRelativePath(ws_root, val.string, out_buf)) |resolved| {
                                                return resolved;
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            } else |_| {}
        } else |_| {}
    }

    // 5. Automatic workspace discovery from build outputs
    return findWorkspaceCandidateAppDylib(state, out_buf);
}

fn appendPathSegment(buf: []u8, len: *usize, seg: []const u8) void {
    if (seg.len == 0) return;
    if (len.* > 0 and len.* < buf.len - 1) {
        buf[len.*] = ':';
        len.* += 1;
    }
    const rem = if (buf.len > len.* + 1) buf.len - 1 - len.* else 0;
    const copy_n = @min(seg.len, rem);
    if (copy_n > 0) {
        @memcpy(buf[len.* .. len.* + copy_n], seg[0..copy_n]);
        len.* += copy_n;
    }
}

/// Asynchronous non-blocking subprocess task execution context.
/// Spawns tasks in an isolated process with redirected stdout/stderr pipes,
/// draining log lines incrementally into the Workbench Output Console tab without blocking the UI.
pub const TaskRunner = struct {
    child_pid: c_int = -1,
    pipe_fd: c_int = -1,
    is_running: bool = false,
    task_name: platform.InlineString(64) = .{},
    command_line: platform.InlineString(256) = .{},
    source_info: platform.InlineString(64) = .{},
    exit_code: ?c_int = null,
    start_time_ms: i64 = 0,
    line_buf: [1024]u8 = undefined,
    line_buf_len: usize = 0,

    /// Starts a task in its own isolated execution context.
    pub fn start(self: *TaskRunner, state: *EditorState, task_name: []const u8, command: []const u8, source: []const u8) bool {
        if (self.is_running) {
            self.terminate();
            state.appendOutput("Tasks", "[Tasks] Terminated previous task.");
        }

        self.task_name.set(task_name);
        self.command_line.set(command);
        self.source_info.set(source);
        self.exit_code = null;
        self.line_buf_len = 0;
        self.start_time_ms = @intCast(platform.profiler.nowNs() / std.time.ns_per_ms);

        var log_hdr_buf: [384]u8 = undefined;
        const log_hdr = std.fmt.bufPrint(&log_hdr_buf, ">>> Executing task: {s} (source: {s}) <<<", .{ command, source }) catch command;
        state.appendOutput("Tasks", log_hdr);

        var notice_buf: [128]u8 = undefined;
        const notice_msg = std.fmt.bufPrint(&notice_buf, "Running task: {s}", .{command}) catch "Running task";
        state.setStatusNotice(notice_msg);

        state.output_scroll_to_bottom = true;
        state.output_channel_filter.set("Tasks");

        if (comptime is_windows) {
            // Fallback for Windows if needed
            self.is_running = false;
            return false;
        }

        var fds: [2]c_int = undefined;
        if (posix_c.pipe(&fds) != 0) {
            state.appendOutput("Tasks", "[Error] Failed to create subprocess pipe.");
            return false;
        }

        const pid = posix_c.fork();
        if (pid < 0) {
            _ = posix_c.close(fds[0]);
            _ = posix_c.close(fds[1]);
            state.appendOutput("Tasks", "[Error] Failed to fork task subprocess.");
            return false;
        }

        if (pid == 0) {
            // Child execution context: redirect stdout & stderr to pipe write end
            _ = posix_c.dup2(fds[1], 1);
            _ = posix_c.dup2(fds[1], 2);
            _ = posix_c.close(fds[0]);
            _ = posix_c.close(fds[1]);

            const ws_root = state.workspaceRoot();
            if (ws_root.len > 0) {
                var ws_z: [512:0]u8 = @splat(0);
                const clen = @min(ws_root.len, ws_z.len - 1);
                @memcpy(ws_z[0..clen], ws_root[0..clen]);
                ws_z[clen] = 0;
                _ = posix_c.chdir(&ws_z);
            }

            // Augment PATH with standard macOS / Linux developer toolchain directories
            // We prepend export PATH="..." directly to the command string so that regardless of
            // whether the shell is zsh, bash, or sh, all toolchains (zig, cargo, brew, etc.) are found.
            var cmd_z: [2048:0]u8 = @splat(0);
            const path_prefix = "export PATH=\"/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:$HOME/.cargo/bin:$HOME/.local/bin:$HOME/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH\"; ";
            const copy_p = @min(path_prefix.len, cmd_z.len - 1);
            @memcpy(cmd_z[0..copy_p], path_prefix[0..copy_p]);
            const rem_c = cmd_z.len - 1 - copy_p;
            const copy_l = @min(command.len, rem_c);
            @memcpy(cmd_z[copy_p .. copy_p + copy_l], command[0..copy_l]);
            cmd_z[copy_p + copy_l] = 0;

            var path_buf: [4096:0]u8 = @splat(0);
            var path_len: usize = 0;

            if (std.c.getenv("HOME")) |home_z| {
                const home_s = std.mem.sliceTo(home_z, 0);
                var sub_buf: [256]u8 = undefined;
                if (std.fmt.bufPrint(&sub_buf, "{s}/.cargo/bin", .{home_s})) |p| appendPathSegment(&path_buf, &path_len, p) else |_| {}
                if (std.fmt.bufPrint(&sub_buf, "{s}/.local/bin", .{home_s})) |p| appendPathSegment(&path_buf, &path_len, p) else |_| {}
                if (std.fmt.bufPrint(&sub_buf, "{s}/bin", .{home_s})) |p| appendPathSegment(&path_buf, &path_len, p) else |_| {}
            }

            appendPathSegment(&path_buf, &path_len, "/opt/homebrew/bin");
            appendPathSegment(&path_buf, &path_len, "/opt/homebrew/sbin");
            appendPathSegment(&path_buf, &path_len, "/usr/local/bin");
            appendPathSegment(&path_buf, &path_len, "/usr/bin");
            appendPathSegment(&path_buf, &path_len, "/bin");
            appendPathSegment(&path_buf, &path_len, "/usr/sbin");
            appendPathSegment(&path_buf, &path_len, "/sbin");

            if (std.c.getenv("PATH")) |cur_p_z| {
                appendPathSegment(&path_buf, &path_len, std.mem.sliceTo(cur_p_z, 0));
            }
            path_buf[path_len] = 0;

            _ = posix_c.setenv("PATH", &path_buf, 1);
            _ = posix_c.setenv("TERM", "xterm-256color", 1);
            _ = posix_c.setenv("COLORTERM", "truecolor", 1);
            _ = posix_c.setenv("CLICOLOR", "1", 1);
            _ = posix_c.setenv("FORCE_COLOR", "1", 1);

            const shell_env = std.c.getenv("SHELL");
            const shell: [*:0]const u8 = if (shell_env) |s| blk: {
                const s_slice = std.mem.sliceTo(s, 0);
                if (builtin.os.tag == .macos and std.mem.eql(u8, s_slice, "/bin/sh")) {
                    break :blk "/bin/zsh";
                }
                break :blk s;
            } else if (builtin.os.tag == .macos)
                "/bin/zsh"
            else
                "/bin/sh";

            // Primary: Direct shell execution with prepended toolchain PATH
            const shell_argv = [_:null]?[*:0]const u8{ shell, "-c", &cmd_z };
            _ = posix_c.execv(shell, &shell_argv);

            // Fallback 1: Login shell
            const login_argv = [_:null]?[*:0]const u8{ shell, "-l", "-c", &cmd_z };
            _ = posix_c.execv(shell, &login_argv);

            // Fallback 2: Direct /bin/zsh on macOS
            if (builtin.os.tag == .macos) {
                const zsh_argv = [_:null]?[*:0]const u8{ "/bin/zsh", "-c", &cmd_z };
                _ = posix_c.execv("/bin/zsh", &zsh_argv);
            }

            // Fallback 3: /bin/sh with prepended toolchain PATH
            const sh_argv = [_:null]?[*:0]const u8{ "/bin/sh", "-c", &cmd_z };
            _ = posix_c.execv("/bin/sh", &sh_argv);
            posix_c._exit(127);
        }

        // Parent process: close write end, configure non-blocking read pipe
        _ = posix_c.close(fds[1]);
        const flags = posix_c.fcntl(fds[0], F_GETFL, @as(c_int, 0));
        if (flags >= 0) {
            _ = posix_c.fcntl(fds[0], F_SETFL, flags | O_NONBLOCK);
        }

        self.pipe_fd = fds[0];
        self.child_pid = pid;
        self.is_running = true;

        if (state.ui_ctx.platform_ctx) |pctx| {
            pctx.needs_continuous_redraw = true;
        }
        state.ui_ctx.invalidateWindow();
        return true;
    }

    /// Polls the active task subprocess pipe incrementally during `Pass.input`.
    /// Streams complete lines into `state.output_lines` under the `"Tasks"` channel.
    pub fn poll(self: *TaskRunner, state: *EditorState) void {
        if (!self.is_running or self.pipe_fd < 0) return;

        var read_buf: [2048]u8 = undefined;
        while (true) {
            const n = posix_c.read(self.pipe_fd, &read_buf, read_buf.len);
            if (n > 0) {
                const bytes = read_buf[0..@intCast(n)];
                for (bytes) |b| {
                    if (b == '\n') {
                        state.appendOutput("Tasks", self.line_buf[0..self.line_buf_len]);
                        self.line_buf_len = 0;
                    } else if (b != '\r') {
                        if (self.line_buf_len < self.line_buf.len) {
                            self.line_buf[self.line_buf_len] = b;
                            self.line_buf_len += 1;
                        } else {
                            state.appendOutput("Tasks", self.line_buf[0..self.line_buf_len]);
                            self.line_buf[0] = b;
                            self.line_buf_len = 1;
                        }
                    }
                }
                state.output_scroll_to_bottom = true;
                state.ui_ctx.invalidateWindow();
                continue;
            }

            if (n == 0) {
                // EOF: child finished
                if (self.line_buf_len > 0) {
                    state.appendOutput("Tasks", self.line_buf[0..self.line_buf_len]);
                    self.line_buf_len = 0;
                }

                var status: c_int = 0;
                _ = posix_c.waitpid(self.child_pid, &status, 0);
                const exit_code: c_int = if ((status & 0x7f) == 0)
                    @intCast((status >> 8) & 0xff)
                else
                    @intCast(status & 0x7f);

                self.exit_code = exit_code;
                if (exit_code == 0) {
                    state.appendOutput("Tasks", "[Done] Task finished successfully.");
                    state.setStatusNotice("Task finished successfully.");
                } else {
                    var msg_buf: [64]u8 = undefined;
                    const msg = std.fmt.bufPrint(&msg_buf, "[Failed] Task exited with code {d}", .{exit_code}) catch "[Failed]";
                    state.appendOutput("Tasks", msg);
                    state.setStatusNotice(msg);
                }

                _ = posix_c.close(self.pipe_fd);
                self.pipe_fd = -1;
                self.child_pid = -1;
                self.is_running = false;
                state.output_scroll_to_bottom = true;
                state.ui_ctx.invalidateWindow();
                return;
            }

            // n < 0: non-blocking check
            const err = std.c._errno().*;
            if (err == EAGAIN or err == EINTR) {
                // Still running, no more bytes available this frame
                break;
            }

            // Read error / closed
            self.terminate();
            state.appendOutput("Tasks", "[Error] Task execution pipe closed unexpectedly.");
            state.ui_ctx.invalidateWindow();
            break;
        }

        if (self.is_running) {
            if (state.ui_ctx.platform_ctx) |pctx| {
                pctx.needs_continuous_redraw = true;
            }
        }
    }

    /// Terminates the running task process if active.
    pub fn terminate(self: *TaskRunner) void {
        if (self.child_pid > 0) {
            _ = posix_c.kill(self.child_pid, SIGTERM);
            _ = posix_c.waitpid(self.child_pid, null, WNOHANG);
            self.child_pid = -1;
        }
        if (self.pipe_fd >= 0) {
            _ = posix_c.close(self.pipe_fd);
            self.pipe_fd = -1;
        }
        self.is_running = false;
        self.line_buf_len = 0;
    }
};

/// Executes the workspace build task (`Cmd+Shift+B` / `workbench.action.tasks.build`).
/// Detects command from `.vscode/tasks.json`, `.vscode/launch.json`, or workspace defaults,
/// opens the Workbench Output Console tab, filters to the `"Tasks"` channel, and runs the task
/// in its own isolated execution context.
pub fn runBuildTask(state: *EditorState, active_bottom_tab: ?*u8) void {
    var cmd_buf: [512]u8 = undefined;
    const info = detectBuildTask(state, &cmd_buf);

    // Do not force the bottom panel open; run tasks quietly in their background execution context.
    // If the user already has the bottom panel open or opens it later, it routes to Output (tab 2).
    state.doc.bottom_panel_tab = 2; // Output Console tab
    if (active_bottom_tab) |tab| {
        tab.* = 2;
    }

    state.output_channel_filter.set("Tasks");
    _ = state.task_runner.start(state, "Build", info.command, info.source);

    if (state.ui_ctx.platform_ctx) |pctx| {
        pctx.needs_continuous_redraw = true;
    }
    state.ui_ctx.invalidateWindow();
}

// ============================================================================
// Unit Tests
// ============================================================================

test "tasks: parseTasksJsonBuildCommand with args and preLaunchTask matching" {
    const json1 =
        \\{
        \\  "version": "2.0.0",
        \\  "tasks": [
        \\    {
        \\      "label": "zig build",
        \\      "type": "shell",
        \\      "command": "zig build",
        \\      "args": ["-Doptimize=ReleaseFast", "--summary", "all"],
        \\      "group": {
        \\        "kind": "build",
        \\        "isDefault": true
        \\      }
        \\    }
        \\  ]
        \\}
    ;
    var out_buf: [256]u8 = undefined;
    const info1 = parseTasksJsonBuildCommand(json1, null, &out_buf).?;
    try std.testing.expectEqualStrings("zig build -Doptimize=ReleaseFast --summary all", info1.command);

    const json2 =
        \\{
        \\  "version": "2.0.0",
        \\  "tasks": [
        \\    {
        \\      "label": "build-c-example",
        \\      "command": "clang -g examples/main.c",
        \\      "group": "build"
        \\    },
        \\    {
        \\      "label": "build-go-example",
        \\      "command": "go build main.go",
        \\      "group": "build"
        \\    }
        \\  ]
        \\}
    ;
    // Match specific preLaunchTask from launch.json
    const info2 = parseTasksJsonBuildCommand(json2, "build-go-example", &out_buf).?;
    try std.testing.expectEqualStrings("go build main.go", info2.command);
}

test "tasks: parseLaunchJson extracts preLaunchTask and direct build commands" {
    const launch_json =
        \\{
        \\  "version": "0.2.0",
        \\  "configurations": [
        \\    {
        \\      "name": "Debug Editor",
        \\      "type": "lldb",
        \\      "request": "launch",
        \\      "preLaunchTask": "zig build"
        \\    }
        \\  ]
        \\}
    ;
    var out_buf: [128]u8 = undefined;
    const task_name = parseLaunchJson(launch_json, &out_buf).?;
    try std.testing.expectEqualStrings("zig build", task_name);
}

test "tasks: cleanJsonc strips comments and trailing commas from VS Code jsonc" {
    const jsonc =
        \\{
        \\  // Workspace build tasks header
        \\  "version": "2.0.0",
        \\  /* Multi-line
        \\     comment */
        \\  "tasks": [
        \\    {
        \\      "label": "zig build",
        \\      "command": "zig build",
        \\      "group": "build",
        \\    },
        \\  ],
        \\}
    ;
    var out_buf: [256]u8 = undefined;
    const info = parseTasksJsonBuildCommand(jsonc, null, &out_buf).?;
    try std.testing.expectEqualStrings("zig build", info.command);
}

test "tasks: parseTasksJsonBuildCommand with /Volumes/Skore/app_zig tasks.json" {
    const path_z: [*:0]const u8 = "/Volumes/Skore/app_zig/.vscode/tasks.json";
    if (std.c.fopen(path_z, "rb")) |fp| {
        defer _ = std.c.fclose(fp);
        var disk_read_buf: [16384]u8 = undefined;
        const n = std.c.fread(&disk_read_buf, 1, disk_read_buf.len, fp);
        if (n > 0) {
            var out_buf: [256]u8 = undefined;
            const info = parseTasksJsonBuildCommand(disk_read_buf[0..n], null, &out_buf).?;
            try std.testing.expectEqualStrings("zig build", info.command);
            try std.testing.expectEqualStrings(".vscode/tasks.json", info.source);
        }
    }
}

test "tasks: listWorkspaceTasks enumerates all tasks from tasks.json" {
    const platform_mod = @import("platform");
    var store = platform_mod.StateStore.init(std.testing.allocator);
    defer store.deinit();
    var snap = platform_mod.SnapshotBuffer.init(std.testing.allocator);
    defer snap.deinit();
    var pctx = platform_mod.PlatformContext{ .width = 1280.0, .height = 800.0 };
    pctx.bindHostStores(&store, &snap);

    const state = try std.testing.allocator.create(EditorState);
    defer std.testing.allocator.destroy(state);
    state.* = .{
        .frame_arena = std.heap.ArenaAllocator.init(std.testing.allocator),
        .fonts = undefined,
        .ui_ctx = undefined,
    };
    state.initResources(&pctx);
    defer state.deinitResources();

    var entries: [32]TaskEntry = undefined;
    const count = listWorkspaceTasks(state, &entries);
    try std.testing.expect(count > 0);
    try std.testing.expect(std.mem.indexOf(u8, entries[0].commandSlice(), "zig build") != null or
                           std.mem.indexOf(u8, entries[0].nameSlice(), "zig build") != null);
}

test "tasks: resolveWorkspaceRelativePath handles variables and relative paths" {
    var buf: [256]u8 = undefined;
    const r1 = resolveWorkspaceRelativePath("/Volumes/Skore/app_zig", "${workspaceFolder}/zig-out/lib/libskorepad_app.dylib", &buf);
    try std.testing.expectEqualStrings("/Volumes/Skore/app_zig/zig-out/lib/libskorepad_app.dylib", r1.?);

    const r2 = resolveWorkspaceRelativePath("/Volumes/Skore/app_zig", "zig-out/lib/libskorepad_app.dylib", &buf);
    try std.testing.expectEqualStrings("/Volumes/Skore/app_zig/zig-out/lib/libskorepad_app.dylib", r2.?);

    const r3 = resolveWorkspaceRelativePath("/Volumes/Skore/app_zig", "/opt/app.dylib", &buf);
    try std.testing.expectEqualStrings("/opt/app.dylib", r3.?);
}

test "tasks: detectPreviewAppDylib detects dylib from workspace candidates and config" {
    const platform_mod = @import("platform");
    var store = platform_mod.StateStore.init(std.testing.allocator);
    defer store.deinit();
    var snap = platform_mod.SnapshotBuffer.init(std.testing.allocator);
    defer snap.deinit();
    var pctx = platform_mod.PlatformContext{ .width = 1280.0, .height = 800.0 };
    pctx.bindHostStores(&store, &snap);

    const state = try std.testing.allocator.create(EditorState);
    defer std.testing.allocator.destroy(state);
    state.* = .{
        .frame_arena = std.heap.ArenaAllocator.init(std.testing.allocator),
        .fonts = undefined,
        .ui_ctx = undefined,
    };
    state.initResources(&pctx);
    defer state.deinitResources();

    var dylib_buf: [512]u8 = undefined;
    // When custom path is set, detectPreviewAppDylib returns it directly
    state.app_custom_path.set("/tmp/test_custom_app.dylib");
    const d1 = detectPreviewAppDylib(state, &dylib_buf);
    try std.testing.expectEqualStrings("/tmp/test_custom_app.dylib", d1.?);

    // When custom path is cleared, detectPreviewAppDylib inspects workspace launch.json / candidates
    state.app_custom_path.clear();
    const d2 = detectPreviewAppDylib(state, &dylib_buf);
    try std.testing.expect(d2 != null);
    try std.testing.expect(std.mem.endsWith(u8, d2.?, ".dylib") or std.mem.endsWith(u8, d2.?, ".so"));
}

test "tasks: subprocess execution inherits augmented developer toolchain PATH" {
    const platform_mod = @import("platform");
    var store = platform_mod.StateStore.init(std.testing.allocator);
    defer store.deinit();
    var snap = platform_mod.SnapshotBuffer.init(std.testing.allocator);
    defer snap.deinit();
    var pctx = platform_mod.PlatformContext{ .width = 1280.0, .height = 800.0 };
    pctx.bindHostStores(&store, &snap);

    const state = try std.testing.allocator.create(EditorState);
    defer std.testing.allocator.destroy(state);
    state.* = .{
        .frame_arena = std.heap.ArenaAllocator.init(std.testing.allocator),
        .fonts = undefined,
        .ui_ctx = undefined,
    };
    state.initResources(&pctx);
    defer state.deinitResources();

    var runner: TaskRunner = .{};
    defer runner.terminate();

    // Verify zig executable is found and executes cleanly via TaskRunner
    try std.testing.expect(runner.start(state, "zig version", "zig version", "test"));
    try std.testing.expect(runner.is_running);

    // Poll until complete
    const ts = std.c.timespec{ .sec = 0, .nsec = 20_000_000 };
    for (0..50) |_| {
        _ = std.c.nanosleep(&ts, null);
        runner.poll(state);
        if (!runner.is_running) break;
    }

    try std.testing.expect(!runner.is_running);
    try std.testing.expectEqual(@as(?c_int, 0), runner.exit_code);
}
