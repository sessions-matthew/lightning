# `std.buf_map`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/buf_map.zig`  
> [← Back to Standard Library Index](README.md)

## Types

### `BufMap`

BufMap copies keys and values before they go into the map and
frees them when they get removed.

### Fields

- `hash_map: BufMapHashMap`
  

### Functions

#### `init`

```zig
pub fn init(allocator: Allocator) BufMap
```

Create a BufMap backed by a specific allocator.
That allocator will be used for both backing allocations
and string deduplication.

#### `deinit`

```zig
pub fn deinit(self: *BufMap) void
```

Free the backing storage of the map, as well as all
of the stored keys and values.

#### `putMove`

```zig
pub fn putMove(self: *BufMap, key: []u8, value: []u8) !void
```

Same as `put` but the key and value become owned by the BufMap rather
than being copied.
If `putMove` fails, the ownership of key and value does not transfer.

#### `put`

```zig
pub fn put(self: *BufMap, key: []const u8, value: []const u8) !void
```

`key` and `value` are copied into the BufMap.

#### `getPtr`

```zig
pub fn getPtr(self: BufMap, key: []const u8) ?*[]const u8
```

Find the address of the value associated with a key.
The returned pointer is invalidated if the map resizes.

#### `get`

```zig
pub fn get(self: BufMap, key: []const u8) ?[]const u8
```

Return the map's copy of the value associated with
a key.  The returned string is invalidated if this
key is removed from the map.

#### `remove`

```zig
pub fn remove(self: *BufMap, key: []const u8) void
```

Removes the item from the map and frees its value.
This invalidates the value returned by get() for this key.

#### `count`

```zig
pub fn count(self: BufMap) BufMapHashMap.Size
```

Returns the number of KV pairs stored in the map.

#### `iterator`

```zig
pub fn iterator(self: *const BufMap) BufMapHashMap.Iterator
```

Returns an iterator over entries in the map.

