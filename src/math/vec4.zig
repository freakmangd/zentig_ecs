const std = @import("std");
const ztg = @import("../init.zig");
const math = std.math;
const util = ztg.util;

/// A vector of 4 `f32`s
pub const Vec4 = extern struct {
    const vec_funcs = @import("vec_funcs.zig");
    pub usingnamespace vec_funcs.init(Vec4);

    x: f32 = 0.0,
    y: f32 = 0.0,
    z: f32 = 0.0,
    w: f32 = 0.0,

    pub inline fn init(x: anytype, y: anytype, z: anytype, w: anytype) Vec4 {
        return .{
            .x = if (comptime @typeInfo(@TypeOf(x)) == .Int) @floatFromInt(x) else x,
            .y = if (comptime @typeInfo(@TypeOf(y)) == .Int) @floatFromInt(y) else y,
            .z = if (comptime @typeInfo(@TypeOf(z)) == .Int) @floatFromInt(z) else z,
            .w = if (comptime @typeInfo(@TypeOf(w)) == .Int) @floatFromInt(w) else w,
        };
    }

    pub inline fn set(self: *Vec4, x: anytype, y: anytype, z: anytype, w: anytype) void {
        self.x = if (comptime @typeInfo(@TypeOf(x)) == .Int) @floatFromInt(x) else x;
        self.y = if (comptime @typeInfo(@TypeOf(y)) == .Int) @floatFromInt(y) else y;
        self.z = if (comptime @typeInfo(@TypeOf(z)) == .Int) @floatFromInt(z) else z;
        self.w = if (comptime @typeInfo(@TypeOf(w)) == .Int) @floatFromInt(w) else w;
    }

    /// Shorthand for .{ .w = 1 }
    pub inline fn identity() Vec4 {
        return .{ .w = 1 };
    }

    /// Shorthand for .{ .w = 1 }
    pub inline fn inside() Vec4 {
        return .{ .w = 1 };
    }

    /// Shorthand for .{ .w = -1 }
    pub inline fn outside() Vec4 {
        return .{ .w = -1 };
    }

    /// Returns T with all of it's components set to the original vector's
    /// T's only required components must be `x`, `y`, `z`, and `w`
    pub inline fn into(self: Vec4, comptime T: type) T {
        if (comptime vec_funcs.isBitcastable(Vec4, T)) return @bitCast(self);
        return .{ .x = @floatCast(self.x), .y = @floatCast(self.y), .z = @floatCast(self.z), .w = @floatCast(self.w) };
    }

    /// Returns T with it's x and y components set to the original vector's x and y
    /// T's only required components must be `x` and `y`
    pub inline fn intoVec2(self: Vec4, comptime T: type) T {
        return .{ .x = @floatCast(self.x), .y = @floatCast(self.y) };
    }

    /// Returns T with it's x and y components set to the original vector's x, y and z
    /// T's only required components must be `x`, `y`, and `z`
    pub inline fn intoVec3(self: Vec4, comptime T: type) T {
        return .{ .x = @floatCast(self.x), .y = @floatCast(self.y), .z = @floatCast(self.z) };
    }

    /// Converts the Vector into a @Vector object of type `T`, doing
    /// the necessary conversions.
    pub inline fn intoVectorOf(self: Vec4, comptime T: type) @Vector(4, T) {
        if (@typeInfo(T) == .Float or @typeInfo(T) == .ComptimeFloat) {
            if (comptime T == f32) {
                return self.intoSimd();
            } else {
                return .{ @floatCast(self.x), @floatCast(self.y), @floatCast(self.z), @floatCast(self.w) };
            }
        } else if (@typeInfo(T) == .Int or @typeInfo(T) == .ComptimeInt) {
            return .{ @intFromFloat(self.x), @intFromFloat(self.y), @intFromFloat(self.z), @intFromFloat(self.w) };
        } else {
            util.compileError("Cannot turn self into a vector of `{s}`", .{@typeName(T)});
        }
    }

    /// For use when integrating with the zmath library
    pub const intoZMath = Vec4.intoSimd;

    /// For use when integrating with the zmath library
    pub const fromZMath = Vec4.fromSimd;

    /// Creates a Vec4 from other, other must have `x`, `y`, `z`, and `w` components
    pub inline fn from(other: anytype) Vec4 {
        if (comptime vec_funcs.isBitcastable(Vec4, @TypeOf(other))) return @bitCast(other);
        return .{ .x = @floatCast(other.x), .y = @floatCast(other.y), .z = @floatCast(other.z), .w = @floatCast(other.w) };
    }

    /// Creates a Vec4 from other, other must have `x`, and `y` components
    pub inline fn fromVec2(vec2: anytype, z: f32, w: f32) Vec4 {
        return .{ .x = @floatCast(vec2.x), .y = @floatCast(vec2.y), .z = z, .w = w };
    }

    /// Creates a Vec4 from other, other must have `x`, `y`, and `z` components
    pub inline fn fromVec3(vec3: anytype, w: f32) Vec4 {
        return .{ .x = @floatCast(vec3.x), .y = @floatCast(vec3.y), .z = @floatCast(vec3.z), .w = w };
    }

    /// Will try to convert vec to a Vec4
    /// e.g. if vec has an x field, it will use it,
    /// same goes for the y, z, and w fields.
    pub inline fn fromAny(vec: anytype) Vec4 {
        return .{
            .x = vec_funcs.convertFieldToF32(vec, "x", 0),
            .y = vec_funcs.convertFieldToF32(vec, "y", 0),
            .z = vec_funcs.convertFieldToF32(vec, "z", 0),
            .w = vec_funcs.convertFieldToF32(vec, "w", 0),
        };
    }

    /// Returns a `Vec3` from self, discarding the `w` component
    pub inline fn flatten(self: Vec4) ztg.Vec3 {
        return self.flattenInto(ztg.Vec3);
    }

    /// Creates a `T`, which must have `x`, `y`, and `z` components, from self and discards the `w` component
    pub inline fn flattenInto(self: Vec4, comptime T: type) T {
        return .{ .x = @floatCast(self.x), .y = @floatCast(self.y), .z = @floatCast(self.z) };
    }

    pub inline fn quatMultiply(v0: Vec4, v1: Vec4) Vec4 {
        return Vec4.fromZMath(ztg.zmath.qmul(v0.intoZMath(), v1.intoZMath()));
    }

    pub inline fn quatRotatePoint(q: Vec4, p: ztg.Vec3) ztg.Vec3 {
        return ztg.Vec3.fromZMath(ztg.zmath.rotate(q.intoZMath(), p.intoZMath()));
    }

    // Thank you unity: https://github.com/Unity-Technologies/UnityCsReference/blob/e7d9de5f09767c3320b6dab51bc2c2dc90447786/Runtime/Export/Math/Quaternion.cs#L169
    pub fn quatAngle(a: Vec4, b: Vec4) f32 {
        const ab_dot = @min(@abs(Vec4.dot(a, b)), 1.0);
        if (ab_dot > 1.0 - std.math.floatEps(f32)) return 0.0;
        return math.acos(ab_dot) * 2.0;
    }

    // Thank you wikipedia: https://en.wikipedia.org/wiki/Conversion_between_quaternions_and_Euler_angles#Quaternion_to_Euler_angles_(in_3-2-1_sequence)_conversion
    pub fn toEulerAngles(q: Vec4) ztg.Vec3 {
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
    pub fn fromEulerAngles(vec: ztg.Vec3) Vec4 {
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

    pub fn format(value: Vec4, comptime fmt: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print(std.fmt.comptimePrint("Vec4({{{s}}}, {{{s}}}, {{{s}}}, {{{s}}})", .{ fmt, fmt, fmt, fmt }), .{ value.x, value.y, value.z, value.w });
    }
};
