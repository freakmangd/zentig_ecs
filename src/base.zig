const std = @import("std");
const rl = @import("raylib");
const ecs = @import("ecs.zig");

pub const Position = struct {
    x: f32,
    y: f32,
};

pub fn register(world: anytype) anyerror!void {
    world.addComponents(.{Position});

    world.addUpdateSystems(&.{
        update_positions,
    });
}

pub fn update_positions(query: ecs.Query(.{Position}, .{})) anyerror!void {
    for (query.items(.a)) |pos| {
        std.debug.print("{} {}\n", .{ pos.x, pos.y });
    }
}
