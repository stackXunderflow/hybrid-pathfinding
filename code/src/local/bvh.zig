const std = @import("std");

const Allocator = std.mem.Allocator;
const common = @import("../common.zig");
const AABB = common.AABB;
const Blob = common.Blob;
const Point2 = common.Point2;

const BVH_LEAF_MINIMUM_ITEMS = 3;

pub const BVH = struct {
    tree: std.ArrayList(BVHItem),
    aabbs: []const AABB,
    allocator: Allocator,

    pub fn init(allocator: Allocator, hull: Blob, aabbs: []const AABB, robot_radius: f32) !BVH {
        var tree: std.ArrayList(BVHItem) = try .initCapacity(allocator, 16);

        const initial_meshs = try allocator.alloc(u32, aabbs.len);
        for (initial_meshs, 0..) |_, i| {
            initial_meshs[i] = @truncate(i);
        }

        tree.appendAssumeCapacity(.{ .aabb = hull.aabb, .content = .{ .leaf = .{ .meshs = initial_meshs } } });

        var self: BVH = .{ .tree = tree, .aabbs = aabbs, .allocator = allocator };

        try self.recDivide(0, robot_radius * 3);

        return self;
    }

    pub fn deinit(self: *BVH) void {
        recDeinit(self, 0);
        self.tree.deinit(self.allocator);
    }

    fn recDeinit(self: *BVH, current: u32) void {
        switch (self.tree.items[current].content) {
            .root => |root| {
                self.recDeinit(root.next);
                self.recDeinit(root.next + 1);
            },
            .leaf => |leaf| {
                self.allocator.free(leaf.meshs);
            },
        }
    }

    fn recDivide(self: *BVH, current: u32, minimum_leaf_size: f32) !void {
        const element = self.tree.items[current];

        switch (element.content) {
            .root => unreachable,
            .leaf => |leaf| {
                if (needSplit(element.aabb, leaf, minimum_leaf_size)) {
                    defer self.allocator.free(leaf.meshs);

                    const split = try splitLeaf(self, leaf, element.aabb);

                    const n: u32 = @truncate(self.tree.items.len);
                    self.tree.items[current] = .{ .aabb = element.aabb, .content = .{ .root = .{ .next = n } } };
                    try self.tree.append(self.allocator, .{ .aabb = calcAABB(self, split[0]), .content = .{ .leaf = .{ .meshs = split[0] } } });
                    try self.tree.append(self.allocator, .{ .aabb = calcAABB(self, split[1]), .content = .{ .leaf = .{ .meshs = split[1] } } });

                    try recDivide(self, n, minimum_leaf_size);
                    try recDivide(self, n + 1, minimum_leaf_size);
                }
            },
        }
    }

    fn splitLeaf(self: *const BVH, leaf: Leaf, aabb: AABB) ![2][]const u32 {
        const w = aabb.width();
        const h = aabb.height();

        var left: std.ArrayList(u32) = .empty;
        var right: std.ArrayList(u32) = .empty;
        if (w > h) {
            const mid_x = aabb.midX();
            for (leaf.meshs) |index| {
                if (self.aabbs[index].midX() < mid_x) {
                    try left.append(self.allocator, index);
                } else {
                    try right.append(self.allocator, index);
                }
            }
        } else {
            const mid_y = aabb.midY();
            for (leaf.meshs) |index| {
                if (self.aabbs[index].midY() < mid_y) {
                    try left.append(self.allocator, index);
                } else {
                    try right.append(self.allocator, index);
                }
            }
        }

        return [2][]const u32{ try left.toOwnedSlice(self.allocator), try right.toOwnedSlice(self.allocator) };
    }

    fn calcAABB(self: *const BVH, meshs: []const u32) AABB {
        var minX = std.math.floatMax(f32);
        var minY = std.math.floatMax(f32);
        var maxX = -std.math.floatMax(f32);
        var maxY = -std.math.floatMax(f32);

        for (meshs) |index| {
            const aabb = self.aabbs[index];

            minX = @min(aabb.Xmin, minX);
            minY = @min(aabb.Ymin, minY);
            maxX = @max(aabb.Xmax, maxX);
            maxY = @max(aabb.Ymax, maxY);
        }

        return .{ .Xmax = maxX, .Xmin = minX, .Ymax = maxY, .Ymin = minY };
    }

    pub fn iterate(self: BVH, context: anytype, node: u32) !IterResult {
        const current = self.tree.items[node];

        if (!current.aabb.containsPoint(context.point)) return .ok;

        switch (current.content) {
            .root => |root| {
                if (try self.iterate(context, root.next) == .early) return .early;
                if (try self.iterate(context, root.next + 1) == .early) return .early;
            },
            .leaf => |leaf| {
                return try context.check(leaf.meshs);
            },
        }

        return .ok;
    }

    pub const IterResult = enum { early, ok };
};

fn needSplit(aabb: AABB, leaf: Leaf, minimum_leaf_size: f32) bool {
    if (leaf.meshs.len <= BVH_LEAF_MINIMUM_ITEMS) return false;
    if (aabb.width() < minimum_leaf_size or aabb.height() < minimum_leaf_size) return false;
    return true;
}

pub const Root = struct { next: u32 };
pub const Leaf = struct { meshs: []const u32 };

pub const BVHItem = struct {
    aabb: AABB,
    content: union(enum) {
        root: Root,
        leaf: Leaf,
    },
};
