# `std.math`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/math.zig`  
> [← Back to Standard Library Index](README.md)

## Types

### `Sign`


### Fields

- `positive`
  
- `negative`
  

### `Min`

```zig
pub fn Min(comptime A: type, comptime B: type) type
```

Given two types, returns the smallest one which is capable of holding the
full range of the minimum value.

### `Log2Int`

```zig
pub fn Log2Int(comptime T: type) type
```

Returns an unsigned int type that can hold the number of bits in T - 1.
Suitable for 0-based bit indices of T.

### `Log2IntCeil`

```zig
pub fn Log2IntCeil(comptime T: type) type
```

Returns an unsigned int type that can hold the number of bits in T.

### `IntFittingRange`

```zig
pub fn IntFittingRange(comptime from: comptime_int, comptime to: comptime_int) type
```

Returns the smallest integer type that can hold both from and to.

### `ByteAlignedInt`

```zig
pub fn ByteAlignedInt(comptime T: type) type
```

Aligns the given integer type bit width to a width divisible by 8.

### `Order`

See also `CompareOperator`.

### Fields

- `gt`
  Greater than (`>`)
- `lt`
  Less than (`<`)
- `eq`
  Equal (`==`)

### Functions

#### `invert`

```zig
pub fn invert(self: Order) Order
```


#### `differ`

```zig
pub fn differ(self: Order) ?Order
```


#### `compare`

```zig
pub fn compare(self: Order, op: CompareOperator) bool
```


### `CompareOperator`

See also `Order`.

### Fields

- `lt`
  Less than (`<`)
- `lte`
  Less than or equal (`<=`)
- `eq`
  Equal (`==`)
- `gte`
  Greater than or equal (`>=`)
- `gt`
  Greater than (`>`)
- `neq`
  Not equal (`!=`)

### Functions

#### `reverse`

```zig
pub fn reverse(op: CompareOperator) CompareOperator
```

Reverse the direction of the comparison.
Use when swapping the left and right hand operands.

### `F80`


### Fields

- `fraction: u64`
  
- `exp: u16`
  

### Functions

#### `toFloat`

```zig
pub fn toFloat(self: F80) f80
```


#### `fromFloat`

```zig
pub fn fromFloat(x: f80) F80
```


## Functions

### `approxEqAbs`

```zig
pub fn approxEqAbs(comptime T: type, x: T, y: T, tolerance: T) bool
```

Performs an approximate comparison of two floating point values `x` and `y`.
Returns true if the absolute difference between them is less or equal than
the specified tolerance.

The `tolerance` parameter is the absolute tolerance used when determining if
the two numbers are close enough; a good value for this parameter is a small
multiple of `floatEps(T)`.

Note that this function is recommended for comparing small numbers
around zero; using `approxEqRel` is suggested otherwise.

NaN values are never considered equal to any value.

### `approxEqRel`

```zig
pub fn approxEqRel(comptime T: type, x: T, y: T, tolerance: T) bool
```

Performs an approximate comparison of two floating point values `x` and `y`.
Returns true if the absolute difference between them is less or equal than
`max(|x|, |y|) * tolerance`, where `tolerance` is a positive number greater
than zero.

The `tolerance` parameter is the relative tolerance used when determining if
the two numbers are close enough; a good value for this parameter is usually
`sqrt(floatEps(T))`, meaning that the two numbers are considered equal if at
least half of the digits are equal.

Note that for comparisons of small numbers around zero this function won't
give meaningful results, use `approxEqAbs` instead.

NaN values are never considered equal to any value.

### `raiseInvalid`

```zig
pub fn raiseInvalid() void
```


### `raiseUnderflow`

```zig
pub fn raiseUnderflow() void
```


### `raiseOverflow`

```zig
pub fn raiseOverflow() void
```


### `raiseInexact`

```zig
pub fn raiseInexact() void
```


### `raiseDivByZero`

```zig
pub fn raiseDivByZero() void
```


### `sin`

```zig
pub inline fn sin(value: anytype) @TypeOf(value)
```

Sine trigonometric function on a floating point number.
Uses a dedicated hardware instruction when available.
This is the same as calling the builtin @sin

### `cos`

```zig
pub inline fn cos(value: anytype) @TypeOf(value)
```

Cosine trigonometric function on a floating point number.
Uses a dedicated hardware instruction when available.
This is the same as calling the builtin @cos

