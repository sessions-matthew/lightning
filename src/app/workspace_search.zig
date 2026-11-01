//! Workspace-wide text search, O(1) frame memoization, and result navigation
//! extracted from `src/app/state.zig`.

const std = @import("std");
const ui = @import("ui");
const platform = @import("platform");
const workspace_fs = @import("workspace_fs.zig");
const state_mod = @import("state.zig");

const EditorState = state_mod.EditorState;
const isPdfCandidatePath = workspace_fs.isPdfCandidatePath;
const isImageCandidatePath = workspace_fs.isImageCandidatePath;
const isDatalessFileOnDisk = workspace_fs.isDatalessFileOnDisk;

pub const MaxWorkspaceSearchMatches: usize = 32;

pub const WorkspaceSearchMatch = struct {
    file_idx: u16 = 0,
    line_num: u32 = 1,
    snippet: platform.InlineString(32) = .{},
    trimmed_line: platform.InlineString(192) = .{},
};

pub const WorkspaceSearchResult = WorkspaceSearchMatch;

pub fn workspaceSearchQuery(self: *const EditorState) []const u8 {
    return self.workspace_search.slice();
}

/// Opens the Workspace Search sidebar (`Shift+Cmd+F`), pre-populating `workspace_search` from the
/// active buffer's single-line selection (if any), and focuses `##workspace_search_input` with all text selected.
pub fn openWorkspaceSearch(self: *EditorState) void {
    self.doc.show_command_palette = false;
    self.doc.show_sidebar = true;
    self.doc.active_sidebar_view = 1;

    if (self.activeSingleLineSelection()) |sel_slice| {
        if (sel_slice.len <= self.workspace_search.buf.len) {
            self.workspace_search.set(sel_slice);
        }
    }

    self.ui_ctx.focusAndSelectAll(ui.scopedIdPath(&.{ "vscode_workbench", "explorer_sidebar" }, "##workspace_search_input"));
    self.ui_ctx.invalidateWindow();
}

pub fn computeWorkspaceSearchSig(self: *const EditorState) u64 {
    var sig: u64 = (@as(u64, @intCast(self.file_count)) *% 0x9E37_79B9_7F4A_7C15) ^ self.last_watch_sig;
    const open_n = self.openBufferCount();
    for (0..open_n) |b_i| {
        const f_idx = self.doc.open_buffers[b_i];
        if (f_idx < self.file_count and self.buffer_initialized[f_idx]) {
            sig = (sig ^ (@as(u64, self.buffers[f_idx].edit_version) +% (@as(u64, f_idx) << 16))) *% 0xBF58_476D_1CE4_E5B9;
        }
    }
    if (self.activeFileIndex()) |act_idx| {
        if (act_idx < self.file_count and self.buffer_initialized[act_idx]) {
            sig = (sig ^ (@as(u64, self.buffers[act_idx].edit_version) *% 0x517C_C1B7_2722_0A95)) *% 0x94D0_49BB_1331_11EB;
        }
    }
    return sig | 1;
}

