# `std.testing`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/testing.zig`  
> [← Back to Standard Library Index](README.md)

## Types

### `TmpDir`


### Fields

- `dir: Io.Dir`
  
- `parent_dir: Io.Dir`
  
- `sub_path: [sub_path_len]u8`
  

### Functions

#### `cleanup`

```zig
pub fn cleanup(self: *TmpDir) void
```


### Constants & Variables

- **`parent_dir_path`**: Deprecated.

### `FuzzInputOptions`


### Fields

- `corpus: []const []const u8 = &.{}`
  

### `Reader`

A `Io.Reader` that writes a predetermined list of buffers during `stream`.

### Fields

- `calls: []const Call`
  
- `interface: Io.Reader`
  
- `next_call_index: usize`
  
- `next_offset: usize`
  
- `artificial_limit: Io.Limit = .unlimited`
  Further reduces how many bytes are written in each `stream` call.

### Types

#### `Call`


### Functions

#### `init`

```zig
pub fn init(buffer: []u8, calls: []const Call) Reader
```


### `ReaderIndirect`

A `Io.Reader` that gets its data from another `Io.Reader`, and always
writes to its own buffer (and returns 0) during `stream` and `readVec`.
Note: zero length buffers are not supported.

### Fields

- `in: *Io.Reader`
  
- `interface: Io.Reader`
  

### Functions

#### `init`

```zig
pub fn init(in: *Io.Reader, buffer: []u8) ReaderIndirect
```


### `WriterIndirect`

A `Io.Writer` that writes its data to another `Io.Writer`, and only
writes new data to its own buffer during `drain`.
Note: zero length buffers are not supported.

### Fields

- `out: *Io.Writer`
  
- `interface: Io.Writer`
  

### Functions

#### `init`

```zig
pub fn init(out: *Io.Writer, buffer: []u8) WriterIndirect
```


## Functions

### `failPrint`

```zig
pub fn failPrint(comptime fmt: []const u8, args: anytype) void
```

Helper function for printing test failure information.

### `expectEqual`

```zig
pub inline fn expectEqual(expected: anytype, actual: anytype) !void
```

This function is intended to be used only in tests. When the two values are not
equal, prints diagnostics to stderr to show exactly how they are not equal,
then returns a test failure error.
`actual` and `expected` are coerced to a common type using peer type resolution.

### `expectApproxEqAbs`

```zig
pub inline fn expectApproxEqAbs(expected: anytype, actual: anytype, tolerance: anytype) !void
```

This function is intended to be used only in tests. When the actual value is
not approximately equal to the expected value, prints diagnostics to stderr
to show exactly how they are not equal, then returns a test failure error.
See `math.approxEqAbs` for more information on the tolerance parameter.
The types must be floating-point.
`actual` and `expected` are coerced to a common type using peer type resolution.

### `expectApproxEqRel`

```zig
pub inline fn expectApproxEqRel(expected: anytype, actual: anytype, tolerance: anytype) !void
```

This function is intended to be used only in tests. When the actual value is
not approximately equal to the expected value, prints diagnostics to stderr
to show exactly how they are not equal, then returns a test failure error.
See `math.approxEqRel` for more information on the tolerance parameter.
The types must be floating-point.
`actual` and `expected` are coerced to a common type using peer type resolution.

### `expectEqualSlices`

```zig
pub fn expectEqualSlices(comptime T: type, expected: []const T, actual: []const T) !void
```

This function is intended to be used only in tests. When the two slices are
not equal, it prints diagnostics to stderr to show exactly how they are not
equal (with the differences highlighted in red), then returns a test
failure error.

### `expectEqualSentinel`

```zig
pub fn expectEqualSentinel(comptime T: type, comptime sentinel: T, expected: [:sentinel]const T, actual: [:sentinel]const T) !void
```

This function is intended to be used only in tests. When the two slices or two arrays are not equal,
or their sentinel (if any) are not the same, it prints diagnostics to stderr to show exactly how
they are not equal (with the differences highlighted in red), then returns a test failure error.
It partially depends on `expectEquaSlices` for printing diagnostics.

### `expect`

```zig
pub fn expect(ok: bool) !void
```

This function is intended to be used only in tests.
When `ok` is false, returns a test failure error.

### `tmpDir`

```zig
pub fn tmpDir(opts: Io.Dir.OpenOptions) TmpDir
```


### `expectError`

```zig
pub fn expectError(expected_error: anyerror, actual_error_union: anytype) !void
```

This function is intended to be used only in tests. When `actual_error_union` is not
`expected_error`, it prints diagnostics to stderr, then returns a test failure error.

### `expectFmt`

```zig
pub fn expectFmt(expected: []const u8, comptime template: []const u8, args: anytype) !void
```

This function is intended to be used only in tests. When the formatted result of the template
and its arguments does not equal the expected text, it prints diagnostics to stderr to show how
they are not equal, then returns an error. It depends on `expectEqualStrings` for printing
diagnostics.

### `expectEqualStrings`

```zig
pub fn expectEqualStrings(expected: []const u8, actual: []const u8) !void
```

it prints diagnostics to stderr to show how they are not equal, then returns an error.

### `expectStringStartsWith`

```zig
pub fn expectStringStartsWith(actual: []const u8, expected_starts_with: []const u8) !void
```

This function is intended to be used only in test. When the start of `actual` and `expected_starts_with`
are not equal, it prints diagnostics to stderr to show how they are not equal, then returns an error.

