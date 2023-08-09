## Queries
Queries are types you can add to your systems to access components added to your entities.

```zig
const MyComponent = struct {
    data: i32,
};

pub fn mySystem(q: ztg.Query(.{ MyComponent })) void {
    for (q.items(0)) |comp| {
        // @TypeOf(comp) == *MyComponent

        comp.data += 1;
    }
}
```

`Query.items` will return a slice of mutable pointers to the queried types (i.e. `[]const *anyopaque`),
unless it is `ztg.Entity`, in which case it will be a slice of `ztg.Entity` (i.e. `[]const ztg.Entity`).

### Querying for entities

When you query for `ztg.Entity`, it retrieves the entity the other components are attached to.

```zig
pub fn mySystem(q: ztg.Query(.{ ztg.Entity, MyComponent })) void {
    for (q.items(0), q.items(1)) |ent, comp| {
        // @TypeOf(ent) == ztg.Entity
        // @TypeOf(comp) == *MyComponent

        std.debug.print("{}'s data is equal to {}", .{ ent, comp.data });
    }
}
```

### Query filters

Query filters are ways to filter your queries without collecting the items of that type.

Example:
```zig
//                 use ztg.QueryOpts to add filters
pub fn mySystem(q: ztg.QueryOpts(.{ ztg.Entity }, .{ ztg.With(MyComponent) })) void {
    for (q.items(0)) |ent| {
        std.debug.print("{} has a MyComponent", .{ ent });
    }
}
```

A common use case is querying for empty structs:
```zig
const Player = struct {};

pub fn mySystem(q: ztg.QueryOpts(.{ ztg.base.Transform }, .{ ztg.With(Player) })) void {
    for (q.items(0)) |tr| {
        tr.translate(.{
            .x = 100.0,
            .y = 50.0,
        });
    }
}
```
