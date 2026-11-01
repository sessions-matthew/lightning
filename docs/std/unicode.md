# `std.unicode`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/unicode.zig`  
> [← Back to Standard Library Index](README.md)

## Types

### `Utf8View`

Utf8View iterates the code points of a utf-8 encoded string.

```
var utf8 = (try std.unicode.Utf8View.init("hi there")).iterator();
while (utf8.nextCodepointSlice()) |codepoint| {
  std.debug.print("got codepoint {s}\n", .{codepoint});
}
```

### Fields

- `bytes: []const u8`
  

### Functions

#### `init`

```zig
pub fn init(s: []const u8) !Utf8View
```


#### `initUnchecked`

```zig
pub fn initUnchecked(s: []const u8) Utf8View
```


#### `initComptime`

```zig
pub inline fn initComptime(comptime s: []const u8) Utf8View
```


#### `iterator`

```zig
pub fn iterator(s: Utf8View) Utf8Iterator
```


### `Utf8Iterator`


### Fields

- `bytes: []const u8`
  
- `i: usize`
  

### Functions

#### `nextCodepointSlice`

```zig
pub fn nextCodepointSlice(it: *Utf8Iterator) ?[]const u8
```


#### `nextCodepoint`

```zig
pub fn nextCodepoint(it: *Utf8Iterator) ?u21
```


#### `peek`

```zig
pub fn peek(it: *Utf8Iterator, n: usize) []const u8
```

Look ahead at the next n codepoints without advancing the iterator.
If fewer than n codepoints are available, then return the remainder of the string.

#### `peekCodepoint`

```zig
pub fn peekCodepoint(it: *Utf8Iterator) ?u21
```

Look ahead at the next codepoint without advancing the iterator.
If no codepoints exist, then returns null.

### `Utf16LeIterator`


### Fields

- `bytes: []const u8`
  
- `i: usize`
  

### Functions

#### `init`

```zig
pub fn init(s: []const u16) Utf16LeIterator
```


#### `nextCodepoint`

```zig
pub fn nextCodepoint(it: *Utf16LeIterator) NextCodepointError!?u21
```


### Error Sets

- **`NextCodepointError`**
  

### `Wtf8View`

Wtf8View iterates the code points of a WTF-8 encoded string,
including surrogate halves.

```
var wtf8 = (try std.unicode.Wtf8View.init("hi there")).iterator();
while (wtf8.nextCodepointSlice()) |codepoint| {
  // note: codepoint could be a surrogate half which is invalid
  // UTF-8, avoid printing or otherwise sending/emitting this directly
}
```

### Fields

- `bytes: []const u8`
  

### Functions

#### `init`

```zig
pub fn init(s: []const u8) error{InvalidWtf8}!Wtf8View
```


#### `initUnchecked`

```zig
pub fn initUnchecked(s: []const u8) Wtf8View
```


#### `initComptime`

```zig
pub inline fn initComptime(comptime s: []const u8) Wtf8View
```


#### `iterator`

```zig
pub fn iterator(s: Wtf8View) Wtf8Iterator
```


### `Wtf8Iterator`

Asserts that `bytes` is valid WTF-8

### Fields

- `bytes: []const u8`
  
- `i: usize`
  

### Functions

#### `nextCodepointSlice`

```zig
pub fn nextCodepointSlice(it: *Wtf8Iterator) ?[]const u8
```


#### `nextCodepoint`

```zig
pub fn nextCodepoint(it: *Wtf8Iterator) ?u21
```


#### `peek`

```zig
pub fn peek(it: *Wtf8Iterator, n: usize) []const u8
```

Look ahead at the next n codepoints without advancing the iterator.
If fewer than n codepoints are available, then return the remainder of the string.

#### `peekCodepoint`

```zig
pub fn peekCodepoint(it: *Wtf8Iterator) ?u21
```

Look ahead at the next codepoint without advancing the iterator.
If no codepoints exist, then returns null.

### `Wtf16LeIterator`


### Fields

- `bytes: []const u8`
  
- `i: usize`
  

### Functions

#### `init`

```zig
pub fn init(s: []const u16) Wtf16LeIterator
```


#### `nextCodepoint`

```zig
pub fn nextCodepoint(it: *Wtf16LeIterator) ?u21
```

If the next codepoint is encoded by a surrogate pair, returns the
codepoint that the surrogate pair represents.
If the next codepoint is an unpaired surrogate, returns the codepoint
of the unpaired surrogate.

