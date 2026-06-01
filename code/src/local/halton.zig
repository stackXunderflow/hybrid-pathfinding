const std = @import("std");
const Allocator = std.mem.Allocator;

const common = @import("../common.zig");
const Point2 = common.Point2;

pub fn halton(index: u32, base: u32, scramble: u32) f32 {
    var res: f32 = 0.0;
    var frac: f32 = 1.0 / @as(f32, @floatFromInt(base));
    var i = index;

    while (i > 0) {
        const digit = (i % base + scramble) % base;
        res += @as(f32, @floatFromInt(digit)) * frac;
        i /= base;
        frac /= @as(f32, @floatFromInt(base));
    }
    return res;
}

pub fn generateHallPoints2D(gpa: Allocator, width: f32, height: f32, ox: f32, oy: f32, density: f32, seed: u64) ![]Point2 {
    const n: usize = @floor(density * width * height);

    var prng: std.Random.DefaultPrng = .init(seed);
    const rnd = prng.random();
    const sx: u32 = rnd.uintAtMost(u32, 99) + 1;
    const sy: u32 = rnd.uintAtMost(u32, 99) + 1;

    const points = try gpa.alloc(Point2, n);
    for (points, 1..) |*p, i| {
        const idx: u32 = @intCast(i);
        p.x = halton(idx, 2, sx) * width + ox;
        p.y = halton(idx, 3, sy) * height + oy;
    }
    return points;
}
