const std = @import("std");
const Allocator = std.mem.Allocator;
const math = std.math;

const common = @import("../common.zig");
const Point2 = common.Point2;
const F32_EPSILON = common.constants.F32_EPSILON;
const global = @import("../global.zig");
const BlobContent = global.BlobContent;
const Pair = global.Pair;

const CoordIdType = struct {
    coord: f32,
    id: usize,
    pointType: usize,
};
fn sortRule(_: void, a: CoordIdType, b: CoordIdType) bool {
    if (!math.approxEqAbs(f32, a.coord, b.coord, F32_EPSILON)) return a.coord < b.coord;
    return a.pointType < b.pointType;
}

pub fn broadPhase(allocator: Allocator, blobs: []const BlobContent) ![]const Pair {
    var minmaxXs = try allocator.alloc(CoordIdType, blobs.len * 2);
    defer allocator.free(minmaxXs);

    for (blobs, 0..) |blob_content, i| {
        const aabb = blob_content.blob.aabb;
        minmaxXs[i * 2] = .{ .coord = aabb.Xmin, .id = i, .pointType = 0 };
        minmaxXs[i * 2 + 1] = .{ .coord = aabb.Xmax, .id = i, .pointType = 1 };
    }
    std.mem.sort(CoordIdType, minmaxXs, {}, sortRule);

    var pairs: std.ArrayList(Pair) = .empty;

    var active_list: std.ArrayList(usize) = .empty;
    defer active_list.deinit(allocator);

    for (minmaxXs) |coordinate| {
        const current_index = coordinate.id;
        const current_aabb = blobs[current_index].blob.aabb;

        switch (coordinate.pointType) {
            0 => {
                for (active_list.items) |active_index| {
                    const active_aabb = blobs[active_index].blob.aabb;

                    const intersect_y = (current_aabb.Ymin <= active_aabb.Ymax) and
                        (current_aabb.Ymax >= active_aabb.Ymin);

                    if (intersect_y) {
                        try pairs.append(allocator, Pair{ .id1 = current_index, .id2 = active_index });
                    }
                }
                try active_list.append(allocator, current_index);
            },
            1 => {
                for (active_list.items, 0..) |active_id, idx| {
                    if (active_id == current_index) {
                        _ = active_list.swapRemove(idx);
                        break;
                    }
                }
            },
            else => {},
        }
    }
    return pairs.toOwnedSlice(allocator);
}
