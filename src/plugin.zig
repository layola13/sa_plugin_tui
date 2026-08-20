const std = @import("std");
const builtin = @import("builtin");
const plugin_api = @import("plugin_api");

const Status = plugin_api.AbiStatus;

pub const Mode = enum(u32) {
    cooked = 0,
    raw = 1,
    alternate_screen = 2,
    mouse_tracking = 3,
};

pub const EventKind = enum(u32) {
    none = 0,
    byte = 1,
    resize = 2,
    eof = 3,
};

const TuiHandle = struct {
    stdin: std.fs.File,
    stdout: std.fs.File,
    rows: u16 = 24,
    cols: u16 = 80,
    raw_mode: bool = false,
    alternate_screen: bool = false,
    mouse_tracking: bool = false,
    unix_saved_termios: ?std.posix.termios = null,
    windows_saved_mode: ?u32 = null,
};

fn handleFromOpaque(value: ?*anyopaque) ?*TuiHandle {
    const ptr = value orelse return null;
    return @ptrCast(@alignCast(ptr));
}

fn querySize(handle: *TuiHandle) void {
    if (builtin.os.tag == .windows) {
        var info: std.os.windows.CONSOLE_SCREEN_BUFFER_INFO = undefined;
        if (std.os.windows.kernel32.GetConsoleScreenBufferInfo(handle.stdout.handle, &info) != 0) {
            const width = @as(i32, info.srWindow.Right) - @as(i32, info.srWindow.Left) + 1;
            const height = @as(i32, info.srWindow.Bottom) - @as(i32, info.srWindow.Top) + 1;
            if (width > 0 and height > 0) {
                handle.cols = @intCast(@min(width, std.math.maxInt(u16)));
                handle.rows = @intCast(@min(height, std.math.maxInt(u16)));
            }
        }
        return;
    }
    var ws: std.posix.winsize = .{ .row = 0, .col = 0, .xpixel = 0, .ypixel = 0 };
    const rc = std.c.ioctl(handle.stdout.handle, std.c.T.IOCGWINSZ, &ws);
    if (rc == 0 and ws.row != 0 and ws.col != 0) {
        handle.rows = ws.row;
        handle.cols = ws.col;
    }
}

fn setRawMode(handle: *TuiHandle, enabled: bool) !void {
    if (builtin.os.tag == .windows) {
        var mode: u32 = undefined;
        if (std.os.windows.kernel32.GetConsoleMode(handle.stdin.handle, &mode) == 0) return error.NotATerminal;
        if (enabled) {
            if (handle.windows_saved_mode == null) handle.windows_saved_mode = mode;
            const raw_mode = mode & ~@as(u32, 0x7);
            if (std.os.windows.kernel32.SetConsoleMode(handle.stdin.handle, raw_mode) == 0) return error.NotATerminal;
        } else if (handle.windows_saved_mode) |saved| {
            if (std.os.windows.kernel32.SetConsoleMode(handle.stdin.handle, saved) == 0) return error.NotATerminal;
            handle.windows_saved_mode = null;
        }
        return;
    }
    if (enabled) {
        if (handle.unix_saved_termios == null) {
            const original = try std.posix.tcgetattr(handle.stdin.handle);
            handle.unix_saved_termios = original;
            var raw = original;
            raw.lflag.ICANON = false;
            raw.lflag.ECHO = false;
            try std.posix.tcsetattr(handle.stdin.handle, .NOW, raw);
        }
    } else if (handle.unix_saved_termios) |saved| {
        try std.posix.tcsetattr(handle.stdin.handle, .NOW, saved);
        handle.unix_saved_termios = null;
    }
}

fn writeAll(handle: *TuiHandle, bytes: []const u8) !void {
    try handle.stdout.writeAll(bytes);
}

fn emitControl(handle: *TuiHandle, bytes: []const u8) !void {
    if (!handle.stdout.supportsAnsiEscapeCodes()) return;
    try writeAll(handle, bytes);
}

fn syncOutput(handle: *TuiHandle) void {
    if (builtin.os.tag != .windows) _ = handle.stdout.sync() catch {};
}

pub export fn sa_tui_open(out_handle: *?*anyopaque) callconv(.c) u32 {
    const allocator = std.heap.c_allocator;
    const handle = allocator.create(TuiHandle) catch return @intFromEnum(Status.failed);
    handle.* = .{ .stdin = std.io.getStdIn(), .stdout = std.io.getStdOut() };
    querySize(handle);
    out_handle.* = handle;
    return @intFromEnum(Status.ok);
}

pub export fn sa_tui_close(handle_value: ?*anyopaque) callconv(.c) u32 {
    const handle = handleFromOpaque(handle_value) orelse return @intFromEnum(Status.invalid_descriptor);
    const allocator = std.heap.c_allocator;
    if (handle.raw_mode) _ = setRawMode(handle, false) catch {};
    if (handle.alternate_screen) _ = emitControl(handle, "\x1b[?1049l\x1b[?25h") catch {};
    if (handle.mouse_tracking) _ = emitControl(handle, "\x1b[?1000l\x1b[?1006l") catch {};
    syncOutput(handle);
    allocator.destroy(handle);
    return @intFromEnum(Status.ok);
}

pub export fn sa_tui_size(handle_value: ?*anyopaque, out_rows: *u16, out_cols: *u16) callconv(.c) u32 {
    const handle = handleFromOpaque(handle_value) orelse return @intFromEnum(Status.invalid_descriptor);
    querySize(handle);
    out_rows.* = handle.rows;
    out_cols.* = handle.cols;
    return @intFromEnum(Status.ok);
}

