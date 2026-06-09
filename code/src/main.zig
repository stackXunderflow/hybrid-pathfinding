const std = @import("std");
const Allocator = std.mem.Allocator;

const cli = @import("cli");
const planner = @import("planner.zig");
const server = @import("server.zig");

pub fn readScene(allocator: Allocator, io: std.Io, path: []const u8) !std.json.Parsed(planner.Input) {
    const file = try std.Io.Dir.cwd().openFile(io, path, .{ .mode = .read_only });
    var json: std.Io.Writer.Allocating = .init(allocator);
    defer json.deinit();
    var buffer: [4096]u8 = undefined;
    var reader = file.reader(io, &buffer);
    _ = try reader.interface.streamRemaining(&json.writer);

    return try std.json.parseFromSlice(planner.Input, allocator, json.written(), .{});
}

fn output(io: std.Io, content: []const u8) !void {
    var buffer: [1024]u8 = undefined;
    var stdout = std.Io.File.stdout();
    var writer = stdout.writer(io, &buffer);
    try writer.interface.writeAll(content);
    try writer.flush();
}

var config = struct {
    scene_path: []const u8 = "",
    serve: bool = false,
    port: u16 = 8080,
}{};

var ginit: std.process.Init = undefined;

pub fn main(init: std.process.Init) !void {
    ginit = init;
    var r = cli.AppRunner.init(&init);
    defer r.deinit();

    const app = cli.App{
        .command = cli.Command{
            .name = "hybrid-pathfinding",
            .options = try r.allocOptions(&.{
                .{
                    .long_name = "scene",
                    .help = "Путь до сцены",
                    .value_ref = r.mkRef(&config.scene_path),
                },
                .{
                    .long_name = "serve",
                    .help = "Запустить HTTP сервер",
                    .value_ref = r.mkRef(&config.serve),
                },
                .{
                    .long_name = "port",
                    .help = "Порт для HTTP сервера",
                    .value_ref = r.mkRef(&config.port),
                },
            }),
            .target = .{ .action = .{ .exec = run } },
        },
    };

    return r.run(&app);
}

fn run() !void {
    if (config.serve) {
        try server.start(ginit.io, ginit.gpa, config.port);
    } else {
        var arena = std.heap.ArenaAllocator.init(ginit.gpa);
        defer arena.deinit();
        const allocator = arena.allocator();
        const parsed = try readScene(allocator, ginit.io, config.scene_path);
        const json = try planner.plan(ginit.io, ginit.gpa, allocator, parsed.value);
        try output(ginit.io, json);
    }
}

test {
    _ = @import("dbg.zig");
    _ = @import("common.zig");
}
