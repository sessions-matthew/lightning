# `std.array_hash_map`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/array_hash_map.zig`  
> [← Back to Standard Library Index](README.md)

## Types

### `Auto`

```zig
pub fn Auto(comptime K: type, comptime V: type) type
```

An `ArrayHashMap` with default hash and equal functions.

See `AutoContext` for a description of the hash and equal implementations.

### `String`

```zig
pub fn String(comptime V: type) type
```

An `ArrayHashMap` with strings as keys.

### `Custom`

```zig
pub fn Custom(comptime K: type, comptime V: type, comptime Context: type, comptime store_hash: bool, ) type
```

A hash table of keys and values, each stored sequentially.

Insertion order is preserved. In general, this data structure supports the same
operations as `std.ArrayList`.

Deletion operations:
* `swapRemove` - O(1)
* `orderedRemove` - O(N)

Modifying the hash map while iterating is allowed, however, one must understand
the (well defined) behavior when mixing insertions and deletions with iteration.

This type does not store an `Allocator` field - the `Allocator` must be passed in
with each function call that requires it.

Can be initialized directly using the default field values.

This type is designed to have low overhead for small numbers of entries. When
`store_hash` is `false` and the number of entries in the map is less than 9,
the overhead cost of using `ArrayHashMap` rather than `std.ArrayList` is
only a single pointer-sized integer.

Default initialization of this struct is deprecated; use `.empty` instead.

### Fields

- `entries: DataList = .{}`
  It is permitted to access this field directly.
  After any modification to the keys, consider calling `reIndex`.
- `index_header: ?*IndexHeader = null`
  When entries length is less than `linear_scan_max`, this remains `null`.
  Once entries length grows big enough, this field is allocated. There is
  an IndexHeader followed by an array of Index(I) structs, where I is defined
  by how many total indexes there are.
- `pointer_stability: std.debug.SafetyLock = .{}`
  Used to detect memory safety violations.

### Types

#### `Entry`

Modifying the key is allowed only if it does not change the hash.
Modifying the value is allowed.
Entry pointers become invalid whenever this ArrayHashMap is modified,
unless `ensureTotalCapacity`/`ensureUnusedCapacity` was previously used.

#### `KV`

A KV pair which has been copied out of the backing store

#### `Data`

The Data type used for the MultiArrayList backing this map

#### `DataList`

The MultiArrayList type backing this map

#### `Hash`

The stored hash type, either u32 or void.

#### `GetOrPutResult`

getOrPut variants return this structure, with pointers
to the backing store and a flag to indicate whether an
existing entry was found.
Modifying the key is allowed only if it does not change the hash.
Modifying the value is allowed.
Entry pointers become invalid whenever this ArrayHashMap is modified,
unless `ensureTotalCapacity`/`ensureUnusedCapacity` was previously used.

#### `Iterator`


### Functions

#### `init`

```zig
pub fn init(gpa: Allocator, key_list: []const K, value_list: []const V) Oom!Self
```


#### `reinit`

```zig
pub fn reinit(self: *Self, gpa: Allocator, key_list: []const K, value_list: []const V) Oom!void
```

An empty `value_list` may be passed, in which case the values array becomes `undefined`.

#### `deinit`

```zig
pub fn deinit(self: *Self, gpa: Allocator) void
```

Frees the backing allocation and leaves the map in an undefined state.
Note that this does not free keys or values.  You must take care of that
before calling this function, if it is needed.

#### `lockPointers`

```zig
pub fn lockPointers(self: *Self) void
```

Puts the hash map into a state where any method call that would
cause an existing key or value pointer to become invalidated will
instead trigger an assertion.

`lockPointers` may be called multiple times. This allows multiple
independent users of the hash map to keep it locked simultaneously.

`unlockPointers` restores the hash map to its previous state when
called the same number of times as `lockPointers`.

#### `unlockPointers`

```zig
pub fn unlockPointers(self: *Self) void
```

Undoes one call to `lockPointers`.

#### `clearRetainingCapacity`

```zig
pub fn clearRetainingCapacity(self: *Self) void
```

Clears the map but retains the backing allocation for future use.

