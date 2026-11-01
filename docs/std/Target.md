# `std.Target`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/Target.zig`  
> [← Back to Standard Library Index](README.md)

All the details about the machine that will be executing code.
Unlike `Query` which might leave some things as "default" or "host", this
data is fully resolved into a concrete set of OS versions, CPU features,
etc.

## Fields

- `cpu: Cpu`
  
- `os: Os`
  
- `abi: Abi`
  
- `ofmt: ObjectFormat`
  
- `dynamic_linker: DynamicLinker = DynamicLinker.none`
  

## Types

### `Os`


### Fields

- `tag: Tag`
  
- `version_range: VersionRange`
  

### Types

#### `Tag`


#### `WindowsVersion`

Based on NTDDI version constants from
https://docs.microsoft.com/en-us/cpp/porting/modifying-winver-and-win32-winnt

#### `HurdVersionRange`


#### `LinuxVersionRange`


#### `VersionRange`

The version ranges here represent the minimum OS version to be supported
and the maximum OS version to be supported. The default values represent
the range that the Zig Standard Library bases its abstractions on.

The minimum version of the range is the main setting to tweak for a target.
Usually, the maximum target OS version will remain the default, which is
the latest released version of the OS.

To test at compile time if the target is guaranteed to support a given OS feature,
one should check that the minimum version of the range is greater than or equal to
the version the feature was introduced in.

To test at compile time if the target certainly will not support a given OS feature,
one should check that the maximum version of the range is less than the version the
feature was introduced in.

If neither of these cases apply, a runtime check should be used to determine if the
target supports a given OS feature.

Binaries built with a given maximum version will continue to function on newer
operating system versions. However, such a binary may not take full advantage of the
newer operating system APIs.

See `Os.isAtLeast`.

#### `TaggedVersionRange`


### Functions

#### `versionRange`

```zig
pub inline fn versionRange(os: Os) TaggedVersionRange
```

Provides a tagged union. `Target` does not store the tag because it is
redundant with the OS tag; this function abstracts that part away.

#### `isAtLeast`

```zig
pub inline fn isAtLeast(os: Os, comptime tag: Tag, ver: switch (tag.versionRangeTag()) { .none => void, .semver, .hurd, .linux => std.SemanticVersion, .windows => WindowsVersion, }) ?bool
```

Checks if system is guaranteed to be at least `version` or older than `version`.
Returns `null` if a runtime check is required.

### `Abi`


### Fields

- `none`
  
- `gnu`
  
- `gnuabin32`
  
- `gnuabi64`
  
- `gnueabi`
  
- `gnueabihf`
  
- `gnuf32`
  
- `gnusf`
  
- `gnux32`
  
- `eabi`
  
- `eabihf`
  
- `abin32`
  
- `x32`
  
- `ilp32`
  
- `android`
  
- `androideabi`
  
- `musl`
  
- `muslabin32`
  
- `muslabi64`
  
- `musleabi`
  
- `musleabihf`
  
- `muslf32`
  
- `muslsf`
  
- `muslx32`
  
- `msvc`
  
- `itanium`
  
- `simulator`
  
- `ohos`
  
- `ohoseabi`
  
- `call0`
  

### Types

#### `Float`


### Functions

#### `default`

```zig
pub fn default(arch: Cpu.Arch, os_tag: Os.Tag) Abi
```


#### `isGnu`

```zig
pub inline fn isGnu(abi: Abi) bool
```


#### `isMusl`

```zig
pub inline fn isMusl(abi: Abi) bool
```


#### `isOpenHarmony`

```zig
pub inline fn isOpenHarmony(abi: Abi) bool
```


#### `isAndroid`

```zig
pub inline fn isAndroid(abi: Abi) bool
```


#### `float`

```zig
pub inline fn float(abi: Abi) Float
```


### `ObjectFormat`


### Fields

- `c`
  C source code.
- `coff`
  The Common Object File Format used by Windows and UEFI.
- `elf`
  The Executable and Linkable Format used by many Unixes.
- `hex`
  The Intel HEX format for storing binary code in ASCII text.
- `macho`
  The Mach object format used by macOS and other Apple platforms.
- `plan9`
  The a.out format used by Plan 9 from Bell Labs.
- `raw`
  Machine code with no metadata.
- `spirv`
  The Khronos Group's Standard Portable Intermediate Representation V.
- `wasm`
  The WebAssembly binary format.

### Functions

#### `fileExt`

```zig
pub fn fileExt(of: ObjectFormat, arch: Cpu.Arch) [:0]const u8
```


#### `default`

```zig
pub fn default(os_tag: Os.Tag, arch: Cpu.Arch) ObjectFormat
```


### `Cpu`


### Fields

- `arch: Arch`
  Architecture
- `model: *const Model`
  The CPU model to target. It has a set of features
  which are overridden with the `features` field.
- `features: Feature.Set`
  An explicit list of the entire CPU feature set. It may differ from the specific CPU model's features.

### Types

#### `Feature`


#### `Arch`


#### `Model`


### Functions

#### `baseline`

```zig
pub fn baseline(arch: Arch, os: Os) Cpu
```

