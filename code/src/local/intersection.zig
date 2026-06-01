const std = @import("std");

const common = @import("../common.zig");
const Mesh = common.Mesh;
const Point2 = common.Point2;

pub fn rayIntersection(mesh: Mesh, point: Point2) bool {
    if (mesh.points.len < 3) return false;

    var count: u32 = 0;

    for (0..mesh.points.len) |i| {
        const current = mesh.points[i];
        const next = mesh.points[(i + 1) % mesh.points.len];

        // Ребро пересекает горизонтальный луч, идущий вправо от точки
        if ((current.y > point.y) != (next.y > point.y)) {
            const x_inters = current.x + (point.y - current.y) * (next.x - current.x) / (next.y - current.y);
            if (x_inters > point.x) {
                count += 1;
            }
        }
    }

    return count % 2 == 1;
}
