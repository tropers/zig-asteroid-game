const std = @import("std");
const rl = @import("raylib");
const rm = rl.math;
const rand = std.crypto.random;
const math = std.math;

const game = @import("game.zig");
const pl = @import("player.zig");
const ast = @import("asteroid.zig");

const poly2d = @import("poly2d.zig");

const SaucerType = enum {
    big,
    small,
};

const FlyingDirection = enum {
    up,
    ahead,
    down,
};

const saucer_dir_change_time = .{
    .big = 200,
    .small = 100,
};

pub const Saucer = struct {
    type: SaucerType,
    pos: rl.Vector2,
    vel: rl.Vector2,
    polygon: poly2d.Poly2d,
    projectiles: std.array_list.Aligned(game.Projectile, null),
    shoot_cooldown: u32,
    dir_change_countdown: u32,
    current_direction: FlyingDirection,
    destroyed: bool,
};

pub fn drawSaucer(saucer: Saucer) !void {
    if (!saucer.destroyed) try poly2d.drawPoly2d(saucer.pos, saucer.polygon, 270.0, game.LINE_THICK);
}

fn saucerShoot(allocator: std.mem.Allocator, game_state: *game.GameState) !void {
    for (game_state.saucers.items) |*saucer| {
        var saucer_projectiles = &saucer.projectiles;

        if (saucer.shoot_cooldown <= 0) {
            const aim_angle = -1.0 + rand.float(f32) * 2.0 * math.pi;

            switch (saucer.type) {
                .big => {
                    try saucer_projectiles.append(allocator, .{
                        .pos = saucer.pos,
                        .vel = .{
                            .x = saucer.vel.x + @cos(aim_angle) * 2.0,
                            .y = saucer.vel.y + @sin(aim_angle) * 2.0,
                        },
                        .life = 150,
                    });

                    saucer.shoot_cooldown = 100;
                    game_state.sound_player.playSound(game_state.game_sounds.saucer_shoot);
                },
                .small => {
                    if (game_state.player.state != .alive) continue;

                    const aim_vector = rm.vector2Multiply(
                        rm.vector2Normalize(rm.vector2Subtract(game_state.player.pos, saucer.pos)),
                        .{ .x = 2.0, .y = 2.0 },
                    );

                    // Scale aim accuracy of small saucer with level
                    const aim_accuracy: f32 = switch (game_state.level) {
                        0...4 => 0.6,
                        5...9 => 0.2,
                        else => 0,
                    };

                    const vel: rl.Vector2 = if (rand.float(f32) >= aim_accuracy) .{
                        .x = aim_vector.x,
                        .y = aim_vector.y,
                    } else .{
                        .x = saucer.vel.x + @cos(aim_angle) * 2.0,
                        .y = saucer.vel.y + @sin(aim_angle) * 2.0,
                    };

                    try saucer_projectiles.append(allocator, .{
                        .pos = saucer.pos,
                        .vel = vel,
                        .life = 200,
                    });

                    saucer.shoot_cooldown = 100;
                    game_state.sound_player.playSound(game_state.game_sounds.saucer_shoot);
                },
            }
        } else {
            saucer.shoot_cooldown -= 1;
        }
    }
}

fn getBigSaucer(allocator: std.mem.Allocator, right_left: bool) !Saucer {
    return .{
        .type = .big,
        .pos = .{
            .x = if (right_left) @as(f32, @floatFromInt(rl.getScreenWidth())) else 0.0,
            .y = @as(f32, @floatFromInt(rand.intRangeAtMost(
                i32,
                @divFloor(rl.getScreenHeight(), 4),
                rl.getScreenHeight() - @divFloor(rl.getScreenHeight(), 4),
            ))),
        },
        .vel = .{
            .y = 0.0,
            .x = if (right_left) -2 else 2,
        },
        .polygon = .{
            .allocator = allocator,
            .points = &[_]rl.Vector2{
                .{ .x = 0.0, .y = -1.0 },
                .{ .x = -0.4, .y = -0.4 },
                .{ .x = -0.4, .y = 0.4 },
                .{ .x = 0.0, .y = 1.0 },
                .{ .x = 0.0, .y = -1.0 },
                .{ .x = 0.0, .y = 1.0 },
                .{ .x = 0.4, .y = 0.3 },
                .{ .x = 0.7, .y = 0.2 },
                .{ .x = 0.7, .y = -0.2 },
                .{ .x = 0.4, .y = -0.3 },
                .{ .x = 0.4, .y = 0.3 },
                .{ .x = 0.4, .y = -0.3 },
                .{ .x = 0.0, .y = -1.0 },
            },
            .color = game.FG_COLOR,
            .scale = 25.0,
        },
        .projectiles = try std.array_list.Aligned(game.Projectile, null).initCapacity(allocator, 32),
        .shoot_cooldown = 0,
        .dir_change_countdown = saucer_dir_change_time.big,
        .current_direction = .ahead,
        .destroyed = false,
    };
}

fn spawnBigSaucer(
    allocator: std.mem.Allocator,
    saucers: *std.array_list.Aligned(Saucer, null),
    big_saucer_spawn_countdown: *u32,
    level: u32,
) !void {
    // Spawn flying saucer on the left side or on the right side
    // right = true
    // left = false
    const right_left = rand.boolean();

    std.debug.print("Oh no! Here comes the big saucer!\n", .{});

    try saucers.append(allocator, try getBigSaucer(allocator, right_left));

    big_saucer_spawn_countdown.* = switch (level) {
        0...4 => 2500,
        5...9 => 500,
        else => 250,
    };
}

