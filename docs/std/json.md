# `std.json`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/json.zig`  
> [← Back to Standard Library Index](README.md)

JSON parsing and stringification conforming to RFC 8259. https://datatracker.ietf.org/doc/html/rfc8259

The low-level `Scanner` API produces `Token`s from an input slice or successive slices of inputs,
The `Reader` API connects a `std.Io.Reader` to a `Scanner`.

The high-level `parseFromSlice` and `parseFromTokenSource` deserialize a JSON document into a Zig type.
Parse into a dynamically-typed `Value` to load any JSON value for runtime inspection.

The low-level `writeStream` emits syntax-conformant JSON tokens to a `std.Io.Writer`.
The high-level `stringify` serializes a Zig or `Value` type into JSON.

## Types

### `Formatter`

```zig
pub fn Formatter(comptime T: type) type
```

Formats the given value using stringify.

### Fields

- `value: T`
  
- `options: Stringify.Options`
  

### Functions

#### `format`

```zig
pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void
```


## Functions

### `fmt`

```zig
pub fn fmt(value: anytype, options: Stringify.Options) Formatter(@TypeOf(value))
```

Returns a formatter that formats the given value using stringify.

## Constants & Variables

- **`ObjectMap`**: 
- **`Array`**: 
- **`Value`**: 
- **`ArrayHashMap`**: 
- **`Scanner`**: 
- **`validate`**: 
- **`Error`**: 
- **`default_buffer_size`**: 
- **`Token`**: 
- **`TokenType`**: 
- **`Diagnostics`**: 
- **`AllocWhen`**: 
- **`default_max_value_len`**: 
- **`Reader`**: 
- **`isNumberFormattedLikeAnInteger`**: 
- **`ParseOptions`**: 
- **`Parsed`**: 
- **`parseFromSlice`**: 
- **`parseFromSliceLeaky`**: 
- **`parseFromTokenSource`**: 
- **`parseFromTokenSourceLeaky`**: 
- **`innerParse`**: 
- **`parseFromValue`**: 
- **`parseFromValueLeaky`**: 
- **`innerParseFromValue`**: 
- **`ParseError`**: 
- **`ParseFromValueError`**: 
- **`Stringify`**: 

