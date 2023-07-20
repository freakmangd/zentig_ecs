const std = @import("std");

pub usingnamespace @import("ecs.zig");
pub usingnamespace @import("query.zig");

pub const math = @import("math/init.zig");
pub const zmath = @import("zmath");

pub const Vec2 = @import("math/vec2.zig").Vec2;
pub const Vec3 = @import("math/vec3.zig").Vec3;
pub const Vec4 = @import("math/vec4.zig").Vec4;
pub const Mat3 = @import("math/mat3.zig");

pub const WorldBuilder = @import("worldbuilder.zig");
pub const Commands = @import("commands.zig");

pub const base = @import("mods/base/init.zig");
pub const input = @import("mods/input.zig");
pub const physics = @import("mods/physics.zig");

pub const log = std.log.scoped(.zentig);

pub const util = @import("util.zig");
pub const meta = @import("meta.zig");
pub const profiler = @import("etc/profiler.zig");

test {
    std.testing.refAllDeclsRecursive(@This());
}
