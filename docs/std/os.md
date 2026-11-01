# `std.os`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/os.zig`  
> [← Back to Standard Library Index](README.md)

## Functions

### `targetRequiresLibC`

```zig
pub fn targetRequiresLibC(target: *const std.Target) bool
```

Returns whether the Zig standard library requires libc in order to interface
with the operating system on the given target.

### `requiresLibC`

```zig
pub fn requiresLibC() bool
```

Returns whether the Zig standard library requires libc in order to interface
with the operating system on the current target.

## Constants & Variables

- **`linux`**: 
- **`plan9`**: 
- **`uefi`**: 
- **`wasi`**: 
- **`emscripten`**: 
- **`windows`**: 

