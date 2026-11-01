# `std.Io`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/Io.zig`  
> [← Back to Standard Library Index](README.md)

A cross-platform interface that abstracts all I/O operations and
concurrency. It includes:
* file system
* networking
* processes
* time and sleeping
* randomness
* async, await, concurrent, and cancel
* concurrent queues
* wait groups and select
* mutexes, futexes, events, and conditions
* memory mapped files
This interface allows programmers to write optimal, reusable code while
participating in these operations.

## Fields

- `userdata: ?*anyopaque`
  
- `vtable: *const VTable`
  

## Types

### `Evented`


### `VTable`


### Fields

- `crashHandler: *const fn (?*anyopaque) void`
  
- `async: *const fn (userdata: ?*anyopaque, result: []u8, result_alignment: std.mem.Alignment, context: []const u8, context_alignment: std.mem.Alignment, start: *const fn (context: *const anyopaque, result: *anyopaque) void, ) ?*AnyFuture`
  If it returns `null` it means `result` has been already populated and
  `await` will be a no-op.
  
  Thread-safe.
- `concurrent: *const fn (userdata: ?*anyopaque, result_len: usize, result_alignment: std.mem.Alignment, context: []const u8, context_alignment: std.mem.Alignment, start: *const fn (context: *const anyopaque, result: *anyopaque) void, ) ConcurrentError!*AnyFuture`
  Thread-safe.
- `await: *const fn (userdata: ?*anyopaque, any_future: *AnyFuture, result: []u8, result_alignment: std.mem.Alignment, ) void`
  This function is only called when `async` returns a non-null value.
  
  Thread-safe.
- `cancel: *const fn (userdata: ?*anyopaque, any_future: *AnyFuture, result: []u8, result_alignment: std.mem.Alignment, ) void`
  Equivalent to `await` but initiates cancel request.
  
  This function is only called when `async` returns a non-null value.
  
  Thread-safe.
- `groupAsync: *const fn (userdata: ?*anyopaque, group: *Group, context: []const u8, context_alignment: std.mem.Alignment, start: *const fn (context: *const anyopaque) void, ) void`
  Thread-safe.
- `groupConcurrent: *const fn (userdata: ?*anyopaque, group: *Group, context: []const u8, context_alignment: std.mem.Alignment, start: *const fn (context: *const anyopaque) void, ) ConcurrentError!void`
  Thread-safe.
- `groupAwait: *const fn (?*anyopaque, *Group, token: *anyopaque) Cancelable!void`
  
- `groupCancel: *const fn (?*anyopaque, *Group, token: *anyopaque) void`
  
- `recancel: *const fn (?*anyopaque) void`
  
- `swapCancelProtection: *const fn (?*anyopaque, new: CancelProtection) CancelProtection`
  
- `checkCancel: *const fn (?*anyopaque) Cancelable!void`
  
- `futexWait: *const fn (?*anyopaque, ptr: *const u32, expected: u32, Timeout) Cancelable!void`
  
- `futexWaitUncancelable: *const fn (?*anyopaque, ptr: *const u32, expected: u32) void`
  
- `futexWake: *const fn (?*anyopaque, ptr: *const u32, max_waiters: u32) void`
  
- `operate: *const fn (?*anyopaque, Operation) Cancelable!Operation.Result`
  
- `batchAwaitAsync: *const fn (?*anyopaque, *Batch) Cancelable!void`
  
- `batchAwaitConcurrent: *const fn (?*anyopaque, *Batch, Timeout) Batch.AwaitConcurrentError!void`
  
- `batchCancel: *const fn (?*anyopaque, *Batch) void`
  
- `dirCreateDir: *const fn (?*anyopaque, Dir, []const u8, Dir.Permissions) Dir.CreateDirError!void`
  
- `dirCreateDirPath: *const fn (?*anyopaque, Dir, []const u8, Dir.Permissions) Dir.CreateDirPathError!Dir.CreatePathStatus`
  
- `dirCreateDirPathOpen: *const fn (?*anyopaque, Dir, []const u8, Dir.Permissions, Dir.OpenOptions) Dir.CreateDirPathOpenError!Dir`
  
- `dirOpenDir: *const fn (?*anyopaque, Dir, []const u8, Dir.OpenOptions) Dir.OpenError!Dir`
  
- `dirStat: *const fn (?*anyopaque, Dir) Dir.StatError!Dir.Stat`
  
- `dirStatFile: *const fn (?*anyopaque, Dir, []const u8, Dir.StatFileOptions) Dir.StatFileError!File.Stat`
  
- `dirAccess: *const fn (?*anyopaque, Dir, []const u8, Dir.AccessOptions) Dir.AccessError!void`
  
- `dirCreateFile: *const fn (?*anyopaque, Dir, []const u8, Dir.CreateFileOptions) File.OpenError!File`
  
- `dirCreateFileAtomic: *const fn (?*anyopaque, Dir, []const u8, Dir.CreateFileAtomicOptions) Dir.CreateFileAtomicError!File.Atomic`
  
- `dirOpenFile: *const fn (?*anyopaque, Dir, []const u8, Dir.OpenFileOptions) File.OpenError!File`
  
- `dirClose: *const fn (?*anyopaque, []const Dir) void`
  
- `dirRead: *const fn (?*anyopaque, *Dir.Reader, []Dir.Entry) Dir.Reader.Error!usize`
  
- `dirRealPath: *const fn (?*anyopaque, Dir, out_buffer: []u8) Dir.RealPathError!usize`
  
- `dirRealPathFile: *const fn (?*anyopaque, Dir, path_name: []const u8, out_buffer: []u8) Dir.RealPathFileError!usize`
  
- `dirDeleteFile: *const fn (?*anyopaque, Dir, []const u8) Dir.DeleteFileError!void`
  
- `dirDeleteDir: *const fn (?*anyopaque, Dir, []const u8) Dir.DeleteDirError!void`
  
- `dirRename: *const fn (?*anyopaque, old_dir: Dir, old_sub_path: []const u8, new_dir: Dir, new_sub_path: []const u8) Dir.RenameError!void`
  
- `dirRenamePreserve: *const fn (?*anyopaque, old_dir: Dir, old_sub_path: []const u8, new_dir: Dir, new_sub_path: []const u8) Dir.RenamePreserveError!void`
  
- `dirSymLink: *const fn (?*anyopaque, Dir, target_path: []const u8, sym_link_path: []const u8, Dir.SymLinkFlags) Dir.SymLinkError!void`
  
- `dirReadLink: *const fn (?*anyopaque, Dir, sub_path: []const u8, buffer: []u8) Dir.ReadLinkError!usize`
  
- `dirSetOwner: *const fn (?*anyopaque, Dir, ?File.Uid, ?File.Gid) Dir.SetOwnerError!void`
  
- `dirSetFileOwner: *const fn (?*anyopaque, Dir, []const u8, ?File.Uid, ?File.Gid, Dir.SetFileOwnerOptions) Dir.SetFileOwnerError!void`
  
- `dirSetPermissions: *const fn (?*anyopaque, Dir, Dir.Permissions) Dir.SetPermissionsError!void`
  
- `dirSetFilePermissions: *const fn (?*anyopaque, Dir, []const u8, File.Permissions, Dir.SetFilePermissionsOptions) Dir.SetFilePermissionsError!void`
  
- `dirSetTimestamps: *const fn (?*anyopaque, Dir, []const u8, Dir.SetTimestampsOptions) Dir.SetTimestampsError!void`
  
- `dirHardLink: *const fn (?*anyopaque, old_dir: Dir, old_sub_path: []const u8, new_dir: Dir, new_sub_path: []const u8, Dir.HardLinkOptions) Dir.HardLinkError!void`
  
- `fileStat: *const fn (?*anyopaque, File) File.StatError!File.Stat`
  
- `fileLength: *const fn (?*anyopaque, File) File.LengthError!u64`
  
- `fileClose: *const fn (?*anyopaque, []const File) void`
  
- `fileWritePositional: *const fn (?*anyopaque, File, header: []const u8, data: []const []const u8, splat: usize, offset: u64) File.WritePositionalError!usize`
  
- `fileWriteFileStreaming: *const fn (?*anyopaque, File, header: []const u8, *Io.File.Reader, Io.Limit) File.Writer.WriteFileError!usize`
  
- `fileWriteFilePositional: *const fn (?*anyopaque, File, header: []const u8, *Io.File.Reader, Io.Limit, offset: u64) File.WriteFilePositionalError!usize`
  
- `fileReadPositional: *const fn (?*anyopaque, File, data: []const []u8, offset: u64) File.ReadPositionalError!usize`
  Returns 0 if reading at or past the end.
- `fileSeekBy: *const fn (?*anyopaque, File, relative_offset: i64) File.SeekError!void`
  
- `fileSeekTo: *const fn (?*anyopaque, File, absolute_offset: u64) File.SeekError!void`
  
- `fileSync: *const fn (?*anyopaque, File) File.SyncError!void`
  
- `fileIsTty: *const fn (?*anyopaque, File) Cancelable!bool`
  
