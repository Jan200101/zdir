const std = @import("std");
const log = std.log;
const Allocator = std.mem.Allocator;
const ComponentIterator = std.fs.path.ComponentIterator;
const PosixComponentIterator = ComponentIterator(.posix, u8);
const Writer = std.Io.Writer;

pub const head_html = @embedFile("head.html");
pub const body_html = @embedFile("body.html");
pub const root_html = @embedFile("root.html");
pub const style_css = @embedFile("style.css");

pub const Head = struct {
    path: []const u8,

    pub fn init(path: []const u8) @This() {
        return .{
            .path = path,
        };
    }

    pub fn format(self: @This(), writer: *std.Io.Writer) !void {
        try writer.print(head_html, .{ self.path, style_css });
    }
};

pub const Body = struct {
    path: []const u8,
    allocator: Allocator,

    pub fn init(allocator: Allocator, path: []const u8) @This() {
        return .{
            .allocator = allocator,
            .path = path,
        };
    }

    pub fn format(self: @This(), writer: *std.Io.Writer) !void {
        try writer.print(body_html, .{
            Crumb.init(self.path),
            FileTable.init(self.allocator, self.path),
        });
    }
};

pub const Crumb = struct {
    path: []const u8,

    pub fn init(path: []const u8) @This() {
        return .{
            .path = path,
        };
    }

    pub fn format(self: @This(), writer: *std.Io.Writer) !void {
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
};

pub const FileTable = struct {
    path: []const u8,
    allocator: Allocator,

    pub fn init(allocator: Allocator, path: []const u8) @This() {
        return .{
            .allocator = allocator,
            .path = path,
        };
    }

    pub fn format(self: @This(), writer: *std.Io.Writer) !void {
        const p = if (self.path.len <= 1)
            "."
        else
            self.path[1..];

        var dir = std.fs.cwd().openDir(p, .{ .iterate = true }) catch return;
        defer dir.close();

        var iter = dir.iterateAssumeFirstIteration();
        while (iter.next() catch return) |content| {
            const suffix = if (content.kind == .directory)
                "/"
            else
                "";

            const full_path = std.fs.path.join(self.allocator, &[_][]const u8{ self.path, content.name }) catch return;
            defer self.allocator.free(full_path);

            try writer.print(
                \\<tr><td><a href="{s}">{s}{s}</a></td>
            , .{ full_path, content.name, suffix });

            try writer.print("<td>{s}</td>", .{@tagName(content.kind)});
            try writer.print("<td></td>", .{});
            if (content.kind == .file)
                try writer.print("<td>{}</td>", .{0})
            else
                try writer.writeAll("<td></td>");
            try writer.writeAll("</tr>");
        }
    }
};

pub fn renderPage(allocator: Allocator, writer: *Writer, path: []const u8) !void {
    try writer.print(root_html, .{
        Head.init(path),
        Body.init(allocator, path),
    });
}
