const std = @import("std");
const ztg = @import("init.zig");
const ca = @import("component_array.zig");
const world = @import("world.zig");
const util = @import("util.zig");

const Allocator = std.mem.Allocator;
const TypeMap = ztg.meta.TypeMap;
const Entity = ztg.Entity;

const Self = @This();

ctx: *anyopaque,
vtable: *const Vtable,

pub const Vtable = struct {
    new_ent: *const fn (*anyopaque) Allocator.Error!Entity,
    remove_ent: *const fn (*anyopaque, Entity) Allocator.Error!void,

    get_ent_parent: *const fn (*const anyopaque, ztg.Entity) error{EntityDoesntExist}!?ztg.Entity,
    set_ent_parent: *const fn (*anyopaque, ztg.Entity, ?ztg.Entity) error{ EntityDoesntExist, ParentDoesntExist }!void,

    add_component: *const fn (*anyopaque, Entity, util.CompId, *const anyopaque) world.CommandsGiveEntError!void,
    remove_component: *const fn (*anyopaque, Entity, util.CompId) ca.Error!void,
    get_component_ptr: *const fn (*anyopaque, Entity, util.CompId) world.CommandsComponentError!?*anyopaque,
    check_ent_has: *const fn (*anyopaque, Entity, util.CompId) world.CommandsComponentError!bool,

    run_stage: *const fn (*anyopaque, []const u8) anyerror!void,

    get_res: *const fn (*anyopaque, ztg.meta.Utp) error{UnregisteredResource}!*anyopaque,
    has_included: *const fn (ztg.meta.Utp) bool,

    query: *const fn (
        ptr: *anyopaque,
        alloc: std.mem.Allocator,
        has_entities: bool,
        req: []const util.CompId,
        opt: []const util.CompId,
        with: []const util.CompId,
        without: []const util.CompId,
    ) Allocator.Error!RuntimeQuery,
};

/// If you are going to run multiple stages in a row, consider `.runStageList()`
///
/// Example:
/// ```zig
/// com.runStage(.render);
/// ```
pub fn runStage(self: Self, comptime stage_id: @TypeOf(.enum_literal)) anyerror!void {
    try self.vtable.run_stage(self.ctx, @tagName(stage_id));
}

/// If you are going to run multiple stages in a row, consider `.runStageNameList()`
///
/// Example:
/// ```zig
/// com.runStageByName("render");
/// ```
pub fn runStageByName(self: Self, stage_id: []const u8) anyerror!void {
    try self.vtable.run_stage(self.ctx, stage_id);
}

/// Example:
/// ```zig
/// com.runStageList(&.{ .ping_send, .ping_receive, .ping_read });
/// ```
pub fn runStageList(self: Self, comptime stage_ids: []const @TypeOf(.enum_literal)) anyerror!void {
    inline for (stage_ids) |sid| {
        try runStage(self, sid);
    }
}

/// Example:
/// ```zig
/// com.runStageList(&.{ "ping_send", "ping_receive", "ping_read" });
/// ```
pub fn runStageNameList(self: Self, stage_ids: []const []const u8) anyerror!void {
    for (stage_ids) |sid| {
        try runStageByName(self, sid);
    }
}

/// Returns an EntityHandle to a new entity
pub fn newEnt(self: Self) Allocator.Error!ztg.EntityHandle {
    return .{ .ent = try self.vtable.new_ent(self.ctx), .com = self };
}

/// Shortcut for creating a new entity and adding one component to it
pub fn newEntWith(self: Self, component: anytype) !ztg.EntityHandle {
    const ent = try newEnt(self);
    try ent.give(component);
    return ent;
}

/// Shortcut for creating a new entity and adding many components to it
pub fn newEntWithMany(self: Self, components: anytype) !ztg.EntityHandle {
    const ent = try newEnt(self);
    try ent.giveMany(components);
    return ent;
}

pub fn getEntParent(self: Self, ent: ztg.Entity) !?ztg.Entity {
    return self.vtable.get_ent_parent(self.ctx, ent);
}

pub fn setEntParent(self: Self, ent: ztg.Entity, parent: ?ztg.Entity) !void {
    return self.vtable.set_ent_parent(self.ctx, ent, parent);
}

pub fn giveEntChild(self: Self, ent: ztg.Entity, child: ztg.Entity) !void {
    return self.vtable.set_ent_parent(self.ctx, child, ent);
}

