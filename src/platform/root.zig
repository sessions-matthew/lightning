//! Platform abstraction module: C-ABI plugin boundary, Host `StateStore` (`useState` + scopes),
//! Reload-Boundary JSON `SnapshotBuffer`, dynamic library hot-reloader, and macOS Metal window host.

const builtin = @import("builtin");

pub const state_store = @import("state_store.zig");
pub const app_api = @import("app_api.zig");
pub const plugin_abi = @import("plugin_abi.zig");
pub const plugin_sdk = @import("plugin_sdk.zig");
pub const lsp_client = @import("lsp_client.zig");
pub const posix_poller = @import("posix_poller.zig");
pub const async_task = @import("async_task.zig");
pub const fs_util = @import("fs_util.zig");
pub const hot_dylib = @import("hot_dylib.zig");
pub const objc = @import("macos/objc.zig");
pub const metal_window = if (builtin.os.tag == .macos) @import("macos/metal_window.zig") else struct {};
pub const win32_window = if (builtin.os.tag == .windows) @import("windows/win32_window.zig") else struct {};
pub const linux_window = if (builtin.os.tag == .linux) @import("linux/linux_window.zig") else struct {};
pub const window_host = if (builtin.os.tag == .windows)
    win32_window
else if (builtin.os.tag == .linux)
    linux_window
else
    metal_window;
pub const profiler = @import("profiler.zig");

pub const StateStore = state_store.StateStore;
pub const StateEntry = state_store.StateEntry;
pub const SnapshotBuffer = state_store.SnapshotBuffer;
pub const InlineString = state_store.InlineString;
pub const computeTypeHash = state_store.computeTypeHash;
pub const SubprocessPoller = posix_poller.SubprocessPoller;
pub const AsyncTask = async_task.AsyncTask;
pub const lsp = lsp_client;

pub const PlatformContext = app_api.PlatformContext;
pub const ClipboardImage = app_api.ClipboardImage;
pub const setTestClipboardImage = app_api.setTestClipboardImage;
pub const setTestPickedFolder = app_api.setTestPickedFolder;
pub const setTestPickedFile = app_api.setTestPickedFile;
pub const setTestSavedFile = app_api.setTestSavedFile;
pub const detectImageMimeFromPath = app_api.detectImageMimeFromPath;
pub const CursorShape = app_api.CursorShape;
pub const KeyCode = app_api.KeyCode;
pub const KeyEvent = app_api.KeyEvent;
pub const AppInitFn = app_api.AppInitFn;
pub const AppBeforeReloadFn = app_api.AppBeforeReloadFn;
pub const AppOnReloadFn = app_api.AppOnReloadFn;
pub const AppTickFn = app_api.AppTickFn;
pub const AppDeinitFn = app_api.AppDeinitFn;
pub const HotDylib = hot_dylib.HotDylib;

test {
    _ = state_store;
    _ = app_api;
    _ = plugin_abi;
    _ = plugin_sdk;
    _ = lsp_client;
    _ = posix_poller;
    _ = async_task;
    _ = fs_util;
    _ = profiler;
    _ = @import("linux/wayland_client.zig");
}
