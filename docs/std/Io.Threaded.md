# `std.Io.Threaded`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/Io/Threaded.zig`  
> [← Back to Standard Library Index](README.md)

## Fields

- `allocator: Allocator`
  Thread-safe.
  
  Used for:
  * allocating `Io.Future` and `Io.Group` closures.
  * formatting spawning child processes
  * scanning environment variables on some targets
  * memory-mapping when mmap or equivalent is not available
- `mutex: Io.Mutex = .init`
  
- `cond: Io.Condition = .init`
  
- `run_queue: std.SinglyLinkedList = .{}`
  
- `join_requested: bool = false`
  
- `stack_size: usize`
  
- `wait_group: WaitGroup = .init`
  All threads are spawned detached; this is how we wait until they all exit.
- `async_limit: Io.Limit`
  
- `concurrent_limit: Io.Limit = .unlimited`
  
- `cpu_count_error: ?std.Thread.CpuCountError`
  Error from calling `std.Thread.getCpuCount` in `init`.
- `busy_count: usize = 0`
  Number of threads that are unavailable to take tasks. To calculate
  available count, subtract this from either `async_limit` or
  `concurrent_limit`.
- `worker_threads: std.atomic.Value(?*Thread)`
  
- `pid: Pid = .unknown`
  
- `have_signal_handler: bool`
  
- `old_sig_io: if (have_sig_io) posix.Sigaction else void`
  
- `old_sig_pipe: if (have_sig_pipe) posix.Sigaction else void`
  
- `use_sendfile: UseSendfile = .default`
  
- `use_copy_file_range: UseCopyFileRange = .default`
  
- `use_fcopyfile: UseFcopyfile = .default`
  
- `use_fchmodat2: UseFchmodat2 = .default`
  
- `disable_memory_mapping: bool`
  
- `stderr_writer: File.Writer = .{ .io = undefined, .interface = File.Writer.initInterface(&.{}), .file = if (is_windows) undefined else .stderr(), .mode = .streaming, }`
  
- `stderr_mode: Io.Terminal.Mode = .no_color`
  
- `stderr_writer_initialized: bool = false`
  
- `stderr_mutex: Io.Mutex = .init`
  
- `stderr_mutex_locker: std.Thread.Id = Thread.invalid_id`
  
- `stderr_mutex_lock_count: usize = 0`
  
- `argv0: Argv0`
  
- `environ_initialized: bool`
  Protected by `mutex`. Determines whether `environ` has been
  memoized based on `process_environ`.
- `environ: Environ`
  
- `dl: Dl = .init`
  
- `null_file: NullFile = .{}`
  
- `random_file: RandomFile = .{}`
  
- `pipe_file: PipeFile = .{}`
  
- `csprng: Csprng = .uninitialized`
  
- `system_basic_information: SystemBasicInformation = .{}`
  
- `process_spawn_mutex: if (is_windows) Io.Mutex else void = if (is_windows) .init else {}`
  

## Types

### `Csprng`


### Fields

- `rng: std.Random.DefaultCsprng`
  

### Functions

#### `isInitialized`

```zig
pub fn isInitialized(c: *const Csprng) bool
```


### Constants & Variables

- **`uninitialized`**: 
- **`seed_len`**: 

### `Argv0`


### Functions

#### `init`

```zig
pub fn init(args: process.Args) Argv0
```


#### `init`

```zig
pub fn init(args: process.Args) Argv0
```


### Constants & Variables

- **`empty`**: 
- **`empty`**: 

### `Environ`


### Fields

- `process_environ: process.Environ`
  Unmodified data directly from the OS.
- `exist: Exist = .{}`
  Protected by `mutex`. Memoized based on `process_environ`. Tracks whether the
  environment variables are present, ignoring their value.
- `string: String = .{}`
  Protected by `mutex`. Memoized based on `process_environ`.
- `zig_progress_file: std.Progress.ParentFileError!File = error.EnvironmentVariableMissing`
  ZIG_PROGRESS
- `err: ?Error = null`
  Protected by `mutex`. Tracks the problem, if any, that occurred when
  trying to scan environment variables.
  
  Errors are only possible on WASI.

### Types

#### `Exist`


#### `String`


### Functions

#### `scan`

```zig
pub fn scan(environ: *Environ, allocator: Allocator) void
```


### Error Sets

- **`Error`**
  

### Constants & Variables

- **`empty`**: 

### `NullFile`


### `RandomFile`


### `PipeFile`


### `Pid`


### `UseSendfile`


### Constants & Variables

- **`default`**: 
- **`default`**: 

### `UseCopyFileRange`


### Constants & Variables

- **`default`**: 
- **`default`**: 

### `UseFcopyfile`


### Constants & Variables

- **`default`**: 
- **`default`**: 

### `UseFchmodat2`


### Constants & Variables

- **`default`**: 
- **`default`**: 

### `InitOptions`


### Fields

- `stack_size: usize = std.Thread.SpawnConfig.default_stack_size`
  Affects how many bytes are memory-mapped for threads.
