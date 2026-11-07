//! Main Editor Application (`libeditor_app.dylib`) featuring a VS Code-style Workbench:
//!   - Top Unified Titlebar + Command Palette Search Pill (`views/titlebar.zig`)
//!   - Far-left Activity Bar with vector icons (`views/activity_bar.zig`)
//!   - Scrollable Explorer & Outline Side Bar (`views/explorer.zig`)
//!   - Multi-tab Code Editor with Syntax Highlighting, Line Gutter, Minimap & Integrated Terminal (`views/editor_pane.zig`)
//!   - Bottom Status Bar (`views/status_bar.zig`)
//!
//! Run with: `zig build run` (and hot-reload live with `zig build app`).

const ui = @import("ui");
const platform = @import("platform");
const PlatformContext = platform.PlatformContext;

const state_mod = @import("state.zig");
const EditorState = state_mod.EditorState;
const STATE_VERSION = state_mod.STATE_VERSION;

const titlebar_view = @import("views/titlebar.zig");
const activity_bar_view = @import("views/activity_bar.zig");
const explorer_view = @import("views/explorer.zig");
const editor_pane_view = @import("views/editor_pane.zig");
const agent_panel_view = @import("views/agent_panel.zig");

comptime {
    ui.exportPlugin(EditorState, "doc", STATE_VERSION, buildWorkbench);
}

fn buildWorkbench(state: *EditorState, ctx: *PlatformContext) void {
    const uic = &state.ui_ctx;
    state.pollWorkspaceWatch();

    var scope = uic.scopedState("vscode_workbench");
    defer scope.end();

    const active_activity = &state.doc.active_sidebar_view;

    // 1. Unified macOS Titlebar with Command Palette Search Pill (36pt)
    _ = titlebar_view.build(state, ctx);

    if (state.context_menu.open and !uic.right_mouse_pressed) {
        uic.setBlockingOverlay(uic.root_rect);
    }

    // 2. Main Workbench Row (Activity Bar + Explorer Sidebar + Editor Groups, filling to bottom of window)
    const body_h = @max(100.0, ctx.height - titlebar_view.TitlebarHeight);
    {
        var body = uic.row(.{
            .h = .pixels(body_h),
            .gap = 0,
        });
        defer body.end();

        const act_out = activity_bar_view.build(state, active_activity);
        if (act_out.layout_changed) {
            uic.invalidateWindow();
        }

        const show_sidebar = uic.latch(bool, state.doc.show_sidebar);
        const sidebar_view = uic.latch(u8, active_activity.*);

        if (show_sidebar) {
            _ = explorer_view.build(state, sidebar_view);
            _ = uic.resizableSash("##sidebar_splitter", true, body_h, &state.doc.sidebar_width, 160.0, 420.0, 48.0, false);
        }

        editor_pane_view.build(state);

        if (state.doc.show_agent_panel) {
            _ = uic.resizableSash("##agent_panel_splitter", true, body_h, &state.doc.agent_panel_width, 260.0, 560.0, ctx.width, true);
            agent_panel_view.build(state, body_h);
        }
    }

    // 3. Floating Command & File Palette Overlay (`Cmd+P` / `Shift+Cmd+P`), Open Workspace (`Cmd+O`), Save As / New Folder Prompt, or Right-Click Context Menu
    if (state.doc.show_command_palette) {
        const palette_rect = ui.Context.topCenteredOverlayRect(
            ctx.width,
            titlebar_view.TitlebarHeight + 2.0,
            320.0,
            560.0,
            0.58,
            268.0,
        );
        editor_pane_view.buildCommandPaletteOverlay(state, palette_rect);
    } else if (state.show_open_workspace_prompt) {
        const open_ws_rect = ui.Context.topCenteredOverlayRect(
            ctx.width,
            titlebar_view.TitlebarHeight + 12.0,
            480.0,
            620.0,
            0.62,
            320.0,
        );
        editor_pane_view.buildOpenWorkspacePromptOverlay(state, open_ws_rect);
    } else if (state.show_save_as_prompt or state.show_new_folder_prompt) {
        const save_as_rect = ui.Context.topCenteredOverlayRect(
            ctx.width,
            titlebar_view.TitlebarHeight + 18.0,
            380.0,
            480.0,
            0.50,
            118.0,
        );
        if (state.show_save_as_prompt) {
            editor_pane_view.buildSaveAsPromptOverlay(state, save_as_rect);
        } else {
            editor_pane_view.buildNewFolderPromptOverlay(state, save_as_rect);
        }
    } else if (state.context_menu.open) {
        editor_pane_view.buildContextMenuOverlay(state);
    }
}

test {
    _ = state_mod;
    _ = @import("agy_client.zig");
    _ = @import("supercomplete.zig");
    _ = @import("analysis.zig");
    _ = @import("git_client.zig");
    _ = @import("commands.zig");
    _ = @import("plugin_manager.zig");
}

