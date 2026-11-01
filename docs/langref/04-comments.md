# Comments

> Zig 0.17.0 Language Reference — Section 4 of 53  
> [← Back to Language Reference Index](../langref.md)

<a id="Comments"></a>
## Comments

There are three types of comments. Normal comments are ignored, while [Doc Comments](#Doc-Comments)
and [Top-Level Doc Comments](#Top-Level-Doc-Comments) are used by the compiler to generate
the package documentation.

**`comments.zig`**
```zig
const print = @import("std").debug.print;

pub fn main() void {
    // Comments in Zig start with "//" and end at the next LF byte (end of line).
    // The line below is a comment and won't be executed.

    //print("Hello?", .{});

    print("Hello, world!\n", .{}); // another comment
}
```

```sh
$ zig build-exe comments.zig
$ ./comments
Hello, world!
```

There are no multiline comments. Zig has the property that each line
of code can be tokenized independently.

<a id="Doc-Comments"></a>
### Doc Comments

A doc comment is one that begins with exactly three slashes (i.e.
`///` but not `////`);
multiple doc comments in a row are merged together to form a multiline
doc comment. The doc comment documents whatever immediately follows it.

**`doc_comments.zig`**
```zig
/// A structure for storing a timestamp, with nanosecond precision (this is a
/// multiline doc comment).
const Timestamp = struct {
    /// The number of seconds since the epoch (this is also a doc comment).
    seconds: i64, // signed so we can represent pre-1970 (not a doc comment)
    /// The number of nanoseconds past the second (doc comment again).
    nanos: u32,

    /// Returns a `Timestamp` struct representing the Unix epoch; that is, the
    /// moment of 1970 Jan 1 00:00:00 UTC (this is a doc comment too).
    pub fn unixEpoch() Timestamp {
        return Timestamp{
            .seconds = 0,
            .nanos = 0,
        };
    }
};
```

Doc comments are only allowed in certain places; it is a compile error to
have a doc comment in an unexpected place, such as in the middle of an expression,
or just before a non-doc comment.

**`invalid_doc-comment.zig`**
```zig
/// doc-comment
//! top-level doc-comment
const std = @import("std");
```

```sh
$ zig build-obj invalid_doc-comment.zig
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/doc/langref/invalid_doc-comment.zig:1:16: error: expected type expression, found 'a document comment'
/// doc-comment
               ^
```

**`unattached_doc-comment.zig`**
```zig
pub fn main() void {}

/// End of file
```

```sh
$ zig build-obj unattached_doc-comment.zig
/private/tmp/s-gZHkm6ql/zig-20261003-6388-n6l20x/zig-0.17.0/doc/langref/unattached_doc-comment.zig:3:1: error: unattached documentation comment
/// End of file
^~~~~~~~~~~~~~~
```

Doc comments can be interleaved with normal comments, which are ignored.

<a id="Top-Level-Doc-Comments"></a>
### Top-Level Doc Comments

A top-level doc comment is one that begins with two slashes and an exclamation
point: `//!`; it documents the type which owns the containing
[Namespace](#Namespace).

It is a compile error if a top-level doc comment is not placed at the start
of a namespace, before any expressions.

**`tldoc_comments.zig`**
```zig
//! Provides functions for retrieving the current date and time with varying
//! degrees of precision and accuracy.

const S = struct {
    //! Top level comments are allowed inside namespaces other than the
    //! implicit struct created by files, but it is not very useful. Currently,
    //! when producing the package documentation, these comments are ignored.
};
```
