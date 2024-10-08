const std = @import("std");
const math = @import("init.zig");

const Self = @This();

pub const Row = @Vector(3, f32);
rows: [3]Row = .{
    .{ 1, 0, 0 },
    .{ 0, 1, 0 },
    .{ 0, 0, 1 },
},

pub inline fn init(xx: f32, xy: f32, xz: f32, yx: f32, yy: f32, yz: f32, zx: f32, zy: f32, zz: f32) Self {
    return .{ .rows = .{
        .{ xx, xy, xz },
        .{ yx, yy, yz },
        .{ zx, zy, zz },
    } };
}

pub inline fn identity() Self {
    return .{ .rows = .{
        .{ 1, 0, 0 },
        .{ 0, 1, 0 },
        .{ 0, 0, 1 },
    } };
}

pub inline fn one() Self {
    return .{ .rows = [_]Row{@splat(@as(f32, 1))} ** 3 };
}

pub inline fn zero() Self {
    return .{ .rows = [_]Row{@splat(@as(f32, 0))} ** 3 };
}

pub inline fn splat(val: f32) Self {
    return .{ .rows = [_]Row{@splat(val)} ** 3 };
}

pub inline fn reduceColumn(self: Self, comptime op: std.builtin.ReduceOp, col: usize) f32 {
    return @reduce(op, self.getColumn(col));
}

pub inline fn reduceRow(self: Self, comptime op: std.builtin.ReduceOp, row: usize) f32 {
    return @reduce(op, self.getRow(row));
}

pub inline fn set(self: *Self, xx: f32, xy: f32, xz: f32, yx: f32, yy: f32, yz: f32, zx: f32, zy: f32, zz: f32) void {
    self.* = .{ .rows = .{
        .{ xx, xy, xz },
        .{ yx, yy, yz },
        .{ zx, zy, zz },
    } };
}

pub inline fn setZero(self: *Self) void {
    self.* = zero();
}

pub inline fn getColumn(self: Self, col: usize) @Vector(3, f32) {
    return .{ self.rows[0][col], self.rows[1][col], self.rows[2][col] };
}

pub inline fn setColumn(self: *Self, col: usize, value: f32) void {
    self.rows[0][col] = value;
    self.rows[1][col] = value;
    self.rows[2][col] = value;
}

pub inline fn setColumnVec(self: *Self, col: usize, vec: @Vector(3, f32)) void {
    self.rows[0][col] = vec[0];
    self.rows[1][col] = vec[1];
    self.rows[2][col] = vec[2];
}

pub inline fn getRow(self: Self, row: usize) Row {
    return self.rows[row];
}

pub inline fn setRow(self: *Self, row: usize, value: f32) void {
    self.rows[row][0] = value;
    self.rows[row][1] = value;
    self.rows[row][2] = value;
}

pub inline fn setRowVec(self: *Self, row: usize, vec: @Vector(3, f32)) void {
    self.rows[row][0] = vec[0];
    self.rows[row][1] = vec[1];
    self.rows[row][2] = vec[2];
}

pub inline fn getMainDiagonal(self: Self) @Vector(3, f32) {
    return .{ self.rows[0][0], self.rows[1][1], self.rows[2][2] };
}

pub inline fn mul(v0: Self, v1: Self) Self {
    return .{
        Row{ v0.tranDot(0, v1.rows[0]), v0.tranDot(1, v1.rows[0]), v0.tranDot(2, v1.rows[0]) },
        Row{ v0.tranDot(0, v1.rows[1]), v0.tranDot(1, v1.rows[1]), v0.tranDot(2, v1.rows[1]) },
        Row{ v0.tranDot(0, v1.rows[2]), v0.tranDot(1, v1.rows[2]), v0.tranDot(2, v1.rows[2]) },
    };
}

pub inline fn add(v0: Self, v1: Self) Self {
    return .{
        v0.rows[0] + v1.rows[0],
        v0.rows[1] + v1.rows[1],
        v0.rows[2] + v1.rows[2],
    };
}

pub inline fn sub(v0: Self, v1: Self) Self {
    return .{
        v0.rows[0] - v1.rows[0],
        v0.rows[1] - v1.rows[1],
        v0.rows[2] - v1.rows[2],
    };
}

pub inline fn scale(self: Self, value: f32) Self {
    return .{
        self.rows[0] * @as(@Vector(3, f32), @splat(value)),
        self.rows[1] * @as(@Vector(3, f32), @splat(value)),
        self.rows[2] * @as(@Vector(3, f32), @splat(value)),
    };
}

pub inline fn mulEql(self: *Self, v1: Self) Self {
    self.rows[0] = Row{ self.tranDot(0, v1.rows[0]), self.tranDot(1, v1.rows[0]), self.tranDot(2, v1.rows[0]) };
    self.rows[1] = Row{ self.tranDot(0, v1.rows[1]), self.tranDot(1, v1.rows[1]), self.tranDot(2, v1.rows[1]) };
    self.rows[2] = Row{ self.tranDot(0, v1.rows[2]), self.tranDot(1, v1.rows[2]), self.tranDot(2, v1.rows[2]) };
}

