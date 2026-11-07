//! Git / Source Control Client & Output Parsers (`src/app/git_client.zig`).
//! Uses `platform.InlineString` for value-copied commit metadata safe across `.dylib` reloads.

const std = @import("std");
const platform = @import("platform");
const workspace_defaults = @import("workspace_defaults.zig");
const SampleFile = workspace_defaults.SampleFile;

const popen = platform.fs_util.popen;
const pclose = platform.fs_util.pclose;

pub const GitBranchSeparator = "---GIT_BRANCH_SEP---";
pub const GitLogSeparator = "---GIT_LOG_SEP---";

pub const GitFileStatus = struct {
    staged: bool = false,
    unstaged: bool = false,
    untracked: bool = false,
    staged_char: u8 = ' ',
    unstaged_char: u8 = ' ',

    pub fn isClean(self: GitFileStatus) bool {
        return !self.staged and !self.unstaged and !self.untracked;
    }
};

pub const MaxCommits: usize = 32;
pub const MaxCommitFiles: usize = 64;

pub const GitCommitEntry = struct {
    hash_str: platform.InlineString(16) = .{},
    subject_str: platform.InlineString(128) = .{},
    rel_time_str: platform.InlineString(32) = .{},
    files: [MaxCommitFiles]platform.InlineString(128) = @splat(.{}),
    file_statuses: [MaxCommitFiles]u8 = @splat('M'),
    file_count: u8 = 0,
    files_changed: u16 = 0,

    pub fn hash(self: *const GitCommitEntry) []const u8 {
        return self.hash_str.slice();
    }

    pub fn subject(self: *const GitCommitEntry) []const u8 {
        return self.subject_str.slice();
    }

    pub fn relTime(self: *const GitCommitEntry) []const u8 {
        return self.rel_time_str.slice();
    }
};

pub fn runCommand(cmd_z: [*:0]const u8) bool {
    const fp = popen(cmd_z, "r") orelse return false;
    var drain: [512]u8 = undefined;
    while (std.c.fread(&drain, 1, drain.len, fp) > 0) {}
    return pclose(fp) == 0;
}

pub fn runPathCommand(comptime fmt_str: []const u8, path: []const u8) void {
    var cmd_buf: [256]u8 = undefined;
    if (std.fmt.bufPrint(&cmd_buf, fmt_str ++ "\x00", .{path})) |slice| {
        const cmd_z: [*:0]const u8 = @ptrCast(slice.ptr);
        _ = runCommand(cmd_z);
    } else |_| {}
}

const dev_null_redirect = if (@import("builtin").os.tag == .windows) ">NUL 2>&1" else ">/dev/null 2>&1";
const stderr_null_redirect = if (@import("builtin").os.tag == .windows) "2>NUL" else "2>/dev/null";

pub fn stagePath(path: []const u8) void {
    runPathCommand("git add -- \"{s}\" " ++ dev_null_redirect, path);
}

pub fn unstagePath(path: []const u8) void {
    runPathCommand("git reset HEAD -- \"{s}\" " ++ dev_null_redirect, path);
}

pub fn stageAll() void {
    _ = runCommand("git add -A " ++ dev_null_redirect);
}

pub fn unstageAll() void {
    _ = runCommand("git reset HEAD " ++ dev_null_redirect);
}

pub fn discardPath(path: []const u8) void {
    runPathCommand("git checkout -- \"{s}\" " ++ dev_null_redirect, path);
}

pub const CommitError = error{
    WriteMessageFailed,
    GitCommitFailed,
};

pub fn commitWithMessage(full_msg: []const u8) CommitError!void {
    const fp = popen("git commit -F - " ++ dev_null_redirect, "w") orelse return error.WriteMessageFailed;
    const written = std.c.fwrite(full_msg.ptr, 1, full_msg.len, fp);
    const rc = pclose(fp);
    if (written != full_msg.len) return error.WriteMessageFailed;
    if (rc != 0) return error.GitCommitFailed;
}

/// Parses `git status --porcelain` output directly into the `out_statuses` slice.
pub fn parsePorcelainStatus(porcelain_out: []const u8, wfs: []const SampleFile, out_statuses: []GitFileStatus) void {
    @memset(out_statuses, .{});
    var lines = std.mem.splitScalar(u8, porcelain_out, '\n');
    while (lines.next()) |line| {
        if (line.len < 4) continue;
        const xy = line[0..2];
        var raw_path = line[3..];
        if (std.mem.indexOf(u8, raw_path, " -> ")) |arrow_idx| {
            raw_path = raw_path[arrow_idx + 4 ..];
        }
        const path = std.mem.trim(u8, raw_path, " \t\r\"");
        for (wfs, 0..) |*wf, idx| {
            if (idx >= out_statuses.len) break;
            if (wf.isSpecial()) continue;
            if (std.mem.eql(u8, wf.path, path) or
                (path.len > wf.path.len and
                    path[path.len - wf.path.len - 1] == '/' and
                    std.mem.endsWith(u8, path, wf.path)))
            {
                if (xy[0] != ' ' and xy[0] != '?') {
                    out_statuses[idx].staged = true;
                    out_statuses[idx].staged_char = xy[0];
                }
                if (xy[1] != ' ' and xy[1] != '?') {
                    out_statuses[idx].unstaged = true;
                    out_statuses[idx].unstaged_char = xy[1];
                }
                if (xy[0] == '?' and xy[1] == '?') {
                    out_statuses[idx].untracked = true;
                    out_statuses[idx].unstaged_char = '?';
                }
            }
        }
    }
}

