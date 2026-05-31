const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const math = std.math;

const common = @import("../common.zig");
const Mesh = common.Mesh;
const Blob = common.Blob;
const Point2 = common.Point2;
const global = @import("../global.zig");
const BlobContent = global.BlobContent;
const Pair = global.Pair;
const andrew = @import("andrew.zig");
const broad_phase = @import("broad_phase.zig");
const sat = @import("sat.zig");

fn findRoot(parents: []usize, x: usize) usize {
    if (parents[x] != x) {
        parents[x] = findRoot(parents, parents[x]);
    }
    return parents[x];
}

fn DSU(gpa: Allocator, blobs: []const BlobContent, pairs: []const Pair) ![]const BlobContent {
    var parents = try gpa.alloc(usize, blobs.len);
    defer gpa.free(parents);

    for (0..blobs.len) |index| {
        parents[index] = index;
    }

    for (pairs) |pair| {
        const root_a = findRoot(parents, pair.id1);
        const root_b = findRoot(parents, pair.id2);
        if (root_a != root_b) {
            parents[root_a] = root_b;
        }
    }

    var root_to_blobs: std.AutoHashMap(usize, std.ArrayList(usize)) = .init(gpa);
    var new_blobs: std.ArrayList(BlobContent) = .empty;
    for (0..blobs.len) |index| {
        try root_to_blobs.put(index, .empty);
    }

    for (0..blobs.len) |index| {
        const root = findRoot(parents, index);
        if (root_to_blobs.getPtr(root)) |list_ptr| {
            try list_ptr.append(gpa, index);
        }
    }

    var it = root_to_blobs.iterator();
    while (it.next()) |entry| {
        if (entry.value_ptr.items.len == 0) continue;

        var points: std.ArrayList(Point2) = .empty;
        var obstacles: std.ArrayList(Mesh) = .empty;
        for (entry.value_ptr.items) |index| {
            const blob_content = blobs[index];

            try points.appendSlice(gpa, blob_content.blob.points);
            try obstacles.appendSlice(gpa, blob_content.meshs);

            gpa.free(blob_content.blob.points);
            gpa.free(blob_content.meshs);
        }

        const mesh = try points.toOwnedSlice(gpa);
        const blob: Blob = .fromPoints(try andrew.convexHull(gpa, mesh));

        try new_blobs.append(gpa, .{ .blob = blob, .meshs = try obstacles.toOwnedSlice(gpa) });
    }
    return try new_blobs.toOwnedSlice(gpa);
}

pub fn intersectBlobs(gpa: Allocator, blobs: []const BlobContent) ![]const BlobContent {
    var current_blobs = blobs;
    while (true) {
        const pairs = try broad_phase.broadPhase(gpa, current_blobs);
        const intersections = try sat.SAT(gpa, current_blobs, pairs);
        defer gpa.free(intersections);
        if (intersections.len == 0) {
            return current_blobs;
        }
        const res_blobs = try DSU(gpa, current_blobs, intersections);
        if (res_blobs.len == current_blobs.len) {
            return res_blobs;
        }
        current_blobs = res_blobs;
    }
}
