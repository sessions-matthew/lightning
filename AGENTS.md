# Agent & Contributor Architecture Guide (`AGENTS.md`)

## Zig 0.17.0 Language & Standard Library Reference

- **Local Markdown Docs**: [`docs/README.md`](docs/README.md)
  - **Language Reference (Single File)**: [`docs/langref.md`](docs/langref.md)
  - **Language Reference (By Section)**: [`docs/langref/`](docs/langref/) (e.g., [`39-builtin-functions.md`](docs/langref/39-builtin-functions.md), [`35-comptime.md`](docs/langref/35-comptime.md))
  - **Standard Library (`std`) Reference**: [`docs/std/README.md`](docs/std/README.md) (e.g., [`Io.md`](docs/std/Io.md), [`Io.Dir.md`](docs/std/Io.Dir.md), [`Io.Reader.md`](docs/std/Io.Reader.md), [`Io.Writer.md`](docs/std/Io.Writer.md), [`mem.md`](docs/std/mem.md), [`process.md`](docs/std/process.md))
- **Interactive Local Server**: Run `zig std` to launch Zig's built-in local Autodoc server (`/opt/homebrew/Cellar/zig/0.17.0/lib/zig/docs`).
- **Online Reference**: https://ziglang.org/documentation/0.17.0/

---

## 1. Layered Module Architecture & Strict Dependency DAG

The codebase is organized into four strictly ordered layers configured in [`build.zig`](build.zig). **Never introduce upward or circular imports.**

```
src/skia/        (Layer 0: Zero-overhead Skia C-ABI bindings & RAII wrappers)
   ▲
src/platform/    (Layer 1: OS window host, C-ABI plugin boundary, StateStore, profiler)
   ▲
src/ui/          (Layer 2: 2-phase immediate/retained UI toolkit, layout, widgets, dock)
   ▲
src/app/         (Layer 3: Editor state, services/clients, & declarative workbench views)
```

| Layer | Directory | Responsibility | Rule |
| :--- | :--- | :--- | :--- |
| **0. Graphics** | `src/skia/` | Direct `extern "c"` Skia bindings (`zero @cImport`) and thin value/RAII types (`Surface`, `Canvas`, `Paint`, `Font`, `TextBlob`). | No UI, layout, or app concepts. |
| **1. Platform** | `src/platform/` | Native Cocoa/Metal host (`skia-window`), `.dylib` hot-reloader, `PlatformContext` C-ABI contract, and `StateStore` (`useState`, `InlineString`). | Must remain agnostic of specific widgets or app state. |
| **2. UI Framework** | `src/ui/` | Two-phase (`Pass.input` / `Pass.paint`) layout engine, `TextCache`, reusable widgets, `markdown`, `code_editor`, `vterm`, `dock`, and `exportPlugin`. | **If a visual primitive, layout pattern, or data structure could be used by >1 view or example, it belongs in `src/ui/`, not `src/app/`.** |
| **3. Application** | `src/app/` | Editor domain state (`state.zig`), external protocol clients (`agy_client.zig`, `supercomplete.zig`), and thin declarative view functions (`src/app/views/`). | Views compose `ui.Context` primitives and dispatch intents to `EditorState`; they should **not** draw raw Skia shapes unless rendering a domain-specific visualization. |

---

## 2. Core Design Philosophies

### 2.1 Two-Phase Hybrid Immediate/Retained Execution (`Pass.input` → `Pass.paint`)
Every frame runs through [`ui.runTwoPhaseFrame`](src/ui/app_runner.zig):
1. **`Pass.input` (CPU-only)**: Measures layout, resolves widget bounding boxes, processes mouse/scroll/keyboard events, mutates state, and accumulates disjoint dirty regions in `uic.damage_list` (`DamageList(8)`) as well as the bounding `uic.dirty_rect`. **Zero GPU or Skia draw calls may happen during `Pass.input`.**
2. **Early-Exit Idle Optimization**: If `dirty_rect == null` after `Pass.input` and `force_full_redraw == false`, the host skips the GPU pass completely (`0%` idle CPU/GPU usage).
3. **`Pass.paint` (Scissor-Clipped Multi-Rect GPU Replay)**: Replays the exact same UI tree while clearing and painting only rects that intersect `uic.damage_list`. Every custom widget draw block **must** guard drawing with `if (uic.shouldPaint(rect)) { ... }`.
4. **Layout Determinism Invariant**: A widget or view function **must consume the exact same layout rects (`nextRect`, `box`, `row`, `column`, `scrollPanel`) in both `.input` and `.paint` passes**. Never conditionally add/skip layout boxes based on `uic.pass`.

