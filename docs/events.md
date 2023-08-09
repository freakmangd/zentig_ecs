## Events
Events are objects in zentig that can be passed between any number of systems.

### Registering and using an event
```zig
const MyEvent = enum {
    win,
    lose,
    tie,
    none,
};

pub fn include(comptime wb: *ztg.WorldBuilder) void {
    wb.addEvent(MyEvent);
    wb.addLabel(.update, .send_event, .default);
    wb.addSystems(.{
        .update = .{ ztg.during(.send_event, sendEvent), ztg.after(.send_event, recvEvent) },
    });
}

fn sendEvent(evt: ztg.EventSender(MyEvent)) !void {
    try evt.send(.win);
    try evt.send(.lose);
    try evt.send(.tie);
}

fn recvEvent(evt: ztg.EventReceiver(MyEvent)) !void {
    try std.testing.expectEqualSlices(MyEvent, evt.items, &.{ .win, .lose, .tie });
}
```

Events are cleared every frame (i.e. after you call `World.cleanForNextFrame`) so you have to
order your systems in a precise way to actually receive any of the events.

See more about system ordering [here](https://github.com/freakmangd/zentig_ecs/tree/main/docs/system_ordering.md).
