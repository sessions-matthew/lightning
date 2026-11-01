# `std.mem`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/mem.zig`  
> [← Back to Standard Library Index](README.md)

## Types

### `Alignment`

Stored as a power-of-two.

### Fields

- `@"1" = 0`
  
- `@"2" = 1`
  
- `@"4" = 2`
  
- `@"8" = 3`
  
- `@"16" = 4`
  
- `@"32" = 5`
  
- `@"64" = 6`
  
- `_`
  

### Functions

#### `toByteUnits`

```zig
pub fn toByteUnits(a: Alignment) usize
```


#### `fromByteUnits`

```zig
pub fn fromByteUnits(n: usize) Alignment
```


#### `fromByteUnitsOptional`

```zig
pub fn fromByteUnitsOptional(maybe_n: ?usize) ?Alignment
```


#### `of`

```zig
pub inline fn of(comptime T: type) Alignment
```


#### `order`

```zig
pub fn order(lhs: Alignment, rhs: Alignment) std.math.Order
```


#### `compare`

```zig
pub fn compare(lhs: Alignment, op: std.math.CompareOperator, rhs: Alignment) bool
```


#### `max`

```zig
pub fn max(lhs: Alignment, rhs: Alignment) Alignment
```


#### `min`

```zig
pub fn min(lhs: Alignment, rhs: Alignment) Alignment
```


#### `forward`

```zig
pub fn forward(a: Alignment, address: usize) usize
```

Return next address with this alignment.

#### `backward`

```zig
pub fn backward(a: Alignment, address: usize) usize
```

Return previous address with this alignment.

#### `check`

```zig
pub fn check(a: Alignment, address: usize) bool
```

Return whether address is aligned to this amount.

### `ValidationAllocator`

```zig
pub fn ValidationAllocator(comptime T: type) type
```

Detects and asserts if the std.mem.Allocator interface is violated by the caller
or the allocator.

### Fields

- `underlying_allocator: T`
  

### Functions

#### `init`

```zig
pub fn init(underlying_allocator: T) @This()
```


#### `allocator`

```zig
pub fn allocator(self: *Self) Allocator
```


#### `alloc`

```zig
pub fn alloc(ctx: *anyopaque, n: usize, alignment: mem.Alignment, ret_addr: usize, ) ?[*]u8
```


#### `resize`

```zig
pub fn resize(ctx: *anyopaque, buf: []u8, alignment: Alignment, new_len: usize, ret_addr: usize, ) bool
```


#### `remap`

```zig
pub fn remap(ctx: *anyopaque, buf: []u8, alignment: Alignment, new_len: usize, ret_addr: usize, ) ?[*]u8
```


#### `free`

```zig
pub fn free(ctx: *anyopaque, buf: []u8, alignment: Alignment, ret_addr: usize, ) void
```


#### `reset`

```zig
pub fn reset(self: *Self) void
```


### `WindowIterator`

```zig
pub fn WindowIterator(comptime T: type) type
```

Iterator type returned by the `window` function for sliding window operations.

### Fields

- `buffer: []const T`
  
- `index: ?usize`
  
- `size: usize`
  
- `advance: usize`
  

### Functions

#### `next`

```zig
pub fn next(self: *Self) ?[]const T
```

Returns a slice of the next window, or null if window is at end.

#### `reset`

```zig
pub fn reset(self: *Self) void
```

Resets the iterator to the initial window.

### `DelimiterType`

Delimiter type for tokenization and splitting operations.

### Fields

- `sequence`
  
- `any`
  
- `scalar`
  

### `TokenIterator`

```zig
pub fn TokenIterator(comptime T: type, comptime delimiter_type: DelimiterType) type
```

Iterator type for tokenization operations, skipping empty sequences and delimiter sequences.

### Fields

- `buffer: []const T`
  
- `delimiter: switch (delimiter_type) { .sequence, .any => []const T, .scalar => T, }`
  
- `index: usize`
  

### Functions

#### `next`

```zig
pub fn next(self: *Self) ?[]const T
```

Returns a slice of the current token, or null if tokenization is
complete, and advances to the next token.

#### `peek`

```zig
pub fn peek(self: *Self) ?[]const T
```

Returns a slice of the current token, or null if tokenization is
complete. Does not advance to the next token.

#### `rest`

```zig
pub fn rest(self: Self) []const T
```

Returns a slice of the remaining bytes. Does not affect iterator state.

#### `reset`

```zig
pub fn reset(self: *Self) void
```

Resets the iterator to the initial token.

### `SplitIterator`

```zig
pub fn SplitIterator(comptime T: type, comptime delimiter_type: DelimiterType) type
```

Iterator type for splitting operations, including empty sequences between delimiters.

### Fields

- `buffer: []const T`
  
- `index: ?usize`
  
- `delimiter: switch (delimiter_type) { .sequence, .any => []const T, .scalar => T, }`
  

### Functions

#### `first`

```zig
pub fn first(self: *Self) []const T
```

Returns a slice of the first field.
Call this only to get the first field and then use `next` to get all subsequent fields.
Asserts that iteration has not begun.

#### `next`

```zig
pub fn next(self: *Self) ?[]const T
```

Returns a slice of the next field, or null if splitting is complete.

#### `peek`

```zig
pub fn peek(self: *const Self) ?[]const T
```

Returns a slice of the next field, or null if splitting is complete.
This method does not alter self.index.

#### `rest`

```zig
pub fn rest(self: Self) []const T
```

Returns a slice of the remaining bytes. Does not affect iterator state.

#### `reset`

```zig
pub fn reset(self: *Self) void
```

Resets the iterator to the initial slice.

### `SplitBackwardsIterator`

