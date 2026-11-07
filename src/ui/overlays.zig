//! Declarative Overlay, Modal Prompt, Typed Action Context Menu, Focus Trap,
//! and Status Bar Segment Primitives for `ui.Context`.

const std = @import("std");
const skia = @import("skia");
const platform = @import("platform");
const root = @import("root.zig");
const layout = @import("layout.zig");

const c = skia.c;
const Color = skia.Color;
const Rect = skia.Rect;
const Context = root.Context;
const WidgetId = root.WidgetId;
const ContextMenuItem = root.ContextMenuItem;
const ContextMenuState = root.ContextMenuState;

/// Result returned each frame by `Context.promptModal`.
pub const PromptModalResult = enum {
    none,
    confirmed,
    cancelled,
};

/// Declarative configuration for `Context.promptModal`.
pub const PromptModalConfig = struct {
    title: []const u8,
    placeholder: []const u8 = "",
    hint: []const u8 = "",
    confirm_label: []const u8 = "Confirm",
    cancel_label: []const u8 = "Cancel",
    input_id: []const u8 = "",
    outside_click_min_y: f32 = 0.0,
    require_non_empty: bool = true,
    padding: layout.Padding = layout.Padding.xy(16, 12),
    gap: f32 = 8.0,
};

/// Typed context menu item descriptor mapping a menu row directly to a domain `Action` enum value.
/// Eliminates fragile positional integer switches when separators or conditional items are added.
pub fn ActionMenuItem(comptime Action: type) type {
    return struct {
        action: ?Action = null,
        label: []const u8,
        shortcut: []const u8 = "",
        disabled: bool = false,
        danger: bool = false,
        separator: bool = false,

        pub fn item(action: Action, label: []const u8, shortcut: []const u8) @This() {
            return .{ .action = action, .label = label, .shortcut = shortcut };
        }

        pub fn itemOpts(
            action: Action,
            label: []const u8,
            shortcut: []const u8,
            opts: struct { disabled: bool = false, danger: bool = false },
        ) @This() {
            return .{
                .action = action,
                .label = label,
                .shortcut = shortcut,
                .disabled = opts.disabled,
                .danger = opts.danger,
            };
        }

        pub fn info(label: []const u8) @This() {
            return .{ .action = null, .label = label, .disabled = true };
        }

        pub fn sep() @This() {
            return .{ .action = null, .label = "---", .separator = true };
        }
    };
}

/// Ensures that `uic.focused_id` is trapped inside the active modal overlay's primary text input (`input_wid`).
/// If `uic.focused_id` matches any `legacy_alias_ids` (or is `0` / outside the modal), focus is redirected
/// to `input_wid` (preserving `select_all_wid` if an alias was targeted with `focusAndSelectAll`).
pub fn ensureOverlayInputFocus(
    uic: *Context,
    input_wid: WidgetId,
    legacy_alias_ids: []const WidgetId,
) void {
    for (legacy_alias_ids) |alias_id| {
        if (alias_id != 0 and uic.select_all_wid == alias_id) {
            uic.select_all_wid = input_wid;
        }
        if (alias_id != 0 and uic.focused_id == alias_id) {
            uic.focused_id = input_wid;
            return;
        }
    }
    if (uic.focused_id != input_wid) {
        uic.focused_id = input_wid;
    }
}

