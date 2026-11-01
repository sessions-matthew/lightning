# `std.hash_map`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/hash_map.zig`  
> [← Back to Standard Library Index](README.md)

## Types

### `AutoHashMap`

```zig
pub fn AutoHashMap(comptime K: type, comptime V: type) type
```


### `AutoHashMapUnmanaged`

```zig
pub fn AutoHashMapUnmanaged(comptime K: type, comptime V: type) type
```


### `AutoContext`

```zig
pub fn AutoContext(comptime K: type) type
```


### Constants & Variables

- **`hash`**: 
- **`eql`**: 

### `StringHashMap`

```zig
pub fn StringHashMap(comptime V: type) type
```

Builtin hashmap for strings as keys.
Key memory is managed by the caller.  Keys and values
will not automatically be freed.

### `StringHashMapUnmanaged`

```zig
pub fn StringHashMapUnmanaged(comptime V: type) type
```

Key memory is managed by the caller.  Keys and values
will not automatically be freed.

### `StringIndexContext`


### Fields

- `bytes: *const std.ArrayList(u8)`
  

### Functions

#### `eql`

```zig
pub fn eql(_: @This(), a: u32, b: u32) bool
```


#### `hash`

```zig
pub fn hash(ctx: @This(), key: u32) u64
```


### `StringIndexAdapter`


### Fields

- `bytes: *const std.ArrayList(u8)`
  

### Functions

#### `eql`

```zig
pub fn eql(ctx: @This(), a: []const u8, b: u32) bool
```


#### `hash`

```zig
pub fn hash(_: @This(), adapted_key: []const u8) u64
```


### `HashMap`

```zig
pub fn HashMap(comptime K: type, comptime V: type, comptime Context: type, comptime max_load_percentage: u64, ) type
```

General purpose hash table.
No order is guaranteed and any modification invalidates live iterators.
It provides fast operations (lookup, insertion, deletion) with quite high
load factors (up to 80% by default) for low memory usage.
For a hash map that can be initialized directly that does not store an Allocator
field, see `HashMapUnmanaged`.
If iterating over the table entries is a strong usecase and needs to be fast,
prefer the alternative `std.ArrayHashMap`.
Context must be a struct type with two member functions:
  hash(self, K) u64
  eql(self, K, K) bool
Adapted variants of many functions are provided.  These variants
take a pseudo key instead of a key.  Their context must have the functions:
  hash(self, PseudoKey) u64
  eql(self, PseudoKey, K) bool

### Fields

- `unmanaged: Unmanaged`
  
- `allocator: Allocator`
  
- `ctx: Context`
  

### Types

#### `Unmanaged`

The type of the unmanaged hash map underlying this wrapper

### Functions

#### `init`

```zig
pub fn init(allocator: Allocator) Self
```

Create a managed hash map with an empty context.
If the context is not zero-sized, you must use
initContext(allocator, ctx) instead.

#### `initContext`

```zig
pub fn initContext(allocator: Allocator, ctx: Context) Self
```

Create a managed hash map with a context

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

#### `deinit`

```zig
pub fn deinit(self: *Self) void
```

Release the backing array and invalidate this map.
This does *not* deinit keys, values, or the context!
If your keys or values need to be released, ensure
that that is done before calling this function.

#### `clearRetainingCapacity`

```zig
pub fn clearRetainingCapacity(self: *Self) void
```

Empty the map, but keep the backing allocation for future use.
This does *not* free keys or values! Be sure to
release them if they need deinitialization before
calling this function.

#### `clearAndFree`

```zig
pub fn clearAndFree(self: *Self) void
```

Empty the map and release the backing allocation.
This does *not* free keys or values! Be sure to
release them if they need deinitialization before
calling this function.

#### `count`

```zig
pub fn count(self: Self) Size
```

Return the number of items in the map.

#### `iterator`

```zig
pub fn iterator(self: *const Self) Iterator
```

Create an iterator over the entries in the map.
The iterator is invalidated if the map is modified.

#### `keyIterator`

```zig
pub fn keyIterator(self: Self) KeyIterator
```

Create an iterator over the keys in the map.
The iterator is invalidated if the map is modified.

#### `valueIterator`

```zig
pub fn valueIterator(self: Self) ValueIterator
```

Create an iterator over the values in the map.
The iterator is invalidated if the map is modified.

#### `getOrPut`

```zig
pub fn getOrPut(self: *Self, key: K) Allocator.Error!GetOrPutResult
```

If key exists this function cannot fail.
If there is an existing item with `key`, then the result's
`Entry` pointers point to it, and found_existing is true.
Otherwise, puts a new item with undefined value, and
the `Entry` pointers point to it. Caller should then initialize
the value (but not the key).

