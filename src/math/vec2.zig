const std = @import("std");
const testing = std.testing;

const ztg = @import("../init.zig");
const util = @import("../util.zig");
const math = std.math;

/// A vector of 2 `f32`s
pub const Vec2 = extern struct {
    x: f32 = 0.0,
    y: f32 = 0.0,

    pub const one = splat(1);
    pub const zero: Vec2 = .{};
    pub const right: Vec2 = .{ .x = 1 };
    pub const left: Vec2 = .{ .x = -1 };
    pub const up: Vec2 = .{ .y = 1 };
    pub const down: Vec2 = .{ .y = -1 };

    pub fn init(x: anytype, y: anytype) Vec2 {
        return .{
            .x = if (comptime @typeInfo(@TypeOf(x)) == .int) @floatFromInt(x) else x,
            .y = if (comptime @typeInfo(@TypeOf(y)) == .int) @floatFromInt(y) else y,
        };
    }

    pub fn set(self: *Vec2, x: anytype, y: anytype) void {
        self.x = if (comptime @typeInfo(@TypeOf(x)) == .int) @floatFromInt(x) else x;
        self.y = if (comptime @typeInfo(@TypeOf(y)) == .int) @floatFromInt(y) else y;
    }

    /// Returns T with all of its components set to the original vector's
    /// T's only required components must be `x`, and `y`
    pub fn into(self: Vec2, comptime T: type) T {
        if (comptime vec_funcs.isBitcastable(Vec2, T)) return @bitCast(self);
        return .{ .x = @floatCast(self.x), .y = @floatCast(self.y) };
    }

    /// Converts the Vector into a @Vector object of type `T`, doing
    /// the necessary conversions.
    pub fn intoVectorOf(self: Vec2, comptime T: type) @Vector(2, T) {
        if (@typeInfo(T) == .float or @typeInfo(T) == .comptime_float) {
            if (comptime T == f32) {
                return self.intoSimd();
            } else {
                return .{ @as(T, @floatCast(self.x)), @as(T, @floatCast(self.y)) };
            }
        } else if (@typeInfo(T) == .int or @typeInfo(T) == .comptime_int) {
            return .{ @as(T, @intFromFloat(self.x)), @as(T, @intFromFloat(self.y)) };
        } else {
            util.compileError("Cannot turn self into a vector of `{s}`", .{@typeName(T)});
        }
    }

    test intoVectorOf {
        try testing.expectEqual(@Vector(2, i32){ 1, 2 }, init(1.4, 2.8).intoVectorOf(i32));
        try testing.expectEqual(@Vector(2, c_int){ 20, 12 }, init(20.2, 12.7).intoVectorOf(i32));
    }

    /// Converts vector to an angle in radians
    /// starting at .{ 1, 0 } and going ccw towards .{ 0, 1 }
    pub fn intoDirAngle(self: Vec2) ztg.math.Radians {
        return math.atan2(self.y, self.x);
    }

    test intoDirAngle {
        try testing.expectEqual(@as(ztg.math.Radians, 0), init(1, 0).intoDirAngle());
        try testing.expectEqual(std.math.degreesToRadians(90), init(0, 1).intoDirAngle());
        try testing.expectEqual(std.math.degreesToRadians(180), init(-1, 0).intoDirAngle());
    }

    /// Converts angle theta to a unit vector representation
    /// starting at .{ 1, 0 } and going ccw towards .{ 0, 1 }
    pub fn fromDirAngle(theta: ztg.math.Radians) Vec2 {
        return .{
            .x = math.cos(theta),
            .y = math.sin(theta),
        };
    }

    test fromDirAngle {
        try Vec2.expectApproxEqAbs(init(0, -1), fromDirAngle(std.math.pi * 1.5));
        try Vec2.expectApproxEqAbs(init(1, 0), fromDirAngle(0));
    }

    /// For use when integrating with the zmath library, sets z and w to 0
    pub fn intoZMath(self: Vec2) @Vector(4, f32) {
        return .{ self.x, self.y, 0.0, 0.0 };
    }

    /// For use when integrating with the zmath library, discards z and w components
    pub fn fromZMath(vec: @Vector(4, f32)) Vec2 {
        return .{ vec[0], vec[1] };
    }

    /// Creates a new Vec2 from the components of other
    pub fn from(other: anytype) Vec2 {
        if (comptime vec_funcs.isBitcastable(Vec2, @TypeOf(other))) return @bitCast(other);
        return .{ .x = @floatCast(other.x), .y = @floatCast(other.y) };
    }

    /// Will try to convert vec to a Vec2
    /// e.g. if vec has an x field, it will use it,
    /// same goes for the y field.
    pub fn fromAny(vec: anytype) Vec2 {
        return .{
            .x = vec_funcs.convertFieldToF32(vec, "x", 0),
            .y = vec_funcs.convertFieldToF32(vec, "y", 0),
        };
    }

    test fromAny {
        const MyVector = struct {
            x: c_int,
            y: u8,
        };

        try Vec2.expectEqual(init(-2, 5), fromAny(MyVector{ .x = -2, .y = 5 }));

        const MyOtherVec = struct {
            x: f16,
        };

        try Vec2.expectEqual(init(10, 0), fromAny(MyOtherVec{ .x = 10 }));
    }

    /// Creates a Vec3 from self and sets the z component
    pub fn extend(self: Vec2, z: f32) ztg.Vec3 {
        return self.extendInto(ztg.Vec3, z);
    }

    /// Creates a T, which must have `x`, `y`, and `z` components, from self and sets the w component
    pub fn extendInto(self: Vec2, comptime T: type, z: f32) T {
        return .{ .x = @floatCast(self.x), .y = @floatCast(self.y), .z = z };
    }

    /// Just returns the x component
    pub fn flatten(self: Vec2) f32 {
        return self.x;
    }

    /// Returns a new Vec2 with all of its components set to a number within [min, max)
    pub fn random(rand: std.Random, _min: f32, _max: f32) Vec2 {
        return .{
            .x = std.math.lerp(_min, _max, rand.float(f32)),
            .y = std.math.lerp(_min, _max, rand.float(f32)),
        };
    }

    /// Returns a new random Vec2 that lies on the outside of a unit circle
    pub fn randomOnUnitCircle(rand: std.Random) Vec2 {
        return fromDirAngle(rand.float(f32) * std.math.pi * 2);
    }

    /// Returns the perpendicular of the vector
    pub fn perpendicular(dir: Vec2) Vec2 {
        return .{
            .x = -dir.y,
            .y = dir.x,
        };
    }

    test perpendicular {
        try init(-1, 0).expectApproxEqAbs(init(0, 1).perpendicular());
    }

    /// Returns a new copy of the vector rotated ccw by `theta` radians
    pub fn getRotated(self: Vec2, theta: ztg.math.Radians) Vec2 {
        return Vec2{
            .x = @mulAdd(f32, std.math.cos(theta), self.x, -std.math.sin(theta) * self.y),
            .y = @mulAdd(f32, std.math.sin(theta), self.x, std.math.cos(theta) * self.y),
        };
    }

    test getRotated {
        try init(0, 1).expectApproxEqAbs(init(1, 0).getRotated(std.math.pi / 2.0));
    }

    /// Rotates the vector ccw in place by `theta` radians
    pub fn setRotated(self: *Vec2, theta: ztg.math.Radians) void {
        self.* = self.getRotated(theta);
    }

    pub fn format(value: Vec2, writer: *std.Io.Writer) !void {
        try writer.print("Vec2({}, {})", .{ value.x, value.y });
    }

    pub fn formatNumber(value: Vec2, writer: *std.Io.Writer, options: std.fmt.Number) !void {
        try writer.writeAll("(");
        try writer.printFloat(value.x, options);
        try writer.writeAll(", ");
        try writer.printFloat(value.y, options);
        try writer.writeAll(")");
    }

    test format {
        const v = init(0, 1);
        try std.testing.expectFmt("Vec2(0, 1)", "{f}", .{v});
        try std.testing.expectFmt("(0e0, 1e0)", "{e}", .{v});
        try std.testing.expectFmt("(0, 1)", "{d}", .{v});
    }

    const vec_funcs = @import("vec_funcs.zig");
    const generated_funcs = vec_funcs.GenerateFunctions(Vec2);
    comptime {
        ztg.meta.checkMixin(Vec2, generated_funcs);
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
