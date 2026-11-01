//! Native Windows (Win32 + DWM Dark Titlebar + Skia Backbuffer) Window Host with live `.dll` Hot-Reloading.
//! Features 0% idle CPU sleep (`MsgWaitForMultipleObjects`), partial scissor updates on a persistent
//! Skia backbuffer surface, Win32 clipboard & file dialogs, and automated benchmark/trace support.

const std = @import("std");
const skia = @import("skia");
const app_api = @import("../app_api.zig");
const state_store = @import("../state_store.zig");
const HotDylib = @import("../hot_dylib.zig").HotDylib;
const profiler = @import("../profiler.zig");

pub const Config = struct {
    title: [*:0]const u8 = "Lightning",
    width: f64 = 1080,
    height: f64 = 700,
    dylib_path: [*:0]const u8 = "zig-out/bin/editor_app.dll",
    max_frames: ?usize = null,
    bench: bool = false,
    metrics_json_path: ?[]const u8 = null,
    trace_path: ?[]const u8 = null,
    scenario: ?[]const u8 = null,
    screenshot_path: ?[]const u8 = null,
};

// ============================================================================
// Win32 C-ABI Types, Constants & Externs (Zero @cImport)
// ============================================================================

const HWND = ?*anyopaque;
const HINSTANCE = ?*anyopaque;
const HICON = ?*anyopaque;
const HCURSOR = ?*anyopaque;
const HBRUSH = ?*anyopaque;
const HMENU = ?*anyopaque;
const HDC = ?*anyopaque;
const HGLOBAL = ?*anyopaque;
const HANDLE = ?*anyopaque;
const ATOM = u16;
const UINT = u32;
const DWORD = u32;
const WORD = u16;
const BOOL = i32;
const LONG = i32;
const WPARAM = usize;
const LPARAM = isize;
const LRESULT = isize;

const WNDPROC = *const fn (HWND, UINT, WPARAM, LPARAM) callconv(.c) LRESULT;

const WNDCLASSEXA = extern struct {
    cbSize: UINT = @sizeOf(WNDCLASSEXA),
    style: UINT = 0,
    lpfnWndProc: WNDPROC,
    cbClsExtra: i32 = 0,
    cbWndExtra: i32 = 0,
    hInstance: HINSTANCE = null,
    hIcon: HICON = null,
    hCursor: HCURSOR = null,
    hbrBackground: HBRUSH = null,
    lpszMenuName: ?[*:0]const u8 = null,
    lpszClassName: [*:0]const u8,
    hIconSm: HICON = null,
};

const POINT = extern struct {
    x: LONG = 0,
    y: LONG = 0,
};

const RECT = extern struct {
    left: LONG = 0,
    top: LONG = 0,
    right: LONG = 0,
    bottom: LONG = 0,
};

const MSG = extern struct {
    hwnd: HWND = null,
    message: UINT = 0,
    wParam: WPARAM = 0,
    lParam: LPARAM = 0,
    time: DWORD = 0,
    pt: POINT = .{},
    lPrivate: DWORD = 0,
};

const BITMAPINFOHEADER = extern struct {
    biSize: DWORD = @sizeOf(BITMAPINFOHEADER),
    biWidth: LONG = 0,
    biHeight: LONG = 0,
    biPlanes: WORD = 1,
    biBitCount: WORD = 32,
    biCompression: DWORD = 0, // BI_RGB = 0
    biSizeImage: DWORD = 0,
    biXPelsPerMeter: LONG = 0,
    biYPelsPerMeter: LONG = 0,
    biClrUsed: DWORD = 0,
    biClrImportant: DWORD = 0,
};

const BITMAPINFO = extern struct {
    bmiHeader: BITMAPINFOHEADER = .{},
    bmiColors: [1]u32 = .{0},
};

const OPENFILENAMEA = extern struct {
    lStructSize: DWORD = @sizeOf(OPENFILENAMEA),
    hwndOwner: HWND = null,
    hInstance: HINSTANCE = null,
    lpstrFilter: ?[*:0]const u8 = null,
    lpstrCustomFilter: ?[*]u8 = null,
    nMaxCustFilter: DWORD = 0,
    nFilterIndex: DWORD = 1,
    lpstrFile: [*]u8,
    nMaxFile: DWORD,
    lpstrFileTitle: ?[*]u8 = null,
    nMaxFileTitle: DWORD = 0,
    lpstrInitialDir: ?[*:0]const u8 = null,
    lpstrTitle: ?[*:0]const u8 = null,
    Flags: DWORD = 0,
    nFileOffset: WORD = 0,
    nFileExtension: WORD = 0,
    lpstrDefExt: ?[*:0]const u8 = null,
    lCustData: LPARAM = 0,
    lpfnHook: ?*const anyopaque = null,
    lpTemplateName: ?[*:0]const u8 = null,
    pvReserved: ?*anyopaque = null,
    dwReserved: DWORD = 0,
    FlagsEx: DWORD = 0,
};

const CS_HREDRAW: UINT = 0x0002;
const CS_VREDRAW: UINT = 0x0001;
const CS_DBLCLKS: UINT = 0x0008;

const WS_OVERLAPPEDWINDOW: DWORD = 0x00CF0000;
const WS_VISIBLE: DWORD = 0x10000000;
const CW_USEDEFAULT: i32 = @bitCast(@as(u32, 0x80000000));
const SW_MAXIMIZE: i32 = 3;
const SW_SHOW: i32 = 5;
const SW_MINIMIZE: i32 = 6;
const SW_RESTORE: i32 = 9;
const SWP_NOSIZE: UINT = 0x0001;
const SWP_NOMOVE: UINT = 0x0002;
const SWP_NOZORDER: UINT = 0x0004;
const SWP_NOACTIVATE: UINT = 0x0010;
const SWP_FRAMECHANGED: UINT = 0x0020;
const PM_REMOVE: UINT = 0x0001;
const QS_ALLINPUT: DWORD = 0x04FF;

const WM_DESTROY: UINT = 0x0002;
const WM_SIZE: UINT = 0x0005;
const WM_PAINT: UINT = 0x000F;
const WM_CLOSE: UINT = 0x0010;
const WM_QUIT: UINT = 0x0012;
const WM_ERASEBKGND: UINT = 0x0014;
const WM_SETCURSOR: UINT = 0x0020;
const WM_NCCALCSIZE: UINT = 0x0083;
const WM_NCHITTEST: UINT = 0x0084;
const WM_KEYDOWN: UINT = 0x0100;
const WM_KEYUP: UINT = 0x0101;
const WM_CHAR: UINT = 0x0102;
const WM_SYSKEYDOWN: UINT = 0x0104;
const WM_COMMAND: UINT = 0x0111;
const WM_MOUSEMOVE: UINT = 0x0200;

const HTCLIENT: LRESULT = 1;
const HTCAPTION: LRESULT = 2;
const HTLEFT: LRESULT = 10;
const HTRIGHT: LRESULT = 11;
const HTTOP: LRESULT = 12;
const HTTOPLEFT: LRESULT = 13;
const HTTOPRIGHT: LRESULT = 14;
const HTBOTTOM: LRESULT = 15;
const HTBOTTOMLEFT: LRESULT = 16;
const HTBOTTOMRIGHT: LRESULT = 17;

const SM_CXSIZEFRAME: i32 = 32;
const SM_CXPADDEDBORDER: i32 = 92;
const TPM_LEFTALIGN: UINT = 0x0000;
const TPM_TOPALIGN: UINT = 0x0000;

const NCCALCSIZE_PARAMS = extern struct {
    rgrc: [3]RECT,
    lppos: ?*anyopaque = null,
};

const MARGINS = extern struct {
    cxLeftWidth: i32 = 0,
    cxRightWidth: i32 = 0,
    cyTopHeight: i32 = 0,
    cyBottomHeight: i32 = 0,
};

const MF_STRING: UINT = 0x0000;
const MF_POPUP: UINT = 0x0010;
const MF_SEPARATOR: UINT = 0x0800;

