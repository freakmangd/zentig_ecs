const std = @import("std");
const ztg = @import("init.zig");

/// Use `before`, `label`, `after`, or `systemOrder` to define the order of
/// execution for systems when adding them to stages
pub const SystemOrder = struct {
    before: ?ztg.meta.EnumLiteral = null,
    during: ?ztg.meta.EnumLiteral = null,
    after: ?ztg.meta.EnumLiteral = null,

    fn Bind(comptime f: anytype, comptime offset: SystemOrder) type {
        return struct {
            comptime f: @TypeOf(f) = f,
            comptime offset: SystemOrder = offset,
        };
    }
};

pub fn systemOrder(comptime f: anytype, comptime offset: SystemOrder) SystemOrder.Bind(f, offset) {
    return .{};
}

pub fn before(comptime _label: ztg.meta.EnumLiteral, comptime f: anytype) SystemOrder.Bind(f, .{ .before = _label }) {
    return .{};
}

pub fn label(comptime _label: ztg.meta.EnumLiteral, comptime f: anytype) SystemOrder.Bind(f, .{ .during = _label }) {
    return .{};
}

pub fn after(comptime _label: ztg.meta.EnumLiteral, comptime f: anytype) SystemOrder.Bind(f, .{ .after = _label }) {
    return .{};
}
