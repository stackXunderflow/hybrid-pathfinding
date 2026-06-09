const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

const common = @import("../common.zig");
const Point2 = common.Point2;
const Vec2 = common.Vec2;
const Robot = common.Robot;
const Blob = common.Blob;
const AABB = common.AABB;
const F32_EPSILON = common.constants.F32_EPSILON;
const dbg = @import("../dbg.zig");
const Debugger = dbg.Debugger;
const global = @import("../global.zig");
const local = @import("../local.zig");
const BlobContent = global.BlobContent;

pub const IndexPoint = struct {
    index: usize,
    t: f32,
};

pub const HullIntersection = struct {
    blob: Blob,
    index: u32,
    in: ?IndexPoint,
    out: ?IndexPoint,
};

pub fn hullIntersections(allocator: Allocator, debugger: *Debugger, origin: Point2, direction: Vec2, length: f32, blobs_content: []const BlobContent) ![]const HullIntersection {
    var result: std.ArrayList(HullIntersection) = .empty;

    for (blobs_content, 0..) |blob_content, i| {
        const blob = blob_content.blob;
        if (intersectAABB(origin, direction, length, blob.aabb)) {
            const intersection_result = try cyrusBeckIntersection(debugger, origin, direction, length, blob, @truncate(i));
            if (intersection_result) |intersection| {
                try result.append(allocator, intersection);
            }
        }
    }

    std.mem.sort(HullIntersection, result.items, {}, sortByTin);

    return try result.toOwnedSlice(allocator);
}

fn sortByTin(_: void, a: HullIntersection, b: HullIntersection) bool {
    const ain = if (a.in) |in| in.t else 0;
    const bin = if (b.in) |in| in.t else 0;

    return ain < bin;
}

fn cyrusBeckIntersection(debugger: *Debugger, origin: Point2, direction: Vec2, length: f32, blob: Blob, blob_id: u32) !?HullIntersection {
    _ = debugger;

    var tin: f32 = -std.math.floatMax(f32);
    var tout: f32 = std.math.floatMax(f32);
    var index_in: usize = std.math.maxInt(usize);
    var index_out: usize = std.math.maxInt(usize);

    for (0..blob.points.len, 1..) |current_index, next_index| {
        const current = blob.points[current_index];
        const next = blob.points[next_index % blob.points.len];
        const vec_to_point = current.vecTo(origin);

        const inner_vec = try next.vecTo(current).rotateRight90();
        const inner_normal = try inner_vec.normilize();

        const dn = direction.scalarProduct(inner_normal);
        const wn = vec_to_point.scalarProduct(inner_normal);

        const t = -(wn / dn);

        if (dn > 0 and t > tin) {
            tin = t;
            index_in = current_index;
        }

        if (dn < 0 and t < tout) {
            tout = t;
            index_out = current_index;
        }

        if (tin > tout) {
            return null;
        }

        if (tin > length) {
            return null;
        }

        if (tout < 0) {
            return null;
        }
    }

    const in: ?IndexPoint = if (tin >= F32_EPSILON) .{ .index = index_in, .t = tin } else null;
    const out: ?IndexPoint = if (tout <= length + F32_EPSILON and tout >= F32_EPSILON) .{ .index = index_out, .t = tout } else null;

    return .{ .blob = blob, .index = blob_id, .in = in, .out = out };
}

fn intersectAABB(origin: Point2, direction: Vec2, length: f32, aabb: AABB) bool {
    const tx1 = (aabb.Xmin - origin.x) / direction.x;
    const tx2 = (aabb.Xmax - origin.x) / direction.x;
    const ty1 = (aabb.Ymin - origin.y) / direction.y;
    const ty2 = (aabb.Ymax - origin.y) / direction.y;

    const txmin = @min(tx1, tx2);
    const txmax = @max(tx1, tx2);
    const tymin = @min(ty1, ty2);
    const tymax = @max(ty1, ty2);

    const tnear = @max(txmin, tymin);
    const tfar = @min(txmax, tymax);

    if (tnear > tfar) return false;
    if (tfar < 0.0) return false;
    if (tnear > length) return false;

    return true;
}
