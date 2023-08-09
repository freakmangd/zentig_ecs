const std = @import("std");
const ztg = @import("init.zig");

const Self = @This();

alloc: std.mem.Allocator,

current_state: usize,
transitions: std.AutoHashMapUnmanaged(Transitions) = .{},
onTransition: *const fn (ctx: *anyopaque, event: ?usize, from: usize, to: usize) anyerror!void,

states_max_val: usize,
events_max_val: usize,

const Transitions = std.AutoHashMapUnmanaged(usize);

pub fn init(alloc: std.mem.Allocator, comptime States: type, comptime Events: type, default_state: States, onTransition: *const fn (ctx: *anyopaque, event: ?usize, from: usize, to: usize) anyerror!void) Self {
    return .{
        .alloc = alloc,
        .current_state = @intFromEnum(default_state),
        .onTransition = onTransition,
        .states_max_val = std.meta.fields(States).len - 1,
        .events_max_val = std.meta.fields(Events).len - 1,
    };
}

pub fn transitionTo(self: *Self, ctx: *anyopaque, state: anytype) !void {
    const val = try self.convertTo(.state, state);
    try self.onTransition(ctx, null, self.current_state, val);
    self.current_state = val;
}

pub fn invoke(self: *Self, ctx: *anyopaque, event: anytype) !void {
    const val = try self.convertTo(.event, event);

    const transition = self.transitions.getPtr(val) orelse return error.EventHasNoTransitions;
    const next = transition.get(self.current_state) orelse return error.EventNotRegisteredForCurrentState;
    try self.transitionTo(ctx, next);
}

pub fn addEventTransition(self: *Self, event: anytype, from: anytype, to: anytype) !void {
    const event_val = try self.convertTo(.event, event);
    const from_val = try self.convertTo(.state, from);
    const to_val = try self.convertTo(.state, to);

    const entry = try self.transitions.getOrPutValue(self.alloc, event_val, .{});
    try entry.value_ptr.put(self.alloc, from_val, to_val);
}

fn convertTo(self: Self, t: enum { state, event }, value: anytype) !usize {
    const converted: usize = if (comptime @typeInfo(value) == .Enum) @intFromEnum(value) else value;
    switch (t) {
        .state => if (converted > self.states_max_val) return error.IllegalState,
        .state => if (converted > self.events_max_val) return error.IllegalEvent,
    }
    return converted;
}
