//! Declarative Keybinding & Command Registry (`commands.zig`).
//!
//! Single source of truth for all editor commands, Command Palette entries (`Shift+Cmd+P`),
//! and global keyboard shortcuts (`uic.shortcut(...)`). Eliminates duplicate dispatch
//! tables between the Command Palette and global keyboard event handling.

const std = @import("std");
const ui = @import("ui");
const state_mod = @import("state.zig");
const EditorState = state_mod.EditorState;

pub const Shortcut = ui.Shortcut;
pub const containsIgnoreCase = ui.command_registry_mod.containsIgnoreCase;

pub const tasks_mod = @import("tasks.zig");
pub const keybindings_mod = @import("keybindings.zig");

pub const Category = enum {
    view,
    file,
    edit,
    agent,
    supercomplete,
    terminal,
    markdown,
    waveform,
    pdf,
    git,
    workspace,
    developer,
    plugins,
    navigation,
    tasks,
    preferences,

    pub fn label(self: Category) []const u8 {
        return switch (self) {
            .view => "View",
            .file => "File",
            .edit => "Edit",
            .agent => "Agent",
            .supercomplete => "Supercomplete",
            .terminal => "Terminal",
            .markdown => "Markdown",
            .waveform => "Waveform",
            .pdf => "PDF",
            .git => "Git",
            .workspace => "Workspace",
            .developer => "Developer",
            .plugins => "Plugins",
            .navigation => "Go",
            .tasks => "Tasks",
            .preferences => "Preferences",
        };
    }
};

pub const CommandId = enum {
    run_build_task,
    run_task,
    command_palette,
    quick_open,
    supercomplete_toggle,
    supercomplete_trigger,
    supercomplete_restart,
    agy_toggle_panel,
    agy_send_selection_or_file,
    agy_fix_diagnostics,
    agy_interrupt_turn,
    agy_reset_conversation,
    agy_load_conversation,
    agy_cycle_mode,
    agy_cycle_effort,
    agy_handoff_tui,
    new_agent_buffer,
    new_agent_side,
    new_terminal_buffer,
    new_terminal_side,
    open_markdown_preview,
    open_markdown_preview_side,
    create_bound_markdown_preview,
    create_bound_markdown_preview_side,
    open_waveform_preview,
    open_waveform_preview_side,
    open_pdf_preview,
    open_pdf_preview_side,
    open_git_diff_preview,
    open_git_diff_preview_side,
    open_app_preview,
    open_app_preview_side,
    select_app_preview_dylib,
    open_workspace_folder,
    refresh_workspace,
    split_right,
    split_down,
    move_tab_next_split,
    close_active_tab,
    close_active_split,
    focus_group_1,
    focus_group_2,
    toggle_sidebar,
    toggle_terminal_panel,
    toggle_output_panel,
    toggle_waveform_panel,
    toggle_minimap,
    toggle_word_wrap,
    toggle_dirty_overlay,
    save_file,
    save_file_as,
    open_scratch_buffer,
    save_all_files,
    revert_file,
    find_in_workspace,
    find_in_file,
    goto_symbol_mode,
    goto_line_mode,
    open_user_plugins_folder,
    reload_all_plugins,
    open_keybindings,
    open_keybindings_json,
};

pub const CommandSpec = struct {
    id: CommandId,
    label: []const u8,
    category: Category = .view,
    shortcut_display: []const u8 = "",
    shortcut: ?Shortcut = null,
    icon_text: []const u8,
    show_in_palette: bool = true,

    pub fn categoryLabel(self: CommandSpec) []const u8 {
        if (std.mem.indexOfScalar(u8, self.label, ':')) |colon_idx| {
            return self.label[0..colon_idx];
        }
        return self.category.label();
    }
};

pub const Command = CommandSpec;

/// Returns `true` if `cmd` matches `query` via `ui.command_registry_mod.matchesCommandQuery`.
pub fn matchesQuery(cmd: CommandSpec, query: []const u8) bool {
    return ui.command_registry_mod.matchesCommandQuery(
        cmd.label,
        cmd.categoryLabel(),
        cmd.shortcut_display,
        query,
    );
}

/// Scores `cmd` against `query` via `ui.command_registry_mod.scoreCommandMatch`.
pub fn scoreQuery(cmd: CommandSpec, query: []const u8) ?i32 {
    return ui.command_registry_mod.scoreCommandMatch(
        cmd.label,
        cmd.categoryLabel(),
        cmd.shortcut_display,
        query,
    );
}

