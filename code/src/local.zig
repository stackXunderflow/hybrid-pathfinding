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
pub const semi_dual_graph = @import("local/semi_dual_graph.zig");

pub const LocalGeometry = struct {
    triang: triangulation.Triangulation,
    graph: semi_dual_graph.Graph,

    pub fn deinit(self: *LocalGeometry, gpa: Allocator) void {
        self.graph.deinit(gpa);
    }
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
    const danger_len = robot_radius * common.constants.LOCAL_GEOMETRY_DANGER_DELTA;
    const expanded_aabbs = try gpa.alloc(AABB, blob.meshs.len);
    defer gpa.free(expanded_aabbs);
    for (blob.meshs, 0..) |mesh, i| {
        expanded_aabbs[i] = AABB.fromPoints(mesh.points).expand(danger_len);
    }

    const edge_density = std.math.sqrt(density);
    const points = try generatePoints(gpa, blob, expanded_aabbs, danger_len, density, edge_density, seed);

    const triang = try triangulation.Delone.run(gpa, points, blob.blob.aabb);
    const graph = try semi_dual_graph.build(gpa, triang, blob, expanded_aabbs, danger_len);

    return .{
        .triang = triang,
        .graph = graph,
    };
}

fn generatePoints(
    gpa: Allocator,
    blob: BlobContent,
    expanded_aabbs: []const AABB,
    danger_len: f32,
    density: f32,
    edge_density: f32,
    seed: u64,
) !PointsCollection {
    var filtred: std.ArrayList(Point2) = .empty;

    const aabb = blob.blob.aabb;

    const points = try halton.generateHallPoints2D(gpa, aabb.width(), aabb.height(), aabb.Xmin, aabb.Ymin, density, seed);

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
