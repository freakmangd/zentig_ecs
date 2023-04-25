# zentig_ecs
A Zig ECS library. 

Zentig is designed for scalability and ease of use, while staying out of your way.
It's heavily inspired by everything that makes [bevy_ecs](https://github.com/bevyengine/bevy) so great.

### WARNING:
It is not recommended to use zentig for anything major in it's current state.
While functional, it is still very obtuse and not optimized as it lacks real testing.

## Installation
```cmd
cd dir_with_build_dot_zig_file
git clone https://github.com/freakmangd/zentig_ecs.git lib/zentig_ecs
```

`build.zig`
```zig
@import("lib/zentig_ecs/lib.zig").addAsPackage("zentig", exe);
```

## Simple

A basic component:
```zig
pub const Player = struct {
  name: []const u8,
};
```

A basic system:
```zig
// If the first argument is of type std.mem.Allocator, the allocator passed into
// the world when creating it is passed into the system.
pub fn playerSpeak(q: Query(.{Player}, .{})) !void {
  for (q.items(.a)) |plr| {
    std.debug.print("My name is {s}\n", .{self.name});
  }
}
```

An entity is just a usize:
```zig
pub const Entity = usize;
```

Registering systems/components into a world:
```zig
const MyWorld = blk: {
  var wb = ztg.WorldBuilder.new();
  wb.addComponents(.{Player});
  wb.addUpdateSystems(.{playerSpeak});
  break :blk wb.Build();
};
```

Calling systems is easily integratable into your game framework:
```zig
test "running systems" {
  var world = MyWorld.init(testing.allocator);

  world.runInitStages();
  world.runUpdateStages();
  world.runDrawStages();
  
  // Support for user defined stages
  world.runStageList(&.{ "UPDATE", "POST_PROCESS", "PRE_RESET", "POST_MORTEM" });
}
```

## Scalability
The `.include()` function in `WorldBuilder` makes it easy to compartmentalize your game systems.

`main.zig`:
```zig
// --snip--
// .include() looks for a `pub fn include(comptime *WorldBuilder) !void` def in each struct
  wb.include(.{
    ztg.base.Init(.{}),
    @include("player.zig"),
  });
// --snip
```

`player.zig`:
```zig
pub fn include(comptime wb: *WorldBuilder) anyerror!void {
  wb.addComponents(.{ Player, PlayerGun, PlayerHUD });
  wb.addSystems(.{ update_player, update_gun, update_hud });
  wb.include(...);
}
```

## Full Example
```zig
const std = @import("std");
const ztg = @import("zentig");

// This would most likely be a player.zig file instead
const player = struct {
  // This is called when passed into a .include() call on a WorldBuilder
  pub fn include(comptime wb: *ztg.WorldBuilder) !void {
    // All components used in the world must be added before .Build() is called on the WorldBuilder
    wb.addComponents(.{Player});
    // Adds a system to the UPDATE stage of the world, systems can only be added during comptime
    wb.addUpdateSystems(.{playerSpeak});
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
  pub fn playerSpeak(query: ztg.Query(.{Player, ztg.base.Transform}, .{})) !void {
    // Query is a wrapper for MultiArrayList, where all the types you passed into the
    // original tuple get indexed as "a" through "z".
    for (query.items(.a), query.items(.b)) |plr, trn| {
      std.debug.print("My name is {s}, and I'm located at {} {}.\n", .{plr.name, trn.pos.x, trn.pos.y});
    }
  }
};

// Constructing the world type must be done at comptime
// `.new(anytype)` passes `anytype` to `.include(anytype)`
const MyWorld = ztg.WorldBuilder.new(.{
  ztg.base.Init(.{}),
  player,
}).Build();

pub fn main() !void {
  var gpa = std.heap.GeneralPurposeAllocator(.{}) {};
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
```

Output:
```
My name is Player, and I'm located at 1.0e+01 1.0e+01.
```

## Raylib Support (WIP)

Zentig comes packed in with useful components around Raylib.
