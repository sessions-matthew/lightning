# `std.zig`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/zig.zig`  
> [← Back to Standard Library Index](README.md)

Builds of the Zig compiler are distributed partly in source form. That
source lives here. These APIs are provided as-is and have absolutely no API
guarantees whatsoever.

## Types

### `SrcHash`


### `Color`


### Fields

- `auto`
  Auto-detect whether stream supports terminal colors.
- `off`
  Force-enable colors.
- `on`
  Suppress colors.

### Functions

#### `terminalMode`

```zig
pub fn terminalMode(color: Color) ?Io.Terminal.Mode
```


#### `settingFromEnvironment`

```zig
pub fn settingFromEnvironment(environ_map: *const std.process.Environ.Map) Color
```

Determine the preference for color or no color based on the NO_COLOR and
CLICOLOR_FORCE environment variables. Color is always disabled on WASI per
https://github.com/WebAssembly/WASI/issues/162

### `Loc`


### Fields

- `line: usize`
  
- `column: usize`
  
- `source_line: []const u8`
  Does not include the trailing newline.

### Functions

#### `eql`

```zig
pub fn eql(a: Loc, b: Loc) bool
```


### `BinNameOptions`


### Fields

- `root_name: []const u8`
  
- `cpu_arch: std.Target.Cpu.Arch`
  
- `os_tag: std.Target.Os.Tag`
  
- `ofmt: std.Target.ObjectFormat`
  
- `abi: std.Target.Abi`
  
- `output_mode: std.lang.OutputMode`
  
- `link_mode: ?std.lang.LinkMode = null`
  
- `version: ?std.SemanticVersion = null`
  

### `SanitizeC`


### Fields

- `off`
  
- `trap`
  
- `full`
  

### `BuildId`


### Fields

- `none`
  
- `fast`
  
- `uuid`
  
- `sha1`
  
- `md5`
  
- `hexstring: HexString`
  

### Types

#### `HexString`


### Functions

#### `eql`

```zig
pub fn eql(a: BuildId, b: BuildId) bool
```


#### `initHexString`

```zig
pub fn initHexString(bytes: []const u8) BuildId
```

Input is byte values, *not* hex-encoded.
Asserts `bytes` fits inside `HexString`

#### `parse`

```zig
pub fn parse(text: []const u8) !BuildId
```

Converts UTF-8 text to a `BuildId`.

#### `format`

```zig
pub fn format(id: BuildId, writer: *Writer) Writer.Error!void
```


### `LtoMode`


### Fields

- `none`
  
- `full`
  
- `thin`
  

### `Subsystem`


### Fields

- `console`
  
- `windows`
  
- `posix`
  
- `native`
  
- `efi_application`
  
- `efi_boot_service_driver`
  
- `efi_rom`
  
- `efi_runtime_driver`
  

### `CompressDebugSections`


### Fields

- `none`
  
- `zlib`
  
- `zstd`
  

### `RcIncludes`


### Fields

- `any`
  Use MSVC if available, fall back to MinGW.
- `msvc`
  Use MSVC include paths (MSVC install + Windows SDK, must be present on the system).
- `gnu`
  Use MinGW include paths (distributed with Zig).
- `none`
  Do not use any autodetected include paths.

### `FormatId`


### Fields

- `bytes: []const u8`
  
- `flags: Flags`
  

### Types

#### `Flags`


### Functions

#### `format`

```zig
pub fn format(ctx: FormatId, writer: *Writer) Writer.Error!void
```

Print the string as a Zig identifier, escaping it with `@""` syntax if needed.

### `StringEscapeWriter`


### Fields

- `out: *Writer`
  
- `writer: Writer`
  

### Functions

#### `init`

```zig
pub fn init(out: *Writer, buffer: []u8) @This()
```


### Constants & Variables

- **`min_buffer_len`**: 

### `EnvVar`

Collects all the environment variables that Zig could possibly inspect, so
that we can do reflection on this and print them with `zig env`.

### Fields

- `ZIG_GLOBAL_CACHE_DIR`
  
- `ZIG_LOCAL_CACHE_DIR`
  
- `ZIG_LOCAL_PKG_DIR`
  
- `ZIG_LIB_DIR`
  
