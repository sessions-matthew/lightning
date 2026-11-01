# `std.Io.File`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/Io/File.zig`  
> [← Back to Standard Library Index](README.md)

## Fields

- `handle: Handle`
  
- `flags: Flags`
  

## Types

### `Flags`


### Fields

- `nonblocking: bool`
  * true:
    - windows: opened with MODE.IO.ASYNCHRONOUS
    - POSIX: O_NONBLOCK is set
  * false:
    - windows: opened with SYNCHRONOUS_ALERT or SYNCHRONOUS_NONALERT, or
      not a file.
    - POSIX: O_NONBLOCK is unset

### `BlockSize`


### `Kind`


### Fields

- `block_device`
  
- `character_device`
  
- `directory`
  
- `named_pipe`
  
- `sym_link`
  
- `file`
  
- `unix_domain_socket`
  
- `whiteout`
  
- `door`
  
- `event_port`
  
- `unknown`
  

### `Stat`


### Fields

- `inode: INode`
  A number that the system uses to point to the file metadata. This
  number is not guaranteed to be unique across time, as some file
  systems may reuse an inode after its file has been deleted. Some
  systems may change the inode of a file over time.
  
  On Linux, the inode is a structure that stores the metadata, and
  the inode _number_ is what you see here: the index number of the
  inode.
  
  The FileIndex on Windows is similar. It is a number for a file that
  is unique to each filesystem.
- `nlink: NLink`
  
- `size: u64`
  
- `permissions: Permissions`
  
- `kind: Kind`
  
- `atime: ?Io.Timestamp`
  Last access time in nanoseconds, relative to UTC 1970-01-01.
  
  Filesystems generally find this value problematic to keep updated since
  it turns read-only file system accesses into file system mutations.
  Some systems report stale values, and some systems explicitly refuse to
  report this value. The latter case is handled by `null`.
- `mtime: Io.Timestamp`
  Last modification time in nanoseconds, relative to UTC 1970-01-01.
- `ctime: Io.Timestamp`
  Last status/metadata change time in nanoseconds, relative to UTC 1970-01-01.
- `block_size: BlockSize`
  Smallest chunk length in bytes appropriate for optimal I/O. This will
  be set to `1` for operating systems or file systems that do not
  recognize this concept. Not always a power of two.

### `Lock`


### Fields

- `none`
  
- `shared`
  
- `exclusive`
  

### `SetTimestampsOptions`


### Fields

- `access_timestamp: SetTimestamp = .unchanged`
  
- `modify_timestamp: SetTimestamp = .unchanged`
  

### `SetTimestamp`


### Fields

- `unchanged`
  Leave the existing timestamp unmodified.
- `now`
  Set to current time using `Io.Clock.real`.
- `new: Io.Timestamp`
  Set to provided timestamp using `Io.Clock.real`.

### Functions

#### `init`

```zig
pub fn init(optional: ?Io.Timestamp) SetTimestamp
```

Convenience for interacting with `Stat`, in which `null` indicates `unchanged`.

### `HardLinkOptions`


### Fields

- `follow_symlinks: bool = false`
  

## Functions

### `stdout`

```zig
pub fn stdout() File
```


### `stderr`

```zig
pub fn stderr() File
```


### `stdin`

```zig
pub fn stdin() File
```


### `stat`

```zig
pub fn stat(file: File, io: Io) StatError!Stat
```

Returns `Stat` containing basic information about the `File`.

### `close`

```zig
pub fn close(file: File, io: Io) void
```


### `closeMany`

```zig
pub fn closeMany(io: Io, files: []const File) void
```


### `sync`

```zig
pub fn sync(file: File, io: Io) SyncError!void
```

Blocks until all pending file contents and metadata modifications for the
file have been synchronized with the underlying filesystem.

This does not ensure that metadata for the directory containing the file
has also reached disk.

### `isTty`

```zig
pub fn isTty(file: File, io: Io) Io.Cancelable!bool
```

Test whether the file refers to a terminal (similar to libc "isatty").

