# `std.array_list`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/array_list.zig`  
> [← Back to Standard Library Index](README.md)

## Types

### `Managed`

```zig
pub fn Managed(comptime T: type) type
```

Deprecated.

### `AlignedManaged`

```zig
pub fn AlignedManaged(comptime T: type, comptime alignment: ?mem.Alignment) type
```

Deprecated.

### Fields

- `items: Slice`
  Contents of the list. This field is intended to be accessed
  directly.
  
  Pointers to elements in this slice are invalidated by various
  functions of this ArrayList in accordance with the respective
  documentation.
   An invalidated pointer may point either to valid or freed memory.
- `capacity: usize`
  How many T values this list can hold without allocating
  additional memory.
- `allocator: Allocator`
  
- `pointer_stability: debug.SafetyLock`
  Used to detect memory safety violations.

### Types

#### `Slice`


#### `SentinelSlice`

```zig
pub fn SentinelSlice(comptime s: T) type
```


### Functions

#### `init`

```zig
pub fn init(gpa: Allocator) Self
```

Deinitialize with `deinit` or use `toOwnedSlice`.

#### `initCapacity`

```zig
pub fn initCapacity(gpa: Allocator, num: usize) Allocator.Error!Self
```

Initialize with capacity to hold `num` elements.
The resulting capacity will equal `num` exactly.
Deinitialize with `deinit` or use `toOwnedSlice`.

#### `deinit`

```zig
pub fn deinit(self: Self) void
```

Release all allocated memory.

#### `lockPointers`

```zig
pub fn lockPointers(self: *Self) void
```

Puts the array list into a state where any method call that would
cause an existing value pointer to become invalidated will
instead trigger an assertion.

`lockPointers` may be called multiple times. This allows multiple
independent users of the list to keep it locked simultaneously.

`unlockPointers` restores the list to its previous state when
called the same number of times as `lockPointers`.

#### `unlockPointers`

```zig
pub fn unlockPointers(self: *Self) void
```

Undoes one call to `lockPointers`.

#### `fromOwnedSlice`

```zig
pub fn fromOwnedSlice(gpa: Allocator, slice: Slice) Self
```

ArrayList takes ownership of the passed in slice. The slice must have been
allocated with `gpa`.
Deinitialize with `deinit` or use `toOwnedSlice`.

#### `fromOwnedSliceSentinel`

```zig
pub fn fromOwnedSliceSentinel(gpa: Allocator, comptime sentinel: T, slice: [:sentinel]T) Self
```

ArrayList takes ownership of the passed in slice. The slice must have been
allocated with `gpa`.
Deinitialize with `deinit` or use `toOwnedSlice`.

#### `moveToUnmanaged`

```zig
pub fn moveToUnmanaged(self: *Self) Aligned(T, alignment)
```

Initializes an ArrayList with the `items` and `capacity` fields
of this ArrayList. Empties this ArrayList.

#### `toOwnedSlice`

```zig
pub fn toOwnedSlice(self: *Self) Allocator.Error!Slice
```

The caller owns the returned memory. Empties this ArrayList.
Its capacity is cleared, making `deinit` safe but unnecessary to call.
May invalidate element pointers if remapping memory cannot be done in place.

#### `toOwnedSliceSentinel`

```zig
pub fn toOwnedSliceSentinel(self: *Self, comptime sentinel: T) Allocator.Error!SentinelSlice(sentinel)
```

The caller owns the returned memory. Empties this ArrayList.
May invalidate element pointers if remapping memory cannot be done in place.

#### `clone`

```zig
pub fn clone(self: Self) Allocator.Error!Self
```

Creates a copy of this ArrayList, using the same allocator.

#### `insert`

```zig
pub fn insert(self: *Self, index: usize, item: T) Allocator.Error!void
```

Insert `item` at index `index`. Moves `list[index .. list.len]` to higher indices to make room.
If `index` is equal to the length of the list this operation is equivalent to append.
This operation is O(N).
Invalidates element pointers if additional memory is needed.
Invalidates pre-existing pointers to elements at and after `index`.
Asserts that the index is in bounds or equal to the length.

#### `insertAssumeCapacity`

```zig
pub fn insertAssumeCapacity(self: *Self, index: usize, item: T) void
```

Insert `item` at index `index`. Moves `list[index .. list.len]` to higher indices to make room.
If `index` is equal to the length of the list this operation is
equivalent to appendAssumeCapacity.
This operation is O(N).
Invalidates pre-existing pointers to elements at and after `index`.
Asserts that there is enough capacity for the new item.
Asserts that the index is in bounds or equal to the length.

#### `addManyAt`

```zig
pub fn addManyAt(self: *Self, index: usize, count: usize) Allocator.Error![]T
```

