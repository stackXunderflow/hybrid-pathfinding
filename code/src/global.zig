const std = @import("std");
const Allocator = std.mem.Allocator;

const common = @import("common.zig");
const Mesh = common.Mesh;
const Point2 = common.Point2;
const Vec2 = common.Vec2;

fn pointLessThan(_: void, a: Point2, b: Point2) bool {
    if (a.x != b.x) return a.x < b.x;
    return a.y < b.y;
}

fn orientation(a: Point2, b: Point2, c: Point2) f32 {
    return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
}

pub fn andrewAlgorithm(allocator: Allocator, mesh: Mesh) !Mesh {
    const points = try allocator.dupe(Point2, mesh.points);
    if (points.len < 3) {
        @panic("У меша меньше трех точек! Нельзя построить выпуклую оболочку");
    }

    std.mem.sort(Point2, points, {}, pointLessThan);

    var hull: std.ArrayList(Point2) = .empty;
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

    const result = try allocator.alloc(Point2, hull.items.len);
    @memcpy(result, hull.items);

    return .{ .points = result };
}

pub fn increaseArea(allocator: Allocator, mesh: Mesh, robotRadius: f32) !Mesh {
    const points = mesh.points;

    var biggerHull = try allocator.alloc(Point2, points.len);

    for (points, 0..) |_, index| {
        const next = (index + 1) % points.len;
        const prev = (index + points.len - 1) % points.len;

        const vecB = Vec2{ .x = points[next].x - points[index].x, .y = points[next].y - points[index].y };
        const vecA = Vec2{ .x = points[index].x - points[prev].x, .y = points[index].y - points[prev].y };

        const normalizedA = try vecA.normilize();
        const normalizedB = try vecB.normilize();
        const normalB = try normalizedB.rotateRight90();
        const normalA = try normalizedA.rotateRight90();

        const normal = try normalA.plus(normalB);

        const vecE = try normal.normilize();

        const sinVec = vecE.x * normalA.x + vecE.y * normalA.y;

        const newPoint = Point2{
            .x = points[index].x + vecE.x * (robotRadius / sinVec),
            .y = points[index].y + vecE.y * (robotRadius / sinVec),
        };

        biggerHull[index] = newPoint;
    }

    return .{ .points = biggerHull };
}
