const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const common = @import("common.zig");
const Mesh = common.Mesh;
const Point2 = common.Point2;
const Vec2 = common.Vec2;
const math = std.math;
const F32_EPSILON = common.F32_EPSILON;

pub const GlobalGeometry = struct {
    arena: ArenaAllocator,
    blobs: []const BlobContent,

    pub fn getBlobs(self: GlobalGeometry) ![]const BlobContent {
        return self.blobs;
    }
};

pub const BlobContent = struct {
    blob: Mesh,
    meshs: []const Mesh,
};

pub const Pair = struct {
    id1: usize,
    id2: usize,
};

pub const coordIdType = struct {
    coord: f32,
    id: usize,
    pointType: usize,
};

pub const AABB = struct {
    id: usize,
    Xmin: f32,
    Ymin: f32,
    Xmax: f32,
    Ymax: f32,
};

fn pointLessThan(_: void, a: Point2, b: Point2) bool {
    if (!math.approxEqAbs(f32, a.x, b.x, F32_EPSILON)) return a.x < b.x;
    return a.y < b.y;
}

fn orientation(a: Point2, b: Point2, c: Point2) f32 {
    return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
}

fn makeVec(a: Point2, b: Point2) Vec2 {
    return Vec2{ .x = b.x - a.x, .y = b.y - a.y };
}

fn andrewAlgorithm(allocator: Allocator, mesh: Mesh) !Mesh {
    const points = try allocator.dupe(Point2, mesh.points);
    if (points.len < 3) {
        @panic("У меша меньше трех точек! Нельзя построить выпуклую оболочку");
    }

    std.mem.sort(Point2, points, {}, pointLessThan);

    var hull: std.ArrayList(Point2) = .empty;
    defer hull.deinit(allocator);

    for (points) |p| {
        while (hull.items.len >= 2 and
            orientation(hull.items[hull.items.len - 2], hull.items[hull.items.len - 1], p) <= 0)
        {
            _ = hull.pop();
        }
        try hull.append(allocator, p);
    }

    const lower_limit = hull.items.len + 1;

    var i: usize = points.len - 1;
    while (i > 0) {
        i -= 1;
        const p = points[i];
        while (hull.items.len >= lower_limit and
            orientation(hull.items[hull.items.len - 2], hull.items[hull.items.len - 1], p) <= 0)
        {
            _ = hull.pop();
        }
        try hull.append(allocator, p);
    }

    _ = hull.pop();

    return .{ .points = try hull.toOwnedSlice(allocator) };
}

fn increaseArea(allocator: Allocator, mesh: Mesh, robotRadius: f32) !Mesh {
    const increaseLen = robotRadius * common.constants.GLOBAL_GEOMETRY_HULL_DELTA;
    const points = mesh.points;

    var biggerHull = try allocator.alloc(Point2, points.len);

    for (points, 0..) |_, index| {
        const next = (index + 1) % points.len;
        const prev = (index + points.len - 1) % points.len;

        const vecB = makeVec(points[index], points[next]);
        const vecA = makeVec(points[prev], points[index]);

        const normalizedA = try vecA.normilize();
        const normalizedB = try vecB.normilize();
        const normalB = try normalizedB.rotateRight90();
        const normalA = try normalizedA.rotateRight90();

        const normal = normalA.plus(normalB);

        const vecE = try normal.normilize();

        const sinVec = vecE.x * normalA.x + vecE.y * normalA.y;

        const newPoint = Point2{
            .x = points[index].x + vecE.x * (increaseLen / sinVec),
            .y = points[index].y + vecE.y * (increaseLen / sinVec),
        };

        biggerHull[index] = newPoint;
    }

    return .{ .points = biggerHull };
}

fn sortRule(_: void, a: coordIdType, b: coordIdType) bool {
    if (!math.approxEqAbs(f32, a.coord, b.coord, F32_EPSILON)) return a.coord < b.coord;
    return a.pointType < b.pointType;
}

