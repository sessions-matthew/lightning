//! Hybrid Immediate/Retained Widget & Layout System for Zig + Skia.
//! Supports two-phase execution:
//!   1. `Pass.input` (CPU-only layout, hit-testing, scroll wheel / scrollbar handling, and dirty-rect calculation)
//!   2. `Pass.paint` (Hardware scissor-clipped Skia rendering with cached `SkTextBlob`s)

const std = @import("std");
const skia = @import("skia");
const platform = @import("platform");
const c = skia.c;
const Color = skia.Color;
pub const Rect = skia.Rect;
const Canvas = skia.Canvas;
const Paint = skia.Paint;
const Font = skia.Font;
const PlatformContext = platform.PlatformContext;

pub const theme_mod = @import("theme.zig");
pub const layout_mod = @import("layout.zig");
pub const damage_mod = @import("damage.zig");
pub const icons_mod = @import("icons.zig");
pub const text_input_mod = @import("text_input.zig");
pub const text_cache_mod = @import("text_cache.zig");
pub const markdown_mod = @import("markdown.zig");
pub const code_editor_mod = @import("code_editor.zig");
pub const vterm_mod = @import("vterm.zig");
pub const waveform_mod = @import("waveform.zig");
pub const diff_viewer_mod = @import("diff_viewer.zig");
pub const pdf_viewer_mod = @import("pdf_viewer.zig");
pub const image_viewer_mod = @import("image_viewer.zig");
pub const app_runner_mod = @import("app_runner.zig");
pub const dock_mod = @import("dock.zig");
pub const frame_cache_mod = @import("frame_cache.zig");
pub const virtual_list_mod = @import("virtual_list.zig");
pub const cards_mod = @import("cards.zig");
pub const stage_mod = @import("stage.zig");
pub const inspector_mod = @import("inspector.zig");
pub const command_registry_mod = @import("command_registry.zig");
pub const data_grid_mod = @import("data_grid.zig");
pub const charts_mod = @import("charts.zig");
pub const node_graph_mod = @import("node_graph.zig");
pub const tree_view_mod = @import("tree_view.zig");

pub const Theme = theme_mod.Theme;
pub const Pass = layout_mod.Pass;
pub const Direction = layout_mod.Direction;
pub const Size = layout_mod.Size;
pub const Padding = layout_mod.Padding;
pub const BorderEdges = layout_mod.BorderEdges;
pub const BoxStyle = layout_mod.BoxStyle;
pub const ContainerPreset = layout_mod.ContainerPreset;
pub const ContainerConfig = layout_mod.ContainerConfig;
pub const ScrollDelta = layout_mod.ScrollDelta;
pub const snapScrollAxis = layout_mod.snapScrollAxis;
pub const ScrollState = layout_mod.ScrollState;
pub const LayoutContainer = layout_mod.LayoutContainer;
pub const MaxDamageRects = damage_mod.MaxDamageRects;
pub const DamageList = damage_mod.DamageList;
pub const Icon = icons_mod.Icon;
pub const IconButtonOptions = icons_mod.IconButtonOptions;
pub const TextInputState = text_input_mod.TextInputState;
pub const TextFieldOptions = text_input_mod.TextFieldOptions;
pub const TextFieldResult = text_input_mod.TextFieldResult;
pub const TextAreaOptions = text_input_mod.TextAreaOptions;
pub const TextAreaResult = text_input_mod.TextAreaResult;
pub const stepListSelection = text_input_mod.stepListSelection;
pub const TextCache = text_cache_mod.TextCache;
pub const TextCacheStats = text_cache_mod.TextCacheStats;
pub const MarkdownOptions = markdown_mod.MarkdownOptions;
pub const MarkdownBubbleOptions = markdown_mod.MarkdownBubbleOptions;
pub const MarkdownResult = markdown_mod.MarkdownResult;
pub const CodeLanguage = code_editor_mod.CodeLanguage;
pub const CompletionPopupItem = code_editor_mod.CompletionPopupItem;
pub const CodeEditorOptions = code_editor_mod.CodeEditorOptions;
pub const CodeEditorResult = code_editor_mod.CodeEditorResult;
pub const CodeEditorBuffer = code_editor_mod.CodeEditorBuffer;
pub const CodeEditorState = code_editor_mod.CodeEditorState;
pub const drawSyntaxHighlightedLine = code_editor_mod.drawSyntaxHighlightedLine;
pub const VTerm = vterm_mod.VTerm;
pub const WaveformData = waveform_mod.WaveformData;
pub const WaveformViewState = waveform_mod.WaveformViewState;
pub const parseVcd = waveform_mod.parseVcd;
pub const SAMPLE_COUNTER_VCD = waveform_mod.SAMPLE_COUNTER_VCD;
pub const DiffViewMode = diff_viewer_mod.DiffViewMode;
pub const DiffViewState = diff_viewer_mod.DiffViewState;
pub const DiffViewerOptions = diff_viewer_mod.DiffViewerOptions;
pub const DiffViewResult = diff_viewer_mod.DiffViewResult;
pub const parseUnifiedDiff = diff_viewer_mod.parseUnifiedDiff;
pub const SAMPLE_GIT_DIFF = diff_viewer_mod.SAMPLE_GIT_DIFF;
pub const PdfOutlineItem = pdf_viewer_mod.PdfOutlineItem;
pub const PdfTextPos = pdf_viewer_mod.PdfTextPos;
pub const PdfPageInfo = pdf_viewer_mod.PdfPageInfo;
pub const PdfDocumentData = pdf_viewer_mod.PdfDocumentData;
pub const PdfViewState = pdf_viewer_mod.PdfViewState;
pub const PdfViewerOptions = pdf_viewer_mod.PdfViewerOptions;
pub const PdfViewerResult = pdf_viewer_mod.PdfViewerResult;
pub const parsePdfDocument = pdf_viewer_mod.parsePdfDocument;
pub const SAMPLE_PDF_DOC = pdf_viewer_mod.SAMPLE_PDF_DOC;
pub const ImageBackdrop = image_viewer_mod.ImageBackdrop;
pub const ImageViewState = image_viewer_mod.ImageViewState;
pub const ImageViewerOptions = image_viewer_mod.ImageViewerOptions;
pub const ImageViewerResult = image_viewer_mod.ImageViewerResult;
pub const ImageDimensions = image_viewer_mod.ImageDimensions;
pub const SAMPLE_SVG_IMAGE = image_viewer_mod.SAMPLE_SVG_IMAGE;
pub const isImagePath = image_viewer_mod.isImagePath;
pub const queryImageDimensions = image_viewer_mod.queryImageDimensions;
pub const drawImageThumbnail = image_viewer_mod.drawImageThumbnail;
pub const FontSizes = app_runner_mod.FontSizes;
pub const FontSet = app_runner_mod.FontSet;
pub const runTwoPhaseFrame = app_runner_mod.runTwoPhaseFrame;
pub const plugin_abi = platform.plugin_abi;
pub const plugin_sdk = platform.plugin_sdk;
pub const exportPlugin = app_runner_mod.exportPlugin;
pub const SplitNode = dock_mod.SplitNode;
pub const SplitTree = dock_mod.SplitTree;
pub const SplitTreeOptions = dock_mod.SplitTreeOptions;
pub const DockDropZone = dock_mod.DockDropZone;
pub const DockDropTarget = dock_mod.DockDropTarget;
pub const CompletedTabDrop = dock_mod.CompletedTabDrop;
pub const TabReorderSwap = dock_mod.TabReorderSwap;
pub const TabDragState = dock_mod.TabDragState;
pub const PaneTabGroup = dock_mod.PaneTabGroup;
pub const FrameLatchTape = frame_cache_mod.FrameLatchTape;
pub const FrameCacheTable = frame_cache_mod.FrameCacheTable;
pub const VcdCacheSlot = frame_cache_mod.VcdCacheSlot;
pub const PdfCacheSlot = frame_cache_mod.PdfCacheSlot;
pub const WrappedLabelOptions = virtual_list_mod.WrappedLabelOptions;
pub const wrapPlainText = virtual_list_mod.wrapPlainText;
pub const VariableHeightCache = virtual_list_mod.VariableHeightCache;
pub const EntryHeightCache = virtual_list_mod.EntryHeightCache;
pub const InlineStepRowResult = cards_mod.InlineStepRowResult;
pub const ThinkingDisclosureOptions = cards_mod.ThinkingDisclosureOptions;
pub const ThinkingDisclosureResult = cards_mod.ThinkingDisclosureResult;
pub const extractThinkingPreviewLine = cards_mod.extractThinkingPreviewLine;
pub const CommandCardStatus = cards_mod.CommandCardStatus;
pub const CommandCardAction = cards_mod.CommandCardAction;
pub const CommandCardOptions = cards_mod.CommandCardOptions;
pub const CommandCardResult = cards_mod.CommandCardResult;
pub const parseRecommendedOptionLabel = cards_mod.parseRecommendedOptionLabel;
pub const measureSelectableOptionCardHeight = cards_mod.measureSelectableOptionCardHeight;
pub const SplitMenuItemResult = cards_mod.SplitMenuItemResult;
pub const AttachmentDisplayItem = cards_mod.AttachmentDisplayItem;
pub const AttachmentStripOptions = cards_mod.AttachmentStripOptions;
pub const Viewport2DState = stage_mod.Viewport2DState;
pub const CanvasStageOptions = stage_mod.CanvasStageOptions;
pub const CanvasStageScope = stage_mod.CanvasStageScope;
pub const ToastSeverity = inspector_mod.ToastSeverity;
pub const ToastItem = inspector_mod.ToastItem;
pub const ToastQueue = inspector_mod.ToastQueue;
pub const DataGridColumn = data_grid_mod.DataGridColumn;
pub const DataGridState = data_grid_mod.DataGridState;
pub const DataGridResult = data_grid_mod.DataGridResult;
pub const SparklineOptions = charts_mod.SparklineOptions;
pub const ChartSeries = charts_mod.ChartSeries;
pub const LineChartOptions = charts_mod.LineChartOptions;
pub const LineChartResult = charts_mod.LineChartResult;
pub const BarChartItem = charts_mod.BarChartItem;
pub const BarChartOptions = charts_mod.BarChartOptions;
pub const GraphPin = node_graph_mod.GraphPin;
pub const GraphNode = node_graph_mod.GraphNode;
pub const GraphEdge = node_graph_mod.GraphEdge;
pub const NodeGraphState = node_graph_mod.NodeGraphState;
pub const NodeGraphOptions = node_graph_mod.NodeGraphOptions;
pub const NodeGraphResult = node_graph_mod.NodeGraphResult;
pub const TreeInlineInputOptions = tree_view_mod.TreeInlineInputOptions;
pub const TreeInlineInputAction = tree_view_mod.TreeInlineInputAction;
pub const pathDepth = tree_view_mod.pathDepth;
pub const parentDirPath = tree_view_mod.parentDirPath;
pub const baseName = tree_view_mod.baseName;
pub const isPathVisibleInTree = tree_view_mod.isPathVisibleInTree;
pub const drawTreeIndentGuides = tree_view_mod.drawTreeIndentGuides;
pub const treeInlineInputRow = tree_view_mod.treeInlineInputRow;

pub const WidgetId = u64;
pub const CursorShape = platform.CursorShape;
pub const KeyCode = platform.KeyCode;

pub fn id(label: []const u8) WidgetId {
    return std.hash.Fnv1a_64.hash(label);
}

/// Computes a scoped `WidgetId` matching a sequence of `pushScope` / `pushId` string scopes followed by `raw_label`.
pub fn scopedIdPath(scopes: []const []const u8, raw_label: []const u8) WidgetId {
    var seed: u64 = 0;
    for (scopes, 0..) |s, idx| {
        var h = std.hash.Fnv1a_64.init();
        if (idx > 0) {
            h.update(std.mem.asBytes(&seed));
        }
        h.update(s);
        seed = h.final();
    }
    var h = std.hash.Fnv1a_64.init();
    if (scopes.len > 0) {
        h.update(std.mem.asBytes(&seed));
    }
    h.update(raw_label);
    const wid = h.final();
    return if (wid == 0) 1 else wid;
}

pub const indexOfIgnoreCasePos = command_registry_mod.indexOfIgnoreCasePos;
pub const containsIgnoreCase = command_registry_mod.containsIgnoreCase;
pub const fuzzyScore = command_registry_mod.fuzzyScore;
pub const scoreCommandMatch = command_registry_mod.scoreCommandMatch;
pub const matchesCommandQuery = command_registry_mod.matchesCommandQuery;
pub const Shortcut = command_registry_mod.Shortcut;
pub const CommandEntry = command_registry_mod.CommandEntry;
pub const matchShortcutInTable = command_registry_mod.matchShortcutInTable;
pub const keyCodeDisplayName = command_registry_mod.keyCodeDisplayName;

/// Insertion-sorts `items` in-place descending by their `.score` field.
pub fn sortByScoreDesc(comptime T: type, items: []T) void {
    if (items.len <= 1) return;
    var i: usize = 1;
    while (i < items.len) : (i += 1) {
        const item = items[i];
        var j: usize = i;
        while (j > 0 and items[j - 1].score < item.score) : (j -= 1) {
            items[j] = items[j - 1];
        }
        items[j] = item;
    }
}

pub const BadgeSpec = struct {
    text: []const u8,
    bg_color: ?u32 = null,
    text_color: ?u32 = null,
    accent: bool = false,
};

pub const ButtonVariant = enum(u8) {
    primary,
    secondary,
    toolbar,
};

pub const ButtonOptions = struct {
    w: Size = .fill,
    h: f32 = 36.0,
    id_override: ?[]const u8 = null,
    variant: ButtonVariant = .secondary,
    icon: ?Icon = null,
    icon_color: ?u32 = null,
    shortcut: []const u8 = "",
};

pub const ChipOptions = struct {
    w: ?f32 = null,
    min_w: f32 = 0.0,
    max_w: f32 = 10000.0,
    h: f32 = 22.0,
    active: bool = false,
    bordered: bool = false,
    mono: bool = false,
    pad_x: f32 = 8.0,
};

pub const BannerSeverity = enum(u8) {
    info,
    warning,
    err,
};

pub const ListItemOptions = struct {
    label: []const u8,
    meta: []const u8 = "",
    meta_color: ?u32 = null,
    icon_text: []const u8 = "",
    icon_color: ?u32 = null,
    icon_bg: ?u32 = null,
    selected: bool = false,
    height: f32 = 26.0,
    mono_label: bool = false,
    indent_level: usize = 0,
    action_label: []const u8 = "",
    secondary_action_label: []const u8 = "",
};

pub const ListItemResult = struct {
    clicked: bool = false,
    right_clicked: bool = false,
    action_clicked: bool = false,
    secondary_action_clicked: bool = false,
};

/// Declarative item specification for `Context.contextMenu(...)` and `Context.contextMenuItem(...)`.
pub const ContextMenuItem = struct {
    label: []const u8 = "",
    shortcut: []const u8 = "",
    enabled: bool = true,
    separator: bool = false,
    danger: bool = false,
};

/// Persistent value-oriented state for a floating right-click context menu.
/// Safe to store inside `EditorState`, `EditorDocument`, or `useState` across `.dylib` hot-reloads.
pub const ContextMenuState = struct {
    open: bool = false,
    anchor_x: f32 = 0,
    anchor_y: f32 = 0,
    target_id: u64 = 0,
    opened_this_frame: bool = false,

    pub fn openAt(self: *ContextMenuState, x: f32, y: f32, target_id: u64) void {
        self.open = true;
        self.anchor_x = x;
        self.anchor_y = y;
        self.target_id = target_id;
        self.opened_this_frame = true;
    }

    pub fn close(self: *ContextMenuState) void {
        self.open = false;
        self.opened_this_frame = false;
    }
};

pub const DocumentTabResult = struct {
    clicked: bool = false,
    closed: bool = false,
    wid: WidgetId = 0,
    rect: c.sk_rect_t = .{ .left = 0, .top = 0, .right = 0, .bottom = 0 },
};

pub const BoxGuard = struct {
    ctx: *Context,
    rect: c.sk_rect_t,
    pub fn end(self: BoxGuard) void {
        self.ctx.endBox();
    }
};

pub const ScopedContainer = BoxGuard;

pub const OverlayGuard = struct {
    ctx: *Context,
    rect: c.sk_rect_t,
    pub fn end(self: OverlayGuard) void {
        if (self.ctx.stack_len > 1) {
            self.ctx.stack_len -= 1;
        }
        self.ctx.in_overlay = false;
    }
};

pub const ScrollGuard = struct {
    ctx: *Context,
    rect: c.sk_rect_t,
    pub fn end(self: ScrollGuard) void {
        self.ctx.endScrollBox();
    }
};

pub const IdGuard = struct {
    ctx: *Context,
    pub fn end(self: IdGuard) void {
        self.ctx.popId();
    }
};

pub const ScopeGuard = struct {
    ctx: *Context,
    pub fn end(self: ScopeGuard) void {
        self.ctx.popScope();
    }
};

/// Visible index range and top/bottom spacer heights for O(1) virtualized list rendering.
pub const VirtualRange = struct {
    first: usize,
    end: usize,
    top_spacer_h: f32,
    bottom_spacer_h: f32,
};

