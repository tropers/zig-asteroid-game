const std = @import("std");
const rl = @import("raylib");
const rm = rl.math;
const rand = std.crypto.random;

const poly2d = @import("poly2d.zig");
const pl = @import("player.zig");
const ast = @import("asteroid.zig");
const sauc = @import("saucer.zig");
const proj = @import("projectiles.zig");

// Global game colors
pub const FG_COLOR: rl.Color = .green;
pub const BG_COLOR: rl.Color = .black;
pub const LINE_THICK: f32 = 1.5;

// Saucer values
const BIG_SAUCER_INITIAL_SPAWN_INTERVAL = 2500;
const SMALL_SAUCER_INITIAL_SPAWN_INTERVAL = 5000;
// const BIG_SAUCER_INITIAL_SPAWN_INTERVAL = 0;
// const SMALL_SAUCER_INITIAL_SPAWN_INTERVAL = 0;

const PARTICLE_CLEANUP_INTERVAL = 100;

const SCREEN_WIDTH = 800;
const SCREEN_HEIGHT = 600;

pub const GameSounds = struct {
    player_shooting: rl.Sound,
    player_thrust: rl.Sound,
    explosion_small: rl.Sound,
    explosion_big: rl.Sound,
    saucer_attack: rl.Sound,
    saucer_shoot: rl.Sound,
    new_life: rl.Sound,
    beep_lower: rl.Sound,
    beep_higher: rl.Sound,
};

pub const SoundPlayer = struct {
    muted: bool = false,

    pub fn playSound(self: *SoundPlayer, sound: rl.Sound) void {
        if (!self.muted) {
            rl.playSound(sound);
        }
    }
};

pub const Particle = struct {
    pos: rl.Vector2,
    vel: rl.Vector2,
    life: u32,
};

pub const Projectile = struct {
    pos: rl.Vector2,
    vel: rl.Vector2,
    life: u32,
};

/// GameState contains all relevant variables to the games state
pub const GameState = struct {
    allocator: std.mem.Allocator,
    time_current: f32 = 0.0,
    time_delta: f32 = 0.0,
    player: pl.Player,
    score: u32 = 0,
    lives: u32 = 3,
    level: u32 = 0,
    asteroids: std.array_list.Aligned(ast.Asteroid, null),
    projectiles: std.array_list.Aligned(Projectile, null),
    particles: std.array_list.Aligned(Particle, null),
    saucers: std.array_list.Aligned(sauc.Saucer, null),
    big_saucer_spawn_countdown: u32 = BIG_SAUCER_INITIAL_SPAWN_INTERVAL,
    small_saucer_spawn_countdown: u32 = SMALL_SAUCER_INITIAL_SPAWN_INTERVAL,
    new_life_score_counter: u32 = 0,
    game_sounds: GameSounds,
    sound_player: SoundPlayer,
    last_beep: bool = false,
};

pub fn calculateScore(
    score: *u32,
    increment: u32,
    new_life_score_counter: *u32,
    lives: *u32,
    sound_player: *SoundPlayer,
    new_life_sound: rl.Sound,
) void {
    score.* += increment;
    new_life_score_counter.* += increment;

    if (new_life_score_counter.* >= 10_000) {
        sound_player.playSound(new_life_sound);
        std.debug.print("New life gained!\n", .{});
        lives.* += 1;
        new_life_score_counter.* -= 10_000;
    }
}

fn drawScore(score: u32) !void {
    var buf: [100]u8 = undefined;
    const score_string = try std.fmt.bufPrintZ(
        &buf,
        "SCORE: {}",
        .{score},
    );

    rl.drawText(score_string, @divFloor(rl.getScreenWidth(), 2) - 60, 10, 20, FG_COLOR);
}

fn drawPaused() void {
    const paused = "PAUSED";

    if (@mod(@round(rl.getTime() * 10.0), 2.0) == 0) {
        rl.drawText(
            paused,
            @divFloor(rl.getScreenWidth(), 2) - @as(i32, paused.len) * 6,
            @divFloor(rl.getScreenHeight(), 2),
            20.0,
            FG_COLOR,
        );
    }
}