Add `count` new elements at position `index`, which have
`undefined` values. Returns a slice pointing to the newly allocated
elements, which becomes invalid after various `ArrayList`
operations.
Invalidates pre-existing pointers to elements at and after `index`.
Invalidates all pre-existing element pointers if capacity must be
increased to accommodate the new elements.
Asserts that the index is in bounds or equal to the length.

#### `addManyAtAssumeCapacity`

```zig
pub fn addManyAtAssumeCapacity(self: *Self, index: usize, count: usize) []T
```

Add `count` new elements at position `index`, which have
`undefined` values. Returns a slice pointing to the newly allocated
elements, which becomes invalid after various `ArrayList`
operations.
Invalidates pre-existing pointers to elements at and after `index`.
Asserts that there is enough capacity for the new elements.
Asserts that the index is in bounds or equal to the length.

#### `insertSlice`

```zig
pub fn insertSlice(self: *Self, index: usize, items: []const T, ) Allocator.Error!void
```

Insert slice `items` at index `index` by moving `list[index .. list.len]` to make room.
This operation is O(N).
Invalidates pre-existing pointers to elements at and after `index`.
Invalidates all pre-existing element pointers if capacity must be
increased to accommodate the new elements.
Asserts that the index is in bounds or equal to the length.

#### `replaceRange`

```zig
pub fn replaceRange(self: *Self, start: usize, len: usize, new_items: []const T) Allocator.Error!void
```

Grows or shrinks the list as necessary.
Invalidates element pointers if additional capacity is allocated,
Invalidates pointers to elements at and above index `start + len`
when `len` and `new_items.len` are unequal.
Asserts that the range is in bounds.

#### `replaceRangeAssumeCapacity`

```zig
pub fn replaceRangeAssumeCapacity(self: *Self, start: usize, len: usize, new_items: []const T) void
```

Grows or shrinks the list as necessary.
Invalidates pointers to elements at and above index `start + len`
when `len` and `new_items.len` are unequal.
Asserts the capacity is enough for additional items.

#### `append`

```zig
pub fn append(self: *Self, item: T) Allocator.Error!void
```

Extends the list by 1 element. Allocates more memory as necessary.
Invalidates element pointers if additional memory is needed.

#### `appendAssumeCapacity`

```zig
pub fn appendAssumeCapacity(self: *Self, item: T) void
```

Extends the list by 1 element.
Never invalidates element pointers.
Asserts that the list can hold one additional item.

#### `orderedRemove`

```zig
pub fn orderedRemove(self: *Self, i: usize) T
```

Remove the element at index `i`, shift elements after index
`i` forward, and return the removed element.
Invalidates element pointers to end of list.
This operation is O(N).
This preserves item order. Use `swapRemove` if order preservation is not important.
Asserts that the index is in bounds.
Asserts that the list is not empty.

#### `swapRemove`

```zig
pub fn swapRemove(self: *Self, i: usize) T
```

Removes the element at the specified index and returns it.
The empty slot is filled from the end of the list.
Invalidates pointers to the end of the list.
This operation is O(1).
This may not preserve item order. Use `orderedRemove` if you need to preserve order.
Asserts that the index is in bounds.

#### `appendSlice`

```zig
pub fn appendSlice(self: *Self, items: []const T) Allocator.Error!void
```

Append the slice of items to the list. Allocates more
memory as necessary.
Invalidates element pointers if additional memory is needed.

#### `appendSliceAssumeCapacity`

```zig
pub fn appendSliceAssumeCapacity(self: *Self, items: []const T) void
```

Append the slice of items to the list.
Never invalidates element pointers.
Asserts that the list can hold the additional items.

#### `appendUnalignedSlice`

```zig
pub fn appendUnalignedSlice(self: *Self, items: []align(1) const T) Allocator.Error!void
```

Append an unaligned slice of items to the list. Allocates more
memory as necessary. Only call this function if calling
`appendSlice` instead would be a compile error.
Invalidates element pointers if additional memory is needed.

#### `appendUnalignedSliceAssumeCapacity`

```zig
pub fn appendUnalignedSliceAssumeCapacity(self: *Self, items: []align(1) const T) void
```

Append the slice of items to the list.
Never invalidates element pointers.
This function is only needed when calling
`appendSliceAssumeCapacity` instead would be a compile error due to the
alignment of the `items` parameter.
Asserts that the list can hold the additional items.

#### `print`

```zig
pub fn print(self: *Self, comptime fmt: []const u8, args: anytype) error{OutOfMemory}!void
```

Prints a formatted string into this list.
Invalidates element pointers if additional memory is needed.

#### `appendNTimes`

```zig
pub inline fn appendNTimes(self: *Self, value: T, n: usize) Allocator.Error!void
```

Append a value to the list `n` times.
Allocates more memory as necessary.
Invalidates element pointers if additional memory is needed.
The function is inline so that a comptime-known `value` parameter will
have a more optimal memset codegen in case it has a repeated byte pattern.

