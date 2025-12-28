const std = @import("std");
const rl = @import("raylib");
const rm = rl.math;

pub const Poly2d = struct {
    allocator: std.mem.Allocator,
    points: []const rl.Vector2,
    scale: f32,
    color: rl.Color,
};

pub fn drawPoly2d(center: rl.Vector2, polygon: Poly2d, rotation: f32, line_thickness: f32) !void {
    var points = try std.array_list.Aligned(rl.Vector2, null).initCapacity(std.heap.page_allocator, 64);
    defer points.deinit(polygon.allocator);

    for (polygon.points) |point| try points.append(polygon.allocator, point);

    const transformedPolygon = .{
        .points = points.items[0..],
        .color = polygon.color,
    };

    for (transformedPolygon.points, 0..) |point, i| {
        transformedPolygon.points[i] = rm.vector2Rotate(point, rotation * std.math.pi / 180.0);
    }

    for (transformedPolygon.points, 0..) |point, i| {
        transformedPolygon.points[i] = rm.vector2Scale(point, polygon.scale);
    }

    for (transformedPolygon.points, 0..) |point, i| {
        transformedPolygon.points[i] = rm.vector2Add(point, center);
    }

    for (0..transformedPolygon.points.len - 1) |i| {
        rl.drawLineEx(transformedPolygon.points[i], transformedPolygon.points[i + 1], line_thickness, transformedPolygon.color);
    }
}
