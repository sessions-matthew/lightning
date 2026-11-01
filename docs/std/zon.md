# `std.zon`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/zon.zig`  
> [← Back to Standard Library Index](README.md)

ZON parsing and stringification.

ZON ("Zig Object Notation") is a textual file format. Outside of `nan` and `inf` literals, ZON's
grammar is a subset of Zig's.

Supported Zig primitives:
* boolean literals
* number literals (including `nan` and `inf`)
* character literals
* enum literals
* `null` literals
* string literals
* multiline string literals

Supported Zig container types:
* anonymous struct literals
* anonymous tuple literals

Here is an example ZON object:
```
.{
    .a = 1.5,
    .b = "hello, world!",
    .c = .{ true, false },
    .d = .{ 1, 2, 3 },
    .e = .{ .x = 13, .y = 67 },
}
```

Individual primitives are also valid ZON, for example:
```
"This string is a valid ZON object."
```

ZON may not contain type names.

ZON does not have syntax for pointers, but the parsers will allocate as needed to match the
given Zig types. Similarly, the serializer will traverse pointers.

## Types

### `Formatter`

```zig
pub fn Formatter(comptime T: type) type
```

Formats the given value using stringify.

### Fields

- `value: T`
  
- `options: stringify.SerializeOptions`
  

### Functions

#### `format`

```zig
pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void
```


## Functions

### `fmt`

```zig
pub fn fmt(value: anytype, options: stringify.SerializeOptions) Formatter(@TypeOf(value))
```

Returns a formatter that formats the given value using stringify.

## Constants & Variables

- **`parse`**: 
- **`stringify`**: 
- **`Serializer`**: 

