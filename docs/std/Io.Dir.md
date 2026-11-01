# `std.Io.Dir`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/Io/Dir.zig`  
> [← Back to Standard Library Index](README.md)

## Fields

- `handle: Handle`
  

## Types

### `Entry`


### Fields

- `name: []const u8`
  
- `kind: File.Kind`
  
- `inode: File.INode`
  

### `Reader`


### Fields

- `dir: Dir`
  
- `state: State`
  
- `buffer: []align(@alignOf(usize)) u8`
  Stores I/O implementation specific data.
- `index: usize`
  Index of next entry in `buffer`.
- `end: usize`
  Fill position of `buffer`.

### Types

#### `State`


### Functions

#### `init`

```zig
pub fn init(dir: Dir, buffer: []align(@alignOf(usize)) u8) Reader
```

Asserts that `buffer` has length at least `min_buffer_len`.

#### `read`

```zig
pub fn read(r: *Reader, io: Io, buffer: []Entry) Error!usize
```

All `Entry.name` are invalidated with the next call to `read` or
`next`.

#### `next`

```zig
pub fn next(r: *Reader, io: Io) Error!?Entry
```

`Entry.name` is invalidated with the next call to `read` or `next`.

#### `reset`

```zig
pub fn reset(r: *Reader) void
```


### Error Sets

- **`Error`**
  

### Constants & Variables

- **`min_buffer_len`**: A length for `buffer` that allows all implementations to function.

### `Iterator`

This API is designed for convenience rather than performance:
* It chooses a buffer size rather than allowing the user to provide one.
* It is movable by only requesting one `Entry` at a time from the `Io`
  implementation rather than doing batch operations.

Still, it will do a decent job of minimizing syscall overhead. For a
lower level abstraction, see `Reader`. For a higher level abstraction,
see `Walker`.

### Fields

- `reader: Reader`
  
- `reader_buffer: [reader_buffer_len]u8 align(@alignOf(usize))`
  

### Functions

#### `init`

```zig
pub fn init(dir: Dir, reader_state: Reader.State) Iterator
```


#### `next`

```zig
pub fn next(it: *Iterator, io: Io) Error!?Entry
```


### Constants & Variables

- **`reader_buffer_len`**: 
- **`Error`**: 

### `SelectiveWalker`


### Fields

- `stack: std.ArrayList(StackItem)`
  
- `name_buffer: std.ArrayList(u8)`
  
- `allocator: Allocator`
  

### Functions

#### `next`

```zig
pub fn next(self: *SelectiveWalker, io: Io) Error!?Walker.Entry
```

After each call to this function, and on deinit(), the memory returned
from this function becomes invalid. A copy must be made in order to keep
a reference to the path.

#### `enter`

```zig
pub fn enter(self: *SelectiveWalker, io: Io, entry: Walker.Entry) !void
```

Traverses into the directory, continuing walking one level down.

#### `deinit`

```zig
pub fn deinit(self: *SelectiveWalker) void
```


#### `leave`

```zig
pub fn leave(self: *SelectiveWalker, io: Io) void
```

Leaves the current directory, continuing walking one level up.
If the current entry is a directory entry, then the "current directory"
will pertain to that entry if `enter` is called before `leave`.

### Error Sets

- **`Error`**
  

### `Walker`


### Fields

- `inner: SelectiveWalker`
  

### Types

#### `Entry`


### Functions

#### `next`

```zig
pub fn next(self: *Walker, io: Io) !?Walker.Entry
```

After each call to this function, and on deinit(), the memory returned
from this function becomes invalid. A copy must be made in order to keep
a reference to the path.

#### `deinit`

```zig
pub fn deinit(self: *Walker) void
```


#### `leave`

```zig
pub fn leave(self: *Walker, io: Io) void
```

Leaves the current directory, continuing walking one level up.
If the current entry is a directory entry, then the "current directory"
is the directory pertaining to the current entry.

### `AccessOptions`


### Fields

- `follow_symlinks: bool = true`
  
- `read: bool = false`
  
- `write: bool = false`
  
- `execute: bool = false`
  

### `OpenOptions`


### Fields

- `access_sub_paths: bool = true`
  `true` means the opened directory can be used as the `Dir` parameter
  for functions which operate based on an open directory handle. When `false`,
  such operations are Illegal Behavior.
- `iterate: bool = false`
  `true` means the opened directory can be scanned for the files and sub-directories
  of the result. It means the `iterate` function can be called.
- `follow_symlinks: bool = true`
  `false` means it won't dereference the symlinks.

### `OpenFileOptions`


### Fields

- `mode: Mode = .read_only`
  
