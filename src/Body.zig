const std = @import("std");

const Allocator = std.mem.Allocator;
const Dir = std.fs.Dir;
const Writer = std.Io.Writer;

const Crumb = @import("Crumb.zig");
const FileTable = @import("FileTable.zig");

const body_html = @embedFile("body.html");

allocator: Allocator,
root_dir: Dir,
path: []const u8,

pub fn init(allocator: Allocator, root_dir: Dir, path: []const u8) @This() {
    return .{
        .allocator = allocator,
        .root_dir = root_dir,
        .path = path,
    };
}

pub fn format(self: @This(), writer: *Writer) !void {
    try writer.print(body_html, .{
        .crumbs = Crumb.init(self.path),
        .files = FileTable.init(self.allocator, self.root_dir, self.path),
    });
}