/// Canonical command registry ordered so more-specific modifier combinations (`Shift+Cmd+...`, `Alt+Cmd+...`)
/// precede base shortcuts (`Cmd+...`) for deterministic shortcut matching.
pub const COMMANDS = [_]CommandSpec{
    .{
        .id = .run_build_task,
        .label = "Tasks: Run Build Task",
        .category = .tasks,
        .shortcut_display = "Shift+Cmd+B",
        .shortcut = .{ .key = .key_b, .cmd = true, .shift = true },
        .icon_text = "⚡",
    },
    .{
        .id = .run_task,
        .label = "Tasks: Run Task",
        .category = .tasks,
        .shortcut_display = "",
        .shortcut = null,
        .icon_text = "⚡",
        .show_in_palette = true,
    },
    .{
        .id = .command_palette,
        .label = "View: Show Command Palette",
        .shortcut_display = "Shift+Cmd+P",
        .shortcut = .{ .key = .key_p, .cmd = true, .shift = true },
        .icon_text = ">",
        .show_in_palette = false,
    },
    .{
        .id = .quick_open,
        .label = "File: Quick Open File by Name...",
        .shortcut_display = "Cmd+P",
        .shortcut = .{ .key = .key_p, .cmd = true, .shift = false },
        .icon_text = "F",
        .show_in_palette = false,
    },
    .{ .id = .supercomplete_toggle, .label = "Supercomplete: Toggle", .icon_text = "✦" },
    .{ .id = .supercomplete_trigger, .label = "Supercomplete: Trigger Suggestion", .icon_text = "✦" },
    .{ .id = .supercomplete_restart, .label = "Supercomplete: Reconnect Engine", .icon_text = "↺" },
    .{
        .id = .agy_toggle_panel,
        .label = "Agent: Toggle Antigravity Agent Panel",
        .shortcut_display = "Shift+Cmd+J",
        .shortcut = .{ .key = .key_j, .cmd = true, .shift = true },
        .icon_text = "✦",
    },
    .{ .id = .agy_send_selection_or_file, .label = "Agent: Send Selection or File to Antigravity", .icon_text = "✦" },
    .{ .id = .agy_fix_diagnostics, .label = "Agent: Fix Diagnostics in Active File", .icon_text = "✦" },
    .{ .id = .agy_interrupt_turn, .label = "Agent: Interrupt Current Turn (SIGTERM)", .icon_text = "■" },
    .{ .id = .agy_reset_conversation, .label = "Agent: Reset Antigravity Conversation", .icon_text = "↺" },
    .{ .id = .agy_load_conversation, .label = "Agent: Load / Resume Past Antigravity Conversation...", .icon_text = "✦" },
    .{ .id = .agy_cycle_mode, .label = "Agent: Cycle Execution Mode (auto / accept-edits / plan)", .icon_text = "⚙" },
    .{ .id = .agy_cycle_effort, .label = "Agent: Cycle Reasoning Effort (low..max)", .icon_text = "⚡" },
    .{ .id = .agy_handoff_tui, .label = "Agent: Open Conversation in Interactive Terminal (TUI)", .icon_text = "T" },
    .{ .id = .new_agent_buffer, .label = "Agent: Create New Agent Buffer", .icon_text = "✦" },
    .{ .id = .new_agent_side, .label = "Agent: Create New Agent Buffer to the Side", .icon_text = "✦" },
    .{
        .id = .new_terminal_buffer,
        .label = "Terminal: Create New Terminal Buffer",
        .shortcut_display = "Shift+Cmd+T",
        .shortcut = .{ .key = .key_t, .cmd = true, .shift = true },
        .icon_text = "T",
    },
    .{ .id = .new_terminal_side, .label = "Terminal: Create New Terminal to the Side", .icon_text = "T" },
    .{ .id = .open_markdown_preview, .label = "Markdown: Open Preview Buffer", .icon_text = "M" },
    .{ .id = .open_markdown_preview_side, .label = "Markdown: Open Preview to the Side", .icon_text = "M" },
    .{ .id = .create_bound_markdown_preview, .label = "Markdown: Create Preview Buffer Tied to Current Buffer", .icon_text = "M" },
    .{ .id = .create_bound_markdown_preview_side, .label = "Markdown: Create Preview Tied to Current Buffer to the Side", .icon_text = "M" },
    .{ .id = .open_waveform_preview, .label = "Waveform: Open Waveform Preview Buffer", .icon_text = "W" },
    .{ .id = .open_waveform_preview_side, .label = "Waveform: Open Waveform Preview to the Side", .icon_text = "W" },
    .{ .id = .open_pdf_preview, .label = "PDF: Open PDF Document Preview Buffer", .icon_text = "P" },
    .{ .id = .open_pdf_preview_side, .label = "PDF: Open PDF Document Preview to the Side", .icon_text = "P" },
    .{ .id = .open_git_diff_preview, .label = "Git: Open Diff View Buffer", .icon_text = "D" },
    .{ .id = .open_git_diff_preview_side, .label = "Git: Open Diff View to the Side", .icon_text = "D" },
    .{ .id = .open_app_preview, .label = "App: Open App Simulator Buffer", .icon_text = "⚡" },
    .{ .id = .open_app_preview_side, .label = "App: Open App Simulator to the Side", .icon_text = "⚡" },
    .{ .id = .select_app_preview_dylib, .label = "App: Select Preview App .dylib...", .icon_text = "📱" },
    .{
        .id = .open_workspace_folder,
        .label = "File: Open Workspace Folder...",
        .shortcut_display = "Cmd+O",
        .shortcut = .{ .key = .key_o, .cmd = true, .shift = false },
        .icon_text = "F",
    },
    .{ .id = .refresh_workspace, .label = "Workspace: Refresh File Explorer", .icon_text = "↺" },
    .{
        .id = .split_down,
        .label = "View: Split Editor Down",
        .shortcut_display = "Shift+Cmd+\\",
        .shortcut = .{ .key = .key_backslash, .cmd = true, .shift = true },
        .icon_text = "S",
    },
    .{
        .id = .move_tab_next_split,
        .label = "View: Move Editor Tab to Next Split",
        .shortcut_display = "Alt+Cmd+\\",
        .shortcut = .{ .key = .key_backslash, .cmd = true, .alt = true },
        .icon_text = "→",
    },
    .{
        .id = .split_right,
        .label = "View: Split Editor Right",
        .shortcut_display = "Cmd+\\",
        .shortcut = .{ .key = .key_backslash, .cmd = true, .shift = false, .alt = false },
        .icon_text = "S",
    },
    .{
        .id = .close_active_tab,
        .label = "View: Close Active Editor Tab",
        .shortcut_display = "Cmd+W",
        .shortcut = .{ .key = .key_w, .cmd = true },
        .icon_text = "×",
    },
    .{ .id = .close_active_split, .label = "View: Close Active Split Group", .icon_text = "×" },
    .{
        .id = .save_file_as,
        .label = "File: Save As New File...",
        .shortcut_display = "Shift+Cmd+S",
        .shortcut = .{ .key = .key_s, .cmd = true, .shift = true },
        .icon_text = "F",
    },
    .{
        .id = .save_file,
        .label = "File: Save Active File",
        .shortcut_display = "Cmd+S",
        .shortcut = .{ .key = .key_s, .cmd = true, .shift = false },
        .icon_text = "F",
    },
    .{ .id = .open_scratch_buffer, .label = "File: Open *scratch* Buffer in Active Pane", .icon_text = "F" },
    .{ .id = .save_all_files, .label = "File: Save All Modified Files", .icon_text = "F" },
    .{ .id = .revert_file, .label = "File: Revert File from Disk", .icon_text = "↺" },
    .{
        .id = .find_in_workspace,
        .label = "Edit: Find in Workspace...",
        .shortcut_display = "Shift+Cmd+F",
        .shortcut = .{ .key = .key_f, .cmd = true, .shift = true },
        .icon_text = "?",
    },
    .{
        .id = .find_in_file,
        .label = "Edit: Find in Current File",
        .shortcut_display = "Cmd+F",
        .shortcut = .{ .key = .key_f, .cmd = true, .shift = false },
        .icon_text = "?",
    },
    .{
        .id = .goto_symbol_mode,
        .label = "Go to Symbol in Editor...",
        .shortcut_display = "@",
        .icon_text = "@",
    },
    .{
        .id = .goto_line_mode,
        .label = "Go to Line / Column...",
        .shortcut_display = "Cmd+G / :",
        .shortcut = .{ .key = .key_g, .cmd = true },
        .icon_text = ":",
    },
    .{
        .id = .toggle_sidebar,
        .label = "View: Toggle Primary Side Bar",
        .shortcut_display = "Cmd+B",
        .shortcut = .{ .key = .key_b, .cmd = true },
        .icon_text = "V",
    },
    .{
        .id = .toggle_terminal_panel,
        .label = "View: Toggle Terminal & Problems Panel",
        .shortcut_display = "Cmd+J",
        .shortcut = .{ .key = .key_j, .cmd = true, .shift = false },
        .icon_text = "T",
    },
    .{
        .id = .toggle_output_panel,
        .label = "View: Toggle Output Log Panel",
        .shortcut_display = "Cmd+Shift+U",
        .shortcut = .{ .key = .key_u, .cmd = true, .shift = true },
        .icon_text = "O",
    },
    .{
        .id = .toggle_waveform_panel,
        .label = "View: Toggle Digital Waveform & VCD Logic Analyzer",
        .icon_text = "~",
    },
    .{ .id = .toggle_minimap, .label = "View: Toggle Code Minimap", .icon_text = "M" },
    .{
        .id = .toggle_word_wrap,
        .label = "View: Toggle Word Wrap",
        .shortcut_display = "Alt+Z",
        .shortcut = .{ .key = .key_z, .cmd_or_ctrl = false, .alt = true },
        .icon_text = "W",
    },
    .{ .id = .toggle_dirty_overlay, .label = "Developer: Toggle Dirty-Rect Paint Overlay", .icon_text = "D" },
    .{
        .id = .focus_group_1,
        .label = "View: Focus Editor Group 1",
        .shortcut_display = "Cmd+1",
        .shortcut = .{ .key = .key_1, .cmd = true },
        .icon_text = "1",
    },
    .{
        .id = .focus_group_2,
        .label = "View: Focus Editor Group 2",
        .shortcut_display = "Cmd+2",
        .shortcut = .{ .key = .key_2, .cmd = true },
        .icon_text = "2",
    },
    .{
        .id = .open_user_plugins_folder,
        .label = "Plugins: Open User Plugins Folder (~/.lightning/plugins)",
        .icon_text = "P",
    },
    .{
        .id = .reload_all_plugins,
        .label = "Plugins: Reload All Dynamic Plugins",
        .icon_text = "↺",
    },
    .{
        .id = .open_keybindings,
        .label = "Preferences: Open Keyboard Shortcuts",
        .category = .preferences,
        .shortcut_display = "Cmd+K Cmd+S",
        .icon_text = "⚙",
    },
    .{
        .id = .open_keybindings_json,
        .label = "Preferences: Open Keyboard Shortcuts (JSON)",
        .category = .preferences,
        .icon_text = "{}",
    },
};

