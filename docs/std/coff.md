# `std.coff`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/coff.zig`  
> [← Back to Standard Library Index](README.md)

## Types

### `Header`


### Fields

- `machine: IMAGE.FILE.MACHINE`
  The number that identifies the type of target machine.
- `number_of_sections: u16`
  The number of sections. This indicates the size of the section table, which immediately follows the headers.
- `time_date_stamp: u32`
  The low 32 bits of the number of seconds since 00:00 January 1, 1970 (a C run-time time_t value),
  which indicates when the file was created.
- `pointer_to_symbol_table: u32`
  The file offset of the COFF symbol table, or zero if no COFF symbol table is present.
  This value should be zero for an image because COFF debugging information is deprecated.
- `number_of_symbols: u32`
  The number of entries in the symbol table.
  This data can be used to locate the string table, which immediately follows the symbol table.
  This value should be zero for an image because COFF debugging information is deprecated.
- `size_of_optional_header: u16`
  The size of the optional header, which is required for executable files but not for object files.
  This value should be zero for an object file. For a description of the header format, see Optional Header (Image Only).
- `flags: Header.Flags`
  The flags that indicate the attributes of the file.

### Types

#### `Flags`


### `DllFlags`


### Fields

- `_reserved_0: u5 = 0`
  
- `HIGH_ENTROPY_VA: bool = false`
  Image can handle a high entropy 64-bit virtual address space.
- `DYNAMIC_BASE: bool = false`
  DLL can be relocated at load time.
- `FORCE_INTEGRITY: bool = false`
  Code Integrity checks are enforced.
- `NX_COMPAT: bool = false`
  Image is NX compatible.
- `NO_ISOLATION: bool = false`
  Isolation aware, but do not isolate the image.
- `NO_SEH: bool = false`
  Does not use structured exception (SE) handling. No SE handler may be called in this image.
- `NO_BIND: bool = false`
  Do not bind the image.
- `APPCONTAINER: bool = false`
  Image must execute in an AppContainer.
- `WDM_DRIVER: bool = false`
  A WDM driver.
- `GUARD_CF: bool = false`
  Image supports Control Flow Guard.
- `TERMINAL_SERVER_AWARE: bool = false`
  Terminal Server aware.

### `Subsystem`


### Fields

- `UNKNOWN = 0`
  An unknown subsystem
- `NATIVE = 1`
  Device drivers and native Windows processes
- `WINDOWS_GUI = 2`
  The Windows graphical user interface (GUI) subsystem
- `WINDOWS_CUI = 3`
  The Windows character subsystem
- `OS2_CUI = 5`
  The OS/2 character subsystem
- `POSIX_CUI = 7`
  The Posix character subsystem
- `NATIVE_WINDOWS = 8`
  Native Win9x driver
- `WINDOWS_CE_GUI = 9`
  Windows CE
- `EFI_APPLICATION = 10`
  An Extensible Firmware Interface (EFI) application
- `EFI_BOOT_SERVICE_DRIVER = 11`
  An EFI driver with boot services
- `EFI_RUNTIME_DRIVER = 12`
  An EFI driver with run-time services
- `EFI_ROM = 13`
  An EFI ROM image
- `XBOX = 14`
  XBOX
- `WINDOWS_BOOT_APPLICATION = 16`
  Windows boot application
- `_`
  

### `OptionalHeader`


### Fields

- `magic: OptionalHeader.Magic`
  
- `major_linker_version: u8`
  
- `minor_linker_version: u8`
  
- `size_of_code: u32`
  
- `size_of_initialized_data: u32`
  
- `size_of_uninitialized_data: u32`
  
- `address_of_entry_point: u32`
  
- `base_of_code: u32`
  

### Types

#### `Magic`


#### `PE32`


#### `@"PE32+"`


### `ImageDataDirectory`


### Fields

- `virtual_address: u32`
  
- `size: u32`
  

### `BaseRelocationDirectoryEntry`


### Fields

- `page_rva: u32`
  The image base plus the page RVA is added to each offset to create the VA where the base relocation must be applied.
- `block_size: u32`
  The total number of bytes in the base relocation block, including the Page RVA and Block Size fields and the Type/Offset fields that follow.