#### `appendNTimesAssumeCapacity`

```zig
pub inline fn appendNTimesAssumeCapacity(self: *Self, value: T, n: usize) void
```

Append a value to the list `n` times.
Never invalidates element pointers.
The function is inline so that a comptime-known `value` parameter will
have a more optimal memset codegen in case it has a repeated byte pattern.
Asserts that the list can hold the additional items.

#### `resize`

```zig
pub fn resize(self: *Self, new_len: usize) Allocator.Error!void
```

Adjust the list length to `new_len`.
Additional elements contain the value `undefined`.
Invalidates element pointers if additional memory is needed.

#### `shrinkAndFree`

```zig
pub fn shrinkAndFree(self: *Self, new_len: usize) void
```

Reduce allocated capacity to `new_len`.
May invalidate element pointers.
Asserts that the new length is less than or equal to the previous length.

#### `shrinkRetainingCapacity`

```zig
pub fn shrinkRetainingCapacity(self: *Self, new_len: usize) void
```

Reduce length to `new_len`.
Invalidates element pointers for the elements `items[new_len..]`.
Asserts that the new length is less than or equal to the previous length.

#### `clearRetainingCapacity`

```zig
pub fn clearRetainingCapacity(self: *Self) void
```

Reduce length to 0.
Invalidates all element pointers.

#### `clearAndFree`

```zig
pub fn clearAndFree(self: *Self) void
```

Invalidates all element pointers.

#### `ensureTotalCapacity`

```zig
pub fn ensureTotalCapacity(self: *Self, new_capacity: usize) Allocator.Error!void
```

If the current capacity is less than `new_capacity`, this function will
modify the array so that it can hold at least `new_capacity` items.
Invalidates element pointers if additional memory is needed.

#### `ensureTotalCapacityPrecise`

```zig
pub fn ensureTotalCapacityPrecise(self: *Self, new_capacity: usize) Allocator.Error!void
```

If the current capacity is less than `new_capacity`, this function will
modify the array so that it can hold exactly `new_capacity` items.
Invalidates element pointers if additional memory is needed.

#### `ensureUnusedCapacity`

```zig
pub fn ensureUnusedCapacity(self: *Self, additional_count: usize) Allocator.Error!void
```

Modify the array so that it can hold at least `additional_count` **more** items.
Invalidates element pointers if additional memory is needed.

#### `expandToCapacity`

```zig
pub fn expandToCapacity(self: *Self) void
```

Increases the array's length to match the full capacity that is already allocated.
The new elements have `undefined` values.
Never invalidates element pointers.

#### `addOne`

```zig
pub fn addOne(self: *Self) Allocator.Error!*T
```

Increase length by 1, returning pointer to the new item.
Invalidates element pointers if additional memory is needed.
The returned pointer may be invalidated by further operations to this list.

#### `addOneAssumeCapacity`

```zig
pub fn addOneAssumeCapacity(self: *Self) *T
```

Increase length by 1, returning pointer to the new item.
The returned pointer may be invalidated by further operations to this list.
Never invalidates element pointers.
Asserts that the list can hold one additional item.

#### `addManyAsArray`

```zig
pub fn addManyAsArray(self: *Self, comptime n: usize) Allocator.Error!*[n]T
```

Resize the array, adding `n` new elements, which have `undefined` values.
The return value is an array pointing to the newly allocated elements.
The returned pointer may be invalidated by further operations to this list.
Resizes list if `self.capacity` is not large enough.
Invalidates element pointers if additional memory is needed.

#### `addManyAsArrayAssumeCapacity`

```zig
pub fn addManyAsArrayAssumeCapacity(self: *Self, comptime n: usize) *[n]T
```

Resize the array, adding `n` new elements, which have `undefined` values.
The return value is an array pointing to the newly allocated elements.
Never invalidates element pointers.
The returned pointer may be invalidated by further operations to this list.
Asserts that the list can hold the additional items.

#### `addManyAsSlice`

```zig
pub fn addManyAsSlice(self: *Self, n: usize) Allocator.Error![]T
```

Resize the array, adding `n` new elements, which have `undefined` values.
The return value is a slice pointing to the newly allocated elements.
The returned pointer may be invalidated by further operations to this list.
Resizes list if `self.capacity` is not large enough.
Invalidates element pointers if additional memory is needed.

#### `addManyAsSliceAssumeCapacity`

```zig
pub fn addManyAsSliceAssumeCapacity(self: *Self, n: usize) []T
```

Resize the array, adding `n` new elements, which have `undefined` values.
The return value is a slice pointing to the newly allocated elements.
Never invalidates element pointers.
The returned pointer may be invalidated by further operations to this list.
Asserts that the list can hold the additional items.

#### `pop`

```zig
pub fn pop(self: *Self) ?T
```

Remove and return the last element from the list, or return `null` if list is empty.
Invalidates element pointers to the removed element.

