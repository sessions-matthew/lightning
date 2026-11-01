# `std.c`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/c.zig`  
> [← Back to Standard Library Index](README.md)

## Types

### `ino_t`


### `off_t`


### `UTIME`

For use with `utimensat` and `futimens`.

### Constants & Variables

- **`NOW`**: 
- **`OMIT`**: 
- **`NOW`**: 
- **`OMIT`**: 
- **`NOW`**: 
- **`OMIT`**: 
- **`NOW`**: 
- **`OMIT`**: 

### `timespec`


### Functions

#### `fromTimestamp`

```zig
pub fn fromTimestamp(tm: wasi.timestamp_t) timespec
```


#### `toTimestamp`

```zig
pub fn toTimestamp(ts: timespec) wasi.timestamp_t
```


### `dev_t`


### `mode_t`


### `nlink_t`


### `uid_t`


### `gid_t`


### `blksize_t`


### `passwd`


### `group`


### `blkcnt_t`


### `fd_t`


### `ARCH`


### `timerfd_clockid_t`


### `clockid_t`


### `CPU_COUNT`


### `E`


### `Elf_Symndx`


### `F`

Command flags for fcntl(2).

### Constants & Variables

- **`GETFD`**: 
- **`SETFD`**: 
- **`GETFL`**: 
- **`SETFL`**: 
- **`DUPFD`**: duplicate file descriptor
- **`GETFD`**: get file descriptor flags
- **`SETFD`**: set file descriptor flags
- **`GETFL`**: get file status flags
- **`SETFL`**: set file status flags
- **`GETOWN`**: get SIGIO/SIGURG proc/pgrp
- **`SETOWN`**: set SIGIO/SIGURG proc/pgrp
- **`GETLK`**: get record locking information
- **`SETLK`**: set record locking information
- **`SETLKW`**: F.SETLK; wait if blocked
- **`SETLKWTIMEOUT`**: F.SETLK; wait if blocked, return on timeout
- **`FLUSH_DATA`**: 
- **`CHKCLEAN`**: Used for regression test
- **`PREALLOCATE`**: Preallocate storage
- **`SETSIZE`**: Truncate a file without zeroing space
- **`RDADVISE`**: Issue an advisory read async with no copy to user
- **`RDAHEAD`**: turn read ahead off/on for this fd
- **`NOCACHE`**: turn data caching off/on for this fd
- **`LOG2PHYS`**: file offset to device offset
- **`GETPATH`**: return the full path of the fd
- **`FULLFSYNC`**: fsync + ask the drive to flush to the media
- **`PATHPKG_CHECK`**: find which component (if any) is a package
- **`FREEZE_FS`**: "freeze" all fs operations
- **`THAW_FS`**: "thaw" all fs operations
- **`GLOBAL_NOCACHE`**: turn data caching off/on (globally) for this file
- **`ADDSIGS`**: add detached signatures
- **`ADDFILESIGS`**: add signature from same file (used by dyld for shared libs)
- **`NODIRECT`**: used in conjunction with F.NOCACHE to indicate that DIRECT, synchronous writes
- **`GETPROTECTIONCLASS`**: Get the protection class of a file from the EA, returns int
- **`SETPROTECTIONCLASS`**: Set the protection class of a file for the EA, requires int
- **`LOG2PHYS_EXT`**: file offset to device offset, extended
- **`GETLKPID`**: get record locking information, per-process
- **`SETBACKINGSTORE`**: Mark the file as being the backing store for another filesystem
- **`GETPATH_MTMINFO`**: return the full path of the FD, but error in specific mtmd circumstances
- **`GETCODEDIR`**: Returns the code directory, with associated hashes, to the caller
- **`SETNOSIGPIPE`**: No SIGPIPE generated on EPIPE
- **`GETNOSIGPIPE`**: Status of SIGPIPE for this fd
- **`TRANSCODEKEY`**: For some cases, we need to rewrap the key for AKS/MKB
- **`SINGLE_WRITER`**: file being written to a by single writer... if throttling enabled, writes
- **`GETPROTECTIONLEVEL`**: Get the protection version number for this filesystem
- **`FINDSIGS`**: Add detached code signatures (used by dyld for shared libs)
- **`ADDFILESIGS_FOR_DYLD_SIM`**: Add signature from same file, only if it is signed by Apple (used by dyld for simulator)
- **`BARRIERFSYNC`**: fsync + issue barrier to drive
- **`ADDFILESIGS_RETURN`**: Add signature from same file, return end offset in structure on success
- **`CHECK_LV`**: Check if Library Validation allows this Mach-O file to be mapped into the calling process
- **`PUNCHHOLE`**: Deallocate a range of the file
- **`TRIM_ACTIVE_FILE`**: Trim an active file
- **`DUPFD_CLOEXEC`**: mark the dup with FD_CLOEXEC
- **`RDLCK`**: shared or read lock
- **`UNLCK`**: unlock
- **`WRLCK`**: exclusive or write lock
- **`DUPFD`**: Duplicate file descriptor.
- **`GETFD`**: Get file descriptor flags.
- **`SETFD`**: Set file descriptor flags.
- **`GETFL`**: Get file status flags.
- **`SETFL`**: Set file status flags.
- **`GETOWN`**: Get SIGIO/SIGURG proc/pgrrp.
- **`SETOWN`**: Set SIGIO/SIGURG proc/pgrrp.
- **`GETLK`**: Get record locking information.
- **`SETLK`**: Set record locking information.
- **`SETLKW`**: Set record locking information and wait if blocked.
- **`SETLK_REMOTE`**: Debugging support for remote locks.
- **`READAHEAD`**: Read ahead.
- **`DUPFD_CLOEXEC`**: DUPFD with FD_CLOEXEC set.
- **`DUP2FD_CLOEXEC`**: DUP2FD with FD_CLOEXEC set.
- **`ADD_SEALS`**: 
- **`GET_SEALS`**: 
- **`KINFO`**: Return `kinfo_file` for a file descriptor.
- **`SEAL_SEAL`**: Prevent adding sealings.
- **`SEAL_SHRINK`**: May not shrink
- **`SEAL_GROW`**: May not grow.
- **`SEAL_WRITE`**: May not write.
- **`RDLCK`**: Shared or read lock.
- **`UNLCK`**: Unlock.
- **`WRLCK`**: Exclusive or write lock.
- **`UNLCKSYS`**: Purge locks for a given system ID.
- **`CANCEL`**: Cancel an async lock request.
- **`SETOWN_EX`**: 
- **`GETOWN_EX`**: 
- **`GETOWNER_UIDS`**: 
- **`ULOCK`**: Unlock a previously locked region
- **`LOCK`**: Lock a region for exclusive use
- **`TLOCK`**: Test and lock a region for exclusive use
- **`TEST`**: Test a region for other processes locks
- **`DUPFD`**: Duplicate fildes
- **`GETFD`**: Get fildes flags
- **`SETFD`**: Set fildes flags
- **`GETFL`**: Get file flags
- **`GETXFL`**: Get file flags including open-only flags
- **`SETFL`**: Set file flags
- **`CHKFL`**: Unused
- **`DUP2FD`**: Duplicate fildes at third arg
- **`DUP2FD_CLOEXEC`**: Like DUP2FD with O_CLOEXEC set EINVAL is fildes matches arg1
- **`DUPFD_CLOEXEC`**: Like DUPFD with O_CLOEXEC set
- **`ISSTREAM`**: Is the file desc. a stream ?
- **`PRIV`**: Turn on private access to file
- **`NPRIV`**: Turn off private access to file
- **`QUOTACTL`**: UFS quota call
- **`BLOCKS`**: Get number of BLKSIZE blocks allocated
- **`BLKSIZE`**: Get optimal I/O block size
- **`GETOWN`**: Get owner (socket emulation)
- **`SETOWN`**: Set owner (socket emulation)
- **`REVOKE`**: Object reuse revoke access to file desc.
- **`HASREMOTELOCKS`**: Does vp have NFS locks private to lock manager
- **`SETLK`**: Set file lock
- **`SETLKW`**: Set file lock and wait
- **`ALLOCSP`**: Allocate file space
- **`FREESP`**: Free file space
- **`GETLK`**: Get file lock
- **`OFD_GETLK`**: Get file lock owned by file
- **`OFD_SETLK`**: Set file lock owned by file
- **`OFD_SETLKW`**: Set file lock owned by file and wait
- **`SHARE`**: Set a file share reservation
- **`UNSHARE`**: Remove a file share reservation
- **`BADFD`**: Create Poison FD
- **`RDLCK`**: Read lock
- **`WRLCK`**: Write lock
- **`UNLCK`**: Remove lock(s)
- **`UNLKSYS`**: remove remote locks for a given system
- **`RDACC`**: Read-only share access
- **`WRACC`**: Write-only share access
- **`RWACC`**: Read-Write share access
- **`NODNY`**: Don't deny others access
- **`RDDNY`**: Deny others read share access
- **`WRDNY`**: Deny others write share access
- **`RWDNY`**: Deny others read or write share access
- **`RMDNY`**: private flag: Deny delete share access
- **`DUPFD`**: 
- **`GETFD`**: 
- **`SETFD`**: 
- **`GETFL`**: 
- **`SETFL`**: 
- **`GETOWN`**: 
- **`SETOWN`**: 
- **`GETLK`**: 
- **`SETLK`**: 
- **`SETLKW`**: 
- **`CLOSEM`**: 
- **`MAXFD`**: 
- **`DUPFD_CLOEXEC`**: 
- **`GETNOSIGPIPE`**: 
- **`SETNOSIGPIPE`**: 
- **`GETPATH`**: 
- **`RDLCK`**: 
- **`WRLCK`**: 
- **`UNLCK`**: 
- **`ULOCK`**: 
- **`LOCK`**: 
- **`TLOCK`**: 
- **`TEST`**: 
- **`DUPFD`**: 
- **`GETFD`**: 
- **`RDLCK`**: 
- **`SETFD`**: 
- **`UNLCK`**: 
- **`WRLCK`**: 
- **`GETFL`**: 
- **`SETFL`**: 
- **`GETOWN`**: 
- **`SETOWN`**: 
- **`GETLK`**: 
- **`SETLK`**: 
- **`SETLKW`**: 
- **`DUP2FD`**: 
- **`DUPFD_CLOEXEC`**: 
- **`DUP2FD_CLOEXEC`**: 
- **`GETPATH`**: 
- **`DUPFD`**: 
- **`GETFD`**: 
- **`SETFD`**: 
- **`GETFL`**: 
- **`SETFL`**: 
- **`GETLK`**: 
- **`SETLK`**: 
- **`SETLKW`**: 
- **`DUPFD_CLOEXEC`**: 
- **`RDLCK`**: 
- **`UNLCK`**: 
- **`WRLCK`**: 
- **`DUPFD`**: 
- **`GETFD`**: 
- **`SETFD`**: 
- **`GETFL`**: 
- **`SETFL`**: 
- **`GETOWN`**: 
- **`SETOWN`**: 
- **`GETLK`**: 
- **`SETLK`**: 
- **`SETLKW`**: 
- **`RDLCK`**: 
- **`UNLCK`**: 
- **`WRLCK`**: 
- **`DUPFD`**: 
- **`GETFD`**: 
- **`SETFD`**: 
- **`GETFL`**: 
- **`SETFL`**: 
- **`ISTTY`**: 
- **`GETLK`**: 
- **`SETLK`**: 
- **`SETLKW`**: 
- **`DUPFD_CLOEXEC`**: 
- **`RDLCK`**: 
- **`WRLCK`**: 
- **`UNLCK`**: 

### `Flock`


### `CTL`


### Constants & Variables

- **`SYSCTL`**: 
- **`KERN`**: 
- **`VM`**: 
- **`VFS`**: 
- **`NET`**: 
- **`DEBUG`**: 
- **`HW`**: 
- **`MACHDEP`**: 
- **`USER`**: 
- **`P1003_1B`**: 
- **`KERN`**: 
- **`DEBUG`**: 
- **`UNSPEC`**: 
- **`KERN`**: 
- **`VM`**: 
- **`VFS`**: 
- **`NET`**: 
- **`DEBUG`**: 
- **`HW`**: 
- **`MACHDEP`**: 
- **`USER`**: 
- **`LWKT`**: 
- **`MAXID`**: 
- **`MAXNAME`**: 
- **`UNSPEC`**: 
- **`KERN`**: 
- **`VM`**: 
- **`FS`**: 
- **`NET`**: 
- **`DEBUG`**: 
- **`HW`**: 
- **`MACHDEP`**: 
- **`DDB`**: 
- **`VFS`**: 
- **`UNSPEC`**: 
- **`KERN`**: 
- **`VM`**: 
- **`VFS`**: 
- **`NET`**: 
- **`DEBUG`**: 
- **`HW`**: 
- **`MACHDEP`**: 
- **`USER`**: 
- **`MAXID`**: 

### `CPU`


### Constants & Variables

- **`COMPATIBLE`**: 
- **`ID_AA64ISAR0`**: 
- **`ID_AA64ISAR1`**: 
- **`ID_AA64ISAR2`**: 
- **`ID_AA64MMFR0`**: 
- **`ID_AA64MMFR1`**: 
- **`ID_AA64MMFR2`**: 
- **`AA64PFR0`**: 
- **`AA64PFR1`**: 
- **`AA64SMFR0`**: 
- **`AA64ZFR0`**: 
- **`LIDACTION`**: 
- **`LED_BLINK`**: 

### `HW`


### Constants & Variables

- **`MACHINE`**: 
- **`MODEL`**: 
- **`NCPU`**: 
- **`BYTEORDER`**: 
- **`PHYSMEM`**: 
- **`USERMEM`**: 
- **`PAGESIZE`**: 
- **`DISKNAMES`**: 
- **`DISKSTATS`**: 
- **`FLOATINGPT`**: 
- **`MACHINE_ARCH`**: 
- **`REALMEM`**: 
- **`MACHINE`**: 
- **`MODEL`**: 
- **`NCPU`**: 
- **`BYTEORDER`**: 
- **`PHYSMEM`**: 
- **`USERMEM`**: 
- **`PAGESIZE`**: 
- **`DISKNAMES`**: 
- **`DISKSTATS`**: 
- **`DISKCOUNT`**: 
- **`SENSORS`**: 
- **`CPUSPEED`**: 
- **`SETPERF`**: 
- **`VENDOR`**: 
- **`PRODUCT`**: 
- **`VERSION`**: 
- **`SERIALNO`**: 
- **`UUID`**: 
- **`PHYSMEM64`**: 
- **`USERMEM64`**: 
- **`NCPUFOUND`**: 
- **`ALLOWPOWERDOWN`**: 
- **`PERFPOLICY`**: 
- **`SMT`**: 
- **`NCPUONLINE`**: 
- **`POWER`**: 

### `KERN`


### Constants & Variables

- **`PROC`**: struct: process entries
- **`PROC_PATHNAME`**: path to executable
- **`PROC_FILEDESC`**: file descriptors for process
- **`IOV_MAX`**: 
- **`PROC_ARGS`**: struct: process argv/env
- **`PROC_PATHNAME`**: path to executable
- **`IOV_MAX`**: 
- **`PROC_ALL`**: 
- **`OSTYPE`**: 
- **`PROC_PID`**: 
- **`OSRELEASE`**: 
- **`PROC_PGRP`**: 
- **`OSREV`**: 
- **`PROC_SESSION`**: 
- **`VERSION`**: 
- **`PROC_TTY`**: 
- **`MAXVNODES`**: 
- **`PROC_UID`**: 
- **`MAXPROC`**: 
- **`PROC_RUID`**: 
- **`MAXFILES`**: 
- **`PROC_ARGS`**: 
- **`ARGMAX`**: 
- **`PROC_CWD`**: 
- **`PROC_PATHNAME`**: 
- **`SECURELVL`**: 
- **`PROC_SIGTRAMP`**: 
- **`HOSTNAME`**: 
- **`HOSTID`**: 
- **`CLOCKRATE`**: 
- **`VNODE`**: 
- **`PROC`**: 
- **`FILE`**: 
- **`PROC_FLAGMASK`**: 
- **`PROF`**: 
- **`PROC_FLAG_LWP`**: 
- **`POSIX1`**: 
- **`NGROUPS`**: 
- **`JOB_CONTROL`**: 
- **`SAVED_IDS`**: 
- **`BOOTTIME`**: 
- **`NISDOMAINNAME`**: 
- **`UPDATEINTERVAL`**: 
- **`OSRELDATE`**: 
- **`NTP_PLL`**: 
- **`BOOTFILE`**: 
- **`MAXFILESPERPROC`**: 
- **`MAXPROCPERUID`**: 
- **`DUMPDEV`**: 
- **`IPC`**: 
- **`DUMMY`**: 
- **`PS_STRINGS`**: 
- **`USRSTACK`**: 
- **`LOGSIGEXIT`**: 
- **`IOV_MAX`**: 
- **`MAXPOSIXLOCKSPERUID`**: 
- **`MAXID`**: 
- **`OSTYPE`**: 
- **`OSRELEASE`**: 
- **`OSREV`**: 
- **`VERSION`**: 
- **`MAXVNODES`**: 
- **`MAXPROC`**: 
- **`MAXFILES`**: 
- **`ARGMAX`**: 
- **`SECURELVL`**: 
- **`HOSTNAME`**: 
- **`HOSTID`**: 
- **`CLOCKRATE`**: 
- **`PROF`**: 
- **`POSIX1`**: 
- **`NGROUPS`**: 
- **`JOB_CONTROL`**: 
- **`SAVED_IDS`**: 
- **`BOOTTIME`**: 
- **`DOMAINNAME`**: 
- **`MAXPARTITIONS`**: 
- **`RAWPARTITION`**: 
- **`MAXTHREAD`**: 
- **`NTHREADS`**: 
- **`OSVERSION`**: 
- **`SOMAXCONN`**: 
- **`SOMINCONN`**: 
- **`NOSUIDCOREDUMP`**: 
- **`FSYNC`**: 
- **`SYSVMSG`**: 
- **`SYSVSEM`**: 
- **`SYSVSHM`**: 
- **`MSGBUFSIZE`**: 
- **`MALLOCSTATS`**: 
- **`CPTIME`**: 
- **`NCHSTATS`**: 
- **`FORKSTAT`**: 
- **`NSELCOLL`**: 
- **`TTY`**: 
- **`CCPU`**: 
- **`FSCALE`**: 
- **`NPROCS`**: 
- **`MSGBUF`**: 
- **`POOL`**: 
- **`STACKGAPRANDOM`**: 
- **`SYSVIPC_INFO`**: 
- **`ALLOWKMEM`**: 
- **`WITNESSWATCH`**: 
- **`SPLASSERT`**: 
- **`PROC_ARGS`**: 
- **`NFILES`**: 
- **`TTYCOUNT`**: 
- **`NUMVNODES`**: 
- **`MBSTAT`**: 
- **`WITNESS`**: 
- **`SEMINFO`**: 
- **`SHMINFO`**: 
- **`INTRCNT`**: 
- **`WATCHDOG`**: 
- **`ALLOWDT`**: 
- **`PROC`**: 
- **`MAXCLUSTERS`**: 
- **`EVCOUNT`**: 
- **`TIMECOUNTER`**: 
- **`MAXLOCKSPERUID`**: 
- **`CPTIME2`**: 
- **`CACHEPCT`**: 
- **`FILE`**: 
- **`WXABORT`**: 
- **`CONSDEV`**: 
- **`NETLIVELOCKS`**: 
- **`POOL_DEBUG`**: 
- **`PROC_CWD`**: 
- **`PROC_NOBROADCASTKILL`**: 
- **`PROC_VMMAP`**: 
- **`GLOBAL_PTRACE`**: 
- **`CONSBUFSIZE`**: 
- **`CONSBUF`**: 
- **`AUDIO`**: 
- **`CPUSTATS`**: 
- **`PFSTATUS`**: 
- **`TIMEOUT_STATS`**: 
- **`UTC_OFFSET`**: 
- **`VIDEO`**: 
- **`PROC_ALL`**: 
- **`PROC_PID`**: 
- **`PROC_PGRP`**: 
- **`PROC_SESSION`**: 
- **`PROC_TTY`**: 
- **`PROC_UID`**: 
- **`PROC_RUID`**: 
- **`PROC_KTHREAD`**: 
- **`PROC_SHOW_THREADS`**: 
- **`PROC_ARGV`**: 
- **`PROC_NARGV`**: 
- **`PROC_ENV`**: 
- **`PROC_NENV`**: 
- **`OSTYPE`**: 
- **`OSRELEASE`**: 
- **`OSREV`**: 
- **`VERSION`**: 
- **`MAXVNODES`**: 
- **`MAXPROC`**: 
- **`MAXFILES`**: 
- **`ARGMAX`**: 
- **`SECURELVL`**: 
- **`HOSTNAME`**: 
- **`HOSTID`**: 
- **`CLOCKRATE`**: 
- **`VNODE`**: 
- **`PROC`**: 
- **`FILE`**: 
- **`PROF`**: 
- **`POSIX1`**: 
- **`NGROUPS`**: 
- **`JOB_CONTROL`**: 
- **`SAVED_IDS`**: 
- **`BOOTTIME`**: 
- **`NISDOMAINNAME`**: 
- **`DOMAINNAME`**: 
- **`MAXPARTITIONS`**: 
- **`KDEBUG`**: 
- **`UPDATEINTERVAL`**: 
- **`OSRELDATE`**: 
- **`NTP_PLL`**: 
- **`BOOTFILE`**: 
- **`MAXFILESPERPROC`**: 
- **`MAXPROCPERUID`**: 
- **`DUMPDEV`**: 
- **`IPC`**: 
- **`DUMMY`**: 
- **`PS_STRINGS`**: 
- **`USRSTACK32`**: 
- **`LOGSIGEXIT`**: 
- **`SYMFILE`**: 
- **`PROCARGS`**: 
- **`NETBOOT`**: 
- **`SYSV`**: 
- **`AFFINITY`**: 
- **`TRANSLATE`**: 
- **`CLASSIC`**: 
- **`EXEC`**: 
- **`CLASSICHANDLER`**: 
- **`AIOMAX`**: 
- **`AIOPROCMAX`**: 
- **`AIOTHREADS`**: 
- **`PROCARGS2`**: 
- **`COREFILE`**: 
- **`COREDUMP`**: 
- **`SUGID_COREDUMP`**: 
- **`PROCDELAYTERM`**: 
- **`SHREG_PRIVATIZABLE`**: 
- **`LOW_PRI_WINDOW`**: 
- **`LOW_PRI_DELAY`**: 
- **`POSIX`**: 
- **`USRSTACK64`**: 
- **`NX_PROTECTION`**: 
- **`TFP`**: 
- **`PROCNAME`**: 
- **`THALTSTACK`**: 
- **`SPECULATIVE_READS`**: 
- **`OSVERSION`**: 
- **`SAFEBOOT`**: 
- **`RAGEVNODE`**: 
- **`TTY`**: 
- **`CHECKOPENEVT`**: 
- **`THREADNAME`**: 
- **`MAXID`**: 

### `MADV`


### Constants & Variables

- **`NORMAL`**: 
- **`RANDOM`**: 
- **`SEQUENTIAL`**: 
- **`WILLNEED`**: 
- **`DONTNEED`**: 
- **`FREE`**: 
- **`ZERO_WIRED_PAGES`**: 
- **`FREE_REUSABLE`**: 
- **`FREE_REUSE`**: 
- **`CAN_REUSE`**: 
- **`PAGEOUT`**: 
- **`ZERO`**: 
- **`NORMAL`**: 
- **`RANDOM`**: 
- **`SEQUENTIAL`**: 
- **`WILLNEED`**: 
- **`DONTNEED`**: 
- **`FREE`**: 
- **`NOSYNC`**: 
- **`AUTOSYNC`**: 
- **`NOCORE`**: 
- **`CORE`**: 
- **`PROTECT`**: 
- **`NORMAL`**: no further special treatment
- **`RANDOM`**: expect random page references
- **`SEQUENTIAL`**: expect sequential page references
- **`WILLNEED`**: will need these pages
- **`DONTNEED`**: don't need these pages
- **`FREE`**: contents can be freed
- **`ACCESS_DEFAULT`**: default access
- **`ACCESS_LWP`**: next LWP to access heavily
- **`ACCESS_MANY`**: many processes to access heavily
- **`PURGE`**: contents will be purged
- **`SEQUENTIAL`**: 
- **`CONTROL_END`**: 
- **`DONTNEED`**: 
- **`RANDOM`**: 
- **`WILLNEED`**: 
- **`NORMAL`**: 
- **`CONTROL_START`**: 
- **`FREE`**: 
- **`NOSYNC`**: 
- **`AUTOSYNC`**: 
- **`NOCORE`**: 
- **`CORE`**: 
- **`INVAL`**: 
- **`SETMAP`**: 
- **`NORMAL`**: 
- **`SET_VOLATILE`**: 
- **`SET_NONVOLATILE`**: 
- **`DONTNEED`**: 
- **`WILLNEED`**: 
- **`SEQUENTIAL`**: 
- **`RANDOM`**: 
- **`NORMAL`**: 
- **`RANDOM`**: 
- **`SEQUENTIAL`**: 
- **`WILLNEED`**: 
- **`DONTNEED`**: 
- **`SPACEAVAIL`**: 
- **`FREE`**: 

