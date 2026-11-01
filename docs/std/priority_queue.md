# `std.priority_queue`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/priority_queue.zig`  
> [← Back to Standard Library Index](README.md)

## Types

### `PriorityQueue`

```zig
pub fn PriorityQueue(comptime T: type, comptime Context: type, comptime compareFn: fn (context: Context, a: T, b: T) Order) type
```

Priority queue for storing generic data. Initialize with `init`.
Provide `compareFn` that returns `Order.lt` when its second
argument should get popped before its third argument,
`Order.eq` if the arguments are of equal priority, or `Order.gt`
if the third argument should be popped first.
For example, to make `pop` return the smallest number, provide
`fn lessThan(context: void, a: T, b: T) Order { _ = context; return std.math.order(a, b); }`

### Fields

- `items: []T`
  
- `cap: usize`
  
- `context: Context`
  

### Types

#### `Iterator`


### Functions

#### `initContext`

```zig
pub fn initContext(context: Context) Self
```

Initialize and return a priority queue with context.

#### `deinit`

```zig
pub fn deinit(self: *Self, allocator: Allocator) void
```

Free memory used by the queue.

#### `push`

```zig
pub fn push(self: *Self, allocator: Allocator, elem: T) !void
```

Insert a new element, maintaining priority.

#### `pushSlice`

```zig
pub fn pushSlice(self: *Self, allocator: Allocator, items: []const T) !void
```

Add each element in `items` to the queue.

#### `peek`

```zig
pub fn peek(self: *const Self) ?T
```

Look at the highest priority element in the queue. Returns
`null` if empty.

#### `pop`

```zig
pub fn pop(self: *Self) ?T
```

Remove and return the highest priority element from the queue.
Returns `null` if empty.

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

Return the number of elements remaining in the priority
queue.

#### `capacity`

```zig
pub fn capacity(self: *const Self) usize
```

Return the number of elements that can be added to the
queue before more memory is allocated.

#### `fromOwnedSlice`

```zig
pub fn fromOwnedSlice(items: []T, context: Context) Self
```

PriorityQueue takes ownership of the passed in slice. The slice must have been
allocated with `allocator`.
Deinitialize with `deinit`.

#### `ensureTotalCapacity`

```zig
pub fn ensureTotalCapacity(self: *Self, allocator: Allocator, new_capacity: usize) !void
```

Ensure that the queue can fit at least `new_capacity` items.

#### `ensureTotalCapacityPrecise`

```zig
pub fn ensureTotalCapacityPrecise(self: *Self, allocator: Allocator, new_capacity: usize) !void
```

If the current capacity is less than `new_capacity`, this function will
modify the array so that it can hold exactly `new_capacity` items.
Invalidates element pointers if additional memory is needed.

#### `ensureUnusedCapacity`

```zig
pub fn ensureUnusedCapacity(self: *Self, allocator: Allocator, additional_count: usize) !void
```

Ensure that the queue can fit at least `additional_count` **more** item.

#### `shrinkAndFree`

```zig
pub fn shrinkAndFree(self: *Self, allocator: Allocator, new_capacity: usize) void
```

Reduce allocated capacity to `new_capacity`.

#### `clearRetainingCapacity`

```zig
pub fn clearRetainingCapacity(self: *Self) void
```

Remove all elements from the items slice.

#### `clearAndFree`

```zig
pub fn clearAndFree(self: *Self, allocator: Allocator) void
```

Invalidates all element pointers.

#### `update`

```zig
pub fn update(self: *Self, elem: T, new_elem: T) !void
```

Replace an element in the queue with a new element, maintaining priority.
If the element being updated doesn't exist, return `error.ElementNotFound`.

#### `iterator`

```zig
pub fn iterator(self: *Self) Iterator
```

Return an iterator that walks the queue without consuming
it. The iteration order may differ from the priority order.
Invalidated if the heap is modified.

### Constants & Variables

- **`empty`**: A priority queue containing no elements.

