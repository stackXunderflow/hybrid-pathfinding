const std = @import("std");
const Allocator = std.mem.Allocator;

const cli = @import("cli");
const code = @import("code");

const common = @import("common.zig");
const Point = common.Point2;
const Mesh = common.Mesh;
const dbg = @import("dbg.zig");
const global = @import("global.zig");
const BlobContent = global.BlobContent;

const Robot = struct { radius: f32, start: Point, end: Point };

const SceneJson = struct {
    robot: Robot,
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
    blobs: []const BlobContent,
    debug: ?[]const dbg.DebugLayout,
};

fn output(io: std.Io, content: Output) !void {
    var buffer: [1024]u8 = undefined;
    var stdout = std.Io.File.stdout();
    var writer = stdout.writer(io, &buffer);
    var stringify = std.json.Stringify{ .writer = &writer.interface, .options = .{ .whitespace = .indent_4 } };
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

    // Проверка: генерация точек внутри AABB каждого Blob
    {
        const local_debug = @import("local/debug_points.zig");

        for (globalGeometry.blobs, 0..) |blob, i| {
            const layer_name = std.fmt.allocPrint(allocator, "blob_{d}_halton", .{i}) catch continue;
            defer allocator.free(layer_name);

            try local_debug.addHaltonPointsInBlobAABB(
                ginit.gpa,
                &debugger,
                blob,
                parsed.value.robot.start,
                parsed.value.robot.end,
                parsed.value.robot.radius,
                0.002, // плотность внутри AABB (чуть меньше для комфортной визуализации)
                42 + @as(u64, i),
                layer_name,
            );
        }
    }
    // тут заканчивается
    try output(ginit.io, .{ .robot = parsed.value.robot, .blobs = globalGeometry.blobs, .debug = debugger.layouts.items });
}
