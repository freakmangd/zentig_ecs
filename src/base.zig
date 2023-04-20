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
        pub fn include(comptime world: *ecs.WorldBuilder) !void {
            world.addComponents(.{Transform});
            world.addResource(Time, .{});
            world.addSystemsToStage("PRE_UPDATE", .{pre_update_time_wrapper});
        }

        fn pre_update_time_wrapper(time: *Time) !void {
            try options.pre_update_time(time);
        }
    };
}
