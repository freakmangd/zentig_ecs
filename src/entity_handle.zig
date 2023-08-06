const ztg = @import("init.zig");
const Entity = ztg.Entity;
const EntityHandle = @This();

com: ztg.Commands,
ent: Entity,

pub inline fn give(self: EntityHandle, comp: anytype) !void {
    try self.com.giveEnt(self.ent, comp);
}

pub inline fn giveMany(self: EntityHandle, comps: anytype) !void {
    try self.com.giveEntMany(self.ent, comps);
}

pub inline fn checkHas(self: EntityHandle, comptime Comp: type) bool {
    return self.com.checkEntHas(self.ent, Comp);
}

pub inline fn getComponent(self: EntityHandle, comptime Comp: type) ?*Comp {
    return self.com.getComponent(self.ent, Comp);
}

pub inline fn getComponentPtr(self: EntityHandle, comptime Comp: type) ?*Comp {
    return self.com.getComponentPtr(self.ent, Comp);
}

/// `parent` accepted types: ?Entity, EntityHandle, null
pub inline fn setParent(self: EntityHandle, parent: anytype) !void {
    switch (@TypeOf(parent)) {
        Entity, ?Entity => try self.com.setEntParent(self.ent, parent),
        EntityHandle => try self.com.setEntParent(self.ent, parent.ent),
        @TypeOf(null) => try self.com.setEntParent(self.ent, null),
        else => |T| @compileError("Type " ++ @typeName(T) ++ " not supported for setParent. Accepted types are: ?Entity, EntityHandle, and @TypeOf(null)"),
    }
}

/// `child` accepted types: ?Entity, EntityHandle
pub inline fn giveChild(self: EntityHandle, child: anytype) !void {
    switch (@TypeOf(child)) {
        Entity, ?Entity => try self.com.giveEntChild(self.ent, child),
        EntityHandle => try self.com.giveEntChild(self.ent, child.ent),
        else => |T| @compileError("Type " ++ @typeName(T) ++ " not supported for giveChild. Accepted types are: ?Entity and EntityHandle"),
    }
}

pub fn newChildWith(self: EntityHandle, child_components: anytype) !EntityHandle {
    const child = try self.com.newEntWithMany(child_components);
    try self.giveChild(child);
    return child;
}
