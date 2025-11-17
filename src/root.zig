const std = @import("std");
const log = std.log;
const Writer = std.Io.Writer;
const ComponentIterator = std.fs.path.ComponentIterator;

pub const head_html = @embedFile("head.html");
pub const style_css = @embedFile("style.css");

pub fn renderPage(writer: *Writer, path: []const u8) !void {
    try writer.writeAll(
        \\<!DOCTYPE html>
        \\<head>
        \\<title>
    );
    try writer.writeAll(path);
    try writer.writeAll("</title>");

    try writer.writeAll(head_html);

    try writer.writeAll("<style>");
    try writer.writeAll(style_css);
    try writer.writeAll("</style>");

    try writer.writeAll(
        \\</head>
        \\<body>
        \\<div id="top">
    );

    const PosixComponentIterator = ComponentIterator(.posix, u8);
    {
        var iter = try PosixComponentIterator.init(path);
        try writer.writeAll(
            \\<a class="crumb" href="/"></a>
        );

        while (iter.next()) |content| {
            try writer.writeAll(
                \\<a class="crumb" href="
            );

            try writer.writeAll(content.path);

            try writer.writeAll("\">");

            try writer.writeAll(content.name);

            try writer.writeAll(
                \\</a>
            );
        }
    }

    try writer.writeAll(
        \\</div>
        \\<div id="main">
        \\<table>
        \\<thead>
        \\<th>Name</th>
        \\<th>Type</th>
        \\<th>Last Modified</th>
        \\<th>Size</th>
        \\</thead>
        \\<tbody>
    );

    dirblk: {
        const p = if (path.len <= 1)
            "."
        else
            path[1..];

        var dir = std.fs.cwd().openDir(p, .{ .iterate = true }) catch break :dirblk;
        defer dir.close();

        var iter = dir.iterateAssumeFirstIteration();
        while (try iter.next()) |content| {
            try writer.writeAll("<tr><td><a href=\"");
            try writer.writeAll(path);
            if (path[path.len - 1] != '/')
                try writer.writeAll("/");
            try writer.writeAll(content.name);
            try writer.writeAll("\">");
            try writer.writeAll(content.name);
            if (content.kind == .directory)
                try writer.writeAll("/");
            try writer.writeAll("</a></td><td>");
            try writer.writeAll(@tagName(content.kind));
            try writer.writeAll("</td><td>");
            try writer.writeAll("</td><td>");
            if (content.kind == .file)
                try writer.writeAll("0");
            try writer.writeAll("</td></tr>");
        }
    }

    try writer.writeAll(
        \\</tbody>
        \\</table>
        \\</div>
        \\</body>
        \\</html>
    );
}
