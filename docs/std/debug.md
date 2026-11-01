# `std.debug`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/debug.zig`  
> [← Back to Standard Library Index](README.md)

## Types

### `SelfInfo`

This type abstracts the target-specific implementation of accessing this process' own debug
information behind a generic interface which supports looking up source locations associated
with addresses, as well as unwinding the stack where a safe mechanism to do so exists.

The Zig Standard Library provides default implementations of `SelfInfo` for common targets, but
the implementation can be overriden by exposing `root.debug.SelfInfo`. Setting `SelfInfo` to
`void` indicates that the `SelfInfo` API is not supported.

This type must expose the following declarations:

```
pub const init: SelfInfo;
pub fn deinit(si: *SelfInfo, io: Io) void;

/// Appends the symbols for the instruction at `address` to `symbols`.
pub fn getSymbols(si: *SelfInfo, io: Io, symbol_allocator: Allocator, text_arena: Allocator, address: usize, include_inline_callers: bool, symbols: *std.ArrayList(Symbol)) SelfInfoError!void;
/// Returns a name for the "module" (e.g. shared library or executable image) containing `address`.
pub fn getModuleName(si: *SelfInfo, io: Io, address: usize) SelfInfoError![]const u8;
pub fn getModuleSlide(si: *SelfInfo, io: Io, address: usize) SelfInfoError!usize;

/// Whether a reliable stack unwinding strategy, such as DWARF unwinding, is available.
pub const can_unwind: bool;
/// Only required if `can_unwind == true`.
pub const UnwindContext = struct {
    /// An address representing the instruction pointer in the last frame.
    pc: usize,

    pub fn init(ctx: *cpu_context.Native) Allocator.Error!UnwindContext;
    pub fn deinit(ctx: *UnwindContext) void;
    /// Returns the frame pointer associated with the last unwound stack frame.
    /// If the frame pointer is unknown, 0 may be returned instead.
    pub fn getFp(uc: *UnwindContext) usize;
};
/// Only required if `can_unwind == true`. Unwinds a single stack frame, returning the frame's
/// return address, or 0 if the end of the stack has been reached.
pub fn unwindFrame(si: *SelfInfo, io: Io, context: *UnwindContext) SelfInfoError!usize;
```

### `TargetInfo`

```zig
pub fn TargetInfo(os: std.Target.Os.Tag, arch: std.Target.Cpu.Arch) type
```

Returns the default `SelfInfo` for the given `os` and `arch`.

### `FullPanic`

```zig
pub fn FullPanic(comptime panicFn: fn ([]const u8, ?usize) noreturn) type
```

A fully-featured panic handler namespace which lowers all panics to calls to `panicFn`.
Safety panics will use formatted printing to provide a meaningful error message.
The signature of `panicFn` should match that of `defaultPanic`.

### Functions

#### `sentinelMismatch`

```zig
pub fn sentinelMismatch(expected: anytype, found: @TypeOf(expected)) noreturn
```


#### `unwrapError`

```zig
pub fn unwrapError(err: anyerror) noreturn
```


#### `outOfBounds`

```zig
pub fn outOfBounds(index: usize, len: usize) noreturn
```


#### `startGreaterThanEnd`

```zig
pub fn startGreaterThanEnd(start: usize, end: usize) noreturn
```


#### `inactiveUnionField`

```zig
pub fn inactiveUnionField(active: anytype, accessed: @TypeOf(active)) noreturn
```


#### `sliceCastLenRemainder`

```zig
pub fn sliceCastLenRemainder(src_len: usize) noreturn
```


#### `reachedUnreachable`

```zig
pub fn reachedUnreachable() noreturn
```


#### `unwrapNull`

```zig
pub fn unwrapNull() noreturn
```


#### `castToNull`

```zig
pub fn castToNull() noreturn
```


#### `incorrectAlignment`

```zig
pub fn incorrectAlignment() noreturn
```


#### `invalidErrorCode`

```zig
pub fn invalidErrorCode() noreturn
```


#### `unexpectedErrorCode`

```zig
pub fn unexpectedErrorCode(err: anyerror) noreturn
```


#### `integerOutOfBounds`

```zig
pub fn integerOutOfBounds() noreturn
```


#### `integerOverflow`

```zig
pub fn integerOverflow() noreturn
```


#### `shlOverflow`

```zig
pub fn shlOverflow() noreturn
```


#### `shrOverflow`

```zig
pub fn shrOverflow() noreturn
```


#### `divideByZero`

```zig
pub fn divideByZero() noreturn
```


#### `exactDivisionRemainder`

```zig
pub fn exactDivisionRemainder() noreturn
```


