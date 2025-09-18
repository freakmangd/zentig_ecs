//! A runtime interface for a World which can be requested in systems

const std = @import("std");
const ztg = @import("init.zig");
const world = @import("world.zig");
const util = @import("util.zig");
const builtin = @import("builtin");

const Allocator = std.mem.Allocator;
const TypeMap = ztg.meta.TypeMap;
const Entity = ztg.Entity;

const Commands = @This();

pub const ComponentError = error{UnregisteredComponent};
pub const RemoveComponentError = ComponentError || error{EntityDoesntExist} || Allocator.Error;

ctx: *anyopaque,
vtable: *const Vtable,

pub const Vtable = struct {
    new_ent: *const fn (*anyopaque) Entity,
    remove_ent: *const fn (*anyopaque, Entity) Allocator.Error!void,

    get_ent_parent: *const fn (*const anyopaque, ztg.Entity) error{EntityDoesntExist}!?ztg.Entity,
    set_ent_parent: *const fn (*anyopaque, ztg.Entity, ?ztg.Entity) error{ EntityDoesntExist, ParentDoesntExist }!void,

    add_component: *const fn (*anyopaque, Entity, util.CompId, u29, *const anyopaque) anyerror!void,
    remove_component: *const fn (*anyopaque, Entity, util.CompId) RemoveComponentError!void,
    get_component_ptr: *const fn (*anyopaque, Entity, util.CompId) ComponentError!?*anyopaque,
    check_ent_has: *const fn (*anyopaque, Entity, util.CompId) ComponentError!bool,

    run_stage: *const fn (*anyopaque, []const u8) anyerror!void,

    get_res: *const fn (*anyopaque, ztg.meta.Utp) error{UnregisteredResource}!*anyopaque,
    has_included: *const fn (ztg.meta.Utp) bool,
};

/// If you are going to run multiple stages in a row, consider `.runStageList()`
pub fn runStage(self: Commands, comptime stage_id: ztg.meta.EnumLiteral) anyerror!void {
    try self.vtable.run_stage(self.ctx, @tagName(stage_id));
}

/// If you are going to run multiple stages in a row, consider `.runStageNameList()`
pub fn runStageByName(self: Commands, stage_id: []const u8) anyerror!void {
    try self.vtable.run_stage(self.ctx, stage_id);
}

pub fn runStageList(self: Commands, comptime stage_ids: []const ztg.meta.EnumLiteral) anyerror!void {
    inline for (stage_ids) |sid| {
        try runStage(self, sid);
    }
}

pub fn runStageNameList(self: Commands, stage_ids: []const []const u8) anyerror!void {
    for (stage_ids) |sid| {
        try runStageByName(self, sid);
    }
}

/// Returns an EntityHandle to a new entity
pub fn newEnt(self: Commands) ztg.EntityHandle {
    return .{ .ent = self.vtable.new_ent(self.ctx), .com = self };
}

/// Shortcut for creating a new entity and adding components to it
pub fn newEntWith(self: Commands, components: anytype) !ztg.EntityHandle {
    const ent = self.vtable.new_ent(self.ctx);
    try self.giveComponents(ent, components);
    return .{ .ent = ent, .com = self };
}

/// Returns the entity's parent if it has one
/// Can error if the entity doesn't exist
pub fn getEntParent(self: Commands, ent: ztg.Entity) !?ztg.Entity {
    return self.vtable.get_ent_parent(self.ctx, ent);
}

/// Sets the entity's parent or removes it depending on the null-ness of `parent`
/// Can error if the entity doesn't exist or the parent isnt null but doesnt exist
pub fn setEntParent(self: Commands, ent: ztg.Entity, parent: ?ztg.Entity) !void {
    return self.vtable.set_ent_parent(self.ctx, ent, parent);
}

/// Inverse of setEntParent
pub fn giveEntChild(self: Commands, ent: ztg.Entity, child: ztg.Entity) !void {
    return self.vtable.set_ent_parent(self.ctx, child, ent);
}

