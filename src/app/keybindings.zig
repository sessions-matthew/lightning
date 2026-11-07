//! VS Code-Compatible Keybinding System (`keybindings.zig`).
//!
//! Provides:
//!   - Parsing and formatting of VS Code key combinations and chord sequences (`KeyChord`).
//!   - VS Code command string identifier mapping (`workbench.action.tasks.build`, `workbench.action.showCommands`, etc.).
//!   - Evaluation of `when` context clauses (`!terminalFocus`, `editorTextFocus`, `!findWidgetVisible`).
//!   - User keybinding customization via JSON (`~/.lightning/keybindings.json` and `.vscode/keybindings.json`).
//!   - Stateful two-step chord dispatching (`Cmd+K Cmd+S`) with user-facing status strip notices.

const std = @import("std");
const ui = @import("ui");
const platform = @import("platform");
const state_mod = @import("state.zig");
const commands_mod = @import("commands.zig");
const tasks_mod = @import("tasks.zig");

const EditorState = state_mod.EditorState;
const CommandId = commands_mod.CommandId;
const Shortcut = ui.Shortcut;
const KeyChord = ui.KeyChord;
const KeyCode = platform.KeyCode;
const KeyEvent = platform.KeyEvent;

pub const WhenClause = enum {
    always,
    editor_text_focus,
    not_terminal_focus,
    terminal_focus,
    not_find_bar_visible,
    find_bar_visible,

    pub fn parse(str: []const u8) WhenClause {
        const s = std.mem.trim(u8, str, " \t\r\n");
        if (s.len == 0) return .always;
        if (std.ascii.eqlIgnoreCase(s, "editortextfocus")) return .editor_text_focus;
        if (std.ascii.eqlIgnoreCase(s, "!terminalfocus") or std.ascii.eqlIgnoreCase(s, "!terminalfocused")) return .not_terminal_focus;
        if (std.ascii.eqlIgnoreCase(s, "terminalfocus") or std.ascii.eqlIgnoreCase(s, "terminalfocused")) return .terminal_focus;
        if (std.ascii.eqlIgnoreCase(s, "!findwidgetvisible") or std.ascii.eqlIgnoreCase(s, "!findbarvisible")) return .not_find_bar_visible;
        if (std.ascii.eqlIgnoreCase(s, "findwidgetvisible") or std.ascii.eqlIgnoreCase(s, "findbarvisible")) return .find_bar_visible;
        return .always;
    }

    pub fn label(self: WhenClause) []const u8 {
        return switch (self) {
            .always => "",
            .editor_text_focus => "editorTextFocus",
            .not_terminal_focus => "!terminalFocus",
            .terminal_focus => "terminalFocus",
            .not_find_bar_visible => "!findWidgetVisible",
            .find_bar_visible => "findWidgetVisible",
        };
    }

    pub fn matches(self: WhenClause, state: *const EditorState) bool {
        return switch (self) {
            .always => true,
            .editor_text_focus => !state.isTerminalFocused(),
            .not_terminal_focus => !state.isTerminalFocused(),
            .terminal_focus => state.isTerminalFocused(),
            .not_find_bar_visible => !state.doc.show_find_bar,
            .find_bar_visible => state.doc.show_find_bar,
        };
    }
};

pub const Keybinding = struct {
    command_id: CommandId,
    chord: KeyChord,
    when: WhenClause = .always,
    is_custom: bool = false,
    is_unbound: bool = false,

    pub fn formatDisplay(self: Keybinding, buf: []u8) []const u8 {
        return self.chord.format(buf);
    }
};

