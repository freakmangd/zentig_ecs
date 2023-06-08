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
    new_ent_fn: *const fn (*anyopaque) error{ Overflow, HitMaxEntities }!ecs.Entity,
    add_component_fn: *const fn (*anyopaque, ecs.Entity, TypeMap.UniqueTypePtr, *const anyopaque) ca.Error!void,
    run_stage_fn: *const fn (*anyopaque, []const u8) anyerror!void,
};

pub fn runStage(self: Self, comptime stage_id: @TypeOf(.enum_literal)) anyerror!void {
    try self.vtable.run_stage_fn(self.ctx, @tagName(stage_id));
}

pub fn runStageByName(self: Self, stage_id: []const u8) anyerror!void {
    try self.vtable.run_stage_fn(self.ctx, stage_id);
}

pub fn runStageList(self: Self, comptime stage_ids: []const @TypeOf(.enum_literal)) anyerror!void {
    for (stage_ids) |sid| {
        try runStage(self, @tagName(sid));
    }
}

pub fn runStageNameList(self: Self, stage_ids: []const []const u8) anyerror!void {
    for (stage_ids) |sid| {
        try runStage(self, sid);
    }
}

/// Runs the stages: .pre_init, .init, .post_init
pub fn runInitStages(self: Self) anyerror!void {
    inline for (.{ "pre_init", "init", "post_init" }) |stage| {
        try runStage(self, stage);
    }
}

/// Runs the stages: .pre_update, .update, .post_update
pub fn runUpdateStages(self: Self) anyerror!void {
    inline for (.{ "pre_update", "update", "post_update" }) |stage| {
        try runStage(self, stage);
    }
}

/// Runs the stages .pre_draw, .draw, .post_draw
pub fn runDrawStages(self: Self) anyerror!void {
    inline for (.{ "pre_draw", "draw", "post_draw" }) |stage| {
        try runStage(self, stage);
    }
}

pub fn newEnt(self: Self) error{ Overflow, HitMaxEntities }!Entity {
    return self.vtable.new_ent_fn(self.ctx);
}

pub fn giveEnt(self: Self, ent: Entity, component: anytype) ca.Error!void {
    try self.vtable.add_component_fn(self.ctx, ent, TypeMap.uniqueTypePtr(@TypeOf(component)), &component);
}

pub fn giveEntMany(self: Self, ent: Entity, components: anytype) ca.Error!void {
    inline for (std.meta.fields(@TypeOf(components))) |field| {
        try giveEnt(self, ent, @field(components, field.name));
    }
}
