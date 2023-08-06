# zentig_ecs
A Zig ECS library. 

Zentig is designed for scalability and ease of use, while staying out of your way.
It's heavily inspired by everything that makes [bevy_ecs](https://github.com/bevyengine/bevy)
so great and [Unity](https://unity.com/) so approachable.

##### WARNING:
It is not recommended to use zentig for anything major in it's current state.
While functional, it is still very obtuse and not optimized as it lacks real testing.

That being said, if you encounter any problems please feel free to open an issue!

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
pub fn playerSpeak(q: ztg.Query(.{Player}, .{})) !void {
  for (q.items(.a)) |plr| {
    std.debug.print("My name is {s}\n", .{self.name});
  }
}
```

Registering systems/components into a world:
```zig
const MyWorld = blk: {
  var wb = ztg.WorldBuilder.init(&.{});
  wb.addComponents(&.{Player});
  wb.addSystemsToStage(.update, .{playerSpeak});
  break :blk wb.Build();
};
```

Calling systems is easily integratable into your game framework:
```zig
test "running systems" {
  var world = MyWorld.init(testing.allocator);

  world.runStage(.load);
  world.runStage(.update);
  world.runStage(.draw);
  
  // Support for user defined stages
  world.runStageList(&.{ .post_process, .pre_reset, .post_mortem });
}
```

## Scalability
The `.include()` function in `WorldBuilder` makes it easy to compartmentalize your game systems.
As well as integrate third party libraries with only one extra line!

`main.zig`:
```zig
// .include() looks for a `pub fn include(comptime *WorldBuilder) (!)void` def in each struct
// if the function errors, it's a compile error. But the signature can return either `!void` or `void`
wb.include(&.{
  ztg.base,
  @include("player.zig"),
  @include("my_library"),
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
      ztg.base, // Namespaces can be included more than once to "ensure" they are included
      //...
  });
}
```

## Installation
See the page on installing [here](https://github.com/freakmangd/zentig_ecs/tree/main/docs/installation.md)

## Full Examples
See full examples in the [examples folder](https://github.com/freakmangd/zentig_ecs/tree/main/examples).

## Raylib Support
While it is easy to get started with a raylib with just zentig_ecs, I've created a library that
wraps common components and provides systems that act on those components [here](https://github.com/freakmangd/zentig_raylib).

That page provides installation instructions and usage examples.