#### `getOrPutAdapted`

```zig
pub fn getOrPutAdapted(self: *Self, key: anytype, ctx: anytype) Allocator.Error!GetOrPutResult
```

If key exists this function cannot fail.
If there is an existing item with `key`, then the result's
`Entry` pointers point to it, and found_existing is true.
Otherwise, puts a new item with undefined key and value, and
the `Entry` pointers point to it. Caller must then initialize
the key and value.

#### `getOrPutAssumeCapacity`

```zig
pub fn getOrPutAssumeCapacity(self: *Self, key: K) GetOrPutResult
```

If there is an existing item with `key`, then the result's
`Entry` pointers point to it, and found_existing is true.
Otherwise, puts a new item with undefined value, and
the `Entry` pointers point to it. Caller should then initialize
the value (but not the key).
If a new entry needs to be stored, this function asserts there
is enough capacity to store it.

#### `getOrPutAssumeCapacityAdapted`

```zig
pub fn getOrPutAssumeCapacityAdapted(self: *Self, key: anytype, ctx: anytype) GetOrPutResult
```

If there is an existing item with `key`, then the result's
`Entry` pointers point to it, and found_existing is true.
Otherwise, puts a new item with undefined value, and
the `Entry` pointers point to it. Caller must then initialize
the key and value.
If a new entry needs to be stored, this function asserts there
is enough capacity to store it.

#### `getOrPutValue`

```zig
pub fn getOrPutValue(self: *Self, key: K, value: V) Allocator.Error!Entry
```


#### `ensureTotalCapacity`

```zig
pub fn ensureTotalCapacity(self: *Self, expected_count: Size) Allocator.Error!void
```

Increases capacity, guaranteeing that insertions up until the
`expected_count` will not cause an allocation, and therefore cannot fail.

#### `ensureUnusedCapacity`

```zig
pub fn ensureUnusedCapacity(self: *Self, additional_count: Size) Allocator.Error!void
```

Increases capacity, guaranteeing that insertions up until
`additional_count` **more** items will not cause an allocation, and
therefore cannot fail.

#### `capacity`

```zig
pub fn capacity(self: Self) Size
```

Returns the number of total elements which may be present before it is
no longer guaranteed that no allocations will be performed.

#### `put`

```zig
pub fn put(self: *Self, key: K, value: V) Allocator.Error!void
```

Clobbers any existing data. To detect if a put would clobber
existing data, see `getOrPut`.

#### `putNoClobber`

```zig
pub fn putNoClobber(self: *Self, key: K, value: V) Allocator.Error!void
```

Inserts a key-value pair into the hash map, asserting that no previous
entry with the same key is already present

#### `putAssumeCapacity`

```zig
pub fn putAssumeCapacity(self: *Self, key: K, value: V) void
```

Asserts there is enough capacity to store the new key-value pair.
Clobbers any existing data. To detect if a put would clobber
existing data, see `getOrPutAssumeCapacity`.

#### `putAssumeCapacityNoClobber`

```zig
pub fn putAssumeCapacityNoClobber(self: *Self, key: K, value: V) void
```

Asserts there is enough capacity to store the new key-value pair.
Asserts that it does not clobber any existing data.
To detect if a put would clobber existing data, see `getOrPutAssumeCapacity`.

#### `fetchPut`

```zig
pub fn fetchPut(self: *Self, key: K, value: V) Allocator.Error!?KV
```

Inserts a new `Entry` into the hash map, returning the previous one, if any.

#### `fetchPutAssumeCapacity`

```zig
pub fn fetchPutAssumeCapacity(self: *Self, key: K, value: V) ?KV
```

Inserts a new `Entry` into the hash map, returning the previous one, if any.
If insertion happens, asserts there is enough capacity without allocating.

#### `fetchRemove`

```zig
pub fn fetchRemove(self: *Self, key: K) ?KV
```

Removes a value from the map and returns the removed kv pair.

#### `fetchRemoveAdapted`

```zig
pub fn fetchRemoveAdapted(self: *Self, key: anytype, ctx: anytype) ?KV
```


#### `get`

```zig
pub fn get(self: Self, key: K) ?V
```

Finds the value associated with a key in the map

#### `getAdapted`

```zig
pub fn getAdapted(self: Self, key: anytype, ctx: anytype) ?V
```


#### `getPtr`

```zig
pub fn getPtr(self: Self, key: K) ?*V
```


#### `getPtrAdapted`

```zig
pub fn getPtrAdapted(self: Self, key: anytype, ctx: anytype) ?*V
```