```zig
pub fn SplitBackwardsIterator(comptime T: type, comptime delimiter_type: DelimiterType) type
```

Iterator type for splitting operations from the end backwards, including empty sequences.

### Fields

- `buffer: []const T`
  
- `index: ?usize`
  
- `delimiter: switch (delimiter_type) { .sequence, .any => []const T, .scalar => T, }`
  

### Functions

#### `first`

```zig
pub fn first(self: *Self) []const T
```

Returns a slice of the first field.
Call this only to get the first field and then use `next` to get all subsequent fields.
Asserts that iteration has not begun.

#### `next`

```zig
pub fn next(self: *Self) ?[]const T
```

Returns a slice of the next field, or null if splitting is complete.

#### `rest`

```zig
pub fn rest(self: Self) []const T
```

Returns a slice of the remaining bytes. Does not affect iterator state.

#### `reset`

```zig
pub fn reset(self: *Self) void
```

Resets the iterator to the initial slice.

### `minMax`

```zig
pub fn minMax(comptime T: type, slice: []const T) struct { T, T }
```

Finds the smallest and largest number in a slice. O(n).
Returns an anonymous struct with the fields `min` and `max`.
`slice` must not be empty.

### `findMinMax`

```zig
pub fn findMinMax(comptime T: type, slice: []const T) struct { usize, usize }
```

Finds the indices of the smallest and largest number in a slice. O(n).
Returns the indices of the smallest and largest numbers in that order.
`slice` must not be empty.

### `ReverseIterator`

```zig
pub fn ReverseIterator(comptime T: type) type
```

Returned by `reverseIterator`.

### Fields

- `ptr: Pointer`
  
- `index: usize`
  

### Functions

#### `next`

```zig
pub fn next(self: *@This()) ?Element
```


#### `nextPtr`

```zig
pub fn nextPtr(self: *@This()) ?ElementPointer
```


## Functions

### `validationWrap`

```zig
pub fn validationWrap(allocator: anytype) ValidationAllocator(@TypeOf(allocator))
```

Wraps an allocator with basic validation checks.
Asserts that allocation sizes are greater than zero and returned pointers have correct alignment.

### `copyForwards`

```zig
pub fn copyForwards(comptime T: type, dest: []T, source: []const T) void
```

Copy all of source into dest at position 0.
dest.len must be >= source.len.
If the slices overlap, dest.ptr must be <= src.ptr.
This function is deprecated; use @memmove instead.

### `copyBackwards`

```zig
pub fn copyBackwards(comptime T: type, dest: []T, source: []const T) void
```

Copy all of source into dest at position 0.
dest.len must be >= source.len.
If the slices overlap, dest.ptr must be >= src.ptr.
This function is deprecated; use @memmove instead.

### `copySentinel`

```zig
pub fn copySentinel(comptime T: type, comptime s: T, dest: []T, source: [*:s]const T) usize
```

Copy `source` into `dest`, excluding the sentinel.

Asserts no overlap. Asserts `dest.len` greater or equal to source len. Returns number of elements copied,
not counting the sentinel.

### `copySentinelInclusive`

```zig
pub fn copySentinelInclusive(comptime T: type, comptime s: T, dest: []T, source: [*:s]const T) usize
```

Copy `source` into `dest`, including the sentinel.

Asserts no overlap. Asserts `dest.len` greater or equal to source len, including room for the sentinel.
Returns number of elements copied, including the sentinel.

### `zeroes`

```zig
pub fn zeroes(comptime T: type) T
```

Generally, Zig users are encouraged to explicitly initialize all fields of a struct explicitly rather than using this function.
However, it is recognized that there are sometimes use cases for initializing all fields to a "zero" value. For example, when
interfacing with a C API where this practice is more common and relied upon. If you are performing code review and see this
function used, examine closely - it may be a code smell.
Zero initializes the type.
This can be used to zero-initialize any type for which it makes sense. Structs will be initialized recursively.

### `zeroInit`

```zig
pub fn zeroInit(comptime T: type, init: anytype) T
```

Initializes all fields of the struct with their default value, or zero values if no default value is present.
If the field is present in the provided initial values, it will have that value instead.
Structs are initialized recursively.

### `sort`

```zig
pub fn sort(comptime T: type, items: []T, context: anytype, comptime lessThanFn: fn (@TypeOf(context), lhs: T, rhs: T) bool, ) void
```

Sorts a slice in-place using a stable algorithm (maintains relative order of equal elements).
Average time complexity: O(n log n), worst case: O(n log n)
Space complexity: O(log n) for recursive calls

For slice of primitives with default ordering, consider using `std.sort.block` directly.
For unstable but potentially faster sorting, see `sortUnstable`.

### `sortUnstable`

```zig
pub fn sortUnstable(comptime T: type, items: []T, context: anytype, comptime lessThanFn: fn (@TypeOf(context), lhs: T, rhs: T) bool, ) void
```

Sorts a slice in-place using an unstable algorithm (does not preserve relative order of equal elements).
Time complexity: O(n) best case, O(n log n) worst case and average case.
Generally faster than stable sort but order of equal elements is undefined.

Uses pattern-defeating quicksort (PDQ) algorithm which performs well on many data patterns.
For stable sorting that preserves equal element order, use `sort`.

### `sortContext`

```zig
pub fn sortContext(a: usize, b: usize, context: anytype) void
```

TODO: currently this just calls `insertionSortContext`. The block sort implementation
in this file needs to be adapted to use the sort context.

### `sortUnstableContext`

```zig
pub fn sortUnstableContext(a: usize, b: usize, context: anytype) void
```

Sorts a range [a, b) using an unstable algorithm with custom context.
This is a lower-level interface for sorting that works with indices instead of slices.
Does not preserve relative order of equal elements.

