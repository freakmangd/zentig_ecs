const std = @import("std");
const ztg = @import("../../init.zig");

const Self = @This();

basis: ztg.zmath.Mat,
__data: struct {
    basis_isdirty: bool = true,
    rot: ztg.Vec4,
    scale: ztg.Vec3,
},

pub inline fn identity() Self {
    return .{
        .basis = ztg.zmath.identity(),
        .__data = .{
            .rot = ztg.Vec4.identity(),
            .scale = ztg.Vec3.one(),
        },
    };
}

pub inline fn getPos(self: Self) ztg.Vec3 {
    return ztg.Vec3.fromZMath(self.basis[3]);
}

pub inline fn getRot(self: Self) ztg.Vec4 {
    return self.__data.rot;
}

pub inline fn getScale(self: Self) ztg.Vec3 {
    return self.__data.scale;
}

fn updateBasis(self: *Self, com: ztg.Commands, ent: ztg.Entity) void {
    var local_tr = com.getComponentPtr(ent, ztg.base.Transform).?;

    var parent_ent = (com.getEntParent(ent) catch unreachable) orelse {
        // we dont have a parent
        self.basis = local_tr.getUpdatedBasis();
        self.__data.basis_isdirty = false;
        return;
    };

    var parent_gtr = com.getComponentPtr(parent_ent, ztg.base.GlobalTransform) orelse {
        // parent doesnt have a transform
        self.basis = local_tr.getUpdatedBasis();
        self.__data.basis_isdirty = false;
        return;
    };

    self.basis = ztg.zmath.mul(local_tr.getUpdatedBasis(), parent_gtr.getUpdatedBasis(com, parent_ent));
    self.__data.basis_isdirty = false;
}

fn getUpdatedBasis(self: *Self, com: ztg.Commands, ent: ztg.Entity) ztg.zmath.Mat {
    if (!self.__data.basis_isdirty) return self.basis;
    self.updateBasis(com, ent);
    return self.basis;
}

pub fn include(comptime wb: *ztg.WorldBuilder) void {
    wb.addComponents(&.{Self});
    wb.addLabel(.post_update, .gtr_update, .default);
    wb.addSystemsToStage(.post_update, ztg.during(.gtr_update, pou_updateGlobals));
}

fn pou_updateGlobals(com: ztg.Commands, q: ztg.Query(.{ ztg.Entity, Self })) void {
    for (q.items(0), q.items(1)) |ent, gtr| {
        gtr.updateBasis(com, ent);
    }
    for (q.items(1)) |gtr| gtr.__data.basis_isdirty = true;
}
