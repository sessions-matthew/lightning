# `std.Io.Terminal`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/Io/Terminal.zig`  
> [← Back to Standard Library Index](README.md)

## Fields

- `writer: *Io.Writer`
  
- `mode: Mode`
  

## Types

### `Color`


### Fields

- `black`
  
- `red`
  
- `green`
  
- `yellow`
  
- `blue`
  
- `magenta`
  
- `cyan`
  
- `white`
  
- `bright_black`
  
- `bright_red`
  
- `bright_green`
  
- `bright_yellow`
  
- `bright_blue`
  
- `bright_magenta`
  
- `bright_cyan`
  
- `bright_white`
  
- `dim`
  
- `bold`
  
- `reset`
  

### `Mode`


### Fields

- `no_color`
  
- `escape_codes`
  
- `windows_api: WindowsApi`
  

### Types

#### `WindowsApi`


### Functions

#### `detect`

```zig
pub fn detect(io: Io, file: File, NO_COLOR: bool, CLICOLOR_FORCE: bool) Io.Cancelable!Mode
```

Detect suitable TTY configuration options for the given file (commonly
stdout/stderr).

Will attempt to enable ANSI escape code support if necessary/possible.

* `NO_COLOR` indicates whether "NO_COLOR" environment variable is
  present and non-empty.
* `CLICOLOR_FORCE` indicates whether "CLICOLOR_FORCE" environment
  variable is present and non-empty.

## Functions

### `setColor`

```zig
pub fn setColor(t: Terminal, color: Color) SetColorError!void
```


## Error Sets

- **`SetColorError`**
  

