# `std.Io.Writer`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/Io/Writer.zig`  
> [← Back to Standard Library Index](README.md)

## Fields

- `vtable: *const VTable`
  
- `buffer: []u8`
  If this has length zero, the writer is unbuffered, and `flush` is a no-op.
- `end: usize = 0`
  In `buffer` before this are buffered bytes, after this is `undefined`.

## Types

### `VTable`


### Fields

- `drain: *const fn (w: *Writer, data: []const []const u8, splat: usize) Error!usize`
  Sends bytes to the logical sink. A write will only be sent here if it
  could not fit into `buffer`, or during a `flush` operation.
  
  `buffer[0..end]` is consumed first, followed by each slice of `data` in
  order. Elements of `data` may alias each other but may not alias
  `buffer`.
  
  This function modifies `Writer.end` and `Writer.buffer` in an
  implementation-defined manner.
  
  `data.len` must be nonzero.
  
  The last element of `data` is repeated as necessary so that it is
  written `splat` number of times, which may be zero.
  
  This function may not be called if the data to be written could have
  been stored in `buffer` instead, including when the amount of data to
  be written is zero and the buffer capacity is zero.
  
  Number of bytes consumed from `data` is returned, excluding bytes from
  `buffer`.
  
  Number of bytes returned may be zero, which does not indicate stream
  end. A subsequent call may return nonzero, or signal end of stream via
  `error.WriteFailed`.
- `sendFile: *const fn (w: *Writer, file_reader: *File.Reader, limit: Limit, ) FileError!usize = unimplementedSendFile`
  Copies contents from an open file to the logical sink. `buffer[0..end]`
  is consumed first, followed by `limit` bytes from `file_reader`.
  
  Number of bytes logically written is returned. This excludes bytes from
  `buffer` because they have already been logically written. Number of
  bytes consumed from `buffer` are tracked by modifying `end`.
  
  Number of bytes returned may be zero, which does not indicate stream
  end. A subsequent call may return nonzero, or signal end of stream via
  `error.WriteFailed`. Caller may check `file_reader` state
  (`File.Reader.atEnd`) to disambiguate between a zero-length read or
  write, and whether the file reached the end.
  
  `error.Unimplemented` indicates the callee cannot offer a more
  efficient implementation than the caller performing its own reads.
- `flush: *const fn (w: *Writer) Error!void = defaultFlush`
  Consumes all remaining buffer.
  
  The default flush implementation calls drain repeatedly until `end` is
  zero, however it is legal for implementations to manage `end`
  differently. For instance, `Allocating` flush is a no-op.
  
  There may be subsequent calls to `drain` and `sendFile` after a `flush`
  operation.
- `rebase: *const fn (w: *Writer, preserve: usize, capacity: usize) Error!void = defaultRebase`
  Ensures `capacity` more bytes can be buffered without rebasing.
  
  The most recent `preserve` bytes must remain buffered.
  
  Only called when `capacity` bytes cannot fit into the unused capacity
  of `buffer`.

### `ByteSizeUnits`


### Fields

- `decimal`
  This formatter represents the number as multiple of 1000 and uses the SI
  measurement units (kB, MB, GB, ...).
- `binary`
  This formatter represents the number as multiple of 1024 and uses the IEC
  measurement units (KiB, MiB, GiB, ...).

### `Discarding`


### Fields

- `count: u64`
  
- `writer: Writer`
  

### Functions

#### `init`

```zig
pub fn init(buffer: []u8) Discarding
```


#### `fullCount`

```zig
pub fn fullCount(d: *const Discarding) u64
```

Includes buffered data (no need to flush).

#### `drain`

```zig
pub fn drain(w: *Writer, data: []const []const u8, splat: usize) Error!usize
```


#### `sendFile`

```zig
pub fn sendFile(w: *Writer, file_reader: *File.Reader, limit: Limit) FileError!usize
```


### `Hashed`

```zig
pub fn Hashed(comptime Hasher: type) type
```

Provides a `Writer` implementation based on calling `Hasher.update`, sending
all data also to an underlying `Writer`.

When using this, the underlying writer is best unbuffered because all
writes are passed on directly to it.