pub const Context = struct {
    arena: std.mem.Allocator,
    canvas: Canvas,
    paint: Paint,
    font_title: Font,
    font_body: Font,
    font_mono: Font,
    theme: Theme = .{},

    /// Optional pointer to the Host `PlatformContext` for React-style `useState` hooks & scopes.
    platform_ctx: ?*PlatformContext = null,

    pass: Pass = .paint,

    // Input state for the frame
    mouse_x: f32 = 0,
    mouse_y: f32 = 0,
    scroll_dx: f32 = 0,
    scroll_dy: f32 = 0,
    magnify_delta: f32 = 0,
    mouse_down: bool = false,
    mouse_pressed: bool = false,
    mouse_released: bool = false,
    mouse_click_count: u8 = 1,
    mouse_shift: bool = false,
    right_mouse_down: bool = false,
    right_mouse_pressed: bool = false,
    right_mouse_released: bool = false,
    key_events: []const platform.KeyEvent = &.{},
    text_input: []const u8 = "",

    // Persistent interaction state across frames
    hot_id: WidgetId = 0,
    active_id: WidgetId = 0,
    focused_id: WidgetId = 0,
    select_all_wid: WidgetId = 0,
    prev_hot_id: WidgetId = 0,
    prev_active_id: WidgetId = 0,
    animating_this_frame: bool = false,
    drag_float_active_wid: WidgetId = 0,
    drag_float_last_mx: f32 = 0.0,

    // Fallback local scroll & text input state slots when running in standalone tests without a Host `PlatformContext`
    fallback_scroll_state: ScrollState = .{},
    fallback_text_input_state: TextInputState = .{},
    fallback_waveform_state: WaveformViewState = .{},
    fallback_pdf_state: PdfViewState = .{},
    fallback_code_block_scroll_state: markdown_mod.CodeBlockScrollState = .{},
    fallback_disclosure_toggles: [64]u8 = @splat(0),
    fallback_anim_slots: [32]struct { wid: WidgetId = 0, value: f32 = 0.0 } = @splat(.{}),

    // Damage tracking (accumulated during `.input` pass, used to cull during `.paint` pass)
    root_rect: c.sk_rect_t = .{ .left = 0, .top = 0, .right = 0, .bottom = 0 },
    dirty_rect: ?c.sk_rect_t = null,
    damage_list: DamageList = .{},
    clip_damage: ?c.sk_rect_t = null,
    blocking_overlay_rect: ?c.sk_rect_t = null,
    blocking_overlay_rects: [8]c.sk_rect_t = undefined,
    blocking_overlay_count: u8 = 0,
    retained_overlay_rects: [8]c.sk_rect_t = undefined,
    retained_overlay_count: u8 = 0,
    frame_registered_overlays: [8]c.sk_rect_t = undefined,
    frame_registered_overlay_count: u8 = 0,
    in_overlay: bool = false,
    last_dropdown_rect: c.sk_rect_t = .{ .left = 0, .top = 0, .right = 0, .bottom = 0 },
    dropdown_overlay_rect: ?c.sk_rect_t = null,
    prev_dropdown_overlay_rect: ?c.sk_rect_t = null,

    // Direct-mapped 512-slot `SkTextBlob` + width cache
    text_cache: TextCache = .{},

    // Zero-allocation hierarchical Widget ID stack (`pushId` / `popId`)
    id_stack: [16]u64 = undefined,
    id_stack_len: usize = 0,

    // Layout container stack
    stack: [16]LayoutContainer = undefined,
    stack_len: usize = 0,
    pass_rect_count: usize = 0,
    last_input_rect_count: usize = 0,
    last_paint_rect_count: usize = 0,

    // Per-frame Markdown block AST & bubble layout caches (shared between Pass.input and Pass.paint in the same frame arena)
    last_md_source_ptr: ?[*]const u8 = null,
    last_md_source_len: usize = 0,
    last_md_blocks: []markdown_mod.Block = &.{},
    md_cache_slots: [64]markdown_mod.MdBlockCacheSlot = @splat(.{}),
    md_cache_next: u8 = 0,
    md_bubble_slots: [32]markdown_mod.MdBubbleCacheSlot = @splat(.{}),
    md_bubble_next: u8 = 0,

    // Per-frame latch tape and multi-slot computed value cache (shared between Pass.input and Pass.paint)
    latch_tape: FrameLatchTape = .{},
    frame_cache: FrameCacheTable = .{},

    // Per-frame 4-way LRU VCD waveform parse cache (shared between Pass.input and Pass.paint in the same frame arena)
    vcd_cache_slots: [4]VcdCacheSlot = @splat(.{}),
    vcd_cache_tick: u32 = 0,

    // Per-frame 4-way LRU PDF document parse cache (shared between Pass.input and Pass.paint in the same frame arena)
    pdf_cache_slots: [4]PdfCacheSlot = @splat(.{}),
    pdf_cache_tick: u32 = 0,

    // Per-frame Unified Diff parse cache (shared between Pass.input and Pass.paint in the same frame arena)
    last_diff_source_ptr: ?[*]const u8 = null,
    last_diff_source_len: usize = 0,
    last_diff_data: ?*const diff_viewer_mod.ParsedDiff = null,

    // Deferred top-most context menu paint descriptor for built-in textFieldEx / textArea right-click menus
    deferred_text_menu_rect: ?c.sk_rect_t = null,
    deferred_text_menu_items: [6]ContextMenuItem = undefined,
    deferred_text_menu_len: usize = 0,
    deferred_text_menu_hot_idx: ?usize = null,

    pub fn deinit(self: *Context) void {
        self.text_cache.deinit();
    }

    pub fn measureTextCached(self: *Context, font: Font, text: []const u8) f32 {
        return self.text_cache.measure(font, text);
    }

    pub fn drawTextCached(self: *Context, font: Font, text: []const u8, x: f32, y: f32) void {
        self.text_cache.draw(self.canvas, self.paint, font, text, x, y);
    }

    pub fn getTextCacheStats(self: *const Context) TextCacheStats {
        return self.text_cache.getStats();
    }

    pub fn resetTextCacheStats(self: *Context) void {
        self.text_cache.resetStats();
    }

    // ========================================================================
    // React Fast Refresh-Style Scoped State Hooks (`useState`)
    // ========================================================================

    pub fn pushScope(self: *Context, scope_name: []const u8) void {
        if (self.platform_ctx) |pctx| {
            pctx.pushScope(scope_name);
        }
        self.pushId(scope_name);
    }

    pub fn popScope(self: *Context) void {
        if (self.platform_ctx) |pctx| {
            pctx.popScope();
        }
        self.popId();
    }

    pub fn scopedState(self: *Context, scope_name: []const u8) ScopeGuard {
        self.pushScope(scope_name);
        return .{ .ctx = self };
    }

    /// Push a numeric or string disambiguator onto the Widget ID stack (for loop items without `fmt` allocations).
    pub fn pushId(self: *Context, value: anytype) void {
        const T = @TypeOf(value);
        var h = std.hash.Fnv1a_64.init();
        if (self.id_stack_len > 0) {
            const parent_seed = self.id_stack[self.id_stack_len - 1];
            h.update(std.mem.asBytes(&parent_seed));
        }
        switch (@typeInfo(T)) {
            .int, .comptime_int => {
                const v: u64 = @intCast(value);
                h.update(std.mem.asBytes(&v));
            },
            .pointer => {
                const slice: []const u8 = value;
                h.update(slice);
            },
            else => {
                h.update(std.mem.asBytes(&value));
            },
        }
        if (self.id_stack_len < self.id_stack.len) {
            self.id_stack[self.id_stack_len] = h.final();
            self.id_stack_len += 1;
        }
    }

    pub fn popId(self: *Context) void {
        if (self.id_stack_len > 0) {
            self.id_stack_len -= 1;
        }
    }

    pub fn scopedId(self: *Context, value: anytype) IdGuard {
        self.pushId(value);
        return .{ .ctx = self };
    }

    /// Resolves a widget label like `"Save"` or `"Reset##file_1"` into a scoped `WidgetId` and display slice.
    pub fn resolveIdAndLabel(self: *const Context, raw_label: []const u8) struct { wid: WidgetId, display: []const u8 } {
        var h = std.hash.Fnv1a_64.init();
        if (self.id_stack_len > 0) {
            const seed = self.id_stack[self.id_stack_len - 1];
            h.update(std.mem.asBytes(&seed));
        }
        h.update(raw_label);
        const wid = h.final();
        const display = if (std.mem.indexOfPos(u8, raw_label, 0, "##")) |sep|
            raw_label[0..sep]
        else
            raw_label;
        return .{ .wid = if (wid == 0) 1 else wid, .display = display };
    }

    /// Focuses `wid` and schedules all text inside that `textFieldEx` / `textArea` to be selected
    /// on the current or next `.input` pass.
    pub fn focusAndSelectAll(self: *Context, wid: WidgetId) void {
        const target = if (wid == 0) 1 else wid;
        self.focused_id = target;
        self.select_all_wid = target;
    }

    /// Focuses a widget identified by `raw_label` inside the given `scopes` chain, combined with any currently active scopes on `self`.
    pub fn focusScoped(self: *Context, scopes: []const []const u8, raw_label: []const u8) void {
        var seed: u64 = if (self.id_stack_len > 0) self.id_stack[self.id_stack_len - 1] else 0;
        var has_seed = (self.id_stack_len > 0);
        for (scopes) |s| {
            var h = std.hash.Fnv1a_64.init();
            if (has_seed) {
                h.update(std.mem.asBytes(&seed));
            }
            h.update(s);
            seed = h.final();
            has_seed = true;
        }
        var h = std.hash.Fnv1a_64.init();
        if (has_seed) {
            h.update(std.mem.asBytes(&seed));
        }
        h.update(raw_label);
        const wid = h.final();
        self.focused_id = if (wid == 0) 1 else wid;
    }

    /// Focuses a widget identified by `raw_label` inside the given `scopes` chain (combined with any currently active scopes on `self`)
    /// and selects all text inside that `textFieldEx` / `textArea`.
    pub fn focusScopedAndSelectAll(self: *Context, scopes: []const []const u8, raw_label: []const u8) void {
        self.focusScoped(scopes, raw_label);
        self.select_all_wid = self.focused_id;
    }

    /// React-style `useState`: returns a zero-overhead `*T` pointer stored in the Host KV map.
    /// Scoped to the current `pushScope` stack; survives `.dylib` hot-reloads and automatically
    /// resets to `default` if `T`'s type or struct fields change.
    pub fn useState(self: *Context, comptime T: type, key: []const u8, default: T) *T {
        const pctx = self.platform_ctx orelse @panic("ui.Context.platform_ctx must be set to call useState");
        return pctx.useState(T, key, default);
    }

    /// Latches `val` (`bool`, integers, enums, floats up to 8 bytes) during `Pass.input` and replays
    /// the exact recorded value during `Pass.paint`, preventing mid-frame state mutations in `.input`
    /// from causing layout branch divergence in `.paint`.
    pub fn latch(self: *Context, comptime T: type, val: T) T {
        return self.latch_tape.latch(T, self.pass, val);
    }

    /// Memoizes a per-frame computed value of type `T` in `self.arena` across `Pass.input` and `Pass.paint`.
    /// Keyed by the FNV-1a hash of the current `id_stack` + `key`.
    pub fn useFrameCache(
        self: *Context,
        comptime T: type,
        key: []const u8,
        ctx: anytype,
        comptime computeFn: anytype,
    ) *T {
        const resolved = self.resolveIdAndLabel(key);
        return self.frame_cache.getOrCompute(T, self.arena, resolved.wid, ctx, computeFn);
    }

    pub fn beginPass(
        self: *Context,
        pass: Pass,
        arena: std.mem.Allocator,
        canvas: Canvas,
        root_rect: c.sk_rect_t,
        mouse_x: f32,
        mouse_y: f32,
        mouse_down: bool,
        mouse_pressed: bool,
        mouse_released: bool,
    ) void {
        self.pass = pass;
        self.arena = arena;
        self.canvas = canvas;
        self.root_rect = root_rect;
        self.mouse_x = mouse_x;
        self.mouse_y = mouse_y;
        self.mouse_down = mouse_down;
        self.mouse_pressed = mouse_pressed;
        self.mouse_released = mouse_released;
        if (self.platform_ctx) |pctx| {
            self.scroll_dx = pctx.scroll_dx;
            self.scroll_dy = pctx.scroll_dy;
            self.magnify_delta = pctx.magnify_delta;
            self.mouse_click_count = if (pctx.mouse_click_count > 0) pctx.mouse_click_count else 1;
            self.mouse_shift = pctx.mouse_shift;
            self.right_mouse_down = pctx.right_mouse_down;
            self.right_mouse_pressed = pctx.right_mouse_pressed;
            self.right_mouse_released = pctx.right_mouse_released;
            self.key_events = pctx.keyEvents();
            self.text_input = pctx.textInput();
            pctx.resetScopes();
        }
        self.stack_len = 0;
        self.id_stack_len = 0;
        self.pass_rect_count = 0;
        self.in_overlay = false;

        if (pass == .input) {
            self.prev_hot_id = self.hot_id;
            self.prev_active_id = self.active_id;
            self.hot_id = 0;
            self.animating_this_frame = false;
            self.dirty_rect = null;
            self.damage_list.clear();
            self.clip_damage = null;
            self.latch_tape.resetForInput();
            self.frame_cache.clear();
            self.last_md_source_ptr = null;
            self.last_md_source_len = 0;
            self.last_md_blocks = &.{};
            self.md_cache_slots = @splat(.{});
            self.md_cache_next = 0;
            self.md_bubble_slots = @splat(.{});
            self.md_bubble_next = 0;
            self.vcd_cache_slots = @splat(.{});
            self.vcd_cache_tick = 0;
            self.pdf_cache_slots = @splat(.{});
            self.pdf_cache_tick = 0;
            self.last_diff_source_ptr = null;
            self.last_diff_source_len = 0;
            self.last_diff_data = null;
            self.deferred_text_menu_rect = null;
            self.deferred_text_menu_len = 0;
            self.deferred_text_menu_hot_idx = null;
            self.prev_dropdown_overlay_rect = self.dropdown_overlay_rect;
            self.dropdown_overlay_rect = null;
            self.blocking_overlay_rect = null;
            self.blocking_overlay_count = 0;
            self.retained_overlay_count = self.frame_registered_overlay_count;
            for (0..self.frame_registered_overlay_count) |ov_i| {
                self.retained_overlay_rects[ov_i] = self.frame_registered_overlays[ov_i];
            }
            self.frame_registered_overlay_count = 0;
        } else {
            self.latch_tape.rewindForPaint();
            self.deferred_text_menu_rect = null;
            self.deferred_text_menu_len = 0;
            self.deferred_text_menu_hot_idx = null;
        }

        self.pushContainer(root_rect, .{
            .direction = .column,
            .padding = Padding.all(0),
            .gap = 0,
        });
        if (pass == .input) {
            if (self.prev_dropdown_overlay_rect) |prev_ov| {
                self.markDirty(Rect.outset(prev_ov, 8.0, 8.0));
            }
        }
    }

    pub fn endPass(self: *Context) void {
        std.debug.assert(self.stack_len == 1);
        std.debug.assert(self.id_stack_len == 0);
        if (self.pass == .input) {
            self.last_input_rect_count = self.pass_rect_count;
            if (!self.mouse_down) {
                self.active_id = 0;
            }
        } else {
            if (self.deferred_text_menu_rect) |m_rect| {
                self.paintDeferredTextContextMenu(
                    m_rect,
                    self.deferred_text_menu_items[0..self.deferred_text_menu_len],
                    self.deferred_text_menu_hot_idx,
                );
            }
            self.last_paint_rect_count = self.pass_rect_count;
        }
        self.stack_len = 0;
    }

    /// Backwards-compatible single-pass helper for simple tests.
    pub fn beginFrame(
        self: *Context,
        arena: std.mem.Allocator,
        canvas: Canvas,
        root_rect: c.sk_rect_t,
        mouse_x: f32,
        mouse_y: f32,
        mouse_down: bool,
        mouse_pressed: bool,
        mouse_released: bool,
    ) void {
        self.beginPass(.input, arena, canvas, root_rect, mouse_x, mouse_y, mouse_down, mouse_pressed, mouse_released);
    }

    pub fn endFrame(self: *Context) void {
        self.endPass();
    }

    pub fn markDirty(self: *Context, rect: c.sk_rect_t) void {
        const clamped = self.clampToActiveScrollViewport(Rect.outset(rect, 3.0, 3.0));
        if (clamped.right <= clamped.left or clamped.bottom <= clamped.top) return;

        self.damage_list.add(clamped);
        if (self.dirty_rect) |existing| {
            self.dirty_rect = Rect.unionRect(existing, clamped);
        } else {
            self.dirty_rect = clamped;
        }
    }

    /// Marks the entire window root rectangle dirty (e.g. when switching tabs or mutating shared state).
    pub fn invalidateWindow(self: *Context) void {
        if (self.pass == .input) {
            self.dirty_rect = self.root_rect;
            self.damage_list.clear();
            self.damage_list.add(self.root_rect);
        }
    }

    /// Returns the sum of damaged rectangle areas in `damage_list` (or `dirty_rect` area).
    pub fn dirtyArea(self: *const Context) f32 {
        if (self.damage_list.len > 0) {
            return self.damage_list.totalArea();
        }
        if (self.dirty_rect) |d| {
            return Rect.area(d);
        }
        return 0.0;
    }

    pub fn shouldPaint(self: *const Context, rect: c.sk_rect_t) bool {
        if (self.pass != .paint) return false;
        const visible = self.clampToActiveScrollViewport(rect);
        if (visible.right <= visible.left or visible.bottom <= visible.top) return false;
        if (self.damage_list.len > 0 and !self.damage_list.intersects(visible)) {
            return false;
        }
        if (self.clip_damage) |dmg| {
            return Rect.intersects(visible, dmg);
        }
        return true;
    }

    /// Clips `self.canvas` to the exact union of dirty rectangles in `self.damage_list`
    /// (or `fallback_rect` when `damage_list` has a single rect) so container and scroll-panel
    /// background fills never overwrite undamaged pixels between disjoint damage regions.
    pub fn clipCanvasToDamage(self: *Context, fallback_rect: c.sk_rect_t) void {
        if (self.damage_list.len > 1) {
            if (skia.PathBuilder.init()) |pb| {
                defer pb.deinit();
                for (self.damage_list.rects[0..self.damage_list.len]) |d| {
                    pb.addRect(d);
                }
                if (pb.detach()) |path| {
                    defer path.deinit();
                    self.canvas.clipPath(path, .intersect, false);
                    return;
                } else |_| {}
            } else |_| {}
        }
        self.canvas.clipRect(fallback_rect, .intersect, false);
    }

    fn clampToActiveScrollViewport(self: *const Context, rect: c.sk_rect_t) c.sk_rect_t {
        var r = rect;
        var idx = self.stack_len;
        while (idx > 0) {
            idx -= 1;
            const container = &self.stack[idx];
            if (container.is_scroll) {
                r.left = @max(r.left, container.bounds.left);
                r.top = @max(r.top, container.bounds.top);
                r.right = @min(r.right, container.bounds.right);
                r.bottom = @min(r.bottom, container.bounds.bottom);
            }
        }
        return r;
    }

    /// Returns `true` when `rect` intersects the active scroll viewport (or window viewport).
    pub fn isRectInViewport(self: *const Context, rect: c.sk_rect_t) bool {
        const visible = self.clampToActiveScrollViewport(rect);
        return visible.right > visible.left and visible.bottom > visible.top;
    }

    /// Returns the vertical `[top, bottom]` bounds of the active scroll viewport (or root viewport).
    pub fn activeViewportY(self: *const Context) struct { top: f32, bottom: f32 } {
        var top: f32 = self.root_rect.top;
        var bottom: f32 = self.root_rect.bottom;
        var idx = self.stack_len;
        while (idx > 0) {
            idx -= 1;
            const container = &self.stack[idx];
            if (container.is_scroll) {
                top = @max(top, container.bounds.top);
                bottom = @min(bottom, container.bounds.bottom);
            }
        }
        return .{ .top = top, .bottom = bottom };
    }

    /// Returns the vertical `y` position where the next layout item in the current container will start.
    pub fn nextCursorY(self: *const Context) f32 {
        const top = &self.stack[self.stack_len - 1];
        const gap = if (top.item_count > 0 and top.direction == .column) top.gap else 0.0;
        return top.cursor_y + gap;
    }

    /// Computes the visible index slice `[first, end)` and top/bottom `spacer` heights for a uniform
    /// vertical list of `item_count` rows with step `item_step_y` inside the active scroll viewport.
    pub fn computeVirtualRange(
        self: *const Context,
        item_count: usize,
        item_step_y: f32,
        overscan: usize,
    ) VirtualRange {
        if (item_count == 0 or item_step_y <= 0.0) {
            return .{ .first = 0, .end = 0, .top_spacer_h = 0.0, .bottom_spacer_h = 0.0 };
        }
        const vp = self.activeViewportY();
        const list_start_y = self.nextCursorY();
        const rel_top = vp.top - list_start_y;
        const rel_bottom = vp.bottom - list_start_y;

        const raw_first: usize = if (rel_top > 0.0)
            @min(item_count, @as(usize, @intFromFloat(@floor(rel_top / item_step_y))))
        else
            0;
        const first: usize = raw_first -| overscan;

        const raw_end: usize = if (rel_bottom > 0.0)
            @min(item_count, @as(usize, @intFromFloat(@ceil(rel_bottom / item_step_y))))
        else
            0;
        const end: usize = @min(item_count, @max(first, raw_end + overscan));

        const container_gap: f32 = if (self.stack_len > 0 and self.stack[self.stack_len - 1].direction == .column)
            self.stack[self.stack_len - 1].gap
        else
            0.0;

        const top_spacer_h: f32 = if (first > 0)
            @max(0.0, @as(f32, @floatFromInt(first)) * item_step_y - container_gap)
        else
            0.0;
        const rem_count: usize = item_count - end;
        const bottom_spacer_h: f32 = if (rem_count > 0)
            @max(0.0, @as(f32, @floatFromInt(rem_count)) * item_step_y - container_gap)
        else
            0.0;

        return .{
            .first = first,
            .end = end,
            .top_spacer_h = top_spacer_h,
            .bottom_spacer_h = bottom_spacer_h,
        };
    }

    pub fn fmt(self: *Context, comptime format: []const u8, args: anytype) []const u8 {
        return std.fmt.allocPrint(self.arena, format, args) catch "";
    }

    fn drawBoxBorder(self: *Context, rect: c.sk_rect_t, style: BoxStyle) void {
        if (style.border_width <= 0 or style.border_color == Color.transparent or !style.border_edges.isAny()) return;
        if (style.border_edges.isAll()) {
            self.paint.setStyle(.stroke);
            self.paint.setStrokeWidth(style.border_width);
            self.paint.setColor(style.border_color);
            if (style.corner_radius > 0) {
                self.canvas.drawRoundRect(rect, style.corner_radius, style.corner_radius, self.paint);
            } else {
                self.canvas.drawRect(rect, self.paint);
            }
            return;
        }
        const bw = style.border_width;
        self.paint.setStyle(.fill);
        self.paint.setColor(style.border_color);
        if (style.border_edges.top) {
            self.canvas.drawRect(Rect.xywh(rect.left, rect.top, rect.right - rect.left, bw), self.paint);
        }
        if (style.border_edges.bottom) {
            self.canvas.drawRect(Rect.xywh(rect.left, rect.bottom - bw, rect.right - rect.left, bw), self.paint);
        }
        if (style.border_edges.left) {
            self.canvas.drawRect(Rect.xywh(rect.left, rect.top, bw, rect.bottom - rect.top), self.paint);
        }
        if (style.border_edges.right) {
            self.canvas.drawRect(Rect.xywh(rect.right - bw, rect.top, bw, rect.bottom - rect.top), self.paint);
        }
    }

    pub fn pushContainer(self: *Context, rect: c.sk_rect_t, style: BoxStyle) void {
        if (self.shouldPaint(rect)) {
            if (style.bg_color != Color.transparent) {
                self.paint.setStyle(.fill);
                self.paint.setColor(style.bg_color);
                if (style.corner_radius > 0) {
                    self.canvas.drawRoundRect(rect, style.corner_radius, style.corner_radius, self.paint);
                } else {
                    self.canvas.drawRect(rect, self.paint);
                }
            }

            self.drawBoxBorder(rect, style);
        }

        const content = c.sk_rect_t{
            .left = rect.left + style.padding.left,
            .top = rect.top + style.padding.top,
            .right = @max(rect.left + style.padding.left, rect.right - style.padding.right),
            .bottom = @max(rect.top + style.padding.top, rect.bottom - style.padding.bottom),
        };

        std.debug.assert(self.stack_len < self.stack.len);
        self.stack[self.stack_len] = .{
            .bounds = rect,
            .content_bounds = content,
            .cursor_x = content.left,
            .cursor_y = content.top,
            .max_child_right = content.left,
            .max_child_bottom = content.top,
            .direction = style.direction,
            .gap = style.gap,
            .item_count = 0,
            .style = style,
        };
        self.stack_len += 1;
    }

    pub fn beginBox(self: *Context, width: f32, height: f32, style: BoxStyle) c.sk_rect_t {
        const rect = self.nextRect(width, height);
        self.pushContainer(rect, style);
        if (style.direction == .row_wrap and height <= 0) {
            self.stack[self.stack_len - 1].auto_height = true;
        }
        return rect;
    }

    pub fn endBox(self: *Context) void {
        if (self.stack_len > 1) {
            const child = self.stack[self.stack_len - 1];
            self.stack_len -= 1;
            const parent = &self.stack[self.stack_len - 1];
            const child_content_bottom = if (child.direction == .row_wrap)
                @max(child.max_child_bottom, child.cursor_y + child.row_line_max_h) + child.style.padding.bottom
            else
                child.max_child_bottom + child.style.padding.bottom;
            const effective_bottom = if (child.auto_height)
                child_content_bottom
            else
                @max(child.bounds.bottom, child_content_bottom);
            parent.max_child_right = @max(parent.max_child_right, @max(child.bounds.right, child.max_child_right + child.style.padding.right));
            parent.max_child_bottom = @max(parent.max_child_bottom, effective_bottom);
            if (parent.direction == .column and (child.auto_height or effective_bottom > child.bounds.bottom)) {
                parent.cursor_y = effective_bottom;
            } else if (parent.direction == .row_wrap) {
                parent.row_line_max_h = @max(parent.row_line_max_h, effective_bottom - child.bounds.top);
            }
        }
    }

    // ========================================================================
    // Scrollable Container (`beginScrollBox` / `endScrollBox`)
    // ========================================================================

    /// Returns the content-relative vertical scroll offset (`scroll_y`) that aligns `rect_top`
    /// with the top of the nearest enclosing scrollable container's content area.
    pub fn scrollOffsetForRectTop(self: *const Context, rect_top: f32) f32 {
        var i: usize = self.stack_len;
        while (i > 0) {
            i -= 1;
            const c_item = self.stack[i];
            if (c_item.is_scroll) {
                if (c_item.scroll_state) |ss| {
                    const unpainted_top = c_item.content_bounds.top - ss.scroll_y;
                    return @max(0.0, rect_top - unpainted_top);
                }
            }
        }
        return 0.0;
    }

    /// Begins a 2D (vertically and horizontally) scrollable container box with hardware scissor
    /// clipping, trackpad/mouse-wheel scrolling (`scroll_dx` / `scroll_dy`), and interactive
    /// draggable vertical and horizontal scrollbar thumbs.
    /// Scroll offsets and content dimensions are automatically persisted via `useState`.
    pub fn beginScrollBox(
        self: *Context,
        scroll_id_str: []const u8,
        width: f32,
        height: f32,
        style: BoxStyle,
    ) c.sk_rect_t {
        const scroll_state: *ScrollState = if (self.platform_ctx != null)
            self.useState(ScrollState, scroll_id_str, .{})
        else
            &self.fallback_scroll_state;
        return self.beginScrollBoxWithState(scroll_id_str, scroll_state, width, height, style);
    }

    /// Begins a 2D scrollable container box backed by an explicit caller-owned `scroll_state`
    /// (for example, per-buffer `ScrollState` stored inside `CodeEditorBuffer`).
    pub fn beginScrollBoxWithState(
        self: *Context,
        scroll_id_str: []const u8,
        scroll_state: *ScrollState,
        width: f32,
        height: f32,
        style: BoxStyle,
    ) c.sk_rect_t {
        const rect = self.nextRect(width, height);
        const scroll_wid = self.resolveIdAndLabel(scroll_id_str).wid;

        const raw_viewport_w = @max(1.0, (rect.right - rect.left) - style.padding.left - style.padding.right);
        const raw_viewport_h = @max(1.0, (rect.bottom - rect.top) - style.padding.top - style.padding.bottom);
        const compact_strip = (rect.bottom - rect.top) <= 40.0;
        const allow_h_scroll = style.allow_h_scroll;

        const v_scrollbar_gutter: f32 = if (!compact_strip and scroll_state.content_height > raw_viewport_h + 0.5) 8.0 else 0.0;
        const h_scrollbar_gutter: f32 = if (allow_h_scroll and !compact_strip and scroll_state.content_width > raw_viewport_w + 0.5) 8.0 else 0.0;

        const viewport_w = @max(1.0, raw_viewport_w - v_scrollbar_gutter);
        const viewport_h = @max(1.0, raw_viewport_h - h_scrollbar_gutter);
        scroll_state.viewport_width = viewport_w;
        scroll_state.viewport_height = viewport_h;
        const max_scroll_x = if (allow_h_scroll) @max(0.0, scroll_state.content_width - viewport_w) else 0.0;
        const max_scroll_y = @max(0.0, scroll_state.content_height - viewport_h);

        // Handle mouse-wheel / trackpad 2D scrolling during the `.input` pass when hovered
        if (self.pass == .input) {
            const clamped_initial_x = std.math.clamp(scroll_state.scroll_x, 0.0, max_scroll_x);
            if (clamped_initial_x != scroll_state.scroll_x) {
                scroll_state.scroll_x = clamped_initial_x;
                self.markDirty(rect);
            }

            const clamped_initial_y = std.math.clamp(scroll_state.scroll_y, 0.0, max_scroll_y);
            if (clamped_initial_y != scroll_state.scroll_y) {
                scroll_state.scroll_y = clamped_initial_y;
                self.markDirty(rect);
            }

            if (self.isHovered(rect)) {
                const snapped = scroll_state.snapDelta(self.scroll_dx, self.scroll_dy);
                if (snapped.dx != 0 and max_scroll_x > 0) {
                    const next_scroll_x = std.math.clamp(scroll_state.scroll_x - snapped.dx, 0.0, max_scroll_x);
                    if (next_scroll_x != scroll_state.scroll_x) {
                        scroll_state.scroll_x = next_scroll_x;
                        self.markDirty(rect);
                    }
                } else if (snapped.dy != 0 and (max_scroll_y == 0 or self.mouse_shift) and max_scroll_x > 0) {
                    // If container only overflows horizontally or Shift is held, vertical wheel pans horizontally
                    const next_scroll_x = std.math.clamp(scroll_state.scroll_x - snapped.dy, 0.0, max_scroll_x);
                    if (next_scroll_x != scroll_state.scroll_x) {
                        scroll_state.scroll_x = next_scroll_x;
                        self.markDirty(rect);
                    }
                }

                if (!self.mouse_shift and snapped.dy != 0 and max_scroll_y > 0) {
                    const next_scroll_y = std.math.clamp(scroll_state.scroll_y - snapped.dy, 0.0, max_scroll_y);
                    if (next_scroll_y != scroll_state.scroll_y) {
                        scroll_state.scroll_y = next_scroll_y;
                        self.markDirty(rect);
                    }
                }
            } else {
                scroll_state.decayAxisBias();
            }
        }

        // Draw panel background before clipping child content
        if (self.shouldPaint(rect) and style.bg_color != Color.transparent) {
            self.paint.setStyle(.fill);
            self.paint.setColor(style.bg_color);
            if (style.corner_radius > 0) {
                self.canvas.drawRoundRect(rect, style.corner_radius, style.corner_radius, self.paint);
            } else {
                self.canvas.drawRect(rect, self.paint);
            }
        }

        var save_count: i32 = 0;
        if (self.pass == .paint) {
            save_count = self.canvas.save();
            // Clip child widgets to the inner viewport of the scroll container
            const inset = style.border_width;
            const clip_r = c.sk_rect_t{
                .left = rect.left + inset,
                .top = rect.top + inset,
                .right = rect.right - inset,
                .bottom = rect.bottom - inset,
            };
            self.canvas.clipRect(clip_r, .intersect, false);
        }

        const content = c.sk_rect_t{
            .left = rect.left + style.padding.left,
            .top = rect.top + style.padding.top,
            .right = @max(rect.left + style.padding.left, rect.right - style.padding.right - v_scrollbar_gutter),
            .bottom = @max(rect.top + style.padding.top, rect.bottom - style.padding.bottom - h_scrollbar_gutter),
        };

        const start_x = content.left - scroll_state.scroll_x;
        const start_y = content.top - scroll_state.scroll_y;

        std.debug.assert(self.stack_len < self.stack.len);
        self.stack[self.stack_len] = .{
            .bounds = rect,
            .content_bounds = content,
            .cursor_x = start_x,
            .cursor_y = start_y,
            .max_child_right = start_x,
            .max_child_bottom = start_y,
            .direction = style.direction,
            .gap = style.gap,
            .item_count = 0,
            .is_scroll = true,
            .style = style,
            .scroll_id = scroll_wid,
            .scroll_state = scroll_state,
            .canvas_save_count = save_count,
        };
        self.stack_len += 1;
        return rect;
    }

    /// Completes a scrollable container, updates its measured content width & height, processes
    /// vertical & horizontal scrollbar thumb dragging, and renders the scrollbar overlays + border.
    pub fn endScrollBox(self: *Context) void {
        if (self.stack_len <= 1) return;
        const container = self.stack[self.stack_len - 1];
        self.stack_len -= 1;

        if (!container.is_scroll) return;
        const scroll_state = container.scroll_state orelse return;
        const rect = container.bounds;
        const content = container.content_bounds;
        const style = container.style;

        // Compute total horizontal width & vertical height of all children laid out inside the scroll box
        const prev_w = scroll_state.content_width;
        const prev_h = scroll_state.content_height;
        const allow_h_scroll = style.allow_h_scroll;

        const unpainted_left = content.left - scroll_state.scroll_x;
        const viewport_w = @max(1.0, content.right - content.left);
        const measured_w = if (allow_h_scroll)
            @max(0.0, @max(container.cursor_x, container.max_child_right) - unpainted_left)
        else
            viewport_w;
        scroll_state.content_width = measured_w;
        scroll_state.viewport_width = viewport_w;

        const unpainted_top = content.top - scroll_state.scroll_y;
        const content_bottom = if (container.direction == .row_wrap)
            @max(container.max_child_bottom, container.cursor_y + container.row_line_max_h) + style.padding.bottom
        else
            @max(container.cursor_y, container.max_child_bottom);
        const measured_h = @max(0.0, content_bottom - unpainted_top);
        const viewport_h = @max(1.0, content.bottom - content.top);
        scroll_state.content_height = measured_h;
        scroll_state.viewport_height = viewport_h;

        if (self.pass == .input and (@abs(measured_w - prev_w) > 0.5 or @abs(measured_h - prev_h) > 0.5)) {
            self.markDirty(rect);
        }

        const max_scroll_x = if (allow_h_scroll) @max(0.0, measured_w - viewport_w) else 0.0;
        if (scroll_state.scroll_x > max_scroll_x) {
            scroll_state.scroll_x = max_scroll_x;
            if (self.pass == .input) self.markDirty(rect);
        }

        const max_scroll_y = @max(0.0, measured_h - viewport_h);
        if (scroll_state.scroll_y > max_scroll_y) {
            scroll_state.scroll_y = max_scroll_y;
            if (self.pass == .input) self.markDirty(rect);
        }

        const compact_strip = (rect.bottom - rect.top) <= 40.0;
        const has_v_scrollbar = !compact_strip and max_scroll_y > 0.5;
        const has_h_scrollbar = !compact_strip and max_scroll_x > 0.5;
        const track_margin: f32 = 8.0;
        const corner_reserve: f32 = if (has_v_scrollbar and has_h_scrollbar) 8.0 else 0.0;

        // 1. Vertical scrollbar track & thumb geometry
        const track_w: f32 = 5.0;
        const track_x = rect.right - track_w - 4.0;
        const track_top = rect.top + track_margin;
        const track_bottom = rect.bottom - track_margin - corner_reserve;
        const track_h = @max(16.0, track_bottom - track_top);

        const visible_ratio_y = std.math.clamp(viewport_h / @max(1.0, measured_h), 0.1, 1.0);
        const thumb_h = @max(24.0, track_h * visible_ratio_y);
        const scrollable_track_h = @max(1.0, track_h - thumb_h);
        const scroll_norm_y = if (max_scroll_y > 0) std.math.clamp(scroll_state.scroll_y / max_scroll_y, 0.0, 1.0) else 0.0;
        const thumb_y = track_top + scroll_norm_y * scrollable_track_h;

        const v_thumb_wid = container.scroll_id ^ 0x5C80_11BA;
        const v_thumb_hit_rect = Rect.xywh(track_x - 5.0, track_top, track_w + 9.0, track_h);

        // 2. Horizontal scrollbar track & thumb geometry
        const h_track_h: f32 = 5.0;
        const h_track_y = rect.bottom - h_track_h - 4.0;
        const h_track_left = rect.left + track_margin;
        const h_track_right = rect.right - track_margin - corner_reserve;
        const h_track_w = @max(16.0, h_track_right - h_track_left);

        const visible_ratio_x = std.math.clamp(viewport_w / @max(1.0, measured_w), 0.1, 1.0);
        const thumb_w = @max(24.0, h_track_w * visible_ratio_x);
        const scrollable_track_w = @max(1.0, h_track_w - thumb_w);
        const scroll_norm_x = if (max_scroll_x > 0) std.math.clamp(scroll_state.scroll_x / max_scroll_x, 0.0, 1.0) else 0.0;
        const thumb_x = h_track_left + scroll_norm_x * scrollable_track_w;

        const h_thumb_wid = container.scroll_id ^ 0x4853_C801;
        const h_thumb_hit_rect = Rect.xywh(h_track_left, h_track_y - 5.0, h_track_w, h_track_h + 9.0);

        if (self.pass == .input) {
            if (has_v_scrollbar) {
                const hovered = self.isHovered(v_thumb_hit_rect);
                if (hovered) {
                    self.hot_id = v_thumb_wid;
                    if (self.mouse_pressed) {
                        self.active_id = v_thumb_wid;
                        if (self.mouse_y >= thumb_y and self.mouse_y <= thumb_y + thumb_h) {
                            scroll_state.drag_grab_offset = self.mouse_y - thumb_y;
                        } else {
                            scroll_state.drag_grab_offset = thumb_h * 0.5;
                        }
                    }
                }

                const hover_changed = (hovered and self.prev_hot_id != v_thumb_wid) or (!hovered and self.prev_hot_id == v_thumb_wid);
                const active_changed = (self.active_id == v_thumb_wid and self.mouse_pressed) or
                    (self.prev_active_id == v_thumb_wid and self.mouse_released);
                if (hover_changed or active_changed) {
                    self.markDirty(v_thumb_hit_rect);
                }

                if (self.active_id == v_thumb_wid and self.mouse_down) {
                    const target_thumb_top = self.mouse_y - scroll_state.drag_grab_offset;
                    const drag_norm = std.math.clamp((target_thumb_top - track_top) / scrollable_track_h, 0.0, 1.0);
                    const new_scroll = drag_norm * max_scroll_y;
                    if (new_scroll != scroll_state.scroll_y) {
                        scroll_state.scroll_y = new_scroll;
                        self.markDirty(rect);
                    }
                }
            }

            if (has_h_scrollbar) {
                const hovered_h = self.isHovered(h_thumb_hit_rect);
                if (hovered_h) {
                    self.hot_id = h_thumb_wid;
                    if (self.mouse_pressed) {
                        self.active_id = h_thumb_wid;
                        if (self.mouse_x >= thumb_x and self.mouse_x <= thumb_x + thumb_w) {
                            scroll_state.drag_grab_offset_x = self.mouse_x - thumb_x;
                        } else {
                            scroll_state.drag_grab_offset_x = thumb_w * 0.5;
                        }
                    }
                }

                const hover_changed_h = (hovered_h and self.prev_hot_id != h_thumb_wid) or (!hovered_h and self.prev_hot_id == h_thumb_wid);
                const active_changed_h = (self.active_id == h_thumb_wid and self.mouse_pressed) or
                    (self.prev_active_id == h_thumb_wid and self.mouse_released);
                if (hover_changed_h or active_changed_h) {
                    self.markDirty(h_thumb_hit_rect);
                }

                if (self.active_id == h_thumb_wid and self.mouse_down) {
                    const target_thumb_left = self.mouse_x - scroll_state.drag_grab_offset_x;
                    const drag_norm_x = std.math.clamp((target_thumb_left - h_track_left) / scrollable_track_w, 0.0, 1.0);
                    const new_scroll_x = drag_norm_x * max_scroll_x;
                    if (new_scroll_x != scroll_state.scroll_x) {
                        scroll_state.scroll_x = new_scroll_x;
                        self.markDirty(rect);
                    }
                }
            }
        }

        if (self.pass == .paint) {
            self.canvas.restoreToCount(container.canvas_save_count);

            if (self.shouldPaint(rect)) {
                // Draw vertical scrollbar track & thumb
                if (has_v_scrollbar) {
                    self.paint.setStyle(.fill);
                    self.paint.setColor(Color.argb(60, 15, 23, 42));
                    self.canvas.drawRoundRect(Rect.xywh(track_x, track_top, track_w, track_h), 2.5, 2.5, self.paint);

                    const is_dragging = (self.active_id == v_thumb_wid and self.mouse_down);
                    const is_hovered = (self.hot_id == v_thumb_wid);
                    const thumb_color = if (is_dragging)
                        self.theme.accent
                    else if (is_hovered)
                        self.theme.accent_hover
                    else
                        Color.argb(145, 148, 163, 184);

                    self.paint.setColor(thumb_color);
                    self.canvas.drawRoundRect(Rect.xywh(track_x, thumb_y, track_w, thumb_h), 2.5, 2.5, self.paint);
                }

                // Draw horizontal scrollbar track & thumb
                if (has_h_scrollbar) {
                    self.paint.setStyle(.fill);
                    self.paint.setColor(Color.argb(60, 15, 23, 42));
                    self.canvas.drawRoundRect(Rect.xywh(h_track_left, h_track_y, h_track_w, h_track_h), 2.5, 2.5, self.paint);

                    const is_dragging_h = (self.active_id == h_thumb_wid and self.mouse_down);
                    const is_hovered_h = (self.hot_id == h_thumb_wid);
                    const thumb_color_h = if (is_dragging_h)
                        self.theme.accent
                    else if (is_hovered_h)
                        self.theme.accent_hover
                    else
                        Color.argb(145, 148, 163, 184);

                    self.paint.setColor(thumb_color_h);
                    self.canvas.drawRoundRect(Rect.xywh(thumb_x, h_track_y, thumb_w, h_track_h), 2.5, 2.5, self.paint);
                }

                // Draw container border on top of clipped content
                self.drawBoxBorder(rect, style);
            }
        }
    }

    pub fn availableWidth(self: *const Context) f32 {
        const top = &self.stack[self.stack_len - 1];
        return switch (top.direction) {
            .column => top.content_bounds.right - top.content_bounds.left,
            .row, .row_wrap => blk: {
                const gap = if (top.item_count > 0) top.gap else 0.0;
                break :blk @max(0, top.content_bounds.right - top.cursor_x - gap);
            },
        };
    }

    pub fn availableHeight(self: *const Context) f32 {
        const top = &self.stack[self.stack_len - 1];
        return switch (top.direction) {
            .column => blk: {
                const gap = if (top.item_count > 0) top.gap else 0.0;
                break :blk @max(0, top.content_bounds.bottom - top.cursor_y - gap);
            },
            .row, .row_wrap => top.content_bounds.bottom - top.content_bounds.top,
        };
    }

    pub fn resolveWidth(self: *const Context, w: Size) f32 {
        const top = &self.stack[self.stack_len - 1];
        const parent_total = top.content_bounds.right - top.content_bounds.left;
        return w.resolve(self.availableWidth(), parent_total, top.gap);
    }

    pub fn resolveHeight(self: *const Context, h: Size) f32 {
        const top = &self.stack[self.stack_len - 1];
        const parent_total = top.content_bounds.bottom - top.content_bounds.top;
        return h.resolve(self.availableHeight(), parent_total, top.gap);
    }

    pub fn resolveSize(self: *const Context, s: Size, is_width: bool) f32 {
        return if (is_width) self.resolveWidth(s) else self.resolveHeight(s);
    }

    // ========================================================================
    // Declarative Container Guards (`box`, `row`, `column`, `flowWrap`, `scrollPanel`)
    // ========================================================================

    pub fn box(self: *Context, cfg: ContainerConfig) BoxGuard {
        const dir = cfg.direction orelse .column;
        const style = cfg.toBoxStyle(dir, self.theme);
        const w = self.resolveWidth(cfg.w);
        const h = if (dir == .row_wrap and cfg.h != .px) 0.0 else self.resolveHeight(cfg.h);
        const rect = self.beginBox(w, h, style);
        return .{ .ctx = self, .rect = rect };
    }

    pub fn row(self: *Context, cfg: ContainerConfig) BoxGuard {
        var r_cfg = cfg;
        if (r_cfg.direction == null) r_cfg.direction = .row;
        return self.box(r_cfg);
    }

    pub fn column(self: *Context, cfg: ContainerConfig) BoxGuard {
        var c_cfg = cfg;
        if (c_cfg.direction == null) c_cfg.direction = .column;
        return self.box(c_cfg);
    }

    pub fn flowWrap(self: *Context, cfg: ContainerConfig) ScopedContainer {
        var fw_cfg = cfg;
        if (fw_cfg.direction == null) fw_cfg.direction = .row_wrap;
        return self.box(fw_cfg);
    }

    pub fn scrollPanel(self: *Context, scroll_id_str: []const u8, cfg: ContainerConfig) ScrollGuard {
        const dir = cfg.direction orelse .column;
        const style = cfg.toBoxStyle(dir, self.theme);
        const w = self.resolveWidth(cfg.w);
        const h = self.resolveHeight(cfg.h);
        const rect = self.beginScrollBox(scroll_id_str, w, h, style);
        return .{ .ctx = self, .rect = rect };
    }

    /// Registers (or clears) a floating overlay rectangle so background widgets underneath it
    /// do not receive hover/click events during `.input`.
    pub fn setBlockingOverlay(self: *Context, rect: ?c.sk_rect_t) void {
        if (rect) |r| {
            if (self.blocking_overlay_count < self.blocking_overlay_rects.len) {
                self.blocking_overlay_rects[self.blocking_overlay_count] = r;
                self.blocking_overlay_count += 1;
            }
            self.blocking_overlay_rect = if (self.blocking_overlay_rect) |existing|
                Rect.unionRect(existing, r)
            else
                r;
        } else {
            self.blocking_overlay_rect = null;
            self.blocking_overlay_count = 0;
        }
    }

    /// Returns `true` when `(x, y)` is inside any active blocking or retained overlay rectangle
    /// while the caller is outside an `overlayBox`.
    pub fn isBlockedByOverlay(self: *const Context, x: f32, y: f32) bool {
        return overlays_mod.isBlockedByOverlay(self, x, y);
    }

    /// Returns `true` during `Pass.input` when a mouse press occurred outside all of the provided `rects`.
    /// Useful for dismissing open popovers, dropdown menus, or flyouts.
    pub fn clickedOutside(self: *const Context, rects: []const c.sk_rect_t) bool {
        if (self.pass != .input or !self.mouse_pressed) return false;
        for (rects) |r| {
            if (self.mouse_x >= r.left and self.mouse_x <= r.right and
                self.mouse_y >= r.top and self.mouse_y <= r.bottom)
            {
                return false;
            }
        }
        return true;
    }

    /// Begins a floating overlay container at `rect` on top of the current layout without
    /// shifting or affecting parent layout cursors.
    pub fn overlayBox(self: *Context, rect: c.sk_rect_t, cfg: ContainerConfig) OverlayGuard {
        self.in_overlay = true;
        if (self.pass == .input and self.frame_registered_overlay_count < self.frame_registered_overlays.len) {
            self.frame_registered_overlays[self.frame_registered_overlay_count] = rect;
            self.frame_registered_overlay_count += 1;
        }
        const dir = cfg.direction orelse .column;
        const style = cfg.toBoxStyle(dir, self.theme);

        if (self.shouldPaint(Rect.outset(rect, 6.0, 6.0))) {
            self.paint.setStyle(.fill);
            self.paint.setColor(Color.argb(85, 2, 6, 23));
            self.canvas.drawRoundRect(Rect.outset(rect, 4.0, 4.0), style.corner_radius + 3.0, style.corner_radius + 3.0, self.paint);
            self.paint.setColor(Color.argb(135, 2, 6, 23));
            self.canvas.drawRoundRect(Rect.outset(rect, 1.5, 1.5), style.corner_radius + 1.0, style.corner_radius + 1.0, self.paint);
        }

        self.pushContainer(rect, style);
        return .{ .ctx = self, .rect = rect };
    }

    /// Computes a centered floating modal rectangle anchored at `top_y` within `win_w`.
    pub fn topCenteredOverlayRect(
        win_w: f32,
        top_y: f32,
        min_w: f32,
        max_w: f32,
        width_ratio: f32,
        height: f32,
    ) c.sk_rect_t {
        const w = std.math.clamp(win_w * width_ratio, min_w, @min(max_w, @max(min_w, win_w - 32.0)));
        const x = @floor((win_w - w) * 0.5);
        return Rect.xywh(x, top_y, w, height);
    }

    /// Returns `true` during `Pass.input` if the user pressed the mouse below `min_y` and outside `overlay_rect`.
    pub fn isClickedOutsideOverlay(self: *const Context, overlay_rect: c.sk_rect_t, min_y: f32) bool {
        if (self.pass != .input or !self.mouse_pressed or self.mouse_y <= min_y) return false;
        return self.mouse_x < overlay_rect.left or self.mouse_x > overlay_rect.right or
            self.mouse_y < overlay_rect.top or self.mouse_y > overlay_rect.bottom;
    }

    /// Returns `true` during `Pass.input` when a right mouse press occurred inside `rect`.
    pub fn rightClicked(self: *Context, rect: c.sk_rect_t) bool {
        if (self.pass != .input or !self.right_mouse_pressed) return false;
        if (!self.isHovered(rect)) return false;
        self.markDirty(rect);
        return true;
    }

    /// Computes a viewport-clamped floating context menu rectangle anchored near `(anchor_x, anchor_y)`.
    pub fn contextMenuRect(
        self: *const Context,
        anchor_x: f32,
        anchor_y: f32,
        width: f32,
        items: []const ContextMenuItem,
    ) c.sk_rect_t {
        var total_h: f32 = 8.0; // 4pt top + 4pt bottom padding
        for (items) |item| {
            total_h += if (item.separator) 7.0 else 25.0;
        }
        const win_l = self.root_rect.left;
        const win_t = self.root_rect.top;
        const win_r = self.root_rect.right;
        const win_b = self.root_rect.bottom;
        const max_x = @max(win_l + 4.0, win_r - width - 6.0);
        const max_y = @max(win_t + 4.0, win_b - total_h - 6.0);
        const x = std.math.clamp(anchor_x, win_l + 4.0, max_x);
        const y = std.math.clamp(anchor_y, win_t + 4.0, max_y);
        return Rect.xywh(x, y, width, total_h);
    }

    /// Renders a single item or horizontal separator inside a `contextMenu` overlay container.
    pub fn contextMenuItem(self: *Context, item: ContextMenuItem) bool {
        if (item.separator) {
            const r = self.nextRect(0, 7.0);
            if (self.shouldPaint(r)) {
                const y = @floor((r.top + r.bottom) * 0.5);
                self.paint.setStyle(.fill);
                self.paint.setColor(Color.argb(65, 110, 118, 129));
                self.canvas.drawRect(Rect.xywh(r.left + 6.0, y, @max(1.0, (r.right - r.left) - 12.0), 1.0), self.paint);
            }
            return false;
        }

        const resolved = self.resolveIdAndLabel(item.label);
        const r = self.nextRect(0, 25.0);
        const clicked = if (item.enabled) self.trackInteraction(resolved.wid, r, r) else false;

        if (self.shouldPaint(r)) {
            const hovered = item.enabled and (self.hot_id == resolved.wid);
            if (hovered) {
                self.paint.setStyle(.fill);
                self.paint.setColor(if (item.danger) Color.argb(45, 248, 81, 73) else Color.rgb(31, 111, 235));
                self.canvas.drawRoundRect(r, 4.5, 4.5, self.paint);
            }

            const save_cnt = self.canvas.save();
            defer self.canvas.restoreToCount(save_cnt);
            self.canvas.clipRect(Rect.ltrb(r.left + 4.0, r.top, r.right - 4.0, r.bottom), .intersect, false);

            const by = r.top + 17.0;
            self.paint.setStyle(.fill);
            const label_col = if (!item.enabled)
                Color.rgb(92, 100, 112)
            else if (item.danger)
                (if (hovered) Color.rgb(255, 123, 114) else Color.rgb(248, 81, 73))
            else if (hovered)
                Color.rgb(255, 255, 255)
            else
                Color.rgb(218, 226, 235);

            self.paint.setColor(label_col);
            self.drawTextCached(self.font_body, resolved.display, r.left + 10.0, by);

            if (item.shortcut.len > 0) {
                const sw = self.measureTextCached(self.font_mono, item.shortcut);
                self.paint.setColor(if (!item.enabled)
                    Color.rgb(72, 79, 88)
                else if (hovered)
                    Color.argb(215, 255, 255, 255)
                else
                    Color.rgb(125, 133, 144));
                self.drawTextCached(self.font_mono, item.shortcut, r.right - sw - 10.0, by - 0.5);
            }
        }

        if (clicked) self.invalidateWindow();
        return clicked;
    }

    /// Renders a floating right-click context menu when `state.open` is true and returns the
    /// 0-based index of the clicked `ContextMenuItem` (automatically closing `state`), or `null`.
    /// Preserves strict two-phase layout determinism (`last_input_rect_count == last_paint_rect_count`)
    /// by resolving dismissal and selection before pushing the `overlayBox` container in `Pass.input`.
    pub fn contextMenu(
        self: *Context,
        menu_id_str: []const u8,
        state: *ContextMenuState,
        width: f32,
        items: []const ContextMenuItem,
    ) ?usize {
        if (!state.open or items.len == 0) return null;

        const menu_rect = self.contextMenuRect(state.anchor_x, state.anchor_y, width, items);

        if (self.pass == .input) {
            if (state.opened_this_frame) {
                state.opened_this_frame = false;
                self.invalidateWindow();
            } else {
                for (self.key_events) |kev| {
                    if (kev.key == .escape) {
                        state.close();
                        self.invalidateWindow();
                        return null;
                    }
                }
                const mouse_inside = (self.mouse_x >= menu_rect.left and self.mouse_x <= menu_rect.right and
                    self.mouse_y >= menu_rect.top and self.mouse_y <= menu_rect.bottom);
                if ((self.mouse_pressed or self.right_mouse_pressed) and !mouse_inside) {
                    state.close();
                    self.invalidateWindow();
                    return null;
                }
                if (self.mouse_released and mouse_inside) {
                    var cur_y: f32 = menu_rect.top + 4.0;
                    const item_left = menu_rect.left + 4.0;
                    const item_right = menu_rect.right - 4.0;
                    for (items, 0..) |item, idx| {
                        const row_h: f32 = if (item.separator) 7.0 else 25.0;
                        if (!item.separator and item.enabled) {
                            if (self.mouse_x >= item_left and self.mouse_x <= item_right and
                                self.mouse_y >= cur_y and self.mouse_y <= cur_y + row_h)
                            {
                                state.close();
                                self.active_id = 0;
                                self.invalidateWindow();
                                return idx;
                            }
                        }
                        cur_y += row_h;
                    }
                }
            }
        }

        var scope = self.scopedId(menu_id_str);
        defer scope.end();

        var ov = self.overlayBox(menu_rect, .{
            .preset = .surface_card,
            .bg_color = Color.rgb(22, 27, 34),
            .border_color = Color.rgb(56, 68, 84),
            .corner_radius = 7.0,
            .padding = Padding.xy(4, 4),
            .gap = 0,
        });
        defer ov.end();

        for (items, 0..) |item, idx| {
            var item_id = self.scopedId(idx);
            defer item_id.end();
            _ = self.contextMenuItem(item);
        }

        return null;
    }

    fn paintDeferredTextContextMenu(
        self: *Context,
        menu_rect: c.sk_rect_t,
        items: []const ContextMenuItem,
        hot_idx: ?usize,
    ) void {
        if (!self.shouldPaint(Rect.outset(menu_rect, 6.0, 6.0))) return;

        const save_cnt = self.canvas.save();
        defer self.canvas.restoreToCount(save_cnt);

        // Drop shadow
        self.paint.setStyle(.fill);
        self.paint.setColor(Color.argb(85, 2, 6, 23));
        self.canvas.drawRoundRect(Rect.outset(menu_rect, 4.0, 4.0), 10.0, 10.0, self.paint);
        self.paint.setColor(Color.argb(135, 2, 6, 23));
        self.canvas.drawRoundRect(Rect.outset(menu_rect, 1.5, 1.5), 8.0, 8.0, self.paint);

        // Card fill & border
        self.paint.setColor(Color.rgb(22, 27, 34));
        self.canvas.drawRoundRect(menu_rect, 7.0, 7.0, self.paint);
        self.paint.setStyle(.stroke);
        self.paint.setStrokeWidth(1.0);
        self.paint.setColor(Color.rgb(56, 68, 84));
        self.canvas.drawRoundRect(menu_rect, 7.0, 7.0, self.paint);

        var cur_y: f32 = menu_rect.top + 4.0;
        const item_left = menu_rect.left + 4.0;
        const item_w = (menu_rect.right - menu_rect.left) - 8.0;

        for (items, 0..) |item, idx| {
            const row_h: f32 = if (item.separator) 7.0 else 25.0;
            const r = Rect.xywh(item_left, cur_y, item_w, row_h);
            if (item.separator) {
                const y = @floor((r.top + r.bottom) * 0.5);
                self.paint.setStyle(.fill);
                self.paint.setColor(Color.argb(65, 110, 118, 129));
                self.canvas.drawRect(Rect.xywh(r.left + 6.0, y, @max(1.0, item_w - 12.0), 1.0), self.paint);
            } else {
                const hovered = item.enabled and (hot_idx != null and hot_idx.? == idx);
                if (hovered) {
                    self.paint.setStyle(.fill);
                    self.paint.setColor(Color.rgb(31, 111, 235));
                    self.canvas.drawRoundRect(r, 4.5, 4.5, self.paint);
                }
                const by = r.top + 17.0;
                self.paint.setStyle(.fill);
                self.paint.setColor(if (!item.enabled)
                    Color.rgb(92, 100, 112)
                else if (hovered)
                    Color.rgb(255, 255, 255)
                else
                    Color.rgb(218, 226, 235));
                self.drawTextCached(self.font_body, item.label, r.left + 10.0, by);

                if (item.shortcut.len > 0) {
                    const sw = self.measureTextCached(self.font_mono, item.shortcut);
                    self.paint.setColor(if (!item.enabled)
                        Color.rgb(72, 79, 88)
                    else if (hovered)
                        Color.argb(215, 255, 255, 255)
                    else
                        Color.rgb(125, 133, 144));
                    self.drawTextCached(self.font_mono, item.shortcut, r.right - sw - 10.0, by - 0.5);
                }
            }
            cur_y += row_h;
        }
    }

    fn handleTextInputContextMenu(
        self: *Context,
        wid: WidgetId,
        st: *TextInputState,
        buf: []u8,
        len: *usize,
        allow_newlines: bool,
        allow_image_paste: bool,
    ) struct { changed: bool, visual_dirty: bool, pasted_image: ?platform.ClipboardImage = null } {
        if (!st.ctx_menu_open) return .{ .changed = false, .visual_dirty = false };

        const s = buf[0..@min(len.*, buf.len)];
        const has_sel = st.hasSelection();
        const items = [6]ContextMenuItem{
            .{ .label = "Undo", .shortcut = "Cmd+Z", .enabled = st.undo_valid },
            .{ .separator = true },
            .{ .label = "Cut", .shortcut = "Cmd+X", .enabled = has_sel },
            .{ .label = "Copy", .shortcut = "Cmd+C", .enabled = has_sel },
            .{ .label = "Paste", .shortcut = "Cmd+V", .enabled = true },
            .{ .label = "Select All", .shortcut = "Cmd+A", .enabled = s.len > 0 },
        };
        const menu_rect = self.contextMenuRect(st.ctx_menu_x, st.ctx_menu_y, 176.0, &items);

        var hot_idx: ?usize = null;
        var cur_y: f32 = menu_rect.top + 4.0;
        const item_left = menu_rect.left + 4.0;
        const item_right = menu_rect.right - 4.0;
        for (items, 0..) |item, idx| {
            const row_h: f32 = if (item.separator) 7.0 else 25.0;
            if (!item.separator and item.enabled) {
                if (self.mouse_x >= item_left and self.mouse_x <= item_right and
                    self.mouse_y >= cur_y and self.mouse_y <= cur_y + row_h)
                {
                    hot_idx = idx;
                }
            }
            cur_y += row_h;
        }

        if (self.pass == .input) {
            if (hot_idx) |hi| {
                self.hot_id = wid ^ (@as(u64, hi + 1) *% 0x9E37_79B9_7F4A_7C15);
                if (self.mouse_pressed) {
                    self.active_id = self.hot_id;
                }
            }
            self.markDirty(Rect.outset(menu_rect, 6.0, 6.0));

            if (st.ctx_menu_opened_this_frame) {
                st.ctx_menu_opened_this_frame = false;
                self.invalidateWindow();
                return .{ .changed = false, .visual_dirty = true };
            }

            for (self.key_events) |kev| {
                if (kev.key == .escape) {
                    st.ctx_menu_open = false;
                    self.invalidateWindow();
                    return .{ .changed = false, .visual_dirty = true };
                }
            }

            const mouse_inside = (self.mouse_x >= menu_rect.left and self.mouse_x <= menu_rect.right and
                self.mouse_y >= menu_rect.top and self.mouse_y <= menu_rect.bottom);
            if ((self.mouse_pressed or self.right_mouse_pressed) and !mouse_inside) {
                st.ctx_menu_open = false;
                self.invalidateWindow();
                return .{ .changed = false, .visual_dirty = true };
            }

            if (self.mouse_released and mouse_inside) {
                if (hot_idx) |hi| {
                    st.ctx_menu_open = false;
                    self.active_id = 0;
                    self.focused_id = wid;
                    self.invalidateWindow();
                    switch (hi) {
                        0 => {
                            const ch = st.performUndoSwap(buf, len);
                            return .{ .changed = ch, .visual_dirty = true };
                        },
                        2 => {
                            if (st.hasSelection()) {
                                if (self.platform_ctx) |pctx| {
                                    _ = pctx.setClipboardText(s[st.selStart()..st.selEnd()]);
                                }
                                st.saveUndo(buf, len.*);
                                const ch = st.deleteSelection(buf, len);
                                return .{ .changed = ch, .visual_dirty = true };
                            }
                        },
                        3 => {
                            if (st.hasSelection()) {
                                if (self.platform_ctx) |pctx| {
                                    _ = pctx.setClipboardText(s[st.selStart()..st.selEnd()]);
                                }
                            }
                            return .{ .changed = false, .visual_dirty = true };
                        },
                        4 => {
                            if (self.platform_ctx) |pctx| {
                                if (allow_image_paste) {
                                    if (pctx.getClipboardImageAlloc(self.arena)) |clip_img| {
                                        return .{ .changed = false, .visual_dirty = true, .pasted_image = clip_img };
                                    }
                                }
                                if (pctx.getClipboardTextAlloc(self.arena)) |clip| {
                                    st.saveUndo(buf, len.*);
                                    const ch = st.insertBytes(buf, len, clip, allow_newlines);
                                    return .{ .changed = ch, .visual_dirty = true };
                                }
                            }
                            return .{ .changed = false, .visual_dirty = true };
                        },
                        5 => {
                            st.selectAll(s.len);
                            return .{ .changed = false, .visual_dirty = true };
                        },
                        else => {},
                    }
                }
            }
        } else {
            self.deferred_text_menu_rect = menu_rect;
            self.deferred_text_menu_items = items;
            self.deferred_text_menu_len = items.len;
            self.deferred_text_menu_hot_idx = hot_idx;
        }
        return .{ .changed = false, .visual_dirty = false };
    }

    /// Consumes remaining available space minus `reserve_after` along the current container axis.
    pub fn fillSpacer(self: *Context, reserve_after: f32) void {
        const top = &self.stack[self.stack_len - 1];
        const avail = switch (top.direction) {
            .row, .row_wrap => self.availableWidth(),
            .column => self.availableHeight(),
        };
        if (avail > reserve_after + top.gap) {
            self.spacer(avail - reserve_after - top.gap);
        }
    }

    pub fn nextRect(self: *Context, width: f32, height: f32) c.sk_rect_t {
        self.pass_rect_count += 1;
        const top = &self.stack[self.stack_len - 1];
        const start_x = if (top.is_scroll and top.scroll_state != null)
            top.content_bounds.left - top.scroll_state.?.scroll_x
        else
            top.content_bounds.left;

        if (top.item_count > 0) {
            switch (top.direction) {
                .column => top.cursor_y += top.gap,
                .row, .row_wrap => top.cursor_x += top.gap,
            }
        }
        top.item_count += 1;

        if (top.direction == .row_wrap) {
            const line_w = @max(0.0, top.content_bounds.right - start_x);
            const req_w = if (width <= 0)
                @max(0.0, top.content_bounds.right - top.cursor_x)
            else if (!top.is_scroll or !top.style.allow_h_scroll)
                @min(width, line_w)
            else
                width;

            if (top.cursor_x > start_x and top.cursor_x + req_w > top.content_bounds.right) {
                top.cursor_x = start_x;
                top.cursor_y += top.row_line_max_h + top.gap;
                top.row_line_max_h = 0;
            }

            const avail_h_wrap = @max(0.0, top.content_bounds.bottom - top.cursor_y);
            const w_wrap = if (width <= 0) @max(0.0, top.content_bounds.right - top.cursor_x) else req_w;
            const h_wrap = if (height <= 0) avail_h_wrap else height;

            const rect_wrap = Rect.xywh(top.cursor_x, top.cursor_y, w_wrap, h_wrap);
            top.row_line_max_h = @max(top.row_line_max_h, h_wrap);
            top.max_child_right = @max(top.max_child_right, rect_wrap.right);
            top.max_child_bottom = @max(top.max_child_bottom, top.cursor_y + top.row_line_max_h);
            top.cursor_x += w_wrap;
            return rect_wrap;
        }

        const avail_w = switch (top.direction) {
            .column => top.content_bounds.right - top.content_bounds.left,
            .row, .row_wrap => @max(0, top.content_bounds.right - top.cursor_x),
        };
        const avail_h = switch (top.direction) {
            .column => @max(0, top.content_bounds.bottom - top.cursor_y),
            .row, .row_wrap => top.content_bounds.bottom - top.content_bounds.top,
        };

        const w = if (width <= 0)
            avail_w
        else if (!top.is_scroll or !top.style.allow_h_scroll)
            @min(width, avail_w)
        else
            width;
        const h = if (height <= 0) avail_h else height;

        const rect = Rect.xywh(top.cursor_x, top.cursor_y, w, h);
        top.max_child_right = @max(top.max_child_right, rect.right);
        top.max_child_bottom = @max(top.max_child_bottom, rect.bottom);
        switch (top.direction) {
            .column => top.cursor_y += h,
            .row, .row_wrap => top.cursor_x += w,
        }
        return rect;
    }

    pub fn spacer(self: *Context, size: f32) void {
        const top = &self.stack[self.stack_len - 1];
        switch (top.direction) {
            .column => _ = self.nextRect(1, size),
            .row, .row_wrap => _ = self.nextRect(size, 1),
        }
    }

    pub fn divider(self: *Context) void {
        const r = self.nextRect(0, 1);
        if (!self.shouldPaint(r)) return;
        self.paint.setStyle(.fill);
        self.paint.setColor(self.theme.border_subtle);
        self.canvas.drawRect(r, self.paint);
    }

    pub fn isHovered(self: *const Context, rect: c.sk_rect_t) bool {
        if (self.isBlockedByOverlay(self.mouse_x, self.mouse_y)) {
            return false;
        }
        const visible = self.clampToActiveScrollViewport(rect);
        if (visible.right <= visible.left or visible.bottom <= visible.top) return false;
        return self.mouse_x >= visible.left and
            self.mouse_x <= visible.right and
            self.mouse_y >= visible.top and
            self.mouse_y <= visible.bottom;
    }

    pub fn trackInteraction(self: *Context, wid: WidgetId, hit_rect: c.sk_rect_t, dirty_rect: c.sk_rect_t) bool {
        const hovered = self.isHovered(hit_rect);
        if (self.pass == .input) {
            if (hovered) {
                self.hot_id = wid;
                if (self.mouse_pressed) {
                    self.active_id = wid;
                }
            }
            const hover_changed = (hovered and self.prev_hot_id != wid) or (!hovered and self.prev_hot_id == wid);
            const active_changed = (self.active_id == wid and self.mouse_pressed) or
                (self.prev_active_id == wid and self.mouse_released);
            if (hover_changed or active_changed) {
                self.markDirty(dirty_rect);
            }
            return hovered and (self.active_id == wid) and self.mouse_released;
        }
        return false;
    }

    // ========================================================================
    // Widgets (Using Cached SkTextBlobs)
    // ========================================================================

    pub fn heading(self: *Context, text: []const u8) void {
        const r = self.nextRect(0, 30);
        if (!self.shouldPaint(r)) return;
        self.paint.setStyle(.fill);
        self.paint.setColor(self.theme.text_primary);
        self.drawTextCached(self.font_title, text, r.left, r.top + 23);
    }

    pub fn label(self: *Context, text: []const u8, color: ?u32) void {
        const top = &self.stack[self.stack_len - 1];
        const w: f32 = if (top.direction != .column) self.measureTextCached(self.font_body, text) + 4.0 else 0.0;
        const r = self.nextRect(w, 20);
        if (!self.shouldPaint(r)) return;
        self.paint.setStyle(.fill);
        self.paint.setColor(color orelse self.theme.text_muted);
        self.drawTextCached(self.font_body, text, r.left, r.top + 15);
    }

    pub fn monoLabel(self: *Context, text: []const u8, color: ?u32) void {
        const top = &self.stack[self.stack_len - 1];
        const w: f32 = if (top.direction != .column) self.measureTextCached(self.font_mono, text) + 4.0 else 0.0;
        const r = self.nextRect(w, 20);
        if (!self.shouldPaint(r)) return;
        self.paint.setStyle(.fill);
        self.paint.setColor(color orelse self.theme.text_primary);
        self.drawTextCached(self.font_mono, text, r.left, r.top + 15);
    }

    pub fn badge(self: *Context, text: []const u8, bg_color: u32, text_color: u32) void {
        const text_w = self.measureTextCached(self.font_mono, text);
        const r = self.nextRect(text_w + 20, 24);
        if (!self.shouldPaint(r)) return;

        self.paint.setStyle(.fill);
        self.paint.setColor(bg_color);
        self.canvas.drawRoundRect(r, 12, 12, self.paint);

        self.paint.setColor(text_color);
        self.drawTextCached(self.font_mono, text, r.left + 10, r.top + 16.5);
    }

    pub fn button(self: *Context, widget_id_str: []const u8, text: []const u8, width: f32) bool {
        const wid = id(widget_id_str);
        const r = self.nextRect(width, 36);
        const clicked = self.trackInteraction(wid, r, r);

        if (self.shouldPaint(r)) {
            const hovered = (self.hot_id == wid);
            const is_active = (self.active_id == wid and self.mouse_down);

            const bg = if (is_active and hovered)
                self.theme.accent_active
            else if (hovered)
                self.theme.accent_hover
            else
                self.theme.accent;

            self.paint.setStyle(.fill);
            self.paint.setColor(bg);
            self.canvas.drawRoundRect(r, 8, 8, self.paint);

            const text_w = self.measureTextCached(self.font_body, text);
            const text_x = r.left + @max(12.0, ((r.right - r.left) - text_w) * 0.5);
            self.paint.setColor(self.theme.text_primary);
            self.drawTextCached(self.font_body, text, text_x, r.top + 23);
        }

        if (clicked) self.invalidateWindow();
        return clicked;
    }

    pub fn tabButton(self: *Context, widget_id_str: []const u8, text: []const u8, selected: bool) bool {
        const wid = id(widget_id_str);
        const r = self.nextRect(0, 36);
        const clicked = self.trackInteraction(wid, r, r);

        if (self.shouldPaint(r)) {
            const hovered = (self.hot_id == wid);
            if (selected or hovered) {
                self.paint.setStyle(.fill);
                self.paint.setColor(if (selected) self.theme.bg_card else self.theme.control_bg);
                self.canvas.drawRoundRect(r, 8, 8, self.paint);
            }

            if (selected) {
                const bar = Rect.xywh(r.left + 4, r.top + 8, 3.5, (r.bottom - r.top) - 16);
                self.paint.setStyle(.fill);
                self.paint.setColor(self.theme.accent_hover);
                self.canvas.drawRoundRect(bar, 2, 2, self.paint);
            }

            self.paint.setStyle(.fill);
            self.paint.setColor(if (selected) self.theme.text_primary else self.theme.text_muted);
            self.drawTextCached(self.font_body, text, r.left + 16, r.top + 23);
        }

        if (clicked) self.invalidateWindow();
        return clicked;
    }

    pub fn toggle(self: *Context, widget_id_str: []const u8, text: []const u8, value: *bool) bool {
        const wid = id(widget_id_str);
        const r = self.nextRect(0, 30);
        const clicked = self.trackInteraction(wid, r, r);

        var changed = false;
        if (self.pass == .input and clicked) {
            value.* = !value.*;
            changed = true;
            self.invalidateWindow();
        }

        if (self.shouldPaint(r)) {
            self.paint.setStyle(.fill);
            self.paint.setColor(self.theme.text_primary);
            self.drawTextCached(self.font_body, text, r.left, r.top + 20);

            const pill_w: f32 = 42;
            const pill_h: f32 = 22;
            const pill_x = r.right - pill_w;
            const pill_y = r.top + 4;
            const pill_rect = Rect.xywh(pill_x, pill_y, pill_w, pill_h);

            self.paint.setColor(if (value.*) self.theme.accent else self.theme.control_bg);
            self.canvas.drawRoundRect(pill_rect, pill_h * 0.5, pill_h * 0.5, self.paint);

            const knob_x = if (value.*) pill_x + pill_w - 11 else pill_x + 11;
            const knob_y = pill_y + pill_h * 0.5;
            self.paint.setColor(Color.white);
            self.canvas.drawCircle(knob_x, knob_y, 8.0, self.paint);
        }

        return changed;
    }

    pub fn slider(
        self: *Context,
        widget_id_str: []const u8,
        text: []const u8,
        value: *f32,
        min_val: f32,
        max_val: f32,
    ) bool {
        const wid = id(widget_id_str);
        const r = self.nextRect(0, 46);

        const track_y = r.top + 34;
        const track_left = r.left + 6;
        const track_right = r.right - 6;
        const track_w = @max(1.0, track_right - track_left);

        const hit_rect = Rect.ltrb(r.left, r.top + 18, r.right, r.bottom);
        _ = self.trackInteraction(wid, hit_rect, r);

        var changed = false;
        if (self.pass == .input and self.active_id == wid and self.mouse_down) {
            const norm = std.math.clamp((self.mouse_x - track_left) / track_w, 0.0, 1.0);
            const new_val = min_val + norm * (max_val - min_val);
            if (new_val != value.*) {
                value.* = new_val;
                changed = true;
                self.invalidateWindow();
            }
        }

        if (self.shouldPaint(r)) {
            const norm = std.math.clamp((value.* - min_val) / (max_val - min_val), 0.0, 1.0);
            const thumb_x = track_left + norm * track_w;

            self.paint.setStyle(.fill);
            self.paint.setColor(self.theme.text_primary);
            self.drawTextCached(self.font_body, text, r.left, r.top + 15);

            const val_str = self.fmt("{d:.2}", .{value.*});
            const val_w = self.measureTextCached(self.font_mono, val_str);
            self.paint.setColor(self.theme.text_muted);
            self.drawTextCached(self.font_mono, val_str, r.right - val_w, r.top + 15);

            self.paint.setColor(self.theme.control_bg);
            self.canvas.drawRoundRect(Rect.xywh(track_left, track_y - 3, track_w, 6), 3, 3, self.paint);

            self.paint.setColor(self.theme.accent);
            self.canvas.drawRoundRect(Rect.xywh(track_left, track_y - 3, thumb_x - track_left, 6), 3, 3, self.paint);

            const is_dragging = (self.active_id == wid and self.mouse_down);
            const hovered = (self.hot_id == wid);
            self.paint.setColor(if (is_dragging or hovered) self.theme.accent_hover else Color.white);
            self.canvas.drawCircle(thumb_x, track_y, if (is_dragging) 8.5 else 7.0, self.paint);
        }

        return changed;
    }

    // ========================================================================
    // Declarative Auto-ID Widgets (`btn`, `tab`, `checkbox`, `sliderFloat`, `titlebar`, `listItem`)
    // ========================================================================

    /// Renders a section header label (with optional top divider when not the first item in a container).
    pub fn sectionHeader(self: *Context, text: []const u8) void {
        const top = &self.stack[self.stack_len - 1];
        if (top.item_count > 0) {
            self.divider();
        }
        self.label(text, null);
    }

    pub const SectionHeaderResult = struct {
        expanded: bool,
        action_clicked: bool = false,
        right_clicked: bool = false,
    };

    pub const TreeFolderResult = struct {
        expanded: bool,
        clicked: bool = false,
        right_clicked: bool = false,
    };

    /// Renders an interactive collapsible sidebar section header with a vector chevron (`.chevron_down` / `.chevron_right`),
    /// section title, and optional right-aligned count badge (`badge_text`).
    /// Toggles `expanded.*` when clicked and returns the current `expanded.*` state.
    pub fn collapsibleSection(
        self: *Context,
        raw_label: []const u8,
        expanded: *bool,
        badge_text: []const u8,
    ) bool {
        return self.collapsibleSectionWithAction(raw_label, expanded, badge_text, "").expanded;
    }

    /// Renders a collapsible sidebar section header with an optional inline action button (e.g. `"↺"`).
    pub fn collapsibleSectionWithAction(
        self: *Context,
        raw_label: []const u8,
        expanded: *bool,
        badge_text: []const u8,
        action_label: []const u8,
    ) SectionHeaderResult {
        const top = &self.stack[self.stack_len - 1];
        if (top.item_count > 0) {
            self.divider();
        }

        const resolved = self.resolveIdAndLabel(raw_label);
        const r = self.nextRect(0, 24.0);

        const has_action = (action_label.len > 0);
        const act_wid = resolved.wid ^ 0x5EC7_104A_C701;
        const bw = if (badge_text.len > 0) self.measureTextCached(self.font_mono, badge_text) else 0.0;
        const pill_w = if (badge_text.len > 0) @max(18.0, bw + 10.0) else 0.0;
        const act_right = if (badge_text.len > 0) r.right - pill_w - 8.0 else r.right - 4.0;
        const act_rect = Rect.xywh(act_right - 18.0, r.top + 3.0, 18.0, 18.0);

        var action_clicked = false;
        if (has_action) {
            action_clicked = self.trackInteraction(act_wid, act_rect, r);
        }
        const over_action = (has_action and self.isHovered(act_rect));
        const clicked = if (!action_clicked and !over_action)
            self.trackInteraction(resolved.wid, r, r)
        else
            false;
        var right_clicked = false;

        if (self.pass == .input) {
            if (clicked) {
                expanded.* = !expanded.*;
                self.invalidateWindow();
            } else if (action_clicked) {
                self.invalidateWindow();
            } else if (self.right_mouse_pressed and self.isHovered(r)) {
                right_clicked = true;
                self.markDirty(r);
            }
        }

        if (self.shouldPaint(r)) {
            const hovered = (self.hot_id == resolved.wid or self.hot_id == act_wid);
            if (hovered) {
                self.paint.setStyle(.fill);
                self.paint.setColor(Color.argb(40, 148, 163, 184));
                self.canvas.drawRoundRect(r, 4.0, 4.0, self.paint);
            }

            const chevron_rect = Rect.xywh(r.left + 2.0, r.top + 4.0, 16.0, 16.0);
            const fg = if (hovered) self.theme.text_primary else self.theme.text_muted;
            self.drawIcon(if (expanded.*) .chevron_down else .chevron_right, chevron_rect, fg);

            const label_max_right = (if (has_action) act_rect.left else act_right) - 4.0;
            if (label_max_right > r.left + 20.0) {
                const save_hdr = self.canvas.save();
                defer self.canvas.restoreToCount(save_hdr);
                self.canvas.clipRect(Rect.ltrb(r.left + 20.0, r.top, label_max_right, r.bottom), .intersect, false);
                self.paint.setStyle(.fill);
                self.paint.setColor(fg);
                self.drawTextCached(self.font_mono, resolved.display, r.left + 20.0, r.top + 16.5);
            }

            if (has_action) {
                const act_hovered = (self.hot_id == act_wid);
                self.paint.setStyle(.fill);
                self.paint.setColor(if (act_hovered) Color.argb(120, 100, 116, 139) else Color.argb(55, 51, 65, 85));
                self.canvas.drawRoundRect(act_rect, 4.0, 4.0, self.paint);
                const aw = self.measureTextCached(self.font_mono, action_label);
                self.paint.setColor(if (act_hovered) self.theme.text_primary else self.theme.text_muted);
                self.drawTextCached(self.font_mono, action_label, act_rect.left + (18.0 - aw) * 0.5, r.top + 16.0);
            }

            if (badge_text.len > 0) {
                const pill_r = Rect.xywh(r.right - pill_w - 4.0, r.top + 4.0, pill_w, 16.0);
                self.paint.setStyle(.fill);
                self.paint.setColor(Color.argb(55, 100, 116, 139));
                self.canvas.drawRoundRect(pill_r, 8.0, 8.0, self.paint);

                self.paint.setColor(self.theme.text_muted);
                self.drawTextCached(self.font_mono, badge_text, pill_r.left + (pill_w - bw) * 0.5, r.top + 15.5);
            }
        }

        return .{ .expanded = expanded.*, .action_clicked = action_clicked, .right_clicked = right_clicked };
    }

    /// Auto-ID button with expressive `Size` support (`.w = .fill`, `.w = .half`, `.w = .px(120)`, `.w = .auto`).
    /// Supports `"Label##disambiguator"` syntax or `uic.scopedId(i)` in loops, optional leading vector `icon`,
    /// and automatic right-aligned shortcut keycap rendering when `shortcut` is set or label ends with ` (F5)`.
    pub fn btn(self: *Context, raw_label: []const u8, opts: ButtonOptions) bool {
        const resolved_label = self.resolveIdAndLabel(raw_label);
        const wid = if (opts.id_override) |ovr| self.resolveIdAndLabel(ovr).wid else resolved_label.wid;
        const display_text = resolved_label.display;
        const top = &self.stack[self.stack_len - 1];
        const max_fit_w = if (top.direction == .row_wrap)
            (top.content_bounds.right - top.content_bounds.left)
        else
            self.availableWidth();
        const w = switch (opts.w) {
            .fit => |bounds| std.math.clamp(
                self.measureTextCached(self.font_body, display_text) + 24.0,
                bounds.min,
                @max(bounds.min, @min(max_fit_w, bounds.max)),
            ),
            else => self.resolveWidth(opts.w),
        };
        const r = self.nextRect(w, opts.h);
        const clicked = self.trackInteraction(wid, r, r);

        if (self.shouldPaint(r)) {
            const hovered = (self.hot_id == wid);
            const is_active = (self.active_id == wid and self.mouse_down);
            const btn_w = r.right - r.left;

            // Extract trailing parenthesized keycap e.g. "Launch / Continue (F5)" -> label="Launch / Continue", keycap="F5"
            var main_label = display_text;
            var keycap = opts.shortcut;
            if (keycap.len == 0 and main_label.len > 4 and main_label[main_label.len - 1] == ')') {
                if (std.mem.lastIndexOfLinear(u8, main_label, " (")) |open_idx| {
                    const inner = main_label[open_idx + 2 .. main_label.len - 1];
                    if (inner.len >= 1 and inner.len <= 9) {
                        keycap = inner;
                        main_label = main_label[0..open_idx];
                    }
                }
            }

            const is_primary = (opts.variant == .primary);
            const rad: f32 = 5.5;
            const bg = if (is_primary)
                (if (is_active and hovered)
                    Color.rgb(20, 36, 64)
                else if (hovered)
                    Color.rgb(32, 58, 100)
                else
                    Color.rgb(25, 45, 78))
            else
                (if (is_active and hovered)
                    Color.rgb(19, 25, 37)
                else if (hovered)
                    Color.rgb(34, 45, 64)
                else
                    Color.rgb(24, 32, 46));

            self.paint.setStyle(.fill);
            self.paint.setColor(bg);
            self.canvas.drawRoundRect(r, rad, rad, self.paint);

            // Subtle top specular highlight
            if (!is_active) {
                self.paint.setColor(if (hovered) Color.argb(28, 255, 255, 255) else Color.argb(14, 255, 255, 255));
                self.canvas.drawRect(Rect.xywh(r.left + 4.0, r.top + 1.0, @max(1.0, btn_w - 8.0), 1.0), self.paint);
            }

            // Crisp 1px border (subtle accent border for primary or hovered, muted slate otherwise)
            const border_col = if (hovered)
                (opts.icon_color orelse Color.rgb(88, 166, 255))
            else if (is_primary)
                Color.rgb(53, 108, 192)
            else
                Color.rgb(46, 59, 80);
            self.paint.setStyle(.stroke);
            self.paint.setStrokeWidth(1.0);
            self.paint.setColor(border_col);
            self.canvas.drawRoundRect(r, rad, rad, self.paint);

            const save_cnt = self.canvas.save();
            defer self.canvas.restoreToCount(save_cnt);
            self.canvas.clipRect(Rect.ltrb(r.left + 2.0, r.top, r.right - 2.0, r.bottom), .intersect, false);

            const baseline_y = r.top + opts.h * 0.65;
            const fg = if (hovered or is_primary) Color.rgb(248, 250, 252) else Color.rgb(214, 224, 236);

            if (opts.variant == .toolbar or btn_w < 110.0) {
                // Compact centered icon + label (for horizontal button rows)
                const tw = self.measureTextCached(self.font_body, main_label);
                const icon_space: f32 = if (opts.icon != null) 16.0 else 0.0;
                const total_w = icon_space + tw;
                const start_x = r.left + @max(6.0, (btn_w - total_w) * 0.5);
                if (opts.icon) |ic| {
                    const ic_col = opts.icon_color orelse fg;
                    self.drawIcon(ic, Rect.xywh(start_x - 2.0, r.top + (opts.h - 16.0) * 0.5, 16.0, 16.0), ic_col);
                }
                self.paint.setStyle(.fill);
                self.paint.setColor(fg);
                self.drawTextCached(self.font_body, main_label, start_x + icon_space, baseline_y);
            } else {
                // Full-width action button: leading icon + left-aligned label + right-aligned keycap pill
                var text_x = r.left + 10.0;
                if (opts.icon) |ic| {
                    const ic_col = opts.icon_color orelse fg;
                    self.drawIcon(ic, Rect.xywh(r.left + 7.0, r.top + (opts.h - 16.0) * 0.5, 16.0, 16.0), ic_col);
                    text_x = r.left + 26.0;
                }
                self.paint.setStyle(.fill);
                self.paint.setColor(fg);
                self.drawTextCached(self.font_body, main_label, text_x, baseline_y);

                if (keycap.len > 0) {
                    const kw = self.measureTextCached(self.font_mono, keycap);
                    const pill_w = kw + 10.0;
                    const pill_h: f32 = @min(16.0, opts.h - 6.0);
                    const pill_r = Rect.xywh(r.right - pill_w - 6.0, r.top + (opts.h - pill_h) * 0.5, pill_w, pill_h);
                    self.paint.setStyle(.fill);
                    self.paint.setColor(Color.argb(120, 15, 20, 30));
                    self.canvas.drawRoundRect(pill_r, 3.5, 3.5, self.paint);
                    self.paint.setStyle(.stroke);
                    self.paint.setStrokeWidth(1.0);
                    self.paint.setColor(if (hovered) Color.rgb(71, 85, 105) else Color.rgb(45, 56, 74));
                    self.canvas.drawRoundRect(pill_r, 3.5, 3.5, self.paint);
                    self.paint.setStyle(.fill);
                    self.paint.setColor(if (hovered) Color.rgb(203, 213, 225) else Color.rgb(148, 163, 184));
                    self.drawTextCached(self.font_mono, keycap, pill_r.left + 5.0, pill_r.top + pill_h * 0.76);
                }
            }
        }

        if (clicked) self.invalidateWindow();
        return clicked;
    }

    /// Auto-ID sidebar tab button (supports `"Title##id"` or `uic.scopedId(i)` in loops).
    pub fn tab(self: *Context, raw_label: []const u8, selected: bool) bool {
        const resolved = self.resolveIdAndLabel(raw_label);
        const r = self.nextRect(0, 36);
        const clicked = self.trackInteraction(resolved.wid, r, r);

        if (self.shouldPaint(r)) {
            const hovered = (self.hot_id == resolved.wid);
            if (selected or hovered) {
                self.paint.setStyle(.fill);
                self.paint.setColor(if (selected) self.theme.bg_card else self.theme.control_bg);
                self.canvas.drawRoundRect(r, 8, 8, self.paint);
            }

            if (selected) {
                const bar = Rect.xywh(r.left + 4, r.top + 8, 3.5, (r.bottom - r.top) - 16);
                self.paint.setStyle(.fill);
                self.paint.setColor(self.theme.accent_hover);
                self.canvas.drawRoundRect(bar, 2, 2, self.paint);
            }

            self.paint.setStyle(.fill);
            self.paint.setColor(if (selected) self.theme.text_primary else self.theme.text_muted);
            self.drawTextCached(self.font_body, resolved.display, r.left + 16, r.top + 23);
        }

        if (clicked) self.invalidateWindow();
        return clicked;
    }

    /// Auto-ID toggle switch (supports `"Label##id"`).
    pub fn checkbox(self: *Context, raw_label: []const u8, value: *bool) bool {
        const resolved = self.resolveIdAndLabel(raw_label);
        const r = self.nextRect(0, 30);
        const clicked = self.trackInteraction(resolved.wid, r, r);

        var changed = false;
        if (self.pass == .input and clicked) {
            value.* = !value.*;
            changed = true;
            self.invalidateWindow();
        }

        if (self.shouldPaint(r)) {
            self.paint.setStyle(.fill);
            self.paint.setColor(self.theme.text_primary);
            self.drawTextCached(self.font_body, resolved.display, r.left, r.top + 20);

            const pill_w: f32 = 42;
            const pill_h: f32 = 22;
            const pill_x = r.right - pill_w;
            const pill_y = r.top + 4;
            const pill_rect = Rect.xywh(pill_x, pill_y, pill_w, pill_h);

            self.paint.setColor(if (value.*) self.theme.accent else self.theme.control_bg);
            self.canvas.drawRoundRect(pill_rect, pill_h * 0.5, pill_h * 0.5, self.paint);

            const knob_x = if (value.*) pill_x + pill_w - 11 else pill_x + 11;
            const knob_y = pill_y + pill_h * 0.5;
            self.paint.setColor(Color.white);
            self.canvas.drawCircle(knob_x, knob_y, 8.0, self.paint);
        }

        return changed;
    }

    /// Auto-ID slider control (supports `"Label##id"`).
    pub fn sliderFloat(self: *Context, raw_label: []const u8, value: *f32, min_val: f32, max_val: f32) bool {
        const resolved = self.resolveIdAndLabel(raw_label);
        const r = self.nextRect(0, 46);

        const track_y = r.top + 34;
        const track_left = r.left + 6;
        const track_right = r.right - 6;
        const track_w = @max(1.0, track_right - track_left);

        const hit_rect = Rect.ltrb(r.left, r.top + 18, r.right, r.bottom);
        _ = self.trackInteraction(resolved.wid, hit_rect, r);

        var changed = false;
        if (self.pass == .input and self.active_id == resolved.wid and self.mouse_down) {
            const norm = std.math.clamp((self.mouse_x - track_left) / track_w, 0.0, 1.0);
            const new_val = min_val + norm * (max_val - min_val);
            if (new_val != value.*) {
                value.* = new_val;
                changed = true;
                self.invalidateWindow();
            }
        }

        if (self.shouldPaint(r)) {
            const norm = std.math.clamp((value.* - min_val) / (max_val - min_val), 0.0, 1.0);
            const thumb_x = track_left + norm * track_w;

            self.paint.setStyle(.fill);
            self.paint.setColor(self.theme.text_primary);
            self.drawTextCached(self.font_body, resolved.display, r.left, r.top + 15);

            const val_str = self.fmt("{d:.2}", .{value.*});
            const val_w = self.measureTextCached(self.font_mono, val_str);
            self.paint.setColor(self.theme.text_muted);
            self.drawTextCached(self.font_mono, val_str, r.right - val_w, r.top + 15);

            self.paint.setColor(self.theme.control_bg);
            self.canvas.drawRoundRect(Rect.xywh(track_left, track_y - 3, track_w, 6), 3, 3, self.paint);

            self.paint.setColor(self.theme.accent);
            self.canvas.drawRoundRect(Rect.xywh(track_left, track_y - 3, thumb_x - track_left, 6), 3, 3, self.paint);

            const is_dragging = (self.active_id == resolved.wid and self.mouse_down);
            const hovered = (self.hot_id == resolved.wid);
            self.paint.setColor(if (is_dragging or hovered) self.theme.accent_hover else Color.white);
            self.canvas.drawCircle(thumb_x, track_y, if (is_dragging) 8.5 else 7.0, self.paint);
        }

        return changed;
    }

    /// Renders a unified macOS window titlebar with fullscreen-aware traffic-light inset,
    /// app icon badge, window title, and right-aligned status badges.
    pub fn titlebar(self: *Context, title_text: []const u8, badges: []const BadgeSpec) void {
        const is_fs = if (self.platform_ctx) |p| p.is_fullscreen else false;
        const left_pad: f32 = if (is_fs) 16.0 else 88.0;

        var bar = self.row(.{
            .h = .pixels(46),
            .padding = Padding{ .left = left_pad, .top = 11, .right = 16, .bottom = 11 },
            .gap = 10,
            .bg_color = Color.rgb(15, 20, 32),
        });
        defer bar.end();

        const title_w = self.measureTextCached(self.font_title, title_text);
        const title_r = self.nextRect(title_w + 28.0, 24.0);
        if (self.shouldPaint(title_r)) {
            self.paint.setStyle(.fill);
            self.paint.setColor(self.theme.accent);
            self.canvas.drawRoundRect(Rect.xywh(title_r.left, title_r.top + 5.0, 14.0, 14.0), 4.0, 4.0, self.paint);

            self.paint.setColor(self.theme.text_primary);
            self.drawTextCached(self.font_title, title_text, title_r.left + 22.0, title_r.top + 17.5);
        }

        // Compute total width of right-aligned badges so `fillSpacer` right-aligns them accurately
        var total_badges_w: f32 = 0;
        for (badges, 0..) |b, idx| {
            total_badges_w += self.measureTextCached(self.font_mono, b.text) + 20.0;
            if (idx + 1 < badges.len) total_badges_w += 10.0;
        }
        self.fillSpacer(total_badges_w);

        for (badges) |b| {
            const bg = b.bg_color orelse (if (b.accent) Color.argb(45, 99, 102, 241) else self.theme.bg_card);
            const fg = b.text_color orelse (if (b.accent) Color.rgb(165, 180, 252) else self.theme.text_muted);
            self.badge(b.text, bg, fg);
        }
    }

    /// Renders an interactive centered search / command center pill inside a titlebar or toolbar.
    /// Returns `true` when clicked.
    pub fn searchPill(
        self: *Context,
        raw_label: []const u8,
        display_text: []const u8,
        active: bool,
        pill_rect: c.sk_rect_t,
        clip_rect: c.sk_rect_t,
    ) bool {
        const resolved = self.resolveIdAndLabel(raw_label);
        const clicked = self.trackInteraction(resolved.wid, pill_rect, clip_rect);

        if (self.shouldPaint(clip_rect)) {
            const pill_hovered = (self.hot_id == resolved.wid);
            self.paint.setStyle(.fill);
            self.paint.setColor(if (active or pill_hovered)
                Color.rgb(28, 35, 49)
            else
                Color.rgb(22, 27, 38));
            self.canvas.drawRoundRect(pill_rect, 5.0, 5.0, self.paint);

            self.paint.setStyle(.stroke);
            self.paint.setStrokeWidth(1.0);
            self.paint.setColor(if (active)
                self.theme.accent
            else
                self.theme.border_subtle);
            self.canvas.drawRoundRect(pill_rect, 5.0, 5.0, self.paint);

            const pill_w = pill_rect.right - pill_rect.left;
            const tw = self.measureTextCached(self.font_body, display_text);
            self.paint.setStyle(.fill);
            self.paint.setColor(if (pill_hovered or active) self.theme.text_primary else self.theme.text_muted);
            self.drawTextCached(
                self.font_body,
                display_text,
                pill_rect.left + @max(6.0, (pill_w - tw) * 0.5),
                pill_rect.top + 16.5,
            );
        }

        if (clicked) self.invalidateWindow();
        return clicked;
    }

    /// Renders a horizontal document tab (with active top highlight bar, right separator, and colored dot).
    pub fn documentTab(self: *Context, raw_label: []const u8, active: bool, dot_color: ?u32) bool {
        return self.documentTabEx(raw_label, active, dot_color, false).clicked;
    }

    /// Renders a horizontal document tab with an optional interactive close (`×`) button.
    pub fn documentTabEx(
        self: *Context,
        raw_label: []const u8,
        active: bool,
        dot_color: ?u32,
        closable: bool,
    ) DocumentTabResult {
        const resolved = self.resolveIdAndLabel(raw_label);
        const text_w = self.measureTextCached(self.font_body, resolved.display);
        const extra_w: f32 = if (closable) 62.0 else 46.0;
        const r = self.nextRect(text_w + extra_w, 34.0);

        const close_wid = resolved.wid ^ 0x9E37_79B9_7F4A_7C15;
        const close_rect = Rect.xywh(r.right - 23.0, r.top + 9.0, 16.0, 16.0);

        var closed = false;
        var clicked = false;

        if (closable) {
            closed = self.trackInteraction(close_wid, close_rect, r);
        }
        if (!closed and !(closable and self.isHovered(close_rect))) {
            clicked = self.trackInteraction(resolved.wid, r, r);
        }

        if (self.shouldPaint(r)) {
            const tab_hovered = (self.hot_id == resolved.wid or self.hot_id == close_wid);
            const close_hovered = (self.hot_id == close_wid);

            self.paint.setStyle(.fill);
            self.paint.setColor(if (active) self.theme.bg_canvas else if (tab_hovered) Color.rgb(22, 28, 39) else Color.rgb(16, 20, 28));
            self.canvas.drawRect(r, self.paint);

            if (active) {
                self.paint.setColor(self.theme.accent);
                self.canvas.drawRect(Rect.xywh(r.left, r.top, r.right - r.left, 2.0), self.paint);
            }

            self.paint.setColor(self.theme.border_subtle);
            self.canvas.drawRect(Rect.xywh(r.right - 1.0, r.top + 6.0, 1.0, 22.0), self.paint);

            self.paint.setColor(dot_color orelse Color.rgb(251, 191, 36));
            self.canvas.drawCircle(r.left + 14.0, r.top + 17.0, 3.5, self.paint);

            self.paint.setColor(if (active) self.theme.text_primary else self.theme.text_muted);
            self.drawTextCached(self.font_body, resolved.display, r.left + 24.0, r.top + 21.5);

            if (closable and (active or tab_hovered)) {
                if (close_hovered) {
                    self.paint.setStyle(.fill);
                    self.paint.setColor(Color.argb(65, 148, 163, 184));
                    self.canvas.drawRoundRect(close_rect, 3.5, 3.5, self.paint);
                }
                self.paint.setStyle(.stroke);
                self.paint.setStrokeWidth(1.3);
                self.paint.setColor(if (close_hovered) self.theme.text_primary else self.theme.text_muted);
                const cx = (close_rect.left + close_rect.right) * 0.5;
                const cy = (close_rect.top + close_rect.bottom) * 0.5;
                const d: f32 = 3.2;
                self.canvas.drawLine(cx - d, cy - d, cx + d, cy + d, self.paint);
                self.canvas.drawLine(cx + d, cy - d, cx - d, cy + d, self.paint);
            }
        }

        if (clicked or closed) self.invalidateWindow();
        return .{ .clicked = clicked, .closed = closed, .wid = resolved.wid, .rect = r };
    }

    /// Renders an interactive vertical or horizontal splitter sash handle between panes.
    /// Dragging the sash updates `value.*` (width or height/ratio) and returns `true`.
    pub fn splitterSash(
        self: *Context,
        raw_label: []const u8,
        vertical_line: bool,
        length: f32,
    ) struct { dragging: bool, hovered: bool, rect: c.sk_rect_t } {
        const resolved = self.resolveIdAndLabel(raw_label);
        const r = if (vertical_line)
            self.nextRect(5.0, length)
        else
            self.nextRect(0.0, 5.0);

        const hit_r = if (vertical_line)
            Rect.ltrb(r.left - 3.0, r.top, r.right + 3.0, r.bottom)
        else
            Rect.ltrb(r.left, r.top - 3.0, r.right, r.bottom + 3.0);

        _ = self.trackInteraction(resolved.wid, hit_r, r);
        const is_dragging = (self.active_id == resolved.wid and self.mouse_down);
        const is_hovered = (self.hot_id == resolved.wid or is_dragging);

        if (self.pass == .input) {
            if (is_hovered) {
                self.setCursor(if (vertical_line) .resize_ew else .resize_ns);
            }
            if (is_dragging) {
                self.invalidateWindow();
            }
        }

        if (self.shouldPaint(r)) {
            self.paint.setStyle(.fill);
            self.paint.setColor(Color.rgb(16, 20, 28));
            self.canvas.drawRect(r, self.paint);

            if (vertical_line) {
                const cx = @floor((r.left + r.right) * 0.5);
                const line_w: f32 = if (is_hovered) 2.0 else 1.0;
                self.paint.setColor(if (is_dragging)
                    self.theme.accent
                else if (is_hovered)
                    self.theme.accent_hover
                else
                    self.theme.border_subtle);
                self.canvas.drawRect(Rect.xywh(cx, r.top, line_w, r.bottom - r.top), self.paint);
            } else {
                const cy = @floor((r.top + r.bottom) * 0.5);
                const line_h: f32 = if (is_hovered) 2.0 else 1.0;
                self.paint.setColor(if (is_dragging)
                    self.theme.accent
                else if (is_hovered)
                    self.theme.accent_hover
                else
                    self.theme.border_subtle);
                self.canvas.drawRect(Rect.xywh(r.left, cy, r.right - r.left, line_h), self.paint);
            }
        }

        return .{ .dragging = is_dragging, .hovered = is_hovered, .rect = r };
    }

    /// Sets the desired OS mouse cursor shape for the current frame.
    pub fn setCursor(self: *Context, shape: CursorShape) void {
        if (self.platform_ctx) |pctx| {
            pctx.cursor_shape = shape;
        }
    }

    /// Checks whether a keyboard shortcut (`Shortcut`) was pressed during the current `.input` pass,
    /// automatically invalidating the window when matched.
    pub fn shortcut(self: *Context, spec: Shortcut) bool {
        if (self.pass != .input) return false;
        for (self.key_events) |kev| {
            if (spec.matches(kev)) {
                self.invalidateWindow();
                return true;
            }
            // Cross-platform Cmd/Ctrl equivalence when `.cmd = true` (or default `uic.shortcut(.{ .key = ... })` without explicit modifiers)
            if (kev.key == spec.key and kev.shift == spec.shift and kev.alt == spec.alt) {
                const wants_cmd_or_ctrl = (spec.cmd and !spec.ctrl) or (!spec.cmd and !spec.ctrl and !spec.alt and !spec.cmd_or_ctrl);
                if (wants_cmd_or_ctrl and (kev.cmd or kev.ctrl)) {
                    self.invalidateWindow();
                    return true;
                }
            }
        }
        return false;
    }

    /// Renders a vector icon button (`Icon`) with optional active left indicator bar and hover highlight.
    pub fn iconButton(self: *Context, raw_label: []const u8, icon: Icon, opts: IconButtonOptions) bool {
        const resolved = self.resolveIdAndLabel(raw_label);
        const r = self.nextRect(opts.w, opts.h);
        const clicked = self.trackInteraction(resolved.wid, r, r);

        if (self.shouldPaint(r)) {
            const hovered = (self.hot_id == resolved.wid);
            const is_pressed = (self.active_id == resolved.wid and self.mouse_down);
            const accent = opts.accent_color orelse self.theme.accent_hover;

            if (hovered or opts.active) {
                const pill = Rect.xywh(
                    r.left + 5.0,
                    r.top + 3.5,
                    @max(8.0, (r.right - r.left) - 10.0),
                    @max(8.0, (r.bottom - r.top) - 7.0),
                );
                self.paint.setStyle(.fill);
                self.paint.setColor(if (is_pressed)
                    Color.rgb(20, 26, 38)
                else if (opts.active)
                    Color.rgb(27, 35, 52)
                else
                    Color.rgb(23, 30, 44));
                self.canvas.drawRoundRect(pill, 7.0, 7.0, self.paint);

                self.paint.setStyle(.stroke);
                self.paint.setStrokeWidth(1.0);
                self.paint.setColor(if (opts.active)
                    Color.withAlpha(accent, 110)
                else
                    Color.rgb(42, 54, 74));
                self.canvas.drawRoundRect(pill, 7.0, 7.0, self.paint);
            }

            if (opts.show_active_bar and opts.active) {
                self.paint.setStyle(.fill);
                self.paint.setColor(accent);
                self.canvas.drawRoundRect(Rect.xywh(r.left + 0.5, r.top + 8.0, 2.5, opts.h - 16.0), 1.2, 1.2, self.paint);
            }

            const fg = if (opts.active)
                (opts.accent_color orelse self.theme.text_primary)
            else if (hovered)
                self.theme.text_primary
            else
                self.theme.text_muted;
            self.drawIcon(icon, r, fg);
        }

        if (clicked) self.invalidateWindow();
        return clicked;
    }

    /// Renders a compact borderless toolbar icon button (e.g., Debug Play, Pause, Step Over, Step Into, Step Out, Restart, Stop, Gear, Console).
    pub fn toolbarIconBtn(
        self: *Context,
        raw_label: []const u8,
        icon: Icon,
        w: f32,
        h: f32,
        enabled: bool,
        color_override: ?u32,
    ) bool {
        const resolved = self.resolveIdAndLabel(raw_label);
        const r = self.nextRect(w, h);
        const clicked = if (enabled) self.trackInteraction(resolved.wid, r, r) else false;

        if (self.shouldPaint(r)) {
            const hovered = enabled and (self.hot_id == resolved.wid);
            const is_pressed = enabled and (self.active_id == resolved.wid and self.mouse_down);

            if (hovered) {
                self.paint.setStyle(.fill);
                self.paint.setColor(if (is_pressed) Color.argb(95, 100, 116, 139) else Color.argb(55, 148, 163, 184));
                self.canvas.drawRoundRect(r, 4.0, 4.0, self.paint);
            }

            const fg = if (!enabled)
                Color.rgb(86, 94, 108)
            else if (color_override) |col|
                col
            else if (hovered)
                self.theme.text_primary
            else
                Color.rgb(176, 186, 198);

            self.drawIcon(icon, r, fg);
        }

        if (clicked) self.invalidateWindow();
        return clicked;
    }

    /// Renders a VS Code-style configuration dropdown selector box with a right-aligned chevron (`⌄`) and focus/active border.
    pub fn dropdownSelect(
        self: *Context,
        raw_label: []const u8,
        display_text: []const u8,
        w: f32,
        h: f32,
        active_border: bool,
    ) bool {
        const resolved = self.resolveIdAndLabel(raw_label);
        const resolved_w = if (w <= 0) @max(60.0, self.availableWidth() + w) else w;
        const r = self.nextRect(resolved_w, h);
        self.last_dropdown_rect = r;
        const clicked = self.trackInteraction(resolved.wid, r, r);

        if (self.shouldPaint(r)) {
            const hovered = (self.hot_id == resolved.wid);

            self.paint.setStyle(.fill);
            self.paint.setColor(if (hovered) Color.rgb(34, 41, 54) else Color.rgb(26, 32, 44));
            self.canvas.drawRoundRect(r, 3.5, 3.5, self.paint);

            self.paint.setStyle(.stroke);
            self.paint.setStrokeWidth(1.1);
            self.paint.setColor(if (active_border or hovered)
                Color.rgb(37, 119, 235)
            else
                Color.rgb(56, 68, 84));
            self.canvas.drawRoundRect(r, 3.5, 3.5, self.paint);

            const save_cnt = self.canvas.save();
            defer self.canvas.restoreToCount(save_cnt);
            self.canvas.clipRect(Rect.ltrb(r.left + 4.0, r.top, r.right - 22.0, r.bottom), .intersect, false);

            self.paint.setStyle(.fill);
            self.paint.setColor(Color.rgb(235, 240, 246));
            self.drawTextCached(self.font_body, display_text, r.left + 8.0, r.top + h * 0.67);
            self.canvas.restoreToCount(save_cnt);

            const chev_r = Rect.xywh(r.right - 20.0, r.top + (h - 16.0) * 0.5, 16.0, 16.0);
            self.drawIcon(.chevron_down, chev_r, if (hovered) self.theme.text_primary else Color.rgb(165, 175, 188));
        }

        if (clicked) self.invalidateWindow();
        return clicked;
    }

    /// Reserves a floating dropdown overlay rectangle anchored directly beneath the last `dropdownSelect`
    /// widget, blocks hover/click events from reaching underlying widgets covered by the menu during
    /// `Pass.input`, and returns `true` if the user clicked outside the dropdown or pressed `Escape`.
    pub fn reserveDropdownOverlay(self: *Context, height: f32) bool {
        const top = &self.stack[self.stack_len - 1];
        const left = top.content_bounds.left;
        const right = top.content_bounds.right;
        const w = @max(120.0, right - left);
        const y = self.last_dropdown_rect.bottom + 4.0;
        const menu_rect = Rect.xywh(left, y, w, @max(24.0, height));
        self.dropdown_overlay_rect = menu_rect;
        self.setBlockingOverlay(menu_rect);

        if (self.pass == .input) {
            self.markDirty(Rect.outset(menu_rect, 8.0, 8.0));
            for (self.key_events) |kev| {
                if (kev.key == .escape) {
                    self.invalidateWindow();
                    return true;
                }
            }
            if (self.clickedOutside(&.{ self.last_dropdown_rect, menu_rect })) {
                self.invalidateWindow();
                return true;
            }
        }
        return false;
    }

    /// Begins painting and laying out the reserved floating dropdown menu overlay on top of prior content.
    pub fn beginDropdownOverlay(self: *Context) OverlayGuard {
        const top = &self.stack[self.stack_len - 1];
        const fallback = Rect.xywh(
            top.content_bounds.left,
            self.last_dropdown_rect.bottom + 4.0,
            @max(120.0, top.content_bounds.right - top.content_bounds.left),
            96.0,
        );
        const rect = self.dropdown_overlay_rect orelse fallback;
        return self.overlayBox(rect, .{
            .direction = .column,
            .padding = Padding.xy(6, 6),
            .gap = 4,
            .bg_color = Color.rgb(24, 31, 44),
            .border_color = Color.rgb(56, 139, 253),
            .border_width = 1.0,
            .corner_radius = 6.0,
        });
    }

    /// Ends a floating dropdown menu overlay started with `beginDropdownOverlay`.
    pub fn endDropdownOverlay(self: *Context) void {
        if (self.stack_len > 1) {
            self.stack_len -= 1;
        }
        self.in_overlay = false;
        self.setBlockingOverlay(null);
    }

    /// Draws a crisp Skia vector `Icon` centered inside `r`.
    pub fn drawIcon(self: *Context, icon: Icon, r: c.sk_rect_t, color: u32) void {
        icons_mod.drawIcon(self, icon, r, color);
    }

    /// Renders a horizontal (left/right) or vertical (top/bottom) resizable split container
    /// with an interactive 5pt splitter sash that automatically updates `ratio.*` (`min_ratio..max_ratio`).
    pub fn splitPanes(
        self: *Context,
        sash_label: []const u8,
        vertical_stack: bool,
        height: f32,
        ratio: *f32,
        min_ratio: f32,
        max_ratio: f32,
        ctx_arg: anytype,
        comptime buildPaneFn: anytype,
    ) void {
        var box_guard = self.box(.{
            .direction = if (vertical_stack) .column else .row,
            .h = .pixels(height),
            .gap = 0,
        });
        defer box_guard.end();

        const rect = box_guard.rect;
        const avail_w = rect.right - rect.left;
        const avail_h = rect.bottom - rect.top;
        const r_clamped = std.math.clamp(ratio.*, min_ratio, max_ratio);

        const pane0_w: Size = if (!vertical_stack) .pixels(@floor((avail_w - 5.0) * r_clamped)) else .fill;
        const pane0_h: f32 = if (vertical_stack) @floor((avail_h - 5.0) * r_clamped) else height;
        buildPaneFn(ctx_arg, 0, pane0_w, pane0_h);

        const sash = self.splitterSash(
            sash_label,
            !vertical_stack,
            if (vertical_stack) avail_w else height,
        );
        if (self.pass == .input and sash.dragging) {
            const new_r = if (vertical_stack)
                (self.mouse_y - rect.top) / @max(1.0, avail_h)
            else
                (self.mouse_x - rect.left) / @max(1.0, avail_w);
            ratio.* = std.math.clamp(new_r, min_ratio, max_ratio);
            self.invalidateWindow();
        }

        const pane1_w: Size = .fill;
        const pane1_h: f32 = if (vertical_stack) @max(1.0, avail_h - 5.0 - pane0_h) else height;
        buildPaneFn(ctx_arg, 1, pane1_w, pane1_h);
    }

    /// Renders a compact panel header tab (with bottom underline bar when active).
    pub fn panelTab(self: *Context, raw_label: []const u8, active: bool) bool {
        const resolved = self.resolveIdAndLabel(raw_label);
        const text_w = self.measureTextCached(self.font_mono, resolved.display) + 16.0;
        const r = self.nextRect(text_w, 24.0);
        const clicked = self.trackInteraction(resolved.wid, r, r);

        if (self.shouldPaint(r)) {
            const hovered = (self.hot_id == resolved.wid);
            self.paint.setStyle(.fill);
            self.paint.setColor(if (active or hovered) self.theme.text_primary else self.theme.text_muted);
            self.drawTextCached(self.font_mono, resolved.display, r.left + 8.0, r.top + 16.0);
            if (active) {
                self.paint.setColor(self.theme.accent);
                self.canvas.drawRect(Rect.xywh(r.left + 6.0, r.bottom - 2.0, (r.right - r.left) - 12.0, 2.0), self.paint);
            }
        }

        if (clicked) self.invalidateWindow();
        return clicked;
    }

    /// Renders an interactive splitter sash and automatically updates `size_val.*` within `[min_size, max_size]`.
    pub fn resizableSash(
        self: *Context,
        raw_label: []const u8,
        vertical_line: bool,
        length: f32,
        size_val: *f32,
        min_size: f32,
        max_size: f32,
        anchor_pos: f32,
        invert: bool,
    ) bool {
        const sash = self.splitterSash(raw_label, vertical_line, length);
        if (self.pass == .input and sash.dragging) {
            const mouse_pos = if (vertical_line) self.mouse_x else self.mouse_y;
            const raw_delta = if (invert) anchor_pos - mouse_pos else mouse_pos - anchor_pos;
            const clamped = std.math.clamp(raw_delta, min_size, max_size);
            if (clamped != size_val.*) {
                size_val.* = clamped;
                self.invalidateWindow();
                return true;
            }
        }
        return false;
    }

    /// Renders a subtle pill/chip button with hover, active, and optional bordered states (e.g. model/mode selectors or toolbar pills).
    pub fn chip(self: *Context, raw_label: []const u8, opts: ChipOptions) bool {
        const resolved = self.resolveIdAndLabel(raw_label);
        const font = if (opts.mono) self.font_mono else self.font_body;
        var cached_tw: ?f32 = null;
        const chip_w = opts.w orelse blk: {
            const tw = self.measureTextCached(font, resolved.display);
            cached_tw = tw;
            break :blk std.math.clamp(tw + opts.pad_x * 2.0, opts.min_w, opts.max_w);
        };
        const r = self.nextRect(chip_w, opts.h);
        const clicked = self.trackInteraction(resolved.wid, r, r);

        if (self.shouldPaint(r)) {
            const tw = cached_tw orelse self.measureTextCached(font, resolved.display);
            const hovered = (self.hot_id == resolved.wid);
            const radius = opts.h * 0.45;

            if (hovered or opts.active or opts.bordered) {
                self.paint.setStyle(.fill);
                const bg = if (opts.active)
                    (if (hovered) Color.argb(55, 139, 148, 158) else Color.argb(32, 139, 148, 158))
                else if (hovered)
                    Color.argb(40, 139, 148, 158)
                else
                    Color.argb(18, 139, 148, 158);
                self.paint.setColor(bg);
                self.canvas.drawRoundRect(r, radius, radius, self.paint);
            }

            if (opts.bordered) {
                self.paint.setStyle(.stroke);
                self.paint.setStrokeWidth(1.0);
                self.paint.setColor(if (hovered) Color.rgb(68, 76, 86) else Color.rgb(42, 49, 60));
                self.canvas.drawRoundRect(r, radius, radius, self.paint);
            }

            const tx = r.left + @max(6.0, ((r.right - r.left) - tw) * 0.5);
            const ty = r.top + opts.h * 0.68;

            self.paint.setStyle(.fill);
            self.paint.setColor(if (hovered or opts.active) self.theme.text_primary else Color.rgb(139, 148, 158));

            const save_cnt = self.canvas.save();
            defer self.canvas.restoreToCount(save_cnt);
            self.canvas.clipRect(Rect.ltrb(r.left + 4.0, r.top, r.right - 4.0, r.bottom), .intersect, false);
            self.drawTextCached(font, resolved.display, tx, ty);
        }

        if (clicked) self.invalidateWindow();
        return clicked;
    }

    /// Renders a selectable single-line popover/dropdown menu item with a leading checkmark when `selected`.
    pub fn menuItem(
        self: *Context,
        raw_label: []const u8,
        selected: bool,
    ) bool {
        const resolved = self.resolveIdAndLabel(raw_label);
        const r = self.nextRect(0, 26.0);
        const clicked = self.trackInteraction(resolved.wid, r, r);

        if (self.shouldPaint(r)) {
            const hovered = (self.hot_id == resolved.wid);
            if (hovered or selected) {
                self.paint.setStyle(.fill);
                self.paint.setColor(if (hovered) Color.rgb(36, 44, 58) else Color.argb(45, 56, 139, 253));
                self.canvas.drawRoundRect(r, 5.0, 5.0, self.paint);
            }

            const save_cnt = self.canvas.save();
            defer self.canvas.restoreToCount(save_cnt);
            self.canvas.clipRect(Rect.ltrb(r.left + 6.0, r.top, r.right - 6.0, r.bottom), .intersect, false);

            const by = r.top + 17.5;
            self.paint.setStyle(.fill);
            if (selected) {
                self.paint.setColor(Color.rgb(88, 166, 255));
                self.drawTextCached(self.font_body, "✓", r.left + 8.0, by);
            }

            self.paint.setColor(if (selected or hovered) Color.rgb(240, 246, 252) else Color.rgb(185, 194, 204));
            self.drawTextCached(self.font_body, resolved.display, r.left + 24.0, by);
        }

        if (clicked) self.invalidateWindow();
        return clicked;
    }

    /// Renders a two-line popover/dropdown menu item with title, subtitle description, and right-aligned selection checkmark.
    pub fn menuItemWithSubtitle(
        self: *Context,
        raw_id: []const u8,
        title: []const u8,
        subtitle: []const u8,
        selected: bool,
    ) bool {
        const resolved = self.resolveIdAndLabel(raw_id);
        const r = self.nextRect(0, 42.0);
        const clicked = self.trackInteraction(resolved.wid, r, r);

        if (self.shouldPaint(r)) {
            const hovered = (self.hot_id == resolved.wid);
            if (selected or hovered) {
                self.paint.setStyle(.fill);
                self.paint.setColor(if (hovered) Color.rgb(33, 38, 45) else Color.argb(32, 56, 139, 253));
                self.canvas.drawRoundRect(r, 6.0, 6.0, self.paint);
            }

            self.paint.setStyle(.fill);
            self.paint.setColor(if (selected) Color.rgb(240, 246, 252) else Color.rgb(201, 209, 217));
            self.drawTextCached(self.font_body, title, r.left + 10.0, r.top + 16.5);

            self.paint.setColor(Color.rgb(110, 118, 129));
            self.drawTextCached(self.font_mono, subtitle, r.left + 10.0, r.top + 33.0);

            if (selected) {
                self.paint.setColor(Color.rgb(88, 166, 255));
                self.drawTextCached(self.font_mono, "✓", r.right - 20.0, r.top + 24.0);
            }
        }

        if (clicked) self.invalidateWindow();
        return clicked;
    }

    /// Renders a circular action button (`↑` send or `■` stop/busy square) with enabled/busy states.
    pub fn circularActionButton(self: *Context, raw_label: []const u8, busy: bool, enabled: bool) bool {
        const resolved = self.resolveIdAndLabel(raw_label);
        const r = self.nextRect(24.0, 24.0);
        const clicked = self.trackInteraction(resolved.wid, r, r);

        if (self.shouldPaint(r)) {
            const hovered = (self.hot_id == resolved.wid);
            const cx = (r.left + r.right) * 0.5;
            const cy = (r.top + r.bottom) * 0.5;

            self.paint.setStyle(.fill);
            if (busy) {
                self.paint.setColor(if (hovered) Color.rgb(248, 81, 73) else Color.argb(45, 248, 81, 73));
                self.canvas.drawCircle(cx, cy, 11.0, self.paint);
                self.paint.setColor(if (hovered) Color.white else Color.rgb(248, 81, 73));
                self.canvas.drawRoundRect(Rect.xywh(cx - 3.5, cy - 3.5, 7.0, 7.0), 1.5, 1.5, self.paint);
            } else {
                self.paint.setColor(if (!enabled)
                    Color.rgb(33, 38, 45)
                else if (hovered)
                    Color.rgb(255, 255, 255)
                else
                    Color.rgb(230, 237, 243));
                self.canvas.drawCircle(cx, cy, 11.0, self.paint);

                self.paint.setStyle(.stroke);
                self.paint.setStrokeWidth(1.6);
                self.paint.setColor(if (!enabled) Color.rgb(110, 118, 129) else Color.rgb(13, 17, 23));
                self.canvas.drawLine(cx, cy + 4.5, cx, cy - 4.5, self.paint);
                self.canvas.drawLine(cx - 3.5, cy - 1.0, cx, cy - 4.5, self.paint);
                self.canvas.drawLine(cx + 3.5, cy - 1.0, cx, cy - 4.5, self.paint);
            }
        }

        if (clicked) self.invalidateWindow();
        return clicked;
    }

    /// Renders a status/alert banner with severity styling (`.info`, `.warning`, `.err`).
    pub fn banner(self: *Context, text: []const u8, severity: BannerSeverity) void {
        const r = self.nextRect(0, 28.0);
        if (!self.shouldPaint(r)) return;

        const save_c = self.canvas.save();
        defer self.canvas.restoreToCount(save_c);
        self.canvas.clipRect(r, .intersect, false);

        const bg = switch (severity) {
            .err => Color.argb(32, 248, 81, 73),
            .warning => Color.argb(32, 210, 153, 34),
            .info => Color.argb(32, 56, 139, 253),
        };
        const border = switch (severity) {
            .err => Color.argb(90, 248, 81, 73),
            .warning => Color.argb(90, 210, 153, 34),
            .info => Color.argb(90, 56, 139, 253),
        };
        const fg = switch (severity) {
            .err => Color.rgb(255, 123, 114),
            .warning => Color.rgb(227, 179, 65),
            .info => Color.rgb(121, 192, 255),
        };

        self.paint.setStyle(.fill);
        self.paint.setColor(bg);
        self.canvas.drawRoundRect(r, 6.0, 6.0, self.paint);

        self.paint.setStyle(.stroke);
        self.paint.setStrokeWidth(1.0);
        self.paint.setColor(border);
        self.canvas.drawRoundRect(r, 6.0, 6.0, self.paint);

        self.paint.setStyle(.fill);
        self.paint.setColor(fg);
        self.drawTextCached(self.font_mono, text, r.left + 10.0, r.top + 18.0);
    }

    /// Renders a structured list or tree item with optional tree indentation guides (`indent_level`),
    /// icon badge, primary label, and right-aligned metadata.
    pub fn listItem(self: *Context, opts: ListItemOptions) bool {
        return self.listItemEx(opts).clicked;
    }

    /// Renders a structured list or tree item with optional hover inline action buttons (`action_label`,
    /// `secondary_action_label`) and colored right-aligned status metadata (`meta`, `meta_color`).
    pub fn listItemEx(self: *Context, opts: ListItemOptions) ListItemResult {
        const resolved = self.resolveIdAndLabel(opts.label);
        const r = self.nextRect(0, opts.height);

        const has_act1 = (opts.action_label.len > 0);
        const has_act2 = (opts.secondary_action_label.len > 0);
        const act1_wid = resolved.wid ^ 0xA11C_7101_5EED;
        const act2_wid = resolved.wid ^ 0xA22C_7202_9EED;

        const raw_meta_w: f32 = if (opts.meta.len > 0) self.measureTextCached(self.font_mono, opts.meta) else 0.0;
        const indent_px: f32 = @as(f32, @floatFromInt(opts.indent_level)) * 13.0;
        const base_text_x = r.left + indent_px + (if (opts.icon_text.len > 0) @as(f32, 28.0) else @as(f32, 10.0));
        const show_meta = (opts.meta.len > 0) and (base_text_x + 48.0 + raw_meta_w < r.right - 6.0);
        const meta_reserve: f32 = if (show_meta) raw_meta_w + 14.0 else 6.0;
        const btn_size: f32 = 17.0;
        const btn_y = r.top + (opts.height - btn_size) * 0.5;
        const act1_rect = Rect.xywh(r.right - meta_reserve - btn_size - 2.0, btn_y, btn_size, btn_size);
        const act2_rect = Rect.xywh(act1_rect.left - btn_size - 3.0, btn_y, btn_size, btn_size);

        var res = ListItemResult{};
        if (has_act1) {
            res.action_clicked = self.trackInteraction(act1_wid, act1_rect, r);
        }
        if (has_act2) {
            res.secondary_action_clicked = self.trackInteraction(act2_wid, act2_rect, r);
        }
        const over_actions = (has_act1 and self.isHovered(act1_rect)) or (has_act2 and self.isHovered(act2_rect));
        if (!res.action_clicked and !res.secondary_action_clicked and !over_actions) {
            res.clicked = self.trackInteraction(resolved.wid, r, r);
        }

        if (self.shouldPaint(r)) {
            const hovered = (self.hot_id == resolved.wid or self.hot_id == act1_wid or self.hot_id == act2_wid);
            if (opts.selected or hovered) {
                self.paint.setStyle(.fill);
                self.paint.setColor(if (opts.selected) Color.argb(55, 56, 139, 253) else self.theme.control_bg);
                self.canvas.drawRoundRect(r, 5.0, 5.0, self.paint);
            }

            tree_view_mod.drawTreeIndentGuides(self, r, opts.indent_level, 9.0, 13.0);

            var text_x = r.left + indent_px + 10.0;
            const baseline_y = r.top + opts.height * 0.68;

            if (opts.icon_text.len > 0) {
                const icon_tw = self.measureTextCached(self.font_mono, opts.icon_text);
                const badge_w = @max(14.0, icon_tw + 6.0);
                if (opts.icon_bg) |ibg| {
                    const badge_r = Rect.xywh(r.left + indent_px + 8.0, r.top + (opts.height - 14.0) * 0.5, badge_w, 14.0);
                    self.paint.setStyle(.fill);
                    self.paint.setColor(ibg);
                    self.canvas.drawRoundRect(badge_r, 3.0, 3.0, self.paint);
                }
                self.paint.setStyle(.fill);
                self.paint.setColor(opts.icon_color orelse self.theme.accent_hover);
                self.drawTextCached(self.font_mono, opts.icon_text, r.left + indent_px + 8.0 + (badge_w - icon_tw) * 0.5, baseline_y - 0.5);
                text_x = r.left + indent_px + 8.0 + badge_w + 6.0;
            }

            const label_font = if (opts.mono_label) self.font_mono else self.font_body;
            const text_max_right = if (hovered and (has_act1 or has_act2))
                (if (has_act2) act2_rect.left else act1_rect.left) - 4.0
            else if (show_meta)
                r.right - meta_reserve - 2.0
            else
                r.right - 6.0;

            if (text_max_right > text_x) {
                const save_txt = self.canvas.save();
                defer self.canvas.restoreToCount(save_txt);
                self.canvas.clipRect(Rect.ltrb(text_x, r.top, text_max_right, r.bottom), .intersect, false);
                self.paint.setStyle(.fill);
                self.paint.setColor(if (opts.selected) self.theme.text_primary else Color.rgb(201, 209, 217));
                self.drawTextCached(label_font, resolved.display, text_x, baseline_y);
            }

            if (hovered and (has_act1 or has_act2)) {
                if (has_act2) {
                    const a2_hov = (self.hot_id == act2_wid);
                    self.paint.setStyle(.fill);
                    self.paint.setColor(if (a2_hov) Color.argb(120, 100, 116, 139) else Color.argb(65, 51, 65, 85));
                    self.canvas.drawRoundRect(act2_rect, 3.5, 3.5, self.paint);
                    const tw2 = self.measureTextCached(self.font_mono, opts.secondary_action_label);
                    self.paint.setColor(if (a2_hov) self.theme.text_primary else self.theme.text_muted);
                    self.drawTextCached(self.font_mono, opts.secondary_action_label, act2_rect.left + (btn_size - tw2) * 0.5, baseline_y - 0.5);
                }
                if (has_act1) {
                    const a1_hov = (self.hot_id == act1_wid);
                    self.paint.setStyle(.fill);
                    self.paint.setColor(if (a1_hov) Color.argb(120, 100, 116, 139) else Color.argb(65, 51, 65, 85));
                    self.canvas.drawRoundRect(act1_rect, 3.5, 3.5, self.paint);
                    const tw1 = self.measureTextCached(self.font_mono, opts.action_label);
                    self.paint.setColor(if (a1_hov) self.theme.text_primary else self.theme.text_muted);
                    self.drawTextCached(self.font_mono, opts.action_label, act1_rect.left + (btn_size - tw1) * 0.5, baseline_y - 0.5);
                }
            }

            if (show_meta) {
                self.paint.setColor(opts.meta_color orelse self.theme.text_muted);
                self.drawTextCached(self.font_mono, opts.meta, r.right - raw_meta_w - 8.0, baseline_y - 0.5);
            }
        }

        if (res.clicked or res.action_clicked or res.secondary_action_clicked) {
            self.invalidateWindow();
        }
        return res;
    }

    /// Renders an expandable/collapsible directory node in a hierarchical file tree with vertical
    /// indent guides (`indent_level`), vector chevron, vector folder icon, and folder label.
    /// Toggles `expanded.*` when clicked and returns the current `expanded.*` state.
    pub fn treeFolderNode(
        self: *Context,
        raw_label: []const u8,
        indent_level: usize,
        expanded: *bool,
        meta: []const u8,
    ) bool {
        return self.treeFolderNodeEx(raw_label, indent_level, expanded, meta).expanded;
    }

    /// Extended variant of `treeFolderNode` that returns `TreeFolderResult` including `.right_clicked`.
    pub fn treeFolderNodeEx(
        self: *Context,
        raw_label: []const u8,
        indent_level: usize,
        expanded: *bool,
        meta: []const u8,
    ) TreeFolderResult {
        const resolved = self.resolveIdAndLabel(raw_label);
        const h: f32 = 24.0;
        const r = self.nextRect(0, h);
        const clicked = self.trackInteraction(resolved.wid, r, r);
        var right_clicked = false;

        if (self.pass == .input) {
            if (clicked) {
                expanded.* = !expanded.*;
                self.invalidateWindow();
            } else if (self.right_mouse_pressed and self.isHovered(r)) {
                right_clicked = true;
                self.markDirty(r);
            }
        }

        if (self.shouldPaint(r)) {
            const hovered = (self.hot_id == resolved.wid);
            if (hovered) {
                self.paint.setStyle(.fill);
                self.paint.setColor(self.theme.control_bg);
                self.canvas.drawRoundRect(r, 5.0, 5.0, self.paint);
            }

            const indent_px: f32 = @as(f32, @floatFromInt(indent_level)) * 13.0;
            tree_view_mod.drawTreeIndentGuides(self, r, indent_level, 9.0, 13.0);

            const chev_r = Rect.xywh(r.left + indent_px + 2.0, r.top + 4.0, 14.0, 16.0);
            self.drawIcon(
                if (expanded.*) .chevron_down else .chevron_right,
                chev_r,
                if (hovered) self.theme.text_primary else self.theme.text_muted,
            );

            const folder_r = Rect.xywh(r.left + indent_px + 17.0, r.top + 4.0, 16.0, 16.0);
            const folder_col = if (expanded.*) Color.rgb(96, 165, 250) else Color.rgb(148, 163, 184);
            self.drawIcon(if (expanded.*) .folder_open else .folder, folder_r, folder_col);

            const baseline_y = r.top + h * 0.68;
            const text_x = r.left + indent_px + 36.0;
            const mw = if (meta.len > 0) self.measureTextCached(self.font_mono, meta) else 0.0;
            const show_meta = (meta.len > 0 and r.left + indent_px + 80.0 + mw < r.right - 6.0);
            const text_max_right = if (show_meta) r.right - mw - 12.0 else r.right - 6.0;

            if (text_max_right > text_x) {
                const save_txt = self.canvas.save();
                defer self.canvas.restoreToCount(save_txt);
                self.canvas.clipRect(Rect.ltrb(text_x, r.top, text_max_right, r.bottom), .intersect, false);
                self.paint.setStyle(.fill);
                self.paint.setColor(if (hovered or expanded.*) self.theme.text_primary else Color.rgb(201, 209, 217));
                self.drawTextCached(self.font_body, resolved.display, text_x, baseline_y);
            }

            if (show_meta) {
                self.paint.setStyle(.fill);
                self.paint.setColor(self.theme.text_muted);
                self.drawTextCached(self.font_mono, meta, r.right - mw - 8.0, baseline_y - 0.5);
            }
        }

        return .{ .expanded = expanded.*, .clicked = clicked, .right_clicked = right_clicked };
    }

    /// Renders a breadcrumb bar with `>` segment separators and a bottom border line.
    pub fn breadcrumbs(self: *Context, crumb_text: []const u8) void {
        const r = self.nextRect(0, 24.0);
        if (!self.shouldPaint(r)) return;

        const save_count = self.canvas.save();
        defer self.canvas.restoreToCount(save_count);
        self.canvas.clipRect(r, .intersect, false);

        self.paint.setStyle(.fill);
        self.paint.setColor(self.theme.bg_canvas);
        self.canvas.drawRect(r, self.paint);

        self.paint.setColor(self.theme.text_muted);
        self.drawTextCached(self.font_mono, crumb_text, r.left + 14.0, r.top + 16.0);

        self.paint.setColor(self.theme.border_subtle);
        self.canvas.drawRect(Rect.xywh(r.left, r.bottom - 1.0, r.right - r.left, 1.0), self.paint);
    }

    /// Renders an interactive single-line text input field with placeholder text, focus border,
    /// backspace/clear handling (`Backspace`, `Cmd+Backspace`), and `Enter`/`Escape` signals.
    pub fn textField(
        self: *Context,
        raw_label: []const u8,
        buf: []u8,
        len: *usize,
        placeholder: []const u8,
        w_spec: Size,
    ) TextFieldResult {
        return self.textFieldEx(raw_label, buf, len, placeholder, .{ .w = w_spec });
    }

    /// Convenience wrapper around `textFieldEx` for a `platform.InlineString(capacity)` pointer.
    pub fn textFieldInline(
        self: *Context,
        raw_label: []const u8,
        inline_str: anytype,
        placeholder: []const u8,
        opts: TextFieldOptions,
    ) TextFieldResult {
        return self.textFieldEx(raw_label, &inline_str.buf, &inline_str.len, placeholder, opts);
    }

    const WrappedLine = text_input_mod.WrappedLine;
    const findVisualLineForOffset = text_input_mod.findVisualLineForOffset;

    fn getTextInputState(self: *Context, raw_label: []const u8) *TextInputState {
        if (self.platform_ctx != null) {
            return self.useState(TextInputState, raw_label, .{});
        }
        return &self.fallback_text_input_state;
    }

    fn computeWrappedLines(
        self: *Context,
        slice: []const u8,
        font: Font,
        max_line_w: f32,
        out: []WrappedLine,
    ) usize {
        if (out.len == 0) return 0;
        var count: usize = 0;
        var pos: usize = 0;
        while (pos <= slice.len and count < out.len) {
            const nl_pos = std.mem.indexOfScalarPos(u8, slice, pos, '\n');
            const hard_end = nl_pos orelse slice.len;
            const hard_line = slice[pos..hard_end];

            if (hard_line.len == 0) {
                out[count] = .{
                    .start = pos,
                    .end = pos,
                    .hard_start = pos,
                    .hard_end = hard_end,
                    .is_hard_end = true,
                };
                count += 1;
            } else {
                var sub_start = pos;
                while (sub_start < hard_end and count < out.len) {
                    const rem = slice[sub_start..hard_end];
                    if (self.measureTextCached(font, rem) <= max_line_w or count + 1 == out.len) {
                        out[count] = .{
                            .start = sub_start,
                            .end = hard_end,
                            .hard_start = pos,
                            .hard_end = hard_end,
                            .is_hard_end = true,
                        };
                        count += 1;
                        break;
                    }

                    // Step word-by-word (measuring at space boundaries first)
                    var last_space: usize = 0;
                    var scan: usize = 0;
                    while (scan < rem.len) {
                        // Advance through non-space word characters
                        while (scan < rem.len and rem[scan] != ' ') : (scan += 1) {}
                        // Include trailing spaces after the word
                        var after_spaces = scan;
                        while (after_spaces < rem.len and rem[after_spaces] == ' ') : (after_spaces += 1) {}

                        const check_end = if (after_spaces > scan) after_spaces else scan;
                        if (check_end == 0) break;
                        if (self.measureTextCached(font, rem[0..check_end]) <= max_line_w) {
                            last_space = check_end;
                            scan = check_end;
                        } else if (after_spaces > scan and self.measureTextCached(font, rem[0..scan]) <= max_line_w) {
                            // The word itself fits, and the trailing space crosses `max_line_w`
                            last_space = after_spaces;
                            break;
                        } else {
                            break;
                        }
                    }

                    var wrap_at: usize = last_space;
                    if (wrap_at == 0) {
                        // Single unbroken word exceeds `max_line_w`: step by UTF-8 codepoint
                        var split_idx: usize = 0;
                        while (split_idx < rem.len) {
                            var next_idx = split_idx + 1;
                            while (next_idx < rem.len and (rem[next_idx] & 0b1100_0000) == 0b1000_0000) : (next_idx += 1) {}
                            if (split_idx > 0 and self.measureTextCached(font, rem[0..next_idx]) > max_line_w) break;
                            split_idx = next_idx;
                        }
                        wrap_at = @max(@as(usize, 1), split_idx);
                    }

                    out[count] = .{
                        .start = sub_start,
                        .end = sub_start + wrap_at,
                        .hard_start = pos,
                        .hard_end = hard_end,
                        .is_hard_end = false,
                    };
                    count += 1;
                    sub_start += wrap_at;
                }
            }

            if (nl_pos) |nl| {
                pos = nl + 1;
            } else {
                break;
            }
        }
        if (count == 0) {
            out[0] = .{ .start = 0, .end = 0, .hard_start = 0, .hard_end = 0, .is_hard_end = true };
            return 1;
        }
        return count;
    }

    /// Measures the vertically auto-expanded pixel height for `textAreaEx` / `textAreaInlineEx`
    /// given `text`, target `width`, and `opts` (`min_lines` .. `max_lines`, `line_h`, `pad_x`, `pad_y`).
    pub fn measureTextAreaHeight(
        self: *Context,
        text: []const u8,
        width: f32,
        opts: TextAreaOptions,
    ) f32 {
        if (opts.max_lines == 0) return @max(24.0, opts.h);
        const text_font = if (opts.use_body_font) self.font_body else self.font_mono;
        const pad_x: f32 = opts.pad_x orelse (if (opts.borderless) 4.0 else 9.0);
        const max_line_w = @max(24.0, width - pad_x * 2.0);
        const min_l = @max(@as(usize, 1), opts.min_lines);
        const max_l = @max(min_l, opts.max_lines);
        if (text.len == 0) {
            return @as(f32, @floatFromInt(min_l)) * opts.line_h + opts.pad_y * 2.0;
        }
        var vlines: [256]WrappedLine = undefined;
        const vline_count = self.computeWrappedLines(text, text_font, max_line_w, &vlines);
        const vis_lines = std.math.clamp(vline_count, min_l, max_l);
        return @as(f32, @floatFromInt(vis_lines)) * opts.line_h + opts.pad_y * 2.0;
    }

    fn handleCommonTextKey(
        self: *Context,
        st: *TextInputState,
        buf: []u8,
        len: *usize,
        kev: platform.KeyEvent,
        allow_newlines: bool,
        allow_image_paste: bool,
    ) struct { handled: bool, changed: bool, visual_dirty: bool, pasted_image: ?platform.ClipboardImage = null } {
        const primary_mod = kev.cmd or kev.ctrl;
        const s = buf[0..@min(len.*, buf.len)];
        const cur: usize = @min(@as(usize, st.cursor), s.len);

        switch (kev.key) {
            .key_a => {
                if (primary_mod) {
                    st.selectAll(s.len);
                    return .{ .handled = true, .changed = false, .visual_dirty = true };
                }
            },
            .key_c => {
                if (primary_mod) {
                    if (st.hasSelection()) {
                        if (self.platform_ctx) |pctx| {
                            _ = pctx.setClipboardText(s[st.selStart()..st.selEnd()]);
                        }
                    }
                    return .{ .handled = true, .changed = false, .visual_dirty = false };
                }
            },
            .key_x => {
                if (primary_mod) {
                    if (st.hasSelection()) {
                        if (self.platform_ctx) |pctx| {
                            _ = pctx.setClipboardText(s[st.selStart()..st.selEnd()]);
                        }
                        st.saveUndo(buf, len.*);
                        const ch = st.deleteSelection(buf, len);
                        return .{ .handled = true, .changed = ch, .visual_dirty = ch };
                    }
                    return .{ .handled = true, .changed = false, .visual_dirty = false };
                }
            },
            .key_v => {
                if (primary_mod) {
                    if (self.platform_ctx) |pctx| {
                        if (allow_image_paste) {
                            if (pctx.getClipboardImageAlloc(self.arena)) |clip_img| {
                                return .{ .handled = true, .changed = false, .visual_dirty = true, .pasted_image = clip_img };
                            }
                        }
                        if (pctx.getClipboardTextAlloc(self.arena)) |clip| {
                            st.saveUndo(buf, len.*);
                            const ch = st.insertBytes(buf, len, clip, allow_newlines);
                            return .{ .handled = true, .changed = ch, .visual_dirty = ch };
                        }
                    }
                    return .{ .handled = true, .changed = false, .visual_dirty = false };
                }
            },
            .key_z => {
                if (primary_mod) {
                    const ch = st.performUndoSwap(buf, len);
                    return .{ .handled = true, .changed = ch, .visual_dirty = ch };
                }
            },
            .left => {
                if (!kev.shift and st.hasSelection() and !kev.cmd and !kev.alt) {
                    const target: u32 = @intCast(st.selStart());
                    st.cursor = target;
                    st.anchor = target;
                } else {
                    const target: usize = if (kev.cmd)
                        (if (std.mem.lastIndexOfScalar(u8, s[0..cur], '\n')) |nl| nl + 1 else 0)
                    else if (kev.alt)
                        code_editor_mod.prevWordBoundary(s, cur)
                    else
                        code_editor_mod.prevGraphemeBoundary(s, cur);
                    st.cursor = @intCast(target);
                    if (!kev.shift) st.anchor = st.cursor;
                }
                return .{ .handled = true, .changed = false, .visual_dirty = true };
            },
            .right => {
                if (!kev.shift and st.hasSelection() and !kev.cmd and !kev.alt) {
                    const target: u32 = @intCast(st.selEnd());
                    st.cursor = target;
                    st.anchor = target;
                } else {
                    const target: usize = if (kev.cmd)
                        (std.mem.indexOfScalarPos(u8, s, cur, '\n') orelse s.len)
                    else if (kev.alt)
                        code_editor_mod.nextWordBoundary(s, cur)
                    else
                        code_editor_mod.nextGraphemeBoundary(s, cur);
                    st.cursor = @intCast(target);
                    if (!kev.shift) st.anchor = st.cursor;
                }
                return .{ .handled = true, .changed = false, .visual_dirty = true };
            },
            .home => {
                const target: usize = if (std.mem.lastIndexOfScalar(u8, s[0..cur], '\n')) |nl| nl + 1 else 0;
                st.cursor = @intCast(target);
                if (!kev.shift) st.anchor = st.cursor;
                return .{ .handled = true, .changed = false, .visual_dirty = true };
            },
            .end => {
                const target: usize = std.mem.indexOfScalarPos(u8, s, cur, '\n') orelse s.len;
                st.cursor = @intCast(target);
                if (!kev.shift) st.anchor = st.cursor;
                return .{ .handled = true, .changed = false, .visual_dirty = true };
            },
            .backspace => {
                st.saveUndo(buf, len.*);
                if (st.hasSelection()) {
                    const ch = st.deleteSelection(buf, len);
                    return .{ .handled = true, .changed = ch, .visual_dirty = ch };
                } else if (cur > 0) {
                    const target: usize = if (kev.cmd) blk: {
                        const line_start = if (std.mem.lastIndexOfScalar(u8, s[0..cur], '\n')) |nl| nl + 1 else 0;
                        break :blk if (line_start < cur) line_start else (line_start - 1);
                    } else if (kev.alt)
                        code_editor_mod.prevWordBoundary(s, cur)
                    else
                        code_editor_mod.prevGraphemeBoundary(s, cur);
                    const ch = st.deleteRange(buf, len, target, cur);
                    return .{ .handled = true, .changed = ch, .visual_dirty = ch };
                }
                return .{ .handled = true, .changed = false, .visual_dirty = false };
            },
            .delete_forward => {
                st.saveUndo(buf, len.*);
                if (st.hasSelection()) {
                    const ch = st.deleteSelection(buf, len);
                    return .{ .handled = true, .changed = ch, .visual_dirty = ch };
                } else if (cur < s.len) {
                    const target: usize = if (kev.cmd)
                        (std.mem.indexOfScalarPos(u8, s, cur, '\n') orelse s.len)
                    else if (kev.alt)
                        code_editor_mod.nextWordBoundary(s, cur)
                    else
                        code_editor_mod.nextGraphemeBoundary(s, cur);
                    const ch = st.deleteRange(buf, len, cur, target);
                    return .{ .handled = true, .changed = ch, .visual_dirty = ch };
                }
                return .{ .handled = true, .changed = false, .visual_dirty = false };
            },
            else => return .{ .handled = false, .changed = false, .visual_dirty = false },
        }
        return .{ .handled = false, .changed = false, .visual_dirty = false };
    }

    /// Renders an interactive single-line text input field with customizable `TextFieldOptions`
    /// (including borderless composer mode and body vs. mono font selection).
    pub fn textFieldEx(
        self: *Context,
        raw_label: []const u8,
        buf: []u8,
        len: *usize,
        placeholder: []const u8,
        opts: TextFieldOptions,
    ) TextFieldResult {
        const resolved = self.resolveIdAndLabel(raw_label);
        const w = self.resolveWidth(opts.w);
        const r = self.nextRect(w, opts.h);
        var res = TextFieldResult{
            .focused = (self.focused_id == resolved.wid),
        };

        const st = self.getTextInputState(raw_label);
        const pad_x: f32 = opts.pad_x orelse (if (opts.borderless) 2.0 else 9.0);
        const text_font = if (opts.use_body_font) self.font_body else self.font_mono;
        const clamped_len = @min(len.*, buf.len);

        if (self.pass == .input) {
            st.syncExternalLen(clamped_len);
            if (self.select_all_wid == resolved.wid) {
                self.select_all_wid = 0;
                st.selectAll(clamped_len);
                self.markDirty(r);
                self.invalidateWindow();
            }
            const hovered = self.isHovered(r);
            if (hovered) {
                self.hot_id = resolved.wid;
                self.setCursor(.ibeam);
            }
            if (self.mouse_pressed and hovered) {
                self.focused_id = resolved.wid;
                self.active_id = resolved.wid;
                res.focused = true;

                const slice = buf[0..@min(len.*, buf.len)];
                const rel_x = @max(0.0, (self.mouse_x - (r.left + pad_x)) + st.scroll_x);
                const hit_off = code_editor_mod.findColumnAtX(self, text_font, slice, rel_x);

                if (self.mouse_click_count >= 3) {
                    st.selectAll(slice.len);
                    st.drag_mode = 3;
                    st.drag_origin_start = 0;
                    st.drag_origin_end = @intCast(slice.len);
                } else if (self.mouse_click_count == 2) {
                    const wr = code_editor_mod.wordRangeAtOffset(slice, hit_off);
                    st.anchor = @intCast(wr.start);
                    st.cursor = @intCast(wr.end);
                    st.drag_mode = 2;
                    st.drag_origin_start = @intCast(wr.start);
                    st.drag_origin_end = @intCast(wr.end);
                } else {
                    st.cursor = @intCast(hit_off);
                    if (!self.mouse_shift) {
                        st.anchor = @intCast(hit_off);
                    }
                    st.drag_mode = 1;
                }
                self.markDirty(r);
                self.invalidateWindow();
            } else if (self.mouse_down and self.active_id == resolved.wid and !self.mouse_pressed) {
                const slice = buf[0..@min(len.*, buf.len)];
                const rel_x = @max(0.0, (self.mouse_x - (r.left + pad_x)) + st.scroll_x);
                const drag_off = code_editor_mod.findColumnAtX(self, text_font, slice, rel_x);
                const prev_cur = st.cursor;
                const prev_anc = st.anchor;

                if (st.drag_mode >= 3) {
                    st.selectAll(slice.len);
                } else if (st.drag_mode == 2) {
                    const wr = code_editor_mod.wordRangeAtOffset(slice, drag_off);
                    if (wr.start < st.drag_origin_start) {
                        st.anchor = st.drag_origin_end;
                        st.cursor = @intCast(wr.start);
                    } else {
                        st.anchor = st.drag_origin_start;
                        st.cursor = @intCast(@max(@as(usize, st.drag_origin_end), wr.end));
                    }
                } else {
                    st.cursor = @intCast(drag_off);
                }
                if (st.cursor != prev_cur or st.anchor != prev_anc) {
                    self.markDirty(r);
                    self.invalidateWindow();
                }
            }
            if (self.mouse_released and self.active_id == resolved.wid) {
                self.active_id = 0;
                st.drag_mode = 0;
            }

            if (self.right_mouse_pressed and hovered) {
                self.focused_id = resolved.wid;
                res.focused = true;
                res.right_clicked = true;
                st.ctx_menu_open = true;
                st.ctx_menu_opened_this_frame = true;
                st.ctx_menu_x = self.mouse_x;
                st.ctx_menu_y = self.mouse_y;
                const slice = buf[0..@min(len.*, buf.len)];
                const rel_x = @max(0.0, (self.mouse_x - (r.left + pad_x)) + st.scroll_x);
                const hit_off = code_editor_mod.findColumnAtX(self, text_font, slice, rel_x);
                if (!st.hasSelection() or hit_off < st.selStart() or hit_off > st.selEnd()) {
                    st.cursor = @intCast(hit_off);
                    st.anchor = @intCast(hit_off);
                }
                self.markDirty(r);
                self.invalidateWindow();
            }

            if (st.ctx_menu_open) {
                const cm = self.handleTextInputContextMenu(resolved.wid, st, buf, len, false, false);
                if (cm.changed) res.changed = true;
                if (cm.visual_dirty or cm.changed) {
                    self.markDirty(r);
                    self.invalidateWindow();
                }
            }

            if (self.focused_id == resolved.wid) {
                var visual_dirty = false;
                for (self.key_events) |kev| {
                    const common = self.handleCommonTextKey(st, buf, len, kev, false, false);
                    if (common.handled) {
                        if (common.changed) res.changed = true;
                        if (common.visual_dirty) visual_dirty = true;
                        continue;
                    }
                    switch (kev.key) {
                        .enter => {
                            res.submitted = true;
                            visual_dirty = true;
                        },
                        .escape => {
                            res.escaped = true;
                            visual_dirty = true;
                        },
                        .up => {
                            if (kev.cmd) {
                                st.cursor = 0;
                                if (!kev.shift) st.anchor = 0;
                            }
                            res.arrow_up = true;
                            visual_dirty = true;
                        },
                        .down => {
                            if (kev.cmd) {
                                st.cursor = @intCast(@min(len.*, buf.len));
                                if (!kev.shift) st.anchor = st.cursor;
                            }
                            res.arrow_down = true;
                            visual_dirty = true;
                        },
                        .tab => {
                            res.tab_pressed = true;
                            visual_dirty = true;
                        },
                        else => {},
                    }
                }

                if (self.text_input.len > 0) {
                    st.saveUndo(buf, len.*);
                    if (st.insertBytes(buf, len, self.text_input, false)) {
                        res.changed = true;
                        visual_dirty = true;
                    }
                }

                // Keep caret visible horizontally inside the text field viewport
                const slice = buf[0..@min(len.*, buf.len)];
                const cur_clamped = @min(@as(usize, st.cursor), slice.len);
                const caret_px = if (cur_clamped > 0) self.measureTextCached(text_font, slice[0..cur_clamped]) else 0.0;
                const avail_w = @max(16.0, (r.right - r.left) - pad_x * 2.0 - 4.0);
                if (caret_px - st.scroll_x > avail_w) {
                    st.scroll_x = caret_px - avail_w;
                } else if (caret_px < st.scroll_x) {
                    st.scroll_x = @max(0.0, caret_px - 12.0);
                }
                const total_px = if (slice.len > 0) self.measureTextCached(text_font, slice) else 0.0;
                if (total_px <= avail_w) {
                    st.scroll_x = 0.0;
                }

                if (res.changed or res.submitted or res.escaped or
                    res.arrow_up or res.arrow_down or res.tab_pressed or visual_dirty)
                {
                    self.markDirty(r);
                }
            }
        }

        if (self.pass == .paint and self.select_all_wid == resolved.wid) {
            st.syncExternalLen(clamped_len);
            st.selectAll(clamped_len);
            self.select_all_wid = 0;
        }

        if (self.shouldPaint(r)) {
            const is_focused = (self.focused_id == resolved.wid);
            if (!opts.borderless) {
                self.paint.setStyle(.fill);
                self.paint.setColor(Color.rgb(13, 17, 24));
                self.canvas.drawRoundRect(r, 6.0, 6.0, self.paint);

                self.paint.setStyle(.stroke);
                self.paint.setStrokeWidth(if (is_focused) 1.4 else 1.0);
                self.paint.setColor(if (is_focused) self.theme.accent else self.theme.border_subtle);
                self.canvas.drawRoundRect(r, 6.0, 6.0, self.paint);
            }

            const save_c = self.canvas.save();
            defer self.canvas.restoreToCount(save_c);
            self.canvas.clipRect(r, .intersect, false);

            self.paint.setStyle(.fill);
            const slice = buf[0..@min(len.*, buf.len)];
            const baseline_y = r.top + opts.h * 0.68;
            const text_x = r.left + pad_x - st.scroll_x;

            if (is_focused and st.hasSelection() and slice.len > 0) {
                const s_start = @min(st.selStart(), slice.len);
                const s_end = @min(st.selEnd(), slice.len);
                if (s_end > s_start) {
                    const x0 = text_x + (if (s_start > 0) self.measureTextCached(text_font, slice[0..s_start]) else 0.0);
                    const x1 = text_x + self.measureTextCached(text_font, slice[0..s_end]);
                    const sel_y = r.top + (opts.h - 18.0) * 0.5;
                    self.paint.setColor(Color.argb(95, 56, 139, 253));
                    self.canvas.drawRoundRect(Rect.xywh(x0, sel_y, @max(2.0, x1 - x0), 18.0), 3.0, 3.0, self.paint);
                }
            }

            if (slice.len > 0) {
                self.paint.setColor(self.theme.text_primary);
                self.drawTextCached(text_font, slice, text_x, baseline_y);
            } else if (placeholder.len > 0) {
                self.paint.setColor(if (opts.borderless) Color.rgb(110, 118, 129) else self.theme.text_muted);
                self.drawTextCached(self.font_body, placeholder, r.left + pad_x, baseline_y);
            }

            if (is_focused) {
                const cur_clamped = @min(@as(usize, st.cursor), slice.len);
                const text_w = if (cur_clamped > 0) self.measureTextCached(text_font, slice[0..cur_clamped]) else 0.0;
                const caret_x = std.math.clamp(text_x + 0.5 + text_w, r.left + 2.0, r.right - 4.0);
                const caret_y = r.top + (opts.h - 16.0) * 0.5;
                if (self.platform_ctx) |pctx| {
                    pctx.ime_cursor_x = caret_x;
                    pctx.ime_cursor_y = caret_y;
                    pctx.ime_cursor_h = 16.0;
                }
                self.paint.setColor(self.theme.accent_hover);
                self.canvas.drawRoundRect(Rect.xywh(caret_x, caret_y, 2.0, 16.0), 1.0, 1.0, self.paint);
            }
        }
        if (self.pass == .paint and st.ctx_menu_open) {
            _ = self.handleTextInputContextMenu(resolved.wid, st, buf, len, false, false);
        }

        return res;
    }

    /// Convenience wrapper around `textArea` for a `platform.InlineString(capacity)` pointer.
    pub fn textAreaInline(
        self: *Context,
        raw_label: []const u8,
        inline_str: anytype,
        placeholder: []const u8,
        w_spec: Size,
        height: f32,
    ) TextFieldResult {
        return self.textAreaEx(raw_label, &inline_str.buf, &inline_str.len, placeholder, .{
            .w = w_spec,
            .h = @max(44.0, height),
        });
    }

    /// Convenience wrapper around `textAreaEx` for a `platform.InlineString(capacity)` pointer
    /// with full `TextAreaOptions` (including `min_lines`..`max_lines` vertical auto-expansion,
    /// `borderless`, `use_body_font`, and `submit_on_enter`).
    pub fn textAreaInlineEx(
        self: *Context,
        raw_label: []const u8,
        inline_str: anytype,
        placeholder: []const u8,
        opts: TextAreaOptions,
    ) TextFieldResult {
        return self.textAreaEx(raw_label, &inline_str.buf, &inline_str.len, placeholder, opts);
    }

    /// Renders an interactive multi-line text area input field with soft word-wrapping,
    /// newline support (`Enter` inserts a newline, `Cmd+Enter` / `Ctrl+Enter` submits),
    /// clipboard paste (`Cmd+V`), and auto-scrolling to keep the active cursor line in view.
    pub fn textArea(
        self: *Context,
        raw_label: []const u8,
        buf: []u8,
        len: *usize,
        placeholder: []const u8,
        w_spec: Size,
        height: f32,
    ) TextFieldResult {
        return self.textAreaEx(raw_label, buf, len, placeholder, .{
            .w = w_spec,
            .h = @max(44.0, height),
        });
    }

    /// Extended multi-line text area with configurable `TextAreaOptions`:
    ///   - Word-wrapping (`computeWrappedLines`) using either `font_body` (`use_body_font = true`) or `font_mono`
    ///   - Optional vertical auto-expansion from `min_lines` to `max_lines` (`max_lines > 0`)
    ///   - Optional `borderless` mode for embedding inside composite cards
    ///   - Configurable `submit_on_enter` (`true`: `Enter` submits and `Shift+Enter`/`Alt+Enter` inserts newline;
    ///     `false`: `Enter` inserts newline and `Cmd+Enter`/`Ctrl+Enter` submits)
    pub fn textAreaEx(
        self: *Context,
        raw_label: []const u8,
        buf: []u8,
        len: *usize,
        placeholder: []const u8,
        opts: TextAreaOptions,
    ) TextFieldResult {
        const resolved = self.resolveIdAndLabel(raw_label);
        const w = self.resolveWidth(opts.w);
        const st = self.getTextInputState(raw_label);
        const text_font = if (opts.use_body_font) self.font_body else self.font_mono;
        const pad_x: f32 = opts.pad_x orelse (if (opts.borderless) 4.0 else 9.0);
        const pad_y: f32 = opts.pad_y;
        const line_h: f32 = opts.line_h;
        const max_line_w = @max(24.0, w - pad_x * 2.0);

        var res = TextFieldResult{
            .focused = (self.focused_id == resolved.wid),
        };
        var vlines: [256]WrappedLine = undefined;
        var visual_dirty = false;

        if (self.pass == .input) {
            st.syncExternalLen(@min(len.*, buf.len));
            if (self.focused_id == resolved.wid) {
                for (self.key_events) |kev| {
                    const common = self.handleCommonTextKey(st, buf, len, kev, true, opts.allow_image_paste);
                    if (common.pasted_image) |img| res.pasted_image = img;
                    if (common.handled) {
                        if (common.changed) res.changed = true;
                        if (common.visual_dirty) visual_dirty = true;
                        continue;
                    }
                    switch (kev.key) {
                        .up => {
                            const slice = buf[0..@min(len.*, buf.len)];
                            if (kev.cmd) {
                                st.cursor = 0;
                                if (!kev.shift) st.anchor = 0;
                            } else {
                                const vline_count = self.computeWrappedLines(slice, text_font, max_line_w, &vlines);
                                const cur_vi = findVisualLineForOffset(vlines[0..vline_count], @min(@as(usize, st.cursor), slice.len));
                                if (cur_vi > 0) {
                                    const cur_vl = vlines[cur_vi];
                                    const col_x = self.measureTextCached(text_font, slice[cur_vl.start..@min(@as(usize, st.cursor), cur_vl.end)]);
                                    const prev_vl = vlines[cur_vi - 1];
                                    const new_col = code_editor_mod.findColumnAtX(self, text_font, slice[prev_vl.start..prev_vl.end], col_x);
                                    st.cursor = @intCast(prev_vl.start + new_col);
                                } else {
                                    st.cursor = 0;
                                    res.arrow_up = true;
                                }
                                if (!kev.shift) st.anchor = st.cursor;
                            }
                            visual_dirty = true;
                        },
                        .down => {
                            const slice = buf[0..@min(len.*, buf.len)];
                            if (kev.cmd) {
                                st.cursor = @intCast(slice.len);
                                if (!kev.shift) st.anchor = st.cursor;
                            } else {
                                const vline_count = self.computeWrappedLines(slice, text_font, max_line_w, &vlines);
                                const cur_vi = findVisualLineForOffset(vlines[0..vline_count], @min(@as(usize, st.cursor), slice.len));
                                if (cur_vi + 1 < vline_count) {
                                    const cur_vl = vlines[cur_vi];
                                    const col_x = self.measureTextCached(text_font, slice[cur_vl.start..@min(@as(usize, st.cursor), cur_vl.end)]);
                                    const next_vl = vlines[cur_vi + 1];
                                    const new_col = code_editor_mod.findColumnAtX(self, text_font, slice[next_vl.start..next_vl.end], col_x);
                                    st.cursor = @intCast(next_vl.start + new_col);
                                } else {
                                    st.cursor = @intCast(slice.len);
                                    res.arrow_down = true;
                                }
                                if (!kev.shift) st.anchor = st.cursor;
                            }
                            visual_dirty = true;
                        },
                        .enter => {
                            const should_submit = if (opts.submit_on_enter)
                                (!kev.shift and !kev.alt)
                            else
                                (kev.cmd or kev.ctrl);
                            if (should_submit) {
                                res.submitted = true;
                                visual_dirty = true;
                            } else {
                                st.saveUndo(buf, len.*);
                                if (st.insertBytes(buf, len, "\n", true)) {
                                    res.changed = true;
                                    visual_dirty = true;
                                }
                            }
                        },
                        .escape => {
                            res.escaped = true;
                            visual_dirty = true;
                        },
                        .tab => {
                            res.tab_pressed = true;
                            visual_dirty = true;
                        },
                        else => {},
                    }
                }

                if (self.text_input.len > 0) {
                    st.saveUndo(buf, len.*);
                    if (st.insertBytes(buf, len, self.text_input, true)) {
                        res.changed = true;
                        visual_dirty = true;
                    }
                }
            }
        }

        const box_h: f32 = if (self.pass == .input) blk: {
            const h_val = if (opts.max_lines > 0)
                self.measureTextAreaHeight(buf[0..@min(len.*, buf.len)], w, opts)
            else
                @max(24.0, opts.h);
            st.last_box_h = h_val;
            break :blk h_val;
        } else if (st.last_box_h > 0.0)
            st.last_box_h
        else if (opts.max_lines > 0)
            self.measureTextAreaHeight(buf[0..@min(len.*, buf.len)], w, opts)
        else
            @max(24.0, opts.h);

        const r = self.nextRect(w, box_h);
        const first_baseline_y = r.top + pad_y + line_h * 0.76;
        const max_vis_lines = @max(1, @as(usize, @intFromFloat(@floor(((r.bottom - r.top) - @max(4.0, pad_y * 1.5)) / line_h))));
        const clamped_len = @min(len.*, buf.len);

        if (self.pass == .input) {
            if (self.select_all_wid == resolved.wid) {
                self.select_all_wid = 0;
                st.selectAll(clamped_len);
                self.markDirty(r);
                self.invalidateWindow();
            }
            const hovered = self.isHovered(r);
            if (hovered) {
                self.hot_id = resolved.wid;
                self.setCursor(.ibeam);
            }

            if (hovered and @abs(self.scroll_dy) > 0.1) {
                const slice = buf[0..@min(len.*, buf.len)];
                const vline_count = self.computeWrappedLines(slice, text_font, max_line_w, &vlines);
                if (vline_count > max_vis_lines) {
                    const max_scroll = vline_count - max_vis_lines;
                    const step: i32 = if (self.scroll_dy < 0) 1 else -1;
                    const cur_s: i32 = @intCast(@min(@as(usize, st.scroll_line), max_scroll));
                    const next_s: usize = @intCast(std.math.clamp(cur_s + step, 0, @as(i32, @intCast(max_scroll))));
                    if (next_s != st.scroll_line) {
                        st.scroll_line = @intCast(next_s);
                        self.markDirty(r);
                        self.invalidateWindow();
                    }
                    self.scroll_dy = 0;
                }
            }

            if (self.mouse_pressed and hovered) {
                self.focused_id = resolved.wid;
                self.active_id = resolved.wid;
                res.focused = true;

                const slice = buf[0..@min(len.*, buf.len)];
                const vline_count = self.computeWrappedLines(slice, text_font, max_line_w, &vlines);
                const max_scroll = if (vline_count > max_vis_lines) vline_count - max_vis_lines else 0;
                const start_line = @min(@as(usize, st.scroll_line), max_scroll);
                const rel_y = @max(0.0, self.mouse_y - (r.top + pad_y));
                const clicked_vis: usize = @intFromFloat(@floor(rel_y / line_h));
                const target_vi = @min(start_line + clicked_vis, vline_count - 1);
                const vl = vlines[target_vi];
                const rel_x = @max(0.0, self.mouse_x - (r.left + pad_x));
                const hit_off = vl.start + code_editor_mod.findColumnAtX(self, text_font, slice[vl.start..vl.end], rel_x);

                if (self.mouse_click_count >= 3) {
                    const line_end_with_nl = if (vl.hard_end < slice.len and slice[vl.hard_end] == '\n') vl.hard_end + 1 else vl.hard_end;
                    st.anchor = @intCast(vl.hard_start);
                    st.cursor = @intCast(line_end_with_nl);
                    st.drag_mode = 3;
                    st.drag_origin_start = @intCast(vl.hard_start);
                    st.drag_origin_end = @intCast(line_end_with_nl);
                } else if (self.mouse_click_count == 2) {
                    const wr = code_editor_mod.wordRangeAtOffset(slice, hit_off);
                    st.anchor = @intCast(wr.start);
                    st.cursor = @intCast(wr.end);
                    st.drag_mode = 2;
                    st.drag_origin_start = @intCast(wr.start);
                    st.drag_origin_end = @intCast(wr.end);
                } else {
                    st.cursor = @intCast(hit_off);
                    if (!self.mouse_shift) {
                        st.anchor = @intCast(hit_off);
                    }
                    st.drag_mode = 1;
                }
                self.markDirty(r);
                self.invalidateWindow();
            } else if (self.mouse_down and self.active_id == resolved.wid and !self.mouse_pressed) {
                const slice = buf[0..@min(len.*, buf.len)];
                const vline_count = self.computeWrappedLines(slice, text_font, max_line_w, &vlines);
                const max_scroll = if (vline_count > max_vis_lines) vline_count - max_vis_lines else 0;
                const start_line = @min(@as(usize, st.scroll_line), max_scroll);
                const rel_y = @max(0.0, self.mouse_y - (r.top + pad_y));
                const clicked_vis: usize = @intFromFloat(@floor(rel_y / line_h));
                const target_vi = @min(start_line + clicked_vis, vline_count - 1);
                const vl = vlines[target_vi];
                const rel_x = @max(0.0, self.mouse_x - (r.left + pad_x));
                const drag_off = vl.start + code_editor_mod.findColumnAtX(self, text_font, slice[vl.start..vl.end], rel_x);
                const prev_cur = st.cursor;
                const prev_anc = st.anchor;

                if (st.drag_mode >= 3) {
                    const line_end_with_nl = if (vl.hard_end < slice.len and slice[vl.hard_end] == '\n') vl.hard_end + 1 else vl.hard_end;
                    if (vl.hard_start < st.drag_origin_start) {
                        st.anchor = st.drag_origin_end;
                        st.cursor = @intCast(vl.hard_start);
                    } else {
                        st.anchor = st.drag_origin_start;
                        st.cursor = @intCast(@max(@as(usize, st.drag_origin_end), line_end_with_nl));
                    }
                } else if (st.drag_mode == 2) {
                    const wr = code_editor_mod.wordRangeAtOffset(slice, drag_off);
                    if (wr.start < st.drag_origin_start) {
                        st.anchor = st.drag_origin_end;
                        st.cursor = @intCast(wr.start);
                    } else {
                        st.anchor = st.drag_origin_start;
                        st.cursor = @intCast(@max(@as(usize, st.drag_origin_end), wr.end));
                    }
                } else {
                    st.cursor = @intCast(drag_off);
                }
                if (st.cursor != prev_cur or st.anchor != prev_anc) {
                    self.markDirty(r);
                    self.invalidateWindow();
                }
            }
            if (self.mouse_released and self.active_id == resolved.wid) {
                self.active_id = 0;
                st.drag_mode = 0;
            }

            if (self.right_mouse_pressed and hovered) {
                self.focused_id = resolved.wid;
                res.focused = true;
                res.right_clicked = true;
                st.ctx_menu_open = true;
                st.ctx_menu_opened_this_frame = true;
                st.ctx_menu_x = self.mouse_x;
                st.ctx_menu_y = self.mouse_y;
                const slice = buf[0..@min(len.*, buf.len)];
                const vline_count = self.computeWrappedLines(slice, text_font, max_line_w, &vlines);
                const max_scroll = if (vline_count > max_vis_lines) vline_count - max_vis_lines else 0;
                const start_line = @min(@as(usize, st.scroll_line), max_scroll);
                const rel_y = @max(0.0, self.mouse_y - (r.top + pad_y));
                const clicked_vis: usize = @intFromFloat(@floor(rel_y / line_h));
                const target_vi = @min(start_line + clicked_vis, vline_count - 1);
                const vl = vlines[target_vi];
                const rel_x = @max(0.0, self.mouse_x - (r.left + pad_x));
                const hit_off = vl.start + code_editor_mod.findColumnAtX(self, text_font, slice[vl.start..vl.end], rel_x);
                if (!st.hasSelection() or hit_off < st.selStart() or hit_off > st.selEnd()) {
                    st.cursor = @intCast(hit_off);
                    st.anchor = @intCast(hit_off);
                }
                self.markDirty(r);
                self.invalidateWindow();
            }

            if (st.ctx_menu_open) {
                const cm = self.handleTextInputContextMenu(resolved.wid, st, buf, len, true, opts.allow_image_paste);
                if (cm.pasted_image) |img| res.pasted_image = img;
                if (cm.changed) res.changed = true;
                if (cm.visual_dirty or cm.changed) {
                    self.markDirty(r);
                    self.invalidateWindow();
                }
            }

            if (self.focused_id == resolved.wid) {
                // Keep active caret visual line scrolled into view
                const slice = buf[0..@min(len.*, buf.len)];
                const vline_count = self.computeWrappedLines(slice, text_font, max_line_w, &vlines);
                const cur_vi = findVisualLineForOffset(vlines[0..vline_count], @min(@as(usize, st.cursor), slice.len));
                const max_scroll = if (vline_count > max_vis_lines) vline_count - max_vis_lines else 0;
                var scroll_line: usize = @min(@as(usize, st.scroll_line), max_scroll);
                if (cur_vi < scroll_line) {
                    scroll_line = cur_vi;
                } else if (cur_vi >= scroll_line + max_vis_lines) {
                    scroll_line = (cur_vi + 1) - max_vis_lines;
                }
                st.scroll_line = @intCast(scroll_line);

                if (res.changed or res.submitted or res.escaped or
                    res.arrow_up or res.arrow_down or res.tab_pressed or visual_dirty)
                {
                    self.markDirty(r);
                }
            }
        }

        if (self.pass == .paint and self.select_all_wid == resolved.wid) {
            st.syncExternalLen(clamped_len);
            st.selectAll(clamped_len);
            self.select_all_wid = 0;
        }

        if (self.shouldPaint(r)) {
            const is_focused = (self.focused_id == resolved.wid);
            if (!opts.borderless) {
                self.paint.setStyle(.fill);
                self.paint.setColor(Color.rgb(13, 17, 24));
                self.canvas.drawRoundRect(r, 6.0, 6.0, self.paint);

                self.paint.setStyle(.stroke);
                self.paint.setStrokeWidth(if (is_focused) 1.4 else 1.0);
                self.paint.setColor(if (is_focused) self.theme.accent else self.theme.border_subtle);
                self.canvas.drawRoundRect(r, 6.0, 6.0, self.paint);
            }

            const save_clip = self.canvas.save();
            defer self.canvas.restoreToCount(save_clip);
            const clip_inset: f32 = if (opts.borderless) 1.0 else 4.0;
            self.canvas.clipRect(Rect.ltrb(r.left + clip_inset, r.top + 1.0, r.right - clip_inset, r.bottom - 1.0), .intersect, false);

            self.paint.setStyle(.fill);
            const slice = buf[0..@min(len.*, buf.len)];
            const eff_placeholder = if (placeholder.len > 0) placeholder else opts.placeholder;

            if (slice.len == 0) {
                if (eff_placeholder.len > 0) {
                    self.paint.setColor(if (opts.borderless) Color.rgb(110, 118, 129) else self.theme.text_muted);
                    self.drawTextCached(self.font_body, eff_placeholder, r.left + pad_x, first_baseline_y);
                }
                if (is_focused) {
                    const caret_x = r.left + pad_x;
                    const caret_y = r.top + pad_y;
                    if (self.platform_ctx) |pctx| {
                        pctx.ime_cursor_x = caret_x;
                        pctx.ime_cursor_y = caret_y;
                        pctx.ime_cursor_h = line_h - 1.0;
                    }
                    self.paint.setColor(self.theme.accent_hover);
                    self.canvas.drawRoundRect(Rect.xywh(caret_x, caret_y, 2.0, @max(14.0, line_h - 2.0)), 1.0, 1.0, self.paint);
                }
            } else {
                const vline_count = self.computeWrappedLines(slice, text_font, max_line_w, &vlines);
                const max_scroll = if (vline_count > max_vis_lines) vline_count - max_vis_lines else 0;
                const start_line = @min(@as(usize, st.scroll_line), max_scroll);
                const vis_count = @min(max_vis_lines, vline_count - start_line);

                const has_sel = is_focused and st.hasSelection();
                const sel_s = st.selStart();
                const sel_e = st.selEnd();

                for (0..vis_count) |vi| {
                    const vl = vlines[start_line + vi];
                    const line_str = slice[vl.start..vl.end];
                    const by = first_baseline_y + @as(f32, @floatFromInt(vi)) * line_h;
                    const row_top = r.top + pad_y + @as(f32, @floatFromInt(vi)) * line_h;

                    if (has_sel) {
                        const line_sel_end_limit = if (vl.is_hard_end and vl.end < slice.len and slice[vl.end] == '\n') vl.end + 1 else vl.end;
                        if (sel_e > vl.start and sel_s < line_sel_end_limit) {
                            const s0 = @max(sel_s, vl.start) - vl.start;
                            const s1 = @min(sel_e, vl.end) - vl.start;
                            const x0 = r.left + pad_x + (if (s0 > 0) self.measureTextCached(text_font, line_str[0..s0]) else 0.0);
                            var x1 = r.left + pad_x + (if (s1 > 0) self.measureTextCached(text_font, line_str[0..s1]) else 0.0);
                            if (sel_e > vl.end and vl.is_hard_end) x1 += 6.0;
                            self.paint.setColor(Color.argb(95, 56, 139, 253));
                            self.canvas.drawRoundRect(Rect.xywh(x0, row_top, @max(2.0, x1 - x0), @max(14.5, line_h - 1.0)), 2.5, 2.5, self.paint);
                        }
                    }

                    if (line_str.len > 0) {
                        self.paint.setColor(self.theme.text_primary);
                        self.drawTextCached(text_font, line_str, r.left + pad_x, by);
                    }
                }

                if (is_focused) {
                    const cur_clamped = @min(@as(usize, st.cursor), slice.len);
                    const cur_vi = findVisualLineForOffset(vlines[0..vline_count], cur_clamped);
                    if (cur_vi >= start_line and cur_vi < start_line + vis_count) {
                        const vl = vlines[cur_vi];
                        const rel_vi = cur_vi - start_line;
                        const prefix_len = @min(cur_clamped - vl.start, vl.end - vl.start);
                        const prefix_w = if (prefix_len > 0) self.measureTextCached(text_font, slice[vl.start .. vl.start + prefix_len]) else 0.0;
                        const caret_x = @min(r.right - 6.0, r.left + pad_x + 0.5 + prefix_w);
                        const caret_y = r.top + pad_y + @as(f32, @floatFromInt(rel_vi)) * line_h;
                        if (self.platform_ctx) |pctx| {
                            pctx.ime_cursor_x = caret_x;
                            pctx.ime_cursor_y = caret_y;
                            pctx.ime_cursor_h = line_h - 1.0;
                        }
                        self.paint.setColor(self.theme.accent_hover);
                        self.canvas.drawRoundRect(Rect.xywh(caret_x, caret_y, 2.0, @max(14.0, line_h - 2.0)), 1.0, 1.0, self.paint);
                    }
                }

                if (vline_count > max_vis_lines) {
                    const track_h = @max(12.0, (r.bottom - r.top) - 4.0);
                    const thumb_h = @max(10.0, track_h * (@as(f32, @floatFromInt(max_vis_lines)) / @as(f32, @floatFromInt(vline_count))));
                    const scroll_ratio = if (max_scroll > 0)
                        @as(f32, @floatFromInt(start_line)) / @as(f32, @floatFromInt(max_scroll))
                    else
                        0.0;
                    const thumb_y = r.top + 2.0 + (track_h - thumb_h) * scroll_ratio;
                    self.paint.setColor(Color.argb(110, 110, 118, 129));
                    self.canvas.drawRoundRect(Rect.xywh(r.right - 3.5, thumb_y, 2.5, thumb_h), 1.25, 1.25, self.paint);
                }
            }
        }
        if (self.pass == .paint and st.ctx_menu_open) {
            _ = self.handleTextInputContextMenu(resolved.wid, st, buf, len, true, opts.allow_image_paste);
        }

        return res;
    }

    // ========================================================================
    // Markdown Renderer Component (`markdown` / `markdownEx`)
    // ========================================================================

    /// Renders a Markdown document into the active layout container with default options.
    pub fn markdown(self: *Context, source: []const u8) void {
        _ = markdown_mod.render(self, source, .{});
    }

    /// Renders a Markdown document with custom typography/display options and returns
    /// interaction metadata (such as hovered or clicked link URLs).
    pub fn markdownEx(self: *Context, source: []const u8, options: MarkdownOptions) MarkdownResult {
        return markdown_mod.render(self, source, options);
    }

    /// Renders a rounded chat/comment bubble with word-wrapped inline Markdown spans.
    pub fn markdownBubble(self: *Context, source: []const u8, options: MarkdownBubbleOptions) MarkdownResult {
        return markdown_mod.renderBubble(self, source, options);
    }

    // ========================================================================
    // Text & Code Editor Component (`codeEditor` / `textEditor`)
    // ========================================================================

    /// Renders an interactive multi-line Code / Text Editor with syntax highlighting,
    /// line numbers, indentation guides, selection, undo/redo, and optional minimap.
    pub fn codeEditor(
        self: *Context,
        widget_id_str: []const u8,
        width: f32,
        height: f32,
        editor_state: anytype,
        options: CodeEditorOptions,
    ) CodeEditorResult {
        return code_editor_mod.render(self, widget_id_str, width, height, editor_state, options);
    }

    /// Renders a clean multi-line Plain Text Editor (without minimap or code syntax highlighting by default).
    pub fn textEditor(
        self: *Context,
        widget_id_str: []const u8,
        width: f32,
        height: f32,
        editor_state: anytype,
    ) CodeEditorResult {
        return code_editor_mod.render(self, widget_id_str, width, height, editor_state, .{
            .language = .plain,
            .show_minimap = false,
            .show_indent_guides = false,
            .syntax_highlight = false,
            .auto_close_pairs = false,
        });
    }

    /// Renders a PTY-backed VT100 / xterm Virtual Terminal Emulator (`VTerm`) into the active container.
    pub fn vterm(
        self: *Context,
        widget_id_str: []const u8,
        width: f32,
        height: f32,
        vt: *VTerm,
        font_override: ?Font,
    ) bool {
        return vterm_mod.render(self, widget_id_str, width, height, vt, font_override);
    }

    /// Parses `vcd_src` once per frame in `self.arena` during `Pass.input` and reuses the cached
    /// `*const WaveformData` during `Pass.paint` across up to 4 concurrent VCD buffers.
    pub fn parseVcdCached(self: *Context, vcd_src: []const u8) *const WaveformData {
        self.vcd_cache_tick +%= 1;
        for (&self.vcd_cache_slots) |*slot| {
            if (slot.data) |cached| {
                if (slot.source_ptr == vcd_src.ptr and slot.source_len == vcd_src.len) {
                    slot.last_used_tick = self.vcd_cache_tick;
                    return cached;
                }
            }
        }
        const parsed = self.arena.create(WaveformData) catch {
            const Static = struct {
                var empty: WaveformData = .{};
            };
            return &Static.empty;
        };
        parseVcd(vcd_src, parsed);

        var victim_idx: usize = 0;
        var min_tick: u32 = std.math.maxInt(u32);
        for (self.vcd_cache_slots, 0..) |slot, idx| {
            if (slot.data == null) {
                victim_idx = idx;
                break;
            }
            if (slot.last_used_tick < min_tick) {
                min_tick = slot.last_used_tick;
                victim_idx = idx;
            }
        }
        self.vcd_cache_slots[victim_idx] = .{
            .source_ptr = vcd_src.ptr,
            .source_len = vcd_src.len,
            .data = parsed,
            .last_used_tick = self.vcd_cache_tick,
        };
        return parsed;
    }

    /// Parses `(raw_bytes, file_path)` once per frame in `self.arena` during `Pass.input` and reuses
    /// the cached `*const PdfDocumentData` during `Pass.paint` across up to 4 concurrent PDF documents.
    pub fn parsePdfCached(self: *Context, raw_bytes: []const u8, file_path: []const u8) *const PdfDocumentData {
        self.pdf_cache_tick +%= 1;
        for (&self.pdf_cache_slots) |*slot| {
            if (slot.data) |cached| {
                if (slot.bytes_ptr == raw_bytes.ptr and
                    slot.bytes_len == raw_bytes.len and
                    slot.path_ptr == file_path.ptr and
                    slot.path_len == file_path.len)
                {
                    slot.last_used_tick = self.pdf_cache_tick;
                    return cached;
                }
            }
        }
        const parsed = self.arena.create(PdfDocumentData) catch {
            const Static = struct {
                var empty: PdfDocumentData = .{};
            };
            return &Static.empty;
        };
        parsePdfDocument(raw_bytes, file_path, parsed);

        var victim_idx: usize = 0;
        var min_tick: u32 = std.math.maxInt(u32);
        for (self.pdf_cache_slots, 0..) |slot, idx| {
            if (slot.data == null) {
                victim_idx = idx;
                break;
            }
            if (slot.last_used_tick < min_tick) {
                min_tick = slot.last_used_tick;
                victim_idx = idx;
            }
        }
        self.pdf_cache_slots[victim_idx] = .{
            .bytes_ptr = raw_bytes.ptr,
            .bytes_len = raw_bytes.len,
            .path_ptr = file_path.ptr,
            .path_len = file_path.len,
            .data = parsed,
            .last_used_tick = self.pdf_cache_tick,
        };
        return parsed;
    }

    /// Parses `diff_text` once per frame in `self.arena` during `Pass.input` and reuses the cached
    /// `*const diff_viewer_mod.ParsedDiff` during `Pass.paint`.
    pub fn parseDiffCached(self: *Context, diff_text: []const u8) *const diff_viewer_mod.ParsedDiff {
        if (self.last_diff_data) |cached| {
            if (self.last_diff_source_ptr == diff_text.ptr and self.last_diff_source_len == diff_text.len) {
                return cached;
            }
        }
        const parsed = self.arena.create(diff_viewer_mod.ParsedDiff) catch {
            const Static = struct {
                var empty: diff_viewer_mod.ParsedDiff = .{};
            };
            return &Static.empty;
        };
        parseUnifiedDiff(diff_text, parsed);
        self.last_diff_source_ptr = diff_text.ptr;
        self.last_diff_source_len = diff_text.len;
        self.last_diff_data = parsed;
        return parsed;
    }

    /// Renders an interactive Digital Waveform & Logic Analyzer (`WaveformData`) into the active container.
    pub fn waveformViewer(
        self: *Context,
        widget_id_str: []const u8,
        width: f32,
        height: f32,
        data: *const WaveformData,
        view: *WaveformViewState,
    ) void {
        waveform_mod.renderWaveformViewer(self, widget_id_str, width, height, data, view);
    }

    /// Parses `vcd_src` once per frame via `parseVcdCached` and renders the Waveform Viewer.
    pub fn waveformViewerSource(
        self: *Context,
        widget_id_str: []const u8,
        width: f32,
        height: f32,
        vcd_src: []const u8,
        view: *WaveformViewState,
    ) void {
        const data = self.parseVcdCached(vcd_src);
        waveform_mod.renderWaveformViewer(self, widget_id_str, width, height, data, view);
    }

    /// Renders an interactive Unified / Side-by-Side Git Diff Viewer (`DiffViewState`) into the active container.
    pub fn diffViewer(
        self: *Context,
        widget_id_str: []const u8,
        width: f32,
        height: f32,
        diff_text: []const u8,
        view: *DiffViewState,
        opts: DiffViewerOptions,
    ) DiffViewResult {
        return diff_viewer_mod.renderDiffViewer(self, widget_id_str, width, height, diff_text, view, opts);
    }

    /// Renders an interactive PDF Document Viewer (`PdfViewState`) with CoreGraphics page rasterization,
    /// outline navigation rail, live search highlights, and text extraction inspector.
    pub fn pdfViewer(
        self: *Context,
        widget_id_str: []const u8,
        width: f32,
        height: f32,
        doc: *const PdfDocumentData,
        view: *PdfViewState,
        opts: PdfViewerOptions,
    ) PdfViewerResult {
        return pdf_viewer_mod.renderPdfViewer(self, widget_id_str, width, height, doc, view, opts);
    }

    /// Parses `(opts.raw_bytes, opts.file_path)` once per frame via `parsePdfCached` and renders the PDF Viewer.
    pub fn pdfViewerSource(
        self: *Context,
        widget_id_str: []const u8,
        width: f32,
        height: f32,
        view: *PdfViewState,
        opts: PdfViewerOptions,
    ) PdfViewerResult {
        const doc = self.parsePdfCached(opts.raw_bytes, opts.file_path);
        return pdf_viewer_mod.renderPdfViewer(self, widget_id_str, width, height, doc, view, opts);
    }

    /// Renders an interactive Image & Vector Viewer (`ImageViewState`) with zoom/pan controls,
    /// backdrop switcher, nearest/linear filter toggle, 90° rotation, and live pixel eyedropper.
    pub fn imageViewer(
        self: *Context,
        widget_id_str: []const u8,
        width: f32,
        height: f32,
        view: *ImageViewState,
        opts: ImageViewerOptions,
    ) ImageViewerResult {
        return image_viewer_mod.renderImageViewer(self, widget_id_str, width, height, view, opts);
    }

    // ========================================================================
    // Recursive Binary Split Tree & 5-Zone Docking (`splitTree` / `dock_mod`)
    // ========================================================================

    /// Recursively lays out a `SplitTree` with interactive `splitterSash` handles at every internal branch.
    pub fn splitTree(
        self: *Context,
        tree: anytype,
        height: f32,
        min_ratio: f32,
        max_ratio: f32,
        ctx: anytype,
        comptime buildLeafFn: fn (@TypeOf(ctx), usize, usize, Size, f32) void,
    ) void {
        dock_mod.renderSplitTree(self, tree, height, min_ratio, max_ratio, ctx, buildLeafFn);
    }

    /// Recursively lays out a `SplitTree` with configurable `SplitTreeOptions` (including optional vertical sash).
    pub fn splitTreeEx(
        self: *Context,
        tree: anytype,
        height: f32,
        opts: SplitTreeOptions,
        ctx: anytype,
        comptime buildLeafFn: fn (@TypeOf(ctx), usize, usize, Size, f32) void,
    ) void {
        dock_mod.renderSplitTreeEx(self, tree, height, opts, ctx, buildLeafFn);
    }

    /// Hit-tests the current mouse position against `pane_rects` to detect a 5-zone dock drop target.
    pub fn detectDockDropTarget(
        self: *const Context,
        pane_rects: []const c.sk_rect_t,
        header_height: f32,
        source_pane: usize,
    ) ?DockDropTarget {
        return dock_mod.detectDockDropTarget(self.mouse_x, self.mouse_y, pane_rects, header_height, source_pane);
    }

    /// Renders a translucent accent highlight rectangle for a dock drop target zone.
    pub fn drawDockDropPreview(self: *Context, preview_rect: c.sk_rect_t) void {
        dock_mod.drawDockDropPreview(self, preview_rect);
    }

    /// Renders a floating ghost tab pill next to the mouse cursor while dragging a tab.
    pub fn drawDragGhostPill(self: *Context, label_text: []const u8, dot_color: u32) void {
        dock_mod.drawDragGhostPill(self, label_text, dot_color);
    }

    // ========================================================================
    // Declarative Overlays, Prompt Modals, Action Context Menus & Status Segments (`overlays_mod`)
    // ========================================================================

    /// Ensures focus is trapped inside `input_wid` when a modal overlay is open.
    pub fn ensureOverlayInputFocus(
        self: *Context,
        input_wid: WidgetId,
        legacy_alias_ids: []const WidgetId,
    ) void {
        overlays_mod.ensureOverlayInputFocus(self, input_wid, legacy_alias_ids);
    }

    /// Renders a complete floating text-input prompt modal and returns `.none`, `.confirmed`, or `.cancelled`.
    pub fn promptModal(
        self: *Context,
        comptime capacity: usize,
        id_scope: []const u8,
        modal_rect: c.sk_rect_t,
        buf: *platform.InlineString(capacity),
        config: PromptModalConfig,
    ) PromptModalResult {
        return overlays_mod.promptModal(self, capacity, id_scope, modal_rect, buf, config);
    }

    /// Renders an interactive file & folder picker modal with live directory listing,
    /// quick navigation (`↑ Up`, `~ Home`, `. CWD`), keyboard navigation (`Up`/`Down`/`Tab`/`Enter`/`Esc`),
    /// and returns `.none`, `.confirmed`, or `.cancelled`.
    pub fn filePickerModal(
        self: *Context,
        comptime capacity: usize,
        id_scope: []const u8,
        modal_rect: c.sk_rect_t,
        buf: *platform.InlineString(capacity),
        selected_idx: *usize,
        config: FilePickerModalConfig,
    ) PromptModalResult {
        return overlays_mod.filePickerModal(self, capacity, id_scope, modal_rect, buf, selected_idx, config);
    }

    /// Renders a typed-action right-click context menu and returns the clicked `?Action` enum tag.
    pub fn contextMenuActions(
        self: *Context,
        comptime Action: type,
        id_str: []const u8,
        state_or_anchor: anytype,
        action_items: []const ActionMenuItem(Action),
    ) ?Action {
        return overlays_mod.contextMenuActions(self, Action, id_str, state_or_anchor, action_items);
    }

    /// Renders a status bar dot + monospace text indicator segment.
    pub fn statusDotIndicator(self: *Context, dot_color: u32, text: []const u8, text_color: ?u32) void {
        overlays_mod.statusDotIndicator(self, dot_color, text, text_color);
    }

    /// Renders a monospace status bar text segment.
    pub fn statusTextSegment(self: *Context, text: []const u8, text_color: ?u32) void {
        overlays_mod.statusTextSegment(self, text, text_color);
    }

    /// Begins laying out and rendering a responsive per-pane mode-line inside `bar_r`.
    pub fn beginModeLine(
        self: *Context,
        id_str: []const u8,
        bar_r: layout_mod.Rect,
        opts: ModeLineOptions,
    ) ModeLine {
        return mode_line_mod.beginModeLine(self, id_str, bar_r, opts);
    }

    // ========================================================================
    // Plain-Text Wrapping, Virtualized Lists & Reusable Cards (`virtual_list_mod` / `cards_mod`)
    // ========================================================================

    pub fn wrapText(self: *Context, font_or_ptr: anytype, text: []const u8, max_width: f32) []const []const u8 {
        return virtual_list_mod.wrapPlainText(self, font_or_ptr, text, max_width);
    }

    pub fn wrappedLabel(self: *Context, text: []const u8, opts: WrappedLabelOptions) void {
        virtual_list_mod.wrappedLabel(self, text, opts);
    }

    pub fn inlineStepRow(
        self: *Context,
        icon: []const u8,
        icon_color: u32,
        label_text: []const u8,
        right_badge: []const u8,
    ) void {
        cards_mod.inlineStepRow(self, icon, icon_color, label_text, right_badge);
    }

    pub fn inlineStepRowEx(
        self: *Context,
        raw_id: []const u8,
        icon: []const u8,
        icon_color: u32,
        label_text: []const u8,
        right_badge: []const u8,
    ) InlineStepRowResult {
        return cards_mod.inlineStepRowEx(self, raw_id, icon, icon_color, label_text, right_badge);
    }

    pub fn thinkingDisclosure(
        self: *Context,
        id_key: []const u8,
        idx: usize,
        preview_title: []const u8,
        body_text: []const u8,
        default_open: bool,
    ) void {
        cards_mod.thinkingDisclosure(self, id_key, idx, preview_title, body_text, default_open);
    }

    pub fn thinkingDisclosureEx(
        self: *Context,
        id_key: []const u8,
        idx: usize,
        preview_title: []const u8,
        body_text: []const u8,
        default_open: bool,
        opts: ThinkingDisclosureOptions,
    ) ThinkingDisclosureResult {
        return cards_mod.thinkingDisclosureEx(self, id_key, idx, preview_title, body_text, default_open, opts);
    }

    pub fn commandExecutionCard(
        self: *Context,
        id_key: []const u8,
        idx: usize,
        cmd_line: []const u8,
        output_body: []const u8,
        status: CommandCardStatus,
    ) CommandCardAction {
        return cards_mod.commandExecutionCard(self, id_key, idx, cmd_line, output_body, status);
    }

    pub fn commandExecutionCardEx(
        self: *Context,
        id_key: []const u8,
        idx: usize,
        cmd_line: []const u8,
        output_body: []const u8,
        status: CommandCardStatus,
        opts: CommandCardOptions,
    ) CommandCardResult {
        return cards_mod.commandExecutionCardEx(self, id_key, idx, cmd_line, output_body, status, opts);
    }

    pub fn selectableOptionCard(
        self: *Context,
        id_str: []const u8,
        opt_label: []const u8,
        is_recommended: bool,
        is_selected: bool,
        is_multi: bool,
        max_text_w: f32,
    ) bool {
        return cards_mod.selectableOptionCard(self, id_str, opt_label, is_recommended, is_selected, is_multi, max_text_w);
    }

    pub fn menuItemWithSubtrigger(
        self: *Context,
        id_str: []const u8,
        label_text: []const u8,
        selected: bool,
        subtrigger_label: ?[]const u8,
        subtrigger_open: bool,
    ) SplitMenuItemResult {
        return cards_mod.menuItemWithSubtrigger(self, id_str, label_text, selected, subtrigger_label, subtrigger_open);
    }

    pub fn attachmentGallery(
        self: *Context,
        id_prefix: []const u8,
        items: []const AttachmentDisplayItem,
        opts: AttachmentStripOptions,
    ) ?usize {
        return cards_mod.attachmentGallery(self, id_prefix, items, opts);
    }

    pub fn emptyStateHero(
        self: *Context,
        rect: layout_mod.Rect,
        title: []const u8,
        subtitle: []const u8,
        hint: ?[]const u8,
    ) void {
        cards_mod.emptyStateHero(self, rect, title, subtitle, hint);
    }

    // ========================================================================
    // Interactive 2D Canvas Stage (`stage_mod`) & Property Inspector / Toasts (`inspector_mod`)
    // ========================================================================

    pub fn beginCanvasStage(
        self: *Context,
        id_str: []const u8,
        vp: *Viewport2DState,
        opts: CanvasStageOptions,
    ) CanvasStageScope {
        return stage_mod.beginCanvasStage(self, id_str, vp, opts);
    }

    pub fn dragFloat(
        self: *Context,
        label_str: []const u8,
        value: *f32,
        speed: f32,
        min_val: f32,
        max_val: f32,
        decimals: u8,
    ) bool {
        return inspector_mod.dragFloat(self, label_str, value, speed, min_val, max_val, decimals);
    }

    pub fn segmentedControl(
        self: *Context,
        comptime EnumT: type,
        id_str: []const u8,
        value: *EnumT,
    ) bool {
        return inspector_mod.segmentedControl(self, EnumT, id_str, value);
    }

    pub fn segmentedControlLabels(
        self: *Context,
        id_str: []const u8,
        labels: []const []const u8,
        selected_idx: *usize,
    ) bool {
        return inspector_mod.segmentedControlLabels(self, id_str, labels, selected_idx);
    }

    pub fn colorSwatchPicker(
        self: *Context,
        id_str: []const u8,
        color: *u32,
        presets: []const u32,
    ) bool {
        return inspector_mod.colorSwatchPicker(self, id_str, color, presets);
    }

    pub fn animateFloat(
        self: *Context,
        id_str: []const u8,
        target: f32,
        lerp_factor: f32,
    ) f32 {
        return inspector_mod.animateFloat(self, id_str, target, lerp_factor);
    }

    pub fn renderToasts(
        self: *Context,
        comptime cap: usize,
        queue: *ToastQueue(cap),
        viewport_rect: layout_mod.Rect,
    ) void {
        inspector_mod.renderToasts(self, cap, queue, viewport_rect);
    }

    /// Renders a virtualized, sortable, column-resizable multi-column DataGrid.
    pub fn dataGrid(
        self: *Context,
        comptime max_cols: usize,
        id_str: []const u8,
        grid_state: *DataGridState(max_cols),
        columns: []const DataGridColumn,
        row_count: usize,
        row_height: f32,
        ctx: anytype,
        comptime cellTextFn: anytype,
    ) DataGridResult {
        return data_grid_mod.renderDataGrid(self, max_cols, id_str, grid_state, columns, row_count, row_height, ctx, cellTextFn);
    }

    // ========================================================================
    // Skia-Accelerated Charts & Sparklines (`charts_mod`) & 2D Node Graph (`node_graph_mod`)
    // ========================================================================

    pub fn sparkline(
        self: *Context,
        id_str: []const u8,
        values: []const f32,
        opts: SparklineOptions,
    ) void {
        charts_mod.sparkline(self, id_str, values, opts);
    }

    pub fn lineChart(
        self: *Context,
        id_str: []const u8,
        series: []const ChartSeries,
        opts: LineChartOptions,
    ) LineChartResult {
        return charts_mod.lineChart(self, id_str, series, opts);
    }

    pub fn barChart(
        self: *Context,
        id_str: []const u8,
        items: []const BarChartItem,
        opts: BarChartOptions,
    ) ?usize {
        return charts_mod.barChart(self, id_str, items, opts);
    }

    pub fn nodeGraph(
        self: *Context,
        comptime max_nodes: usize,
        id_str: []const u8,
        state: *NodeGraphState(max_nodes),
        nodes: []const GraphNode,
        edges: []const GraphEdge,
        opts: NodeGraphOptions,
    ) NodeGraphResult {
        return node_graph_mod.nodeGraph(self, max_nodes, id_str, state, nodes, edges, opts);
    }

    /// Draws subtle vertical indent guide lines at each ancestor depth level inside `row_rect`
    /// when `self.shouldPaint(row_rect)`.
    pub fn drawTreeIndentGuides(
        self: *Context,
        row_rect: layout_mod.Rect,
        depth: usize,
        base_pad: f32,
        step_px: f32,
    ) void {
        tree_view_mod.drawTreeIndentGuides(self, row_rect, depth, base_pad, step_px);
    }

    /// Renders an indented inline tree text-input row (for renaming or creating a folder/file)
    /// with optional leading badge/chevron, indent guides, auto-focus + select-all, and
    /// `Enter` submit / `Escape` or outside-click cancel detection.
    pub fn treeInlineInputRow(
        self: *Context,
        comptime cap: usize,
        id_str: []const u8,
        depth: usize,
        prefix_badge: []const u8,
        prefix_color: u32,
        buf: *platform.InlineString(cap),
        placeholder: []const u8,
        opts: TreeInlineInputOptions,
    ) TreeInlineInputAction {
        return tree_view_mod.treeInlineInputRow(self, cap, id_str, depth, prefix_badge, prefix_color, buf, placeholder, opts);
    }
};