const IDM_FILE_OPEN_WORKSPACE: usize = 1001;
const IDM_FILE_OPEN_FILE: usize = 1002;
const IDM_FILE_SAVE: usize = 1003;
const IDM_FILE_SAVE_AS: usize = 1004;
const IDM_FILE_CLOSE_TAB: usize = 1005;
const IDM_FILE_EXIT: usize = 1006;

const IDM_EDIT_UNDO: usize = 1010;
const IDM_EDIT_REDO: usize = 1011;
const IDM_EDIT_CUT: usize = 1012;
const IDM_EDIT_COPY: usize = 1013;
const IDM_EDIT_PASTE: usize = 1014;
const IDM_EDIT_SELECT_ALL: usize = 1015;
const IDM_EDIT_FIND: usize = 1016;
const IDM_EDIT_FIND_WS: usize = 1017;

const IDM_VIEW_PALETTE: usize = 1020;
const IDM_VIEW_SIDEBAR: usize = 1021;
const IDM_VIEW_TERMINAL: usize = 1022;
const IDM_VIEW_SPLIT: usize = 1023;
const IDM_VIEW_AGENT_PANEL: usize = 1024;
const IDM_VIEW_NEW_TERMINAL: usize = 1025;
const IDM_VIEW_NEW_AGENT: usize = 1026;
const WM_LBUTTONDOWN: UINT = 0x0201;
const WM_LBUTTONUP: UINT = 0x0202;
const WM_LBUTTONDBLCLK: UINT = 0x0203;
const WM_RBUTTONDOWN: UINT = 0x0204;
const WM_RBUTTONUP: UINT = 0x0205;
const WM_MOUSEWHEEL: UINT = 0x020A;
const WM_MOUSEHWHEEL: UINT = 0x020E;
const WM_DPICHANGED: UINT = 0x02E0;

const VK_BACK: WPARAM = 0x08;
const VK_TAB: WPARAM = 0x09;
const VK_RETURN: WPARAM = 0x0D;
const VK_SHIFT: i32 = 0x10;
const VK_CONTROL: i32 = 0x11;
const VK_MENU: i32 = 0x12; // Alt
const VK_ESCAPE: WPARAM = 0x1B;
const VK_SPACE: WPARAM = 0x20;
const VK_PRIOR: WPARAM = 0x21; // Page Up
const VK_NEXT: WPARAM = 0x22; // Page Down
const VK_END: WPARAM = 0x23;
const VK_HOME: WPARAM = 0x24;
const VK_LEFT: WPARAM = 0x25;
const VK_UP: WPARAM = 0x26;
const VK_RIGHT: WPARAM = 0x27;
const VK_DOWN: WPARAM = 0x28;
const VK_DELETE: WPARAM = 0x2E;
const VK_F5: WPARAM = 0x74;
const VK_F9: WPARAM = 0x78;
const VK_F10: WPARAM = 0x79;
const VK_F11: WPARAM = 0x7A;
const VK_OEM_PLUS: WPARAM = 0xBB;
const VK_OEM_MINUS: WPARAM = 0xBD;
const VK_OEM_2: WPARAM = 0xBF; // /?
const VK_OEM_4: WPARAM = 0xDB; // [{
const VK_OEM_5: WPARAM = 0xDC; // \|
const VK_OEM_6: WPARAM = 0xDD; // ]}

const CF_TEXT: UINT = 1;
const GMEM_MOVEABLE: UINT = 0x0002;
const SRCCOPY: DWORD = 0x00CC0020;
const DIB_RGB_COLORS: UINT = 0;

const OFN_PATHMUSTEXIST: DWORD = 0x00000800;
const OFN_FILEMUSTEXIST: DWORD = 0x00001000;
const OFN_OVERWRITEPROMPT: DWORD = 0x00000002;
const OFN_NOCHANGEDIR: DWORD = 0x00000008;

extern "kernel32" fn GetModuleHandleA(lpModuleName: ?[*:0]const u8) callconv(.c) HINSTANCE;
extern "kernel32" fn GlobalAlloc(uFlags: UINT, dwBytes: usize) callconv(.c) HGLOBAL;
extern "kernel32" fn GlobalLock(hMem: HGLOBAL) callconv(.c) ?[*]u8;
extern "kernel32" fn GlobalUnlock(hMem: HGLOBAL) callconv(.c) BOOL;
extern "kernel32" fn GlobalFree(hMem: HGLOBAL) callconv(.c) HGLOBAL;
extern "kernel32" fn Sleep(dwMilliseconds: DWORD) callconv(.c) void;

