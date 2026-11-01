# Identifiers

> Zig 0.17.0 Language Reference — Section 6 of 53  
> [← Back to Language Reference Index](../langref.md)

<a id="Identifiers"></a>
## Identifiers

Identifiers must start with an alphabetic character or underscore and may be followed
by any number of alphanumeric characters or underscores.
They must not overlap with any keywords. See [Keyword Reference](#Keyword-Reference).

<a id="String-Identifier-Syntax"></a>
### String Identifier Syntax

If a name that does not fit these requirements is needed, such as for
linking with external libraries, the `@""` syntax
may be used.

**`identifiers.zig`**
```zig
const @"identifier with spaces in it" = 0xff;
const @"1SmallStep4Man" = 112358;

const c = @import("std").c;
pub extern "c" fn @"error"() void;
pub extern "c" fn @"fstat$INODE64"(fd: c.fd_t, buf: *c.Stat) c_int;

const Color = enum {
    red,
    @"really red",
};
const color: Color = .@"really red";
```