- `allow_directory: bool = true`
  Determines the behavior when opening a path that refers to a directory.
  
  If set to true, directories may be opened, but `error.IsDir` is still
  possible in certain scenarios, e.g. attempting to open a directory with
  write permissions.
  
  If set to false, `error.IsDir` will always be returned when opening a directory.
  
  When set to false:
  * On Windows, the behavior is implemented without any extra syscalls.
  * On other operating systems, the behavior is implemented with an additional
    `fstat` syscall.
- `path_only: bool = false`
  Indicates intent for only some operations to be performed on this
  opened file:
  * `close`
  * `stat`
  On Linux and FreeBSD, this corresponds to `std.posix.O.PATH`.
- `lock: File.Lock = .none`
  Open the file with an advisory lock to coordinate with other processes
  accessing it at the same time. An exclusive lock will prevent other
  processes from acquiring a lock. A shared lock will prevent other
  processes from acquiring a exclusive lock, but does not prevent
  other process from getting their own shared locks.
  
  The lock is advisory, except on Linux in very specific circumstances[1].
  This means that a process that does not respect the locking API can still get access
  to the file, despite the lock.
  
  On these operating systems, the lock is acquired atomically with
  opening the file:
  * Darwin
  * DragonFlyBSD
  * FreeBSD
  * Haiku
  * NetBSD
  * OpenBSD
  On these operating systems, the lock is acquired via a separate syscall
  after opening the file:
  * Linux
  * Windows
  
  [1]: https://www.kernel.org/doc/Documentation/filesystems/mandatory-locking.txt
- `lock_nonblocking: bool = false`
  Sets whether or not to wait until the file is locked to return. If set to true,
  `error.WouldBlock` will be returned. Otherwise, the file will wait until the file
  is available to proceed.
- `allow_ctty: bool = false`
  Set this to allow the opened file to automatically become the
  controlling TTY for the current process.
- `follow_symlinks: bool = true`
  
- `resolve_beneath: bool = false`
  If supported by the operating system, attempted path resolution that
  would escape the directory instead returns `error.AccessDenied`. If
  unsupported, this option is ignored.

### Types

#### `Mode`


### Functions

#### `isRead`

```zig
pub fn isRead(self: OpenFileOptions) bool
```


#### `isWrite`

```zig
pub fn isWrite(self: OpenFileOptions) bool
```


### `CreateFileOptions`


### Fields

- `read: bool = false`
  Whether the file will be created with read access.
- `truncate: bool = true`
  If the file already exists, and is a regular file, and the access
  mode allows writing, it will be truncated to length 0.
- `exclusive: bool = false`
  Ensures that this open call creates the file, otherwise causes
  `error.PathAlreadyExists` to be returned.
- `lock: File.Lock = .none`
  Open the file with an advisory lock to coordinate with other processes
  accessing it at the same time. An exclusive lock will prevent other
  processes from acquiring a lock. A shared lock will prevent other
  processes from acquiring a exclusive lock, but does not prevent
  other process from getting their own shared locks.
  
  The lock is advisory, except on Linux in very specific circumstances[1].
  This means that a process that does not respect the locking API can still get access
  to the file, despite the lock.
  
  On these operating systems, the lock is acquired atomically with
  opening the file:
  * Darwin
  * DragonFlyBSD
  * FreeBSD
  * Haiku
  * NetBSD
  * OpenBSD
  On these operating systems, the lock is acquired via a separate syscall
  after opening the file:
  * Linux
  * Windows
  
  [1]: https://www.kernel.org/doc/Documentation/filesystems/mandatory-locking.txt
- `lock_nonblocking: bool = false`
  Sets whether or not to wait until the file is locked to return. If set to true,
  `error.WouldBlock` will be returned. Otherwise, the file will wait until the file
  is available to proceed.
- `permissions: Permissions = .default_file`
  
- `resolve_beneath: bool = false`
  If supported by the operating system, attempted path resolution that
  would escape the directory instead returns `error.AccessDenied`. If
  unsupported, this option is ignored.

### `WriteFileOptions`


### Fields

