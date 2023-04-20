const std = @import("std");
const ztg = @import("zentig");

// This would most likely be a player.zig file instead
const player = struct {
    // This is called when passed into a .include() call on a WorldBuilder
    pub fn include(comptime wb: *ztg.WorldBuilder) !void {
        // All components used in the world must be added before .Build() is called on the WorldBuilder
        wb.addComponents(.{Player});
        // Adds a system to the UPDATE stage of the world, systems can only be added during comptime
        wb.addUpdateSystems(.{player_speak});
    }

    // A basic component
    pub const Player = struct {
        name: []const u8,
    };

    // A "Bundle" is just a name for a predetermined list of Components,
    // it's really just so you dont forget to add something when making entities
    pub const PlayerBundle = struct {
        Player,
        ztg.base.Transform,
    };

    // A basic system
    pub fn player_speak(query: ztg.Query(.{ Player, ztg.base.Transform }, .{})) !void {
        // Query is a wrapper for MultiArrayList, where all the types you passed into the
        // original tuple get indexed as "a" through "z".
        for (query.items(.a), query.items(.b)) |plr, trn| {
            std.debug.print("My name is {s}, and I'm located at {} {}.\n", .{ plr.name, trn.pos.x, trn.pos.y });
        }
    }
};

// Constructing the world must be done at comptime
const MyWorld = blk: {
    var wb = ztg.WorldBuilder.new();
    wb.include(.{
        ztg.base.Init(.{}),
        player,
    });
    break :blk wb.Build();
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    var world = try MyWorld.init(alloc);
    defer world.deinit();

    // Create a new entity for the player
    const player_ent = try world.newEnt();

    // Use the PlayerBundle struct as a blueprint
    try world.giveEntBundle(player_ent, player.PlayerBundle, .{
        .{ .name = "Player" },
        .{ .pos = ztg.Vec3.new(10, 10, 10) },
    });

    // runs all the functions added to the UPDATE stage
    try world.runStage("UPDATE");
}
