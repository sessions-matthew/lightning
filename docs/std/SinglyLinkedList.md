# `std.SinglyLinkedList`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/SinglyLinkedList.zig`  
> [← Back to Standard Library Index](README.md)

A singly-linked list is headed by a single forward pointer. The elements
are singly-linked for minimum space and pointer manipulation overhead at
the expense of O(n) removal for arbitrary elements. New elements can be
added to the list after an existing element or at the head of the list.

A singly-linked list may only be traversed in the forward direction.

Singly-linked lists are useful under these conditions:
* Ability to preallocate elements / requirement of infallibility for
  insertion.
* Ability to allocate elements intrusively along with other data.
* Homogenous elements.

## Fields

- `first: ?*Node = null`
  

## Types

### `Node`

This struct contains only a next pointer and not any data payload. The
intended usage is to embed it intrusively into another data structure and
access the data with `@fieldParentPtr`.

### Fields

- `next: ?*Node = null`
  

### Functions

#### `insertAfter`

```zig
pub fn insertAfter(node: *Node, new_node: *Node) void
```


#### `removeNext`

```zig
pub fn removeNext(node: *Node) ?*Node
```

Remove the node after the one provided, returning it.

#### `findLast`

```zig
pub fn findLast(node: *Node) *Node
```

Iterate over the singly-linked list from this node, until the final
node is found.

This operation is O(N). Instead of calling this function, consider
using a different data structure.

#### `countChildren`

```zig
pub fn countChildren(node: *const Node) usize
```

Iterate over each next node, returning the count of all nodes except
the starting one.

This operation is O(N). Instead of calling this function, consider
using a different data structure.

#### `reverse`

```zig
pub fn reverse(indirect: *?*Node) void
```

Reverse the list starting from this node in-place.

This operation is O(N). Instead of calling this function, consider
using a different data structure.

## Functions

### `prepend`

```zig
pub fn prepend(list: *SinglyLinkedList, new_node: *Node) void
```


### `remove`

```zig
pub fn remove(list: *SinglyLinkedList, node: *const Node) void
```

Remove `node` from the list.
Asserts that `node` is in the list.

### `popFirst`

```zig
pub fn popFirst(list: *SinglyLinkedList) ?*Node
```

Remove and return the first node in the list.

### `len`

```zig
pub fn len(list: SinglyLinkedList) usize
```

Iterate over all nodes, returning the count.

This operation is O(N). Consider tracking the length separately rather than
computing it.

