# `std.meta`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/meta.zig`  
> [← Back to Standard Library Index](README.md)

## Types

### `Child`

```zig
pub fn Child(comptime T: type) type
```

Given a parameterized type (array, vector, pointer, optional), returns the "child type".

### `Elem`

```zig
pub fn Elem(comptime T: type) type
```

Given a "memory span" type (array, slice, vector, or pointer to such), returns the "element type".

### `Sentinel`

```zig
pub fn Sentinel(comptime T: type, comptime sentinel_val: Elem(T)) type
```

Given a "memory span" type, returns the same type except with the given sentinel value.

### `FieldEnum`

```zig
pub fn FieldEnum(comptime T: type) type
```

Returns an enum with a variant named after each field of `T`.

### `DeclEnum`

```zig
pub fn DeclEnum(comptime T: type) type
```


### `BareUnion`

```zig
pub fn BareUnion(comptime T: type) type
```


### `BackingInt`

```zig
pub fn BackingInt(comptime T: type) type
```

For enums, packed unions and packed structs, returns their backing integer type.
For tagged unions, returns the backing integer type of their enum tag type.

### `Tag`

```zig
pub fn Tag(comptime T: type) type
```


### `Float`

```zig
pub fn Float(comptime bit_count: u8) type
```


### `ArgsTuple`

```zig
pub fn ArgsTuple(comptime Function: type) type
```

For a given function type, returns a tuple type which fields will
correspond to the argument types.

Examples:
- `ArgsTuple(fn () void)` ⇒ `tuple { }`
- `ArgsTuple(fn (a: u32) u32)` ⇒ `tuple { u32 }`
- `ArgsTuple(fn (a: u32, b: f16) noreturn)` ⇒ `tuple { u32, f16 }`

### `Slice`

```zig
pub fn Slice(comptime Pointer: type) type
```

Given a pointer type, type-erases the array length if present, returning an
equivalent pointer type that is always a slice.

### `AbsorbSentinel`

```zig
pub fn AbsorbSentinel(comptime Pointer: type) type
```

Given a pointer type, removes the sentinel if present, returning an
equivalent pointer type with no sentinel

## Functions

### `stringToEnum`

```zig
pub fn stringToEnum(comptime T: type, tag_name: []const u8) ?T
```

Returns the variant of an enum type corresponding to the provided tag name,
or `null` if no such variant exists.

### `alignment`

```zig
pub fn alignment(comptime T: type) comptime_int
```

Returns the alignment of type T.
Note that if T is a pointer type the result is different than the one
returned by @alignOf(T).
If T is a pointer type the alignment of the type it points to is returned.

### `sentinel`

```zig
pub inline fn sentinel(comptime T: type) ?Elem(T)
```

Given a type which can have a sentinel e.g. `[:0]u8`, returns the sentinel value,
or `null` if there is not one.
Types which cannot possibly have a sentinel will be a compile error.
Result is always comptime-known.

### `containerLayout`

```zig
pub fn containerLayout(comptime T: type) Type.ContainerLayout
```


### `declarations`

```zig
pub fn declarations(comptime T: type) []const [:0]const u8
```

Returns the list of declaration names of namespace types.

This function is only useful when the callsite does not know statically
which kind of container it is.

### `a`

```zig
pub fn a() void
```


### `a`

```zig
pub fn a() void
```


### `a`

```zig
pub fn a() void
```


### `a`

```zig
pub fn a() void
```


### `fieldInfo`

```zig
pub fn fieldInfo(comptime T: type, comptime field: FieldEnum(T)) switch (@typeInfo(T)) { .@"struct" => struct { name: [:0]const u8, type: type, attrs: Type.Struct.FieldAttributes }, .@"union" => struct { name: [:0]const u8, type: type, attrs: Type.Union.FieldAttributes }, .@"enum" => struct { name: [:0]const u8, value: comptime_int }, .error_set => struct { name: [:0]const u8 }, else => @compileError("Expected struct, union, error set or enum type, found '" ++ @typeName(T) ++ "'"), }
```

Deprecated in favor of `@typeInfo`.

To be removed after 0.17.0 is tagged.

### `fieldNames`

```zig
pub fn fieldNames(comptime T: type) []const [:0]const u8
```

Deprecated in favor of `@typeInfo`.

To be removed after 0.17.0 is tagged.

### `fieldTypes`

```zig
pub fn fieldTypes(comptime T: type) []const type
```

Deprecated in favor of `@typeInfo`.

To be removed after 0.17.0 is tagged.

### `tags`

```zig
pub fn tags(comptime T: type) *const [fieldNames(T).len]T
```

Given an enum or error set type, returns a pointer to an array containing all tags for that
enum or error set.

### `activeTag`

```zig
pub fn activeTag(u: anytype) Tag(@TypeOf(u))
```

Returns the active tag of a tagged union

### `eql`

```zig
pub fn eql(a: anytype, b: @TypeOf(a)) bool
```

Compares two of any type for equality. Containers that do not support comparison
on their own are compared on a field-by-field basis. Pointers are not followed.

### `fieldIndex`

```zig
pub fn fieldIndex(comptime T: type, comptime name: []const u8) ?comptime_int
```

Given a type and a name, return the field index according to source order.
Returns `null` if the field is not found.

### `isError`

```zig
pub fn isError(error_union: anytype) bool
```

Returns whether `error_union` contains an error.

### `hasFn`

```zig
pub inline fn hasFn(comptime T: type, comptime name: []const u8) bool
```

Returns true if a type has a namespace and the namespace contains `name`;
`false` otherwise. Result is always comptime-known.

### `foo`

```zig
pub fn foo() void
```


### `hasMethod`

```zig
pub inline fn hasMethod(comptime T: type, comptime name: []const u8) bool
```

Returns true if a type has a `name` method; `false` otherwise.
Result is always comptime-known.

### `foo`

```zig
pub fn foo() void
```


### `foo`

```zig
pub fn foo() void
```


### `hasUniqueRepresentation`

```zig
pub inline fn hasUniqueRepresentation(comptime T: type) bool
```

True if every value of the type `T` has a unique bit pattern representing it.
In other words, `T` has no unused bits and no padding.
Result is always comptime-known.

## Constants & Variables

- **`TrailerFlags`**: 
- **`declarationInfo`**: To be removed after Zig 0.17.0 is tagged.
- **`fields`**: To be removed after Zig 0.17.0 is tagged.
- **`a`**: 
- **`a`**: 
- **`b`**: 
- **`c`**: 
- **`a`**: 
- **`b`**: 
- **`c`**: 

