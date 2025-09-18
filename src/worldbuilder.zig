//! A comptime only class for constructing World types

const std = @import("std");
const ztg = @import("init.zig");
const util = @import("util.zig");
const world = @import("world.zig");

const TypeMap = ztg.meta.TypeMap;
const TypeBuilder = ztg.meta.TypeBuilder;
const World = world.World;

const WorldBuilder = @This();

const StageLabel = struct {
    name: []const u8,
    before: TypeBuilder = .{ .is_tuple = true },
    during: TypeBuilder = .{ .is_tuple = true },
    after: TypeBuilder = .{ .is_tuple = true },
};

pub const StageDef = struct {
    name: []const u8,
    labels: ztg.ComptimeList(StageLabel),
};

const default_stages = struct {
    // zig fmt: off
    pub const init        = 0;
    pub const load        = 1;
    pub const pre_update  = 2;
    pub const update      = 3;
    pub const post_update = 4;
    pub const draw        = 5;
    pub const deinit      = 6;
    // zig fmt: on
};

warnings: []const u8 = "",

max_entities: usize = 100_000,
stage_defs: ztg.ComptimeList(StageDef) = .{},

comp_types: TypeMap = .{},
event_types: TypeMap = .{},
included: TypeMap = .{},

resources: TypeBuilder = .{},
added_resources: TypeMap = .{},

// TODO: implement
optimize: OptimizeMode = .low_alloc,

on_crash_fn: OnCrashFn = defaultCrash,
on_ent_overflow: OnEntOverflow = .crash,

pub const OnCrashFn = fn (ztg.Commands, ztg.CrashReason) anyerror!void;

// TODO: implement
const OptimizeMode = enum {
    /// (DEFAULT) Pre-allocates everything with a known max. Reduces the number of allocations per frame greatly, but can use a lot of memory with large components
    low_alloc,
    /// Pre-allocates everything except component data
    low_component_mem,
    /// Only allocates when necessary
    low_mem,
};

pub const OnEntOverflow = enum {
    /// Invokes OnCrashFn with the CrashReason of .hit_ent_limit
    crash,
    /// Takes the last entity spawned, strips it of its components, and returns it
    overwrite_last,
    /// Takes the first entity spawned, strips it of its components, and returns it
    overwrite_first,
};

/// Passes `includes` to `self.include(...)`
/// Also adds `Allocator` and `Random` resources
pub fn init(comptime includes: []const type) WorldBuilder {
    var self = WorldBuilder{};

    for (@typeInfo(default_stages).@"struct".decls) |decl| {
        self.stage_defs.append(.{
            .name = decl.name,
            .labels = ztg.ComptimeList(StageLabel).fromSlice(&.{.{ .name = "body" }}),
        });
    }

    self.addResource(std.mem.Allocator, undefined);
    self.addResource(ztg.FrameAlloc, undefined);
    self.addResource(std.Random, undefined);
    self.include(includes);

    return self;
}

/// Calls `include(comptime wb: *WorldBuilder) (!)void` on all structs passed into the `includes` slice.
/// `.init(...)` passes its arguments to this function.
///
/// You can include a struct more than once without errors/warnings, its effects will only be applied once.
pub fn include(comptime self: *WorldBuilder, comptime includes: []const type) void {
    for (includes) |TI| {
        if (comptime std.meta.hasFn(TI, "include")) {
            if (comptime self.included.has(TI)) continue; // silent fail

            const ti = @typeInfo(@TypeOf(TI.include));

            if (comptime !(ti.@"fn".params.len == 1 and ti.@"fn".params[0].type.? == *WorldBuilder))
                util.compileError("{s}'s include function's signature must be fn(*WorldBuilder) (!)void", .{@typeName(TI)});

            if (comptime ztg.meta.canReturnError(@TypeOf(TI.include))) {
                TI.include(self) catch |err| util.compileError("Cound not build world, error in include. Error: {}", .{err});
            } else {
                TI.include(self);
            }
            self.included.append(TI);
        } else {
            util.compileError("Struct {s} does not have an fn include, it should not be passed to include.", .{@typeName(TI)});
        }
    }
}

