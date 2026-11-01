# `std.Build.Module`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/Build/Module.zig`  
> [← Back to Standard Library Index](README.md)

## Fields

- `owner: *std.Build`
  The one responsible for creating this module.
- `root_source_file: ?LazyPath`
  
- `import_table: std.array_hash_map.String(*Module)`
  The modules that are mapped into this module's import table.
  Use `addImport` rather than modifying this field directly in order to
  maintain step dependency edges.
- `resolved_target: ?std.Build.ResolvedTarget = null`
  
- `optimize: ?std.builtin.Optimize = null`
  
- `dwarf_format: ?std.dwarf.Format`
  
- `c_macros: ArrayList([]const u8)`
  
- `include_dirs: ArrayList(IncludeDir)`
  
- `lib_paths: ArrayList(LazyPath)`
  
- `rpaths: ArrayList(RPath)`
  
- `frameworks: std.array_hash_map.String(LinkFrameworkOptions)`
  
- `link_objects: ArrayList(LinkObject)`
  
- `strip: ?bool`
  
- `unwind_tables: ?std.builtin.UnwindTables`
  
- `single_threaded: ?bool`
  
- `stack_protector: ?bool`
  
- `stack_check: ?bool`
  
- `sanitize_c: ?std.zig.SanitizeC`
  
- `sanitize_thread: ?bool`
  
- `fuzz: ?bool`
  
- `code_model: std.builtin.CodeModel`
  
- `valgrind: ?bool`
  
- `pic: ?bool`
  
- `red_zone: ?bool`
  
- `omit_frame_pointer: ?bool`
  
- `error_tracing: ?bool`
  
- `link_libc: ?bool`
  
- `link_libcpp: ?bool`
  
- `no_builtin: ?bool`
  
- `patchable_function_entry: u16`
  
- `export_symbol_names: []const []const u8 = &.{}`
  Symbols to be exported when compiling to WebAssembly.
- `cached_graph: Graph = .{ .modules = &.{}, .names = &.{} }`
  Caches the result of `getGraph` when called multiple times.
  Use `getGraph` instead of accessing this field directly.

## Types

### `RPath`


### Fields

- `lazy_path: LazyPath`
  
- `special: []const u8`
  

### `LinkObject`


### Fields

- `static_path: LazyPath`
  
- `other_step: *Step.Compile`
  
- `system_lib: SystemLib`
  
- `assembly_file: LazyPath`
  
- `c_source_file: *CSourceFile`
  
- `c_source_files: *CSourceFiles`
  
- `win32_resource_file: *RcSourceFile`
  Deprecated. This functionality will be moved to an external package:
  https://codeberg.org/ziglang/rc

### `SystemLib`


### Fields

- `name: []const u8`
  
- `needed: bool`
  
- `weak: bool`
  
- `use_pkg_config: UsePkgConfig`
  
- `preferred_link_mode: std.builtin.LinkMode`
  
- `search_strategy: SystemLib.SearchStrategy`
  

### Constants & Variables

- **`UsePkgConfig`**: 
- **`SearchStrategy`**: 

### `CSourceLanguage`


### Fields

- `c`
  
- `cpp`
  
- `objective_c`
  
- `objective_cpp`
  
- `assembly`
  Standard assembly
- `assembly_with_preprocessor`
  Assembly with the C preprocessor

### Functions

#### `clangIdentifier`

```zig
pub fn clangIdentifier(self: CSourceLanguage) [:0]const u8
```

The value passed to "-x" CLI flag of Clang.

### `CSourceFiles`


### Fields

- `root: LazyPath`
  
- `files: []const []const u8`
  `files` is relative to `root`, which is
  the build root by default
- `flags: []const []const u8`
  
- `language: ?CSourceLanguage`
  By default, determines language of each file individually based on its file extension

### `CSourceFile`


### Fields

- `file: LazyPath`
  
- `flags: []const []const u8 = &.{}`
  
- `language: ?CSourceLanguage = null`
  By default, determines language of each file individually based on its file extension

### Functions

#### `dupe`

```zig
pub fn dupe(file: CSourceFile, graph: *const std.Build.Graph) CSourceFile
```


### `RcSourceFile`

Deprecated. This functionality will be moved to an external package:
https://codeberg.org/ziglang/rc

### Fields

- `file: LazyPath`
  
- `flags: []const []const u8 = &.{}`
  Any option that rc.exe accepts will work here, with the exception of:
  - `/fo`: The output filename is set by the build system
  - `/p`: Only running the preprocessor is not supported in this context
  - `/:no-preprocess` (non-standard option): Not supported in this context
  - Any MUI-related option
  https://learn.microsoft.com/en-us/windows/win32/menurc/using-rc-the-rc-command-line-
  
  Implicitly defined options:
   /x (ignore the INCLUDE environment variable)
   /D_DEBUG or /DNDEBUG depending on the optimization mode
