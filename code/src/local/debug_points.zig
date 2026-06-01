const std = @import("std");
const Allocator = std.mem.Allocator;

const common = @import("../common.zig");
const Point2 = common.Point2;

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
    _ = robot_radius;

    const aabb = blob.blob.aabb;

    const w = aabb.width();
    const h = aabb.height();

    const points = try halton.generateHallPoints2D(gpa, w, h, aabb.Xmin, aabb.Ymin, density, seed);

    blk: for (points) |point| {
        if (blob.blob.containsPoint(point)){
            for (blob.meshs) |mesh| {
                if (intersection.rayIntersection(mesh, point)){
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