pub const overlays_mod = @import("overlays.zig");
pub const PromptModalConfig = overlays_mod.PromptModalConfig;
pub const PromptModalResult = overlays_mod.PromptModalResult;
pub const FilePickerModalConfig = overlays_mod.FilePickerModalConfig;
pub const ActionMenuItem = overlays_mod.ActionMenuItem;

pub const mode_line_mod = @import("mode_line.zig");
pub const ModeLine = mode_line_mod.ModeLine;
pub const ModeLineCursor = mode_line_mod.ModeLine;
pub const ModeLineOptions = mode_line_mod.ModeLineOptions;
pub const ModeLineClickResult = mode_line_mod.ModeLineClickResult;
pub const ModeLineIconKind = mode_line_mod.ModeLineIconKind;

test {
    _ = layout_mod;
    _ = markdown_mod;
    _ = code_editor_mod;
    _ = vterm_mod;
    _ = waveform_mod;
    _ = diff_viewer_mod;
    _ = pdf_viewer_mod;
    _ = image_viewer_mod;
    _ = dock_mod;
    _ = virtual_list_mod;
    _ = cards_mod;
    _ = stage_mod;
    _ = inspector_mod;
    _ = data_grid_mod;
    _ = charts_mod;
    _ = node_graph_mod;
    _ = tree_view_mod;
    _ = damage_mod;
    _ = icons_mod;
    _ = text_input_mod;
    _ = @import("text_cache.zig");
    _ = @import("overlays.zig");
    _ = @import("mode_line.zig");
    _ = @import("command_registry.zig");
}

