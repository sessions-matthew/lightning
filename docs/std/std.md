# `std`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/std.zig`  
> [← Back to Standard Library Index](README.md)

## Types

### `ArrayList`

```zig
pub fn ArrayList(comptime T: type) type
```

A contiguous, growable list of items in memory. This is a wrapper around a
slice of `T` values.

The same allocator must be used throughout its entire lifetime. Initialize
directly with `empty` or `initCapacity`, and deinitialize with `deinit` or
`toOwnedSlice`.

### `Options`


### Fields

- `enable_segfault_handler: bool = debug.default_enable_segfault_handler`
  
- `signal_stack_size: ?u64 = 1 << 18`
  If set, `std.start` and `std.Thread` will configure an per-thread alternative signal stack
  of this size. Importantly, if `enable_segfault_handler` is set, the segfault handler will
  use this alternative stack, meaning it can still print stack traces even if a segmentation
  fault is caused by a stack overflow.
  
  On POSIX targets, the signal stack is configured using 'sigaltstack(2)'.
  
  On Windows, this value is currently ignored.
- `log_level: log.Level = log.default_level`
  The current log level.
- `log_scope_levels: []const log.ScopeLevel = &.{}`
  
- `logFn: fn (comptime message_level: log.Level, comptime scope: @EnumLiteral(), comptime format: []const u8, args: anytype, ) void = log.defaultLog`
  
- `page_size_min: ?usize = null`
  Overrides `std.heap.page_size_min`.
- `page_size_max: ?usize = null`
  Overrides `std.heap.page_size_max`.
- `queryPageSize: fn () usize = heap.defaultQueryPageSize`
  Overrides default implementation for determining OS page size at runtime.
- `fmt_max_depth: usize = fmt.default_max_depth`
  
- `http_disable_tls: bool = false`
  By default, std.http.Client will support HTTPS connections.  Set this option to `true` to
  disable TLS support.
  
  This will likely reduce the size of the binary, but it will also make it impossible to
  make a HTTPS connection.
- `http_enable_ssl_key_log_file: bool = @import("builtin").mode == .debug`
  This enables `std.http.Client` to log ssl secrets to the file specified by the SSLKEYLOGFILE
  env var.  Creating such a log file allows other programs with access to that file to decrypt
  all `std.http.Client` traffic made by this program.
- `side_channels_mitigations: crypto.SideChannelsMitigations = crypto.default_side_channels_mitigations`
  
- `allow_stack_tracing: bool = !@import("builtin").strip_debug_info`
  Whether to allow capturing and writing stack traces. This affects the following functions:
  * `debug.captureCurrentStackTrace`
  * `debug.writeCurrentStackTrace`
  * `debug.dumpCurrentStackTrace`
  * `debug.writeStackTrace`
  * `debug.dumpStackTrace`
  * `debug.writeErrorReturnTrace`
  * `debug.dumpErrorReturnTrace`
  
  Stack traces can generally be collected and printed when debug info is stripped, but are
  often less useful since they usually cannot be mapped to source locations and/or have bad
  source locations. The stack tracing logic can also be quite large, which may be undesirable,
  particularly in ReleaseSmall.
  
  If this is `false`, then captured stack traces will always be empty, and attempts to write
  stack traces will just print an error to the relevant `Io.Writer` and return.
- `networking: bool = true`
  Allows disabling networking in std.Io implementations.
- `unexpected_error_tracing: bool = @import("builtin").mode == .debug and switch (@import("builtin").zig_backend) { .stage2_llvm, .stage2_x86_64 => true, else => false, }`
  Whether or not `error.Unexpected` will print its value and a stack trace.
  
  If this happens the fix is to add the error code to the corresponding
  switch expression, possibly introduce a new error in the error set, and
  send a patch to Zig.

### Constants & Variables

- **`logTerminalMode`**: TODO This is a separate decl instead of a field as a workaround around
- **`elf_debug_info_search_paths`**: TODO This is a separate decl instead of a field as a workaround around
- **`debug_threaded_io`**: 
- **`debug_io`**: The `Io` instance that `std.debug` uses for `std.debug.print`,
- **`FilePermissions`**: Overrides `std.Io.File.Permissions`.
- **`cwd`**: Overrides `std.Io.Dir.cwd`.

## Constants & Variables

- **`AutoHashMap`**
- **`AutoHashMapUnmanaged`**: 
- **`BitStack`**: 
- **`Build`**: 
- **`BufMap`**: 
- **`BufSet`**: 
- **`StaticStringMap`**: 
- **`StaticStringMapWithEql`**: 
- **`Deque`**: 
- **`DoublyLinkedList`**: 
- **`DynLib`**: 
- **`DynamicBitSet`**: Deprecated: use `bit_set.DynamicManaged`.
- **`DynamicBitSetUnmanaged`**: Deprecated: use `bit_set.Dynamic`.
- **`EnumArray`**: 
- **`EnumMap`**: 
- **`EnumSet`**: 
- **`HashMap`**: 
- **`HashMapUnmanaged`**: 
- **`Io`**: 
- **`MultiArrayList`**: 
- **`PriorityQueue`**: 
- **`PriorityDequeue`**: 
- **`Progress`**: 
- **`Random`**: 
- **`SemanticVersion`**: 
- **`SinglyLinkedList`**: 
- **`StaticBitSet`**: Deprecated: use `bit_set.Static`.
- **`StringHashMap`**: 
- **`StringHashMapUnmanaged`**: 
- **`Target`**: 
- **`Thread`**: 
- **`Treap`**: 
- **`Tz`**: 
- **`Uri`**: 
- **`ArrayHashMapUnmanaged`**: Deprecated; use `array_hash_map.Custom`.
- **`AutoArrayHashMapUnmanaged`**: Deprecated; use `array_hash_map.Auto`.
- **`StringArrayHashMapUnmanaged`**: Deprecated; use `array_hash_map.String`.
- **`array_list`**: 
- **`ArrayListAligned`**: Deprecated; use `array_list.Aligned`.
- **`ArrayListAlignedUnmanaged`**: Deprecated; use `array_list.Aligned`.
- **`ArrayListUnmanaged`**: Deprecated; use `ArrayList`.
- **`array_hash_map`**: 
- **`atomic`**: 
- **`base64`**: 
- **`bit_set`**: 
- **`builtin`**: Deprecated; use `lang`.
- **`lang`**: 
- **`c`**: 
- **`coff`**: 
- **`compress`**: 
- **`static_string_map`**: 
- **`crypto`**: 
- **`debug`**: 
- **`dwarf`**: 
- **`elf`**: 
- **`enums`**: 
- **`fmt`**: 
- **`fs`**: 
- **`spirv`**: 
- **`hash`**: 
- **`hash_map`**: 
- **`heap`**: 
- **`http`**: 
- **`json`**: 
- **`leb`**: 
- **`log`**: 
- **`macho`**: 
- **`math`**: 
- **`mem`**: 
- **`meta`**: 
- **`os`**: 
- **`pdb`**: 
- **`pie`**: 
- **`posix`**: 
- **`process`**: 
- **`sort`**: 
- **`simd`**: 
- **`ascii`**: 
- **`tar`**: 
- **`testing`**: 
- **`time`**: 
- **`tz`**: 
- **`unicode`**: 
- **`valgrind`**: 
- **`wasm`**: 
- **`zig`**: 
- **`zip`**: 
- **`zon`**: 
- **`start`**: 
- **`options`**: Compile-time known settings overridable by the root source file.