- `sub_path: []const u8`
  On Windows, `sub_path` should be encoded as [WTF-8](https://wtf-8.codeberg.page/).
  On WASI, `sub_path` should be encoded as valid UTF-8.
  On other platforms, `sub_path` is an opaque sequence of bytes with no particular encoding.
- `data: []const u8`
  
- `flags: CreateFileOptions = .{}`
  

### `PrevStatus`


### Fields

- `stale`
  
- `fresh`
  

### `CreatePathStatus`


### Fields

- `existed`
  
- `created`
  

### `CreateDirPathOpenOptions`


### Fields

- `open_options: OpenOptions = .{}`
  
- `permissions: Permissions = .default_dir`
  

### `StatFileOptions`


### Fields

- `follow_symlinks: bool = true`
  

### `SymLinkFlags`

Use with `symLink`, `symLinkAtomic`, and `symLinkAbsolute` to
specify whether the symlink will point to a file or a directory. This value
is ignored on all hosts except Windows where creating symlinks to different
resource types, requires different flags. By default, `symLinkAbsolute` is
assumed to point to a file.

### Fields

- `is_directory: bool = false`
  

### `CopyFileOptions`


### Fields

- `permissions: ?File.Permissions = null`
  When this is `null` the permissions are copied from the source file.
- `make_path: bool = false`
  
- `replace: bool = true`
  

### `CreateFileAtomicOptions`


### Fields

- `permissions: File.Permissions = .default_file`
  
- `make_path: bool = false`
  
- `replace: bool = false`
  Tells whether the unnamed file will be ultimately created with
  `File.Atomic.link` or `File.Atomic.replace`.
  
  If this value is incorrect it will cause an assertion failure in
  `File.Atomic.replace`.

### `SetFilePermissionsOptions`


### Fields

- `follow_symlinks: bool = true`
  

### `SetFileOwnerOptions`


### Fields

- `follow_symlinks: bool = true`
  

### `SetTimestampsOptions`


### Fields

- `follow_symlinks: bool = true`
  
- `access_timestamp: File.SetTimestamp = .unchanged`
  
- `modify_timestamp: File.SetTimestamp = .unchanged`
  

### `SetTimestampsNowOptions`


### Fields

- `follow_symlinks: bool = true`
  

## Functions

### `cwd`

```zig
pub fn cwd() Dir
```

Returns a handle to the current working directory.

It is not opened with iteration capability. Iterating over the result is
illegal behavior.

Closing the returned `Dir` is checked illegal behavior.

On POSIX targets, this function is comptime-callable.

This function is overridable via `std.Options.cwd`.

### `iterate`

```zig
pub fn iterate(dir: Dir) Iterator
```


### `iterateAssumeFirstIteration`

```zig
pub fn iterateAssumeFirstIteration(dir: Dir) Iterator
```

Like `iterate`, but will not reset the directory cursor before the first
iteration. This should only be used in cases where it is known that the
`Dir` has not had its cursor modified yet (e.g. it was just opened).

### `walkSelectively`

```zig
pub fn walkSelectively(dir: Dir, allocator: Allocator) !SelectiveWalker
```

Recursively iterates over a directory, but requires the user to
opt-in to recursing into each directory entry.

`dir` must have been opened with `OpenOptions.iterate` set to `true`.

`Walker.deinit` releases allocated memory and directory handles.

The order of returned file system entries is undefined.

`dir` will not be closed after walking it.

See also `walk`.

### `walk`

```zig
pub fn walk(dir: Dir, allocator: Allocator) Allocator.Error!Walker
```

Recursively iterates over a directory.

`dir` must have been opened with `OpenOptions.iterate` set to `true`.

`Walker.deinit` releases allocated memory and directory handles.

The order of returned file system entries is undefined.

`dir` will not be closed after walking it.

See also:
* `walkSelectively`

### `access`

```zig
pub fn access(dir: Dir, io: Io, sub_path: []const u8, options: AccessOptions) AccessError!void
```

Test accessing `sub_path`.

On Windows, `sub_path` should be encoded as [WTF-8](https://wtf-8.codeberg.page/).
On WASI, `sub_path` should be encoded as valid UTF-8.
On other platforms, `sub_path` is an opaque sequence of bytes with no particular encoding.

Be careful of Time-Of-Check-Time-Of-Use race conditions when using this
function. For example, instead of testing if a file exists and then opening
it, just open it and handle the error for file not found.

### `accessAbsolute`

```zig
pub fn accessAbsolute(io: Io, absolute_path: []const u8, options: AccessOptions) AccessError!void
```


### `openDir`

```zig
pub fn openDir(dir: Dir, io: Io, sub_path: []const u8, options: OpenOptions) OpenError!Dir
```

Opens a directory at the given path. The directory is a system resource that remains
open until `close` is called on the result.

The directory cannot be iterated unless the `iterate` option is set to `true`.

On Windows, `sub_path` should be encoded as [WTF-8](https://wtf-8.codeberg.page/).
On WASI, `sub_path` should be encoded as valid UTF-8.
On other platforms, `sub_path` is an opaque sequence of bytes with no particular encoding.

### `openDirAbsolute`

```zig
pub fn openDirAbsolute(io: Io, absolute_path: []const u8, options: OpenOptions) OpenError!Dir
```


### `close`

```zig
pub fn close(dir: Dir, io: Io) void
```


### `closeMany`

```zig
pub fn closeMany(io: Io, dirs: []const Dir) void
```


### `openFile`

```zig
pub fn openFile(dir: Dir, io: Io, sub_path: []const u8, options: OpenFileOptions) File.OpenError!File
```

Opens a file for reading or writing, without attempting to create a new file.

To create a new file, see `createFile`.

Allocates a resource to be released with `File.close`.

On Windows, `sub_path` should be encoded as [WTF-8](https://wtf-8.codeberg.page/).
On WASI, `sub_path` should be encoded as valid UTF-8.
On other platforms, `sub_path` is an opaque sequence of bytes with no particular encoding.

### `openFileAbsolute`

```zig
pub fn openFileAbsolute(io: Io, absolute_path: []const u8, options: OpenFileOptions) File.OpenError!File
```


### `createFile`

```zig
pub fn createFile(dir: Dir, io: Io, sub_path: []const u8, flags: CreateFileOptions) File.OpenError!File
```

Creates, opens, or overwrites a file with write access.

Allocates a resource to be dellocated with `File.close`.

On Windows, `sub_path` should be encoded as [WTF-8](https://wtf-8.codeberg.page/).
On WASI, `sub_path` should be encoded as valid UTF-8.
On other platforms, `sub_path` is an opaque sequence of bytes with no particular encoding.

### `createFileAbsolute`

```zig
pub fn createFileAbsolute(io: Io, absolute_path: []const u8, flags: CreateFileOptions) File.OpenError!File
```


### `writeFile`

```zig
pub fn writeFile(dir: Dir, io: Io, options: WriteFileOptions) WriteFileError!void
```

Writes content to the file system, using the file creation flags provided.

### `updateFile`

```zig
pub fn updateFile(source_dir: Dir, io: Io, source_path: []const u8, dest_dir: Dir, dest_path: []const u8, options: CopyFileOptions, ) !PrevStatus
```

Check the file size, mtime, and permissions of `source_path` and `dest_path`. If
they are equal, does nothing. Otherwise, atomically copies `source_path` to
`dest_path`, creating the parent directory hierarchy as needed. The
destination file gains the mtime, atime, and permissions of the source file so
that the next call to `updateFile` will not need a copy.

Returns the previous status of the file before updating.

* On Windows, both paths should be encoded as [WTF-8](https://wtf-8.codeberg.page/).
* On WASI, both paths should be encoded as valid UTF-8.
* On other platforms, both paths are an opaque sequence of bytes with no particular encoding.

### `readFile`

```zig
pub fn readFile(dir: Dir, io: Io, file_path: []const u8, buffer: []u8) ReadFileError![]u8
```

Read all of file contents using a preallocated buffer.

The returned slice has the same pointer as `buffer`. If the length matches `buffer.len`
the situation is ambiguous. It could either mean that the entire file was read, and
it exactly fits the buffer, or it could mean the buffer was not big enough for the
entire file.

* On Windows, `file_path` should be encoded as [WTF-8](https://simonsapin.github.io/wtf-8/).
* On WASI, `file_path` should be encoded as valid UTF-8.
* On other platforms, `file_path` is an opaque sequence of bytes with no particular encoding.

### `createDir`

```zig
pub fn createDir(dir: Dir, io: Io, sub_path: []const u8, permissions: Permissions) CreateDirError!void
```

Creates a single directory with a relative or absolute path.

* On Windows, `sub_path` should be encoded as [WTF-8](https://simonsapin.github.io/wtf-8/).
* On WASI, `sub_path` should be encoded as valid UTF-8.
* On other platforms, `sub_path` is an opaque sequence of bytes with no particular encoding.

Related:
* `createDirPath`
* `createDirAbsolute`

### `createDirAbsolute`

```zig
pub fn createDirAbsolute(io: Io, absolute_path: []const u8, permissions: Permissions) CreateDirError!void
```

Create a new directory, based on an absolute path.

Asserts that the path is absolute. See `createDir` for a function that
operates on both absolute and relative paths.

On Windows, `absolute_path` should be encoded as [WTF-8](https://wtf-8.codeberg.page/).
On WASI, `absolute_path` should be encoded as valid UTF-8.
On other platforms, `absolute_path` is an opaque sequence of bytes with no particular encoding.

### `createDirPath`

```zig
pub fn createDirPath(dir: Dir, io: Io, sub_path: []const u8) CreateDirPathError!void
```

Creates parent directories with default permissions as necessary to ensure
`sub_path` exists as a directory.

Returns success if the path already exists and is a directory.

This function may not be atomic. If it returns an error, the file system
may have been modified.

Fails on an empty path with `error.BadPathName` as that is not a path that
can be created.

On Windows, `sub_path` should be encoded as [WTF-8](https://simonsapin.github.io/wtf-8/).
On WASI, `sub_path` should be encoded as valid UTF-8.
On other platforms, `sub_path` is an opaque sequence of bytes with no particular encoding.

Paths containing `..` components are handled differently depending on the platform:
- On Windows, `..` are resolved before the path is passed to NtCreateFile, meaning
  a `sub_path` like "first/../second" will resolve to "second" and only a
  `./second` directory will be created.
- On other platforms, `..` are not resolved before the path is passed to `mkdirat`,
  meaning a `sub_path` like "first/../second" will create both a `./first`
  and a `./second` directory.

See also:
* `createDirPathStatus`

### `createDirPathStatus`

```zig
pub fn createDirPathStatus(dir: Dir, io: Io, sub_path: []const u8, permissions: Permissions) CreateDirPathError!CreatePathStatus
```

Same as `createDirPath` except returns whether the path already existed or was
successfully created.

### `createDirPathOpen`

```zig
pub fn createDirPathOpen(dir: Dir, io: Io, sub_path: []const u8, options: CreateDirPathOpenOptions) CreateDirPathOpenError!Dir
```

Performs the equivalent of `createDirPath` followed by `openDir`, atomically if possible.

When this operation is canceled, it may leave the file system in a
partially modified state.

On Windows, `sub_path` should be encoded as [WTF-8](https://wtf-8.codeberg.page/).
On WASI, `sub_path` should be encoded as valid UTF-8.
On other platforms, `sub_path` is an opaque sequence of bytes with no particular encoding.

### `stat`

```zig
pub fn stat(dir: Dir, io: Io) StatError!Stat
```


### `statFile`

```zig
pub fn statFile(dir: Dir, io: Io, sub_path: []const u8, options: StatFileOptions) StatFileError!Stat
```

Returns metadata for a file inside the directory.

On Windows, this requires three syscalls. On other operating systems, it
only takes one.

Symlinks are followed.

`sub_path` may be absolute, in which case `self` is ignored.

* On Windows, `sub_path` should be encoded as [WTF-8](https://simonsapin.github.io/wtf-8/).
* On WASI, `sub_path` should be encoded as valid UTF-8.
* On other platforms, `sub_path` is an opaque sequence of bytes with no particular encoding.

### `realPath`

```zig
pub fn realPath(dir: Dir, io: Io, out_buffer: []u8) RealPathError!usize
```

Obtains the canonicalized absolute path name of `sub_path` relative to this
`Dir`. If `sub_path` is absolute, ignores this `Dir` handle and obtains the
canonicalized absolute pathname of `sub_path` argument.

This function has limited platform support, and using it can lead to
unnecessary failures and race conditions. It is generally advisable to
avoid this function entirely.

### `realPathFile`

```zig
pub fn realPathFile(dir: Dir, io: Io, sub_path: []const u8, out_buffer: []u8) RealPathFileError!usize
```

Obtains the canonicalized absolute path name of `sub_path` relative to this
`Dir`. If `sub_path` is absolute, ignores this `Dir` handle and obtains the
canonicalized absolute pathname of `sub_path` argument.

This function has limited platform support, and using it can lead to
unnecessary failures and race conditions. It is generally advisable to
avoid this function entirely.

See also:
* `realPathFileAlloc`.
* `realPathFileAbsolute`.

### `realPathFileAlloc`

```zig
pub fn realPathFileAlloc(dir: Dir, io: Io, sub_path: []const u8, allocator: Allocator) RealPathFileAllocError![:0]u8
```

Same as `realPathFile` except allocates result.

This function has limited platform support, and using it can lead to
unnecessary failures and race conditions. It is generally advisable to
avoid this function entirely.

See also:
* `realPathFile`.
* `realPathFileAbsolute`.

### `realPathFileAbsolute`

```zig
pub fn realPathFileAbsolute(io: Io, absolute_path: []const u8, out_buffer: []u8) RealPathFileError!usize
```

Same as `realPathFile` except `absolute_path` is asserted to be an absolute
path.

This function has limited platform support, and using it can lead to
unnecessary failures and race conditions. It is generally advisable to
avoid this function entirely.

See also:
* `realPathFile`.
* `realPathFileAlloc`.

### `realPathFileAbsoluteAlloc`

```zig
pub fn realPathFileAbsoluteAlloc(io: Io, absolute_path: []const u8, allocator: Allocator) RealPathFileAllocError![:0]u8
```

Same as `realPathFileAbsolute` except allocates result.

This function has limited platform support, and using it can lead to
unnecessary failures and race conditions. It is generally advisable to
avoid this function entirely.

See also:
* `realPathFileAbsolute`.
* `realPathFile`.

### `deleteFile`

```zig
pub fn deleteFile(dir: Dir, io: Io, sub_path: []const u8) DeleteFileError!void
```

Delete a file name and possibly the file it refers to, based on an open directory handle.

On Windows, `sub_path` should be encoded as [WTF-8](https://wtf-8.codeberg.page/).
On WASI, `sub_path` should be encoded as valid UTF-8.
On other platforms, `sub_path` is an opaque sequence of bytes with no particular encoding.

Asserts that the path parameter has no null bytes.

### `deleteFileAbsolute`

```zig
pub fn deleteFileAbsolute(io: Io, absolute_path: []const u8) DeleteFileError!void
```


### `deleteDir`

```zig
pub fn deleteDir(dir: Dir, io: Io, sub_path: []const u8) DeleteDirError!void
```

Returns `error.DirNotEmpty` if the directory is not empty.

To delete a directory recursively, see `deleteTree`.

On Windows, `sub_path` should be encoded as [WTF-8](https://wtf-8.codeberg.page/).
On WASI, `sub_path` should be encoded as valid UTF-8.
On other platforms, `sub_path` is an opaque sequence of bytes with no particular encoding.

### `deleteDirAbsolute`

```zig
pub fn deleteDirAbsolute(io: Io, absolute_path: []const u8) DeleteDirError!void
```

Same as `deleteDir` except the path is absolute.

On Windows, `dir_path` should be encoded as [WTF-8](https://wtf-8.codeberg.page/).
On WASI, `dir_path` should be encoded as valid UTF-8.
On other platforms, `dir_path` is an opaque sequence of bytes with no particular encoding.

### `rename`

```zig
pub fn rename(old_dir: Dir, old_sub_path: []const u8, new_dir: Dir, new_sub_path: []const u8, io: Io, ) RenameError!void
```

Change the name or location of a file or directory.

If `new_sub_path` already exists, it will be replaced.

Renaming a file over an existing directory or a directory over an existing
file will fail with `error.IsDir` or `error.NotDir`

* On Windows, both paths should be encoded as [WTF-8](https://wtf-8.codeberg.page/).
* On WASI, both paths should be encoded as valid UTF-8.
* On other platforms, both paths are an opaque sequence of bytes with no particular encoding.

### `renameAbsolute`

```zig
pub fn renameAbsolute(old_path: []const u8, new_path: []const u8, io: Io) RenameError!void
```


### `renamePreserve`

```zig
pub fn renamePreserve(old_dir: Dir, old_sub_path: []const u8, new_dir: Dir, new_sub_path: []const u8, io: Io, ) RenamePreserveError!void
```

Change the name or location of a file or directory.

If `new_sub_path` already exists, `error.PathAlreadyExists` will be returned.

* On Windows, both paths should be encoded as [WTF-8](https://wtf-8.codeberg.page/).
* On WASI, both paths should be encoded as valid UTF-8.
* On other platforms, both paths are an opaque sequence of bytes with no particular encoding.

### `hardLink`

```zig
pub fn hardLink(old_dir: Dir, old_sub_path: []const u8, new_dir: Dir, new_sub_path: []const u8, io: Io, options: HardLinkOptions, ) HardLinkError!void
```


### `symLink`

```zig
pub fn symLink(dir: Dir, io: Io, target_path: []const u8, sym_link_path: []const u8, flags: SymLinkFlags, ) SymLinkError!void
```

Creates a symbolic link named `sym_link_path` which contains the string `target_path`.

A symbolic link (also known as a soft link) may point to an existing file or to a nonexistent
one; the latter case is known as a dangling link.

If `sym_link_path` exists, it will not be overwritten.

On Windows, both paths should be encoded as [WTF-8](https://wtf-8.codeberg.page/).
On WASI, both paths should be encoded as valid UTF-8.
On other platforms, both paths are an opaque sequence of bytes with no particular encoding.

### `symLinkAbsolute`

```zig
pub fn symLinkAbsolute(io: Io, target_path: []const u8, sym_link_path: []const u8, flags: SymLinkFlags, ) SymLinkError!void
```


### `symLinkAtomic`

```zig
pub fn symLinkAtomic(dir: Dir, io: Io, target_path: []const u8, sym_link_path: []const u8, flags: SymLinkFlags, ) !void
```

Same as `symLink`, except tries to create the symbolic link until it
succeeds or encounters an error other than `error.PathAlreadyExists`.

* On Windows, both paths should be encoded as [WTF-8](https://wtf-8.codeberg.page/).
* On WASI, both paths should be encoded as valid UTF-8.
* On other platforms, both paths are an opaque sequence of bytes with no particular encoding.

### `readLink`

```zig
pub fn readLink(dir: Dir, io: Io, sub_path: []const u8, buffer: []u8) ReadLinkError!usize
```

Obtain target of a symbolic link.

Returns how many bytes of `buffer` are populated.

Asserts that the path parameter has no null bytes.

On Windows, `sub_path` should be encoded as [WTF-8](https://wtf-8.codeberg.page/).
On WASI, `sub_path` should be encoded as valid UTF-8.
On other platforms, `sub_path` is an opaque sequence of bytes with no particular encoding.

### `readLinkAbsolute`

```zig
pub fn readLinkAbsolute(io: Io, absolute_path: []const u8, buffer: []u8) ReadLinkError!usize
```

Same as `readLink`, except it asserts the path is absolute.

On Windows, `path` should be encoded as [WTF-8](https://wtf-8.codeberg.page/).
On WASI, `path` should be encoded as valid UTF-8.
On other platforms, `path` is an opaque sequence of bytes with no particular encoding.

### `readFileAlloc`

```zig
pub fn readFileAlloc(dir: Dir, io: Io, sub_path: []const u8, gpa: Allocator, limit: Io.Limit, ) ReadFileAllocError![]u8
```

Reads all the bytes from the named file. On success, caller owns returned
buffer.

If the file size is already known, a better alternative is to initialize a
`File.Reader`.

If the file size cannot be obtained, an error is returned. If
this is a realistic possibility, a better alternative is to initialize a
`File.Reader` which handles this seamlessly.

### `readFileAllocOptions`

```zig
pub fn readFileAllocOptions(dir: Dir, io: Io, sub_path: []const u8, gpa: Allocator, limit: Io.Limit, comptime alignment: std.mem.Alignment, comptime sentinel: ?u8, ) ReadFileAllocError!(if (sentinel) |s| [:s]align(alignment.toByteUnits()) u8 else []align(alignment.toByteUnits()) u8)
```

Reads all the bytes from the named file. On success, caller owns returned
buffer.

If the file size is already known, a better alternative is to initialize a
`File.Reader`.

### `deleteTree`

```zig
pub fn deleteTree(dir: Dir, io: Io, sub_path: []const u8) DeleteTreeError!void
```

Whether `sub_path` describes a symlink, file, or directory, this function
removes it. If it cannot be removed because it is a non-empty directory,
this function recursively removes its entries and then tries again.

This operation is not atomic on most file systems.

On Windows, `sub_path` should be encoded as [WTF-8](https://wtf-8.codeberg.page/).
On WASI, `sub_path` should be encoded as valid UTF-8.
On other platforms, `sub_path` is an opaque sequence of bytes with no particular encoding.

### `deleteTreeMinStackSize`

```zig
pub fn deleteTreeMinStackSize(dir: Dir, io: Io, sub_path: []const u8) DeleteTreeError!void
```

Like `deleteTree`, but only keeps one `Iterator` active at a time to minimize the function's stack size.
This is slower than `deleteTree` but uses less stack space.
On Windows, `sub_path` should be encoded as [WTF-8](https://wtf-8.codeberg.page/).
On WASI, `sub_path` should be encoded as valid UTF-8.
On other platforms, `sub_path` is an opaque sequence of bytes with no particular encoding.

### `copyFile`

```zig
pub fn copyFile(source_dir: Dir, source_path: []const u8, dest_dir: Dir, dest_path: []const u8, io: Io, options: CopyFileOptions, ) CopyFileError!void
```

Atomically creates a new file at `dest_path` within `dest_dir` with the
same contents as `source_path` within `source_dir`.

Whether to overwrite the existing file is determined by `options`.

On Linux, until https://patchwork.kernel.org/patch/9636735/ is merged and
readily available, there is a possibility of power loss or application
termination leaving temporary files present in the same directory as
dest_path.

On Windows, both paths should be encoded as
[WTF-8](https://wtf-8.codeberg.page/). On WASI, both paths should be
encoded as valid UTF-8. On other platforms, both paths are an opaque
sequence of bytes with no particular encoding.

### `copyFileAbsolute`

```zig
pub fn copyFileAbsolute(source_path: []const u8, dest_path: []const u8, io: Io, options: CopyFileOptions, ) !void
```

Same as `copyFile`, except asserts that both `source_path` and `dest_path`
are absolute.

On Windows, both paths should be encoded as [WTF-8](https://wtf-8.codeberg.page/).
On WASI, both paths should be encoded as valid UTF-8.
On other platforms, both paths are an opaque sequence of bytes with no particular encoding.

### `createFileAtomic`

```zig
pub fn createFileAtomic(dir: Dir, io: Io, sub_path: []const u8, options: CreateFileAtomicOptions, ) CreateFileAtomicError!File.Atomic
```

Create an unnamed ephemeral file that can eventually be atomically
materialized into `sub_path`.

The returned `File.Atomic` provides API to emulate the behavior in case it
is not directly supported by the underlying operating system.

* On Windows, `sub_path` should be encoded as [WTF-8](https://wtf-8.codeberg.page/).
* On WASI, `sub_path` should be encoded as valid UTF-8.
* On other platforms, `sub_path` is an opaque sequence of bytes with no particular encoding.

### `setPermissions`

```zig
pub fn setPermissions(dir: Dir, io: Io, new_permissions: File.Permissions) SetPermissionsError!void
```

Also known as "chmod".

The process must have the correct privileges in order to do this
successfully, or must have the effective user ID matching the owner
of the directory. Additionally, the directory must have been opened
with `OpenOptions.iterate` set to `true`.

### `setFilePermissions`

```zig
pub fn setFilePermissions(dir: Dir, io: Io, sub_path: []const u8, new_permissions: File.Permissions, options: SetFilePermissionsOptions, ) SetFilePermissionsError!void
```

Also known as "fchmodat".

### `setOwner`

```zig
pub fn setOwner(dir: Dir, io: Io, owner: ?File.Uid, group: ?File.Gid) SetOwnerError!void
```

Also known as "chown".

The process must have the correct privileges in order to do this
successfully. The group may be changed by the owner of the directory to
any group of which the owner is a member. Additionally, the directory
must have been opened with `OpenOptions.iterate` set to `true`. If the
owner or group is specified as `null`, the ID is not changed.

### `setFileOwner`

```zig
pub fn setFileOwner(dir: Dir, io: Io, sub_path: []const u8, owner: ?File.Uid, group: ?File.Gid, options: SetFileOwnerOptions, ) SetFileOwnerError!void
```

Also known as "fchownat".

### `setTimestamps`

```zig
pub fn setTimestamps(dir: Dir, io: Io, sub_path: []const u8, options: SetTimestampsOptions, ) SetTimestampsError!void
```

The granularity that ultimately is stored depends on the combination of
operating system and file system. When a value as provided that exceeds
this range, the value is clamped to the maximum.

### `setTimestampsNow`

```zig
pub fn setTimestampsNow(dir: Dir, io: Io, sub_path: []const u8, options: SetTimestampsNowOptions, ) SetTimestampsError!void
```

Sets the accessed and modification timestamps of the provided path to the
current wall clock time.

The granularity that ultimately is stored depends on the combination of
operating system and file system.

## Error Sets

- **`PathNameError`**
  
- **`AccessError`**
  
- **`OpenError`**
  
- **`WriteFileError`**
  
- **`ReadFileError`**
  
- **`CreateDirError`**
  
- **`CreateDirPathError`**
  
- **`CreateDirPathOpenError`**
  
- **`StatFileError`**
  
- **`RealPathFileError`**
  
- **`RealPathFileAllocError`**
  
- **`DeleteFileError`**
  
- **`DeleteDirError`**
  
- **`RenameError`**
  
- **`RenamePreserveError`**
  
- **`SymLinkError`**
  
- **`ReadLinkError`**
  
- **`ReadFileAllocError`**
  
- **`DeleteTreeError`**
  
- **`CopyFileError`**
  
- **`CreateFileAtomicError`**
  
- **`SetFilePermissionsError`**
  
- **`SetFileOwnerError`**
  
- **`SetTimestampsError`**
  

## Constants & Variables

- **`Handle`**: 
- **`path`**: 
- **`max_path_bytes`**: The maximum length of a file path that the operating system will accept.
- **`max_name_bytes`**: This represents the maximum size of a `[]u8` file name component that
- **`UpdateFileError`**: 
- **`Stat`**: 
- **`StatError`**: 
- **`RealPathError`**: 
- **`HardLinkOptions`**: 
- **`HardLinkError`**: 
- **`SetPermissionsError`**: 
- **`Permissions`**: 
- **`SetOwnerError`**: 