fn giveComponentSingle(self: Commands, ent: Entity, component: anytype) !void {
    const Component = @TypeOf(component);
    if (Component == type) util.compileError("You have passed `{}` to giveComponents, which is of type `type`, you might have forgotten to instantiate it.", .{component});

    self.vtable.add_component(self.ctx, ent, util.compId(Component), @alignOf(Component), @ptrCast(&component)) catch |err| switch (err) {
        error.UnregisteredComponent => panicOnUnregistered(Component, .component),
        else => return err,
    };
}

/// Adds the components to the entity `ent`. If the component cannot be added without invalidating
/// pointers, it will be queued to be added after the current system finishes.
///
/// Possible types for components:
/// + tuple { T, V, ... }, where types within the tuple are registered components
/// + struct { t: T, v: V, ... }, where types within the struct are registered components,
///     and the struct itself has an `is_component_bundle` public decl
///
/// If any of the types passed in the tuple/struct components have the `is_component_bundle`
/// public decl, they will be treated as component bundles and recursively added
pub fn giveComponents(self: Commands, ent: Entity, components: anytype) !void {
    const Components = @TypeOf(components);

    if (@typeInfo(Components) == .@"struct" and
        !@typeInfo(Components).@"struct".is_tuple and
        !@hasDecl(Components, "is_component_bundle"))
    {
        @compileError(
            \\Struct passed to giveComponents does not have a public is_component_bundle decl,
            \\if it is not a bundle wrap it in an anonymous tuple."
        );
    }

    inline for (std.meta.fields(Components)) |field| {
        if (comptime util.isContainer(field.type) and @hasDecl(field.type, "is_component_bundle")) {
            try giveComponents(self, ent, @field(components, field.name));
        } else {
            try giveComponentSingle(self, ent, @field(components, field.name));
        }
    }
}

/// Removes the component of type `Component` given to `ent`
pub fn removeComponent(self: Commands, ent: Entity, comptime Component: type) !void {
    return self.vtable.remove_component(self.ctx, ent, util.compId(Component)) catch |err| switch (err) {
        error.UnregisteredComponent => panicOnUnregistered(Component, .component),
        else => return err,
    };
}

/// Returns true or false depending on whether ent has the component of type `Component`
pub fn checkEntHas(self: Commands, ent: Entity, comptime Component: type) bool {
    return self.vtable.check_ent_has(self.ctx, ent, util.compId(Component)) catch |err| switch (err) {
        error.UnregisteredComponent => panicOnUnregistered(Component, .component),
    };
}

/// Returns a copy of the component data associated with `ent`
pub fn getComponent(self: Commands, ent: Entity, comptime Component: type) ?Component {
    const ptr = self.vtable.get_component_ptr(self.ctx, ent, util.compId(Component)) catch |err| switch (err) {
        error.UnregisteredComponent => panicOnUnregistered(Component, .component),
    };
    if (comptime @sizeOf(Component) == 0) return if (ptr) |_| undefined else null;
    return if (ptr) |p| @as(*Component, @ptrCast(@alignCast(p))).* else null;
}

/// Returns a pointer to the component data associated with `ent`
pub fn getComponentPtr(self: Commands, ent: Entity, comptime Component: type) ?*Component {
    const ptr = self.vtable.get_component_ptr(self.ctx, ent, util.compId(Component)) catch |err| switch (err) {
        error.UnregisteredComponent => panicOnUnregistered(Component, .component),
    };
    return if (ptr) |p| @ptrCast(@alignCast(p)) else null;
}

/// Queues the removal of all components in lists associated with `ent`
pub fn removeEnt(self: Commands, ent: Entity) !void {
    try self.vtable.remove_ent(self.ctx, ent);
}

/// Returns a pointer to the world resource T
pub fn getResPtr(self: Commands, comptime T: type) *T {
    const ptr = self.vtable.get_res(self.ctx, ztg.meta.utpOf(T)) catch |err| switch (err) {
        error.UnregisteredResource => panicOnUnregistered(T, .resource),
    };
    return @ptrCast(@alignCast(ptr));
}