#### `allocatedSlice`

```zig
pub fn allocatedSlice(self: Self) Slice
```

Returns a slice of all the items plus the extra capacity, whose memory
contents are `undefined`.
The returned pointer may be invalidated by further operations to this list.

#### `unusedCapacitySlice`

```zig
pub fn unusedCapacitySlice(self: Self) []T
```

Returns a slice of only the extra capacity after items.
This can be useful for writing directly into an ArrayList.
Note that such an operation must be followed up with a direct
modification of `self.items.len`.
The returned pointer may be invalidated by further operations to this list.

#### `getLast`

```zig
pub fn getLast(self: Self) T
```

Deprecated

#### `last`

```zig
pub fn last(self: Self) ?T
```

Returns the last element from the list, or `null` if the list is
empty.
Never invalidates element pointers.

#### `lastPtr`

```zig
pub fn lastPtr(self: Self) ?*T
```

Returns a pointer to the last element from the list, or `null` if
the list is empty.
The returned pointer may be invalidated by further operations to this list.

### Constants & Variables

- **`getLastOrNull`**: Deprecated in favor of `last`

### `Aligned`

```zig
pub fn Aligned(comptime T: type, comptime alignment: ?mem.Alignment) type
```

A contiguous, growable list of arbitrarily aligned items in memory.
This is a wrapper around an array of T values aligned to `alignment`-byte
addresses. If the specified alignment is `null`, then `@alignOf(T)` is used.

Functions that potentially allocate memory accept an `Allocator` parameter.
Initialize directly or with `initCapacity`, and deinitialize with `deinit`
or use `toOwnedSlice`.

### Fields

- `items: Slice`
  Contents of the list. This field is intended to be accessed
  directly.
  
  Pointers to elements in this slice are invalidated by various
  functions of this ArrayList in accordance with the respective
  documentation.
   An invalidated pointer may point either to valid or freed memory.
- `capacity: usize`
  How many T values this list can hold without allocating
  additional memory.
- `pointer_stability: debug.SafetyLock`
  Used to detect memory safety violations.

### Types

#### `Slice`


#### `SentinelSlice`

```zig
pub fn SentinelSlice(comptime s: T) type
```


### Functions

#### `initCapacity`

```zig
pub fn initCapacity(gpa: Allocator, num: usize) Allocator.Error!Self
```

Initialize with capacity to hold exactly `num` elements.
Deinitialize with `deinit` or `toOwnedSlice`.

#### `initBuffer`

```zig
pub fn initBuffer(buffer: Slice) Self
```

Initialize with externally-managed memory. The buffer determines the
capacity, and the length is set to zero.

When initialized this way, all functions that accept an Allocator
argument cause illegal behavior.

#### `deinit`

```zig
pub fn deinit(self: *Self, gpa: Allocator) void
```

Release all allocated memory.

#### `lockPointers`

```zig
pub fn lockPointers(self: *Self) void
```

Puts the unmanaged array list into a state where any method call that would
cause an existing value pointer to become invalidated will
instead trigger an assertion.

`lockPointers` may be called multiple times. This allows multiple
independent users of the list to keep it locked simultaneously.

`unlockPointers` restores the list to its previous state when
called the same number of times as `lockPointers`.

#### `unlockPointers`

```zig
pub fn unlockPointers(self: *Self) void
```

Undoes one call to `lockPointers`.

#### `toManaged`

```zig
pub fn toManaged(self: *Self, gpa: Allocator) AlignedManaged(T, alignment)
```

Convert this list into an analogous memory-managed one.
The returned list has ownership of the underlying memory.

#### `fromOwnedSlice`

```zig
pub fn fromOwnedSlice(slice: Slice) Self
```

ArrayList takes ownership of the passed in slice.
Deinitialize with `deinit` or use `toOwnedSlice`.

#### `fromOwnedSliceSentinel`

```zig
pub fn fromOwnedSliceSentinel(comptime sentinel: T, slice: [:sentinel]T) Self
```

ArrayList takes ownership of the passed in slice.
Deinitialize with `deinit` or use `toOwnedSlice`.

#### `toOwnedSlice`

```zig
pub fn toOwnedSlice(self: *Self, gpa: Allocator) Allocator.Error!Slice
```

The caller owns the returned memory. Empties this ArrayList.
Its capacity is cleared, making deinit() safe but unnecessary to call.
May invalidate element pointers.

#### `toOwnedSliceSentinel`

```zig
pub fn toOwnedSliceSentinel(self: *Self, gpa: Allocator, comptime sentinel: T) Allocator.Error!SentinelSlice(sentinel)
```

The caller owns the returned memory. ArrayList becomes empty.
May invalidate element pointers.

#### `toOwnedSliceAssert`

```zig
pub fn toOwnedSliceAssert(self: *Self) Slice
```

