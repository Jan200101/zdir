const std = @import("std");
const builtin = @import("builtin");

const log = std.log;
const posix = std.posix;
const net = std.net;
const Address = net.Address;
const Server = net.Server;
const Io = std.Io;
const Reader = Io.Reader;
const Writer = Io.Writer;
const Allocator = std.mem.Allocator;
const File = std.fs.File;
const native_endian = builtin.target.cpu.arch.endian();
const assert = std.debug.assert;
const core = @import("core");

const MimeType = @import("Mime.zig").Type;
const lockdown = @import("lockdown.zig");

// 30 minutes
const CACHE_AGE = 60 * 30;

const fcgi_version = enum(u8) {
    VERSION_1 = 1,
};

const fcgi_type = enum(u8) {
    BEGIN_REQUEST = 1,
    ABORT_REQUEST = 2,
    END_REQUEST = 3,
    PARAMS = 4,
    STDIN = 5,
    STDOUT = 6,
    STDERR = 7,
    DATA = 8,
    GET_VALUES = 9,
    GET_VALUES_RESULT = 10,
    UNKNOWN_TYPE = 11,
};

const fcgi_params = enum {
    PATH_INFO,
};

const fcgi_protocol_status = enum(u8) {
    REQUEST_COMPLETE = 0,
    CANT_MPX_CONN = 1,
    OVERLOADED = 2,
    UNKNOWN_ROLE = 3,
};

const fcgi_header = extern struct {
    version: fcgi_version,
    type: fcgi_type,
    request_id: u16,
    content_length: u16,
    padding_length: u8,
    reserved: u8 = 0,
};

const fcgi_request = struct {
    header: fcgi_header,
    body: ?[]u8,

    pub fn deinit(self: *@This(), allocator: Allocator) void {
        if (self.body) |body|
            allocator.free(body);
    }
};

const fcgi_end_body = extern struct {
    app_status: u32,
    protocol_status: fcgi_protocol_status,
    reserve: [3]u8 = .{ 0, 0, 0 },
};

const BodyWriter = struct {
    server: *FastCgiServer,
    writer: Writer,
    type: fcgi_type,
    request_id: u16,

    pub fn drain(w: *Writer, data: []const []const u8, splat: usize) Writer.Error!usize {
        if (data.len == 0) return 0;
        const bw: *BodyWriter = @alignCast(@fieldParentPtr("writer", w));
        var len: usize = 0;

        const buffer = w.buffered();
        if (buffer.len > 0) {
            try bw.server.respond(bw.type, bw.request_id, buffer);
            len += w.consume(buffer.len);
        }

        for (data[0 .. data.len - 1]) |d| {
            if (d.len == 0) continue;
            try bw.server.respond(bw.type, bw.request_id, d);
            len += d.len;
        }

        const pattern = data[data.len - 1];
        if (pattern.len > 0) {
            for (0..splat) |_| {
                try bw.server.respond(bw.type, bw.request_id, pattern);
                len += pattern.len;
            }
        }

        return len;
    }

    pub fn sendFile(w: *Writer, file_reader: *File.Reader, limit: std.Io.Limit) Writer.FileError!usize {
        const bw: *BodyWriter = @alignCast(@fieldParentPtr("writer", w));
        _ = bw;
        _ = file_reader;
        _ = limit;
        return 0;
    }

    pub fn end(bw: *BodyWriter) !void {
        try bw.server.respond(bw.type, bw.request_id, &.{});
        try bw.writer.flush();
    }
};

const FastCgiServer = struct {
    in: *Reader,
    out: *Writer,

    pub fn init(in: *Reader, out: *Writer) @This() {
        return .{
            .in = in,
            .out = out,
        };
    }

    pub fn readRequest(self: *@This(), allocator: Allocator) !fcgi_request {
        var header: fcgi_header = undefined;
        try self.in.readSliceAll(@ptrCast(&header));
        if (native_endian != .big) {
            header.request_id = @byteSwap(header.request_id);
            header.content_length = @byteSwap(header.content_length);
        }

        const body = if (header.content_length > 0)
            try self.in.readAlloc(allocator, header.content_length)
        else
            null;

        if (header.padding_length > 0)
            try self.in.discardAll(header.padding_length);

        log.debug("received {s} request {}", .{ @tagName(header.type), header.request_id });

        return .{
            .header = header,
            .body = body,
        };
    }

    pub fn respond(self: *@This(), ftype: fcgi_type, request_id: u16, bytes: []const u8) !void {
        const net_request_id = if (native_endian != .big)
            @byteSwap(request_id)
        else
            request_id;

        const net_content_length: u16 =
            if (native_endian != .big)
                @byteSwap(@as(u16, @intCast(bytes.len)))
            else
                @intCast(bytes.len);

        var header: fcgi_header = .{
            .version = .VERSION_1,
            .type = ftype,
            .request_id = net_request_id,
            .content_length = net_content_length,
            .padding_length = 0,
            .reserved = 0,
        };

        log.debug("send {s} request {}", .{ @tagName(ftype), request_id });

        try self.out.writeAll(@ptrCast(&header));

        if (bytes.len > 0)
            try self.out.writeAll(bytes);

        try self.out.flush();
    }

    pub fn respondStreaming(self: *@This(), buffer: []u8, ftype: fcgi_type, request_id: u16) BodyWriter {
        return .{
            .server = self,
            .type = ftype,
            .request_id = request_id,
            .writer = .{
                .buffer = buffer,
                .vtable = &.{
                    .drain = BodyWriter.drain,
                    //.sendFile = BodyWriter.sendFile,
                },
            },
        };
    }

    pub fn completeRequest(self: *@This(), request_id: u16, end_body: fcgi_end_body) !void {
        try self.respond(.END_REQUEST, request_id, @ptrCast(&end_body));
    }
};

