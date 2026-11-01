# `std.static_string_map`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/static_string_map.zig`  
> [← Back to Standard Library Index](README.md)

## Types

### `StaticStringMap`

```zig
pub fn StaticStringMap(comptime V: type) type
```

Static string map optimized for small sets of disparate string keys.
Works by separating the keys by length at initialization and only checking
strings of equal length at runtime.

### `StaticStringMapWithEql`

```zig
pub fn StaticStringMapWithEql(comptime V: type, comptime eql: fn (a: []const u8, b: []const u8) bool, ) type
```

StaticStringMap, but accepts an equality function (`eql`).
The `eql` function is only called to determine the equality
of equal length strings. Any strings that are not equal length
are never compared using the `eql` function.

### Fields

- `kvs: *const KVs = &empty_kvs`
  
- `len_indexes: [*]const u32 = &empty_len_indexes`
  
- `len_indexes_len: u32 = 0`
  
- `min_len: u32 = std.math.maxInt(u32)`
  
- `max_len: u32 = 0`
  

### Types

#### `KV`


### Functions

#### `initComptime`

```zig
pub inline fn initComptime(comptime kvs_list: anytype) Self
```

Returns a map backed by static, comptime allocated memory.

`kvs_list` must be either a list of `struct { []const u8, V }`
(key-value pair) tuples, or a list of `struct { []const u8 }`
(only keys) tuples if `V` is `void`.

#### `initEnum`

```zig
pub inline fn initEnum() Self
```

Returns a map backed by static, comptime allocated memory.

`V` must be an enum. The enum's tag names will be used as the keys.

#### `init`

```zig
pub fn init(kvs_list: anytype, allocator: mem.Allocator) !Self
```

Returns a map backed by memory allocated with `allocator`.

Handles `kvs_list` the same way as `initComptime()`.

#### `deinit`

```zig
pub fn deinit(self: Self, allocator: mem.Allocator) void
```

this method should only be used with init() and not with initComptime().

#### `has`

```zig
pub fn has(self: Self, str: []const u8) bool
```

Checks if the map has a value for the key.

#### `get`

```zig
pub fn get(self: Self, str: []const u8) ?V
```

Returns the value for the key if any, else null.

#### `getIndex`

```zig
pub fn getIndex(self: Self, str: []const u8) ?usize
```

Returns the index corresponding to the `str` within the
generated `kvs`, or `null` if `str` was not found.
The returned index is unrelated to the input `kvs_list`.

#### `getLongestPrefix`

```zig
pub fn getLongestPrefix(self: Self, str: []const u8) ?KV
```

Returns the key-value pair where key is the longest prefix of `str`
else null.

This is effectively an O(N) algorithm which loops from `max_len` to
`min_len` and calls `getIndex()` to check all keys with the given
len.

#### `getLongestPrefixIndex`

```zig
pub fn getLongestPrefixIndex(self: Self, str: []const u8) ?usize
```

Returns the index within the generated `kvs` corresponding to the
key-value pair where key is the longest prefix of `str`, or `null`
if no such key-value pair was found. The returned index is unrelated
to the input `kvs_list`.

This is effectively an O(N) algorithm which loops from `max_len` to
`min_len` and calls `getIndex()` to check all keys with the given
len.

#### `keys`

```zig
pub fn keys(self: Self) []const []const u8
```

Returns the slice of keys from the generated `kvs`, which may
be in a different order than the input `kvs_list`.

#### `values`

```zig
pub fn values(self: Self) []const V
```

Returns the slice of values from the generated `kvs`, which may
be in a different order than the input `kvs_list`.

## Functions

### `defaultEql`

```zig
pub fn defaultEql(a: []const u8, b: []const u8) bool
```

Like `std.mem.eql`, but takes advantage of the fact that the lengths
of `a` and `b` are known to be equal.

### `eqlAsciiIgnoreCase`

```zig
pub fn eqlAsciiIgnoreCase(a: []const u8, b: []const u8) bool
```

Like `std.ascii.eqlIgnoreCase` but takes advantage of the fact that
the lengths of `a` and `b` are known to be equal.

## Constants & Variables

- **`foo`**: 
- **`foo`**: 
- **`foo`**: 