- `fileEnableAnsiEscapeCodes: *const fn (?*anyopaque, File) File.EnableAnsiEscapeCodesError!void`
  
- `fileSupportsAnsiEscapeCodes: *const fn (?*anyopaque, File) Cancelable!bool`
  
- `fileSetLength: *const fn (?*anyopaque, File, u64) File.SetLengthError!void`
  
- `fileSetOwner: *const fn (?*anyopaque, File, ?File.Uid, ?File.Gid) File.SetOwnerError!void`
  
- `fileSetPermissions: *const fn (?*anyopaque, File, File.Permissions) File.SetPermissionsError!void`
  
- `fileSetTimestamps: *const fn (?*anyopaque, File, File.SetTimestampsOptions) File.SetTimestampsError!void`
  
- `fileLock: *const fn (?*anyopaque, File, File.Lock) File.LockError!void`
  
- `fileTryLock: *const fn (?*anyopaque, File, File.Lock) File.LockError!bool`
  
- `fileUnlock: *const fn (?*anyopaque, File) void`
  
- `fileDowngradeLock: *const fn (?*anyopaque, File) File.DowngradeLockError!void`
  
- `fileRealPath: *const fn (?*anyopaque, File, out_buffer: []u8) File.RealPathError!usize`
  
- `fileHardLink: *const fn (?*anyopaque, File, Dir, []const u8, File.HardLinkOptions) File.HardLinkError!void`
  
- `fileMemoryMapCreate: *const fn (?*anyopaque, File, File.MemoryMap.CreateOptions) File.MemoryMap.CreateError!File.MemoryMap`
  
- `fileMemoryMapDestroy: *const fn (?*anyopaque, *File.MemoryMap) void`
  
- `fileMemoryMapSetLength: *const fn (?*anyopaque, *File.MemoryMap, usize) File.MemoryMap.SetLengthError!void`
  
- `fileMemoryMapRead: *const fn (?*anyopaque, *File.MemoryMap) File.ReadPositionalError!void`
  
- `fileMemoryMapWrite: *const fn (?*anyopaque, *File.MemoryMap) File.WritePositionalError!void`
  
- `processExecutableOpen: *const fn (?*anyopaque, Dir.OpenFileOptions) std.process.OpenExecutableError!File`
  
- `processExecutablePath: *const fn (?*anyopaque, buffer: []u8) std.process.ExecutablePathError!usize`
  
- `lockStderr: *const fn (?*anyopaque, ?Terminal.Mode) Cancelable!LockedStderr`
  
- `tryLockStderr: *const fn (?*anyopaque, ?Terminal.Mode) Cancelable!?LockedStderr`
  
- `unlockStderr: *const fn (?*anyopaque) void`
  
- `processCurrentPath: *const fn (?*anyopaque, buffer: []u8) std.process.CurrentPathError!usize`
  
- `processSetCurrentDir: *const fn (?*anyopaque, Dir) std.process.SetCurrentDirError!void`
  
- `processSetCurrentPath: *const fn (?*anyopaque, []const u8) std.process.SetCurrentPathError!void`
  
- `processReplace: *const fn (?*anyopaque, std.process.ReplaceOptions) std.process.ReplaceError`
  
- `processSpawn: *const fn (?*anyopaque, std.process.SpawnOptions) std.process.SpawnError!std.process.Child`
  
- `childWait: *const fn (?*anyopaque, *std.process.Child) std.process.Child.WaitError!std.process.Child.Term`
  
- `childKill: *const fn (?*anyopaque, *std.process.Child) void`
  
- `progressParentFile: *const fn (?*anyopaque) std.Progress.ParentFileError!File`
  
- `inheritParentDir: *const fn (?*anyopaque, handle: Dir.Handle) InheritParentHandleError!Dir`
  
- `inheritParentFile: *const fn (?*anyopaque, handle: File.Handle, flags: File.Flags) InheritParentHandleError!File`
  
- `now: *const fn (?*anyopaque, Clock) Timestamp`
  
- `clockResolution: *const fn (?*anyopaque, Clock) Clock.ResolutionError!Duration`
  
- `sleep: *const fn (?*anyopaque, Timeout) Cancelable!void`
  
- `random: *const fn (?*anyopaque, buffer: []u8) void`
  
- `randomSecure: *const fn (?*anyopaque, buffer: []u8) RandomSecureError!void`
  
- `netListenIp: *const fn (?*anyopaque, address: *const net.IpAddress, net.IpAddress.ListenOptions) net.IpAddress.ListenError!net.Socket`
  
- `netAccept: *const fn (?*anyopaque, server: net.Socket.Handle, options: net.Server.AcceptOptions) net.Server.AcceptError!net.Socket`
  
- `netBindIp: *const fn (?*anyopaque, address: *const net.IpAddress, options: net.IpAddress.BindOptions) net.IpAddress.BindError!net.Socket`
  
- `netConnectIp: *const fn (?*anyopaque, address: *const net.IpAddress, options: net.IpAddress.ConnectOptions) net.IpAddress.ConnectError!net.Socket`
  
- `netListenUnix: *const fn (?*anyopaque, *const net.UnixAddress, net.UnixAddress.ListenOptions) net.UnixAddress.ListenError!net.Socket.Handle`
  
- `netConnectUnix: *const fn (?*anyopaque, *const net.UnixAddress) net.UnixAddress.ConnectError!net.Socket.Handle`
  
- `netSocketCreatePair: *const fn (?*anyopaque, net.Socket.CreatePairOptions) net.Socket.CreatePairError![2]net.Socket`
  
- `netWriteFile: *const fn (?*anyopaque, net.Socket.Handle, header: []const u8, *Io.File.Reader, Io.Limit) net.Stream.Writer.WriteFileError!usize`
  
- `netClose: *const fn (?*anyopaque, sockets: []const net.Socket) void`
  
- `netShutdown: *const fn (?*anyopaque, handle: net.Socket.Handle, how: net.ShutdownHow) net.ShutdownError!void`
  
- `netInterfaceNameResolve: *const fn (?*anyopaque, *const net.Interface.Name) net.Interface.Name.ResolveError!net.Interface`
  
- `netInterfaceName: *const fn (?*anyopaque, net.Interface) net.Interface.NameError!net.Interface.Name`
  
- `netLookup: *const fn (?*anyopaque, net.HostName, *Queue(net.HostName.LookupResult), net.HostName.LookupOptions) net.HostName.LookupError!void`
  

### `Operation`


### Fields

- `file_read_streaming: FileReadStreaming`
  
- `file_write_streaming: FileWriteStreaming`
  
- `device_io_control: DeviceIoControl`
  On Windows this is NtDeviceIoControlFile. On POSIX this is ioctl. On
  other systems this tag is unreachable.
- `net_receive: NetReceive`
  
- `net_send: NetSend`
  
- `net_read: NetRead`
  
- `net_write: NetWrite`
  

### Types

#### `FileReadStreaming`

May return 0 reads which is different than `error.EndOfStream`.

#### `FileWriteStreaming`


#### `DeviceIoControl`


#### `NetReceive`


#### `NetSend`


#### `NetRead`


#### `NetWrite`


#### `Storage`


#### `OptionalIndex`


#### `List`


### Constants & Variables

- **`Tag`**: 
- **`Result`**: 

### `Batch`

Submits many operations together without waiting for all of them to
complete.

This is a low-level abstraction based on `Operation`. For a higher
level API that operates on `Future`, see `Select` and `Group`.

### Fields

- `storage: []Operation.Storage`
  
- `unused: Operation.List`
  
- `submitted: Operation.List`
  
- `pending: Operation.List`
  
- `completed: Operation.List`
  
- `userdata: ?*anyopaque align(@max(@alignOf(?*anyopaque), 4))`
  

### Types

#### `Completion`


### Functions

#### `init`

```zig
pub fn init(storage: []Operation.Storage) Batch
```

After calling this, it is safe to unconditionally defer a call to
`cancel`. `storage` is a pre-allocated buffer of undefined memory that
determines the maximum number of active operations that can be
submitted via `add` and `addAt`.

#### `add`

```zig
pub fn add(batch: *Batch, operation: Operation) u32
```

Adds an operation to be performed at the next await call.
Returns the index that will be returned by `next` after the operation completes.
Asserts that no more than `storage.len` operations are active at a time.

#### `addAt`

```zig
pub fn addAt(batch: *Batch, index: u32, operation: Operation) void
```

Adds an operation to be performed at the next await call.
After the operation completes, `next` will return `index`.
Asserts that the operation at `index` is not active.

#### `next`

```zig
pub fn next(batch: *Batch) ?Completion
```

After calling `awaitAsync`, `awaitConcurrent`, or `cancel`, this
function iterates over the completed operations.

Each completion returned from this function dequeues from the `Batch`.
It is not required to dequeue all completions before awaiting again.

#### `awaitAsync`

```zig
pub fn awaitAsync(batch: *Batch, io: Io) Cancelable!void
```

Waits for at least one of the submitted operations to complete. After
this function returns the completed operations can be iterated with
`next`.

This function provides opportunity for the implementation to introduce
concurrency into the batched operations, but unlike `awaitConcurrent`,
does not require it, and therefore cannot fail with
`error.ConcurrencyUnavailable`.