The context must provide lessThan(a_idx, b_idx) and swap(a_idx, b_idx) methods.
Uses pattern-defeating quicksort (PDQ) algorithm.

### `order`

```zig
pub fn order(comptime T: type, lhs: []const T, rhs: []const T) math.Order
```

Compares two slices of numbers lexicographically. O(n).

### `orderZ`

```zig
pub fn orderZ(comptime T: type, lhs: [*:0]const T, rhs: [*:0]const T) math.Order
```

Compares two many-item pointers with NUL-termination lexicographically.

### `boundedOrderZ`

```zig
pub fn boundedOrderZ(comptime T: type, lhs: [*:0]const T, rhs: [*:0]const T, bound: usize) math.Order
```

Compares two many-item pointers with NUL-termination lexicographically until some specified bound.

### `lessThan`

```zig
pub fn lessThan(comptime T: type, lhs: []const T, rhs: []const T) bool
```

Returns true if lhs < rhs, false otherwise

### `lessThanZ`

```zig
pub fn lessThanZ(comptime T: type, lhs: [*:0]const T, rhs: [*:0]const T) bool
```

Returns `true` if `lhs < rhs`; `false` otherwise, operating on null-terminated arrays.

### `eql`

```zig
pub fn eql(comptime T: type, a: []const T, b: []const T) bool
```

Returns true if and only if the slices have the same length and all elements
compare true using equality operator.

### `findDiff`

```zig
pub fn findDiff(comptime T: type, a: []const T, b: []const T) ?usize
```

Compares two slices and returns the index of the first inequality.
Returns null if the slices are equal.

### `span`

```zig
pub fn span(ptr: anytype) Span(@TypeOf(ptr))
```

Takes a sentinel-terminated pointer and returns a slice, iterating over the
memory to find the sentinel and determine the length.
Pointer attributes such as const are preserved.
`[*c]` pointers are assumed to be non-null and 0-terminated.

### `sliceTo`

```zig
pub fn sliceTo(ptr: anytype, comptime end: std.meta.Elem(@TypeOf(ptr))) SliceTo(@TypeOf(ptr), end)
```

Takes a pointer to an array, a many-item pointer, or a slice, and returns a
slice of the items up to the first occurrence of `end`.
If `end` is not found, the resulting slice will include all items up to the
input's length or sentinel.
If the pointer type is unbounded (no length or sentinel), `end` will be the
sentinel for the resulting slice.
If the pointer type is sentinel-terminated by `end`, the resulting slice
will also be sentinel-terminated by `end`.
Pointer properties such as mutability and alignment are preserved.
C pointers are assumed to be non-null.

### `len`

```zig
pub fn len(value: anytype) usize
```

Takes a sentinel-terminated pointer and iterates over the memory to find the
sentinel and determine the length.
`[*c]` pointers are assumed to be non-null and 0-terminated.

### `findSentinel`

```zig
pub fn findSentinel(comptime T: type, comptime sentinel: T, p: [*:sentinel]const T) usize
```

Returns the index of the sentinel value in a sentinel-terminated pointer.
Linear search through memory until the sentinel is found.

### `allEqual`

```zig
pub fn allEqual(comptime T: type, slice: []const T, scalar: T) bool
```

Returns true if all elements in a slice are equal to the scalar value provided

### `trimStart`

```zig
pub fn trimStart(comptime T: type, slice: []const T, values_to_strip: []const T) []const T
```

Remove a set of values from the beginning of a slice.

### `trimEnd`

```zig
pub fn trimEnd(comptime T: type, slice: []const T, values_to_strip: []const T) []const T
```

Remove a set of values from the end of a slice.

### `trim`

```zig
pub fn trim(comptime T: type, slice: []const T, values_to_strip: []const T) []const T
```

Remove a set of values from the beginning and end of a slice.

### `findScalar`

```zig
pub fn findScalar(comptime T: type, slice: []const T, value: T) ?usize
```

Linear search for the index of a scalar value inside a slice.

### `findScalarLast`

```zig
pub fn findScalarLast(comptime T: type, slice: []const T, value: T) ?usize
```

Linear search for the last index of a scalar value inside a slice.

### `findScalarPos`

```zig
pub fn findScalarPos(comptime T: type, slice: []const T, start_index: usize, value: T) ?usize
```

Linear search for the index of a scalar value inside a slice, starting from a given position.
Returns null if the value is not found.

### `findAny`

```zig
pub fn findAny(comptime T: type, slice: []const T, values: []const T) ?usize
```

Linear search for the index of any value in the provided list inside a slice.
Returns null if no values are found.

### `findLastAny`

```zig
pub fn findLastAny(comptime T: type, slice: []const T, values: []const T) ?usize
```

Linear search for the last index of any value in the provided list inside a slice.
Returns null if no values are found.

### `findAnyPos`

```zig
pub fn findAnyPos(comptime T: type, slice: []const T, start_index: usize, values: []const T) ?usize
```

Linear search for the index of any value in the provided list inside a slice, starting from a given position.
Returns null if no values are found.

### `findNone`

```zig
pub fn findNone(comptime T: type, slice: []const T, values: []const T) ?usize
```

Find the first item in `slice` which is not contained in `values`.

Comparable to `strspn` in the C standard library.

### `findLastNone`

```zig
pub fn findLastNone(comptime T: type, slice: []const T, values: []const T) ?usize
```

Find the last item in `slice` which is not contained in `values`.

Like `strspn` in the C standard library, but searches from the end.

### `findNonePos`

```zig
pub fn findNonePos(comptime T: type, slice: []const T, start_index: usize, values: []const T) ?usize
```

Find the first item in `slice[start_index..]` which is not contained in `values`.
The returned index will be relative to the start of `slice`, and never less than `start_index`.