extern "user32" fn RegisterClassExA(lpWndClass: *const WNDCLASSEXA) callconv(.c) ATOM;
extern "user32" fn CreateWindowExA(
    dwExStyle: DWORD,
    lpClassName: [*:0]const u8,
    lpWindowName: [*:0]const u8,
    dwStyle: DWORD,
    X: i32,
    Y: i32,
    nWidth: i32,
    nHeight: i32,
    hWndParent: HWND,
    hMenu: HMENU,
    hInstance: HINSTANCE,
    lpParam: ?*anyopaque,
) callconv(.c) HWND;
extern "user32" fn DestroyWindow(hWnd: HWND) callconv(.c) BOOL;
extern "user32" fn ShowWindow(hWnd: HWND, nCmdShow: i32) callconv(.c) BOOL;
extern "user32" fn UpdateWindow(hWnd: HWND) callconv(.c) BOOL;
extern "user32" fn PeekMessageA(lpMsg: *MSG, hWnd: HWND, wMsgFilterMin: UINT, wMsgFilterMax: UINT, wRemoveMsg: UINT) callconv(.c) BOOL;
extern "user32" fn TranslateMessage(lpMsg: *const MSG) callconv(.c) BOOL;
extern "user32" fn DispatchMessageA(lpMsg: *const MSG) callconv(.c) LRESULT;
extern "user32" fn DefWindowProcA(hWnd: HWND, Msg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(.c) LRESULT;
extern "user32" fn PostQuitMessage(nExitCode: i32) callconv(.c) void;
extern "user32" fn GetClientRect(hWnd: HWND, lpRect: *RECT) callconv(.c) BOOL;
extern "user32" fn GetDC(hWnd: HWND) callconv(.c) HDC;
extern "user32" fn ReleaseDC(hWnd: HWND, hDC: HDC) callconv(.c) i32;
extern "user32" fn ValidateRect(hWnd: HWND, lpRect: ?*const RECT) callconv(.c) BOOL;
extern "user32" fn GetKeyState(nVirtKey: i32) callconv(.c) i16;
extern "user32" fn SetCapture(hWnd: HWND) callconv(.c) HWND;
extern "user32" fn ReleaseCapture() callconv(.c) BOOL;
extern "user32" fn LoadCursorA(hInstance: HINSTANCE, lpCursorName: ?*const anyopaque) callconv(.c) HCURSOR;
extern "user32" fn SetCursor(hCursor: HCURSOR) callconv(.c) HCURSOR;
extern "user32" fn OpenClipboard(hWndNewOwner: HWND) callconv(.c) BOOL;
extern "user32" fn CloseClipboard() callconv(.c) BOOL;
extern "user32" fn EmptyClipboard() callconv(.c) BOOL;
extern "user32" fn GetClipboardData(uFormat: UINT) callconv(.c) HANDLE;
extern "user32" fn SetClipboardData(uFormat: UINT, hMem: HANDLE) callconv(.c) HANDLE;
extern "user32" fn MsgWaitForMultipleObjects(nCount: DWORD, pHandles: ?*const HANDLE, fWaitAll: BOOL, dwMilliseconds: DWORD, dwWakeMask: DWORD) callconv(.c) DWORD;
extern "user32" fn GetDpiForWindow(hwnd: HWND) callconv(.c) UINT;
extern "user32" fn CreateMenu() callconv(.c) HMENU;
extern "user32" fn CreatePopupMenu() callconv(.c) HMENU;
extern "user32" fn AppendMenuA(hMenu: HMENU, uFlags: UINT, uIDNewItem: usize, lpNewItem: ?[*:0]const u8) callconv(.c) BOOL;
extern "user32" fn SetMenu(hWnd: HWND, hMenu: HMENU) callconv(.c) BOOL;
extern "user32" fn TrackPopupMenu(hMenu: HMENU, uFlags: UINT, x: i32, y: i32, nReserved: i32, hWnd: HWND, prcRect: ?*const RECT) callconv(.c) BOOL;
extern "user32" fn IsZoomed(hWnd: HWND) callconv(.c) BOOL;
extern "user32" fn GetSystemMetricsForDpi(nIndex: i32, dpi: UINT) callconv(.c) i32;
extern "user32" fn ScreenToClient(hWnd: HWND, lpPoint: *POINT) callconv(.c) BOOL;
extern "user32" fn ClientToScreen(hWnd: HWND, lpPoint: *POINT) callconv(.c) BOOL;
extern "user32" fn SetWindowPos(hWnd: HWND, hWndInsertAfter: HWND, X: i32, Y: i32, cx: i32, cy: i32, uFlags: UINT) callconv(.c) BOOL;

extern "gdi32" fn StretchDIBits(
    hdc: HDC,
    xDest: i32,
    yDest: i32,
    DestWidth: i32,
    DestHeight: i32,
    xSrc: i32,
    ySrc: i32,
    SrcWidth: i32,
    SrcHeight: i32,
    lpBits: ?*const anyopaque,
    lpbmi: *const BITMAPINFO,
    iUsage: UINT,
    rop: DWORD,
) callconv(.c) i32;

extern "dwmapi" fn DwmSetWindowAttribute(hwnd: HWND, dwAttribute: DWORD, pvAttribute: *const anyopaque, cbAttribute: DWORD) callconv(.c) i32;
extern "dwmapi" fn DwmExtendFrameIntoClientArea(hwnd: HWND, pMarInset: *const MARGINS) callconv(.c) i32;
extern "comdlg32" fn GetOpenFileNameA(lpofn: *OPENFILENAMEA) callconv(.c) BOOL;
extern "comdlg32" fn GetSaveFileNameA(lpofn: *OPENFILENAMEA) callconv(.c) BOOL;

const GUID = extern struct {
    Data1: u32,
    Data2: u16,
    Data3: u16,
    Data4: [8]u8,
};

const CLSID_FileOpenDialog = GUID{
    .Data1 = 0xDC1C5A9C,
    .Data2 = 0xE88A,
    .Data3 = 0x4DDE,
    .Data4 = .{ 0xA5, 0xA1, 0x60, 0xF8, 0x2A, 0x20, 0xAE, 0xF7 },
};

const IID_IFileOpenDialog = GUID{
    .Data1 = 0xD57C7288,
    .Data2 = 0xD4AD,
    .Data3 = 0x4768,
    .Data4 = .{ 0xBE, 0x02, 0x9D, 0x96, 0x95, 0x32, 0xD9, 0x60 },
};

const IShellItemVtbl = extern struct {
    QueryInterface: *const anyopaque,
    AddRef: *const anyopaque,
    Release: *const fn (self: *IShellItem) callconv(.c) u32,
    BindToHandler: *const anyopaque,
    GetParent: *const anyopaque,
    GetDisplayName: *const fn (self: *IShellItem, sigdnName: DWORD, ppszName: *?[*:0]u16) callconv(.c) i32,
    GetAttributes: *const anyopaque,
    Compare: *const anyopaque,
};

const IShellItem = extern struct {
    lpVtbl: *const IShellItemVtbl,
};

const IFileOpenDialogVtbl = extern struct {
    QueryInterface: *const anyopaque,
    AddRef: *const anyopaque,
    Release: *const fn (self: *IFileOpenDialog) callconv(.c) u32,
    Show: *const fn (self: *IFileOpenDialog, hwndOwner: HWND) callconv(.c) i32,
    SetFileTypes: *const anyopaque,
    SetFileTypeIndex: *const anyopaque,
    GetFileTypeIndex: *const anyopaque,
    Advise: *const anyopaque,
    Unadvise: *const anyopaque,
    SetOptions: *const fn (self: *IFileOpenDialog, fos: DWORD) callconv(.c) i32,
    GetOptions: *const fn (self: *IFileOpenDialog, pfos: *DWORD) callconv(.c) i32,
    SetDefaultFolder: *const anyopaque,
    SetFolder: *const anyopaque,
    GetFolder: *const anyopaque,
    GetCurrentSelection: *const anyopaque,
    SetFileName: *const anyopaque,
    GetFileName: *const anyopaque,
    SetTitle: *const fn (self: *IFileOpenDialog, pszTitle: [*:0]const u16) callconv(.c) i32,
    SetOkButtonLabel: *const anyopaque,
    SetFileNameLabel: *const anyopaque,
    GetResult: *const fn (self: *IFileOpenDialog, ppsi: *?*IShellItem) callconv(.c) i32,
};

const IFileOpenDialog = extern struct {
    lpVtbl: *const IFileOpenDialogVtbl,
};

const BROWSEINFOA = extern struct {
    hwndOwner: HWND = null,
    pidlRoot: ?*const anyopaque = null,
    pszDisplayName: ?[*]u8 = null,
    lpszTitle: ?[*:0]const u8 = null,
    ulFlags: UINT = 0,
    lpfn: ?*const anyopaque = null,
    lParam: LPARAM = 0,
    iImage: i32 = 0,
};

const COINIT_APARTMENTTHREADED: DWORD = 0x2;
const CLSCTX_INPROC_SERVER: DWORD = 0x1;
const FOS_NOCHANGEDIR: DWORD = 0x00000008;
const FOS_PICKFOLDERS: DWORD = 0x00000020;
const FOS_FORCEFILESYSTEM: DWORD = 0x00000040;
const SIGDN_FILESYSPATH: DWORD = 0x80058000;
const BIF_RETURNONLYFSDIRS: UINT = 0x00000001;
const BIF_EDITBOX: UINT = 0x00000010;
const BIF_NEWDIALOGSTYLE: UINT = 0x00000040;

extern "ole32" fn CoInitializeEx(pvReserved: ?*anyopaque, dwCoInit: DWORD) callconv(.c) i32;
extern "ole32" fn CoCreateInstance(
    rclsid: *const GUID,
    pUnkOuter: ?*anyopaque,
    dwClsContext: DWORD,
    riid: *const GUID,
    ppv: *?*anyopaque,
) callconv(.c) i32;
extern "ole32" fn CoTaskMemFree(pv: ?*anyopaque) callconv(.c) void;
extern "shell32" fn SHBrowseForFolderA(lpbi: *BROWSEINFOA) callconv(.c) ?*anyopaque;
extern "shell32" fn SHGetPathFromIDListA(pidl: ?*const anyopaque, pszPath: [*]u8) callconv(.c) BOOL;

const Win32EventState = struct {
    ctx: *app_api.PlatformContext,
    hwnd: HWND = null,
    file_menu: HMENU = null,
    edit_menu: HMENU = null,
    view_menu: HMENU = null,
    pending_window_action: u32 = 0,
    pending_action_x: f32 = 0,
    pending_action_y: f32 = 0,
    quit_requested: bool = false,
    had_event: bool = false,
    saw_left_down: bool = false,
    saw_left_up: bool = false,
    saw_right_down: bool = false,
    saw_right_up: bool = false,
    mouse_down: bool = false,
    right_mouse_down: bool = false,
    current_cursor: HCURSOR = null,
};

var g_win32_state: ?*Win32EventState = null;

fn makeIntResource(id: u16) ?*const anyopaque {
    return @ptrFromInt(@as(usize, id));
}

fn applyWin32CursorShape(shape: app_api.CursorShape) void {
    // Standard Win32 IDC_* resource IDs
    const idc: u16 = switch (shape) {
        .arrow => 32512, // IDC_ARROW
        .ibeam => 32513, // IDC_IBEAM
        .crosshair => 32515, // IDC_CROSS
        .resize_ew => 32644, // IDC_SIZEWE
        .resize_ns => 32645, // IDC_SIZENS
        .not_allowed => 32648, // IDC_NO
        .pointing_hand, .grab, .grabbing => 32649, // IDC_HAND
    };
    const hcur = LoadCursorA(null, makeIntResource(idc));
    if (g_win32_state) |st| {
        st.current_cursor = hcur;
    }
    if (hcur != null) {
        _ = SetCursor(hcur);
    }
}

fn isKeyDown(vk: i32) bool {
    return (GetKeyState(vk) & @as(i16, @bitCast(@as(u16, 0x8000)))) != 0;
}

fn handleWin32KeyDown(ctx: *app_api.PlatformContext, vk: WPARAM) bool {
    const shift = isKeyDown(VK_SHIFT);
    const ctrl = isKeyDown(VK_CONTROL);
    const alt = isKeyDown(VK_MENU);
    // On Windows, map Ctrl to `cmd` so standard shortcuts (Ctrl+S, Ctrl+P, Ctrl+F, Ctrl+Z, etc.) work identically
    const cmd = ctrl;

    const mapped_key: app_api.KeyCode = switch (vk) {
        VK_LEFT => .left,
        VK_RIGHT => .right,
        VK_DOWN => .down,
        VK_UP => .up,
        VK_HOME => .home,
        VK_END => .end,
        VK_PRIOR => .page_up,
        VK_NEXT => .page_down,
        VK_BACK => .backspace,
        VK_DELETE => .delete_forward,
        VK_RETURN => .enter,
        VK_TAB => .tab,
        VK_ESCAPE => .escape,
        VK_F5 => .f5,
        VK_F9 => .f9,
        VK_F10 => .f10,
        VK_F11 => .f11,
        'A' => if (cmd) .key_a else .none,
        'B' => if (cmd) .key_b else .none,
        'C' => if (cmd) .key_c else .none,
        'D' => if (cmd) .key_d else .none,
        'E' => if (cmd) .key_e else .none,
        'F' => if (cmd) .key_f else .none,
        'G' => if (cmd) .key_g else .none,
        'H' => if (cmd) .key_h else .none,
        'I' => if (cmd) .key_i else .none,
        'J' => if (cmd) .key_j else .none,
        'K' => if (cmd) .key_k else .none,
        'L' => if (cmd) .key_l else .none,
        'M' => if (cmd) .key_m else .none,
        'N' => if (cmd) .key_n else .none,
        'O' => if (cmd) .key_o else .none,
        'P' => if (cmd) .key_p else .none,
        'Q' => if (cmd) .key_q else .none,
        'R' => if (cmd) .key_r else .none,
        'S' => if (cmd) .key_s else .none,
        'T' => if (cmd) .key_t else .none,
        'U' => if (cmd) .key_u else .none,
        'V' => if (cmd) .key_v else .none,
        'W' => if (cmd) .key_w else .none,
        'X' => if (cmd) .key_x else .none,
        'Y' => if (cmd) .key_y else .none,
        'Z' => if (cmd) .key_z else .none,
        '1' => if (cmd) .key_1 else .none,
        '2' => if (cmd) .key_2 else .none,
        '6' => if (cmd) .key_6 else .none,
        VK_SPACE => if (cmd) .key_space else .none,
        VK_OEM_MINUS => if (cmd) .key_minus else .none,
        VK_OEM_2 => if (cmd) .key_slash else .none,
        VK_OEM_4 => if (cmd) .key_lbracket else .none,
        VK_OEM_5 => if (cmd) .key_backslash else .none,
        VK_OEM_6 => if (cmd) .key_rbracket else .none,
        else => .none,
    };

    if (mapped_key != .none) {
        ctx.pushKeyEvent(.{
            .key = mapped_key,
            .shift = shift,
            .cmd = cmd,
            .alt = alt,
            .ctrl = ctrl,
        });
        return true;
    }
    return false;
}

fn win32WndProc(hwnd: HWND, msg: UINT, wparam: WPARAM, lparam: LPARAM) callconv(.c) LRESULT {
    const st = g_win32_state orelse return DefWindowProcA(hwnd, msg, wparam, lparam);
    const scale: f32 = if (st.ctx.dpi_scale > 0.0) st.ctx.dpi_scale else 1.0;

    switch (msg) {
        WM_CLOSE => {
            st.quit_requested = true;
            PostQuitMessage(0);
            return 0;
        },
        WM_DESTROY => {
            st.quit_requested = true;
            PostQuitMessage(0);
            return 0;
        },
        WM_ERASEBKGND => return 1,
        WM_PAINT => {
            _ = ValidateRect(hwnd, null);
            st.ctx.force_full_redraw = true;
            st.had_event = true;
            return 0;
        },
        WM_SIZE, WM_DPICHANGED => {
            st.ctx.force_full_redraw = true;
            st.had_event = true;
            return 0;
        },
        WM_NCCALCSIZE => {
            if (wparam != 0) {
                if (IsZoomed(hwnd) != 0 and lparam != 0) {
                    const params: *NCCALCSIZE_PARAMS = @ptrFromInt(@as(usize, @bitCast(lparam)));
                    const dpi = GetDpiForWindow(hwnd);
                    const pad = GetSystemMetricsForDpi(SM_CXSIZEFRAME, dpi) + GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi);
                    params.rgrc[0].left += pad;
                    params.rgrc[0].top += pad;
                    params.rgrc[0].right -= pad;
                    params.rgrc[0].bottom -= pad;
                }
                return 0;
            }
            return DefWindowProcA(hwnd, msg, wparam, lparam);
        },
        WM_NCHITTEST => {
            const sx: i16 = @truncate(@as(isize, lparam));
            const sy: i16 = @truncate(@as(isize, lparam >> 16));
            var pt = POINT{ .x = sx, .y = sy };
            _ = ScreenToClient(hwnd, &pt);
            var rc: RECT = .{};
            _ = GetClientRect(hwnd, &rc);
            const w_px = rc.right - rc.left;
            const h_px = rc.bottom - rc.top;

            if (IsZoomed(hwnd) == 0) {
                const border: i32 = @max(5, @as(i32, @intFromFloat(@round(6.0 * scale))));
                const corner: i32 = border * 2;
                const on_left = pt.x < border;
                const on_right = pt.x >= w_px - border;
                const on_top = pt.y < border;
                const on_bottom = pt.y >= h_px - border;

                if (on_top and pt.x < corner) return HTTOPLEFT;
                if (on_top and pt.x >= w_px - corner) return HTTOPRIGHT;
                if (on_bottom and pt.x < corner) return HTBOTTOMLEFT;
                if (on_bottom and pt.x >= w_px - corner) return HTBOTTOMRIGHT;
                if (on_left) return HTLEFT;
                if (on_right) return HTRIGHT;
                if (on_top) return HTTOP;
                if (on_bottom) return HTBOTTOM;
            }

            const lx = @as(f32, @floatFromInt(pt.x)) / scale;
            const ly = @as(f32, @floatFromInt(pt.y)) / scale;
            const win_w = @as(f32, @floatFromInt(w_px)) / scale;

            if (ly >= 0.0 and ly < 36.0) {
                // Left File/Edit/View menu items (`0..144`), center search pill, and right caption buttons (`win_w - 138..win_w`) remain interactive client areas
                const pill_left = (win_w - 300.0) * 0.5;
                const pill_right = (win_w + 300.0) * 0.5;
                if (lx < 144.0 or (lx >= pill_left and lx <= pill_right) or lx >= win_w - 138.0) {
                    return HTCLIENT;
                }
                return HTCAPTION;
            }
            return HTCLIENT;
        },
        WM_SETCURSOR => {
            if ((lparam & 0xFFFF) == 1 and st.current_cursor != null) { // HTCLIENT == 1
                _ = SetCursor(st.current_cursor);
                return 1;
            }
            return DefWindowProcA(hwnd, msg, wparam, lparam);
        },
        WM_MOUSEMOVE => {
            const x_px: i16 = @truncate(@as(isize, lparam));
            const y_px: i16 = @truncate(@as(isize, lparam >> 16));
            st.ctx.mouse_x = @as(f32, @floatFromInt(x_px)) / scale;
            st.ctx.mouse_y = @as(f32, @floatFromInt(y_px)) / scale;
            st.ctx.mouse_shift = isKeyDown(VK_SHIFT);
            st.had_event = true;
            return 0;
        },
        WM_LBUTTONDOWN, WM_LBUTTONDBLCLK => {
            const x_px: i16 = @truncate(@as(isize, lparam));
            const y_px: i16 = @truncate(@as(isize, lparam >> 16));
            st.ctx.mouse_x = @as(f32, @floatFromInt(x_px)) / scale;
            st.ctx.mouse_y = @as(f32, @floatFromInt(y_px)) / scale;
            st.ctx.mouse_shift = isKeyDown(VK_SHIFT);
            st.ctx.mouse_click_count = if (msg == WM_LBUTTONDBLCLK) 2 else 1;
            st.saw_left_down = true;
            st.mouse_down = true;
            st.had_event = true;
            _ = SetCapture(hwnd);
            return 0;
        },
        WM_LBUTTONUP => {
            const x_px: i16 = @truncate(@as(isize, lparam));
            const y_px: i16 = @truncate(@as(isize, lparam >> 16));
            st.ctx.mouse_x = @as(f32, @floatFromInt(x_px)) / scale;
            st.ctx.mouse_y = @as(f32, @floatFromInt(y_px)) / scale;
            st.saw_left_up = true;
            st.mouse_down = false;
            st.had_event = true;
            _ = ReleaseCapture();
            return 0;
        },
        WM_RBUTTONDOWN => {
            const x_px: i16 = @truncate(@as(isize, lparam));
            const y_px: i16 = @truncate(@as(isize, lparam >> 16));
            st.ctx.mouse_x = @as(f32, @floatFromInt(x_px)) / scale;
            st.ctx.mouse_y = @as(f32, @floatFromInt(y_px)) / scale;
            st.saw_right_down = true;
            st.right_mouse_down = true;
            st.had_event = true;
            return 0;
        },
        WM_RBUTTONUP => {
            const x_px: i16 = @truncate(@as(isize, lparam));
            const y_px: i16 = @truncate(@as(isize, lparam >> 16));
            st.ctx.mouse_x = @as(f32, @floatFromInt(x_px)) / scale;
            st.ctx.mouse_y = @as(f32, @floatFromInt(y_px)) / scale;
            st.saw_right_up = true;
            st.right_mouse_down = false;
            st.had_event = true;
            return 0;
        },
        WM_MOUSEWHEEL => {
            const delta: i16 = @bitCast(@as(u16, @truncate(wparam >> 16)));
            st.ctx.mouse_shift = isKeyDown(VK_SHIFT);
            st.ctx.scroll_dy += (@as(f32, @floatFromInt(delta)) / 120.0) * 36.0;
            st.had_event = true;
            return 0;
        },
        WM_MOUSEHWHEEL => {
            const delta: i16 = @bitCast(@as(u16, @truncate(wparam >> 16)));
            st.ctx.mouse_shift = isKeyDown(VK_SHIFT);
            st.ctx.scroll_dx -= (@as(f32, @floatFromInt(delta)) / 120.0) * 36.0;
            st.had_event = true;
            return 0;
        },
        WM_COMMAND => {
            const cmd_id: usize = wparam & 0xFFFF;
            st.had_event = true;
            st.ctx.force_full_redraw = true;
            switch (cmd_id) {
                IDM_FILE_OPEN_WORKSPACE => st.ctx.pushKeyEvent(.{ .key = .key_o, .cmd = true }),
                IDM_FILE_OPEN_FILE => st.ctx.pushKeyEvent(.{ .key = .key_p, .cmd = true }),
                IDM_FILE_SAVE => st.ctx.pushKeyEvent(.{ .key = .key_s, .cmd = true }),
                IDM_FILE_SAVE_AS => st.ctx.pushKeyEvent(.{ .key = .key_s, .cmd = true, .shift = true }),
                IDM_FILE_CLOSE_TAB => st.ctx.pushKeyEvent(.{ .key = .key_w, .cmd = true }),
                IDM_FILE_EXIT => {
                    st.quit_requested = true;
                    PostQuitMessage(0);
                },
                IDM_EDIT_UNDO => st.ctx.pushKeyEvent(.{ .key = .key_z, .cmd = true }),
                IDM_EDIT_REDO => st.ctx.pushKeyEvent(.{ .key = .key_z, .cmd = true, .shift = true }),
                IDM_EDIT_CUT => st.ctx.pushKeyEvent(.{ .key = .key_x, .cmd = true }),
                IDM_EDIT_COPY => st.ctx.pushKeyEvent(.{ .key = .key_c, .cmd = true }),
                IDM_EDIT_PASTE => st.ctx.pushKeyEvent(.{ .key = .key_v, .cmd = true }),
                IDM_EDIT_SELECT_ALL => st.ctx.pushKeyEvent(.{ .key = .key_a, .cmd = true }),
                IDM_EDIT_FIND => st.ctx.pushKeyEvent(.{ .key = .key_f, .cmd = true }),
                IDM_EDIT_FIND_WS => st.ctx.pushKeyEvent(.{ .key = .key_f, .cmd = true, .shift = true }),
                IDM_VIEW_PALETTE => st.ctx.pushKeyEvent(.{ .key = .key_p, .cmd = true, .shift = true }),
                IDM_VIEW_SIDEBAR => st.ctx.pushKeyEvent(.{ .key = .key_b, .cmd = true }),
                IDM_VIEW_TERMINAL => st.ctx.pushKeyEvent(.{ .key = .key_j, .cmd = true }),
                IDM_VIEW_AGENT_PANEL => st.ctx.pushKeyEvent(.{ .key = .key_j, .cmd = true, .shift = true }),
                IDM_VIEW_NEW_TERMINAL => st.ctx.pushKeyEvent(.{ .key = .key_t, .cmd = true, .shift = true }),
                IDM_VIEW_NEW_AGENT => st.ctx.pushKeyEvent(.{ .key = .key_a, .cmd = true, .shift = true }),
                IDM_VIEW_SPLIT => st.ctx.pushKeyEvent(.{ .key = .key_backslash, .cmd = true }),
                else => return DefWindowProcA(hwnd, msg, wparam, lparam),
            }
            return 0;
        },
        WM_KEYDOWN, WM_SYSKEYDOWN => {
            st.had_event = true;
            if (handleWin32KeyDown(st.ctx, wparam)) {
                return 0;
            }
            return DefWindowProcA(hwnd, msg, wparam, lparam);
        },
        WM_CHAR => {
            const ch: u32 = @truncate(wparam);
            const ctrl = isKeyDown(VK_CONTROL);
            if (!ctrl and ch >= 0x20 and ch != 0x7F) {
                var utf8_buf: [4]u8 = undefined;
                if (std.unicode.utf8Encode(@intCast(ch), &utf8_buf)) |len| {
                    st.ctx.pushTextInput(utf8_buf[0..len]);
                    st.had_event = true;
                } else |_| {}
            }
            return 0;
        },
        else => return DefWindowProcA(hwnd, msg, wparam, lparam),
    }
}

