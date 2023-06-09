const std = @import("std");

pub usingnamespace @import("math.zig");
pub usingnamespace @import("ecs.zig");

pub const WorldBuilder = @import("worldbuilder.zig");
pub const worldInfo = @import("world.zig").worldInfo;
pub const Commands = @import("commands.zig");

pub const base = @import("mods/base.zig");
pub const input = @import("mods/input.zig");
pub const physics = @import("mods/physics.zig");

test {
    std.testing.refAllDeclsRecursive(@This());
}
