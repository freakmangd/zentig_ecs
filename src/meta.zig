const std = @import("std");

pub const TypeBuilder = @import("etc/type_builder.zig");
pub const TypeMap = @import("etc/type_map.zig");

pub fn canReturnError(comptime Fn: type) bool {
    return comptime @typeInfo(@typeInfo(Fn).Fn.return_type.?) == .ErrorUnion;
}

const MemberFnType = enum {
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

pub const UniqueTypePtr = *const opaque {};
pub const uniqueTypePtr = struct {
    inline fn typeId(comptime T: type) UniqueTypePtr {
        comptime return typeIdImpl(T);
    }
    inline fn typeIdImpl(comptime T: type) UniqueTypePtr {
        _ = T;
        const gen = struct {
            var id: u1 = undefined;
        };
        return @ptrCast(&gen.id);
    }
}.typeId;

//pub const UniqueTypePtr = *const anyopaque;
//pub fn uniqueTypePtr(comptime T: type) UniqueTypePtr {
//    return @typeName(T);
//}

//pub const UniqueTypePtr = u64;
//var id_counter: u64 = 0;
//pub fn uniqueTypePtr(comptime T: type) UniqueTypePtr {
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
