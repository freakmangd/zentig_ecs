const std = @import("std");
const testing = std.testing;
const ztg = @import("init.zig");
const WorldBuilder = @import("worldbuilder.zig");

test "ztg.World" {
    var world = try game_file.MyWorld.init(testing.allocator);
    defer world.deinit();

    try world.runStageList(&.{ .init, .update });
}

const game_file = struct {
    const MyWorld = WorldBuilder.new(.{
        ztg.base,
        game_file,
    }).Build();

    pub fn include(comptime world: *WorldBuilder) void {
        world.addComponents(.{Sprite});
        world.include(.{player_file});
    }

    pub const Sprite = struct {
        img: usize,
    };
};

const player_file = struct {
    pub fn include(comptime world: *WorldBuilder) void {
        world.addComponents(.{Player});
        world.addSystemsToStage(.init, .{playerSpawn});
        world.addUpdateSystems(.{playerSpeach});
        world.addStage(.player_update);
        world.addSystemsToStage(.player_update, .{playerSpecial});
    }

    pub const Player = struct {
        name: []const u8,
    };

    pub const PlayerBundle = struct {
        p: Player,
        tran: ztg.base.Transform,
        sprite: game_file.Sprite,
    };

    fn playerSpawn(com: ztg.Commands) !void {
        const player_ent = try com.newEnt();
        try com.giveEntMany(player_ent, player_file.PlayerBundle{
            .p = .{ .name = "Player" },
            .tran = .{ .pos = ztg.Vec3.new(10, 10, 0) },
            .sprite = .{ .img = 0 },
        });
    }

    fn playerSpeach(com: ztg.Commands, q: ztg.Query(&.{ Player, ztg.base.Transform })) !void {
        for (q.items(.a), q.items(.b)) |player, trn| {
            try std.testing.expectFmt("My name is Player, and I'm located at 10 10.", "My name is {s}, and I'm located at {} {}.", .{
                player.name,
                @floatToInt(i32, trn.pos.x),
                @floatToInt(i32, trn.pos.y),
            });
        }

        try com.runStage(.player_update);
    }

    fn playerSpecial(q: ztg.Query(&.{ Player, game_file.Sprite })) !void {
        for (q.items(.b)) |spr| {
            try std.testing.expectEqual(@as(usize, 0), spr.img);
        }
    }
};
