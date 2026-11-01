# `std.buf_set`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/buf_set.zig`  
> [← Back to Standard Library Index](README.md)

## Types

### `BufSet`

A BufSet is a set of strings.  The BufSet duplicates
strings internally, and never takes ownership of strings
which are passed to it.

### Fields

- `hash_map: BufSetHashMap`
  

### Functions

#### `init`

```zig
pub fn init(a: Allocator) BufSet
```

Create a BufSet using an allocator.  The allocator will
be used internally for both backing allocations and
string duplication.

#### `deinit`

```zig
pub fn deinit(self: *BufSet) void
```

Free a BufSet along with all stored keys.

#### `insert`

```zig
pub fn insert(self: *BufSet, value: []const u8) !void
```

Insert an item into the BufSet.  The item will be
copied, so the caller may delete or reuse the
passed string immediately.

#### `contains`

```zig
pub fn contains(self: BufSet, value: []const u8) bool
```

Check if the set contains an item matching the passed string

#### `remove`

```zig
pub fn remove(self: *BufSet, value: []const u8) void
```

Remove an item from the set.

#### `count`

```zig
pub fn count(self: *const BufSet) usize
```

Returns the number of items stored in the set

#### `iterator`

```zig
pub fn iterator(self: *const BufSet) Iterator
```

Returns an iterator over the items stored in the set.
Iteration order is arbitrary.

#### `allocator`

```zig
pub fn allocator(self: *const BufSet) Allocator
```

Get the allocator used by this set

#### `cloneWithAllocator`

```zig
pub fn cloneWithAllocator(self: *const BufSet, new_allocator: Allocator, ) Allocator.Error!BufSet
```

Creates a copy of this BufSet, using a specified allocator.

#### `clone`

```zig
pub fn clone(self: *const BufSet) Allocator.Error!BufSet
```

Creates a copy of this BufSet, using the same allocator.

### Constants & Variables

- **`Iterator`**: 