This implementation makes suboptimal buffering decisions due to being
generic. A better solution will involve creating a writer for each hash
function, where the splat buffer can be tailored to the hash implementation
details.

Contrast with `Hashing` which terminates the stream pipeline.

### Fields

- `out: *Writer`
  
- `hasher: Hasher`
  
- `writer: Writer`
  

### Functions

#### `init`

```zig
pub fn init(out: *Writer, buffer: []u8) @This()
```


#### `initHasher`

```zig
pub fn initHasher(out: *Writer, hasher: Hasher, buffer: []u8) @This()
```


### `Hashing`

```zig
pub fn Hashing(comptime Hasher: type) type
```

Provides a `Writer` implementation based on calling `Hasher.update`,
discarding all data.

This implementation makes suboptimal buffering decisions due to being
generic. A better solution will involve creating a writer for each hash
function, where the splat buffer can be tailored to the hash implementation
details.

The total number of bytes written is stored in `hasher`.

Contrast with `Hashed` which also passes the data to an underlying stream.

### Fields

- `hasher: Hasher`
  
- `writer: Writer`
  

### Functions

#### `init`

```zig
pub fn init(buffer: []u8) @This()
```


#### `initHasher`

```zig
pub fn initHasher(hasher: Hasher, buffer: []u8) @This()
```


### `Allocating`

Maintains `Writer` state such that it writes to the unused capacity of an
array list, filling it up completely before making a call through the
vtable, causing a resize. Consequently, the same, optimized, non-generic
machine code that uses `Writer`, such as formatted printing, takes
the hot paths when using this API.

When using this API, it is not necessary to call `flush`.

### Fields

- `allocator: Allocator`
  
- `writer: Writer`
  
- `alignment: std.mem.Alignment`
  

### Functions

#### `init`

```zig
pub fn init(allocator: Allocator) Allocating
```


#### `initAligned`

```zig
pub fn initAligned(allocator: Allocator, alignment: std.mem.Alignment) Allocating
```


#### `initCapacity`

```zig
pub fn initCapacity(allocator: Allocator, capacity: usize) error{OutOfMemory}!Allocating
```


#### `initOwnedSlice`

```zig
pub fn initOwnedSlice(allocator: Allocator, slice: []u8) Allocating
```


#### `initOwnedSliceAligned`

```zig
pub fn initOwnedSliceAligned(allocator: Allocator, comptime alignment: std.mem.Alignment, slice: []align(alignment.toByteUnits()) u8, ) Allocating
```


#### `fromArrayList`

```zig
pub fn fromArrayList(allocator: Allocator, array_list: *ArrayList(u8)) Allocating
```

Replaces `array_list` with empty, taking ownership of the memory.

#### `fromArrayListAligned`

```zig
pub fn fromArrayListAligned(allocator: Allocator, comptime alignment: std.mem.Alignment, array_list: *std.array_list.Aligned(u8, alignment), ) Allocating
```

Replaces `array_list` with empty, taking ownership of the memory.

#### `deinit`

```zig
pub fn deinit(a: *Allocating) void
```


#### `toArrayList`

```zig
pub fn toArrayList(a: *Allocating) ArrayList(u8)
```

Returns an array list that takes ownership of the allocated memory.
Resets the `Allocating` to an empty state.

#### `toArrayListAligned`

```zig
pub fn toArrayListAligned(a: *Allocating, comptime alignment: std.mem.Alignment, ) std.array_list.Aligned(u8, alignment)
```

Returns an array list that takes ownership of the allocated memory.
Resets the `Allocating` to an empty state.

#### `ensureUnusedCapacity`

```zig
pub fn ensureUnusedCapacity(a: *Allocating, additional_count: usize) Allocator.Error!void
```


#### `ensureTotalCapacity`

```zig
pub fn ensureTotalCapacity(a: *Allocating, new_capacity: usize) Allocator.Error!void
```


#### `ensureTotalCapacityPrecise`

```zig
pub fn ensureTotalCapacityPrecise(a: *Allocating, new_capacity: usize) Allocator.Error!void
```


#### `toOwnedSlice`

```zig
pub fn toOwnedSlice(a: *Allocating) Allocator.Error![]u8
```


#### `toOwnedSliceSentinel`

