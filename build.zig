const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const is_macos = (target.result.os.tag == .macos);
    const is_windows = (target.result.os.tag == .windows);
    const is_linux = (target.result.os.tag == .linux);
    const skia_lib_dir = if (is_windows)
        (if (target.result.cpu.arch == .aarch64)
            b.path("vendor/skiasharp/lib/win-arm64")
        else
            b.path("vendor/skiasharp/lib/win-x64"))
    else if (is_linux)
        (if (target.result.cpu.arch == .aarch64)
            b.path("vendor/skiasharp/lib/linux-arm64")
        else if (target.result.cpu.arch == .arm)
            b.path("vendor/skiasharp/lib/linux-arm")
        else
            b.path("vendor/skiasharp/lib/linux-x64"))
    else
        b.path("vendor/skiasharp/lib");

    // ========================================================================
    // 1. Framework Modules (`skia`, `ui`, `platform`)
    // ========================================================================

    // Core `skia` module (idiomatic Zig wrapper + direct extern C bindings, zero @cImport)
    const skia_mod = b.addModule("skia", .{
        .root_source_file = b.path("src/skia/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    skia_mod.addLibraryPath(skia_lib_dir);
    skia_mod.linkSystemLibrary("SkiaSharp", .{});
    if (!is_windows) {
        skia_mod.addRPath(skia_lib_dir);
    }

    // `ui` module (2-phase input/paint widget toolkit, layout engine, SkTextBlob cache)
    const ui_mod = b.addModule("ui", .{
        .root_source_file = b.path("src/ui/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "skia", .module = skia_mod },
        },
    });
    if (is_macos) {
        ui_mod.linkFramework("CoreGraphics", .{});
        ui_mod.linkFramework("CoreFoundation", .{});
        ui_mod.linkFramework("PDFKit", .{});
    }

    // `platform` module (C-ABI plugin boundary, StateStore, dylib hot-loader, macOS Metal / Win32 host)
    const platform_mod = b.addModule("platform", .{
        .root_source_file = b.path("src/platform/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "skia", .module = skia_mod },
        },
    });
    if (is_macos) {
        platform_mod.linkFramework("Cocoa", .{});
        platform_mod.linkSystemLibrary("objc", .{});
    } else if (is_windows) {
        platform_mod.linkSystemLibrary("user32", .{});
        platform_mod.linkSystemLibrary("gdi32", .{});
        platform_mod.linkSystemLibrary("comdlg32", .{});
        platform_mod.linkSystemLibrary("dwmapi", .{});
        platform_mod.linkSystemLibrary("ole32", .{});
        platform_mod.linkSystemLibrary("shell32", .{});
        platform_mod.linkSystemLibrary("ws2_32", .{});
    }
    ui_mod.addImport("platform", platform_mod);

    // Lightweight `plugin_sdk` module for standalone `.dylib`/`.dll` editor plugins (zero Skia linkage!)
    const plugin_opt: std.builtin.OptimizeMode = if (optimize == .debug) .fast else optimize;
    const plugin_sdk_mod = b.addModule("plugin_sdk", .{
        .root_source_file = b.path("src/platform/plugin_sdk.zig"),
        .target = target,
        .optimize = plugin_opt,
        .link_libc = true,
    });

    // Install SkiaSharp runtime shared library so installed binaries find it
    const install_dylib = if (is_windows) blk: {
        const win_dll_path = if (target.result.cpu.arch == .aarch64)
            b.path("vendor/skiasharp/lib/win-arm64/libSkiaSharp.dll")
        else
            b.path("vendor/skiasharp/lib/win-x64/libSkiaSharp.dll");
        const inst_bin = b.addInstallBinFile(win_dll_path, "libSkiaSharp.dll");
        const inst_lib = b.addInstallLibFile(win_dll_path, "libSkiaSharp.dll");
        b.getInstallStep().dependOn(&inst_lib.step);
        break :blk inst_bin;
    } else if (is_linux) blk: {
        const linux_so_path = if (target.result.cpu.arch == .aarch64)
            b.path("vendor/skiasharp/lib/linux-arm64/libSkiaSharp.so")
        else if (target.result.cpu.arch == .arm)
            b.path("vendor/skiasharp/lib/linux-arm/libSkiaSharp.so")
        else
            b.path("vendor/skiasharp/lib/linux-x64/libSkiaSharp.so");
        const inst_so = b.addInstallLibFile(linux_so_path, "libSkiaSharp.so");
        const inst_soname = b.addInstallLibFile(linux_so_path, "libSkiaSharp.so.153.0.0");
        b.getInstallStep().dependOn(&inst_soname.step);
        break :blk inst_so;
    } else b.addInstallLibFile(
        b.path("vendor/skiasharp/lib/libSkiaSharp.dylib"),
        "libSkiaSharp.dylib",
    );
    b.getInstallStep().dependOn(&install_dylib.step);

    // ========================================================================
    // 2. Shared Window Host Executable (`lightning` / `skia-window`)
    // ========================================================================
    const window_exe = b.addExecutable(.{
        .name = "lightning",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/window_main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "skia", .module = skia_mod },
                .{ .name = "platform", .module = platform_mod },
            },
        }),
    });
    if (is_macos) {
        window_exe.root_module.linkFramework("Cocoa", .{});
        window_exe.root_module.linkFramework("Metal", .{});
        window_exe.root_module.linkFramework("QuartzCore", .{});
        window_exe.root_module.linkFramework("CoreFoundation", .{});
        window_exe.root_module.linkSystemLibrary("objc", .{});
        window_exe.root_module.addRPath(.{ .cwd_relative = "@executable_path/../lib" });
    } else if (is_windows) {
        window_exe.subsystem = .windows;
        window_exe.root_module.linkSystemLibrary("user32", .{});
        window_exe.root_module.linkSystemLibrary("gdi32", .{});
        window_exe.root_module.linkSystemLibrary("comdlg32", .{});
        window_exe.root_module.linkSystemLibrary("dwmapi", .{});
        window_exe.root_module.linkSystemLibrary("ole32", .{});
        window_exe.root_module.linkSystemLibrary("shell32", .{});
        window_exe.root_module.linkSystemLibrary("ws2_32", .{});
    } else if (is_linux) {
        window_exe.root_module.addRPath(.{ .cwd_relative = "$ORIGIN/../lib" });
    }
    const install_window_exe = b.addInstallArtifact(window_exe, .{});
    b.getInstallStep().dependOn(&install_window_exe.step);

    // Also install skia-window alias in zig-out/bin for backward compatibility
    const install_window_alias = b.addInstallArtifact(window_exe, .{
        .dest_sub_path = if (is_windows) "skia-window.exe" else "skia-window",
    });
    b.getInstallStep().dependOn(&install_window_alias.step);

    // ========================================================================
    // 3. Main Editor Application (`src/app/main.zig` -> `libeditor_app.dylib`)
    // ========================================================================
    const editor_app_lib = addHotReloadPlugin(b, "editor_app", "src/app/main.zig", target, optimize, skia_mod, ui_mod, platform_mod);
    const install_editor_app = b.addInstallArtifact(editor_app_lib, .{});
    b.getInstallStep().dependOn(&install_editor_app.step);

    // Native Zig `.dylib` Editor Extensions (`plugins/*.zig` -> `zig-out/plugins/lib*.dylib`)
    const plugins_step = b.step("plugins", "Compile native Zig .dylib editor plugins into zig-out/plugins/");
    const extension_specs = [_]struct { name: []const u8, src: []const u8 }{
        .{ .name = "doc_metrics", .src = "plugins/doc_metrics.zig" },
        .{ .name = "cpp_lsp", .src = "plugins/cpp_lsp.zig" },
        .{ .name = "java_lsp", .src = "plugins/java_lsp.zig" },
        .{ .name = "go_lsp", .src = "plugins/go_lsp.zig" },
        .{ .name = "sv_lsp", .src = "plugins/sv_lsp.zig" },
        .{ .name = "zig_lsp", .src = "plugins/zig_lsp.zig" },
        .{ .name = "rust_lsp", .src = "plugins/rust_lsp.zig" },
        .{ .name = "python_lsp", .src = "plugins/python_lsp.zig" },
        .{ .name = "ts_lsp", .src = "plugins/ts_lsp.zig" },
        .{ .name = "hdl_lsp", .src = "plugins/hdl_lsp.zig" },
        .{ .name = "rtl_sim", .src = "plugins/rtl_sim.zig" },
        .{ .name = "hex_inspector", .src = "plugins/hex_inspector.zig" },
        .{ .name = "lldb_debug", .src = "plugins/lldb_debug.zig" },
        .{ .name = "git_lens", .src = "plugins/git_lens.zig" },
        .{ .name = "pdf_reader", .src = "plugins/pdf_reader.zig" },
    };

    const app_step = b.step("app", "Recompile only libeditor_app.dylib for live hot-reloading");
    app_step.dependOn(&install_editor_app.step);

    const run_step = b.step("run", "Run the Lightning application");
    const run_editor_cmd = b.addRunArtifact(window_exe);
    run_editor_cmd.step.dependOn(&install_dylib.step);
    run_editor_cmd.step.dependOn(&install_window_exe.step);
    run_editor_cmd.step.dependOn(&install_editor_app.step);

    for (extension_specs) |spec| {
        const ext_lib = addEditorExtensionPlugin(b, spec.name, spec.src, target, plugin_opt, plugin_sdk_mod);
        const install_ext = b.addInstallArtifact(ext_lib, .{
            .dest_dir = .{ .override = .{ .custom = "plugins" } },
        });
        b.getInstallStep().dependOn(&install_ext.step);
        plugins_step.dependOn(&install_ext.step);
        run_editor_cmd.step.dependOn(&install_ext.step);
    }

    run_editor_cmd.addArgs(&.{ "--dylib", "zig-out/lib/libeditor_app.dylib", "--title", "Lightning" });
    run_editor_cmd.addPassthruArgs();
    run_step.dependOn(&run_editor_cmd.step);

    // Keep `run-window` alias for convenience
    const run_window_step = b.step("run-window", "Run the main Editor application (alias for `run`)");
    run_window_step.dependOn(&run_editor_cmd.step);

    // ========================================================================
    // 4. Dedicated Feature Examples (`examples/`)
    // ========================================================================

    // Example A: Studio Showcase (`examples/studio/main.zig`)
    const studio_lib = addHotReloadPlugin(b, "example_studio", "examples/studio/main.zig", target, optimize, skia_mod, ui_mod, platform_mod);
    const install_studio = b.addInstallArtifact(studio_lib, .{});

    const studio_step = b.step("example-studio", "Recompile only libexample_studio.dylib for hot-reloading");
    studio_step.dependOn(&install_studio.step);

    const run_studio_step = b.step("run-studio", "Run the Studio feature showcase example (animation, scissor, useState)");
    const run_studio_cmd = b.addRunArtifact(window_exe);
    run_studio_cmd.step.dependOn(&install_dylib.step);
    run_studio_cmd.step.dependOn(&install_window_exe.step);
    run_studio_cmd.step.dependOn(&install_studio.step);
    run_studio_cmd.addArgs(&.{ "--dylib", "zig-out/lib/libexample_studio.dylib", "--title", "Example: Zig + Skia Studio" });
    run_studio_cmd.addPassthruArgs();
    run_studio_step.dependOn(&run_studio_cmd.step);

    // Example B: Scrollable Containers (`examples/scrollable/main.zig`)
    const scrollable_lib = addHotReloadPlugin(b, "example_scrollable", "examples/scrollable/main.zig", target, optimize, skia_mod, ui_mod, platform_mod);
    const install_scrollable = b.addInstallArtifact(scrollable_lib, .{});

    const scrollable_step = b.step("example-scrollable", "Recompile only libexample_scrollable.dylib for hot-reloading");
    scrollable_step.dependOn(&install_scrollable.step);

    const run_scrollable_step = b.step("run-scrollable", "Run the Scrollable containers & virtual feed example");
    const run_scrollable_cmd = b.addRunArtifact(window_exe);
    run_scrollable_cmd.step.dependOn(&install_dylib.step);
    run_scrollable_cmd.step.dependOn(&install_window_exe.step);
    run_scrollable_cmd.step.dependOn(&install_scrollable.step);
    run_scrollable_cmd.addArgs(&.{ "--dylib", "zig-out/lib/libexample_scrollable.dylib", "--title", "Example: Scrollable Containers" });
    run_scrollable_cmd.addPassthruArgs();
    run_scrollable_step.dependOn(&run_scrollable_cmd.step);

    // Example C: Headless Raster CLI Demo (`examples/raster_cli/main.zig`)
    const raster_cli_exe = b.addExecutable(.{
        .name = "example-raster-cli",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/raster_cli/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "skia", .module = skia_mod },
                .{ .name = "ui", .module = ui_mod },
                .{ .name = "platform", .module = platform_mod },
            },
        }),
    });
    if (is_macos) {
        raster_cli_exe.root_module.addRPath(.{ .cwd_relative = "@executable_path/../lib" });
    } else if (is_linux) {
        raster_cli_exe.root_module.addRPath(.{ .cwd_relative = "$ORIGIN/../lib" });
    }
    const install_raster_cli = b.addInstallArtifact(raster_cli_exe, .{});

    const run_raster_step = b.step("run-raster-cli", "Run the headless Skia raster PNG encoding CLI example");
    const run_raster_cmd = b.addRunArtifact(raster_cli_exe);
    run_raster_cmd.step.dependOn(&install_dylib.step);
    run_raster_cmd.step.dependOn(&install_raster_cli.step);
    run_raster_cmd.addPassthruArgs();
    run_raster_step.dependOn(&run_raster_cmd.step);

    // Example D: Markdown Renderer Showcase (`examples/markdown/main.zig`)
    const markdown_lib = addHotReloadPlugin(b, "example_markdown", "examples/markdown/main.zig", target, optimize, skia_mod, ui_mod, platform_mod);
    const install_markdown = b.addInstallArtifact(markdown_lib, .{});

    const markdown_step = b.step("example-markdown", "Recompile only libexample_markdown.dylib for hot-reloading");
    markdown_step.dependOn(&install_markdown.step);

    const run_markdown_step = b.step("run-markdown", "Run the Markdown renderer component showcase example");
    const run_markdown_cmd = b.addRunArtifact(window_exe);
    run_markdown_cmd.step.dependOn(&install_dylib.step);
    run_markdown_cmd.step.dependOn(&install_window_exe.step);
    run_markdown_cmd.step.dependOn(&install_markdown.step);
    run_markdown_cmd.addArgs(&.{ "--dylib", "zig-out/lib/libexample_markdown.dylib", "--title", "Example: Markdown Renderer" });
    run_markdown_cmd.addPassthruArgs();
    run_markdown_step.dependOn(&run_markdown_cmd.step);

    // Example E: Text & Code Editor Showcase (`examples/code_editor/main.zig`)
    const code_editor_lib = addHotReloadPlugin(b, "example_code_editor", "examples/code_editor/main.zig", target, optimize, skia_mod, ui_mod, platform_mod);
    const install_code_editor = b.addInstallArtifact(code_editor_lib, .{});

    const code_editor_step = b.step("example-code-editor", "Recompile only libexample_code_editor.dylib for hot-reloading");
    code_editor_step.dependOn(&install_code_editor.step);

    const run_code_editor_step = b.step("run-code-editor", "Run the interactive Text & Code Editor component showcase example");
    const run_code_editor_cmd = b.addRunArtifact(window_exe);
    run_code_editor_cmd.step.dependOn(&install_dylib.step);
    run_code_editor_cmd.step.dependOn(&install_window_exe.step);
    run_code_editor_cmd.step.dependOn(&install_code_editor.step);
    run_code_editor_cmd.addArgs(&.{ "--dylib", "zig-out/lib/libexample_code_editor.dylib", "--title", "Example: Text & Code Editor" });
    run_code_editor_cmd.addPassthruArgs();
    run_code_editor_step.dependOn(&run_code_editor_cmd.step);

    // Build all examples step
    const examples_step = b.step("examples", "Compile all example programs and plugins");
    examples_step.dependOn(&install_studio.step);
    examples_step.dependOn(&install_scrollable.step);
    examples_step.dependOn(&install_raster_cli.step);
    examples_step.dependOn(&install_markdown.step);
    examples_step.dependOn(&install_code_editor.step);

    // ========================================================================
    // 5. Unit Tests (`zig build test`)
    // ========================================================================
    const skia_tests = b.addTest(.{ .root_module = skia_mod });
    const run_skia_tests = b.addRunArtifact(skia_tests);

    const ui_tests = b.addTest(.{ .root_module = ui_mod });
    const run_ui_tests = b.addRunArtifact(ui_tests);

    const platform_tests = b.addTest(.{ .root_module = platform_mod });
    const run_platform_tests = b.addRunArtifact(platform_tests);

    const app_tests = b.addTest(.{ .root_module = editor_app_lib.root_module });
    const run_app_tests = b.addRunArtifact(app_tests);
    run_app_tests.step.dependOn(plugins_step);

    const test_step = b.step("test", "Run all framework and app unit tests");
    test_step.dependOn(&run_skia_tests.step);
    test_step.dependOn(&run_ui_tests.step);
    test_step.dependOn(&run_platform_tests.step);
    test_step.dependOn(&run_app_tests.step);

    // ========================================================================
    // 6. Automated Performance Benchmarks (`zig build bench` & `zig build microbench`)
    // ========================================================================
    const microbench_exe = b.addExecutable(.{
        .name = "editor-microbench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/bench_main.zig"),
            .target = target,
            .optimize = .ReleaseFast,
            .link_libc = true,
            .imports = &.{
                .{ .name = "skia", .module = skia_mod },
                .{ .name = "ui", .module = ui_mod },
                .{ .name = "platform", .module = platform_mod },
            },
        }),
    });
    if (is_macos) {
        microbench_exe.root_module.addRPath(.{ .cwd_relative = "@executable_path/../lib" });
    } else if (is_linux) {
        microbench_exe.root_module.addRPath(.{ .cwd_relative = "$ORIGIN/../lib" });
    }
    const install_microbench = b.addInstallArtifact(microbench_exe, .{});
    b.getInstallStep().dependOn(&install_microbench.step);

    const microbench_step = b.step("microbench", "Run headless subsystem microbenchmarks (TextCache, Damage, CodeEditor, Layout, I/O)");
    const run_microbench_cmd = b.addRunArtifact(microbench_exe);
    run_microbench_cmd.step.dependOn(&install_dylib.step);
    run_microbench_cmd.step.dependOn(&install_microbench.step);
    run_microbench_cmd.addPassthruArgs();
    microbench_step.dependOn(&run_microbench_cmd.step);
    const bench_step = b.step("bench", "Run scriptable performance benchmark (typing scenario, 300 frames)");
    const run_bench_cmd = b.addRunArtifact(window_exe);
    run_bench_cmd.step.dependOn(&install_dylib.step);
    run_bench_cmd.step.dependOn(&install_window_exe.step);
    run_bench_cmd.step.dependOn(&install_editor_app.step);
    run_bench_cmd.addArgs(&.{
        "--dylib", "zig-out/lib/libeditor_app.dylib",
        "--bench",
        "--frames", "300",
        "--scenario", "typing",
    });
    run_bench_cmd.addPassthruArgs();
    bench_step.dependOn(&run_bench_cmd.step);

    // 7. Apple Instruments Profiler (`zig build xctrace`)
    const xctrace_step = b.step("xctrace", "Record an Apple Instruments Time Profiler trace (zig-out/editor_profile.trace)");
    const run_xctrace_cmd = b.addSystemCommand(&.{
        "sh",
        "-c",
        "rm -rf zig-out/editor_profile.trace && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun xctrace record --template 'Time Profiler' --output zig-out/editor_profile.trace --launch -- ./zig-out/bin/lightning --dylib zig-out/lib/libeditor_app.dylib --bench --frames 300 --scenario scroll",
    });
    run_xctrace_cmd.step.dependOn(&install_dylib.step);
    run_xctrace_cmd.step.dependOn(&install_window_exe.step);
    run_xctrace_cmd.step.dependOn(&install_editor_app.step);
    xctrace_step.dependOn(&run_xctrace_cmd.step);

    // ========================================================================
    // 8. macOS Packaging (`zig build package` & `zig build bundle`)
    // ========================================================================
    const package_step = b.step("package", "Assemble self-contained macOS Lightning.app bundle, Lightning.dmg, and Lightning-macos.zip");
    const package_cmd = b.addSystemCommand(&.{
        "python3",
        "scripts/package_macos.py",
    });
    package_cmd.step.dependOn(&install_dylib.step);
    package_cmd.step.dependOn(&install_window_exe.step);
    package_cmd.step.dependOn(&install_editor_app.step);
    package_cmd.step.dependOn(plugins_step);
    package_step.dependOn(&package_cmd.step);

    const bundle_step = b.step("bundle", "Alias for `package` (assemble macOS Lightning.app)");
    bundle_step.dependOn(&package_cmd.step);

    // ========================================================================
    // 9. Cross-Compilation Steps (`zig build windows` & `zig build linux`)
    // ========================================================================
    const windows_step = b.step("windows", "Cross-compile self-contained Windows x86_64 distribution into zig-out/windows/");
    const windows_cmd = b.addSystemCommand(&.{
        b.graph.zig_exe,
        "build",
        "-Dtarget=x86_64-windows-gnu",
        "--prefix",
        "zig-out/windows",
    });
    windows_step.dependOn(&windows_cmd.step);

    const linux_step = b.step("linux", "Cross-compile self-contained Linux x86_64 distribution into zig-out/linux/");
    const linux_cmd = b.addSystemCommand(&.{
        b.graph.zig_exe,
        "build",
        "-Dtarget=x86_64-linux-gnu",
        "--prefix",
        "zig-out/linux",
    });
    linux_step.dependOn(&linux_cmd.step);

    const linux_armv7_step = b.step("linux-armv7", "Cross-compile self-contained Linux ARMv7 hardfloat distribution into zig-out/linux-armv7/");
    const linux_armv7_cmd = b.addSystemCommand(&.{
        b.graph.zig_exe,
        "build",
        "-Dtarget=arm-linux-gnueabihf",
        "-Dcpu=generic+v7a",
        "--prefix",
        "zig-out/linux-armv7",
    });
    linux_armv7_step.dependOn(&linux_armv7_cmd.step);
}

