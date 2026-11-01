//! Antigravity Supercomplete Engine (`src/app/supercomplete.zig`).
//!
//! Native Zig port of the Antigravity Supercomplete for Eclipse Theia extension:
//!   - Discovers the running Antigravity Language Server (`language_server` / `agy --hub`)
//!     loopback port and `csrf_token` (or spawns a standalone `language_server` hub if none is active).
//!   - Communicates via non-blocking ConnectRPC over HTTP/1.1 (`127.0.0.1:<port>`) to
//!     `/exa.language_server_pb.LanguageServerService/HandleStreamingCommand`
//!     using 5-byte framed streaming envelopes (`[0x00][uint32 BE length][JSON]`).
//!   - Reconciles window-relative `characterDiff.changes` against the cursor offset (`extractInsertItem`).
//!   - Enforces the Theia extension's language-agnostic guards:
//!       1. Acceptance cooldown (suppresses auto-chaining after `Tab` until next user keystroke)
//!       2. Mid-word suppression (skips auto-trigger when cursor is inside an identifier)
//!       3. 75ms typing debounce & instant in-flight cancellation on new keystrokes

const std = @import("std");
const builtin = @import("builtin");
const platform = @import("platform");
const agy_client = @import("agy_client.zig");

const is_windows = (builtin.os.tag == .windows);
const popen = platform.fs_util.popen;
const pclose = platform.fs_util.pclose;
extern "c" fn fgets(s: [*]u8, n: c_int, stream: *std.c.FILE) ?[*]u8;