test "Workbench Views: full 2-phase Pass.input -> Pass.paint layout determinism across all panels and overlays" {
    const std = @import("std");
    const skia = @import("skia");

    const surface = try skia.Surface.initRasterN32Premul(1280, 800);
    defer surface.deinit();

    var store = platform.StateStore.init(std.testing.allocator);
    defer store.deinit();
    var snap = platform.SnapshotBuffer.init(std.testing.allocator);
    defer snap.deinit();
    var pctx = platform.PlatformContext{ .width = 1280.0, .height = 800.0 };
    pctx.bindHostStores(&store, &snap);
    pctx.canvas = surface.canvas().ptr;

    const state = try std.testing.allocator.create(EditorState);
    defer std.testing.allocator.destroy(state);
    state.* = .{
        .frame_arena = std.heap.ArenaAllocator.init(std.testing.allocator),
        .fonts = undefined,
        .ui_ctx = undefined,
    };
    state.initResources(&pctx);
    defer state.deinitResources();

    // Enable sidebar, bottom panel, agent panel, minimap, and a 2-pane split
    state.doc.show_sidebar = true;
    state.doc.show_bottom_panel = true;
    state.doc.show_agent_panel = true;
    state.doc.show_minimap = true;
    state.openFile(0);
    state.splitPaneHorizontal(0);
    state.openFile(1);

    // Frame 1: Full redraw with all panels open -> runs Pass.input + Pass.paint
    pctx.force_full_redraw = true;
    const painted_1 = ui.runTwoPhaseFrame(&state.ui_ctx, &pctx, &state.frame_arena, false, state, buildWorkbench);
    try std.testing.expect(painted_1);

    // Frame 2: Open Command Palette overlay and verify 2-phase Pass.input + Pass.paint
    state.doc.show_command_palette = true;
    pctx.force_full_redraw = true;
    const painted_2 = ui.runTwoPhaseFrame(&state.ui_ctx, &pctx, &state.frame_arena, false, state, buildWorkbench);
    try std.testing.expect(painted_2);
    try std.testing.expectEqual(state.ui_ctx.last_input_rect_count, state.ui_ctx.last_paint_rect_count);

    // Frame 3: Close Command Palette, open Right-Click Context Menus across all 13 targets, and verify 2-phase determinism
    state.doc.show_command_palette = false;
    state.context_menu_folder.set("src/ui");
    state.context_menu_label.set("buildWorkbench");
    state.context_menu_line = 42;
    const targets = [_]state_mod.ContextMenuTarget{
        .code_editor,
        .pdf_viewer,
        .terminal,
        .explorer_file,
        .explorer_folder,
        .outline_symbol,
        .search_match,
        .git_change,
        .git_commit,
        .plugin_item,
        .problem_item,
        .agent_message,
        .titlebar_pill,
        .pane_modeline,
        .titlebar_file_menu,
        .titlebar_edit_menu,
        .titlebar_view_menu,
    };
    for (targets) |t| {
        state.openContextMenu(t, 0, 0, t == .terminal);
        pctx.force_full_redraw = true;
        const painted_ctx = ui.runTwoPhaseFrame(&state.ui_ctx, &pctx, &state.frame_arena, false, state, buildWorkbench);
        try std.testing.expect(painted_ctx);
        try std.testing.expectEqual(state.ui_ctx.last_input_rect_count, state.ui_ctx.last_paint_rect_count);
    }

    // Exercise in-app Open File / Workspace Folder Picker modal overlay (`show_open_workspace_prompt`)
    state.context_menu.open = false;
    state.show_open_workspace_prompt = true;
    state.open_workspace_path.set(".");
    pctx.force_full_redraw = true;
    try std.testing.expect(ui.runTwoPhaseFrame(&state.ui_ctx, &pctx, &state.frame_arena, false, state, buildWorkbench));
    try std.testing.expectEqual(state.ui_ctx.last_input_rect_count, state.ui_ctx.last_paint_rect_count);
    state.show_open_workspace_prompt = false;

    // Exercise *Waveform Preview* split pane and dedicated plugin Activity Bar sidebars
    state.context_menu.open = false;
    state.doc.show_sidebar = true;
    state.doc.active_sidebar_view = 2; // Simple Plugins browser panel
    state.openWaveformPreviewBuffer(true);
    pctx.force_full_redraw = true;
    try std.testing.expect(ui.runTwoPhaseFrame(&state.ui_ctx, &pctx, &state.frame_arena, false, state, buildWorkbench));
    try std.testing.expectEqual(state.ui_ctx.last_input_rect_count, state.ui_ctx.last_paint_rect_count);

    for (0..state.plugins.plugin_count) |p_idx| {
        if (state.plugins.plugins[p_idx].sidebar_icon != .none) {
            state.doc.active_sidebar_view = @intCast(3 + p_idx);
            pctx.force_full_redraw = true;
            try std.testing.expect(ui.runTwoPhaseFrame(&state.ui_ctx, &pctx, &state.frame_arena, false, state, buildWorkbench));
            try std.testing.expectEqual(state.ui_ctx.last_input_rect_count, state.ui_ctx.last_paint_rect_count);
        }
    }

    // Exercise *Git Diff* in Unified and Split modes alongside the Git Source Control & Lens plugin
    for (0..state.plugins.plugin_count) |p_idx| {
        if (state.plugins.plugins[p_idx].sidebar_icon == .git) {
            state.doc.active_sidebar_view = @intCast(3 + p_idx);
            break;
        }
    }
    state.doc.show_agent_panel = false;
    state.doc.show_bottom_panel = false;
    state.doc.split_tree = .{};
    state.doc.panes[0] = .{};
    state.openFile(0);
    state.openGitDiffForFile("src/app/state.zig", "", false, true);
    state.git_diff_views[1].mode = .unified;
    pctx.force_full_redraw = true;
    try std.testing.expect(ui.runTwoPhaseFrame(&state.ui_ctx, &pctx, &state.frame_arena, false, state, buildWorkbench));
    try std.testing.expectEqual(state.ui_ctx.last_input_rect_count, state.ui_ctx.last_paint_rect_count);

    // Exercise full-pane Split (Side-by-Side) diff mode
    state.doc.split_tree = .{};
    state.doc.panes[0] = .{};
    state.openGitDiffForFile("src/app/state.zig", "", false, false);
    state.git_diff_views[0].mode = .split;
    pctx.force_full_redraw = true;
    try std.testing.expect(ui.runTwoPhaseFrame(&state.ui_ctx, &pctx, &state.frame_arena, false, state, buildWorkbench));
    try std.testing.expectEqual(state.ui_ctx.last_input_rect_count, state.ui_ctx.last_paint_rect_count);

    // Exercise Bottom Panel Output Log tab (clean editor output without plugin views)
    state.doc.show_bottom_panel = true;
    state.appendOutput("Test", "Sample output line 1");
    state.appendOutput("Build", "Compilation successful");
    const bottom_tab = state.ui_ctx.useState(u8, "bottom_panel_tab", 0);
    bottom_tab.* = 2; // Select OUTPUT tab
    pctx.force_full_redraw = true;
    try std.testing.expect(ui.runTwoPhaseFrame(&state.ui_ctx, &pctx, &state.frame_arena, false, state, buildWorkbench));
    try std.testing.expectEqual(state.ui_ctx.last_input_rect_count, state.ui_ctx.last_paint_rect_count);

    // Exercise *PDF Preview* and PDF Reader plugin across Page, Split, and Dark Paper modes
    _ = state.plugins.loadOrReloadDylib(state, "zig-out/plugins/libpdf_reader.dylib");
    for (0..state.plugins.plugin_count) |p_idx| {
        if (state.plugins.plugins[p_idx].sidebar_icon == .pdf) {
            state.doc.active_sidebar_view = @intCast(3 + p_idx);
            break;
        }
    }

    state.doc.show_sidebar = true;
    state.doc.show_bottom_panel = false;
    state.doc.show_agent_panel = false;
    state.doc.split_tree = .{};
    state.doc.panes[0] = .{};
    state.openPdfPreviewBuffer(false);
    state.pdf_views[0].current_page = 0;
    state.pdf_views[0].zoom = 1.05;
    state.pdf_views[0].invert_paper = false;
    state.pdf_views[0].show_outline = true;
    pctx.force_full_redraw = true;
    try std.testing.expect(ui.runTwoPhaseFrame(&state.ui_ctx, &pctx, &state.frame_arena, false, state, buildWorkbench));
    try std.testing.expectEqual(state.ui_ctx.last_input_rect_count, state.ui_ctx.last_paint_rect_count);

    state.openPdfPreviewBuffer(true);
    state.pdf_views[1].current_page = 1;
    state.pdf_views[1].zoom = 1.0;
    state.pdf_views[1].invert_paper = true;
    state.pdf_views[1].show_outline = false;
    state.openFindBar();
    state.find_query.set("UART");
    pctx.force_full_redraw = true;
    try std.testing.expect(ui.runTwoPhaseFrame(&state.ui_ctx, &pctx, &state.frame_arena, false, state, buildWorkbench));
    try std.testing.expectEqual(state.ui_ctx.last_input_rect_count, state.ui_ctx.last_paint_rect_count);
    state.doc.show_find_bar = false;

    // Exercise Agent Panel with an active `CORTEX_STEP_TYPE_ASK_QUESTION` card (single + multi-select + write-in)
    state.doc.show_agent_panel = true;
    const ask_traj =
        \\{"status":"CASCADE_RUN_STATUS_RUNNING","trajectory":{"trajectoryId":"traj-1","steps":[
        \\  {"type":"CORTEX_STEP_TYPE_USER_INPUT","status":"CORTEX_STEP_STATUS_DONE","userInput":{"userResponse":"Help me configure the build"}},
        \\  {"type":"CORTEX_STEP_TYPE_ASK_QUESTION","status":"CORTEX_STEP_STATUS_WAITING",
        \\   "askQuestion":{"questions":[
        \\     {"question":"Which optimization mode should we target?","isMultiSelect":false,"options":[
        \\       {"id":"1","text":"(Recommended) ReleaseSafe"},
        \\       {"id":"2","text":"ReleaseFast"}
        \\     ]},
        \\     {"question":"Which artifacts should we build?","isMultiSelect":true,"options":[
        \\       {"id":"1","text":"Host executable (lightning)"},
        \\       {"id":"2","text":"Editor dylib (libeditor_app.dylib)"}
        \\     ]}
        \\   ]}}
        \\]}}
    ;
    try std.testing.expect(state.agy.parseTrajectoryResponse(ask_traj));
    try std.testing.expect(state.agy.pending_question.active);
    pctx.force_full_redraw = true;
    try std.testing.expect(ui.runTwoPhaseFrame(&state.ui_ctx, &pctx, &state.frame_arena, false, state, buildWorkbench));
    try std.testing.expectEqual(state.ui_ctx.last_input_rect_count, state.ui_ctx.last_paint_rect_count);
}

