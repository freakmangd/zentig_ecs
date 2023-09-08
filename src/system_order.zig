const std = @import("std");
const ztg = @import("init.zig");

/// An enum describing the three possible orderings for
/// a system within a label.
pub const SystemOrder = enum {
    before,
    during,
    after,
};

fn Bind(comptime _label: ztg.meta.EnumLiteral, comptime f: anytype, comptime offset: SystemOrder) type {
    return struct {
        comptime label: ztg.meta.EnumLiteral = _label,
        comptime f: @TypeOf(f) = f,
        comptime offset: SystemOrder = offset,
    };
}

fn BindingGroup(comptime _label: ztg.meta.EnumLiteral, comptime groups: anytype) type {
    return struct {
        comptime label: ztg.meta.EnumLiteral = _label,
        comptime groups: @TypeOf(groups) = groups,
    };
}

/// Equivelent to calling `before`, `during`, or `after` depending on the `offset` parameter
pub fn ordered(comptime _label: ztg.meta.EnumLiteral, comptime f: anytype, comptime offset: SystemOrder) Bind(_label, f, offset) {
    return .{};
}

/// Makes the system `f` invoke _before_ the specified label
pub fn before(comptime _label: ztg.meta.EnumLiteral, comptime f: anytype) Bind(_label, f, .before) {
    return .{};
}

/// Makes the system `f` invoke _during_ the specified label
pub fn during(comptime _label: ztg.meta.EnumLiteral, comptime f: anytype) Bind(_label, f, .during) {
    return .{};
}

/// Makes the system `f` invoke _after_ the specified label
pub fn after(comptime _label: ztg.meta.EnumLiteral, comptime f: anytype) Bind(_label, f, .after) {
    return .{};
}

pub fn orderGroup(comptime _label: ztg.meta.EnumLiteral, comptime groups: anytype) BindingGroup(_label, groups) {
    return .{};
}
