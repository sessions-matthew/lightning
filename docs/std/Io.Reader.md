# `std.Io.Reader`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/Io/Reader.zig`  
> [← Back to Standard Library Index](README.md)

## Fields

- `vtable: *const VTable`
  
- `buffer: []u8`
  
- `seek: usize`
  Number of bytes which have been consumed from `buffer`.
- `end: usize`
  In `buffer` before this are buffered bytes, after this is `undefined`.

## Types

### `VTable`


### Fields

- `stream: *const fn (r: *Reader, w: *Writer, limit: Limit) StreamError!usize`
  Writes bytes from the internally tracked logical position to `w`.
  
  Returns the number of bytes written, which will be at minimum `0` and
  at most `limit`. The number returned, including zero, does not indicate
  end of stream.
  
  The reader's internal logical seek position moves forward in accordance
  with the number of bytes returned from this function.
  
  Implementations are encouraged to utilize mandatory minimum buffer
  sizes combined with short reads (returning a value less than `limit`)
  in order to minimize complexity.
  
  Although this function is usually called when `buffer` is empty, it is
  also called when it needs to be filled more due to the API user
  requesting contiguous memory. In either case, the existing buffer data
  should be ignored; new data written to `w`.
  
  In addition to, or instead of writing to `w`, the implementation may
  choose to store data in `buffer`, modifying `seek` and `end`
  accordingly. Implementations are encouraged to take advantage of
  this if it simplifies the logic.
- `discard: *const fn (r: *Reader, limit: Limit) Error!usize = defaultDiscard`
  Consumes bytes from the internally tracked stream position without
  providing access to them.
  
  Returns the number of bytes discarded, which will be at minimum `0` and
  at most `limit`. The number of bytes returned, including zero, does not
  indicate end of stream.
  
  The reader's internal logical seek position moves forward in accordance
  with the number of bytes returned from this function.
  
  Implementations are encouraged to utilize mandatory minimum buffer
  sizes combined with short reads (returning a value less than `limit`)
  in order to minimize complexity.
  
  The default implementation is is based on calling `stream`, borrowing
  `buffer` to construct a temporary `Writer` and ignoring the written
  data.
  
  This function is only called when `buffer` is empty.
- `readVec: *const fn (r: *Reader, data: [][]u8) Error!usize = defaultReadVec`
  Returns number of bytes written to `data`.
  
  `data` must have nonzero length. `data[0]` may have zero length, in
  which case the implementation must write to `Reader.buffer`.
  
  `data` may not contain an alias to `Reader.buffer`.
  
  `data` is mutable because the implementation may temporarily modify the
  fields in order to handle partial reads. Implementations must restore
  the original value before returning.
  
  Implementations may ignore `data`, writing directly to `Reader.buffer`,
  modifying `seek` and `end` accordingly, and returning 0 from this
  function. Implementations are encouraged to take advantage of this if
  it simplifies the logic.
  
  The default implementation calls `stream` with either `data[0]` or
  `Reader.buffer`, whichever is bigger.
- `rebase: *const fn (r: *Reader, capacity: usize) RebaseError!void = defaultRebase`
  Ensures `capacity` data can be buffered without rebasing.
  
  Asserts `capacity` is within buffer capacity, or that the stream ends
  within `capacity` bytes.
  
  Only called when `capacity` cannot be satisfied by unused capacity of
  `buffer`.
  
  The default implementation moves buffered data to the start of
  `buffer`, setting `seek` to zero, and cannot fail.

### `Hashed`

```zig
pub fn Hashed(comptime Hasher: type) type
```

Provides a `Reader` implementation by passing data from an underlying
reader through `Hasher.update`.

The underlying reader is best unbuffered.

This implementation makes suboptimal buffering decisions due to being
generic. A better solution will involve creating a reader for each hash
function, where the discard buffer can be tailored to the hash
implementation details.

### Fields

- `in: *Reader`
  
- `hasher: Hasher`
  
- `reader: Reader`
  

### Functions

#### `init`

```zig
pub fn init(in: *Reader, hasher: Hasher, buffer: []u8) @This()
```


## Functions

### `limited`

