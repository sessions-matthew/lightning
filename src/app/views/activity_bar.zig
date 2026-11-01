//! Far-left Activity Bar (44pt wide) with icons for Explorer, Search, Plugins, and dynamic plugin sidebars.

const skia = @import("skia");
const ui = @import("ui");
const state_mod = @import("../state.zig");
const EditorState = state_mod.EditorState;

pub const ActivityAction = struct {
    layout_changed: bool = false,
};

pub fn build(state: *EditorState, active_activity: *u8) ActivityAction {
    const uic = &state.ui_ctx;
    var action = ActivityAction{};

    _ = uic.beginBox(44, 0, .{
        .direction = .column,
        .padding = ui.Padding.xy(0, 6),
        .gap = 4,
        .bg_color = skia.Color.rgb(16, 20, 28),
        .border_color = uic.theme.border_subtle,
        .border_width = 1.0,
        .border_edges = .right_only,
    });
    defer uic.endBox();

    const items = [_]struct { id: []const u8, icon: ui.Icon }{
        .{ .id = "##act_explorer", .icon = .files },
        .{ .id = "##act_search", .icon = .search },
        .{ .id = "##act_plugins", .icon = .plugins },
    };

    for (items, 0..) |item, idx| {
        const idx_u8: u8 = @intCast(idx);
        const is_selected = state.doc.show_sidebar and (active_activity.* == idx_u8);
        if (uic.iconButton(item.id, item.icon, .{
            .w = 44.0,
            .h = 40.0,
            .active = is_selected,
            .show_active_bar = true,
        })) {
            if (active_activity.* == idx_u8) {
                state.doc.show_sidebar = !state.doc.show_sidebar;
            } else {
                active_activity.* = idx_u8;
                state.doc.show_sidebar = true;
            }
            if (active_activity.* == 1 and state.doc.show_sidebar) {
                uic.focusScopedAndSelectAll(&.{"explorer_sidebar"}, "##workspace_search_input");
            }
            if (active_activity.* == 2 and state.doc.show_sidebar) {
                _ = state.plugins.scanAndReloadPlugins(state, true);
                uic.focusScopedAndSelectAll(&.{"explorer_sidebar"}, "##plugin_search_input");
            }
            action.layout_changed = true;
        }
    }

    // Dynamic Activity Bar icons contributed by enabled plugins (e.g., Git Source Control, LLDB Debug, RTL Sim, Hex Inspector)
    var rendered_plugin_divider = false;
    for (0..state.plugins.plugin_count) |p_idx| {
        const p = &state.plugins.plugins[p_idx];
        if (!p.active or !p.enabled or !p.capabilities.sidebar_panel or p.sidebar_icon == .none) continue;

        if (!rendered_plugin_divider) {
            rendered_plugin_divider = true;
            uic.divider();
        }

        var id_guard = uic.scopedId(p_idx + 100);
        defer id_guard.end();

        const act_id: u8 = @intCast(3 + p_idx);
        const is_selected = state.doc.show_sidebar and (active_activity.* == act_id);
        const icon: ui.Icon = switch (p.sidebar_icon) {
            .debug => .debug,
            .cpu => .cpu,
            .board => .board,
            .waveform => .waveform,
            .pdf => .pdf,
            .git => .git,
            .plugins => .plugins,
            .none => .plugins,
        };
        const accent_col: ?u32 = switch (p.sidebar_icon) {
            .debug => skia.Color.rgb(249, 115, 22), // Warm Debug Orange
            .waveform => skia.Color.rgb(168, 85, 247), // Logic Analyzer Violet
            .pdf => skia.Color.rgb(244, 63, 94), // PDF Rose/Crimson
            .cpu => skia.Color.rgb(56, 189, 248), // Hardware Cyan
            .board => skia.Color.rgb(250, 204, 21), // BeagleBone Silkscreen Gold/Amber
            .git => skia.Color.rgb(52, 211, 153),
            else => null,
        };
        if (uic.iconButton("##act_plugin_icon", icon, .{
            .w = 44.0,
            .h = 40.0,
            .active = is_selected,
            .show_active_bar = true,
            .accent_color = accent_col,
        })) {
            if (active_activity.* == act_id) {
                state.doc.show_sidebar = !state.doc.show_sidebar;
            } else {
                active_activity.* = act_id;
                state.doc.show_sidebar = true;
            }
            action.layout_changed = true;
        }
    }

    const avail_h = uic.availableHeight();
    if (avail_h > 92) {
        uic.spacer(avail_h - 92);
    }

    if (uic.iconButton("##act_toggle_agent", .agent, .{
        .w = 44.0,
        .h = 40.0,
        .active = state.doc.show_agent_panel,
        .show_active_bar = true,
    })) {
        state.doc.show_agent_panel = !state.doc.show_agent_panel;
        if (state.doc.show_agent_panel) {
            uic.focusScoped(&.{"agy_agent_panel"}, "##agy_prompt_input");
        }
        action.layout_changed = true;
    }

    if (uic.iconButton("##act_toggle_panel", .terminal, .{
        .w = 44.0,
        .h = 40.0,
        .active = state.doc.show_bottom_panel,
        .show_active_bar = true,
    })) {
        state.doc.show_bottom_panel = !state.doc.show_bottom_panel;
        action.layout_changed = true;
    }

    return action;
}