```zig
pub fn toOwnedSliceSentinel(a: *Allocating, comptime sentinel: u8) Allocator.Error![:sentinel]u8
```


#### `written`

```zig
pub fn written(a: *Allocating) []u8
```


#### `shrinkRetainingCapacity`

```zig
pub fn shrinkRetainingCapacity(a: *Allocating, new_len: usize) void
```


#### `clearRetainingCapacity`

```zig
pub fn clearRetainingCapacity(a: *Allocating) void
```


## Functions

### `fixed`

```zig
pub fn fixed(buffer: []u8) Writer
```

Writes to `buffer` and returns `error.WriteFailed` when it is full.

### `hashed`

```zig
pub fn hashed(w: *Writer, hasher: anytype, buffer: []u8) Hashed(@TypeOf(hasher))
```


### `buffered`

```zig
pub fn buffered(w: *const Writer) []u8
```

Returns the contents not yet drained.

### `countSplat`

```zig
pub fn countSplat(data: []const []const u8, splat: usize) usize
```


### `countSendFileLowerBound`

```zig
pub fn countSendFileLowerBound(n: usize, file_reader: *File.Reader, limit: Limit) ?usize
```


### `writeVec`

```zig
pub fn writeVec(w: *Writer, data: []const []const u8) Error!usize
```

If the total number of bytes of `data` fits inside `unusedCapacitySlice`,
this function is guaranteed to not fail, not call into `VTable`, and return
the total bytes inside `data`.

### `writeSplat`

```zig
pub fn writeSplat(w: *Writer, data: []const []const u8, splat: usize) Error!usize
```

If the number of bytes to write based on `data` and `splat` fits inside
`unusedCapacitySlice`, this function is guaranteed to not fail, not call
into `VTable`, and return the full number of bytes.

### `writeSplatHeader`

```zig
pub fn writeSplatHeader(w: *Writer, header: []const u8, data: []const []const u8, splat: usize, ) Error!usize
```

Returns how many bytes were consumed from `header` and `data`.

### `writeSplatHeaderLimit`

```zig
pub fn writeSplatHeaderLimit(w: *Writer, header: []const u8, data: []const []const u8, splat: usize, limit: Limit, ) Error!usize
```

Equivalent to `writeSplatHeader` but writes at most `limit` bytes.

### `flush`

```zig
pub fn flush(w: *Writer) Error!void
```

Drains all remaining buffered data.

### `defaultFlush`

```zig
pub fn defaultFlush(w: *Writer) Error!void
```

Repeatedly calls `VTable.drain` until `end` is zero.

### `noopFlush`

```zig
pub fn noopFlush(w: *Writer) Error!void
```

Does nothing.

### `rebase`

```zig
pub fn rebase(w: *Writer, preserve: usize, unused_capacity_len: usize) Error!void
```


### `defaultRebase`

```zig
pub fn defaultRebase(w: *Writer, preserve: usize, minimum_len: usize) Error!void
```


### `unusedCapacitySlice`

```zig
pub fn unusedCapacitySlice(w: *const Writer) []u8
```


### `unusedCapacityLen`

```zig
pub fn unusedCapacityLen(w: *const Writer) usize
```


### `writableArray`

```zig
pub fn writableArray(w: *Writer, comptime len: usize) Error!*[len]u8
```

Asserts the provided buffer has total capacity enough for `len`.

Advances the buffer end position by `len`.

### `writableSlice`

```zig
pub fn writableSlice(w: *Writer, len: usize) Error![]u8
```

Asserts the provided buffer has total capacity enough for `len`.

Advances the buffer end position by `len`.

### `writableSliceGreedy`

```zig
pub fn writableSliceGreedy(w: *Writer, minimum_len: usize) Error![]u8
```

Asserts the provided buffer has total capacity enough for `minimum_len`.

Does not `advance` the buffer end position.

If `minimum_len` is zero, this is equivalent to `unusedCapacitySlice`.

### `writableSliceGreedyPreserve`

```zig
pub fn writableSliceGreedyPreserve(w: *Writer, preserve: usize, minimum_len: usize) Error![]u8
```

Asserts the provided buffer has total capacity enough for `minimum_len`
and `preserve` combined.