Comparable to `strspn` in the C standard library.

### `find`

```zig
pub fn find(comptime T: type, haystack: []const T, needle: []const T) ?usize
```

Search for needle in haystack and return the index of the first occurrence.
Uses Boyer-Moore-Horspool algorithm on large inputs; linear search on small inputs.
Returns null if needle is not found.

### `findLastLinear`

```zig
pub fn findLastLinear(comptime T: type, haystack: []const T, needle: []const T) ?usize
```

Find the index in a slice of a sub-slice, searching from the end backwards.
To start looking at a different index, slice the haystack first.
Consider using `lastIndexOf` instead of this, which will automatically use a
more sophisticated algorithm on larger inputs.

### `findPosLinear`

```zig
pub fn findPosLinear(comptime T: type, haystack: []const T, start_index: usize, needle: []const T) ?usize
```

Consider using `findPos` instead of this, which will automatically use a
more sophisticated algorithm on larger inputs.

### `findLast`

```zig
pub fn findLast(comptime T: type, haystack: []const T, needle: []const T) ?usize
```

Find the index in a slice of a sub-slice, searching from the end backwards.
To start looking at a different index, slice the haystack first.
Uses the Reverse Boyer-Moore-Horspool algorithm on large inputs;
`lastIndexOfLinear` on small inputs.

### `findPos`

```zig
pub fn findPos(comptime T: type, haystack: []const T, start_index: usize, needle: []const T) ?usize
```

Uses Boyer-Moore-Horspool algorithm on large inputs; `findPosLinear` on small inputs.

### `count`

```zig
pub fn count(comptime T: type, haystack: []const T, needle: []const T) usize
```

Returns the number of needles inside the haystack
needle.len must be > 0
does not count overlapping needles

### `countScalar`

```zig
pub fn countScalar(comptime T: type, list: []const T, element: T) usize
```

Returns the number of times `element` appears in a slice of memory.

### `containsAtLeast`

```zig
pub fn containsAtLeast(comptime T: type, haystack: []const T, expected_count: usize, needle: []const T) bool
```

Returns true if the haystack contains expected_count or more needles
needle.len must be > 0
does not count overlapping needles
See also: `containsAtLeastScalar`

### `containsAtLeastScalar`

```zig
pub fn containsAtLeastScalar(comptime T: type, list: []const T, element: T, minimum: usize) bool
```

Returns true if `element` appears at least `minimum` number of times in `list`.
Related:
* `containsAtLeast`
* `countScalar`

### `readVarInt`

```zig
pub fn readVarInt(comptime ReturnType: type, bytes: []const u8, endian: Endian) ReturnType
```

Reads an integer from memory with size equal to bytes.len.
ReturnType specifies the return type, which must be large enough to store
the result.

### `readVarPackedInt`

```zig
pub fn readVarPackedInt(comptime T: type, bytes: []const u8, bit_offset: usize, bit_count: usize, endian: std.builtin.Endian, signedness: std.builtin.Signedness, ) T
```

Loads an integer from packed memory with provided bit_count, bit_offset, and signedness.
Asserts that T is large enough to store the read value.

### `readInt`

```zig
pub inline fn readInt(comptime T: type, buffer: *const [@divExact(@typeInfo(T).int.bits, 8)]u8, endian: Endian) T
```

Reads an integer from memory with bit count specified by T.
The bit count of T must be evenly divisible by 8.
This function cannot fail and cannot cause undefined behavior.

### `readPackedInt`

```zig
pub fn readPackedInt(comptime T: type, bytes: []const u8, bit_offset: usize, endian: Endian) T
```

Loads an integer from packed memory.
Asserts that buffer contains at least bit_offset + @bitSizeOf(T) bits.

### `writeInt`

```zig
pub inline fn writeInt(comptime T: type, buffer: *[@divExact(@typeInfo(T).int.bits, 8)]u8, value: T, endian: Endian) void
```

Writes an integer to memory, storing it in twos-complement.
This function always succeeds, has defined behavior for all inputs, but
the integer bit width must be divisible by 8.

### `writePackedInt`

```zig
pub fn writePackedInt(comptime T: type, bytes: []u8, bit_offset: usize, value: T, endian: Endian) void
```

Stores an integer to packed memory.
Asserts that buffer contains at least bit_offset + @bitSizeOf(T) bits.

### `writeVarPackedInt`

```zig
pub fn writeVarPackedInt(bytes: []u8, bit_offset: usize, bit_count: usize, value: anytype, endian: std.builtin.Endian) void
```

Stores an integer to packed memory with provided bit_offset, bit_count, and signedness.
If negative, the written value is sign-extended.

### `byteSwap`

```zig
pub fn byteSwap(comptime S: type, ptr: *S) void
```

Reverses the byte order.
Handles structs, unions, arrays, enums, floats, and integers recursively.
The order of extern struct fields and array elements remains unchanged and
will be byte swapped recursively.
Useful for converting between little-endian and big-endian representations.

### `byteSwapAligned`

```zig
pub fn byteSwapAligned(comptime S: type, comptime a: Alignment, ptr: *align(a.toByteUnits()) S, ) void
```

Reverses the byte order.
Handles structs, unions, arrays, enums, floats, and integers recursively.
The order of extern struct fields and array elements remains unchanged and
will be byte swapped recursively.
Useful for converting between little-endian and big-endian representations.

### `byteSwapAllElements`

```zig
pub fn byteSwapAllElements(comptime Elem: type, slice: []Elem) void
```

Reverses the byte order of all elements in a slice.
Handles structs, unions, arrays, enums, floats, and integers recursively.
Useful for converting between little-endian and big-endian representations.

### `tokenizeAny`