### `MCL`


### `MLOCK`


### `MSF`


### Constants & Variables

- **`ASYNC`**: 
- **`INVALIDATE`**: 
- **`KILLPAGES`**: invalidate, leave mapped
- **`DEACTIVATE`**: deactivate, leave mapped
- **`SYNC`**: 
- **`SYNC`**: 
- **`ASYNC`**: 
- **`INVALIDATE`**: 
- **`ASYNC`**: 
- **`SYNC`**: 
- **`INVALIDATE`**: 
- **`ASYNC`**: 
- **`INVALIDATE`**: 
- **`SYNC`**: 
- **`SYNC`**: 
- **`ASYNC`**: 
- **`INVALIDATE`**: 

### `POLL`


### Constants & Variables

- **`RDNORM`**: 
- **`WRNORM`**: 
- **`IN`**: 
- **`OUT`**: 
- **`ERR`**: 
- **`HUP`**: 
- **`NVAL`**: 
- **`IN`**: 
- **`PRI`**: 
- **`OUT`**: 
- **`RDNORM`**: 
- **`WRNORM`**: 
- **`RDBAND`**: 
- **`WRBAND`**: 
- **`EXTEND`**: 
- **`ATTRIB`**: 
- **`NLINK`**: 
- **`WRITE`**: 
- **`ERR`**: 
- **`HUP`**: 
- **`NVAL`**: 
- **`STANDARD`**: 
- **`IN`**: any readable data available.
- **`PRI`**: OOB/Urgent readable data.
- **`OUT`**: file descriptor is writeable.
- **`RDNORM`**: non-OOB/URG data available.
- **`WRNORM`**: no write type differentiation.
- **`RDBAND`**: OOB/Urgent readable data.
- **`WRBAND`**: OOB/Urgent data can be written.
- **`INIGNEOF`**: like IN, except ignore EOF.
- **`ERR`**: some poll error occurred.
- **`HUP`**: file descriptor was "hung up".
- **`NVAL`**: requested events "invalid".
- **`STANDARD`**: 
- **`IN`**: 
- **`PRI`**: 
- **`OUT`**: 
- **`RDNORM`**: 
- **`WRNORM`**: 
- **`RDBAND`**: 
- **`WRBAND`**: 
- **`RDHUP`**: Read-side hangup.
- **`ERR`**: Non-testable events (may not be specified in events).
- **`HUP`**: 
- **`NVAL`**: 
- **`REMOVE`**: Events to control `/dev/poll` (not specified in revents)
- **`ONESHOT`**: 
- **`ET`**: 
- **`IN`**: Testable events (may be specified in events field).
- **`PRI`**: 
- **`OUT`**: 
- **`RDNORM`**: 
- **`WRNORM`**: 
- **`RDBAND`**: 
- **`WRBAND`**: 
- **`ERR`**: Non-testable events (may not be specified in events field).
- **`HUP`**: 
- **`NVAL`**: 
- **`IN`**: any readable data available
- **`OUT`**: file descriptor is writeable
- **`RDNORM`**: 
- **`WRNORM`**: 
- **`RDBAND`**: priority readable data
- **`WRBAND`**: priority data can be written
- **`PRI`**: high priority readable data
- **`ERR`**: errors pending
- **`HUP`**: disconnected
- **`NVAL`**: invalid file descriptor
- **`IN`**: 
- **`PRI`**: 
- **`OUT`**: 
- **`ERR`**: 
- **`HUP`**: 
- **`NVAL`**: 
- **`RDNORM`**: 
- **`NORM`**: 
- **`WRNORM`**: 
- **`RDBAND`**: 
- **`WRBAND`**: 
- **`IN`**: 
- **`PRI`**: 
- **`OUT`**: 
- **`ERR`**: 
- **`HUP`**: 
- **`NVAL`**: 
- **`RDNORM`**: 
- **`WRNORM`**: 
- **`WRBAND`**: 
- **`RDHUP`**: 

### `PROT`

Basic memory protection flags

### `RLIM`


### Constants & Variables

- **`INFINITY`**: No limit
- **`SAVED_MAX`**: 
- **`SAVED_CUR`**: 
- **`INFINITY`**: No limit
- **`SAVED_MAX`**: 
- **`SAVED_CUR`**: 

### `S`


### Functions

#### `ISBLK`

```zig
pub fn ISBLK(m: u32) bool
```


#### `ISCHR`

```zig
pub fn ISCHR(m: u32) bool
```


#### `ISDIR`

```zig
pub fn ISDIR(m: u32) bool
```


#### `ISFIFO`

```zig
pub fn ISFIFO(m: u32) bool
```


#### `ISLNK`

```zig
pub fn ISLNK(m: u32) bool
```


#### `ISREG`

```zig
pub fn ISREG(m: u32) bool
```


#### `ISSOCK`

```zig
pub fn ISSOCK(m: u32) bool
```


#### `ISFIFO`

```zig
pub fn ISFIFO(m: u32) bool
```


#### `ISCHR`

```zig
pub fn ISCHR(m: u32) bool
```


#### `ISDIR`

```zig
pub fn ISDIR(m: u32) bool
```


#### `ISBLK`

```zig
pub fn ISBLK(m: u32) bool
```


#### `ISREG`

```zig
pub fn ISREG(m: u32) bool
```


#### `ISLNK`

```zig
pub fn ISLNK(m: u32) bool
```


#### `ISSOCK`

```zig
pub fn ISSOCK(m: u32) bool
```


#### `IWHT`

```zig
pub fn IWHT(m: u32) bool
```


#### `ISFIFO`

```zig
pub fn ISFIFO(m: u32) bool
```


#### `ISCHR`

```zig
pub fn ISCHR(m: u32) bool
```


#### `ISDIR`

```zig
pub fn ISDIR(m: u32) bool
```


#### `ISBLK`

```zig
pub fn ISBLK(m: u32) bool
```


#### `ISREG`

```zig
pub fn ISREG(m: u32) bool
```


#### `ISLNK`

```zig
pub fn ISLNK(m: u32) bool
```


#### `ISSOCK`

```zig
pub fn ISSOCK(m: u32) bool
```


#### `IWHT`

```zig
pub fn IWHT(m: u32) bool
```


#### `ISFIFO`

```zig
pub fn ISFIFO(m: u32) bool
```


#### `ISCHR`

```zig
pub fn ISCHR(m: u32) bool
```


#### `ISDIR`

```zig
pub fn ISDIR(m: u32) bool
```


#### `ISBLK`

```zig
pub fn ISBLK(m: u32) bool
```


#### `ISREG`

```zig
pub fn ISREG(m: u32) bool
```


#### `ISLNK`

```zig
pub fn ISLNK(m: u32) bool
```


#### `ISSOCK`

```zig
pub fn ISSOCK(m: u32) bool
```


#### `ISDOOR`

```zig
pub fn ISDOOR(m: u32) bool
```


#### `ISPORT`

```zig
pub fn ISPORT(m: u32) bool
```


#### `ISFIFO`

```zig
pub fn ISFIFO(m: u32) bool
```


#### `ISCHR`

```zig
pub fn ISCHR(m: u32) bool
```


#### `ISDIR`

```zig
pub fn ISDIR(m: u32) bool
```


#### `ISBLK`

```zig
pub fn ISBLK(m: u32) bool
```


#### `ISREG`

```zig
pub fn ISREG(m: u32) bool
```


#### `ISLNK`

```zig
pub fn ISLNK(m: u32) bool
```


#### `ISSOCK`

```zig
pub fn ISSOCK(m: u32) bool
```


#### `IWHT`

```zig
pub fn IWHT(m: u32) bool
```


#### `ISFIFO`

```zig
pub fn ISFIFO(m: u32) bool
```


#### `ISCHR`

```zig
pub fn ISCHR(m: u32) bool
```


#### `ISDIR`

```zig
pub fn ISDIR(m: u32) bool
```


#### `ISBLK`

```zig
pub fn ISBLK(m: u32) bool
```


#### `ISREG`

```zig
pub fn ISREG(m: u32) bool
```


#### `ISLNK`

```zig
pub fn ISLNK(m: u32) bool
```


#### `ISSOCK`

```zig
pub fn ISSOCK(m: u32) bool
```


#### `IWHT`

```zig
pub fn IWHT(m: u32) bool
```


#### `ISREG`

```zig
pub fn ISREG(m: u32) bool
```


#### `ISLNK`

```zig
pub fn ISLNK(m: u32) bool
```


#### `ISBLK`

```zig
pub fn ISBLK(m: u32) bool
```


#### `ISDIR`

```zig
pub fn ISDIR(m: u32) bool
```


#### `ISCHR`

```zig
pub fn ISCHR(m: u32) bool
```


#### `ISFIFO`

```zig
pub fn ISFIFO(m: u32) bool
```


#### `ISSOCK`

```zig
pub fn ISSOCK(m: u32) bool
```


#### `ISINDEX`

```zig
pub fn ISINDEX(m: u32) bool
```


#### `ISFIFO`

```zig
pub fn ISFIFO(m: u32) bool
```


#### `ISCHR`

```zig
pub fn ISCHR(m: u32) bool
```


#### `ISDIR`

```zig
pub fn ISDIR(m: u32) bool
```


#### `ISBLK`

```zig
pub fn ISBLK(m: u32) bool
```


#### `ISREG`

```zig
pub fn ISREG(m: u32) bool
```


#### `ISLNK`

```zig
pub fn ISLNK(m: u32) bool
```


#### `ISSOCK`

```zig
pub fn ISSOCK(m: u32) bool
```


#### `ISDIR`

```zig
pub fn ISDIR(m: u32) bool
```


#### `ISCHR`

```zig
pub fn ISCHR(m: u32) bool
```


#### `ISBLK`

```zig
pub fn ISBLK(m: u32) bool
```


#### `ISREG`

```zig
pub fn ISREG(m: u32) bool
```


#### `ISFIFO`

```zig
pub fn ISFIFO(m: u32) bool
```


#### `ISLNK`

```zig
pub fn ISLNK(m: u32) bool
```


#### `ISSOCK`

```zig
pub fn ISSOCK(m: u32) bool
```


### Constants & Variables

- **`IFBLK`**: 
- **`IFCHR`**: 
- **`IFDIR`**: 
- **`IFIFO`**: 
- **`IFLNK`**: 
- **`IFMT`**: 
- **`IFREG`**: 
- **`IFSOCK`**: 
- **`IFMT`**: 
- **`IFIFO`**: 
- **`IFCHR`**: 
- **`IFDIR`**: 
- **`IFBLK`**: 
- **`IFREG`**: 
- **`IFLNK`**: 
- **`IFSOCK`**: 
- **`IFWHT`**: 
- **`ISUID`**: 
- **`ISGID`**: 
- **`ISVTX`**: 
- **`IRWXU`**: 
- **`IRUSR`**: 
- **`IWUSR`**: 
- **`IXUSR`**: 
- **`IRWXG`**: 
- **`IRGRP`**: 
- **`IWGRP`**: 
- **`IXGRP`**: 
- **`IRWXO`**: 
- **`IROTH`**: 
- **`IWOTH`**: 
- **`IXOTH`**: 
- **`IFMT`**: 
- **`IFIFO`**: 
- **`IFCHR`**: 
- **`IFDIR`**: 
- **`IFBLK`**: 
- **`IFREG`**: 
- **`IFLNK`**: 
- **`IFSOCK`**: 
- **`IFWHT`**: 
- **`ISUID`**: 
- **`ISGID`**: 
- **`ISVTX`**: 
- **`IRWXU`**: 
- **`IRUSR`**: 
- **`IWUSR`**: 
- **`IXUSR`**: 
- **`IRWXG`**: 
- **`IRGRP`**: 
- **`IWGRP`**: 
- **`IXGRP`**: 
- **`IRWXO`**: 
- **`IROTH`**: 
- **`IWOTH`**: 
- **`IXOTH`**: 
- **`IFMT`**: 
- **`IFIFO`**: 
- **`IFCHR`**: 
- **`IFDIR`**: 
- **`IFBLK`**: 
- **`IFREG`**: 
- **`IFLNK`**: 
- **`IFSOCK`**: 
- **`IFDOOR`**: SunOS 2.6 Door
- **`IFPORT`**: Solaris 10 Event Port
- **`ISUID`**: 
- **`ISGID`**: 
- **`ISVTX`**: 
- **`IRWXU`**: 
- **`IRUSR`**: 
- **`IWUSR`**: 
- **`IXUSR`**: 
- **`IRWXG`**: 
- **`IRGRP`**: 
- **`IWGRP`**: 
- **`IXGRP`**: 
- **`IRWXO`**: 
- **`IROTH`**: 
- **`IWOTH`**: 
- **`IXOTH`**: 
- **`IFMT`**: 
- **`IFIFO`**: 
- **`IFCHR`**: 
- **`IFDIR`**: 
- **`IFBLK`**: 
- **`IFREG`**: 
- **`IFLNK`**: 
- **`IFSOCK`**: 
- **`IFWHT`**: 
- **`ISUID`**: 
- **`ISGID`**: 
- **`ISVTX`**: 
- **`IRWXU`**: 
- **`IRUSR`**: 
- **`IWUSR`**: 
- **`IXUSR`**: 
- **`IRWXG`**: 
- **`IRGRP`**: 
- **`IWGRP`**: 
- **`IXGRP`**: 
- **`IRWXO`**: 
- **`IROTH`**: 
- **`IWOTH`**: 
- **`IXOTH`**: 
- **`IFMT`**: 
- **`IFIFO`**: 
- **`IFCHR`**: 
- **`IFDIR`**: 
- **`IFBLK`**: 
- **`IFREG`**: 
- **`IFLNK`**: 
- **`IFSOCK`**: 
- **`IFWHT`**: 
- **`ISUID`**: 
- **`ISGID`**: 
- **`ISVTX`**: 
- **`IRWXU`**: 
- **`IRUSR`**: 
- **`IWUSR`**: 
- **`IXUSR`**: 
- **`IRWXG`**: 
- **`IRGRP`**: 
- **`IWGRP`**: 
- **`IXGRP`**: 
- **`IRWXO`**: 
- **`IROTH`**: 
- **`IWOTH`**: 
- **`IXOTH`**: 
- **`IREAD`**: 
- **`IEXEC`**: 
- **`IWRITE`**: 
- **`ISTXT`**: 
- **`BLKSIZE`**: 
- **`IFMT`**: 
- **`IFSOCK`**: 
- **`IFLNK`**: 
- **`IFREG`**: 
- **`IFBLK`**: 
- **`IFDIR`**: 
- **`IFCHR`**: 
- **`IFIFO`**: 
- **`INDEX_DIR`**: 
- **`IUMSK`**: 
- **`ISUID`**: 
- **`ISGID`**: 
- **`ISVTX`**: 
- **`IRWXU`**: 
- **`IRUSR`**: 
- **`IWUSR`**: 
- **`IXUSR`**: 
- **`IRWXG`**: 
- **`IRGRP`**: 
- **`IWGRP`**: 
- **`IXGRP`**: 
- **`IRWXO`**: 
- **`IROTH`**: 
- **`IWOTH`**: 
- **`IXOTH`**: 
- **`IFMT`**: 
- **`IFIFO`**: 
- **`IFCHR`**: 
- **`IFDIR`**: 
- **`IFBLK`**: 
- **`IFREG`**: 
- **`IFLNK`**: 
- **`IFSOCK`**: 
- **`ISUID`**: 
- **`ISGID`**: 
- **`ISVTX`**: 
- **`IRWXU`**: 
- **`IRUSR`**: 
- **`IWUSR`**: 
- **`IXUSR`**: 
- **`IRWXG`**: 
- **`IRGRP`**: 
- **`IWGRP`**: 
- **`IXGRP`**: 
- **`IRWXO`**: 
- **`IROTH`**: 
- **`IWOTH`**: 
- **`IXOTH`**: 
- **`BLKSIZE`**: 
- **`IFMT`**: 
- **`IFDIR`**: 
- **`IFCHR`**: 
- **`IFBLK`**: 
- **`IFREG`**: 
- **`IFIFO`**: 
- **`IFLNK`**: 
- **`IFSOCK`**: 
- **`ISUID`**: 
- **`ISGID`**: 
- **`ISVTX`**: 
- **`IRUSR`**: 
- **`IWUSR`**: 
- **`IXUSR`**: 
- **`IREAD`**: 
- **`IWRITE`**: 
- **`IEXEC`**: 
- **`IRGRP`**: 
- **`IWGRP`**: 
- **`IXGRP`**: 
- **`IROTH`**: 
- **`IWOTH`**: 
- **`IXOTH`**: 
- **`IRWXU`**: 
- **`IRWXG`**: 
- **`IRWXO`**: 

### `SA`


### Constants & Variables

- **`ONSTACK`**: take signal on signal stack
- **`RESTART`**: restart system on signal return
- **`RESETHAND`**: reset to SIG.DFL when taking signal
- **`NOCLDSTOP`**: do not generate SIG.CHLD on child stop
- **`NODEFER`**: don't mask the signal we're delivering
- **`NOCLDWAIT`**: don't keep zombies around
- **`SIGINFO`**: signal handler with SIGINFO args
- **`USERTRAMP`**: do not bounce off kernel's sigtramp
- **`@"64REGSET"`**: signal handler with SIGINFO args with 64bit regs information
- **`ONSTACK`**: 
- **`RESTART`**: 
- **`RESETHAND`**: 
- **`NOCLDSTOP`**: 
- **`NODEFER`**: 
- **`NOCLDWAIT`**: 
- **`SIGINFO`**: 
- **`ONSTACK`**: 
- **`RESETHAND`**: 
- **`RESTART`**: 
- **`SIGINFO`**: 
- **`NODEFER`**: 
- **`NOCLDWAIT`**: 
- **`ONSTACK`**: 
- **`RESTART`**: 
- **`RESETHAND`**: 
- **`NOCLDSTOP`**: 
- **`NODEFER`**: 
- **`NOCLDWAIT`**: 
- **`SIGINFO`**: 
- **`ONSTACK`**: 
- **`RESTART`**: 
- **`RESETHAND`**: 
- **`NODEFER`**: 
- **`NOCLDWAIT`**: 
- **`SIGINFO`**: 
- **`NOCLDSTOP`**: 
- **`NOCLDWAIT`**: 
- **`RESETHAND`**: 
- **`NODEFER`**: 
- **`RESTART`**: 
- **`ONSTACK`**: 
- **`SIGINFO`**: 
- **`NOMASK`**: 
- **`STACK`**: 
- **`ONESHOT`**: 
- **`ONSTACK`**: 
- **`RESTART`**: 
- **`RESETHAND`**: 
- **`NOCLDSTOP`**: 
- **`NODEFER`**: 
- **`NOCLDWAIT`**: 
- **`SIGINFO`**: 
- **`NOCLDSTOP`**: 
- **`NOCLDWAIT`**: 
- **`SIGINFO`**: 
- **`ONSTACK`**: 
- **`RESTART`**: 
- **`NODEFER`**: 
- **`RESETHAND`**: 
- **`NOMASK`**: 
- **`ONESHOT`**: 

### `sigval_t`


### `SC`


### `_SC`


### `SEEK`


### Constants & Variables

- **`SET`**: 
- **`CUR`**: 
- **`END`**: 
- **`SET`**: 
- **`CUR`**: 
- **`END`**: 
- **`SET`**: 
- **`CUR`**: 
- **`END`**: 
- **`DATA`**: 
- **`HOLE`**: 

### `SHUT`


### Constants & Variables

- **`RD`**: 
- **`WR`**: 
- **`RDWR`**: 

### `SIG`

Signal types

### Functions

#### `IDX`

```zig
pub inline fn IDX(sig: usize) usize
```


#### `WORD`

```zig
pub inline fn WORD(sig: usize) usize
```


#### `BIT`

```zig
pub inline fn BIT(sig: usize) usize
```


#### `VALID`

```zig
pub inline fn VALID(sig: usize) usize
```


#### `IDX`

```zig
pub inline fn IDX(sig: usize) usize
```


#### `WORD`

```zig
pub inline fn WORD(sig: usize) usize
```


#### `BIT`

```zig
pub inline fn BIT(sig: usize) usize
```


#### `VALID`

```zig
pub inline fn VALID(sig: usize) usize
```


#### `IDX`

```zig
pub inline fn IDX(sig: usize) usize
```


#### `WORD`

```zig
pub inline fn WORD(sig: usize) usize
```


#### `BIT`

```zig
pub inline fn BIT(sig: usize) usize
```


#### `VALID`

```zig
pub inline fn VALID(sig: usize) usize
```


### Constants & Variables

- **`DFL`**: default signal action
- **`IGN`**: ignore signal
- **`GET`**: return current value
- **`SGE`**: signal gets error
- **`ACK`**: acknowledge
- **`ERR`**: Signal error value (returned by signal call on error)
- **`ERR`**: 
- **`DFL`**: 
- **`IGN`**: 
- **`HOLD`**: 
- **`BLOCK`**: block specified signal set
- **`UNBLOCK`**: unblock specified signal set
- **`SETMASK`**: set specified signal set
- **`IOT`**: 
- **`POLL`**: 
- **`BLOCK`**: 
- **`UNBLOCK`**: 
- **`SETMASK`**: 
- **`DFL`**: 
- **`IGN`**: 
- **`ERR`**: 
- **`WORDS`**: 
- **`MAXSIG`**: 
- **`IOT`**: 
- **`LWP`**: 
- **`RTMIN`**: 
- **`RTMAX`**: 
- **`DFL`**: 
- **`ERR`**: 
- **`IGN`**: 
- **`HOLD`**: 
- **`WORDS`**: 
- **`MAXSIG`**: 
- **`BLOCK`**: 
- **`UNBLOCK`**: 
- **`SETMASK`**: 
- **`RTMIN`**: 
- **`RTMAX`**: 
- **`POLL`**: 
- **`IOT`**: 
- **`CLD`**: 
- **`DFL`**: 
- **`IGN`**: 
- **`ERR`**: 
- **`WORDS`**: 
- **`MAXSIG`**: 
- **`BLOCK`**: 
- **`UNBLOCK`**: 
- **`SETMASK`**: 
- **`RTMIN`**: 
- **`RTMAX`**: 
- **`IOT`**: 
- **`DFL`**: 
- **`IGN`**: 
- **`ERR`**: 
- **`BLOCK`**: 
- **`UNBLOCK`**: 
- **`SETMASK`**: 
- **`WORDS`**: 
- **`IOT`**: 
- **`DFL`**: 
- **`IGN`**: 
- **`ERR`**: 
- **`HOLD`**: 
- **`BLOCK`**: 
- **`UNBLOCK`**: 
- **`SETMASK`**: 
- **`IO`**: 
- **`IOT`**: 
- **`DFL`**: 
- **`IGN`**: 
- **`ERR`**: 
- **`CATCH`**: 
- **`HOLD`**: 
- **`BLOCK`**: 
- **`UNBLOCK`**: 
- **`SETMASK`**: 
- **`IOT`**: 
- **`DFL`**: 
- **`ERR`**: 
- **`IGN`**: 
- **`BLOCK`**: 
- **`UNBLOCK`**: 
- **`SETMASK`**: 

### `SIOCGIFINDEX`


### `SYS`


### `Sigaction`

Renamed from `sigaction` to `Sigaction` to avoid conflict with function name.

### Types

#### `handler_fn`


#### `sigaction_fn`


#### `handler_fn`


#### `sigaction_fn`


#### `handler_fn`


#### `sigaction_fn`


#### `handler_fn`


#### `sigaction_fn`


#### `handler_fn`


#### `sigaction_fn`


#### `handler_fn`


#### `sigaction_fn`


#### `handler_fn`


#### `sigaction_fn`


#### `handler_fn`


#### `sigaction_fn`


#### `handler_fn`


#### `sigaction_fn`


#### `handler_fn`


#### `sigaction_fn`


### `T`


### Constants & Variables

