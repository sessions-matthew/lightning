# `std.bit_set`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/bit_set.zig`  
> [← Back to Standard Library Index](README.md)

This file defines several variants of bit sets.  A bit set
is a densely stored set of integers with a known maximum,
in which each integer gets a single bit.  Bit sets have very
fast presence checks, update operations, and union and intersection
operations.  However, if the number of possible items is very
large and the number of actual items in a given set is usually
small, they may be less memory efficient than an array set.

There are five variants defined here:

Integer:
  A bit set with static size, which is backed by a single integer.
  This set is good for sets with a small size, but may generate
  inefficient code for larger sets, especially in debug mode.

Array:
  A bit set with static size, which is backed by an array of usize.
  This set is good for sets with a larger size, but may use
  more bytes than necessary if your set is small.

Static:
  Picks either Integer or Array depending on the requested
  size.  The interfaces of these two types match exactly, except for fields.

Dynamic:
  A bit set with runtime-known size, backed by an allocated slice
  of usize.

DynamicManaged:
  A variant of Dynamic which stores an allocator, using it when needed.

## Types

### `Static`

```zig
pub fn Static(comptime size: usize) type
```

Returns the optimal static bit set type for the specified number
of elements: either `IntegerBitSet` or `ArrayBitSet`,
both of which fulfill the same interface.
The returned type will perform no allocations,
can be copied by value, and does not require deinitialization.

### `Integer`

```zig
pub fn Integer(comptime size: u16) type
```

A bit set with static size, which is backed by a single integer.
This set is good for sets with a small size, but may generate
inefficient code for larger sets, especially in debug mode.

### Fields

- `mask: MaskInt`
  The bit mask, as a single integer

### Types

#### `ShiftInt`

The integer type used to shift a mask in this bit set

#### `Iterator`

```zig
pub fn Iterator(comptime options: IteratorOptions) type
```


### Functions

#### `capacity`

```zig
pub inline fn capacity(self: Self) usize
```

Returns the number of bits in this bit set

#### `isSet`

```zig
pub fn isSet(self: Self, index: usize) bool
```

Returns true if the bit at the specified index
is present in the set, false otherwise.

#### `count`

```zig
pub fn count(self: Self) usize
```

Returns the total number of set bits in this bit set.

#### `setValue`

```zig
pub fn setValue(self: *Self, index: usize, value: bool) void
```

Changes the value of the specified bit of the bit
set to match the passed boolean.

#### `set`

```zig
pub fn set(self: *Self, index: usize) void
```

Adds a specific bit to the bit set

#### `setRangeValue`

```zig
pub fn setRangeValue(self: *Self, range: Range, value: bool) void
```

Changes the value of all bits in the specified range to
match the passed boolean.

#### `unset`

```zig
pub fn unset(self: *Self, index: usize) void
```

Removes a specific bit from the bit set

#### `toggle`

```zig
pub fn toggle(self: *Self, index: usize) void
```

Flips a specific bit in the bit set

#### `toggleSet`

```zig
pub fn toggleSet(self: *Self, toggles: Self) void
```

Flips all bits in this bit set which are present
in the toggles bit set.

#### `toggleAll`

```zig
pub fn toggleAll(self: *Self) void
```

Flips every bit in the bit set.

#### `unsetAll`

```zig
pub fn unsetAll(self: *Self) void
```

Set all bits to 0.

#### `setAll`

```zig
pub fn setAll(self: *Self) void
```

Set all bits to 1.

#### `setUnion`

```zig
pub fn setUnion(self: *Self, other: Self) void
```

Performs a union of two bit sets, and stores the
result in the first one.  Bits in the result are
set if the corresponding bits were set in either input.

#### `setIntersection`

```zig
pub fn setIntersection(self: *Self, other: Self) void
```

Performs an intersection of two bit sets, and stores
the result in the first one.  Bits in the result are
set if the corresponding bits were set in both inputs.

#### `findFirstSet`

```zig
pub fn findFirstSet(self: Self) ?usize
```

Finds the index of the first set bit.
If no bits are set, returns null.

#### `findLastSet`

```zig
pub fn findLastSet(self: Self) ?usize
```

Finds the index of the last set bit.
If no bits are set, returns null.

#### `toggleFirstSet`

```zig
pub fn toggleFirstSet(self: *Self) ?usize
```

Finds the index of the first set bit, and unsets it.
If no bits are set, returns null.

