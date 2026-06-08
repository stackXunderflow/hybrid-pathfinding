const std = @import("std");

pub const constants = struct {
    pub const GLOBAL_GEOMETRY_HULL_DELTA: f32 = 1.05;
    pub const F32_EPSILON = 0.001;
    pub const LOCAL_GEOMETRY_DANGER_DELTA: f32 = 1.051;
    pub const EDGE_POINTS_OFFSET: f32 = 1.049;
    pub const POINTS_DENSITY_PER_ROBOT_AREA = 3;
};

pub const SceneBorders = struct {
    bottom_left: Point2,
    top_right: Point2,
};

pub const Robot = struct { radius: f32, start: Point2, end: Point2 };

pub const Point2 = struct {
    x: f32,
    y: f32,

    pub fn vecTo(from: Point2, to: Point2) Vec2 {
        return .{ .x = to.x - from.x, .y = to.y - from.y };
    }

    pub fn plus(self: Point2, vec: Vec2) Point2 {
        return .{ .x = self.x + vec.x, .y = self.y + vec.y };
    }

    pub fn magnitude(self: Point2, other: Point2) f32 {
        return self.vecTo(other).len();
    }

    pub fn orientation(self: Point2, a: Point2, b: Point2) f32 {
        return a.vecTo(b).cross(a.vecTo(self));
    }

    pub fn orientationRobust(self: Point2, a: Point2, b: Point2) f64 {
        const ax: f64 = a.x;
        const ay: f64 = a.y;
        const bx: f64 = b.x;
        const by: f64 = b.y;
        const px: f64 = self.x;
        const py: f64 = self.y;
        return (bx - ax) * (py - ay) - (by - ay) * (px - ax);
    }

    pub fn projectOnEdge(self: Point2, a: Point2, b: Point2) Point2 {
        const ab = Point2.vecTo(a, b);
        const ap = Point2.vecTo(a, self);
        const len = ab.scalarProduct(ab);
        const t = std.math.clamp(ap.scalarProduct(ab) / len, 0, 1);
        return a.plus(ab.scale(t));
    }
};

pub const Vec2 = struct {
    x: f32,
    y: f32,

    pub fn normilize(self: Vec2) !Vec2 {
        const length = std.math.sqrt(self.x * self.x + self.y * self.y);
        return .{ .x = self.x / length, .y = self.y / length };
    }

    pub fn rotateRight90(self: Vec2) !Vec2 {
        return .{ .x = self.y, .y = -self.x };
    }

    pub fn plus(self: Vec2, other: Vec2) Vec2 {
        return Vec2{
            .x = self.x + other.x,
            .y = self.y + other.y,
        };
    }

    pub fn scale(self: Vec2, mul: f32) Vec2 {
        return .{ .x = self.x * mul, .y = self.y * mul };
    }

    pub fn cross(self: Vec2, other: Vec2) f32 {
        return self.x * other.y - self.y * other.x;
    }

    pub fn scalarProduct(self: Vec2, other: Vec2) f32 {
        return self.x * other.x + self.y * other.y;
    }

    pub fn len(self: Vec2) f32 {
        return std.math.sqrt(self.x * self.x + self.y * self.y);
    }
};

pub const AABB = struct {
    Xmin: f32,
    Ymin: f32,
    Xmax: f32,
    Ymax: f32,

    pub fn fromPoints(points: []const Point2) AABB {
        var max_y: f32 = points[0].y;
        var min_y: f32 = points[0].y;
        var max_x: f32 = points[0].x;
        var min_x: f32 = points[0].x;

        for (points[1..]) |point| {
            max_x = @max(max_x, point.x);
            min_x = @min(min_x, point.x);
            max_y = @max(max_y, point.y);
            min_y = @min(min_y, point.y);
        }

        return .{ .Xmin = min_x, .Ymin = min_y, .Xmax = max_x, .Ymax = max_y };
    }

    pub fn width(self: AABB) f32 {
        return self.Xmax - self.Xmin;
    }

    pub fn height(self: AABB) f32 {
        return self.Ymax - self.Ymin;
    }

    pub fn containsPoint(self: AABB, point: Point2) bool {
        return point.x >= self.Xmin and point.x <= self.Xmax and point.y >= self.Ymin and point.y <= self.Ymax;
    }

    pub fn expand(self: AABB, distance: f32) AABB {
        return .{ .Xmin = self.Xmin - distance, .Ymin = self.Ymin - distance, .Xmax = self.Xmax + distance, .Ymax = self.Ymax + distance };
    }
};

pub const Mesh = struct {
    points: []const Point2,
};

pub const Blob = struct {
    points: []const Point2,
    aabb: AABB,

    pub fn fromPoints(points: []const Point2) Blob {
        return .{ .points = points, .aabb = .fromPoints(points) };
    }

    pub fn containsPoint(self: Blob, point: Point2) bool {
        if (!self.aabb.containsPoint(point)) return false;
        for (0..self.points.len, 1..) |a, b| {
            const start = self.points[a];
            const end = self.points[b % self.points.len];
            if (point.orientation(start, end) <= 0) {
                return false;
            }
        }
        return true;
    }
};