- **`IOCGWINSZ`**: 
- **`IOCEXCL`**: 
- **`IOCNXCL`**: 
- **`IOCSCTTY`**: 
- **`IOCGPGRP`**: 
- **`IOCSPGRP`**: 
- **`IOCOUTQ`**: 
- **`IOCSTI`**: 
- **`IOCGWINSZ`**: 
- **`IOCSWINSZ`**: 
- **`IOCMGET`**: 
- **`IOCMBIS`**: 
- **`IOCMBIC`**: 
- **`IOCMSET`**: 
- **`FIONREAD`**: 
- **`IOCCONS`**: 
- **`IOCPKT`**: 
- **`FIONBIO`**: 
- **`IOCNOTTY`**: 
- **`IOCSETD`**: 
- **`IOCGETD`**: 
- **`IOCSBRK`**: 
- **`IOCCBRK`**: 
- **`IOCGSID`**: 
- **`IOCGPTN`**: 
- **`IOCSIG`**: 
- **`CGETA`**: 
- **`CSETA`**: 
- **`CSETAW`**: 
- **`CSETAF`**: 
- **`CSBRK`**: 
- **`CXONC`**: 
- **`CFLSH`**: 
- **`IOCGWINSZ`**: 
- **`IOCSWINSZ`**: 
- **`IOCGSOFTCAR`**: 
- **`IOCSSOFTCAR`**: 
- **`CGETS`**: 
- **`CSETS`**: 
- **`CSANOW`**: 
- **`CSETSW`**: 
- **`CSADRAIN`**: 
- **`CSETSF`**: 
- **`IOCSETLD`**: 
- **`IOCGETLD`**: 
- **`IOCGPPS`**: 
- **`IOCSPPS`**: 
- **`IOCGPPSEV`**: 
- **`IOCGETD`**: 
- **`IOCSETD`**: 
- **`IOCHPCL`**: 
- **`IOCGETP`**: 
- **`IOCSETP`**: 
- **`IOCSETN`**: 
- **`IOCEXCL`**: 
- **`IOCNXCL`**: 
- **`IOCFLUSH`**: 
- **`IOCSETC`**: 
- **`IOCGETC`**: 
- **`IOCLBIS`**: bis local mode bits
- **`IOCLBIC`**: bic local mode bits
- **`IOCLSET`**: set entire local mode word
- **`IOCLGET`**: get local modes
- **`IOCSBRK`**: set break bit
- **`IOCCBRK`**: clear break bit
- **`IOCSDTR`**: set data terminal ready
- **`IOCCDTR`**: clear data terminal ready
- **`IOCSLTC`**: set local special chars
- **`IOCGLTC`**: get local special chars
- **`IOCOUTQ`**: driver output queue size
- **`IOCNOTTY`**: void tty association
- **`IOCSCTTY`**: get a ctty
- **`IOCSTOP`**: stop output, like ^S
- **`IOCSTART`**: start output, like ^Q
- **`IOCGPGRP`**: get pgrp of tty
- **`IOCSPGRP`**: set pgrp of tty
- **`IOCGSID`**: get session id on ctty
- **`IOCSTI`**: simulate terminal input
- **`IOCMSET`**: set all modem bits
- **`IOCMBIS`**: bis modem bits
- **`IOCMBIC`**: bic modem bits
- **`IOCMGET`**: get all modem bits
- **`IOCCBRK`**: 
- **`IOCCDTR`**: 
- **`IOCCONS`**: 
- **`IOCDCDTIMESTAMP`**: 
- **`IOCDRAIN`**: 
- **`IOCEXCL`**: 
- **`IOCEXT`**: 
- **`IOCFLAG_CDTRCTS`**: 
- **`IOCFLAG_CLOCAL`**: 
- **`IOCFLAG_CRTSCTS`**: 
- **`IOCFLAG_MDMBUF`**: 
- **`IOCFLAG_SOFTCAR`**: 
- **`IOCFLUSH`**: 
- **`IOCGETA`**: 
- **`IOCGETD`**: 
- **`IOCGFLAGS`**: 
- **`IOCGLINED`**: 
- **`IOCGPGRP`**: 
- **`IOCGQSIZE`**: 
- **`IOCGRANTPT`**: 
- **`IOCGSID`**: 
- **`IOCGSIZE`**: 
- **`IOCGWINSZ`**: 
- **`IOCMBIC`**: 
- **`IOCMBIS`**: 
- **`IOCMGET`**: 
- **`IOCMSET`**: 
- **`IOCM_CAR`**: 
- **`IOCM_CD`**: 
- **`IOCM_CTS`**: 
- **`IOCM_DSR`**: 
- **`IOCM_DTR`**: 
- **`IOCM_LE`**: 
- **`IOCM_RI`**: 
- **`IOCM_RNG`**: 
- **`IOCM_RTS`**: 
- **`IOCM_SR`**: 
- **`IOCM_ST`**: 
- **`IOCNOTTY`**: 
- **`IOCNXCL`**: 
- **`IOCOUTQ`**: 
- **`IOCPKT`**: 
- **`IOCPKT_DATA`**: 
- **`IOCPKT_DOSTOP`**: 
- **`IOCPKT_FLUSHREAD`**: 
- **`IOCPKT_FLUSHWRITE`**: 
- **`IOCPKT_IOCTL`**: 
- **`IOCPKT_NOSTOP`**: 
- **`IOCPKT_START`**: 
- **`IOCPKT_STOP`**: 
- **`IOCPTMGET`**: 
- **`IOCPTSNAME`**: 
- **`IOCRCVFRAME`**: 
- **`IOCREMOTE`**: 
- **`IOCSBRK`**: 
- **`IOCSCTTY`**: 
- **`IOCSDTR`**: 
- **`IOCSETA`**: 
- **`IOCSETAF`**: 
- **`IOCSETAW`**: 
- **`IOCSETD`**: 
- **`IOCSFLAGS`**: 
- **`IOCSIG`**: 
- **`IOCSLINED`**: 
- **`IOCSPGRP`**: 
- **`IOCSQSIZE`**: 
- **`IOCSSIZE`**: 
- **`IOCSTART`**: 
- **`IOCSTAT`**: 
- **`IOCSTI`**: 
- **`IOCSTOP`**: 
- **`IOCSWINSZ`**: 
- **`IOCUCNTL`**: 
- **`IOCXMTFRAME`**: 
- **`CGETA`**: 
- **`CSETA`**: 
- **`CSETAF`**: 
- **`CSETAW`**: 
- **`CWAITEVENT`**: 
- **`CSBRK`**: 
- **`CFLSH`**: 
- **`CXONC`**: 
- **`CQUERYCONNECTED`**: 
- **`CGETBITS`**: 
- **`CSETDTR`**: 
- **`CSETRTS`**: 
- **`IOCGWINSZ`**: 
- **`IOCSWINSZ`**: 
- **`CVTIME`**: 
- **`IOCGPGRP`**: 
- **`IOCSPGRP`**: 
- **`IOCSCTTY`**: 
- **`IOCMGET`**: 
- **`IOCMSET`**: 
- **`IOCSBRK`**: 
- **`IOCCBRK`**: 
- **`IOCMBIS`**: 
- **`IOCMBIC`**: 
- **`IOCGSID`**: 
- **`FIONREAD`**: 
- **`FIONBIO`**: 
- **`IOCCBRK`**: 
- **`IOCCDTR`**: 
- **`IOCCONS`**: 
- **`IOCDCDTIMESTAMP`**: 
- **`IOCDRAIN`**: 
- **`IOCEXCL`**: 
- **`IOCEXT`**: 
- **`IOCFLAG_CDTRCTS`**: 
- **`IOCFLAG_CLOCAL`**: 
- **`IOCFLAG_CRTSCTS`**: 
- **`IOCFLAG_MDMBUF`**: 
- **`IOCFLAG_SOFTCAR`**: 
- **`IOCFLUSH`**: 
- **`IOCGETA`**: 
- **`IOCGETD`**: 
- **`IOCGFLAGS`**: 
- **`IOCGLINED`**: 
- **`IOCGPGRP`**: 
- **`IOCGQSIZE`**: 
- **`IOCGRANTPT`**: 
- **`IOCGSID`**: 
- **`IOCGSIZE`**: 
- **`IOCGWINSZ`**: 
- **`IOCMBIC`**: 
- **`IOCMBIS`**: 
- **`IOCMGET`**: 
- **`IOCMSET`**: 
- **`IOCM_CAR`**: 
- **`IOCM_CD`**: 
- **`IOCM_CTS`**: 
- **`IOCM_DSR`**: 
- **`IOCM_DTR`**: 
- **`IOCM_LE`**: 
- **`IOCM_RI`**: 
- **`IOCM_RNG`**: 
- **`IOCM_RTS`**: 
- **`IOCM_SR`**: 
- **`IOCM_ST`**: 
- **`IOCNOTTY`**: 
- **`IOCNXCL`**: 
- **`IOCOUTQ`**: 
- **`IOCPKT`**: 
- **`IOCPKT_DATA`**: 
- **`IOCPKT_DOSTOP`**: 
- **`IOCPKT_FLUSHREAD`**: 
- **`IOCPKT_FLUSHWRITE`**: 
- **`IOCPKT_IOCTL`**: 
- **`IOCPKT_NOSTOP`**: 
- **`IOCPKT_START`**: 
- **`IOCPKT_STOP`**: 
- **`IOCPTMGET`**: 
- **`IOCPTSNAME`**: 
- **`IOCRCVFRAME`**: 
- **`IOCREMOTE`**: 
- **`IOCSBRK`**: 
- **`IOCSCTTY`**: 
- **`IOCSDTR`**: 
- **`IOCSETA`**: 
- **`IOCSETAF`**: 
- **`IOCSETAW`**: 
- **`IOCSETD`**: 
- **`IOCSFLAGS`**: 
- **`IOCSIG`**: 
- **`IOCSLINED`**: 
- **`IOCSPGRP`**: 
- **`IOCSQSIZE`**: 
- **`IOCSSIZE`**: 
- **`IOCSTART`**: 
- **`IOCSTAT`**: 
- **`IOCSTI`**: 
- **`IOCSTOP`**: 
- **`IOCSWINSZ`**: 
- **`IOCUCNTL`**: 
- **`IOCXMTFRAME`**: 
- **`IOCMODG`**: 
- **`IOCMODS`**: 
- **`IOCM_LE`**: 
- **`IOCM_DTR`**: 
- **`IOCM_RTS`**: 
- **`IOCM_ST`**: 
- **`IOCM_SR`**: 
- **`IOCM_CTS`**: 
- **`IOCM_CAR`**: 
- **`IOCM_CD`**: 
- **`IOCM_RNG`**: 
- **`IOCM_RI`**: 
- **`IOCM_DSR`**: 
- **`IOCEXCL`**: 
- **`IOCNXCL`**: 
- **`IOCFLUSH`**: 
- **`IOCGETA`**: 
- **`IOCSETA`**: 
- **`IOCSETAW`**: 
- **`IOCSETAF`**: 
- **`IOCGETD`**: 
- **`IOCSETD`**: 
- **`IOCSBRK`**: 
- **`IOCCBRK`**: 
- **`IOCSDTR`**: 
- **`IOCCDTR`**: 
- **`IOCGPGRP`**: 
- **`IOCSPGRP`**: 
- **`IOCOUTQ`**: 
- **`IOCSTI`**: 
- **`IOCNOTTY`**: 
- **`IOCPKT`**: 
- **`IOCPKT_DATA`**: 
- **`IOCPKT_FLUSHREAD`**: 
- **`IOCPKT_FLUSHWRITE`**: 
- **`IOCPKT_STOP`**: 
- **`IOCPKT_START`**: 
- **`IOCPKT_NOSTOP`**: 
- **`IOCPKT_DOSTOP`**: 
- **`IOCPKT_IOCTL`**: 
- **`IOCSTOP`**: 
- **`IOCSTART`**: 
- **`IOCMSET`**: 
- **`IOCMBIS`**: 
- **`IOCMBIC`**: 
- **`IOCMGET`**: 
- **`IOCREMOTE`**: 
- **`IOCGWINSZ`**: 
- **`IOCSWINSZ`**: 
- **`IOCUCNTL`**: 
- **`IOCSTAT`**: 
- **`IOCGSID`**: 
- **`IOCCONS`**: 
- **`IOCSCTTY`**: 
- **`IOCEXT`**: 
- **`IOCSIG`**: 
- **`IOCDRAIN`**: 
- **`IOCMSDTRWAIT`**: 
- **`IOCMGDTRWAIT`**: 
- **`IOCTIMESTAMP`**: 
- **`IOCDCDTIMESTAMP`**: 
- **`IOCSDRAINWAIT`**: 
- **`IOCGDRAINWAIT`**: 
- **`IOCISPTMASTER`**: 
- **`IOCGPGRP`**: 
- **`IOCSPGRP`**: 
- **`CGETS`**: 
- **`CSETS`**: 
- **`CSETSW`**: 
- **`CSETSF`**: 
- **`CFLSH`**: 
- **`IOCGWINSZ`**: 
- **`IOCSCTTY`**: 
- **`IOCSTI`**: 
- **`IOCNOTTY`**: 
- **`IOCSWINSZ`**: 
- **`IOCGPTN`**: 

### `IOCPARM_MASK`


### `TFD`


### `VDSO`


### `W`


### Functions

#### `EXITSTATUS`

```zig
pub fn EXITSTATUS(x: u32) u8
```


#### `TERMSIG`

```zig
pub fn TERMSIG(x: u32) SIG
```


#### `STOPSIG`

```zig
pub fn STOPSIG(x: u32) SIG
```


#### `IFEXITED`

```zig
pub fn IFEXITED(x: u32) bool
```


#### `IFSTOPPED`

```zig
pub fn IFSTOPPED(x: u32) bool
```


#### `IFSIGNALED`

```zig
pub fn IFSIGNALED(x: u32) bool
```


#### `EXITSTATUS`

```zig
pub fn EXITSTATUS(s: u32) u8
```


#### `TERMSIG`

```zig
pub fn TERMSIG(s: u32) SIG
```


#### `STOPSIG`

```zig
pub fn STOPSIG(s: u32) SIG
```


#### `IFEXITED`

```zig
pub fn IFEXITED(s: u32) bool
```


#### `IFSTOPPED`

```zig
pub fn IFSTOPPED(s: u32) bool
```


#### `IFSIGNALED`

```zig
pub fn IFSIGNALED(s: u32) bool
```


#### `EXITSTATUS`

```zig
pub fn EXITSTATUS(s: u32) u8
```


#### `TERMSIG`

```zig
pub fn TERMSIG(s: u32) SIG
```


#### `STOPSIG`

```zig
pub fn STOPSIG(s: u32) SIG
```


#### `IFEXITED`

```zig
pub fn IFEXITED(s: u32) bool
```


#### `IFCONTINUED`

```zig
pub fn IFCONTINUED(s: u32) bool
```


#### `IFSTOPPED`

```zig
pub fn IFSTOPPED(s: u32) bool
```


#### `IFSIGNALED`

```zig
pub fn IFSIGNALED(s: u32) bool
```


#### `EXITSTATUS`

```zig
pub fn EXITSTATUS(s: u32) u8
```


#### `TERMSIG`

```zig
pub fn TERMSIG(s: u32) SIG
```


#### `STOPSIG`

```zig
pub fn STOPSIG(s: u32) SIG
```


#### `IFEXITED`

```zig
pub fn IFEXITED(s: u32) bool
```


#### `IFCONTINUED`

```zig
pub fn IFCONTINUED(s: u32) bool
```


#### `IFSTOPPED`

```zig
pub fn IFSTOPPED(s: u32) bool
```


#### `IFSIGNALED`

```zig
pub fn IFSIGNALED(s: u32) bool
```


#### `EXITSTATUS`

```zig
pub fn EXITSTATUS(s: u32) u8
```


#### `TERMSIG`

```zig
pub fn TERMSIG(s: u32) SIG
```


#### `STOPSIG`

```zig
pub fn STOPSIG(s: u32) SIG
```


#### `IFEXITED`

```zig
pub fn IFEXITED(s: u32) bool
```


#### `IFSTOPPED`

```zig
pub fn IFSTOPPED(s: u32) bool
```


#### `IFSIGNALED`

```zig
pub fn IFSIGNALED(s: u32) bool
```


#### `EXITSTATUS`

```zig
pub fn EXITSTATUS(s: u32) u8
```


#### `TERMSIG`

```zig
pub fn TERMSIG(s: u32) SIG
```


#### `STOPSIG`

```zig
pub fn STOPSIG(s: u32) SIG
```


#### `IFEXITED`

```zig
pub fn IFEXITED(s: u32) bool
```


#### `IFSTOPPED`

```zig
pub fn IFSTOPPED(s: u32) bool
```


#### `IFSIGNALED`

```zig
pub fn IFSIGNALED(s: u32) bool
```


#### `EXITSTATUS`

```zig
pub fn EXITSTATUS(s: u32) u8
```


#### `TERMSIG`

```zig
pub fn TERMSIG(s: u32) SIG
```


#### `STOPSIG`

```zig
pub fn STOPSIG(s: u32) SIG
```


#### `IFEXITED`

```zig
pub fn IFEXITED(s: u32) bool
```


#### `IFCONTINUED`

```zig
pub fn IFCONTINUED(s: u32) bool
```


#### `IFSTOPPED`

```zig
pub fn IFSTOPPED(s: u32) bool
```


#### `IFSIGNALED`

```zig
pub fn IFSIGNALED(s: u32) bool
```


#### `EXITSTATUS`

```zig
pub fn EXITSTATUS(s: u32) u8
```


#### `STOPSIG`

```zig
pub fn STOPSIG(s: u32) SIG
```


#### `TERMSIG`

```zig
pub fn TERMSIG(s: u32) SIG
```


#### `IFEXITED`

```zig
pub fn IFEXITED(s: u32) bool
```


#### `IFSTOPPED`

```zig
pub fn IFSTOPPED(s: u32) bool
```


#### `IFSIGNALED`

```zig
pub fn IFSIGNALED(s: u32) bool
```


#### `IFCONTINUED`

```zig
pub fn IFCONTINUED(s: u32) bool
```


### Constants & Variables

- **`NOHANG`**: [XSI] no hang in wait/no child to reap
- **`UNTRACED`**: [XSI] notify on stop, untraced child
- **`NOHANG`**: 
- **`UNTRACED`**: 
- **`STOPPED`**: 
- **`CONTINUED`**: 
- **`NOWAIT`**: 
- **`EXITED`**: 
- **`TRAPPED`**: 
- **`EXITED`**: 
- **`TRAPPED`**: 
- **`UNTRACED`**: 
- **`STOPPED`**: 
- **`CONTINUED`**: 
- **`NOHANG`**: 
- **`NOWAIT`**: 
- **`NOHANG`**: 
- **`UNTRACED`**: 
- **`STOPPED`**: 
- **`CONTINUED`**: 
- **`NOWAIT`**: 
- **`EXITED`**: 
- **`TRAPPED`**: 
- **`NOHANG`**: 
- **`UNTRACED`**: 
- **`CONTINUED`**: 
- **`STOPPED`**: 
- **`NOWAIT`**: 
- **`EXITED`**: 
- **`TRAPPED`**: 
- **`NOHANG`**: 
- **`UNTRACED`**: 
- **`CONTINUED`**: 
- **`EXITED`**: 
- **`STOPPED`**: 
- **`NOWAIT`**: 
- **`NOHANG`**: 
- **`UNTRACED`**: 
- **`CONTINUED`**: 
- **`NOHANG`**: 
- **`UNTRACED`**: 
- **`STOPPED`**: 
- **`EXITED`**: 
- **`CONTINUED`**: 
- **`NOWAIT`**: 

### `accept_filter_arg`


### `clock_t`


### `cpu_set_t`


### `dl_phdr_info`


### `epoll_event`


### `ifreq`


### `in_pktinfo`


### `in6_pktinfo`


### `itimerspec`


### `linger`


### `msghdr`


### `msghdr_const`


### `mmsghdr`


### `cmsghdr`


### `nfds_t`


### `perf_event_attr`


### `pid_t`


### `pollfd`


### `rlim_t`


### `rlimit`


### `rlimit_resource`


### Constants & Variables

- **`AS`**: 
- **`AS`**: 
- **`AS`**: 
- **`AS`**: 
- **`AS`**: 

### `rusage`


### Constants & Variables

- **`SELF`**: 
- **`CHILDREN`**: 
- **`SELF`**: 
- **`CHILDREN`**: 
- **`THREAD`**: 
- **`SELF`**: 
- **`CHILDREN`**: 
- **`SELF`**: 
- **`CHILDREN`**: 
- **`THREAD`**: 
- **`SELF`**: 
- **`CHILDREN`**: 

### `siginfo_t`


### `sigset_t`


### `sigval`


### `addrinfo`


### `sockaddr`


### Types

#### `storage`


#### `in`


#### `in6`


#### `un`

UNIX domain socket

#### `storage`


#### `in`


#### `in6`


#### `un`


#### `storage`


#### `in`


#### `in6`


#### `un`

Definitions for UNIX IPC domain.

#### `storage`


#### `in`


#### `in6`


#### `un`

Definitions for UNIX IPC domain.

#### `storage`


#### `in`


#### `in6`


#### `un`


#### `storage`


#### `in`


#### `in6`


#### `un`


#### `storage`


#### `in`


#### `in6`


#### `un`

Definitions for UNIX IPC domain.

#### `in`


#### `in6`


#### `un`


### Constants & Variables

- **`SS_MAXSIZE`**: 
- **`SS_MAXSIZE`**: 
- **`SS_MAXSIZE`**: 
- **`SS_MAXSIZE`**: 
- **`SS_MAXSIZE`**: 
- **`SS_MAXSIZE`**: 
- **`SS_MAXSIZE`**: 

### `socklen_t`


### `in_port_t`


### `sa_family_t`


### `AF`


### Constants & Variables