fn drawProjectile(projectile: Projectile) void {
    if (projectile.life > 0) rl.drawPolyLinesEx(projectile.pos, 4, 2.0, 0.0, LINE_THICK, FG_COLOR);
}

fn drawParticle(particle: Particle) void {
    if (particle.life > 0) rl.drawPolyLinesEx(particle.pos, 4, 2.0, 0.0, LINE_THICK, FG_COLOR);
}

fn drawLives(lives: u32, playerPolygon: poly2d.Poly2d) !void {
    for (0..lives) |i| {
        try poly2d.drawPoly2d(
            .{
                .x = @as(f32, @floatFromInt(rl.getScreenWidth() - 20 * @as(i32, @intCast(i)))) - 15.0,
                .y = 15,
            },
            playerPolygon,
            270.0,
            LINE_THICK,
        );
    }
}

fn drawGame(game_state: *GameState) !void {
    rl.clearBackground(BG_COLOR);
    // rl.drawFPS(0, 0);
    try drawScore(game_state.score);
    try drawLives(game_state.lives, game_state.player.polygon);

    if (game_state.player.blink_timer > 0) {
        try pl.drawPlayerBlinking(game_state.player);
        game_state.player.blink_timer -= 1;
    } else {
        try pl.drawPlayer(game_state.player);
    }

    for (game_state.saucers.items) |saucer| {
        try sauc.drawSaucer(saucer);
        for (saucer.projectiles.items) |projectile| {
            drawProjectile(projectile);
        }
    }

    for (game_state.asteroids.items) |asteroid| {
        try ast.drawAsteroid(asteroid);
    }

    for (game_state.projectiles.items) |projectile| {
        drawProjectile(projectile);
    }

    for (game_state.particles.items) |particle| {
        drawParticle(particle);
    }
}

fn drawGameOver(score: u32) !void {
    rl.clearBackground(BG_COLOR);
    rl.drawFPS(0, 0);

    try drawScore(score);
    const gameOver = "GAME OVER";
    const restart = "Press \"R\" to restart.";
    rl.drawText(
        gameOver,
        @divFloor(rl.getScreenWidth(), 2) - @as(i32, gameOver.len * 6),
        @divFloor(rl.getScreenHeight(), 2),
        20,
        FG_COLOR,
    );
    rl.drawText(
        restart,
        @divFloor(rl.getScreenWidth(), 2) - @as(i32, restart.len * 5),
        @divFloor(rl.getScreenHeight(), 2) + 20,
        20,
        FG_COLOR,
    );
}

fn processParticles(particles: *std.array_list.Aligned(Particle, null)) void {
    for (particles.items) |*particle| {
        if (particle.life > 0) {
            particle.life -= 1;
            particle.pos = rm.vector2Add(particle.pos, particle.vel);
        }
    }
}

pub fn explosion(allocator: std.mem.Allocator, particles: *std.array_list.Aligned(Particle, null), position: rl.Vector2, velocity: ?rl.Vector2) !void {
    var x_vel: f32 = 0.0;
    var y_vel: f32 = 0.0;

    for (0..rand.intRangeAtMost(usize, 5, 12)) |_| {
        if (velocity) |vel| {
            x_vel = 1.5 * vel.x + (-1.0 + rand.float(f32) * 4.0);
            y_vel = 1.5 * vel.y + (-1.0 + rand.float(f32) * 4.0);
        } else {
            x_vel = -1.0 + rand.float(f32) * 4.0;
            y_vel = -1.0 + rand.float(f32) * 4.0;
        }

        try particles.append(allocator, .{
            .life = 100.0,
            .pos = position,
            .vel = .{
                .x = x_vel,
                .y = y_vel,
            },
        });
    }
}

fn processProjectiles(game_state: *GameState) !void {
    try proj.processPlayerProjectiles(game_state);
    try proj.processSaucerProjectiles(game_state);
}

pub fn deinitSaucer(allocator: std.mem.Allocator, saucers: *std.array_list.Aligned(sauc.Saucer, null), saucer_index: usize) void {
    saucers.items[saucer_index].projectiles.deinit(allocator);
    _ = saucers.orderedRemove(saucer_index);
}