fn winGetClipboardImpl(buf_ptr: ?[*]u8, buf_cap: usize) callconv(.c) usize {
    if (OpenClipboard(null) == 0) return 0;
    defer _ = CloseClipboard();

    const hdata = GetClipboardData(CF_TEXT) orelse return 0;
    const locked = GlobalLock(hdata) orelse return 0;
    defer _ = GlobalUnlock(hdata);

    const c_str: [*:0]const u8 = @ptrCast(locked);
    const slice = std.mem.span(c_str);
    if (buf_ptr) |bp| {
        if (buf_cap > 0) {
            const n = @min(slice.len, buf_cap);
            @memcpy(bp[0..n], slice[0..n]);
        }
    }
    return slice.len;
}

fn winSetClipboardImpl(ptr: [*]const u8, len: usize) callconv(.c) void {
    if (OpenClipboard(null) == 0) return;
    defer _ = CloseClipboard();
    _ = EmptyClipboard();

    const hmem = GlobalAlloc(GMEM_MOVEABLE, len + 1) orelse return;
    const locked = GlobalLock(hmem) orelse {
        _ = GlobalFree(hmem);
        return;
    };
    @memcpy(locked[0..len], ptr[0..len]);
    locked[len] = 0;
    _ = GlobalUnlock(hmem);
    if (SetClipboardData(CF_TEXT, hmem) == null) {
        _ = GlobalFree(hmem);
    }
}

