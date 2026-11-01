# `std.process`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/process.zig`  
> [← Back to Standard Library Index](README.md)

## Types

### `Init`

A standard set of pre-initialized useful APIs for programs to take
advantage of. This is the type of the first parameter of the main function.
Applications wanting more flexibility can accept `Init.Minimal` instead.

Completion of https://github.com/ziglang/zig/issues/24510 will also allow
the second parameter of the main function to be a custom struct that
contain auto-parsed CLI arguments.

### Fields

- `minimal: Minimal`
  `Init` is a superset of `Minimal`; the latter is included here.
- `arena: *std.heap.ArenaAllocator`
  Permanent storage for the entire process, cleaned automatically on
  exit. Threadsafe.
- `gpa: Allocator`
  A default-selected general purpose allocator for temporary heap
  allocations. Debug mode will set up leak checking if possible.
  Threadsafe.
- `io: Io`
  An appropriate default Io implementation based on the target
  configuration. Debug mode will set up leak checking if possible.
- `environ_map: *Environ.Map`
  Environment variables, initialized with `gpa`. Not threadsafe.
- `preopens: Preopens`
  Named files that have been provided by the parent process. This is
  mainly useful on WASI, but can be used on other systems to mimic the
  behavior with respect to stdio.

### Types

#### `Minimal`

Alternative to `Init` as the first parameter of the main function.

### `UserInfo`


### Fields

- `uid: posix.uid_t`
  
- `gid: posix.gid_t`
  

### `ReplaceOptions`


### Fields

- `exe: Exe = .detect`
  
- `argv: []const []const u8`
  
- `cwd: Child.Cwd = .inherit`
  Set to change the current working directory when spawning the child process.
- `environ_map: ?*const Environ.Map = null`
  Replaces the environment when provided. The PATH value from here is
  never used to resolve `argv[0]`.
- `expand_arg0: ArgExpansion = .no_expand`
  
- `inherit_dirs: []const Dir = &.{}`
  
- `inherit_files: []const File = &.{}`
  
- `start_suspended: bool = false`
  Start child process in suspended state.
  For Posix systems it's started as if SIGSTOP was sent.

### Types

#### `Exe`


### `ArgExpansion`


### Fields

- `expand`
  
- `no_expand`
  

### `WindowsExtension`

File name extensions supported natively by `CreateProcess()` on Windows.

### Fields

- `bat`
  
- `cmd`
  
- `com`
  
- `exe`
  

### Constants & Variables

- **`max_len`**: Length of the longest supported extension (in ASCII characters)

### `SpawnOptions`


### Fields

- `exe: ReplaceOptions.Exe = .detect`
  
- `argv: []const []const u8`
  
- `cwd: Child.Cwd = .inherit`
  Set to change the current working directory when spawning the child process.
- `environ_map: ?*const Environ.Map = null`
  Replaces the child environment when provided. The PATH value from here
  is not used to resolve `argv[0]`; that resolution always uses parent
  environment.
- `expand_arg0: ArgExpansion = .no_expand`
  
- `progress_node: std.Progress.Node = .none`
  When populated, a pipe will be created for the child process to
  communicate progress back to the parent. The file descriptor of the
  write end of the pipe will be specified in the `ZIG_PROGRESS`
  environment variable inside the child process. The progress reported by
  the child will be attached to this progress node in the parent process.
  
  The child's progress tree will be grafted into the parent's progress tree,
  by substituting this node with the child's root node.
- `stdin: StdIo = .inherit`
  
- `stdout: StdIo = .inherit`
  
- `stderr: StdIo = .inherit`
  
- `inherit_dirs: []const Dir = &.{}`
  
- `inherit_files: []const File = &.{}`
  
- `request_resource_usage_statistics: bool = false`
  Set to true to obtain rusage information for the child process.
  Depending on the target platform and implementation status, the
  requested statistics may or may not be available. If they are
  available, then the `resource_usage_statistics` field will be populated
  after calling `wait`.
  On Linux and Darwin, this obtains rusage statistics from wait4().
- `uid: ?posix.uid_t = null`
  Set to change the user id when spawning the child process.
- `gid: ?posix.gid_t = null`
  Set to change the group id when spawning the child process.
- `pgid: ?posix.pid_t = null`
  Set to change the process group id when spawning the child process.
- `start_suspended: bool = false`
  Start child process in suspended state.
  For Posix systems it's started as if SIGSTOP was sent.
- `create_no_window: bool = false`
  Windows-only. Sets the CREATE_NO_WINDOW flag in CreateProcess.

### Types

#### `StdIo`

Behavior of the child process's standard input, output, and error streams.

### `RunOptions`


### Fields

- `exe: ReplaceOptions.Exe = .detect`
  
- `argv: []const []const u8`
  
