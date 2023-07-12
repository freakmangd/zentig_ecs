const std = @import("std");
const math = std.math;
const util = @import("util.zig");
const Vec3 = @import("vec3.zig");

pub usingnamespace @import("vec_funcs.zig").init(Self);
const Self = @This();

x: f32 = 0.0,
y: f32 = 0.0,
z: f32 = 0.0,
w: f32 = 0.0,

pub inline fn init(x: anytype, y: anytype, z: anytype, w: anytype) Vec3 {
    return .{
        .x = if (comptime @typeInfo(@TypeOf(x)) == .Int) @floatFromInt(x) else x,
        .y = if (comptime @typeInfo(@TypeOf(y)) == .Int) @floatFromInt(y) else y,
        .z = if (comptime @typeInfo(@TypeOf(z)) == .Int) @floatFromInt(z) else z,
        .w = if (comptime @typeInfo(@TypeOf(w)) == .Int) @floatFromInt(w) else w,
    };
}

pub inline fn set(self: *Self, x: f32, y: f32, z: f32, w: f32) void {
    self.x = x;
    self.y = y;
    self.z = z;
    self.w = w;
}

pub inline fn equals(a: Self, b: Self) bool {
    return a.x == b.x and a.y == b.y and a.z == b.z and a.w == b.w;
}

pub inline fn one() Self {
    return .{ .x = 1, .y = 1, .z = 1, .w = 1 };
}

pub inline fn identity() Self {
    return .{ .w = 1 };
}

pub inline fn forward() Self {
    return .{ .z = 1 };
}

pub inline fn backward() Self {
    return .{ .z = -1 };
}

pub inline fn inside() Self {
    return .{ .w = 1 };
}

pub inline fn outside() Self {
    return .{ .w = -1 };
}

pub inline fn splat(s: f32) Self {
    return .{ .x = s, .y = s, .z = s, .w = s };
}

pub inline fn into(self: Self, comptime T: type) T {
    return .{ .x = self.x, .y = self.y, .z = self.z, .w = self.w };
}

pub inline fn into2(self: Self, comptime T: type) T {
    return .{ .x = self.x, .y = self.y };
}

pub inline fn into3(self: Self, comptime T: type) T {
    return .{ .x = self.x, .y = self.y, .z = self.z };
}

pub inline fn intoVectorOf(self: Self, comptime T: type) @Vector(4, T) {
    if (comptime std.meta.trait.isFloat(T)) {
        return .{ @floatCast(self.x), @floatCast(self.y), @floatCast(self.z), @floatCast(self.w) };
    } else if (comptime std.meta.trait.isIntegral(T)) {
        return .{ @intFromFloat(self.x), @intFromFloat(self.y), @intFromFloat(self.z), @intFromFloat(self.w) };
    }
}

pub inline fn from(other: anytype) Self {
    return .{ .x = other.x, .y = other.y, .z = other.z, .w = other.w };
}

pub inline fn from2(vec2: anytype, z: f32, w: f32) Self {
    return .{ .x = vec2.x, .y = vec2.y, .z = z, .w = w };
}

pub inline fn from3(vec3: anytype, w: f32) Self {
    return .{ .x = vec3.x, .y = vec3.y, .z = vec3.z, .w = w };
}

/// Will try to convert vec to a Vec4
/// e.g. if vec has an x field, it will use it,
/// same goes for the y, z, and w fields.
pub inline fn fromAny(vec: anytype) Self {
    return .{
        .x = util.convertFieldToF32(vec, "x", 0),
        .y = util.convertFieldToF32(vec, "y", 0),
        .z = util.convertFieldToF32(vec, "z", 0),
        .w = util.convertFieldToF32(vec, "w", 0),
    };
}

pub inline fn dot(a: Self, b: Self) f32 {
    return a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w;
}

pub inline fn length(self: Self) f32 {
    return @sqrt((self.x * self.x) + (self.y * self.y) + (self.z * self.z) + (self.w * self.w));
}

pub inline fn sqrLength(self: Self) f32 {
    return (self.x * self.x) + (self.y * self.y) + (self.z * self.z) + (self.w * self.w);
}

pub inline fn getNegated(self: Self) Self {
    return .{ .x = -self.x, .y = -self.y, .z = -self.z, .w = -self.w };
}

pub inline fn divide(v: Self, s: f32) Self {
    return .{ .x = v.x / s, .y = v.y / s, .z = v.z / s, .w = v.w / s };
}

pub inline fn multiply(v: Self, s: f32) Self {
    return .{ .x = v.x * s, .y = v.y * s, .z = v.z * s, .w = v.w * s };
}

pub inline fn add(v0: Self, v1: Self) Self {
    return .{ .x = v0.x + v1.x, .y = v0.y + v1.y, .z = v0.z + v1.z, .w = v0.w + v1.w };
}

pub inline fn subtract(v0: Self, v1: Self) Self {
    return .{ .x = v0.x - v1.x, .y = v0.y - v1.y, .z = v0.z - v1.z, .w = v0.w - v1.w };
}

pub inline fn scale(v0: Self, v1: Self) Self {
    return .{ .x = v0.x * v1.x, .y = v0.y * v1.y, .z = v0.z * v1.z, .w = v0.w * v1.w };
}

