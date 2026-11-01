//! Native Zig `.dylib` Editor Plugin: TypeScript / JavaScript Language Server (`tsserver` / `biome`) (`plugins/ts_lsp.zig`).
//!
//! Compiled into `zig-out/plugins/libts_lsp.dylib` (~159 KB, zero Skia linkage).

const std = @import("std");
const sdk = @import("plugin_sdk");

const SNIPPET_INTERFACE =
    \\export interface ApiResponse<T> {
    \\  readonly ok: boolean;
    \\  readonly status: number;
    \\  readonly data: T;
    \\}
    \\
    \\export async function fetchJson<T>(url: string): Promise<ApiResponse<T>> {
    \\  const res = await fetch(url);
    \\  const data = (await res.json()) as T;
    \\  return { ok: res.ok, status: res.status, data };
    \\}
    \\
;

comptime {
    sdk.exportLspLanguagePlugin(.{
        .id = "builtin.ts_lsp",
        .display_name = "TypeScript / JS Language Server",
        .version = "0.1.0",
        .sidebar_title = "TYPESCRIPT (TSSERVER)",
        .language = .typescript,
        .ready_status = "Ready (tsserver / biome engine)",
        .format_indent = 2,
        .format_label = "Format TS",
        .format_notice = "TypeScript: Formatted buffer (2-space style)",
        .commands = &.{
            .{
                .id = "ts_lsp.insert_interface",
                .title = "TypeScript (tsserver): Insert Exported Interface & Handler",
                .category = "TypeScript LSP",
                .hint = "Interface",
                .snippet = SNIPPET_INTERFACE,
                .notice = "TypeScript: Inserted generic ApiResponse<T> interface & async fetch",
            },
        },
    });
}