- **`UNSPEC`**: 
- **`UNIX`**: 
- **`LOCAL`**: 
- **`INET`**: 
- **`AX25`**: 
- **`IPX`**: 
- **`APPLETALK`**: 
- **`NETROM`**: 
- **`BRIDGE`**: 
- **`ATMPVC`**: 
- **`X25`**: 
- **`INET6`**: 
- **`ROSE`**: 
- **`DECnet`**: 
- **`NETBEUI`**: 
- **`SECURITY`**: 
- **`KEY`**: 
- **`NETLINK`**: 
- **`ROUTE`**: 
- **`PACKET`**: 
- **`ASH`**: 
- **`ECONET`**: 
- **`ATMSVC`**: 
- **`RDS`**: 
- **`SNA`**: 
- **`IRDA`**: 
- **`PPPOX`**: 
- **`WANPIPE`**: 
- **`LLC`**: 
- **`CAN`**: 
- **`TIPC`**: 
- **`BLUETOOTH`**: 
- **`IUCV`**: 
- **`RXRPC`**: 
- **`ISDN`**: 
- **`PHONET`**: 
- **`IEEE802154`**: 
- **`CAIF`**: 
- **`ALG`**: 
- **`NFC`**: 
- **`VSOCK`**: 
- **`KCM`**: 
- **`QIPCRTR`**: 
- **`MAX`**: 
- **`UNSPEC`**: 
- **`LOCAL`**: 
- **`UNIX`**: 
- **`INET`**: 
- **`SYS_CONTROL`**: 
- **`IMPLINK`**: 
- **`PUP`**: 
- **`CHAOS`**: 
- **`NS`**: 
- **`ISO`**: 
- **`OSI`**: 
- **`ECMA`**: 
- **`DATAKIT`**: 
- **`CCITT`**: 
- **`SNA`**: 
- **`DECnet`**: 
- **`DLI`**: 
- **`LAT`**: 
- **`HYLINK`**: 
- **`APPLETALK`**: 
- **`ROUTE`**: 
- **`LINK`**: 
- **`XTP`**: 
- **`COIP`**: 
- **`CNT`**: 
- **`RTIP`**: 
- **`IPX`**: 
- **`SIP`**: 
- **`PIP`**: 
- **`ISDN`**: 
- **`E164`**: 
- **`KEY`**: 
- **`INET6`**: 
- **`NATM`**: 
- **`SYSTEM`**: 
- **`NETBIOS`**: 
- **`PPP`**: 
- **`MAX`**: 
- **`UNSPEC`**: 
- **`UNIX`**: 
- **`LOCAL`**: 
- **`FILE`**: 
- **`INET`**: 
- **`IMPLINK`**: 
- **`PUP`**: 
- **`CHAOS`**: 
- **`NETBIOS`**: 
- **`ISO`**: 
- **`OSI`**: 
- **`ECMA`**: 
- **`DATAKIT`**: 
- **`CCITT`**: 
- **`SNA`**: 
- **`DECnet`**: 
- **`DLI`**: 
- **`LAT`**: 
- **`HYLINK`**: 
- **`APPLETALK`**: 
- **`ROUTE`**: 
- **`LINK`**: 
- **`pseudo_XTP`**: 
- **`COIP`**: 
- **`CNT`**: 
- **`pseudo_RTIP`**: 
- **`IPX`**: 
- **`SIP`**: 
- **`pseudo_PIP`**: 
- **`ISDN`**: 
- **`E164`**: 
- **`pseudo_KEY`**: 
- **`INET6`**: 
- **`NATM`**: 
- **`ATM`**: 
- **`pseudo_HDRCMPLT`**: 
- **`NETGRAPH`**: 
- **`SLOW`**: 
- **`SCLUSTER`**: 
- **`ARP`**: 
- **`BLUETOOTH`**: 
- **`IEEE80211`**: 
- **`INET_SDP`**: 
- **`INET6_SDP`**: 
- **`MAX`**: 
- **`UNSPEC`**: 
- **`UNIX`**: 
- **`LOCAL`**: 
- **`FILE`**: 
- **`INET`**: 
- **`IMPLINK`**: 
- **`PUP`**: 
- **`CHAOS`**: 
- **`NS`**: 
- **`NBS`**: 
- **`ECMA`**: 
- **`DATAKIT`**: 
- **`CCITT`**: 
- **`SNA`**: 
- **`DECnet`**: 
- **`DLI`**: 
- **`LAT`**: 
- **`HYLINK`**: 
- **`APPLETALK`**: 
- **`NIT`**: 
- **`@"802"`**: 
- **`OSI`**: 
- **`X25`**: 
- **`OSINET`**: 
- **`GOSIP`**: 
- **`IPX`**: 
- **`ROUTE`**: 
- **`LINK`**: 
- **`INET6`**: 
- **`KEY`**: 
- **`NCA`**: 
- **`POLICY`**: 
- **`INET_OFFLOAD`**: 
- **`TRILL`**: 
- **`PACKET`**: 
- **`LX_NETLINK`**: 
- **`MAX`**: 
- **`UNSPEC`**: 
- **`LOCAL`**: 
- **`UNIX`**: 
- **`INET`**: 
- **`IMPLINK`**: 
- **`PUP`**: 
- **`CHAOS`**: 
- **`NS`**: 
- **`ISO`**: 
- **`OSI`**: 
- **`ECMA`**: 
- **`DATAKIT`**: 
- **`CCITT`**: 
- **`SNA`**: 
- **`DECnet`**: 
- **`DLI`**: 
- **`LAT`**: 
- **`HYLINK`**: 
- **`APPLETALK`**: 
- **`OROUTE`**: 
- **`LINK`**: 
- **`COIP`**: 
- **`CNT`**: 
- **`IPX`**: 
- **`INET6`**: 
- **`ISDN`**: 
- **`E164`**: 
- **`NATM`**: 
- **`ARP`**: 
- **`BLUETOOTH`**: 
- **`IEEE80211`**: 
- **`MPLS`**: 
- **`ROUTE`**: 
- **`CAN`**: 
- **`ETHER`**: 
- **`MAX`**: 
- **`UNSPEC`**: 
- **`OSI`**: 
- **`UNIX`**: 
- **`LOCAL`**: 
- **`INET`**: 
- **`IMPLINK`**: 
- **`PUP`**: 
- **`CHAOS`**: 
- **`NETBIOS`**: 
- **`ISO`**: 
- **`ECMA`**: 
- **`DATAKIT`**: 
- **`CCITT`**: 
- **`SNA`**: 
- **`DLI`**: 
- **`LAT`**: 
- **`HYLINK`**: 
- **`APPLETALK`**: 
- **`ROUTE`**: 
- **`LINK`**: 
- **`COIP`**: 
- **`CNT`**: 
- **`IPX`**: 
- **`SIP`**: 
- **`ISDN`**: 
- **`INET6`**: 
- **`NATM`**: 
- **`ATM`**: 
- **`NETGRAPH`**: 
- **`BLUETOOTH`**: 
- **`MPLS`**: 
- **`MAX`**: 
- **`UNSPEC`**: 
- **`INET`**: 
- **`APPLETALK`**: 
- **`ROUTE`**: 
- **`LINK`**: 
- **`INET6`**: 
- **`DLI`**: 
- **`IPX`**: 
- **`NOTIFY`**: 
- **`LOCAL`**: 
- **`UNIX`**: 
- **`BLUETOOTH`**: 
- **`MAX`**: 
- **`UNSPEC`**: 
- **`UNIX`**: 
- **`LOCAL`**: 
- **`INET`**: 
- **`APPLETALK`**: 
- **`INET6`**: 
- **`KEY`**: 
- **`ROUTE`**: 
- **`SNA`**: 
- **`MPLS`**: 
- **`BLUETOOTH`**: 
- **`ISDN`**: 
- **`MAX`**: 
- **`UNSPEC`**: 
- **`LOCAL`**: 
- **`UNIX`**: 
- **`INET`**: 
- **`INET6`**: 
- **`MAX`**: 

### `PF`


### Constants & Variables

- **`UNSPEC`**: 
- **`UNIX`**: 
- **`LOCAL`**: 
- **`INET`**: 
- **`AX25`**: 
- **`IPX`**: 
- **`APPLETALK`**: 
- **`NETROM`**: 
- **`BRIDGE`**: 
- **`ATMPVC`**: 
- **`X25`**: 
- **`PF_INET6`**: 
- **`PF_ROSE`**: 
- **`PF_DECnet`**: 
- **`PF_NETBEUI`**: 
- **`PF_SECURITY`**: 
- **`PF_KEY`**: 
- **`PF_NETLINK`**: 
- **`PF_ROUTE`**: 
- **`PF_PACKET`**: 
- **`PF_ASH`**: 
- **`PF_ECONET`**: 
- **`PF_ATMSVC`**: 
- **`PF_RDS`**: 
- **`PF_SNA`**: 
- **`PF_IRDA`**: 
- **`PF_PPPOX`**: 
- **`PF_WANPIPE`**: 
- **`PF_LLC`**: 
- **`PF_CAN`**: 
- **`PF_TIPC`**: 
- **`PF_BLUETOOTH`**: 
- **`PF_IUCV`**: 
- **`PF_RXRPC`**: 
- **`PF_ISDN`**: 
- **`PF_PHONET`**: 
- **`PF_IEEE802154`**: 
- **`PF_CAIF`**: 
- **`PF_ALG`**: 
- **`PF_NFC`**: 
- **`PF_VSOCK`**: 
- **`PF_KCM`**: 
- **`PF_QIPCRTR`**: 
- **`PF_MAX`**: 
- **`UNSPEC`**: 
- **`LOCAL`**: 
- **`UNIX`**: 
- **`INET`**: 
- **`IMPLINK`**: 
- **`PUP`**: 
- **`CHAOS`**: 
- **`NS`**: 
- **`ISO`**: 
- **`OSI`**: 
- **`ECMA`**: 
- **`DATAKIT`**: 
- **`CCITT`**: 
- **`SNA`**: 
- **`DECnet`**: 
- **`DLI`**: 
- **`LAT`**: 
- **`HYLINK`**: 
- **`APPLETALK`**: 
- **`ROUTE`**: 
- **`LINK`**: 
- **`XTP`**: 
- **`COIP`**: 
- **`CNT`**: 
- **`SIP`**: 
- **`IPX`**: 
- **`RTIP`**: 
- **`PIP`**: 
- **`ISDN`**: 
- **`KEY`**: 
- **`INET6`**: 
- **`NATM`**: 
- **`SYSTEM`**: 
- **`NETBIOS`**: 
- **`PPP`**: 
- **`MAX`**: 
- **`UNSPEC`**: 
- **`LOCAL`**: 
- **`UNIX`**: 
- **`INET`**: 
- **`IMPLINK`**: 
- **`PUP`**: 
- **`CHAOS`**: 
- **`NETBIOS`**: 
- **`ISO`**: 
- **`OSI`**: 
- **`ECMA`**: 
- **`DATAKIT`**: 
- **`CCITT`**: 
- **`DECnet`**: 
- **`DLI`**: 
- **`LAT`**: 
- **`HYLINK`**: 
- **`APPLETALK`**: 
- **`ROUTE`**: 
- **`LINK`**: 
- **`XTP`**: 
- **`COIP`**: 
- **`CNT`**: 
- **`SIP`**: 
- **`IPX`**: 
- **`RTIP`**: 
- **`PIP`**: 
- **`ISDN`**: 
- **`KEY`**: 
- **`INET6`**: 
- **`NATM`**: 
- **`ATM`**: 
- **`NETGRAPH`**: 
- **`SLOW`**: 
- **`SCLUSTER`**: 
- **`ARP`**: 
- **`BLUETOOTH`**: 
- **`IEEE80211`**: 
- **`INET_SDP`**: 
- **`INET6_SDP`**: 
- **`MAX`**: 
- **`UNSPEC`**: 
- **`UNIX`**: 
- **`LOCAL`**: 
- **`FILE`**: 
- **`INET`**: 
- **`IMPLINK`**: 
- **`PUP`**: 
- **`CHAOS`**: 
- **`NS`**: 
- **`NBS`**: 
- **`ECMA`**: 
- **`DATAKIT`**: 
- **`CCITT`**: 
- **`SNA`**: 
- **`DECnet`**: 
- **`DLI`**: 
- **`LAT`**: 
- **`HYLINK`**: 
- **`APPLETALK`**: 
- **`NIT`**: 
- **`@"802"`**: 
- **`OSI`**: 
- **`X25`**: 
- **`OSINET`**: 
- **`GOSIP`**: 
- **`IPX`**: 
- **`ROUTE`**: 
- **`LINK`**: 
- **`INET6`**: 
- **`KEY`**: 
- **`NCA`**: 
- **`POLICY`**: 
- **`TRILL`**: 
- **`PACKET`**: 
- **`LX_NETLINK`**: 
- **`MAX`**: 
- **`UNSPEC`**: 
- **`LOCAL`**: 
- **`UNIX`**: 
- **`INET`**: 
- **`IMPLINK`**: 
- **`PUP`**: 
- **`CHAOS`**: 
- **`NS`**: 
- **`ISO`**: 
- **`OSI`**: 
- **`ECMA`**: 
- **`DATAKIT`**: 
- **`CCITT`**: 
- **`SNA`**: 
- **`DECnet`**: 
- **`DLI`**: 
- **`LAT`**: 
- **`HYLINK`**: 
- **`APPLETALK`**: 
- **`OROUTE`**: 
- **`LINK`**: 
- **`COIP`**: 
- **`CNT`**: 
- **`INET6`**: 
- **`IPX`**: 
- **`ISDN`**: 
- **`E164`**: 
- **`NATM`**: 
- **`ARP`**: 
- **`BLUETOOTH`**: 
- **`MPLS`**: 
- **`ROUTE`**: 
- **`CAN`**: 
- **`ETHER`**: 
- **`MAX`**: 
- **`INET6`**: 
- **`IMPLINK`**: 
- **`ROUTE`**: 
- **`ISO`**: 
- **`PIP`**: 
- **`CHAOS`**: 
- **`DATAKIT`**: 
- **`INET`**: 
- **`APPLETALK`**: 
- **`SIP`**: 
- **`OSI`**: 
- **`CNT`**: 
- **`LINK`**: 
- **`HYLINK`**: 
- **`MAX`**: 
- **`KEY`**: 
- **`PUP`**: 
- **`COIP`**: 
- **`SNA`**: 
- **`LOCAL`**: 
- **`NETBIOS`**: 
- **`NATM`**: 
- **`BLUETOOTH`**: 
- **`UNSPEC`**: 
- **`NETGRAPH`**: 
- **`ECMA`**: 
- **`IPX`**: 
- **`DLI`**: 
- **`ATM`**: 
- **`CCITT`**: 
- **`ISDN`**: 
- **`RTIP`**: 
- **`LAT`**: 
- **`UNIX`**: 
- **`XTP`**: 
- **`DECnet`**: 
- **`UNSPEC`**: 
- **`INET`**: 
- **`ROUTE`**: 
- **`LINK`**: 
- **`INET6`**: 
- **`LOCAL`**: 
- **`UNIX`**: 
- **`BLUETOOTH`**: 
- **`UNSPEC`**: 
- **`LOCAL`**: 
- **`UNIX`**: 
- **`INET`**: 
- **`APPLETALK`**: 
- **`INET6`**: 
- **`DECnet`**: 
- **`KEY`**: 
- **`ROUTE`**: 
- **`SNA`**: 
- **`MPLS`**: 
- **`BLUETOOTH`**: 
- **`ISDN`**: 
- **`MAX`**: 
- **`LOCAL`**: 
- **`UNIX`**: 
- **`INET`**: 
- **`INET6`**: 
- **`UNSPEC`**: 
- **`MAX`**: 

### `DT`


### Constants & Variables

- **`UNKNOWN`**: 
- **`FIFO`**: 
- **`CHR`**: 
- **`DIR`**: 
- **`BLK`**: 
- **`REG`**: 
- **`LNK`**: 
- **`SOCK`**: 
- **`WHT`**: 
- **`UNKNOWN`**: 
- **`FIFO`**: 
- **`CHR`**: 
- **`DIR`**: 
- **`BLK`**: 
- **`REG`**: 
- **`LNK`**: 
- **`SOCK`**: 
- **`WHT`**: 
- **`DBF`**: 

### `MSG`


### Constants & Variables

- **`OOB`**: 
- **`PEEK`**: 
- **`DONTROUTE`**: 
- **`EOR`**: 
- **`TRUNC`**: 
- **`CTRUNC`**: 
- **`WAITALL`**: 
- **`DONTWAIT`**: 
- **`BCAST`**: 
- **`MCAST`**: 
- **`EOF`**: 
- **`NOSIGNAL`**: 
- **`TRUNC`**: 
- **`CTRUNC`**: 
- **`PEEK`**: 
- **`OOB`**: 
- **`DONTROUTE`**: 
- **`WAITALL`**: 
- **`DONTWAIT`**: 
- **`NOSIGNAL`**: 
- **`EOR`**: 
- **`OOB`**: 
- **`PEEK`**: 
- **`DONTROUTE`**: 
- **`EOR`**: 
- **`TRUNC`**: 
- **`CTRUNC`**: 
- **`WAITALL`**: 
- **`DONTWAIT`**: 
- **`EOF`**: 
- **`NOTIFICATION`**: 
- **`NBIO`**: 
- **`COMPAT`**: 
- **`SOCALLBCK`**: 
- **`NOSIGNAL`**: 
- **`CMSG_CLOEXEC`**: 
- **`WAITFORONE`**: 
- **`MORETOCOME`**: 
- **`TLSAPPDATA`**: 
- **`OOB`**: 
- **`PEEK`**: 
- **`DONTROUTE`**: 
- **`EOR`**: 
- **`TRUNC`**: 
- **`CTRUNC`**: 
- **`WAITALL`**: 
- **`DONTWAIT`**: 
- **`BCAST`**: 
- **`MCAST`**: 
- **`NOSIGNAL`**: 
- **`CMSG_CLOEXEC`**: 
- **`NBIO`**: 
- **`WAITFORONE`**: 
- **`NOTIFICATION`**: 
- **`OOB`**: 
- **`PEEK`**: 
- **`DONTROUTE`**: 
- **`EOR`**: 
- **`TRUNC`**: 
- **`CTRUNC`**: 
- **`WAITALL`**: 
- **`DONTWAIT`**: 
- **`BCAST`**: 
- **`MCAST`**: 
- **`NOSIGNAL`**: 
- **`CMSG_CLOEXEC`**: 
- **`WAITFORONE`**: 
- **`CMSG_CLOFORK`**: 
- **`OOB`**: 
- **`PEEK`**: 
- **`DONTROUTE`**: 
- **`EOR`**: 
- **`TRUNC`**: 
- **`CTRUNC`**: 
- **`WAITALL`**: 
- **`DONTWAIT`**: 
- **`NOSIGNAL`**: 
- **`SYNC`**: 
- **`CMSG_CLOEXEC`**: 
- **`CMSG_CLOFORK`**: 
- **`FBLOCKING`**: 
- **`FNONBLOCKING`**: 
- **`OOB`**: 
- **`PEEK`**: 
- **`DONTROUTE`**: 
- **`EOR`**: 
- **`CTRUNC`**: 
- **`TRUNC`**: 
- **`WAITALL`**: 
- **`DONTWAIT`**: 
- **`NOTIFICATION`**: 
- **`NOSIGNAL`**: 
- **`CMSG_CLOEXEC`**: 
- **`CMSG_CLOFORK`**: 

### `SOCK`


### Constants & Variables

- **`STREAM`**: 
- **`DGRAM`**: 
- **`RAW`**: 
- **`RDM`**: 
- **`SEQPACKET`**: 
- **`MAXADDRLEN`**: 
- **`CLOEXEC`**: Not actually supported by Darwin, but Zig supplies a shim.
- **`NONBLOCK`**: Not actually supported by Darwin, but Zig supplies a shim.
- **`STREAM`**: 
- **`DGRAM`**: 
- **`RAW`**: 
- **`RDM`**: 
- **`SEQPACKET`**: 
- **`CLOEXEC`**: 
- **`NONBLOCK`**: 
- **`DGRAM`**: Datagram.
- **`STREAM`**: STREAM.
- **`RAW`**: Raw-protocol interface.
- **`RDM`**: Reliably-delivered message.
- **`SEQPACKET`**: Sequenced packed stream.
- **`NONBLOCK`**: 
- **`NDELAY`**: 
- **`CLOEXEC`**: 
- **`STREAM`**: 
- **`DGRAM`**: 
- **`RAW`**: 
- **`RDM`**: 
- **`SEQPACKET`**: 
- **`CONN_DGRAM`**: 
- **`DCCP`**: 
- **`CLOEXEC`**: 
- **`NONBLOCK`**: 
- **`NOSIGPIPE`**: 
- **`FLAGS_MASK`**: 
- **`STREAM`**: 
- **`DGRAM`**: 
- **`RAW`**: 
- **`RDM`**: 
- **`SEQPACKET`**: 
- **`MAXADDRLEN`**: 
- **`CLOEXEC`**: 
- **`NONBLOCK`**: 
- **`STREAM`**: 
- **`DGRAM`**: 
- **`RAW`**: 
- **`SEQPACKET`**: 
- **`MISC`**: 
- **`NONBLOCK`**: 
- **`CLOEXEC`**: 
- **`STREAM`**: 
- **`DGRAM`**: 
- **`RAW`**: 
- **`RDM`**: 
- **`SEQPACKET`**: 
- **`CLOEXEC`**: 
- **`NONBLOCK`**: 
- **`STREAM`**: 
- **`DGRAM`**: 
- **`RAW`**: 
- **`RDM`**: 
- **`SEQPACKET`**: 
- **`NONBLOCK`**: 
- **`CLOEXEC`**: 

### `TCP`


### Constants & Variables

- **`NODELAY`**: 
- **`MAXSEG`**: 

### `IPPROTO`


### Constants & Variables