fn copyAndNormalizeWinPath(src: []const u8, buf_ptr: [*]u8, buf_cap: usize) usize {
    if (buf_cap == 0 or src.len == 0) return 0;
    var n = @min(src.len, buf_cap);
    for (0..n) |i| {
        buf_ptr[i] = if (src[i] == '\\') '/' else src[i];
    }
    while (n > 3 and buf_ptr[n - 1] == '/') {
        n -= 1;
    }
    return n;
}

fn winPickFileImpl(buf_ptr: [*]u8, buf_cap: usize) callconv(.c) usize {
    if (buf_cap == 0) return 0;
    var file_buf: [1024]u8 = @splat(0);
    var ofn = OPENFILENAMEA{
        .hwndOwner = if (g_win32_state) |st| st.hwnd else null,
        .lpstrFilter = "All Files (*.*)\x00*.*\x00",
        .lpstrFile = &file_buf,
        .nMaxFile = file_buf.len,
        .lpstrTitle = "Open File",
        .Flags = OFN_PATHMUSTEXIST | OFN_FILEMUSTEXIST | OFN_NOCHANGEDIR,
    };
    if (GetOpenFileNameA(&ofn) == 0) return 0;
    const slice = std.mem.sliceTo(&file_buf, 0);
    return copyAndNormalizeWinPath(slice, buf_ptr, buf_cap);
}