### `BaseRelocation`


### Fields

- `offset: u12`
  Stored in the remaining 12 bits of the WORD, an offset from the starting address that was specified in the Page RVA field for the block.
  This offset specifies where the base relocation is to be applied.
- `type: BaseRelocationType`
  Stored in the high 4 bits of the WORD, a value that indicates the type of base relocation to be applied.

### `BaseRelocationType`


### Fields

- `ABSOLUTE = 0`
  The base relocation is skipped. This type can be used to pad a block.
- `HIGH = 1`
  The base relocation adds the high 16 bits of the difference to the 16-bit field at offset. The 16-bit field represents the high value of a 32-bit word.
- `LOW = 2`
  The base relocation adds the low 16 bits of the difference to the 16-bit field at offset. The 16-bit field represents the low half of a 32-bit word.
- `HIGHLOW = 3`
  The base relocation applies all 32 bits of the difference to the 32-bit field at offset.
- `HIGHADJ = 4`
  The base relocation adds the high 16 bits of the difference to the 16-bit field at offset.
  The 16-bit field represents the high value of a 32-bit word.
  The low 16 bits of the 32-bit value are stored in the 16-bit word that follows this base relocation.
  This means that this base relocation occupies two slots.
- `MIPS_JMPADDR = 5`
  When the machine type is MIPS, the base relocation applies to a MIPS jump instruction.
- `RESERVED = 6`
  This relocation is meaningful only when the machine type is ARM or Thumb.
  The base relocation applies the 32-bit address of a symbol across a consecutive MOVW/MOVT instruction pair.
  This relocation is only meaningful when the machine type is RISC-V.
  The base relocation applies to the high 20 bits of a 32-bit absolute address.
  Reserved, must be zero.
- `THUMB_MOV32 = 7`
  This relocation is meaningful only when the machine type is Thumb.
  The base relocation applies the 32-bit address of a symbol to a consecutive MOVW/MOVT instruction pair.
- `RISCV_LOW12S = 8`
  This relocation is only meaningful when the machine type is RISC-V.
  The base relocation applies to the low 12 bits of a 32-bit absolute address formed in RISC-V I-type instruction format.
  This relocation is only meaningful when the machine type is RISC-V.
  The base relocation applies to the low 12 bits of a 32-bit absolute address formed in RISC-V S-type instruction format.
- `MIPS_JMPADDR16 = 9`
  This relocation is only meaningful when the machine type is LoongArch 32-bit.
  The base relocation applies to a 32-bit absolute address formed in two consecutive instructions.
  This relocation is only meaningful when the machine type is LoongArch 64-bit.
  The base relocation applies to a 64-bit absolute address formed in four consecutive instructions.
  The relocation is only meaningful when the machine type is MIPS.
  The base relocation applies to a MIPS16 jump instruction.
- `DIR64 = 10`
  The base relocation applies the difference to the 64-bit field at offset.
- `_`
  

### `DebugDirectoryEntry`


### Fields

- `characteristics: u32`
  
- `time_date_stamp: u32`
  
- `major_version: u16`
  
- `minor_version: u16`
  
- `type: DebugType`
  
- `size_of_data: u32`
  
- `address_of_raw_data: u32`
  
- `pointer_to_raw_data: u32`
  

### `DebugType`


### Fields

- `UNKNOWN = 0`
  
- `COFF = 1`
  
- `CODEVIEW = 2`
  
- `FPO = 3`
  
- `MISC = 4`
  
- `EXCEPTION = 5`
  
- `FIXUP = 6`
  
- `OMAP_TO_SRC = 7`
  
- `OMAP_FROM_SRC = 8`
  
- `BORLAND = 9`
  
- `RESERVED10 = 10`
  
- `VC_FEATURE = 12`
  
- `POGO = 13`
  
- `ILTCG = 14`
  
- `MPX = 15`
  
- `REPRO = 16`
  
- `EX_DLLCHARACTERISTICS = 20`
  
- `_`
  

### `TlsDirectoryEntry`

```zig
pub fn TlsDirectoryEntry(comptime magic: std.coff.OptionalHeader.Magic) type
```


### `ImportDirectoryEntry`


### Fields