test "DamageList: keeps disjoint dirty rects separate and culls middle widgets in shouldPaint" {
    const surface = try skia.Surface.initRasterN32Premul(1280, 800);
    defer surface.deinit();
    const paint = try Paint.init();
    defer paint.deinit();
    const font = try Font.init(null, 13.0);
    defer font.deinit();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var uic = Context{
        .arena = arena.allocator(),
        .canvas = surface.canvas(),
        .paint = paint,
        .font_title = font,
        .font_body = font,
        .font_mono = font,
    };
    defer uic.deinit();

    const win_rect = Rect.xywh(0, 0, 1280, 800);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 0, 0, false, false, false);
    uic.markDirty(Rect.xywh(20, 20, 10, 18));
    uic.markDirty(Rect.xywh(1200, 760, 50, 18));
    uic.endPass();

    try std.testing.expectEqual(@as(usize, 2), uic.damage_list.len);
    try std.testing.expect(uic.dirtyArea() < 2500.0);

    uic.clip_damage = uic.dirty_rect;
    uic.pass = .paint;
    // Top-left and bottom-right widgets should paint, while center widget is culled!
    try std.testing.expect(uic.shouldPaint(Rect.xywh(18, 18, 20, 20)));
    try std.testing.expect(uic.shouldPaint(Rect.xywh(1195, 755, 60, 24)));
    try std.testing.expect(!uic.shouldPaint(Rect.xywh(500, 350, 200, 100)));
}