comptime {
    // Verify at compile time that every command with a keybinding has a display label.
    for (COMMANDS) |cmd| {
        if (cmd.shortcut != null and cmd.shortcut_display.len == 0) {
            @compileError("CommandSpec with .shortcut must also specify .shortcut_display");
        }
    }
}

/// Evaluates all registered global shortcuts against `state.ui_ctx` during `Pass.input`
/// and executes the matching command. Uses the VS Code-compatible `KeybindingManager`
/// with automatic chord handling (`Cmd+K Cmd+S`) and user overrides, falling back to
/// the static `COMMANDS` table if the manager has not yet been initialized.
pub fn dispatchGlobalShortcuts(state: *EditorState, active_bottom_tab: ?*u8) bool {
    if (state.keybindings.bindings.items.len > 0) {
        return state.keybindings.dispatch(state, active_bottom_tab);
    }

    const uic = &state.ui_ctx;
    const term_focused = state.isTerminalFocused();
    for (COMMANDS) |spec| {
        const sc = spec.shortcut orelse continue;
        // Skip Cmd+G when the Find Bar is open so Cmd+G can be used for find-next if desired
        if (spec.id == .goto_line_mode and state.doc.show_find_bar) continue;

        // When a terminal (`VTerm`) has focus, reserve `Ctrl+<key>` (without `Cmd`) for POSIX
        // terminal/vim control sequences (`^W`, `^F`, `^B`, `^P`, `^J`, `^G`, `^S`, `^\`).
        if (term_focused) {
            var has_cmd_match = false;
            for (uic.key_events) |kev| {
                if (kev.key == sc.key and kev.cmd and kev.shift == sc.shift and kev.alt == sc.alt) {
                    has_cmd_match = true;
                    break;
                }
            }
            if (!has_cmd_match) continue;
        }

        if (uic.shortcut(sc)) {
            execute(state, spec.id, false, active_bottom_tab);
            return true;
        }
    }
    return false;
}

