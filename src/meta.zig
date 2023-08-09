const std = @import("std");

pub const TypeBuilder = @import("etc/type_builder.zig");
pub const TypeMap = @import("etc/type_map.zig");

pub const EnumLiteral = @TypeOf(.enum_literal);

/// Returns whether a function type can return an error
pub fn canReturnError(comptime Fn: type) bool {
    comptime return @typeInfo(@typeInfo(Fn).Fn.return_type.?) == .ErrorUnion;
}

pub const MemberFnType = enum {
    by_value,
    by_ptr,
    by_const_ptr,
    non_member,
};

/// Returns whether a function is a member function
/// and whether it takes by value, ptr, or const ptr
pub fn memberFnType(comptime Container: type, comptime fn_name: []const u8) MemberFnType {
    if (!@hasDecl(Container, fn_name)) @compileError("Function " ++ fn_name ++ " is not part of the " ++ @typeName(Container) ++ " namespace.");

    const params = @typeInfo(@TypeOf(@field(Container, fn_name))).Fn.params;
    if (comptime params.len == 0) return .non_member;

    const Param0 = params[0].type orelse return .non_member;

    if (DerefType(Param0) == Container) {
        if (std.meta.trait.isConstPtr(Param0)) {
            return .by_const_ptr;
        } else if (std.meta.trait.isSingleItemPtr(Param0)) {
            return .by_ptr;
        } else {
            return .by_value;
        }
    }
    return .non_member;
}

/// If `T` is a Pointer type this function returns the child, otherwise returns `T`
pub fn DerefType(comptime T: type) type {
    if (comptime std.meta.trait.isSingleItemPtr(T)) return std.meta.Child(T);
    return T;
}

/// Returns the return type of the function f
pub fn ReturnType(comptime f: anytype) type {
    return @typeInfo(@TypeOf(f)).Fn.return_type.?;
}

/// A structure for making lists of comptime only objects.
/// To be only used at comptime.
pub fn ComptimeList(comptime T: type) type {
    return struct {
        const Self = @This();

        items: []const T = &.{},

        pub fn fromSlice(comptime items: []const T) Self {
            return .{ .items = items };
        }

        pub fn append(comptime self: *Self, comptime t: T) void {
            self.items = self.items ++ .{t};
        }

        pub fn insert(comptime self: *Self, comptime index: usize, comptime t: T) void {
            self.items = self.items[0..index] ++ .{t} ++ self.items[index..];
        }

        pub fn replace(comptime self: *Self, comptime index: usize, comptime t: T) void {
            var items: [self.items.len]T = undefined;
            @memcpy(&items, self.items);

            items[index] = t;

            self.items = &items;
        }
    };
}

test ComptimeList {
    const list = comptime blk: {
        var list = ComptimeList(usize).fromSlice(&.{ 1, 2, 3 });
        list.append(4);
        list.replace(0, 5);
        break :blk list;
    };
    try std.testing.expectEqualSlices(usize, &.{ 5, 2, 3, 4 }, list.items);
}

pub const Utp = *const opaque {};
pub const utpOf = struct {
    inline fn utpOf(comptime T: type) Utp {
        comptime return utpOfImpl(T);
    }
    inline fn utpOfImpl(comptime T: type) Utp {
        _ = T;
        const gen = struct {
            var id: u1 = undefined;
        };
        return @ptrCast(&gen.id);
    }
}.utpOf;

//pub const UniqueTypePtr = *const anyopaque;
//pub fn uniqueTypePtr(comptime T: type) UniqueTypePtr {
//    return @typeName(T);
//}

//pub const TypeId = u64;
//var id_counter: u64 = 0;
//pub fn typeId(comptime T: type) u64 {
//    _ = T;
//    const static = struct {
//        var id: ?u64 = null;
//    };
//    const result = static.id orelse blk: {
//        static.id = id_counter;
//        id_counter += 1;
//        break :blk static.id.?;
//    };
//    return result;
//}
