//! Built-in fallback workspace files and `SampleFile` descriptor for `EditorState`.

const ui = @import("ui");

pub const BufferKind = enum {
    file,
    markdown_preview,
    bound_markdown_preview,
    waveform_preview,
    pdf_preview,
    git_diff_preview,
    app_preview,
    terminal,
    agent,

    pub fn isReadOnlyPreview(self: BufferKind) bool {
        return switch (self) {
            .markdown_preview,
            .bound_markdown_preview,
            .waveform_preview,
            .pdf_preview,
            .git_diff_preview,
            .app_preview,
            => true,
            .file, .terminal, .agent => false,
        };
    }

    pub fn badgeLabel(self: BufferKind) ?[]const u8 {
        return switch (self) {
            .file => null,
            .markdown_preview, .bound_markdown_preview => "P",
            .waveform_preview => "W",
            .pdf_preview => "PDF",
            .git_diff_preview => "D",
            .app_preview => "APP",
            .terminal => "T",
            .agent => "✦",
        };
    }
};

pub const SampleFile = struct {
    name: []const u8,
    path: [:0]const u8,
    folder: []const u8,
    language: ui.CodeLanguage = .zig,
    is_markdown_preview: bool = false,
    is_bound_markdown_preview: bool = false,
    md_preview_source_idx: u16 = 0,
    is_waveform_preview: bool = false,
    is_pdf_preview: bool = false,
    is_git_diff_preview: bool = false,
    is_app_preview: bool = false,
    is_terminal: bool = false,
    terminal_slot: u16 = 0,
    is_agent: bool = false,
    agent_slot: u16 = 0,
    initial_source: []const u8,

    pub fn kind(self: SampleFile) BufferKind {
        if (self.is_agent) return .agent;
        if (self.is_terminal) return .terminal;
        if (self.is_app_preview) return .app_preview;
        if (self.is_git_diff_preview) return .git_diff_preview;
        if (self.is_pdf_preview) return .pdf_preview;
        if (self.is_waveform_preview) return .waveform_preview;
        if (self.is_markdown_preview) {
            return if (self.is_bound_markdown_preview) .bound_markdown_preview else .markdown_preview;
        }
        return .file;
    }

    pub fn isSpecial(self: SampleFile) bool {
        return self.kind() != .file;
    }
};

