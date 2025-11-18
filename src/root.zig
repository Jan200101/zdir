const std = @import("std");
const log = std.log;
const Allocator = std.mem.Allocator;
const ComponentIterator = std.fs.path.ComponentIterator;
const Dir = std.fs.Dir;
const PosixComponentIterator = ComponentIterator(.posix, u8);
const Writer = std.Io.Writer;

pub const config = @import("config");

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
    allocator: Allocator,
    root_dir: std.fs.Dir,
    path: []const u8,

    pub fn init(allocator: Allocator, root_dir: std.fs.Dir, path: []const u8) @This() {
        return .{
            .allocator = allocator,
            .root_dir = root_dir,
            .path = path,
        };
    }

    pub fn format(self: @This(), writer: *std.Io.Writer) !void {
        try writer.print(body_html, .{
            Crumb.init(self.path),
            FileTable.init(self.allocator, self.root_dir, self.path),
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
    allocator: Allocator,
    root_dir: std.fs.Dir,
    path: []const u8,

    pub fn init(allocator: Allocator, root_dir: std.fs.Dir, path: []const u8) @This() {
        return .{
            .allocator = allocator,
            .root_dir = root_dir,
            .path = path,
        };
    }

    pub fn sortDirEntry(_: void, a: Dir.Entry, b: Dir.Entry) bool {
        if (a.kind != b.kind) {
            if (a.kind == .directory)
                return true;
            if (b.kind == .directory)
                return false;
        }
        return std.ascii.orderIgnoreCase(a.name, b.name) == .lt;
    }

    pub fn format(self: @This(), writer: *std.Io.Writer) !void {
        const p = if (self.path.len <= 1)
            "."
        else
            self.path[1..];

        var dir = self.root_dir.openDir(p, .{ .iterate = true }) catch |err| {
            log.err(
                "failed to open {s}: {s}",
                .{ p, @errorName(err) },
            );
            return;
        };
        defer dir.close();

        var contents: std.array_list.Aligned(Dir.Entry, null) = .empty;
        defer contents.deinit(self.allocator);

        var iter = dir.iterateAssumeFirstIteration();
        while (iter.next() catch return) |content| {
            if (content.name[0] == '.')
                continue;

            var store = content;
            store.name = self.allocator.dupe(u8, content.name) catch |err| {
                log.err(
                    "failed to allocate {s}: {s}",
                    .{ content.name, @errorName(err) },
                );
                return;
            };

            contents.append(self.allocator, store) catch |err| {
                log.err(
                    "failed to append {s}: {s}",
                    .{ store.name, @errorName(err) },
                );
                self.allocator.free(store.name);

                return;
            };
        }

        const content_slice = contents.toOwnedSlice(self.allocator) catch |err| {
            log.err(
                "failed to own slice: {s}",
                .{@errorName(err)},
            );
            return;
        };
        defer self.allocator.free(content_slice);
        std.mem.sort(Dir.Entry, content_slice, {}, sortDirEntry);

        for (content_slice) |content| {
            defer self.allocator.free(content.name);

            const suffix = if (content.kind == .directory)
                "/"
            else
                "";

            const full_path = std.fs.path.join(self.allocator, &[_][]const u8{ self.path, content.name }) catch |err| {
                log.err(
                    "failed to join {s} {s}: {s}",
                    .{ self.path, content.name, @errorName(err) },
                );
                continue;
            };
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

pub fn getRoot() !std.fs.Dir {
    return try std.fs.cwd().openDir(config.root_path, .{});
}

pub fn canServeFile(root_dir: std.fs.Dir, path: []const u8) bool {
    const p = if (path.len <= 1)
        "."
    else
        path[1..];

    const stat = root_dir.statFile(p) catch return false;

    return stat.kind != .directory;
}

pub fn serveFile(root_dir: std.fs.Dir, writer: *Writer, path: []const u8) !void {
    const p = if (path.len <= 1)
        "."
    else
        path[1..];

    const file = try root_dir.openFile(p, .{});
    defer file.close();

    var reader = file.reader(&.{});
    _ = try writer.sendFileAll(&reader, .unlimited);
}

pub fn serveDir(allocator: Allocator, root_dir: std.fs.Dir, writer: *Writer, path: []const u8) !void {
    try writer.print(root_html, .{
        Head.init(path),
        Body.init(allocator, root_dir, path),
    });
}
