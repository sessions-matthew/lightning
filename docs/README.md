# Zig 0.17.0 Documentation

Offline Markdown documentation extracted from `/opt/homebrew/Cellar/zig/0.17.0/doc/langref.html`, `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/docs`, and `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std`.

> [!TIP]
> **Interactive Standard Library Browser**: You can also run `zig std` in the terminal to launch Zig's built-in local Autodoc web server (`/opt/homebrew/Cellar/zig/0.17.0/lib/zig/docs`).

---

## 1. Language Reference

- **[Complete Language Reference (Single File)](langref.md)** (`docs/langref.md`)

### Language Reference by Topic (`docs/langref/`)

| # | Topic | File |
| :--- | :--- | :--- |
| 01 | Introduction | [`langref/01-introduction.md`](langref/01-introduction.md) |
| 02 | Zig Standard Library | [`langref/02-zig-standard-library.md`](langref/02-zig-standard-library.md) |
| 03 | Hello World | [`langref/03-hello-world.md`](langref/03-hello-world.md) |
| 04 | Comments | [`langref/04-comments.md`](langref/04-comments.md) |
| 05 | Namespace | [`langref/05-namespace.md`](langref/05-namespace.md) |
| 06 | Identifiers | [`langref/06-identifiers.md`](langref/06-identifiers.md) |
| 07 | Values | [`langref/07-values.md`](langref/07-values.md) |
| 08 | Zig Test | [`langref/08-zig-test.md`](langref/08-zig-test.md) |
| 09 | Variables | [`langref/09-variables.md`](langref/09-variables.md) |
| 10 | Integers | [`langref/10-integers.md`](langref/10-integers.md) |
| 11 | Floats | [`langref/11-floats.md`](langref/11-floats.md) |
| 12 | Operators | [`langref/12-operators.md`](langref/12-operators.md) |
| 13 | Arrays | [`langref/13-arrays.md`](langref/13-arrays.md) |
| 14 | Vectors | [`langref/14-vectors.md`](langref/14-vectors.md) |
| 15 | Pointers | [`langref/15-pointers.md`](langref/15-pointers.md) |
| 16 | Slices | [`langref/16-slices.md`](langref/16-slices.md) |
| 17 | `struct` | [`langref/17-struct.md`](langref/17-struct.md) |
| 18 | `enum` | [`langref/18-enum.md`](langref/18-enum.md) |
| 19 | `union` | [`langref/19-union.md`](langref/19-union.md) |
| 20 | `opaque` | [`langref/20-opaque.md`](langref/20-opaque.md) |
| 21 | Blocks | [`langref/21-blocks.md`](langref/21-blocks.md) |
| 22 | `switch` | [`langref/22-switch.md`](langref/22-switch.md) |
| 23 | `while` | [`langref/23-while.md`](langref/23-while.md) |
| 24 | `for` | [`langref/24-for.md`](langref/24-for.md) |
| 25 | `if` | [`langref/25-if.md`](langref/25-if.md) |
| 26 | `defer` | [`langref/26-defer.md`](langref/26-defer.md) |
| 27 | `unreachable` | [`langref/27-unreachable.md`](langref/27-unreachable.md) |
| 28 | `noreturn` | [`langref/28-noreturn.md`](langref/28-noreturn.md) |
| 29 | Functions | [`langref/29-functions.md`](langref/29-functions.md) |
| 30 | Errors | [`langref/30-errors.md`](langref/30-errors.md) |
| 31 | Optionals | [`langref/31-optionals.md`](langref/31-optionals.md) |
| 32 | Casting | [`langref/32-casting.md`](langref/32-casting.md) |
| 33 | Zero Bit Types | [`langref/33-zero-bit-types.md`](langref/33-zero-bit-types.md) |
| 34 | Result Location Semantics | [`langref/34-result-location-semantics.md`](langref/34-result-location-semantics.md) |
| 35 | `comptime` | [`langref/35-comptime.md`](langref/35-comptime.md) |
| 36 | Assembly | [`langref/36-assembly.md`](langref/36-assembly.md) |
| 37 | Atomics | [`langref/37-atomics.md`](langref/37-atomics.md) |
| 38 | Async Functions | [`langref/38-async-functions.md`](langref/38-async-functions.md) |
| 39 | Builtin Functions (`@...`) | [`langref/39-builtin-functions.md`](langref/39-builtin-functions.md) |
| 40 | Optimization Mode | [`langref/40-optimization-mode.md`](langref/40-optimization-mode.md) |
| 41 | Single Threaded Builds | [`langref/41-single-threaded-builds.md`](langref/41-single-threaded-builds.md) |
| 42 | Illegal Behavior | [`langref/42-illegal-behavior.md`](langref/42-illegal-behavior.md) |
| 43 | Memory | [`langref/43-memory.md`](langref/43-memory.md) |
| 44 | Compile Variables | [`langref/44-compile-variables.md`](langref/44-compile-variables.md) |
| 45 | Compilation Model | [`langref/45-compilation-model.md`](langref/45-compilation-model.md) |
| 46 | Zig Build System | [`langref/46-zig-build-system.md`](langref/46-zig-build-system.md) |
| 47 | C Interop | [`langref/47-c.md`](langref/47-c.md) |
| 48 | WebAssembly | [`langref/48-webassembly.md`](langref/48-webassembly.md) |
| 49 | Targets | [`langref/49-targets.md`](langref/49-targets.md) |
| 50 | Style Guide | [`langref/50-style-guide.md`](langref/50-style-guide.md) |
| 51 | Source Encoding | [`langref/51-source-encoding.md`](langref/51-source-encoding.md) |
| 52 | Keyword Reference | [`langref/52-keyword-reference.md`](langref/52-keyword-reference.md) |
| 53 | Appendix (Grammar & Zen) | [`langref/53-appendix.md`](langref/53-appendix.md) |

