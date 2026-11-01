# `std.enums`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/enums.zig`  
> [← Back to Standard Library Index](README.md)

This module contains utilities and data structures for working with enums.

## Types

### `EnumFieldStruct`

```zig
pub fn EnumFieldStruct(comptime E: type, comptime Data: type, comptime field_default: ?Data) type
```

Returns a struct with a field matching each unique named enum element.
If the enum is extern and has multiple names for the same value, only
the first name is used.  Each field is of type Data and has the provided
default, which may be undefined.

### `EnumSet`

```zig
pub fn EnumSet(comptime E: type) type
```

A set of enum elements, backed by a bitfield.  If the enum
is exhaustive but not dense, a mapping will be constructed from enum values
to dense indices.  This type does no dynamic allocation and
can be copied by value.

### Fields

- `bits: BitSet = .empty`
  

### Types

#### `Indexer`

The indexing rules for converting between keys and indices.

#### `Iterator`


### Functions

#### `init`

```zig
pub fn init(init_values: EnumFieldStruct(E, bool, false)) Self
```

Initializes the set using a struct of bools

#### `initMany`

```zig
pub fn initMany(keys: []const Key) Self
```

Returns a set containing multiple keys.

#### `initOne`

```zig
pub fn initOne(key: Key) Self
```

Returns a set containing a single key.

#### `count`

```zig
pub fn count(self: Self) usize
```

Returns the number of keys in the set.

#### `contains`

```zig
pub fn contains(self: Self, key: Key) bool
```

Checks if a key is in the set.

#### `insert`

```zig
pub fn insert(self: *Self, key: Key) void
```

Puts a key in the set.

#### `remove`

```zig
pub fn remove(self: *Self, key: Key) void
```

Removes a key from the set.

#### `setPresent`

```zig
pub fn setPresent(self: *Self, key: Key, present: bool) void
```

Changes the presence of a key in the set to match the passed bool.

#### `toggle`

```zig
pub fn toggle(self: *Self, key: Key) void
```

Toggles the presence of a key in the set.  If the key is in
the set, removes it.  Otherwise adds it.

#### `toggleSet`

```zig
pub fn toggleSet(self: *Self, other: Self) void
```

Toggles the presence of all keys in the passed set.

#### `toggleAll`

```zig
pub fn toggleAll(self: *Self) void
```

Toggles all possible keys in the set.

#### `setUnion`

```zig
pub fn setUnion(self: *Self, other: Self) void
```

Adds all keys in the passed set to this set.

#### `setIntersection`

```zig
pub fn setIntersection(self: *Self, other: Self) void
```

Removes all keys which are not in the passed set.

#### `eql`

```zig
pub fn eql(self: Self, other: Self) bool
```

Returns true iff both sets have the same keys.

#### `subsetOf`

```zig
pub fn subsetOf(self: Self, other: Self) bool
```

Returns true iff all the keys in this set are
in the other set. The other set may have keys
not found in this set.

#### `supersetOf`

```zig
pub fn supersetOf(self: Self, other: Self) bool
```

Returns true iff this set contains all the keys
in the other set. This set may have keys not
found in the other set.

#### `complement`

```zig
pub fn complement(self: Self) Self
```

Returns a set with all the keys not in this set.

#### `unionWith`

```zig
pub fn unionWith(self: Self, other: Self) Self
```

Returns a set with keys that are in either this
set or the other set.

#### `intersectWith`

```zig
pub fn intersectWith(self: Self, other: Self) Self
```

Returns a set with keys that are in both this
set and the other set.

#### `xorWith`

```zig
pub fn xorWith(self: Self, other: Self) Self
```

Returns a set with keys that are in either this
set or the other set, but not both.

#### `differenceWith`

```zig
pub fn differenceWith(self: Self, other: Self) Self
```

Returns a set with keys that are in this set
except for keys in the other set.

#### `iterator`

```zig
pub fn iterator(self: *const Self) Iterator
```

Returns an iterator over this set, which iterates in
index order.  Modifications to the set during iteration
may or may not be observed by the iterator, but will
not invalidate it.

### Constants & Variables

- **`Key`**: The element type for this set.
- **`len`**: The maximum number of items in this set.
- **`empty`**: A set containing no keys.
- **`full`**: A set containing all possible keys.

### `EnumMap`

```zig
pub fn EnumMap(comptime E: type, comptime V: type) type
```

A map keyed by an enum, backed by a bitfield and a dense array.
If the enum is exhaustive but not dense, a mapping will be constructed from
enum values to dense indices.  This type does no dynamic
allocation and can be copied by value.

Default initialization is deprecated; use .empty instead.

