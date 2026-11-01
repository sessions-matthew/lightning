# `std.dynamic_library`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/dynamic_library.zig`  
> [← Back to Standard Library Index](README.md)

## Types

### `DynLib`

Cross-platform dynamic library loading and symbol lookup.
Platform-specific functionality is available through the `inner` field.

### Fields

- `inner: InnerType`
  

### Functions

#### `open`

```zig
pub fn open(path: []const u8) Error!DynLib
```

Trusts the file. Malicious file will be able to execute arbitrary code.

#### `openZ`

```zig
pub fn openZ(path_c: [*:0]const u8) Error!DynLib
```

Trusts the file. Malicious file will be able to execute arbitrary code.

#### `close`

```zig
pub fn close(self: *DynLib) void
```

Trusts the file.

#### `lookup`

```zig
pub fn lookup(self: *DynLib, comptime T: type, name: [:0]const u8) ?T
```


### Error Sets

- **`Error`**
  

### `ElfDynLib`


### Fields

- `strings: [*:0]u8`
  
- `syms: [*]elf.Sym`
  
- `hash_table: HashTable`
  
- `versym: ?[*]elf.Versym`
  
- `verdef: ?*elf.Verdef`
  
- `memory: []align(std.heap.page_size_min) u8`
  

### Types

#### `GnuHashSection32`


#### `GnuHashSection64`


### Functions

#### `open`

```zig
pub fn open(path: []const u8, LD_LIBRARY_PATH: ?[]const u8) Error!ElfDynLib
```

Trusts the file. Malicious file will be able to execute arbitrary code.

#### `openZ`

```zig
pub fn openZ(path_c: [*:0]const u8, LD_LIBRARY_PATH: ?[]const u8) Error!ElfDynLib
```

Trusts the file. Malicious file will be able to execute arbitrary code.

#### `close`

```zig
pub fn close(self: *ElfDynLib) void
```

Trusts the file

#### `lookup`

```zig
pub fn lookup(self: *const ElfDynLib, comptime T: type, name: [:0]const u8) ?T
```


#### `lookupAddress`

```zig
pub fn lookupAddress(self: *const ElfDynLib, vername: []const u8, name: []const u8) ?usize
```

ElfDynLib specific
Returns the address of the symbol

### Constants & Variables

- **`Error`**: 

### `DlDynLib`


### Fields

- `handle: *anyopaque`
  

### Functions

#### `open`

```zig
pub fn open(path: []const u8) Error!DlDynLib
```


#### `openZ`

```zig
pub fn openZ(path_c: [*:0]const u8) Error!DlDynLib
```


#### `close`

```zig
pub fn close(self: *DlDynLib) void
```


#### `lookup`

```zig
pub fn lookup(self: *DlDynLib, comptime T: type, name: [:0]const u8) ?T
```


#### `getError`

```zig
pub fn getError() ?[:0]const u8
```

DlDynLib specific
Returns human readable string describing most recent error than occurred from `lookup`
or `null` if no error has occurred since initialization or when `getError` was last called.

### Constants & Variables

- **`Error`**: 

## Functions

### `get_DYNAMIC`

```zig
pub fn get_DYNAMIC() ?[*]const elf.Dyn
```

TODO fix comparisons of extern symbol pointers so we don't need this helper function.

### `linkmap_iterator`

```zig
pub fn linkmap_iterator() error{InvalidExe}!LinkMap.Iterator
```