#### `eql`

```zig
pub fn eql(self: Self, other: Self) bool
```

Returns true iff every corresponding bit in both
bit sets are the same.

#### `subsetOf`

```zig
pub fn subsetOf(self: Self, other: Self) bool
```

Returns true iff the first bit set is the subset
of the second one.

#### `supersetOf`

```zig
pub fn supersetOf(self: Self, other: Self) bool
```

Returns true iff the first bit set is the superset
of the second one.

#### `complement`

```zig
pub fn complement(self: Self) Self
```

Returns the complement bit sets. Bits in the result
are set if the corresponding bits were not set.

#### `unionWith`

```zig
pub fn unionWith(self: Self, other: Self) Self
```

Returns the union of two bit sets. Bits in the
result are set if the corresponding bits were set
in either input.

#### `intersectWith`

```zig
pub fn intersectWith(self: Self, other: Self) Self
```

Returns the intersection of two bit sets. Bits in
the result are set if the corresponding bits were
set in both inputs.

#### `xorWith`

```zig
pub fn xorWith(self: Self, other: Self) Self
```

Returns the xor of two bit sets. Bits in the
result are set if the corresponding bits were
not the same in both inputs.

#### `differenceWith`

```zig
pub fn differenceWith(self: Self, other: Self) Self
```

Returns the difference of two bit sets. Bits in
the result are set if set in the first but not
set in the second set.

#### `iterator`

```zig
pub fn iterator(self: *const Self, comptime options: IteratorOptions) Iterator(options)
```

Iterates through the items in the set, according to the options.
The default options (.{}) will iterate indices of set bits in
ascending order.  Modifications to the underlying bit set may
or may not be observed by the iterator.

### Constants & Variables

- **`bit_length`**: The number of items in this bit set
- **`MaskInt`**: The integer type used to represent a mask in this bit set
- **`empty`**: A bit set with no elements present.
- **`full`**: A bit set with all elements present.

### `Array`

```zig
pub fn Array(comptime MaskIntType: type, comptime size: usize) type
```

A bit set with static size, which is backed by an array of usize.
This set is good for sets with a larger size, but may use
more bytes than necessary if your set is small.

### Fields

- `masks: [num_masks]MaskInt`
  The bit masks, ordered with lower indices first.
  Padding bits at the end are undefined.

### Types

#### `ShiftInt`

The integer type used to shift a mask in this bit set

#### `Iterator`

```zig
pub fn Iterator(comptime options: IteratorOptions) type
```


### Functions

#### `capacity`

```zig
pub inline fn capacity(self: Self) usize
```

Returns the number of bits in this bit set

#### `isSet`

```zig
pub fn isSet(self: Self, index: usize) bool
```

Returns true if the bit at the specified index
is present in the set, false otherwise.

#### `count`

```zig
pub fn count(self: Self) usize
```

Returns the total number of set bits in this bit set.

#### `setValue`

```zig
pub fn setValue(self: *Self, index: usize, value: bool) void
```

Changes the value of the specified bit of the bit
set to match the passed boolean.

#### `set`

```zig
pub fn set(self: *Self, index: usize) void
```

Adds a specific bit to the bit set

#### `setRangeValue`

```zig
pub fn setRangeValue(self: *Self, range: Range, value: bool) void
```

Changes the value of all bits in the specified range to
match the passed boolean.

#### `unset`

```zig
pub fn unset(self: *Self, index: usize) void
```

Removes a specific bit from the bit set

#### `toggle`

```zig
pub fn toggle(self: *Self, index: usize) void
```

Flips a specific bit in the bit set

#### `toggleSet`

```zig
pub fn toggleSet(self: *Self, toggles: Self) void
```

Flips all bits in this bit set which are present
in the toggles bit set.

#### `toggleAll`

```zig
pub fn toggleAll(self: *Self) void
```

Flips every bit in the bit set.

#### `unsetAll`

```zig
pub fn unsetAll(self: *Self) void
```

Set all bits to 0.

#### `setAll`

```zig
pub fn setAll(self: *Self) void
```

Set all bits to 1.

#### `setUnion`

```zig
pub fn setUnion(self: *Self, other: Self) void
```

Performs a union of two bit sets, and stores the
result in the first one.  Bits in the result are
set if the corresponding bits were set in either input.

#### `setIntersection`

```zig
pub fn setIntersection(self: *Self, other: Self) void
```