fn addHotReloadPlugin(
    b: *std.Build,
    name: []const u8,
    root_src: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    skia_mod: *std.Build.Module,
    ui_mod: *std.Build.Module,
    platform_mod: *std.Build.Module,
) *std.Build.Step.Compile {
    const lib = b.addLibrary(.{
        .name = name,
        .linkage = .dynamic,
        .root_module = b.createModule(.{
            .root_source_file = b.path(root_src),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "skia", .module = skia_mod },
                .{ .name = "ui", .module = ui_mod },
                .{ .name = "platform", .module = platform_mod },
            },
        }),
    });
    if (target.result.os.tag == .macos) {
        lib.root_module.addRPath(.{ .cwd_relative = "@loader_path" });
    } else if (target.result.os.tag == .linux) {
        lib.root_module.addRPath(.{ .cwd_relative = "$ORIGIN" });
    } else if (target.result.os.tag == .windows) {
        lib.root_module.linkSystemLibrary("ws2_32", .{});
    }
    return lib;
}

fn addEditorExtensionPlugin(
    b: *std.Build,
    name: []const u8,
    root_src: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    plugin_sdk_mod: *std.Build.Module,
) *std.Build.Step.Compile {
    return b.addLibrary(.{
        .name = name,
        .linkage = .dynamic,
        .root_module = b.createModule(.{
            .root_source_file = b.path(root_src),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "plugin_sdk", .module = plugin_sdk_mod },
            },
        }),
    });
}
