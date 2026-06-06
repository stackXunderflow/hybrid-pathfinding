const std = @import("std");
const Allocator = std.mem.Allocator;

const common = @import("common.zig");
const Point2 = common.Point2;
const AABB = common.AABB;
const dbg = @import("dbg.zig");
const global = @import("global.zig");
const BlobContent = global.BlobContent;
const halton = @import("local/halton.zig");
const intersection = @import("local/intersection.zig");
const blob_boundary = @import("local/blob_boundary_points.zig");
const increase_area = @import("global/increase_area.zig");
const triangulation = @import("local/triangulation.zig");

pub const LocalGeometry = struct {
    triang: triangulation.Triangulation,
};

pub const PointsCollection = struct {
    items: []Point2,
    halton: usize,
    obstacles: usize,
    boundary: usize,
    superstructure: usize,
};

pub fn localGeometry(
    gpa: Allocator,
    blob: BlobContent,
    robot_radius: f32,
    density: f32,
    seed: u64,
) !LocalGeometry {
    const edge_density = std.math.sqrt(density);
    const points = try generatePoints(gpa, blob, robot_radius, density, edge_density, seed);

    const triang = try triangulation.Delone.run(gpa, points, blob.blob.aabb);

    return .{
        .triang = triang,
    };
}

fn generatePoints(
    gpa: Allocator,
    blob: BlobContent,
    robot_radius: f32,
    density: f32,
    edge_density: f32,
    seed: u64,
) !PointsCollection {
    var filtred: std.ArrayList(Point2) = .empty;

    const danger_len = robot_radius * common.constants.LOCAL_GEOMETRY_DANGER_DELTA;

    const aabb = blob.blob.aabb;

    const points = try halton.generateHallPoints2D(gpa, aabb.width(), aabb.height(), aabb.Xmin, aabb.Ymin, density, seed);

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
    const halton_ind = filtred.items.len;

    for (blob.meshs) |mesh| {
        const expanded = try increase_area.increaseArea(gpa, mesh.points, danger_len);
        defer gpa.free(expanded);

        const boundary_points = try blob_boundary.generateBlobBoundaryPoints(gpa, expanded, edge_density);
        defer gpa.free(boundary_points);

        for (boundary_points) |point| {
            if (intersection.isValidPoint(point, danger_len, blob, expanded_aabbs)) {
                try filtred.append(gpa, point);
            }
        }
    }
    const obstacles = filtred.items.len;

    const boundary_points = try blob_boundary.generateBlobBoundaryPoints(
        gpa,
        blob.blob.points,
        edge_density,
    );
    defer gpa.free(boundary_points);
    try filtred.appendSlice(gpa, boundary_points);
    const boundary = filtred.items.len;

    return .{
        .items = try filtred.toOwnedSlice(gpa),
        .halton = halton_ind,
        .obstacles = obstacles,
        .boundary = boundary,
        .superstructure = 0,
    };
}
