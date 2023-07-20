const std = @import("std");
const ztg = @import("init.zig");
const ca = @import("component_array.zig");
const world = @import("world.zig");

const Allocator = std.mem.Allocator;
const TypeMap = ztg.meta.TypeMap;
const Entity = ztg.Entity;

const Self = @This();

ctx: *anyopaque,
vtable: *const Vtable,

pub const Vtable = struct {
    new_ent_fn: *const fn (*anyopaque) Allocator.Error!Entity,
    remove_ent_fn: *const fn (*anyopaque, Entity) Allocator.Error!void,
    add_component_fn: *const fn (*anyopaque, Entity, ztg.meta.UniqueTypePtr, *const anyopaque) world.CommandsGiveEntError!void,
    run_stage_fn: *const fn (*anyopaque, []const u8) anyerror!void,
    get_res_fn: *const fn (*anyopaque, ztg.meta.UniqueTypePtr) *anyopaque,
    check_ent_has_fn: *const fn (*anyopaque, Entity, ztg.meta.UniqueTypePtr) bool,
};

/// If you are going to run multiple stages in a row, consider `.runStageList()`
///
/// Example:
/// ```zig
/// com.runStage(.render);
/// ```
pub inline fn runStage(self: Self, comptime stage_id: @TypeOf(.enum_literal)) anyerror!void {
    try self.vtable.run_stage_fn(self.ctx, @tagName(stage_id));
}

/// If you are going to run multiple stages in a row, consider `.runStageNameList()`
///
/// Example:
/// ```zig
/// com.runStageByName("render");
/// ```
pub inline fn runStageByName(self: Self, stage_id: []const u8) anyerror!void {
    try self.vtable.run_stage_fn(self.ctx, stage_id);
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
pub inline fn newEnt(self: Self) Allocator.Error!ztg.EntityHandle {
    return .{ .ent = try self.vtable.new_ent_fn(self.ctx), .com = self };
}

/// Shortcut for creating a new entity and adding one component to it
pub fn newEntWith(self: Self, component: anytype) !ztg.EntityHandle {
    const ent = try newEnt(self);
    try ent.giveEnt(component);
    return ent;
}

/// Shortcut for creating a new entity and adding many components to it
pub fn newEntWithMany(self: Self, components: anytype) !ztg.EntityHandle {
    const ent = try newEnt(self);
    try ent.giveEntMany(components);
    return ent;
}

/// Adds a component to the entity `ent`. If the component cannot be added without invalidating
/// pointers, it will be queued to be added after the current system finishes.
pub fn giveEnt(self: Self, ent: Entity, component: anytype) !void {
    self.vtable.add_component_fn(self.ctx, ent, ztg.meta.uniqueTypePtr(@TypeOf(component)), &component) catch |err| switch (err) {
        error.UnregisteredComponent => std.debug.panic("Cannot give ent {} a component of type {s} as it has not been registered.", .{ ent, @typeName(@TypeOf(component)) }),
        else => return err,
    };
}

/// Adds every field in the components object to its component list at the Entity index
pub fn giveEntMany(self: Self, ent: Entity, components: anytype) !void {
    inline for (std.meta.fields(@TypeOf(components))) |field| {
        try giveEnt(self, ent, @field(components, field.name));
    }
}

/// Returns true or false depending on whether ent has the component of type `Component`
pub fn checkEntHas(self: Self, ent: Entity, comptime Component: type) bool {
    return self.vtable.check_ent_has_fn(self.ctx, ent, ztg.meta.uniqueTypePtr(Component));
}

/// Queues the removal of all components in lists correlated with `ent`
pub fn removeEnt(self: Self, ent: Entity) !void {
    try self.vtable.remove_ent_fn(self.ctx, ent);
}

/// Returns a pointer to the world resource T
pub fn getResPtr(self: Self, comptime T: type) *T {
    return @ptrCast(@alignCast(self.vtable.get_res_fn(self.ctx, ztg.meta.uniqueTypePtr(T))));
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
        ztg.base.Transform.default(),
        test_mod.MyComponent{
            .speed = 1_000,
            .dir = ztg.Vec2.init(0.7, 2),
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

    if (!my_ent.checkEntHas(test_mod.MyComponent)) try my_ent.giveEnt(test_mod.MyComponent{
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
