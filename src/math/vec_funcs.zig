//! This is the common functionality of all vectors
//!
//! A lot of functions here are based on the Unity implementations: https://github.com/Unity-Technologies/UnityCsReference/blob/master/Runtime/Export/Math/Vector2.cs

const std = @import("std");
const ztg = @import("../init.zig");
const util = @import("../util.zig");
const math = std.math;
const builtin = std.builtin;

pub fn GenerateFunctions(comptime Self: type) type {
    if (@typeInfo(Self).@"struct".layout != .@"extern") @compileError("To implement vec_funcs into a struct it must be marked extern.");

    const vec_len = @typeInfo(Self).@"struct".fields.len;

    return struct {
        pub inline fn equals(a: Self, b: Self) bool {
            return @reduce(.And, a.intoSimd() == b.intoSimd());
        }

        /// Compares a and b using the same method as `std.math.approxEqRel` with a custom tolerance
        pub fn approxEqRelBy(a: Self, b: Self, tolerance: f32) bool {
            std.debug.assert(tolerance >= 0);
            const x = a.intoSimd();
            const y = b.intoSimd();

            if (@reduce(.And, x == y)) return true;
            return @reduce(.And, @abs(x - y) <= @max(@abs(x), @abs(y)) * @as(@Vector(vec_len, f32), @splat(tolerance)));
        }

        /// Compares a and b using the same method as `std.math.approxEqAbs` with a custom tolerance
        pub fn approxEqAbsBy(a: Self, b: Self, tolerance: f32) bool {
            std.debug.assert(tolerance >= 0);
            const x = a.intoSimd();
            const y = b.intoSimd();

            if (@reduce(.And, x == y)) return true;
            return @reduce(.And, @abs(x - y) <= @as(@Vector(vec_len, f32), @splat(tolerance)));
        }

        /// Compares a and b using the same method as `std.math.approxEqRel`
        pub inline fn approxEqRel(a: Self, b: Self) bool {
            return Self.approxEqRelBy(a, b, std.math.floatEps(f32));
        }

        /// Compares a and b using the same method as `std.math.approxEqAbs`
        pub inline fn approxEqAbs(a: Self, b: Self) bool {
            return Self.approxEqAbsBy(a, b, std.math.floatEps(f32));
        }

        /// Only to be used in tests, returns an error if `equals` returned false between the two
        pub fn expectEqual(expected: Self, actual: Self) !void {
            if (!Self.equals(expected, actual)) {
                std.debug.print("expected {}, found {}", .{ expected, actual });
                return error.TestExpectedEqual;
            }
        }

        /// Only to be used in tests, returns an error if `approxEqAbs` returned false between the two
        pub fn expectApproxEqAbs(expected: Self, actual: Self) !void {
            if (!approxEqAbs(expected, actual)) {
                std.debug.print("expected {}, found {}", .{ expected, actual });
                return error.TestExpectedEqual;
            }
        }

        /// Only to be used in tests, returns an error if `approxEqRel` returned false between the two
        pub fn expectApproxEqRel(expected: Self, actual: Self) !void {
            if (!approxEqRel(expected, actual)) {
                std.debug.print("expected {}, found {}", .{ expected, actual });
                return error.TestExpectedEqual;
            }
        }

        /// Access a vector component by runtime index
        pub inline fn axis(self: Self, i: std.math.IntFittingRange(0, vec_len - 1)) f32 {
            return @as(*const [vec_len]f32, @ptrCast(&self))[i];
        }

        /// Returns a vector with every element set to s
        pub inline fn splat(s: f32) Self {
            return fromArray(@splat(s));
        }

        pub inline fn copy(self: Self) Self {
            return self;
        }

        pub inline fn intoSimd(self: Self) @Vector(vec_len, f32) {
            return @bitCast(self);
        }

        inline fn fromSimd(self: @Vector(vec_len, f32)) Self {
            return @bitCast(self);
        }

        pub inline fn intoArray(self: Self) [vec_len]f32 {
            return @bitCast(self);
        }

        inline fn fromArray(self: [vec_len]f32) Self {
            return @bitCast(self);
        }

        pub inline fn abs(v: Self) Self {
            return fromSimd(@abs(v.toSimd()));
        }

        /// Returns the angle between to vectors in radians
        pub inline fn angle(a: Self, b: Self) ztg.math.Radians {
            const denominator = math.sqrt(Self.sqrLength(a) * Self.sqrLength(b));
            if (math.approxEqAbs(f32, denominator, 0, 1e-15)) return 0;

            const vec_dot = math.clamp(dot(a, b) / denominator, -1, 1);
            return math.acos(vec_dot);
        }

        /// Returns the signed angle between to vectors in radians
        pub inline fn angleSigned(a: Self, b: Self) ztg.math.Radians {
            const unsigned = Self.angle(a, b);
            const sign = math.sign(a.x * b.y - a.y * b.x);
            return unsigned * sign;
        }

        /// Returns a normalized vector that points from `orig` to `to`
        pub inline fn directionTo(orig: Self, to: Self) Self {
            return sub(to, orig).getNormalized();
        }

        pub inline fn distance(a: Self, b: Self) f32 {
            return length(sub(a, b));
        }

        pub inline fn sqrDistance(a: Self, b: Self) f32 {
            return sqrLength(sub(a, b));
        }

        pub inline fn dot(a: Self, b: Self) f32 {
            return ztg.math.dotVec(a.intoSimd(), b.intoSimd());
        }

        pub inline fn getNormalized(self: Self) Self {
            const m = Self.length(self);
            if (m == 0) return self;
            return Self.div(self, m);
        }

        pub inline fn setNormalized(self: *Self) void {
            self.* = self.getNormalized();
        }

        pub inline fn length(self: Self) f32 {
            return ztg.math.lengthVec(self.intoSimd());
        }

        pub inline fn sqrLength(self: Self) f32 {
            return ztg.math.sqrLengthVec(self.intoSimd());
        }

        pub inline fn lerp(a: Self, b: Self, t: f32) Self {
            return fromSimd(ztg.math.lerpVec(a.intoSimd(), b.intoSimd(), t));
        }

        pub inline fn lerpUnclamped(a: Self, b: Self, t: f32) Self {
            return fromSimd(ztg.math.lerpUnclampedVec(a.intoSimd(), b.intoSimd(), t));
        }

        /// Returns `orig` moved by an amount no greater than `max_dist` in the
        /// direction towards `to`. Will always arrive at `to` and stay without overshooting.
        pub fn moveTowards(orig: Self, to: Self, max_dist: f32) Self {
            var to_vec = Self.sub(to, orig);
            const sqr_dist = Self.sqrLength(to_vec);

            if (sqr_dist < math.floatEps(f32) or (max_dist >= 0 and sqr_dist <= max_dist * max_dist)) return to;

            const dist = math.sqrt(sqr_dist);

            to_vec.divEql(dist);
            to_vec.mulEql(max_dist);
            return Self.add(orig, to_vec);
        }

        /// Returns a vector containing the max values of a and b
        pub inline fn max(a: Self, b: Self) Self {
            return @max(a.intoSimd(), b.intoSimd());
        }

        /// Returns a vector containing the min values of a and b
        pub inline fn min(a: Self, b: Self) Self {
            return @min(a.intoSimd(), b.intoSimd());
        }

        pub inline fn project(a: Self, b: Self) Self {
            return Self.mul(b, Self.dot(a, b) / Self.dot(b, b));
        }

        pub inline fn reflect(dir: Self, normal: Self) Self {
            const factor = -2 * Self.dot(dir, normal);
            return Self.add(dir, Self.mul(dir, factor));
        }

        /// Returns a vector with random components between 0 and 1
        pub inline fn random01(rand: std.Random) Self {
            return Self.random(rand, 0, 1);
        }

        const Component = blk: {
            var info = @typeInfo(std.meta.FieldEnum(Self)).@"enum";
            info.tag_type = i32;
            break :blk @Type(.{ .@"enum" = info });
        };

        /// Returns the vector with its components ordered in the method defined in `comps`
        /// Example:
        /// ```zig
        /// const a = Vec2.init(10, 20);
        /// const b = a.swizzle(.{ .y, .x });
        /// try b.expectEqual(.{ .x = 20, .y = 10 });
        /// ```
        pub inline fn swizzle(self: Self, comptime comps: [vec_len]Component) Self {
            return fromSimd(@shuffle(f32, self.intoSimd(), undefined, @as(@Vector(vec_len, i32), @bitCast(comps))));
        }

        /// Returns a vector with components chosen from a and b based on `comps`.
        /// Behaves similarly to `@shuffle`
        /// Example:
        /// ```zig
        /// const a = Vec2.init(10, 20);
        /// const b = Vec2.init(20, 10);
        /// const c = Vec2.shuffle(a, b, .{ -1, 1 });
        /// try c.expectEqual(.{ .x = 20, .y = 20 });
        /// ```
        pub inline fn shuffle(a: Self, b: Self, comptime comps: @Vector(vec_len, i32)) Self {
            return fromSimd(@shuffle(f32, a.intoSimd(), b.intoSimd(), comps));
        }

        /// Returns a copy of `vec` with it's length clamped to max_len
        pub inline fn withClampedLength(vec: Self, max_len: f32) Self {
            const sqr_len = Self.sqrLength(vec);

            if (sqr_len > max_len * max_len) {
                const len = math.sqrt(sqr_len);
                const normalized = Self.div(vec, len);
                return Self.mul(normalized, max_len);
            }

            return vec;
        }

        pub inline fn getNegated(self: Self) Self {
            return fromSimd(-self.intoSimd());
        }

        pub inline fn setNegated(self: *Self) void {
            self.* = self.getNegated();
        }

        pub inline fn add(v0: Self, v1: Self) Self {
            return fromSimd(v0.intoSimd() + v1.intoSimd());
        }

        pub inline fn sub(v0: Self, v1: Self) Self {
            return fromSimd(v0.intoSimd() - v1.intoSimd());
        }

        pub inline fn mul(v0: Self, s: f32) Self {
            return fromSimd(v0.intoSimd() * @as(@Vector(vec_len, f32), @splat(s)));
        }

        pub inline fn div(v0: Self, s: f32) Self {
            return fromSimd(v0.intoSimd() / @as(@Vector(vec_len, f32), @splat(s)));
        }

        pub inline fn scale(v0: Self, v1: Self) Self {
            return fromSimd(v0.intoSimd() * v1.intoSimd());
        }

        pub inline fn addEql(self: *Self, other: Self) void {
            self.* = self.add(other);
        }

        pub inline fn subEql(self: *Self, other: Self) void {
            self.* = self.sub(other);
        }

        pub inline fn mulEql(self: *Self, scalar: f32) void {
            self.* = self.mul(scalar);
        }

        pub inline fn divEql(self: *Self, scalar: f32) void {
            self.* = self.div(scalar);
        }

        pub inline fn scaleEql(self: *Self, other: Self) void {
            self.* = self.scale(other);
        }
    };
}