fn resetPlayer(player: *pl.Player) void {
    player.allocator = player.allocator;
    player.pos = .{
        .x = @as(f32, @floatFromInt(SCREEN_WIDTH / 2)),
        .y = @as(f32, @floatFromInt(SCREEN_HEIGHT / 2)),
    };
    player.vel = .{
        .x = 0.0,
        .y = 0.0,
    };
    player.polygon = .{
        .allocator = player.allocator,
        .points = &[_]rl.Vector2{
            .{ .x = -1.0, .y = 1.0 },
            .{ .x = 1.0, .y = 0.0 },
            .{ .x = -1.0, .y = -1.0 },
            .{ .x = -0.3, .y = 0.0 },
            .{ .x = -1.0, .y = 1.0 },
        },
        .color = FG_COLOR,
        .scale = 10.0,
    };
    player.rotation = 0.0;
    player.radius = 10.0;
    player.state = .alive;
    player.respawn_timer = 0;
    player.collision_cooldown = 0;
    player.blink_timer = 0;
}

fn restartGame(game_state: *GameState) !void {
    game_state.lives = 3;
    game_state.score = 0;
    game_state.level = 0;
    resetPlayer(&game_state.player);
    game_state.asteroids.clearAndFree(game_state.allocator);
    game_state.projectiles.clearAndFree(game_state.allocator);
    game_state.saucers.clearAndFree(game_state.allocator);
    game_state.particles.clearAndFree(game_state.allocator);
    game_state.big_saucer_spawn_countdown = BIG_SAUCER_INITIAL_SPAWN_INTERVAL;
    game_state.small_saucer_spawn_countdown = SMALL_SAUCER_INITIAL_SPAWN_INTERVAL;
    game_state.player.collision_cooldown = 0;
    game_state.new_life_score_counter = 0;
    game_state.last_beep = false;
    game_state.time_current = 0.0;
    game_state.time_delta = 0.0;

    try ast.generateAsteroids(
        game_state.allocator,
        &game_state.asteroids,
        game_state.level,
    );
}

fn handleLevelUp(game_state: *GameState) !void {
    // If no asteroids and saucers are left, level up!
    if (game_state.asteroids.items.len <= 0 and game_state.saucers.items.len <= 0) {
        try ast.generateAsteroids(game_state.allocator, &game_state.asteroids, game_state.level);

        game_state.player.collision_cooldown = 100;

        calculateScore(
            &game_state.score,
            100,
            &game_state.new_life_score_counter,
            &game_state.lives,
            &game_state.sound_player,
            game_state.game_sounds.new_life,
        );

        game_state.level += 1;
    }
}

fn playBeeps(game_state: *GameState) void {
    const beep_speed = 10.0 - game_state.time_current / 60.0;

    if (!rl.isSoundPlaying(game_state.game_sounds.beep_higher) and !rl.isSoundPlaying(game_state.game_sounds.beep_lower)) {
        if (@mod(@round(rl.getTime() * 10.0), @round(beep_speed)) == 0) {
            if (game_state.last_beep) {
                game_state.sound_player.playSound(game_state.game_sounds.beep_higher);
                game_state.last_beep = false;
            } else {
                game_state.sound_player.playSound(game_state.game_sounds.beep_lower);
                game_state.last_beep = true;
            }
        }
    }
}

fn particleCleanup(particle_cleanup_timer: *u32, game_state: *GameState) void {
    if (particle_cleanup_timer.* <= 0) {
        for (game_state.particles.items, 0..) |particle, i| {
            if (particle.life <= 0) {
                _ = game_state.particles.orderedRemove(i);
            }
        }

        particle_cleanup_timer.* = PARTICLE_CLEANUP_INTERVAL;
    } else {
        particle_cleanup_timer.* -= 1;
    }
}

