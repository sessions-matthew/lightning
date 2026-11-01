# Result Location Semantics

> Zig 0.17.0 Language Reference — Section 34 of 53  
> [← Back to Language Reference Index](../langref.md)

<a id="Result-Location-Semantics"></a>
## Result Location Semantics

During compilation, every Zig expression and sub-expression is assigned optional result location
information. This information dictates what type the expression should have (its result type), and
where the resulting value should be placed in memory (its result location). The information is
optional in the sense that not every expression has this information: assignment to
`_`, for instance, does not provide any information about the type of an
expression, nor does it provide a concrete memory location to place it in.

As a motivating example, consider the statement `const x: u32 = 42;`. The type
annotation here provides a result type of `u32` to the initialization expression
`42`, instructing the compiler to coerce this integer (initially of type
`comptime_int`) to this type. We will see more examples shortly.

This is not an implementation detail: the logic outlined above is codified into the Zig language
specification, and is the primary mechanism of type inference in the language. This system is
collectively referred to as "Result Location Semantics".

<a id="Result-Types"></a>
### Result Types

Result types are propagated recursively through expressions where possible. For instance, if the
expression `&e` has result type `*u32`, then
`e` is given a result type of `u32`, allowing the
language to perform this coercion before taking a reference.

The result type mechanism is utilized by casting builtins such as `@intCast`.
Rather than taking as an argument the type to cast to, these builtins use their result type to
determine this information. The result type is often known from context; where it is not, the
`@as` builtin can be used to explicitly provide a result type.

We can break down the result types for each component of a simple expression as follows:

**`result_type_propagation.zig`**
```zig
const expectEqual = @import("std").testing.expectEqual;
test "result type propagates through struct initializer" {
    const S = struct { x: u32 };
    const val: u64 = 123;
    const s: S = .{ .x = @intCast(val) };
    // .{ .x = @intCast(val) }   has result type `S` due to the type annotation
    //         @intCast(val)     has result type `u32` due to the type of the field `S.x`
    //                  val      has no result type, as it is permitted to be any integer type
    try expectEqual(@as(u32, 123), s.x);
}
```

```sh
$ zig test result_type_propagation.zig
1/1 result_type_propagation.test.result type propagates through struct initializer...OK
All 1 tests passed.
```

This result type information is useful for the aforementioned cast builtins, as well as to avoid
the construction of pre-coercion values, and to avoid the need for explicit type coercions in some
cases. The following table details how some common expressions propagate result types, where
`x` and `y` are arbitrary sub-expressions.

| Expression | Parent Result Type | Sub-expression Result Type |
| --- | --- | --- |
| `const val: T = x` | - | `x` is a `T` |
| `var val: T = x` | - | `x` is a `T` |
| `val = x` | - | `x` is a `@TypeOf(val)` |
| `@as(T, x)` | - | `x` is a `T` |
| `&x` | `*T` | `x` is a `T` |
| `&x` | `[]T` | `x` is some array of `T` |
| `f(x)` | - | `x` has the type of the first parameter of `f` |
| `.{x}` | `T` | `x` is a `@FieldType(T, "0")` |
| `.{ .a = x }` | `T` | `x` is a `@FieldType(T, "a")` |
| `T{x}` | - | `x` is a `@FieldType(T, "0")` |
| `T{ .a = x }` | - | `x` is a `@FieldType(T, "a")` |
| `@Int(x, y)` | - | `x` is a `std.lang.Signedness`, `y` is a `u16` |
| `@typeInfo(x)` | - | `x` is a `type` |
| `x << y` | - | `y` is a `std.math.Log2IntCeil(@TypeOf(x))` |

<a id="Result-Locations"></a>
### Result Locations

In addition to result type information, every expression may be optionally assigned a result
location: a pointer to which the value must be directly written. This system can be used to prevent
intermediate copies when initializing data structures, which can be important for types which must
have a fixed memory address ("pinned" types).

When compiling the simple assignment expression `x = e`, many languages would
create the temporary value `e` on the stack, and then assign it to
`x`, potentially performing a type coercion in the process. Zig approaches this
differently. The expression `e` is given a result type matching the type of
`x`, and a result location of `&x`. For many syntactic
forms of `e`, this has no practical impact. However, it can have important
semantic effects when working with more complex syntax forms.

For instance, if the expression `.{ .a = x, .b = y }` has a result location of
`ptr`, then `x` is given a result location of
`&ptr.a`, and `y` a result location of `&ptr.b`.
Without this system, this expression would construct a temporary struct value entirely on the stack, and
only then copy it to the destination address. In essence, Zig desugars the assignment
`foo = .{ .a = x, .b = y }` to the two statements `foo.a = x; foo.b = y;`.

This can sometimes be important when assigning an aggregate value where the initialization
expression depends on the previous value of the aggregate. The easiest way to demonstrate this is by
attempting to swap fields of a struct or array - the following logic looks sound, but in fact is not:

**`result_location_interfering_with_swap.zig`**
```zig
const expectEqual = @import("std").testing.expectEqual;
test "attempt to swap array elements with array initializer" {
    var arr: [2]u32 = .{ 1, 2 };
    arr = .{ arr[1], arr[0] };
    // The previous line is equivalent to the following two lines:
    //   arr[0] = arr[1];
    //   arr[1] = arr[0];
    // So this fails!
    try expectEqual(2, arr[0]); // succeeds
    try expectEqual(1, arr[1]); // fails
}
```

```sh
$ zig test result_location_interfering_with_swap.zig
1/1 result_location_interfering_with_swap.test.attempt to swap array elements with array initializer...expected 1, found 2
FAIL (TestExpectedEqual)
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/lib/std/testing.zig:93:17: 0x10507743b in expectEqualInner__func_999 (test)
                return error.TestExpectedEqual;
                ^
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/lib/std/testing.zig:57:5: 0x105077593 in expectEqual (test)
    return expectEqualInner(T, expected, actual);
    ^
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/.zig-cache/tmp/73aefd7196557343/../../../doc/langref/result_location_interfering_with_swap.zig:10:5: 0x10507760f in test.attempt to swap array elements with array initializer (test)
    try expectEqual(1, arr[1]); // fails
    ^
0 passed; 0 skipped; 1 failed.
error: the following test command failed with exit code 1:
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/.zig-cache/o/0cd7681f43ad3241db3d5b97c69a3962/test --seed=0x7ac2bd2e
```

The following table details how some common expressions propagate result locations, where
`x` and `y` are arbitrary sub-expressions. Note that
some expressions cannot provide meaningful result locations to sub-expressions, even if they
themselves have a result location.

| Expression | Result Location | Sub-expression Result Locations |
| --- | --- | --- |
| `const val: T = x` | - | `x` has result location `&val` |
| `var val: T = x` | - | `x` has result location `&val` |
| `val = x` | - | `x` has result location `&val` |
| `@as(T, x)` | `ptr` | `x` has no result location |
| `&x` | `ptr` | `x` has no result location |
| `f(x)` | `ptr` | `x` has no result location |
| `.{x}` | `ptr` | `x` has result location `&ptr[0]` |
| `.{ .a = x }` | `ptr` | `x` has result location `&ptr.a` |
| `T{x}` | `ptr` | `x` has no result location (typed initializers do not propagate result locations) |
| `T{ .a = x }` | `ptr` | `x` has no result location (typed initializers do not propagate result locations) |
| `@Int(x, y)` | - | `x` and `y` do not have result locations |
| `@typeInfo(x)` | `ptr` | `x` has no result location |
| `x << y` | `ptr` | `x` and `y` do not have result locations |
