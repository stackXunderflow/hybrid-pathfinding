const std = @import("std");
const Allocator = std.mem.Allocator;

const cli = @import("cli");
const code = @import("code");

const TimeStamp = std.Io.Timestamp;
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

const Input = struct {
    robot: Robot,
    borders: SceneBorders,
    meshs: []const Mesh,
};

pub fn readScene(allocator: Allocator, io: std.Io, path: []const u8) !std.json.Parsed(Input) {
    const file = try std.Io.Dir.cwd().openFile(io, path, .{ .mode = .read_only });
    var json: std.Io.Writer.Allocating = .init(allocator);
    defer json.deinit();
    var buffer: [4096]u8 = undefined;
    var reader = file.reader(io, &buffer);
    _ = try reader.interface.streamRemaining(&json.writer);

    return try std.json.parseFromSlice(Input, allocator, json.written(), .{});
}

pub const Output = struct {
    time_report: []const u8,
    robot: Robot,
    result: Result,
    triangulations: []const ?AbstractStruct,
    graphs: []const ?AbstractStruct,
    borders: SceneBorders,
    blobs: []const BlobContent,
    debug: ?[]const dbg.DebugLayout,

    pub const Result = union(enum) {
        ok: struct {
            points: []const Point,
            types: []const pathfinding.PointType,
            length: f32,
        },
        err: enum {
            start_blocked,
            end_blocked,
            no_path,
        },
    };

    pub const AbstractStruct = struct {
        points: []const Point,
        indices: []const u32,
    };
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

const TimeReport = struct {
    const clock = std.Io.Clock.awake;

    io: std.Io,
    global_start: ?TimeStamp = null,
    global_end: ?TimeStamp = null,
    local_start: ?TimeStamp = null,
    local_end: ?TimeStamp = null,
    pf_start: ?TimeStamp = null,
    pf_end: ?TimeStamp = null,

    pub fn now(self: TimeReport) TimeStamp {
        return .now(self.io, clock);
    }

    fn seconds(from: TimeStamp, to: TimeStamp) f64 {
        return @as(f64, @floatFromInt(from.durationTo(to).nanoseconds)) / @as(f64, std.time.ns_per_s);
    }

    pub fn toString(self: TimeReport, allocator: Allocator) ![]const u8 {
        return std.fmt.allocPrint(allocator, "Global: {d:.6}s  Local: {d:.6}s  Pf: {d:.6}s  Total: {d:.6}s", .{
            seconds(self.global_start.?, self.global_end.?),
            seconds(self.local_start.?, self.local_end.?),
            seconds(self.pf_start.?, self.pf_end.?),
            seconds(self.global_start.?, self.pf_end.?),
        });
    }
};

fn run() !void {
    var arena = std.heap.ArenaAllocator.init(ginit.gpa);
    defer arena.deinit();
    const allocator = arena.allocator();

    var debugger = try dbg.Debugger.init(ginit.gpa);
    defer debugger.deinit();

    const parsed = try readScene(allocator, ginit.io, config.scene_path);
    const robot = parsed.value.robot;

    var report: TimeReport = .{ .io = ginit.io };

    report.global_start = report.now();
    const globalGeometry = try global.globalGeometry(ginit.gpa, parsed.value.meshs, robot.radius);
    defer globalGeometry.arena.deinit();
    report.global_end = report.now();

    report.local_start = report.now();
    const localGeometry = try allocator.alloc(local.LocalGeometry, globalGeometry.blobs.len);

    const density = common.constants.POINTS_DENSITY_PER_ROBOT_AREA / (std.math.pi * robot.radius * robot.radius);

    for (globalGeometry.blobs, 0..) |blob, i| {
        localGeometry[i] = try local.localGeometry(ginit.gpa, blob, @truncate(i), robot, density, 42);
    }
    defer {
        for (localGeometry) |lg| {
            lg.arena.deinit();
        }
    }
    report.local_end = report.now();

    report.pf_start = report.now();
    const pf_result = try pathfinding.findPath(ginit.gpa, &debugger, robot, globalGeometry, localGeometry);
    report.pf_end = report.now();

    const triangulations = try allocator.alloc(?Output.AbstractStruct, globalGeometry.blobs.len);
    const graphs = try allocator.alloc(?Output.AbstractStruct, globalGeometry.blobs.len);

    for (localGeometry, 0..) |lg, i| {
        triangulations[i] = try lg.triang.asOutputAbstract(allocator);
        graphs[i] = try lg.graph.asOutputAbstract(allocator);
    }

    try output(ginit.io, .{
        .time_report = try report.toString(allocator),
        .result = try pf_result.asOutputResult(allocator),
        .graphs = graphs,
        .triangulations = triangulations,
        .robot = robot,
        .borders = parsed.value.borders,
        .blobs = globalGeometry.blobs,
        .debug = if (@import("builtin").mode == .Debug) debugger.layouts.items else null,
    });
}

test {
    _ = @import("dbg.zig");
    _ = @import("common.zig");
}
