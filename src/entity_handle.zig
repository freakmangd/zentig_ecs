const std = @import("std");
const ztg = @import("init.zig");
const Entity = ztg.Entity;
const EntityHandle = @This();

com: ztg.Commands,
ent: Entity,

pub fn giveComponents(self: EntityHandle, comps: anytype) !void {
    try self.com.giveComponents(self.ent, comps);
}

pub fn removeComponent(self: EntityHandle, comptime Comp: type) !void {
    try self.com.removeComponent(self.ent, Comp);
}

pub fn checkHas(self: EntityHandle, comptime Comp: type) bool {
    return self.com.checkEntHas(self.ent, Comp);
}

pub fn getComponent(self: EntityHandle, comptime Comp: type) ?Comp {
    return self.com.getComponent(self.ent, Comp);
}

pub fn getComponentPtr(self: EntityHandle, comptime Comp: type) ?*Comp {
    return self.com.getComponentPtr(self.ent, Comp);
}

/// `parent` accepted types: ?Entity, EntityHandle, @TypeOf(null)
pub fn setParent(self: EntityHandle, parent: anytype) !void {
    switch (@TypeOf(parent)) {
        Entity, ?Entity => try self.com.setEntParent(self.ent, parent),
        EntityHandle => try self.com.setEntParent(self.ent, parent.ent),
        @TypeOf(null) => try self.com.setEntParent(self.ent, null),
        else => |T| @compileError(std.fmt.comptimePrint("Type `{s}` not supported for setParent. Accepted types are: ?Entity, EntityHandle, and @TypeOf(null)", .{@typeName(T)})),
    }
}

/// `child` accepted types: ?Entity, EntityHandle
pub fn giveChild(self: EntityHandle, child: anytype) !void {
    switch (@TypeOf(child)) {
        Entity, ?Entity => try self.com.giveEntChild(self.ent, child),
        EntityHandle => try self.com.giveEntChild(self.ent, child.ent),
        else => |T| @compileError(std.fmt.comptimePrint("Type `{s}` not supported for giveChild. Accepted types are: ?Entity, EntityHandle", .{@typeName(T)})),
    }
}

pub fn newChildWith(self: EntityHandle, child_components: anytype) !EntityHandle {
    const child = try self.com.newEntWith(child_components);
    try self.giveChild(child);
    return child;
}
