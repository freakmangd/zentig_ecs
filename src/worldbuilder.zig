const std = @import("std");
const TypeBuilder = @import("type_builder.zig");
const TypeMap = @import("type_map.zig");
const ztg = @import("init.zig");
const util = @import("util.zig");
const base = @import("mods/base.zig");
const physics = @import("mods/physics.zig");
const world = @import("world.zig");

const Entity = @import("ecs.zig").Entity;
const World = world.World;

const Self = @This();

pub const StageDef = struct {
    name: []const u8,
    def: TypeBuilder,
};

const default_stages = struct {
    // zig fmt: off
    const setup       = 0;
    const pre_init    = 1;
    const init        = 2;
    const post_init   = 3;
    const pre_update  = 4;
    const update      = 5;
    const post_update = 6;
    const pre_draw    = 7;
    const draw        = 8;
    const post_draw   = 9;
    const cleanup     = 10;
    // zig fmt: on
};

warnings: []const u8 = "",

max_entities: usize = 20_000,
stage_defs: []const StageDef = &.{},

comp_types: TypeMap = .{},
event_types: TypeMap = .{},
included: TypeMap = .{},

resources: TypeBuilder,
added_resources: TypeMap = .{},

// TODO: implement
optimize: OptimizeMode = .low_alloc,

on_crash_fn: ztg.OnCrashFn = defaultCrash,
on_ent_overflow: OnEntOverflow = .crash,

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

pub fn init(comptime includes: []const type) Self {
    var self = Self{
        .resources = TypeBuilder.init(false, .Auto),
    };

    for (@typeInfo(default_stages).Struct.decls) |decl| {
        self.stage_defs = self.stage_defs ++ .{.{
            .name = decl.name,
            .def = TypeBuilder.init(true, .Auto),
        }};
    }

    self.include(includes);
    self.addResource(std.mem.Allocator, undefined);
    self.addResource(std.rand.Random, undefined);

    return self;
}

/// Calls `include(comptime wb: *WorldBuilder) !void` on all structs passed into the `includes` tuple.
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
/// pub fn include(comptime wb: *WorldBuilder) !void {
///     wb.addComponents(&.{ Player });
/// }
/// ```
pub fn include(comptime self: *Self, comptime includes: []const type) void {
    inline for (includes) |inc| {
        if (comptime std.meta.trait.hasFn("include")(inc)) {
            if (comptime self.included.has(inc)) return; // silent fail

            const ti = @typeInfo(@TypeOf(inc.include));
            if (comptime ti != .Fn) @compileError("A type's include decl must be a function.");

            if (comptime !(ti.Fn.params.len == 1 and ti.Fn.params[0].type.? == *Self)) {
                @compileError(@typeName(inc) ++ "'s include function's signature must be fn(*WorldBuilder) (!)void");
            }

            if (comptime util.canReturnError(@TypeOf(inc.include))) {
                inc.include(self) catch |err| @compileError("Cound not build world, error in include. Error: " ++ err);
            } else {
                inc.include(self);
            }
            self.included.append(inc);
        } else {
            @compileError("Struct " ++ @typeName(inc) ++ " does not have an fn include, it should not be passed to include.");
        }
    }
}

pub fn addStage(comptime self: *Self, comptime stage_name: @TypeOf(.enum_literal)) void {
    for (self.stage_defs) |sdef| {
        if (std.mem.eql(u8, sdef.name, @tagName(stage_name))) {
            self.warn("Tried to add stage `" ++ sdef.name ++ "` to world more than once.");
            return;
        }
    }

    self.stage_defs = self.stage_defs ++ .{.{
        .name = @tagName(stage_name),
        .def = TypeBuilder.init(true, .Auto),
    }};
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
///     for (q.items(.a)) |pl| {
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

/// Resources are unique struct instances that you can get within your systems:
///
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
    if (comptime std.meta.trait.isContainer(T) and (@hasDecl(T, "query_types") or @hasDecl(T, "EventSendType") or @hasDecl(T, "EventRecvType"))) @compileError("Queries and Events cannot be resources.");

    if (self.added_resources.has(T)) {
        self.warn("Tried to add resource type `" ++ @typeName(T) ++ "` to world more than once.");
        return;
    }

    self.added_resources.append(T);
    const idx = self.added_resources.indexOf(T).?;
    self.resources.addField(std.fmt.comptimePrint("{}", .{idx}), T, &default_value);
}

pub fn addEvent(comptime self: *Self, comptime T: type) void {
    if (self.event_types.has(T)) {
        self.warn("Tried to add event type `" ++ @typeName(T) ++ "` to world more than once.");
        return;
    }

    self.event_types.append(T);
}

/// Example:
///
/// ```zig
/// wb.addSystemsToStage(.draw, .{ drawPlayer });
/// ```
pub fn addSystemsToStage(comptime self: *Self, comptime stage_tag: @TypeOf(.enum_literal), systems: anytype) void {
    if (comptime !std.meta.trait.isTuple(@TypeOf(systems))) @compileError("Expected tuple for @TypeOf(systems).");

    const stage_name = @tagName(stage_tag);

    // if stage is part of DEFAULT_STAGES, we already know the index
    if (comptime @hasDecl(default_stages, stage_name)) {
        const stage_index = @field(default_stages, stage_name);
        addSystemsToStage_final(self, stage_index, systems);
        return;
    }

    for (self.stage_defs, 0..) |sdef, i| {
        if (std.mem.eql(u8, sdef.name, stage_name)) {
            addSystemsToStage_final(self, i, systems);
            return;
        }
    }

    @compileError("Stage " ++ stage_name ++ " is not in world.");
}

fn addSystemsToStage_final(comptime self: *Self, stage_index: usize, systems: anytype) void {
    var stage_defs: [self.stage_defs.len]StageDef = undefined;
    std.mem.copy(StageDef, &stage_defs, self.stage_defs);

    for (systems) |sys| {
        stage_defs[stage_index].def.addTupleField(stage_defs[stage_index].def.type_def.fields.len, comptime @TypeOf(sys), &sys);
    }

    self.stage_defs = &stage_defs;
}

/// Shorthand for `addSystemsToStage(.init, ...)`
pub fn addInitSystems(comptime self: *Self, systems: anytype) void {
    addSystemsToStage(self, .init, systems);
}

/// Shorthand for `addSystemsToStage(.update, ...)`
pub fn addUpdateSystems(comptime self: *Self, systems: anytype) void {
    addSystemsToStage(self, .update, systems);
}

/// Shorthand for `addSystemsToStage(.update, ...)`
pub fn addDrawSystems(comptime self: *Self, systems: anytype) void {
    addSystemsToStage(self, .draw, systems);
}

/// Set the crash handler function, returning .success from the function prevents the crash.
/// Only return .success if you are sure you have fixed the CrashReason.
pub fn setCrashFn(comptime self: *Self, comptime f: ztg.OnCrashFn) void {
    self.on_crash_fn = f;
}

fn defaultCrash(com: ztg.Commands, r: ztg.CrashReason) anyerror!ztg.Status {
    _ = com;
    std.log.err("Crashed due to: {}\n", .{r});
    return .failure;
}

/// Returns the final World type
pub fn Build(comptime self: Self) type {
    if (self.max_entities > 500_000) self.warn("It isn't recommended to have a max_entities count over 500,000 as it could cause unstable performance.");
    return World(self);
}

fn warn(comptime self: *Self, comptime message: []const u8) void {
    self.warnings = self.warnings ++ message ++ "\n";
}

test Self {
    const MyWorld = Self.init(&.{
        base,
        physics,
    }).Build();
    _ = MyWorld;
}
