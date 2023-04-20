const std = @import("std");
const ecs = @import("ecs.zig");

pub const PhysBody = struct {
    vel: ecs.Vec3,
};

pub const Collider = struct {
    box: Box,

    pub const Box = struct {};
};

pub fn Init() type {
    return struct {
        pub fn include(comptime wb: *ecs.WorldBuilder) !void {
            wb.addComponents(.{PhysBody});
        }

        pub fn register(world: anytype) !void {
            const MLib = Lib(@TypeOf(world));
            try world.addSystemsToStage(ecs.stages.POST_UPDATE, &.{MLib.post_update_physbodies});
        }

        fn Lib(comptime WorldPtr: type) type {
            return struct {
                fn post_update_physbodies(world: WorldPtr) !void {
                    var q = try world.query(.{ ecs.base.Transform, PhysBody }, .{});
                    defer q.deinit(world.alloc);

                    const time = world.getRes(ecs.base.Time);

                    for (q.items(.a), q.items(.b)) |tr, pb| {
                        const delta = ecs.Vec3.multiply(pb.vel, time.dt);
                        tr.pos = tr.pos.add(delta);
                    }
                }
            };
        }
    };
}