### Fields

- `bits: BitSet = .empty`
  Bits determining whether items are in the map
- `values: [Indexer.count]Value = undefined`
  Values of items in the map.  If the associated
  bit is zero, the value is undefined.

### Types

#### `Indexer`

The index mapping for this map

#### `Entry`

An entry in the map.

#### `Iterator`


### Functions

#### `init`

```zig
pub fn init(init_values: EnumFieldStruct(E, ?Value, @as(?Value, null))) Self
```

Initializes the map using a sparse struct of optionals

#### `initFull`

```zig
pub fn initFull(value: Value) Self
```

Initializes a full mapping with all keys set to value.
Consider using EnumArray instead if the map will remain full.

#### `initFullWith`

```zig
pub fn initFullWith(init_values: EnumFieldStruct(E, Value, null)) Self
```

Initializes a full mapping with supplied values.
Consider using EnumArray instead if the map will remain full.

#### `initFullWithDefault`

```zig
pub fn initFullWithDefault(comptime default: ?Value, init_values: EnumFieldStruct(E, Value, default)) Self
```

Initializes a full mapping with a provided default.
Consider using EnumArray instead if the map will remain full.

#### `count`

```zig
pub fn count(self: *const Self) usize
```

The number of items in the map.

#### `contains`

```zig
pub fn contains(self: *const Self, key: Key) bool
```

Checks if the map contains an item.

#### `get`

```zig
pub fn get(self: *const Self, key: Key) ?Value
```

Gets the value associated with a key.
If the key is not in the map, returns null.

#### `getAssertContains`

```zig
pub fn getAssertContains(self: *const Self, key: Key) Value
```

Gets the value associated with a key, which must
exist in the map.

#### `getPtr`

```zig
pub fn getPtr(self: *Self, key: Key) ?*Value
```

Gets the address of the value associated with a key.
If the key is not in the map, returns null.

#### `getPtrConst`

```zig
pub fn getPtrConst(self: *const Self, key: Key) ?*const Value
```

Gets the address of the const value associated with a key.
If the key is not in the map, returns null.

#### `getPtrAssertContains`

```zig
pub fn getPtrAssertContains(self: *Self, key: Key) *Value
```

Gets the address of the value associated with a key.
The key must be present in the map.

#### `getPtrConstAssertContains`

```zig
pub fn getPtrConstAssertContains(self: *const Self, key: Key) *const Value
```

Gets the address of the const value associated with a key.
The key must be present in the map.

#### `put`

```zig
pub fn put(self: *Self, key: Key, value: Value) void
```

Adds the key to the map with the supplied value.
If the key is already in the map, overwrites the value.

#### `putUninitialized`

```zig
pub fn putUninitialized(self: *Self, key: Key) *Value
```

Adds the key to the map with an undefined value.
If the key is already in the map, the value becomes undefined.
A pointer to the value is returned, which should be
used to initialize the value.

#### `fetchPut`

```zig
pub fn fetchPut(self: *Self, key: Key, value: Value) ?Value
```

Sets the value associated with the key in the map,
and returns the old value.  If the key was not in
the map, returns null.

#### `remove`

```zig
pub fn remove(self: *Self, key: Key) void
```

Removes a key from the map.  If the key was not in the map,
does nothing.

#### `fetchRemove`

```zig
pub fn fetchRemove(self: *Self, key: Key) ?Value
```

Removes a key from the map, and returns the old value.
If the key was not in the map, returns null.

#### `iterator`

```zig
pub fn iterator(self: *Self) Iterator
```

Returns an iterator over the map, which visits items in index order.
Modifications to the underlying map may or may not be observed by
the iterator, but will not invalidate it.

### Constants & Variables

- **`Key`**: The key type used to index this map
- **`Value`**: The value type stored in this map
- **`len`**: The number of possible keys in the map
- **`empty`**: 

### `EnumMultiset`

```zig
pub fn EnumMultiset(comptime E: type) type
```

A multiset of enum elements up to a count of usize. Backed
by an EnumArray. This type does no dynamic allocation and can
be copied by value.

### `BoundedEnumMultiset`

```zig
pub fn BoundedEnumMultiset(comptime E: type, comptime CountSize: type) type
```

A multiset of enum elements up to CountSize. Backed by an
EnumArray. This type does no dynamic allocation and can be
copied by value.

### Fields

- `counts: EnumArray(E, CountSize)`
  

### Functions

#### `init`

```zig
pub fn init(init_counts: EnumFieldStruct(E, CountSize, 0)) Self
```

Initializes the multiset using a struct of counts.

#### `initWithCount`

