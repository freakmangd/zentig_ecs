const std = @import("std");
const builtin = @import("builtin");
const Self = @This();

start: if (builtin.mode == .Debug) i64 else void,
time: if (builtin.mode == .Debug) i64 else void,

pub fn init() Self {
    if (builtin.mode != .Debug) return .{ .start = {}, .time = {} };
    return .{ .start = std.time.milliTimestamp(), .time = 0 };
}

pub fn readTime(self: *Self, title: []const u8) void {
    if (builtin.mode != .Debug) return;
    self.time = std.time.milliTimestamp() - self.start;
    std.debug.print("{s} :: ms: {}\n", .{ title, self.time });
}