const posix_net = if (!is_windows) struct {
    pub const AF_INET: c_int = 2;
    pub const SOCK_STREAM: c_int = 1;
    pub const F_GETFL: c_int = 3;
    pub const F_SETFL: c_int = 4;
    pub const O_NONBLOCK: c_int = if (builtin.os.tag == .linux) 0x0800 else 0x0004;
    pub const MSG_NOSIGNAL: c_int = 0x20000; // SO_NOSIGPIPE on macOS
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
            return 0;
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

pub const InsertItem = struct {
    text: []const u8,
    delete_len: usize = 0,
};

pub const MaxGhostTextBytes: usize = 2048;
pub const MaxResponseBufBytes: usize = 65536;

pub const SupercompleteClient = struct {
    enabled: bool = true,

    // Discovered Antigravity Hub / Language Server connection details
    ls_port: u16 = 0,
    alt_port: u16 = 0,
    csrf_buf: [96]u8 = @splat(0),
    csrf_len: u8 = 0,
    last_attach_attempt_ms: i64 = 0,

    // Interaction guards (from Theia extension)
    suppress_until_next_input: bool = false,
    last_accepted_ms: i64 = 0,
    pending_trigger_ms: i64 = 0,
    pending_explicit: bool = false,
    pending_file_idx: usize = 0,
    pending_cursor_offset: usize = 0,
    pending_edit_version: u32 = 0,

    // Non-blocking in-flight HTTP/1.1 ConnectRPC request state
    sock_fd: c_int = -1,
    req_start_ms: i64 = 0,
    req_file_idx: usize = 0,
    req_cursor_offset: usize = 0,
    req_edit_version: u32 = 0,
    tx_buf: std.ArrayList(u8) = .empty,
    tx_sent: usize = 0,
    rx_buf: [MaxResponseBufBytes]u8 = undefined,
    rx_len: usize = 0,

    // Active inline ghost-text suggestion for the current buffer & cursor offset
    ghost_buf: [MaxGhostTextBytes]u8 = @splat(0),
    ghost_len: usize = 0,
    ghost_delete_len: usize = 0,
    ghost_file_idx: usize = 0,
    ghost_cursor_offset: usize = 0,
    ghost_edit_version: u32 = 0,
    active_poll_frames: u32 = 0,

    pub fn init() SupercompleteClient {
        return .{};
    }

    pub fn deinit(self: *SupercompleteClient) void {
        self.cancelRequest();
        self.tx_buf.deinit(std.heap.c_allocator);
    }

    pub fn isConnected(self: *const SupercompleteClient) bool {
        return self.ls_port > 0 and self.csrf_len > 0;
    }

    pub fn csrfToken(self: *const SupercompleteClient) []const u8 {
        return self.csrf_buf[0..@min(@as(usize, self.csrf_len), self.csrf_buf.len)];
    }

    pub fn clearGhost(self: *SupercompleteClient) void {
        self.ghost_len = 0;
        self.ghost_delete_len = 0;
    }

    /// Returns the active ghost-text completion if it matches the given `file_idx`, `cursor_offset`, and `edit_version`.
    pub fn activeGhostFor(
        self: *const SupercompleteClient,
        file_idx: usize,
        cursor_offset: usize,
        edit_version: u32,
    ) ?InsertItem {
        if (!self.enabled or self.ghost_len == 0) return null;
        if (self.ghost_file_idx != file_idx or
            self.ghost_cursor_offset != cursor_offset or
            self.ghost_edit_version != edit_version)
        {
            return null;
        }
        return .{
            .text = self.ghost_buf[0..self.ghost_len],
            .delete_len = self.ghost_delete_len,
        };
    }

    /// Called when the user accepts a ghost-text completion via `Tab`.
    /// Enforces Guard 1 (Acceptance Cooldown): suppresses auto-chaining until the next real user edit.
    pub fn onAccepted(self: *SupercompleteClient, now_ms: i64) void {
        self.clearGhost();
        self.cancelRequest();
        self.pending_trigger_ms = 0;
        self.last_accepted_ms = now_ms;
        self.suppress_until_next_input = true;
    }

    /// Called when the user presses `Esc` or moves the cursor away from the suggestion.
    pub fn onDismissed(self: *SupercompleteClient) void {
        self.clearGhost();
        self.cancelRequest();
        self.pending_trigger_ms = 0;
    }

    /// Called when the user edits the active buffer (`text_changed`).
    /// Schedules a debounced (75ms) Supercomplete query after canceling any in-flight request.
    pub fn onUserTextChanged(
        self: *SupercompleteClient,
        now_ms: i64,
        file_idx: usize,
        doc_text: []const u8,
        cursor_offset: usize,
        edit_version: u32,
    ) void {
        self.clearGhost();
        self.cancelRequest();

        if (!self.enabled) return;

        // Re-enable auto-triggers once user types > 150ms after accepting a suggestion
        if (now_ms - self.last_accepted_ms > 150) {
            self.suppress_until_next_input = false;
        }

        // Guard 1: Don't auto-chain after an accept until the user types something new
        if (self.suppress_until_next_input or (now_ms - self.last_accepted_ms < 350)) {
            return;
        }

        // Guard 2: Don't auto-complete inside existing identifiers (mid-word)
        if (cursor_offset < doc_text.len) {
            const ch_after = doc_text[cursor_offset];
            if (isWordChar(ch_after)) {
                return;
            }
        }

        // Guard 3: 75ms typing debounce
        self.pending_trigger_ms = now_ms + 75;
        self.pending_explicit = false;
        self.pending_file_idx = file_idx;
        self.pending_cursor_offset = cursor_offset;
        self.pending_edit_version = edit_version;
        self.active_poll_frames = 30;
    }

    /// Explicitly triggers a Supercomplete suggestion immediately (bypassing cooldown, mid-word, and debounce guards).
    pub fn triggerExplicit(
        self: *SupercompleteClient,
        now_ms: i64,
        file_idx: usize,
        cursor_offset: usize,
        edit_version: u32,
    ) void {
        self.enabled = true;
        self.suppress_until_next_input = false;
        self.clearGhost();
        self.cancelRequest();
        self.pending_trigger_ms = now_ms;
        self.pending_explicit = true;
        self.pending_file_idx = file_idx;
        self.pending_cursor_offset = cursor_offset;
        self.pending_edit_version = edit_version;
        self.active_poll_frames = 90;
    }

    pub fn cancelRequest(self: *SupercompleteClient) void {
        if (self.sock_fd >= 0) {
            closeLoopbackSocket(self.sock_fd);
            self.sock_fd = -1;
        }
        self.tx_buf.clearRetainingCapacity();
        self.tx_sent = 0;
        self.rx_len = 0;
    }

    // ========================================================================
    // Antigravity Hub (`language_server` / `agy --hub` / `~/.gemini/.../daemon/*.json`) Discovery
    // ========================================================================

    pub fn attach(self: *SupercompleteClient, now_ms: i64) bool {
        self.last_attach_attempt_ms = now_ms;
        return agy_client.discoverRunningHub(
            &self.ls_port,
            &self.alt_port,
            &self.csrf_buf,
            &self.csrf_len,
        );
    }

    const extractFlagValue = agy_client.extractCmdFlagValue;

    // ========================================================================
    // Non-Blocking ConnectRPC Streaming Request & Poll Loop
    // ========================================================================

    pub fn poll(
        self: *SupercompleteClient,
        now_ms: i64,
        active_file_idx: usize,
        abs_uri: []const u8,
        lang_id: []const u8,
        doc_text: []const u8,
        cursor_offset: usize,
        cursor_row: usize,
        cursor_col: usize,
        edit_version: u32,
    ) bool {
        var changed = false;

        // 1. Check if a debounced trigger is ready to fire
        if (self.pending_trigger_ms > 0 and now_ms >= self.pending_trigger_ms) {
            const is_same_pos = (self.pending_file_idx == active_file_idx and
                self.pending_cursor_offset == cursor_offset and
                self.pending_edit_version == edit_version);
            self.pending_trigger_ms = 0;

            if (is_same_pos and self.enabled) {
                if (!self.isConnected() and (now_ms - self.last_attach_attempt_ms > 2000 or self.pending_explicit)) {
                    _ = self.attach(now_ms);
                }
                if (self.isConnected()) {
                    _ = self.startConnectRpcRequest(
                        now_ms,
                        active_file_idx,
                        abs_uri,
                        lang_id,
                        doc_text,
                        cursor_offset,
                        cursor_row,
                        cursor_col,
                        edit_version,
                    );
                }
            }
        }

        // 2. Drive non-blocking socket I/O if a request is in-flight
        if (self.sock_fd >= 0) {
            self.active_poll_frames = 30;

            // Cancel if user moved cursor or switched files
            if (self.req_file_idx != active_file_idx or
                self.req_cursor_offset != cursor_offset or
                self.req_edit_version != edit_version or
                now_ms - self.req_start_ms > 3000)
            {
                self.cancelRequest();
                return changed;
            }

            // Write remaining request bytes
            if (self.tx_sent < self.tx_buf.items.len) {
                const rem = self.tx_buf.items[self.tx_sent..];
                const n = writeLoopbackSocket(self.sock_fd, rem.ptr, rem.len);
                if (n > 0) {
                    self.tx_sent += @intCast(n);
                }
            }

            // Read available response bytes
            var temp: [4096]u8 = undefined;
            var eof = false;
            var loops: usize = 0;
            while (loops < 8 and self.rx_len < self.rx_buf.len) : (loops += 1) {
                const avail = self.rx_buf.len - self.rx_len;
                const n = readLoopbackSocket(self.sock_fd, &temp, @min(temp.len, avail));
                if (n < 0) break;
                if (n == 0) {
                    eof = true;
                    break;
                }
                const un: usize = @intCast(n);
                @memcpy(self.rx_buf[self.rx_len .. self.rx_len + un], temp[0..un]);
                self.rx_len += un;
            }

            // Parse HTTP response once complete (or as streaming frames arrive)
            if (self.rx_len > 0) {
                if (self.processHttpResponse(doc_text, cursor_offset)) {
                    changed = true;
                }
            }

            if (eof) {
                self.cancelRequest();
            }
        } else if (self.active_poll_frames > 0) {
            self.active_poll_frames -= 1;
        }

        return changed;
    }

    fn startConnectRpcRequest(
        self: *SupercompleteClient,
        now_ms: i64,
        file_idx: usize,
        abs_uri: []const u8,
        lang_id: []const u8,
        doc_text: []const u8,
        cursor_offset: usize,
        cursor_row: usize,
        cursor_col: usize,
        edit_version: u32,
    ) bool {
        self.cancelRequest();
        if (!self.isConnected()) return false;

        // Build JSON payload matching the Theia extension
        var json_list: std.ArrayList(u8) = .empty;
        defer json_list.deinit(std.heap.c_allocator);
        const alloc = std.heap.c_allocator;

        json_list.appendSlice(
            alloc,
            "{\"metadata\":{\"ideName\":\"antigravity\",\"ideVersion\":\"2.22.0\",\"extensionName\":\"antigravity\",\"locale\":\"en\"},\"document\":{\"text\":\"",
        ) catch return false;
        appendJsonEscaped(&json_list, alloc, doc_text) catch return false;

        var tail_buf: [512]u8 = undefined;
        const tail = std.fmt.bufPrint(
            &tail_buf,
            "\",\"editorLanguage\":\"{s}\",\"cursorOffset\":{d},\"cursorPosition\":{{\"row\":{d},\"col\":{d}}},\"absoluteUri\":\"{s}\"}},\"requestSource\":10,\"diffType\":4,\"supercompleteTriggerCondition\":3}}",
            .{ lang_id, cursor_offset, cursor_row, cursor_col, abs_uri },
        ) catch return false;
        json_list.appendSlice(alloc, tail) catch return false;

        // 5-byte ConnectRPC envelope: [0x00][uint32 BE length][JSON]
        const frame_len = json_list.items.len;
        const body_len = 5 + frame_len;

        var hdr_buf: [512]u8 = undefined;
        const hdr = std.fmt.bufPrint(
            &hdr_buf,
            "POST /exa.language_server_pb.LanguageServerService/HandleStreamingCommand HTTP/1.1\r\n" ++
                "Host: 127.0.0.1:{d}\r\n" ++
                "Content-Type: application/connect+json\r\n" ++
                "Content-Length: {d}\r\n" ++
                "x-codeium-csrf-token: {s}\r\n" ++
                "Connection: close\r\n\r\n",
            .{ self.ls_port, body_len, self.csrfToken() },
        ) catch return false;

        self.tx_buf.clearRetainingCapacity();
        self.tx_buf.appendSlice(alloc, hdr) catch return false;
        var env_hdr: [5]u8 = .{ 0, 0, 0, 0, 0 };
        std.mem.writeInt(u32, env_hdr[1..5], @intCast(frame_len), .big);
        self.tx_buf.appendSlice(alloc, &env_hdr) catch return false;
        self.tx_buf.appendSlice(alloc, json_list.items) catch return false;

        // Open non-blocking loopback TCP socket
        const fd = openLoopbackSocket(self.ls_port);
        if (fd < 0) return false;

        self.sock_fd = fd;
        self.req_start_ms = now_ms;
        self.req_file_idx = file_idx;
        self.req_cursor_offset = cursor_offset;
        self.req_edit_version = edit_version;
        self.tx_sent = 0;
        self.rx_len = 0;
        self.active_poll_frames = 60;
        return true;
    }

    fn processHttpResponse(self: *SupercompleteClient, doc_text: []const u8, cursor_offset: usize) bool {
        const raw = self.rx_buf[0..self.rx_len];
        const hdr_end = std.mem.indexOf(u8, raw, "\r\n\r\n") orelse return false;
        const headers = raw[0..hdr_end];
        const body_raw = raw[hdr_end + 4 ..];

        // If we accidentally hit the HTTPS port (`400 Bad Request`), swap to `alt_port`
        if (std.mem.indexOf(u8, headers, "400 Bad Request") != null or
            std.mem.indexOf(u8, body_raw, "HTTPS server") != null)
        {
            if (self.alt_port > 0 and self.alt_port != self.ls_port) {
                const tmp = self.ls_port;
                self.ls_port = self.alt_port;
                self.alt_port = tmp;
            } else {
                self.ls_port = 0;
            }
            self.cancelRequest();
            return false;
        }

        if (std.mem.indexOf(u8, headers, "200 OK") == null) {
            return false;
        }

        // Unchunk HTTP body if `Transfer-Encoding: chunked` is present
        var body_storage: [MaxResponseBufBytes]u8 = undefined;
        const payload = if (containsIgnoreCaseAscii(headers, "transfer-encoding: chunked"))
            decodeChunkedBody(body_raw, &body_storage)
        else
            body_raw;

        // Walk ConnectRPC 5-byte frames (`[flags: 1B][len: 4B BE][json]`), keeping the latest valid match
        var matched = false;
        var pos: usize = 0;
        while (pos + 5 <= payload.len) {
            const frame_flags = payload[pos];
            const frame_len: usize = std.mem.readInt(u32, payload[pos + 1 ..][0..4], .big);
            pos += 5;
            if (pos + frame_len > payload.len) break;
            const frame_bytes = payload[pos .. pos + frame_len];
            pos += frame_len;

            if (frame_flags == 0 and frame_bytes.len > 2) {
                if (extractInsertItem(std.heap.c_allocator, doc_text, cursor_offset, frame_bytes)) |item| {
                    defer std.heap.c_allocator.free(item.text);
                    if (item.text.len > 0 and item.text.len <= self.ghost_buf.len) {
                        @memcpy(self.ghost_buf[0..item.text.len], item.text);
                        self.ghost_len = item.text.len;
                        self.ghost_delete_len = item.delete_len;
                        self.ghost_file_idx = self.req_file_idx;
                        self.ghost_cursor_offset = self.req_cursor_offset;
                        self.ghost_edit_version = self.req_edit_version;
                        matched = true;
                    }
                }
            }
        }
        return matched;
    }
};

// ============================================================================
// Window-Relative Diff Reconciliation (`getInsertItem` from Theia Extension)
// ============================================================================

/// Parses a single ConnectRPC JSON frame from `HandleStreamingCommand` and reconciles
/// window-relative `characterDiff.changes` against `doc_text[0..cursor_offset]`.
/// Caller owns the returned `InsertItem.text` slice allocated from `allocator`.
pub fn extractInsertItem(
    allocator: std.mem.Allocator,
    doc_text: []const u8,
    cursor_offset: usize,
    frame_json: []const u8,
) ?InsertItem {
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, frame_json, .{}) catch return null;
    defer parsed.deinit();

    if (parsed.value != .object) return null;
    const root = parsed.value.object;

    // 1. Direct text fields (`rawText`, `insertText`)
    if (getJsonString(root, "rawText")) |s| {
        if (s.len > 0) return dupItem(allocator, s, 0);
    }
    if (getJsonString(root, "insertText")) |s| {
        if (s.len > 0) return dupItem(allocator, s, 0);
    }

    // 2. Window-relative `characterDiff.changes` reconciliation
    const clamped_cursor = @min(cursor_offset, doc_text.len);
    const text_before_cursor = doc_text[0..clamped_cursor];

    if (root.get("characterDiff")) |cd_val| {
        if (cd_val == .object) {
            if (cd_val.object.get("changes")) |changes_val| {
                if (changes_val == .array) {
                    const items = changes_val.array.items;
                    for (items, 0..) |c_val, i| {
                        if (c_val != .object) continue;
                        const c_obj = c_val.object;
                        if (!isChangeInsert(c_obj)) continue;
                        const c_text = getJsonString(c_obj, "text") orelse continue;
                        if (c_text.len == 0) continue;

                        if (i > 0) {
                            const prev_val = items[i - 1];
                            if (prev_val == .object) {
                                const prev_obj = prev_val.object;
                                const prev_text = getJsonString(prev_obj, "text") orelse "";
                                if (isChangeDelete(prev_obj)) {
                                    if (prev_text.len > 0 and std.mem.endsWith(u8, text_before_cursor, prev_text)) {
                                        return dupItem(allocator, c_text, prev_text.len);
                                    }
                                }
                                const match_len = @min(prev_text.len, 30);
                                if (match_len == 0 or std.mem.endsWith(u8, text_before_cursor, prev_text[prev_text.len - match_len ..])) {
                                    return dupItem(allocator, c_text, 0);
                                }
                            }
                        } else {
                            return dupItem(allocator, c_text, 0);
                        }
                    }
                }
            }
        }
    }

    // 3. Fallback: `diff.lines` (`UNIFIED_DIFF_LINE_TYPE_INSERT`)
    if (root.get("diff")) |diff_val| {
        if (diff_val == .object) {
            if (diff_val.object.get("lines")) |lines_val| {
                if (lines_val == .array) {
                    var acc: std.ArrayList(u8) = .empty;
                    defer acc.deinit(allocator);
                    for (lines_val.array.items) |l_val| {
                        if (l_val != .object) continue;
                        const l_obj = l_val.object;
                        if (isUnifiedLineInsert(l_obj)) {
                            const t = getJsonString(l_obj, "text") orelse "";
                            if (acc.items.len > 0) acc.append(allocator, '\n') catch {};
                            acc.appendSlice(allocator, t) catch {};
                        }
                    }
                    if (acc.items.len > 0) {
                        return dupItem(allocator, acc.items, 0);
                    }
                }
            }
        }
    }

    return null;
}

