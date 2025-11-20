const std = @import("std");
const builtin = @import("builtin");

const log = std.log;
const linux = std.os.linux;
const posix = std.posix;
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

    pub fn content(self: Asset) []const u8 {
        return switch (self) {
            .@"style.css" => @embedFile("style.css"),
            .@"favicon.ico" => @embedFile("favicon.ico"),
        };
    }

    pub fn is_asset(path: []const u8) bool {
        if (path.len <= 1)
            return false;

        const p = path[1..];

        if (std.mem.startsWith(u8, p, assets_path))
            return true;

        if (std.mem.eql(u8, p, "favicon.ico"))
            return true;

        return false;
    }
};

const Head = @import("Head.zig");
const Body = @import("Body.zig");

pub fn getRoot() !std.fs.Dir {
    return try std.fs.cwd().openDir(config.root_path, .{});
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

    // reserve asset path completely
    if (Asset.is_asset(path)) {
        const asset_path = if (std.mem.startsWith(u8, p, assets_dir))
            p[assets_dir.len..]
        else
            p;
        const asset = std.meta.stringToEnum(Asset, asset_path) orelse return;

        _ = try writer.writeAll(asset.content());

        return;
    }

    const file = root_dir.openFile(p, .{}) catch |err| {
        try writer.print("Failed to open {s}: {s}", .{
            p,
            @errorName(err),
        });
        return;
    };
    defer file.close();

    var reader = file.reader(&.{});
    _ = try writer.sendFileAll(&reader, .unlimited);
}

pub fn serveDir(allocator: Allocator, root_dir: std.fs.Dir, writer: *Writer, path: []const u8) !void {
    try writer.print(root_html, .{
        .head = Head.init(path),
        .body = Body.init(allocator, root_dir, path),
    });
}
