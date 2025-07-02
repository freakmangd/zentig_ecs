const std = @import("std");
const ztg = @import("../init.zig");
const math = std.math;
const util = ztg.util;

/// A vector of 4 `f32`s
pub const Vec4 = extern struct {
    x: f32 = 0.0,
    y: f32 = 0.0,
    z: f32 = 0.0,
    w: f32 = 0.0,

    pub const one = splat(1);
    pub const zero: Vec4 = .{};
    pub const right: Vec4 = .{ .x = 1 };
    pub const left: Vec4 = .{ .x = -1 };
    pub const up: Vec4 = .{ .y = 1 };
    pub const down: Vec4 = .{ .y = -1 };
    pub const forward: Vec4 = .{ .z = 1 };
    pub const backward: Vec4 = .{ .z = -1 };
    pub const inward: Vec4 = .{ .w = 1 };
    pub const outward: Vec4 = .{ .w = -1 };

    pub fn init(x: anytype, y: anytype, z: anytype, w: anytype) Vec4 {
        return .{
            .x = if (comptime @typeInfo(@TypeOf(x)) == .int) @floatFromInt(x) else x,
            .y = if (comptime @typeInfo(@TypeOf(y)) == .int) @floatFromInt(y) else y,
            .z = if (comptime @typeInfo(@TypeOf(z)) == .int) @floatFromInt(z) else z,
            .w = if (comptime @typeInfo(@TypeOf(w)) == .int) @floatFromInt(w) else w,
        };
    }

    pub fn set(self: *Vec4, x: anytype, y: anytype, z: anytype, w: anytype) void {
        self.x = if (comptime @typeInfo(@TypeOf(x)) == .int) @floatFromInt(x) else x;
        self.y = if (comptime @typeInfo(@TypeOf(y)) == .int) @floatFromInt(y) else y;
        self.z = if (comptime @typeInfo(@TypeOf(z)) == .int) @floatFromInt(z) else z;
        self.w = if (comptime @typeInfo(@TypeOf(w)) == .int) @floatFromInt(w) else w;
    }

    /// Shorthand for .{ .w = 1 }
    pub const identity: Vec4 = .{ .w = 1 };

    /// Returns T with all of its components set to the original vector's
    /// T's only required components must be `x`, `y`, `z`, and `w`
    pub fn into(self: Vec4, comptime T: type) T {
        if (comptime vec_funcs.isBitcastable(Vec4, T)) return @bitCast(self);
        return .{ .x = @floatCast(self.x), .y = @floatCast(self.y), .z = @floatCast(self.z), .w = @floatCast(self.w) };
    }

    /// Returns T with its x and y components set to the original vector's x and y
    /// T's only required components must be `x` and `y`
    pub fn intoVec2(self: Vec4, comptime T: type) T {
        return .{ .x = @floatCast(self.x), .y = @floatCast(self.y) };
    }

    /// Returns T with its x and y components set to the original vector's x, y and z
    /// T's only required components must be `x`, `y`, and `z`
    pub fn intoVec3(self: Vec4, comptime T: type) T {
        return .{ .x = @floatCast(self.x), .y = @floatCast(self.y), .z = @floatCast(self.z) };
    }

    /// Converts the Vector into a @Vector object of type `T`, doing
    /// the necessary conversions.
    pub fn intoVectorOf(self: Vec4, comptime T: type) @Vector(4, T) {
        if (@typeInfo(T) == .float or @typeInfo(T) == .comptime_float) {
            if (comptime T == f32) {
                return self.intoSimd();
            } else {
                return .{ @floatCast(self.x), @floatCast(self.y), @floatCast(self.z), @floatCast(self.w) };
            }
        } else if (@typeInfo(T) == .int or @typeInfo(T) == .comptime_int) {
            return .{ @intFromFloat(self.x), @intFromFloat(self.y), @intFromFloat(self.z), @intFromFloat(self.w) };
        } else {
            util.compileError("Cannot turn self into a vector of `{s}`", .{@typeName(T)});
        }
    }

    /// For use when integrating with the zmath library, sets z and w to 0
    pub fn intoZMath(self: Vec4) @Vector(4, f32) {
        return @bitCast(self);
    }

    /// For use when integrating with the zmath library, discards z and w components
    pub fn fromZMath(vec: @Vector(4, f32)) Vec4 {
        return @bitCast(vec);
    }

    /// Creates a Vec4 from other, other must have `x`, `y`, `z`, and `w` components
    pub fn from(other: anytype) Vec4 {
        if (comptime vec_funcs.isBitcastable(Vec4, @TypeOf(other))) return @bitCast(other);
        return .{ .x = @floatCast(other.x), .y = @floatCast(other.y), .z = @floatCast(other.z), .w = @floatCast(other.w) };
    }

    /// Creates a Vec4 from other, other must have `x`, and `y` components
    pub fn fromVec2(vec2: anytype, z: f32, w: f32) Vec4 {
        return .{ .x = @floatCast(vec2.x), .y = @floatCast(vec2.y), .z = z, .w = w };
    }

    /// Creates a Vec4 from other, other must have `x`, `y`, and `z` components
    pub fn fromVec3(vec3: anytype, w: f32) Vec4 {
        return .{ .x = @floatCast(vec3.x), .y = @floatCast(vec3.y), .z = @floatCast(vec3.z), .w = w };
    }

    /// Will try to convert vec to a Vec4
    /// e.g. if vec has an x field, it will use it,
    /// same goes for the y, z, and w fields.
    pub fn fromAny(vec: anytype) Vec4 {
        return .{
            .x = vec_funcs.convertFieldToF32(vec, "x", 0),
            .y = vec_funcs.convertFieldToF32(vec, "y", 0),
            .z = vec_funcs.convertFieldToF32(vec, "z", 0),
            .w = vec_funcs.convertFieldToF32(vec, "w", 0),
        };
    }

    /// Returns a `Vec3` from self, discarding the `w` component
    pub fn flatten(self: Vec4) ztg.Vec3 {
        return self.flattenInto(ztg.Vec3);
    }

    /// Creates a `T`, which must have `x`, `y`, and `z` components, from self and discards the `w` component
    pub fn flattenInto(self: Vec4, comptime T: type) T {
        return .{ .x = @floatCast(self.x), .y = @floatCast(self.y), .z = @floatCast(self.z) };
    }

    pub fn quatMultiply(v0: Vec4, v1: Vec4) Vec4 {
        return Vec4.fromZMath(ztg.zmath.qmul(v0.intoZMath(), v1.intoZMath()));
    }

    pub fn quatRotatePoint(q: Vec4, p: ztg.Vec3) ztg.Vec3 {
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
        const cr = @cos(vec.x * 0.5);
        const sr = @sin(vec.x * 0.5);
        const cp = @cos(vec.y * 0.5);
        const sp = @sin(vec.y * 0.5);
        const cy = @cos(vec.z * 0.5);
        const sy = @sin(vec.z * 0.5);

        return .{
            .x = sr * cp * cy - cr * sp * sy,
            .y = cr * sp * cy + sr * cp * sy,
            .z = cr * cp * sy - sr * sp * cy,
            .w = cr * cp * cy + sr * sp * sy,
        };
    }

    pub fn format(value: Vec4, comptime _fmt: []const u8, opt: std.fmt.FormatOptions, writer: anytype) !void {
        const start_str, const fmt = comptime blk: {
            if (_fmt.len > 0 and _fmt[0] == 's') break :blk .{ "(", _fmt[1..] };
            break :blk .{ "Vec4(", _fmt };
        };
        try writer.writeAll(start_str);
        try util.formatFloatValue(value.x, fmt, opt, writer);
        try writer.writeAll(", ");
        try util.formatFloatValue(value.y, fmt, opt, writer);
        try writer.writeAll(", ");
        try util.formatFloatValue(value.z, fmt, opt, writer);
        try writer.writeAll(", ");
        try util.formatFloatValue(value.w, fmt, opt, writer);
        try writer.writeAll(")");
    }

    const vec_funcs = @import("vec_funcs.zig");
    const generated_funcs = vec_funcs.GenerateFunctions(Vec4);
    comptime {
        ztg.meta.checkMixin(Vec4, generated_funcs);
    }

    pub const equals = generated_funcs.equals;
    pub const approxEqRelBy = generated_funcs.approxEqRelBy;
    pub const approxEqAbsBy = generated_funcs.approxEqAbsBy;
    pub const approxEqRel = generated_funcs.approxEqRel;
    pub const approxEqAbs = generated_funcs.approxEqAbs;
    pub const expectEqual = generated_funcs.expectEqual;
    pub const expectApproxEqAbs = generated_funcs.expectApproxEqAbs;
    pub const expectApproxEqRel = generated_funcs.expectApproxEqRel;
    pub const splat = generated_funcs.splat;
    pub const copy = generated_funcs.copy;
    pub const intoSimd = generated_funcs.intoSimd;
    pub const intoArray = generated_funcs.intoArray;
    pub const abs = generated_funcs.abs;
    pub const angle = generated_funcs.angle;
    pub const angleSigned = generated_funcs.angleSigned;
    pub const directionTo = generated_funcs.directionTo;
    pub const distance = generated_funcs.distance;
    pub const sqrDistance = generated_funcs.sqrDistance;
    pub const dot = generated_funcs.dot;
    pub const getNormalized = generated_funcs.getNormalized;
    pub const setNormalized = generated_funcs.setNormalized;
    pub const length = generated_funcs.length;
    pub const sqrLength = generated_funcs.sqrLength;
    pub const lerp = generated_funcs.lerp;
    pub const lerpUnclamped = generated_funcs.lerpUnclamped;
    pub const moveTowards = generated_funcs.moveTowards;
    pub const max = generated_funcs.max;
    pub const min = generated_funcs.min;
    pub const project = generated_funcs.project;
    pub const reflect = generated_funcs.reflect;
    pub const random01 = generated_funcs.random01;
    pub const swizzle = generated_funcs.swizzle;
    pub const shuffle = generated_funcs.shuffle;
    pub const withClampedLength = generated_funcs.withClampedLength;
    pub const getNegated = generated_funcs.getNegated;
    pub const setNegated = generated_funcs.setNegated;
    pub const add = generated_funcs.add;
    pub const sub = generated_funcs.sub;
    pub const mul = generated_funcs.mul;
    pub const div = generated_funcs.div;
    pub const scale = generated_funcs.scale;
    pub const addEql = generated_funcs.addEql;
    pub const subEql = generated_funcs.subEql;
    pub const mulEql = generated_funcs.mulEql;
    pub const divEql = generated_funcs.divEql;
    pub const scaleEql = generated_funcs.scaleEql;
    pub const axis = generated_funcs.axis;
};
