//! Antigravity Local Socket Agent Client (`src/app/agy_client.zig`).
//!
//! Communicates directly with the local Antigravity Language Server / Hub (`127.0.0.1:<port>`)
//! over non-blocking HTTP/1.1 JSON RPC (`exa.language_server_pb.LanguageServerService`):
//!   - Auto-discovers the running `language_server` / `agy --hub` loopback port and `--csrf_token`
//!     (or spawns `agy --hub` in the background if no hub is running).
//!   - Queries `/GetCascadeModelConfigData` to discover the default model and available model list.
//!   - Starts conversations via `/StartCascade` (`CORTEX_TRAJECTORY_SOURCE_CASCADE_CLIENT`).
//!   - Sends user prompts via `/SendUserCascadeMessage` with `cascadeConfig.plannerConfig`.
//!   - Streams live trajectory steps, tool calls, and token usage via `/GetCascadeTrajectory`.
//!   - Cancels active turns cleanly via `/CancelCascadeInvocation` without killing the daemon.

const std = @import("std");
const builtin = @import("builtin");
const platform = @import("platform");

const is_windows = (builtin.os.tag == .windows);
const popen = platform.fs_util.popen;
const pclose = platform.fs_util.pclose;
const getcwd = platform.fs_util.getcwd;
extern "c" fn fgets(s: [*]u8, n: c_int, stream: *std.c.FILE) ?[*]u8;

const posix_net = if (!is_windows) struct {
    pub const AF_INET: c_int = 2;
    pub const SOCK_STREAM: c_int = 1;
    pub const F_GETFL: c_int = 3;
    pub const F_SETFL: c_int = 4;
    pub const O_NONBLOCK: c_int = if (builtin.os.tag == .linux) 0x0800 else 0x0004;
    pub const SOL_SOCKET: c_int = 0xffff;
    pub const SO_NOSIGPIPE: c_int = 0x1022;

    pub const sockaddr_in = if (builtin.os.tag == .linux) extern struct {
        sin_family: u16 = AF_INET,
        sin_port: u16,
        sin_addr: u32,
        sin_zero: [8]u8 = @splat(0),
    } else extern struct {
        sin_len: u8 = @sizeOf(sockaddr_in),
        sin_family: u8 = AF_INET,
        sin_port: u16,
        sin_addr: u32,
        sin_zero: [8]u8 = @splat(0),
    };

    extern "c" fn socket(domain: c_int, sock_type: c_int, protocol: c_int) c_int;
    extern "c" fn connect(sockfd: c_int, addr: *const sockaddr_in, addrlen: u32) c_int;
    extern "c" fn setsockopt(sockfd: c_int, level: c_int, optname: c_int, optval: *const anyopaque, optlen: u32) c_int;
    extern "c" fn chmod(path: [*:0]const u8, mode: c_uint) c_int;
} else struct {
    pub const AF_INET: c_int = 2;
    pub const SOCK_STREAM: c_int = 1;
    pub const FIONBIO: c_ulong = 0x8004667E;
    pub const WSAEWOULDBLOCK: c_int = 10035;
    pub const WSAEINPROGRESS: c_int = 10036;
    pub const WSAEALREADY: c_int = 10037;
    pub const WSAENOTCONN: c_int = 10057;

    pub const WSADATA = extern struct {
        wVersion: u16 = 0,
        wHighVersion: u16 = 0,
        iMaxSockets: u16 = 0,
        iMaxUdpDg: u16 = 0,
        lpVendorInfo: ?*u8 = null,
        szDescription: [257]u8 = @splat(0),
        szSystemStatus: [129]u8 = @splat(0),
    };

    pub const sockaddr_in = extern struct {
        sin_family: i16 = AF_INET,
        sin_port: u16,
        sin_addr: u32,
        sin_zero: [8]u8 = @splat(0),
    };

    var wsa_initialized: bool = false;

    extern "ws2_32" fn WSAStartup(wVersionRequested: u16, lpWSAData: *WSADATA) callconv(.c) c_int;
    extern "ws2_32" fn WSAGetLastError() callconv(.c) c_int;
    extern "ws2_32" fn socket(af: c_int, sock_type: c_int, protocol: c_int) callconv(.c) usize;
    extern "ws2_32" fn connect(s: usize, name: *const sockaddr_in, namelen: c_int) callconv(.c) c_int;
    extern "ws2_32" fn ioctlsocket(s: usize, cmd: c_long, argp: *c_ulong) callconv(.c) c_int;
    extern "ws2_32" fn send(s: usize, buf: [*]const u8, len: c_int, flags: c_int) callconv(.c) c_int;
    extern "ws2_32" fn recv(s: usize, buf: [*]u8, len: c_int, flags: c_int) callconv(.c) c_int;
    extern "ws2_32" fn closesocket(s: usize) callconv(.c) c_int;
};

fn openLoopbackSocket(port: u16) c_int {
    if (comptime is_windows) {
        if (!posix_net.wsa_initialized) {
            var wsa: posix_net.WSADATA = .{};
            if (posix_net.WSAStartup(0x0202, &wsa) == 0) {
                posix_net.wsa_initialized = true;
            }
        }
        const s = posix_net.socket(posix_net.AF_INET, posix_net.SOCK_STREAM, 0);
        if (s == ~@as(usize, 0)) return -1;
        var nonblock: c_ulong = 1;
        _ = posix_net.ioctlsocket(s, @bitCast(posix_net.FIONBIO), &nonblock);
        const addr = posix_net.sockaddr_in{
            .sin_port = std.mem.nativeToBig(u16, port),
            .sin_addr = std.mem.nativeToBig(u32, 0x7f000001),
        };
        _ = posix_net.connect(s, &addr, @sizeOf(posix_net.sockaddr_in));
        return @intCast(s);
    } else {
        const fd = posix_net.socket(posix_net.AF_INET, posix_net.SOCK_STREAM, 0);
        if (fd < 0) return -1;
        var one: c_int = 1;
        _ = posix_net.setsockopt(fd, posix_net.SOL_SOCKET, posix_net.SO_NOSIGPIPE, &one, @sizeOf(c_int));
        const flags = std.c.fcntl(fd, posix_net.F_GETFL, @as(c_int, 0));
        if (flags >= 0) {
            _ = std.c.fcntl(fd, posix_net.F_SETFL, flags | posix_net.O_NONBLOCK);
        }
        const addr = posix_net.sockaddr_in{
            .sin_port = std.mem.nativeToBig(u16, port),
            .sin_addr = std.mem.nativeToBig(u32, 0x7f000001),
        };
        _ = posix_net.connect(fd, &addr, @sizeOf(posix_net.sockaddr_in));
        return fd;
    }
}

fn writeLoopbackSocket(fd: c_int, ptr: [*]const u8, len: usize) isize {
    if (comptime is_windows) {
        const n = posix_net.send(@intCast(fd), ptr, @intCast(@min(len, 65536)), 0);
        if (n < 0) return -1;
        return @intCast(n);
    } else {
        return std.c.write(fd, ptr, len);
    }
}

fn readLoopbackSocket(fd: c_int, ptr: [*]u8, len: usize) isize {
    if (comptime is_windows) {
        const n = posix_net.recv(@intCast(fd), ptr, @intCast(@min(len, 65536)), 0);
        if (n < 0) {
            const err = posix_net.WSAGetLastError();
            if (err == posix_net.WSAEWOULDBLOCK or
                err == posix_net.WSAEINPROGRESS or
                err == posix_net.WSAEALREADY or
                err == posix_net.WSAENOTCONN)
            {
                return -1;
            }
            return 0; // Non-wouldblock error treated as EOF
        }
        return @intCast(n);
    } else {
        return std.c.read(fd, ptr, len);
    }
}

fn closeLoopbackSocket(fd: c_int) void {
    if (comptime is_windows) {
        _ = posix_net.closesocket(@intCast(fd));
    } else {
        _ = std.c.close(fd);
    }
}

pub const AgyMode = enum(u8) {
    auto = 0,
    accept_edits = 1,
    plan = 2,

    pub fn label(self: AgyMode) []const u8 {
        return switch (self) {
            .auto => "auto",
            .accept_edits => "accept-edits",
            .plan => "plan",
        };
    }

    pub fn next(self: AgyMode) AgyMode {
        return switch (self) {
            .auto => .accept_edits,
            .accept_edits => .plan,
            .plan => .auto,
        };
    }
};

pub const AgyEffort = enum(u8) {
    low = 0,
    medium = 1,
    high = 2,
    xhigh = 3,
    max = 4,

    pub fn label(self: AgyEffort) []const u8 {
        return switch (self) {
            .low => "low",
            .medium => "medium",
            .high => "high",
            .xhigh => "xhigh",
            .max => "max",
        };
    }

    pub fn next(self: AgyEffort) AgyEffort {
        return switch (self) {
            .low => .medium,
            .medium => .high,
            .high => .xhigh,
            .xhigh => .max,
            .max => .low,
        };
    }
};

pub const UsageStats = struct {
    input_tokens: u64 = 0,
    output_tokens: u64 = 0,
    thinking_tokens: u64 = 0,
    cache_read_tokens: u64 = 0,
    total_tokens: u64 = 0,
};

pub const ModelEntry = struct {
    label_buf: [48]u8 = @splat(0),
    label_len: u8 = 0,
    enum_buf: [48]u8 = @splat(0),
    enum_len: u8 = 0,

    pub fn label(self: *const ModelEntry) []const u8 {
        return self.label_buf[0..@min(@as(usize, self.label_len), self.label_buf.len)];
    }

    pub fn baseLabel(self: *const ModelEntry) []const u8 {
        return stripModelVariantSuffix(self.label());
    }

    pub fn modelEnum(self: *const ModelEntry) []const u8 {
        return self.enum_buf[0..@min(@as(usize, self.enum_len), self.enum_buf.len)];
    }
};

pub const ModelFamily = struct {
    base_label: []const u8 = "",
    rep_idx: usize = 0,
};

pub fn stripModelVariantSuffix(lbl: []const u8) []const u8 {
    const suffixes = [_][]const u8{
        " (High)",
        " (Low)",
        " (Medium)",
        " (Thinking)",
    };
    for (suffixes) |sfx| {
        if (std.mem.endsWith(u8, lbl, sfx)) {
            return lbl[0 .. lbl.len - sfx.len];
        }
    }
    return lbl;
}

pub const RpcKind = enum {
    none,
    get_models,
    list_conversations,
    search_conversations,
    start_cascade,
    send_message,
    get_trajectory,
    cancel_invocation,
    answer_question,
};

pub const ConversationSummary = struct {
    id_buf: [64]u8 = @splat(0),
    id_len: u8 = 0,
    title_buf: [96]u8 = @splat(0),
    title_len: u8 = 0,
    workspace_buf: [192]u8 = @splat(0),
    workspace_len: u8 = 0,
    git_root_buf: [192]u8 = @splat(0),
    git_root_len: u8 = 0,
    modified_buf: [32]u8 = @splat(0),
    modified_len: u8 = 0,
    step_count: u32 = 0,
    is_running: bool = false,
    matches_cwd: bool = false,

    pub fn id(self: *const ConversationSummary) []const u8 {
        return self.id_buf[0..@min(@as(usize, self.id_len), self.id_buf.len)];
    }

    pub fn setId(self: *ConversationSummary, s: []const u8) void {
        const n = @min(s.len, self.id_buf.len);
        @memcpy(self.id_buf[0..n], s[0..n]);
        self.id_len = @intCast(n);
    }

    pub fn title(self: *const ConversationSummary) []const u8 {
        const s = self.title_buf[0..@min(@as(usize, self.title_len), self.title_buf.len)];
        return if (s.len > 0) s else "Untitled Conversation";
    }

    pub fn setTitle(self: *ConversationSummary, s: []const u8) void {
        const trimmed = std.mem.trim(u8, s, " \t\r\n");
        const n = @min(trimmed.len, self.title_buf.len);
        @memcpy(self.title_buf[0..n], trimmed[0..n]);
        self.title_len = @intCast(n);
    }

    pub fn workspace(self: *const ConversationSummary) []const u8 {
        return self.workspace_buf[0..@min(@as(usize, self.workspace_len), self.workspace_buf.len)];
    }

    pub fn setWorkspace(self: *ConversationSummary, raw_uri: []const u8) void {
        const clean = normalizeWorkspaceUriPath(raw_uri);
        const n = @min(clean.len, self.workspace_buf.len);
        @memcpy(self.workspace_buf[0..n], clean[0..n]);
        self.workspace_len = @intCast(n);
    }

    pub fn gitRoot(self: *const ConversationSummary) []const u8 {
        return self.git_root_buf[0..@min(@as(usize, self.git_root_len), self.git_root_buf.len)];
    }

    pub fn setGitRoot(self: *ConversationSummary, raw_uri: []const u8) void {
        const clean = normalizeWorkspaceUriPath(raw_uri);
        const n = @min(clean.len, self.git_root_buf.len);
        @memcpy(self.git_root_buf[0..n], clean[0..n]);
        self.git_root_len = @intCast(n);
    }

    pub fn workspaceBasename(self: *const ConversationSummary) []const u8 {
        const ws = self.workspace();
        if (ws.len == 0) return "global";
        if (std.mem.lastIndexOfScalar(u8, ws, '/')) |slash| {
            if (slash + 1 < ws.len) return ws[slash + 1 ..];
        }
        return ws;
    }

    pub fn modifiedTime(self: *const ConversationSummary) []const u8 {
        return self.modified_buf[0..@min(@as(usize, self.modified_len), self.modified_buf.len)];
    }

    pub fn setModifiedTime(self: *ConversationSummary, s: []const u8) void {
        const n = @min(s.len, self.modified_buf.len);
        @memcpy(self.modified_buf[0..n], s[0..n]);
        self.modified_len = @intCast(n);
    }

    /// Returns a compact date/time label (`MM-DD HH:MM` or `YYYY-MM-DD`) from an ISO-8601 timestamp.
    pub fn shortDate(self: *const ConversationSummary) []const u8 {
        const m = self.modifiedTime();
        // Format: "2026-10-25T00:17:26.510959Z" -> "10-25"
        if (m.len >= 10 and m[4] == '-' and m[7] == '-') {
            return m[5..10];
        }
        return m;
    }
};

pub const ChatEntryKind = enum(u8) {
    user_prompt,
    thinking,
    tool_call,
    shell_command,
    assistant_markdown,
    error_banner,
    question_prompt,
};

pub const ChatEntry = struct {
    kind: ChatEntryKind = .assistant_markdown,
    exit_code: i16 = -1,
    start: u32 = 0,
    end: u32 = 0,
    aux_start: u32 = 0,
    aux_end: u32 = 0,
    detail_start: u32 = 0,
    detail_end: u32 = 0,
};

pub const MaxQuestionsPerStep: usize = 6;
pub const MaxOptionsPerQuestion: usize = 8;

pub const QuestionOption = struct {
    id_buf: [16]u8 = @splat(0),
    id_len: u8 = 0,
    text_buf: [320]u8 = @splat(0),
    text_len: u16 = 0,

    pub fn id(self: *const QuestionOption) []const u8 {
        return self.id_buf[0..@min(@as(usize, self.id_len), self.id_buf.len)];
    }

    pub fn setId(self: *QuestionOption, s: []const u8) void {
        const n = @min(s.len, self.id_buf.len);
        @memcpy(self.id_buf[0..n], s[0..n]);
        self.id_len = @intCast(n);
    }

    pub fn text(self: *const QuestionOption) []const u8 {
        return self.text_buf[0..@min(@as(usize, self.text_len), self.text_buf.len)];
    }

    pub fn setText(self: *QuestionOption, s: []const u8) void {
        const n = @min(s.len, self.text_buf.len);
        @memcpy(self.text_buf[0..n], s[0..n]);
        self.text_len = @intCast(n);
    }
};

pub const QuestionItem = struct {
    question_buf: [384]u8 = @splat(0),
    question_len: u16 = 0,
    is_multi_select: bool = false,
    options: [MaxOptionsPerQuestion]QuestionOption = @splat(.{}),
    option_count: u8 = 0,
    selected_mask: u8 = 0,
    use_write_in: bool = false,
    write_in: platform.InlineString(512) = .{},
    skipped: bool = false,

    pub fn question(self: *const QuestionItem) []const u8 {
        return self.question_buf[0..@min(@as(usize, self.question_len), self.question_buf.len)];
    }

    pub fn setQuestion(self: *QuestionItem, s: []const u8) void {
        const n = @min(s.len, self.question_buf.len);
        @memcpy(self.question_buf[0..n], s[0..n]);
        self.question_len = @intCast(n);
    }

    pub fn optionSlice(self: *const QuestionItem) []const QuestionOption {
        return self.options[0..@min(@as(usize, self.option_count), self.options.len)];
    }

    pub fn isOptionSelected(self: *const QuestionItem, idx: usize) bool {
        if (idx >= MaxOptionsPerQuestion) return false;
        return (self.selected_mask & (@as(u8, 1) << @intCast(idx))) != 0;
    }

    pub fn selectOption(self: *QuestionItem, idx: usize) void {
        if (idx >= self.option_count) return;
        const bit: u8 = @as(u8, 1) << @intCast(idx);
        if (self.is_multi_select) {
            self.selected_mask ^= bit;
        } else {
            self.selected_mask = bit;
            self.use_write_in = false;
        }
        self.skipped = false;
    }

    pub fn toggleWriteIn(self: *QuestionItem) void {
        if (self.is_multi_select) {
            self.use_write_in = !self.use_write_in;
        } else {
            self.use_write_in = true;
            self.selected_mask = 0;
        }
        self.skipped = false;
    }

    pub fn hasAnswer(self: *const QuestionItem) bool {
        if (self.selected_mask != 0) return true;
        if (self.write_in.trim(" \t\r\n").len > 0) return true;
        return false;
    }
};

pub const PendingQuestionGroup = struct {
    active: bool = false,
    submitted: bool = false,
    trajectory_id_buf: [64]u8 = @splat(0),
    trajectory_id_len: u8 = 0,
    step_index: u32 = 0,
    questions: [MaxQuestionsPerStep]QuestionItem = @splat(.{}),
    question_count: usize = 0,

    pub fn trajectoryId(self: *const PendingQuestionGroup) []const u8 {
        return self.trajectory_id_buf[0..@min(@as(usize, self.trajectory_id_len), self.trajectory_id_buf.len)];
    }

    pub fn setTrajectoryId(self: *PendingQuestionGroup, s: []const u8) void {
        const n = @min(s.len, self.trajectory_id_buf.len);
        @memcpy(self.trajectory_id_buf[0..n], s[0..n]);
        self.trajectory_id_len = @intCast(n);
    }

    pub fn questionSlice(self: *const PendingQuestionGroup) []const QuestionItem {
        return self.questions[0..@min(self.question_count, self.questions.len)];
    }

    pub fn questionSliceMut(self: *PendingQuestionGroup) []QuestionItem {
        return self.questions[0..@min(self.question_count, self.questions.len)];
    }

    pub fn hasAnySelection(self: *const PendingQuestionGroup) bool {
        for (self.questionSlice()) |*q| {
            if (q.hasAnswer()) return true;
        }
        return false;
    }
};

pub const TranscriptCapacity: usize = 524288;
pub const MaxModels: usize = 16;
pub const MaxChatEntries: usize = 384;
pub const MaxConversations: usize = 48;
pub const MaxPendingAttachments: usize = 4;

pub const ImageAttachment = struct {
    path_buf: [256]u8 = @splat(0),
    path_len: u16 = 0,
    name_buf: [64]u8 = @splat(0),
    name_len: u8 = 0,
    mime_buf: [32]u8 = @splat(0),
    mime_len: u8 = 0,
    width: u32 = 0,
    height: u32 = 0,
    byte_size: u32 = 0,

    pub fn path(self: *const ImageAttachment) []const u8 {
        return self.path_buf[0..@min(@as(usize, self.path_len), self.path_buf.len)];
    }

    pub fn setPath(self: *ImageAttachment, s: []const u8) void {
        const n = @min(s.len, self.path_buf.len);
        @memcpy(self.path_buf[0..n], s[0..n]);
        self.path_len = @intCast(n);
    }

    pub fn name(self: *const ImageAttachment) []const u8 {
        return self.name_buf[0..@min(@as(usize, self.name_len), self.name_buf.len)];
    }

    pub fn setName(self: *ImageAttachment, s: []const u8) void {
        const n = @min(s.len, self.name_buf.len);
        @memcpy(self.name_buf[0..n], s[0..n]);
        self.name_len = @intCast(n);
    }

    pub fn mimeType(self: *const ImageAttachment) []const u8 {
        const m = self.mime_buf[0..@min(@as(usize, self.mime_len), self.mime_buf.len)];
        return if (m.len > 0) m else "image/png";
    }

    pub fn setMimeType(self: *ImageAttachment, s: []const u8) void {
        const n = @min(s.len, self.mime_buf.len);
        @memcpy(self.mime_buf[0..n], s[0..n]);
        self.mime_len = @intCast(n);
    }
};

