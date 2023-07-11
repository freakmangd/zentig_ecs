const std = @import("std");
const ecs = @import("ecs.zig");
const TypeMap = @import("type_map.zig");
const Entity = ecs.Entity;
const Allocator = std.mem.Allocator;
const ca = @import("component_array.zig");

const Self = @This();

ctx: *anyopaque,
vtable: *const Vtable,

pub const Vtable = struct {
    new_ent_fn: *const fn (*anyopaque) Allocator.Error!Entity,
    remove_ent_fn: *const fn (*anyopaque, Entity) Allocator.Error!void,
    add_component_fn: *const fn (*anyopaque, Entity, TypeMap.UniqueTypePtr, *const anyopaque) ca.Error!void,
    run_stage_fn: *const fn (*anyopaque, []const u8) anyerror!void,
    get_res_fn: *const fn (*anyopaque, TypeMap.UniqueTypePtr) *anyopaque,
    check_ent_has_fn: *const fn (*anyopaque, Entity, TypeMap.UniqueTypePtr) bool,
};

/// If you are going to run multiple stages in a row, consider `.runStageList()`
///
/// Example:
/// ```zig
/// com.runStage(.render);
/// ```
pub fn runStage(self: Self, comptime stage_id: @TypeOf(.enum_literal)) anyerror!void {
    try self.vtable.run_stage_fn(self.ctx, @tagName(stage_id));
}

/// If you are going to run multiple stages in a row, consider `.runStageNameList()`
///
/// Example:
/// ```zig
/// com.runStageByName("render");
/// ```
pub fn runStageByName(self: Self, stage_id: []const u8) anyerror!void {
    try self.vtable.run_stage_fn(self.ctx, stage_id);
}

/// If you are going to run builtin pre_X, X, post_X stages, consider `.runInitStages()`, `.runUpdateStages()`, or `.runDrawStages()`
///
/// Example:
/// ```zig
/// com.runStageList(&.{ .ping_send, .ping_receive, .ping_read });
/// ```
pub fn runStageList(self: Self, comptime stage_ids: []const @TypeOf(.enum_literal)) anyerror!void {
    for (stage_ids) |sid| {
        try runStage(self, @tagName(sid));
    }
}

/// If you are going to run builtin pre_X, X, post_X stages, consider `.runInitStages()`, `.runUpdateStages()`, or `.runDrawStages()`
///
/// Example:
/// ```zig
/// com.runStageList(&.{ "ping_send", "ping_receive", "ping_read" });
/// ```
pub fn runStageNameList(self: Self, stage_ids: []const []const u8) anyerror!void {
    for (stage_ids) |sid| {
        try runStageByName(self, sid);
    }
}

/// Runs the stages: .pre_init, .init, .post_init
pub fn runInitStages(self: Self) anyerror!void {
    inline for (.{ .pre_init, .init, .post_init }) |stage| {
        try runStage(self, stage);
    }
}

/// Runs the stages: .pre_update, .update, .post_update
pub fn runUpdateStages(self: Self) anyerror!void {
    inline for (.{ .pre_update, .update, .post_update }) |stage| {
        try runStage(self, stage);
    }
}

/// Runs the stages .pre_draw, .draw, .post_draw
pub fn runDrawStages(self: Self) anyerror!void {
    inline for (.{ .pre_draw, .draw, .post_draw }) |stage| {
        try runStage(self, stage);
    }
}

/// Returns an EntityHandle to a new entity
pub fn newEnt(self: Self) Allocator.Error!ecs.EntityHandle {
    const ent = try self.vtable.new_ent_fn(self.ctx);
    return .{ .ent = ent, .com = self };
}

/// Shortcut for creating a new entity and adding one component to it
pub fn newEntWith(self: Self, component: anytype) !ecs.EntityHandle {
    const ent = try newEnt(self);
    try ent.giveEnt(component);
    return ent;
}

/// Shortcut for creating a new entity and adding many components to it
pub fn newEntWithMany(self: Self, components: anytype) !ecs.EntityHandle {
    const ent = try newEnt(self);
    try ent.giveEntMany(components);
    return ent;
}

/// Adds a component to the entity `ent`. If the component cannot be added without invalidating
/// pointers, it will be queued to be added after the current system finishes.
pub fn giveEnt(self: Self, ent: Entity, component: anytype) !void {
    try self.vtable.add_component_fn(self.ctx, ent, TypeMap.uniqueTypePtr(@TypeOf(component)), &component);
}

/// Adds every field in the components object to its component list at the Entity index
pub fn giveEntMany(self: Self, ent: Entity, components: anytype) !void {
    inline for (std.meta.fields(@TypeOf(components))) |field| {
        try giveEnt(self, ent, @field(components, field.name));
    }
}

/// Queues the removal of all components in lists correlated with `ent`
pub fn removeEnt(self: Self, ent: Entity) !void {
    try self.vtable.remove_ent_fn(self.ctx, ent);
}

/// Returns a pointer to the world resource T
pub fn getResPtr(self: Self, comptime T: type) *T {
    return @ptrCast(@alignCast(self.vtable.get_res_fn(self.ctx, TypeMap.uniqueTypePtr(T))));
}
