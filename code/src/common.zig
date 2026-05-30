const std = @import("std");

pub const F32_EPSILON = 0.000001;
pub const constants = struct {
    pub const GLOBAL_GEOMETRY_HULL_DELTA: f32 = 1.05;
};

pub const Point2 = struct { x: f32, y: f32 };

pub const Mesh = struct {
    points: []const Point2,
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

pub const Blob = struct {
    point: []Point2,
};
