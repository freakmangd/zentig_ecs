const std = @import("std");
const expectEqual = std.testing.expectEqual;

/// Alias for `f32`, used to clarify input parameters for
/// functions that take angles in radians
pub const Radians = f32;

/// Alias for `f32`, used to clarify input parameters for
/// functions that take angles in degrees
pub const Degrees = f32;

inline fn toFloat(comptime T: type, x: anytype) T {
    if (T == @TypeOf(x)) return x;

    return switch (@typeInfo(@TypeOf(x))) {
        .Int => @floatFromInt(x),
        .Float => @floatCast(x),
        .ComptimeFloat, .ComptimeInt => x,
        else => |X| @compileError("Cannot convert " ++ @typeName(X) ++ " to a float."),
    };
}

test toFloat {
    try expectEqual(@as(f32, 1.0), toFloat(f32, 1));
    try expectEqual(@as(f32, 1.0), toFloat(f32, 1.0));
    try expectEqual(@as(f32, 1.0), toFloat(f32, @as(i32, 1)));
    try expectEqual(@as(f32, 1.0), toFloat(f32, @as(f32, 1.0)));
}

/// Converts a and b to floats (if neeeded) and multiplies them, returning a float of type T
pub inline fn mulAsFloat(comptime T: type, a: anytype, b: anytype) T {
    return toFloat(T, a) * toFloat(T, b);
}

test mulAsFloat {
    try expectEqual(@as(f32, 7.0), mulAsFloat(f32, 14, 0.5));
    try expectEqual(@as(f32, 20.5), mulAsFloat(f32, @as(u1, 1), @as(f32, 20.5)));
}

/// Converts a and b to floats (if neeeded) and divides them, returning a float of type T
pub inline fn divAsFloat(comptime T: type, a: anytype, b: anytype) error{DivideByZero}!T {
    if (b == 0) return error.DivideByZero;
    return toFloat(T, a) / toFloat(T, b);
}

test divAsFloat {
    try expectEqual(@as(f32, 0.13), try divAsFloat(f32, 13, 100));
    try expectEqual(@as(f32, 0.5), try divAsFloat(f32, @as(u1, 1), @as(i32, 2)));
    try std.testing.expectError(error.DivideByZero, divAsFloat(f32, 1_000, 0));
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
///
/// Example:
/// ```zig
/// try expectEqual(@Vector(2, f32){ 1, 1 }, swizzleVec(@Vector(2, f32){ 1, 2 }, .{ 0, 0 }));
/// try expectEqual(@Vector(2, f32){ 2, 2 }, swizzleVec(@Vector(2, f32){ 1, 2 }, .{ 1, 1 }));
/// try expectEqual(@Vector(2, f32){ 2, 1 }, swizzleVec(@Vector(2, f32){ 1, 2 }, .{ 1, 0 }));
/// ```
pub inline fn swizzleVec(vec: anytype, comptime mask: @TypeOf(vec)) @TypeOf(vec) {
    const Vector = @typeInfo(@TypeOf(vec)).Vector;
    comptime for (@as([Vector.len]Vector.child, mask)) |m| if (m < 0) @compileError(std.fmt.comptimePrint("Swizzle mask must be all positive, found {}.", .{m}));
    return @shuffle(f32, vec, undefined, mask);
}

test swizzleVec {
    try expectEqual(@Vector(2, f32){ 1, 1 }, swizzleVec(@Vector(2, f32){ 1, 2 }, .{ 0, 0 }));
    try expectEqual(@Vector(2, f32){ 2, 2 }, swizzleVec(@Vector(2, f32){ 1, 2 }, .{ 1, 1 }));
    try expectEqual(@Vector(2, f32){ 2, 1 }, swizzleVec(@Vector(2, f32){ 1, 2 }, .{ 1, 0 }));
}

test {
    std.testing.refAllDeclsRecursive(@This());
    _ = @import("vec2.zig");
    _ = @import("vec3.zig");
    _ = @import("vec4.zig");
    _ = @import("vec_funcs.zig");
}