test "Outline View: rendering Zig files in Explorer Outline and @Symbol palette without corruption" {
    const std = @import("std");
    const skia = @import("skia");

    const scale: f32 = 2.0;
    const logical_w: f32 = 1280.0;
    const logical_h: f32 = 800.0;
    const surface = try skia.Surface.initRasterN32Premul(
        @intFromFloat(logical_w * scale),
        @intFromFloat(logical_h * scale),
    );
    defer surface.deinit();

    const font_mgr = try skia.FontMgr.initDefault();
    defer font_mgr.deinit();

    var store = platform.StateStore.init(std.testing.allocator);
    defer store.deinit();
    var snap = platform.SnapshotBuffer.init(std.testing.allocator);
    defer snap.deinit();
    var pctx = platform.PlatformContext{
        .font_mgr = font_mgr.ptr,
        .width = logical_w,
        .height = logical_h,
        .dpi_scale = scale,
    };
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

    // Open `src/app/analysis.zig` (or first `.zig` file in workspace)
    var zig_idx: usize = 0;
    for (state.workspaceFiles(), 0..) |wf, idx| {
        if (std.mem.eql(u8, wf.path, "src/app/analysis.zig")) {
            zig_idx = idx;
            break;
        } else if (wf.language == .zig) {
            zig_idx = idx;
        }
    }
    state.openFile(zig_idx);
    state.doc.show_sidebar = true;
    state.doc.active_sidebar_view = 0;
    state.doc.sec_open_editors = true;
    state.doc.sec_files = false; // Collapse workspace tree so OUTLINE is prominently visible
    state.doc.sec_outline = true;
    state.doc.outline_group_fn = true;
    state.doc.outline_group_types = true;

    const canvas = surface.canvas();
    _ = canvas.save();
    canvas.scale(scale, scale);
    pctx.canvas = canvas.ptr;
    pctx.force_full_redraw = true;
    const painted = ui.runTwoPhaseFrame(&state.ui_ctx, &pctx, &state.frame_arena, false, state, buildWorkbench);
    canvas.restore();
    try std.testing.expect(painted);
    try std.testing.expectEqual(state.ui_ctx.last_input_rect_count, state.ui_ctx.last_paint_rect_count);

    // Verify all cached symbols after full UI pass are valid ASCII identifiers and non-corrupted
    const syms = state.symbolsForFile(zig_idx);
    try std.testing.expect(syms.len > 0);
    for (syms) |s| {
        try std.testing.expect(s.name.len > 0);
        try std.testing.expect(std.mem.eql(u8, s.kind, "fn") or std.mem.eql(u8, s.kind, "st") or std.mem.eql(u8, s.kind, "ct"));
        for (s.name) |ch| {
            try std.testing.expect(std.ascii.isAlphanumeric(ch) or ch == '_');
        }
    }

    // Also render `src/app/views/explorer.zig` with `@` Go-to-Symbol Command Palette open
    for (state.workspaceFiles(), 0..) |wf, idx| {
        if (std.mem.eql(u8, wf.path, "src/app/views/explorer.zig")) {
            zig_idx = idx;
            break;
        }
    }
    state.openFile(zig_idx);
    state.doc.show_command_palette = true;
    state.palette_query.set("@");
    _ = canvas.save();
    canvas.scale(scale, scale);
    pctx.canvas = canvas.ptr;
    pctx.force_full_redraw = true;
    const painted_exp = ui.runTwoPhaseFrame(&state.ui_ctx, &pctx, &state.frame_arena, false, state, buildWorkbench);
    canvas.restore();
    try std.testing.expect(painted_exp);
    try std.testing.expectEqual(state.ui_ctx.last_input_rect_count, state.ui_ctx.last_paint_rect_count);

    const exp_syms = state.symbolsForFile(zig_idx);
    try std.testing.expect(exp_syms.len > 0);
    for (exp_syms) |s| {
        try std.testing.expect(s.name.len > 0);
        try std.testing.expect(std.mem.eql(u8, s.kind, "fn") or std.mem.eql(u8, s.kind, "st") or std.mem.eql(u8, s.kind, "ct"));
        for (s.name) |ch| {
            try std.testing.expect(std.ascii.isAlphanumeric(ch) or ch == '_');
        }
    }
}

