const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

const common = @import("common.zig");
const Point2 = common.Point2;
const AABB = common.AABB;
const Blob = common.Blob;
const Robot = common.Robot;
const dbg = @import("dbg.zig");
const global = @import("global.zig");
const BlobContent = global.BlobContent;
const increase_area = @import("global/increase_area.zig");
const blob_boundary = @import("local/blob_boundary_points.zig");
const halton = @import("local/halton.zig");
const intersection = @import("local/intersection.zig");
pub const semi_dual_graph = @import("local/semi_dual_graph.zig");
const triangulation = @import("local/triangulation.zig");
const BVH = @import("local/bvh.zig");

pub const PointInfo = union(enum) {
    blocked,
    some: struct { triangle: u32, graph_node: u32 },
};

pub const LocalGeometry = struct {
    arena: ArenaAllocator,
    blob: BlobContent,
    triang: triangulation.Triangulation,
    graph: semi_dual_graph.Graph,
    index: u32,

    pub fn deinit(self: *LocalGeometry, gpa: Allocator) void {
        self.graph.deinit(gpa);
    }

    pub fn locatePoint(self: LocalGeometry, point: Point2) ?PointInfo {
        if (!self.blob.blob.containsPoint(point)) {
            return null;
        }

        const triangle = triangulation.findTriangle(self.triang.points.items, self.triang.triangles, point, self.triang.triangles[0]);
        const node = self.graph.triangle_to_point[triangle.index];

        return if (node == semi_dual_graph.null_node) .blocked else .{ .some = .{ .triangle = triangle.index, .graph_node = node } };
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
    index: u32,
    robot: Robot,
    density: f32,
    seed: u64,
) !LocalGeometry {
    var arena: ArenaAllocator = .init(gpa);
    const allocator = arena.allocator();

    const danger_len = robot.radius * common.constants.LOCAL_GEOMETRY_DANGER_DELTA;
    const expanded_aabbs = try allocator.alloc(AABB, blob.meshs.len);
    defer allocator.free(expanded_aabbs);
    for (blob.meshs, 0..) |mesh, i| {
        expanded_aabbs[i] = AABB.fromPoints(mesh.points).expand(danger_len);
    }

    var bvh: BVH.BVH = try .init(gpa, blob.blob, expanded_aabbs, robot.radius);
    defer bvh.deinit();

    const edge_density = std.math.sqrt(density);
    const points = try generatePoints(allocator, blob, expanded_aabbs, bvh, danger_len, density, edge_density, seed);

    const triang = try triangulation.Delone.run(allocator, points, blob.blob.aabb);
    const graph = try semi_dual_graph.build(allocator, triang, blob, expanded_aabbs, bvh, danger_len);

    return .{
        .arena = arena,
        .blob = blob,
        .index = index,
        .triang = triang,
        .graph = graph,
    };
}

fn generatePoints(
    gpa: Allocator,
    blob: BlobContent,
    expanded_aabbs: []const AABB,
    bvh: BVH.BVH,
    danger_len: f32,
    density: f32,
    edge_density: f32,
    seed: u64,
) !PointsCollection {
    var filtred: std.ArrayList(Point2) = .empty;

    const aabb = blob.blob.aabb;

    const points = try halton.generateHallPoints2D(gpa, aabb.width(), aabb.height(), aabb.Xmin, aabb.Ymin, density, seed);

    for (points) |point| {
        if (intersection.isValidPoint(point, danger_len, blob, expanded_aabbs, bvh)) {
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
            if (intersection.isValidPoint(point, danger_len, blob, expanded_aabbs, bvh)) {
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