```zig
pub fn initWithCount(comptime c: CountSize) Self
```

Initializes the multiset with all keys at the
same count.

#### `count`

```zig
pub fn count(self: Self) usize
```

Returns the total number of key counts in the multiset.

#### `contains`

```zig
pub fn contains(self: Self, key: E) bool
```

Checks if at least one key in multiset.

#### `removeAll`

```zig
pub fn removeAll(self: *Self, key: E) void
```

Removes all instance of a key from multiset. Same as
setCount(key, 0).

#### `addAssertSafe`

```zig
pub fn addAssertSafe(self: *Self, key: E, c: CountSize) void
```

Increases the key count by given amount. Caller asserts
operation will not overflow.

#### `add`

```zig
pub fn add(self: *Self, key: E, c: CountSize) error{Overflow}!void
```

Increases the key count by given amount.

#### `remove`

```zig
pub fn remove(self: *Self, key: E, c: CountSize) void
```

Decreases the key count by given amount. If amount is
greater than the number of keys in multset, then key count
will be set to zero.

#### `getCount`

```zig
pub fn getCount(self: Self, key: E) CountSize
```

Returns the count for a key.

#### `setCount`

```zig
pub fn setCount(self: *Self, key: E, c: CountSize) void
```

Set the count for a key.

#### `addSetAssertSafe`

```zig
pub fn addSetAssertSafe(self: *Self, other: Self) void
```

Increases the all key counts by given multiset. Caller
asserts operation will not overflow any key.

#### `addSet`

```zig
pub fn addSet(self: *Self, other: Self) error{Overflow}!void
```

Increases the all key counts by given multiset.

#### `removeSet`

```zig
pub fn removeSet(self: *Self, other: Self) void
```

Decreases the all key counts by given multiset. If
the given multiset has more key counts than this,
then that key will have a key count of zero.

#### `eql`

```zig
pub fn eql(self: Self, other: Self) bool
```

Returns true iff all key counts are the same as
given multiset.

#### `subsetOf`

```zig
pub fn subsetOf(self: Self, other: Self) bool
```

Returns true iff all key counts less than or
equal to the given multiset.

#### `supersetOf`

```zig
pub fn supersetOf(self: Self, other: Self) bool
```

Returns true iff all key counts greater than or
equal to the given multiset.

#### `plusAssertSafe`

```zig
pub fn plusAssertSafe(self: Self, other: Self) Self
```

Returns a multiset with the total key count of this
multiset and the other multiset. Caller asserts
operation will not overflow any key.

#### `plus`

```zig
pub fn plus(self: Self, other: Self) error{Overflow}!Self
```

Returns a multiset with the total key count of this
multiset and the other multiset.

#### `minus`

```zig
pub fn minus(self: Self, other: Self) Self
```

Returns a multiset with the key count of this
multiset minus the corresponding key count in the
other multiset. If the other multiset contains
more key count than this set, that key will have
a count of zero.

#### `iterator`

```zig
pub fn iterator(self: *Self) Iterator
```

Returns an iterator over this multiset. Keys with zero
counts are included. Modifications to the set during
iteration may or may not be observed by the iterator,
but will not invalidate it.

### Constants & Variables

- **`empty`**: A multiset with a count of zero.
- **`Entry`**: 
- **`Iterator`**: 

### `EnumArray`

```zig
pub fn EnumArray(comptime E: type, comptime V: type) type
```

An array keyed by an enum, backed by a dense array.
If the enum is not dense, a mapping will be constructed from
enum values to dense indices.  This type does no dynamic
allocation and can be copied by value.

### Fields

- `values: [Indexer.count]Value`
  

### Types

#### `Indexer`

The index mapping for this map

#### `Entry`

An entry in the array.

#### `Iterator`


### Functions

#### `init`

```zig
pub fn init(init_values: EnumFieldStruct(E, Value, null)) Self
```


#### `initDefault`

```zig
pub fn initDefault(comptime default: ?Value, init_values: EnumFieldStruct(E, Value, default)) Self
```

Initializes values in the enum array, with the specified default.

#### `initUndefined`

```zig
pub fn initUndefined() Self
```


#### `initFill`

```zig
pub fn initFill(v: Value) Self
```


#### `get`

```zig
pub fn get(self: Self, key: Key) Value
```

Returns the value in the array associated with a key.

#### `getPtr`

```zig
pub fn getPtr(self: *Self, key: Key) *Value
```

Returns a pointer to the slot in the array associated with a key.

#### `getPtrConst`

```zig
pub fn getPtrConst(self: *const Self, key: Key) *const Value
```

Returns a const pointer to the slot in the array associated with a key.

