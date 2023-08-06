const std = @import("std");
const ztg = @import("init.zig");

const Allocator = std.mem.Allocator;
const Commands = ztg.Commands;
const StageDef = ztg.WorldBuilder.StageDef;
const TypeBuilder = ztg.meta.TypeBuilder;

pub fn Init(comptime stage_defs: []const StageDef, comptime World: type) type {
    const Inner = CompileStagesList(stage_defs);
    const inner = Inner{};

    return struct {
        // inner: struct {
        //   UPDATE: struct {
        //     body: struct {
        //       before: tuple {
        //       },
        //       during: tuple {
        //         fn (Alloc, Query(...)) anyerror!void = @import("...").system_fn,
        //         fn (Alloc, Query(...), Query(...)) anyerror!void = @import("...").system_fn,
        //       },
        //       after: tuple {
        //       },
        //     },
        //     ...
        //   },
        //   ...
        // }
        pub const StageField = std.meta.FieldEnum(Inner);

        pub fn runStage(world: *World, comptime stage_field: StageField, comptime catch_errs: bool, comptime errCallback: if (catch_errs) fn (anyerror) void else void) !void {
            const stage = @field(inner, std.meta.fieldInfo(Inner, stage_field).name);

            inline for (std.meta.fields(@TypeOf(stage))) |label_info| {
                try runSystemTuple(label_info.type.before, world, catch_errs, errCallback);
                try runSystemTuple(label_info.type.during, world, catch_errs, errCallback);
                try runSystemTuple(label_info.type.after, world, catch_errs, errCallback);
            }
        }

        inline fn runSystemTuple(systems: anytype, world: *World, comptime catch_errs: bool, comptime errCallback: if (catch_errs) fn (anyerror) void else void) !void {
            inline for (systems) |sys| {
                const System = @TypeOf(sys);
                var args = try world.initParamsForSystem(world.frame_alloc, @typeInfo(System).Fn.params);

                if (comptime ztg.meta.canReturnError(System)) {
                    if (comptime catch_errs) {
                        @call(.auto, sys, args) catch |err| {
                            errCallback(err);
                        };
                    } else {
                        try @call(.auto, sys, args);
                    }
                } else {
                    @call(.auto, sys, args);
                }

                try world.postSystemUpdate();
            }
        }

        pub fn runStageByName(world: *World, stage_name: []const u8) anyerror!void {
            inline for (std.meta.fields(Inner), 0..) |field, i| {
                if (std.mem.eql(u8, field.name, stage_name)) {
                    return runStage(world, @enumFromInt(i), false, void{});
                }
            }
            return error.UnknownStage;
        }
    };
}

fn CompileStagesList(comptime stage_defs: []const StageDef) type {
    var stages_list = TypeBuilder{};
    inline for (stage_defs) |sdef| {
        var stage = TypeBuilder{};
        inline for (sdef.labels) |label| {
            const Label = struct {
                const before = label.before.Build(){};
                const during = label.during.Build(){};
                const after = label.after.Build(){};
            };
            stage.addField(label.name, Label, &Label{});
        }
        const Stage = stage.Build();
        stages_list.addField(sdef.name, Stage, &Stage{});
    }
    return stages_list.Build();
}
