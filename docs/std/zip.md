# `std.zip`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/zip.zig`  
> [← Back to Standard Library Index](README.md)

The .ZIP File Format Specification is found here:
   https://pkwaredownloads.blob.core.windows.net/pem/APPNOTE.txt

Note that this file uses the abbreviation "cd" for "central directory"

## Types

### `CompressionMethod`


### Fields

- `store = 0`
  
- `deflate = 8`
  
- `_`
  

### `ExtraHeader`


### Fields

- `zip64_info = 0x1`
  
- `_`
  

### `LocalFileHeader`


### Fields

- `signature: [4]u8 align(1)`
  
- `version_needed_to_extract: u16 align(1)`
  
- `flags: GeneralPurposeFlags align(1)`
  
- `compression_method: CompressionMethod align(1)`
  
- `last_modification_time: u16 align(1)`
  
- `last_modification_date: u16 align(1)`
  
- `crc32: u32 align(1)`
  
- `compressed_size: u32 align(1)`
  
- `uncompressed_size: u32 align(1)`
  
- `filename_len: u16 align(1)`
  
- `extra_len: u16 align(1)`
  

### `CentralDirectoryFileHeader`


### Fields

- `signature: [4]u8 align(1)`
  
- `version_made_by: u16 align(1)`
  
- `version_needed_to_extract: u16 align(1)`
  
- `flags: GeneralPurposeFlags align(1)`
  
- `compression_method: CompressionMethod align(1)`
  
- `last_modification_time: u16 align(1)`
  
- `last_modification_date: u16 align(1)`
  
- `crc32: u32 align(1)`
  
- `compressed_size: u32 align(1)`
  
- `uncompressed_size: u32 align(1)`
  
- `filename_len: u16 align(1)`
  
- `extra_len: u16 align(1)`
  
- `comment_len: u16 align(1)`
  
- `disk_number: u16 align(1)`
  
- `internal_file_attributes: u16 align(1)`
  
- `external_file_attributes: u32 align(1)`
  
- `local_file_header_offset: u32 align(1)`
  

### `EndRecord64`


### Fields

- `signature: [4]u8 align(1)`
  
- `end_record_size: u64 align(1)`
  
- `version_made_by: u16 align(1)`
  
- `version_needed_to_extract: u16 align(1)`
  
- `disk_number: u32 align(1)`
  
- `central_directory_disk_number: u32 align(1)`
  
- `record_count_disk: u64 align(1)`
  
- `record_count_total: u64 align(1)`
  
- `central_directory_size: u64 align(1)`
  
- `central_directory_offset: u64 align(1)`
  

### `EndLocator64`


### Fields

- `signature: [4]u8 align(1)`
  
- `zip64_disk_count: u32 align(1)`
  
- `record_file_offset: u64 align(1)`
  
- `total_disk_count: u32 align(1)`
  

### `EndRecord`


### Fields

- `signature: [4]u8 align(1)`
  
- `disk_number: u16 align(1)`
  
- `central_directory_disk_number: u16 align(1)`
  
- `record_count_disk: u16 align(1)`
  
- `record_count_total: u16 align(1)`
  
- `central_directory_size: u32 align(1)`
  
- `central_directory_offset: u32 align(1)`
  
- `comment_len: u16 align(1)`
  

### Functions

#### `need_zip64`

```zig
pub fn need_zip64(self: EndRecord) bool
```


#### `findBuffer`

```zig
pub fn findBuffer(buffer: []const u8) FindBufferError!EndRecord
```

TODO audit this logic

#### `findFile`

```zig
pub fn findFile(fr: *File.Reader) FindFileError!EndRecord
```


### Error Sets

- **`FindBufferError`**
  
- **`FindFileError`**
  

### `Iterator`


### Fields

- `input: *File.Reader`
  
- `cd_record_count: u64`
  
- `cd_zip_offset: u64`
  
- `cd_size: u64`
  
- `cd_record_index: u64 = 0`
  
- `cd_record_offset: u64 = 0`
  

### Types

#### `Entry`


### Functions

#### `init`

```zig
pub fn init(input: *File.Reader) !Iterator
```


#### `next`

```zig
pub fn next(self: *Iterator) !?Entry
```


### `Diagnostics`


### Fields

- `allocator: std.mem.Allocator`
  
- `root_dir: []const u8 = ""`
  The common root directory for all extracted files if there is one.
- `saw_first_file: bool = false`
  

### Functions

#### `deinit`

```zig
pub fn deinit(self: *Diagnostics) void
```


#### `nextFilename`

```zig
pub fn nextFilename(self: *Diagnostics, name: []const u8) error{OutOfMemory}!void
```


### `ExtractOptions`


### Fields

- `allow_backslashes: bool = false`
  Allow filenames within the zip to use backslashes.  Back slashes are normalized
  to forward slashes before forwarding them to platform APIs.
- `diagnostics: ?*Diagnostics = null`
  
- `verify_checksums: bool = false`
  

## Functions

### `extract`

```zig
pub fn extract(dest: Io.Dir, fr: *File.Reader, options: ExtractOptions) !void
```

Extract the zipped files to the given `dest` directory.

## Constants & Variables

- **`central_file_header_sig`**: 
- **`local_file_header_sig`**: 
- **`end_record_sig`**: 
- **`end_record64_sig`**: 
- **`end_locator64_sig`**: 

