const std = @import("std");
const builtin = @import("builtin");

const log = std.log;
const http = std.http;

const core = @import("core");

const MimeType = @import("Mime.zig").Type;

// 30 minutes
const CACHE_AGE = 60 * 30;

var stdout_buffer: [1024]u8 = undefined;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var stdout = std.fs.File.stdout().writer(&stdout_buffer);
    const writer = &stdout.interface;
    defer writer.flush() catch {};

    const path = std.process.getEnvVarOwned(allocator, "PATH_INFO") catch "/";

    const sane_path = try std.fs.path.resolvePosix(allocator, &[_][]const u8{ "/", path });
    defer allocator.free(sane_path);

    var root_dir = try core.getRoot();
    defer root_dir.close();

    if (core.isAsset(sane_path)) {
        try writer.print("Content-Type: {s}\n", .{MimeType.fromPath(path).contentType()});
        try writer.print("Cache-Control: max-age={}\n", .{CACHE_AGE});
        try writer.writeAll("\n");
        try core.serveAsset(writer, sane_path);
    } else if (core.canServeFile(root_dir, sane_path)) {
        try writer.print("Content-Type: {s}\n", .{MimeType.fromPath(path).contentType()});
        try writer.writeAll("\n");
        try core.serveFile(root_dir, writer, sane_path);
    } else {
        try writer.writeAll("Content-Type: text/html; charset=utf-8\n\n");
        try core.serveDir(allocator, root_dir, writer, sane_path);
    }
}