test "widget system layout, SkTextBlob cache, scroll box, and damage-rect calculation" {
    const surface = try skia.Surface.initRasterN32Premul(320, 240);
    defer surface.deinit();

    const paint = try Paint.init();
    defer paint.deinit();
    paint.setAntiAlias(true);

    const font = try Font.init(null, 14.0);
    defer font.deinit();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var uic = Context{
        .arena = arena.allocator(),
        .canvas = surface.canvas(),
        .paint = paint,
        .font_title = font,
        .font_body = font,
        .font_mono = font,
    };
    defer uic.deinit();

    var toggled = false;
    var slider_val: f32 = 0.5;

    // Frame 1: Mouse press at (50, 25) inside first button
    uic.beginFrame(arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 320, 240), 50, 25, true, true, false);
    const clicked_press = uic.button("btn_test", "Click Me", 120);
    _ = uic.toggle("tog_test", "Enable Feature", &toggled);
    _ = uic.slider("sld_test", "Amount", &slider_val, 0.0, 1.0);
    uic.endFrame();
    try std.testing.expect(!clicked_press);

    // Paint pass exercises cached SkTextBlob rendering
    uic.beginPass(.paint, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 320, 240), 50, 25, true, true, false);
    _ = uic.button("btn_test", "Click Me", 120);
    _ = uic.toggle("tog_test", "Enable Feature", &toggled);
    _ = uic.slider("sld_test", "Amount", &slider_val, 0.0, 1.0);
    uic.endPass();

    // Frame 2: Mouse release at (50, 25) -> triggers button click and marks button dirty!
    _ = arena.reset(.retain_capacity);
    uic.beginFrame(arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 320, 240), 50, 25, false, false, true);
    const clicked_release = uic.button("btn_test", "Click Me", 120);
    uic.endFrame();
    try std.testing.expect(clicked_release);
    try std.testing.expect(uic.dirty_rect != null);

    // Frame 3: Scrollable container test with overflowing content
    _ = arena.reset(.retain_capacity);
    uic.scroll_dy = 0;
    uic.beginPass(.input, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 320, 240), 40, 40, false, false, false);
    _ = uic.beginScrollBox("scroll_test", 200, 100, .{ .padding = Padding.all(8), .gap = 8 });
    for (0..6) |_| {
        _ = uic.button("item_btn", "Row Item", 0);
    }
    uic.endScrollBox();
    uic.endPass();
    try std.testing.expect(uic.fallback_scroll_state.content_height > 100.0);

    // Frame 4: Scroll wheel down inside scroll box updates scroll_y and marks scroll box dirty
    _ = arena.reset(.retain_capacity);
    uic.scroll_dy = -30.0;
    uic.beginPass(.input, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 320, 240), 40, 40, false, false, false);
    _ = uic.beginScrollBox("scroll_test", 200, 100, .{ .padding = Padding.all(8), .gap = 8 });
    for (0..6) |_| {
        _ = uic.button("item_btn", "Row Item", 0);
    }
    uic.endScrollBox();
    uic.endPass();
    try std.testing.expectEqual(@as(f32, 30.0), uic.fallback_scroll_state.scroll_y);
    try std.testing.expect(uic.dirty_rect != null);

    // Frame 5: Declarative layout guards, scoped IDs, and high-level components
    _ = arena.reset(.retain_capacity);
    uic.scroll_dy = 0;
    uic.beginPass(.input, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 320, 240), 10, 10, false, false, false);
    {
        var r = uic.row(.{ .preset = .toolbar });
        defer r.end();

        var id1: u64 = 0;
        {
            var s1 = uic.scopedId("left_group");
            defer s1.end();
            id1 = uic.resolveIdAndLabel("Save##action").wid;
            _ = uic.btn("Save##action", .{ .w = .pixels(80) });
        }
        {
            var s2 = uic.scopedId("right_group");
            defer s2.end();
            const id2 = uic.resolveIdAndLabel("Save##action").wid;
            try std.testing.expect(id1 != id2);
        }
    }
    {
        var col = uic.column(.{ .w = .half, .preset = .panel_card });
        defer col.end();
        uic.sectionHeader("SETTINGS");
        _ = uic.checkbox("Auto Format", &toggled);
        _ = uic.sliderFloat("Zoom", &slider_val, 0.5, 2.0);
        _ = uic.listItem(.{ .label = "main.zig", .selected = true, .meta = "M" });
    }
    uic.endPass();

    // Frame 6: Horizontal scrolling container test (`scroll_dx` -> `scroll_x` & `content_width`)
    _ = arena.reset(.retain_capacity);
    uic.fallback_scroll_state = .{};
    uic.scroll_dx = 0;
    uic.scroll_dy = 0;
    uic.beginPass(.input, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 320, 240), 40, 40, false, false, false);
    {
        var h_scroll = uic.scrollPanel("h_scroll_test", .{
            .direction = .row,
            .w = .pixels(180),
            .h = .pixels(60),
            .gap = 8,
        });
        defer h_scroll.end();
        for (0..5) |i| {
            var item_id = uic.scopedId(i);
            defer item_id.end();
            _ = uic.btn("Stage", .{ .w = .pixels(90) });
        }
    }
    uic.endPass();
    try std.testing.expect(uic.fallback_scroll_state.content_width > 400.0);

    _ = arena.reset(.retain_capacity);
    uic.scroll_dx = -45.0;
    uic.beginPass(.input, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 320, 240), 40, 40, false, false, false);
    {
        var h_scroll = uic.scrollPanel("h_scroll_test", .{
            .direction = .row,
            .w = .pixels(180),
            .h = .pixels(60),
            .gap = 8,
        });
        defer h_scroll.end();
        for (0..5) |i| {
            var item_id = uic.scopedId(i);
            defer item_id.end();
            _ = uic.btn("Stage", .{ .w = .pixels(90) });
        }
    }
    uic.endPass();
    try std.testing.expectEqual(@as(f32, 45.0), uic.fallback_scroll_state.scroll_x);
    try std.testing.expect(uic.dirty_rect != null);

    // Frame 7: SplitPanes layout & interactive splitter sash resizing test
    _ = arena.reset(.retain_capacity);
    var split_ratio: f32 = 0.5;
    const SplitTestCtx = struct {
        uic: *Context,
        pane_widths: [2]f32 = .{ 0, 0 },
        fn buildPane(ctx: *@This(), idx: usize, w: Size, h: f32) void {
            var col = ctx.uic.column(.{ .w = w, .h = .pixels(h) });
            defer col.end();
            ctx.pane_widths[idx] = col.rect.right - col.rect.left;
        }
    };
    var split_ctx = SplitTestCtx{ .uic = &uic };

    // Press on splitter sash at x=159 (50% of 320w)
    uic.beginPass(.input, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 320, 240), 159, 100, true, true, false);
    uic.splitPanes("##test_split", false, 200.0, &split_ratio, 0.2, 0.8, &split_ctx, SplitTestCtx.buildPane);
    uic.endPass();
    try std.testing.expect(split_ctx.pane_widths[0] > 150.0 and split_ctx.pane_widths[0] < 160.0);
    try std.testing.expect(split_ctx.pane_widths[1] > 150.0 and split_ctx.pane_widths[1] < 160.0);

    // Drag splitter sash to x=224 (70% of 320w)
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 320, 240), 224, 100, true, false, false);
    uic.splitPanes("##test_split", false, 200.0, &split_ratio, 0.2, 0.8, &split_ctx, SplitTestCtx.buildPane);
    uic.endPass();
    try std.testing.expectApproxEqAbs(@as(f32, 0.7), split_ratio, 0.02);

    // Frame 8: Scoped ID path matching & promoted framework widgets (chip, menuItem, circularActionButton, banner, markdownBubble)
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.paint, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 320, 240), 10, 10, false, false, false);
    {
        var s_outer = uic.scopedId("vscode_workbench");
        defer s_outer.end();
        var s_inner = uic.scopedId("agy_agent_panel");
        defer s_inner.end();
        const actual_wid = uic.resolveIdAndLabel("##agy_prompt_input").wid;
        const path_wid = scopedIdPath(&.{ "vscode_workbench", "agy_agent_panel" }, "##agy_prompt_input");
        try std.testing.expectEqual(actual_wid, path_wid);
    }
    {
        var box_edges = uic.box(.{
            .h = .pixels(160),
            .border_edges = .bottom_only,
        });
        defer box_edges.end();
        _ = uic.chip("Fast##mode_chip", .{ .active = true, .min_w = 48.0, .max_w = 120.0 });
        _ = uic.btn("Auto Fit##fit_btn", .{ .w = Size.fitContent(60.0, 140.0) });
        _ = uic.menuItem("Planning##mode_item", true);
        _ = uic.circularActionButton("##send_btn", false, true);
        uic.banner("Test error banner", .err);
        _ = uic.markdownBubble("Hello `inline code` in bubble!", .{});
    }
    uic.endPass();

    // Frame 9: Verify clipCanvasToDamage inside a scrollPanel never erases middle items when hover jumps across rows
    const buildTreeFn = struct {
        fn build(ctx: *Context) void {
            var sp = ctx.scrollPanel("test_tree_scroll", .{
                .w = .pixels(200),
                .h = .pixels(200),
                .bg_color = Color.rgb(18, 23, 33),
                .padding = Padding.all(0),
                .gap = 0,
            });
            defer sp.end();
            for (0..5) |i| {
                var id_g = ctx.scopedId(i);
                defer id_g.end();
                _ = ctx.btn("Item", .{ .h = 24.0 });
            }
        }
    }.build;

    // Initial full paint with mouse hovering item 0 (y = 12)
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 320, 240), 50, 12, false, false, false);
    buildTreeFn(&uic);
    uic.endPass();
    uic.invalidateWindow();
    uic.clip_damage = Rect.xywh(0, 0, 320, 240);
    uic.beginPass(.paint, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 320, 240), 50, 12, false, false, false);
    buildTreeFn(&uic);
    uic.endPass();

    // Middle item 2 is at y = 48..72; verify its button fill color (Color.rgb(24, 32, 46)) is painted at (50, 60)
    const item2_before = try surface.peekPixelColor(50, 60);
    try std.testing.expectEqual(Color.rgb(24, 32, 46), item2_before);

    // Jump mouse hover directly from item 0 (y = 12) to item 4 (y = 108), creating 2 disjoint damage rects
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 320, 240), 50, 108, false, false, false);
    buildTreeFn(&uic);
    uic.endPass();
    try std.testing.expectEqual(@as(usize, 2), uic.damage_list.len);

    // Paint with clipCanvasToDamage: scrollPanel background fill must NOT overwrite item 2 at (50, 60)
    {
        const save_cnt = surface.canvas().save();
        defer surface.canvas().restoreToCount(save_cnt);
        uic.clipCanvasToDamage(uic.dirty_rect.?);
        uic.clip_damage = uic.dirty_rect;
        uic.beginPass(.paint, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 320, 240), 50, 108, false, false, false);
        buildTreeFn(&uic);
        uic.endPass();
    }
    const item2_after = try surface.peekPixelColor(50, 60);
    try std.testing.expectEqual(Color.rgb(24, 32, 46), item2_after);
}

