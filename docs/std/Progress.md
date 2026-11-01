# `std.Progress`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/Progress.zig`  
> [← Back to Standard Library Index](README.md)

This API is non-allocating, non-fallible, thread-safe, and lock-free.

## Fields

- `terminal: Io.File`
  Currently this API only supports this value being set to stderr, which
  happens automatically inside `start`.
- `io: Io`
  
- `terminal_mode: TerminalMode`
  
- `update_worker: ?Io.Future(WorkerError!void)`
  
- `redraw_event: Io.Event`
  Atomically set by SIGWINCH as well as the root done() function.
- `need_clear: bool`
  
- `status: Status`
  
- `refresh_rate_ns: u64`
  
- `initial_delay_ns: u64`
  
- `rows: u16`
  
- `cols: u16`
  
- `draw_buffer: []u8`
  Accessed only by the update thread.
- `node_parents: [node_storage_buffer_len]Node.Parent`
  This is in a separate array from `node_storage` but with the same length so
  that it can be iterated over efficiently without trashing too much of the
  CPU cache.
- `node_storage: [node_storage_buffer_len]Node.Storage`
  
- `node_freelist_next: [node_storage_buffer_len]Node.OptionalIndex`
  
- `node_freelist: Freelist`
  
- `node_end_index: u32`
  This is the number of elements in node arrays which have been used so far. Nodes before this
  index are either active, or on the freelist. The remaining nodes are implicitly free. This
  value may at times temporarily exceed the node count.
- `ipc_next: Ipc.SlotAtomic`
  
- `ipc: [ipc_storage_buffer_len]Ipc`
  
- `ipc_files: [ipc_storage_buffer_len]Io.File`
  
- `start_failure: StartFailure`
  

## Types

### `Status`


### Fields

- `working`
  Indicates the application is progressing towards completion of a task.
  Unless the application is interactive, this is the only status the
  program will ever have!
- `success`
  The application has completed an operation, and is now waiting for user
  input rather than calling exit(0).
- `failure`
  The application encountered an error, and is now waiting for user input
  rather than calling exit(1).
- `failure_working`
  The application encountered at least one error, but is still working on
  more tasks.

### `Ipc`


### Fields

- `locked: bool`
  mutex protecting `file` use, only locked by `serializeIpc`
- `valid: bool`
  when unlocked: whether `file` is defined
  when locked: whether `file` does not need to be closed
- `unused: @Int(.unsigned, 32 - 2 - @bitSizeOf(Generation)) = 0`
  
- `generation: Generation`
  

### Types

#### `Slot`


#### `Index`


### Constants & Variables

- **`Generation`**: 

### `TerminalMode`


### Fields

- `off`
  
- `ansi_escape_codes`
  
- `windows_api: if (is_windows) WindowsApi else noreturn`
  This is not the same as being run on windows because other terminals
  exist like MSYS/git-bash.

### Types

#### `WindowsApi`


### `Node`

Represents one unit of progress. Each node can have children nodes, or
one can use integers with `update`.

### Fields

- `index: OptionalIndex`
  

### Types

#### `OptionalIndex`


#### `Index`

Index into `node_storage`.

### Functions

#### `start`

```zig
pub fn start(node: Node, name: []const u8, estimated_total_items: usize) Node
```

Create a new child progress node. Thread-safe.

Passing 0 for `estimated_total_items` means unknown.

#### `startFmt`

```zig
pub fn startFmt(node: Node, estimated_total_items: usize, comptime format: []const u8, args: anytype) Node
```


#### `completeOne`

```zig
pub fn completeOne(n: Node) void
```

This is the same as calling `start` and then `end` on the returned `Node`. Thread-safe.

#### `setName`

```zig
pub fn setName(n: Node, new_name: []const u8) void
```

Thread-safe. Bytes after '0' in `new_name` are ignored.

#### `getName`

```zig
pub fn getName(n: Node) [max_name_len]u8
```

Gets the name of this `Node`.
A pointer to this array can later be passed to `setName` to restore the name.

#### `setCompletedItems`

```zig
pub fn setCompletedItems(n: Node, completed_items: usize) void
```

Thread-safe.

#### `setEstimatedTotalItems`

```zig
pub fn setEstimatedTotalItems(n: Node, count: usize) void
```

Thread-safe. 0 means unknown.

#### `increaseEstimatedTotalItems`

```zig
pub fn increaseEstimatedTotalItems(n: Node, count: usize) void
```

Thread-safe.

#### `end`

```zig
pub fn end(n: Node) void
```

Finish a started `Node`. Thread-safe.

#### `setIpcFile`

```zig
pub fn setIpcFile(node: Node, expected_io_userdata: ?*anyopaque, file: Io.File) void
```

Used by `std.process.Child`. Thread-safe.

#### `setIpcIndex`

```zig
pub fn setIpcIndex(node: Node, ipc_index: Ipc.Index) void
```


#### `takeIpcIndex`

```zig
pub fn takeIpcIndex(node: Node) ?Ipc.Index
```

Not thread-safe.

### Constants & Variables

- **`none`**: 
- **`max_name_len`**: 

### `StartFailure`


### Fields

- `unstarted`
  
- `spawn_ipc_worker: error{ConcurrencyUnavailable}`
  
- `spawn_update_worker: error{ConcurrencyUnavailable}`
  
- `parent_ipc: error{ UnsupportedOperation, UnrecognizedFormat }`
  

### `Options`


### Fields

- `draw_buffer: []u8 = &default_draw_buffer`
  User-provided buffer with static lifetime.
  
  Used to store the entire write buffer sent to the terminal. Progress output will be truncated if it
  cannot fit into this buffer which will look bad but not cause any malfunctions.
  
  Must be at least 200 bytes.
- `refresh_rate_ns: Io.Duration = .fromMilliseconds(80)`
  How many nanoseconds between writing updates to the terminal.
- `initial_delay_ns: Io.Duration = .fromMilliseconds(200)`
  How many nanoseconds to keep the output hidden
- `estimated_total_items: usize = 0`
  If provided, causes the progress item to have a denominator.
  0 means unknown.
- `root_name: []const u8 = ""`
  
- `disable_printing: bool = false`
  

## Functions

### `start`

```zig
pub fn start(io: Io, options: Options) Node
```

Initializes a global Progress instance.

Asserts there is only one global Progress instance.

Call `Node.end` when done.

If an error occurs, `start_failure` will be populated.

### `setStatus`

```zig
pub fn setStatus(new_status: Status) void
```


### `clearWrittenWithEscapeCodes`

```zig
pub fn clearWrittenWithEscapeCodes(file_writer: *Io.File.Writer) Io.Writer.Error!void
```


## Error Sets

- **`ParentFileError`**
  

## Constants & Variables

- **`max_packet_len`**: 
- **`have_ipc`**: 

