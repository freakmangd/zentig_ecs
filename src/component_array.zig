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
        component_name: []const u8,

        components_data: ByteArray = undefined,
        entities: std.ArrayListUnmanaged(ecs.Entity) = undefined,
        ent_to_comp_idx: []Index = undefined,

        pub fn init(alloc: Allocator, comptime T: type) !Self {
            //const max_cap = comptime blk: {
            //    if (std.meta.trait.isContainer(T) and @hasDecl(T, "max_entities")) break :blk T.max_entities;
            //    break :blk max_ents;
            //};
            //_ = max_cap;

            var self = Self{
                .alloc = alloc,
                .component_utp = TypeMap.uniqueTypePtr(T),
                .component_name = @typeName(T),
            };

            self.components_data = ByteArray.init(T);
            errdefer self.components_data.deinit(alloc);

            self.entities = std.ArrayListUnmanaged(ecs.Entity){};
            errdefer self.entities.deinit(alloc);

            self.ent_to_comp_idx = try alloc.alloc(Index, max_ents);

            for (self.ent_to_comp_idx) |*etc| {
                etc.* = null_bit;
            }

            return self;
        }

        fn initForTests(comptime T: type) !Self {
            return init(std.testing.allocator, T);
        }

        pub fn deinit(self: *Self) void {
            self.components_data.deinit(self.alloc);
            self.entities.deinit(self.alloc);
            self.alloc.free(self.ent_to_comp_idx);
        }

        pub fn assign(self: *Self, ent: ecs.Entity, entry: anytype) !void {
            if (TypeMap.uniqueTypePtr(@TypeOf(entry)) != self.component_utp) std.debug.panic("Incorrect type. Expected UTP {}, found UTP {} (Type: {s}).", .{
                self.component_utp,
                TypeMap.uniqueTypePtr(@TypeOf(entry)),
                @typeName(@TypeOf(entry)),
            });
            try self.appendBytes(ent, std.mem.asBytes(&entry));
        }

        pub fn assignData(self: *Self, ent: ecs.Entity, data: *const anyopaque) !void {
            try self.appendBytes(ent, data);
        }

        fn appendBytes(self: *Self, ent: ecs.Entity, bytes_start: *const anyopaque) !void {
            try self.entities.append(self.alloc, ent);
            self.ent_to_comp_idx[ent] = @intCast(Index, self.components_data.len());
            try self.components_data.appendPtr(self.alloc, bytes_start);
        }

        pub fn reassign(self: *Self, old: ecs.Entity, new: ecs.Entity) void {
            const old_ent_idx = self.indexOfEntityInEnts(old);
            self.entities.items[old_ent_idx] = new;
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

const CAT = ComponentArray(usize, 10);

const Data = struct {
    lmao: u32,
    uhh: bool = false,
    xd: f32 = 100.0,
    ugh: enum { ok, bad } = .ok,
};

test "simple test" {
    var arr = try CAT.initForTests(u32);
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
    var arr = try CAT.initForTests(Data);
    defer arr.deinit();

    try arr.assign(2, Data{ .lmao = 100_000 });
    try arr.assignData(5, &Data{ .lmao = 20_000 });

    try std.testing.expectEqual(@as(u32, 100_000), arr.getAs(Data, 2).?.lmao);
    try std.testing.expectEqual(@as(u32, 20_000), arr.getAs(Data, 5).?.lmao);

    try std.testing.expect(arr.contains(2));
    arr.swapRemove(2);
    try std.testing.expect(!arr.contains(2));

    try std.testing.expectEqual(@as(f32, 100.0), arr.getAs(Data, 5).?.xd);

    arr.swapRemove(5);

    try std.testing.expectEqual(@as(usize, 0), arr.len());
}

test "remove" {
    var arr = try CAT.initForTests(usize);
    defer arr.deinit();

    try arr.assign(1, @as(usize, 100));
    try arr.assign(2, @as(usize, 200));

    arr.swapRemove(2);

    try std.testing.expectEqual(@as(usize, 100), arr.getAs(usize, 1).?.*);
    try std.testing.expectEqual(@as(usize, 1), arr.len());
}

test "reassign" {
    var arr = try CAT.initForTests(usize);
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
    var arr = try ComponentArray(usize, 2).initForTests(usize);
    defer arr.deinit();

    try arr.assign(0, @as(usize, 10));
    try arr.assign(1, @as(usize, 20));
}
