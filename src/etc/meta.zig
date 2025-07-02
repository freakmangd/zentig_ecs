const std = @import("std");
const util = @import("../util.zig");

pub const TypeBuilder = @import("type_builder.zig");
pub const TypeMap = @import("type_map.zig");

pub const EnumLiteral = @TypeOf(.enum_literal);

/// Returns whether a function type can return an error
pub fn canReturnError(comptime Fn: type) bool {
    comptime return @typeInfo(@typeInfo(Fn).@"fn".return_type.?) == .error_union;
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

    const params = @typeInfo(@TypeOf(@field(Container, fn_name))).@"fn".params;
    if (comptime params.len == 0) return .non_member;

    const Param0 = params[0].type orelse return .non_member;
    const ti = @typeInfo(Param0);

    if (DerefType(Param0) == Container) {
        if (ti == .pointer) {
            if (ti.pointer.is_const) {
                return .by_const_ptr;
            } else {
                return .by_ptr;
            }
        } else {
            return .by_value;
        }
    }
    return .non_member;
}

/// If `T` is a Pointer type this function returns the child, otherwise returns `T`
pub fn DerefType(comptime T: type) type {
    const ti = @typeInfo(T);
    if (ti == .pointer) return ti.pointer.child;
    return T;
}

/// Returns the return type of the function f
pub fn ReturnType(comptime f: anytype) type {
    return @typeInfo(@TypeOf(f)).@"fn".return_type.?;
}

/// Combines two struct types by their fields,
/// returning a new type that contains all of the fields
/// of the types passed in.
pub fn CombineStructTypes(comptime types: []const type) type {
    var field_count: usize = 0;

    for (types) |T| {
        field_count += @typeInfo(T).@"struct".fields.len;
    }

    var field_types: [field_count]std.builtin.Type.StructField = undefined;
    var field_types_i: usize = 0;

    for (types) |T| {
        for (std.meta.fields(T)) |field| {
            field_types[field_types_i] = field;
            field_types_i += 1;
        }
    }

    return @Type(.{ .@"struct" = .{
        .fields = &field_types,
        .decls = &.{},
        .layout = .auto,
        .is_tuple = false,
    } });
}

test CombineStructTypes {
    const A = struct { a: i32, b: i16 };
    const B = struct { c: f32, d: f16 };
    const C = CombineStructTypes(&.{ A, B });

    try std.testing.expectEqualDeep(std.meta.fieldNames(C), &[_][]const u8{ "a", "b", "c", "d" });
    try std.testing.expectEqual(i32, std.meta.FieldType(C, .a));
    try std.testing.expectEqual(i16, std.meta.FieldType(C, .b));
    try std.testing.expectEqual(f32, std.meta.FieldType(C, .c));
    try std.testing.expectEqual(f16, std.meta.FieldType(C, .d));
}

pub fn CombineEnumTypes(comptime types: []const type) type {
    var field_count: usize = 0;

    for (types) |T| {
        if (comptime !@typeInfo(T).@"enum".is_exhaustive) @compileError("Cannot combine enums that are non-exhaustive");
        field_count += @typeInfo(T).@"enum".fields.len;
    }

    var field_types: [field_count]std.builtin.Type.EnumField = undefined;
    var field_types_i: usize = 0;

    for (types) |T| for (std.meta.fields(T)) |field| {
        field_types[field_types_i] = std.builtin.Type.EnumField{
            .name = field.name,
            .value = field_types_i,
        };
        field_types_i += 1;
    };

    return @Type(.{ .@"enum" = std.builtin.Type.Enum{
        .fields = &field_types,
        .decls = &.{},
        .tag_type = std.math.IntFittingRange(0, field_count),
        .is_exhaustive = true,
    } });
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

pub fn checkMixin(comptime T: type, comptime Mixin: type) void {
    for (@typeInfo(Mixin).@"struct".decls) |decl| {
        if (!@hasDecl(T, decl.name) or @field(T, decl.name) != @field(Mixin, decl.name))
            @compileError("Mixin receptor " ++ @typeName(T) ++ " is missing decl " ++ decl.name);
    }
}

pub fn EnumFromLiterals(comptime literals: []const EnumLiteral) type {
    var fields: [literals.len]std.builtin.Type.EnumField = undefined;

    for (&fields, literals, 0..) |*o, lit, i| {
        o.* = std.builtin.Type.EnumField{
            .name = @tagName(lit),
            .value = i,
        };
    }

    return @Type(.{ .@"enum" = std.builtin.Type.Enum{
        .fields = &fields,
        .decls = &.{},
        .tag_type = std.math.IntFittingRange(0, literals.len),
        .is_exhaustive = true,
    } });
}

pub const Utp = *const opaque {};
pub const utpOf = struct {
    inline fn utpOf(comptime T: type) Utp {
        comptime return utpOfImpl(T);
    }
    inline fn utpOfImpl(comptime T: type) Utp {
        const gen = struct {
            var id: u1 = undefined;

            comptime {
                _ = T;
            }
        };
        return @ptrCast(&gen.id);
    }
}.utpOf;
