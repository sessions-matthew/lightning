# `std.atomic`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/atomic.zig`  
> [← Back to Standard Library Index](README.md)

## Types

### `Value`

```zig
pub fn Value(comptime T: type) type
```

This is a thin wrapper around a primitive value to prevent accidental data races.

### Fields

- `raw: T`
  Care must be taken to avoid data races when interacting with this field directly.

### Functions

#### `init`

```zig
pub fn init(value: T) Self
```


#### `load`

```zig
pub inline fn load(self: *const Self, comptime order: AtomicOrder) T
```


#### `store`

```zig
pub inline fn store(self: *Self, value: T, comptime order: AtomicOrder) void
```


#### `swap`

```zig
pub inline fn swap(self: *Self, operand: T, comptime order: AtomicOrder) T
```


#### `cmpxchgWeak`

```zig
pub inline fn cmpxchgWeak(self: *Self, expected_value: T, new_value: T, comptime success_order: AtomicOrder, comptime fail_order: AtomicOrder, ) ?T
```


#### `cmpxchgStrong`

```zig
pub inline fn cmpxchgStrong(self: *Self, expected_value: T, new_value: T, comptime success_order: AtomicOrder, comptime fail_order: AtomicOrder, ) ?T
```


#### `fetchAdd`

```zig
pub inline fn fetchAdd(self: *Self, operand: T, comptime order: AtomicOrder) T
```


#### `fetchSub`

```zig
pub inline fn fetchSub(self: *Self, operand: T, comptime order: AtomicOrder) T
```


#### `fetchMin`

```zig
pub inline fn fetchMin(self: *Self, operand: T, comptime order: AtomicOrder) T
```


#### `fetchMax`

```zig
pub inline fn fetchMax(self: *Self, operand: T, comptime order: AtomicOrder) T
```


#### `fetchAnd`

```zig
pub inline fn fetchAnd(self: *Self, operand: T, comptime order: AtomicOrder) T
```


#### `fetchNand`

```zig
pub inline fn fetchNand(self: *Self, operand: T, comptime order: AtomicOrder) T
```


#### `fetchXor`

```zig
pub inline fn fetchXor(self: *Self, operand: T, comptime order: AtomicOrder) T
```


#### `fetchOr`

```zig
pub inline fn fetchOr(self: *Self, operand: T, comptime order: AtomicOrder) T
```


#### `rmw`

```zig
pub inline fn rmw(self: *Self, comptime op: std.builtin.AtomicRmwOp, operand: T, comptime order: AtomicOrder, ) T
```


#### `bitSet`

```zig
pub inline fn bitSet(self: *Self, bit: Bit, comptime order: AtomicOrder) u1
```

Marked `inline` so that if `bit` is comptime-known, the instruction
can be lowered to a more efficient machine code instruction if
possible.

#### `bitReset`

```zig
pub inline fn bitReset(self: *Self, bit: Bit, comptime order: AtomicOrder) u1
```

Marked `inline` so that if `bit` is comptime-known, the instruction
can be lowered to a more efficient machine code instruction if
possible.

#### `bitToggle`

```zig
pub inline fn bitToggle(self: *Self, bit: Bit, comptime order: AtomicOrder) u1
```

Marked `inline` so that if `bit` is comptime-known, the instruction
can be lowered to a more efficient machine code instruction if
possible.

### `Mutex`

A lock-free single-owner resource.

### Fields

- `unlocked`
  
- `locked`
  

### Functions

#### `tryLock`

```zig
pub fn tryLock(m: *Mutex) bool
```


#### `unlock`

```zig
pub fn unlock(m: *Mutex) void
```


## Functions

### `spinLoopHint`

```zig
pub inline fn spinLoopHint() void
```

Signals to the processor that the caller is inside a busy-wait spin-loop.

### `cacheLineForCpu`

```zig
pub fn cacheLineForCpu(cpu: std.Target.Cpu) u16
```


## Constants & Variables

- **`cache_line`**: The estimated size of the CPU's cache line when atomically updating memory.