```zig
pub fn tokenizeAny(comptime T: type, buffer: []const T, delimiters: []const T) TokenIterator(T, .any)
```

Returns an iterator that iterates over the slices of `buffer` that are not
any of the items in `delimiters`.

`tokenizeAny(u8, "   abc|def ||  ghi  ", " |")` will return slices
for "abc", "def", "ghi", null, in that order.

If `buffer` is empty, the iterator will return null.
If none of `delimiters` exist in buffer,
the iterator will return `buffer`, null, in that order.

See also: `tokenizeSequence`, `tokenizeScalar`,
          `splitSequence`,`splitAny`, `splitScalar`,
          `splitBackwardsSequence`, `splitBackwardsAny`, and `splitBackwardsScalar`

### `tokenizeSequence`

```zig
pub fn tokenizeSequence(comptime T: type, buffer: []const T, delimiter: []const T) TokenIterator(T, .sequence)
```

Returns an iterator that iterates over the slices of `buffer` that are not
the sequence in `delimiter`.

`tokenizeSequence(u8, "<>abc><def<><>ghi", "<>")` will return slices
for "abc><def", "ghi", null, in that order.

If `buffer` is empty, the iterator will return null.
If `delimiter` does not exist in buffer,
the iterator will return `buffer`, null, in that order.
The delimiter length must not be zero.

See also: `tokenizeAny`, `tokenizeScalar`,
          `splitSequence`,`splitAny`, and `splitScalar`
          `splitBackwardsSequence`, `splitBackwardsAny`, and `splitBackwardsScalar`

### `tokenizeScalar`

```zig
pub fn tokenizeScalar(comptime T: type, buffer: []const T, delimiter: T) TokenIterator(T, .scalar)
```

Returns an iterator that iterates over the slices of `buffer` that are not
`delimiter`.

`tokenizeScalar(u8, "   abc def     ghi  ", ' ')` will return slices
for "abc", "def", "ghi", null, in that order.

If `buffer` is empty, the iterator will return null.
If `delimiter` does not exist in buffer,
the iterator will return `buffer`, null, in that order.

See also: `tokenizeAny`, `tokenizeSequence`,
          `splitSequence`,`splitAny`, and `splitScalar`
          `splitBackwardsSequence`, `splitBackwardsAny`, and `splitBackwardsScalar`

### `splitSequence`

```zig
pub fn splitSequence(comptime T: type, buffer: []const T, delimiter: []const T) SplitIterator(T, .sequence)
```

Returns an iterator that iterates over the slices of `buffer` that
are separated by the byte sequence in `delimiter`.

`splitSequence(u8, "abc||def||||ghi", "||")` will return slices
for "abc", "def", "", "ghi", null, in that order.

If `delimiter` does not exist in buffer,
the iterator will return `buffer`, null, in that order.
The delimiter length must not be zero.

See also: `splitAny`, `splitScalar`, `splitBackwardsSequence`,
          `splitBackwardsAny`,`splitBackwardsScalar`,
          `tokenizeAny`, `tokenizeSequence`, and `tokenizeScalar`.

### `splitAny`

```zig
pub fn splitAny(comptime T: type, buffer: []const T, delimiters: []const T) SplitIterator(T, .any)
```

Returns an iterator that iterates over the slices of `buffer` that
are separated by any item in `delimiters`.

`splitAny(u8, "abc,def||ghi", "|,")` will return slices
for "abc", "def", "", "ghi", null, in that order.

If none of `delimiters` exist in buffer,
the iterator will return `buffer`, null, in that order.

See also: `splitSequence`, `splitScalar`, `splitBackwardsSequence`,
          `splitBackwardsAny`,`splitBackwardsScalar`,
          `tokenizeAny`, `tokenizeSequence`, and `tokenizeScalar`.

### `splitScalar`

```zig
pub fn splitScalar(comptime T: type, buffer: []const T, delimiter: T) SplitIterator(T, .scalar)
```

Returns an iterator that iterates over the slices of `buffer` that
are separated by `delimiter`.

`splitScalar(u8, "abc|def||ghi", '|')` will return slices
for "abc", "def", "", "ghi", null, in that order.

If `delimiter` does not exist in buffer,
the iterator will return `buffer`, null, in that order.

See also: `splitSequence`, `splitAny`, `splitBackwardsSequence`,
          `splitBackwardsAny`,`splitBackwardsScalar`,
          `tokenizeAny`, `tokenizeSequence`, and `tokenizeScalar`.

### `splitBackwardsSequence`

```zig
pub fn splitBackwardsSequence(comptime T: type, buffer: []const T, delimiter: []const T) SplitBackwardsIterator(T, .sequence)
```

Returns an iterator that iterates backwards over the slices of `buffer` that
are separated by the sequence in `delimiter`.

`splitBackwardsSequence(u8, "abc||def||||ghi", "||")` will return slices
for "ghi", "", "def", "abc", null, in that order.

If `delimiter` does not exist in buffer,
the iterator will return `buffer`, null, in that order.
The delimiter length must not be zero.

See also: `splitBackwardsAny`, `splitBackwardsScalar`,
          `splitSequence`, `splitAny`,`splitScalar`,
          `tokenizeAny`, `tokenizeSequence`, and `tokenizeScalar`.

### `splitBackwardsAny`

```zig
pub fn splitBackwardsAny(comptime T: type, buffer: []const T, delimiters: []const T) SplitBackwardsIterator(T, .any)
```

Returns an iterator that iterates backwards over the slices of `buffer` that
are separated by any item in `delimiters`.

`splitBackwardsAny(u8, "abc,def||ghi", "|,")` will return slices
for "ghi", "", "def", "abc", null, in that order.

If none of `delimiters` exist in buffer,
the iterator will return `buffer`, null, in that order.

