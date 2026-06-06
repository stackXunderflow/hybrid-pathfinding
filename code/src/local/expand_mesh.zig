const std = @import("std");
const Allocator = std.mem.Allocator;

const common = @import("../common.zig");
const Point2 = common.Point2;
const Mesh = common.Mesh;
const F32_EPSILON = common.constants.F32_EPSILON;

const min_sin = 0.5;

pub fn expandMesh(gpa: Allocator, mesh: Mesh, expand_len: f32) ![]const Point2 {
    const n = mesh.points.len;
    if (n < 3) return error.NotEnoughPoints;

    var result: std.ArrayList(Point2) = .empty;

    for (0..n) |index| {
        const prev = (index + n - 1) % n;
        const next = (index + 1) % n;

        const vecB = mesh.points[index].vecTo(mesh.points[next]);
        const vecA = mesh.points[prev].vecTo(mesh.points[index]);

        if (vecA.len() < F32_EPSILON or vecB.len() < F32_EPSILON) {
            continue;
        }

        const normalizedA = try vecA.normilize();
        const normalizedB = try vecB.normilize();
        const normalB = try normalizedB.rotateRight90();
        const normalA = try normalizedA.rotateRight90();

        const normal = normalA.plus(normalB);
        const vecE = try normal.normilize();
        const sinVec = vecE.x * normalA.x + vecE.y * normalA.y;

        if (sinVec < min_sin) {
            try result.append(gpa, .{
                .x = mesh.points[index].x + normalA.x * expand_len + vecE.x * expand_len,
                .y = mesh.points[index].y + normalA.y * expand_len + vecE.y * expand_len,
            });
            try result.append(gpa, .{
                .x = mesh.points[index].x + normalB.x * expand_len + vecE.x * expand_len,
                .y = mesh.points[index].y + normalB.y * expand_len + vecE.y * expand_len,
            });
        } else {
            try result.append(gpa, .{
                .x = mesh.points[index].x + vecE.x * (expand_len / sinVec),
                .y = mesh.points[index].y + vecE.y * (expand_len / sinVec),
            });
        }
    }

    return try result.toOwnedSlice(gpa);
}