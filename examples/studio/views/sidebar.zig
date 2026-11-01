//! Left inspector sidebar panel view (`beginScrollBox` / `endScrollBox`).
//! Demonstrates combining:
//!   - **Scrollable Container (`uic.scrollPanel("sidebar_scroll", ...)` / `sidebar.end()`)**
//!     with hardware scissor clipping, trackpad/wheel scrolling, and a draggable scrollbar thumb.
//!   - **Property Inspector Controls (`segmentedControl`, `colorSwatchPicker`, `dragFloat`)**
//!     and notification toasts (`ToastQueue(4)`).
//!   - **Component UI State (`uic.useState`)** scoped to `"sidebar"` (selected tab, animation toggle, click counter)
//!   - **Global Structured Document State (`state.doc`)** persisted across reloads via JSON boundary serialization.

const ui = @import("ui");
const state_mod = @import("../state.zig");
const AppState = state_mod.AppState;
const WorkspaceDocument = state_mod.WorkspaceDocument;
const StageStyleMode = state_mod.StageStyleMode;

pub const SidebarOutput = struct {
    animate: *bool,
    click_count: *u32,
    stage_params_changed: bool = false,
    titlebar_dirty: bool = false,
};

pub fn build(state: *AppState) SidebarOutput {
    const uic = &state.ui_ctx;

    // Push a React-like component scope so hook keys are namespaced under "sidebar"
    var scope = uic.scopedState("sidebar");
    defer scope.end();

    // Component-level UI state stored in the Host's Type-Hashed KV Store (`useState`):
    const selected_tab = uic.useState(u8, "selected_tab", 0);
    const animate = uic.useState(bool, "animate", false);
    const click_count = uic.useState(u32, "click_count", 0);

    var out = SidebarOutput{
        .animate = animate,
        .click_count = click_count,
    };

    var sidebar = uic.scrollPanel("sidebar_scroll", .{
        .w = .pixels(272),
        .preset = .panel_card,
    });
    defer sidebar.end();

    uic.sectionHeader("WORKSPACE VIEW");
    if (uic.tab("Vector Stage##tab_stage", selected_tab.* == 0)) {
        selected_tab.* = 0;
        uic.markDirty(sidebar.rect);
    }
    if (uic.tab("Geometry & Motion##tab_shader", selected_tab.* == 1)) {
        selected_tab.* = 1;
        uic.markDirty(sidebar.rect);
    }

    uic.sectionHeader("STYLE & PALETTE");
    if (uic.segmentedControl(StageStyleMode, "##seg_stage_mode", &state.doc.style_mode)) {
        state.stage_full_dirty = true;
        out.stage_params_changed = true;
    }
    if (uic.colorSwatchPicker("##swatch_accent", &state.doc.accent_color, &state_mod.ACCENT_SWATCHES)) {
        state.rebuildRingShader(state.doc.accent_color);
        state.stage_full_dirty = true;
        out.stage_params_changed = true;
    }

    uic.sectionHeader("RENDERING & DEBUG");
    if (uic.checkbox("Animate Scene (60fps)##tog_animate", animate)) {
        out.titlebar_dirty = true;
        out.stage_params_changed = true;
    }
    if (uic.checkbox("Show Grid##tog_grid", &state.doc.show_grid)) {
        state.stage_full_dirty = true;
        out.stage_params_changed = true;
    }
    if (uic.checkbox("Cursor Halo##tog_halo", &state.doc.show_cursor_halo)) {
        state.stage_full_dirty = true;
        out.stage_params_changed = true;
    }
    if (uic.checkbox("Show Scissor Outline##tog_dirty_vis", &state.doc.show_dirty_overlay)) {
        state.stage_full_dirty = true;
        out.stage_params_changed = true;
    }

    uic.sectionHeader("DOCUMENT PARAMETERS (JSON)");
    if (uic.sliderFloat("Rotation Speed##sld_speed", &state.doc.rotation_speed, 0.0, 4.0)) out.stage_params_changed = true;
    if (uic.sliderFloat("Orbit Rings##sld_rings", &state.doc.ring_count, 1.0, 8.0)) out.stage_params_changed = true;
    if (uic.sliderFloat("Corner Radius##sld_radius", &state.doc.corner_radius, 4.0, 90.0)) out.stage_params_changed = true;
    if (uic.dragFloat("Ring Thickness##df_stroke", &state.doc.stroke_width, 0.08, 1.0, 14.0, 1)) out.stage_params_changed = true;
    if (uic.dragFloat("Wave Spread##df_spread", &state.doc.spread_angle, 0.25, 0.0, 60.0, 1)) out.stage_params_changed = true;
    if (uic.sliderFloat("Stage Zoom##sld_zoom", &state.doc.zoom, 0.4, 2.0)) {
        state.stage_full_dirty = true;
        out.stage_params_changed = true;
    }

    uic.sectionHeader("ACTIONS");
    if (uic.btn("+ Increment Counter##btn_action", .{})) {
        click_count.* += 1;
        out.titlebar_dirty = true;
        state.toasts.push(uic.fmt("Counter incremented to #{d}", .{click_count.*}), .success, 150);
    }
    if (uic.btn("Reset Defaults##btn_reset", .{})) {
        state.doc = WorkspaceDocument{};
        state.rebuildRingShader(state.doc.accent_color);
        animate.* = false;
        state.stage_full_dirty = true;
        uic.markDirty(sidebar.rect);
        out.titlebar_dirty = true;
        out.stage_params_changed = true;
        state.toasts.push("Restored default studio parameters", .info, 180);
    }

    return out;
}
