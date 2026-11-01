# `std.posix`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/posix.zig`  
> [← Back to Standard Library Index](README.md)

POSIX API layer.

This is more cross platform than using OS-specific APIs, however, it is
lower-level and less portable than other namespaces such as `std.Io` and
`std.process`.

These APIs are generally lowered to libc function calls if and only if libc
is linked. Most operating systems other than Windows, Linux, and WASI
require always linking libc because they use it as the stable syscall ABI.

## Types

### `system`

A libc-compatible API layer.

### Types

#### `fd_t`


#### `pid_t`


#### `pollfd`


#### `uid_t`


#### `gid_t`


#### `mode_t`


#### `nlink_t`


#### `blksize_t`


#### `ino_t`


#### `SIG`


#### `pid_t`


#### `pollfd`


#### `fd_t`


#### `uid_t`


#### `gid_t`


#### `mode_t`


#### `nlink_t`


#### `blksize_t`


#### `ino_t`


#### `SIG`


### Constants & Variables

- **`IFNAMESIZE`**: 
- **`NAME_MAX`**: 
- **`IFNAMESIZE`**: 

### `Stat`

Windows has no concept of `stat`.

On Linux, the `stat` bits/wrappers are removed due to having to maintain
the different varying stat structs per target and libc, leading to runtime
errors. Users targeting Linux should add a comptime check and use statx,
similar to how `Io.File.stat` does.

### `iovec`


### Fields

- `base: [*]u8`
  
- `len: usize`
  

### `iovec_const`


### Fields

- `base: [*]const u8`
  
- `len: usize`
  

### `ACCMODE`


### `TCSA`


### Fields

- `NOW`
  
- `DRAIN`
  
- `FLUSH`
  
- `_`
  

### `winsize`


### Fields

- `row: u16`
  
- `col: u16`
  
- `xpixel: u16`
  
- `ypixel: u16`
  

### `RebootCommand`


## Namespaces

- **`LOCK`**: 
- **`LOG`**: 

## Functions

### `reboot`

```zig
pub fn reboot(cmd: RebootCommand) RebootError!void
```


### `raise`

```zig
pub fn raise(sig: SIG) RaiseError!void
```


### `kill`

```zig
pub fn kill(pid: pid_t, sig: SIG) KillError!void
```


### `read`

```zig
pub fn read(fd: fd_t, buf: []u8) ReadError!usize
```

Returns the number of bytes that were read, which can be less than
buf.len. If 0 bytes were read, that means EOF.
If `fd` is opened in non blocking mode, the function will return error.WouldBlock
when EAGAIN is received.

Linux has a limit on how many bytes may be transferred in one `read` call, which is `0x7ffff000`
on both 64-bit and 32-bit systems. This is due to using a signed C int as the return value, as
well as stuffing the errno codes into the last `4096` values. This is noted on the `read` man page.
The limit on Darwin is `0x7fffffff`, trying to read more than that returns EINVAL.
The corresponding POSIX limit is `maxInt(isize)`.

### `openat`

```zig
pub fn openat(dir_fd: fd_t, file_path: []const u8, flags: O, mode: mode_t) OpenError!fd_t
```

