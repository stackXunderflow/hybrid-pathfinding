const std = @import("std");
const Allocator = std.mem.Allocator;

const common = @import("../common.zig");
const Point2 = common.Point2;
const AABB = common.AABB;

const global = @import("../global.zig");
const BlobContent = global.BlobContent;

const dbg = @import("../dbg.zig");
const halton = @import("halton.zig");

const intersection = @import("intersection.zig");

const offset = @import("offset_points.zig");

pub const GeneratedPoints = struct {
    halton: []const Point2,
    obstacles: []const []const Point2,
};

pub fn generatePoints(
    gpa: Allocator,
    blob: BlobContent,
    robot_radius: f32,
    density: f32,
    edge_density: f32,
    seed: u64,
) !GeneratedPoints {
    const danger_len = robot_radius * common.constants.LOCAL_GEOMETRY_DANGER_DELTA;
    _ = edge_density;

    const aabb = blob.blob.aabb;

    const w = aabb.width();
    const h = aabb.height();

    const points = try halton.generateHallPoints2D(gpa, w, h, aabb.Xmin, aabb.Ymin, density, seed);
    var filtred: std.ArrayList(Point2) = .empty;

    const expanded_aabbs = try gpa.alloc(AABB, blob.meshs.len);
    defer gpa.free(expanded_aabbs);
    for (blob.meshs, 0..) |mesh, i| {
        expanded_aabbs[i] = AABB.fromPoints(mesh.points).expand(danger_len);
    }

    for (points) |point| {
        if (intersection.isValidPoint(point, danger_len, blob, expanded_aabbs)) {
            try filtred.append(gpa, point);
        }
    }

    const empty_obstacles = try gpa.alloc([]const Point2, 0);

    return .{ .halton = try filtred.toOwnedSlice(gpa), .obstacles = empty_obstacles };
}
