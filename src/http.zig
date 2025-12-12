const std = @import("std");
const builtin = @import("builtin");

const log = std.log;
const http = std.http;
const HttpServer = http.Server;
const Address = std.net.Address;

const core = @import("core");

const lockdown = @import("lockdown.zig");

pub fn main() !void {
    var root_dir = try core.getRoot();
    defer root_dir.close();

    const addr = try Address.parseIp("0.0.0.0", core.config.http_port);
    var server = try Address.listen(addr, .{ .reuse_address = true });
    defer server.deinit();

    try lockdown.lockdown_dir(root_dir);

    log.info("Starting HTTP server at http://{f}", .{addr});

    var recv_buffer: [1024]u8 = undefined;
    var send_buffer: [100]u8 = undefined;

    accept: while (true) {
        const connection = try server.accept();
        defer connection.stream.close();

        log.debug("connection from {f}", .{connection.address});

        var connection_br = connection.stream.reader(&recv_buffer);
        var connection_bw = connection.stream.writer(&send_buffer);

        var http_server: HttpServer = .init(connection_br.interface(), &connection_bw.interface);
        while (http_server.reader.state == .ready) {
            var request = http_server.receiveHead() catch |err| switch (err) {
                error.HttpConnectionClosing => break,
                else => {
                    std.debug.print("error: {s}\n", .{@errorName(err)});
                    continue :accept;
                },
            };

            switch (request.upgradeRequested()) {
                .other => |proto| log.err("Unsupported protocol {s}", .{proto}),
                .websocket => |_| log.err("Websocket unsupported", .{}),
                .none => handleRequest(&request, root_dir) catch |err| log.err("failed to handle request: {s}", .{@errorName(err)}),
            }
        }
    }
}

fn handleRequest(request: *HttpServer.Request, root_dir: std.fs.Dir) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var response_buffer: [1024]u8 = undefined;
    var response = try request.respondStreaming(&response_buffer, .{ .respond_options = .{
        .keep_alive = false,
    } });
    defer response.end() catch {};
    const writer = &response.writer;

    const target = request.head.target;
    const abs_path, const query = if (std.mem.indexOfPos(u8, target, 0, "?")) |pos|
        .{ target[0..pos], target[pos..] }
    else
        .{ request.head.target, "" };

    _ = query;

    var target_buffer: [1024]u8 = undefined;
    const resolved_path = std.Uri.percentDecodeBackwards(&target_buffer, abs_path);

    log.debug("requested {s}", .{resolved_path});

    const sane_path = try std.fs.path.resolvePosix(allocator, &[_][]const u8{ "/", resolved_path });
    defer allocator.free(sane_path);

    if (core.isAsset(sane_path)) {
        try core.serveAsset(writer, sane_path);
    } else if (core.canServeFile(root_dir, sane_path)) {
        try core.serveFile(root_dir, writer, sane_path);
    } else {
        try core.serveDir(allocator, root_dir, writer, sane_path);
    }
}