### `expectStringEndsWith`

```zig
pub fn expectStringEndsWith(actual: []const u8, expected_ends_with: []const u8) !void
```

This function is intended to be used only in test. When the end of `actual` and `expected_ends_with`
are not equal, it prints diagnostics to stderr to show how they are not equal, then returns an error.

### `expectEqualDeep`

```zig
pub inline fn expectEqualDeep(expected: anytype, actual: anytype) error{TestExpectedEqual}!void
```

This function is intended to be used only in tests. When the two values are not
deeply equal, prints diagnostics to stderr to show exactly how they are not equal,
then returns a test failure error.
`actual` and `expected` are coerced to a common type using peer type resolution.

Deeply equal is defined as follows:
Primitive types are deeply equal if they are equal using `==` operator.
Struct values are deeply equal if their corresponding fields are deeply equal.
Container types(like Array/Slice/Vector) deeply equal when their corresponding elements are deeply equal.
Pointer values are deeply equal if values they point to are deeply equal.

Note: Self-referential structs are supported (e.g. things like std.SinglyLinkedList)
but may cause infinite recursion or stack overflow when a container has a pointer to itself.

### `format`

```zig
pub fn format(self: @This(), writer: *Io.Writer) !void
```


### `failPrintIndicatorLine`

```zig
pub fn failPrintIndicatorLine(source: []const u8, indicator_index: usize) void
```

Helper function for printing test failure information.

### `failPrintWithVisibleNewlines`

```zig
pub fn failPrintWithVisibleNewlines(source: []const u8) void
```

Helper function for printing test failure information.

### `failPrintLine`

```zig
pub fn failPrintLine(line: []const u8) void
```

Helper function for printing test failure information.

### `checkAllAllocationFailures`

```zig
pub fn checkAllAllocationFailures(backing_allocator: std.mem.Allocator, comptime test_fn: anytype, extra_args: CheckAllAllocationFailuresExtraArgs(@TypeOf(test_fn)), ) !void
```

Exhaustively check that allocation failures within `test_fn` are handled without
introducing memory leaks. If used with the `testing.allocator` as the `backing_allocator`,
it will also be able to detect double frees, etc (when runtime safety is enabled).

The provided `test_fn` must have a `std.mem.Allocator` as its first argument,
and must have a return type of `!void`. Any extra arguments of `test_fn` can
be provided via the `extra_args` tuple.

Any relevant state shared between runs of `test_fn` *must* be reset within `test_fn`.

The strategy employed is to:
- Run the test function once to get the total number of allocations.
- Then, iterate and run the function X more times, incrementing
  the failing index each iteration (where X is the total number of
  allocations determined previously)

Expects that `test_fn` has a deterministic number of memory allocations:
- If an allocation was made to fail during a run of `test_fn`, but `test_fn`
  didn't return `error.OutOfMemory`, then `error.SwallowedOutOfMemoryError`
  is returned from `checkAllAllocationFailures`. You may want to ignore this
  depending on whether or not the code you're testing includes some strategies
  for recovering from `error.OutOfMemory`.
- If a run of `test_fn` with an expected allocation failure executes without
  an allocation failure being induced, then `error.NondeterministicMemoryUsage`
  is returned. This error means that there are allocation points that won't be
  tested by the strategy this function employs (that is, there are sometimes more
  points of allocation than the initial run of `test_fn` detects).

---

Here's an example using a simple test case that will cause a leak when the
allocation of `bar` fails (but will pass normally):

```zig
test {
    const length: usize = 10;
    const allocator = std.testing.allocator;
    var foo = try allocator.alloc(u8, length);
    var bar = try allocator.alloc(u8, length);

    allocator.free(foo);
    allocator.free(bar);
}
```

The test case can be converted to something that this function can use by
doing:

```zig
fn testImpl(allocator: std.mem.Allocator, length: usize) !void {
    var foo = try allocator.alloc(u8, length);
    var bar = try allocator.alloc(u8, length);

    allocator.free(foo);
    allocator.free(bar);
}

test {
    const length: usize = 10;
    const allocator = std.testing.allocator;
    try std.testing.checkAllAllocationFailures(allocator, testImpl, .{length});
}
```

Running this test will show that `foo` is leaked when the allocation of
`bar` fails. The simplest fix, in this case, would be to use defer like so:

```zig
fn testImpl(allocator: std.mem.Allocator, length: usize) !void {
    var foo = try allocator.alloc(u8, length);
    defer allocator.free(foo);
    var bar = try allocator.alloc(u8, length);
    defer allocator.free(bar);
}
```

### `refAllDecls`

```zig
pub fn refAllDecls(comptime T: type) void
```

Given a type, references all the declarations inside, so that the semantic analyzer sees them.

### `fuzz`

```zig
pub inline fn fuzz(context: anytype, comptime testOne: fn (context: @TypeOf(context), smith: *Smith) anyerror!void, options: FuzzInputOptions, ) anyerror!void
```

Inline to avoid coverage instrumentation.

## Constants & Variables

- **`random_seed`**: Provides deterministic randomness in unit tests.
- **`FailingAllocator`**: 
- **`failing_allocator`**: 
- **`allocator_instance`**: 
- **`allocator`**: 
- **`io_instance`**: 
- **`io`**: 
- **`environ`**: 
- **`log_level`**: TODO https://github.com/ziglang/zig/issues/5738
- **`backend_can_print`**: 
- **`Smith`**: 

