const std = @import("std");
const meta = @import("../meta.zig");

const Self = @This();

types: []const type = &.{},

pub fn append(comptime self: *Self, comptime T: type) void {
    self.types = self.types ++ &[_]type{T};
}

pub fn appendSlice(comptime self: *Self, comptime types: []const type) void {
    self.types = self.types ++ types;
}

pub fn has(comptime self: Self, comptime T: type) bool {
    for (self.types) |t| {
        @setEvalBranchQuota(20_000);
        if (t == T) return true;
    }
    return false;
}

pub fn indexOf(comptime self: Self, comptime T: type) ?usize {
    for (self.types, 0..) |t, i| {
        @setEvalBranchQuota(20_000);
        if (t == T) return i;
    }
    return null;
}

pub fn fromUtp(comptime self: Self, utp: meta.UniqueTypePtr) ?usize {
    inline for (self.types, 0..) |t, i| {
        @setEvalBranchQuota(20_000);
        if (meta.uniqueTypePtr(t) == utp) return i;
    }
    return null;
}

pub fn nameFromUtp(comptime self: Self, utp: meta.UniqueTypePtr) []const u8 {
    inline for (self.types) |t| {
        @setEvalBranchQuota(20_000);
        if (meta.uniqueTypePtr(t) == utp) return @typeName(t);
    }
    return "Error::NonRegisteredType";
}

test {
    const typemap = comptime blk: {
        var tm = Self{};
        tm.append(u32);
        break :blk tm;
    };

    try std.testing.expectEqual(0, comptime typemap.indexOf(u32).?);
    try std.testing.expectEqual(0, comptime typemap.fromUtp(meta.uniqueTypePtr(u32)).?);
}
