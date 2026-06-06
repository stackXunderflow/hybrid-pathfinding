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
const local = @import("local.zig");
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

    const app = cli.App{
        .command = cli.Command{
            .name = "scene",
            .options = try r.allocOptions(&.{
                .{
                    .long_name = "scene",
                    .help = "Путь до сцены",
                    .value_ref = r.mkRef(&config.scene_path),
                },
            }),
            .target = cli.CommandTarget{
                .action = cli.CommandAction{
                    .exec = run,
                },
            },
        },
    };

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

    for (globalGeometry.blobs, 0..) |blob, i| {
        const layer_name = std.fmt.allocPrint(allocator, "blob_{d}_halton", .{i}) catch continue;
        defer allocator.free(layer_name);

        const localGeometry = try local.localGeometry(
            ginit.gpa,
            blob,
            parsed.value.robot.radius,
            0.001,
            42,
        );

        const tr = try ginit.gpa.alloc(u32, localGeometry.triang.triangles.len * 3);
        for (localGeometry.triang.triangles, 0..) |triangle, j| {
            tr[j * 3] = triangle.nodes[0];
            tr[j * 3 + 1] = triangle.nodes[1];
            tr[j * 3 + 2] = triangle.nodes[2];
        }

        try debugger.triangulation(localGeometry.triang.points.items, tr, .{ .layout = "full" });
    }

    try output(ginit.io, .{ .robot = parsed.value.robot, .borders = parsed.value.borders, .blobs = globalGeometry.blobs, .debug = debugger.layouts.items });
}

test {
    _ = @import("dbg.zig");
    _ = @import("common.zig");
}
