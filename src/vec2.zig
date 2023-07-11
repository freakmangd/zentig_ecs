const std = @import("std");
const math = std.math;
const util = @import("util.zig");
const Vec3 = @import("vec3.zig");

const Vec2 = @This();
pub usingnamespace @import("vec_funcs.zig").init(Vec2);

x: f32 = 0.0,
y: f32 = 0.0,

pub inline fn init(x: anytype, y: anytype) Vec2 {
    return .{
        .x = if (comptime @typeInfo(x) == .Int) @floatFromInt(x) else x,
        .y = if (comptime @typeInfo(y) == .Int) @floatFromInt(y) else y,
    };
}

pub inline fn set(self: *Vec2, x: f32, y: f32) void {
    self.x = x;
    self.y = y;
}

pub inline fn equals(a: Vec2, b: Vec2) bool {
    return a.x == b.x and a.y == b.y;
}

pub inline fn splat(s: f32) Vec2 {
    return .{ .x = s, .y = s };
}

pub inline fn one() Vec2 {
    return .{ .x = 1, .y = 1 };
}

pub inline fn into(self: Vec2, comptime T: type) T {
    return .{ .x = self.x, .y = self.y };
}

pub inline fn intoVectorOf(self: Vec2, comptime T: type) @Vector(2, T) {
    if (comptime std.meta.trait.isFloat(T)) {
        return .{ @as(T, @floatCast(self.x)), @as(T, @floatCast(self.y)) };
    } else if (comptime std.meta.trait.isIntegral(T)) {
        return .{ @as(T, @intFromFloat(self.x)), @as(T, @intFromFloat(self.y)) };
    }
}

pub inline fn from(other: anytype) Vec2 {
    return .{ .x = other.x, .y = .other.y };
}

/// Will try to convert vec to a Vec2
/// e.g. if vec has an x field, it will use it,
/// same goes for the y field.
pub inline fn fromAny(vec: anytype) Vec2 {
    return .{
        .x = util.convertFieldToF32(vec, "x", 0),
        .y = util.convertFieldToF32(vec, "y", 0),
    };
}

pub inline fn extend(self: Vec2, z: f32) Vec3 {
    return .{ .x = self.x, .y = self.y, .z = z };
}

pub inline fn extendInto(self: Vec2, z: f32, comptime T: type) T {
    return .{ .x = self.x, .y = self.y, .z = z };
}

pub inline fn toDirAngle(self: Vec2) f32 {
    return math.atan2(f32, self.y, self.x);
}

pub inline fn fromDirAngle(theta: f32) Vec2 {
    return .{
        .x = math.cos(theta),
        .y = math.sin(theta),
    };
}

pub inline fn length(self: Vec2) f32 {
    return @sqrt((self.x * self.x) + (self.y * self.y));
}

pub inline fn sqrLength(self: Vec2) f32 {
    return (self.x * self.x) + (self.y * self.y);
}

pub inline fn min(a: Vec2, b: Vec2) Vec2 {
    return .{
        .x = @min(a.x, b.x),
        .y = @min(a.y, b.y),
    };
}

pub inline fn max(a: Vec2, b: Vec2) Vec2 {
    return .{
        .x = @max(a.x, b.x),
        .y = @max(a.y, b.y),
    };
}

pub inline fn getNegated(self: Vec2) Vec2 {
    return .{ .x = -self.x, .y = -self.y };
}

pub inline fn divide(v: Vec2, s: f32) Vec2 {
    return .{ .x = v.x / s, .y = v.y / s };
}

pub inline fn multiply(v: Vec2, s: f32) Vec2 {
    return .{ .x = v.x * s, .y = v.y * s };
}

pub inline fn add(v0: Vec2, v1: Vec2) Vec2 {
    return .{ .x = v0.x + v1.x, .y = v0.y + v1.y };
}

pub inline fn subtract(v0: Vec2, v1: Vec2) Vec2 {
    return .{ .x = v0.x - v1.x, .y = v0.y - v1.y };
}

pub inline fn scale(v0: Vec2, v1: Vec2) Vec2 {
    return .{ .x = v0.x * v1.x, .y = v0.y * v1.y };
}

pub inline fn lerp(orig: Vec2, to: Vec2, t: f32) Vec2 {
    const t_clamped = math.clamp(t, 0, 1);
    return .{
        .x = orig.x + (to.x - orig.x) * t_clamped,
        .y = orig.y + (to.y - orig.y) * t_clamped,
    };
}

pub inline fn lerpUnclamped(orig: Vec2, to: Vec2, t: f32) Vec2 {
    return .{
        .x = orig.x + (to.x - orig.x) * t,
        .y = orig.y + (to.y - orig.y) * t,
    };
}

pub inline fn perpendicular(dir: Vec2) Vec2 {
    return .{
        .x = -dir.y,
        .y = dir.x,
    };
}

pub inline fn dot(a: Vec2, b: Vec2) f32 {
    return a.x * b.x + a.y * b.y;
}

pub inline fn setNormalized(self: *Vec2) void {
    const m = length(self);
    if (m == 0) return;
    self.x /= m;
    self.y /= m;
}

pub inline fn setNegated(self: *Vec2) void {
    self.x = -self.x;
    self.y = -self.y;
}

pub inline fn plusEql(self: *Vec2, other: Vec2) void {
    self.x += other.x;
    self.y += other.y;
}

pub inline fn subEql(self: *Vec2, other: Vec2) void {
    self.x -= other.x;
    self.y -= other.y;
}

pub inline fn mulEql(self: *Vec2, scalar: f32) void {
    self.x *= scalar;
    self.y *= scalar;
}

pub inline fn divEql(self: *Vec2, scalar: f32) void {
    self.x /= scalar;
    self.y /= scalar;
}

pub inline fn scaleEql(self: *Vec2, other: Vec2) void {
    self.x *= other.x;
    self.y *= other.y;
}