fn winPickFolderImpl(buf_ptr: [*]u8, buf_cap: usize) callconv(.c) usize {
    if (buf_cap == 0) return 0;
    const owner_hwnd: HWND = if (g_win32_state) |st| st.hwnd else null;

    // 1. Primary: Modern Windows Explorer Folder Picker (`IFileOpenDialog` with `FOS_PICKFOLDERS`)
    _ = CoInitializeEx(null, COINIT_APARTMENTTHREADED);
    var raw_dlg: ?*anyopaque = null;
    if (CoCreateInstance(&CLSID_FileOpenDialog, null, CLSCTX_INPROC_SERVER, &IID_IFileOpenDialog, &raw_dlg) >= 0) {
        if (raw_dlg) |ptr| {
            const dlg: *IFileOpenDialog = @ptrCast(@alignCast(ptr));
            defer _ = dlg.lpVtbl.Release(dlg);

            var options: DWORD = 0;
            _ = dlg.lpVtbl.GetOptions(dlg, &options);
            _ = dlg.lpVtbl.SetOptions(dlg, options | FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM | FOS_NOCHANGEDIR);

            const title_w = std.unicode.utf8ToUtf16LeStringLiteral("Open Workspace Folder");
            _ = dlg.lpVtbl.SetTitle(dlg, title_w);

            const show_hr = dlg.lpVtbl.Show(dlg, owner_hwnd);
            if (show_hr < 0) {
                // User cancelled the modern folder dialog
                return 0;
            }

            var item_opt: ?*IShellItem = null;
            if (dlg.lpVtbl.GetResult(dlg, &item_opt) >= 0) {
                if (item_opt) |item| {
                    defer _ = item.lpVtbl.Release(item);
                    var psz_path: ?[*:0]u16 = null;
                    if (item.lpVtbl.GetDisplayName(item, SIGDN_FILESYSPATH, &psz_path) >= 0) {
                        if (psz_path) |wide_z| {
                            defer CoTaskMemFree(wide_z);
                            const wide_slice = std.mem.sliceTo(wide_z, 0);
                            var utf8_buf: [1024]u8 = undefined;
                            if (std.unicode.utf16LeToUtf8(&utf8_buf, wide_slice)) |utf8_len| {
                                return copyAndNormalizeWinPath(utf8_buf[0..utf8_len], buf_ptr, buf_cap);
                            } else |_| {}
                        }
                    }
                }
            }
            return 0;
        }
    }

    // 2. Fallback: Shell `SHBrowseForFolderA` directory picker
    var display_buf: [260]u8 = @splat(0);
    var bi = BROWSEINFOA{
        .hwndOwner = owner_hwnd,
        .pszDisplayName = &display_buf,
        .lpszTitle = "Select Workspace Folder",
        .ulFlags = BIF_RETURNONLYFSDIRS | BIF_NEWDIALOGSTYLE | BIF_EDITBOX,
    };
    const pidl = SHBrowseForFolderA(&bi) orelse return 0;
    defer CoTaskMemFree(pidl);

    var path_buf: [1024]u8 = @splat(0);
    if (SHGetPathFromIDListA(pidl, &path_buf) == 0) return 0;
    const slice = std.mem.sliceTo(&path_buf, 0);
    return copyAndNormalizeWinPath(slice, buf_ptr, buf_cap);
}

fn winSaveFileImpl(buf_ptr: [*]u8, buf_cap: usize) callconv(.c) usize {
    if (buf_cap == 0) return 0;
    var file_buf: [1024]u8 = @splat(0);
    var ofn = OPENFILENAMEA{
        .hwndOwner = if (g_win32_state) |st| st.hwnd else null,
        .lpstrFilter = "All Files (*.*)\x00*.*\x00",
        .lpstrFile = &file_buf,
        .nMaxFile = file_buf.len,
        .lpstrTitle = "Save File",
        .Flags = OFN_PATHMUSTEXIST | OFN_OVERWRITEPROMPT | OFN_NOCHANGEDIR,
    };
    if (GetSaveFileNameA(&ofn) == 0) return 0;
    const slice = std.mem.sliceTo(&file_buf, 0);
    return copyAndNormalizeWinPath(slice, buf_ptr, buf_cap);
}

fn winWindowActionImpl(action: u32, x: f32, y: f32) callconv(.c) void {
    const st = g_win32_state orelse return;
    st.pending_window_action = action;
    st.pending_action_x = x;
    st.pending_action_y = y;
}

fn executePendingWindowAction(st: *Win32EventState) void {
    const action = st.pending_window_action;
    if (action == 0) return;
    st.pending_window_action = 0;

    const hwnd = st.hwnd orelse return;
    const scale: f32 = if (st.ctx.dpi_scale > 0.0) st.ctx.dpi_scale else 1.0;

    switch (action) {
        1, 2, 3 => {
            const menu = switch (action) {
                1 => st.file_menu,
                2 => st.edit_menu,
                else => st.view_menu,
            };
            if (menu != null) {
                _ = ReleaseCapture();
                st.mouse_down = false;
                var pt = POINT{
                    .x = @intFromFloat(@round(st.pending_action_x * scale)),
                    .y = @intFromFloat(@round(st.pending_action_y * scale)),
                };
                _ = ClientToScreen(hwnd, &pt);
                _ = TrackPopupMenu(menu, TPM_LEFTALIGN | TPM_TOPALIGN, pt.x, pt.y, 0, hwnd, null);
                st.ctx.force_full_redraw = true;
                st.had_event = true;
            }
        },
        10 => _ = ShowWindow(hwnd, SW_MINIMIZE),
        11 => {
            if (IsZoomed(hwnd) != 0) {
                _ = ShowWindow(hwnd, SW_RESTORE);
            } else {
                _ = ShowWindow(hwnd, SW_MAXIMIZE);
            }
        },
        12 => {
            st.quit_requested = true;
            PostQuitMessage(0);
        },
        else => {},
    }
}

