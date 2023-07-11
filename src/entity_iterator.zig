//! Used for requesting a list of all entities from a world

const std = @import("std");
const ztg = @import("init.zig");

const Self = @This();

entities_start: *const anyopaque,
len: usize,
bits: u8,
index: usize = 0,

pub fn init(entities_start: *const anyopaque, len: usize, bits: u8) Self {
    return .{
        .entities_start = entities_start,
        .len = len,
        .bits = bits,
    };
}

pub fn next(self: *Self) ?ztg.Entity {
    if (self.index >= self.len) return null;
    self.index += 1;
    return @as(ztg.Entity, @bitCast((self.entities_start + (self.index * self.bits))[0..self.bits]));
}
