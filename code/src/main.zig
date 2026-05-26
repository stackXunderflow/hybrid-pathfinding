const std = @import("std");
const Allocator = std.mem.Allocator;

const code = @import("code");

const common = @import("common.zig");
const Point = common.Point;
const Mesh = common.Mesh;
const ui = @import("ui.zig");

const SceneJson = struct {
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

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.gpa);
    defer init.gpa.free(args);

    const parsed = try readScene(init.gpa, init.io, "scene.json");
    defer parsed.deinit();

    const blobs: []const Mesh = &[0]Mesh{};
    try ui.showBlocking(init.gpa, args, .{ .meshs = parsed.value.meshs, .blobs = blobs });
}
