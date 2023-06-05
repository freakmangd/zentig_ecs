const std = @import("std");

pub fn canReturnError(comptime Fn: type) bool {
    return comptime std.meta.trait.is(.ErrorUnion)(@typeInfo(Fn).Fn.return_type.?);
}

pub fn DerefType(comptime T: type) type {
    if (comptime std.meta.trait.isSingleItemPtr(T)) return std.meta.Child(T);
    return T;
}

/// Get the element type of a MultiArrayList, used internally
pub fn MultiArrayListElem(comptime T: type) type {
    return @typeInfo(@TypeOf(T.pop)).Fn.return_type.?;
}

/// Get the element type of an ArrayHashMap, used internally
pub fn ArrayHashMapElem(comptime T: type) type {
    return @typeInfo(T.KV).Struct.fields[1].type;
}

const MemberFnType = enum {
    by_value,
    by_ptr,
    by_const_ptr,
    non_member,
};

pub fn isMemberFn(comptime Container: type, comptime Fn: anytype) MemberFnType {
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
