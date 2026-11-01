# `std.log`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/log.zig`  
> [← Back to Standard Library Index](README.md)

std.log is a standardized interface for logging which allows for the logging
of programs and libraries using this interface to be formatted and filtered
by the implementer of the `std.options.logFn` function.

Each log message has an associated scope enum, which can be used to give
context to the logging. The logging functions in std.log implicitly use a
scope of .default.

A logging namespace using a custom scope can be created using the
std.log.scoped function, passing the scope as an argument; the logging
functions in the resulting struct use the provided scope parameter.
For example, a library called 'libfoo' might use
`const log = std.log.scoped(.libfoo);` to use .libfoo as the scope of its
log messages.

For an example implementation of the `logFn` function, see `defaultLog`,
which is the default implementation. It outputs to stderr, using color if
supported. Its output looks like this:
```
error: this is an error
error(scope): this is an error with a non-default scope
warning: this is a warning
info: this is an informative message
debug: this is a debugging message
```

## Types

### `Level`


### Fields

- `err`
  Error: something has gone wrong. This might be recoverable or might
  be followed by the program exiting.
- `warn`
  Warning: it is uncertain if something has gone wrong or not, but the
  circumstances would be worth investigating.
- `info`
  Info: general messages about the state of the program.
- `debug`
  Debug: messages only useful for debugging.

### Functions

#### `asText`

```zig
pub fn asText(comptime self: Level) []const u8
```

Returns a string literal of the given level in full text form.

### `ScopeLevel`


### Fields

- `scope: @EnumLiteral()`
  
- `level: Level`
  

### `scoped`

```zig
pub fn scoped(comptime scope: @EnumLiteral()) type
```

Returns a scoped logging namespace that logs all messages using the scope
provided here.

### Functions

#### `err`

```zig
pub fn err(comptime format: []const u8, args: anytype, ) void
```

Log an error message. This log level is intended to be used
when something has gone wrong. This might be recoverable or might
be followed by the program exiting.

#### `warn`

```zig
pub fn warn(comptime format: []const u8, args: anytype, ) void
```

Log a warning message. This log level is intended to be used if
it is uncertain whether something has gone wrong or not, but the
circumstances would be worth investigating.

#### `info`

```zig
pub fn info(comptime format: []const u8, args: anytype, ) void
```

Log an info message. This log level is intended to be used for
general messages about the state of the program.

#### `debug`

```zig
pub fn debug(comptime format: []const u8, args: anytype, ) void
```

Log a debug message. This log level is intended to be used for
messages which are only useful for debugging.

### `default`

The default scoped logging namespace.

## Functions

### `logEnabled`

```zig
pub fn logEnabled(comptime level: Level, comptime scope: @EnumLiteral()) bool
```

Determine if a specific log message level and scope combination are enabled for logging.

### `defaultTerminalMode`

```zig
pub fn defaultTerminalMode() std.Io.Terminal.Mode
```


### `defaultLog`

```zig
pub fn defaultLog(comptime level: Level, comptime scope: @EnumLiteral(), comptime format: []const u8, args: anytype, ) void
```

The default implementation for the log function. Custom log functions may
forward log messages to this function.

Uses a 64-byte buffer for formatted printing which is flushed before this
function returns.

### `defaultLogFileTerminal`

```zig
pub fn defaultLogFileTerminal(comptime level: Level, comptime scope: @EnumLiteral(), comptime format: []const u8, args: anytype, t: std.Io.Terminal, ) std.Io.Writer.Error!void
```


## Constants & Variables

- **`default_level`**: The default log level is based on build mode.
- **`terminalMode`**: 
- **`default_log_scope`**: 
- **`err`**: Log an error message using the default scope. This log level is intended to
- **`warn`**: Log a warning message using the default scope. This log level is intended
- **`info`**: Log an info message using the default scope. This log level is intended to
- **`debug`**: Log a debug message using the default scope. This log level is intended to