/// Renders a complete floating text-input prompt modal (`overlayBox` + title label + auto-focused
/// `textFieldInline` + `Enter`/`Escape`/outside-click handling + hint/Cancel/Confirm footer row).
/// Consumes an identical number of layout rectangles in both `Pass.input` and `Pass.paint`.
pub fn promptModal(
    uic: *Context,
    comptime capacity: usize,
    id_scope: []const u8,
    modal_rect: c.sk_rect_t,
    buf: *platform.InlineString(capacity),
    config: PromptModalConfig,
) PromptModalResult {
    const outside_clicked = if (config.outside_click_min_y > 0.0)
        uic.isClickedOutsideOverlay(modal_rect, config.outside_click_min_y)
    else
        uic.clickedOutside(&.{modal_rect});

    const use_explicit_input_id = (config.input_id.len > 0 or std.mem.startsWith(u8, id_scope, "##"));
    const input_label = if (config.input_id.len > 0)
        config.input_id
    else if (std.mem.startsWith(u8, id_scope, "##"))
        id_scope
    else
        "##prompt_input";

    if (!use_explicit_input_id) {
        uic.pushId(id_scope);
    }

    const input_wid = uic.resolveIdAndLabel(input_label).wid;
    ensureOverlayInputFocus(uic, input_wid, &.{});

    var dialog = uic.overlayBox(modal_rect, .{
        .padding = config.padding,
        .gap = config.gap,
        .bg_color = Color.rgb(20, 26, 38),
        .border_color = Color.argb(150, 100, 116, 139),
        .border_width = 1.0,
        .corner_radius = 8.0,
    });

    uic.label(config.title, Color.rgb(241, 245, 249));

    const tf = uic.textFieldInline(
        input_label,
        buf,
        config.placeholder,
        .{ .w = .fill },
    );

    if (use_explicit_input_id) {
        uic.pushId(id_scope);
    }

    var cancel_clicked = false;
    var confirm_clicked = false;
    {
        var actions = uic.row(.{
            .h = .pixels(26),
            .gap = 8,
        });
        defer actions.end();

        const hint_box_w = @max(40.0, uic.availableWidth() - 148.0);
        {
            var hint_box = uic.row(.{ .w = .pixels(hint_box_w), .h = .pixels(24) });
            defer hint_box.end();
            if (config.hint.len > 0) {
                uic.label(config.hint, Color.rgb(100, 116, 139));
            }
        }
        if (uic.btn(config.cancel_label, .{ .w = .pixels(66), .h = 24, .id_override = "##prompt_cancel" })) {
            cancel_clicked = true;
        }
        if (uic.btn(config.confirm_label, .{ .w = .pixels(66), .h = 24, .variant = .primary, .id_override = "##prompt_confirm" })) {
            confirm_clicked = true;
        }
    }

    dialog.end();
    uic.popId();

    if (outside_clicked or tf.escaped or cancel_clicked) {
        if (uic.pass == .input and uic.frame_registered_overlay_count > 0) {
            uic.frame_registered_overlay_count -= 1;
        }
        uic.invalidateWindow();
        return .cancelled;
    }

    const trimmed = std.mem.trim(u8, buf.slice(), " \t\r\n");
    const can_confirm = !config.require_non_empty or trimmed.len > 0;
    if ((tf.submitted or confirm_clicked) and can_confirm) {
        if (uic.pass == .input and uic.frame_registered_overlay_count > 0) {
            uic.frame_registered_overlay_count -= 1;
        }
        uic.invalidateWindow();
        return .confirmed;
    }

    return .none;
}

/// Declarative configuration for `Context.filePickerModal`.
pub const FilePickerModalConfig = struct {
    title: []const u8,
    placeholder: []const u8 = "Enter directory or file path (or ~/...)",
    hint: []const u8 = "Click folder to browse · Enter or Open to select · Esc to Cancel",
    confirm_label: []const u8 = "Open",
    cancel_label: []const u8 = "Cancel",
    input_id: []const u8 = "##open_workspace_input",
    outside_click_min_y: f32 = 36.0,
    list_height: f32 = 192.0,
    show_files: bool = true,
    require_non_empty: bool = true,
    padding: layout.Padding = layout.Padding.xy(14, 10),
    gap: f32 = 6.0,
};

const FilePickerEntry = struct {
    name: []const u8,
    full_path: []const u8,
    is_dir: bool,
    is_parent: bool = false,
};

fn pickerEntryLessThan(_: void, a: FilePickerEntry, b: FilePickerEntry) bool {
    if (a.is_parent != b.is_parent) return a.is_parent;
    if (a.is_dir != b.is_dir) return a.is_dir;
    const min_len = @min(a.name.len, b.name.len);
    for (0..min_len) |i| {
        const ca = std.ascii.toLower(a.name[i]);
        const cb = std.ascii.toLower(b.name[i]);
        if (ca != cb) return ca < cb;
    }
    return a.name.len < b.name.len;
}

fn expandHomePath(arena: std.mem.Allocator, raw_trimmed: []const u8) []const u8 {
    if (std.mem.eql(u8, raw_trimmed, "~") or std.mem.startsWith(u8, raw_trimmed, "~/")) {
        const home_opt = platform.fs_util.getenv("HOME") orelse platform.fs_util.getenv("USERPROFILE");
        if (home_opt) |home_z| {
            const home = std.mem.sliceTo(home_z, 0);
            const rest = if (raw_trimmed.len > 1) raw_trimmed[1..] else "";
            return std.fmt.allocPrint(arena, "{s}{s}", .{ home, rest }) catch raw_trimmed;
        }
    }
    return raw_trimmed;
}

fn checkPathIsDir(path_slice: []const u8) bool {
    if (path_slice.len == 0 or path_slice.len >= 510) return false;
    var path_z: [512:0]u8 = @splat(0);
    @memcpy(path_z[0..path_slice.len], path_slice);
    path_z[path_slice.len] = 0;
    return platform.fs_util.isDirectoryOnDisk(&path_z);
}

