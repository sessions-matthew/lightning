# `std.Build`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/Build.zig`  
> [← Back to Standard Library Index](README.md)

## Fields

- `graph: *Graph`
  Shared state among all Build instances.
- `install_tls: Step.TopLevel`
  
- `uninstall_tls: Step.TopLevel`
  
- `allocator: Allocator`
  
- `default_step: *Step`
  
- `top_level_steps: std.array_hash_map.String(*Step.TopLevel)`
  
- `root: Cache.Path`
  Path to the directory containing build.zig.
- `debug_log_scopes: []const []const u8 = &.{}`
  
- `debug_stack_frames_count: u8 = 8`
  Number of stack frames captured when a `StackTrace` is recorded for debug purposes,
  in particular at `Step` creation.
  Set to 0 to disable stack collection.
- `user_input_options: PackageOptions.Map`
  
- `available_options_map: std.array_hash_map.String(AvailableOption) = .empty`
  
- `invalid_user_input: bool`
  
- `dep_prefix: []const u8 = ""`
  
- `modules: std.array_hash_map.String(*Module)`
  
- `named_writefiles: std.array_hash_map.String(*Step.WriteFile)`
  
- `named_lazy_paths: std.array_hash_map.String(LazyPath)`
  
- `pkg_hash: []const u8`
  The hash of this instance's package. `""` means that this is the root package.
- `available_deps: AvailableDeps`
  A mapping from dependency names to package hashes.

## Types

### `ConfigureDependency`


### Fields

- `lazy_path: LazyPath`
  
- `is_directory: bool`
  
- `metadata_only: bool`
  

### `ReleaseMode`


### Fields

- `off`
  
- `any`
  
- `fast`
  
- `safe`
  
- `small`
  

### `Graph`

Shared state among all Build instances.
Settings that are here rather than in Build are not configurable per-package.

### Fields

- `io: Io`
  
- `arena: Allocator`
  Process lifetime.
- `system_integration_options: std.array_hash_map.String(SystemLibraryMode) = .empty`
  
- `system_package_mode: bool = false`
  
- `zig_exe: []const u8`
  
- `environ_map: process.Environ.Map`
  
- `needed_lazy_dependencies: std.array_hash_map.String(void) = .empty`
  
- `host: ResolvedTarget`
  Information about the native target. Computed before build() is invoked.
- `dependency_cache: PackageInstanceMap = .empty`
  
- `allow_so_scripts: ?bool = null`
  
- `time_report: bool = false`
  
- `verbose: bool = false`
  
- `stderr_mode: ?Io.Terminal.Mode = null`
  Similar to the `Io.Terminal.Mode` returned by `Io.lockStderr`, but also
  respects the '--color' flag.
- `release_mode: ReleaseMode = .off`
  
- `generated_files: std.ArrayList(*Step)`
  Indexes correspond to `Configuration.GeneratedFileIndex`.
- `wip_configuration: Configuration.Wip`
  
- `cache_poison: CachePoison = .pure`
  
- `search_prefixes: std.ArrayList([]const u8) = .empty`
  Observing this data causes cache poisoning. See `CachePoison`.
- `configure_dependencies: ArrayList(ConfigureDependency) = .empty`
  Populated by calling one of:
  * `dependOnFileContents`
  * `dependOnFileMetadata`
  * `dependOnDirectoryContents`
  * `dependOnDirectoryMetadata`

### Types

#### `CachePoison`

If the cache is poisoned means that the **configure logic** had side
effects, or otherwise did something that could not be tracked by the
cache system.

This is not to be confused with whether individual steps may have side
effects when being evaluated; it has to do with the logic inside build.zig
itself. For example, a `Run` step that prints "hello world" has side
effects *at make time* and therefore does not warrant setting this flag,
while checking for the existence of `scdoc` *at configure time* in order to
choose the default value for a configuration option does.

Keeping the cache pure will make `zig build` faster, bypassing the
configurer process when identical configuration would be generated.

When the cache is poisoned, the maker process will delete the build
configuration file upon ingesting it since it cannot be reused.

### Functions

#### `addGeneratedFile`

```zig
pub fn addGeneratedFile(graph: *Graph, owner: *Step) Configuration.GeneratedFileIndex
```


#### `dupeString`

```zig
pub fn dupeString(graph: *const Graph, bytes: []const u8) []const u8
```


#### `dupePath`

```zig
pub fn dupePath(graph: *const Graph, bytes: []const u8) []const u8
```


#### `dupeStrings`

```zig
pub fn dupeStrings(graph: *const Graph, strings: []const []const u8) []const []const u8
```


