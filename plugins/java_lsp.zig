//! Native Zig `.dylib` Editor Plugin: Java Language Server (`jdtls`) (`plugins/java_lsp.zig`).
//!
//! Compiled into `zig-out/plugins/libjava_lsp.dylib` (~69 KB, zero Skia linkage).
//!
//! Features:
//!   - Spawns & communicates with Eclipse JDT Language Server (`jdtls`) over non-blocking (`O_NONBLOCK`)
//!     JSON-RPC 2.0 stdio pipes (`initialize`, `textDocument/didOpen`, `didChange`, `didSave`, `publishDiagnostics`).
//!   - Automatic zero-allocation Java lexical & AST fallback when `jdtls` is starting up or not installed.
//!   - Interactive Java Symbol Outline (`package`, `class`, `interface`, `enum`, `record`, methods)
//!     with live search filter and click-to-jump navigation.
//!   - Live Java Diagnostics & code quality hints with one-click jump to offending line.
//!   - Java Brace & Indentation Formatter, `public class` + `main` generator, and Java Record generator.

const std = @import("std");
const sdk = @import("plugin_sdk");

fn isJavaBuffer(buf: sdk.BufferInfo) bool {
    return sdk.lsp.LspLanguage.java.matchesPath(buf.file_path) or
        std.mem.indexOfPos(u8, buf.text, 0, "public class ") != null or
        std.mem.indexOfPos(u8, buf.text, 0, "System.out.") != null or
        std.mem.indexOfPos(u8, buf.text, 0, "import java.") != null;
}

const JAVA_MAIN_SNIPPET =
    \\package com.workspace.app;
    \\
    \\import java.util.List;
    \\
    \\public class Application {
    \\    public static void main(String[] args) {
    \\        System.out.println("Application started");
    \\    }
    \\}
    \\
;

const JAVA_RECORD_SNIPPET =
    \\public record ServiceConfig(String host, int port, boolean tlsEnabled) {
    \\    public String endpoint() {
    \\        return (tlsEnabled ? "https://" : "http://") + host + ":" + port;
    \\    }
    \\}
    \\
;

comptime {
    sdk.exportLspLanguagePlugin(.{
        .id = "builtin.java_lsp",
        .display_name = "Java Language Server (jdtls)",
        .version = "0.1.0",
        .sidebar_title = "JAVA LANGUAGE SERVER (JDTLS)",
        .language = .java,
        .ready_status = "Ready (jdtls + AST engine)",
        .format_indent = 4,
        .format_label = "Format Java",
        .format_notice = "jdtls: Formatted Java buffer (4-space Google Java style)",
        .is_buffer_match = isJavaBuffer,
        .commands = &.{
            .{
                .id = "java_lsp.insert_main_class",
                .title = "Java (jdtls): Insert Public Class & main() Method",
                .category = "Java LSP",
                .hint = "Main",
                .snippet = JAVA_MAIN_SNIPPET,
                .notice = "jdtls: Inserted Java class & public static void main",
                .btn_label = "+ Main##java_main_btn",
                .btn_width = 72,
            },
            .{
                .id = "java_lsp.insert_record",
                .title = "Java (jdtls): Insert Immutable Java Record",
                .category = "Java LSP",
                .hint = "Record",
                .snippet = JAVA_RECORD_SNIPPET,
                .notice = "jdtls: Inserted Java 21 record declaration",
                .btn_label = "+ Record##java_rec_btn",
                .btn_width = 74,
            },
        },
    });
}