/// Parses `git log --name-status` (or `--name-only`) `--pretty=format:'COMMIT|%h|%s|%cr'` output into `out_commits`.
pub fn parseGitLog(log_out: []const u8, wfs: []const SampleFile, out_commits: []GitCommitEntry) usize {
    _ = wfs;
    var count: usize = 0;
    var lines = std.mem.splitScalar(u8, log_out, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r'");
        if (trimmed.len == 0) continue;

        if (std.mem.startsWith(u8, trimmed, "COMMIT|")) {
            if (count >= out_commits.len) break;
            var parts = std.mem.splitScalar(u8, trimmed[7..], '|');
            const h = parts.next() orelse continue;
            const s = parts.next() orelse continue;
            const r = parts.next() orelse "recent";

            var entry = GitCommitEntry{};
            entry.hash_str.set(h);
            entry.subject_str.set(s);
            entry.rel_time_str.set(r);

            out_commits[count] = entry;
            count += 1;
        } else if (count > 0) {
            var commit = &out_commits[count - 1];
            commit.files_changed += 1;
            if (commit.file_count < MaxCommitFiles) {
                var status_char: u8 = 'M';
                var file_path: []const u8 = trimmed;
                if (std.mem.indexOfScalar(u8, trimmed, '\t')) |first_tab| {
                    const status_tok = std.mem.trim(u8, trimmed[0..first_tab], " \t");
                    if (status_tok.len > 0) {
                        status_char = status_tok[0];
                    }
                    const rest = trimmed[first_tab + 1 ..];
                    if (std.mem.lastIndexOfScalar(u8, rest, '\t')) |last_tab| {
                        file_path = std.mem.trim(u8, rest[last_tab + 1 ..], " \t\r\"");
                    } else {
                        file_path = std.mem.trim(u8, rest, " \t\r\"");
                    }
                }
                if (file_path.len > 0) {
                    const f_idx = commit.file_count;
                    commit.files[f_idx].set(file_path);
                    commit.file_statuses[f_idx] = status_char;
                    commit.file_count += 1;
                }
            }
        }
    }
    return count;
}

pub fn queryBranch(out_branch: *platform.InlineString(64)) bool {
    const fp = popen("git rev-parse --abbrev-ref HEAD " ++ stderr_null_redirect, "r") orelse return false;
    defer _ = pclose(fp);
    var out_buf: [128]u8 = undefined;
    const n = std.c.fread(&out_buf, 1, out_buf.len, fp);
    const trimmed = std.mem.trim(u8, out_buf[0..n], " \t\r\n");
    out_branch.set(trimmed);
    return trimmed.len > 0;
}

pub fn queryStatus(wfs: []const SampleFile, out_statuses: []GitFileStatus) bool {
    const fp = popen("git status --porcelain -uall " ++ stderr_null_redirect, "r") orelse return false;
    defer _ = pclose(fp);
    var out_buf: [16384]u8 = undefined;
    var total: usize = 0;
    while (total < out_buf.len) {
        const n = std.c.fread(out_buf[total..].ptr, 1, out_buf.len - total, fp);
        if (n == 0) break;
        total += n;
    }
    parsePorcelainStatus(out_buf[0..total], wfs, out_statuses);
    return true;
}

pub fn queryRecentCommits(wfs: []const SampleFile, out_commits: []GitCommitEntry) ?usize {
    const log_cmd = if (@import("builtin").os.tag == .windows)
        "git log -n 32 --relative --name-status --pretty=format:\"COMMIT|%h|%s|%cr\" 2>NUL"
    else
        "git log -n 32 --relative --name-status --pretty=format:'COMMIT|%h|%s|%cr' 2>/dev/null";
    const fp = popen(log_cmd, "r") orelse return null;
    defer _ = pclose(fp);
    var out_buf: [32768]u8 = undefined;
    var total: usize = 0;
    while (total < out_buf.len) {
        const n = std.c.fread(out_buf[total..].ptr, 1, out_buf.len - total, fp);
        if (n == 0) break;
        total += n;
    }
    if (total == 0) return 0;
    return parseGitLog(out_buf[0..total], wfs, out_commits);
}