#### `set`

```zig
pub fn set(self: *Self, key: Key, value: Value) void
```

Sets the value in the slot associated with a key.

#### `iterator`

```zig
pub fn iterator(self: *Self) Iterator
```

Iterates over the items in the array, in index order.

### Constants & Variables

- **`Key`**: The key type used to index this map
- **`Value`**: The value type stored in this map
- **`len`**: The number of possible keys in the map

### `EnumIndexer`

```zig
pub fn EnumIndexer(comptime E: type) type
```


### Functions

#### `indexOf`

```zig
pub fn indexOf(e: E) usize
```


#### `keyForIndex`

```zig
pub fn keyForIndex(i: usize) E
```


#### `indexOf`

```zig
pub fn indexOf(e: E) usize
```


#### `keyForIndex`

```zig
pub fn keyForIndex(i: usize) E
```


#### `indexOf`

```zig
pub fn indexOf(e: E) usize
```


#### `keyForIndex`

```zig
pub fn keyForIndex(i: usize) E
```


#### `indexOf`

```zig
pub fn indexOf(e: E) usize
```


#### `keyForIndex`

```zig
pub fn keyForIndex(i: usize) E
```


### Constants & Variables

- **`Key`**: 
- **`count`**: 
- **`Key`**: 
- **`count`**: 
- **`Key`**: 
- **`count`**: 
- **`Key`**: 
- **`count`**: 

## Functions

### `fromInt`

```zig
pub fn fromInt(comptime E: type, integer: anytype) ?E
```


### `valuesFromFields`

```zig
pub inline fn valuesFromFields(comptime E: type, comptime field_values: []const comptime_int) []const E
```

Looks up the supplied field values in the given enum type.
The result array is in the same order as the input.

### `values`

```zig
pub inline fn values(comptime E: type) []const E
```

Returns the set of all named values in the given enum, in
declaration order.

### `tagName`

```zig
pub fn tagName(comptime E: type, e: E) ?[:0]const u8
```

A safe alternative to @tagName() for non-exhaustive enums that doesn't
panic when `e` has no tagged value.
Returns the tag name for `e` or null if no tag exists.

### `directEnumArrayLen`

```zig
pub fn directEnumArrayLen(comptime E: type, comptime max_unused_slots: comptime_int) comptime_int
```

Determines the length of a direct-mapped enum array, indexed by
@intCast(usize, @intFromEnum(enum_value)).
If the enum is non-exhaustive, the resulting length will only be enough
to hold all explicit fields.
If the enum contains any fields with values that cannot be represented
by usize, a compile error is issued.  The max_unused_slots parameter limits
the total number of items which have no matching enum key (holes in the enum
numbering).  So for example, if an enum has values 1, 2, 5, and 6, max_unused_slots
must be at least 3, to allow unused slots 0, 3, and 4.

### `directEnumArray`

```zig
pub fn directEnumArray(comptime E: type, comptime Data: type, comptime max_unused_slots: comptime_int, init_values: EnumFieldStruct(E, Data, null), ) [directEnumArrayLen(E, max_unused_slots)]Data
```

Initializes an array of Data which can be indexed by
@intCast(usize, @intFromEnum(enum_value)).
If the enum is non-exhaustive, the resulting array will only be large enough
to hold all explicit fields.
If the enum contains any fields with values that cannot be represented
by usize, a compile error is issued.  The max_unused_slots parameter limits
the total number of items which have no matching enum key (holes in the enum
numbering).  So for example, if an enum has values 1, 2, 5, and 6, max_unused_slots
must be at least 3, to allow unused slots 0, 3, and 4.
The init_values parameter must be a struct with field names that match the enum values.
If the enum has multiple fields with the same value, the name of the first one must
be used.

### `directEnumArrayDefault`

```zig
pub fn directEnumArrayDefault(comptime E: type, comptime Data: type, comptime default: ?Data, comptime max_unused_slots: comptime_int, init_values: EnumFieldStruct(E, Data, default), ) [directEnumArrayLen(E, max_unused_slots)]Data
```

Initializes an array of Data which can be indexed by
@intCast(usize, @intFromEnum(enum_value)).  The enum must be exhaustive.
If the enum contains any fields with values that cannot be represented
by usize, a compile error is issued.  The max_unused_slots parameter limits
the total number of items which have no matching enum key (holes in the enum
numbering).  So for example, if an enum has values 1, 2, 5, and 6, max_unused_slots
must be at least 3, to allow unused slots 0, 3, and 4.
The init_values parameter must be a struct with field names that match the enum values.
If the enum has multiple fields with the same value, the name of the first one must
be used.