### `tan`

```zig
pub inline fn tan(value: anytype) @TypeOf(value)
```

Tangent trigonometric function on a floating point number.
Uses a dedicated hardware instruction when available.
This is the same as calling the builtin @tan

### `radiansToDegrees`

```zig
pub fn radiansToDegrees(ang: anytype) if (@TypeOf(ang) == comptime_int) comptime_float else @TypeOf(ang)
```

Converts an angle in radians to degrees. T must be a float or comptime number or a vector of floats.

### `degreesToRadians`

```zig
pub fn degreesToRadians(ang: anytype) if (@TypeOf(ang) == comptime_int) comptime_float else @TypeOf(ang)
```

Converts an angle in degrees to radians. T must be a float or comptime number or a vector of floats.

### `exp`

```zig
pub inline fn exp(value: anytype) @TypeOf(value)
```

Base-e exponential function on a floating point number.
Uses a dedicated hardware instruction when available.
This is the same as calling the builtin @exp

### `exp2`

```zig
pub inline fn exp2(value: anytype) @TypeOf(value)
```

Base-2 exponential function on a floating point number.
Uses a dedicated hardware instruction when available.
This is the same as calling the builtin @exp2

### `wrap`

```zig
pub fn wrap(x: anytype, r: anytype) @TypeOf(x)
```

Odd sawtooth function
```
        |
     /  | /    /
    /   |/    /
 --/----/----/--
  /    /|   /
 /    / |  /
        |
```
Limit x to the half-open interval [-r, r).

### `clamp`

```zig
pub fn clamp(val: anytype, lower: anytype, upper: anytype) @TypeOf(val, lower, upper)
```

Odd ramp function
```
        |  _____
        | /
        |/
 -------/-------
       /|
 _____/ |
        |
```
Limit val to the inclusive range [lower, upper].

### `mul`

```zig
pub fn mul(comptime T: type, a: T, b: T) (error{Overflow}!T)
```

Returns the product of a and b. Returns an error on overflow.

### `add`

```zig
pub fn add(comptime T: type, a: T, b: T) (error{Overflow}!T)
```

Returns the sum of a and b. Returns an error on overflow.

### `sub`

```zig
pub fn sub(comptime T: type, a: T, b: T) (error{Overflow}!T)
```

Returns a - b, or an error on overflow.

### `negate`

```zig
pub fn negate(x: anytype) !@TypeOf(x)
```


### `shlExact`

```zig
pub fn shlExact(comptime T: type, a: T, shift_amt: Log2Int(T)) !T
```

Shifts a left by shift_amt. Returns an error on overflow. shift_amt
is unsigned.

### `shl`

```zig
pub fn shl(comptime T: type, a: T, shift_amt: anytype) T
```

Shifts left. Overflowed bits are truncated.
A negative shift amount results in a right shift.

### `shr`

```zig
pub fn shr(comptime T: type, a: T, shift_amt: anytype) T
```

Shifts right. Overflowed bits are truncated.
A negative shift amount results in a left shift.

### `rotr`

```zig
pub fn rotr(comptime T: type, x: T, r: anytype) T
```

Rotates right. Only unsigned values can be rotated.  Negative shift
values result in shift modulo the bit count.

### `rotl`

```zig
pub fn rotl(comptime T: type, x: T, r: anytype) T
```

Rotates left. Only unsigned values can be rotated.  Negative shift
values result in shift modulo the bit count.

### `divTrunc`

```zig
pub fn divTrunc(comptime T: type, numerator: T, denominator: T) !T
```

Divide numerator by denominator, rounding toward zero. Returns an
error on overflow or when denominator is zero.

### `divFloor`

```zig
pub fn divFloor(comptime T: type, numerator: T, denominator: T) !T
```

Divide numerator by denominator, rounding toward negative
infinity. Returns an error on overflow or when denominator is
zero.

### `divCeil`

```zig
pub fn divCeil(comptime T: type, numerator: T, denominator: T) !T
```

Divide numerator by denominator, rounding toward positive
infinity. Returns an error on overflow or when denominator is
zero.

### `divExact`

```zig
pub fn divExact(comptime T: type, numerator: T, denominator: T) !T
```

Divide numerator by denominator. Return an error if quotient is
not an integer, denominator is zero, or on overflow.

### `mod`

```zig
pub fn mod(comptime T: type, numerator: T, denominator: T) !T
```

