const std = @import("std");
const game = @import("./game.zig");

pub fn main() anyerror!void {
    try game.runGame();
}
