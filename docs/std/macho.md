# `std.macho`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/macho.zig`  
> [← Back to Standard Library Index](README.md)

## Types

### `cpu_type_t`


### `cpu_subtype_t`


### `vm_prot_t`


### Fields

- `READ: bool = false`
  
- `WRITE: bool = false`
  
- `EXEC: bool = false`
  
- `_: u1 = 0`
  
- `COPY: bool = false`
  When a caller finds that they cannot obtain write permission on a
  mapped entry, the following flag can be used. The entry will be
  made "needs copy" effectively copying the object (using COW),
  and write permission will be added to the maximum protections for
  the associated entry.
- `__: u27 = 0`
  

### `mach_header`


### Fields

- `magic: u32`
  
- `cputype: cpu_type_t`
  
- `cpusubtype: cpu_subtype_t`
  
- `filetype: u32`
  
- `ncmds: u32`
  
- `sizeofcmds: u32`
  
- `flags: u32`
  

### `mach_header_64`


### Fields

- `magic: u32 = MH_MAGIC_64`
  
- `cputype: cpu_type_t = 0`
  
- `cpusubtype: cpu_subtype_t = 0`
  
- `filetype: u32 = 0`
  
- `ncmds: u32 = 0`
  
- `sizeofcmds: u32 = 0`
  
- `flags: u32 = 0`
  
- `reserved: u32 = 0`
  

### `fat_header`


### Fields

- `magic: u32`
  
- `nfat_arch: u32`
  

### `fat_arch`


### Fields

- `cputype: cpu_type_t`
  
- `cpusubtype: cpu_subtype_t`
  
- `offset: u32`
  
- `size: u32`
  
- `@"align": u32`
  

### `load_command`


### Fields

- `cmd: LC`
  
- `cmdsize: u32`
  

### `uuid_command`

The uuid load command contains a single 128-bit unique random number that
identifies an object produced by the static link editor.

### Fields

- `cmd: LC = .UUID`
  LC_UUID
- `cmdsize: u32 = @sizeOf(uuid_command)`
  sizeof(struct uuid_command)
- `uuid: [16]u8 = undefined`
  the 128-bit uuid

### `version_min_command`

The version_min_command contains the min OS version on which this
binary was built to run.

### Fields

- `cmd: LC`
  LC_VERSION_MIN_MACOSX or LC_VERSION_MIN_IPHONEOS or LC_VERSION_MIN_WATCHOS or LC_VERSION_MIN_TVOS
- `cmdsize: u32 = @sizeOf(version_min_command)`
  sizeof(struct version_min_command)
- `version: u32`
  X.Y.Z is encoded in nibbles xxxx.yy.zz
- `sdk: u32`
  X.Y.Z is encoded in nibbles xxxx.yy.zz

### `source_version_command`

The source_version_command is an optional load command containing
the version of the sources used to build the binary.

### Fields

- `cmd: LC = .SOURCE_VERSION`
  LC_SOURCE_VERSION
- `cmdsize: u32 = @sizeOf(source_version_command)`
  sizeof(source_version_command)
- `version: u64`
  A.B.C.D.E packed as a24.b10.c10.d10.e10

### `build_version_command`

The build_version_command contains the min OS version on which this
binary was built to run for its platform. The list of known platforms and
tool values following it.

### Fields

- `cmd: LC = .BUILD_VERSION`
  LC_BUILD_VERSION
- `cmdsize: u32`
  sizeof(struct build_version_command) plus
  ntools * sizeof(struct build_version_command)
- `platform: PLATFORM`
  platform
- `minos: u32`
  X.Y.Z is encoded in nibbles xxxx.yy.zz
- `sdk: u32`
  X.Y.Z is encoded in nibbles xxxx.yy.zz
- `ntools: u32`
  number of tool entries following this

### `build_tool_version`


### Fields

- `tool: TOOL`
  enum for the tool
- `version: u32`
  version number of the tool

### `PLATFORM`


### Fields

- `UNKNOWN = 0`
  
- `ANY = 0xffffffff`
  
- `MACOS = 1`
  
- `IOS = 2`
  
- `TVOS = 3`
  
- `WATCHOS = 4`
  
- `BRIDGEOS = 5`
  
- `MACCATALYST = 6`
  
- `IOSSIMULATOR = 7`
  
- `TVOSSIMULATOR = 8`
  
- `WATCHOSSIMULATOR = 9`
  
- `DRIVERKIT = 10`
  
- `VISIONOS = 11`
  
- `VISIONOSSIMULATOR = 12`
  
- `_`
  

### `TOOL`


### Fields

- `CLANG = 0x1`
  
- `SWIFT = 0x2`
  
- `LD = 0x3`
  
- `LLD = 0x4`
  
- `ZIG = 0x5`
  
- `_`
  

### `entry_point_command`

The entry_point_command is a replacement for thread_command.
It is used for main executables to specify the location (file offset)
of main(). If -stack_size was used at link time, the stacksize
field will contain the stack size needed for the main thread.

### Fields

- `cmd: LC = .MAIN`
  LC_MAIN only used in MH_EXECUTE filetypes
- `cmdsize: u32 = @sizeOf(entry_point_command)`
  sizeof(struct entry_point_command)
- `entryoff: u64 = 0`
  file (__TEXT) offset of main()
- `stacksize: u64 = 0`
  if not zero, initial stack size

### `symtab_command`

The symtab_command contains the offsets and sizes of the link-edit 4.3BSD
"stab" style symbol table information as described in the header files
<nlist.h> and <stab.h>.

### Fields

- `cmd: LC = .SYMTAB`
  LC_SYMTAB
- `cmdsize: u32 = @sizeOf(symtab_command)`
  sizeof(struct symtab_command)
- `symoff: u32 = 0`
  symbol table offset
- `nsyms: u32 = 0`
  number of symbol table entries
- `stroff: u32 = 0`
  string table offset
- `strsize: u32 = 0`
  string table size in bytes

### `dysymtab_command`

This is the second set of the symbolic information which is used to support
the data structures for the dynamically link editor.

The original set of symbolic information in the symtab_command which contains
the symbol and string tables must also be present when this load command is
present.  When this load command is present the symbol table is organized
into three groups of symbols:
 local symbols (static and debugging symbols) - grouped by module
 defined external symbols - grouped by module (sorted by name if not lib)
 undefined external symbols (sorted by name if MH_BINDATLOAD is not set,
 and in order the were seen by the static linker if MH_BINDATLOAD is set)
In this load command there are offsets and counts to each of the three groups
of symbols.

This load command contains a the offsets and sizes of the following new
symbolic information tables:
 table of contents
 module table
 reference symbol table
 indirect symbol table
The first three tables above (the table of contents, module table and
reference symbol table) are only present if the file is a dynamically linked
shared library.  For executable and object modules, which are files
containing only one module, the information that would be in these three
tables is determined as follows:
 table of contents - the defined external symbols are sorted by name
 module table - the file contains only one module so everything in the file
 is part of the module.
 reference symbol table - is the defined and undefined external symbols

For dynamically linked shared library files this load command also contains
offsets and sizes to the pool of relocation entries for all sections
separated into two groups:
 external relocation entries
 local relocation entries
For executable and object modules the relocation entries continue to hang
off the section structures.

### Fields

