const std = @import("std");
const ztg = @import("init.zig");

const Allocator = std.mem.Allocator;
const Commands = ztg.Commands;
const StageDef = ztg.WorldBuilder.StageDef;
const TypeBuilder = ztg.meta.TypeBuilder;

pub fn Init(comptime stage_defs: []const StageDef) type {
    const Inner = CompileStagesList(stage_defs);
    // inner: struct {
    //   update: struct {
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
    const inner = Inner{};

    return struct {
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
            const stage = @field(inner, @tagName(stage_field));

            inline for (@typeInfo(@TypeOf(stage)).@"struct".fields) |label_info| {
                inline for (&.{ "before", "during", "after" }) |tuple_name| {
                    const substage = @field(label_info.type, tuple_name);
                    inline for (@typeInfo(@TypeOf(substage)).@"struct".fields) |sys_field| {
                        const sys = @field(substage, sys_field.name);
                        const System = @TypeOf(sys);
                        const params = @typeInfo(System).@"fn".params;
                        const args = try world.initParamsForSystem(world.frame_arena.allocator(), params);

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
                inline for (&.{ "before", "during", "after" }) |tuple_name| {
                    defer wait_group.reset();
                    var stage_err: ?anyerror = null;

                    inline for (@field(label_info.type, tuple_name)) |sys| {
                        try thread_pool.spawn(runSystemInParallel, .{ world, sys, &stage_err, &wait_group });
                    }

                    thread_pool.waitAndWork(&wait_group);

                    if (stage_err) |err| {
                        if (comptime catch_errs) errCallback(err) else return err;
                    }
                }
            }

            _ = thread_arena.reset(.retain_capacity);
        }

        fn runSystemInParallel(world: anytype, comptime f: anytype, stage_err: *?anyerror, group: *std.Thread.WaitGroup) void {
            group.start();
            defer group.finish();

            const F = @TypeOf(f);
            const params = @typeInfo(F).@"fn".params;
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
        ) !void {
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
