const std = @import("std");
const ztg = @import("init.zig");
const world = @import("world.zig");

const TypeMap = ztg.meta.TypeMap;
const TypeBuilder = ztg.meta.TypeBuilder;
const World = world.World;

const Self = @This();

const StageLabel = struct {
    name: []const u8,
    before: TypeBuilder = .{ .is_tuple = true },
    during: TypeBuilder = .{ .is_tuple = true },
    after: TypeBuilder = .{ .is_tuple = true },
};

pub const StageDef = struct {
    name: []const u8,
    labels: ztg.meta.ComptimeList(StageLabel),
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
stage_defs: ztg.meta.ComptimeList(StageDef) = .{},

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

const OnEntOverflow = enum {
    /// Invokes OnCrashFn with the CrashReason of .hit_ent_limit
    crash,
    /// Takes the last entity spawned, strips it of its components, and returns it
    overwrite_last,
    /// Takes the first entity spawned, strips it of its components, and returns it
    overwrite_first,
};

/// Passes `includes` to `self.include(...)`
/// Also adds `Allocator` and `Random` resources
pub fn init(comptime includes: []const type) Self {
    var self = Self{};

    for (@typeInfo(default_stages).Struct.decls) |decl| {
        self.stage_defs.append(.{
            .name = decl.name,
            .labels = ztg.meta.ComptimeList(StageLabel).fromSlice(&.{.{ .name = "body" }}),
        });
    }

    self.addResource(std.mem.Allocator, undefined);
    self.addResource(ztg.FrameAlloc, undefined);
    self.addResource(std.rand.Random, undefined);
    self.include(includes);

    return self;
}

/// Calls `include(comptime wb: *WorldBuilder) (!)void` on all structs passed into the `includes` slice.
/// `.init(...)` passes it's arguments to this function.
///
/// You can include a struct more than once without errors/warnings, it's effects will only be applied once.
///
/// Example:
/// ```zig
/// wb.include(&.{ @import("player.zig") });
/// ```
///
/// `player.zig:`
/// ```zig
/// pub fn include(comptime wb: *WorldBuilder) void {
///     wb.addComponents(&.{ Player });
/// }
/// ```
pub fn include(comptime self: *Self, comptime includes: []const type) void {
    for (includes) |TI| {
        if (comptime std.meta.trait.hasFn("include")(TI)) {
            if (comptime self.included.has(TI)) continue; // silent fail

            const ti = @typeInfo(@TypeOf(TI.include));

            if (comptime !(ti.Fn.params.len == 1 and ti.Fn.params[0].type.? == *Self)) {
                @compileError(@typeName(TI) ++ "'s include function's signature must be fn(*WorldBuilder) (!)void");
            }

            if (comptime ztg.meta.canReturnError(@TypeOf(TI.include))) {
                TI.include(self) catch |err| @compileError("Cound not build world, error in include. Error: " ++ err);
            } else {
                TI.include(self);
            }
            self.included.append(TI);
        } else {
            @compileError("Struct " ++ @typeName(TI) ++ " does not have an fn include, it should not be passed to include.");
        }
    }
}

/// Creates a new stage that can be ran and have events added to it
///
/// Example:
/// ```zig
/// wb.addStage(.my_custom_stage);
/// wb.addSystemsToStage(.my_custom_stage, .{mySystem});
///
/// // @TypeOf(world) == wb.Build();
/// world.runStage(.my_custom_stage); // Prints "Hello."
///
/// fn mySystem() void {
///   std.debug.print("Hello.\n", .{});
/// }
/// ```
pub fn addStage(comptime self: *Self, comptime stage_name: ztg.meta.EnumLiteral) void {
    for (self.stage_defs) |sdef| {
        if (std.mem.eql(u8, sdef.name, @tagName(stage_name))) {
            self.warn("Tried to add stage `" ++ sdef.name ++ "` to world more than once.");
            return;
        }
    }

    self.stage_defs.append(.{
        .name = @tagName(stage_name),
        .labels = ztg.meta.ComptimeList(StageLabel).fromSlice(&.{.{ .name = "body" }}),
    });
}

fn stageIndexFromName(comptime self: Self, comptime stage_name: []const u8) usize {
    // if stage is part of DEFAULT_STAGES, we already know the index
    if (@hasDecl(default_stages, stage_name)) return @field(default_stages, stage_name);

    for (self.stage_defs, 0..) |sdef, i| {
        if (std.mem.eql(u8, sdef.name, stage_name)) {
            return i;
        }
    }

    @compileError("Stage " ++ stage_name ++ " is not in world. Consider adding it with WorldBuilder.addStage");
}

fn labelIndexFromName(comptime stage: StageDef, comptime label_name: []const u8) usize {
    for (stage.labels.items, 0..) |label, i| {
        if (std.mem.eql(u8, label.name, label_name)) return i;
    }
    @compileError("Cannot find label " ++ label_name ++ " within stage. Consider adding it with WorldBuilder.addLabel");
}

/// Adds a new label named `label_name` to the system named `stage_name`.
/// This label can then be used to order your systems.
///
/// Each stage has a default label of `.body` which all systems are added
/// to by default.
///
/// Example:
/// ```zig
/// wb.addLabel(.update, .my_early_label, .{ .before = .body });
/// wb.addLabel(.update, .my_label, .default); // default appends it to the end of the label list
///
/// wb.addSystemsToStage(.update, ztg.after(.my_label, mySystem));
/// ```
pub fn addLabel(comptime self: *Self, comptime stage_name: ztg.meta.EnumLiteral, comptime label_name: ztg.meta.EnumLiteral, comptime order: union(enum) {
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
    self.stage_defs.replace(stage_index, stage);
}

/// After you add a component, you can then query for it in your systems:
///
/// ```zig
/// const Player = struct { score: usize };
///
/// // ...
///
/// wb.addComponents(&.{ Player });
///
/// // ...
///
/// pub fn mySystem(q: Query(.{ Player })) void {
///     for (q.items(0)) |pl| {
///         std.debug.print("My score is {}\n", .{ pl.score });
///     }
/// }
/// ```
pub fn addComponents(comptime self: *Self, comptime comps: []const type) void {
    inline for (comps) |T| {
        if (comptime self.comp_types.has(T)) @compileError("Attempted to add type `" ++ @typeName(T) ++ "` to worldbuilder more than once.");
    }
    self.comp_types.appendSlice(comps);
}

/// Resources are unique struct instances that you can request within your systems:
///
/// Example:
/// ```zig
/// const Timer = struct { current: usize };
///
/// wb.addResource(Timer, .{ .current = 0 });
///
/// pub fn mySystem(timer: Timer) void {
///     std.debug.print("{}\n", .{ timer.current });
/// }
///
/// pub fn updateTimer(timer: *Timer) void {
///     timer.current += 1;
/// }
/// ```
pub fn addResource(comptime self: *Self, comptime T: type, comptime default_value: T) void {
    if (comptime T == ztg.Commands) @compileError("`Commands` cannot be a resource type.");
    if (comptime std.meta.trait.isContainer(T) and (@hasDecl(T, "IsQueryType") or @hasDecl(T, "EventSendType") or @hasDecl(T, "EventRecvType"))) @compileError("Queries and Events cannot be resources.");

    if (self.added_resources.has(T)) {
        self.warn("Tried to add resource type `" ++ @typeName(T) ++ "` to world more than once.");
        return;
    }

    self.added_resources.append(T);
    const idx = self.added_resources.indexOf(T).?;
    self.resources.addField(std.fmt.comptimePrint("{}", .{idx}), T, &default_value);
}

/// Registers an event that has a payload of type `T`
///
/// Example:
/// ```zig
/// const Score = struct { total: usize };
/// const PointsGained = struct { amount: usize };
///
/// wb.addEvent(PointsGained);
///
/// pub fn playerUpdate(q: Query(.{ Player, Transform, Box }), points_event: EventSender(PointsGained)) void {
///   for (q.items(0), q.items(1), q.items(2)) |pl, tr, box| {
///     if (pl.isTouchingCoin(tr, box)) points_event.send(.{ .amount = 50 });
///   }
/// }
///
/// pub fn scoreUpdate(score: *Score, points_event: EventReceiver(PointsGained)) void {
///   for (points_event.items) |pe| score.total += pe.amount;
/// }
/// ```
pub fn addEvent(comptime self: *Self, comptime T: type) void {
    if (self.event_types.has(T)) {
        self.warn("Tried to add event type `" ++ @typeName(T) ++ "` to world more than once.");
        return;
    }

    self.event_types.append(T);
}

/// Adds the system to the specified stage
///
/// Example:
/// ```zig
/// wb.addSystemsToStage(.draw, drawPlayer);
/// // or for multiple
/// wb.addSystemsToStage(.draw, .{ drawPlayer, drawEnemy });
/// ```
pub fn addSystemsToStage(comptime self: *Self, comptime stage_tag: @TypeOf(.enum_literal), systems: anytype) void {
    self.addSystemsToStageByName(@tagName(stage_tag), systems);
}

/// Same as `addSystemsToStage` but with a string instead of an enum literal
pub fn addSystemsToStageByName(comptime self: *Self, comptime stage_name: []const u8, _systems: anytype) void {
    const systems = if (comptime !std.meta.trait.isTuple(@TypeOf(_systems))) .{_systems} else _systems;
    const stage_index = comptime self.stageIndexFromName(stage_name);

    for (systems) |sys| {
        switch (@typeInfo(@TypeOf(sys))) {
            .Fn => self.appendToStageLabel(stage_index, "body", .during, sys),
            .Struct => {
                if (!@hasField(@TypeOf(sys), "label")) @compileError("Passed unsupported struct type to addSystems, the only supported structs come from ztg.before(), ztg.during(), and ztg.after().");
                self.appendToStageLabel(stage_index, @tagName(sys.label), sys.offset, sys.f);
            },
            else => @compileError("addSystems expected a tuple of supported types, a member of that tuple was of type `" ++ @typeName(@TypeOf(sys)) ++ "` which is not supported."),
        }
    }
}

fn appendToStageLabel(comptime self: *Self, comptime stage_index: usize, comptime label_name: []const u8, comptime offset: ztg.SystemOrder, sys: anytype) void {
    var stage = self.stage_defs.items[stage_index];

    const label_index = labelIndexFromName(stage, label_name);
    var label = stage.labels.items[label_index];

    switch (offset) {
        .before => label.before.appendTupleFieldExtra(@TypeOf(sys), sys, true, 0),
        .during => label.during.appendTupleFieldExtra(@TypeOf(sys), sys, true, 0),
        .after => label.after.appendTupleFieldExtra(@TypeOf(sys), sys, true, 0),
    }

    stage.labels.replace(label_index, label);
    self.stage_defs.replace(stage_index, stage);
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
pub fn addSystems(comptime self: *Self, system_lists: anytype) void {
    inline for (std.meta.fields(@TypeOf(system_lists))) |list_field| {
        if (!self.hasStageName(list_field.name)) @compileError("Cannot add systems to stage " ++ list_field.name ++ " as it does not exist.");
        const list = @field(system_lists, list_field.name);
        self.addSystemsToStageByName(list_field.name, list);
    }
}

/// Checks whether a stage with the name `stage_name` has been added
/// to the worldbuilder.
pub fn hasStageName(comptime self: *const Self, comptime stage_name: []const u8) bool {
    inline for (self.stage_defs.items) |sdef| {
        if (std.mem.eql(u8, sdef.name, stage_name)) return true;
    }
    return false;
}

/// Shorthand for `addSystemsToStage(.load, ...)`
pub fn addLoadSystems(comptime self: *Self, systems: anytype) void {
    addSystemsToStage(self, .load, systems);
}

/// Shorthand for `addSystemsToStage(.update, ...)`
pub fn addUpdateSystems(comptime self: *Self, systems: anytype) void {
    addSystemsToStage(self, .update, systems);
}

/// Shorthand for `addSystemsToStage(.draw, ...)`
pub fn addDrawSystems(comptime self: *Self, systems: anytype) void {
    addSystemsToStage(self, .draw, systems);
}

fn defaultCrash(com: ztg.Commands, r: ztg.CrashReason) anyerror!void {
    _ = com;
    ztg.log.err("Crashed due to: {}\n", .{r});
}

/// Returns the final World type
pub fn Build(comptime self: Self) type {
    return World(self);
}

fn warn(comptime self: *Self, comptime message: []const u8) void {
    self.warnings = self.warnings ++ message ++ "\n";
}

const test_namespace = struct {
    pub const MyWorld = Self.init(&.{
        ztg.base,
    }).Build();

    pub const MyComponent = struct {
        value: i32,
    };

    pub fn include(comptime wb: *Self) void {
        wb.addComponents(&.{MyComponent});
    }
};

test Self {
    var w = try test_namespace.MyWorld.init(std.testing.allocator);
    defer w.deinit();
}
