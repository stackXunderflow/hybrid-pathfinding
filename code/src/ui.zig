const std = @import("std");
const Allocator = std.mem.Allocator;
const AutoHashMap = std.AutoHashMap;

const qt6 = @import("libqt6zig");
const QApplication = qt6.QApplication;
const QMainWindow = qt6.QMainWindow;
const QGraphicsScene = qt6.QGraphicsScene;
const QGraphicsView = qt6.QGraphicsView;
const QColor = qt6.QColor;
const QKeyEvent = qt6.QKeyEvent;
const QResizeEvent = qt6.QResizeEvent;
const qnamespace_enums = qt6.qnamespace_enums;
const QGraphicsSceneWheelEvent = qt6.QGraphicsSceneWheelEvent;
const QGraphicsSceneHoverEvent = qt6.QGraphicsSceneHoverEvent;
const QGraphicsSceneMouseEvent = qt6.QGraphicsSceneMouseEvent;
const QWidget = qt6.QWidget;
const QGraphicsPathItem = qt6.QGraphicsPathItem;
const QPainterPath = qt6.QPainterPath;
const QBrush = qt6.QBrush;

const common = @import("common.zig");
const Point = common.Point;
const Mesh = common.Mesh;

const zoom_in_scale = 1.25;
const zoom_out_scale = 0.8;

var qscene: QGraphicsScene = undefined;
var view: QGraphicsView = undefined;

pub const Scene = struct {
    meshs: []const Mesh,
    blobs: []const Mesh,
};

pub fn showBlocking(gpa: Allocator, args: []const [:0]const u8, scene: Scene) !void {
    var arena = std.heap.ArenaAllocator.init(gpa);
    const allocator = arena.allocator();
    defer arena.deinit();

    const argv = try allocator.alloc([:0]u8, args.len);
    defer allocator.free(argv);
    for (args, 0..) |arg, i|
        argv[i] = try allocator.dupeZ(u8, arg);
    var argc: i32 = @intCast(argv.len);
    const qapp = QApplication.New(allocator, &argc, argv);
    defer qapp.Delete();

    const window = QMainWindow.New2();
    defer window.Delete();

    window.SetWindowTitle("brrr");
    window.Resize(490, 520);
    window.SetMinimumSize2(360, 450);

    qscene = QGraphicsScene.New();
    defer qscene.Delete();

    view = QGraphicsView.New2();
    defer view.Delete();

    qscene.OnKeyPressEvent(sceneKeyPressEvent);
    qscene.OnWheelEvent(sceneWheelEvent);
    view.SetDragMode(1);
    view.SetHorizontalScrollBarPolicy(qnamespace_enums.ScrollBarPolicy.ScrollBarAlwaysOn);
    view.SetVerticalScrollBarPolicy(qnamespace_enums.ScrollBarPolicy.ScrollBarAlwaysOn);
    view.OnResizeEvent(viewResizeEvent);

    try loadItems(scene, qscene);

    view.SetScene(qscene);
    view.Show();

    window.SetCentralWidget(view);
    window.Show();

    _ = QApplication.Exec();
}

fn loadItems(scene: Scene, qview: QGraphicsScene) !void {
    const mesh_color = QColor.New14(0, 255, 255, 200);
    defer mesh_color.Delete();
    const mesh_brush = QBrush.New3(mesh_color);
    defer mesh_brush.Delete();

    for (scene.meshs) |mesh| {
        const path = pathFromPoints(mesh.points);
        defer path.Delete();
        const item = QGraphicsPathItem.New2(path);
        item.SetBrush(mesh_brush);
        qview.AddItem(item);
    }
    for (scene.blobs) |blob| {
        const path = pathFromPoints(blob.points);
        defer path.Delete();
        const item = QGraphicsPathItem.New2(path);
        item.SetBrush(mesh_brush);
        qview.AddItem(item);
    }
}

fn pathFromPoints(points: []const Point) QPainterPath {
    const path = QPainterPath.New();

    if (points.len == 0) return path;

    path.MoveTo2(points[0].x, points[0].y);
    for (points[1..]) |p| {
        path.LineTo2(p.x, p.y);
    }
    path.CloseSubpath();

    return path;
}

fn sceneKeyPressEvent(_: QGraphicsScene, event: QKeyEvent) callconv(.c) void {
    const key = event.Key();
    switch (key) {
        qnamespace_enums.Key.Key_0 => view.Scale(zoom_in_scale, zoom_in_scale),
        qnamespace_enums.Key.Key_9 => view.Scale(zoom_out_scale, zoom_out_scale),
        else => {},
    }
}

fn sceneWheelEvent(_: QGraphicsScene, event: QGraphicsSceneWheelEvent) callconv(.c) void {
    if ((QApplication.QueryKeyboardModifiers() & qnamespace_enums.KeyboardModifier.ShiftModifier) != 0)
        if (event.Delta() > 0)
            view.Scale(zoom_in_scale, zoom_in_scale)
        else
            view.Scale(zoom_out_scale, zoom_out_scale);
}

fn viewResizeEvent(self: QGraphicsView, _: QResizeEvent) callconv(.c) void {
    const rect = qscene.ItemsBoundingRect();
    defer rect.Delete();

    self.FitInView22(rect, qnamespace_enums.AspectRatioMode.KeepAspectRatio);
}