- `ZIG_LIBC`
  
- `ZIG_BUILD_ERROR_STYLE`
  
- `ZIG_BUILD_MULTILINE_ERRORS`
  
- `ZIG_BUILD_SUMMARY`
  
- `ZIG_VERBOSE_LINK`
  
- `ZIG_VERBOSE_CC`
  
- `ZIG_VERBOSE_CMD`
  
- `ZIG_DEBUG_CMD`
  
- `ZIG_IS_DETECTING_LIBC_PATHS`
  
- `ZIG_IS_AVOIDING_CALLING_ITSELF`
  
- `NIX_CFLAGS_COMPILE`
  
- `NIX_CFLAGS_LINK`
  
- `NIX_LDFLAGS`
  
- `C_INCLUDE_PATH`
  
- `CPLUS_INCLUDE_PATH`
  
- `LIBRARY_PATH`
  
- `CC`
  
- `PKG_CONFIG`
  
- `NO_COLOR`
  
- `CLICOLOR_FORCE`
  
- `XDG_CACHE_HOME`
  
- `LOCALAPPDATA`
  
- `HOME`
  
- `PROGRAMDATA`
  
- `HOMEBREW_PREFIX`
  

### Functions

#### `isSet`

```zig
pub fn isSet(ev: EnvVar, map: *const std.process.Environ.Map) bool
```


#### `get`

```zig
pub fn get(ev: EnvVar, map: *const std.process.Environ.Map) ?[]const u8
```


### `SimpleComptimeReason`


### Fields

- `operand_setEvalBranchQuota`
  
- `operand_setFloatMode`
  
- `operand_branchHint`
  
- `operand_setRuntimeSafety`
  
- `operand_embedFile`
  
- `operand_shuffle_mask`
  
- `operand_atomicRmw_operation`
  
- `operand_reduce_operation`
  
- `export_target`
  
- `export_options`
  
- `extern_options`
  
- `prefetch_options`
  
- `call_modifier`
  
- `compile_error_string`
  
- `inline_assembly_code`
  
- `atomic_order`
  
- `slice_cat_operand`
  
- `inline_call_target`
  
- `generic_call_target`
  
- `wasm_memory_index`
  
- `work_group_dim_index`
  
- `clobber`
  
- `type`
  
- `int_signedness`
  
- `int_bit_width`
  
- `array_sentinel`
  
- `array_length`
  
- `pointer_size`
  
- `pointer_attrs`
  
- `pointer_sentinel`
  
- `slice_sentinel`
  
- `vector_length`
  
- `fn_ret_ty`
  
- `fn_param_types`
  
- `fn_param_attrs`
  
- `fn_attrs`
  
- `struct_layout`
  
- `struct_field_names`
  
- `struct_field_types`
  
- `struct_field_attrs`
  
- `union_layout`
  
- `union_field_names`
  
- `union_field_types`
  
- `union_field_attrs`
  
- `tuple_field_types`
  
- `enum_field_names`
  
- `enum_field_values`
  
- `union_enum_tag_type`
  
- `enum_int_tag_type`
  
- `packed_struct_backing_int_type`
  
- `packed_union_backing_int_type`
  
- `decl_name`
  
- `field_name`
  
- `tuple_field_index`
  
- `container_var_init`
  
- `@"callconv"`
  
- `@"align"`
  
- `@"addrspace"`
  
- `@"linksection"`
  
- `comptime_keyword`
  
- `comptime_call_modifier`
  
- `inline_loop_operand`
  
- `switch_item`
  
- `tuple_field_default_value`
  
- `struct_field_default_value`
  
- `enum_field_tag_value`
  
- `slice_single_item_ptr_bounds`
  
- `stored_to_comptime_field`
  
- `stored_to_comptime_var`
  
- `casted_to_comptime_int`
  
- `casted_to_comptime_float`
  
- `std_lang_decl`
  

### Functions

#### `message`

```zig
pub fn message(r: SimpleComptimeReason) []const u8
```


### `EmitArtifact`

Every kind of artifact which the compiler can emit.

### Fields

- `bin`
  
- `@"asm"`
  
- `implib`
  
- `llvm_ir`
  
- `llvm_bc`
  
- `docs`
  
- `pdb`
  