- **`ICMP`**: 
- **`ICMPV6`**: 
- **`TCP`**: 
- **`UDP`**: 
- **`IP`**: 
- **`IPV6`**: 
- **`RAW`**: 
- **`IP`**: dummy for IP
- **`ICMP`**: control message protocol
- **`TCP`**: tcp
- **`UDP`**: user datagram protocol
- **`IPV6`**: IP6 header
- **`RAW`**: raw IP packet
- **`HOPOPTS`**: IP6 hop-by-hop options
- **`IGMP`**: group mgmt protocol
- **`GGP`**: gateway^2 (deprecated)
- **`IPV4`**: IPv4 encapsulation
- **`IPIP`**: for compatibility
- **`ST`**: Stream protocol II
- **`EGP`**: exterior gateway protocol
- **`PIGP`**: private interior gateway
- **`RCCMON`**: BBN RCC Monitoring
- **`NVPII`**: network voice protocol
- **`PUP`**: pup
- **`ARGUS`**: Argus
- **`EMCON`**: EMCON
- **`XNET`**: Cross Net Debugger
- **`CHAOS`**: Chaos
- **`MUX`**: Multiplexing
- **`MEAS`**: DCN Measurement Subsystems
- **`HMP`**: Host Monitoring
- **`PRM`**: Packet Radio Measurement
- **`IDP`**: xns idp
- **`TRUNK1`**: Trunk-1
- **`TRUNK2`**: Trunk-2
- **`LEAF1`**: Leaf-1
- **`LEAF2`**: Leaf-2
- **`RDP`**: Reliable Data
- **`IRTP`**: Reliable Transaction
- **`TP`**: tp-4 w/ class negotiation
- **`BLT`**: Bulk Data Transfer
- **`NSP`**: Network Services
- **`INP`**: Merit Internodal
- **`DCCP`**: Datagram Congestion Control Protocol
- **`@"3PC"`**: Third Party Connect
- **`IDPR`**: InterDomain Policy Routing
- **`XTP`**: XTP
- **`DDP`**: Datagram Delivery
- **`CMTP`**: Control Message Transport
- **`TPXX`**: TP++ Transport
- **`IL`**: IL transport protocol
- **`SDRP`**: Source Demand Routing
- **`ROUTING`**: IP6 routing header
- **`FRAGMENT`**: IP6 fragmentation header
- **`IDRP`**: InterDomain Routing
- **`RSVP`**: resource reservation
- **`GRE`**: General Routing Encap.
- **`MHRP`**: Mobile Host Routing
- **`BHA`**: BHA
- **`ESP`**: IP6 Encap Sec. Payload
- **`AH`**: IP6 Auth Header
- **`INLSP`**: Integ. Net Layer Security
- **`SWIPE`**: IP with encryption
- **`NHRP`**: Next Hop Resolution
- **`MOBILE`**: IP Mobility
- **`TLSP`**: Transport Layer Security
- **`SKIP`**: SKIP
- **`ICMPV6`**: ICMP6
- **`NONE`**: IP6 no next header
- **`DSTOPTS`**: IP6 destination option
- **`AHIP`**: any host internal protocol
- **`CFTP`**: CFTP
- **`HELLO`**: "hello" routing protocol
- **`SATEXPAK`**: SATNET/Backroom EXPAK
- **`KRYPTOLAN`**: Kryptolan
- **`RVD`**: Remote Virtual Disk
- **`IPPC`**: Pluribus Packet Core
- **`ADFS`**: Any distributed FS
- **`SATMON`**: Satnet Monitoring
- **`VISA`**: VISA Protocol
- **`IPCV`**: Packet Core Utility
- **`CPNX`**: Comp. Prot. Net. Executive
- **`CPHB`**: Comp. Prot. HeartBeat
- **`WSN`**: Wang Span Network
- **`PVP`**: Packet Video Protocol
- **`BRSATMON`**: BackRoom SATNET Monitoring
- **`ND`**: Sun net disk proto (temp.)
- **`WBMON`**: WIDEBAND Monitoring
- **`WBEXPAK`**: WIDEBAND EXPAK
- **`EON`**: ISO cnlp
- **`VMTP`**: VMTP
- **`SVMTP`**: Secure VMTP
- **`VINES`**: Banyon VINES
- **`TTP`**: TTP
- **`IGP`**: NSFNET-IGP
- **`DGP`**: dissimilar gateway prot.
- **`TCF`**: TCF
- **`IGRP`**: Cisco/GXS IGRP
- **`OSPFIGP`**: OSPFIGP
- **`SRPC`**: Strite RPC protocol
- **`LARP`**: Locus Address Resoloution
- **`MTP`**: Multicast Transport
- **`AX25`**: AX.25 Frames
- **`IPEIP`**: IP encapsulated in IP
- **`MICP`**: Mobile Int.ing control
- **`SCCSP`**: Semaphore Comm. security
- **`ETHERIP`**: Ethernet IP encapsulation
- **`ENCAP`**: encapsulation header
- **`APES`**: any private encr. scheme
- **`GMTP`**: GMTP
- **`IPCOMP`**: payload compression (IPComp)
- **`SCTP`**: SCTP
- **`MH`**: IPv6 Mobility Header
- **`UDPLITE`**: UDP-Lite
- **`HIP`**: IP6 Host Identity Protocol
- **`SHIM6`**: IP6 Shim6 Protocol
- **`PIM`**: Protocol Independent Mcast
- **`CARP`**: CARP
- **`PGM`**: PGM
- **`MPLS`**: MPLS-in-IP
- **`PFSYNC`**: PFSYNC
- **`RESERVED_253`**: Reserved
- **`RESERVED_254`**: Reserved
- **`IP`**: dummy for IP
- **`HOPOPTS`**: Hop by hop header for IPv6
- **`ICMP`**: control message protocol
- **`IGMP`**: group control protocol
- **`GGP`**: gateway^2 (deprecated)
- **`ENCAP`**: IP in IP encapsulation
- **`TCP`**: tcp
- **`EGP`**: exterior gateway protocol
- **`PUP`**: pup
- **`UDP`**: user datagram protocol
- **`IDP`**: xns idp
- **`IPV6`**: IPv6 encapsulated in IP
- **`ROUTING`**: Routing header for IPv6
- **`FRAGMENT`**: Fragment header for IPv6
- **`RSVP`**: rsvp
- **`ESP`**: IPsec Encap. Sec. Payload
- **`AH`**: IPsec Authentication Hdr.
- **`ICMPV6`**: ICMP for IPv6
- **`NONE`**: No next header for IPv6
- **`DSTOPTS`**: Destination options
- **`HELLO`**: "hello" routing protocol
- **`ND`**: UNOFFICIAL net disk proto
- **`EON`**: ISO clnp
- **`OSPF`**: OSPF
- **`PIM`**: PIM routing protocol
- **`SCTP`**: Stream Control
- **`RAW`**: raw IP packet
- **`PROTO_SDP`**: Sockets Direct Protocol
- **`IP`**: dummy for IP
- **`HOPOPTS`**: IP6 hop-by-hop options
- **`ICMP`**: control message protocol
- **`IGMP`**: group mgmt protocol
- **`GGP`**: gateway^2 (deprecated)
- **`IPV4`**: IP header
- **`IPIP`**: IP inside IP
- **`TCP`**: tcp
- **`EGP`**: exterior gateway protocol
- **`PUP`**: pup
- **`UDP`**: user datagram protocol
- **`IDP`**: xns idp
- **`TP`**: tp-4 w/ class negotiation
- **`DCCP`**: DCCP
- **`IPV6`**: IP6 header
- **`ROUTING`**: IP6 routing header
- **`FRAGMENT`**: IP6 fragmentation header
- **`RSVP`**: resource reservation
- **`GRE`**: GRE encaps RFC 1701
- **`ESP`**: encap. security payload
- **`AH`**: authentication header
- **`MOBILE`**: IP Mobility RFC 2004
- **`IPV6_ICMP`**: IPv6 ICMP
- **`ICMPV6`**: ICMP6
- **`NONE`**: IP6 no next header
- **`DSTOPTS`**: IP6 destination option
- **`EON`**: ISO cnlp
- **`ETHERIP`**: Ethernet-in-IP
- **`ENCAP`**: encapsulation header
- **`PIM`**: Protocol indep. multicast
- **`IPCOMP`**: IP Payload Comp. Protocol
- **`VRRP`**: VRRP RFC 2338
- **`CARP`**: Common Address Resolution Protocol
- **`L2TP`**: L2TPv3
- **`SCTP`**: SCTP
- **`PFSYNC`**: PFSYNC
- **`RAW`**: raw IP packet
- **`IP`**: 
- **`ICMP`**: 
- **`TCP`**: 
- **`UDP`**: 
- **`IPV6`**: 
- **`RAW`**: 
- **`HOPOPTS`**: 
- **`IGMP`**: 
- **`GGP`**: 
- **`IPV4`**: 
- **`IPIP`**: 
- **`ST`**: 
- **`EGP`**: 
- **`PIGP`**: 
- **`RCCMON`**: 
- **`NVPII`**: 
- **`PUP`**: 
- **`ARGUS`**: 
- **`EMCON`**: 
- **`XNET`**: 
- **`CHAOS`**: 
- **`MUX`**: 
- **`MEAS`**: 
- **`HMP`**: 
- **`PRM`**: 
- **`IDP`**: 
- **`TRUNK1`**: 
- **`TRUNK2`**: 
- **`LEAF1`**: 
- **`LEAF2`**: 
- **`RDP`**: 
- **`IRTP`**: 
- **`TP`**: 
- **`BLT`**: 
- **`NSP`**: 
- **`INP`**: 
- **`SEP`**: 
- **`@"3PC"`**: 
- **`IDPR`**: 
- **`XTP`**: 
- **`DDP`**: 
- **`CMTP`**: 
- **`TPXX`**: 
- **`IL`**: 
- **`SDRP`**: 
- **`ROUTING`**: 
- **`FRAGMENT`**: 
- **`IDRP`**: 
- **`RSVP`**: 
- **`GRE`**: 
- **`MHRP`**: 
- **`BHA`**: 
- **`ESP`**: 
- **`AH`**: 
- **`INLSP`**: 
- **`SWIPE`**: 
- **`NHRP`**: 
- **`MOBILE`**: 
- **`TLSP`**: 
- **`SKIP`**: 
- **`ICMPV6`**: 
- **`NONE`**: 
- **`DSTOPTS`**: 
- **`AHIP`**: 
- **`CFTP`**: 
- **`HELLO`**: 
- **`SATEXPAK`**: 
- **`KRYPTOLAN`**: 
- **`RVD`**: 
- **`IPPC`**: 
- **`ADFS`**: 
- **`SATMON`**: 
- **`VISA`**: 
- **`IPCV`**: 
- **`CPNX`**: 
- **`CPHB`**: 
- **`WSN`**: 
- **`PVP`**: 
- **`BRSATMON`**: 
- **`ND`**: 
- **`WBMON`**: 
- **`WBEXPAK`**: 
- **`EON`**: 
- **`VMTP`**: 
- **`SVMTP`**: 
- **`VINES`**: 
- **`TTP`**: 
- **`IGP`**: 
- **`DGP`**: 
- **`TCF`**: 
- **`IGRP`**: 
- **`OSPFIGP`**: 
- **`SRPC`**: 
- **`LARP`**: 
- **`MTP`**: 
- **`AX25`**: 
- **`IPEIP`**: 
- **`MICP`**: 
- **`SCCSP`**: 
- **`ETHERIP`**: 
- **`ENCAP`**: 
- **`APES`**: 
- **`GMTP`**: 
- **`IPCOMP`**: 
- **`PIM`**: 
- **`CARP`**: 
- **`PGM`**: 
- **`PFSYNC`**: 
- **`DIVERT`**: 
- **`MAX`**: 
- **`DONE`**: 
- **`UNKNOWN`**: 
- **`IP`**: 
- **`HOPOPTS`**: 
- **`ICMP`**: 
- **`IGMP`**: 
- **`TCP`**: 
- **`UDP`**: 
- **`IPV6`**: 
- **`ROUTING`**: 
- **`FRAGMENT`**: 
- **`ESP`**: 
- **`AH`**: 
- **`ICMPV6`**: 
- **`NONE`**: 
- **`DSTOPTS`**: 
- **`ETHERIP`**: 
- **`RAW`**: 
- **`MAX`**: 
- **`IP`**: dummy for IP
- **`HOPOPTS`**: IP6 hop-by-hop options
- **`ICMP`**: control message protocol
- **`IGMP`**: group mgmt protocol
- **`GGP`**: gateway^2 (deprecated)
- **`IPV4`**: IP header
- **`IPIP`**: IP inside IP
- **`TCP`**: tcp
- **`EGP`**: exterior gateway protocol
- **`PUP`**: pup
- **`UDP`**: user datagram protocol
- **`IDP`**: xns idp
- **`TP`**: tp-4 w/ class negotiation
- **`IPV6`**: IP6 header
- **`ROUTING`**: IP6 routing header
- **`FRAGMENT`**: IP6 fragmentation header
- **`RSVP`**: resource reservation
- **`GRE`**: GRE encaps RFC 1701
- **`ESP`**: encap. security payload
- **`AH`**: authentication header
- **`MOBILE`**: IP Mobility RFC 2004
- **`IPV6_ICMP`**: IPv6 ICMP
- **`ICMPV6`**: ICMP6
- **`NONE`**: IP6 no next header
- **`DSTOPTS`**: IP6 destination option
- **`EON`**: ISO cnlp
- **`ETHERIP`**: Ethernet-in-IP
- **`ENCAP`**: encapsulation header
- **`PIM`**: Protocol indep. multicast
- **`IPCOMP`**: IP Payload Comp. Protocol
- **`VRRP`**: VRRP RFC 2338
- **`CARP`**: Common Address Resolution Protocol
- **`PFSYNC`**: PFSYNC
- **`RAW`**: raw IP packet
- **`IP`**: 
- **`ICMP`**: 
- **`IGMP`**: 
- **`IPIP`**: 
- **`TCP`**: 
- **`UDP`**: 
- **`IPV6`**: 
- **`ESP`**: 
- **`AH`**: 
- **`ICMPV6`**: 
- **`RAW`**: 

### `IP`


### `IPV6`


### `IPTOS`


### `SOL`


### Constants & Variables

- **`SOCKET`**: 
- **`SOCKET`**: 
- **`ROUTE`**: 
- **`PACKET`**: 
- **`FILTER`**: 
- **`SOCKET`**: 

### `SO`


### Constants & Variables

- **`DEBUG`**: 
- **`ACCEPTCONN`**: 
- **`REUSEADDR`**: 
- **`KEEPALIVE`**: 
- **`DONTROUTE`**: 
- **`BROADCAST`**: 
- **`USELOOPBACK`**: 
- **`LINGER`**: 
- **`OOBINLINE`**: 
- **`REUSEPORT`**: 
- **`ACCEPTFILTER`**: 
- **`SNDBUF`**: 
- **`RCVBUF`**: 
- **`SNDLOWAT`**: 
- **`RCVLOWAT`**: 
- **`SNDTIMEO`**: 
- **`RCVTIMEO`**: 
- **`ERROR`**: 
- **`TYPE`**: 
- **`NREAD`**: 
- **`NKE`**: 
- **`NOSIGPIPE`**: 
- **`NOADDRERR`**: 
- **`NWRITE`**: 
- **`REUSESHAREUID`**: 
- **`LINGER_SEC`**: 
- **`DEBUG`**: 
- **`ACCEPTCONN`**: 
- **`REUSEADDR`**: 
- **`KEEPALIVE`**: 
- **`DONTROUTE`**: 
- **`BROADCAST`**: 
- **`USELOOPBACK`**: 
- **`LINGER`**: 
- **`OOBINLINE`**: 
- **`REUSEPORT`**: 
- **`TIMESTAMP`**: 
- **`NOSIGPIPE`**: 
- **`ACCEPTFILTER`**: 
- **`BINTIME`**: 
- **`NO_OFFLOAD`**: 
- **`NO_DDP`**: 
- **`REUSEPORT_LB`**: 
- **`SNDBUF`**: 
- **`RCVBUF`**: 
- **`SNDLOWAT`**: 
- **`RCVLOWAT`**: 
- **`SNDTIMEO`**: 
- **`RCVTIMEO`**: 
- **`ERROR`**: 
- **`TYPE`**: 
- **`LABEL`**: 
- **`PEERLABEL`**: 
- **`LISTENQLIMIT`**: 
- **`LISTENQLEN`**: 
- **`LISTENINCQLEN`**: 
- **`SETFIB`**: 
- **`USER_COOKIE`**: 
- **`PROTOCOL`**: 
- **`PROTOTYPE`**: 
- **`TS_CLOCK`**: 
- **`MAX_PACING_RATE`**: 
- **`DOMAIN`**: 
- **`DEBUG`**: 
- **`ACCEPTCONN`**: 
- **`REUSEADDR`**: 
- **`KEEPALIVE`**: 
- **`DONTROUTE`**: 
- **`BROADCAST`**: 
- **`USELOOPBACK`**: 
- **`LINGER`**: 
- **`OOBINLINE`**: 
- **`DGRAM_ERRIND`**: 
- **`RECVUCRED`**: 
- **`SNDBUF`**: 
- **`RCVBUF`**: 
- **`SNDLOWAT`**: 
- **`RCVLOWAT`**: 
- **`SNDTIMEO`**: 
- **`RCVTIMEO`**: 
- **`ERROR`**: 
- **`TYPE`**: 
- **`PROTOTYPE`**: 
- **`ANON_MLP`**: 
- **`MAC_EXEMPT`**: 
- **`DOMAIN`**: 
- **`RCVPSH`**: 
- **`SECATTR`**: 
- **`TIMESTAMP`**: 
- **`ALLZONES`**: 
- **`EXCLBIND`**: 
- **`MAC_IMPLICIT`**: 
- **`VRRP`**: 
- **`DEBUG`**: 
- **`ACCEPTCONN`**: 
- **`REUSEADDR`**: 
- **`KEEPALIVE`**: 
- **`DONTROUTE`**: 
- **`BROADCAST`**: 
- **`USELOOPBACK`**: 
- **`LINGER`**: 
- **`OOBINLINE`**: 
- **`REUSEPORT`**: 
- **`NOSIGPIPE`**: 
- **`ACCEPTFILTER`**: 
- **`TIMESTAMP`**: 
- **`RERROR`**: 
- **`SNDBUF`**: 
- **`RCVBUF`**: 
- **`SNDLOWAT`**: 
- **`RCVLOWAT`**: 
- **`ERROR`**: 
- **`TYPE`**: 
- **`OVERFLOWED`**: 
- **`NOHEADER`**: 
- **`SNDTIMEO`**: 
- **`RCVTIMEO`**: 
- **`DEBUG`**: 
- **`ACCEPTCONN`**: 
- **`REUSEADDR`**: 
- **`KEEPALIVE`**: 
- **`DONTROUTE`**: 
- **`BROADCAST`**: 
- **`USELOOPBACK`**: 
- **`LINGER`**: 
- **`OOBINLINE`**: 
- **`REUSEPORT`**: 
- **`TIMESTAMP`**: 
- **`NOSIGPIPE`**: 
- **`ACCEPTFILTER`**: 
- **`RERROR`**: 
- **`PASSCRED`**: 
- **`SNDBUF`**: 
- **`RCVBUF`**: 
- **`SNDLOWAT`**: 
- **`RCVLOWAT`**: 
- **`SNDTIMEO`**: 
- **`RCVTIMEO`**: 
- **`ERROR`**: 
- **`TYPE`**: 
- **`SNDSPACE`**: 
- **`CPUHINT`**: 
- **`ACCEPTCONN`**: 
- **`BROADCAST`**: 
- **`DEBUG`**: 
- **`DONTROUTE`**: 
- **`KEEPALIVE`**: 
- **`OOBINLINE`**: 
- **`REUSEADDR`**: 
- **`REUSEPORT`**: 
- **`USELOOPBACK`**: 
- **`LINGER`**: 
- **`SNDBUF`**: 
- **`SNDLOWAT`**: 
- **`SNDTIMEO`**: 
- **`RCVBUF`**: 
- **`RCVLOWAT`**: 
- **`RCVTIMEO`**: 
- **`ERROR`**: 
- **`TYPE`**: 
- **`NONBLOCK`**: 
- **`BINDTODEVICE`**: 
- **`PEERCRED`**: 
- **`DEBUG`**: 
- **`ACCEPTCONN`**: 
- **`REUSEADDR`**: 
- **`KEEPALIVE`**: 
- **`DONTROUTE`**: 
- **`BROADCAST`**: 
- **`USELOOPBACK`**: 
- **`LINGER`**: 
- **`OOBINLINE`**: 
- **`REUSEPORT`**: 
- **`TIMESTAMP`**: 
- **`BINDANY`**: 
- **`ZEROIZE`**: 
- **`SNDBUF`**: 
- **`RCVBUF`**: 
- **`SNDLOWAT`**: 
- **`RCVLOWAT`**: 
- **`SNDTIMEO`**: 
- **`RCVTIMEO`**: 
- **`ERROR`**: 
- **`TYPE`**: 
- **`NETPROC`**: 
- **`RTABLE`**: 
- **`PEERCRED`**: 
- **`SPLICE`**: 
- **`DOMAIN`**: 
- **`PROTOCOL`**: 
- **`RCVTIMEO`**: 
- **`SNDTIMEO`**: 
- **`TYPE`**: 
- **`ERROR`**: 
- **`PEERCRED`**: 
- **`RCVBUF`**: 
- **`SNDBUF`**: 
- **`DEBUG`**: 
- **`REUSEADDR`**: 
- **`BINDTODEVICE`**: 
- **`KEEPALIVE`**: 
- **`TIMESTAMP`**: 
- **`BROADCAST`**: 
- **`LINGER`**: 
- **`ACCEPTCONN`**: 
- **`DONTROUTE`**: 
- **`OOBINLINE`**: 
- **`SNDLOWAT`**: 
- **`RCVLOWAT`**: 

### `SOMAXCONN`


### `SCM`


### Constants & Variables

- **`RIGHTS`**: 
- **`UCRED`**: 
- **`TIMESTAMP`**: 
- **`RIGHTS`**: 
- **`TIMESTAMP`**: 
- **`RIGHTS`**: 
- **`RIGHTS`**: 
- **`TIMESTAMP`**: 
- **`CREDS`**: 
- **`BINTIME`**: 
- **`REALTIME`**: 
- **`MONOTONIC`**: 
- **`TIME_INFO`**: 
- **`CREDS2`**: 
- **`RIGHTS`**: 
- **`TIMESTAMP`**: 
- **`CREDS`**: 
- **`RIGHTS`**: 
- **`TIMESTAMP`**: 
- **`CREDS`**: 
- **`RIGHTS`**: 
- **`TIMESTAMP`**: 
- **`RIGHTS`**: 
- **`TIMESTAMP`**: 
- **`CREDS`**: 
- **`TIMESTAMP_MONOTONIC`**: 

### `stack_t`


### `time_t`


### `suseconds_t`


### `timeval`


### `timezone`


### `user_desc`


### `utsname`


### `PR`


### `RTLD`


### `dirent`


### Functions

#### `reclen`

```zig
pub fn reclen(self: dirent) u16
```


### `dirent64`


### `AI`


### `NI`


### `EAI`


### `dl_iterate_phdr_callback`


### `Stat`


### Functions

#### `atime`

```zig
pub fn atime(self: @This()) timespec
```


#### `mtime`

```zig
pub fn mtime(self: @This()) timespec
```


#### `ctime`

```zig
pub fn ctime(self: @This()) timespec
```


#### `fromFilestat`

```zig
pub fn fromFilestat(st: wasi.filestat_t) Stat
```


#### `atime`

```zig
pub fn atime(self: @This()) timespec
```


#### `mtime`

```zig
pub fn mtime(self: @This()) timespec
```


#### `ctime`

```zig
pub fn ctime(self: @This()) timespec
```


#### `birthtime`

```zig
pub fn birthtime(self: @This()) timespec
```


#### `atime`

```zig
pub fn atime(self: @This()) timespec
```


#### `mtime`

```zig
pub fn mtime(self: @This()) timespec
```


#### `ctime`

```zig
pub fn ctime(self: @This()) timespec
```


#### `atime`

```zig
pub fn atime(self: @This()) timespec
```


#### `mtime`

```zig
pub fn mtime(self: @This()) timespec
```


#### `ctime`

```zig
pub fn ctime(self: @This()) timespec
```


#### `birthtime`

```zig
pub fn birthtime(self: @This()) timespec
```


#### `atime`

```zig
pub fn atime(self: @This()) timespec
```


#### `mtime`

```zig
pub fn mtime(self: @This()) timespec
```


#### `ctime`

```zig
pub fn ctime(self: @This()) timespec
```


#### `atime`

```zig
pub fn atime(self: @This()) timespec
```


#### `mtime`

```zig
pub fn mtime(self: @This()) timespec
```


#### `ctime`

```zig
pub fn ctime(self: @This()) timespec
```


#### `birthtime`

```zig
pub fn birthtime(self: @This()) timespec
```


#### `atime`

```zig
pub fn atime(self: @This()) timespec
```


#### `mtime`

```zig
pub fn mtime(self: @This()) timespec
```


#### `ctime`

```zig
pub fn ctime(self: @This()) timespec
```


#### `birthtime`

```zig
pub fn birthtime(self: @This()) timespec
```


#### `atime`

```zig
pub fn atime(self: @This()) timespec
```


#### `mtime`

```zig
pub fn mtime(self: @This()) timespec
```


#### `ctime`

```zig
pub fn ctime(self: @This()) timespec
```


### `pthread_spinlock_t`


### `pthread_mutex_t`


### `pthread_cond_t`


### `pthread_rwlock_t`


### `pthread_attr_t`


### `pthread_key_t`


### `padded_pthread_spin_t`


### `pthread_spin_t`


### `sem_t`


### `Kevent`

Renamed from `kevent` to `Kevent` to avoid conflict with function name.

### `port_t`


### `port_event`


### `AT`


### Constants & Variables

- **`REMOVEDIR`**: Remove directory instead of unlinking file
- **`FDCWD`**: 
- **`EACCESS`**: Use effective ids in access check
- **`SYMLINK_NOFOLLOW`**: Act on the symlink itself not the target
- **`SYMLINK_FOLLOW`**: Act on target of symlink
- **`REMOVEDIR`**: Path refers to directory
- **`FDCWD`**: Magic value that specify the use of the current working directory
- **`EACCESS`**: Check access using effective user and group ID
- **`SYMLINK_NOFOLLOW`**: Do not follow symbolic links
- **`SYMLINK_FOLLOW`**: Follow symbolic link
- **`REMOVEDIR`**: Remove directory instead of file
- **`BENEATH`**: Fail if not under dirfd
- **`FDCWD`**: Magic value that specify the use of the current working directory
- **`EACCESS`**: Check access using effective user and group ID
- **`SYMLINK_NOFOLLOW`**: Do not follow symbolic links
- **`SYMLINK_FOLLOW`**: Follow symbolic link
- **`REMOVEDIR`**: Remove directory instead of file
- **`FDCWD`**: 
- **`SYMLINK_NOFOLLOW`**: 
- **`REMOVEDIR`**: 
- **`EACCESS`**: 
- **`SYMLINK_FOLLOW`**: 
- **`FDCWD`**: Magic value that specify the use of the current working directory
- **`EACCESS`**: Check access using effective user and group ID
- **`SYMLINK_NOFOLLOW`**: Do not follow symbolic links
- **`SYMLINK_FOLLOW`**: Follow symbolic link
- **`REMOVEDIR`**: Remove directory instead of file
- **`FDCWD`**: 
- **`SYMLINK_NOFOLLOW`**: 
- **`SYMLINK_FOLLOW`**: 
- **`REMOVEDIR`**: 
- **`EACCESS`**: 
- **`FDCWD`**: Magic value that specify the use of the current working directory
- **`SYMLINK_NOFOLLOW`**: Do not follow symbolic links
- **`SYMLINK_FOLLOW`**: Follow symbolic link
- **`REMOVEDIR`**: Remove directory instead of file
- **`TRIGGER`**: 
- **`EACCESS`**: Check access using effective user and group ID
- **`FDCWD`**: 
- **`SYMLINK_NOFOLLOW`**: 
- **`REMOVEDIR`**: 
- **`SYMLINK_FOLLOW`**: 
- **`NO_AUTOMOUNT`**: 
- **`EMPTY_PATH`**: 
- **`STATX_SYNC_TYPE`**: 
- **`STATX_SYNC_AS_STAT`**: 
- **`STATX_FORCE_SYNC`**: 
- **`STATX_DONT_SYNC`**: 
- **`RECURSIVE`**: 
- **`EACCESS`**: 
- **`SYMLINK_NOFOLLOW`**: 
- **`SYMLINK_FOLLOW`**: 
- **`REMOVEDIR`**: 
- **`FDCWD`**: When linking libc, we follow their convention and use -2 for current working directory.
- **`FDCWD`**: 
- **`SYMLINK_NOFOLLOW`**: 
- **`REMOVEDIR`**: 
- **`EACCESS`**: 

### `O`


### `EXECVEAT`


### `MAP`


### `MREMAP`


### `cc_t`


### `V`

Indices into the `cc` array in the `termios` struct.

### `NCCS`


### `termios`


### `tc_iflag_t`


### `tc_oflag_t`


### `CSIZE`


### `tc_cflag_t`


### `tc_lflag_t`


### `speed_t`


### `whence_t`


### `sig_atomic_t`


### `SS`


### Constants & Variables

- **`ONSTACK`**: 
- **`DISABLE`**: 
- **`ONSTACK`**: 
- **`DISABLE`**: 

### `EV`


### Constants & Variables