/// Renders an interactive in-app File & Folder Picker Modal (`overlayBox` + quick navigation buttons
/// `↑ Up`, `~ Home`, `. CWD` + auto-focused path `textFieldInline` + scrollable directory/file browser
/// + keyboard `Up`/`Down`/`Tab`/`Enter`/`Escape` + Cancel/Open action row).
/// Latches the browsed path at the start of `Pass.input` so `Pass.input` and `Pass.paint` always
/// consume the exact same layout rectangles (`last_input_rect_count == last_paint_rect_count`).
pub fn filePickerModal(
    uic: *Context,
    comptime capacity: usize,
    id_scope: []const u8,
    modal_rect: c.sk_rect_t,
    buf: *platform.InlineString(capacity),
    selected_idx: *usize,
    config: FilePickerModalConfig,
) PromptModalResult {
    const outside_clicked = if (config.outside_click_min_y > 0.0)
        uic.isClickedOutsideOverlay(modal_rect, config.outside_click_min_y)
    else
        uic.clickedOutside(&.{modal_rect});

    // Latch the current path before any input mutations so `.input` and `.paint` enumerate identical entries
    const cur_slice = uic.arena.dupe(u8, buf.slice()) catch buf.slice();
    const latched_ptr = uic.latch([*]const u8, cur_slice.ptr);
    const latched_len = uic.latch(usize, cur_slice.len);
    const latched_raw = latched_ptr[0..latched_len];
    const trimmed_raw = std.mem.trim(u8, latched_raw, " \t\r\n\"'");

    var cwd_buf: [512]u8 = undefined;
    const cwd_slice: []const u8 = if (platform.fs_util.getcwd(&cwd_buf, cwd_buf.len)) |p|
        std.mem.sliceTo(p, 0)
    else
        ".";

    const expanded = if (trimmed_raw.len > 0)
        expandHomePath(uic.arena, trimmed_raw)
    else
        cwd_slice;

    const PickerScanCache = struct {
        browse_dir: []const u8 = "",
        entries: []const FilePickerEntry = &.{},

        const ScanCtx = struct {
            expanded: []const u8,
            cwd_slice: []const u8,
            show_files: bool,
        };

        fn build(arena: std.mem.Allocator, sctx: ScanCtx) *@This() {
            var b_dir: []const u8 = sctx.cwd_slice;
            var f_prefix: []const u8 = "";

            if (checkPathIsDir(sctx.expanded)) {
                var clean = sctx.expanded;
                while (clean.len > 1 and clean[clean.len - 1] == '/') {
                    clean = clean[0 .. clean.len - 1];
                }
                b_dir = clean;
            } else if (std.fs.path.dirname(sctx.expanded)) |parent| {
                const eff_parent = if (parent.len == 0) "." else parent;
                if (checkPathIsDir(eff_parent)) {
                    b_dir = eff_parent;
                    f_prefix = std.fs.path.basename(sctx.expanded);
                }
            }

            var list = arena.alloc(FilePickerEntry, 96) catch unreachable;
            var cnt: usize = 0;

            if (f_prefix.len == 0) {
                if (std.fs.path.dirname(b_dir)) |parent_dir| {
                    if (!std.mem.eql(u8, parent_dir, b_dir)) {
                        list[cnt] = .{
                            .name = ".. (Parent Directory)",
                            .full_path = arena.dupe(u8, parent_dir) catch parent_dir,
                            .is_dir = true,
                            .is_parent = true,
                        };
                        cnt += 1;
                    }
                }
            }

            if (b_dir.len > 0 and b_dir.len < 500) {
                var dir_z: [512:0]u8 = @splat(0);
                @memcpy(dir_z[0..b_dir.len], b_dir);
                dir_z[b_dir.len] = 0;
                if (platform.fs_util.opendir(&dir_z)) |dirp| {
                    defer _ = platform.fs_util.closedir(dirp);
                    const show_hidden = (f_prefix.len > 0 and f_prefix[0] == '.');
                    while (platform.fs_util.readdir(dirp)) |ent| {
                        if (cnt >= list.len) break;
                        const raw_ent_name = platform.fs_util.direntName(ent);
                        if (raw_ent_name.len == 0 or std.mem.eql(u8, raw_ent_name, ".") or std.mem.eql(u8, raw_ent_name, "..")) continue;
                        const name_raw = if (raw_ent_name.len > 8 and raw_ent_name[0] == '.' and std.mem.endsWith(u8, raw_ent_name, ".icloud")) blk: {
                            const unwrapped = raw_ent_name[1 .. raw_ent_name.len - 7];
                            break :blk if (unwrapped.len > 0 and unwrapped[0] != '.') unwrapped else raw_ent_name;
                        } else raw_ent_name;
                        if (!show_hidden and name_raw[0] == '.') continue;
                        if (f_prefix.len > 0 and !root.containsIgnoreCase(name_raw, f_prefix)) continue;

                        const joined = if (std.mem.eql(u8, b_dir, "/"))
                            (std.fmt.allocPrint(arena, "/{s}", .{name_raw}) catch continue)
                        else if (std.mem.eql(u8, b_dir, "."))
                            (arena.dupe(u8, name_raw) catch continue)
                        else
                            (std.fmt.allocPrint(arena, "{s}/{s}", .{ b_dir, name_raw }) catch continue);

                        var dup_entry = false;
                        for (list[0..cnt]) |ex| {
                            if (std.mem.eql(u8, ex.full_path, joined)) {
                                dup_entry = true;
                                break;
                            }
                        }
                        if (dup_entry) continue;

                        const is_dir = if (ent.d_type == platform.fs_util.DT_DIR)
                            true
                        else if (ent.d_type == platform.fs_util.DT_REG)
                            false
                        else
                            checkPathIsDir(joined);
                        if (!is_dir and !sctx.show_files) continue;

                        const disp_name = if (is_dir)
                            (std.fmt.allocPrint(arena, "{s}/", .{name_raw}) catch continue)
                        else
                            (arena.dupe(u8, name_raw) catch continue);

                        list[cnt] = .{
                            .name = disp_name,
                            .full_path = joined,
                            .is_dir = is_dir,
                            .is_parent = false,
                        };
                        cnt += 1;
                    }
                }
            }

            if (cnt > 1) {
                std.mem.sort(FilePickerEntry, list[0..cnt], {}, pickerEntryLessThan);
            }

            const res = arena.create(@This()) catch unreachable;
            res.* = .{
                .browse_dir = arena.dupe(u8, b_dir) catch b_dir,
                .entries = list[0..cnt],
            };
            return res;
        }
    };

    const scan_cache = uic.useFrameCache(
        PickerScanCache,
        id_scope,
        PickerScanCache.ScanCtx{
            .expanded = expanded,
            .cwd_slice = cwd_slice,
            .show_files = config.show_files,
        },
        PickerScanCache.build,
    );
    const browse_dir = scan_cache.browse_dir;
    const entries = scan_cache.entries;
    const entry_count = entries.len;
    if (entry_count > 0 and selected_idx.* >= entry_count) {
        selected_idx.* = entry_count - 1;
    }

    const use_explicit_input_id = (config.input_id.len > 0 or std.mem.startsWith(u8, id_scope, "##"));
    const input_label = if (config.input_id.len > 0)
        config.input_id
    else if (std.mem.startsWith(u8, id_scope, "##"))
        id_scope
    else
        "##prompt_input";

    if (!use_explicit_input_id) {
        uic.pushId(id_scope);
    }

    const input_wid = uic.resolveIdAndLabel(input_label).wid;
    ensureOverlayInputFocus(uic, input_wid, &.{});

    var dialog = uic.overlayBox(modal_rect, .{
        .padding = config.padding,
        .gap = config.gap,
        .bg_color = Color.rgb(20, 26, 38),
        .border_color = Color.argb(150, 100, 116, 139),
        .border_width = 1.0,
        .corner_radius = 8.0,
    });

    var nav_up_clicked = false;
    var nav_home_clicked = false;
    var nav_cwd_clicked = false;
    {
        var hdr = uic.row(.{
            .h = .pixels(24),
            .gap = 6,
        });
        defer hdr.end();

        const title_box_w = @max(60.0, uic.availableWidth() - 196.0);
        {
            var title_box = uic.row(.{ .w = .pixels(title_box_w), .h = .pixels(24) });
            defer title_box.end();
            uic.label(config.title, Color.rgb(241, 245, 249));
        }
        if (uic.btn("↑ Up", .{ .w = .pixels(52), .h = 22, .id_override = "##fp_nav_up" })) {
            nav_up_clicked = true;
        }
        if (uic.btn("~ Home", .{ .w = .pixels(64), .h = 22, .id_override = "##fp_nav_home" })) {
            nav_home_clicked = true;
        }
        if (uic.btn(". CWD", .{ .w = .pixels(58), .h = 22, .id_override = "##fp_nav_cwd" })) {
            nav_cwd_clicked = true;
        }
    }

    const tf = uic.textFieldInline(
        input_label,
        buf,
        config.placeholder,
        .{ .w = .fill },
    );

    if (use_explicit_input_id) {
        uic.pushId(id_scope);
    }

    if (tf.changed) {
        selected_idx.* = 0;
        uic.invalidateWindow();
    }
    if (entry_count > 0) {
        if (tf.arrow_down) {
            selected_idx.* = (selected_idx.* + 1) % entry_count;
            uic.invalidateWindow();
        } else if (tf.arrow_up) {
            selected_idx.* = (selected_idx.* + entry_count - 1) % entry_count;
            uic.invalidateWindow();
        } else if (tf.tab_pressed) {
            const sel_entry = entries[@min(selected_idx.*, entry_count - 1)];
            buf.set(sel_entry.full_path);
            selected_idx.* = 0;
            uic.invalidateWindow();
        }
    }

    var clicked_entry_idx: ?usize = null;
    {
        var list_scroll = uic.scrollPanel("fp_dir_scroll", .{
            .h = .pixels(config.list_height),
            .gap = 2,
            .bg_color = Color.rgb(14, 18, 26),
            .padding = layout.Padding.xy(4, 4),
        });
        defer list_scroll.end();

        if (entry_count == 0) {
            uic.label("No matching folders or files in directory.", Color.rgb(100, 116, 139));
        } else {
            const vr = uic.computeVirtualRange(entry_count, 25.0, 2);
            if (vr.top_spacer_h > 0) uic.spacer(vr.top_spacer_h);
            for (vr.first..vr.end) |e_idx| {
                const entry = entries[e_idx];
                var eid = uic.scopedId(e_idx + 5000);
                defer eid.end();

                const is_sel = (e_idx == selected_idx.*);
                if (uic.listItem(.{
                    .label = entry.name,
                    .meta = if (entry.is_parent) "parent" else if (entry.is_dir) "folder" else "file",
                    .icon_text = if (entry.is_dir) "DIR" else "FILE",
                    .icon_color = if (entry.is_dir) Color.rgb(96, 165, 250) else Color.rgb(148, 163, 184),
                    .icon_bg = if (entry.is_dir) Color.argb(40, 59, 130, 246) else Color.argb(35, 100, 116, 139),
                    .selected = is_sel,
                    .height = 23.0,
                    .mono_label = true,
                })) {
                    clicked_entry_idx = e_idx;
                }
            }
            if (vr.bottom_spacer_h > 0) uic.spacer(vr.bottom_spacer_h);
        }
    }

    var cancel_clicked = false;
    var confirm_clicked = false;
    {
        var actions = uic.row(.{
            .h = .pixels(26),
            .gap = 8,
        });
        defer actions.end();

        const hint_box_w = @max(40.0, uic.availableWidth() - 148.0);
        {
            var hint_box = uic.row(.{ .w = .pixels(hint_box_w), .h = .pixels(24) });
            defer hint_box.end();
            if (config.hint.len > 0) {
                uic.label(config.hint, Color.rgb(100, 116, 139));
            }
        }
        if (uic.btn(config.cancel_label, .{ .w = .pixels(66), .h = 24, .id_override = "##prompt_cancel" })) {
            cancel_clicked = true;
        }
        if (uic.btn(config.confirm_label, .{ .w = .pixels(66), .h = 24, .variant = .primary, .id_override = "##prompt_confirm" })) {
            confirm_clicked = true;
        }
    }

    dialog.end();
    uic.popId();

    if (uic.pass == .input) {
        if (nav_up_clicked) {
            if (std.fs.path.dirname(browse_dir)) |parent_dir| {
                buf.set(parent_dir);
                selected_idx.* = 0;
                uic.invalidateWindow();
            }
        } else if (nav_home_clicked) {
            const home_opt = platform.fs_util.getenv("HOME") orelse platform.fs_util.getenv("USERPROFILE");
            if (home_opt) |home_z| {
                buf.set(std.mem.sliceTo(home_z, 0));
            } else {
                buf.set("~");
            }
            selected_idx.* = 0;
            uic.invalidateWindow();
        } else if (nav_cwd_clicked) {
            buf.set(cwd_slice);
            selected_idx.* = 0;
            uic.invalidateWindow();
        } else if (clicked_entry_idx) |c_idx| {
            const entry = entries[c_idx];
            if (entry.is_dir) {
                buf.set(entry.full_path);
                selected_idx.* = 0;
                uic.invalidateWindow();
            } else {
                if (std.mem.eql(u8, std.mem.trim(u8, buf.slice(), " \t\r\n"), entry.full_path)) {
                    confirm_clicked = true;
                } else {
                    buf.set(entry.full_path);
                    selected_idx.* = c_idx;
                    uic.invalidateWindow();
                }
            }
        }
    }

    if (outside_clicked or tf.escaped or cancel_clicked) {
        if (uic.pass == .input and uic.frame_registered_overlay_count > 0) {
            uic.frame_registered_overlay_count -= 1;
        }
        uic.invalidateWindow();
        return .cancelled;
    }

    const trimmed = std.mem.trim(u8, buf.slice(), " \t\r\n");
    const can_confirm = !config.require_non_empty or trimmed.len > 0;
    if ((tf.submitted or confirm_clicked) and can_confirm) {
        if (uic.pass == .input and uic.frame_registered_overlay_count > 0) {
            uic.frame_registered_overlay_count -= 1;
        }
        uic.invalidateWindow();
        return .confirmed;
    }

    return .none;
}

