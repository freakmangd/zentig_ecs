const std = @import("std");
const util = @import("util.zig");
const Commands = @import("commands.zig");
const Allocator = std.mem.Allocator;
const StageDef = @import("init.zig").WorldBuilder.StageDef;
const TypeBuilder = @import("type_builder.zig");

pub fn Init(comptime stage_defs: []const StageDef, comptime World: type) type {
    const Inner = CompileStagesList(stage_defs);

    return struct {
        // inner: struct {
        //   UPDATE: tuple {
        //     fn (Alloc, Query(...)) anyerror!void = @import("...").system_fn,
        //     fn (Alloc, Query(...), Query(...)) anyerror!void = @import("...").system_fn,
        //     ...
        //   },
        //   ...
        // }
        inner: Inner,

        pub const StageField = std.meta.FieldEnum(Inner);

        pub fn runStage(comptime this: @This(), world: *World, comptime stage_field: StageField) anyerror!void {
            const stage = @field(this.inner, std.meta.fieldInfo(Inner, stage_field).name);

            inline for (std.meta.fields(@TypeOf(stage))) |stage_field_info| {
                var args = try world.initParamsForSystem(@typeInfo(stage_field_info.type).Fn.params);
                defer world.deinitParamsForSystem(&args);

                if (comptime util.canReturnError(stage_field_info.type)) {
                    try @call(.auto, @field(stage, stage_field_info.name), args);
                } else {
                    @call(.auto, @field(stage, stage_field_info.name), args);
                }

                try world.postSystemCleanup();
            }
        }

        pub fn runStageCatchErrors(comptime this: @This(), world: *World, comptime stage_field: StageField, comptime errCallback: fn (anyerror) void) !void {
            const stage = @field(this.inner, std.meta.fieldInfo(Inner, stage_field).name);

            inline for (std.meta.fields(@TypeOf(stage))) |stage_field_info| {
                var args = try world.initParamsForSystem(@typeInfo(stage_field_info.type).Fn.params);
                defer world.deinitParamsForSystem(&args);

                if (comptime util.canReturnError(stage_field_info.type)) {
                    @call(.auto, @field(stage, stage_field_info.name), args) catch |err| {
                        errCallback(err);
                    };
                } else {
                    @call(.auto, @field(stage, stage_field_info.name), args);
                }

                try world.postSystemCleanup();
            }
        }

        pub fn runStageRuntime(comptime this: @This(), world: *World, stage_name: []const u8) anyerror!void {
            inline for (std.meta.fields(Inner)) |field| {
                if (std.mem.eql(u8, field.name, stage_name)) {
                    try runStage(this, world, @as(StageField, @enumFromInt(std.meta.fieldIndex(Inner, field.name).?)));
                    break;
                }
            }
        }
    };
}

fn CompileStagesList(comptime stage_defs: []const StageDef) type {
    var final = TypeBuilder.init(false, .Auto);
    for (stage_defs) |sdef| {
        const Stage = sdef.def.Build();
        final.addField(sdef.name, Stage, &Stage{});
    }
    return final.Build();
}
