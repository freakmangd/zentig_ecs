const std = @import("std");
const ztg = @import("../init.zig");

pub const PhysBody = struct {
    vel: ztg.Vec3,
};

pub const Collider = struct {
    box: Box,

    pub const Box = struct {};
};

pub fn include(comptime wb: *ztg.WorldBuilder) void {
    wb.addComponents(&.{PhysBody});
    wb.addSystemsToStage(.post_update, .{pou_physbodies});
}

fn pou_physbodies(q: ztg.Query(&.{ ztg.base.Transform, PhysBody })) void {
    for (q.items(0), q.items(1)) |tr, pb| {
        const delta = ztg.Vec3.multiply(pb.vel, 0.0);
        tr.pos = tr.pos.add(delta);
    }
}