/// Returns up to `MaxWorkspaceSearchMatches` (32) workspace search results for `self.workspaceSearchQuery()`,
/// memoized across `.input` and `.paint` passes so steady frames perform zero file I/O or text scanning.
/// Prioritizes project source code files before `docs/` reference manuals and breaks out of the file loop
/// as soon as `MaxWorkspaceSearchMatches` matches are collected.
pub fn workspaceSearchMatches(self: *EditorState) []const WorkspaceSearchMatch {
    const query = self.workspaceSearchQuery();
    if (query.len == 0) {
        self.cached_search_query.clear();
        self.cached_search_match_count = 0;
        self.cached_search_sig = 0;
        return &.{};
    }

    const cur_sig = computeWorkspaceSearchSig(self);
    if (self.cached_search_sig == cur_sig and self.cached_search_query.eql(query)) {
        return self.cached_search_matches[0..self.cached_search_match_count];
    }

    self.cached_search_query.set(query);
    self.cached_search_sig = cur_sig;

    var match_count: usize = 0;
    const wfs = self.workspaceFiles();

    // If a PDF buffer (`*PDF Preview*` or `.pdf` file) is currently active or open, include its page matches first
    for (wfs, 0..) |file, f_idx| {
        if (match_count >= MaxWorkspaceSearchMatches) break;
        const is_pdf = file.is_pdf_preview or isPdfCandidatePath(file.path);
        if (!is_pdf) continue;
        if (!self.isBufferOpen(f_idx) and self.bufferVisibleInPane(f_idx) == null) continue;

        const is_direct = !file.is_pdf_preview and isPdfCandidatePath(file.path);
        if (is_direct and isDatalessFileOnDisk(file.path.ptr)) continue;
        const eff_path = if (is_direct) file.path else self.pdf_custom_path.slice();
        const eff_bytes = if (is_direct)
            self.buffers[f_idx].slice()
        else if (self.pdf_custom_bytes.len > 0)
            self.pdf_custom_bytes.slice()
        else if (eff_path.len > 0)
            ""
        else
            ui.SAMPLE_PDF_DOC;

        var pdf_doc = ui.PdfDocumentData{};
        ui.parsePdfDocument(eff_bytes, eff_path, &pdf_doc);
        const cached_n = @min(pdf_doc.page_count, pdf_doc.pages.len);
        for (0..cached_n) |p_idx| {
            if (match_count >= MaxWorkspaceSearchMatches) break;
            const page = &pdf_doc.pages[p_idx];
            for (page.lines[0..page.line_count]) |line_in| {
                const line = line_in.slice();
                if (ui.containsIgnoreCase(line, query)) {
                    const trimmed = std.mem.trim(u8, line, " \t\r");
                    const snippet_slice = if (trimmed.len > 22) trimmed[0..22] else trimmed;
                    var m = &self.cached_search_matches[match_count];
                    m.* = .{
                        .file_idx = @intCast(f_idx),
                        .line_num = @intCast(p_idx + 1),
                    };
                    m.snippet.set(snippet_slice);
                    m.trimmed_line.set(trimmed);
                    match_count += 1;
                    if (match_count >= MaxWorkspaceSearchMatches) break;
                }
            }
        }
    }

    // Pass 0 searches non-`docs/` project files first; Pass 1 searches `docs/` only if <32 matches were found
    for (0..2) |search_pass| {
        if (match_count >= MaxWorkspaceSearchMatches) break;
        for (wfs, 0..) |file, f_idx| {
            if (match_count >= MaxWorkspaceSearchMatches) break;
            if (file.isSpecial() or isPdfCandidatePath(file.path) or isImageCandidatePath(file.path)) continue;
            const is_docs_file = std.mem.startsWith(u8, file.path, "docs/");
            if ((search_pass == 0 and is_docs_file) or (search_pass == 1 and !is_docs_file)) continue;
            if (!self.loaded_from_disk[f_idx] and isDatalessFileOnDisk(file.path.ptr)) continue;

            self.ensureFileLoaded(f_idx);
            const text = self.buffers[f_idx].slice();
            if (query.len > text.len) continue;

            var pos: usize = 0;
            var cur_line: u32 = 1;
            var counted_up_to: usize = 0;
            while (ui.indexOfIgnoreCasePos(text, pos, query)) |match_off| {
                for (text[counted_up_to..match_off]) |ch| {
                    if (ch == '\n') cur_line += 1;
                }
                var line_start = match_off;
                while (line_start > 0 and text[line_start - 1] != '\n') : (line_start -= 1) {}
                var line_end = match_off + query.len;
                while (line_end < text.len and text[line_end] != '\n') : (line_end += 1) {}

                const line = text[line_start..line_end];
                const trimmed = std.mem.trim(u8, line, " \t\r");
                const snippet_slice = if (trimmed.len > 22) trimmed[0..22] else trimmed;

                var m = &self.cached_search_matches[match_count];
                m.* = .{
                    .file_idx = @intCast(f_idx),
                    .line_num = cur_line,
                };
                m.snippet.set(snippet_slice);
                m.trimmed_line.set(trimmed);
                match_count += 1;
                if (match_count >= MaxWorkspaceSearchMatches) break;

                counted_up_to = line_end;
                pos = if (line_end < text.len) line_end + 1 else text.len;
            }
        }
    }

    self.cached_search_match_count = match_count;
    return self.cached_search_matches[0..match_count];
}

pub const performWorkspaceSearch = workspaceSearchMatches;