#### `clearAndFree`

```zig
pub fn clearAndFree(self: *Self, gpa: Allocator) void
```

Clears the map and releases the backing allocation

#### `count`

```zig
pub fn count(self: Self) usize
```

Returns the number of KV pairs stored in this map.

#### `keys`

```zig
pub fn keys(self: Self) []K
```

Returns the backing array of keys in this map. Modifying the map may
invalidate this array. Modifying this array in a way that changes
key hashes or key equality puts the map into an unusable state until
`reIndex` is called.

#### `values`

```zig
pub fn values(self: Self) []V
```

Returns the backing array of values in this map. Modifying the map
may invalidate this array. It is permitted to modify the values in
this array.

#### `iterator`

```zig
pub fn iterator(self: Self) Iterator
```

Returns an iterator over the pairs in this map.
Modifying the map may invalidate this iterator.

#### `getOrPut`

```zig
pub fn getOrPut(self: *Self, gpa: Allocator, key: K) Oom!GetOrPutResult
```

If key exists this function cannot fail.
If there is an existing item with `key`, then the result
`Entry` pointer points to it, and found_existing is true.
Otherwise, puts a new item with undefined value, and
the `Entry` pointer points to it. Caller should then initialize
the value (but not the key).

#### `getOrPutContext`

```zig
pub fn getOrPutContext(self: *Self, gpa: Allocator, key: K, ctx: Context) Oom!GetOrPutResult
```


#### `getOrPutAdapted`

```zig
pub fn getOrPutAdapted(self: *Self, gpa: Allocator, key: anytype, key_ctx: anytype) Oom!GetOrPutResult
```


#### `getOrPutContextAdapted`

```zig
pub fn getOrPutContextAdapted(self: *Self, gpa: Allocator, key: anytype, key_ctx: anytype, ctx: Context) Oom!GetOrPutResult
```


#### `getOrPutAssumeCapacity`

```zig
pub fn getOrPutAssumeCapacity(self: *Self, key: K) GetOrPutResult
```

If there is an existing item with `key`, then the result
`Entry` pointer points to it, and found_existing is true.
Otherwise, puts a new item with undefined value, and
the `Entry` pointer points to it. Caller should then initialize
the value (but not the key).
If a new entry needs to be stored, this function asserts there
is enough capacity to store it.

#### `getOrPutAssumeCapacityContext`

```zig
pub fn getOrPutAssumeCapacityContext(self: *Self, key: K, ctx: Context) GetOrPutResult
```


#### `getOrPutAssumeCapacityAdapted`

```zig
pub fn getOrPutAssumeCapacityAdapted(self: *Self, key: anytype, ctx: anytype) GetOrPutResult
```

If there is an existing item with `key`, then the result
`Entry` pointers point to it, and found_existing is true.
Otherwise, puts a new item with undefined key and value, and
the `Entry` pointers point to it. Caller must then initialize
both the key and the value.
If a new entry needs to be stored, this function asserts there
is enough capacity to store it.

#### `getOrPutValue`

```zig
pub fn getOrPutValue(self: *Self, gpa: Allocator, key: K, value: V) Oom!GetOrPutResult
```


#### `getOrPutValueContext`

```zig
pub fn getOrPutValueContext(self: *Self, gpa: Allocator, key: K, value: V, ctx: Context) Oom!GetOrPutResult
```


#### `ensureTotalCapacity`

```zig
pub fn ensureTotalCapacity(self: *Self, gpa: Allocator, new_capacity: usize) Oom!void
```

Increases capacity, guaranteeing that insertions up until the
`expected_count` will not cause an allocation, and therefore cannot fail.

#### `ensureTotalCapacityContext`

```zig
pub fn ensureTotalCapacityContext(self: *Self, gpa: Allocator, new_capacity: usize, ctx: Context) Oom!void
```


#### `ensureUnusedCapacity`

```zig
pub fn ensureUnusedCapacity(self: *Self, gpa: Allocator, additional_capacity: usize, ) Oom!void
```

Increases capacity, guaranteeing that insertions up until
`additional_count` **more** items will not cause an allocation, and
therefore cannot fail.