Performs an intersection of two bit sets, and stores
the result in the first one.  Bits in the result are
set if the corresponding bits were set in both inputs.

#### `findFirstSet`

```zig
pub fn findFirstSet(self: Self) ?usize
```

Finds the index of the first set bit.
If no bits are set, returns null.

#### `findLastSet`

```zig
pub fn findLastSet(self: Self) ?usize
```

Finds the index of the last set bit.
If no bits are set, returns null.

#### `toggleFirstSet`

```zig
pub fn toggleFirstSet(self: *Self) ?usize
```

Finds the index of the first set bit, and unsets it.
If no bits are set, returns null.

#### `eql`

```zig
pub fn eql(self: Self, other: Self) bool
```

Returns true iff every corresponding bit in both
bit sets are the same.

#### `subsetOf`

```zig
pub fn subsetOf(self: Self, other: Self) bool
```

Returns true iff the first bit set is the subset
of the second one.

#### `supersetOf`

```zig
pub fn supersetOf(self: Self, other: Self) bool
```

Returns true iff the first bit set is the superset
of the second one.

#### `complement`

```zig
pub fn complement(self: Self) Self
```

Returns the complement bit sets. Bits in the result
are set if the corresponding bits were not set.

#### `unionWith`

```zig
pub fn unionWith(self: Self, other: Self) Self
```

Returns the union of two bit sets. Bits in the
result are set if the corresponding bits were set
in either input.

#### `intersectWith`

```zig
pub fn intersectWith(self: Self, other: Self) Self
```

Returns the intersection of two bit sets. Bits in
the result are set if the corresponding bits were
set in both inputs.

#### `xorWith`

```zig
pub fn xorWith(self: Self, other: Self) Self
```

Returns the xor of two bit sets. Bits in the
result are set if the corresponding bits were
not the same in both inputs.

#### `differenceWith`

```zig
pub fn differenceWith(self: Self, other: Self) Self
```

Returns the difference of two bit sets. Bits in
the result are set if set in the first but not
set in the second set.

#### `iterator`

```zig
pub fn iterator(self: *const Self, comptime options: IteratorOptions) Iterator(options)
```

Iterates through the items in the set, according to the options.
The default options (.{}) will iterate indices of set bits in
ascending order.  Modifications to the underlying bit set may
or may not be observed by the iterator.

### Constants & Variables

- **`bit_length`**: The number of items in this bit set
- **`MaskInt`**: The integer type used to represent a mask in this bit set
- **`last_item_mask`**: 
- **`empty`**: A bit set with no elements present.
- **`full`**: A bit set with all elements present.

### `Dynamic`

A bit set with runtime-known size, backed by an allocated slice
of usize.  The allocator must be tracked externally by the user.

### Fields

- `bit_length: usize = 0`
  The number of valid items in this bit set
- `masks: [*]MaskInt = empty_masks_ptr`
  The bit masks, ordered with lower indices first.
  Padding bits at the end must be zeroed.

### Types

#### `MaskInt`

The integer type used to represent a mask in this bit set

#### `ShiftInt`

The integer type used to shift a mask in this bit set

#### `Iterator`

```zig
pub fn Iterator(comptime options: IteratorOptions) type
```


### Functions

#### `initEmpty`

```zig
pub fn initEmpty(allocator: Allocator, bit_length: usize) !Self
```

Creates a bit set with no elements present.
If bit_length is not zero, deinit must eventually be called.

#### `initFull`

```zig
pub fn initFull(allocator: Allocator, bit_length: usize) !Self
```

Creates a bit set with all elements present.
If bit_length is not zero, deinit must eventually be called.

#### `resize`

```zig
pub fn resize(self: *@This(), allocator: Allocator, new_len: usize, fill: bool) !void
```

Resizes to a new bit_length.  If the new length is larger
than the old length, fills any added bits with `fill`.
If new_len is not zero, deinit must eventually be called.

#### `deinit`

```zig
pub fn deinit(self: *Self, allocator: Allocator) void
```

Deinitializes the array and releases its memory.
The passed allocator must be the same one used for
init* or resize in the past.

#### `clone`

```zig
pub fn clone(self: *const Self, new_allocator: Allocator) !Self
```

Creates a duplicate of this bit set, using the new allocator.

#### `capacity`

```zig
pub inline fn capacity(self: Self) usize
```

Returns the number of bits in this bit set