test "ui.Context: textFieldEx and textArea hotkeys (Cmd+A, word jump, mid-string edit, undo) and multi-click selection" {
    const surface = try skia.Surface.initRasterN32Premul(320, 240);
    defer surface.deinit();
    const paint = try skia.Paint.init();
    defer paint.deinit();
    const font = try Font.init(null, 13.0);
    defer font.deinit();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var uic = Context{
        .arena = arena.allocator(),
        .canvas = surface.canvas(),
        .paint = paint,
        .font_title = font,
        .font_body = font,
        .font_mono = font,
    };
    defer uic.deinit();

    var tf_buf: [128]u8 = undefined;
    var tf_len: usize = 11;
    @memcpy(tf_buf[0..11], "hello world");

    // 1. Focus textFieldEx and press Alt+Left (move caret before "world"), then insert "big "
    uic.focused_id = uic.resolveIdAndLabel("##tf").wid;
    const alt_left = [_]platform.KeyEvent{.{ .key = .left, .alt = true }};
    uic.key_events = &alt_left;
    uic.text_input = "big ";
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 320, 240), 0, 0, false, false, false);
    const res1 = uic.textFieldEx("##tf", &tf_buf, &tf_len, "", .{ .w = .pixels(260), .h = 28 });
    uic.endPass();
    try std.testing.expect(res1.changed);
    try std.testing.expectEqualStrings("hello big world", tf_buf[0..tf_len]);

    // 2. Double-click on first word ("hello") at x = 15, y = 14 -> selects "hello" (0..5)
    uic.key_events = &.{};
    uic.text_input = "";
    uic.mouse_click_count = 2;
    uic.mouse_shift = false;
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 320, 240), 15, 14, true, true, false);
    _ = uic.textFieldEx("##tf", &tf_buf, &tf_len, "", .{ .w = .pixels(260), .h = 28 });
    uic.endPass();
    try std.testing.expectEqual(@as(u32, 0), uic.fallback_text_input_state.anchor);
    try std.testing.expectEqual(@as(u32, 5), uic.fallback_text_input_state.cursor);

    // 3. Triple-click at x = 15, y = 14 -> selects entire text field (0..15)
    uic.mouse_click_count = 3;
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 320, 240), 15, 14, true, true, false);
    _ = uic.textFieldEx("##tf", &tf_buf, &tf_len, "", .{ .w = .pixels(260), .h = 28 });
    uic.endPass();
    try std.testing.expectEqual(@as(u32, 0), uic.fallback_text_input_state.anchor);
    try std.testing.expectEqual(@as(u32, 15), uic.fallback_text_input_state.cursor);

    // 4. Cmd+A then type "replaced" -> replaces all text, then Cmd+Z undoes back to "hello big world"
    uic.mouse_click_count = 1;
    const cmd_a = [_]platform.KeyEvent{.{ .key = .key_a, .cmd = true }};
    uic.key_events = &cmd_a;
    uic.text_input = "replaced";
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 320, 240), 0, 0, false, false, false);
    _ = uic.textFieldEx("##tf", &tf_buf, &tf_len, "", .{ .w = .pixels(260), .h = 28 });
    uic.endPass();
    try std.testing.expectEqualStrings("replaced", tf_buf[0..tf_len]);

    const cmd_z = [_]platform.KeyEvent{.{ .key = .key_z, .cmd = true }};
    uic.key_events = &cmd_z;
    uic.text_input = "";
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 320, 240), 0, 0, false, false, false);
    _ = uic.textFieldEx("##tf", &tf_buf, &tf_len, "", .{ .w = .pixels(260), .h = 28 });
    uic.endPass();
    try std.testing.expectEqualStrings("hello big world", tf_buf[0..tf_len]);

    // 5. Test textArea multi-line Up arrow + mid-line edit + triple-click line selection
    uic.fallback_text_input_state = .{};
    var ta_buf: [128]u8 = undefined;
    var ta_len: usize = 11;
    @memcpy(ta_buf[0..11], "first\nsecond"[0..11]);
    ta_len = 12;
    @memcpy(ta_buf[0..12], "first\nsecond");

    uic.focused_id = uic.resolveIdAndLabel("##ta").wid;
    const up_and_end = [_]platform.KeyEvent{
        .{ .key = .up },
        .{ .key = .right, .cmd = true },
    };
    uic.key_events = &up_and_end;
    uic.text_input = "!";
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 320, 240), 0, 0, false, false, false);
    _ = uic.textArea("##ta", &ta_buf, &ta_len, "", .pixels(260), 80.0);
    uic.endPass();
    try std.testing.expectEqualStrings("first!\nsecond", ta_buf[0..ta_len]);

    // Paint pass with selection active in textArea
    uic.key_events = &cmd_a;
    uic.text_input = "";
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 320, 240), 0, 0, false, false, false);
    _ = uic.textArea("##ta", &ta_buf, &ta_len, "", .pixels(260), 80.0);
    uic.endPass();
    uic.invalidateWindow();
    uic.clip_damage = Rect.xywh(0, 0, 320, 240);
    uic.beginPass(.paint, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 320, 240), 0, 0, false, false, false);
    _ = uic.textArea("##ta", &ta_buf, &ta_len, "", .pixels(260), 80.0);
    uic.endPass();
    try std.testing.expectEqual(@as(u32, 0), uic.fallback_text_input_state.anchor);
    try std.testing.expectEqual(@as(u32, 13), uic.fallback_text_input_state.cursor);
    _ = waveform_mod;
    _ = app_runner_mod;
}

