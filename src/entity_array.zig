const std = @import("std");
const ecs = @import("ecs.zig");

pub fn EntityArray(comptime size: usize) type {
    return struct {
        const Self = @This();

        ents: [size]ecs.Entity = undefined,
        idx_lookup: [size]u32,
        len: u32 = 0,

        pub fn init() Self {
            var self = Self{ .idx_lookup = undefined };

            for (&self.idx_lookup) |*d| {
                d.* = std.math.maxInt(u32);
            }

            return self;
        }

        pub fn getIndexOf(self: *const Self, ent: ecs.Entity) u32 {
            return self.idx_lookup[ent];
        }

        pub fn getEntityAt(self: *const Self, idx: usize) ecs.Entity {
            return self.ents[idx];
        }

        pub fn set(self: *Self, idx: u32, ent: ecs.Entity) void {
            self.ents[idx] = ent;
            self.idx_lookup[ent] = idx;
        }

        pub fn append(self: *Self, ent: ecs.Entity) void {
            self.set(self.len, ent);
            self.len += 1;
        }

        pub fn swapRemoveEnt(self: *Self, ent: ecs.Entity) bool {
            if (self.len == 0) return false;
            if (!self.hasEntity(ent)) return false;
            const idx = self.getIndexOf(ent);

            if (idx != self.len - 1) {
                self.set(idx, self.getEntityAt(self.len - 1));
            } else {
                self.ents[idx] = std.math.maxInt(u32);
            }

            self.len -= 1;
            self.idx_lookup[ent] = std.math.maxInt(u32);
            return true;
        }

        pub fn hasEntity(self: *Self, ent: ecs.Entity) bool {
            return self.getIndexOf(ent) != std.math.maxInt(u32);
        }

        pub fn hasIndex(self: *Self, idx: usize) bool {
            return idx < self.len;
        }

        pub fn reset(self: *Self) void {
            self.len = 0;
        }

        pub fn constSlice(self: *const Self) []const ecs.Entity {
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

    arr.swapRemoveEnt(1);

    try std.testing.expect(!arr.hasEntity(1));
    try std.testing.expectEqual(@as(usize, 2), arr.constSlice().len);
    try std.testing.expectEqualSlices(ecs.Entity, &.{ 0, 2 }, arr.constSlice());

    arr.swapRemoveEnt(2);

    try std.testing.expect(!arr.hasEntity(2));
}