/// Creates a new stage that can be ran and have systems added to it
pub fn addStage(comptime self: *WorldBuilder, comptime stage_name: ztg.meta.EnumLiteral) void {
    for (self.stage_defs.items) |sdef| {
        if (std.mem.eql(u8, sdef.name, @tagName(stage_name))) {
            self.warn(std.fmt.comptimePrint("Tried to add stage `{s}` to world more than once.", .{sdef.name}));
            return;
        }
    }

    self.stage_defs.append(.{
        .name = @tagName(stage_name),
        .labels = ztg.ComptimeList(StageLabel).fromSlice(&.{.{ .name = "body" }}),
    });
}

test addStage {
    const namespace = struct {
        var stage_was_run: bool = false;

        pub fn include(comptime wb: *WorldBuilder) void {
            wb.addStage(.my_stage);
            wb.addSystemsToStage(.my_stage, mySystem);
            try std.testing.expect(wb.hasStageName("my_stage"));
        }

        fn mySystem() void {
            stage_was_run = true;
        }
    };

    var w = try testWorld(namespace);
    defer w.deinit();

    try w.runStage(.my_stage);
    try std.testing.expect(namespace.stage_was_run);
}

fn stageIndexFromName(comptime self: WorldBuilder, comptime stage_name: []const u8) usize {
    // if stage is part of DEFAULT_STAGES, we already know the index
    if (@hasDecl(default_stages, stage_name)) return @field(default_stages, stage_name);

    for (self.stage_defs.items, 0..) |sdef, i| {
        if (std.mem.eql(u8, sdef.name, stage_name)) {
            return i;
        }
    }

    util.compileError("Stage `{s}` is not in world. Consider adding it with WorldBuilder.addStage", .{stage_name});
}

fn labelIndexFromName(comptime stage: StageDef, comptime label_name: []const u8) usize {
    for (stage.labels.items, 0..) |label, i| {
        if (std.mem.eql(u8, label.name, label_name)) return i;
    }
    util.compileError("Cannot find label `{s}` within stage `{s}`. Consider adding it with WorldBuilder.addLabel", .{ label_name, stage.name });
}

/// Adds a new label named `label_name` to the system named `stage_name`.
/// This label can then be used to order your systems.
///
/// Each stage has a default label of `.body` which all systems are added
/// to by default.
pub fn addLabel(comptime self: *WorldBuilder, comptime stage_name: ztg.meta.EnumLiteral, comptime label_name: ztg.meta.EnumLiteral, comptime order: union(enum) {
    before: ztg.meta.EnumLiteral,
    after: ztg.meta.EnumLiteral,
    default,
}) void {
    const stage_index = self.stageIndexFromName(@tagName(stage_name));
    var stage = self.stage_defs.items[stage_index];

    const index = switch (order) {
        .before => |label| labelIndexFromName(stage, @tagName(label)),
        .after => |label| labelIndexFromName(stage, @tagName(label)) + 1,
        .default => stage.labels.items.len,
    };

    stage.labels.insert(index, .{
        .name = @tagName(label_name),
    });
    self.stage_defs.set(stage_index, stage);
}

test addLabel {
    const namespace = struct {
        var counter: usize = 0;

        pub fn include(comptime wb: *WorldBuilder) void {
            wb.addLabel(.load, .my_label, .{ .before = .body });
            wb.addSystems(.{
                .load = .{
                    load_body_during,
                    ztg.before(.my_label, load_my_label_before),
                    ztg.during(.my_label, load_my_label_during),
                    ztg.after(.my_label, load_my_label_after),
                },
            });
        }

        fn load_my_label_before() !void {
            try std.testing.expectEqual(@as(usize, 0), counter);
            counter += 1;
        }

        fn load_my_label_during() !void {
            try std.testing.expectEqual(@as(usize, 1), counter);
            counter += 1;
        }

        fn load_my_label_after() !void {
            try std.testing.expectEqual(@as(usize, 2), counter);
            counter += 1;
        }

        fn load_body_during() !void {
            try std.testing.expectEqual(@as(usize, 3), counter);
            counter += 1;
        }
    };

    var w = try testWorld(namespace);
    defer w.deinit();

    try w.runStage(.load);
    try std.testing.expectEqual(@as(usize, 4), namespace.counter);
}

