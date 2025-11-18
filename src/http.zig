const std = @import("std");
const builtin = @import("builtin");

const log = std.log;
const http = std.http;
const HttpServer = http.Server;
const Address = std.net.Address;

const code = @import("code");

pub fn main() !void {
    const addr = try Address.parseIp("127.0.0.1", 8884);
    var server = try Address.listen(addr, .{ .reuse_address = true });
    defer server.deinit();

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
                .none => handleRequest(&request) catch |err| log.err("failed to handle request: {s}", .{@errorName(err)}),
            }
        }
    }
}

fn handleRequest(request: *HttpServer.Request) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var response_buffer: [1024]u8 = undefined;
    var response = try request.respondStreaming(&response_buffer, .{ .respond_options = .{
        .keep_alive = false,
    } });
    const writer = &response.writer;

    var target_path: [1024]u8 = undefined;

    const sane_path = try std.fs.path.resolvePosix(allocator, &[_][]const u8{ "/", std.Uri.percentDecodeBackwards(&target_path, request.head.target) });
    defer allocator.free(sane_path);

    var root_dir = try code.getRoot();
    defer root_dir.close();

    if (code.canServeFile(root_dir, sane_path)) {
        try code.serveFile(root_dir, writer, sane_path);
    } else {
        try code.serveDir(allocator, root_dir, writer, sane_path);
    }

    try response.end();
}
