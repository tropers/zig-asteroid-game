const std = @import("std");
const rl = @import("raylib");

const game = @import("game.zig");
const pl = @import("player.zig");
const ast = @import("asteroid.zig");

pub fn processPlayerProjectiles(game_state: *game.GameState) !void {
    for (game_state.projectiles.items, 0..) |*projectile, i| {
        if (projectile.life <= 0) {
            _ = game_state.projectiles.orderedRemove(i);
            break;
        }

        projectile.life -= 1;

        projectile.pos = .{
            .x = @mod(projectile.pos.x + projectile.vel.x, @as(
                f32,
                @floatFromInt(rl.getScreenWidth()),
            )),
            .y = @mod(
                projectile.pos.y + projectile.vel.y,
                @as(f32, @floatFromInt(rl.getScreenHeight())),
            ),
        };

        for (game_state.asteroids.items, 0..) |*asteroid, j| {
            if (rl.checkCollisionPointCircle(projectile.pos, asteroid.pos, switch (asteroid.size) {
                .big => ast.ASTEROID_BIG_RADIUS,
                .medium => ast.ASTEROID_MEDIUM_RADIUS,
                .small => ast.ASTEROID_SMALL_RADIUS,
            }) and !asteroid.destroyed) {
                if (asteroid.size == .big) {
                    game_state.sound_player.playSound(game_state.game_sounds.explosion_big);
                } else {
                    game_state.sound_player.playSound(game_state.game_sounds.explosion_small);
                }

                try ast.explodeAsteroid(game_state.allocator, asteroid, &game_state.asteroids, &game_state.particles);
                game_state.asteroids.items[j].destroyed = true;
                projectile.life = 0;

                game.calculateScore(
                    &game_state.score,
                    switch (asteroid.size) {
                        .big => 20.0,
                        .medium => 50.0,
                        .small => 100.0,
                    },
                    &game_state.new_life_score_counter,
                    &game_state.lives,
                    &game_state.sound_player,
                    game_state.game_sounds.new_life,
                );

                break;
            }
        }

        for (game_state.saucers.items, 0..) |saucer, j| {
            if (rl.checkCollisionPointCircle(projectile.pos, saucer.pos, saucer.polygon.scale)) {
                game_state.sound_player.playSound(game_state.game_sounds.explosion_small);
                try game.explosion(game_state.allocator, &game_state.particles, saucer.pos, saucer.vel);
                game.deinitSaucer(game_state.allocator, &game_state.saucers, j);
                projectile.life = 0;
                game.calculateScore(
                    &game_state.score,
                    switch (saucer.type) {
                        .big => 400,
                        .small => 800,
                    },
                    &game_state.new_life_score_counter,
                    &game_state.lives,
                    &game_state.sound_player,
                    game_state.game_sounds.new_life,
                );

                std.debug.print("{s} saucer destroyed!\n", .{switch (saucer.type) {
                    .big => "Big",
                    .small => "Small",
                }});
                break;
            }
        }
    }
}

pub fn processSaucerProjectiles(game_state: *game.GameState) !void {
    if (game_state.saucers.items.len < 1) return;

    for (game_state.saucers.items) |*saucer| {
        for (saucer.projectiles.items) |*projectile| {
            if (projectile.life <= 0) continue;

            projectile.life -= 1;

            projectile.pos = .{
                .x = @mod(projectile.pos.x + projectile.vel.x, @as(f32, @floatFromInt(rl.getScreenWidth()))),
                .y = @mod(projectile.pos.y + projectile.vel.y, @as(f32, @floatFromInt(rl.getScreenHeight()))),
            };

            if (rl.checkCollisionPointCircle(
                projectile.pos,
                game_state.player.pos,
                game_state.player.radius,
            )) {
                projectile.life = 0;
                if (game_state.player.state == .alive)
                    try pl.playerHit(
                        &game_state.player,
                        &game_state.lives,
                        game_state.score,
                        &game_state.particles,
                        switch (saucer.type) {
                            .big => &.{
                                "You were obliterated by a big saucer!",
                                "Big saucer strikes Player.",
                                "KABOOM! You were hit by a projectile of the BIG SAUCER!",
                            },
                            .small => &.{
                                "You were obliterated by a small saucer!",
                                "Small saucer strikes Player.",
                                "KABOOM! You were hit by a projectile of the SMALL SAUCER!",
                                "Small saucers have aimbot installed... To your demise!",
                            },
                        },
                        &game_state.sound_player,
                        game_state.game_sounds,
                    );
            }

            for (game_state.asteroids.items, 0..) |*asteroid, j| {
                if (rl.checkCollisionPointCircle(projectile.pos, asteroid.pos, switch (asteroid.size) {
                    .big => ast.ASTEROID_BIG_RADIUS,
                    .medium => ast.ASTEROID_MEDIUM_RADIUS,
                    .small => ast.ASTEROID_SMALL_RADIUS,
                })) {
                    try ast.explodeAsteroid(
                        game_state.allocator,
                        asteroid,
                        &game_state.asteroids,
                        &game_state.particles,
                    );

                    game_state.asteroids.items[j].destroyed = true;
                    projectile.life = 0;
                    break;
                }
            }
        }
    }
}