- **`ADD`**: add event to kq (implies enable)
- **`DELETE`**: delete event from kq
- **`ENABLE`**: enable event
- **`DISABLE`**: disable event (not reported)
- **`ONESHOT`**: only report one occurrence
- **`CLEAR`**: clear event state after reporting
- **`RECEIPT`**: force immediate event output
- **`DISPATCH`**: disable event after reporting
- **`UDATA_SPECIFIC`**: unique kevent per udata value
- **`DISPATCH2`**: ... in combination with DELETE
- **`VANISHED`**: report that source has vanished
- **`SYSFLAGS`**: reserved by system
- **`FLAG0`**: filter-specific flag
- **`FLAG1`**: filter-specific flag
- **`EOF`**: EOF detected (return value)
- **`ERROR`**: error, data contains errno (return value)
- **`POLL`**: use poll(2) semantics for EVFILT.READ
- **`OOBAND`**: on input, filter should actively return in the presence of OOB on the descriptor
- **`ADD`**: 
- **`DELETE`**: 
- **`ENABLE`**: 
- **`DISABLE`**: 
- **`ONESHOT`**: 
- **`CLEAR`**: 
- **`RECEIPT`**: 
- **`DISPATCH`**: 
- **`NODATA`**: 
- **`FLAG1`**: 
- **`ERROR`**: 
- **`EOF`**: 
- **`SYSFLAGS`**: 
- **`ADD`**: add event to kq (implies enable)
- **`DELETE`**: delete event from kq
- **`ENABLE`**: enable event
- **`DISABLE`**: disable event (not reported)
- **`ONESHOT`**: only report one occurrence
- **`CLEAR`**: clear event state after reporting
- **`RECEIPT`**: force EV_ERROR on success, data=0
- **`DISPATCH`**: disable event after reporting
- **`FLAG1`**: filter-specific flag
- **`ERROR`**: error, data contains errno
- **`EOF`**: EOF detected
- **`ADD`**: add event to kq (implies enable)
- **`DELETE`**: delete event from kq
- **`ENABLE`**: enable event
- **`DISABLE`**: disable event (not reported)
- **`FORCEONESHOT`**: enable _ONESHOT and force trigger
- **`KEEPUDATA`**: do not update the udata field
- **`ONESHOT`**: only report one occurrence
- **`CLEAR`**: clear event state after reporting
- **`RECEIPT`**: force immediate event output
- **`DISPATCH`**: disable event after reporting
- **`SYSFLAGS`**: reserved by system
- **`DROP`**: note should be dropped
- **`FLAG1`**: filter-specific flag 1
- **`FLAG2`**: filter-specific flag 2
- **`EOF`**: EOF detected (return value)
- **`ERROR`**: error, event data contains errno (return value)
- **`ADD`**: 
- **`DELETE`**: 
- **`ENABLE`**: 
- **`DISABLE`**: 
- **`ONESHOT`**: 
- **`CLEAR`**: 
- **`RECEIPT`**: 
- **`DISPATCH`**: 
- **`FLAG1`**: 
- **`ERROR`**: 
- **`EOF`**: 
- **`ADD`**: add event to kq (implies enable)
- **`DELETE`**: delete event from kq
- **`ENABLE`**: enable event
- **`DISABLE`**: disable event (not reported)
- **`ONESHOT`**: only report one occurrence
- **`CLEAR`**: clear event state after reporting
- **`RECEIPT`**: force immediate event output
- **`DISPATCH`**: disable event after reporting

### `EVFILT`


### Constants & Variables

- **`READ`**: 
- **`WRITE`**: 
- **`AIO`**: attached to aio requests
- **`VNODE`**: attached to vnodes
- **`PROC`**: attached to struct proc
- **`SIGNAL`**: attached to struct proc
- **`TIMER`**: timers
- **`MACHPORT`**: Mach portsets
- **`FS`**: Filesystem events
- **`USER`**: User events
- **`VM`**: Virtual memory events
- **`EXCEPT`**: Exception events
- **`SYSCOUNT`**: 
- **`READ`**: 
- **`WRITE`**: 
- **`AIO`**: attached to aio requests
- **`VNODE`**: attached to vnodes
- **`PROC`**: attached to struct proc
- **`SIGNAL`**: attached to struct proc
- **`TIMER`**: timers
- **`PROCDESC`**: Process descriptors
- **`FS`**: Filesystem events
- **`LIO`**: 
- **`USER`**: User events
- **`SENDFILE`**: Sendfile events
- **`EMPTY`**: 
- **`FS`**: 
- **`USER`**: 
- **`EXCEPT`**: 
- **`TIMER`**: 
- **`SIGNAL`**: 
- **`PROC`**: 
- **`VNODE`**: 
- **`AIO`**: 
- **`WRITE`**: 
- **`READ`**: 
- **`SYSCOUNT`**: 
- **`MARKER`**: 
- **`READ`**: 
- **`WRITE`**: 
- **`AIO`**: attached to aio requests
- **`VNODE`**: attached to vnodes
- **`PROC`**: attached to struct proc
- **`SIGNAL`**: attached to struct proc
- **`TIMER`**: timers
- **`FS`**: Filesystem events
- **`USER`**: User events
- **`EMPTY`**: Empty filter
- **`READ`**: 
- **`WRITE`**: 
- **`AIO`**: attached to aio requests
- **`VNODE`**: attached to vnodes
- **`PROC`**: attached to struct proc
- **`SIGNAL`**: attached to struct proc
- **`TIMER`**: timers
- **`PROCDESC`**: Process descriptors
- **`FS`**: Filesystem events
- **`LIO`**: attached to lio requests
- **`USER`**: User events
- **`SENDFILE`**: Sendfile events
- **`EMPTY`**: empty send socket buf
- **`JAIL`**: attached to struct prison
- **`JAILDESC`**: attached to jail descriptors
- **`READ`**: 
- **`WRITE`**: 
- **`AIO`**: 
- **`VNODE`**: 
- **`PROC`**: 
- **`SIGNAL`**: 
- **`TIMER`**: 
- **`DEVICE`**: 
- **`EXCEPT`**: 
- **`USER`**: 

### `NOTE`


### Constants & Variables

- **`TRIGGER`**: On input, TRIGGER causes the event to be triggered for output.
- **`FFNOP`**: ignore input fflags
- **`FFAND`**: and fflags
- **`FFOR`**: or fflags
- **`FFCOPY`**: copy fflags
- **`FFCTRLMASK`**: mask for operations
- **`FFLAGSMASK`**: 
- **`LOWAT`**: low water mark
- **`OOB`**: OOB data
- **`DELETE`**: vnode was removed
- **`WRITE`**: data contents changed
- **`EXTEND`**: size increased
- **`ATTRIB`**: attributes changed
- **`LINK`**: link count changed
- **`RENAME`**: vnode was renamed
- **`REVOKE`**: vnode access was revoked
- **`NONE`**: No specific vnode event: to test for EVFILT_READ activation
- **`FUNLOCK`**: vnode was unlocked by flock(2)
- **`EXIT`**: process exited
- **`FORK`**: process forked
- **`EXEC`**: process exec'd
- **`SIGNAL`**: shared with EVFILT_SIGNAL
- **`EXITSTATUS`**: exit status to be returned, valid for child process only
- **`EXIT_DETAIL`**: provide details on reasons for exit
- **`PDATAMASK`**: mask for signal & exit status
- **`PCTRLMASK`**: 
- **`EXIT_DETAIL_MASK`**: 
- **`EXIT_DECRYPTFAIL`**: 
- **`EXIT_MEMORY`**: 
- **`EXIT_CSERROR`**: 
- **`VM_PRESSURE`**: will react on memory pressure
- **`VM_PRESSURE_TERMINATE`**: will quit on memory pressure, possibly after cleaning up dirty state
- **`VM_PRESSURE_SUDDEN_TERMINATE`**: will quit immediately on memory pressure
- **`VM_ERROR`**: there was an error
- **`SECONDS`**: data is seconds
- **`USECONDS`**: data is microseconds
- **`NSECONDS`**: data is nanoseconds
- **`ABSOLUTE`**: absolute timeout
- **`LEEWAY`**: ext[1] holds leeway for power aware timers
- **`CRITICAL`**: system does minimal timer coalescing
- **`BACKGROUND`**: system does maximum timer coalescing
- **`MACH_CONTINUOUS_TIME`**: with ABSOLUTE: causes the timer to continue to tick across sleep, still uses gettimeofday epoch
- **`MACHTIME`**: data is mach absolute time units
- **`FFNOP`**: 
- **`TRACK`**: 
- **`DELETE`**: 
- **`LOWAT`**: 
- **`TRACKERR`**: 
- **`OOB`**: 
- **`WRITE`**: 
- **`EXTEND`**: 
- **`CHILD`**: 
- **`ATTRIB`**: 
- **`LINK`**: 
- **`RENAME`**: 
- **`REVOKE`**: 
- **`PDATAMASK`**: 
- **`FFLAGSMASK`**: 
- **`TRIGGER`**: 
- **`EXEC`**: 
- **`FFAND`**: 
- **`FORK`**: 
- **`EXIT`**: 
- **`FFOR`**: 
- **`FFCTRLMASK`**: 
- **`FFCOPY`**: 
- **`PCTRLMASK`**: 
- **`FFNOP`**: ignore input fflags
- **`FFAND`**: AND fflags
- **`FFOR`**: OR fflags
- **`FFCOPY`**: copy fflags
- **`FFCTRLMASK`**: masks for operations
- **`FFLAGSMASK`**: 
- **`TRIGGER`**: On input, TRIGGER causes the event to be triggered for output.
- **`LOWAT`**: low water mark
- **`DELETE`**: vnode was removed
- **`WRITE`**: data contents changed
- **`EXTEND`**: size increased
- **`ATTRIB`**: attributes changed
- **`LINK`**: link count changed
- **`RENAME`**: vnode was renamed
- **`REVOKE`**: vnode access was revoked
- **`OPEN`**: vnode was opened
- **`CLOSE`**: file closed (no FWRITE)
- **`CLOSE_WRITE`**: file closed (FWRITE)
- **`READ`**: file was read
- **`EXIT`**: process exited
- **`FORK`**: process forked
- **`EXEC`**: process exec'd
- **`PDATAMASK`**: mask for signal & exit status
- **`PCTRLMASK`**: 
- **`TRACK`**: follow across forks
- **`TRACKERR`**: could not track child
- **`CHILD`**: am a child process
- **`SIGNAL`**: shared with EVFILT_SIGNAL
- **`MSECONDS`**: data is milliseconds
- **`SECONDS`**: data is seconds
- **`USECONDS`**: data is microseconds
- **`NSECONDS`**: data is nanoseconds
- **`ABSTIME`**: timeout is absolute
- **`TRIGGER`**: On input, TRIGGER causes the event to be triggered for output.
- **`FFNOP`**: ignore input fflags
- **`FFAND`**: and fflags
- **`FFOR`**: or fflags
- **`FFCOPY`**: copy fflags
- **`FFCTRLMASK`**: mask for operations
- **`FFLAGSMASK`**: 
- **`LOWAT`**: low water mark
- **`FILE_POLL`**: behave like poll()
- **`DELETE`**: vnode was removed
- **`WRITE`**: data contents changed
- **`EXTEND`**: size increased
- **`ATTRIB`**: attributes changed
- **`LINK`**: link count changed
- **`RENAME`**: vnode was renamed
- **`REVOKE`**: vnode access was revoked
- **`OPEN`**: vnode was opened
- **`CLOSE`**: file closed, fd did not allow write
- **`CLOSE_WRITE`**: file closed, fd did allow write
- **`READ`**: file was read
- **`EXIT`**: process exited
- **`FORK`**: process forked
- **`EXEC`**: process exec'd
- **`PDATAMASK`**: mask for signal & exit status
- **`PCTRLMASK`**: 
- **`SECONDS`**: data is seconds
- **`MSECONDS`**: data is milliseconds
- **`USECONDS`**: data is microseconds
- **`NSECONDS`**: data is nanoseconds
- **`ABSTIME`**: timeout is absolute
- **`LOWAT`**: 
- **`EOF`**: 
- **`OOB`**: 
- **`DELETE`**: 
- **`WRITE`**: 
- **`EXTEND`**: 
- **`ATTRIB`**: 
- **`LINK`**: 
- **`RENAME`**: 
- **`REVOKE`**: 
- **`TRUNCATE`**: 
- **`EXIT`**: 
- **`FORK`**: 
- **`EXEC`**: 
- **`PDATAMASK`**: 
- **`PCTRLMASK`**: 
- **`TRACK`**: 
- **`TRACKERR`**: 
- **`CHILD`**: 
- **`CHANGE`**: 
- **`FFNOP`**: 
- **`FFAND`**: 
- **`FFOR`**: 
- **`FFCOPY`**: 
- **`FFCTRLMASK`**: 
- **`FFLAGSMASK`**: 
- **`TRIGGER`**: 

### `FUTEX`


### `MFD`


### `DIR`


### `HWCAP`


### Namespaces

- **`@"2"`**: 
- **`@"2"`**: 

### Constants & Variables

- **`ISA_A`**: 
- **`ISA_B`**: 
- **`ISA_C`**: 
- **`ISA_D`**: 
- **`ISA_F`**: 
- **`ISA_H`**: 
- **`ISA_I`**: 
- **`ISA_M`**: 
- **`ISA_V`**: 
- **`FPU`**: 
- **`TSC`**: 
- **`CX8`**: 
- **`SEP`**: 
- **`AMD_SYSC`**: 
- **`CMOV`**: 
- **`MMX`**: 
- **`AMD_MMX`**: 
- **`AMD_3DNow`**: 
- **`AMD_3DNowx`**: 
- **`FXSR`**: 
- **`SSE`**: 
- **`SSE2`**: 
- **`PAUSE`**: 
- **`SSE3`**: 
- **`MON`**: 
- **`CX16`**: 
- **`AHF`**: 
- **`TSCP`**: 
- **`AMD_SSE4A`**: 
- **`POPCNT`**: 
- **`AMD_LZCNT`**: 
- **`SSSE3`**: 
- **`SSE4_1`**: 
- **`SSE4_2`**: 
- **`MOVBE`**: 
- **`AES`**: 
- **`PCLMULQDQ`**: 
- **`XSAVE`**: 
- **`AVX`**: 
- **`VMX`**: 
- **`AMD_SVM`**: 
- **`ISA_A`**: 
- **`ISA_B`**: 
- **`ISA_C`**: 
- **`ISA_D`**: 
- **`ISA_F`**: 
- **`ISA_H`**: 
- **`ISA_I`**: 
- **`ISA_M`**: 
- **`ISA_V`**: 

### `sf_hdtr`


### `pthread_cancelstate`


### `caddr_t`


### `pthread_t`


### `FILE`


### `LC`

These are implementation defined but share identical values in at least musl and glibc:
- https://git.musl-libc.org/cgit/musl/tree/include/locale.h?id=ab31e9d6a0fa7c5c408856c89df2dfb12c344039#n18
- https://sourceware.org/git/?p=glibc.git;a=blob;f=locale/bits/locale.h;h=0fcbb66114be5fef0577dc9047256eb508c45919;hb=c90cfce849d010474e8cccf3e5bff49a2c8b141f#l26

### Fields

- `CTYPE = 0`
  
- `NUMERIC = 1`
  
- `TIME = 2`
  
- `COLLATE = 3`
  
- `MONETARY = 4`
  
- `MESSAGES = 5`
  
- `ALL = 6`
  
- `PAPER = 7`
  
- `NAME = 8`
  
- `ADDRESS = 9`
  
- `TELEPHONE = 10`
  
- `MEASUREMENT = 11`
  
- `IDENTIFICATION = 12`
  
- `_`
  

### `max_align_t`


### `div_t`


### Fields

- `quot: c_int`
  
- `rem: c_int`
  

### `ldiv_t`


### Fields

- `quot: c_long`
  
- `rem: c_long`
  

### `lldiv_t`


### Fields

- `quot: c_longlong`
  
- `rem: c_longlong`
  

### `imaxdiv_t`


### Fields

- `quot: intmax_t`
  
- `rem: intmax_t`
  

### `intmax_t`


### `uintmax_t`


### `wint_t`


### `wchar_t`


### `TIMER`


## Functions

### `versionCheck`

```zig
pub inline fn versionCheck(comptime version: std.SemanticVersion) bool
```

* If not linking libc, returns `false`.
* If linking musl libc, returns `true`.
* If linking GNU libc (glibc), returns `true` if the target version is greater than or equal to
  `version`.
* If linking Android libc (bionic), returns `true` if the target API level is greater than or
  equal to `version.major`, ignoring other components.
* If linking a libc other than these, returns `false`.

### `errno`

```zig
pub fn errno(rc: anytype) E
```

Get the errno if rc is -1 and SUCCESS if rc is not -1.

### `opendir`

```zig
pub extern "c" fn opendir(pathname: [*:0]const u8) ?*DIR
```


### `fdopendir`

```zig
pub extern "c" fn fdopendir(fd: c_int) ?*DIR
```


### `rewinddir`

```zig
pub extern "c" fn rewinddir(dp: *DIR) void
```


### `closedir`

```zig
pub extern "c" fn closedir(dp: *DIR) c_int
```


### `telldir`

```zig
pub extern "c" fn telldir(dp: *DIR) c_long
```


### `seekdir`

```zig
pub extern "c" fn seekdir(dp: *DIR, loc: c_long) void
```


### `sigwait`

```zig
pub extern "c" fn sigwait(set: ?*sigset_t, sig: ?*c_int) c_int
```


### `alarm`

```zig
pub extern "c" fn alarm(seconds: c_uint) c_uint
```


### `statx`

```zig
pub extern "c" fn statx(dirfd: fd_t, path: [*:0]const u8, flags: u32, mask: linux.STATX, buf: *linux.Statx) c_int
```


### `getpwent`

```zig
pub extern "c" fn getpwent() ?*passwd
```


### `endpwent`

```zig
pub extern "c" fn endpwent() void
```


### `setpwent`

```zig
pub extern "c" fn setpwent() void
```


### `getpwnam`

```zig
pub extern "c" fn getpwnam(name: [*:0]const u8) ?*passwd
```


### `getpwnam_r`

```zig
pub extern "c" fn getpwnam_r(name: [*:0]const u8, pwd: *passwd, buf: [*]u8, buflen: usize, result: *?*passwd) c_int
```


### `getpwuid`

```zig
pub extern "c" fn getpwuid(uid: uid_t) ?*passwd
```


### `getpwuid_r`

```zig
pub extern "c" fn getpwuid_r(uid: uid_t, pwd: *passwd, buf: [*]u8, buflen: usize, result: *?*passwd) c_int
```


### `getgrent`

```zig
pub extern "c" fn getgrent() ?*group
```


### `setgrent`

```zig
pub extern "c" fn setgrent() void
```


### `endgrent`

```zig
pub extern "c" fn endgrent() void
```


### `getgrnam`

```zig
pub extern "c" fn getgrnam(name: [*:0]const u8) ?*group
```


### `getgrnam_r`

```zig
pub extern "c" fn getgrnam_r(name: [*:0]const u8, grp: *group, buf: [*]u8, buflen: usize, result: *?*group) c_int
```


### `getgrgid`

```zig
pub extern "c" fn getgrgid(gid: gid_t) ?*group
```


### `getgrgid_r`

```zig
pub extern "c" fn getgrgid_r(gid: gid_t, grp: *group, buf: [*]u8, buflen: usize, result: *?*group) c_int
```


### `getrlimit64`

```zig
pub extern "c" fn getrlimit64(resource: rlimit_resource, rlim: *rlimit) c_int
```


### `lseek64`

```zig
pub extern "c" fn lseek64(fd: fd_t, offset: i64, whence: c_int) i64
```


### `mmap64`

```zig
pub extern "c" fn mmap64(addr: ?*align(page_size) anyopaque, len: usize, prot: PROT, flags: MAP, fd: fd_t, offset: i64) *anyopaque
```


### `open64`

```zig
pub extern "c" fn open64(path: [*:0]const u8, oflag: O, ...) c_int
```


### `openat64`

```zig
pub extern "c" fn openat64(fd: c_int, path: [*:0]const u8, oflag: O, ...) c_int
```


### `pread64`

```zig
pub extern "c" fn pread64(fd: fd_t, buf: [*]u8, nbyte: usize, offset: i64) isize
```


### `preadv64`

```zig
pub extern "c" fn preadv64(fd: c_int, iov: [*]const iovec, iovcnt: c_uint, offset: i64) isize
```


### `pwrite64`

```zig
pub extern "c" fn pwrite64(fd: fd_t, buf: [*]const u8, nbyte: usize, offset: i64) isize
```


### `pwritev64`

```zig
pub extern "c" fn pwritev64(fd: c_int, iov: [*]const iovec_const, iovcnt: c_uint, offset: i64) isize
```


### `sendfile64`

```zig
pub extern "c" fn sendfile64(out_fd: fd_t, in_fd: fd_t, offset: ?*i64, count: usize) isize
```


### `setrlimit64`

```zig
pub extern "c" fn setrlimit64(resource: rlimit_resource, rlim: *const rlimit) c_int
```


### `sched_getaffinity`

```zig
pub extern "c" fn sched_getaffinity(pid: c_int, size: usize, set: *cpu_set_t) c_int
```


### `eventfd`

```zig
pub extern "c" fn eventfd(initval: c_uint, flags: c_uint) c_int
```


### `epoll_ctl`

```zig
pub extern "c" fn epoll_ctl(epfd: fd_t, op: c_uint, fd: fd_t, event: ?*epoll_event) c_int
```


### `epoll_create1`

```zig
pub extern "c" fn epoll_create1(flags: c_uint) c_int
```


### `epoll_wait`

```zig
pub extern "c" fn epoll_wait(epfd: fd_t, events: [*]epoll_event, maxevents: c_uint, timeout: c_int) c_int
```


### `epoll_pwait`

```zig
pub extern "c" fn epoll_pwait(epfd: fd_t, events: [*]epoll_event, maxevents: c_int, timeout: c_int, sigmask: *const sigset_t, ) c_int
```


### `timerfd_create`

```zig
pub extern "c" fn timerfd_create(clockid: timerfd_clockid_t, flags: c_int) c_int
```


### `timerfd_settime`

```zig
pub extern "c" fn timerfd_settime(fd: c_int, flags: c_int, new_value: *const itimerspec, old_value: ?*itimerspec, ) c_int
```


### `timerfd_gettime`

```zig
pub extern "c" fn timerfd_gettime(fd: c_int, curr_value: *itimerspec) c_int
```


### `inotify_init1`

```zig
pub extern "c" fn inotify_init1(flags: c_uint) c_int
```


### `inotify_add_watch`

```zig
pub extern "c" fn inotify_add_watch(fd: fd_t, pathname: [*:0]const u8, mask: u32) c_int
```


### `inotify_rm_watch`

```zig
pub extern "c" fn inotify_rm_watch(fd: fd_t, wd: c_int) c_int
```


### `fallocate64`

```zig
pub extern "c" fn fallocate64(fd: fd_t, mode: c_int, offset: off_t, len: off_t) c_int
```


### `fopen64`

```zig
pub extern "c" fn fopen64(noalias filename: [*:0]const u8, noalias modes: [*:0]const u8) ?*FILE
```


### `ftruncate64`

```zig
pub extern "c" fn ftruncate64(fd: c_int, length: off_t) c_int
```


### `fallocate`

```zig
pub extern "c" fn fallocate(fd: fd_t, mode: c_int, offset: off_t, len: off_t) c_int
```


### `getauxval`

```zig
pub extern "c" fn getauxval(type: c_ulong) c_ulong
```


### `elf_aux_info`

```zig
pub extern "c" fn elf_aux_info(aux: c_int, buf: *anyopaque, buflen: c_int) c_int
```


### `dl_iterate_phdr`

```zig
pub extern "c" fn dl_iterate_phdr(callback: dl_iterate_phdr_callback, data: ?*anyopaque) c_int
```


### `memfd_create`

```zig
pub extern "c" fn memfd_create(name: [*:0]const u8, flags: c_uint) c_int
```


### `signalfd`

```zig
pub extern "c" fn signalfd(fd: fd_t, mask: *const sigset_t, flags: u32) c_int
```


### `prlimit`

```zig
pub extern "c" fn prlimit(pid: pid_t, resource: rlimit_resource, new_limit: *const rlimit, old_limit: *rlimit) c_int
```


### `mincore`

```zig
pub extern "c" fn mincore(addr: *align(page_size) anyopaque, length: usize, vec: [*]u8, ) c_int
```


### `madvise`

```zig
pub extern "c" fn madvise(addr: *align(page_size) anyopaque, length: usize, advice: u32, ) c_int
```


### `fopen`

```zig
pub extern "c" fn fopen(noalias filename: [*:0]const u8, noalias modes: [*:0]const u8) ?*FILE
```


### `fclose`

```zig
pub extern "c" fn fclose(stream: *FILE) c_int
```


### `fwrite`

```zig
pub extern "c" fn fwrite(noalias ptr: [*]const u8, size_of_type: usize, item_count: usize, noalias stream: *FILE) usize
```


