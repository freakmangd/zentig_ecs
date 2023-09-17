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

        var thread_pool: std.Thread.Pool = undefined;

        pub fn init(alloc: std.mem.Allocator) !void {
            _ = alloc;
            //try std.Thread.Pool.init(&thread_pool, .{ .allocator = alloc });
        }

        pub fn deinit() void {
            //thread_pool.deinit();
        }

        pub fn runStage(
            world: *World,
            comptime stage_field: StageField,
            comptime catch_errs: bool,
            comptime errCallback: if (catch_errs) fn (anyerror) void else void,
        ) !void {
            const stage = @field(inner, std.meta.fieldInfo(Inner, stage_field).name);

            inline for (std.meta.fields(@TypeOf(stage))) |label_info| {
                try runSystemTuple(label_info.type.before, world, catch_errs, errCallback);
                try runSystemTuple(label_info.type.during, world, catch_errs, errCallback);
                try runSystemTuple(label_info.type.after, world, catch_errs, errCallback);
            }
        }

        fn runSystemTuple(systems: anytype, world: *World, comptime catch_errs: bool, comptime errCallback: if (catch_errs) fn (anyerror) void else void) !void {
            inline for (systems) |sys| {
                const System = @TypeOf(sys);
                const params = @typeInfo(System).Fn.params;
                const args = try world.initParamsForSystem(world.frame_alloc, params);

                if (comptime ztg.meta.canReturnError(System)) {
                    @call(.auto, sys, args) catch |err| {
                        if (comptime catch_errs) errCallback(err) else return err;
                    };
                } else {
                    @call(.auto, sys, args);
                }

                try world.postSystemUpdate();
            }
        }

        // doesnt work
        fn runStageInParallel(
            world: *World,
            comptime stage_field: StageField,
            comptime catch_errs: bool,
            comptime errCallback: if (catch_errs) fn (anyerror) void else void,
        ) !void {
            const Stage = @TypeOf(@field(inner, std.meta.fieldInfo(Inner, stage_field).name));

            try runLabelSectionsInParallel(world, Stage, catch_errs, errCallback, "before");
            try runLabelSectionsInParallel(world, Stage, catch_errs, errCallback, "during");
            try runLabelSectionsInParallel(world, Stage, catch_errs, errCallback, "after");
        }

        fn runLabelSectionsInParallel(
            world: *World,
            comptime Stage: type,
            comptime catch_errs: bool,
            comptime errCallback: if (catch_errs) fn (anyerror) void else void,
            comptime section: []const u8,
        ) !void {
            var stage_err: ?anyerror = null;
            var wait_group = std.Thread.WaitGroup{};

            inline for (std.meta.fields(Stage)) |label_info| {
                try runSystemTupleInParallel(@field(label_info.type, section), world, &stage_err, &wait_group);
            }

            thread_pool.waitAndWork(&wait_group);

            if (stage_err) |err| {
                if (comptime catch_errs) errCallback(err) else return err;
            }
        }

        fn runSystemTupleInParallel(systems: anytype, world: *World, stage_err: *?anyerror, group: *std.Thread.WaitGroup) !void {
            inline for (systems) |sys| {
                const params = @typeInfo(@TypeOf(sys)).Fn.params;
                const args = if (comptime params.len == 0) .{} else try world.initParamsForSystem(world.frame_alloc, params);
                try thread_pool.spawn(runSystemInParallel, .{ world, sys, args, stage_err, group });
            }
        }

        fn runSystemInParallel(world: *World, comptime f: anytype, args: anytype, stage_err: *?anyerror, group: *std.Thread.WaitGroup) void {
            group.start();
            defer group.finish();

            if (comptime ztg.meta.canReturnError(@TypeOf(f))) {
                @call(.auto, f, args) catch |sys_err| {
                    stage_err.* = sys_err;
                    return;
                };
            } else {
                @call(.auto, f, args);
            }

            world.postSystemUpdate() catch |world_err| {
                stage_err.* = world_err;
            };
        }

        pub fn runStageByName(
            world: *World,
            stage_name: []const u8,
            comptime catch_errs: bool,
            comptime errCallback: if (catch_errs) fn (anyerror) void else void,
        ) anyerror!void {
            inline for (std.meta.fields(Inner), 0..) |field, i| {
                if (std.mem.eql(u8, field.name, stage_name)) {
                    return runStage(world, @enumFromInt(i), catch_errs, errCallback);
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
        inline for (sdef.labels.items) |label| {
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
