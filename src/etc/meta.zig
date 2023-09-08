const std = @import("std");
const util = @import("../util.zig");

pub const TypeBuilder = @import("type_builder.zig");
pub const TypeMap = @import("type_map.zig");

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
    if (!@hasDecl(Container, fn_name)) util.compileError("Function `{s}` is not part of the `{s}` namespace.", .{ fn_name, @typeName(Container) });

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

/// Combines two struct types by their fields,
/// returning a new type that contains all of the fields
/// of the types passed in.
///
/// Example:
/// ```zig
/// const A = struct { a: i32, b: i16 };
/// const B = struct { c: f32, d: f16 };
///
/// const C = CombineStructTypes(&.{ A, B });
/// // C == struct { a: i32, b: i16, c: f32, d: f16 };
/// ```
pub fn CombineStructTypes(comptime types: []const type) type {
    var field_count: usize = 0;

    for (types) |T| {
        field_count += @typeInfo(T).Struct.fields.len;
    }

    var field_types: [field_count]std.builtin.Type.StructField = undefined;
    var field_types_i: usize = 0;

    for (types) |T| {
        for (std.meta.fields(T)) |field| {
            field_types[field_types_i] = field;
            field_types_i += 1;
        }
    }

    return @Type(.{ .Struct = std.builtin.Type.Struct{
        .fields = &field_types,
        .decls = &.{},
        .layout = .Auto,
        .is_tuple = false,
    } });
}

test CombineStructTypes {
    const A = struct { a: i32, b: i16 };
    const B = struct { c: f32, d: f16 };
    const C = CombineStructTypes(&.{ A, B });

    try std.testing.expectEqualDeep(std.meta.fieldNames(C), &.{ "a", "b", "c", "d" });
    try std.testing.expectEqual(i32, std.meta.FieldType(C, .a));
    try std.testing.expectEqual(i16, std.meta.FieldType(C, .b));
    try std.testing.expectEqual(f32, std.meta.FieldType(C, .c));
    try std.testing.expectEqual(f16, std.meta.FieldType(C, .d));
}

fn DeclsToTuple(comptime T: type) type {
    var types: [std.meta.declarations(T).len]type = undefined;
    for (&types, std.meta.declarations(T)) |*o, decl| {
        o.* = @TypeOf(@field(T, decl.name));
    }
    return std.meta.Tuple(&types);
}

pub fn declsToTuple(comptime T: type) DeclsToTuple(T) {
    var out: DeclsToTuple(T) = undefined;
    for (std.meta.declarations(T), 0..) |decl, i| {
        out[i] = @field(T, decl.name);
    }
    return out;
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
