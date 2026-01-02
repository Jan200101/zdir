const std = @import("std");
const builtin = @import("builtin");

const log = std.log.scoped(.zdir);
const linux = std.os.linux;
const posix = std.posix;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const ComponentIterator = std.fs.path.ComponentIterator;
const Dir = std.fs.Dir;
const PosixComponentIterator = ComponentIterator(.posix, u8);
const Writer = std.Io.Writer;

pub const config = @import("config");

const root_html = @embedFile("root.html");

pub const assets_path = "_zdir";
pub const assets_dir = assets_path ++ "/";

const Asset = enum {
    @"style.css",
    @"favicon.ico",
    @"robots.txt",

    pub fn content(self: Asset) []const u8 {
        return switch (self) {
            .@"style.css" => @embedFile("style.css"),
            .@"favicon.ico" => @embedFile("favicon.ico"),
            .@"robots.txt" => @embedFile("robots.txt"),
        };
    }

    pub fn is_asset(path: []const u8) bool {
        if (path.len <= 1)
            return false;

        assert(path[0] == '/');
        const p = path[1..];

        if (std.mem.startsWith(u8, p, assets_path))
            return true;

        const root_assets = [_]@This(){
            .@"favicon.ico",
            .@"robots.txt",
        };

        for (root_assets) |asset|
            if (std.mem.eql(u8, p, @tagName(asset)))
                return true;

        return false;
    }
};

pub fn getRoot() !std.fs.Dir {
    return try std.fs.cwd().openDir(config.root_path, .{});
}

pub fn isAsset(path: []const u8) bool {
    return Asset.is_asset(path);
}

pub fn serveAsset(writer: *Writer, path: []const u8) !void {
    const p = if (path.len <= 1)
        "."
    else
        path[1..];

    const asset_path = if (std.mem.startsWith(u8, p, assets_dir))
        p[assets_dir.len..]
    else
        p;
    const asset = std.meta.stringToEnum(Asset, asset_path) orelse return;

    _ = try writer.writeAll(asset.content());
}

pub fn canServeFile(root_dir: std.fs.Dir, path: []const u8) bool {
    const p = if (path.len <= 1)
        "."
    else
        path[1..];

    if (Asset.is_asset(path))
        return true;

    const stat = root_dir.statFile(p) catch return false;

    return stat.kind != .directory;
}

pub fn serveFile(root_dir: std.fs.Dir, writer: *Writer, path: []const u8) !void {
    const p = if (path.len <= 1)
        "."
    else
        path[1..];

    const file = root_dir.openFile(p, .{}) catch |err| {
        try writer.print("Failed to open {s}: {s}", .{
            p,
            @errorName(err),
        });
        return;
    };
    defer file.close();

    var reader = file.readerStreaming(&.{});
    _ = try writer.sendFileAll(&reader, .unlimited);
}

pub fn serveDir(allocator: Allocator, root_dir: std.fs.Dir, writer: *Writer, path: []const u8) !void {
    try writer.print(root_html, .{
        .head = @import("Head.zig").init(path),
        .body = @import("Body.zig").init(allocator, root_dir, path),
    });
}
