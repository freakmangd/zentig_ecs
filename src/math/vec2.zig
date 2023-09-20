const std = @import("std");
const testing = std.testing;

const ztg = @import("../init.zig");
const util = @import("../util.zig");
const math = std.math;

/// A vector of 2 `f32`s
pub const Vec2 = extern struct {
    const vec_funcs = @import("vec_funcs.zig");
    pub usingnamespace vec_funcs.init(Vec2);

    x: f32 = 0.0,
    y: f32 = 0.0,

    pub inline fn init(x: anytype, y: anytype) Vec2 {
        return .{
            .x = if (comptime @typeInfo(@TypeOf(x)) == .Int) @floatFromInt(x) else x,
            .y = if (comptime @typeInfo(@TypeOf(y)) == .Int) @floatFromInt(y) else y,
        };
    }

    pub inline fn set(self: *Vec2, x: anytype, y: anytype) void {
        self.x = if (comptime @typeInfo(@TypeOf(x)) == .Int) @floatFromInt(x) else x;
        self.y = if (comptime @typeInfo(@TypeOf(y)) == .Int) @floatFromInt(y) else y;
    }

    /// Returns T with all of it's components set to the original vector's
    /// T's only required components must be `x`, and `y`
    pub inline fn into(self: Vec2, comptime T: type) T {
        if (comptime @typeInfo(T).Struct.layout == .Extern and @sizeOf(T) == @sizeOf(Vec2)) return @bitCast(self);
        return .{ .x = @floatCast(self.x), .y = @floatCast(self.y) };
    }

    /// Converts the Vector into a @Vector object of type `T`, doing
    /// the necessary conversions.
    pub inline fn intoVectorOf(self: Vec2, comptime T: type) @Vector(2, T) {
        if (comptime std.meta.trait.isFloat(T)) {
            if (comptime T == f32) {
                return self.intoSimd();
            } else {
                return .{ @as(T, @floatCast(self.x)), @as(T, @floatCast(self.y)) };
            }
        } else if (comptime std.meta.trait.isIntegral(T)) {
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
    pub inline fn intoDirAngle(self: Vec2) ztg.math.Radians {
        return math.atan2(f32, self.y, self.x);
    }

    test intoDirAngle {
        try testing.expectEqual(@as(ztg.math.Radians, 0), init(1, 0).intoDirAngle());
        try testing.expectEqual(std.math.degreesToRadians(ztg.math.Radians, 90), init(0, 1).intoDirAngle());
        try testing.expectEqual(std.math.degreesToRadians(ztg.math.Radians, 180), init(-1, 0).intoDirAngle());
    }

    /// Converts angle theta to a unit vector representation
    /// starting at .{ 1, 0 } and going ccw towards .{ 0, 1 }
    pub inline fn fromDirAngle(theta: ztg.math.Radians) Vec2 {
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
    pub inline fn intoZMath(self: Vec2) @Vector(4, f32) {
        return .{ self.x, self.y, 0.0, 0.0 };
    }

    /// For use when integrating with the zmath library, discards z and w components
    pub inline fn fromZMath(vec: @Vector(4, f32)) Vec2 {
        return .{ vec[0], vec[1] };
    }

    /// Creates a new Vec2 from the components of other
    pub inline fn from(other: anytype) Vec2 {
        if (comptime @typeInfo(@TypeOf(other)).Struct.layout == .Extern and @sizeOf(@TypeOf(other)) == @sizeOf(Vec2)) return @bitCast(other);
        return .{ .x = @floatCast(other.x), .y = @floatCast(other.y) };
    }

    /// Will try to convert vec to a Vec2
    /// e.g. if vec has an x field, it will use it,
    /// same goes for the y field.
    pub inline fn fromAny(vec: anytype) Vec2 {
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
    pub inline fn extend(self: Vec2, z: f32) ztg.Vec3 {
        return self.extendInto(ztg.Vec3, z);
    }

    /// Creates a T, which must have `x`, `y`, and `z` components, from self and sets the w component
    pub inline fn extendInto(self: Vec2, comptime T: type, z: f32) T {
        return .{ .x = @floatCast(self.x), .y = @floatCast(self.y), .z = z };
    }

    /// Just returns the x component
    pub inline fn flatten(self: Vec2) f32 {
        return self.x;
    }

    /// Returns a new Vec2 with all of it's components set to a number within [min, max)
    pub inline fn random(rand: std.rand.Random, _min: f32, _max: f32) Vec2 {
        return .{
            .x = std.math.lerp(_min, _max, rand.float(f32)),
            .y = std.math.lerp(_min, _max, rand.float(f32)),
        };
    }

    /// Returns a new random Vec2 that lies on the outside of a unit circle
    pub inline fn randomOnUnitCircle(rand: std.rand.Random) Vec2 {
        return fromDirAngle(rand.float(f32) * std.math.pi * 2);
    }

    /// Returns the perpendicular of the vector
    pub inline fn perpendicular(dir: Vec2) Vec2 {
        return .{
            .x = -dir.y,
            .y = dir.x,
        };
    }

    test perpendicular {
        try init(-1, 0).expectApproxEqAbs(init(0, 1).perpendicular());
    }

    /// Returns a new copy of the vector rotated ccw by `angle` radians
    pub inline fn getRotated(self: Vec2, angle: ztg.math.Radians) Vec2 {
        return Vec2{
            .x = @mulAdd(f32, std.math.cos(angle), self.x, -std.math.sin(angle) * self.y),
            .y = @mulAdd(f32, std.math.sin(angle), self.x, std.math.cos(angle) * self.y),
        };
    }

    test getRotated {
        try init(0, 1).expectApproxEqAbs(init(1, 0).getRotated(std.math.pi / 2.0));
    }

    /// Rotates the vector ccw in place by `angle` radians
    pub inline fn setRotated(self: *Vec2, angle: ztg.math.Radians) void {
        self.* = self.getRotated(angle);
    }

    pub fn format(value: Vec2, comptime fmt: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print(std.fmt.comptimePrint("Vec2({{{s}}}, {{{s}}})", .{ fmt, fmt }), .{ value.x, value.y });
    }
};