/// Returns `true` when `(x, y)` is covered by any explicit blocking overlay rect registered via
/// `setBlockingOverlay` OR any auto-retained `overlayBox` rect from the previous input pass,
/// while the caller is not currently inside an `overlayBox` (`!uic.in_overlay`).
pub fn isBlockedByOverlay(uic: *const Context, x: f32, y: f32) bool {
    if (uic.in_overlay) return false;
    for (uic.blocking_overlay_rects[0..uic.blocking_overlay_count]) |ov| {
        if (x >= ov.left and x <= ov.right and y >= ov.top and y <= ov.bottom) {
            return true;
        }
    }
    if (uic.blocking_overlay_count == 0) {
        if (uic.blocking_overlay_rect) |ov| {
            if (x >= ov.left and x <= ov.right and y >= ov.top and y <= ov.bottom) {
                return true;
            }
        }
    }
    for (uic.retained_overlay_rects[0..uic.retained_overlay_count]) |ov| {
        if (x >= ov.left and x <= ov.right and y >= ov.top and y <= ov.bottom) {
            return true;
        }
    }
    return false;
}

/// Renders a floating right-click context menu from a slice of `ActionMenuItem(Action)` and returns
/// the selected `?Action` enum tag (or `null` if no item was activated).
/// `state_or_anchor` may be either a `*ContextMenuState` pointer or an anchor `sk_rect_t`.
pub fn contextMenuActions(
    uic: *Context,
    comptime Action: type,
    id_str: []const u8,
    state_or_anchor: anytype,
    action_items: []const ActionMenuItem(Action),
) ?Action {
    if (action_items.len == 0) return null;

    var stack_items: [32]ContextMenuItem = undefined;
    const count = @min(action_items.len, stack_items.len);
    var max_row_w: f32 = 216.0;

    for (action_items[0..count], 0..) |ai, idx| {
        stack_items[idx] = .{
            .label = ai.label,
            .shortcut = ai.shortcut,
            .enabled = !ai.disabled,
            .separator = ai.separator,
            .danger = ai.danger,
        };
        if (!ai.separator) {
            const lw = uic.measureTextCached(uic.font_body, ai.label);
            const sw = if (ai.shortcut.len > 0) uic.measureTextCached(uic.font_mono, ai.shortcut) + 18.0 else 0.0;
            max_row_w = @max(max_row_w, lw + sw + 28.0);
        }
    }
    const auto_w = std.math.clamp(@ceil(max_row_w), 208.0, 280.0);

    const ArgType = @TypeOf(state_or_anchor);
    if (ArgType == *ContextMenuState) {
        if (uic.contextMenu(id_str, state_or_anchor, auto_w, stack_items[0..count])) |choice_idx| {
            if (choice_idx < count) {
                return action_items[choice_idx].action;
            }
        }
        return null;
    } else if (ArgType == c.sk_rect_t) {
        const rect_w = state_or_anchor.right - state_or_anchor.left;
        const menu_w = if (rect_w >= 120.0) rect_w else auto_w;
        var temp_state = ContextMenuState{
            .open = true,
            .anchor_x = state_or_anchor.left,
            .anchor_y = state_or_anchor.top,
            .opened_this_frame = false,
        };
        if (uic.contextMenu(id_str, &temp_state, menu_w, stack_items[0..count])) |choice_idx| {
            if (choice_idx < count) {
                return action_items[choice_idx].action;
            }
        }
        return null;
    } else {
        @compileError("contextMenuActions expects `*ContextMenuState` or `skia.c.sk_rect_t` as 4th argument");
    }
}