Open and possibly create a file. Keeps trying if it gets interrupted.
`file_path` is relative to the open directory handle `dir_fd`.
On Windows, `file_path` should be encoded as [WTF-8](https://wtf-8.codeberg.page/).
On WASI, `file_path` should be encoded as valid UTF-8.
On other platforms, `file_path` is an opaque sequence of bytes with no particular encoding.
See also `openatZ`.

### `openatZ`

```zig
pub fn openatZ(dir_fd: fd_t, file_path: [*:0]const u8, flags: O, mode: mode_t) OpenError!fd_t
```

Open and possibly create a file. Keeps trying if it gets interrupted.
`file_path` is relative to the open directory handle `dir_fd`.
On Windows, `file_path` should be encoded as [WTF-8](https://wtf-8.codeberg.page/).
On WASI, `file_path` should be encoded as valid UTF-8.
On other platforms, `file_path` is an opaque sequence of bytes with no particular encoding.
See also `openat`.

### `getppid`

```zig
pub fn getppid() pid_t
```


### `getpeername`

```zig
pub fn getpeername(sock: socket_t, addr: *sockaddr, addrlen: *socklen_t) GetSockNameError!void
```


### `fanotify_init`

```zig
pub fn fanotify_init(flags: std.os.linux.fanotify.InitFlags, event_f_flags: u32) FanotifyInitError!i32
```


### `fanotify_mark`

```zig
pub fn fanotify_mark(fanotify_fd: fd_t, flags: std.os.linux.fanotify.MarkFlags, mask: std.os.linux.fanotify.MarkMask, dirfd: fd_t, pathname: ?[]const u8, ) FanotifyMarkError!void
```


### `fanotify_markZ`

```zig
pub fn fanotify_markZ(fanotify_fd: fd_t, flags: std.os.linux.fanotify.MarkFlags, mask: std.os.linux.fanotify.MarkMask, dirfd: fd_t, pathname: ?[*:0]const u8, ) FanotifyMarkError!void
```


### `mmap`

```zig
pub fn mmap(ptr: ?[*]align(page_size_min) u8, length: usize, prot: PROT, flags: MAP, fd: fd_t, offset: u64, ) MMapError![]align(page_size_min) u8
```

Map files or devices into memory.
`length` does not need to be aligned.
Use of a mapped region can result in these signals:
* SIGSEGV - Attempted write into a region mapped as read-only.
* SIGBUS - Attempted  access to a portion of the buffer that does not correspond to the file

### `munmap`

```zig
pub fn munmap(memory: []align(page_size_min) const u8) void
```

Deletes the mappings for the specified address range, causing
further references to addresses within the range to generate invalid memory references.
Note that while POSIX allows unmapping a region in the middle of an existing mapping,
Zig's munmap function does not, for two reasons:
* It violates the Zig principle that resource deallocation must succeed.
* The Windows function, NtFreeVirtualMemory, has this restriction.

### `mremap`

```zig
pub fn mremap(old_address: ?[*]align(page_size_min) u8, old_len: usize, new_len: usize, flags: system.MREMAP, new_address: ?[*]align(page_size_min) u8, ) MRemapError![]align(page_size_min) u8
```


### `msync`

```zig
pub fn msync(memory: []align(page_size_min) u8, flags: i32) MSyncError!void
```


### `sysctl`

```zig
pub fn sysctl(name: []const c_int, oldp: ?*anyopaque, oldlenp: ?*usize, newp: ?*anyopaque, newlen: usize, ) SysCtlError!void
```


### `getSelfPhdrs`

```zig
pub fn getSelfPhdrs() []std.elf.ElfN.Phdr
```


### `dl_iterate_phdr`

```zig
pub fn dl_iterate_phdr(context: anytype, comptime Error: type, comptime callback: fn (info: *dl_phdr_info, size: usize, context: @TypeOf(context)) Error!void, ) Error!void
```


### `sched_getaffinity`

```zig
pub fn sched_getaffinity(pid: pid_t) SchedGetAffinityError!cpu_set_t
```


### `sigaltstack`

```zig
pub fn sigaltstack(ss: ?*const stack_t, old_ss: ?*stack_t) SigaltstackError!void
```


### `sigfillset`

```zig
pub fn sigfillset() sigset_t
```

Return a filled sigset_t.

### `sigemptyset`

```zig
pub fn sigemptyset() sigset_t
```

Return an empty sigset_t.

### `sigaddset`

```zig
pub fn sigaddset(set: *sigset_t, sig: SIG) void
```


### `sigdelset`

```zig
pub fn sigdelset(set: *sigset_t, sig: SIG) void
```


### `sigismember`

```zig
pub fn sigismember(set: *const sigset_t, sig: SIG) bool
```


### `sigaction`

```zig
pub fn sigaction(sig: SIG, noalias act: ?*const Sigaction, noalias oact: ?*Sigaction) void
```

Examine and change a signal action.

### `sigprocmask`

```zig
pub fn sigprocmask(flags: u32, noalias set: ?*const sigset_t, noalias oldset: ?*sigset_t) void
```

Sets the thread signal mask.

### `gethostname`

```zig
pub fn gethostname(name_buffer: *[HOST_NAME_MAX]u8) GetHostNameError![]u8
```


### `uname`

```zig
pub fn uname() utsname
```


### `poll`

```zig
pub fn poll(fds: []pollfd, timeout: i32) PollError!usize
```


### `ppoll`

```zig
pub fn ppoll(fds: []pollfd, timeout: ?*const timespec, mask: ?*const sigset_t) PPollError!usize
```


### `setsockopt`

```zig
pub fn setsockopt(fd: socket_t, level: i32, optname: u32, opt: []const u8) SetSockOptError!void
```

Set a socket's options.

### `memfd_createZ`

```zig
pub fn memfd_createZ(name: [*:0]const u8, flags: u32) MemFdCreateError!fd_t
```


### `memfd_create`

```zig
pub fn memfd_create(name: []const u8, flags: u32) MemFdCreateError!fd_t
```


### `getrusage`

```zig
pub fn getrusage(who: i32) rusage
```


### `tcgetattr`

```zig
pub fn tcgetattr(handle: fd_t) TermiosGetError!termios
```


### `tcsetattr`

```zig
pub fn tcsetattr(handle: fd_t, optional_action: TCSA, termios_p: termios) TermiosSetError!void
```


### `tcgetpgrp`

```zig
pub fn tcgetpgrp(handle: fd_t) TermioGetPgrpError!pid_t
```

Returns the process group ID for the TTY associated with the given handle.

### `tcsetpgrp`

```zig
pub fn tcsetpgrp(handle: fd_t, pgrp: pid_t) TermioSetPgrpError!void
```

Sets the controlling process group ID for given TTY.
handle must be valid fd_t to a TTY associated with calling process.
pgrp must be a valid process group, and the calling process must be a member
of that group.

### `signalfd`

```zig
pub fn signalfd(fd: fd_t, mask: *const sigset_t, flags: u32) !fd_t
```


### `sync`

```zig
pub fn sync() void
```

Write all pending file contents and metadata modifications to all filesystems.

### `syncfs`

```zig
pub fn syncfs(fd: fd_t) SyncError!void
```

Write all pending file contents and metadata modifications to the filesystem which contains the specified file.

### `fdatasync`

```zig
pub fn fdatasync(fd: fd_t) SyncError!void
```

Write all pending file contents for the specified file descriptor to the underlying filesystem, but not necessarily the metadata.

### `prctl`

```zig
pub fn prctl(option: PR, args: anytype) PrctlError!u31
```


### `getrlimit`

```zig
pub fn getrlimit(resource: rlimit_resource) GetrlimitError!rlimit
```


### `setrlimit`

```zig
pub fn setrlimit(resource: rlimit_resource, limits: rlimit) SetrlimitError!void
```


### `mincore`

```zig
pub fn mincore(ptr: [*]align(page_size_min) u8, length: usize, vec: [*]u8) MincoreError!void
```

Determine whether pages are resident in memory.

### `madvise`

```zig
pub fn madvise(ptr: [*]align(page_size_min) u8, length: usize, advice: u32) MadviseError!void
```

Give advice about use of memory.
This syscall is optional and is sometimes configured to be disabled.

### `perf_event_open`

```zig
pub fn perf_event_open(attr: *system.perf_event_attr, pid: pid_t, cpu: i32, group_fd: fd_t, flags: usize, ) PerfEventOpenError!fd_t
```


### `ptrace`

```zig
pub fn ptrace(request: u32, pid: pid_t, addr: usize, data: usize) PtraceError!void
```


### `name_to_handle_at`

```zig
pub fn name_to_handle_at(dirfd: fd_t, pathname: []const u8, handle: *std.os.linux.file_handle, mount_id: *i32, flags: u32, ) NameToFileHandleAtError!void
```


### `name_to_handle_atZ`

```zig
pub fn name_to_handle_atZ(dirfd: fd_t, pathname_z: [*:0]const u8, handle: *std.os.linux.file_handle, mount_id: *i32, flags: u32, ) NameToFileHandleAtError!void
```


### `unexpectedErrno`

```zig
pub fn unexpectedErrno(err: E) UnexpectedError
```

Call this when you made a syscall or something that sets errno
and you get an unexpected error.

### `toPosixPath`

```zig
pub fn toPosixPath(file_path: []const u8) error{NameTooLong}![PATH_MAX - 1:0]u8
```

Used to convert a slice to a null terminated slice on the stack.

## Error Sets

- **`RebootError`**
  
- **`KillError`**
  
- **`OpenError`**
  
- **`GetSockNameError`**
  
- **`FanotifyInitError`**
  
- **`FanotifyMarkError`**
  
- **`MMapError`**
  
- **`MRemapError`**
  
- **`MSyncError`**
  
- **`SysCtlError`**
  
- **`SchedGetAffinityError`**
  
- **`SigaltstackError`**
  
- **`GetHostNameError`**
  
- **`PollError`**
  
- **`PPollError`**
  
- **`SetSockOptError`**
  
- **`MemFdCreateError`**
  
- **`TIOCError`**
  
- **`TermiosGetError`**
  
- **`TermiosSetError`**
  
- **`TermioGetPgrpError`**
  
- **`TermioSetPgrpError`**
  
- **`PrctlError`**
  
- **`SetrlimitError`**
  
- **`MincoreError`**
  
- **`MadviseError`**
  
- **`PerfEventOpenError`**
  
- **`PtraceError`**
  
- **`NameToFileHandleAtError`**
  

## Constants & Variables

- **`AF`**: 
- **`AF_SUN`**: 
- **`AI`**: 
- **`ARCH`**: 
- **`AT`**: 
- **`AT_SUN`**: 
- **`CLOCK`**: 
- **`CPU_COUNT`**: 
- **`CTL`**: 
- **`DT`**: 
- **`E`**: 
- **`Elf_Symndx`**: 
- **`F`**: 
- **`FD_CLOEXEC`**: 
- **`Flock`**: 
- **`HOST_NAME_MAX`**: 
- **`HW`**: 
- **`IFNAMESIZE`**: 
- **`IOV_MAX`**: 
- **`IP`**: 
- **`IPV6`**: 
- **`IPPROTO`**: 
- **`IPTOS`**: 
- **`KERN`**: 
- **`Kevent`**: 
- **`MADV`**: 
- **`MAP`**: 
- **`MAX_ADDR_LEN`**: 
- **`MCL`**: 
- **`MFD`**: 
- **`MLOCK`**: 
- **`MREMAP`**: 
- **`MSF`**: 
- **`MSG`**: 
- **`NAME_MAX`**: 
- **`NSIG`**: 
- **`O`**: 
- **`PATH_MAX`**: 
- **`POLL`**: 
- **`POSIX_FADV`**: 
- **`PR`**: 
- **`PROT`**: 
- **`RLIM`**: 
- **`S`**: 
- **`SA`**: 
- **`SC`**: 
- **`SCM`**: 
- **`SEEK`**: 
- **`SHUT`**: 
- **`SIG`**: 
- **`SIOCGIFINDEX`**: 
- **`SO`**: 
- **`SOCK`**: 
- **`SOL`**: 
- **`IFF`**: 
- **`STDERR_FILENO`**: 
- **`STDIN_FILENO`**: 
- **`STDOUT_FILENO`**: 
- **`SYS`**: 
- **`Sigaction`**: 
- **`T`**: 
- **`TCP`**: 
- **`VDSO`**: 
- **`W`**: 
- **`_SC`**: 
- **`addrinfo`**: 
- **`blkcnt_t`**: 
- **`blksize_t`**: 
- **`clock_t`**: 
- **`clockid_t`**: 
- **`cmsghdr`**: 
- **`cmsg_align`**: 
- **`timerfd_clockid_t`**: 
- **`cpu_set_t`**: 
- **`dev_t`**: 
- **`dl_phdr_info`**: 
- **`fd_t`**: 
- **`file_obj`**: 
- **`gid_t`**: 
- **`ifreq`**: 
- **`in_pktinfo`**: 
- **`in6_pktinfo`**: 
- **`ino_t`**: 
- **`linger`**: 
- **`mode_t`**: 
- **`msghdr`**: 
- **`msghdr_const`**: 
- **`nfds_t`**: 
- **`nlink_t`**: 
- **`off_t`**: 
- **`pid_t`**: 
- **`pollfd`**: 
- **`port_event`**: 
- **`port_notify`**: 
- **`port_t`**: 
- **`rlim_t`**: 
- **`rlimit`**: 
- **`rlimit_resource`**: 
- **`rusage`**: 
- **`sa_family_t`**: 
- **`siginfo_t`**: 
- **`sigset_t`**: 
- **`sigrtmin`**: 
- **`sigrtmax`**: 
- **`sockaddr`**: 
- **`socklen_t`**: 
- **`stack_t`**: 
- **`time_t`**: 
- **`timespec`**: 
- **`timestamp_t`**: 
- **`timeval`**: 
- **`timezone`**: 
- **`UTIME`**: 
- **`uid_t`**: 
- **`user_desc`**: 
- **`utsname`**: 
- **`termios`**: 
- **`CSIZE`**: 
- **`NCCS`**: 
- **`cc_t`**: 
- **`V`**: 
- **`speed_t`**: 
- **`tc_iflag_t`**: 
- **`tc_oflag_t`**: 
- **`tc_cflag_t`**: 
- **`tc_lflag_t`**: 
- **`F_OK`**: 
- **`R_OK`**: 
- **`W_OK`**: 
- **`X_OK`**: 
- **`socket_t`**: 
- **`errno`**: Obtains errno from the return value of a system function call.
- **`RaiseError`**: 
- **`ReadError`**: 
- **`SyncError`**: 
- **`GetrlimitError`**: 
- **`lfs64_abi`**: 
- **`UnexpectedError`**: 

