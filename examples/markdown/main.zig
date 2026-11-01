//! Dedicated Markdown Renderer Showcase (`libexample_markdown.dylib`).
//! Demonstrates `ui.Context.markdownEx()` paired with a live-editable `ui.Context.codeEditor()`
//! raw Markdown source pane, declarative layout guards, and `ui.runTwoPhaseFrame`.
//!
//! Run with: `zig build run-markdown` (and hot-reload live with `zig build example-markdown`).

const std = @import("std");
const skia = @import("skia");
const ui = @import("ui");
const platform = @import("platform");
const PlatformContext = platform.PlatformContext;

const STATE_VERSION: u64 = 0x2026_1019_4D46;

const MarkdownDemoConfig = struct {
    line_height: f32 = 22.0,
    code_line_height: f32 = 20.0,
    show_line_numbers: bool = true,
    syntax_highlight: bool = true,
    split_source_view: bool = true,
    show_dirty_overlay: bool = false,
};

const DocPreset = struct {
    title: []const u8,
    badge: []const u8,
    markdown: []const u8,
};

const DOC_PRESETS = [_]DocPreset{
    .{
        .title = "1. Architecture Guide",
        .badge = "CORE",
        .markdown =
        \\# Zig + Skia UI Architecture
        \\
        \\Welcome to the **Markdown Renderer Component** (`src/ui/markdown.zig`). It parses and renders structured Markdown documents directly onto a hardware-accelerated **Skia Metal** canvas using the 2-phase `Pass.input` and `Pass.paint` pipeline.
        \\
        \\> [!TIP]
        \\> Edit the Markdown source in the middle pane or adjust the **Body Line Height** slider to see real-time layout reflow and word wrapping!
        \\
        \\## Key Rendering Capabilities
        \\
        \\- [x] Word-wrapped paragraphs with **bold**, *italic*, `inline code`, and ~~strikethrough~~
        \\- [x] Interactive links like [Zig Language Reference](https://ziglang.org/documentation/master/) and [Skia Graphics](https://skia.org)
        \\- [x] GitHub-style Callout Alerts (`NOTE`, `TIP`, `IMPORTANT`, `WARNING`, `CAUTION`)
        \\- [x] Fenced code blocks with language headers, line numbers, and syntax highlighting
        \\- [ ] Custom embedded SVG diagrams (planned for next milestone)
        \\
        \\## Two-Phase Execution Model
        \\
        \\| Phase | Responsibility | GPU Calls |
        \\| :--- | :--- | :---: |
        \\| `Pass.input` | Layout measurement, scroll physics & hit-testing | `0` |
        \\| `Pass.paint` | Scissor-clipped drawing with cached `SkTextBlob`s | Minimal |
        \\| `TextCache` | Direct-mapped 512-slot glyph run cache | Cached |
        \\
        \\## Usage Example
        \\
        \\Embedding Markdown inside any scrollable container takes a single call on `ui.Context`:
        \\
        \\```zig
        \\var panel = uic.scrollPanel("doc_scroll", .{ .preset = .panel_card });
        \\defer panel.end();
        \\
        \\const res = uic.markdownEx(markdown_src, .{
        \\    .show_code_line_numbers = true,
        \\    .syntax_highlight_code = true,
        \\});
        \\```
        \\
        \\> [!NOTE]
        \\> All text runs are automatically sub-sliced from the input buffer with **zero string allocations** and cached in `TextCache`.
        ,
    },
    .{
        .title = "2. Syntax & Callout Showcase",
        .badge = "SYNTAX",
        .markdown =
        \\# Complete Markdown Syntax Showcase
        \\
        \\This document exercises every block and inline construct supported by `ui.markdown_mod`.
        \\
        \\## 1. Inline Typography & Links
        \\
        \\Inline spans can mix **strong emphasis**, *italicized terms*, `monospace_pills()`, ~~deprecated APIs~~, and clickable links such as [GitHub Repository](https://github.com/ziglang/zig) or [Metal Shading Language Spec](https://developer.apple.com/metal/) within a single wrapped paragraph.
        \\
        \\---
        \\
        \\## 2. GitHub Callout Alerts & Blockquotes
        \\
        \\> Standard blockquote: Design is not just what it looks like and feels like. Design is how it works.
        \\
        \\> [!NOTE]
        \\> Useful background context or implementation notes that stand out from body paragraphs.
        \\
        \\> [!IMPORTANT]
        \\> Critical invariants required for hot-reloadable `.dylib` plugins and `StateStore` hooks.
        \\
        \\> [!WARNING]
        \\> Mutating layout dimensions during `Pass.paint` instead of `Pass.input` will desynchronize dirty rectangles.
        \\
        \\> [!CAUTION]
        \\> Never hold raw pointers into the plugin dylib across `dlclose` boundaries without serializing state.
        \\
        \\---
        \\
        \\## 3. Ordered, Unordered & Nested Lists
        \\
        \\1. Initialize `skia.DirectContext` bound to the `CAMetalLayer` device and queue
        \\2. Run `Pass.input` to compute bounding boxes and union dirty regions
        \\3. Intersect `clip_damage` and replay `Pass.paint`
        \\
        \\- Level 0 bullet item with `inline code`
        \\  - Level 1 nested bullet item with **bold text**
        \\    - Level 2 deeply nested item with [API Link](https://ziglang.org)
        ,
    },
    .{
        .title = "3. Hot-Reload & Release Notes",
        .badge = "v0.4.0",
        .markdown =
        \\# Release v0.4.0 — Declarative UI & Markdown
        \\
        \\The **v0.4.0** update introduces native Markdown document rendering, an interactive `codeEditor` widget, and declarative container guards.
        \\
        \\> [!IMPORTANT]
        \\> You can edit `examples/markdown/main.zig` and run `zig build example-markdown` in another terminal to hot-reload this window without losing scroll position!
        \\
        \\## Benchmark Summary
        \\
        \\| Metric | v0.3.0 | v0.4.0 | Status |
        \\| :--- | :---: | :---: | ---: |
        \\| Idle GPU Usage | `0.0%` | `0.0%` | Verified |
        \\| TextCache Slots | `128` | `512` | **4x Capacity** |
        \\| Scroll Frame Time | `0.42 ms` | `0.31 ms` | **120 Hz Locked** |
        \\
        \\## Quick CLI Commands
        \\
        \\```bash
        \\# Run the interactive Markdown showcase window
        \\zig build run-markdown
        \\
        \\# Recompile only libexample_markdown.dylib for live hot-reload
        \\zig build example-markdown
        \\
        \\# Run all unit tests (skia, ui, markdown, code_editor, platform)
        \\zig build test
        \\```
        \\
        \\## Verification Checklist
        \\
        \\- [x] Verify ATX headings `# H1` through `#### H4`
        \\- [x] Verify word-wrapped inline spans and clickable links
        \\- [x] Verify fenced code blocks and pipe tables
        \\- [x] Verify two-finger trackpad scrolling and scrollbar thumb dragging
        ,
    },
};

const MarkdownDemoState = struct {
    frame_arena: std.heap.ArenaAllocator,
    fonts: ui.FontSet,
    ui_ctx: ui.Context,
    config: MarkdownDemoConfig = .{},
    buffers: [DOC_PRESETS.len]ui.CodeEditorBuffer(4096) = undefined,
    buffers_initialized: bool = false,
    last_clicked_url: platform.InlineString(128) = .{},

    pub fn init(self: *MarkdownDemoState, ctx: *PlatformContext) void {
        self.fonts = ui.FontSet.init(ctx, .{});
        self.ui_ctx = self.fonts.initContext(self.frame_arena.allocator(), ctx);

        if (!self.buffers_initialized) {
            for (DOC_PRESETS, 0..) |preset, idx| {
                self.buffers[idx] = ui.CodeEditorBuffer(4096).initFromSlice(preset.markdown);
            }
            self.buffers_initialized = true;
        }
    }

    pub fn deinit(self: *MarkdownDemoState) void {
        self.ui_ctx.deinit();
        self.fonts.deinit();
        self.frame_arena.deinit();
    }
};

comptime {
    ui.exportPlugin(MarkdownDemoState, "config", STATE_VERSION, buildUi);
}

fn buildUi(state: *MarkdownDemoState) void {
    const uic = &state.ui_ctx;
    var scope = uic.scopedState("markdown_showcase");
    defer scope.end();

    const active_doc_idx = uic.useState(usize, "active_doc_idx", 0);
    const doc_idx = active_doc_idx.* % DOC_PRESETS.len;
    const preset = DOC_PRESETS[doc_idx];
    const active_buf = &state.buffers[doc_idx];

    // 1. Unified Titlebar
    uic.titlebar("Example: Markdown Renderer Component", &.{
        .{ .text = uic.fmt("DOC: {s}", .{preset.badge}), .accent = true },
        .{ .text = if (state.config.split_source_view) "MODE: LIVE SPLIT" else "MODE: PREVIEW ONLY" },
    });

    // 2. Main Workspace Row
    var workspace = uic.row(.{ .preset = .workspace });
    defer workspace.end();

    // Left Control Sidebar (265pt)
    {
        var sidebar = uic.scrollPanel("md_sidebar_scroll", .{
            .w = .pixels(265),
            .preset = .panel_card,
        });
        defer sidebar.end();

        uic.sectionHeader("DOCUMENT PRESETS");
        for (DOC_PRESETS, 0..) |item, idx| {
            var item_id = uic.scopedId(idx);
            defer item_id.end();
            if (uic.tab(item.title, doc_idx == idx)) {
                active_doc_idx.* = idx;
            }
        }

        uic.sectionHeader("RENDERER OPTIONS");
        _ = uic.checkbox("Split Editable Source", &state.config.split_source_view);
        _ = uic.checkbox("Syntax Highlight Code", &state.config.syntax_highlight);
        _ = uic.checkbox("Code Line Numbers", &state.config.show_line_numbers);
        _ = uic.checkbox("Show Scissor Outline", &state.config.show_dirty_overlay);
        _ = uic.sliderFloat("Body Line Height", &state.config.line_height, 18.0, 30.0);

        if (uic.btn("Reset Document Source", .{})) {
            active_buf.saveUndoCheckpoint();
            active_buf.setText(preset.markdown);
        }

        uic.sectionHeader("LINK INTERACTION");
        const clicked_slice = if (!state.last_clicked_url.isEmpty())
            state.last_clicked_url.slice()
        else
            "Click any link in preview";
        uic.badge(clicked_slice, uic.theme.bg_card, skia.Color.rgb(125, 211, 252));
    }

    // Optional Live-Editable Raw Markdown Source Pane
    if (state.config.split_source_view and uic.availableWidth() > 520.0) {
        const source_w = uic.resolveWidth(.fraction(0.45));
        _ = uic.codeEditor("md_source_editor", source_w, 0, active_buf, .{
            .language = .markdown,
            .font = state.fonts.code,
            .line_height = 20.0,
            .show_line_numbers = true,
            .show_indent_guides = false,
            .show_minimap = false,
            .show_status_bar = true,
        });
    }

    // Rendered Markdown Preview Pane
    {
        var preview = uic.scrollPanel("md_rendered_preview_scroll", .{
            .preset = .panel_card,
            .padding = ui.Padding.all(22),
            .gap = 12,
        });
        defer preview.end();

        const md_res = uic.markdownEx(active_buf.slice(), .{
            .font_h1 = state.fonts.h1,
            .font_h2 = state.fonts.h2,
            .font_h3 = state.fonts.h3,
            .font_body = state.fonts.body,
            .font_mono = state.fonts.mono,
            .line_height = state.config.line_height,
            .code_line_height = state.config.code_line_height,
            .show_code_line_numbers = state.config.show_line_numbers,
            .syntax_highlight_code = state.config.syntax_highlight,
        });

        if (md_res.clicked_link) |url| {
            state.last_clicked_url.set(url);
            uic.invalidateWindow();
        }
    }
}
