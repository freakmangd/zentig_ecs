const std = @import("std");
const ztg = @import("init.zig");
const util = @import("util.zig");

/// Used in systems to _send_ events to be received by `EventReceiver`s of the same `T`
///
/// Events are cleared at the end of every frame, so system ordering is
/// important. See `docs/system_ordering.md` for more info.
pub fn EventSender(comptime T: type) type {
    return struct {
        const Self = @This();

        // used for type identification
        pub const EventSendType = T;

        alloc: std.mem.Allocator,
        event_pool: *EventArray(T),

        pub fn send(self: Self, event_data: T) std.mem.Allocator.Error!void {
            try self.event_pool.arr.append(self.alloc, event_data);
        }
    };
}

/// Used in systems to _receive_ events sent by `EventSender`s of the same `T`
///
/// Events are cleared at the end of every frame, so system ordering is
/// important. See `docs/system_ordering.md` for more info.
pub fn EventReceiver(comptime T: type) type {
    return struct {
        // used for type identification
        pub const EventRecvType = T;

        events: *EventArray(T),

        pub fn next(self: @This()) ?*T {
            return self.events.next();
        }
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

        fn sendEventFirst(evt: ztg.EventSender(MyEvent)) !void {
            try evt.send(.win);
            try evt.send(.lose);
        }

        fn recvEventFirst(evt: ztg.EventReceiver(MyEvent)) !void {
            try std.testing.expectEqual(MyEvent.win, evt.next().?.*);
            try std.testing.expectEqual(MyEvent.lose, evt.next().?.*);
            try std.testing.expectEqual(null, evt.next());
        }

        fn sendEventSecond(evt: ztg.EventSender(MyEvent)) !void {
            try evt.send(.tie);
        }

        fn recvEventSecond(evt: ztg.EventReceiver(MyEvent)) !void {
            try std.testing.expectEqual(MyEvent.tie, evt.next().?.*);
            try std.testing.expectEqual(null, evt.next());
        }

        pub fn include(comptime wb: *ztg.WorldBuilder) void {
            wb.addEvent(MyEvent);
            wb.addLabel(.update, .send_event, .default);
            wb.addSystems(.{
                .update = .{
                    sendEventFirst,
                    recvEventFirst,
                    sendEventSecond,
                    recvEventSecond,
                },
            });
        }
    };

    var world = try events_test_mod.World.init(std.testing.allocator);
    defer world.deinit();
    try world.runStage(.update);
}

fn EventArray(comptime T: type) type {
    return struct {
        arr: std.ArrayListUnmanaged(T) = .{},
        index: usize = 0,

        pub fn next(self: *@This()) ?*T {
            if (self.index >= self.arr.items.len) return null;
            defer self.index += 1;
            return &self.arr.items[self.index];
        }
    };
}

pub fn EventPools(comptime event_types: anytype) type {
    const Inner = blk: {
        var tb = ztg.meta.TypeBuilder{};
        inline for (event_types) |T| {
            tb.appendTupleField(EventArray(T), &EventArray(T){});
        }
        break :blk tb.Build();
    };

    return struct {
        const Self = @This();

        inner: Inner = .{},

        pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
            inline for (std.meta.fields(Inner)) |field| {
                @field(self.inner, field.name).arr.deinit(alloc);
            }
        }

        pub fn getPtr(self: *Self, comptime EventType: type) *EventArray(EventType) {
            const field_name = comptime std.fmt.comptimePrint("{}", .{util.indexOfType(event_types, EventType) orelse util.compileError("Event `{s}` was not registered.", .{@typeName(EventType)})});
            return &@field(self.inner, field_name);
        }

        pub fn clear(self: *Self) void {
            inline for (std.meta.fields(Inner)) |field| {
                const ea = &@field(self.inner, field.name);
                ea.arr.clearRetainingCapacity();
                ea.index = 0;
            }
        }
    };
}