#### `isSet`

```zig
pub fn isSet(self: Self, index: usize) bool
```

Returns true if the bit at the specified index
is present in the set, false otherwise.

#### `count`

```zig
pub fn count(self: Self) usize
```

Returns the total number of set bits in this bit set.

#### `setValue`

```zig
pub fn setValue(self: *Self, index: usize, value: bool) void
```

Changes the value of the specified bit of the bit
set to match the passed boolean.

#### `set`

```zig
pub fn set(self: *Self, index: usize) void
```

Adds a specific bit to the bit set

#### `setRangeValue`

```zig
pub fn setRangeValue(self: *Self, range: Range, value: bool) void
```

Changes the value of all bits in the specified range to
match the passed boolean.

#### `unset`

```zig
pub fn unset(self: *Self, index: usize) void
```

Removes a specific bit from the bit set

#### `unsetAll`

```zig
pub fn unsetAll(self: *Self) void
```

Set all bits to 0.

#### `setAll`

```zig
pub fn setAll(self: *Self) void
```

Set all bits to 1.

#### `toggle`

```zig
pub fn toggle(self: *Self, index: usize) void
```

Flips a specific bit in the bit set

#### `toggleSet`

```zig
pub fn toggleSet(self: *Self, toggles: Self) void
```

Flips all bits in this bit set which are present
in the toggles bit set.  Both sets must have the
same bit_length.

#### `toggleAll`

```zig
pub fn toggleAll(self: *Self) void
```

Flips every bit in the bit set.

#### `setUnion`

```zig
pub fn setUnion(self: *Self, other: Self) void
```

Performs a union of two bit sets, and stores the
result in the first one.  Bits in the result are
set if the corresponding bits were set in either input.
The two sets must both be the same bit_length.

#### `setIntersection`

```zig
pub fn setIntersection(self: *Self, other: Self) void
```

Performs an intersection of two bit sets, and stores
the result in the first one.  Bits in the result are
set if the corresponding bits were set in both inputs.
The two sets must both be the same bit_length.

#### `findFirstSet`

```zig
pub fn findFirstSet(self: Self) ?usize
```

Finds the index of the first set bit.
If no bits are set, returns null.

#### `findLastSet`

```zig
pub fn findLastSet(self: Self) ?usize
```

Finds the index of the last set bit.
If no bits are set, returns null.

#### `toggleFirstSet`

```zig
pub fn toggleFirstSet(self: *Self) ?usize
```

Finds the index of the first set bit, and unsets it.
If no bits are set, returns null.

#### `eql`

```zig
pub fn eql(self: Self, other: Self) bool
```

Returns true iff every corresponding bit in both
bit sets are the same.

#### `subsetOf`

```zig
pub fn subsetOf(self: Self, other: Self) bool
```

Returns true iff the first bit set is the subset
of the second one.

#### `supersetOf`

```zig
pub fn supersetOf(self: Self, other: Self) bool
```

Returns true iff the first bit set is the superset
of the second one.

#### `iterator`

```zig
pub fn iterator(self: *const Self, comptime options: IteratorOptions) Iterator(options)
```

Iterates through the items in the set, according to the options.
The default options (.{}) will iterate indices of set bits in
ascending order.  Modifications to the underlying bit set may
or may not be observed by the iterator.  Resizing the underlying
bit set invalidates the iterator.

### `DynamicManaged`

A bit set with runtime-known size, backed by an allocated slice
of usize.  Thin wrapper around Dynamic which keeps
track of the allocator instance.

Deprecated in favor of `Dynamic` which accepts an `Allocator`
as a parameter when needed instead of storing it.

### Fields

- `allocator: Allocator`
  
- `unmanaged: Dynamic = .{}`
  

### Types

#### `MaskInt`

The integer type used to represent a mask in this bit set

#### `ShiftInt`

The integer type used to shift a mask in this bit set

### Functions

#### `initEmpty`

```zig
pub fn initEmpty(allocator: Allocator, bit_length: usize) !Self
```

Creates a bit set with no elements present.

#### `initFull`

```zig
pub fn initFull(allocator: Allocator, bit_length: usize) !Self
```

Creates a bit set with all elements present.

#### `resize`

```zig
pub fn resize(self: *@This(), new_len: usize, fill: bool) !void
```

Resizes to a new length.  If the new length is larger
than the old length, fills any added bits with `fill`.

#### `deinit`