pub fn BroadPhase(allocator: Allocator, blobs: []const BlobContent) ![]const Pair {
    const length = blobs.len;

    var aabbs: std.ArrayList(AABB) = try .initCapacity(allocator, length);
    var minmaxXs: std.ArrayList(coordIdType) = try .initCapacity(allocator, length * 2);

    for (blobs, 0..) |blob, i| {
        var maxY: f32 = -math.inf(f32);
        var minY: f32 = math.inf(f32);
        var maxX: f32 = -math.inf(f32);
        var minX: f32 = math.inf(f32);
        const points = blob.blob.points;
        for (points) |point| {
            maxX = @max(maxX, point.x);
            minX = @min(minX, point.x);
            maxY = @max(maxY, point.y);
            minY = @min(minY, point.y);
        }
        try aabbs.append(allocator, AABB{ .id = i, .Xmin = minX, .Ymin = minY, .Xmax = maxX, .Ymax = maxY });
        try minmaxXs.append(allocator, coordIdType{ .coord = minX, .id = i, .pointType = 0 });
        try minmaxXs.append(allocator, coordIdType{ .coord = maxX, .id = i, .pointType = 1 });
    }
    std.mem.sort(coordIdType, minmaxXs.items, {}, sortRule);

    var pairs: std.ArrayList(Pair) = .empty;

    var active_list: std.ArrayList(usize) = .empty;

    for (minmaxXs.items) |coordinate| {
        const currentId = coordinate.id;
        const current_aabb = aabbs.items[currentId];

        switch (coordinate.pointType) {
            0 => {
                for (active_list.items) |active_elem| {
                    const active_aabb = aabbs.items[active_elem];

                    const intersect_y = (current_aabb.Ymin <= active_aabb.Ymax) and
                        (current_aabb.Ymax >= active_aabb.Ymin);

                    if (intersect_y) {
                        try pairs.append(allocator, Pair{ .id1 = current_aabb.id, .id2 = active_aabb.id });
                    }
                }
                try active_list.append(allocator, currentId);
            },
            1 => {
                for (active_list.items, 0..) |active_id, idx| {
                    if (active_id == currentId) {
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

fn SAT(gpa: Allocator, blobs: []const BlobContent, pairs: []const Pair) ![]const Pair {
    var intersections: std.ArrayList(Pair) = .empty;
    for (pairs) |pair| {
        var norm_vectors: std.ArrayList(Vec2) = .empty;
        const pointsA = blobs[pair.id1].blob.points;
        const pointsB = blobs[pair.id2].blob.points;

        for (pointsA, 0..) |_, index| {
            const next = (index + 1) % pointsA.len;

            const vecA = makeVec(pointsA[index], pointsA[next]);

            const normal_vec = try vecA.rotateRight90();

            try norm_vectors.append(gpa, normal_vec);
        }

        for (pointsB, 0..) |_, index| {
            const next = (index + 1) % pointsB.len;

            const vecB = makeVec(pointsB[index], pointsB[next]);

            const normal_vec = try vecB.rotateRight90();

            try norm_vectors.append(gpa, normal_vec);
        }

        var intersect = true;

        for (norm_vectors.items) |vector| {
            var proect_vectorsA: std.ArrayList(f32) = .empty;
            defer proect_vectorsA.deinit(gpa);

            var proect_vectorsB: std.ArrayList(f32) = .empty;
            defer proect_vectorsB.deinit(gpa);

            // Собираем проекции для текущей оси
            for (pointsA) |point| {
                const pk = point.x * vector.x + point.y * vector.y;
                try proect_vectorsA.append(gpa, pk);
            }
            for (pointsB) |point| {
                const pj = point.x * vector.x + point.y * vector.y;
                try proect_vectorsB.append(gpa, pj);
            }

            var min_valA = proect_vectorsA.items[0];
            for (proect_vectorsA.items[1..]) |val| {
                min_valA = @min(min_valA, val);
            }

            var max_valA = proect_vectorsA.items[0];
            for (proect_vectorsA.items[1..]) |val| {
                max_valA = @max(max_valA, val);
            }

            var min_valB = proect_vectorsB.items[0];
            for (proect_vectorsB.items[1..]) |val| {
                min_valB = @min(min_valB, val);
            }

            var max_valB = proect_vectorsB.items[0];
            for (proect_vectorsB.items[1..]) |val| {
                max_valB = @max(max_valB, val);
            }

            if (max_valA < min_valB or max_valB < min_valA) {
                intersect = false;
                break;
            }
        }
        if (intersect) {
            try intersections.append(gpa, pair);
        }
    }
    return try intersections.toOwnedSlice(gpa);
}

fn findRoot(parents: []usize, x: usize) usize {
    if (parents[x] != x) {
        parents[x] = findRoot(parents, parents[x]);
    }
    return parents[x];
}

fn DSU(gpa: Allocator, blobs: []const BlobContent, pairs: []const Pair) ![]const BlobContent {
    var parents: std.ArrayList(usize) = .empty;

    for (0..blobs.len) |index| {
        try parents.append(gpa, index);
    }

    for (pairs) |pair| {
        const root_a = findRoot(parents.items, pair.id1);
        const root_b = findRoot(parents.items, pair.id2);
        if (root_a != root_b) {
            parents.items[root_a] = root_b;
        }
    }
    var dict: std.AutoHashMap(usize, std.ArrayList(usize)) = .init(gpa);
    var meshs: std.ArrayList(BlobContent) = .empty;
    defer meshs.deinit(gpa);
    for (0..blobs.len) |index| {
        try dict.put(index, .empty);
    }

    for (0..blobs.len) |index| {
        const root = findRoot(parents.items, index);
        if (dict.getPtr(root)) |list_ptr| {
            try list_ptr.append(gpa, index);
        }
    }

    var it = dict.iterator();
    while (it.next()) |entry| {
        var points: std.ArrayList(Point2) = .empty;
        for (entry.value_ptr.items) |index| {
            for (blobs[index].blob.points) |point| {
                try points.append(gpa, point);
            }
        }

        if (points.items.len == 0) continue;
        const mesh = Mesh{ .points = try points.toOwnedSlice(gpa) };
        const blob = try andrewAlgorithm(gpa, mesh);

        try meshs.append(gpa, .{ .blob = blob, .meshs = &.{} });
    }
    return try meshs.toOwnedSlice(gpa);
}

fn intersectBlobs(gpa: Allocator, blobs: []const BlobContent) ![]const BlobContent {
    var current_blobs = blobs;
    while (true) {
        const pairs = try BroadPhase(gpa, current_blobs);
        const intersect_const = try SAT(gpa, current_blobs, pairs);
        if (intersect_const.len == 0) {
            return current_blobs;
        }
        const res_blobs = try DSU(gpa, current_blobs, intersect_const);
        if (res_blobs.len == current_blobs.len) {
            return res_blobs;
        }
        current_blobs = res_blobs;
    }
}

pub fn globalGeometry(gpa: Allocator, meshs: []const Mesh, robotRadius: f32) !GlobalGeometry {
    var arena: ArenaAllocator = .init(gpa);
    const allocator = arena.allocator();

    var blobs: std.ArrayList(BlobContent) = try .initCapacity(allocator, meshs.len);

    for (meshs) |mesh| {
        const blob = try andrewAlgorithm(allocator, mesh);
        const meshsAlloc = try allocator.alloc(Mesh, 1);
        meshsAlloc[0] = mesh;
        blobs.appendAssumeCapacity(.{ .blob = blob, .meshs = meshsAlloc });
    }

    for (blobs.items, 0..) |blob, index| {
        const biggerBlob = try increaseArea(allocator, blob.blob, robotRadius);
        blobs.items[index].blob = biggerBlob;
    }
    const new_blobs = try blobs.toOwnedSlice(allocator);
    const res_blobs = try intersectBlobs(gpa, new_blobs);

    return .{ .arena = arena, .blobs = res_blobs };
}
