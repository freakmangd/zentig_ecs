const std = @import("std");

pub const Vec2 = struct {
    x: f32 = 0.0,
    y: f32 = 0.0,

    pub inline fn new(x: f32, y: f32) Vec2 {
        return .{ .x = x, .y = y };
    }

    pub inline fn splat(s: f32) Vec2 {
        return .{ .x = s, .y = s };
    }

    pub inline fn one() Vec2 {
        return .{ .x = 1, .y = 1 };
    }

    pub inline fn zero() Vec2 {
        return .{};
    }

    pub inline fn as(self: Vec2, comptime T: type) @Vector(2, T) {
        if (comptime std.meta.trait.isFloat(T)) {
            return .{ @floatCast(T, self.x), @floatCast(T, self.y) };
        } else if (comptime std.meta.trait.isIntegral(T)) {
            return .{ @floatToInt(T, self.x), @floatToInt(T, self.y) };
        }
    }

    pub inline fn copy(self: Vec2) Vec2 {
        return .{ .x = self.x, .y = self.y };
    }

    pub fn length(self: Vec2) f32 {
        return @sqrt((self.x * self.x) + (self.y * self.y));
    }

    pub fn sqrLength(self: Vec2) f32 {
        return (self.x * self.x) + (self.y * self.y);
    }

    pub fn getNormalized(self: Vec2) error{DivideByZero}!Vec2 {
        const m = length(self);
        if (m == 0) return error.DivideByZero;
        return divide(self, m);
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

    pub fn setNormalized(self: *Vec2) error{DivideByZero}!void {
        const m = length(self);
        if (m == 0) return error.DivideByZero;
        self.x /= m;
        self.y /= m;
    }

    pub fn setNegated(self: *Vec2) void {
        self.x = -self.x;
        self.y = -self.y;
    }

    pub fn plusEql(self: *Vec2, other: Vec2) void {
        self.x += other.x;
        self.y += other.y;
    }

    pub fn subEql(self: *Vec2, other: Vec2) void {
        self.x -= other.x;
        self.y -= other.y;
    }

    pub fn mulEql(self: *Vec2, scalar: f32) void {
        self.x *= scalar;
        self.y *= scalar;
    }

    pub fn divEql(self: *Vec2, scalar: f32) void {
        self.x /= scalar;
        self.y /= scalar;
    }

    pub fn scaleEql(self: *Vec2, other: Vec2) void {
        self.x = self.x * other.x;
        self.y = self.y * other.y;
    }
};

pub const Vec3 = struct {
    x: f32 = 0.0,
    y: f32 = 0.0,
    z: f32 = 0.0,

    pub inline fn new(x: f32, y: f32, z: f32) Vec3 {
        return .{ .x = x, .y = y, .z = z };
    }

    pub inline fn zero() Vec3 {
        return .{};
    }

    pub inline fn one() Vec3 {
        return .{ .x = 1, .y = 1, .z = 1 };
    }

    pub inline fn splat(s: f32) Vec3 {
        return .{ .x = s, .y = s, .z = s };
    }

    pub inline fn as(self: Vec3, comptime T: type) @Vector(2, T) {
        if (comptime std.meta.trait.isFloat(T)) {
            return .{ @floatCast(T, self.x), @floatCast(T, self.y) };
        } else if (comptime std.meta.trait.isIntegral(T)) {
            return .{ @floatToInt(T, self.x), @floatToInt(T, self.y) };
        }
    }

    pub inline fn copy(self: Vec3) Vec3 {
        return .{ .x = self.x, .y = self.y, .z = self.z };
    }

    pub fn length(self: Vec3) f32 {
        return @sqrt((self.x * self.x) + (self.y * self.y) + (self.z * self.z));
    }

    pub fn sqrLength(self: Vec3) f32 {
        return (self.x * self.x) + (self.y * self.y) + (self.z * self.z);
    }

    pub fn getNormalized(self: Vec3) error{DivideByZero}!Vec3 {
        const m = length(self);
        if (m == 0) return error.DivideByZero;
        return divide(self, m);
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

    pub fn setNormalized(self: *Vec3) error{DivideByZero}!void {
        const m = length(self);
        if (m == 0) return error.DivideByZero;
        self.x /= m;
        self.y /= m;
        self.z /= m;
    }

    pub fn setNegated(self: *Vec3) void {
        self.x = -self.x;
        self.y = -self.y;
        self.z = -self.z;
    }

    pub fn plusEql(self: *Vec3, other: Vec3) void {
        self.x += other.x;
        self.y += other.y;
        self.z += other.z;
    }

    pub fn subEql(self: *Vec3, other: Vec3) void {
        self.x -= other.x;
        self.y -= other.y;
        self.z -= other.z;
    }

    pub fn mulEql(self: *Vec3, scalar: f32) void {
        self.x *= scalar;
        self.y *= scalar;
        self.z *= scalar;
    }

    pub fn divEql(self: *Vec3, scalar: f32) void {
        self.x /= scalar;
        self.y /= scalar;
        self.z /= scalar;
    }

    pub fn scaleEql(self: *Vec3, other: Vec3) void {
        self.x = self.x * other.x;
        self.y = self.y * other.y;
        self.z = self.z * other.z;
    }
};

pub const Quaternion = struct {
    x: f32 = 0.0,
    y: f32 = 0.0,
    z: f32 = 0.0,
    w: f32 = 0.0,

    // TODO: actually make quaternions work lmao
    pub fn identity() Quaternion {
        return .{ .x = 0, .y = 0, .z = 0, .w = 0 };
    }
};
