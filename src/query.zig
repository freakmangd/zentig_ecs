const std = @import("std");
const Entity = @import("ecs.zig").Entity;
const TypeBuilder = @import("type_builder.zig");
const TypeMap = @import("type_map.zig");

var nullptr: usize = 0;

/// Takes list of types: `&.{ Player, Position, Sprite }` and returns
/// an object that can be used to iterate through entities that have all of those components
/// if one of the types is `Entity` (`usize`) then it will also have
/// the entity those components are attatched to.
pub fn Query(comptime query_types_raw: anytype) type {
    return QueryOpts(query_types_raw, .{});
}

/// Takes list of types: `&.{ Player, Position, Sprite }` and returns
/// an object that can be used to iterate through entities that have all of those components
/// if one of the types is `Entity` (`usize`) then it will also have
/// the entity those components are attatched to.
///
/// Also allows options which restrict the query without actually collecting the entities
/// that fit the restriction, such as `&.{ Transform }, &.{ With(Player) }`
pub fn QueryOpts(comptime query_types_raw: anytype, comptime options: anytype) type {
    if (query_types_raw.len > 30) @compileError("Querying for types is limited to 30 types at a time.");

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
                var qt_tb = TypeBuilder.init(true, .Auto);
                for (query_types_raw) |QTR| {
                    if (QTR == Entity) continue;
                    qt_tb.appendTupleField(type, &QTR);
                }
                break :blk qt_tb.Build(){};
            }
            break :blk query_types_raw;
        };

        comp_ptrs: [query_types.len][]*anyopaque,
        entities: if (has_entities) []Entity else void,
        len: usize = 0,

        pub fn init(alloc: std.mem.Allocator, list_len: usize) !Self {
            var self = Self{
                .entities = if (comptime has_entities) try alloc.alloc(Entity, list_len) else void{},
                .comp_ptrs = undefined,
            };

            for (&self.comp_ptrs) |*o| {
                o.* = try alloc.alloc(*anyopaque, list_len);
            }
            return self;
        }

        pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
            for (self.comp_ptrs) |comp| alloc.free(comp);
            if (has_entities) alloc.free(self.entities);
        }

        pub fn items(self: *const Self, comptime idx: usize) Items(idx) {
            if (comptime query_types_raw[idx] == Entity) return self.entities[0..self.len];
            const idx_adjusted = if (comptime has_entities and idx >= entity_type_idx) idx - 1 else idx;
            return @ptrCast(Items(idx), self.comp_ptrs[idx_adjusted][0..self.len]);
        }

        fn Items(comptime idx: usize) type {
            if (comptime query_types_raw[idx] == Entity) return []const Entity;
            return []const *query_types_raw[idx];
        }
    };
}

fn QueryOld(comptime q: anytype, comptime options: anytype) type {
    if (comptime q.len >= 158) @compileError("Query has too many items.");

    var tm = TypeMap{};
    var tb = TypeBuilder.init(false, .Auto);

    inline for (q, 0..) |Q, i| {
        tb.addField(std.fmt.comptimePrint("{c}", .{@intCast(u8, 97 + i)}), if (Q == Entity) Entity else *Q, null);
        if (tm.has(Q)) @compileError("Cannot use the same type twice in a query.");
        tm.append(Q);
    }

    tb.addField("QueryType", @TypeOf(q), &q);
    tb.addField("OptionsType", @TypeOf(options), &options);
    return std.MultiArrayList(tb.Build());
}