// Thank you unity: https://github.com/Unity-Technologies/UnityCsReference/blob/e7d9de5f09767c3320b6dab51bc2c2dc90447786/Runtime/Export/Math/Quaternion.cs#L87C9-L87C9
pub inline fn quatMultiply(v0: Self, v1: Self) Self {
    return .{
        .x = v0.w * v1.x + v0.x * v1.w + v0.y * v1.z - v0.z * v1.y,
        .y = v0.w * v1.y + v0.y * v1.w + v0.z * v1.x - v0.x * v1.z,
        .z = v0.w * v1.z + v0.z * v1.w + v0.x * v1.y - v0.y * v1.x,
        .w = v0.w * v1.w - v0.x * v1.x - v0.y * v1.y - v0.z * v1.z,
    };
}

// Thank you unity: https://github.com/Unity-Technologies/UnityCsReference/blob/e7d9de5f09767c3320b6dab51bc2c2dc90447786/Runtime/Export/Math/Quaternion.cs#L97C1-L97C1
pub fn quatRotatePoint(q: Self, p: Vec3) Vec3 {
    const dbl_q = q.multiply(2);

    const xx = q.x * dbl_q.x;
    const yy = q.y * dbl_q.y;
    const zz = q.z * dbl_q.z;

    const xy = q.x * dbl_q.y;
    const xz = q.x * dbl_q.z;
    const yz = q.y * dbl_q.z;
    const wx = q.w * dbl_q.x;
    const wy = q.w * dbl_q.y;
    const wz = q.w * dbl_q.z;

    return .{
        .x = (1 - (yy + zz)) * p.x + (xy - wz) * p.y + (xz + wy) * p.z,
        .y = (xy + wz) * p.x + (1 - (xx + zz)) * p.y + (yz - wx) * p.z,
        .z = (xz - wy) * p.x + (yz + wx) * p.y + (1 - (xx + yy)) * p.z,
    };
}

// Thank you unity: https://github.com/Unity-Technologies/UnityCsReference/blob/e7d9de5f09767c3320b6dab51bc2c2dc90447786/Runtime/Export/Math/Quaternion.cs#L169
pub fn quatAngle(a: Self, b: Self) f32 {
    const ab_dot = @min(@fabs(dot(a, b)), 1.0);
    if (ab_dot > 1.0 - std.math.floatEps(f32)) return 0.0;
    return math.acos(ab_dot) * 2.0;
}

// Thank you wikipedia: https://en.wikipedia.org/wiki/Conversion_between_quaternions_and_Euler_angles#Quaternion_to_Euler_angles_(in_3-2-1_sequence)_conversion
pub fn toEulerAngles(q: Self) Vec3 {
    const sinr_cosp = 2 * (q.w * q.x + q.y * q.z);
    const cosr_cosp = 1 - 2 * (q.x * q.x + q.y * q.y);

    const sinp = math.sqrt(1 + 2 * (q.w * q.y - q.x * q.z));
    const cosp = math.sqrt(1 - 2 * (q.w * q.y - q.x * q.z));

    const siny_cosp = 2 * (q.w * q.z + q.x * q.y);
    const cosy_cosp = 1 - 2 * (q.y * q.y + q.z * q.z);

    return .{
        .x = math.atan2(f32, sinr_cosp, cosr_cosp),
        .y = 2 * math.atan2(f32, sinp, cosp) - std.math.pi / 2.0,
        .z = math.atan2(f32, siny_cosp, cosy_cosp),
    };
}

// Thank you wikipedia: https://en.wikipedia.org/wiki/Conversion_between_quaternions_and_Euler_angles#Euler_angles_(in_3-2-1_sequence)_to_quaternion_conversion
pub fn fromEulerAngles(vec: Vec3) Self {
    const cr = math.cos(vec.x * 0.5);
    const sr = math.sin(vec.x * 0.5);
    const cp = math.cos(vec.y * 0.5);
    const sp = math.sin(vec.y * 0.5);
    const cy = math.cos(vec.z * 0.5);
    const sy = math.sin(vec.z * 0.5);

    return .{
        .x = sr * cp * cy - cr * sp * sy,
        .y = cr * sp * cy + sr * cp * sy,
        .z = cr * cp * sy - sr * sp * cy,
        .w = cr * cp * cy + sr * sp * sy,
    };
}

pub inline fn setNormalized(self: *Self) void {
    const m = length(self);
    if (m == 0) return;
    self.x /= m;
    self.y /= m;
    self.z /= m;
    self.w /= m;
}

pub inline fn setNegated(self: *Self) void {
    self.x = -self.x;
    self.y = -self.y;
    self.z = -self.z;
    self.w = -self.w;
}

pub inline fn plusEql(self: *Self, other: Self) void {
    self.x += other.x;
    self.y += other.y;
    self.z += other.z;
    self.w += other.w;
}

pub inline fn subEql(self: *Self, other: Self) void {
    self.x -= other.x;
    self.y -= other.y;
    self.z -= other.z;
    self.w -= other.w;
}

pub inline fn mulEql(self: *Self, scalar: f32) void {
    self.x *= scalar;
    self.y *= scalar;
    self.z *= scalar;
    self.w *= scalar;
}

pub inline fn divEql(self: *Self, scalar: f32) void {
    self.x /= scalar;
    self.y /= scalar;
    self.z /= scalar;
    self.w /= scalar;
}

pub inline fn scaleEql(self: *Self, other: Self) void {
    self.x *= other.x;
    self.y *= other.y;
    self.z *= other.z;
    self.w *= other.w;
}
