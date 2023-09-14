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
    };
}

test ComptimeList {
    const list = comptime blk: {
        var list = ComptimeList(usize).fromSlice(&.{ 1, 2, 3 });
        list.append(4);
        list.set(0, 5);
        list.insert(1, 6);
        break :blk list;
    };
    try std.testing.expectEqualSlices(usize, &.{ 5, 6, 2, 3, 4 }, list.items);
}
