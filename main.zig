const std = @import("std");
const ztg = @import("zentig");

// This would most likely be a player.zig file instead
const player = struct {
    pub fn register(comptime world: *ztg.WorldBuilder) anyerror!void {
        // All components used in the world must be added before `.Build()` is called on the WorldBuilder
        world.addComponents(.{Player});
        // Adds a system to the `.update` stage of the world, systems can only be added during comptime
        world.addUpdateSystems(.{playerSpeak});
        // Player relies on ztg.base.Transform, we can include it here without worrying about including it twice
        world.include(.{ztg.base});
    }

    pub const Player = struct {
        name: []const u8,
    };

    pub const PlayerBundle = struct {
        p: Player,
        tran: ztg.base.Transform,
    };

    pub fn playerSpeak(query: ztg.Query(.{ Player, ztg.base.Transform }, .{})) !void {
        // Query is a wrapper for MultiArrayList, where all the types you passed into the
        // original tuple get indexed as "a" through "z".
        for (query.items(.a), query.items(.b)) |plr, trn| {
            std.debug.print("My name is {s}, and I'm located at {} {}.", .{ plr.name, trn.pos.x, trn.pos.y });
        }
    }
};

pub fn main() !void {
    const MyWorld = ztg.WorldBuilder.init(.{
        ztg.base,
        player,
    }).Build();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    var world = try MyWorld.init(alloc);
    defer world.deinit();

    const player_ent = try world.newEnt();
    try world.giveEntMany(player_ent, player.PlayerBundle{
        .p = .{ .name = "Player" },
        .tran = .{ .pos = ztg.Vec3.init(10, 10, 10) }, // rot defaults to 0 and scale defaults to ztg.Vec3.init(1, 1, 1)
    });

    try world.runStage(.update);
}