fn setupWin32MenuBar(st: *Win32EventState) void {
    const file_menu = CreatePopupMenu();
    if (file_menu != null) {
        _ = AppendMenuA(file_menu, MF_STRING, IDM_FILE_OPEN_WORKSPACE, "Open Workspace Folder...\tCtrl+O");
        _ = AppendMenuA(file_menu, MF_STRING, IDM_FILE_OPEN_FILE, "Quick Open File...\tCtrl+P");
        _ = AppendMenuA(file_menu, MF_SEPARATOR, 0, null);
        _ = AppendMenuA(file_menu, MF_STRING, IDM_FILE_SAVE, "Save\tCtrl+S");
        _ = AppendMenuA(file_menu, MF_STRING, IDM_FILE_SAVE_AS, "Save As...\tCtrl+Shift+S");
        _ = AppendMenuA(file_menu, MF_SEPARATOR, 0, null);
        _ = AppendMenuA(file_menu, MF_STRING, IDM_FILE_CLOSE_TAB, "Close Editor\tCtrl+W");
        _ = AppendMenuA(file_menu, MF_SEPARATOR, 0, null);
        _ = AppendMenuA(file_menu, MF_STRING, IDM_FILE_EXIT, "E&xit\tAlt+F4");
        st.file_menu = file_menu;
    }

    const edit_menu = CreatePopupMenu();
    if (edit_menu != null) {
        _ = AppendMenuA(edit_menu, MF_STRING, IDM_EDIT_UNDO, "Undo\tCtrl+Z");
        _ = AppendMenuA(edit_menu, MF_STRING, IDM_EDIT_REDO, "Redo\tCtrl+Shift+Z");
        _ = AppendMenuA(edit_menu, MF_SEPARATOR, 0, null);
        _ = AppendMenuA(edit_menu, MF_STRING, IDM_EDIT_CUT, "Cut\tCtrl+X");
        _ = AppendMenuA(edit_menu, MF_STRING, IDM_EDIT_COPY, "Copy\tCtrl+C");
        _ = AppendMenuA(edit_menu, MF_STRING, IDM_EDIT_PASTE, "Paste\tCtrl+V");
        _ = AppendMenuA(edit_menu, MF_STRING, IDM_EDIT_SELECT_ALL, "Select All\tCtrl+A");
        _ = AppendMenuA(edit_menu, MF_SEPARATOR, 0, null);
        _ = AppendMenuA(edit_menu, MF_STRING, IDM_EDIT_FIND, "Find in File...\tCtrl+F");
        _ = AppendMenuA(edit_menu, MF_STRING, IDM_EDIT_FIND_WS, "Find in Workspace...\tCtrl+Shift+F");
        st.edit_menu = edit_menu;
    }

    const view_menu = CreatePopupMenu();
    if (view_menu != null) {
        _ = AppendMenuA(view_menu, MF_STRING, IDM_VIEW_PALETTE, "Command Palette...\tCtrl+Shift+P");
        _ = AppendMenuA(view_menu, MF_STRING, IDM_VIEW_SIDEBAR, "Toggle Primary Sidebar\tCtrl+B");
        _ = AppendMenuA(view_menu, MF_STRING, IDM_VIEW_TERMINAL, "Toggle Terminal / Bottom Panel\tCtrl+J");
        _ = AppendMenuA(view_menu, MF_STRING, IDM_VIEW_AGENT_PANEL, "Toggle Antigravity Agent Panel\tCtrl+Shift+J");
        _ = AppendMenuA(view_menu, MF_STRING, IDM_VIEW_NEW_TERMINAL, "New Terminal Buffer\tCtrl+Shift+T");
        _ = AppendMenuA(view_menu, MF_STRING, IDM_VIEW_NEW_AGENT, "New Agent Buffer\tCtrl+Shift+A");
        _ = AppendMenuA(view_menu, MF_STRING, IDM_VIEW_SPLIT, "Split Editor Right\tCtrl+\\");
        st.view_menu = view_menu;
    }
}

