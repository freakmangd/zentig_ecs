const std = @import("std");
const ztg = @import("init.zig");

const meta = ztg.meta;
const Entity = ztg.Entity;
const TypeMap = ztg.meta.TypeMap;

/// Takes tuple of types: `.{ Player, Position, Sprite }` and returns
/// an object that can be used to iterate through entities that have all of those components
/// if one of the types is `Entity` (`usize`) then it will also have
/// the entity those components are attatched to.
pub fn Query(comptime query_types_raw: anytype) type {
    return QueryOpts(query_types_raw, .{});
}

/// Takes tuple of types: `.{ Player, Position, Sprite }` and returns
/// an object that can be used to iterate through entities that have all of those components
/// if one of the types is `Entity` (`usize`) then it will also have
/// the entity those components are attatched to.
///
/// Also allows options which restrict the query without actually collecting the entities
/// that fit the restriction, such as `.{ Transform }, .{ With(Player) }`
pub fn QueryOpts(comptime query_types_raw: anytype, comptime _options: anytype) type {
    //comptime assertOkQuery(query_types_raw, _options);

    return struct {
        const Self = @This();

        pub const IsQueryType = true;
        pub const options = _options;

        pub const has_entities: bool = blk: {
            for (query_types_raw) |QT| {
                if (QT == Entity) break :blk true;
            }
            break :blk false;
        };

        const types_tuple = getRawTypesInfo(query_types_raw);
        pub const req_types = types_tuple[0];
        pub const req_utps = types_tuple[1];
        pub const opt_types = types_tuple[2];
        pub const opt_utps = types_tuple[3];
        pub const is_optional = types_tuple[4];

        const options_tuple = getOptionsInfo(options);
        pub const with_utps = options_tuple[0];
        pub const without_utps = options_tuple[1];

        comp_ptrs: [req_types.types.len][]*anyopaque,
        opt_ptrs: [opt_types.types.len][]?*anyopaque,
        entities: if (has_entities) []Entity else void,
        len: usize = 0,

        pub fn init(alloc: std.mem.Allocator, list_len: usize) !Self {
            var self = Self{
                .entities = if (comptime has_entities) try alloc.alloc(Entity, list_len) else void{},
                .comp_ptrs = undefined,
                .opt_ptrs = undefined,
            };

            for (&self.comp_ptrs) |*o| {
                o.* = try alloc.alloc(*anyopaque, list_len);
            }
            for (&self.opt_ptrs) |*o| {
                o.* = try alloc.alloc(?*anyopaque, list_len);
                for (o.*) |*v| {
                    v.* = null;
                }
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
            const OutChildType = query_types_raw[idx];

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
            const OutChildType = query_types_raw[idx];

            if (comptime OutChildType == Entity) {
                std.debug.assert(self.entities.len == 1);
                return self.entities[0];
            }

            if (comptime req_types.indexOf(OutChildType)) |comp_idx| {
                std.debug.assert(self.comp_ptrs[comp_idx].len == 1);
                return @ptrCast(@alignCast(self.comp_ptrs[comp_idx][0]));
            } else if (comptime opt_types.indexOf(UnwrapOpt(OutChildType))) |comp_idx| {
                std.debug.assert(self.opt_ptrs[comp_idx].len == 1);
                return @ptrCast(@alignCast(self.opt_ptrs[comp_idx][0]));
            }

            @compileError(std.fmt.comptimePrint("Index {} could not be resolved", .{idx}));
        }

        pub inline fn first(self: *const Self, comptime idx: usize) Single(idx) {
            const OutChildType = query_types_raw[idx];

            if (comptime OutChildType == Entity) return self.entities[0];

            if (comptime req_types.indexOf(OutChildType)) |comp_idx| {
                return @ptrCast(@alignCast(self.comp_ptrs[comp_idx][0]));
            } else if (comptime opt_types.indexOf(UnwrapOpt(OutChildType))) |comp_idx| {
                return @ptrCast(@alignCast(self.opt_ptrs[comp_idx][0]));
            }

            @compileError(std.fmt.comptimePrint("Index {} could not be resolved", .{idx}));
        }

        fn UnwrapOpt(comptime T: type) type {
            if (comptime @typeInfo(T) == .Optional) return std.meta.Child(T);
            return T;
        }

        fn Items(comptime idx: usize) type {
            return []const Single(idx);
        }

        fn Single(comptime idx: usize) type {
            if (comptime idx >= query_types_raw.len) @compileError("Index for query outside of query types range.");
            if (comptime query_types_raw[idx] == Entity) return Entity;
            if (comptime @typeInfo(query_types_raw[idx]) == .Optional) return ?*UnwrapOpt(query_types_raw[idx]);
            return *query_types_raw[idx];
        }
    };
}

fn getRawTypesInfo(comptime query_types_raw: anytype) struct {
    TypeMap,
    []const meta.UniqueTypePtr,
    TypeMap,
    []const meta.UniqueTypePtr,
    [query_types_raw.len]bool,
} {
    var req: TypeMap = .{};
    var opt: TypeMap = .{};
    var r_utps: []const meta.UniqueTypePtr = &.{};
    var o_utps: []const meta.UniqueTypePtr = &.{};
    var is_opt = [_]bool{false} ** query_types_raw.len;

    for (query_types_raw, 0..) |QT, i| {
        // remove entites from query types
        if (QT == Entity) continue;

        if (@typeInfo(QT) == .Optional) {
            if (opt.has(std.meta.Child(QT))) @compileError("Cannot use the same type twice in a Query.");
            opt.append(std.meta.Child(QT));
            o_utps = o_utps ++ [_]meta.UniqueTypePtr{meta.uniqueTypePtr(std.meta.Child(QT))};
            is_opt[i] = true;
        } else {
            if (req.has(QT)) @compileError("Cannot use the same type twice in a Query.");
            req.append(QT);
            r_utps = r_utps ++ [_]meta.UniqueTypePtr{meta.uniqueTypePtr(QT)};
        }
    }

    return .{ req, r_utps, opt, o_utps, is_opt };
}

fn getOptionsInfo(comptime options: anytype) struct { []const meta.UniqueTypePtr, []const meta.UniqueTypePtr } {
    var w_utps: []const meta.UniqueTypePtr = &.{};
    var wo_utps: []const meta.UniqueTypePtr = &.{};

    for (options) |OT| {
        if (@hasDecl(OT, "QueryWith")) {
            w_utps = w_utps ++ [_]meta.UniqueTypePtr{meta.uniqueTypePtr(OT.QueryWith)};
        } else if (@hasDecl(OT, "QueryWithout")) {
            wo_utps = wo_utps ++ [_]meta.UniqueTypePtr{meta.uniqueTypePtr(OT.QueryWithout)};
        }
    }

    return .{ w_utps, wo_utps };
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
