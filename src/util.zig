//! Functions used internally by zentig that either shouldnt be exposed
//! or are too specific to be of any use outside zentig.

const std = @import("std");
const builtin = @import("builtin");
const ztg = @import("init.zig");

/// Get the element type of a MultiArrayList
pub fn MultiArrayListElem(comptime T: type) type {
    return @typeInfo(@TypeOf(T.pop)).Fn.return_type.?;
}

/// Get the element type of an ArrayHashMap
pub fn ArrayHashMapElem(comptime T: type) type {
    return @typeInfo(T.KV).Struct.fields[1].type;
}

pub fn compileError(comptime format: []const u8, comptime args: anytype) noreturn {
    @compileError(std.fmt.comptimePrint(format, args));
}

pub fn assertOkOnAddedFunction(comptime Container: type) void {
    const member_type = comptime ztg.meta.memberFnType(Container, "onAdded");
    const fn_info = @typeInfo(@TypeOf(Container.onAdded)).Fn;

    const return_type_info = @typeInfo(fn_info.return_type.?);
    if (!(return_type_info == .Void or (return_type_info == .ErrorUnion and return_type_info.ErrorUnion.payload == void))) {
        @compileError("onAdded functions must return void or !void");
    }

    if (comptime member_type == .non_member and (fn_info.params[0].type.? != ztg.Entity or fn_info.params[1].type.? != ztg.Commands)) {
        compileError("non-member onAdded function from type `{s}` does not follow the form fn (Entity, Commands) (!)void", .{@typeName(Container)});
    } else if (comptime member_type != .non_member and (fn_info.params[1].type.? != ztg.Entity or fn_info.params[2].type.? != ztg.Commands)) {
        compileError("member onAdded function from type `{s}` does not follow the form fn (Self|*const Self|*Self, Entity, Commands) (!)void", .{@typeName(Container)});
    }
}

pub fn resetCompIds() void {
    if (comptime builtin.mode != .Debug) return;
    id_counter = 0;
    last_reset_id += 1;
}

pub const CompId = usize;
var last_reset_id: if (builtin.mode == .Debug) usize else void = if (builtin.mode == .Debug) 0 else void{};
var id_counter: CompId = 0;
pub fn compId(comptime T: type) CompId {
    _ = T;
    const static = struct {
        var reset_id: if (builtin.mode == .Debug) usize else void = if (builtin.mode == .Debug) 0 else void{};
        var id: ?CompId = null;
    };
    const result = blk: {
        if (static.id == null or if (comptime builtin.mode == .Debug) if_blk: {
            break :if_blk static.reset_id != last_reset_id;
        } else if_blk: {
            break :if_blk false;
        }) {
            static.id = id_counter;
            static.reset_id = last_reset_id;
            id_counter += 1;
        }
        break :blk static.id.?;
    };
    return result;
}

pub fn idsFromTypes(comptime types: []const type) [types.len]CompId {
    var out: [types.len]CompId = undefined;
    inline for (types, &out) |T, *o| o.* = compId(T);
    return out;
}

pub const CompIdList = struct {
    ids: []const CompId,
    is_required: bool,
};
