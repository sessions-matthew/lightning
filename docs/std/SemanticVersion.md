# `std.SemanticVersion`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/SemanticVersion.zig`  
> [← Back to Standard Library Index](README.md)

A software version formatted according to the Semantic Versioning 2.0.0 specification.

See: https://semver.org

## Fields

- `major: usize`
  
- `minor: usize`
  
- `patch: usize`
  
- `pre: ?[]const u8 = null`
  
- `build: ?[]const u8 = null`
  

## Types

### `Range`


### Fields

- `min: Version`
  
- `max: Version`
  

### Functions

#### `includesVersion`

```zig
pub fn includesVersion(self: Range, ver: Version) bool
```


#### `isAtLeast`

```zig
pub fn isAtLeast(self: Range, ver: Version) ?bool
```

Checks if system is guaranteed to be at least `version` or older than `version`.
Returns `null` if a runtime check is required.

## Functions

### `order`

```zig
pub fn order(lhs: Version, rhs: Version) std.math.Order
```


### `parse`

```zig
pub fn parse(text: []const u8) !Version
```


### `format`

```zig
pub fn format(self: Version, w: *std.Io.Writer) std.Io.Writer.Error!void
```


