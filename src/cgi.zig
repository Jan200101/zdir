const std = @import("std");
const builtin = @import("builtin");

const log = std.log;

const core = @import("core");

// 30 minutes
const CACHE_AGE = 60 * 30;

var stdout_buffer: [1024]u8 = undefined;

const MimeType = enum {
    txt,
    md,
    map,
    spec,
    sha256sum,
    sha512sum,
    c,
    cpp,
    h,
    py,
    lua,
    zig,
    zon,
    php,

    csv,
    html,
    css,
    pdf,

    png,
    jpeg,
    jpg,
    gif,
    webp,
    svg,
    bmp,
    ico,

    zip,
    tar,
    @"7z",
    cpio,
    rar,

    gz,
    xz,
    zstd,
    zst,
    bz2,

    bin,

    bat,
    com,
    dll,
    exe,
    msi,

    pub fn contentType(self: @This()) []const u8 {
        return switch (self) {
            .txt,
            .md,
            .map,
            .spec,
            .sha256sum,
            .sha512sum,
            .c,
            .cpp,
            .h,
            .py,
            .lua,
            .zig,
            .zon,
            .php,
            => "text/plain; charset=utf-8",

            .csv => "text/csv; charset=utf-8",
            .html => "text/html; charset=utf-8",
            .css => "text/css; charset=utf-8",
            .pdf => "application/pdf",

            .png => "image/png",
            .jpeg => "image/jpeg",
            .jpg => "image/jpeg",
            .gif => "image/gif",
            .webp => "image/webp",
            .svg => "image/svg+xml",
            .bmp => "image/bmp",
            .ico => "image/x-icon",

            .zip => "application/zip",
            .tar => "application/x-tar",
            .@"7z" => "application/x-7z-compressed",
            .cpio => "application/x-cpio",
            .rar => "application/x-rar-compressed",

            .gz => "application/gzip",
            .xz => "application/x-xz",
            .zstd, .zst => "application/zstd",
            .bz2 => "application/x-bzip2",

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

fn get_mime(path: []const u8) MimeType {
    const extension = std.fs.path.extension(path);
    return if (extension.len > 1)
        std.meta.stringToEnum(MimeType, std.fs.path.extension(path)[1..]) orelse .bin
    else
        .bin;
}

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
        try writer.print("Content-Type: {s}\n", .{get_mime(sane_path).contentType()});
        try writer.print("Cache-Control: max-age={}\n", .{CACHE_AGE});
        try writer.writeAll("\n");
        try core.serveAsset(writer, sane_path);
    } else if (core.canServeFile(root_dir, sane_path)) {
        try writer.print("Content-Type: {s}\n", .{get_mime(sane_path).contentType()});
        try writer.writeAll("\n");
        try core.serveFile(root_dir, writer, sane_path);
    } else {
        try writer.writeAll("Content-Type: text/html; charset=utf-8\n\n");
        try core.serveDir(allocator, root_dir, writer, sane_path);
    }
}
