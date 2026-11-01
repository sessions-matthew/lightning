# `std.http`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/http.zig`  
> [← Back to Standard Library Index](README.md)

## Types

### `Version`


### Fields

- `@"HTTP/1.0"`
  
- `@"HTTP/1.1"`
  

### `Method`

https://developer.mozilla.org/en-US/docs/Web/HTTP/Methods

https://datatracker.ietf.org/doc/html/rfc7231#section-4 Initial definition

https://datatracker.ietf.org/doc/html/rfc5789#section-2 PATCH

https://datatracker.ietf.org/doc/html/rfc10008#name-query-method QUERY

### Fields

- `GET`
  
- `HEAD`
  
- `POST`
  
- `PUT`
  
- `DELETE`
  
- `CONNECT`
  
- `OPTIONS`
  
- `TRACE`
  
- `PATCH`
  
- `QUERY`
  

### Functions

#### `requestHasBody`

```zig
pub fn requestHasBody(m: Method) bool
```

Returns true if a request of this method is allowed to have a body
Actual behavior from servers may vary and should still be checked

#### `responseHasBody`

```zig
pub fn responseHasBody(m: Method) bool
```

Returns true if a response to this method is allowed to have a body
Actual behavior from clients may vary and should still be checked

#### `safe`

```zig
pub fn safe(m: Method) bool
```

An HTTP method is safe if it doesn't alter the state of the server.

https://developer.mozilla.org/en-US/docs/Glossary/Safe/HTTP

https://datatracker.ietf.org/doc/html/rfc7231#section-4.2.1

#### `idempotent`

```zig
pub fn idempotent(m: Method) bool
```

An HTTP method is idempotent if an identical request can be made once
or several times in a row with the same effect while leaving the server
in the same state.

https://developer.mozilla.org/en-US/docs/Glossary/Idempotent

https://datatracker.ietf.org/doc/html/rfc7231#section-4.2.2

#### `cacheable`

```zig
pub fn cacheable(m: Method) bool
```

A cacheable response can be stored to be retrieved and used later,
saving a new request to the server.

https://developer.mozilla.org/en-US/docs/Glossary/cacheable

https://datatracker.ietf.org/doc/html/rfc7231#section-4.2.3

### `Status`

https://developer.mozilla.org/en-US/docs/Web/HTTP/Status

### Fields

- `@"continue" = 100`
  
- `switching_protocols = 101`
  
- `processing = 102`
  
- `early_hints = 103`
  
- `ok = 200`
  
- `created = 201`
  
- `accepted = 202`
  
- `non_authoritative_info = 203`
  
- `no_content = 204`
  
- `reset_content = 205`
  
- `partial_content = 206`
  
- `multi_status = 207`
  
- `already_reported = 208`
  
- `im_used = 226`
  
- `multiple_choice = 300`
  
- `moved_permanently = 301`
  
- `found = 302`
  
- `see_other = 303`
  
- `not_modified = 304`
  
- `use_proxy = 305`
  
- `temporary_redirect = 307`
  
- `permanent_redirect = 308`
  
- `bad_request = 400`
  
- `unauthorized = 401`
  
- `payment_required = 402`
  
- `forbidden = 403`
  
- `not_found = 404`
  
- `method_not_allowed = 405`
  
- `not_acceptable = 406`
  
- `proxy_auth_required = 407`
  
- `request_timeout = 408`
  
- `conflict = 409`
  
- `gone = 410`
  
- `length_required = 411`
  
- `precondition_failed = 412`
  
- `payload_too_large = 413`
  
- `uri_too_long = 414`
  
- `unsupported_media_type = 415`
  
- `range_not_satisfiable = 416`
  
- `expectation_failed = 417`
  
- `teapot = 418`
  
- `misdirected_request = 421`
  
- `unprocessable_entity = 422`
  
- `locked = 423`
  
- `failed_dependency = 424`
  
- `too_early = 425`
  
