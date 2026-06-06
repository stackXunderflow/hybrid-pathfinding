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

pub const Delone = struct {
    points: PointsCollection,
    triangles: std.ArrayList(Triangle),
    cache: Cache,

    pub fn run(gpa: Allocator, initial_points: PointsCollection, aabb: AABB) !Triangulation {
        const normalized = try normalization.normalize(gpa, initial_points, aabb);
        const superstructure = try makeSuperstructure(gpa, normalized);
        var triangles: std.ArrayList(Triangle) = .empty;
        try triangles.append(gpa, superstructure.triangle);

        var delone: Delone = .{ .cache = try Cache.init(gpa, 2), .points = superstructure.points, .triangles = triangles };

        for (0..delone.points.boundary) |index| {
            const point = delone.points.items[index];
            const triangle = delone.findTriangle(point);

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
            }
        }

        return .{
            .points = try normalization.denormalize(gpa, delone.points, aabb),
            .triangles = try delone.triangles.toOwnedSlice(gpa),
        };
    }

    fn updateNeighbor(self: *Delone, nei_index: u32, old_tr: u32, new_tr: u32) void {
        if (nei_index == Triangle.null_index) return;

        for (0..3) |i| {
            if (self.triangles.items[nei_index].neighbors[i] == old_tr) {
                self.triangles.items[nei_index].neighbors[i] = new_tr;
            }
        }
    }

    fn findTriangle(self: *Delone, point: Point2) Triangle {
        var current_triangle = self.triangles.items[self.cache.getTriangleIndex(point)];

        blk: while (true) {
            for (0..3, 1..4) |a_index, b_index| {
                const nodes = current_triangle.nodes;
                const a = self.points.items[nodes[a_index]];
                const b = self.points.items[nodes[b_index % 3]];

                if (point.orientation(a, b) < 0) {
                    current_triangle = self.triangles.items[current_triangle.neighbors[a_index]];
                    continue :blk;
                }
            }

            break :blk;
        }
        return current_triangle;
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
};

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
