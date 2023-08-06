const std = @import("std");
const ztg = @import("zentig");
const testing = std.testing;

test "ztg.World" {
    var world = try game_file.MyWorld.init(std.testing.allocator);
    defer world.deinit();

    try world.runStageList(&.{ .init, .update });
}

const game_file = struct {
    const MyWorld = ztg.WorldBuilder.init(&.{
        ztg.base,
        @This(),
    }).Build();

    pub fn include(comptime world: *ztg.WorldBuilder) void {
        world.addComponents(&.{Sprite});
        world.include(&.{player_file});
    }

    pub const Sprite = struct {
        img: usize,
    };
};

const player_file = struct {
    pub fn include(comptime world: *ztg.WorldBuilder) void {
        world.addComponents(&.{ Player, Jetpack, Backpack });
        world.addSystems(.{
            .load = .{playerSpawn},
            .update = .{ playerSpeach, playerSpecial },
        });
    }

    pub const Player = struct {
        name: []const u8,
    };

    pub const PlayerBundle = struct {
        Player,
        ztg.base.Transform,
        game_file.Sprite,
    };

    pub const Jetpack = struct {
        thrust: i32,
    };

    pub const Backpack = struct {
        space: u32,
    };

    fn playerSpawn(com: ztg.Commands) !void {
        // "GiveMany" functions can be called with either a struct that defines
        // all the types. (PlayerBundle)
        const plr = try com.newEntWithMany(PlayerBundle{
            .{ .name = "Player" },
            ztg.base.Transform.initWith(.{ .pos = ztg.vec3(10, 10, 0) }),
            .{ .img = 0 },
        });

        // Or an anonymous tuple.
        try plr.giveEntMany(.{
            Jetpack{ .thrust = 100 },
            Backpack{ .space = 20 },
        });

        // this could be also written as:
        // try com.giveEntMany(plr.ent, .{ ... });
    }

    fn playerSpeach(q: ztg.Query(.{ Player, ztg.base.Transform })) !void {
        for (q.items(0), q.items(1)) |player, trn| {
            try std.testing.expectEqualStrings("Player", player.name);
            try std.testing.expect(trn.getPos().equals(.{ .x = 10, .y = 10 }));
        }
    }

    fn playerSpecial(q: ztg.QueryOpts(.{game_file.Sprite}, .{ztg.With(Player)})) !void {
        for (q.items(0)) |spr| {
            try std.testing.expectEqual(@as(usize, 0), spr.img);
        }
    }
};
