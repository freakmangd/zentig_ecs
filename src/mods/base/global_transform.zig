const std = @import("std");
const ztg = @import("../../init.zig");

const GlobalTransform = @This();

basis: ztg.zmath.Mat,
__data: struct {
    rot: ztg.Vec4,
    scale: ztg.Vec3,
    basis_is_dirty: bool = true,
},

pub const identity: GlobalTransform = .{
    .basis = ztg.zmath.identity(),
    .__data = .{
        .rot = ztg.Vec4.identity,
        .scale = ztg.Vec3.one,
    },
};

pub fn getPos(self: GlobalTransform) ztg.Vec3 {
    return ztg.Vec3.fromZMath(self.basis[3]);
}

pub fn getRot(self: GlobalTransform) ztg.Vec4 {
    return self.__data.rot;
}

pub fn getScale(self: GlobalTransform) ztg.Vec3 {
    return self.__data.scale;
}

fn updateBasis(self: *GlobalTransform, com: ztg.Commands, ent: ztg.Entity) void {
    var local_tr = com.getComponentPtr(ent, ztg.base.Transform).?;

    const parent_ent = (com.getEntParent(ent) catch unreachable) orelse {
        // we dont have a parent
        self.basis = local_tr.getUpdatedBasis();
        self.__data.rot = local_tr.getRot();
        self.__data.scale = local_tr.getScale();
        self.__data.basis_is_dirty = false;
        return;
    };

    var parent_gtr = com.getComponentPtr(parent_ent, GlobalTransform) orelse {
        // parent doesnt have a transform
        self.basis = local_tr.getUpdatedBasis();
        self.__data.rot = local_tr.getRot();
        self.__data.scale = local_tr.getScale();
        self.__data.basis_is_dirty = false;
        return;
    };

    self.basis = ztg.zmath.mul(local_tr.getUpdatedBasis(), parent_gtr.getUpdatedBasis(com, parent_ent));
    self.__data.rot = local_tr.getRot().quatMultiply(parent_gtr.getRot());
    self.__data.scale = local_tr.getScale().scale(parent_gtr.getScale());
    self.__data.basis_is_dirty = false;
}

fn getUpdatedBasis(self: *GlobalTransform, com: ztg.Commands, ent: ztg.Entity) ztg.zmath.Mat {
    if (self.__data.basis_is_dirty) self.updateBasis(com, ent);
    return self.basis;
}

pub fn include(comptime wb: *ztg.WorldBuilder) void {
    wb.addComponents(&.{GlobalTransform});
    wb.addLabel(.post_update, .gtr_update, .default);
    wb.addSystemsToStage(.post_update, ztg.during(.gtr_update, pou_updateGlobals));
}

fn pou_updateGlobals(com: ztg.Commands, q: ztg.Query(.{ ztg.Entity, GlobalTransform })) void {
    for (q.items(ztg.Entity), q.items(GlobalTransform)) |ent, gtr| {
        gtr.updateBasis(com, ent);
    }
    for (q.items(GlobalTransform)) |gtr| gtr.__data.basis_is_dirty = true;
}
