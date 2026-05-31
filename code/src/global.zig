const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const math = std.math;

const common = @import("common.zig");
const Mesh = common.Mesh;
const Blob = common.Blob;
const andrew = @import("global/andrew.zig");
const increase_area = @import("global/increase_area.zig");
const intersections = @import("global/intersections.zig");

pub const GlobalGeometry = struct {
    arena: ArenaAllocator,
    blobs: []const BlobContent,
};

pub const BlobContent = struct {
    blob: Blob,
    meshs: []const Mesh,
};

pub const Pair = struct {
    id1: usize,
    id2: usize,
};

pub fn globalGeometry(gpa: Allocator, meshs: []const Mesh, robotRadius: f32) !GlobalGeometry {
    var arena: ArenaAllocator = .init(gpa);
    const allocator = arena.allocator();

    var blobs = try allocator.alloc(BlobContent, meshs.len);
    defer allocator.free(blobs);

    for (meshs, 0..) |mesh, index| {
        const blob_points = try andrew.convexHull(allocator, mesh.points);
        defer allocator.free(blob_points);
        const bigger_blob_points = try increase_area.increaseArea(allocator, blob_points, robotRadius);

        const mesh_alloc = try allocator.alloc(Mesh, 1);
        mesh_alloc[0] = mesh;

        blobs[index] = .{ .blob = .fromPoints(bigger_blob_points), .meshs = mesh_alloc };
    }

    const res_blobs = try intersections.intersectBlobs(allocator, blobs);

    return .{ .arena = arena, .blobs = res_blobs };
}
