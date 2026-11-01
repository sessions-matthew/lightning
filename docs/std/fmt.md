# `std.fmt`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/fmt.zig`  
> [← Back to Standard Library Index](README.md)

String formatting and parsing.

## Types

### `Alignment`


### Fields

- `left`
  
- `center`
  
- `right`
  

### `Case`


### Fields

- `lower`
  
- `upper`
  

### `Options`


### Fields

- `precision: ?usize = null`
  
- `width: ?usize = null`
  
- `alignment: Alignment = default_alignment`
  
- `fill: u8 = default_fill_char`
  

### Functions

#### `toNumber`

```zig
pub fn toNumber(o: Options, mode: Number.Mode, case: Case) Number
```


### `Number`


### Fields

- `mode: Mode = .decimal`
  
- `case: Case = .lower`
  Affects hex digits as well as floating point "inf"/"INF".
- `precision: ?usize = null`
  
- `width: ?usize = null`
  
- `alignment: Alignment = default_alignment`
  
- `fill: u8 = default_fill_char`
  

### Types

#### `Mode`


### `Placeholder`


### Fields

- `specifier_arg: []const u8`
  
- `fill: u8`
  
- `alignment: Alignment`
  
- `arg: Specifier`
  
- `width: Specifier`
  
- `precision: Specifier`
  

### Functions

#### `parse`

```zig
pub fn parse(comptime bytes: []const u8) Placeholder
```


### `Specifier`


### Fields

- `none`
  
- `number: usize`
  
- `named: []const u8`
  

### `Parser`

A stream based parser for format strings.

Allows to implement formatters compatible with std.fmt without replicating
the standard library behavior.

### Fields

- `bytes: []const u8`
  
- `i: usize`
  

### Functions

#### `number`

```zig
pub fn number(self: *@This()) ?usize
```


#### `until`

```zig
pub fn until(self: *@This(), delimiter: u8) []const u8
```


#### `char`

```zig
pub fn char(self: *@This()) ?u8
```


#### `maybe`

```zig
pub fn maybe(self: *@This(), byte: u8) bool
```


#### `specifier`

```zig
pub fn specifier(self: *@This()) !Specifier
```


#### `peek`

```zig
pub fn peek(self: *@This(), i: usize) ?u8
```


### `ArgSetType`


### `ArgState`


### Fields

- `next_arg: usize = 0`
  
- `used_args: ArgSetType = 0`
  
- `args_len: usize`
  

### Functions

#### `hasUnusedArgs`

```zig
pub fn hasUnusedArgs(self: *@This()) bool
```


#### `nextArg`

```zig
pub fn nextArg(self: *@This(), arg_index: ?usize) ?usize
```


### `Alt`

```zig
pub fn Alt(comptime Data: type, comptime formatFn: fn (data: Data, writer: *Writer) Writer.Error!void, ) type
```

Creates a type suitable for instantiating and passing to a "{f}" placeholder.

### Fields

- `data: Data`
  

### Functions

#### `format`

```zig
pub inline fn format(self: @This(), writer: *Writer) Writer.Error!void
```


## Functions

### `printInt`

```zig
pub fn printInt(buffer: []u8, value: anytype, base: u8, case: Case, options: Options) usize
```

Asserts the rendered integer value fits in `buffer`.
Returns the end index within `buffer`.

### `digits2`

```zig
pub fn digits2(value: u8) [2]u8
```

Converts values in the range [0, 100) to a base 10 string.

### `alt`

```zig
pub fn alt(context: anytype, comptime func_name: @EnumLiteral(), ) Alt(@TypeOf(context), @field(@TypeOf(context), @tagName(func_name)))
```

Helper for calling alternate format methods besides one named "format".

### `other`

```zig
pub fn other(ex: @This(), w: *Writer) Writer.Error!void
```


### `parseInt`

```zig
pub fn parseInt(comptime T: type, buf: []const u8, base: u8) ParseIntError!T
```

Parses the string `buf` as signed or unsigned representation in the
specified base of an integral value of type `T`.