test "ui.Context: right-click contextMenu and built-in textFieldEx right-click menu 2-phase layout determinism" {
    const surface = try skia.Surface.initRasterN32Premul(400, 300);
    defer surface.deinit();
    const paint = try skia.Paint.init();
    defer paint.deinit();
    const font = try Font.init(null, 13.0);
    defer font.deinit();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var uic = Context{
        .arena = arena.allocator(),
        .canvas = surface.canvas(),
        .paint = paint,
        .font_title = font,
        .font_body = font,
        .font_mono = font,
    };
    defer uic.deinit();

    var menu_state = ContextMenuState{};
    var selected_item: ?usize = null;
    const menu_items = [_]ContextMenuItem{
        .{ .label = "Cut", .shortcut = "Cmd+X", .enabled = true },
        .{ .label = "Copy", .shortcut = "Cmd+C", .enabled = true },
        .{ .separator = true },
        .{ .label = "Delete", .shortcut = "Backspace", .enabled = true, .danger = true },
    };

    const buildMenuScene = struct {
        fn build(c_ctx: *Context, st: *ContextMenuState, items: []const ContextMenuItem, out_sel: *?usize) void {
            const target_r = c_ctx.nextRect(200, 80);
            if (c_ctx.rightClicked(target_r)) {
                st.openAt(c_ctx.mouse_x, c_ctx.mouse_y, 1);
            }
            if (c_ctx.contextMenu("test_ctx_menu", st, 180.0, items)) |idx| {
                out_sel.* = idx;
            }
        }
    }.build;

    // 1. Frame 1: Right-click inside target_r at (60, 40) -> opens contextMenu, both passes consume identical rects
    uic.right_mouse_pressed = true;
    uic.right_mouse_down = true;
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 400, 300), 60, 40, false, false, false);
    buildMenuScene(&uic, &menu_state, &menu_items, &selected_item);
    uic.endPass();
    try std.testing.expect(menu_state.open);

    uic.clip_damage = uic.dirty_rect;
    uic.beginPass(.paint, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 400, 300), 60, 40, false, false, false);
    buildMenuScene(&uic, &menu_state, &menu_items, &selected_item);
    uic.endPass();
    try std.testing.expectEqual(uic.last_input_rect_count, uic.last_paint_rect_count);

    // 2. Frame 2: Hover + click item 1 ("Copy" at y = 40 + 4 + 25 + 12 = 81) and release -> selects item 1 and closes menu deterministically
    uic.right_mouse_pressed = false;
    uic.right_mouse_down = false;
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 400, 300), 90, 81, false, false, true);
    buildMenuScene(&uic, &menu_state, &menu_items, &selected_item);
    uic.endPass();
    try std.testing.expect(!menu_state.open);
    try std.testing.expectEqual(@as(?usize, 1), selected_item);

    uic.clip_damage = uic.dirty_rect;
    uic.beginPass(.paint, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 400, 300), 90, 81, false, false, true);
    buildMenuScene(&uic, &menu_state, &menu_items, &selected_item);
    uic.endPass();
    try std.testing.expectEqual(uic.last_input_rect_count, uic.last_paint_rect_count);

    // 3. Built-in textFieldEx right-click menu: right-click opens deferred menu and clicking "Select All" selects all text
    var tf_buf: [64]u8 = undefined;
    var tf_len: usize = 9;
    @memcpy(tf_buf[0..9], "zig-menu!");
    uic.fallback_text_input_state = .{};

    uic.right_mouse_pressed = true;
    uic.right_mouse_down = true;
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 400, 300), 30, 14, false, false, false);
    const tf_r1 = uic.textFieldEx("##tf_ctx", &tf_buf, &tf_len, "", .{ .w = .pixels(200), .h = 28 });
    uic.endPass();
    try std.testing.expect(tf_r1.right_clicked);
    try std.testing.expect(uic.fallback_text_input_state.ctx_menu_open);

    uic.clip_damage = uic.dirty_rect;
    uic.beginPass(.paint, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 400, 300), 30, 14, false, false, false);
    _ = uic.textFieldEx("##tf_ctx", &tf_buf, &tf_len, "", .{ .w = .pixels(200), .h = 28 });
    uic.endPass();
    try std.testing.expectEqual(uic.last_input_rect_count, uic.last_paint_rect_count);
}