The caller owns the returned memory. Empties this ArrayList.
Its capacity is cleared, making deinit() safe but unnecessary to call.

Asserts what the capacity is equal to the length.
Never invalidates element pointers.

See also:
* `shrinkToLen`

#### `toOwnedSliceSentinelAssert`

```zig
pub fn toOwnedSliceSentinelAssert(self: *Self, comptime sentinel: T) SentinelSlice(sentinel)
```

The caller owns the returned memory. ArrayList becomes empty.
Asserts what the capacity is equal to the length + 1.
Never invalidates element pointers.

#### `clone`

```zig
pub fn clone(self: Self, gpa: Allocator) Allocator.Error!Self
```

Creates a copy of this ArrayList.

#### `insert`

```zig
pub fn insert(self: *Self, gpa: Allocator, index: usize, item: T) Allocator.Error!void
```

Insert `item` at index `index`. Moves `list[index .. list.len]` to higher indices to make room.
If `index` is equal to the length of the list this operation is equivalent to append.
This operation is O(N).
Invalidates element pointers if additional memory is needed.
Invalidates pre-existing pointers to elements at and after `index`.
Asserts that the index is in bounds or equal to the length.

#### `insertAssumeCapacity`

```zig
pub fn insertAssumeCapacity(self: *Self, index: usize, item: T) void
```

Insert `item` at index `index`. Moves `list[index .. list.len]` to higher indices to make room.
If `index` is equal to the length of the list this operation is
equivalent to appendAssumeCapacity.
This operation is O(N).
Invalidates pre-existing pointers to elements at and after `index`.
Asserts that the list has capacity for one additional item.
Asserts that the index is in bounds or equal to the length.

#### `insertBounded`

```zig
pub fn insertBounded(self: *Self, i: usize, item: T) error{OutOfMemory}!void
```

Insert `item` at index `index`. Moves `list[index .. list.len]` to higher indices to make room.
If `index` is equal to the length of the list this operation is
equivalent to appendAssumeCapacity.
This operation is O(N).
Invalidates pre-existing pointers to elements at and after `index`.
Asserts that the index is in bounds or equal to the length.
If the list lacks unused capacity for the additional item, returns
`error.OutOfMemory`.

#### `addManyAt`

```zig
pub fn addManyAt(self: *Self, gpa: Allocator, index: usize, count: usize, ) Allocator.Error![]T
```

Add `count` new elements at position `index`, which have
`undefined` values. Returns a slice pointing to the newly allocated
elements, which becomes invalid after various `ArrayList`
operations.
Invalidates pre-existing pointers to elements at and after `index`.
Invalidates all pre-existing element pointers if capacity must be
increased to accommodate the new elements.
Asserts that the index is in bounds or equal to the length.

#### `addManyAtAssumeCapacity`

```zig
pub fn addManyAtAssumeCapacity(self: *Self, index: usize, count: usize) []T
```

Add `count` new elements at position `index`, which have
`undefined` values. Returns a slice pointing to the newly allocated
elements, which becomes invalid after various `ArrayList`
operations.
Invalidates pre-existing pointers to elements at and after `index`.
Asserts that the list has capacity for the additional items.
Asserts that the index is in bounds or equal to the length.

#### `addManyAtBounded`

```zig
pub fn addManyAtBounded(self: *Self, index: usize, count: usize) error{OutOfMemory}![]T
```

Add `count` new elements at position `index`, which have
`undefined` values, returning a slice pointing to the newly
allocated elements, which becomes invalid after various `ArrayList`
operations.
Invalidates pre-existing pointers to elements at and after `index`.
If the list lacks unused capacity for the additional items, returns
`error.OutOfMemory`.
Asserts that the index is in bounds or equal to the length.

#### `insertSlice`

```zig
pub fn insertSlice(self: *Self, gpa: Allocator, index: usize, items: []const T, ) Allocator.Error!void
```

Insert slice `items` at index `index` by moving `list[index .. list.len]` to make room.
This operation is O(N).
Invalidates pre-existing pointers to elements at and after `index`.
Invalidates all pre-existing element pointers if capacity must be
increased to accommodate the new elements.
Asserts that the index is in bounds or equal to the length.

#### `insertSliceAssumeCapacity`

```zig
pub fn insertSliceAssumeCapacity(self: *Self, index: usize, items: []const T, ) void
```

Insert slice `items` at index `index` by moving `list[index .. list.len]` to make room.
This operation is O(N).
Invalidates pre-existing pointers to elements at and after `index`.
Asserts that the list has capacity for the additional items.
Asserts that the index is in bounds or equal to the length.

#### `insertSliceBounded`

```zig
pub fn insertSliceBounded(self: *Self, index: usize, items: []const T, ) error{OutOfMemory}!void
```

