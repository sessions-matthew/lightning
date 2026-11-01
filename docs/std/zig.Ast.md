# `std.zig.Ast`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/zig/Ast.zig`  
> [← Back to Standard Library Index](README.md)

Abstract Syntax Tree for Zig source code.
For Zig syntax, the root node is at nodes[0] and contains the list of
sub-nodes.
For Zon syntax, the root node is at nodes[0] and contains lhs as the node
index of the main expression.

## Fields

- `source: [:0]const u8`
  Reference to externally-owned data.
- `tokens: TokenList.Slice`
  
- `nodes: NodeList.Slice`
  
- `extra_data: []u32`
  
- `mode: Mode = .zig`
  
- `errors: []const Error`
  

## Types

### `ByteOffset`


### `TokenList`


### `NodeList`


### `TokenIndex`

Index into `tokens`.

### `OptionalTokenIndex`

Index into `tokens`, or null.

### Fields

- `none = std.math.maxInt(u32)`
  
- `_`
  

### Functions

#### `unwrap`

```zig
pub fn unwrap(oti: OptionalTokenIndex) ?TokenIndex
```


#### `fromToken`

```zig
pub fn fromToken(ti: TokenIndex) OptionalTokenIndex
```


#### `fromOptional`

```zig
pub fn fromOptional(oti: ?TokenIndex) OptionalTokenIndex
```


### `TokenOffset`

A relative token index.

### Fields

- `zero = 0`
  
- `_`
  

### Functions

#### `init`

```zig
pub fn init(base: TokenIndex, destination: TokenIndex) TokenOffset
```


#### `toOptional`

```zig
pub fn toOptional(to: TokenOffset) OptionalTokenOffset
```


#### `toAbsolute`

```zig
pub fn toAbsolute(offset: TokenOffset, base: TokenIndex) TokenIndex
```


### `OptionalTokenOffset`

A relative token index, or null.

### Fields

- `none = std.math.maxInt(i32)`
  
- `_`
  

### Functions

#### `unwrap`

```zig
pub fn unwrap(oto: OptionalTokenOffset) ?TokenOffset
```


### `Location`


### Fields

- `line: usize`
  
- `column: usize`
  
- `line_start: usize`
  
- `line_end: usize`
  

### `Span`


### Fields

- `start: u32`
  
- `end: u32`
  
- `main: u32`
  

### `Mode`


### Fields

- `zig`
  
- `zon`
  

### `ParseOptions`


### Fields

- `recover: bool = true`
  
- `mode: Mode = .zig`
  

### `Error`


### Fields

- `tag: Tag`
  
- `is_note: bool = false`
  
- `token_is_prev: bool = false`
  True if `token` points to the token before the token causing an issue.
- `token: TokenIndex`
  
- `extra: union { none: void, expected_tag: Token.Tag, offset: usize, } = .{ .none = {} }`
  

### Types

#### `Tag`


### `ExtraIndex`

Index into `extra_data`.

### Fields

- `_`
  

### `Node`


### Fields

- `tag: Tag`
  
- `main_token: TokenIndex`
  
- `data: Data`
  

### Types

#### `Index`

Index into `nodes`.

#### `OptionalIndex`

Index into `nodes`, or null.

#### `Offset`

A relative node index.

#### `OptionalOffset`

A relative node index, or null.

#### `Tag`

The FooComma/FooSemicolon variants exist to ease the implementation of
`Ast.lastToken()`

#### `Data`


#### `LocalVarDecl`


#### `ArrayTypeSentinel`


#### `PtrType`


#### `PtrTypeBitRange`


#### `SubRange`


#### `If`


#### `ContainerField`


#### `GlobalVarDecl`


#### `Slice`


#### `SliceSentinel`


#### `While`


#### `WhileCont`


#### `For`


#### `FnProtoOne`


#### `FnProto`


#### `Asm`


## Namespaces

- **`full`**: Fully assembled AST node information.

## Functions

### `tokenTag`

```zig
pub fn tokenTag(tree: *const Ast, token_index: TokenIndex) Token.Tag
```


### `tokenStart`

```zig
pub fn tokenStart(tree: *const Ast, token_index: TokenIndex) ByteOffset
```


### `nodeTag`

