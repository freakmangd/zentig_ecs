const std = @import("std");
const ztg = @import("zentig");

// Constructing the world must be done at comptime
// `.new(anytype)` passes `anytype` to `.include(anytype)`
const MyWorld = ztg.WorldBuilder.new(.{
    ztg.base,
    player,
}).Build();

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
    pub fn player_speak(query: ztg.Query(.{ Player, ztg.base.Transform }, .{}), time: ztg.base.Time) !void {
        // Query is a wrapper for MultiArrayList, where all the types you passed into the
        // original tuple get indexed as "a" through "z".
        for (query.items(.a), query.items(.b)) |plr, trn| {
            std.debug.print("My name is {s}, and I'm located at {} {}.\n", .{ plr.name, trn.pos.x, trn.pos.y });
            std.debug.print("The current frame is {}\n", .{time.frameCount});
        }
    }
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

    // runs the PRE_UPDATE, UPDATE, and POST_UPDATE stages.
    try world.runUpdateStages();
    // it is recommended over runStage("UPDATE") as some built-in module systems use PRE_UPDATE
    // and POST_UPDATE, such as input and physics
}