Insert slice `items` at index `index` by moving `list[index .. list.len]` to make room.
This operation is O(N).
Invalidates pre-existing pointers to elements at and after `index`.
If the list lacks unused capacity for the additional items, returns
`error.OutOfMemory`.
Asserts that the index is in bounds or equal to the length.

#### `replaceRange`

```zig
pub fn replaceRange(self: *Self, gpa: Allocator, start: usize, len: usize, new_items: []const T, ) Allocator.Error!void
```

Grows or shrinks the list as necessary.
Invalidates element pointers if additional capacity is allocated,
Invalidates pointers to elements at and above index `start + len`
when `len` and `new_items.len` are unequal.
Asserts that the range is in bounds.

#### `replaceRangeAssumeCapacity`

```zig
pub fn replaceRangeAssumeCapacity(self: *Self, start: usize, len: usize, new_items: []const T, ) void
```

Grows or shrinks the list as necessary.
Invalidates pointers to elements at and above index `start + len`
when `len` and `new_items.len` are unequal.
Asserts the capacity is enough for additional items.

#### `replaceRangeBounded`

```zig
pub fn replaceRangeBounded(self: *Self, start: usize, len: usize, new_items: []const T, ) error{OutOfMemory}!void
```

Invalidates pointers to elements at and above index `start + len`
when `len` and `new_items.len` are unequal.
If the unused capacity is insufficient for additional items,
returns `error.OutOfMemory`.

#### `append`

```zig
pub fn append(self: *Self, gpa: Allocator, item: T) Allocator.Error!void
```

Extend the list by 1 element. Allocates more memory as necessary.
Invalidates element pointers if additional memory is needed.

#### `appendAssumeCapacity`

```zig
pub fn appendAssumeCapacity(self: *Self, item: T) void
```

Extend the list by 1 element.

Never invalidates element pointers.

Asserts that the list can hold one additional item.

#### `appendBounded`

```zig
pub fn appendBounded(self: *Self, item: T) error{OutOfMemory}!void
```

Extend the list by 1 element.

Never invalidates element pointers.

If the list lacks unused capacity for the additional item, returns
`error.OutOfMemory`.

#### `orderedRemove`

```zig
pub fn orderedRemove(self: *Self, i: usize) T
```

Remove the element at index `i` from the list and return its value.
Invalidates pointers to the last element.
This operation is O(N).
Asserts that the index is in bounds.

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

#### `swapRemove`

```zig
pub fn swapRemove(self: *Self, i: usize) T
```

Removes the element at the specified index and returns it.
The empty slot is filled from the end of the list.
Invalidates pointers to last element.
This operation is O(1).
Asserts that the index is in bounds.

#### `appendSlice`

```zig
pub fn appendSlice(self: *Self, gpa: Allocator, items: []const T) Allocator.Error!void
```

Append the slice of items to the list. Allocates more
memory as necessary.
Invalidates element pointers if additional memory is needed.

#### `appendSliceAssumeCapacity`

```zig
pub fn appendSliceAssumeCapacity(self: *Self, items: []const T) void
```

Append the slice of items to the list.
Never invalidates element pointers.
Asserts that the list can hold the additional items.

#### `appendSliceBounded`

```zig
pub fn appendSliceBounded(self: *Self, items: []const T) error{OutOfMemory}!void
```

Append the slice of items to the list.
Never invalidates element pointers.
If the list lacks unused capacity for the additional items, returns `error.OutOfMemory`.

#### `appendUnalignedSlice`

```zig
pub fn appendUnalignedSlice(self: *Self, gpa: Allocator, items: []align(1) const T) Allocator.Error!void
```

Append the slice of items to the list. Allocates more
memory as necessary. Only call this function if a call to `appendSlice` instead would
be a compile error.
Invalidates element pointers if additional memory is needed.

#### `appendUnalignedSliceAssumeCapacity`

```zig
pub fn appendUnalignedSliceAssumeCapacity(self: *Self, items: []align(1) const T) void
```

Append an unaligned slice of items to the list.

Intended to be used only when `appendSliceAssumeCapacity` would be
a compile error.
Never invalidates element pointers.
Asserts that the list can hold the additional items.

#### `appendUnalignedSliceBounded`

```zig
pub fn appendUnalignedSliceBounded(self: *Self, items: []align(1) const T) error{OutOfMemory}!void
```

Append an unaligned slice of items to the list.

Intended to be used only when `appendSliceAssumeCapacity` would be
a compile error.
Never invalidates element pointers.
If the list lacks unused capacity for the additional items, returns
`error.OutOfMemory`.

#### `print`

```zig
pub fn print(self: *Self, gpa: Allocator, comptime fmt: []const u8, args: anytype) error{OutOfMemory}!void
```

Prints a formatted string into this list.
Invalidates element pointers if additional memory is needed.

#### `printAssumeCapacity`

```zig
pub fn printAssumeCapacity(self: *Self, comptime fmt: []const u8, args: anytype) void
```