pub fn runGame() !void {
    rl.setConfigFlags(.{ .window_resizable = true });

    rl.initWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "Asteroids!");
    defer rl.closeWindow(); // Close window and OpenGL context

    rl.setTargetFPS(60);

    rl.initAudioDevice();
    defer rl.closeAudioDevice();

    const allocator = std.heap.page_allocator;

    var game_state = GameState{
        .allocator = allocator,
        .player = .{
            .allocator = allocator,
            .pos = .{
                .x = @as(f32, @floatFromInt(SCREEN_WIDTH / 2)),
                .y = @as(f32, @floatFromInt(SCREEN_HEIGHT / 2)),
            },
            .vel = .{
                .x = 0.0,
                .y = 0.0,
            },
            .polygon = .{
                .allocator = allocator,
                .points = &[_]rl.Vector2{
                    .{ .x = -1.0, .y = 1.0 },
                    .{ .x = 1.0, .y = 0.0 },
                    .{ .x = -1.0, .y = -1.0 },
                    .{ .x = -0.3, .y = 0.0 },
                    .{ .x = -1.0, .y = 1.0 },
                },
                .color = FG_COLOR,
                .scale = 10.0,
            },
            .rotation = 0.0,
            .radius = 10.0,
            .state = .alive,
            .respawn_timer = 0,
            .collision_cooldown = 0,
            .blink_timer = 0,
        },
        .asteroids = try std.array_list.Aligned(ast.Asteroid, null).initCapacity(allocator, 128),
        .projectiles = try std.array_list.Aligned(Projectile, null).initCapacity(allocator, 512),
        .saucers = try std.array_list.Aligned(sauc.Saucer, null).initCapacity(allocator, 16),
        .particles = try std.array_list.Aligned(Particle, null).initCapacity(allocator, 512),
        .game_sounds = .{
            .player_shooting = try rl.loadSound("resources/player_shoot.wav"),
            .player_thrust = try rl.loadSound("resources/thrust.wav"),
            .explosion_small = try rl.loadSound("resources/explosion_small.wav"),
            .explosion_big = try rl.loadSound("resources/explosion_big.wav"),
            .saucer_attack = try rl.loadSound("resources/saucer_attack.wav"),
            .saucer_shoot = try rl.loadSound("resources/saucer_shoot.wav"),
            .new_life = try rl.loadSound("resources/new_life.wav"),
            .beep_higher = try rl.loadSound("resources/beep_higher.wav"),
            .beep_lower = try rl.loadSound("resources/beep_lower.wav"),
        },
        .sound_player = SoundPlayer{},
    };
    defer game_state.asteroids.deinit(allocator);
    defer game_state.projectiles.deinit(allocator);
    defer game_state.saucers.deinit(allocator);
    defer game_state.particles.deinit(allocator);

    // Unload sounds from game_sounds struct
    defer {
        inline for (std.meta.fields(GameSounds)) |field| {
            rl.unloadSound(@field(game_state.game_sounds, field.name));
        }
    }

    try ast.generateAsteroids(
        game_state.allocator,
        &game_state.asteroids,
        game_state.level,
    );

    var game_paused = false;

    var particle_cleanup_timer: u32 = PARTICLE_CLEANUP_INTERVAL;

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        rl.beginDrawing();
        defer rl.endDrawing();

        if (rl.isKeyPressed(.p) and game_state.player.state != .dead) {
            game_paused = !game_paused;
            continue;
        }

        // Mute and unmute game
        if (rl.isKeyPressed(.m)) {
            game_state.sound_player.muted = !game_state.sound_player.muted;
        }

        if (game_paused) {
            try drawGame(&game_state);
            drawPaused();

            if (rl.isKeyPressed(.r)) {
                try restartGame(&game_state);
                game_paused = false;
            }

            continue;
        }

        switch (game_state.player.state) {
            .dead => {
                try drawGameOver(game_state.score);

                // Restart game
                if (rl.isKeyPressed(.r)) try restartGame(&game_state);
            },
            else => {
                try pl.processPlayer(
                    &game_state.player,
                    &game_state.projectiles,
                    &game_state.sound_player,
                    game_state.game_sounds,
                );
                try processProjectiles(&game_state);

                try ast.processAsteroids(allocator, &game_state);

                try sauc.processSaucers(allocator, &game_state);
                processParticles(&game_state.particles);

                try handleLevelUp(&game_state);

                particleCleanup(&particle_cleanup_timer, &game_state);

                try drawGame(&game_state);

                playBeeps(&game_state);
            },
        }

        const time_delta = rl.getFrameTime();
        game_state.time_current += time_delta;
    }
}
