# `std.tar`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/tar.zig`  
> [← Back to Standard Library Index](README.md)

Tar archive is single ordinary file which can contain many files (or
directories, symlinks, ...). It's build by series of blocks each size of 512
bytes. First block of each entry is header which defines type, name, size
permissions and other attributes. Header is followed by series of blocks of
file content, if any that entry has content. Content is padded to the block
size, so next header always starts at block boundary.

This simple format is extended by GNU and POSIX pax extensions to support
file names longer than 256 bytes and additional attributes.

This is not comprehensive tar parser. Here we are only file types needed to
support Zig package manager; normal file, directory, symbolic link. And
subset of attributes: name, size, permissions.

GNU tar reference: https://www.gnu.org/software/tar/manual/html_node/Standard.html
pax reference: https://pubs.opengroup.org/onlinepubs/9699919799/utilities/pax.html#tag_20_92_13

## Types

### `Diagnostics`

Provide this to receive detailed error messages.
When this is provided, some errors which would otherwise be returned
immediately will instead be added to this structure. The API user must check
the errors in diagnostics to know whether the operation succeeded or failed.

### Fields

- `allocator: std.mem.Allocator`
  
- `errors: std.ArrayList(Error) = .empty`
  
- `entries: usize = 0`
  
- `root_dir: []const u8 = ""`
  

### Types

#### `Error`


### Functions

#### `deinit`

```zig
pub fn deinit(d: *Diagnostics) void
```


### `ExtractOptions`


### Fields

- `strip_components: u32 = 0`
  Number of directory levels to skip when extracting files.
- `mode_mode: ModeMode = .executable_bit_only`
  How to handle the "mode" property of files from within the tar file.
- `exclude_empty_directories: bool = false`
  Prevents creation of empty directories.
- `diagnostics: ?*Diagnostics = null`
  Collects error messages during unpacking

### Types

#### `ModeMode`


### `FileKind`

Type of the file returned by iterator `next` method.

### Fields

- `directory`
  
- `sym_link`
  
- `file`
  

### `Iterator`

Iterator over entries in the tar file represented by reader.

### Fields

- `reader: *Io.Reader`
  
- `diagnostics: ?*Diagnostics = null`
  
- `header_buffer: [Header.SIZE]u8 = undefined`
  
- `file_name_buffer: []u8`
  
- `link_name_buffer: []u8`
  
- `padding: usize = 0`
  
- `unread_file_bytes: u64 = 0`
  

### Types

#### `Options`

Options for iterator.
Buffers should be provided by the caller.

#### `File`


### Functions

#### `init`

```zig
pub fn init(reader: *Io.Reader, options: Options) Iterator
```

Iterates over files in tar archive.
`next` returns each file in tar archive.

#### `next`

```zig
pub fn next(self: *Iterator) !?File
```

Iterates through the tar archive as if it is a series of files.
Internally, the tar format often uses entries (header with optional
content) to add meta data that describes the next file. These
entries should not normally be visible to the outside. As such, this
loop iterates through one or more entries until it collects a all
file attributes.

#### `streamRemaining`

```zig
pub fn streamRemaining(it: *Iterator, file: File, w: *Io.Writer) Io.Reader.StreamError!void
```


### `PaxIterator`


### Fields

- `size: usize`
  
- `reader: *Io.Reader`
  

### Functions

#### `next`

```zig
pub fn next(self: *Self) !?Attribute
```


## Functions

### `extract`

```zig
pub fn extract(io: Io, dir: Io.Dir, reader: *Io.Reader, options: ExtractOptions) !void
```

Ingests tar file from `reader`, populating file contents within `dir`. If
any file would be extracted outside of `dir`, an error is return instead.

## Constants & Variables

- **`Writer`**: 
- **`PipeOptions`**: Deprecated, renamed to `ExtractOptions`.
- **`pipeToFileSystem`**: Deprecated, renamed to `extract`.