/// Executes `id` against `state`. Both global shortcuts (`from_palette == false`)
/// and Command Palette selection (`from_palette == true`) route through this function.
pub fn execute(
    state: *EditorState,
    id: CommandId,
    from_palette: bool,
    active_bottom_tab: ?*u8,
) void {
    const uic = &state.ui_ctx;
    switch (id) {
        .command_palette => {
            state.openPaletteWithPrefix(">");
            uic.focused_id = uic.resolveIdAndLabel("##palette_input").wid;
            return;
        },
        .quick_open => {
            if (state.doc.show_command_palette and state.paletteQuery().len == 0) {
                state.doc.show_command_palette = false;
                uic.focused_id = state.activeEditorWidgetId();
            } else {
                state.openPaletteWithPrefix("");
                uic.focused_id = uic.resolveIdAndLabel("##palette_input").wid;
            }
            return;
        },
        .goto_symbol_mode => {
            state.openPaletteWithPrefix("@");
            uic.focused_id = uic.resolveIdAndLabel("##palette_input").wid;
            return;
        },
        .goto_line_mode => {
            state.openPaletteWithPrefix(":");
            uic.focused_id = uic.resolveIdAndLabel("##palette_input").wid;
            return;
        },
        .supercomplete_toggle => state.toggleSupercomplete(),
        .supercomplete_trigger => state.triggerSupercomplete(),
        .supercomplete_restart => state.reconnectSupercomplete(),
        .agy_toggle_panel => {
            state.doc.show_agent_panel = !state.doc.show_agent_panel;
            state.doc.show_command_palette = false;
            if (state.doc.show_agent_panel) {
                uic.focused_id = ui.scopedIdPath(&.{ "vscode_workbench", "agy_agent_panel" }, "##agy_prompt_input");
            } else {
                uic.focused_id = state.activeEditorWidgetId();
            }
            return;
        },
        .agy_send_selection_or_file => {
            state.doc.show_command_palette = false;
            state.sendAgySelectionOrFilePrompt("Review and explain this code.");
            uic.focused_id = ui.scopedIdPath(&.{ "vscode_workbench", "agy_agent_panel" }, "##agy_prompt_input");
            return;
        },
        .agy_fix_diagnostics => {
            state.doc.show_command_palette = false;
            state.sendAgyDiagnosticsPrompt();
            uic.focused_id = ui.scopedIdPath(&.{ "vscode_workbench", "agy_agent_panel" }, "##agy_prompt_input");
            return;
        },
        .agy_interrupt_turn => state.activeAgySession().interruptTurn(),
        .agy_reset_conversation => state.activeAgySession().resetConversation(),
        .agy_load_conversation => {
            state.doc.show_command_palette = false;
            state.openAgyConversationPicker();
            return;
        },
        .agy_cycle_mode => {
            const sess = state.activeAgySession();
            sess.cycleMode();
            state.setStatusNotice(uic.fmt("agy mode: {s}", .{sess.mode.label()}));
        },
        .agy_cycle_effort => {
            const sess = state.activeAgySession();
            sess.cycleEffort();
            state.setStatusNotice(uic.fmt("agy effort: {s}", .{sess.effort.label()}));
        },
        .agy_handoff_tui => state.handoffAgyToTerminal(),
        .new_agent_buffer => state.createAgentBuffer(false),
        .new_agent_side => state.createAgentBuffer(true),
        .new_terminal_buffer => state.createTerminalBuffer(false),
        .new_terminal_side => state.createTerminalBuffer(true),
        .open_markdown_preview => state.openMarkdownPreviewBuffer(false),
        .open_markdown_preview_side => state.openMarkdownPreviewBuffer(true),
        .create_bound_markdown_preview => state.createBoundMarkdownPreviewBuffer(false),
        .create_bound_markdown_preview_side => state.createBoundMarkdownPreviewBuffer(true),
        .open_waveform_preview => state.openWaveformPreviewBuffer(false),
        .open_waveform_preview_side => state.openWaveformPreviewBuffer(true),
        .open_pdf_preview => state.openPdfPreviewBuffer(false),
        .open_pdf_preview_side => state.openPdfPreviewBuffer(true),
        .open_git_diff_preview => state.openGitDiffPreviewBuffer(false),
        .open_git_diff_preview_side => state.openGitDiffPreviewBuffer(true),
        .open_app_preview => state.openAppPreviewBuffer(false),
        .open_app_preview_side => state.openAppPreviewBuffer(true),
        .select_app_preview_dylib => {
            state.openPaletteWithPrefix("app: ");
            return;
        },
        .open_workspace_folder => {
            state.openWorkspacePrompt();
            return;
        },
        .refresh_workspace => state.refreshWorkspaceFiles(true),
        .split_right => state.splitEditorRight(),
        .split_down => state.splitEditorDown(),
        .move_tab_next_split => state.moveActiveTabToOtherSplit(),
        .close_active_tab => state.closeActiveTab(),
        .close_active_split => state.closeSplitPane(state.activePaneIndex()),
        .focus_group_1 => state.focusPane(0),
        .focus_group_2 => {
            if (state.paneCount() > 1) {
                state.focusPane(1);
            }
        },
        .toggle_sidebar => state.doc.show_sidebar = !state.doc.show_sidebar,
        .toggle_terminal_panel => {
            state.doc.show_bottom_panel = !state.doc.show_bottom_panel;
            state.doc.show_command_palette = false;
            if (state.doc.show_bottom_panel) {
                if (active_bottom_tab) |tab| tab.* = 0;
                uic.focused_id = ui.id("workbench_vterm");
            } else {
                uic.focused_id = state.activeEditorWidgetId();
            }
            return;
        },
        .toggle_output_panel => {
            state.doc.show_bottom_panel = !state.doc.show_bottom_panel;
            state.doc.show_command_palette = false;
            if (state.doc.show_bottom_panel) {
                if (active_bottom_tab) |tab| tab.* = 2;
            } else {
                uic.focused_id = state.activeEditorWidgetId();
            }
            return;
        },
        .toggle_waveform_panel => {
            state.openWaveformPreviewBuffer(true);
        },
        .toggle_minimap => state.doc.show_minimap = !state.doc.show_minimap,
        .toggle_word_wrap => {
            const cur_file = state.activeFileIndex();
            const new_state = state.toggleBufferWordWrap(cur_file);
            state.setStatusNotice(if (new_state) "Word Wrap: Enabled for current buffer" else "Word Wrap: Disabled for current buffer");
            state.ui_ctx.invalidateWindow();
        },
        .toggle_dirty_overlay => state.doc.show_dirty_overlay = !state.doc.show_dirty_overlay,
        .save_file => {
            if (state.activeFileIndex()) |f_idx| {
                _ = state.saveFileToDisk(f_idx);
            } else {
                state.openSaveAsPrompt();
                return;
            }
        },
        .save_file_as => {
            state.openSaveAsPrompt();
            return;
        },
        .open_scratch_buffer => {
            state.openScratchInActivePane();
        },
        .save_all_files => _ = state.saveAllDirtyFiles(),
        .revert_file => {
            if (state.activeFileIndex()) |f_idx| {
                state.loadFileFromDiskOrFallback(f_idx);
                state.setStatusNotice("Reverted file from disk");
            }
        },
        .find_in_workspace => {
            state.openWorkspaceSearch();
            return;
        },
        .find_in_file => {
            state.openFindBar();
            return;
        },
        .open_user_plugins_folder => {
            _ = state.plugins.ensureUserPluginsDirectoryExists();
            var dir_buf: [256:0]u8 = @splat(0);
            if (state.plugins.userPluginsDirectory(&dir_buf)) |dir_slice| {
                const io = std.Options.debug_io;
                var child = std.process.spawn(io, .{
                    .argv = &.{ "open", dir_slice },
                    .stdin = .ignore,
                    .stdout = .ignore,
                    .stderr = .ignore,
                }) catch null;
                if (child) |*c| _ = c.wait(io) catch null;
                state.setStatusNotice("Opened ~/.lightning/plugins");
            }
        },
        .reload_all_plugins => {
            _ = state.plugins.scanAndReloadPlugins(state, true);
            state.setStatusNotice("Scanned plugins (~/.lightning/plugins, zig-out/plugins)");
        },
        .run_build_task => {
            tasks_mod.runBuildTask(state, active_bottom_tab);
            return;
        },
        .run_task => {
            state.doc.show_command_palette = true;
            state.setPaletteQuery("> task:");
            uic.focused_id = ui.id("workbench_palette_input");
            return;
        },
        .open_keybindings => {
            state.openKeybindingsView();
            return;
        },
        .open_keybindings_json => {
            state.openKeybindingsFile();
            return;
        },
    }

    if (from_palette) {
        state.doc.show_command_palette = false;
        uic.focused_id = state.activeEditorWidgetId();
    }
}

