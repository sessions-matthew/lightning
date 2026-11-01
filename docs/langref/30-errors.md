# Errors

> Zig 0.17.0 Language Reference — Section 30 of 53  
> [← Back to Language Reference Index](../langref.md)

<a id="Errors"></a>
## Errors

<a id="Error-Set-Type"></a>
### Error Set Type

An error set is like an [enum](#enum).
However, each error name across the entire compilation gets assigned an unsigned integer
greater than 0. You are allowed to declare the same error name more than once, and if you do, it
gets assigned the same integer value.

The error set type defaults to a `u16`, though if the maximum number of distinct
error values is provided via the `--error-limit [num]` command line parameter an integer type
with the minimum number of bits required to represent all of the error values will be used.

You can [coerce](#Type-Coercion) an error from a subset to a superset:

**`test_coerce_error_subset_to_superset.zig`**
```zig
const std = @import("std");

const FileOpenError = error{
    AccessDenied,
    OutOfMemory,
    FileNotFound,
};

const AllocationError = error{
    OutOfMemory,
};

test "coerce subset to superset" {
    const err = foo(AllocationError.OutOfMemory);
    try std.testing.expectEqual(FileOpenError.OutOfMemory, err);
}

fn foo(err: AllocationError) FileOpenError {
    return err;
}
```

```sh
$ zig test test_coerce_error_subset_to_superset.zig
1/1 test_coerce_error_subset_to_superset.test.coerce subset to superset...OK
All 1 tests passed.
```

But you cannot [coerce](#Type-Coercion) an error from a superset to a subset:

**`test_coerce_error_superset_to_subset.zig`**
```zig
const FileOpenError = error{
    AccessDenied,
    OutOfMemory,
    FileNotFound,
};

const AllocationError = error{
    OutOfMemory,
};

test "coerce superset to subset" {
    foo(FileOpenError.OutOfMemory) catch {};
}

fn foo(err: FileOpenError) AllocationError {
    return err;
}
```

```sh
$ zig test test_coerce_error_superset_to_subset.zig
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/doc/langref/test_coerce_error_superset_to_subset.zig:16:12: error: expected type 'error{OutOfMemory}', found 'error{AccessDenied,FileNotFound,OutOfMemory}'
    return err;
           ^~~
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/doc/langref/test_coerce_error_superset_to_subset.zig:16:12: note: 'error.AccessDenied' not a member of destination error set
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/doc/langref/test_coerce_error_superset_to_subset.zig:16:12: note: 'error.FileNotFound' not a member of destination error set
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/doc/langref/test_coerce_error_superset_to_subset.zig:15:28: note: function return type declared here
fn foo(err: FileOpenError) AllocationError {
                           ^~~~~~~~~~~~~~~
referenced by:
    test.coerce superset to subset: /private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/doc/langref/test_coerce_error_superset_to_subset.zig:12:8
```

There is a shortcut for declaring an error set with only 1 value, and then getting that value:

**`single_value_error_set_shortcut.zig`**
```zig
const err = error.FileNotFound;
```

This is equivalent to:

**`single_value_error_set.zig`**
```zig
const err = (error{FileNotFound}).FileNotFound;
```

This becomes useful when using [Inferred Error Sets](#Inferred-Error-Sets).

<a id="The-Global-Error-Set"></a>
#### The Global Error Set

`anyerror` refers to the global error set.
This is the error set that contains all errors in the entire compilation unit, i.e. it is the union of all other error sets.

You can [coerce](#Type-Coercion) any error set to the global one, and you can explicitly
cast an error of the global error set to a non-global one. This inserts a language-level
assert to make sure the error value is in fact in the destination error set.

The global error set should generally be avoided because it prevents the
compiler from knowing what errors are possible at compile-time. Knowing
the error set at compile-time is better for generated documentation and
helpful error messages, such as forgetting a possible error value in a [switch](#switch).

<a id="Error-Union-Type"></a>
### Error Union Type

An error set type and normal type can be combined with the `!`
binary operator to form an error union type. You are likely to use an
error union type more often than an error set type by itself.

Here is a function to parse a string into a 64-bit integer:

**`error_union_parsing_u64.zig`**
```zig
const std = @import("std");
const maxInt = std.math.maxInt;

pub fn parseU64(buf: []const u8, radix: u8) !u64 {
    var x: u64 = 0;

    for (buf) |c| {
        const digit = charToDigit(c);

        if (digit >= radix) {
            return error.InvalidChar;
        }

        // x *= radix
        var ov = @mulWithOverflow(x, radix);
        if (ov[1] != 0) return error.OverFlow;

        // x += digit
        ov = @addWithOverflow(ov[0], digit);
        if (ov[1] != 0) return error.OverFlow;
        x = ov[0];
    }

    return x;
}

fn charToDigit(c: u8) u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'A'...'Z' => c - 'A' + 10,
        'a'...'z' => c - 'a' + 10,
        else => maxInt(u8),
    };
}

test "parse u64" {
    const result = try parseU64("1234", 10);
    try std.testing.expectEqual(1234, result);
}
```

```sh
$ zig test error_union_parsing_u64.zig
1/1 error_union_parsing_u64.test.parse u64...OK
All 1 tests passed.
```

Notice the return type is `!u64`. This means that the function
either returns an unsigned 64 bit integer, or an error. We left off the error set
to the left of the `!`, so the error set is inferred.

Within the function definition, you can see some return statements that return
an error, and at the bottom a return statement that returns a `u64`.
Both types [coerce](#Type-Coercion) to `anyerror!u64`.

What it looks like to use this function varies depending on what you're
trying to do. One of the following:

- You want to provide a default value if it returned an error.
- If it returned an error then you want to return the same error.
- You know with complete certainty it will not return an error, so want to unconditionally unwrap it.
- You want to take a different action for each possible error.

<a id="catch"></a>
#### catch

If you want to provide a default value, you can use the `catch` binary operator:

**`catch.zig`**
```zig
const parseU64 = @import("error_union_parsing_u64.zig").parseU64;

fn doAThing(str: []u8) void {
    const number = parseU64(str, 10) catch 13;
    _ = number; // ...
}
```

In this code, `number` will be equal to the successfully parsed string, or
a default value of 13. The type of the right hand side of the binary `catch` operator must
match the unwrapped error union type, or be of type `noreturn`.

If you want to provide a default value with
`catch` after performing some logic, you
can combine `catch` with named [Blocks](#Blocks):

**`handle_error_with_catch_block.zig`**
```zig
const parseU64 = @import("error_union_parsing_u64.zig").parseU64;

fn doAThing(str: []u8) void {
    const number = parseU64(str, 10) catch blk: {
        // do things
        break :blk 13;
    };
    _ = number; // number is now initialized
}
```

<a id="try"></a>
#### try

Let's say you wanted to return the error if you got one, otherwise continue with the
function logic:

**`catch_err_return.zig`**
```zig
const parseU64 = @import("error_union_parsing_u64.zig").parseU64;

fn doAThing(str: []u8) !void {
    const number = parseU64(str, 10) catch |err| return err;
    _ = number; // ...
}
```

There is a shortcut for this. The `try` expression:

**`try.zig`**
```zig
const parseU64 = @import("error_union_parsing_u64.zig").parseU64;

fn doAThing(str: []u8) !void {
    const number = try parseU64(str, 10);
    _ = number; // ...
}
```

`try` evaluates an error union expression. If it is an error, it returns
from the current function with the same error. Otherwise, the expression results in
the unwrapped value.

Maybe you know with complete certainty that an expression will never be an error.
In this case you can do this:

Here we know for sure that "1234" will parse successfully. So we put the
`unreachable` value on the right hand side.
`unreachable` invokes safety-checked [Illegal Behavior](#Illegal-Behavior), so
in [debug](#debug) and [safe](#safe), triggers a safety panic by default. So, while
we're debugging the application, if there *was* a surprise error here, the application
would crash appropriately.

You may want to take a different action for every situation. For that, we combine
the [if](#if) and [switch](#switch) expression:

**`handle_all_error_scenarios.zig`**
```zig
fn doAThing(str: []u8) void {
    if (parseU64(str, 10)) |number| {
        doSomethingWithNumber(number);
    } else |err| switch (err) {
        error.Overflow => {
            // handle overflow...
        },
        // we promise that InvalidChar won't happen (or crash in debug mode if it does)
        error.InvalidChar => unreachable,
    }
}
```

Finally, you may want to handle only some errors. For that, you can capture the unhandled
errors in the `else` case, which now contains a narrower error set:

**`handle_some_error_scenarios.zig`**
```zig
fn doAnotherThing(str: []u8) error{InvalidChar}!void {
    if (parseU64(str, 10)) |number| {
        doSomethingWithNumber(number);
    } else |err| switch (err) {
        error.Overflow => {
            // handle overflow...
        },
        else => |leftover_err| return leftover_err,
    }
}
```

You must use the variable capture syntax. If you don't need the
variable, you can capture with `_` and avoid the
`switch`.

**`handle_no_error_scenarios.zig`**
```zig
fn doADifferentThing(str: []u8) void {
    if (parseU64(str, 10)) |number| {
        doSomethingWithNumber(number);
    } else |_| {
        // do as you'd like
    }
}
```

<a id="errdefer"></a>
#### errdefer

The other component to error handling is defer statements.
In addition to an unconditional [defer](#defer), Zig has `errdefer`,
which evaluates the deferred expression on block exit path if and only if
the function returned with an error from the block.

Example:

**`errdefer_example.zig`**
```zig
fn createFoo(param: i32) !Foo {
    const foo = try tryToAllocateFoo();
    // now we have allocated foo. we need to free it if the function fails.
    // but we want to return it if the function succeeds.
    errdefer deallocateFoo(foo);

    const tmp_buf = allocateTmpBuffer() orelse return error.OutOfMemory;
    // tmp_buf is truly a temporary resource, and we for sure want to clean it up
    // before this block leaves scope
    defer deallocateTmpBuffer(tmp_buf);

    if (param > 1337) return error.InvalidParam;

    // here the errdefer will not run since we're returning success from the function.
    // but the defer will run!
    return foo;
}
```

The neat thing about this is that you get robust error handling without
the verbosity and cognitive overhead of trying to make sure every exit path
is covered. The deallocation code is always directly following the allocation code.

A couple of other tidbits about error handling:

- These primitives give enough expressiveness that it's completely practical to have failing to check for an error be a compile error. If you really want to ignore the error, you can add `catch unreachable` and get the added benefit of crashing in [debug](#debug) and [safe](#safe) modes if your assumption was wrong.
- Since Zig understands error types, it can pre-weight branches in favor of errors not occurring. Just a small optimization benefit that is not available in other languages.

See also:

- [defer](#defer)
- [if](#if)
- [switch](#switch)

An error union is created with the `!` binary operator.
You can use compile-time reflection to access the child type of an error union:

**`test_error_union.zig`**
```zig
const expectEqual = @import("std").testing.expectEqual;

test "error union" {
    var foo: anyerror!i32 = undefined;

    // Coerce from child type of an error union:
    foo = 1234;

    // Coerce from an error set:
    foo = error.SomeError;

    // Use compile-time reflection to access the payload type of an error union:
    try comptime expectEqual(i32, @typeInfo(@TypeOf(foo)).error_union.payload);

    // Use compile-time reflection to access the error set type of an error union:
    try comptime expectEqual(anyerror, @typeInfo(@TypeOf(foo)).error_union.error_set);
}
```

```sh
$ zig test test_error_union.zig
1/1 test_error_union.test.error union...OK
All 1 tests passed.
```

<a id="Merging-Error-Sets"></a>
#### Merging Error Sets

Use the `||` operator to merge two error sets together. The resulting
error set contains the errors of both error sets. Doc comments from the left-hand
side override doc comments from the right-hand side. In this example, the doc
comments for `C.PathNotFound` is `A doc comment`.

This is especially useful for functions which return different error sets depending
on [comptime](#comptime) branches. For example, the Zig standard library uses
`LinuxFileOpenError || WindowsFileOpenError` for the error set of opening
files.

**`test_merging_error_sets.zig`**
```zig
const A = error{
    NotDir,

    /// A doc comment
    PathNotFound,
};
const B = error{
    OutOfMemory,

    /// B doc comment
    PathNotFound,
};

const C = A || B;

fn foo() C!void {
    return error.NotDir;
}

test "merge error sets" {
    if (foo()) {
        @panic("unexpected");
    } else |err| switch (err) {
        error.OutOfMemory => @panic("unexpected"),
        error.PathNotFound => @panic("unexpected"),
        error.NotDir => {},
    }
}
```

```sh
$ zig test test_merging_error_sets.zig
1/1 test_merging_error_sets.test.merge error sets...OK
All 1 tests passed.
```

<a id="Inferred-Error-Sets"></a>
#### Inferred Error Sets

Because many functions in Zig return a possible error, Zig supports inferring the error set.
To infer the error set for a function, prepend the `!` operator to the function’s return type, like `!T`:

**`test_inferred_error_sets.zig`**
```zig
// With an inferred error set
pub fn add_inferred(comptime T: type, a: T, b: T) !T {
    const ov = @addWithOverflow(a, b);
    if (ov[1] != 0) return error.Overflow;
    return ov[0];
}

// With an explicit error set
pub fn add_explicit(comptime T: type, a: T, b: T) Error!T {
    const ov = @addWithOverflow(a, b);
    if (ov[1] != 0) return error.Overflow;
    return ov[0];
}

const Error = error{
    Overflow,
};

const std = @import("std");

test "inferred error set" {
    if (add_inferred(u8, 255, 1)) |_| unreachable else |err| switch (err) {
        error.Overflow => {}, // ok
    }
}
```

```sh
$ zig test test_inferred_error_sets.zig
1/1 test_inferred_error_sets.test.inferred error set...OK
All 1 tests passed.
```

When a function has an inferred error set, that function becomes generic and thus it becomes
trickier to do certain things with it, such as obtain a function pointer, or have an error
set that is consistent across different build targets. Additionally, inferred error sets
are incompatible with recursion.

In these situations, it is recommended to use an explicit error set. You can generally start
with an empty error set and let compile errors guide you toward completing the set.

These limitations may be overcome in a future version of Zig.

<a id="Error-Return-Traces"></a>
### Error Return Traces

Error Return Traces show all the points in the code that an error was returned to the calling function. This makes it practical to use [try](#try) everywhere and then still be able to know what happened if an error ends up bubbling all the way out of your application.

**`error_return_trace.zig`**
```zig
pub fn main() !void {
    try foo(12);
}

fn foo(x: i32) !void {
    if (x >= 5) {
        try bar();
    } else {
        try bang2();
    }
}

fn bar() !void {
    if (baz()) {
        try quux();
    } else |err| switch (err) {
        error.FileNotFound => try hello(),
    }
}

fn baz() !void {
    try bang1();
}

fn quux() !void {
    try bang2();
}

fn hello() !void {
    try bang2();
}

fn bang1() !void {
    return error.FileNotFound;
}

fn bang2() !void {
    return error.PermissionDenied;
}
```

```sh
$ zig build-exe error_return_trace.zig
$ ./error_return_trace
error: PermissionDenied
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/.zig-cache/tmp/e090d6163e3848dd/../../../doc/langref/error_return_trace.zig:34:5: 0x102d17577 in bang1 (error_return_trace)
    return error.FileNotFound;
    ^
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/.zig-cache/tmp/e090d6163e3848dd/../../../doc/langref/error_return_trace.zig:22:5: 0x102d175e3 in baz (error_return_trace)
    try bang1();
    ^
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/.zig-cache/tmp/e090d6163e3848dd/../../../doc/langref/error_return_trace.zig:38:5: 0x102d175f3 in bang2 (error_return_trace)
    return error.PermissionDenied;
    ^
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/.zig-cache/tmp/e090d6163e3848dd/../../../doc/langref/error_return_trace.zig:30:5: 0x102d176c3 in hello (error_return_trace)
    try bang2();
    ^
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/.zig-cache/tmp/e090d6163e3848dd/../../../doc/langref/error_return_trace.zig:17:31: 0x102d177bf in bar (error_return_trace)
        error.FileNotFound => try hello(),
                              ^
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/.zig-cache/tmp/e090d6163e3848dd/../../../doc/langref/error_return_trace.zig:7:9: 0x102d17853 in foo (error_return_trace)
        try bar();
        ^
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/.zig-cache/tmp/e090d6163e3848dd/../../../doc/langref/error_return_trace.zig:2:5: 0x102d178ef in main (error_return_trace)
    try foo(12);
    ^
```

Look closely at this example. This is no stack trace.

You can see that the final error bubbled up was `PermissionDenied`,
but the original error that started this whole thing was `FileNotFound`. In the `bar` function, the code handles the original error code,
and then returns another one, from the switch statement. Error Return Traces make this clear, whereas a stack trace would look like this:

**`stack_trace.zig`**
```zig
pub fn main() void {
    foo(12);
}

fn foo(x: i32) void {
    if (x >= 5) {
        bar();
    } else {
        bang2();
    }
}

fn bar() void {
    if (baz()) {
        quux();
    } else {
        hello();
    }
}

fn baz() bool {
    return bang1();
}

fn quux() void {
    bang2();
}

fn hello() void {
    bang2();
}

fn bang1() bool {
    return false;
}

fn bang2() void {
    @panic("PermissionDenied");
}
```

```sh
$ zig build-exe stack_trace.zig
$ ./stack_trace
thread 37850 panic: PermissionDenied
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/.zig-cache/tmp/b31ff071efdfa56d/../../../doc/langref/stack_trace.zig:38:5: 0x1027355eb in bang2 (stack_trace)
    @panic("PermissionDenied");
    ^
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/.zig-cache/tmp/b31ff071efdfa56d/../../../doc/langref/stack_trace.zig:30:10: 0x102735897 in hello (stack_trace)
    bang2();
         ^
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/.zig-cache/tmp/b31ff071efdfa56d/../../../doc/langref/stack_trace.zig:17:14: 0x10273577b in bar (stack_trace)
        hello();
             ^
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/.zig-cache/tmp/b31ff071efdfa56d/../../../doc/langref/stack_trace.zig:7:12: 0x10273533f in foo (stack_trace)
        bar();
           ^
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/.zig-cache/tmp/b31ff071efdfa56d/../../../doc/langref/stack_trace.zig:2:8: 0x10273519f in main (stack_trace)
    foo(12);
       ^
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/lib/std/start.zig:788:64: 0x10273513b in callMain (stack_trace)
    if (fn_info.param_types.len == 0) return wrapMain(root.main());
                                                               ^
???:?:?: 0x18cd53e7f in start (/usr/lib/dyld)
(process terminated by signal)
```

Here, the stack trace does not explain how the control
flow in `bar` got to the `hello()` call.
One would have to open a debugger or further instrument the application
in order to find out. The error return trace, on the other hand,
shows exactly how the error bubbled up.

This debugging feature makes it easier to iterate quickly on code that
robustly handles all error conditions. This means that Zig developers
will naturally find themselves writing correct, robust code in order
to increase their development pace.

Error Return Traces are enabled by default in [debug](#debug) builds and disabled by default in [fast](#fast), [safe](#safe) and [small](#small) builds.

There are a few ways to activate this error return tracing feature:

- Return an error from main
- An error makes its way to `catch unreachable` and you have not overridden the default panic handler
- Use [errorReturnTrace](#errorReturnTrace) to access the current return trace. You can use `std.debug.dumpErrorReturnTrace` to print it. This function returns comptime-known [null](#null) when building without error return tracing support.

<a id="Implementation-Details"></a>
#### Implementation Details

To analyze performance cost, there are two cases:

- when no errors are returned
- when returning errors

For the case when no errors are returned, the cost is a single memory write operation, only in the first non-failable function in the call graph that calls a failable function, i.e. when a function returning `void` calls a function returning `error`.
This is to initialize this struct in the stack memory:

**`stack_trace_struct.zig`**
```zig
pub const StackTrace = struct {
    index: usize,
    instruction_addresses: [N]usize,
};
```

Here, N is the maximum function call depth as determined by call graph analysis. Recursion is ignored and counts for 2.

A pointer to `StackTrace` is passed as a secret parameter to every function that can return an error, but it's always the first parameter, so it can likely sit in a register and stay there.

That's it for the path when no errors occur. It's practically free in terms of performance.

When generating the code for a function that returns an error, just before the `return` statement (only for the `return` statements that return errors), Zig generates a call to this function:

**`zig_return_error_fn.zig`**
```zig
// marked as "no-inline" in LLVM IR
fn __zig_return_error(stack_trace: *StackTrace) void {
    stack_trace.instruction_addresses[stack_trace.index] = @returnAddress();
    stack_trace.index = (stack_trace.index + 1) % N;
}
```

The cost is 2 math operations plus some memory reads and writes. The memory accessed is constrained and should remain cached for the duration of the error return bubbling.

As for code size cost, 1 function call before a return statement is no big deal. Even so,
I have [a plan](https://github.com/ziglang/zig/issues/690) to make the call to
`__zig_return_error` a tail call, which brings the code size cost down to actually zero. What is a return statement in code without error return tracing can become a jump instruction in code with error return tracing.
