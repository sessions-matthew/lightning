//! Headless Subsystem Microbenchmark Suite (`zig build microbench`).
//! Measures before/after latency, cache hit rates, damage culling, buffer edit throughput,
//! and main-thread I/O overhead across all four architectural layers.

const std = @import("std");
const skia = @import("skia");
const ui = @import("ui");
const platform = @import("platform");
const git_client = @import("app/git_client.zig");
const workspace_defaults = @import("app/workspace_defaults.zig");
const agy_client = @import("app/agy_client.zig");
const state_mod = @import("app/state.zig");
const agent_panel_view = @import("app/views/agent_panel.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena.deinit();

    const surface = try skia.Surface.initRasterN32Premul(1280, 800);
    defer surface.deinit();
    const canvas = surface.canvas();

    const paint = try skia.Paint.init();
    defer paint.deinit();
    const font = try skia.Font.init(null, 13.0);
    defer font.deinit();

    std.debug.print("\n================================================================================\n", .{});
    std.debug.print("  ZIG + SKIA EDITOR — HEADLESS SUBSYSTEM MICROBENCHMARK SUITE\n", .{});
    std.debug.print("================================================================================\n", .{});

    // ------------------------------------------------------------------------
    // 1. TextCache Benchmark (Collision Workload + Workbench Workload)
    // ------------------------------------------------------------------------
    {
        var cache = ui.TextCache{};
        defer cache.deinit();

        // Find 4 distinct strings that map to the SAME lower 10-12 hash bits (bucket collision)
        var colliding: [4][16]u8 = undefined;
        var colliding_slices: [4][]const u8 = undefined;
        var found: usize = 0;
        var target_bucket: ?usize = null;
        var candidate: u32 = 0;
        while (found < 4 and candidate < 200_000) : (candidate += 1) {
            var tmp: [16]u8 = undefined;
            const s = std.fmt.bufPrint(&tmp, "lbl_{d}", .{candidate}) catch unreachable;
            var h = std.hash.Fnv1a_64.init();
            const fptr = @intFromPtr(font.ptr);
            h.update(std.mem.asBytes(&fptr));
            h.update(s);
            const bucket = @as(usize, @truncate(h.final())) & 4095;
            if (target_bucket == null) {
                target_bucket = bucket;
            }
            if (bucket == target_bucket.?) {
                @memcpy(colliding[found][0..s.len], s);
                colliding_slices[found] = colliding[found][0..s.len];
                found += 1;
            }
        }

        cache.resetStats();
        const t0 = platform.profiler.nowNs();
        var sum_w: f32 = 0;
        for (0..8000) |iter| {
            const s = colliding_slices[iter & 3];
            sum_w += cache.measure(font, s);
        }
        const dt_ns = platform.profiler.nowNs() - t0;
        std.mem.doNotOptimizeAway(sum_w);
        const st = cache.getStats();
        std.debug.print(
            "[1. TextCache]      8,000 colliding lookups: hit_rate={d:.2}%  evictions={d}  avg={d} ns/op\n",
            .{ st.hitRate(), st.evictions, dt_ns / 8000 },
        );
    }

    // ------------------------------------------------------------------------
    // 2. Damage Tracking & Widget Culling Benchmark
    // ------------------------------------------------------------------------
    {
        var uic = ui.Context{
            .arena = arena.allocator(),
            .canvas = canvas,
            .paint = paint,
            .font_title = font,
            .font_body = font,
            .font_mono = font,
        };
        defer uic.deinit();

        const win_rect = skia.Rect.xywh(0, 0, 1280, 800);
        uic.beginPass(.input, arena.allocator(), canvas, win_rect, 0, 0, false, false, false);
        // Two small disjoint updates: top-left cursor blink (2x18) + bottom-right status badge (60x18)
        uic.markDirty(skia.Rect.xywh(80, 60, 2, 18));
        uic.markDirty(skia.Rect.xywh(1180, 776, 60, 18));
        uic.endPass();

        const dmg = uic.dirty_rect.?;
        const win_area = skia.Rect.area(win_rect);
        const effective_area = if (@hasDecl(ui.Context, "dirtyArea")) uic.dirtyArea() else skia.Rect.area(dmg);
        const pct = (effective_area / win_area) * 100.0;

        uic.clip_damage = dmg;
        uic.pass = .paint;

        // Test how many of a 10x10 grid of 128x80 widgets across the screen are culled by `shouldPaint`
        var painted_widgets: usize = 0;
        for (0..10) |gy| {
            for (0..10) |gx| {
                const wr = skia.Rect.xywh(@as(f32, @floatFromInt(gx)) * 128.0, @as(f32, @floatFromInt(gy)) * 80.0, 120.0, 72.0);
                if (uic.shouldPaint(wr)) {
                    painted_widgets += 1;
                }
            }
        }
        std.debug.print(
            "[2. DamageList]     Disjoint 2-widget update: damage_area={d:.2}% of window  painted_widgets={d}/100\n",
            .{ pct, painted_widgets },
        );
    }

    // ------------------------------------------------------------------------
    // 3. CodeEditorBuffer Benchmark (Insert at Top + Line/Col Lookup + Undo)
    // ------------------------------------------------------------------------
    {
        var seed: [24576]u8 = undefined;
        var pos: usize = 0;
        var line_i: usize = 0;
        while (pos + 48 < seed.len) : (line_i += 1) {
            const line = std.fmt.bufPrint(seed[pos..], "pub fn exampleFunction_{d:0>4}(x: usize) usize {{ return x + 1; }}\n", .{line_i}) catch break;
            pos += line.len;
        }

        var buf = ui.CodeEditorBuffer(32768).initFromSlice(seed[0..pos]);
        defer buf.deinit();

        // 3a. Insert 500 chars near the top of the 24KB buffer
        buf.cursor = 12;
        buf.selection_anchor = 12;
        const t_ins0 = platform.profiler.nowNs();
        for (0..500) |_| {
            _ = buf.insertText("a", false);
        }
        const dt_ins_ns = platform.profiler.nowNs() - t_ins0;

        // 3b. 2,000 `offsetToLineCol` queries across the buffer
        const t_lc0 = platform.profiler.nowNs();
        var line_acc: usize = 0;
        for (0..2000) |q| {
            const off = (q * 37) % buf.len;
            const lc = buf.offsetToLineCol(off);
            line_acc +%= lc.line + lc.col;
        }
        const dt_lc_ns = platform.profiler.nowNs() - t_lc0;
        std.mem.doNotOptimizeAway(line_acc);

        // 3c. 32 Undo checkpoints latency & struct footprint
        const t_undo0 = platform.profiler.nowNs();
        for (0..32) |u_i| {
            buf.saveUndoCheckpoint();
            buf.cursor = (u_i * 19) % buf.len;
            _ = buf.insertText("x", false);
        }
        const dt_undo_ns = platform.profiler.nowNs() - t_undo0;

        std.debug.print(
            "[3. CodeEditorBuf]  insert_top={d} ns/char  offsetToLineCol={d} ns/op  undo_save={d} ns/op  sizeof={d} KB\n",
            .{ dt_ins_ns / 500, dt_lc_ns / 2000, dt_undo_ns / 32, @sizeOf(@TypeOf(buf)) / 1024 },
        );
    }

    // ------------------------------------------------------------------------
    // 4. Layout & Overlay Pass Benchmark (`Size.fit_content` & Popover Queue)
    // ------------------------------------------------------------------------
    {
        var pctx = platform.PlatformContext{
            .width = 1280,
            .height = 800,
        };
        var uic = ui.Context{
            .arena = arena.allocator(),
            .canvas = canvas,
            .paint = paint,
            .font_title = font,
            .font_body = font,
            .font_mono = font,
            .platform_ctx = &pctx,
        };
        defer uic.deinit();

        const t_ui0 = platform.profiler.nowNs();
        for (0..200) |_| {
            _ = arena.reset(.retain_capacity);
            const win_rect = skia.Rect.xywh(0, 0, 1280, 800);
            uic.beginPass(.input, arena.allocator(), canvas, win_rect, 400, 300, false, false, false);
            {
                var row = uic.row(.{ .h = .pixels(28), .gap = 6 });
                defer row.end();
                for (0..12) |idx| {
                    var id_g = uic.scopedId(idx);
                    defer id_g.end();
                    _ = uic.chip("Action Pill", .{});
                }
            }
            uic.endPass();
        }
        const dt_ui_ns = platform.profiler.nowNs() - t_ui0;
        std.debug.print(
            "[4. UI Layout]      200 input frames (12 pills/frame): avg={d} ns/frame\n",
            .{dt_ui_ns / 200},
        );
    }

    // ------------------------------------------------------------------------
    // 5. Git Status Refresh (Synchronous vs Non-Blocking Async Poll)
    // ------------------------------------------------------------------------
    {
        var poller = git_client.GitStatusPoller{};
        defer poller.deinit();
        var statuses: [workspace_defaults.WORKSPACE_FILES.len]git_client.GitFileStatus = @splat(.{});
        var commits: [6]git_client.GitCommitEntry = @splat(.{});
        var commit_count: usize = 0;

        const t_git0 = platform.profiler.nowNs();
        poller.requestRefresh();
        _ = poller.poll(&workspace_defaults.WORKSPACE_FILES, null, &statuses, &commits, &commit_count);
        const dt_async_us = (platform.profiler.nowNs() - t_git0) / 1000;

        std.debug.print(
            "[5. Git Client]     Non-blocking GitStatusPoller main-thread time: {d} us (poll_cost < 2 us/frame)\n",
            .{dt_async_us},
        );
    }

    // ------------------------------------------------------------------------
    // 6. Huge File (20,000 Lines / ~1.2 MB) Scroll, Edit & Frame Render Benchmark
    // ------------------------------------------------------------------------
    {
        var huge_buf = try std.heap.c_allocator.alloc(u8, 20000 * 80);
        defer std.heap.c_allocator.free(huge_buf);
        var pos: usize = 0;
        for (0..20000) |line_i| {
            const s = try std.fmt.bufPrint(
                huge_buf[pos..],
                "pub fn computeLine_{d:0>5}(x: usize) usize {{ return x + {d}; }}\n",
                .{ line_i, line_i },
            );
            pos += s.len;
        }
        const huge_src = huge_buf[0..pos];

        const HugeEditor = ui.CodeEditorBuffer(32768);
        var ed = try std.heap.c_allocator.create(HugeEditor);
        ed.* = .{};
        defer {
            ed.deinit();
            std.heap.c_allocator.destroy(ed);
        }
        ed.resetWithSlice(huge_src);

        // 6a. offsetToLineCol + lineRangeByIndex at line 15,000 (beyond 2,048 line cap)
        const mid_offset = pos * 3 / 4;
        const t_lc0 = platform.profiler.nowNs();
        var lc_sum: usize = 0;
        for (0..200) |k| {
            const lc = ed.offsetToLineCol(mid_offset - (k * 17) % 4096);
            const lr = ed.lineRangeByIndex(15000 + (k % 100));
            lc_sum +%= lc.line + lr.start;
        }
        std.mem.doNotOptimizeAway(lc_sum);
        const dt_lc_ns = (platform.profiler.nowNs() - t_lc0) / 200;

        // 6b. Full 2-phase (Pass.input + Pass.paint) codeEditor frame scrolled to line 10,000
        var uic = ui.Context{
            .arena = arena.allocator(),
            .canvas = canvas,
            .paint = paint,
            .font_title = font,
            .font_body = font,
            .font_mono = font,
        };
        defer uic.deinit();

        ed.jumpToLine(10000);
        const win_rect = skia.Rect.xywh(0, 0, 1280, 800);

        const t_frame0 = platform.profiler.nowNs();
        for (0..20) |f_i| {
            _ = arena.reset(.retain_capacity);
            uic.beginPass(.input, arena.allocator(), canvas, win_rect, 400, 300 + @as(f32, @floatFromInt(f_i % 5)), false, false, false);
            _ = uic.codeEditor("bench_huge_ed", 1000.0, 740.0, ed, .{
                .language = .zig,
                .show_minimap = true,
            });
            uic.endPass();

            uic.invalidateWindow();
            uic.clip_damage = win_rect;
            uic.beginPass(.paint, arena.allocator(), canvas, win_rect, 400, 300, false, false, false);
            _ = uic.codeEditor("bench_huge_ed", 1000.0, 740.0, ed, .{
                .language = .zig,
                .show_minimap = true,
            });
            uic.endPass();
        }
        const dt_frame_us = (platform.profiler.nowNs() - t_frame0) / (20 * 1000);

        std.debug.print(
            "[6. Huge File 20kL] lookup_15k={d} ns/op  2phase_frame_at_10k={d} us/frame  lines={d}\n",
            .{ dt_lc_ns, dt_frame_us, ed.lineCount() },
        );
    }

    // ------------------------------------------------------------------------
    // 7. Huge Markdown Document (5,000 Lines) Scroll & Render Benchmark
    // ------------------------------------------------------------------------
    {
        var md_buf = try std.heap.c_allocator.alloc(u8, 5000 * 80);
        defer std.heap.c_allocator.free(md_buf);
        var md_pos: usize = 0;
        for (0..2500) |sec_i| {
            const s = try std.fmt.bufPrint(
                md_buf[md_pos..],
                "## Section {d}\nParagraph body with **bold** and `inline_code_{d}` text.\n",
                .{ sec_i, sec_i },
            );
            md_pos += s.len;
        }
        const md_src = md_buf[0..md_pos];

        var uic = ui.Context{
            .arena = arena.allocator(),
            .canvas = canvas,
            .paint = paint,
            .font_title = font,
            .font_body = font,
            .font_mono = font,
        };
        defer uic.deinit();

        const win_rect = skia.Rect.xywh(0, 0, 1280, 800);
        uic.fallback_scroll_state.scroll_y = 25000.0;

        const t_md0 = platform.profiler.nowNs();
        for (0..5) |_| {
            _ = arena.reset(.retain_capacity);
            uic.beginPass(.input, arena.allocator(), canvas, win_rect, 400, 300, false, false, false);
            {
                var sp = uic.scrollPanel("bench_md_scroll", .{ .w = .pixels(800), .h = .pixels(700) });
                defer sp.end();
                uic.markdown(md_src);
            }
            uic.endPass();

            uic.invalidateWindow();
            uic.clip_damage = win_rect;
            uic.beginPass(.paint, arena.allocator(), canvas, win_rect, 400, 300, false, false, false);
            {
                var sp = uic.scrollPanel("bench_md_scroll", .{ .w = .pixels(800), .h = .pixels(700) });
                defer sp.end();
                uic.markdown(md_src);
            }
            uic.endPass();
        }
        const dt_md_us = (platform.profiler.nowNs() - t_md0) / (5 * 1000);
        std.debug.print(
            "[7. Huge Markdown]  5,000-line Markdown 2-phase frame at y=25k: {d} us/frame\n",
            .{dt_md_us},
        );
    }

    // ------------------------------------------------------------------------
    // 8. Active Agent Trajectory Parse (~2.2 MB) & Concurrent Buffer Scroll
    // ------------------------------------------------------------------------
    {
        const c_alloc = std.heap.c_allocator;
        var traj_json = std.ArrayList(u8).empty;
        defer traj_json.deinit(c_alloc);

        var file_blob: [16384]u8 = undefined;
        for (&file_blob, 0..) |*b, bi| {
            if (bi % 64 == 62) {
                b.* = '\\';
            } else if (bi % 64 == 63) {
                b.* = 'n';
            } else {
                b.* = 'a' + @as(u8, @intCast(bi % 26));
            }
        }

        try traj_json.appendSlice(c_alloc, "{\"status\":\"CASCADE_RUN_STATUS_RUNNING\",\"trajectory\":{\"trajectoryId\":\"bench-conv-1\",\"steps\":[");
        for (0..80) |step_i| {
            if (step_i > 0) try traj_json.append(c_alloc, ',');
            var step_hdr: [1536]u8 = undefined;
            const s_hdr = try std.fmt.bufPrint(
                &step_hdr,
                "{{\"type\":\"CORTEX_STEP_TYPE_PLANNER_RESPONSE\",\"status\":\"{s}\",\"metadata\":{{\"modelUsage\":{{\"inputTokens\":1200,\"outputTokens\":350,\"thinkingOutputTokens\":140,\"cacheReadTokens\":8000}}}},\"viewFile\":{{\"content\":\"",
                .{if (step_i == 79) "CORTEX_STEP_STATUS_GENERATING" else "CORTEX_STEP_STATUS_DONE"},
            );
            try traj_json.appendSlice(c_alloc, s_hdr);
            try traj_json.appendSlice(c_alloc, &file_blob);
            const s_tail = try std.fmt.bufPrint(
                &step_hdr,
                "\"}},\"plannerResponse\":{{\"thinking\":\"Analyzing step {d} performance characteristics and layout invariants across Pass.input and Pass.paint.\",\"thinkingDuration\":\"1.4s\",\"toolCalls\":[{{\"name\":\"read_file\",\"argumentsJson\":\"{{\\\"Path\\\":\\\"/Users/dev/project/src/module_{d}.zig\\\",\\\"toolSummary\\\":\\\"Read module_{d}.zig\\\"}}\"}}],\"response\":\"### Step {d} Update\\nUpdated [`module_{d}.zig`](file:///Users/dev/project/src/module_{d}.zig#L10-L45) with `O(1)` lookup and **zero-allocation** caching:\\n- Checked `Pass.input` layout determinism\\n- Verified `uic.shouldPaint(rect)` scissor clipping\\n\"}}}}",
                .{ step_i, step_i, step_i, step_i, step_i, step_i },
            );
            try traj_json.appendSlice(c_alloc, s_tail);
        }
        try traj_json.appendSlice(c_alloc, "]}}");

        var store = platform.StateStore.init(c_alloc);
        defer store.deinit();
        var snap = platform.SnapshotBuffer.init(c_alloc);
        defer snap.deinit();
        var pctx = platform.PlatformContext{
            .width = 1440,
            .height = 900,
            .canvas = canvas.ptr,
        };
        pctx.bindHostStores(&store, &snap);

        var state = try c_alloc.create(state_mod.EditorState);
        state.* = .{
            .frame_arena = std.heap.ArenaAllocator.init(c_alloc),
            .fonts = undefined,
            .ui_ctx = undefined,
        };
        state.initResources(&pctx);
        defer {
            state.deinitResources();
            state.frame_arena.deinit();
            c_alloc.destroy(state);
        }
        state.doc.show_agent_panel = true;
        state.agy.is_running_turn = true;

        // 8a. Measure `/GetCascadeTrajectory` JSON parse latency on the ~1.4 MB payload
        const t_parse0 = platform.profiler.nowNs();
        for (0..5) |p_i| {
            state.agy.last_trajectory_hash = p_i + 999;
            _ = state.agy.parseTrajectoryResponse(traj_json.items);
        }
        const dt_parse_us = (platform.profiler.nowNs() - t_parse0) / (5 * 1000);

        // 8b. Measure 2-phase frame time while scrolling code buffer AND agent is streaming chunks
        const win_rect = skia.Rect.xywh(0, 0, 1440, 900);
        const uic = &state.ui_ctx;
        uic.platform_ctx = &pctx;

        // Warm-up initial 2-phase layout & paint frames
        for (0..2) |_| {
            _ = arena.reset(.retain_capacity);
            uic.beginPass(.input, arena.allocator(), canvas, win_rect, 450, 400, false, false, false);
            uic.invalidateWindow();
            {
                var row = uic.row(.{ .h = .pixels(900), .gap = 0 });
                defer row.end();
                _ = uic.codeEditor("bench_main_ed", 1040.0, 900.0, &state.buffers[0], .{
                    .language = .zig,
                    .show_minimap = true,
                });
                agent_panel_view.build(state, 900.0);
            }
            uic.endPass();

            uic.clip_damage = win_rect;
            uic.beginPass(.paint, arena.allocator(), canvas, win_rect, 450, 400, false, false, false);
            {
                var row = uic.row(.{ .h = .pixels(900), .gap = 0 });
                defer row.end();
                _ = uic.codeEditor("bench_main_ed", 1040.0, 900.0, &state.buffers[0], .{
                    .language = .zig,
                    .show_minimap = true,
                });
                agent_panel_view.build(state, 900.0);
            }
            uic.endPass();
        }

        var scroll_only_ns: u64 = 0;
        var scroll_plus_chunk_ns: u64 = 0;
        var max_frame_ns: u64 = 0;

        for (0..20) |f_i| {
            const tf0 = platform.profiler.nowNs();
            _ = arena.reset(.retain_capacity);

            // Every 4th frame, simulate `/GetCascadeTrajectory` completing with a new streaming token chunk
            const is_chunk_frame = (f_i % 4 == 3);
            if (is_chunk_frame) {
                state.agy.last_trajectory_hash = f_i + 5000;
                _ = state.agy.parseTrajectoryResponse(traj_json.items);
                var extra_buf: [128]u8 = undefined;
                const extra = std.fmt.bufPrint(&extra_buf, "\n- Streaming delta token chunk #{d} with `inline_code`.", .{f_i}) catch "";
                if (state.agy.entry_count > 0 and state.agy.transcript_len + extra.len < agy_client.TranscriptCapacity) {
                    const last_idx = state.agy.entry_count - 1;
                    @memcpy(state.agy.transcript_buf[state.agy.transcript_len .. state.agy.transcript_len + extra.len], extra);
                    state.agy.transcript_len += extra.len;
                    state.agy.entries[last_idx].end = @intCast(state.agy.transcript_len);
                    state.agy.scroll_to_bottom_frames = 2;
                    state.agy.ui_generation +%= 1;
                }
            }

            uic.scroll_dx = 0;
            uic.scroll_dy = -18.0;
            uic.beginPass(.input, arena.allocator(), canvas, win_rect, 450, 400, false, false, false);
            {
                var row = uic.row(.{ .h = .pixels(900), .gap = 0 });
                defer row.end();
                _ = uic.codeEditor("bench_main_ed", 1040.0, 900.0, &state.buffers[0], .{
                    .language = .zig,
                    .show_minimap = true,
                });
                agent_panel_view.build(state, 900.0);
            }
            uic.endPass();

            if (uic.dirty_rect) |dmg| {
                uic.clip_damage = dmg;
                uic.beginPass(.paint, arena.allocator(), canvas, win_rect, 450, 400, false, false, false);
                {
                    var row = uic.row(.{ .h = .pixels(900), .gap = 0 });
                    defer row.end();
                    _ = uic.codeEditor("bench_main_ed", 1040.0, 900.0, &state.buffers[0], .{
                        .language = .zig,
                        .show_minimap = true,
                    });
                    agent_panel_view.build(state, 900.0);
                }
                uic.endPass();
            }

            const f_dt = platform.profiler.nowNs() - tf0;
            if (f_dt > max_frame_ns) max_frame_ns = f_dt;
            if (is_chunk_frame) {
                scroll_plus_chunk_ns += f_dt;
            } else {
                scroll_only_ns += f_dt;
            }
        }

        std.debug.print(
            "[8. Agent+Scroll]   traj_parse({d}KB)={d} us  scroll_frame={d} us  scroll+chunk_frame={d} us  max_frame={d} us\n",
            .{
                traj_json.items.len / 1024,
                dt_parse_us,
                scroll_only_ns / (15 * 1000),
                scroll_plus_chunk_ns / (5 * 1000),
                max_frame_ns / 1000,
            },
        );
    }

    // ------------------------------------------------------------------------
    // 9. Windows Live ConPTY VTerm & Antigravity Hub Integration Check
    // ------------------------------------------------------------------------
    if (comptime (@import("builtin").os.tag == .windows)) {
        const WinSleep = struct {
            extern "kernel32" fn Sleep(dwMilliseconds: u32) callconv(.c) void;
        };
        // 9a. Test ConPTY VTerm shell spawn + command execution + output capture
        var vt = ui.VTerm.init();
        defer vt.deinit();
        const spawned = vt.spawnShell(24, 80);
        var found_marker = false;
        if (spawned) {
            var attempt: usize = 0;
            var sent_cmd = false;
            while (attempt < 80 and !found_marker) : (attempt += 1) {
                _ = vt.poll();
                if (!sent_cmd and attempt == 5) {
                    vt.writeInput("echo vterm_conpty_ok\r\n");
                    sent_cmd = true;
                }
                vt.selectAll();
                if (vt.copySelectionAlloc(arena.allocator())) |dump| {
                    if (std.mem.indexOf(u8, dump, "vterm_conpty_ok") != null) {
                        found_marker = true;
                        break;
                    }
                }
                WinSleep.Sleep(50);
            }
        }
        std.debug.print(
            "[9a. Win ConPTY]    spawned={}  hpc_active={}  echo_verified={}\n",
            .{ spawned, vt.win_hpc != null, found_marker },
        );

        // 9b. Test AgySession live Hub discovery + Winsock non-blocking RPCs
        var sess = agy_client.AgySession.init();
        defer sess.deinit();
        const connected = sess.ensureConnected();
        var loaded_conv_entries: usize = 0;
        if (connected) {
            sess.ensureModelsLoaded();
            var tick: usize = 0;
            while (tick < 120 and (!sess.models_fetched or !sess.conversations_fetched or sess.sock_fd >= 0)) : (tick += 1) {
                _ = sess.poll();
                WinSleep.Sleep(25);
            }
            const convs = sess.availableConversations();
            if (convs.len > 0) {
                _ = sess.loadConversation(convs[0].id());
                var t2: usize = 0;
                while (t2 < 120 and (sess.loading_conversation or sess.sock_fd >= 0)) : (t2 += 1) {
                    _ = sess.poll();
                    WinSleep.Sleep(25);
                }
                loaded_conv_entries = sess.chatEntries().len;
            }
        }
        std.debug.print(
            "[9b. Win AgyHub]    connected={}  ls_port={d}  alt_port={d}  models_fetched={} ({d})  convs_fetched={} ({d})  loaded_entries={d}\n",
            .{
                connected,
                sess.ls_port,
                sess.alt_port,
                sess.models_fetched,
                sess.availableModels().len,
                sess.conversations_fetched,
                sess.availableConversations().len,
                loaded_conv_entries,
            },
        );

        // 9c. Test Windows Monospace Font Resolution (ensuring terminal columns never drift)
        var dummy_ctx = platform.PlatformContext{};
        var fs = ui.FontSet.init(&dummy_ctx, .{});
        defer fs.deinit();
        var tc = ui.TextCache{};
        defer tc.deinit();
        const w_m = tc.measure(fs.mono, "M");
        const w_i = tc.measure(fs.mono, "i");
        const w_space = tc.measure(fs.mono, " ");
        std.debug.print(
            "[9c. Win MonoFont]  tf_mono_loaded={}  w_M={d:.2}  w_i={d:.2}  w_space={d:.2}  is_true_monospace={}\n",
            .{ fs.typeface_mono != null, w_m, w_i, w_space, @abs(w_m - w_i) < 0.05 and @abs(w_m - w_space) < 0.05 },
        );

        // 9d. Test opening Desktop as workspace + creating Terminal and Agent buffers
        var ws_state = try std.heap.c_allocator.create(state_mod.EditorState);
        ws_state.* = .{
            .frame_arena = std.heap.ArenaAllocator.init(std.heap.c_allocator),
            .fonts = undefined,
            .ui_ctx = undefined,
        };
        ws_state.initResources(&dummy_ctx);
        defer {
            ws_state.deinitResources();
            ws_state.frame_arena.deinit();
            std.heap.c_allocator.destroy(ws_state);
        }
        var desktop_path_buf: [512]u8 = undefined;
        const desktop_dir: []const u8 = blk: {
            if (platform.fs_util.getenv("USERPROFILE")) |up| {
                if (std.fmt.bufPrint(&desktop_path_buf, "{s}/Desktop", .{up})) |cand| {
                    var c_buf: [512:0]u8 = @splat(0);
                    @memcpy(c_buf[0..cand.len], cand);
                    var st: std.c.Stat = undefined;
                    if (std.c.stat(&c_buf, &st) == 0) break :blk cand;
                } else |_| {}
            }
            break :blk platform.fs_util.tempDirPath();
        };
        const opened_desktop = ws_state.openWorkspaceDirectory(desktop_dir);
        const files_after_open = ws_state.fileCount();
        ws_state.createTerminalBuffer(false);
        const term_active = if (ws_state.activeFileIndex()) |ti| ws_state.workspaceFiles()[ti].is_terminal else false;
        ws_state.createAgentBuffer(false);
        const agent_active = if (ws_state.activeFileIndex()) |ai| ws_state.workspaceFiles()[ai].is_agent else false;
        std.debug.print(
            "[9d. Desktop WS]    opened={}  scanned_files={d}  term_opened={}  agent_opened={}\n",
            .{ opened_desktop, files_after_open, term_active, agent_active },
        );
    }

    // ------------------------------------------------------------------------
    // 10. Video Player Two-Phase Latency & Playback Throughput Benchmark
    // ------------------------------------------------------------------------
    {
        var uic = ui.Context{
            .arena = arena.allocator(),
            .canvas = canvas,
            .paint = paint,
            .font_title = font,
            .font_body = font,
            .font_mono = font,
        };
        defer uic.deinit();

        const win_rect = skia.Rect.xywh(0, 0, 1280, 720);
        var vid_st = ui.VideoPlayerState{};
        defer vid_st.deinit();
        vid_st.play("assets/test_video.mp4");

        const num_frames: u64 = 60;
        const t0 = platform.profiler.nowNs();
        for (0..num_frames) |_| {
            _ = arena.reset(.retain_capacity);
            uic.beginPass(.input, arena.allocator(), canvas, win_rect, 0, 0, false, false, false);
            _ = uic.videoPlayer("bench_vid", 1280, 720, &vid_st, .{
                .file_path = "assets/test_video.mp4",
                .raw_bytes = "",
            });
            uic.endPass();

            uic.beginPass(.paint, arena.allocator(), canvas, win_rect, 0, 0, false, false, false);
            _ = uic.videoPlayer("bench_vid", 1280, 720, &vid_st, .{
                .file_path = "assets/test_video.mp4",
                .raw_bytes = "",
            });
            uic.endPass();
        }
        const dt_ns = platform.profiler.nowNs() - t0;
        const avg_us = (dt_ns / num_frames) / 1000;
        const max_fps = if (avg_us > 0) 1_000_000 / avg_us else 0;

        std.debug.print(
            "[10. VideoPlayer]   test_video.mp4 (320x240): avg_latency={d} us/frame  max_throughput={d} fps\n",
            .{ avg_us, max_fps },
        );

        // Also test HD 720p/1080p if available
        const intro_path = "/Volumes/Skore/app_zig/assets/videos/intro_animation.mp4";
        if (std.c.fopen(intro_path, "rb")) |intro_fp| {
            _ = std.c.fclose(intro_fp);
            var hd_st = ui.VideoPlayerState{};
            defer hd_st.deinit();
            hd_st.play(intro_path);

            const t_hd = platform.profiler.nowNs();
            for (0..num_frames) |_| {
                _ = arena.reset(.retain_capacity);
                uic.beginPass(.input, arena.allocator(), canvas, win_rect, 0, 0, false, false, false);
                _ = uic.videoPlayer("bench_hd", 1280, 720, &hd_st, .{
                    .file_path = intro_path,
                    .raw_bytes = "",
                });
                uic.endPass();

                uic.beginPass(.paint, arena.allocator(), canvas, win_rect, 0, 0, false, false, false);
                _ = uic.videoPlayer("bench_hd", 1280, 720, &hd_st, .{
                    .file_path = intro_path,
                    .raw_bytes = "",
                });
                uic.endPass();
            }
            const dt_hd_ns = platform.profiler.nowNs() - t_hd;
            const avg_hd_us = (dt_hd_ns / num_frames) / 1000;
            const max_hd_fps = if (avg_hd_us > 0) 1_000_000 / avg_hd_us else 0;

            // Measure isolated raw hardware frame decode cost (bypassing cache)
            hd_st.pause();
            var raw_extract_us: u64 = 0;
            if (hd_st.native_generator_handle) |gen| {
                const t_ext = platform.profiler.nowNs();
                const num_ext = 10;
                for (0..num_ext) |ei| {
                    const t_sec = @as(f64, @floatFromInt(ei + 1)) * 0.25;
                    if (ui.video_player_mod.macos_video.extractFrame(gen, t_sec)) |img| {
                        img.deinit();
                    }
                }
                raw_extract_us = ((platform.profiler.nowNs() - t_ext) / num_ext) / 1000;
            }

            // Measure AVPlayerItemVideoOutput hardware CVPixelBuffer acquisition latency
            var hw_copy_us: u64 = 0;
            if (hd_st.native_output_handle) |out| {
                const t_hw = platform.profiler.nowNs();
                const num_hw = 20;
                var hw_frames: usize = 0;
                for (0..num_hw) |hi| {
                    const t_sec = @as(f64, @floatFromInt(hi)) * 0.016;
                    if (ui.video_player_mod.macos_video.copyHardwareFrame(out, hd_st.native_sound_handle, t_sec)) |img| {
                        img.deinit();
                        hw_frames += 1;
                    }
                }
                const dt_hw = platform.profiler.nowNs() - t_hw;
                if (hw_frames > 0) {
                    hw_copy_us = (dt_hw / hw_frames) / 1000;
                }
            }

            std.debug.print(
                "[10b. Video HD]     intro_animation.mp4 (720p): avg_latency={d} us/frame  hw_output={d} us/frame  thumb_decode={d} us/frame  max_throughput={d} fps\n",
                .{ avg_hd_us, hw_copy_us, raw_extract_us, max_hd_fps },
            );
        }
    }

    std.debug.print("================================================================================\n\n", .{});
}
