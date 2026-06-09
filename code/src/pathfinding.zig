const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

const common = @import("common.zig");
const Output = @import("planner.zig").Output;
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

pub const PointType = union(enum) {
    robot,
    hull: u32,
    local,
};

pub const PathItem = struct {
    point: Point2,
    point_type: PointType,
};

pub const Path = struct {
    items: []const PathItem,

    pub fn len(self: Path) f32 {
        var acc: f32 = 0;

        for (self.items[0 .. self.items.len - 1], self.items[1..]) |a, b| {
            acc += a.point.magnitude(b.point);
        }

        return acc;
    }
};

pub const Result = union(enum) {
    start_blocked,
    end_blocked,
    no_path,
    ok: Path,

    pub fn asOutputResult(self: Result, allocator: Allocator) !Output.Result {
        return switch (self) {
            .ok => |ok| {
                const points = try allocator.alloc(Point2, ok.items.len);
                const types = try allocator.alloc(PointType, ok.items.len);
                for (ok.items, 0..) |item, i| {
                    points[i] = item.point;
                    types[i] = item.point_type;
                }
                return .{ .ok = .{
                    .points = points,
                    .types = types,
                    .length = ok.len(),
                } };
            },
            .start_blocked => .{ .err = .start_blocked },
            .end_blocked => .{ .err = .end_blocked },
            .no_path => .{ .err = .no_path },
        };
    }
};

pub fn findPath(
    gpa: Allocator,
    debugger: *Debugger,
    robot: Robot,
    global_geometry: global.GlobalGeometry,
    local_geometries: []const local.LocalGeometry,
) !Result {
    var arena: ArenaAllocator = .init(gpa);
    const allocator = arena.allocator();
    const origin = robot.start;
    const vec = origin.vecTo(robot.end);
    const direction = try vec.normilize();
    const length = vec.len();

    const hull_intersections = try intersections.hullIntersections(allocator, debugger, origin, direction, length, global_geometry.blobs);
    defer allocator.free(hull_intersections);

    if (hull_intersections.len == 0) {
        return straightLinePath(robot);
    }

    if (hull_intersections.len == 1 and hull_intersections[0].in == null and hull_intersections[0].out == null) {
        return try singleBlobStrategy(allocator, robot, local_geometries[hull_intersections[0].index]);
    }

    const path = try buildPath(allocator, debugger, origin, direction, robot.end, hull_intersections, local_geometries);

    return switch (path) {
        .ok => |ok| try simplifyPath(allocator, debugger, ok, global_geometry.blobs),
        else => path,
    };
}

fn straightLinePath(robot: Robot) Result {
    const start: PathItem = .{ .point = robot.start, .point_type = .robot };
    const end: PathItem = .{ .point = robot.end, .point_type = .robot };
    return .{ .ok = .{ .items = &[2]PathItem{ start, end } } };
}

fn singleBlobStrategy(allocator: Allocator, robot: Robot, geometry: local.LocalGeometry) !Result {
    const from = geometry.locatePoint(robot.start) orelse unreachable;
    const to = geometry.locatePoint(robot.end) orelse unreachable;

    if (from == .blocked) {
        return .start_blocked;
    }

    if (to == .blocked) {
        return .end_blocked;
    }

    const lpath = (try shortest_path.find(allocator, geometry, from.some.graph_node, to.some.graph_node)) orelse return .no_path;
    defer lpath.deinit(allocator);

    return .{ .ok = try lpath.asPath(geometry, allocator) };
}

fn simplifyPath(gpa: Allocator, debugger: *Debugger, path: Path, blobs_content: []const BlobContent) !Result {
    var simplified: std.ArrayList(PathItem) = .fromOwnedSlice(try gpa.dupe(PathItem, path.items));

    blk: while (true) {
        const total = simplified.items.len;
        if (total <= 3) {
            break;
        }
        for (0..total - 2, 2..) |near, far| {
            const near_type = simplified.items[near].point_type;
            const far_type = simplified.items[far].point_type;

            if (near_type == .local or far_type == .local) continue;
            if (near_type == .hull and far_type == .hull and near_type.hull == far_type.hull) continue;

            const near_point = simplified.items[near].point;
            const far_point = simplified.items[far].point;

            const vec = near_point.vecTo(far_point);
            const length = vec.len();
            const direction = try vec.normilize();

            const hull_intersections = try intersections.hullIntersections(gpa, debugger, near_point, direction, length - 1, blobs_content);
            defer gpa.free(hull_intersections);

            if (hull_intersections.len == 0 or (hull_intersections.len == 1 and hull_intersections[0].in == null and hull_intersections[0].out == null)) {
                _ = simplified.orderedRemove(near + 1);
                continue :blk;
            }
        }

        break;
    }

    return .{ .ok = .{
        .items = try simplified.toOwnedSlice(gpa),
    } };
}

