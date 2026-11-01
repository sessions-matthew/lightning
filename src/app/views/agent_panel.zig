//! Right-side Antigravity (`agy`) Agent Panel (`views/agent_panel.zig`).
//! Styled after the Antigravity Web / Agent Manager interface:
//!   - Minimal header bar with conversation title and subtle icon actions
//!   - Clean rounded user message bubbles (no "YOU" labels or side bars)
//!   - Minimal inline step/tool rows (`› tool_name  detail`)
//!   - Flowing assistant Markdown responses
//!   - Unified rounded bottom prompt box with inline context `@` pill, mode/model selectors,
//!     and circular `↑` send / `■` stop button

const std = @import("std");
const skia = @import("skia");
const platform = @import("platform");
const ui = @import("ui");
const state_mod = @import("../state.zig");
const agy_client = @import("../agy_client.zig");
const EditorState = state_mod.EditorState;

const TranscriptHeightCache = ui.VariableHeightCache(agy_client.MaxChatEntries);

/// Renders an interactive `ask_question` card inside the Agent Panel conversation stream,
/// supporting single-select radio options, multi-select checkboxes, custom write-in input,
/// and Submit / Skip actions over `/HandleCascadeUserInteraction`.
fn drawPendingQuestionCard(
    uic: *ui.Context,
    state: *EditorState,
    session: *agy_client.AgySession,
    entry_idx: usize,
) void {
    const q_slice = session.pending_question.questionSliceMut();
    if (q_slice.len == 0) return;

    var card_scope = uic.scopedId(entry_idx);
    defer card_scope.end();

    const card_w = @max(180.0, uic.availableWidth());
    const pad_x: f32 = 12.0;
    const pad_y: f32 = 10.0;
    const gap_y: f32 = 6.0;
    const inner_w = @max(120.0, card_w - pad_x * 2.0);
    const opt_text_w = @max(80.0, inner_w - 34.0);
    const title_line_h: f32 = 18.0;

    // 1. Pre-measure wrapped lines for every question & option so `uic.box` gets the exact height in both passes
    const WrappedQuestionLayout = struct {
        title_lines: []const []const u8,
        title_h: f32,
        opt_labels: [8][]const u8 = @splat(""),
        opt_recommended: [8]bool = @splat(false),
    };

    var layouts: [6]WrappedQuestionLayout = undefined;
    var total_h: f32 = pad_y * 2.0 + 20.0; // Top/bottom padding + 20pt header row
    var item_count: usize = 1; // Header row is item 0

    for (q_slice, 0..) |*q, q_i| {
        const t_lines = uic.wrapText(uic.font_body, q.question(), inner_w - 4.0);
        const sub_h: f32 = if (q.is_multi_select) 15.0 else 2.0;
        const t_h = @as(f32, @floatFromInt(@max(t_lines.len, 1))) * title_line_h + sub_h;

        layouts[q_i] = .{
            .title_lines = t_lines,
            .title_h = t_h,
        };
        if (q_i > 0) {
            total_h += 6.0; // Divider spacing between multiple questions
            item_count += 1;
        }
        total_h += t_h;
        item_count += 1;

        for (q.optionSlice(), 0..) |*opt, o_i| {
            const parsed = ui.parseRecommendedOptionLabel(opt.text());
            const o_h = ui.measureSelectableOptionCardHeight(uic, parsed.label, parsed.is_recommended, opt_text_w);
            layouts[q_i].opt_labels[o_i] = parsed.label;
            layouts[q_i].opt_recommended[o_i] = parsed.is_recommended;
            total_h += o_h;
            item_count += 1;
        }

        // Write-in ("Other...") row (26pt)
        total_h += 26.0;
        item_count += 1;
    }

    // Footer action row (`Skip` + `Submit`, 26pt)
    total_h += 26.0;
    item_count += 1;
    if (item_count > 1) {
        total_h += @as(f32, @floatFromInt(item_count - 1)) * gap_y;
    }

    var card = uic.box(.{
        .direction = .column,
        .h = .pixels(total_h),
        .padding = ui.Padding.xy(pad_x, pad_y),
        .gap = gap_y,
        .bg_color = skia.Color.rgb(20, 26, 36),
        .border_color = skia.Color.argb(145, 56, 139, 253),
        .border_width = 1.0,
        .corner_radius = 10.0,
    });
    defer card.end();

    // 2. Card Header Row (20pt)
    {
        const hdr_r = uic.nextRect(0, 20.0);
        if (uic.shouldPaint(hdr_r)) {
            uic.paint.setStyle(.fill);
            uic.paint.setColor(skia.Color.rgb(88, 166, 255));
            const hdr_title = if (q_slice.len > 1)
                uic.fmt("?  Agent Questions ({d})", .{q_slice.len})
            else
                "?  Agent Question";
            uic.drawTextCached(uic.font_body, hdr_title, hdr_r.left + 2.0, hdr_r.top + 14.5);
        }
    }

    var submit_requested = false;
    var skip_requested = false;

    // 3. Questions + Selectable Option Rows + Write-In Input
    for (q_slice, 0..) |*q, q_i| {
        var q_scope = uic.scopedId(q_i);
        defer q_scope.end();

        if (q_i > 0) {
            const div_r = uic.nextRect(0, 6.0);
            if (uic.shouldPaint(div_r)) {
                const y = @floor((div_r.top + div_r.bottom) * 0.5);
                uic.paint.setStyle(.fill);
                uic.paint.setColor(skia.Color.rgb(38, 46, 58));
                uic.canvas.drawRect(skia.Rect.xywh(div_r.left, y, div_r.right - div_r.left, 1.0), uic.paint);
            }
        }

        const q_lay = layouts[q_i];
        const title_r = uic.nextRect(0, q_lay.title_h);
        if (uic.shouldPaint(title_r)) {
            uic.paint.setStyle(.fill);
            uic.paint.setColor(skia.Color.rgb(240, 246, 252));
            for (q_lay.title_lines, 0..) |line_str, l_idx| {
                const ly = title_r.top + 14.5 + @as(f32, @floatFromInt(l_idx)) * title_line_h;
                uic.drawTextCached(uic.font_body, line_str, title_r.left + 2.0, ly);
            }
            if (q.is_multi_select) {
                const sub_y = title_r.top + 13.5 + @as(f32, @floatFromInt(q_lay.title_lines.len)) * title_line_h;
                uic.paint.setColor(skia.Color.rgb(125, 133, 144));
                uic.drawTextCached(uic.font_body, "Select all options that apply", title_r.left + 2.0, sub_y);
            }
        }

        for (q.optionSlice(), 0..) |_, o_i| {
            const selected = q.isOptionSelected(o_i) and (!q.use_write_in or q.is_multi_select);
            if (uic.selectableOptionCard(
                uic.fmt("##agy_q_opt_{d}", .{o_i}),
                q_lay.opt_labels[o_i],
                q_lay.opt_recommended[o_i],
                selected,
                q.is_multi_select,
                opt_text_w,
            )) {
                q.selectOption(o_i);
            }
        }

        // Write-In ("Other...") Input Row (26pt)
        {
            var wi_row = uic.row(.{
                .h = .pixels(26.0),
                .gap = 4,
            });
            defer wi_row.end();

            const tog_r = uic.nextRect(22.0, 26.0);
            const tog_wid = uic.resolveIdAndLabel("##agy_q_wi_tog").wid;
            const tog_clicked = uic.trackInteraction(tog_wid, tog_r, tog_r);
            if (uic.hot_id == tog_wid) uic.setCursor(.pointing_hand);

            const tf_wid = uic.resolveIdAndLabel("##agy_q_wi_input").wid;
            if (tog_clicked) {
                q.toggleWriteIn();
                if (q.use_write_in) uic.focused_id = tf_wid;
                uic.invalidateWindow();
            }

            const wi_selected = q.use_write_in or (q.write_in.trim(" \t\r\n").len > 0);
            if (uic.shouldPaint(tog_r)) {
                const ind_cx = tog_r.left + 12.0;
                const ind_cy = tog_r.top + 13.0;
                if (q.is_multi_select) {
                    const box_r = skia.Rect.xywh(ind_cx - 6.0, ind_cy - 6.0, 12.0, 12.0);
                    if (wi_selected) {
                        uic.paint.setStyle(.fill);
                        uic.paint.setColor(uic.theme.accent);
                        uic.canvas.drawRoundRect(box_r, 3.0, 3.0, uic.paint);
                        uic.paint.setColor(skia.Color.white);
                        uic.drawTextCached(uic.font_body, "✓", box_r.left + 1.5, box_r.top + 10.5);
                    } else {
                        uic.paint.setStyle(.stroke);
                        uic.paint.setStrokeWidth(1.2);
                        uic.paint.setColor(skia.Color.rgb(110, 118, 129));
                        uic.canvas.drawRoundRect(box_r, 3.0, 3.0, uic.paint);
                    }
                } else {
                    uic.paint.setStyle(.stroke);
                    uic.paint.setStrokeWidth(1.3);
                    uic.paint.setColor(if (wi_selected) uic.theme.accent_hover else skia.Color.rgb(110, 118, 129));
                    uic.canvas.drawCircle(ind_cx, ind_cy, 5.5, uic.paint);
                    if (wi_selected) {
                        uic.paint.setStyle(.fill);
                        uic.paint.setColor(uic.theme.accent_hover);
                        uic.canvas.drawCircle(ind_cx, ind_cy, 2.8, uic.paint);
                    }
                }
            }

            const tf_w = @max(80.0, inner_w - 28.0);
            const tf_res = uic.textFieldInline(
                "##agy_q_wi_input",
                &q.write_in,
                "Other (type custom answer)...",
                .{
                    .w = .pixels(tf_w),
                    .h = 26.0,
                    .use_body_font = true,
                    .pad_x = 8.0,
                },
            );
            if (tf_res.changed and q.write_in.trim(" \t\r\n").len > 0) {
                q.use_write_in = true;
                if (!q.is_multi_select) q.selected_mask = 0;
                q.skipped = false;
            }
            if (tf_res.submitted and session.pending_question.hasAnySelection()) {
                submit_requested = true;
            }
        }
    }

    // 4. Footer Row (`Skip` and `Submit` buttons)
    {
        var footer = uic.row(.{
            .h = .pixels(26.0),
            .gap = 6,
        });
        defer footer.end();

        const can_submit = session.pending_question.hasAnySelection();
        if (uic.availableWidth() > 144.0) {
            uic.fillSpacer(138.0);
        }

        if (uic.chip("Skip##agy_q_skip", .{
            .w = 56.0,
            .h = 24.0,
            .bordered = true,
        })) {
            skip_requested = true;
        }

        if (uic.chip("Submit##agy_q_submit", .{
            .w = 72.0,
            .h = 24.0,
            .active = can_submit,
            .bordered = true,
        })) {
            if (can_submit) {
                submit_requested = true;
            }
        }
    }

    if (submit_requested) {
        state.submitAgyQuestionResponseFor(session, false);
    } else if (skip_requested) {
        state.submitAgyQuestionResponseFor(session, true);
    }
}

