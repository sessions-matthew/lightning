# `std.lang`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/lang.zig`  
> [← Back to Standard Library Index](README.md)

Types and values provided by the Zig language.

## Types

### `StackTrace`

This data structure is used by the Zig language code generation and
therefore must be kept in sync with the compiler implementation.

### Fields

- `index: usize`
  
- `instruction_addresses: []usize`
  

### `GlobalLinkage`

This data structure is used by the Zig language code generation and
therefore must be kept in sync with the compiler implementation.

### Fields

- `strong`
  
- `weak`
  

### `SymbolVisibility`

This data structure is used by the Zig language code generation and
therefore must be kept in sync with the compiler implementation.

### Fields

- `default`
  
- `hidden`
  
- `protected`
  

### `AtomicOrder`

This data structure is used by the Zig language code generation and
therefore must be kept in sync with the compiler implementation.

### Fields

- `unordered`
  
- `monotonic`
  
- `acquire`
  
- `release`
  
- `acq_rel`
  
- `seq_cst`
  

### `ReduceOp`

This data structure is used by the Zig language code generation and
therefore must be kept in sync with the compiler implementation.

### Fields

- `And`
  
- `Or`
  
- `Xor`
  
- `Min`
  
- `Max`
  
- `Add`
  
- `Mul`
  

### `AtomicRmwOp`

This data structure is used by the Zig language code generation and
therefore must be kept in sync with the compiler implementation.

### Fields

- `Xchg`
  Exchange - store the operand unmodified.
  Supports enums, integers, and floats.
- `Add`
  Add operand to existing value.
  Supports integers and floats.
  For integers, two's complement wraparound applies.
- `Sub`
  Subtract operand from existing value.
  Supports integers and floats.
  For integers, two's complement wraparound applies.
- `And`
  Perform bitwise AND on existing value with operand.
  Supports integers.
- `Nand`
  Perform bitwise NAND on existing value with operand.
  Supports integers.
- `Or`
  Perform bitwise OR on existing value with operand.
  Supports integers.
- `Xor`
  Perform bitwise XOR on existing value with operand.
  Supports integers.
- `Max`
  Store operand if it is larger than the existing value.
  Supports integers and floats.
- `Min`
  Store operand if it is smaller than the existing value.
  Supports integers and floats.

### `CodeModel`