#### `integerPartOutOfBounds`

```zig
pub fn integerPartOutOfBounds() noreturn
```


#### `corruptSwitch`

```zig
pub fn corruptSwitch() noreturn
```


#### `shiftRhsTooBig`

```zig
pub fn shiftRhsTooBig() noreturn
```


#### `invalidEnumValue`

```zig
pub fn invalidEnumValue() noreturn
```


#### `forLenMismatch`

```zig
pub fn forLenMismatch() noreturn
```


#### `copyLenMismatch`

```zig
pub fn copyLenMismatch() noreturn
```


#### `memcpyAlias`

```zig
pub fn memcpyAlias() noreturn
```


#### `noreturnReturned`

```zig
pub fn noreturnReturned() noreturn
```


#### `loadUninstantiableType`

```zig
pub fn loadUninstantiableType() noreturn
```


### Constants & Variables

- **`call`**: 

### `SourceLocation`

Unresolved source locations can be represented with a single `usize` that
corresponds to a virtual memory address of the program counter. Combined
with debug information, those values can be converted into a resolved
source location, including file, line, and column.

### Fields

- `line: u64`
  
- `column: u64`
  
- `file_name: []const u8`
  

### Constants & Variables

- **`invalid`**: 

### `Symbol`


### Fields

- `name: ?[]const u8`
  
- `compile_unit_name: ?[]const u8`
  
- `source_location: ?SourceLocation`
  

### Constants & Variables

- **`unknown`**: 

### `CpuContextPtr`

The pointer through which a `cpu_context.Native` is received from callers of stack tracing logic.

### `StackTrace`


### Fields

- `return_addresses: []usize`
  Each element is the "return address" of a function call, meaning the instruction address
  which control flow will return to when the function returns.
  
  The first slice element corresponds to the innermost stack frame, and the last element to
  the outermost.
  
  Inlined function calls do not have meaningful return addresses and are therefore not
  included in this slice. Instead, when printing the stack trace, the source locations of
  inline calls should be read from debug information and the corresponding "inline frames"
  printed in the appropriate locations.
- `skipped: SkippedAddresses`
  Indicates whether any stack frames were omitted from `return_addresses`.

### `SkippedAddresses`

Indicates how many addresses were skipped in a trace.

### Fields

- `none = 0`
  No addresses were omitted: `return_addresses` contains all stack frames, including the
  outermost.
- `unknown = std.math.maxInt(usize)`
  It is not known whether any frames were omitted.
- `_`
  The full stack trace was available, but some frames are not included in
  `return_addresses` due to buffer size limitations. The enum value is the exact number of
  addresses which were omitted.

### `StackUnwindOptions`


### Fields

- `first_address: ?usize = null`
  If not `null`, we will ignore all frames up until this return address. This is typically
  used to omit intermediate handling code (for instance, a panic handler and its machinery)
  from stack traces.
- `context: ?CpuContextPtr = null`
  If not `null`, we will unwind from this `cpu_context.Native` instead of the current top of
  the stack. The main use case here is printing stack traces from signal handlers, where the
  kernel provides a `*const cpu_context.Native` of the state before the signal.
- `allow_unsafe_unwind: bool = false`
  If `true`, stack unwinding strategies which may cause crashes are used as a last resort.
  If `false`, only known-safe mechanisms will be attempted.

### `FormatStackTrace`


### Fields

- `stack_trace: StackTrace`
  
- `terminal_mode: Io.Terminal.Mode = .no_color`
  

### Functions

#### `format`

```zig
pub fn format(fst: FormatStackTrace, writer: *Writer) Writer.Error!void
```


### `Trace`

This API helps you track where a value originated and where it was mutated,
or any other points of interest.
In debug mode, it adds a small size penalty (104 bytes on 64-bit architectures)
to the aggregate that you add it to.
In release mode, it is size 0 and all methods are no-ops.
This is a pre-made type with default settings.
For more advanced usage, see `ConfigurableTrace`.

### `ConfigurableTrace`

```zig
pub fn ConfigurableTrace(comptime size: usize, comptime stack_frame_count: usize, comptime is_enabled: bool) type
```


### Fields

- `addrs: [actual_size][stack_frame_count]usize`
  
- `notes: [actual_size][]const u8`
  
- `index: Index`
  

### Functions

#### `addNoInline`

```zig
pub noinline fn addNoInline(t: *@This(), note: []const u8) void
```


#### `addNoOp`

```zig
pub inline fn addNoOp(t: *@This(), note: []const u8) void
```


#### `addAddr`

```zig
pub fn addAddr(t: *@This(), addr: usize, note: []const u8) void
```


#### `dump`

