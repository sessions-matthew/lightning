# `std.DoublyLinkedList`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/DoublyLinkedList.zig`  
> [← Back to Standard Library Index](README.md)

A doubly-linked list has a pair of pointers to both the head and
tail of the list. List elements have pointers to both the previous
and next elements in the sequence. The list can be traversed both
forward and backward. Some operations that take linear O(n) time
with a singly-linked list can be done without traversal in constant
O(1) time with a doubly-linked list:

* Removing an element.
* Inserting a new element before an existing element.
* Pushing or popping an element from the end of the list.

## Fields

- `first: ?*Node = null`
  
- `last: ?*Node = null`
  

## Types

### `Node`

This struct contains only the prev and next pointers and not any data
payload. The intended usage is to embed it intrusively into another data
structure and access the data with `@fieldParentPtr`.

### Fields

- `prev: ?*Node = null`
  
- `next: ?*Node = null`
  

## Functions

### `insertAfter`

```zig
pub fn insertAfter(list: *DoublyLinkedList, existing_node: *Node, new_node: *Node) void
```


### `insertBefore`

```zig
pub fn insertBefore(list: *DoublyLinkedList, existing_node: *Node, new_node: *Node) void
```


### `concatByMoving`

```zig
pub fn concatByMoving(list1: *DoublyLinkedList, list2: *DoublyLinkedList) void
```

Concatenate list2 onto the end of list1, removing all entries from the former.

Arguments:
    list1: the list to concatenate onto
    list2: the list to be concatenated

### `append`

```zig
pub fn append(list: *DoublyLinkedList, new_node: *Node) void
```

Insert a new node at the end of the list.

Arguments:
    new_node: Pointer to the new node to insert.

### `prepend`

```zig
pub fn prepend(list: *DoublyLinkedList, new_node: *Node) void
```

Insert a new node at the beginning of the list.

Arguments:
    new_node: Pointer to the new node to insert.

### `remove`

```zig
pub fn remove(list: *DoublyLinkedList, node: *const Node) void
```

Remove a node from the list.
Assumes the node is in the list.

Arguments:
    node: Pointer to the node to be removed.

### `popLast`

```zig
pub fn popLast(list: *DoublyLinkedList) ?*Node
```

Remove and return a pointer to the last node in the list.

### `popFirst`

```zig
pub fn popFirst(list: *DoublyLinkedList) ?*Node
```

Remove and return a pointer to the first node in the list.

### `len`

```zig
pub fn len(list: DoublyLinkedList) usize
```

Iterate over all nodes, returning the count.

This operation is O(N). Consider tracking the length separately rather than
computing it.

## Constants & Variables

- **`pop`**: Deprecated in favor of `popLast`

