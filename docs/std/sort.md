# `std.sort`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/sort.zig`  
> [← Back to Standard Library Index](README.md)

## Types

### `Mode`


### Fields

- `stable`
  
- `unstable`
  

### `equalRange`

```zig
pub fn equalRange(comptime T: type, items: []const T, context: anytype, comptime compareFn: fn (@TypeOf(context), T) std.math.Order, ) struct { usize, usize }
```

Returns a tuple of the lower and upper indices in `items` between which all
elements return `.eq` when given to `compareFn`.
If no element in `items` returns `.eq`, both indices are the index of the
first element in `items` which returns `.gt`, or if no element returns `.gt`,
both indices are `items.len`.

`items` must be sorted in ascending order with respect to `compareFn`:
```
[0]                                                   [len]
┌───┬───┬─/ /─┬───┬───┬───┬─/ /─┬───┬───┬───┬─/ /─┬───┐
│.lt│.lt│ \ \ │.lt│.eq│.eq│ \ \ │.eq│.gt│.gt│ \ \ │.gt│
└───┴───┴─/ /─┴───┴───┴───┴─/ /─┴───┴───┴───┴─/ /─┴───┘
├─────────────────┼─────────────────┼─────────────────┤
 ↳ zero or more    ↳ zero or more    ↳ zero or more
                  ├─────────────────┤
                   ↳ returned range
```

`O(log n)` time complexity.

See also: `binarySearch`, `lowerBound, `upperBound`, `partitionPoint`.

## Functions

### `insertion`

```zig
pub fn insertion(comptime T: type, items: []T, context: anytype, comptime lessThanFn: fn (@TypeOf(context), lhs: T, rhs: T) bool, ) void
```

Stable in-place sort. O(n) best case, O(pow(n, 2)) worst case.
O(1) memory (no allocator required).
Sorts in ascending order with respect to the given `lessThan` function.

### `insertionContext`

```zig
pub fn insertionContext(a: usize, b: usize, context: anytype) void
```

Stable in-place sort. O(n) best case, O(pow(n, 2)) worst case.
O(1) memory (no allocator required).
`context` must have methods `swap` and `lessThan`,
which each take 2 `usize` parameters indicating the index of an item.
Sorts in ascending order with respect to `lessThan`.

### `heap`

```zig
pub fn heap(comptime T: type, items: []T, context: anytype, comptime lessThanFn: fn (@TypeOf(context), lhs: T, rhs: T) bool, ) void
```

Unstable in-place sort. O(n*log(n)) best case, worst case and average case.
O(1) memory (no allocator required).
Sorts in ascending order with respect to the given `lessThan` function.

### `heapContext`

```zig
pub fn heapContext(a: usize, b: usize, context: anytype) void
```

Unstable in-place sort. O(n*log(n)) best case, worst case and average case.
O(1) memory (no allocator required).
`context` must have methods `swap` and `lessThan`,
which each take 2 `usize` parameters indicating the index of an item.
Sorts in ascending order with respect to `lessThan`.

### `asc`

```zig
pub fn asc(comptime T: type) fn (void, T, T) bool
```

Use to generate a comparator function for a given type. e.g. `sort(u8, slice, {}, asc(u8))`.

### `desc`

```zig
pub fn desc(comptime T: type) fn (void, T, T) bool
```

Use to generate a comparator function for a given type. e.g. `sort(u8, slice, {}, desc(u8))`.

### `lessThan`

```zig
pub fn lessThan(ctx: @This(), a: usize, b: usize) bool
```


### `swap`

```zig
pub fn swap(ctx: @This(), a: usize, b: usize) void
```


### `binarySearch`

```zig
pub fn binarySearch(comptime T: type, items: []const T, context: anytype, comptime compareFn: fn (@TypeOf(context), T) std.math.Order, ) ?usize
```

Returns the index of an element in `items` returning `.eq` when given to `compareFn`.
- If there are multiple such elements, returns the index of any one of them.
- If there are no such elements, returns `null`.

`items` must be sorted in ascending order with respect to `compareFn`:
```
[0]                                                   [len]
┌───┬───┬─/ /─┬───┬───┬───┬─/ /─┬───┬───┬───┬─/ /─┬───┐
│.lt│.lt│ \ \ │.lt│.eq│.eq│ \ \ │.eq│.gt│.gt│ \ \ │.gt│
└───┴───┴─/ /─┴───┴───┴───┴─/ /─┴───┴───┴───┴─/ /─┴───┘
├─────────────────┼─────────────────┼─────────────────┤
 ↳ zero or more    ↳ zero or more    ↳ zero or more
                  ├─────────────────┤
                   ↳ if not null, returned
                     index is in this range