- `import_lookup_table_rva: u32`
  The RVA of the import lookup table.
  This table contains a name or ordinal for each import.
  (The name "Characteristics" is used in Winnt.h, but no longer describes this field.)
- `time_date_stamp: u32`
  The stamp that is set to zero until the image is bound.
  After the image is bound, this field is set to the time/data stamp of the DLL.
- `forwarder_chain: u32`
  The index of the first forwarder reference.
- `name_rva: u32`
  The address of an ASCII string that contains the name of the DLL.
  This address is relative to the image base.
- `import_address_table_rva: u32`
  The RVA of the import address table.
  The contents of this table are identical to the contents of the import lookup table until the image is bound.

### `ImportLookupTableEntry`

```zig
pub fn ImportLookupTableEntry(comptime magic: std.coff.OptionalHeader.Magic) type
```


### `ImportHintNameEntry`

Every name ends with a NULL byte. IF the NULL byte does not fall on
2byte boundary, the entry structure is padded to ensure 2byte alignment.

### Fields

- `hint: u16`
  An index into the export name pointer table.
  A match is attempted first with this value. If it fails, a binary search is performed on the DLL's export name pointer table.
- `name: [1]u8`
  Pointer to NULL terminated ASCII name.
  Variable length...

### `ExportDirectoryTable`


### Fields

- `flags: u32`
  Reserved
- `time_date_stamp: u32`
  Creation time of this table
- `major_version: u16`
  
- `minor_version: u16`
  
- `name_rva: u32`
  The address of an ASCII string that contains the name of the DLL.
  This address is relative to the image base.
- `ordinal_base: u32`
  The ordinal of the first export in this image
- `number_of_entries: u32`
  Number of entries in the export address table
- `number_of_names: u32`
  Number of entries in the name pointer table and ordinal table
- `export_address_table_rva: u32`
  
- `name_pointer_table_rva: u32`
  
- `ordinal_table_rva: u32`
  

### `ExportAddressTableEntry`


### Fields

- `export_or_forwarder_rva: u32`
  If this address is within the export section, then this is the address of the export
  Otherwise, this is the address of a string that specfies a symbol in another DLL:
    <dll name>.<export name>
    <dll name>.#<export ordinal>

### `ExportNamePointerTableEntry`


### Fields

- `name_rva: u32`
  

### `ExportOrdinalTableEntry`


### Fields

- `unbiased_ordinal: u16`
  

### `SectionHeader`


### Fields

- `name: [8]u8`
  
- `virtual_size: u32`
  
- `virtual_address: u32`
  
- `size_of_raw_data: u32`
  
- `pointer_to_raw_data: u32`
  
- `pointer_to_relocations: u32`
  
- `pointer_to_linenumbers: u32`
  
- `number_of_relocations: u16`
  
- `number_of_linenumbers: u16`
  
- `flags: SectionHeader.Flags`
  

### Types

#### `Flags`


### Functions

#### `getName`

```zig
pub fn getName(self: *align(1) const SectionHeader) ?[]const u8
```


#### `getNameOffset`

```zig
pub fn getNameOffset(self: SectionHeader) ?u32
```


#### `getAlignment`

```zig
pub fn getAlignment(self: SectionHeader) ?u16
```

Applicable only to section headers in COFF objects.

#### `setAlignment`

```zig
pub fn setAlignment(self: *SectionHeader, new_alignment: u16) void
```


#### `isCode`

```zig
pub fn isCode(self: SectionHeader) bool
```


#### `isComdat`

```zig
pub fn isComdat(self: SectionHeader) bool
```


### `Symbol`


### Fields

- `name: [8]u8`
  
- `value: u32`
  
- `section_number: SectionNumber`
  
- `type: SymType`
  
- `storage_class: StorageClass`
  
- `number_of_aux_symbols: u8`
  

### Functions

#### `sizeOf`

```zig
pub fn sizeOf() comptime_int
```


#### `getName`

```zig
pub fn getName(self: *const Symbol) ?[]const u8
```


#### `getNameOffset`

```zig
pub fn getNameOffset(self: Symbol) ?u32
```


### `SectionNumber`


### Fields