### `fread`

```zig
pub extern "c" fn fread(noalias ptr: [*]u8, size_of_type: usize, item_count: usize, noalias stream: *FILE) usize
```


### `printf`

```zig
pub extern "c" fn printf(format: [*:0]const u8, ...) c_int
```


### `abort`

```zig
pub extern "c" fn abort() noreturn
```


### `exit`

```zig
pub extern "c" fn exit(code: c_int) noreturn
```


### `_Exit`

```zig
pub extern "c" fn _Exit(code: c_int) noreturn
```


### `_exit`

```zig
pub extern "c" fn _exit(code: c_int) noreturn
```


### `isatty`

```zig
pub extern "c" fn isatty(fd: fd_t) c_int
```


### `lseek`

```zig
pub extern "c" fn lseek(fd: fd_t, offset: off_t, whence: whence_t) off_t
```


### `open`

```zig
pub extern "c" fn open(path: [*:0]const u8, oflag: O, ...) c_int
```


### `openat`

```zig
pub extern "c" fn openat(fd: c_int, path: [*:0]const u8, oflag: O, ...) c_int
```


### `ftruncate`

```zig
pub extern "c" fn ftruncate(fd: c_int, length: off_t) c_int
```


### `raise`

```zig
pub extern "c" fn raise(sig: SIG) c_int
```


### `read`

```zig
pub extern "c" fn read(fd: fd_t, buf: [*]u8, nbyte: usize) isize
```


### `readv`

```zig
pub extern "c" fn readv(fd: c_int, iov: [*]const iovec, iovcnt: c_uint) isize
```


### `pread`

```zig
pub extern "c" fn pread(fd: fd_t, buf: [*]u8, nbyte: usize, offset: off_t) isize
```


### `preadv`

```zig
pub extern "c" fn preadv(fd: c_int, iov: [*]const iovec, iovcnt: c_uint, offset: off_t) isize
```


### `writev`

```zig
pub extern "c" fn writev(fd: c_int, iov: [*]const iovec_const, iovcnt: c_uint) isize
```


### `pwritev`

```zig
pub extern "c" fn pwritev(fd: c_int, iov: [*]const iovec_const, iovcnt: c_uint, offset: off_t) isize
```


### `write`

```zig
pub extern "c" fn write(fd: fd_t, buf: [*]const u8, nbyte: usize) isize
```


### `pwrite`

```zig
pub extern "c" fn pwrite(fd: fd_t, buf: [*]const u8, nbyte: usize, offset: off_t) isize
```


### `mmap`

```zig
pub extern "c" fn mmap(addr: ?*align(page_size) anyopaque, len: usize, prot: PROT, flags: MAP, fd: fd_t, offset: off_t) *anyopaque
```


### `munmap`

```zig
pub extern "c" fn munmap(addr: *align(page_size) const anyopaque, len: usize) c_int
```


### `mremap`

```zig
pub extern "c" fn mremap(addr: ?*align(page_size) const anyopaque, old_len: usize, new_len: usize, flags: MREMAP, ...) *anyopaque
```


### `mprotect`

```zig
pub extern "c" fn mprotect(addr: *align(page_size) anyopaque, len: usize, prot: PROT) c_int
```


### `link`

```zig
pub extern "c" fn link(oldpath: [*:0]const u8, newpath: [*:0]const u8) c_int
```


### `linkat`

```zig
pub extern "c" fn linkat(oldfd: fd_t, oldpath: [*:0]const u8, newfd: fd_t, newpath: [*:0]const u8, flags: c_uint) c_int
```


### `unlink`

```zig
pub extern "c" fn unlink(path: [*:0]const u8) c_int
```


### `unlinkat`

```zig
pub extern "c" fn unlinkat(dirfd: fd_t, path: [*:0]const u8, flags: c_uint) c_int
```


### `getcwd`

```zig
pub extern "c" fn getcwd(buf: [*]u8, size: usize) ?[*]u8
```


### `waitpid`

```zig
pub extern "c" fn waitpid(pid: pid_t, status: ?*c_int, options: c_int) pid_t
```


### `access`

```zig
pub extern "c" fn access(path: [*:0]const u8, mode: c_uint) c_int
```


### `faccessat`

```zig
pub extern "c" fn faccessat(dirfd: fd_t, path: [*:0]const u8, mode: c_uint, flags: c_uint) c_int
```


### `pipe`

```zig
pub extern "c" fn pipe(fds: *[2]fd_t) c_int
```


### `mkdir`

```zig
pub extern "c" fn mkdir(path: [*:0]const u8, mode: mode_t) c_int
```


### `mkdirat`

```zig
pub extern "c" fn mkdirat(dirfd: fd_t, path: [*:0]const u8, mode: mode_t) c_int
```


### `symlink`

```zig
pub extern "c" fn symlink(existing: [*:0]const u8, new: [*:0]const u8) c_int
```


### `symlinkat`

```zig
pub extern "c" fn symlinkat(oldpath: [*:0]const u8, newdirfd: fd_t, newpath: [*:0]const u8) c_int
```


### `rename`

```zig
pub extern "c" fn rename(old: [*:0]const u8, new: [*:0]const u8) c_int
```


### `renameat`

```zig
pub extern "c" fn renameat(olddirfd: fd_t, old: [*:0]const u8, newdirfd: fd_t, new: [*:0]const u8) c_int
```


### `chdir`

```zig
pub extern "c" fn chdir(path: [*:0]const u8) c_int
```


### `fchdir`

```zig
pub extern "c" fn fchdir(fd: fd_t) c_int
```


### `execve`

```zig
pub extern "c" fn execve(path: [*:0]const u8, argv: [*:null]const ?[*:0]const u8, envp: [*:null]const ?[*:0]const u8) c_int
```


### `execveat`

```zig
pub extern "c" fn execveat(dirfd: fd_t, path: [*:0]const u8, argv: [*:null]const ?[*:0]const u8, envp: [*:null]const ?[*:0]const u8, flags: EXECVEAT) c_int
```


### `dup`

```zig
pub extern "c" fn dup(fd: fd_t) c_int
```


### `dup2`

```zig
pub extern "c" fn dup2(old_fd: fd_t, new_fd: fd_t) c_int
```


### `dup3`

```zig
pub extern "c" fn dup3(old: c_int, new: c_int, flags: c_uint) c_int
```


### `readlink`

```zig
pub extern "c" fn readlink(noalias path: [*:0]const u8, noalias buf: [*]u8, bufsize: usize) isize
```


### `readlinkat`

```zig
pub extern "c" fn readlinkat(dirfd: fd_t, noalias path: [*:0]const u8, noalias buf: [*]u8, bufsize: usize) isize
```


### `chmod`

```zig
pub extern "c" fn chmod(path: [*:0]const u8, mode: mode_t) c_int
```


### `fchmod`

```zig
pub extern "c" fn fchmod(fd: fd_t, mode: mode_t) c_int
```


### `fchmodat`

```zig
pub extern "c" fn fchmodat(fd: fd_t, path: [*:0]const u8, mode: mode_t, flags: c_uint) c_int
```


### `fchown`

```zig
pub extern "c" fn fchown(fd: fd_t, owner: uid_t, group: gid_t) c_int
```


### `fchownat`

```zig
pub extern "c" fn fchownat(fd: fd_t, path: [*:0]const u8, owner: uid_t, group: gid_t, flags: c_uint) c_int
```


### `umask`

```zig
pub extern "c" fn umask(mode: mode_t) mode_t
```


### `rmdir`

```zig
pub extern "c" fn rmdir(path: [*:0]const u8) c_int
```


### `getenv`

```zig
pub extern "c" fn getenv(name: [*:0]const u8) ?[*:0]u8
```


### `sysctl`

```zig
pub extern "c" fn sysctl(name: [*]const c_int, namelen: c_uint, oldp: ?*anyopaque, oldlenp: ?*usize, newp: ?*anyopaque, newlen: usize) c_int
```


### `sysctlbyname`

```zig
pub extern "c" fn sysctlbyname(name: [*:0]const u8, oldp: ?*anyopaque, oldlenp: ?*usize, newp: ?*anyopaque, newlen: usize) c_int
```


### `sysctlnametomib`

```zig
pub extern "c" fn sysctlnametomib(name: [*:0]const u8, mibp: ?*c_int, sizep: ?*usize) c_int
```


### `tcgetattr`

```zig
pub extern "c" fn tcgetattr(fd: fd_t, termios_p: *termios) c_int
```


### `tcsetattr`

```zig
pub extern "c" fn tcsetattr(fd: fd_t, optional_action: TCSA, termios_p: *const termios) c_int
```


### `fcntl`

```zig
pub extern "c" fn fcntl(fd: fd_t, cmd: c_int, ...) c_int
```


### `uname`

```zig
pub extern "c" fn uname(buf: *utsname) c_int
```


### `gethostname`

```zig
pub extern "c" fn gethostname(name: [*]u8, len: usize) c_int
```


### `shutdown`

```zig
pub extern "c" fn shutdown(socket: fd_t, how: c_int) c_int
```


### `bind`

```zig
pub extern "c" fn bind(socket: fd_t, address: ?*const sockaddr, address_len: socklen_t) c_int
```


### `listen`

```zig
pub extern "c" fn listen(sockfd: fd_t, backlog: c_uint) c_int
```


### `getsockname`

```zig
pub extern "c" fn getsockname(sockfd: fd_t, noalias addr: *sockaddr, noalias addrlen: *socklen_t) c_int
```


### `getpeername`

```zig
pub extern "c" fn getpeername(sockfd: fd_t, noalias addr: *sockaddr, noalias addrlen: *socklen_t) c_int
```


### `connect`

```zig
pub extern "c" fn connect(sockfd: fd_t, sock_addr: *const sockaddr, addrlen: socklen_t) c_int
```


### `accept`

```zig
pub extern "c" fn accept(sockfd: fd_t, noalias addr: ?*sockaddr, noalias addrlen: ?*socklen_t) c_int
```


### `accept4`

```zig
pub extern "c" fn accept4(sockfd: fd_t, noalias addr: ?*sockaddr, noalias addrlen: ?*socklen_t, flags: c_uint) c_int
```


### `getsockopt`

```zig
pub extern "c" fn getsockopt(sockfd: fd_t, level: i32, optname: u32, noalias optval: ?*anyopaque, noalias optlen: *socklen_t) c_int
```


### `setsockopt`

```zig
pub extern "c" fn setsockopt(sockfd: fd_t, level: i32, optname: u32, optval: ?*const anyopaque, optlen: socklen_t) c_int
```


### `send`

```zig
pub extern "c" fn send(sockfd: fd_t, buf: *const anyopaque, len: usize, flags: u32) isize
```


### `sendto`

```zig
pub extern "c" fn sendto(sockfd: fd_t, buf: *const anyopaque, len: usize, flags: u32, dest_addr: ?*const sockaddr, addrlen: socklen_t, ) isize
```


### `sendmsg`

```zig
pub extern "c" fn sendmsg(sockfd: fd_t, msg: *const msghdr_const, flags: u32) isize
```


### `sendmmsg`

```zig
pub extern "c" fn sendmmsg(sockfd: fd_t, msgvec: [*]mmsghdr, n: c_uint, flags: u32) c_int
```


### `recv`

```zig
pub extern "c" fn recv(sockfd: fd_t, arg1: ?*anyopaque, arg2: usize, arg3: c_int, ) if (native_os == .windows) c_int else isize
```


### `recvfrom`

```zig
pub extern "c" fn recvfrom(sockfd: fd_t, noalias buf: *anyopaque, len: usize, flags: u32, noalias src_addr: ?*sockaddr, noalias addrlen: ?*socklen_t, ) if (native_os == .windows) c_int else isize
```


### `kill`

```zig
pub extern "c" fn kill(pid: pid_t, sig: SIG) c_int
```


### `setuid`

```zig
pub extern "c" fn setuid(uid: uid_t) c_int
```


### `setgid`

```zig
pub extern "c" fn setgid(gid: gid_t) c_int
```


### `seteuid`

```zig
pub extern "c" fn seteuid(euid: uid_t) c_int
```


### `setegid`

```zig
pub extern "c" fn setegid(egid: gid_t) c_int
```


### `setreuid`

```zig
pub extern "c" fn setreuid(ruid: uid_t, euid: uid_t) c_int
```


### `setregid`

```zig
pub extern "c" fn setregid(rgid: gid_t, egid: gid_t) c_int
```


### `setresuid`

```zig
pub extern "c" fn setresuid(ruid: uid_t, euid: uid_t, suid: uid_t) c_int
```


### `setresgid`

```zig
pub extern "c" fn setresgid(rgid: gid_t, egid: gid_t, sgid: gid_t) c_int
```


### `setpgid`

```zig
pub extern "c" fn setpgid(pid: pid_t, pgid: pid_t) c_int
```


### `getuid`

```zig
pub extern "c" fn getuid() uid_t
```


### `getgid`

```zig
pub extern "c" fn getgid() gid_t
```


### `geteuid`

```zig
pub extern "c" fn geteuid() uid_t
```


### `getegid`

```zig
pub extern "c" fn getegid() gid_t
```


### `getresuid`

```zig
pub extern "c" fn getresuid(ruid: *uid_t, euid: *uid_t, suid: *uid_t) c_int
```


### `getresgid`

```zig
pub extern "c" fn getresgid(rgid: *gid_t, egid: *gid_t, sgid: *gid_t) c_int
```


### `malloc`

```zig
pub extern "c" fn malloc(usize) ?*anyopaque
```


### `calloc`

```zig
pub extern "c" fn calloc(usize, usize) ?*anyopaque
```


### `realloc`

```zig
pub extern "c" fn realloc(?*anyopaque, usize) ?*anyopaque
```


### `free`

```zig
pub extern "c" fn free(?*anyopaque) void
```


### `futimes`

```zig
pub extern "c" fn futimes(fd: fd_t, times: ?*[2]timeval) c_int
```


### `utimes`

```zig
pub extern "c" fn utimes(path: [*:0]const u8, times: ?*[2]timeval) c_int
```


### `utimensat`

```zig
pub extern "c" fn utimensat(dirfd: fd_t, pathname: [*:0]const u8, times: ?*const [2]timespec, flags: u32) c_int
```


### `futimens`

```zig
pub extern "c" fn futimens(fd: fd_t, times: ?*const [2]timespec) c_int
```


### `pthread_create`

```zig
pub extern "c" fn pthread_create(noalias newthread: *pthread_t, noalias attr: ?*const pthread_attr_t, start_routine: *const fn (?*anyopaque) callconv(.c) ?*anyopaque, noalias arg: ?*anyopaque, ) E
```


### `pthread_setcancelstate`

```zig
pub extern "c" fn pthread_setcancelstate(pthread_cancelstate, ?*pthread_cancelstate) E
```


### `pthread_cancel`

```zig
pub extern "c" fn pthread_cancel(pthread_t) E
```


### `pthread_attr_init`

```zig
pub extern "c" fn pthread_attr_init(attr: *pthread_attr_t) E
```


### `pthread_attr_setstack`

```zig
pub extern "c" fn pthread_attr_setstack(attr: *pthread_attr_t, stackaddr: *anyopaque, stacksize: usize) E
```


### `pthread_attr_setstacksize`

```zig
pub extern "c" fn pthread_attr_setstacksize(attr: *pthread_attr_t, stacksize: usize) E
```


### `pthread_attr_setguardsize`

```zig
pub extern "c" fn pthread_attr_setguardsize(attr: *pthread_attr_t, guardsize: usize) E
```


### `pthread_attr_destroy`

```zig
pub extern "c" fn pthread_attr_destroy(attr: *pthread_attr_t) E
```


### `pthread_self`

```zig
pub extern "c" fn pthread_self() pthread_t
```


### `pthread_join`

```zig
pub extern "c" fn pthread_join(thread: pthread_t, arg_return: ?*?*anyopaque) E
```


### `pthread_detach`

```zig
pub extern "c" fn pthread_detach(thread: pthread_t) E
```


### `pthread_atfork`

```zig
pub extern "c" fn pthread_atfork(prepare: ?*const fn () callconv(.c) void, parent: ?*const fn () callconv(.c) void, child: ?*const fn () callconv(.c) void, ) c_int
```


### `pthread_key_create`

```zig
pub extern "c" fn pthread_key_create(key: *pthread_key_t, destructor: ?*const fn (value: *anyopaque) callconv(.c) void, ) E
```


### `pthread_key_delete`

```zig
pub extern "c" fn pthread_key_delete(key: pthread_key_t) E
```


### `pthread_getspecific`

```zig
pub extern "c" fn pthread_getspecific(key: pthread_key_t) ?*anyopaque
```


### `pthread_setspecific`

```zig
pub extern "c" fn pthread_setspecific(key: pthread_key_t, value: ?*anyopaque) c_int
```


### `pthread_sigmask`

```zig
pub extern "c" fn pthread_sigmask(how: c_int, set: *const sigset_t, oldset: *sigset_t) c_int
```


### `pthread_getname_np`

```zig
pub extern "c" fn pthread_getname_np(thread: pthread_t, name: [*:0]u8, len: usize) c_int
```


### `pthread_kill`

```zig
pub extern "c" fn pthread_kill(pthread_t, signal: SIG) c_int
```


### `pthread_exit`

```zig
pub extern "c" fn pthread_exit(ptr: ?*anyopaque) noreturn
```


### `sem_init`

```zig
pub extern "c" fn sem_init(sem: *sem_t, pshared: c_int, value: c_uint) c_int
```


### `sem_destroy`

```zig
pub extern "c" fn sem_destroy(sem: *sem_t) c_int
```


### `sem_open`

```zig
pub extern "c" fn sem_open(name: [*:0]const u8, flag: c_int, mode: mode_t, value: c_uint) *sem_t
```


### `sem_close`

```zig
pub extern "c" fn sem_close(sem: *sem_t) c_int
```


### `sem_post`

```zig
pub extern "c" fn sem_post(sem: *sem_t) c_int
```


### `sem_wait`

```zig
pub extern "c" fn sem_wait(sem: *sem_t) c_int
```


### `sem_trywait`

```zig
pub extern "c" fn sem_trywait(sem: *sem_t) c_int
```


### `sem_timedwait`

```zig
pub extern "c" fn sem_timedwait(sem: *sem_t, abs_timeout: *const timespec) c_int
```


### `sem_getvalue`

```zig
pub extern "c" fn sem_getvalue(sem: *sem_t, sval: *c_int) c_int
```


### `shm_unlink`

```zig
pub extern "c" fn shm_unlink(name: [*:0]const u8) c_int
```


### `kqueue`

```zig
pub extern "c" fn kqueue() c_int
```


### `kevent`

```zig
pub extern "c" fn kevent(kq: c_int, changelist: [*]const Kevent, nchanges: c_int, eventlist: [*]Kevent, nevents: c_int, timeout: ?*const timespec, ) c_int
```


### `port_create`

```zig
pub extern "c" fn port_create() port_t
```


### `port_associate`

```zig
pub extern "c" fn port_associate(port: port_t, source: u32, object: usize, events: u32, user_var: ?*anyopaque, ) c_int
```


### `port_dissociate`

```zig
pub extern "c" fn port_dissociate(port: port_t, source: u32, object: usize) c_int
```


### `port_send`

```zig
pub extern "c" fn port_send(port: port_t, events: u32, user_var: ?*anyopaque) c_int
```


### `port_sendn`

```zig
pub extern "c" fn port_sendn(ports: [*]port_t, errors: []u32, num_ports: u32, events: u32, user_var: ?*anyopaque, ) c_int
```


### `port_get`

```zig
pub extern "c" fn port_get(port: port_t, event: *port_event, timeout: ?*timespec) c_int
```


### `port_getn`

```zig
pub extern "c" fn port_getn(port: port_t, event_list: []port_event, max_events: u32, events_retrieved: *u32, timeout: ?*timespec, ) c_int
```


### `port_alert`

```zig
pub extern "c" fn port_alert(port: port_t, flags: u32, events: u32, user_var: ?*anyopaque) c_int
```


### `getaddrinfo`

```zig
pub extern "c" fn getaddrinfo(noalias node: ?[*:0]const u8, noalias service: ?[*:0]const u8, noalias hints: ?*const addrinfo, noalias res: *?*addrinfo, ) EAI
```


### `freeaddrinfo`

```zig
pub extern "c" fn freeaddrinfo(res: *addrinfo) void
```


### `getnameinfo`

```zig
pub extern "c" fn getnameinfo(noalias addr: *const sockaddr, addrlen: socklen_t, noalias host: ?[*]u8, hostlen: socklen_t, noalias serv: ?[*]u8, servlen: socklen_t, flags: NI, ) EAI
```


### `gai_strerror`

```zig
pub extern "c" fn gai_strerror(errcode: EAI) [*:0]const u8
```


### `poll`

```zig
pub extern "c" fn poll(fds: [*]pollfd, nfds: nfds_t, timeout: c_int) c_int
```


### `ppoll`

```zig
pub extern "c" fn ppoll(fds: [*]pollfd, nfds: nfds_t, timeout: ?*const timespec, sigmask: ?*const sigset_t) c_int
```


### `dn_expand`

```zig
pub extern "c" fn dn_expand(msg: [*:0]const u8, eomorig: [*:0]const u8, comp_dn: [*:0]const u8, exp_dn: [*:0]u8, length: c_int, ) c_int
```


### `pthread_spin_init`

```zig
pub extern "c" fn pthread_spin_init(spin: *pthread_spinlock_t, pshared: c_int) c_int
```


### `pthread_spin_lock`

```zig
pub extern "c" fn pthread_spin_lock(spin: *pthread_spinlock_t) c_int
```


### `pthread_spin_unlock`

```zig
pub extern "c" fn pthread_spin_unlock(spin: *pthread_spinlock_t) c_int
```


### `pthread_spin_trylock`

```zig
pub extern "c" fn pthread_spin_trylock(spin: *pthread_spinlock_t) c_int
```


### `pthread_spin_destroy`

```zig
pub extern "c" fn pthread_spin_destroy(spin: *pthread_spinlock_t) c_int
```


### `pthread_mutex_lock`

```zig
pub extern "c" fn pthread_mutex_lock(mutex: *pthread_mutex_t) E
```


### `pthread_mutex_unlock`

```zig
pub extern "c" fn pthread_mutex_unlock(mutex: *pthread_mutex_t) E
```


### `pthread_mutex_trylock`

```zig
pub extern "c" fn pthread_mutex_trylock(mutex: *pthread_mutex_t) E
```


### `pthread_mutex_destroy`

```zig
pub extern "c" fn pthread_mutex_destroy(mutex: *pthread_mutex_t) E
```


### `pthread_cond_wait`

```zig
pub extern "c" fn pthread_cond_wait(noalias cond: *pthread_cond_t, noalias mutex: *pthread_mutex_t) E
```


### `pthread_cond_timedwait`

```zig
pub extern "c" fn pthread_cond_timedwait(noalias cond: *pthread_cond_t, noalias mutex: *pthread_mutex_t, noalias abstime: *const timespec) E
```


### `pthread_cond_signal`

```zig
pub extern "c" fn pthread_cond_signal(cond: *pthread_cond_t) E
```


### `pthread_cond_broadcast`

```zig
pub extern "c" fn pthread_cond_broadcast(cond: *pthread_cond_t) E
```


### `pthread_cond_destroy`

```zig
pub extern "c" fn pthread_cond_destroy(cond: *pthread_cond_t) E
```


### `pthread_rwlock_destroy`

```zig
pub extern "c" fn pthread_rwlock_destroy(rwl: *pthread_rwlock_t) callconv(.c) E
```


### `pthread_rwlock_rdlock`

```zig
pub extern "c" fn pthread_rwlock_rdlock(rwl: *pthread_rwlock_t) callconv(.c) E
```


### `pthread_rwlock_wrlock`

```zig
pub extern "c" fn pthread_rwlock_wrlock(rwl: *pthread_rwlock_t) callconv(.c) E
```


### `pthread_rwlock_tryrdlock`

```zig
pub extern "c" fn pthread_rwlock_tryrdlock(rwl: *pthread_rwlock_t) callconv(.c) E
```


### `pthread_rwlock_trywrlock`

```zig
pub extern "c" fn pthread_rwlock_trywrlock(rwl: *pthread_rwlock_t) callconv(.c) E
```


### `pthread_rwlock_unlock`

```zig
pub extern "c" fn pthread_rwlock_unlock(rwl: *pthread_rwlock_t) callconv(.c) E
```


### `dlopen`

```zig
pub extern "c" fn dlopen(path: ?[*:0]const u8, mode: RTLD) ?*anyopaque
```


### `dlclose`

```zig
pub extern "c" fn dlclose(handle: *anyopaque) c_int
```


