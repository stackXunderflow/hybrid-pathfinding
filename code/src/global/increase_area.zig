const std = @import("std");
const Allocator = std.mem.Allocator;

const common = @import("../common.zig");
const Point2 = common.Point2;

pub fn increaseArea(allocator: Allocator, points: []const Point2, robotRadius: f32) ![]const Point2 {
    const increaseLen = robotRadius * common.constants.GLOBAL_GEOMETRY_HULL_DELTA;

    var biggerHull = try allocator.alloc(Point2, points.len);

    for (points, 0..) |_, index| {
        const next = (index + 1) % points.len;
        const prev = (index + points.len - 1) % points.len;

        const vecB = points[index].vecTo(points[next]);
        const vecA = points[prev].vecTo(points[index]);

        const normalizedA = try vecA.normilize();
        const normalizedB = try vecB.normilize();
        const normalB = try normalizedB.rotateRight90();
        const normalA = try normalizedA.rotateRight90();

        const normal = normalA.plus(normalB);

        const vecE = try normal.normilize();

        const sinVec = vecE.x * normalA.x + vecE.y * normalA.y;

        const newPoint = Point2{
            .x = points[index].x + vecE.x * (increaseLen / sinVec),
            .y = points[index].y + vecE.y * (increaseLen / sinVec),
        };

        biggerHull[index] = newPoint;
    }

    return biggerHull;
}