Prints a formatted string into this list.
Asserts that there is enough capacity for the write.
Never invalidates element pointers.

#### `printBounded`

```zig
pub fn printBounded(self: *Self, comptime fmt: []const u8, args: anytype) error{OutOfMemory}!void
```

Prints a formatted string into this list.
Returns error.OutOfMemory if additional capacity is needed for the write.
Never invalidates element pointers.

#### `appendNTimes`

```zig
pub inline fn appendNTimes(self: *Self, gpa: Allocator, value: T, n: usize) Allocator.Error!void
```

Append a value to the list `n` times.
Allocates more memory as necessary.
Invalidates element pointers if additional memory is needed.
The function is inline so that a comptime-known `value` parameter will
have a more optimal memset codegen in case it has a repeated byte pattern.

#### `appendNTimesAssumeCapacity`

```zig
pub inline fn appendNTimesAssumeCapacity(self: *Self, value: T, n: usize) void
```

Append a value to the list `n` times.

Never invalidates element pointers.

The function is inline so that a comptime-known `value` parameter will
have better memset codegen in case it has a repeated byte pattern.

Asserts that the list can hold the additional items.

#### `appendNTimesBounded`

```zig
pub inline fn appendNTimesBounded(self: *Self, value: T, n: usize) error{OutOfMemory}!void
```

Append a value to the list `n` times.

Never invalidates element pointers.

The function is inline so that a comptime-known `value` parameter will
have better memset codegen in case it has a repeated byte pattern.

If the list lacks unused capacity for the additional items, returns
`error.OutOfMemory`.

#### `resize`

```zig
pub fn resize(self: *Self, gpa: Allocator, new_len: usize) Allocator.Error!void
```

Adjust the list length to `new_len`.
Additional elements contain the value `undefined`.
Invalidates element pointers if additional memory is needed.

#### `shrinkAndFree`

```zig
pub fn shrinkAndFree(self: *Self, gpa: Allocator, new_len: usize) void
```

Reduce allocated capacity to `new_len`.
May invalidate element pointers.
Asserts that the new length is less than or equal to the previous length.

#### `shrinkAndFreePrecise`

```zig
pub fn shrinkAndFreePrecise(self: *Self, gpa: Allocator, new_len: usize) Allocator.Error!void
```

Reduce allocated capacity to `new_len`.
May invalidate element pointers.
Asserts that the new length is less than or equal to the previous length.
If succeds capacity is guaranteed to be equal to the length.

#### `shrinkToLen`

```zig
pub fn shrinkToLen(self: *Self, gpa: Allocator) Allocator.Error!void
```

Shrinks capacity to match length.
May invalidate element pointers.
If succeds it is safe to call `toOwnedSliceAssert`.

#### `shrinkToLenSentinel`

```zig
pub fn shrinkToLenSentinel(self: *Self, gpa: Allocator) Allocator.Error!void
```

Shrinks or expands capacity to match length + 1.
May invalidate element pointers.
If succeds it is safe to call `toOwnedSliceSentinelAssert`.

#### `shrinkRetainingCapacity`

```zig
pub fn shrinkRetainingCapacity(self: *Self, new_len: usize) void
```

Reduce length to `new_len`.
Invalidates pointers to elements `items[new_len..]`.
Keeps capacity the same.
Asserts that the new length is less than or equal to the previous length.

#### `clearRetainingCapacity`

```zig
pub fn clearRetainingCapacity(self: *Self) void
```

Reduce length to 0.
Invalidates all element pointers.

#### `clearAndFree`

```zig
pub fn clearAndFree(self: *Self, gpa: Allocator) void
```

Invalidates all element pointers.

#### `ensureTotalCapacity`

```zig
pub fn ensureTotalCapacity(self: *Self, gpa: Allocator, new_capacity: usize) Allocator.Error!void
```

Modify the array so that it can hold at least `new_capacity` items.
Implements super-linear growth to achieve amortized O(1) append operations.
Invalidates element pointers if additional memory is needed.

#### `ensureTotalCapacityPrecise`

```zig
pub fn ensureTotalCapacityPrecise(self: *Self, gpa: Allocator, new_capacity: usize) Allocator.Error!void
```

If the current capacity is less than `new_capacity`, this function will
modify the array so that it can hold exactly `new_capacity` items.
Invalidates element pointers if additional memory is needed.

#### `ensureUnusedCapacity`

```zig
pub fn ensureUnusedCapacity(self: *Self, gpa: Allocator, additional_count: usize, ) Allocator.Error!void
```

Modify the array so that it can hold at least `additional_count` **more** items.
Invalidates element pointers if additional memory is needed.

#### `expandToCapacity`

```zig
pub fn expandToCapacity(self: *Self) void
```

Increases the array's length to match the full capacity that is already allocated.
The new elements have `undefined` values.
Never invalidates element pointers.

