const std = @import("std");
const Allocator = std.mem.Allocator;

const cli = @import("cli");
const code = @import("code");

const common = @import("common.zig");
const Robot = common.Robot;
const Point = common.Point2;
const Mesh = common.Mesh;
const Blob = common.Blob;
const AABB = common.AABB;
const SceneBorders = common.SceneBorders;
const dbg = @import("dbg.zig");
const global = @import("global.zig");
const BlobContent = global.BlobContent;
const pathfinding = @import("pathfinding.zig");

const SceneJson = struct {
    robot: Robot,
    borders: SceneBorders,
    meshs: []const Mesh,
};

pub fn readScene(allocator: Allocator, io: std.Io, path: []const u8) !std.json.Parsed(SceneJson) {
    const file = try std.Io.Dir.cwd().openFile(io, path, .{ .mode = .read_only });
    var json: std.Io.Writer.Allocating = .init(allocator);
    defer json.deinit();
    var buffer: [128]u8 = undefined;
    var reader = file.reader(io, &buffer);
    _ = try reader.interface.streamRemaining(&json.writer);

    return try std.json.parseFromSlice(SceneJson, allocator, json.written(), .{});
}

const Output = struct {
    robot: Robot,
    borders: SceneBorders,
    blobs: []const BlobContent,
    debug: ?[]const dbg.DebugLayout,
};

fn output(io: std.Io, content: Output) !void {
    var buffer: [1024]u8 = undefined;
    var stdout = std.Io.File.stdout();
    var writer = stdout.writer(io, &buffer);
    var stringify = std.json.Stringify{ .writer = &writer.interface, .options = .{ .whitespace = .indent_4, .emit_null_optional_fields = false } };
    try stringify.write(content);
    try writer.flush();
}

var config = struct {
    scene_path: []const u8 = "",
}{};

var ginit: std.process.Init = undefined;

pub fn main(init: std.process.Init) !void {
    ginit = init;
    var r = cli.AppRunner.init(&init);
    defer r.deinit();

    const app = cli.App{ .command = cli.Command{ .name = "scene", .options = try r.allocOptions(&.{.{ .long_name = "scene", .help = "Путь до сцены", .value_ref = r.mkRef(&config.scene_path) }}), .target = cli.CommandTarget{ .action = cli.CommandAction{ .exec = run } } } };

    return r.run(&app);
}

fn run() !void {
    var arena = std.heap.ArenaAllocator.init(ginit.gpa);
    defer arena.deinit();
    const allocator = arena.allocator();

    var debugger = try dbg.Debugger.init(ginit.gpa);
    defer debugger.deinit();

    const parsed = try readScene(allocator, ginit.io, config.scene_path);

    const globalGeometry = try global.globalGeometry(ginit.gpa, parsed.value.meshs, parsed.value.robot.radius);
    defer globalGeometry.arena.deinit();

    try pathfinding.findPath(ginit.gpa, &debugger, parsed.value.robot, globalGeometry.blobs);

    {
        const blob_boundary = @import("local/blob_boundary_points.zig");

        for (globalGeometry.blobs, 0..) |blob, i| {
            const layer_name = std.fmt.allocPrint(allocator, "blob_{d}_boundary", .{i}) catch continue;
            defer allocator.free(layer_name);

            const boundary_points = try blob_boundary.generateBlobBoundaryPoints(
                ginit.gpa,
                blob.blob,
                0.02,
            );

            for (boundary_points) |point| {
                try debugger.point(point, .{ .layout = layer_name });
            }
        }
    }

    {
        const expand_mesh = @import("local/expand_mesh.zig");
        const blob_boundary = @import("local/blob_boundary_points.zig");
        const intersection = @import("local/intersection.zig");
        const danger_len = parsed.value.robot.radius * common.constants.LOCAL_GEOMETRY_DANGER_DELTA;

        for (globalGeometry.blobs, 0..) |blob, i| {
            const expanded_aabbs = try ginit.gpa.alloc(AABB, blob.meshs.len);
            defer ginit.gpa.free(expanded_aabbs);
            for (blob.meshs, 0..) |mesh, k| {
                expanded_aabbs[k] = AABB.fromPoints(mesh.points).expand(danger_len);
            }

            for (blob.meshs, 0..) |mesh, j| {
                const layer_name = std.fmt.allocPrint(allocator, "blob_{d}_mesh_{d}_expanded", .{ i, j }) catch continue;
                defer allocator.free(layer_name);

                const fill_layer_name = std.fmt.allocPrint(allocator, "blob_{d}_mesh_{d}_expanded_fill", .{ i, j }) catch continue;
                defer allocator.free(fill_layer_name);

                const points_layer_name = std.fmt.allocPrint(allocator, "blob_{d}_mesh_{d}_expanded_points", .{ i, j }) catch continue;
                defer allocator.free(points_layer_name);

                const expanded = try expand_mesh.expandMesh(ginit.gpa, mesh, danger_len);
                defer ginit.gpa.free(expanded);

                try debugger.mesh(expanded, .{ .layout = fill_layer_name });

                for (expanded[0 .. expanded.len - 1], expanded[1..]) |from, to| {
                    try debugger.line(from, to, .{ .layout = layer_name });
                }
                try debugger.line(expanded[expanded.len - 1], expanded[0], .{ .layout = layer_name });

                const expanded_blob = Blob.fromPoints(expanded);
                const boundary_points = try blob_boundary.generateBlobBoundaryPoints(ginit.gpa, expanded_blob, 0.02);
                defer ginit.gpa.free(boundary_points);

                for (boundary_points) |point| {
                    if (intersection.isValidPoint(point, danger_len, blob, expanded_aabbs)) {
                        try debugger.point(point, .{ .layout = points_layer_name });
                    }
                }
            }
        }
    }

    {
        const local_debug = @import("local/debug_points.zig");

        for (globalGeometry.blobs, 0..) |blob, i| {
            const layer_name = std.fmt.allocPrint(allocator, "blob_{d}_halton", .{i}) catch continue;
            defer allocator.free(layer_name);

            const generated = try local_debug.generatePoints(
                ginit.gpa,
                blob,
                parsed.value.robot.radius,
                0.001,
                0.02,
                42,
            );

            for (generated.halton) |point| {
                try debugger.point(point, .{ .layout = layer_name });
            }

            for (generated.obstacles) |o| {
                for (o) |point| {
                    try debugger.point(point, .{ .layout = layer_name });
                }
            }
        }
    }
    try output(ginit.io, .{ .robot = parsed.value.robot, .borders = parsed.value.borders, .blobs = globalGeometry.blobs, .debug = debugger.layouts.items });
}

test {
    _ = @import("dbg.zig");
    _ = @import("common.zig");
}