#### `cwdRelativePath`

```zig
pub fn cwdRelativePath(graph: *Graph, sub_path: []const u8) LazyPath
```

An absolute path or a path relative to the current working directory of
the build runner process.

Use of this function indicates a dependency on the host system.

#### `path`

```zig
pub fn path(graph: *Graph, base: Configuration.LazyPath.Relative.Base, sub_path: []const u8) LazyPath
```

A path whose components and contents are known at some point during
`Step` resolution, relative to the provided base directory.

#### `alloc`

```zig
pub fn alloc(graph: *const Graph, comptime T: type, n: usize) []T
```

Allocates using the global process arena, failing the build on
allocation failure.

#### `create`

```zig
pub fn create(graph: *const Graph, comptime T: type) *T
```

Allocates using the global process arena, failing the build on
allocation failure.

#### `addBytesList`

```zig
pub fn addBytesList(graph: *Graph, bytes_list: []const []const u8) []const Configuration.Bytes
```


#### `addBytes`

```zig
pub fn addBytes(graph: *Graph, bytes: []const u8) Configuration.Bytes
```


#### `addString`

```zig
pub fn addString(graph: *Graph, bytes: []const u8) Configuration.String
```


#### `poisonCache`

```zig
pub fn poisonCache(graph: *Graph) void
```

Indicates that the **configure logic** had side effects, or otherwise
did something that could not be tracked by the cache system.

See `CachePoison` documentation for more details.

As an alternative to calling this function, consider these APIs instead:
* `dependOnFileContents`

### `SystemLibraryMode`


### Fields

- `user_disabled`
  User asked for the library to be disabled.
  The build runner has not confirmed whether the setting is recognized yet.
- `user_enabled`
  User asked for the library to be enabled.
  The build runner has not confirmed whether the setting is recognized yet.
- `declared_disabled`
  The build runner has confirmed that this setting is recognized.
  System integration with this library has been resolved to off.
- `declared_enabled`
  The build runner has confirmed that this setting is recognized.
  System integration with this library has been resolved to on.

### `ExecutableOptions`


### Fields

- `name: []const u8`
  
- `root_module: *Module`
  
- `version: ?std.SemanticVersion = null`
  
- `linkage: ?std.builtin.LinkMode = null`
  
- `max_rss: u64 = 0`
  
- `use_llvm: ?bool = null`
  
- `use_lld: ?bool = null`
  
- `zig_lib_dir: ?LazyPath = null`
  
- `win32_manifest: ?LazyPath = null`
  Deprecated. This functionality will be moved to an external package:
  https://codeberg.org/ziglang/rc
  
  Embed a `.manifest` file in the compilation if the object format supports it.
  https://learn.microsoft.com/en-us/windows/win32/sbscs/manifest-files-reference
  Manifest files must have the extension `.manifest`.
  Can be set regardless of target. The `.manifest` file will be ignored
  if the target object format does not support embedded manifests.

### `ObjectOptions`


### Fields

- `name: []const u8`
  
- `root_module: *Module`
  
- `max_rss: u64 = 0`
  
- `use_llvm: ?bool = null`
  
- `use_lld: ?bool = null`
  
- `zig_lib_dir: ?LazyPath = null`
  

### `LibraryOptions`


### Fields

- `linkage: std.builtin.LinkMode = .static`
  
- `name: []const u8`
  
- `root_module: *Module`
  
- `version: ?std.SemanticVersion = null`
  
- `max_rss: u64 = 0`
  
- `use_llvm: ?bool = null`
  
- `use_lld: ?bool = null`
  
- `zig_lib_dir: ?LazyPath = null`
  
- `win32_manifest: ?LazyPath = null`
  Deprecated. This functionality will be moved to an external package:
  https://codeberg.org/ziglang/rc
  
  Embed a `.manifest` file in the compilation if the object format supports it.
  https://learn.microsoft.com/en-us/windows/win32/sbscs/manifest-files-reference
  Manifest files must have the extension `.manifest`.
  Can be set regardless of target. The `.manifest` file will be ignored
  if the target object format does not support embedded manifests.
- `win32_module_definition: ?LazyPath = null`
  Win32 module definition file (.def).

### `TestOptions`


### Fields

- `name: []const u8 = "test"`
  
- `root_module: *Module`
  
- `max_rss: u64 = 0`
  
- `filters: []const []const u8 = &.{}`
  
- `test_runner: ?Step.Compile.TestRunner = null`
  
- `use_llvm: ?bool = null`
  
- `use_lld: ?bool = null`
  
- `zig_lib_dir: ?LazyPath = null`
  