pub fn main() !void {
    var root_dir = try core.getRoot();
    defer root_dir.close();

    const socket_path = core.config.fcgi_socket_path;

    posix.unlink(socket_path) catch |err|
        switch (err) {
            error.FileNotFound => {},
            else => return err,
        };

    const addr = try Address.initUnix(socket_path);
    var server = try Address.listen(addr, .{});
    defer server.deinit();

    lockdown.lockdown_dir(root_dir);

    log.info("Starting FastCGI session at {s}", .{socket_path});

    var recv_buffer: [1024]u8 = undefined;
    var send_buffer: [100]u8 = undefined;

    while (true) {
        const connection = try server.accept();
        defer connection.stream.close();

        log.debug("received connection", .{});

        var connection_br = connection.stream.reader(&recv_buffer);
        var connection_bw = connection.stream.writer(&send_buffer);

        var fastcgi_server: FastCgiServer = .init(connection_br.interface(), &connection_bw.interface);
        processRequests(root_dir, &fastcgi_server) catch |err| log.err("failed to handle request: {s}", .{@errorName(err)});
    }
}

fn processRequests(root_dir: std.fs.Dir, server: *FastCgiServer) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var params_done: bool = false;
    var stdin_done: bool = false;

    var path: ?[]u8 = null;

    while (true) {
        var request = try server.readRequest(allocator);
        defer request.deinit(allocator);

        switch (request.header.type) {
            .ABORT_REQUEST => return,
            .PARAMS => if (request.body) |body| {
                var params_reader = Reader.fixed(body);
                var lens: [2]u32 = undefined;
                read_params: while (true) {
                    for (&lens) |*len| {
                        const byte = params_reader.peekByte() catch |err| switch (err) {
                            error.EndOfStream => break :read_params,
                            else => return err,
                        };

                        if ((byte >> 7) == 1) {
                            // 4 bytes long
                            const bytes = try params_reader.take(4);
                            const sizep: *u32 = @ptrCast(@alignCast(bytes.ptr));
                            if (native_endian != .big)
                                sizep.* = @byteSwap(sizep.*);
                            len.* = sizep.*;
                        } else {
                            // 1 byte long
                            len.* = byte;
                            params_reader.toss(1);
                        }
                    }

                    const name = try params_reader.take(lens[0]);
                    const value = try params_reader.take(lens[1]);

                    const param = std.meta.stringToEnum(fcgi_params, name) orelse continue;
                    switch (param) {
                        .PATH_INFO => {
                            assert(path == null);
                            path = try allocator.dupe(u8, value);
                        },
                    }
                }
            } else {
                params_done = true;
                log.debug("PARAMS complete", .{});
            },
            .STDIN => if (request.header.content_length == 0) {
                stdin_done = true;
                log.debug("STDIN complete", .{});
            },
            else => {},
        }

        if (params_done and stdin_done) {
            log.info("Request fully received, sending response", .{});

            // Streaming (incomplete)
            {
                var response_buffer: [1024]u8 = undefined;
                var response = server.respondStreaming(&response_buffer, .STDOUT, request.header.request_id);
                defer response.end() catch {};

                const writer = &response.writer;
                const sane_path = try std.fs.path.resolvePosix(allocator, &[_][]const u8{ "/", path orelse "/" });
                defer allocator.free(sane_path);

                try writer.writeAll("Status: 200 OK\r\n");
                if (core.isAsset(sane_path)) {
                    try writer.print("Content-Type: {s}\n", .{MimeType.fromPath(sane_path).contentType()});
                    try writer.print("Cache-Control: max-age={}\n", .{CACHE_AGE});
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

            try server.completeRequest(request.header.request_id, .{
                .app_status = 0,
                .protocol_status = .REQUEST_COMPLETE,
            });

            return;
        }
    }
}