- `UNDEFINED = 0`
  The symbol record is not yet assigned a section.
  A value of zero indicates that a reference to an external symbol is defined elsewhere.
  A value of non-zero is a common symbol with a size that is specified by the value.
- `ABSOLUTE = -1`
  The symbol has an absolute (non-relocatable) value and is not an address.
- `DEBUG = -2`
  The symbol provides general type or debugging information but does not correspond to a section.
  Microsoft tools use this setting along with .file records (storage class FILE).
- `_`
  

### `SymType`


### Fields

- `complex_type: ComplexType`
  
- `base_type: BaseType`
  

### `BaseType`


### Fields

- `NULL = 0`
  No type information or unknown base type. Microsoft tools use this setting
- `VOID = 1`
  No valid type; used with void pointers and functions
- `CHAR = 2`
  A character (signed byte)
- `SHORT = 3`
  A 2-byte signed integer
- `INT = 4`
  A natural integer type (normally 4 bytes in Windows)
- `LONG = 5`
  A 4-byte signed integer
- `FLOAT = 6`
  A 4-byte floating-point number
- `DOUBLE = 7`
  An 8-byte floating-point number
- `STRUCT = 8`
  A structure
- `UNION = 9`
  A union
- `ENUM = 10`
  An enumerated type
- `MOE = 11`
  A member of enumeration (a specified value)
- `BYTE = 12`
  A byte; unsigned 1-byte integer
- `WORD = 13`
  A word; unsigned 2-byte integer
- `UINT = 14`
  An unsigned integer of natural size (normally, 4 bytes)
- `DWORD = 15`
  An unsigned 4-byte integer
- `_`
  

### `ComplexType`


### Fields

- `NULL = 0`
  No derived type; the symbol is a simple scalar variable.
- `POINTER = 16`
  The symbol is a pointer to base type.
- `FUNCTION = 32`
  The symbol is a function that returns a base type.
- `ARRAY = 48`
  The symbol is an array of base type.
- `_`
  

### `StorageClass`


### Fields

- `END_OF_FUNCTION = 0xff`
  A special symbol that represents the end of function, for debugging purposes.
- `NULL = 0`
  No assigned storage class.
- `AUTOMATIC = 1`
  The automatic (stack) variable. The Value field specifies the stack frame offset.
- `EXTERNAL = 2`
  A value that Microsoft tools use for external symbols.
  The Value field indicates the size if the section number is IMAGE_SYM_UNDEFINED (0).
  If the section number is not zero, then the Value field specifies the offset within the section.
- `STATIC = 3`
  The offset of the symbol within the section.
  If the Value field is zero, then the symbol represents a section name.
- `REGISTER = 4`
  A register variable.
  The Value field specifies the register number.
- `EXTERNAL_DEF = 5`
  A symbol that is defined externally.
- `LABEL = 6`
  A code label that is defined within the module.
  The Value field specifies the offset of the symbol within the section.
- `UNDEFINED_LABEL = 7`
  A reference to a code label that is not defined.
- `MEMBER_OF_STRUCT = 8`
  The structure member. The Value field specifies the n th member.
- `ARGUMENT = 9`
  A formal argument (parameter) of a function. The Value field specifies the n th argument.
- `STRUCT_TAG = 10`
  The structure tag-name entry.
- `MEMBER_OF_UNION = 11`
  A union member. The Value field specifies the n th member.
- `UNION_TAG = 12`
  The Union tag-name entry.
- `TYPE_DEFINITION = 13`
  A Typedef entry.
- `UNDEFINED_STATIC = 14`
  A static data declaration.
- `ENUM_TAG = 15`
  An enumerated type tagname entry.
- `MEMBER_OF_ENUM = 16`
  A member of an enumeration. The Value field specifies the n th member.
- `REGISTER_PARAM = 17`
  A register parameter.
- `BIT_FIELD = 18`
  A bit-field reference. The Value field specifies the n th bit in the bit field.
- `BLOCK = 100`
  A .bb (beginning of block) or .eb (end of block) record.
  The Value field is the relocatable address of the code location.
- `FUNCTION = 101`
  A value that Microsoft tools use for symbol records that define the extent of a function: begin function (.bf ), end function ( .ef ), and lines in function ( .lf ).
  For .lf records, the Value field gives the number of source lines in the function.
  For .ef records, the Value field gives the size of the function code.
