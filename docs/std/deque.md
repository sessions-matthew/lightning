# `std.deque`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/deque.zig`  
> [← Back to Standard Library Index](README.md)

## Types

### `Deque`

```zig
pub fn Deque(comptime T: type) type
```

A contiguous, growable, double-ended queue.

Pushing/popping items from either end of the queue is O(1).

### Fields

- `buffer: []T`
  A ring buffer.
- `head: usize`
  The index in buffer where the first item in the logical deque is stored.
- `len: usize`
  The number of items stored in the logical deque.

### Types

#### `Iterator`


### Functions

#### `initCapacity`

```zig
pub fn initCapacity(gpa: Allocator, capacity: usize) Allocator.Error!Self
```

Initialize with capacity to hold `capacity` elements.
The resulting capacity will equal `capacity` exactly.
Deinitialize with `deinit`.

#### `initBuffer`

```zig
pub fn initBuffer(buffer: []T) Self
```

Initialize with externally-managed memory. The buffer determines the
capacity and the deque is initially empty.

When initialized this way, all functions that accept an Allocator
argument cause illegal behavior.

#### `deinit`

```zig
pub fn deinit(deque: *Self, gpa: Allocator) void
```

Release all allocated memory.

#### `ensureTotalCapacity`

```zig
pub fn ensureTotalCapacity(deque: *Self, gpa: Allocator, new_capacity: usize) Allocator.Error!void
```

Modify the deque so that it can hold at least `new_capacity` items.
Implements super-linear growth to achieve amortized O(1) push/pop operations.
Invalidates element pointers if additional memory is needed.

#### `ensureTotalCapacityPrecise`

```zig
pub fn ensureTotalCapacityPrecise(deque: *Self, gpa: Allocator, new_capacity: usize) Allocator.Error!void
```

If the current capacity is less than `new_capacity`, this function will
modify the deque so that it can hold exactly `new_capacity` items.
Invalidates element pointers if additional memory is needed.

#### `ensureUnusedCapacity`

```zig
pub fn ensureUnusedCapacity(deque: *Self, gpa: Allocator, additional_count: usize, ) Allocator.Error!void
```

Modify the deque so that it can hold at least `additional_count` **more** items.
Invalidates element pointers if additional memory is needed.

#### `pushFront`

```zig
pub fn pushFront(deque: *Self, gpa: Allocator, item: T) error{OutOfMemory}!void
```

Add one item to the front of the deque.

Invalidates element pointers if additional memory is needed.

#### `pushFrontBounded`

```zig
pub fn pushFrontBounded(deque: *Self, item: T) error{OutOfMemory}!void
```

Add one item to the front of the deque.

Never invalidates element pointers.

If the deque lacks unused capacity for the additional item, returns
`error.OutOfMemory`.

#### `pushFrontAssumeCapacity`

```zig
pub fn pushFrontAssumeCapacity(deque: *Self, item: T) void
```

Add one item to the front of the deque.

Never invalidates element pointers.

Asserts that the deque can hold one additional item.

#### `pushBack`

```zig
pub fn pushBack(deque: *Self, gpa: Allocator, item: T) error{OutOfMemory}!void
```

Add one item to the back of the deque.

Invalidates element pointers if additional memory is needed.

#### `pushBackBounded`

```zig
pub fn pushBackBounded(deque: *Self, item: T) error{OutOfMemory}!void
```

Add one item to the back of the deque.

Never invalidates element pointers.

If the deque lacks unused capacity for the additional item, returns
`error.OutOfMemory`.

#### `pushBackAssumeCapacity`

```zig
pub fn pushBackAssumeCapacity(deque: *Self, item: T) void
```

Add one item to the back of the deque.

Never invalidates element pointers.

Asserts that the deque can hold one additional item.

#### `pushFrontSlice`

```zig
pub fn pushFrontSlice(deque: *Self, gpa: Allocator, items: []const T) error{OutOfMemory}!void
```

Add `items` to the front of the deque.
This is equivalent to iterating `items` in reverse and calling
`pushFront` on every single entry.

Invalidates element pointers if additional memory is needed.

#### `pushFrontSliceBounded`

```zig
pub fn pushFrontSliceBounded(deque: *Self, items: []const T) error{OutOfMemory}!void
```

Add `items` to the front of the deque.
This is equivalent to iterating `items` in reverse and calling
`pushFront` on every single entry.

Never invalidates element pointers.

If the deque lacks unused capacity for the additional items, returns
`error.OutOfMemory`.

#### `pushFrontSliceAssumeCapacity`

```zig
pub fn pushFrontSliceAssumeCapacity(deque: *Self, items: []const T) void
```

Add `items` to the front of the deque.
This is equivalent to iterating `items` in reverse and calling
`pushFront` on every single entry.

Never invalidates element pointers.

Asserts that the deque can hold the additional items.

#### `pushBackSlice`

```zig
pub fn pushBackSlice(deque: *Self, gpa: Allocator, items: []const T) error{OutOfMemory}!void
```

Add `items` to the back of the deque.
This is equivalent to iterating `items` in order and calling
`pushBack` on every single entry.

Invalidates element pointers if additional memory is needed.

#### `pushBackSliceBounded`

```zig
pub fn pushBackSliceBounded(deque: *Self, items: []const T) error{OutOfMemory}!void
```

Add `items` to the back of the deque.
This is equivalent to iterating `items` in order and calling
`pushBack` on every single entry.

Never invalidates element pointers.

If the deque lacks unused capacity for the additional items, returns
`error.OutOfMemory`.

#### `pushBackSliceAssumeCapacity`

```zig
pub fn pushBackSliceAssumeCapacity(deque: *Self, items: []const T) void
```

Add `items` to the back of the deque.
This is equivalent to iterating `items` in order and calling
`pushBack` on every single entry.

Never invalidates element pointers.

Asserts that the deque can hold the additional items.

#### `front`

```zig
pub fn front(deque: *const Self) ?T
```

Return the first item in the deque or null if empty.

#### `frontPtr`

```zig
pub fn frontPtr(deque: *const Self) ?*T
```

Return pointer to the first item in the deque or null if empty.

#### `back`

```zig
pub fn back(deque: *const Self) ?T
```

Return the last item in the deque or null if empty.

#### `backPtr`

```zig
pub fn backPtr(deque: *const Self) ?*T
```

Return the last item in the deque or null if empty.

#### `at`

```zig
pub fn at(deque: *const Self, index: usize) T
```

Return the item at the given index in the deque.

The first item in the queue is at index 0.

Asserts that the index is in-bounds.

#### `atPtr`

```zig
pub fn atPtr(deque: *const Self, index: usize) *T
```

Return pointer to the item at the given index in the deque.

The first item in the queue is at index 0.

Asserts that the index is in-bounds.

#### `popFront`

```zig
pub fn popFront(deque: *Self) ?T
```

Remove and return the first item in the deque or null if empty.

#### `popBack`

```zig
pub fn popBack(deque: *Self) ?T
```

Remove and return the last item in the deque or null if empty.

#### `iterator`

```zig
pub fn iterator(deque: *const Self) Iterator
```

Iterates over all items in the deque in order from front to back.

### Constants & Variables

- **`empty`**: A Deque containing no elements.