Returns numerator modulo denominator, or an error if denominator is
zero or negative. Negative numerators never result in negative
return values.

### `rem`

```zig
pub fn rem(comptime T: type, numerator: T, denominator: T) !T
```

Returns the remainder when numerator is divided by denominator, or
an error if denominator is zero or negative. Negative numerators
can give negative results.

### `negateCast`

```zig
pub fn negateCast(x: anytype) !@Int(.signed, @bitSizeOf(@TypeOf(x)))
```

Returns the negation of the integer parameter.
Result is a signed integer.

### `cast`

```zig
pub fn cast(comptime T: type, x: anytype) ?T
```

Cast an integer to a different integer type. If the value doesn't fit,
return null.

### `alignCast`

```zig
pub fn alignCast(comptime alignment: Alignment, ptr: anytype) AlignCastError!AlignCastResult(alignment, @TypeOf(ptr))
```

Align cast a pointer but return an error if it's the wrong alignment

### `isPowerOfTwo`

```zig
pub fn isPowerOfTwo(int: anytype) bool
```

Asserts `int > 0`.

### `round`

```zig
pub inline fn round(value: anytype) @TypeOf(value)
```

Rounds the given floating point number to the nearest integer.
If two integers are equally close, rounds away from zero.
Uses a dedicated hardware instruction when available.
This is the same as calling the builtin @round

### `trunc`

```zig
pub inline fn trunc(value: anytype) @TypeOf(value)
```

Rounds the given floating point number to an integer, towards zero.
Uses a dedicated hardware instruction when available.
This is the same as calling the builtin @trunc

### `floor`

```zig
pub inline fn floor(value: anytype) @TypeOf(value)
```

Returns the largest integral value not greater than the given floating point number.
Uses a dedicated hardware instruction when available.
This is the same as calling the builtin @floor

### `floorPowerOfTwo`

```zig
pub fn floorPowerOfTwo(comptime T: type, value: T) T
```

Returns the nearest power of two less than or equal to value, or
zero if value is less than or equal to zero.

### `ceil`

```zig
pub inline fn ceil(value: anytype) @TypeOf(value)
```

Returns the smallest integral value not less than the given floating point number.
Uses a dedicated hardware instruction when available.
This is the same as calling the builtin @ceil

### `ceilPowerOfTwoPromote`

```zig
pub fn ceilPowerOfTwoPromote(comptime T: type, value: T) @Int(@typeInfo(T).int.signedness, @typeInfo(T).int.bits + 1)
```

Returns the next power of two (if the value is not already a power of two).
Only unsigned integers can be used. Zero is not an allowed input.
Result is a type with 1 more bit than the input type.

### `ceilPowerOfTwo`

```zig
pub fn ceilPowerOfTwo(comptime T: type, value: T) (error{Overflow}!T)
```

Returns the next power of two (if the value is not already a power of two).
Only unsigned integers can be used. Zero is not an allowed input.
If the value doesn't fit, returns an error.

### `ceilPowerOfTwoAssert`

```zig
pub fn ceilPowerOfTwoAssert(comptime T: type, value: T) T
```

Returns the next power of two (if the value is not already a power
of two). Only unsigned integers can be used. Zero is not an
allowed input. Asserts that the value fits.

### `log2_int`

```zig
pub fn log2_int(comptime T: type, x: T) Log2Int(T)
```

Return the log base 2 of integer value x, rounding down to the
nearest integer.

### `log2_int_ceil`

```zig
pub fn log2_int_ceil(comptime T: type, x: T) Log2IntCeil(T)
```

Return the log base 2 of integer value x, rounding up to the
nearest integer.

### `lossyCast`

```zig
pub fn lossyCast(comptime T: type, value: anytype) T
```

Cast a value to a different type. If the value doesn't fit in, or
can't be perfectly represented by, the new type, it will be
converted to the closest possible representation.

### `lerp`

```zig
pub fn lerp(a: anytype, b: anytype, t: anytype) @TypeOf(a, b, t)
```

Performs linear interpolation between *a* and *b* based on *t*.
*t* ranges from 0.0 to 1.0, but may exceed these bounds.
Supports floats and vectors of floats.

This does not guarantee returning *b* if *t* is 1 due to floating-point errors.
This is monotonic.

### `maxInt`

```zig
pub fn maxInt(comptime T: type) comptime_int
```

