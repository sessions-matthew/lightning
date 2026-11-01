# `std.heap.DebugAllocator`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/heap/debug_allocator.zig`  
> [← Back to Standard Library Index](README.md)

An allocator that is intended to be used in Debug mode.

## Features

* Captures stack traces on allocation, free, and optionally resize.
* Double free detection, which prints all three traces (first alloc, first
  free, second free).
* Leak detection, with stack traces.
* Never reuses memory addresses, making it easier for Zig to detect branch
  on undefined values in case of dangling pointers. This relies on
  the backing allocator to also not reuse addresses.
* Uses a minimum backing allocation size to avoid operating system errors
  from having too many active memory mappings.
* When a page of memory is no longer needed, give it back to resident
  memory as soon as possible, so that it causes page faults when used.
* Cross platform. Operates based on a backing allocator which makes it work
  everywhere, even freestanding.
* Compile-time configuration.

These features require the allocator to be quite slow and wasteful. For
example, when allocating a single byte, the efficiency is less than 1%;
it requires more than 100 bytes of overhead to manage the allocation for
one byte. The efficiency gets better with larger allocations.

## Basic Design

Allocations are divided into two categories, small and large.

Small allocations are divided into buckets based on `page_size`:

```
index obj_size
0     1
1     2
2     4
3     8
4     16
5     32
6     64
7     128
8     256
9     512
10    1024
11    2048
...
```

This goes on for `small_bucket_count` indexes.

Allocations are grouped into an object size based on max(len, alignment),
rounded up to the next power of two.

The main allocator state has an array of all the "current" buckets for each
size class. Each slot in the array can be null, meaning the bucket for that
size class is not allocated. When the first object is allocated for a given
size class, it makes one `page_size` allocation from the backing allocator.
This allocation is divided into "slots" - one per allocated object, leaving
room for the allocation metadata (starting with `BucketHeader`), which is
located at the very end of the "page".

The allocation metadata includes "used bits" - 1 bit per slot representing
whether the slot is used. Allocations always take the next available slot
from the current bucket, setting the corresponding used bit, as well as
incrementing `allocated_count`.

Frees recover the allocation metadata based on the address, length, and
alignment, relying on the backing allocation's large alignment, combined
with the fact that allocations are never moved from small to large, or vice
versa.

When a bucket is full, a new one is allocated, containing a pointer to the
previous one. This doubly-linked list is iterated during leak detection.

Resizing and remapping work the same on small allocations: if the size
class would not change, then the operation succeeds, and the address is
unchanged. Otherwise, the request is rejected.

Large objects are allocated directly using the backing allocator. Metadata
is stored separately in a `std.HashMap` using the backing allocator.

Resizing and remapping are forwarded directly to the backing allocator,
except where such operations would change the category from large to small.

## Types

### `Config`


### Fields

- `stack_trace_frames: usize = default_stack_trace_frames`
  Number of stack frames to capture.
- `enable_memory_limit: bool = false`
  If true, the allocator will have two fields:
   * `total_requested_bytes` which tracks the total allocated bytes of memory requested.
   * `requested_memory_limit` which causes allocations to return `error.OutOfMemory`
     when the `total_requested_bytes` exceeds this limit.
  If false, these fields will be `void`.
- `safety: bool = std.debug.runtime_safety`
  Whether to enable safety checks.
- `thread_safe: bool = !builtin.single_threaded`
  Whether the allocator may be used simultaneously from multiple threads.
- `never_unmap: bool = false`
  This is a temporary debugging trick you can use to turn segfaults into more helpful
  logged error messages with stack trace details. The downside is that every allocation
  will be leaked, unless used with retain_metadata!
- `retain_metadata: bool = false`
  This is a temporary debugging aid that retains metadata about allocations indefinitely.
  This allows a greater range of double frees to be reported. All metadata is freed when
  deinit is called. When used with never_unmap, deliberately leaked memory is also freed
  during deinit. Currently should be used with never_unmap to avoid segfaults.
  TODO https://github.com/ziglang/zig/issues/4298 will allow use without never_unmap
- `verbose_log: bool = false`
  Enables emitting info messages with the size and address of every allocation.
- `backing_allocator_zeroes: bool = true`
  Tell whether the backing allocator returns already-zeroed memory.
- `resize_stack_traces: bool = false`
  When resizing an allocation, refresh the stack trace with the resize
  callsite. Comes with a performance penalty.
- `canary: usize = @truncate(0x9232a6ff85dff10f)`
  Magic value that distinguishes allocations owned by this allocator from
  other regions of memory.
- `page_size: usize = default_page_size`
  The size of allocations requested from the backing allocator for
  subdividing into slots for small allocations.
  
  Must be a power of two.

### `DebugAllocator`

```zig
pub fn DebugAllocator(comptime config: Config) type
```

Default initialization of this struct is deprecated; use `.init` instead.

### Fields

- `backing_allocator: Allocator = std.heap.page_allocator`
  
- `buckets: [small_bucket_count]?*BucketHeader = @splat(null)`
  Tracks the active bucket, which is the one that has free slots in it.
- `large_allocations: LargeAllocTable = .empty`
  
- `total_requested_bytes: @TypeOf(total_requested_bytes_init) = total_requested_bytes_init`
  
- `requested_memory_limit: @TypeOf(requested_memory_limit_init) = requested_memory_limit_init`
  
- `mutex: @TypeOf(mutex_init) = mutex_init`
  

### Functions

#### `allocator`

```zig
pub fn allocator(self: *Self) Allocator
```


#### `detectLeaks`

```zig
pub fn detectLeaks(self: *Self) usize
```

Emits log messages for leaks and then returns the number of detected leaks (0 if no leaks were detected).

#### `flushRetainedMetadata`

```zig
pub fn flushRetainedMetadata(self: *Self) void
```


#### `deinit`

```zig
pub fn deinit(self: *Self) std.heap.Check
```

Returns `std.heap.Check.leak` if there were leaks; `std.heap.Check.ok` otherwise.

#### `deinitWithoutLeakChecks`

```zig
pub fn deinitWithoutLeakChecks(self: *Self) void
```

Like `deinit`, but does not check for memory leaks. This is useful if leaks have already
been detected manually with `detectLeaks` to avoid reporting them for a second time.

### Constants & Variables

- **`init`**: 
- **`Error`**: 

