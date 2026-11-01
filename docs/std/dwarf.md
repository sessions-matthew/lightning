# `std.dwarf`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/dwarf.zig`  
> [← Back to Standard Library Index](README.md)

DWARF debugging data format.

This namespace contains unopinionated types and data definitions only. For
an implementation of parsing and caching DWARF information, see
`std.debug.Dwarf`.

## Types

### `Format`


### Fields

- `@"32"`
  
- `@"64"`
  

### `CC`


### Fields

- `normal = 0x1`
  
- `program = 0x2`
  
- `nocall = 0x3`
  
- `pass_by_reference = 0x4`
  
- `pass_by_value = 0x5`
  
- `GNU_renesas_sh = 0x40`
  
- `GNU_borland_fastcall_i386 = 0x41`
  
- `BORLAND_safecall = 0xb0`
  
- `BORLAND_stdcall = 0xb1`
  
- `BORLAND_pascal = 0xb2`
  
- `BORLAND_msfastcall = 0xb3`
  
- `BORLAND_msreturn = 0xb4`
  
- `BORLAND_thiscall = 0xb5`
  
- `BORLAND_fastcall = 0xb6`
  
- `LLVM_vectorcall = 0xc0`
  
- `LLVM_Win64 = 0xc1`
  
- `LLVM_X86_64SysV = 0xc2`
  
- `LLVM_AAPCS = 0xc3`
  
- `LLVM_AAPCS_VFP = 0xc4`
  
- `LLVM_IntelOclBicc = 0xc5`
  
- `LLVM_SpirFunction = 0xc6`
  
- `LLVM_OpenCLKernel = 0xc7`
  
- `LLVM_Swift = 0xc8`
  
- `LLVM_PreserveMost = 0xc9`
  
- `LLVM_PreserveAll = 0xca`
  
- `LLVM_X86RegCall = 0xcb`
  
- `LLVM_M68kRTD = 0xcc`
  
- `LLVM_PreserveNone = 0xcd`
  
- `LLVM_RISCVVectorCall = 0xce`
  
- `LLVM_SwiftTail = 0xcf`
  

### Constants & Variables

- **`lo_user`**: 
- **`hi_user`**: 

## Namespaces

- **`LLE`**: 
- **`CFA`**: 
- **`CHILDREN`**: 
- **`LNS`**: 
- **`LNE`**: 
- **`UT`**: 
- **`LNCT`**: 
- **`RLE`**: 
- **`ACCESS`**: 

## Constants & Variables

- **`TAG`**: 
- **`AT`**: 
- **`OP`**: 
- **`LANG`**: 
- **`FORM`**: 
- **`ATE`**: 
- **`EH`**: 

