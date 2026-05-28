const std = @import("std");
const Allocator = std.mem.Allocator;

const cli = @import("cli");
const code = @import("code");

const common = @import("common.zig");
const Point = common.Point2;
const Mesh = common.Mesh;
const global = @import("global.zig");

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

const BlobContent = struct {
    blob: Mesh,
    meshs: []const Mesh,
};

const Output = struct {
    robot: Robot,
    blobs: []const BlobContent,
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

    const parsed = try readScene(allocator, ginit.io, config.scene_path);

    var blobs: std.ArrayList(BlobContent) = try .initCapacity(allocator, parsed.value.meshs.len);
    for (parsed.value.meshs) |mesh| {
        const blob = try global.andrewAlgorithm(allocator, mesh);
        const meshs = try allocator.alloc(Mesh, 1);
        meshs[0] = mesh;
        blobs.appendAssumeCapacity(.{ .blob = blob, .meshs = meshs });
    }
    var new_blobs: std.ArrayList(BlobContent) = try .initCapacity(allocator, blobs.items.len);
    for (blobs.items) |blob| {
        const biggerBlob = try global.increaseArea(allocator, blob.blob, parsed.value.robot.radius);
        allocator.free(blob.blob.points);
        const meshs = try allocator.alloc(BlobContent, 1);
        meshs[0] = blob;
        new_blobs.appendAssumeCapacity(.{ .blob = biggerBlob, .meshs = blob.meshs });
    }

    try output(ginit.io, .{ .robot = parsed.value.robot, .blobs = new_blobs.items });
}
