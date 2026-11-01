# unreachable

> Zig 0.17.0 Language Reference — Section 27 of 53  
> [← Back to Language Reference Index](../langref.md)

<a id="unreachable"></a>
## unreachable

In [debug](#debug) and [safe](#safe) mode
`unreachable` emits a call to `panic` with the message `reached unreachable code`.

In [fast](#fast) and [small](#small) mode, the optimizer uses the assumption that `unreachable` code
will never be hit to perform optimizations.

<a id="Basics"></a>
### Basics

**`test_unreachable.zig`**
```zig
// unreachable is used to assert that control flow will never reach a
// particular location:
test "basic math" {
    const x = 1;
    const y = 2;
    if (x + y != 3) {
        unreachable;
    }
}
```

```sh
$ zig test test_unreachable.zig
1/1 test_unreachable.test.basic math...OK
All 1 tests passed.
```

In fact, this is how `std.debug.assert` is implemented:

**`test_assertion_failure.zig`**
```zig
// This is how std.debug.assert is implemented
fn assert(ok: bool) void {
    if (!ok) unreachable; // assertion failure
}

// This test will fail because we hit unreachable.
test "this will fail" {
    assert(false);
}
```

```sh
$ zig test test_assertion_failure.zig
1/1 test_assertion_failure.test.this will fail...thread 38155 panic: reached unreachable code
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/.zig-cache/tmp/d6ab9145c05f6125/../../../doc/langref/test_assertion_failure.zig:3:14: 0x10285b3ff in assert (test)
    if (!ok) unreachable; // assertion failure
             ^
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/.zig-cache/tmp/d6ab9145c05f6125/../../../doc/langref/test_assertion_failure.zig:8:11: 0x10285b3bf in test.this will fail (test)
    assert(false);
          ^
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/lib/compiler/test_runner.zig:295:25: 0x1028371c3 in mainTerminal (test)
        if (test_fn.func()) |_| {
                        ^
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/lib/compiler/test_runner.zig:74:28: 0x102836ca3 in main (test)
        return mainTerminal(init);
                           ^
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/lib/std/start.zig:789:88: 0x102834bd3 in callMain (test)
    if (fn_info.param_types[0].? == std.process.Init.Minimal) return wrapMain(root.main(.{
                                                                                       ^
???:?:?: 0x18cd53e7f in start (/usr/lib/dyld)
error: the following test command terminated with signal ABRT:
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/.zig-cache/o/c50a3082f33528b0b783ba21fc3a14fa/test --seed=0xae7a1edd
```

<a id="At-Compile-Time"></a>
### At Compile-Time

**`test_comptime_unreachable.zig`**
```zig
const assert = @import("std").debug.assert;

test "type of unreachable" {
    comptime {
        // The type of unreachable is noreturn.

        // However this assertion will still fail to compile because
        // unreachable expressions are compile errors.

        assert(@TypeOf(unreachable) == noreturn);
    }
}
```

```sh
$ zig test test_comptime_unreachable.zig
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/doc/langref/test_comptime_unreachable.zig:10:16: error: unreachable code
        assert(@TypeOf(unreachable) == noreturn);
               ^~~~~~~~~~~~~~~~~~~~
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/doc/langref/test_comptime_unreachable.zig:10:24: note: control flow is diverted here
        assert(@TypeOf(unreachable) == noreturn);
                       ^~~~~~~~~~~
```

See also:

- [Zig Test](#Zig-Test)
- [Optimization Mode](#Optimization-Mode)
- [comptime](#comptime)