test "commands registry: all CommandId values are represented and shortcuts have display labels" {
    for (std.enums.values(CommandId)) |cid| {
        var found = false;
        for (COMMANDS) |spec| {
            if (spec.id == cid) {
                found = true;
                break;
            }
        }
        try std.testing.expect(found);
    }
}

test "commands: toggle_word_wrap spec, default markdown word wrap, and buffer toggle execution" {
    const platform = @import("platform");

    // 1. Verify toggle_word_wrap is registered with Alt+Z
    var found_spec: ?CommandSpec = null;
    for (COMMANDS) |spec| {
        if (spec.id == .toggle_word_wrap) {
            found_spec = spec;
            break;
        }
    }
    try std.testing.expect(found_spec != null);
    const spec = found_spec.?;
    try std.testing.expectEqualStrings("View: Toggle Word Wrap", spec.label);
    try std.testing.expectEqualStrings("Alt+Z", spec.shortcut_display);
    try std.testing.expect(spec.shortcut != null);
    try std.testing.expectEqual(platform.KeyCode.key_z, spec.shortcut.?.key);
    try std.testing.expectEqual(true, spec.shortcut.?.alt);
    try std.testing.expectEqual(false, spec.shortcut.?.cmd_or_ctrl);

    // 2. Initialize EditorState to test buffer word wrap logic and command execution
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

    // Check defaults across loaded files
    // Find a markdown file and a non-markdown file (or create dynamic slots)
    var md_idx_opt: ?usize = null;
    var non_md_idx_opt: ?usize = null;
    for (state.workspaceFiles(), 0..) |wf, i| {
        if (wf.language == .markdown and !wf.isSpecial() and md_idx_opt == null) {
            md_idx_opt = i;
        } else if (wf.language != .markdown and !wf.isSpecial() and non_md_idx_opt == null) {
            non_md_idx_opt = i;
        }
    }

    if (md_idx_opt) |md_idx| {
        // Markdown files must default to word wrapped
        try std.testing.expectEqual(true, state.isBufferWordWrap(md_idx));
        // Toggle should flip it to false
        _ = state.toggleBufferWordWrap(md_idx);
        try std.testing.expectEqual(false, state.isBufferWordWrap(md_idx));
        // Toggle again should flip back to true
        _ = state.toggleBufferWordWrap(md_idx);
        try std.testing.expectEqual(true, state.isBufferWordWrap(md_idx));
    }

    if (non_md_idx_opt) |code_idx| {
        // Non-markdown files must default to non-word wrapped
        try std.testing.expectEqual(false, state.isBufferWordWrap(code_idx));
        // Toggle should flip it to true
        _ = state.toggleBufferWordWrap(code_idx);
        try std.testing.expectEqual(true, state.isBufferWordWrap(code_idx));
        // Toggle again should flip back to false
        _ = state.toggleBufferWordWrap(code_idx);
        try std.testing.expectEqual(false, state.isBufferWordWrap(code_idx));

        // Test command execution via execute()
        state.openFile(code_idx);
        try std.testing.expectEqual(false, state.isBufferWordWrap(code_idx));
        execute(state, .toggle_word_wrap, false, null);
        try std.testing.expectEqual(true, state.isBufferWordWrap(code_idx));
        execute(state, .toggle_word_wrap, false, null);
        try std.testing.expectEqual(false, state.isBufferWordWrap(code_idx));
    }

    // Test scratch buffer word wrap default and toggle
    try std.testing.expectEqual(false, state.isBufferWordWrap(null));
    _ = state.toggleBufferWordWrap(null);
    try std.testing.expectEqual(true, state.isBufferWordWrap(null));
}

