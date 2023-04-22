const std = @import("std");
const testing = std.testing;
const util = @import("util.zig");
const base = @import("mods/base.zig");
const physics = @import("mods/physics.zig");
const TypeBuilder = @import("type_builder.zig");
const Allocator = std.mem.Allocator;

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

const TypeMap = struct {
    types: []const type = &.{},

    pub fn append(comptime self: *TypeMap, comptime T: type) void {
        self.types = self.types ++ &[_]type{T};
    }

    pub fn has(comptime self: TypeMap, comptime T: type) bool {
        for (self.types) |t| {
            if (t == T) return true;
        }
        return false;
    }
};

pub const WorldBuilder = struct {
    const Self = @This();

    const StageDef = struct {
        name: []const u8,
        def: TypeBuilder,
    };

    const DEFAULT_STAGES = struct {
        // zig fmt: off
        const PRE_INIT    = 0;
        const INIT        = 1;
        const POST_INIT   = 2;
        const PRE_UPDATE  = 3;
        const UPDATE      = 4;
        const POST_UPDATE = 5;
        const PRE_DRAW    = 6;
        const DRAW        = 7;
        const POST_DRAW   = 8;
        // zig fmt: on
    };

    compholder: TypeBuilder,
    resources: TypeBuilder,
    stage_defs: []const StageDef,

    included: TypeMap,

    pub fn new(comptime includes: anytype) Self {
        var self = Self{
            .compholder = TypeBuilder.new(false, .Auto),
            .resources = TypeBuilder.new(false, .Auto),
            .stage_defs = &.{},
            .included = .{},
        };

        for (@typeInfo(DEFAULT_STAGES).Struct.decls) |decl| {
            self.stage_defs = self.stage_defs ++ .{.{
                .name = decl.name,
                .def = TypeBuilder.new(true, .Auto),
            }};
        }

        self.include(includes);

        return self;
    }

    pub fn include(comptime self: *Self, comptime includes: anytype) void {
        inline for (includes) |inc| {
            if (comptime std.meta.trait.hasFn("include")(inc)) {
                if (comptime self.included.has(inc)) return;

                inc.include(self) catch |err| @compileError("Cound not build world, error in include. Error: " ++ err);
                self.included.append(inc);
            } else {
                @compileError("Struct " ++ @typeName(inc) ++ "does not have an fn include, it should not be passed to include.");
            }
        }
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
        if (comptime !std.meta.trait.isTuple(@TypeOf(systems))) @compileError("Expected tuple for @TypeOf(systems).");

        // if stage is part of DEFAULT_STAGES, we already know the index
        if (comptime @hasDecl(DEFAULT_STAGES, stage_name)) {
            const stage_index = @field(DEFAULT_STAGES, stage_name);
            addSystemsToStage_final(self, self.stage_defs[stage_index], stage_index, systems);
            return;
        }

        var i: usize = DEFAULT_STAGES.POST_DRAW + 1;
        while (i < self.stage_defs.len) {
            const sdef = self.stage_defs[i];

            if (std.mem.eql(u8, sdef.name, stage_name)) {
                addSystemsToStage_final(self, sdef, i, systems);
                return;
            }
        }

        @compileError("Cannot find stage " ++ stage_name ++ " in world.");
    }

    fn addSystemsToStage_final(comptime self: *Self, comptime sdef: StageDef, stage_index: usize, systems: anytype) void {
        var _stage_defs: [self.stage_defs.len]StageDef = undefined;
        std.mem.copy(StageDef, &_stage_defs, self.stage_defs);

        for (systems) |sys| {
            _stage_defs[stage_index].def = _stage_defs[stage_index].def.addTupleField(sdef.def.type_def.fields.len, comptime @TypeOf(sys), &sys);
        }

        self.stage_defs = &_stage_defs;
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

            pub fn runStage(comptime this: @This(), world: anytype, comptime stage_name: []const u8) anyerror!void {
                if (comptime !@hasField(@TypeOf(this.inner), stage_name)) @compileError("World does not have stage " ++ stage_name ++ " to run.");

                const stage = @field(this.inner, stage_name);

                inline for (std.meta.fields(@TypeOf(stage))) |stage_field| {
                    var args = try getArgsForSystem(world, stage_field.type);
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
        return World(CompHolder, self.resources.Build(), Stages(CompileStagesList(self.stage_defs)));
    }

    fn getArgsForSystem(world: anytype, comptime SysFn: type) anyerror!std.meta.ArgsTuple(SysFn) {
        var out: std.meta.ArgsTuple(SysFn) = undefined;

        inline for (out, 0..) |param, i| {
            const Param = @TypeOf(param);

            if (Param == Allocator) {
                if (i == 0) continue;
                @compileError("A system argument of Allocator must be the first argument.");
            }

            if (comptime std.meta.trait.isContainer(Param) and @hasDecl(Param, "Field")) {
                const query_ti = std.meta.fieldInfo(MultiArrayListElem(Param), .QueryType);
                const opts_ti = std.meta.fieldInfo(MultiArrayListElem(Param), .OptionsType);

                out[i] = try world.query(
                    @ptrCast(
                        *const query_ti.type,
                        query_ti.default_value.?,
                    ).*,
                    @ptrCast(
                        *const opts_ti.type,
                        opts_ti.default_value.?,
                    ).*,
                );
            } else if (comptime std.meta.trait.isSingleItemPtr(Param)) {
                out[i] = world.getResPtr(std.meta.Child(Param));
            } else {
                out[i] = world.getRes(Param);
            }
        }

        return out;
    }

    fn deinitArgsForSystem(args: anytype, alloc: Allocator) void {
        inline for (std.meta.fields(@TypeOf(args.*))) |args_field| {
            if (args_field.type == Allocator) continue;

            if (comptime std.meta.trait.isContainer(args_field.type) and @hasDecl(args_field.type, "deinit")) {
                @field(args, args_field.name).deinit(alloc);
            }
        }
    }

    fn CompileStagesList(comptime stage_defs: []const StageDef) type {
        var final = TypeBuilder.new(false, .Auto);
        for (stage_defs) |sdef| {
            const Stage = sdef.def.Build();
            final = final.addField(sdef.name, Stage, &Stage{});
        }
        return final.Build();
    }
};

const MyWorld = blk: {
    var wb = WorldBuilder.new();
    wb.include(.{
        base,
        physics,
    });
    break :blk wb.Build();
};

test WorldBuilder {
    _ = MyWorld;
}

fn World(comptime CompHolder: type, comptime Resources: type, comptime StagesList: type) type {
    return struct {
        const Self = @This();
        const __stages = StagesList{ .inner = .{} };

        alloc: Allocator,

        entities: std.ArrayList(Entity),
        next_ent: Entity = 0,

        components: CompHolder,
        resources: Resources,

        pub fn init(alloc: Allocator) !Self {
            var self = Self{
                .alloc = alloc,
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
            try __stages.runStage(self, stage_id);
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
            inline for (q) |Q| {
                assertComponent(Q);
            }

            var result = Query(q, options){};

            var comp0s = self.getListOf(q[0]);
            var comp0_iter = comp0s.iterator();

            comp_loop: while (comp0_iter.next()) |comp| {
                var res_item: MultiArrayListElem(Query(q, options)) = undefined;

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
