const std = @import("std");
const rl = @import("raylib");
const rand = std.crypto.random;
const math = std.math;

const poly2d = @import("poly2d.zig");
const game = @import("game.zig");
const pl = @import("player.zig");
const sauc = @import("saucer.zig");

pub const ASTEROID_BIG_RADIUS = 50.0;
pub const ASTEROID_MEDIUM_RADIUS = 20.0;
pub const ASTEROID_SMALL_RADIUS = 10.0;

const AsteroidSize = enum { small, medium, big };

pub const Asteroid = struct {
    pos: rl.Vector2,
    vel: rl.Vector2,
    polygon: poly2d.Poly2d,
    size: AsteroidSize,
    rotation: f32,
    rotational_vel: f32,
    destroyed: bool,
};

pub fn drawAsteroid(asteroid: Asteroid) !void {
    if (!asteroid.destroyed) try poly2d.drawPoly2d(asteroid.pos, asteroid.polygon, asteroid.rotation, game.LINE_THICK);
}

/// Generates a random polygon for an asteroid by
/// going clockwise in a cirlce and adding points accordingly.
/// Using RNG, variation is added to every point to make the shape
/// of the asteroid look more realistic.
fn generateAsteroidPolygon(allocator: std.mem.Allocator, radius: f32) !poly2d.Poly2d {
    const point_count: u32 = 12;
    var asteroid_points = try std.array_list.Aligned(rl.Vector2, null).initCapacity(allocator, point_count);
    const deg_per_point: u32 = 360 / point_count;

    for (0..point_count) |i| {
        // Add variation to every point
        var point_random = rand.float(f32) + 0.4;
        if (point_random > 1.1) point_random = 1.1;

        try asteroid_points.append(allocator, .{
            .x = @cos(@as(f32, @floatFromInt(i * deg_per_point)) * math.pi / 180.0) * point_random,
            .y = @sin(@as(f32, @floatFromInt(i * deg_per_point)) * math.pi / 180.0) * point_random,
        });
    }

    // Connect last point with first point of the polygon
    try asteroid_points.append(allocator, .{
        .x = asteroid_points.items[0].x,
        .y = asteroid_points.items[0].y,
    });

    return .{
        .allocator = allocator,
        .points = asteroid_points.items[0..],
        .scale = radius,
        .color = game.FG_COLOR,
    };
}

pub fn generateAsteroids(
    allocator: std.mem.Allocator,
    asteroids: *std.array_list.Aligned(Asteroid, null),
    level: u32,
) !void {
    const asteroids_amount = switch (level) {
        0...4 => rand.intRangeAtMost(usize, 2, 4),
        5...9 => rand.intRangeAtMost(usize, 5, 8),
        else => rand.intRangeAtMost(usize, 7, 12),
    };

    for (0..asteroids_amount) |_| {
        const sides_enum = enum {
            north,
            east,
            south,
            west,
        };

        const side = rand.enumValue(sides_enum);
        var asteroid_pos = rl.Vector2.zero();

        switch (side) {
            .north => {
                asteroid_pos = rl.Vector2{
                    .x = rand.float(f32) * @as(f32, @floatFromInt(rl.getScreenWidth())),
                    .y = 0.0,
                };
            },
            .east => {
                asteroid_pos = rl.Vector2{
                    .x = @as(f32, @floatFromInt(rl.getScreenWidth())),
                    .y = rand.float(f32) * @as(f32, @floatFromInt(rl.getScreenHeight())),
                };
            },
            .south => {
                asteroid_pos = rl.Vector2{
                    .x = rand.float(f32) * @as(f32, @floatFromInt(rl.getScreenWidth())),
                    .y = @as(f32, @floatFromInt(rl.getScreenHeight())),
                };
            },
            .west => {
                asteroid_pos = rl.Vector2{
                    .x = 0.0,
                    .y = rand.float(f32) * @as(f32, @floatFromInt(rl.getScreenHeight())),
                };
            },
        }

        try asteroids.append(allocator, .{
            .pos = asteroid_pos,
            .vel = .{
                .x = (-1.0 + rand.float(f32) * 7) / 2,
                .y = (-1.0 + rand.float(f32) * 7) / 2,
            },
            .rotation = 0.0,
            .size = .big,
            .polygon = try generateAsteroidPolygon(allocator, ASTEROID_BIG_RADIUS),
            .rotational_vel = rand.float(f32),
            .destroyed = false,
        });
    }
}