pub const AgySession = struct {
    // Discovered Antigravity Hub loopback port & CSRF token
    ls_port: u16 = 0,
    alt_port: u16 = 0,
    csrf_buf: [96]u8 = @splat(0),
    csrf_len: u8 = 0,

    mode: AgyMode = .accept_edits,
    effort: AgyEffort = .high,

    // Available models fetched from `/GetCascadeModelConfigData`
    models: [MaxModels]ModelEntry = @splat(.{}),
    model_count: usize = 0,
    selected_model_idx: usize = 0,
    models_fetched: bool = false,
    models_attempted: bool = false,
    user_picked_model: bool = false,
    default_model_buf: [48]u8 = @splat(0),
    default_model_len: u8 = 0,

    // Past & active conversations fetched from `/GetAllCascadeTrajectories`
    conversations: [MaxConversations]ConversationSummary = @splat(.{}),
    conversation_count: usize = 0,
    conversations_fetched: bool = false,
    conversations_attempted: bool = false,
    last_connect_attempt_ms: i64 = 0,
    hub_spawn_attempted: bool = false,
    loading_conversation: bool = false,
    open_picker_requested: bool = false,
    scroll_to_bottom_frames: u8 = 0,
    synced_workspace_buf: [256]u8 = @splat(0),
    synced_workspace_len: u8 = 0,

    // Active Cascade conversation UUID (`cascadeId`) & summary title
    conv_id_buf: [64:0]u8 = @splat(0),
    conv_id_len: u8 = 0,
    active_title_buf: [96]u8 = @splat(0),
    active_title_len: u8 = 0,

    status_buf: [96]u8 = @splat(0),
    status_len: u8 = 0,

    active_tool_buf: [128]u8 = @splat(0),
    active_tool_len: u8 = 0,

    is_running_turn: bool = false,
    turn_completed_flag: bool = false,
    active_poll_frames: u32 = 0,
    poll_tick_counter: u32 = 0,
    last_poll_ms: i64 = 0,
    eof_ready_ms: i64 = 0,
    steps_at_send: usize = 0,
    seen_running_status: bool = false,
    last_trajectory_hash: u64 = 0,
    unchanged_polls: u16 = 0,
    ui_generation: u32 = 1,

    // Pending `ask_question` interaction (`CORTEX_STEP_TYPE_ASK_QUESTION`) waiting for user response
    pending_question: PendingQuestionGroup = .{},

    // Pending & queued image attachments pasted into the prompt composer (`Cmd+V`)
    pending_attachments: [MaxPendingAttachments]ImageAttachment = @splat(.{}),
    pending_attachment_count: u8 = 0,
    queued_attachments: [MaxPendingAttachments]ImageAttachment = @splat(.{}),
    queued_attachment_count: u8 = 0,
    last_sent_media_buf: [1024]u8 = @splat(0),
    last_sent_media_len: u16 = 0,
    paste_seq: u32 = 0,

    // Queued prompt waiting for `/StartCascade` or `/GetCascadeModelConfigData` to complete
    queued_prompt_buf: [8192]u8 = @splat(0),
    queued_prompt_len: usize = 0,

    // Non-blocking HTTP/1.1 RPC socket state
    sock_fd: c_int = -1,
    active_rpc: RpcKind = .none,
    tx_buf: std.ArrayList(u8) = .empty,
    tx_sent: usize = 0,
    rx_buf: std.ArrayList(u8) = .empty,
    json_scratch: std.ArrayList(u8) = .empty,

    usage: UsageStats = .{},

    // Markdown conversation transcript & structured chat entries rendered in the Agent Panel
    transcript_buf: [TranscriptCapacity]u8 = @splat(0),
    transcript_len: usize = 0,
    entries: [MaxChatEntries]ChatEntry = @splat(.{}),
    entry_count: usize = 0,
    // Per-entry thinking dropdown state (`0 = auto`, `1 = collapsed`, `2 = expanded`)
    thinking_toggle: [MaxChatEntries]u8 = @splat(0),

    pub fn init() AgySession {
        var s = AgySession{};
        s.setDefaultModel("MODEL_PLACEHOLDER_M26");
        s.seedDefaultModels();
        s.setStatus("Idle · Local Socket");
        return s;
    }

    fn addModelEntry(self: *AgySession, lbl: []const u8, m_enum: []const u8) void {
        if (self.model_count >= MaxModels) return;
        var entry = &self.models[self.model_count];
        entry.* = .{};
        const l_n = @min(lbl.len, entry.label_buf.len);
        @memcpy(entry.label_buf[0..l_n], lbl[0..l_n]);
        entry.label_len = @intCast(l_n);

        const e_n = @min(m_enum.len, entry.enum_buf.len);
        @memcpy(entry.enum_buf[0..e_n], m_enum[0..e_n]);
        entry.enum_len = @intCast(e_n);
        self.model_count += 1;
    }

    fn seedDefaultModels(self: *AgySession) void {
        self.model_count = 0;
        self.addModelEntry("Gemini 3.1 Pro (High)", "MODEL_PLACEHOLDER_M37");
        self.addModelEntry("Gemini 3.1 Pro (Low)", "MODEL_PLACEHOLDER_M36");
        self.addModelEntry("Gemini 3 Flash", "MODEL_PLACEHOLDER_M18");
        self.addModelEntry("Claude Sonnet 4.6 (Thinking)", "MODEL_PLACEHOLDER_M35");
        self.addModelEntry("Claude Opus 4.6 (Thinking)", "MODEL_PLACEHOLDER_M26");
        self.addModelEntry("GPT-OSS 120B (Medium)", "MODEL_OPENAI_GPT_OSS_120B_MEDIUM");
        self.selected_model_idx = 4; // Default to Claude Opus 4.6 (Thinking)
    }

    pub fn availableModels(self: *const AgySession) []const ModelEntry {
        return self.models[0..@min(self.model_count, self.models.len)];
    }

    pub fn uniqueModelFamilies(self: *const AgySession, out: *[MaxModels]ModelFamily) []const ModelFamily {
        var count: usize = 0;
        const avail = self.availableModels();
        for (avail, 0..) |*m, idx| {
            const base = m.baseLabel();
            if (base.len == 0) continue;
            var exists = false;
            for (out[0..count]) |existing| {
                if (std.mem.eql(u8, existing.base_label, base)) {
                    exists = true;
                    break;
                }
            }
            if (!exists and count < MaxModels) {
                out[count] = .{ .base_label = base, .rep_idx = idx };
                count += 1;
            }
        }
        return out[0..count];
    }

    pub fn activeBaseModelLabel(self: *const AgySession) []const u8 {
        if (self.model_count > 0 and self.selected_model_idx < self.model_count) {
            return self.models[self.selected_model_idx].baseLabel();
        }
        return "Model";
    }

    pub fn selectModel(self: *AgySession, idx: usize) void {
        if (idx < self.model_count) {
            self.selected_model_idx = idx;
            self.user_picked_model = true;
            const lbl = self.models[idx].label();
            if (std.mem.endsWith(u8, lbl, "(Low)")) {
                self.effort = .low;
            } else if (std.mem.endsWith(u8, lbl, "(Medium)")) {
                self.effort = .medium;
            } else if (std.mem.endsWith(u8, lbl, "(High)")) {
                self.effort = .high;
            }
        }
    }

    pub fn selectModelFamilyAndEffort(self: *AgySession, base_label: []const u8, effort: AgyEffort) void {
        self.effort = effort;
        self.user_picked_model = true;

        const target_suffix: []const u8 = switch (effort) {
            .low => "(Low)",
            .medium => "(Medium)",
            else => "(High)",
        };

        const avail = self.availableModels();
        var fallback_idx: ?usize = null;
        for (avail, 0..) |*m, idx| {
            if (std.mem.eql(u8, m.baseLabel(), base_label)) {
                if (fallback_idx == null) fallback_idx = idx;
                if (std.mem.endsWith(u8, m.label(), target_suffix)) {
                    self.selected_model_idx = idx;
                    return;
                }
            }
        }
        if (fallback_idx) |fb| {
            self.selected_model_idx = fb;
        }
    }

    pub fn ensureModelsLoaded(self: *AgySession) void {
        if (self.models_fetched or self.models_attempted or self.sock_fd >= 0) return;
        const now_ms: i64 = @intCast(platform.profiler.nowNs() / std.time.ns_per_ms);
        if (self.last_connect_attempt_ms != 0 and self.isProcessAlive() and (now_ms - self.last_connect_attempt_ms) < 2000) {
            return;
        }
        if (self.ensureConnected()) {
            self.models_attempted = true;
            self.last_connect_attempt_ms = now_ms;
            _ = self.beginRpcRequest(.get_models, "GetCascadeModelConfigData", "{}");
        }
    }

    pub fn ensureConversationsLoaded(self: *AgySession) void {
        if (self.conversations_fetched or self.conversations_attempted or self.sock_fd >= 0) return;
        if (self.ensureConnected()) {
            self.conversations_attempted = true;
            _ = self.beginRpcRequest(.list_conversations, "GetAllCascadeTrajectories", "{}");
        }
    }

    pub fn refreshConversations(self: *AgySession) void {
        self.conversations_fetched = false;
        self.conversations_attempted = false;
        self.conversation_count = 0;
        self.last_connect_attempt_ms = 0;
        if (self.sock_fd < 0 and self.ensureConnected()) {
            self.conversations_attempted = true;
            _ = self.beginRpcRequest(.list_conversations, "GetAllCascadeTrajectories", "{}");
        }
    }

    pub fn availableConversations(self: *const AgySession) []const ConversationSummary {
        return self.conversations[0..@min(self.conversation_count, self.conversations.len)];
    }

    pub fn workspaceConversationCount(self: *const AgySession) usize {
        var cnt: usize = 0;
        for (self.availableConversations()) |*c| {
            if (c.matches_cwd) cnt += 1;
        }
        return cnt;
    }

    pub fn syncedWorkspaceRoot(self: *const AgySession) []const u8 {
        return self.synced_workspace_buf[0..@min(@as(usize, self.synced_workspace_len), self.synced_workspace_buf.len)];
    }

    /// Synchronizes the active editor workspace root path with `AgySession` and recomputes
    /// `matches_cwd` across all cached conversations whenever the workspace changes.
    pub fn syncWorkspaceRoot(self: *AgySession, raw_workspace_root: []const u8) void {
        var clean = normalizeWorkspaceUriPath(raw_workspace_root);
        var cwd_buf: [512]u8 = undefined;
        if (clean.len == 0 or std.mem.eql(u8, clean, ".")) {
            if (getcwd(&cwd_buf, cwd_buf.len)) |cz| {
                clean = normalizeWorkspaceUriPath(std.mem.sliceTo(cz, 0));
            } else {
                clean = "";
            }
        }

        if (std.mem.eql(u8, self.syncedWorkspaceRoot(), clean)) return;

        const n = @min(clean.len, self.synced_workspace_buf.len);
        @memcpy(self.synced_workspace_buf[0..n], clean[0..n]);
        self.synced_workspace_len = @intCast(n);

        var git_root_buf: [512]u8 = undefined;
        const active_git_root = findEnclosingGitRoot(clean, &git_root_buf);

        const count = @min(self.conversation_count, self.conversations.len);
        for (self.conversations[0..count]) |*c| {
            c.matches_cwd = doesConversationMatchWorkspace(c.workspace(), c.gitRoot(), clean, active_git_root);
        }
    }

    /// Shares discovered Antigravity Hub loopback connection parameters (`ls_port`, `alt_port`,
    /// `csrf_buf`), workspace root, model catalog (`/GetCascadeModelConfigData`), and conversation
    /// summary list (`/GetAllCascadeTrajectories`) from `src` into `self` so multiple concurrent
    /// `AgySession` buffers multiplex over the same `agy` process without redundant process/RPC discovery.
    pub fn shareHubStateFrom(self: *AgySession, src: *const AgySession) void {
        if (src.isProcessAlive()) {
            if (!self.isProcessAlive() or self.ls_port != src.ls_port or self.alt_port != src.alt_port) {
                self.ls_port = src.ls_port;
                self.alt_port = src.alt_port;
                self.csrf_buf = src.csrf_buf;
                self.csrf_len = src.csrf_len;
                if (std.mem.eql(u8, self.statusText(), "Idle · Local Socket") or
                    std.mem.eql(u8, self.statusText(), "Waiting for Antigravity Hub..."))
                {
                    self.setStatus("Connected to Hub");
                }
            }
        }
        if (src.synced_workspace_len > 0 and self.synced_workspace_len == 0) {
            self.synced_workspace_buf = src.synced_workspace_buf;
            self.synced_workspace_len = src.synced_workspace_len;
        }
        self.models_attempted = src.models_attempted;
        if (src.models_fetched and (!self.models_fetched or self.model_count < src.model_count)) {
            self.models = src.models;
            self.model_count = src.model_count;
            self.default_model_buf = src.default_model_buf;
            self.default_model_len = src.default_model_len;
            if (!self.user_picked_model and src.selected_model_idx < src.model_count) {
                self.selected_model_idx = src.selected_model_idx;
            }
            self.models_fetched = true;
            self.models_attempted = true;
        }
        self.conversations_attempted = src.conversations_attempted;
        if (src.conversations_fetched and (!self.conversations_fetched or self.conversation_count < src.conversation_count)) {
            self.conversations = src.conversations;
            self.conversation_count = src.conversation_count;
            self.conversations_fetched = true;
            self.conversations_attempted = true;
            if (self.conv_id_len > 0 and self.active_title_len == 0) {
                for (self.availableConversations()) |*c| {
                    if (std.mem.eql(u8, c.id(), self.conversationId())) {
                        if (c.title_len > 0) self.setActiveTitle(c.title());
                        break;
                    }
                }
            }
        }
    }

    pub fn activeTitle(self: *const AgySession) []const u8 {
        return self.active_title_buf[0..@min(@as(usize, self.active_title_len), self.active_title_buf.len)];
    }

    pub fn setActiveTitle(self: *AgySession, s: []const u8) void {
        const trimmed = std.mem.trim(u8, s, " \t\r\n");
        const n = @min(trimmed.len, self.active_title_buf.len);
        @memcpy(self.active_title_buf[0..n], trimmed[0..n]);
        self.active_title_len = @intCast(n);
    }

    pub fn deinit(self: *AgySession) void {
        self.closeSocket();
        self.tx_buf.deinit(std.heap.c_allocator);
        self.rx_buf.deinit(std.heap.c_allocator);
        self.json_scratch.deinit(std.heap.c_allocator);
    }

    pub fn closeSocket(self: *AgySession) void {
        if (self.sock_fd >= 0) {
            closeLoopbackSocket(self.sock_fd);
            self.sock_fd = -1;
        }
        self.active_rpc = .none;
        self.tx_buf.clearRetainingCapacity();
        self.tx_sent = 0;
        self.rx_buf.clearRetainingCapacity();
        self.eof_ready_ms = 0;
    }

    pub fn isProcessAlive(self: *const AgySession) bool {
        return self.ls_port > 0 and self.csrf_len > 0;
    }

    pub fn csrfToken(self: *const AgySession) []const u8 {
        return self.csrf_buf[0..@min(@as(usize, self.csrf_len), self.csrf_buf.len)];
    }

    pub fn conversationId(self: *const AgySession) []const u8 {
        return self.conv_id_buf[0..@min(@as(usize, self.conv_id_len), self.conv_id_buf.len)];
    }

    pub fn statusText(self: *const AgySession) []const u8 {
        return self.status_buf[0..@min(@as(usize, self.status_len), self.status_buf.len)];
    }

    pub fn activeToolText(self: *const AgySession) []const u8 {
        return self.active_tool_buf[0..@min(@as(usize, self.active_tool_len), self.active_tool_buf.len)];
    }

    pub fn transcript(self: *const AgySession) []const u8 {
        return self.transcript_buf[0..@min(self.transcript_len, self.transcript_buf.len)];
    }

    pub fn chatEntries(self: *const AgySession) []const ChatEntry {
        return self.entries[0..@min(self.entry_count, self.entries.len)];
    }

    pub fn entryText(self: *const AgySession, e: ChatEntry) []const u8 {
        const s = @min(@as(usize, e.start), self.transcript_len);
        const end = @max(s, @min(@as(usize, e.end), self.transcript_len));
        return self.transcript_buf[s..end];
    }

    pub fn entryAuxText(self: *const AgySession, e: ChatEntry) []const u8 {
        const s = @min(@as(usize, e.aux_start), self.transcript_len);
        const end = @max(s, @min(@as(usize, e.aux_end), self.transcript_len));
        return self.transcript_buf[s..end];
    }

    pub fn entryDetailText(self: *const AgySession, e: ChatEntry) []const u8 {
        const s = @min(@as(usize, e.detail_start), self.transcript_len);
        const end = @max(s, @min(@as(usize, e.detail_end), self.transcript_len));
        return self.transcript_buf[s..end];
    }

    pub fn isThinkingExpanded(self: *const AgySession, entry_idx: usize, is_active_streaming: bool) bool {
        if (entry_idx >= self.thinking_toggle.len) return false;
        return switch (self.thinking_toggle[entry_idx]) {
            1 => false,
            2 => true,
            else => is_active_streaming,
        };
    }

    pub fn toggleThinkingExpanded(self: *AgySession, entry_idx: usize, currently_expanded: bool) void {
        if (entry_idx >= self.thinking_toggle.len) return;
        self.thinking_toggle[entry_idx] = if (currently_expanded) 1 else 2;
        self.ui_generation +%= 1;
    }

    pub fn pendingAttachments(self: *const AgySession) []const ImageAttachment {
        return self.pending_attachments[0..@min(@as(usize, self.pending_attachment_count), self.pending_attachments.len)];
    }

    pub fn addImageAttachmentFromFile(
        self: *AgySession,
        file_path: []const u8,
        display_name: []const u8,
        mime_type: []const u8,
        width: u32,
        height: u32,
        byte_size: u32,
    ) bool {
        if (file_path.len == 0) return false;
        const count = @min(@as(usize, self.pending_attachment_count), self.pending_attachments.len);
        for (self.pending_attachments[0..count]) |*existing| {
            if (std.mem.eql(u8, existing.path(), file_path)) {
                existing.setName(if (display_name.len > 0) display_name else "image.png");
                existing.setMimeType(if (mime_type.len > 0) mime_type else "image/png");
                existing.width = width;
                existing.height = height;
                existing.byte_size = byte_size;
                self.ui_generation +%= 1;
                return true;
            }
        }

        const slot: usize = if (count < MaxPendingAttachments) blk: {
            self.pending_attachment_count = @intCast(count + 1);
            break :blk count;
        } else blk: {
            for (0 .. MaxPendingAttachments - 1) |i| {
                self.pending_attachments[i] = self.pending_attachments[i + 1];
            }
            break :blk MaxPendingAttachments - 1;
        };

        var att = &self.pending_attachments[slot];
        att.* = .{};
        att.setPath(file_path);
        const fallback_name = if (std.mem.lastIndexOfScalar(u8, file_path, '/')) |slash|
            (if (slash + 1 < file_path.len) file_path[slash + 1 ..] else "image.png")
        else
            file_path;
        att.setName(if (display_name.len > 0) display_name else fallback_name);
        att.setMimeType(if (mime_type.len > 0) mime_type else "image/png");
        att.width = width;
        att.height = height;
        att.byte_size = byte_size;
        self.ui_generation +%= 1;
        return true;
    }

    pub fn addImageAttachmentFromBytes(
        self: *AgySession,
        raw_bytes: []const u8,
        mime_type: []const u8,
        display_name: []const u8,
        source_path: []const u8,
        width: u32,
        height: u32,
    ) bool {
        if (source_path.len > 0 and source_path.len < 255) {
            var zpath: [256:0]u8 = @splat(0);
            @memcpy(zpath[0..source_path.len], source_path);
            if (std.c.fopen(&zpath, "rb")) |fp| {
                _ = std.c.fclose(fp);
                return self.addImageAttachmentFromFile(
                    source_path,
                    display_name,
                    mime_type,
                    width,
                    height,
                    @intCast(@min(raw_bytes.len, std.math.maxInt(u32))),
                );
            }
        }
        if (raw_bytes.len == 0) return false;

        self.paste_seq +%= 1;
        const ts_ms: u64 = platform.profiler.nowNs() / std.time.ns_per_ms;

        const ext: []const u8 = if (std.mem.eql(u8, mime_type, "image/jpeg"))
            "jpg"
        else if (std.mem.eql(u8, mime_type, "image/webp"))
            "webp"
        else if (std.mem.eql(u8, mime_type, "image/gif"))
            "gif"
        else if (std.mem.eql(u8, mime_type, "image/svg+xml"))
            "svg"
        else
            "png";

        var path_buf: [256:0]u8 = @splat(0);
        const path_slice = std.fmt.bufPrint(
            path_buf[0 .. path_buf.len - 1],
            "{s}/lightning_paste_{d}_{d}.{s}",
            .{ platform.fs_util.tempDirPath(), ts_ms, self.paste_seq, ext },
        ) catch return false;
        path_buf[path_slice.len] = 0;

        const fp = std.c.fopen(&path_buf, "wb") orelse return false;
        const written = std.c.fwrite(raw_bytes.ptr, 1, raw_bytes.len, fp);
        _ = std.c.fclose(fp);
        if (written != raw_bytes.len) return false;

        var default_name_buf: [64]u8 = undefined;
        const eff_name = if (display_name.len > 0)
            display_name
        else
            (std.fmt.bufPrint(&default_name_buf, "screenshot-{d}.{s}", .{ self.paste_seq, ext }) catch "screenshot.png");

        return self.addImageAttachmentFromFile(
            path_slice,
            eff_name,
            if (mime_type.len > 0) mime_type else "image/png",
            width,
            height,
            @intCast(@min(raw_bytes.len, std.math.maxInt(u32))),
        );
    }

    pub fn removePendingAttachment(self: *AgySession, idx: usize) void {
        const count = @min(@as(usize, self.pending_attachment_count), self.pending_attachments.len);
        if (idx >= count) return;
        var i: usize = idx;
        while (i + 1 < count) : (i += 1) {
            self.pending_attachments[i] = self.pending_attachments[i + 1];
        }
        self.pending_attachments[count - 1] = .{};
        self.pending_attachment_count = @intCast(count - 1);
        self.ui_generation +%= 1;
    }

    pub fn clearPendingAttachments(self: *AgySession) void {
        if (self.pending_attachment_count == 0) return;
        self.pending_attachments = @splat(.{});
        self.pending_attachment_count = 0;
        self.ui_generation +%= 1;
    }

    pub fn computeVisibleStateDigest(self: *const AgySession) u64 {
        var h = std.hash.Wyhash.init(0xA675_E551_0000_0001);
        h.update(std.mem.asBytes(&self.entry_count));
        h.update(std.mem.asBytes(&self.transcript_len));
        h.update(std.mem.asBytes(&self.is_running_turn));
        h.update(std.mem.asBytes(&self.loading_conversation));
        h.update(std.mem.asBytes(&self.pending_question.active));
        h.update(std.mem.asBytes(&self.pending_question.step_index));
        h.update(std.mem.asBytes(&self.usage.total_tokens));
        h.update(self.activeToolText());
        h.update(self.statusText());
        if (self.transcript_len > 0) {
            const tail_start = self.transcript_len -| 256;
            h.update(self.transcript_buf[tail_start..self.transcript_len]);
        }
        if (self.entry_count > 0) {
            const last_e = self.entries[self.entry_count - 1];
            h.update(std.mem.asBytes(&last_e));
        }
        return h.final();
    }

    fn evictOldestEntries(self: *AgySession, needed_bytes: usize) void {
        var keep_from: usize = if (self.entry_count >= MaxChatEntries) 1 else 0;
        while (keep_from < self.entry_count) {
            const drop_b: usize = @min(@as(usize, self.entries[keep_from].start), self.transcript_len);
            const remain_b = self.transcript_len - drop_b;
            if (remain_b + needed_bytes <= TranscriptCapacity) break;
            keep_from += 1;
        }

        if (keep_from == 0) {
            if (self.transcript_len + needed_bytes > TranscriptCapacity) {
                self.entry_count = 0;
                self.transcript_len = 0;
                self.thinking_toggle = @splat(0);
            }
            return;
        }

        if (keep_from >= self.entry_count) {
            self.entry_count = 0;
            self.transcript_len = 0;
            self.thinking_toggle = @splat(0);
            return;
        }

        const drop_bytes: usize = @min(@as(usize, self.entries[keep_from].start), self.transcript_len);
        const remain_bytes = self.transcript_len - drop_bytes;
        if (drop_bytes > 0 and remain_bytes > 0) {
            std.mem.copyForwards(
                u8,
                self.transcript_buf[0..remain_bytes],
                self.transcript_buf[drop_bytes .. drop_bytes + remain_bytes],
            );
        }
        self.transcript_len = remain_bytes;

        const remain_entries = self.entry_count - keep_from;
        const drop_u32: u32 = @intCast(drop_bytes);
        for (0..remain_entries) |i| {
            var e = self.entries[keep_from + i];
            e.start -|= drop_u32;
            e.end -|= drop_u32;
            e.aux_start -|= drop_u32;
            e.aux_end -|= drop_u32;
            e.detail_start -|= drop_u32;
            e.detail_end -|= drop_u32;
            self.entries[i] = e;
            self.thinking_toggle[i] = self.thinking_toggle[keep_from + i];
        }
        for (remain_entries..MaxChatEntries) |i| {
            self.thinking_toggle[i] = 0;
        }
        self.entry_count = remain_entries;
    }

    pub fn pushChatEntry(self: *AgySession, kind: ChatEntryKind, primary: []const u8, aux: []const u8) void {
        const clamped_primary = primary[0..@min(primary.len, TranscriptCapacity / 2)];
        const clamped_aux = aux[0..@min(aux.len, TranscriptCapacity / 4)];
        const total_needed = clamped_primary.len + clamped_aux.len;

        if (self.entry_count >= MaxChatEntries or self.transcript_len + total_needed > TranscriptCapacity) {
            self.evictOldestEntries(total_needed);
        }

        const p_start: u32 = @intCast(self.transcript_len);
        self.appendTranscript(clamped_primary);
        const p_end: u32 = @intCast(self.transcript_len);

        const a_start: u32 = @intCast(self.transcript_len);
        if (clamped_aux.len > 0) {
            self.appendTranscript(clamped_aux);
        }
        const a_end: u32 = @intCast(self.transcript_len);

        self.entries[self.entry_count] = .{
            .kind = kind,
            .start = p_start,
            .end = p_end,
            .aux_start = a_start,
            .aux_end = a_end,
        };
        self.entry_count += 1;
    }

    pub fn attachShellCommandResult(
        self: *AgySession,
        cmd_line: []const u8,
        summary_fallback: []const u8,
        output: []const u8,
        exit_code: i16,
    ) void {
        const clamped_out = output[0..@min(output.len, 2048)];

        // Pair with the most recent pending `.shell_command` entry (or create one if none exists)
        var target_idx: ?usize = null;
        var i: usize = self.entry_count;
        while (i > 0) {
            i -= 1;
            const e = self.entries[i];
            if (e.kind == .shell_command and e.detail_start == e.detail_end and e.exit_code < 0) {
                target_idx = i;
                break;
            }
        }

        if (target_idx == null) {
            const prim = if (cmd_line.len > 0) cmd_line else summary_fallback;
            const aux = if (summary_fallback.len > 0) summary_fallback else cmd_line;
            self.pushChatEntry(.shell_command, prim, aux);
            if (self.entry_count > 0) {
                target_idx = self.entry_count - 1;
            }
        }

        const idx = target_idx orelse return;
        self.entries[idx].exit_code = exit_code;

        if (clamped_out.len > 0) {
            if (self.transcript_len + clamped_out.len > TranscriptCapacity) {
                self.evictOldestEntries(clamped_out.len);
                if (idx >= self.entry_count) return;
            }
            const d_start: u32 = @intCast(self.transcript_len);
            self.appendTranscript(clamped_out);
            const d_end: u32 = @intCast(self.transcript_len);
            self.entries[idx].detail_start = d_start;
            self.entries[idx].detail_end = d_end;
        }
    }

    pub fn activeModelEnum(self: *const AgySession) []const u8 {
        if (self.model_count > 0 and self.selected_model_idx < self.model_count) {
            const m = self.models[self.selected_model_idx].modelEnum();
            if (m.len > 0) return m;
        }
        const def = self.default_model_buf[0..@min(@as(usize, self.default_model_len), self.default_model_buf.len)];
        return if (def.len > 0) def else "MODEL_PLACEHOLDER_M418";
    }

    pub fn activeModelLabel(self: *const AgySession) []const u8 {
        if (self.model_count > 0 and self.selected_model_idx < self.model_count) {
            const lbl = self.models[self.selected_model_idx].label();
            if (lbl.len > 0) return lbl;
        }
        return self.effort.label();
    }

    pub fn setDefaultModel(self: *AgySession, m: []const u8) void {
        const n = @min(m.len, self.default_model_buf.len);
        @memcpy(self.default_model_buf[0..n], m[0..n]);
        self.default_model_len = @intCast(n);
    }

    pub fn cycleMode(self: *AgySession) void {
        self.mode = self.mode.next();
    }

    pub fn cycleEffort(self: *AgySession) void {
        self.effort = self.effort.next();
        if (self.model_count > 0) {
            self.selected_model_idx = (self.selected_model_idx + 1) % self.model_count;
        }
    }

    pub fn setStatus(self: *AgySession, msg: []const u8) void {
        const n = @min(msg.len, self.status_buf.len);
        @memcpy(self.status_buf[0..n], msg[0..n]);
        self.status_len = @intCast(n);
    }

    pub fn setActiveTool(self: *AgySession, msg: []const u8) void {
        const n = @min(msg.len, self.active_tool_buf.len);
        @memcpy(self.active_tool_buf[0..n], msg[0..n]);
        self.active_tool_len = @intCast(n);
    }

    pub fn appendTranscript(self: *AgySession, text: []const u8) void {
        if (text.len == 0) return;
        if (self.transcript_len + text.len > TranscriptCapacity) {
            const drop = @min(self.transcript_len, @max(TranscriptCapacity / 4, text.len));
            const remain = self.transcript_len - drop;
            if (remain > 0) {
                std.mem.copyForwards(u8, self.transcript_buf[0..remain], self.transcript_buf[drop .. drop + remain]);
            }
            self.transcript_len = remain;
        }
        const avail = TranscriptCapacity - self.transcript_len;
        const n = @min(text.len, avail);
        @memcpy(self.transcript_buf[self.transcript_len .. self.transcript_len + n], text[0..n]);
        self.transcript_len += n;
    }

    // ========================================================================
    // Hub Discovery (`language_server` / `agy --hub` / `~/.gemini/.../daemon/*.json`)
    // ========================================================================

    pub fn ensureConnected(self: *AgySession) bool {
        if (self.isProcessAlive()) return true;

        const now_ms: i64 = @intCast(platform.profiler.nowNs() / std.time.ns_per_ms);
        const retry_interval_ms: i64 = if (self.hub_spawn_attempted) 1500 else 5000;
        if (self.last_connect_attempt_ms != 0 and (now_ms - self.last_connect_attempt_ms) < retry_interval_ms) {
            return false;
        }
        self.last_connect_attempt_ms = now_ms;

        self.ls_port = 0;
        self.alt_port = 0;
        self.csrf_len = 0;

        syncCliOAuthTokenIfNeeded();

        if (discoverRunningHub(&self.ls_port, &self.alt_port, &self.csrf_buf, &self.csrf_len)) {
            self.setStatus("Connected to Hub");
            return true;
        }

        self.spawnBackgroundHubIfNeeded();
        if (!self.hub_spawn_attempted) {
            self.setStatus("Waiting for Antigravity Hub...");
        }
        return false;
    }

    fn spawnBackgroundHubIfNeeded(self: *AgySession) void {
        if (comptime (builtin.is_test or is_windows)) return;
        if (self.hub_spawn_attempted) return;
        self.hub_spawn_attempted = true;

        syncCliOAuthTokenIfNeeded();

        const spawn_cmd =
            "sh -c 'export PATH=\"$HOME/.local/bin:$PATH\"; " ++
            "command -v agy >/dev/null 2>&1 && " ++
            "SSH_TTY=/dev/pts/0 AGY_ENABLE_HUB=1 nohup agy --hub --hub-port=0 >/dev/null 2>&1 &' 2>/dev/null";
        if (popen(spawn_cmd, "r")) |fp| {
            _ = pclose(fp);
            self.active_poll_frames = @max(self.active_poll_frames, 240);
            self.setStatus("Starting Antigravity Hub...");
        }
    }

    pub const extractFlagValue = extractCmdFlagValue;

    // ========================================================================
    // Lifecycle & Conversation Operations over Local Socket
    // ========================================================================

    /// Interrupts the active turn cleanly via `/CancelCascadeInvocation` over the local socket
    /// without killing the daemon or losing `cascadeId`.
    pub fn interruptTurn(self: *AgySession) void {
        self.queued_prompt_len = 0;
        self.queued_attachment_count = 0;
        self.pending_question.active = false;
        self.pending_question.submitted = false;
        self.last_trajectory_hash = 0;
        self.unchanged_polls = 0;
        self.ui_generation +%= 1;
        if (!self.is_running_turn) return;
        self.is_running_turn = false;
        self.active_tool_len = 0;
        self.pushChatEntry(.error_banner, "Turn interrupted by user.", "");
        self.setStatus("Interrupted");

        if (self.conv_id_len > 0 and self.ensureConnected()) {
            var body_buf: [160]u8 = undefined;
            const body = std.fmt.bufPrint(&body_buf, "{{\"cascadeId\":\"{s}\"}}", .{self.conversationId()}) catch return;
            _ = self.beginRpcRequest(.cancel_invocation, "CancelCascadeInvocation", body);
        } else {
            self.closeSocket();
        }
    }

    /// Resets the conversation so the next user prompt starts a fresh `cascadeId` via `/StartCascade`.
    pub fn resetConversation(self: *AgySession) void {
        if (self.is_running_turn) {
            self.interruptTurn();
        }
        self.closeSocket();
        self.conv_id_len = 0;
        self.conv_id_buf = @splat(0);
        self.active_title_len = 0;
        self.active_title_buf = @splat(0);
        self.loading_conversation = false;
        self.queued_prompt_len = 0;
        self.queued_attachment_count = 0;
        self.pending_attachment_count = 0;
        self.last_sent_media_len = 0;
        self.steps_at_send = 0;
        self.seen_running_status = false;
        self.last_trajectory_hash = 0;
        self.unchanged_polls = 0;
        self.ui_generation +%= 1;
        self.pending_question = .{};
        self.usage = .{};
        self.transcript_len = 0;
        self.entry_count = 0;
        self.thinking_toggle = @splat(0);
        self.scroll_to_bottom_frames = 1;
        self.setStatus("Idle · New Session");
    }

    /// Loads and resumes an existing Antigravity conversation by `cascadeId` (`UUID`):
    /// - Sets `self.conv_id_buf` so subsequent user prompts continue the same conversation.
    /// - Fetches `/GetCascadeTrajectory` over the local socket (with offline fallback to `~/.gemini/antigravity/brain/<id>`).
    pub fn loadConversation(self: *AgySession, cascade_id: []const u8) bool {
        const trimmed_id = std.mem.trim(u8, cascade_id, " \t\r\n");
        if (trimmed_id.len == 0 or trimmed_id.len >= self.conv_id_buf.len) return false;

        self.closeSocket();
        @memcpy(self.conv_id_buf[0..trimmed_id.len], trimmed_id);
        self.conv_id_buf[trimmed_id.len] = 0;
        self.conv_id_len = @intCast(trimmed_id.len);

        self.active_title_len = 0;
        var summary_running = false;
        for (self.availableConversations()) |*c| {
            if (std.mem.eql(u8, c.id(), trimmed_id)) {
                self.setActiveTitle(c.title());
                summary_running = c.is_running;
                break;
            }
        }

        self.queued_prompt_len = 0;
        self.queued_attachment_count = 0;
        self.last_sent_media_len = 0;
        self.steps_at_send = 0;
        self.seen_running_status = summary_running;
        self.is_running_turn = summary_running;
        self.loading_conversation = true;
        self.last_trajectory_hash = 0;
        self.unchanged_polls = 0;
        self.ui_generation +%= 1;
        self.active_tool_len = 0;
        self.pending_question = .{};
        self.usage = .{};
        self.transcript_len = 0;
        self.entry_count = 0;
        self.thinking_toggle = @splat(0);
        self.scroll_to_bottom_frames = 2;
        self.active_poll_frames = 120;
        self.setStatus("Loading conversation...");

        if (self.requestTrajectoryUpdateRpc()) {
            return true;
        }
        if (self.loadTranscriptJsonlFallback(trimmed_id)) {
            self.loading_conversation = false;
            self.scroll_to_bottom_frames = 2;
            self.ui_generation +%= 1;
            self.setStatus("Loaded · Offline");
            return true;
        }
        self.loading_conversation = false;
        self.ui_generation +%= 1;
        self.setStatus("Failed to load conversation");
        return false;
    }

    /// Formats the `/HandleCascadeUserInteraction` JSON request body for `self.pending_question`.
    pub fn buildQuestionInteractionPayload(
        self: *const AgySession,
        out: *std.ArrayList(u8),
        alloc: std.mem.Allocator,
        skip_all: bool,
    ) !void {
        var hdr_buf: [256]u8 = undefined;
        const traj_id = self.pending_question.trajectoryId();
        const hdr = if (traj_id.len > 0)
            try std.fmt.bufPrint(
                &hdr_buf,
                "{{\"cascadeId\":\"{s}\",\"interaction\":{{\"trajectoryId\":\"{s}\",\"stepIndex\":{d},\"askQuestion\":{{\"cancelled\":false,\"responses\":[",
                .{ self.conversationId(), traj_id, self.pending_question.step_index },
            )
        else
            try std.fmt.bufPrint(
                &hdr_buf,
                "{{\"cascadeId\":\"{s}\",\"interaction\":{{\"stepIndex\":{d},\"askQuestion\":{{\"cancelled\":false,\"responses\":[",
                .{ self.conversationId(), self.pending_question.step_index },
            );
        try out.appendSlice(alloc, hdr);

        const q_slice = self.pending_question.questionSlice();
        for (q_slice, 0..) |*q, q_idx| {
            if (q_idx > 0) try out.append(alloc, ',');
            try out.appendSlice(alloc, "{\"question\":\"");
            try appendJsonEscaped(out, alloc, q.question());
            try out.appendSlice(alloc, if (q.is_multi_select) "\",\"isMultiSelect\":true,\"options\":[" else "\",\"isMultiSelect\":false,\"options\":[");

            const opts = q.optionSlice();
            for (opts, 0..) |*opt, opt_i| {
                if (opt_i > 0) try out.append(alloc, ',');
                try out.appendSlice(alloc, "{\"id\":\"");
                try appendJsonEscaped(out, alloc, opt.id());
                try out.appendSlice(alloc, "\",\"text\":\"");
                try appendJsonEscaped(out, alloc, opt.text());
                try out.appendSlice(alloc, "\"}");
            }
            try out.appendSlice(alloc, "],\"selectedOptionIds\":[");

            const write_in_trimmed = q.write_in.trim(" \t\r\n");
            const prefer_write_in_only = (!q.is_multi_select and q.use_write_in and write_in_trimmed.len > 0);
            var selected_count: usize = 0;
            if (!skip_all and !prefer_write_in_only) {
                for (opts, 0..) |*opt, opt_i| {
                    if (q.isOptionSelected(opt_i)) {
                        if (selected_count > 0) try out.append(alloc, ',');
                        try out.append(alloc, '"');
                        try appendJsonEscaped(out, alloc, opt.id());
                        try out.append(alloc, '"');
                        selected_count += 1;
                    }
                }
            }
            try out.append(alloc, ']');

            var has_write_in = false;
            if (!skip_all and write_in_trimmed.len > 0 and (q.use_write_in or q.is_multi_select or selected_count == 0)) {
                try out.appendSlice(alloc, ",\"writeInResponse\":\"");
                try appendJsonEscaped(out, alloc, write_in_trimmed);
                try out.append(alloc, '"');
                has_write_in = true;
            }

            const is_skipped = skip_all or (selected_count == 0 and !has_write_in);
            if (is_skipped) {
                try out.appendSlice(alloc, ",\"skipped\":true}");
            } else {
                try out.appendSlice(alloc, ",\"skipped\":false}");
            }
        }

        try out.appendSlice(alloc, "]}}}");
    }

    /// Dispatches the user's selected option(s) / write-in response (or skip) for the active
    /// `CORTEX_STEP_TYPE_ASK_QUESTION` step via `/HandleCascadeUserInteraction`.
    pub fn submitQuestionResponse(self: *AgySession, skip_all: bool) bool {
        if (!self.pending_question.active or self.conv_id_len == 0) return false;
        if (!self.ensureConnected()) return false;

        if (skip_all) {
            for (self.pending_question.questionSliceMut()) |*q| {
                q.selected_mask = 0;
                q.use_write_in = false;
                q.write_in.clear();
                q.skipped = true;
            }
        }

        var payload: std.ArrayList(u8) = .empty;
        defer payload.deinit(std.heap.c_allocator);
        self.buildQuestionInteractionPayload(&payload, std.heap.c_allocator, skip_all) catch return false;

        self.pending_question.active = false;
        self.pending_question.submitted = true;
        self.is_running_turn = true;
        self.seen_running_status = false;
        self.last_trajectory_hash = 0;
        self.unchanged_polls = 0;
        self.ui_generation +%= 1;
        self.scroll_to_bottom_frames = 3;
        self.active_tool_len = 0;
        self.active_poll_frames = 180;
        self.setStatus("Thinking...");

        return self.beginRpcRequest(.answer_question, "HandleCascadeUserInteraction", payload.items);
    }

    /// Sends a user prompt (and any pending image attachments) over the local ConnectRPC socket:
    /// 1. Ensures connection to `127.0.0.1:<port>`
    /// 2. Fetches `/GetCascadeModelConfigData` if models haven't been loaded yet
    /// 3. Calls `/StartCascade` if `cascadeId` hasn't been created yet
    /// 4. Dispatches `/SendUserCascadeMessage` and begins streaming `/GetCascadeTrajectory`
    pub fn sendUserPrompt(self: *AgySession, content: []const u8) bool {
        const trimmed = std.mem.trim(u8, content, " \t\r\n");
        const att_count = @min(@as(usize, self.pending_attachment_count), self.pending_attachments.len);
        if (trimmed.len == 0 and att_count == 0) return false;

        if (!self.ensureConnected()) {
            self.pushChatEntry(.error_banner, "Could not find running Antigravity language_server hub.", "");
            self.scroll_to_bottom_frames = 2;
            self.ui_generation +%= 1;
            return false;
        }

        const q_text = if (trimmed.len > 0) trimmed else " ";
        const q_len = @min(q_text.len, self.queued_prompt_buf.len);
        @memcpy(self.queued_prompt_buf[0..q_len], q_text[0..q_len]);
        self.queued_prompt_len = q_len;

        self.queued_attachment_count = @intCast(att_count);
        var media_pos: usize = 0;
        for (self.pending_attachments[0..att_count], 0..) |att, i| {
            self.queued_attachments[i] = att;
            const p = att.path();
            if (p.len > 0) {
                if (media_pos > 0) appendFixedSlice(&self.last_sent_media_buf, &media_pos, "\n");
                appendFixedSlice(&self.last_sent_media_buf, &media_pos, p);
            }
        }
        self.last_sent_media_len = @intCast(media_pos);
        self.pending_attachment_count = 0;

        self.is_running_turn = true;
        self.seen_running_status = false;
        self.last_trajectory_hash = 0;
        self.unchanged_polls = 0;
        self.ui_generation +%= 1;
        self.scroll_to_bottom_frames = 3;
        self.active_tool_len = 0;
        self.active_poll_frames = 180;
        self.setStatus("Thinking...");

        if (self.conv_id_len == 0) {
            self.transcript_len = 0;
            self.entry_count = 0;
            self.thinking_toggle = @splat(0);
        }
        self.pushChatEntry(.user_prompt, trimmed, self.last_sent_media_buf[0..media_pos]);

        if (!self.models_fetched) {
            return self.beginRpcRequest(.get_models, "GetCascadeModelConfigData", "{}");
        }
        if (self.conv_id_len == 0) {
            return self.startNewCascadeRpc();
        }
        return self.dispatchQueuedMessageRpc();
    }

    fn startNewCascadeRpc(self: *AgySession) bool {
        var cwd_buf: [512]u8 = undefined;
        const cwd_slice = if (getcwd(&cwd_buf, cwd_buf.len)) |cz|
            std.mem.sliceTo(cz, 0)
        else
            "/tmp";
        const file_scheme = if (cwd_slice.len > 0 and cwd_slice[0] != '/') "file:///" else "file://";
        var body_buf: [768]u8 = undefined;
        const body = std.fmt.bufPrint(
            &body_buf,
            "{{\"metadata\":{{\"ideName\":\"antigravity\",\"ideVersion\":\"2.24.0\",\"extensionName\":\"antigravity\",\"locale\":\"en\"}}," ++
                "\"source\":\"CORTEX_TRAJECTORY_SOURCE_CASCADE_CLIENT\"," ++
                "\"workspaceUris\":[\"{s}{s}\"]}}",
            .{ file_scheme, cwd_slice },
        ) catch return false;
        return self.beginRpcRequest(.start_cascade, "StartCascade", body);
    }

    /// Formats the `/SendUserCascadeMessage` JSON payload including optional base64-encoded `"media"` attachments.
    pub fn buildSendUserMessagePayload(
        self: *const AgySession,
        msg: []const u8,
        attachments: []const ImageAttachment,
        out: *std.ArrayList(u8),
        alloc: std.mem.Allocator,
    ) !void {
        var prefix_buf: [256]u8 = undefined;
        const prefix = try std.fmt.bufPrint(
            &prefix_buf,
            "{{\"metadata\":{{\"ideName\":\"antigravity\",\"ideVersion\":\"2.24.0\",\"extensionName\":\"antigravity\",\"locale\":\"en\"}},\"cascadeId\":\"{s}\",\"items\":[{{\"text\":\"",
            .{self.conversationId()},
        );

        try out.appendSlice(alloc, prefix);
        try appendJsonEscaped(out, alloc, msg);
        try out.appendSlice(alloc, "\"}]");

        if (attachments.len > 0) {
            var wrote_media = false;
            for (attachments) |*att| {
                const raw_bytes = readFileBytesAlloc(alloc, att.path(), 20 * 1024 * 1024) orelse continue;
                defer alloc.free(raw_bytes);

                const b64_len = std.base64.standard.Encoder.calcSize(raw_bytes.len);
                const b64_buf = try alloc.alloc(u8, b64_len);
                defer alloc.free(b64_buf);
                const encoded = std.base64.standard.Encoder.encode(b64_buf, raw_bytes);

                if (!wrote_media) {
                    try out.appendSlice(alloc, ",\"media\":[");
                    wrote_media = true;
                } else {
                    try out.append(alloc, ',');
                }
                try out.appendSlice(alloc, "{\"mimeType\":\"");
                try appendJsonEscaped(out, alloc, att.mimeType());
                try out.appendSlice(alloc, "\",\"description\":\"");
                try appendJsonEscaped(out, alloc, att.name());
                try out.appendSlice(alloc, "\",\"uri\":\"");
                try appendJsonEscaped(out, alloc, att.path());
                try out.appendSlice(alloc, "\",\"inlineData\":\"");
                try out.appendSlice(alloc, encoded);
                try out.appendSlice(alloc, "\"}");
            }
            if (wrote_media) {
                try out.append(alloc, ']');
            }
        }

        var suffix_buf: [320]u8 = undefined;
        const suffix = try std.fmt.bufPrint(
            &suffix_buf,
            ",\"cascadeConfig\":{{\"plannerConfig\":{{\"requestedModel\":{{\"model\":\"{s}\"}},\"conversational\":{{}},\"toolConfig\":{{\"askQuestion\":{{\"enabled\":true}}}}}}}}}}",
            .{self.activeModelEnum()},
        );
        try out.appendSlice(alloc, suffix);
    }

    fn dispatchQueuedMessageRpc(self: *AgySession) bool {
        const q_att_count = @min(@as(usize, self.queued_attachment_count), self.queued_attachments.len);
        if ((self.queued_prompt_len == 0 and q_att_count == 0) or self.conv_id_len == 0) return false;
        const msg = self.queued_prompt_buf[0..self.queued_prompt_len];

        var payload: std.ArrayList(u8) = .empty;
        defer payload.deinit(std.heap.c_allocator);
        const alloc = std.heap.c_allocator;

        self.buildSendUserMessagePayload(
            msg,
            self.queued_attachments[0..q_att_count],
            &payload,
            alloc,
        ) catch return false;

        self.queued_prompt_len = 0;
        self.queued_attachment_count = 0;
        return self.beginRpcRequest(.send_message, "SendUserCascadeMessage", payload.items);
    }

    fn requestTrajectoryUpdateRpc(self: *AgySession) bool {
        if (self.conv_id_len == 0) return false;
        var body_buf: [160]u8 = undefined;
        const body = std.fmt.bufPrint(&body_buf, "{{\"cascadeId\":\"{s}\"}}", .{self.conversationId()}) catch return false;
        return self.beginRpcRequest(.get_trajectory, "GetCascadeTrajectory", body);
    }

    fn beginRpcRequest(self: *AgySession, kind: RpcKind, method: []const u8, json_body: []const u8) bool {
        self.closeSocket();
        if (!self.ensureConnected()) return false;

        const alloc = std.heap.c_allocator;
        var hdr_buf: [512]u8 = undefined;
        const hdr = std.fmt.bufPrint(
            &hdr_buf,
            "POST /exa.language_server_pb.LanguageServerService/{s} HTTP/1.1\r\n" ++
                "Host: 127.0.0.1:{d}\r\n" ++
                "Content-Type: application/json\r\n" ++
                "Content-Length: {d}\r\n" ++
                "x-codeium-csrf-token: {s}\r\n" ++
                "Connection: close\r\n\r\n",
            .{ method, self.ls_port, json_body.len, self.csrfToken() },
        ) catch return false;

        self.tx_buf.appendSlice(alloc, hdr) catch return false;
        self.tx_buf.appendSlice(alloc, json_body) catch return false;

        const fd = openLoopbackSocket(self.ls_port);
        if (fd < 0) return false;

        self.sock_fd = fd;
        self.active_rpc = kind;
        self.tx_sent = 0;
        self.rx_buf.clearRetainingCapacity();
        self.active_poll_frames = 120;
        return true;
    }

    // ========================================================================
    // Non-Blocking Socket Poll Loop
    // ========================================================================

    pub fn poll(self: *AgySession) bool {
        const now_ms: i64 = @intCast(platform.profiler.nowNs() / std.time.ns_per_ms);
        return self.pollWithHint(now_ms, false);
    }

    pub fn pollWithHint(self: *AgySession, now_ms: i64, defer_heavy_parse: bool) bool {
        var any_changed = false;

        // 1. Drive active non-blocking HTTP RPC socket
        if (self.sock_fd >= 0) {
            self.active_poll_frames = 90;

            if (self.tx_sent < self.tx_buf.items.len) {
                const rem = self.tx_buf.items[self.tx_sent..];
                const n = writeLoopbackSocket(self.sock_fd, rem.ptr, rem.len);
                if (n > 0) {
                    self.tx_sent += @intCast(n);
                }
            }

            var temp: [16384]u8 = undefined;
            var eof = (self.eof_ready_ms != 0);
            if (!eof and self.tx_sent >= self.tx_buf.items.len) {
                var loops: usize = 0;
                while (loops < 64) : (loops += 1) {
                    const n = readLoopbackSocket(self.sock_fd, &temp, temp.len);
                    if (n < 0) break;
                    if (n == 0) {
                        eof = true;
                        break;
                    }
                    const un: usize = @intCast(n);
                    self.rx_buf.appendSlice(std.heap.c_allocator, temp[0..un]) catch break;
                }
            }

            if (eof) {
                if (self.eof_ready_ms == 0) self.eof_ready_ms = now_ms;
                // If user is actively scrolling another pane right on this frame, defer trajectory parse
                // to the next non-scroll frame (up to 160ms max) so trackpad scroll frames never stall.
                if (self.active_rpc == .get_trajectory and defer_heavy_parse and now_ms - self.eof_ready_ms < 160) {
                    return false;
                }
                self.eof_ready_ms = 0;
                const completed_rpc = self.active_rpc;
                self.last_poll_ms = now_ms;
                if (self.handleCompletedHttpResponse(completed_rpc)) {
                    any_changed = true;
                }
            }
            return any_changed;
        }

        // 2. When no RPC socket is currently open and a turn is running (and not blocked waiting on user input),
        //    poll `/GetCascadeTrajectory` with wall-clock adaptive backoff (250ms active, 400ms after 2 unchanged, 650ms after 6 unchanged).
        if (self.is_running_turn and self.conv_id_len > 0 and !self.pending_question.active) {
            self.active_poll_frames = 90;
            self.poll_tick_counter +%= 1;
            const poll_interval_ms: i64 = if (self.unchanged_polls >= 6)
                650
            else if (self.unchanged_polls >= 2)
                400
            else
                250;
            const poll_interval_ticks: u32 = if (self.unchanged_polls >= 6)
                20
            else if (self.unchanged_polls >= 2)
                15
            else
                10;

            const elapsed_ok = (self.last_poll_ms == 0) or
                (now_ms - self.last_poll_ms >= poll_interval_ms) or
                (now_ms <= self.last_poll_ms and self.poll_tick_counter >= poll_interval_ticks);
            if (elapsed_ok and !defer_heavy_parse) {
                self.poll_tick_counter = 0;
                self.last_poll_ms = now_ms;
                _ = self.requestTrajectoryUpdateRpc();
            }
        } else if (self.active_poll_frames > 0) {
            self.active_poll_frames -= 1;
        }

        return any_changed;
    }

    fn handleCompletedHttpResponse(self: *AgySession, rpc_kind: RpcKind) bool {
        const raw = self.rx_buf.items;
        const hdr_end = std.mem.indexOf(u8, raw, "\r\n\r\n") orelse {
            if (raw.len == 0) {
                self.ls_port = 0;
                self.alt_port = 0;
                self.csrf_len = 0;
                self.models_attempted = false;
                self.conversations_attempted = false;
            }
            self.closeSocket();
            return false;
        };
        const headers = raw[0..hdr_end];
        const body_raw = raw[hdr_end + 4 ..];

        // Swap to `alt_port` if we hit the HTTPS listener
        if (std.mem.indexOf(u8, headers, "400 Bad Request") != null or
            std.mem.indexOf(u8, body_raw, "HTTPS server") != null)
        {
            const swapped = (self.alt_port > 0 and self.alt_port != self.ls_port);
            if (swapped) {
                const tmp = self.ls_port;
                self.ls_port = self.alt_port;
                self.alt_port = tmp;
                self.models_attempted = false;
                self.conversations_attempted = false;
            }
            self.closeSocket();
            if (swapped) {
                switch (rpc_kind) {
                    .get_models => {
                        self.models_attempted = true;
                        _ = self.beginRpcRequest(.get_models, "GetCascadeModelConfigData", "{}");
                    },
                    .list_conversations => {
                        self.conversations_attempted = true;
                        _ = self.beginRpcRequest(.list_conversations, "GetAllCascadeTrajectories", "{}");
                    },
                    .start_cascade => _ = self.startNewCascadeRpc(),
                    .send_message => _ = self.dispatchQueuedMessageRpc(),
                    .get_trajectory => _ = self.requestTrajectoryUpdateRpc(),
                    else => {},
                }
            }
            return false;
        }

        const alloc = std.heap.c_allocator;
        var unchunked = std.ArrayList(u8).empty;
        defer unchunked.deinit(alloc);

        const json_body = if (containsIgnoreCaseAscii(headers, "transfer-encoding: chunked")) blk: {
            decodeChunkedAlloc(body_raw, &unchunked, alloc);
            break :blk unchunked.items;
        } else body_raw;

        // Fast zero-copy path for `/GetCascadeTrajectory` (avoids duplicating multi-MB trajectory JSON)
        if (rpc_kind == .get_trajectory) {
            const was_loading = self.loading_conversation;
            const changed = self.parseTrajectoryResponse(json_body);
            self.closeSocket();
            if (changed) {
                return true;
            }
            if (was_loading) {
                self.loading_conversation = false;
                if (self.loadTranscriptJsonlFallback(self.conversationId())) {
                    self.scroll_to_bottom_frames = 2;
                    self.setStatus("Loaded · Offline");
                    self.ui_generation +%= 1;
                    return true;
                }
                self.setStatus("Empty conversation");
                self.ui_generation +%= 1;
                return true;
            }
            return false;
        }

        // Copy body before closing socket (which clears `rx_buf`) for RPCs that initiate follow-up requests
        const body_copy = alloc.dupe(u8, json_body) catch {
            self.closeSocket();
            return false;
        };
        defer alloc.free(body_copy);

        self.closeSocket();

        switch (rpc_kind) {
            .none, .cancel_invocation => {
                if (!self.is_running_turn and self.sock_fd < 0) self.active_poll_frames = 0;
                self.ui_generation +%= 1;
                return true;
            },
            .get_models => {
                self.parseModelConfigResponse(body_copy);
                if (self.queued_prompt_len > 0 or self.queued_attachment_count > 0) {
                    if (self.conv_id_len == 0) {
                        _ = self.startNewCascadeRpc();
                    } else {
                        _ = self.dispatchQueuedMessageRpc();
                    }
                } else if (!self.conversations_fetched and !self.conversations_attempted) {
                    self.conversations_attempted = true;
                    _ = self.beginRpcRequest(.list_conversations, "GetAllCascadeTrajectories", "{}");
                } else if (!self.is_running_turn and self.sock_fd < 0) {
                    self.active_poll_frames = 0;
                }
                self.ui_generation +%= 1;
                return true;
            },
            .list_conversations => {
                _ = self.parseConversationsResponse(body_copy);
                if (self.sock_fd < 0 and self.conversation_count < MaxConversations) {
                    _ = self.beginRpcRequest(.search_conversations, "SearchConversations", "{}");
                } else if (!self.is_running_turn and self.sock_fd < 0) {
                    self.active_poll_frames = 0;
                }
                self.ui_generation +%= 1;
                return true;
            },
            .search_conversations => {
                _ = self.parseConversationsResponse(body_copy);
                self.conversations_fetched = true;
                if (!self.is_running_turn and self.sock_fd < 0) {
                    self.active_poll_frames = 0;
                }
                self.ui_generation +%= 1;
                return true;
            },
            .start_cascade => {
                if (self.parseStartCascadeResponse(body_copy)) {
                    self.conversations_fetched = false;
                    if (self.queued_prompt_len > 0 or self.queued_attachment_count > 0) {
                        _ = self.dispatchQueuedMessageRpc();
                    }
                    self.ui_generation +%= 1;
                    return true;
                }
                self.is_running_turn = false;
                self.setStatus("Failed to start cascade");
                self.ui_generation +%= 1;
                return true;
            },
            .send_message, .answer_question => {
                self.poll_tick_counter = 8;
                self.last_poll_ms = 0;
                _ = self.requestTrajectoryUpdateRpc();
                self.ui_generation +%= 1;
                return true;
            },
            .get_trajectory => unreachable,
        }
    }

    pub fn parseModelConfigResponse(self: *AgySession, json_bytes: []const u8) void {
        defer if (!self.models_fetched) {
            self.models_attempted = false;
            self.last_connect_attempt_ms = @intCast(platform.profiler.nowNs() / std.time.ns_per_ms);
            self.active_poll_frames = @max(self.active_poll_frames, 120);
        };
        var parsed = std.json.parseFromSlice(std.json.Value, std.heap.c_allocator, json_bytes, .{}) catch return;
        defer parsed.deinit();
        if (parsed.value != .object) return;
        const root = parsed.value.object;

        if (root.get("defaultOverrideModelConfig")) |def_cfg| {
            if (def_cfg == .object) {
                if (def_cfg.object.get("modelOrAlias")) |moa| {
                    if (moa == .object) {
                        if (getJsonString(moa.object, "model")) |m_str| {
                            self.setDefaultModel(m_str);
                        }
                    }
                }
            }
        }

        if (root.get("clientModelConfigs")) |arr_val| {
            if (arr_val == .array and arr_val.array.items.len > 0) {
                var prev_enum_buf: [48]u8 = @splat(0);
                const prev_enum = self.activeModelEnum();
                const prev_len = @min(prev_enum.len, prev_enum_buf.len);
                @memcpy(prev_enum_buf[0..prev_len], prev_enum[0..prev_len]);
                const target_enum = if (self.user_picked_model)
                    prev_enum_buf[0..prev_len]
                else
                    self.default_model_buf[0..self.default_model_len];

                self.model_count = 0;
                for (arr_val.array.items) |item| {
                    if (self.model_count >= MaxModels) break;
                    if (item != .object) continue;
                    const lbl = getJsonString(item.object, "label") orelse continue;
                    const moa = item.object.get("modelOrAlias") orelse continue;
                    if (moa != .object) continue;
                    const m_enum = getJsonString(moa.object, "model") orelse continue;

                    var entry = &self.models[self.model_count];
                    entry.* = .{};
                    const l_n = @min(lbl.len, entry.label_buf.len);
                    @memcpy(entry.label_buf[0..l_n], lbl[0..l_n]);
                    entry.label_len = @intCast(l_n);

                    const e_n = @min(m_enum.len, entry.enum_buf.len);
                    @memcpy(entry.enum_buf[0..e_n], m_enum[0..e_n]);
                    entry.enum_len = @intCast(e_n);

                    if (std.mem.eql(u8, m_enum, target_enum)) {
                        self.selected_model_idx = self.model_count;
                    }
                    self.model_count += 1;
                }
                if (self.model_count > 0) {
                    self.models_fetched = true;
                }
            }
        }
    }

    pub fn parseStartCascadeResponse(self: *AgySession, json_bytes: []const u8) bool {
        var parsed = std.json.parseFromSlice(std.json.Value, std.heap.c_allocator, json_bytes, .{}) catch return false;
        defer parsed.deinit();
        if (parsed.value != .object) return false;
        const cid = getJsonString(parsed.value.object, "cascadeId") orelse return false;
        if (cid.len == 0 or cid.len >= self.conv_id_buf.len) return false;

        @memcpy(self.conv_id_buf[0..cid.len], cid);
        self.conv_id_buf[cid.len] = 0;
        self.conv_id_len = @intCast(cid.len);
        self.steps_at_send = 0;
        return true;
    }

    /// Parses `/GetAllCascadeTrajectories` (`trajectorySummaries` map) or `/SearchConversations` (`results` array)
    /// JSON, filtering out untitled internal subagent worktrees and sorting conversations by `lastModifiedTime` descending.
    pub fn parseConversationsResponse(self: *AgySession, json_bytes: []const u8) bool {
        var parsed = std.json.parseFromSlice(std.json.Value, std.heap.c_allocator, json_bytes, .{}) catch return false;
        defer parsed.deinit();
        if (parsed.value != .object) return false;
        const root = parsed.value.object;
        if (root.get("errorMessage") != null or root.get("code") != null) {
            if (self.conversation_count == 0) {
                self.conversations_attempted = false;
            }
            return false;
        }
        const is_search_results = (root.get("trajectorySummaries") == null and root.get("results") != null);
        const sums_val = root.get("trajectorySummaries") orelse root.get("results") orelse {
            self.conversations_fetched = true;
            return true;
        };

        var cwd_buf: [512]u8 = undefined;
        var active_root: []const u8 = self.syncedWorkspaceRoot();
        if (active_root.len == 0) {
            if (getcwd(&cwd_buf, cwd_buf.len)) |cz| {
                active_root = normalizeWorkspaceUriPath(std.mem.sliceTo(cz, 0));
            }
        }
        var git_root_buf: [512]u8 = undefined;
        const active_git_root = findEnclosingGitRoot(active_root, &git_root_buf);

        const alloc = std.heap.c_allocator;
        var list = std.ArrayList(ConversationSummary).empty;
        defer list.deinit(alloc);

        if (is_search_results) {
            for (self.availableConversations()) |existing| {
                list.append(alloc, existing) catch break;
            }
        }

        switch (sums_val) {
            .object => |map| {
                var it = map.iterator();
                while (it.next()) |kv| {
                    if (kv.value_ptr.* != .object) continue;
                    if (parseSingleConversationSummary(
                        kv.key_ptr.*,
                        kv.value_ptr.*.object,
                        active_root,
                        active_git_root,
                        self.conversationId(),
                    )) |summary| {
                        list.append(alloc, summary) catch break;
                    }
                }
            },
            .array => |arr| {
                for (arr.items) |item| {
                    if (item != .object) continue;
                    const cid = getJsonString(item.object, "cascadeId") orelse
                        getJsonString(item.object, "trajectoryId") orelse continue;
                    const trimmed_cid = std.mem.trim(u8, cid, " \t\r\n");
                    var already_exists = false;
                    for (list.items) |*existing| {
                        if (std.mem.eql(u8, existing.id(), trimmed_cid)) {
                            already_exists = true;
                            break;
                        }
                    }
                    if (already_exists) continue;
                    if (parseSingleConversationSummary(
                        trimmed_cid,
                        item.object,
                        active_root,
                        active_git_root,
                        self.conversationId(),
                    )) |summary| {
                        list.append(alloc, summary) catch break;
                    }
                }
            },
            else => return false,
        }

        // Sort descending by ISO-8601 `modifiedTime()` (most recent conversations first)
        if (list.items.len > 1) {
            var i: usize = 1;
            while (i < list.items.len) : (i += 1) {
                const cur = list.items[i];
                var j: usize = i;
                while (j > 0 and std.mem.order(u8, cur.modifiedTime(), list.items[j - 1].modifiedTime()) == .gt) : (j -= 1) {
                    list.items[j] = list.items[j - 1];
                }
                list.items[j] = cur;
            }
        }

        const count = @min(list.items.len, MaxConversations);
        for (0..count) |idx| {
            self.conversations[idx] = list.items[idx];
            if (self.conv_id_len > 0 and std.mem.eql(u8, list.items[idx].id(), self.conversationId())) {
                if (self.active_title_len == 0 and list.items[idx].title_len > 0) {
                    self.setActiveTitle(list.items[idx].title());
                }
            }
        }
        self.conversation_count = count;
        self.conversations_fetched = true;
        return true;
    }

    /// Parses `/GetCascadeTrajectory` JSON and rebuilds the live Markdown transcript,
    /// active tool badge, pending user question cards, and token usage telemetry.
    /// Uses a zero-DOM single-pass `JsonWalker` that skips huge ignored tool outputs (`viewFile`,
    /// `readFile`, `editFile`, `grepSearch`, `cortexMemory`, `checkpoint`) in O(1) memory.
    pub fn parseTrajectoryResponse(self: *AgySession, json_bytes: []const u8) bool {
        const raw_hash = std.hash.Wyhash.hash(0, json_bytes);
        const body_hash: u64 = if (raw_hash == 0) 1 else raw_hash;
        if (!self.loading_conversation and body_hash == self.last_trajectory_hash) {
            self.unchanged_polls = @min(self.unchanged_polls + 1, 1000);
            return false;
        }
        const prev_digest = self.computeVisibleStateDigest();
        const prev_entry_count = self.entry_count;
        const prev_transcript_len = self.transcript_len;

        var w = JsonWalker{ .src = json_bytes };
        if (!w.expectChar('{')) return false;

        var run_status_buf: [64]u8 = undefined;
        var run_status: []const u8 = "";
        var root_traj_id_buf: [64]u8 = undefined;
        var root_traj_id: []const u8 = self.conversationId();

        const was_loading_conversation = self.loading_conversation;
        var parsed_steps_array = false;
        var total_in: u64 = 0;
        var total_out: u64 = 0;
        var total_think: u64 = 0;
        var total_cache: u64 = 0;
        var any_generating = false;
        var waiting_for_user = false;
        var step_count: usize = 0;

        while (true) {
            w.skipWs();
            if (w.pos >= w.src.len) return false;
            if (w.src[w.pos] == '}') {
                w.pos += 1;
                break;
            }
            if (w.src[w.pos] == ',') {
                w.pos += 1;
                continue;
            }
            var key_buf: [64]u8 = undefined;
            const key = w.readStringFixed(&key_buf) orelse return false;
            if (!w.expectChar(':')) return false;

            if (std.mem.eql(u8, key, "status")) {
                run_status = w.readStringFixed(&run_status_buf) orelse blk: {
                    if (!w.skipValue()) return false;
                    break :blk "";
                };
            } else if (std.mem.eql(u8, key, "trajectory")) {
                if (!w.expectChar('{')) {
                    if (!w.skipValue()) return false;
                    continue;
                }
                while (true) {
                    w.skipWs();
                    if (w.pos >= w.src.len) return false;
                    if (w.src[w.pos] == '}') {
                        w.pos += 1;
                        break;
                    }
                    if (w.src[w.pos] == ',') {
                        w.pos += 1;
                        continue;
                    }
                    var tkey_buf: [64]u8 = undefined;
                    const tkey = w.readStringFixed(&tkey_buf) orelse return false;
                    if (!w.expectChar(':')) return false;

                    if (std.mem.eql(u8, tkey, "trajectoryId")) {
                        const tid = w.readStringFixed(&root_traj_id_buf) orelse blk: {
                            if (!w.skipValue()) return false;
                            break :blk "";
                        };
                        if (tid.len > 0) root_traj_id = tid;
                    } else if (std.mem.eql(u8, tkey, "steps")) {
                        if (!w.expectChar('[')) {
                            if (!w.skipValue()) return false;
                            continue;
                        }
                        parsed_steps_array = true;
                        w.skipWs();
                        if (w.pos < w.src.len and w.src[w.pos] == ']') {
                            w.pos += 1;
                            if (was_loading_conversation) {
                                self.loading_conversation = false;
                                self.is_running_turn = false;
                                self.setStatus("Empty conversation");
                            }
                            return false;
                        }

                        self.loading_conversation = false;
                        self.last_trajectory_hash = body_hash;
                        self.transcript_len = 0;
                        self.entry_count = 0;
                        self.active_tool_len = 0;

                        while (true) {
                            w.skipWs();
                            if (w.pos >= w.src.len) break;
                            if (w.src[w.pos] == ']') {
                                w.pos += 1;
                                break;
                            }
                            if (w.src[w.pos] == ',') {
                                w.pos += 1;
                                continue;
                            }
                            const idx = step_count;
                            step_count += 1;

                            if (!self.parseSingleTrajectoryStepFast(
                                &w,
                                root_traj_id,
                                idx,
                                &total_in,
                                &total_out,
                                &total_think,
                                &total_cache,
                                &any_generating,
                                &waiting_for_user,
                            )) return false;
                        }
                    } else {
                        if (!w.skipValue()) return false;
                    }
                }
            } else {
                if (!w.skipValue()) return false;
            }
        }

        if (!parsed_steps_array or step_count == 0) return false;
        if (self.last_sent_media_len > 0 and self.entry_count > 0) {
            var idx_rev: usize = self.entry_count;
            while (idx_rev > 0) {
                idx_rev -= 1;
                if (self.entries[idx_rev].kind == .user_prompt) {
                    if (self.entries[idx_rev].aux_start == self.entries[idx_rev].aux_end) {
                        const fallback_media = self.last_sent_media_buf[0..@min(@as(usize, self.last_sent_media_len), self.last_sent_media_buf.len)];
                        if (self.transcript_len + fallback_media.len <= TranscriptCapacity) {
                            const a_start: u32 = @intCast(self.transcript_len);
                            self.appendTranscript(fallback_media);
                            const a_end: u32 = @intCast(self.transcript_len);
                            self.entries[idx_rev].aux_start = a_start;
                            self.entries[idx_rev].aux_end = a_end;
                        }
                    }
                    break;
                }
            }
        }
        if (waiting_for_user and root_traj_id.len > 0) {
            self.pending_question.setTrajectoryId(root_traj_id);
        }

        const is_running = std.mem.eql(u8, run_status, "CASCADE_RUN_STATUS_RUNNING");
        if (is_running) {
            self.seen_running_status = true;
        }

        if (!waiting_for_user and self.pending_question.active) {
            self.pending_question.active = false;
        }

        self.usage = .{
            .input_tokens = total_in,
            .output_tokens = total_out,
            .thinking_tokens = total_think,
            .cache_read_tokens = total_cache,
            .total_tokens = total_in + total_out + total_think,
        };

        if (was_loading_conversation) {
            self.steps_at_send = step_count;
            self.scroll_to_bottom_frames = 2;
            if (waiting_for_user) {
                self.is_running_turn = true;
                self.setActiveTool("Waiting for your response");
                self.setStatus("Waiting for your response...");
            } else if (is_running or any_generating) {
                self.is_running_turn = true;
                if (self.active_tool_len > 0) {
                    self.setStatus(self.activeToolText());
                } else {
                    self.setStatus("Thinking...");
                }
            } else {
                self.is_running_turn = false;
                self.active_tool_len = 0;
                self.setStatus("Loaded · Ready");
            }
            self.unchanged_polls = 0;
            self.ui_generation +%= 1;
            return true;
        }

        if (waiting_for_user) {
            self.is_running_turn = true;
            self.setActiveTool("Waiting for your response");
            self.setStatus("Waiting for your response...");
        } else if (!is_running and !any_generating and (self.seen_running_status or step_count > self.steps_at_send + 1)) {
            self.is_running_turn = false;
            self.steps_at_send = step_count;
            self.active_tool_len = 0;
            self.turn_completed_flag = true;
            self.conversations_fetched = false;
            self.setStatus("Completed");
        } else if (is_running or any_generating) {
            if (self.active_tool_len > 0) {
                self.setStatus(self.activeToolText());
            } else {
                self.setStatus("Thinking...");
            }
        }

        const new_digest = self.computeVisibleStateDigest();
        if (!self.turn_completed_flag and new_digest == prev_digest) {
            self.unchanged_polls = @min(self.unchanged_polls + 1, 1000);
            return false;
        }
        if (self.entry_count != prev_entry_count or self.transcript_len != prev_transcript_len or self.turn_completed_flag) {
            self.scroll_to_bottom_frames = @max(self.scroll_to_bottom_frames, 2);
        }
        self.unchanged_polls = 0;
        self.ui_generation +%= 1;
        return true;
    }

    fn parseSingleTrajectoryStepFast(
        self: *AgySession,
        w: *JsonWalker,
        root_traj_id: []const u8,
        idx: usize,
        total_in: *u64,
        total_out: *u64,
        total_think: *u64,
        total_cache: *u64,
        any_generating: *bool,
        waiting_for_user: *bool,
    ) bool {
        w.skipWs();
        const step_start = w.pos;
        if (!w.expectChar('{')) return false;

        var step_type_buf: [64]u8 = undefined;
        var step_type: []const u8 = "";
        var step_status_buf: [64]u8 = undefined;
        var step_status: []const u8 = "";

        var user_input_slice: ?[]const u8 = null;
        var planner_resp_slice: ?[]const u8 = null;
        var run_cmd_slice: ?[]const u8 = null;
        var err_msg_slice: ?[]const u8 = null;
        var meta_args_slice: ?[]const u8 = null;

        while (true) {
            w.skipWs();
            if (w.pos >= w.src.len) return false;
            if (w.src[w.pos] == '}') {
                w.pos += 1;
                break;
            }
            if (w.src[w.pos] == ',') {
                w.pos += 1;
                continue;
            }
            var kbuf: [64]u8 = undefined;
            const key = w.readStringFixed(&kbuf) orelse return false;
            if (!w.expectChar(':')) return false;

            if (std.mem.eql(u8, key, "type")) {
                step_type = w.readStringFixed(&step_type_buf) orelse blk: {
                    if (!w.skipValue()) return false;
                    break :blk "";
                };
            } else if (std.mem.eql(u8, key, "status")) {
                step_status = w.readStringFixed(&step_status_buf) orelse blk: {
                    if (!w.skipValue()) return false;
                    break :blk "";
                };
            } else if (std.mem.eql(u8, key, "metadata")) {
                parseStepMetadataFast(w, total_in, total_out, total_think, total_cache, &meta_args_slice);
            } else if (std.mem.eql(u8, key, "userInput")) {
                user_input_slice = w.captureValueSlice() orelse return false;
            } else if (std.mem.eql(u8, key, "plannerResponse")) {
                planner_resp_slice = w.captureValueSlice() orelse return false;
            } else if (std.mem.eql(u8, key, "runCommand")) {
                run_cmd_slice = w.captureValueSlice() orelse return false;
            } else if (std.mem.eql(u8, key, "errorMessage")) {
                err_msg_slice = w.captureValueSlice() orelse return false;
            } else {
                // Skip huge ignored fields (`viewFile`, `readFile`, `editFile`, `grepSearch`, `cortexMemory`, `checkpoint`, etc.)
                if (!w.skipValue()) return false;
            }
        }
        const step_raw = w.src[step_start..w.pos];

        if (std.mem.eql(u8, step_status, "CORTEX_STEP_STATUS_GENERATING") or
            std.mem.eql(u8, step_status, "CORTEX_STEP_STATUS_RUNNING") or
            std.mem.eql(u8, step_status, "CORTEX_STEP_STATUS_PENDING") or
            std.mem.eql(u8, step_status, "CORTEX_STEP_STATUS_WAITING"))
        {
            any_generating.* = true;
        }

        const alloc = std.heap.c_allocator;

        if (std.mem.eql(u8, step_type, "CORTEX_STEP_TYPE_USER_INPUT")) {
            if (user_input_slice) |ui_raw| {
                var media_buf: [1024]u8 = undefined;
                const media_paths = extractUserPromptMediaFast(ui_raw, &media_buf);
                self.json_scratch.clearRetainingCapacity();
                const raw_text = extractUserPromptTextFast(ui_raw, &self.json_scratch, alloc) orelse "";
                const clean_text = stripUserRequestWrapper(raw_text);
                if (clean_text.len > 0 or media_paths.len > 0) {
                    self.pushChatEntry(.user_prompt, clean_text, media_paths);
                }
            }
        } else if (std.mem.eql(u8, step_type, "CORTEX_STEP_TYPE_PLANNER_RESPONSE")) {
            if (planner_resp_slice) |pr_raw| {
                self.parsePlannerResponseFast(pr_raw, step_status);
            }
        } else if (std.mem.eql(u8, step_type, "CORTEX_STEP_TYPE_RUN_COMMAND")) {
            if (run_cmd_slice) |rc_raw| {
                self.parseRunCommandFast(rc_raw, step_status, meta_args_slice);
            }
        } else if (std.mem.eql(u8, step_type, "CORTEX_STEP_TYPE_ASK_QUESTION")) {
            var parsed_step = std.json.parseFromSlice(std.json.Value, alloc, step_raw, .{}) catch return true;
            defer parsed_step.deinit();
            if (parsed_step.value == .object) {
                if (self.handleAskQuestionStep(parsed_step.value.object, root_traj_id, @intCast(idx))) {
                    waiting_for_user.* = true;
                    any_generating.* = true;
                }
            }
        } else if (std.mem.eql(u8, step_type, "CORTEX_STEP_TYPE_ERROR_MESSAGE")) {
            if (err_msg_slice) |em_raw| {
                var err_buf: [512]u8 = undefined;
                const err_txt = extractErrorMessageFast(em_raw, &err_buf);
                if (err_txt.len > 0) {
                    self.pushChatEntry(.error_banner, err_txt, "");
                    self.setStatus(err_txt);
                }
            }
        }
        return true;
    }

    fn parsePlannerResponseFast(self: *AgySession, pr_raw: []const u8, step_status: []const u8) void {
        var w = JsonWalker{ .src = pr_raw };
        if (!w.expectChar('{')) return;

        var thinking_val_slice: ?[]const u8 = null;
        var dur_buf: [48]u8 = undefined;
        var raw_dur: []const u8 = "";
        var tool_calls_slice: ?[]const u8 = null;
        var mod_resp_slice: ?[]const u8 = null;
        var resp_slice: ?[]const u8 = null;

        while (true) {
            w.skipWs();
            if (w.pos >= w.src.len or w.src[w.pos] == '}') break;
            if (w.src[w.pos] == ',') {
                w.pos += 1;
                continue;
            }
            var kbuf: [64]u8 = undefined;
            const key = w.readStringFixed(&kbuf) orelse return;
            if (!w.expectChar(':')) return;

            if (std.mem.eql(u8, key, "thinking")) {
                thinking_val_slice = w.captureValueSlice();
            } else if (std.mem.eql(u8, key, "thinkingDuration")) {
                raw_dur = w.readStringFixed(&dur_buf) orelse blk: {
                    _ = w.skipValue();
                    break :blk "";
                };
            } else if (std.mem.eql(u8, key, "toolCalls")) {
                tool_calls_slice = w.captureValueSlice();
            } else if (std.mem.eql(u8, key, "modifiedResponse")) {
                mod_resp_slice = w.captureValueSlice();
            } else if (std.mem.eql(u8, key, "response")) {
                resp_slice = w.captureValueSlice();
            } else {
                if (!w.skipValue()) return;
            }
        }

        const alloc = std.heap.c_allocator;

        if (thinking_val_slice) |ts| {
            var tw = JsonWalker{ .src = ts };
            self.json_scratch.clearRetainingCapacity();
            if (tw.readStringScratch(&self.json_scratch, alloc, TranscriptCapacity / 2)) |raw_thinking| {
                const clean_thinking = std.mem.trim(u8, raw_thinking, " \t\r\n");
                if (clean_thinking.len > 0) {
                    const step_generating = std.mem.eql(u8, step_status, "CORTEX_STEP_STATUS_GENERATING") or
                        std.mem.eql(u8, step_status, "CORTEX_STEP_STATUS_RUNNING") or
                        std.mem.eql(u8, step_status, "CORTEX_STEP_STATUS_PENDING");
                    var dur_label_buf: [48]u8 = undefined;
                    const dur_label = formatThinkingDurationLabel(raw_dur, step_generating, &dur_label_buf);
                    self.pushChatEntry(.thinking, clean_thinking, dur_label);
                }
            }
        }

        if (tool_calls_slice) |tcs| {
            var aw = JsonWalker{ .src = tcs };
            if (aw.expectChar('[')) {
                while (true) {
                    aw.skipWs();
                    if (aw.pos >= aw.src.len or aw.src[aw.pos] == ']') break;
                    if (aw.src[aw.pos] == ',') {
                        aw.pos += 1;
                        continue;
                    }
                    const tc_obj_slice = aw.captureValueSlice() orelse break;
                    var ow = JsonWalker{ .src = tc_obj_slice };
                    if (!ow.expectChar('{')) continue;

                    var t_name_buf: [64]u8 = undefined;
                    var t_name: []const u8 = "tool";
                    var args_val_slice: ?[]const u8 = null;

                    while (true) {
                        ow.skipWs();
                        if (ow.pos >= ow.src.len or ow.src[ow.pos] == '}') break;
                        if (ow.src[ow.pos] == ',') {
                            ow.pos += 1;
                            continue;
                        }
                        var tkbuf: [48]u8 = undefined;
                        const tkey = ow.readStringFixed(&tkbuf) orelse break;
                        if (!ow.expectChar(':')) break;

                        if (std.mem.eql(u8, tkey, "name")) {
                            t_name = ow.readStringFixed(&t_name_buf) orelse blk: {
                                _ = ow.skipValue();
                                break :blk "tool";
                            };
                        } else if (std.mem.eql(u8, tkey, "argumentsJson")) {
                            args_val_slice = ow.captureValueSlice();
                        } else {
                            if (!ow.skipValue()) break;
                        }
                    }

                    self.json_scratch.clearRetainingCapacity();
                    const args_json: []const u8 = if (args_val_slice) |avs| blk: {
                        var argw = JsonWalker{ .src = avs };
                        break :blk argw.readStringScratch(&self.json_scratch, alloc, 4096) orelse "";
                    } else "";

                    var summary_buf: [128]u8 = undefined;
                    const summary = extractToolArgsSummary(args_json, &summary_buf);

                    if (std.mem.eql(u8, t_name, "run_command")) {
                        var cmd_buf: [512]u8 = undefined;
                        const cmd_line = extractCommandLineFromArgsJson(args_json, &cmd_buf);
                        const prim = if (cmd_line.len > 0) cmd_line else summary;
                        const aux = if (summary.len > 0) summary else cmd_line;
                        self.pushChatEntry(.shell_command, prim, aux);
                    } else {
                        self.pushChatEntry(.tool_call, t_name, summary);
                    }

                    var badge_buf: [128]u8 = undefined;
                    const badge = if (summary.len > 0)
                        std.fmt.bufPrint(&badge_buf, "{s}: {s}", .{ t_name, summary }) catch t_name
                    else
                        t_name;
                    self.setActiveTool(badge);
                }
            }
        }

        const chosen_resp_slice = mod_resp_slice orelse resp_slice;
        if (chosen_resp_slice) |rs| {
            var rw = JsonWalker{ .src = rs };
            self.json_scratch.clearRetainingCapacity();
            var resp_text = rw.readStringScratch(&self.json_scratch, alloc, TranscriptCapacity / 2) orelse "";
            if (resp_text.len == 0 and mod_resp_slice != null and resp_slice != null) {
                var rw2 = JsonWalker{ .src = resp_slice.? };
                self.json_scratch.clearRetainingCapacity();
                resp_text = rw2.readStringScratch(&self.json_scratch, alloc, TranscriptCapacity / 2) orelse "";
            }
            if (resp_text.len > 0) {
                self.pushChatEntry(.assistant_markdown, resp_text, "");
            }
        }
    }

    fn parseRunCommandFast(
        self: *AgySession,
        rc_raw: []const u8,
        step_status: []const u8,
        meta_args_slice: ?[]const u8,
    ) void {
        var w = JsonWalker{ .src = rc_raw };
        if (!w.expectChar('{')) return;

        var cmd_buf: [512]u8 = undefined;
        var cmd_line: []const u8 = "";
        var prop_cmd_buf: [512]u8 = undefined;
        var prop_cmd_line: []const u8 = "";
        var full_out_slice: ?[]const u8 = null;
        var trunc_out_slice: ?[]const u8 = null;
        var direct_out_slice: ?[]const u8 = null;
        var parsed_exit: ?i16 = null;

        while (true) {
            w.skipWs();
            if (w.pos >= w.src.len or w.src[w.pos] == '}') break;
            if (w.src[w.pos] == ',') {
                w.pos += 1;
                continue;
            }
            var kbuf: [64]u8 = undefined;
            const key = w.readStringFixed(&kbuf) orelse return;
            if (!w.expectChar(':')) return;

            if (std.mem.eql(u8, key, "commandLine")) {
                cmd_line = w.readStringFixed(&cmd_buf) orelse blk: {
                    _ = w.skipValue();
                    break :blk "";
                };
            } else if (std.mem.eql(u8, key, "proposedCommandLine")) {
                prop_cmd_line = w.readStringFixed(&prop_cmd_buf) orelse blk: {
                    _ = w.skipValue();
                    break :blk "";
                };
            } else if (std.mem.eql(u8, key, "combinedOutput")) {
                if (w.expectChar('{')) {
                    while (true) {
                        w.skipWs();
                        if (w.pos >= w.src.len) break;
                        if (w.src[w.pos] == '}') {
                            w.pos += 1;
                            break;
                        }
                        if (w.src[w.pos] == ',') {
                            w.pos += 1;
                            continue;
                        }
                        var ckbuf: [48]u8 = undefined;
                        const ckey = w.readStringFixed(&ckbuf) orelse break;
                        if (!w.expectChar(':')) break;
                        if (std.mem.eql(u8, ckey, "full")) {
                            full_out_slice = w.captureValueSlice();
                        } else if (std.mem.eql(u8, ckey, "truncated")) {
                            trunc_out_slice = w.captureValueSlice();
                        } else {
                            if (!w.skipValue()) break;
                        }
                    }
                } else {
                    if (!w.skipValue()) return;
                }
            } else if (std.mem.eql(u8, key, "output")) {
                direct_out_slice = w.captureValueSlice();
            } else if (std.mem.eql(u8, key, "exitCode")) {
                if (w.readInt()) |n| {
                    parsed_exit = @intCast(std.math.clamp(n, -1, 32767));
                }
            } else {
                if (!w.skipValue()) return;
            }
        }

        const effective_cmd = if (cmd_line.len > 0) cmd_line else prop_cmd_line;
        const alloc = std.heap.c_allocator;

        var summary_buf: [128]u8 = undefined;
        var summary: []const u8 = "";
        if (meta_args_slice) |mas| {
            self.json_scratch.clearRetainingCapacity();
            var mw = JsonWalker{ .src = mas };
            const args_json = mw.readStringScratch(&self.json_scratch, alloc, 4096) orelse "";
            summary = extractToolArgsSummary(args_json, &summary_buf);
        }

        // Only unescape up to 8192 bytes of command output (since `attachShellCommandResult` clamps to 4096 bytes)
        self.json_scratch.clearRetainingCapacity();
        const chosen_out_slice = full_out_slice orelse trunc_out_slice orelse direct_out_slice;
        var raw_out: []const u8 = "";
        if (chosen_out_slice) |cos| {
            var ow = JsonWalker{ .src = cos };
            raw_out = ow.readStringScratch(&self.json_scratch, alloc, 8192) orelse "";
        }
        if (raw_out.len == 0 and full_out_slice != null and trunc_out_slice != null) {
            var ow2 = JsonWalker{ .src = trunc_out_slice.? };
            self.json_scratch.clearRetainingCapacity();
            raw_out = ow2.readStringScratch(&self.json_scratch, alloc, 8192) orelse "";
        }

        const clean_out = cleanShellCommandOutput(raw_out, &parsed_exit);
        const step_done = std.mem.eql(u8, step_status, "CORTEX_STEP_STATUS_DONE") or
            std.mem.eql(u8, step_status, "CORTEX_STEP_STATUS_ERROR") or
            std.mem.eql(u8, step_status, "CORTEX_STEP_STATUS_CANCELED");
        const exit_code: i16 = parsed_exit orelse (if (step_done) 0 else -1);

        self.attachShellCommandResult(effective_cmd, summary, clean_out, exit_code);
    }

    /// Offline fallback reader for `~/.gemini/antigravity/brain/<cascade_id>/.system_generated/logs/transcript.jsonl`
    /// (and `~/.gemini/antigravity-cli/brain/<cascade_id>/.system_generated/logs/transcript.jsonl`)
    /// when the local language server hub is not running or cannot load an archived trajectory.
    pub fn loadTranscriptJsonlFallback(self: *AgySession, cascade_id: []const u8) bool {
        if (cascade_id.len == 0 or cascade_id.len > 64) return false;
        const home_z = platform.fs_util.getenv("HOME") orelse platform.fs_util.getenv("USERPROFILE") orelse return false;
        const home = std.mem.sliceTo(home_z, 0);
        if (home.len == 0) return false;

        var path_buf: [512:0]u8 = @splat(0);
        const path = std.fmt.bufPrint(
            path_buf[0 .. path_buf.len - 1],
            "{s}/.gemini/antigravity/brain/{s}/.system_generated/logs/transcript.jsonl",
            .{ home, cascade_id },
        ) catch return false;
        path_buf[path.len] = 0;

        const fp = std.c.fopen(&path_buf, "rb") orelse blk: {
            const cli_path = std.fmt.bufPrint(
                path_buf[0 .. path_buf.len - 1],
                "{s}/.gemini/antigravity-cli/brain/{s}/.system_generated/logs/transcript.jsonl",
                .{ home, cascade_id },
            ) catch return false;
            path_buf[cli_path.len] = 0;
            break :blk std.c.fopen(&path_buf, "rb") orelse return false;
        };
        defer _ = std.c.fclose(fp);

        self.transcript_len = 0;
        self.entry_count = 0;
        self.active_tool_len = 0;
        var total_in: u64 = 0;
        var total_out: u64 = 0;
        var total_cache: u64 = 0;
        var parsed_any = false;

        var line_buf: [32768]u8 = undefined;
        while (fgets(&line_buf, @intCast(line_buf.len), fp) != null) {
            const line = std.mem.trim(u8, std.mem.sliceTo(&line_buf, 0), " \t\r\n");
            if (line.len == 0) continue;

            var parsed = std.json.parseFromSlice(std.json.Value, std.heap.c_allocator, line, .{}) catch continue;
            defer parsed.deinit();
            if (parsed.value != .object) continue;
            const step = parsed.value.object;

            const step_type = getJsonString(step, "type") orelse "";
            total_in += getJsonUint(step, "input_tokens");
            total_out += getJsonUint(step, "output_tokens");
            total_cache += getJsonUint(step, "cache_read_tokens");

            if (std.mem.eql(u8, step_type, "USER_INPUT")) {
                var media_buf: [1024]u8 = undefined;
                const media_paths = extractJsonStepMediaPaths(step, &media_buf);
                const raw_c = getJsonString(step, "content") orelse "";
                const clean = stripUserRequestWrapper(raw_c);
                if (clean.len > 0 or media_paths.len > 0) {
                    self.pushChatEntry(.user_prompt, clean, media_paths);
                    parsed_any = true;
                }
            } else if (std.mem.eql(u8, step_type, "PLANNER_RESPONSE")) {
                const raw_thinking = getJsonString(step, "thinking") orelse "";
                const clean_thinking = std.mem.trim(u8, raw_thinking, " \t\r\n");
                if (clean_thinking.len > 0) {
                    const raw_dur = getJsonString(step, "thinking_duration") orelse
                        getJsonString(step, "thinkingDuration") orelse "";
                    var dur_label_buf: [48]u8 = undefined;
                    const dur_label = formatThinkingDurationLabel(raw_dur, false, &dur_label_buf);
                    self.pushChatEntry(.thinking, clean_thinking, dur_label);
                    parsed_any = true;
                }
                if (step.get("tool_calls")) |tc_arr| {
                    if (tc_arr == .array) {
                        for (tc_arr.array.items) |tc_val| {
                            if (tc_val != .object) continue;
                            const t_name = getJsonString(tc_val.object, "name") orelse "tool";
                            var summary_buf: [128]u8 = undefined;
                            var summary: []const u8 = "";
                            var cmd_buf: [512]u8 = undefined;
                            var cmd_line: []const u8 = "";
                            if (tc_val.object.get("args")) |args_val| {
                                if (args_val == .object) {
                                    summary = extractToolArgsSummaryFromObject(args_val.object, &summary_buf);
                                    cmd_line = extractCommandLineFromObject(args_val.object, &cmd_buf);
                                }
                            }
                            if (std.mem.eql(u8, t_name, "run_command")) {
                                const prim = if (cmd_line.len > 0) cmd_line else summary;
                                const aux = if (summary.len > 0) summary else cmd_line;
                                self.pushChatEntry(.shell_command, prim, aux);
                            } else {
                                self.pushChatEntry(.tool_call, t_name, summary);
                            }
                            parsed_any = true;
                        }
                    }
                }
                const content = getJsonString(step, "content") orelse "";
                if (content.len > 0) {
                    self.pushChatEntry(.assistant_markdown, content, "");
                    parsed_any = true;
                }
            } else if (std.mem.eql(u8, step_type, "GENERIC")) {
                const raw_c = getJsonString(step, "content") orelse "";
                if (std.mem.indexOf(u8, raw_c, "Command exited with code ") != null or
                    std.mem.indexOf(u8, raw_c, "Command output:\n") != null)
                {
                    var parsed_exit: ?i16 = null;
                    const clean_out = cleanShellCommandOutput(raw_c, &parsed_exit);
                    self.attachShellCommandResult("", "", clean_out, parsed_exit orelse 0);
                }
            }
        }

        if (parsed_any) {
            self.usage = .{
                .input_tokens = total_in,
                .output_tokens = total_out,
                .thinking_tokens = 0,
                .cache_read_tokens = total_cache,
                .total_tokens = total_in + total_out,
            };
        }
        return parsed_any;
    }

    /// Parses a `CORTEX_STEP_TYPE_ASK_QUESTION` step.
    /// Returns `true` if the step is currently waiting on user input (`pending_question.active = true`).
    fn handleAskQuestionStep(self: *AgySession, step: std.json.ObjectMap, root_traj_id: []const u8, fallback_idx: u32) bool {
        const step_status = getJsonString(step, "status") orelse "";
        var step_idx: u32 = fallback_idx;
        var traj_id: []const u8 = root_traj_id;

        var args_json_fallback: []const u8 = "";
        if (step.get("metadata")) |meta_val| {
            if (meta_val == .object) {
                if (meta_val.object.get("sourceTrajectoryStepInfo")) |st_info| {
                    if (st_info == .object) {
                        if (getJsonString(st_info.object, "trajectoryId")) |tid| {
                            if (tid.len > 0) traj_id = tid;
                        }
                        if (st_info.object.get("stepIndex") != null) {
                            step_idx = @intCast(getJsonUint(st_info.object, "stepIndex"));
                        }
                    }
                }
                if (meta_val.object.get("toolCall")) |tc_val| {
                    if (tc_val == .object) {
                        args_json_fallback = getJsonString(tc_val.object, "argumentsJson") orelse "";
                    }
                }
            }
        }

        var completed_responses_arr: ?[]const std.json.Value = null;
        var request_questions_arr: ?[]const std.json.Value = null;
        if (step.get("completedInteractions")) |ci_val| {
            if (ci_val == .array and ci_val.array.items.len > 0) {
                const first_ci = ci_val.array.items[0];
                if (first_ci == .object) {
                    if (first_ci.object.get("response")) |resp_val| {
                        if (resp_val == .object) {
                            if (resp_val.object.get("askQuestion")) |aq_val| {
                                if (aq_val == .object) {
                                    if (aq_val.object.get("responses")) |r_arr| {
                                        if (r_arr == .array) completed_responses_arr = r_arr.array.items;
                                    }
                                }
                            }
                        }
                    }
                    if (first_ci.object.get("request")) |req_val| {
                        if (req_val == .object) {
                            if (req_val.object.get("askQuestion")) |aq_val| {
                                if (aq_val == .object) {
                                    if (aq_val.object.get("questions")) |q_arr| {
                                        if (q_arr == .array) request_questions_arr = q_arr.array.items;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        if (request_questions_arr == null) {
            if (step.get("askQuestion")) |aq_val| {
                if (aq_val == .object) {
                    if (aq_val.object.get("questions")) |q_arr| {
                        if (q_arr == .array) request_questions_arr = q_arr.array.items;
                    }
                }
            }
        }
        if (request_questions_arr == null) {
            if (step.get("requestedInteraction")) |ri_val| {
                if (ri_val == .object) {
                    if (ri_val.object.get("askQuestion")) |aq_val| {
                        if (aq_val == .object) {
                            if (aq_val.object.get("questions")) |q_arr| {
                                if (q_arr == .array) request_questions_arr = q_arr.array.items;
                            }
                        }
                    }
                }
            }
        }

        const step_done = std.mem.eql(u8, step_status, "CORTEX_STEP_STATUS_DONE") or
            std.mem.eql(u8, step_status, "CORTEX_STEP_STATUS_CANCELED") or
            std.mem.eql(u8, step_status, "CORTEX_STEP_STATUS_ERROR") or
            std.mem.eql(u8, step_status, "CORTEX_STEP_STATUS_INVALID");
        const has_completed = (completed_responses_arr != null);
        const already_submitted_locally = (self.pending_question.submitted and self.pending_question.step_index == step_idx);

        // 1. Completed or locally submitted question step -> render Q&A summary in transcript
        if (step_done or has_completed or already_submitted_locally) {
            if ((step_done or has_completed) and self.pending_question.step_index == step_idx) {
                self.pending_question.active = false;
                self.pending_question.submitted = false;
            }
            const source_items = completed_responses_arr orelse request_questions_arr;
            if (source_items) |items| {
                var md_buf: [2048]u8 = undefined;
                const md = if (already_submitted_locally and !has_completed and !step_done)
                    formatLocalQuestionAnswerSummary(&self.pending_question, &md_buf)
                else
                    formatJsonQuestionAnswerSummary(items, &md_buf);
                if (md.len > 0) {
                    self.pushChatEntry(.user_prompt, md, "");
                }
            } else if (already_submitted_locally) {
                var md_buf: [2048]u8 = undefined;
                const md = formatLocalQuestionAnswerSummary(&self.pending_question, &md_buf);
                if (md.len > 0) {
                    self.pushChatEntry(.user_prompt, md, "");
                }
            }
            return false;
        }

        // 2. Active waiting question step -> populate `self.pending_question` (preserving any user selections for same step_idx)
        const preserve_existing = (self.pending_question.active and self.pending_question.step_index == step_idx and self.pending_question.question_count > 0);
        if (!preserve_existing) {
            var new_group: PendingQuestionGroup = .{
                .active = true,
                .submitted = false,
                .step_index = step_idx,
            };
            new_group.setTrajectoryId(traj_id);

            if (request_questions_arr) |q_items| {
                populateQuestionsFromJsonSlice(&new_group, q_items);
            } else if (args_json_fallback.len > 0) {
                populateQuestionsFromToolArgsJson(&new_group, args_json_fallback);
            }

            if (new_group.question_count > 0) {
                self.pending_question = new_group;
            } else {
                return false;
            }
        } else {
            self.pending_question.setTrajectoryId(traj_id);
        }

        self.pushChatEntry(.question_prompt, "The agent has a question for you", "");
        return true;
    }
};

fn populateQuestionsFromJsonSlice(group: *PendingQuestionGroup, q_items: []const std.json.Value) void {
    group.question_count = 0;
    for (q_items) |q_val| {
        if (group.question_count >= MaxQuestionsPerStep) break;
        if (q_val != .object) continue;
        const q_obj = q_val.object;
        const q_text = getJsonString(q_obj, "question") orelse continue;

        var item = &group.questions[group.question_count];
        item.* = .{};
        item.setQuestion(std.mem.trim(u8, q_text, " \t\r\n"));
        item.is_multi_select = getJsonBool(q_obj, "isMultiSelect") orelse
            getJsonBool(q_obj, "is_multi_select") orelse false;

        if (q_obj.get("options")) |opts_val| {
            if (opts_val == .array) {
                for (opts_val.array.items, 0..) |opt_val, opt_idx| {
                    if (item.option_count >= MaxOptionsPerQuestion) break;
                    var opt = &item.options[item.option_count];
                    opt.* = .{};
                    var id_fallback_buf: [8]u8 = undefined;
                    const id_fallback = std.fmt.bufPrint(&id_fallback_buf, "{d}", .{opt_idx + 1}) catch "1";

                    switch (opt_val) {
                        .object => |o_map| {
                            const o_id = getJsonString(o_map, "id") orelse id_fallback;
                            const o_txt = getJsonString(o_map, "text") orelse continue;
                            opt.setId(o_id);
                            opt.setText(std.mem.trim(u8, o_txt, " \t\r\n"));
                            item.option_count += 1;
                        },
                        .string => |s| {
                            opt.setId(id_fallback);
                            opt.setText(std.mem.trim(u8, s, " \t\r\n"));
                            item.option_count += 1;
                        },
                        else => {},
                    }
                }
            }
        }

        // Pre-select `(Recommended)` option by default for single-choice questions
        if (!item.is_multi_select and item.option_count > 0) {
            for (item.optionSlice(), 0..) |*opt, opt_i| {
                if (std.ascii.startsWithIgnoreCase(opt.text(), "(recommended)")) {
                    item.selected_mask = @as(u8, 1) << @intCast(opt_i);
                    break;
                }
            }
        }

        group.question_count += 1;
    }
}

fn populateQuestionsFromToolArgsJson(group: *PendingQuestionGroup, args_json: []const u8) void {
    var parsed = std.json.parseFromSlice(std.json.Value, std.heap.c_allocator, args_json, .{}) catch return;
    defer parsed.deinit();
    if (parsed.value != .object) return;
    if (parsed.value.object.get("questions")) |q_val| {
        switch (q_val) {
            .array => |arr| populateQuestionsFromJsonSlice(group, arr.items),
            .string => |s| {
                var inner = std.json.parseFromSlice(std.json.Value, std.heap.c_allocator, s, .{}) catch return;
                defer inner.deinit();
                if (inner.value == .array) {
                    populateQuestionsFromJsonSlice(group, inner.value.array.items);
                }
            },
            else => {},
        }
    }
}

fn appendFixedSlice(buf: []u8, pos: *usize, slice: []const u8) void {
    const avail = buf.len -| pos.*;
    const n = @min(avail, slice.len);
    if (n > 0) {
        @memcpy(buf[pos.* .. pos.* + n], slice[0..n]);
        pos.* += n;
    }
}

fn formatLocalQuestionAnswerSummary(group: *const PendingQuestionGroup, out_buf: *[2048]u8) []const u8 {
    var pos: usize = 0;
    const q_slice = group.questionSlice();
    for (q_slice, 0..) |*q, idx| {
        if (idx > 0) appendFixedSlice(out_buf, &pos, "\n\n");
        appendFixedSlice(out_buf, &pos, "**");
        appendFixedSlice(out_buf, &pos, q.question());
        appendFixedSlice(out_buf, &pos, "**\n");
        const write_in_trimmed = q.write_in.trim(" \t\r\n");
        var wrote_any = false;
        if (!q.skipped) {
            for (q.optionSlice(), 0..) |*opt, opt_i| {
                if (q.isOptionSelected(opt_i)) {
                    appendFixedSlice(out_buf, &pos, "- ");
                    appendFixedSlice(out_buf, &pos, opt.text());
                    appendFixedSlice(out_buf, &pos, "\n");
                    wrote_any = true;
                }
            }
            if (write_in_trimmed.len > 0 and (q.use_write_in or q.is_multi_select or !wrote_any)) {
                appendFixedSlice(out_buf, &pos, "- ");
                appendFixedSlice(out_buf, &pos, write_in_trimmed);
                appendFixedSlice(out_buf, &pos, "\n");
                wrote_any = true;
            }
        }
        if (!wrote_any) {
            appendFixedSlice(out_buf, &pos, "- *Skipped*");
        }
    }
    return std.mem.trim(u8, out_buf[0..pos], " \t\r\n");
}

fn formatJsonQuestionAnswerSummary(items: []const std.json.Value, out_buf: *[2048]u8) []const u8 {
    var pos: usize = 0;
    for (items, 0..) |q_val, idx| {
        if (q_val != .object) continue;
        const q_obj = q_val.object;
        const q_text = getJsonString(q_obj, "question") orelse continue;
        if (idx > 0) appendFixedSlice(out_buf, &pos, "\n\n");
        appendFixedSlice(out_buf, &pos, "**");
        appendFixedSlice(out_buf, &pos, std.mem.trim(u8, q_text, " \t\r\n"));
        appendFixedSlice(out_buf, &pos, "**\n");

        var wrote_any = false;
        const skipped = getJsonBool(q_obj, "skipped") orelse false;
        if (!skipped) {
            if (q_obj.get("selectedOptionIds")) |sel_val| {
                if (sel_val == .array) {
                    for (sel_val.array.items) |sel_id_val| {
                        const sel_id = switch (sel_id_val) {
                            .string => |s| s,
                            else => continue,
                        };
                        const opt_txt = lookupOptionTextById(q_obj, sel_id) orelse sel_id;
                        appendFixedSlice(out_buf, &pos, "- ");
                        appendFixedSlice(out_buf, &pos, opt_txt);
                        appendFixedSlice(out_buf, &pos, "\n");
                        wrote_any = true;
                    }
                }
            }
            if (getJsonString(q_obj, "writeInResponse")) |wi| {
                const trimmed_wi = std.mem.trim(u8, wi, " \t\r\n");
                if (trimmed_wi.len > 0) {
                    appendFixedSlice(out_buf, &pos, "- ");
                    appendFixedSlice(out_buf, &pos, trimmed_wi);
                    appendFixedSlice(out_buf, &pos, "\n");
                    wrote_any = true;
                }
            }
        }
        if (!wrote_any) {
            appendFixedSlice(out_buf, &pos, "- *Skipped*");
        }
    }
    return std.mem.trim(u8, out_buf[0..pos], " \t\r\n");
}

fn lookupOptionTextById(q_obj: std.json.ObjectMap, target_id: []const u8) ?[]const u8 {
    const opts_val = q_obj.get("options") orelse return null;
    if (opts_val != .array) return null;
    for (opts_val.array.items) |opt_val| {
        if (opt_val != .object) continue;
        const o_id = getJsonString(opt_val.object, "id") orelse continue;
        if (std.mem.eql(u8, o_id, target_id)) {
            return getJsonString(opt_val.object, "text");
        }
    }
    return null;
}

fn normalizeWorkspaceUriPath(raw_uri: []const u8) []const u8 {
    var clean = std.mem.trim(u8, raw_uri, " \t\r\n");
    if (std.mem.startsWith(u8, clean, "file://")) {
        clean = clean["file://".len..];
    }
    if (clean.len >= 3 and clean[0] == '/' and clean[2] == ':') {
        clean = clean[1..];
    }
    while (clean.len > 1 and clean[clean.len - 1] == '/') {
        clean = clean[0 .. clean.len - 1];
    }
    return clean;
}

/// Returns `true` when `path` is a top-level system, user home, or volume mount container
/// (such as `/`, `/Users/<user>`, `/home/<user>`, `/Users/<user>/Projects`, or `/Volumes/<VolumeName>`)
/// that should never match child projects via prefix/ancestor matching.
pub fn isBroadContainerPath(raw_path: []const u8) bool {
    const p = normalizeWorkspaceUriPath(raw_path);
    if (p.len <= 1) return true;
    if (std.mem.eql(u8, p, "/Users") or
        std.mem.eql(u8, p, "/home") or
        std.mem.eql(u8, p, "/Volumes") or
        std.mem.eql(u8, p, "/tmp") or
        std.mem.eql(u8, p, "/var") or
        std.mem.eql(u8, p, "/private"))
    {
        return true;
    }
    // External drive mount roots (`/Volumes/<VolumeName>`)
    if (std.mem.startsWith(u8, p, "/Volumes/")) {
        const rest = p["/Volumes/".len..];
        if (std.mem.indexOfScalar(u8, rest, '/') == null) return true;
    }
    // User home directory (`/Users/<user>` or `/home/<user>`) and its immediate top-level folders (`/Projects`, `/Documents`, `/Desktop`, `/Downloads`)
    const home_rest: ?[]const u8 = if (std.mem.startsWith(u8, p, "/Users/"))
        p["/Users/".len..]
    else if (std.mem.startsWith(u8, p, "/home/"))
        p["/home/".len..]
    else
        null;
    if (home_rest) |rest| {
        if (std.mem.indexOfScalar(u8, rest, '/')) |slash_idx| {
            const sub = rest[slash_idx + 1 ..];
            if (std.mem.eql(u8, sub, "Projects") or
                std.mem.eql(u8, sub, "Documents") or
                std.mem.eql(u8, sub, "Desktop") or
                std.mem.eql(u8, sub, "Downloads"))
            {
                return true;
            }
        } else {
            return true;
        }
    }
    return false;
}

// ============================================================================
// Antigravity Hub Discovery (`~/.gemini/.../daemon/*.json` + `ps` + `lsof`/`ss`)
// ============================================================================

pub fn extractCmdFlagValue(cmd_line: []const u8, flag: []const u8) ?[]const u8 {
    const pos = std.mem.indexOf(u8, cmd_line, flag) orelse return null;
    var rest = cmd_line[pos + flag.len ..];
    if (rest.len == 0) return null;
    if (rest[0] == '=' or rest[0] == ' ') {
        rest = std.mem.trimStart(u8, rest[1..], " ");
    } else {
        return null;
    }
    var end: usize = 0;
    while (end < rest.len and rest[end] != ' ' and rest[end] != '\t' and rest[end] != '\r' and rest[end] != '\n') : (end += 1) {}
    if (end == 0) return null;
    return rest[0..end];
}

/// Parses a daemon metadata file such as `~/.gemini/antigravity-cli/daemon/hub_4400.json`
/// (`{"pid": 63503, "httpsPort": 62643, "httpPort": 4400, "csrfToken": "..."}`).
pub fn parseHubDaemonJson(
    json_bytes: []const u8,
    out_pid: *u32,
    out_http_port: *u16,
    out_https_port: *u16,
    out_csrf_buf: *[96]u8,
    out_csrf_len: *u8,
) bool {
    out_pid.* = 0;
    out_http_port.* = 0;
    out_https_port.* = 0;
    out_csrf_len.* = 0;

    var parsed = std.json.parseFromSlice(std.json.Value, std.heap.c_allocator, json_bytes, .{}) catch return false;
    defer parsed.deinit();
    if (parsed.value != .object) return false;
    const obj = parsed.value.object;

    const csrf = getJsonString(obj, "csrfToken") orelse getJsonString(obj, "csrf_token") orelse return false;
    if (csrf.len == 0 or csrf.len > out_csrf_buf.len) return false;

    const pid_u64 = getJsonUint(obj, "pid");
    const http_u64 = getJsonUint(obj, "httpPort");
    const https_u64 = getJsonUint(obj, "httpsPort");
    const generic_port_u64 = getJsonUint(obj, "port");

    const http_port: u16 = if (http_u64 > 0 and http_u64 <= std.math.maxInt(u16))
        @intCast(http_u64)
    else if (generic_port_u64 > 0 and generic_port_u64 <= std.math.maxInt(u16))
        @intCast(generic_port_u64)
    else
        0;
    const https_port: u16 = if (https_u64 > 0 and https_u64 <= std.math.maxInt(u16))
        @intCast(https_u64)
    else
        0;

    if (http_port == 0 and https_port == 0) return false;

    out_pid.* = if (pid_u64 <= std.math.maxInt(u32)) @intCast(pid_u64) else 0;
    out_http_port.* = if (http_port > 0) http_port else https_port;
    out_https_port.* = if (https_port > 0 and https_port != out_http_port.*) https_port else 0;
    @memcpy(out_csrf_buf[0..csrf.len], csrf);
    out_csrf_len.* = @intCast(csrf.len);
    return true;
}

/// Parses `ss -tlnp` output on Linux (`LISTEN ... 127.0.0.1:4400 ... users:(("agy",pid=63503,fd=12))`)
/// and extracts up to 4 listening loopback TCP ports owned by `target_pid`.
pub fn parseListeningPortsFromSsOutput(ss_output: []const u8, target_pid: u32, out_ports: *[4]u16) usize {
    if (target_pid == 0) return 0;
    var pid_tag_buf: [32]u8 = undefined;
    const pid_tag = std.fmt.bufPrint(&pid_tag_buf, "pid={d}", .{target_pid}) catch return 0;

    var port_count: usize = 0;
    var line_it = std.mem.splitScalar(u8, ss_output, '\n');
    while (line_it.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;

        // Verify `pid=<target_pid>` appears with a non-digit boundary after it
        var matched_pid = false;
        var search_pos: usize = 0;
        while (std.mem.indexOfPos(u8, line, search_pos, pid_tag)) |idx| {
            const after_idx = idx + pid_tag.len;
            if (after_idx >= line.len or !std.ascii.isDigit(line[after_idx])) {
                matched_pid = true;
                break;
            }
            search_pos = after_idx;
        }
        if (!matched_pid) continue;

        const ip_idx = std.mem.indexOf(u8, line, "127.0.0.1:") orelse continue;
        const after = line[ip_idx + "127.0.0.1:".len ..];
        var p_end: usize = 0;
        while (p_end < after.len and std.ascii.isDigit(after[p_end])) : (p_end += 1) {}
        if (p_end > 0 and port_count < out_ports.len) {
            if (std.fmt.parseInt(u16, after[0..p_end], 10)) |p| {
                if (p > 0) {
                    var exists = false;
                    for (out_ports[0..port_count]) |existing| {
                        if (existing == p) {
                            exists = true;
                            break;
                        }
                    }
                    if (!exists) {
                        out_ports[port_count] = p;
                        port_count += 1;
                    }
                }
            } else |_| {}
        }
    }
    return port_count;
}

pub fn isPidAlive(pid: u32) bool {
    if (pid == 0) return false;
    if (comptime builtin.os.tag == .linux) {
        var proc_buf: [64:0]u8 = @splat(0);
        const proc_slice = std.fmt.bufPrint(proc_buf[0..62], "/proc/{d}", .{pid}) catch return false;
        proc_buf[proc_slice.len] = 0;
        return platform.fs_util.pathExistsOnDisk(&proc_buf);
    } else if (comptime !is_windows) {
        const posix_kill = struct {
            extern "c" fn kill(pid: c_int, sig: c_int) c_int;
        };
        if (pid > @as(u32, @intCast(std.math.maxInt(c_int)))) return false;
        return posix_kill.kill(@intCast(pid), 0) == 0;
    } else {
        return true;
    }
}

fn tryDiscoverFromDaemonDir(
    dir_path: []const u8,
    out_ls_port: *u16,
    out_alt_port: *u16,
    out_csrf_buf: *[96]u8,
    out_csrf_len: *u8,
) bool {
    if (dir_path.len == 0 or dir_path.len >= 480) return false;
    var dir_z: [512:0]u8 = @splat(0);
    @memcpy(dir_z[0..dir_path.len], dir_path);
    dir_z[dir_path.len] = 0;

    const dirp = platform.fs_util.opendir(&dir_z) orelse return false;
    defer _ = platform.fs_util.closedir(dirp);

    while (platform.fs_util.readdir(dirp)) |ent| {
        const name = platform.fs_util.direntName(ent);
        if (!std.mem.endsWith(u8, name, ".json")) continue;

        var file_path_buf: [512]u8 = undefined;
        const file_path = std.fmt.bufPrint(&file_path_buf, "{s}/{s}", .{ dir_path, name }) catch continue;
        const raw_bytes = readFileBytesAlloc(std.heap.c_allocator, file_path, 16 * 1024) orelse continue;
        defer std.heap.c_allocator.free(raw_bytes);

        var pid: u32 = 0;
        var http_port: u16 = 0;
        var https_port: u16 = 0;
        if (parseHubDaemonJson(raw_bytes, &pid, &http_port, &https_port, out_csrf_buf, out_csrf_len)) {
            if (pid == 0 or isPidAlive(pid)) {
                out_ls_port.* = http_port;
                out_alt_port.* = https_port;
                return true;
            }
        }
    }
    return false;
}

/// Discovers a running Antigravity Language Server / Hub (`agy --hub` or `language_server`)
/// across macOS, Linux (including ARMv7 with `binfmt_misc` / `qemu-aarch64`), and Windows:
///   1. Checks `~/.gemini/antigravity-cli/daemon/*.json` and `~/.gemini/antigravity/daemon/*.json`
///      (e.g. `hub_4400.json` written by `AGY_ENABLE_HUB=1 agy --hub`).
///   2. Scans `ps` for processes with `--csrf_token` (`language_server`, `--hub`, or `agy`),
///      and queries listening loopback TCP ports via `lsof` or `ss -tlnp` (Linux fallback when `lsof` is absent).
pub fn discoverRunningHub(
    out_ls_port: *u16,
    out_alt_port: *u16,
    out_csrf_buf: *[96]u8,
    out_csrf_len: *u8,
) bool {
    out_ls_port.* = 0;
    out_alt_port.* = 0;
    out_csrf_len.* = 0;

    // 1. Fast path: inspect daemon JSON files in `~/.gemini/antigravity-cli/daemon` and `~/.gemini/antigravity/daemon`
    if (platform.fs_util.getenv("HOME") orelse platform.fs_util.getenv("USERPROFILE")) |home_z| {
        const home = std.mem.sliceTo(home_z, 0);
        if (home.len > 0 and home.len < 420) {
            var dir_buf: [512]u8 = undefined;
            if (std.fmt.bufPrint(&dir_buf, "{s}/.gemini/antigravity-cli/daemon", .{home})) |cli_dir| {
                if (tryDiscoverFromDaemonDir(cli_dir, out_ls_port, out_alt_port, out_csrf_buf, out_csrf_len)) {
                    return true;
                }
            } else |_| {}
            if (std.fmt.bufPrint(&dir_buf, "{s}/.gemini/antigravity/daemon", .{home})) |ide_dir| {
                if (tryDiscoverFromDaemonDir(ide_dir, out_ls_port, out_alt_port, out_csrf_buf, out_csrf_len)) {
                    return true;
                }
            } else |_| {}
        }
    }

    // 2. Process table scan (`ps` / PowerShell) for `--csrf_token`
    const ps_cmd = if (comptime is_windows)
        "powershell.exe -NoProfile -NonInteractive -Command \"Get-CimInstance Win32_Process -Filter \\\"Name LIKE 'language_server%' OR Name LIKE 'agy%'\\\" | ForEach-Object { \\\"$($_.ProcessId) $($_.CommandLine)\\\" }\""
    else
        "ps -ax -o pid=,command= 2>/dev/null";

    const fp = popen(ps_cmd, "r") orelse return false;
    defer _ = pclose(fp);

    var line_buf: [2048]u8 = undefined;
    var found_pid: u32 = 0;
    var direct_port: u16 = 0;

    while (fgets(&line_buf, @intCast(line_buf.len), fp) != null) {
        const line = std.mem.sliceTo(&line_buf, 0);
        if (std.mem.indexOf(u8, line, "language_server") == null and
            std.mem.indexOf(u8, line, "--hub") == null and
            std.mem.indexOf(u8, line, "agy") == null)
        {
            continue;
        }
        const csrf = extractCmdFlagValue(line, "--csrf_token") orelse continue;
        if (csrf.len == 0 or csrf.len > out_csrf_buf.len) continue;

        const trimmed_line = std.mem.trimStart(u8, line, " \t");
        var pid_end: usize = 0;
        while (pid_end < trimmed_line.len and std.ascii.isDigit(trimmed_line[pid_end])) : (pid_end += 1) {}
        if (pid_end == 0) continue;

        const pid = std.fmt.parseInt(u32, trimmed_line[0..pid_end], 10) catch continue;
        @memcpy(out_csrf_buf[0..csrf.len], csrf);
        out_csrf_len.* = @intCast(csrf.len);
        found_pid = pid;

        if (extractCmdFlagValue(line, "--hub-port")) |hp| {
            direct_port = std.fmt.parseInt(u16, hp, 10) catch 0;
        }
        break;
    }

    if (found_pid == 0 or out_csrf_len.* == 0) {
        out_csrf_len.* = 0;
        return false;
    }

    if (direct_port > 0) {
        out_ls_port.* = direct_port;
        return true;
    }

    var ports: [4]u16 = @splat(0);
    var port_count: usize = 0;

    if (comptime is_windows) {
        const net_fp = popen("netstat -ano -p tcp", "r") orelse return false;
        defer _ = pclose(net_fp);

        while (fgets(&line_buf, @intCast(line_buf.len), net_fp) != null) {
            const l = std.mem.trim(u8, std.mem.sliceTo(&line_buf, 0), " \t\r\n");
            if (std.mem.indexOf(u8, l, "LISTENING") == null) continue;
            const ip_idx = std.mem.indexOf(u8, l, "127.0.0.1:") orelse continue;
            var pid_start: usize = l.len;
            while (pid_start > 0 and std.ascii.isDigit(l[pid_start - 1])) : (pid_start -= 1) {}
            if (pid_start == l.len) continue;
            const line_pid = std.fmt.parseInt(u32, l[pid_start..], 10) catch continue;
            if (line_pid != found_pid) continue;

            const after = l[ip_idx + "127.0.0.1:".len ..];
            var p_end: usize = 0;
            while (p_end < after.len and std.ascii.isDigit(after[p_end])) : (p_end += 1) {}
            if (p_end > 0 and port_count < ports.len) {
                if (std.fmt.parseInt(u16, after[0..p_end], 10)) |p| {
                    ports[port_count] = p;
                    port_count += 1;
                } else |_| {}
            }
        }
    } else {
        var cmd_buf: [128]u8 = undefined;
        if (std.fmt.bufPrint(
            cmd_buf[0 .. cmd_buf.len - 1],
            "lsof -Pan -p {d} -iTCP -sTCP:LISTEN 2>/dev/null",
            .{found_pid},
        )) |cmd| {
            cmd_buf[cmd.len] = 0;
            const cmd_z: [*:0]const u8 = @ptrCast(cmd_buf[0..cmd.len]);
            if (popen(cmd_z, "r")) |lsof_fp| {
                defer _ = pclose(lsof_fp);
                while (fgets(&line_buf, @intCast(line_buf.len), lsof_fp) != null) {
                    const l = std.mem.sliceTo(&line_buf, 0);
                    if (std.mem.indexOf(u8, l, "127.0.0.1:")) |idx| {
                        const after = l[idx + "127.0.0.1:".len ..];
                        var p_end: usize = 0;
                        while (p_end < after.len and std.ascii.isDigit(after[p_end])) : (p_end += 1) {}
                        if (p_end > 0 and port_count < ports.len) {
                            if (std.fmt.parseInt(u16, after[0..p_end], 10)) |p| {
                                ports[port_count] = p;
                                port_count += 1;
                            } else |_| {}
                        }
                    }
                }
            }
        } else |_| {}

        // Linux fallback when `lsof` is not installed: query `ss -tlnp`
        if (port_count == 0) {
            if (popen("ss -tlnp 2>/dev/null", "r")) |ss_fp| {
                defer _ = pclose(ss_fp);
                var ss_out: std.ArrayList(u8) = .empty;
                defer ss_out.deinit(std.heap.c_allocator);
                while (fgets(&line_buf, @intCast(line_buf.len), ss_fp) != null) {
                    const l = std.mem.sliceTo(&line_buf, 0);
                    ss_out.appendSlice(std.heap.c_allocator, l) catch break;
                }
                port_count = parseListeningPortsFromSsOutput(ss_out.items, found_pid, &ports);
            }
        }
    }

    if (port_count == 0) {
        out_csrf_len.* = 0;
        return false;
    }
    if (port_count >= 2) {
        out_ls_port.* = ports[1];
        out_alt_port.* = ports[0];
    } else {
        out_ls_port.* = ports[0];
    }
    return true;
}

/// Copies the Antigravity CLI OAuth token (`~/.gemini/antigravity-cli/antigravity-oauth-token`)
/// to the standalone language server token path (`~/.gemini/jetski-standalone-oauth-token`)
/// when present and newer/different, so `agy --hub` can authenticate headless/CLI sessions
/// without requiring a separate browser login.
pub fn syncCliOAuthTokenBetweenPaths(src_path: []const u8, dst_path: []const u8) bool {
    const alloc = std.heap.c_allocator;
    const src_bytes = readFileBytesAlloc(alloc, src_path, 32 * 1024) orelse return false;
    defer alloc.free(src_bytes);
    if (src_bytes.len == 0) return false;

    if (readFileBytesAlloc(alloc, dst_path, 32 * 1024)) |dst_bytes| {
        defer alloc.free(dst_bytes);
        if (std.mem.eql(u8, src_bytes, dst_bytes)) return true;
    }

    if (dst_path.len == 0 or dst_path.len >= 512) return false;
    var z_dst: [512:0]u8 = @splat(0);
    @memcpy(z_dst[0..dst_path.len], dst_path);

    const fp = std.c.fopen(&z_dst, "wb") orelse return false;
    const written = std.c.fwrite(src_bytes.ptr, 1, src_bytes.len, fp);
    _ = std.c.fclose(fp);
    if (written != src_bytes.len) return false;

    if (comptime !is_windows) {
        _ = posix_net.chmod(&z_dst, 0o600);
    }
    return true;
}

pub fn syncCliOAuthTokenIfNeeded() void {
    if (comptime (builtin.is_test or is_windows)) return;
    const home_c = std.c.getenv("HOME") orelse return;
    const home = std.mem.sliceTo(home_c, 0);
    if (home.len == 0 or home.len > 400) return;

    var src_buf: [512]u8 = undefined;
    var dst_buf: [512]u8 = undefined;
    const src_path = std.fmt.bufPrint(&src_buf, "{s}/.gemini/antigravity-cli/antigravity-oauth-token", .{home}) catch return;
    const dst_path = std.fmt.bufPrint(&dst_buf, "{s}/.gemini/jetski-standalone-oauth-token", .{home}) catch return;
    _ = syncCliOAuthTokenBetweenPaths(src_path, dst_path);
}

/// Walks up from `start_dir` (up to 4 levels, stopping at broad container boundaries) to find
/// an enclosing `.git` repository root on disk, if any.
pub fn findEnclosingGitRoot(start_dir: []const u8, out_buf: *[512]u8) []const u8 {
    var cur = normalizeWorkspaceUriPath(start_dir);
    var depth: usize = 0;
    while (depth < 5 and cur.len > 1 and !isBroadContainerPath(cur)) : (depth += 1) {
        var probe_z: [512:0]u8 = @splat(0);
        const probe = std.fmt.bufPrint(probe_z[0..510], "{s}/.git", .{cur}) catch break;
        probe_z[probe.len] = 0;
        if (platform.fs_util.pathExistsOnDisk(&probe_z)) {
            const n = @min(cur.len, out_buf.len);
            @memcpy(out_buf[0..n], cur[0..n]);
            return out_buf[0..n];
        }
        cur = std.fs.path.dirname(cur) orelse break;
    }
    return "";
}

/// Determines whether a conversation (`conv_ws`, `conv_git_root`) belongs to the active editor
/// project (`active_root`, `active_git_root`), preventing broad volume/home roots (like `/Volumes/Skore`)
/// from matching nested projects while properly matching subpackages within the same repository.
pub fn doesConversationMatchWorkspace(
    raw_conv_ws: []const u8,
    raw_conv_git: []const u8,
    raw_active_root: []const u8,
    raw_active_git: []const u8,
) bool {
    const conv_ws = normalizeWorkspaceUriPath(raw_conv_ws);
    const conv_git = normalizeWorkspaceUriPath(raw_conv_git);
    const active_root = normalizeWorkspaceUriPath(raw_active_root);
    const active_git = normalizeWorkspaceUriPath(raw_active_git);

    if (active_root.len == 0 or std.mem.eql(u8, active_root, ".")) return false;

    // 1. Direct exact workspace folder match
    if (conv_ws.len > 0 and std.mem.eql(u8, conv_ws, active_root)) return true;

    // 1b. Basename-only workspace match (from `/SearchConversations` `workspaceName` field)
    if (conv_ws.len > 0 and std.mem.indexOfScalar(u8, conv_ws, '/') == null) {
        if (!isBroadContainerPath(active_root) and std.mem.eql(u8, conv_ws, std.fs.path.basename(active_root))) {
            return true;
        }
        if (active_git.len > 0 and !isBroadContainerPath(active_git) and std.mem.eql(u8, conv_ws, std.fs.path.basename(active_git))) {
            return true;
        }
        return false;
    }

    // 2. Same Git repository root (when the git root is a specific project, not a broad container)
    if (active_git.len > 0 and !isBroadContainerPath(active_git)) {
        if (conv_ws.len > 0 and std.mem.eql(u8, conv_ws, active_git)) return true;
        if (conv_git.len > 0 and std.mem.eql(u8, conv_git, active_git)) return true;
    }
    if (conv_git.len > 0 and !isBroadContainerPath(conv_git)) {
        if (std.mem.eql(u8, conv_git, active_root)) return true;
    }

    // 3. Subdirectory within the same non-broad project folder
    if (conv_ws.len > 0) {
        if (!isBroadContainerPath(active_root) and
            std.mem.startsWith(u8, conv_ws, active_root) and
            conv_ws.len > active_root.len and
            conv_ws[active_root.len] == '/')
        {
            return true;
        }
        if (!isBroadContainerPath(conv_ws) and
            std.mem.startsWith(u8, active_root, conv_ws) and
            active_root.len > conv_ws.len and
            active_root[conv_ws.len] == '/')
        {
            return true;
        }
    }

    return false;
}

fn parseSingleConversationSummary(
    cid: []const u8,
    obj: std.json.ObjectMap,
    active_root: []const u8,
    active_git_root: []const u8,
    active_cid: []const u8,
) ?ConversationSummary {
    const trimmed_id = std.mem.trim(u8, cid, " \t\r\n");
    if (trimmed_id.len == 0 or trimmed_id.len > 64) return null;

    var step_count: u32 = @intCast(@min(getJsonUint(obj, "stepCount"), std.math.maxInt(u32)));
    const has_search_fields = (getJsonString(obj, "title") != null or getJsonString(obj, "snippet") != null);
    if (step_count == 0 and has_search_fields) {
        step_count = 1;
    }
    const is_active = (active_cid.len > 0 and std.mem.eql(u8, trimmed_id, active_cid));
    if (step_count == 0 and !is_active) return null;

    var title_str = getJsonString(obj, "summary") orelse getJsonString(obj, "title") orelse "";
    if (title_str.len == 0) {
        if (obj.get("annotations")) |ann_val| {
            if (ann_val == .object) {
                title_str = getJsonString(ann_val.object, "title") orelse "";
            }
        }
    }
    if (title_str.len == 0) {
        title_str = getJsonString(obj, "snippet") orelse "";
    }
    title_str = std.mem.trim(u8, title_str, " \t\r\n");

    var ws_uri: []const u8 = "";
    var git_uri: []const u8 = "";
    if (obj.get("workspaces")) |ws_arr| {
        if (ws_arr == .array and ws_arr.array.items.len > 0) {
            if (ws_arr.array.items[0] == .object) {
                const ws0 = ws_arr.array.items[0].object;
                ws_uri = getJsonString(ws0, "workspaceFolderAbsoluteUri") orelse
                    getJsonString(ws0, "gitRootAbsoluteUri") orelse "";
                git_uri = getJsonString(ws0, "gitRootAbsoluteUri") orelse "";
            }
        }
    }
    if (ws_uri.len == 0) {
        if (obj.get("trajectoryMetadata")) |tm_val| {
            if (tm_val == .object) {
                if (tm_val.object.get("workspaces")) |ws_arr| {
                    if (ws_arr == .array and ws_arr.array.items.len > 0) {
                        if (ws_arr.array.items[0] == .object) {
                            const ws0 = ws_arr.array.items[0].object;
                            ws_uri = getJsonString(ws0, "workspaceFolderAbsoluteUri") orelse "";
                            if (git_uri.len == 0) {
                                git_uri = getJsonString(ws0, "gitRootAbsoluteUri") orelse "";
                            }
                        }
                    }
                }
            }
        }
    }
    if (ws_uri.len == 0) {
        ws_uri = getJsonString(obj, "workspaceName") orelse "";
    }

    // Filter out internal untitled background subagent worktrees
    if (title_str.len == 0 and
        (std.mem.indexOf(u8, ws_uri, "/.gemini/antigravity/worktrees/") != null or
            std.mem.indexOf(u8, ws_uri, "/subagent-") != null))
    {
        return null;
    }

    var summary = ConversationSummary{};
    summary.setId(trimmed_id);
    if (title_str.len > 0) {
        summary.setTitle(title_str);
    } else {
        summary.setTitle("Untitled Conversation");
    }
    summary.setWorkspace(ws_uri);
    summary.setGitRoot(git_uri);

    const mod_time = getJsonString(obj, "lastModifiedTime") orelse
        getJsonString(obj, "lastUserInputTime") orelse
        getJsonString(obj, "createdTime") orelse "";
    summary.setModifiedTime(mod_time);
    summary.step_count = step_count;

    const status_str = getJsonString(obj, "status") orelse "";
    summary.is_running = std.mem.eql(u8, status_str, "CASCADE_RUN_STATUS_RUNNING");
    summary.matches_cwd = doesConversationMatchWorkspace(
        summary.workspace(),
        summary.gitRoot(),
        active_root,
        active_git_root,
    );

    return summary;
}

fn extractUserPromptText(ui_obj: std.json.ObjectMap) []const u8 {
    if (getJsonString(ui_obj, "userResponse")) |ur| {
        const trimmed = std.mem.trim(u8, ur, " \t\r\n");
        if (trimmed.len > 0) return trimmed;
    }
    if (ui_obj.get("items")) |items_val| {
        if (items_val == .array) {
            for (items_val.array.items) |it| {
                if (it != .object) continue;
                if (getJsonString(it.object, "text")) |txt| {
                    const trimmed = std.mem.trim(u8, txt, " \t\r\n");
                    if (trimmed.len > 0) return trimmed;
                }
            }
        }
    }
    return "";
}

/// Zero-DOM single-pass JSON cursor used by `parseTrajectoryResponse` and tool argument extractors
/// to skip megabytes of unused tool fields (`viewFile`, `readFile`, `editFile`, `grepSearch`,
/// `cortexMemory`, `checkpoint`) with zero heap allocations.
const JsonWalker = struct {
    src: []const u8,
    pos: usize = 0,

    pub inline fn skipWs(self: *JsonWalker) void {
        var p = self.pos;
        const s = self.src;
        while (p < s.len) : (p += 1) {
            const c = s[p];
            if (c != ' ' and c != '\t' and c != '\n' and c != '\r') break;
        }
        self.pos = p;
    }

    pub inline fn expectChar(self: *JsonWalker, ch: u8) bool {
        self.skipWs();
        if (self.pos < self.src.len and self.src[self.pos] == ch) {
            self.pos += 1;
            return true;
        }
        return false;
    }

    pub fn skipString(self: *JsonWalker) bool {
        self.skipWs();
        const s = self.src;
        var p = self.pos;
        if (p >= s.len or s[p] != '"') return false;
        p += 1;
        while (p < s.len) {
            const q = std.mem.indexOfScalarPos(u8, s, p, '"') orelse {
                self.pos = s.len;
                return false;
            };
            if (s[q - 1] != '\\') {
                self.pos = q + 1;
                return true;
            }
            var bs: usize = 0;
            var k = q;
            while (k > p and s[k - 1] == '\\') : (k -= 1) {
                bs += 1;
            }
            if ((bs & 1) == 0) {
                self.pos = q + 1;
                return true;
            }
            p = q + 1;
        }
        self.pos = s.len;
        return false;
    }

    pub fn skipValue(self: *JsonWalker) bool {
        self.skipWs();
        const s = self.src;
        if (self.pos >= s.len) return false;
        const first = s[self.pos];
        if (first == '"') {
            return self.skipString();
        }
        if (first == '{' or first == '[') {
            var depth: usize = 1;
            var p = self.pos + 1;
            while (p < s.len and depth > 0) {
                const ch = s[p];
                if (ch == '"') {
                    self.pos = p;
                    if (!self.skipString()) return false;
                    p = self.pos;
                } else if (ch == '{' or ch == '[') {
                    depth += 1;
                    p += 1;
                } else if (ch == '}' or ch == ']') {
                    depth -= 1;
                    p += 1;
                } else {
                    p += 1;
                }
            }
            self.pos = p;
            return depth == 0;
        }
        var p = self.pos;
        while (p < s.len) : (p += 1) {
            const c = s[p];
            if (c == ',' or c == '}' or c == ']' or c == ' ' or c == '\t' or c == '\n' or c == '\r') break;
        }
        if (p == self.pos) return false;
        self.pos = p;
        return true;
    }

    pub fn captureValueSlice(self: *JsonWalker) ?[]const u8 {
        self.skipWs();
        const start = self.pos;
        if (!self.skipValue()) return null;
        return self.src[start..self.pos];
    }

    pub fn readUint(self: *JsonWalker) u64 {
        self.skipWs();
        if (self.pos >= self.src.len) return 0;
        if (self.src[self.pos] == '"') {
            var buf: [32]u8 = undefined;
            const s = self.readStringFixed(&buf) orelse return 0;
            return std.fmt.parseInt(u64, s, 10) catch 0;
        }
        const start = self.pos;
        if (!self.skipValue()) return 0;
        return std.fmt.parseInt(u64, self.src[start..self.pos], 10) catch 0;
    }

    pub fn readInt(self: *JsonWalker) ?i64 {
        self.skipWs();
        if (self.pos >= self.src.len) return null;
        if (self.src[self.pos] == '"') {
            var buf: [32]u8 = undefined;
            const s = self.readStringFixed(&buf) orelse return null;
            return std.fmt.parseInt(i64, s, 10) catch null;
        }
        const start = self.pos;
        if (!self.skipValue()) return null;
        return std.fmt.parseInt(i64, self.src[start..self.pos], 10) catch null;
    }

    pub fn readStringFixed(self: *JsonWalker, out_buf: []u8) ?[]const u8 {
        self.skipWs();
        const s = self.src;
        if (self.pos >= s.len or s[self.pos] != '"') return null;
        const content_start = self.pos + 1;
        if (!self.skipString()) return null;
        const raw = s[content_start .. self.pos - 1];

        const first_bs = std.mem.indexOfScalar(u8, raw, '\\') orelse {
            const n = @min(raw.len, out_buf.len);
            @memcpy(out_buf[0..n], raw[0..n]);
            return out_buf[0..n];
        };

        var out_len: usize = @min(first_bs, out_buf.len);
        if (out_len > 0) {
            @memcpy(out_buf[0..out_len], raw[0..out_len]);
        }
        var rpos: usize = first_bs;
        while (rpos < raw.len and out_len < out_buf.len) {
            const next_bs = std.mem.indexOfScalarPos(u8, raw, rpos, '\\') orelse {
                const rem = raw[rpos..];
                const take = @min(rem.len, out_buf.len - out_len);
                @memcpy(out_buf[out_len .. out_len + take], rem[0..take]);
                out_len += take;
                break;
            };
            if (next_bs > rpos) {
                const lit = raw[rpos..next_bs];
                const take = @min(lit.len, out_buf.len - out_len);
                @memcpy(out_buf[out_len .. out_len + take], lit[0..take]);
                out_len += take;
                if (out_len >= out_buf.len) break;
            }
            rpos = next_bs + 1;
            if (rpos >= raw.len) break;
            const esc = raw[rpos];
            rpos += 1;
            if (esc == 'u') {
                if (rpos + 4 > raw.len) break;
                const cp = decodeJsonUtf16Escape(raw, &rpos) orelse '?';
                var u8_buf: [4]u8 = undefined;
                const n_u8 = std.unicode.utf8Encode(cp, &u8_buf) catch 0;
                if (out_len + n_u8 <= out_buf.len) {
                    @memcpy(out_buf[out_len .. out_len + n_u8], u8_buf[0..n_u8]);
                    out_len += n_u8;
                }
            } else {
                const decoded: u8 = switch (esc) {
                    '"' => '"',
                    '\\' => '\\',
                    '/' => '/',
                    'b' => 0x08,
                    'f' => 0x0c,
                    'n' => '\n',
                    'r' => '\r',
                    't' => '\t',
                    else => esc,
                };
                out_buf[out_len] = decoded;
                out_len += 1;
            }
        }
        return out_buf[0..out_len];
    }

    pub fn readStringScratch(
        self: *JsonWalker,
        scratch: *std.ArrayList(u8),
        alloc: std.mem.Allocator,
        max_len: usize,
    ) ?[]const u8 {
        self.skipWs();
        const s = self.src;
        if (self.pos >= s.len or s[self.pos] != '"') return null;
        const content_start = self.pos + 1;
        if (!self.skipString()) return null;
        const raw = s[content_start .. self.pos - 1];

        const first_bs = std.mem.indexOfScalar(u8, raw, '\\') orelse {
            return raw[0..@min(raw.len, max_len)];
        };

        if (first_bs > 0) {
            const take = @min(first_bs, max_len -| scratch.items.len);
            if (take > 0) scratch.appendSlice(alloc, raw[0..take]) catch return null;
        }
        var rpos: usize = first_bs;
        while (rpos < raw.len and scratch.items.len < max_len) {
            const next_bs = std.mem.indexOfScalarPos(u8, raw, rpos, '\\') orelse {
                const rem = raw[rpos..];
                const take = @min(rem.len, max_len -| scratch.items.len);
                if (take > 0) scratch.appendSlice(alloc, rem[0..take]) catch return null;
                break;
            };
            if (next_bs > rpos) {
                const lit = raw[rpos..next_bs];
                const take = @min(lit.len, max_len -| scratch.items.len);
                if (take > 0) scratch.appendSlice(alloc, lit[0..take]) catch return null;
                if (scratch.items.len >= max_len) break;
            }
            rpos = next_bs + 1;
            if (rpos >= raw.len) break;
            const esc = raw[rpos];
            rpos += 1;
            if (esc == 'u') {
                if (rpos + 4 > raw.len) break;
                const cp = decodeJsonUtf16Escape(raw, &rpos) orelse '?';
                var u8_buf: [4]u8 = undefined;
                const n_u8 = std.unicode.utf8Encode(cp, &u8_buf) catch 0;
                if (scratch.items.len + n_u8 <= max_len) {
                    scratch.appendSlice(alloc, u8_buf[0..n_u8]) catch return null;
                }
            } else {
                const decoded: u8 = switch (esc) {
                    '"' => '"',
                    '\\' => '\\',
                    '/' => '/',
                    'b' => 0x08,
                    'f' => 0x0c,
                    'n' => '\n',
                    'r' => '\r',
                    't' => '\t',
                    else => esc,
                };
                scratch.append(alloc, decoded) catch return null;
            }
        }
        return scratch.items;
    }
};

fn decodeJsonUtf16Escape(s: []const u8, pos: *usize) ?u21 {
    if (pos.* + 4 > s.len) return null;
    const cp1 = std.fmt.parseInt(u16, s[pos.* .. pos.* + 4], 16) catch return null;
    pos.* += 4;
    if (cp1 >= 0xD800 and cp1 <= 0xDBFF) {
        if (pos.* + 6 <= s.len and s[pos.*] == '\\' and s[pos.* + 1] == 'u') {
            if (std.fmt.parseInt(u16, s[pos.* + 2 .. pos.* + 6], 16)) |cp2| {
                if (cp2 >= 0xDC00 and cp2 <= 0xDFFF) {
                    pos.* += 6;
                    const hi: u21 = @intCast(cp1 - 0xD800);
                    const lo: u21 = @intCast(cp2 - 0xDC00);
                    return 0x10000 + (hi << 10) + lo;
                }
            } else |_| {}
        }
        return 0xFFFD;
    }
    if (cp1 >= 0xDC00 and cp1 <= 0xDFFF) return 0xFFFD;
    return @intCast(cp1);
}

fn parseStepMetadataFast(
    w: *JsonWalker,
    total_in: *u64,
    total_out: *u64,
    total_think: *u64,
    total_cache: *u64,
    meta_args_slice: *?[]const u8,
) void {
    if (!w.expectChar('{')) {
        _ = w.skipValue();
        return;
    }
    while (true) {
        w.skipWs();
        if (w.pos >= w.src.len) return;
        if (w.src[w.pos] == '}') {
            w.pos += 1;
            return;
        }
        if (w.src[w.pos] == ',') {
            w.pos += 1;
            continue;
        }
        var mkbuf: [48]u8 = undefined;
        const mkey = w.readStringFixed(&mkbuf) orelse return;
        if (!w.expectChar(':')) return;

        if (std.mem.eql(u8, mkey, "modelUsage")) {
            if (w.expectChar('{')) {
                while (true) {
                    w.skipWs();
                    if (w.pos >= w.src.len) break;
                    if (w.src[w.pos] == '}') {
                        w.pos += 1;
                        break;
                    }
                    if (w.src[w.pos] == ',') {
                        w.pos += 1;
                        continue;
                    }
                    var ukbuf: [48]u8 = undefined;
                    const ukey = w.readStringFixed(&ukbuf) orelse break;
                    if (!w.expectChar(':')) break;
                    if (std.mem.eql(u8, ukey, "inputTokens")) {
                        total_in.* += w.readUint();
                    } else if (std.mem.eql(u8, ukey, "outputTokens")) {
                        total_out.* += w.readUint();
                    } else if (std.mem.eql(u8, ukey, "thinkingOutputTokens")) {
                        total_think.* += w.readUint();
                    } else if (std.mem.eql(u8, ukey, "cacheReadTokens")) {
                        total_cache.* += w.readUint();
                    } else {
                        if (!w.skipValue()) break;
                    }
                }
            } else {
                if (!w.skipValue()) return;
            }
        } else if (std.mem.eql(u8, mkey, "toolCall")) {
            if (w.expectChar('{')) {
                while (true) {
                    w.skipWs();
                    if (w.pos >= w.src.len) break;
                    if (w.src[w.pos] == '}') {
                        w.pos += 1;
                        break;
                    }
                    if (w.src[w.pos] == ',') {
                        w.pos += 1;
                        continue;
                    }
                    var tckbuf: [48]u8 = undefined;
                    const tckey = w.readStringFixed(&tckbuf) orelse break;
                    if (!w.expectChar(':')) break;
                    if (std.mem.eql(u8, tckey, "argumentsJson")) {
                        meta_args_slice.* = w.captureValueSlice();
                    } else {
                        if (!w.skipValue()) break;
                    }
                }
            } else {
                if (!w.skipValue()) return;
            }
        } else {
            if (!w.skipValue()) return;
        }
    }
}

fn extractUserPromptTextFast(
    ui_raw: []const u8,
    scratch: *std.ArrayList(u8),
    alloc: std.mem.Allocator,
) ?[]const u8 {
    var w = JsonWalker{ .src = ui_raw };
    if (!w.expectChar('{')) return null;

    var user_resp_slice: ?[]const u8 = null;
    var items_slice: ?[]const u8 = null;

    while (true) {
        w.skipWs();
        if (w.pos >= w.src.len or w.src[w.pos] == '}') break;
        if (w.src[w.pos] == ',') {
            w.pos += 1;
            continue;
        }
        var kbuf: [48]u8 = undefined;
        const key = w.readStringFixed(&kbuf) orelse break;
        if (!w.expectChar(':')) break;

        if (std.mem.eql(u8, key, "userResponse")) {
            user_resp_slice = w.captureValueSlice();
        } else if (std.mem.eql(u8, key, "items")) {
            items_slice = w.captureValueSlice();
        } else {
            if (!w.skipValue()) break;
        }
    }

    if (user_resp_slice) |urs| {
        var urw = JsonWalker{ .src = urs };
        scratch.clearRetainingCapacity();
        if (urw.readStringScratch(scratch, alloc, TranscriptCapacity / 2)) |ur_txt| {
            const trimmed = std.mem.trim(u8, ur_txt, " \t\r\n");
            if (trimmed.len > 0) return trimmed;
        }
    }

    if (items_slice) |its| {
        var aw = JsonWalker{ .src = its };
        if (aw.expectChar('[')) {
            while (true) {
                aw.skipWs();
                if (aw.pos >= aw.src.len or aw.src[aw.pos] == ']') break;
                if (aw.src[aw.pos] == ',') {
                    aw.pos += 1;
                    continue;
                }
                const item_raw = aw.captureValueSlice() orelse break;
                var iw = JsonWalker{ .src = item_raw };
                if (!iw.expectChar('{')) continue;
                while (true) {
                    iw.skipWs();
                    if (iw.pos >= iw.src.len or iw.src[iw.pos] == '}') break;
                    if (iw.src[iw.pos] == ',') {
                        iw.pos += 1;
                        continue;
                    }
                    var ikbuf: [32]u8 = undefined;
                    const ikey = iw.readStringFixed(&ikbuf) orelse break;
                    if (!iw.expectChar(':')) break;
                    if (std.mem.eql(u8, ikey, "text")) {
                        scratch.clearRetainingCapacity();
                        if (iw.readStringScratch(scratch, alloc, TranscriptCapacity / 2)) |txt| {
                            const trimmed = std.mem.trim(u8, txt, " \t\r\n");
                            if (trimmed.len > 0) return trimmed;
                        }
                    } else {
                        if (!iw.skipValue()) break;
                    }
                }
            }
        }
    }
    return null;
}

fn readFileBytesAlloc(alloc: std.mem.Allocator, file_path: []const u8, max_bytes: usize) ?[]u8 {
    const clean_path = normalizeWorkspaceUriPath(file_path);
    if (clean_path.len == 0 or clean_path.len >= 512) return null;
    var zpath: [512:0]u8 = @splat(0);
    @memcpy(zpath[0..clean_path.len], clean_path);
    const fp = std.c.fopen(&zpath, "rb") orelse return null;
    defer _ = std.c.fclose(fp);

    var out: std.ArrayList(u8) = .empty;
    var chunk: [16384]u8 = undefined;
    while (out.items.len < max_bytes) {
        const want = @min(chunk.len, max_bytes - out.items.len);
        const n = std.c.fread(&chunk, 1, want, fp);
        if (n == 0) break;
        out.appendSlice(alloc, chunk[0..n]) catch {
            out.deinit(alloc);
            return null;
        };
    }
    if (out.items.len == 0) {
        out.deinit(alloc);
        return null;
    }
    return out.toOwnedSlice(alloc) catch {
        out.deinit(alloc);
        return null;
    };
}

fn extractUserPromptMediaFast(ui_raw: []const u8, out_buf: *[1024]u8) []const u8 {
    var w = JsonWalker{ .src = ui_raw };
    if (!w.expectChar('{')) return "";

    var media_slice: ?[]const u8 = null;
    while (true) {
        w.skipWs();
        if (w.pos >= w.src.len or w.src[w.pos] == '}') break;
        if (w.src[w.pos] == ',') {
            w.pos += 1;
            continue;
        }
        var kbuf: [48]u8 = undefined;
        const key = w.readStringFixed(&kbuf) orelse break;
        if (!w.expectChar(':')) break;

        if (std.mem.eql(u8, key, "media")) {
            media_slice = w.captureValueSlice();
        } else {
            if (!w.skipValue()) break;
        }
    }

    const ms = media_slice orelse return "";
    var aw = JsonWalker{ .src = ms };
    if (!aw.expectChar('[')) return "";

    var pos: usize = 0;
    while (true) {
        aw.skipWs();
        if (aw.pos >= aw.src.len or aw.src[aw.pos] == ']') break;
        if (aw.src[aw.pos] == ',') {
            aw.pos += 1;
            continue;
        }
        const item_raw = aw.captureValueSlice() orelse break;
        var iw = JsonWalker{ .src = item_raw };
        if (!iw.expectChar('{')) continue;

        var uri_buf: [256]u8 = undefined;
        var uri_slice: []const u8 = "";
        while (true) {
            iw.skipWs();
            if (iw.pos >= iw.src.len or iw.src[iw.pos] == '}') break;
            if (iw.src[iw.pos] == ',') {
                iw.pos += 1;
                continue;
            }
            var ikbuf: [32]u8 = undefined;
            const ikey = iw.readStringFixed(&ikbuf) orelse break;
            if (!iw.expectChar(':')) break;
            if (std.mem.eql(u8, ikey, "uri")) {
                uri_slice = iw.readStringFixed(&uri_buf) orelse blk: {
                    _ = iw.skipValue();
                    break :blk "";
                };
            } else {
                if (!iw.skipValue()) break;
            }
        }
        const clean_uri = normalizeWorkspaceUriPath(uri_slice);
        if (clean_uri.len > 0) {
            if (pos > 0) appendFixedSlice(out_buf, &pos, "\n");
            appendFixedSlice(out_buf, &pos, clean_uri);
        }
    }
    return out_buf[0..pos];
}

fn extractJsonStepMediaPaths(step: std.json.ObjectMap, out_buf: *[1024]u8) []const u8 {
    const media_val = step.get("media") orelse return "";
    if (media_val != .array) return "";
    var pos: usize = 0;
    for (media_val.array.items) |m_item| {
        if (m_item != .object) continue;
        const raw_uri = getJsonString(m_item.object, "uri") orelse continue;
        const clean_uri = normalizeWorkspaceUriPath(raw_uri);
        if (clean_uri.len > 0) {
            if (pos > 0) appendFixedSlice(out_buf, &pos, "\n");
            appendFixedSlice(out_buf, &pos, clean_uri);
        }
    }
    return out_buf[0..pos];
}

fn extractErrorMessageFast(em_raw: []const u8, out_buf: *[512]u8) []const u8 {
    var w = JsonWalker{ .src = em_raw };
    if (!w.expectChar('{')) return "";
    while (true) {
        w.skipWs();
        if (w.pos >= w.src.len or w.src[w.pos] == '}') break;
        if (w.src[w.pos] == ',') {
            w.pos += 1;
            continue;
        }
        var kbuf: [48]u8 = undefined;
        const key = w.readStringFixed(&kbuf) orelse break;
        if (!w.expectChar(':')) break;
        if (std.mem.eql(u8, key, "error")) {
            if (!w.expectChar('{')) {
                _ = w.skipValue();
                continue;
            }
            var short_buf: [512]u8 = undefined;
            var short_err: []const u8 = "";
            var user_buf: [512]u8 = undefined;
            var user_err: []const u8 = "";
            while (true) {
                w.skipWs();
                if (w.pos >= w.src.len or w.src[w.pos] == '}') break;
                if (w.src[w.pos] == ',') {
                    w.pos += 1;
                    continue;
                }
                var ekbuf: [48]u8 = undefined;
                const ekey = w.readStringFixed(&ekbuf) orelse break;
                if (!w.expectChar(':')) break;
                if (std.mem.eql(u8, ekey, "shortError")) {
                    short_err = w.readStringFixed(&short_buf) orelse blk: {
                        _ = w.skipValue();
                        break :blk "";
                    };
                } else if (std.mem.eql(u8, ekey, "userErrorMessage")) {
                    user_err = w.readStringFixed(&user_buf) orelse blk: {
                        _ = w.skipValue();
                        break :blk "";
                    };
                } else {
                    if (!w.skipValue()) break;
                }
            }
            const chosen = if (short_err.len > 0) short_err else if (user_err.len > 0) user_err else "Agent error";
            const n = @min(chosen.len, out_buf.len);
            @memcpy(out_buf[0..n], chosen[0..n]);
            return out_buf[0..n];
        } else {
            if (!w.skipValue()) break;
        }
    }
    return "";
}

fn stripUserRequestWrapper(raw: []const u8) []const u8 {
    var s = std.mem.trim(u8, raw, " \t\r\n");
    const open_tag = "<USER_REQUEST>";
    const close_tag = "</USER_REQUEST>";
    if (std.mem.indexOf(u8, s, open_tag)) |open_idx| {
        const after_open = s[open_idx + open_tag.len ..];
        if (std.mem.indexOf(u8, after_open, close_tag)) |close_idx| {
            s = std.mem.trim(u8, after_open[0..close_idx], " \t\r\n");
        }
    }
    return s;
}

/// Formats a protobuf JSON duration string (e.g. `"5.081949s"`, `"0.412s"`) into a human-readable
/// thinking dropdown header label (`"Thought for 5s"`, `"Thought for <1s"`, `"Thought"`, or `"Thinking..."`).
pub fn formatThinkingDurationLabel(raw_duration: []const u8, is_generating: bool, out_buf: *[48]u8) []const u8 {
    var s = std.mem.trim(u8, raw_duration, " \t\r\n");
    if (std.mem.endsWith(u8, s, "s")) {
        s = s[0 .. s.len - 1];
    }
    if (s.len > 0) {
        if (std.fmt.parseFloat(f64, s)) |secs_f| {
            if (secs_f >= 0.0) {
                const rounded: u64 = @intFromFloat(@round(secs_f));
                if (rounded == 0) {
                    return "Thought for <1s";
                } else if (rounded < 60) {
                    return std.fmt.bufPrint(out_buf, "Thought for {d}s", .{rounded}) catch "Thought";
                } else {
                    const mins = rounded / 60;
                    const rem_s = rounded % 60;
                    if (rem_s == 0) {
                        return std.fmt.bufPrint(out_buf, "Thought for {d}m", .{mins}) catch "Thought";
                    }
                    return std.fmt.bufPrint(out_buf, "Thought for {d}m {d}s", .{ mins, rem_s }) catch "Thought";
                }
            }
        } else |_| {}
    }
    return if (is_generating) "Thinking..." else "Thought";
}

fn extractToolArgsSummaryFromObject(obj: std.json.ObjectMap, out_buf: *[128]u8) []const u8 {
    const keys = [_][]const u8{
        "toolSummary",
        "toolAction",
        "Path",
        "AbsolutePath",
        "TargetFile",
        "CommandLine",
        "query",
        "SearchPath",
        "DirectoryPath",
    };
    for (keys) |k| {
        if (getJsonString(obj, k)) |val| {
            const trimmed = std.mem.trim(u8, val, " \t\r\n\"\t");
            if (trimmed.len > 0) {
                const n = @min(trimmed.len, out_buf.len);
                @memcpy(out_buf[0..n], trimmed[0..n]);
                return out_buf[0..n];
            }
        }
    }
    return "";
}

fn extractToolArgsSummary(args_json: []const u8, out_buf: *[128]u8) []const u8 {
    if (args_json.len == 0) return "";
    const keys = [_][]const u8{
        "toolSummary",
        "toolAction",
        "Path",
        "AbsolutePath",
        "TargetFile",
        "CommandLine",
        "query",
        "SearchPath",
        "DirectoryPath",
    };
    var w = JsonWalker{ .src = args_json };
    if (!w.expectChar('{')) return "";
    var best_prio: usize = keys.len + 1;
    var best_len: usize = 0;

    while (true) {
        w.skipWs();
        if (w.pos >= w.src.len or w.src[w.pos] == '}') break;
        if (w.src[w.pos] == ',') {
            w.pos += 1;
            continue;
        }
        var kbuf: [48]u8 = undefined;
        const key = w.readStringFixed(&kbuf) orelse break;
        if (!w.expectChar(':')) break;

        var matched_prio: ?usize = null;
        for (keys, 0..) |k, prio| {
            if (std.mem.eql(u8, key, k)) {
                matched_prio = prio;
                break;
            }
        }
        if (matched_prio) |prio| {
            if (prio < best_prio) {
                var vbuf: [128]u8 = undefined;
                if (w.readStringFixed(&vbuf)) |val| {
                    const trimmed = std.mem.trim(u8, val, " \t\r\n\"\t");
                    if (trimmed.len > 0) {
                        const n = @min(trimmed.len, out_buf.len);
                        @memcpy(out_buf[0..n], trimmed[0..n]);
                        best_len = n;
                        best_prio = prio;
                        if (prio == 0) return out_buf[0..best_len];
                        continue;
                    }
                } else {
                    _ = w.skipValue();
                }
            } else {
                if (!w.skipValue()) break;
            }
        } else {
            if (!w.skipValue()) break;
        }
    }
    return out_buf[0..best_len];
}

fn extractCommandLineFromObject(obj: std.json.ObjectMap, out_buf: *[512]u8) []const u8 {
    const keys = [_][]const u8{
        "CommandLine",
        "commandLine",
        "command",
    };
    for (keys) |k| {
        if (getJsonString(obj, k)) |val| {
            const trimmed = std.mem.trim(u8, val, " \t\r\n");
            if (trimmed.len > 0) {
                const n = @min(trimmed.len, out_buf.len);
                @memcpy(out_buf[0..n], trimmed[0..n]);
                return out_buf[0..n];
            }
        }
    }
    return "";
}

fn extractCommandLineFromArgsJson(args_json: []const u8, out_buf: *[512]u8) []const u8 {
    if (args_json.len == 0) return "";
    const keys = [_][]const u8{
        "CommandLine",
        "commandLine",
        "command",
    };
    var w = JsonWalker{ .src = args_json };
    if (!w.expectChar('{')) return "";
    var best_prio: usize = keys.len + 1;
    var best_len: usize = 0;

    while (true) {
        w.skipWs();
        if (w.pos >= w.src.len or w.src[w.pos] == '}') break;
        if (w.src[w.pos] == ',') {
            w.pos += 1;
            continue;
        }
        var kbuf: [48]u8 = undefined;
        const key = w.readStringFixed(&kbuf) orelse break;
        if (!w.expectChar(':')) break;

        var matched_prio: ?usize = null;
        for (keys, 0..) |k, prio| {
            if (std.mem.eql(u8, key, k)) {
                matched_prio = prio;
                break;
            }
        }
        if (matched_prio) |prio| {
            if (prio < best_prio) {
                var vbuf: [512]u8 = undefined;
                if (w.readStringFixed(&vbuf)) |val| {
                    const trimmed = std.mem.trim(u8, val, " \t\r\n");
                    if (trimmed.len > 0) {
                        const n = @min(trimmed.len, out_buf.len);
                        @memcpy(out_buf[0..n], trimmed[0..n]);
                        best_len = n;
                        best_prio = prio;
                        if (prio == 0) return out_buf[0..best_len];
                        continue;
                    }
                } else {
                    _ = w.skipValue();
                }
            } else {
                if (!w.skipValue()) break;
            }
        } else {
            if (!w.skipValue()) break;
        }
    }
    return out_buf[0..best_len];
}

pub fn cleanShellCommandOutput(raw: []const u8, parsed_exit_code_out: *?i16) []const u8 {
    const exit_marker = "Command exited with code ";
    if (std.mem.indexOf(u8, raw, exit_marker)) |idx| {
        const after = raw[idx + exit_marker.len ..];
        var d_end: usize = 0;
        while (d_end < after.len and (std.ascii.isDigit(after[d_end]) or (d_end == 0 and after[d_end] == '-'))) : (d_end += 1) {}
        if (d_end > 0) {
            if (std.fmt.parseInt(i16, after[0..d_end], 10)) |ec| {
                parsed_exit_code_out.* = ec;
            } else |_| {}
        }
    }

    var body = raw;
    const out_marker = "Command output:\n";
    if (std.mem.indexOf(u8, body, out_marker)) |out_idx| {
        body = body[out_idx + out_marker.len ..];
    } else if (std.mem.indexOf(u8, body, exit_marker)) |exit_idx| {
        const after_exit = body[exit_idx + exit_marker.len ..];
        if (std.mem.indexOfScalar(u8, after_exit, '\n')) |nl| {
            body = after_exit[nl + 1 ..];
        } else {
            body = "";
        }
    }
    return std.mem.trim(u8, body, " \t\r\n");
}

fn getJsonString(obj: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    const v = obj.get(key) orelse return null;
    return switch (v) {
        .string => |s| s,
        else => null,
    };
}

fn getJsonBool(obj: std.json.ObjectMap, key: []const u8) ?bool {
    const v = obj.get(key) orelse return null;
    return switch (v) {
        .bool => |b| b,
        else => null,
    };
}

fn getJsonUint(obj: std.json.ObjectMap, key: []const u8) u64 {
    const v = obj.get(key) orelse return 0;
    return switch (v) {
        .integer => |n| if (n > 0) @intCast(n) else 0,
        .string => |s| std.fmt.parseInt(u64, s, 10) catch 0,
        else => 0,
    };
}

fn containsIgnoreCaseAscii(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0 or needle.len > haystack.len) return false;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[i .. i + needle.len], needle)) return true;
    }
    return false;
}

fn decodeChunkedAlloc(src: []const u8, out: *std.ArrayList(u8), alloc: std.mem.Allocator) void {
    var in_pos: usize = 0;
    while (in_pos < src.len) {
        const line_end = std.mem.indexOfPos(u8, src, in_pos, "\r\n") orelse break;
        const size_str = std.mem.trim(u8, src[in_pos..line_end], " \t");
        if (size_str.len == 0) {
            in_pos = line_end + 2;
            continue;
        }
        const chunk_len = std.fmt.parseInt(usize, size_str, 16) catch break;
        in_pos = line_end + 2;
        if (chunk_len == 0) break;
        if (in_pos + chunk_len > src.len) break;
        out.appendSlice(alloc, src[in_pos .. in_pos + chunk_len]) catch break;
        in_pos += chunk_len;
        if (in_pos + 2 <= src.len and src[in_pos] == '\r' and src[in_pos + 1] == '\n') {
            in_pos += 2;
        }
    }
}

fn appendJsonEscaped(list: *std.ArrayList(u8), allocator: std.mem.Allocator, text: []const u8) !void {
    for (text) |b| {
        switch (b) {
            '"' => try list.appendSlice(allocator, "\\\""),
            '\\' => try list.appendSlice(allocator, "\\\\"),
            '\n' => try list.appendSlice(allocator, "\\n"),
            '\r' => try list.appendSlice(allocator, "\\r"),
            '\t' => try list.appendSlice(allocator, "\\t"),
            0x00...0x08, 0x0B...0x0C, 0x0E...0x1F => {
                var hex_buf: [6]u8 = undefined;
                const hex = std.fmt.bufPrint(&hex_buf, "\\u{x:0>4}", .{b}) catch continue;
                try list.appendSlice(allocator, hex);
            },
            else => try list.append(allocator, b),
        }
    }
}

test "AgySession local socket StartCascade and GetCascadeTrajectory parsing" {
    var session = AgySession.init();
    defer session.deinit();

    try std.testing.expect(session.parseStartCascadeResponse("{\"cascadeId\":\"60dbe823-2708-42f7-9e49-064e75ac445f\"}"));
    try std.testing.expectEqualStrings("60dbe823-2708-42f7-9e49-064e75ac445f", session.conversationId());

    session.is_running_turn = true;
    const traj_json =
        \\{"status":"CASCADE_RUN_STATUS_IDLE","trajectory":{"steps":[
        \\  {"type":"CORTEX_STEP_TYPE_USER_INPUT","status":"CORTEX_STEP_STATUS_DONE","userInput":{"userResponse":"Read build.zig"}},
        \\  {"type":"CORTEX_STEP_TYPE_PLANNER_RESPONSE","status":"CORTEX_STEP_STATUS_DONE",
        \\   "metadata":{"modelUsage":{"inputTokens":"1200","outputTokens":"45","thinkingOutputTokens":"15"}},
        \\   "plannerResponse":{"toolCalls":[{"id":"c1","name":"read_file","argumentsJson":"{\"Path\":\"/workspace/build.zig\"}"}],"modifiedResponse":"The first line imports `std`."}}
        \\]}}
    ;
    try std.testing.expect(session.parseTrajectoryResponse(traj_json));
    try std.testing.expect(!session.is_running_turn);
    try std.testing.expect(session.turn_completed_flag);
    try std.testing.expectEqual(@as(u64, 1200), session.usage.input_tokens);
    try std.testing.expectEqual(@as(u64, 45), session.usage.output_tokens);
    try std.testing.expect(std.mem.indexOf(u8, session.transcript(), "read_file") != null);
    try std.testing.expect(std.mem.indexOf(u8, session.transcript(), "The first line imports `std`.") != null);
}

test "AgySession CORTEX_STEP_TYPE_ASK_QUESTION waiting, selection, write-in, and HandleCascadeUserInteraction payload" {
    var session = AgySession.init();
    defer session.deinit();

    try std.testing.expect(session.parseStartCascadeResponse("{\"cascadeId\":\"063c3f14-ee8c-4723-b817-0c711d470223\"}"));
    session.is_running_turn = true;

    const waiting_traj =
        \\{"status":"CASCADE_RUN_STATUS_RUNNING","trajectory":{"trajectoryId":"02710d62-0f91-4cba-b1d8-2bc3e4a838b7","steps":[
        \\  {"type":"CORTEX_STEP_TYPE_USER_INPUT","status":"CORTEX_STEP_STATUS_DONE","userInput":{"userResponse":"Configure thermal DRC"}},
        \\  {"type":"CORTEX_STEP_TYPE_ASK_QUESTION","status":"CORTEX_STEP_STATUS_WAITING",
        \\   "metadata":{"sourceTrajectoryStepInfo":{"trajectoryId":"02710d62-0f91-4cba-b1d8-2bc3e4a838b7","stepIndex":38}},
        \\   "askQuestion":{"questions":[
        \\     {"question":"What is the target maximum trace temperature rise?","isMultiSelect":false,"options":[
        \\       {"id":"1","text":"(Recommended) 10C rise"},
        \\       {"id":"2","text":"5C rise"}
        \\     ]},
        \\     {"question":"Which checks should be enabled?","isMultiSelect":true,"options":[
        \\       {"id":"1","text":"Trace width check"},
        \\       {"id":"2","text":"Via current check"}
        \\     ]}
        \\   ]}}
        \\]}}
    ;
    try std.testing.expect(session.parseTrajectoryResponse(waiting_traj));
    try std.testing.expect(session.is_running_turn);
    try std.testing.expect(session.pending_question.active);
    try std.testing.expectEqual(@as(u32, 38), session.pending_question.step_index);
    try std.testing.expectEqualStrings("02710d62-0f91-4cba-b1d8-2bc3e4a838b7", session.pending_question.trajectoryId());
    try std.testing.expectEqual(@as(usize, 2), session.pending_question.question_count);

    // Question 0 has `(Recommended)` pre-selected automatically
    try std.testing.expect(session.pending_question.questions[0].isOptionSelected(0));
    try std.testing.expect(!session.pending_question.questions[0].isOptionSelected(1));

    // Select option 1 on Question 0 and multi-select both options + write-in on Question 1
    session.pending_question.questions[0].selectOption(1);
    try std.testing.expect(!session.pending_question.questions[0].isOptionSelected(0));
    try std.testing.expect(session.pending_question.questions[0].isOptionSelected(1));

    session.pending_question.questions[1].selectOption(0);
    session.pending_question.questions[1].selectOption(1);
    session.pending_question.questions[1].write_in.set("Also check neck-down length");
    session.pending_question.questions[1].use_write_in = true;

    // Polling the exact same trajectory JSON bytes is deduplicated in O(1) without resetting selections
    try std.testing.expect(!session.parseTrajectoryResponse(waiting_traj));
    // Even when trajectory JSON changes (e.g. updated token telemetry), re-parsing the waiting step preserves selections
    session.last_trajectory_hash = 0;
    try std.testing.expect(!session.parseTrajectoryResponse(waiting_traj));
    try std.testing.expect(session.pending_question.questions[0].isOptionSelected(1));
    try std.testing.expect(session.pending_question.questions[1].isOptionSelected(0));
    try std.testing.expect(session.pending_question.questions[1].isOptionSelected(1));
    try std.testing.expectEqualStrings("Also check neck-down length", session.pending_question.questions[1].write_in.slice());

    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(std.testing.allocator);
    try session.buildQuestionInteractionPayload(&payload, std.testing.allocator, false);
    try std.testing.expect(std.mem.indexOf(u8, payload.items, "\"stepIndex\":38") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload.items, "\"selectedOptionIds\":[\"2\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload.items, "\"selectedOptionIds\":[\"1\",\"2\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload.items, "\"writeInResponse\":\"Also check neck-down length\"") != null);
}

test "AgySession GetAllCascadeTrajectories parsing, sorting, and conversation resume" {
    var session = AgySession.init();
    defer session.deinit();

    const summaries_json =
        \\{"trajectorySummaries":{
        \\  "03442d23-8b0e-421b-bcd5-dd58ff0f746f":{
        \\    "summary":"App Framework Structural Improvements",
        \\    "stepCount":78,
        \\    "lastModifiedTime":"2026-10-24T08:32:34Z",
        \\    "status":"CASCADE_RUN_STATUS_IDLE",
        \\    "workspaces":[{"workspaceFolderAbsoluteUri":"file:///Users/developer/Projects/editor"}]
        \\  },
        \\  "2bf2cb86-72bd-4c13-8536-f142d94b6735":{
        \\    "summary":"",
        \\    "stepCount":149,
        \\    "lastModifiedTime":"2026-10-24T08:27:55Z",
        \\    "status":"CASCADE_RUN_STATUS_IDLE",
        \\    "workspaces":[{"workspaceFolderAbsoluteUri":"file:///Users/developer/.gemini/antigravity/worktrees/03442d23/subagent-self"}]
        \\  },
        \\  "02a11b66-eec4-4efb-8711-233dcb59fdde":{
        \\    "summary":"Editor Git Integration Refresh Issue",
        \\    "stepCount":410,
        \\    "lastModifiedTime":"2026-10-25T00:17:26Z",
        \\    "status":"CASCADE_RUN_STATUS_IDLE",
        \\    "workspaces":[{"workspaceFolderAbsoluteUri":"file:///Users/developer/Projects/editor"}]
        \\  }
        \\}}
    ;

    try std.testing.expect(session.parseConversationsResponse(summaries_json));
    const convs = session.availableConversations();
    // Subagent worktree with empty title is filtered out; remaining 2 are sorted newest first
    try std.testing.expectEqual(@as(usize, 2), convs.len);
    try std.testing.expectEqualStrings("02a11b66-eec4-4efb-8711-233dcb59fdde", convs[0].id());
    try std.testing.expectEqualStrings("Editor Git Integration Refresh Issue", convs[0].title());
    try std.testing.expectEqualStrings("editor", convs[0].workspaceBasename());
    try std.testing.expectEqualStrings("10-25", convs[0].shortDate());
    try std.testing.expectEqual(@as(u32, 410), convs[0].step_count);

    try std.testing.expectEqualStrings("03442d23-8b0e-421b-bcd5-dd58ff0f746f", convs[1].id());
    try std.testing.expectEqualStrings("App Framework Structural Improvements", convs[1].title());

    // Simulate resuming conversation 0
    _ = session.loadConversation(convs[0].id());
    session.loading_conversation = true;
    try std.testing.expectEqualStrings("02a11b66-eec4-4efb-8711-233dcb59fdde", session.conversationId());
    try std.testing.expectEqualStrings("Editor Git Integration Refresh Issue", session.activeTitle());

    const resumed_traj =
        \\{"status":"CASCADE_RUN_STATUS_IDLE","trajectory":{"steps":[
        \\  {"type":"CORTEX_STEP_TYPE_USER_INPUT","status":"CORTEX_STEP_STATUS_DONE","userInput":{"items":[{"text":"<USER_REQUEST>\nFix git status refresh\n</USER_REQUEST>"}]}},
        \\  {"type":"CORTEX_STEP_TYPE_PLANNER_RESPONSE","status":"CORTEX_STEP_STATUS_DONE","plannerResponse":{"thinking":"Inspecting `GitStatusPoller` non-blocking pipe handling.","thinkingDuration":"5.081949s","toolCalls":[{"id":"c1","name":"run_command","argumentsJson":"{\"CommandLine\":\"zig build test\",\"toolSummary\":\"Run unit tests\"}"}]}},
        \\  {"type":"CORTEX_STEP_TYPE_RUN_COMMAND","status":"CORTEX_STEP_STATUS_DONE","runCommand":{"commandLine":"zig build test","exitCode":0,"combinedOutput":{"full":"Command exited with code 0.\n\nCommand output:\nAll 42 tests passed."}}},
        \\  {"type":"CORTEX_STEP_TYPE_PLANNER_RESPONSE","status":"CORTEX_STEP_STATUS_DONE","plannerResponse":{"response":"Updated `GitStatusPoller`."}}
        \\]}}
    ;
    try std.testing.expect(session.parseTrajectoryResponse(resumed_traj));
    try std.testing.expect(!session.loading_conversation);
    try std.testing.expect(!session.is_running_turn);
    try std.testing.expectEqualStrings("Loaded · Ready", session.statusText());
    try std.testing.expectEqual(@as(usize, 4), session.chatEntries().len);
    try std.testing.expectEqual(ChatEntryKind.user_prompt, session.chatEntries()[0].kind);
    try std.testing.expectEqualStrings("Fix git status refresh", session.entryText(session.chatEntries()[0]));
    try std.testing.expectEqual(ChatEntryKind.thinking, session.chatEntries()[1].kind);
    try std.testing.expectEqualStrings("Inspecting `GitStatusPoller` non-blocking pipe handling.", session.entryText(session.chatEntries()[1]));
    try std.testing.expectEqualStrings("Thought for 5s", session.entryAuxText(session.chatEntries()[1]));
    try std.testing.expect(!session.isThinkingExpanded(1, false));
    session.toggleThinkingExpanded(1, false);
    try std.testing.expect(session.isThinkingExpanded(1, false));
    session.toggleThinkingExpanded(1, true);
    try std.testing.expect(!session.isThinkingExpanded(1, false));
    try std.testing.expectEqual(ChatEntryKind.shell_command, session.chatEntries()[2].kind);
    try std.testing.expectEqualStrings("zig build test", session.entryText(session.chatEntries()[2]));
    try std.testing.expectEqualStrings("Run unit tests", session.entryAuxText(session.chatEntries()[2]));
    try std.testing.expectEqualStrings("All 42 tests passed.", session.entryDetailText(session.chatEntries()[2]));
    try std.testing.expectEqual(@as(i16, 0), session.chatEntries()[2].exit_code);
    try std.testing.expectEqual(ChatEntryKind.assistant_markdown, session.chatEntries()[3].kind);
    try std.testing.expectEqualStrings("Updated `GitStatusPoller`.", session.entryText(session.chatEntries()[3]));

    // Verify workspace matching excludes broad volume/home roots (`/Volumes/Skore`, `/Users/u/Projects`)
    try std.testing.expect(isBroadContainerPath("/Volumes/Skore"));
    try std.testing.expect(isBroadContainerPath("/Users/developer/Projects"));
    try std.testing.expect(!isBroadContainerPath("/Volumes/Skore/firmware/esp32v1_zig"));
    try std.testing.expect(!doesConversationMatchWorkspace(
        "/Volumes/Skore",
        "",
        "/Volumes/Skore/firmware/esp32v1_zig",
        "/Volumes/Skore/firmware/esp32v1_zig",
    ));
    try std.testing.expect(!doesConversationMatchWorkspace(
        "/Volumes/Skore/firmware/esp32v1",
        "/Volumes/Skore/firmware/esp32v1",
        "/Volumes/Skore/firmware/esp32v1_zig",
        "/Volumes/Skore/firmware/esp32v1_zig",
    ));
    try std.testing.expect(doesConversationMatchWorkspace(
        "/Volumes/Skore/firmware/esp32v1_zig",
        "/Volumes/Skore/firmware/esp32v1_zig",
        "/Volumes/Skore/firmware/esp32v1_zig/app_core",
        "/Volumes/Skore/firmware/esp32v1_zig",
    ));
}

test "AgySession: image attachment persistence, base64 SendUserCascadeMessage media, and trajectory media URI parsing" {
    const alloc = std.testing.allocator;
    const session = try alloc.create(AgySession);
    defer alloc.destroy(session);
    session.* = AgySession.init();
    defer session.deinit();

    // Minimal valid 1x1 PNG bytes
    const sample_png = [_]u8{
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
        0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
        0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
        0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
        0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
        0x42, 0x60, 0x82,
    };

    try std.testing.expect(session.addImageAttachmentFromBytes(&sample_png, "image/png", "screenshot.png", "", 1, 1));
    try std.testing.expectEqual(@as(usize, 1), session.pendingAttachments().len);
    const saved_path = session.pendingAttachments()[0].path();
    try std.testing.expect(std.mem.startsWith(u8, saved_path, "/tmp/lightning_paste_"));
    try std.testing.expect(std.mem.endsWith(u8, saved_path, ".png"));

    _ = session.loadConversation("test-conv-uuid-1234");
    var payload_buf: std.ArrayList(u8) = .empty;
    defer payload_buf.deinit(alloc);
    try session.buildSendUserMessagePayload("Please inspect this screenshot", session.pendingAttachments(), &payload_buf, alloc);
    const payload = payload_buf.items;

    try std.testing.expect(std.mem.indexOf(u8, payload, "\"cascadeId\":\"test-conv-uuid-1234\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"media\":[{\"mimeType\":\"image/png\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"inlineData\":\"iVBORw0KGgo") != null);

    // Parse trajectory containing userInput.media
    const media_traj =
        \\{"status":"CASCADE_RUN_STATUS_IDLE","trajectory":{"steps":[
        \\  {"type":"CORTEX_STEP_TYPE_USER_INPUT","status":"CORTEX_STEP_STATUS_DONE","userInput":{"items":[{"text":"What is in this screenshot?"}],"media":[{"mimeType":"image/png","uri":"/tmp/test_paste_img.png"}]}},
        \\  {"type":"CORTEX_STEP_TYPE_PLANNER_RESPONSE","status":"CORTEX_STEP_STATUS_DONE","plannerResponse":{"response":"I see a 1x1 test image."}}
        \\]}}
    ;
    try std.testing.expect(session.parseTrajectoryResponse(media_traj));
    try std.testing.expectEqual(@as(usize, 2), session.chatEntries().len);
    try std.testing.expectEqual(ChatEntryKind.user_prompt, session.chatEntries()[0].kind);
    try std.testing.expectEqualStrings("What is in this screenshot?", session.entryText(session.chatEntries()[0]));
    try std.testing.expectEqualStrings("/tmp/test_paste_img.png", session.entryAuxText(session.chatEntries()[0]));
}

test "AgySession: daemon hub_4400.json discovery, Linux ss -tlnp + binfmt_misc port parsing, and Linux /home container paths" {
    // 1. Parse `~/.gemini/antigravity-cli/daemon/hub_4400.json`
    const hub_json =
        \\{
        \\  "pid": 63503,
        \\  "httpsPort": 62643,
        \\  "httpPort": 4400,
        \\  "lsVersion": "2.28.2",
        \\  "csrfToken": "d7089b4e-90d8-427b-bf11-159ac95eff93"
        \\}
    ;
    var pid: u32 = 0;
    var http_port: u16 = 0;
    var https_port: u16 = 0;
    var csrf_buf: [96]u8 = @splat(0);
    var csrf_len: u8 = 0;
    try std.testing.expect(parseHubDaemonJson(hub_json, &pid, &http_port, &https_port, &csrf_buf, &csrf_len));
    try std.testing.expectEqual(@as(u32, 63503), pid);
    try std.testing.expectEqual(@as(u16, 4400), http_port);
    try std.testing.expectEqual(@as(u16, 62643), https_port);
    try std.testing.expectEqualStrings("d7089b4e-90d8-427b-bf11-159ac95eff93", csrf_buf[0..csrf_len]);

    // 2. Parse `ss -tlnp` output on ARMv7 Linux with `binfmt_misc` (`qemu-aarch64` / `agy`)
    const ss_sample =
        \\State  Recv-Q Send-Q Local Address:Port   Peer Address:PortProcess
        \\LISTEN 0      4096       127.0.0.1:42969       0.0.0.0:*    users:(("agy",pid=6350,fd=12))
        \\LISTEN 0      4096       127.0.0.1:62643       0.0.0.0:*    users:(("qemu-aarch64",pid=63503,fd=11))
        \\LISTEN 0      4096       127.0.0.1:4400        0.0.0.0:*    users:(("agy",pid=63503,fd=14))
    ;
    var ports: [4]u16 = @splat(0);
    const port_count = parseListeningPortsFromSsOutput(ss_sample, 63503, &ports);
    try std.testing.expectEqual(@as(usize, 2), port_count);
    try std.testing.expectEqual(@as(u16, 62643), ports[0]);
    try std.testing.expectEqual(@as(u16, 4400), ports[1]);

    // 3. Extract `--csrf_token` from `binfmt_misc` command line
    const binfmt_cmd = "63503 /usr/bin/qemu-aarch64 /home/matthewsessions/.local/bin/agy --hub --csrf_token=d7089b4e-90d8-427b-bf11-159ac95eff93";
    try std.testing.expectEqualStrings(
        "d7089b4e-90d8-427b-bf11-159ac95eff93",
        extractCmdFlagValue(binfmt_cmd, "--csrf_token").?,
    );

    // 4. Verify Linux `/home/<user>` broad container path filtering
    try std.testing.expect(isBroadContainerPath("/home"));
    try std.testing.expect(isBroadContainerPath("/home/matthewsessions"));
    try std.testing.expect(isBroadContainerPath("/home/matthewsessions/Projects"));
    try std.testing.expect(!isBroadContainerPath("/home/matthewsessions/lightning-armv7"));

    // 5. Verify model config retry reset on startup auth error and SearchConversations SQLite summary merging
    const alloc = std.testing.allocator;
    const session = try alloc.create(AgySession);
    defer alloc.destroy(session);
    session.* = AgySession.init();
    defer session.deinit();

    session.models_attempted = true;
    session.parseModelConfigResponse("{\"errorMessage\":\"failed to get load code assist response: error getting token source: You are not logged into Antigravity.\"}");
    try std.testing.expect(!session.models_fetched);
    try std.testing.expect(!session.models_attempted);

    session.models_attempted = true;
    session.parseModelConfigResponse("{\"clientModelConfigs\":[{\"label\":\"Gemini 4 Argon (Medium)\",\"modelOrAlias\":{\"model\":\"MODEL_PLACEHOLDER_M418\"}}]}");
    try std.testing.expect(session.models_fetched);
    try std.testing.expect(session.models_attempted);
    try std.testing.expectEqual(@as(usize, 1), session.model_count);
    try std.testing.expectEqualStrings("Gemini 4 Argon (Medium)", session.availableModels()[0].label());

    session.syncWorkspaceRoot("/home/matthewsessions/lightning-armv7");
    try std.testing.expect(session.parseConversationsResponse(
        \\{"trajectorySummaries":{"acd44a38-8671-45a9-8218-04b7dd7e6fa0":{"summary":"list a couple files","stepCount":4,"lastModifiedTime":"2026-11-01T07:20:33Z","workspaces":[{"workspaceFolderAbsoluteUri":"file:///home/matthewsessions/lightning-armv7/bin"}]}}}
    ));
    try std.testing.expectEqual(@as(usize, 1), session.conversation_count);
    try std.testing.expect(session.availableConversations()[0].matches_cwd);

    // Merge SQLite `/SearchConversations` results without overwriting the richer in-memory summary
    try std.testing.expect(session.parseConversationsResponse(
        \\{"results":[
        \\  {"cascadeId":"acd44a38-8671-45a9-8218-04b7dd7e6fa0","title":"list a couple files","workspaceName":"bin","lastModifiedTime":"2026-11-01T07:20:33Z"},
        \\  {"cascadeId":"fff48321-a03b-4c1b-bff7-5b9ce2e48f68","title":"Listing Files in Directory","workspaceName":"lightning-armv7","lastModifiedTime":"2026-11-01T05:56:43Z"}
        \\]}
    ));
    try std.testing.expectEqual(@as(usize, 2), session.conversation_count);
    try std.testing.expectEqual(@as(u32, 4), session.availableConversations()[0].step_count);
    try std.testing.expectEqualStrings("Listing Files in Directory", session.availableConversations()[1].title());
    try std.testing.expect(session.availableConversations()[1].matches_cwd);
}
