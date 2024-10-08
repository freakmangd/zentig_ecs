const std = @import("std");
const util = @import("../util.zig");
const Type = std.builtin.Type;

const Self = @This();

fields: []const Type.StructField = &.{},
is_tuple: bool = false,
layout: Type.ContainerLayout = .auto,

pub fn initFrom(comptime T: type) Self {
    const ti = @typeInfo(T).@"struct";
    return .{
        .fields = ti.fields,
        .is_tuple = ti.is_tuple,
        .layout = ti.layout,
    };
}

pub fn addFieldExtra(
    comptime self: *Self,
    comptime name: [:0]const u8,
    comptime T: type,
    comptime default_value: ?*const anyopaque,
    comptime is_comptime: ?bool,
    comptime alignment: ?comptime_int,
) void {
    self.fields = self.fields ++ &[_]Type.StructField{.{
        .type = T,
        .name = name,
        .default_value = default_value,
        .alignment = alignment orelse 0,
        .is_comptime = is_comptime orelse false,
    }};
}

pub fn addField(comptime self: *Self, comptime name: [:0]const u8, comptime T: type, comptime default_value: ?*const anyopaque) void {
    return addFieldExtra(self, name, T, default_value, null, null);
}

pub fn addTupleField(comptime self: *Self, comptime index: usize, comptime T: type, comptime default_value: ?*const anyopaque) void {
    return addField(self, std.fmt.comptimePrint("{}", .{index}), T, default_value);
}

pub fn appendTupleField(comptime self: *Self, comptime T: type, comptime default_value: ?*const anyopaque) void {
    return addField(self, std.fmt.comptimePrint("{}", .{self.fields.len}), T, default_value);
}

pub fn addTupleFieldExtra(
    comptime self: *Self,
    comptime index: usize,
    comptime T: type,
    comptime default_value: ?*const anyopaque,
    comptime is_comptime: ?bool,
    comptime alignment: ?comptime_int,
) void {
    return addFieldExtra(self, std.fmt.comptimePrint("{}", .{index}), T, default_value, is_comptime, alignment);
}

pub fn appendTupleFieldExtra(
    comptime self: *Self,
    comptime T: type,
    comptime default_value: ?*const anyopaque,
    comptime is_comptime: ?bool,
    comptime alignment: ?comptime_int,
) void {
    return addFieldExtra(self, std.fmt.comptimePrint("{}", .{self.fields.len}), T, default_value, is_comptime, alignment);
}

pub fn Build(comptime self: Self) type {
    return @Type(.{ .@"struct" = .{
        .fields = self.fields,
        .is_tuple = self.is_tuple,
        .layout = self.layout,
        .decls = &.{},
    } });
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