```zig
pub fn nodeTag(tree: *const Ast, node: Node.Index) Node.Tag
```


### `nodeMainToken`

```zig
pub fn nodeMainToken(tree: *const Ast, node: Node.Index) TokenIndex
```


### `nodeData`

```zig
pub fn nodeData(tree: *const Ast, node: Node.Index) Node.Data
```


### `isTokenPrecededByTags`

```zig
pub fn isTokenPrecededByTags(tree: *const Ast, ti: TokenIndex, expected_token_tags: []const Token.Tag, ) bool
```


### `deinit`

```zig
pub fn deinit(tree: *Ast, gpa: Allocator) void
```


### `parse`

```zig
pub fn parse(gpa: Allocator, source: [:0]const u8, options: ParseOptions) Allocator.Error!Ast
```

Result should be freed with tree.deinit() when there are
no more references to any of the tokens or nodes.

### `parseTokens`

```zig
pub fn parseTokens(gpa: Allocator, source: [:0]const u8, tokens: Ast.TokenList.Slice, options: ParseOptions, ) Allocator.Error!Ast
```


### `renderAlloc`

```zig
pub fn renderAlloc(tree: Ast, gpa: Allocator) error{OutOfMemory}![]u8
```

`gpa` is used for allocating the resulting formatted source code.
Caller owns the returned slice of bytes, allocated with `gpa`.

### `render`

```zig
pub fn render(tree: Ast, gpa: Allocator, w: *Writer, fixups: Render.Fixups) Render.Error!void
```


### `errorOffset`

```zig
pub fn errorOffset(tree: Ast, parse_error: Error) u32
```

Returns an extra offset for column and byte offset of errors that
should point after the token in the error message.

### `tokenLocation`

```zig
pub fn tokenLocation(self: Ast, start_offset: ByteOffset, token_index: TokenIndex) Location
```


### `tokenSlice`

```zig
pub fn tokenSlice(tree: Ast, token_index: TokenIndex) []const u8
```


### `extraDataSlice`

```zig
pub fn extraDataSlice(tree: Ast, range: Node.SubRange, comptime T: type) []const T
```


### `extraDataSliceWithLen`

```zig
pub fn extraDataSliceWithLen(tree: Ast, start: ExtraIndex, len: u32, comptime T: type) []const T
```


### `extraData`

```zig
pub fn extraData(tree: Ast, index: ExtraIndex, comptime T: type) T
```


### `rootDecls`

```zig
pub fn rootDecls(tree: Ast) []const Node.Index
```


### `renderError`

```zig
pub fn renderError(tree: Ast, parse_error: Error, w: *Writer) Writer.Error!void
```


### `firstToken`

```zig
pub fn firstToken(tree: Ast, node: Node.Index) TokenIndex
```


### `lastToken`

```zig
pub fn lastToken(tree: Ast, node: Node.Index) TokenIndex
```


### `tokensOnSameLine`

```zig
pub fn tokensOnSameLine(tree: Ast, token1: TokenIndex, token2: TokenIndex) bool
```


### `getNodeSource`

```zig
pub fn getNodeSource(tree: Ast, node: Node.Index) []const u8
```


### `globalVarDecl`

```zig
pub fn globalVarDecl(tree: Ast, node: Node.Index) full.VarDecl
```


### `localVarDecl`

```zig
pub fn localVarDecl(tree: Ast, node: Node.Index) full.VarDecl
```


### `simpleVarDecl`

```zig
pub fn simpleVarDecl(tree: Ast, node: Node.Index) full.VarDecl
```


### `alignedVarDecl`

```zig
pub fn alignedVarDecl(tree: Ast, node: Node.Index) full.VarDecl
```


### `assignDestructure`

```zig
pub fn assignDestructure(tree: Ast, node: Node.Index) full.AssignDestructure
```


### `ifSimple`

```zig
pub fn ifSimple(tree: Ast, node: Node.Index) full.If
```


### `ifFull`

```zig
pub fn ifFull(tree: Ast, node: Node.Index) full.If
```


### `containerField`

```zig
pub fn containerField(tree: Ast, node: Node.Index) full.ContainerField
```


### `containerFieldInit`

```zig
pub fn containerFieldInit(tree: Ast, node: Node.Index) full.ContainerField
```


### `containerFieldAlign`

