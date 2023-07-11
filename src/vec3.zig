const std = @import("std");
const math = std.math;
const util = @import("util.zig");
const Vec4 = @import("vec4.zig");

const Vec3 = @This();
pub usingnamespace @import("vec_funcs.zig").init(Vec3);

x: f32 = 0.0,
y: f32 = 0.0,
z: f32 = 0.0,

pub inline fn init(x: anytype, y: anytype, z: anytype) Vec3 {
    return .{
        .x = if (comptime @typeInfo(@TypeOf(x)) == .Int) @floatFromInt(x) else x,
        .y = if (comptime @typeInfo(@TypeOf(y)) == .Int) @floatFromInt(y) else y,
        .z = if (comptime @typeInfo(@TypeOf(z)) == .Int) @floatFromInt(z) else z,
    };
}

pub inline fn set(self: *Vec3, x: f32, y: f32, z: f32) void {
    self.x = x;
    self.y = y;
    self.z = z;
}

pub inline fn equals(a: Vec3, b: Vec3) bool {
    return a.x == b.x and a.y == b.y and a.z == b.z;
}

pub inline fn one() Vec3 {
    return .{ .x = 1, .y = 1, .z = 1 };
}

pub inline fn forward() Vec3 {
    return .{ .z = 1 };
}

pub inline fn backward() Vec3 {
    return .{ .z = -1 };
}

pub inline fn splat(s: f32) Vec3 {
    return .{ .x = s, .y = s, .z = s };
}

pub inline fn into(self: Vec3, comptime T: type) T {
    return .{ .x = self.x, .y = self.y, .z = self.z };
}

pub inline fn into2(self: Vec3, comptime T: type) T {
    return .{ .x = self.x, .y = self.y };
}

pub inline fn intoVectorOf(self: Vec3, comptime T: type) @Vector(3, T) {
    if (comptime std.meta.trait.isFloat(T)) {
        return .{ @floatCast(self.x), @floatCast(self.y), @floatCast(self.z) };
    } else if (comptime std.meta.trait.isIntegral(T)) {
        return .{ @intFromFloat(self.x), @intFromFloat(self.y), @intFromFloat(self.z) };
    }
}

pub inline fn from(other: anytype) Vec3 {
    return .{ .x = other.x, .y = other.y, .z = other.z };
}

pub inline fn from2(vec2: anytype, z: f32) Vec3 {
    return .{ .x = vec2.x, .y = vec2.y, .z = z };
}

/// Will try to convert vec to a Vec3
/// e.g. if vec has an x field, it will use it,
/// same goes for the y and z fields.
pub inline fn fromAny(vec: anytype) Vec3 {
    return .{
        .x = util.convertFieldToF32(vec, "x", 0),
        .y = util.convertFieldToF32(vec, "y", 0),
        .z = util.convertFieldToF32(vec, "z", 0),
    };
}

pub inline fn extend(self: Vec3, w: f32) Vec4 {
    return .{ .x = self.x, .y = self.y, .z = self.z, .w = w };
}

pub inline fn toQuatAsEuler(self: Vec3) Vec4 {
    return Vec4.fromEulerAngles(self);
}

pub inline fn cross(a: Vec3, b: Vec3) Vec3 {
    return .{
        .x = a.y * b.z - a.z * b.y,
        .y = a.z * b.x - a.x * b.z,
        .z = a.x * b.y - a.y * b.x,
    };
}

pub inline fn dot(a: Vec3, b: Vec3) f32 {
    return a.x * b.x + a.y * b.y + a.z * b.z;
}

pub inline fn length(self: Vec3) f32 {
    return @sqrt((self.x * self.x) + (self.y * self.y) + (self.z * self.z));
}

pub inline fn sqrLength(self: Vec3) f32 {
    return (self.x * self.x) + (self.y * self.y) + (self.z * self.z);
}

pub inline fn getNegated(self: Vec3) Vec3 {
    return .{ .x = -self.x, .y = -self.y, .z = -self.z };
}

pub inline fn divide(v: Vec3, s: f32) Vec3 {
    return .{ .x = v.x / s, .y = v.y / s, .z = v.z / s };
}

pub inline fn multiply(v: Vec3, s: f32) Vec3 {
    return .{ .x = v.x * s, .y = v.y * s, .z = v.z * s };
}

pub inline fn add(v0: Vec3, v1: Vec3) Vec3 {
    return .{ .x = v0.x + v1.x, .y = v0.y + v1.y, .z = v0.z + v1.z };
}

pub inline fn subtract(v0: Vec3, v1: Vec3) Vec3 {
    return .{ .x = v0.x - v1.x, .y = v0.y - v1.y, .z = v0.z - v1.z };
}

pub inline fn scale(v0: Vec3, v1: Vec3) Vec3 {
    return .{ .x = v0.x * v1.x, .y = v0.y * v1.y, .z = v0.z * v1.z };
}

pub inline fn setNormalized(self: *Vec3) void {
    const m = length(self);
    if (m == 0) return;
    self.x /= m;
    self.y /= m;
    self.z /= m;
}

pub inline fn setNegated(self: *Vec3) void {
    self.x = -self.x;
    self.y = -self.y;
    self.z = -self.z;
}

pub inline fn plusEql(self: *Vec3, other: Vec3) void {
    self.x += other.x;
    self.y += other.y;
    self.z += other.z;
}

pub inline fn subEql(self: *Vec3, other: Vec3) void {
    self.x -= other.x;
    self.y -= other.y;
    self.z -= other.z;
}

pub inline fn mulEql(self: *Vec3, scalar: f32) void {
    self.x *= scalar;
    self.y *= scalar;
    self.z *= scalar;
}

pub inline fn divEql(self: *Vec3, scalar: f32) void {
    self.x /= scalar;
    self.y /= scalar;
    self.z /= scalar;
}

pub inline fn scaleEql(self: *Vec3, other: Vec3) void {
    self.x *= other.x;
    self.y *= other.y;
    self.z *= other.z;
}
