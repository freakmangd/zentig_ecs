const std = @import("std");
const Entity = @import("ecs.zig").Entity;
const TypeBuilder = @import("type_builder.zig");
const TypeMap = @import("type_map.zig");

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

        // remove entites from query types
        const types_tuple = blk: {
            var req: TypeMap = .{};
            var opt: TypeMap = .{};
            var r_utps: []const TypeMap.UniqueTypePtr = &.{};
            var o_utps: []const TypeMap.UniqueTypePtr = &.{};
            var is_opt = [_]bool{false} ** query_types_raw.len;

            for (query_types_raw, 0..) |QT, i| {
                if (QT == Entity) continue;

                if (@typeInfo(QT) == .Optional) {
                    if (opt.has(std.meta.Child(QT))) @compileError("Cannot use the same type twice in a Query.");
                    opt.append(std.meta.Child(QT));
                    o_utps = o_utps ++ [_]TypeMap.UniqueTypePtr{TypeMap.uniqueTypePtr(std.meta.Child(QT))};
                    is_opt[i] = true;
                } else {
                    if (req.has(QT)) @compileError("Cannot use the same type twice in a Query.");
                    req.append(QT);
                    r_utps = r_utps ++ [_]TypeMap.UniqueTypePtr{TypeMap.uniqueTypePtr(QT)};
                }
            }

            if (req.types.len == 0 and opt.types.len > 0) @compileError("Cannot have a query for only optional types.");
            break :blk .{ req, r_utps, opt, o_utps, is_opt };
        };
        pub const req_types = types_tuple[0];
        pub const req_utps = types_tuple[1];
        pub const opt_types = types_tuple[2];
        pub const opt_utps = types_tuple[3];
        pub const is_optional = types_tuple[4];

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

        pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
            for (self.comp_ptrs) |comp| alloc.free(comp);
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
        pub fn items(self: *const Self, comptime idx: usize) Items(idx) {
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
        pub fn single(self: *const Self, comptime idx: usize) Single(idx) {
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

        pub fn first(self: *const Self, comptime idx: usize) Single(idx) {
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
            if (comptime query_types_raw[idx] == Entity) return Entity;
            if (comptime @typeInfo(query_types_raw[idx]) == .Optional) return ?*UnwrapOpt(query_types_raw[idx]);
            return *query_types_raw[idx];
        }
    };
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
