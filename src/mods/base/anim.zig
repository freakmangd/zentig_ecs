const std = @import("std");
const ztg = @import("../../init.zig");

const Self = @This();

state: ztg.StateMachine,

pub fn init(alloc: std.mem.Allocator, comptime States: type, comptime Events: type, default_state: States) Self {
    return .{
        .state = ztg.StateMachine.init(alloc, States, Events, default_state, onTransition),
    };
}

fn onTransition(ctx: *anyopaque, event: ?usize, from: usize, to: usize) !void {
    _ = to;
    _ = from;
    _ = event;
    var self: Self = @ptrCast(@alignCast(ctx));
    _ = self;
}
