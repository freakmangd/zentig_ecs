const std = @import("std");
const ecs = @import("ecs.zig");

pub const Transform = struct {
    pos: ecs.Vec3 = ecs.Vec3.new(0, 0, 0),
    rot: ecs.Quaternion = ecs.Quaternion.identity(),
    scale: ecs.Vec3 = ecs.Vec3.one(),
};

pub fn register(world: anytype) anyerror!void {
    world.addComponents(.{Transform});
}