/// Maps `id` to the canonical VS Code dotted command string.
pub fn commandToVSCodeId(id: CommandId) []const u8 {
    return switch (id) {
        .run_build_task => "workbench.action.tasks.build",
        .run_task => "workbench.action.tasks.runTask",
        .command_palette => "workbench.action.showCommands",
        .quick_open => "workbench.action.quickOpen",
        .save_file => "workbench.action.files.save",
        .save_file_as => "workbench.action.files.saveAs",
        .save_all_files => "workbench.action.files.saveAll",
        .revert_file => "workbench.action.files.revert",
        .close_active_tab => "workbench.action.closeActiveEditor",
        .close_active_split => "workbench.action.closeActiveSplit",
        .split_right => "workbench.action.splitEditorRight",
        .split_down => "workbench.action.splitEditorDown",
        .move_tab_next_split => "workbench.action.moveEditorToNextGroup",
        .focus_group_1 => "workbench.action.focusFirstEditorGroup",
        .focus_group_2 => "workbench.action.focusSecondEditorGroup",
        .toggle_sidebar => "workbench.action.toggleSidebarVisibility",
        .toggle_terminal_panel => "workbench.action.terminal.toggleTerminal",
        .new_terminal_buffer => "workbench.action.terminal.new",
        .new_terminal_side => "workbench.action.terminal.newSide",
        .toggle_output_panel => "workbench.action.output.toggleOutput",
        .toggle_waveform_panel => "workbench.action.toggleWaveform",
        .toggle_minimap => "workbench.action.toggleMinimap",
        .toggle_word_wrap => "workbench.action.toggleWordWrap",
        .toggle_dirty_overlay => "workbench.action.toggleDirtyOverlay",
        .find_in_file => "actions.find",
        .find_in_workspace => "workbench.action.findInFiles",
        .goto_symbol_mode => "workbench.action.gotoSymbol",
        .goto_line_mode => "workbench.action.gotoLine",
        .open_scratch_buffer => "workbench.action.openScratchBuffer",
        .open_workspace_folder => "workbench.action.openWorkspace",
        .refresh_workspace => "workbench.action.reloadWindow",
        .open_keybindings => "workbench.action.openGlobalKeybindings",
        .open_keybindings_json => "workbench.action.openGlobalKeybindingsFile",
        .open_user_plugins_folder => "workbench.action.plugins.openFolder",
        .reload_all_plugins => "workbench.action.plugins.reloadAll",
        .supercomplete_toggle => "supercomplete.toggle",
        .supercomplete_trigger => "supercomplete.trigger",
        .supercomplete_restart => "supercomplete.restart",
        .agy_toggle_panel => "agent.togglePanel",
        .agy_send_selection_or_file => "agent.sendSelection",
        .agy_fix_diagnostics => "agent.fixDiagnostics",
        .agy_interrupt_turn => "agent.interrupt",
        .agy_reset_conversation => "agent.reset",
        .agy_load_conversation => "agent.loadConversation",
        .agy_cycle_mode => "agent.cycleMode",
        .agy_cycle_effort => "agent.cycleEffort",
        .agy_handoff_tui => "agent.handoffTerminal",
        .new_agent_buffer => "agent.newBuffer",
        .new_agent_side => "agent.newSide",
        .open_markdown_preview => "markdown.showPreview",
        .open_markdown_preview_side => "markdown.showPreviewToSide",
        .create_bound_markdown_preview => "markdown.showBoundPreview",
        .create_bound_markdown_preview_side => "markdown.showBoundPreviewToSide",
        .open_waveform_preview => "waveform.openPreview",
        .open_waveform_preview_side => "waveform.openPreviewToSide",
        .open_pdf_preview => "pdf.openPreview",
        .open_pdf_preview_side => "pdf.openPreviewToSide",
        .open_git_diff_preview => "git.openDiff",
        .open_git_diff_preview_side => "git.openDiffToSide",
        .open_app_preview => "app.openPreview",
        .open_app_preview_side => "app.openPreviewToSide",
        .select_app_preview_dylib => "app.selectPreviewDylib",
    };
}

