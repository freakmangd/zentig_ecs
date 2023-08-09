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

pub fn nameFromIndex(comptime self: Self, idx: usize) []const u8 {
    inline for (self.types, 0..) |T, i| {
        @setEvalBranchQuota(20_000);
        if (idx == i) return @typeName(T);
    }
    return "ERROR";
}

pub fn hasUtp(comptime self: Self, utp: meta.Utp) bool {
    inline for (self.types) |T| {
        @setEvalBranchQuota(20_000);
        if (meta.utpOf(T) == utp) return true;
    }
    return false;
}

test {
    const typemap = comptime blk: {
        var tm = Self{};
        tm.append(u32);
        break :blk tm;
    };

    try std.testing.expectEqual(0, comptime typemap.indexOf(u32).?);
}
