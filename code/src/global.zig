const std = @import("std");
const Allocator = std.mem.Allocator;

const common = @import("common.zig");
const Mesh = common.Mesh;
const Point = common.Point;

fn pointLessThan(_: void, a: Point, b: Point) bool {
    if (a.x != b.x) return a.x < b.x;
    return a.y < b.y;
}

fn orientation(a: Point, b: Point, c: Point) f32 {
    return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
}

pub fn andrewAlgorithm(allocator: Allocator, mesh: Mesh) !Mesh {
    const points = try allocator.dupe(Point, mesh.points);
    if (points.len < 3) {
        @panic("У меша меньше трех точек! Нельзя построить выпуклую оболочку");
    }

    std.mem.sort(Point, points, {}, pointLessThan);

    var hull: std.ArrayList(Point) = .empty;
    defer hull.deinit(allocator);

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

    const result = try allocator.alloc(Point, hull.items.len);
    @memcpy(result, hull.items);

    return .{ .points = result };
}