- `stderr_limit: Io.Limit = .unlimited`
  
- `stdout_limit: Io.Limit = .unlimited`
  
- `reserve_amount: usize = 64`
  How many bytes to initially allocate for stderr and stdout.
- `cwd: Child.Cwd = .inherit`
  Set to change the current working directory when spawning the child process.
- `environ_map: ?*const Environ.Map = null`
  Replaces the child environment when provided. The PATH value from here
  is not used to resolve `argv[0]`; that resolution always uses parent
  environment.
- `expand_arg0: ArgExpansion = .no_expand`
  
- `progress_node: std.Progress.Node = std.Progress.Node.none`
  When populated, a pipe will be created for the child process to
  communicate progress back to the parent. The file descriptor of the
  write end of the pipe will be specified in the `ZIG_PROGRESS`
  environment variable inside the child process. The progress reported by
  the child will be attached to this progress node in the parent process.
  
  The child's progress tree will be grafted into the parent's progress tree,
  by substituting this node with the child's root node.
- `create_no_window: bool = true`
  Windows-only. Sets the CREATE_NO_WINDOW flag in CreateProcess.
- `timeout: Io.Timeout = .none`
  

### `RunResult`


### Fields

- `term: Child.Term`
  
- `stdout: []u8`
  
- `stderr: []u8`
  

### `LockMemoryOptions`


### Fields

- `on_fault: bool = false`
  Lock pages that are currently resident and mark the entire range so
  that the remaining nonresident pages are locked when they are populated
  by a page fault.

### `LockMemoryAllOptions`


### Fields

- `current: bool = false`
  
- `future: bool = false`
  
- `on_fault: bool = false`
  Asserted to be used together with `current` or `future`, or both.

### `MemoryProtection`


### Fields

- `read: bool = false`
  
- `write: bool = false`
  
- `execute: bool = false`
  

## Functions

### `currentPath`

```zig
pub fn currentPath(io: Io, buffer: []u8) CurrentPathError!usize
```

