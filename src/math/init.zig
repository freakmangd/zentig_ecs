const std = @import("std");

pub inline fn divAsFloat(comptime T: type, a: anytype, b: anytype) T {
    return if (comptime std.meta.trait.isIntegral(@TypeOf(a))) @as(T, @floatFromInt(a)) else a / if (comptime std.meta.trait.isIntegral(@TypeOf(b))) @as(T, @floatFromInt(b)) else b;
}

pub inline fn clamp01(v: anytype) @TypeOf(v) {
    return @call(.always_inline, std.math.clamp, .{ v, 0, 1 });
}

pub inline fn lengthVec3(vec: @Vector(3, f32)) f32 {
    return @sqrt(@reduce(.Add, vec * vec));
}

pub fn normalizeVec3(vec: @Vector(3, f32)) @Vector(3, f32) {
    const len = lengthVec3(vec);
    if (len == 0) return vec;
    return vec / @as(@Vector(3, f32), @splat(len));
}

pub inline fn dotVec3(vec0: @Vector(3, f32), vec1: @Vector(3, f32)) f32 {
    return @reduce(.Add, vec0 * vec1);
}

const Vec3Component = enum { x, y, z };
pub inline fn swizzleVec3(vec: @Vector(3, f32), comptime x: Vec3Component, comptime y: Vec3Component, comptime z: Vec3Component) @Vector(3, f32) {
    return @shuffle(f32, vec, undefined, [_]i32{ @intFromEnum(x), @intFromEnum(y), @intFromEnum(z) });
}

test {
    _ = @import("vec2.zig");
    _ = @import("vec3.zig");
    _ = @import("vec4.zig");
    _ = @import("vec_funcs.zig");
}
