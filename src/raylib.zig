const std = @import("std");
const ecs = @import("ecs.zig");
const rl = @import("raylib");

pub const Sprite = struct {
    tex: rl.Texture2D,
    color: rl.Color,
};

pub fn register(world: anytype) anyerror!void {
    world.addSystemsToStage(ecs.stages.DRAW, &.{
        draw_sprites,
    });
}

pub fn draw_sprites(alloc: std.mem.Allocator, query: ecs.Query(.{ Sprite, ecs.base.Position }, .{})) anyerror!void {
    var slice = query.slice();
    defer slice.deinit(alloc);

    for (slice.items(.a), slice.items(.b)) |spr, pos| {
        rl.DrawTexture(spr.tex, @floatToInt(c_int, pos.x), @floatToInt(c_int, pos.y), spr.color);
    }
}