Does not `advance` the buffer end position.

When draining the buffer, ensures that at least `preserve` bytes
remain buffered.

If `preserve` is zero, this is equivalent to `writableSliceGreedy`.

### `writableSlicePreserve`

```zig
pub fn writableSlicePreserve(w: *Writer, preserve: usize, len: usize) Error![]u8
```

Asserts the provided buffer has total capacity enough for `len`
and `preserve` combined.

Advances the buffer end position by `len`.

When draining the buffer, ensures that at least `preserve` bytes
remain buffered.

If `preserve` is zero, this is equivalent to `writableSlice`.

### `ensureUnusedCapacity`

```zig
pub fn ensureUnusedCapacity(w: *Writer, n: usize) Error!void
```


### `undo`

```zig
pub fn undo(w: *Writer, n: usize) void
```


### `advance`

```zig
pub fn advance(w: *Writer, n: usize) void
```

After calling `writableSliceGreedy`, this function tracks how many bytes
were written to it.

This is not needed when using `writableSlice` or `writableArray`.

### `writeVecAll`

```zig
pub fn writeVecAll(w: *Writer, data: [][]const u8) Error!void
```

The `data` parameter is mutable because this function needs to mutate the
fields in order to handle partial writes from `VTable.writeSplat`.

### `writeSplatAll`

```zig
pub fn writeSplatAll(w: *Writer, data: [][]const u8, splat: usize) Error!void
```

The `data` parameter is mutable because this function needs to mutate the
fields in order to handle partial writes from `VTable.writeSplat`.
`data` will be restored to its original state before returning.

### `write`

```zig
pub fn write(w: *Writer, bytes: []const u8) Error!usize
```

Transfers `bytes` to the stream, calling `drain` at most once.

Returns the number of bytes transferred, which may be less than
`bytes.len`, including zero.

A return value less than `bytes.len` does not indicate failure; a
subsequent call may return nonzero, or fail with `error.WriteFailed`.

See also:
* `writeAll`
* `writeVec`

### `writeAll`

```zig
pub fn writeAll(w: *Writer, bytes: []const u8) Error!void
```

Transfers `bytes` to the stream, calling `drain` as many times as necessary
such that all `bytes` are transferred.

See also:
* `print`
* `writeVecAll`
* `write`

### `print`

```zig
pub fn print(w: *Writer, comptime fmt: []const u8, args: anytype) Error!void
```

Renders `fmt` string with `args`, calling `w` with slices of bytes.

The format string must be comptime-known and may contain placeholders
following this format:
```
{[argument][specifier]:[fill][alignment][width].[precision]}
```

Above, each word including its surrounding [ and ] is a parameter to be replaced with:

- **argument** is either the numeric index or the field name of the argument that should be inserted.
  - When using a field name, the field name (an identifier) must be enclosed in square
    brackets, e.g. `{[score]...}` as opposed to the numeric index form which can be written e.g. `{2...}`.
- **specifier** is a type-dependent formatting option that determines how a type should formatted (see below).
- **fill** is a single byte which is used to pad formatted numbers.
- **alignment** is one of the three bytes '<', '^', or '>' to make numbers
  left, center, or right-aligned, respectively.
  - Not all specifiers support alignment.
  - Alignment is not Unicode-aware; appropriate only when used with raw
    bytes or ASCII.
- **width** is the total size of the field in bytes, only applicable to
  number formatting.
- **precision** specifies how many decimals a formatted number should have.

Most of the parameters are optional and may be omitted. The separators (':'
and '.') may be omitted when all parameters afterwards are omitted.

The **fill** parameter is an exception. If a non-zero **fill** character is
required at the same time as **width** is specified, **alignment** is
required, otherwise the digit following ':' is interpreted as **width**.

**specifier** supports:
- "x" and "X": numeric value in hexadecimal notation, or string in hexadecimal bytes
- "s":
  - for pointer-to-many and C pointers of u8, print as a C-string using zero-termination
  - for slices of u8, print the entire slice as a string without zero-termination
- "t":
  - for enums and tagged unions: prints the tag name
  - for error sets: prints the error name
