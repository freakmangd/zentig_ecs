const std = @import("std");
const ztg = @import("zentig");
const rl = @import("raylib");
const zrl = ztg.Raylib(rl);

// Constructing the world must be done at comptime
// `.init(anytype)` passes `anytype` to `.include(anytype)`
const MyWorld = ztg.WorldBuilder.init(.{
    ztg.base,
    zrl,
}).Build();

// entities with both a Sprite and Transform component will
// be drawn during the .draw stage
const RlObject = struct {
    zrl.Sprite,
    ztg.base.Transform,
};

pub fn main() !void {
    // typical raylib-zig setup
    const screenWidth = 800;
    const screenHeight = 600;

    rl.InitWindow(screenWidth, screenHeight, "Untitled");
    rl.SetTargetFPS(60);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var world = try MyWorld.init(alloc);
    defer world.deinit();

    for (0..10) |_| {
        const obj_ent = try world.newEnt();

        try world.giveEntMany(obj_ent, RlObject{
            zrl.Sprite.init("examples/smile.png", rl.WHITE),
            .{ .pos = ztg.Vec3.init(rl.GetRandomValue(0, screenWidth), rl.GetRandomValue(0, screenHeight), 0.0) }, // the z component of a position will not be taken into account
        });
    }

    try world.runInitStages();

    while (!rl.WindowShouldClose()) {
        try world.runUpdateStages();

        rl.BeginDrawing();
        rl.ClearBackground(rl.BLACK);

        // .X_draw stages must be called between rl.BeginDrawing() and rl.EndDrawing()
        try world.runDrawStages();

        rl.EndDrawing();

        world.cleanForNextFrame();
    }

    rl.CloseWindow();
}
