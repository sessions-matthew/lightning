//! Native Zig `.dylib` Editor Plugin: Python Language Server (`ruff` / `pyright` + `uv`) (`plugins/python_lsp.zig`).
//!
//! Compiled into `zig-out/plugins/libpython_lsp.dylib` (~159 KB, zero Skia linkage).

const std = @import("std");
const sdk = @import("plugin_sdk");

const SNIPPET_DATACLASS =
    \\from dataclasses import dataclass
    \\
    \\
    \\@dataclass(frozen=True, slots=True)
    \\class PipelineConfig:
    \\    name: str
    \\    batch_size: int = 64
    \\    learning_rate: float = 1e-3
    \\
;

const SNIPPET_PYTEST =
    \\import pytest
    \\
    \\
    \\def test_pipeline_execution() -> None:
    \\    result = 2 + 2
    \\    assert result == 4
    \\
;

comptime {
    sdk.exportLspLanguagePlugin(.{
        .id = "builtin.python_lsp",
        .display_name = "Python Language Server (ruff / pyright)",
        .version = "0.1.0",
        .sidebar_title = "PYTHON (RUFF / PYRIGHT)",
        .language = .python,
        .ready_status = "Ready (ruff / pyright + uv engine)",
        .commands = &.{
            .{
                .id = "python_lsp.insert_dataclass",
                .title = "Python (ruff/pyright): Insert Typed @dataclass Skeleton",
                .category = "Python LSP",
                .hint = "@dataclass",
                .snippet = SNIPPET_DATACLASS,
                .notice = "Python: Inserted typed @dataclass(frozen=True, slots=True)",
            },
            .{
                .id = "python_lsp.insert_pytest",
                .title = "Python (uv + pytest): Insert pytest Fixture & Test Suite",
                .category = "Python LSP",
                .hint = "pytest",
                .snippet = SNIPPET_PYTEST,
                .notice = "Python (uv): Inserted pytest unit test skeleton",
            },
        },
    });
}
