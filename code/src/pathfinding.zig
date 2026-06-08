const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

const common = @import("common.zig");
const Point2 = common.Point2;
const Vec2 = common.Vec2;
const Robot = common.Robot;
const Blob = common.Blob;
const AABB = common.AABB;
const F32_EPSILON = common.constants.F32_EPSILON;
const dbg = @import("dbg.zig");
const Debugger = dbg.Debugger;
const global = @import("global.zig");
const BlobContent = global.BlobContent;
const local = @import("local.zig");
const intersections = @import("pathfinding/intersections.zig");
const HullIntersection = intersections.HullIntersection;
const shortest_path = @import("pathfinding/shortest_path.zig");

const Path = struct {
    points: []const Point2,
    types: []const PointType,
};

const Result = union(enum) {
    start_blocked,
    end_blocked,
    no_path,
    ok,
};

const PointType = union(enum) {
    robot,
    hull: u32,
    local: u32,
};

pub fn findPath(
    gpa: Allocator,
    debugger: *Debugger,
    robot: Robot,
    global_geometry: global.GlobalGeometry,
    local_geometries: []const local.LocalGeometry,
) !Result {
    var arena: ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const allocator = arena.allocator();
    const origin = robot.start;
    const vec = origin.vecTo(robot.end);
    const direction = try vec.normilize();
    const length = vec.len();

    const hull_intersections = try intersections.hullIntersections(allocator, debugger, origin, direction, length, global_geometry.blobs);
    defer allocator.free(hull_intersections);

    std.log.debug("{any}", .{hull_intersections});

    if (hull_intersections.len == 0) {
        try debugger.line(robot.start, robot.end, .{ .layout = "direct path" });
        return .ok;
    }

    if (hull_intersections.len == 1 and hull_intersections[0].in == null and hull_intersections[0].out == null) {
        return try singleBlobStrategy(allocator, debugger, robot, local_geometries[hull_intersections[0].index]);
    }
    if (hull_intersections.len > 0) {
        const first = hull_intersections[0];
        const last = hull_intersections[hull_intersections.len - 1];

        if (first.in == null) {
            const local_geometry = local_geometries[first.index];
            const info = local_geometry.locatePoint(robot.start) orelse unreachable;
            const graph = local_geometry.graph;

            const out = first.out orelse unreachable;
            const out_point = origin.plus(direction.scale(out.t));

            switch (info) {
                .blocked => try debugger.point(robot.start, .{ .label = "BLOCKED" }),

                .some => |av| {
                    const nearest = graph.findNearestHullPoint(out_point);

                    const path = (try shortest_path.find(allocator, local_geometry, av.graph_node, nearest)) orelse return .start_blocked;
                    try dbgPath(debugger, path.points, graph.points, "local start");
                },
            }
        }

        if (last.out == null) {
            const local_geometry = local_geometries[last.index];
            const info = local_geometry.locatePoint(robot.end) orelse unreachable;
            const graph = local_geometry.graph;

            const in = last.in orelse unreachable;
            const in_point = origin.plus(direction.scale(in.t));

            switch (info) {
                .blocked => try debugger.point(robot.end, .{ .label = "BLOCKED" }),

                .some => |av| {
                    const nearest = graph.findNearestHullPoint(in_point);

                    const path = (try shortest_path.find(allocator, local_geometry, av.graph_node, nearest)) orelse return .end_blocked;
                    try dbgPath(debugger, path.points, graph.points, "local end");
                },
            }
        }
    }

    const path = try buildPath(allocator, debugger, origin, direction, robot.end, hull_intersections, local_geometries);

    for (path.points[0 .. path.points.len - 1], path.points[1..]) |from, to| {
        try debugger.line(from, to, .{ .layout = "global naive pf" });
    }

    const simplified = try simplifyNaivePath(allocator, debugger, path, global_geometry.blobs);

    for (simplified.points[0 .. simplified.points.len - 1], simplified.points[1..]) |from, to| {
        try debugger.line(from, to, .{ .layout = "global simplified pf" });
    }

    return .ok;
}

