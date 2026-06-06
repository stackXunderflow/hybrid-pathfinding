const std = @import("std");
const expand = @import("src/local/expand_mesh.zig");
const common = @import("src/common.zig");

pub fn main() !void {
    const mesh: common.Mesh = .{ .points = &.{
        .{ .x = 628, .y = 801 },
        .{ .x = 669, .y = 611 },
        .{ .x = 759, .y = 547 },
        .{ .x = 933, .y = 541 },
        .{ .x = 823, .y = 617 },
        .{ .x = 1112, .y = 720 },
        .{ .x = 824, .y = 711 },
        .{ .x = 901, .y = 878 },
        .{ .x = 740, .y = 803 },
        .{ .x = 617, .y = 891 },
    }};
    const expanded = try expand.expandMesh(std.heap.page_allocator, mesh, 26.275);
    defer std.heap.page_allocator.free(expanded);
    std.debug.print("points: {d}\n", .{expanded.len});
}