See also:
* `enableAnsiEscapeCodes`
* `supportsAnsiEscapeCodes`.

### `enableAnsiEscapeCodes`

```zig
pub fn enableAnsiEscapeCodes(file: File, io: Io) EnableAnsiEscapeCodesError!void
```


### `supportsAnsiEscapeCodes`

```zig
pub fn supportsAnsiEscapeCodes(file: File, io: Io) Io.Cancelable!bool
```

Test whether ANSI escape codes will be treated as such without
attempting to enable support for ANSI escape codes.

### `setLength`

```zig
pub fn setLength(file: File, io: Io, new_length: u64) SetLengthError!void
```

Truncates or expands the file, populating any new data with zeroes.

The file offset after this call is left unchanged.

This function operates on an open file handle. There is not an equivalent
function in `Dir` which operates on paths because generally, such
functionality will introduce Time-Of-Check, Time-Of-Use (TOCTOU) bugs. In
the rare case when those semantics are actually needed, it is reasonable to
open the file with the truncate flag.

### `length`

```zig
pub fn length(file: File, io: Io) LengthError!u64
```

Retrieve the ending byte index of the file.

Sometimes cheaper than `stat` if only the length is needed.

### `setPermissions`

```zig
pub fn setPermissions(file: File, io: Io, new_permissions: Permissions) SetPermissionsError!void
```

Also known as "chmod".

The process must have the correct privileges in order to do this
successfully, or must have the effective user ID matching the owner of the
file.

### `setOwner`

```zig
pub fn setOwner(file: File, io: Io, owner: ?Uid, group: ?Gid) SetOwnerError!void
```

Also known as "chown".

The process must have the correct privileges in order to do this
successfully. The group may be changed by the owner of the file to any
group of which the owner is a member. If the owner or group is specified as
`null`, the ID is not changed.

### `setTimestamps`

```zig
pub fn setTimestamps(file: File, io: Io, options: SetTimestampsOptions) SetTimestampsError!void
```

The granularity that ultimately is stored depends on the combination of
operating system and file system. When a value as provided that exceeds
this range, the value is clamped to the maximum.

### `setTimestampsNow`

```zig
pub fn setTimestampsNow(file: File, io: Io) SetTimestampsError!void
```

Sets the accessed and modification timestamps of `file` to the current wall
clock time.

The granularity that ultimately is stored depends on the combination of
operating system and file system.

### `readStreaming`

```zig
pub fn readStreaming(file: File, io: Io, buffer: []const []u8) ReadStreamingError!usize
```

May return fewer bytes than buffer space available, including 0.
End-of-stream is indicated by `error.EndOfStream`.

See also:
* `reader`

### `readPositional`

```zig
pub fn readPositional(file: File, io: Io, buffer: []const []u8, offset: u64) ReadPositionalError!usize
```

Returns 0 on stream end or if `buffer` has no space available for data.

See also:
* `reader`

### `writePositional`

```zig
pub fn writePositional(file: File, io: Io, buffer: []const []const u8, offset: u64) WritePositionalError!usize
```

See also:
* `writer`

### `writePositionalAll`

```zig
pub fn writePositionalAll(file: File, io: Io, bytes: []const u8, offset: u64) WritePositionalError!void
```

Equivalent to creating a positional writer, writing `bytes`, and then flushing.

### `reader`

```zig
pub fn reader(file: File, io: Io, buffer: []u8) Reader
```

Defaults to positional reading; falls back to streaming.

Positional is more threadsafe, since the global seek position is not
affected.

See also:
* `readerStreaming`

### `readPositionalAll`

```zig
pub fn readPositionalAll(file: File, io: Io, buffer: []u8, offset: u64) ReadPositionalError!usize
```

Equivalent to creating a positional reader and reading multiple times to fill `buffer`.

Returns number of bytes read into `buffer`. If less than `buffer.len`, end of file occurred.

See also:
* `reader`

### `readerStreaming`

```zig
pub fn readerStreaming(file: File, io: Io, buffer: []u8) Reader
```

