//! Hot-reloadable application plugin entry point (`libeditor_app.dylib`).
//!
//! Exports `app_init`, `app_before_reload`, `app_on_reload`, `app_tick`, and `app_deinit`:
//!   - `app_before_reload`: Serializes `state.doc` (`WorkspaceDocument`) to the Host's JSON
//!     snapshot buffer and frees all `.dylib`-owned Skia resources prior to `dlclose`.
//!   - `app_on_reload`: Allocates the new `AppState` (even if its struct layout changed!) and
//!     hydrates `state.doc` from the Host's JSON snapshot with `.ignore_unknown_fields = true`.
//!   - Component UI state (`uic.useState`) lives in the Host's Type-Hashed KV Store and
//!     automatically persists across reloads with zero serialization cost.

const skia = @import("skia");
const ui = @import("ui");
const platform = @import("platform");
const PlatformContext = platform.PlatformContext;

const state_mod = @import("state.zig");
const AppState = state_mod.AppState;
const STATE_VERSION = state_mod.STATE_VERSION;

const titlebar_view = @import("views/titlebar.zig");
const sidebar_view = @import("views/sidebar.zig");
const stage_view = @import("views/stage.zig");

comptime {
    ui.exportPlugin(AppState, "doc", STATE_VERSION, buildUiTree);
}

fn buildUiTree(state: *AppState, ctx: *PlatformContext) void {
    const uic = &state.ui_ctx;
    if (uic.pass == .input and ctx.force_full_redraw) {
        state.stage_full_dirty = true;
    }

    // Read component hooks from "sidebar" scope so the top titlebar can display their live values
    var sidebar_scope = uic.scopedState("sidebar");
    const animate_hook = uic.useState(bool, "animate", false);
    const click_count_hook = uic.useState(u32, "click_count", 0);
    sidebar_scope.end();

    ctx.needs_continuous_redraw = animate_hook.*;

    // 1. Custom Unified macOS Titlebar (Full-Bleed Top 46pt)
    const titlebar_rect = titlebar_view.build(state, ctx, animate_hook.*, click_count_hook.*);

    // 2. Main Workspace Body Below Titlebar
    {
        var workspace = uic.row(.{ .preset = .workspace });
        defer workspace.end();

        const sidebar_out = sidebar_view.build(state);
        if (sidebar_out.animate.*) {
            ctx.needs_continuous_redraw = true;
        }

        stage_view.build(
            state,
            ctx,
            sidebar_out.animate.*,
            sidebar_out.stage_params_changed,
            sidebar_out.titlebar_dirty,
            titlebar_rect,
        );
    }

    // 3. Bottom-right Notification Toasts
    uic.renderToasts(4, &state.toasts, skia.Rect.xywh(0, 0, ctx.width, ctx.height));
}
