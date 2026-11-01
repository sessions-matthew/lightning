# Values

> Zig 0.17.0 Language Reference — Section 7 of 53  
> [← Back to Language Reference Index](../langref.md)

<a id="Values"></a>
## Values

**`values.zig`**
```zig
// Top-level declarations are order-independent:
const print = std.debug.print;
const std = @import("std");
const os = std.os;
const assert = std.debug.assert;

// Custom error set definition:
const ExampleErrorSet = error{
    ExampleErrorVariant,
};

pub fn main() void {
    // integers
    const one_plus_one: i32 = 1 + 1;
    print("1 + 1 = {}\n", .{one_plus_one});

    // floats
    const seven_div_three: f32 = 7.0 / 3.0;
    print("7.0 / 3.0 = {}\n", .{seven_div_three});

    // boolean
    print("{}\n{}\n{}\n", .{
        true and false,
        true or false,
        !true,
    });

    // optional
    var optional_value: ?[]const u8 = null;
    assert(optional_value == null);

    print("\noptional 1\ntype: {}\nvalue: {?s}\n", .{
        @TypeOf(optional_value), optional_value,
    });

    optional_value = "hi";
    assert(optional_value != null);

    print("\noptional 2\ntype: {}\nvalue: {?s}\n", .{
        @TypeOf(optional_value), optional_value,
    });

    // error union
    var number_or_error: ExampleErrorSet!i32 = ExampleErrorSet.ExampleErrorVariant;

    print("\nerror union 1\ntype: {}\nvalue: {!}\n", .{
        @TypeOf(number_or_error),
        number_or_error,
    });

    number_or_error = 1234;

    print("\nerror union 2\ntype: {}\nvalue: {!}\n", .{
        @TypeOf(number_or_error), number_or_error,
    });
}
```

```sh
$ zig build-exe values.zig
$ ./values
1 + 1 = 2
7.0 / 3.0 = 2.3333333
false
true
false

optional 1
type: ?[]const u8
value: null

optional 2
type: ?[]const u8
value: hi

error union 1
type: error{ExampleErrorVariant}!i32
value: error.ExampleErrorVariant

error union 2
type: error{ExampleErrorVariant}!i32
value: 1234
```

<a id="Primitive-Types"></a>
### Primitive Types

**Primitive Types**

