const std = @import("std");
const Allocator = std.mem.Allocator;

const common = @import("../common.zig");
const AABB = common.AABB;
const Point2 = common.Point2;
const Debugger = @import("../dbg.zig").Debugger;
const local = @import("../local.zig");
const PointsCollection = local.PointsCollection;
const Cache = @import("triangulation/cache.zig").Cache;
const normalization = @import("triangulation/normalization.zig");

pub const Superstructure = struct {
    points: PointsCollection,
    triangle: Triangle,
};

pub const Triangulation = struct {
    points: PointsCollection,
    triangles: []const Triangle,
};

pub const Triangle = struct {
    nodes: [3]u32,
    neighbors: [3]u32,
    index: u32,

    pub const null_index = std.math.maxInt(u32);
};

pub const Edge = struct {
    triangle: u32,
    edge_index: u32,
};

pub const Delone = struct {
    allocator: Allocator,
    points: PointsCollection,
    triangles: std.ArrayList(Triangle),
    cache: Cache,
    edges_queue: std.Deque(Edge),

    pub fn run(gpa: Allocator, initial_points: PointsCollection, aabb: AABB) !Triangulation {
        const normalized = try normalization.normalize(gpa, initial_points, aabb);
        const superstructure = try makeSuperstructure(gpa, normalized);
        var triangles: std.ArrayList(Triangle) = .empty;
        try triangles.append(gpa, superstructure.triangle);

        var delone: Delone = .{
            .allocator = gpa,
            .cache = try Cache.init(gpa, 2),
            .points = superstructure.points,
            .triangles = triangles,
            .edges_queue = .empty,
        };

        defer delone.cache.deinit();
        defer delone.edges_queue.deinit(gpa);

        for (0..delone.points.items.len - 3) |index| {
            const point = delone.points.items[index];
            const triangle = delone.findTriangleCache(point);

            var too_close = false;
            for (triangle.nodes) |node_idx| {
                const node_pt = delone.points.items[node_idx];
                if (point.magnitude(node_pt) < 1e-6) {
                    too_close = true;
                    break;
                }
            }
            if (too_close) continue;

            const i: u32 = @truncate(index);
            const n: u32 = @truncate(delone.triangles.items.len);
            if (delone.checkOnEdge(triangle, point)) |edge| {
                const nei = delone.triangles.items[triangle.neighbors[edge]];

                const c_ind = edge;
                const a_ind = (edge + 1) % 3;
                const b_ind = (edge + 2) % 3;

                const c = triangle.nodes[c_ind];
                const a = triangle.nodes[a_ind];

                const d_ind = findUniqueIndex(nei.nodes, a, c);

                const b = triangle.nodes[b_ind];
                const d = nei.nodes[d_ind];

                const ab = triangle.neighbors[a_ind];
                const bc = triangle.neighbors[b_ind];
                const da = nei.neighbors[d_ind];
                const cd = nei.neighbors[(d_ind + 2) % 3];

                const ind1 = triangle.index;
                const ind2 = n;
                const ind3 = nei.index;
                const ind4 = n + 1;

                const first: Triangle = .{ .nodes = [_]u32{ a, b, i }, .neighbors = [_]u32{ ab, ind2, ind4 }, .index = ind1 };
                const second: Triangle = .{ .nodes = [_]u32{ b, c, i }, .neighbors = [_]u32{ bc, ind3, ind1 }, .index = ind2 };
                const third: Triangle = .{ .nodes = [_]u32{ c, d, i }, .neighbors = [_]u32{ cd, ind4, ind2 }, .index = ind3 };
                const fourth: Triangle = .{ .nodes = [_]u32{ d, a, i }, .neighbors = [_]u32{ da, ind1, ind3 }, .index = ind4 };

                delone.triangles.items[triangle.index] = first;
                delone.triangles.items[nei.index] = third;
                try delone.triangles.append(gpa, second);
                try delone.triangles.append(gpa, fourth);

                delone.updateNeighbor(bc, triangle.index, ind2);
                delone.updateNeighbor(da, nei.index, ind4);

                const new_triangles = &[_]Triangle{ first, second, third, fourth };
                try delone.queueTrianglesCheck(new_triangles);
                try delone.addToCache(new_triangles);
            } else {
                const nodes = triangle.nodes;
                const neighbors = triangle.neighbors;

                const ind1 = triangle.index;
                const ind2 = n;
                const ind3 = n + 1;
                const first: Triangle = .{ .nodes = [_]u32{ nodes[0], nodes[1], i }, .neighbors = [_]u32{ neighbors[0], ind2, ind3 }, .index = ind1 };
                const second: Triangle = .{ .nodes = [_]u32{ nodes[1], nodes[2], i }, .neighbors = [_]u32{ neighbors[1], ind3, ind1 }, .index = ind2 };
                const third: Triangle = .{ .nodes = [_]u32{ nodes[2], nodes[0], i }, .neighbors = [_]u32{ neighbors[2], ind1, ind2 }, .index = ind3 };

                delone.triangles.items[triangle.index] = first;
                try delone.triangles.append(gpa, second);
                try delone.triangles.append(gpa, third);

                delone.updateNeighbor(neighbors[1], triangle.index, ind2);
                delone.updateNeighbor(neighbors[2], triangle.index, ind3);

                const new_triangles = &[_]Triangle{ first, second, third };
                try delone.queueTrianglesCheck(new_triangles);
                try delone.addToCache(new_triangles);
            }

            try delone.fixTriangles();

            const m_f = @as(f64, @floatFromInt(delone.cache.m));
            if (@as(f64, @floatFromInt(normalized.items.len)) > delone.cache.r * m_f * m_f) {
                try delone.cache.resize();
            }
        }

        return .{
            .points = try normalization.denormalize(gpa, delone.points, aabb),
            .triangles = try delone.resultTriangles(),
        };
    }

    fn resultTriangles(self: Delone) ![]const Triangle {
        const gpa = self.allocator;

        var filtered: std.ArrayList(Triangle) = try .initCapacity(gpa, self.triangles.items.len);
        blk: for (self.triangles.items) |triangle| {
            for (triangle.nodes) |node| {
                if (node >= self.points.items.len - 3) continue :blk;
            }
            try filtered.append(gpa, triangle);
        }

        const remap = try gpa.alloc(u32, self.triangles.items.len);
        defer gpa.free(remap);
        @memset(remap, Triangle.null_index);

        for (filtered.items, 0..) |tri, new_i| {
            remap[tri.index] = @intCast(new_i);
        }

        for (filtered.items) |*tri| {
            for (&tri.neighbors) |*nei| {
                if (nei.* == Triangle.null_index) continue;
                nei.* = remap[nei.*];
            }
        }

        for (filtered.items, 0..) |*tri, new_i| {
            tri.index = @intCast(new_i);
        }

        return try filtered.toOwnedSlice(gpa);
    }

    fn addToCache(self: *Delone, triangles: []const Triangle) !void {
        for (triangles) |triangle| {
            self.cache.putTriangle(self.triangleCenter(triangle), triangle.index);
        }
    }

    fn queueTrianglesCheck(self: *Delone, triangles: []const Triangle) !void {
        for (triangles) |tr| {
            try self.edges_queue.pushBack(self.allocator, .{ .edge_index = 0, .triangle = tr.index });
        }
    }

    fn fixTriangles(self: *Delone) !void {
        while (self.edges_queue.popFront()) |edge| {
            try self.fixForEdge(edge);
        }
    }

    fn fixForEdge(self: *Delone, edge: Edge) !void {
        const points = self.points.items;

        const trinagle = self.triangles.items[edge.triangle];

        if (trinagle.neighbors[edge.edge_index] == Triangle.null_index) return;
        const nei = self.triangles.items[trinagle.neighbors[edge.edge_index]];

        const adjacent = edge.edge_index;

        const b_ind = trinagle.nodes[adjacent];
        const a_ind = trinagle.nodes[(adjacent + 1) % 3];
        const d_ind = trinagle.nodes[(adjacent + 2) % 3];

        const nei_adjacent = std.mem.findScalar(u32, &nei.nodes, a_ind) orelse return;
        if (nei.nodes[(nei_adjacent + 1) % 3] != b_ind) return;

        const c_ind = nei.nodes[(nei_adjacent + 2) % 3];

        const a = points[a_ind];
        const b = points[b_ind];
        const d = points[d_ind];
        const c = points[c_ind];

        const da = d.vecTo(a);
        const db = d.vecTo(b);
        const ca = c.vecTo(a);
        const cb = c.vecTo(b);

        const cos_alpha = da.scalarProduct(db);
        const cos_beta = cb.scalarProduct(ca);

        const should_flip = if (cos_alpha < 0 and cos_beta < 0)
            true
        else if (cos_alpha >= 0 and cos_beta >= 0)
            false
        else blk: {
            const sin_alpha = @abs(da.cross(db));
            const sin_beta = @abs(cb.cross(ca));
            break :blk sin_alpha * cos_beta + sin_beta * cos_alpha < 0;
        };

        if (should_flip) {
            if (a.orientationRobust(d, c) <= 1e-9 or b.orientationRobust(c, d) <= 1e-9) return;

            const first: Triangle = .{ .nodes = [_]u32{ d_ind, c_ind, a_ind }, .neighbors = [_]u32{ nei.index, nei.neighbors[(nei_adjacent + 2) % 3], trinagle.neighbors[(adjacent + 1) % 3] }, .index = trinagle.index };
            const second: Triangle = .{ .nodes = [_]u32{ c_ind, d_ind, b_ind }, .neighbors = [_]u32{ trinagle.index, trinagle.neighbors[(adjacent + 2) % 3], nei.neighbors[(nei_adjacent + 1) % 3] }, .index = nei.index };

            self.triangles.items[first.index] = first;
            self.triangles.items[second.index] = second;

            self.updateNeighbor(trinagle.neighbors[(adjacent + 2) % 3], trinagle.index, second.index);
            self.updateNeighbor(nei.neighbors[(nei_adjacent + 2) % 3], nei.index, first.index);

            for (&[_]Triangle{ first, second }) |tr| {
                for (1..3) |i| {
                    try self.edges_queue.pushBack(self.allocator, .{ .edge_index = @truncate(i), .triangle = tr.index });
                }
            }
        }
    }

    fn updateNeighbor(self: *Delone, nei_index: u32, old_tr: u32, new_tr: u32) void {
        if (nei_index == Triangle.null_index) return;

        for (0..3) |i| {
            if (self.triangles.items[nei_index].neighbors[i] == old_tr) {
                self.triangles.items[nei_index].neighbors[i] = new_tr;
            }
        }
    }

    fn findTriangleCache(self: *Delone, point: Point2) Triangle {
        const start = self.triangles.items[self.cache.getTriangleIndex(point)];

        return findTriangle(self.points.items, self.triangles.items, point, start);
    }

    fn checkOnEdge(self: Delone, triangle: Triangle, point: Point2) ?u32 {
        for (0..3, 1..4) |a_index, b_index| {
            const nodes = triangle.nodes;
            const a = self.points.items[nodes[a_index]];
            const b = self.points.items[nodes[b_index % 3]];

            const dist = point.magnitude(point.projectOnEdge(a, b));

            if (dist < common.constants.F32_EPSILON) {
                return @truncate(a_index);
            }
        }

        return null;
    }

    fn triangleCenter(self: Delone, triangle: Triangle) Point2 {
        var x: f32 = 0;
        var y: f32 = 0;

        for (triangle.nodes) |index| {
            const point = self.points.items[index];
            x += point.x;
            y += point.y;
        }

        return .{ .x = x / 3, .y = y / 3 };
    }
};

