const std = @import("std");

pub const Vec2 = @import("vec2.zig");
pub const Vec3 = @import("vec3.zig");
pub const Vec4 = @import("vec4.zig");

pub const clamp = std.math.clamp;

pub fn clamp01(v: anytype) @TypeOf(v) {
    return @call(.always_inline, clamp, .{ v, 0, 1 });
}

test {
    _ = @import("vec2.zig");
    _ = @import("vec3.zig");
    _ = @import("vec4.zig");
    _ = @import("vec_funcs.zig");
}
