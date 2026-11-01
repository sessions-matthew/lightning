# `std.BitStack`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/BitStack.zig`  
> [← Back to Standard Library Index](README.md)

Effectively a stack of u1 values implemented using ArrayList(u8).

## Fields

- `bytes: std.array_list.Managed(u8)`
  
- `bit_len: usize = 0`
  

## Functions

### `init`

```zig
pub fn init(allocator: Allocator) @This()
```


### `deinit`

```zig
pub fn deinit(self: *@This()) void
```


### `ensureTotalCapacity`

```zig
pub fn ensureTotalCapacity(self: *@This(), bit_capacity: usize) Allocator.Error!void
```


### `push`

```zig
pub fn push(self: *@This(), b: u1) Allocator.Error!void
```


### `peek`

```zig
pub fn peek(self: *const @This()) u1
```


### `pop`

```zig
pub fn pop(self: *@This()) u1
```


### `pushWithStateAssumeCapacity`

```zig
pub fn pushWithStateAssumeCapacity(buf: []u8, bit_len: *usize, b: u1) void
```

Standalone function for working with a fixed-size buffer.

### `peekWithState`

```zig
pub fn peekWithState(buf: []const u8, bit_len: usize) u1
```

Standalone function for working with a fixed-size buffer.

### `popWithState`

```zig
pub fn popWithState(buf: []const u8, bit_len: *usize) u1
```

Standalone function for working with a fixed-size buffer.

