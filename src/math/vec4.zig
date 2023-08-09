const std = @import("std");
const ztg = @import("../init.zig");
const math = std.math;
const util = ztg.util;

pub const Vec4 = extern struct {
    const vec_funcs = @import("vec_funcs.zig");
    pub usingnamespace vec_funcs.init(Vec4);

    const Self = @This();

    x: f32 = 0.0,
    y: f32 = 0.0,
    z: f32 = 0.0,
    w: f32 = 0.0,

    pub inline fn init(x: anytype, y: anytype, z: anytype, w: anytype) Self {
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

    /// Shorthand for .{ .w = 1 }
    pub inline fn identity() Self {
        return .{ .w = 1 };
    }

    /// Shorthand for .{ .w = 1 }
    pub inline fn inside() Self {
        return .{ .w = 1 };
    }

    /// Shorthand for .{ .w = -1 }
    pub inline fn outside() Self {
        return .{ .w = -1 };
    }

    /// Returns T with all of it's components set to the original vector's
    /// T's only required components must be `x`, `y`, `z`, and `w`
    pub inline fn into(self: Self, comptime T: type) T {
        return .{ .x = self.x, .y = self.y, .z = self.z, .w = self.w };
    }

    /// Returns T with it's x and y components set to the original vector's x and y
    /// T's only required components must be `x` and `y`
    pub inline fn intoVec2(self: Self, comptime T: type) T {
        return .{ .x = self.x, .y = self.y };
    }

    /// Returns T with it's x and y components set to the original vector's x, y and z
    /// T's only required components must be `x`, `y`, and `z`
    pub inline fn intoVec3(self: Self, comptime T: type) T {
        return .{ .x = self.x, .y = self.y, .z = self.z };
    }

    /// Converts the Vector into a @Vector object of type `T`, doing
    /// the necessary conversions.
    pub inline fn intoVectorOf(self: Self, comptime T: type) @Vector(4, T) {
        if (comptime std.meta.trait.isFloat(T)) {
            if (comptime T == f32) {
                return self.intoSimd();
            } else {
                return .{ @floatCast(self.x), @floatCast(self.y), @floatCast(self.z), @floatCast(self.w) };
            }
        } else if (comptime std.meta.trait.isIntegral(T)) {
            return .{ @intFromFloat(self.x), @intFromFloat(self.y), @intFromFloat(self.z), @intFromFloat(self.w) };
        } else {
            @compileError("Cannot turn self into a vector of " ++ @typeName(T));
        }
    }

    /// For use when integrating with the zmath library
    pub const intoZMath = Self.intoSimd;

    /// For use when integrating with the zmath library
    pub const fromZMath = Self.fromSimd;

    /// Creates a Vec4 from other, other must have `x`, `y`, `z`, and `w` components
    pub inline fn from(other: anytype) Self {
        return .{ .x = other.x, .y = other.y, .z = other.z, .w = other.w };
    }

    /// Creates a Vec4 from other, other must have `x`, and `y` components
    pub inline fn fromVec2(vec2: anytype, z: f32, w: f32) Self {
        return .{ .x = vec2.x, .y = vec2.y, .z = z, .w = w };
    }

    /// Creates a Vec4 from other, other must have `x`, `y`, and `z` components
    pub inline fn fromVec3(vec3: anytype, w: f32) Self {
        return .{ .x = vec3.x, .y = vec3.y, .z = vec3.z, .w = w };
    }

    /// Will try to convert vec to a Vec4
    /// e.g. if vec has an x field, it will use it,
    /// same goes for the y, z, and w fields.
    pub inline fn fromAny(vec: anytype) Self {
        return .{
            .x = vec_funcs.convertFieldToF32(vec, "x", 0),
            .y = vec_funcs.convertFieldToF32(vec, "y", 0),
            .z = vec_funcs.convertFieldToF32(vec, "z", 0),
            .w = vec_funcs.convertFieldToF32(vec, "w", 0),
        };
    }

    /// Returns a `Vec3` from self, discarding the `w` component
    pub inline fn flatten(self: Self) ztg.Vec3 {
        return self.flattenInto(ztg.Vec3);
    }

    /// Creates a `T`, which must have `x`, `y`, and `z` components, from self and discards the `w` component
    pub inline fn flattenInto(self: Self, comptime T: type) T {
        return .{ .x = self.x, .y = self.y, .z = self.z };
    }

    pub inline fn quatMultiply(v0: Self, v1: Self) Self {
        return Self.fromZMath(ztg.zmath.qmul(v0.intoZMath(), v1.intoZMath()));
    }

    pub inline fn quatRotatePoint(q: Self, p: ztg.Vec3) ztg.Vec3 {
        return ztg.Vec3.fromZMath(ztg.zmath.rotate(q.intoZMath(), p.intoZMath()));
    }

    // Thank you unity: https://github.com/Unity-Technologies/UnityCsReference/blob/e7d9de5f09767c3320b6dab51bc2c2dc90447786/Runtime/Export/Math/Quaternion.cs#L169
    pub fn quatAngle(a: Self, b: Self) f32 {
        const ab_dot = @min(@fabs(Self.dot(a, b)), 1.0);
        if (ab_dot > 1.0 - std.math.floatEps(f32)) return 0.0;
        return math.acos(ab_dot) * 2.0;
    }

    // Thank you wikipedia: https://en.wikipedia.org/wiki/Conversion_between_quaternions_and_Euler_angles#Quaternion_to_Euler_angles_(in_3-2-1_sequence)_conversion
    pub fn toEulerAngles(q: Self) ztg.Vec3 {
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
    pub fn fromEulerAngles(vec: ztg.Vec3) Self {
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

    pub fn format(value: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;
        try writer.print("Vec4({" ++ fmt ++ "}, {" ++ fmt ++ "}, {" ++ fmt ++ "}, {" ++ fmt ++ "})", .{ value.x, value.y, value.z, value.w });
    }
};
