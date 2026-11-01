# `std.tz`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/tz.zig`  
> [← Back to Standard Library Index](README.md)

The Time Zone Information Format (TZif)
https://datatracker.ietf.org/doc/html/rfc8536

## Types

### `Transition`


### Fields

- `ts: i64`
  
- `timetype: *Timetype`
  

### `Timetype`


### Fields

- `offset: i32`
  
- `flags: u8`
  
- `name_data: [6:0]u8`
  

### Functions

#### `name`

```zig
pub fn name(self: *const Timetype) [:0]const u8
```


#### `isDst`

```zig
pub fn isDst(self: Timetype) bool
```


#### `standardTimeIndicator`

```zig
pub fn standardTimeIndicator(self: Timetype) bool
```


#### `utIndicator`

```zig
pub fn utIndicator(self: Timetype) bool
```


### `Leapsecond`


### Fields

- `occurrence: i48`
  
- `correction: i16`
  

### `Tz`


### Fields

- `allocator: Allocator`
  
- `transitions: []const Transition`
  
- `timetypes: []const Timetype`
  
- `leapseconds: []const Leapsecond`
  
- `footer: ?[]const u8`
  

### Functions

#### `parse`

```zig
pub fn parse(allocator: Allocator, reader: *Reader) !Tz
```


#### `deinit`

```zig
pub fn deinit(self: *Tz) void
```


