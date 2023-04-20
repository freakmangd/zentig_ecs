const std = @import("std");

pub const Vec2 = struct {
    x: f32,
    y: f32,

    pub inline fn new(x: f32, y: f32) Vec2 {
        return .{ .x = x, .y = y };
    }

    pub inline fn splat(s: f32) Vec2 {
        return .{ .x = s, .y = s };
    }

    pub inline fn one() Vec2 {
        return .{ .x = 1, .y = 1 };
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
};

pub const Vec3 = struct {
    x: f32,
    y: f32,
    z: f32,

    pub inline fn new(x: f32, y: f32, z: f32) Vec3 {
        return .{ .x = x, .y = y, .z = z };
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
};

pub const Quaternion = struct {
    x: f32,
    y: f32,
    z: f32,
    w: f32,

    // TODO: actually make quaternions work lmao
    pub fn identity() Quaternion {
        return .{ .x = 0, .y = 0, .z = 0, .w = 0 };
    }
};
