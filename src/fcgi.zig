const std = @import("std");
const builtin = @import("builtin");

const log = std.log;
const posix = std.posix;
const net = std.net;
const mem = std.mem;
const Address = net.Address;
const Server = net.Server;
const Io = std.Io;
const Reader = Io.Reader;
const Writer = Io.Writer;
const Allocator = mem.Allocator;
const File = std.fs.File;
const Limit = Io.Limit;
const native_endian = builtin.target.cpu.arch.endian();
const assert = std.debug.assert;
const maxInt = std.math.maxInt;
const core = @import("core");

const MimeType = @import("Mime.zig").Type;
const lockdown = @import("lockdown.zig");

// 30 minutes
const CACHE_AGE = 60 * 30;
const MAX_REQUESTS = 10;

const is_debug = switch (builtin.mode) {
    .Debug, .ReleaseSafe => true,
    .ReleaseFast, .ReleaseSmall => false,
};

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

const fcgi_role = enum(u16) {
    RESPONDER = 1,
    AUTHORIZER = 2,
    FILTER = 3,
};

const fcgi_flags = packed struct(u8) {
    KEEP_CONN: bool,
    reserved: u7,
};

const fcgi_header = extern struct {
    version: fcgi_version,
    type: fcgi_type,
    request_id: u16,
    content_length: u16,
    padding_length: u8,
    reserved: u8 = 0,
};

const fcgi_end_body = extern struct {
    app_status: u32,
    protocol_status: fcgi_protocol_status,
    reserve: [3]u8 = .{ 0, 0, 0 },
};

const fcgi_begin_body = extern struct {
    role: fcgi_role,
    flags: fcgi_flags,
    reserved: [5]u8,
};

const fcgi_request = struct {
    header: fcgi_header,
    bytes: ?[]u8,

    pub fn deinit(self: *@This(), allocator: Allocator) void {
        if (self.bytes) |bytes|
            allocator.free(bytes);
    }

    pub inline fn bytesToValue(self: *@This(), comptime T: type) T {
        assert(self.bytes != null);
        var V: T = mem.bytesToValue(T, self.bytes.?);
        if (native_endian != .big) std.mem.byteSwapAllFields(T, &V);
        return V;
    }
};

const fcgi_request_state = struct {
    path: ?[]u8 = null,
    params_done: bool = false,
    stdin_done: bool = false,

    fn receiveComplete(self: *@This()) bool {
        return self.params_done and self.stdin_done;
    }

    fn deinit(self: *@This(), allocator: Allocator) void {
        if (self.path) |path|
            allocator.free(path);
    }

    fn reset(self: *@This(), allocator: Allocator) void {
        self.deinit(allocator);
        self.* = @This(){};
    }
};

const BodyWriter = struct {
    server: *FastCgiServer,
    writer: Writer,
    type: fcgi_type,
    request_id: u16,

    pub fn drain(w: *Writer, data: []const []const u8, splat: usize) Writer.Error!usize {
        const bw: *BodyWriter = @alignCast(@fieldParentPtr("writer", w));
        const data_len = w.end + Writer.countSplat(data, splat);
        const data_limit: Limit = .limited(@min(data_len, maxInt(u16)));

        log.debug("streaming buffered {s} request {} size={}", .{ @tagName(bw.type), bw.request_id, data_limit.toInt().? });

        try bw.server.respondHeader(bw.type, bw.request_id, @intCast(data_limit.toInt() orelse unreachable));
        const n = try bw.server.out.writeSplatHeaderLimit(w.buffered(), data, splat, data_limit);
        return w.consume(n);
    }

    pub fn sendFile(w: *Writer, file_reader: *File.Reader, limit: Limit) Writer.FileError!usize {
        const bw: *BodyWriter = @alignCast(@fieldParentPtr("writer", w));
        const data_len = Writer.countSendFileLowerBound(w.end, file_reader, limit) orelse return error.Unimplemented;
        const data_limit: Limit = .limited(@min(data_len, maxInt(u16)));

        log.debug("streaming raw {s} request {} size={}", .{ @tagName(bw.type), bw.request_id, data_limit.toInt().? });

        try bw.server.respondHeader(bw.type, bw.request_id, @intCast(data_limit.toInt() orelse unreachable));
        const n = if (data_limit.subtract(w.buffered().len)) |sendfile_limit|
            try bw.server.out.sendFileHeader(w.buffered(), file_reader, sendfile_limit.min(limit))
        else
            try bw.server.out.write(data_limit.slice(w.buffered()));

        return w.consume(n);
    }

    pub fn end(bw: *BodyWriter) !void {
        try bw.writer.flush();
        try bw.server.respondEmpty(bw.type, bw.request_id);
    }
};

