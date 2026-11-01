# `std.simd`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/simd.zig`  
> [← Back to Standard Library Index](README.md)

SIMD (Single Instruction; Multiple Data) convenience functions.

May offer a potential boost in performance on some targets by performing
the same operation on multiple elements at once.

Some functions are known to not work on MIPS.

## Types

### `VectorIndex`

```zig
pub fn VectorIndex(comptime VectorType: type) type
```

Returns the smallest type of unsigned ints capable of indexing any element within the given vector type.

### `VectorCount`

```zig
pub fn VectorCount(comptime VectorType: type) type
```

Returns the smallest type of unsigned ints capable of holding the length of the given vector type.

## Functions

### `suggestVectorLengthForCpu`

```zig
pub fn suggestVectorLengthForCpu(comptime T: type, comptime cpu: std.Target.Cpu) ?comptime_int
```


### `suggestVectorLength`

```zig
pub fn suggestVectorLength(comptime T: type) ?comptime_int
```

Suggests a target-dependant vector length for a given type, or null if scalars are recommended.
Not yet implemented for every CPU architecture.

### `iota`

```zig
pub inline fn iota(comptime T: type, comptime len: usize) @Vector(len, T)
```

Returns a vector containing the first `len` integers in order from 0 to `len`-1.
For example, `iota(i32, 8)` will return a vector containing `.{0, 1, 2, 3, 4, 5, 6, 7}`.

### `repeat`

```zig
pub fn repeat(comptime len: usize, vec: anytype) @Vector(len, std.meta.Child(@TypeOf(vec)))
```

Returns a vector containing the same elements as the input, but repeated until the desired length is reached.
For example, `repeat(8, [_]u32{1, 2, 3})` will return a vector containing `.{1, 2, 3, 1, 2, 3, 1, 2}`.

### `join`

```zig
pub fn join(a: anytype, b: anytype) @Vector(vectorLength(@TypeOf(a)) + vectorLength(@TypeOf(b)), std.meta.Child(@TypeOf(a)))
```

Returns a vector containing all elements of the first vector at the lower indices followed by all elements of the second vector
at the higher indices.

### `interlace`

```zig
pub fn interlace(vecs: anytype) @Vector(vectorLength(@TypeOf(vecs[0])) * vecs.len, std.meta.Child(@TypeOf(vecs[0])))
```

Returns a vector whose elements alternates between those of each input vector.
For example, `interlace(.{[4]u32{11, 12, 13, 14}, [4]u32{21, 22, 23, 24}})` returns a vector containing `.{11, 21, 12, 22, 13, 23, 14, 24}`.

### `deinterlace`

```zig
pub fn deinterlace(comptime vec_count: usize, interlaced: anytype, ) [vec_count]@Vector(vectorLength(@TypeOf(interlaced)) / vec_count, std.meta.Child(@TypeOf(interlaced)), )
```

The contents of `interlaced` is evenly split between vec_count vectors that are returned as an array. They "take turns",
receiving one element from `interlaced` at a time.

### `extract`

```zig
pub fn extract(vec: anytype, comptime first: VectorIndex(@TypeOf(vec)), comptime count: VectorCount(@TypeOf(vec)), ) @Vector(count, std.meta.Child(@TypeOf(vec)))
```


### `mergeShift`

```zig
pub fn mergeShift(a: anytype, b: anytype, comptime shift: VectorCount(@TypeOf(a, b))) @TypeOf(a, b)
```

Joins two vectors, shifts them leftwards (towards lower indices) and extracts the leftmost elements into a vector the length of a and b.

### `shiftElementsRight`

```zig
pub fn shiftElementsRight(vec: anytype, comptime amount: VectorCount(@TypeOf(vec)), shift_in: std.meta.Child(@TypeOf(vec))) @TypeOf(vec)
```

Elements are shifted rightwards (towards higher indices). New elements are added to the left, and the rightmost elements are cut off
so that the length of the vector stays the same.

### `shiftElementsLeft`

```zig
pub fn shiftElementsLeft(vec: anytype, comptime amount: VectorCount(@TypeOf(vec)), shift_in: std.meta.Child(@TypeOf(vec))) @TypeOf(vec)
```

Elements are shifted leftwards (towards lower indices). New elements are added to the right, and the leftmost elements are cut off
so that no elements with indices below 0 remain.

### `rotateElementsLeft`

```zig
pub fn rotateElementsLeft(vec: anytype, comptime amount: VectorCount(@TypeOf(vec))) @TypeOf(vec)
```

Elements are shifted leftwards (towards lower indices). Elements that leave to the left will reappear to the right in the same order.

### `rotateElementsRight`

```zig
pub fn rotateElementsRight(vec: anytype, comptime amount: VectorCount(@TypeOf(vec))) @TypeOf(vec)
```

Elements are shifted rightwards (towards higher indices). Elements that leave to the right will reappear to the left in the same order.

### `reverseOrder`

```zig
pub fn reverseOrder(vec: anytype) @TypeOf(vec)
```


### `firstTrue`

```zig
pub fn firstTrue(vec: anytype) ?VectorIndex(@TypeOf(vec))
```


### `lastTrue`

```zig
pub fn lastTrue(vec: anytype) ?VectorIndex(@TypeOf(vec))
```


### `countTrues`

```zig
pub fn countTrues(vec: anytype) VectorCount(@TypeOf(vec))
```


### `firstIndexOfValue`

```zig
pub fn firstIndexOfValue(vec: anytype, value: std.meta.Child(@TypeOf(vec))) ?VectorIndex(@TypeOf(vec))
```


### `lastIndexOfValue`

```zig
pub fn lastIndexOfValue(vec: anytype, value: std.meta.Child(@TypeOf(vec))) ?VectorIndex(@TypeOf(vec))
```


### `countElementsWithValue`

```zig
pub fn countElementsWithValue(vec: anytype, value: std.meta.Child(@TypeOf(vec))) VectorCount(@TypeOf(vec))
```


### `prefixScanWithFunc`

```zig
pub fn prefixScanWithFunc(comptime hop: isize, vec: anytype, comptime ErrorType: type, comptime func: fn (@TypeOf(vec), @TypeOf(vec)) if (ErrorType == void) @TypeOf(vec) else ErrorType!@TypeOf(vec), comptime identity: std.meta.Child(@TypeOf(vec)), ) if (ErrorType == void) @TypeOf(vec) else ErrorType!@TypeOf(vec)
```

Same as prefixScan, but with a user-provided, mathematically associative function.

### `prefixScan`

```zig
pub fn prefixScan(comptime op: std.builtin.ReduceOp, comptime hop: isize, vec: anytype) @TypeOf(vec)
```

Returns a vector whose elements are the result of performing the specified operation on the corresponding
element of the input vector and every hop'th element that came before it (or after, if hop is negative).
Supports the same operations as the @reduce() builtin. Takes O(logN) to compute.
The scan is not linear, which may affect floating point errors. This may affect the determinism of
algorithms that use this function.

