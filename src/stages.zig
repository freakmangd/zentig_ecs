const std = @import("std");
const ztg = @import("init.zig");

const Allocator = std.mem.Allocator;
const Commands = ztg.Commands;
const StageDef = ztg.WorldBuilder.StageDef;
const TypeBuilder = ztg.meta.TypeBuilder;

pub fn Init(comptime stage_defs: []const StageDef) type {
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
        var thread_alloc: std.heap.ThreadSafeAllocator = undefined;
        var thread_arena: std.heap.ArenaAllocator = undefined;
        var wait_group = std.Thread.WaitGroup{};

        pub fn init(alloc: std.mem.Allocator) !void {
            thread_alloc = .{ .child_allocator = alloc };
            thread_arena = std.heap.ArenaAllocator.init(thread_alloc.allocator());
            try std.Thread.Pool.init(&thread_pool, .{ .allocator = thread_alloc.allocator() });
        }

        pub fn deinit() void {
            thread_pool.deinit();
            thread_arena.deinit();
        }

        pub fn runStage(
            world: anytype,
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

        fn runSystemTuple(systems: anytype, world: anytype, comptime catch_errs: bool, comptime errCallback: if (catch_errs) fn (anyerror) void else void) !void {
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

        pub fn runStageInParallel(
            world: anytype,
            comptime stage_field: StageField,
            comptime catch_errs: bool,
            comptime errCallback: if (catch_errs) fn (anyerror) void else void,
        ) !void {
            const Stage = @TypeOf(@field(inner, std.meta.fieldInfo(Inner, stage_field).name));

            inline for (std.meta.fields(Stage)) |label_info| {
                try runLabelSectionInParallel(world, label_info.type.before, catch_errs, errCallback);
                try runLabelSectionInParallel(world, label_info.type.during, catch_errs, errCallback);
                try runLabelSectionInParallel(world, label_info.type.after, catch_errs, errCallback);
            }

            _ = thread_arena.reset(.retain_capacity);
        }

        fn runLabelSectionInParallel(
            world: anytype,
            comptime systems_tuple: anytype,
            comptime catch_errs: bool,
            comptime errCallback: if (catch_errs) fn (anyerror) void else void,
        ) !void {
            defer wait_group.reset();
            var stage_err: ?anyerror = null;

            inline for (systems_tuple) |sys| {
                try thread_pool.spawn(runSystemInParallel, .{ world, sys, &stage_err, &wait_group });
            }

            thread_pool.waitAndWork(&wait_group);

            if (stage_err) |err| {
                if (comptime catch_errs) errCallback(err) else return err;
            }
        }

        fn runSystemInParallel(world: anytype, comptime f: anytype, stage_err: *?anyerror, group: *std.Thread.WaitGroup) void {
            group.start();
            defer group.finish();

            const F = @TypeOf(f);
            const params = @typeInfo(F).Fn.params;
            const args = world.initParamsForSystem(thread_alloc.allocator(), params) catch |err| {
                stage_err.* = err;
                return;
            };

            if (comptime ztg.meta.canReturnError(F)) {
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
            world: anytype,
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
            stage.addField(label.name ++ "", Label, &Label{});
        }
        const Stage = stage.Build();
        stages_list.addField(sdef.name ++ "", Stage, &Stage{});
    }
    return stages_list.Build();
}
