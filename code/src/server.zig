const std = @import("std");
const http = std.http;
const net = std.Io.net;

const common = @import("common.zig");
const Robot = common.Robot;
const Point = common.Point2;
const Mesh = common.Mesh;
const global = @import("global.zig");
const BlobContent = global.BlobContent;
const pathfinding = @import("pathfinding.zig");
const dbg = @import("dbg.zig");

const SceneJson = struct {
    robot: Robot,
    meshs: []const Mesh,
};

const Output = struct {
    robot: Robot,
    blobs: []const BlobContent,
    debug: ?[]const dbg.DebugLayout,
};

pub fn runServer(allocator: std.mem.Allocator, io: std.Io, port: u16) !void {
    var address = net.IpAddress{ .ip4 = net.Ip4Address.loopback(port) };
    var server = try address.listen(io, .{ .reuse_address = true });
    defer server.deinit(io);

    while (true) {
        var stream = try server.accept(io);
        defer stream.close(io);

        var read_buf: [8192]u8 = undefined;
        var write_buf: [8192]u8 = undefined;
        var tcp_reader = stream.reader(io, &read_buf);
        var tcp_writer = stream.writer(io, &write_buf);

        var http_server = http.Server.init(&tcp_reader.interface, &tcp_writer.interface);

        while (true) {
            var request = http_server.receiveHead() catch |err| switch (err) {
                error.HttpConnectionClosing => break,
                else => break,
            };

            if (request.head.method != .POST) break;

            var body_buf: [4096]u8 = undefined;
            var body_reader = try request.readerExpectContinue(&body_buf);
            var body_alloc = std.Io.Writer.Allocating.init(allocator);
            defer body_alloc.deinit();
            _ = try body_reader.streamRemaining(&body_alloc.writer);
            const body = body_alloc.written();

            var parsed = std.json.parseFromSlice(SceneJson, allocator, body, .{}) catch {
                break;
            };
            defer parsed.deinit();

            var debugger = try dbg.Debugger.init(allocator);
            defer debugger.deinit();

            const globalGeometry = try global.globalGeometry(allocator, parsed.value.meshs, parsed.value.robot.radius);
            defer globalGeometry.arena.deinit();

            try pathfinding.findPath(allocator, &debugger, parsed.value.robot, globalGeometry.blobs);

            {
                const local_debug = @import("local/debug_points.zig");

                for (globalGeometry.blobs, 0..) |blob, i| {
                    const layer_name = std.fmt.allocPrint(allocator, "blob_{d}_halton", .{i}) catch continue;
                    defer allocator.free(layer_name);

                    try local_debug.addHaltonPointsInBlobAABB(
                        allocator,
                        &debugger,
                        blob,
                        parsed.value.robot.start,
                        parsed.value.robot.end,
                        parsed.value.robot.radius,
                        0.001,
                        42,
                        layer_name,
                    );
                }
            }

            var output_alloc = std.Io.Writer.Allocating.init(allocator);
            defer output_alloc.deinit();

            var stringify = std.json.Stringify{
                .writer = &output_alloc.writer,
                .options = .{ .whitespace = .indent_4, .emit_null_optional_fields = false },
            };
            try stringify.write(Output{
                .robot = parsed.value.robot,
                .blobs = globalGeometry.blobs,
                .debug = debugger.layouts.items,
            });

            try request.respond(output_alloc.written(), .{
                .status = .ok,
                .keep_alive = request.head.keep_alive,
                .extra_headers = &.{
                    .{ .name = "content-type", .value = "application/json" },
                },
            });
        }
    }
}
