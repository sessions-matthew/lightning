# Floats

> Zig 0.17.0 Language Reference — Section 11 of 53  
> [← Back to Language Reference Index](../langref.md)

<a id="Floats"></a>
## Floats

Zig has the following floating point types:

- `f16` - IEEE-754-2008 binary16
- `f32` - IEEE-754-2008 binary32
- `f64` - IEEE-754-2008 binary64
- `f80` - IEEE-754-2008 80-bit extended precision
- `f128` - IEEE-754-2008 binary128
- `c_longdouble` - matches `long double` for the target C ABI

<a id="Float-Literals"></a>
### Float Literals

Float literals have type `comptime_float` which is guaranteed to have
the same precision and operations of the largest other floating point type, which is
`f128`.

Float literals [coerce](#Type-Coercion) to any floating point type,
and to any [integer](#Integers) type when there is no fractional component.

**`float_literals.zig`**
```zig
const floating_point = 123.0E+77;
const another_float = 123.0;
const yet_another = 123.0e+77;

const hex_floating_point = 0x103.70p-5;
const another_hex_float = 0x103.70;
const yet_another_hex_float = 0x103.70P-5;

// underscores may be placed between two digits as a visual separator
const lightspeed = 299_792_458.000_000;
const nanosecond = 0.000_000_001;
const more_hex = 0x1234_5678.9ABC_CDEFp-10;
```

There is no syntax for NaN, infinity, or negative infinity. For these special values,
one must use the standard library:

**`float_special_values.zig`**
```zig
const std = @import("std");

const inf = std.math.inf(f32);
const negative_inf = -std.math.inf(f64);
const nan = std.math.nan(f128);
```

<a id="Floating-Point-Operations"></a>
### Floating Point Operations

By default floating point operations use `.strict` mode,
but you can switch to `.optimized` mode on a per-block basis:

**`float_mode_obj.zig`**
```zig
const std = @import("std");
const big = @as(f64, 1 << 40);

export fn foo_strict(x: f64) f64 {
    return x + big - big;
}

export fn foo_optimized(x: f64) f64 {
    @setFloatMode(.optimized);
    return x + big - big;
}
```

```sh
$ zig build-obj float_mode_obj.zig -O fast
```

For this test we have to separate code into two object files -
otherwise the optimizer figures out all the values at compile-time,
which operates in strict mode.

**`float_mode_exe.zig`**
```zig
const print = @import("std").debug.print;

extern fn foo_strict(x: f64) f64;
extern fn foo_optimized(x: f64) f64;

pub fn main() void {
    const x = 0.001;
    print("optimized = {}\n", .{foo_optimized(x)});
    print("strict = {}\n", .{foo_strict(x)});
}
```

```sh
$ zig build-exe float_mode_exe.zig float_mode_obj.o -O fast
$ ./float_mode_exe
optimized = 0.001
strict = 0.0009765625
```

See also:

- [@setFloatMode](#setFloatMode)
- [Division by Zero](#Division-by-Zero)
