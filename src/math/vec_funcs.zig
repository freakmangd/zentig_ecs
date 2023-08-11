//! This is the common functionality of all vectors
//!
//! A lot of functions here are based on the Unity implementations: https://github.com/Unity-Technologies/UnityCsReference/blob/master/Runtime/Export/Math/Vector2.cs

const std = @import("std");
const ztg = @import("../init.zig");
const math = std.math;

pub fn init(comptime Self: type) type {
    if (@typeInfo(Self).Struct.layout != .Extern) @compileError("To implement vec_funcs into a struct it must be marked extern.");

    const vec_len = std.meta.fields(Self).len;

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
            return @reduce(.And, @fabs(x - y) <= @max(@fabs(x), @fabs(y)) * @as(@Vector(vec_len, f32), @splat(tolerance)));
        }

        /// Compares a and b using the same method as `std.math.approxEqAbs` with a custom tolerance
        pub fn approxEqAbsBy(a: Self, b: Self, tolerance: f32) bool {
            std.debug.assert(tolerance >= 0);
            const x = a.intoSimd();
            const y = b.intoSimd();

            if (@reduce(.And, x == y)) return true;
            return @reduce(.And, @fabs(x - y) <= @as(@Vector(vec_len, f32), @splat(tolerance)));
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

        /// Returns a vector with every element set to 1
        pub inline fn one() Self {
            return fromSimd(@splat(1));
        }

        /// Returns a vector with every element set to s
        pub inline fn splat(s: f32) Self {
            return fromSimd(@splat(s));
        }

        /// Shorthand for .{}
        pub inline fn zero() Self {
            return .{};
        }

        /// Shorthand for .{ .x = 1 }
        pub inline fn right() Self {
            return .{ .x = 1 };
        }

        /// Shorthand for .{ .x = -1 }
        pub inline fn left() Self {
            return .{ .x = -1 };
        }

        /// Shorthand for .{ .y = 1 }
        pub inline fn up() Self {
            return .{ .y = 1 };
        }

        /// Shorthand for .{ .y = -1 }
        pub inline fn down() Self {
            return .{ .y = -1 };
        }

        pub usingnamespace if (vec_len > 2) struct {
            /// Shorthand for .{ .z = 1 }
            pub inline fn forward() Self {
                return .{ .z = 1 };
            }

            /// Shorthand for .{ .z = -1 }
            pub inline fn backward() Self {
                return .{ .z = -1 };
            }
        } else struct {};

        pub inline fn copy(self: Self) Self {
            return self;
        }

        pub inline fn intoSimd(self: Self) @Vector(vec_len, f32) {
            return @bitCast(self);
        }

        pub inline fn fromSimd(self: @Vector(vec_len, f32)) Self {
            return @bitCast(self);
        }

        /// Returns the angle between to vectors in radians
        pub inline fn angle(a: Self, b: Self) ztg.math.Radians {
            const denominator = math.sqrt(Self.sqrLength(a) * Self.sqrLength(b));
            if (math.approxEqAbs(f32, denominator, 0, 1e-15)) return 0;

            const vec_dot = math.clamp(Self.dot(a, b) / denominator, -1, 1);
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
            return Self.sub(to, orig).getNormalized();
        }

        pub inline fn distance(a: Self, b: Self) f32 {
            return Self.length(Self.sub(a, b));
        }

        pub inline fn dot(a: Vec2, b: Vec2) f32 {
            return ztg.math.dotVec(a.intoSimd(), b.intoSimd());
        }

        pub inline fn getNormalized(self: Self) Self {
            const m = Self.length(self);
            if (m == 0) return self;
            return Self.div(self, m);
        }

        pub inline fn setNormalized(self: *Vec2) void {
            self.* = self.getNormalized();
        }

        pub inline fn length(self: Self) f32 {
            return ztg.math.lengthVec(self.intoSimd());
        }

        pub inline fn sqrLength(self: Self) f32 {
            return ztg.math.sqrLengthVec(self.intoSimd());
        }

        pub inline fn lerp(a: Self, b: Self, t: f32) Self {
            return ztg.math.lerpVec(a.intoSimd(), b.intoSimd(), t);
        }

        pub inline fn lerpUnclamped(a: Self, b: Self, t: f32) Self {
            return ztg.math.lerpUnclampedVec(a.intoSimd(), b.intoSimd(), t);
        }

        /// Returns `orig` moved by an amount no greater than `max_dist` in the
        /// direction towards `to`. Will always arrive at `to` and stay without overshooting.
        pub inline fn moveTowards(orig: Self, to: Self, max_dist: f32) Self {
            var to_vec = Self.sub(to, orig);
            const sqr_dist = Self.sqrLength(to_vec);

            if (sqr_dist < math.floatEps(f32) or (max_dist >= 0 and sqr_dist <= max_dist * max_dist)) return to;

            const dist = math.sqrt(sqr_dist);

            to_vec.divEql(dist * max_dist);
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
        pub inline fn random01(rand: std.rand.Random) Self {
            return Self.random(rand, 0, 1);
        }

        const Component = blk: {
            var info = @typeInfo(std.meta.FieldEnum(Self)).Enum;
            info.tag_type = i32;
            break :blk @Type(.{ .Enum = info });
        };

        /// Returns the vector with it's components ordered in the method defined in `comps`
        /// Example:
        /// ```zig
        /// const a = Vec2.init(10, 20);
        /// const b = a.swizzle(.{ .y, .x });
        /// try b.expectEqual(.{ 20, 10 });
        /// ```
        pub inline fn swizzle(self: Self, comptime comps: [vec_len]Component) Self {
            return fromSimd(@shuffle(f32, self.intoSimd(), undefined, @as(@Vector(vec_len, i32), @bitCast(comps))));
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
            return Self.fromSimd(v0.intoSimd() + v1.intoSimd());
        }

        pub inline fn sub(v0: Self, v1: Self) Self {
            return Self.fromSimd(v0.intoSimd() - v1.intoSimd());
        }

        pub inline fn mul(v0: Self, s: f32) Self {
            return fromSimd(v0.intoSimd() * @as(@Vector(vec_len, f32), @splat(s)));
        }

        pub inline fn div(v0: Self, s: f32) Self {
            return fromSimd(v0.intoSimd() / @as(@Vector(vec_len, f32), @splat(s)));
        }

        pub inline fn scale(v0: Self, v1: Self) Self {
            return Self.fromSimd(v0.intoSimd() * v1.intoSimd());
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
        .Int => @floatFromInt(@field(obj, field_name)),
        .Float => @floatCast(@field(obj, field_name)),
        .ComptimeFloat => @field(obj, field_name),
        .ComptimeInt => @field(obj, field_name),
        else => @compileError("Cannot convert type " ++ @typeName(FieldType) ++ " to f32."),
    };
}

const Vec2 = @import("vec2.zig").Vec2;

test "angle" {
    const v = Vec2.right();

    try std.testing.expectApproxEqRel(math.degreesToRadians(f32, 90), v.angle(Vec2.down()), std.math.floatEps(f32));
    try std.testing.expectApproxEqRel(math.degreesToRadians(f32, -90), v.angleSigned(Vec2.down()), std.math.floatEps(f32));
}

test "direction" {
    const v0 = Vec2.zero();
    const v1 = Vec2.right();

    try std.testing.expect(v0.directionTo(v1).equals(Vec2.right()));
}

test "getNormalized" {
    const v = Vec2.init(10, 20);
    _ = v;
}

test "swizzle" {
    const vec = Vec2.init(10, 20);
    try Vec2.expectEqual(Vec2.init(20, 10), vec.swizzle(.{ .y, .x }));
    try Vec2.expectEqual(Vec2.init(10, 10), vec.swizzle(.{ .x, .x }));
    try Vec2.expectEqual(Vec2.init(20, 20), vec.swizzle(.{ .y, .y }));
}