#### `addOne`

```zig
pub fn addOne(self: *Self, gpa: Allocator) Allocator.Error!*T
```

Increase length by 1, returning pointer to the new item.
Invalidates element pointers if additional memory is needed.
The returned pointer may be invalidated by further operations to this list.

#### `addOneAssumeCapacity`

```zig
pub fn addOneAssumeCapacity(self: *Self) *T
```

Increase length by 1, returning pointer to the new item.
Never invalidates element pointers.
The returned pointer may be invalidated by further operations to this list.
Asserts that the list can hold one additional item.

#### `addOneBounded`

```zig
pub fn addOneBounded(self: *Self) error{OutOfMemory}!*T
```

Increase length by 1, returning pointer to the new item.
Never invalidates element pointers.
The returned pointer may be invalidated by further operations to this list.
If the list lacks unused capacity for the additional item, returns `error.OutOfMemory`.

#### `addManyAsArray`

```zig
pub fn addManyAsArray(self: *Self, gpa: Allocator, comptime n: usize) Allocator.Error!*[n]T
```

Resize the array, adding `n` new elements, which have `undefined` values.
Invalidates element pointers if additional memory is required.
The return value is an array pointing to the newly allocated elements.
The returned pointer may be invalidated by further operations to this list.

#### `addManyAsArrayAssumeCapacity`

```zig
pub fn addManyAsArrayAssumeCapacity(self: *Self, comptime n: usize) *[n]T
```

Resize the array, adding `n` new elements, which have `undefined` values.
The return value is an array pointing to the newly allocated elements.
Never invalidates element pointers.
The returned pointer may be invalidated by further operations to this list.
Asserts that the list can hold the additional items.

#### `addManyAsArrayBounded`

```zig
pub fn addManyAsArrayBounded(self: *Self, comptime n: usize) error{OutOfMemory}!*[n]T
```

Resize the array, adding `n` new elements, which have `undefined` values.
The return value is an array pointing to the newly allocated elements.
Never invalidates element pointers.
The returned pointer may be invalidated by further operations to this list.
If the list lacks unused capacity for the additional items, returns
`error.OutOfMemory`.

#### `addManyAsSlice`

```zig
pub fn addManyAsSlice(self: *Self, gpa: Allocator, n: usize) Allocator.Error![]T
```

Resize the array, adding `n` new elements, which have `undefined` values.
The return value is a slice pointing to the newly allocated elements.
The returned pointer may be invalidated by further operations to this list.
Resizes list if `self.capacity` is not large enough.

#### `addManyAsSliceAssumeCapacity`

```zig
pub fn addManyAsSliceAssumeCapacity(self: *Self, n: usize) []T
```

Resizes the array, adding `n` new elements, which have `undefined`
values, returning a slice pointing to the newly allocated elements.
Never invalidates element pointers.
The returned pointer may be invalidated by further operations to this list.
Asserts that the list can hold the additional items.

#### `addManyAsSliceBounded`

```zig
pub fn addManyAsSliceBounded(self: *Self, n: usize) error{OutOfMemory}![]T
```

Resizes the array, adding `n` new elements, which have `undefined`
values, returning a slice pointing to the newly allocated elements.
Never invalidates element pointers.
The returned pointer may be invalidated by further operations to this list.
If the list lacks unused capacity for the additional items, returns
`error.OutOfMemory`.

#### `pop`

```zig
pub fn pop(self: *Self) ?T
```

Remove and return the last element from the list.
If the list is empty, returns `null`.
Invalidates pointers to last element.

#### `allocatedSlice`

```zig
pub fn allocatedSlice(self: Self) Slice
```

Returns a slice of all the items plus the extra capacity, whose memory
contents are `undefined`.
The returned pointer may be invalidated by further operations to this list.

#### `unusedCapacitySlice`

```zig
pub fn unusedCapacitySlice(self: Self) []T
```

Returns a slice of only the extra capacity after items.
This can be useful for writing directly into an ArrayList.
Note that such an operation must be followed up with a direct
modification of `self.items.len`.
The returned pointer may be invalidated by further operations to this list.

#### `getLast`

```zig
pub fn getLast(self: Self) T
```

Deprecated

#### `last`

```zig
pub fn last(self: Self) ?T
```

Returns the last element from the list, or `null` if the list is
empty.

#### `lastPtr`

```zig
pub fn lastPtr(self: Self) ?*T
```

Returns a pointer to the last element from the list, or `null` if
the list is empty.
The returned pointer may be invalidated by further operations to this list.

#### `growCapacity`

```zig
pub fn growCapacity(minimum: usize) usize
```

Called when memory growth is necessary. Returns a capacity larger than
minimum that grows super-linearly.

### Constants & Variables

- **`empty`**: An ArrayList containing no elements.
- **`getLastOrNull`**: Deprecated in favor of `last`

