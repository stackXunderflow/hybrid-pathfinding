const std = @import("std");
const Allocator = std.mem.Allocator;
const math = std.math;
const common = @import("../common.zig");
const Point2 = common.Point2;
const F32_EPSILON = common.constants.F32_EPSILON;

pub fn checkClosePoints(allocator: Allocator, points: []const Point2) ![]Point2 {
    var cleanPoints: std.ArrayList(Point2) = .empty;
    defer cleanPoints.deinit(allocator);

    for (points) |p| {
        if (cleanPoints.items.len > 0) {
            const last = cleanPoints.items[cleanPoints.items.len - 1];
            if (@abs(p.x - last.x) < F32_EPSILON and @abs(p.y - last.y) < F32_EPSILON) {
                continue; // Пропускаем дубликат
            }
        }
        try cleanPoints.append(allocator, p);
    }

    if (cleanPoints.items.len > 1) {
        const first = cleanPoints.items[0];
        const last = cleanPoints.items[cleanPoints.items.len - 1];
        if (@abs(first.x - last.x) < 0.001 and @abs(first.y - last.y) < 0.001) {
            _ = cleanPoints.pop();
        }
    }
    return try cleanPoints.toOwnedSlice(allocator);
}
