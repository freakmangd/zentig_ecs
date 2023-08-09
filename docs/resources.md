## Resources

Resources are global objects you can register and request within your systems.

### Requesting systems

Requesting systems can be done by value or by pointer, just by adding the type to your
system's paramter list.

```zig
// std.rand.Random is a resource added by default
fn mySystem(rand: std.rand.Random) void {
    std.debug.print("{}\n", .{ rand.float(f32) });
}
```

### Adding systems

Adding systems are done during comptime through the `WorldBuilder`

```zig
const MyResource = struct {
    win_message: []const u8,
};

wb.addResource(MyResource, .{ .win_message = "You did it!" });
```

A common pattern is to leave MyResource as `undefined` and add a system to `.init` to
set up the resource.

```zig
wb.addResource(MyResource, undefined);
wb.addSystemsToStage(.init, ini_MyResource);

// std.mem.Allocator is a default resource 
// that you set by passing an allocator to `World.init(Allocator)`
fn ini_MyResource(mr: *MyResource, alloc: std.mem.Allocator) void {
    mr.score_list = std.ArrayList(f32).init(alloc);
}
```
