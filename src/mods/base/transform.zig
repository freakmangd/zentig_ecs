const std = @import("std");
const ztg = @import("../../init.zig");
const zmath = @import("zmath");

const Transform = @This();

basis: zmath.Mat = zmath.identity(),
/// Read only
rotation: ztg.Vec4 = .identity,
/// Read only
scale: ztg.Vec3 = .one,
/// Requests an update of basis, you don't have to touch this
basis_is_dirty: bool = false,

pub const identity: Transform = .{
    .basis = zmath.identity(),
    .rotation = .identity,
    .scale = .one,
    .basis_is_dirty = false,
};

pub fn init(pos: ztg.Vec3, rot: ztg.Vec4, scale: ztg.Vec3) Transform {
    return .{
        .basis = zmath.translation(pos.x, pos.y, pos.z),
        .rotation = rot,
        .scale = scale,
    };
}

pub const InitOptions = struct {
    pos: ztg.Vec3 = .zero,
    rot: ztg.Vec4 = .identity,
    scale: ztg.Vec3 = .one,
};

pub fn initWith(with: InitOptions) Transform {
    return init(with.pos, with.rot, with.scale);
}

pub fn fromPos(pos: ztg.Vec3) Transform {
    return init(pos, .identity, .one);
}

pub fn fromRot(rot: ztg.Vec4) Transform {
    return init(.zero, rot, .one);
}

pub fn fromScale(scale: ztg.Vec3) Transform {
    return init(.zero, .identity, scale);
}

pub fn getPos(self: Transform) ztg.Vec3 {
    return .fromZMath(self.basis[3]);
}

pub fn setPos(self: *Transform, new_pos: ztg.Vec3) void {
    self.basis[3][0] = new_pos.x;
    self.basis[3][1] = new_pos.y;
    self.basis[3][2] = new_pos.z;
}

pub fn translate(self: *Transform, by: ztg.Vec3) void {
    self.basis[3] += by.intoZMath();
}

pub fn getRot(self: Transform) ztg.Vec4 {
    return self.rotation;
}

pub fn setRot(self: *Transform, new_rot: ztg.Vec4) void {
    self.rotation = new_rot;
    self.basis_is_dirty = true;
}

pub fn setRotEuler(self: *Transform, x: f32, y: f32, z: f32) void {
    self.rotation = .fromEulerAngles(.{ .x = x, .y = y, .z = z });
    self.basis_is_dirty = true;
}

pub fn setRotEulerV(self: *Transform, euler: ztg.Vec3) void {
    self.rotation = .fromEulerAngles(euler);
    self.basis_is_dirty = true;
}

pub fn rotate(self: *Transform, by: ztg.Vec4) void {
    self.rotation = self.rotation.quatMultiply(by);
    self.basis_is_dirty = true;
}

pub fn rotateEuler(self: *Transform, x: f32, y: f32, z: f32) void {
    self.rotate(.fromEulerAngles(.{ .x = x, .y = y, .z = z }));
}

pub fn rotateEulerV(self: *Transform, by: ztg.Vec3) void {
    self.rotate(.fromEulerAngles(by));
}

pub fn getScale(self: Transform) ztg.Vec3 {
    return self.scale;
}

pub fn setScale(self: *Transform, new_scale: ztg.Vec3) void {
    self.scale = new_scale;
    self.basis_is_dirty = true;
}

pub fn scaleBy(self: *Transform, scalar: ztg.Vec3) void {
    self.scale.scaleEql(scalar);
    self.basis_is_dirty = true;
}

pub fn updateBasis(self: *Transform) void {
    self.basis_is_dirty = false;
    self.basis = self.calculateLatestMatrix();
}

pub fn calculateLatestMatrix(self: Transform) zmath.Mat {
    const mat0 = zmath.scalingV(self.scale.intoZMath());
    const mat1 = zmath.mul(mat0, zmath.matFromQuat(self.rotation.intoZMath()));
    return zmath.mul(mat1, zmath.translationV(self.getPos().intoZMath()));
}

pub fn getUpdatedBasis(self: *Transform) zmath.Mat {
    if (self.basis_is_dirty) self.updateBasis();
    return self.basis;
}

pub fn onAdded(ent: ztg.Entity, com: ztg.Commands) !void {
    if (!com.checkEntHas(ent, ztg.base.GlobalTransform)) try com.giveComponents(ent, .{ztg.base.GlobalTransform.identity});
}

test Transform {
    std.testing.refAllDecls(Transform);

    var t = Transform.initWith(.{
        .pos = .{ .x = 100 },
    });

    try std.testing.expectEqual(ztg.Vec3.init(100, 0, 0), t.getPos());

    t.setPos(.{ .x = 10 });

    try std.testing.expectEqual(ztg.Vec3.init(10, 0, 0), t.getPos());

    t.translate(.{
        .y = 100,
        .z = -20,
    });

    try std.testing.expectEqual(ztg.Vec3.init(10, 100, -20), t.getPos());

    t.rotateEuler(120, 80, 90);

    try std.testing.expectEqual(ztg.Vec4.fromEulerAngles(.{ .x = 120, .y = 80, .z = 90 }), t.getRot());
}
