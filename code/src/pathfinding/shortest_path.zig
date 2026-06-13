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
const triangulation = @import("../local/triangulation.zig");
const dbg = @import("../dbg.zig");
const Debugger = dbg.Debugger;
const global = @import("../global.zig");
const local = @import("../local.zig");
const Graph = semi_dual_graph.Graph;
const semi_dual_graph = @import("../local/semi_dual_graph.zig");
const pathfinding = @import("../pathfinding.zig");
const PathItem = pathfinding.PathItem;
const Path = pathfinding.Path;
const BlobContent = global.BlobContent;

pub const PointType = enum {
    hull,
    triang,
};

pub const LocalPath = struct {
    points: []const u32,

    pub fn deinit(self: LocalPath, allocator: Allocator) void {
        allocator.free(self.points);
    }

    pub fn asPath(self: LocalPath, geometry: local.LocalGeometry, allocator: Allocator) !Path {
        const graph = geometry.graph;
        const path = try allocator.alloc(PathItem, self.points.len);
        for (self.points, 0..) |pt, i| {
            const item: PathItem = .{ .point = graph.points[pt], .point_type = if (pt < graph.boundary_count) .{ .hull = geometry.index } else .local };
            path[i] = item;
        }
        return .{ .items = path, .blob_start = geometry.index, .blob_end = geometry.index };
    }
};

const QueueItem = struct {
    path_len: f32,
    weight: f32,
    node: u32,

    fn compareFn(_: void, a: QueueItem, b: QueueItem) std.math.Order {
        return std.math.order(a.weight, b.weight);
    }
};

const MapItem = struct {
    path_len: f32,
    prev: u32,
};

pub fn find(allocator: Allocator, geometry: local.LocalGeometry, from: u32, to: u32) !?LocalPath {
    const graph = geometry.graph;

    std.debug.assert(from < graph.points.len);
    std.debug.assert(to < graph.points.len);

    const end = geometry.graph.points[to];

    var map: std.AutoHashMap(u32, MapItem) = .init(allocator);
    try map.put(from, .{ .path_len = 0, .prev = std.math.maxInt(u32) });
    defer map.deinit();

    var queue: std.PriorityQueue(QueueItem, void, QueueItem.compareFn) = .empty;
    defer queue.deinit(allocator);
    try queue.push(allocator, .{ .node = from, .weight = 0, .path_len = 0 });

    blk: while (queue.pop()) |current| {
        if (current.node == to) {
            break :blk;
        }

        const connections = graph.connections.get(current.node).?;
        for (connections) |conn| {
            const next_len = current.path_len + conn.len;
            const next: QueueItem = .{
                .path_len = next_len,
                .weight = next_len + end.magnitude(geometry.graph.points[conn.to]),
                .node = conn.to,
            };

            const old = map.get(next.node);
            if (old == null or old.?.path_len > next.path_len) {
                try map.put(next.node, .{ .path_len = next.path_len, .prev = current.node });
                try queue.push(allocator, next);
            }
        }
    }

    var path: std.ArrayList(u32) = .empty;
    try path.append(allocator, to);
    while (path.items[path.items.len - 1] != from) {
        const map_item = map.get(path.items[path.items.len - 1]) orelse return null;
        try path.append(allocator, map_item.prev);
    }

    const points = try path.toOwnedSlice(allocator);
    std.mem.reverse(u32, points);

    return try simplifyPhase(allocator, geometry, points);
}