/// Renders a collapsible thinking block dropdown (`▸ Thought for 5s · preview...` / `▾ Thought for 5s` + full Markdown body).
fn drawThinkingDropdown(
    uic: *ui.Context,
    state: *EditorState,
    session: *agy_client.AgySession,
    agent_slot_opt: ?usize,
    salt_prefix: []const u8,
    entry_idx: usize,
    total_entries: usize,
    thinking_text: []const u8,
    duration_label: []const u8,
) void {
    const is_active_streaming = (session.is_running_turn and entry_idx + 1 == total_entries);
    const toggle_slot: ?*u8 = if (entry_idx < session.thinking_toggle.len) &session.thinking_toggle[entry_idx] else null;
    const res = uic.thinkingDisclosureEx(
        salt_prefix,
        entry_idx,
        duration_label,
        thinking_text,
        is_active_streaming,
        .{
            .toggle_slot = toggle_slot,
            .id_salt = uic.fmt("{s}_think_md_{d}", .{ salt_prefix, entry_idx }),
        },
    );
    if (res.right_clicked) {
        state.context_menu_index = entry_idx;
        state.context_menu_agent_slot = if (agent_slot_opt) |s| @intCast(s) else null;
        state.openContextMenu(.agent_message, state.activePaneIndex(), state.activeFileIndex(), false);
    }
    if (res.clicked_link) |link_url| {
        _ = state.openLinkOrFileUrl(link_url);
    }
}

/// Renders a collapsible shell command (`run_command`) dropdown showing the summary & exit status badge
/// when collapsed, and expanding to a pre-measured terminal card with `$ <command>` and stdout/stderr output.
fn drawShellCommandDropdown(
    uic: *ui.Context,
    state: *EditorState,
    session: *agy_client.AgySession,
    agent_slot_opt: ?usize,
    entry_idx: usize,
    cmd_line: []const u8,
    summary: []const u8,
    output: []const u8,
    exit_code: i16,
) void {
    const toggle_slot: ?*u8 = if (entry_idx < session.thinking_toggle.len) &session.thinking_toggle[entry_idx] else null;
    const res = uic.commandExecutionCardEx(
        "agy_sh",
        entry_idx,
        cmd_line,
        output,
        ui.CommandCardStatus.fromExitCode(exit_code),
        .{
            .summary = summary,
            .toggle_slot = toggle_slot,
        },
    );
    if (res.right_clicked) {
        state.context_menu_index = entry_idx;
        state.context_menu_agent_slot = if (agent_slot_opt) |s| @intCast(s) else null;
        state.openContextMenu(.agent_message, state.activePaneIndex(), state.activeFileIndex(), false);
    }
}

/// Clicking a file step row opens that file in the active editor pane.
fn drawInlineStepRow(
    uic: *ui.Context,
    state: *EditorState,
    agent_slot_opt: ?usize,
    entry_idx: usize,
    tool_name: []const u8,
    detail: []const u8,
) void {
    const res = uic.inlineStepRowEx(
        uic.fmt("##agy_step_{d}", .{entry_idx}),
        "›",
        skia.Color.rgb(110, 118, 129),
        tool_name,
        detail,
    );
    if (res.clicked) {
        _ = state.openLinkOrFileUrl(detail);
    } else if (res.right_clicked) {
        state.context_menu_index = entry_idx;
        state.context_menu_agent_slot = if (agent_slot_opt) |s| @intCast(s) else null;
        state.openContextMenu(.agent_message, state.activePaneIndex(), state.activeFileIndex(), false);
    }
}

fn computeEntrySignature(
    session: *const agy_client.AgySession,
    entry: agy_client.ChatEntry,
    entry_idx: usize,
    total_entries: usize,
) u64 {
    const text = session.entryText(entry);
    const aux = session.entryAuxText(entry);
    const detail = session.entryDetailText(entry);
    const is_active_streaming = (session.is_running_turn and entry_idx + 1 == total_entries);
    const expanded: u8 = switch (entry.kind) {
        .thinking => @intFromBool(session.isThinkingExpanded(entry_idx, is_active_streaming)),
        .shell_command => @intFromBool(session.isThinkingExpanded(entry_idx, false)),
        else => 0,
    };

    var h = std.hash.Wyhash.init(0x9E37_79B9_7F4A_7C15);
    h.update(std.mem.asBytes(&entry.kind));
    h.update(std.mem.asBytes(&entry.exit_code));
    h.update(std.mem.asBytes(&expanded));
    const t_len = text.len;
    const a_len = aux.len;
    const d_len = detail.len;
    h.update(std.mem.asBytes(&t_len));
    h.update(std.mem.asBytes(&a_len));
    h.update(std.mem.asBytes(&d_len));
    if (text.len <= 128) {
        h.update(text);
    } else {
        h.update(text[0..64]);
        h.update(text[text.len - 64 ..]);
    }
    if (aux.len > 0) h.update(aux[0..@min(aux.len, 64)]);
    if (detail.len > 0) h.update(detail[detail.len -| 64 ..]);
    const res = h.final();
    return if (res == 0) 1 else res;
}