/// Renders a compact status bar indicator consisting of a colored status dot (`dot_color`)
/// followed by a monospace label (`text`). Safe for two-phase layout inside a status strip row.
pub fn statusDotIndicator(
    uic: *Context,
    dot_color: u32,
    text: []const u8,
    text_color: ?u32,
) void {
    const tw = uic.measureTextCached(uic.font_mono, text);
    const r = uic.nextRect(tw + 14.0, 18.0);
    if (!uic.shouldPaint(r)) return;

    uic.paint.setStyle(.fill);
    uic.paint.setColor(dot_color);
    uic.canvas.drawCircle(r.left + 4.0, (r.top + r.bottom) * 0.5, 3.2, uic.paint);

    uic.paint.setColor(text_color orelse uic.theme.text_muted);
    uic.drawTextCached(uic.font_mono, text, r.left + 12.0, r.top + 13.0);
}

/// Renders a monospace text segment inside a status strip row.
pub fn statusTextSegment(
    uic: *Context,
    text: []const u8,
    text_color: ?u32,
) void {
    const tw = uic.measureTextCached(uic.font_mono, text);
    const r = uic.nextRect(tw, 18.0);
    if (!uic.shouldPaint(r)) return;

    uic.paint.setStyle(.fill);
    uic.paint.setColor(text_color orelse uic.theme.text_muted);
    uic.drawTextCached(uic.font_mono, text, r.left, r.top + 13.0);
}

