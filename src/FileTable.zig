const std = @import("std");

const log = std.log;
const Allocator = std.mem.Allocator;
const Dir = std.fs.Dir;
const Writer = std.Io.Writer;

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

pub fn sortDirEntry(_: void, a: Dir.Entry, b: Dir.Entry) bool {
    if (a.kind != b.kind) {
        if (a.kind == .directory)
            return true;
        if (b.kind == .directory)
            return false;
    }
    return std.ascii.orderIgnoreCase(a.name, b.name) == .lt;
}

pub fn format(self: @This(), writer: *Writer) !void {
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
        if (content.kind == .file) {
            const size = blk: {
                const stat = dir.statFile(content.name) catch break :blk 0;

                break :blk stat.size;
            };

            try writer.print("<td>{}</td>", .{size});
        } else {
            try writer.writeAll("<td></td>");
        }
        try writer.writeAll("</tr>");
    }
}