pub fn findTriangle(points: []const Point2, triangles: []const Triangle, point: Point2, start: Triangle) Triangle {
    var current_triangle = start;
    var steps: usize = 0;

    blk: while (true) {
        if (steps > triangles.len) {
            return findTriangleLinear(points, triangles, point) orelse current_triangle;
        }
        steps += 1;

        for (0..3, 1..4) |a_index, b_index| {
            const nodes = current_triangle.nodes;
            const a = points[nodes[a_index]];
            const b = points[nodes[b_index % 3]];

            if (point.orientationRobust(a, b) < -1e-9) {
                current_triangle = triangles[current_triangle.neighbors[a_index]];
                continue :blk;
            }
        }

        break :blk;
    }
    return current_triangle;
}

fn findTriangleLinear(points: []const Point2, triangles: []const Triangle, point: Point2) ?Triangle {
    blk: for (triangles) |triangle| {
        for (0..3, 1..4) |a_index, b_index| {
            const nodes = triangle.nodes;
            const a = points[nodes[a_index]];
            const b = points[nodes[b_index % 3]];

            if (point.orientationRobust(a, b) < -1e-9) continue :blk;
        }

        return triangle;
    }

    return null;
}

fn findUniqueIndex(values: [3]u32, a: u32, b: u32) usize {
    for (values, 0..) |v, i| {
        if (!(v == a or v == b)) {
            return i;
        }
    }

    unreachable;
}

fn makeSuperstructure(allocator: Allocator, points: PointsCollection) !Superstructure {
    var new: std.ArrayList(Point2) = try .initCapacity(allocator, points.items.len + 3);
    new.appendSliceAssumeCapacity(points.items);

    new.appendAssumeCapacity(.{ .x = -10, .y = -10 });
    new.appendAssumeCapacity(.{ .x = 10, .y = -10 });
    new.appendAssumeCapacity(.{ .x = 0, .y = 10 });

    const n: u32 = @truncate(new.items.len);
    const triangle: Triangle = .{
        .nodes = [_]u32{ n - 3, n - 2, n - 1 },
        .neighbors = [_]u32{ Triangle.null_index, Triangle.null_index, Triangle.null_index },
        .index = 0,
    };

    var new_collection = points;
    new_collection.superstructure = n;
    new_collection.items = new.toOwnedSliceAssert();

    return .{ .points = new_collection, .triangle = triangle };
}
