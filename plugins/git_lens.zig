//! Native Zig `.dylib` Editor Plugin: Git Source Control & Diff Lens (`plugins/git_lens.zig`).
//!
//! Features:
//!   - Dedicated Activity Bar Source Control view (`.sidebar_icon = .git`).
//!   - Queries shared host Git status, branch, and commit history via `ctx.getGitStatus()`.
//!   - Dispatches Git working-tree actions via host `ctx.gitAction(...)` (zero duplicate subprocesses).
//!   - Interactive Staging (`+`), Unstaging (`-`, `Unstage All`), Discard (`↺`), and Multiline Commit input.
//!   - Collapsible `STAGED CHANGES`, `CHANGES`, `COMMITS` history tree, and `BLAME & DIFF LENS` inspector.
//!   - Status bar blame badge showing the author & short commit hash of the current line.

const std = @import("std");
const sdk = @import("plugin_sdk");

const popen = sdk.fs_util.popen;
const pclose = sdk.fs_util.pclose;

const GitLensState = struct {
    initialized: bool = false,
    git_installed: bool = false,

    // Collapsible section states
    sec_staged: bool = true,
    sec_changes: bool = true,
    sec_commits: bool = true,
    sec_blame: bool = true,

    // Deferred stage-all confirmation & action state (preserves Pass.input == Pass.paint layout determinism)
    confirm_stage_all: bool = false,
    next_confirm_stage_all: bool = false,
    pending_stage_all_toggle: bool = false,
    has_pending_action: bool = false,
    pending_action: sdk.GitAction = .refresh,
    pending_action_arg: sdk.InlineString(512) = .{},
    pending_save_dirty: bool = false,
    pending_reload_disk: bool = false,
    pending_stage_all_before_commit: bool = false,

    // Source Control UI state (actual files & commits are streamed directly from host snapshot)
    branch: sdk.InlineString(64) = .{},
    commit_msg: sdk.InlineString(512) = .{},
    expanded_commits: [64]u64 = @splat(0),
    expanded_commit_count: u8 = 0,

    // Blame & Diff Lens state
    last_queried_line: u32 = 0,
    commit_sha: sdk.InlineString(16) = .{},
    author: sdk.InlineString(64) = .{},
    summary: sdk.InlineString(128) = .{},
    diff_hunk: sdk.InlineString(512) = .{},
    last_status: sdk.InlineString(128) = .{},

    fn isCommitExpanded(self: *const GitLensState, commit_hash: []const u8) bool {
        const h = std.hash.Fnv1a_64.hash(commit_hash);
        for (self.expanded_commits[0..self.expanded_commit_count]) |eh| {
            if (eh == h) return true;
        }
        return false;
    }

    fn setCommitExpanded(self: *GitLensState, commit_hash: []const u8, expanded: bool) void {
        const h = std.hash.Fnv1a_64.hash(commit_hash);
        for (self.expanded_commits[0..self.expanded_commit_count], 0..) |eh, idx| {
            if (eh == h) {
                if (!expanded) {
                    var j = idx;
                    while (j + 1 < self.expanded_commit_count) : (j += 1) {
                        self.expanded_commits[j] = self.expanded_commits[j + 1];
                    }
                    self.expanded_commit_count -= 1;
                }
                return;
            }
        }
        if (expanded and self.expanded_commit_count < self.expanded_commits.len) {
            self.expanded_commits[self.expanded_commit_count] = h;
            self.expanded_commit_count += 1;
        }
    }

    fn queueAction(
        self: *GitLensState,
        ctx: *sdk.PluginContext,
        action: sdk.GitAction,
        arg: []const u8,
        save_dirty: bool,
        reload_disk: bool,
    ) void {
        self.has_pending_action = true;
        self.pending_action = action;
        self.pending_action_arg.set(arg);
        self.pending_save_dirty = save_dirty;
        self.pending_reload_disk = reload_disk;
        self.pending_stage_all_before_commit = false;
        ctx.requestContinuousRedraw();
    }
};

comptime {
    std.debug.assert(@sizeOf(GitLensState) <= 8192);
}

