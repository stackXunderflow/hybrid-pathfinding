const std = @import("std");
const Allocator = std.mem.Allocator;
const math = std.math;

const common = @import("../common.zig");
const Point2 = common.Point2;
const Vec2 = common.Vec2;
const global = @import("../global.zig");
const BlobContent = global.BlobContent;
const Pair = global.Pair;

pub fn SAT(gpa: Allocator, blobs: []const BlobContent, pairs: []const Pair) ![]const Pair {
    var intersections: std.ArrayList(Pair) = .empty;
    for (pairs) |pair| {
        const pointsA = blobs[pair.id1].blob.points;
        const pointsB = blobs[pair.id2].blob.points;
        var norm_vectors: std.ArrayList(Vec2) = try .initCapacity(gpa, pointsA.len + pointsB.len);
        defer norm_vectors.deinit(gpa);

        append_normals(&norm_vectors, pointsA);
        append_normals(&norm_vectors, pointsB);

        var intersect = true;

        for (norm_vectors.items) |vector| {
            const min_max_a = minMaxScalar(pointsA, vector);
            const min_max_b = minMaxScalar(pointsB, vector);

            if (min_max_a.max < min_max_b.min or min_max_b.max < min_max_a.min) {
                intersect = false;
                break;
            }
        }
        if (intersect) {
            try intersections.append(gpa, pair);
        }
    }
    return try intersections.toOwnedSlice(gpa);
}

fn append_normals(norm_vectors: *std.ArrayList(Vec2), points: []const Point2) void {
    for (0..points.len, 1..) |current_index, next_index| {
        const current = points[current_index];
        const next = points[next_index % points.len];

        const vec = current.vecTo(next);
        const normal_vec = try vec.rotateRight90();

        norm_vectors.appendAssumeCapacity(normal_vec);
    }
}

const MinMaxScalar = struct {
    min: f32,
    max: f32,
};

fn minMaxScalar(points: []const Point2, vector: Vec2) MinMaxScalar {
    var min = math.inf(f32);
    var max = -math.inf(f32);

    for (points) |point| {
        const val = point.x * vector.x + point.y * vector.y;

        min = @min(min, val);
        max = @max(max, val);
    }

    return .{ .min = min, .max = max };
}