/// After you add a component, you can then query for it in your systems
pub fn addComponents(comptime self: *WorldBuilder, comptime comps: []const type) void {
    for (comps) |T| {
        if (comptime self.comp_types.has(T)) util.compileError("Attempted to add type `{s}` to worldbuilder more than once.", .{@typeName(T)});
    }
    self.comp_types.appendSlice(comps);
}

test addComponents {
    var w = try testWorld(struct {
        pub fn include(comptime wb: *WorldBuilder) void {
            wb.addComponents(&.{ MyComponent, MyEmpty, MyEnum, MyUnion });
        }

        const MyComponent = struct {
            value: i32,
        };

        const MyEmpty = struct {};

        const MyEnum = enum {
            a,
            b,
        };

        const MyUnion = union(enum) {
            a: i32,
            b: bool,
        };
    });
    defer w.deinit();
}

/// Adds a resource, which is a struct instance that you can request within your systems
pub fn addResource(comptime self: *WorldBuilder, comptime T: type, comptime default_value: T) void {
    if (comptime T == ztg.Commands) @compileError("`Commands` cannot be a resource type.");
    if (comptime util.isContainer(T) and (@hasDecl(T, "IsQueryType") or @hasDecl(T, "EventSendType") or @hasDecl(T, "EventRecvType")))
        @compileError("Queries and Events cannot be resources.");

    {
        const DT = DerefTypeUntilNonPtr(T);
        for (self.added_resources.types) |ART| {
            if (DT == DerefTypeUntilNonPtr(ART)) @compileError("Cannot add a pointer to a type and the type as different resources, " ++
                "ie a resource of *u32 and u32 cannot exist at the same time. Use a wrapper.");
        }
    }

    if (self.added_resources.has(T)) {
        self.warn(std.fmt.comptimePrint("Tried to add resource type `{s}` to world more than once.", .{@typeName(T)}));
        return;
    }

    self.added_resources.append(T);
    const idx = self.added_resources.types.len - 1;
    self.resources.addField(std.fmt.comptimePrint("{}", .{idx}), T, @ptrCast(&default_value));
}

fn DerefTypeUntilNonPtr(comptime T: type) type {
    var CT = T;
    while (@typeInfo(CT) == .pointer) {
        CT = @typeInfo(CT).pointer.child;
    }
    return CT;
}

test addResource {
    {
        const MyResource = struct { data: i32 = 0 };

        var w = try testWorld(struct {
            pub fn include(comptime wb: *WorldBuilder) void {
                wb.addResource(MyResource, .{ .data = 10 });
                wb.addSystemsToStage(.update, update);
            }

            fn update(res: *MyResource) void {
                res.data += 1;
            }
        });
        defer w.deinit();

        try std.testing.expectEqual(@as(i32, 10), w.getRes(MyResource).data);
        try w.runStage(.update);
        try std.testing.expectEqual(@as(i32, 11), w.getRes(MyResource).data);
    }

    // allow resources to be pointers
    {
        const test_namespace = struct {
            fn initResource(alloc: std.mem.Allocator, res: **u32) !void {
                res.* = try alloc.create(u32);
                res.*.* = 10;
            }

            fn deinitResource(alloc: std.mem.Allocator, res: *u32) void {
                alloc.destroy(res);
            }

            fn requestResource(res: *u32) !void {
                try std.testing.expectEqual(@as(u32, 10), res.*);
            }
        };

        const MyWorld = comptime blk: {
            var wb = WorldBuilder.init(&.{});
            wb.addResource(*u32, undefined);
            wb.addSystems(.{
                .init = test_namespace.initResource,
                .deinit = test_namespace.deinitResource,
                .load = test_namespace.requestResource,
            });
            break :blk wb.Build();
        };

        var w = try MyWorld.init(std.testing.allocator);
        defer w.deinit();

        try w.runStage(.load);
    }
}

/// Registers an event that has a payload of type `T`
pub fn addEvent(comptime self: *WorldBuilder, comptime T: type) void {
    if (self.event_types.has(T)) {
        self.warn(std.fmt.comptimePrint("Tried to add event type `{s}` to world more than once.", .{@typeName(T)}));
        return;
    }

    self.event_types.append(T);
}

