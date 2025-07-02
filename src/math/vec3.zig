const std = @import("std");
const ztg = @import("../init.zig");
const math = std.math;
const util = @import("../util.zig");

/// A vector of 3 `f32`s
pub const Vec3 = extern struct {
    x: f32 = 0.0,
    y: f32 = 0.0,
    z: f32 = 0.0,

    pub const one = splat(1);
    pub const zero: Vec3 = .{};
    pub const right: Vec3 = .{ .x = 1 };
    pub const left: Vec3 = .{ .x = -1 };
    pub const up: Vec3 = .{ .y = 1 };
    pub const down: Vec3 = .{ .y = -1 };
    pub const forward: Vec3 = .{ .z = 1 };
    pub const backward: Vec3 = .{ .z = -1 };

    pub fn init(x: anytype, y: anytype, z: anytype) Vec3 {
        return .{
            .x = if (comptime @typeInfo(@TypeOf(x)) == .int) @floatFromInt(x) else x,
            .y = if (comptime @typeInfo(@TypeOf(y)) == .int) @floatFromInt(y) else y,
            .z = if (comptime @typeInfo(@TypeOf(z)) == .int) @floatFromInt(z) else z,
        };
    }

    pub fn set(self: *Vec3, x: anytype, y: anytype, z: anytype) void {
        self.x = if (comptime @typeInfo(@TypeOf(x)) == .int) @floatFromInt(x) else x;
        self.y = if (comptime @typeInfo(@TypeOf(y)) == .int) @floatFromInt(y) else y;
        self.z = if (comptime @typeInfo(@TypeOf(z)) == .int) @floatFromInt(z) else z;
    }

    /// Returns T with all of it's components set to the original vector's
    /// T's only required components must be `x`, `y`, and `z`
    pub fn into(self: Vec3, comptime T: type) T {
        if (comptime vec_funcs.isBitcastable(Vec3, T)) return @bitCast(self);
        return .{ .x = @floatCast(self.x), .y = @floatCast(self.y), .z = @floatCast(self.z) };
    }

    /// Returns T with it's x and y components set to the original vector's x and y
    /// T's only required components must be `x` and `y`
    pub fn intoVec2(self: Vec3, comptime T: type) T {
        return .{ .x = @floatCast(self.x), .y = @floatCast(self.y) };
    }

    /// Converts the Vector into a @Vector object of type `T`, doing
    /// the necessary conversions.
    pub fn intoVectorOf(self: Vec3, comptime T: type) @Vector(3, T) {
        if (@typeInfo(T) == .float or @typeInfo(T) == .comptime_float) {
            if (comptime T == f32) {
                return self.intoSimd();
            } else {
                return .{ @floatCast(self.x), @floatCast(self.y), @floatCast(self.z) };
            }
        } else if (@typeInfo(T) == .int) {
            return .{ @intFromFloat(self.x), @intFromFloat(self.y), @intFromFloat(self.z) };
        } else {
            util.compileError("Cannot turn self into a vector of `{s}`", .{@typeName(T)});
        }
    }

    /// Returns a Quaternion from self, interpreting self as having Euler angles
    pub fn intoQuatAsEuler(self: Vec3) ztg.Vec4 {
        return ztg.Vec4.fromEulerAngles(self);
    }

    /// For use when integrating with the zmath library, sets w to 0
    pub fn intoZMath(self: Vec3) @Vector(4, f32) {
        return .{ self.x, self.y, self.z, 0.0 };
    }

    /// For use when integrating with the zmath library, ignores w component
    pub fn fromZMath(vec: @Vector(4, f32)) Vec3 {
        return .{ .x = vec[0], .y = vec[1], .z = vec[2] };
    }

    /// Creates a Vec3 from other, other must have `x`, `y`, and `z` components
    pub fn from(other: anytype) Vec3 {
        if (comptime vec_funcs.isBitcastable(Vec3, @TypeOf(other))) return @bitCast(other);
        return .{ .x = @floatCast(other.x), .y = @floatCast(other.y), .z = @floatCast(other.z) };
    }

    /// Creates a Vec3 from other, other must have `x` and `y` components
    pub fn fromVec2(vec2: anytype, z: f32) Vec3 {
        return .{ .x = @floatCast(vec2.x), .y = @floatCast(vec2.y), .z = z };
    }

    /// Will try to convert vec to a `Vec3`
    /// e.g. if `vec` has an `x` field, it will use it,
    /// same goes for the `y` and `z` fields.
    pub fn fromAny(vec: anytype) Vec3 {
        return .{
            .x = vec_funcs.convertFieldToF32(vec, "x", 0),
            .y = vec_funcs.convertFieldToF32(vec, "y", 0),
            .z = vec_funcs.convertFieldToF32(vec, "z", 0),
        };
    }

    /// Creates a `Vec4` from `self` and sets the `w` component
    pub fn extend(self: Vec3, w: f32) ztg.Vec4 {
        return self.extendInto(ztg.Vec4, w);
    }

    /// Creates a `T`, which must have `x`, `y`, `z`, and `w` components, from self and sets the `w` component
    pub fn extendInto(self: Vec3, comptime T: type, w: f32) T {
        return .{ .x = @floatCast(self.x), .y = @floatCast(self.y), .z = @floatCast(self.z), .w = w };
    }

    /// Returns a `Vec2` from self, discarding the `z` component
    pub fn flatten(self: Vec3) ztg.Vec2 {
        return self.flattenInto(ztg.Vec2);
    }

    /// Creates a `T`, which must have `x` and `y` components, from self and discards the `z` component
    pub fn flattenInto(self: Vec3, comptime T: type) T {
        return .{ .x = @floatCast(self.x), .y = @floatCast(self.y) };
    }

    /// Calculates the cross product of two vectors
    pub fn cross(a: Vec3, b: Vec3) Vec3 {
        return .{
            .x = @mulAdd(f32, a.y, b.z, -a.z * b.y),
            .y = @mulAdd(f32, a.z, b.x, -a.x * b.z),
            .z = @mulAdd(f32, a.x, b.y, -a.y * b.x),
        };
    }

    /// Returns a new Vec3 with all of it's components set to a number within [min, max)
    pub fn random(rand: std.Random, _min: f32, _max: f32) Vec3 {
        return .{
            .x = std.math.lerp(_min, _max, rand.float(f32)),
            .y = std.math.lerp(_min, _max, rand.float(f32)),
            .z = std.math.lerp(_min, _max, rand.float(f32)),
        };
    }

    /// Returns a new random Vec3 that lies on the surface of a unit sphere
    pub fn randomOnUnitSphere(rand: std.Random) Vec3 {
        var rand_vec = @Vector(3, f32){ rand.float(f32), rand.float(f32), rand.float(f32) };
        rand_vec *= @as(@Vector(3, f32), @splat(1 / ztg.math.lengthVec(rand_vec)));
        return from(rand_vec);
    }

    pub fn format(value: Vec3, comptime _fmt: []const u8, opt: std.fmt.FormatOptions, writer: anytype) !void {
        const start_str, const fmt = comptime blk: {
            if (_fmt.len > 0 and _fmt[0] == 's') break :blk .{ "(", _fmt[1..] };
            break :blk .{ "Vec3(", _fmt };
        };
        try writer.writeAll(start_str);
        try util.formatFloatValue(value.x, fmt, opt, writer);
        try writer.writeAll(", ");
        try util.formatFloatValue(value.y, fmt, opt, writer);
        try writer.writeAll(", ");
        try util.formatFloatValue(value.z, fmt, opt, writer);
        try writer.writeAll(")");
    }

    const vec_funcs = @import("vec_funcs.zig");
    const generated_funcs = vec_funcs.GenerateFunctions(Vec3);
    comptime {
        ztg.meta.checkMixin(Vec3, generated_funcs);
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