- `emit_object: bool = false`
  Emits an object file instead of a test binary.
  The object must be linked separately.
  Usually used in conjunction with a custom `test_runner`.

### `AssemblyOptions`


### Fields

- `name: []const u8`
  
- `source_file: LazyPath`
  
- `target: ResolvedTarget`
  To choose the same computer as the one building the package, pass the
  `host` field of the package's `Build` instance.
- `optimize: std.builtin.Optimize`
  
- `max_rss: u64 = 0`
  
- `zig_lib_dir: ?LazyPath = null`
  

### `StandardOptimizeOptionOptions`


### Fields

- `preferred_optimize_mode: ?std.builtin.Optimize = null`
  

### `StandardTargetOptionsArgs`


### Fields

- `whitelist: ?[]const Target.Query = null`
  
- `default_target: Target.Query = .{}`
  

### `RunOptions`


### Fields

- `stderr_behavior: process.SpawnOptions.StdIo = .inherit`
  
- `stdout_limit: Io.Limit = .limited(1_000_000)`
  Fail the configuration if stdout is larger than this.
- `cwd: process.Child.Cwd = .inherit`
  Set to change the current working directory when spawning the child
  process.
- `environ_map: ?*const process.Environ.Map = null`
  Replaces the child environment when provided. The PATH value from here
  is not used to resolve `argv[0]`; that resolution always uses parent
  environment.
- `expand_arg0: process.ArgExpansion = .no_expand`
  

### `RunResult`


### Fields

- `success: []u8`
  Thild process exited with code 0, writing this stdout.
- `spawn_failed: process.SpawnError`
  The child process could not be created.
- `bad_exit_code: u8`
  The child process indicated failure.
- `crashed`
  The child process terminated abnormally.

### `Dependency`


### Fields

- `builder: *Build`
  

### Functions

#### `artifact`

```zig
pub fn artifact(d: *Dependency, name: []const u8) *Step.Compile
```


#### `module`

```zig
pub fn module(d: *Dependency, name: []const u8) *Module
```


#### `namedWriteFiles`

```zig
pub fn namedWriteFiles(d: *Dependency, name: []const u8) *Step.WriteFile
```


#### `namedLazyPath`

```zig
pub fn namedLazyPath(d: *Dependency, name: []const u8) LazyPath
```


#### `path`

```zig
pub fn path(d: *Dependency, sub_path: []const u8) LazyPath
```


### `PackageEntry`


### Fields

- `hash: []const u8`
  
- `available: bool`
  
- `build_root: []const u8`
  
- `deps: AvailableDeps`
  
- `run_build: ?*const fn (*Build) void`
  

### `LazyPath`

A reference to an existing or future path.

### Fields

- `src_path: struct { owner: *std.Build, sub_path: []const u8, }`
  A source file path relative to build root.
- `generated: struct { index: Configuration.GeneratedFileIndex, up: usize = 0, sub_path: []const u8 = "", }`
  
- `cwd_relative: []const u8`
  Deprecated; call `Graph.cwdRelativePath` instead.
- `dependency: struct { dependency: *Dependency, sub_path: []const u8, }`
  
- `relative: struct { base: Configuration.LazyPath.Relative.Base, sub_path: []const u8 = "", pub fn eql(a: @This(), b: @This()) bool { return a.base == b.base and mem.eql(u8, a.sub_path, b.sub_path); } }`
  

### Functions

#### `eql`

```zig
pub fn eql(a: @This(), b: @This()) bool
```


#### `dirname`

```zig
pub fn dirname(lazy_path: LazyPath) LazyPath
```

Returns a lazy path referring to the directory containing this path.

The dirname is not allowed to escape the logical root for underlying
path. For example, if the path is relative to the build root, the
dirname is not allowed to traverse outside of the build root.
Similarly, if the path is a generated file inside zig-cache, the
dirname is not allowed to traverse outside of zig-cache.

#### `path`

```zig
pub fn path(lazy_path: LazyPath, b: *Build, sub_path: []const u8) LazyPath
```


#### `join`

```zig
pub fn join(lazy_path: LazyPath, arena: Allocator, sub_path: []const u8) Allocator.Error!LazyPath
```


#### `getDisplayName`

```zig
pub fn getDisplayName(lazy_path: LazyPath) []const u8
```

Deprecated, use `format` instead.

#### `format`

```zig
pub fn format(lp: LazyPath, w: *Io.Writer) Io.Writer.Error!void
```


#### `addStepDependencies`

```zig
pub fn addStepDependencies(lazy_path: LazyPath, other_step: *Step) void
```