fn processAsteroid(
    allocator: std.mem.Allocator,
    game_state: *game.GameState,
    asteroid: *Asteroid,
    asteroid_index: usize,
) !void {
    if (asteroid.destroyed) return;

    asteroid.pos = .{
        .x = @mod(asteroid.pos.x + asteroid.vel.x, @as(f32, @floatFromInt(rl.getScreenWidth()))),
        .y = @mod(asteroid.pos.y + asteroid.vel.y, @as(f32, @floatFromInt(rl.getScreenHeight()))),
    };

    asteroid.rotation += asteroid.rotational_vel;

    if (rl.checkCollisionCircles(game_state.player.pos, game_state.player.radius, asteroid.pos, switch (asteroid.size) {
        .big => ASTEROID_BIG_RADIUS,
        .medium => ASTEROID_MEDIUM_RADIUS,
        .small => ASTEROID_SMALL_RADIUS,
    })) {
        if (game_state.player.state == .alive) {
            try pl.playerHit(
                &game_state.player,
                &game_state.lives,
                game_state.score,
                &game_state.particles,
                &.{
                    "You came a bit too close to that space junk!",
                    "You hit an asteroid!",
                    "You aren't supposed to fly into those rocks...",
                    "Really now? How did you not see that one coming?",
                },
                &game_state.sound_player,
                game_state.game_sounds,
            );

            try explodeAsteroid(
                allocator,
                asteroid,
                &game_state.asteroids,
                &game_state.particles,
            );

            game_state.asteroids.items[asteroid_index].destroyed = true;
        }
    }

    for (game_state.saucers.items, 0..) |saucer, i| {
        if (rl.checkCollisionCircles(saucer.pos, saucer.polygon.scale, asteroid.pos, switch (asteroid.size) {
            .big => ASTEROID_BIG_RADIUS,
            .medium => ASTEROID_MEDIUM_RADIUS,
            .small => ASTEROID_SMALL_RADIUS,
        })) {
            game_state.sound_player.playSound(game_state.game_sounds.explosion_small);
            try game.explosion(allocator, &game_state.particles, saucer.pos, saucer.vel);
            try explodeAsteroid(
                allocator,
                asteroid,
                &game_state.asteroids,
                &game_state.particles,
            );

            game_state.asteroids.items[asteroid_index].destroyed = true;

            game.deinitSaucer(allocator, &game_state.saucers, i);
            std.debug.print("{s} saucer destroyed by asteroid!\n", .{switch (saucer.type) {
                .big => "Big",
                .small => "Small",
            }});
            break;
        }
    }
}

pub fn processAsteroids(
    allocator: std.mem.Allocator,
    game_state: *game.GameState,
) !void {
    for (game_state.asteroids.items, 0..) |*asteroid, i| {
        if (asteroid.destroyed) {
            _ = game_state.asteroids.orderedRemove(i);
            break;
        }

        try processAsteroid(
            allocator,
            game_state,
            asteroid,
            i,
        );
    }
}

pub fn explodeAsteroid(
    allocator: std.mem.Allocator,
    asteroid: *Asteroid,
    asteroids: *std.array_list.Aligned(Asteroid, null),
    particles: *std.array_list.Aligned(game.Particle, null),
) !void {
    try game.explosion(allocator, particles, asteroid.pos, asteroid.vel);
    if (asteroid.size == .small) return;

    for (0..rand.intRangeAtMost(usize, 2, 3)) |_| {
        try asteroids.append(allocator, .{
            .pos = asteroid.pos,
            .vel = .{
                .x = asteroid.vel.x + (-1.0 + rand.float(f32) * 2.0),
                .y = asteroid.vel.y + (-1.0 + rand.float(f32) * 2.0),
            },
            .rotation = 0.0,
            .size = switch (asteroid.size) {
                .big => .medium,
                .medium => .small,
                else => .small,
            },
            .polygon = try generateAsteroidPolygon(allocator, switch (asteroid.size) {
                .big => ASTEROID_MEDIUM_RADIUS,
                .medium => ASTEROID_SMALL_RADIUS,
                .small => ASTEROID_SMALL_RADIUS,
            }),
            .rotational_vel = rand.float(f32),
            .destroyed = false,
        });
    }
}
