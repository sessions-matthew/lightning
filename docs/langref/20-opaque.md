# opaque

> Zig 0.17.0 Language Reference — Section 20 of 53  
> [← Back to Language Reference Index](../langref.md)

<a id="opaque"></a>
## opaque

`opaque {}` declares a new type with an unknown (but non-zero) size and alignment.
It can contain declarations the same as [structs](#struct), [unions](#union),
and [enums](#enum).

This is typically used for type safety when interacting with C code that does not expose struct details.
Example:

**`test_opaque.zig`**
```zig
const Derp = opaque {};
const Wat = opaque {};

extern fn bar(d: *Derp) void;
fn foo(w: *Wat) callconv(.c) void {
    bar(w);
}

test "call foo" {
    foo(undefined);
}
```

```sh
$ zig test test_opaque.zig
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/doc/langref/test_opaque.zig:6:9: error: expected type '*test_opaque.Derp', found '*test_opaque.Wat'
    bar(w);
        ^
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/doc/langref/test_opaque.zig:6:9: note: pointer type child 'test_opaque.Wat' cannot cast into pointer type child 'test_opaque.Derp'
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/doc/langref/test_opaque.zig:2:13: note: opaque declared here
const Wat = opaque {};
            ^~~~~~~~~
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/doc/langref/test_opaque.zig:1:14: note: opaque declared here
const Derp = opaque {};
             ^~~~~~~~~
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/doc/langref/test_opaque.zig:4:18: note: parameter type declared here
extern fn bar(d: *Derp) void;
                 ^~~~~
referenced by:
    test.call foo: /private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/doc/langref/test_opaque.zig:10:8
```