#### `ensureUnusedCapacityContext`

```zig
pub fn ensureUnusedCapacityContext(self: *Self, gpa: Allocator, additional_capacity: usize, ctx: Context, ) Oom!void
```


#### `capacity`

```zig
pub fn capacity(self: Self) usize
```

Returns the number of total elements which may be present before it is
no longer guaranteed that no allocations will be performed.

#### `put`

```zig
pub fn put(self: *Self, gpa: Allocator, key: K, value: V) Oom!void
```

Clobbers any existing data. To detect if a put would clobber
existing data, see `getOrPut`.

#### `putContext`

```zig
pub fn putContext(self: *Self, gpa: Allocator, key: K, value: V, ctx: Context) Oom!void
```


#### `putNoClobber`

```zig
pub fn putNoClobber(self: *Self, gpa: Allocator, key: K, value: V) Oom!void
```

Inserts a key-value pair into the hash map, asserting that no previous
entry with the same key is already present

#### `putNoClobberContext`

```zig
pub fn putNoClobberContext(self: *Self, gpa: Allocator, key: K, value: V, ctx: Context) Oom!void
```


#### `putAssumeCapacity`

```zig
pub fn putAssumeCapacity(self: *Self, key: K, value: V) void
```

Asserts there is enough capacity to store the new key-value pair.
Clobbers any existing data. To detect if a put would clobber
existing data, see `getOrPutAssumeCapacity`.

#### `putAssumeCapacityContext`

```zig
pub fn putAssumeCapacityContext(self: *Self, key: K, value: V, ctx: Context) void
```


#### `putAssumeCapacityNoClobber`

```zig
pub fn putAssumeCapacityNoClobber(self: *Self, key: K, value: V) void
```

Asserts there is enough capacity to store the new key-value pair.
Asserts that it does not clobber any existing data.
To detect if a put would clobber existing data, see `getOrPutAssumeCapacity`.

#### `putAssumeCapacityNoClobberContext`

```zig
pub fn putAssumeCapacityNoClobberContext(self: *Self, key: K, value: V, ctx: Context) void
```


#### `fetchPut`

```zig
pub fn fetchPut(self: *Self, gpa: Allocator, key: K, value: V) Oom!?KV
```

Inserts a new `Entry` into the hash map, returning the previous one, if any.

#### `fetchPutContext`

```zig
pub fn fetchPutContext(self: *Self, gpa: Allocator, key: K, value: V, ctx: Context) Oom!?KV
```


#### `fetchPutAssumeCapacity`

```zig
pub fn fetchPutAssumeCapacity(self: *Self, key: K, value: V) ?KV
```

Inserts a new `Entry` into the hash map, returning the previous one, if any.
If insertion happens, asserts there is enough capacity without allocating.

#### `fetchPutAssumeCapacityContext`

```zig
pub fn fetchPutAssumeCapacityContext(self: *Self, key: K, value: V, ctx: Context) ?KV
```


#### `getEntry`

```zig
pub fn getEntry(self: Self, key: K) ?Entry
```

Finds pointers to the key and value storage associated with a key.

#### `getEntryContext`

```zig
pub fn getEntryContext(self: Self, key: K, ctx: Context) ?Entry
```


#### `getEntryAdapted`

```zig
pub fn getEntryAdapted(self: Self, key: anytype, ctx: anytype) ?Entry
```


#### `getIndex`

```zig
pub fn getIndex(self: Self, key: K) ?usize
```

Finds the index in the `entries` array where a key is stored

#### `getIndexContext`

```zig
pub fn getIndexContext(self: Self, key: K, ctx: Context) ?usize
```


#### `getIndexAdapted`

```zig
pub fn getIndexAdapted(self: Self, key: anytype, ctx: anytype) ?usize
```


#### `get`

```zig
pub fn get(self: Self, key: K) ?V
```

Find the value associated with a key

#### `getContext`

```zig
pub fn getContext(self: Self, key: K, ctx: Context) ?V
```


#### `getAdapted`

```zig
pub fn getAdapted(self: Self, key: anytype, ctx: anytype) ?V
```


