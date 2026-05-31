const std = @import("std");
const Allocator = std.mem.Allocator;

const common = @import("../common.zig");
const Point2 = common.Point2;

/// Одна координата scrambled Halton-последовательности.
/// index считается с 1 (как принято в Halton).
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

/// Генератор равномерно-распределённых точек в прямоугольнике
/// с помощью scrambled Halton (база 2 по X, база 3 по Y).
pub const PointGenerator = struct {
    density: f32, // точек на единицу площади
    width: f32,
    height: f32,
    seed: u64, // только для выбора scramble

    /// Возвращает ~ density*width*height точек в диапазоне
    /// [-width/2 .. +width/2] × [-height/2 .. +height/2].
    /// Память нужно освободить через gpa.
    pub fn generateHallPoints2D(self: PointGenerator, gpa: Allocator) ![]Point2 {
        const n: usize = @intFromFloat(@max(0, @round(self.density * self.width * self.height)));
        if (n == 0) return &.{};

        var prng: std.Random.DefaultPrng = .init(self.seed);
        const rnd = prng.random();
        const sx: u32 = rnd.uintAtMost(u32, 99) + 1;
        const sy: u32 = rnd.uintAtMost(u32, 99) + 1;

        const ox = -self.width / 2.0;
        const oy = -self.height / 2.0;

        const points = try gpa.alloc(Point2, n);
        for (points, 0..) |*p, i| {
            const idx: u32 = @intCast(i + 1);
            p.x = halton(idx, 2, sx) * self.width + ox;
            p.y = halton(idx, 3, sy) * self.height + oy;
        }
        return points;
    }
};