See also: `splitBackwardsSequence`, `splitBackwardsScalar`,
          `splitSequence`, `splitAny`,`splitScalar`,
          `tokenizeAny`, `tokenizeSequence`, and `tokenizeScalar`.

### `splitBackwardsScalar`

```zig
pub fn splitBackwardsScalar(comptime T: type, buffer: []const T, delimiter: T) SplitBackwardsIterator(T, .scalar)
```

Returns an iterator that iterates backwards over the slices of `buffer` that
are separated by `delimiter`.

`splitBackwardsScalar(u8, "abc|def||ghi", '|')` will return slices
for "ghi", "", "def", "abc", null, in that order.

If `delimiter` does not exist in buffer,
the iterator will return `buffer`, null, in that order.

See also: `splitBackwardsSequence`, `splitBackwardsAny`,
          `splitSequence`, `splitAny`,`splitScalar`,
          `tokenizeAny`, `tokenizeSequence`, and `tokenizeScalar`.

### `window`

```zig
pub fn window(comptime T: type, buffer: []const T, size: usize, advance: usize) WindowIterator(T)
```

Returns an iterator with a sliding window of slices for `buffer`.
The sliding window has length `size` and on every iteration moves
forward by `advance`.

Extract data for moving average with:
`window(u8, "abcdefg", 3, 1)` will return slices
"abc", "bcd", "cde", "def", "efg", null, in that order.

Chunk or split every N items with:
`window(u8, "abcdefg", 3, 3)` will return slices
"abc", "def", "g", null, in that order.

Pick every even index with:
`window(u8, "abcdefg", 1, 2)` will return slices
"a", "c", "e", "g" null, in that order.

The `size` and `advance` must be not be zero.

### `startsWith`

```zig
pub fn startsWith(comptime T: type, haystack: []const T, needle: []const T) bool
```

Returns true if haystack starts with needle.
Time complexity: O(needle.len)

### `endsWith`

```zig
pub fn endsWith(comptime T: type, haystack: []const T, needle: []const T) bool
```

Returns true if haystack ends with needle.
Time complexity: O(needle.len)

### `cutPrefix`

```zig
pub fn cutPrefix(comptime T: type, slice: []const T, prefix: []const T) ?[]const T
```

If `slice` starts with `prefix`, returns the rest of `slice` starting at `prefix.len`.

### `cutSuffix`

```zig
pub fn cutSuffix(comptime T: type, slice: []const T, suffix: []const T) ?[]const T
```

If `slice` ends with `suffix`, returns `slice` from beginning to start of `suffix`.

### `cut`

```zig
pub fn cut(comptime T: type, haystack: []const T, needle: []const T) ?struct { []const T, []const T }
```

Returns slice of `haystack` before and after first occurrence of `needle`,
or `null` if not found.

See also:
* `cutScalar`
* `split`
* `tokenizeAny`

### `cutLast`

```zig
pub fn cutLast(comptime T: type, haystack: []const T, needle: []const T) ?struct { []const T, []const T }
```

Returns slice of `haystack` before and after last occurrence of `needle`,
or `null` if not found.

See also:
* `cut`
* `cutScalarLast`

### `cutScalar`

```zig
pub fn cutScalar(comptime T: type, haystack: []const T, needle: T) ?struct { []const T, []const T }
```

Returns slice of `haystack` before and after first occurrence `needle`, or
`null` if not found.

See also:
* `cut`
* `splitScalar`
* `tokenizeScalar`

### `cutScalarLast`

```zig
pub fn cutScalarLast(comptime T: type, haystack: []const T, needle: T) ?struct { []const T, []const T }
```

Returns slice of `haystack` before and after last occurrence of `needle`,
or `null` if not found.

See also:
* `cut`
* `splitScalar`
* `tokenizeScalar`

### `join`

```zig
pub fn join(allocator: Allocator, separator: []const u8, slices: []const []const u8) Allocator.Error![]u8
```

Naively combines a series of slices with a separator.
Allocates memory for the result, which must be freed by the caller.

### `joinZ`

```zig
pub fn joinZ(allocator: Allocator, separator: []const u8, slices: []const []const u8) Allocator.Error![:0]u8
```

Naively combines a series of slices with a separator and null terminator.
Allocates memory for the result, which must be freed by the caller.

### `concat`

```zig
pub fn concat(allocator: Allocator, comptime T: type, slices: []const []const T) Allocator.Error![]T
```

Copies each T from slices into a new slice that exactly holds all the elements.

### `concatWithSentinel`

```zig
pub fn concatWithSentinel(allocator: Allocator, comptime T: type, slices: []const []const T, comptime s: T) Allocator.Error![:s]T
```

Copies each T from slices into a new slice that exactly holds all the elements.

### `concatMaybeSentinel`

```zig
pub fn concatMaybeSentinel(allocator: Allocator, comptime T: type, slices: []const []const T, comptime s: ?T) Allocator.Error![]T
```

Copies each T from slices into a new slice that exactly holds all the elements as well as the sentinel.

### `min`

```zig
pub fn min(comptime T: type, slice: []const T) T
```

Returns the smallest number in a slice. O(n).
`slice` must not be empty.

### `max`

```zig
pub fn max(comptime T: type, slice: []const T) T
```

Returns the largest number in a slice. O(n).
`slice` must not be empty.

### `findMin`

```zig
pub fn findMin(comptime T: type, slice: []const T) usize
```

Returns the index of the smallest number in a slice. O(n).
`slice` must not be empty.

### `findMax`

```zig
pub fn findMax(comptime T: type, slice: []const T) usize
```

Returns the index of the largest number in a slice. O(n).
`slice` must not be empty.

### `swap`

