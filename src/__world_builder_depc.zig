// Currently, this version of WorldBuilder does not work, as
// function pointers at comptime are a lil wonkey

/// `info` should be a tuple of structs that have
/// the def `fn register(world: anytype) anyerror!void`
pub const WorldBuilder = struct {
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

    pub fn new() Self {
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

    // TODO: This function does not work with the current zig version:
    // src\ecs.zig:201:13: error: TODO (LLVM): implement const of pointer type '[TODO fix internal compiler bug regarding dump]' (value.Value.Tag.function)
    //
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
        _ = Inner;
        return struct {
            // inner: struct {
            //   UPDATE: tuple {
            //     *const fn (Alloc, Query(...)) anyerror!void = @import("...").system_fn,
            //     *const fn (Alloc, Query(...), Query(...)) anyerror!void = @import("...").system_fn,
            //     ...
            //   },
            //   ...
            // }
            //inner: Inner,

            pub fn runStage(stages: @This(), world: anytype, comptime stage_name: []const u8) anyerror!void {
                _ = stage_name;
                _ = world;
                _ = stages;
                //const stage = @field(stages.inner, stage_name);

                //inline for (std.meta.fields(@TypeOf(stage))) |stage_field| {
                //    var args = try getArgsForSystem(world, std.meta.Child(stage_field.type));
                //    defer deinitArgsForSystem(&args, world.alloc);

                //    if (@TypeOf(args[0]) == Allocator) {
                //        args[0] = world.alloc;
                //    }

                //    try @call(.auto, @field(stage, stage_field.name), args);
                //}
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