/// Resolves a VS Code command identifier or friendly alias to a `CommandId`.
pub fn vsCodeIdToCommand(str: []const u8) ?CommandId {
    const s = std.mem.trim(u8, str, " \t\r\n");
    if (s.len == 0) return null;

    // Check exact matches against commandToVSCodeId
    inline for (std.enums.values(CommandId)) |cid| {
        if (std.ascii.eqlIgnoreCase(s, commandToVSCodeId(cid))) {
            return cid;
        }
    }

    // Common VS Code aliases
    if (std.ascii.eqlIgnoreCase(s, "tasks.build") or std.ascii.eqlIgnoreCase(s, "build") or std.ascii.eqlIgnoreCase(s, "run_build_task")) {
        return .run_build_task;
    }
    if (std.ascii.eqlIgnoreCase(s, "tasks.runtask") or std.ascii.eqlIgnoreCase(s, "tasks.run") or std.ascii.eqlIgnoreCase(s, "run_task")) {
        return .run_task;
    }
    if (std.ascii.eqlIgnoreCase(s, "showcommands") or std.ascii.eqlIgnoreCase(s, "command_palette")) {
        return .command_palette;
    }
    if (std.ascii.eqlIgnoreCase(s, "quickopen") or std.ascii.eqlIgnoreCase(s, "quick_open")) {
        return .quick_open;
    }
    if (std.ascii.eqlIgnoreCase(s, "files.save") or std.ascii.eqlIgnoreCase(s, "save") or std.ascii.eqlIgnoreCase(s, "save_file")) {
        return .save_file;
    }
    if (std.ascii.eqlIgnoreCase(s, "files.saveas") or std.ascii.eqlIgnoreCase(s, "save_as")) {
        return .save_file_as;
    }
    if (std.ascii.eqlIgnoreCase(s, "find") or std.ascii.eqlIgnoreCase(s, "find_in_file")) {
        return .find_in_file;
    }
    if (std.ascii.eqlIgnoreCase(s, "findinworkspace") or std.ascii.eqlIgnoreCase(s, "find_in_workspace")) {
        return .find_in_workspace;
    }
    if (std.ascii.eqlIgnoreCase(s, "keybindings") or std.ascii.eqlIgnoreCase(s, "open_keybindings")) {
        return .open_keybindings;
    }
    if (std.ascii.eqlIgnoreCase(s, "keybindings.json") or std.ascii.eqlIgnoreCase(s, "open_keybindings_json")) {
        return .open_keybindings_json;
    }

    // Check enum tag names
    inline for (std.enums.values(CommandId)) |cid| {
        if (std.ascii.eqlIgnoreCase(s, @tagName(cid))) {
            return cid;
        }
    }

    return null;
}

