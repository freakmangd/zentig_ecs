const std = @import("std");
const util = @import("../util.zig");
const Type = std.builtin.Type;

const TypeBuilder = @This();

layout: Type.ContainerLayout = .auto,
backing_integer: ?type = null,
field_names: []const []const u8 = &.{},
field_types: []const type = &.{},
field_attrs: []const Type.StructField.Attributes = &.{},

pub fn initFrom(comptime T: type) TypeBuilder {
    const ti = @typeInfo(T).@"struct";

    var types: [ti.fields.len]type = undefined;
    var attrs: [ti.fields.len]Type.StructField.Attributes = undefined;
    for (ti.fields, &types, &attrs) |field, *t, *a| {
        t.* = field.type;
        a.* = .{
            .default_value_ptr = field.default_value_ptr,
            .@"align" = field.alignment,
            .@"comptime" = field.is_comptime,
        };
    }

    return .{
        .layout = ti.layout,
        .backing_integer = ti.backing_integer,
        .field_names = std.meta.fieldNames(T),
        .field_types = &types,
        .field_attrs = &attrs,
    };
}

pub fn addFieldExtra(
    comptime self: *TypeBuilder,
    comptime name: []const u8,
    comptime T: type,
    comptime default_value: ?*const anyopaque,
    comptime is_comptime: ?bool,
    comptime alignment: ?usize,
) void {
    self.field_names = self.field_names ++ &[_][]const u8{name};
    self.field_types = self.field_types ++ &[_]type{T};
    self.field_attrs = self.field_attrs ++ &[_]Type.StructField.Attributes{.{
        .default_value_ptr = default_value,
        .@"align" = alignment,
        .@"comptime" = is_comptime orelse false,
    }};
}

pub fn addField(
    comptime self: *TypeBuilder,
    comptime name: []const u8,
    comptime T: type,
    comptime default_value: ?*const anyopaque,
) void {
    return addFieldExtra(self, name, T, default_value, null, null);
}

pub const addTupleField = @compileError("Tuples have been restricted, just use a []const type and ++");
pub const addTupleFieldExtra = @compileError("Tuples have been restricted, just use a []const type and ++");
pub const appendTupleField = @compileError("Tuples have been restricted, just use a []const type and ++");
pub const appendTupleFieldExtra = @compileError("Tuples have been restricted, just use a []const type and ++");

pub fn Build(comptime self: TypeBuilder) type {
    return @Struct(
        self.layout,
        self.backing_integer,
        self.field_names,
        self.field_types[0..self.field_names.len],
        self.field_attrs[0..self.field_names.len],
    );
}