```zig
pub fn limited(r: *Reader, limit: Limit, buffer: []u8) Limited
```


### `fixed`

```zig
pub fn fixed(buffer: []const u8) Reader
```

Constructs a `Reader` such that it will read from `buffer` and then end.

### `stream`

```zig
pub fn stream(r: *Reader, w: *Writer, limit: Limit) StreamError!usize
```


### `discard`

```zig
pub fn discard(r: *Reader, limit: Limit) Error!usize
```


### `defaultDiscard`

```zig
pub fn defaultDiscard(r: *Reader, limit: Limit) Error!usize
```


### `streamExact`

```zig
pub fn streamExact(r: *Reader, w: *Writer, n: usize) StreamError!void
```

"Pump" exactly `n` bytes from the reader to the writer.

### `streamExact64`

```zig
pub fn streamExact64(r: *Reader, w: *Writer, n: u64) StreamError!void
```

"Pump" exactly `n` bytes from the reader to the writer.

### `streamExactPreserve`

```zig
pub fn streamExactPreserve(r: *Reader, w: *Writer, preserve_len: usize, n: usize) StreamError!void
```

"Pump" exactly `n` bytes from the reader to the writer.

On success, at least `preserve_len` bytes will remain buffered if there are
enough buffered bytes to do so.
The amount buffered by the writer after the call will only be less than
`preserve_len` if `w.end + n` is less than `preserve_len` before the call.
The intentionally preserved bytes will include up to `preserve_len -| n` bytes from
the previously buffered bytes, plus `@min(n, preserve_len)` of the newly
"pumped" bytes.

Asserts `Writer.buffer` capacity is at least `preserve_len`.
`n` can be greater than the `Writer.buffer` capacity.

### `streamRemaining`

```zig
pub fn streamRemaining(r: *Reader, w: *Writer) StreamRemainingError!usize
```

"Pump" data from the reader to the writer, handling `error.EndOfStream` as
a success case.

Returns total number of bytes written to `w`.

### `discardRemaining`

```zig
pub fn discardRemaining(r: *Reader) ShortError!usize
```

Consumes the stream until the end, ignoring all the data, returning the
number of bytes discarded.

### `allocRemaining`

```zig
pub fn allocRemaining(r: *Reader, gpa: Allocator, limit: Limit) LimitedAllocError![]u8
```

Transfers all bytes from the current position to the end of the stream, up
to `limit`, returning them as a caller-owned allocated slice.

If `limit` is exceeded, `error.StreamTooLong` is returned instead.
In such case, the next byte that would be read will be one byte past the
first one to exceed `limit`, and all preceeding bytes have been discarded.

See also:
* `appendRemaining`

### `allocRemainingAlignedSentinel`

```zig
pub fn allocRemainingAlignedSentinel(r: *Reader, gpa: Allocator, limit: Limit, comptime alignment: std.mem.Alignment, comptime sentinel: ?u8, ) LimitedAllocError!(if (sentinel) |s| [:s]align(alignment.toByteUnits()) u8 else []align(alignment.toByteUnits()) u8)
```


### `appendExact`

```zig
pub fn appendExact(r: *Reader, gpa: Allocator, list: *ArrayList(u8), n: usize, ) AppendExactError!void
```

Transfers exactly `n` bytes from the reader to the `ArrayList`.

See also:
* `appendRemaining`

### `appendRemaining`

```zig
pub fn appendRemaining(r: *Reader, gpa: Allocator, list: *ArrayList(u8), limit: Limit, ) LimitedAllocError!void
```

Transfers all bytes from the current position to the end of the stream, up
to `limit`, appending them to `list`.

If `limit` is reached or exceeded, `error.StreamTooLong` is returned
instead. In such case, the next byte that would be read will be the first
one to exceed `limit`, and all preceeding bytes have been appended to
`list`.

See also:
* `allocRemaining`

### `appendRemainingAligned`

```zig
pub fn appendRemainingAligned(r: *Reader, gpa: Allocator, comptime alignment: std.mem.Alignment, list: *std.array_list.Aligned(u8, alignment), limit: Limit, ) LimitedAllocError!void
```

