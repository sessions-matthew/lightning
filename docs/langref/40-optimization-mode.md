# Optimization Mode

> Zig 0.17.0 Language Reference — Section 40 of 53  
> [← Back to Language Reference Index](../langref.md)

<a id="Optimization-Mode"></a>
## Optimization Mode

Zig has four optimization modes:

- [debug](#debug) (default)
- [fast](#fast)
- [safe](#safe)
- [small](#small)

To add standard build options to a `build.zig` file:

**`build.zig`**
```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const exe = b.addExecutable(.{
        .name = "example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("example.zig"),
            .optimize = optimize,
        }),
    });
    b.default_step.dependOn(&exe.step);
}
```

This causes these options to be available:

- **`-Doptimize=debug`**: Optimizations off and safety on (default)
- **`-Doptimize=safe`**: Optimizations on and safety on
- **`-Doptimize=fast`**: Optimizations on and safety off
- **`-Doptimize=small`**: Size optimizations on and safety off

<a id="debug"></a>
### debug

```sh
$ zig build-exe example.zig
```

- Fast compilation speed
- Safety checks enabled
- Slow runtime performance
- Large binary size
- No reproducible build requirement

<a id="fast"></a>
### fast

```sh
$ zig build-exe example.zig -Ofast
```

- Fast runtime performance
- Safety checks disabled
- Slow compilation speed
- Large binary size
- Reproducible build

<a id="safe"></a>
### safe

```sh
$ zig build-exe example.zig -Osafe
```

- Medium runtime performance
- Safety checks enabled
- Slow compilation speed
- Large binary size
- Reproducible build

<a id="small"></a>
### small

```sh
$ zig build-exe example.zig -Osmall
```

- Medium runtime performance
- Safety checks disabled
- Slow compilation speed
- Small binary size
- Reproducible build

See also:

- [Compile Variables](#Compile-Variables)
- [Zig Build System](#Zig-Build-System)
- [Illegal Behavior](#Illegal-Behavior)