#### `getPtr`

```zig
pub fn getPtr(self: Self, key: K) ?*V
```

Find a pointer to the value associated with a key

#### `getPtrContext`

```zig
pub fn getPtrContext(self: Self, key: K, ctx: Context) ?*V
```


#### `getPtrAdapted`

```zig
pub fn getPtrAdapted(self: Self, key: anytype, ctx: anytype) ?*V
```


#### `getKey`

```zig
pub fn getKey(self: Self, key: K) ?K
```

Find the actual key associated with an adapted key

#### `getKeyContext`

```zig
pub fn getKeyContext(self: Self, key: K, ctx: Context) ?K
```


#### `getKeyAdapted`

```zig
pub fn getKeyAdapted(self: Self, key: anytype, ctx: anytype) ?K
```


#### `getKeyPtr`

```zig
pub fn getKeyPtr(self: Self, key: K) ?*K
```

Find a pointer to the actual key associated with an adapted key

#### `getKeyPtrContext`

```zig
pub fn getKeyPtrContext(self: Self, key: K, ctx: Context) ?*K
```


#### `getKeyPtrAdapted`

```zig
pub fn getKeyPtrAdapted(self: Self, key: anytype, ctx: anytype) ?*K
```


#### `contains`

```zig
pub fn contains(self: Self, key: K) bool
```

Check whether a key is stored in the map

#### `containsContext`

```zig
pub fn containsContext(self: Self, key: K, ctx: Context) bool
```


#### `containsAdapted`

```zig
pub fn containsAdapted(self: Self, key: anytype, ctx: anytype) bool
```


#### `fetchSwapRemove`

```zig
pub fn fetchSwapRemove(self: *Self, key: K) ?KV
```

If there is an `Entry` with a matching key, it is deleted from
the hash map, and then returned from this function. The entry is
removed from the underlying array by swapping it with the last
element.

#### `fetchSwapRemoveContext`

```zig
pub fn fetchSwapRemoveContext(self: *Self, key: K, ctx: Context) ?KV
```


#### `fetchSwapRemoveAdapted`

```zig
pub fn fetchSwapRemoveAdapted(self: *Self, key: anytype, ctx: anytype) ?KV
```


#### `fetchSwapRemoveContextAdapted`

```zig
pub fn fetchSwapRemoveContextAdapted(self: *Self, key: anytype, key_ctx: anytype, ctx: Context) ?KV
```


#### `fetchOrderedRemove`

```zig
pub fn fetchOrderedRemove(self: *Self, key: K) ?KV
```

If there is an `Entry` with a matching key, it is deleted from
the hash map, and then returned from this function. The entry is
removed from the underlying array by shifting all elements forward
thereby maintaining the current ordering.

#### `fetchOrderedRemoveContext`

```zig
pub fn fetchOrderedRemoveContext(self: *Self, key: K, ctx: Context) ?KV
```


#### `fetchOrderedRemoveAdapted`

```zig
pub fn fetchOrderedRemoveAdapted(self: *Self, key: anytype, ctx: anytype) ?KV
```


#### `fetchOrderedRemoveContextAdapted`

```zig
pub fn fetchOrderedRemoveContextAdapted(self: *Self, key: anytype, key_ctx: anytype, ctx: Context) ?KV
```


#### `swapRemove`

```zig
pub fn swapRemove(self: *Self, key: K) bool
```

If there is an `Entry` with a matching key, it is deleted from
the hash map. The entry is removed from the underlying array
by swapping it with the last element.  Returns true if an entry
was removed, false otherwise.

#### `swapRemoveContext`

```zig
pub fn swapRemoveContext(self: *Self, key: K, ctx: Context) bool
```


#### `swapRemoveAdapted`

```zig
pub fn swapRemoveAdapted(self: *Self, key: anytype, ctx: anytype) bool
```


#### `swapRemoveContextAdapted`

```zig
pub fn swapRemoveContextAdapted(self: *Self, key: anytype, key_ctx: anytype, ctx: Context) bool
```


#### `orderedRemove`

```zig
pub fn orderedRemove(self: *Self, key: K) bool
```