/// Renders a 2-line past conversation row showing title, workspace badge, step count, and modified date.
fn drawConversationSummaryRow(
    uic: *ui.Context,
    raw_id: []const u8,
    conv: *const @import("../agy_client.zig").ConversationSummary,
    is_active_conv: bool,
) bool {
    const resolved = uic.resolveIdAndLabel(raw_id);
    const r = uic.nextRect(0, 42.0);
    const clicked = uic.trackInteraction(resolved.wid, r, r);
    const hovered = (uic.hot_id == resolved.wid);
    if (hovered) uic.setCursor(.pointing_hand);

    if (uic.shouldPaint(r)) {
        uic.paint.setStyle(.fill);
        uic.paint.setColor(if (is_active_conv)
            skia.Color.argb(46, 56, 139, 253)
        else if (hovered)
            skia.Color.rgb(28, 35, 48)
        else
            skia.Color.rgb(18, 23, 31));
        uic.canvas.drawRoundRect(r, 6.0, 6.0, uic.paint);

        uic.paint.setStyle(.stroke);
        uic.paint.setStrokeWidth(1.0);
        uic.paint.setColor(if (is_active_conv)
            skia.Color.argb(170, 88, 166, 255)
        else if (hovered)
            skia.Color.rgb(54, 63, 78)
        else
            skia.Color.rgb(32, 39, 50));
        uic.canvas.drawRoundRect(r, 6.0, 6.0, uic.paint);

        const save_cnt = uic.canvas.save();
        defer uic.canvas.restoreToCount(save_cnt);
        uic.canvas.clipRect(skia.Rect.ltrb(r.left + 8.0, r.top, r.right - 8.0, r.bottom), .intersect, false);

        const text_x = r.left + 22.0;
        uic.paint.setStyle(.fill);
        if (conv.is_running) {
            uic.paint.setColor(skia.Color.rgb(63, 185, 80));
            uic.canvas.drawCircle(r.left + 13.0, r.top + 14.0, 3.5, uic.paint);
        } else if (is_active_conv) {
            uic.paint.setColor(skia.Color.rgb(88, 166, 255));
            uic.drawTextCached(uic.font_body, "✓", r.left + 9.0, r.top + 18.0);
        } else {
            uic.paint.setColor(if (conv.matches_cwd) skia.Color.rgb(88, 166, 255) else skia.Color.rgb(110, 118, 129));
            uic.drawTextCached(uic.font_body, "›", r.left + 10.5, r.top + 17.5);
        }

        // Primary title line
        uic.paint.setColor(if (is_active_conv or hovered) skia.Color.rgb(240, 246, 252) else skia.Color.rgb(209, 217, 224));
        uic.drawTextCached(uic.font_body, conv.title(), text_x, r.top + 17.5);

        // Secondary metadata line (`workspace · N steps · MM-DD`)
        const ws_name = conv.workspaceBasename();
        const date_str = conv.shortDate();
        const meta_line = if (date_str.len > 0)
            uic.fmt("{s} · {d} steps · {s}", .{ ws_name, conv.step_count, date_str })
        else
            uic.fmt("{s} · {d} steps", .{ ws_name, conv.step_count });

        uic.paint.setColor(if (conv.matches_cwd) skia.Color.rgb(125, 145, 170) else skia.Color.rgb(110, 118, 129));
        uic.drawTextCached(uic.font_mono, meta_line, text_x, r.top + 34.0);
    }

    if (clicked) uic.invalidateWindow();
    return clicked;
}

/// Renders attached image thumbnails for a `.user_prompt` chat entry (clicking any thumbnail opens it in `ImageViewer`).
fn drawUserPromptAttachments(
    uic: *ui.Context,
    state: *EditorState,
    entry_idx: usize,
    media_paths: []const u8,
) void {
    var items: [agy_client.MaxPendingAttachments]ui.AttachmentDisplayItem = undefined;
    var count: usize = 0;
    var it = std.mem.splitScalar(u8, media_paths, '\n');
    while (it.next()) |raw_p| {
        const p = std.mem.trim(u8, raw_p, " \t\r");
        if (p.len > 0 and count < items.len) {
            items[count] = .{ .path = p };
            count += 1;
        }
    }
    if (count == 0) return;

    var scope = uic.scopedId(entry_idx);
    defer scope.end();

    if (uic.attachmentGallery("usr", items[0..count], .{
        .removable = false,
        .align_right = true,
        .row_height = 88.0,
    })) |i| {
        _ = state.openLinkOrFileUrl(items[i].path);
    }
}

/// Renders the horizontal strip of pending pasted image attachments inside the composer box.
fn drawPendingAttachmentsStrip(
    uic: *ui.Context,
    state: *EditorState,
    session: *agy_client.AgySession,
    att_count: usize,
    deferred_remove: *?usize,
) void {
    const atts = session.pendingAttachments();
    const count = @min(@min(att_count, atts.len), agy_client.MaxPendingAttachments);
    if (count == 0) {
        _ = uic.nextRect(0, 46.0);
        return;
    }

    var items: [agy_client.MaxPendingAttachments]ui.AttachmentDisplayItem = undefined;
    for (atts[0..count], 0..) |*att, idx| {
        items[idx] = .{
            .path = att.path(),
            .name = att.name(),
            .width = att.width,
            .height = att.height,
        };
    }

    var clicked_idx: ?usize = null;
    var removed_idx: ?usize = null;
    _ = uic.attachmentGallery("agy_att", items[0..count], .{
        .removable = true,
        .row_height = 46.0,
        .clicked_idx_out = &clicked_idx,
        .removed_idx_out = &removed_idx,
    });
    if (removed_idx) |rm_idx| {
        deferred_remove.* = rm_idx;
    } else if (clicked_idx) |open_idx| {
        _ = state.openLinkOrFileUrl(items[open_idx].path);
    }
}

pub fn build(state: *EditorState, panel_h: f32) void {
    const uic = &state.ui_ctx;
    var scope = uic.scopedState("agy_agent_panel");
    defer scope.end();

    const panel_w = std.math.clamp(state.doc.agent_panel_width, 260.0, 560.0);
    buildSession(state, &state.agy, &state.agy_prompt, null, null, panel_w, panel_h);
}

/// Renders an interactive `*agent-N*` buffer inside a split pane (`pane_idx`), backed by
/// `state.agent_sessions[agent_slot]` and `state.agent_prompts[agent_slot]`, sharing the same
/// underlying `agy` process hub as `state.agy`.
pub fn buildBuffer(state: *EditorState, pane_idx: usize, agent_slot: usize, panel_h: f32) void {
    const uic = &state.ui_ctx;
    const clamped_slot = state.ensureAgentSlot(agent_slot);
    var scope = uic.scopedState("agy_agent_buf");
    defer scope.end();
    var pane_guard = uic.scopedId(pane_idx);
    defer pane_guard.end();
    var slot_guard = uic.scopedId(clamped_slot);
    defer slot_guard.end();

    const panel_w = @max(220.0, uic.availableWidth());
    buildSession(
        state,
        &state.agent_sessions[clamped_slot],
        &state.agent_prompts[clamped_slot],
        pane_idx,
        clamped_slot,
        panel_w,
        panel_h,
    );
}