Adds dependencies this file source implies to the given step.

#### `dupe`

```zig
pub fn dupe(lazy_path: LazyPath, graph: *const Graph) LazyPath
```

Copies the internal strings.

The `graph` parameter is only used for the global arena allocator.

#### `dupeList`

```zig
pub fn dupeList(lazy_paths: []const LazyPath, graph: *const Graph) []const LazyPath
```

Copies the slice of paths and all internal strings.

The `graph` parameter is only used for the global arena allocator.

### Constants & Variables

- **`zig_exe`**: Path to the Zig executable being used to execute "zig build".
- **`zig_lib`**: Path to the "lib/" directory from the Zig installation being used to
- **`cache_root`**: Path to the project's local cache directory (usually called ".zig-cache").

### `InstallDir`


### Fields

- `prefix: void`
  
- `lib: void`
  
- `bin: void`
  
- `header: void`
  
- `custom: []const u8`
  A path relative to the prefix

### Functions

#### `dupe`

```zig
pub fn dupe(dir: InstallDir, graph: *const Graph) InstallDir
```

Duplicates the install directory including the path if set to custom.

### `ResolvedTarget`

A pair of target query and fully resolved target.
This type is generally required by build system API that need to be given a
target. The query is kept because the Zig toolchain needs to know which parts
of the target are "native". This can apply to the CPU, the OS, or even the ABI.

### Fields

- `query: Target.Query`
  
- `result: Target`
  

### `SystemIntegrationOptionConfig`


### Fields

- `default: ?bool = null`
  If left as null, then the default will depend on system_package_mode.

## Namespaces

- **`PackageOptions`**: Build system implementation details.

## Functions

### `create`

```zig
pub fn create(graph: *Graph, root: Cache.Path, available_deps: AvailableDeps, ) error{OutOfMemory}!*Build
```

Build system implementation detail.

### `addOptions`

```zig
pub fn addOptions(b: *Build) *Step.Options
```

Create a set of key-value pairs that can be converted into a Zig source
file and then inserted into a Zig compilation's module table for importing.

This provides a way to expose build.zig values to Zig source code with
`@import`. Related: `Module.addOptions`.

### `addExecutable`

```zig
pub fn addExecutable(b: *Build, options: ExecutableOptions) *Step.Compile
```


### `addObject`

```zig
pub fn addObject(b: *Build, options: ObjectOptions) *Step.Compile
```


### `addLibrary`

```zig
pub fn addLibrary(b: *Build, options: LibraryOptions) *Step.Compile
```


### `addTest`

```zig
pub fn addTest(b: *Build, options: TestOptions) *Step.Compile
```

Creates an executable containing unit tests.

Equivalent to running the command `zig test --test-no-exec ...`.

**This step does not run the unit tests**. Typically, the result of this
function will be passed to `addRunArtifact`, creating a `Step.Run`. These
two steps are separated because they are independently configured and
cached.

### `addModule`

```zig
pub fn addModule(b: *Build, name: []const u8, options: Module.CreateOptions) *Module
```

This function creates a module and adds it to the package's module set, making
it available to other packages which depend on this one.
`createModule` can be used instead to create a private module.

### `createModule`

```zig
pub fn createModule(b: *Build, options: Module.CreateOptions) *Module
```

This function creates a private module, to be used by the current package,
but not exposed to other packages depending on this one.
`addModule` can be used instead to create a public module.

### `addSystemCommand`

```zig
pub fn addSystemCommand(b: *Build, argv: []const []const u8) *Step.Run
```

Creates a step that executes a process on the host system.

`argv` is one or more command line arguments passed to the executed
process. The first element is the name of the executable to run. More
command line arguments can be added with methods of `Step.Run`, such as:
* `Step.Run.addArgs`
* `Step.Run.addArtifactArg`
* `Step.Run.addFileArg`
* `Step.Run.addOutputFileArg`

This function introduces a system dependency, compromising reproducibility
and making it more difficult to set up one's computer in order to build the
project from source.

See also:
* `addRunArtifact`
* `addRunFile`

### `addRunArtifact`

```zig
pub fn addRunArtifact(b: *Build, exe: *Step.Compile) *Step.Run
```

Creates a `Step.Run` with an executable built with `addExecutable`.
Add command line arguments with methods of `Step.Run`.

It doesn't have to target the host. In some cases cross-compiled binaries
can even be executed.

This is declarative; it constructs a build step that may or may not be run
depending on the options provided by the user to the build command.

See also:
* `addSystemCommand`
* `addRunFile`

### `addRunFile`

