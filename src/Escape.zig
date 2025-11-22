const std = @import("std");

const Allocator = std.mem.Allocator;
const Dir = std.fs.Dir;
const Writer = std.Io.Writer;

const Crumb = @import("Crumb.zig");
const FileTable = @import("FileTable.zig");

const body_html = @embedFile("body.html");

input: []const u8,

pub fn init(input: []const u8) @This() {
    return .{
        .input = input,
    };
}

pub fn format(self: @This(), writer: *Writer) !void {
    for (self.input) |char| switch (char) {
        '"' => try writer.writeAll("&quot;"),
        '\'' => try writer.writeAll("&apos;"),
        '&' => try writer.writeAll("&amp;"),
        '<' => try writer.writeAll("&lt;"),
        '>' => try writer.writeAll("&gt;"),
        else => try writer.writeByte(char),
    };
}