test "commands: find_in_file and find_in_workspace focus search input with all text highlighted" {
    const platform = @import("platform");
    const modals = @import("views/modals.zig");

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

    // 1. Select a word in the active buffer and execute .find_in_file (Cmd+F)
    state.openScratchInActivePane();
    state.scratch_buf.setText("const target_symbol = 42;\n");
    state.scratch_buf.selection_anchor = 6;
    state.scratch_buf.cursor = 19; // "target_symbol"
    execute(state, .find_in_file, false, null);

    try std.testing.expect(state.doc.show_find_bar);
    try std.testing.expectEqualStrings("target_symbol", state.findQuery());
    const expected_find_wid = ui.scopedIdPath(&.{ "vscode_workbench", "editor_pane" }, "##find_bar_input");
    try std.testing.expectEqual(expected_find_wid, state.ui_ctx.focused_id);
    try std.testing.expectEqual(expected_find_wid, state.ui_ctx.select_all_wid);

    // 2. Pressing Cmd+F again while Find Bar is already open keeps it open and re-selects all text
    execute(state, .find_in_file, false, null);
    try std.testing.expect(state.doc.show_find_bar);
    try std.testing.expectEqual(expected_find_wid, state.ui_ctx.focused_id);
    try std.testing.expectEqual(expected_find_wid, state.ui_ctx.select_all_wid);

    // Run buildFindBar in Pass.input and verify TextInputState has anchor=0, cursor=13 ("target_symbol".len)
    const skia = @import("skia");
    const surface = try skia.Surface.initRasterN32Premul(640, 120);
    defer surface.deinit();
    state.ui_ctx.beginPass(.input, state.frame_arena.allocator(), surface.canvas(), skia.Rect.xywh(0, 0, 640, 120), 0, 0, false, false, false);
    {
        var wb_scope = state.ui_ctx.scopedState("vscode_workbench");
        defer wb_scope.end();
        var ep_scope = state.ui_ctx.scopedState("editor_pane");
        defer ep_scope.end();
        modals.buildFindBar(state, null);
        const st = state.ui_ctx.useState(ui.TextInputState, "##find_bar_input", .{});
        try std.testing.expectEqual(@as(u32, 0), st.anchor);
        try std.testing.expectEqual(@as(u32, 13), st.cursor);
        try std.testing.expect(st.hasSelection());
    }
    state.ui_ctx.endPass();

    // 3. Execute .find_in_workspace (Shift+Cmd+F) -> opens Search sidebar and selects all in ##workspace_search_input
    execute(state, .find_in_workspace, false, null);
    try std.testing.expect(state.doc.show_sidebar);
    try std.testing.expectEqual(@as(u8, 1), state.doc.active_sidebar_view);
    try std.testing.expectEqualStrings("target_symbol", state.workspaceSearchQuery());
    const expected_ws_wid = ui.scopedIdPath(&.{ "vscode_workbench", "explorer_sidebar" }, "##workspace_search_input");
    try std.testing.expectEqual(expected_ws_wid, state.ui_ctx.focused_id);
    try std.testing.expectEqual(expected_ws_wid, state.ui_ctx.select_all_wid);
}