/// Adds a component to the entity `ent`. If the component cannot be added without invalidating
/// pointers, it will be queued to be added after the current system finishes.
pub fn giveEnt(self: Self, ent: Entity, component: anytype) !void {
    const Component = @TypeOf(component);
    const has_onAdded = comptime @hasDecl(Component, "onAdded");

    if (comptime has_onAdded) util.assertOkOnAddedFunction(Component);

    const member_type: ?ztg.meta.MemberFnType = comptime if (has_onAdded) ztg.meta.memberFnType(Component, "onAdded") else null;
    const needs_mut = member_type == .by_ptr;
    const can_err = comptime has_onAdded and ztg.meta.canReturnError(@TypeOf(Component.onAdded));
    var mutable_comp: if (has_onAdded and needs_mut) Component else void = if (comptime has_onAdded and needs_mut) component else void{};

    if (comptime has_onAdded) {
        if (comptime member_type == .non_member) {
            if (comptime can_err) try Component.onAdded(ent, self) else Component.onAdded(ent, self);
        } else {
            var c = if (comptime needs_mut) mutable_comp else component;
            if (comptime can_err) try c.onAdded(ent, self) else c.onAdded(ent, self);
        }
    }

    self.vtable.add_component(self.ctx, ent, util.compId(Component), if (has_onAdded and needs_mut) &mutable_comp else &component) catch |err| switch (err) {
        error.UnregisteredComponent => std.debug.panic("Cannot give ent {} a component of type {s} as it has not been registered.", .{ ent, @typeName(Component) }),
        else => return err,
    };
}

/// Adds every field in the components object to its component list at the Entity index
pub fn giveEntMany(self: Self, ent: Entity, components: anytype) !void {
    inline for (std.meta.fields(@TypeOf(components))) |field| {
        if (comptime @hasDecl(field.type, "is_component_bundle")) {
            try giveEntMany(self, ent, @field(components, field.name));
        } else {
            try giveEnt(self, ent, @field(components, field.name));
        }
    }
}

pub fn removeComponent(self: Self, ent: Entity, comptime Component: type) ca.Error!void {
    return self.vtable.remove_component(self.ctx, ent, util.compId(Component));
}

/// Returns true or false depending on whether ent has the component of type `Component`
pub fn checkEntHas(self: Self, ent: Entity, comptime Component: type) bool {
    return self.vtable.check_ent_has(self.ctx, ent, util.compId(Component)) catch |err| switch (err) {
        error.UnregisteredComponent => std.debug.panic("Cannot check if entity {} has component of type {s} as it has not been registered.", .{ ent, @typeName(Component) }),
    };
}

/// Returns a pointer to the component data associated with `ent`
pub fn getComponent(self: Self, ent: Entity, comptime Component: type) ?Component {
    const ptr = self.vtable.get_component_ptr(self.ctx, ent, util.compId(Component)) catch |err| switch (err) {
        error.UnregisteredComponent => std.debug.panic("Cannot get pointer to component of type {s} as it has not been registered.", .{@typeName(Component)}),
    };
    if (comptime @sizeOf(Component) == 0) return if (ptr) |_| Component{} else null;
    return if (ptr) |p| @as(*Component, @ptrCast(@alignCast(p))).* else null;
}

/// Returns a pointer to the component data associated with `ent`
pub fn getComponentPtr(self: Self, ent: Entity, comptime Component: type) ?*Component {
    const ptr = self.vtable.get_component_ptr(self.ctx, ent, util.compId(Component)) catch |err| switch (err) {
        error.UnregisteredComponent => std.debug.panic("Cannot get pointer to component of type {s} as it has not been registered.", .{@typeName(Component)}),
    };
    return if (ptr) |p| @ptrCast(@alignCast(p)) else null;
}

/// Queues the removal of all components in lists associated with `ent`
pub fn removeEnt(self: Self, ent: Entity) !void {
    try self.vtable.remove_ent(self.ctx, ent);
}

/// Returns a pointer to the world resource T
pub fn getResPtr(self: Self, comptime T: type) *T {
    const ptr = self.vtable.get_res(self.ctx, ztg.meta.utpOf(T)) catch |err| switch (err) {
        error.UnregisteredResource => std.debug.panic("Cannot access a pointer to resource of type {s} because it was not registered.", .{@typeName(T)}),
    };
    return @ptrCast(@alignCast(ptr));
}

pub fn hasIncluded(self: Self, comptime Namespace: type) bool {
    return self.vtable.has_included(ztg.meta.utpOf(Namespace));
}