```zig
pub fn containerFieldAlign(tree: Ast, node: Node.Index) full.ContainerField
```


### `fnProtoSimple`

```zig
pub fn fnProtoSimple(tree: Ast, buffer: *[1]Node.Index, node: Node.Index) full.FnProto
```


### `fnProtoMulti`

```zig
pub fn fnProtoMulti(tree: Ast, node: Node.Index) full.FnProto
```


### `fnProtoOne`

```zig
pub fn fnProtoOne(tree: Ast, buffer: *[1]Node.Index, node: Node.Index) full.FnProto
```


### `fnProto`

```zig
pub fn fnProto(tree: Ast, node: Node.Index) full.FnProto
```


### `structInitOne`

```zig
pub fn structInitOne(tree: Ast, buffer: *[1]Node.Index, node: Node.Index) full.StructInit
```


### `structInitDotTwo`

```zig
pub fn structInitDotTwo(tree: Ast, buffer: *[2]Node.Index, node: Node.Index) full.StructInit
```


### `structInitDot`

```zig
pub fn structInitDot(tree: Ast, node: Node.Index) full.StructInit
```


### `structInit`

```zig
pub fn structInit(tree: Ast, node: Node.Index) full.StructInit
```


### `arrayInitOne`

```zig
pub fn arrayInitOne(tree: Ast, buffer: *[1]Node.Index, node: Node.Index) full.ArrayInit
```


### `arrayInitDotTwo`

```zig
pub fn arrayInitDotTwo(tree: Ast, buffer: *[2]Node.Index, node: Node.Index) full.ArrayInit
```


### `arrayInitDot`

```zig
pub fn arrayInitDot(tree: Ast, node: Node.Index) full.ArrayInit
```


### `arrayInit`

```zig
pub fn arrayInit(tree: Ast, node: Node.Index) full.ArrayInit
```


### `arrayType`

```zig
pub fn arrayType(tree: Ast, node: Node.Index) full.ArrayType
```


### `arrayTypeSentinel`

```zig
pub fn arrayTypeSentinel(tree: Ast, node: Node.Index) full.ArrayType
```


### `ptrTypeAligned`

```zig
pub fn ptrTypeAligned(tree: Ast, node: Node.Index) full.PtrType
```


### `ptrTypeSentinel`

```zig
pub fn ptrTypeSentinel(tree: Ast, node: Node.Index) full.PtrType
```


### `ptrType`

```zig
pub fn ptrType(tree: Ast, node: Node.Index) full.PtrType
```


### `ptrTypeBitRange`

```zig
pub fn ptrTypeBitRange(tree: Ast, node: Node.Index) full.PtrType
```


### `sliceOpen`

```zig
pub fn sliceOpen(tree: Ast, node: Node.Index) full.Slice
```


### `slice`

```zig
pub fn slice(tree: Ast, node: Node.Index) full.Slice
```


### `sliceSentinel`

```zig
pub fn sliceSentinel(tree: Ast, node: Node.Index) full.Slice
```


### `containerDeclTwo`

```zig
pub fn containerDeclTwo(tree: Ast, buffer: *[2]Node.Index, node: Node.Index) full.ContainerDecl
```


### `containerDecl`

```zig
pub fn containerDecl(tree: Ast, node: Node.Index) full.ContainerDecl
```


### `containerDeclArg`

```zig
pub fn containerDeclArg(tree: Ast, node: Node.Index) full.ContainerDecl
```


### `containerDeclRoot`

```zig
pub fn containerDeclRoot(tree: Ast) full.ContainerDecl
```


### `taggedUnionTwo`

```zig
pub fn taggedUnionTwo(tree: Ast, buffer: *[2]Node.Index, node: Node.Index) full.ContainerDecl
```


### `taggedUnion`

```zig
pub fn taggedUnion(tree: Ast, node: Node.Index) full.ContainerDecl
```


### `taggedUnionEnumTag`

```zig
pub fn taggedUnionEnumTag(tree: Ast, node: Node.Index) full.ContainerDecl
```


### `switchFull`

```zig
pub fn switchFull(tree: Ast, node: Node.Index) full.Switch
```


### `switchCaseOne`

```zig
pub fn switchCaseOne(tree: Ast, node: Node.Index) full.SwitchCase
```