fn dupItem(allocator: std.mem.Allocator, text: []const u8, delete_len: usize) ?InsertItem {
    const trimmed_end = std.mem.trimEnd(u8, text, " \r\n");
    const final_slice = if (trimmed_end.len > 0) trimmed_end else text;
    if (final_slice.len == 0) return null;
    const copy = allocator.dupe(u8, final_slice) catch return null;
    return .{ .text = copy, .delete_len = delete_len };
}

fn isChangeInsert(obj: std.json.ObjectMap) bool {
    const v = obj.get("type") orelse return false;
    return switch (v) {
        .integer => |n| n == 1,
        .string => |s| std.mem.eql(u8, s, "DIFF_CHANGE_TYPE_INSERT"),
        else => false,
    };
}

fn isChangeDelete(obj: std.json.ObjectMap) bool {
    const v = obj.get("type") orelse return false;
    return switch (v) {
        .integer => |n| n == 2,
        .string => |s| std.mem.eql(u8, s, "DIFF_CHANGE_TYPE_DELETE"),
        else => false,
    };
}

fn isUnifiedLineInsert(obj: std.json.ObjectMap) bool {
    const v = obj.get("type") orelse return false;
    return switch (v) {
        .integer => |n| n == 1,
        .string => |s| std.mem.eql(u8, s, "UNIFIED_DIFF_LINE_TYPE_INSERT"),
        else => false,
    };
}

