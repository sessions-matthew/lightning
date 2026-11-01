# `std.heap`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/heap.zig`  
> [← Back to Standard Library Index](README.md)

## Types

### `Check`

Deprecated.

### Fields

- `ok`
  
- `leak`
  

### `MemoryPool`

```zig
pub fn MemoryPool(comptime Item: type) type
```

A memory pool that can allocate objects of a single type very quickly.
Use this when you need to allocate a lot of objects of the same type,
because it outperforms general purpose allocators.
Functions that potentially allocate memory accept an `Allocator` parameter.

## Functions

### `pageSize`

```zig
pub inline fn pageSize() usize
```

If the page size is comptime-known, return value is comptime.
Otherwise, calls `std.options.queryPageSize` which by default queries the
host operating system at runtime.

### `defaultQueryPageSize`

```zig
pub fn defaultQueryPageSize() usize
```

The default implementation of `std.options.queryPageSize`.
Asserts that the page size is within `page_size_min` and `page_size_max`

### `testAllocator`

```zig
pub fn testAllocator(base_allocator: mem.Allocator) !void
```

This one should not try alignments that exceed what C malloc can handle.

### `testAllocatorAligned`

```zig
pub fn testAllocatorAligned(base_allocator: mem.Allocator) !void
```


### `testAllocatorLargeAlignment`

```zig
pub fn testAllocatorLargeAlignment(base_allocator: mem.Allocator) !void
```


### `testAllocatorAlignedShrink`

```zig
pub fn testAllocatorAlignedShrink(base_allocator: mem.Allocator) !void
```


## Constants & Variables

- **`ArenaAllocator`**: 
- **`SmpAllocator`**: 
- **`SafeAllocator`**: 
- **`FixedBufferAllocator`**: 
- **`BufferFirstAllocator`**: 
- **`PageAllocator`**: 
- **`WasmAllocator`**: 
- **`BrkAllocator`**: 
- **`DebugAllocatorConfig`**: Deprecated; use `SafeAllocator.Options`.
- **`DebugAllocator`**: Deprecated; use `SafeAllocator`.
- **`memory_pool`**: 
- **`page_size_min`**: comptime-known minimum page size of the target.
- **`page_size_max`**: comptime-known maximum page size of the target.
- **`c_allocator`**: A wrapper around the C memory allocation API which supports the full `Allocator`
- **`page_allocator`**: On operating systems that support memory mapping, this allocator makes a
- **`smp_allocator`**: 
- **`wasm_allocator`**: This allocator is fast, small, and specific to WebAssembly.
- **`brk_allocator`**: Supports single-threaded WebAssembly and Linux.

