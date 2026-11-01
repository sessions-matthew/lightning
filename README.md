# Lightning Editor

**Lightning** is a fast, native code editor written in **Zig 0.17.0** and rendered with **Skia** over **Metal** (macOS), **Win32** (Windows), and **Wayland/X11** (Linux).

Its interface combines the workbench layout of **VS Code** (activity bar, file explorer, docked split panes, Command Palette) with the buffer-centric workflow of **Emacs** (per-window interactive mode lines, `*scratch*` buffers, and side-by-side terminal/agent/preview buffers).

---

## Core Features

- **0% Idle CPU/GPU Rendering**: Two-phase UI execution (`Pass.input` → `Pass.paint`) tracks dirty regions (`DamageList(8)`) and skips GPU drawing completely when idle.
- **Live Hot-Reloading**: The window host (`lightning`) reloads `libeditor_app` and extension plugins on the fly in **<200 ms** while preserving session state.
- **Built-in Buffers & Tools**:
  - Multi-language code editor with syntax highlighting, minimap, and inline ghost-text completions (**Supercomplete**).
  - Integrated PTY/ConPTY terminal emulator (**VTerm**), **Antigravity (`agy`)** AI agent panel, and **Git** diff viewer.
  - Live **Markdown**, **PDF**, and digital **VCD Waveform** previews.
- **Native Plugin SDK (`plugins/`)**: ~69 KB standalone `.dylib`/`.dll`/`.so` extensions with hot-reload support, including work-in-progress LSP integrations (`zls`, `rust-analyzer`, `clangd`, `gopls`, `pyright`, `tsserver`, `jdtls`, `verible`, `vhdl_ls`), **LLDB** debugging, **RTL simulation**, **Git Lens**, and **Hex inspection**.

---

## Quick Start

Requires **Zig `0.17.0`** (prebuilt SkiaSharp libraries are vendored in `vendor/skiasharp/lib/`).

```bash
# Build and run Lightning
zig build run

# Hot-reload the editor or plugins while running
zig build app
zig build plugins

# Run unit tests and microbenchmarks
zig build test
zig build microbench

# Package / cross-compile distributions
zig build package   # macOS Lightning.app + .dmg
zig build windows   # Windows x86_64 -> zig-out/windows/
zig build linux     # Linux x86_64   -> zig-out/linux/
```

---

## Keyboard Shortcuts

| Shortcut | Action |
| :--- | :--- |
| `Shift + Cmd + P` | Command Palette (`>`) |
| `Cmd + P` | Quick Open File (`@` for symbols, `:` for line) |
| `Cmd + O` / `Cmd + S` | Open Folder / Save File |
| `Cmd + F` / `Shift + Cmd + F` | Find in File / Find in Workspace |
| `Cmd + \` / `Shift + Cmd + \` | Split Editor Right / Down |
| `Cmd + W` | Close Active Tab |
| `Cmd + B` / `Cmd + J` | Toggle Sidebar / Toggle Bottom Panel |
| `Shift + Cmd + T` | New Terminal Buffer (`VTerm`) |
| `Shift + Cmd + J` | Toggle Antigravity Agent Panel |
| `Cmd + /` / `Cmd + D` | Toggle Comment / Duplicate Line |

---

## Architecture

```text
src/skia/      (Layer 0: Skia C-ABI bindings & RAII wrappers)
src/platform/  (Layer 1: Native window host, StateStore, hot-reloader, Plugin SDK)
src/ui/        (Layer 2: Two-phase UI toolkit, dock, code editor, vterm, markdown)
src/app/       (Layer 3: EditorState, commands, clients, and workbench views)
plugins/       (Standalone native .dylib/.dll/.so editor extensions)
examples/      (Standalone UI showcase targets: `zig build examples`)
```

See [`AGENTS.md`](AGENTS.md) for architecture details and [`docs/README.md`](docs/README.md) for local Zig 0.17.0 documentation.

## Acknowledgments

Built with **Gemini** in **Google Antigravity**.

## License

[MIT](LICENSE)