#### `awaitConcurrent`

```zig
pub fn awaitConcurrent(batch: *Batch, io: Io, timeout: Timeout) AwaitConcurrentError!void
```

Waits for at least one of the submitted operations to complete. After
this function returns the completed operations can be iterated with
`next`.

Unlike `awaitAsync`, this function requires the implementation to
perform the operations concurrently and therefore can fail with
`error.ConcurrencyUnavailable`.

#### `cancel`

```zig
pub fn cancel(batch: *Batch, io: Io) void
```

Requests all pending operations to be interrupted, then waits for all
pending operations to complete. After this returns, the `Batch` is in a
well-defined state, ready to be iterated with `next`. Successfully
canceled operations will be absent from the iteration. Some operations
may have successfully completed regardless of the cancel request and
will appear in the iteration.

### Error Sets

- **`AwaitConcurrentError`**
  

### `Limit`


### Fields

- `nothing = 0`
  
- `unlimited = math.maxInt(usize)`
  
- `_`
  

### Functions

#### `limited`

```zig
pub fn limited(n: usize) Limit
```

`math.maxInt(usize)` is interpreted to mean `.unlimited`.

#### `limited64`

```zig
pub fn limited64(n: u64) Limit
```

Any value grater than `math.maxInt(usize)` is interpreted to mean
`.unlimited`.

#### `countVec`

```zig
pub fn countVec(data: []const []const u8) Limit
```


#### `min`

```zig
pub fn min(a: Limit, b: Limit) Limit
```


#### `max`

```zig
pub fn max(a: Limit, b: Limit) Limit
```


#### `minInt`

```zig
pub fn minInt(l: Limit, n: usize) usize
```


#### `minInt64`

```zig
pub fn minInt64(l: Limit, n: u64) usize
```


#### `slice`

```zig
pub fn slice(l: Limit, s: []u8) []u8
```


#### `sliceConst`

```zig
pub fn sliceConst(l: Limit, s: []const u8) []const u8
```


#### `toInt`

```zig
pub fn toInt(l: Limit) ?usize
```


#### `toInt64`

```zig
pub fn toInt64(l: Limit) ?u64
```


#### `slice1`

```zig
pub fn slice1(l: Limit, non_empty_buffer: []u8) []u8
```

Reduces a slice to account for the limit, leaving room for one extra
byte above the limit, allowing for the use case of differentiating
between end-of-stream and reaching the limit.

#### `nonzero`

```zig
pub fn nonzero(l: Limit) bool
```


#### `subtract`

```zig
pub fn subtract(l: Limit, amount: usize) ?Limit
```

Return a new limit reduced by `amount` or return `null` indicating
limit would be exceeded.

### `Clock`


### Fields

- `real`
  A settable system-wide clock that measures real (i.e. wall-clock)
  time. This clock is affected by discontinuous jumps in the system
  time (e.g., if the system administrator manually changes the
  clock), and by frequency adjustments performed by NTP and similar
  applications.
  
  This clock normally counts the number of seconds since 1970-01-01
  00:00:00 Coordinated Universal Time (UTC) except that it ignores
  leap seconds; near a leap second it is typically adjusted by NTP to
  stay roughly in sync with UTC.
  
  Timestamps returned by implementations of this clock represent time
  elapsed since 1970-01-01T00:00:00Z, the POSIX/Unix epoch, ignoring
  leap seconds. This is colloquially known as "Unix time". If the
  underlying OS uses a different epoch for native timestamps (e.g.,
  Windows, which uses 1601-01-01) they are translated accordingly.
- `awake`
  A nonsettable system-wide clock that represents time since some
  unspecified point in the past.
  
  Monotonic: Guarantees that the time returned by consecutive calls
  will not go backwards, but successive calls may return identical
  (not-increased) time values.
  
  Not affected by discontinuous jumps in the system time (e.g., if
  the system administrator manually changes the clock), but may be
  affected by frequency adjustments.
  
  This clock expresses intent to **exclude time that the system is
  suspended**. However, implementations may be unable to satisify
  this, and may include that time.
  
  * On Linux, corresponds `CLOCK_MONOTONIC`.
  * On macOS, corresponds to `CLOCK_UPTIME_RAW`.
- `boot`
  Identical to `awake` except it expresses intent to **include time
  that the system is suspended**, however, due to limitations it may
  behave identically to `awake`.
  
  * On Linux, corresponds `CLOCK_BOOTTIME`.
  * On macOS, corresponds to `CLOCK_MONOTONIC_RAW`.
- `cpu_process`
  Tracks the amount of CPU time in user or kernel mode used by the calling
  process.
- `cpu_thread`
  Tracks the amount of CPU time in user or kernel mode used by the calling
  thread.

### Types

#### `Timestamp`


#### `Duration`


### Functions

#### `now`

```zig
pub fn now(clock: Clock, io: Io) Io.Timestamp
```

This function is not cancelable because it does not block.

Resolution is determined by `resolution` which may be 0 if the
clock is unsupported.

See also:
* `Clock.Timestamp.now`

#### `resolution`

```zig
pub fn resolution(clock: Clock, io: Io) ResolutionError!Io.Duration
```

Reveals the granularity of `clock`. May be zero, indicating
unsupported clock.

### Error Sets

- **`ResolutionError`**
  

### `Timestamp`


### Fields

- `nanoseconds: i96`
  

### Functions

#### `now`

```zig
pub fn now(io: Io, clock: Clock) Io.Timestamp
```


#### `durationTo`

```zig
pub fn durationTo(from: Timestamp, to: Timestamp) Duration
```


#### `addDuration`

```zig
pub fn addDuration(from: Timestamp, duration: Duration) Timestamp
```


#### `subDuration`

```zig
pub fn subDuration(from: Timestamp, duration: Duration) Timestamp
```


#### `withClock`

```zig
pub fn withClock(t: Timestamp, clock: Clock) Clock.Timestamp
```


#### `fromNanoseconds`

```zig
pub fn fromNanoseconds(x: i96) Timestamp
```


#### `toMicroseconds`

```zig
pub fn toMicroseconds(t: Timestamp) i64
```


#### `toMilliseconds`

```zig
pub fn toMilliseconds(t: Timestamp) i64
```


#### `toSeconds`

```zig
pub fn toSeconds(t: Timestamp) i64
```


#### `toNanoseconds`

```zig
pub fn toNanoseconds(t: Timestamp) i96
```


#### `formatNumber`

```zig
pub fn formatNumber(t: Timestamp, w: *std.Io.Writer, n: std.fmt.Number) std.Io.Writer.Error!void
```


#### `untilNow`

```zig
pub fn untilNow(t: Timestamp, io: Io, clock: Clock) Duration
```

Resolution is determined by `Clock.resolution` which may be 0 if
the clock is unsupported.

#### `compare`

```zig
pub fn compare(lhs: Timestamp, op: math.CompareOperator, rhs: Timestamp) bool
```


### Constants & Variables

- **`zero`**: 

### `Duration`


### Fields

- `nanoseconds: i96`
  

### Functions

#### `fromNanoseconds`

```zig
pub fn fromNanoseconds(x: i96) Duration
```


#### `fromMicroseconds`

```zig
pub fn fromMicroseconds(x: i64) Duration
```


#### `fromMilliseconds`

```zig
pub fn fromMilliseconds(x: i64) Duration
```


#### `fromSeconds`

```zig
pub fn fromSeconds(x: i64) Duration
```


#### `toMicroseconds`

```zig
pub fn toMicroseconds(d: Duration) i64
```


#### `toMilliseconds`

```zig
pub fn toMilliseconds(d: Duration) i64
```


#### `toSeconds`

```zig
pub fn toSeconds(d: Duration) i64
```


#### `toNanoseconds`

```zig
pub fn toNanoseconds(d: Duration) i96
```


#### `format`

```zig
pub fn format(duration: Duration, w: *Writer) Writer.Error!void
```

Write number of nanoseconds according to its signed magnitude:
`[#y][#w][#d][#h][#m]#[.###][n|u|m]s`

### Constants & Variables

- **`zero`**: 
- **`max`**: 

### `Timeout`

Declares under what conditions an operation should return `error.Timeout`.

### Fields

- `none`
  `.none` will wait forever
- `duration: Clock.Duration`
  
- `deadline: Clock.Timestamp`
  

### Functions

#### `toTimestamp`

```zig
pub fn toTimestamp(t: Timeout, io: Io) ?Clock.Timestamp
```


#### `toDeadline`

```zig
pub fn toDeadline(t: Timeout, io: Io) Timeout
```


#### `toDurationFromNow`

```zig
pub fn toDurationFromNow(t: Timeout, io: Io) ?Clock.Duration
```


#### `sleep`

```zig
pub fn sleep(timeout: Timeout, io: Io) Cancelable!void
```

Waits until the timeout has passed.

See also:
* `Io.sleep`
* `Clock.Duration.sleep`
* `Clock.Timestamp.wait`

### Error Sets

- **`Error`**
  

### `AnyFuture`


### `Future`

