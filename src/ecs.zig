const std = @import("std");
const ztg = @import("init.zig");
const TypeBuilder = @import("type_builder.zig");
const TypeMap = @import("type_map.zig");

pub usingnamespace @import("query.zig");

pub const util = @import("util.zig");

pub const Entity = usize;

pub const EntityHandle = struct {
    com: ztg.Commands,
    ent: Entity,

    pub fn giveEnt(self: EntityHandle, comp: anytype) !void {
        try self.com.giveEnt(comp);
    }

    pub fn giveEntMany(self: EntityHandle, comps: anytype) !void {
        try self.com.giveEntMany(self.ent, comps);
    }
};

//pub const EntityIter = @import("entity_iterator.zig");

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

pub const OnCrashFn = fn (ztg.Commands, CrashReason) anyerror!Status;

pub const CrashReason = enum {
    hit_ent_limit,
};

pub const Status = enum {
    failure,
    success,
};