The code model puts constraints on the location of symbols and the size of code and data.
The selection of a code model is a trade off on speed and restrictions that needs to be selected on a per application basis to meet its requirements.
A slightly more detailed explanation can be found in (for example) the [System V Application Binary Interface (x86_64)](https://github.com/hjl-tools/x86-psABI/wiki/x86-64-psABI-1.0.pdf) 3.5.1.

This data structure is used by the Zig language code generation and
therefore must be kept in sync with the compiler implementation.

### Fields

- `default`
  
- `extreme`
  
- `kernel`
  
- `large`
  
- `medany`
  
- `medium`
  
- `medlow`
  
- `medmid`
  
- `normal`
  
- `small`
  
- `tiny`
  

### `Optimize`

This data structure is used by the Zig language code generation and
therefore must be kept in sync with the compiler implementation.

### Fields

- `debug`
  Safety checks enabled. Optimize for bug detection, accurate debug info,
  and compilation speed (in that order).
- `safe`
  Safety checks enabled. Optimize for runtime performance.
- `fast`
  Safety checks disabled. Optimize for runtime performance.
- `small`
  Safety checks disabled. Optimize for machine code size, then runtime performance.

### Functions

#### `fromString`

```zig
pub fn fromString(s: []const u8) ?@This()
```

Deprecated, to be removed after 0.18.0

#### `runtimeSafety`

```zig
pub fn runtimeSafety(o: @This()) bool
```

Returns whether illegal behavior safety checks are enabled based on the
provided optimization mode.

### Constants & Variables

- **`Debug`**: Deprecated, to be removed after 0.18.0
- **`ReleaseSafe`**: Deprecated, to be removed after 0.18.0
- **`ReleaseFast`**: Deprecated, to be removed after 0.18.0
- **`ReleaseSmall`**: Deprecated, to be removed after 0.18.0

### `CallingConvention`

The calling convention of a function defines how arguments and return values are passed, as well
as any other requirements which callers and callees must respect, such as register preservation
and stack alignment.

This data structure is used by the Zig language code generation and
therefore must be kept in sync with the compiler implementation.

### Fields

- `auto`
  The default Zig calling convention when neither `export` nor `inline` is specified.
  This calling convention makes no guarantees about stack alignment, registers, etc.
  It can only be used within this Zig compilation unit.
- `async`
  The calling convention of a function that can be called with `async` syntax. An `async` call
  of a runtime-known function must target a function with this calling convention.
  Comptime-known functions with other calling conventions may be coerced to this one.
- `naked`
  Functions with this calling convention have no prologue or epilogue, making the function
  uncallable in regular Zig code. This can be useful when integrating with assembly.
- `@"inline"`
  This calling convention is exactly equivalent to using the `inline` keyword on a function
  definition. This function will be semantically inlined by the Zig compiler at call sites.
  Pointers to inline functions are comptime-only.
- `x86_64_sysv: CommonOptions`
  
- `x86_64_x32: CommonOptions`
  
- `x86_64_win: CommonOptions`
  
- `x86_64_regcall_v3_sysv: CommonOptions`
  
- `x86_64_regcall_v4_win: CommonOptions`
  
- `x86_64_vectorcall: CommonOptions`
  
- `x86_64_interrupt: CommonOptions`
  
- `x86_64_preserve_none: CommonOptions`
  
- `x86_sysv: X86RegparmOptions`
  
- `x86_win: X86RegparmOptions`
  
- `x86_mingw: X86RegparmOptions`
  
- `x86_stdcall: X86RegparmOptions`
  
- `x86_fastcall: CommonOptions`
  
- `x86_thiscall: CommonOptions`
  
- `x86_thiscall_mingw: CommonOptions`
  
- `x86_regcall_v3: CommonOptions`
  
- `x86_regcall_v4_win: CommonOptions`
  
- `x86_vectorcall: CommonOptions`
  
- `x86_interrupt: CommonOptions`
  
- `x86_16_cdecl: CommonOptions`
  
- `x86_16_stdcall: CommonOptions`
  
- `x86_16_regparmcall: CommonOptions`
  
- `x86_16_interrupt: CommonOptions`
  
- `aarch64_aapcs: CommonOptions`
  
- `aarch64_aapcs_darwin: CommonOptions`
  
- `aarch64_aapcs_win: CommonOptions`
  
- `aarch64_vfabi: CommonOptions`
  
- `aarch64_vfabi_sve: CommonOptions`
  
- `aarch64_preserve_none: CommonOptions`
  
- `alpha_osf: CommonOptions`
  The standard `alpha` calling convention.
- `arm_aapcs: CommonOptions`
  ARM Architecture Procedure Call Standard
- `arm_aapcs_vfp: CommonOptions`
  ARM Architecture Procedure Call Standard Vector Floating-Point
- `arm_interrupt: ArmInterruptOptions`
  
- `mips64_n64: CommonOptions`
  
- `mips64_n32: CommonOptions`
  
- `mips64_interrupt: MipsInterruptOptions`
  
- `mips_o32: CommonOptions`
  
- `mips_interrupt: MipsInterruptOptions`
  
- `riscv64_lp64: CommonOptions`
  
- `riscv64_lp64_v: CommonOptions`
  
- `riscv64_interrupt: RiscvInterruptOptions`
  
- `riscv32_ilp32: CommonOptions`
  
- `riscv32_ilp32_v: CommonOptions`
  
- `riscv32_interrupt: RiscvInterruptOptions`
  
- `sparc64_sysv: CommonOptions`
  
- `sparc_sysv: CommonOptions`
  
- `powerpc64_elf: CommonOptions`
  
- `powerpc64_elf_altivec: CommonOptions`
  
- `powerpc64_elf_v2: CommonOptions`
  
- `powerpc_sysv: CommonOptions`
  
- `powerpc_sysv_altivec: CommonOptions`
  
- `powerpc_aix: CommonOptions`
  
- `powerpc_aix_altivec: CommonOptions`
  
- `wasm_mvp: CommonOptions`
  The standard `wasm32` and `wasm64` calling convention, as specified in the WebAssembly Tool Conventions.
- `arc_sysv: CommonOptions`
  The standard `arc`/`arceb` calling convention.
- `arc_interrupt: ArcInterruptOptions`
  
- `avr_gnu`
  
- `avr_builtin`
  
- `avr_signal`
  
- `avr_interrupt`
  
- `bpf_std: CommonOptions`
  The standard `bpfel`/`bpfeb` calling convention.
- `csky_sysv: CommonOptions`
  
- `csky_interrupt: CommonOptions`
  
- `hexagon_sysv: CommonOptions`
  
- `hexagon_sysv_hvx: CommonOptions`
  
- `hppa_elf: CommonOptions`
  The standard `hppa` calling convention.
- `hppa64_elf: CommonOptions`
  The standard `hppa64` calling convention.
- `kvx_lp64: CommonOptions`
  
- `kvx_ilp32: CommonOptions`
  
- `lanai_sysv: CommonOptions`
  The standard `lanai` calling convention.
- `loongarch64_lp64: CommonOptions`
  The standard `loongarch64` calling convention.
- `loongarch32_ilp32: CommonOptions`
  The standard `loongarch32` calling convention.
- `m68k_sysv: CommonOptions`
  
- `m68k_gnu: CommonOptions`
  
- `m68k_rtd: CommonOptions`
  
- `m68k_interrupt: CommonOptions`
  
- `m88k_sysv: CommonOptions`
  
- `microblaze_std: CommonOptions`
  The standard `microblaze`/`microblazeel` calling convention.
- `microblaze_interrupt: MicroblazeInterruptOptions`
  
- `msp430_eabi: CommonOptions`
  The standard `msp430` calling convention.
- `msp430_interrupt: CommonOptions`
  
- `or1k_sysv: CommonOptions`
  The standard `or1k` calling convention.
- `propeller_sysv: CommonOptions`
  The standard `propeller` calling convention.
- `s390x_sysv: CommonOptions`
  
- `s390x_sysv_vx: CommonOptions`
  
- `sh_gnu: CommonOptions`
  
- `sh_renesas: CommonOptions`
  
- `sh_interrupt: ShInterruptOptions`
  
- `ve_sysv: CommonOptions`
  The standard `ve` calling convention.
- `xcore_xs1: CommonOptions`
  
- `xcore_xs2: CommonOptions`
  
- `xtensa_call0: CommonOptions`
  
- `xtensa_windowed: CommonOptions`
  
- `amdgcn_device: CommonOptions`
  
- `amdgcn_kernel`
  
- `amdgcn_cs: CommonOptions`
  
- `nvptx_device`
  
- `nvptx_kernel`
  
- `spirv_device`
  
- `spirv_vertex`
  
- `spirv_kernel: SpirvKernelOptions`
  
- `spirv_fragment: SpirvFragmentOptions`
  
- `spirv_task: SpirvKernelOptions`
  
- `spirv_mesh: SpirvMeshOptions`
  
- `ez80_cet`
  
- `ez80_tiflags`
  
- `spork8`
  

### Types

#### `CommonOptions`

Options shared across most calling conventions.

#### `X86RegparmOptions`

Options for x86 calling conventions which support the regparm attribute to pass some
arguments in registers.

#### `ArcInterruptOptions`

Options for the `arc_interrupt` calling convention.

#### `ArmInterruptOptions`

Options for the `arm_interrupt` calling convention.

#### `MicroblazeInterruptOptions`

Options for the `microblaze_interrupt` calling convention.

#### `MipsInterruptOptions`

Options for the `mips_interrupt` and `mips64_interrupt` calling conventions.

#### `RiscvInterruptOptions`

Options for the `riscv32_interrupt` and `riscv64_interrupt` calling conventions.

#### `ShInterruptOptions`

Options for the `sh_interrupt` calling convention.

#### `SpirvKernelOptions`


#### `SpirvFragmentOptions`


#### `SpirvMeshOptions`


### Functions

#### `archs`

```zig
pub fn archs(cc: CallingConvention) []const std.Target.Cpu.Arch
```

Returns the array of `std.Target.Cpu.Arch` to which this `CallingConvention` applies.
Asserts that `cc` is not `.auto`, `.@"async"`, `.naked`, or `.@"inline"`.

#### `eql`

```zig
pub fn eql(a: CallingConvention, b: CallingConvention) bool
```


#### `withStackAlign`

```zig
pub fn withStackAlign(cc: CallingConvention, incoming_stack_alignment: u64) CallingConvention
```


### Constants & Variables

- **`Tag`**: 
- **`c`**: This is an alias for the default C calling convention for this target.
- **`winapi`**: 
- **`kernel`**: 

### `AddressSpace`

This data structure is used by the Zig language code generation and
therefore must be kept in sync with the compiler implementation.

### Fields

- `generic`
  
- `gs`
  
- `fs`
  
- `ss`
  
- `far`
  Allows addressing the entire address space by storing both segment and offset.
- `global`
  
- `constant`
  
- `param`
  
- `shared`
  
- `local`
  
- `private`
  
- `input`
  
- `output`
  
- `uniform`
  
- `push_constant`
  
- `storage_buffer`
  
- `physical_storage_buffer`
  
- `flash`
  
- `flash1`
  
- `flash2`
  
- `flash3`
  
- `flash4`
  
- `flash5`
  
- `cog`
  This address space only addresses the cog-local ram.
- `hub`
  This address space only addresses shared hub ram.
- `lut`
  This address space only addresses the "lookup" ram
- `externref`
  
- `funcref`
  

### `SourceLocation`

This data structure is used by the Zig language code generation and
therefore must be kept in sync with the compiler implementation.

### Fields

- `module: [:0]const u8`
  The name chosen when compiling. Not a file path.
- `file: [:0]const u8`
  Relative to the root directory of its module.
- `fn_name: [:0]const u8`
  
- `line: u32`
  
- `column: u32`
  

### `TypeId`


### `Type`

This data structure is used by the Zig language code generation and
therefore must be kept in sync with the compiler implementation.

### Fields

- `type`
  
- `void`
  
- `bool`
  
- `noreturn`
  
- `int: Int`
  
- `float: Float`
  
- `pointer: Pointer`
  
- `array: Array`
  
- `@"struct": Struct`
  
- `comptime_float`
  
- `comptime_int`
  
- `undefined`
  
- `null`
  
- `optional: Optional`
  
- `error_union: ErrorUnion`
  
- `error_set: ErrorSet`
  
- `@"enum": Enum`
  
- `@"union": Union`
  
- `@"fn": Fn`
  
- `@"opaque": Opaque`
  
- `frame: Frame`
  
- `@"anyframe": AnyFrame`
  
- `vector: Vector`
  
- `enum_literal`
  
- `spirv: Spirv`
  

### Types

#### `Int`

This data structure is used by the Zig language code generation and
therefore must be kept in sync with the compiler implementation.

#### `Float`

This data structure is used by the Zig language code generation and
therefore must be kept in sync with the compiler implementation.

#### `Pointer`

This data structure is used by the Zig language code generation and
therefore must be kept in sync with the compiler implementation.

#### `Array`

This data structure is used by the Zig language code generation and
therefore must be kept in sync with the compiler implementation.

#### `ContainerLayout`

This data structure is used by the Zig language code generation and
therefore must be kept in sync with the compiler implementation.

#### `Struct`

This data structure is used by the Zig language code generation and
therefore must be kept in sync with the compiler implementation.

#### `Optional`

This data structure is used by the Zig language code generation and
therefore must be kept in sync with the compiler implementation.

#### `ErrorUnion`

This data structure is used by the Zig language code generation and
therefore must be kept in sync with the compiler implementation.

#### `ErrorSet`

This data structure is used by the Zig language code generation and
therefore must be kept in sync with the compiler implementation.

#### `Enum`

This data structure is used by the Zig language code generation and
therefore must be kept in sync with the compiler implementation.

#### `Union`

This data structure is used by the Zig language code generation and
therefore must be kept in sync with the compiler implementation.

#### `Fn`

This data structure is used by the Zig language code generation and
therefore must be kept in sync with the compiler implementation.

#### `Spirv`

This data structure is used by the Zig language code generation and
therefore must be kept in sync with the compiler implementation.

#### `Opaque`

This data structure is used by the Zig language code generation and
therefore must be kept in sync with the compiler implementation.

#### `Frame`

This data structure is used by the Zig language code generation and
therefore must be kept in sync with the compiler implementation.

#### `AnyFrame`

This data structure is used by the Zig language code generation and
therefore must be kept in sync with the compiler implementation.

#### `Vector`

This data structure is used by the Zig language code generation and
therefore must be kept in sync with the compiler implementation.

### `FloatMode`

This data structure is used by the Zig language code generation and
therefore must be kept in sync with the compiler implementation.

### Fields

- `strict`
  
- `optimized`
  

### `Endian`

This data structure is used by the Zig language code generation and
therefore must be kept in sync with the compiler implementation.

### Fields

- `big`
  
- `little`
  

### Constants & Variables

- **`native`**: 
- **`foreign`**: 

### `Signedness`

This data structure is used by the Zig language code generation and
therefore must be kept in sync with the compiler implementation.

### Fields

- `signed`
  
- `unsigned`
  

### `OutputMode`

This data structure is used by the Zig language code generation and
therefore must be kept in sync with the compiler implementation.

### Fields

- `Exe`
  
- `Lib`
  
- `Obj`
  

### `LinkMode`

This data structure is used by the Zig language code generation and
therefore must be kept in sync with the compiler implementation.

### Fields

- `static`
  
- `dynamic`
  

### `UnwindTables`

This data structure is used by the Zig language code generation and
therefore must be kept in sync with the compiler implementation.

### Fields

- `none`
  
- `sync`
  
- `async`
  

### `WasiExecModel`

This data structure is used by the Zig language code generation and
therefore must be kept in sync with the compiler implementation.

### Fields

- `command`
  
- `reactor`
  

### `CallModifier`

This data structure is used by the Zig language code generation and
therefore must be kept in sync with the compiler implementation.

### Fields

- `auto`
  Equivalent to function call syntax.
- `never_tail`
  Prevents tail call optimization. This guarantees that the return
  address will point to the callsite, as opposed to the callsite's
  callsite. If the call is otherwise required to be tail-called
  or inlined, a compile error is emitted instead.
- `never_inline`
  Guarantees that the call will not be inlined. If the call is
  otherwise required to be inlined, a compile error is emitted instead.
- `no_suspend`
  Asserts that the function call will not suspend. This allows a
  non-async function to call an async function.
- `always_tail`
  Guarantees that the call will be generated with tail call optimization.
  If this is not possible, a compile error is emitted instead.
- `always_inline`
  Guarantees that the call will be inlined at the callsite.
  If this is not possible, a compile error is emitted instead.
- `compile_time`
  Evaluates the call at compile-time. If the call cannot be completed at
  compile-time, a compile error is emitted instead.

### `VaListAarch64`

This data structure is used by the Zig language code generation and
therefore must be kept in sync with the compiler implementation.

### Fields

- `__stack: *anyopaque`
  
- `__gr_top: *anyopaque`
  
- `__vr_top: *anyopaque`
  
- `__gr_offs: c_int`
  
- `__vr_offs: c_int`
  

### `VaListAlpha`

This data structure is used by the Zig language code generation and
therefore must be kept in sync with the compiler implementation.

### Fields

- `__base: *anyopaque`
  
- `__offset: c_int`
  

### `VaListArm`

This data structure is used by the Zig language code generation and
therefore must be kept in sync with the compiler implementation.

### Fields

- `__ap: *anyopaque`
  

### `VaListHexagon`

This data structure is used by the Zig language code generation and
therefore must be kept in sync with the compiler implementation.

### Fields

- `__current_saved_reg_area_pointer: *anyopaque`
  
- `__saved_reg_area_end_pointer: *anyopaque`
  
- `__overflow_area_pointer: *anyopaque`
  

### `VaListPowerPc`

This data structure is used by the Zig language code generation and
therefore must be kept in sync with the compiler implementation.

### Fields

- `gpr: u8`
  
- `fpr: u8`
  
- `reserved: c_ushort`
  
- `overflow_arg_area: *anyopaque`
  
- `reg_save_area: *anyopaque`
  

### `VaListS390x`

This data structure is used by the Zig language code generation and
therefore must be kept in sync with the compiler implementation.

### Fields

- `__gpr: c_long`
  
- `__fpr: c_long`
  
- `__overflow_arg_area: *anyopaque`
  
- `__reg_save_area: *anyopaque`
  

### `VaListSh`

This data structure is used by the Zig language code generation and
therefore must be kept in sync with the compiler implementation.

### Fields

- `__va_next_o: *anyopaque`
  
- `__va_next_o_limit: *anyopaque`
  
- `__va_next_fp: *anyopaque`
  
- `__va_next_fp_limit: *anyopaque`
  
- `__va_next_stack: *anyopaque`
  

### `VaListX86_64`

This data structure is used by the Zig language code generation and
therefore must be kept in sync with the compiler implementation.

### Fields

- `gp_offset: c_uint`
  
- `fp_offset: c_uint`
  
- `overflow_arg_area: *anyopaque`
  
- `reg_save_area: *anyopaque`
  

### `VaListXtensa`

This data structure is used by the Zig language code generation and
therefore must be kept in sync with the compiler implementation.

### Fields

- `__va_stk: *c_int`
  
- `__va_reg: *c_int`
  
- `__va_ndx: c_int`
  

### `VaList`

This data structure is used by the Zig language code generation and
therefore must be kept in sync with the compiler implementation.

### `PrefetchOptions`

This data structure is used by the Zig language code generation and
therefore must be kept in sync with the compiler implementation.

### Fields

- `rw: Rw = .read`
  Whether the prefetch should prepare for a read or a write.
- `locality: u2 = 3`
  The data's locality in an inclusive range from 0 to 3.
  
  0 means no temporal locality. That is, the data can be immediately
  dropped from the cache after it is accessed.
  
  3 means high temporal locality. That is, the data should be kept in
  the cache as it is likely to be accessed again soon.
- `cache: Cache = .data`
  The cache that the prefetch should be performed on.

### Types

#### `Rw`


#### `Cache`


### `ExportOptions`

This data structure is used by the Zig language code generation and
therefore must be kept in sync with the compiler implementation.

### Fields

- `name: []const u8`
  
- `linkage: GlobalLinkage = .strong`
  
- `section: ?[]const u8 = null`
  
- `visibility: SymbolVisibility = .default`
  

### `ExternOptions`

This data structure is used by the Zig language code generation and
therefore must be kept in sync with the compiler implementation.

### Fields

- `name: []const u8`
  
- `library_name: ?[]const u8 = null`
  
- `linkage: GlobalLinkage = .strong`
  
- `visibility: SymbolVisibility = .default`
  
- `is_thread_local: bool = false`
  Setting this to `true` makes the `@extern` a runtime value.
- `is_dll_import: bool = false`
  
- `relocation: Relocation = .any`
  
- `decoration: ?Decoration = null`
  

### Types

#### `Decoration`


#### `Relocation`


### `BranchHint`

This data structure is used by the Zig language code generation and
therefore must be kept in sync with the compiler implementation.

### Fields

- `none`
  Equivalent to no hint given.
- `likely`
  This branch of control flow is more likely to be reached than its peers.
  The optimizer should optimize for reaching it.
- `unlikely`
  This branch of control flow is less likely to be reached than its peers.
  The optimizer should optimize for not reaching it.
- `cold`
  This branch of control flow is unlikely to *ever* be reached.
  The optimizer may place it in a different page of memory to optimize other branches.
- `unpredictable`
  It is difficult to predict whether this branch of control flow will be reached.
  The optimizer should avoid branching behavior with expensive mispredictions.

### `CompilerBackend`

This enum is set by the compiler and communicates which compiler
implementation is used to produce machine code.

In theory, Zig code should be agnostic to the backend that implements the
language. The only reason to observe this value is to **work around
problems with compiler implementations.**

A common pitful is failing the compilation if the compiler backend does not
match a whitelist of backends; a more resilient strategy is to detect that
a known problem would occur in a blacklist of backends.

The enum is nonexhaustive so that alternate Zig language implementations
may choose a random number as their tag, thereby avoiding conflicts with
other implementations, and codebases can interact with these values even if
this upstream enum does not have a name for the number. Of course, upstream
is happy to accept patches to add additional Zig implementations to this
enum.

This data structure is part of the Zig language specification.

### Fields

- `other = 0`
  It is allowed for a compiler implementation to not reveal its identity,
  in which case this value is appropriate. Be cool and make sure your
  code supports `other` Zig compilers!
- `stage1 = 1`
  The original Zig compiler created in 2015 by Andrew Kelley. Implemented
  in C++. Used LLVM. Deleted from the ZSF ziglang/zig codebase on
  December 6th, 2022.
- `stage2_llvm = 2`
  The reference implementation self-hosted compiler of Zig, using the
  LLVM backend.
- `stage2_c = 3`
  The reference implementation self-hosted compiler of Zig, using the
  backend that generates C source code.
  
  Note that one can observe whether the compilation will output C code
  directly with `object_format` value rather than the `compiler_backend` value.
- `stage2_wasm = 4`
  The reference implementation self-hosted compiler of Zig, using the
  WebAssembly backend.
- `stage2_arm = 5`
  The reference implementation self-hosted compiler of Zig, using the
  arm backend.
- `stage2_x86_64 = 6`
  The reference implementation self-hosted compiler of Zig, using the
  x86_64 backend.
- `stage2_aarch64 = 7`
  The reference implementation self-hosted compiler of Zig, using the
  aarch64 backend.
- `stage2_x86 = 8`
  The reference implementation self-hosted compiler of Zig, using the
  x86 backend.
- `stage2_riscv64 = 9`
  The reference implementation self-hosted compiler of Zig, using the
  riscv64 backend.
- `stage2_sparc64 = 10`
  The reference implementation self-hosted compiler of Zig, using the
  sparc64 backend.
- `stage2_spirv = 11`
  The reference implementation self-hosted compiler of Zig, using the
  spirv backend.
- `stage2_powerpc = 12`
  The reference implementation self-hosted compiler of Zig, using the
  powerpc backend.
- `stage2_loongarch = 13`
  The reference implementation self-hosted compiler of Zig, using the
  loongarch backend.
- `zsf_spork8 = 14`
  The Zig Software Foundation self-hosted implementation of Zig. Backend
  originally contributed by Ben Anderman in 2026.
- `_`
  

### `TestFn`

This function type is used by the Zig language code generation and
therefore must be kept in sync with the compiler implementation.

### Fields

- `name: []const u8`
  
- `func: *const fn () anyerror!void`
  

## Functions

### `returnError`

```zig
pub noinline fn returnError() void
```


## Constants & Variables

- **`assembly`**: 
- **`OptimizeMode`**: Deprecated, to be removed after 0.18.0
- **`panic`**: This namespace is used by the Zig compiler to emit various kinds of safety

