const std = @import("std");
const Allocator = std.mem.Allocator;
const math = std.math;

const common = @import("../common.zig");
const Point2 = common.Point2;
const F32_EPSILON = common.constants.F32_EPSILON;
const global = @import("../global.zig");
const BlobContent = global.BlobContent;
const Pair = global.Pair;

fn pointLessThan(_: void, a: Point2, b: Point2) bool {
    if (!math.approxEqAbs(f32, a.x, b.x, F32_EPSILON)) return a.x < b.x;
    return a.y < b.y;
}

fn orientation(a: Point2, b: Point2, c: Point2) f32 {
    return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
}

pub fn convexHull(allocator: Allocator, mesh_points: []const Point2) ![]const Point2 {
    const points = try allocator.dupe(Point2, mesh_points);
    defer allocator.free(points);

    if (points.len < 3) {
        @panic("У меша меньше трех точек! Нельзя построить выпуклую оболочку");
    }

    std.mem.sort(Point2, points, {}, pointLessThan);

    var hull: std.ArrayList(Point2) = .empty;

    for (points) |p| {
        while (hull.items.len >= 2 and
            orientation(hull.items[hull.items.len - 2], hull.items[hull.items.len - 1], p) <= 0)
        {
            _ = hull.pop();
        }
        try hull.append(allocator, p);
    }

    const lower_limit = hull.items.len + 1;

    var i: usize = points.len - 1;
    while (i > 0) {
        i -= 1;
        const p = points[i];
        while (hull.items.len >= lower_limit and
            orientation(hull.items[hull.items.len - 2], hull.items[hull.items.len - 1], p) <= 0)
        {
            _ = hull.pop();
        }
        try hull.append(allocator, p);
    }

    _ = hull.pop();

    return try hull.toOwnedSlice(allocator);
}