The "default" set of CPU features for cross-compiling. A conservative set
of features that is expected to be supported on most available hardware.

#### `has`

```zig
pub fn has(cpu: Cpu, comptime family: Arch.Family, feature: @field(Target, @tagName(family)).Feature) bool
```

Returns true if `feature` is enabled.

#### `hasAny`

```zig
pub fn hasAny(cpu: Cpu, comptime family: Arch.Family, features: []const @field(Target, @tagName(family)).Feature) bool
```

Returns true if any feature in `features` is enabled.

#### `hasAll`

```zig
pub fn hasAll(cpu: Cpu, comptime family: Arch.Family, features: []const @field(Target, @tagName(family)).Feature) bool
```

Returns true if all features in `features` are enabled.

### `AddressSpaceContext`

The places where a user can specify an address space attribute

### Fields

- `function`
  A function is specified to be placed in a certain address space.
- `variable`
  A (global) variable is specified to be placed in a certain address space. In contrast to
  `.constant`, these values (and thus the address space they will be placed in) are required
  to be mutable.
- `constant`
  A (global) constant value is specified to be placed in a certain address space. In contrast
  to `.variable`, values placed in this address space are not required to be mutable.
- `pointer`
  A pointer is ascripted to point into a certain address space.

### `DynamicLinker`


### Fields

- `buffer: [255]u8`
  Contains the memory used to store the dynamic linker path. This field
  should not be used directly. See `get` and `set`. This field exists so
  that this API requires no allocator.
- `len: u8`
  Used to construct the dynamic linker path. This field should not be used
  directly. See `get` and `set`.

### Types

#### `Kind`


### Functions

#### `init`

```zig
pub fn init(maybe_path: ?[]const u8) DynamicLinker
```

Asserts that the length is less than or equal to 255 bytes.

#### `initFmt`

```zig
pub fn initFmt(comptime fmt_str: []const u8, args: anytype) !DynamicLinker
```


#### `get`

```zig
pub fn get(dl: *const DynamicLinker) ?[]const u8
```

The returned memory has the same lifetime as the `DynamicLinker`.

#### `set`

```zig
pub fn set(dl: *DynamicLinker, maybe_path: ?[]const u8) void
```

Asserts that the length is less than or equal to 255 bytes.

#### `setFmt`

```zig
pub fn setFmt(dl: *DynamicLinker, comptime fmt_str: []const u8, args: anytype) !void
```

Asserts that the length is less than or equal to 255 bytes.

#### `eql`

```zig
pub fn eql(lhs: DynamicLinker, rhs: DynamicLinker) bool
```


#### `kind`

```zig
pub fn kind(os: Os.Tag) Kind
```


#### `standard`

```zig
pub fn standard(cpu: Cpu, os: Os.Tag, abi: Abi) DynamicLinker
```

The strictness of this function depends on the value of `kind(os.tag)`:

* `.none`: Ignores all arguments and just returns `none`.
* `.arch_os`: Ignores `abi` and returns the dynamic linker matching `cpu` and `os`.
* `.arch_os_abi`: Returns the dynamic linker matching `cpu`, `os`, and `abi`.

In the case of `.arch_os` in particular, callers should be aware that a valid dynamic linker
being returned only means that the `cpu` + `os` combination represents a platform that
actually exists and which has an established dynamic linker path that does not change with
the ABI; it does not necessarily mean that `abi` makes any sense at all for that platform.
The responsibility for determining whether `abi` is valid in this case rests with the
caller. `Abi.default()` can be used to pick a best-effort default ABI for such platforms.

### Constants & Variables

- **`none`**: 

### `StackGrowth`


### Fields

- `down`
  
- `up`
  

### `CType`


### Fields

- `char`
  
- `short`
  
- `ushort`
  
- `int`
  
- `uint`
  
- `long`
  
- `ulong`
  
- `longlong`
  
- `ulonglong`
  
- `float`
  
- `double`
  
- `longdouble`
  

## Functions

### `toElfMachine`

```zig
pub fn toElfMachine(target: *const Target) std.elf.EM
```


### `toCoffMachine`

```zig
pub fn toCoffMachine(target: *const Target) std.coff.IMAGE.FILE.MACHINE
```


### `zigTriple`

```zig
pub fn zigTriple(target: *const Target, allocator: Allocator) Allocator.Error![]u8
```


### `hurdTupleSimple`

```zig
pub fn hurdTupleSimple(allocator: Allocator, arch: Cpu.Arch, abi: Abi) ![]u8
```

Deprecated; to be removed in 0.18.0. Use `std.zig.target.hurdTupleSimple` instead.

### `hurdTuple`

```zig
pub fn hurdTuple(target: *const Target, allocator: Allocator) ![]u8
```

Deprecated; to be removed in 0.18.0. Use `std.zig.target.hurdTuple` instead.

### `linuxTripleSimple`

```zig
pub fn linuxTripleSimple(allocator: Allocator, arch: Cpu.Arch, os_tag: Os.Tag, abi: Abi) ![]u8
```

Deprecated; to be removed in 0.18.0. Use `std.zig.target.linuxTripleSimple` instead.