### `dlsym`

```zig
pub extern "c" fn dlsym(handle: ?*anyopaque, symbol: [*:0]const u8) ?*anyopaque
```


### `dlerror`

```zig
pub extern "c" fn dlerror() ?[*:0]u8
```


### `sync`

```zig
pub extern "c" fn sync() void
```


### `syncfs`

```zig
pub extern "c" fn syncfs(fd: c_int) c_int
```


### `fsync`

```zig
pub extern "c" fn fsync(fd: c_int) c_int
```


### `fdatasync`

```zig
pub extern "c" fn fdatasync(fd: c_int) c_int
```


### `prctl`

```zig
pub extern "c" fn prctl(option: c_int, ...) c_int
```


### `getrlimit`

```zig
pub extern "c" fn getrlimit(resource: rlimit_resource, rlim: *rlimit) c_int
```


### `setrlimit`

```zig
pub extern "c" fn setrlimit(resource: rlimit_resource, rlim: *const rlimit) c_int
```


### `fmemopen`

```zig
pub extern "c" fn fmemopen(noalias buf: ?*anyopaque, size: usize, noalias mode: [*:0]const u8) ?*FILE
```


### `syslog`

```zig
pub extern "c" fn syslog(priority: c_int, message: [*:0]const u8, ...) void
```


### `openlog`

```zig
pub extern "c" fn openlog(ident: [*:0]const u8, logopt: c_int, facility: c_int) void
```


### `closelog`

```zig
pub extern "c" fn closelog() void
```


### `setlogmask`

```zig
pub extern "c" fn setlogmask(maskpri: c_int) c_int
```


### `if_nametoindex`

```zig
pub extern "c" fn if_nametoindex([*:0]const u8) c_int
```


### `getpid`

```zig
pub extern "c" fn getpid() pid_t
```


### `getppid`

```zig
pub extern "c" fn getppid() pid_t
```


### `setsid`

```zig
pub extern "c" fn setsid() pid_t
```


### `setlocale`

```zig
pub extern "c" fn setlocale(category: LC, locale: ?[*:0]const u8) ?[*:0]const u8
```


### `pthread_getthreadid_np`

```zig
pub extern "c" fn pthread_getthreadid_np() c_int
```


### `pthread_set_name_np`

```zig
pub extern "c" fn pthread_set_name_np(thread: pthread_t, name: [*:0]const u8) void
```


### `pthread_get_name_np`

```zig
pub extern "c" fn pthread_get_name_np(thread: pthread_t, name: [*:0]u8, len: usize) void
```


### `bzero`

```zig
pub extern "c" fn bzero(s: *anyopaque, n: usize) void
```


### `strncmp`

```zig
pub extern "c" fn strncmp(a: [*:0]const c_char, b: [*:0]const c_char, max: usize) c_int
```


### `strcasecmp`

```zig
pub extern "c" fn strcasecmp(a: [*:0]const c_char, b: [*:0]const c_char) c_int
```


### `strncasecmp`

```zig
pub extern "c" fn strncasecmp(a: [*:0]const c_char, b: [*:0]const c_char, max: usize) c_int
```


### `strnlen`

```zig
pub extern "c" fn strnlen(s: [*:0]const c_char, n: usize) callconv(.c) usize
```


### `strndup`

```zig
pub extern "c" fn strndup(s: [*:0]const c_char, n: usize) ?[*:0]c_char
```


### `wcsnlen`

```zig
pub extern "c" fn wcsnlen(s: [*:0]const wchar_t, n: usize) callconv(.c) usize
```


### `ffs`

```zig
pub extern "c" fn ffs(i: c_int) c_int
```


### `ffsl`

```zig
pub extern "c" fn ffsl(i: c_long) c_long
```


### `ffsll`

```zig
pub extern "c" fn ffsll(i: c_longlong) c_longlong
```


### `erand48`

```zig
pub extern "c" fn erand48(xsubi: *[3]c_ushort) f64
```


### `jrand48`

```zig
pub extern "c" fn jrand48(xsubi: *[3]c_ushort) c_long
```


### `nrand48`

```zig
pub extern "c" fn nrand48(xsubi: *[3]c_ushort) c_long
```


### `insque`

```zig
pub extern "c" fn insque(element: *anyopaque, pred: ?*anyopaque) void
```


### `remque`

```zig
pub extern "c" fn remque(element: *anyopaque) void
```


### `imaxabs`

```zig
pub extern "c" fn imaxabs(a: intmax_t) intmax_t
```


### `imaxdiv`

```zig
pub extern "c" fn imaxdiv(a: intmax_t, b: intmax_t) imaxdiv_t
```


### `abs`

```zig
pub extern "c" fn abs(a: c_int) c_int
```


### `labs`

```zig
pub extern "c" fn labs(a: c_long) c_long
```


### `llabs`

```zig
pub extern "c" fn llabs(a: c_longlong) c_longlong
```


### `div`

```zig
pub extern "c" fn div(a: c_int, b: c_int) div_t
```


### `ldiv`

```zig
pub extern "c" fn ldiv(a: c_long, b: c_long) ldiv_t
```


### `lldiv`

```zig
pub extern "c" fn lldiv(a: c_longlong, b: c_longlong) lldiv_t
```


### `atoi`

```zig
pub extern "c" fn atoi(str: [*:0]const c_char) c_int
```


### `atol`

```zig
pub extern "c" fn atol(str: [*:0]const c_char) c_long
```


### `atoll`

```zig
pub extern "c" fn atoll(str: [*:0]const c_char) c_longlong
```


### `strtol`

```zig
pub extern "c" fn strtol(noalias str: [*:0]const c_char, noalias str_end: ?*[*:0]c_char, base: c_int) callconv(.c) c_long
```


### `strtoll`

```zig
pub extern "c" fn strtoll(noalias str: [*:0]const c_char, noalias str_end: ?*[*:0]c_char, base: c_int) callconv(.c) c_longlong
```


### `strtoul`

```zig
pub extern "c" fn strtoul(noalias str: [*:0]const c_char, noalias str_end: ?*[*:0]c_char, base: c_int) callconv(.c) c_ulong
```


### `strtoull`

```zig
pub extern "c" fn strtoull(noalias str: [*:0]const c_char, noalias str_end: ?*[*:0]c_char, base: c_int) callconv(.c) c_ulonglong
```


### `strtoimax`

```zig
pub extern "c" fn strtoimax(noalias str: [*:0]const c_char, noalias str_end: ?*[*:0]c_char, base: c_int) callconv(.c) intmax_t
```


### `strtoumax`

```zig
pub extern "c" fn strtoumax(noalias str: [*:0]const c_char, noalias str_end: ?*[*:0]c_char, base: c_int) callconv(.c) uintmax_t
```


### `bsearch`

```zig
pub extern "c" fn bsearch(key: *const anyopaque, base: *const anyopaque, n: usize, size: usize, compare: *const fn (a: *const anyopaque, b: *const anyopaque) callconv(.c) c_int, ) ?*anyopaque
```


### `atan`

```zig
pub extern "c" fn atan(x: f64) f64
```


### `copysign`

```zig
pub extern "c" fn copysign(x: f64, y: f64) f64
```


### `fdim`

```zig
pub extern "c" fn fdim(x: f64, y: f64) f64
```


### `frexp`

```zig
pub extern "c" fn frexp(x: f64, e: *c_int) f64
```


### `hypot`

```zig
pub extern "c" fn hypot(x: f64, y: f64) f64
```


### `modff`

```zig
pub extern "c" fn modff(x: f32, iptr: *f32) f32
```


### `modf`

```zig
pub extern "c" fn modf(x: f64, iptr: *f64) f64
```


### `modfl`

```zig
pub extern "c" fn modfl(x: c_longdouble, iptr: *c_longdouble) c_longdouble
```


### `rintf`

```zig
pub extern "c" fn rintf(x: f32) f32
```


### `rint`

```zig
pub extern "c" fn rint(x: f64) f64
```


### `rintl`

```zig
pub extern "c" fn rintl(x: c_longdouble) c_longdouble
```


## Constants & Variables

- **`iovec`**: 
- **`iovec_const`**: 
- **`LOCK`**: 
- **`winsize`**: 
- **`_mh_execute_header`**: The value of the link editor defined symbol _MH_EXECUTE_SYM is the address
- **`TIMERFD_CLOCK`**: 
- **`CLOCK`**: 
- **`FD_CLOEXEC`**: 
- **`F_OK`**: Test for existence of file.
- **`X_OK`**: Test for execute or search permission.
- **`W_OK`**: Test for write permission.
- **`R_OK`**: Test for read permission.
- **`HOST_NAME_MAX`**: 
- **`IOV_MAX`**: 
- **`NAME_MAX`**: 
- **`PATH_MAX`**: 
- **`STDIN_FILENO`**: 
- **`STDOUT_FILENO`**: 
- **`STDERR_FILENO`**: 
- **`TCSA`**: 
- **`cmsg_align`**: 
- **`IFNAMESIZE`**: 
- **`_errno`**: 
- **`MAXNAMLEN`**: 
- **`MAP_FAILED`**: Used by libc to communicate failure. Not actually part of the underlying syscall.
- **`NSIG`**: maximum signal number + 1
- **`MINSIGSTKSZ`**: 
- **`SIGSTKSZ`**: 
- **`close`**: 
- **`clock_getres`**: 
- **`clock_gettime`**: 
- **`fstat`**: 
- **`fstatat`**: 
- **`arc4random_buf`**: 
- **`getentropy`**: 
- **`getrandom`**: 
- **`sendfile`**: 
- **`sigaltstack`**: 
- **`pipe2`**: 
- **`copy_file_range`**: 
- **`getdirentries`**: 
- **`getdents`**: 
- **`getrusage`**: 
- **`gettimeofday`**: 
- **`mlock`**: 
- **`mlock2`**: 
- **`munlock`**: 
- **`mlockall`**: 
- **`munlockall`**: 
- **`msync`**: 
- **`nanosleep`**: 
- **`readdir`**: 
- **`realpath`**: 
- **`sched_yield`**: 
- **`sigaction`**: 
- **`sigrtmin`**: Zig's version of SIGRTMIN.  Actually a function.
- **`sigrtmax`**: Zig's version of SIGRTMAX.  Actually a function.
- **`sigfillset`**: 
- **`sigaddset`**: 
- **`sigemptyset`**: 
- **`sigdelset`**: 
- **`sigismember`**: 
- **`sigprocmask`**: 
- **`socket`**: 
- **`socketpair`**: 
- **`stat`**: 
- **`_msize`**: 
- **`malloc_size`**: 
- **`malloc_usable_size`**: 
- **`posix_memalign`**: 
- **`sysconf`**: 
- **`flock`**: 
- **`futex`**: 
- **`environ`**: 
- **`wait4`**: 
- **`fork`**: 
- **`recvmsg`**: 
- **`pthread_setname_np`**: 
- **`pthread_threadid_np`**: 
- **`ptrace`**: 
- **`shm_open`**: 
- **`PTHREAD_PROCESS_PRIVATE`**: 
- **`PTHREAD_PROCESS_SHARED`**: 
- **`PTHREAD_MUTEX_INITIALIZER`**: 
- **`PTHREAD_COND_INITIALIZER`**: 
- **`dladdr`**: 
- **`dl_info`**: 
- **`clock_nanosleep`**: 
- **`ioctl`**: 
- **`swab`**: 
- **`strdup`**: 
- **`wcsdup`**: 
- **`AF_SUN`**: 
- **`AT_SUN`**: 
- **`FILE_EVENT`**: 
- **`GETCONTEXT`**: 
- **`GETUSTACK`**: 
- **`PORT_ALERT`**: 
- **`PORT_SOURCE`**: 
- **`POSIX_FADV`**: 
- **`SETCONTEXT`**: 
- **`SETUSTACK`**: 
- **`SFD`**: 
- **`ctid_t`**: 
- **`file_obj`**: 
- **`id_t`**: 
- **`lif_ifinfo_req`**: 
- **`lif_nd_req`**: 
- **`lifreq`**: 
- **`major_t`**: 
- **`minor_t`**: 
- **`poolid_t`**: 
- **`port_notify`**: 
- **`priority`**: 
- **`procfs`**: 
- **`projid_t`**: 
- **`signalfd_siginfo`**: 
- **`taskid_t`**: 
- **`zoneid_t`**: 
- **`B_ABSOLUTE_TIMEOUT`**: 
- **`B_OS_NAME_LENGTH`**: 
- **`B_TIMEOUT_REAL_TIME_BASE`**: 
- **`DirEnt`**: 
- **`_kern_acquire_sem_etc`**: 
- **`_kern_create_sem`**: 
- **`_kern_delete_sem`**: 
- **`_kern_open_dir`**: 
- **`_kern_read_dir`**: 
- **`_kern_read_stat`**: 
- **`_kern_release_sem_etc`**: 
- **`_kern_rewind_dir`**: 
- **`area_id`**: 
- **`find_thread`**: 
- **`get_system_info`**: 
- **`on_exit_thread`**: 
- **`port_id`**: 
- **`readv_pos`**: 
- **`sem_id`**: 
- **`status_t`**: 
- **`system_info`**: 
- **`team_id`**: 
- **`thread_id`**: 
- **`writev_pos`**: 
- **`AUTH`**: 
- **`BI`**: 
- **`PTHREAD_STACK_MIN`**: 
- **`TCFLUSH`**: 
- **`TCIO`**: 
- **`auth_approval`**: 
- **`auth_call`**: 
- **`auth_cat`**: 
- **`auth_challenge`**: 
- **`auth_check_change`**: 
- **`auth_check_expire`**: 
- **`auth_checknologin`**: 
- **`auth_clean`**: 
- **`auth_close`**: 
- **`auth_clrenv`**: 
- **`auth_clroption`**: 
- **`auth_clroptions`**: 
- **`auth_getitem`**: 
- **`auth_getpwd`**: 
- **`auth_getstate`**: 
- **`auth_getvalue`**: 
- **`auth_item_t`**: 
- **`auth_mkvalue`**: 
- **`auth_open`**: 
- **`auth_session_t`**: 
- **`auth_setdata`**: 
- **`auth_setenv`**: 
- **`auth_setitem`**: 
- **`auth_setoption`**: 
- **`auth_setpwd`**: 
- **`auth_setstate`**: 
- **`auth_userchallenge`**: 
- **`auth_usercheck`**: 
- **`auth_userokay`**: 
- **`auth_userresponse`**: 
- **`auth_verify`**: 
- **`bcrypt`**: 
- **`bcrypt_checkpass`**: 
- **`bcrypt_gensalt`**: 
- **`bcrypt_newhash`**: 
- **`getpwnam_shadow`**: 
- **`getpwuid_shadow`**: 
- **`getthrid`**: 
- **`login_cap_t`**: 
- **`login_close`**: 
- **`login_getcapbool`**: 
- **`login_getcapnum`**: 
- **`login_getcapsize`**: 
- **`login_getcapstr`**: 
- **`login_getcaptime`**: 
- **`login_getclass`**: 
- **`login_getstyle`**: 
- **`pledge`**: 
- **`pw_dup`**: 
- **`setclasscontext`**: 
- **`setpassent`**: 
- **`setusercontext`**: 
- **`uid_from_user`**: 
- **`unveil`**: 
- **`user_from_uid`**: 
- **`CAP_RIGHTS_VERSION`**: 
- **`KINFO_FILE_SIZE`**: 
- **`UMTX_ABSTIME`**: 
- **`UMTX_OP`**: 
- **`_umtx_op`**: 
- **`_umtx_time`**: 
- **`cap_rights`**: 
- **`fflags_t`**: 
- **`fsblkcnt_t`**: 
- **`fsfilcnt_t`**: 
- **`kinfo_file`**: 
- **`kinfo_getfile`**: 
- **`CALENDAR_CLOCK`**: 
- **`COPYFILE`**: 
- **`CPUFAMILY`**: 
- **`PT`**: 
- **`DB_RECORDTYPE`**: 
- **`EXC`**: 
- **`EXCEPTION`**: 
- **`KEVENT`**: 
- **`MACH`**: 
- **`MACH_MSG_TYPE`**: 
- **`MACH_PORT_RIGHT`**: 
- **`MACH_TASK_BASIC_INFO`**: 
- **`MACH_TASK_BASIC_INFO_COUNT`**: 
- **`MATTR`**: 
- **`NSVersionOfRunTimeLibrary`**: 
- **`OPEN_MAX`**: 
- **`OS`**: 
- **`POSIX_SPAWN`**: 
- **`SYSPROTO_EVENT`**: 
- **`SYSPROTO_CONTROL`**: 
- **`TASK`**: 
- **`TASK_NULL`**: 
- **`TASK_VM_INFO`**: 
- **`TASK_VM_INFO_COUNT`**: 
- **`THREAD`**: 
- **`THREAD_BASIC_INFO`**: 
- **`THREAD_BASIC_INFO_COUNT`**: 
- **`THREAD_IDENTIFIER_INFO_COUNT`**: 
- **`THREAD_NULL`**: 
- **`THREAD_STATE_NONE`**: 
- **`UL`**: 
- **`VM`**: 
- **`_NSGetExecutablePath`**: 
- **`__getdirentries64`**: 
- **`__ulock_wait`**: 
- **`__ulock_wait2`**: 
- **`__ulock_wake`**: 
- **`_dyld_get_image_header`**: 
- **`_dyld_get_image_name`**: 
- **`_dyld_get_image_vmaddr_slide`**: 
- **`_dyld_image_count`**: 
- **`_dyld_get_image_header_containing_address`**: 
- **`dyld_image_path_containing_address`**: 
- **`_host_page_size`**: 
- **`boolean_t`**: 
- **`clock_get_time`**: 
- **`clock_serv_t`**: 
- **`clock_res_t`**: 
- **`@"close$NOCANCEL"`**: 
- **`dispatch`**: 
- **`fcopyfile`**: 
- **`renameatx_np`**: 
- **`host_t`**: 
- **`integer_t`**: 
- **`ipc_space_t`**: 
- **`ipc_space_port_t`**: 
- **`kern_return_t`**: 
- **`vm_size_t`**: 
- **`kevent64`**: 
- **`kevent64_s`**: 
- **`mach_absolute_time`**: 
- **`mach_continuous_time`**: 
- **`mach_hdr`**: 
- **`mach_host_self`**: 
- **`mach_msg`**: 
- **`mach_msg_return_t`**: 
- **`mach_msg_type_number_t`**: 
- **`mach_port_allocate`**: 
- **`mach_port_array_t`**: 
- **`mach_port_deallocate`**: 
- **`mach_port_insert_right`**: 
- **`mach_port_name_t`**: 
- **`mach_port_t`**: 
- **`mach_task_basic_info`**: 
- **`mach_task_self`**: 
- **`mach_timebase_info`**: 
- **`mach_timebase_info_data`**: 
- **`mach_timespec_t`**: 
- **`mach_vm_address_t`**: 
- **`mach_vm_protect`**: 
- **`mach_vm_read`**: 
- **`mach_vm_region`**: 
- **`mach_vm_region_recurse`**: 
- **`mach_vm_size_t`**: 
- **`mach_vm_write`**: 
- **`natural_t`**: 
- **`os_log_create`**: 
- **`os_log_t`**: 
- **`os_log_type_enabled`**: 
- **`os_log_type_t`**: 
- **`os_signpost_enabled`**: 
- **`os_signpost_id_generate`**: 
- **`os_signpost_id_make_with_pointer`**: 
- **`os_signpost_id_t`**: 
- **`os_signpost_interval_begin`**: 
- **`os_signpost_interval_end`**: 
- **`os_unfair_lock`**: 
- **`os_unfair_lock_assert_not_owner`**: 
- **`os_unfair_lock_assert_owner`**: 
- **`os_unfair_lock_lock`**: 
- **`os_unfair_lock_t`**: 
- **`os_unfair_lock_trylock`**: 
- **`os_unfair_lock_unlock`**: 
- **`pid_for_task`**: 
- **`posix_spawn`**: 
- **`posix_spawn_file_actions_addchdir_np`**: 
- **`posix_spawn_file_actions_addclose`**: 
- **`posix_spawn_file_actions_adddup2`**: 
- **`posix_spawn_file_actions_addfchdir_np`**: 
- **`posix_spawn_file_actions_addinherit_np`**: 
- **`posix_spawn_file_actions_addopen`**: 
- **`posix_spawn_file_actions_destroy`**: 
- **`posix_spawn_file_actions_init`**: 
- **`posix_spawn_file_actions_t`**: 
- **`posix_spawnattr_destroy`**: 
- **`posix_spawnattr_getflags`**: 
- **`posix_spawnattr_getpgroup`**: 
- **`posix_spawnattr_init`**: 
- **`posix_spawnattr_setflags`**: 
- **`posix_spawnattr_setpgroup`**: 
- **`posix_spawnattr_t`**: 
- **`posix_spawnp`**: 
- **`pthread_attr_get_qos_class_np`**: 
- **`pthread_attr_set_qos_class_np`**: 
- **`pthread_get_qos_class_np`**: 
- **`pthread_set_qos_class_self_np`**: 
- **`qos_class_t`**: 
- **`task_flavor_t`**: 
- **`task_for_pid`**: 
- **`task_get_exception_ports`**: 
- **`task_info`**: 
- **`task_info_t`**: 
- **`task_name_t`**: 
- **`task_resume`**: 
- **`task_set_exception_ports`**: 
- **`task_suspend`**: 
- **`task_threads`**: 
- **`task_vm_info_data_t`**: 
- **`thread_basic_info`**: 
- **`thread_get_state`**: 
- **`thread_identifier_info`**: 
- **`thread_info`**: 
- **`thread_info_t`**: 
- **`thread_resume`**: 
- **`thread_set_state`**: 
- **`vm_address_t`**: 
- **`vm_deallocate`**: 
- **`vm_machine_attribute`**: 
- **`vm_machine_attribute_t`**: 
- **`vm_machine_attribute_val_t`**: 
- **`vm_map_t`**: 
- **`vm_offset_t`**: 
- **`vm_prot_t`**: 
- **`vm_region_basic_info_64`**: 
- **`vm_region_extended_info`**: 
- **`vm_region_info_t`**: 
- **`vm_region_recurse_info_t`**: 
- **`vm_region_submap_info_64`**: 
- **`vm_region_submap_short_info_64`**: 
- **`vm_region_top_info`**: 
- **`exception_behavior_array_t`**: 
- **`exception_behavior_t`**: 
- **`exception_data_t`**: 
- **`exception_data_type_t`**: 
- **`exception_flavor_array_t`**: 
- **`exception_handler_array_t`**: 
- **`exception_handler_t`**: 
- **`exception_mask_array_t`**: 
- **`exception_mask_t`**: 
- **`exception_port_array_t`**: 
- **`exception_port_t`**: 
- **`exception_type_t`**: 
- **`mach_exception_data_t`**: 
- **`mach_exception_data_type_t`**: 
- **`mach_msg_bits_t`**: 
- **`mach_msg_id_t`**: 
- **`mach_msg_header_t`**: 
- **`mach_msg_option_t`**: 
- **`mach_msg_size_t`**: 
- **`mach_msg_timeout_t`**: 
- **`mach_msg_type_name_t`**: 
- **`mach_port_right_t`**: 
- **`memory_object_offset_t`**: 
- **`policy_t`**: 
- **`task_policy_flavor_t`**: 
- **`task_policy_t`**: 
- **`task_read_t`**: 
- **`task_t`**: 
- **`thread_act_t`**: 
- **`thread_flavor_t`**: 
- **`thread_port_t`**: 
- **`thread_state_flavor_t`**: 
- **`thread_state_t`**: 
- **`thread_t`**: 
- **`time_value_t`**: 
- **`vm32_object_id_t`**: 
- **`vm_behavior_t`**: 
- **`vm_inherit_t`**: 
- **`vm_map_read_t`**: 
- **`vm_object_id_t`**: 
- **`vm_region_flavor_t`**: 
- **`_ksiginfo`**: 
- **`_lwp_self`**: 
- **`_lwp_park`**: 
- **`_lwp_unpark`**: 
- **`_lwp_unpark_all`**: 
- **`lwpid_t`**: 
- **`lwp_gettid`**: 
- **`umtx_sleep`**: 
- **`umtx_wakeup`**: 
- **`PERF_EVENT`**: 
- **`disown`**: 
- **`profiling_enable`**: 
- **`profiling_disable`**: 
- **`profiling_free_buffer`**: 
- **`purge`**: 
- **`perf_event`**: 
- **`perf_register_string`**: 
- **`get_stack_bounds`**: 
- **`anon_create`**: 
- **`getkeymap`**: 
- **`setkeymap`**: 

