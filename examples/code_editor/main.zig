//! Dedicated Text & Code Editor Component Showcase (`libexample_code_editor.dylib`).
//! Demonstrates declarative UI composition (`uic.titlebar`, `uic.row`, `uic.scrollPanel`,
//! `uic.sectionHeader`, `uic.btn`, `uic.tab`, `uic.checkbox`, `uic.sliderFloat`, `uic.codeEditor`)
//! alongside `ui.FontSet` and `ui.runTwoPhaseFrame`.
//!
//! Run with: `zig build run-code-editor` (and hot-reload live with `zig build example-code-editor`).

const std = @import("std");
const ui = @import("ui");
const platform = @import("platform");
const PlatformContext = platform.PlatformContext;

const STATE_VERSION: u64 = 0x2026_1019_CE02;

const EditorDemoConfig = struct {
    show_line_numbers: bool = true,
    show_indent_guides: bool = true,
    show_minimap: bool = false,
    show_status_bar: bool = true,
    syntax_highlight: bool = true,
    auto_close_pairs: bool = true,
    read_only: bool = false,
    show_dirty_overlay: bool = false,
    line_height: f32 = 21.0,
};

const FileTemplate = struct {
    name: []const u8,
    language: ui.CodeLanguage,
    initial_source: []const u8,
};

const FILE_TEMPLATES = [_]FileTemplate{
    .{
        .name = "shader_pipeline.zig",
        .language = .zig,
        .initial_source =
        \\//! Hardware-Accelerated Skia + Metal Compute Pipeline.
        \\//! Click anywhere to edit, drag to select, or press Cmd+/ to toggle comments!
        \\
        \\const std = @import("std");
        \\const skia = @import("skia");
        \\const ui = @import("ui");
        \\
        \\pub const PipelineConfig = struct {
        \\    sample_count: u32 = 4,
        \\    vsync_enabled: bool = true,
        \\    target_fps: f32 = 120.0,
        \\};
        \\
        \\pub fn renderFrame(uic: *ui.Context, cfg: PipelineConfig) !void {
        \\    if (cfg.sample_count == 0) {
        \\        return error.InvalidSampleCount;
        \\    }
        \\
        \\    // Try typing a new function or pressing Enter inside `{}`!
        \\    const label = uic.fmt("Target FPS: {d:.0}", .{cfg.target_fps});
        \\    uic.heading(label);
        \\}
        ,
    },
    .{
        .name = "live_notes.md",
        .language = .markdown,
        .initial_source =
        \\# Live Editable Markdown
        \\
        \\Edit this **Markdown** buffer on the left and watch the rendered preview update on the right in real time!
        \\
        \\> [!TIP]
        \\> Try selecting multiple lines and pressing `Tab` or `Shift+Tab` — the selection stays active!
        \\
        \\## Interactive Features
        \\
        \\- [x] Full keyboard editing & UTF-8 text insertion
        \\- [x] Mouse click & drag range selection
        \\- [x] Built-in `Undo` (`Cmd+Z`) and `Redo` (`Cmd+Shift+Z`)
        \\- [ ] Add your own task item here!
        \\
        \\| Shortcut | Action |
        \\| :--- | :--- |
        \\| `Cmd + /` | Toggle line comment |
        \\| `Cmd + D` | Duplicate current line |
        \\| `Tab / Shift+Tab` | Indent or outdent selection |
        ,
    },
    .{
        .name = "settings.json",
        .language = .json,
        .initial_source =
        \\{
        \\    "editor.fontFamily": "Menlo",
        \\    "editor.fontSize": 13,
        \\    "editor.lineNumbers": true,
        \\    "editor.minimap.enabled": false,
        \\    "editor.autoClosingBrackets": "always",
        \\    "gpu.backend": "MetalGanesh",
        \\    "gpu.resourceCacheLimitMB": 8
        \\}
        ,
    },
    .{
        .name = "scratchpad.txt",
        .language = .plain,
        .initial_source =
        \\Plain Text Scratchpad Buffer
        \\============================
        \\
        \\This tab uses plain-text mode (`CodeLanguage.plain`).
        \\You can use it as a general-purpose multi-line text area or note pad.
        \\
        \\Try selecting several lines with the mouse and pressing Tab / Shift+Tab,
        \\or use Alt+Left / Alt+Right to jump word-by-word.
        ,
    },
};

const CodeEditorDemoState = struct {
    frame_arena: std.heap.ArenaAllocator,
    fonts: ui.FontSet,
    ui_ctx: ui.Context,
    config: EditorDemoConfig = .{},
    buffers: [FILE_TEMPLATES.len]ui.CodeEditorBuffer(4096) = undefined,
    buffers_initialized: bool = false,

    pub fn init(self: *CodeEditorDemoState, ctx: *PlatformContext) void {
        self.fonts = ui.FontSet.init(ctx, .{});
        self.ui_ctx = self.fonts.initContext(self.frame_arena.allocator(), ctx);

        if (!self.buffers_initialized) {
            for (FILE_TEMPLATES, 0..) |tpl, idx| {
                self.buffers[idx] = ui.CodeEditorBuffer(4096).initFromSlice(tpl.initial_source);
            }
            self.buffers_initialized = true;
            self.ui_ctx.focused_id = ui.id("main_code_editor");
        }
    }

    pub fn deinit(self: *CodeEditorDemoState) void {
        self.ui_ctx.deinit();
        self.fonts.deinit();
        self.frame_arena.deinit();
    }
};

