const std = @import("std");
const win = @import("win");
const mem = std.mem;
const unicode = std.unicode;

const Allocator = mem.Allocator;
const ArrayList = std.ArrayList;

const DesktopManager = struct {
    alloc: Allocator,
    inner: *win.IDesktopWallpaper,
    monitors: ArrayList([*:0]const u16),
    monitors_len: usize,

    const Self = @This();

    fn init(alloc: Allocator) !Self {
        var self: Self = undefined;
        self.alloc = alloc;

        var hr = win.CoInitializeEx(null, win.COINIT_APARTMENTTHREADED);
        if (win.FAILED(hr)) {
            return error.CoInitFailed;
        }
        errdefer win.CoUninitialize();

        hr = win.CoCreateInstance(
            &win.CLSID_DesktopWallpaper,
            null,
            win.CLSCTX_ALL,
            &win.IID_IDesktopWallpaper,
            @ptrCast(&self.inner),
        );
        if (win.FAILED(hr)) {
            return error.FailedCoCreateInstance;
        }

        self.monitors_len = 0; // win.UINT is 32bit, usize is 64bit
        hr = self.inner.lpVtbl.*.GetMonitorDevicePathCount.?(
            self.inner,
            @ptrCast(&self.monitors_len),
        );
        if (win.FAILED(hr)) {
            return error.FailedGetMonitorCount;
        }

        self.monitors = try ArrayList([*:0]const u16).initCapacity(
            alloc,
            self.monitors_len,
        );
        errdefer {
            for (self.monitors.items) |monitor_id| {
                win.CoTaskMemFree(@ptrCast(@constCast(monitor_id)));
            }
            self.monitors.deinit();
        }

        for (0..self.monitors_len) |i| {
            var monitor_id: [*:0]u16 = undefined;
            hr = self.inner.lpVtbl.*.GetMonitorDevicePathAt.?(
                self.inner,
                @intCast(i),
                @ptrCast(&monitor_id),
            );
            if (win.FAILED(hr)) {
                return error.FailedGetMonitorId;
            }
            errdefer win.CoTaskMemFree(@ptrCast(monitor_id));
            try self.monitors.append(monitor_id);
        }

        return self;
    }

    fn deinit(self: *Self) void {
        for (self.monitors.items) |monitor_id| {
            win.CoTaskMemFree(@ptrCast(@constCast(monitor_id)));
        }
        self.monitors.deinit();
        win.CoUninitialize();
    }

    fn listMonitors(self: Self) !void {
        for (0.., self.monitors.items) |i, monitor| {
            const len = mem.len(monitor);

            const monitor_utf8 = try unicode.utf16LeToUtf8Alloc(
                self.alloc,
                monitor[0..len],
            );
            defer self.alloc.free(monitor_utf8);
            std.debug.print("{d}: {s}\n", .{ i, monitor_utf8 });
        }
    }

    fn setWallpaper(self: Self, wallpaper: []const u8, monitor: usize) !void {
        const wallpaper_real = try std.fs.cwd().realpathAlloc(self.alloc, wallpaper);
        defer self.alloc.free(wallpaper_real);
        const wallpaper_utf16 = try unicode.utf8ToUtf16LeAllocZ(self.alloc, wallpaper_real);
        defer self.alloc.free(wallpaper_utf16);

        if (monitor >= self.monitors_len) {
            return error.MonitorOutOfBound;
        }
        const hr = self.inner.lpVtbl.*.SetWallpaper.?(
            self.inner,
            self.monitors.items[monitor],
            wallpaper_utf16,
        );
        if (win.FAILED(hr)) {
            return error.FailedToSetWallpaper;
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var zlap = try @import("zlap").Zlap(@embedFile("commands.zlap")).init(alloc);
    defer zlap.deinit();

    if (zlap.is_help) {
        std.debug.print("{s}\n", .{zlap.help_msg});
        return;
    }

    var dm = try DesktopManager.init(alloc);
    defer dm.deinit();

    if (zlap.isSubcmdActive("list")) {
        try dm.listMonitors();
    } else if (zlap.isSubcmdActive("set")) {
        const subcmd = zlap.subcommands.get("set").?;
        const monitor: usize = @intCast(subcmd.args.get("MONITOR").?.value.number);
        const wallpaper = subcmd.args.get("WALLPAPER").?.value.string;
        try dm.setWallpaper(wallpaper, monitor);
    } else {
        std.debug.print("{s}\n", .{zlap.help_msg});
    }
}
