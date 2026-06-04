const std = @import("std");
const Allocator = std.mem.Allocator;

const common = @import("../common.zig");
const Point2 = common.Point2;
const Vec2 = common.Vec2;
const Mesh = common.Mesh;

const intersection = @import("intersection.zig");

pub fn generateOffsetPoints(gpa: Allocator, a: Point2, b: Point2, dangerLen: f32, density: f32) ![]Point2 {
    const vec = Point2.vecTo(a, b);
    const length = vec.len();

    const u = if (length < common.constants.F32_EPSILON) Vec2{ .x = 1, .y = 0 } else try vec.normilize();
    const n = try u.rotateRight90();
    const offset = n.scale(dangerLen);

    const target_step = if (density > 0) 1.0 / density else length;
    const num_intervals: usize = if (length <= 0 or target_step <= 0) 1 else @max(1, @as(usize, @intFromFloat(@floor(length / target_step))));
    const num_points = num_intervals + 1;

    const points = try gpa.alloc(Point2, num_points);
    for (0..num_points) |i| {
        const t = if (num_points <= 1) 0 else @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(num_points - 1));
        const base = a.plus(vec.scale(t));
        points[i] = base.plus(offset);
    }
    return points;
}