test "Workbench Monkey-Tester: randomized command dispatch, split-pane topology invariants, and Pass.input == Pass.paint rect-count determinism" {
    const std = @import("std");
    const skia = @import("skia");
    const commands = @import("commands.zig");

    const surface = try skia.Surface.initRasterN32Premul(1280, 800);
    defer surface.deinit();

    var store = platform.StateStore.init(std.testing.allocator);
    defer store.deinit();
    var snap = platform.SnapshotBuffer.init(std.testing.allocator);
    defer snap.deinit();
    var pctx = platform.PlatformContext{ .width = 1280.0, .height = 800.0 };
    pctx.bindHostStores(&store, &snap);
    pctx.canvas = surface.canvas().ptr;

    const state = try std.testing.allocator.create(EditorState);
    defer std.testing.allocator.destroy(state);
    state.* = .{
        .frame_arena = std.heap.ArenaAllocator.init(std.testing.allocator),
        .fonts = undefined,
        .ui_ctx = undefined,
    };
    state.initResources(&pctx);
    defer state.deinitResources();

    const safe_cmds = [_]commands.CommandId{
        .command_palette,
        .quick_open,
        .agy_toggle_panel,
        .agy_cycle_mode,
        .agy_cycle_effort,
        .new_agent_buffer,
        .new_agent_side,
        .open_markdown_preview,
        .open_markdown_preview_side,
        .create_bound_markdown_preview,
        .create_bound_markdown_preview_side,
        .open_git_diff_preview,
        .open_git_diff_preview_side,
        .open_waveform_preview,
        .open_waveform_preview_side,
        .split_right,
        .split_down,
        .move_tab_next_split,
        .close_active_tab,
        .close_active_split,
        .focus_group_1,
        .focus_group_2,
        .toggle_sidebar,
        .toggle_terminal_panel,
        .toggle_waveform_panel,
        .toggle_minimap,
        .toggle_dirty_overlay,
        .open_scratch_buffer,
        .find_in_workspace,
        .find_in_file,
        .goto_symbol_mode,
        .goto_line_mode,
    };

    var prng = std.Random.DefaultPrng.init(0x7788_99AA_BBCC_DDEE);
    const rand = prng.random();

    for (0..60) |_| {
        const cmd = safe_cmds[rand.uintLessThan(usize, safe_cmds.len)];
        commands.execute(state, cmd, rand.boolean(), null);

        // Occasionally open a random workspace file
        if (rand.boolean() and state.fileCount() > 0) {
            state.openFile(rand.uintLessThan(usize, state.fileCount()));
        }

        // Invariant 1: SplitTree pane_count always within [1, MaxEditorPanes]
        try std.testing.expect(state.paneCount() >= 1);
        try std.testing.expect(state.paneCount() <= state_mod.MaxEditorPanes);

        // Invariant 2: Steady-state 2-phase frame consumes the exact same number of layout rects in Pass.input and Pass.paint
        pctx.force_full_redraw = true;
        const painted = ui.runTwoPhaseFrame(&state.ui_ctx, &pctx, &state.frame_arena, false, state, buildWorkbench);
        try std.testing.expect(painted);
        try std.testing.expectEqual(state.ui_ctx.last_input_rect_count, state.ui_ctx.last_paint_rect_count);
    }
}