fn singleBlobStrategy(allocator: Allocator, debugger: *Debugger, robot: Robot, geometry: local.LocalGeometry) !Result {
    const from = geometry.locatePoint(robot.start) orelse unreachable;
    const to = geometry.locatePoint(robot.end) orelse unreachable;

    if (from == .blocked) {
        return .start_blocked;
    }

    if (to == .blocked) {
        return .end_blocked;
    }

    const path = (try shortest_path.find(allocator, geometry, from.some.graph_node, to.some.graph_node)) orelse return .no_path;

    try dbgPath(debugger, path.points, geometry.graph.points, "single blob path");

    return .ok;
}

fn dbgPath(debugger: *Debugger, path: []const u32, points: []const Point2, layout: []const u8) !void {
    for (path[0 .. path.len - 1], path[1..]) |f, t| {
        try debugger.line(points[f], points[t], .{ .layout = layout });
    }
}

fn simplifyNaivePath(gpa: Allocator, debugger: *Debugger, path: Path, blobs_content: []const BlobContent) !Path {
    var simplified: std.ArrayList(Point2) = .fromOwnedSlice(try gpa.dupe(Point2, path.points));
    var simplified_types: std.ArrayList(PointType) = .fromOwnedSlice(try gpa.dupe(PointType, path.types));

    blk: while (true) {
        const total = simplified.items.len;
        if (total <= 3) {
            break;
        }
        for (0..total - 2, 2..) |near, far| {
            if (simplified_types.items[near] == .hull and simplified_types.items[far] == .hull) {
                if (simplified_types.items[near].hull == simplified_types.items[far].hull) {
                    continue;
                }
            }

            const near_point = simplified.items[near];
            const far_point = simplified.items[far];

            const vec = near_point.vecTo(far_point);
            const length = vec.len();
            const direction = try vec.normilize();

            const hull_intersections = try intersections.hullIntersections(gpa, debugger, near_point, direction, length - 1, blobs_content);
            defer gpa.free(hull_intersections);

            if (hull_intersections.len == 0 or (hull_intersections.len == 1 and hull_intersections[0].in == null and hull_intersections[0].out == null)) {
                _ = simplified.orderedRemove(near + 1);
                _ = simplified_types.orderedRemove(near + 1);
                continue :blk;
            }
        }

        break;
    }

    return .{
        .points = try simplified.toOwnedSlice(gpa),
        .types = try simplified_types.toOwnedSlice(gpa),
    };
}

fn buildPath(gpa: Allocator, debugger: *Debugger, origin: Point2, direction: Vec2, end: Point2, hull_intersections: []const HullIntersection, local_geometries: []const local.LocalGeometry) !Path {
    var path: std.ArrayList(Point2) = .empty;
    try path.append(gpa, origin);
    var points_type: std.ArrayList(PointType) = .empty;
    try points_type.append(gpa, .robot);

    for (hull_intersections) |intersection| {
        const blob = intersection.blob;

        const iin = intersection.in orelse continue;
        const iout = intersection.out orelse continue;

        const in = origin.plus(direction.scale(iin.t));
        const out = origin.plus(direction.scale(iout.t));

        const geometry = local_geometries[intersection.index];
        const lpath = try shortest_path.find(gpa, geometry, geometry.graph.findNearestHullPoint(in), geometry.graph.findNearestHullPoint(out));
        try dbgPath(debugger, lpath.?.points, geometry.graph.points, "alternative");

        try path.append(gpa, in);
        try points_type.append(gpa, .{ .hull = intersection.index });

        const cut_a = in.magnitude(blob.points[iin.index]);
        const cut_b = out.magnitude(blob.points[iout.index]);
        const path_a = hullLen(blob, iin.index, iout.index);
        const path_b = hullLen(blob, iout.index, iin.index);

        const total_points = blob.points.len;
        var current_index: usize = undefined;
        var to_index: usize = undefined;
        var is_path_b = false;
        if (path_a - cut_a + cut_b < path_b - cut_b + cut_a) {
            current_index = iin.index;
            to_index = iout.index;
        } else {
            current_index = iin.index + total_points;
            to_index = iout.index;
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
            try points_type.append(gpa, .{ .hull = intersection.index });

            if (is_path_b and ((current_index - 1) % total_points == to_index)) {
                break;
            }
        }

        try path.append(gpa, out);
        try points_type.append(gpa, .{ .hull = intersection.index });
    }

    try path.append(gpa, end);
    try points_type.append(gpa, .robot);

    return .{ .points = try path.toOwnedSlice(gpa), .types = try points_type.toOwnedSlice(gpa) };
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
