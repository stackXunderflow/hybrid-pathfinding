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
        if (@abs(point.y) > 1) return 0;
        if (@abs(point.x) > 1) return 0;

        const x: u32 = @intFromFloat(@floor(point.x * m));
        const y: u32 = @intFromFloat(@floor(point.y * m));
        const clamped_x = std.math.clamp(x, 0, self.m - 1);
        const clamped_y = std.math.clamp(y, 0, self.m - 1);
        return clamped_y * self.m + clamped_x;
    }

    pub fn getTriangleIndex(self: Cache, point: Point2) u32 {
        return self.cache[self.getCell(point)];
    }

    pub fn putTriangle(self: *Cache, center: Point2, triangle: u32) void {
        self.cache[self.getCell(center)] = triangle;
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