```zig
pub fn deinit(self: *Self) void
```

Deinitializes the array and releases its memory.
The passed allocator must be the same one used for
init* or resize in the past.

#### `clone`

```zig
pub fn clone(self: *const Self, new_allocator: Allocator) !Self
```

Creates a duplicate of this bit set, using the new allocator.

#### `capacity`

```zig
pub inline fn capacity(self: Self) usize
```

Returns the number of bits in this bit set

#### `isSet`

```zig
pub fn isSet(self: Self, index: usize) bool
```

Returns true if the bit at the specified index
is present in the set, false otherwise.

#### `count`

```zig
pub fn count(self: Self) usize
```

Returns the total number of set bits in this bit set.

#### `setValue`

```zig
pub fn setValue(self: *Self, index: usize, value: bool) void
```

Changes the value of the specified bit of the bit
set to match the passed boolean.

#### `set`

```zig
pub fn set(self: *Self, index: usize) void
```

Adds a specific bit to the bit set

#### `setRangeValue`

```zig
pub fn setRangeValue(self: *Self, range: Range, value: bool) void
```

Changes the value of all bits in the specified range to
match the passed boolean.

#### `unset`

```zig
pub fn unset(self: *Self, index: usize) void
```

Removes a specific bit from the bit set

#### `toggle`

```zig
pub fn toggle(self: *Self, index: usize) void
```

Flips a specific bit in the bit set

#### `toggleSet`

```zig
pub fn toggleSet(self: *Self, toggles: Self) void
```

Flips all bits in this bit set which are present
in the toggles bit set.  Both sets must have the
same bit_length.

#### `toggleAll`

```zig
pub fn toggleAll(self: *Self) void
```

Flips every bit in the bit set.

#### `setUnion`

```zig
pub fn setUnion(self: *Self, other: Self) void
```

Performs a union of two bit sets, and stores the
result in the first one.  Bits in the result are
set if the corresponding bits were set in either input.
The two sets must both be the same bit_length.

#### `setIntersection`

```zig
pub fn setIntersection(self: *Self, other: Self) void
```

Performs an intersection of two bit sets, and stores
the result in the first one.  Bits in the result are
set if the corresponding bits were set in both inputs.
The two sets must both be the same bit_length.

#### `unsetAll`

```zig
pub fn unsetAll(self: *Self) void
```

Set all bits to 0.

#### `setAll`

```zig
pub fn setAll(self: *Self) void
```

Set all bits to 1.

#### `findFirstSet`

```zig
pub fn findFirstSet(self: Self) ?usize
```

Finds the index of the first set bit.
If no bits are set, returns null.

#### `findLastSet`

```zig
pub fn findLastSet(self: Self) ?usize
```

Finds the index of the last set bit.
If no bits are set, returns null.

#### `toggleFirstSet`

```zig
pub fn toggleFirstSet(self: *Self) ?usize
```

Finds the index of the first set bit, and unsets it.
If no bits are set, returns null.

#### `eql`

```zig
pub fn eql(self: Self, other: Self) bool
```

Returns true iff every corresponding bit in both
bit sets are the same.

#### `iterator`

```zig
pub fn iterator(self: *const Self, comptime options: IteratorOptions) Iterator(options)
```

Iterates through the items in the set, according to the options.
The default options (.{}) will iterate indices of set bits in
ascending order.  Modifications to the underlying bit set may
or may not be observed by the iterator.  Resizing the underlying
bit set invalidates the iterator.

### Constants & Variables

- **`Iterator`**: 

### `IteratorOptions`

Options for configuring an iterator over a bit set

### Fields

- `kind: Type = .set`
  determines which bits should be visited
- `direction: Direction = .forward`
  determines the order in which bit indices should be visited

### Types

#### `Type`


#### `Direction`


### `Range`

A range of indices within a bitset.

### Fields

- `start: usize`
  The index of the first bit of interest.
- `end: usize`
  The index immediately after the last bit of interest.

## Constants & Variables

- **`StaticBitSet`**: Deprecated: use `Static`.
- **`IntegerBitSet`**: Deprecated: use `Integer`.
- **`ArrayBitSet`**: Deprecated: use `Array`.
- **`DynamicBitSetUnmanaged`**: Deprecated: use `Dynamic`.
- **`DynamicBitSet`**: Deprecated: use `DynamicManaged` or `Dynamic` (will need to update callsites).