Transfers all bytes from the current position to the end of the stream, up
to `limit`, appending them to `list`.

If `limit` is reached or exceeded, `error.StreamTooLong` is returned
instead. In such case, the next byte that would be read will be the first
one to exceed `limit`, and all preceeding bytes have been appended to
`list`.

See also:
* `appendRemaining`
* `allocRemainingAligned`

### `appendRemainingUnlimited`

```zig
pub fn appendRemainingUnlimited(r: *Reader, gpa: Allocator, list: *ArrayList(u8)) UnlimitedAllocError!void
```


### `readVec`

```zig
pub fn readVec(r: *Reader, data: [][]u8) Error!usize
```

Writes bytes from the internally tracked stream position to `data`.

Returns the number of bytes written, which will be at minimum `0` and
at most the sum of each data slice length. The number of bytes read,
including zero, does not indicate end of stream.

The reader's internal logical seek position moves forward in accordance
with the number of bytes returned from this function.

### `defaultReadVec`

```zig
pub fn defaultReadVec(r: *Reader, data: [][]u8) Error!usize
```

Writes to `Reader.buffer` or `data`, whichever has larger capacity.

### `buffered`

```zig
pub fn buffered(r: *Reader) []u8
```


### `bufferedLen`

```zig
pub fn bufferedLen(r: *const Reader) usize
```


### `hashed`

```zig
pub fn hashed(r: *Reader, hasher: anytype, buffer: []u8) Hashed(@TypeOf(hasher))
```


### `readVecAll`

```zig
pub fn readVecAll(r: *Reader, data: [][]u8) Error!void
```


### `peek`

```zig
pub fn peek(r: *Reader, n: usize) Error![]u8
```

Returns the next `n` bytes from the stream, filling the buffer as
necessary.

Invalidates previously returned values from `peek`.

Asserts that the `Reader` was initialized with a buffer capacity at
least as big as `n`.

If there are fewer than `n` bytes left in the stream, `error.EndOfStream`
is returned instead.

See also:
* `toss`

### `peekGreedy`

```zig
pub fn peekGreedy(r: *Reader, n: usize) Error![]u8
```

Returns all the next buffered bytes, after filling the buffer to ensure it
contains at least `n` bytes.

Invalidates previously returned values from `peek` and `peekGreedy`.

Asserts that the `Reader` was initialized with a buffer capacity at
least as big as `n`.

If there are fewer than `n` bytes left in the stream, `error.EndOfStream`
is returned instead.

See also:
* `peek`
* `toss`

### `toss`

```zig
pub fn toss(r: *Reader, n: usize) void
```

Skips the next `n` bytes from the stream, advancing the seek position. This
is typically and safely used after `peek`.

Asserts that the number of bytes buffered is at least as many as `n`.

The "tossed" memory remains alive until a "peek" operation occurs.

See also:
* `peek`.
* `discard`.

### `tossBuffered`

```zig
pub fn tossBuffered(r: *Reader) void
```

Equivalent to `toss(r.bufferedLen())`.

### `take`

```zig
pub fn take(r: *Reader, n: usize) Error![]u8
```

Equivalent to `peek` followed by `toss`.

The data returned is invalidated by the next call to `take`, `peek`,
`fill`, and functions with those prefixes.

### `takeArray`

```zig
pub fn takeArray(r: *Reader, comptime n: usize) Error!*[n]u8
```

Returns the next `n` bytes from the stream as an array, filling the buffer
as necessary and advancing the seek position `n` bytes.

Asserts that the `Reader` was initialized with a buffer capacity at
least as big as `n`.

If there are fewer than `n` bytes left in the stream, `error.EndOfStream`
is returned instead.

See also:
* `take`

### `peekArray`

```zig
pub fn peekArray(r: *Reader, comptime n: usize) Error!*[n]u8
```

Returns the next `n` bytes from the stream as an array, filling the buffer
as necessary, without advancing the seek position.

Asserts that the `Reader` was initialized with a buffer capacity at
least as big as `n`.

If there are fewer than `n` bytes left in the stream, `error.EndOfStream`
is returned instead.

