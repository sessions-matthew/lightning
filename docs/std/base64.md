# `std.base64`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/base64.zig`  
> [← Back to Standard Library Index](README.md)

Base64 encoding/decoding as specified by
[RFC 4648](https://datatracker.ietf.org/doc/html/rfc4648).

## Types

### `Codecs`

Base64 codecs

### Fields

- `alphabet_chars: [64]u8`
  
- `pad_char: ?u8`
  
- `decoderWithIgnore: decoderWithIgnoreProto`
  
- `Encoder: Base64Encoder`
  
- `Decoder: Base64Decoder`
  

### `Base64Encoder`


### Fields

- `alphabet_chars: [64]u8`
  
- `pad_char: ?u8`
  

### Functions

#### `init`

```zig
pub fn init(alphabet_chars: [64]u8, pad_char: ?u8) Base64Encoder
```

A bunch of assertions, then simply pass the data right through.

#### `calcSize`

```zig
pub fn calcSize(encoder: *const Base64Encoder, source_len: usize) usize
```

Compute the encoded length

#### `encodeWriter`

```zig
pub fn encodeWriter(encoder: *const Base64Encoder, dest: *std.Io.Writer, source: []const u8) !void
```


#### `encode`

```zig
pub fn encode(encoder: *const Base64Encoder, dest: []u8, source: []const u8) []const u8
```

dest.len must at least be what you get from ::calcSize.

### `Base64Decoder`


### Fields

- `char_to_index: [256]u8`
  e.g. 'A' => 0.
  `invalid_char` for any value not in the 64 alphabet chars.
- `fast_char_to_index: [4][256]u32`
  
- `pad_char: ?u8`
  

### Functions

#### `init`

```zig
pub fn init(alphabet_chars: [64]u8, pad_char: ?u8) Base64Decoder
```


#### `calcSizeUpperBound`

```zig
pub fn calcSizeUpperBound(decoder: *const Base64Decoder, source_len: usize) Error!usize
```

Return the maximum possible decoded size for a given input length - The actual length may be less if the input includes padding.
`InvalidPadding` is returned if the input length is not valid.

#### `calcSizeForSlice`

```zig
pub fn calcSizeForSlice(decoder: *const Base64Decoder, source: []const u8) Error!usize
```

Return the exact decoded size for a slice.
`InvalidPadding` is returned if the input length is not valid.

#### `decode`

```zig
pub fn decode(decoder: *const Base64Decoder, dest: []u8, source: []const u8) Error!void
```

dest.len must be what you get from ::calcSize.
Invalid characters result in `error.InvalidCharacter`.
Invalid padding results in `error.InvalidPadding`.

### `Base64DecoderWithIgnore`


### Fields

- `decoder: Base64Decoder`
  
- `char_is_ignored: [256]bool`
  

### Functions

#### `init`

```zig
pub fn init(alphabet_chars: [64]u8, pad_char: ?u8, ignore_chars: []const u8) Base64DecoderWithIgnore
```


#### `calcSizeUpperBound`

```zig
pub fn calcSizeUpperBound(decoder_with_ignore: *const Base64DecoderWithIgnore, source_len: usize) usize
```

Return the maximum possible decoded size for a given input length - The actual length may be
less if the input includes padding or ignored characters.

#### `decode`

```zig
pub fn decode(decoder_with_ignore: *const Base64DecoderWithIgnore, dest: []u8, source: []const u8) Error!usize
```

Invalid characters that are not ignored result in error.InvalidCharacter.
Invalid padding results in error.InvalidPadding.
Decoding more data than can fit in dest results in error.NoSpaceLeft. See also ::calcSizeUpperBound.
Returns the number of bytes written to dest.

## Error Sets

- **`Error`**
  

## Constants & Variables

- **`standard_alphabet_chars`**: The Base64 alphabet defined in
- **`standard`**: Standard Base64 codecs, with padding, as defined in
- **`standard_no_pad`**: Standard Base64 codecs, without padding, as defined in
- **`url_safe_alphabet_chars`**: The URL-safe Base64 alphabet defined in
- **`url_safe`**: URL-safe Base64 codecs, with padding, as defined in
- **`url_safe_no_pad`**: URL-safe Base64 codecs, without padding, as defined in

