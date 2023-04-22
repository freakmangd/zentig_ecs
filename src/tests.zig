const std = @import("std");
const testing = std.testing;
const ztg = @import("ecs.zig");

test "ztg.World" {
    var world = try game_file.MyWorld.init(testing.allocator);
    defer world.deinit();

    const player_ent = try world.newEnt();
    try world.giveEntBundle(player_ent, player_file.PlayerBundle, .{
        .p = .{ .name = "Player" },
        .tran = .{ .pos = ztg.Vec3.new(10, 10, 0) },
        .sprite = .{ .img = 0 },
    });

    try world.runStage("UPDATE");
}

const game_file = struct {
    const MyWorld = blk: {
        var wb = ztg.WorldBuilder.new();
        wb.include(.{
            ztg.base,
            game_file,
        });
        break :blk wb.Build();
    };

    pub fn include(comptime world: *ztg.WorldBuilder) anyerror!void {
        world.addComponents(.{Sprite});
        world.include(.{player_file});
    }

    pub const Sprite = struct {
        img: usize,
    };
};

const player_file = struct {
    pub fn include(comptime world: *ztg.WorldBuilder) anyerror!void {
        world.addComponents(.{Player});
        world.addUpdateSystems(.{player_speach});
    }

    pub const Player = struct {
        name: []const u8,
    };

    pub const PlayerBundle = struct {
        p: Player,
        tran: ztg.base.Transform,
        sprite: game_file.Sprite,
    };

    fn player_speach(q: ztg.Query(.{ Player, ztg.base.Transform }, .{})) anyerror!void {
        for (q.items(.a), q.items(.b)) |player, trn| {
            try std.testing.expectFmt("My name is Player, and I'm located at 10 10.", "My name is {s}, and I'm located at {} {}.", .{
                player.name,
                @floatToInt(i32, trn.pos.x),
                @floatToInt(i32, trn.pos.y),
            });
        }
    }
};