- `upgrade_required = 426`
  
- `precondition_required = 428`
  
- `too_many_requests = 429`
  
- `request_header_fields_too_large = 431`
  
- `unavailable_for_legal_reasons = 451`
  
- `internal_server_error = 500`
  
- `not_implemented = 501`
  
- `bad_gateway = 502`
  
- `service_unavailable = 503`
  
- `gateway_timeout = 504`
  
- `http_version_not_supported = 505`
  
- `variant_also_negotiates = 506`
  
- `insufficient_storage = 507`
  
- `loop_detected = 508`
  
- `not_extended = 510`
  
- `network_authentication_required = 511`
  
- `_`
  

### Types

#### `Class`


### Functions

#### `phrase`

```zig
pub fn phrase(self: Status) ?[]const u8
```


#### `class`

```zig
pub fn class(self: Status) Class
```


### `TransferEncoding`

compression is intentionally omitted here since it is handled in `ContentEncoding`.

### Fields

- `chunked`
  
- `none`
  

### `ContentEncoding`


### Fields

- `zstd`
  
- `gzip`
  
- `deflate`
  
- `compress`
  
- `identity`
  

### Functions

#### `fromString`

```zig
pub fn fromString(s: []const u8) ?ContentEncoding
```


#### `minBufferCapacity`

```zig
pub fn minBufferCapacity(ce: ContentEncoding) usize
```


### `Connection`


### Fields

- `keep_alive`
  
- `close`
  

### `Header`


### Fields

- `name: []const u8`
  
- `value: []const u8`
  

### `Reader`


### Fields

- `in: *std.Io.Reader`
  
- `interface: std.Io.Reader`
  This is preallocated memory that might be used by `bodyReader`. That
  function might return a pointer to this field, or a different
  `*std.Io.Reader`. Advisable to not access this field directly.
- `state: State`
  Keeps track of whether the stream is ready to accept a new request,
  making invalid API usage cause assertion failures rather than HTTP
  protocol violations.
- `trailers: []const u8 = &.{}`
  HTTP trailer bytes. These are at the end of a transfer-encoding:
  chunked message. This data is available only after calling one of the
  "end" functions and points to data inside the buffer of `in`, and is
  therefore invalidated on the next call to `receiveHead`, or any other
  read from `in`.
- `body_err: ?BodyError = null`
  
- `max_head_len: usize`
  

### Types

#### `RemainingChunkLen`


#### `State`


### Functions

#### `receiveHead`

```zig
pub fn receiveHead(reader: *Reader) HeadError![]const u8
```

Buffers the entire head inside `in`.

The resulting memory is invalidated by any subsequent consumption of
the input stream.

#### `bodyReader`

```zig
pub fn bodyReader(reader: *Reader, transfer_buffer: []u8, transfer_encoding: TransferEncoding, content_length: ?u64, ) *std.Io.Reader
```

If compressed body has been negotiated this will return compressed bytes.

Asserts only called once and after `receiveHead`.

See also:
* `interfaceDecompressing`

#### `bodyReaderDecompressing`

```zig
pub fn bodyReaderDecompressing(reader: *Reader, transfer_buffer: []u8, transfer_encoding: TransferEncoding, content_length: ?u64, content_encoding: ContentEncoding, decompress: *Decompress, decompress_buffer: []u8, ) *std.Io.Reader
```

If compressed body has been negotiated this will return decompressed bytes.

Asserts only called once and after `receiveHead`.

See also:
* `interface`

### Error Sets

- **`BodyError`**
  
- **`HeadError`**
  

### `Decompress`


### Fields

- `flate: std.compress.flate.Decompress`
  
- `zstd: std.compress.zstd.Decompress`
  
- `none: *std.Io.Reader`
  

### Functions

#### `init`

```zig
pub fn init(decompress: *Decompress, transfer_reader: *std.Io.Reader, buffer: []u8, content_encoding: ContentEncoding, ) *std.Io.Reader
```