```zig
pub fn swap(comptime T: type, noalias a: *T, noalias b: *T) void
```

Exchanges contents of two memory locations.

### `reverse`

```zig
pub fn reverse(comptime T: type, items: []T) void
```

In-place order reversal of a slice

### `reverseIterator`

```zig
pub fn reverseIterator(slice: anytype) ReverseIterator(@TypeOf(slice))
```

Iterates over a slice in reverse.

### `rotate`

```zig
pub fn rotate(comptime T: type, items: []T, amount: usize) void
```

In-place rotation of the values in an array ([0 1 2 3] becomes [1 2 3 0] if we rotate by 1)
Assumes 0 <= amount <= items.len

### `replace`

```zig
pub fn replace(comptime T: type, input: []const T, needle: []const T, replacement: []const T, output: []T) usize
```

Replace needle with replacement as many times as possible, writing to an output buffer which is assumed to be of
appropriate size. Use replacementSize to calculate an appropriate buffer size.
The `input` and `output` slices must not overlap.
The needle must not be empty.
Returns the number of replacements made.

### `replaceScalar`

```zig
pub fn replaceScalar(comptime T: type, slice: []T, match: T, replacement: T) void
```

Replace all occurrences of `match` with `replacement`.

### `collapseRepeatsLen`

```zig
pub fn collapseRepeatsLen(comptime T: type, slice: []T, elem: T) usize
```

Collapse consecutive duplicate elements into one entry.

### `collapseRepeats`

```zig
pub fn collapseRepeats(comptime T: type, slice: []T, elem: T) []T
```

Collapse consecutive duplicate elements into one entry.

### `replacementSize`

```zig
pub fn replacementSize(comptime T: type, input: []const T, needle: []const T, replacement: []const T) usize
```

Calculate the size needed in an output buffer to perform a replacement.
The needle must not be empty.

### `replaceOwned`

```zig
pub fn replaceOwned(comptime T: type, allocator: Allocator, input: []const T, needle: []const T, replacement: []const T) Allocator.Error![]T
```

Perform a replacement on an allocated buffer of pre-determined size. Caller must free returned memory.

### `littleToNative`

```zig
pub fn littleToNative(comptime T: type, x: T) T
```

Converts a little-endian integer to host endianness.

### `bigToNative`

```zig
pub fn bigToNative(comptime T: type, x: T) T
```

Converts a big-endian integer to host endianness.

### `toNative`

```zig
pub fn toNative(comptime T: type, x: T, endianness_of_x: Endian) T
```

Converts an integer from specified endianness to host endianness.

### `nativeTo`

```zig
pub fn nativeTo(comptime T: type, x: T, desired_endianness: Endian) T
```

Converts an integer which has host endianness to the desired endianness.

### `nativeToLittle`

```zig
pub fn nativeToLittle(comptime T: type, x: T) T
```

Converts an integer which has host endianness to little endian.

### `nativeToBig`

```zig
pub fn nativeToBig(comptime T: type, x: T) T
```

Converts an integer which has host endianness to big endian.

### `alignPointerOffset`

```zig
pub fn alignPointerOffset(ptr: anytype, align_to: usize) ?usize
```

Returns the number of elements that, if added to the given pointer, align it
to a multiple of the given quantity, or `null` if one of the following
conditions is met:
- The aligned pointer would not fit the address space,
- The delta required to align the pointer is not a multiple of the pointee's
  type.

### `alignPointer`

```zig
pub fn alignPointer(ptr: anytype, align_to: usize) ?@TypeOf(ptr)
```

Aligns a given pointer value to a specified alignment factor.
Returns an aligned pointer or null if one of the following conditions is
met:
- The aligned pointer would not fit the address space,
- The delta required to align the pointer is not a multiple of the pointee's
  type.

### `asBytes`

```zig
pub fn asBytes(ptr: anytype) AsBytesReturnType(@TypeOf(ptr))
```

Given a pointer to a single item, returns a slice of the underlying bytes, preserving pointer attributes.

### `toBytes`

```zig
pub fn toBytes(value: anytype) [@sizeOf(@TypeOf(value))]u8
```

Given any value, returns a copy of its bytes in an array.

### `bytesAsValue`

```zig
pub fn bytesAsValue(comptime T: type, bytes: anytype) BytesAsValueReturnType(T, @TypeOf(bytes))
```

Given a pointer to an array of bytes, returns a pointer to a value of the specified type
backed by those bytes, preserving pointer attributes.

### `bytesToValue`

```zig
pub fn bytesToValue(comptime T: type, bytes: anytype) T
```

Given a pointer to an array of bytes, returns a value of the specified type backed by a
copy of those bytes.

### `bytesAsSlice`

```zig
pub fn bytesAsSlice(comptime T: type, bytes: anytype) BytesAsSliceReturnType(T, @TypeOf(bytes))
```

Given a slice of bytes, returns a slice of the specified type
backed by those bytes, preserving pointer attributes.
If `T` is zero-bytes sized, the returned slice has a len of zero.

### `sliceAsBytes`

```zig
pub fn sliceAsBytes(slice: anytype) SliceAsBytesReturnType(@TypeOf(slice))
```

Given a slice, returns a slice of the underlying bytes, preserving pointer attributes.

### `absorbSentinel`

```zig
pub fn absorbSentinel(slice: anytype) AbsorbSentinel(@TypeOf(slice))
```

If the provided slice is not sentinel terminated, do nothing and return that slice.
If it is sentinel-terminated, return a non-sentinel-terminated slice with the
length increased by one to include the absorbed sentinel element.

### `alignForwardAnyAlign`

```zig
pub fn alignForwardAnyAlign(comptime T: type, addr: T, alignment: T) T
```