If there is an `Entry` with a matching key, it is deleted from
the hash map. The entry is removed from the underlying array
by shifting all elements forward, thereby maintaining the
current ordering.  Returns true if an entry was removed, false otherwise.

#### `orderedRemoveContext`

```zig
pub fn orderedRemoveContext(self: *Self, key: K, ctx: Context) bool
```


#### `orderedRemoveAdapted`

```zig
pub fn orderedRemoveAdapted(self: *Self, key: anytype, ctx: anytype) bool
```


#### `orderedRemoveContextAdapted`

```zig
pub fn orderedRemoveContextAdapted(self: *Self, key: anytype, key_ctx: anytype, ctx: Context) bool
```


#### `swapRemoveAt`

```zig
pub fn swapRemoveAt(self: *Self, index: usize) void
```

Deletes the item at the specified index in `entries` from
the hash map. The entry is removed from the underlying array
by swapping it with the last element.

#### `swapRemoveAtContext`

```zig
pub fn swapRemoveAtContext(self: *Self, index: usize, ctx: Context) void
```


#### `orderedRemoveAt`

```zig
pub fn orderedRemoveAt(self: *Self, index: usize) void
```

Deletes the item at the specified index in `entries` from
the hash map. The entry is removed from the underlying array
by shifting all elements forward, thereby maintaining the
current ordering.

#### `orderedRemoveAtContext`

```zig
pub fn orderedRemoveAtContext(self: *Self, index: usize, ctx: Context) void
```


#### `orderedRemoveAtMany`

```zig
pub fn orderedRemoveAtMany(self: *Self, gpa: Allocator, sorted_indexes: []const usize) Oom!void
```

Remove the entries indexed by `sorted_indexes`. The indexes to be
removed correspond to state before deletion.

This operation is O(N).

Asserts that each index to be removed is in bounds.

Invalidates key and element pointers beyond the first deleted index.

#### `orderedRemoveAtManyContext`

```zig
pub fn orderedRemoveAtManyContext(self: *Self, gpa: Allocator, sorted_indexes: []const usize, ctx: Context, ) Oom!void
```


#### `clone`

```zig
pub fn clone(self: Self, gpa: Allocator) Oom!Self
```

Create a copy of the hash map which can be modified separately.
The copy uses the same context as this instance, but is allocated
with the provided allocator.

#### `cloneContext`

```zig
pub fn cloneContext(self: Self, gpa: Allocator, ctx: Context) Oom!Self
```


#### `move`

```zig
pub fn move(self: *Self) Self
```

Set the map to an empty state, making deinitialization a no-op, and
returning a copy of the original.

#### `reIndex`

```zig
pub fn reIndex(self: *Self, gpa: Allocator) Oom!void
```

Recomputes stored hashes and rebuilds the key indexes. If the
underlying keys have been modified directly, call this method to
recompute the denormalized metadata necessary for the operation of
the methods of this map that lookup entries by key.

One use case for this is directly calling `entries.resize()` to grow
the underlying storage, and then setting the `keys` and `values`
directly without going through the methods of this map.

The time complexity of this operation is O(n).

#### `reIndexContext`

```zig
pub fn reIndexContext(self: *Self, gpa: Allocator, ctx: Context) Oom!void
```


#### `setKey`

```zig
pub fn setKey(self: *Self, index: usize, new_key: K) void
```

Modify an entry's key without reordering any entries.

#### `setKeyContext`

```zig
pub fn setKeyContext(self: *Self, index: usize, new_key: K, ctx: Context) void
```


#### `sort`

```zig
pub inline fn sort(self: *Self, sort_ctx: anytype) void
```

Sorts the entries and then rebuilds the index.
`sort_ctx` must have this method:
`fn lessThan(ctx: @TypeOf(ctx), a_index: usize, b_index: usize) bool`
Uses a stable sorting algorithm.

#### `sortUnstable`

```zig
pub inline fn sortUnstable(self: *Self, sort_ctx: anytype) void
```

Sorts the entries and then rebuilds the index.
`sort_ctx` must have this method:
`fn lessThan(ctx: @TypeOf(ctx), a_index: usize, b_index: usize) bool`
Uses an unstable sorting algorithm.