### `BodyWriter`

Request or response body.

### Fields

- `http_protocol_output: *Writer`
  Until the lifetime of `BodyWriter` ends, it is illegal to modify the
  state of this other than via methods of `BodyWriter`.
- `state: State`
  
- `writer: Writer`
  

### Types

#### `State`


#### `EndChunkedOptions`


### Functions

#### `isEliding`

```zig
pub fn isEliding(w: *const BodyWriter) bool
```


#### `flush`

```zig
pub fn flush(w: *BodyWriter) Error!void
```

Sends all buffered data across `BodyWriter.http_protocol_output`.

#### `end`

```zig
pub fn end(w: *BodyWriter) Error!void
```

When using content-length, asserts that the amount of data sent matches
the value sent in the header, then flushes `http_protocol_output`.

When using transfer-encoding: chunked, writes the end-of-stream message
with empty trailers, then flushes the stream to the system. Asserts any
started chunk has been completely finished.

Respects the value of `isEliding` to omit all data after the headers.

See also:
* `endUnflushed`
* `endChunked`

#### `endUnflushed`

```zig
pub fn endUnflushed(w: *BodyWriter) Error!void
```

When using content-length, asserts that the amount of data sent matches
the value sent in the header.

Otherwise, transfer-encoding: chunked is being used, and it writes the
end-of-stream message with empty trailers.

Respects the value of `isEliding` to omit all data after the headers.

Does not flush `http_protocol_output`, but does flush `writer`.

See also:
* `end`
* `endChunked`

#### `endChunked`

```zig
pub fn endChunked(w: *BodyWriter, options: EndChunkedOptions) Error!void
```

Writes the end-of-stream message and any optional trailers, flushing
the underlying stream.

Asserts that the BodyWriter is using transfer-encoding: chunked.

Respects the value of `isEliding` to omit all data after the headers.

See also:
* `endChunkedUnflushed`
* `end`

#### `endChunkedUnflushed`

```zig
pub fn endChunkedUnflushed(w: *BodyWriter, options: EndChunkedOptions) Error!void
```

Writes the end-of-stream message and any optional trailers.

Does not flush.

Asserts that the BodyWriter is using transfer-encoding: chunked.

Respects the value of `isEliding` to omit all data after the headers.

See also:
* `endChunked`
* `endUnflushed`
* `end`

#### `contentLengthDrain`

```zig
pub fn contentLengthDrain(w: *Writer, data: []const []const u8, splat: usize) Error!usize
```


#### `noneDrain`

```zig
pub fn noneDrain(w: *Writer, data: []const []const u8, splat: usize) Error!usize
```


#### `elidingDrain`

```zig
pub fn elidingDrain(w: *Writer, data: []const []const u8, splat: usize) Error!usize
```


#### `elidingSendFile`

```zig
pub fn elidingSendFile(w: *Writer, file_reader: *File.Reader, limit: std.Io.Limit) Writer.FileError!usize
```


#### `noneSendFile`

```zig
pub fn noneSendFile(w: *Writer, file_reader: *File.Reader, limit: std.Io.Limit) Writer.FileError!usize
```

Returns `null` if size cannot be computed without making any syscalls.

#### `contentLengthSendFile`

```zig
pub fn contentLengthSendFile(w: *Writer, file_reader: *File.Reader, limit: std.Io.Limit) Writer.FileError!usize
```


#### `chunkedSendFile`

```zig
pub fn chunkedSendFile(w: *Writer, file_reader: *File.Reader, limit: std.Io.Limit) Writer.FileError!usize
```


#### `chunkedDrain`

```zig
pub fn chunkedDrain(w: *Writer, data: []const []const u8, splat: usize) Error!usize
```


### Constants & Variables

- **`Error`**: 

## Constants & Variables

- **`Client`**: 
- **`Server`**: 
- **`HeadParser`**: 
- **`ChunkParser`**: 
- **`HeaderIterator`**: 

