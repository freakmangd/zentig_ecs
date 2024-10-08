const std = @import("std");
const util = @import("../util.zig");
const expectEqual = std.testing.expectEqual;

/// Alias for `f32`, used to clarify input parameters for
/// functions that take angles in radians
pub const Radians = f32;

/// Alias for `f32`, used to clarify input parameters for
/// functions that take angles in degrees
pub const Degrees = f32;

pub const Vec2 = @import("vec2.zig").Vec2;
pub const Vec3 = @import("vec3.zig").Vec3;
pub const Vec4 = @import("vec4.zig").Vec4;

pub fn VectorOfLen(comptime len: usize) ?type {
    return switch (len) {
        2 => Vec2,
        3 => Vec3,
        4 => Vec4,
        else => null,
    };
}

fn isFloat(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .float, .comptime_float => true,
        else => false,
    };
}
fn isIntegral(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .int, .comptime_int => true,
        else => false,
    };
}

pub inline fn toFloat(comptime T: type, x: anytype) T {
    if (T == @TypeOf(x)) return x;
    if (comptime !isFloat(T)) @compileError("toFloat requires it's first argument `T` to be a Float type to convert `x` to.");

    return switch (@typeInfo(@TypeOf(x))) {
        .int => @floatFromInt(x),
        .float => @floatCast(x),
        .comptime_float, .comptime_int => x,
        else => util.compileError("Cannot convert `{s}` to a float.", .{@typeName(@TypeOf(x))}),
    };
}

test toFloat {
    try expectEqual(@as(f32, 1.0), toFloat(f32, 1));
    try expectEqual(@as(f32, 1.0), toFloat(f32, 1.0));
    try expectEqual(@as(f32, 1.0), toFloat(f32, @as(i32, 1)));
    try expectEqual(@as(f32, 1.0), toFloat(f32, @as(f32, 1.0)));
    try expectEqual(@as(f32, 1.0), toFloat(f32, @as(f16, 1.0)));
}

pub inline fn toInt(comptime T: type, x: anytype) T {
    if (comptime T == @TypeOf(x)) return x;
    if (comptime !isIntegral(T)) @compileError("toInt requires it's first argument `T` to be an Integral type to convert `x` to.");

    return switch (@typeInfo(@TypeOf(x))) {
        .int => @intCast(x),
        .float => @intFromFloat(x),
        .comptime_float, .comptime_int => x,
        else => util.compileError("Cannot convert `{s}` to an int.", .{@typeName(@TypeOf(x))}),
    };
}

test toInt {
    try expectEqual(@as(i32, 1), toInt(i32, 1));
    try expectEqual(@as(i32, 1), toInt(i32, 1.0));
    try expectEqual(@as(i32, 1), toInt(i32, @as(i32, 1)));
    try expectEqual(@as(i32, 1), toInt(i32, @as(f32, 1.0)));
    try expectEqual(@as(i32, 1), toInt(i32, @as(i16, 1)));
    try expectEqual(@as(i32, 1), toInt(i32, @as(u16, 1)));
}

pub const mulAsFloat = @compileError("mulAsFloat has been renamed to mul");
pub const divAsFloat = @compileError("divAsFloat has been renamed to div");

inline fn checkUnnecessary(comptime name: []const u8, comptime T: type, comptime A: type, comptime B: type) void {
    if (comptime isFloat(T) and isFloat(A) and isFloat(B)) {
        @compileError(std.fmt.comptimePrint("Unnecessary use of automatic conversion {s}, both types are floats", .{name}));
    } else if (comptime isIntegral(T) and isIntegral(A) and isIntegral(B)) {
        @compileError(std.fmt.comptimePrint("Unnecessary use of automatic conversion {s}, both types are ints", .{name}));
    }
}

/// Converts a and b to T (if neeeded) and adds them, returning a float or integer of type T
pub inline fn add(comptime T: type, a: anytype, b: anytype) T {
    comptime checkUnnecessary("add", T, @TypeOf(a), @TypeOf(b));

    if (comptime isFloat(T)) {
        return toFloat(T, a) + toFloat(T, b);
    } else if (comptime isIntegral(T)) {
        return toInt(T, a) + toInt(T, b);
    } else {
        util.compileError("Automatic conversion addition is not available for type `{s}`", .{@typeName(T)});
    }
}