See also:
* `peek`
* `takeArray`

### `discardAll`

```zig
pub fn discardAll(r: *Reader, n: usize) Error!void
```

Skips the next `n` bytes from the stream, advancing the seek position.

Unlike `toss` which is infallible, in this function `n` can be any amount.

Returns `error.EndOfStream` if fewer than `n` bytes could be discarded.

See also:
* `toss`
* `discardRemaining`
* `discardShort`
* `discard`

### `discardAll64`

```zig
pub fn discardAll64(r: *Reader, n: u64) Error!void
```


### `discardShort`

```zig
pub fn discardShort(r: *Reader, n: usize) ShortError!usize
```

Skips the next `n` bytes from the stream, advancing the seek position.

Unlike `toss` which is infallible, in this function `n` can be any amount.

Returns the number of bytes discarded, which is less than `n` if and only
if the stream reached the end.

See also:
* `discardAll`
* `discardRemaining`
* `discard`

### `readSliceAll`

```zig
pub fn readSliceAll(r: *Reader, buffer: []u8) Error!void
```

Fill `buffer` with the next `buffer.len` bytes from the stream, advancing
the seek position.

Invalidates previously returned values from `peek`.

If the provided buffer cannot be filled completely, `error.EndOfStream` is
returned instead.

See also:
* `peek`
* `readSliceShort`

### `readSliceShort`

```zig
pub fn readSliceShort(r: *Reader, buffer: []u8) ShortError!usize
```

Fill `buffer` with the next `buffer.len` bytes from the stream, advancing
the seek position.

Invalidates previously returned values from `peek`.

Returns the number of bytes read, which is less than `buffer.len` if and
only if the stream reached the end.

See also:
* `readSliceAll`

### `readSliceEndian`

```zig
pub inline fn readSliceEndian(r: *Reader, comptime Elem: type, buffer: []Elem, endian: std.builtin.Endian, ) Error!void
```

Fill `buffer` with the next `buffer.len` bytes from the stream, advancing
the seek position.

Invalidates previously returned values from `peek`.

If the provided buffer cannot be filled completely, `error.EndOfStream` is
returned instead.

The function is inline to avoid the dead code in case `endian` is
comptime-known and matches host endianness.

See also:
* `readSliceAll`
* `readSliceEndianAlloc`

### `readSliceEndianAlloc`

```zig
pub inline fn readSliceEndianAlloc(r: *Reader, allocator: Allocator, comptime Elem: type, len: usize, endian: std.builtin.Endian, ) ReadAllocError![]Elem
```

The function is inline to avoid the dead code in case `endian` is
comptime-known and matches host endianness.

### `readAllocAll`

```zig
pub fn readAllocAll(r: *Reader, allocator: Allocator, len: usize) ReadAllocError![]u8
```

Shortcut for calling `readSliceAll` with a buffer provided by `allocator`.

### `readAllocShort`

```zig
pub fn readAllocShort(r: *Reader, allocator: Allocator, len: usize) ReadAllocError![]u8
```

Shortcut for calling `readSliceShort` with a buffer provided by `allocator`,
shrinking allocation if stream reached the end.

### `takeSentinel`

```zig
pub fn takeSentinel(r: *Reader, comptime sentinel: u8) DelimiterError![:sentinel]u8
```

Returns a slice of the next bytes of buffered data from the stream until
`sentinel` is found, advancing the seek position past the sentinel.

Returned slice has a sentinel.

Invalidates previously returned values from `peek`.

See also:
* `peekSentinel`
* `takeDelimiterExclusive`
* `takeDelimiterInclusive`

### `peekSentinel`

```zig
pub fn peekSentinel(r: *Reader, comptime sentinel: u8) DelimiterError![:sentinel]u8
```

Returns a slice of the next bytes of buffered data from the stream until
`sentinel` is found, without advancing the seek position.

Returned slice has a sentinel; end of stream does not count as a delimiter.

Invalidates previously returned values from `peek`.

See also:
* `takeSentinel`
* `peekDelimiterExclusive`
* `peekDelimiterInclusive`

### `takeDelimiterInclusive`