```zig
pub fn Future(Result: type) type
```


### Fields

- `any_future: ?*AnyFuture`
  
- `result: Result`
  

### Functions

#### `cancel`

```zig
pub fn cancel(f: *@This(), io: Io) Result
```

Equivalent to `await` but places a cancelation request. This causes the task to receive
`error.Canceled` from its next "cancelation point" (if any). A cancelation point is a
call to a function in `Io` which can return `error.Canceled`.

After cancelation of a task is requested, only the next cancelation point in that task
will return `error.Canceled`: future points will not re-signal the cancelation. As such,
it is usually a bug to ignore `error.Canceled`. However, to defer handling cancelation
requests, see also `recancel` and `CancelProtection`.

Idempotent. Not threadsafe.

#### `await`

```zig
pub fn await(f: *@This(), io: Io) Result
```

Idempotent. Not threadsafe.

### `Group`

An unordered set of tasks which can only be awaited or canceled as a whole.
Tasks are spawned in the group with `Group.async` and `Group.concurrent`.

The resources associated with each task are *guaranteed* to be released when
the individual task returns, as opposed to when the whole group completes or
is awaited. For this reason, it is not a resource leak to have a long-lived
group which concurrent tasks are repeatedly added to. However, asynchronous
tasks are not guaranteed to run until `Group.await` or `Group.cancel` is
called, so adding async tasks to a group without ever awaiting it may leak
resources.

### Fields

- `token: std.atomic.Value(?*anyopaque)`
  This value indicates whether or not a group has pending tasks. `null`
  means there are no pending tasks, and no resources associated with the
  group, so `await` and `cancel` return immediately without calling the
  implementation. This means that `token` must be accessed atomically to
  avoid racing with the check in `await` and `cancel`.
- `state: usize`
  This value is available for the implementation to use as it wishes.

### Functions

#### `async`

```zig
pub fn async(g: *Group, io: Io, function: anytype, args: std.meta.ArgsTuple(@TypeOf(function))) void
```

Equivalent to `Io.async`, except the task is spawned in this `Group`
instead of becoming associated with a `Future`.

The return type of `function` must be coercible to `Cancelable!void`.
`function` returning `error.Canceled` does nothing because it is an
cancelation propagation boundary.

Once this function is called, there are resources associated with the
group. To release those resources, `await` or `cancel` must eventually
be called.

`function` is not guaranteed to have been called until `await` or
`cancel` is called.

#### `concurrent`

```zig
pub fn concurrent(g: *Group, io: Io, function: anytype, args: std.meta.ArgsTuple(@TypeOf(function))) ConcurrentError!void
```

Equivalent to `Io.concurrent`, except the task is spawned in this
`Group` instead of becoming associated with a `Future`.

The return type of `function` must be coercible to `Cancelable!void`.
`function` returning `error.Canceled` does nothing because it is an
cancelation propagation boundary.

Once this function is called, there are resources associated with the
group. To release those resources, `Group.await` or `Group.cancel` must
eventually be called.

#### `await`

```zig
pub fn await(g: *Group, io: Io) Cancelable!void
```

Blocks until all tasks of the group finish. During this time,
cancelation requests propagate to all members of the group, and
will also cause `error.Canceled` to be returned when the group
does ultimately finish.

After this function returns, all tasks of the `Group` created with
`async` or `concurrent` are guaranteed to have run.

Idempotent. Not threadsafe.

It is safe to call this function concurrently with `Group.async` or
`Group.concurrent`, provided that the group does not complete until
the call to `Group.async` or `Group.concurrent` returns.

#### `cancel`

```zig
pub fn cancel(g: *Group, io: Io) void
```

Equivalent to `await` but immediately requests cancelation on all
members of the group.

After this function returns, all tasks of the `Group` created with
`async` or `concurrent` are guaranteed to have run.

For a description of cancelation and cancelation points, see `Future.cancel`.

Idempotent. Not threadsafe.

It is safe to call this function concurrently with `Group.async` or
`Group.concurrent`, provided that the group does not complete until
the call to `Group.async` or `Group.concurrent` returns.

### Constants & Variables

- **`init`**: 

### `CancelProtection`

In rare cases, it is desirable to completely block cancelation notification, so that a region
of code can run uninterrupted before `error.Canceled` is potentially observed. Therefore, every
task has a "cancel protection" state which indicates whether or not `Io` functions can introduce
cancelation points.

To modify a task's cancel protection state, see `swapCancelProtection`.

For a description of cancelation and cancelation points, see `Future.cancel`.

### Fields

- `unblocked = 0`
  Any call to an `Io` function with `error.Canceled` in its error set is a cancelation point.
  
  This is the default state, which all tasks are created in.
- `blocked = 1`
  No `Io` function introduces a cancelation point (`error.Canceled` will never be returned).

### `Select`

```zig
pub fn Select(comptime U: type) type
```

Executes tasks together, providing a mechanism to wait until one or more
tasks complete. Similar to `Batch` but operates at the higher level task
abstraction layer rather than lower level `Operation` abstraction layer.

The provided tagged union will be used as the return type of the await
function. When calling async or concurrent, one specifies which union field
the called function's result will be placed into upon completion.

### Fields

- `io: Io`
  
- `group: Group`
  
- `queue: Queue(U)`
  

### Types

#### `Field`


### Functions

#### `init`

```zig
pub fn init(io: Io, buffer: []U) S
```


#### `async`

```zig
pub fn async(s: *S, comptime field: Field, function: anytype, args: std.meta.ArgsTuple(@TypeOf(function)), ) void
```

Calls `function` with `args` asynchronously. The resource spawned is
owned by the select.

`function` must have return type matching the `field` field of `Union`.

`function` *may* be called immediately, before `async` returns.

When this function returns, it is guaranteed that `function` has
already been called and completed, or it has successfully been
assigned a unit of concurrency.

After this is called, `await` or `cancel` must be called before the
select is deinitialized.

Threadsafe.

Related:
* `Io.async`
* `Group.async`

#### `concurrent`

```zig
pub fn concurrent(s: *S, comptime field: Field, function: anytype, args: std.meta.ArgsTuple(@TypeOf(function)), ) ConcurrentError!void
```

Calls `function` with `args` concurrently. The resource spawned is
owned by the select.

`function` must have return type matching the `field` field of `Union`.

After this function returns successfully, it is guaranteed that
`function` has been assigned a unit of concurrency, and `await` or
`cancel` must be called before the select is deinitialized.


Threadsafe.

Related:
* `Io.concurrent`
* `Group.concurrent`

#### `await`

```zig
pub fn await(s: *S) Cancelable!U
```

Blocks until another task of the select finishes.

It is legal to call `async` and `concurrent` after this.

Threadsafe.

#### `awaitMany`

```zig
pub fn awaitMany(s: *S, buffer: []U, min: usize) Cancelable!usize
```

Blocks until at least `min` number of results have been copied
into `buffer`.

Asserts that `buffer.len >= min`.

It is legal to call `async` and `concurrent` after this.

Threadsafe.

#### `cancel`

```zig
pub fn cancel(s: *S) ?U
```

Requests cancelation on all remaining tasks owned by the select,
then blocks until they all finish. If the select was initialized
with insufficient buffer space for all remaining tasks to finish, a
deadlock occurs.

If any of the select tasks allocate resources, those tasks may have
completed, meaning that this function must be called in a loop
until `null` is returned in order to deallocate those resources. If
there is no possibility of resource leaks, `cancelDiscard` is
preferable.

It is illegal to call `await` or `awaitMany` after this.

It is safe to call this multiple times, even after `null` is
returned.

Threadsafe.

#### `cancelDiscard`

```zig
pub fn cancelDiscard(s: *S) void
```

Requests cancelation on all remaining tasks owned by the select,
then blocks until they all finish.

All return values from outstanding tasks are discarded. This
function is therefore inappropriate to call when a task can return
an allocated resource. For that use case, see `cancel`.

It is illegal to call `await` or `awaitMany` after this.

It is safe to call this multiple times.

Threadsafe.

### Constants & Variables

- **`Union`**: 

### `Mutex`

Mutex is a synchronization primitive which enforces atomic access to a
shared region of code known as the "critical section".

Mutex is an extern struct so that it may be used as a field inside another
extern struct.

### Fields

- `state: std.atomic.Value(State)`
  

### Types

#### `State`


### Functions

#### `tryLock`

```zig
pub fn tryLock(m: *Mutex) bool
```


#### `lock`

```zig
pub fn lock(m: *Mutex, io: Io) Cancelable!void
```


#### `lockUncancelable`

```zig
pub fn lockUncancelable(m: *Mutex, io: Io) void
```

Same as `lock`, except does not introduce a cancelation point.

For a description of cancelation and cancelation points, see `Future.cancel`.

#### `unlock`

```zig
pub fn unlock(m: *Mutex, io: Io) void
```


### Constants & Variables

- **`init`**: 

### `Condition`


### Fields

- `state: std.atomic.Value(State)`
  
- `epoch: std.atomic.Value(u32)`
  Incremented whenever the condition is signaled

### Functions

#### `wait`

