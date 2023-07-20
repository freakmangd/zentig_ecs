const std = @import("std");
const ztg = @import("init.zig");

pub const Entity = usize;

pub const EntityHandle = struct {
    com: ztg.Commands,
    ent: Entity,

    pub inline fn giveEnt(self: EntityHandle, comp: anytype) !void {
        try self.com.giveEnt(self.ent, comp);
    }

    pub inline fn giveEntMany(self: EntityHandle, comps: anytype) !void {
        try self.com.giveEntMany(self.ent, comps);
    }

    pub inline fn checkEntHas(self: EntityHandle, comptime Comp: type) bool {
        return self.com.checkEntHas(self.ent, Comp);
    }
};

fn StageLabelOffset(comptime _label: @TypeOf(.enum_literal), comptime f: anytype, comptime offset: comptime_int) type {
    return struct {
        comptime f: @TypeOf(f) = f,
        comptime label: @TypeOf(.enum_literal) = _label,
        comptime offset: comptime_int = offset,
    };
}

pub fn stageLabelOffset(comptime _label: @TypeOf(.enum_literal), comptime f: anytype, comptime offset: comptime_int) StageLabelOffset(_label, f, offset) {
    return .{};
}

pub fn before(comptime _label: @TypeOf(.enum_literal), comptime f: anytype) StageLabelOffset(_label, f, -1) {
    return .{};
}

pub fn label(comptime _label: @TypeOf(.enum_literal), comptime f: anytype) StageLabelOffset(_label, f, 0) {
    return .{};
}

pub fn after(comptime _label: @TypeOf(.enum_literal), comptime f: anytype) StageLabelOffset(_label, f, 1) {
    return .{};
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

pub fn Added(comptime T: type) type {
    return struct {
        pub const QueryAdded: type = T;
    };
}

pub fn Removed(comptime T: type) type {
    return struct {
        pub const QueryRemoved: type = T;
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