- `cmd: LC = .DYSYMTAB`
  LC_DYSYMTAB
- `cmdsize: u32 = @sizeOf(dysymtab_command)`
  sizeof(struct dysymtab_command)
- `ilocalsym: u32 = 0`
  index of local symbols
- `nlocalsym: u32 = 0`
  number of local symbols
- `iextdefsym: u32 = 0`
  index to externally defined symbols
- `nextdefsym: u32 = 0`
  number of externally defined symbols
- `iundefsym: u32 = 0`
  index to undefined symbols
- `nundefsym: u32 = 0`
  number of undefined symbols
- `tocoff: u32 = 0`
  file offset to table of contents
- `ntoc: u32 = 0`
  number of entries in table of contents
- `modtaboff: u32 = 0`
  file offset to module table
- `nmodtab: u32 = 0`
  number of module table entries
- `extrefsymoff: u32 = 0`
  offset to referenced symbol table
- `nextrefsyms: u32 = 0`
  number of referenced symbol table entries
- `indirectsymoff: u32 = 0`
  file offset to the indirect symbol table
- `nindirectsyms: u32 = 0`
  number of indirect symbol table entries
- `extreloff: u32 = 0`
  offset to external relocation entries
- `nextrel: u32 = 0`
  number of external relocation entries
- `locreloff: u32 = 0`
  offset to local relocation entries
- `nlocrel: u32 = 0`
  number of local relocation entries

### `linkedit_data_command`

The linkedit_data_command contains the offsets and sizes of a blob
of data in the __LINKEDIT segment.

### Fields

- `cmd: LC`
  LC_CODE_SIGNATURE, LC_SEGMENT_SPLIT_INFO, LC_FUNCTION_STARTS, LC_DATA_IN_CODE, LC_DYLIB_CODE_SIGN_DRS or LC_LINKER_OPTIMIZATION_HINT.
- `cmdsize: u32 = @sizeOf(linkedit_data_command)`
  sizeof(struct linkedit_data_command)
- `dataoff: u32 = 0`
  file offset of data in __LINKEDIT segment
- `datasize: u32 = 0`
  file size of data in __LINKEDIT segment

### `dyld_info_command`

The dyld_info_command contains the file offsets and sizes of
the new compressed form of the information dyld needs to
load the image.  This information is used by dyld on Mac OS X
10.6 and later.  All information pointed to by this command
is encoded using byte streams, so no endian swapping is needed
to interpret it.

### Fields

- `cmd: LC = .DYLD_INFO_ONLY`
  LC_DYLD_INFO or LC_DYLD_INFO_ONLY
- `cmdsize: u32 = @sizeOf(dyld_info_command)`
  sizeof(struct dyld_info_command)
- `rebase_off: u32 = 0`
  file offset to rebase info
- `rebase_size: u32 = 0`
  size of rebase info
- `bind_off: u32 = 0`
  file offset to binding info
- `bind_size: u32 = 0`
  size of binding info
- `weak_bind_off: u32 = 0`
  file offset to weak binding info
- `weak_bind_size: u32 = 0`
  size of weak binding info
- `lazy_bind_off: u32 = 0`
  file offset to lazy binding info
- `lazy_bind_size: u32 = 0`
  size of lazy binding info
- `export_off: u32 = 0`
  file offset to lazy binding info
- `export_size: u32 = 0`
  size of lazy binding info

### `dylinker_command`

A program that uses a dynamic linker contains a dylinker_command to identify
the name of the dynamic linker (LC_LOAD_DYLINKER). And a dynamic linker
contains a dylinker_command to identify the dynamic linker (LC_ID_DYLINKER).
A file can have at most one of these.
This struct is also used for the LC_DYLD_ENVIRONMENT load command and contains
string for dyld to treat like an environment variable.

### Fields

- `cmd: LC`
  LC_ID_DYLINKER, LC_LOAD_DYLINKER, or LC_DYLD_ENVIRONMENT
- `cmdsize: u32`
  includes pathname string
- `name: u32`
  A variable length string in a load command is represented by an lc_str
  union.  The strings are stored just after the load command structure and
  the offset is from the start of the load command structure.  The size
  of the string is reflected in the cmdsize field of the load command.
  Once again any padded bytes to bring the cmdsize field to a multiple
  of 4 bytes must be zero.

### `dylib_command`

A dynamically linked shared library (filetype == MH_DYLIB in the mach header)
contains a dylib_command (cmd == LC_ID_DYLIB) to identify the library.
An object that uses a dynamically linked shared library also contains a
dylib_command (cmd == LC_LOAD_DYLIB, LC_LOAD_WEAK_DYLIB, or
LC_REEXPORT_DYLIB) for each library it uses.

### Fields

- `cmd: LC`
  LC_ID_DYLIB, LC_LOAD_WEAK_DYLIB, LC_LOAD_DYLIB, LC_REEXPORT_DYLIB
- `cmdsize: u32`
  includes pathname string
- `dylib: dylib`
  the library identification

### `dylib`

Dynamically linked shared libraries are identified by two things.  The
pathname (the name of the library as found for execution), and the
compatibility version number.  The pathname must match and the compatibility
number in the user of the library must be greater than or equal to the
library being used.  The time stamp is used to record the time a library was
built and copied into user so it can be use to determined if the library used
at runtime is exactly the same as used to build the program.

### Fields

- `name: u32`
  library's pathname (offset pointing at the end of dylib_command)
- `timestamp: u32`
  library's build timestamp
- `current_version: u32`
  library's current version number
- `compatibility_version: u32`
  library's compatibility version number

### `rpath_command`

The rpath_command contains a path which at runtime should be added to the current
run path used to find @rpath prefixed dylibs.

### Fields

- `cmd: LC = .RPATH`
  LC_RPATH
- `cmdsize: u32`
  includes string
- `path: u32`
  path to add to run path

### `encryption_info_command`


### Fields

- `cmd: LC = .ENCRYPTION_INFO`
  
- `cmdsize: u32 = @sizeOf(encryption_info_command)`
  
- `cryptoff: u32`
  
- `cryptsize: u32`
  
- `cryptid: u32 = 0`
  

### `encryption_info_command_64`


### Fields

- `cmd: LC = .ENCRYPTION_INFO_64`
  
- `cmdsize: u32 = @sizeOf(encryption_info_command_64)`
  
- `cryptoff: u32`
  
- `cryptsize: u32`
  
- `cryptid: u32 = 0`
  
- `_pad: u32 = 0`
  

### `segment_command`

The segment load command indicates that a part of this file is to be
mapped into the task's address space.  The size of this segment in memory,
vmsize, maybe equal to or larger than the amount to map from this file,
filesize.  The file is mapped starting at fileoff to the beginning of
the segment in memory, vmaddr.  The rest of the memory of the segment,
if any, is allocated zero fill on demand.  The segment's maximum virtual
memory protection and initial virtual memory protection are specified
by the maxprot and initprot fields.  If the segment has sections then the
section structures directly follow the segment command and their size is
reflected in cmdsize.

### Fields

- `cmd: LC = .SEGMENT`
  LC_SEGMENT
- `cmdsize: u32`
  includes sizeof section structs
- `segname: [16]u8`
  segment name
- `vmaddr: u32`
  memory address of this segment
- `vmsize: u32`
  memory size of this segment
