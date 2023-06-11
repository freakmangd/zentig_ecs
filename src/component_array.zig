const std = @import("std");
const ecs = @import("ecs.zig");
const ByteArray = @import("byte_array.zig").ByteArray;
const util = @import("util.zig");
const TypeMap = @import("type_map.zig");
const print = std.debug.print;
const Allocator = std.mem.Allocator;

pub const Error = Allocator.Error || error{Overflow};

pub fn ComponentArray(comptime Index: type, comptime max_ents: usize) type {
    const null_bit = 1 << (@typeInfo(Index).Int.bits - 1);

    return struct {
        const Self = @This();

        alloc: std.mem.Allocator,

        component_utp: TypeMap.UniqueTypePtr,

        components_data: ByteArray,
        entities: std.ArrayListUnmanaged(ecs.Entity),
        ent_to_comp_idx: []Index,

        pub fn init(alloc: Allocator, comptime T: type, max_cap: usize) !Self {
            var self = Self{
                .alloc = alloc,
                .component_utp = TypeMap.uniqueTypePtr(T),
                .components_data = try ByteArray.initCapacity(T, alloc, max_cap),
                .entities = try std.ArrayListUnmanaged(ecs.Entity).initCapacity(alloc, max_cap),
                .ent_to_comp_idx = try alloc.alloc(Index, max_ents),
            };

            for (self.ent_to_comp_idx) |*etc| {
                etc.* = null_bit;
            }

            return self;
        }

        pub fn deinit(self: *Self) void {
            self.components_data.deinit(self.alloc);
            self.entities.deinit(self.alloc);
            self.alloc.free(self.ent_to_comp_idx);
        }

        pub fn assign(self: *Self, ent: ecs.Entity, entry: anytype) void {
            if (TypeMap.uniqueTypePtr(@TypeOf(entry)) != self.component_utp) std.debug.panic("Incorrect type.", .{});
            self.appendBytes(ent, std.mem.asBytes(&entry));
        }

        pub fn assignData(self: *Self, ent: ecs.Entity, data: *const anyopaque) void {
            self.appendBytes(ent, data);
        }

        inline fn appendBytes(self: *Self, ent: ecs.Entity, bytes_start: *const anyopaque) void {
            if (self.entities.items.len == self.entities.capacity) std.debug.panic("Hit max capacity for component {*}!", .{self.component_utp});
            self.entities.appendAssumeCapacity(ent);
            self.ent_to_comp_idx[ent] = @intCast(Index, self.components_data.len());
            self.components_data.appendPtrAssumeCapacity(bytes_start);
        }

        pub fn reassign(self: *Self, old: ecs.Entity, new: ecs.Entity) void {
            const old_ent_idx = self.indexOfEntityInEnts(old);
            _ = self.entities.swapRemove(old_ent_idx);
            self.entities.appendAssumeCapacity(new); // we just removed something from the array, no error

            self.ent_to_comp_idx[new] = self.ent_to_comp_idx[old];
            self.ent_to_comp_idx[old] |= null_bit;
        }

        pub fn swapRemove(self: *Self, ent: ecs.Entity) void {
            const last_ent = self.entities.items[self.entities.items.len - 1];

            // here because the entities array mirrors the components array,
            // (whenever an entity is added at an index, a component is added at the same index in the component array)
            // wherever the entity is removed at is where the component data will be swapRemove'ed into...
            const index_of_rem = self.indexOfEntityInEnts(ent);
            _ = self.entities.swapRemove(index_of_rem);

            self.components_data.swapRemove(self.ent_to_comp_idx[ent]);
            self.ent_to_comp_idx[ent] |= null_bit;

            // were removing the end of the array, so no need to reassign the last_ent's value
            if (index_of_rem == self.entities.items.len) return;

            // ... so we can assign that here
            self.ent_to_comp_idx[last_ent] = @intCast(Index, index_of_rem);
        }

        fn indexOfEntityInEnts(self: *const Self, ent: ecs.Entity) usize {
            // since entities and components are always added in pairs,
            // ent_to_comp_idx also functions as an ent_to_ent_idx
            const index = self.ent_to_comp_idx[ent];
            if (index & null_bit != 0) return std.debug.panic("Could not find entity {} in entities.", .{ent});
            return index;
        }

        pub fn get(self: *const Self, ent: ecs.Entity) ?*anyopaque {
            const index = self.ent_to_comp_idx[ent];
            if (index & null_bit != 0) return null;
            return self.components_data.get(index);
        }

        pub fn getAs(self: *const Self, comptime T: type, ent: ecs.Entity) ?*T {
            if (TypeMap.uniqueTypePtr(T) != self.component_utp) std.debug.panic("Incorrect type.", .{});
            var g = self.get(ent) orelse return null;
            return cast(T, g);
        }

        pub inline fn contains(self: *const Self, ent: ecs.Entity) bool {
            return self.ent_to_comp_idx[ent] & null_bit == 0;
        }

        pub inline fn len(self: *const Self) usize {
            return self.entities.items.len;
        }

        inline fn cast(comptime T: type, data: *anyopaque) *T {
            if (@alignOf(T) == 0) return @ptrCast(*T, data);
            return @ptrCast(*T, @alignCast(@alignOf(T), data));
        }

        pub inline fn iterator(self: *Self) ByteArray.ByteIterator {
            return self.components_data.iterator();
        }
    };
}

