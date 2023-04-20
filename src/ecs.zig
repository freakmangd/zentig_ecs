const std = @import("std");
const testing = std.testing;
const util = @import("util.zig");
const TypeBuilder = @import("type_builder.zig");
const Allocator = std.mem.Allocator;

pub usingnamespace util;
pub const base = @import("base.zig");
pub const physics = @import("physics.zig");

pub const Entity = usize;

const STAGES_LIST = struct {
    PRE_INIT: usize = 0,
    INIT: usize = 1,
    POST_INIT: usize = 2,
    PRE_UPDATE: usize = 3,
    UPDATE: usize = 4,
    POST_UPDATE: usize = 5,
    PRE_DRAW: usize = 6,
    DRAW: usize = 7,
    POST_DRAW: usize = 8,
};
pub const stages = STAGES_LIST{};

pub const WorldBuilder = struct {
    const Self = @This();

    const StageDef = struct {
        name: []const u8,
        def: TypeBuilder,
    };

    const DEFAULT_STAGES = [_][]const u8{
        "PRE_INIT",
        "INIT",
        "POST_INIT",
        "PRE_UPDATE",
        "UPDATE",
        "POST_UPDATE",
        "PRE_DRAW",
        "DRAW",
        "POST_DRAW",
    };

    compholder: TypeBuilder,
    resources: TypeBuilder,
    stage_defs: []const StageDef,
    include_list: []const type,

    pub fn new() Self {
        var self = Self{
            .compholder = TypeBuilder.new(false, .Auto),
            .resources = TypeBuilder.new(false, .Auto),
            .stage_defs = &.{},
            .include_list = &.{},
        };

        for (DEFAULT_STAGES) |name| {
            self.stage_defs = self.stage_defs ++ &[_]StageDef{.{
                .name = name,
                .def = TypeBuilder.new(true, .Auto),
            }};
        }

        return self;
    }

    pub fn include(comptime self: *Self, comptime includes: anytype) void {
        inline for (includes) |inc| {
            if (comptime std.meta.trait.hasFn("include")(inc)) {
                inc.include(self) catch |err| @compileError("Cound not build world, error in include. Error: " ++ err);
            } else if (comptime !std.meta.trait.hasFn("register")(inc)) {
                @compileError("Included struct " ++ @typeName(inc) ++ " has neither an include fn nor a register fn, make sure you're not supposed to add a field of the struct");
            }
        }
        self.include_list = self.include_list ++ includes;
    }

    pub fn addComponents(comptime self: *Self, comps: anytype) void {
        for (comps) |Comp| {
            self.compholder = self.compholder.addField(@typeName(Comp), std.AutoArrayHashMap(Entity, Comp), null);
        }
    }

    pub fn addResource(comptime self: *Self, comptime T: type, default_value: T) void {
        self.resources = self.resources.addField(@typeName(T), T, &default_value);
    }

    // TODO: This function sucks ass
    pub fn addSystemsToStage(comptime self: *Self, comptime stage_name: []const u8, systems: anytype) void {
        for (self.stage_defs, 0..) |sdef, i| {
            if (std.mem.eql(u8, sdef.name, stage_name)) {
                var _sdef = sdef;

                for (systems) |sys| {
                    _sdef.def = _sdef.def.addTupleField(sdef.def.type_def.fields.len, comptime @TypeOf(sys), &sys);
                }

                var _stage_defs: [self.stage_defs.len]StageDef = undefined;
                std.mem.copy(StageDef, &_stage_defs, self.stage_defs);

                _stage_defs[i] = _sdef;

                self.stage_defs = &_stage_defs;
                break;
            }
        }
    }

    pub fn addUpdateSystems(comptime self: *Self, systems: anytype) void {
        addSystemsToStage(self, "UPDATE", systems);
    }

    pub fn Stages(comptime Inner: type) type {
        return struct {
            // inner: struct {
            //   UPDATE: tuple {
            //     *const fn (Alloc, Query(...)) anyerror!void = @import("...").system_fn,
            //     *const fn (Alloc, Query(...), Query(...)) anyerror!void = @import("...").system_fn,
            //     ...
            //   },
            //   ...
            // }
            inner: Inner,

            pub fn runStage(this: @This(), world: anytype, comptime stage_name: []const u8) anyerror!void {
                const stage = @field(this.inner, stage_name);

                inline for (std.meta.fields(@TypeOf(stage))) |stage_field| {
                    var args = try getArgsForSystem(world, std.meta.Child(stage_field.type));
                    defer deinitArgsForSystem(&args, world.alloc);

                    if (@TypeOf(args[0]) == Allocator) {
                        args[0] = world.alloc;
                    }

                    try @call(.auto, @field(stage, stage_field.name), args);
                }
            }
        };
    }

    pub fn Build(comptime self: Self) type {
        return World(self.compholder.Build(), self.resources.Build(), Stages(CompileStagesList(self.stage_defs)));
    }

    fn getArgsForSystem(world: anytype, comptime SysFn: type) anyerror!std.meta.ArgsTuple(SysFn) {
        var out: std.meta.ArgsTuple(SysFn) = undefined;

        inline for (out, 0..) |param, i| {
            const Param = @TypeOf(param);

            if (Param == Allocator) {
                if (i == 0) continue;
                @compileError("A system argument of Allocator must be the first argument.");
            }

            const queryTypeInfo = std.meta.fieldInfo(MultiArrayListElem(Param), .QueryType);
            const optsTypeInfo = std.meta.fieldInfo(MultiArrayListElem(Param), .OptionsType);

            out[i] = try world.query(
                @ptrCast(
                    *const queryTypeInfo.type,
                    queryTypeInfo.default_value.?,
                ).*,
                @ptrCast(
                    *const optsTypeInfo.type,
                    optsTypeInfo.default_value.?,
                ).*,
            );
        }

        return out;
    }

    fn deinitArgsForSystem(args: anytype, alloc: Allocator) void {
        inline for (std.meta.fields(@TypeOf(args.*))) |args_field| {
            if (args_field.type == Allocator) continue;

            if (@hasDecl(args_field.type, "deinit")) {
                @field(args, args_field.name).deinit(alloc);
            }
        }
    }

    fn CompileStagesList(comptime stage_defs: []const StageDef) type {
        var final = TypeBuilder.new(false, .Auto);
        for (stage_defs) |sdef| {
            const Stage = sdef.def.Build();
            final = final.addField(sdef.name, Stage, null);
        }
        return final.Build();
    }
};

