const std = @import("std");
const ztg = @import("init.zig");

/// Used in systems to _send_ events to be received by `EventReceiver`s of the same `T`
///
/// Events are cleared at the end of every frame, so system ordering is
/// important. See `docs/system_ordering.md` for more info.
///
/// Example:
/// ```zig
/// fn sendEvent(evt: ztg.EventSender(MyEvent)) !void {
///     try evt.send(.win);
///     try evt.send(.lose);
///     try evt.send(.tie);
/// }
///
/// fn recvEvent(evt: ztg.EventReceiver(MyEvent)) !void {
///     try std.testing.expectEqualSlices(MyEvent, evt.items, &.{ .win, .lose, .tie });
/// }
/// ```
pub fn EventSender(comptime T: type) type {
    return struct {
        const Self = @This();

        // used for type identification
        pub const EventSendType = T;

        alloc: std.mem.Allocator,
        event_pool: *std.ArrayListUnmanaged(T),

        pub fn send(self: Self, event_data: T) std.mem.Allocator.Error!void {
            try self.event_pool.append(self.alloc, event_data);
        }
    };
}

/// Used in systems to _receive_ events sent by `EventSender`s of the same `T`
///
/// Events are cleared at the end of every frame, so system ordering is
/// important. See `docs/system_ordering.md` for more info.
///
/// Example:
/// ```zig
/// fn sendEvent(evt: ztg.EventSender(MyEvent)) !void {
///     try evt.send(.win);
///     try evt.send(.lose);
///     try evt.send(.tie);
/// }
///
/// fn recvEvent(evt: ztg.EventReceiver(MyEvent)) !void {
///     try std.testing.expectEqualSlices(MyEvent, evt.items, &.{ .win, .lose, .tie });
/// }
/// ```
pub fn EventReceiver(comptime T: type) type {
    return struct {
        // used for type identification
        pub const EventRecvType = T;

        items: []const T,
    };
}

test "events" {
    const events_test_mod = struct {
        const World = ztg.WorldBuilder.init(&.{@This()}).Build();

        const MyEvent = enum {
            win,
            lose,
            tie,
            none,
        };

        fn sendEvent(evt: ztg.EventSender(MyEvent)) !void {
            try evt.send(.win);
            try evt.send(.lose);
            try evt.send(.tie);
        }

        fn recvEvent(evt: ztg.EventReceiver(MyEvent)) !void {
            try std.testing.expectEqualSlices(MyEvent, evt.items, &.{ .win, .lose, .tie });
        }

        pub fn include(comptime wb: *ztg.WorldBuilder) void {
            wb.addEvent(MyEvent);
            wb.addLabel(.update, .send_event, .default);
            wb.addSystems(.{
                .update = .{ ztg.during(.send_event, sendEvent), ztg.after(.send_event, recvEvent) },
            });
        }
    };

    var world = try events_test_mod.World.init(std.testing.allocator);
    defer world.deinit();
    try world.runStage(.update);
}