```zig
pub fn takeDelimiterInclusive(r: *Reader, delimiter: u8) DelimiterError![]u8
```

Returns a slice of the next bytes of buffered data from the stream until
`delimiter` is found, advancing the seek position past the delimiter.

Returned slice includes the delimiter as the last byte.

Invalidates previously returned values from `peek`.

See also:
* `takeSentinel`
* `takeDelimiterExclusive`
* `peekDelimiterInclusive`

### `peekDelimiterInclusive`

```zig
pub fn peekDelimiterInclusive(r: *Reader, delimiter: u8) DelimiterError![]u8
```

Returns a slice of the next bytes of buffered data from the stream until
`delimiter` is found, without advancing the seek position.

Returned slice includes the delimiter as the last byte.

Invalidates previously returned values from `peek`.

See also:
* `peekSentinel`
* `peekDelimiterExclusive`
* `takeDelimiterInclusive`

### `takeDelimiterExclusive`

```zig
pub fn takeDelimiterExclusive(r: *Reader, delimiter: u8) DelimiterError![]u8
```

Returns a slice of the next bytes of buffered data from the stream until
`delimiter` is found, advancing the seek position up to (but not past)
the delimiter.

Returned slice excludes the delimiter. End-of-stream is treated equivalent
to a delimiter, unless it would result in a length 0 return value, in which
case `error.EndOfStream` is returned instead.

If the delimiter is not found within a number of bytes matching the
capacity of this `Reader`, `error.StreamTooLong` is returned. In
such case, the stream state is unmodified as if this function was never
called.

Invalidates previously returned values from `peek`.

See also:
* `takeDelimiter`
* `takeDelimiterInclusive`
* `peekDelimiterExclusive`

### `takeDelimiter`

```zig
pub fn takeDelimiter(r: *Reader, delimiter: u8) error{ ReadFailed, StreamTooLong }!?[]u8
```

Returns a slice of the next bytes of buffered data from the stream until
`delimiter` is found, advancing the seek position past the delimiter.

Returned slice excludes the delimiter. End-of-stream is treated equivalent
to a delimiter, unless it would result in a length 0 return value, in which
case `null` is returned instead.

If the delimiter is not found within a number of bytes matching the
capacity of this `Reader`, `error.StreamTooLong` is returned. In
such case, the stream state is unmodified as if this function was never
called.

Invalidates previously returned values from `peek`.

See also:
* `takeDelimiterInclusive`
* `takeDelimiterExclusive`

### `peekDelimiterExclusive`

```zig
pub fn peekDelimiterExclusive(r: *Reader, delimiter: u8) DelimiterError![]u8
```

Returns a slice of the next bytes of buffered data from the stream until
`delimiter` is found, without advancing the seek position.

Returned slice excludes the delimiter. End-of-stream is treated equivalent
to a delimiter, unless it would result in a length 0 return value, in which
case `error.EndOfStream` is returned instead.

If the delimiter is not found within a number of bytes matching the
capacity of this `Reader`, `error.StreamTooLong` is returned. In
such case, the stream state is unmodified as if this function was never
called.

Invalidates previously returned values from `peek`.

See also:
* `peekDelimiterInclusive`
* `takeDelimiterExclusive`

### `streamDelimiter`

```zig
pub fn streamDelimiter(r: *Reader, w: *Writer, delimiter: u8) StreamError!usize
```

Appends to `w` contents by reading from the stream until `delimiter` is
found. Does not write the delimiter itself.

Does not discard the delimiter from the `Reader`.

Returns number of bytes streamed, which may be zero, or error.EndOfStream
if the delimiter was not found.

Asserts buffer capacity of at least one. This function performs better with
larger buffers.

See also:
* `streamDelimiterEnding`
* `streamDelimiterLimit`

### `streamDelimiterEnding`

```zig
pub fn streamDelimiterEnding(r: *Reader, w: *Writer, delimiter: u8, ) StreamRemainingError!usize
```

Appends to `w` contents by reading from the stream until `delimiter` is found.
Does not write the delimiter itself.