const Data = struct {
    lmao: u32,
    uhh: bool = false,
    xd: f32 = 100.0,
    ugh: enum { ok, bad } = .ok,
};

test "simple test" {
    var arr = try ComponentArray(10).init(std.testing.allocator, u32);
    defer arr.deinit();

    try arr.assign(0, @as(u32, 1));
    try arr.assign(1, @as(u32, 1));
    try arr.assign(2, @as(u32, 1));

    _ = arr.swapRemove(2);

    for (arr.components_data.slicedAs(u32)) |val| {
        try std.testing.expectEqual(@as(u32, 1), val);
    }
}

test "data" {
    var arr = try ComponentArray(10).init(std.testing.allocator, Data);
    defer arr.deinit();

    try arr.assign(2, Data{ .lmao = 100_000 });
    try arr.assignData(5, &Data{ .lmao = 20_000 });

    try std.testing.expectEqual(@as(u32, 100_000), arr.getAs(Data, 2).?.lmao);
    try std.testing.expectEqual(@as(u32, 20_000), arr.getAs(Data, 5).?.lmao);

    try std.testing.expect(arr.contains(2));
    _ = arr.swapRemove(2);
    try std.testing.expect(!arr.contains(2));

    try std.testing.expectEqual(@as(f32, 100.0), arr.getAs(Data, 5).?.xd);

    _ = arr.swapRemove(5);

    try std.testing.expectEqual(@as(usize, 0), arr.len());
}

test "remove" {
    var arr = try ComponentArray(10).init(std.testing.allocator, usize);
    defer arr.deinit();

    try arr.assign(1, @as(usize, 100));
    try arr.assign(2, @as(usize, 200));

    _ = arr.swapRemove(2);

    try std.testing.expectEqual(@as(usize, 100), arr.getAs(usize, 1).?.*);
    try std.testing.expectEqual(@as(usize, 1), arr.len());
}

test "reassign" {
    var arr = try ComponentArray(10).init(std.testing.allocator, usize);
    defer arr.deinit();

    try arr.assign(0, @as(usize, 10));
    try arr.assign(1, @as(usize, 20));

    try std.testing.expectEqual(@as(usize, 10), arr.getAs(usize, 0).?.*);
    try std.testing.expectEqual(@as(usize, 20), arr.getAs(usize, 1).?.*);

    arr.reassign(0, 2);

    try std.testing.expect(!arr.contains(0));
    try std.testing.expectEqual(@as(usize, 10), arr.getAs(usize, 2).?.*);
    try std.testing.expectEqual(@as(usize, 20), arr.getAs(usize, 1).?.*);
}

test "capacity" {
    var arr = try ComponentArray(2).init(std.testing.allocator, usize);
    defer arr.deinit();

    try arr.assign(0, @as(usize, 10));
    try arr.assign(1, @as(usize, 20));
    try std.testing.expectError(error.Overflow, arr.assign(1, @as(usize, 20)));

    _ = arr.swapRemove(0);
    try arr.assign(0, @as(usize, 20));
}