```zig
pub fn addRunFile(b: *Build, executable: LazyPath) *Step.Run
```

Creates a step that executes the provided file.

Add more command line arguments via methods of `Step.Run`.

See also:
* `addSystemCommand`
* `addRunArtifact`

### `addConfigHeader`

```zig
pub fn addConfigHeader(b: *Build, options: Step.ConfigHeader.Options, values: anytype, ) *Step.ConfigHeader
```

Using the `values` provided, produces a C header file, possibly based on a
template input file (e.g. config.h.in).
When an input template file is provided, this function will fail the build
when an option not found in the input file is provided in `values`, and
when an option found in the input file is missing from `values`.

### `dupe`

```zig
pub fn dupe(b: *Build, bytes: []const u8) []const u8
```

Deprecated, call `Graph.dupeString` instead.

### `dupeStrings`

```zig
pub fn dupeStrings(b: *Build, strings: []const []const u8) []const []const u8
```

Deprecated, call `Graph.dupeStrings` instead.

### `dupePath`

```zig
pub fn dupePath(b: *Build, bytes: []const u8) []const u8
```

Deprecated, call `Graph.dupePath` instead.

### `addWriteFile`

```zig
pub fn addWriteFile(b: *Build, file_path: []const u8, data: []const u8) *Step.WriteFile
```


### `addNamedWriteFiles`

```zig
pub fn addNamedWriteFiles(b: *Build, name: []const u8) *Step.WriteFile
```


### `addNamedLazyPath`

```zig
pub fn addNamedLazyPath(b: *Build, name: []const u8, lp: LazyPath) void
```


### `addTempFiles`

```zig
pub fn addTempFiles(b: *Build) *Step.WriteFile
```

Creates a step for mutating files inside a temporary directory created lazily
and automatically cleaned up upon successful build.

The directory will be placed inside "tmp" rather than "o", and caching will
be skipped. During the `make` phase, the step will always do all the file
system operations, and on successful build completion, the dir will be
deleted along with all other tmp directories. The directory is therefore
eligible to be used for mutations by other steps.

See also:
* `addWriteFiles`
* `addMutateFiles`

### `addMutateFiles`

```zig
pub fn addMutateFiles(b: *Build, tmp_path: LazyPath) *Step.WriteFile
```

Creates a step for mutating temporary directories created with `addTempFiles`.

Consider instead `addWriteFiles` which is for creating a cached directory
of files to operate on.

This should only be used with a `tmp_path` obtained via `addTempFiles` or
`tmpPath`.

### `addWriteFiles`

```zig
pub fn addWriteFiles(b: *Build) *Step.WriteFile
```


### `addUpdateSourceFiles`

```zig
pub fn addUpdateSourceFiles(b: *Build) *Step.UpdateSourceFiles
```

Creates a step for writing data to paths relative to the build root,
mutating the project's source files.

This build step was designed not to be used during the normal build
process, but rather as a utility run by a developer with intention to
update source files, which will then be committed to version control.

Example use cases:
* precompiling assets which are tracked by version control
* snapshot testing

### `addFail`

```zig
pub fn addFail(b: *Build, error_msg: []const u8) *Step.Fail
```


### `addFmt`

```zig
pub fn addFmt(b: *Build, options: Step.Fmt.Options) *Step.Fmt
```


### `addTranslateC`

```zig
pub fn addTranslateC(b: *Build, options: Step.TranslateC.Options) *Step.TranslateC
```


### `getInstallStep`

```zig
pub fn getInstallStep(b: *Build) *Step
```


### `getUninstallStep`

```zig
pub fn getUninstallStep(b: *Build) *Step
```


### `option`

```zig
pub fn option(b: *Build, comptime T: type, name_raw: []const u8, description_raw: []const u8) ?T
```

Creates a configuration option to be passed to the build.zig script.
When a user directly runs `zig build`, they can set these options with `-D` arguments.
When a project depends on a Zig package as a dependency, it programmatically sets
these options when calling the dependency's build.zig script as a function.
`null` is returned when an option is left to default.

### `step`

```zig
pub fn step(b: *Build, name: []const u8, description: []const u8) *Step
```

Creates a top-level build step, exposed to the CLI user and advertised in
the "--help" menu.

### `standardOptimizeOption`

```zig
pub fn standardOptimizeOption(b: *Build, options: StandardOptimizeOptionOptions) std.builtin.Optimize
```


### `standardTargetOptions`

```zig
pub fn standardTargetOptions(b: *Build, args: StandardTargetOptionsArgs) ResolvedTarget
```

Exposes standard `zig build` options for choosing a target and additionally
resolves the target query.