Returns number of bytes streamed, which may be zero. If the stream reaches
the end, the reader buffer will be empty when this function returns.
Otherwise, it will have at least one byte buffered, starting with the
delimiter.

Asserts buffer capacity of at least one. This function performs better with
larger buffers.

See also:
* `streamDelimiter`
* `streamDelimiterLimit`

### `streamDelimiterLimit`

```zig
pub fn streamDelimiterLimit(r: *Reader, w: *Writer, delimiter: u8, limit: Limit, ) StreamDelimiterLimitError!usize
```

Appends to `w` contents by reading from the stream until `delimiter` is found.
Does not write the delimiter itself.

Does not discard the delimiter from the `Reader`.

Returns number of bytes streamed, which may be zero. End of stream can be
detected by checking if the next byte in the stream is the delimiter.

Asserts buffer capacity of at least one. This function performs better with
larger buffers.

### `discardDelimiterInclusive`

```zig
pub fn discardDelimiterInclusive(r: *Reader, delimiter: u8) Error!usize
```

Reads from the stream until specified byte is found, discarding all data,
including the delimiter.

Returns number of bytes discarded, or `error.EndOfStream` if the delimiter
is not found.

See also:
* `discardDelimiterExclusive`
* `discardDelimiterLimit`

### `discardDelimiterExclusive`

```zig
pub fn discardDelimiterExclusive(r: *Reader, delimiter: u8) ShortError!usize
```

Reads from the stream until specified byte is found, discarding all data,
excluding the delimiter.

Returns the number of bytes discarded.

Succeeds if stream ends before delimiter found. End of stream can be
detected by checking if the delimiter is buffered.

See also:
* `discardDelimiterInclusive`
* `discardDelimiterLimit`

### `discardDelimiterLimit`

```zig
pub fn discardDelimiterLimit(r: *Reader, delimiter: u8, limit: Limit) DiscardDelimiterLimitError!usize
```

Reads from the stream until specified byte is found, discarding all data,
excluding the delimiter.

Returns the number of bytes discarded.

Succeeds if stream ends before delimiter found. End of stream can be
detected by checking if the delimiter is buffered.

### `fill`

```zig
pub fn fill(r: *Reader, n: usize) Error!void
```

Fills the buffer such that it contains at least `n` bytes, without
advancing the seek position.

Returns `error.EndOfStream` if and only if there are fewer than `n` bytes
remaining.

If the end of stream is not encountered, asserts buffer capacity is at
least `n`.

### `fillMore`

```zig
pub fn fillMore(r: *Reader) Error!void
```

Without advancing the seek position, does exactly one underlying read, filling the buffer as
much as possible. This may result in zero bytes added to the buffer, which is not an end of
stream condition. End of stream is communicated via returning `error.EndOfStream`.

Asserts buffer capacity is at least 1.

### `peekByte`

```zig
pub fn peekByte(r: *Reader) Error!u8
```

Returns the next byte from the stream or returns `error.EndOfStream`.

Does not advance the seek position.

Asserts the buffer capacity is nonzero.

### `takeByte`

```zig
pub fn takeByte(r: *Reader) Error!u8
```

Reads 1 byte from the stream or returns `error.EndOfStream`.

Asserts the buffer capacity is nonzero.

### `takeByteSigned`

```zig
pub fn takeByteSigned(r: *Reader) Error!i8
```

Same as `takeByte` except the returned byte is signed.

### `takeInt`

```zig
pub inline fn takeInt(r: *Reader, comptime T: type, endian: std.builtin.Endian) Error!T
```

Asserts the buffer was initialized with a capacity at least `@bitSizeOf(T) / 8`.

### `peekInt`

```zig
pub inline fn peekInt(r: *Reader, comptime T: type, endian: std.builtin.Endian) Error!T
```

Asserts the buffer was initialized with a capacity at least `@bitSizeOf(T) / 8`.

### `takeVarInt`

```zig
pub fn takeVarInt(r: *Reader, comptime Int: type, endian: std.builtin.Endian, n: usize) Error!Int
```

Asserts the buffer was initialized with a capacity at least `n`.

### `takeStructPointer`

```zig
pub fn takeStructPointer(r: *Reader, comptime T: type) Error!*align(1) T
```