- `h`
  

### Functions

#### `cacheName`

```zig
pub fn cacheName(ea: EmitArtifact, gpa: Allocator, opts: BinNameOptions) Allocator.Error![]const u8
```

If using `Server` to communicate with the compiler, it will place requested artifacts in
paths under the output directory, where those paths are named according to this function.
Returned string is allocated with `gpa` and owned by the caller.

### `ClangCliParam`

The defaults are chosen here to reduce the size of src/clang_options.zon

### Fields

- `name: []const u8`
  
- `ze: ZigEquivalent = .other`
  
- `syntax: Syntax = .flag`
  
- `pd1: bool = true`
  Prefixed by "-"
- `pd2: bool = false`
  Prefixed by "--"
- `psl: bool = false`
  Prefixed by "/"

### Types

#### `Syntax`


#### `ZigEquivalent`


### Functions

#### `matchEql`

```zig
pub fn matchEql(self: @This(), arg: []const u8) u2
```


#### `matchStartsWith`

```zig
pub fn matchStartsWith(self: @This(), arg: []const u8) usize
```


### `AllocPrintCmdOptions`

Deprecated

### Fields

- `cwd: ?[]const u8 = null`
  
- `parent_env: ?*const std.process.Environ.Map = null`
  
- `child_env: ?*const std.process.Environ.Map = null`
  

### `SubprocessCommand`


### Fields

- `argv: []const []const u8`
  
- `cwd: ?[]const u8 = null`
  
- `parent_env: ?*const std.process.Environ.Map = null`
  
- `child_env: ?*const std.process.Environ.Map = null`
  

### Functions

#### `format`

```zig
pub fn format(sc: SubprocessCommand, w: *Io.Writer) Io.Writer.Error!void
```


### `Directories`


### Fields

- `cwd: []const u8`
  The string returned by `introspect.getResolvedCwd`. This is typically an absolute path,
  but on WASI is the empty string "" instead, because WASI does not have absolute paths.
- `zig_lib: Cache.Directory`
  The Zig 'lib' directory.
  `zig_lib.path` is resolved (`resolvePath`) or `null` for cwd.
  Guaranteed to be a different path from `global_cache` and `local_cache`.
- `global_cache: Cache.Directory`
  The global Zig cache directory.
  `global_cache.path` is resolved (`resolvePath`) or `null` for cwd.
- `local_cache: Cache.Directory`
  The local Zig cache directory.
  `local_cache.path` is resolved (`resolvePath`) or `null` for cwd.
  This may be the same as `global_cache`.
- `build_root: Cache.Directory`
  The directory that contains build.zig. This path is provided by the
  build system, when the build system is used, otherwise, it is `null`
  for cwd.

### Types

#### `InitOptions`


### Functions

#### `deinit`

```zig
pub fn deinit(dirs: *Directories, io: Io) void
```


#### `withoutLocalCache`

```zig
pub fn withoutLocalCache(dirs: Directories) Directories
```

Returns a `Directories` where `local_cache` is replaced with `global_cache`, intended for
use by sub-compilations (e.g. compiler_rt). Do not `deinit` the returned `Directories`; it
shares handles with `dirs`.

#### `init`

```zig
pub fn init(arena: Allocator, io: Io, options: InitOptions) Directories
```

Uses `std.process.fatal` on error conditions.

#### `openUnresolved`

```zig
pub fn openUnresolved(arena: Allocator, io: Io, cwd: []const u8, unresolved_path: []const u8, thing: enum { @"zig lib", @"global cache", @"local cache", @"build root" }, ) Cache.Directory
```


### `BuildExeSubprocessOptions`


### Fields

- `argv: []const []const u8`
  
- `cache_root: Cache.Directory`
  
- `root_name: []const u8`
  
- `environ_map: ?*std.process.Environ.Map = null`
  
- `cache_manifest: ?*Cache.Manifest = null`
  
- `arch_os_abi: ?[]const u8 = null`
  
- `cpu_features: ?[]const u8 = null`
  
- `progress_node: std.Progress.Node = .none`
  
- `skip_log_cmdline_on_compile_errors: bool = false`
  