### `switchCase`

```zig
pub fn switchCase(tree: Ast, node: Node.Index) full.SwitchCase
```


### `asmSimple`

```zig
pub fn asmSimple(tree: Ast, node: Node.Index) full.Asm
```


### `asmFull`

```zig
pub fn asmFull(tree: Ast, node: Node.Index) full.Asm
```


### `whileSimple`

```zig
pub fn whileSimple(tree: Ast, node: Node.Index) full.While
```


### `whileCont`

```zig
pub fn whileCont(tree: Ast, node: Node.Index) full.While
```


### `whileFull`

```zig
pub fn whileFull(tree: Ast, node: Node.Index) full.While
```


### `forSimple`

```zig
pub fn forSimple(tree: Ast, node: Node.Index) full.For
```


### `forFull`

```zig
pub fn forFull(tree: Ast, node: Node.Index) full.For
```


### `callOne`

```zig
pub fn callOne(tree: Ast, buffer: *[1]Node.Index, node: Node.Index) full.Call
```


### `callFull`

```zig
pub fn callFull(tree: Ast, node: Node.Index) full.Call
```


### `fullVarDecl`

```zig
pub fn fullVarDecl(tree: Ast, node: Node.Index) ?full.VarDecl
```


### `fullIf`

```zig
pub fn fullIf(tree: Ast, node: Node.Index) ?full.If
```


### `fullWhile`

```zig
pub fn fullWhile(tree: Ast, node: Node.Index) ?full.While
```


### `fullFor`

```zig
pub fn fullFor(tree: Ast, node: Node.Index) ?full.For
```


### `fullContainerField`

```zig
pub fn fullContainerField(tree: Ast, node: Node.Index) ?full.ContainerField
```


### `fullFnProto`

```zig
pub fn fullFnProto(tree: Ast, buffer: *[1]Ast.Node.Index, node: Node.Index) ?full.FnProto
```


### `fullStructInit`

```zig
pub fn fullStructInit(tree: Ast, buffer: *[2]Ast.Node.Index, node: Node.Index) ?full.StructInit
```


### `fullArrayInit`

```zig
pub fn fullArrayInit(tree: Ast, buffer: *[2]Node.Index, node: Node.Index) ?full.ArrayInit
```


### `fullArrayType`

```zig
pub fn fullArrayType(tree: Ast, node: Node.Index) ?full.ArrayType
```


### `fullPtrType`

```zig
pub fn fullPtrType(tree: Ast, node: Node.Index) ?full.PtrType
```


### `fullSlice`

```zig
pub fn fullSlice(tree: Ast, node: Node.Index) ?full.Slice
```


### `fullContainerDecl`

```zig
pub fn fullContainerDecl(tree: Ast, buffer: *[2]Ast.Node.Index, node: Node.Index) ?full.ContainerDecl
```


### `fullSwitch`

```zig
pub fn fullSwitch(tree: Ast, node: Node.Index) ?full.Switch
```


### `fullSwitchCase`

```zig
pub fn fullSwitchCase(tree: Ast, node: Node.Index) ?full.SwitchCase
```


### `fullAsm`

```zig
pub fn fullAsm(tree: Ast, node: Node.Index) ?full.Asm
```


### `fullCall`

```zig
pub fn fullCall(tree: Ast, buffer: *[1]Ast.Node.Index, node: Node.Index) ?full.Call
```


### `builtinCallParams`

```zig
pub fn builtinCallParams(tree: Ast, buffer: *[2]Ast.Node.Index, node: Ast.Node.Index) ?[]const Node.Index
```


### `blockStatements`

```zig
pub fn blockStatements(tree: Ast, buffer: *[2]Ast.Node.Index, node: Ast.Node.Index) ?[]const Node.Index
```


### `nodeToSpan`

```zig
pub fn nodeToSpan(tree: *const Ast, node: Ast.Node.Index) Span
```


### `tokenToSpan`

```zig
pub fn tokenToSpan(tree: *const Ast, token: Ast.TokenIndex) Span
```


### `tokensToSpan`

```zig
pub fn tokensToSpan(tree: *const Ast, start: Ast.TokenIndex, end: Ast.TokenIndex, main: Ast.TokenIndex) Span
```


## Constants & Variables

- **`Render`**: 

