const std = @import("std");
const Allocator = std.mem.Allocator;
const planner = @import("planner.zig");

const server_buf_size = 8192;

pub fn start(io: std.Io, gpa: Allocator, port: u16) !void {
    const address = try std.Io.net.IpAddress.parse("0.0.0.0", port);
    var tcp_server = try address.listen(io, .{ .reuse_address = true });
    defer tcp_server.deinit(io);

    var read_buf: [server_buf_size]u8 = undefined;
    var write_buf: [server_buf_size]u8 = undefined;
    var transfer_buf: [server_buf_size]u8 = undefined;

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();

    while (true) {
        _ = arena.reset(.free_all);
        const allocator = arena.allocator();

        const stream = tcp_server.accept(io) catch |err| switch (err) {
            error.ConnectionAborted, error.BlockedByFirewall => continue,
            else => |e| return e,
        };
        defer stream.close(io);

        var conn_reader = stream.reader(io, &read_buf);
        var conn_writer = stream.writer(io, &write_buf);

        var http_server = std.http.Server.init(&conn_reader.interface, &conn_writer.interface);

        handleClient(allocator, io, &http_server, &transfer_buf) catch |err| {
            switch (err) {
                error.HttpConnectionClosing => continue,
                else => {},
            }
        };
    }
}

fn handleClient(allocator: Allocator, io: std.Io, http_server: *std.http.Server, transfer_buf: []u8) !void {
    var request = try http_server.receiveHead();

    if (request.head.method != .POST or !std.mem.eql(u8, request.head.target, "/solve")) {
        try request.respond("{\"error\":\"not found\"}", .{ .status = .not_found });
        return;
    }

    var body_alloc: std.Io.Writer.Allocating = .init(allocator);
    defer body_alloc.deinit();

    var body_reader = request.readerExpectNone(transfer_buf);
    _ = try body_reader.streamRemaining(&body_alloc.writer);
    const body = body_alloc.written();

    const parsed = std.json.parseFromSlice(planner.Input, allocator, body, .{}) catch |err| {
        const msg = try std.fmt.allocPrint(allocator, "{{\"error\":\"invalid json: {}\"}}", .{err});
        try request.respond(msg, .{ .status = .bad_request });
        return;
    };

    const scene_input = parsed.value;

    const result = planner.plan(io, allocator, allocator, scene_input) catch |err| {
        const msg = try std.fmt.allocPrint(allocator, "{{\"error\":\"plan failed: {}\"}}", .{err});
        try request.respond(msg, .{ .status = .internal_server_error });
        return;
    };

    try request.respond(result, .{ .status = .ok });
}
