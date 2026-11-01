# `std.treap`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/treap.zig`  
> [← Back to Standard Library Index](README.md)

## Types

### `Treap`

```zig
pub fn Treap(comptime Key: type, comptime compareFn: anytype) type
```


### Fields

- `root: ?*Node = null`
  
- `prng: Prng = .{}`
  

### Types

#### `Node`

A Node represents an item or point in the treap with a uniquely associated key.

#### `Entry`

An Entry represents a slot in the treap associated with a given key.

#### `InorderIterator`

Usage example:
  var iter = treap.inorderIterator();
  while (iter.next()) |node| {
    ...
  }

### Functions

#### `getMin`

```zig
pub fn getMin(self: Self) ?*Node
```

Returns the smallest Node by key in the treap if there is one.
Use `getEntryForExisting()` to replace/remove this Node from the treap.

#### `getMax`

```zig
pub fn getMax(self: Self) ?*Node
```

Returns the largest Node by key in the treap if there is one.
Use `getEntryForExisting()` to replace/remove this Node from the treap.

#### `getEntryFor`

```zig
pub fn getEntryFor(self: *Self, key: Key) Entry
```

Lookup the Entry for the given key in the treap.
The Entry act's as a slot in the treap to insert/replace/remove the node associated with the key.

#### `getEntryForExisting`

```zig
pub fn getEntryForExisting(self: *Self, node: *Node) Entry
```

Get an entry for a Node that currently exists in the treap.
It is undefined behavior if the Node is not currently inserted in the treap.
The Entry act's as a slot in the treap to insert/replace/remove the node associated with the key.

#### `inorderIterator`

```zig
pub fn inorderIterator(self: *Self) InorderIterator
```


