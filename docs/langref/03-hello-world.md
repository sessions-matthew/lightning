# Hello World

> Zig 0.17.0 Language Reference — Section 3 of 53  
> [← Back to Language Reference Index](../langref.md)

<a id="Hello-World"></a>
## Hello World

**`hello.zig`**
```zig
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    try std.Io.File.stdout().writeStreamingAll(init.io, "Hello, World!\n");
}
```

```sh
$ zig build-exe hello.zig
$ ./hello
Hello, World!
```

Most of the time, it is more appropriate to write to stderr rather than stdout, and
whether or not the message is successfully written to the stream is irrelevant.
Also, formatted printing often comes in handy. For this common case,
there is a simpler API:

**`hello_again.zig`**
```zig
const std = @import("std");

pub fn main() void {
    std.debug.print("Hello, {s}!\n", .{"World"});
}
```

```sh
$ zig build-exe hello_again.zig
$ ./hello_again
Hello, World!
```

In this case, the `!` may be omitted from the return
type of `main` because no errors are returned from the function.

See also:

- [Values](#Values)
- [Tuples](#Tuples)
- [@import](#import)
- [Errors](#Errors)
- [Entry Point](#Entry-Point)
- [Source Encoding](#Source-Encoding)
- [try](#try)