- `END_OF_STRUCT = 102`
  An end-of-structure entry.
- `FILE = 103`
  A value that Microsoft tools, as well as traditional COFF format, use for the source-file symbol record.
  The symbol is followed by auxiliary records that name the file.
- `SECTION = 104`
  A definition of a section (Microsoft tools use STATIC storage class instead).
- `WEAK_EXTERNAL = 105`
  A weak external. For more information, see Auxiliary Format 3: Weak Externals.
- `CLR_TOKEN = 107`
  A CLR token symbol. The name is an ASCII string that consists of the hexadecimal value of the token.
  For more information, see CLR Token Definition (Object Only).
- `_`
  

### `FunctionDefinition`


### Fields

- `tag_index: u32`
  The symbol-table index of the corresponding .bf (begin function) symbol record.
- `total_size: u32`
  The size of the executable code for the function itself.
  If the function is in its own section, the SizeOfRawData in the section header is greater or equal to this field,
  depending on alignment considerations.
- `pointer_to_linenumber: u32`
  The file offset of the first COFF line-number entry for the function, or zero if none exists.
- `pointer_to_next_function: u32`
  The symbol-table index of the record for the next function.
  If the function is the last in the symbol table, this field is set to zero.
- `unused: [2]u8`
  

### `SectionDefinition`


### Fields

- `length: u32`
  The size of section data; the same as SizeOfRawData in the section header.
- `number_of_relocations: u16`
  The number of relocation entries for the section.
- `number_of_linenumbers: u16`
  The number of line-number entries for the section.
- `checksum: u32`
  The checksum for communal data. It is applicable if the IMAGE_SCN_LNK_COMDAT flag is set in the section header.
- `number: u16`
  One-based index into the section table for the associated section. This is used when the COMDAT selection setting is 5.
- `selection: ComdatSelection`
  The COMDAT selection number. This is applicable if the section is a COMDAT section.
- `unused: [3]u8`
  

### `FileDefinition`


### Fields

- `file_name: [18]u8`
  An ANSI string that gives the name of the source file.
  This is padded with nulls if it is less than the maximum length.

### Functions

#### `getFileName`

```zig
pub fn getFileName(self: *const FileDefinition) []const u8
```


### `WeakExternalDefinition`


### Fields

- `tag_index: u32`
  The symbol-table index of sym2, the symbol to be linked if sym1 is not found.
- `flag: WeakExternalFlag`
  A value of IMAGE_WEAK_EXTERN_SEARCH_NOLIBRARY indicates that no library search for sym1 should be performed.
  A value of IMAGE_WEAK_EXTERN_SEARCH_LIBRARY indicates that a library search for sym1 should be performed.
  A value of IMAGE_WEAK_EXTERN_SEARCH_ALIAS indicates that sym1 is an alias for sym2.
- `unused: [10]u8`
  

### Functions

#### `sizeOf`

```zig
pub fn sizeOf() comptime_int
```


### `WeakExternalFlag`


### Fields

- `SEARCH_NOLIBRARY = 1`
  
- `SEARCH_LIBRARY = 2`
  
- `SEARCH_ALIAS = 3`
  
- `ANTI_DEPENDENCY = 4`
  
- `_`
  

### `ComdatSelection`


### Fields

- `NONE = 0`
  Not a COMDAT section.
- `NODUPLICATES = 1`
  If this symbol is already defined, the linker issues a "multiply defined symbol" error.
- `ANY = 2`
  Any section that defines the same COMDAT symbol can be linked; the rest are removed.
- `SAME_SIZE = 3`
  The linker chooses an arbitrary section among the definitions for this symbol.
  If all definitions are not the same size, a "multiply defined symbol" error is issued.
- `EXACT_MATCH = 4`
  The linker chooses an arbitrary section among the definitions for this symbol.
  If all definitions do not match exactly, a "multiply defined symbol" error is issued.
