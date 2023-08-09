# Hello World!
## Getting your first stages up and running.

After you have installed zentig and have it compiling, here is a quick guide to making your
first `World` and how entities, components, and systems work within zentig.

### Creating the World

First, we're going to import zentig in `main.zig`. I have it under a module named `"zentig"`.

Add to line 1:
```zig
01: const std = @import("std");
02: const ztg = @import("zentig");
```

Then, we're going to use the `WorldBuilder` to create our World.

Add to line 4:
```zig
04: const World = ztg.WorldBuilder.init(&.{}).Build();
```

That `&.{}` is an empty list of `type`s which are used as plugins for our world.
All a type needs to be considered a "plugin" is a public declaration of the form: [^1]
```zig
pub fn include(comptime wb: *ztg.WorldBuilder) void {}
// or
pub fn include(comptime wb: *ztg.WorldBuilder) !void {}
```

[^1]: In the errorable case, any error returned becomes a compile error.

Right now, lets just create the world and try to use it:

Starting at line 6:
```zig
06:  pub fn main() !void {
07:     // Standard allocator setup
08:     var gpa = std.heap.GeneralPurposeAllocator(.{}) {};
09:     defer _ = gpa.deinit();
10:     const alloc = gpa.allocator();
11:
12:     var world = try World.init(alloc);
13:     defer world.deinit();
13:
15:     world.runStage(.load);
16: }
```

The `World.runStage` function runs the `.load` stage. Which doesnt have any systems in it yet,
so it won't do anything sadly.

### Extending our world

In order for our world to have functionality, we must add systems and components to the world builder.

We can turn our main file into a "plugin" by adding this function:

Starting at line 6:

```zig
06: pub fn include(comptime wb: *ztg.WorldBuilder) void {
07: 
08: }
09:
10: pub fn main() !void {
```

Then you must include the file into the `WorldBuilder` by changing line 4 to:
```zig
const World = ztg.WorldBuilder.init(&.{@This()}).Build();
```

The `@This()` makes the `WorldBuilder` run the `include` function we just defined.

Now we can start adding components and systems to our world.

#### Systems

Let's make a simple system:

Starting at line 12:
```zig
12: fn mySystem() void {
13:     std.debug.print("Hello World!\n", .{});
14: }
```

No let's add it to the world through our `include` function:

Add to line 9:
```zig
08: pub fn include(comptime wb: *ztg.WorldBuilder) void {
09:     wb.addSystemsToStage(.load, mySystem);
10: }
```

Now if we build it using `zig build run` we get this output:
```
Hello World!
```

#### Components

Let's make a simple component:

Add to line 6: [^2]
```zig
06: const Name = struct { []const u8 };
07: 
08: pub fn include(comptime wb: *ztg.WorldBuilder) void {
```

[^2]: This example doesnt consider memory lifetime for a slice, but you should

Let's add that to the world like so:

Add to line 10:
```zig
08: pub fn include(comptime wb: *ztg.WorldBuilder) void {
09:     wb.addSystemsToStage(.load, mySystem);
10:     wb.addComponents(&.{Name});
11: }
```

Now we can create entities that have that component. We can add entities through systems or 
the world directly, but it's more useful to do it through systems.

Lets make a system to do just that:

Add to line 17:
```zig
17: fn spawnEntities(com: ztg.Commands) !void {
18:     _ = try com.newEntWith(Name{"Mark"});
19:     _ = try com.newEntWith(Name{"Steve"});
20:     _ = try com.newEntWith(Name{"Alice"});
21: }
```

Here we're discarding the `EntityHandle` returned by `newEntWith`, which is just an `Entity` and a `Commands`
together to add some helper functions, but we dont need it as the entity is done being constructed once
it has a `Name`.

#### Querying for components

Let's change our previous system so that it queries for entities that have the `Name` component:

Change line 13:
```zig
13: fn mySystem(q: ztg.Query(.{Name})) void {
14:     for (q.items(0)) |name| {
15:         // Here we use name[0] because Name is a single item tuple
16:         std.debug.print("Hello {s}!\n", .{name[0]});
17:     }
18: }
```
>__Sidenote:__
>
>`Query.items` is a function that returns a slice of the components you queried for.
>The argument sepcifies which component is iterated over. For example if you had a query like:
>```zig
>ztg.Query(.{Name, Player, Score})
>```
>`q.items(0)` returns a `[]const *Name`<br>
>`q.items(1)` returns a `[]const *Player`<br>
>`q.items(2)` returns a `[]const *Score`<br>
>
>Which you can iterate over all at the same time because they are of equal lengths:
>```zig
>for (q.items(0), q.items(1), q.items(2)) |name, player, score| {
>    if (score.value > 100 and player.health > 0) std.debug.print("{s} has won!", .{name});
>}
>```

Now we just need to change a bit of the `include` and `main` functions so these functions execute
in order.

in `fn include`:
```zig
08: pub fn include(comptime wb: *ztg.WorldBuilder) void {
09:     wb.addSystemsToStage(.load, spawnEntities);
10:     wb.addSystemsToStage(.update, mySystem);
11:     wb.addComponents(&.{Name});
12: }
```

on line 37 in `fn main`:
```zig
36:     try world.runStage(.load);
37:     try world.runStage(.update);
```

Now when we run `zig build run` we get this output:
```
Hello Mark!
Hello Steve!
Hello Alice!
```

Our program is now complete, but try adding a `Score` component to each entity with a field `total` and an update system
that increments it by one and reports the total and the entity's name.
Then try running `.update` multiple times until it reports a score of `3` for each.

> Hint: You can either use `Commands.newEntWithMany` and pass an annonymous tuple of type `struct { Name, Score }`, or
> you can assign that `EntityHandle` to a local and use `EntityHandle.give` to give the entity a `Score` as well.

The answer and the whole file we just created is in `examples/hello_world.zig`.