Positional is more threadsafe, since the global seek position is not
affected, but when such syscalls are not available, preemptively
initializing in streaming mode skips a failed syscall.

See also:
* `reader`

### `writer`

```zig
pub fn writer(file: File, io: Io, buffer: []u8) Writer
```

Defaults to positional reading; falls back to streaming.

Positional is more threadsafe, since the global seek position is not
affected.

### `writerStreaming`

```zig
pub fn writerStreaming(file: File, io: Io, buffer: []u8) Writer
```

Positional is more threadsafe, since the global seek position is not
affected, but when such syscalls are not available, preemptively
initializing in streaming mode will skip a failed syscall.

### `writeStreaming`

```zig
pub fn writeStreaming(file: File, io: Io, header: []const u8, data: []const []const u8, splat: usize) Writer.Error!usize
```

This is a low-level API that calls the `Io` interface function directly.
For a higher level API, see `writerStreaming`.

### `writeStreamingAll`

```zig
pub fn writeStreamingAll(file: File, io: Io, bytes: []const u8) Writer.Error!void
```

Equivalent to creating a streaming writer, writing `bytes`, and then flushing.

### `lock`

```zig
pub fn lock(file: File, io: Io, l: Lock) LockError!void
```

Blocks when an incompatible lock is held by another process. A process may
hold only one type of lock (shared or exclusive) on a file. When a process
terminates in any way, the lock is released.

Assumes the file is unlocked.

### `unlock`

```zig
pub fn unlock(file: File, io: Io) void
```

Assumes the file is locked.

### `tryLock`

```zig
pub fn tryLock(file: File, io: Io, l: Lock) LockError!bool
```

Attempts to obtain a lock, returning `true` if the lock is obtained, and
`false` if there was an existing incompatible lock held. A process may hold
only one type of lock (shared or exclusive) on a file. When a process
terminates in any way, the lock is released.

Assumes the file is unlocked.

### `downgradeLock`

```zig
pub fn downgradeLock(file: File, io: Io) LockError!void
```

Assumes the file is already locked in exclusive mode.
Atomically modifies the lock to be in shared mode, without releasing it.

### `realPath`

```zig
pub fn realPath(file: File, io: Io, out_buffer: []u8) RealPathError!usize
```

Obtains the canonicalized absolute path name corresponding to an open file
handle.

This function has limited platform support, and using it can lead to
unnecessary failures and race conditions. It is generally advisable to
avoid this function entirely.

### `hardLink`

```zig
pub fn hardLink(file: File, io: Io, new_dir: Dir, new_sub_path: []const u8, options: HardLinkOptions, ) HardLinkError!void
```


### `createMemoryMap`

```zig
pub fn createMemoryMap(file: File, io: Io, options: MemoryMap.CreateOptions) MemoryMap.CreateError!MemoryMap
```


## Error Sets

- **`StatError`**
  
- **`OpenError`**
  
- **`SyncError`**
  
- **`EnableAnsiEscapeCodesError`**
  
- **`SetLengthError`**
  
- **`SetPermissionsError`**
  
- **`SetOwnerError`**
  
- **`SetTimestampsError`**
  
- **`ReadStreamingError`**
  
- **`ReadPositionalError`**
  
- **`WritePositionalError`**
  
- **`SeekError`**
  
- **`WriteFilePositionalError`**
  
- **`LockError`**
  
- **`DowngradeLockError`**
  
- **`RealPathError`**
  
- **`HardLinkError`**
  

## Constants & Variables

- **`Handle`**: 
- **`Reader`**: 
- **`Writer`**: 
- **`Atomic`**: 
- **`MemoryMap`**: Memory intended to remain consistent with file contents.
- **`MultiReader`**: Concurrently read from multiple file streams, eliminating risk of
- **`INode`**: 
- **`NLink`**: 
- **`Uid`**: 
- **`Gid`**: 
- **`LengthError`**: 
- **`Permissions`**: Cross-platform representation of permissions on a file.