Round an address down to the next (or current) aligned address.
Unlike `alignForward`, `alignment` can be any positive number, not just a power of 2.

### `alignForward`

```zig
pub fn alignForward(comptime T: type, addr: T, alignment: T) T
```

Round an address up to the next (or current) aligned address.
The alignment must be a power of 2 and greater than 0.
Asserts that rounding up the address does not cause integer overflow.

### `alignForwardLog2`

```zig
pub fn alignForwardLog2(addr: usize, log2_alignment: u8) usize
```

Rounds an address up to the next alignment boundary using log2 representation.
Equivalent to alignForward with alignment = 1 << log2_alignment.
More efficient when alignment is known to be a power of 2.

### `doNotOptimizeAway`

```zig
pub fn doNotOptimizeAway(val: anytype) void
```

Force an evaluation of the expression; this tries to prevent
the compiler from optimizing the computation away even if the
result eventually gets discarded.

### `alignBackwardAnyAlign`

```zig
pub fn alignBackwardAnyAlign(comptime T: type, addr: T, alignment: T) T
```

Round an address down to the previous (or current) aligned address.
Unlike `alignBackward`, `alignment` can be any positive number, not just a power of 2.

### `alignBackward`

```zig
pub fn alignBackward(comptime T: type, addr: T, alignment: T) T
```

Round an address down to the previous (or current) aligned address.
The alignment must be a power of 2 and greater than 0.

### `isValidAlign`

```zig
pub fn isValidAlign(alignment: usize) bool
```

Returns whether `alignment` is a valid alignment, meaning it is
a positive power of 2.

### `isValidAlignGeneric`

```zig
pub fn isValidAlignGeneric(comptime T: type, alignment: T) bool
```

Returns whether `alignment` is a valid alignment, meaning it is
a positive power of 2.

### `isAlignedAnyAlign`

```zig
pub fn isAlignedAnyAlign(i: usize, alignment: usize) bool
```

Returns true if i is aligned to the given alignment.
Works with any positive alignment value, not just powers of 2.
For power-of-2 alignments, `isAligned` is more efficient.

### `isAlignedLog2`

```zig
pub fn isAlignedLog2(addr: usize, log2_alignment: u8) bool
```

Returns true if addr is aligned to 2^log2_alignment.
More efficient than `isAligned` when alignment is known to be a power of 2.
log2_alignment must be < @bitSizeOf(usize).

### `isAligned`

```zig
pub fn isAligned(addr: usize, alignment: usize) bool
```

Given an address and an alignment, return true if the address is a multiple of the alignment
The alignment must be a power of 2 and greater than 0.

### `isAlignedGeneric`

```zig
pub fn isAlignedGeneric(comptime T: type, addr: T, alignment: T) bool
```

Generic version of `isAligned` that works with any integer type.
Returns true if addr is aligned to the given alignment.
Alignment must be a power of 2 and greater than 0.

### `alignInBytes`

```zig
pub fn alignInBytes(bytes: []u8, comptime new_alignment: usize) ?[]align(new_alignment) u8
```

Returns the largest slice in the given bytes that conforms to the new alignment,
or `null` if the given bytes contain no conforming address.

### `alignInSlice`

```zig
pub fn alignInSlice(slice: anytype, comptime new_alignment: usize) ?AlignedSlice(@TypeOf(slice), new_alignment)
```

Returns the largest sub-slice within the given slice that conforms to the new alignment,
or `null` if the given slice contains no conforming address.

### `print`

```zig
pub fn print(buffer: []u8, comptime format: []const u8, args: anytype) PrintError![]u8
```

Render a formatted string into `buffer`. Returns a slice of `buffer`
starting at index 0 containing the result, or `error.NoSpaceLeft` if one or
more bytes were truncated.

See `std.Io.Writer.print`.

### `printSentinel`

```zig
pub fn printSentinel(buffer: []u8, comptime format: []const u8, args: anytype, comptime sentinel: u8, ) PrintError![:sentinel]u8
```

Like `print` but returned slice has the provided sentinel.

## Error Sets

- **`PrintError`**
  

## Constants & Variables

- **`byte_size_in_bits`**: The standard library currently thoroughly depends on byte size
- **`Allocator`**: 
- **`indexOfDiff`**: Deprecated in favor of `findDiff`.
- **`indexOfSentinel`**: Deprecated in favor of `findSentinel`.
- **`indexOfScalar`**: Deprecated in favor of `findScalar`.
- **`lastIndexOfScalar`**: Deprecated in favor of `findScalarLast`.
- **`indexOfScalarPos`**: Deprecated in favor of `findScalarPos`.
- **`indexOfAny`**: Deprecated in favor of `findAny`.
- **`lastIndexOfAny`**: Deprecated in favor of `findLastAny`.
- **`indexOfAnyPos`**: Deprecated in favor of `findAnyPos`.
- **`indexOfNone`**: Deprecated in favor of `findNone`.
- **`lastIndexOfNone`**: Deprecated in favor of `findLastNone`.
- **`indexOfNonePos`**: 
- **`indexOf`**: Deprecated in favor of `find`.
- **`lastIndexOfLinear`**: Deprecated in favor of `findLastLinear`.
- **`indexOfPosLinear`**: 
- **`lastIndexOf`**: Deprecated in favor of `find`.
- **`indexOfPos`**: Deprecated in favor of `findPos`.
- **`byteSwapAllFields`**: Deprecated: use `byteSwap` instead.
- **`byteSwapAllFieldsAligned`**: Deprecated: use `byteSwapAligned` instead.
- **`indexOfMin`**: Deprecated in favor of `findMin`.
- **`indexOfMax`**: 
- **`indexOfMinMax`**: Deprecated in favor of `findMinMax`.