### 2.2 Hot-Reload Safety & Value-Oriented State (`dlclose`-Safe Memory)
The host executable (`skia-window`) dynamically reloads `libeditor_app.dylib` on the fly:
- **No Dangling `.rodata` Pointers Across Reloads**: Never store slices (`[]const u8`) pointing to string literals or plugin static memory inside `StateStore` (`uic.useState`) or long-lived host heap structures—when the old `.dylib` is `dlclose`d, its `.rodata` segment is unmapped. Always use value-copied buffers such as [`platform.InlineString(capacity)`](src/platform/state_store.zig).
- **Serializable Document State**: Keep user preferences and layout trees (`EditorDocument`, `SplitTree`, `PaneTabGroup`) in plain, `std.json`-serializable value structs with default field values so `saveSnapshotJson` / `loadSnapshotJson` can restore state seamlessly across schema changes.
- **Single-Line Plugin Entrypoint**: Use `comptime { ui.exportPlugin(StateType, "doc", STATE_VERSION, buildFn); }` rather than duplicating C-ABI `export fn app_*` hooks.

### 2.3 Hierarchical Scoped IDs & State Hooks
- **Scoped Widget IDs**: Widget identity is computed by chaining FNV-1a hashes down `uic.id_stack` (`pushScope` / `pushId` / `resolveIdAndLabel`).
- **Loop Disambiguation**: Inside loops, always push an index or pointer disambiguator (`var id_guard = uic.scopedId(idx); defer id_guard.end();`) or use `"Label##unique_suffix"` syntax instead of formatting temporary ID strings.
- **Cross-Scope Focus**: When focusing a widget that lives inside nested `scopedState` / `scopedId` blocks from outside that scope, always use [`uic.focusScoped(&.{ "scope_a", "scope_b" }, "##widget_id")`](src/ui/root.zig) or [`ui.scopedIdPath(&.{ ... }, "##widget_id")`](src/ui/root.zig)—never hash a flat `"scope:##widget_id"` literal with `ui.id(...)`.

### 2.4 Zero-Allocation Text & Per-Frame Arena Discipline
- **Cached `SkTextBlob`s**: Never call raw Skia text drawing in widgets. Always use `uic.measureTextCached(font, text)` and `uic.drawTextCached(font, text, x, y)` so glyph runs hit the 4096-entry (1024 sets × 4 ways) LRU set-associative [`TextCache`](src/ui/text_cache.zig).
- **Bounded Fixed Buffers & Frame Arena**: Prefer comptime-bounded value structs (`CodeEditorBuffer(N)`, `InlineString(N)`, `SplitTree(N)`, `PaneTabGroup(N)`) for persistent state, and `uic.arena` (`uic.fmt(...)`) for transient per-frame formatting that is reset at the start of every frame in `O(1)`.

### 2.5 Unidirectional Data Flow in `src/app/`
- **Views Are Thin & Declarative**: Files in `src/app/views/` should read `EditorState`, declare containers (`uic.row`, `uic.column`, `uic.scrollPanel`, `uic.overlayBox`) with declarative styling (`.border_edges`, `.preset`, `.bg_color` from `uic.theme`, `Size.fitContent(min, max)`), and invoke semantic methods on `EditorState` or [`commands.execute`](src/app/commands.zig) when user interactions occur.
- **Declarative Command & Shortcut Registry**: Register all global keyboard shortcuts and Command Palette items in [`src/app/commands.zig`](src/app/commands.zig) (`COMMANDS`) rather than scattering ad-hoc shortcut checks across views.
- **Defer Structural Tree Mutations**: When rendering recursive structures like `uic.splitTree`, never mutate the tree's node topology mid-traversal; record a `PendingPaneOp` and apply it after `uic.splitTree` returns.
- **Non-Blocking External I/O**: External processes and sockets (`agy_client.zig`, `supercomplete.zig`, `git_client.zig`, `vterm.zig`) must use non-blocking descriptors (`O_NONBLOCK`) polled during `Pass.input`, setting `pctx.needs_continuous_redraw = true` only while an async turn or stream is actively in flight.