```zig
pub fn wait(cond: *Condition, io: Io, mutex: *Mutex) Cancelable!void
```

Blocks until the condition is signaled or canceled.

See also:
* `waitUncancelable`
* `waitTimeout`

#### `waitTimeout`

```zig
pub fn waitTimeout(cond: *Condition, io: Io, mutex: *Mutex, timeout: Timeout) WaitTimeoutError!void
```

Blocks until the condition is signaled, canceled, or the provided
timeout expires.

See also:
* `wait`
* `waitUncancelable`

#### `waitUncancelable`

```zig
pub fn waitUncancelable(cond: *Condition, io: Io, mutex: *Mutex) void
```

Same as `wait`, except does not introduce a cancelation point.

See `Future.cancel` for a description of cancelation points.

#### `signal`

```zig
pub fn signal(cond: *Condition, io: Io) void
```


#### `broadcast`

```zig
pub fn broadcast(cond: *Condition, io: Io) void
```


### Error Sets

- **`WaitTimeoutError`**
  

### Constants & Variables

- **`init`**: 

### `Event`

Logical boolean flag which can be set and unset and supports a "wait until set" operation.

### Fields

- `unset`
  
- `waiting`
  
- `is_set`
  

### Functions

#### `isSet`

```zig
pub fn isSet(event: *const Event) bool
```

Returns whether the logical boolean is `true`.

#### `wait`

```zig
pub fn wait(event: *Event, io: Io) Cancelable!void
```

Blocks until the logical boolean is `true`.

#### `waitUncancelable`

```zig
pub fn waitUncancelable(event: *Event, io: Io) void
```

Same as `wait`, except does not introduce a cancelation point.

For a description of cancelation and cancelation points, see `Future.cancel`.

#### `waitTimeout`

```zig
pub fn waitTimeout(event: *Event, io: Io, timeout: Timeout) WaitTimeoutError!void
```

Blocks the calling thread until either the logical boolean is set, the timeout expires, or a
spurious wakeup occurs. If the timeout expires or a spurious wakeup occurs, `error.Timeout`
is returned.

#### `set`

```zig
pub fn set(e: *Event, io: Io) void
```

Sets the logical boolean to true, and hence unblocks any pending calls to `wait`. The
logical boolean remains true until `reset` is called, so future calls to `set` have no
semantic effect.

Any memory accesses prior to a `set` call are "released", so that if this `set` call causes
`isSet` to return `true` or a wait to finish, those tasks will be able to observe those
memory accesses.

#### `reset`

```zig
pub fn reset(e: *Event) void
```

Sets the logical boolean to false.

Assumes that there is no pending call to `wait` or `waitUncancelable`.

However, concurrent calls to `isSet`, `set`, and `reset` are allowed.

### Error Sets

- **`WaitTimeoutError`**
  

### `TypeErasedQueue`


### Fields

- `mutex: Mutex`
  
- `closed: bool`
  
- `buffer: []u8`
  Ring buffer. This data is logically *after* queued getters.
- `start: usize`
  
- `len: usize`
  
- `putters: std.DoublyLinkedList`
  
- `getters: std.DoublyLinkedList`
  

### Functions

#### `init`

```zig
pub fn init(buffer: []u8) TypeErasedQueue
```


#### `close`

```zig
pub fn close(q: *TypeErasedQueue, io: Io) void
```

After this is called, the queue enters a "closed" state. A closed
queue always returns `error.Closed` for put attempts even when
there is space in the buffer. However, existing elements of the
queue are retrieved before `error.Closed` is returned.

Idempotent. Threadsafe.

#### `put`

```zig
pub fn put(q: *TypeErasedQueue, io: Io, elements: []const u8, min: usize) (QueueClosedError || Cancelable)!usize
```


#### `putUncancelable`

```zig
pub fn putUncancelable(q: *TypeErasedQueue, io: Io, elements: []const u8, min: usize) QueueClosedError!usize
```

Same as `put`, except does not introduce a cancelation point.

For a description of cancelation and cancelation points, see `Future.cancel`.

#### `get`

```zig
pub fn get(q: *TypeErasedQueue, io: Io, buffer: []u8, min: usize) (QueueClosedError || Cancelable)!usize
```


#### `getUncancelable`

```zig
pub fn getUncancelable(q: *TypeErasedQueue, io: Io, buffer: []u8, min: usize) QueueClosedError!usize
```

Same as `get`, except does not introduce a cancelation point.

For a description of cancelation and cancelation points, see `Future.cancel`.

### `Queue`

```zig
pub fn Queue(Elem: type) type
```

Many producer, many consumer, thread-safe, runtime configurable buffer size.
When buffer is empty, consumers suspend and are resumed by producers.
When buffer is full, producers suspend and are resumed by consumers.

### Fields

- `type_erased: TypeErasedQueue`
  

### Functions

#### `init`

```zig
pub fn init(buffer: []Elem) @This()
```


#### `close`

```zig
pub fn close(q: *@This(), io: Io) void
```

After this is called, the queue enters a "closed" state. A closed
queue always returns `error.Closed` for put attempts even when
there is space in the buffer. However, existing elements of the
queue are retrieved before `error.Closed` is returned.

Threadsafe.

#### `put`

```zig
pub fn put(q: *@This(), io: Io, elements: []const Elem, min: usize) (QueueClosedError || Cancelable)!usize
```

Appends elements to the end of the queue, potentially blocking if
there is insufficient capacity. Returns when any one of the
following conditions is satisfied:

* At least `min` elements have been added to the queue
* The queue is closed
* The current task is canceled

Returns how many of `elements` have been added to the queue, if any.
If an error is returned, no elements have been added.

If the queue is closed or the task is canceled, but some items were
already added before the closure or cancelation, then `put` may
return a number lower than `min`, in which case future calls are
guaranteed to return `error.Canceled` or `error.Closed`.

A return value of 0 is only possible if `min` is 0, in which case
the call is guaranteed to queue as many of `elements` as is possible
*without* blocking.

Asserts that `elements.len >= min`.

#### `putAll`

```zig
pub fn putAll(q: *@This(), io: Io, elements: []const Elem) (QueueClosedError || Cancelable)!void
```

Same as `put` but blocks until all elements have been added to the queue.

If the queue is closed or canceled, `error.Closed` or `error.Canceled`
is returned, and it is unspecified how many, if any, of `elements` were
added to the queue prior to cancelation or closure.

#### `putUncancelable`

```zig
pub fn putUncancelable(q: *@This(), io: Io, elements: []const Elem, min: usize) QueueClosedError!usize
```

Same as `put`, except does not introduce a cancelation point.

For a description of cancelation and cancelation points, see `Future.cancel`.

#### `putOne`

```zig
pub fn putOne(q: *@This(), io: Io, item: Elem) (QueueClosedError || Cancelable)!void
```

Appends `item` to the end of the queue, blocking if the queue is full.

#### `putOneUncancelable`

```zig
pub fn putOneUncancelable(q: *@This(), io: Io, item: Elem) QueueClosedError!void
```

Same as `putOne`, except does not introduce a cancelation point.

For a description of cancelation and cancelation points, see `Future.cancel`.

#### `get`

```zig
pub fn get(q: *@This(), io: Io, buffer: []Elem, min: usize) (QueueClosedError || Cancelable)!usize
```

Receives elements from the beginning of the queue, potentially blocking
if there are insufficient elements currently in the queue. Returns when
any one of the following conditions is satisfied:

* At least `min` elements have been received from the queue
* The queue is closed and contains no buffered elements
* The current task is canceled

Returns how many elements of `buffer` have been populated, if any.
If an error is returned, no elements have been populated.

If the queue is closed or the task is canceled, but some items were
already received before the closure or cancelation, then `get` may
return a number lower than `min`, in which case future calls are
guaranteed to return `error.Canceled` or `error.Closed`.

A return value of 0 is only possible if `min` is 0, in which case
the call is guaranteed to fill as much of `buffer` as is possible
*without* blocking.

Asserts that `buffer.len >= min`.

#### `getUncancelable`

```zig
pub fn getUncancelable(q: *@This(), io: Io, buffer: []Elem, min: usize) QueueClosedError!usize
```

Same as `get`, except does not introduce a cancelation point.

For a description of cancelation and cancelation points, see `Future.cancel`.

#### `getOne`

```zig
pub fn getOne(q: *@This(), io: Io) (QueueClosedError || Cancelable)!Elem
```

Receives one element from the beginning of the queue, blocking if the queue is empty.

#### `getOneUncancelable`

```zig
pub fn getOneUncancelable(q: *@This(), io: Io) QueueClosedError!Elem
```

Same as `getOne`, except does not introduce a cancelation point.

For a description of cancelation and cancelation points, see `Future.cancel`.

#### `capacity`

```zig
pub fn capacity(q: *const @This()) usize
```

Returns buffer length in `Elem` units.

### `LockedStderr`


### Fields

- `file_writer: *File.Writer`
  
- `terminal_mode: Terminal.Mode`
  

### Functions

#### `terminal`

```zig
pub fn terminal(ls: LockedStderr) Terminal
```


#### `clear`

