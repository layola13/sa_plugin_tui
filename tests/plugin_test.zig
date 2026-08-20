const std = @import("std");
const plugin = @import("plugin");
const plugin_api = @import("plugin_api");

test "tui descriptor exposes the versioned skill contract" {
    const descriptor = &plugin.saasm_plugin_descriptor_v1;
    try std.testing.expectEqual(plugin_api.abi_version, descriptor.abi_version);
    try std.testing.expectEqualStrings("tui", std.mem.span(descriptor.name));
    try std.testing.expectEqual(@as(usize, 3), descriptor.skills_len);
    try std.testing.expectEqualStrings("tui.terminal", descriptor.skills_ptr[0].name);
    try std.testing.expectEqualStrings("tui.input", descriptor.skills_ptr[1].name);
    try std.testing.expectEqualStrings("tui.ansi", descriptor.skills_ptr[2].name);
}

test "tui handle reports a non-empty terminal size" {
    var handle: ?*anyopaque = null;
    try std.testing.expectEqual(@as(u32, 0), plugin.sa_tui_open(&handle));
    defer _ = plugin.sa_tui_close(handle);
    var rows: u16 = 0;
    var cols: u16 = 0;
    try std.testing.expectEqual(@as(u32, 0), plugin.sa_tui_size(handle, &rows, &cols));
    try std.testing.expect(rows > 0);
    try std.testing.expect(cols > 0);
}

test "tui mode transitions are reversible" {
    var handle: ?*anyopaque = null;
    try std.testing.expectEqual(@as(u32, 0), plugin.sa_tui_open(&handle));
    defer _ = plugin.sa_tui_close(handle);
    try std.testing.expectEqual(@as(u32, 0), plugin.sa_tui_set_mode(handle, 2));
    try std.testing.expectEqual(@as(u32, 0), plugin.sa_tui_set_mode(handle, 3));
    try std.testing.expectEqual(@as(u32, 0), plugin.sa_tui_set_mode(handle, 0));
}