test "overlays: promptModal two-phase layout determinism, focus trap, Enter confirm, and Escape/outside cancel" {
    const surface = try skia.Surface.initRasterN32Premul(640, 360);
    defer surface.deinit();
    const paint = try skia.Paint.init();
    defer paint.deinit();
    const font = try skia.Font.init(null, 13.0);
    defer font.deinit();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var uic = Context{
        .arena = arena.allocator(),
        .canvas = surface.canvas(),
        .paint = paint,
        .font_title = font,
        .font_body = font,
        .font_mono = font,
    };
    defer uic.deinit();

    const win_rect = Rect.xywh(0, 0, 640, 360);
    const modal_rect = Rect.xywh(120, 60, 400, 118);
    var path_buf: platform.InlineString(256) = .{};
    path_buf.set("src/new_module.zig");

    // 1. Frame 1 (Pass.input + Pass.paint): auto-focuses prompt input & preserves rect count determinism
    uic.focused_id = 0;
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 200, 100, false, false, false);
    const res_idle = uic.promptModal(256, "save_as", modal_rect, &path_buf, .{
        .title = "Save Buffer As New File",
        .placeholder = "path/to/file.zig...",
        .hint = "Enter to Save · Esc to Cancel",
        .confirm_label = "Save",
        .input_id = "##save_as_input",
    });
    uic.endPass();
    try std.testing.expectEqual(PromptModalResult.none, res_idle);
    try std.testing.expectEqual(uic.resolveIdAndLabel("##save_as_input").wid, uic.focused_id);

    uic.beginPass(.paint, arena.allocator(), surface.canvas(), win_rect, 200, 100, false, false, false);
    _ = uic.promptModal(256, "save_as", modal_rect, &path_buf, .{
        .title = "Save Buffer As New File",
        .placeholder = "path/to/file.zig...",
        .hint = "Enter to Save · Esc to Cancel",
        .confirm_label = "Save",
        .input_id = "##save_as_input",
    });
    uic.endPass();
    try std.testing.expectEqual(uic.last_input_rect_count, uic.last_paint_rect_count);

    // 2. Pressing Enter with non-empty buffer returns `.confirmed`
    const enter_kev = [_]platform.KeyEvent{.{ .key = .enter }};
    uic.key_events = &enter_kev;
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 200, 100, false, false, false);
    const res_enter = uic.promptModal(256, "save_as", modal_rect, &path_buf, .{
        .title = "Save Buffer As New File",
        .placeholder = "path/to/file.zig...",
        .hint = "Enter to Save · Esc to Cancel",
        .confirm_label = "Save",
        .input_id = "##save_as_input",
    });
    uic.endPass();
    uic.key_events = &.{};
    try std.testing.expectEqual(PromptModalResult.confirmed, res_enter);

    // 3. Pressing Escape returns `.cancelled`
    const esc_kev = [_]platform.KeyEvent{.{ .key = .escape }};
    uic.key_events = &esc_kev;
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 200, 100, false, false, false);
    const res_esc = uic.promptModal(256, "save_as", modal_rect, &path_buf, .{
        .title = "Save Buffer As New File",
        .placeholder = "path/to/file.zig...",
        .hint = "Enter to Save · Esc to Cancel",
        .confirm_label = "Save",
        .input_id = "##save_as_input",
    });
    uic.endPass();
    uic.key_events = &.{};
    try std.testing.expectEqual(PromptModalResult.cancelled, res_esc);

    // 4. Clicking outside `modal_rect` returns `.cancelled`
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 20, 200, true, true, false);
    const res_outside = uic.promptModal(256, "save_as", modal_rect, &path_buf, .{
        .title = "Save Buffer As New File",
        .placeholder = "path/to/file.zig...",
        .hint = "Enter to Save · Esc to Cancel",
        .confirm_label = "Save",
        .input_id = "##save_as_input",
    });
    uic.endPass();
    try std.testing.expectEqual(PromptModalResult.cancelled, res_outside);
}

