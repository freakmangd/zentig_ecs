const std = @import("std");
const ztg = @import("../../init.zig");
const zmath = @import("zmath");

const Self = @This();

basis: zmath.Mat,
basis_isdirty: bool = true,

__data: struct {
    rot: ztg.Vec4,
    scale: ztg.Vec3,
},

parent: ?*Self = null,

pub fn init(_pos: ztg.Vec3, _rot: ztg.Vec4, _scale: ztg.Vec3) Self {
    return .{
        .basis = zmath.translationV(_pos.intoZMath()),
        .__data = .{
            .rot = _rot,
            .scale = _scale,
        },
    };
}

pub inline fn initWith(with: struct {
    pos: ztg.Vec3 = ztg.Vec3.zero(),
    rot: ztg.Vec4 = ztg.Vec4.identity(),
    scale: ztg.Vec3 = ztg.Vec3.one(),
}) Self {
    return init(with.pos, with.rot, with.scale);
}

pub inline fn default() Self {
    return init(ztg.Vec3.zero(), ztg.Vec4.identity(), ztg.Vec3.one());
}

pub inline fn getPos(self: Self) ztg.Vec3 {
    return ztg.Vec3.fromZMath(self.basis[3]);
}

pub fn getGlobalPos(self: Self) ztg.Vec3 {
    if (self.parent) |parent| return self.getPos().add(parent.getGlobalPos());
    return self.getPos();
}

pub inline fn setPos(self: *Self, new_pos: ztg.Vec3) void {
    self.basis[3][0] = new_pos.x;
    self.basis[3][1] = new_pos.y;
    self.basis[3][2] = new_pos.z;
}

pub inline fn translate(self: *Self, by: ztg.Vec3) void {
    self.basis[3] += by.intoZMath();
}

pub inline fn getRot(self: Self) ztg.Vec4 {
    return self.__data.rot;
}

pub fn getGlobalRot(self: Self) ztg.Vec4 {
    if (self.parent) |parent| return self.__data.rot.add(parent.getGlobalRot());
    return self.getRot();
}

pub inline fn setRot(self: *Self, new_rot: ztg.Vec4) void {
    self.__data.rot = new_rot;
    self.basis_isdirty = true;
}

pub inline fn rotate(self: *Self, by: ztg.Vec4) void {
    std.debug.print("before {}\n", .{std.math.radiansToDegrees(f32, by.z)});
    self.__data.rot.addEql(by);
    std.debug.print("added {}\n", .{std.math.radiansToDegrees(f32, by.z)});
    self.basis_isdirty = true;
}

pub inline fn getScale(self: Self) ztg.Vec3 {
    return self.__data.scale;
}

pub inline fn setScale(self: Self, new_scale: ztg.Vec3) void {
    self.__data.scale = new_scale;
    self.basis_isdirty = true;
}

pub inline fn scale(self: *Self, scalar: ztg.Vec3) void {
    self.__data.scale.scaleEql(scalar);
    self.basis_isdirty = true;
}

pub fn updateBasis(self: *Self) void {
    const mat0 = zmath.scalingV(self.__data.scale.intoZMath());
    const mat1 = zmath.mul(mat0, zmath.rotationX(self.__data.rot.x));
    const mat2 = zmath.mul(mat1, zmath.rotationY(self.__data.rot.y));
    const mat3 = zmath.mul(mat2, zmath.rotationZ(self.__data.rot.z));
    const mat4 = zmath.mul(mat3, zmath.translationV(self.getPos().intoZMath()));

    self.basis_isdirty = false;
    self.basis = mat4;
}

pub fn getGlobalMatrix(self: *Self) zmath.Mat {
    if (self.basis_isdirty) self.updateBasis();
    if (self.parent) |parent| return zmath.mul(parent.getGlobalMatrix(), self.basis);
    return self.basis;
}