- "b64": string as standard base64
- "e": floating point value in scientific notation
- "d": numeric value in decimal notation
- "b": integer value in binary notation
- "o": integer value in octal notation
- "c": integer as an ASCII character. Integer type must have 8 bits at max.
- "u": integer as an UTF-8 sequence. Integer type must have 21 bits at max.
- "B": bytes in SI units (decimal)
- "Bi": bytes in IEC units (binary)
- "?": optional value as either the unwrapped value, or `null`; may be
  followed by a format specifier for the underlying value.
- "!": error union value as either the unwrapped value, or the formatted
  error value; may be followed by a format specifier for the underlying
  value.
- "*": the address of the value instead of the value itself.
- "any": a value of any type using its default format.
- "f": delegates to the `format` method of the type, passing `*Writer` and
  expecting `Error!void` returned.
- "q": prints as a double-quote escaped string. Inside the double-quoted
  string, everything is passed through unmodified, except for the following
  transformations:
  - escaped: '\n', '\r', '\t', '\\', '"'
  - hex-encoded: ASCII control characters, invalid UTF-8 sequences,
    non-ASCII line endings (U+0085, U+2028, U+2029), byte order marks (U+FEFF).
- "qf": delegates to the `format` method of the type, while double-quote
  escaping.

Literal curly braces can be escaped in the format string via doubling, e.g.
"{{" or "}}".

### `writeByte`

```zig
pub fn writeByte(w: *Writer, byte: u8) Error!void
```

Calls `drain` as many times as necessary such that `byte` is transferred.

### `writeBytePreserve`

```zig
pub fn writeBytePreserve(w: *Writer, preserve: usize, byte: u8) Error!void
```

On success, at least `preserve` bytes will remain buffered if there are
enough buffered bytes to do so.
The amount buffered by the writer after the call will only be less than
`preserve` if `w.end + 1` is less than `preserve` before the call.
The intentionally preserved bytes will include up to `preserve -| 1` bytes from
the previously buffered bytes, plus the newly written byte.

Asserts buffer capacity is at least `preserve`.

### `splatByteAll`

```zig
pub fn splatByteAll(w: *Writer, byte: u8, n: usize) Error!void
```

Writes the same byte many times, performing the underlying write call as
many times as necessary.

### `splatBytePreserve`

```zig
pub fn splatBytePreserve(w: *Writer, preserve: usize, byte: u8, n: usize) Error!void
```

Writes the same byte many times, performing the underlying write call as
many times as necessary.

On success, at least `preserve` bytes will remain buffered if there are
enough buffered bytes to do so.
The amount buffered by the writer after the call will only be less than
`preserve` if `w.end + n` is less than `preserve` before the call.
The intentionally preserved bytes will include up to `preserve -| n` bytes from
the previously buffered bytes, plus `@min(n, preserve_len)` of the newly
written bytes.

Asserts buffer capacity is at least `preserve`.
`n` can be greater than the buffer capacity.

### `splatByte`

```zig
pub fn splatByte(w: *Writer, byte: u8, n: usize) Error!usize
```

Writes the same byte many times, allowing short writes.

Does maximum of one underlying `VTable.drain`.

### `splatBytesAll`

```zig
pub fn splatBytesAll(w: *Writer, bytes: []const u8, splat: usize) Error!void
```

Writes the same slice many times, performing the underlying write call as
many times as necessary.

### `splatBytes`

```zig
pub fn splatBytes(w: *Writer, bytes: []const u8, n: usize) Error!usize
```

Writes the same slice many times, allowing short writes.

Does maximum of one underlying `VTable.drain`.

### `writeInt`

```zig
pub inline fn writeInt(w: *Writer, comptime T: type, value: T, endian: std.lang.Endian) Error!void
```

Asserts the `buffer` was initialized with a capacity of at least `@sizeOf(T)` bytes.

### `writeStruct`

```zig
pub inline fn writeStruct(w: *Writer, value: anytype, endian: std.lang.Endian) Error!void
```

The function is inline to avoid the dead code in case `endian` is
comptime-known and matches host endianness.

### `writeSliceEndian`

```zig
pub inline fn writeSliceEndian(w: *Writer, Elem: type, slice: []const Elem, endian: std.lang.Endian, ) Error!void
```