fn getSmallSaucer(allocator: std.mem.Allocator, right_left: bool) !Saucer {
    return .{
        .type = .small,
        .pos = .{
            .x = if (right_left) @as(f32, @floatFromInt(rl.getScreenWidth())) else 0.0,
            .y = @as(f32, @floatFromInt(rand.intRangeAtMost(
                i32,
                @divFloor(rl.getScreenHeight(), 4),
                rl.getScreenHeight() - @divFloor(rl.getScreenHeight(), 4),
            ))),
        },
        .vel = .{
            .y = 0.0,
            .x = if (right_left) -2 else 2,
        },
        .polygon = .{
            .allocator = allocator,
            .points = &[_]rl.Vector2{
                .{ .x = 0.0, .y = -1.0 },
                .{ .x = -0.4, .y = -0.4 },
                .{ .x = -0.4, .y = 0.4 },
                .{ .x = 0.0, .y = 1.0 },
                .{ .x = 0.0, .y = -1.0 },
                .{ .x = 0.0, .y = 1.0 },
                .{ .x = 0.4, .y = 0.3 },
                .{ .x = 0.7, .y = 0.2 },
                .{ .x = 0.7, .y = -0.2 },
                .{ .x = 0.4, .y = -0.3 },
                .{ .x = 0.4, .y = 0.3 },
                .{ .x = 0.4, .y = -0.3 },
                .{ .x = 0.0, .y = -1.0 },
            },
            .color = game.FG_COLOR,
            .scale = 15.0,
        },
        .projectiles = try std.array_list.Aligned(game.Projectile, null).initCapacity(allocator, 32),
        .shoot_cooldown = 0,
        .dir_change_countdown = saucer_dir_change_time.small,
        .current_direction = .ahead,
        .destroyed = false,
    };
}

fn spawnSmallSaucer(
    allocator: std.mem.Allocator,
    saucers: *std.array_list.Aligned(Saucer, null),
    small_saucer_spawn_countdown: *u32,
    level: u32,
) !void {
    // Spawn flying saucer on the left side or on the right side
    // right = true
    // left = false
    const right_left = rand.boolean();

    std.debug.print("Oh no! Here comes the small saucer! It uses aimbot!\n", .{});

    try saucers.append(allocator, try getSmallSaucer(allocator, right_left));

    small_saucer_spawn_countdown.* = switch (level) {
        0...4 => 5000,
        5...9 => 1500,
        else => 200,
    };
}

pub fn processSaucers(
    allocator: std.mem.Allocator,
    game_state: *game.GameState,
) !void {
    if (game_state.big_saucer_spawn_countdown <= 0) {
        try spawnBigSaucer(
            allocator,
            &game_state.saucers,
            &game_state.big_saucer_spawn_countdown,
            game_state.level,
        );
    }

    if (game_state.small_saucer_spawn_countdown <= 0) {
        try spawnSmallSaucer(
            allocator,
            &game_state.saucers,
            &game_state.small_saucer_spawn_countdown,
            game_state.level,
        );
    }

    for (game_state.saucers.items, 0..) |*saucer, i| {
        if (saucer.destroyed) {
            game_state.saucers.items[i].projectiles.deinit(allocator);
            _ = game_state.saucers.orderedRemove(i);
            break;
        }

        saucer.pos = rm.vector2Add(saucer.pos, saucer.vel);
        saucer.pos.y = @mod(saucer.pos.y, @as(f32, @floatFromInt(rl.getScreenHeight())));

        saucer.dir_change_countdown -= 1;

        if (saucer.dir_change_countdown <= 0) {
            saucer.dir_change_countdown = switch (saucer.type) {
                .big => saucer_dir_change_time.big,
                .small => saucer_dir_change_time.small,
            };

            // Always change direction between straight ahead and then up / down
            if (saucer.current_direction != .ahead) {
                saucer.current_direction = .ahead;
                saucer.vel.y = 0.0;
            } else {
                const new_direction = rand.boolean();

                saucer.vel.y = switch (new_direction) {
                    true => -1.0,
                    false => 1.0,
                };

                saucer.current_direction = switch (new_direction) {
                    true => .up,
                    false => .down,
                };
            }
        }

        try saucerShoot(allocator, game_state);

        if (rl.checkCollisionCircles(game_state.player.pos, game_state.player.radius, saucer.pos, saucer.polygon.scale)) {
            if (game_state.player.state == .alive)
                try pl.playerHit(
                    &game_state.player,
                    &game_state.lives,
                    game_state.score,
                    &game_state.particles,
                    &.{
                        "You came too close to the flying saucer.",
                        "Player decides to ram the flying saucer. Flying saucer wins...",
                        "You manage to get a quick glimpse of the aliens in" ++
                            " the flying saucer before you inevitably crash.",
                    },
                    &game_state.sound_player,
                    game_state.game_sounds,
                );
        }

        if (saucer.pos.x < 0.0 or saucer.pos.x > @as(f32, @floatFromInt(rl.getScreenWidth()))) {
            game.deinitSaucer(allocator, &game_state.saucers, i);
            break;
        }
    }

    // TODO: Fix sound clipping in continuous play
    if (game_state.saucers.items.len > 0 and !rl.isSoundPlaying(game_state.game_sounds.saucer_attack)) {
        game_state.sound_player.playSound(game_state.game_sounds.saucer_attack);
    }

    // TODO: Determine when to countdown for saucers
    game_state.big_saucer_spawn_countdown -= 1;
    game_state.small_saucer_spawn_countdown -= 1;
}