```zig
pub fn clear(ls: LockedStderr, buffer: []u8) Cancelable!void
```


## Functions

### `operate`

```zig
pub fn operate(io: Io, operation: Operation) Cancelable!Operation.Result
```

Performs one `Operation`.

### `operateTimeout`

```zig
pub fn operateTimeout(io: Io, operation: Operation, timeout: Timeout) OperateTimeoutError!Operation.Result
```

Performs one `Operation` with provided `timeout`.

### `recancel`

```zig
pub fn recancel(io: Io) void
```

Asserts that `error.Canceled` was returned from a prior cancelation point, and "re-arms" the
cancelation request, so that `error.Canceled` will be returned again from the next cancelation
point.

For a description of cancelation and cancelation points, see `Future.cancel`.

### `swapCancelProtection`

```zig
pub fn swapCancelProtection(io: Io, new: CancelProtection) CancelProtection
```

Updates the current task's cancel protection state (see `CancelProtection`).

The typical usage for this function is to protect a block of code from cancelation:
```
const old_cancel_protect = io.swapCancelProtection(.blocked);
defer _ = io.swapCancelProtection(old_cancel_protect);
doSomeWork() catch |err| switch (err) {
    error.Canceled => unreachable,
};
```

For a description of cancelation and cancelation points, see `Future.cancel`.

### `checkCancel`

```zig
pub fn checkCancel(io: Io) Cancelable!void
```

This function acts as a pure cancelation point (subject to protection; see `CancelProtection`)
and does nothing else. In other words, it returns `error.Canceled` if there is an outstanding
non-blocked cancelation request, but otherwise is a no-op.

It is rarely necessary to call this function. The primary use case is in long-running CPU-bound
tasks which may need to respond to cancelation before completing. Short tasks, or those which
perform other `Io` operations (and hence have other cancelation points), will typically already
respond quickly to cancelation requests.

For a description of cancelation and cancelation points, see `Future.cancel`.

### `futexWait`

```zig
pub fn futexWait(io: Io, comptime T: type, ptr: *align(@alignOf(u32)) const T, expected: T) Cancelable!void
```

Atomically checks if the value at `ptr` equals `expected`, and if so, blocks until either:

* a matching (same `ptr` argument) `futexWake` call occurs, or
* a spurious ("random") wakeup occurs.

Typically, `futexWake` should be called immediately after updating the value at `ptr.*`, to
unblock tasks using `futexWait` to wait for the value to change from what it previously was.

The caller is responsible for identifying spurious wakeups if necessary, typically by checking
the value at `ptr.*`.

Asserts that `T` is 4 bytes in length and has a well-defined layout with no padding bits.

### `futexWaitTimeout`

```zig
pub fn futexWaitTimeout(io: Io, comptime T: type, ptr: *align(@alignOf(u32)) const T, expected: T, timeout: Timeout) Cancelable!void
```

Same as `futexWait`, except also unblocks if `timeout` expires. As with `futexWait`, spurious
wakeups are possible. It remains the caller's responsibility to differentiate between these
three possible wake-up reasons if necessary.

### `futexWaitUncancelable`

```zig
pub fn futexWaitUncancelable(io: Io, comptime T: type, ptr: *align(@alignOf(u32)) const T, expected: T) void
```

Same as `futexWait`, except does not introduce a cancelation point.

For a description of cancelation and cancelation points, see `Future.cancel`.

### `futexWake`

```zig
pub fn futexWake(io: Io, comptime T: type, ptr: *align(@alignOf(u32)) const T, max_waiters: u32) void
```

Unblocks pending futex waits on `ptr`, up to a limit of `max_waiters` calls.

### `async`

```zig
pub fn async(io: Io, function: anytype, args: std.meta.ArgsTuple(@TypeOf(function)), ) Future(@typeInfo(@TypeOf(function)).@"fn".return_type.?)
```

Calls `function` with `args`, such that the return value of the function is
not guaranteed to be available until `await` is called.

`function` *may* be called immediately, before `async` returns. This has
weaker guarantees than `concurrent`, making more portable and reusable.

When this function returns, it is guaranteed that `function` has already
been called and completed, or it has successfully been assigned a unit of
concurrency.

See also:
* `Group`

### `concurrent`

```zig
pub fn concurrent(io: Io, function: anytype, args: std.meta.ArgsTuple(@TypeOf(function)), ) ConcurrentError!Future(@typeInfo(@TypeOf(function)).@"fn".return_type.?)
```

Calls `function` with `args`, such that the return value of the function is
not guaranteed to be available until `await` is called, allowing the caller
to progress while waiting for any `Io` operations.

This has stronger guarantee than `async`, placing restrictions on what kind
of `Io` implementations are supported. By calling `async` instead, one
allows, for example, stackful single-threaded blocking I/O.

### `sleep`

```zig
pub fn sleep(io: Io, duration: Duration, clock: Clock) Cancelable!void
```

Waits until a specified amount of time has passed on `clock`.

See also:
* `Clock.Duration.sleep`
* `Clock.Timestamp.wait`
* `Timeout.sleep`

### `lockStderr`

```zig
pub fn lockStderr(io: Io, buffer: []u8, terminal_mode: ?Terminal.Mode) Cancelable!LockedStderr
```

For doing application-level writes to the standard error stream.
Coordinates also with debug-level writes that are ignorant of Io interface
and implementations.

See also:
* `tryLockStderr`

### `tryLockStderr`

```zig
pub fn tryLockStderr(io: Io, buffer: []u8, terminal_mode: ?Terminal.Mode) Cancelable!?LockedStderr
```

Same as `lockStderr` but non-blocking.

### `unlockStderr`

```zig
pub fn unlockStderr(io: Io) void
```


### `random`

```zig
pub fn random(io: Io, buffer: []u8) void
```

Obtains entropy from a cryptographically secure pseudo-random number
generator.

The implementation *may* store RNG state in process memory and use it to
fill `buffer`.

The randomness is seeded by `randomSecure`, or a less secure mechanism upon
failure.

Threadsafe.

See also `randomSecure`.

### `randomSecure`

```zig
pub fn randomSecure(io: Io, buffer: []u8) RandomSecureError!void
```

Obtains cryptographically secure entropy from outside the process.

Always makes a syscall, or otherwise avoids dependency on process memory,
in order to obtain fresh randomness. Does not rely on stored RNG state.

Does not have any fallback mechanisms; returns `error.EntropyUnavailable`
if any problems occur.

Threadsafe.

See also `random`.

### `noCrashHandler`

```zig
pub fn noCrashHandler(userdata: ?*anyopaque) void
```


### `noAsync`

```zig
pub fn noAsync(userdata: ?*anyopaque, result: []u8, result_alignment: std.mem.Alignment, context: []const u8, context_alignment: std.mem.Alignment, start: *const fn (context: *const anyopaque, result: *anyopaque) void) ?*AnyFuture
```


### `failingConcurrent`

```zig
pub fn failingConcurrent(userdata: ?*anyopaque, result_len: usize, result_alignment: std.mem.Alignment, context: []const u8, context_alignment: std.mem.Alignment, start: *const fn (context: *const anyopaque, result: *anyopaque) void, ) ConcurrentError!*AnyFuture
```


### `unreachableAwait`

```zig
pub fn unreachableAwait(userdata: ?*anyopaque, any_future: *AnyFuture, result: []u8, result_alignment: std.mem.Alignment, ) void
```


### `unreachableCancel`

```zig
pub fn unreachableCancel(userdata: ?*anyopaque, any_future: *AnyFuture, result: []u8, result_alignment: std.mem.Alignment, ) void
```


### `noGroupAsync`

```zig
pub fn noGroupAsync(userdata: ?*anyopaque, group: *Group, context: []const u8, context_alignment: std.mem.Alignment, start: *const fn (context: *const anyopaque) void, ) void
```


### `failingGroupConcurrent`

```zig
pub fn failingGroupConcurrent(userdata: ?*anyopaque, group: *Group, context: []const u8, context_alignment: std.mem.Alignment, start: *const fn (context: *const anyopaque) void, ) ConcurrentError!void
```


### `unreachableGroupAwait`

```zig
pub fn unreachableGroupAwait(userdata: ?*anyopaque, group: *Group, token: *anyopaque) Cancelable!void
```


### `unreachableGroupCancel`

```zig
pub fn unreachableGroupCancel(userdata: ?*anyopaque, group: *Group, token: *anyopaque) void
```


### `unreachableRecancel`

```zig
pub fn unreachableRecancel(userdata: ?*anyopaque) void
```


### `unreachableSwapCancelProtection`

```zig
pub fn unreachableSwapCancelProtection(userdata: ?*anyopaque, new: CancelProtection) CancelProtection
```


### `unreachableCheckCancel`

```zig
pub fn unreachableCheckCancel(userdata: ?*anyopaque) Cancelable!void
```


### `noFutexWait`

```zig
pub fn noFutexWait(userdata: ?*anyopaque, ptr: *const u32, expected: u32, timeout: Timeout) Cancelable!void
```


### `noFutexWaitUncancelable`

