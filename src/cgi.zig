const std = @import("std");
const builtin = @import("builtin");

const code = @import("code");

var stdout_buffer: [1024]u8 = undefined;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var stdout = std.fs.File.stdout().writer(&stdout_buffer);
    const writer = &stdout.interface;

    const path = std.process.getEnvVarOwned(allocator, "PATH_INFO") catch "/";

    const sane_path = try std.fs.path.resolvePosix(allocator, &[_][]const u8{ "/", path });
    defer allocator.free(sane_path);

    code.serve(allocator, writer, sane_path) catch |err| {
        try writer.print("err {s}", .{@errorName(err)});
    };
}