- `async_limit: ?Io.Limit = null`
  Maximum thread pool size (excluding main thread) when dispatching async
  tasks. Until this limit, calls to `Io.async` when all threads are busy will
  cause a new thread to be spawned and permanently added to the pool. After
  this limit, calls to `Io.async` when all threads are busy run the task
  immediately.
  
  Defaults to one less than the number of logical CPU cores.
  
  Protected by `Threaded.mutex` once the I/O instance is already in use. See
  `setAsyncLimit`.
- `concurrent_limit: Io.Limit = .unlimited`
  Maximum thread pool size (excluding main thread) for dispatching concurrent
  tasks. Until this limit, calls to `Io.concurrent` will increase the thread
  pool size.
  
  After this number, calls to `Io.concurrent` return `error.ConcurrencyUnavailable`.
- `argv0: Argv0 = .empty`
  Affects the following operations:
  * `processExecutablePath` on OpenBSD and Haiku.
- `environ: process.Environ = .empty`
  Affects the following operations:
  * `fileIsTty`
  * `processExecutablePath` on OpenBSD and Haiku (observes "PATH").
  * `processSpawn`, `processSpawnPath`, `processReplace`, `processReplacePath`
- `disable_memory_mapping: bool = false`
  If set to `true`, `File.MemoryMap` APIs will always take the fallback path.

### `GetFinalPathNameByHandleFormat`

Specifies how to format volume path in the result of `GetFinalPathNameByHandle`.
Defaults to DOS volume names.

### Fields

- `volume_name: enum { Dos, Nt, } = .Dos`
  

### `WindowsPathSpace`


### Fields

- `data: [windows.PATH_MAX_WIDE:0]u16`
  
- `len: usize`
  

### Functions

#### `span`

```zig
pub fn span(wps: *const WindowsPathSpace) [:0]const u16
```


#### `string`

```zig
pub fn string(wps: *const WindowsPathSpace) windows.UNICODE_STRING
```


### `PosixAddress`


### Fields

- `any: posix.sockaddr`
  
- `in: posix.sockaddr.in`
  
- `in6: posix.sockaddr.in6`
  

### `posixSocketModeProtocol`

```zig
pub fn posixSocketModeProtocol(family: posix.sa_family_t, mode: net.Socket.Mode, protocol: ?net.Protocol) !struct { u32, u32 }
```


### `CreatePipeOptions`


### Fields

- `server: End`
  
- `client: End`
  
- `inbound: bool = false`
  
- `outbound: bool = false`
  
- `maximum_instances: u32 = 1`
  
- `quota: u32 = 4096`
  
- `default_timeout: windows.LARGE_INTEGER = -120 * std.time.ns_per_s / 100`
  

### Types

#### `End`


## Functions

### `waitForApcOrAlert`

```zig
pub fn waitForApcOrAlert() void
```


### `init`

```zig
pub fn init(gpa: Allocator, options: InitOptions, ) Threaded
```

Related:
* `init_single_threaded`

### `setAsyncLimit`

```zig
pub fn setAsyncLimit(t: *Threaded, new_limit: Io.Limit) void
```


### `deinit`

```zig
pub fn deinit(t: *Threaded) void
```


### `io`

```zig
pub fn io(t: *Threaded) Io
```


### `dirOpenFileWtf16`

```zig
pub fn dirOpenFileWtf16(dir_handle: ?windows.HANDLE, sub_path_w: []const u16, flags: Dir.OpenFileOptions, ) File.OpenError!File
```


### `dirOpenDirWindows`

```zig
pub fn dirOpenDirWindows(dir: Dir, sub_path_w: []const u16, options: Dir.OpenOptions, ) Dir.OpenError!Dir
```


### `GetFinalPathNameByHandle`

```zig
pub fn GetFinalPathNameByHandle(hFile: windows.HANDLE, fmt: GetFinalPathNameByHandleFormat, out_buffer: []u16, ) GetFinalPathNameByHandleError![]u16
```

