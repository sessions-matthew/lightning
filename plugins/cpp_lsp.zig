//! Native Zig `.dylib` Editor Plugin: C/C++ Language Server (`clangd`) (`plugins/cpp_lsp.zig`).
//!
//! Compiled into `zig-out/plugins/libcpp_lsp.dylib` (~69 KB, zero Skia linkage).

const std = @import("std");
const sdk = @import("plugin_sdk");

const SNIPPET_HEADER_GUARD =
    \\#pragma once
    \\
    \\#include <cstdint>
    \\#include <string_view>
    \\
    \\namespace project {
    \\
    \\} // namespace project
    \\
;

const SNIPPET_RAII_CLASS =
    \\class EngineComponent {
    \\public:
    \\    EngineComponent() = default;
    \\    ~EngineComponent() noexcept = default;
    \\
    \\    EngineComponent(const EngineComponent&) = delete;
    \\    EngineComponent& operator=(const EngineComponent&) = delete;
    \\    EngineComponent(EngineComponent&&) noexcept = default;
    \\    EngineComponent& operator=(EngineComponent&&) noexcept = default;
    \\
    \\    void update(double dt) {
    \\        (void)dt;
    \\    }
    \\};
    \\
;

comptime {
    sdk.exportLspLanguagePlugin(.{
        .id = "builtin.cpp_lsp",
        .display_name = "C/C++ Language Server (clangd)",
        .version = "0.1.0",
        .sidebar_title = "C/C++ (clangd)",
        .language = .cpp,
        .ready_status = "Ready (clangd + AST engine)",
        .format_indent = 4,
        .format_label = "Format C++",
        .format_notice = "clangd: Formatted C/C++ buffer (4-space style)",
        .commands = &.{
            .{
                .id = "cpp_lsp.insert_header_guard",
                .title = "C/C++ (clangd): Insert #pragma once & Header Guard",
                .category = "C/C++ LSP",
                .hint = "Header",
                .snippet = SNIPPET_HEADER_GUARD,
                .notice = "clangd: Inserted #pragma once & namespace header",
            },
            .{
                .id = "cpp_lsp.insert_class",
                .title = "C/C++ (clangd): Insert RAII C++ Class Skeleton",
                .category = "C/C++ LSP",
                .hint = "Class",
                .snippet = SNIPPET_RAII_CLASS,
                .notice = "clangd: Inserted C++20 RAII class skeleton",
            },
        },
    });
}