fn buildPath(gpa: Allocator, debugger: *Debugger, origin: Point2, direction: Vec2, end: Point2, hull_intersections: []const HullIntersection, local_geometries: []const local.LocalGeometry) !Result {
    var path: std.ArrayList(PathItem) = .empty;
    try path.append(gpa, .{ .point = origin, .point_type = .robot });

    const first = hull_intersections[0];
    if (first.in == null) {
        const iout = first.out orelse unreachable;
        const out = origin.plus(direction.scale(iout.t));

        const geometry = local_geometries[first.index];

        const info = geometry.locatePoint(origin) orelse unreachable;

        switch (info) {
            .blocked => {
                try debugger.point(origin, .{ .label = "BLOCKED" });
                return .start_blocked;
            },

            .some => |av| {
                const nearest = geometry.graph.findNearestHullPoint(out);

                const lpath = (try shortest_path.find(gpa, geometry, av.graph_node, nearest)) orelse return .no_path;
                try path.appendSlice(gpa, (try lpath.asPath(geometry, gpa)).items);
                try path.append(gpa, .{ .point = out, .point_type = .{ .hull = geometry.index } });
            },
        }
    }

    for (hull_intersections) |intersection| {
        const blob = intersection.blob;

        const iin = intersection.in orelse continue;
        const iout = intersection.out orelse continue;

        const in = origin.plus(direction.scale(iin.t));
        const out = origin.plus(direction.scale(iout.t));

        const geometry = local_geometries[intersection.index];
        const lpath = (try shortest_path.find(gpa, geometry, geometry.graph.findNearestHullPoint(in), geometry.graph.findNearestHullPoint(out))) orelse unreachable;
        const through_blob = try lpath.asPath(local_geometries[intersection.index], gpa);
        const variants = try pathsAroundHull(gpa, blob, in, iin, out, iout, .{ .hull = intersection.index });

        const through_blob_len = through_blob.len();
        const ccw_len = variants[0].len();
        const cw_len = variants[1].len();

        if (through_blob_len < @min(ccw_len, cw_len) * 1) {
            try path.append(gpa, .{ .point = in, .point_type = .{ .hull = intersection.index } });
            try path.appendSlice(gpa, through_blob.items);
            try path.append(gpa, .{ .point = out, .point_type = .{ .hull = intersection.index } });
        } else {
            if (ccw_len < cw_len) {
                try path.appendSlice(gpa, variants[0].items);
            } else {
                try path.appendSlice(gpa, variants[1].items);
            }
        }
    }

    const last = hull_intersections[hull_intersections.len - 1];
    if (last.out == null) {
        const iin = last.in orelse unreachable;
        const in = origin.plus(direction.scale(iin.t));

        const geometry = local_geometries[last.index];

        const info = geometry.locatePoint(end) orelse unreachable;

        switch (info) {
            .blocked => {
                try debugger.point(end, .{ .label = "BLOCKED" });
                return .end_blocked;
            },

            .some => |av| {
                const nearest = geometry.graph.findNearestHullPoint(in);

                const lpath = (try shortest_path.find(gpa, geometry, nearest, av.graph_node)) orelse return .no_path;
                try path.append(gpa, .{ .point = in, .point_type = .{ .hull = geometry.index } });
                try path.appendSlice(gpa, (try lpath.asPath(geometry, gpa)).items);
            },
        }
    }

    try path.append(gpa, .{ .point = end, .point_type = .robot });

    return .{ .ok = .{ .items = try path.toOwnedSlice(gpa) } };
}

fn pathsAroundHull(allocator: Allocator, hull: Blob, in_point: Point2, in: intersections.IndexPoint, out_point: Point2, out: intersections.IndexPoint, point_type: PointType) ![2]Path {
    const n = hull.points.len;

    var ccw: std.ArrayList(PathItem) = .empty;
    try ccw.append(allocator, .{ .point = in_point, .point_type = point_type });
    var i = (in.index) % n;
    while (i != out.index) {
        i = (i + 1) % n;
        try ccw.append(allocator, .{ .point = hull.points[i], .point_type = point_type });
    }
    try ccw.append(allocator, .{ .point = out_point, .point_type = point_type });

    var cw: std.ArrayList(PathItem) = .empty;
    try cw.append(allocator, .{ .point = in_point, .point_type = point_type });
    var j = in.index;
    while (j != out.index) {
        try cw.append(allocator, .{ .point = hull.points[j], .point_type = point_type });
        j = (j + n - 1) % n;
    }
    try cw.append(allocator, .{ .point = out_point, .point_type = point_type });

    return [2]Path{
        .{ .items = try ccw.toOwnedSlice(allocator) },
        .{ .items = try cw.toOwnedSlice(allocator) },
    };
}