## Functions

### `utf8CodepointSequenceLength`

```zig
pub fn utf8CodepointSequenceLength(c: u21) !u3
```

Returns how many bytes the UTF-8 representation would require
for the given codepoint.

### `utf8ByteSequenceLength`

```zig
pub fn utf8ByteSequenceLength(first_byte: u8) !u3
```

Given the first byte of a UTF-8 codepoint,
returns a number 1-4 indicating the total length of the codepoint in bytes.
If this byte does not match the form of a UTF-8 start byte, returns Utf8InvalidStartByte.

### `utf8Encode`

```zig
pub fn utf8Encode(c: u21, out: []u8) error{ Utf8CannotEncodeSurrogateHalf, CodepointTooLarge }!u3
```

Encodes the given codepoint into a UTF-8 byte sequence.
c: the codepoint.
out: the out buffer to write to. Must have a len >= utf8CodepointSequenceLength(c).
Errors: if c cannot be encoded in UTF-8.
Returns: the number of bytes written to out.

### `utf8EncodeComptime`

```zig
pub inline fn utf8EncodeComptime(comptime c: u21) [ utf8CodepointSequenceLength(c) catch |err| @compileError(@errorName(err)) ]u8
```


### `utf8Decode`

```zig
pub fn utf8Decode(bytes: []const u8) Utf8DecodeError!u21
```

Deprecated. This function has an awkward API that is too easy to use incorrectly.

### `utf8Decode2`

```zig
pub fn utf8Decode2(bytes: [2]u8) Utf8Decode2Error!u21
```


### `utf8Decode3`

```zig
pub fn utf8Decode3(bytes: [3]u8) Utf8Decode3Error!u21
```


### `utf8Decode3AllowSurrogateHalf`

```zig
pub fn utf8Decode3AllowSurrogateHalf(bytes: [3]u8) Utf8Decode3AllowSurrogateHalfError!u21
```


### `utf8Decode4`

```zig
pub fn utf8Decode4(bytes: [4]u8) Utf8Decode4Error!u21
```


### `utf8ValidCodepoint`

```zig
pub fn utf8ValidCodepoint(value: u21) bool
```

Returns true if the given unicode codepoint can be encoded in UTF-8.

### `utf8CountCodepoints`

```zig
pub fn utf8CountCodepoints(s: []const u8) !usize
```

Returns the length of a supplied UTF-8 string literal in terms of unicode
codepoints.

### `utf8ValidateSlice`

```zig
pub fn utf8ValidateSlice(input: []const u8) bool
```

Returns true if the input consists entirely of UTF-8 codepoints

### `utf16IsHighSurrogate`

```zig
pub fn utf16IsHighSurrogate(c: u16) bool
```


### `utf16IsLowSurrogate`

```zig
pub fn utf16IsLowSurrogate(c: u16) bool
```


### `utf16CodepointSequenceLength`

```zig
pub fn utf16CodepointSequenceLength(c: u21) !u2
```

Returns how many code units the UTF-16 representation would require
for the given codepoint.

### `utf16CodeUnitSequenceLength`

```zig
pub fn utf16CodeUnitSequenceLength(first_code_unit: u16) !u2
```

Given the first code unit of a UTF-16 codepoint, returns a number 1-2
indicating the total length of the codepoint in UTF-16 code units.
If this code unit does not match the form of a UTF-16 start code unit, returns Utf16InvalidStartCodeUnit.

### `utf16DecodeSurrogatePair`

```zig
pub fn utf16DecodeSurrogatePair(surrogate_pair: []const u16) !u21
```

Decodes the codepoint encoded in the given pair of UTF-16 code units.
Asserts that `surrogate_pair.len >= 2` and that the first code unit is a high surrogate.
If the second code unit is not a low surrogate, error.ExpectedSecondSurrogateHalf is returned.

### `utf16CountCodepoints`

```zig
pub fn utf16CountCodepoints(utf16le: []const u16) !usize
```

Returns the length of a supplied UTF-16 string literal in terms of unicode
codepoints.

### `fmtUtf8`

```zig
pub fn fmtUtf8(utf8: []const u8) std.fmt.Alt([]const u8, formatUtf8)
```