---

## 2. Standard Library Reference (`docs/std/`)

Generated using Zig 0.17.0's Autodoc AST walker (`/opt/homebrew/Cellar/zig/0.17.0/lib/zig/docs/wasm/Walk.zig` + `Decl.zig`):

- **[Standard Library Index (`docs/std/README.md`)](std/README.md)**
- **Core 0.17.0 Modules**:
  - [`std`](std/std.md) — Root Standard Library declarations & `std.Options`
  - [`std.Io`](std/Io.md) — Cross-platform I/O & concurrency interface
  - [`std.Io.Dir`](std/Io.Dir.md) — Directory operations (`openFile`, `readFileAlloc`, `iterate`, `walk`)
  - [`std.Io.File`](std/Io.File.md) — File operations (`stdout`, `stderr`, `reader`, `writer`)
  - [`std.Io.Reader`](std/Io.Reader.md) — Buffered/streaming reader interface
  - [`std.Io.Writer`](std/Io.Writer.md) — Buffered/allocating/fixed writer interface
  - [`std.Io.net`](std/Io.net.md) — Networking (`IpAddress`, `Stream`, `Server`)
  - [`std.process`](std/process.md) — `Init`, `Args`, `Child`, environment, and process control
  - [`std.mem`](std/mem.md) — Memory manipulation, `Allocator`, slices, alignment, and tokenizers
  - [`std.fmt`](std/fmt.md) — Formatting and parsing
  - [`std.heap`](std/heap.md) — Allocators (`ArenaAllocator`, `DebugAllocator`, `smp_allocator`, `page_allocator`)
  - [`std.array_list`](std/array_list.md) / [`std.hash_map`](std/hash_map.md) / [`std.array_hash_map`](std/array_hash_map.md) — Containers
  - [`std.json`](std/json.md) — JSON parsing, stringifying, and `Scanner`
  - [`std.posix`](std/posix.md) — POSIX system call wrappers
  - [`std.Thread`](std/Thread.md) — Kernel threads, `Mutex`, `Condition`, `RwLock`, `Pool`
  - [`std.Build`](std/Build.md) / [`std.Build.Module`](std/Build.Module.md) / [`std.Build.Step`](std/Build.Step.md) — Build system API
  - [`std.zig`](std/zig.md) / [`std.zig.Ast`](std/zig.Ast.md) — Zig tokenizer, parser, and AST
  - [`std.testing`](std/testing.md) / [`std.debug`](std/debug.md) — Testing assertions and debugging