/// Converts a and b to T (if neeeded) and subtracts them, returning a float or integer of type T
pub inline fn sub(comptime T: type, a: anytype, b: anytype) T {
    comptime checkUnnecessary("sub", T, @TypeOf(a), @TypeOf(b));

    if (comptime isFloat(T)) {
        return toFloat(T, a) - toFloat(T, b);
    } else if (comptime isIntegral(T)) {
        return toInt(T, a) - toInt(T, b);
    } else {
        util.compileError("Automatic conversion subtraction is not available for type `{s}`", .{@typeName(T)});
    }
}

/// Converts a and b to T (if neeeded) and multiplies them, returning a float or integer of type T
pub inline fn mul(comptime T: type, a: anytype, b: anytype) T {
    comptime checkUnnecessary("mul", T, @TypeOf(a), @TypeOf(b));

    if (comptime isFloat(T)) {
        return toFloat(T, a) * toFloat(T, b);
    } else if (comptime isIntegral(T)) {
        return toInt(T, a) * toInt(T, b);
    } else {
        util.compileError("Automatic conversion multiplication is not available for type `{s}`", .{@typeName(T)});
    }
}

test mul {
    try expectEqual(@as(f32, 7.0), mul(f32, 14, 0.5));
    try expectEqual(@as(f32, 20.5), mul(f32, @as(u1, 1), @as(f32, 20.5)));
}

/// Converts a and b to T (if neeeded) and divides them, returning a float or integer of type T
pub inline fn div(comptime T: type, a: anytype, b: anytype) error{DivideByZero}!T {
    comptime checkUnnecessary("div", T, @TypeOf(a), @TypeOf(b));
    if (b == 0) return error.DivideByZero;

    if (comptime isFloat(T)) {
        return toFloat(T, a) / toFloat(T, b);
    } else if (comptime isIntegral(T)) {
        return toInt(T, a) / toInt(T, b);
    } else {
        util.compileError("Automatic conversion division is not available for type `{s}`", .{@typeName(T)});
    }
}

test div {
    try expectEqual(@as(f32, 0.13), try div(f32, 13, 100));
    try expectEqual(@as(f32, 0.5), try div(f32, @as(u1, 1), @as(i32, 2)));
    try std.testing.expectError(error.DivideByZero, div(f32, 1_000, 0));
}

/// Converts a and b to f32 and adds them
pub inline fn addf32(a: anytype, b: anytype) f32 {
    return add(f32, a, b);
}

/// Converts a and b to f32 and subtracts them
pub inline fn subf32(a: anytype, b: anytype) f32 {
    return sub(f32, a, b);
}

/// Converts a and b to f32 and multiplies them
pub inline fn mulf32(a: anytype, b: anytype) f32 {
    return mul(f32, a, b);
}

/// Converts a and b to f32 and divides them
pub inline fn divf32(a: anytype, b: anytype) error{DivideByZero}!f32 {
    return div(f32, a, b);
}

fn angleDifference(from: anytype, to: anytype) @TypeOf(from, to) {
    const difference = (to - from) % std.math.tau;
    return ((2.0 * difference) % std.math.tau) - difference;
}

/// Clamps v between 0 and 1
pub inline fn clamp01(v: anytype) @TypeOf(v) {
    return @call(.always_inline, std.math.clamp, .{ v, 0, 1 });
}

test clamp01 {
    try expectEqual(@as(f32, 0.5), clamp01(@as(f32, 0.5)));
    try expectEqual(@as(f32, 1.0), clamp01(@as(f32, 1.5)));
    try expectEqual(@as(f32, 0.0), clamp01(@as(f32, -20.0)));
}

pub fn moveTowards(from: anytype, to: anytype, delta: anytype) @TypeOf(from, to, delta) {
    if (@abs(to - from) <= delta)
        return to;

    return from + (std.math.sign(to - from) * delta);
}

pub fn rotateToward(from: anytype, to: anytype, delta: anytype) @TypeOf(from, to, delta) {
    const difference = angleDifference(from, to);
    const abs_difference = @abs(difference);
    return from + std.math.clamp(delta, abs_difference - std.math.pi, abs_difference) * if (difference >= 0.0) 1.0 else -1.0;
}

pub fn remap(
    value: anytype,
    in_from: anytype,
    in_to: anytype,
    out_from: anytype,
    out_to: anytype,
) @TypeOf(value, in_from, in_to, out_from, out_to) {
    return std.math.lerp(out_from, out_to, inverseLerp(in_from, in_to, value));
}

