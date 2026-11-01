# `std.valgrind`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/valgrind.zig`  
> [← Back to Standard Library Index](README.md)

## Types

### `ClientRequest`


### Fields

- `RunningOnValgrind = 4097`
  
- `DiscardTranslations = 4098`
  
- `ClientCall0 = 4353`
  
- `ClientCall1 = 4354`
  
- `ClientCall2 = 4355`
  
- `ClientCall3 = 4356`
  
- `CountErrors = 4609`
  
- `GdbMonitorCommand = 4610`
  
- `MalloclikeBlock = 4865`
  
- `ResizeinplaceBlock = 4875`
  
- `FreelikeBlock = 4866`
  
- `CreateMempool = 4867`
  
- `DestroyMempool = 4868`
  
- `MempoolAlloc = 4869`
  
- `MempoolFree = 4870`
  
- `MempoolTrim = 4871`
  
- `MoveMempool = 4872`
  
- `MempoolChange = 4873`
  
- `MempoolExists = 4874`
  
- `Printf = 5121`
  
- `PrintfBacktrace = 5122`
  
- `PrintfValistByRef = 5123`
  
- `PrintfBacktraceValistByRef = 5124`
  
- `StackRegister = 5377`
  
- `StackDeregister = 5378`
  
- `StackChange = 5379`
  
- `LoadPdbDebuginfo = 5633`
  
- `MapIpToSrcloc = 5889`
  
- `ChangeErrDisablement = 6145`
  
- `VexInitForIri = 6401`
  
- `InnerThreads = 6402`
  

## Namespaces

- **`MempoolFlags`**: Create a memory pool.

## Functions

### `doClientRequest`

```zig
pub fn doClientRequest(default: usize, request: usize, a1: usize, a2: usize, a3: usize, a4: usize, a5: usize) usize
```


### `ToolBase`

```zig
pub fn ToolBase(base: [2]u8) u32
```


### `IsTool`

```zig
pub fn IsTool(base: [2]u8, code: usize) bool
```


### `runningOnValgrind`

```zig
pub fn runningOnValgrind() usize
```

Returns the number of Valgrinds this code is running under.  That
is, 0 if running natively, 1 if running under Valgrind, 2 if
running under Valgrind which is running under another Valgrind,
etc.

### `discardTranslations`

```zig
pub fn discardTranslations(qzz: []const u8) void
```

Discard translation of code in the slice qzz.  Useful if you are debugging
a JITter or some such, since it provides a way to make sure valgrind will
retranslate the invalidated area.  Returns no value.

### `innerThreads`

```zig
pub fn innerThreads(qzz: [*]u8) void
```


### `nonSimdCall0`

```zig
pub fn nonSimdCall0(func: fn (usize) usize) usize
```


### `nonSimdCall1`

```zig
pub fn nonSimdCall1(func: fn (usize, usize) usize, a1: usize) usize
```


### `nonSimdCall2`

```zig
pub fn nonSimdCall2(func: fn (usize, usize, usize) usize, a1: usize, a2: usize) usize
```


### `nonSimdCall3`

```zig
pub fn nonSimdCall3(func: fn (usize, usize, usize, usize) usize, a1: usize, a2: usize, a3: usize) usize
```


### `countErrors`

```zig
pub fn countErrors() usize
```

Counts the number of errors that have been recorded by a tool.  Nb:
the tool must record the errors with VG_(maybe_record_error)() or
VG_(unique_error)() for them to be counted.

### `mallocLikeBlock`

```zig
pub fn mallocLikeBlock(mem: []u8, rzB: usize, is_zeroed: bool) void
```


### `resizeInPlaceBlock`

```zig
pub fn resizeInPlaceBlock(oldmem: []u8, newsize: usize, rzB: usize) void
```


### `freeLikeBlock`

```zig
pub fn freeLikeBlock(addr: [*]u8, rzB: usize) void
```


### `createMempool`

```zig
pub fn createMempool(pool: [*]u8, rzB: usize, is_zeroed: bool, flags: usize) void
```


### `destroyMempool`

```zig
pub fn destroyMempool(pool: [*]u8) void
```

Destroy a memory pool.

### `mempoolAlloc`

```zig
pub fn mempoolAlloc(pool: [*]u8, mem: []u8) void
```

Associate a piece of memory with a memory pool.

### `mempoolFree`

```zig
pub fn mempoolFree(pool: [*]u8, addr: [*]u8) void
```

Disassociate a piece of memory from a memory pool.

### `mempoolTrim`

```zig
pub fn mempoolTrim(pool: [*]u8, mem: []u8) void
```

Disassociate any pieces outside a particular range.

### `moveMempool`

```zig
pub fn moveMempool(poolA: [*]u8, poolB: [*]u8) void
```

Resize and/or move a piece associated with a memory pool.

### `mempoolChange`

```zig
pub fn mempoolChange(pool: [*]u8, addrA: [*]u8, mem: []u8) void
```

Resize and/or move a piece associated with a memory pool.

### `mempoolExists`

```zig
pub fn mempoolExists(pool: [*]u8) bool
```

Return if a mempool exists.

### `stackRegister`

```zig
pub fn stackRegister(stack: []u8) usize
```

Mark a piece of memory as being a stack. Returns a stack id.
start is the lowest addressable stack byte, end is the highest
addressable stack byte.

### `stackDeregister`

```zig
pub fn stackDeregister(id: usize) void
```

Unmark the piece of memory associated with a stack id as being a stack.

### `stackChange`

```zig
pub fn stackChange(id: usize, newstack: []u8) void
```

Change the start and end address of the stack id.
start is the new lowest addressable stack byte, end is the new highest
addressable stack byte.

### `mapIpToSrcloc`

```zig
pub fn mapIpToSrcloc(addr: *const u8, buf64: [64]u8) usize
```

Map a code address to a source file name and line number.  buf64
must point to a 64-byte buffer in the caller's address space. The
result will be dumped in there and is guaranteed to be zero
terminated.  If no info is found, the first byte is set to zero.

### `disableErrorReporting`

```zig
pub fn disableErrorReporting() void
```

Disable error reporting for this thread.  Behaves in a stack like
way, so you can safely call this multiple times provided that
enableErrorReporting() is called the same number of times
to re-enable reporting.  The first call of this macro disables
reporting.  Subsequent calls have no effect except to increase the
number of enableErrorReporting() calls needed to re-enable
reporting.  Child threads do not inherit this setting from their
parents -- they are always created with reporting enabled.

### `enableErrorReporting`

```zig
pub fn enableErrorReporting() void
```

Re-enable error reporting. (see disableErrorReporting())

### `monitorCommand`

```zig
pub fn monitorCommand(command: [*]u8) bool
```

Execute a monitor command from the client program.
If a connection is opened with GDB, the output will be sent
according to the output mode set for vgdb.
If no connection is opened, output will go to the log output.
Returns 1 if command not recognised, 0 otherwise.

## Constants & Variables

- **`memcheck`**: 
- **`callgrind`**: 
- **`cachegrind`**: 

