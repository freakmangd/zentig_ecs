const std = @import("std");
const ztg = @import("init.zig");

pub fn EntityArray(comptime ComponentMask: type, comptime size: usize) type {
    return struct {
        const Self = @This();

        const IndexTagType = std.math.IntFittingRange(0, size + 1);
        pub const Index = enum(IndexTagType) {
            NULL = std.math.maxInt(IndexTagType),
            _,

            pub fn toEntity(idx: Index) ztg.Entity {
                return @enumFromInt(@intFromEnum(idx));
            }

            pub fn fromEntity(ent: ztg.Entity) Index {
                return @enumFromInt(@intFromEnum(ent));
            }
        };

        ents: [size]Index = .{Index.NULL} ** size,
        idx_lookup: [size]Index = .{Index.NULL} ** size,
        parent_lookup: [size]Index = .{Index.NULL} ** size,
        comp_masks: [size]ComponentMask = undefined,

        len: usize = 0,

        pub fn getIndexOf(self: *const Self, ent: ztg.Entity) ?usize {
            if (self.idx_lookup[ent.toInt()] == Index.NULL) return null;
            return @intFromEnum(self.idx_lookup[ent.toInt()]);
        }

        pub fn getEntityAt(self: *const Self, idx: usize) ?ztg.Entity {
            if (self.ents[idx] == Index.NULL) return null;
            return self.ents[idx].toEntity();
        }

        pub fn set(self: *Self, idx: usize, ent: ztg.Entity, comp_mask: ComponentMask) void {
            self.ents[idx] = .fromEntity(ent);
            self.idx_lookup[ent.toInt()] = @enumFromInt(idx);
            self.comp_masks[ent.toInt()] = comp_mask;
        }

        pub fn setParent(self: *Self, ent: ztg.Entity, parent: ?ztg.Entity) !void {
            if (!self.hasEntity(ent)) return error.EntityDoesntExist;
            if (parent) |p| if (!self.hasEntity(p)) return error.ParentDoesntExist;
            self.parent_lookup[ent.toInt()] = if (parent) |p| .fromEntity(p) else Index.NULL;
        }

        pub fn getParent(self: *const Self, ent: ztg.Entity) !?ztg.Entity {
            if (!self.hasEntity(ent)) return error.EntityDoesntExist;
            if (self.parent_lookup[ent.toInt()] != Index.NULL) return self.parent_lookup[ent.toInt()].toEntity();
            return null;
        }

        /// Slow function, it's a lot easier to go up than go down
        pub fn getChildren(self: *const Self, alloc: std.mem.Allocator, ent: ztg.Entity) ![]const ztg.Entity {
            if (!self.hasEntity(ent)) return error.EntityDoesntExist;
            var children = std.ArrayList(ztg.Entity).init(alloc);
            for (self.parent_lookup, 0..) |pl, ch| if (@intFromEnum(pl) == ent.toInt()) try children.append(@enumFromInt(ch));
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
                const popped = self.pop();
                self.set(idx, popped.ent, popped.mask);
            } else {
                self.ents[idx] = Index.NULL;
                self.len -= 1;
            }

            self.idx_lookup[ent.toInt()] = Index.NULL;
            self.comp_masks[ent.toInt()] = ComponentMask.initEmpty();
            return true;
        }

        pub fn pop(self: *Self) struct { ent: ztg.Entity, mask: ComponentMask } {
            const last = self.getEntityAt(self.len - 1).?;
            self.idx_lookup[last.toInt()] = Index.NULL;
            const mask = self.comp_masks[last.toInt()];
            self.comp_masks[last.toInt()] = ComponentMask.initEmpty();

            self.len -= 1;

            return .{ .ent = last, .mask = mask };
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
    var arr = EntityArray(CompMask, 10){};

    const zero: ztg.Entity = @enumFromInt(0);
    const one: ztg.Entity = @enumFromInt(1);
    const two: ztg.Entity = @enumFromInt(2);

    arr.append(zero);
    arr.append(one);
    arr.append(two);

    try std.testing.expect(arr.hasEntity(zero));
    try std.testing.expectEqual(3, arr.constSlice().len);

    _ = arr.swapRemoveEnt(one);

    try std.testing.expect(!arr.hasEntity(one));
    try std.testing.expectEqual(2, arr.constSlice().len);
    try std.testing.expectEqualSlices(EntityArray(CompMask, 10).Index, &.{
        @enumFromInt(0),
        @enumFromInt(2),
    }, arr.constSlice());

    _ = arr.swapRemoveEnt(two);

    try std.testing.expect(!arr.hasEntity(two));
}