const FastCgiServer = struct {
    in: *Reader,
    out: *Writer,

    const RequestError = Reader.ReadAllocError;
    const ResponseError = Writer.Error;

    pub fn init(in: *Reader, out: *Writer) @This() {
        return .{
            .in = in,
            .out = out,
        };
    }

    pub fn readRequest(self: *@This(), allocator: Allocator) RequestError!fcgi_request {
        const header = try self.in.takeStruct(fcgi_header, .big);
        const bytes = if (header.content_length > 0)
            try self.in.readAlloc(allocator, header.content_length)
        else
            null;

        if (header.padding_length > 0)
            try self.in.discardAll(header.padding_length);

        log.debug("received {s} request {}", .{ @tagName(header.type), header.request_id });

        return .{
            .header = header,
            .bytes = bytes,
        };
    }

    pub fn endRequest(self: *@This(), request_id: u16, end_body: fcgi_end_body) ResponseError!void {
        try self.respond(.END_REQUEST, request_id, @ptrCast(&end_body));
    }

    pub fn respond(self: *@This(), ftype: fcgi_type, request_id: u16, bytes: []const u8) ResponseError!void {
        if (bytes.len == 0)
            return;

        log.debug("sending {s} request {} size={}", .{ @tagName(ftype), request_id, bytes.len });

        var i: usize = 0;
        while (i < bytes.len) {
            const end = @min(i + maxInt(u16), bytes.len);
            defer i = end;
            const chunk = bytes[i..end];
            assert(chunk.len > 0);

            log.debug("send {s} request {}", .{ @tagName(ftype), request_id });

            try self.respondHeader(ftype, request_id, @intCast(chunk.len));
            if (chunk.len > 0)
                try self.out.writeAll(chunk);
        }
        try self.out.flush();
    }

    pub fn respondEmpty(self: *@This(), ftype: fcgi_type, request_id: u16) ResponseError!void {
        try self.respondHeader(ftype, request_id, 0);
        try self.out.flush();
        log.debug("completed {s} request {}", .{ @tagName(ftype), request_id });
    }

    pub fn respondHeader(self: *@This(), ftype: fcgi_type, request_id: u16, content_length: u16) ResponseError!void {
        const header: fcgi_header = .{
            .version = .VERSION_1,
            .type = ftype,
            .request_id = request_id,
            .content_length = content_length,
            .padding_length = 0,
            .reserved = 0,
        };

        try self.out.writeStruct(header, .big);
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
                    .sendFile = BodyWriter.sendFile,
                },
            },
        };
    }
};

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

pub fn main() !void {
    defer if (is_debug) {
        _ = debug_allocator.deinit();
    };

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
    var send_buffer: [2048]u8 = undefined;

    while (true) {
        const connection = try server.accept();
        defer connection.stream.close();

        log.debug("received connection", .{});

        var connection_br = connection.stream.reader(&recv_buffer);
        var connection_bw = connection.stream.writer(&send_buffer);

        var fastcgi_server: FastCgiServer = .init(connection_br.interface(), &connection_bw.interface);
        processRequests(root_dir, &fastcgi_server) catch |err| {
            log.err("failed to handle request: {s}", .{@errorName(err)});
            if (builtin.mode == .Debug)
                std.debug.dumpStackTrace(@errorReturnTrace().?.*);
        };
    }
}