const stderr_null_redirect = if (@import("builtin").os.tag == .windows) "2>NUL" else "2>/dev/null";

fn probeBinary(name: []const u8) bool {
    var cmd_buf: [128]u8 = undefined;
    const probe_fmt = if (@import("builtin").os.tag == .windows)
        "where {s} >NUL 2>&1\x00"
    else
        "command -v {s} >/dev/null 2>&1\x00";
    const cmd = std.fmt.bufPrint(&cmd_buf, probe_fmt, .{name}) catch return false;
    const fp = popen(@ptrCast(cmd.ptr), "r") orelse return false;
    var drain: [128]u8 = undefined;
    while (std.c.fread(&drain, 1, drain.len, fp) > 0) {}
    return pclose(fp) == 0;
}

fn syncBranchFromHost(ctx: *sdk.PluginContext, st: *GitLensState) void {
    var snap: sdk.GitStatusSnapshot = .{};
    if (ctx.getGitStatus(&snap)) {
        st.branch.set(snap.branch.toZig());
    }
}

fn ensureInitialized(ctx: *sdk.PluginContext, state: *GitLensState) void {
    if (state.initialized) return;
    state.initialized = true;
    state.git_installed = probeBinary("git");
    state.sec_staged = true;
    state.sec_changes = true;
    state.sec_commits = true;
    state.sec_blame = true;
    syncBranchFromHost(ctx, state);
    if (ctx.activeBuffer()) |buf| {
        queryGitBlame(state, buf.file_path, @intCast(buf.cursor_line + 1));
    }
}

fn queryGitBlame(state: *GitLensState, file_path: []const u8, line_1based: u32) void {
    state.last_queried_line = line_1based;
    if (!state.git_installed or file_path.len == 0) return;

    var cmd_buf: [384]u8 = undefined;
    const cmd_slice = std.fmt.bufPrint(
        &cmd_buf,
        "git blame --porcelain -L{d},{d} -- \"{s}\" " ++ stderr_null_redirect ++ "\x00",
        .{ line_1based, line_1based, file_path },
    ) catch return;

    var out_buf: [1024]u8 = undefined;
    var out_len: usize = 0;
    if (popen(@ptrCast(cmd_slice.ptr), "r")) |fp| {
        defer _ = pclose(fp);
        while (out_len < out_buf.len) {
            const n = std.c.fread(out_buf[out_len..].ptr, 1, out_buf.len - out_len, fp);
            if (n == 0) break;
            out_len += n;
        }
    }
    if (out_len == 0) return;

    const output = out_buf[0..out_len];
    var lines = std.mem.splitScalar(u8, output, '\n');
    if (lines.next()) |first_line| {
        if (first_line.len >= 8) {
            state.commit_sha.set(first_line[0..8]);
        }
    }
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "author ")) {
            state.author.set(line["author ".len..]);
        } else if (std.mem.startsWith(u8, line, "summary ")) {
            state.summary.set(line["summary ".len..]);
        }
    }
}

fn queryGitDiff(state: *GitLensState, file_path: []const u8) void {
    if (!state.git_installed or file_path.len == 0) return;
    var cmd_buf: [320]u8 = undefined;
    const cmd_slice = std.fmt.bufPrint(&cmd_buf, "git diff -U2 -- \"{s}\" " ++ stderr_null_redirect ++ "\x00", .{file_path}) catch return;

    var diff_buf: [512]u8 = undefined;
    var out_len: usize = 0;
    if (popen(@ptrCast(cmd_slice.ptr), "r")) |fp| {
        defer _ = pclose(fp);
        while (out_len < diff_buf.len) {
            const n = std.c.fread(diff_buf[out_len..].ptr, 1, diff_buf.len - out_len, fp);
            if (n == 0) break;
            out_len += n;
        }
    }
    state.diff_hunk.set(diff_buf[0..out_len]);
}

fn splitFolderAndBasename(rel_path: []const u8) struct { folder: []const u8, name: []const u8 } {
    if (std.mem.lastIndexOfScalar(u8, rel_path, '/')) |slash_idx| {
        return .{
            .folder = if (slash_idx == 0) "." else rel_path[0..slash_idx],
            .name = rel_path[slash_idx + 1 ..],
        };
    }
    return .{ .folder = ".", .name = rel_path };
}

