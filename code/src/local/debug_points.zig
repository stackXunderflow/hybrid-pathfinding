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

pub fn addHaltonPointsInBlobAABB(
    gpa: Allocator,
    debugger: *dbg.Debugger,
    blob: BlobContent,
    robot_start: Point2,
    robot_end: Point2,
    robot_radius: f32,
    density: f32,
    seed: u64,
    layer_name: []const u8,
) !void {
    _ = robot_start;
    _ = robot_end;

    const dangerLen = robot_radius * common.constants.LOCAL_GEOMETRY_DANGER_DELTA;

    const aabb = blob.blob.aabb;

    const w = aabb.width();
    const h = aabb.height();

    const points = try halton.generateHallPoints2D(gpa, w, h, aabb.Xmin, aabb.Ymin, density, seed);

    const expanded_aabbs = try gpa.alloc(AABB, blob.meshs.len);
    for (blob.meshs, 0..) |mesh, i| {
        expanded_aabbs[i] = AABB.fromPoints(mesh.points).expand(dangerLen);
    }

    blk: for (points) |point| {
        if (blob.blob.containsPoint(point)){
            for (blob.meshs, 0..) |mesh, i| {
                if (!expanded_aabbs[i].containsPoint(point)){
                    continue;
                }
                if (intersection.dangerIntersection(mesh, point, dangerLen)){
                    continue :blk;
                }
            }

            try debugger.point(
                point,
                .{ .layout = layer_name },
            );
        }
    }

}
