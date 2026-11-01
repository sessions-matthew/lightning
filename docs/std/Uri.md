# `std.Uri`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/Uri.zig`  
> [← Back to Standard Library Index](README.md)

Uniform Resource Identifier (URI) parsing roughly adhering to
<https://tools.ietf.org/html/rfc3986>. Does not do perfect grammar and
character class checking, but should be robust against URIs in the wild.

## Fields

- `scheme: []const u8`
  
- `user: ?Component = null`
  
- `password: ?Component = null`
  
- `host: ?Component = null`
  
- `port: ?u16 = null`
  
- `path: Component = Component.empty`
  
- `query: ?Component = null`
  
- `fragment: ?Component = null`
  

## Types

### `Component`


### Fields

- `raw: []const u8`
  Invalid characters in this component must be percent encoded
  before being printed as part of a URI.
- `percent_encoded: []const u8`
  This component is already percent-encoded, it can be printed
  directly as part of a URI.

### Functions

#### `isEmpty`

```zig
pub fn isEmpty(component: Component) bool
```


#### `toRaw`

```zig
pub fn toRaw(component: Component, buffer: []u8) error{NoSpaceLeft}![]const u8
```

Returned value may point into `buffer` or be the original string.

#### `toRawMaybeAlloc`

```zig
pub fn toRawMaybeAlloc(component: Component, arena: Allocator) Allocator.Error![]const u8
```

Allocates the result with `arena` only if needed, so the result should not be freed.

#### `formatRaw`

```zig
pub fn formatRaw(component: Component, w: *Writer) Writer.Error!void
```


#### `formatEscaped`

```zig
pub fn formatEscaped(component: Component, w: *Writer) Writer.Error!void
```


#### `formatUser`

```zig
pub fn formatUser(component: Component, w: *Writer) Writer.Error!void
```


#### `formatPassword`

```zig
pub fn formatPassword(component: Component, w: *Writer) Writer.Error!void
```


#### `formatHost`

```zig
pub fn formatHost(component: Component, w: *Writer) Writer.Error!void
```


#### `formatPath`

```zig
pub fn formatPath(component: Component, w: *Writer) Writer.Error!void
```


#### `formatQuery`

```zig
pub fn formatQuery(component: Component, w: *Writer) Writer.Error!void
```


#### `formatFragment`

```zig
pub fn formatFragment(component: Component, w: *Writer) Writer.Error!void
```


#### `percentEncode`

```zig
pub fn percentEncode(w: *Writer, raw: []const u8, comptime isValidChar: fn (u8) bool) Writer.Error!void
```


### Constants & Variables

- **`empty`**: 

### `Format`


### Fields

- `uri: *const Uri`
  
- `flags: Flags = .{}`
  

### Types

#### `Flags`


### Functions

#### `default`

```zig
pub fn default(f: Format, writer: *Writer) Writer.Error!void
```


## Functions

### `percentDecodeBackwards`

```zig
pub fn percentDecodeBackwards(output: []u8, input: []const u8) []u8
```

Percent decodes all %XX where XX is a valid hex number.
`output` may alias `input` if `output.ptr <= input.ptr`.
Mutates and returns a subslice of `output`.

### `percentDecodeInPlace`

```zig
pub fn percentDecodeInPlace(buffer: []u8) []u8
```

Percent decodes all %XX where XX is a valid hex number.
Mutates and returns a subslice of `buffer`.

### `parseAfterScheme`

```zig
pub fn parseAfterScheme(scheme: []const u8, text: []const u8) ParseError!Uri
```

Parses the URI or returns an error. This function is not compliant, but is required to parse
some forms of URIs in the wild, such as HTTP Location headers.
The return value will contain strings pointing into the original `text`.
Each component that is provided, will be non-`null`.

### `format`

```zig
pub fn format(uri: *const Uri, writer: *Writer) Writer.Error!void
```


### `writeToStream`

```zig
pub fn writeToStream(uri: *const Uri, writer: *Writer, flags: Format.Flags) Writer.Error!void
```


### `fmt`

```zig
pub fn fmt(uri: *const Uri, flags: Format.Flags) std.fmt.Alt(Format, Format.default)
```


### `parse`

```zig
pub fn parse(text: []const u8) ParseError!Uri
```

The return value will contain strings pointing into the original `text`.
Each component that is provided will be non-`null`.

### `resolveInPlace`

```zig
pub fn resolveInPlace(base: Uri, new_len: usize, aux_buf: *[]u8) ResolveInPlaceError!Uri
```

Resolves a URI against a base URI, conforming to
[RFC 3986, Section 5](https://www.rfc-editor.org/rfc/rfc3986#section-5)

Assumes new location is already copied to the beginning of `aux_buf.*`.
Parses that new location as a URI, and then resolves the path in place.

If a merge needs to take place, the newly constructed path will be stored
in `aux_buf.*` just after the copied location, and `aux_buf.*` will be
modified to only contain the remaining unused space.

## Error Sets

- **`ParseError`**
  
- **`ResolveInPlaceError`**
  

## Constants & Variables

- **`getHost`**: 
- **`getHostAlloc`**: 