```zig
pub fn dump(t: @This()) void
```


#### `format`

```zig
pub fn format(t: @This(), comptime fmt: []const u8, options: std.fmt.Options, writer: *Writer, ) !void
```


### Constants & Variables

- **`init`**: 
- **`enabled`**: 
- **`add`**: 

### `SafetyLock`


### Fields

- `state: State = if (runtime_safety) .unlocked else .unknown`
  

### Types

#### `State`


### Functions

#### `lock`

```zig
pub fn lock(l: *SafetyLock) void
```

Exclusive. Use when mutating data.

#### `unlock`

```zig
pub fn unlock(l: *SafetyLock) void
```


#### `lockShared`

```zig
pub fn lockShared(l: *SafetyLock) void
```

Use when consuming data in a read-only manner.

#### `unlockShared`

```zig
pub fn unlockShared(l: *SafetyLock) void
```


#### `assertUnlocked`

```zig
pub fn assertUnlocked(l: SafetyLock) void
```


#### `assertLocked`

```zig
pub fn assertLocked(l: SafetyLock) void
```


#### `assertLockedShared`

```zig
pub fn assertLockedShared(l: SafetyLock) void
```


## Functions

### `lockStderr`

```zig
pub fn lockStderr(buffer: []u8) Io.LockedStderr
```

Allows the caller to freely write to stderr until `unlockStderr` is called.

During the lock, any `std.Progress` information is cleared from the terminal.

The lock is recursive, so it is valid for the same thread to call
`lockStderr` multiple times, allowing the panic handler to safely
dump the stack trace and panic message even if the mutex was held at the
panic site.

The returned `Writer` does not need to be manually flushed: flushing is
performed automatically when the matching `unlockStderr` call occurs.

This is a low-level debugging primitive that bypasses the `Io` interface,
writing directly to stderr using the most basic syscalls available. This
function does not switch threads, switch stacks, or suspend.

Alternatively, use the higher-level `Io.lockStderr` to integrate with the
application's chosen `Io` implementation.

### `unlockStderr`

```zig
pub fn unlockStderr() void
```


### `print`

```zig
pub fn print(comptime fmt: []const u8, args: anytype) void
```

Writes to stderr, ignoring errors.

This is a low-level debugging primitive that bypasses the `Io` interface,
writing directly to stderr using the most basic syscalls available. This
function does not switch threads, switch stacks, or suspend.

Uses a 64-byte buffer for formatted printing which is flushed before this
function returns.

Alternatively, use the higher-level `std.log` or `Io.lockStderr` to
integrate with the application's chosen `Io` implementation.

### `getSelfDebugInfo`

```zig
pub inline fn getSelfDebugInfo() !*SelfInfo
```

Marked `inline` to propagate a comptime-known error to callers.

### `dumpHex`

```zig
pub fn dumpHex(bytes: []const u8) void
```

Tries to print a hexadecimal view of the bytes, unbuffered, and ignores any error returned.
Obtains the stderr mutex while dumping.

### `dumpHexFallible`

```zig
pub fn dumpHexFallible(t: Io.Terminal, bytes: []const u8) !void
```

Prints a hexadecimal view of the bytes, returning any error that occurs.

### `assert`

```zig
pub fn assert(ok: bool) void
```

Invokes detectable illegal behavior when `ok` is `false`.

In debug and safe modes, calls to this function are always
generated, and the `unreachable` statement triggers a panic.

In fast and small modes, calls to this function are optimized
away, and in fact the optimizer is able to use the assertion in its
heuristics.

Inside a test block, it is best to use the `testing` module rather than
this function, because this function may not detect a test failure in
fast and small mode. Outside of a test block, this assert
function is the correct function to use.

### `assertReadable`

```zig
pub fn assertReadable(slice: []const volatile u8) void
```

Invokes detectable illegal behavior when the provided slice is not mapped
or lacks read permissions.

### `assertAligned`

```zig
pub fn assertAligned(ptr: anytype, comptime alignment: std.mem.Alignment) void
```

Invokes detectable illegal behavior when the provided array is not aligned
to the provided amount.

### `panic`

```zig
pub fn panic(comptime format: []const u8, args: anytype) noreturn
```

Equivalent to `@panic` but with a formatted message.

### `panicExtra`

```zig
pub fn panicExtra(ret_addr: ?usize, comptime format: []const u8, args: anytype, ) noreturn
```

Equivalent to `@panic` but with a formatted message and an explicitly provided return address
which will be the first address in the stack trace.

### `defaultPanic`

```zig
pub fn defaultPanic(msg: []const u8, first_trace_addr: ?usize) noreturn
```

Dumps a stack trace to standard error, then aborts.

