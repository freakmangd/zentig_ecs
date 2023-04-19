// archive of old version of WorldBuilder,
// which only uses include

const std = @import("std");
const testing = std.testing;
const util = @import("util.zig");
const TypeBuilder = @import("type_builder.zig");
const Allocator = std.mem.Allocator;

pub usingnamespace util;
pub const base = @import("base.zig");

pub const Entity = usize;

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
    stage_defs: []const StageDef,

    pub fn new() Self {
        var self = Self{
            .compholder = TypeBuilder.new(false, .Auto),
            .stage_defs = &.{},
        };

        for (DEFAULT_STAGES) |name| {
            self.stage_defs = self.stage_defs ++ &[_]StageDef{.{
                .name = name,
                .def = TypeBuilder.new(true, .Auto),
            }};
        }

        return self;
    }

    pub fn include(comptime self: *Self, comptime includes: []const *const fn (comptime *WorldBuilder) anyerror!void) anyerror!void {
        inline for (includes) |inc| {
            try inc(self);
        }
    }

    pub fn addComponents(comptime self: *Self, comps: anytype) void {
        for (comps) |Comp| {
            self.compholder = self.compholder.addField(@typeName(Comp), std.AutoArrayHashMap(Entity, Comp), null);
        }
    }

    // TODO: This function sucks ass
    pub fn addSystemsToStage(comptime self: *Self, comptime stage_name: []const u8, systems: anytype) void {
        for (self.stage_defs, 0..) |sdef, i| {
            if (std.mem.eql(u8, sdef.name, stage_name)) {
                var _sdef = sdef;

                for (systems) |sys| {
                    _sdef.def = _sdef.def.addTupleField(sdef.def.type_def.fields.len, *const @TypeOf(sys), &sys);
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

            pub fn runStage(stages: @This(), world: anytype, comptime stage_name: []const u8) anyerror!void {
                const stage = @field(stages.inner, stage_name);

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
        const CompHolder = self.compholder.Build();
        return World(CompHolder, Stages(CompileStagesList(self.stage_defs)));
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

    fn CompileStagesList(comptime stages: []const StageDef) type {
        var final = TypeBuilder.new(false, .Auto);
        for (stages) |sdef| {
            const Stage = sdef.def.Build();
            final = final.addField(sdef.name, Stage, null);
        }
        return final.Build();
    }
};

test WorldBuilder {
    const MyWorld = comptime blk: {
        var wb = WorldBuilder.new();
        try wb.include(&.{
            base.register,
            game_file.register,
        });
        break :blk wb.Build();
    };
    _ = MyWorld;
}

fn World(comptime CompHolder: type, comptime Stages: type) type {
    return struct {
        const Self = @This();

        alloc: Allocator,

        entities: std.ArrayList(Entity),
        next_ent: Entity = 0,

        stages: Stages,
        components: CompHolder,

        pub fn init(alloc: Allocator) !Self {
            var self = Self{
                .alloc = alloc,
                .stages = .{ .inner = undefined },
                .components = undefined,
                .entities = std.ArrayList(Entity).init(alloc),
                .next_ent = 0,
            };

            inline for (std.meta.fields(CompHolder)) |field| {
                @field(self.components, field.name) = field.type.init(alloc);
            }

            inline for (std.meta.fields(@TypeOf(self.stages.inner))) |field| {
                @field(self.stages.inner, field.name) = field.type{};
            }

            return self;
        }

        pub fn deinit(self: Self) void {
            self.entities.deinit();
        }

        pub fn runStageList(self: *Self, stage_names: []const []const u8) anyerror!void {
            for (stage_names) |sid| {
                try self.stages.runStage(self, sid);
            }
        }

        pub fn runStage(self: *Self, comptime stage_name: []const u8) anyerror!void {
            try self.stages.runStage(self, stage_name);
        }

        pub fn runInitStages(self: *Self) anyerror!void {
            inline for (.{ "PRE_INIT", "INIT", "POST_INIT" }) |stage| {
                try runStage(self, stage);
            }
        }

        pub fn runUpdateStages(self: *Self) anyerror!void {
            inline for (.{ "PRE_UPDATE", "UPDATE", "POST_UPDATE" }) |stage| {
                try runStage(self, stage);
            }
        }

        pub fn runDrawStages(self: *Self) anyerror!void {
            inline for (.{ "PRE_DRAW", "DRAW", "POST_DRAW" }) |stage| {
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
            if (std.meta.trait.isTuple(Bundle)) {
                inline for (std.meta.fields(Bundle)) |field| {
                    try self.getListOf(field.type).put(ent, @field(bundle, field.name));
                }
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

        fn assertComponent(comptime Component: type) void {
            comptime {
                if (!std.meta.trait.hasField(@typeName(Component))(CompHolder)) {
                    @compileError("Cannot use component of type " ++ @typeName(Component) ++ " as it has not been added to the world.");
                }
            }
        }

        fn getListOf(self: *Self, comptime Component: type) *std.AutoArrayHashMap(Entity, Component) {
            comptime assertComponent(Component);
            return &@field(self.components, @typeName(Component));
        }
    };
}

/// Takes tuple: { Player, Position, Sprite } and returns
/// a struct of pointers labeled a-z: { a: *Player, b: *Position, c: *Sprite }
pub fn Query(comptime q: anytype, comptime options: anytype) type {
    var tb = TypeBuilder.new(false, .Auto);
    inline for (q, 0..) |Q, i| {
        tb = tb.addField(&[1]u8{97 + i}, *Q, null);
    }
    tb = tb.addField("QueryType", @TypeOf(q), &q).addField("OptionsType", @TypeOf(options), &options);
    return std.MultiArrayList(tb.Build());
}

test World {
    const MyWorld = comptime blk: {
        var wb = WorldBuilder.new();
        try wb.include(&.{
            base.register,
            game_file.register,
        });
        break :blk wb.Build();
    };

    var world = try MyWorld.init(testing.allocator);
    defer world.deinit();

    const player_ent = try world.newEnt();
    try world.giveEntBundle(player_ent, player_file.PlayerBundle, .{
        .p = .{ .name = "Player" },
        .tran = .{},
        .sprite = .{ .img = 0 },
    });

    try world.runStage("UPDATE");
}

const game_file = struct {
    pub fn register(comptime world: *WorldBuilder) anyerror!void {
        world.addComponents(.{Sprite});
        try world.include(&.{player_file.register});
    }

    pub const Sprite = struct {
        img: usize,
    };
};

const player_file = struct {
    pub fn register(comptime world: *WorldBuilder) anyerror!void {
        world.addComponents(.{Player});
        world.addUpdateSystems(.{player_speach});
        try world.include(&.{player_weapons_file.register});
    }

    pub const Player = struct {
        name: []const u8,
    };

    pub const PlayerBundle = struct {
        p: Player,
        tran: base.Transform,
        sprite: game_file.Sprite,
    };

    fn player_speach(q: Query(.{ player_file.Player, base.Transform }, .{})) anyerror!void {
        for (q.items(.a), q.items(.b)) |player, trn| {
            std.debug.print("My name is {s}, and I'm located at {} {}.", .{ player.name, trn.pos.x, trn.pos.y });
        }
    }
};

const player_weapons_file = struct {
    pub fn register(comptime world: *WorldBuilder) anyerror!void {
        world.addComponents(.{Gun});
    }

    pub const Gun = struct {
        ammo: u32,
    };
};

fn MultiArrayListElem(comptime T: type) type {
    return @typeInfo(@TypeOf(T.pop)).Fn.return_type.?;
}
