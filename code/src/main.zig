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
    var buffer: [4096]u8 = undefined;
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
    const robot = parsed.value.robot;

    const clock = std.Io.Clock.awake;

    const global_start = std.Io.Timestamp.now(ginit.io, clock);
    const globalGeometry = try global.globalGeometry(ginit.gpa, parsed.value.meshs, robot.radius);
    defer globalGeometry.arena.deinit();
    const global_end = std.Io.Timestamp.now(ginit.io, clock);
    const global_elapsed = global_start.durationTo(global_end);

    const local_start = std.Io.Timestamp.now(ginit.io, clock);
    const localGeometry = try allocator.alloc(local.LocalGeometry, globalGeometry.blobs.len);

    const density = common.constants.POINTS_DENSITY_PER_ROBOT_AREA / (std.math.pi * robot.radius * robot.radius);
    std.debug.print("DENSITY: {}", .{density});

    for (globalGeometry.blobs, 0..) |blob, i| {
        localGeometry[i] = try local.localGeometry(ginit.gpa, blob, robot, density, 42);
        for (localGeometry[i].triang.points.items) |p| {
            try debugger.point(p, .{});
        }
    }
    defer {
        for (localGeometry) |lg| {
            lg.arena.deinit();
        }
    }
    const local_end = std.Io.Timestamp.now(ginit.io, clock);
    const local_elapsed = local_start.durationTo(local_end);

    const pf_start = std.Io.Timestamp.now(ginit.io, clock);
    const pf_result = try pathfinding.findPath(ginit.gpa, &debugger, robot, globalGeometry, localGeometry);
    const pf_end = std.Io.Timestamp.now(ginit.io, clock);
    const pf_elapsed = pf_start.durationTo(pf_end);

    std.log.info("PF RESULT: {}", .{pf_result});

    std.log.debug("global: {d:.6}s", .{@as(f64, @floatFromInt(global_elapsed.nanoseconds)) / @as(f64, std.time.ns_per_s)});
    std.log.debug("local: {d:.6}s", .{@as(f64, @floatFromInt(local_elapsed.nanoseconds)) / @as(f64, std.time.ns_per_s)});
    std.log.debug("pathfinding: {d:.6}s", .{@as(f64, @floatFromInt(pf_elapsed.nanoseconds)) / @as(f64, std.time.ns_per_s)});

    try output(ginit.io, .{ .robot = robot, .borders = parsed.value.borders, .blobs = globalGeometry.blobs, .debug = debugger.layouts.items });
}

test {
    _ = @import("dbg.zig");
    _ = @import("common.zig");
}
