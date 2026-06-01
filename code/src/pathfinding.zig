const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

const common = @import("common.zig");
const Point2 = common.Point2;
const Vec2 = common.Vec2;
const Robot = common.Robot;
const dbg = @import("dbg.zig");
const Debugger = dbg.Debugger;
const global = @import("global.zig");
const BlobContent = global.BlobContent;
const Blob = common.Blob;
const AABB = common.AABB;

pub fn findPath(gpa: Allocator, debugger: *Debugger, robot: Robot, blobs_content: []const BlobContent) !void {
    var arena: ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const allocator = arena.allocator();
    const origin = robot.start;
    const vec = origin.vecTo(robot.end);
    const direction = try vec.normilize();
    const length = vec.len();

    const intersections = try hullIntersections(allocator, debugger, origin, direction, length, blobs_content);
    defer allocator.free(intersections);

    const path = try buildPath(gpa, origin, direction, robot.end, intersections);
    defer gpa.free(path);

    for (path[0 .. path.len - 1], path[1..]) |from, to| {
        try debugger.line(from, to, .{ .layout = "pathfinding" });
    }
}

fn buildPath(gpa: Allocator, origin: Point2, direction: Vec2, end: Point2, intersections: []const HullIntersection) ![]const Point2 {
    var path: std.ArrayList(Point2) = .empty;
    try path.append(gpa, origin);

    for (intersections) |intersection| {
        const blob = intersection.blob;

        const in = origin.plus(direction.scale(intersection.in.t));
        const out = origin.plus(direction.scale(intersection.out.t));

        try path.append(gpa, in);

        const cut_a = in.magnitude(blob.points[intersection.in.index]);
        const cut_b = out.magnitude(blob.points[intersection.out.index]);
        const path_a = hullLen(blob, intersection.in.index, intersection.out.index);
        const path_b = hullLen(blob, intersection.out.index, intersection.in.index);

        const total_points = blob.points.len;
        var current_index: usize = undefined;
        var to_index: usize = undefined;
        var is_path_b = false;
        if (path_a - cut_a + cut_b < path_b - cut_b + cut_a) {
            current_index = intersection.in.index;
            to_index = intersection.out.index;
        } else {
            current_index = intersection.in.index + total_points;
            to_index = intersection.out.index;
            is_path_b = true;
        }

        if (is_path_b) {
            current_index += 1;
        }
        while (current_index % total_points != to_index) {
            if (is_path_b) {
                current_index -= 1;
            } else {
                current_index += 1;
            }
            const next_point = blob.points[current_index % total_points];
            try path.append(gpa, next_point);

            if (is_path_b and ((current_index - 1) % total_points == to_index)) {
                break;
            }
        }

        try path.append(gpa, out);
    }

    try path.append(gpa, end);

    return path.toOwnedSlice(gpa);
}

fn hullLen(hull: Blob, from_index: usize, to_index: usize) f32 {
    const total_points = hull.points.len;
    var len: f32 = 0;
    var current_index = from_index;

    while (current_index % total_points != to_index) {
        const current = hull.points[current_index % total_points];
        const next = hull.points[(current_index + 1) % total_points];

        len += current.magnitude(next);

        current_index += 1;
    }

    return len;
}

fn sortByTin(_: void, a: HullIntersection, b: HullIntersection) bool {
    return a.in.t < b.in.t;
}

fn hullIntersections(allocator: Allocator, debugger: *Debugger, origin: Point2, direction: Vec2, length: f32, blobs_content: []const BlobContent) ![]const HullIntersection {
    var result: std.ArrayList(HullIntersection) = .empty;

    for (blobs_content) |blob_content| {
        const blob = blob_content.blob;
        if (intersectAABB(origin, direction, length, blob.aabb)) {
            const intersection_result = try cyrusBeckIntersection(debugger, origin, direction, length, blob);
            if (intersection_result) |intersection| {
                try result.append(allocator, intersection);
            }
        }
    }

    std.mem.sort(HullIntersection, result.items, {}, sortByTin);

    return try result.toOwnedSlice(allocator);
}

const IndexPoint = struct {
    index: usize,
    t: f32,
};

const HullIntersection = struct {
    blob: Blob,
    in: IndexPoint,
    out: IndexPoint,
};

fn cyrusBeckIntersection(debugger: *Debugger, origin: Point2, direction: Vec2, length: f32, blob: Blob) !?HullIntersection {
    var tin: f32 = 0;
    var tout = std.math.inf(f32);
    var index_in: usize = 0;
    var index_out: usize = 0;

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
    }

    const in = origin.plus(direction.scale(tin));
    const out = origin.plus(direction.scale(tout));

    try debugger.point(in, .{ .layout = "pf points" });
    try debugger.point(out, .{ .layout = "pf points" });

    return .{ .blob = blob, .in = .{ .index = index_in, .t = tin }, .out = .{ .index = index_out, .t = tout } };
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