### `writeSliceSwap`

```zig
pub fn writeSliceSwap(w: *Writer, Elem: type, slice: []const Elem) Error!void
```


### `sendFile`

```zig
pub fn sendFile(w: *Writer, file_reader: *File.Reader, limit: Limit) FileError!usize
```

Unlike `writeSplat` and `writeVec`, this function will call into `VTable`
even if there is enough buffer capacity for the file contents.

The caller is responsible for flushing. Although the buffer may be bypassed
as an optimization, this is not a guarantee.

Although it would be possible to eliminate `error.Unimplemented` from the
error set by reading directly into the buffer in such case, this is not
done because it is more efficient to do it higher up the call stack so that
the error does not occur with each write.

See `sendFileReading` for an alternative that does not have
`error.Unimplemented` in the error set.

### `sendFileHeader`

```zig
pub fn sendFileHeader(w: *Writer, header: []const u8, file_reader: *File.Reader, limit: Limit, ) FileError!usize
```

Returns how many bytes from `header` and `file_reader` were consumed.

`limit` only applies to `file_reader`.

### `sendFileReading`

```zig
pub fn sendFileReading(w: *Writer, file_reader: *File.Reader, limit: Limit) FileReadingError!usize
```

Asserts nonzero buffer capacity and nonzero `limit`.

### `sendFileAll`

```zig
pub fn sendFileAll(w: *Writer, file_reader: *File.Reader, limit: Limit) FileAllError!usize
```

Number of bytes logically written is returned. This excludes bytes from
`buffer` because they have already been logically written.

The caller is responsible for flushing. Although the buffer may be bypassed
as an optimization, this is not a guarantee.

Asserts nonzero buffer capacity.

### `sendFileReadingAll`

```zig
pub fn sendFileReadingAll(w: *Writer, file_reader: *File.Reader, limit: Limit) FileAllError!usize
```

Equivalent to `sendFileAll` but uses direct `pread` and `read` calls on
`file` rather than `sendFile`. This is generally used as a fallback when
the underlying implementation returns `error.Unimplemented`, which is why
that error code does not appear in this function's error set.

Asserts nonzero buffer capacity.

### `alignBuffer`

```zig
pub fn alignBuffer(w: *Writer, buffer: []const u8, width: usize, alignment: std.fmt.Alignment, fill: u8, ) Error!void
```


### `alignBufferOptions`

```zig
pub fn alignBufferOptions(w: *Writer, buffer: []const u8, options: std.fmt.Options) Error!void
```


### `printAddress`

```zig
pub fn printAddress(w: *Writer, value: anytype) Error!void
```


### `printValue`

```zig
pub fn printValue(w: *Writer, comptime fmt: []const u8, options: std.fmt.Options, value: anytype, max_depth: usize, ) Error!void
```

Asserts `buffer` capacity of at least 2 if `value` is a union.

### `printStringEscaped`

```zig
pub fn printStringEscaped(w: *Writer, bytes: []const u8) Error!void
```

Prints a double quote, then escapes a string according to Zig string
literal rules, then a double quote.

### `printVector`

```zig
pub fn printVector(w: *Writer, comptime fmt: []const u8, options: std.fmt.Options, value: anytype, max_depth: usize, ) Error!void
```


### `printArray`

```zig
pub fn printArray(w: *Writer, comptime fmt: []const u8, options: std.fmt.Options, ptr_to_array: anytype, max_depth: usize, ) Error!void
```


### `printInt`

```zig
pub inline fn printInt(w: *Writer, value: anytype, base: u8, case: std.fmt.Case, options: std.fmt.Options, ) Error!void
```


### `printIntAny`

```zig
pub fn printIntAny(w: *Writer, value: anytype, base: u8, case: std.fmt.Case, options: std.fmt.Options, ) Error!void
```

In general, prefer `printInt` to avoid generic explosion. However this
function may be used when optimal codegen for a particular integer type is
desired.

### `printAsciiChar`

```zig
pub fn printAsciiChar(w: *Writer, c: u8, options: std.fmt.Options) Error!void
```


### `printAscii`

```zig
pub fn printAscii(w: *Writer, bytes: []const u8, options: std.fmt.Options) Error!void
```


