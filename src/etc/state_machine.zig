const std = @import("std");
const ztg = @import("../init.zig");

const Self = @This();

alloc: std.mem.Allocator,

current_state: usize,
transitions: std.AutoHashMapUnmanaged(usize, Transition) = .{},
onTransition: ?*const fn (ctx: ?*anyopaque, event: ?usize, from: usize, to: usize) anyerror!void,

states_max_val: usize,
events_max_val: usize,

const Transition = std.AutoHashMapUnmanaged(usize, usize);

pub fn init(alloc: std.mem.Allocator, comptime States: type, comptime Events: type, default_state: States, onTransition: ?*const fn (ctx: ?*anyopaque, event: ?usize, from: usize, to: usize) anyerror!void) Self {
    return .{
        .alloc = alloc,
        .current_state = @intFromEnum(default_state),
        .onTransition = onTransition,

        .states_max_val = std.meta.fields(States).len - 1,
        .events_max_val = std.meta.fields(Events).len - 1,
    };
}

pub fn deinit(self: *Self) void {
    var iter = self.transitions.valueIterator();
    while (iter.next()) |transition| {
        transition.deinit(self.alloc);
    }

    self.transitions.deinit(self.alloc);
}

pub fn readState(self: Self, comptime As: type) As {
    return @enumFromInt(self.current_state);
}

pub fn transitionTo(self: *Self, ctx: ?*anyopaque, state: anytype) !void {
    const val = try self.convertTo(.state, state);

    if (self.onTransition) |ot| try ot(ctx, null, self.current_state, val);
    self.current_state = val;
}

pub fn invoke(self: *Self, ctx: ?*anyopaque, event: anytype) !void {
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

pub fn convertTo(self: Self, comptime t: enum { state, event }, value: anytype) !usize {
    const ti = @typeInfo(@TypeOf(value));
    if (comptime !(ti == .@"enum" or ti == .int))
        @compileError(std.fmt.comptimePrint("Expected integer or enum as argument, found {s}", .{@typeName(@TypeOf(value))}));

    const converted: usize = if (comptime @typeInfo(@TypeOf(value)) == .@"enum") @intFromEnum(value) else value;
    switch (t) {
        .state => if (converted > self.states_max_val) return error.IllegalState,
        .event => if (converted > self.events_max_val) return error.IllegalEvent,
    }
    return converted;
}

test {
    const States = enum { one, two, three };
    const Events = enum { add, subtract };

    var sm = init(std.testing.allocator, States, Events, .one, null);
    defer sm.deinit();

    try sm.addEventTransition(Events.add, States.one, States.two);
    try sm.addEventTransition(Events.add, States.two, States.three);

    try sm.addEventTransition(Events.subtract, States.three, States.two);
    try sm.addEventTransition(Events.subtract, States.two, States.one);

    try sm.invoke(null, Events.add);
    try std.testing.expect(sm.readState(States) == .two);

    try sm.invoke(null, Events.add);
    try std.testing.expect(sm.readState(States) == .three);

    try std.testing.expectError(error.EventNotRegisteredForCurrentState, sm.invoke(null, Events.add));

    try sm.invoke(null, Events.subtract);
    try std.testing.expect(sm.readState(States) == .two);

    try sm.invoke(null, Events.subtract);
    try std.testing.expect(sm.readState(States) == .one);

    try std.testing.expectError(error.EventNotRegisteredForCurrentState, sm.invoke(null, Events.subtract));
}
