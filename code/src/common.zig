const std = @import("std");

pub const constants = struct {
    pub const GLOBAL_GEOMETRY_HULL_DELTA: f32 = 1.05;
    pub const F32_EPSILON = 0.000001;
};

pub const Point2 = struct {
    x: f32,
    y: f32,

    pub fn vecTo(from: Point2, to: Point2) Vec2 {
        return .{ .x = to.x - from.x, .y = to.y - from.y };
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
};

pub const Mesh = struct {
    points: []const Point2,

    // fn containsPoint(self: Mesh, point: Point2) bool {

    //Тут должна быть реализация проверки на наличие точки, сделаю позже

    // }
};

pub const Blob = struct {
    points: []const Point2,
    aabb: AABB,

    pub fn fromPoints(points: []const Point2) Blob {
        return .{ .points = points, .aabb = .fromPoints(points) };
    }

    pub fn containsPoint(self: Blob, point: Point2) bool {
        for (0..self.points.len, 1..) |a, b| {
            const start = self.points[a];
            const end = self.points[b % self.points.len];
            const d = (end.x - start.x) * (point.y - start.y) - (end.y - start.y) * (point.x - start.x);
            if (d < 0) {
                return false;
            }
        }
        return true;
    }
};