test "overlays: contextMenuActions maps clicked items across separators to typed Action enum across .input and .paint passes" {
    const surface = try skia.Surface.initRasterN32Premul(640, 360);
    defer surface.deinit();
    const paint = try skia.Paint.init();
    defer paint.deinit();
    const font = try skia.Font.init(null, 13.0);
    defer font.deinit();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var uic = Context{
        .arena = arena.allocator(),
        .canvas = surface.canvas(),
        .paint = paint,
        .font_title = font,
        .font_body = font,
        .font_mono = font,
    };
    defer uic.deinit();

    const TestAction = enum {
        cut,
        copy,
        paste,
        delete,
    };
    const Item = ActionMenuItem(TestAction);
    const items = [_]Item{
        Item.item(.cut, "Cut", "Cmd+X"),
        Item.item(.copy, "Copy", "Cmd+C"),
        Item.sep(),
        Item.item(.paste, "Paste", "Cmd+V"),
        Item.sep(),
        Item.itemOpts(.delete, "Delete File", "", .{ .danger = true }),
    };

    const win_rect = Rect.xywh(0, 0, 640, 360);
    const anchor = Rect.xywh(40, 40, 220, 0);

    // 1. Hover & paint pass determinism + status bar segments
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 80, 55, false, false, false);
    uic.statusDotIndicator(Color.rgb(52, 211, 153), "main", null);
    uic.statusTextSegment("Ln 10, Col 4", null);
    const idle_act = uic.contextMenuActions(TestAction, "test_ctx", anchor, &items);
    uic.endPass();
    try std.testing.expectEqual(@as(?TestAction, null), idle_act);

    uic.beginPass(.paint, arena.allocator(), surface.canvas(), win_rect, 80, 55, false, false, false);
    uic.statusDotIndicator(Color.rgb(52, 211, 153), "main", null);
    uic.statusTextSegment("Ln 10, Col 4", null);
    _ = uic.contextMenuActions(TestAction, "test_ctx", anchor, &items);
    uic.endPass();
    try std.testing.expectEqual(uic.last_input_rect_count, uic.last_paint_rect_count);

    // 2. Click on "Paste" (after a separator: y = 40 + 4 + 25 + 25 + 7 + 12 = 113) -> maps cleanly to `.paste`
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 90, 113, false, false, true);
    const clicked_act = uic.contextMenuActions(TestAction, "test_ctx", anchor, &items);
    uic.endPass();
    try std.testing.expectEqual(@as(?TestAction, .paste), clicked_act);
}

