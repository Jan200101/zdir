const std = @import("std");
const builtin = @import("builtin");

const log = std.log;

const core = @import("core");

var stdout_buffer: [1024]u8 = undefined;

const Ext = enum {
    txt,
    md,
    map,
    spec,
    sha256sum,
    sha512sum,
    c,
    py,
    lua,
    php,

    csv,
    html,
    css,

    zip,
    tar,
    @"tar.gz",
    @"tar.xz",
    @"tar.zstd",
    @"7z",

    pdf,
    bin,

    bat,
    com,
    dll,
    exe,
    msi,

    pub fn contentType(self: Ext) []const u8 {
        return switch (self) {
            .txt,
            .md,
            .map,
            .spec,
            .sha256sum,
            .sha512sum,
            .c,
            .py,
            .lua,
            .php,
            => "text/plain",

            .csv => "text/csv",
            .html => "text/html",
            .css => "text/css",

            .zip => "application/zip",
            .tar => "application/x-tar",
            .@"tar.gz" => "application/gzip",
            .@"tar.xz" => "application/x-xz",
            .@"tar.zstd" => "application/zstd",
            .@"7z" => "application/x-7z-compressed",

            .pdf => "application/pdf",
            .bin => "application/octet-stream",

            .bat,
            .com,
            .dll,
            .exe,
            .msi,
            => "application/x-msdownload",
        };
    }
};

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

    if (core.canServeFile(root_dir, sane_path)) {
        const extension = std.fs.path.extension(sane_path);
        const ext_type = if (extension.len > 1)
            std.meta.stringToEnum(Ext, std.fs.path.extension(sane_path)[1..]) orelse .bin
        else
            .bin;

        try writer.print("Content-Type: {s}; charset=utf-8\n\n", .{ext_type.contentType()});
        try core.serveFile(root_dir, writer, sane_path);
    } else {
        try writer.writeAll("Content-Type: text/html; charset=utf-8\n\n");
        try core.serveDir(allocator, root_dir, writer, sane_path);
    }
}
