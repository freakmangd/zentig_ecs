//! A lot of functions here are based on the Unity implementations: https://github.com/Unity-Technologies/UnityCsReference/blob/master/Runtime/Export/Math/Vector2.cs

const std = @import("std");
const math = std.math;

pub fn init(comptime Self: type) type {
    return struct {
        pub inline fn zero() Self {
            return .{};
        }

        pub inline fn right() Self {
            return .{ .x = 1 };
        }

        pub inline fn left() Self {
            return .{ .x = -1 };
        }

        pub inline fn up() Self {
            return .{ .y = 1 };
        }

        pub inline fn down() Self {
            return .{ .y = -1 };
        }

        pub inline fn copy(self: Self) Self {
            return self;
        }

        pub inline fn angle(a: Self, b: Self) f32 {
            const denominator = math.sqrt(Self.sqrLength(a) * Self.sqrLength(b));
            if (math.approxEqAbs(f32, denominator, 0, 1e-15)) return 0;

            const vec_dot = math.clamp(Self.dot(a, b) / denominator, -1, 1);
            return math.acos(vec_dot);
        }

        pub inline fn angleSigned(a: Self, b: Self) f32 {
            const unsigned = Self.angle(a, b);
            const sign = math.sign(a.x * b.y - a.y * b.x);
            return unsigned * sign;
        }

        pub inline fn direction(orig: Self, to: Self) Self {
            return Self.subtract(to, orig).getNormalized();
        }

        pub inline fn distance(a: Self, b: Self) f32 {
            return Self.length(Self.subtract(a, b));
        }

        pub inline fn getNormalized(self: Self) Self {
            const m = Self.length(self);
            if (m == 0) return self;
            return Self.divide(self, m);
        }

        pub inline fn moveTowards(orig: Self, to: Self, max_dist: f32) Self {
            const to_vec = Self.subtract(to, orig);
            const sqr_dist = Self.sqrLength(to_vec);

            if (sqr_dist < math.floatEps(f32) or (max_dist >= 0 and sqr_dist <= max_dist * max_dist)) return to;

            const dist = math.sqrt(sqr_dist);

            to_vec.divEql(dist * max_dist);
            return Self.add(orig, to_vec);
        }

        pub inline fn project(a: Self, b: Self) Self {
            return Self.multiply(b, Self.dot(a, b) / Self.dot(b, b));
        }

        pub inline fn reflect(dir: Self, normal: Self) Self {
            const factor = -2 * Self.dot(dir, normal);
            return Self.add(dir, Self.multiply(dir, factor));
        }

        /// Returns a copy of `vec` with it's length clamped to max_len
        pub inline fn withClampedLength(vec: Self, max_len: f32) Self {
            const sqr_len = Self.sqrLength(vec);

            if (sqr_len > max_len * max_len) {
                const len = math.sqrt(sqr_len);
                const normalized = Self.divide(vec, len);
                return Self.multiply(normalized, max_len);
            }

            return vec;
        }
    };
}

const Vec2 = @import("vec2.zig");

test "angle" {
    const v = Vec2.right();

    try expectApproxEql(math.degreesToRadians(f32, 90), v.angle(Vec2.down()));
    try expectApproxEql(math.degreesToRadians(f32, -90), v.angleSigned(Vec2.down()));
}

test "direction" {
    const v0 = Vec2.zero();
    const v1 = Vec2.right();

    try std.testing.expect(v0.direction(v1).equals(Vec2.right()));
}

test "getNormalized" {}

fn expectApproxEql(a: anytype, b: @TypeOf(a)) !void {
    if (!math.approxEqAbs(@TypeOf(a), a, b, math.floatEps(f32))) {
        std.debug.print("expected {}, found {}\n", .{ a, b });
        return error.TestExpectedEqual;
    }
}