---

## 3. Codebase Structure & Where to Put New Code

- **`src/platform/plugin_abi.zig` & `src/platform/plugin_sdk.zig`**: Versioned C-ABI vtable contract (`EditorPluginV1`, `EditorHostApiV1`, `PluginUiApiV1`) and ergonomic Zig authoring SDK (`sdk.exportEditorPlugin`, `sdk.PluginContext`) for standalone ~69 KB `.dylib` editor plugins with zero Skia linkage.
- **`src/ui/layout.zig`**: Sizing (`Size`, including `.fitContent(min, max)`), `Padding`, `BorderEdges`, `BoxStyle`, `ContainerPreset`, `ContainerConfig`, `ScrollState`.
- **`src/ui/root.zig`**: `ui.Context` core stack, `DamageList(8)` multi-rect two-phase damage tracking, `clickedOutside`, and standard widgets (`btn`, `chip`, `iconButton`, `menuItem`, `circularActionButton`, `banner`, `listItemEx`, `treeFolderNode`, `textFieldEx`, `textFieldInline`, `textAreaInline`, `splitterSash`, `resizableSash`).
- **`src/ui/dock.zig`**: `SplitNode`, `SplitTree(max_panes)`, `PaneTabGroup(max_tabs)`, `TabDragState`, and 5-zone dock drop-target detection.
- **`src/ui/code_editor.zig`**: `CodeEditorBuffer(capacity)` with incremental line-start index ($O(\log L)$ `offsetToLineCol`, $O(1)$ `lineRangeByIndex`) and coalesced delta undo/redo ring, multi-language tokenizer, minimap, and inline ghost-text rendering.
- **`src/ui/markdown.zig`**: Zero-allocation Markdown block/inline parser, callout alerts, syntax-highlighted code blocks, tables, and `renderBubble`.
- **`src/ui/vterm.zig`**: PTY-backed VT100/xterm virtual terminal emulator with 256-color/TrueColor SGR support.
- **`src/app/state.zig`**: Central `EditorState` and serializable `EditorDocument` (workspace file index, buffers, git status, command actions). Keep `state.zig` focused on state transitions; extract standalone subsystems and protocol clients into sibling modules (`src/app/commands.zig`, `src/app/plugin_manager.zig`, `src/app/agy_client.zig`, `src/app/supercomplete.zig`, `src/app/git_client.zig`, `src/app/analysis.zig`, `src/app/workspace_defaults.zig`).
- **`src/app/views/`**: Stateless view builders (`titlebar.zig`, `activity_bar.zig`, `explorer.zig`, `editor_pane.zig`, `agent_panel.zig`, `status_bar.zig`).
- **`plugins/`**: Standalone native Zig `.dylib` editor extensions (e.g., `plugins/doc_metrics.zig` $\to$ `zig-out/plugins/libdoc_metrics.dylib`), dynamically discovered and hot-reloaded by `PluginManager`.

---

## 4. Verification & Development Workflow

Always verify changes with the following commands before concluding a task:

```bash
# 1. Run all unit tests (platform StateStore, PluginABI/SDK, UI layout/widgets, SplitTree/PaneTabGroup, Markdown, CodeEditor, Commands, Git/Agy/Supercomplete)
zig build test

# 2. Run headless subsystem microbenchmark suite (TextCache, DamageList, CodeEditorBuffer, UI Layout, GitStatusPoller)
zig build microbench

# 3. Compile native Zig .dylib editor extensions into zig-out/plugins/ (<100ms, ~69 KB)
zig build plugins

# 4. Compile only libeditor_app.dylib for live hot-reload (<200ms)
zig build app

# 5. Compile all standalone feature showcase plugins (studio, scrollable, markdown, code_editor, raster_cli)
zig build examples

# 6. Full workspace build (host executable + main editor plugin + extension plugins)
zig build
```

When adding a new widget, layout option, or state container to `src/ui/` or `src/platform/`, **always add a unit test** in the corresponding module (`src/ui/root.zig`, `src/ui/dock.zig`, `src/ui/code_editor.zig`, or `src/platform/state_store.zig`) that exercises both `.input` and `.paint` passes.
