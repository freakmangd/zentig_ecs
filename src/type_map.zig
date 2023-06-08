const std = @import("std");
const Self = @This();

types: []const type = &.{},

pub fn append(comptime self: *Self, comptime T: type) void {
    self.types = self.types ++ &[_]type{T};
}

pub fn has(comptime self: Self, comptime T: type) bool {
    for (self.types) |t| {
        if (t == T) return true;
    }
    return false;
}

pub fn indexOf(comptime self: Self, comptime T: type) ?usize {
    for (self.types, 0..) |t, i| {
        if (t == T) return i;
    }
    return null;
}

pub fn fromUtp(comptime self: Self, utp: UniqueTypePtr) ?usize {
    inline for (self.types, 0..) |t, i| {
        if (uniqueTypePtr(t) == utp) return i;
    }
    return null;
}

//pub const UniqueTypePtr = *const anyopaque;
//pub fn uniqueTypePtr(comptime T: type) UniqueTypePtr {
//    return @typeName(T);
//}

//pub const UniqueTypePtr = u64;
//var id_counter: u64 = 0;
//pub fn uniqueTypePtr(comptime T: type) UniqueTypePtr {
//    _ = T;
//    const static = struct {
//        var id: ?u64 = null;
//    };
//    const result = static.id orelse blk: {
//        static.id = id_counter;
//        id_counter += 1;
//        break :blk static.id.?;
//    };
//    return result;
//}

pub const UniqueTypePtr = *const opaque {};
pub const uniqueTypePtr = struct {
    inline fn typeId(comptime T: type) UniqueTypePtr {
        comptime return typeIdImpl(T);
    }
    inline fn typeIdImpl(comptime T: type) UniqueTypePtr {
        _ = T;
        const gen = struct {
            var id: u1 = undefined;
        };
        return @ptrCast(UniqueTypePtr, &gen.id);
    }
}.typeId;

test "ok" {
    const typemap = comptime blk: {
        var tm = Self{};
        tm.append(u32);
        break :blk tm;
    };

    try std.testing.expectEqual(0, comptime typemap.indexOf(u32).?);
    try std.testing.expectEqual(0, comptime typemap.fromUtp(uniqueTypePtr(u32)).?);
}
