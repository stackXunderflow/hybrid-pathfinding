const std = @import("std");
const Allocator = std.mem.Allocator;

const common = @import("../common.zig");
const Point2 = common.Point2;

const global = @import("../global.zig");
const BlobContent = global.BlobContent;

const dbg = @import("../dbg.zig");
const halton = @import("halton.zig");

/// Генерирует Halton-точки **внутри AABB** одного BlobContent.
///
/// Точки равномерно распределяются по всему прямоугольнику AABB
/// без какого-либо отступа (полное покрытие области).
///
/// Start, End и radius робота передаются для контекста
/// (могут использоваться позже для фильтрации или других нужд).
pub fn addHaltonPointsInBlobAABB(
    gpa: Allocator,
    debugger: *dbg.Debugger,
    blob: BlobContent,
    robot_start: Point2,
    robot_end: Point2,
    robot_radius: f32,
    density: f32,
    seed: u64,
    layer_name: []const u8,
) !void {
    _ = gpa;
    _ = robot_start;
    _ = robot_end;
    _ = robot_radius;

    if (density <= 0) return;

    const aabb = blob.blob.aabb;

    // Используем AABB как есть — без сжатия
    const min_x = aabb.Xmin;
    const max_x = aabb.Xmax;
    const min_y = aabb.Ymin;
    const max_y = aabb.Ymax;

    const w = max_x - min_x;
    const h = max_y - min_y;

    if (w <= 0 or h <= 0) return;

    const n: usize = @intFromFloat(@max(0, @round(density * w * h)));
    if (n == 0) return;

    // Scramble для Halton (так же, как в PointGenerator)
    var prng: std.Random.DefaultPrng = .init(seed);
    const rnd = prng.random();
    const scramble_x: u32 = rnd.uintAtMost(u32, 99) + 1;
    const scramble_y: u32 = rnd.uintAtMost(u32, 99) + 1;

    for (0..n) |i| {
        const idx: u32 = @intCast(i + 1);

        const tx = halton.halton(idx, 2, scramble_x); // [0, 1]
        const ty = halton.halton(idx, 3, scramble_y);

        const px = min_x + tx * w;
        const py = min_y + ty * h;

        if (blob.blob.containsPoint(.{ .x = px, .y = py })) {
            try debugger.point(
                .{ .x = px, .y = py },
                .{ .layout = layer_name },
            );
        }
    }
}
