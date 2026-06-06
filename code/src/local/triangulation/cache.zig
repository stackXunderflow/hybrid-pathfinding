const std = @import("std");
const Allocator = std.mem.Allocator;

const common = @import("../../common.zig");
const Point2 = common.Point2;

pub const Cache = struct {
    allocator: Allocator,
    r: f32,
    m: u32,
    cache: []u32,

    pub fn init(gpa: Allocator, size: u32) !Cache {
        const cache = try gpa.alloc(u32, size * size);
        @memset(cache, 0);

        return .{ .allocator = gpa, .r = 4, .m = size, .cache = cache };
    }

    pub fn deinit(self: *Cache) void {
        self.allocator.free(self.cache);
    }

    pub fn getCell(self: Cache, point: Point2) u32 {
        const m: f32 = @floatFromInt(self.m);
        const row: u32 = @intFromFloat(point.y / m);
        const column: u32 = @intFromFloat(point.x / m);

        return row * self.m + column;
    }

    pub fn getTriangleIndex(self: Cache, point: Point2) u32 {
        return self.cache[self.getCell(point)];
    }

    pub fn resize(self: *Cache) !void {
        const size = self.m * 2;
        const cache = try self.allocator.alloc(u32, size * size);

        for (self.cache, 0..) |old, i| {
            const row = i / self.m;
            const column = i % self.m;

            cache[row * 2 * size + column * 2] = old;
            cache[row * 2 * size + column * 2 + 1] = old;
            cache[(row * 2 + 1) * size + column * 2] = old;
            cache[(row * 2 + 1) * size + column * 2 + 1] = old;
        }

        self.allocator.free(self.cache);
        self.cache = cache;
        self.m = size;
    }
};
