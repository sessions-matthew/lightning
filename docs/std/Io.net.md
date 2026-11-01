# `std.Io.net`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/Io/net.zig`  
> [← Back to Standard Library Index](README.md)

## Types

### `Protocol`

Source of truth: Internet Assigned Numbers Authority (IANA)

### Fields

- `hopopts = 0`
  
- `icmp = 1`
  
- `igmp = 2`
  
- `ipip = 4`
  
- `tcp = 6`
  
- `egp = 8`
  
- `pup = 12`
  
- `udp = 17`
  
- `idp = 22`
  
- `tp = 29`
  
- `dccp = 33`
  
- `ipv6 = 41`
  
- `routing = 43`
  
- `fragment = 44`
  
- `rsvp = 46`
  
- `gre = 47`
  
- `esp = 50`
  
- `ah = 51`
  
- `icmpv6 = 58`
  
- `none = 59`
  
- `dstopts = 60`
  
- `mtp = 92`
  
- `beetph = 94`
  
- `encap = 98`
  
- `pim = 103`
  
- `comp = 108`
  
- `sctp = 132`
  
- `mh = 135`
  
- `udplite = 136`
  
- `mpls = 137`
  
- `ethernet = 143`
  
- `raw = 255`
  
- `mptcp = 262`
  
- `_`
  

### `IpAddress`


### Fields

- `ip4: Ip4Address`
  
- `ip6: Ip6Address`
  

### Types

#### `ListenOptions`


#### `BindOptions`


#### `ConnectOptions`


### Functions

#### `parseLiteral`

```zig
pub fn parseLiteral(text: []const u8) ParseLiteralError!IpAddress
```

Parse an IP address which may include a port.

For IPv4, this is written `address:port`.

For IPv6, RFC 3986 defines this as an "IP literal", and the port is
differentiated from the address by surrounding the address part in
brackets "[addr]:port". Even if the port is not given, the brackets are
mandatory.

#### `parse`

```zig
pub fn parse(text: []const u8, port: u16) !IpAddress
```

Parse the given IP address string into an `IpAddress` value.

This is a pure function but it cannot handle IPv6 addresses that have
scope ids ("%foo" at the end). To also handle those, `resolve` must be
called instead.

#### `parseIp4`

```zig
pub fn parseIp4(text: []const u8, port: u16) Ip4Address.ParseError!IpAddress
```


#### `parseIp6`

```zig
pub fn parseIp6(text: []const u8, port: u16) Ip6Address.ParseError!IpAddress
```

This is a pure function but it cannot handle IPv6 addresses that have
scope ids ("%foo" at the end). To also handle those, `resolveIp6` must be
called instead.

#### `resolve`

```zig
pub fn resolve(io: Io, text: []const u8, port: u16) !IpAddress
```

This function requires an `Io` parameter because it must query the operating
system to convert interface name to index. For example, in
"fe80::e0e:76ff:fed4:cf22%eno1", "eno1" must be resolved to an index by
creating a socket and then using an `ioctl` syscall.

For a pure function that cannot handle scopes, see `parse`.

#### `resolveIp6`

```zig
pub fn resolveIp6(io: Io, text: []const u8, port: u16) Ip6Address.ResolveError!IpAddress
```


#### `getPort`

```zig
pub fn getPort(a: IpAddress) u16
```

Returns the port in native endian.

#### `setPort`

```zig
pub fn setPort(a: *IpAddress, port: u16) void
```

`port` is native-endian.

#### `fromIp6`

```zig
pub fn fromIp6(ip6: Ip6Address) IpAddress
```

Converts from an IPv4-mapped IPv6 address, or returns the IPv6 address directly.

#### `formatResolved`

```zig
pub fn formatResolved(a: IpAddress, io: Io, w: *Io.Writer) Ip6Address.FormatError!void
```

Includes the optional scope ("%foo" at the end) in IPv6 addresses.

See `format` for an alternative that omits scopes and does
not require an `Io` parameter.

#### `format`

```zig
pub fn format(a: IpAddress, w: *Io.Writer) Io.Writer.Error!void
```

See `formatResolved` for an alternative that additionally prints the optional
scope at the end of IPv6 addresses and requires an `Io` parameter.

#### `eql`

```zig
pub fn eql(a: *const IpAddress, b: *const IpAddress) bool
```


