const std = @import("std");
const ztg = @import("init.zig");
const TypeBuilder = @import("type_builder.zig");
const TypeMap = @import("type_map.zig");

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

/// Takes list of types: `&.{ Player, Position, Sprite }` and returns
/// an object that can be used to iterate through entities that have all of those components
/// if one of the types is `Entity` (`usize`) then it will also have
/// the entity those components are attatched to.
pub fn Query(comptime query_types_raw: []const type) type {
    return QueryOpts(query_types_raw, &.{});
}

/// Takes list of types: `&.{ Player, Position, Sprite }` and returns
/// an object that can be used to iterate through entities that have all of those components
/// if one of the types is `Entity` (`usize`) then it will also have
/// the entity those components are attatched to.
///
/// Also allows options which restrict the query without actually collecting the entities
/// that fit the restriction, such as `&.{ Transform }, &.{ With(Player) }`
pub fn QueryOpts(comptime query_types_raw: []const type, comptime options: []const type) type {
    var tm = TypeMap{};
    inline for (query_types_raw) |QT| {
        if (tm.has(QT)) @compileError("Cannot use the same type twice in a Query.");
        tm.append(QT);
    }

    var tm_opts = TypeMap{};
    inline for (options) |QT| {
        if (tm_opts.has(QT)) @compileError("Cannot use the same type twice in a Query.");
        tm_opts.append(QT);
    }

    return struct {
        const Self = @This();

        pub const OptionsType = options;

        pub const type_utps = blk: {
            var out: [query_types.len]TypeMap.UniqueTypePtr = undefined;
            for (&out, query_types) |*o, QT| {
                if (QT == Entity) continue;
                o.* = TypeMap.uniqueTypePtr(QT);
            }
            break :blk out;
        };

        const entity_type_idx = blk: {
            for (query_types_raw, 0..) |QT, i| {
                if (QT == Entity) break :blk i;
            }
            break :blk -1;
        };

        pub const has_entities = blk: {
            for (query_types_raw) |QT| {
                if (QT == Entity) break :blk true;
            }
            break :blk false;
        };

        // remove entites from query types
        pub const query_types = blk: {
            if (has_entities) {
                var qt_tb = TypeBuilder.new(true, .Auto);
                comptime var i: usize = 0;
                for (query_types_raw) |QTR| {
                    if (QTR != Entity) {
                        qt_tb.addTupleField(i, type, &QTR);
                        i += 1;
                    }
                }
                break :blk qt_tb.Build(){};
            }
            break :blk query_types_raw;
        };

        comp_ptrs: [query_types.len][]*anyopaque,
        entities: if (has_entities) []Entity else void,

        pub fn init(alloc: std.mem.Allocator, list_len: usize) !Self {
            var self = Self{
                .entities = if (comptime has_entities) try alloc.alloc(Entity, list_len) else void{},
                .comp_ptrs = undefined,
            };

            for (&self.comp_ptrs) |*o| o.* = try alloc.alloc(*anyopaque, list_len);
            return self;
        }

        pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
            for (self.comp_ptrs) |comp| alloc.free(comp);
            if (has_entities) alloc.free(self.entities);
        }

        pub fn items(self: *const Self, comptime idx: usize) Items(idx) {
            if (comptime query_types_raw[idx] == Entity) return self.entities;
            const idx_adjusted = if (comptime has_entities and idx >= entity_type_idx) idx - 1 else idx;
            return @ptrCast(Items(idx), self.comp_ptrs[idx_adjusted]);
        }

        pub inline fn len(self: *const Self) usize {
            if (comptime query_types.len == 0) return 0;
            return self.comp_ptrs[0].len;
        }

        fn Items(comptime idx: usize) type {
            if (comptime query_types_raw[idx] == Entity) return []const Entity;
            const idx_adjusted = if (has_entities and idx >= entity_type_idx) idx - 1 else idx;
            return []const *query_types[idx_adjusted];
        }
    };
}

fn QueryOld(comptime q: anytype, comptime options: anytype) type {
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

pub fn MinEntInt(comptime max: usize) type {
    return std.meta.Int(.unsigned, @typeInfo(std.math.IntFittingRange(0, max)).Int.bits + 1);
}

pub const OnCrashFn = fn (ztg.Commands, CrashReason) anyerror!Status;

pub const CrashReason = enum {
    hit_ent_limit,
};

pub const Status = enum {
    failure,
    success,
};
