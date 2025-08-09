package wallp

import "core:fmt"
import "core:os"
import "core:strconv"
import path "core:path/filepath"
import unicode "core:unicode/utf16"
import win "core:sys/windows"

foreign import "system:ole32.lib"
foreign import "system:user32.lib"

IUnknown	    :: win.IUnknown
IUnknown_VTable :: win.IUnknown_VTable

CLSID_DesktopWallpaper := &win.GUID{0xC2CF3110, 0x460E, 0x4FC1,
    {0xB9, 0xD0, 0x8A, 0x1C, 0x0C, 0x9C, 0xC4, 0xBD}}
IID_IDesktopWallpaper := &win.IID{0xB92B56A9, 0x8B55, 0x4E14,
    {0x9A, 0x89, 0x01, 0x99, 0xBB, 0xB6, 0xF9, 0x3B}}

IDesktopWallpaper :: struct #raw_union {
    #subtype iunknown: IUnknown,
    using lpVtbl: ^IDesktopWallpaperVtbl
}
IDesktopWallpaperVtbl :: struct {
    using IUnknownVtbl: IUnknown_VTable,
    SetWallpaper: proc "system" (
        self: ^IDesktopWallpaper,
        monitor_id: win.LPCWSTR,
        wallpaper: win.LPCWSTR,
    ) -> win.HRESULT,
    GetWallpaper: proc "system" (
        self: ^IDesktopWallpaper,
        monitor_id: win.LPCWSTR,
        wallpaper: ^win.LPCWSTR,
    ) -> win.HRESULT,
    GetMonitorDevicePathAt: proc "system" (
        self: ^IDesktopWallpaper,
        count: win.UINT,
        monitor_id: ^win.LPWSTR,
    ) -> win.HRESULT,
    GetMonitorDevicePathCount: proc "system" (
        self: ^IDesktopWallpaper,
        counter: ^win.UINT
    ) -> win.HRESULT,
    // actually, there are much more methods exists, but since they are not
    // used in this program, it just marked by `rawptr`.
    GetMonitorRECT:      rawptr,
    SetBackgroundColor:  rawptr,
    GetBackgroundColor:  rawptr,
    SetPosition:         rawptr,
    GetPosition:         rawptr,
    SetSlideshow:        rawptr,
    GetSlideshow:        rawptr,
    SetSlideshowOptions: rawptr,
    GetSlideshowOptions: rawptr,
    AdvanceSlideshow:    rawptr,
    GetStatus:           rawptr,
    Enable:              rawptr,
}

DesktopManager :: struct {
    inner: ^IDesktopWallpaper,
    monitors: []cstring16,
    monitors_len: uintptr,
}

WallpErr :: enum u8 {
    None = 0,
    InitFailed,
}

initDesktop :: proc() -> (self: DesktopManager, err: WallpErr) {
    hr := win.CoInitializeEx()
    if win.FAILED(hr) {
        fmt.eprintln("CoInitFailed")
        err = .InitFailed
        return
    }
    defer if err != nil do win.CoUninitialize()

    hr = win.CoCreateInstance(
        CLSID_DesktopWallpaper,
        nil,
        win.CLSCTX_ALL,
        IID_IDesktopWallpaper,
        auto_cast &self.inner,
    )
    if win.FAILED(hr) {
        fmt.eprintln("CoCreateInstance failed")
        err = .InitFailed
        return
    }

    monitors_len: win.UINT = 0
    hr = self.inner->GetMonitorDevicePathCount(&monitors_len)
    if win.FAILED(hr) {
        fmt.eprintln("cannot obtain monitor device count")
        err = .InitFailed
        return
    }

    self.monitors = make([]cstring16, monitors_len)
    defer if err != nil {
        for i in 0..<self.monitors_len {
            win.CoTaskMemFree(transmute([^]u16)self.monitors[i])
        }
        delete(self.monitors)
    }

    for i in 0..<monitors_len {
        monitor_id: win.LPWSTR = ---
        hr = self.inner->GetMonitorDevicePathAt(i, &monitor_id)
        if win.FAILED(hr) {
            fmt.eprintln("cannot obtain monitor device count")
            err = .InitFailed
            return
        }
        defer if err != nil do win.CoTaskMemFree(monitor_id)

        self.monitors[self.monitors_len] = transmute(cstring16)monitor_id
        self.monitors_len += 1
    }

    return
}

deinitDesktop :: proc(self: ^DesktopManager) {
    for i in 0..<self.monitors_len {
        win.CoTaskMemFree(transmute([^]u16)self.monitors[i])
    }
    delete(self.monitors)
    win.CoUninitialize()
}

main :: proc() {
    if len(os.args) < 2 {
        fmt.eprintln("ERROR: Invalid argument")
        fmt.eprintln("USAGE: wallp <list/set>")
        os.exit(1)
    }

    dm, err := initDesktop()
    if err != nil {
        os.exit(1)
    }
    defer deinitDesktop(&dm)

    switch {
    case os.args[1] == "list":
        for monitor, i in dm.monitors {
            monitor_len := len(monitor)
            monitor_utf8 := make([]u8, monitor_len)
            defer delete(monitor_utf8)

            len := unicode.decode_to_utf8(
                monitor_utf8,
                (transmute([^]u16)monitor)[0:monitor_len],
            )
            fmt.printf("%d: %s\n", i, transmute(string)(monitor_utf8[0:len]))
        }
    case os.args[1] == "set":
        if len(os.args[1:]) != 3 {
            fmt.eprintln("ERROR: Invalid argument")
            fmt.eprintln("USAGE: wallp set MONITOR WALLPAPER")
            fmt.eprintln("       MONITOR:   integer")
            fmt.eprintln("       WALLPAPER: wallpaper path")
            os.exit(1)
        }

        monitor, ok_monitor := strconv.parse_int(os.args[2])
        if !ok_monitor {
            fmt.eprintf("ERROR: %s cannot be converted into integer\n", os.args[2])
            os.exit(1)
        }
        wallpaper, ok_wallpaper := path.abs(os.args[3])
        if !ok_wallpaper {
            fmt.eprintf("ERROR: cannot make an absolute path from %s\n", os.args[3])
            os.exit(1)
        }
        defer delete(wallpaper)

        wallpaper_utf16_buf := make([]u16, len(wallpaper))
        defer delete(wallpaper_utf16_buf)

        unicode.encode_string(wallpaper_utf16_buf, wallpaper)
        wallpaper_utf16 := transmute(cstring16)(raw_data(wallpaper_utf16_buf))
        hr := dm.inner->SetWallpaper(dm.monitors[monitor], wallpaper_utf16)

        if win.FAILED(hr) {
            fmt.eprintln("ERROR: failed to change wallpaper")
            os.exit(1)
        }
    case:
        fmt.eprintln("ERROR: Invalid argument")
        fmt.eprintln("USAGE: wallp <list/set>")
        os.exit(1)
    }
}