- `include_paths: []const LazyPath = &.{}`
  Include paths that may or may not exist yet and therefore need to be
  specified as a LazyPath. Each path will be appended to the flags
  as `/I <resolved path>`.

### Functions

#### `dupe`

```zig
pub fn dupe(file: RcSourceFile, graph: *const std.Build.Graph) RcSourceFile
```


### `IncludeDir`


### Fields

- `path: LazyPath`
  
- `path_system: LazyPath`
  
- `path_after: LazyPath`
  
- `framework_path: LazyPath`
  
- `framework_path_system: LazyPath`
  
- `other_step: *Step.Compile`
  
- `config_header_step: *Step.ConfigHeader`
  
- `embed_path: LazyPath`
  

### `LinkFrameworkOptions`


### Fields

- `needed: bool = false`
  Causes dynamic libraries to be linked regardless of whether they are
  actually depended on. When false, dynamic libraries with no referenced
  symbols will be omitted by the linker.
- `weak: bool = false`
  Marks all referenced symbols from this library as weak, meaning that if
  a same-named symbol is provided by another compilation unit, instead of
  emitting a "duplicate symbol" error, the linker will resolve all
  references to the symbol with the strong version.
  
  When the linker encounters two weak symbols, the chosen one is
  determined by the order compilation units are provided to the linker,
  priority given to later ones.

### `CreateOptions`

Unspecified options here will be inherited from parent `Module` when
inserted into an import table.

### Fields

- `root_source_file: ?LazyPath = null`
  This could either be a generated file, in which case the module
  contains exactly one file, or it could be a path to the root source
  file of directory of files which constitute the module.
  If `null`, it means this module is made up of only `link_objects`.
- `imports: []const Import = &.{}`
  The table of other modules that this module can access via `@import`.
  Imports are allowed to be cyclical, so this table can be added to after
  the `Module` is created via `addImport`.
- `target: ?std.Build.ResolvedTarget = null`
  
- `optimize: ?std.builtin.Optimize = null`
  
- `link_libc: ?bool = null`
  `true` requires a compilation that includes this Module to link libc.
  `false` causes a build failure if a compilation that includes this Module would link libc.
  `null` neither requires nor prevents libc from being linked.
- `link_libcpp: ?bool = null`
  `true` requires a compilation that includes this Module to link libc++.
  `false` causes a build failure if a compilation that includes this Module would link libc++.
  `null` neither requires nor prevents libc++ from being linked.
- `single_threaded: ?bool = null`
  
- `strip: ?bool = null`
  
- `unwind_tables: ?std.builtin.UnwindTables = null`
  
- `dwarf_format: ?std.dwarf.Format = null`
  
- `code_model: std.builtin.CodeModel = .default`
  
- `stack_protector: ?bool = null`
  
- `stack_check: ?bool = null`
  
- `sanitize_c: ?std.zig.SanitizeC = null`
  
- `sanitize_thread: ?bool = null`
  
- `fuzz: ?bool = null`
  
- `valgrind: ?bool = null`
  Whether to emit machine code that integrates with Valgrind.
- `pic: ?bool = null`
  Position Independent Code
- `red_zone: ?bool = null`
  
- `omit_frame_pointer: ?bool = null`
  Whether to omit the stack frame pointer. Frees up a register and makes it
  more difficult to obtain stack traces. Has target-dependent effects.
- `error_tracing: ?bool = null`
  
- `no_builtin: ?bool = null`
  
- `patchable_function_entry: u16 = 0`
  

### `Import`


### Fields

- `name: []const u8`
  
- `module: *Module`
  

### `LinkSystemLibraryOptions`


### Fields

- `needed: bool = false`
  Causes dynamic libraries to be linked regardless of whether they are
  actually depended on. When false, dynamic libraries with no referenced
  symbols will be omitted by the linker.
- `weak: bool = false`
  Marks all referenced symbols from this library as weak, meaning that if
  a same-named symbol is provided by another compilation unit, instead of
  emitting a "duplicate symbol" error, the linker will resolve all
  references to the symbol with the strong version.
  
  When the linker encounters two weak symbols, the chosen one is
  determined by the order compilation units are provided to the linker,
  priority given to later ones.
- `use_pkg_config: SystemLib.UsePkgConfig = .yes`
  
- `preferred_link_mode: std.builtin.LinkMode = .dynamic`
  
