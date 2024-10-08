# zentig_ecs
A Zig ECS library. 

Zentig is designed for scalability and ease of use, while staying out of your way.
It's heavily inspired by everything that makes [bevy_ecs](https://github.com/bevyengine/bevy)
so great and [Unity](https://unity.com/) so approachable.

##### WARNING:
It is not recommended to use zentig for anything major in it's current state.
While it is functional and I use it frequently, it is far from battle tested.

That being said, if you encounter any problems please feel free to open an issue!

## Installation
Fetching for zig master:
```
zig fetch --save git+https://github.com/freakmangd/zentig_ecs
```

Fetching for zig 0.13.0:
```
zig fetch --save https://github.com/freakmangd/zentig_ecs/archive/refs/tags/0.13.0.tar.gz
```

In both cases, place this in your `build.zig`:
```zig
const zentig = b.dependency("zentig-ecs", .{});
exe.root_module.addImport("ztg", zentig.module("zentig"));
```

And import it in your project:
```zig
const ztg = @import("ztg");
```

## Overview
An entity is just a `usize`:
```zig
pub const Entity = usize;
```

A basic component:
```zig
pub const Player = struct {
  name: []const u8,
};
```

A basic system:
```zig
pub fn playerSpeak(q: ztg.Query(.{Player})) !void {
  for (q.items(0)) |plr| {
    std.debug.print("My name is {s}\n", .{self.name});
  }
}
```

Registering systems/components into a world:
```zig
const MyWorld = blk: {
  var wb = ztg.WorldBuilder.init(&.{});
  wb.addComponents(&.{Player});
  wb.addSystemsToStage(.update, playerSpeak);
  break :blk wb.Build();
};
```

Calling systems is easily integratable into your game framework:
```zig
test "running systems" {
  var world = MyWorld.init(testing.allocator);
  defer world.deinit();

  try world.runStage(.load);
  try world.runUpdateStages();
  try world.runStage(.draw);
  
  // Support for user defined stages
  try world.runStageList(&.{ .post_process, .pre_reset, .post_mortem });
}
```

## Scalability
The `.include()` function in `WorldBuilder` makes it easy to compartmentalize your game systems.
As well as integrate third party libraries with only one extra line!

`main.zig`:
```zig
// .include() looks for a `pub fn include(comptime *WorldBuilder) (!)void` def 
// in each struct. If the function errors it's a compile error,
// but the signature can return either `!void` or `void`
wb.include(&.{
  ztg.base,
  @import("player.zig"),
  @import("my_library"),
});
```

`player.zig`:
```zig
pub fn include(comptime wb: *ztg.WorldBuilder) void {
  wb.addComponents(.{ Player, PlayerGun, PlayerHUD });
  wb.addSystemsToStage(.update, .{ update_player, update_gun, update_hud });
}
```

`my_library/init.zig`:
```zig
pub fn include(comptime wb: *ztg.WorldBuilder) void {
  wb.include(&.{
      // Namespaces can be included more than once to "ensure" 
      // they are included if you depend on them
      ztg.base, 
      //...
  });
}
```

## Getting Started
See this short tutorial on creating systems and components [here](https://github.com/freakmangd/zentig_ecs/tree/main/docs/hello_world.md)

## Full Examples
See full examples in the [examples folder](https://github.com/freakmangd/zentig_ecs/tree/main/examples)

## Framework Support
zentig is framework agnostic, it doesn't include any drawing capabilities. For that you need something like Raylib, I've created a library that
wraps common Raylib components and provides systems that act on those components [here](https://github.com/freakmangd/zentig_raylib).

That page provides installation instructions and usage examples.
