const std = @import("std");
const TypeBuilder = @import("type_builder.zig");
const TypeMap = @import("type_map.zig");

pub const Entity = usize;

/// Takes tuple: { Player, Position, Sprite } and returns
/// a MultiArrayList of a struct of pointers labeled a-z: { a: *Player, b: *Position, c: *Sprite }
/// if one of the tuple types is `Entity` (`usize`) then it will also have
/// the entity those components are attatched to.
///
/// As items are labeled a-z, anything past 26 items in the query is not recommended.
pub fn Query(comptime q: anytype, comptime options: anytype) type {
    if (comptime q.len >= 158) @compileError("Query has too many items.");

    var tm = TypeMap{};
    var tb = TypeBuilder.new(false, .Auto);

    inline for (q, 0..) |Q, i| {
        tb.addField(std.fmt.comptimePrint("{c}", .{@intCast(u8, 97 + i)}), if (Q == Entity) Entity else *Q, null);
        if (tm.has(Q)) @compileError("Cannot use the same type twice in a query.");
        tm.append(Q);
    }

    tb.addField("QueryType", @TypeOf(q), &q);
    tb.addField("OptionsType", @TypeOf(options), &options);
    return std.MultiArrayList(tb.Build());
}

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

pub fn EventReceiver(comptime T: type) type {
    return struct {
        pub const EventRecvType = T;

        items: []const T,
    };
}

pub fn Added(comptime T: type, comptime Opts: type) type {
    return struct {
        pub const QueryAdded: type = T;
        pub const Options: type = Opts;
    };
}

pub fn Removed(comptime T: type, comptime Opts: type) type {
    return struct {
        pub const QueryRemoved: type = T;
        pub const Options: type = Opts;
    };
}

pub fn With(comptime T: type) type {
    return struct {
        pub const QueryWith = T;
    };
}

pub fn Without(comptime T: type) type {
    return struct {
        pub const QueryWithout = T;
    };
}
