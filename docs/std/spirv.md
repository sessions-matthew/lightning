# `std.spirv`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/spirv.zig`  
> [← Back to Standard Library Index](README.md)

## Types

### `Scope`


### Fields

- `cross_device = 0`
  
- `device = 1`
  
- `workgroup = 2`
  
- `subgroup = 3`
  
- `invocation = 4`
  
- `queue_family = 5`
  
- `shader_call_khr = 6`
  

### `MemorySemantics`


### Fields

- `_reserved_bit_0: bool = false`
  
- `acquire: bool = false`
  
- `release: bool = false`
  
- `acquire_release: bool = false`
  
- `sequentially_consistent: bool = false`
  
- `_reserved_bit_5: bool = false`
  
- `uniform_memory: bool = false`
  
- `subgroup_memory: bool = false`
  
- `workgroup_memory: bool = false`
  
- `cross_workgroup_memory: bool = false`
  
- `atomic_counter_memory: bool = false`
  
- `image_memory: bool = false`
  
- `output_memory: bool = false`
  
- `make_available: bool = false`
  
- `make_visible: bool = false`
  
- `@"volatile": bool = false`
  
- `_reserved: u16 = 0`
  

### Constants & Variables

- **`none`**: 

## Functions

### `controlBarrier`

```zig
pub fn controlBarrier(comptime execution: Scope, comptime memory: Scope, comptime semantics: MemorySemantics, ) void
```


### `memoryBarrier`

```zig
pub fn memoryBarrier(comptime memory: Scope, comptime semantics: MemorySemantics) void
```


### `workgroupBarrier`

```zig
pub fn workgroupBarrier() void
```


### `specConst`

```zig
pub fn specConst(T: type, comptime default_value: T, comptime spec_id: u32) T
```


### `imageSampleImplicitLod`

```zig
pub fn imageSampleImplicitLod(sampled_image: anytype, coordinate: ImageCoordinate(std.meta.Child(@TypeOf(sampled_image)), f32), ) @Vector(4, ImageSampledType(std.meta.Child(@TypeOf(sampled_image))))
```

The type of `sampled_image` must be a pointer to a SPIR-V sampled image.

### `imageQuerySize`

```zig
pub fn imageQuerySize(image: anytype, ) ImageCoordinate(std.meta.Child(@TypeOf(image)), u32)
```

Query the dimensions of `image`, with no level of detail.

### `imageWrite`

```zig
pub fn imageWrite(image: anytype, T: type, coordinate: ImageCoordinate(std.meta.Child(@TypeOf(image)), T), texel: @Vector(4, ImageSampledType(std.meta.Child(@TypeOf(image)))), ) void
```

Write a texel to an image without a sampler.
The type of `image` must be a pointer to a SPIR-V image.

### `setMeshOutputs`

```zig
pub fn setMeshOutputs(vertex_count: u32, primitive_count: u32) void
```


## Constants & Variables

- **`position_in`**: 
- **`position_out`**: 
- **`point_size_in`**: 
- **`point_size_out`**: 
- **`invocation_id`**: 
- **`frag_coord`**: 
- **`point_coord`**: 
- **`frag_depth`**: 
- **`num_workgroups`**: 
- **`workgroup_size`**: 
- **`workgroup_id`**: 
- **`local_invocation_id`**: 
- **`global_invocation_id`**: 
- **`vertex_index`**: 
- **`instance_index`**: 

