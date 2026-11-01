//! Native Zig `.dylib` Editor Plugin: Rust Language Server (`rust-analyzer`) (`plugins/rust_lsp.zig`).
//!
//! Compiled into `zig-out/plugins/librust_lsp.dylib` (~159 KB, zero Skia linkage).

const std = @import("std");
const sdk = @import("plugin_sdk");

const SNIPPET_STRUCT =
    \\#[derive(Debug, Clone, PartialEq, Eq)]
    \\pub struct EngineConfig {
    \\    pub workers: usize,
    \\    pub enable_simd: bool,
    \\}
    \\
    \\impl EngineConfig {
    \\    pub fn new(workers: usize) -> Self {
    \\        Self {
    \\            workers,
    \\            enable_simd: true,
    \\        }
    \\    }
    \\}
    \\
;

const SNIPPET_TESTS =
    \\#[cfg(test)]
    \\mod tests {
    \\    use super::*;
    \\
    \\    #[test]
    \\    fn it_works() {
    \\        assert_eq!(2 + 2, 4);
    \\    }
    \\}
    \\
;

comptime {
    sdk.exportLspLanguagePlugin(.{
        .id = "builtin.rust_lsp",
        .display_name = "Rust Language Server (rust-analyzer)",
        .version = "0.1.0",
        .sidebar_title = "RUST (RUST-ANALYZER)",
        .language = .rust,
        .ready_status = "Ready (rust-analyzer + clippy engine)",
        .format_indent = 4,
        .format_label = "rustfmt",
        .format_notice = "rustfmt: Formatted Rust buffer (4-space style)",
        .commands = &.{
            .{
                .id = "rust_lsp.insert_struct",
                .title = "Rust (rust-analyzer): Insert #[derive] Struct & impl Block",
                .category = "Rust LSP",
                .hint = "Struct",
                .snippet = SNIPPET_STRUCT,
                .notice = "rust-analyzer: Inserted #[derive] struct & impl block",
            },
            .{
                .id = "rust_lsp.insert_tests",
                .title = "Rust (rust-analyzer): Insert #[cfg(test)] Module",
                .category = "Rust LSP",
                .hint = "#[test]",
                .snippet = SNIPPET_TESTS,
                .notice = "rust-analyzer: Inserted #[cfg(test)] module",
            },
        },
    });
}