#### `listen`

```zig
pub fn listen(address: *const IpAddress, io: Io, options: ListenOptions) ListenError!Server
```

Waits for a TCP connection. When using this API, `bind` does not need
to be called. The returned `Server` has an open `stream`.

#### `bind`

```zig
pub fn bind(address: *const IpAddress, io: Io, options: BindOptions) BindError!Socket
```

Associates an address with a `Socket` which can be used to receive UDP
packets and other kinds of non-streaming messages. See `listen` for a
streaming alternative.

One bound `Socket` can be used to receive messages from multiple
different addresses.

#### `connect`

```zig
pub fn connect(address: *const IpAddress, io: Io, options: ConnectOptions) ConnectError!Stream
```

Initiates a connection-oriented network stream.

### Error Sets

- **`ParseLiteralError`**
  
- **`ListenError`**
  
- **`BindError`**
  
- **`ConnectError`**
  

### Constants & Variables

- **`Family`**: 

### `Ip4Address`

An IPv4 address in binary memory layout.

### Fields

- `bytes: [4]u8`
  
- `port: u16`
  

### Functions

#### `loopback`

```zig
pub fn loopback(port: u16) Ip4Address
```


#### `unspecified`

```zig
pub fn unspecified(port: u16) Ip4Address
```


#### `fromIp6`

```zig
pub fn fromIp6(ip6: Ip6Address) ?Ip4Address
```

Converts from an IPv4-mapped IPv6 address, or returns `null`.

#### `fromAny`

```zig
pub fn fromAny(addr: IpAddress) ?Ip6Address
```

Given an `IpAddress`, converts it to an `Ip4Address` directly, or from
an IPv4-mapped IPv6 address, or returns `null`.

#### `parse`

```zig
pub fn parse(buffer: []const u8, port: u16) ParseError!Ip4Address
```


#### `format`

```zig
pub fn format(a: Ip4Address, w: *Io.Writer) Io.Writer.Error!void
```


#### `eql`

```zig
pub fn eql(a: Ip4Address, b: Ip4Address) bool
```


### Error Sets

- **`ParseError`**
  

### `Ip6Address`

An IPv6 address in binary memory layout.

### Fields

- `port: u16`
  Native endian
- `bytes: [16]u8`
  Big endian
- `flow: u32 = 0`
  
- `interface: Interface = .none`
  

### Types

#### `Policy`


#### `Unresolved`

An IPv6 address but with `Interface` as a name rather than index.

### Functions

#### `loopback`

```zig
pub fn loopback(port: u16) Ip6Address
```


#### `unspecified`

```zig
pub fn unspecified(port: u16) Ip6Address
```


#### `fromIp4`

```zig
pub fn fromIp4(ip4: Ip4Address) Ip6Address
```

Constructs an IPv4-mapped IPv6 address.

#### `fromAny`

```zig
pub fn fromAny(addr: IpAddress) Ip6Address
```

Given an `IpAddress`, converts it to an `Ip6Address` directly, or via
constructing an IPv4-mapped IPv6 address.

#### `parse`

```zig
pub fn parse(buffer: []const u8, port: u16) ParseError!Ip6Address
```

This is a pure function but it cannot handle IPv6 addresses that have
scope ids ("%foo" at the end). To also handle those, `resolve` must be
called instead, or the lower level `Unresolved` API may be used.

#### `resolve`

```zig
pub fn resolve(io: Io, buffer: []const u8, port: u16) ResolveError!Ip6Address
```

This function requires an `Io` parameter because it must query the operating
system to convert interface name to index. For example, in
"fe80::e0e:76ff:fed4:cf22%eno1", "eno1" must be resolved to an index by
creating a socket and then using an `ioctl` syscall.

#### `formatResolved`

```zig
pub fn formatResolved(a: *const Ip6Address, io: Io, w: *Io.Writer) FormatError!void
```

Includes the optional scope ("%foo" at the end).

See `format` for an alternative that omits scopes and does
not require an `Io` parameter.

#### `format`

```zig
pub fn format(a: *const Ip6Address, w: *Io.Writer) Io.Writer.Error!void
```

See `formatResolved` for an alternative that additionally prints the optional
scope at the end of addresses and requires an `Io` parameter.

#### `eql`