- `search_strategy: SystemLib.SearchStrategy = .paths_first`
  

### `AddCSourceFilesOptions`


### Fields

- `root: ?LazyPath = null`
  When provided, `files` are relative to `root` rather than the
  package that owns the `Compile` step.
- `files: []const []const u8`
  
- `flags: []const []const u8 = &.{}`
  
- `language: ?CSourceLanguage = null`
  By default, determines language of each file individually based on its file extension

### `Graph`

Elements of `modules` and `names` are matched one-to-one.

### Fields

- `modules: []const *Module`
  
- `names: []const []const u8`
  

## Functions

### `init`

```zig
pub fn init(m: *Module, owner: *std.Build, value: union(enum) { options: CreateOptions, existing: *const Module }, ) void
```


### `create`

```zig
pub fn create(owner: *std.Build, options: CreateOptions) *Module
```


### `addImport`

```zig
pub fn addImport(m: *Module, name: []const u8, module: *Module) void
```

Adds an existing module to be used with `@import`.

### `addAnonymousImport`

```zig
pub fn addAnonymousImport(m: *Module, name: []const u8, options: CreateOptions) void
```

Creates a new module and adds it to be used with `@import`.

### `addOptions`

```zig
pub fn addOptions(m: *Module, module_name: []const u8, options: *Step.Options) void
```

Converts a set of key-value pairs into a Zig source file, and then inserts it into
the Module's import table with the specified name. This makes the options importable
via `@import("module_name")`.

### `linkSystemLibrary`

```zig
pub fn linkSystemLibrary(m: *Module, name: []const u8, options: LinkSystemLibraryOptions, ) void
```


### `linkFramework`

```zig
pub fn linkFramework(m: *Module, name: []const u8, options: LinkFrameworkOptions) void
```


### `addCSourceFiles`

```zig
pub fn addCSourceFiles(m: *Module, options: AddCSourceFilesOptions) void
```

Handy when you have many non-Zig source files and want them all to have the same flags.

### `addCSourceFile`

```zig
pub fn addCSourceFile(m: *Module, source: CSourceFile) void
```


### `addWin32ResourceFile`

```zig
pub fn addWin32ResourceFile(m: *Module, source: RcSourceFile) void
```

Deprecated. This functionality will be moved to an external package:
https://codeberg.org/ziglang/rc

Resource files must have the extension `.rc`.
Can be called regardless of target. The .rc file will be ignored
if the target object format does not support embedded resources.

### `addAssemblyFile`

```zig
pub fn addAssemblyFile(m: *Module, source: LazyPath) void
```


### `addObjectFile`

```zig
pub fn addObjectFile(m: *Module, object: LazyPath) void
```


### `addObject`

```zig
pub fn addObject(m: *Module, object: *Step.Compile) void
```


### `linkLibrary`

```zig
pub fn linkLibrary(m: *Module, library: *Step.Compile) void
```


### `addAfterIncludePath`

```zig
pub fn addAfterIncludePath(m: *Module, lazy_path: LazyPath) void
```


### `addSystemIncludePath`

```zig
pub fn addSystemIncludePath(m: *Module, lazy_path: LazyPath) void
```


### `addIncludePath`

```zig
pub fn addIncludePath(m: *Module, lazy_path: LazyPath) void
```


### `addConfigHeader`

```zig
pub fn addConfigHeader(m: *Module, config_header: *Step.ConfigHeader) void
```


### `addSystemFrameworkPath`

```zig
pub fn addSystemFrameworkPath(m: *Module, directory_path: LazyPath) void
```


### `addFrameworkPath`

```zig
pub fn addFrameworkPath(m: *Module, directory_path: LazyPath) void
```


### `addEmbedPath`

```zig
pub fn addEmbedPath(m: *Module, lazy_path: LazyPath) void
```


### `addLibraryPath`

```zig
pub fn addLibraryPath(m: *Module, directory_path: LazyPath) void
```


### `addRPath`

```zig
pub fn addRPath(m: *Module, directory_path: LazyPath) void
```


### `addRPathSpecial`

```zig
pub fn addRPathSpecial(m: *Module, bytes: []const u8) void
```


### `addCMacro`

```zig
pub fn addCMacro(m: *Module, name: []const u8, value: []const u8) void
```

Equvialent to the following C code, applied to all C source files owned by
this `Module`:
```c
#define name value
```
`name` and `value` need not live longer than the function call.

### `getGraph`

```zig
pub fn getGraph(root: *Module) Graph
```

Given that `root` is the root `Module` of a compilation, return all
`Module` in the module graph, including `root` itself. `root` is guaranteed
to be the first module in the returned slice.

