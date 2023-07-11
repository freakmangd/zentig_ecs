const std = @import("std");

pub const TypeBuilder = @import("type_builder.zig");
pub const TypeMap = @import("type_map.zig");

pub fn canReturnError(comptime Fn: type) bool {
    return comptime std.meta.trait.is(.ErrorUnion)(@typeInfo(Fn).Fn.return_type.?);
}

pub fn DerefType(comptime T: type) type {
    if (comptime std.meta.trait.isSingleItemPtr(T)) return std.meta.Child(T);
    return T;
}

/// Get the element type of a MultiArrayList
pub fn MultiArrayListElem(comptime T: type) type {
    return @typeInfo(@TypeOf(T.pop)).Fn.return_type.?;
}

/// Get the element type of an ArrayHashMap
pub fn ArrayHashMapElem(comptime T: type) type {
    return @typeInfo(T.KV).Struct.fields[1].type;
}

pub fn MinEntInt(comptime max: usize) type {
    return std.meta.Int(.unsigned, @typeInfo(std.math.IntFittingRange(0, max)).Int.bits + 1);
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

pub fn convertFieldToF32(obj: anytype, comptime field_name: []const u8, default: f32) f32 {
    const O = @TypeOf(obj);
    const fi = std.meta.fieldIndex(O, field_name) orelse return default;

    const FieldType = std.meta.fields(O)[fi].type;
    switch (@typeInfo(FieldType)) {
        .Int => return @floatFromInt(@field(obj, field_name)),
        .Float => return @floatCast(@field(obj, field_name)),
        else => @compileError("Cannot convert type " ++ @typeName(FieldType) ++ " to f32."),
    }
}