test "overlays: multi-rect blocking overlays and auto-retained overlayBox rects do not block empty gap between disjoint overlays" {
    const surface = try skia.Surface.initRasterN32Premul(640, 360);
    defer surface.deinit();
    const paint = try skia.Paint.init();
    defer paint.deinit();
    const font = try skia.Font.init(null, 13.0);
    defer font.deinit();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var uic = Context{
        .arena = arena.allocator(),
        .canvas = surface.canvas(),
        .paint = paint,
        .font_title = font,
        .font_body = font,
        .font_mono = font,
    };
    defer uic.deinit();

    const win_rect = Rect.xywh(0, 0, 640, 360);
    const left_ov = Rect.xywh(20, 20, 100, 100);
    const right_ov = Rect.xywh(300, 20, 100, 100);

    // 1. Register two disjoint blocking overlays via `setBlockingOverlay`
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 200, 50, false, false, false);
    uic.setBlockingOverlay(left_ov);
    uic.setBlockingOverlay(right_ov);
    try std.testing.expectEqual(@as(u8, 2), uic.blocking_overlay_count);
    try std.testing.expect(uic.isBlockedByOverlay(60, 60));
    try std.testing.expect(uic.isBlockedByOverlay(350, 60));
    // Empty space at (200, 60) between the two disjoint overlays is NOT blocked
    try std.testing.expect(!uic.isBlockedByOverlay(200, 60));

    // Also render two `overlayBox`es at the end of Pass 1 so they auto-register for the next Pass.input
    {
        var ov1 = uic.overlayBox(left_ov, .{});
        defer ov1.end();
    }
    {
        var ov2 = uic.overlayBox(right_ov, .{});
        defer ov2.end();
    }
    uic.endPass();
    try std.testing.expectEqual(@as(u8, 2), uic.frame_registered_overlay_count);

    // 2. Next Pass.input automatically retains the two overlayBox rects without calling setBlockingOverlay
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 200, 60, false, false, false);
    try std.testing.expectEqual(@as(u8, 2), uic.retained_overlay_count);
    try std.testing.expect(uic.isBlockedByOverlay(60, 60));
    try std.testing.expect(uic.isBlockedByOverlay(350, 60));
    try std.testing.expect(!uic.isBlockedByOverlay(200, 60));
    uic.endPass();
}

test "overlays: filePickerModal two-phase layout determinism, directory listing, and keyboard/click navigation" {
    const surface = try skia.Surface.initRasterN32Premul(800, 600);
    defer surface.deinit();
    const paint = try skia.Paint.init();
    defer paint.deinit();
    const font = try skia.Font.init(null, 13.0);
    defer font.deinit();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var uic = Context{
        .arena = arena.allocator(),
        .canvas = surface.canvas(),
        .paint = paint,
        .font_title = font,
        .font_body = font,
        .font_mono = font,
    };
    defer uic.deinit();

    const win_rect = Rect.xywh(0, 0, 800, 600);
    const modal_rect = Rect.xywh(140, 60, 520, 320);
    var path_buf: platform.InlineString(256) = .{};
    path_buf.set("src");
    var sel_idx: usize = 0;

    // 1. Frame 1: Pass.input + Pass.paint layout determinism when listing `src/`
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 200, 100, false, false, false);
    const res1 = uic.filePickerModal(256, "open_workspace", modal_rect, &path_buf, &sel_idx, .{
        .title = "Open Workspace Folder or File",
    });
    uic.endPass();
    try std.testing.expectEqual(PromptModalResult.none, res1);

    uic.beginPass(.paint, arena.allocator(), surface.canvas(), win_rect, 200, 100, false, false, false);
    _ = uic.filePickerModal(256, "open_workspace", modal_rect, &path_buf, &sel_idx, .{
        .title = "Open Workspace Folder or File",
    });
    uic.endPass();
    try std.testing.expectEqual(uic.last_input_rect_count, uic.last_paint_rect_count);

    // 2. Pressing Enter confirms selection
    const enter_kev = [_]platform.KeyEvent{.{ .key = .enter }};
    uic.key_events = &enter_kev;
    _ = arena.reset(.retain_capacity);
    uic.beginPass(.input, arena.allocator(), surface.canvas(), win_rect, 200, 100, false, false, false);
    const res2 = uic.filePickerModal(256, "open_workspace", modal_rect, &path_buf, &sel_idx, .{
        .title = "Open Workspace Folder or File",
    });
    uic.endPass();
    uic.key_events = &.{};
    try std.testing.expectEqual(PromptModalResult.confirmed, res2);
}