pub const RuntimeQuery = struct {
    comp_ptrs: [][]*anyopaque,
    opt_ptrs: [][]?*anyopaque,
    entities: []ztg.Entity,
    len: usize,

    pub fn init(alloc: std.mem.Allocator, req_len: usize, opt_len: usize, list_len: usize) !RuntimeQuery {
        var self: RuntimeQuery = undefined;

        self.comp_ptrs = try alloc.alloc([]*anyopaque, req_len);
        self.opt_ptrs = try alloc.alloc([]?*anyopaque, opt_len);
        self.len = 0;

        for (self.comp_ptrs) |*o| {
            o.* = try alloc.alloc(*anyopaque, list_len);
        }
        for (self.opt_ptrs) |*o| {
            o.* = try alloc.alloc(?*anyopaque, list_len);
            @memset(o.*, null);
        }

        return self;
    }

    pub fn deinit(self: RuntimeQuery, alloc: std.mem.Allocator) void {
        for (self.comp_ptrs) |o| {
            alloc.free(o);
        }
        alloc.free(self.comp_ptrs);
        for (self.opt_ptrs) |o| {
            alloc.free(o);
        }
        alloc.free(self.opt_ptrs);
    }
};

pub fn query(self: Self, alloc: std.mem.Allocator, comptime Query: type) !Query {
    var temp: RuntimeQuery = try self.vtable.query(
        self.ctx,
        alloc,
        Query.has_entities,
        Query.req_utps,
        Query.opt_utps,
        Query.with_utps,
        Query.without_utps,
    );
    errdefer temp.deinit(alloc);

    var out = try Query.init(alloc, temp.len);

    @memcpy(&out.comp_ptrs, temp.comp_ptrs);
    @memcpy(&out.opt_ptrs, temp.opt_ptrs);
    out.len = temp.len;

    if (comptime Query.has_entities) @memcpy(&out.entities, temp.entities);

    return out;
}

const test_mod = struct {
    pub const MyComponent = struct {
        speed: f32,
        dir: ztg.Vec2,
    };

    pub fn update_MyComponent(q: ztg.Query(.{ ztg.base.Transform, MyComponent })) void {
        for (q.items(0), q.items(1)) |tr, c| {
            tr.translate(c.dir.mul(c.speed).extend(0));
        }
    }

    pub fn include(comptime wb: *ztg.WorldBuilder) void {
        wb.include(&.{ztg.base}); // ensure we included ztg.base for the Transform component
        wb.addComponents(&.{MyComponent});
        wb.addSystemsToStage(.update, .{update_MyComponent});
    }
};

const MyWorld = ztg.WorldBuilder.init(&.{ ztg.base, test_mod }).Build();

test "basic usage" {
    var w = try MyWorld.init(std.testing.allocator);
    defer w.deinit();
    const com = w.commands();

    _ = try com.newEntWithMany(.{
        ztg.base.Transform.identity(),
        test_mod.MyComponent{
            .speed = 1_000,
            .dir = ztg.vec2(0.7, 2),
        },
    });
}

test "running stages" {
    var w = try MyWorld.init(std.testing.allocator);
    defer w.deinit();
    const com = w.commands();

    try std.testing.expectEqual(@as(usize, 0), com.getResPtr(ztg.base.Time).frame_count);
    try com.runStage(.update);
    try std.testing.expectEqual(@as(usize, 1), com.getResPtr(ztg.base.Time).frame_count);
    try com.runStageByName("update");
    try std.testing.expectEqual(@as(usize, 2), com.getResPtr(ztg.base.Time).frame_count);
    try com.runStageList(&.{.update});
    try std.testing.expectEqual(@as(usize, 3), com.getResPtr(ztg.base.Time).frame_count);
    try com.runStageNameList(&.{"update"});
    try std.testing.expectEqual(@as(usize, 4), com.getResPtr(ztg.base.Time).frame_count);
}

test "adding/removing entities" {
    var w = try MyWorld.init(std.testing.allocator);
    defer w.deinit();
    const com = w.commands();

    const my_ent = try com.newEntWith(ztg.base.Transform.initWith(.{}));

    if (!my_ent.checkHas(test_mod.MyComponent)) try my_ent.give(test_mod.MyComponent{
        .speed = 50,
        .dir = ztg.Vec2.right(),
    });

    try w.postSystemUpdate();

    const q = try w.query(std.testing.allocator, ztg.Query(.{ ztg.base.Transform, test_mod.MyComponent }));
    defer q.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(f32, 0), q.single(0).getPos().x);
    try com.runStage(.update);
    try std.testing.expectEqual(@as(f32, 50), q.single(0).getPos().x);

    try com.removeEnt(my_ent.ent);
    try w.postSystemUpdate();

    const q2 = try w.query(std.testing.allocator, ztg.Query(.{test_mod.MyComponent}));
    defer q2.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), q2.len);
}
