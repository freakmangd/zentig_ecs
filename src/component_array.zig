const std = @import("std");
const builtin = @import("builtin");
const ztg = @import("init.zig");
const util = @import("util.zig");
const ByteArray = @import("etc/byte_array.zig");
const Allocator = std.mem.Allocator;

/// Stores component data as bytes on the heap
pub fn ComponentArray(comptime Index: type) type {
    return struct {
        const Self = @This();
        const debug_info = builtin.mode == .Debug and !builtin.is_test;

        component_id: if (debug_info) util.CompId else void,
        component_name: if (debug_info) []const u8 else void,

        components_data: ByteArray,
        entities: std.ArrayListUnmanaged(ztg.Entity) = .{},
        ent_to_comp_idx: std.AutoHashMapUnmanaged(ztg.Entity, Index) = .{},

        pub fn init(comptime T: type) Self {
            return .{
                .component_id = if (comptime debug_info) util.compId(T) else {},
                .component_name = if (comptime debug_info) @typeName(T) else {},
                .components_data = ByteArray.init(T),
            };
        }

        pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
            self.components_data.deinit(alloc);
            self.entities.deinit(alloc);
            self.ent_to_comp_idx.deinit(alloc);
        }

        pub fn assign(self: *Self, alloc: std.mem.Allocator, ent: ztg.Entity, entry: anytype) !*anyopaque {
            self.assertType(@TypeOf(entry));
            return self.appendBytes(alloc, ent, std.mem.asBytes(&entry));
        }

        pub fn assignData(self: *Self, alloc: std.mem.Allocator, ent: ztg.Entity, data: *const anyopaque) !*anyopaque {
            return self.appendBytes(alloc, ent, data);
        }

        fn appendBytes(self: *Self, alloc: std.mem.Allocator, ent: ztg.Entity, bytes_start: *const anyopaque) !*anyopaque {
            try self.entities.append(alloc, ent);
            try self.ent_to_comp_idx.put(alloc, ent, @intCast(self.components_data.len));
            return self.components_data.appendPtr(alloc, bytes_start);
        }

        pub fn willResize(self: *const Self) bool {
            return self.entities.items.len >= self.components_data.getCapacity();
        }

        pub fn swapRemove(self: *Self, ent: ztg.Entity) void {
            const last_ent = self.entities.items[self.entities.items.len - 1];

            // here because the entities array mirrors the components array,
            // (whenever an entity is added at an index, a component is added at the same index in the component array)
            // wherever the entity is removed at is where the component data will be swapRemove'ed into...
            const index_of_rem = self.indexOfEntityInEnts(ent);
            _ = self.entities.swapRemove(index_of_rem);

            self.components_data.swapRemove(index_of_rem);
            _ = self.ent_to_comp_idx.remove(ent);

            // were removing the end of the array, so no need to reassign the last_ent's value
            if (index_of_rem == self.entities.items.len) return;

            // ... so we can assign that here
            self.ent_to_comp_idx.putAssumeCapacity(last_ent, @intCast(index_of_rem));
        }

        fn indexOfEntityInEnts(self: *const Self, ent: ztg.Entity) usize {
            // since entities and components are always added in pairs,
            // ent_to_comp_idx also functions as an ent_to_ent_idx
            return self.ent_to_comp_idx.get(ent) orelse std.debug.panic("Could not find entity {} in entities.", .{ent});
        }

        pub fn get(self: *const Self, ent: ztg.Entity) ?*anyopaque {
            const index = self.ent_to_comp_idx.get(ent) orelse return null;
            return self.components_data.get(index);
        }

        pub fn getAs(self: *const Self, comptime T: type, ent: ztg.Entity) ?*T {
            self.assertType(T);

            const g = self.get(ent) orelse return null;
            return cast(T, g);
        }

        pub inline fn contains(self: *const Self, ent: ztg.Entity) bool {
            return self.ent_to_comp_idx.contains(ent);
        }

        pub inline fn len(self: *const Self) usize {
            return self.entities.items.len;
        }

        inline fn cast(comptime T: type, data: *anyopaque) *T {
            if (comptime @alignOf(T) == 0) return @ptrCast(data);
            return @ptrCast(@alignCast(data));
        }

        pub fn iterator(self: *Self) ByteArray.ByteIterator {
            return self.components_data.iterator();
        }

        fn assertType(self: Self, comptime T: type) void {
            if (comptime builtin.mode != .Debug) return;

            if (comptime debug_info) {
                if (util.compId(T) != self.component_id)
                    std.debug.panic("Incorrect type. Expected Type: {s} (ID {}), found Type {s} (ID: {}).", .{
                        self.component_name,
                        self.component_id,
                        @typeName(T),
                        util.compId(T),
                    });
            }
        }
    };
}

fn initForTests(comptime Index: type, comptime T: type) ComponentArray(Index) {
    return ComponentArray(Index).init(T);
}

const Data = struct {
    val: u32,
    uhh: bool = false,
    xd: f32 = 100.0,
    ugh: enum { ok, bad } = .ok,
};

test "simple test" {
    var arr = initForTests(usize, u32);
    defer arr.deinit(std.testing.allocator);

    _ = try arr.assign(std.testing.allocator, @enumFromInt(0), @as(u32, 1));
    _ = try arr.assign(std.testing.allocator, @enumFromInt(1), @as(u32, 1));
    _ = try arr.assign(std.testing.allocator, @enumFromInt(2), @as(u32, 1));

    _ = arr.swapRemove(@enumFromInt(2));

    for (arr.components_data.slicedAs(u32)) |val| {
        try std.testing.expectEqual(@as(u32, 1), val);
    }
}

test "data" {
    var arr = initForTests(usize, Data);
    defer arr.deinit(std.testing.allocator);

    const two: ztg.Entity = @enumFromInt(2);
    const five: ztg.Entity = @enumFromInt(5);

    _ = try arr.assign(std.testing.allocator, two, Data{ .val = 100_000 });
    _ = try arr.assignData(std.testing.allocator, five, &Data{ .val = 20_000 });

    try std.testing.expectEqual(100_000, arr.getAs(Data, two).?.val);
    try std.testing.expectEqual(20_000, arr.getAs(Data, five).?.val);

    try std.testing.expect(arr.contains(two));
    arr.swapRemove(two);
    try std.testing.expect(!arr.contains(two));

    try std.testing.expectEqual(100, arr.getAs(Data, five).?.xd);

    arr.swapRemove(five);

    try std.testing.expectEqual(0, arr.len());
}

test "remove" {
    var arr = initForTests(usize, usize);
    defer arr.deinit(std.testing.allocator);

    const one: ztg.Entity = @enumFromInt(1);
    const two: ztg.Entity = @enumFromInt(2);

    _ = try arr.assign(std.testing.allocator, one, @as(usize, 100));
    _ = try arr.assign(std.testing.allocator, two, @as(usize, 200));

    arr.swapRemove(two);

    try std.testing.expectEqual(100, arr.getAs(usize, one).?.*);
    try std.testing.expectEqual(1, arr.len());
}

test "capacity" {
    var arr = initForTests(usize, usize);
    defer arr.deinit(std.testing.allocator);

    const zero: ztg.Entity = @enumFromInt(0);
    const one: ztg.Entity = @enumFromInt(1);

    _ = try arr.assign(std.testing.allocator, zero, @as(usize, 10));
    _ = try arr.assign(std.testing.allocator, one, @as(usize, 20));
}