When `base` is zero the string prefix is examined to detect the true base:
 * A prefix of "0b" implies base=2,
 * A prefix of "0o" implies base=8,
 * A prefix of "0x" implies base=16,
 * Otherwise base=10 is assumed.

Ignores '_' character in `buf`.
See also `parseUnsigned`.

### `parseIntWithGenericCharacter`

```zig
pub fn parseIntWithGenericCharacter(comptime Result: type, comptime Character: type, buf: []const Character, base: u8, ) ParseIntError!Result
```

Like `parseInt`, but with a generic `Character` type.

### `parseUnsigned`

```zig
pub fn parseUnsigned(comptime T: type, buf: []const u8, base: u8) ParseIntError!T
```

Parses the string `buf` as unsigned representation in the specified base
of an integral value of type `T`.

When `base` is zero the string prefix is examined to detect the true base:
 * A prefix of "0b" implies base=2,
 * A prefix of "0o" implies base=8,
 * A prefix of "0x" implies base=16,
 * Otherwise base=10 is assumed.

Ignores '_' character in `buf`.
See also `parseInt`.

### `parseIntSizeSuffix`

```zig
pub fn parseIntSizeSuffix(buf: []const u8, digit_base: u8) ParseIntError!usize
```

Parses a number like '2G', '2Gi', or '2GiB'.

### `charToDigit`

```zig
pub fn charToDigit(c: u8, base: u8) (error{InvalidCharacter}!u8)
```


### `digitToChar`

```zig
pub fn digitToChar(digit: u8, case: Case) u8
```


### `bufPrint`

```zig
pub fn bufPrint(buf: []u8, comptime fmt: []const u8, args: anytype) BufPrintError![]u8
```

Deprecated in favor of `mem.print`.

### `bufPrintSentinel`

```zig
pub fn bufPrintSentinel(buf: []u8, comptime fmt: []const u8, args: anytype, comptime sentinel: u8, ) BufPrintError![:sentinel]u8
```

Deprecated in favor of `mem.printSentinel`.

### `count`

```zig
pub fn count(comptime fmt: []const u8, args: anytype) usize
```

Count the characters needed for format.

### `allocPrint`

```zig
pub fn allocPrint(gpa: Allocator, comptime fmt: []const u8, args: anytype) Allocator.Error![]u8
```

Deprecated in favor of `Allocator.print`.

### `allocPrintSentinel`

```zig
pub fn allocPrintSentinel(gpa: Allocator, comptime fmt: []const u8, args: anytype, comptime sentinel: u8, ) Allocator.Error![:sentinel]u8
```

Deprecated in favor of `Allocator.printSentinel`.

### `comptimePrint`

```zig
pub inline fn comptimePrint(comptime fmt: []const u8, args: anytype) *const [count(fmt, args):0]u8
```


### `format`

```zig
pub fn format(s: @This(), writer: *Writer) Writer.Error!void
```


### `bytesToHex`

```zig
pub fn bytesToHex(input: anytype, case: Case) [input.len * 2]u8
```

Encodes a sequence of bytes as hexadecimal digits.
Returns an array containing the encoded bytes.

### `hexToBytes`

```zig
pub fn hexToBytes(out: []u8, input: []const u8) ![]u8
```

Decodes the sequence of bytes represented by the specified string of
hexadecimal characters.
Returns a slice of the output buffer containing the decoded bytes.

### `format`

```zig
pub fn format(self: R, writer: *Writer) Writer.Error!void
```


### `hex`

```zig
pub fn hex(x: anytype) [@typeInfo(@TypeOf(x)).int.bits / 4]u8
```

Converts an unsigned integer of any multiple of u8 to an array of lowercase
hex bytes, little endian.

## Error Sets

- **`ParseIntError`**
  

## Constants & Variables

- **`float`**: 
- **`default_max_depth`**: 
- **`parseFloat`**: 
- **`ParseFloatError`**: 
- **`BufPrintError`**: Deprecated in favor of `mem.PrintError`.
- **`hex_charset`**: 

