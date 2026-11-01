# `std.priority_dequeue`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/priority_dequeue.zig`  
> [← Back to Standard Library Index](README.md)

## Types

### `PriorityDequeue`

```zig
pub fn PriorityDequeue(comptime T: type, comptime Context: type, comptime compareFn: fn (context: Context, a: T, b: T) Order) type
```

Priority Dequeue for storing generic data. Initialize with `init`.
Provide `compareFn` that returns `Order.lt` when its second
argument should get min-popped before its third argument,
`Order.eq` if the arguments are of equal priority, or `Order.gt`
if the third argument should be min-popped second.
Popping the max element works in reverse. For example,
to make `popMin` return the smallest number, provide
`fn lessThan(context: void, a: T, b: T) Order { _ = context; return std.math.order(a, b); }`

### Fields

- `items: []T`
  
- `len: usize`
  
- `context: Context`
  

### Types

#### `Iterator`


### Functions

#### `initContext`

```zig
pub fn initContext(context: Context) Self
```

Initialize and return a new priority dequeue with context.

#### `deinit`

```zig
pub fn deinit(self: *Self, allocator: Allocator) void
```

Free memory used by the dequeue.

#### `push`

```zig
pub fn push(self: *Self, allocator: Allocator, elem: T) !void
```

Insert a new element, maintaining priority.

#### `pushSlice`

```zig
pub fn pushSlice(self: *Self, allocator: Allocator, items: []const T) !void
```

Add each element in `items` to the dequeue.

#### `peekMin`

```zig
pub fn peekMin(self: *const Self) ?T
```

Look at the smallest element in the dequeue. Returns
`null` if empty.

#### `peekMax`

```zig
pub fn peekMax(self: *const Self) ?T
```

Look at the largest element in the dequeue. Returns
`null` if empty.

#### `popMin`

```zig
pub fn popMin(self: *Self) ?T
```

Remove and return the smallest element from the dequeue, or `null` if empty

#### `popMax`

```zig
pub fn popMax(self: *Self) ?T
```

Remove and return the largest element from the dequeue, or `null` if empty

#### `popIndex`

```zig
pub fn popIndex(self: *Self, index: usize) T
```

Remove and return element at index. Indices are in the
same order as iterator, which is not necessarily priority
order.

#### `count`

```zig
pub fn count(self: *const Self) usize
```

Return the number of elements remaining in the dequeue

#### `capacity`

```zig
pub fn capacity(self: *const Self) usize
```

Return the number of elements that can be added to the
dequeue before more memory is allocated.

#### `fromOwnedSlice`

```zig
pub fn fromOwnedSlice(items: []T, context: Context) Self
```

Dequeue takes ownership of the passed in slice. The slice must be de-initialize
with `deinit`.

#### `ensureTotalCapacity`

```zig
pub fn ensureTotalCapacity(self: *Self, allocator: Allocator, new_capacity: usize) !void
```

Ensure that the dequeue can fit at least `new_capacity` items.

#### `ensureUnusedCapacity`

```zig
pub fn ensureUnusedCapacity(self: *Self, allocator: Allocator, additional_count: usize) !void
```

Ensure that the dequeue can fit at least `additional_count` **more** items.

#### `shrinkAndFree`

```zig
pub fn shrinkAndFree(self: *Self, allocator: Allocator, new_len: usize) void
```

Reduce allocated capacity to `new_len`.

#### `update`

```zig
pub fn update(self: *Self, elem: T, new_elem: T) !void
```


#### `iterator`

```zig
pub fn iterator(self: *Self) Iterator
```

Return an iterator that walks the queue without consuming
it. The iteration order may differ from the priority order.
Invalidated if the queue is modified.

### Constants & Variables

- **`empty`**: A priority dequeue containing no elements.