#### `getKey`

```zig
pub fn getKey(self: Self, key: K) ?K
```

Finds the actual key associated with an adapted key in the map

#### `getKeyAdapted`

```zig
pub fn getKeyAdapted(self: Self, key: anytype, ctx: anytype) ?K
```


#### `getKeyPtr`

```zig
pub fn getKeyPtr(self: Self, key: K) ?*K
```


#### `getKeyPtrAdapted`

```zig
pub fn getKeyPtrAdapted(self: Self, key: anytype, ctx: anytype) ?*K
```


#### `getEntry`

```zig
pub fn getEntry(self: Self, key: K) ?Entry
```

Finds the key and value associated with a key in the map

#### `getEntryAdapted`

```zig
pub fn getEntryAdapted(self: Self, key: anytype, ctx: anytype) ?Entry
```


#### `contains`

```zig
pub fn contains(self: Self, key: K) bool
```

Check if the map contains a key

#### `containsAdapted`

```zig
pub fn containsAdapted(self: Self, key: anytype, ctx: anytype) bool
```


#### `remove`

```zig
pub fn remove(self: *Self, key: K) bool
```

If there is an `Entry` with a matching key, it is deleted from
the hash map, and this function returns true.  Otherwise this
function returns false.

TODO: answer the question in these doc comments, does this
increase the unused capacity by one?

#### `removeAdapted`

```zig
pub fn removeAdapted(self: *Self, key: anytype, ctx: anytype) bool
```

TODO: answer the question in these doc comments, does this
increase the unused capacity by one?

#### `removeByPtr`

```zig
pub fn removeByPtr(self: *Self, key_ptr: *K) void
```

Delete the entry with key pointed to by key_ptr from the hash map.
key_ptr is assumed to be a valid pointer to a key that is present
in the hash map.

TODO: answer the question in these doc comments, does this
increase the unused capacity by one?

#### `clone`

```zig
pub fn clone(self: Self) Allocator.Error!Self
```

Creates a copy of this map, using the same allocator

#### `cloneWithAllocator`

```zig
pub fn cloneWithAllocator(self: Self, new_allocator: Allocator) Allocator.Error!Self
```

Creates a copy of this map, using a specified allocator

#### `cloneWithContext`

```zig
pub fn cloneWithContext(self: Self, new_ctx: anytype) Allocator.Error!HashMap(K, V, @TypeOf(new_ctx), max_load_percentage)
```

Creates a copy of this map, using a specified context

#### `cloneWithAllocatorAndContext`

```zig
pub fn cloneWithAllocatorAndContext(self: Self, new_allocator: Allocator, new_ctx: anytype, ) Allocator.Error!HashMap(K, V, @TypeOf(new_ctx), max_load_percentage)
```

Creates a copy of this map, using a specified allocator and context.

#### `move`

```zig
pub fn move(self: *Self) Self
```

Set the map to an empty state, making deinitialization a no-op, and
returning a copy of the original.

#### `rehash`

```zig
pub fn rehash(self: *Self) void
```

Rehash the map, in-place.

Over time, due to the current tombstone-based implementation, a
HashMap could become fragmented due to the buildup of tombstone
entries that causes a performance degradation due to excessive
probing. The kind of pattern that might cause this is a long-lived
HashMap with repeated inserts and deletes.

After this function is called, there will be no tombstones in
the HashMap, each of the entries is rehashed and any existing
key/value pointers into the HashMap are invalidated.

### Constants & Variables

- **`Entry`**: An entry, containing pointers to a key and value stored in the map
- **`KV`**: A copy of a key and value which are no longer in the map
- **`Hash`**: The integer type that is the result of hashing
- **`Iterator`**: The iterator type returned by iterator()
- **`KeyIterator`**: 
- **`ValueIterator`**: 
- **`Size`**: The integer type used to store the size of the map
- **`GetOrPutResult`**: The type returned from getOrPut and variants

## Namespaces

- **`StringContext`**: 

## Functions

### `getAutoHashFn`

```zig
pub fn getAutoHashFn(comptime K: type, comptime Context: type) (fn (Context, K) u64)
```


### `getAutoEqlFn`

```zig
pub fn getAutoEqlFn(comptime K: type, comptime Context: type) (fn (Context, K, K) bool)
```


### `eqlString`

```zig
pub fn eqlString(a: []const u8, b: []const u8) bool
```


### `hashString`

```zig
pub fn hashString(s: []const u8) u64
```


## Constants & Variables

- **`default_max_load_percentage`**: 
- **`HashMapUnmanaged`**: A HashMap based on open addressing and linear probing.