Return a Formatter for a (potentially ill-formed) UTF-8 string.
Ill-formed UTF-8 byte sequences are replaced by the replacement character (U+FFFD)
according to "U+FFFD Substitution of Maximal Subparts" from Chapter 3 of
the Unicode standard, and as specified by https://encoding.spec.whatwg.org/#utf-8-decoder

### `utf16LeToUtf8ArrayList`

```zig
pub fn utf16LeToUtf8ArrayList(result: *std.array_list.Managed(u8), utf16le: []const u16) Utf16LeToUtf8AllocError!void
```


### `utf16LeToUtf8Alloc`

```zig
pub fn utf16LeToUtf8Alloc(allocator: Allocator, utf16le: []const u16) Utf16LeToUtf8AllocError![]u8
```

Caller owns returned memory.

### `utf16LeToUtf8AllocZ`

```zig
pub fn utf16LeToUtf8AllocZ(allocator: Allocator, utf16le: []const u16) Utf16LeToUtf8AllocError![:0]u8
```

Caller owns returned memory.

### `utf16LeToUtf8`

```zig
pub fn utf16LeToUtf8(utf8: []u8, utf16le: []const u16) Utf16LeToUtf8Error!usize
```


### `utf8ToUtf16LeArrayList`

```zig
pub fn utf8ToUtf16LeArrayList(result: *std.array_list.Managed(u16), utf8: []const u8) error{ InvalidUtf8, OutOfMemory }!void
```


### `utf8ToUtf16LeAlloc`

```zig
pub fn utf8ToUtf16LeAlloc(allocator: Allocator, utf8: []const u8) error{ InvalidUtf8, OutOfMemory }![]u16
```


### `utf8ToUtf16LeAllocZ`

```zig
pub fn utf8ToUtf16LeAllocZ(allocator: Allocator, utf8: []const u8) error{ InvalidUtf8, OutOfMemory }![:0]u16
```


### `utf8ToUtf16Le`

```zig
pub fn utf8ToUtf16Le(utf16le: []u16, utf8: []const u8) error{InvalidUtf8}!usize
```

Returns index of next character. If exact fit, returned index equals output slice length.
Assumes there is enough space for the output.

### `utf8ToUtf16LeImpl`

```zig
pub fn utf8ToUtf16LeImpl(utf16le: []u16, utf8: []const u8, comptime surrogates: Surrogates) !usize
```


### `utf8ToUtf16LeStringLiteral`

```zig
pub fn utf8ToUtf16LeStringLiteral(comptime utf8: []const u8) *const [calcUtf16LeLen(utf8) catch |err| @compileError(err):0]u16
```

Converts a UTF-8 string literal into a UTF-16LE string literal.

### `wtf8ToWtf16LeStringLiteral`

```zig
pub fn wtf8ToWtf16LeStringLiteral(comptime wtf8: []const u8) *const [calcWtf16LeLen(wtf8) catch |err| @compileError(err):0]u16
```

Converts a WTF-8 string literal into a WTF-16LE string literal.

### `calcUtf16LeLenImpl`

```zig
pub fn calcUtf16LeLenImpl(utf8: []const u8, comptime surrogates: Surrogates) !usize
```


### `calcUtf16LeLen`

```zig
pub fn calcUtf16LeLen(utf8: []const u8) CalcUtf16LeLenError!usize
```

Returns length in UTF-16LE of UTF-8 slice as length of []u16.
Length in []u8 is 2*len16.

### `calcWtf16LeLen`

```zig
pub fn calcWtf16LeLen(wtf8: []const u8) CalcWtf16LeLenError!usize
```

Returns length in WTF-16LE of WTF-8 slice as length of []u16.
Length in []u8 is 2*len16.

### `fmtUtf16Le`

```zig
pub fn fmtUtf16Le(utf16le: []const u16) std.fmt.Alt([]const u16, formatUtf16Le)
```

Return a Formatter for a (potentially ill-formed) UTF-16 LE string,
which will be converted to UTF-8 during formatting.
Unpaired surrogates are replaced by the replacement character (U+FFFD).

### `isSurrogateCodepoint`

```zig
pub fn isSurrogateCodepoint(c: u21) bool
```

Returns true if the codepoint is a surrogate (U+DC00 to U+DFFF)

### `wtf8Encode`

```zig
pub fn wtf8Encode(c: u21, out: []u8) error{CodepointTooLarge}!u3
```