```zig
pub fn eql(a: Ip6Address, b: Ip6Address) bool
```


#### `isMultiCast`

```zig
pub fn isMultiCast(a: Ip6Address) bool
```


#### `isLinkLocal`

```zig
pub fn isLinkLocal(a: Ip6Address) bool
```


#### `isLoopBack`

```zig
pub fn isLoopBack(a: Ip6Address) bool
```


#### `isSiteLocal`

```zig
pub fn isSiteLocal(a: Ip6Address) bool
```


#### `policy`

```zig
pub fn policy(a: Ip6Address) *const Policy
```


#### `scope`

```zig
pub fn scope(a: Ip6Address) u8
```


### Error Sets

- **`ParseError`**
  
- **`ResolveError`**
  
- **`FormatError`**
  

### `UnixAddress`


### Fields

- `path: []const u8`
  

### Types

#### `ListenOptions`


### Functions

#### `init`

```zig
pub fn init(p: []const u8) InitError!UnixAddress
```


#### `isAbstract`

```zig
pub fn isAbstract(ua: *const UnixAddress) bool
```


#### `listen`

```zig
pub fn listen(ua: *const UnixAddress, io: Io, options: ListenOptions) ListenError!Server
```


#### `connect`

```zig
pub fn connect(ua: *const UnixAddress, io: Io) ConnectError!Stream
```


### Error Sets

- **`InitError`**
  
- **`ListenError`**
  
- **`ConnectError`**
  

### Constants & Variables

- **`max_len`**: 

### `ReceiveFlags`


### Fields

- `oob: bool = false`
  
- `peek: bool = false`
  
- `trunc: bool = false`
  
- `_: u5 = 0`
  

### `IncomingMessage`


### Fields

- `from: IpAddress`
  Populated by receive functions.
- `data: []u8`
  Populated by receive functions, points into the caller-supplied buffer.
- `control: []u8`
  Supplied by caller before calling receive functions; mutated by receive
  functions.
- `flags: Flags`
  Populated by receive functions.

### Types

#### `Flags`


### Constants & Variables

- **`init`**: Useful for initializing before calling `receiveManyTimeout`.

### `OutgoingMessage`


### Fields

- `address: *const IpAddress`
  
- `data_ptr: [*]const u8`
  
- `data_len: usize`
  Initialized with how many bytes of `data_ptr` to send. After sending
  succeeds, replaced with how many bytes were actually sent.
- `control: []const u8 = &.{}`
  

### `SendFlags`


### Fields

- `confirm: bool = false`
  
- `dont_route: bool = false`
  
- `eor: bool = false`
  
- `oob: bool = false`
  
- `fastopen: bool = false`
  
- `_: u3 = 0`
  

### `ShutdownHow`


### Fields

- `recv`
  
- `send`
  
- `both`
  

### `Interface`


### Fields

- `index: u32`
  Value 0 indicates `none`.

### Types

#### `Name`


### Functions

#### `name`

```zig
pub fn name(i: Interface, io: Io) NameError!Name
```

Asserts not `none`.

Corresponds to "if_indextoname" in libc.

#### `isNone`

```zig
pub fn isNone(i: Interface) bool
```


### Error Sets

- **`NameError`**
  

### Constants & Variables

- **`none`**: 

### `Socket`

An open port with unspecified protocol.

### Fields

- `handle: Handle`
  
- `address: IpAddress`
  Contains the resolved ephemeral port number if requested.

### Types

#### `Mode`


#### `sendManyTimeout`

```zig
pub fn sendManyTimeout(s: *const Socket, io: Io, messages: []OutgoingMessage, flags: SendFlags, timeout: Io.Timeout, ) struct { ?SendTimeoutError, usize }
```


#### `receiveManyTimeout`

```zig
pub fn receiveManyTimeout(s: *const Socket, io: Io, message_buffer: []IncomingMessage, data_buffer: []u8, flags: ReceiveFlags, timeout: Io.Timeout, ) struct { ?ReceiveTimeoutError, usize }
```

Waits until at least one message is delivered, possibly returning more
than one message. Connectionless.

Returns number of messages received, or `error.Timeout` if no message
arrives early enough.

See also:
* `receive`
* `receiveTimeout`

#### `CreatePairOptions`


### Functions

#### `close`

```zig
pub fn close(s: *const Socket, io: Io) void
```

