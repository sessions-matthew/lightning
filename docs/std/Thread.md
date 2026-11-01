# `std.Thread`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/Thread.zig`  
> [← Back to Standard Library Index](README.md)

This struct represents a kernel thread.

## Fields

- `impl: Impl`
  

## Types

### `Id`

Represents an ID per thread guaranteed to be unique only within a process.

### `SpawnConfig`

Configuration options for hints on how to spawn threads.

### Fields

- `stack_size: usize = default_stack_size`
  Size in bytes of the Thread's stack
- `allocator: ?std.mem.Allocator = null`
  The allocator to be used to allocate memory for the to-be-spawned thread

### Constants & Variables

- **`default_stack_size`**: 

## Functions

### `setName`

```zig
pub fn setName(self: Thread, io: Io, name: []const u8) SetNameError!void
```


### `getName`

```zig
pub fn getName(self: Thread, buffer_ptr: *[max_name_len:0]u8) GetNameError!?[]const u8
```

On Windows, the result is encoded as [WTF-8](https://wtf-8.codeberg.page/).
On other platforms, the result is an opaque sequence of bytes with no particular encoding.

### `getCurrentId`

```zig
pub fn getCurrentId() Id
```

Returns the platform ID of the callers thread.
Attempts to use thread locals and avoid syscalls when possible.

### `getCpuCount`

```zig
pub fn getCpuCount() CpuCountError!usize
```

Returns the platforms view on the number of logical CPU cores available.

Returned value guaranteed to be >= 1.

### `spawn`

```zig
pub fn spawn(config: SpawnConfig, comptime function: anytype, args: anytype) SpawnError!Thread
```

Spawns a new thread which executes `function` using `args` and returns a handle to the spawned thread.
`config` can be used as hints to the platform for how to spawn and execute the `function`.
The caller must eventually either call `join()` to wait for the thread to finish and free its resources
or call `detach()` to excuse the caller from calling `join()` and have the thread clean up its resources on completion.

### `getHandle`

```zig
pub fn getHandle(self: Thread) Handle
```

Returns the handle of this thread

### `detach`

```zig
pub fn detach(self: Thread) void
```

Release the obligation of the caller to call `join()` and have the thread clean up its own resources on completion.
Once called, this consumes the Thread object and invoking any other functions on it is considered undefined behavior.

### `join`

```zig
pub fn join(self: Thread) void
```

Waits for the thread to complete, then deallocates any resources created on `spawn()`.
Once called, this consumes the Thread object and invoking any other functions on it is considered undefined behavior.

### `yield`

```zig
pub fn yield() YieldError!void
```

Yields the current thread potentially allowing other threads to run.

### `run`

```zig
pub fn run(ctx: *@This()) !void
```


### `maybeAttachSignalStack`

```zig
pub fn maybeAttachSignalStack() void
```

Configures the per-thread alternative signal stack requested by `std.options.signal_stack_size`.

## Error Sets

- **`SetNameError`**
  
- **`GetNameError`**
  
- **`CpuCountError`**
  
- **`SpawnError`**
  
- **`YieldError`**
  

## Constants & Variables

- **`use_pthreads`**: 
- **`max_name_len`**: 
- **`Handle`**: Represents a kernel thread handle.