pub const KeybindingManager = struct {
    bindings: std.ArrayListUnmanaged(Keybinding) = .empty,
    pending_chord: ?Shortcut = null,
    pending_chord_time_ms: i64 = 0,

    pub fn initDefaults(self: *KeybindingManager, alloc: std.mem.Allocator) !void {
        self.bindings.clearRetainingCapacity();

        // 1. VS Code Task & Build defaults: Cmd+Shift+B (macOS) / Ctrl+Shift+B (Linux/Windows)
        try self.bindings.append(alloc, .{
            .command_id = .run_build_task,
            .chord = KeyChord.single(.{ .key = .key_b, .cmd = true, .shift = true }),
            .when = .always,
        });

        // 2. Command Palette & Quick Open
        try self.bindings.append(alloc, .{
            .command_id = .command_palette,
            .chord = KeyChord.single(.{ .key = .key_p, .cmd = true, .shift = true }),
        });
        try self.bindings.append(alloc, .{
            .command_id = .quick_open,
            .chord = KeyChord.single(.{ .key = .key_p, .cmd = true, .shift = false }),
        });

        // 3. Keybinding Shortcuts: Cmd+K Cmd+S (VS Code Standard Chord!)
        try self.bindings.append(alloc, .{
            .command_id = .open_keybindings,
            .chord = KeyChord.init(.{ .key = .key_k, .cmd = true }, .{ .key = .key_s, .cmd = true }),
        });

        // 4. File Operations
        try self.bindings.append(alloc, .{
            .command_id = .save_file_as,
            .chord = KeyChord.single(.{ .key = .key_s, .cmd = true, .shift = true }),
        });
        try self.bindings.append(alloc, .{
            .command_id = .save_file,
            .chord = KeyChord.single(.{ .key = .key_s, .cmd = true, .shift = false }),
        });
        try self.bindings.append(alloc, .{
            .command_id = .open_workspace_folder,
            .chord = KeyChord.single(.{ .key = .key_o, .cmd = true, .shift = false }),
        });

        // 5. Navigation & Search
        try self.bindings.append(alloc, .{
            .command_id = .find_in_workspace,
            .chord = KeyChord.single(.{ .key = .key_f, .cmd = true, .shift = true }),
        });
        try self.bindings.append(alloc, .{
            .command_id = .find_in_file,
            .chord = KeyChord.single(.{ .key = .key_f, .cmd = true, .shift = false }),
        });
        try self.bindings.append(alloc, .{
            .command_id = .goto_line_mode,
            .chord = KeyChord.single(.{ .key = .key_g, .cmd = true }),
            .when = .not_find_bar_visible,
        });

        // 6. Split Panes & Window Layout
        try self.bindings.append(alloc, .{
            .command_id = .split_down,
            .chord = KeyChord.single(.{ .key = .key_backslash, .cmd = true, .shift = true }),
        });
        try self.bindings.append(alloc, .{
            .command_id = .move_tab_next_split,
            .chord = KeyChord.single(.{ .key = .key_backslash, .cmd = true, .alt = true }),
        });
        try self.bindings.append(alloc, .{
            .command_id = .split_right,
            .chord = KeyChord.single(.{ .key = .key_backslash, .cmd = true, .shift = false, .alt = false }),
        });
        try self.bindings.append(alloc, .{
            .command_id = .close_active_tab,
            .chord = KeyChord.single(.{ .key = .key_w, .cmd = true }),
        });

        // 7. Workbench Panels
        try self.bindings.append(alloc, .{
            .command_id = .toggle_sidebar,
            .chord = KeyChord.single(.{ .key = .key_b, .cmd = true }),
        });
        try self.bindings.append(alloc, .{
            .command_id = .toggle_terminal_panel,
            .chord = KeyChord.single(.{ .key = .key_j, .cmd = true, .shift = false }),
        });
        try self.bindings.append(alloc, .{
            .command_id = .toggle_output_panel,
            .chord = KeyChord.single(.{ .key = .key_u, .cmd = true, .shift = true }),
        });
        try self.bindings.append(alloc, .{
            .command_id = .toggle_word_wrap,
            .chord = KeyChord.single(.{ .key = .key_z, .cmd_or_ctrl = false, .alt = true }),
        });
        try self.bindings.append(alloc, .{
            .command_id = .focus_group_1,
            .chord = KeyChord.single(.{ .key = .key_1, .cmd = true }),
        });
        try self.bindings.append(alloc, .{
            .command_id = .focus_group_2,
            .chord = KeyChord.single(.{ .key = .key_2, .cmd = true }),
        });

        // 8. Agent & Terminal Buffer Shortcuts
        try self.bindings.append(alloc, .{
            .command_id = .agy_toggle_panel,
            .chord = KeyChord.single(.{ .key = .key_j, .cmd = true, .shift = true }),
        });
        try self.bindings.append(alloc, .{
            .command_id = .new_terminal_buffer,
            .chord = KeyChord.single(.{ .key = .key_t, .cmd = true, .shift = true }),
        });
    }

    pub fn deinit(self: *KeybindingManager, alloc: std.mem.Allocator) void {
        self.bindings.deinit(alloc);
    }

    /// Loads custom keybindings from a VS Code-formatted JSON array string:
    /// ```json
    /// [
    ///   { "key": "shift+cmd+b", "command": "workbench.action.tasks.build" },
    ///   { "key": "cmd+w", "command": "-workbench.action.closeActiveEditor" }
    /// ]
    /// ```
    pub fn loadFromJson(self: *KeybindingManager, alloc: std.mem.Allocator, json_text: []const u8) usize {
        const cleaned = tasks_mod.cleanJsonc(alloc, json_text) catch return 0;
        defer alloc.free(cleaned);

        var parsed = std.json.parseFromSlice(std.json.Value, alloc, cleaned, .{}) catch return 0;
        defer parsed.deinit();

        if (parsed.value != .array) return 0;

        var count: usize = 0;
        for (parsed.value.array.items) |item| {
            if (item != .object) continue;
            const obj = item.object;

            const key_val = obj.get("key") orelse continue;
            if (key_val != .string or key_val.string.len == 0) continue;

            const cmd_val = obj.get("command") orelse continue;
            if (cmd_val != .string or cmd_val.string.len == 0) continue;

            const chord = KeyChord.parse(key_val.string) orelse continue;

            var raw_cmd_str = cmd_val.string;
            var is_unbound = false;
            if (std.mem.startsWith(u8, raw_cmd_str, "-")) {
                is_unbound = true;
                raw_cmd_str = raw_cmd_str[1..];
            }

            const cid = vsCodeIdToCommand(raw_cmd_str) orelse continue;

            var when_clause: WhenClause = .always;
            if (obj.get("when")) |w_val| {
                if (w_val == .string) {
                    when_clause = WhenClause.parse(w_val.string);
                }
            }

            self.addOrOverride(alloc, .{
                .command_id = cid,
                .chord = chord,
                .when = when_clause,
                .is_custom = true,
                .is_unbound = is_unbound,
            }) catch continue;

            count += 1;
        }

        return count;
    }

    /// Adds or updates a keybinding entry. Custom keybindings take precedence over defaults.
    pub fn addOrOverride(self: *KeybindingManager, alloc: std.mem.Allocator, kb: Keybinding) !void {
        // Check for existing matching keybinding
        for (self.bindings.items) |*existing| {
            if (existing.command_id == kb.command_id and existing.when == kb.when) {
                existing.* = kb;
                return;
            }
        }
        // Insert custom bindings at the beginning so they match before defaults
        try self.bindings.insert(alloc, 0, kb);
    }

    /// Attempts to load custom keybindings from `.vscode/keybindings.json` in the workspace root,
    /// or from user directory `~/.lightning/keybindings.json`.
    pub fn loadFromDisk(self: *KeybindingManager, alloc: std.mem.Allocator, workspace_root: []const u8) void {
        var path_buf: [400]u8 = undefined;

        // 1. Workspace keybindings (.vscode/keybindings.json)
        if (std.fmt.bufPrint(&path_buf, "{s}/.vscode/keybindings.json\x00", .{workspace_root})) |p| {
            const p_z: [*:0]const u8 = @ptrCast(p.ptr);
            if (std.c.fopen(p_z, "rb")) |file| {
                defer _ = std.c.fclose(file);
                var read_buf: [8192]u8 = undefined;
                const bytes_read = std.c.fread(&read_buf, 1, read_buf.len, file);
                if (bytes_read > 0) {
                    _ = self.loadFromJson(alloc, read_buf[0..bytes_read]);
                }
            }
        } else |_| {}

        // 2. User keybindings (~/.lightning/keybindings.json)
        if (platform.fs_util.getenv("HOME")) |home_z| {
            const home = std.mem.span(home_z);
            if (std.fmt.bufPrint(&path_buf, "{s}/.lightning/keybindings.json\x00", .{home})) |p| {
                const p_z: [*:0]const u8 = @ptrCast(p.ptr);
                if (std.c.fopen(p_z, "rb")) |file| {
                    defer _ = std.c.fclose(file);
                    var read_buf: [8192]u8 = undefined;
                    const bytes_read = std.c.fread(&read_buf, 1, read_buf.len, file);
                    if (bytes_read > 0) {
                        _ = self.loadFromJson(alloc, read_buf[0..bytes_read]);
                    }
                }
            } else |_| {}
        }
    }

    /// Formats the current keybinding table as a JSON document matching VS Code `keybindings.json`.
    pub fn exportToJson(self: *const KeybindingManager, alloc: std.mem.Allocator) ![]u8 {
        var list: std.ArrayListUnmanaged(u8) = .empty;
        errdefer list.deinit(alloc);

        try list.appendSlice(alloc, "[\n");
        var first = true;
        for (self.bindings.items) |kb| {
            if (kb.is_unbound) continue;
            if (!first) try list.appendSlice(alloc, ",\n");
            first = false;

            var chord_buf: [48]u8 = undefined;
            const chord_str = kb.chord.format(&chord_buf);
            const cmd_str = commandToVSCodeId(kb.command_id);
            const when_str = kb.when.label();

            try list.appendSlice(alloc, "  {\n");
            try list.appendSlice(alloc, "    \"key\": \"");
            // Output lowercase chord string (standard in VS Code JSON)
            for (chord_str) |c| {
                try list.append(alloc, std.ascii.toLower(c));
            }
            try list.appendSlice(alloc, "\",\n");

            try list.appendSlice(alloc, "    \"command\": \"");
            try list.appendSlice(alloc, cmd_str);
            try list.appendSlice(alloc, "\"");

            if (when_str.len > 0) {
                try list.appendSlice(alloc, ",\n    \"when\": \"");
                try list.appendSlice(alloc, when_str);
                try list.appendSlice(alloc, "\"\n");
            } else {
                try list.appendSlice(alloc, "\n");
            }

            try list.appendSlice(alloc, "  }");
        }
        try list.appendSlice(alloc, "\n]\n");
        return list.toOwnedSlice(alloc);
    }

    /// Finds the active keybinding for a given command.
    pub fn findBindingForCommand(self: *const KeybindingManager, cmd: CommandId) ?Keybinding {
        for (self.bindings.items) |kb| {
            if (kb.command_id == cmd and !kb.is_unbound) {
                return kb;
            }
        }
        return null;
    }

    /// Formats the active shortcut for a command into `buf`.
    pub fn formatShortcutForCommand(self: *const KeybindingManager, cmd: CommandId, buf: []u8) ?[]const u8 {
        if (self.findBindingForCommand(cmd)) |kb| {
            return kb.formatDisplay(buf);
        }
        return null;
    }

    /// Dispatches active key events against registered keybindings.
    /// Supports both single shortcuts (e.g. `Cmd+Shift+B`) and two-step chords (`Cmd+K Cmd+S`).
    pub fn dispatch(self: *KeybindingManager, state: *EditorState, active_bottom_tab: ?*u8) bool {
        const uic = &state.ui_ctx;
        if (uic.pass != .input) return false;
        if (uic.key_events.len == 0) return false;

        const term_focused = state.isTerminalFocused();

        // 1. Check if we have an active pending chord (e.g. Cmd+K was pressed on the previous frame)
        if (self.pending_chord) |first_sc| {
            for (uic.key_events) |kev| {
                // Escape cancels pending chord
                if (kev.key == .escape) {
                    self.pending_chord = null;
                    state.setStatusNotice("Chord cancelled.");
                    uic.invalidateWindow();
                    return true;
                }

                // Check if (first_sc, kev) matches any chorded keybinding
                for (self.bindings.items) |kb| {
                    if (kb.is_unbound) continue;
                    if (!kb.chord.isChord()) continue;
                    if (!kb.when.matches(state)) continue;

                    if (kb.chord.first.matches(.{ .key = first_sc.key, .cmd = first_sc.cmd, .ctrl = first_sc.ctrl, .alt = first_sc.alt, .shift = first_sc.shift })) {
                        if (kb.chord.matchesSecond(kev)) {
                            self.pending_chord = null;
                            commands_mod.execute(state, kb.command_id, false, active_bottom_tab);
                            uic.invalidateWindow();
                            return true;
                        }
                    }
                }
            }

            // If an unmapped key was pressed while waiting for second chord, cancel chord
            self.pending_chord = null;
        }

        // 2. Normal dispatch across registered keybindings
        for (self.bindings.items) |kb| {
            if (kb.is_unbound) continue;
            if (!kb.when.matches(state)) continue;

            const sc = kb.chord.first;

            // When a terminal has focus, reserve Ctrl+<key> (without Cmd) for POSIX/Vim terminal escapes
            if (term_focused and kb.when != .terminal_focus) {
                var has_cmd_match = false;
                for (uic.key_events) |kev| {
                    if (kev.key == sc.key and (kev.cmd or sc.cmd) and kev.shift == sc.shift and kev.alt == sc.alt) {
                        has_cmd_match = true;
                        break;
                    }
                }
                if (!has_cmd_match) continue;
            }

            if (uic.shortcut(sc)) {
                // If this is a chorded shortcut, enter pending chord mode
                if (kb.chord.isChord()) {
                    self.pending_chord = sc;
                    self.pending_chord_time_ms = @intCast(platform.profiler.nowNs() / std.time.ns_per_ms);

                    var sc_buf: [32]u8 = undefined;
                    const sc_str = sc.format(&sc_buf);
                    var notice_buf: [96]u8 = undefined;
                    const notice_msg = std.fmt.bufPrint(&notice_buf, "({s}) was pressed. Waiting for second key of chord...", .{sc_str}) catch "Waiting for second key of chord...";
                    state.setStatusNotice(notice_msg);
                    uic.invalidateWindow();
                    return true;
                }

                // Single shortcut matched! Execute the command!
                commands_mod.execute(state, kb.command_id, false, active_bottom_tab);
                uic.invalidateWindow();
                return true;
            }
        }

        return false;
    }
};