test "ui.Context: computeVirtualRange 2-phase layout determinism and exact scroll height" {
    const surface = try skia.Surface.initRasterN32Premul(320, 240);
    defer surface.deinit();
    const paint = try skia.Paint.init();
    defer paint.deinit();
    const font = try Font.init(null, 13.0);
    defer font.deinit();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var uic = Context{
        .arena = arena.allocator(),
        .canvas = surface.canvas(),
        .paint = paint,
        .font_title = font,
        .font_body = font,
        .font_mono = font,
    };
    defer uic.deinit();

    // Scroll down to y = 260 inside a 120px viewport with 100 items of height 24px (gap = 2px -> step = 26px)
    uic.fallback_scroll_state = .{ .scroll_y = 260.0, .content_height = 2598.0 };
    const buildVirtualList = struct {
        fn build(ctx: *Context, out_range: *VirtualRange) void {
            var sp = ctx.scrollPanel("virt_list", .{
                .w = .pixels(200),
                .h = .pixels(120),
                .padding = Padding.all(0),
                .gap = 2.0,
            });
            defer sp.end();
            const vr = ctx.computeVirtualRange(100, 26.0, 2);
            out_range.* = vr;
            if (vr.top_spacer_h > 0) ctx.spacer(vr.top_spacer_h);
            for (vr.first..vr.end) |idx| {
                var id_g = ctx.scopedId(idx);
                defer id_g.end();
                _ = ctx.btn("Row", .{ .h = 24.0 });
            }
            if (vr.bottom_spacer_h > 0) ctx.spacer(vr.bottom_spacer_h);
        }
    }.build;

    var vr_input: VirtualRange = .{ .first = 0, .end = 0, .top_spacer_h = 0, .bottom_spacer_h = 0 };
    var vr_paint: VirtualRange = .{ .first = 0, .end = 0, .top_spacer_h = 0, .bottom_spacer_h = 0 };

    uic.beginPass(.input, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 320, 240), 0, 0, false, false, false);
    buildVirtualList(&uic, &vr_input);
    uic.endPass();

    // Base first is 260 / 26 = 10; with overscan = 2 -> first = 8
    try std.testing.expectEqual(@as(usize, 8), vr_input.first);
    try std.testing.expect(vr_input.end > vr_input.first and vr_input.end < 25);
    try std.testing.expectApproxEqAbs(@as(f32, 8.0 * 26.0 - 2.0), vr_input.top_spacer_h, 0.01);
    // Total content height of 100 items of 24px with 99 gaps of 2px = 2400 + 198 = 2598px
    try std.testing.expectApproxEqAbs(@as(f32, 2598.0), uic.fallback_scroll_state.content_height, 0.1);

    uic.clip_damage = Rect.xywh(0, 0, 320, 240);
    uic.beginPass(.paint, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 320, 240), 0, 0, false, false, false);
    buildVirtualList(&uic, &vr_paint);
    uic.endPass();

    try std.testing.expectEqual(vr_input.first, vr_paint.first);
    try std.testing.expectEqual(vr_input.end, vr_paint.end);
    try std.testing.expectEqual(uic.last_input_rect_count, uic.last_paint_rect_count);
}

test "ui.Context: per-frame preview parser memoization (parseVcdCached, parsePdfCached, parseDiffCached)" {
    const surface = try skia.Surface.initRasterN32Premul(480, 320);
    defer surface.deinit();
    const paint = try skia.Paint.init();
    defer paint.deinit();
    const font = try Font.init(null, 13.0);
    defer font.deinit();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var uic = Context{
        .arena = arena.allocator(),
        .canvas = surface.canvas(),
        .paint = paint,
        .font_title = font,
        .font_body = font,
        .font_mono = font,
    };
    defer uic.deinit();

    const sample_vcd =
        \\$timescale 1ns $end
        \\$var wire 1 ! clk $end
        \\$enddefinitions $end
        \\#0
        \\0!
        \\#10
        \\1!
    ;
    const sample_pdf = "%PDF-1.4\n1 0 obj\n<< /Type /Page >>\nendobj\nBT (Hello Memoized PDF) Tj ET\n%%EOF";
    const sample_diff =
        \\--- a/foo.zig
        \\+++ b/foo.zig
        \\@@ -1,2 +1,2 @@
        \\-const a = 1;
        \\+const a = 2;
        \\ const b = 3;
    ;

    var vcd_state = WaveformViewState{};
    var pdf_state = PdfViewState{};
    var diff_state = DiffViewState{};

    // Input pass: parses and populates per-frame cache
    uic.beginPass(.input, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 480, 320), 0, 0, false, false, false);
    const vcd_in = uic.parseVcdCached(sample_vcd);
    const pdf_in = uic.parsePdfCached(sample_pdf, "sample.pdf");
    const diff_in = uic.parseDiffCached(sample_diff);
    uic.waveformViewerSource("vcd_test", 400.0, 80.0, sample_vcd, &vcd_state);
    _ = uic.pdfViewerSource("pdf_test", 400.0, 80.0, &pdf_state, .{ .raw_bytes = sample_pdf, .file_path = "sample.pdf" });
    _ = uic.diffViewer("diff_test", 400.0, 80.0, sample_diff, &diff_state, .{});
    uic.endPass();

    // Paint pass (same frame, arena not reset): returns identical cached struct pointers without re-parsing
    uic.clip_damage = Rect.xywh(0, 0, 480, 320);
    uic.beginPass(.paint, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 480, 320), 0, 0, false, false, false);
    const vcd_paint = uic.parseVcdCached(sample_vcd);
    const pdf_paint = uic.parsePdfCached(sample_pdf, "sample.pdf");
    const diff_paint = uic.parseDiffCached(sample_diff);
    uic.waveformViewerSource("vcd_test", 400.0, 80.0, sample_vcd, &vcd_state);
    _ = uic.pdfViewerSource("pdf_test", 400.0, 80.0, &pdf_state, .{ .raw_bytes = sample_pdf, .file_path = "sample.pdf" });
    _ = uic.diffViewer("diff_test", 400.0, 80.0, sample_diff, &diff_state, .{});
    uic.endPass();

    try std.testing.expectEqual(vcd_in, vcd_paint);
    try std.testing.expectEqual(pdf_in, pdf_paint);
    try std.testing.expectEqual(diff_in, diff_paint);
    try std.testing.expectEqual(uic.last_input_rect_count, uic.last_paint_rect_count);
}

test "ui.Context: floating dropdown overlay does not shift underlying widgets and blocks click-through" {
    const surface = try skia.Surface.initRasterN32Premul(240, 320);
    defer surface.deinit();
    const paint = try skia.Paint.init();
    defer paint.deinit();
    const font = try Font.init(null, 13.0);
    defer font.deinit();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var uic = Context{
        .arena = arena.allocator(),
        .canvas = surface.canvas(),
        .paint = paint,
        .font_title = font,
        .font_body = font,
        .font_mono = font,
    };
    defer uic.deinit();

    const Helper = struct {
        fn build(
            c_ui: *Context,
            open: bool,
            sibling_top_out: *f32,
            under_clicked_out: *bool,
            overlay_clicked_out: *bool,
        ) void {
            _ = c_ui.dropdownSelect("##cfg_dd", "Debug Target", 200.0, 24.0, open);
            if (open) {
                _ = c_ui.reserveDropdownOverlay(68.0);
            }
            sibling_top_out.* = c_ui.nextCursorY();
            under_clicked_out.* = c_ui.listItem(.{ .label = "Underlying Row##under" });
            if (open) {
                _ = c_ui.beginDropdownOverlay();
                defer c_ui.endDropdownOverlay();
                overlay_clicked_out.* = c_ui.listItem(.{ .label = "Overlay Option##ov_opt", .meta = "lldb", .selected = true });
            }
        }
    };

    var y_closed: f32 = 0;
    var y_open: f32 = 0;
    var under_clicked = false;
    var overlay_clicked = false;

    // 1. Closed dropdown pass
    uic.beginPass(.input, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 240, 320), 60, 42, false, false, false);
    Helper.build(&uic, false, &y_closed, &under_clicked, &overlay_clicked);
    uic.endPass();

    // 2. Open dropdown pass: press & release at (60, 42), which overlaps both Underlying Row and Overlay Option
    uic.beginPass(.input, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 240, 320), 60, 42, true, true, false);
    Helper.build(&uic, true, &y_open, &under_clicked, &overlay_clicked);
    uic.endPass();

    uic.beginPass(.input, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 240, 320), 60, 42, false, false, true);
    Helper.build(&uic, true, &y_open, &under_clicked, &overlay_clicked);
    uic.endPass();

    uic.clip_damage = Rect.xywh(0, 0, 240, 320);
    uic.beginPass(.paint, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 240, 320), 60, 42, false, false, false);
    var dummy_under = false;
    var dummy_ov = false;
    Helper.build(&uic, true, &y_open, &dummy_under, &dummy_ov);
    uic.endPass();

    // Opening the dropdown must not shift the underlying row vertically
    try std.testing.expectApproxEqAbs(y_closed, y_open, 0.01);
    // Clicking inside the open dropdown must trigger the overlay option, not the underlying row
    try std.testing.expect(!under_clicked);
    try std.testing.expect(overlay_clicked);
    try std.testing.expectEqual(uic.last_input_rect_count, uic.last_paint_rect_count);
}

test "ui.Context: focusAndSelectAll and focusScopedAndSelectAll highlight all text in textFieldEx across 2-phase frames" {
    const surface = try skia.Surface.initRasterN32Premul(320, 120);
    defer surface.deinit();
    const paint = try skia.Paint.init();
    defer paint.deinit();
    const font = try Font.init(null, 13.0);
    defer font.deinit();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var uic = Context{
        .arena = arena.allocator(),
        .canvas = surface.canvas(),
        .paint = paint,
        .font_title = font,
        .font_body = font,
        .font_mono = font,
    };
    defer uic.deinit();

    var find_buf: [64]u8 = undefined;
    var find_len: usize = 11;
    @memcpy(find_buf[0..11], "search_term");
    uic.fallback_text_input_state = .{ .cursor = 3, .anchor = 3, .last_len = 11, .initialized = true };

    // 1. Trigger focusScopedAndSelectAll (simulating Cmd+F focusing the Find Bar input)
    uic.focusScopedAndSelectAll(&.{"editor_pane"}, "##find_bar_input");

    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 320, 120), 0, 0, false, false, false);
    {
        var sc = uic.scopedId("editor_pane");
        defer sc.end();
        const tf = uic.textFieldEx("##find_bar_input", &find_buf, &find_len, "Find...", .{ .w = .pixels(220), .h = 28 });
        try std.testing.expect(tf.focused);
    }
    uic.endPass();

    try std.testing.expectEqual(@as(u32, 0), uic.fallback_text_input_state.anchor);
    try std.testing.expectEqual(@as(u32, 11), uic.fallback_text_input_state.cursor);
    try std.testing.expect(uic.fallback_text_input_state.hasSelection());

    uic.clip_damage = Rect.xywh(0, 0, 320, 120);
    uic.beginPass(.paint, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 320, 120), 0, 0, false, false, false);
    {
        var sc = uic.scopedId("editor_pane");
        defer sc.end();
        _ = uic.textFieldEx("##find_bar_input", &find_buf, &find_len, "Find...", .{ .w = .pixels(220), .h = 28 });
    }
    uic.endPass();
    try std.testing.expectEqual(uic.last_input_rect_count, uic.last_paint_rect_count);

    // 2. Typing immediately replaces the entire highlighted search query
    uic.text_input = "new";
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 320, 120), 0, 0, false, false, false);
    {
        var sc = uic.scopedId("editor_pane");
        defer sc.end();
        const tf = uic.textFieldEx("##find_bar_input", &find_buf, &find_len, "Find...", .{ .w = .pixels(220), .h = 28 });
        try std.testing.expect(tf.changed);
    }
    uic.endPass();
    try std.testing.expectEqualStrings("new", find_buf[0..find_len]);
}

test "ui.Context: textAreaInlineEx word-wrapping, vertical auto-expansion, Shift+Enter newline, and Enter submit" {
    const surface = try skia.Surface.initRasterN32Premul(320, 240);
    defer surface.deinit();
    const paint = try skia.Paint.init();
    defer paint.deinit();
    const font = try Font.init(null, 13.0);
    defer font.deinit();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var uic = Context{
        .arena = arena.allocator(),
        .canvas = surface.canvas(),
        .paint = paint,
        .font_title = font,
        .font_body = font,
        .font_mono = font,
    };
    defer uic.deinit();

    var prompt = platform.InlineString(512){};
    const opts = TextAreaOptions{
        .w = .pixels(140.0),
        .min_lines = 1,
        .max_lines = 6,
        .line_h = 19.0,
        .pad_x = 4.0,
        .pad_y = 4.5,
        .borderless = true,
        .use_body_font = true,
        .submit_on_enter = true,
    };

    // 1. Empty prompt: 1 line height (19.0 + 9.0 = 28.0)
    const h_empty = uic.measureTextAreaHeight(prompt.slice(), 140.0, opts);
    try std.testing.expectApproxEqAbs(@as(f32, 28.0), h_empty, 0.01);

    // 2. Multi-word text that wraps across multiple lines grows height automatically
    prompt.set("This is a long sentence that wraps by word across multiple visual lines in the composer");
    const h_wrapped = uic.measureTextAreaHeight(prompt.slice(), 140.0, opts);
    try std.testing.expect(h_wrapped >= 28.0 + 19.0 * 2.0);

    // 3. Shift+Enter inserts a newline and grows height further; Enter submits without inserting a newline
    uic.focused_id = id("##test_expanding_prompt");
    const shift_enter = [_]platform.KeyEvent{.{ .key = .enter, .shift = true }};
    uic.key_events = &shift_enter;

    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 320, 240), 0, 0, false, false, false);
    const res_nl = uic.textAreaInlineEx("##test_expanding_prompt", &prompt, "Ask anything...", opts);
    const y_after_input = uic.nextCursorY();
    uic.endPass();

    try std.testing.expect(res_nl.changed);
    try std.testing.expect(!res_nl.submitted);
    try std.testing.expect(std.mem.endsWith(u8, prompt.slice(), "\n"));

    uic.clip_damage = Rect.xywh(0, 0, 320, 240);
    uic.beginPass(.paint, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 320, 240), 0, 0, false, false, false);
    _ = uic.textAreaInlineEx("##test_expanding_prompt", &prompt, "Ask anything...", opts);
    const y_after_paint = uic.nextCursorY();
    uic.endPass();

    try std.testing.expectApproxEqAbs(y_after_input, y_after_paint, 0.01);
    try std.testing.expectEqual(uic.last_input_rect_count, uic.last_paint_rect_count);

    // Plain Enter submits
    const plain_enter = [_]platform.KeyEvent{.{ .key = .enter }};
    uic.key_events = &plain_enter;
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 320, 240), 0, 0, false, false, false);
    const res_sub = uic.textAreaInlineEx("##test_expanding_prompt", &prompt, "Ask anything...", opts);
    uic.endPass();
    try std.testing.expect(res_sub.submitted);
}

test "ui.Context: latch and useFrameCache preserve two-phase determinism across Pass.input and Pass.paint" {
    const surface = try skia.Surface.initRasterN32Premul(320, 240);
    defer surface.deinit();
    const paint = try skia.Paint.init();
    defer paint.deinit();
    const font = try Font.init(null, 13.0);
    defer font.deinit();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var uic = Context{
        .arena = arena.allocator(),
        .canvas = surface.canvas(),
        .paint = paint,
        .font_title = font,
        .font_body = font,
        .font_mono = font,
    };
    defer uic.deinit();

    const ComputedStats = struct {
        total: usize,
        calls: usize,
    };
    const ComputeCtx = struct {
        base: usize,
        call_counter: *usize,
        fn build(_: std.mem.Allocator, cctx: @This()) ComputedStats {
            cctx.call_counter.* += 1;
            return .{
                .total = cctx.base * 10,
                .calls = cctx.call_counter.*,
            };
        }
    };

    var show_panel: bool = true;
    var active_tab: u8 = 2;
    var compute_calls: usize = 0;

    // Pass.input: latch values BEFORE mid-frame mutation, and compute cached stats once
    uic.beginPass(.input, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 320, 240), 0, 0, false, false, false);
    const latched_show_in = uic.latch(bool, show_panel);
    const latched_tab_in = uic.latch(u8, active_tab);
    if (latched_show_in) {
        uic.label("Panel Visible", null);
    }
    const stats_in_1 = uic.useFrameCache(ComputedStats, "test_stats", ComputeCtx{
        .base = 7,
        .call_counter = &compute_calls,
    }, ComputeCtx.build);
    const stats_in_2 = uic.useFrameCache(ComputedStats, "test_stats", ComputeCtx{
        .base = 7,
        .call_counter = &compute_calls,
    }, ComputeCtx.build);
    // Simulate mid-frame state mutation during Pass.input
    show_panel = false;
    active_tab = 5;
    uic.endPass();

    try std.testing.expectEqual(true, latched_show_in);
    try std.testing.expectEqual(@as(u8, 2), latched_tab_in);
    try std.testing.expectEqual(@as(usize, 1), compute_calls);
    try std.testing.expectEqual(stats_in_1, stats_in_2);
    try std.testing.expectEqual(@as(usize, 70), stats_in_1.total);

    // Pass.paint: latch replays exact Pass.input values despite mid-frame mutation, and useFrameCache hits without recomputing
    uic.clip_damage = Rect.xywh(0, 0, 320, 240);
    uic.beginPass(.paint, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 320, 240), 0, 0, false, false, false);
    const latched_show_paint = uic.latch(bool, show_panel);
    const latched_tab_paint = uic.latch(u8, active_tab);
    if (latched_show_paint) {
        uic.label("Panel Visible", null);
    }
    const stats_paint = uic.useFrameCache(ComputedStats, "test_stats", ComputeCtx{
        .base = 99,
        .call_counter = &compute_calls,
    }, ComputeCtx.build);
    uic.endPass();

    try std.testing.expectEqual(true, latched_show_paint);
    try std.testing.expectEqual(@as(u8, 2), latched_tab_paint);
    try std.testing.expectEqual(@as(usize, 1), compute_calls);
    try std.testing.expectEqual(stats_in_1, stats_paint);
    try std.testing.expectEqual(uic.last_input_rect_count, uic.last_paint_rect_count);

    // Verify 4-slot parseVcdCached and parsePdfCached do not thrash when 2 panes show different sources
    const vcd_a = "$timescale 1ns $end\n$var wire 1 ! a $end\n$enddefinitions $end\n#0\n0!\n";
    const vcd_b = "$timescale 1ns $end\n$var wire 1 @ b $end\n$enddefinitions $end\n#0\n1@\n";
    const pdf_a = "%PDF-1.4\n1 0 obj\n<< /Type /Page >>\nendobj\nBT (Doc A) Tj ET\n%%EOF";
    const pdf_b = "%PDF-1.4\n1 0 obj\n<< /Type /Page >>\nendobj\nBT (Doc B) Tj ET\n%%EOF";

    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 320, 240), 0, 0, false, false, false);
    const va_in = uic.parseVcdCached(vcd_a);
    const vb_in = uic.parseVcdCached(vcd_b);
    const pa_in = uic.parsePdfCached(pdf_a, "a.pdf");
    const pb_in = uic.parsePdfCached(pdf_b, "b.pdf");
    uic.endPass();

    uic.beginPass(.paint, arena.allocator(), surface.canvas(), Rect.xywh(0, 0, 320, 240), 0, 0, false, false, false);
    const va_paint = uic.parseVcdCached(vcd_a);
    const vb_paint = uic.parseVcdCached(vcd_b);
    const pa_paint = uic.parsePdfCached(pdf_a, "a.pdf");
    const pb_paint = uic.parsePdfCached(pdf_b, "b.pdf");
    uic.endPass();

    try std.testing.expect(va_in != vb_in);
    try std.testing.expectEqual(va_in, va_paint);
    try std.testing.expectEqual(vb_in, vb_paint);
    try std.testing.expect(pa_in != pb_in);
    try std.testing.expectEqual(pa_in, pa_paint);
    try std.testing.expectEqual(pb_in, pb_paint);
}

