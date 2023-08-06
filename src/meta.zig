const std = @import("std");

pub const TypeBuilder = @import("etc/type_builder.zig");
pub const TypeMap = @import("etc/type_map.zig");

pub const EnumLiteral = @TypeOf(.enum_literal);

pub fn canReturnError(comptime Fn: type) bool {
    comptime return @typeInfo(@typeInfo(Fn).Fn.return_type.?) == .ErrorUnion;
}

pub const MemberFnType = enum {
    by_value,
    by_ptr,
    by_const_ptr,
    non_member,
};

pub fn memberFnType(comptime Container: type, comptime Fn: anytype) MemberFnType {
    const params = @typeInfo(@TypeOf(Fn)).Fn.params;
    if (comptime params.len == 0) return false;

    const Param0 = params[0].type orelse return false;

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

pub fn DerefType(comptime T: type) type {
    if (comptime std.meta.trait.isSingleItemPtr(T)) return std.meta.Child(T);
    return T;
}

pub fn ReturnType(comptime f: anytype) type {
    return @typeInfo(@TypeOf(f)).Fn.return_type.?;
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