pub const WORKSPACE_FILES = [_]SampleFile{
    .{
        .name = "main.zig",
        .path = "src/app/main.zig",
        .folder = "src/app",
        .language = .zig,
        .initial_source =
        \\//! Main Editor Application (`libeditor_app.dylib`).
        \\const std = @import("std");
        \\const ui = @import("ui");
        ,
    },
    .{
        .name = "editor_pane.zig",
        .path = "src/app/views/editor_pane.zig",
        .folder = "src/app/views",
        .language = .zig,
        .initial_source =
        \\//! VS Code Center Workbench: Tabs, Breadcrumbs, Find Bar, Code Editor & Split Markdown.
        \\const ui = @import("ui");
        ,
    },
    .{
        .name = "explorer.zig",
        .path = "src/app/views/explorer.zig",
        .folder = "src/app/views",
        .language = .zig,
        .initial_source =
        \\//! Primary Sidebar: Explorer, Workspace Search, Source Control, and Run & Debug.
        \\const ui = @import("ui");
        ,
    },
    .{
        .name = "layout.zig",
        .path = "src/ui/layout.zig",
        .folder = "src/ui",
        .language = .zig,
        .initial_source =
        \\//! Flex-like row/column and 2D scrollable container layout primitives.
        \\const skia = @import("skia");
        ,
    },
    .{
        .name = "README.md",
        .path = "README.md",
        .folder = ".",
        .language = .markdown,
        .initial_source =
        \\# Zig + Skia Hardware-Accelerated Editor
        \\
        \\Welcome to the live **Zig + Skia + Metal** editor workbench!
        \\
        \\> [!TIP]
        \\> Edit this Markdown file on the left to see the live rendered preview update on the right, or press `Cmd+S` to save to disk!
        \\
        \\## Keyboard Shortcuts
        \\
        \\| Shortcut | Command |
        \\| :--- | :--- |
        \\| `Cmd + Shift + B` | Tasks: Run Build Task (`zig build`, `.vscode/tasks.json`, etc.) |
        \\| `Cmd + S` | Save active buffer to disk |
        \\| `Cmd + F` | Toggle Find in Buffer bar |
        \\| `Cmd + G` | Find Next match (`Cmd+Shift+G` Previous) |
        \\| `Cmd + P` | Toggle Quick Open / Command Palette |
        \\| `Cmd + B` | Toggle Primary Sidebar |
        \\| `Cmd + J` | Toggle Integrated Terminal / Problems Panel |
        \\| `Cmd + /` | Toggle line comment |
        \\| `Cmd + D` | Duplicate current line |
        ,
    },
    .{
        .name = "build.zig",
        .path = "build.zig",
        .folder = ".",
        .language = .zig,
        .initial_source =
        \\const std = @import("std");
        \\pub fn build(b: *std.Build) void {
        \\    _ = b;
        \\}
        ,
    },
    .{
        .name = "state.zig",
        .path = "src/app/state.zig",
        .folder = "src/app",
        .language = .zig,
        .initial_source = "//! Editor application state.\n",
    },
    .{
        .name = "titlebar.zig",
        .path = "src/app/views/titlebar.zig",
        .folder = "src/app/views",
        .language = .zig,
        .initial_source = "//! Unified macOS titlebar.\n",
    },
    .{
        .name = "activity_bar.zig",
        .path = "src/app/views/activity_bar.zig",
        .folder = "src/app/views",
        .language = .zig,
        .initial_source = "//! Far-left activity bar.\n",
    },
    .{
        .name = "status_bar.zig",
        .path = "src/app/views/status_bar.zig",
        .folder = "src/app/views",
        .language = .zig,
        .initial_source = "//! Bottom status bar.\n",
    },
    .{
        .name = "root.zig",
        .path = "src/ui/root.zig",
        .folder = "src/ui",
        .language = .zig,
        .initial_source = "//! UI widget & layout root.\n",
    },
    .{
        .name = "dock.zig",
        .path = "src/ui/dock.zig",
        .folder = "src/ui",
        .language = .zig,
        .initial_source = "//! Recursive binary split tree & docking.\n",
    },
    .{
        .name = "code_editor.zig",
        .path = "src/ui/code_editor.zig",
        .folder = "src/ui",
        .language = .zig,
        .initial_source = "//! Interactive code editor widget.\n",
    },
    .{
        .name = "markdown.zig",
        .path = "src/ui/markdown.zig",
        .folder = "src/ui",
        .language = .zig,
        .initial_source = "//! Markdown parser & renderer.\n",
    },
    .{
        .name = "vterm.zig",
        .path = "src/ui/vterm.zig",
        .folder = "src/ui",
        .language = .zig,
        .initial_source = "//! PTY VT100 terminal emulator.\n",
    },
    .{
        .name = "metal_window.zig",
        .path = "src/platform/macos/metal_window.zig",
        .folder = "src/platform",
        .language = .zig,
        .initial_source = "//! Native Cocoa + Metal window backend.\n",
    },
    .{
        .name = "objc.zig",
        .path = "src/platform/macos/objc.zig",
        .folder = "src/platform",
        .language = .zig,
        .initial_source = "//! Objective-C runtime bridge.\n",
    },
    .{
        .name = "AGENTS.md",
        .path = "AGENTS.md",
        .folder = ".",
        .language = .markdown,
        .initial_source = "testing\n",
    },
    .{
        .name = "*Markdown Preview*",
        .path = "*Markdown Preview*",
        .folder = "*special*",
        .language = .markdown,
        .is_markdown_preview = true,
        .initial_source = "",
    },
    .{
        .name = "*Waveform Preview*",
        .path = "sim_trace.vcd",
        .folder = "*special*",
        .language = .systemverilog,
        .is_waveform_preview = true,
        .initial_source = "",
    },
    .{
        .name = "*PDF Preview*",
        .path = "datasheet_rv32.pdf",
        .folder = "*special*",
        .language = .markdown,
        .is_pdf_preview = true,
        .initial_source = "",
    },
    .{
        .name = "*Git Diff*",
        .path = "*Git Diff*",
        .folder = "*special*",
        .language = .zig,
        .is_git_diff_preview = true,
        .initial_source = "",
    },
    .{
        .name = "*App Preview*",
        .path = "*App Preview*",
        .folder = "*special*",
        .language = .zig,
        .is_app_preview = true,
        .initial_source = "",
    },
};