fn getJsonString(obj: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    const v = obj.get(key) orelse return null;
    return switch (v) {
        .string => |s| s,
        else => null,
    };
}

fn isWordChar(ch: u8) bool {
    return std.ascii.isAlphanumeric(ch) or ch == '_';
}

fn containsIgnoreCaseAscii(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0 or needle.len > haystack.len) return false;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[i .. i + needle.len], needle)) return true;
    }
    return false;
}

fn decodeChunkedBody(src: []const u8, out: []u8) []const u8 {
    var in_pos: usize = 0;
    var out_pos: usize = 0;
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
        const copy_n = @min(chunk_len, out.len - out_pos);
        @memcpy(out[out_pos .. out_pos + copy_n], src[in_pos .. in_pos + copy_n]);
        out_pos += copy_n;
        in_pos += chunk_len;
        if (in_pos + 2 <= src.len and src[in_pos] == '\r' and src[in_pos + 1] == '\n') {
            in_pos += 2;
        }
    }
    return out[0..out_pos];
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

test "Supercomplete characterDiff window-relative reconciliation" {
    const doc = "const std = @import(\"std\");\npub fn add(a: i32, b: i32) i32 {\n    return ";
    const frame =
        \\{"completionId":"ff4db722","characterDiff":{"changes":[{"text":"const std = @import(\"std\");\npub fn add(a: i32, b: i32) i32 {\n    return ","type":"DIFF_CHANGE_TYPE_UNCHANGED"},{"text":"a + b;\n}","type":"DIFF_CHANGE_TYPE_INSERT"}]}}
    ;
    const item = extractInsertItem(std.testing.allocator, doc, doc.len, frame) orelse return error.TestUnexpectedResult;
    defer std.testing.allocator.free(item.text);

    try std.testing.expectEqualStrings("a + b;\n}", item.text);
    try std.testing.expectEqual(@as(usize, 0), item.delete_len);
}

test "Supercomplete characterDiff mid-token delete+insert replacement" {
    const doc = "pub fn main() void {\n    std.debug.pr";
    const frame =
        \\{"characterDiff":{"changes":[{"text":"    std.debug.","type":"DIFF_CHANGE_TYPE_UNCHANGED"},{"text":"pr","type":"DIFF_CHANGE_TYPE_DELETE"},{"text":"print(\"hello\\n\", .{});","type":"DIFF_CHANGE_TYPE_INSERT"}]}}
    ;
    const item = extractInsertItem(std.testing.allocator, doc, doc.len, frame) orelse return error.TestUnexpectedResult;
    defer std.testing.allocator.free(item.text);

    try std.testing.expectEqualStrings("print(\"hello\\n\", .{});", item.text);
    try std.testing.expectEqual(@as(usize, 2), item.delete_len);
}