### `parseTargetQuery`

```zig
pub fn parseTargetQuery(options: std.Target.Query.ParseOptions) error{ParseFailed}!std.Target.Query
```

Obtain a target query from a string, reporting diagnostics to stderr if the
parsing failed.
Asserts that the `diagnostics` field of `options` is `null`. This use case
is handled instead by calling `std.Target.Query.parse` directly.

### `standardTargetOptionsQueryOnly`

```zig
pub fn standardTargetOptionsQueryOnly(b: *Build, args: StandardTargetOptionsArgs) Target.Query
```

Exposes standard `zig build` options for choosing a target.

### `addUserInputOption`

```zig
pub fn addUserInputOption(b: *Build, name: []const u8, value_raw: []const u8) error{OutOfMemory}!bool
```

Build system implementation detail.

### `addUserInputFlag`

```zig
pub fn addUserInputFlag(b: *Build, name: []const u8) error{OutOfMemory}!bool
```

Build system implementation detail.

### `installArtifact`

```zig
pub fn installArtifact(b: *Build, artifact: *Step.Compile) void
```

This creates the install step and adds it to the dependencies of the
top-level install step, using all the default options.
See `addInstallArtifact` for a more flexible function.

### `addInstallArtifact`

```zig
pub fn addInstallArtifact(b: *Build, artifact: *Step.Compile, options: Step.InstallArtifact.Options, ) *Step.InstallArtifact
```

This merely creates the step; it does not add it to the dependencies of the
top-level install step.

### `installFile`

```zig
pub fn installFile(b: *Build, src_path: []const u8, dest_rel_path: []const u8) void
```

`dest_rel_path` is relative to prefix path

### `installDirectory`

```zig
pub fn installDirectory(b: *Build, options: Step.InstallDir.Options) void
```


### `installBinFile`

```zig
pub fn installBinFile(b: *Build, src_path: []const u8, dest_rel_path: []const u8) void
```

`dest_rel_path` is relative to bin path

### `installLibFile`

```zig
pub fn installLibFile(b: *Build, src_path: []const u8, dest_rel_path: []const u8) void
```

`dest_rel_path` is relative to lib path

### `addObjCopy`

```zig
pub fn addObjCopy(b: *Build, source: LazyPath, options: Step.ObjCopy.Options) *Step.ObjCopy
```


### `addInstallFile`

```zig
pub fn addInstallFile(b: *Build, source: LazyPath, dest_rel_path: []const u8) *Step.InstallFile
```

`dest_rel_path` is relative to install prefix path

### `addInstallBinFile`

```zig
pub fn addInstallBinFile(b: *Build, source: LazyPath, dest_rel_path: []const u8) *Step.InstallFile
```

`dest_rel_path` is relative to bin path

### `addInstallLibFile`

```zig
pub fn addInstallLibFile(b: *Build, source: LazyPath, dest_rel_path: []const u8) *Step.InstallFile
```

`dest_rel_path` is relative to lib path

### `addInstallHeaderFile`

```zig
pub fn addInstallHeaderFile(b: *Build, source: LazyPath, dest_rel_path: []const u8) *Step.InstallFile
```

`dest_rel_path` is relative to header path

### `addInstallFileWithDir`

```zig
pub fn addInstallFileWithDir(b: *Build, source: LazyPath, install_dir: InstallDir, dest_rel_path: []const u8, ) *Step.InstallFile
```


### `addInstallDirectory`

```zig
pub fn addInstallDirectory(b: *Build, options: Step.InstallDir.Options) *Step.InstallDir
```


### `addCheckFile`

```zig
pub fn addCheckFile(b: *Build, file_source: LazyPath, options: Step.CheckFile.Options, ) *Step.CheckFile
```


### `path`

```zig
pub fn path(b: *Build, sub_path: []const u8) LazyPath
```

References a file or directory relative to the source root.

### `pathList`

```zig
pub fn pathList(b: *Build, sub_paths: []const []const u8) []const LazyPath
```

Creates a list of files and/or directories relative to the source root.

### `pathJoin`

```zig
pub fn pathJoin(b: *Build, paths: []const []const u8) []u8
```


### `pathResolve`

```zig
pub fn pathResolve(b: *Build, paths: []const []const u8) []u8
```


### `fmt`

```zig
pub fn fmt(b: *Build, comptime format: []const u8, args: anytype) []u8
```


### `findProgramLazy`

```zig
pub fn findProgramLazy(b: *Build, options: Step.FindProgram.Options) LazyPath
```

Creates an anonymous `Step` that searches for an executable on the host that
has more than one possible name.