test addEvent {
    const MyEvent = struct { data: i32 };
    const namespace = struct {
        var system_was_run = false;

        pub fn include(comptime wb: *WorldBuilder) void {
            wb.addEvent(MyEvent);
            wb.addSystems(.{
                .load = .{ sendEvent, ztg.after(.body, recvEvent) },
            });
        }

        fn sendEvent(send: ztg.EventSender(MyEvent)) !void {
            try send.send(.{ .data = 20 });
        }

        fn recvEvent(recv: ztg.EventReceiver(MyEvent)) !void {
            try std.testing.expectEqual(20, recv.next().?.data);
            system_was_run = true;
        }
    };

    var w = try testWorld(namespace);
    defer w.deinit();

    try w.runStage(.load);
    try std.testing.expect(namespace.system_was_run);
}

/// Adds the system to the specified stage,
/// second argument can take a single system (`sysName`) or multiple in a tuple (`.{sysName1, sysName2}`)
pub fn addSystemsToStage(comptime self: *WorldBuilder, comptime stage_tag: ztg.meta.EnumLiteral, systems: anytype) void {
    self.addSystemsToStageByName(@tagName(stage_tag), systems);
}

/// Same as `addSystemsToStage` but with a string instead of an enum literal
pub fn addSystemsToStageByName(comptime self: *WorldBuilder, comptime stage_name: []const u8, _systems: anytype) void {
    const _systems_ti = @typeInfo(@TypeOf(_systems));
    const systems = if (comptime !(_systems_ti == .@"struct" and _systems_ti.@"struct".is_tuple)) .{_systems} else _systems;
    const stage_index = comptime self.stageIndexFromName(stage_name);

    for (systems) |sys| {
        switch (@typeInfo(@TypeOf(sys))) {
            .@"fn" => self.appendToStageLabel(stage_index, "body", .during, sys),
            .@"struct" => {
                if (!@hasField(@TypeOf(sys), "label")) @compileError("Passed unsupported struct type to addSystems, the only supported structs come from ztg.before(), ztg.during(), ztg.after(), and ztg.orderGroup().");

                if (@hasField(@TypeOf(sys), "groups")) {
                    for (std.meta.fields(@TypeOf(sys.groups))) |group_field| {
                        const group_raw = @field(sys.groups, group_field.name);
                        const group_raw_ti = @typeInfo(@TypeOf(group_raw));
                        const group = if (comptime !(group_raw_ti == .@"struct" and group_raw_ti.@"struct".is_tuple)) .{group_raw} else group_raw;

                        for (group) |s| {
                            const ordering = std.meta.stringToEnum(ztg.SystemOrder, group_field.name) orelse
                                util.compileError("{s} is not a supported label group, supported label groups are .before, .during, and .after", .{group_field.name});

                            self.appendToStageLabel(stage_index, @tagName(sys.label), ordering, s);
                        }
                    }
                } else {
                    self.appendToStageLabel(stage_index, @tagName(sys.label), sys.offset, sys.f);
                }
            },
            else => util.compileError("addSystems expected a tuple of supported types, a member of that tuple was of type `{s}` which is not supported.", .{@typeName(@TypeOf(sys))}),
        }
    }
}

fn appendToStageLabel(comptime self: *WorldBuilder, comptime stage_index: usize, comptime label_name: []const u8, comptime offset: ztg.SystemOrder, sys: anytype) void {
    var stage = self.stage_defs.items[stage_index];

    const label_index = labelIndexFromName(stage, label_name);
    var label = stage.labels.items[label_index];

    switch (offset) {
        .before => label.before.appendTupleFieldExtra(@TypeOf(sys), sys, true, 0),
        .during => label.during.appendTupleFieldExtra(@TypeOf(sys), sys, true, 0),
        .after => label.after.appendTupleFieldExtra(@TypeOf(sys), sys, true, 0),
    }

    stage.labels.set(label_index, label);
    self.stage_defs.set(stage_index, stage);
}

/// Useful for adding systems to multiple stages.
///
/// Example:
/// ```zig
/// wb.addSystems(.{
///   .load = .{myLoadSystem},
///   .update = .{myUpdateSystem},
///   .draw = .{myDrawSystem}
/// });
/// ```
pub fn addSystems(comptime self: *WorldBuilder, system_lists: anytype) void {
    for (std.meta.fields(@TypeOf(system_lists))) |list_field| {
        if (!self.hasStageName(list_field.name)) util.compileError("Cannot add systems to stage `{s}` as it does not exist.", .{list_field.name});
        const list = @field(system_lists, list_field.name);
        self.addSystemsToStageByName(list_field.name, list);
    }
}

