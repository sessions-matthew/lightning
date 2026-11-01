# Blocks

> Zig 0.17.0 Language Reference — Section 21 of 53  
> [← Back to Language Reference Index](../langref.md)

<a id="Blocks"></a>
## Blocks

Blocks are used to limit the scope of variable declarations:

**`test_blocks.zig`**
```zig
test "access variable after block scope" {
    {
        var x: i32 = 1;
        _ = &x;
    }
    x += 1;
}
```

```sh
$ zig test test_blocks.zig
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/doc/langref/test_blocks.zig:6:5: error: use of undeclared identifier 'x'
    x += 1;
    ^
```

Blocks are expressions. When labeled, `break` can be used
to return a value from the block:

**`test_labeled_break.zig`**
```zig
const std = @import("std");
const expectEqual = std.testing.expectEqual;

test "labeled break from labeled block expression" {
    var y: i32 = 123;

    const x = blk: {
        y += 1;
        break :blk y;
    };
    try expectEqual(124, x);
    try expectEqual(124, y);
}
```

```sh
$ zig test test_labeled_break.zig
1/1 test_labeled_break.test.labeled break from labeled block expression...OK
All 1 tests passed.
```

Here, `blk` can be any name.

See also:

- [Labeled while](#Labeled-while)
- [Labeled for](#Labeled-for)

<a id="Shadowing"></a>
### Shadowing

[Identifiers](#Identifiers) are never allowed to "hide" other identifiers by using the same name:

**`test_shadowing.zig`**
```zig
const pi = 3.14;

test "inside test block" {
    // Let's even go inside another block
    {
        var pi: i32 = 1234;
    }
}
```

```sh
$ zig test test_shadowing.zig
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/doc/langref/test_shadowing.zig:6:13: error: local variable shadows declaration of 'pi'
        var pi: i32 = 1234;
            ^~
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/doc/langref/test_shadowing.zig:1:1: note: declared here
const pi = 3.14;
^~~~~~~~~~~~~~~
```

Because of this, when you read Zig code you can always rely on an identifier to consistently mean
the same thing within the scope it is defined. Note that you can, however, use the same name if
the scopes are separate:

**`test_scopes.zig`**
```zig
test "separate scopes" {
    {
        const pi = 3.14;
        _ = pi;
    }
    {
        var pi: bool = true;
        _ = &pi;
    }
}
```

```sh
$ zig test test_scopes.zig
1/1 test_scopes.test.separate scopes...OK
All 1 tests passed.
```

<a id="Empty-Blocks"></a>
### Empty Blocks

An empty block returns the single value of type `void`:

**`test_empty_block.zig`**
```zig
const std = @import("std");
const expectEqual = std.testing.expectEqual;

test {
    const a = {};
    try expectEqual(void, @TypeOf(a));
}
```

```sh
$ zig test test_empty_block.zig
1/1 test_empty_block.test_0...OK
All 1 tests passed.
```
