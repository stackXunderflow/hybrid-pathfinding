const std = @import("std");
const Allocator = std.mem.Allocator;

const common = @import("../../common.zig");
const AABB = common.AABB;
const Vec2 = common.Vec2;
const Point2 = common.Point2;
const local = @import("../../local.zig");
const PointsCollection = local.PointsCollection;
const triangulation = @import("../triangulation.zig");

pub fn normalize(gpa: Allocator, points: PointsCollection, aabb: AABB) !PointsCollection {
    const shift: Vec2 = .{ .x = -aabb.Xmin, .y = -aabb.Ymin };
    const ratio = @max(aabb.height(), aabb.width());

    const new = try gpa.alloc(Point2, points.items.len);
    for (points.items, 0..) |p, i| {
        const shifted = p.plus(shift);
        new[i] = .{ .x = shifted.x / ratio, .y = shifted.y / ratio };
    }

    var new_collection = points;
    new_collection.items = new;

    return new_collection;
}

pub fn denormalize(gpa: Allocator, points: PointsCollection, aabb: AABB) !PointsCollection {
    const shift: Vec2 = .{ .x = aabb.Xmin, .y = aabb.Ymin };
    const ratio = @max(aabb.height(), aabb.width());

    const new = try gpa.alloc(Point2, points.items.len);
    for (points.items, 0..) |p, i| {
        new[i] = .{ .x = p.x * ratio + shift.x, .y = p.y * ratio + shift.y };
    }

    var new_collection = points;
    new_collection.items = new;

    return new_collection;
}