pub fn inverseLerp(from: anytype, to: anytype, weight: anytype) @TypeOf(from, to, weight) {
    return (weight - from) / (to - from);
}

/// Returns the length of a @Vector object
pub inline fn lengthVec(vec: anytype) f32 {
    return @sqrt(@reduce(.Add, vec * vec));
}

test lengthVec {
    try expectEqual(@as(f32, 1.0), lengthVec(@Vector(2, f32){ 1, 0 }));
    try expectEqual(@as(f32, 1.0), lengthVec(@Vector(2, f32){ -1, 0 }));
    try expectEqual(@as(f32, 5.0), lengthVec(@Vector(2, f32){ 3, 4 }));
}

/// Returns the square length of a @Vector object
pub inline fn sqrLengthVec(vec: anytype) f32 {
    return @reduce(.Add, vec * vec);
}

/// Returns the distance between the a and b vectors
pub inline fn distanceVec(a: anytype, b: anytype) f32 {
    return lengthVec(a - b);
}

/// Returns the square distance between the a and b vectors
pub inline fn sqrDistanceVec(a: anytype, b: anytype) f32 {
    return sqrLengthVec(a - b);
}

/// Lerps between two @Vector objects by a scalar t clamped between 0 and 1
pub inline fn lerpVec(a: anytype, b: anytype, t: f32) @TypeOf(a, b) {
    const t_clamped = clamp01(t);
    return @mulAdd(@TypeOf(a, b), b - a, @splat(t_clamped), a);
}

/// Lerps between two @Vector objects by a scalar t
pub inline fn lerpUnclampedVec(a: anytype, b: anytype, t: f32) @TypeOf(a, b) {
    return @mulAdd(@TypeOf(a, b), b - a, @splat(t), a);
}

/// Normalizes a @Vector object
pub fn normalizeVec(vec: anytype) @TypeOf(vec) {
    const len = lengthVec(vec);
    if (len == 0) return vec;
    return vec / @as(@TypeOf(vec), @splat(len));
}

test normalizeVec {
    try expectEqual(@Vector(2, f32){ 1, 0 }, normalizeVec(@Vector(2, f32){ 200_000, 0 }));
    try expectEqual(@Vector(2, f32){ 0.8, 0.6 }, normalizeVec(@Vector(2, f32){ 8, 6 }));
    try expectEqual(@Vector(2, f32){ 0, 0 }, normalizeVec(@Vector(2, f32){ 0, 0 }));
}

/// Returns the dot product of two @Vector objects
pub inline fn dotVec(vec0: anytype, vec1: @TypeOf(vec0)) f32 {
    return @reduce(.Add, vec0 * vec1);
}

test dotVec {
    try expectEqual(@as(f32, 32.0), dotVec(@Vector(3, f32){ 1, 2, 3 }, .{ 4, 5, 6 }));
    try expectEqual(@as(f32, 28.0), dotVec(@Vector(3, f32){ 6, 5, 4 }, .{ 1, 2, 3 }));
    try expectEqual(@as(f32, -3.0), dotVec(@Vector(3, f32){ 1, 1, 1 }, .{ -1, -1, -1 }));
}

/// Swizzles a @Vector object by a comptime mask
pub inline fn swizzleVec(vec: anytype, comptime mask: @TypeOf(vec)) @TypeOf(vec) {
    const Vector = @typeInfo(@TypeOf(vec)).vector;
    comptime for (@as([Vector.len]Vector.child, mask)) |m| if (m < 0) @compileError(std.fmt.comptimePrint("Swizzle mask must be all positive, found {}.", .{m}));
    return @shuffle(f32, vec, undefined, mask);
}

test swizzleVec {
    try expectEqual(@Vector(2, f32){ 1, 1 }, swizzleVec(@Vector(2, f32){ 1, 2 }, .{ 0, 0 }));
    try expectEqual(@Vector(2, f32){ 2, 2 }, swizzleVec(@Vector(2, f32){ 1, 2 }, .{ 1, 1 }));
    try expectEqual(@Vector(2, f32){ 2, 1 }, swizzleVec(@Vector(2, f32){ 1, 2 }, .{ 1, 0 }));
}

test {
    _ = @import("vec2.zig");
    _ = @import("vec3.zig");
    _ = @import("vec4.zig");
    _ = @import("vec_funcs.zig");
}
