const std = @import("std");

pub const Type = enum {
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

    pub fn fromPath(path: []const u8) @This() {
        const extension = std.fs.path.extension(path);
        return if (extension.len > 1)
            std.meta.stringToEnum(@This(), std.fs.path.extension(path)[1..]) orelse .bin
        else
            .bin;
    }
};
