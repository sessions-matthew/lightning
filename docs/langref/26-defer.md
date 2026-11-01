# defer

> Zig 0.17.0 Language Reference — Section 26 of 53  
> [← Back to Language Reference Index](../langref.md)

<a id="defer"></a>
## defer

Executes an expression unconditionally at scope exit.

**`test_defer.zig`**
```zig
const std = @import("std");
const expectEqual = std.testing.expectEqual;
const print = std.debug.print;

fn deferExample() !usize {
    var a: usize = 1;

    {
        defer a = 2;
        a = 1;
    }
    try expectEqual(2, a);

    a = 5;
    return a;
}

test "defer basics" {
    try expectEqual(5, (try deferExample()));
}
```

```sh
$ zig test test_defer.zig
1/1 test_defer.test.defer basics...OK
All 1 tests passed.
```

Defer expressions are evaluated in reverse order.

**`defer_unwind.zig`**
```zig
const std = @import("std");
const print = std.debug.print;

pub fn main() void {
    print("\n", .{});

    defer {
        print("1 ", .{});
    }
    defer {
        print("2 ", .{});
    }
    if (false) {
        // defers are not run if they are never executed.
        defer {
            print("3 ", .{});
        }
    }
}
```

```sh
$ zig build-exe defer_unwind.zig
$ ./defer_unwind

2 1
```

Inside a defer expression the return statement is not allowed.

**`test_invalid_defer.zig`**
```zig
fn deferInvalidExample() !void {
    defer {
        return error.DeferError;
    }

    return error.DeferError;
}
```

```sh
$ zig test test_invalid_defer.zig
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/doc/langref/test_invalid_defer.zig:3:9: error: cannot return from defer expression
        return error.DeferError;
        ^~~~~~~~~~~~~~~~~~~~~~~
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/doc/langref/test_invalid_defer.zig:2:5: note: defer expression here
    defer {
    ^~~~~
```

See also:

- [Errors](#Errors)