```

`O(log n)` time complexity.

See also: `lowerBound, `upperBound`, `partitionPoint`, `equalRange`.

### `lowerBound`

```zig
pub fn lowerBound(comptime T: type, items: []const T, context: anytype, comptime compareFn: fn (@TypeOf(context), T) std.math.Order, ) usize
```

Returns the index of the first element in `items` that is greater than or equal to `context`,
as determined by `compareFn`. If no such element exists, returns `items.len`.

`items` must be sorted in ascending order with respect to `compareFn`:
```
[0]                                                   [len]
┌───┬───┬─/ /─┬───┬───┬───┬─/ /─┬───┬───┬───┬─/ /─┬───┐
│.lt│.lt│ \ \ │.lt│.eq│.eq│ \ \ │.eq│.gt│.gt│ \ \ │.gt│
└───┴───┴─/ /─┴───┴───┴───┴─/ /─┴───┴───┴───┴─/ /─┴───┘
├─────────────────┼─────────────────┼─────────────────┤
 ↳ zero or more    ↳ zero or more    ↳ zero or more
                  ├───┤
                   ↳ returned index
```

`O(log n)` time complexity.

See also: `binarySearch`, `upperBound`, `partitionPoint`, `equalRange`.

### `upperBound`

```zig
pub fn upperBound(comptime T: type, items: []const T, context: anytype, comptime compareFn: fn (@TypeOf(context), T) std.math.Order, ) usize
```

Returns the index of the first element in `items` that is greater than `context`, as determined
by `compareFn`. If no such element exists, returns `items.len`.

`items` must be sorted in ascending order with respect to `compareFn`:
```
[0]                                                   [len]
┌───┬───┬─/ /─┬───┬───┬───┬─/ /─┬───┬───┬───┬─/ /─┬───┐
│.lt│.lt│ \ \ │.lt│.eq│.eq│ \ \ │.eq│.gt│.gt│ \ \ │.gt│
└───┴───┴─/ /─┴───┴───┴───┴─/ /─┴───┴───┴───┴─/ /─┴───┘
├─────────────────┼─────────────────┼─────────────────┤
 ↳ zero or more    ↳ zero or more    ↳ zero or more
                                    ├───┤
                                     ↳ returned index
```

`O(log n)` time complexity.

See also: `binarySearch`, `lowerBound`, `partitionPoint`, `equalRange`.

### `partitionPoint`

```zig
pub fn partitionPoint(comptime T: type, items: []const T, context: anytype, comptime predicate: fn (@TypeOf(context), T) bool, ) usize
```

Returns the index of the partition point of `items` in relation to the given predicate.
- If all elements of `items` satisfy the predicate the returned value is `items.len`.

`items` must contain a prefix for which all elements satisfy the predicate,
and beyond which none of the elements satisfy the predicate:
```
[0]                                          [len]
┌────┬────┬─/ /─┬────┬─────┬─────┬─/ /─┬─────┐
│true│true│ \ \ │true│false│false│ \ \ │false│
└────┴────┴─/ /─┴────┴─────┴─────┴─/ /─┴─────┘
├────────────────────┼───────────────────────┤
 ↳ zero or more       ↳ zero or more
                     ├─────┤
                      ↳ returned index
```

`O(log n)` time complexity.

See also: `binarySearch`, `lowerBound, `upperBound`, `equalRange`.

### `argMin`

```zig
pub fn argMin(comptime T: type, items: []const T, context: anytype, comptime lessThan: fn (@TypeOf(context), lhs: T, rhs: T) bool, ) ?usize
```


### `min`

```zig
pub fn min(comptime T: type, items: []const T, context: anytype, comptime lessThan: fn (context: @TypeOf(context), lhs: T, rhs: T) bool, ) ?T
```


### `argMax`

```zig
pub fn argMax(comptime T: type, items: []const T, context: anytype, comptime lessThan: fn (context: @TypeOf(context), lhs: T, rhs: T) bool, ) ?usize
```


### `max`

```zig
pub fn max(comptime T: type, items: []const T, context: anytype, comptime lessThan: fn (context: @TypeOf(context), lhs: T, rhs: T) bool, ) ?T
```


### `isSorted`

```zig
pub fn isSorted(comptime T: type, items: []const T, context: anytype, comptime lessThan: fn (context: @TypeOf(context), lhs: T, rhs: T) bool, ) bool
```


## Constants & Variables

- **`block`**: 
- **`pdq`**: 
- **`pdqContext`**: 

