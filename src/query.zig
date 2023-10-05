const std = @import("std");
const ztg = @import("init.zig");

const meta = ztg.meta;
const Entity = ztg.Entity;
const TypeMap = ztg.meta.TypeMap;

/// Takes tuple of types: `.{ Player, Position, Sprite }` and returns
/// an object that can be used to iterate through entities that have
/// all of those components. If one of the types is `Entity` (`usize`)
/// then it will also have the entity those components are attatched to.
///
/// Used in systems like so:
/// ```zig
/// pub fn mySystem(q: Query(.{ Player, Transform, Score })) void {}
/// ```
pub fn Query(comptime query_types: anytype) type {
    return QueryOpts(query_types, .{});
}

/// Takes tuple of types: `.{ Player, Position, Sprite }` and returns
/// an object that can be used to iterate through entities that have
/// all of those components. If one of the types is `Entity` (`usize`)
/// then it will also have the entity those components are attatched to.
///
/// Also allows options which restrict the query without actually collecting the entities
/// that fit the restriction, such as `.{ Transform }, .{ With(Player) }`
///
/// Used in systems like so:
/// ```zig
/// pub fn mySystem(q: QueryOpts(.{ Transform, Speed }, .{ Without(Enemy) })) void {}
/// ```
pub fn QueryOpts(comptime query_types: anytype, comptime _options: anytype) type {
    //comptime assertOkQuery(query_types_raw, _options);

    return struct {
        const Self = @This();

        pub const IsQueryType = true;
        pub const options = _options;

        pub const has_entities: bool = blk: {
            for (query_types) |QT| {
                if (QT == Entity) break :blk true;
            }
            break :blk false;
        };

        const raw_types_info = getRawTypesInfo(query_types);
        pub const req_types = raw_types_info[0];
        pub const opt_types = raw_types_info[1];

        const options_info = getOptionsInfo(options);
        pub const with_types = options_info[0];
        pub const without_types = options_info[1];

        comp_ptrs: [req_types.types.len][]*anyopaque = undefined,
        opt_ptrs: [opt_types.types.len][]?*anyopaque = undefined,
        entities: if (has_entities) []Entity else void = undefined,
        len: usize = 0,

        pub fn init(alloc: std.mem.Allocator, list_len: usize) !Self {
            var self = Self{
                .comp_ptrs = undefined,
                .opt_ptrs = undefined,
            };

            self.entities = if (comptime has_entities) try alloc.alloc(Entity, list_len) else void{};
            errdefer if (comptime has_entities) alloc.free(self.entities);

            var last_inited_slice: usize = 0;
            errdefer for (self.comp_ptrs[0..last_inited_slice]) |o| {
                alloc.free(o);
            };

            for (&self.comp_ptrs) |*o| {
                o.* = try alloc.alloc(*anyopaque, list_len);
                last_inited_slice += 1;
            }

            var last_inited_opt_slice: usize = 0;
            errdefer for (self.comp_ptrs[0..last_inited_slice]) |o| {
                alloc.free(o);
            };

            for (&self.opt_ptrs) |*o| {
                o.* = try alloc.alloc(?*anyopaque, list_len);
                @memset(o.*, null);
                last_inited_opt_slice += 1;
            }

            return self;
        }

        pub fn deinit(self: *const Self, alloc: std.mem.Allocator) void {
            for (self.comp_ptrs) |ptrs| alloc.free(ptrs);
            for (self.opt_ptrs) |ptrs| alloc.free(ptrs);
            if (has_entities) alloc.free(self.entities);
        }

        /// Returns a slice of pointers to the queried components
        ///
        /// Example:
        /// ```zig
        /// const q = world.query(.{ Transform, Image });
        ///
        /// for (q.items(0), q.items(1)) |tr, img| {
        ///   img.drawAt(tr.pos);
        /// }
        /// ```
        pub inline fn items(self: *const Self, comptime idx: usize) Items(idx) {
            const OutChildType = query_types[idx];

            if (comptime OutChildType == Entity) return self.entities[0..self.len];

            if (comptime req_types.indexOf(OutChildType)) |comp_idx| {
                return @ptrCast(self.comp_ptrs[comp_idx][0..self.len]);
            } else if (comptime opt_types.indexOf(UnwrapOpt(OutChildType))) |comp_idx| {
                return @ptrCast(self.opt_ptrs[comp_idx][0..self.len]);
            }

            @compileError(std.fmt.comptimePrint("Index {} could not be resolved", .{idx}));
        }

        /// Asserts there is only one item in the query and
        /// returns a single pointer to the type at the given index
        ///
        /// Example:
        /// ```zig
        /// const q = world.queryOpts(.{ Transform }, .{ With(Player) });
        ///
        /// const tr = q.single(0);
        /// std.debug.print("Player is located at {d}, {d}.", .{ tr.pos.x, tr.pos.y });
        /// ```
        pub inline fn single(self: *const Self, comptime idx: usize) Single(idx) {
            std.debug.assert(self.len == 1);
            return self.first(idx);
        }

        pub inline fn first(self: *const Self, comptime idx: usize) Single(idx) {
            return self.items(idx)[0];
        }

        fn UnwrapOpt(comptime T: type) type {
            if (comptime @typeInfo(T) == .Optional) return std.meta.Child(T);
            return T;
        }

        fn Items(comptime idx: usize) type {
            return []Single(idx);
        }

        fn Single(comptime idx: usize) type {
            if (comptime idx >= query_types.len) @compileError("Index for query outside of query types range.");
            if (comptime query_types[idx] == Entity) return Entity;
            if (comptime @typeInfo(query_types[idx]) == .Optional) return ?*UnwrapOpt(query_types[idx]);
            return *query_types[idx];
        }
    };
}

fn getRawTypesInfo(comptime query_types: anytype) struct { TypeMap, TypeMap } {
    var req: TypeMap = .{};
    var opt: TypeMap = .{};

    for (query_types) |QT| {
        // remove entites from query types
        if (QT == Entity) continue;

        if (@typeInfo(QT) == .Optional) {
            if (opt.has(std.meta.Child(QT))) @compileError("Cannot use the same type twice in a Query.");
            opt.append(std.meta.Child(QT));
        } else {
            if (req.has(QT)) @compileError("Cannot use the same type twice in a Query.");
            req.append(QT);
        }
    }

    return .{ req, opt };
}

fn getOptionsInfo(comptime options: anytype) struct { TypeMap, TypeMap } {
    var with: TypeMap = .{};
    var without: TypeMap = .{};

    for (options) |OT| {
        if (@hasDecl(OT, "QueryWith")) {
            with.append(OT.QueryWith);
        } else if (@hasDecl(OT, "QueryWithout")) {
            without.append(OT.QueryWithout);
        }
    }

    return .{ with, without };
}

fn assertOkQuery(comptime query_types_raw: anytype, comptime options: anytype) void {
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
}

//fn Query(comptime q: anytype, comptime options: anytype) type {
//    if (comptime q.len >= 158) @compileError("Query has too many items.");
//
//    var tm = TypeMap{};
//    var tb = TypeBuilder.init(false, .Auto);
//
//    inline for (q, 0..) |Q, i| {
//        tb.addField(std.fmt.comptimePrint("{c}", .{@intCast(u8, 97 + i)}), if (Q == Entity) Entity else *Q, null);
//        if (tm.has(Q)) @compileError("Cannot use the same type twice in a query.");
//        tm.append(Q);
//    }
//
//    tb.addField("QueryType", @TypeOf(q), &q);
//    tb.addField("OptionsType", @TypeOf(options), &options);
//    return std.MultiArrayList(tb.Build());
//}