test "Multiple Agent Buffers (*agent-N*): shared agy hub state, independent sessions, and 2-phase rect determinism" {
    const std = @import("std");
    const skia = @import("skia");
    const commands = @import("commands.zig");

    const surface = try skia.Surface.initRasterN32Premul(1280, 800);
    defer surface.deinit();

    var store = platform.StateStore.init(std.testing.allocator);
    defer store.deinit();
    var snap = platform.SnapshotBuffer.init(std.testing.allocator);
    defer snap.deinit();
    var pctx = platform.PlatformContext{ .width = 1280.0, .height = 800.0 };
    pctx.bindHostStores(&store, &snap);
    pctx.canvas = surface.canvas().ptr;

    const state = try std.testing.allocator.create(EditorState);
    defer std.testing.allocator.destroy(state);
    state.* = .{
        .frame_arena = std.heap.ArenaAllocator.init(std.testing.allocator),
        .fonts = undefined,
        .ui_ctx = undefined,
    };
    state.initResources(&pctx);
    defer state.deinitResources();

    // Pre-populate simulated Antigravity Hub credentials and model/conversation catalogs on `state.agy`
    state.agy.ls_port = 52431;
    state.agy.alt_port = 52432;
    const tok = "shared-hub-csrf-token-1234";
    @memcpy(state.agy.csrf_buf[0..tok.len], tok);
    state.agy.csrf_len = tok.len;
    state.agy.models_attempted = true;
    state.agy.models_fetched = true;
    state.agy.conversations_attempted = true;
    state.agy.conversations_fetched = true;

    // 1. Create `*agent-1*` in the active pane and `*agent-2*` split to the side
    commands.execute(state, .new_agent_buffer, false, null);
    try std.testing.expect(state.agent_slot_used[0]);
    const agt1_idx = state.activeFileIndex().?;
    try std.testing.expect(state.workspaceFiles()[agt1_idx].is_agent);
    try std.testing.expectEqual(@as(u8, 0), state.workspaceFiles()[agt1_idx].agent_slot);
    try std.testing.expectEqualStrings("*agent-1*", state.workspaceFiles()[agt1_idx].name);

    commands.execute(state, .new_agent_side, false, null);
    try std.testing.expect(state.agent_slot_used[1]);
    try std.testing.expectEqual(@as(usize, 2), state.paneCount());
    const agt2_idx = state.activeFileIndex().?;
    try std.testing.expect(state.workspaceFiles()[agt2_idx].is_agent);
    try std.testing.expectEqual(@as(u8, 1), state.workspaceFiles()[agt2_idx].agent_slot);
    try std.testing.expectEqualStrings("*agent-2*", state.workspaceFiles()[agt2_idx].name);

    // 2. Verify both `*agent-1*` and `*agent-2*` share the exact same `agy` process hub credentials
    try std.testing.expectEqual(@as(u16, 52431), state.agent_sessions[0].ls_port);
    try std.testing.expectEqual(@as(u16, 52431), state.agent_sessions[1].ls_port);
    try std.testing.expectEqualStrings(tok, state.agent_sessions[0].csrfToken());
    try std.testing.expectEqualStrings(tok, state.agent_sessions[1].csrfToken());

    // 3. Verify each agent buffer maintains independent prompt text, mode, and conversation state
    state.agent_prompts[0].set("Prompt for agent 1");
    state.agent_prompts[1].set("Prompt for agent 2");
    state.agent_sessions[0].mode = .plan;
    state.agent_sessions[1].mode = .accept_edits;
    try std.testing.expectEqualStrings("Prompt for agent 2", state.activeAgyPrompt().slice());
    try std.testing.expectEqual(state.agent_sessions[1].mode, state.activeAgySession().mode);

    // 4. Render full workbench with both `*agent-1*`, `*agent-2*`, and the right-side Agent Panel visible
    state.doc.show_agent_panel = true;
    pctx.force_full_redraw = true;
    const painted = ui.runTwoPhaseFrame(&state.ui_ctx, &pctx, &state.frame_arena, false, state, buildWorkbench);
    try std.testing.expect(painted);
    try std.testing.expectEqual(state.ui_ctx.last_input_rect_count, state.ui_ctx.last_paint_rect_count);

    // 5. Killing `*agent-2*` releases its agent slot cleanly while preserving `*agent-1*`
    state.killBuffer(agt2_idx);
    try std.testing.expect(!state.agent_slot_used[1]);
    try std.testing.expect(state.agent_slot_used[0]);

    // 6. Populate 40 chat entries in `state.agy` while `is_running_turn = true` and verify:
    //    - Offscreen entries are virtualized (culled to 1 rect each) after initial height caching
    //    - `Pass.input` and `Pass.paint` consume the exact same number of layout rects (`last_input_rect_count == last_paint_rect_count`)
    //    - Streaming a new token into `state.agy` only marks the Agent Panel rect dirty (not the full 1280x800 window)
    state.agy.is_running_turn = true;
    for (0..20) |turn_i| {
        var u_buf: [64]u8 = undefined;
        const u_msg = try std.fmt.bufPrint(&u_buf, "User prompt #{d} with `inline code`", .{turn_i});
        state.agy.pushChatEntry(.user_prompt, u_msg, "");

        var a_buf: [256]u8 = undefined;
        const a_msg = try std.fmt.bufPrint(
            &a_buf,
            "### Step {d}\nHere is a multi-line explanation for step {d}.\n- Bullet item A\n- Bullet item B\n```zig\nconst x: usize = {d};\n```",
            .{ turn_i, turn_i, turn_i },
        );
        state.agy.pushChatEntry(.assistant_markdown, a_msg, "");
    }
    state.agy.scroll_to_bottom_frames = 2;
    state.agy.ui_generation +%= 1;

    // Frame A & B: initial measurement, scrollbar gutter stabilization, & auto-scroll to exact bottom
    _ = ui.runTwoPhaseFrame(&state.ui_ctx, &pctx, &state.frame_arena, false, state, buildWorkbench);
    try std.testing.expectEqual(state.ui_ctx.last_input_rect_count, state.ui_ctx.last_paint_rect_count);
    const initial_rects = state.ui_ctx.last_input_rect_count;

    _ = ui.runTwoPhaseFrame(&state.ui_ctx, &pctx, &state.frame_arena, false, state, buildWorkbench);
    try std.testing.expectEqual(state.ui_ctx.last_input_rect_count, state.ui_ctx.last_paint_rect_count);

    // Frame C: no changes while running -> offscreen historical entries are culled in Pass.input AND Pass.paint is skipped completely
    const idle_painted = ui.runTwoPhaseFrame(&state.ui_ctx, &pctx, &state.frame_arena, false, state, buildWorkbench);
    try std.testing.expect(!idle_painted);
    const culled_rects = state.ui_ctx.last_input_rect_count;
    try std.testing.expect(culled_rects < initial_rects);

    // Frame D & E: stream a new assistant message -> only the Agent Panel region is damaged and scroll_y auto-advances
    state.agy.pushChatEntry(.assistant_markdown, "Streaming new token chunk...\nSecond line of streamed chunk.", "");
    state.agy.scroll_to_bottom_frames = 2;
    state.agy.ui_generation +%= 1;
    const stream_painted = ui.runTwoPhaseFrame(&state.ui_ctx, &pctx, &state.frame_arena, false, state, buildWorkbench);
    try std.testing.expect(stream_painted);
    try std.testing.expectEqual(state.ui_ctx.last_input_rect_count, state.ui_ctx.last_paint_rect_count);
    try std.testing.expect(state.ui_ctx.last_input_rect_count < initial_rects);
    const total_win_area = pctx.width * pctx.height;
    try std.testing.expect(state.ui_ctx.dirtyArea() < total_win_area * 0.45);

    const follow_painted = ui.runTwoPhaseFrame(&state.ui_ctx, &pctx, &state.frame_arena, false, state, buildWorkbench);
    try std.testing.expect(follow_painted);
    try std.testing.expectEqual(state.ui_ctx.last_input_rect_count, state.ui_ctx.last_paint_rect_count);

    // 7. Paste a clipboard screenshot via Cmd+V into the active `*agent-1*` buffer and verify:
    //    - Pending attachment is added to `state.agent_sessions[0]`
    //    - Two-phase layout determinism (`last_input_rect_count == last_paint_rect_count`) holds with the pending attachment strip visible
    //    - Sending an image-only prompt works and renders the user_prompt attachment thumbnail in the transcript
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
    platform.setTestClipboardImage(.{
        .data = &sample_png,
        .mime_type = "image/png",
        .filename = "clipboard_screenshot.png",
        .source_path = "",
    });
    defer platform.setTestClipboardImage(null);

    state.doc.split_tree.active_pane = 0;
    pctx.key_events[0] = .{
        .key = .key_v,
        .cmd = true,
    };
    pctx.key_event_count = 1;
    const paste_painted = ui.runTwoPhaseFrame(&state.ui_ctx, &pctx, &state.frame_arena, false, state, buildWorkbench);
    pctx.key_event_count = 0;
    try std.testing.expect(paste_painted);
    try std.testing.expectEqual(state.ui_ctx.last_input_rect_count, state.ui_ctx.last_paint_rect_count);
    try std.testing.expectEqual(@as(usize, 1), state.agent_sessions[0].pendingAttachments().len);

    // Send the pasted image attachment and verify two-phase layout determinism on the sent transcript bubble
    state.agent_prompts[0].clear();
    state.sendAgyPromptFromSession(&state.agent_sessions[0], &state.agent_prompts[0], 0);
    try std.testing.expectEqual(@as(usize, 0), state.agent_sessions[0].pendingAttachments().len);
    try std.testing.expect(state.agent_sessions[0].chatEntries().len >= 1);

    const sent_painted = ui.runTwoPhaseFrame(&state.ui_ctx, &pctx, &state.frame_arena, false, state, buildWorkbench);
    try std.testing.expect(sent_painted);
    try std.testing.expectEqual(state.ui_ctx.last_input_rect_count, state.ui_ctx.last_paint_rect_count);

    // 8. Large Workspace Explorer Tree Virtualization & Watch Signature Stability:
    //    - Register 300 nested files across 15 subdirectories and expand all folders
    //    - Verify `state.cached_tree_nodes_list` caches all 300+ visible nodes in O(N)
    //    - Verify viewport virtualization keeps `last_input_rect_count` strictly bounded (< 220 rects)
    //      and preserves `last_input_rect_count == last_paint_rect_count` across scrolling and folder toggles
    //    - Verify toggling folder expansion keeps `state.last_watch_sig == state.computeWorkspaceWatchSignature()`
    state.has_opened_workspace = true;
    for (0..15) |dir_i| {
        for (0..20) |file_i| {
            var path_buf: [128]u8 = undefined;
            const rel_path = try std.fmt.bufPrint(&path_buf, "subsys/mod_{d:0>2}/driver_{d:0>2}.c", .{ dir_i, file_i });
            state.registerDiscoveredWorkspaceFile(rel_path);
        }
    }
    state.setAllFolderNodesExpanded(true);
    try std.testing.expectEqual(state.last_watch_sig, state.computeWorkspaceWatchSignature());

    state.doc.show_sidebar = true;
    state.doc.active_sidebar_view = 0;
    state.doc.sec_files = true;

    _ = ui.runTwoPhaseFrame(&state.ui_ctx, &pctx, &state.frame_arena, true, state, buildWorkbench);
    try std.testing.expectEqual(state.ui_ctx.last_input_rect_count, state.ui_ctx.last_paint_rect_count);
    try std.testing.expect(state.cached_tree_nodes_list.items.len >= 315);
    // Even with 315+ expanded tree rows, virtualized Explorer only lays out visible rows + overscan
    try std.testing.expect(state.ui_ctx.last_input_rect_count < 220);

    // Scroll the Explorer sidebar down and verify two-phase layout rect count determinism holds
    pctx.mouse_x = 120.0;
    pctx.mouse_y = 300.0;
    pctx.scroll_dy = -420.0;
    const tree_scroll_painted = ui.runTwoPhaseFrame(&state.ui_ctx, &pctx, &state.frame_arena, false, state, buildWorkbench);
    pctx.scroll_dy = 0.0;
    try std.testing.expect(tree_scroll_painted);
    try std.testing.expectEqual(state.ui_ctx.last_input_rect_count, state.ui_ctx.last_paint_rect_count);
    try std.testing.expect(state.ui_ctx.last_input_rect_count < 220);

    // Collapse a folder and verify watch signature stays synchronized without false-positive disk rescans
    state.setFolderExpanded("subsys/mod_00", false);
    try std.testing.expectEqual(state.last_watch_sig, state.computeWorkspaceWatchSignature());
    const collapse_painted = ui.runTwoPhaseFrame(&state.ui_ctx, &pctx, &state.frame_arena, false, state, buildWorkbench);
    try std.testing.expect(collapse_painted);
    try std.testing.expectEqual(state.ui_ctx.last_input_rect_count, state.ui_ctx.last_paint_rect_count);

    // 9. Explorer Outline Symbol Virtualization & Zero-Damage Idle Verification:
    //    - Verify OUTLINE section handles switching between a buffer with many symbols and a Markdown buffer
    //      with fewer headings without out-of-bounds slice panics or Pass.input/Pass.paint rect mismatch
    //    - Verify an idle frame with Explorer + CodeEditor + Agent Panel open produces 0% damage (dirty_rect == null)
    state.doc.sec_outline = true;
    state.doc.show_agent_panel = true;
    state.openFile(0);
    state.openFile(1);
    state.doc.panes[0].active_tab = 0;
    _ = ui.runTwoPhaseFrame(&state.ui_ctx, &pctx, &state.frame_arena, true, state, buildWorkbench);
    try std.testing.expectEqual(state.ui_ctx.last_input_rect_count, state.ui_ctx.last_paint_rect_count);

    // Switch active tab to Markdown buffer and verify two-phase determinism
    state.doc.panes[0].active_tab = 1;
    _ = ui.runTwoPhaseFrame(&state.ui_ctx, &pctx, &state.frame_arena, true, state, buildWorkbench);
    try std.testing.expectEqual(state.ui_ctx.last_input_rect_count, state.ui_ctx.last_paint_rect_count);

    // Settle scroll heights across one normal frame, then verify the next idle frame skips Pass.paint (dirty_rect == null)
    pctx.mouse_x = -1.0;
    pctx.mouse_y = -1.0;
    pctx.force_full_redraw = false;
    _ = ui.runTwoPhaseFrame(&state.ui_ctx, &pctx, &state.frame_arena, false, state, buildWorkbench);
    const idle_painted_2 = ui.runTwoPhaseFrame(&state.ui_ctx, &pctx, &state.frame_arena, false, state, buildWorkbench);
    try std.testing.expect(!idle_painted_2);
    try std.testing.expect(state.ui_ctx.dirty_rect == null);
}