Encodes the given codepoint into a WTF-8 byte sequence.
c: the codepoint.
out: the out buffer to write to. Must have a len >= utf8CodepointSequenceLength(c).
Errors: if c cannot be encoded in WTF-8.
Returns: the number of bytes written to out.

### `wtf8Decode`

```zig
pub fn wtf8Decode(bytes: []const u8) Wtf8DecodeError!u21
```

Deprecated. This function has an awkward API that is too easy to use incorrectly.

### `wtf8ValidateSlice`

```zig
pub fn wtf8ValidateSlice(input: []const u8) bool
```

Returns true if the input consists entirely of WTF-8 codepoints
(all the same restrictions as UTF-8, but allows surrogate codepoints
U+D800 to U+DFFF).
Does not check for well-formed WTF-8, meaning that this function
does not check that all surrogate halves are unpaired.

### `wtf16LeToWtf8ArrayList`

```zig
pub fn wtf16LeToWtf8ArrayList(result: *std.array_list.Managed(u8), utf16le: []const u16) Allocator.Error!void
```


### `wtf16LeToWtf8Alloc`

```zig
pub fn wtf16LeToWtf8Alloc(allocator: Allocator, wtf16le: []const u16) Allocator.Error![]u8
```

Caller must free returned memory.

### `wtf16LeToWtf8AllocZ`

```zig
pub fn wtf16LeToWtf8AllocZ(allocator: Allocator, wtf16le: []const u16) Allocator.Error![:0]u8
```

Caller must free returned memory.

### `wtf16LeToWtf8`

```zig
pub fn wtf16LeToWtf8(wtf8: []u8, wtf16le: []const u16) usize
```


### `wtf8ToWtf16LeArrayList`

```zig
pub fn wtf8ToWtf16LeArrayList(result: *std.array_list.Managed(u16), wtf8: []const u8) error{ InvalidWtf8, OutOfMemory }!void
```


### `wtf8ToWtf16LeAlloc`

```zig
pub fn wtf8ToWtf16LeAlloc(allocator: Allocator, wtf8: []const u8) error{ InvalidWtf8, OutOfMemory }![]u16
```


### `wtf8ToWtf16LeAllocZ`

```zig
pub fn wtf8ToWtf16LeAllocZ(allocator: Allocator, wtf8: []const u8) error{ InvalidWtf8, OutOfMemory }![:0]u16
```


### `wtf8ToWtf16Le`

```zig
pub fn wtf8ToWtf16Le(wtf16le: []u16, wtf8: []const u8) error{InvalidWtf8}!usize
```

Returns index of next character. If exact fit, returned index equals output slice length.
Assumes there is enough space for the output.

### `wtf8ToUtf8Lossy`

```zig
pub fn wtf8ToUtf8Lossy(utf8: []u8, wtf8: []const u8) error{InvalidWtf8}!void
```

Surrogate codepoints (U+D800 to U+DFFF) are replaced by the Unicode replacement
character (U+FFFD).
All surrogate codepoints and the replacement character are encoded as three
bytes, meaning the input and output slices will always be the same length.
In-place conversion is supported when `utf8` and `wtf8` refer to the same slice.
Note: If `wtf8` is entirely composed of well-formed UTF-8, then no conversion is necessary.
      `utf8ValidateSlice` can be used to check if lossy conversion is worthwhile.
If `wtf8` is not valid WTF-8, then `error.InvalidWtf8` is returned.

### `wtf8ToUtf8LossyAlloc`

```zig
pub fn wtf8ToUtf8LossyAlloc(allocator: Allocator, wtf8: []const u8) error{ InvalidWtf8, OutOfMemory }![]u8
```


### `wtf8ToUtf8LossyAllocZ`

```zig
pub fn wtf8ToUtf8LossyAllocZ(allocator: Allocator, wtf8: []const u8) error{ InvalidWtf8, OutOfMemory }![:0]u8
```


### `calcWtf8Len`

```zig
pub fn calcWtf8Len(wtf16le: []const u16) usize
```

Returns the length, in bytes, that would be necessary to encode the
given WTF-16 LE slice as WTF-8.

## Error Sets

- **`Utf16LeToUtf8AllocError`**
  

## Constants & Variables

- **`replacement_character`**: Use this to replace an unknown, unrecognized, or unrepresentable character.
- **`replacement_character_utf8`**: 
- **`Utf16LeToUtf8Error`**: 

