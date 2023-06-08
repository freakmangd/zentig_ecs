const std = @import("std");
const math = @import("../math.zig");
const ztg = @import("../init.zig");

pub const Transform = struct {
    pos: math.Vec3 = math.Vec3.new(0, 0, 0),
    rot: math.Quaternion = math.Quaternion.identity(),
    scale: math.Vec3 = math.Vec3.one(),
};

pub const Time = struct {
    dt: f32 = 0.0,
    realDt: f32 = 0.0,

    timeScale: f32 = 1.0,

    time: f32 = 0.0,
    realTime: f32 = 0.0,

    frameCount: usize = 0,
};

pub fn include(comptime world: *ztg.WorldBuilder) !void {
    world.addComponents(&.{Transform});
    world.addResource(Time, .{});
}
