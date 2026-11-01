# `std.ascii`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/ascii.zig`  
> [← Back to Standard Library Index](README.md)

The 7-bit [ASCII](https://en.wikipedia.org/wiki/ASCII) character encoding standard.

This is not to be confused with the 8-bit [extended ASCII](https://en.wikipedia.org/wiki/Extended_ASCII) character encoding.

Even though this module concerns itself with 7-bit ASCII,
functions use `u8` as the type instead of `u7` for convenience and compatibility.
Characters outside of the 7-bit range are gracefully handled (e.g. by returning `false`).

See also: https://en.wikipedia.org/wiki/ASCII#Character_set

## Types

### `HexEscape`


### Fields

- `bytes: []const u8`
  
- `charset: *const [16]u8`
  

### Functions

#### `format`

```zig
pub fn format(se: HexEscape, w: *std.Io.Writer) std.Io.Writer.Error!void
```


### Constants & Variables

- **`upper_charset`**: 
- **`lower_charset`**: 

## Namespaces

- **`control_code`**: The C0 control codes of the ASCII encoding.

## Functions

### `isAlphanumeric`

```zig
pub fn isAlphanumeric(c: u8) bool
```

Returns whether the character is alphanumeric: A-Z, a-z, or 0-9.

### `isAlphabetic`

```zig
pub fn isAlphabetic(c: u8) bool
```

Returns whether the character is alphabetic: A-Z or a-z.

### `isControl`

```zig
pub fn isControl(c: u8) bool
```

Returns whether the character is a control character.

See also: `control_code`

### `isDigit`

```zig
pub fn isDigit(c: u8) bool
```

Returns whether the character is a digit.

### `isLower`

```zig
pub fn isLower(c: u8) bool
```

Returns whether the character is a lowercase letter.

### `isPrint`

```zig
pub fn isPrint(c: u8) bool
```

Returns whether the character is printable and has some graphical representation,
including the space character.

### `isGraphical`

```zig
pub fn isGraphical(c: u8) bool
```

Returns whether the character has some graphical representation,

### `isPunctuation`

```zig
pub fn isPunctuation(c: u8) bool
```

Returns whether the character is a punctuation character.

### `isWhitespace`

```zig
pub fn isWhitespace(c: u8) bool
```

Returns whether this character is included in `whitespace`.

### `isUpper`

```zig
pub fn isUpper(c: u8) bool
```

Returns whether the character is an uppercase letter.

### `isHex`

```zig
pub fn isHex(c: u8) bool
```

Returns whether the character is a hexadecimal digit: A-F, a-f, or 0-9.

### `isAscii`

```zig
pub fn isAscii(c: u8) bool
```

Returns whether the character is a 7-bit ASCII character.

### `toUpper`

```zig
pub fn toUpper(c: u8) u8
```

Uppercases the character and returns it as-is if already uppercase or not a letter.

### `toLower`

```zig
pub fn toLower(c: u8) u8
```

Lowercases the character and returns it as-is if already lowercase or not a letter.

### `lowerString`

```zig
pub fn lowerString(output: []u8, ascii_string: []const u8) []u8
```

Writes a lower case copy of `ascii_string` to `output`.
Asserts `output.len >= ascii_string.len`.

### `allocLowerString`

```zig
pub fn allocLowerString(allocator: std.mem.Allocator, ascii_string: []const u8) ![]u8
```

Allocates a lower case copy of `ascii_string`.
Caller owns returned string and must free with `allocator`.

### `upperString`

```zig
pub fn upperString(output: []u8, ascii_string: []const u8) []u8
```

Writes an upper case copy of `ascii_string` to `output`.
Asserts `output.len >= ascii_string.len`.

### `allocUpperString`

```zig
pub fn allocUpperString(allocator: std.mem.Allocator, ascii_string: []const u8) ![]u8
```

Allocates an upper case copy of `ascii_string`.
Caller owns returned string and must free with `allocator`.

### `eqlIgnoreCase`

```zig
pub fn eqlIgnoreCase(a: []const u8, b: []const u8) bool
```

Compares strings `a` and `b` case-insensitively and returns whether they are equal.

### `startsWithIgnoreCase`

```zig
pub fn startsWithIgnoreCase(haystack: []const u8, needle: []const u8) bool
```


### `endsWithIgnoreCase`

```zig
pub fn endsWithIgnoreCase(haystack: []const u8, needle: []const u8) bool
```


### `findIgnoreCase`

```zig
pub fn findIgnoreCase(haystack: []const u8, needle: []const u8) ?usize
```

Finds `needle` in `haystack`, ignoring case, starting at index 0.

### `findIgnoreCasePos`

```zig
pub fn findIgnoreCasePos(haystack: []const u8, start_index: usize, needle: []const u8) ?usize
```

Finds `needle` in `haystack`, ignoring case, starting at `start_index`.
Uses Boyer-Moore-Horspool algorithm on large inputs; `findIgnoreCasePosLinear` on small inputs.

### `findIgnoreCasePosLinear`

```zig
pub fn findIgnoreCasePosLinear(haystack: []const u8, start_index: usize, needle: []const u8) ?usize
```

Consider using `findIgnoreCasePos` instead of this, which will automatically use a
more sophisticated algorithm on larger inputs.

### `orderIgnoreCase`

```zig
pub fn orderIgnoreCase(lhs: []const u8, rhs: []const u8) std.math.Order
```

Returns the lexicographical order of two slices. O(n).

### `orderIgnoreCaseZ`

```zig
pub fn orderIgnoreCaseZ(lhs: [*:0]const u8, rhs: [*:0]const u8) std.math.Order
```

Returns the lexicographical order of two many-item pointers with NUL-termination. O(n).

### `boundedOrderIgnoreCaseZ`

```zig
pub fn boundedOrderIgnoreCaseZ(lhs: [*:0]const u8, rhs: [*:0]const u8, bound: usize) std.math.Order
```

Returns the lexicographical order of two many-item pointers with NUL-termination until some specified bound. O(n).

### `lessThanIgnoreCase`

```zig
pub fn lessThanIgnoreCase(lhs: []const u8, rhs: []const u8) bool
```

Returns whether the lexicographical order of `lhs` is lower than `rhs`.

### `hexEscape`

```zig
pub fn hexEscape(bytes: []const u8, case: std.fmt.Case) HexEscape
```

Replaces non-ASCII bytes with hex escapes.

## Constants & Variables

- **`lowercase`**: 
- **`uppercase`**: 
- **`letters`**: 
- **`whitespace`**: Whitespace for general use.

