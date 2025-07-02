const std = @import("std");
const ztg = @import("../../init.zig");
const zmath = @import("zmath");

const Self = @This();

basis: zmath.Mat = zmath.translationV(ztg.Vec3.zero.intoZMath()),
__data: struct {
    rot: ztg.Vec4 = ztg.Vec4.identity,
    scale: ztg.Vec3 = ztg.Vec3.one,
    basis_is_dirty: bool = true,
} = .{},

pub const InitOptions = struct {
    pos: ztg.Vec3 = ztg.Vec3.zero,
    rot: ztg.Vec4 = ztg.Vec4.identity,
    scale: ztg.Vec3 = ztg.Vec3.one,
};

pub fn init(_pos: ztg.Vec3, _rot: ztg.Vec4, _scale: ztg.Vec3) Self {
    return .{
        .basis = zmath.translationV(_pos.intoZMath()),
        .__data = .{
            .rot = _rot,
            .scale = _scale,
        },
    };
}

pub fn initWith(with: InitOptions) Self {
    return init(with.pos, with.rot, with.scale);
}

pub fn fromPos(pos: ztg.Vec3) Self {
    return init(pos, ztg.Vec4.identity, ztg.Vec3.one);
}

pub fn fromRot(rot: ztg.Vec4) Self {
    return init(ztg.Vec3.zero, rot, ztg.Vec3.one);
}

pub fn fromScale(_scale: ztg.Vec3) Self {
    return init(ztg.Vec3.zero, ztg.Vec4.identity, _scale);
}

pub fn getPos(self: Self) ztg.Vec3 {
    return ztg.Vec3.fromZMath(self.basis[3]);
}

pub fn setPos(self: *Self, new_pos: ztg.Vec3) void {
    zmath.storeArr4(&self.basis[3], new_pos.intoZMath());
}

pub fn translate(self: *Self, by: ztg.Vec3) void {
    self.basis[3] += by.intoZMath();
}

pub fn getRot(self: Self) ztg.Vec4 {
    return self.__data.rot;
}

pub fn setRot(self: *Self, new_rot: ztg.Vec4) void {
    self.__data.rot = new_rot;
    self.__data.basis_is_dirty = true;
}

pub fn setRotEuler(self: *Self, x: f32, y: f32, z: f32) void {
    self.__data.rot = ztg.Vec4.fromEulerAngles(.{ .x = x, .y = y, .z = z });
    self.__data.basis_is_dirty = true;
}

pub fn rotate(self: *Self, by: ztg.Vec4) void {
    self.__data.rot = self.__data.rot.quatMultiply(by);
    self.__data.basis_is_dirty = true;
}

pub fn rotateEuler(self: *Self, x: f32, y: f32, z: f32) void {
    self.rotate(ztg.Vec4.fromEulerAngles(.{ .x = x, .y = y, .z = z }));
}

pub fn getScale(self: Self) ztg.Vec3 {
    return self.__data.scale;
}

pub fn setScale(self: *Self, new_scale: ztg.Vec3) void {
    self.__data.scale = new_scale;
    self.__data.basis_is_dirty = true;
}

pub fn scale(self: *Self, scalar: ztg.Vec3) void {
    self.__data.scale.scaleEql(scalar);
    self.__data.basis_is_dirty = true;
}

pub fn updateBasis(self: *Self) void {
    self.__data.basis_is_dirty = false;
    self.basis = self.calculateLatestMatrix();
}

pub fn calculateLatestMatrix(self: Self) zmath.Mat {
    const mat0 = zmath.scalingV(self.__data.scale.intoZMath());
    const mat1 = zmath.mul(mat0, zmath.matFromQuat(self.__data.rot.intoZMath()));
    return zmath.mul(mat1, zmath.translationV(self.getPos().intoZMath()));
}

pub fn getUpdatedBasis(self: *Self) zmath.Mat {
    if (self.__data.basis_is_dirty) self.updateBasis();
    return self.basis;
}

pub fn onAdded(ent: ztg.Entity, com: ztg.Commands) !void {
    if (!com.checkEntHas(ent, ztg.base.GlobalTransform)) try com.giveComponents(ent, .{ztg.base.GlobalTransform.identity});
}

test {
    var t = Self.initWith(.{
        .pos = .{ .x = 100 },
    });

    try std.testing.expectEqual(ztg.vec3(100, 0, 0), t.getPos());

    t.translate(.{
        .y = 100,
        .z = -20,
    });

    try std.testing.expectEqual(ztg.vec3(100, 100, -20), t.getPos());

    t.rotateEuler(120, 80, 90);

    try std.testing.expectEqual(ztg.Vec4.fromEulerAngles(.{ .x = 120, .y = 80, .z = 90 }), t.getRot());
}