Obtains an unaligned pointer to the beginning of the stream, reinterpreted
as a pointer to the provided type, advancing the seek position.

Asserts the buffer was initialized with a capacity at least `@sizeOf(T)`.

See also:
* `peekStructPointer`
* `takeStruct`

### `peekStructPointer`

```zig
pub fn peekStructPointer(r: *Reader, comptime T: type) Error!*align(1) T
```

Obtains an unaligned pointer to the beginning of the stream, reinterpreted
as a pointer to the provided type, without advancing the seek position.

Asserts the buffer was initialized with a capacity at least `@sizeOf(T)`.

See also:
* `takeStructPointer`
* `peekStruct`

### `takeStruct`

```zig
pub inline fn takeStruct(r: *Reader, comptime T: type, endian: std.builtin.Endian) Error!T
```

This function is inline to avoid referencing `std.mem.byteSwapAllFields`
when `endian` is comptime-known and matches the host endianness.

See also:
* `takeStructPointer`
* `peekStruct`

### `peekStruct`

```zig
pub inline fn peekStruct(r: *Reader, comptime T: type, endian: std.builtin.Endian) Error!T
```

Asserts the buffer was initialized with a capacity at least `@sizeOf(T)`.

This function is inline to avoid referencing `std.mem.byteSwapAllFields`
when `endian` is comptime-known and matches the host endianness.

See also:
* `takeStruct`
* `peekStructPointer`

### `takeEnum`

```zig
pub fn takeEnum(r: *Reader, comptime Enum: type, endian: std.builtin.Endian) TakeEnumError!Enum
```

Reads an integer with the same size as the given enum's tag type. If the
integer matches an enum tag, casts the integer to the enum tag and returns
it. Otherwise, returns `error.InvalidEnumTag`.

Asserts the buffer was initialized with a capacity at least `@sizeOf(Enum)`.

### `takeEnumNonexhaustive`

```zig
pub fn takeEnumNonexhaustive(r: *Reader, comptime Enum: type, endian: std.builtin.Endian) Error!Enum
```

Reads an integer with the same size as the given nonexhaustive enum's tag type.

Asserts the buffer was initialized with a capacity at least `@sizeOf(Enum)`.

### `takeLeb128`

```zig
pub fn takeLeb128(r: *Reader, comptime T: type) TakeLeb128Error!T
```

Read a single LEB128 value as type T, or `error.Overflow` if the value cannot fit.

### `rebase`

```zig
pub fn rebase(r: *Reader, capacity: usize) Error!void
```

Ensures `capacity` data can be buffered without rebasing.

### `defaultRebase`

```zig
pub fn defaultRebase(r: *Reader, capacity: usize) Error!void
```


### `writableVectorPosix`

```zig
pub fn writableVectorPosix(r: *Reader, buffer: []std.posix.iovec, data: []const []u8) Error!struct { usize, usize }
```


### `writableVectorWsa`

```zig
pub fn writableVectorWsa(r: *Reader, buffer: []std.os.windows.AFD.WSABUF(.@"var"), data: []const []u8, ) Error!struct { usize, usize }
```


### `writableVector`

```zig
pub fn writableVector(r: *Reader, buffer: [][]u8, data: []const []u8) Error!struct { usize, usize }
```


## Error Sets

- **`StreamError`**
  
- **`Error`**
  
- **`StreamRemainingError`**
  
- **`ShortError`**
  
- **`LimitedAllocError`**
  
- **`AppendExactError`**
  
- **`UnlimitedAllocError`**
  
- **`ReadAllocError`**
  
- **`DelimiterError`**
  
- **`StreamDelimiterLimitError`**
  
- **`DiscardDelimiterLimitError`**
  
- **`TakeEnumError`**
  
- **`TakeLeb128Error`**
  

## Constants & Variables

- **`Limited`**: 
- **`RebaseError`**: 
- **`failing`**: 
- **`ending_instance`**: This is generally safe to `@constCast` because it has an empty buffer, so
- **`ending`**: 
- **`readAlloc`**: Deprecated; use readAllocAll. to be removed after 0.17.