- `fileoff: u32`
  file offset of this segment
- `filesize: u32`
  amount to map from the file
- `maxprot: vm_prot_t`
  maximum VM protection
- `initprot: vm_prot_t`
  initial VM protection
- `nsects: u32`
  number of sections in segment
- `flags: u32`
  

### `segment_command_64`

The 64-bit segment load command indicates that a part of this file is to be
mapped into a 64-bit task's address space.  If the 64-bit segment has
sections then section_64 structures directly follow the 64-bit segment
command and their size is reflected in cmdsize.

### Fields

- `cmd: LC = .SEGMENT_64`
  LC_SEGMENT_64
- `cmdsize: u32`
  includes sizeof section_64 structs
- `segname: [16]u8`
  segment name
- `vmaddr: u64 = 0`
  memory address of this segment
- `vmsize: u64 = 0`
  memory size of this segment
- `fileoff: u64 = 0`
  file offset of this segment
- `filesize: u64 = 0`
  amount to map from the file
- `maxprot: vm_prot_t = .{}`
  maximum VM protection
- `initprot: vm_prot_t = .{}`
  initial VM protection
- `nsects: u32 = 0`
  number of sections in segment
- `flags: u32 = 0`
  

### Functions

#### `segName`

```zig
pub fn segName(seg: *const segment_command_64) []const u8
```


#### `isWriteable`

```zig
pub fn isWriteable(seg: segment_command_64) bool
```


### `section`

A segment is made up of zero or more sections.  Non-MH_OBJECT files have
all of their segments with the proper sections in each, and padded to the
specified segment alignment when produced by the link editor.  The first
segment of a MH_EXECUTE and MH_FVMLIB format file contains the mach_header
and load commands of the object file before its first section.  The zero
fill sections are always last in their segment (in all formats).  This
allows the zeroed segment padding to be mapped into memory where zero fill
sections might be. The gigabyte zero fill sections, those with the section
type S_GB_ZEROFILL, can only be in a segment with sections of this type.
These segments are then placed after all other segments.

The MH_OBJECT format has all of its sections in one segment for
compactness.  There is no padding to a specified segment boundary and the
mach_header and load commands are not part of the segment.

Sections with the same section name, sectname, going into the same segment,
segname, are combined by the link editor.  The resulting section is aligned
to the maximum alignment of the combined sections and is the new section's
alignment.  The combined sections are aligned to their original alignment in
the combined section.  Any padded bytes to get the specified alignment are
zeroed.

The format of the relocation entries referenced by the reloff and nreloc
fields of the section structure for mach object files is described in the
header file <reloc.h>.

### Fields

- `sectname: [16]u8`
  name of this section
- `segname: [16]u8`
  segment this section goes in
- `addr: u32`
  memory address of this section
- `size: u32`
  size in bytes of this section
- `offset: u32`
  file offset of this section
- `@"align": u32`
  section alignment (power of 2)
- `reloff: u32`
  file offset of relocation entries
- `nreloc: u32`
  number of relocation entries