test "commands: create_bound_markdown_preview stays tied to target buffer when switching markdown files" {
    const platform = @import("platform");

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

    var md1_idx: ?usize = null;
    var md2_idx: ?usize = null;
    for (state.workspaceFiles(), 0..) |wf, idx| {
        if (wf.language == .markdown and !wf.isSpecial()) {
            if (md1_idx == null) {
                md1_idx = idx;
            } else if (md2_idx == null) {
                md2_idx = idx;
                break;
            }
        }
    }
    try std.testing.expect(md1_idx != null and md2_idx != null);

    // 1. Open first markdown file and create a tied preview buffer to the side
    state.openFile(md1_idx.?);
    execute(state, .create_bound_markdown_preview_side, false, null);
    try std.testing.expectEqual(@as(usize, 2), state.paneCount());

    const bound_preview_idx = state.activeFileIndex().?;
    const bound_wf = state.workspaceFiles()[bound_preview_idx];
    try std.testing.expect(bound_wf.is_markdown_preview);
    try std.testing.expect(bound_wf.is_bound_markdown_preview);
    try std.testing.expectEqual(md1_idx.?, state.markdownPreviewSourceIndexForBuffer(bound_preview_idx));

    // 2. Open the regular dynamic *Markdown Preview* in pane 0
    state.focusPane(0);
    execute(state, .open_markdown_preview, false, null);
    const dyn_preview_idx = state.activeFileIndex().?;
    try std.testing.expect(dyn_preview_idx != bound_preview_idx);
    try std.testing.expect(!state.workspaceFiles()[dyn_preview_idx].is_bound_markdown_preview);
    try std.testing.expectEqual(md1_idx.?, state.markdownPreviewSourceIndexForBuffer(dyn_preview_idx));

    // 3. Switch to the second markdown file -> dynamic preview switches to md2, but bound preview stays tied to md1
    state.openFile(md2_idx.?);
    try std.testing.expectEqual(md2_idx.?, state.markdownPreviewSourceIndexForBuffer(dyn_preview_idx));
    try std.testing.expectEqual(md1_idx.?, state.markdownPreviewSourceIndexForBuffer(bound_preview_idx));

    // 4. Create a second bound preview tied to md2
    execute(state, .create_bound_markdown_preview, false, null);
    const bound_preview2_idx = state.activeFileIndex().?;
    try std.testing.expect(bound_preview2_idx != bound_preview_idx);
    try std.testing.expectEqual(md2_idx.?, state.markdownPreviewSourceIndexForBuffer(bound_preview2_idx));
    try std.testing.expectEqual(md1_idx.?, state.markdownPreviewSourceIndexForBuffer(bound_preview_idx));

    // 5. Verify clicking directly in the buffer content area (without clicking the bottom mode line)
    // switches the active pane and preserves it across both Pass.input and Pass.paint.
    const skia = @import("skia");
    const editor_pane_view = @import("views/editor_pane.zig");
    const surface = try skia.Surface.initRasterN32Premul(1280, 800);
    defer surface.deinit();

    // Open code buffer in Pane 0 and bound markdown preview in Pane 1
    state.openFileInPane(0, md1_idx.?);
    try std.testing.expectEqual(@as(usize, 0), state.activePaneIndex());

    const runFrame = struct {
        fn build(s: *EditorState) void {
            var wb_scope = s.ui_ctx.scopedState("vscode_workbench");
            defer wb_scope.end();
            editor_pane_view.build(s);
        }
    };

    // Initial layout frame to populate pane_rects
    state.ui_ctx.beginPass(.input, state.frame_arena.allocator(), surface.canvas(), skia.Rect.xywh(0, 0, 1280, 800), 0, 0, false, false, false);
    runFrame.build(state);
    state.ui_ctx.endPass();
    state.ui_ctx.beginPass(.paint, state.frame_arena.allocator(), surface.canvas(), skia.Rect.xywh(0, 0, 1280, 800), 0, 0, false, false, false);
    runFrame.build(state);
    state.ui_ctx.endPass();

    // Click inside Pane 1's buffer body (well above the 24pt bottom mode line)
    const p1_rect = state.pane_rects[1];
    const p1_click_x = (p1_rect.left + p1_rect.right) * 0.5;
    const p1_click_y = p1_rect.top + 80.0;
    state.ui_ctx.beginPass(.input, state.frame_arena.allocator(), surface.canvas(), skia.Rect.xywh(0, 0, 1280, 800), p1_click_x, p1_click_y, true, true, false);
    runFrame.build(state);
    state.ui_ctx.endPass();
    state.ui_ctx.beginPass(.paint, state.frame_arena.allocator(), surface.canvas(), skia.Rect.xywh(0, 0, 1280, 800), p1_click_x, p1_click_y, true, false, false);
    runFrame.build(state);
    state.ui_ctx.endPass();

    try std.testing.expectEqual(@as(usize, 1), state.activePaneIndex());
    try std.testing.expectEqual(EditorState.editorWidgetIdForPane(1), state.ui_ctx.focused_id);

    // Click back inside Pane 0's buffer body (well above the 24pt bottom mode line)
    const p0_rect = state.pane_rects[0];
    const p0_click_x = (p0_rect.left + p0_rect.right) * 0.5;
    const p0_click_y = p0_rect.top + 80.0;
    state.ui_ctx.beginPass(.input, state.frame_arena.allocator(), surface.canvas(), skia.Rect.xywh(0, 0, 1280, 800), p0_click_x, p0_click_y, true, true, false);
    runFrame.build(state);
    state.ui_ctx.endPass();
    state.ui_ctx.beginPass(.paint, state.frame_arena.allocator(), surface.canvas(), skia.Rect.xywh(0, 0, 1280, 800), p0_click_x, p0_click_y, true, false, false);
    runFrame.build(state);
    state.ui_ctx.endPass();

    try std.testing.expectEqual(@as(usize, 0), state.activePaneIndex());
    try std.testing.expectEqual(EditorState.editorWidgetIdForPane(0), state.ui_ctx.focused_id);
}

