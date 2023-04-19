const std = @import("std");
const testing = std.testing;
const util = @import("util.zig");
const TypeBuilder = @import("type_builder.zig");
const Allocator = std.mem.Allocator;

pub usingnamespace util;
pub const base = @import("base.zig");

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
    stage_defs: []const StageDef,
    include_list: []const type,

    pub fn new() Self {
        var self = Self{
            .compholder = TypeBuilder.new(false, .Auto),
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
            }
            self.include_list = self.include_list ++ includes;
        }
    }

    pub fn addComponents(comptime self: *Self, comps: anytype) void {
        for (comps) |Comp| {
            self.compholder = self.compholder.addField(@typeName(Comp), std.AutoArrayHashMap(Entity, Comp), null);
        }
    }

    // TODO: This function sucks ass
    //pub fn addSystemsToStage(comptime self: *Self, comptime stage_name: []const u8, systems: anytype) void {
    //    for (self.stage_defs, 0..) |sdef, i| {
    //        if (std.mem.eql(u8, sdef.name, stage_name)) {
    //            var _sdef = sdef;

    //            for (systems) |sys| {
    //                _sdef.def = _sdef.def.addTupleField(sdef.def.type_def.fields.len, *const @TypeOf(sys), &sys);
    //            }

    //            var _stage_defs: [self.stage_defs.len]StageDef = undefined;
    //            std.mem.copy(StageDef, &_stage_defs, self.stage_defs);

    //            _stage_defs[i] = _sdef;

    //            self.stage_defs = &_stage_defs;
    //            break;
    //        }
    //    }
    //}

    //pub fn addUpdateSystems(comptime self: *Self, systems: anytype) void {
    //    addSystemsToStage(self, "UPDATE", systems);
    //}

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
        const CompHolder = self.compholder.Build();
        return World(CompHolder, std.meta.Tuple(self.include_list)); //, Stages(CompileStagesList(self.stage_defs)));
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

test WorldBuilder {
    const MyWorld = comptime blk: {
        var wb = WorldBuilder.new();
        wb.include(.{
            base,
        });
        break :blk wb.Build();
    };
    _ = MyWorld;
}

fn World(comptime CompHolder: type, comptime IncludeList: type) type {
    return struct {
        const Self = @This();

        const SystemList = std.ArrayList(*const fn (*Self) anyerror!void);
        const Stages = std.ArrayList(SystemList);

        alloc: Allocator,

        entities: std.ArrayList(Entity),
        next_ent: Entity = 0,

        stages_list: Stages,
        components: CompHolder,

        pub fn init(alloc: Allocator) !Self {
            var self = Self{
                .alloc = alloc,
                .stages_list = std.ArrayList(SystemList).init(alloc),
                .components = undefined,
                .entities = std.ArrayList(Entity).init(alloc),
                .next_ent = 0,
            };

            inline for (std.meta.fields(CompHolder)) |field| {
                @field(self.components, field.name) = field.type.init(alloc);
            }

            inline for (std.meta.fields(STAGES_LIST)) |_| {
                try self.stages_list.append(SystemList.init(alloc));
            }

            inline for (std.meta.fields(IncludeList)) |inc| {
                if (comptime std.meta.trait.hasFn("register")(inc.type)) {
                    try inc.type.register(&self);
                }
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

        pub fn register(self: *Self, register_fns: []const *const fn (*Self) anyerror!void) anyerror!void {
            for (register_fns) |_fn| {
                try _fn(self);
            }
        }

        pub fn addSystemsToStage(self: *Self, stage_id: usize, systems: []const *const fn (*Self) anyerror!void) Allocator.Error!void {
            for (systems) |sys| {
                try self.stages_list.items[stage_id].append(sys);
            }
        }

        pub fn addUpdateSystems(self: *Self, systems: []const *const fn (*Self) anyerror!void) Allocator.Error!void {
            try self.addSystemsToStage(stages.UPDATE, systems);
        }

        pub fn runStageList(self: *Self, stage_ids: []const usize) anyerror!void {
            for (stage_ids) |sid| {
                try runStage(self, sid);
            }
        }

        pub fn runStage(self: *Self, comptime stage_id: usize) anyerror!void {
            for (self.stages_list.items[stage_id].items) |sys| {
                try sys(self);
            }
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
