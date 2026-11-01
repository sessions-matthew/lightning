# union

> Zig 0.17.0 Language Reference — Section 19 of 53  
> [← Back to Language Reference Index](../langref.md)

<a id="union"></a>
## union

A bare `union` defines a set of possible types that a value
can be as a list of fields. Only one field can be active at a time.
The in-memory representation of bare unions is not guaranteed.
Bare unions cannot be used to reinterpret memory. For that, use [@ptrCast](#ptrCast),
or use an [extern union](#extern-union) or a [packed union](#packed-union) which have
guaranteed in-memory layout.
[Accessing the non-active field](#Wrong-Union-Field-Access) is
safety-checked [Illegal Behavior](#Illegal-Behavior):

**`test_wrong_union_access.zig`**
```zig
const Payload = union {
    int: i64,
    float: f64,
    boolean: bool,
};
test "simple union" {
    var payload = Payload{ .int = 1234 };
    payload.float = 12.34;
}
```

```sh
$ zig test test_wrong_union_access.zig
1/1 test_wrong_union_access.test.simple union...thread 38045 panic: access of union field 'float' while field 'int' is active
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/.zig-cache/tmp/d5f1ed18e19c4783/../../../doc/langref/test_wrong_union_access.zig:8:12: 0x102b87453 in test.simple union (test)
    payload.float = 12.34;
           ^
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/lib/compiler/test_runner.zig:295:25: 0x102b631c3 in mainTerminal (test)
        if (test_fn.func()) |_| {
                        ^
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/lib/compiler/test_runner.zig:74:28: 0x102b62ca3 in main (test)
        return mainTerminal(init);
                           ^
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/lib/std/start.zig:789:88: 0x102b60bd3 in callMain (test)
    if (fn_info.param_types[0].? == std.process.Init.Minimal) return wrapMain(root.main(.{
                                                                                       ^
???:?:?: 0x18cd53e7f in start (/usr/lib/dyld)
error: the following test command terminated with signal ABRT:
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/.zig-cache/o/1f3274394deeb4d83dae39185e475a63/test --seed=0xd624e37e
```

You can activate another field by assigning the entire union:

**`test_simple_union.zig`**
```zig
const std = @import("std");
const expectEqual = std.testing.expectEqual;

const Payload = union {
    int: i64,
    float: f64,
    boolean: bool,
};
test "simple union" {
    var payload = Payload{ .int = 1234 };
    try expectEqual(1234, payload.int);
    payload = Payload{ .float = 12.34 };
    try expectEqual(12.34, payload.float);
}
```

```sh
$ zig test test_simple_union.zig
1/1 test_simple_union.test.simple union...OK
All 1 tests passed.
```

In order to use [switch](#switch) with a union, it must be a [tagged union](#Tagged-union)
or a [packed union](#packed-union).

To initialize a union when the tag is a [comptime](#comptime)-known name, see [@unionInit](#unionInit).

<a id="Tagged-union"></a>
### Tagged union

Unions can be declared with an enum tag type.
This turns the union into a *tagged* union, which makes it eligible
to use with [switch](#switch) expressions. When switching on tagged unions,
the tag value can be obtained using an additional capture.
Tagged unions coerce to their tag type: [Type Coercion: Unions and Enums](#Type-Coercion-Unions-and-Enums).

**`test_tagged_union.zig`**
```zig
const std = @import("std");
const expectEqual = std.testing.expectEqual;

const ComplexTypeTag = enum {
    ok,
    not_ok,
};
const ComplexType = union(ComplexTypeTag) {
    ok: u8,
    not_ok: void,
};

test "switch on tagged union" {
    const c = ComplexType{ .ok = 42 };
    try expectEqual(ComplexTypeTag.ok, @as(ComplexTypeTag, c));

    switch (c) {
        .ok => |value| try expectEqual(42, value),
        .not_ok => unreachable,
    }

    switch (c) {
        .ok => |_, tag| {
            // Because we're in the '.ok' prong, 'tag' is compile-time known to be '.ok':
            comptime std.debug.assert(tag == .ok);
        },
        .not_ok => unreachable,
    }
}

test "get tag type" {
    try expectEqual(ComplexTypeTag, std.meta.Tag(ComplexType));
}
```

```sh
$ zig test test_tagged_union.zig
1/2 test_tagged_union.test.switch on tagged union...OK
2/2 test_tagged_union.test.get tag type...OK
All 2 tests passed.
```

In order to modify the payload of a tagged union in a switch expression,
place a `*` before the variable name to make it a pointer:

**`test_switch_modify_tagged_union.zig`**
```zig
const std = @import("std");
const expectEqual = std.testing.expectEqual;

const ComplexTypeTag = enum {
    ok,
    not_ok,
};
const ComplexType = union(ComplexTypeTag) {
    ok: u8,
    not_ok: void,
};

test "modify tagged union in switch" {
    var c = ComplexType{ .ok = 42 };

    switch (c) {
        ComplexTypeTag.ok => |*value| value.* += 1,
        ComplexTypeTag.not_ok => unreachable,
    }

    try expectEqual(43, c.ok);
}
```

```sh
$ zig test test_switch_modify_tagged_union.zig
1/1 test_switch_modify_tagged_union.test.modify tagged union in switch...OK
All 1 tests passed.
```

Unions can be made to infer the enum tag type.
Further, unions can have methods just like structs and enums.

**`test_union_method.zig`**
```zig
const std = @import("std");
const expect = std.testing.expect;

const Variant = union(enum) {
    int: i32,
    boolean: bool,

    // void can be omitted when inferring enum tag type.
    none,

    fn truthy(self: Variant) bool {
        return switch (self) {
            Variant.int => |x_int| x_int != 0,
            Variant.boolean => |x_bool| x_bool,
            Variant.none => false,
        };
    }
};

test "union method" {
    var v1: Variant = .{ .int = 1 };
    var v2: Variant = .{ .boolean = false };
    var v3: Variant = .none;

    try expect(v1.truthy());
    try expect(!v2.truthy());
    try expect(!v3.truthy());
}
```

```sh
$ zig test test_union_method.zig
1/1 test_union_method.test.union method...OK
All 1 tests passed.
```

Unions with inferred enum tag types can also assign ordinal values to their inferred tag.
This requires the tag to specify an explicit integer type.
[@backingInt](#backingInt) can be used to access the ordinal value corresponding to the active field.

**`test_tagged_union_with_tag_values.zig`**
```zig
const std = @import("std");
const expectEqual = std.testing.expectEqual;

const Tagged = union(enum(u32)) {
    int: i64 = 123,
    boolean: bool = 67,
};

test "tag values" {
    const int: Tagged = .{ .int = -40 };
    try expectEqual(123, @backingInt(int));

    const boolean: Tagged = .{ .boolean = false };
    try expectEqual(67, @backingInt(boolean));
}
```

```sh
$ zig test test_tagged_union_with_tag_values.zig
1/1 test_tagged_union_with_tag_values.test.tag values...OK
All 1 tests passed.
```

[@tagName](#tagName) can be used to return a [comptime](#comptime)
`[:0]const u8` value representing the field name:

**`test_tagName.zig`**
```zig
const std = @import("std");
const expectEqualSlices = std.testing.expectEqualSlices;

const Small2 = union(enum) {
    a: i32,
    b: bool,
    c: u8,
};
test "@tagName" {
    try expectEqualSlices(u8, "a", @tagName(Small2.a));
}
```

```sh
$ zig test test_tagName.zig
1/1 test_tagName.test.@tagName...OK
All 1 tests passed.
```

<a id="extern-union"></a>
### extern union

An `extern union` has memory layout guaranteed to be compatible with
the target C ABI.

See also:

- [extern struct](#extern-struct)

<a id="packed-union"></a>
### packed union

A `packed union` has well-defined in-memory layout and is eligible
to be in a [packed struct](#packed-struct).

All fields in a packed union must have the same [@bitSizeOf](#bitSizeOf).

Equating packed unions results in a comparison of the backing integer,
and only works for the `==` and `!=` [Operators](#Operators).

**`test_packed_union_equality.zig`**
```zig
const std = @import("std");
const expectEqual = std.testing.expectEqual;

test "packed union equality" {
    const U = packed union {
        a: u4,
        b: i4,
    };
    const x: U = .{ .a = 3 };
    const y: U = .{ .b = 3 };
    try expectEqual(x, y);
}
```

```sh
$ zig test test_packed_union_equality.zig
1/1 test_packed_union_equality.test.packed union equality...OK
All 1 tests passed.
```

See also:

- [@backingInt](#backingInt)
- [@fromBackingInt](#fromBackingInt)

<a id="Anonymous-Union-Literals"></a>
### Anonymous Union Literals

[Anonymous Struct Literals](#Anonymous-Struct-Literals) syntax can be used to initialize unions without specifying
the type:

**`test_anonymous_union.zig`**
```zig
const std = @import("std");
const expectEqual = std.testing.expectEqual;

const Number = union {
    int: i32,
    float: f64,
};

test "anonymous union literal syntax" {
    const i: Number = .{ .int = 42 };
    const f = makeNumber();
    try expectEqual(42, i.int);
    try expectEqual(12.34, f.float);
}

fn makeNumber() Number {
    return .{ .float = 12.34 };
}
```

```sh
$ zig test test_anonymous_union.zig
1/1 test_anonymous_union.test.anonymous union literal syntax...OK
All 1 tests passed.
```
