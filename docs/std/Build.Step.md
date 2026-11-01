# `std.Build.Step`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/Build/Step.zig`  
> [← Back to Standard Library Index](README.md)

## Fields

- `tag: Configuration.Step.Tag`
  
- `name: []const u8`
  
- `owner: *Build`
  
- `dependencies: std.ArrayList(*Step)`
  
- `max_rss: u64`
  Set this field to declare an upper bound on the amount of bytes of memory it will
  take to run the step. Zero means no limit.
  
  The idea to annotate steps that might use a high amount of RAM with an
  upper bound. For example, perhaps a particular set of unit tests require 4
  GiB of RAM, and those tests will be run under 4 different build
  configurations at once. This would potentially require 16 GiB of memory on
  the system if all 4 steps executed simultaneously, which could easily be
  greater than what is actually available, potentially causing the system to
  crash when using `zig build` at the default concurrency level.
  
  This field causes the build runner to do two things:
  1. ulimit child processes, so that they will fail if it would exceed this
  memory limit. This serves to enforce that this upper bound value is
  correct.
  2. Ensure that the set of concurrent steps at any given time have a total
  max_rss value that does not exceed the `max_total_rss` value of the build
  runner. This value is configurable on the command line, and defaults to the
  total system memory available.
- `debug_stack_trace: std.debug.StackTrace`
  The return address associated with creation of this step that can be useful
  to print along with debugging messages.

## Types

### `Type`

```zig
pub fn Type(comptime tag: Tag) type
```


### `TopLevel`


### Fields

- `step: Step`
  
- `description: []const u8`
  

### Constants & Variables

- **`base_tag`**: 

### `StepOptions`


### Fields

- `tag: Tag`
  
- `name: []const u8`
  
- `owner: *Build`
  
- `first_ret_addr: ?usize = null`
  
- `max_rss: u64 = 0`
  

## Functions

### `init`

```zig
pub fn init(options: StepOptions) Step
```


### `dependOn`

```zig
pub fn dependOn(step: *Step, other: *Step) void
```


### `cast`

```zig
pub fn cast(step: *Step, comptime T: type) ?*T
```


### `dump`

```zig
pub fn dump(step: *Step, t: std.Io.Terminal) void
```

For debugging purposes, prints identifying information about this Step.

## Constants & Variables

- **`Tag`**: 
- **`CheckFile`**: 
- **`Compile`**: 
- **`ConfigHeader`**: 
- **`Fail`**: 
- **`FindProgram`**: 
- **`Fmt`**: 
- **`InstallArtifact`**: 
- **`InstallDir`**: 
- **`InstallFile`**: 
- **`ObjCopy`**: 
- **`Options`**: 
- **`Run`**: 
- **`TranslateC`**: 
- **`UpdateSourceFiles`**: 
- **`WriteFile`**: 