// ============================================================================
// Unit Tests
// ============================================================================

test "keybindings: initDefaults, commandToVSCodeId, and loadFromJson" {
    var mgr = KeybindingManager{};
    try mgr.initDefaults(std.testing.allocator);
    defer mgr.deinit(std.testing.allocator);

    // Verify build task is registered by default with Shift+Cmd+B
    const build_kb = mgr.findBindingForCommand(.run_build_task).?;
    try std.testing.expectEqual(KeyCode.key_b, build_kb.chord.first.key);
    try std.testing.expect(build_kb.chord.first.cmd);
    try std.testing.expect(build_kb.chord.first.shift);

    var disp_buf: [48]u8 = undefined;
    try std.testing.expectEqualStrings("Shift+Cmd+B", build_kb.formatDisplay(&disp_buf));
    try std.testing.expectEqualStrings("workbench.action.tasks.build", commandToVSCodeId(.run_build_task));

    // Custom user keybinding override via JSON
    const user_json =
        \\[
        \\  {
        \\    "key": "cmd+b",
        \\    "command": "workbench.action.tasks.build"
        \\  },
        \\  {
        \\    "key": "cmd+w",
        \\    "command": "-workbench.action.closeActiveEditor"
        \\  }
        \\]
    ;
    const loaded = mgr.loadFromJson(std.testing.allocator, user_json);
    try std.testing.expectEqual(@as(usize, 2), loaded);

    // Overridden build command now formats as "Cmd+B"
    const custom_build = mgr.findBindingForCommand(.run_build_task).?;
    try std.testing.expectEqualStrings("Cmd+B", custom_build.formatDisplay(&disp_buf));

    // Close active editor is now unbound
    const unbound_w = mgr.findBindingForCommand(.close_active_tab);
    try std.testing.expect(unbound_w == null);

    // Export to JSON roundtrip
    const exported_json = try mgr.exportToJson(std.testing.allocator);
    defer std.testing.allocator.free(exported_json);
    try std.testing.expect(std.mem.indexOf(u8, exported_json, "workbench.action.tasks.build") != null);
}