- `ASSOCIATIVE = 5`
  The section is linked if a certain other COMDAT section is linked.
  This other section is indicated by the Number field of the auxiliary symbol record for the section definition.
  This setting is useful for definitions that have components in multiple sections
  (for example, code in one and data in another), but where all must be linked or discarded as a set.
  The other section this section is associated with must be a COMDAT section, which can be another
  associative COMDAT section. An associative COMDAT section's section association chain can't form a loop.
  The section association chain must eventually come to a COMDAT section that doesn't have IMAGE_COMDAT_SELECT_ASSOCIATIVE set.
- `LARGEST = 6`
  The linker chooses the largest definition from among all of the definitions for this symbol.
  If multiple definitions have this size, the choice between them is arbitrary.
- `_`
  

### `DebugInfoDefinition`


### Fields

- `unused_1: [4]u8`
  
- `linenumber: u16`
  The actual ordinal line number (1, 2, 3, and so on) within the source file, corresponding to the .bf or .ef record.
- `unused_2: [6]u8`
  
- `pointer_to_next_function: u32`
  The symbol-table index of the next .bf symbol record.
  If the function is the last in the symbol table, this field is set to zero.
  It is not used for .ef records.
- `unused_3: [2]u8`
  

### `Coff`


### Fields

- `data: []const u8`
  
- `is_loaded: bool`
  
- `is_image: bool`
  
- `coff_header_offset: usize`
  
- `guid: [16]u8 = undefined`
  
- `age: u32 = undefined`
  

### Functions

#### `init`

```zig
pub fn init(data: []const u8, is_loaded: bool) error{ EndOfStream, MissingPEHeader }!Coff
```


#### `getPdbPath`

```zig
pub fn getPdbPath(self: *Coff) !?[]const u8
```


#### `getHeader`

```zig
pub fn getHeader(self: Coff) Header
```


#### `getOptionalHeader`

```zig
pub fn getOptionalHeader(self: Coff) OptionalHeader
```


#### `getOptionalHeader32`

```zig
pub fn getOptionalHeader32(self: Coff) OptionalHeader.PE32
```


#### `getOptionalHeader64`

```zig
pub fn getOptionalHeader64(self: Coff) OptionalHeader.@"PE32+"
```


#### `getImageBase`

```zig
pub fn getImageBase(self: Coff) u64
```


#### `getNumberOfDataDirectories`

```zig
pub fn getNumberOfDataDirectories(self: Coff) u32
```


#### `getDataDirectories`

```zig
pub fn getDataDirectories(self: *const Coff) []align(1) const ImageDataDirectory
```


#### `getSymtab`

```zig
pub fn getSymtab(self: *const Coff) ?Symtab
```


#### `getStrtab`

```zig
pub fn getStrtab(self: *const Coff) error{InvalidStrtabSize}!?Strtab
```


#### `strtabRequired`

```zig
pub fn strtabRequired(self: *const Coff) bool
```


#### `getSectionHeaders`

```zig
pub fn getSectionHeaders(self: *const Coff) []align(1) const SectionHeader
```


#### `getSectionHeadersAlloc`

```zig
pub fn getSectionHeadersAlloc(self: *const Coff, allocator: mem.Allocator) ![]SectionHeader
```


#### `getSectionName`

```zig
pub fn getSectionName(self: *const Coff, sect_hdr: *align(1) const SectionHeader) error{InvalidStrtabSize}![]const u8
```


#### `getSectionByName`

```zig
pub fn getSectionByName(self: *const Coff, comptime name: []const u8) ?*align(1) const SectionHeader
```


#### `getSectionData`

```zig
pub fn getSectionData(self: *const Coff, sec: *align(1) const SectionHeader) []const u8
```


#### `getSectionDataAlloc`

```zig
pub fn getSectionDataAlloc(self: *const Coff, sec: *align(1) const SectionHeader, allocator: mem.Allocator) ![]u8
```


### `Symtab`


### Fields

- `buffer: []const u8`
  

### Types

#### `Tag`


#### `Record`


#### `Slice`


### Functions

#### `len`

```zig
pub fn len(self: Symtab) usize
```


#### `at`

```zig
pub fn at(self: Symtab, index: usize, tag: Tag) Record
```

Lives as long as Symtab instance.

#### `slice`

```zig
pub fn slice(self: Symtab, start: usize, end: ?usize) Slice
```


