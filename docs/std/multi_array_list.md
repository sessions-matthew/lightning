# `std.multi_array_list`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/multi_array_list.zig`  
> [← Back to Standard Library Index](README.md)

## Types

### `MultiArrayList`

```zig
pub fn MultiArrayList(comptime T: type) type
```

A MultiArrayList stores a list of a struct or tagged union type.
Instead of storing a single list of items, MultiArrayList
stores separate lists for each field of the struct or
lists of tags and bare unions.
This allows for memory savings if the struct or union has padding,
and also improves cache usage if only some fields or just tags
are needed for a computation.  The primary API for accessing fields is
the `slice()` function, which computes the start pointers
for the array of each field.  From the slice you can call
`.items(.<field_name>)` to obtain a slice of field values.
For unions you can call `.items(.tags)` or `.items(.data)`.

### Fields

- `bytes: [*]u8 = undefined`
  This pointer is always aligned to the boundary `sizes.big_align`; this is not specified
  in the type to avoid `MultiArrayList(T)` depending on the alignment of `T` because this
  can lead to dependency loops. See `allocatedBytes` which `@alignCast`s this pointer to
  the correct type.
- `len: usize = 0`
  
- `capacity: usize = 0`
  

### Types

#### `Field`


#### `Slice`

A MultiArrayList.Slice contains cached start pointers for each field in the list.
These pointers are not normally stored to reduce the size of the list in memory.
If you are accessing multiple fields, call slice() first to compute the pointers,
and then get the field arrays from the slice.

### Functions

#### `initCapacity`

```zig
pub fn initCapacity(gpa: Allocator, num: usize) Allocator.Error!Self
```

Initialize with capacity to hold exactly `num` elements.
Deinitialize with `deinit` or `toOwnedSlice`.

#### `deinit`

```zig
pub fn deinit(self: *Self, gpa: Allocator) void
```

Release all allocated memory.

#### `toOwnedSlice`

```zig
pub fn toOwnedSlice(self: *Self) Slice
```

The caller owns the returned memory. Empties this MultiArrayList.

#### `slice`

```zig
pub fn slice(self: Self) Slice
```

Compute pointers to the start of each field of the array.
If you need to access multiple fields, calling this may
be more efficient than calling `items()` multiple times.

#### `items`

```zig
pub fn items(self: Self, comptime field: Field) []FieldType(field)
```

Get the slice of values for a specified field.
If you need multiple fields, consider calling slice()
instead.

#### `set`

```zig
pub fn set(self: *Self, index: usize, elem: T) void
```

Overwrite one array element with new data.

#### `get`

```zig
pub fn get(self: Self, index: usize) T
```

Obtain all the data for one array element.

#### `swap`

```zig
pub fn swap(self: Self, a: usize, b: usize) void
```


#### `append`

```zig
pub fn append(self: *Self, gpa: Allocator, elem: T) Allocator.Error!void
```

Extend the list by 1 element.

Allocates more memory as necessary.

#### `appendAssumeCapacity`

```zig
pub fn appendAssumeCapacity(self: *Self, elem: T) void
```

Extend the list by 1 element.

Asserts that capacity is sufficient to hold an additional item.

#### `appendBounded`

```zig
pub fn appendBounded(self: *Self, elem: T) error{OutOfMemory}!void
```

Extend the list by 1 element.

If capacity is not sufficient to hold an additional
item, returns `error.OutOfMemory`.

#### `addOne`

```zig
pub fn addOne(self: *Self, gpa: Allocator) Allocator.Error!usize
```

Extend the list by 1 element, returning the newly reserved
index with uninitialized data.

Allocates more memory as necessary.

#### `addOneAssumeCapacity`

```zig
pub fn addOneAssumeCapacity(self: *Self) usize
```

Extend the list by 1 element, returning the newly reserved
index with uninitialized data.

Asserts that capacity is sufficient to hold an additional item.

#### `addOneBounded`

```zig
pub fn addOneBounded(self: *Self) error{OutOfMemory}!usize
```

Extend the list by 1 element, returning the newly reserved
index with uninitialized data.

If capacity is not sufficient to hold an additional
item, returns `error.OutOfMemory`.

#### `pop`

```zig
pub fn pop(self: *Self) ?T
```

Remove and return the last element from the list, or return `null` if list is empty.
Invalidates pointers to fields of the removed element.

#### `insert`

```zig
pub fn insert(self: *Self, gpa: Allocator, index: usize, elem: T) !void
```

Inserts an item into the list. Shifts all elements
after and including the specified index back by one and
sets the given index to the specified element.

Allocates more memory as necessary.

#### `insertAssumeCapacity`

```zig
pub fn insertAssumeCapacity(self: *Self, index: usize, elem: T) void
```

Inserts an item into the list. Shifts all elements
after and including the specified index back by one and
sets the given index to the specified element.

Asserts that capacity is sufficient to hold an additional item.

#### `insertBounded`

```zig
pub fn insertBounded(self: *Self, index: usize, elem: T) error{OutOfMemory}!void
```

Inserts an item into the list. Shifts all elements
after and including the specified index back by one and
sets the given index to the specified element.

If capacity is not sufficient to hold an additional
item, returns `error.OutOfMemory`.

#### `swapRemove`

```zig
pub fn swapRemove(self: *Self, index: usize) void
```