### `printUnicodeCodepoint`

```zig
pub fn printUnicodeCodepoint(w: *Writer, c: u21) Error!void
```


### `printFloat`

```zig
pub fn printFloat(w: *Writer, value: anytype, options: std.fmt.Number) Error!void
```

Uses a larger stack buffer; asserts mode is decimal or scientific.

### `printFloatHexOptions`

```zig
pub fn printFloatHexOptions(w: *Writer, value: anytype, options: std.fmt.Number) Error!void
```

Uses a smaller stack buffer; asserts mode is not decimal or scientific.

### `printFloatHex`

```zig
pub fn printFloatHex(w: *Writer, value: anytype, case: std.fmt.Case, opt_precision: ?usize) Error!void
```


### `printByteSize`

```zig
pub fn printByteSize(w: *Writer, value: u64, comptime units: ByteSizeUnits, options: std.fmt.Options, ) Error!void
```

Format option `precision` is ignored when `value` is less than 1kB

### `invalidFmtError`

```zig
pub fn invalidFmtError(comptime fmt: []const u8, value: anytype) noreturn
```


### `printHex`

```zig
pub fn printHex(w: *Writer, bytes: []const u8, case: std.fmt.Case) Error!void
```


### `printBase64`

```zig
pub fn printBase64(w: *Writer, bytes: []const u8) Error!void
```


### `writeUleb128`

```zig
pub fn writeUleb128(w: *Writer, value: anytype) Error!void
```

Write a single unsigned integer as LEB128 to the given writer.

### `writeSleb128`

```zig
pub fn writeSleb128(w: *Writer, value: anytype) Error!void
```

Write a single signed integer as LEB128 to the given writer.

### `writeLeb128`

```zig
pub fn writeLeb128(w: *Writer, value: anytype) Error!void
```

Write a single integer as LEB128 to the given writer.

### `format`

```zig
pub fn format(self: SelfType, w: *Writer) Error!void
```


### `failingDrain`

```zig
pub fn failingDrain(w: *Writer, data: []const []const u8, splat: usize) Error!usize
```


### `failingSendFile`

```zig
pub fn failingSendFile(w: *Writer, file_reader: *File.Reader, limit: Limit) FileError!usize
```


### `failingRebase`

```zig
pub fn failingRebase(w: *Writer, preserve: usize, capacity: usize) Error!void
```


### `consume`

```zig
pub fn consume(w: *Writer, n: usize) usize
```

Removes the first `n` bytes from `buffer` by shifting buffer contents,
returning how many bytes are left after consuming the entire buffer, or
zero if the entire buffer was not consumed.

Useful for `VTable.drain` function implementations to implement partial
drains.

### `consumeAll`

```zig
pub fn consumeAll(w: *Writer) usize
```

Shortcut for setting `end` to zero and returning zero. Equivalent to
calling `consume` with `end`.

### `unimplementedSendFile`

```zig
pub fn unimplementedSendFile(w: *Writer, file_reader: *File.Reader, limit: Limit) FileError!usize
```

For use when the `Writer` implementation can cannot offer a more efficient
implementation than a basic read/write loop on the file.

### `fixedDrain`

```zig
pub fn fixedDrain(w: *Writer, data: []const []const u8, splat: usize) Error!usize
```

When this function is called it usually means the buffer got full, so it's
time to return an error. However, we still need to make sure all of the
available buffer has been filled. Also, it may be called from `flush` in
which case it should return successfully.

### `unreachableDrain`

```zig
pub fn unreachableDrain(w: *Writer, data: []const []const u8, splat: usize) Error!usize
```


### `unreachableRebase`

```zig
pub fn unreachableRebase(w: *Writer, preserve: usize, capacity: usize) Error!void
```


### `fromArrayList`

```zig
pub fn fromArrayList(array_list: *ArrayList(u8)) Writer
```


### `toArrayList`

```zig
pub fn toArrayList(w: *Writer) ArrayList(u8)
```


## Error Sets

- **`Error`**
  
- **`FileAllError`**
  
- **`FileReadingError`**
  
- **`FileError`**
  

## Constants & Variables

- **`failing`**: 

