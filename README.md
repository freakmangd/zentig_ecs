# zentig_ecs (NOT FOR USE CURRENTLY)
A Zig ECS library. 

Zentig is designed for scalability and ease of use, while staying out of your way.
It's heavily inspired by everything that makes [bevy_ecs](https://github.com/bevyengine/bevy) so great.

### __WARNING: This library _DOES NOT WORK___
There currently is an issue with the compiler, or something, I actually don't know really.
This is the compiler message I get when building:
```
src\ecs.zig:234:13: error: TODO (LLVM): implement const of pointer type '[TODO fix internal compiler bug regarding dump]' (value.Value.Tag.function)
        pub fn init(alloc: Allocator) !Self {
```

Which I don't _think_ is my fault... probably...

## Simple

A basic component:
```zig
pub const Player = struct {
  name: []const u8,
  
  pub fn speak(self: Player) void {
    std.debug.print("My name is {s}\n", .{self.name});
  }
};
```

A basic system:
```zig
// If the first argument is of type std.mem.Allocator, the allocator passed into
// the world when creating it is passed into the system.
pub fn player_speak(q: Query(.{Player}, .{})) !void {
  for (q.items(.a)) |plr| {
    plr.speak();
  }
}
```

An entity is just a usize:
```zig
pub const Entity = usize;
```

Registering systems/components into a world:
```zig
const MyWorld = comptime blk: {
  var wb = ztg.WorldBuilder.new();
  wb.addComponents(.{Player});
  wb.addUpdateSystems(.{player_speak});
  break :blk wb.Build();
};
```

Calling systems is easily integratable into your game framework:
```zig
  world.runInitStages();
  world.runUpdateStages();
  world.runDrawStages();
  
  // Support for user defined stages
  world.runStageList(&.{ "UPDATE", "POST_PROCESS", "PRE_RESET", "POST_MORTEM" });
```

## Scalability
The `.include()` function in `WorldBuilder` makes it easy to compartmentalize your game systems.

`main.zig`:
```zig
// --snip--
// .include() looks for a pub fn register(WorldBuilder) def in each struct
  wb.include(.{
    ztg.base,
    @include("player.zig"),
  });
// --snip
```

`player.zig`:
```zig
pub fn register(comptime wb: WorldBuilder) anyerror!void {
  wb.addComponents(.{ Player, PlayerGun, PlayerHUD });
  wb.addSystems(.{ update_player, update_gun, update_hud });
  try wb.include(...);
}
```

## Full Example
```zig
const std = @import("std");
const ztg = @import("zentig");

// This would most likely be a player.zig file instead
const player = struct {
  // This is called when the containing struct is passed into a .include() call on a WorldBuilder
  pub fn register(comptime world: ztg.WorldBuilder) anyerror!void {
    // All components used in the world must be added before .Build() is called on the WorldBuilder
    world.addComponents(.{Player});
    // Adds a system to the UPDATE stage of the world, systems can only be added during comptime
    world.addUpdateSystems(.{player_speak});
  }
  
  // A basic component
  pub const Player = struct {
    name: []const u8,
  };
  
  // A "Bundle" is just a name for a predetermined list of Components,
  // it's really just so you dont forget to add something when making entities
  pub const PlayerBundle = struct {
    p: Player,
    tran: ztg.base.Transform,
  };
  
  // A basic system
  pub fn player_speak(query: ztg.Query(.{Player, ztg.base.Transform}, .{})) !void {
    // Query is a wrapper for MultiArrayList, where all the types you passed into the
    // original tuple get indexed as "a" through "z".
    for (query.items(.a), query.items(.b)) |plr, trn| {
      std.debug.print("My name is {s}, and I'm located at {} {}.", .{plr.name, trn.pos.x, trn.pos.y});
    }
  }
};

pub fn main() !void {
  // Constructing the world must be done at comptime
  const MyWorld = comptime blk: {
    var wb = ztg.WorldBuilder.new();
    try wb.include(.{
      ztg.base,
      player,
    });
    break :blk wb.Build();
  };
  
  var gpa = std.heap.GeneralPurposeAllocator(.{}) {};
  const alloc = gpa.allocator();

  var world = try MyWorld.init(alloc);
  defer world.deinit();

  // Create a new entity for the player
  const player_ent = try world.newEnt();
  
  // Use the PlayerBundle struct as a blueprint
  try world.giveEntBundle(player_ent, player.PlayerBundle, .{
    .p = .{ .name = "Player" },
    .tran = .{ .pos = ztg.Vec3.new(10, 10, 10) }, // rot defaults to 0 and scale defaults to ztg.Vec3(1, 1, 1)
  });

  // runs all the functions added to the UPDATE stage
  try world.runStage("UPDATE");
}
```

## Raylib Support (WIP)

Zentig comes packed in with useful components around Raylib.