fn fileIconText(name: []const u8) []const u8 {
    const ext = std.fs.path.extension(name);
    if (ext.len <= 1) return "·";
    const raw = ext[1..];
    if (std.mem.eql(u8, raw, "json")) return "{}";
    if (std.mem.eql(u8, raw, "sh") or std.mem.eql(u8, raw, "zsh") or std.mem.eql(u8, raw, "bash")) return "$";
    return raw[0..@min(raw.len, 2)];
}

fn isPathActive(active_path: []const u8, rel_path: []const u8) bool {
    if (active_path.len == 0 or rel_path.len == 0) return false;
    if (std.mem.eql(u8, active_path, rel_path)) return true;
    if (active_path.len > rel_path.len and
        active_path[active_path.len - rel_path.len - 1] == '/' and
        std.mem.endsWith(u8, active_path, rel_path))
    {
        return true;
    }
    return false;
}

fn executePendingAction(ctx: *sdk.PluginContext, st: *GitLensState) void {
    if (st.pending_save_dirty) {
        ctx.syncWorkspaceGit(true, false);
    }
    if (st.pending_stage_all_before_commit) {
        _ = ctx.gitAction(.stage_all, "");
    }
    if (st.pending_action == .commit) {
        const msg = std.mem.trim(u8, st.pending_action_arg.slice(), " \t\r\n");
        if (msg.len == 0) {
            ctx.setStatusNotice("Git: Enter a commit message first");
            return;
        }
        if (ctx.gitAction(.commit, msg)) {
            st.commit_msg.clear();
            st.diff_hunk.clear();
            syncBranchFromHost(ctx, st);
            if (ctx.activeBuffer()) |buf| {
                queryGitBlame(st, buf.file_path, @intCast(buf.cursor_line + 1));
            }
            const br = st.branch.slice();
            if (br.len > 0) {
                ctx.setStatusNotice(ctx.fmt("Committed changes on {s}", .{br}));
            } else {
                ctx.setStatusNotice("Committed changes");
            }
        } else {
            ctx.setStatusNotice("Git commit failed");
        }
        ctx.syncWorkspaceGit(false, false);
    } else {
        _ = ctx.gitAction(st.pending_action, st.pending_action_arg.slice());
        syncBranchFromHost(ctx, st);
        ctx.syncWorkspaceGit(false, st.pending_reload_disk);
    }
}

fn handleCommitRequest(ctx: *sdk.PluginContext, st: *GitLensState, staged_count: usize, unstaged_count: usize) void {
    const msg = std.mem.trim(u8, st.commit_msg.slice(), " \t\r\n");
    if (msg.len == 0) {
        ctx.setStatusNotice("Git: Enter a commit message before committing");
        return;
    }
    if (staged_count > 0) {
        st.next_confirm_stage_all = false;
        st.pending_stage_all_toggle = true;
        st.queueAction(ctx, .commit, msg, false, false);
    } else if (unstaged_count > 0) {
        st.next_confirm_stage_all = true;
        st.pending_stage_all_toggle = true;
        ctx.requestContinuousRedraw();
    } else {
        ctx.setStatusNotice("Git: Working tree clean — nothing to commit");
    }
}

fn registerCommands(ctx: *sdk.PluginContext) void {
    ctx.registerCommand(
        "git_lens.blame_line",
        "Git: Blame Active Cursor Line",
        "Git & Version Control",
        "Blame",
    );
    ctx.registerCommand(
        "git_lens.diff_file",
        "Git: Refresh File Diff Hunk Preview",
        "Git & Version Control",
        "Diff",
    );
    ctx.registerCommand(
        "git_lens.stage_active_file",
        "Git: Stage Active File",
        "Git & Version Control",
        "+",
    );
    ctx.registerCommand(
        "git_lens.unstage_all",
        "Git: Unstage All Staged Changes",
        "Git & Version Control",
        "-",
    );
    ctx.registerCommand(
        "git_lens.refresh_status",
        "Git: Refresh Source Control Status",
        "Git & Version Control",
        "↺",
    );
}