fn processRequests(root_dir: std.fs.Dir, server: *FastCgiServer) !void {
    const base_allocator = gpa: {
        if (builtin.target.os.tag == .wasi) break :gpa .{ std.heap.wasm_allocator, false };
        break :gpa if (is_debug) debug_allocator.allocator() else std.heap.page_allocator;
    };
    defer if (is_debug) {
        _ = debug_allocator.detectLeaks();
    };

    var arena = std.heap.ArenaAllocator.init(base_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var keep_connection: bool = true;

    var request_states: [MAX_REQUESTS]fcgi_request_state = undefined;
    defer for (&request_states) |*state| state.deinit(allocator);
    @memset(&request_states, .{});

    while (true) {
        var request = try server.readRequest(allocator);
        defer request.deinit(allocator);

        const request_id = request.header.request_id;
        const state = &request_states[request_id];

        switch (request.header.type) {
            .BEGIN_REQUEST => {
                if (request.bytes) |_| {
                    log.info("begin request {}", .{request_id});

                    const request_begin_body = request.bytesToValue(fcgi_begin_body);
                    keep_connection = request_begin_body.flags.KEEP_CONN;
                    if (request_begin_body.role != .RESPONDER) {
                        log.err("received invalid role expected: {s}, got: {s}", .{ @tagName(fcgi_role.RESPONDER), @tagName(request_begin_body.role) });

                        try server.endRequest(request_id, .{
                            .app_status = 0,
                            .protocol_status = .REQUEST_COMPLETE,
                        });

                        return;
                    }
                } else {
                    log.err("received {s} without body", .{@tagName(request.header.type)});
                }
            },
            .ABORT_REQUEST => {
                log.debug("aborting request {}", .{request_id});
                try server.endRequest(request_id, .{
                    .app_status = 0,
                    .protocol_status = .UNKNOWN_ROLE,
                });

                state.reset(allocator);
                continue;
            },
            .PARAMS => if (request.bytes) |bytes| {
                var params_reader = Reader.fixed(bytes);
                var lens: [2]u32 = undefined;
                read_params: while (true) {
                    for (&lens) |*len| {
                        const byte = params_reader.peekByte() catch |err| switch (err) {
                            error.EndOfStream => break :read_params,
                            else => return err,
                        };

                        if ((byte >> 7) == 1) {
                            // 4 bytes long
                            const big_size = try params_reader.takeInt(u32, .big);
                            len.* = big_size;
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
                            assert(state.path == null);
                            state.path = try allocator.dupe(u8, value);
                        },
                    }
                }
            } else {
                state.params_done = true;
                log.info("received parameters for {} path={?s}", .{ request_id, state.path });
            },
            .STDIN => if (request.header.content_length == 0) {
                state.stdin_done = true;
                log.info("received stdin for {}", .{request_id});
            },
            else => {
                log.err("Unknown request type {s}", .{@tagName(request.header.type)});
            },
        }

        if (state.receiveComplete()) {
            {
                var response_buffer: [1024]u8 = undefined;
                var response = server.respondStreaming(&response_buffer, .STDOUT, request_id);
                defer response.end() catch {};

                const writer = &response.writer;
                const sane_path = try std.fs.path.resolvePosix(allocator, &[_][]const u8{ "/", state.path orelse "/" });
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

            log.info("ending request {}", .{request_id});
            try server.endRequest(request_id, .{
                .app_status = 0,
                .protocol_status = .REQUEST_COMPLETE,
            });

            state.reset(allocator);
            log.debug("reset request state {}", .{request_id});

            if (!keep_connection) {
                log.info("closing connection at request of client", .{});
                return;
            }
        }
    }
}
