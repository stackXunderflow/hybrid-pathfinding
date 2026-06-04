const std = @import("std");
const Allocator = std.mem.Allocator;

const common = @import("../common.zig");
const Point2 = common.Point2;
const Vec2 = common.Vec2;
const Mesh = common.Mesh;

const intersection = @import("intersection.zig");

pub fn generateOffsetPointsEdge(gpa: Allocator, a: Point2, b: Point2, dangerLen: f32, density: f32) ![]Point2 {
    const vec = Point2.vecTo(a, b);
    const length = vec.len();

    const u = try vec.normilize();
    const n = try u.rotateRight90();
    const offset = n.scale(dangerLen);

    const target_step = 1.0 / density;
    const num_intervals: usize = @max(1, @as(usize, @intFromFloat(@floor(length / target_step))));
    const num_points = num_intervals + 1;

    const points = try gpa.alloc(Point2, num_points);
    for (0..num_points) |i| {
        const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(num_points - 1));
        const base = a.plus(vec.scale(t));
        points[i] = base.plus(offset);
    }
    return points;
}

pub fn generateOffsetPoints(gpa: Allocator, mesh: Mesh, danger_len: f32, density: f32) ![]const Point2 {
    var points: std.ArrayList(Point2) = .empty;
    for (0..mesh.points.len) |i| {
        const p1 = mesh.points[i];
        const p2 = mesh.points[(i + 1) % mesh.points.len];
        const edge_pts = try generateOffsetPointsEdge(gpa, p1, p2, danger_len, density);

        try points.appendSlice(gpa, edge_pts);
    }
    return try points.toOwnedSlice(gpa);
}
