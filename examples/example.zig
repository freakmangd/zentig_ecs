const std = @import("std");
const ztg = @import("zentig");

// Constructing the world must be done at comptime
// `.init(anytype)` passes `anytype` to `.include(anytype)`
const MyWorld = ztg.WorldBuilder.init(&.{
    ztg.base,
    player,
    Mover,
}).Build();

// This would most likely be a player.zig file instead
const player = struct {
    // This is called when passed into a .include()/.init() call on a WorldBuilder
    pub fn include(comptime wb: *ztg.WorldBuilder) void {
        // All components used in the world must be added at comptime
        wb.addComponents(&.{Player});
        // Adds a system to the .load and .update stage of the world, systems can only be added during comptime
        wb.addSystems(.{
            .load = .{spawn},
            .update = .{speak},
        });
        // You can add to any stage defined in default_stages or you own custom stages
        // ex: wb.addStage(.player_speak);
    }

    // A basic component
    pub const Player = struct {
        name: []const u8,
    };

    // A "Bundle" is just a name for a predetermined list of Components,
    // it's really just so you dont forget to add something when making entities
    // and/or for creating helper functions for these groups of compontents.
    pub const PlayerBundle = struct {
        Player,
        ztg.base.Transform,
    };

    pub fn spawn(com: ztg.Commands) !void {
        // Use the PlayerBundle struct as a blueprint
        const plr_ent = try com.newEntWithMany(player.PlayerBundle{
            .{ .name = "Player" },
            .{ .pos = ztg.Vec3.init(10, 10, 0) },
        });

        try plr_ent.giveEnt(Mover{
            .speed = 5,
            .dir = ztg.Vec3.right(),
        });
    }

    // A basic system
    pub fn speak(q: ztg.Query(.{ Player, ztg.base.Transform }), time: ztg.base.Time) !void {
        // Here you can query for items in the world, and running .items()
        // on a query object will return an array of pointers to all the objects
        // of that type in the world.
        //
        // The number in items() represents the position of the Type in the Query type.
        // 0 for Player, 1 for Transform, etc.
        for (q.items(0), q.items(1)) |plr, tr| {
            std.debug.print("My name is {s}, and I'm located at {d} {d}.\n", .{ plr.name, tr.pos.x, tr.pos.y });
            std.debug.print("The current frame is {}\n", .{time.frame_count});
        }
    }
};

// This component defines a speed and direction for objects to move in
const Mover = struct {
    speed: f32,
    dir: ztg.Vec3,

    pub fn onAdded(ent: ztg.Entity, com: ztg.Commands) !void {
        // A default transform is provided in case the entity doesnt have one.
        // The defaults of a transform place it at { 0, 0, 0 } with a scale of
        // { 1, 1, 1 } and a rotation of 0.
        if (!com.checkEntHas(ent, ztg.base.Transform)) try ent.giveEnt(ztg.base.Transform{});
    }

    pub fn include(comptime wb: *ztg.WorldBuilder) void {
        // Mods can be included multiple times without any effect.
        // Here we want to ensure the ztg.base.Transform component
        // has been added to the world.
        wb.include(&.{ztg.base});

        wb.addComponents(&.{Mover});
        wb.addUpdateSystems(.{update});
    }

    fn update(q: ztg.Query(.{ Mover, ztg.base.Transform })) void {
        for (q.items(0), q.items(1)) |m, tr| {
            tr.translate(m.dir.mul(m.speed));
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    // Init the world
    var world = try MyWorld.init(alloc);
    defer world.deinit();

    // runs the .load stage
    try world.runStage(.load);

    // runs the .update stage
    try world.runStage(.update);

    std.debug.print("Next frame!\n", .{});

    // ditto
    try world.runStage(.update);
}