Returns the `LazyPath` of the found executable. The search only takes place
if the `LazyPath` will be used by a depending `Step`.

This API is useful in the following cases:
* The binary is not named the same across all systems (for example "python"
  vs "python3").
* The binary may be produced by building from source rather than being
  globally installed and will therefore be possibly found in one of the
  search prefix paths.

Names are searched in order, observing search prefixes first and then PATH
environment variable.

Windows file name extensions are searched automatically, respecting the
PATHEXT environment variable, so they need not be included in this list.
However, even on Windows, the names will be checked without appending
extensions first, so that can be used as a priority system.

See also:
* `findProgram`

### `findProgram`

```zig
pub fn findProgram(b: *Build, options: FindProgramOptions) ?[]const u8
```

Immediately (in the configure phase), searches for an executable on the host
that has more than one possible name.

Calling this function poisons the configuration cache, so it is only
appropriate when the existence of the program or its output needs to be
observed by configuration logic. For more information, see
`Graph.CachePoison` documentation.

Names are searched in order, observing search prefixes first and then PATH
environment variable.

Windows file name extensions are searched automatically, respecting the
PATHEXT environment variable, so they need not be included in this list.
However, even on Windows, the names will be checked without appending
extensions first, so that can be used as a priority system.

See also:
* `findProgramLazy`

### `runAllowFail`

```zig
pub fn runAllowFail(b: *Build, argv: []const []const u8, exit_code: *u8, stderr_behavior: process.SpawnOptions.StdIo, ) anyerror![]u8
```

Deprecated; use `runFallible`.

### `runFallible`

```zig
pub fn runFallible(b: *Build, argv: []const []const u8, options: RunOptions) RunResult
```

Executes the provided command immediately, allowing failure.

If the program exits successfully, stdout is returned. Otherwise, returns
an indication of failure.

See also:
* `run`.

### `run`

```zig
pub fn run(b: *Build, argv: []const []const u8) []u8
```

Executes the provided command immediately.

If the program exits successfully, stdout is returned. Otherwise, fails the
build with a helpful message.

See also:
* `runFallible`.

### `addSearchPrefix`

```zig
pub fn addSearchPrefix(b: *Build, search_prefix: []const u8) void
```

Adds additional paths, equivalent to the `--search-prefix` arguments
provided by the user. Paths added with this function have lower precedence
than the ones specified by the user on the command line.

It is generally best practice to avoid calling this function, instead
relying on the user to provide these paths via the standard build system
interface. However, when integrating with other build systems, the user may
have already provided the information to the other build system, and thus
it is desirable to use that same information without requiring the user to
provide it again.

### `isRoot`

```zig
pub fn isRoot(b: *const Build) bool
```


### `lazyDependency`

```zig
pub fn lazyDependency(b: *Build, name: []const u8, args: anytype) ?*Dependency
```

Deprecated in favor of `dependencyLazy`.

### `dependencyLazy`

```zig
pub fn dependencyLazy(b: *Build, name: []const u8, args: anytype) error{LazyDependencyNeeded}!*Dependency
```

Declares that the current configuration does in fact require a potentially
lazy dependency.

If the dependency is already fetched, it is returned. However if the
dependency is not yet fetched, then when the build script is finished
running, the toolchain will not proceed to the make phase. Instead, the
parent process will additionally fetch all the lazy dependencies that were
actually required by running the build script, recompile the build script,
and then run it again. In other words, if this function returns
`error.LazyDependencyNeeded` it means that the only purpose of completing
the configure phase is to find out all the other lazy dependencies that are
also required. In this case, one must propagate the error all the way up
and return it from the main build function.

For non-lazy dependencies, this always succeeds.

### `dependency`

```zig
pub fn dependency(b: *Build, name: []const u8, args: anytype) *Dependency
```

Declares that the current configuration does in fact require a potentially
lazy dependency.

If the dependency is already fetched, it is returned. Otherwise, exits the
configuration phase with intent to fetch the lazy dependency and rerun the
configuration script.

If it is known to the caller at this point that additional lazy
dependencies are also required, it would save time to call `dependencyLazy`
instead, handling `error.LazyDependencyNeeded` in a way that marks multiple
potentially lazy dependencies as required before eventually returning
that error from the top level build function.

### `lazyImport`

```zig
pub inline fn lazyImport(b: *Build, comptime asking_build_zig: type, comptime dep_name: []const u8, ) ?type
```