#### `sortContext`

```zig
pub inline fn sortContext(self: *Self, sort_ctx: anytype, ctx: Context) void
```


#### `sortUnstableContext`

```zig
pub inline fn sortUnstableContext(self: *Self, sort_ctx: anytype, ctx: Context) void
```


#### `shrinkRetainingCapacity`

```zig
pub fn shrinkRetainingCapacity(self: *Self, new_len: usize) void
```

Shrinks the underlying `Entry` array to `new_len` elements and
discards any associated index entries. Keeps capacity the same.

Asserts the discarded entries remain initialized and capable of
performing hash and equality checks. Any deinitialization of
discarded entries must take place *after* calling this function.

#### `shrinkRetainingCapacityContext`

```zig
pub fn shrinkRetainingCapacityContext(self: *Self, new_len: usize, ctx: Context) void
```

Shrinks the underlying `Entry` array to `new_len` elements and
discards any associated index entries. Keeps capacity the same.

Asserts the discarded entries remain initialized and capable of
performing hash and equality checks. Any deinitialization of
discarded entries must take place *after* calling this function.

#### `shrinkAndFree`

```zig
pub fn shrinkAndFree(self: *Self, gpa: Allocator, new_len: usize) void
```

Shrinks the underlying `Entry` array to `new_len` elements and
discards any associated index entries. Reduces allocated capacity.

Asserts the discarded entries remain initialized and capable of
performing hash and equality checks. It is a bug to call this
function if the discarded entries require deinitialization. For
that use case, `shrinkRetainingCapacity` can be used instead.

#### `shrinkAndFreeContext`

```zig
pub fn shrinkAndFreeContext(self: *Self, gpa: Allocator, new_len: usize, ctx: Context) void
```

Shrinks the underlying `Entry` array to `new_len` elements and
discards any associated index entries. Reduces allocated capacity.

Asserts the discarded entries remain initialized and capable of
performing hash and equality checks. It is a bug to call this
function if the discarded entries require deinitialization. For
that use case, `shrinkRetainingCapacityContext` can be used
instead.

#### `pop`

```zig
pub fn pop(self: *Self) ?KV
```

Removes the last inserted `Entry` in the hash map and returns it.
Otherwise returns null.

#### `popContext`

```zig
pub fn popContext(self: *Self, ctx: Context) ?KV
```


### Constants & Variables

- **`empty`**: A map containing no keys or values.

### `AutoContext`

```zig
pub fn AutoContext(comptime K: type) type
```


### Constants & Variables

- **`hash`**: 
- **`eql`**: 

## Namespaces

- **`StringContext`**: 

## Functions

### `eqlString`

```zig
pub fn eqlString(a: []const u8, b: []const u8) bool
```


### `hashString`

```zig
pub fn hashString(s: []const u8) u32
```


### `f`

```zig
pub fn f(allocator: Allocator) !void
```


### `lessThan`

```zig
pub fn lessThan(ctx: @This(), a_index: usize, b_index: usize) bool
```


### `getHashPtrAddrFn`

```zig
pub fn getHashPtrAddrFn(comptime K: type, comptime Context: type) (fn (Context, K) u32)
```


### `getTrivialEqlFn`

```zig
pub fn getTrivialEqlFn(comptime K: type, comptime Context: type) (fn (Context, K, K) bool)
```


### `getAutoHashFn`

```zig
pub fn getAutoHashFn(comptime K: type, comptime Context: type) (fn (Context, K) u32)
```


### `getAutoEqlFn`

```zig
pub fn getAutoEqlFn(comptime K: type, comptime Context: type) (fn (Context, K, K, usize) bool)
```


### `autoEqlIsCheap`

```zig
pub fn autoEqlIsCheap(comptime K: type) bool
```


### `getAutoHashStratFn`

```zig
pub fn getAutoHashStratFn(comptime K: type, comptime Context: type, comptime strategy: std.hash.Strategy) (fn (Context, K) u32)
```


## Constants & Variables

- **`ArrayHashMap`**: Deprecated; use `Custom`.