fn onInit(ctx: *sdk.PluginContext) void {
    registerCommands(ctx);
    const st = ctx.useState(GitLensState, "state", .{});
    ensureInitialized(ctx, st);
}

fn onDeinit(_: *sdk.PluginContext) void {}

fn onBeforeReload(_: *sdk.PluginContext) void {}

fn onReload(ctx: *sdk.PluginContext) void {
    registerCommands(ctx);
    const st = ctx.useState(GitLensState, "state", .{});
    ensureInitialized(ctx, st);
    syncBranchFromHost(ctx, st);
}

fn onBufferSave(ctx: *sdk.PluginContext, buf: sdk.BufferInfo) void {
    const st = ctx.useState(GitLensState, "state", .{});
    ensureInitialized(ctx, st);
    queryGitBlame(st, buf.file_path, @intCast(buf.cursor_line + 1));
    queryGitDiff(st, buf.file_path);
    _ = ctx.gitAction(.refresh, "");
    syncBranchFromHost(ctx, st);
}

fn onPollIo(ctx: *sdk.PluginContext) void {
    const st = ctx.useState(GitLensState, "state", .{});
    ensureInitialized(ctx, st);
    if (st.branch.len == 0) {
        syncBranchFromHost(ctx, st);
    }
}

fn onCommand(ctx: *sdk.PluginContext, cmd_id: []const u8) void {
    const st = ctx.useState(GitLensState, "state", .{});
    ensureInitialized(ctx, st);

    if (std.mem.eql(u8, cmd_id, "git_lens.blame_line")) {
        if (ctx.activeBuffer()) |buf| {
            const line_1based: u32 = @intCast(buf.cursor_line + 1);
            queryGitBlame(st, buf.file_path, line_1based);
            const msg = ctx.fmt(
                "Git Blame L{d}: [{s}] {s} — {s}",
                .{ line_1based, st.commit_sha.slice(), st.author.slice(), st.summary.slice() },
            );
            st.last_status.set(msg);
            ctx.setStatusNotice(msg);
        }
    } else if (std.mem.eql(u8, cmd_id, "git_lens.diff_file")) {
        if (ctx.activeBuffer()) |buf| {
            queryGitDiff(st, buf.file_path);
            const msg = ctx.fmt("Git Diff refreshed ({d} bytes)", .{st.diff_hunk.len});
            st.last_status.set(msg);
            ctx.setStatusNotice(msg);
        }
    } else if (std.mem.eql(u8, cmd_id, "git_lens.stage_active_file")) {
        if (ctx.activeBuffer()) |buf| {
            if (buf.file_path.len > 0) {
                ctx.syncWorkspaceGit(true, false);
                _ = ctx.gitAction(.stage_path, buf.file_path);
                syncBranchFromHost(ctx, st);
                ctx.syncWorkspaceGit(false, false);
                ctx.setStatusNotice(ctx.fmt("Staged active file: {s}", .{buf.file_path}));
            }
        }
    } else if (std.mem.eql(u8, cmd_id, "git_lens.unstage_all")) {
        _ = ctx.gitAction(.unstage_all, "");
        syncBranchFromHost(ctx, st);
        ctx.syncWorkspaceGit(false, false);
        ctx.setStatusNotice("Unstaged all changes");
    } else if (std.mem.eql(u8, cmd_id, "git_lens.refresh_status")) {
        _ = ctx.gitAction(.refresh, "");
        syncBranchFromHost(ctx, st);
        ctx.syncWorkspaceGit(false, false);
        ctx.setStatusNotice("Refreshed Git status");
    }
}

fn renderStatusBar(ctx: *sdk.PluginContext) void {
    const st = ctx.useState(GitLensState, "state", .{});
    ensureInitialized(ctx, st);
    const sha = if (st.commit_sha.len > 0) st.commit_sha.slice() else st.branch.slice();
    const label = if (st.author.len > 0)
        ctx.fmt("git {s} ({s})##git_lens_chip", .{ sha, st.author.slice() })
    else if (sha.len > 0)
        ctx.fmt("git {s}##git_lens_chip", .{sha})
    else
        "git##git_lens_chip";
    if (ctx.ui.chip(label, false)) {
        onCommand(ctx, "git_lens.blame_line");
    }
}