/// Non-blocking asynchronous Git status & commit history poller.
/// Uses `platform.SubprocessPoller` to drain output incrementally
/// during `Pass.input` without stalling the UI render thread.
pub const GitStatusPoller = struct {
    poller: platform.SubprocessPoller(65536) = .{},

    pub fn deinit(self: *GitStatusPoller) void {
        self.poller.deinit();
    }

    pub fn isBusy(self: *const GitStatusPoller) bool {
        return self.poller.isBusy();
    }

    pub fn requestRefresh(self: *GitStatusPoller) void {
        const cmd = if (@import("builtin").os.tag == .windows)
            "git --no-optional-locks rev-parse --abbrev-ref HEAD 2>NUL & echo. & echo ---GIT_BRANCH_SEP--- & git --no-optional-locks status --porcelain -uall 2>NUL & echo. & echo ---GIT_LOG_SEP--- & git --no-optional-locks log -n 32 --relative --name-status --pretty=format:\"COMMIT|%h|%s|%cr\" 2>NUL"
        else
            "git --no-optional-locks rev-parse --abbrev-ref HEAD 2>/dev/null; printf '\\n---GIT_BRANCH_SEP---\\n'; git --no-optional-locks status --porcelain -uall; printf '\\n---GIT_LOG_SEP---\\n'; git --no-optional-locks log -n 32 --relative --name-status --pretty=format:'COMMIT|%h|%s|%cr'";
        self.poller.request(cmd);
    }

    /// Polls the non-blocking subprocess poller. Returns `true` when the background `git` command
    /// finishes and `out_statuses` and `out_commits` have been updated.
    pub fn poll(
        self: *GitStatusPoller,
        wfs: []const SampleFile,
        out_branch: ?*platform.InlineString(64),
        out_statuses: []GitFileStatus,
        out_commits: []GitCommitEntry,
        out_commit_count: *usize,
    ) bool {
        const payload = self.poller.poll() orelse return false;

        var remainder = payload;
        if (std.mem.indexOf(u8, remainder, GitBranchSeparator)) |b_idx| {
            if (out_branch) |branch_ptr| {
                const raw_branch = std.mem.trim(u8, remainder[0..b_idx], " \t\r\n");
                branch_ptr.set(raw_branch);
            }
            remainder = remainder[b_idx + GitBranchSeparator.len ..];
        }

        if (std.mem.indexOf(u8, remainder, GitLogSeparator)) |sep_idx| {
            const porcelain_part = remainder[0..sep_idx];
            const log_part = remainder[sep_idx + GitLogSeparator.len ..];
            parsePorcelainStatus(porcelain_part, wfs, out_statuses);
            out_commit_count.* = parseGitLog(log_part, wfs, out_commits);
        } else {
            parsePorcelainStatus(remainder, wfs, out_statuses);
        }
        return true;
    }
};

test "git_client: parsePorcelainStatus and parseGitLog" {
    const files = [_]SampleFile{
        .{ .name = "main.zig", .path = "src/app/main.zig", .folder = "src/app", .initial_source = "" },
        .{ .name = "root.zig", .path = "src/ui/root.zig", .folder = "src/ui", .initial_source = "" },
    };
    const porcelain =
        "M  src/app/main.zig\n" ++
        " M src/ui/root.zig\n";
    var statuses: [2]GitFileStatus = @splat(.{});
    parsePorcelainStatus(porcelain, &files, &statuses);
    try std.testing.expect(statuses[0].staged);
    try std.testing.expect(!statuses[0].unstaged);
    try std.testing.expect(!statuses[1].staged);
    try std.testing.expect(statuses[1].unstaged);

    const log_sample =
        "COMMIT|a1b2c3d|Refactor UI widgets|2 hours ago\n" ++
        "M\tsrc/app/main.zig\n" ++
        "A\tsrc/ui/root.zig\n";
    var commits: [4]GitCommitEntry = undefined;
    const n = parseGitLog(log_sample, &files, &commits);
    try std.testing.expectEqual(@as(usize, 1), n);
    try std.testing.expectEqualStrings("a1b2c3d", commits[0].hash());
    try std.testing.expectEqualStrings("Refactor UI widgets", commits[0].subject());
    try std.testing.expectEqualStrings("2 hours ago", commits[0].relTime());
    try std.testing.expectEqual(@as(u16, 2), commits[0].files_changed);
    try std.testing.expectEqual(@as(u8, 2), commits[0].file_count);
    try std.testing.expectEqualStrings("src/app/main.zig", commits[0].files[0].slice());
    try std.testing.expectEqual(@as(u8, 'M'), commits[0].file_statuses[0]);
    try std.testing.expectEqualStrings("src/ui/root.zig", commits[0].files[1].slice());
    try std.testing.expectEqual(@as(u8, 'A'), commits[0].file_statuses[1]);
}

test "git_client: GitStatusPoller non-blocking requestRefresh and poll" {
    var poller = GitStatusPoller{};
    defer poller.deinit();

    var statuses: [workspace_defaults.WORKSPACE_FILES.len]GitFileStatus = @splat(.{});
    var commits: [6]GitCommitEntry = @splat(.{});
    var commit_count: usize = 0;

    poller.requestRefresh();
    try std.testing.expect(poller.isBusy());

    // First immediate poll should return without blocking (false while child is still executing)
    _ = poller.poll(&workspace_defaults.WORKSPACE_FILES, null, &statuses, &commits, &commit_count);
}