Returns canonical (normalized) path of handle.
Use `GetFinalPathNameByHandleFormat` to specify whether the path is meant to include
NT or DOS volume name (e.g., `\Device\HarddiskVolume0\foo.txt` versus `C:\foo.txt`).
If DOS volume name format is selected, note that this function does *not* prepend
`\\?\` prefix to the resultant path.

### `QueryObjectName`

```zig
pub fn QueryObjectName(handle: windows.HANDLE, out_buffer: []u16) QueryObjectNameError![]u16
```


### `wToPrefixedFileW`

```zig
pub fn wToPrefixedFileW(dir: ?windows.HANDLE, path: [:0]const u16, options: Wtf16ToPrefixedFileWOptions) Wtf16ToPrefixedFileWError!WindowsPathSpace
```

Converts the `path` to WTF16, null-terminated. If the path contains any
namespace prefix, or is anything but a relative path (rooted, drive relative,
etc) the result will have the NT-style prefix `\??\`.

Similar to RtlDosPathNameToNtPathName_U with a few differences:
- Does not allocate on the heap.
- Relative paths are kept as relative unless they contain too many ..
  components, in which case they are resolved against the `dir` if it
  is non-null, or the CWD if it is null.
- Special case device names like COM1, NUL, etc are not handled specially (TODO)
- . and space are not stripped from the end of relative paths (potential TODO)

### `sliceToPrefixedFileW`

```zig
pub fn sliceToPrefixedFileW(dir: ?windows.HANDLE, path: []const u8, options: Wtf16ToPrefixedFileWOptions) Wtf8ToPrefixedFileWError!WindowsPathSpace
```

Same as `wToPrefixedFileW` but accepts a WTF-8 encoded path.
https://wtf-8.codeberg.page/

### `posixAddressFamily`

```zig
pub fn posixAddressFamily(a: *const IpAddress) posix.sa_family_t
```


### `addressFromPosix`

```zig
pub fn addressFromPosix(posix_address: *const PosixAddress) IpAddress
```


### `addressToPosix`

```zig
pub fn addressToPosix(a: *const IpAddress, storage: *PosixAddress) posix.socklen_t
```


### `errnoBug`

```zig
pub fn errnoBug(err: posix.E) Io.UnexpectedError
```


### `recoverableOsBugDetected`

```zig
pub fn recoverableOsBugDetected() void
```


### `clockToPosix`

```zig
pub fn clockToPosix(clock: Io.Clock) posix.clockid_t
```


### `statFromLinux`

```zig
pub fn statFromLinux(stx: *const std.os.linux.Statx) Io.UnexpectedError!File.Stat
```


### `statxKind`

```zig
pub fn statxKind(stx_mode: u16) File.Kind
```


### `statFromPosix`

```zig
pub fn statFromPosix(st: *const posix.Stat) File.Stat
```


### `timestampFromPosix`

```zig
pub fn timestampFromPosix(timespec: *const posix.timespec) Io.Timestamp
```


### `nanosecondsFromPosix`

```zig
pub fn nanosecondsFromPosix(timespec: *const posix.timespec) i96
```


### `setTimestampToPosix`

```zig
pub fn setTimestampToPosix(set_ts: File.SetTimestamp) posix.timespec
```


### `pathToPosix`

```zig
pub fn pathToPosix(file_path: []const u8, buffer: *[posix.PATH_MAX]u8) Dir.PathNameError![:0]u8
```


### `statusToTerm`

```zig
pub fn statusToTerm(status: u32) process.Child.Term
```


### `posixExecveat`

```zig
pub fn posixExecveat(dir: posix.fd_t, path: ?[*:0]const u8, argv: [*:null]const ?[*:0]const u8, env_block: process.Environ.PosixBlock, ) process.ReplaceError
```

This function ignores PATH environment variable.

### `windowsCreatePipe`

```zig
pub fn windowsCreatePipe(t: *Threaded, options: CreatePipeOptions) ![2]windows.HANDLE
```


### `environString`

```zig
pub fn environString(t: *Threaded, comptime name: []const u8) ?[:0]const u8
```


### `fallbackSeed`

```zig
pub fn fallbackSeed(aslr_addr: ?*anyopaque, seed: *[Csprng.seed_len]u8) void
```


### `pipe2`

```zig
pub fn pipe2(flags: posix.O) PipeError![2]posix.fd_t
```


### `dup2`

```zig
pub fn dup2(old_fd: posix.fd_t, new_fd: posix.fd_t) DupError!void
```


### `fchdir`

```zig
pub fn fchdir(fd: posix.fd_t) FchdirError!void
```


### `chdir`

```zig
pub fn chdir(dir_path: []const u8) ChdirError!void
```


### `mutexLock`

```zig
pub fn mutexLock(m: *Io.Mutex) Io.Cancelable!void
```

Same as `Io.Mutex.lock` but avoids the VTable.

### `mutexLockUncancelable`

```zig
pub fn mutexLockUncancelable(m: *Io.Mutex) void
```

Same as `Io.Mutex.lockUncancelable` but avoids the VTable.

### `mutexUnlock`

```zig
pub fn mutexUnlock(m: *Io.Mutex) void
```

Same as `Io.Mutex.unlock` but avoids the VTable.

### `closeFd`

```zig
pub fn closeFd(fd: posix.fd_t) void
```


## Error Sets

- **`GetFinalPathNameByHandleError`**
  
- **`QueryObjectNameError`**
  
- **`PipeError`**
  
- **`DupError`**
  
- **`FchdirError`**
  
- **`ChdirError`**
  

## Constants & Variables

- **`apc_align`**: 
- **`max_iovecs_len`**: 
- **`splat_buffer_size`**: 
- **`default_PATH`**: 
- **`init_single_threaded`**: Statically initialize such that calls to `Io.VTable.concurrent` will fail
- **`global_single_threaded`**: In general, the application is responsible for choosing the `Io`
- **`socket_flags_unsupported`**: 
- **`Wtf8ToPrefixedFileWError`**: 
- **`linux_statx_request`**: 
- **`linux_statx_check`**: 