pub export fn sa_tui_write(handle_value: ?*anyopaque, bytes: [*]const u8, len: usize) callconv(.c) u32 {
    const handle = handleFromOpaque(handle_value) orelse return @intFromEnum(Status.invalid_descriptor);
    writeAll(handle, bytes[0..len]) catch return @intFromEnum(Status.io_error);
    return @intFromEnum(Status.ok);
}

pub export fn sa_tui_flush(handle_value: ?*anyopaque) callconv(.c) u32 {
    const handle = handleFromOpaque(handle_value) orelse return @intFromEnum(Status.invalid_descriptor);
    syncOutput(handle);
    return @intFromEnum(Status.ok);
}

pub export fn sa_tui_set_mode(handle_value: ?*anyopaque, mode_value: u32) callconv(.c) u32 {
    const handle = handleFromOpaque(handle_value) orelse return @intFromEnum(Status.invalid_descriptor);
    const mode: Mode = std.meta.intToEnum(Mode, mode_value) catch return @intFromEnum(Status.invalid_descriptor);
    switch (mode) {
        .cooked => {
            if (handle.alternate_screen) _ = emitControl(handle, "\x1b[?1049l\x1b[?25h") catch return @intFromEnum(Status.failed);
            if (handle.mouse_tracking) _ = emitControl(handle, "\x1b[?1000l\x1b[?1006l") catch return @intFromEnum(Status.failed);
            handle.alternate_screen = false;
            handle.mouse_tracking = false;
            if (handle.raw_mode) setRawMode(handle, false) catch return @intFromEnum(Status.unsupported);
            handle.raw_mode = false;
        },
        .raw => {
            setRawMode(handle, true) catch return @intFromEnum(Status.unsupported);
            handle.raw_mode = true;
        },
        .alternate_screen => {
            emitControl(handle, "\x1b[?1049h\x1b[?25l") catch return @intFromEnum(Status.failed);
            handle.alternate_screen = true;
        },
        .mouse_tracking => {
            emitControl(handle, "\x1b[?1000h\x1b[?1006h") catch return @intFromEnum(Status.failed);
            handle.mouse_tracking = true;
        },
    }
    return @intFromEnum(Status.ok);
}

pub export fn sa_tui_read_event(
    handle_value: ?*anyopaque,
    timeout_ms: u32,
    out_kind: *u32,
    out_code: *u32,
) callconv(.c) u32 {
    const handle = handleFromOpaque(handle_value) orelse return @intFromEnum(Status.invalid_descriptor);
    if (timeout_ms > 0) {
        if (builtin.os.tag == .windows) {
            const wait_result = std.os.windows.kernel32.WaitForSingleObject(handle.stdin.handle, timeout_ms);
            if (wait_result == std.os.windows.WAIT_TIMEOUT) {
                out_kind.* = @intFromEnum(EventKind.none);
                out_code.* = 0;
                return @intFromEnum(Status.timeout);
            }
            if (wait_result != std.os.windows.WAIT_OBJECT_0) return @intFromEnum(Status.io_error);
        } else {
            var poll_fds = [_]std.posix.pollfd{.{ .fd = handle.stdin.handle, .events = std.posix.POLL.IN, .revents = 0 }};
            const ready = std.posix.poll(&poll_fds, @intCast(@min(timeout_ms, std.math.maxInt(i32)))) catch return @intFromEnum(Status.io_error);
            if (ready == 0) {
                out_kind.* = @intFromEnum(EventKind.none);
                out_code.* = 0;
                return @intFromEnum(Status.timeout);
            }
        }
    }
    var byte: [1]u8 = undefined;
    const count = handle.stdin.read(&byte) catch return @intFromEnum(Status.io_error);
    if (count == 0) {
        out_kind.* = @intFromEnum(EventKind.eof);
        out_code.* = 0;
        return @intFromEnum(Status.ok);
    }
    out_kind.* = @intFromEnum(EventKind.byte);
    out_code.* = byte[0];
    return @intFromEnum(Status.ok);
}

const skills = [_]plugin_api.SkillSection{
    .{
        .name = "tui.terminal",
        .summary = "Cross-platform terminal ownership, dimensions, and mode control",
        .items = &.{
            "open and close a terminal handle",
            "query terminal rows and columns",
            "toggle cooked, raw, and alternate-screen modes",
        },
    },
    .{
        .name = "tui.input",
        .summary = "Byte-oriented terminal input with bounded waits",
        .items = &.{
            "read byte and EOF input events",
            "return timeout status when no input is available",
        },
    },
    .{
        .name = "tui.ansi",
        .summary = "UTF-8 output and ANSI terminal controls",
        .items = &.{
            "write and flush UTF-8 output",
            "toggle mouse tracking controls",
        },
    },
};

pub const descriptor = plugin_api.PluginDescriptor{
    .abi_version = plugin_api.abi_version,
    .descriptor_size = @as(u32, @intCast(@sizeOf(plugin_api.PluginDescriptor))),
    .name = "tui",
    .init = null,
    .prebuild = null,
    .postbuild = null,
    .handle_command = null,
    .skills_ptr = skills[0..].ptr,
    .skills_len = skills.len,
};

pub export const saasm_plugin_descriptor_v1: plugin_api.PluginDescriptor = descriptor;

pub export fn saasm_plugin_descriptor_v1_fn(out: *plugin_api.PluginDescriptor) callconv(.c) void {
    out.* = descriptor;
}
