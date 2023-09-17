const std = @import("std");
const ztg = @import("../init.zig");
const math = std.math;
const util = ztg.util;

/// A vector of 3 `f32`s
pub const Vec3 = extern struct {
    const vec_funcs = @import("vec_funcs.zig");
    pub usingnamespace vec_funcs.init(Vec3);

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

    pub inline fn set(self: *Vec3, x: anytype, y: anytype, z: anytype) void {
        self.x = if (comptime @typeInfo(@TypeOf(x)) == .Int) @floatFromInt(x) else x;
        self.y = if (comptime @typeInfo(@TypeOf(y)) == .Int) @floatFromInt(y) else y;
        self.z = if (comptime @typeInfo(@TypeOf(z)) == .Int) @floatFromInt(z) else z;
    }

    /// Returns T with all of it's components set to the original vector's
    /// T's only required components must be `x`, `y`, and `z`
    pub inline fn into(self: Vec3, comptime T: type) T {
        if (@typeInfo(T).Struct.layout == .Extern) return @bitCast(self);
        return .{ .x = @floatCast(self.x), .y = @floatCast(self.y), .z = @floatCast(self.z) };
    }

    /// Returns T with it's x and y components set to the original vector's x and y
    /// T's only required components must be `x` and `y`
    pub inline fn intoVec2(self: Vec3, comptime T: type) T {
        return .{ .x = @floatCast(self.x), .y = @floatCast(self.y) };
    }

    /// Converts the Vector into a @Vector object of type `T`, doing
    /// the necessary conversions.
    pub inline fn intoVectorOf(self: Vec3, comptime T: type) @Vector(3, T) {
        if (comptime std.meta.trait.isFloat(T)) {
            if (comptime T == f32) {
                return self.intoSimd();
            } else {
                return .{ @floatCast(self.x), @floatCast(self.y), @floatCast(self.z) };
            }
        } else if (comptime std.meta.trait.isIntegral(T)) {
            return .{ @intFromFloat(self.x), @intFromFloat(self.y), @intFromFloat(self.z) };
        } else {
            util.compileError("Cannot turn self into a vector of `{s}`", .{@typeName(T)});
        }
    }

    /// Returns a Quaternion from self, interpreting self as having Euler angles
    pub inline fn intoQuatAsEuler(self: Vec3) ztg.Vec4 {
        return ztg.Vec4.fromEulerAngles(self);
    }

    /// For use when integrating with the zmath library, sets w to 0
    pub inline fn intoZMath(self: Vec3) @Vector(4, f32) {
        return .{ self.x, self.y, self.z, 0.0 };
    }

    /// For use when integrating with the zmath library, ignores w component
    pub inline fn fromZMath(vec: @Vector(4, f32)) Vec3 {
        return .{ .x = vec[0], .y = vec[1], .z = vec[2] };
    }

    /// Creates a Vec3 from other, other must have `x`, `y`, and `z` components
    pub inline fn from(other: anytype) Vec3 {
        if (@typeInfo(@TypeOf(other)).Struct.layout == .Extern) return @bitCast(other);
        return .{ .x = @floatCast(other.x), .y = @floatCast(other.y), .z = @floatCast(other.z) };
    }

    /// Creates a Vec3 from other, other must have `x` and `y` components
    pub inline fn fromVec2(vec2: anytype, z: f32) Vec3 {
        return .{ .x = @floatCast(vec2.x), .y = @floatCast(vec2.y), .z = z };
    }

    /// Will try to convert vec to a `Vec3`
    /// e.g. if `vec` has an `x` field, it will use it,
    /// same goes for the `y` and `z` fields.
    pub inline fn fromAny(vec: anytype) Vec3 {
        return .{
            .x = vec_funcs.convertFieldToF32(vec, "x", 0),
            .y = vec_funcs.convertFieldToF32(vec, "y", 0),
            .z = vec_funcs.convertFieldToF32(vec, "z", 0),
        };
    }

    /// Creates a `Vec4` from `self` and sets the `w` component
    pub inline fn extend(self: Vec3, w: f32) ztg.Vec4 {
        return self.extendInto(ztg.Vec4, w);
    }

    /// Creates a `T`, which must have `x`, `y`, `z`, and `w` components, from self and sets the `w` component
    pub inline fn extendInto(self: Vec3, comptime T: type, w: f32) T {
        return .{ .x = @floatCast(self.x), .y = @floatCast(self.y), .z = @floatCast(self.z), .w = w };
    }

    /// Returns a `Vec2` from self, discarding the `z` component
    pub inline fn flatten(self: Vec3) ztg.Vec2 {
        return self.flattenInto(ztg.Vec2);
    }

    /// Creates a `T`, which must have `x` and `y` components, from self and discards the `z` component
    pub inline fn flattenInto(self: Vec3, comptime T: type) T {
        return .{ .x = @floatCast(self.x), .y = @floatCast(self.y) };
    }

    /// Calculates the cross product of two vectors
    pub inline fn cross(a: Vec3, b: Vec3) Vec3 {
        return .{
            .x = @mulAdd(f32, a.y, b.z, -a.z * b.y),
            .y = @mulAdd(f32, a.z, b.x, -a.x * b.z),
            .z = @mulAdd(f32, a.x, b.y, -a.y * b.x),
        };
    }

    /// Returns a new Vec3 with all of it's components set to a number within [min, max)
    pub inline fn random(rand: std.rand.Random, _min: f32, _max: f32) Vec3 {
        return .{
            .x = std.math.lerp(_min, _max, rand.float(f32)),
            .y = std.math.lerp(_min, _max, rand.float(f32)),
            .z = std.math.lerp(_min, _max, rand.float(f32)),
        };
    }

    /// Returns a new random Vec3 that lies on the surface of a unit sphere
    pub inline fn randomOnUnitSphere(rand: std.rand.Random) Vec3 {
        var rand_vec = @Vector(3, f32){ rand.float(f32), rand.float(f32), rand.float(f32) };
        rand_vec *= 1 / ztg.math.lengthVec(rand_vec);
        return Vec3.fromSimd(rand_vec);
    }

    pub fn format(value: Vec3, comptime fmt: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print(std.fmt.comptimePrint("Vec3({{{s}}}, {{{s}}}, {{{s}}})", .{ fmt, fmt, fmt }), .{ value.x, value.y, value.z });
    }
};
