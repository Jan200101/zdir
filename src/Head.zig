const std = @import("std");

const Writer = std.Io.Writer;

const core = @import("root.zig");
const assets_path = core.assets_path;

const head_html = @embedFile("head.html");

path: []const u8,

pub fn init(path: []const u8) @This() {
    return .{
        .path = path,
    };
}

pub fn format(self: @This(), writer: *Writer) !void {
    try writer.print(head_html, .{ self.path, assets_path });
}