pub fn convertFieldToF32(obj: anytype, comptime field_name: []const u8, default: f32) f32 {
    const O = @TypeOf(obj);
    const field_index = std.meta.fieldIndex(O, field_name) orelse return default;
    const FieldType = std.meta.fields(O)[field_index].type;

    return switch (@typeInfo(FieldType)) {
        .int => @floatFromInt(@field(obj, field_name)),
        .float => @floatCast(@field(obj, field_name)),
        .comptime_float => @field(obj, field_name),
        .comptime_int => @field(obj, field_name),
        else => util.compileError("Cannot convert type `{s}` to f32.", .{@typeName(FieldType)}),
    };
}

pub fn isBitcastable(comptime Self: type, comptime Other: type) bool {
    return comptime blk: {
        const other_ti = @typeInfo(Other);
        const s_fields: []const builtin.Type.StructField = @typeInfo(Self).@"struct".fields;

        if (other_ti == .vector and
            other_ti.vector.len == s_fields.len and
            other_ti.vector.child == f32) break :blk true;

        if (other_ti.@"struct".layout != .@"extern") break :blk false;

        const o_fields: []const builtin.Type.StructField = other_ti.@"struct".fields;
        if (s_fields.len != o_fields.len) break :blk false;

        const OtherField = std.meta.FieldEnum(Other);
        for (s_fields) |sf| {
            const other_field = std.meta.stringToEnum(OtherField, sf.name) orelse break :blk false;
            if (sf.type != std.meta.FieldType(Other, other_field)) break :blk false;
        }

        break :blk true;
    };
}

