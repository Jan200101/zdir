const std = @import("std");
const log = std.log;
const Writer = std.Io.Writer;

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

    var start_index: usize = 0;

    var loop = true;
    while (loop) {
        const index = blk: {
            const start = start_index;
            const i = std.mem.indexOfPosLinear(u8, path, start, "/") orelse path.len;
            start_index = i + 1;

            log.debug("start {} i {}", .{ start, i });

            var e = i + 1;
            if (i == path.len) {
                loop = false;
                e = i;
            }

            if (i > 0 and start >= i)
                continue;

            break :blk .{
                .start = start,
                .end = i,
                .full = e,
            };
        };

        try writer.writeAll(
            \\<a class="crumb" href="
        );

        try writer.writeAll(path[0..index.full]);

        try writer.writeAll("\">");

        try writer.writeAll(path[index.start..index.end]);

        try writer.writeAll(
            \\</a>
        );
    }

    try writer.writeAll(
        \\</div>
        \\<div id="main">
        \\<table>
        \\<thead>
        \\<th>Name</th>
        \\<th>Last Modified</th>
        \\<th>Size</th>
        \\</thead>
        \\<tbody>
    );

    dirblk: {
        var p = blk: {
            if (path[0] == '/') {
                break :blk path[1..path.len];
            }
            break :blk path;
        };

        if (p.len == 0)
            p = ".";

        log.debug("p {s}", .{p});

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
            try writer.writeAll("</a></td><td>");
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