pub inline fn addEql(self: *Self, v1: Self) Self {
    self.rows[0] += v1.rows[0];
    self.rows[1] += v1.rows[1];
    self.rows[2] += v1.rows[2];
}

pub inline fn subEql(self: *Self, v1: Self) Self {
    self.rows[0] -= v1.rows[0];
    self.rows[1] -= v1.rows[1];
    self.rows[2] -= v1.rows[2];
}

pub inline fn scaleEql(self: *Self, value: f32) Self {
    self.rows[0] *= @as(@Vector(3, f32), @splat(value));
    self.rows[1] *= @as(@Vector(3, f32), @splat(value));
    self.rows[2] *= @as(@Vector(3, f32), @splat(value));
}

pub fn getScale() @Vector(3, f32) {}

pub fn determinant(self: Self) f32 {
    // zig fmt: off
    return self.rows[0][0] * (self.rows[1][1] * self.rows[2][2] - self.rows[2][1] * self.rows[1][2]) -
        self.rows[1][0] * (self.rows[0][1] * self.rows[2][2] - self.rows[2][1] * self.rows[0][2]) +
        self.rows[2][0] * (self.rows[0][1] * self.rows[1][2] - self.rows[1][1] * self.rows[0][2]);
    // zig fmt: on
}

inline fn cofac(self: Self, row1: usize, col1: usize, row2: usize, col2: usize) f32 {
    return self.rows[row1][col1] * self.rows[row2][col2] - self.rows[row1][col2] * self.rows[row2][col1];
}

pub fn inverted(self: Self) error{DivisionByZero}!Self {
    const co = @Vector(3, f32){
        self.cofac(1, 1, 2, 2),
        self.cofac(1, 2, 2, 0),
        self.cofac(1, 0, 2, 1),
    };

    const det = @reduce(.Add, self.getRow(0) * co);
    if (det == 0.0) return error.DivisionByZero;
    const s: f32 = 1.0 / (if (comptime @typeInfo(f32) == .int) @as(f32, @floatFromInt(det)) else det);

    return .{ .rows = [_]Row{
        Row{ co[0] * s, self.cofac(0, 2, 2, 1) * s, self.cofac(0, 1, 1, 2) * s },
        Row{ co[1] * s, self.cofac(0, 0, 2, 2) * s, self.cofac(0, 2, 1, 0) * s },
        Row{ co[2] * s, self.cofac(0, 1, 2, 0) * s, self.cofac(0, 0, 1, 1) * s },
    } };
}

pub fn orthonormalized(self: Self) Self {
    var x = self.getColumn(0);
    var y = self.getColumn(1);
    var z = self.getColumn(2);

    x = math.normalizeVec3(x);
    y = y - x * @as(@Vector(3, f32), @splat(math.dotVec3(x, y)));
    y = math.normalizeVec3(y);
    z = z - x * @as(@Vector(3, f32), @splat(math.dotVec3(x, z))) - y * @as(@Vector(3, f32), @splat(math.dotVec3(y, z)));
    z = math.normalizeVec3(z);

    return .{
        .rows = .{ x, y, z },
    };
}

pub fn orthogonalized(self: Self) Self {
    _ = self;
}

pub inline fn xform(self: Self, vec: @Vector(3, f32)) @Vector(3, f32) {
    return .{
        math.dotVec3(self.rows[0], vec),
        math.dotVec3(self.rows[1], vec),
        math.dotVec3(self.rows[2], vec),
    };
}

pub inline fn xformInv(self: Self, vec: @Vector(3, f32)) @Vector(3, f32) {
    return .{
        @reduce(.Add, self.getColumn(0) * vec),
        @reduce(.Add, self.getColumn(1) * vec),
        @reduce(.Add, self.getColumn(2) * vec),
    };
}

pub inline fn tranXForm(self: Self, other: Self) Self {
    return .{ .rows = .{
        .{
            @reduce(.Add, self.getColumn(0) * other.getColumn(0)),
            @reduce(.Add, self.getColumn(0) * other.getColumn(1)),
            @reduce(.Add, self.getColumn(0) * other.getColumn(2)),
        },
        .{
            @reduce(.Add, self.getColumn(1) * other.getColumn(0)),
            @reduce(.Add, self.getColumn(1) * other.getColumn(1)),
            @reduce(.Add, self.getColumn(1) * other.getColumn(2)),
        },
        .{
            @reduce(.Add, self.getColumn(2) * other.getColumn(0)),
            @reduce(.Add, self.getColumn(2) * other.getColumn(1)),
            @reduce(.Add, self.getColumn(2) * other.getColumn(2)),
        },
    } };
}

/// f32ransposed dot product of a column
pub inline fn tranDot(self: Self, col: usize, vec: @Vector(3, f32)) f32 {
    return @reduce(.Add, self.getColumn(col) * vec);
}
