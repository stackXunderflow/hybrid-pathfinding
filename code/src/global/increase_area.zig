const std = @import("std");
const Allocator = std.mem.Allocator;

const common = @import("../common.zig");
const Point2 = common.Point2;

pub fn increaseArea(allocator: Allocator, points: []const Point2, robotRadius: f32) ![]const Point2 {
    const increaseLen = robotRadius * common.constants.GLOBAL_GEOMETRY_HULL_DELTA;

    var biggerHull: std.ArrayList(Point2) = .empty;
    errdefer biggerHull.deinit(allocator);

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
        const min_sin = 0.25;
        const sinVec = vecE.x * normalA.x + vecE.y * normalA.y;

        if (sinVec < min_sin) {
            const p1 = Point2{
                .x = points[index].x + normalA.x * increaseLen + vecE.x * increaseLen,
                .y = points[index].y + normalA.y * increaseLen + vecE.y * increaseLen,
            };
            const p2 = Point2{
                .x = points[index].x + normalB.x * increaseLen + vecE.x * increaseLen,
                .y = points[index].y + normalB.y * increaseLen + vecE.y * increaseLen,
            };
            try biggerHull.append(allocator, p1);
            try biggerHull.append(allocator, p2);
        } else {
            const newPoint = Point2{
                .x = points[index].x + vecE.x * (increaseLen / sinVec),
                .y = points[index].y + vecE.y * (increaseLen / sinVec),
            };
            try biggerHull.append(allocator, newPoint);
        }
    }

    return try biggerHull.toOwnedSlice(allocator);
}