### `captureCurrentStackTrace`

```zig
pub noinline fn captureCurrentStackTrace(options: StackUnwindOptions, addr_buf: []usize) StackTrace
```

Capture and return the current stack trace. The returned `StackTrace` stores its addresses in
the given buffer, so `addr_buf` must have a lifetime at least equal to the `StackTrace`.

See `writeCurrentStackTrace` to immediately print the trace instead of capturing it.

### `writeCurrentStackTrace`

```zig
pub noinline fn writeCurrentStackTrace(options: StackUnwindOptions, t: Io.Terminal) Writer.Error!void
```

Write the current stack trace to `writer`, annotated with source locations.

See `captureCurrentStackTrace` to capture the trace addresses into a buffer instead of printing.

### `dumpCurrentStackTrace`

```zig
pub fn dumpCurrentStackTrace(options: StackUnwindOptions) void
```

A thin wrapper around `writeCurrentStackTrace` which writes to stderr and ignores write errors.

### `writeErrorReturnTrace`

```zig
pub fn writeErrorReturnTrace(et: *const std.builtin.StackTrace, t: Io.Terminal) Writer.Error!void
```

Write a previously captured error return trace to `writer`, annotated with source locations.

### `writeStackTrace`

```zig
pub fn writeStackTrace(st: *const StackTrace, t: Io.Terminal) Writer.Error!void
```

Write a previously captured stack trace to `writer`, annotated with source locations.

### `dumpStackTrace`

```zig
pub fn dumpStackTrace(st: *const StackTrace) void
```

A thin wrapper around `writeStackTrace` which writes to stderr and ignores write errors.

### `dumpErrorReturnTrace`

```zig
pub fn dumpErrorReturnTrace(et: *const std.builtin.StackTrace) void
```

A thin wrapper around `writeErrorReturnTrace` which writes to stderr and ignores write errors.

### `stripInstructionPtrAuthCode`

```zig
pub inline fn stripInstructionPtrAuthCode(ptr: usize) usize
```

Some platforms use pointer authentication: the upper bits of instruction pointers contain a
signature. This function clears those signature bits to make the pointer directly usable.

### `getDebugInfoAllocator`

```zig
pub fn getDebugInfoAllocator() Allocator
```

The returned allocator should be thread-safe if the compilation is multi-threaded, because
multiple threads could capture and/or print stack traces simultaneously.

### `maybeEnableSegfaultHandler`

```zig
pub fn maybeEnableSegfaultHandler() void
```


### `updateSegfaultHandler`

```zig
pub fn updateSegfaultHandler(act: ?*const posix.Sigaction) void
```


### `attachSegfaultHandler`

```zig
pub fn attachSegfaultHandler() void
```

Attaches a global handler for several signals which, when triggered, prints output to stderr
similar to the default panic handler, with a message containing the type of signal and a stack
trace if possible. This implementation does not just call the panic handler, because unwinding
the stack (for a stack trace) when a signal is received requires special target-specific logic.

On POSIX targets, the signal handler is configured to use the alternative signal stack. Such a
stack is configured by the Zig Standard Library if `std.options.signal_stack_size` is set.

The signals for which a handler is installed are:
* SIGSEGV (segmentation fault)
* SIGILL (illegal instruction)
* SIGBUS (bus error)
* SIGFPE (arithmetic exception)

### `defaultHandleSegfault`

```zig
pub fn defaultHandleSegfault(addr: ?usize, name: []const u8, opt_ctx: ?CpuContextPtr) noreturn
```


### `dumpStackPointerAddr`

```zig
pub fn dumpStackPointerAddr(prefix: []const u8) void
```


### `inValgrind`

```zig
pub inline fn inValgrind() bool
```

Detect whether the program is being executed in the Valgrind virtual machine.

When Valgrind integrations are disabled, this returns comptime-known false.
Otherwise, the result is runtime-known.

## Error Sets

- **`SelfInfoError`**
  

## Constants & Variables

- **`Dwarf`**: 
- **`Pdb`**: 
- **`ElfFile`**: 
- **`MachOFile`**: 
- **`Info`**: 
- **`Coverage`**: 
- **`cpu_context`**: 
- **`simple_panic`**: 
- **`no_panic`**: 
- **`runtime_safety`**: Deprecated in favor of `std.lang.Optimize.runtimeSafety`, to be removed after 0.18.0
- **`sys_can_stack_trace`**: Whether we can unwind the stack on this target, allowing capturing and/or printing the current
- **`have_segfault_handling_support`**: Whether or not the current target can print useful debug information when a segfault occurs.
- **`default_enable_segfault_handler`**: 