/// Returns whether or not the world included the type `Namespace` in the `WorldBuilder`
pub fn hasIncluded(self: Commands, comptime Namespace: type) bool {
    return self.vtable.has_included(ztg.meta.utpOf(Namespace));
}

fn panicOnUnregistered(comptime T: type, comptime t: enum { component, resource }) noreturn {
    switch (t) {
        .component => std.debug.panic("Component of type {s} has not been registered, use addComponents in WorldBuilder to register a component.", .{@typeName(T)}),
        .resource => std.debug.panic("Cannot request a pointer to resource of type {s} as it has not been registered, use addResource in WorldBuilder to register a resource.", .{@typeName(T)}),
    }
}

const test_mod = struct {
    pub const MyComponent = struct {
        speed: f32,
        dir: ztg.Vec2,
    };

    pub fn update_MyComponent(q: ztg.Query(.{ ztg.base.Transform, MyComponent })) void {
        for (q.items(ztg.base.Transform), q.items(MyComponent)) |tr, c| {
            tr.translate(c.dir.mul(c.speed).extend(0));
        }
    }

    pub fn test_time(com: ztg.Commands, time: *ztg.base.Time) !void {
        try std.testing.expectEqual(@as(usize, 0), time.frame_count);
        try com.runStage(.update);
        try std.testing.expectEqual(@as(usize, 1), time.frame_count);
        try com.runStageByName("update");
        try std.testing.expectEqual(@as(usize, 2), time.frame_count);
        try com.runStageList(&.{.update});
        try std.testing.expectEqual(@as(usize, 3), time.frame_count);
        try com.runStageNameList(&.{"update"});
        try std.testing.expectEqual(@as(usize, 4), time.frame_count);
    }

    pub fn include(comptime wb: *ztg.WorldBuilder) void {
        wb.include(&.{ztg.base}); // ensure we included ztg.base for the Transform component
        wb.addComponents(&.{MyComponent});
        wb.addSystemsToStage(.update, .{update_MyComponent});
        wb.addStage(.do_test);
        wb.addSystemsToStage(.do_test, test_time);
    }
};

const MyWorld = ztg.WorldBuilder.init(&.{ ztg.base, test_mod }).Build();

test "basic usage" {
    var w = try MyWorld.init(std.testing.allocator);
    defer w.deinit();
    const com = w.commands();

    _ = try com.newEntWith(.{
        ztg.base.Transform{},
        test_mod.MyComponent{
            .speed = 1_000,
            .dir = .init(0.7, 2),
        },
    });
}

test "running stages" {
    var w = try MyWorld.init(std.testing.allocator);
    defer w.deinit();

    // any errors that occur during the stage are propogated
    // up to this call
    try w.runStage(.do_test);
}

test "adding/removing entities" {
    var w = try MyWorld.init(std.testing.allocator);
    defer w.deinit();
    const com = w.commands();

    const my_ent = try com.newEntWith(.{ztg.base.Transform.initWith(.{})});

    if (!my_ent.checkHas(test_mod.MyComponent)) try my_ent.giveComponents(.{test_mod.MyComponent{
        .speed = 50,
        .dir = ztg.Vec2.right,
    }});

    try w.postSystemUpdate();

    const q = try w.query(std.testing.allocator, ztg.Query(.{ ztg.base.Transform, test_mod.MyComponent }));
    defer q.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(f32, 0), q.single(ztg.base.Transform).getPos().x);
    try com.runStage(.update);
    try std.testing.expectEqual(@as(f32, 50), q.single(ztg.base.Transform).getPos().x);

    try com.removeEnt(my_ent.ent);
    try w.postSystemUpdate();

    const q2 = try w.query(std.testing.allocator, ztg.Query(.{test_mod.MyComponent}));
    defer q2.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), q2.len);
}