- `flags: u32`
  flags (section type and attributes
- `reserved1: u32`
  reserved (for offset or index)
- `reserved2: u32`
  reserved (for count or sizeof)

### `section_64`


### Fields

- `sectname: [16]u8`
  name of this section
- `segname: [16]u8`
  segment this section goes in
- `addr: u64 = 0`
  memory address of this section
- `size: u64 = 0`
  size in bytes of this section
- `offset: u32 = 0`
  file offset of this section
- `@"align": u32 = 0`
  section alignment (power of 2)
- `reloff: u32 = 0`
  file offset of relocation entries
- `nreloc: u32 = 0`
  number of relocation entries
- `flags: u32 = S_REGULAR`
  flags (section type and attributes
- `reserved1: u32 = 0`
  reserved (for offset or index)
- `reserved2: u32 = 0`
  reserved (for count or sizeof)
- `reserved3: u32 = 0`
  reserved

### Functions

#### `sectName`

```zig
pub fn sectName(sect: *const section_64) []const u8
```


#### `segName`

```zig
pub fn segName(sect: *const section_64) []const u8
```


#### `@"type"`

```zig
pub fn @"type"(sect: section_64) u8
```


#### `attrs`

```zig
pub fn attrs(sect: section_64) u32
```


#### `isCode`

```zig
pub fn isCode(sect: section_64) bool
```


#### `isZerofill`

```zig
pub fn isZerofill(sect: section_64) bool
```


#### `isSymbolStubs`

```zig
pub fn isSymbolStubs(sect: section_64) bool
```


#### `isDebug`

```zig
pub fn isDebug(sect: section_64) bool
```


#### `isDontDeadStrip`

```zig
pub fn isDontDeadStrip(sect: section_64) bool
```


#### `isDontDeadStripIfReferencesLive`

```zig
pub fn isDontDeadStripIfReferencesLive(sect: section_64) bool
```


### `nlist`


### Fields

- `n_strx: u32`
  
- `n_type: u8`
  
- `n_sect: u8`
  
- `n_desc: i16`
  
- `n_value: u32`
  

### `nlist_64`


### Fields

- `n_strx: u32`
  
- `n_type: packed union(u8) { bits: packed struct(u8) { ext: bool, type: enum(u3) { undf = 0, abs = 1, sect = 7, pbud = 6, indr = 5, _, }, pext: bool, is_stab: u3, }, stab: enum(u8) { gsym = N_GSYM, fname = N_FNAME, fun = N_FUN, stsym = N_STSYM, lcsym = N_LCSYM, bnsym = N_BNSYM, ast = N_AST, opt = N_OPT, rsym = N_RSYM, sline = N_SLINE, ensym = N_ENSYM, ssym = N_SSYM, so = N_SO, oso = N_OSO, lsym = N_LSYM, bincl = N_BINCL, sol = N_SOL, params = N_PARAMS, version = N_VERSION, olevel = N_OLEVEL, psym = N_PSYM, eincl = N_EINCL, entry = N_ENTRY, lbrac = N_LBRAC, excl = N_EXCL, rbrac = N_RBRAC, bcomm = N_BCOMM, ecomm = N_ECOMM, ecoml = N_ECOML, leng = N_LENG, _, }, }`
  
- `n_sect: u8`
  
- `n_desc: packed struct(u16) { _pad0: u3 = 0, arm_thumb_def: bool, referenced_dynamically: bool, discarded_or_no_dead_strip: bool, weak_ref: bool, weak_def_or_ref_to_weak: bool, symbol_resolver: bool, alt_entry: bool, _pad2: u6 = 0, }`
  
- `n_value: u64`
  

### Functions

#### `tentative`

```zig
pub fn tentative(sym: nlist_64) bool
```


### `relocation_info`

Format of a relocation entry of a Mach-O file.  Modified from the 4.3BSD
format.  The modifications from the original format were changing the value
of the r_symbolnum field for "local" (r_extern == 0) relocation entries.
This modification is required to support symbols in an arbitrary number of
sections not just the three sections (text, data and bss) in a 4.3BSD file.
Also the last 4 bits have had the r_type tag added to them.

### Fields

- `r_address: i32`
  offset in the section to what is being relocated
- `r_symbolnum: u24`
  symbol index if r_extern == 1 or section ordinal if r_extern == 0
- `r_pcrel: u1`
  was relocated pc relative already
- `r_length: u2`
  0=byte, 1=word, 2=long, 3=quad
- `r_extern: u1`
  does not include value of sym referenced
- `r_type: u4`
  if not 0, machine specific relocation type

### `LC`


### Fields

- `NONE = 0x0`
  No load command - invalid
- `SEGMENT = 0x1`
  segment of this file to be mapped
- `SYMTAB = 0x2`
  link-edit stab symbol table info
- `SYMSEG = 0x3`
  link-edit gdb symbol table info (obsolete)
- `THREAD = 0x4`
  thread
- `UNIXTHREAD = 0x5`
  unix thread (includes a stack)
- `LOADFVMLIB = 0x6`
  load a specified fixed VM shared library
- `IDFVMLIB = 0x7`
  fixed VM shared library identification
- `IDENT = 0x8`
  object identification info (obsolete)
- `FVMFILE = 0x9`
  fixed VM file inclusion (internal use)
- `PREPAGE = 0xa`
  prepage command (internal use)
- `DYSYMTAB = 0xb`
  dynamic link-edit symbol table info
- `LOAD_DYLIB = 0xc`
  load a dynamically linked shared library
- `ID_DYLIB = 0xd`
  dynamically linked shared lib ident
- `LOAD_DYLINKER = 0xe`
  load a dynamic linker
- `ID_DYLINKER = 0xf`
  dynamic linker identification
- `PREBOUND_DYLIB = 0x10`
  modules prebound for a dynamically
- `ROUTINES = 0x11`
  image routines
- `SUB_FRAMEWORK = 0x12`
  sub framework
- `SUB_UMBRELLA = 0x13`
  sub umbrella
- `SUB_CLIENT = 0x14`
  sub client
- `SUB_LIBRARY = 0x15`
  sub library
- `TWOLEVEL_HINTS = 0x16`
  two-level namespace lookup hints
- `PREBIND_CKSUM = 0x17`
  prebind checksum
- `LOAD_WEAK_DYLIB = 0x18 | LC_REQ_DYLD`
  load a dynamically linked shared library that is allowed to be missing
  (all symbols are weak imported).
- `SEGMENT_64 = 0x19`
  64-bit segment of this file to be mapped
- `ROUTINES_64 = 0x1a`
  64-bit image routines
- `UUID = 0x1b`
  the uuid
- `RPATH = 0x1c | LC_REQ_DYLD`
  runpath additions
- `CODE_SIGNATURE = 0x1d`
  local of code signature
- `SEGMENT_SPLIT_INFO = 0x1e`
  local of info to split segments
- `REEXPORT_DYLIB = 0x1f | LC_REQ_DYLD`
  load and re-export dylib
- `LAZY_LOAD_DYLIB = 0x20`
  delay load of dylib until first use
- `ENCRYPTION_INFO = 0x21`
  encrypted segment information
- `DYLD_INFO = 0x22`
  compressed dyld information
- `DYLD_INFO_ONLY = 0x22 | LC_REQ_DYLD`
  compressed dyld information only
- `LOAD_UPWARD_DYLIB = 0x23 | LC_REQ_DYLD`
  load upward dylib
- `VERSION_MIN_MACOSX = 0x24`
  build for MacOSX min OS version
- `VERSION_MIN_IPHONEOS = 0x25`
  build for iPhoneOS min OS version
- `FUNCTION_STARTS = 0x26`
  compressed table of function start addresses
- `DYLD_ENVIRONMENT = 0x27`
  string for dyld to treat like environment variable
- `MAIN = 0x28 | LC_REQ_DYLD`
  replacement for LC_UNIXTHREAD
- `DATA_IN_CODE = 0x29`
  table of non-instructions in __text
- `SOURCE_VERSION = 0x2A`
  source version used to build binary
- `DYLIB_CODE_SIGN_DRS = 0x2B`
  Code signing DRs copied from linked dylibs
- `ENCRYPTION_INFO_64 = 0x2C`
  64-bit encrypted segment information
- `LINKER_OPTION = 0x2D`
  linker options in MH_OBJECT files
- `LINKER_OPTIMIZATION_HINT = 0x2E`
  optimization hints in MH_OBJECT files
- `VERSION_MIN_TVOS = 0x2F`
  build for AppleTV min OS version
- `VERSION_MIN_WATCHOS = 0x30`
  build for Watch min OS version
- `NOTE = 0x31`
  arbitrary data included within a Mach-O file
- `BUILD_VERSION = 0x32`
  build for platform min OS version
- `DYLD_EXPORTS_TRIE = 0x33 | LC_REQ_DYLD`
  used with linkedit_data_command, payload is trie
- `DYLD_CHAINED_FIXUPS = 0x34 | LC_REQ_DYLD`
  used with linkedit_data_command
- `_`
  

### `reloc_type_x86_64`


### Fields

- `X86_64_RELOC_UNSIGNED = 0`
  for absolute addresses
- `X86_64_RELOC_SIGNED`
  for signed 32-bit displacement
- `X86_64_RELOC_BRANCH`
  a CALL/JMP instruction with 32-bit displacement
- `X86_64_RELOC_GOT_LOAD`
  a MOVQ load of a GOT entry
- `X86_64_RELOC_GOT`
  other GOT references
- `X86_64_RELOC_SUBTRACTOR`
  must be followed by a X86_64_RELOC_UNSIGNED
- `X86_64_RELOC_SIGNED_1`
  for signed 32-bit displacement with a -1 addend
- `X86_64_RELOC_SIGNED_2`
  for signed 32-bit displacement with a -2 addend
- `X86_64_RELOC_SIGNED_4`
  for signed 32-bit displacement with a -4 addend
- `X86_64_RELOC_TLV`
  for thread local variables

### `reloc_type_arm64`


### Fields

- `ARM64_RELOC_UNSIGNED = 0`
  For pointers.
- `ARM64_RELOC_SUBTRACTOR`
  Must be followed by a ARM64_RELOC_UNSIGNED.
- `ARM64_RELOC_BRANCH26`
  A B/BL instruction with 26-bit displacement.
- `ARM64_RELOC_PAGE21`
  Pc-rel distance to page of target.
- `ARM64_RELOC_PAGEOFF12`
  Offset within page, scaled by r_length.
- `ARM64_RELOC_GOT_LOAD_PAGE21`
  Pc-rel distance to page of GOT slot.
- `ARM64_RELOC_GOT_LOAD_PAGEOFF12`
  Offset within page of GOT slot, scaled by r_length.
- `ARM64_RELOC_POINTER_TO_GOT`
  For pointers to GOT slots.
- `ARM64_RELOC_TLVP_LOAD_PAGE21`
  Pc-rel distance to page of TLVP slot.
- `ARM64_RELOC_TLVP_LOAD_PAGEOFF12`
  Offset within page of TLVP slot, scaled by r_length.
- `ARM64_RELOC_ADDEND`
  Must be followed by PAGE21 or PAGEOFF12.

### `CodeDirectory`

This CodeDirectory is tailored specifically at version 0x20400.

### Fields

- `magic: u32`
  Magic number (CSMAGIC_CODEDIRECTORY)
- `length: u32`
  Total length of CodeDirectory blob
- `version: u32`
  Compatibility version
- `flags: u32`
  Setup and mode flags
- `hashOffset: u32`
  Offset of hash slot element at index zero
- `identOffset: u32`
  Offset of identifier string
- `nSpecialSlots: u32`
  Number of special hash slots
- `nCodeSlots: u32`
  Number of ordinary (code) hash slots
- `codeLimit: u32`
  Limit to main image signature range
- `hashSize: u8`
  Size of each hash in bytes
- `hashType: u8`
  Type of hash (cdHashType* constants)
- `platform: u8`
  Platform identifier; zero if not platform binary
- `pageSize: u8`
  log2(page size in bytes); 0 => infinite
- `spare2: u32`
  Unused (must be zero)
- `scatterOffset: u32`
  
- `teamOffset: u32`
  
- `spare3: u32`
  
- `codeLimit64: u64`
  
- `execSegBase: u64`
  Offset of executable segment
- `execSegLimit: u64`
  Limit of executable segment
- `execSegFlags: u64`
  Executable segment flags

### `BlobIndex`

Structure of an embedded-signature SuperBlob

### Fields

- `type: u32`
  Type of entry
- `offset: u32`
  Offset of entry

### `SuperBlob`

This structure is followed by GenericBlobs in no particular
order as indicated by offsets in index

### Fields

- `magic: u32`
  Magic number
- `length: u32`
  Total length of SuperBlob
- `count: u32`
  Number of index BlobIndex entries following this struct

### `GenericBlob`


### Fields

- `magic: u32`
  Magic number
- `length: u32`
  Total length of blob

### `data_in_code_entry`

The LC_DATA_IN_CODE load commands uses a linkedit_data_command
to point to an array of data_in_code_entry entries. Each entry
describes a range of data in a code section.

### Fields

- `offset: u32`
  From mach_header to start of data range.
- `length: u16`
  Number of bytes in data range.
- `kind: u16`
  A DICE_KIND value.

### `LoadCommandIterator`


### Fields

- `next_index: usize`
  
- `ncmds: usize`
  
- `r: std.Io.Reader`
  

### Types

#### `LoadCommand`


### Functions

#### `next`

```zig
pub fn next(it: *LoadCommandIterator) error{InvalidMachO}!?LoadCommand
```


#### `init`

```zig
pub fn init(hdr: *const mach_header_64, cmds_buf_overlong: []const u8) error{InvalidMachO}!LoadCommandIterator
```


### `compact_unwind_encoding_t`


### `compact_unwind_entry`


### Fields

- `rangeStart: u64`
  
- `rangeLength: u32`
  
- `compactUnwindEncoding: u32`
  
- `personalityFunction: u64`
  
- `lsda: u64`
  

### `unwind_info_section_header`


### Fields

- `version: u32 = UNWIND_SECTION_VERSION`
  UNWIND_SECTION_VERSION
- `commonEncodingsArraySectionOffset: u32`
  
- `commonEncodingsArrayCount: u32`
  
- `personalityArraySectionOffset: u32`
  
- `personalityArrayCount: u32`
  
- `indexSectionOffset: u32`
  
- `indexCount: u32`
  

### `unwind_info_section_header_index_entry`


### Fields

- `functionOffset: u32`
  
- `secondLevelPagesSectionOffset: u32`
  section offset to start of regular or compress page
- `lsdaIndexArraySectionOffset: u32`
  section offset to start of lsda_index array for this range

### `unwind_info_section_header_lsda_index_entry`


### Fields

- `functionOffset: u32`
  
- `lsdaOffset: u32`
  

### `unwind_info_regular_second_level_entry`


### Fields

- `functionOffset: u32`
  
- `encoding: compact_unwind_encoding_t`
  

### `UNWIND_SECOND_LEVEL`


### Fields

- `REGULAR = 2`
  
- `COMPRESSED = 3`
  
- `_`
  

### `unwind_info_regular_second_level_page_header`


### Fields

- `kind: UNWIND_SECOND_LEVEL = .REGULAR`
  UNWIND_SECOND_LEVEL_REGULAR
- `entryPageOffset: u16`
  
- `entryCount: u16`
  

### `unwind_info_compressed_second_level_page_header`


### Fields

- `kind: UNWIND_SECOND_LEVEL = .COMPRESSED`
  UNWIND_SECOND_LEVEL_COMPRESSED
- `entryPageOffset: u16`
  
- `entryCount: u16`
  
- `encodingsPageOffset: u16`
  
- `encodingsCount: u16`
  

### `UnwindInfoCompressedEntry`


### Fields

- `funcOffset: u24`
  
- `encodingIndex: u8`
  

### `UNWIND_X86_64_MODE`


### Fields

- `OLD = 0`
  
- `RBP_FRAME = 1`
  
- `STACK_IMMD = 2`
  
- `STACK_IND = 3`
  
- `DWARF = 4`
  

### `UNWIND_X86_64_REG`


### Fields

- `NONE = 0`
  
- `RBX = 1`
  
- `R12 = 2`
  
- `R13 = 3`
  
- `R14 = 4`
  
- `R15 = 5`
  
- `RBP = 6`
  

### `UNWIND_ARM64_MODE`


### Fields

- `OLD = 0`
  
- `FRAMELESS = 2`
  
- `DWARF = 3`
  
- `FRAME = 4`
  

### `CompactUnwindEncoding`


### Fields

- `value: packed union { x86_64: packed union { frame: packed struct(u24) { reg4: u3, reg3: u3, reg2: u3, reg1: u3, reg0: u3, unused: u1 = 0, frame_offset: u8, }, frameless: packed struct(u24) { stack_reg_permutation: u10, stack_reg_count: u3, stack: packed union { direct: packed struct(u11) { _: u3, stack_size: u8, }, indirect: packed struct(u11) { stack_adjust: u3, sub_offset: u8, }, }, }, dwarf: u24, }, arm64: packed union { frame: packed struct(u24) { x_reg_pairs: packed struct(u5) { x19_x20: u1, x21_x22: u1, x23_x24: u1, x25_x26: u1, x27_x28: u1, }, d_reg_pairs: packed struct(u4) { d8_d9: u1, d10_d11: u1, d12_d13: u1, d14_d15: u1, }, _: u15, }, frameless: packed struct(u24) { _: u12 = 0, stack_size: u12, }, dwarf: u24, }, }`
  
- `mode: packed union { x86_64: UNWIND_X86_64_MODE, arm64: UNWIND_ARM64_MODE, }`
  
- `personality_index: u2`
  
- `has_lsda: u1`
  
- `start: u1`
  

## Namespaces

- **`PROT`**: 

## Constants & Variables

- **`LC_REQ_DYLD`**: After MacOS X 10.1 when a new load command is added that is required to be
- **`MH_MAGIC`**: the mach magic number
- **`MH_CIGAM`**: NXSwapInt(MH_MAGIC)
- **`MH_MAGIC_64`**: the 64-bit mach magic number
- **`MH_CIGAM_64`**: NXSwapInt(MH_MAGIC_64)
- **`MH_OBJECT`**: relocatable object file
- **`MH_EXECUTE`**: demand paged executable file
- **`MH_FVMLIB`**: fixed VM shared library file
- **`MH_CORE`**: core file
- **`MH_PRELOAD`**: preloaded executable file
- **`MH_DYLIB`**: dynamically bound shared library
- **`MH_DYLINKER`**: dynamic link editor
- **`MH_BUNDLE`**: dynamically bound bundle file
- **`MH_DYLIB_STUB`**: shared library stub for static linking only, no section contents
- **`MH_DSYM`**: companion file with only debug sections
- **`MH_KEXT_BUNDLE`**: x86_64 kexts
- **`MH_NOUNDEFS`**: the object file has no undefined references
- **`MH_INCRLINK`**: the object file is the output of an incremental link against a base file and can't be link edited again
- **`MH_DYLDLINK`**: the object file is input for the dynamic linker and can't be statically link edited again
- **`MH_BINDATLOAD`**: the object file's undefined references are bound by the dynamic linker when loaded.
- **`MH_PREBOUND`**: the file has its dynamic undefined references prebound.
- **`MH_SPLIT_SEGS`**: the file has its read-only and read-write segments split
- **`MH_LAZY_INIT`**: the shared library init routine is to be run lazily via catching memory faults to its writeable segments (obsolete)
- **`MH_TWOLEVEL`**: the image is using two-level name space bindings
- **`MH_FORCE_FLAT`**: the executable is forcing all images to use flat name space bindings
- **`MH_NOMULTIDEFS`**: this umbrella guarantees no multiple definitions of symbols in its sub-images so the two-level namespace hints can always be used.
- **`MH_NOFIXPREBINDING`**: do not have dyld notify the prebinding agent about this executable
- **`MH_PREBINDABLE`**: the binary is not prebound but can have its prebinding redone. only used when MH_PREBOUND is not set.
- **`MH_ALLMODSBOUND`**: indicates that this binary binds to all two-level namespace modules of its dependent libraries. only used when MH_PREBINDABLE and MH_TWOLEVEL are both set.
- **`MH_SUBSECTIONS_VIA_SYMBOLS`**: safe to divide up the sections into sub-sections via symbols for dead code stripping
- **`MH_CANONICAL`**: the binary has been canonicalized via the unprebind operation
- **`MH_WEAK_DEFINES`**: the final linked image contains external weak symbols
- **`MH_BINDS_TO_WEAK`**: the final linked image uses weak symbols
- **`MH_ALLOW_STACK_EXECUTION`**: When this bit is set, all stacks in the task will be given stack execution privilege.  Only used in MH_EXECUTE filetypes.
- **`MH_ROOT_SAFE`**: When this bit is set, the binary declares it is safe for use in processes with uid zero
- **`MH_SETUID_SAFE`**: When this bit is set, the binary declares it is safe for use in processes when issetugid() is true
- **`MH_NO_REEXPORTED_DYLIBS`**: When this bit is set on a dylib, the static linker does not need to examine dependent dylibs to see if any are re-exported
- **`MH_PIE`**: When this bit is set, the OS will load the main executable at a random address.  Only used in MH_EXECUTE filetypes.
- **`MH_DEAD_STRIPPABLE_DYLIB`**: Only for use on dylibs.  When linking against a dylib that has this bit set, the static linker will automatically not create a LC_LOAD_DYLIB load command to the dylib if no symbols are being referenced from the dylib.
- **`MH_HAS_TLV_DESCRIPTORS`**: Contains a section of type S_THREAD_LOCAL_VARIABLES
- **`MH_NO_HEAP_EXECUTION`**: When this bit is set, the OS will run the main executable with a non-executable heap even on platforms (e.g. x86) that don't require it. Only used in MH_EXECUTE filetypes.
- **`MH_APP_EXTENSION_SAFE`**: The code was linked for use in an application extension.
- **`MH_NLIST_OUTOFSYNC_WITH_DYLDINFO`**: The external symbols listed in the nlist symbol table do not include all the symbols listed in the dyld info.
- **`MH_SIM_SUPPORT`**: Allow LC_MIN_VERSION_MACOS and LC_BUILD_VERSION load commands with the platforms macOS, iOSMac, iOSSimulator, tvOSSimulator and watchOSSimulator.
- **`MH_DYLIB_IN_CACHE`**: Only for use on dylibs. When this bit is set, the dylib is part of the dyld shared cache, rather than loose in the filesystem.
- **`FAT_MAGIC`**: the fat magic number
- **`FAT_CIGAM`**: NXSwapLong(FAT_MAGIC)
- **`FAT_MAGIC_64`**: the 64-bit fat magic number
- **`FAT_CIGAM_64`**: NXSwapLong(FAT_MAGIC_64)
- **`SG_HIGHVM`**: Segment flags
- **`SG_FVMLIB`**: This segment is the VM that is allocated by a fixed VM library, for overlap checking in
- **`SG_NORELOC`**: This segment has nothing that was relocated in it and nothing relocated to it, that is
- **`SG_PROTECTED_VERSION_1`**: This segment is protected.  If the segment starts at file offset 0, the
- **`SG_READ_ONLY`**: This segment is made read-only after fixups
- **`SECTION_TYPE`**: The flags field of a section structure is separated into two parts a section
- **`SECTION_ATTRIBUTES`**: 24 section attributes
- **`S_REGULAR`**: regular section
- **`S_ZEROFILL`**: zero fill on demand section
- **`S_CSTRING_LITERALS`**: section with only literal C string
- **`S_4BYTE_LITERALS`**: section with only 4 byte literals
- **`S_8BYTE_LITERALS`**: section with only 8 byte literals
- **`S_LITERAL_POINTERS`**: section with only pointers to
- **`N_STAB`**: if any of these bits set, a symbolic debugging entry
- **`N_PEXT`**: private external symbol bit
- **`N_TYPE`**: mask for the type bits
- **`N_EXT`**: external symbol bit, set for external symbols
- **`N_UNDF`**: symbol is undefined
- **`N_ABS`**: symbol is absolute
- **`N_SECT`**: symbol is defined in the section number given in n_sect
- **`N_PBUD`**: symbol is undefined  and the image is using a prebound
- **`N_INDR`**: symbol is defined to be the same as another symbol; the n_value
- **`N_GSYM`**: global symbol: name,,NO_SECT,type,0
- **`N_FNAME`**: procedure name (f77 kludge): name,,NO_SECT,0,0
- **`N_FUN`**: procedure: name,,n_sect,linenumber,address
- **`N_STSYM`**: static symbol: name,,n_sect,type,address
- **`N_LCSYM`**: .lcomm symbol: name,,n_sect,type,address
- **`N_BNSYM`**: begin nsect sym: 0,,n_sect,0,address
- **`N_AST`**: AST file path: name,,NO_SECT,0,0
- **`N_OPT`**: emitted with gcc2_compiled and in gcc source
- **`N_RSYM`**: register sym: name,,NO_SECT,type,register
- **`N_SLINE`**: src line: 0,,n_sect,linenumber,address
- **`N_ENSYM`**: end nsect sym: 0,,n_sect,0,address
- **`N_SSYM`**: structure elt: name,,NO_SECT,type,struct_offset
- **`N_SO`**: source file name: name,,n_sect,0,address
- **`N_OSO`**: object file name: name,,0,0,st_mtime
- **`N_LSYM`**: local sym: name,,NO_SECT,type,offset
- **`N_BINCL`**: include file beginning: name,,NO_SECT,0,sum
- **`N_SOL`**: #included file name: name,,n_sect,0,address
- **`N_PARAMS`**: compiler parameters: name,,NO_SECT,0,0
- **`N_VERSION`**: compiler version: name,,NO_SECT,0,0
- **`N_OLEVEL`**: compiler -O level: name,,NO_SECT,0,0
- **`N_PSYM`**: parameter: name,,NO_SECT,type,offset
- **`N_EINCL`**: include file end: name,,NO_SECT,0,0
- **`N_ENTRY`**: alternate entry: name,,n_sect,linenumber,address
- **`N_LBRAC`**: left bracket: 0,,NO_SECT,nesting level,address
- **`N_EXCL`**: deleted include file: name,,NO_SECT,0,sum
- **`N_RBRAC`**: right bracket: 0,,NO_SECT,nesting level,address
- **`N_BCOMM`**: begin common: name,,NO_SECT,0,0
- **`N_ECOMM`**: end common: name,,n_sect,0,0
- **`N_ECOML`**: end common (local name): 0,,n_sect,0,address
- **`N_LENG`**: second stab entry with length information
- **`S_NON_LAZY_SYMBOL_POINTERS`**: section with only non-lazy symbol pointers
- **`S_LAZY_SYMBOL_POINTERS`**: section with only lazy symbol pointers
- **`S_SYMBOL_STUBS`**: section with only symbol stubs, byte size of stub in the reserved2 field
- **`S_MOD_INIT_FUNC_POINTERS`**: section with only function pointers for initialization
- **`S_MOD_TERM_FUNC_POINTERS`**: section with only function pointers for termination
- **`S_COALESCED`**: section contains symbols that are to be coalesced
- **`S_GB_ZEROFILL`**: zero fill on demand section (that can be larger than 4 gigabytes)
- **`S_INTERPOSING`**: section with only pairs of function pointers for interposing
- **`S_16BYTE_LITERALS`**: section with only 16 byte literals
- **`S_DTRACE_DOF`**: section contains DTrace Object Format
- **`S_LAZY_DYLIB_SYMBOL_POINTERS`**: section with only lazy symbol pointers to lazy loaded dylibs
- **`S_ATTR_DEBUG`**: a debug section
- **`S_ATTR_PURE_INSTRUCTIONS`**: section contains only true machine instructions
- **`S_ATTR_NO_TOC`**: section contains coalesced symbols that are not to be in a ranlib
- **`S_ATTR_STRIP_STATIC_SYMS`**: ok to strip static symbols in this section in files with the
- **`S_ATTR_NO_DEAD_STRIP`**: no dead stripping
- **`S_ATTR_LIVE_SUPPORT`**: blocks are live if they reference live blocks
- **`S_ATTR_SELF_MODIFYING_CODE`**: used with x86 code stubs written on by dyld
- **`S_ATTR_SOME_INSTRUCTIONS`**: section contains some machine instructions
- **`S_ATTR_EXT_RELOC`**: section has external relocation entries
- **`S_ATTR_LOC_RELOC`**: section has local relocation entries
- **`S_THREAD_LOCAL_REGULAR`**: template of initial values for TLVs
- **`S_THREAD_LOCAL_ZEROFILL`**: template of initial values for TLVs
- **`S_THREAD_LOCAL_VARIABLES`**: TLV descriptors
- **`S_THREAD_LOCAL_VARIABLE_POINTERS`**: pointers to TLV descriptors
- **`S_THREAD_LOCAL_INIT_FUNCTION_POINTERS`**: functions to call to initialize TLV values
- **`S_INIT_FUNC_OFFSETS`**: 32-bit offsets to initializers
- **`CPU_TYPE_X86_64`**: CPU type targeting 64-bit Intel-based Macs
- **`CPU_TYPE_ARM64`**: CPU type targeting 64-bit ARM-based Macs
- **`CPU_SUBTYPE_X86_64_ALL`**: All Intel-based Macs
- **`CPU_SUBTYPE_ARM_ALL`**: All ARM-based Macs
- **`REBASE_TYPE_POINTER`**: 
- **`REBASE_TYPE_TEXT_ABSOLUTE32`**: 
- **`REBASE_TYPE_TEXT_PCREL32`**: 
- **`REBASE_OPCODE_MASK`**: 
- **`REBASE_IMMEDIATE_MASK`**: 
- **`REBASE_OPCODE_DONE`**: 
- **`REBASE_OPCODE_SET_TYPE_IMM`**: 
- **`REBASE_OPCODE_SET_SEGMENT_AND_OFFSET_ULEB`**: 
- **`REBASE_OPCODE_ADD_ADDR_ULEB`**: 
- **`REBASE_OPCODE_ADD_ADDR_IMM_SCALED`**: 
- **`REBASE_OPCODE_DO_REBASE_IMM_TIMES`**: 
- **`REBASE_OPCODE_DO_REBASE_ULEB_TIMES`**: 
- **`REBASE_OPCODE_DO_REBASE_ADD_ADDR_ULEB`**: 
- **`REBASE_OPCODE_DO_REBASE_ULEB_TIMES_SKIPPING_ULEB`**: 
- **`BIND_TYPE_POINTER`**: 
- **`BIND_TYPE_TEXT_ABSOLUTE32`**: 
- **`BIND_TYPE_TEXT_PCREL32`**: 
- **`BIND_SPECIAL_DYLIB_SELF`**: 
- **`BIND_SPECIAL_DYLIB_MAIN_EXECUTABLE`**: 
- **`BIND_SPECIAL_DYLIB_FLAT_LOOKUP`**: 
- **`BIND_SYMBOL_FLAGS_WEAK_IMPORT`**: 
- **`BIND_SYMBOL_FLAGS_NON_WEAK_DEFINITION`**: 
- **`BIND_OPCODE_MASK`**: 
- **`BIND_IMMEDIATE_MASK`**: 
- **`BIND_OPCODE_DONE`**: 
- **`BIND_OPCODE_SET_DYLIB_ORDINAL_IMM`**: 
- **`BIND_OPCODE_SET_DYLIB_ORDINAL_ULEB`**: 
- **`BIND_OPCODE_SET_DYLIB_SPECIAL_IMM`**: 
- **`BIND_OPCODE_SET_SYMBOL_TRAILING_FLAGS_IMM`**: 
- **`BIND_OPCODE_SET_TYPE_IMM`**: 
- **`BIND_OPCODE_SET_ADDEND_SLEB`**: 
- **`BIND_OPCODE_SET_SEGMENT_AND_OFFSET_ULEB`**: 
- **`BIND_OPCODE_ADD_ADDR_ULEB`**: 
- **`BIND_OPCODE_DO_BIND`**: 
- **`BIND_OPCODE_DO_BIND_ADD_ADDR_ULEB`**: 
- **`BIND_OPCODE_DO_BIND_ADD_ADDR_IMM_SCALED`**: 
- **`BIND_OPCODE_DO_BIND_ULEB_TIMES_SKIPPING_ULEB`**: 
- **`REFERENCE_FLAG_UNDEFINED_NON_LAZY`**: This symbol is a reference to an external non-lazy (data) symbol.
- **`REFERENCE_FLAG_UNDEFINED_LAZY`**: This symbol is a reference to an external lazy symbol—that is, to a function call.
- **`REFERENCE_FLAG_DEFINED`**: This symbol is defined in this module.
- **`REFERENCE_FLAG_PRIVATE_DEFINED`**: This symbol is defined in this module and is visible only to modules within this shared library.
- **`REFERENCE_FLAG_PRIVATE_UNDEFINED_NON_LAZY`**: This symbol is defined in another module in this file, is a non-lazy (data) symbol, and is visible
- **`REFERENCE_FLAG_PRIVATE_UNDEFINED_LAZY`**: This symbol is defined in another module in this file, is a lazy (function) symbol, and is visible
- **`REFERENCED_DYNAMICALLY`**: Must be set for any defined symbol that is referenced by dynamic-loader APIs (such as dlsym and
- **`N_NO_DEAD_STRIP`**: The N_NO_DEAD_STRIP bit of the n_desc field only ever appears in a
- **`N_DESC_DISCARDED`**: Used by the dynamic linker at runtime. Do not set this bit.
- **`N_WEAK_REF`**: Indicates that this symbol is a weak reference. If the dynamic linker cannot find a definition
- **`N_WEAK_DEF`**: Indicates that this symbol is a weak definition. If the static linker or the dynamic linker finds
- **`N_SYMBOL_RESOLVER`**: The N_SYMBOL_RESOLVER bit of the n_desc field indicates that the
- **`EXPORT_SYMBOL_FLAGS_KIND_MASK`**: 
- **`EXPORT_SYMBOL_FLAGS_KIND_REGULAR`**: 
- **`EXPORT_SYMBOL_FLAGS_KIND_THREAD_LOCAL`**: 
- **`EXPORT_SYMBOL_FLAGS_KIND_ABSOLUTE`**: 
- **`EXPORT_SYMBOL_FLAGS_WEAK_DEFINITION`**: 
- **`EXPORT_SYMBOL_FLAGS_REEXPORT`**: 
- **`EXPORT_SYMBOL_FLAGS_STUB_AND_RESOLVER`**: 
- **`INDIRECT_SYMBOL_LOCAL`**: 
- **`INDIRECT_SYMBOL_ABS`**: 
- **`CSMAGIC_REQUIREMENT`**: Single Requirement blob
- **`CSMAGIC_REQUIREMENTS`**: Requirements vector (internal requirements)
- **`CSMAGIC_CODEDIRECTORY`**: CodeDirectory blob
- **`CSMAGIC_EMBEDDED_SIGNATURE`**: embedded form of signature data
- **`CSMAGIC_EMBEDDED_SIGNATURE_OLD`**: XXX
- **`CSMAGIC_EMBEDDED_ENTITLEMENTS`**: Embedded entitlements
- **`CSMAGIC_EMBEDDED_DER_ENTITLEMENTS`**: Embedded DER encoded entitlements
- **`CSMAGIC_DETACHED_SIGNATURE`**: Multi-arch collection of embedded signatures
- **`CSMAGIC_BLOBWRAPPER`**: CMS Signature, among other things
- **`CS_SUPPORTSSCATTER`**: 
- **`CS_SUPPORTSTEAMID`**: 
- **`CS_SUPPORTSCODELIMIT64`**: 
- **`CS_SUPPORTSEXECSEG`**: 
- **`CSSLOT_CODEDIRECTORY`**: Slot index for CodeDirectory
- **`CSSLOT_INFOSLOT`**: 
- **`CSSLOT_REQUIREMENTS`**: 
- **`CSSLOT_RESOURCEDIR`**: 
- **`CSSLOT_APPLICATION`**: 
- **`CSSLOT_ENTITLEMENTS`**: 
- **`CSSLOT_DER_ENTITLEMENTS`**: 
- **`CSSLOT_ALTERNATE_CODEDIRECTORIES`**: first alternate CodeDirectory, if any
- **`CSSLOT_ALTERNATE_CODEDIRECTORY_MAX`**: Max number of alternate CD slots
- **`CSSLOT_ALTERNATE_CODEDIRECTORY_LIMIT`**: One past the last
- **`CSSLOT_SIGNATURESLOT`**: CMS Signature
- **`CSSLOT_IDENTIFICATIONSLOT`**: 
- **`CSSLOT_TICKETSLOT`**: 
- **`CSTYPE_INDEX_REQUIREMENTS`**: Compat with amfi
- **`CSTYPE_INDEX_ENTITLEMENTS`**: Compat with amfi
- **`CS_HASHTYPE_SHA1`**: 
- **`CS_HASHTYPE_SHA256`**: 
- **`CS_HASHTYPE_SHA256_TRUNCATED`**: 
- **`CS_HASHTYPE_SHA384`**: 
- **`CS_SHA1_LEN`**: 
- **`CS_SHA256_LEN`**: 
- **`CS_SHA256_TRUNCATED_LEN`**: 
- **`CS_CDHASH_LEN`**: Always - larger hashes are truncated
- **`CS_HASH_MAX_SIZE`**: Max size of the hash we'll support
- **`CS_SIGNER_TYPE_UNKNOWN`**: 
- **`CS_SIGNER_TYPE_LEGACYVPN`**: 
- **`CS_SIGNER_TYPE_MAC_APP_STORE`**: 
- **`CS_ADHOC`**: 
- **`CS_LINKER_SIGNED`**: 
- **`CS_EXECSEG_MAIN_BINARY`**: 
- **`UNWIND_SECTION_VERSION`**: 
- **`UNWIND_IS_NOT_FUNCTION_START`**: 
- **`UNWIND_HAS_LSDA`**: 
- **`UNWIND_PERSONALITY_MASK`**: 
- **`UNWIND_X86_64_MODE_MASK`**: 
- **`UNWIND_X86_64_RBP_FRAME_REGISTERS`**: 
- **`UNWIND_X86_64_RBP_FRAME_OFFSET`**: 
- **`UNWIND_X86_64_FRAMELESS_STACK_SIZE`**: 
- **`UNWIND_X86_64_FRAMELESS_STACK_ADJUST`**: 
- **`UNWIND_X86_64_FRAMELESS_STACK_REG_COUNT`**: 
- **`UNWIND_X86_64_FRAMELESS_STACK_REG_PERMUTATION`**: 
- **`UNWIND_X86_64_DWARF_SECTION_OFFSET`**: 
- **`UNWIND_ARM64_MODE_MASK`**: 
- **`UNWIND_ARM64_FRAME_X19_X20_PAIR`**: 
- **`UNWIND_ARM64_FRAME_X21_X22_PAIR`**: 
- **`UNWIND_ARM64_FRAME_X23_X24_PAIR`**: 
- **`UNWIND_ARM64_FRAME_X25_X26_PAIR`**: 
- **`UNWIND_ARM64_FRAME_X27_X28_PAIR`**: 
- **`UNWIND_ARM64_FRAME_D8_D9_PAIR`**: 
- **`UNWIND_ARM64_FRAME_D10_D11_PAIR`**: 
- **`UNWIND_ARM64_FRAME_D12_D13_PAIR`**: 
- **`UNWIND_ARM64_FRAME_D14_D15_PAIR`**: 
- **`UNWIND_ARM64_FRAMELESS_STACK_SIZE_MASK`**: 
- **`UNWIND_ARM64_DWARF_SECTION_OFFSET`**: 
- **`ARMAG`**: String that begins an archive file.
- **`ARFMAG`**: String in ar_fmag at the end of each header.

