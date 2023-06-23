const std = @import("std");
const ecs = @import("ecs.zig");

pub fn EntityArray(comptime size: usize) type {
    return struct {
        const Self = @This();

        pub const Index = ecs.util.MinEntInt(size);
        const NULL = std.math.maxInt(Index);

        ents: [size]Index = undefined,
        idx_lookup: [size]Index,
        len: Index = 0,

        pub fn init() Self {
            var self = Self{ .idx_lookup = undefined };

            for (&self.idx_lookup) |*d| {
                d.* = NULL;
            }

            return self;
        }

        pub fn getIndexOf(self: *const Self, ent: ecs.Entity) Index {
            return self.idx_lookup[ent];
        }

        pub fn getEntityAt(self: *const Self, idx: usize) ecs.Entity {
            return self.ents[idx];
        }

        pub fn set(self: *Self, idx: Index, ent: ecs.Entity) void {
            self.ents[idx] = @intCast(Index, ent);
            self.idx_lookup[ent] = idx;
        }

        pub fn append(self: *Self, ent: ecs.Entity) void {
            self.set(self.len, ent);
            self.len += 1;
        }

        pub fn appendSlice(self: *Self, ents: []const ecs.Entity) void {
            for (ents) |ent| self.append(ent);
        }

        pub fn swapRemoveEnt(self: *Self, ent: ecs.Entity) bool {
            if (self.len == 0) return false;
            if (!self.hasEntity(ent)) return false;
            const idx = self.getIndexOf(ent);

            if (idx != self.len - 1) {
                self.set(idx, self.getEntityAt(self.len - 1));
            } else {
                self.ents[idx] = NULL;
            }

            self.len -= 1;
            self.idx_lookup[ent] = NULL;
            return true;
        }

        pub fn hasEntity(self: *Self, ent: ecs.Entity) bool {
            return self.getIndexOf(ent) != NULL;
        }

        pub fn hasIndex(self: *Self, idx: usize) bool {
            return idx < self.len;
        }

        pub fn reset(self: *Self) void {
            self.len = 0;
        }

        pub fn slice(self: *Self) []Index {
            return self.ents[0..self.len];
        }

        pub fn constSlice(self: *const Self) []const Index {
            return self.ents[0..self.len];
        }
    };
}

test EntityArray {
    var arr = EntityArray(10).init();

    arr.append(0);
    arr.append(1);
    arr.append(2);

    try std.testing.expect(arr.hasEntity(0));
    try std.testing.expect(arr.hasIndex(arr.getIndexOf(0)));
    try std.testing.expectEqual(@as(usize, 3), arr.constSlice().len);

    _ = arr.swapRemoveEnt(1);

    try std.testing.expect(!arr.hasEntity(1));
    try std.testing.expectEqual(@as(usize, 2), arr.constSlice().len);
    try std.testing.expectEqualSlices(EntityArray(10).Index, &.{ 0, 2 }, arr.constSlice());

    _ = arr.swapRemoveEnt(2);

    try std.testing.expect(!arr.hasEntity(2));
}