```zig
pub fn noFutexWaitUncancelable(userdata: ?*anyopaque, ptr: *const u32, expected: u32) void
```


### `noFutexWake`

```zig
pub fn noFutexWake(userdata: ?*anyopaque, ptr: *const u32, max_waiters: u32) void
```


### `failingOperate`

```zig
pub fn failingOperate(userdata: ?*anyopaque, operation: Operation) Cancelable!Operation.Result
```


### `unreachableBatchAwaitAsync`

```zig
pub fn unreachableBatchAwaitAsync(userdata: ?*anyopaque, b: *Batch) Cancelable!void
```


### `unreachableBatchAwaitConcurrent`

```zig
pub fn unreachableBatchAwaitConcurrent(userdata: ?*anyopaque, b: *Batch, timeout: Timeout) Batch.AwaitConcurrentError!void
```


### `unreachableBatchCancel`

```zig
pub fn unreachableBatchCancel(userdata: ?*anyopaque, b: *Batch) void
```


### `failingDirCreateDir`

```zig
pub fn failingDirCreateDir(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8, permissions: Dir.Permissions) Dir.CreateDirError!void
```


### `failingDirCreateDirPath`

```zig
pub fn failingDirCreateDirPath(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8, permissions: Dir.Permissions) Dir.CreateDirPathError!Dir.CreatePathStatus
```


### `failingDirCreateDirPathOpen`

```zig
pub fn failingDirCreateDirPathOpen(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8, permissions: Dir.Permissions, options: Dir.OpenOptions) Dir.CreateDirPathOpenError!Dir
```


### `failingDirOpenDir`

```zig
pub fn failingDirOpenDir(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8, options: Dir.OpenOptions) Dir.OpenError!Dir
```


### `failingDirStat`

```zig
pub fn failingDirStat(userdata: ?*anyopaque, dir: Dir) Dir.StatError!Dir.Stat
```


### `failingDirStatFile`

```zig
pub fn failingDirStatFile(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8, options: Dir.StatFileOptions) Dir.StatFileError!File.Stat
```


### `failingDirAccess`

```zig
pub fn failingDirAccess(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8, options: Dir.AccessOptions) Dir.AccessError!void
```


### `failingDirCreateFile`

```zig
pub fn failingDirCreateFile(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8, options: Dir.CreateFileOptions) File.OpenError!File
```


### `failingDirCreateFileAtomic`

```zig
pub fn failingDirCreateFileAtomic(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8, options: Dir.CreateFileAtomicOptions) Dir.CreateFileAtomicError!File.Atomic
```


### `failingDirOpenFile`

```zig
pub fn failingDirOpenFile(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8, flags: Dir.OpenFileOptions) File.OpenError!File
```


### `unreachableDirClose`

```zig
pub fn unreachableDirClose(userdata: ?*anyopaque, dirs: []const Dir) void
```


### `noDirRead`

```zig
pub fn noDirRead(userdata: ?*anyopaque, dir_reader: *Dir.Reader, buffer: []Dir.Entry) Dir.Reader.Error!usize
```


### `failingDirRealPath`

```zig
pub fn failingDirRealPath(userdata: ?*anyopaque, dir: Dir, out_buffer: []u8) Dir.RealPathError!usize
```


### `failingDirRealPathFile`

```zig
pub fn failingDirRealPathFile(userdata: ?*anyopaque, dir: Dir, path_name: []const u8, out_buffer: []u8) Dir.RealPathFileError!usize
```


### `failingDirDeleteFile`

```zig
pub fn failingDirDeleteFile(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8) Dir.DeleteFileError!void
```


### `failingDirDeleteDir`

```zig
pub fn failingDirDeleteDir(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8) Dir.DeleteDirError!void
```


### `failingDirRename`

```zig
pub fn failingDirRename(userdata: ?*anyopaque, old_dir: Dir, old_sub_path: []const u8, new_dir: Dir, new_sub_path: []const u8) Dir.RenameError!void
```


### `failingDirRenamePreserve`

```zig
pub fn failingDirRenamePreserve(userdata: ?*anyopaque, old_dir: Dir, old_sub_path: []const u8, new_dir: Dir, new_sub_path: []const u8) Dir.RenamePreserveError!void
```


### `failingDirSymLink`

```zig
pub fn failingDirSymLink(userdata: ?*anyopaque, dir: Dir, target_path: []const u8, sym_link_path: []const u8, flags: Dir.SymLinkFlags) Dir.SymLinkError!void
```


### `failingDirReadLink`

```zig
pub fn failingDirReadLink(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8, buffer: []u8) Dir.ReadLinkError!usize
```


### `failingDirSetOwner`

```zig
pub fn failingDirSetOwner(userdata: ?*anyopaque, dir: Dir, owner: ?File.Uid, group: ?File.Gid) Dir.SetOwnerError!void
```


### `failingDirSetFileOwner`

```zig
pub fn failingDirSetFileOwner(userdata: ?*anyopaque, dir: std.Io.Dir, sub_path: []const u8, owner: ?File.Uid, group: ?File.Gid, options: Dir.SetFileOwnerOptions) Dir.SetFileOwnerError!void
```


### `failingDirSetPermissions`

```zig
pub fn failingDirSetPermissions(userdata: ?*anyopaque, dir: Dir, permissions: Dir.Permissions) Dir.SetPermissionsError!void
```


### `failingDirSetFilePermissions`

```zig
pub fn failingDirSetFilePermissions(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8, permissions: File.Permissions, options: Dir.SetFilePermissionsOptions) Dir.SetFilePermissionsError!void
```


### `noDirSetTimestamps`

```zig
pub fn noDirSetTimestamps(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8, options: Dir.SetTimestampsOptions) Dir.SetTimestampsError!void
```


### `failingDirHardLink`

```zig
pub fn failingDirHardLink(userdata: ?*anyopaque, old_dir: Dir, old_sub_path: []const u8, new_dir: Dir, new_sub_path: []const u8, options: Dir.HardLinkOptions) Dir.HardLinkError!void
```


### `failingFileStat`

```zig
pub fn failingFileStat(userdata: ?*anyopaque, file: File) File.StatError!File.Stat
```


### `failingFileLength`

```zig
pub fn failingFileLength(userdata: ?*anyopaque, file: File) File.LengthError!u64
```


### `unreachableFileClose`

```zig
pub fn unreachableFileClose(userdata: ?*anyopaque, files: []const File) void
```


### `failingFileWritePositional`

```zig
pub fn failingFileWritePositional(userdata: ?*anyopaque, file: File, header: []const u8, data: []const []const u8, splat: usize, offset: u64) File.WritePositionalError!usize
```


### `noFileWriteFileStreaming`

```zig
pub fn noFileWriteFileStreaming(userdata: ?*anyopaque, file: File, header: []const u8, file_reader: *Io.File.Reader, limit: Io.Limit) File.Writer.WriteFileError!usize
```


### `noFileWriteFilePositional`

```zig
pub fn noFileWriteFilePositional(userdata: ?*anyopaque, file: File, header: []const u8, file_reader: *Io.File.Reader, limit: Io.Limit, offset: u64) File.WriteFilePositionalError!usize
```


### `failingFileReadPositional`

```zig
pub fn failingFileReadPositional(userdata: ?*anyopaque, file: File, data: []const []u8, offset: u64) File.ReadPositionalError!usize
```


### `failingFileSeekBy`

```zig
pub fn failingFileSeekBy(userdata: ?*anyopaque, file: File, relative_offset: i64) File.SeekError!void
```


### `failingFileSeekTo`

```zig
pub fn failingFileSeekTo(userdata: ?*anyopaque, file: File, absolute_offset: u64) File.SeekError!void
```


### `failingFileSync`

```zig
pub fn failingFileSync(userdata: ?*anyopaque, file: File) File.SyncError!void
```


### `unreachableFileIsTty`

```zig
pub fn unreachableFileIsTty(userdata: ?*anyopaque, file: File) Cancelable!bool
```


### `unreachableFileEnableAnsiEscapeCodes`

```zig
pub fn unreachableFileEnableAnsiEscapeCodes(userdata: ?*anyopaque, file: File) File.EnableAnsiEscapeCodesError!void
```


### `unreachableFileSupportsAnsiEscapeCodes`

```zig
pub fn unreachableFileSupportsAnsiEscapeCodes(userdata: ?*anyopaque, file: File) Cancelable!bool
```


### `failingFileSetLength`

```zig
pub fn failingFileSetLength(userdata: ?*anyopaque, file: File, length: u64) File.SetLengthError!void
```


### `failingFileSetOwner`

```zig
pub fn failingFileSetOwner(userdata: ?*anyopaque, file: File, owner: ?File.Uid, group: ?File.Gid) File.SetOwnerError!void
```


### `failingFileSetPermissions`

```zig
pub fn failingFileSetPermissions(userdata: ?*anyopaque, file: File, permissions: File.Permissions) File.SetPermissionsError!void
```


### `noFileSetTimestamps`

```zig
pub fn noFileSetTimestamps(userdata: ?*anyopaque, file: File, options: File.SetTimestampsOptions) File.SetTimestampsError!void
```


