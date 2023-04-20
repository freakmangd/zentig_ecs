const std = @import("std");
const ecs = @import("ecs.zig");

pub const Transform = struct {
    pos: ecs.Vec3 = ecs.Vec3.new(0, 0, 0),
    rot: ecs.Quaternion = ecs.Quaternion.identity(),
    scale: ecs.Vec3 = ecs.Vec3.one(),
};

pub const Time = struct {
    dt: f32 = 0.0,
    realDt: f32 = 0.0,

    timeScale: f32 = 1.0,

    time: f32 = 0.0,
    realTime: f32 = 0.0,

    frameCount: usize = 0,
};

/// Only updates frameCount
pub fn pre_update_time_default(time: *Time) !void {
    time.frameCount += 1;
}

const InitOptions = struct {
    pre_update_time: fn (*Time) anyerror!void = pre_update_time_default,
};

pub fn Init(comptime options: InitOptions) type {
    return struct {
        var FIXED_UPDATE = 0;

        pub fn include(comptime world: *ecs.WorldBuilder) !void {
            world.addComponents(.{Transform});
            world.addResource(Time, .{});
        }

        pub fn register(world: anytype) !void {
            const MLib = Lib(@TypeOf(world));
            try world.addSystemsToStage(ecs.stages.PRE_UPDATE, &.{MLib.pre_update_time_wrapper});
        }

        pub fn Lib(comptime WorldPtr: type) type {
            return struct {
                fn pre_update_time_wrapper(world: WorldPtr) !void {
                    var time = world.getResPtr(Time);
                    try options.pre_update_time(time);
                }
            };
        }
    };
}
