const std = @import("std");
const Allocator = std.mem.Allocator;

const common = @import("../common.zig");
const Point2 = common.Point2;
const AABB = common.AABB;
const dbg = @import("../dbg.zig");
const global = @import("../global.zig");
const BlobContent = global.BlobContent;
const Output = @import("../planner.zig").Output;
const intersection = @import("intersection.zig");
const triangulation = @import("triangulation.zig");
const Triangle = triangulation.Triangle;
const Triangulation = triangulation.Triangulation;

pub const Connection = struct {
    to: u32,
    len: f32,
};

pub const Graph = struct {
    points: []const Point2,
    boundary_count: u32,
    triangle_to_point: []const u32,
    connections: std.AutoHashMapUnmanaged(u32, []const Connection),

    pub fn deinit(self: *Graph, gpa: Allocator) void {
        var it = self.connections.iterator();
        while (it.next()) |entry| {
            gpa.free(entry.value_ptr.*);
        }
        self.connections.deinit(gpa);
        gpa.free(self.points);
    }

    pub fn findNearestHullPoint(self: Graph, point: Point2) u32 {
        var nearest: u32 = 0;
        var min_dist = std.math.floatMax(f32);

        for (self.points[0..self.boundary_count], 0..) |hull_point, i| {
            const new = hull_point.magnitude(point);
            if (new < min_dist) {
                min_dist = new;
                nearest = @truncate(i);
            }
        }

        return nearest;
    }

    pub fn asOutputAbstract(self: Graph, allocator: Allocator) !Output.AbstractStruct {
        var edges: std.ArrayList(u32) = .empty;

        var it = self.connections.keyIterator();
        while (it.next()) |node| {
            for (self.connections.get(node.*).?) |conn| {
                try edges.append(allocator, node.*);
                try edges.append(allocator, conn.to);
            }
        }

        return .{ .indices = try edges.toOwnedSlice(allocator), .points = self.points };
    }
};

pub const null_node = std.math.maxInt(u32);

pub fn build(gpa: Allocator, triang: Triangulation, blob: BlobContent, expanded_aabbs: []const AABB, danger_len: f32) !Graph {
    const collection = triang.points;
    const all_points = collection.items;
    const boundary_start: u32 = @intCast(collection.obstacles);
    const boundary_count: u32 = @intCast(collection.boundary - collection.obstacles);

    var center_indices = try gpa.alloc(u32, triang.triangles.len);
    @memset(center_indices, null_node);

    var valid_center_count: u32 = 0;
    var centers = try std.ArrayList(Point2).initCapacity(gpa, triang.triangles.len);
    defer centers.deinit(gpa);

    for (triang.triangles, 0..) |tri, i| {
        const center = triangleCenter(all_points, tri);
        if (!intersection.isValidPoint(center, danger_len, blob, expanded_aabbs)) continue;
        center_indices[i] = boundary_count + valid_center_count;
        valid_center_count += 1;
        try centers.append(gpa, center);
    }

    const graph_points = try gpa.alloc(Point2, boundary_count + valid_center_count);
    @memcpy(graph_points[0..boundary_count], all_points[collection.obstacles..collection.boundary]);
    @memcpy(graph_points[boundary_count..], centers.items);

    const node_count = boundary_count + valid_center_count;
    var adjacency = try gpa.alloc(std.ArrayList(Connection), node_count);
    defer {
        for (adjacency) |*list| list.deinit(gpa);
        gpa.free(adjacency);
    }
    for (adjacency) |*list| {
        list.* = try .initCapacity(gpa, 6);
    }

    for (0..boundary_count) |i| {
        const j = (i + 1) % boundary_count;
        const a: u32 = @intCast(i);
        const b: u32 = @intCast(j);
        const w = graph_points[a].magnitude(graph_points[b]);
        try adjacency[a].append(gpa, .{ .to = b, .len = w });
        try adjacency[b].append(gpa, .{ .to = a, .len = w });
    }

    for (triang.triangles, 0..) |tri, i| {
        const center_node = center_indices[i];
        if (center_node == null_node) continue;

        var boundary_nodes: [3]u32 = undefined;
        var boundary_len: u8 = 0;
        for (tri.nodes) |node| {
            if (node < boundary_start or node >= boundary_start + boundary_count) continue;
            boundary_nodes[boundary_len] = node - boundary_start;
            boundary_len += 1;
        }
        if (boundary_len < 2) continue;

        for (boundary_nodes[0..boundary_len]) |boundary_node| {
            const w = graph_points[center_node].magnitude(graph_points[boundary_node]);
            try adjacency[center_node].append(gpa, .{ .to = boundary_node, .len = w });
            try adjacency[boundary_node].append(gpa, .{ .to = center_node, .len = w });
        }
    }

    for (triang.triangles, 0..) |tri, i| {
        const from = center_indices[i];
        if (from == null_node) continue;

        for (tri.neighbors) |nei_index| {
            if (nei_index == Triangle.null_index) continue;
            const to = center_indices[nei_index];
            if (to == null_node or i >= nei_index) continue;
            const w = graph_points[from].magnitude(graph_points[to]);
            try adjacency[from].append(gpa, .{ .to = to, .len = w });
            try adjacency[to].append(gpa, .{ .to = from, .len = w });
        }
    }

    var connections: std.AutoHashMapUnmanaged(u32, []const Connection) = .empty;
    try connections.ensureTotalCapacity(gpa, node_count);

    for (adjacency, 0..) |*list, i| {
        if (list.items.len == 0) continue;
        const node: u32 = @intCast(i);
        try connections.put(gpa, node, try list.toOwnedSlice(gpa));
    }

    return .{
        .points = graph_points,
        .boundary_count = boundary_count,
        .triangle_to_point = center_indices,
        .connections = connections,
    };
}

pub fn triangleCenter(points: []const Point2, tri: Triangle) Point2 {
    const a = points[tri.nodes[0]];
    const b = points[tri.nodes[1]];
    const c = points[tri.nodes[2]];
    return .{
        .x = (a.x + b.x + c.x) / 3,
        .y = (a.y + b.y + c.y) / 3,
    };
}
