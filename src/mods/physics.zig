const std = @import("std");
const ecs = @import("../ecs.zig");

pub const PhysBody = struct {
    vel: ecs.Vec3,
};

pub const Collider = struct {
    box: Box,

    pub const Box = struct {};
};

pub fn include(comptime wb: *ecs.WorldBuilder) !void {
    wb.addComponents(.{PhysBody});
    wb.addSystemsToStage("POST_UPDATE", .{post_update_physbodies});
}

fn post_update_physbodies(q: ecs.Query(.{ ecs.base.Transform, PhysBody }, .{})) !void {
    for (q.items(.a), q.items(.b)) |tr, pb| {
        const delta = ecs.Vec3.multiply(pb.vel, 0.0);
        tr.pos = tr.pos.add(delta);
    }
}