On Windows, the result is encoded as [WTF-8](https://wtf-8.codeberg.page/).
On other platforms, the result is an opaque sequence of bytes with no
particular encoding.

### `currentPathAlloc`

```zig
pub fn currentPathAlloc(io: Io, allocator: Allocator) CurrentPathAllocError![:0]u8
```

Shortcut for calling `currentPath` with a buffer of size `max_path_bytes`.

On Windows, the result is encoded as [WTF-8](https://wtf-8.codeberg.page/).
On other platforms, the result is an opaque sequence of bytes with no
particular encoding.

Caller owns returned memory.

### `getUserInfo`

```zig
pub fn getUserInfo(io: Io, name: []const u8) !UserInfo
```

POSIX function which gets a uid from username.

### `posixGetUserInfo`

```zig
pub fn posixGetUserInfo(io: Io, name: []const u8) !UserInfo
```

TODO this reads /etc/passwd. But sometimes the user/id mapping is in something else
like NIS, AD, etc. See `man nss` or look at an strace for `id myuser`.

### `getBaseAddress`

```zig
pub fn getBaseAddress() usize
```


### `replace`

```zig
pub fn replace(io: Io, options: ReplaceOptions) ReplaceError
```

Replaces the current process image with the executed process. If this
function succeeds, it does not return.

It is illegal to call this function in a fork() child.

### `spawn`

```zig
pub fn spawn(io: Io, options: SpawnOptions) SpawnError!Child
```

Creates a child process.

### `run`

```zig
pub fn run(gpa: Allocator, io: Io, options: RunOptions) RunError!RunResult
```

Spawns a child process, waits for it, collecting stdout and stderr, and then returns.
If it succeeds, the caller owns result.stdout and result.stderr memory.

### `totalSystemMemory`

```zig
pub fn totalSystemMemory() TotalSystemMemoryError!u64
```

Returns the total system memory, in bytes as a u64.
We return a u64 instead of usize due to PAE on ARM
and Linux's /proc/meminfo reporting more memory when
using QEMU user mode emulation.

### `cleanExit`

```zig
pub fn cleanExit(io: Io) void
```

Indicate intent to terminate with a successful exit code.

In debug builds, this is a no-op, so that the calling code's cleanup
mechanisms are tested and so that external tools checking for resource
leaks can be accurate. In release builds, this calls `exit` with code zero,
and does not return.

### `raiseFileDescriptorLimit`

```zig
pub fn raiseFileDescriptorLimit() void
```

Request ability to have more open file descriptors simultaneously.

On some systems, this raises the limit before seeing ProcessFdQuotaExceeded
errors. On other systems, this does nothing.

### `fatal`

```zig
pub fn fatal(comptime format: []const u8, format_arguments: anytype) noreturn
```

Logs an error and then terminates the process with exit code 1.

### `executablePathAlloc`

```zig
pub fn executablePathAlloc(io: Io, allocator: Allocator) ExecutablePathAllocError![:0]u8
```


### `executablePath`

```zig
pub fn executablePath(io: Io, out_buffer: []u8) ExecutablePathError!usize
```

Get the path to the current executable, following symlinks.

This function may return an error if the current executable
was deleted after spawning.

Returned value is a slice of out_buffer.

On Windows, the result is encoded as [WTF-8](https://wtf-8.codeberg.page/).
On other platforms, the result is an opaque sequence of bytes with no particular encoding.

On Linux, depends on procfs being mounted. If the currently executing binary has
been deleted, the file path looks something like "/a/b/c/exe (deleted)".

See also:
* `executableDirPath` - to obtain only the directory
* `openExecutable` - to obtain only an open file handle

### `executableDirPath`

```zig
pub fn executableDirPath(io: Io, out_buffer: []u8) ExecutablePathError!usize
```

Get the directory path that contains the current executable.

Returns index into `out_buffer`.

On Windows, the result is encoded as [WTF-8](https://wtf-8.codeberg.page/).
On other platforms, the result is an opaque sequence of bytes with no particular encoding.

### `executableDirPathAlloc`

```zig
pub fn executableDirPathAlloc(io: Io, allocator: Allocator) ExecutablePathAllocError![]u8
```

Same as `executableDirPath` except allocates the result.

### `openExecutable`

```zig
pub fn openExecutable(io: Io, flags: Dir.OpenFileOptions) OpenExecutableError!File
```


### `abort`

```zig
pub fn abort() noreturn
```

Causes abnormal process termination.

If linking against libc, this calls `std.c.abort`. Otherwise it raises
SIGABRT followed by SIGKILL.

Invokes the current signal handler for SIGABRT, if any.

### `exit`

```zig
pub fn exit(status: u8) noreturn
```

Exits all threads of the program with the specified status code.

### `setCurrentDir`

```zig
pub fn setCurrentDir(io: Io, dir: Io.Dir) !void
```

Changes the current working directory to the open directory handle.
Corresponds to "fchdir" in libc.

This modifies global process state and can have surprising effects in
multithreaded applications. Most applications and especially libraries
should not call this function as a general rule, however it can have use
cases in, for example, implementing a shell, or child process execution.

Calling this function makes code less portable and less reusable.

### `setCurrentPath`

```zig
pub fn setCurrentPath(io: Io, path: []const u8) !void
```

Changes the current working directory to the given path.
Corresponds to "chdir" in libc.

This modifies global process state and can have surprising effects in
multithreaded applications. Most applications and especially libraries
should not call this function as a general rule, however it can have use
cases in, for example, implementing a shell, or child process execution.

Calling this function makes code less portable and less reusable.

### `lockMemory`

```zig
pub fn lockMemory(memory: []align(std.heap.page_size_min) const u8, options: LockMemoryOptions) LockMemoryError!void
```

Request part of the calling process's virtual address space to be in RAM,
preventing that memory from being paged to the swap area.

Corresponds to "mlock" or "mlock2" in libc.

See also:
* unlockMemory

### `unlockMemory`

```zig
pub fn unlockMemory(memory: []align(std.heap.page_size_min) const u8) UnlockMemoryError!void
```

Withdraw request for process's virtual address space to be in RAM.

Corresponds to "munlock" in libc.

See also:
* `lockMemory`

### `lockMemoryAll`

```zig
pub fn lockMemoryAll(options: LockMemoryAllOptions) LockMemoryError!void
```


### `unlockMemoryAll`

```zig
pub fn unlockMemoryAll() UnlockMemoryError!void
```


### `protectMemory`

```zig
pub fn protectMemory(memory: []align(std.heap.page_size_min) u8, protection: MemoryProtection) ProtectMemoryError!void
```


## Error Sets

- **`CurrentPathError`**
  
- **`CurrentPathAllocError`**
  
- **`ReplaceError`**
  
- **`SpawnError`**
  
- **`RunError`**
  
- **`TotalSystemMemoryError`**
  
- **`ExecutablePathBaseError`**
  
- **`ExecutablePathAllocError`**
  
- **`ExecutablePathError`**
  
- **`OpenExecutableError`**
  
- **`SetCurrentDirError`**
  
- **`SetCurrentPathError`**
  
- **`LockMemoryError`**
  
- **`UnlockMemoryError`**
  
- **`ProtectMemoryError`**
  

## Constants & Variables

- **`Child`**: 
- **`Args`**: 
- **`Environ`**: 
- **`Preopens`**: 
- **`can_replace`**: Tells whether the target operating system supports replacing the current
- **`can_spawn`**: Tells whether spawning child processes is supported.

