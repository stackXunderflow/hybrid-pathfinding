const std = @import("std");
const common = @import("common.zig");
const Point2 = common.Point2;
const Vec2 = common.Vec2;
const Mesh = common.Mesh;
const ArenaAllocator = std.heap.ArenaAllocator;
const ArrayList = std.ArrayList;
const str = []const u8;

pub const Options = struct {
    layout: ?str = null,
    label: ?str = null,
};

pub const DebugItem = struct {
    type: []const u8,
    point: ?Point2 = null,
    from: ?Point2 = null,
    to: ?Point2 = null,
    points: ?[]const Point2 = null,
    label: ?[]const u8 = null,
};

pub const DebugLayout = struct {
    name: []const u8,
    content: ArrayList(DebugItem),

    pub fn jsonStringify(v: *const DebugLayout, s: *std.json.Stringify) !void {
        try s.write(.{ .name = v.name, .content = v.content.items });
    }
};

pub const Debugger = struct {
    arena: ArenaAllocator,
    layouts: ArrayList(DebugLayout),

    pub fn init(gpa: std.mem.Allocator) !Debugger {
        var arena = ArenaAllocator.init(gpa);
        const allocator = arena.allocator();

        var layouts: ArrayList(DebugLayout) = try .initCapacity(allocator, 1);
        layouts.appendAssumeCapacity(.{ .content = .empty, .name = "default layer" });

        return .{ .arena = arena, .layouts = layouts };
    }

    pub fn deinit(self: *Debugger) void {
        self.arena.deinit();
    }

    fn append_item(self: *Debugger, item: DebugItem, layout_name: ?str) !void {
        const layout: *DebugLayout = try self.find_or_create_layout(layout_name);
        const allocator = self.arena.allocator();

        var clone = item;
        if (clone.label) |label| {
            clone.label = try allocator.dupe(u8, label);
        }

        try layout.content.append(allocator, clone);
    }

    fn find_or_create_layout(self: *Debugger, nullable_layout_name: ?str) !*DebugLayout {
        if (nullable_layout_name) |layout_name| {
            for (self.layouts.items, 0..) |layout, index| {
                if (std.mem.eql(u8, layout_name, layout.name)) {
                    return &self.layouts.items[index];
                }
            }

            const allocator = self.arena.allocator();
            const layer = DebugLayout{
                .name = try allocator.dupe(u8, layout_name),
                .content = try .initCapacity(allocator, 32),
            };

            try self.layouts.append(allocator, layer);
            return &self.layouts.items[self.layouts.items.len - 1];
        } else {
            return &self.layouts.items[0];
        }
    }

    pub fn point(self: *Debugger, p: Point2, o: Options) !void {
        try self.append_item(.{ .type = "point", .point = p, .label = o.label }, o.layout);
    }

    pub fn line(self: *Debugger, p1: Point2, p2: Point2, o: Options) !void {
        try self.append_item(.{ .type = "line", .from = p1, .to = p2, .label = o.label }, o.layout);
    }

    pub fn mesh(self: *Debugger, mesh_points: []const Point2, o: Options) !void {
        const allocator = self.arena.allocator();
        const copy = try allocator.dupe(Point2, mesh_points);
        try self.append_item(.{ .type = "mesh", .points = copy, .label = o.label }, o.layout);
    }
};

test "dbg" {
    const testing = std.testing;
    var debugger = try Debugger.init(testing.allocator);
    defer debugger.deinit();

    try debugger.point(.{ .x = 50, .y = -50.0 }, .{ .layout = "ВАЖНЫЕ ТОЧКИ", .label = "Я ВАЖНАЯ ТОЧКА" });
    // Без слоя
    try debugger.line(.{ .x = 10, .y = 100 }, .{ .x = 600, .y = 32 }, .{ .label = "линия для дебага" });
    // Без слоя и без имени
    try debugger.line(.{ .x = 500, .y = -100 }, .{ .x = 666, .y = 666 }, .{});

    try testing.expectEqual(2, debugger.layouts.items.len);
    try testing.expectEqualStrings("default layer", debugger.layouts.items[0].name);
    try testing.expectEqualStrings("ВАЖНЫЕ ТОЧКИ", debugger.layouts.items[1].name);
    try testing.expectEqual(2, debugger.layouts.items[0].content.items.len);
    try testing.expectEqual(1, debugger.layouts.items[1].content.items.len);
}

test "copy label" {
    const testing = std.testing;
    var debugger = try Debugger.init(testing.allocator);
    defer debugger.deinit();

    {
        const str1 = try std.fmt.allocPrint(testing.allocator, "abc", .{});
        const str2 = try std.fmt.allocPrint(testing.allocator, "def", .{});

        const zero: Point2 = .{ .x = 0, .y = 0 };
        try debugger.point(zero, .{ .label = str1 });
        try debugger.line(zero, zero, .{ .label = str2 });

        testing.allocator.free(str1);
        testing.allocator.free(str2);
    }

    const layer = debugger.layouts.items[0].content.items;
    try testing.expectEqualStrings("abc", layer[0].label.?);
    try testing.expectEqualStrings("def", layer[1].label.?);
}