const MyWorld = blk: {
    var wb = WorldBuilder.new();
    wb.include(.{
        base.Init(.{}),
        physics.Init(),
    });
    break :blk wb.Build();
};

test WorldBuilder {
    _ = MyWorld;
}

fn World(comptime CompHolder: type, comptime Resources: type, comptime StagesList: type) type {
    return struct {
        const Self = @This();

        alloc: Allocator,

        entities: std.ArrayList(Entity),
        next_ent: Entity = 0,

        stages_list: StagesList,
        components: CompHolder,
        resources: Resources,

        pub fn init(alloc: Allocator) !Self {
            var self = Self{
                .alloc = alloc,
                .stages_list = .{ .inner = .{} },
                .components = undefined,
                .resources = .{},
                .entities = std.ArrayList(Entity).init(alloc),
                .next_ent = 0,
            };

            inline for (std.meta.fields(CompHolder)) |field| {
                @field(self.components, field.name) = field.type.init(alloc);
            }

            return self;
        }

        pub fn deinit(self: *Self) void {
            self.entities.deinit();

            for (self.stages_list.items) |stage| {
                stage.deinit();
            }

            self.stages_list.deinit();

            inline for (std.meta.fields(CompHolder)) |field| {
                @field(self.components, field.name).deinit();
            }
        }

        pub fn runStageList(self: *Self, stage_ids: []const []const u8) anyerror!void {
            for (stage_ids) |sid| {
                try runStage(self, sid);
            }
        }

        pub fn runStage(self: *Self, comptime stage_id: []const u8) anyerror!void {
            self.stages_list.runStage(self, stage_id);
        }

        pub fn runInitStages(self: *Self) anyerror!void {
            inline for (.{ stages.PRE_INIT, stages.INIT, stages.POST_INIT }) |stage| {
                try runStage(self, stage);
            }
        }

        pub fn runUpdateStages(self: *Self) anyerror!void {
            inline for (.{ stages.PRE_UPDATE, stages.UPDATE, stages.POST_UPDATE }) |stage| {
                try runStage(self, stage);
            }
        }

        pub fn runDrawStages(self: *Self) anyerror!void {
            inline for (.{ stages.PRE_DRAW, stages.DRAW, stages.POST_DRAW }) |stage| {
                try runStage(self, stage);
            }
        }

        pub fn newEnt(self: *Self) !Entity {
            try self.entities.append(self.next_ent);
            self.next_ent += 1;
            return self.next_ent - 1;
        }

        pub fn giveEnt(self: *Self, ent: Entity, comptime Component: type, comp: Component) Allocator.Error!void {
            try self.getListOf(Component).put(ent, comp);
        }

        pub fn giveEntMany(self: *Self, ent: Entity, components: anytype) Allocator.Error!void {
            inline for (std.meta.fields(@TypeOf(components))) |field| {
                try self.getListOf(field.type).put(ent, @field(components, field.name));
            }
        }

        pub fn giveEntBundle(self: *Self, ent: Entity, comptime Bundle: type, bundle: Bundle) Allocator.Error!void {
            inline for (std.meta.fields(Bundle)) |field| {
                try self.getListOf(field.type).put(ent, @field(bundle, field.name));
            }
        }

        pub fn query(self: *Self, comptime q: anytype, comptime options: anytype) !Query(q, options) {
            comptime {
                inline for (q) |Q| {
                    assertComponent(Q);
                }
            }

            var result = Query(q, options){};

            var comp0s = self.getListOf(q[0]);
            var comp0_iter = comp0s.iterator();

            comp_loop: while (comp0_iter.next()) |comp| {
                var res_item: Query(q, options).Elem = undefined;

                inline for (q, 0..) |Q, i| {
                    if (i == 0) {
                        res_item[i] = comp.value_ptr;
                        continue;
                    }

                    var other_q = self.getListOf(Q);
                    if (!other_q.contains(comp.key_ptr.*)) continue :comp_loop;

                    res_item[i] = other_q.getPtr(comp.key_ptr.*).?;
                }

                try result.append(self.alloc, res_item);
            }

            return result;
        }

        pub fn getRes(self: Self, comptime T: type) T {
            return @field(self.resources, @typeName(T));
        }

        pub fn getResPtr(self: *Self, comptime T: type) *T {
            return &@field(self.resources, @typeName(T));
        }

        fn assertComponent(comptime Component: type) void {
            comptime {
                if (!std.meta.trait.hasField(@typeName(Component))(CompHolder)) {
                    @compileError("Cannot use component of type stages." ++ @typeName(Component) ++ " as it has not been added to the world.");
                }
            }
        }

        fn getListOf(self: *Self, comptime Component: type) *std.AutoArrayHashMap(Entity, Component) {
            comptime assertComponent(Component);
            return &@field(self.components, @typeName(Component));
        }
    };
}

test "Resources" {
    var world = try MyWorld.init(testing.allocator);
    defer world.deinit();

    try testing.expectEqual(@as(usize, 0), world.getRes(base.Time).frameCount);

    try world.runUpdateStages();

    try testing.expectEqual(@as(usize, 1), world.getRes(base.Time).frameCount);

    var time = world.getResPtr(base.Time);
    time.frameCount = 100;

    try testing.expectEqual(@as(usize, 100), world.getRes(base.Time).frameCount);
}

/// Takes tuple: { Player, Position, Sprite } and returns
/// a MultiArrayList of a struct of pointers labeled a-z: { a: *Player, b: *Position, c: *Sprite }
pub fn Query(comptime q: anytype, comptime options: anytype) type {
    var tb = TypeBuilder.new(false, .Auto);
    inline for (q, 0..) |Q, i| {
        tb = tb.addField(&[1]u8{97 + i}, *Q, null);
    }
    tb = tb.addField("QueryType", @TypeOf(q), &q).addField("OptionsType", @TypeOf(options), &options);
    return std.MultiArrayList(tb.Build());
}

fn MultiArrayListElem(comptime T: type) type {
    return @typeInfo(@TypeOf(T.pop)).Fn.return_type.?;
}