/// Checks whether a stage with the name `stage_name` has been added
/// to the worldbuilder.
pub fn hasStageName(comptime self: *const WorldBuilder, comptime stage_name: []const u8) bool {
    for (self.stage_defs.items) |sdef| {
        if (std.mem.eql(u8, sdef.name, stage_name)) return true;
    }
    return false;
}

fn defaultCrash(com: ztg.Commands, r: ztg.CrashReason) anyerror!void {
    _ = com;
    ztg.log.err("Crashed due to: {}\n", .{r});
}

/// Returns the final World type
pub fn Build(comptime self: WorldBuilder) type {
    verifyQueryTypes(self.stage_defs.items, self.comp_types.types);

    const comp_types = self.comp_types.dereference(self.comp_types.types.len);
    const event_types = self.event_types.dereference(self.event_types.types.len);
    const added_resources = self.added_resources.dereference(self.added_resources.types.len);
    const included = self.included.dereference(self.included.types.len);
    const on_ent_overflow = self.on_ent_overflow;
    const on_crash_fn = self.on_crash_fn;
    const warnings = self.warnings[0..].*;

    const Resources = self.resources.Build();
    const EventPool = @import("events.zig").EventPools(event_types);
    const StagesList = @import("stages.zig").Init(self.stage_defs.items);

    return World(
        self.max_entities,
        Resources,
        comp_types,
        StagesList,
        EventPool,
        added_resources,
        included,
        on_ent_overflow,
        on_crash_fn,
        warnings,
    );
}

/// Check added systems query parameters, if one of their query types isnt in the comp_types list, compile error
fn verifyQueryTypes(stages: []const StageDef, comp_types: []const type) void {
    for (stages) |stage| for (stage.labels.items) |label| inline for (.{ "before", "during", "after" }) |section_name| {
        const section: TypeBuilder = @field(label, section_name);
        for (section.fields) |field| {
            const system_ti = @typeInfo(field.type).@"fn";
            for (system_ti.params) |param| {
                const Param = param.type.?;
                if (@typeInfo(Param) != .@"struct" or !@hasDecl(Param, "req_types")) continue;

                inline for (.{ Param.req_types, Param.opt_types }) |query_types| for (query_types.types) |T| {
                    if (!util.typeArrayHas(comp_types, T)) {
                        util.compileError("System `{s}` contains a query for type `{s}`, which is not a registered component type. Add it with addComponents", .{
                            @typeName(field.type),
                            @typeName(T),
                        });
                    }
                };
            }
        }
    };
}

fn warn(comptime self: *WorldBuilder, comptime message: []const u8) void {
    self.warnings = std.fmt.comptimePrint("{s}{s}\n", .{ self.warnings, message });
}

fn testWorld(comptime namespace: type) !WorldBuilder.init(&.{namespace}).Build() {
    return .init(std.testing.allocator);
}

test WorldBuilder {
    var w = try testWorld(ztg.base);
    defer w.deinit();
}

test "adding systems" {
    const namespace = struct {
        var stages_were_run = [_]bool{false} ** 5;

        pub fn include(comptime wb: *WorldBuilder) void {
            wb.addSystemsToStage(.load, sys0);
            wb.addSystemsToStageByName("load", sys1);
            wb.addSystems(.{ .load = load, .update = update, .draw = draw });
        }

        fn sys0() void {
            stages_were_run[0] = true;
        }

        fn sys1() void {
            stages_were_run[1] = true;
        }

        fn load() void {
            stages_were_run[2] = true;
        }

        fn update() void {
            stages_were_run[3] = true;
        }

        fn draw() void {
            stages_were_run[4] = true;
        }
    };

    var w = try testWorld(namespace);
    defer w.deinit();

    try w.runStage(.load);
    try w.runUpdateStages();
    try w.runStage(.draw);

    try std.testing.expect(namespace.stages_were_run[0]);
    try std.testing.expect(namespace.stages_were_run[1]);
    try std.testing.expect(namespace.stages_were_run[2]);
    try std.testing.expect(namespace.stages_were_run[3]);
    try std.testing.expect(namespace.stages_were_run[4]);
}
