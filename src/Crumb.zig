const std = @import("std");

const Writer = std.Io.Writer;
const ComponentIterator = std.fs.path.ComponentIterator;
const PosixComponentIterator = ComponentIterator(.posix, u8);

path: []const u8,

pub fn init(path: []const u8) @This() {
    return .{
        .path = path,
    };
}

pub fn format(self: @This(), writer: *Writer) !void {
    try writer.writeAll(
        \\<a class="crumb" href="/"></a>
    );

    var iterator: PosixComponentIterator = try .init(self.path);
    while (iterator.next()) |content| {
        try writer.print(
            \\<a class="crumb" href="{s}">{s}</a>
        , .{ content.path, content.name });
    }
}
