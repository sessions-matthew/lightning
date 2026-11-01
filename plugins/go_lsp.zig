//! Native Zig `.dylib` Editor Plugin: Go Language Server (`gopls`) (`plugins/go_lsp.zig`).
//!
//! Compiled into `zig-out/plugins/libgo_lsp.dylib` (~69 KB, zero Skia linkage).

const std = @import("std");
const sdk = @import("plugin_sdk");

const SNIPPET_ERR_CHECK =
    \\    if err != nil {
    \\        return fmt.Errorf("operation failed: %w", err)
    \\    }
    \\
;

const SNIPPET_PKG_MAIN =
    \\package main
    \\
    \\import (
    \\    "context"
    \\    "fmt"
    \\)
    \\
    \\type Service struct {
    \\    Name string
    \\}
    \\
    \\func (s *Service) Run(ctx context.Context) error {
    \\    _ = ctx
    \\    fmt.Printf("service %s running\n", s.Name)
    \\    return nil
    \\}
    \\
    \\func main() {
    \\    svc := &Service{Name: "worker"}
    \\    _ = svc.Run(context.Background())
    \\}
    \\
;

comptime {
    sdk.exportLspLanguagePlugin(.{
        .id = "builtin.go_lsp",
        .display_name = "Go Language Server (gopls)",
        .version = "0.1.0",
        .sidebar_title = "Go (gopls)",
        .language = .go,
        .ready_status = "Ready (gopls + AST engine)",
        .format_indent = 4,
        .format_label = "gofmt",
        .format_notice = "gopls: Formatted Go buffer (gofmt style)",
        .commands = &.{
            .{
                .id = "go_lsp.insert_err_check",
                .title = "Go (gopls): Insert if err != nil Guard",
                .category = "Go LSP",
                .hint = "if err",
                .snippet = SNIPPET_ERR_CHECK,
                .notice = "gopls: Inserted wrapped if err != nil guard",
            },
            .{
                .id = "go_lsp.insert_package_main",
                .title = "Go (gopls): Insert package main & Worker Skeleton",
                .category = "Go LSP",
                .hint = "main.go",
                .snippet = SNIPPET_PKG_MAIN,
                .notice = "gopls: Inserted Go package main & Service struct",
            },
        },
    });
}
