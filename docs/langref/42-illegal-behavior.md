# Illegal Behavior

> Zig 0.17.0 Language Reference — Section 42 of 53  
> [← Back to Language Reference Index](../langref.md)

<a id="Illegal-Behavior"></a>
## Illegal Behavior

Many operations in Zig trigger what is known as "Illegal Behavior" (IB). If Illegal Behavior is detected at
compile-time, Zig emits a compile error and refuses to continue. Otherwise, when Illegal Behavior is not caught
at compile-time, it falls into one of two categories.

Some Illegal Behavior is *safety-checked*: this means that the compiler will insert "safety checks"
anywhere that the Illegal Behavior may occur at runtime, to determine whether it is about to happen. If it
is, the safety check "fails", which triggers a panic.

All other Illegal Behavior is *unchecked*, meaning the compiler is unable to insert safety checks for
it. If Unchecked Illegal Behavior is invoked at runtime, anything can happen: usually that will be some kind of
crash, but the optimizer is free to make Unchecked Illegal Behavior do anything, such as calling arbitrary functions
or clobbering arbitrary data. This is similar to the concept of "undefined behavior" in some other languages. Note that
Unchecked Illegal Behavior still always results in a compile error if evaluated at [comptime](#comptime), because the Zig
compiler is able to perform more sophisticated checks at compile-time than at runtime.

Most Illegal Behavior is safety-checked. However, to facilitate optimizations, safety checks are disabled by default
in the [fast](#fast) and [small](#small) optimization modes. Safety checks can also be enabled or disabled
on a per-block basis, overriding the default for the current optimization mode, using [@setRuntimeSafety](#setRuntimeSafety). When
safety checks are disabled, Safety-Checked Illegal Behavior behaves like Unchecked Illegal Behavior; that is, any behavior
may result from invoking it.

When a safety check fails, Zig's default panic handler crashes with a stack trace, like this:

**`test_illegal_behavior.zig`**
```zig
test "safety check" {
    unreachable;
}
```

```sh
$ zig test test_illegal_behavior.zig
1/1 test_illegal_behavior.test.safety check...thread 34658 panic: reached unreachable code
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/.zig-cache/tmp/4ec78cf3e9600ed/../../../doc/langref/test_illegal_behavior.zig:2:5: 0x1046e33af in test.safety check (test)
    unreachable;
    ^
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/lib/compiler/test_runner.zig:295:25: 0x1046bf1c3 in mainTerminal (test)
        if (test_fn.func()) |_| {
                        ^
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/lib/compiler/test_runner.zig:74:28: 0x1046beca3 in main (test)
        return mainTerminal(init);
                           ^
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/lib/std/start.zig:789:88: 0x1046bcbd3 in callMain (test)
    if (fn_info.param_types[0].? == std.process.Init.Minimal) return wrapMain(root.main(.{
                                                                                       ^
???:?:?: 0x18cd53e7f in start (/usr/lib/dyld)
error: the following test command terminated with signal ABRT:
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/.zig-cache/o/62c07afac7dc1de0d4ee61e4f4fe7aaf/test --seed=0xb4148647
```

<a id="Reaching-Unreachable-Code"></a>
### Reaching Unreachable Code

At compile-time:

**`test_comptime_reaching_unreachable.zig`**
```zig
comptime {
    assert(false);
}
fn assert(ok: bool) void {
    if (!ok) unreachable; // assertion failure
}
```

```sh
$ zig test test_comptime_reaching_unreachable.zig
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/doc/langref/test_comptime_reaching_unreachable.zig:5:14: error: reached unreachable code
    if (!ok) unreachable; // assertion failure
             ^~~~~~~~~~~
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/doc/langref/test_comptime_reaching_unreachable.zig:2:11: note: called at comptime here
    assert(false);
    ~~~~~~^~~~~~~
```

At runtime:

**`runtime_reaching_unreachable.zig`**
```zig
const std = @import("std");

pub fn main() void {
    std.debug.assert(false);
}
```

```sh
$ zig build-exe runtime_reaching_unreachable.zig
$ ./runtime_reaching_unreachable
thread 35512 panic: reached unreachable code
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/lib/std/debug.zig:442:14: 0x1048269e3 in assert (runtime_reaching_unreachable)
    if (!ok) unreachable; // assertion failure
             ^
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/.zig-cache/tmp/3e5d512951b78aa4/../../../doc/langref/runtime_reaching_unreachable.zig:4:21: 0x1049311a3 in main (runtime_reaching_unreachable)
    std.debug.assert(false);
                    ^
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/lib/std/start.zig:788:64: 0x10493113b in callMain (runtime_reaching_unreachable)
    if (fn_info.param_types.len == 0) return wrapMain(root.main());
                                                               ^
???:?:?: 0x18cd53e7f in start (/usr/lib/dyld)
(process terminated by signal)
```

<a id="Index-out-of-Bounds"></a>
### Index out of Bounds

At compile-time:

**`test_comptime_index_out_of_bounds.zig`**
```zig
comptime {
    const array: [5]u8 = "hello".*;
    const garbage = array[5];
    _ = garbage;
}
```

```sh
$ zig test test_comptime_index_out_of_bounds.zig
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/doc/langref/test_comptime_index_out_of_bounds.zig:3:27: error: index 5 outside array of length 5
    const garbage = array[5];
                          ^
```

At runtime:

**`runtime_index_out_of_bounds.zig`**
```zig
pub fn main() void {
    const x = foo("hello");
    _ = x;
}

fn foo(x: []const u8) u8 {
    return x[5];
}
```

```sh
$ zig build-exe runtime_index_out_of_bounds.zig
$ ./runtime_index_out_of_bounds
thread 37294 panic: index out of bounds: index 5, len 5
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/.zig-cache/tmp/bceac7ea052f4800/../../../doc/langref/runtime_index_out_of_bounds.zig:7:13: 0x1042fd393 in foo (runtime_index_out_of_bounds)
    return x[5];
            ^
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/.zig-cache/tmp/bceac7ea052f4800/../../../doc/langref/runtime_index_out_of_bounds.zig:2:18: 0x1042fd1af in main (runtime_index_out_of_bounds)
    const x = foo("hello");
                 ^
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/lib/std/start.zig:788:64: 0x1042fd13b in callMain (runtime_index_out_of_bounds)
    if (fn_info.param_types.len == 0) return wrapMain(root.main());
                                                               ^
???:?:?: 0x18cd53e7f in start (/usr/lib/dyld)
(process terminated by signal)
```

<a id="Cast-Negative-Number-to-Unsigned-Integer"></a>
### Cast Negative Number to Unsigned Integer

At compile-time:

**`test_comptime_invalid_cast.zig`**
```zig
comptime {
    const value: i32 = -1;
    const unsigned: u32 = @intCast(value);
    _ = unsigned;
}
```

```sh
$ zig test test_comptime_invalid_cast.zig
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/doc/langref/test_comptime_invalid_cast.zig:3:36: error: type 'u32' cannot represent integer value '-1'
    const unsigned: u32 = @intCast(value);
                                   ^~~~~
```

At runtime:

**`runtime_invalid_cast.zig`**
```zig
const std = @import("std");

pub fn main() void {
    var value: i32 = -1; // runtime-known
    _ = &value;
    const unsigned: u32 = @intCast(value);
    std.debug.print("value: {}\n", .{unsigned});
}
```

```sh
$ zig build-exe runtime_invalid_cast.zig
$ ./runtime_invalid_cast
thread 36396 panic: integer does not fit in destination type
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/.zig-cache/tmp/e2ffa61292d009b7/../../../doc/langref/runtime_invalid_cast.zig:6:27: 0x1004f51cf in main (runtime_invalid_cast)
    const unsigned: u32 = @intCast(value);
                          ^
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/lib/std/start.zig:788:64: 0x1004f513b in callMain (runtime_invalid_cast)
    if (fn_info.param_types.len == 0) return wrapMain(root.main());
                                                               ^
???:?:?: 0x18cd53e7f in start (/usr/lib/dyld)
(process terminated by signal)
```

To obtain the maximum value of an unsigned integer, use `std.math.maxInt`.

<a id="Cast-Truncates-Data"></a>
### Cast Truncates Data

At compile-time:

**`test_comptime_invalid_cast_truncate.zig`**
```zig
comptime {
    const spartan_count: u16 = 300;
    const byte: u8 = @intCast(spartan_count);
    _ = byte;
}
```

```sh
$ zig test test_comptime_invalid_cast_truncate.zig
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/doc/langref/test_comptime_invalid_cast_truncate.zig:3:31: error: type 'u8' cannot represent integer value '300'
    const byte: u8 = @intCast(spartan_count);
                              ^~~~~~~~~~~~~
```

At runtime:

**`runtime_invalid_cast_truncate.zig`**
```zig
const std = @import("std");

pub fn main() void {
    var spartan_count: u16 = 300; // runtime-known
    _ = &spartan_count;
    const byte: u8 = @intCast(spartan_count);
    std.debug.print("value: {}\n", .{byte});
}
```

```sh
$ zig build-exe runtime_invalid_cast_truncate.zig
$ ./runtime_invalid_cast_truncate
thread 34014 panic: integer does not fit in destination type
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/.zig-cache/tmp/b40408d8f249cadb/../../../doc/langref/runtime_invalid_cast_truncate.zig:6:22: 0x102ee11d3 in main (runtime_invalid_cast_truncate)
    const byte: u8 = @intCast(spartan_count);
                     ^
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/lib/std/start.zig:788:64: 0x102ee113b in callMain (runtime_invalid_cast_truncate)
    if (fn_info.param_types.len == 0) return wrapMain(root.main());
                                                               ^
???:?:?: 0x18cd53e7f in start (/usr/lib/dyld)
(process terminated by signal)
```

To truncate bits, use [@truncate](#truncate).

<a id="Integer-Overflow"></a>
### Integer Overflow

<a id="Default-Operations"></a>
#### Default Operations

The following operators can cause integer overflow:

- `+` (addition)
- `-` (subtraction)
- `-` (negation)
- `*` (multiplication)
- `/` (division)
- [@divTrunc](#divTrunc) (division)
- [@divFloor](#divFloor) (division)
- [@divCeil](#divCeil) (division)
- [@divExact](#divExact) (division)

Example with addition at compile-time:

**`test_comptime_overflow.zig`**
```zig
comptime {
    var byte: u8 = 255;
    byte += 1;
}
```

```sh
$ zig test test_comptime_overflow.zig
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/doc/langref/test_comptime_overflow.zig:3:10: error: overflow of integer type 'u8' with value '256'
    byte += 1;
    ~~~~~^~~~
```

At runtime:

**`runtime_overflow.zig`**
```zig
const std = @import("std");

pub fn main() void {
    var byte: u8 = 255;
    byte += 1;
    std.debug.print("value: {}\n", .{byte});
}
```

```sh
$ zig build-exe runtime_overflow.zig
$ ./runtime_overflow
thread 35349 panic: integer overflow
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/.zig-cache/tmp/7bc4a4e6fd69f5c0/../../../doc/langref/runtime_overflow.zig:5:10: 0x1028a51db in main (runtime_overflow)
    byte += 1;
         ^
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/lib/std/start.zig:788:64: 0x1028a513b in callMain (runtime_overflow)
    if (fn_info.param_types.len == 0) return wrapMain(root.main());
                                                               ^
???:?:?: 0x18cd53e7f in start (/usr/lib/dyld)
(process terminated by signal)
```

<a id="Standard-Library-Math-Functions"></a>
#### Standard Library Math Functions

These functions provided by the standard library return possible errors.

- `@import("std").math.add`
- `@import("std").math.sub`
- `@import("std").math.mul`
- `@import("std").math.divTrunc`
- `@import("std").math.divFloor`
- `@import("std").math.divCeil`
- `@import("std").math.divExact`
- `@import("std").math.shl`

Example of catching an overflow for addition:

**`math_add.zig`**
```zig
const math = @import("std").math;
const print = @import("std").debug.print;
pub fn main() !void {
    var byte: u8 = 255;

    byte = if (math.add(u8, byte, 1)) |result| result else |err| {
        print("unable to add one: {s}\n", .{@errorName(err)});
        return err;
    };

    print("result: {}\n", .{byte});
}
```

```sh
$ zig build-exe math_add.zig
$ ./math_add
unable to add one: Overflow
error: Overflow
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/lib/std/math.zig:571:21: 0x104342b5f in add__func_853 (math_add)
    if (ov[1] != 0) return error.Overflow;
                    ^
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/.zig-cache/tmp/7992309b2c49fd78/../../../doc/langref/math_add.zig:8:9: 0x10434100b in main (math_add)
        return err;
        ^
```

<a id="Builtin-Overflow-Functions"></a>
#### Builtin Overflow Functions

These builtins return a tuple containing whether there was an overflow
(as a `u1`) and the possibly overflowed bits of the operation:

- [@addWithOverflow](#addWithOverflow)
- [@subWithOverflow](#subWithOverflow)
- [@mulWithOverflow](#mulWithOverflow)
- [@shlWithOverflow](#shlWithOverflow)

Example of [@addWithOverflow](#addWithOverflow):

**`addWithOverflow_builtin.zig`**
```zig
const print = @import("std").debug.print;
pub fn main() void {
    const byte: u8 = 255;

    const ov = @addWithOverflow(byte, 10);
    if (ov[1] != 0) {
        print("overflowed result: {}\n", .{ov[0]});
    } else {
        print("result: {}\n", .{ov[0]});
    }
}
```

```sh
$ zig build-exe addWithOverflow_builtin.zig
$ ./addWithOverflow_builtin
overflowed result: 9
```

<a id="Wrapping-Operations"></a>
#### Wrapping Operations

These operations have guaranteed wraparound semantics.

- `+%` (wraparound addition)
- `-%` (wraparound subtraction)
- `-%` (wraparound negation)
- `*%` (wraparound multiplication)

**`test_wraparound_semantics.zig`**
```zig
const std = @import("std");
const expectEqual = std.testing.expectEqual;
const minInt = std.math.minInt;
const maxInt = std.math.maxInt;

test "wraparound addition and subtraction" {
    const x: i32 = maxInt(i32);
    const min_val = x +% 1;
    try expectEqual(minInt(i32), min_val);
    const max_val = min_val -% 1;
    try expectEqual(maxInt(i32), max_val);
}
```

```sh
$ zig test test_wraparound_semantics.zig
1/1 test_wraparound_semantics.test.wraparound addition and subtraction...OK
All 1 tests passed.
```

<a id="Exact-Left-Shift-Overflow"></a>
### Exact Left Shift Overflow

At compile-time:

**`test_comptime_shlExact_overflow.zig`**
```zig
comptime {
    const x = @shlExact(@as(u8, 0b01010101), 2);
    _ = x;
}
```

```sh
$ zig test test_comptime_shlExact_overflow.zig
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/doc/langref/test_comptime_shlExact_overflow.zig:2:15: error: overflow of integer type 'u8' with value '340'
    const x = @shlExact(@as(u8, 0b01010101), 2);
              ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
```

At runtime:

**`runtime_shlExact_overflow.zig`**
```zig
const std = @import("std");

pub fn main() void {
    var x: u8 = 0b01010101; // runtime-known
    _ = &x;
    const y = @shlExact(x, 2);
    std.debug.print("value: {}\n", .{y});
}
```

```sh
$ zig build-exe runtime_shlExact_overflow.zig
$ ./runtime_shlExact_overflow
thread 35954 panic: left shift overflowed bits
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/.zig-cache/tmp/74d61be668d27c70/../../../doc/langref/runtime_shlExact_overflow.zig:6:5: 0x1022c9243 in main (runtime_shlExact_overflow)
    const y = @shlExact(x, 2);
    ^
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/lib/std/start.zig:788:64: 0x1022c913b in callMain (runtime_shlExact_overflow)
    if (fn_info.param_types.len == 0) return wrapMain(root.main());
                                                               ^
???:?:?: 0x18cd53e7f in start (/usr/lib/dyld)
(process terminated by signal)
```

<a id="Exact-Right-Shift-Overflow"></a>
### Exact Right Shift Overflow

At compile-time:

**`test_comptime_shrExact_overflow.zig`**
```zig
comptime {
    const x = @shrExact(@as(u8, 0b10101010), 2);
    _ = x;
}
```

```sh
$ zig test test_comptime_shrExact_overflow.zig
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/doc/langref/test_comptime_shrExact_overflow.zig:2:15: error: exact shift shifted out 1 bits
    const x = @shrExact(@as(u8, 0b10101010), 2);
              ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
```

At runtime:

**`runtime_shrExact_overflow.zig`**
```zig
const builtin = @import("builtin");
const std = @import("std");

pub fn main() void {
    var x: u8 = 0b10101010; // runtime-known
    _ = &x;
    const y = @shrExact(x, 2);
    std.debug.print("value: {}\n", .{y});

    if ((builtin.cpu.arch.isPowerPC() or builtin.cpu.arch.isRISCV() or builtin.cpu.arch.isLoongArch() or builtin.cpu.arch == .s390x) and builtin.zig_backend == .stage2_llvm) @panic("https://github.com/ziglang/zig/issues/24304");
}
```

```sh
$ zig build-exe runtime_shrExact_overflow.zig
$ ./runtime_shrExact_overflow
thread 33770 panic: right shift overflowed bits
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/.zig-cache/tmp/e14412f32521a66d/../../../doc/langref/runtime_shrExact_overflow.zig:7:5: 0x104c7d203 in main (runtime_shrExact_overflow)
    const y = @shrExact(x, 2);
    ^
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/lib/std/start.zig:788:64: 0x104c7d13b in callMain (runtime_shrExact_overflow)
    if (fn_info.param_types.len == 0) return wrapMain(root.main());
                                                               ^
???:?:?: 0x18cd53e7f in start (/usr/lib/dyld)
(process terminated by signal)
```

<a id="Division-by-Zero"></a>
### Division by Zero

At compile-time:

**`test_comptime_division_by_zero.zig`**
```zig
comptime {
    const a: i32 = 1;
    const b: i32 = 0;
    const c = a / b;
    _ = c;
}
```

```sh
$ zig test test_comptime_division_by_zero.zig
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/doc/langref/test_comptime_division_by_zero.zig:4:19: error: division by zero here causes illegal behavior
    const c = a / b;
                  ^
```

At runtime:

**`runtime_division_by_zero.zig`**
```zig
const std = @import("std");

pub fn main() void {
    var a: u32 = 1;
    var b: u32 = 0;
    _ = .{ &a, &b };
    const c = a / b;
    std.debug.print("value: {}\n", .{c});
}
```

```sh
$ zig build-exe runtime_division_by_zero.zig
$ ./runtime_division_by_zero
thread 37952 panic: division by zero
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/.zig-cache/tmp/1b61586793d24ef9/../../../doc/langref/runtime_division_by_zero.zig:7:17: 0x102d2d22b in main (runtime_division_by_zero)
    const c = a / b;
                ^
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/lib/std/start.zig:788:64: 0x102d2d13b in callMain (runtime_division_by_zero)
    if (fn_info.param_types.len == 0) return wrapMain(root.main());
                                                               ^
???:?:?: 0x18cd53e7f in start (/usr/lib/dyld)
(process terminated by signal)
```

<a id="Remainder-Division-by-Zero"></a>
### Remainder Division by Zero

At compile-time:

**`test_comptime_remainder_division_by_zero.zig`**
```zig
comptime {
    const a: i32 = 10;
    const b: i32 = 0;
    const c = a % b;
    _ = c;
}
```

```sh
$ zig test test_comptime_remainder_division_by_zero.zig
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/doc/langref/test_comptime_remainder_division_by_zero.zig:4:19: error: division by zero here causes illegal behavior
    const c = a % b;
                  ^
```

At runtime:

**`runtime_remainder_division_by_zero.zig`**
```zig
const std = @import("std");

pub fn main() void {
    var a: u32 = 10;
    var b: u32 = 0;
    _ = .{ &a, &b };
    const c = a % b;
    std.debug.print("value: {}\n", .{c});
}
```

```sh
$ zig build-exe runtime_remainder_division_by_zero.zig
$ ./runtime_remainder_division_by_zero
thread 32907 panic: division by zero
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/.zig-cache/tmp/5a2df5e169093f72/../../../doc/langref/runtime_remainder_division_by_zero.zig:7:17: 0x10249d233 in main (runtime_remainder_division_by_zero)
    const c = a % b;
                ^
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/lib/std/start.zig:788:64: 0x10249d13b in callMain (runtime_remainder_division_by_zero)
    if (fn_info.param_types.len == 0) return wrapMain(root.main());
                                                               ^
???:?:?: 0x18cd53e7f in start (/usr/lib/dyld)
(process terminated by signal)
```

<a id="Exact-Division-Remainder"></a>
### Exact Division Remainder

At compile-time:

**`test_comptime_divExact_remainder.zig`**
```zig
comptime {
    const a: u32 = 10;
    const b: u32 = 3;
    const c = @divExact(a, b);
    _ = c;
}
```

```sh
$ zig test test_comptime_divExact_remainder.zig
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/doc/langref/test_comptime_divExact_remainder.zig:4:15: error: exact division produced remainder
    const c = @divExact(a, b);
              ^~~~~~~~~~~~~~~
```

At runtime:

**`runtime_divExact_remainder.zig`**
```zig
const std = @import("std");

pub fn main() void {
    var a: u32 = 10;
    var b: u32 = 3;
    _ = .{ &a, &b };
    const c = @divExact(a, b);
    std.debug.print("value: {}\n", .{c});
}
```

```sh
$ zig build-exe runtime_divExact_remainder.zig
$ ./runtime_divExact_remainder
thread 34552 panic: exact division produced remainder
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/.zig-cache/tmp/d91cfc3e51b67f4b/../../../doc/langref/runtime_divExact_remainder.zig:7:15: 0x100605257 in main (runtime_divExact_remainder)
    const c = @divExact(a, b);
              ^
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/lib/std/start.zig:788:64: 0x10060513b in callMain (runtime_divExact_remainder)
    if (fn_info.param_types.len == 0) return wrapMain(root.main());
                                                               ^
???:?:?: 0x18cd53e7f in start (/usr/lib/dyld)
(process terminated by signal)
```

<a id="Attempt-to-Unwrap-Null"></a>
### Attempt to Unwrap Null

At compile-time:

**`test_comptime_unwrap_null.zig`**
```zig
comptime {
    const optional_number: ?i32 = null;
    const number = optional_number.?;
    _ = number;
}
```

```sh
$ zig test test_comptime_unwrap_null.zig
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/doc/langref/test_comptime_unwrap_null.zig:3:35: error: unable to unwrap null
    const number = optional_number.?;
                   ~~~~~~~~~~~~~~~^~
```

At runtime:

**`runtime_unwrap_null.zig`**
```zig
const std = @import("std");

pub fn main() void {
    var optional_number: ?i32 = null;
    _ = &optional_number;
    const number = optional_number.?;
    std.debug.print("value: {}\n", .{number});
}
```

```sh
$ zig build-exe runtime_unwrap_null.zig
$ ./runtime_unwrap_null
thread 35733 panic: attempt to use null value
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/.zig-cache/tmp/4a5208c4b39730e/../../../doc/langref/runtime_unwrap_null.zig:6:35: 0x102df1233 in main (runtime_unwrap_null)
    const number = optional_number.?;
                                  ^
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/lib/std/start.zig:788:64: 0x102df113b in callMain (runtime_unwrap_null)
    if (fn_info.param_types.len == 0) return wrapMain(root.main());
                                                               ^
???:?:?: 0x18cd53e7f in start (/usr/lib/dyld)
(process terminated by signal)
```

One way to avoid this crash is to test for null instead of assuming non-null, with
the `if` expression:

**`testing_null_with_if.zig`**
```zig
const print = @import("std").debug.print;
pub fn main() void {
    const optional_number: ?i32 = null;

    if (optional_number) |number| {
        print("got number: {}\n", .{number});
    } else {
        print("it's null\n", .{});
    }
}
```

```sh
$ zig build-exe testing_null_with_if.zig
$ ./testing_null_with_if
it's null
```

See also:

- [Optionals](#Optionals)

<a id="Attempt-to-Unwrap-Error"></a>
### Attempt to Unwrap Error

At compile-time:

**`test_comptime_unwrap_error.zig`**
```zig
comptime {
    const number = getNumberOrFail() catch unreachable;
    _ = number;
}

fn getNumberOrFail() !i32 {
    return error.UnableToReturnNumber;
}
```

```sh
$ zig test test_comptime_unwrap_error.zig
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/doc/langref/test_comptime_unwrap_error.zig:2:44: error: caught unexpected error 'UnableToReturnNumber'
    const number = getNumberOrFail() catch unreachable;
                                           ^~~~~~~~~~~
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/doc/langref/test_comptime_unwrap_error.zig:7:18: note: error returned here
    return error.UnableToReturnNumber;
                 ^~~~~~~~~~~~~~~~~~~~
```

At runtime:

**`runtime_unwrap_error.zig`**
```zig
const std = @import("std");

pub fn main() void {
    const number = getNumberOrFail() catch unreachable;
    std.debug.print("value: {}\n", .{number});
}

fn getNumberOrFail() !i32 {
    return error.UnableToReturnNumber;
}
```

```sh
$ zig build-exe runtime_unwrap_error.zig
$ ./runtime_unwrap_error
thread 35955 panic: attempt to unwrap error: UnableToReturnNumber
error return context:
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/.zig-cache/tmp/cff0242906ab4007/../../../doc/langref/runtime_unwrap_error.zig:9:5: 0x100ae51a3 in getNumberOrFail (runtime_unwrap_error)
    return error.UnableToReturnNumber;
    ^

stack trace:
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/.zig-cache/tmp/cff0242906ab4007/../../../doc/langref/runtime_unwrap_error.zig:4:44: 0x100ae5253 in main (runtime_unwrap_error)
    const number = getNumberOrFail() catch unreachable;
                                           ^
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/lib/std/start.zig:788:64: 0x100ae513b in callMain (runtime_unwrap_error)
    if (fn_info.param_types.len == 0) return wrapMain(root.main());
                                                               ^
???:?:?: 0x18cd53e7f in start (/usr/lib/dyld)
(process terminated by signal)
```

One way to avoid this crash is to test for an error instead of assuming a successful result, with
the `if` expression:

**`testing_error_with_if.zig`**
```zig
const print = @import("std").debug.print;

pub fn main() void {
    const result = getNumberOrFail();

    if (result) |number| {
        print("got number: {}\n", .{number});
    } else |err| {
        print("got error: {s}\n", .{@errorName(err)});
    }
}

fn getNumberOrFail() !i32 {
    return error.UnableToReturnNumber;
}
```

```sh
$ zig build-exe testing_error_with_if.zig
$ ./testing_error_with_if
got error: UnableToReturnNumber
```

See also:

- [Errors](#Errors)

<a id="Invalid-Error-Code"></a>
### Invalid Error Code

At compile-time:

**`test_comptime_invalid_error_code.zig`**
```zig
comptime {
    _ = @errorFromInt(12345);
}
```

```sh
$ zig test test_comptime_invalid_error_code.zig
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/doc/langref/test_comptime_invalid_error_code.zig:2:23: error: integer value '12345' represents no error
    _ = @errorFromInt(12345);
                      ^~~~~
```

At runtime:

**`runtime_invalid_error_code.zig`**
```zig
const std = @import("std");

pub fn main() void {
    const err = error.AnError;
    var number = @intFromError(err) + 500;
    _ = &number;
    const invalid_err = @errorFromInt(number);
    std.debug.print("value: {}\n", .{invalid_err});
}
```

```sh
$ zig build-exe runtime_invalid_error_code.zig
$ ./runtime_invalid_error_code
thread 33700 panic: invalid error code
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/.zig-cache/tmp/4583c17554ea1060/../../../doc/langref/runtime_invalid_error_code.zig:7:5: 0x10300524b in main (runtime_invalid_error_code)
    const invalid_err = @errorFromInt(number);
    ^
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/lib/std/start.zig:788:64: 0x10300513b in callMain (runtime_invalid_error_code)
    if (fn_info.param_types.len == 0) return wrapMain(root.main());
                                                               ^
???:?:?: 0x18cd53e7f in start (/usr/lib/dyld)
(process terminated by signal)
```

<a id="Invalid-Enum-Cast"></a>
### Invalid Enum Cast

At compile-time:

**`test_comptime_invalid_enum_cast.zig`**
```zig
const Foo = enum(u2) {
    a,
    b,
    c,
};
comptime {
    const a: u2 = 3;
    const b: Foo = @fromBackingInt(a);
    _ = b;
}
```

```sh
$ zig test test_comptime_invalid_enum_cast.zig
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/doc/langref/test_comptime_invalid_enum_cast.zig:8:20: error: enum 'test_comptime_invalid_enum_cast.Foo' has no tag with value '3'
    const b: Foo = @fromBackingInt(a);
                   ^~~~~~~~~~~~~~~~~~
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/doc/langref/test_comptime_invalid_enum_cast.zig:1:13: note: enum declared here
const Foo = enum(u2) {
            ^~~~
```

At runtime:

**`runtime_invalid_enum_cast.zig`**
```zig
const std = @import("std");

const Foo = enum(u2) {
    a,
    b,
    c,
};

fn foo(a: u2) void {
    const b: Foo = @fromBackingInt(a);
    std.debug.print("value: {s}\n", .{@tagName(b)});
}

pub fn main() void {
    foo(3);
}
```

```sh
$ zig build-exe runtime_invalid_enum_cast.zig
$ ./runtime_invalid_enum_cast
thread 39117 panic: invalid enum value
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/.zig-cache/tmp/8d25b8da37024cae/../../../doc/langref/runtime_invalid_enum_cast.zig:10:20: 0x104bcd34f in foo (runtime_invalid_enum_cast)
    const b: Foo = @fromBackingInt(a);
                   ^
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/.zig-cache/tmp/8d25b8da37024cae/../../../doc/langref/runtime_invalid_enum_cast.zig:15:8: 0x104bcd19f in main (runtime_invalid_enum_cast)
    foo(3);
       ^
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/lib/std/start.zig:788:64: 0x104bcd13b in callMain (runtime_invalid_enum_cast)
    if (fn_info.param_types.len == 0) return wrapMain(root.main());
                                                               ^
???:?:?: 0x18cd53e7f in start (/usr/lib/dyld)
(process terminated by signal)
```

<a id="Invalid-Error-Set-Cast"></a>
### Invalid Error Set Cast

At compile-time:

**`test_comptime_invalid_error_set_cast.zig`**
```zig
const Set1 = error{
    A,
    B,
};
const Set2 = error{
    A,
    C,
};
comptime {
    _ = @as(Set2, @errorCast(Set1.B));
}
```

```sh
$ zig test test_comptime_invalid_error_set_cast.zig
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/doc/langref/test_comptime_invalid_error_set_cast.zig:10:19: error: 'error.B' not a member of error set 'error{A,C}'
    _ = @as(Set2, @errorCast(Set1.B));
                  ^~~~~~~~~~~~~~~~~~
```

At runtime:

**`runtime_invalid_error_set_cast.zig`**
```zig
const std = @import("std");

const Set1 = error{
    A,
    B,
};
const Set2 = error{
    A,
    C,
};
pub fn main() void {
    foo(Set1.B);
}
fn foo(set1: Set1) void {
    const x: Set2 = @errorCast(set1);
    std.debug.print("value: {}\n", .{x});
}
```

```sh
$ zig build-exe runtime_invalid_error_set_cast.zig
$ ./runtime_invalid_error_set_cast
thread 35815 panic: unexpected error code, found error.B
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/.zig-cache/tmp/ea511c6836657a31/../../../doc/langref/runtime_invalid_error_set_cast.zig:15:21: 0x102b31403 in foo (runtime_invalid_error_set_cast)
    const x: Set2 = @errorCast(set1);
                    ^
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/.zig-cache/tmp/ea511c6836657a31/../../../doc/langref/runtime_invalid_error_set_cast.zig:12:8: 0x102b311af in main (runtime_invalid_error_set_cast)
    foo(Set1.B);
       ^
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/lib/std/start.zig:788:64: 0x102b3113b in callMain (runtime_invalid_error_set_cast)
    if (fn_info.param_types.len == 0) return wrapMain(root.main());
                                                               ^
???:?:?: 0x18cd53e7f in start (/usr/lib/dyld)
(process terminated by signal)
```

<a id="Incorrect-Pointer-Alignment"></a>
### Incorrect Pointer Alignment

At compile-time:

**`test_comptime_incorrect_pointer_alignment.zig`**
```zig
comptime {
    const ptr: *align(1) i32 = @ptrFromInt(0x1);
    const aligned: *align(4) i32 = @alignCast(ptr);
    _ = aligned;
}
```

```sh
$ zig test test_comptime_incorrect_pointer_alignment.zig
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/doc/langref/test_comptime_incorrect_pointer_alignment.zig:3:47: error: pointer address 0x1 is not aligned to 4 bytes
    const aligned: *align(4) i32 = @alignCast(ptr);
                                              ^~~
```

At runtime:

**`runtime_incorrect_pointer_alignment.zig`**
```zig
const mem = @import("std").mem;
pub fn main() !void {
    var array align(4) = [_]u32{ 0x11111111, 0x11111111 };
    const bytes = mem.sliceAsBytes(array[0..]);
    if (foo(bytes) != 0x11111111) return error.Wrong;
}
fn foo(bytes: []u8) u32 {
    const slice4 = bytes[1..5];
    const int_slice = mem.bytesAsSlice(u32, @as([]align(4) u8, @alignCast(slice4)));
    return int_slice[0];
}
```

```sh
$ zig build-exe runtime_incorrect_pointer_alignment.zig
$ ./runtime_incorrect_pointer_alignment
thread 37231 panic: incorrect alignment
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/.zig-cache/tmp/fb3e98113afd6e76/../../../doc/langref/runtime_incorrect_pointer_alignment.zig:9:64: 0x102e0a25f in foo (runtime_incorrect_pointer_alignment)
    const int_slice = mem.bytesAsSlice(u32, @as([]align(4) u8, @alignCast(slice4)));
                                                               ^
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/.zig-cache/tmp/fb3e98113afd6e76/../../../doc/langref/runtime_incorrect_pointer_alignment.zig:5:12: 0x102e08f43 in main (runtime_incorrect_pointer_alignment)
    if (foo(bytes) != 0x11111111) return error.Wrong;
           ^
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/lib/std/start.zig:788:64: 0x102e09223 in callMain (runtime_incorrect_pointer_alignment)
    if (fn_info.param_types.len == 0) return wrapMain(root.main());
                                                               ^
???:?:?: 0x18cd53e7f in start (/usr/lib/dyld)
(process terminated by signal)
```

<a id="Wrong-Union-Field-Access"></a>
### Wrong Union Field Access

At compile-time:

**`test_comptime_wrong_union_field_access.zig`**
```zig
comptime {
    var f = Foo{ .int = 42 };
    f.float = 12.34;
}

const Foo = union {
    float: f32,
    int: u32,
};
```

```sh
$ zig test test_comptime_wrong_union_field_access.zig
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/doc/langref/test_comptime_wrong_union_field_access.zig:3:6: error: access of union field 'float' while field 'int' is active
    f.float = 12.34;
    ~^~~~~~
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/doc/langref/test_comptime_wrong_union_field_access.zig:6:13: note: union declared here
const Foo = union {
            ^~~~~
```

At runtime:

**`runtime_wrong_union_field_access.zig`**
```zig
const std = @import("std");

const Foo = union {
    float: f32,
    int: u32,
};

pub fn main() void {
    var f = Foo{ .int = 42 };
    bar(&f);
}

fn bar(f: *Foo) void {
    f.float = 12.34;
    std.debug.print("value: {}\n", .{f.float});
}
```

```sh
$ zig build-exe runtime_wrong_union_field_access.zig
$ ./runtime_wrong_union_field_access
thread 34889 panic: access of union field 'float' while field 'int' is active
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/.zig-cache/tmp/9763cce114b5e7d9/../../../doc/langref/runtime_wrong_union_field_access.zig:14:6: 0x102c0940b in bar (runtime_wrong_union_field_access)
    f.float = 12.34;
     ^
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/.zig-cache/tmp/9763cce114b5e7d9/../../../doc/langref/runtime_wrong_union_field_access.zig:10:8: 0x102c091c3 in main (runtime_wrong_union_field_access)
    bar(&f);
       ^
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/lib/std/start.zig:788:64: 0x102c0913b in callMain (runtime_wrong_union_field_access)
    if (fn_info.param_types.len == 0) return wrapMain(root.main());
                                                               ^
???:?:?: 0x18cd53e7f in start (/usr/lib/dyld)
(process terminated by signal)
```

This safety is not available for `extern` or `packed` unions.

To change the active field of a union, assign the entire union, like this:

**`change_active_union_field.zig`**
```zig
const std = @import("std");

const Foo = union {
    float: f32,
    int: u32,
};

pub fn main() void {
    var f = Foo{ .int = 42 };
    bar(&f);
}

fn bar(f: *Foo) void {
    f.* = Foo{ .float = 12.34 };
    std.debug.print("value: {}\n", .{f.float});
}
```

```sh
$ zig build-exe change_active_union_field.zig
$ ./change_active_union_field
value: 12.34
```

To change the active field of a union when a meaningful value for the field is not known,
use [undefined](#undefined), like this:

**`undefined_active_union_field.zig`**
```zig
const std = @import("std");

const Foo = union {
    float: f32,
    int: u32,
};

pub fn main() void {
    var f = Foo{ .int = 42 };
    f = Foo{ .float = undefined };
    bar(&f);
    std.debug.print("value: {}\n", .{f.float});
}

fn bar(f: *Foo) void {
    f.float = 12.34;
}
```

```sh
$ zig build-exe undefined_active_union_field.zig
$ ./undefined_active_union_field
value: 12.34
```

See also:

- [union](#union)
- [extern union](#extern-union)

<a id="Out-of-Bounds-Float-to-Integer-Cast"></a>
### Out of Bounds Float to Integer Cast

This happens when casting a float to an integer where the float has a value outside the
integer type's range.

At compile-time:

**`test_comptime_out_of_bounds_float_to_integer_cast.zig`**
```zig
comptime {
    const float: f32 = 4294967296;
    const int: i32 = @intFromFloat(float);
    _ = int;
}
```

```sh
$ zig test test_comptime_out_of_bounds_float_to_integer_cast.zig
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/doc/langref/test_comptime_out_of_bounds_float_to_integer_cast.zig:3:36: error: float value '4294967296' cannot be stored in integer type 'i32'
    const int: i32 = @intFromFloat(float);
                                   ^~~~~
```

At runtime:

**`runtime_out_of_bounds_float_to_integer_cast.zig`**
```zig
pub fn main() void {
    var float: f32 = 4294967296; // runtime-known
    _ = &float;
    const int: i32 = @intFromFloat(float);
    _ = int;
}
```

```sh
$ zig build-exe runtime_out_of_bounds_float_to_integer_cast.zig
$ ./runtime_out_of_bounds_float_to_integer_cast
thread 37486 panic: integer part of floating point value out of bounds
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/.zig-cache/tmp/4ede41395c19cdc1/../../../doc/langref/runtime_out_of_bounds_float_to_integer_cast.zig:4:22: 0x1021b51f7 in main (runtime_out_of_bounds_float_to_integer_cast)
    const int: i32 = @intFromFloat(float);
                     ^
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/lib/std/start.zig:788:64: 0x1021b513b in callMain (runtime_out_of_bounds_float_to_integer_cast)
    if (fn_info.param_types.len == 0) return wrapMain(root.main());
                                                               ^
???:?:?: 0x18cd53e7f in start (/usr/lib/dyld)
(process terminated by signal)
```

<a id="Pointer-Cast-Invalid-Null"></a>
### Pointer Cast Invalid Null

This happens when casting a pointer with the address 0 to a pointer which may not have the address 0.
For example, [C Pointers](#C-Pointers), [Optional Pointers](#Optional-Pointers), and [allowzero](#allowzero) pointers
allow address zero, but normal [Pointers](#Pointers) do not.

At compile-time:

**`test_comptime_invalid_null_pointer_cast.zig`**
```zig
comptime {
    const opt_ptr: ?*i32 = null;
    const ptr: *i32 = @ptrCast(opt_ptr);
    _ = ptr;
}
```

```sh
$ zig test test_comptime_invalid_null_pointer_cast.zig
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/doc/langref/test_comptime_invalid_null_pointer_cast.zig:3:32: error: null pointer casted to type '*i32'
    const ptr: *i32 = @ptrCast(opt_ptr);
                               ^~~~~~~
```

At runtime:

**`runtime_invalid_null_pointer_cast.zig`**
```zig
pub fn main() void {
    var opt_ptr: ?*i32 = null;
    _ = &opt_ptr;
    const ptr: *i32 = @ptrCast(opt_ptr);
    _ = ptr;
}
```

```sh
$ zig build-exe runtime_invalid_null_pointer_cast.zig
$ ./runtime_invalid_null_pointer_cast
thread 38785 panic: cast causes pointer to be null
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/.zig-cache/tmp/201c9d8701e9e1a2/../../../doc/langref/runtime_invalid_null_pointer_cast.zig:4:23: 0x104f611d3 in main (runtime_invalid_null_pointer_cast)
    const ptr: *i32 = @ptrCast(opt_ptr);
                      ^
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/lib/std/start.zig:788:64: 0x104f6113b in callMain (runtime_invalid_null_pointer_cast)
    if (fn_info.param_types.len == 0) return wrapMain(root.main());
                                                               ^
???:?:?: 0x18cd53e7f in start (/usr/lib/dyld)
(process terminated by signal)
```