fn simplifyPhase(gpa: Allocator, geometry: local.LocalGeometry, indices: []const u32) !LocalPath {
    var path: std.ArrayList(u32) = .empty;
    var current: usize = 0;
    var next: usize = current + 1;
    const n = indices.len;
    const points = geometry.graph.points;

    try path.append(gpa, indices[0]);
    while (current != n - 1) {
        if (next >= n) {
            if (current != n - 1) {
                try path.append(gpa, indices[n - 1]);
            }
            break;
        }

        const current_idx = indices[current];
        const next_idx = indices[next];
        const current_point = points[current_idx];
        const next_point = points[next_idx];

        var safe = false;
        if (next == current + 1) {
            safe = true;
        } else if (current_idx >= geometry.graph.boundary_count and next_idx >= geometry.graph.boundary_count) {
            safe = try checkForSafeTriangles(geometry, current_point, next_point);
        }

        if (safe) {
            next += 1;
        } else {
            const last_safe = next - 1;
            try path.append(gpa, indices[last_safe]);

            current = last_safe;
            next = current + 1;
        }
    }

    return .{ .points = try path.toOwnedSlice(gpa) };
}

fn triangleIsSafe(graph: Graph, tri: triangulation.Triangle) bool {
    return graph.triangle_to_point[tri.index] != semi_dual_graph.null_node;
}

fn segmentIntersectsEdge(A: Point2, B: Point2, u: Point2, v: Point2) bool {
    const oA = A.orientationRobust(u, v);
    const oB = B.orientationRobust(u, v);
    if ((oA > 1e-9 and oB > 1e-9) or (oA < -1e-9 and oB < -1e-9)) return false;

    const ou = u.orientationRobust(A, B);
    const ov = v.orientationRobust(A, B);
    if ((ou > 1e-9 and ov > 1e-9) or (ou < -1e-9 and ov < -1e-9)) return false;

    return true;
}

fn checkForSafeTriangles(
    geometry: local.LocalGeometry,
    from: Point2,
    to: Point2,
) !bool {
    const points = geometry.triang.points.items;
    const triangles = geometry.triang.triangles;
    const graph = geometry.graph;

    const start_tri = triangulation.findTriangle(points, triangles, from, triangles[0]);

    var current_tri = start_tri;
    var prev_tri_index: u32 = triangulation.Triangle.null_index;
    var visited_count: usize = 0;
    const max_visits = triangles.len;

    while (visited_count <= max_visits) : (visited_count += 1) {
        if (!triangleIsSafe(graph, current_tri)) {
            return false;
        }

        var to_inside = true;
        for (0..3) |i| {
            const u = points[current_tri.nodes[i]];
            const v = points[current_tri.nodes[(i + 1) % 3]];
            if (to.orientationRobust(u, v) < -1e-9) {
                to_inside = false;
                break;
            }
        }

        if (to_inside) {
            return true;
        }

        var crossed_edge: ?u32 = null;
        for (0..3) |i| {
            const neighbor = current_tri.neighbors[i];
            if (neighbor == prev_tri_index) continue;

            const u = points[current_tri.nodes[i]];
            const v = points[current_tri.nodes[(i + 1) % 3]];

            if (segmentIntersectsEdge(from, to, u, v)) {
                crossed_edge = @intCast(i);
                break;
            }
        }

        if (crossed_edge) |edge_idx| {
            const neighbor = current_tri.neighbors[edge_idx];
            if (neighbor == triangulation.Triangle.null_index) {
                return false;
            }
            prev_tri_index = current_tri.index;
            current_tri = triangles[neighbor];
        } else {
            var most_negative: f64 = 0;
            var best_edge: ?u32 = null;
            for (0..3) |i| {
                const neighbor = current_tri.neighbors[i];
                if (neighbor == prev_tri_index) continue;

                const u = points[current_tri.nodes[i]];
                const v = points[current_tri.nodes[(i + 1) % 3]];
                const orient = to.orientationRobust(u, v);
                if (orient < most_negative) {
                    most_negative = orient;
                    best_edge = @intCast(i);
                }
            }

            if (best_edge) |edge_idx| {
                const neighbor = current_tri.neighbors[edge_idx];
                if (neighbor == triangulation.Triangle.null_index) return false;
                prev_tri_index = current_tri.index;
                current_tri = triangles[neighbor];
            } else {
                return false;
            }
        }
    }

    return false;
}