Leaves `address` in a valid state.

#### `closeMany`

```zig
pub fn closeMany(io: Io, sockets: []const Socket) void
```


#### `send`

```zig
pub fn send(s: *const Socket, io: Io, dest: *const IpAddress, data: []const u8) SendError!void
```

Transfers `data` to `dest`, connectionless, in one packet.

#### `sendTimeout`

```zig
pub fn sendTimeout(s: *const Socket, io: Io, dest: *const IpAddress, data: []const u8, timeout: Io.Timeout, ) SendTimeoutError!void
```


#### `sendMany`

```zig
pub fn sendMany(s: *const Socket, io: Io, messages: []OutgoingMessage, flags: SendFlags) SendError!void
```

Deprecated; use `sendManyTimeout` with a timeout of `.none`.

If this function returns an error, some (but not all) of `messages` may
still have been sent. This condition is not reported by this function,
but is reported by `sendManyTimeout`.

#### `receive`

```zig
pub fn receive(s: *const Socket, io: Io, buffer: []u8) ReceiveError!IncomingMessage
```

Waits for data. Connectionless.

See also:
* `receiveTimeout`

#### `receiveTimeout`

```zig
pub fn receiveTimeout(s: *const Socket, io: Io, buffer: []u8, timeout: Io.Timeout, ) ReceiveTimeoutError!IncomingMessage
```

Waits for data. Connectionless.

Returns `error.Timeout` if no message arrives early enough.

See also:
* `receive`
* `receiveManyTimeout`

#### `createPair`

```zig
pub fn createPair(io: Io, options: CreatePairOptions) CreatePairError![2]Socket
```

Create a set of two sockets that are connected to each other.

Also known as "socketpair".

### Error Sets

- **`SendError`**
  
- **`SendTimeoutError`**
  
- **`ReceiveError`**
  
- **`ReceiveTimeoutError`**
  
- **`CreatePairError`**
  

### Constants & Variables

- **`Handle`**: Underlying platform-defined type which may or may not be

### `Stream`

An open socket connection with a network protocol that guarantees
sequencing, delivery, and prevents repetition. Typically TCP or UNIX domain
socket.

### Fields

- `socket: Socket`
  

### Types

#### `ReadResult`


#### `Reader`


#### `Writer`


### Functions

#### `read`

```zig
pub fn read(s: *const Stream, io: Io, data: [][]u8) Reader.Error!usize
```

This is a low-level API that calls the `Io` interface function directly.
For a higher level API, see `reader`.

#### `readWithControl`

```zig
pub fn readWithControl(s: *const Stream, io: Io, data: [][]u8, control: []u8) Reader.Error!ReadResult
```

Read with control data.

This is a low-level API that calls the `Io` interface function directly.
For a higher level API, see `reader`.

#### `close`

```zig
pub fn close(s: *const Stream, io: Io) void
```


#### `shutdown`

```zig
pub fn shutdown(s: *const Stream, io: Io, how: ShutdownHow) ShutdownError!void
```


#### `reader`

```zig
pub fn reader(stream: Stream, io: Io, buffer: []u8) Reader
```


#### `readerWithControl`

```zig
pub fn readerWithControl(stream: Stream, io: Io, buffer: []u8, control_buffer: []align(cmsg_align) u8, ) Reader
```

Same as `reader`, but also provides a buffer for storing control data.

#### `writer`

```zig
pub fn writer(stream: Stream, io: Io, buffer: []u8) Writer
```


### `Server`


### Fields

- `socket: Socket`
  
- `options: AcceptOptions`
  

### Types

#### `AcceptOptions`


### Functions

#### `deinit`

```zig
pub fn deinit(s: *Server, io: Io) void
```


#### `accept`

```zig
pub fn accept(s: *Server, io: Io) AcceptError!Stream
```

Blocks until a client connects to the server.

### Error Sets

- **`AcceptError`**
  

## Namespaces

- **`cmsg`**: Utility Functions for interacting with POSIX socket control messages.

## Error Sets

- **`ShutdownError`**
  

## Constants & Variables

- **`HostName`**: 
- **`has_unix_sockets`**: Windows 10 added support for unix sockets in build 17063, redstone 4 is the
- **`default_kernel_backlog`**: 
- **`cmsg_align`**: 

