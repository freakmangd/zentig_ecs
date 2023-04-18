const std = @import("std");
const TypeBuilder = @import("type_builder.zig");
const Allocator = std.mem.Allocator;

pub const base = @import("base.zig");
pub const raylib = @import("raylib.zig");

pub const Entity = usize;

/// `info` should be a tuple of structs that have
/// the def `fn register(world: anytype) anyerror!void`
pub fn WorldBuilder(comptime info: anytype) type {
    return struct {
        const Self = @This();

        const StageDef = struct {
            name: []const u8,
            next: ?usize,
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

        pub fn new() anyerror!Self {
            var self = Self{
                .compholder = TypeBuilder.new(false, .Auto),
                .stage_defs = &.{},
            };

            for (DEFAULT_STAGES, 1..) |name, i| {
                self.stage_defs = self.stage_defs ++ &[_]StageDef{.{
                    .name = name,
                    .next = if (i == DEFAULT_STAGES.len) null else i,
                    .def = TypeBuilder.new(true, .Auto),
                }};
            }

            try include(&self, info);

            return self;
        }

        pub fn include(comptime self: *Self, more_info: anytype) anyerror!void {
            inline for (more_info) |inf| {
                if (std.meta.trait.hasFn("register")(inf)) {
                    try inf.register(self);
                }
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

                    for (systems.*) |sys| {
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

        pub fn Build(comptime self: Self) type {
            const Stages = struct {
                // inner: struct {
                //   UPDATE: tuple {
                //     *const fn (Alloc, Query(...)) anyerror!void = @import("...").system_fn,
                //     *const fn (Alloc, Query(...), Query(...)) anyerror!void = @import("...").system_fn,
                //     ...
                //   },
                //   ...
                // }
                inner: CompileStagesList(self.stage_defs),

                pub fn runStage(stages: @This(), world: anytype, comptime stage_name: []const u8) anyerror!void {
                    const stage = @field(stages.inner, stage_name);

                    inline for (std.meta.fields(@TypeOf(stage))) |stage_field| {
                        var args = try getArgsForSystem(world, std.meta.Child(stage_field.type));
                        if (@TypeOf(args[0]) == Allocator) {
                            args[0] = world.alloc;
                        }
                        try @call(.auto, @field(stage, stage_field.name), args);
                    }
                }
            };

            // CompHolder = struct {
            //   player.Player: std.AutoArrayHashMap(Entity, Player),
            //   base.Position: std.AutoArrayHashMap(Entity, Position),
            //   ...
            // };
            const CompHolder = self.compholder.Build();

            return World(CompHolder, Stages);
        }

        fn getArgsForSystem(world: anytype, comptime SysFn: type) anyerror!std.meta.ArgsTuple(SysFn) {
            var out: std.meta.ArgsTuple(SysFn) = undefined;

            inline for (out, 0..) |param, i| {
                const Param = @TypeOf(param);

                if (Param == Allocator) continue;

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

        fn CompileStagesList(comptime stages: []const StageDef) type {
            var final = TypeBuilder.new(false, .Auto);
            for (stages) |sdef| {
                const Stage = sdef.def.Build();
                final = final.addField(sdef.name, Stage, &Stage{});
            }
            return final.Build();
        }
    };
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
                .stages = .{ .inner = .{} },
                .components = undefined,
                .entities = std.ArrayList(Entity).init(alloc),
                .next_ent = 0,
            };

            inline for (std.meta.fields(CompHolder)) |field| {
                @field(self.components, field.name) = field.type.init(alloc);
            }

            return self;
        }

        pub fn runStageList(self: *Self, stage_ids: []const []const u8) anyerror!void {
            for (stage_ids) |sid| {
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

        pub fn giveEntBundle(self: *Self, ent: Entity, bundle: anytype) !void {
            inline for (std.meta.fields(@TypeOf(bundle))) |field| {
                try self.getListOf(field.type).put(ent, @field(bundle, field.name));
            }
        }

        pub fn query(self: *Self, comptime q: anytype, comptime options: anytype) !Query(q, options) {
            comptime {
                inline for (q) |Q| {
                    if (!std.meta.trait.hasField(@typeName(Q))(CompHolder)) @compileError("Cannot query type " ++ @typeName(Q) ++ " as it has not been added to the world.");
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

        fn getListOf(self: *Self, comptime Component: type) *std.AutoArrayHashMap(Entity, Component) {
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

    //var fields: []const std.builtin.Type.StructField = &.{};
    //inline for (q, 0..) |Q, i| {
    //    fields = fields ++ .{std.builtin.Type.StructField{
    //        .name = &[1]u8{97 + i},
    //        .type = *Q,
    //        .is_comptime = false,
    //        .default_value = null,
    //        .alignment = 0,
    //    }};
    //}
    //fields = fields ++ .{.{
    //    .name = "QueryType",
    //    .type = @TypeOf(q),
    //    .is_comptime = true,
    //    .default_value = q,
    //    .alignment = 0,
    //}};
    //return @Type(std.builtin.Type{ .Struct = .{
    //    .fields = fields,
    //    .decls = .{},
    //    .layout = .Auto,
    //    .is_tuple = false,
    //} });
}

fn MultiArrayListElem(comptime T: type) type {
    return @typeInfo(@TypeOf(T.pop)).Fn.return_type.?;
}