### `Strtab`


### Fields

- `buffer: []const u8`
  

### Functions

#### `get`

```zig
pub fn get(self: Strtab, off: u32) []const u8
```


### `ImportHeader`


### Fields

- `sig1: IMAGE.FILE.MACHINE = .UNKNOWN`
  Must be IMAGE_FILE_MACHINE_UNKNOWN
- `sig2: u16 = 0xFFFF`
  Must be 0xFFFF
- `version: u16`
  
- `machine: IMAGE.FILE.MACHINE`
  
- `time_date_stamp: u32`
  
- `size_of_data: u32`
  
- `hint: u16`
  
- `types: packed struct(u16) { type: ImportType, name_type: ImportNameType, reserved: u11, }`
  

### `ImportType`


### Fields

- `CODE = 0`
  Executable code.
- `DATA = 1`
  Data.
- `CONST = 2`
  Specified as CONST in .def file.
- `_`
  

### `ImportNameType`


### Fields

- `ORDINAL = 0`
  The import is by ordinal. This indicates that the value in the Ordinal/Hint
  field of the import header is the import's ordinal. If this constant is not
  specified, then the Ordinal/Hint field should always be interpreted as the import's hint.
- `NAME = 1`
  The import name is identical to the public symbol name.
- `NAME_NOPREFIX = 2`
  The import name is the public symbol name, but skipping the leading ?, @, or optionally _.
- `NAME_UNDECORATE = 3`
  The import name is the public symbol name, but skipping the leading ?, @, or optionally _,
  and truncating at the first @.
- `NAME_EXPORTAS = 4`
  https://github.com/llvm/llvm-project/pull/83211
- `_`
  

### `Relocation`


### Fields

- `virtual_address: u32`
  
- `symbol_table_index: u32`
  
- `type: u16`
  

### Functions

#### `sizeOf`

```zig
pub fn sizeOf() comptime_int
```


### `ArchiveMemberHeader`


### Fields

- `name: [16]u8`
  Left-justified '/' terminated member name
- `date: [12]u8`
  Left-justified ASCII decimal: seconds since January 1st, 1970
- `user_id: [6]u8`
  Left-justified ASCII decimal: user id
- `group_id: [6]u8`
  Left-justified ASCII decimal: group id
- `file_mode: [8]u8`
  Left-justified ASCII octal: file mode
- `size: [10]u8`
  Left-justified ASCII decimal: size of the member following this header,
  not including the size of this header.
- `end_of_header: [2]u8`
  The literal string '`\n'

### Types

#### `Kind`


### Functions

#### `parseName`

```zig
pub fn parseName(self: *const ArchiveMemberHeader, opt_longnames: ?[]const u8, ) ![]const u8
```

Extracts the name of the member by either reading it directly from
the header, or by finding it inside the longnames member, if provided.

#### `parseDate`

```zig
pub fn parseDate(self: *const ArchiveMemberHeader) !u40
```


#### `parseUserId`

```zig
pub fn parseUserId(self: *const ArchiveMemberHeader) !u20
```


#### `parseGroupId`

```zig
pub fn parseGroupId(self: *const ArchiveMemberHeader) !u20
```


#### `parseFileMode`

```zig
pub fn parseFileMode(self: *const ArchiveMemberHeader) !u20
```


#### `parseSize`

```zig
pub fn parseSize(self: *const ArchiveMemberHeader) !u34
```


### `LineNumber`


### Fields

- `type: extern union { symbol_table_index: u32, virtual_address: u32, }`
  
- `line_number: u16`
  

### Functions

#### `sizeOf`

```zig
pub fn sizeOf() comptime_int
```


## Namespaces

- **`IMAGE`**: 

## Error Sets

- **`Error`**
  

## Constants & Variables

- **`archive_signature`**: 
- **`archive_end_of_header`**: 
- **`pe_signature`**: 
- **`pe_pointer_offset`**: 
- **`IMAGE_NT_OPTIONAL_HDR32_MAGIC`**: 
- **`IMAGE_NT_OPTIONAL_HDR64_MAGIC`**: 
- **`IMAGE_NUMBEROF_DIRECTORY_ENTRIES`**: 

