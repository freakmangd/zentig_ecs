const std = @import("std");

/// A structure for making lists at comptime.
/// To be only used at comptime.
pub fn ComptimeList(comptime T: type) type {
    return struct {
        const Self = @This();

        items: []const T = &.{},

        pub fn fromSlice(comptime items: []const T) Self {
            return .{ .items = items };
        }

        pub fn append(comptime self: *Self, comptime t: T) void {
            self.items = self.items ++ .{t};
        }

        pub fn appendSlice(comptime self: *Self, comptime slice: []const T) void {
            self.items = self.items ++ slice;
        }

        pub fn insert(comptime self: *Self, comptime index: usize, comptime t: T) void {
            var items: [self.items.len + 1]T = undefined;

            @memcpy(items[0..index], self.items[0..index]);
            @memcpy(items[index + 1 ..], self.items[index..]);
            items[index] = t;

            self.items = &items;
        }

        pub fn set(comptime self: *Self, comptime index: usize, comptime t: T) void {
            var items: [self.items.len]T = undefined;
            @memcpy(&items, self.items);

            items[index] = t;

            self.items = &items;
        }

        pub fn dereference(comptime self: Self, comptime len: usize) [len]T {
            return self.items[0..].*;
        }
    };
}

test ComptimeList {
    {
        const list = comptime blk: {
            var list = ComptimeList(usize).fromSlice(&.{ 1, 2, 3 });
            list.append(4);
            list.appendSlice(&.{ 5, 6, 7 });
            list.set(0, 8);
            list.insert(1, 9);
            break :blk list.dereference(list.items.len);
        };
        try std.testing.expectEqualSlices(usize, &.{ 8, 9, 2, 3, 4, 5, 6, 7 }, &list);
    }

    {
        const list = comptime blk: {
            var list = ComptimeList(type).fromSlice(&.{ u1, u2, u3 });
            list.append(u4);
            list.appendSlice(&.{ u5, u6, u7 });
            list.set(0, u8);
            list.insert(1, u9);
            break :blk list;
        };
        inline for (list.items, &[_]type{ u8, u9, u2, u3, u4, u5, u6, u7 }) |Actual, Expected| {
            if (Actual != Expected) return error.TestExpectedEqual;
        }
    }
}
