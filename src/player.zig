const std = @import("std");
const rand = std.crypto.random;
const math = std.math;

const rl = @import("raylib");
const rm = rl.math;
const main = @import("main.zig");
const game = @import("game.zig");
const poly2d = @import("poly2d.zig");

const PlayerState = enum {
    alive,
    respawning,
    dead,
};

pub const Player = struct {
    allocator: std.mem.Allocator,
    pos: rl.Vector2,
    vel: rl.Vector2,
    polygon: poly2d.Poly2d,
    rotation: f32,
    radius: f32,
    state: PlayerState,
    respawn_timer: u32,
    blink_timer: u32,
    collision_cooldown: u32,
};

fn drawFlame(player: Player) void {
    // TODO: Magic numbers
    const flame_pos = rl.Vector2{
        .x = player.pos.x - (@cos(player.rotation * math.pi / 180.0) * 8.0),
        .y = player.pos.y - (@sin(player.rotation * math.pi / 180.0) * 8.0),
    };

    if (rand.boolean())
        rl.drawPolyLinesEx(flame_pos, 4, 7.0, player.rotation - 180.0, game.LINE_THICK, game.FG_COLOR);
}

pub fn drawPlayerBlinking(player: Player) !void {
    switch (player.state) {
        .alive => {
            if (@mod(@round(rl.getTime() * 20.0), 2.0) == 0) {
                try poly2d.drawPoly2d(player.pos, player.polygon, player.rotation, game.LINE_THICK);
            }

            if (rl.isKeyDown(.up)) {
                drawFlame(player);
            }

            // Draw halo around player when collision cooldown is active
            if (player.collision_cooldown > 0) {
                rl.drawPolyLinesEx(
                    player.pos,
                    12,
                    player.radius * 3 + @sin(@as(f32, @floatCast(rl.getTime())) * 20.0),
                    0.0,
                    game.LINE_THICK,
                    game.FG_COLOR,
                );
            }
        },
        else => {},
    }
}

pub fn drawPlayer(player: Player) !void {
    switch (player.state) {
        .alive => {
            try poly2d.drawPoly2d(player.pos, player.polygon, player.rotation, game.LINE_THICK);

            if (rl.isKeyDown(.up)) {
                drawFlame(player);
            }

            // Draw halo around player when collision cooldown is active
            if (player.collision_cooldown > 0) {
                rl.drawPolyLinesEx(
                    player.pos,
                    12,
                    player.radius * 3 + @sin(@as(f32, @floatCast(rl.getTime())) * 20.0),
                    0.0,
                    game.LINE_THICK,
                    game.FG_COLOR,
                );
            }
        },
        else => {},
    }
}

fn printRandomMessage(messages: []const [:0]const u8) void {
    std.debug.print("{s}\n", .{
        messages[rand.intRangeAtMost(usize, 0, messages.len - 1)],
    });
}

pub fn playerHit(
    player: *Player,
    lives: *u32,
    score: u32,
    particles: *std.array_list.Aligned(game.Particle, null),
    hit_messages: ?[]const [:0]const u8,
    sound_player: *game.SoundPlayer,
    game_sounds: game.GameSounds,
) !void {
    switch (player.state) {
        .alive => {
            sound_player.playSound(game_sounds.explosion_small);

            if (player.collision_cooldown <= 0) {
                try game.explosion(player.allocator, particles, player.pos, player.vel);
                lives.* -= 1;

                if (hit_messages) |msg| printRandomMessage(msg);

                if (lives.* <= 0) {
                    player.state = .dead;
                    std.debug.print("GAME OVER!\nScore: {}\n", .{score});
                } else {
                    player.state = .respawning;
                }

                player.pos = .{
                    .x = @as(f32, @floatFromInt(rl.getScreenWidth())) / 2.0,
                    .y = @as(f32, @floatFromInt(rl.getScreenHeight())) / 2.0,
                };
                player.vel = .{ .x = 0.0, .y = 0.0 };
                player.rotation = 0.0;

                player.respawn_timer = 250;
            }
        },
        else => {},
    }
}

fn playerShoot(player: *Player, projectiles: *std.array_list.Aligned(game.Projectile, null)) !void {
    try projectiles.append(player.allocator, .{
        .pos = player.pos,
        .vel = .{
            // TODO: Magic numbers
            .x = player.vel.x + @cos(player.rotation * math.pi / 180.0) * 8.0,
            .y = player.vel.y + @sin(player.rotation * math.pi / 180.0) * 8.0,
        },
        .life = 50,
    });
}

pub fn processPlayer(
    player: *Player,
    projectiles: *std.array_list.Aligned(game.Projectile, null),
    sound_player: *game.SoundPlayer,
    game_sounds: game.GameSounds,
) !void {
    if (player.collision_cooldown > 0) player.collision_cooldown -= 1;

    switch (player.state) {
        .alive => {
            // Accelerate
            if (rl.isKeyDown(.up)) {
                if (!rl.isSoundPlaying(game_sounds.player_thrust))
                    sound_player.playSound(game_sounds.player_thrust);

                player.vel = .{
                    .x = player.vel.x + @cos(player.rotation * math.pi / 180.0) / 10.0,
                    .y = player.vel.y + @sin(player.rotation * math.pi / 180.0) / 10.0,
                };
            }

            if (rl.isKeyDown(.left)) {
                player.rotation -= 4;
            } else if (rl.isKeyDown(.right)) {
                player.rotation += 4;
            }

            if (rl.isKeyPressed(.space) or rl.isKeyPressed(.x)) {
                sound_player.playSound(game_sounds.player_shooting);
                try playerShoot(player, projectiles);
            }

            const drag = 0.005;
            player.vel = rm.vector2Multiply(player.vel, .{
                .x = 1.0 - drag,
                .y = 1.0 - drag,
            });

            player.pos = .{
                .x = @mod(player.pos.x + player.vel.x, @as(f32, @floatFromInt(rl.getScreenWidth()))),
                .y = @mod(player.pos.y + player.vel.y, @as(f32, @floatFromInt(rl.getScreenHeight()))),
            };
        },
        .respawning => {
            player.respawn_timer -= 1;

            if (player.respawn_timer <= 0) {
                player.collision_cooldown = 50;
                player.state = .alive;
                player.blink_timer = 100;
            }
        },
        else => {},
    }
}