### `linuxTriple`

```zig
pub fn linuxTriple(target: *const Target, allocator: Allocator) ![]u8
```

Deprecated; to be removed in 0.18.0. Use `std.zig.target.linuxTriple` instead.

### `exeFileExt`

```zig
pub fn exeFileExt(target: *const Target) [:0]const u8
```


### `staticLibSuffix`

```zig
pub fn staticLibSuffix(target: *const Target) [:0]const u8
```


### `dynamicLibSuffix`

```zig
pub fn dynamicLibSuffix(target: *const Target) [:0]const u8
```


### `libPrefix`

```zig
pub fn libPrefix(target: *const Target) [:0]const u8
```


### `isMinGW`

```zig
pub inline fn isMinGW(target: *const Target) bool
```


### `isGnuLibC`

```zig
pub inline fn isGnuLibC(target: *const Target) bool
```


### `isMuslLibC`

```zig
pub inline fn isMuslLibC(target: *const Target) bool
```


### `isBionicLibC`

```zig
pub inline fn isBionicLibC(target: *const Target) bool
```


### `isDarwinLibC`

```zig
pub inline fn isDarwinLibC(target: *const Target) bool
```


### `isFreeBSDLibC`

```zig
pub inline fn isFreeBSDLibC(target: *const Target) bool
```


### `isNetBSDLibC`

```zig
pub inline fn isNetBSDLibC(target: *const Target) bool
```


### `isOpenBSDLibC`

```zig
pub inline fn isOpenBSDLibC(target: *const Target) bool
```


### `isWasiLibC`

```zig
pub inline fn isWasiLibC(target: *const Target) bool
```


### `requiresLibC`

```zig
pub fn requiresLibC(target: *const Target) bool
```

Does this target require linking libc? This may be the case if the target has an unstable
syscall interface, for example.

### `supportsAddressSpace`

```zig
pub fn supportsAddressSpace(target: Target, address_space: std.builtin.AddressSpace, context: ?AddressSpaceContext, ) bool
```

Returns whether this target supports `address_space`. If `context` is `null`, this
function simply answers the general question of whether the target has any concept
of `address_space`; if non-`null`, the function additionally checks whether
`address_space` is valid in that context.

### `standardDynamicLinkerPath`

```zig
pub fn standardDynamicLinkerPath(target: *const Target) DynamicLinker
```


### `ptrBitWidth_cpu_abi`

```zig
pub fn ptrBitWidth_cpu_abi(cpu: Cpu, abi: Abi) u16
```


### `ptrBitWidth_arch_abi`

```zig
pub fn ptrBitWidth_arch_abi(cpu_arch: Cpu.Arch, abi: Abi) u16
```


### `ptrBitWidth`

```zig
pub fn ptrBitWidth(target: *const Target) u16
```


### `stackAlignment`

```zig
pub fn stackAlignment(target: *const Target) u16
```


### `stackGrowth`

```zig
pub fn stackGrowth(target: *const Target) StackGrowth
```


### `cCharSignedness`

```zig
pub fn cCharSignedness(target: *const Target) ?std.builtin.Signedness
```

Default signedness of `char` for the native C compiler for this target
Note that char signedness is implementation-defined and many compilers provide
an option to override the default signedness e.g. GCC's -funsigned-char / -fsigned-char
Returns `null` if no C ABI is defined for this target.

### `cTypeByteSize`

```zig
pub fn cTypeByteSize(t: *const Target, c_type: CType) ?u16
```

Returns `null` if no C ABI is defined for this target.

### `cTypeBitSize`

```zig
pub fn cTypeBitSize(target: *const Target, c_type: CType) ?u16
```

Returns `null` if no C ABI is defined for this target.

### `cTypeAlignment`

```zig
pub fn cTypeAlignment(target: *const Target, c_type: CType) ?u16
```

Returns `null` if no C ABI is defined for this target.

### `cMaxIntAlignment`

```zig
pub fn cMaxIntAlignment(target: *const Target) u16
```


### `cCallingConvention`

```zig
pub fn cCallingConvention(target: *const Target) ?std.builtin.CallingConvention
```


## Constants & Variables

- **`Query`**: 
- **`aarch64`**: 
- **`alpha`**: 
- **`amdgcn`**: 
- **`arc`**: 
- **`arm`**: 
- **`avr`**: 
- **`bpf`**: 
- **`csky`**: 
- **`hexagon`**: 
- **`hppa`**: 
- **`kalimba`**: 
- **`kvx`**: 
- **`lanai`**: 
- **`loongarch`**: 
- **`m68k`**: 
- **`m88k`**: 
- **`microblaze`**: 
- **`mips`**: 
- **`msp430`**: 
- **`nvptx`**: 
- **`or1k`**: 
- **`powerpc`**: 
- **`propeller`**: 
- **`riscv`**: 
- **`s390x`**: 
- **`sh`**: 
- **`sparc`**: 
- **`spirv`**: 
- **`spork8`**: 
- **`ve`**: 
- **`wasm`**: 
- **`x86`**: 
- **`xcore`**: 
- **`xtensa`**: 
- **`z80`**: 