- `error_bundle: ?*ErrorBundle = null`
  If this is provided, compilation errors are sent here. Otherwise, they are printed to stderr.
  Must be an initialized `ErrorBundle`; if it is updated then it is cleared first.

### `BuildExeSubprocessResult`


### Fields

- `received_fs_inputs: bool`
  
- `cache_hit: bool`
  
- `path: Cache.Path`
  

## Namespaces

- **`c_translation`**: 

## Functions

### `hashSrc`

```zig
pub fn hashSrc(src: []const u8) SrcHash
```


### `srcHashEql`

```zig
pub fn srcHashEql(a: SrcHash, b: SrcHash) bool
```


### `hashName`

```zig
pub fn hashName(parent_hash: SrcHash, sep: []const u8, name: []const u8) SrcHash
```


### `findLineColumn`

```zig
pub fn findLineColumn(source: []const u8, byte_offset: usize) Loc
```


### `lineDelta`

```zig
pub fn lineDelta(source: []const u8, start: usize, end: usize) isize
```


### `binNameAlloc`

```zig
pub fn binNameAlloc(allocator: Allocator, options: BinNameOptions) error{OutOfMemory}![]u8
```

Returns the standard file system basename of a binary generated by the Zig compiler.

### `serializeCpu`

```zig
pub fn serializeCpu(buffer: *std.array_list.Managed(u8), cpu: std.Target.Cpu) Allocator.Error!void
```

Renders a `std.Target.Cpu` value into a textual representation that can be parsed
via the `-mcpu` flag passed to the Zig compiler.
Appends the result to `buffer`.

### `serializeCpuAlloc`

```zig
pub fn serializeCpuAlloc(ally: Allocator, cpu: std.Target.Cpu) Allocator.Error![]u8
```


### `fmtId`

```zig
pub fn fmtId(bytes: []const u8) FormatId
```

Return a Formatter for a Zig identifier, escaping it with `@""` syntax if needed.

See also `fmtIdFlags`.

### `fmtIdFlags`

```zig
pub fn fmtIdFlags(bytes: []const u8, flags: FormatId.Flags) FormatId
```

Return a Formatter for a Zig identifier, escaping it with `@""` syntax if needed.

See also `fmtId`.

### `fmtIdPU`

```zig
pub fn fmtIdPU(bytes: []const u8) FormatId
```


### `fmtIdP`

```zig
pub fn fmtIdP(bytes: []const u8) FormatId
```


### `fmtString`

```zig
pub fn fmtString(bytes: []const u8) std.fmt.Alt([]const u8, stringEscape)
```

Return a formatter for escaping a double quoted Zig string.

### `fmtChar`

```zig
pub fn fmtChar(c: u21) std.fmt.Alt(u21, charEscape)
```

Return a formatter for escaping a single quoted Zig string.

### `stringEscape`

```zig
pub fn stringEscape(bytes: []const u8, w: *Writer) Writer.Error!void
```

Print the string as escaped contents of a double quoted string.

The following transformations are made:
* escaped: '\n', '\r', '\t', '\\', '"'
* hex-encoded:
  * ascii control characters
  * invalid UTF-8 sequences
  * non-ascii line endings (U+0085, U+2028, U+2029)
  * byte order marks (U+FEFF)

Everything else is passed through unmodified.

### `charEscape`

```zig
pub fn charEscape(codepoint: u21, w: *Writer) Writer.Error!void
```

Print as escaped contents of a single-quoted string.

### `isValidId`

```zig
pub fn isValidId(bytes: []const u8) bool
```


### `isUnderscore`

```zig
pub fn isUnderscore(bytes: []const u8) bool
```


### `readSourceFileToEndAlloc`

```zig
pub fn readSourceFileToEndAlloc(gpa: Allocator, file_reader: *Io.File.Reader) ![:0]u8
```

If the source can be UTF-16LE encoded, this function asserts that `gpa`
will align a byte-sized allocation to at least 2. Allocators that don't do
this are rare.

### `printAstErrorsToStderr`

```zig
pub fn printAstErrorsToStderr(gpa: Allocator, io: Io, tree: Ast, path: []const u8, color: Color) !void
```


### `putAstErrorsIntoBundle`

```zig
pub fn putAstErrorsIntoBundle(gpa: Allocator, tree: Ast, path: []const u8, wip_errors: *ErrorBundle.Wip, ) Allocator.Error!void
```


