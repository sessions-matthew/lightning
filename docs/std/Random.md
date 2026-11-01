# `std.Random`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/Random.zig`  
> [← Back to Standard Library Index](README.md)

The engines provided here should be initialized from an external source.
Be sure to use a CSPRNG when required, otherwise using a normal PRNG will
be faster and use substantially less stack space.

## Fields

- `ptr: *anyopaque`
  Any comparison of this field may result in illegal behavior, since it may be set to
  `undefined` in cases where the random implementation does not have any associated
  state.
- `fillFn: *const fn (ptr: *anyopaque, buf: []u8) void`
  

## Types

### `IoSource`


### Fields

- `io: std.Io`
  

### Functions

#### `interface`

```zig
pub fn interface(this: *const @This()) std.Random
```


## Functions

### `init`

```zig
pub fn init(pointer: anytype, comptime fillFn: fn (ptr: @TypeOf(pointer), buf: []u8) void) Random
```


### `bytes`

```zig
pub fn bytes(r: Random, buf: []u8) void
```

Read random bytes into the specified buffer until full.

### `array`

```zig
pub fn array(r: Random, comptime E: type, comptime N: usize) [N]E
```


### `boolean`

```zig
pub fn boolean(r: Random) bool
```


### `enumValue`

```zig
pub inline fn enumValue(r: Random, comptime EnumType: type) EnumType
```

Returns a random value from an enum, evenly distributed.

Note that this will not yield consistent results across all targets
due to dependence on the representation of `usize` as an index.
See `enumValueWithIndex` for further commentary.

### `enumValueWithIndex`

```zig
pub fn enumValueWithIndex(r: Random, comptime EnumType: type, comptime Index: type) EnumType
```

Returns a random value from an enum, evenly distributed.

An index into an array of all named values is generated using the
specified `Index` type to determine the return value.
This allows for results to be independent of `usize` representation.

Prefer `enumValue` if this isn't important.

See `uintLessThan`, which this function uses in most cases,
for commentary on the runtime of this function.

### `int`

```zig
pub fn int(r: Random, comptime T: type) T
```

Returns a random int `i` such that `minInt(T) <= i <= maxInt(T)`.
`i` is evenly distributed.

### `uintLessThanBiased`

```zig
pub fn uintLessThanBiased(r: Random, comptime T: type, less_than: T) T
```

Constant-time implementation off `uintLessThan`.
The results of this function may be biased.

### `uintLessThan`

```zig
pub fn uintLessThan(r: Random, comptime T: type, less_than: T) T
```

Returns an evenly distributed random unsigned integer `0 <= i < less_than`.
This function assumes that the underlying `fillFn` produces evenly distributed values.
Within this assumption, the runtime of this function is exponentially distributed.
If `fillFn` were backed by a true random generator,
the runtime of this function would technically be unbounded.
However, if `fillFn` is backed by any evenly distributed pseudo random number generator,
this function is guaranteed to return.
If you need deterministic runtime bounds, use `uintLessThanBiased`.

### `uintAtMostBiased`

```zig
pub fn uintAtMostBiased(r: Random, comptime T: type, at_most: T) T
```

Constant-time implementation off `uintAtMost`.
The results of this function may be biased.

### `uintAtMost`

```zig
pub fn uintAtMost(r: Random, comptime T: type, at_most: T) T
```

Returns an evenly distributed random unsigned integer `0 <= i <= at_most`.
See `uintLessThan`, which this function uses in most cases,
for commentary on the runtime of this function.

### `intRangeLessThanBiased`

```zig
pub fn intRangeLessThanBiased(r: Random, comptime T: type, at_least: T, less_than: T) T
```

Constant-time implementation off `intRangeLessThan`.
The results of this function may be biased.

### `intRangeLessThan`

```zig
pub fn intRangeLessThan(r: Random, comptime T: type, at_least: T, less_than: T) T
```

Returns an evenly distributed random integer `at_least <= i < less_than`.
See `uintLessThan`, which this function uses in most cases,
for commentary on the runtime of this function.

### `intRangeAtMostBiased`

```zig
pub fn intRangeAtMostBiased(r: Random, comptime T: type, at_least: T, at_most: T) T
```

Constant-time implementation off `intRangeAtMostBiased`.
The results of this function may be biased.

### `intRangeAtMost`

```zig
pub fn intRangeAtMost(r: Random, comptime T: type, at_least: T, at_most: T) T
```

Returns an evenly distributed random integer `at_least <= i <= at_most`.
See `uintLessThan`, which this function uses in most cases,
for commentary on the runtime of this function.

### `float`

```zig
pub fn float(r: Random, comptime T: type) T
```

Return a floating point value evenly distributed in the range [0, 1).

### `floatNorm`

```zig
pub fn floatNorm(r: Random, comptime T: type) T
```

Return a floating point value normally distributed with mean = 0, stddev = 1.

To use different parameters, use: floatNorm(...) * desiredStddev + desiredMean.

### `floatExp`

```zig
pub fn floatExp(r: Random, comptime T: type) T
```

Return an exponentially distributed float with a rate parameter of 1.

To use a different rate parameter, use: floatExp(...) / desiredRate.

### `shuffle`

```zig
pub inline fn shuffle(r: Random, comptime T: type, buf: []T) void
```

Shuffle a slice into a random order.

Note that this will not yield consistent results across all targets
due to dependence on the representation of `usize` as an index.
See `shuffleWithIndex` for further commentary.

### `shuffleWithIndex`

```zig
pub fn shuffleWithIndex(r: Random, comptime T: type, buf: []T, comptime Index: type) void
```

Shuffle a slice into a random order, using an index of a
specified type to maintain distribution across targets.
Asserts the index type can represent `buf.len`.

Indexes into the slice are generated using the specified `Index`
type, which determines distribution properties. This allows for
results to be independent of `usize` representation.

Prefer `shuffle` if this isn't important.

See `intRangeLessThan`, which this function uses,
for commentary on the runtime of this function.

### `weightedIndex`

```zig
pub fn weightedIndex(r: Random, comptime T: type, proportions: []const T) usize
```

Randomly selects an index into `proportions`, where the likelihood of each
index is weighted by that proportion.
It is more likely for the index of the last proportion to be returned
than the index of the first proportion in the slice, and vice versa.

This is useful for selecting an item from a slice where weights are not equal.
`T` must be a numeric type capable of holding the sum of `proportions`.

### `limitRangeBiased`

```zig
pub fn limitRangeBiased(comptime T: type, random_int: T, less_than: T) T
```

Convert a random integer 0 <= random_int <= maxValue(T),
into an integer 0 <= result < less_than.
This function introduces a minor bias.

## Constants & Variables

- **`DefaultPrng`**: Fast unbiased random numbers.
- **`DefaultCsprng`**: Cryptographically secure random numbers.
- **`Ascon`**: 
- **`ChaCha`**: 
- **`Isaac64`**: 
- **`Pcg`**: 
- **`Xoroshiro128`**: 
- **`Xoshiro256`**: 
- **`Sfc64`**: 
- **`RomuTrio`**: 
- **`SplitMix64`**: 
- **`ziggurat`**: 
- **`lcg`**: 

