const std = @import("std");
const builtin = @import("builtin");

const log = std.log.scoped(.cgi);
const http = std.http;

const core = @import("core");
const common = @import("common.zig");
const lockdown = @import("lockdown.zig");
const MimeType = @import("Mime.zig").Type;

var stdout_buffer: [4096]u8 = undefined;

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

pub fn main() !void {
    var root_dir = try core.getRoot();
    defer root_dir.close();

    lockdown.lockdown_dir(root_dir);

    const base_allocator = gpa: {
        if (builtin.target.os.tag == .wasi) break :gpa .{ std.heap.wasm_allocator, false };
        break :gpa if (common.is_debug) debug_allocator.allocator() else std.heap.page_allocator;
    };
    defer if (common.is_debug) {
        _ = debug_allocator.deinit();
    };

    var arena = std.heap.ArenaAllocator.init(base_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var stdout = std.fs.File.stdout().writer(&stdout_buffer);
    const writer = &stdout.interface;
    defer writer.flush() catch {};

    const path = std.process.getEnvVarOwned(allocator, "PATH_INFO") catch "/";

    const sane_path = try std.fs.path.resolvePosix(allocator, &[_][]const u8{ "/", path });
    defer allocator.free(sane_path);

    if (core.isAsset(sane_path)) {
        try writer.print("Content-Type: {s}\n", .{MimeType.fromPath(sane_path).contentType()});
        try writer.print("Cache-Control: max-age={}\n", .{common.CACHE_AGE});
        try writer.writeAll("\n");
        try core.serveAsset(writer, sane_path);
    } else if (core.canServeFile(root_dir, sane_path)) {
        try writer.print("Content-Type: {s}\n", .{MimeType.fromPath(sane_path).contentType()});
        try writer.writeAll("\n");
        try core.serveFile(root_dir, writer, sane_path);
    } else {
        try writer.writeAll("Content-Type: text/html; charset=utf-8\n\n");
        try core.serveDir(allocator, root_dir, writer, sane_path);
    }
}