In a build.zig file, this function is to `@import` what `lazyDependency` is to `dependency`.
If the dependency is lazy and has not yet been fetched, it instructs the parent process to fetch
that dependency after the build script has finished running, then returns `null`.
If the dependency is lazy but has already been fetched, or if it is eager, it returns
the build.zig struct of that dependency, just like a regular `@import`.

### `dependencyFromBuildZig`

```zig
pub fn dependencyFromBuildZig(b: *Build, comptime build_zig: type, args: anytype, ) *Dependency
```

Build system implementation detail.

### `runPackageScript`

```zig
pub inline fn runPackageScript(b: *Build, comptime build_zig: anytype) void
```

Build system implementation detail.

### `tmpPath`

```zig
pub fn tmpPath(b: *Build) LazyPath
```

Creates a path leading to a directory inside "tmp" subdirectory of local
cache which is created on demand and cleaned up by the build runner upon
success.

### `resolveTargetQuery`

```zig
pub fn resolveTargetQuery(b: *Build, query: Target.Query) ResolvedTarget
```

Converts a target query into a fully resolved target that can be passed to
various parts of the API.

### `wantSharedLibSymLinks`

```zig
pub fn wantSharedLibSymLinks(target: Target) bool
```


### `systemIntegrationOption`

```zig
pub fn systemIntegrationOption(b: *Build, name: []const u8, config: SystemIntegrationOptionConfig, ) bool
```


### `dependOnFileContents`

```zig
pub fn dependOnFileContents(b: *Build, lazy_path: LazyPath) void
```

Indicates that the build.zig logic depends on a particular file's contents.

If the file is created, deleted, or has its contents changed, the configure
phase will be repeated. If the inode or mtime change, but the file contents
remain the same, it will not cause the configure logic to be repeated.

This is an alternative to `Graph.poisonCache` that avoids making every invocation
of `zig build` into a cache miss.

Only a subset of `LazyPath` are supported:
- Relative to cwd
- Relative to any package root
- Relative to zig cache or zig installation

If the file would be inside one of the search prefixes, then the dependency
cannot be tracked; `Graph.poisonCache` must be used instead.

### `dependOnFileMetadata`

```zig
pub fn dependOnFileMetadata(b: *Build, lazy_path: LazyPath) void
```

Indicates that the build.zig logic depends on a particular file's size,
inode, mtime, and contents.

If the file is created, deleted, has its contents changed, or the inode
changes, or the mtime changes, the configure phase will be repeated.

This is an alternative to `Graph.poisonCache` that avoids making every invocation
of `zig build` into a cache miss.

Only a subset of `LazyPath` are supported:
- Relative to cwd
- Relative to any package root
- Relative to zig cache or zig installation

If the file would be inside one of the search prefixes, then the dependency
cannot be tracked; `Graph.poisonCache` must be used instead.

### `dependOnDirectoryContents`

```zig
pub fn dependOnDirectoryContents(b: *Build, lazy_path: LazyPath) void
```

Indicates that the build.zig logic depends on a particular directory's entries.

This is an alternative to `Graph.poisonCache` that avoids making every invocation
of `zig build` into a cache miss.

If any file is created, deleted, or renamed in this directory, leaving the
directory in a different state than last configuration with respect to
existence and naming of entries, the configure phase will be repeated.

Only a subset of `LazyPath` are supported:
- Relative to cwd
- Relative to any package root
- Relative to zig cache or zig installation

If the directory would be inside one of the search prefixes, then the dependency
cannot be tracked; `Graph.poisonCache` must be used instead.

Not recursive.

### `dependOnDirectoryMetadata`

```zig
pub fn dependOnDirectoryMetadata(b: *Build, lazy_path: LazyPath) void
```

Indicates that the build.zig logic depends on a particular directory's last
modification date.

This is an alternative to `Graph.poisonCache` that avoids making every invocation
of `zig build` into a cache miss.

If any file is created, deleted, or renamed in this directory, the
configure phase will be repeated.

Only a subset of `LazyPath` are supported:
- Relative to cwd
- Relative to any package root
- Relative to zig cache or zig installation

If the directory would be inside one of the search prefixes, then the dependency
cannot be tracked; `Graph.poisonCache` must be used instead.

Not recursive.

### `serializeConfigurationExiting`

```zig
pub fn serializeConfigurationExiting(b: *Build) noreturn
```

Build system implementation detail.

## Constants & Variables

- **`Cache`**: 
- **`Step`**: 
- **`Module`**: 
- **`abi`**: 
- **`Configuration`**: The serialized output of configure phase ingested by make phase.
- **`Serialize`**: Logic that transforms `Build` into `Configuration`.
- **`FindProgramOptions`**: 
- **`package_map`**: Build system implementation detail.