const Vec2 = @import("vec2.zig").Vec2;
const Vec4 = @import("vec4.zig").Vec4;

test "angle" {
    const v = Vec2.right;

    const between_down = v.angle(Vec2.down);
    try std.testing.expectApproxEqRel(math.degreesToRadians(90), between_down, std.math.floatEps(f32));

    const between_down_signed = v.angleSigned(Vec2.down);
    try std.testing.expectApproxEqRel(math.degreesToRadians(-90), between_down_signed, std.math.floatEps(f32));
}

test "directionTo" {
    const v0 = Vec2.zero;
    const v1 = Vec2.right;

    try std.testing.expect(v0.directionTo(v1).equals(Vec2.right));
}

test "getNormalized" {
    const v = Vec2.init(3, 4);
    try Vec2.expectApproxEqRel(Vec2.init(0.6, 0.8), v.getNormalized());
}

test "swizzle" {
    const vec = Vec2.init(10, 20);
    try Vec2.expectEqual(Vec2.init(20, 10), vec.swizzle(.{ .y, .x }));
    try Vec2.expectEqual(Vec2.init(10, 10), vec.swizzle(.{ .x, .x }));
    try Vec2.expectEqual(Vec2.init(20, 20), vec.swizzle(.{ .y, .y }));
}

test "shuffle" {
    const a = Vec2{ .x = 10, .y = 20 };
    const b = Vec2{ .x = 20, .y = 10 };
    const c = Vec2.shuffle(a, b, .{ -1, 1 });
    try Vec2.expectEqual(.{ .x = 20, .y = 20 }, c);
}

test isBitcastable {
    const ExternVec = extern struct {
        x: f32 = 0xDEAD,
        y: f32 = 0xBEEF,
    };

    try std.testing.expect(isBitcastable(Vec2, ExternVec));
    try Vec2.expectEqual(Vec2.init(0xDEAD, 0xBEEF), Vec2.from(ExternVec{}));

    const MyVec = struct {
        x: f32 = 0xDEAD,
        y: f32 = 0xBEEF,
    };

    try std.testing.expect(!isBitcastable(Vec2, MyVec));
    try Vec2.expectEqual(Vec2.init(0xDEAD, 0xBEEF), Vec2.from(MyVec{}));
}

test "axis" {
    const vec: Vec4 = .init(10, 20, 30, 40);
    try std.testing.expectEqual(10, vec.axis(0));
    try std.testing.expectEqual(20, vec.axis(1));
    try std.testing.expectEqual(30, vec.axis(2));
    try std.testing.expectEqual(40, vec.axis(3));
}
