const std = @import("std");
const math = @import("../math.zig");
const ztg = @import("../init.zig");

pub const Name = struct { []const u8 };

pub const Transform = struct {
    pos: math.Vec3 = math.Vec3.new(0, 0, 0),
    rot: math.Quaternion = math.Quaternion.identity(),
    scale: math.Vec3 = math.Vec3.one(),
};

pub const Lifetime = struct {
    max: f32,
    current: f32 = 0.0,
    is_dead: bool = false,

    tick_rate: TimeScale = .scaled_time,
    on_death: OnDeath = .destroy,

    pub const TimeScale = enum {
        scaled_time,
        real_time,
    };

    pub const OnDeath = union(enum) {
        destroy,
        callback: *const fn (*Lifetime, ztg.Entity) anyerror!void,
    };
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
    world.addComponents(&.{ Name, Transform, Lifetime });
    world.addResource(Time, .{});
    world.addSystemsToStage(.post_update, .{pou_lifetimes});
}

pub fn pou_lifetimes(com: ztg.Commands, q: ztg.Query(&.{ ztg.Entity, Lifetime }), time: Time) !void {
    for (q.items(0), q.items(1)) |ent, lt| {
        if (lt.is_dead) continue;

        lt.current += time.dt;
        if (lt.current >= lt.max) {
            lt.is_dead = true;

            switch (lt.on_death) {
                .destroy => try com.removeEnt(ent),
                .callback => |cb| try cb(lt, ent),
            }
        }
    }
}