comptime {
    ui.exportPlugin(CodeEditorDemoState, "config", STATE_VERSION, buildUi);
}

fn buildUi(state: *CodeEditorDemoState) void {
    const uic = &state.ui_ctx;
    var scope = uic.scopedState("code_editor_demo");
    defer scope.end();

    const active_tab = uic.useState(usize, "active_tab", 0);
    const tab_idx = active_tab.* % FILE_TEMPLATES.len;
    const tpl = FILE_TEMPLATES[tab_idx];
    const active_buf = &state.buffers[tab_idx];

    // 1. Unified Window Titlebar with Right-Aligned Status Badges
    uic.titlebar("Example: Text & Code Editor Component", &.{
        .{ .text = uic.fmt("FILE: {s}", .{tpl.name}), .accent = true },
        .{ .text = uic.fmt("LANG: {s}", .{tpl.language.label()}) },
    });

    // 2. Main Workspace Row (Sidebar + Editor Area)
    var workspace = uic.row(.{ .preset = .workspace });
    defer workspace.end();

    // Left Control Sidebar (265pt)
    {
        var sidebar = uic.scrollPanel("ce_sidebar_scroll", .{
            .w = .pixels(265),
            .preset = .panel_card,
            .gap = 8,
        });
        defer sidebar.end();

        uic.sectionHeader("OPEN BUFFERS");
        for (FILE_TEMPLATES, 0..) |file_tpl, idx| {
            var item_id = uic.scopedId(idx);
            defer item_id.end();
            if (uic.tab(file_tpl.name, tab_idx == idx)) {
                active_tab.* = idx;
                uic.focused_id = ui.id("main_code_editor");
            }
        }

        uic.sectionHeader("EDITOR COMMANDS");
        {
            var undo_row = uic.row(.{ .h = .pixels(36), .gap = 8 });
            defer undo_row.end();
            if (uic.btn("Undo", .{ .w = .half })) {
                _ = active_buf.undo();
                uic.focused_id = ui.id("main_code_editor");
            }
            if (uic.btn("Redo", .{ .w = .half })) {
                _ = active_buf.redo();
                uic.focused_id = ui.id("main_code_editor");
            }
        }
        {
            var cmd_row = uic.row(.{ .h = .pixels(36), .gap = 8 });
            defer cmd_row.end();
            if (uic.btn("Toggle //", .{ .w = .half })) {
                _ = active_buf.toggleLineComment(tpl.language.commentPrefix());
                uic.focused_id = ui.id("main_code_editor");
            }
            if (uic.btn("Dup Line", .{ .w = .half })) {
                _ = active_buf.duplicateCurrentLine();
                uic.focused_id = ui.id("main_code_editor");
            }
        }
        if (uic.btn("Reset Buffer to Default", .{})) {
            active_buf.saveUndoCheckpoint();
            active_buf.setText(tpl.initial_source);
            uic.focused_id = ui.id("main_code_editor");
        }

        uic.sectionHeader("DISPLAY SETTINGS");
        _ = uic.checkbox("Line Numbers", &state.config.show_line_numbers);
        _ = uic.checkbox("Indent Guides", &state.config.show_indent_guides);
        _ = uic.checkbox("Show Minimap", &state.config.show_minimap);
        _ = uic.checkbox("Syntax Highlight", &state.config.syntax_highlight);
        _ = uic.checkbox("Auto-Close Pairs", &state.config.auto_close_pairs);
        _ = uic.checkbox("Read-Only Mode", &state.config.read_only);
        _ = uic.checkbox("Show Scissor Outline", &state.config.show_dirty_overlay);
        _ = uic.sliderFloat("Line Height", &state.config.line_height, 18.0, 28.0);
    }

    // Right Workspace: Code Editor (+ Live Markdown Preview when `live_notes.md` is active!)
    const is_md_split = (tpl.language == .markdown and uic.availableWidth() > 560.0);
    const editor_w = if (is_md_split) uic.resolveWidth(.half) else 0.0;

    _ = uic.codeEditor("main_code_editor", editor_w, 0, active_buf, .{
        .language = tpl.language,
        .font = state.fonts.code,
        .line_height = state.config.line_height,
        .show_line_numbers = state.config.show_line_numbers,
        .show_breakpoint_gutter = (tpl.language == .zig or tpl.language == .cpp or tpl.language == .rust),
        .show_indent_guides = state.config.show_indent_guides,
        .show_minimap = state.config.show_minimap and !is_md_split,
        .show_status_bar = state.config.show_status_bar,
        .syntax_highlight = state.config.syntax_highlight,
        .auto_close_pairs = state.config.auto_close_pairs,
        .read_only = state.config.read_only,
    });

    if (is_md_split) {
        var md_panel = uic.scrollPanel("md_live_preview", .{
            .preset = .panel_card,
            .padding = ui.Padding.all(18),
            .corner_radius = 8,
        });
        defer md_panel.end();
        uic.markdown(active_buf.slice());
    }
}
