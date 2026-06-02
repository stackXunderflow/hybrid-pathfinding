const common = @import("../common.zig");
const Mesh = common.Mesh;
const Point2 = common.Point2;
const Vec2 = common.Vec2;

pub fn rayIntersection(mesh: Mesh, point: Point2) bool {
    if (mesh.points.len < 3) return false;

    var count: u32 = 0;

    for (0..mesh.points.len) |i| {
        const current = mesh.points[i];
        const next = mesh.points[(i + 1) % mesh.points.len];

        if ((current.y > point.y) != (next.y > point.y)) {
            const x_inters = current.x + (point.y - current.y) * (next.x - current.x) / (next.y - current.y);
            if (x_inters > point.x) {
                count += 1;
            }
        }
    }

    return count % 2 == 1;
}

pub fn distanceToSegment(point: Point2, a: Point2, b: Point2) f32 {
    const ab = Point2.vecTo(a, b);
    const ap = Point2.vecTo(a, point);
    const len2 = ab.scalarProduct(ab);
    if (len2 == 0.0) {
        return ap.len();
    }
    var t = ap.scalarProduct(ab) / len2;
    if (t < 0.0) t = 0.0;
    if (t > 1.0) t = 1.0;
    const proj = a.plus(ab.scale(t));
    const diff = Point2.vecTo(point, proj);
    return diff.len();
}

pub fn dangerIntersection(mesh: Mesh, point: Point2, dangerLen: f32) bool {
    if (rayIntersection(mesh, point)) {
        return true;
    }
    const n = mesh.points.len;
    for (0..n) |i| {
        const curr = mesh.points[i];
        const next = mesh.points[(i + 1) % n];
        const dist = distanceToSegment(point, curr, next);
        if (dist < dangerLen) {
            return true;
        }
    }
    return false;
}