### `resolveTargetQueryOrFatal`

```zig
pub fn resolveTargetQueryOrFatal(io: Io, target_query: std.Target.Query) std.Target
```


### `parseTargetQueryOrReportFatalError`

```zig
pub fn parseTargetQueryOrReportFatalError(allocator: Allocator, opts: std.Target.Query.ParseOptions, ) std.Target.Query
```


### `allocPrintCmd`

```zig
pub fn allocPrintCmd(gpa: Allocator, argv: []const []const u8, options: AllocPrintCmdOptions) Allocator.Error![]u8
```

Deprecated

### `getResolvedCwd`

```zig
pub fn getResolvedCwd(io: Io, gpa: Allocator) std.process.CurrentPathAllocError![]u8
```

Like `std.process.currentPathAlloc`, but also resolves the path with `Dir.path.resolve`. This
means the path has no repeated separators, no "." or ".." components, and no trailing separator.
On WASI, "" is returned instead of ".".

### `findZigLibDir`

```zig
pub fn findZigLibDir(gpa: Allocator, io: Io) !Cache.Directory
```

Both the directory handle and the path are newly allocated resources which the caller now owns.

### `findZigLibDirFromSelfExe`

```zig
pub fn findZigLibDirFromSelfExe(allocator: Allocator, io: Io, cwd_path: []const u8, self_exe_path: []const u8, ) error{ OutOfMemory, FileNotFound }!Cache.Directory
```

Both the directory handle and the path are newly allocated resources which the caller now owns.

### `resolveGlobalCacheDir`

```zig
pub fn resolveGlobalCacheDir(arena: Allocator, environ_map: *const std.process.Environ.Map) ![]const u8
```


### `resolveSuitableLocalCacheDir`

```zig
pub fn resolveSuitableLocalCacheDir(arena: Allocator, io: Io, cwd: []const u8) Allocator.Error!?[]u8
```

Searches upwards from `cwd` for a directory containing a `build.zig` file.
If such a directory is found, returns the path to it joined to the `.zig_cache` name.
Otherwise, returns `null`, indicating no suitable local cache location.

### `resolvePath`

```zig
pub fn resolvePath(gpa: Allocator, cwd_resolved: []const u8, paths: []const []const u8, ) Allocator.Error![]u8
```

Similar to `Dir.path.resolve`, but converts to a cwd-relative path, or, if that would
start with a relative up-dir (".."), an absolute path based on the cwd. Also, the cwd
returns the empty string ("") instead of ".".

### `isUpDir`

```zig
pub fn isUpDir(p: []const u8) bool
```


### `buildExeSubprocess`

```zig
pub fn buildExeSubprocess(gpa: Allocator, io: Io, options: BuildExeSubprocessOptions, ) BuildExeSubprocessError!BuildExeSubprocessResult
```

Assumes `argv` has `--listen=-` in it and the child process is `zig build-exe`.

Result path is allocated via gpa.

## Error Sets

- **`BuildExeSubprocessError`**
  

## Constants & Variables

- **`ErrorBundle`**: 
- **`Server`**: 
- **`Client`**: 
- **`Token`**: 
- **`Tokenizer`**: 
- **`TokenSmith`**: 
- **`string_literal`**: 
- **`number_literal`**: 
- **`primitives`**: 
- **`isPrimitive`**: 
- **`Ast`**: 
- **`AstGen`**: 
- **`Zir`**: 
- **`Zoir`**: 
- **`ZonGen`**: 
- **`system`**: 
- **`BuiltinFn`**: 
- **`AstRlAnnotate`**: 
- **`LibCInstallation`**: 
- **`WindowsSdk`**: 
- **`LibCDirs`**: 
- **`PkgConfig`**: 
- **`target`**: 
- **`llvm`**: 
- **`parser_generated_oracle`**: 
- **`ParsedCharLiteral`**: 
- **`parseCharLiteral`**: 
- **`parseNumberLiteral`**: 
- **`default_local_zig_cache_basename`**: 
- **`build_zig_basename`**: 
- **`SrcHasher`**: 
- **`max_src_size`**: There are many assumptions in the entire codebase that Zig source files can

