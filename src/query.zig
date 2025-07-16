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
/// Also allows options which restrict the query without actually collecting the entities
/// that fit the restriction, such as `.{ Transform, With(Player) }`
pub fn Query(comptime query_types: anytype) type {
    return struct {
        const Self = @This();

        pub const IsQueryType = {};

        pub const has_entities: bool = blk: {
            for (query_types) |QT| {
                if (QT == Entity) break :blk true;
            }
            break :blk false;
        };

        const types = classifyTypes(query_types);
        pub const req_types = types.required;
        pub const opt_types = types.optional;
        pub const with_types = types.with;
        pub const without_types = types.without;

        comp_ptrs: [req_types.types.len][]*anyopaque = undefined,
        opt_ptrs: [opt_types.types.len][]?*anyopaque = undefined,
        entities: if (has_entities) []Entity else void = undefined,
        len: usize = 0,

        pub fn init(alloc: std.mem.Allocator, list_len: usize) std.mem.Allocator.Error!Self {
            var self = Self{
                .comp_ptrs = undefined,
                .opt_ptrs = undefined,
            };

            self.entities = if (comptime has_entities) try alloc.alloc(Entity, list_len) else {};
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
            errdefer for (self.opt_ptrs[0..last_inited_opt_slice]) |o| {
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
        pub fn items(self: *const Self, comptime T: type) []const Single(T) {
            if (comptime T == Entity) return self.entities[0..self.len];

            if (comptime req_types.indexOf(T)) |comp_idx| {
                return @ptrCast(self.comp_ptrs[comp_idx][0..self.len]);
            } else if (comptime opt_types.indexOf(UnwrapOpt(T))) |comp_idx| {
                return @ptrCast(self.opt_ptrs[comp_idx][0..self.len]);
            }

            @compileError(std.fmt.comptimePrint("There is no type {} in query", .{T}));
        }

        /// Asserts there is only one item in the query and
        /// returns a single pointer to the type at the given index
        pub fn single(self: *const Self, comptime T: type) Single(T) {
            std.debug.assert(self.len == 1);
            return self.first(T);
        }

        /// Asserts there are zero or one items in the query,
        /// returns null if the query collected 0 items
        pub fn singleOrNull(self: *const Self, comptime T: type) ?Single(T) {
            std.debug.assert(self.len <= 1);
            return self.firstOrNull(T);
        }

        pub fn first(self: *const Self, comptime T: type) Single(T) {
            return self.items(T)[0];
        }

        pub fn firstOrNull(self: *const Self, comptime T: type) ?Single(T) {
            if (self.len == 0) return null;
            return self.items(T)[0];
        }

        fn UnwrapOpt(comptime T: type) type {
            if (comptime @typeInfo(T) == .optional) return std.meta.Child(T);
            return T;
        }

        fn Single(comptime T: type) type {
            if (T == Entity) return Entity;
            if (comptime @typeInfo(T) == .optional) return ?*UnwrapOpt(T);
            return *T;
        }
    };
}

fn classifyTypes(comptime query_types: anytype) struct {
    required: TypeMap,
    optional: TypeMap,
    with: TypeMap,
    without: TypeMap,
} {
    var required: TypeMap = .{};
    var optional: TypeMap = .{};
    var with: TypeMap = .{};
    var without: TypeMap = .{};

    for (query_types) |T| {
        if (T == Entity) continue;

        switch (@typeInfo(T)) {
            .optional => |opt| optional.append(opt.child),
            .@"struct" => str: {
                if (@hasDecl(T, "QueryWith")) {
                    with.append(T.QueryWith);
                    break :str;
                } else if (@hasDecl(T, "QueryWithout")) {
                    without.append(T.QueryWithout);
                    break :str;
                }

                required.append(T);
            },
            else => |t| @compileError(std.fmt.comptimePrint("Type in query cannot be of type {}", .{@tagName(t)})),
        }
    }

    return .{
        .required = required,
        .optional = optional,
        .with = with,
        .without = without,
    };
}

/// A query modifier asserting the entity has a component of type `T`
/// without actually collecting it in the query
pub fn With(comptime T: type) type {
    return struct {
        pub const QueryWith = T;
    };
}

/// A query modifier asserting the entity does __not__ have a component of type `T`
pub fn Without(comptime T: type) type {
    return struct {
        pub const QueryWithout = T;
    };
}