test "commands: matchesQuery, scoreQuery, and matchShortcutInTable integration" {
    try std.testing.expect(containsIgnoreCase("View: Toggle Word Wrap", "word wrap"));

    var save_cmd: ?CommandSpec = null;
    for (COMMANDS) |spec| {
        if (spec.id == .save_file) {
            save_cmd = spec;
            break;
        }
    }
    try std.testing.expect(save_cmd != null);
    try std.testing.expect(matchesQuery(save_cmd.?, "save active"));
    try std.testing.expect(matchesQuery(save_cmd.?, "cmd+s"));
    try std.testing.expect(!matchesQuery(save_cmd.?, "nonexistent_cmd_xyz"));
    try std.testing.expect(scoreQuery(save_cmd.?, "Save Active") != null);

    const idx_palette = ui.matchShortcutInTable(CommandSpec, &COMMANDS, .{ .key = .key_p, .cmd = true, .shift = true });
    try std.testing.expect(idx_palette != null);
    try std.testing.expectEqual(CommandId.command_palette, COMMANDS[idx_palette.?].id);

    const idx_quick_open = ui.matchShortcutInTable(CommandSpec, &COMMANDS, .{ .key = .key_p, .cmd = true });
    try std.testing.expect(idx_quick_open != null);
    try std.testing.expectEqual(CommandId.quick_open, COMMANDS[idx_quick_open.?].id);

    const idx_build = ui.matchShortcutInTable(CommandSpec, &COMMANDS, .{ .key = .key_b, .cmd = true, .shift = true });
    try std.testing.expect(idx_build != null);
    try std.testing.expectEqual(CommandId.run_build_task, COMMANDS[idx_build.?].id);
}

test "commands: vscode-like keybinding system and Command+Shift+B build execution" {
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

    // 1. Verify default Shift+Cmd+B is wired in keybindings manager
    const build_kb = state.keybindings.findBindingForCommand(.run_build_task);
    try std.testing.expect(build_kb != null);
    try std.testing.expectEqual(platform_mod.KeyCode.key_b, build_kb.?.chord.first.key);
    try std.testing.expect(build_kb.?.chord.first.cmd);
    try std.testing.expect(build_kb.?.chord.first.shift);

    try std.testing.expectEqualStrings("Shift+Cmd+B", state.shortcutDisplayForCommand(.run_build_task, ""));

    // 2. Dispatching Cmd+Shift+B key event triggers run_build_task
    var bottom_tab: u8 = 1; // start on Problems tab
    state.vterm.headless_loopback = true;
    state.ui_ctx.pass = .input;
    const build_ev = [_]platform_mod.KeyEvent{.{
        .key = .key_b,
        .cmd = true,
        .shift = true,
    }};
    state.ui_ctx.key_events = &build_ev;

    const dispatched = dispatchGlobalShortcuts(state, &bottom_tab);
    try std.testing.expect(dispatched);

    // Verify build task executed:
    // - Bottom panel / terminal is NOT brought up (runs quietly in background execution context)
    // - Bottom panel tab routed to Output Console (2)
    // - Tasks output channel filter activated
    // - Task runner started in its own isolated subprocess execution context
    // - Tasks output channel received initial task header
    // - Status notice announced build execution
    try std.testing.expect(!state.doc.show_bottom_panel);
    try std.testing.expectEqual(@as(u8, 2), state.doc.bottom_panel_tab);
    try std.testing.expectEqual(@as(u8, 2), bottom_tab);
    try std.testing.expectEqualStrings("Tasks", state.output_channel_filter.slice());
    try std.testing.expect(state.task_runner.is_running or state.task_runner.exit_code != null);
    try std.testing.expect(state.output_line_count > 0);
    var found_tasks_log = false;
    for (state.output_lines[0..state.output_line_count]) |line| {
        if (std.mem.eql(u8, line.channel.slice(), "Tasks")) {
            found_tasks_log = true;
            try std.testing.expect(std.mem.indexOf(u8, line.text.slice(), "zig build") != null);
        }
    }
    try std.testing.expect(found_tasks_log);
    try std.testing.expect(std.mem.indexOf(u8, state.status_notice.slice(), "Running task: zig build") != null);

    // 3. User keybinding override via JSON: remap build task to Cmd+B
    const user_override_json =
        \\[
        \\  {
        \\    "key": "cmd+b",
        \\    "command": "workbench.action.tasks.build"
        \\  }
        \\]
    ;
    _ = state.keybindings.loadFromJson(std.heap.c_allocator, user_override_json);
    try std.testing.expectEqualStrings("Cmd+B", state.shortcutDisplayForCommand(.run_build_task, ""));

    // Now Cmd+B executes build task instead of toggling sidebar
    state.ui_ctx.pass = .input;
    const custom_ev = [_]platform_mod.KeyEvent{.{
        .key = .key_b,
        .cmd = true,
        .shift = false,
    }};
    state.ui_ctx.key_events = &custom_ev;
    const dispatched_custom = dispatchGlobalShortcuts(state, &bottom_tab);
    try std.testing.expect(dispatched_custom);
}