pub fn openWorkspaceSearchResult(self: *EditorState, match: WorkspaceSearchMatch) void {
    const f_idx: usize = @intCast(match.file_idx);
    const wfs = self.workspaceFiles();
    if (f_idx >= wfs.len) return;
    const line_num: usize = @intCast(match.line_num);
    const query = self.workspaceSearchQuery();

    self.openFile(f_idx);
    self.find_query.set(query);
    if (!wfs[f_idx].is_pdf_preview and !isPdfCandidatePath(wfs[f_idx].path)) {
        self.buffers[f_idx].jumpToLineAndHighlight(line_num, query);
        const cur_lc = self.buffers[f_idx].cursorLineCol();
        self.doc.cursor_line = @intCast(cur_lc.line);
        self.doc.cursor_col = @intCast(cur_lc.col);
    }
    self.ui_ctx.focused_id = self.activeEditorWidgetId();
}

pub fn replaceInWorkspace(self: *EditorState, query: []const u8, replacement: []const u8) usize {
    if (query.len == 0) return 0;
    var replaced_count: usize = 0;
    const wfs = self.workspaceFiles();
    for (wfs, 0..) |file, f_idx| {
        if (file.isSpecial() or isPdfCandidatePath(file.path) or isImageCandidatePath(file.path)) continue;
        if (!self.loaded_from_disk[f_idx]) continue;
        const buf = &self.buffers[f_idx];
        var pos: usize = 0;
        while (ui.indexOfIgnoreCasePos(buf.slice(), pos, query)) |match_off| {
            buf.selection_anchor = match_off;
            buf.cursor = match_off + query.len;
            if (!buf.insertText(replacement, true)) break;
            replaced_count += 1;
            pos = match_off + replacement.len;
        }
    }
    if (replaced_count > 0) {
        self.cached_search_sig = 0;
        self.ui_ctx.invalidateWindow();
    }
    return replaced_count;
}

test "EditorState.workspaceSearchMatches: early outer-loop stop at 32 matches, O(1) frame memoization, and live buffer edit invalidation" {
    var store = platform.StateStore.init(std.testing.allocator);
    defer store.deinit();
    var snap = platform.SnapshotBuffer.init(std.testing.allocator);
    defer snap.deinit();
    var pctx = platform.PlatformContext{ .width = 1280.0, .height = 800.0 };
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

    // 1. Search for a common symbol ("const") -> must cap at MaxWorkspaceSearchMatches (32) and stop loading remaining files
    state.workspace_search.set("const");
    const matches_1 = state.workspaceSearchMatches();
    try std.testing.expectEqual(MaxWorkspaceSearchMatches, matches_1.len);

    var loaded_count: usize = 0;
    for (0..state.file_count) |i| {
        if (state.loaded_from_disk[i]) loaded_count += 1;
    }
    try std.testing.expect(loaded_count < state.file_count);

    // 2. Subsequent steady-frame calls (e.g. Pass.paint + idle mouse/scroll frames) hit the O(1) cache
    const t0 = platform.profiler.nowNs();
    var total_cached: usize = 0;
    for (0..1000) |_| {
        total_cached += state.workspaceSearchMatches().len;
    }
    const elapsed_ns = platform.profiler.nowNs() - t0;
    try std.testing.expectEqual(@as(usize, 32000), total_cached);
    // 1,000 memoized calls must complete in well under 5ms (< 5 us/call; typically ~20 ns/call)
    try std.testing.expect(elapsed_ns < 5 * std.time.ns_per_ms);

    // 3. Live edit in an open buffer immediately updates workspaceSearchMatches()
    const build_idx = state.findWorkspaceFileIndexByPath("build.zig") orelse 0;
    state.openFile(build_idx);
    var tok_buf: [64]u8 = undefined;
    const dyn_tok = try std.fmt.bufPrint(&tok_buf, "DYN_{s}_{d}", .{ "SEARCH_PROFILER", 987654 });
    state.workspace_search.set(dyn_tok);
    try std.testing.expectEqual(@as(usize, 0), state.workspaceSearchMatches().len);

    _ = state.buffers[build_idx].insertText(dyn_tok, false);
    const after_edit_matches = state.workspaceSearchMatches();
    try std.testing.expectEqual(@as(usize, 1), after_edit_matches.len);
    try std.testing.expectEqual(@as(u16, @intCast(build_idx)), after_edit_matches[0].file_idx);
}
