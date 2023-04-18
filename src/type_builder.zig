const std = @import("std");
const Type = std.builtin.Type;

const Self = @This();

// TODO: eventually turn this into a []Type.StructField?
type_def: Type.Struct,

pub fn new(comptime is_tuple: bool, comptime layout: Type.ContainerLayout) Self {
    return .{ .type_def = .{
        .fields = &.{},
        .is_tuple = is_tuple,
        .layout = layout,
        .decls = &.{},
    } };
}

pub fn from(comptime T: type) Self {
    return .{ .type_def = @typeInfo(T).Struct };
}

pub fn addFieldExtra(
    comptime self: Self,
    comptime name: []const u8,
    comptime T: type,
    comptime default_value: ?*const anyopaque,
    comptime is_comptime: ?bool,
    comptime alignment: ?comptime_int,
) Self {
    const new_fields = self.type_def.fields ++ &[_]Type.StructField{.{
        .type = T,
        .name = name,
        .default_value = default_value,
        .alignment = alignment orelse 0,
        .is_comptime = is_comptime orelse false,
    }};
    return .{ .type_def = .{
        .fields = new_fields,
        .decls = &.{},
        .layout = self.type_def.layout,
        .is_tuple = self.type_def.is_tuple,
    } };
}

pub fn addField(comptime self: Self, comptime name: []const u8, comptime T: type, comptime default_value: ?*const anyopaque) Self {
    return addFieldExtra(self, name, T, default_value, null, null);
}

pub fn addTupleField(comptime self: Self, comptime index: usize, comptime T: type, comptime default_value: ?*const anyopaque) Self {
    return addField(self, std.fmt.comptimePrint("{}", .{index}), T, default_value);
}

pub fn Build(comptime self: Self) type {
    return @Type(Type{ .Struct = self.type_def });
}
