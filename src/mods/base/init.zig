const std = @import("std");
const ztg = @import("../../init.zig");

pub const Time = @import("time.zig");
pub const Lifetime = @import("lifetime.zig");
pub const Transform = @import("transform.zig");
pub const GlobalTransform = @import("global_transform.zig");

pub const Active = struct { bool = true };
pub const Name = struct { []const u8 };

pub fn include(comptime world: *ztg.WorldBuilder) !void {
    world.addComponents(&.{ Active, Name, Transform });
    world.include(&.{ Lifetime, Time, GlobalTransform });
}