Returns the maximum value of integer type T.

### `minInt`

```zig
pub fn minInt(comptime T: type) comptime_int
```

Returns the minimum value of integer type T.

### `mulWide`

```zig
pub fn mulWide(comptime T: type, a: T, b: T) @Int(@typeInfo(T).int.signedness, @typeInfo(T).int.bits * 2, )
```

Multiply a and b. Return type is wide enough to guarantee no
overflow.

### `order`

```zig
pub fn order(a: anytype, b: anytype) Order
```

Given two numbers, this function returns the order they are with respect to each other.

### `compare`

```zig
pub fn compare(a: anytype, op: CompareOperator, b: anytype) bool
```

This function does the same thing as comparison operators, however the
operator is a runtime-known enum value. Works on any operands that
support comparison operators.

### `boolMask`

```zig
pub inline fn boolMask(comptime MaskInt: type, value: bool) MaskInt
```

Returns a mask of all ones if value is true,
and a mask of all zeroes if value is false.
Compiles to one instruction for register sized integers.

### `comptimeMod`

```zig
pub fn comptimeMod(num: anytype, comptime denom: comptime_int) IntFittingRange(0, denom - 1)
```

Return the mod of `num` with the smallest integer type

### `sign`

```zig
pub inline fn sign(n: anytype) SignOf(@TypeOf(n))
```

Returns -1, 0, or 1.
Supports integer and float types and vectors of integer and float types.
Unsigned integer types will always return 0 or 1.
The returned integer type is the smallest that fits the possible values.
Branchless.

### `signExtend`

```zig
pub fn signExtend(To: type, n: anytype) To
```

Increases the bit width of an integer by copying the most significant bit.
This results in the input and output having the same arithmetic value, when
interpreted as two's complement integers.

## Error Sets

- **`AlignCastError`**
  

## Constants & Variables

- **`e`**: Euler's number (e)
- **`pi`**: Archimedes' constant (π)
- **`phi`**: Phi or Golden ratio constant (Φ) = (1 + sqrt(5))/2
- **`tau`**: Circle constant (τ)
- **`log2e`**: log2(e)
- **`log10e`**: log10(e)
- **`ln2`**: ln(2)
- **`ln10`**: ln(10)
- **`two_sqrtpi`**: 2/sqrt(π)
- **`sqrt2`**: sqrt(2)
- **`sqrt1_2`**: 1/sqrt(2)
- **`rad_per_deg`**: pi/180.0
- **`deg_per_rad`**: 180.0/pi
- **`FloatRepr`**: 
- **`floatExponentBits`**: 
- **`floatMantissaBits`**: 
- **`floatFractionalBits`**: 
- **`floatExponentMin`**: 
- **`floatExponentMax`**: 
- **`floatTrueMin`**: 
- **`floatMin`**: 
- **`floatMax`**: 
- **`floatEps`**: 
- **`floatEpsAt`**: 
- **`inf`**: 
- **`long_double`**: 
- **`nan`**: 
- **`snan`**: 
- **`isNan`**: 
- **`isSignalNan`**: 
- **`frexp`**: 
- **`Frexp`**: 
- **`modf`**: 
- **`Modf`**: 
- **`copysign`**: 
- **`isFinite`**: 
- **`isInf`**: 
- **`isPositiveInf`**: 
- **`isNegativeInf`**: 
- **`isPositiveZero`**: 
- **`isNegativeZero`**: 
- **`isNormal`**: 
- **`nextAfter`**: 
- **`signbit`**: 
- **`scalbn`**: 
- **`ldexp`**: 
- **`pow`**: 
- **`powi`**: 
- **`sqrt`**: 
- **`cbrt`**: 
- **`acos`**: 
- **`asin`**: 
- **`atan`**: 
- **`atan2`**: 
- **`hypot`**: 
- **`expm1`**: 
- **`ilogb`**: 
- **`log`**: 
- **`log2`**: 
- **`log10`**: 
- **`log10_int`**: 
- **`log_int`**: 
- **`log1p`**: 
- **`asinh`**: 
- **`acosh`**: 
- **`atanh`**: 
- **`sinh`**: 
- **`cosh`**: 
- **`tanh`**: 
- **`gcd`**: 
- **`lcm`**: 
- **`gamma`**: 
- **`lgamma`**: 
- **`complex`**: 
- **`Complex`**: 
- **`big`**: 