### `failingFileLock`

```zig
pub fn failingFileLock(userdata: ?*anyopaque, file: File, lock: File.Lock) File.LockError!void
```


### `failingFileTryLock`

```zig
pub fn failingFileTryLock(userdata: ?*anyopaque, file: File, lock: File.Lock) File.LockError!bool
```


### `unreachableFileUnlock`

```zig
pub fn unreachableFileUnlock(userdata: ?*anyopaque, file: File) void
```


### `failingFileDowngradeLock`

```zig
pub fn failingFileDowngradeLock(userdata: ?*anyopaque, file: File) File.DowngradeLockError!void
```


### `failingFileRealPath`

```zig
pub fn failingFileRealPath(userdata: ?*anyopaque, file: File, out_buffer: []u8) File.RealPathError!usize
```


### `failingFileHardLink`

```zig
pub fn failingFileHardLink(userdata: ?*anyopaque, file: File, new_dir: Dir, new_sub_path: []const u8, options: File.HardLinkOptions) File.HardLinkError!void
```


### `failingFileMemoryMapCreate`

```zig
pub fn failingFileMemoryMapCreate(userdata: ?*anyopaque, file: File, options: File.MemoryMap.CreateOptions) File.MemoryMap.CreateError!File.MemoryMap
```


### `unreachableFileMemoryMapDestroy`

```zig
pub fn unreachableFileMemoryMapDestroy(userdata: ?*anyopaque, mm: *File.MemoryMap) void
```


### `unreachableFileMemoryMapSetLength`

```zig
pub fn unreachableFileMemoryMapSetLength(userdata: ?*anyopaque, mm: *File.MemoryMap, new_len: usize) File.MemoryMap.SetLengthError!void
```


### `unreachableFileMemoryMapRead`

```zig
pub fn unreachableFileMemoryMapRead(userdata: ?*anyopaque, mm: *File.MemoryMap) File.ReadPositionalError!void
```


### `unreachableFileMemoryMapWrite`

```zig
pub fn unreachableFileMemoryMapWrite(userdata: ?*anyopaque, mm: *File.MemoryMap) File.WritePositionalError!void
```


### `failingProcessExecutableOpen`

```zig
pub fn failingProcessExecutableOpen(userdata: ?*anyopaque, flags: Dir.OpenFileOptions) std.process.OpenExecutableError!File
```


### `failingProcessExecutablePath`

```zig
pub fn failingProcessExecutablePath(userdata: ?*anyopaque, buffer: []u8) std.process.ExecutablePathError!usize
```


### `unreachableLockStderr`

```zig
pub fn unreachableLockStderr(userdata: ?*anyopaque, terminal_mode: ?Terminal.Mode) Cancelable!LockedStderr
```


### `noTryLockStderr`

```zig
pub fn noTryLockStderr(userdata: ?*anyopaque, terminal_mode: ?Terminal.Mode) Cancelable!?LockedStderr
```


### `unreachableUnlockStderr`

```zig
pub fn unreachableUnlockStderr(userdata: ?*anyopaque) void
```


### `failingProcessCurrentPath`

```zig
pub fn failingProcessCurrentPath(userdata: ?*anyopaque, buffer: []u8) std.process.CurrentPathError!usize
```


### `failingProcessSetCurrentDir`

```zig
pub fn failingProcessSetCurrentDir(userdata: ?*anyopaque, dir: Dir) std.process.SetCurrentDirError!void
```


### `failingProcessSetCurrentPath`

```zig
pub fn failingProcessSetCurrentPath(userdata: ?*anyopaque, path: []const u8) std.process.SetCurrentPathError!void
```


### `failingProcessReplace`

```zig
pub fn failingProcessReplace(userdata: ?*anyopaque, options: std.process.ReplaceOptions) std.process.ReplaceError
```


### `failingProcessSpawn`

```zig
pub fn failingProcessSpawn(userdata: ?*anyopaque, options: std.process.SpawnOptions) std.process.SpawnError!std.process.Child
```


### `unreachableChildWait`

```zig
pub fn unreachableChildWait(userdata: ?*anyopaque, child: *std.process.Child) std.process.Child.WaitError!std.process.Child.Term
```


### `unreachableChildKill`

```zig
pub fn unreachableChildKill(userdata: ?*anyopaque, child: *std.process.Child) void
```


### `failingProgressParentFile`

```zig
pub fn failingProgressParentFile(userdata: ?*anyopaque) std.Progress.ParentFileError!File
```


### `failingInheritParentDir`

```zig
pub fn failingInheritParentDir(userdata: ?*anyopaque, handle: Dir.Handle) InheritParentHandleError!Dir
```


### `failingInheritParentFile`

```zig
pub fn failingInheritParentFile(userdata: ?*anyopaque, handle: File.Handle, flags: File.Flags) InheritParentHandleError!File
```


### `noRandom`

```zig
pub fn noRandom(userdata: ?*anyopaque, buffer: []u8) void
```


### `failingRandomSecure`

```zig
pub fn failingRandomSecure(userdata: ?*anyopaque, buffer: []u8) RandomSecureError!void
```


### `noNow`

```zig
pub fn noNow(userdata: ?*anyopaque, clock: Clock) Timestamp
```


### `failingClockResolution`

```zig
pub fn failingClockResolution(userdata: ?*anyopaque, clock: Clock) Clock.ResolutionError!Duration
```


### `noSleep`

```zig
pub fn noSleep(userdata: ?*anyopaque, clock: Timeout) Cancelable!void
```


### `failingNetListenIp`

```zig
pub fn failingNetListenIp(userdata: ?*anyopaque, address: *const net.IpAddress, options: net.IpAddress.ListenOptions) net.IpAddress.ListenError!net.Socket
```


### `failingNetAccept`

```zig
pub fn failingNetAccept(userdata: ?*anyopaque, listen_fd: net.Socket.Handle, options: net.Server.AcceptOptions) net.Server.AcceptError!net.Socket
```


### `failingNetBindIp`

```zig
pub fn failingNetBindIp(userdata: ?*anyopaque, address: *const net.IpAddress, options: net.IpAddress.BindOptions) net.IpAddress.BindError!net.Socket
```


### `failingNetConnectIp`

```zig
pub fn failingNetConnectIp(userdata: ?*anyopaque, address: *const net.IpAddress, options: net.IpAddress.ConnectOptions) net.IpAddress.ConnectError!net.Socket
```


### `failingNetListenUnix`

```zig
pub fn failingNetListenUnix(userdata: ?*anyopaque, address: *const net.UnixAddress, options: net.UnixAddress.ListenOptions) net.UnixAddress.ListenError!net.Socket.Handle
```


### `failingNetConnectUnix`

```zig
pub fn failingNetConnectUnix(userdata: ?*anyopaque, address: *const net.UnixAddress) net.UnixAddress.ConnectError!net.Socket.Handle
```


### `failingNetSocketCreatePair`

```zig
pub fn failingNetSocketCreatePair(userdata: ?*anyopaque, options: net.Socket.CreatePairOptions) net.Socket.CreatePairError![2]net.Socket
```


### `failingNetWriteFile`

```zig
pub fn failingNetWriteFile(userdata: ?*anyopaque, handle: net.Socket.Handle, header: []const u8, file_reader: *Io.File.Reader, limit: Io.Limit) net.Stream.Writer.WriteFileError!usize
```


### `unreachableNetClose`

```zig
pub fn unreachableNetClose(userdata: ?*anyopaque, sockets: []const net.Socket) void
```


### `failingNetShutdown`

```zig
pub fn failingNetShutdown(userdata: ?*anyopaque, handle: net.Socket.Handle, how: net.ShutdownHow) net.ShutdownError!void
```


### `failingNetInterfaceNameResolve`

```zig
pub fn failingNetInterfaceNameResolve(userdata: ?*anyopaque, name: *const net.Interface.Name) net.Interface.Name.ResolveError!net.Interface
```


### `unreachableNetInterfaceName`

```zig
pub fn unreachableNetInterfaceName(userdata: ?*anyopaque, interface: net.Interface) net.Interface.NameError!net.Interface.Name
```


### `failingNetLookup`

```zig
pub fn failingNetLookup(userdata: ?*anyopaque, host_name: net.HostName, resolved: *Queue(net.HostName.LookupResult), options: net.HostName.LookupOptions) net.HostName.LookupError!void
```


## Error Sets

- **`OperateTimeoutError`**
  
- **`Cancelable`**
  
- **`UnexpectedError`**
  
- **`InheritParentHandleError`**
  
- **`QueueClosedError`**
  
- **`ConcurrentError`**
  
- **`RandomSecureError`**
  

## Constants & Variables

- **`Threaded`**: 
- **`fiber`**: 
- **`Dispatch`**: 
- **`Kqueue`**: 
- **`Uring`**: 
- **`Reader`**: 
- **`Writer`**: 
- **`net`**: 
- **`Dir`**: 
- **`File`**: 
- **`Terminal`**: 
- **`RwLock`**: 
- **`Semaphore`**: 
- **`failing`**: An implementation of `Io` which simulates a system supporting no `Io` operations.