pub fn run(config: Config) !void {
    const font_mgr = try skia.FontMgr.initDefault();
    defer font_mgr.deinit();

    const debug_paint = try skia.Paint.init();
    defer debug_paint.deinit();
    debug_paint.setAntiAlias(true);
    debug_paint.setStyle(.stroke);
    debug_paint.setStrokeWidth(1.5);
    debug_paint.setColor(skia.Color.argb(220, 16, 185, 129));

    var host_store = state_store.StateStore.init(std.heap.c_allocator);
    defer host_store.deinit();

    var host_snapshot = state_store.SnapshotBuffer.init(std.heap.c_allocator);
    defer host_snapshot.deinit();

    var ctx = app_api.PlatformContext{
        .gr_context = null,
        .font_mgr = font_mgr.ptr,
        .host_get_clipboard = &winGetClipboardImpl,
        .host_set_clipboard = &winSetClipboardImpl,
        .host_pick_folder = &winPickFolderImpl,
        .host_pick_file = &winPickFileImpl,
        .host_save_file = &winSaveFileImpl,
        .host_window_action = &winWindowActionImpl,
    };
    ctx.bindHostStores(&host_store, &host_snapshot);

    var hot_lib = HotDylib{
        .watch_path = config.dylib_path,
    };
    defer hot_lib.unload(&ctx);

    if (!hot_lib.checkAndReload(&ctx)) {
        std.debug.print("Failed to load {s}\n", .{hot_lib.watch_path});
        return error.DylibLoadFailed;
    }

    var trace_collector = profiler.TraceCollector.init(std.heap.c_allocator, config.trace_path != null);
    defer {
        if (config.trace_path) |tp| {
            trace_collector.writeJsonFile(tp) catch {};
        }
        trace_collector.deinit();
    }

    var metrics_collector = profiler.FrameMetricsCollector.init(std.heap.c_allocator);
    defer {
        if (config.bench) {
            metrics_collector.printSummary();
        }
        if (config.metrics_json_path) |mp| {
            metrics_collector.writeJsonFile(mp) catch {};
        }
        metrics_collector.deinit();
    }

    const scenario = if (config.scenario) |s| profiler.ScenarioKind.fromString(s) else .none;
    const effective_max_frames: ?usize = config.max_frames orelse if (config.bench) 300 else null;

    const hinstance = GetModuleHandleA(null);
    const class_name: [*:0]const u8 = "LightningSkiaWindowClass";
    var wc = WNDCLASSEXA{
        .style = CS_HREDRAW | CS_VREDRAW | CS_DBLCLKS,
        .lpfnWndProc = &win32WndProc,
        .hInstance = hinstance,
        .hCursor = LoadCursorA(null, makeIntResource(32512)),
        .lpszClassName = class_name,
    };
    _ = RegisterClassExA(&wc);

    var event_state = Win32EventState{
        .ctx = &ctx,
        .current_cursor = wc.hCursor,
    };
    g_win32_state = &event_state;
    defer g_win32_state = null;

    const init_w: i32 = @intFromFloat(config.width);
    const init_h: i32 = @intFromFloat(config.height);
    const hwnd = CreateWindowExA(
        0,
        class_name,
        config.title,
        WS_OVERLAPPEDWINDOW | WS_VISIBLE,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        init_w,
        init_h,
        null,
        null,
        hinstance,
        null,
    ) orelse return error.WindowCreationFailed;
    defer _ = DestroyWindow(hwnd);
    event_state.hwnd = hwnd;

    // Enable Windows 10/11 dark immersive frame, rounded corners (DWMWA_WINDOW_CORNER_PREFERENCE = 33, DWMWCP_ROUND = 2),
    // and custom frameless titlebar shadow (`DwmExtendFrameIntoClientArea` + `SWP_FRAMECHANGED`).
    const dark_mode: BOOL = 1;
    _ = DwmSetWindowAttribute(hwnd, 20, &dark_mode, @sizeOf(BOOL));
    const corner_pref: DWORD = 2; // DWMWCP_ROUND
    _ = DwmSetWindowAttribute(hwnd, 33, &corner_pref, @sizeOf(DWORD));
    const margins = MARGINS{ .cxLeftWidth = 0, .cxRightWidth = 0, .cyTopHeight = 1, .cyBottomHeight = 0 };
    _ = DwmExtendFrameIntoClientArea(hwnd, &margins);
    setupWin32MenuBar(&event_state);
    _ = SetWindowPos(
        hwnd,
        null,
        0,
        0,
        0,
        0,
        SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE,
    );

    _ = ShowWindow(hwnd, SW_SHOW);
    _ = UpdateWindow(hwnd);

    var prev_cursor_shape: app_api.CursorShape = .arrow;
    var redraw_frames_remaining: u8 = 2;
    var prev_phys_w: i32 = 0;
    var prev_phys_h: i32 = 0;
    var pixel_storage: []u32 = &.{};
    defer if (pixel_storage.len > 0) std.heap.c_allocator.free(pixel_storage);

    var backbuffer_surface: ?skia.Surface = null;
    defer if (backbuffer_surface) |s| s.deinit();

    var last_frame_ns: u64 = profiler.nowNs();
    const min_frame_interval_ns: u64 = 16_666_667; // 60Hz frame pacing

    while (!event_state.quit_requested) {
        const t_frame_start = profiler.nowNs();

        const should_sleep = (scenario == .none) and !ctx.needs_continuous_redraw and (redraw_frames_remaining == 0) and (effective_max_frames == null);
        if (should_sleep) {
            _ = MsgWaitForMultipleObjects(0, null, 0, 400, QS_ALLINPUT);
        } else if (effective_max_frames == null and !config.bench) {
            const elapsed_ns = t_frame_start -| last_frame_ns;
            if (elapsed_ns < min_frame_interval_ns) {
                const wait_ms: DWORD = @intCast((min_frame_interval_ns - elapsed_ns) / 1_000_000);
                if (wait_ms > 0) {
                    _ = MsgWaitForMultipleObjects(0, null, 0, wait_ms, QS_ALLINPUT);
                }
            }
        }

        event_state.had_event = false;
        event_state.saw_left_down = false;
        event_state.saw_left_up = false;
        event_state.saw_right_down = false;
        event_state.saw_right_up = false;

        if (scenario != .none) {
            profiler.runScenarioTick(scenario, ctx.frame_count, &ctx);
            redraw_frames_remaining = 2;
        }

        const t_events_start = profiler.nowNs();
        var msg: MSG = .{};
        while (PeekMessageA(&msg, null, 0, 0, PM_REMOVE) != 0) {
            if (msg.message == WM_QUIT) {
                event_state.quit_requested = true;
                break;
            }
            _ = TranslateMessage(&msg);
            _ = DispatchMessageA(&msg);
        }
        const t_events_end = profiler.nowNs();
        const events_ns = t_events_end - t_events_start;
        trace_collector.record("Win32.Events", "event", t_events_start, t_events_end);

        if (event_state.quit_requested) break;
        if (effective_max_frames) |limit| {
            if (ctx.frame_count >= limit) break;
        }

        if (should_sleep or ctx.frame_count % 15 == 0) {
            if (hot_lib.checkAndReload(&ctx)) {
                ctx.force_full_redraw = true;
                redraw_frames_remaining = 2;
            }
        }

        var client_rect: RECT = .{};
        _ = GetClientRect(hwnd, &client_rect);
        const phys_w: i32 = @max(1, client_rect.right - client_rect.left);
        const phys_h: i32 = @max(1, client_rect.bottom - client_rect.top);
        const dpi = GetDpiForWindow(hwnd);
        const scale: f32 = if (dpi > 0) @as(f32, @floatFromInt(dpi)) / 96.0 else 1.0;

        ctx.dpi_scale = scale;
        ctx.width = @as(f32, @floatFromInt(phys_w)) / scale;
        ctx.height = @as(f32, @floatFromInt(phys_h)) / scale;

        const size_changed = (phys_w != prev_phys_w) or (phys_h != prev_phys_h) or (backbuffer_surface == null);
        if (size_changed) {
            if (backbuffer_surface) |old_s| old_s.deinit();
            if (pixel_storage.len > 0) std.heap.c_allocator.free(pixel_storage);

            const total_pixels: usize = @intCast(phys_w * phys_h);
            pixel_storage = try std.heap.c_allocator.alloc(u32, total_pixels);
            @memset(pixel_storage, 0xFF0B0F19);

            const info = skia.ImageInfo.initBgra8888Premul(phys_w, phys_h);
            backbuffer_surface = try skia.Surface.initRasterDirect(
                info,
                @ptrCast(pixel_storage.ptr),
                @as(usize, @intCast(phys_w)) * @sizeOf(u32),
            );
            ctx.force_full_redraw = true;
            redraw_frames_remaining = 4;
            prev_phys_w = phys_w;
            prev_phys_h = phys_h;
        } else if (event_state.had_event or ctx.text_input_len > 0 or ctx.key_event_count > 0) {
            redraw_frames_remaining = @max(redraw_frames_remaining, 2);
        }

        if (redraw_frames_remaining > 0) {
            redraw_frames_remaining -= 1;
        }

        ctx.mouse_down = event_state.mouse_down or event_state.saw_left_down;
        ctx.mouse_pressed = event_state.saw_left_down;
        ctx.mouse_released = event_state.saw_left_up;
        ctx.right_mouse_down = event_state.right_mouse_down or event_state.saw_right_down;
        ctx.right_mouse_pressed = event_state.saw_right_down;
        ctx.right_mouse_released = event_state.saw_right_up;

        const backbuffer = backbuffer_surface.?;
        const back_canvas = backbuffer.canvas();
        _ = back_canvas.save();
        back_canvas.scale(ctx.dpi_scale, ctx.dpi_scale);

        ctx.canvas = back_canvas.ptr;
        ctx.cursor_shape = .arrow;
        ctx.phase_input_us = 0;
        ctx.phase_paint_us = 0;

        const t_tick_start = profiler.nowNs();
        profiler.signpostStart(.app_tick, @intCast(ctx.frame_count));
        const did_paint = if (hot_lib.app_tick) |tick_fn| tick_fn(&ctx) else false;
        profiler.signpostEnd(.app_tick, @intCast(ctx.frame_count));
        const t_tick_end = profiler.nowNs();

        if (ctx.show_dirty_overlay and did_paint) {
            back_canvas.drawRect(ctx.last_dirty_rect, debug_paint);
        }
        back_canvas.restore();

        ctx.canvas = null;
        ctx.clearFrameInput();

        if (ctx.phase_input_us > 0) {
            const input_dur_ns = @as(u64, ctx.phase_input_us) * 1000;
            trace_collector.record("Pass.input", "layout", t_tick_start, t_tick_start + input_dur_ns);
        }
        if (ctx.phase_paint_us > 0) {
            const paint_dur_ns = @as(u64, ctx.phase_paint_us) * 1000;
            trace_collector.record("Pass.paint", "render", t_tick_end - paint_dur_ns, t_tick_end);
        }

        if (ctx.cursor_shape != prev_cursor_shape) {
            prev_cursor_shape = ctx.cursor_shape;
            applyWin32CursorShape(ctx.cursor_shape);
        }

        if (event_state.pending_window_action != 0) {
            executePendingWindowAction(&event_state);
            redraw_frames_remaining = @max(redraw_frames_remaining, 2);
        }

        if (!did_paint and effective_max_frames == null) {
            last_frame_ns = profiler.nowNs();
            continue;
        }

        const t_present_start = profiler.nowNs();
        if (GetDC(hwnd)) |hdc| {
            var bmi = BITMAPINFO{
                .bmiHeader = .{
                    .biWidth = phys_w,
                    // Negative height indicates top-down DIB matching Skia's row order
                    .biHeight = -phys_h,
                    .biPlanes = 1,
                    .biBitCount = 32,
                    .biCompression = 0,
                },
            };
            _ = StretchDIBits(
                hdc,
                0,
                0,
                phys_w,
                phys_h,
                0,
                0,
                phys_w,
                phys_h,
                pixel_storage.ptr,
                &bmi,
                DIB_RGB_COLORS,
                SRCCOPY,
            );
            _ = ReleaseDC(hwnd, hdc);
        }
        const t_present_end = profiler.nowNs();
        trace_collector.record("Win32.StretchDIBits", "gpu", t_present_start, t_present_end);
        last_frame_ns = t_present_end;

        const t_frame_end = profiler.nowNs();
        trace_collector.record("Frame", "frame", t_frame_start, t_frame_end);

        const total_win_area = @max(1.0, ctx.width * ctx.height);
        const dirty_area = skia.Rect.area(ctx.last_dirty_rect);
        metrics_collector.recordFrame(
            .{
                .total_ns = t_frame_end - t_frame_start,
                .events_ns = events_ns,
                .input_ns = @as(u64, ctx.phase_input_us) * 1000,
                .paint_ns = @as(u64, ctx.phase_paint_us) * 1000,
                .gpu_flush_ns = 0,
                .metal_present_ns = t_present_end - t_present_start,
                .damage_pct = @floatCast((dirty_area / total_win_area) * 100.0),
            },
            pixel_storage.len * @sizeOf(u32),
            1,
            &ctx,
        );

        ctx.frame_count += 1;
    }
}