fn renderSidebar(ctx: *sdk.PluginContext) void {
    const st = ctx.useState(GitLensState, "state", .{});
    ensureInitialized(ctx, st);

    if (ctx.ui.isInputPass()) {
        if (st.pending_stage_all_toggle) {
            st.confirm_stage_all = st.next_confirm_stage_all;
            st.pending_stage_all_toggle = false;
        }
        if (st.has_pending_action) {
            st.has_pending_action = false;
            executePendingAction(ctx, st);
        }
    }

    var snap: sdk.GitStatusSnapshot = .{};
    _ = ctx.getGitStatus(&snap);
    if (snap.branch.len > 0) {
        st.branch.set(snap.branch.toZig());
    }

    var staged_count: usize = 0;
    var unstaged_count: usize = 0;
    if (snap.files_ptr) |files_ptr| {
        for (0..snap.file_count) |i| {
            const f = files_ptr[i];
            if (f.staged) staged_count += 1;
            if (f.unstaged or f.untracked) unstaged_count += 1;
        }
    }

    const active_path = if (ctx.activeBuffer()) |b| b.file_path else "";
    const branch_name = st.branch.slice();

    // 1. Source Control Header
    if (branch_name.len > 0) {
        ctx.ui.label(ctx.fmt("SOURCE CONTROL · {s}", .{branch_name}));
    } else {
        ctx.ui.label("SOURCE CONTROL");
    }
    ctx.ui.spacer(0, 2);

    // 2. Multiline Commit Message Input & Single Commit Button
    const commit_tf = ctx.ui.textAreaInline(
        "##vc_commit_input",
        &st.commit_msg,
        "Message (Cmd+Enter to commit)...",
        64.0,
    );
    if (commit_tf.submitted) {
        handleCommitRequest(ctx, st, staged_count, unstaged_count);
    }

    const commit_label = if (staged_count > 0)
        ctx.fmt("Commit ({d} Staged)##vc_commit_btn", .{staged_count})
    else
        "Commit##vc_commit_btn";

    if (ctx.ui.button(commit_label, 0, 26)) {
        handleCommitRequest(ctx, st, staged_count, unstaged_count);
    }

    // Inline Stage-All Confirmation Prompt (when Commit pressed with 0 staged & >0 unstaged changes)
    if (st.confirm_stage_all) {
        ctx.ui.spacer(0, 2);
        ctx.ui.label(ctx.fmt("Stage all {d} modified file(s) and commit?", .{unstaged_count}));
        if (ctx.ui.button("Yes (Stage All & Commit)##vc_prompt_yes", 0, 24)) {
            st.next_confirm_stage_all = false;
            st.pending_stage_all_toggle = true;
            const msg = std.mem.trim(u8, st.commit_msg.slice(), " \t\r\n");
            st.queueAction(ctx, .commit, msg, true, false);
            st.pending_stage_all_before_commit = true;
        }
        if (ctx.ui.button("Cancel##vc_prompt_cancel", 0, 24)) {
            st.next_confirm_stage_all = false;
            st.pending_stage_all_toggle = true;
            ctx.requestContinuousRedraw();
        }
        ctx.ui.spacer(0, 2);
    }

    // 3. Collapsible STAGED CHANGES Section
    const staged_badge = ctx.fmt("{d}", .{staged_count});
    const staged_sec = ctx.ui.collapsibleSectionWithAction(
        "STAGED CHANGES##sec_vc_staged",
        &st.sec_staged,
        staged_badge,
        "−",
    );
    if (staged_sec.action_clicked and staged_count > 0) {
        st.queueAction(ctx, .unstage_all, "", false, false);
    }
    if (staged_sec.expanded) {
        if (staged_count == 0) {
            ctx.ui.label("No staged changes.");
        } else if (snap.files_ptr) |files_ptr| {
            var s_idx: usize = 0;
            for (0..snap.file_count) |i| {
                const f = files_ptr[i];
                if (!f.staged) continue;
                const rel_path = f.path.toZig();
                const parts = splitFolderAndBasename(rel_path);
                const status_char: u8 = if (f.status != 0) f.status else 'M';
                const meta_str = if (!std.mem.eql(u8, parts.folder, "."))
                    ctx.fmt("{s} {c}", .{ parts.folder, status_char })
                else
                    ctx.fmt("{c}", .{status_char});

                const res = ctx.ui.listItemEx(.{
                    .label = ctx.fmt("{s}##vc_staged_{d}", .{ parts.name, s_idx }),
                    .meta = meta_str,
                    .accent = .staged_green,
                    .icon_text = fileIconText(parts.name),
                    .selected = isPathActive(active_path, rel_path),
                    .action_label = "-",
                    .secondary_action_label = "↗",
                });
                if (res.action_clicked) {
                    st.queueAction(ctx, .unstage_path, rel_path, false, false);
                } else if (res.secondary_action_clicked) {
                    _ = ctx.openFilePath(rel_path);
                } else if (res.clicked) {
                    ctx.openGitDiff(rel_path, "", true, false);
                }
                s_idx += 1;
            }

            if (ctx.ui.chip("Unstage All##vc_unstage_all", false)) {
                st.queueAction(ctx, .unstage_all, "", false, false);
            }
        }
    }

    // 4. Collapsible CHANGES Section (Clean Flat List + Manual Refresh `↺`)
    const changes_badge = ctx.fmt("{d}", .{unstaged_count});
    const chg_sec = ctx.ui.collapsibleSectionWithAction(
        "CHANGES##sec_vc_changes",
        &st.sec_changes,
        changes_badge,
        "↺",
    );
    if (chg_sec.action_clicked) {
        st.queueAction(ctx, .refresh, "", false, false);
    }
    if (chg_sec.expanded) {
        if (unstaged_count == 0) {
            ctx.ui.label("Working tree clean.");
        } else if (snap.files_ptr) |files_ptr| {
            var u_idx: usize = 0;
            for (0..snap.file_count) |i| {
                const f = files_ptr[i];
                if (!f.unstaged and !f.untracked) continue;
                const rel_path = f.path.toZig();
                const parts = splitFolderAndBasename(rel_path);
                const status_char: u8 = if (f.untracked) '?' else if (f.status != 0) f.status else 'M';
                const meta_str = if (!std.mem.eql(u8, parts.folder, "."))
                    ctx.fmt("{s} {c}", .{ parts.folder, status_char })
                else
                    ctx.fmt("{c}", .{status_char});

                const res = ctx.ui.listItemEx(.{
                    .label = ctx.fmt("{s}##vc_chg_{d}", .{ parts.name, u_idx }),
                    .meta = meta_str,
                    .accent = .modified_amber,
                    .icon_text = fileIconText(parts.name),
                    .selected = isPathActive(active_path, rel_path),
                    .action_label = "+",
                    .secondary_action_label = "↺",
                });
                if (res.action_clicked) {
                    st.queueAction(ctx, .stage_path, rel_path, true, false);
                } else if (res.secondary_action_clicked) {
                    st.queueAction(ctx, .discard_path, rel_path, false, true);
                } else if (res.clicked) {
                    ctx.openGitDiff(rel_path, "", false, false);
                }
                u_idx += 1;
            }
        }
    }

    // 5. Collapsible COMMITS History Tree
    const commits_badge = ctx.fmt("{d}", .{snap.commit_count});
    if (ctx.ui.collapsibleSection("COMMITS##sec_vc_commits", &st.sec_commits, commits_badge)) {
        if (snap.commit_count == 0 or snap.commits_ptr == null) {
            ctx.ui.label("No commit history found.");
        } else if (snap.commits_ptr) |commits_ptr| {
            for (0..snap.commit_count) |c_idx| {
                const commit = commits_ptr[c_idx];
                const c_hash = commit.hash.toZig();
                const c_subj = commit.subject.toZig();
                const c_rel_time = commit.rel_time.toZig();
                const node_label = ctx.fmt("{s}  {s}##vc_commit_{d}", .{
                    c_hash,
                    c_subj,
                    c_idx,
                });
                const selected = (st.commit_sha.len > 0 and std.mem.startsWith(u8, st.commit_sha.slice(), c_hash));
                var is_expanded = st.isCommitExpanded(c_hash);
                if (ctx.ui.treeFolderNode(node_label, 0, &is_expanded, c_rel_time)) {
                    st.setCommitExpanded(c_hash, true);
                    if (commit.file_count == 0 or commit.files_ptr == null) {
                        ctx.ui.label("   No modified files in commit.");
                    } else if (commit.files_ptr) |c_files_ptr| {
                        for (0..commit.file_count) |f_idx| {
                            const cf = c_files_ptr[f_idx];
                            const rel_path = cf.path.toZig();
                            const status_char: u8 = if (cf.status != 0) cf.status else 'M';
                            const parts = splitFolderAndBasename(rel_path);
                            const meta_str = if (!std.mem.eql(u8, parts.folder, "."))
                                ctx.fmt("{s} {c}", .{ parts.folder, status_char })
                            else
                                ctx.fmt("{c}", .{status_char});

                            const res = ctx.ui.listItemEx(.{
                                .label = ctx.fmt("{s}##vc_cfile_{d}_{d}", .{ parts.name, c_idx, f_idx }),
                                .meta = meta_str,
                                .accent = if (status_char == 'A') .staged_green else .modified_amber,
                                .icon_text = fileIconText(parts.name),
                                .selected = isPathActive(active_path, rel_path),
                                .indent_level = 1,
                                .action_label = "↗",
                            });
                            if (res.action_clicked) {
                                _ = ctx.openFilePath(rel_path);
                            } else if (res.clicked) {
                                ctx.openGitDiff(rel_path, c_hash, false, false);
                            }
                        }
                        if (commit.files_changed > commit.file_count) {
                            ctx.ui.label(ctx.fmt("   +{d} more file(s)...", .{commit.files_changed - commit.file_count}));
                        }
                    }
                } else {
                    st.setCommitExpanded(c_hash, false);
                }
                if (selected and !is_expanded) {
                    ctx.ui.label(ctx.fmt("   {s}", .{c_subj}));
                }
            }
        }
    }

    // 6. Collapsible BLAME & DIFF LENS Inspector
    if (ctx.ui.collapsibleSection("BLAME & DIFF LENS##sec_vc_blame", &st.sec_blame, "")) {
        if (st.last_status.len > 0) {
            ctx.ui.monoLabel(st.last_status.slice());
            ctx.ui.spacer(0, 4);
        }

        ctx.ui.label(ctx.fmt("Commit: {s}", .{st.commit_sha.slice()}));
        ctx.ui.label(ctx.fmt("Author: {s}", .{st.author.slice()}));
        ctx.ui.monoLabel(ctx.fmt("\"{s}\"", .{st.summary.slice()}));

        if (st.diff_hunk.len > 0) {
            ctx.ui.spacer(0, 4);
            ctx.ui.label("HUNK PREVIEW");
            ctx.ui.monoLabel(st.diff_hunk.slice());
        }

        ctx.ui.spacer(0, 4);
        if (ctx.ui.button("Open Side-by-Side Diff##vc_open_diff_btn", 0, 24)) {
            if (active_path.len > 0) {
                ctx.openGitDiff(active_path, st.commit_sha.slice(), false, true);
            }
        }
    }
}

comptime {
    sdk.exportEditorPlugin(.{
        .id = "builtin.git_lens",
        .display_name = "Git Source Control & Lens",
        .version = "0.1.0",
        .sidebar_title = "SOURCE CONTROL",
        .sidebar_icon = .git,
        .init = &onInit,
        .before_reload = &onBeforeReload,
        .on_reload = &onReload,
        .deinit = &onDeinit,
        .on_poll_io = &onPollIo,
        .on_command = &onCommand,
        .on_buffer_save = &onBufferSave,
        .render_sidebar = &renderSidebar,
        .render_status_bar = &renderStatusBar,
    });
}