| Type | C Equivalent | Description |
| --- | --- | --- |
| `i8` | `int8_t` | signed 8-bit integer |
| `u8` | `uint8_t` | unsigned 8-bit integer |
| `i16` | `int16_t` | signed 16-bit integer |
| `u16` | `uint16_t` | unsigned 16-bit integer |
| `i32` | `int32_t` | signed 32-bit integer |
| `u32` | `uint32_t` | unsigned 32-bit integer |
| `i64` | `int64_t` | signed 64-bit integer |
| `u64` | `uint64_t` | unsigned 64-bit integer |
| `i128` | `__int128` | signed 128-bit integer |
| `u128` | `unsigned __int128` | unsigned 128-bit integer |
| `isize` | `intptr_t`, `ssize_t` | signed pointer sized integer |
| `usize` | `uintptr_t`, `size_t` | unsigned pointer sized integer. Also see [#5185](https://github.com/ziglang/zig/issues/5185) |
| `c_char` | `char` | for ABI compatibility with C |
| `c_short` | `short` | for ABI compatibility with C |
| `c_ushort` | `unsigned short` | for ABI compatibility with C |
| `c_int` | `int` | for ABI compatibility with C |
| `c_uint` | `unsigned int` | for ABI compatibility with C |
| `c_long` | `long` | for ABI compatibility with C |
| `c_ulong` | `unsigned long` | for ABI compatibility with C |
| `c_longlong` | `long long` | for ABI compatibility with C |
| `c_ulonglong` | `unsigned long long` | for ABI compatibility with C |
| `c_longdouble` | `long double` | for ABI compatibility with C |
| `f16` | `_Float16` | 16-bit floating point (10-bit mantissa) IEEE-754-2008 binary16 |
| `f32` | `float` | 32-bit floating point (23-bit mantissa) IEEE-754-2008 binary32 |
| `f64` | `double` | 64-bit floating point (52-bit mantissa) IEEE-754-2008 binary64 |
| `f80` | `long double` | 80-bit floating point (64-bit mantissa) IEEE-754-2008 80-bit extended precision |
| `f128` | `_Float128` | 128-bit floating point (112-bit mantissa) IEEE-754-2008 binary128 |
| `bool` | `bool` | `true` or `false` |
| `anyopaque` | `void` | Used for type-erased pointers. |
| `noreturn` | (none) | the type of `break`, `continue`, `return`, `unreachable`, and `while (true) {}` |
| `type` | (none) | the type of types |
| `anyerror` | (none) | an error code |
| `comptime_int` | (none) | Only allowed for [comptime](#comptime)-known values. The type of integer literals. |
| `comptime_float` | (none) | Only allowed for [comptime](#comptime)-known values. The type of float literals. |

In addition to the integer types above, arbitrary bit-width integers can be referenced by using
an identifier of `i` or `u` followed by digits. For example, the identifier
`i7` refers to a signed 7-bit integer. The maximum allowed bit-width of an
integer type is `65535`.

See also:

- [Integers](#Integers)
- [Floats](#Floats)
- [void](#void)
- [Errors](#Errors)
- [@Int](#Int)

<a id="Primitive-Values"></a>
### Primitive Values

**Primitive Values**

| Name | Description |
| --- | --- |
| `true` and `false` | `bool` values |
| `null` | used to set an optional type to `null` |
| `undefined` | used to leave a value unspecified |

See also:

- [Optionals](#Optionals)
- [undefined](#undefined)

<a id="String-Literals-and-Unicode-Code-Point-Literals"></a>
### String Literals and Unicode Code Point Literals

String literals are constant single-item [Pointers](#Pointers) to null-terminated byte arrays.
The type of string literals encodes both the length, and the fact that they are null-terminated,
and thus they can be [coerced](#Type-Coercion) to both [Slices](#Slices) and
[Null-Terminated Pointers](#Sentinel-Terminated-Pointers).
Dereferencing string literals converts them to [Arrays](#Arrays).

Because Zig source code is [UTF-8 encoded](#Source-Encoding), any
non-ASCII bytes appearing within a string literal in source code carry
their UTF-8 meaning into the content of the string in the Zig program;
the bytes are not modified by the compiler. It is possible to embed
non-UTF-8 bytes into a string literal using `\xNN` notation.

Indexing into a string containing non-ASCII bytes returns individual
bytes, whether valid UTF-8 or not.

Unicode code point literals have type `comptime_int`, the same as
[Integer Literals](#Integer-Literals). All [Escape Sequences](#Escape-Sequences) are valid in both string literals
and Unicode code point literals.

**`string_literals.zig`**
```zig
const print = @import("std").debug.print;
const mem = @import("std").mem; // will be used to compare bytes

pub fn main() void {
    const bytes = "hello";
    print("{}\n", .{@TypeOf(bytes)}); // *const [5:0]u8
    print("{d}\n", .{bytes.len}); // 5
    print("{c}\n", .{bytes[1]}); // 'e'
    print("{d}\n", .{bytes[5]}); // 0
    print("{}\n", .{'e' == '\x65'}); // true
    print("{d}\n", .{'\u{1f4a9}'}); // 128169
    print("{d}\n", .{'💯'}); // 128175
    print("{u}\n", .{'⚡'});
    print("{}\n", .{mem.eql(u8, "hello", "h\x65llo")}); // true
    print("{}\n", .{mem.eql(u8, "💯", "\xf0\x9f\x92\xaf")}); // also true
    const invalid_utf8 = "\xff\xfe"; // non-UTF-8 strings are possible with \xNN notation.
    print("0x{x}\n", .{invalid_utf8[1]}); // indexing them returns individual bytes...
    print("0x{x}\n", .{"💯"[1]}); // ...as does indexing part-way through non-ASCII characters
}
```

```sh
$ zig build-exe string_literals.zig
$ ./string_literals
*const [5:0]u8
5
e
0
true
128169
128175
⚡
true
true
0xfe
0x9f
```

See also:

- [Arrays](#Arrays)
- [Source Encoding](#Source-Encoding)

<a id="Escape-Sequences"></a>
#### Escape Sequences

**Escape Sequences**

| Escape Sequence | Name |
| --- | --- |
| `\n` | Newline |
| `\r` | Carriage Return |
| `\t` | Tab |
| `\\` | Backslash |
| `\'` | Single Quote |
| `\"` | Double Quote |
| `\xNN` | hexadecimal 8-bit byte value (2 digits) |
| `\u{NNNNNN}` | hexadecimal Unicode scalar value UTF-8 encoded (1 or more digits) |

Note that the maximum valid Unicode scalar value is `0x10ffff`.

<a id="Multiline-String-Literals"></a>
#### Multiline String Literals

Multiline string literals have no escapes and can span across multiple lines.
To start a multiline string literal, use the `\\` token. Just like a comment,
the string literal goes until the end of the line. The end of the line is
not included in the string literal.
However, if the next line begins with `\\` then a newline is appended and
the string literal continues.

**`multiline_string_literals.zig`**
```zig
const hello_world_in_c =
    \\#include <stdio.h>
    \\
    \\int main(int argc, char **argv) {
    \\    printf("hello world\n");
    \\    return 0;
    \\}
;
```

See also:

- [@embedFile](#embedFile)

<a id="Assignment"></a>
### Assignment

Use the `const` keyword to assign a value to an identifier:

**`constant_identifier_cannot_change.zig`**
```zig
const x = 1234;

fn foo() void {
    // It works at file scope as well as inside functions.
    const y = 5678;

    // Once assigned, an identifier cannot be changed.
    y += 1;
}

pub fn main() void {
    foo();
}
```

```sh
$ zig build-exe constant_identifier_cannot_change.zig
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/doc/langref/constant_identifier_cannot_change.zig:8:5: error: cannot assign to constant
    y += 1;
    ^
referenced by:
    main: /private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/doc/langref/constant_identifier_cannot_change.zig:12:8
    callMain [inlined]: /private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/lib/std/start.zig:788:64
    callMainWithArgs [inlined]: /private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/lib/std/start.zig:729:20
    main: /private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/lib/std/start.zig:754:28
    1 reference(s) hidden; use '-freference-trace=5' to see all references
```

`const` applies to all of the bytes that the identifier immediately addresses. [Pointers](#Pointers) have their own const-ness.

If you need a variable that you can modify, use the `var` keyword:

**`mutable_var.zig`**
```zig
const print = @import("std").debug.print;

pub fn main() void {
    var y: i32 = 5678;

    y += 1;

    print("{d}", .{y});
}
```

```sh
$ zig build-exe mutable_var.zig
$ ./mutable_var
5679
```

Variables must be initialized:

**`var_must_be_initialized.zig`**
```zig
pub fn main() void {
    var x: i32;

    x = 1;
}
```

```sh
$ zig build-exe var_must_be_initialized.zig
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/doc/langref/var_must_be_initialized.zig:2:15: error: expected '=', found ';'
    var x: i32;
              ^
```

<a id="undefined"></a>
#### undefined

Use `undefined` to leave variables uninitialized:

**`assign_undefined.zig`**
```zig
const print = @import("std").debug.print;

pub fn main() void {
    var x: i32 = undefined;
    x = 1;
    print("{d}", .{x});
}
```

```sh
$ zig build-exe assign_undefined.zig
$ ./assign_undefined
1
```

`undefined` can be [coerced](#Type-Coercion) to any type.
Once this happens, it is no longer possible to detect that the value is `undefined`.
`undefined` means the value could be anything, even something that is nonsense
according to the type. Translated into English, `undefined` means "Not a meaningful
value. Using this value would be a bug. The value will be unused, or overwritten before being used."

In [debug](#debug) and [safe](#safe) mode, Zig writes `0xaa` bytes to undefined memory. This is to catch
bugs early, and to help detect use of undefined memory in a debugger. However, this behavior is only an
implementation feature, not a language semantic, so it is not guaranteed to be observable to code.

<a id="Destructuring"></a>
#### Destructuring

A destructuring assignment can separate elements of indexable aggregate types
([Tuples](#Tuples), [Arrays](#Arrays), [Vectors](#Vectors)):

**`destructuring_to_existing.zig`**
```zig
const print = @import("std").debug.print;

pub fn main() void {
    var x: u32 = undefined;
    var y: u32 = undefined;
    var z: u32 = undefined;

    const tuple = .{ 1, 2, 3 };

    x, y, z = tuple;

    print("tuple: x = {}, y = {}, z = {}\n", .{x, y, z});

    const array = [_]u32{ 4, 5, 6 };

    x, y, z = array;

    print("array: x = {}, y = {}, z = {}\n", .{x, y, z});

    const vector: @Vector(3, u32) = .{ 7, 8, 9 };

    x, y, z = vector;

    print("vector: x = {}, y = {}, z = {}\n", .{x, y, z});
}
```

```sh
$ zig build-exe destructuring_to_existing.zig
$ ./destructuring_to_existing
tuple: x = 1, y = 2, z = 3
array: x = 4, y = 5, z = 6
vector: x = 7, y = 8, z = 9
```

A destructuring expression may only appear within a block (i.e. not at [Namespace](#Namespace) scope).
The left hand side of the assignment must consist of a comma separated list,
each element of which may be either an lvalue (for instance, an existing `var`) or a variable declaration:

**`destructuring_mixed.zig`**
```zig
const print = @import("std").debug.print;

pub fn main() void {
    var x: u32 = undefined;

    const tuple = .{ 1, 2, 3 };

    x, var y : u32, const z = tuple;

    print("x = {}, y = {}, z = {}\n", .{x, y, z});

    // y is mutable
    y = 100;

    // You can use _ to throw away unwanted values.
    _, x, _ = tuple;

    print("x = {}\n", .{x});
}
```

```sh
$ zig build-exe destructuring_mixed.zig
$ ./destructuring_mixed
x = 1, y = 2, z = 3
x = 2
```

A destructure may be prefixed with the `comptime` keyword, in which case the entire
destructure expression is evaluated at [comptime](#comptime). All `var`s declared would
be `comptime var`s and all expressions (both result locations and the assignee
expression) are evaluated at [comptime](#comptime).

See also:

- [Destructuring Tuples](#Destructuring-Tuples)
- [Destructuring Arrays](#Destructuring-Arrays)
- [Destructuring Vectors](#Destructuring-Vectors)
