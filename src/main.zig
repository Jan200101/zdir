const std = @import("std");

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
    var alloc_buffer: [1024]u8 = undefined;
    var alloc: std.heap.FixedBufferAllocator = .init(&alloc_buffer);
    const bfa = alloc.allocator();

    var response_buffer: [1024]u8 = undefined;
    var response = try request.respondStreaming(&response_buffer, .{ .respond_options = .{
        .keep_alive = false,
    } });
    const writer = &response.writer;

    const sane_path = try std.fs.path.resolvePosix(bfa, &[_][]const u8{ "/", request.head.target });

    log.debug("target {s}", .{request.head.target});
    log.debug("path {s}", .{sane_path});

    try code.renderPage(writer, sane_path);

    try response.end();
}
