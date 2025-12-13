const std = @import("std");
const util = @import("../util.zig");

pub const TypeBuilder = @import("type_builder.zig");
pub const TypeMap = @import("type_map.zig").TypeMap;
pub const TypeSet = TypeMap(void);

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
pub fn memberFnTypeByName(comptime Container: type, comptime fn_name: []const u8) MemberFnType {
    if (!@hasDecl(Container, fn_name)) util.compileError("Function `{s}` is not part of the `{s}` namespace.", .{ fn_name, @typeName(Container) });
    return memberFnType(Container, @field(Container, fn_name));
}

pub fn memberFnType(comptime Container: type, comptime Func: anytype) MemberFnType {
    const params = @typeInfo(Func).@"fn".params;
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

    var field_names_buffer: [field_count][]const u8 = undefined;
    var field_names: std.ArrayList([]const u8) = .initBuffer(&field_names_buffer);

    var field_types_buffer: [field_count]type = undefined;
    var field_types: std.ArrayList(type) = .initBuffer(&field_types_buffer);

    var field_attrs_buffer: [field_count]std.builtin.Type.StructField.Attributes = undefined;
    var field_attrs: std.ArrayList(std.builtin.Type.StructField.Attributes) = .initBuffer(&field_attrs_buffer);

    for (types) |T| {
        field_names.appendSliceAssumeCapacity(std.meta.fieldNames(T));

        for (@typeInfo(T).@"struct".fields) |field| {
            field_types.appendAssumeCapacity(field.type);
            field_attrs.appendAssumeCapacity(.{
                .default_value_ptr = field.default_value_ptr,
                .@"comptime" = field.is_comptime,
                .@"align" = field.alignment,
            });
        }
    }

    return @Struct(.auto, null, &field_names_buffer, &field_types_buffer, &field_attrs_buffer);
}

test CombineStructTypes {
    const A = struct { a: i32, b: i16 };
    const B = struct { c: f32, d: f16 };
    const C = CombineStructTypes(&.{ A, B });

    try std.testing.expectEqualDeep(std.meta.fieldNames(C), &[_][]const u8{ "a", "b", "c", "d" });
    try std.testing.expectEqual(i32, @FieldType(C, "a"));
    try std.testing.expectEqual(i16, @FieldType(C, "b"));
    try std.testing.expectEqual(f32, @FieldType(C, "c"));
    try std.testing.expectEqual(f16, @FieldType(C, "d"));
}

pub fn CombineEnumTypes(comptime types: []const type) type {
    var field_count: usize = 0;
    var is_exhaustive = true;

    for (types) |T| {
        if (!@typeInfo(T).@"enum".is_exhaustive) is_exhaustive = false;
        field_count += @typeInfo(T).@"enum".fields.len;
    }

    var field_names_buffer: [field_count][]const u8 = &.{};
    var field_names: std.ArrayList([]const u8) = .initBuffer(&field_names_buffer);
    for (types) |T| field_names.appendAssumeCapacity(std.meta.fieldNames(T));

    const TagInt = std.math.IntFittingRange(0, field_count);

    return @Enum(
        TagInt,
        if (is_exhaustive) .exhaustive else .nonexhaustive,
        &field_names_buffer,
        &std.simd.iota(TagInt, field_count),
    );
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

pub fn prettyPrint(comptime T: type) *const [std.fmt.count(prettyPrintFmt(T), prettyPrintArgs(T)):0]u8 {
    return std.fmt.comptimePrint(prettyPrintFmt(T), prettyPrintArgs(T));
}

fn prettyPrintFmt(comptime T: type) []const u8 {
    var fmt: []const u8 = "struct {{";
    inline for (std.meta.fields(T)) |_| {
        fmt = fmt ++ "{s}: {s} ";
    }
    return fmt ++ "}},";
}

fn PrettyPrintArgs(comptime T: type) type {
    return std.meta.Tuple(&[_]type{[]const u8} ** (std.meta.fields(T).len * 2));
}

fn prettyPrintArgs(comptime T: type) PrettyPrintArgs(T) {
    var out: PrettyPrintArgs(T) = undefined;

    const MAX_DEPTH = 10;
    comptime var i: usize = 0;
    const out_fields = std.meta.fields(T);
    inline for (out_fields) |field| {
        out[i] = field.name;
        out[i + 1] = if (util.isContainer(field.type) and i / 2 < MAX_DEPTH) prettyPrint(field.type) else @typeName(field.type);
        i += 2;
    }

    return out;
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
