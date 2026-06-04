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

    gpa.free(points);
    gpa.free(expanded_aabbs);

    const edge_layer_name = try std.fmt.allocPrint(gpa, "{s}_offset", .{layer_name});
    defer gpa.free(edge_layer_name);
    const edge_density: f32 = 0.05;
    for (blob.meshs) |mesh| {
        const n = mesh.points.len;
        if (n < 2) continue;
        for (0..n) |i| {
            const p1 = mesh.points[i];
            const p2 = mesh.points[(i + 1) % n];
            const edge_pts = try offset.generateSafeOffsetPoints(gpa, p1, p2, mesh, blob.meshs, dangerLen, edge_density);
            defer gpa.free(edge_pts);
            for (edge_pts) |pt| {
                if (blob.blob.containsPoint(pt)) {
                    try debugger.point(pt, .{ .layout = edge_layer_name });
                }
            }
        }
    }

}

