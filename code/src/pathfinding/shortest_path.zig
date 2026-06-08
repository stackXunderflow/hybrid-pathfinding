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

pub const PointType = enum {
    hull,
    triang,
};

pub const LocalPath = struct {
    points: []const u32,
};

const QueueItem = struct {
    weight: f32,
    node: u32,

    fn compareFn(_: void, a: QueueItem, b: QueueItem) std.math.Order {
        return std.math.order(a.weight, b.weight);
    }
};

const MapItem = struct {
    weight: f32,
    prev: u32,
};

pub fn find(allocator: Allocator, geometry: local.LocalGeometry, from: u32, to: u32) !?LocalPath {
    const graph = geometry.graph;

    std.debug.assert(from < graph.points.len);
    std.debug.assert(to < graph.points.len);

    var map: std.AutoHashMap(u32, MapItem) = .init(allocator);
    try map.put(from, .{ .weight = 0, .prev = std.math.maxInt(u32) });
    defer map.deinit();

    var queue: std.PriorityQueue(QueueItem, void, QueueItem.compareFn) = .empty;
    defer queue.deinit(allocator);
    try queue.push(allocator, .{ .node = from, .weight = 0 });

    blk: while (queue.pop()) |current| {
        const connections = graph.connections.get(current.node).?;
        for (connections) |conn| {
            const next: QueueItem = .{ .weight = current.weight + conn.weight, .node = conn.to };

            const old = map.get(next.node);
            if (old == null or old.?.weight > next.weight) {
                try map.put(next.node, .{ .weight = next.weight, .prev = current.node });
                try queue.push(allocator, next);

                if (next.node == to) {
                    break :blk;
                }
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

    return .{ .points = points };
}