Remove the specified item from the list, swapping the last
item in the list into its position. Fast, but does not
retain list ordering.

#### `orderedRemove`

```zig
pub fn orderedRemove(self: *Self, index: usize) void
```

Remove the specified item from the list, shifting items
after it to preserve order.

#### `orderedRemoveMany`

```zig
pub fn orderedRemoveMany(self: *Self, sorted_indexes: []const usize) void
```

Remove the elements indexed by `sorted_indexes`. The indexes to be
removed correspond to the array list before deletion.

Asserts:
* Each index to be removed is in bounds.
* The indexes to be removed are sorted ascending.

Duplicates in `sorted_indexes` are allowed.

This operation is O(N).

Invalidates element pointers beyond the first deleted index.

#### `resize`

```zig
pub fn resize(self: *Self, gpa: Allocator, new_len: usize) Allocator.Error!void
```

Adjust the list's length to `new_len`.
Does not initialize added items, if any.

#### `shrinkAndFree`

```zig
pub fn shrinkAndFree(self: *Self, gpa: Allocator, new_len: usize) void
```

Attempt to reduce allocated capacity to `new_len`.
If `new_len` is greater than zero, this may fail to reduce the capacity,
but the data remains intact and the length is updated to new_len.

#### `clearAndFree`

```zig
pub fn clearAndFree(self: *Self, gpa: Allocator) void
```


#### `shrinkRetainingCapacity`

```zig
pub fn shrinkRetainingCapacity(self: *Self, new_len: usize) void
```

Reduce length to `new_len`.
Invalidates pointers to elements `items[new_len..]`.
Keeps capacity the same.

#### `clearRetainingCapacity`

```zig
pub fn clearRetainingCapacity(self: *Self) void
```

Invalidates all element pointers.

#### `ensureTotalCapacity`

```zig
pub fn ensureTotalCapacity(self: *Self, gpa: Allocator, new_capacity: usize) Allocator.Error!void
```

Modify the array so that it can hold at least `new_capacity` items.
Implements super-linear growth to achieve amortized O(1) append operations.
Invalidates element pointers if additional memory is needed.

#### `growCapacity`

```zig
pub fn growCapacity(minimum: usize) usize
```

Given a lower bound of required memory capacity, returns a larger value
with super-linear growth.

#### `ensureUnusedCapacity`

```zig
pub fn ensureUnusedCapacity(self: *Self, gpa: Allocator, additional_count: usize) Allocator.Error!void
```

Modify the array so that it can hold at least `additional_count` **more** items.
Invalidates pointers if additional memory is needed.

#### `setCapacity`

```zig
pub fn setCapacity(self: *Self, gpa: Allocator, new_capacity: usize) Allocator.Error!void
```

Modify the array so that it can hold exactly `new_capacity` items.
Invalidates pointers if additional memory is needed.
`new_capacity` must be greater or equal to `len`.

#### `clone`

```zig
pub fn clone(self: Self, gpa: Allocator) Allocator.Error!Self
```

Create a copy of this list with a new backing store,
using the specified allocator.

#### `sort`

```zig
pub fn sort(self: Self, ctx: anytype) void
```

This function guarantees a stable sort, i.e the relative order of equal elements is preserved during sorting.
Read more about stable sorting here: https://en.wikipedia.org/wiki/Sorting_algorithm#Stability
If this guarantee does not matter, `sortUnstable` might be a faster alternative.
`ctx` has the following method:
`fn lessThan(ctx: @TypeOf(ctx), a_index: usize, b_index: usize) bool`

#### `sortSpan`

```zig
pub fn sortSpan(self: Self, a: usize, b: usize, ctx: anytype) void
```

Sorts only the subsection of items between indices `a` and `b` (excluding `b`)
This function guarantees a stable sort, i.e the relative order of equal elements is preserved during sorting.
Read more about stable sorting here: https://en.wikipedia.org/wiki/Sorting_algorithm#Stability
If this guarantee does not matter, `sortSpanUnstable` might be a faster alternative.
`ctx` has the following method:
`fn lessThan(ctx: @TypeOf(ctx), a_index: usize, b_index: usize) bool`

#### `sortUnstable`

```zig
pub fn sortUnstable(self: Self, ctx: anytype) void
```

This function does NOT guarantee a stable sort, i.e the relative order of equal elements may change during sorting.
Due to the weaker guarantees of this function, this may be faster than the stable `sort` method.
Read more about stable sorting here: https://en.wikipedia.org/wiki/Sorting_algorithm#Stability
`ctx` has the following method:
`fn lessThan(ctx: @TypeOf(ctx), a_index: usize, b_index: usize) bool`

#### `sortSpanUnstable`

```zig
pub fn sortSpanUnstable(self: Self, a: usize, b: usize, ctx: anytype) void
```

Sorts only the subsection of items between indices `a` and `b` (excluding `b`)
This function does NOT guarantee a stable sort, i.e the relative order of equal elements may change during sorting.
Due to the weaker guarantees of this function, this may be faster than the stable `sortSpan` method.
Read more about stable sorting here: https://en.wikipedia.org/wiki/Sorting_algorithm#Stability
`ctx` has the following method:
`fn lessThan(ctx: @TypeOf(ctx), a_index: usize, b_index: usize) bool`

#### `capacityInBytes`

```zig
pub fn capacityInBytes(capacity: usize) usize
```


### Constants & Variables

- **`empty`**: 

