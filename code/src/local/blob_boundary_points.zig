const std = @import("std");
const Allocator = std.mem.Allocator;

const common = @import("../common.zig");
const Point2 = common.Point2;
const Blob = common.Blob;

fn generateEdgePoints(gpa: Allocator, a: Point2, b: Point2, density: f32) ![]const Point2 {
    const vec = Point2.vecTo(a, b);
    const length = vec.len();

    var points: std.ArrayList(Point2) = .empty;
    try points.append(gpa, a);

    const spacing = 1.0 / density;
    const n: usize = @intFromFloat(@floor(length / spacing));

    const u = try vec.normilize();
    const step = length / @as(f32, @floatFromInt(n));

    for (1..n + 1) |i| {
        const t = step * @as(f32, @floatFromInt(i));
        if (t >= length) break;
        try points.append(gpa, a.plus(u.scale(t)));
    }

    return try points.toOwnedSlice(gpa);
}

pub fn generateBlobBoundaryPoints(gpa: Allocator, mesh_points: []const Point2, density: f32) ![]const Point2 {
    var points: std.ArrayList(Point2) = .empty;
    for (0..mesh_points.len) |i| {
        const p1 = mesh_points[i];
        const p2 = mesh_points[(i + 1) % mesh_points.len];
        const edge_pts = try generateEdgePoints(gpa, p1, p2, density);
        defer gpa.free(edge_pts);

        try points.appendSlice(gpa, edge_pts);
    }
    return try points.toOwnedSlice(gpa);
}
