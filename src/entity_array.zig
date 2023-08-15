const std = @import("std");
const ztg = @import("init.zig");

pub fn EntityArray(comptime ComponentMask: type, comptime size: usize) type {
    return struct {
        const Self = @This();

        const IndexTagType = std.math.IntFittingRange(0, size + 1);
        pub const Index = enum(IndexTagType) {
            NULL = std.math.maxInt(IndexTagType),
            _,
        };

        ents: [size]Index = undefined,
        idx_lookup: [size]Index = undefined,
        parent_lookup: [size]Index = undefined,
        comp_masks: [size]ComponentMask = undefined,

        len: usize = 0,

        pub fn init() Self {
            var self = Self{};
            @memset(&self.ents, Index.NULL);
            @memset(&self.idx_lookup, Index.NULL);
            @memset(&self.parent_lookup, Index.NULL);
            return self;
        }

        pub fn getIndexOf(self: *const Self, ent: ztg.Entity) ?usize {
            if (self.idx_lookup[ent] == Index.NULL) return null;
            return @intFromEnum(self.idx_lookup[ent]);
        }

        pub fn getEntityAt(self: *const Self, idx: usize) ?ztg.Entity {
            if (self.ents[idx] == Index.NULL) return null;
            return @intFromEnum(self.ents[idx]);
        }

        pub fn set(self: *Self, idx: usize, ent: ztg.Entity, comp_mask: ComponentMask) void {
            self.ents[idx] = @enumFromInt(ent);
            self.idx_lookup[ent] = @enumFromInt(idx);
            self.comp_masks[ent] = comp_mask;
        }

        pub fn setParent(self: *Self, ent: ztg.Entity, parent: ?ztg.Entity) !void {
            if (!self.hasEntity(ent)) return error.EntityDoesntExist;
            if (parent) |p| if (!self.hasEntity(p)) return error.ParentDoesntExist;
            self.parent_lookup[ent] = if (parent) |p| @enumFromInt(p) else Index.NULL;
        }

        pub fn getParent(self: *const Self, ent: ztg.Entity) !?ztg.Entity {
            if (!self.hasEntity(ent)) return error.EntityDoesntExist;
            if (self.parent_lookup[ent] != Index.NULL) return @intFromEnum(self.parent_lookup[ent]);
            return null;
        }

        /// Slow function, it's a lot easier to go up than go down
        pub fn getChildren(self: *const Self, alloc: std.mem.Allocator, ent: ztg.Entity) ![]const ztg.Entity {
            if (!self.hasEntity(ent)) return error.EntityDoesntExist;
            var children = std.ArrayList(ztg.Entity).init(alloc);
            for (self.parent_lookup, 0..) |pl, ch| if (@intFromEnum(pl) == ent) try children.append(ch);
            return children.toOwnedSlice();
        }

        pub fn append(self: *Self, ent: ztg.Entity) void {
            self.set(self.len, ent, ComponentMask.initEmpty());
            self.len += 1;
        }

        pub fn appendSlice(self: *Self, ents: []const ztg.Entity) void {
            for (ents) |ent| self.append(ent);
        }

        pub fn swapRemoveEnt(self: *Self, ent: ztg.Entity) bool {
            if (self.len == 0) return false;
            const idx = self.getIndexOf(ent) orelse return false;

            if (idx != self.len - 1) {
                const rep = self.getEntityAt(self.len - 1).?;
                self.set(idx, rep, self.comp_masks[rep]);
            } else {
                self.ents[idx] = Index.NULL;
            }

            self.len -= 1;
            self.idx_lookup[ent] = Index.NULL;
            self.comp_masks[ent] = ComponentMask.initEmpty();
            return true;
        }

        pub fn hasEntity(self: *const Self, ent: ztg.Entity) bool {
            return self.getIndexOf(ent) != null;
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
    const CompMask = std.bit_set.StaticBitSet(0);
    var arr = EntityArray(CompMask, 10).init();

    arr.append(0);
    arr.append(1);
    arr.append(2);

    try std.testing.expect(arr.hasEntity(0));
    try std.testing.expectEqual(@as(usize, 3), arr.constSlice().len);

    _ = arr.swapRemoveEnt(1);

    try std.testing.expect(!arr.hasEntity(1));
    try std.testing.expectEqual(@as(usize, 2), arr.constSlice().len);
    try std.testing.expectEqualSlices(EntityArray(CompMask, 10).Index, &.{
        @as(EntityArray(CompMask, 10).Index, @enumFromInt(0)),
        @as(EntityArray(CompMask, 10).Index, @enumFromInt(2)),
    }, arr.constSlice());

    _ = arr.swapRemoveEnt(2);

    try std.testing.expect(!arr.hasEntity(2));
}