fn buildSession(
    state: *EditorState,
    session: *agy_client.AgySession,
    prompt: *platform.InlineString(8192),
    pane_idx_opt: ?usize,
    agent_slot_opt: ?usize,
    panel_w: f32,
    panel_h: f32,
) void {
    const uic = &state.ui_ctx;

    const prompt_wid = uic.resolveIdAndLabel("##agy_prompt_input").wid;
    if (pane_idx_opt) |p_idx| {
        if (uic.focused_id == EditorState.editorWidgetIdForPane(p_idx)) {
            uic.focused_id = prompt_wid;
        }
        if (uic.pass == .input and uic.focused_id == prompt_wid) {
            state.doc.split_tree.active_pane = @intCast(p_idx);
        }
    }

    // Ensure `/GetCascadeModelConfigData` and `/GetAllCascadeTrajectories` are fetched from the local socket during input pass
    if (uic.pass == .input) {
        state.syncAgyHubState();
        session.syncWorkspaceRoot(state.workspaceRoot());
        if (!state.anyAgyModelsAttempted()) {
            session.ensureModelsLoaded();
        }
        if (!state.anyAgyConversationsAttempted()) {
            session.ensureConversationsLoaded();
        }
        state.syncAgyHubState();
    }

    const model_picker_open = uic.useState(bool, "model_picker_open", false);
    const effort_flyout_open = uic.useState(bool, "effort_flyout_open", false);
    const effort_flyout_row = uic.useState(usize, "effort_flyout_row", 0);
    const mode_picker_open = uic.useState(bool, "mode_picker_open", false);
    const conv_picker_open = uic.useState(bool, "conv_picker_open", false);
    const conv_filter_workspace = uic.useState(bool, "conv_filter_workspace", true);
    const last_rendered_gen = uic.useState(u32, "last_rendered_gen", 0);
    const last_running_state = uic.useState(bool, "last_running_state", false);

    if (uic.pass == .input and session.open_picker_requested) {
        session.open_picker_requested = false;
        conv_picker_open.* = true;
        model_picker_open.* = false;
        effort_flyout_open.* = false;
        mode_picker_open.* = false;
        uic.invalidateWindow();
    }

    const bg_main = skia.Color.rgb(13, 17, 23);

    var panel = uic.box(.{
        .direction = .column,
        .w = if (pane_idx_opt != null) .fill else .pixels(panel_w),
        .h = .pixels(panel_h),
        .padding = ui.Padding.all(0),
        .gap = 0,
        .bg_color = bg_main,
        .border_edges = if (pane_idx_opt != null) .none else .left_only,
    });
    const panel_rect = panel.rect;
    defer panel.end();

    if (uic.pass == .input) {
        if (last_rendered_gen.* != session.ui_generation or last_running_state.* != session.is_running_turn) {
            last_rendered_gen.* = session.ui_generation;
            last_running_state.* = session.is_running_turn;
            uic.markDirty(panel_rect);
        }
    }

    if (pane_idx_opt) |p_idx| {
        if (uic.pass == .input and uic.mouse_pressed and uic.isHovered(panel_rect)) {
            state.doc.split_tree.active_pane = @intCast(p_idx);
        }
    }

    const salt_prefix = if (pane_idx_opt) |p_idx|
        uic.fmt("agy_buf_{d}_{d}", .{ p_idx, agent_slot_opt orelse 0 })
    else
        "agy";
    const transcript_scroll_id = if (pane_idx_opt) |p_idx|
        uic.fmt("agy_transcript_scroll_{d}_{d}", .{ p_idx, agent_slot_opt orelse 0 })
    else
        "agy_transcript_scroll";
    const picker_scroll_id = if (pane_idx_opt) |p_idx|
        uic.fmt("agy_conv_picker_scroll_{d}_{d}", .{ p_idx, agent_slot_opt orelse 0 })
    else
        "agy_conv_picker_scroll";

    const header_h: f32 = 36.0;
    const input_w = @max(80.0, panel_w - 40.0);
    const prompt_measure_opts = ui.TextAreaOptions{
        .w = .pixels(input_w),
        .min_lines = 1,
        .max_lines = 8,
        .line_h = 19.0,
        .pad_x = 4.0,
        .pad_y = 4.5,
        .borderless = true,
        .use_body_font = true,
        .submit_on_enter = true,
    };
    const composer_input_h = uic.useState(f32, "composer_input_h", 28.0);
    const rendered_att_count = uic.useState(usize, "rendered_att_count", 0);
    if (uic.pass == .input) {
        // Handle Cmd+V / Ctrl+V image paste when the prompt input is focused, the panel is hovered, or this agent buffer pane is active.
        const is_active_agent_target = (uic.focused_id == prompt_wid) or
            uic.isHovered(panel_rect) or
            (pane_idx_opt != null and state.activePaneIndex() == pane_idx_opt.?);
        if (is_active_agent_target and uic.shortcut(.{ .key = .key_v, .shift = false, .alt = false })) {
            if (uic.platform_ctx) |pctx| {
                if (pctx.getClipboardImageAlloc(uic.arena)) |clip_img| {
                    uic.focused_id = prompt_wid;
                    _ = state.attachClipboardImageToAgySession(session, clip_img);
                    uic.key_events = &.{};
                    uic.markDirty(panel_rect);
                } else if (uic.focused_id != prompt_wid and uic.isHovered(panel_rect)) {
                    uic.focused_id = prompt_wid;
                }
            }
        }
        const cur_att_count = session.pendingAttachments().len;
        if (rendered_att_count.* != cur_att_count) {
            rendered_att_count.* = cur_att_count;
            uic.markDirty(panel_rect);
        }
        const max_input_h = @max(28.0, panel_h - header_h - 140.0);
        const measured_h = @min(max_input_h, uic.measureTextAreaHeight(prompt.slice(), input_w, prompt_measure_opts));
        if (@abs(measured_h - composer_input_h.*) > 0.5) {
            if (measured_h > composer_input_h.*) {
                session.scroll_to_bottom_frames = @max(session.scroll_to_bottom_frames, 1);
            }
            composer_input_h.* = measured_h;
            uic.markDirty(panel_rect);
        }
    }
    const att_count = rendered_att_count.*;
    const att_extra_h: f32 = if (att_count > 0) 54.0 else 0.0;
    const input_h = composer_input_h.*;
    const composer_outer_h: f32 = input_h + 76.0 + att_extra_h;
    var family_buf: [16]agy_client.ModelFamily = undefined;
    const families = session.uniqueModelFamilies(&family_buf);
    const family_count = @max(@as(usize, 1), families.len);

    const model_menu_h: f32 = @as(f32, @floatFromInt(family_count)) * 30.0 + 10.0;
    const flyout_w: f32 = 88.0;
    const model_menu_w: f32 = @min(204.0, @max(156.0, panel_w - flyout_w - 22.0));
    const model_menu_rect = skia.Rect.xywh(
        panel_rect.left + 10.0,
        @max(panel_rect.top + 40.0, panel_rect.bottom - composer_outer_h - model_menu_h - 4.0),
        model_menu_w,
        model_menu_h,
    );

    const clamped_row = if (effort_flyout_row.* < family_count) effort_flyout_row.* else 0;
    const flyout_h: f32 = 3.0 * 28.0 + 12.0;
    const raw_flyout_y = model_menu_rect.top + @as(f32, @floatFromInt(clamped_row)) * 30.0;
    const flyout_y = std.math.clamp(
        raw_flyout_y,
        panel_rect.top + 40.0,
        @max(panel_rect.top + 40.0, panel_rect.bottom - composer_outer_h - flyout_h - 4.0),
    );
    const effort_flyout_rect = skia.Rect.xywh(
        model_menu_rect.right + 4.0,
        flyout_y,
        flyout_w,
        flyout_h,
    );

    const mode_menu_h: f32 = 3.0 * 28.0 + 12.0;
    const mode_menu_w: f32 = 176.0;
    const mode_menu_rect = skia.Rect.xywh(
        panel_rect.left + 14.0,
        @max(panel_rect.top + 40.0, panel_rect.bottom - composer_outer_h - mode_menu_h - 4.0),
        mode_menu_w,
        mode_menu_h,
    );

    const conv_menu_h: f32 = std.math.clamp(panel_h - header_h - 24.0, 180.0, 380.0);
    const conv_menu_rect = skia.Rect.xywh(
        panel_rect.left + 8.0,
        panel_rect.top + header_h + 4.0,
        @max(180.0, panel_w - 16.0),
        conv_menu_h,
    );

    if (conv_picker_open.*) {
        uic.setBlockingOverlay(conv_menu_rect);
    } else if (model_picker_open.*) {
        if (effort_flyout_open.*) {
            uic.setBlockingOverlay(skia.Rect.ltrb(
                model_menu_rect.left,
                @min(model_menu_rect.top, effort_flyout_rect.top),
                effort_flyout_rect.right,
                @max(model_menu_rect.bottom, effort_flyout_rect.bottom),
            ));
        } else {
            uic.setBlockingOverlay(model_menu_rect);
        }
    } else if (mode_picker_open.*) {
        uic.setBlockingOverlay(mode_menu_rect);
    }
    defer uic.setBlockingOverlay(null);

    // 1. Minimal Top Bar (36pt): Conversation Selector on left, `History`, `+` (New), `>_` (TUI), `×`/Split on right
    var toggled_conv_picker = false;
    {
        var header = uic.box(.{
            .direction = .row,
            .h = .pixels(header_h),
            .padding = ui.Padding.xy(10, 7),
            .gap = 5,
            .bg_color = bg_main,
            .border_color = skia.Color.rgb(26, 32, 42),
            .border_edges = .bottom_only,
        });
        defer header.end();

        // Derive conversation title from `activeTitle()`, first user prompt, or fallback to buffer name / "Agent"
        var conv_title: []const u8 = session.activeTitle();
        if (conv_title.len == 0) {
            for (session.chatEntries()) |entry| {
                if (entry.kind == .user_prompt) {
                    const raw = std.mem.trim(u8, session.entryText(entry), " \t\r\n");
                    if (raw.len > 0) {
                        const first_nl = std.mem.indexOfScalar(u8, raw, '\n') orelse raw.len;
                        const max_end = @min(first_nl, 24);
                        const safe_end = ui.code_editor_mod.snapToGraphemeBoundary(raw, max_end);
                        const line = raw[0..safe_end];
                        if (line.len > 0) conv_title = line;
                    }
                    break;
                }
            }
        }
        if (conv_title.len == 0) {
            if (pane_idx_opt) |p_idx| {
                if (state.paneActiveFile(p_idx)) |f_idx| {
                    conv_title = state.workspaceFiles()[f_idx].name;
                }
            }
            if (conv_title.len == 0) conv_title = "Agent";
        } else {
            const safe_end = ui.code_editor_mod.snapToGraphemeBoundary(conv_title, @min(conv_title.len, 24));
            conv_title = conv_title[0..safe_end];
        }

        const title_chip_max_w = @max(96.0, panel_w - 154.0);
        if (uic.chip(uic.fmt("▾ {s}##agy_conv_picker_btn", .{conv_title}), .{
            .min_w = 72.0,
            .max_w = title_chip_max_w,
            .h = 22.0,
            .pad_x = 8.0,
            .active = conv_picker_open.*,
            .bordered = conv_picker_open.*,
        })) {
            conv_picker_open.* = !conv_picker_open.*;
            if (conv_picker_open.*) {
                model_picker_open.* = false;
                effort_flyout_open.* = false;
                mode_picker_open.* = false;
                state.syncAgyHubState();
                session.refreshConversations();
                state.syncAgyHubState();
                if (uic.platform_ctx) |pctx| pctx.needs_continuous_redraw = true;
            }
            toggled_conv_picker = true;
            uic.invalidateWindow();
        }

        if (uic.availableWidth() > 134.0) {
            uic.fillSpacer(128.0);
        }

        if (uic.chip("History##agy_hist_btn", .{
            .w = 48.0,
            .h = 22.0,
            .active = conv_picker_open.*,
        })) {
            conv_picker_open.* = !conv_picker_open.*;
            if (conv_picker_open.*) {
                model_picker_open.* = false;
                effort_flyout_open.* = false;
                mode_picker_open.* = false;
                state.syncAgyHubState();
                session.refreshConversations();
                state.syncAgyHubState();
                if (uic.platform_ctx) |pctx| pctx.needs_continuous_redraw = true;
            }
            toggled_conv_picker = true;
            uic.invalidateWindow();
        }

        if (uic.chip("+##agy_reset", .{ .w = 24.0, .h = 22.0 })) {
            conv_picker_open.* = false;
            session.resetConversation();
            uic.invalidateWindow();
        }

        if (uic.chip(">_##agy_tui", .{ .w = 28.0, .h = 22.0, .mono = true })) {
            state.handoffAgySessionToTerminal(session);
        }

        if (agent_slot_opt == null) {
            if (uic.iconButton("##close_agy_panel", .close, .{ .w = 22.0, .h = 22.0 })) {
                state.doc.show_agent_panel = false;
                uic.invalidateWindow();
            }
        } else {
            if (uic.iconButton("##split_agy_buf", .split_horizontal, .{ .w = 22.0, .h = 22.0 })) {
                state.createAgentBuffer(true);
            }
        }
    }

    // 2. Conversation Stream (or minimal empty state with Recent Conversations)
    const body_h = @max(60.0, panel_h - header_h - composer_outer_h);
    const entries = session.chatEntries();

    if (uic.pass == .input) {
        const ss = uic.useState(ui.ScrollState, transcript_scroll_id, .{});
        const min_entries_h = @as(f32, @floatFromInt(entries.len)) * 36.0;
        if (entries.len > 0 and ss.content_height < min_entries_h) {
            ss.content_height = min_entries_h;
        }
        ss.viewport_height = @max(1.0, body_h - 24.0);
        if (session.scroll_to_bottom_frames > ss.scroll_to_bottom_frames) {
            ss.scroll_to_bottom_frames = session.scroll_to_bottom_frames;
        }
        if (entries.len == 0) {
            ss.auto_scroll_pinned = true;
            ss.scroll_to_bottom_frames = 0;
            session.scroll_to_bottom_frames = 0;
        } else {
            const scrolled_up = uic.isHovered(panel_rect) and !uic.mouse_shift and @abs(uic.scroll_dy) > @abs(uic.scroll_dx);
            if (ss.updateTailPin(
                scrolled_up,
                if (scrolled_up) uic.scroll_dy else 0.0,
                session.is_running_turn,
                36.0,
            )) {
                uic.markDirty(panel_rect);
            }
            session.scroll_to_bottom_frames = ss.scroll_to_bottom_frames;
        }
    }

    {
        var scroll = uic.scrollPanel(transcript_scroll_id, .{
            .h = .pixels(body_h),
            .padding = ui.Padding.xy(14, 12),
            .gap = 10,
            .bg_color = bg_main,
        });
        defer scroll.end();

        if (entries.len == 0) {
            if (session.loading_conversation) {
                const top_pad = @max(24.0, (body_h - 80.0) * 0.4);
                _ = uic.nextRect(0, top_pad);
                const load_r = uic.nextRect(0, 36.0);
                uic.emptyStateHero(load_r, "Loading conversation...", "", null);
            } else {
                const all_convs = session.availableConversations();
                const ws_convs_count = session.workspaceConversationCount();
                const top_pad = if (ws_convs_count > 0) 8.0 else @max(24.0, (body_h - 160.0) * 0.38);
                _ = uic.nextRect(0, top_pad);

                const hero_r = uic.nextRect(0, 44.0);
                uic.emptyStateHero(
                    hero_r,
                    "What can I help you build?",
                    "Ask a question or reference files with @",
                    null,
                );

                // Subtle suggestion pills
                {
                    var pill_col = uic.box(.{
                        .direction = .column,
                        .h = .pixels(104.0),
                        .padding = ui.Padding.xy(12, 4),
                        .gap = 6,
                    });
                    defer pill_col.end();

                    const pill_w = @max(140.0, panel_w - 52.0);
                    if (uic.chip("Explain active file##starter_explain", .{
                        .w = pill_w,
                        .h = 28.0,
                        .bordered = true,
                    })) {
                        prompt.set("Explain how this code works concisely.");
                        state.sendAgyPromptFromSession(session, prompt, agent_slot_opt);
                    }

                    if (uic.chip("Fix diagnostics in buffer##starter_fix", .{
                        .w = pill_w,
                        .h = 28.0,
                        .bordered = true,
                    })) {
                        state.sendAgyDiagnosticsPrompt();
                    }

                    if (uic.chip("Review code & suggest improvements##starter_review", .{
                        .w = pill_w,
                        .h = 28.0,
                        .bordered = true,
                    })) {
                        prompt.set("Review this code for edge cases, bugs, or performance improvements.");
                        state.sendAgyPromptFromSession(session, prompt, agent_slot_opt);
                    }
                }

                // Recent Conversations matching the current workspace directly in empty state
                if (ws_convs_count > 0) {
                    _ = uic.nextRect(0, 4.0);
                    {
                        var sec_hdr = uic.row(.{
                            .h = .pixels(22.0),
                            .gap = 6,
                        });
                        defer sec_hdr.end();

                        uic.label("Recent in Workspace", skia.Color.rgb(139, 148, 158));

                        if (uic.availableWidth() > 54.0) {
                            uic.fillSpacer(50.0);
                        }

                        if (uic.chip("All ▸##empty_view_all_convs", .{
                            .w = 46.0,
                            .h = 20.0,
                        })) {
                            conv_picker_open.* = true;
                            toggled_conv_picker = true;
                            state.syncAgyHubState();
                            session.refreshConversations();
                            state.syncAgyHubState();
                            if (uic.platform_ctx) |pctx| pctx.needs_continuous_redraw = true;
                            uic.invalidateWindow();
                        }
                    }

                    const preview_limit = @min(ws_convs_count, 6);
                    var shown: usize = 0;
                    const active_cid = session.conversationId();

                    for (all_convs, 0..) |*conv, c_idx| {
                        if (shown >= preview_limit) break;
                        if (!conv.matches_cwd) continue;
                        var c_scope = uic.scopedId(c_idx);
                        defer c_scope.end();

                        const is_cur = (active_cid.len > 0 and std.mem.eql(u8, conv.id(), active_cid));
                        if (drawConversationSummaryRow(uic, "##empty_recent_conv", conv, is_cur)) {
                            state.loadAgyConversationInto(session, conv.id(), agent_slot_opt);
                            if (pane_idx_opt != null) uic.focused_id = prompt_wid;
                        }
                        shown += 1;
                    }
                }
            }
        } else {
            const entry_cache = uic.useState(TranscriptHeightCache, "entry_height_cache", .{});
            if (uic.pass == .input) {
                entry_cache.syncWidthAndResetCullMask(uic.availableWidth());
            }
            const vp_top = scroll.rect.top - 240.0;
            const vp_bot = scroll.rect.bottom + 240.0;

            var opened_entry_menu = false;
            var has_question_card = false;
            for (entries, 0..) |entry, entry_idx| {
                const item_top_y = uic.nextCursorY();
                const sig = if (uic.pass == .input and entry_idx < agy_client.MaxChatEntries and entry.kind != .question_prompt)
                    computeEntrySignature(session, entry, entry_idx, entries.len)
                else
                    0;

                if (entry_cache.cullOrBeginItem(uic, entry_idx, sig, item_top_y, vp_top, vp_bot)) |culled_r| {
                    if (uic.rightClicked(culled_r)) {
                        state.context_menu_index = entry_idx;
                        state.context_menu_agent_slot = if (agent_slot_opt) |s| @intCast(s) else null;
                        state.openContextMenu(.agent_message, state.activePaneIndex(), state.activeFileIndex(), false);
                        opened_entry_menu = true;
                    }
                    continue;
                }

                const text = session.entryText(entry);
                const aux = session.entryAuxText(entry);
                switch (entry.kind) {
                    .user_prompt => {
                        if (aux.len > 0) {
                            drawUserPromptAttachments(uic, state, entry_idx, aux);
                        }
                        if (std.mem.trim(u8, text, " \t\r\n").len > 0 or aux.len == 0) {
                            const md_res = uic.markdownBubble(text, .{
                                .id_salt = uic.fmt("{s}_usr_{d}", .{ salt_prefix, entry_idx }),
                            });
                            if (md_res.clicked_link) |link_url| {
                                _ = state.openLinkOrFileUrl(link_url);
                            }
                        }
                    },
                    .thinking => drawThinkingDropdown(uic, state, session, agent_slot_opt, salt_prefix, entry_idx, entries.len, text, aux),
                    .tool_call => drawInlineStepRow(uic, state, agent_slot_opt, entry_idx, text, aux),
                    .shell_command => drawShellCommandDropdown(
                        uic,
                        state,
                        session,
                        agent_slot_opt,
                        entry_idx,
                        text,
                        aux,
                        session.entryDetailText(entry),
                        entry.exit_code,
                    ),
                    .assistant_markdown => {
                        const trimmed = std.mem.trim(u8, text, " \t\r\n");
                        if (trimmed.len > 0) {
                            const md_res = uic.markdownEx(trimmed, .{
                                .id_salt = uic.fmt("{s}_md_{d}", .{ salt_prefix, entry_idx }),
                            });
                            if (md_res.clicked_link) |link_url| {
                                _ = state.openLinkOrFileUrl(link_url);
                            }
                        }
                    },
                    .error_banner => uic.banner(text, .err),
                    .question_prompt => {
                        has_question_card = true;
                        drawPendingQuestionCard(uic, state, session, entry_idx);
                    },
                }
                const bot_y = uic.stack[uic.stack_len - 1].cursor_y;
                if (uic.pass == .input and entry_idx < agy_client.MaxChatEntries) {
                    const measured_h = bot_y - item_top_y;
                    entry_cache.recordHeight(entry_idx, sig, measured_h);
                }
                const entry_r = skia.Rect.ltrb(scroll.rect.left, item_top_y, scroll.rect.right, bot_y);
                if (uic.rightClicked(entry_r)) {
                    state.context_menu_index = entry_idx;
                    state.context_menu_agent_slot = if (agent_slot_opt) |s| @intCast(s) else null;
                    state.openContextMenu(.agent_message, state.activePaneIndex(), state.activeFileIndex(), false);
                    opened_entry_menu = true;
                }
            }
            if (!opened_entry_menu and uic.rightClicked(scroll.rect)) {
                state.context_menu_index = if (entries.len > 0) entries.len - 1 else 0;
                state.context_menu_agent_slot = if (agent_slot_opt) |s| @intCast(s) else null;
                state.openContextMenu(.agent_message, state.activePaneIndex(), state.activeFileIndex(), false);
            }

            if (session.is_running_turn and !has_question_card) {
                const active_tool = session.activeToolText();
                const status_r = uic.nextRect(0, 20.0);
                if (uic.shouldPaint(status_r)) {
                    uic.paint.setStyle(.fill);
                    uic.paint.setColor(skia.Color.rgb(139, 148, 158));
                    const msg = if (active_tool.len > 0)
                        uic.fmt("› {s}...", .{active_tool[0..@min(active_tool.len, 40)]})
                    else
                        "› Thinking...";
                    uic.drawTextCached(uic.font_body, msg, status_r.left + 4.0, status_r.top + 14.5);
                }
            }
        }
    }

    if (uic.pass == .input) {
        const ss_after = uic.useState(ui.ScrollState, transcript_scroll_id, .{});
        if (entries.len > 0 and ss_after.finishTailPinPass(session.is_running_turn)) {
            session.scroll_to_bottom_frames = @max(session.scroll_to_bottom_frames, ss_after.scroll_to_bottom_frames);
            if (uic.platform_ctx) |pctx| pctx.needs_continuous_redraw = true;
        }
    }

    // 3. Bottom Antigravity Web-Style Unified Prompt Box (104pt)
    {
        var comp_wrap = uic.box(.{
            .direction = .column,
            .h = .pixels(composer_outer_h),
            .padding = ui.Padding.xy(10, 8),
            .gap = 0,
            .bg_color = bg_main,
        });
        defer comp_wrap.end();

        // Rounded prompt box surface with declarative focus border
        const input_focused = (uic.focused_id == prompt_wid);
        var card = uic.box(.{
            .direction = .column,
            .h = .pixels(composer_outer_h - 16.0),
            .padding = ui.Padding.xy(10, 8),
            .gap = 8,
            .bg_color = skia.Color.rgb(22, 27, 34),
            .border_color = if (input_focused) skia.Color.rgb(72, 82, 96) else skia.Color.rgb(48, 54, 61),
            .border_width = 1.0,
            .corner_radius = 10.0,
        });
        defer card.end();

        // Pending image attachments strip (when attachments are queued)
        var deferred_remove_att: ?usize = null;
        if (att_count > 0) {
            drawPendingAttachmentsStrip(uic, state, session, att_count, &deferred_remove_att);
        }

        // Top inside box: seamless borderless multi-line word-wrapping text input
        const can_send = !prompt.isEmpty() or session.pendingAttachments().len > 0;
        var pasted_img_from_tf: ?platform.ClipboardImage = null;
        {
            var input_row = uic.row(.{
                .h = .pixels(input_h),
                .gap = 0,
            });
            defer input_row.end();

            const prompt_placeholder = if (session.pending_question.active)
                "Reply to agent's question, or use card above..."
            else if (att_count > 0)
                "Add a message for your attached image(s), or press Enter to send..."
            else
                "Ask anything, @ to mention, Cmd+V to paste image...";
            const tf = uic.textAreaInlineEx(
                "##agy_prompt_input",
                prompt,
                prompt_placeholder,
                .{
                    .w = .pixels(input_w),
                    .h = input_h,
                    .line_h = 19.0,
                    .pad_x = 4.0,
                    .pad_y = 4.5,
                    .borderless = true,
                    .use_body_font = true,
                    .submit_on_enter = true,
                    .allow_image_paste = true,
                },
            );
            pasted_img_from_tf = tf.pasted_image;
            if (tf.submitted and can_send) {
                state.sendAgyPromptFromSession(session, prompt, agent_slot_opt);
            }
            if (uic.pass == .input and (tf.changed or tf.submitted)) {
                const next_h = uic.measureTextAreaHeight(prompt.slice(), input_w, prompt_measure_opts);
                if (@abs(next_h - input_h) > 0.5) {
                    if (uic.platform_ctx) |pctx| pctx.needs_continuous_redraw = true;
                    uic.markDirty(panel_rect);
                    uic.invalidateWindow();
                }
            }
        }

        // Bottom inside box: `@ file` context chip, Mode dropdown chip, Model dropdown chip, Spacer, Circular `↑` button
        {
            var bar = uic.row(.{
                .h = .pixels(24.0),
                .gap = 4,
            });
            defer bar.end();

            var ctx_label: []const u8 = "@ Context";
            if (state.doc.agy_include_context) {
                if (state.contextFileIndexForAgent()) |f_idx| {
                    const wf = state.workspaceFiles()[f_idx];
                    if (!wf.isSpecial()) {
                        const buf = &state.buffers[f_idx];
                        if (buf.hasSelection()) {
                            const sel = buf.selectionRange();
                            const s_lc = buf.offsetToLineCol(sel.start);
                            const e_lc = buf.offsetToLineCol(sel.end);
                            ctx_label = uic.fmt("@{s}:{d}-{d}", .{ wf.name, s_lc.line + 1, e_lc.line + 1 });
                        } else {
                            ctx_label = uic.fmt("@{s}", .{wf.name});
                        }
                    }
                }
            }

            if (uic.chip(uic.fmt("{s}##agy_ctx_toggle", .{ctx_label}), .{
                .min_w = 52.0,
                .max_w = 108.0,
                .h = 22.0,
                .active = state.doc.agy_include_context,
            })) {
                state.doc.agy_include_context = !state.doc.agy_include_context;
            }

            var toggled_picker = false;

            const mode_str = switch (session.mode) {
                .plan => "Planning",
                .accept_edits => "Fast",
                .auto => "Auto",
            };
            const mode_lbl = uic.fmt("▾ {s}##agy_mode", .{mode_str});
            if (uic.chip(mode_lbl, .{
                .h = 22.0,
                .pad_x = 9.0,
                .active = mode_picker_open.*,
            })) {
                mode_picker_open.* = !mode_picker_open.*;
                if (mode_picker_open.*) {
                    model_picker_open.* = false;
                    conv_picker_open.* = false;
                }
                toggled_picker = true;
            }

            const active_base = session.activeBaseModelLabel();
            const effort_short = switch (session.effort) {
                .low => "Low",
                .medium => "Med",
                else => "High",
            };
            const model_chip_display = uic.fmt("{s} · {s}", .{
                active_base[0..@min(active_base.len, 15)],
                effort_short,
            });
            const model_lbl = uic.fmt("▾ {s}##agy_model_picker_btn", .{model_chip_display});
            if (uic.chip(model_lbl, .{
                .max_w = 142.0,
                .h = 22.0,
                .pad_x = 9.0,
                .active = model_picker_open.*,
            })) {
                model_picker_open.* = !model_picker_open.*;
                if (model_picker_open.*) {
                    mode_picker_open.* = false;
                    conv_picker_open.* = false;
                    effort_flyout_open.* = false;
                    state.syncAgyHubState();
                    session.ensureModelsLoaded();
                    state.syncAgyHubState();
                } else {
                    effort_flyout_open.* = false;
                }
                toggled_picker = true;
            }

            if (uic.availableWidth() > 30.0) {
                uic.fillSpacer(28.0);
            }

            if (uic.circularActionButton(
                "##agy_send_or_stop",
                session.is_running_turn,
                can_send,
            )) {
                model_picker_open.* = false;
                effort_flyout_open.* = false;
                mode_picker_open.* = false;
                conv_picker_open.* = false;
                if (session.is_running_turn) {
                    session.interruptTurn();
                    uic.invalidateWindow();
                } else if (can_send) {
                    state.sendAgyPromptFromSession(session, prompt, agent_slot_opt);
                }
            }

            // Dismiss open picker when clicking outside the menu & side flyout
            if (!toggled_picker and !toggled_conv_picker) {
                if (conv_picker_open.* and uic.clickedOutside(&.{conv_menu_rect})) {
                    conv_picker_open.* = false;
                    uic.invalidateWindow();
                }
                if (model_picker_open.*) {
                    const active_rects: []const skia.c.sk_rect_t = if (effort_flyout_open.*)
                        &.{ model_menu_rect, effort_flyout_rect }
                    else
                        &.{model_menu_rect};
                    if (uic.clickedOutside(active_rects)) {
                        model_picker_open.* = false;
                        effort_flyout_open.* = false;
                        uic.invalidateWindow();
                    }
                }
                if (mode_picker_open.* and uic.clickedOutside(&.{mode_menu_rect})) {
                    mode_picker_open.* = false;
                    uic.invalidateWindow();
                }
            }
        }

        if (uic.pass == .input) {
            if (pasted_img_from_tf) |clip_img| {
                _ = state.attachClipboardImageToAgySession(session, clip_img);
                if (uic.platform_ctx) |pctx| pctx.needs_continuous_redraw = true;
                uic.markDirty(panel_rect);
                uic.invalidateWindow();
            }
            if (deferred_remove_att) |rm_idx| {
                session.removePendingAttachment(rm_idx);
                if (uic.platform_ctx) |pctx| pctx.needs_continuous_redraw = true;
                uic.markDirty(panel_rect);
                uic.invalidateWindow();
            }
        }
    }

    // 4. Floating Conversation History Picker Overlay
    if (conv_picker_open.*) {
        const all_convs = session.availableConversations();
        const ws_count = session.workspaceConversationCount();
        const active_cid = session.conversationId();

        var menu = uic.overlayBox(conv_menu_rect, .{
            .direction = .column,
            .padding = ui.Padding.xy(8, 8),
            .gap = 6,
            .bg_color = skia.Color.rgb(18, 23, 31),
            .border_color = skia.Color.rgb(54, 63, 78),
            .border_width = 1.0,
            .corner_radius = 10.0,
        });
        defer menu.end();

        // Top filter & action bar inside the conversation overlay (24pt)
        {
            var top_bar = uic.row(.{
                .h = .pixels(24.0),
                .gap = 5,
            });
            defer top_bar.end();

            const ws_lbl = uic.fmt("Workspace ({d})##conv_flt_ws", .{ws_count});
            if (uic.chip(ws_lbl, .{
                .min_w = 88.0,
                .h = 22.0,
                .active = conv_filter_workspace.*,
                .bordered = true,
            })) {
                conv_filter_workspace.* = true;
                uic.invalidateWindow();
            }

            const all_lbl = uic.fmt("All ({d})##conv_flt_all", .{all_convs.len});
            if (uic.chip(all_lbl, .{
                .min_w = 54.0,
                .h = 22.0,
                .active = !conv_filter_workspace.*,
                .bordered = true,
            })) {
                conv_filter_workspace.* = false;
                uic.invalidateWindow();
            }

            if (uic.availableWidth() > 86.0) {
                uic.fillSpacer(80.0);
            }

            if (uic.chip("+ New##conv_picker_new", .{
                .w = 48.0,
                .h = 22.0,
                .bordered = true,
            })) {
                conv_picker_open.* = false;
                session.resetConversation();
                uic.invalidateWindow();
            }

            if (uic.chip("↺##conv_picker_refresh", .{
                .w = 24.0,
                .h = 22.0,
            })) {
                state.syncAgyHubState();
                session.refreshConversations();
                state.syncAgyHubState();
                if (uic.platform_ctx) |pctx| pctx.needs_continuous_redraw = true;
                uic.invalidateWindow();
            }
        }

        const list_h = @max(80.0, conv_menu_h - 46.0);
        var list_scroll = uic.scrollPanel(picker_scroll_id, .{
            .h = .pixels(list_h),
            .padding = ui.Padding.xy(2, 2),
            .gap = 5,
            .bg_color = skia.Color.transparent,
        });
        defer list_scroll.end();

        var matched_count: usize = 0;
        for (all_convs, 0..) |*conv, c_idx| {
            if (conv_filter_workspace.* and !conv.matches_cwd) continue;
            matched_count += 1;

            var c_scope = uic.scopedId(c_idx);
            defer c_scope.end();

            const is_cur = (active_cid.len > 0 and std.mem.eql(u8, conv.id(), active_cid));
            if (drawConversationSummaryRow(uic, "##picker_conv_row", conv, is_cur)) {
                conv_picker_open.* = false;
                state.loadAgyConversationInto(session, conv.id(), agent_slot_opt);
                if (pane_idx_opt != null) uic.focused_id = prompt_wid;
            }
        }

        if (matched_count == 0) {
            const msg = if (!session.conversations_fetched)
                "Fetching conversations from Antigravity Hub..."
            else if (conv_filter_workspace.*)
                "No conversations found for this workspace."
            else
                "No past conversations found.";
            const empty_r = uic.nextRect(0, 60.0);
            uic.emptyStateHero(empty_r, msg, "", null);
        }
    }

    // 4. Floating Model Picker Popup Menu + Side Effort Flyout (`Low` / `Medium` / `High`)
    if (model_picker_open.*) {
        const active_base = session.activeBaseModelLabel();
        const cur_eff_txt = switch (session.effort) {
            .low => "Low",
            .medium => "Med",
            else => "High",
        };

        {
            var menu = uic.overlayBox(model_menu_rect, .{
                .direction = .column,
                .padding = ui.Padding.xy(5, 5),
                .gap = 2,
                .bg_color = skia.Color.rgb(22, 27, 34),
                .border_color = skia.Color.rgb(48, 54, 61),
                .border_width = 1.0,
                .corner_radius = 8.0,
            });
            defer menu.end();

            for (families, 0..) |fam, idx| {
                var id_guard = uic.scopedId(idx);
                defer id_guard.end();

                const is_sel = std.mem.eql(u8, fam.base_label, active_base);
                const is_flyout_row = (effort_flyout_open.* and effort_flyout_row.* == idx);
                const row_res = uic.menuItemWithSubtrigger(
                    uic.fmt("{s}##model_fam", .{fam.base_label}),
                    fam.base_label,
                    is_sel,
                    if (is_sel) cur_eff_txt else "High",
                    is_flyout_row,
                );

                if (row_res.subtrigger_hovered and uic.pass == .input) {
                    if (!effort_flyout_open.* or effort_flyout_row.* != idx) {
                        effort_flyout_open.* = true;
                        effort_flyout_row.* = idx;
                        uic.invalidateWindow();
                    }
                }
                if (row_res.subtrigger_clicked) {
                    if (effort_flyout_open.* and effort_flyout_row.* == idx) {
                        effort_flyout_open.* = false;
                    } else {
                        effort_flyout_open.* = true;
                        effort_flyout_row.* = idx;
                    }
                    uic.invalidateWindow();
                } else if (row_res.row_clicked) {
                    session.selectModelFamilyAndEffort(fam.base_label, session.effort);
                    model_picker_open.* = false;
                    effort_flyout_open.* = false;
                    state.setStatusNotice(uic.fmt("Model: {s}", .{session.activeModelLabel()}));
                    uic.invalidateWindow();
                }
            }
        }

        // Side Flyout Dropdown for Effort (`Low` / `Medium` / `High`)
        if (effort_flyout_open.* and clamped_row < families.len) {
            const target_family = families[clamped_row].base_label;
            const is_target_active = std.mem.eql(u8, target_family, active_base);

            var flyout = uic.overlayBox(effort_flyout_rect, .{
                .direction = .column,
                .padding = ui.Padding.xy(5, 5),
                .gap = 2,
                .bg_color = skia.Color.rgb(22, 27, 34),
                .border_color = skia.Color.rgb(58, 66, 76),
                .border_width = 1.0,
                .corner_radius = 8.0,
            });
            defer flyout.end();

            if (uic.menuItem("High##eff_high", is_target_active and session.effort == .high)) {
                session.selectModelFamilyAndEffort(target_family, .high);
                effort_flyout_open.* = false;
                model_picker_open.* = false;
                state.setStatusNotice(uic.fmt("{s} · High", .{target_family}));
                uic.invalidateWindow();
            }
            if (uic.menuItem("Medium##eff_med", is_target_active and session.effort == .medium)) {
                session.selectModelFamilyAndEffort(target_family, .medium);
                effort_flyout_open.* = false;
                model_picker_open.* = false;
                state.setStatusNotice(uic.fmt("{s} · Medium", .{target_family}));
                uic.invalidateWindow();
            }
            if (uic.menuItem("Low##eff_low", is_target_active and session.effort == .low)) {
                session.selectModelFamilyAndEffort(target_family, .low);
                effort_flyout_open.* = false;
                model_picker_open.* = false;
                state.setStatusNotice(uic.fmt("{s} · Low", .{target_family}));
                uic.invalidateWindow();
            }
        }
    }

    // 5. Floating Mode Picker Popup Menu (`Planning` / `Fast` / `Auto`)
    if (mode_picker_open.*) {
        var menu = uic.overlayBox(mode_menu_rect, .{
            .direction = .column,
            .padding = ui.Padding.xy(6, 6),
            .gap = 2,
            .bg_color = skia.Color.rgb(22, 27, 34),
            .border_color = skia.Color.rgb(48, 54, 61),
            .border_width = 1.0,
            .corner_radius = 8.0,
        });
        defer menu.end();

        if (uic.menuItem("Planning##mode_plan", session.mode == .plan)) {
            session.mode = .plan;
            mode_picker_open.* = false;
            uic.invalidateWindow();
        }
        if (uic.menuItem("Fast (Accept Edits)##mode_fast", session.mode == .accept_edits)) {
            session.mode = .accept_edits;
            mode_picker_open.* = false;
            uic.invalidateWindow();
        }
        if (uic.menuItem("Auto##mode_auto", session.mode == .auto)) {
            session.mode = .auto;
            mode_picker_open.* = false;
            uic.invalidateWindow();
        }
    }

    if (uic.pass == .input) {
        if (session.sock_fd >= 0 or
            (session.is_running_turn and !session.pending_question.active) or
            session.active_poll_frames > 0 or
            session.scroll_to_bottom_frames > 0)
        {
            if (uic.platform_ctx) |pctx| pctx.needs_continuous_redraw = true;
        }
    }
}
