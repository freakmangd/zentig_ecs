const std = @import("std");
const ecs = @import("ecs.zig");
const ps = @import("packed_sparse.zig");
const util = @import("util.zig");
const TypeMap = @import("type_map.zig");
const print = std.debug.print;
const Allocator = std.mem.Allocator;

pub const Error = ps.Error || Allocator.Error;

const null_bit = 1 << (@typeInfo(usize).Int.bits - 1);

pub fn ComponentArray(comptime max_ents: usize) type {
    return struct {
        const Self = @This();

        fba: std.heap.FixedBufferAllocator,
        fba_buf: []u8,
        alloc: std.mem.Allocator,

        component_utp: TypeMap.UniqueTypePtr,

        len: usize = 0,
        components_data: std.ArrayListUnmanaged(u8),
        id_lookup: ps.PackedSparse(usize, max_ents),
        entry_size: usize,

        pub fn init(fba_buf: []u8, comptime T: type) !Self {
            const T_size = @sizeOf(T);

            var fba = std.heap.FixedBufferAllocator.init(fba_buf);

            var self = Self{
                .fba = fba,
                .fba_buf = fba_buf,
                .alloc = fba.allocator(),
                .component_utp = TypeMap.uniqueTypePtr(T),
                .components_data = try std.ArrayListUnmanaged(u8).initCapacity(fba.allocator(), fba_buf.len),
                .id_lookup = ps.PackedSparse(ecs.Entity, max_ents).init(),
                .entry_size = @intCast(usize, T_size),
            };

            for (&self.id_lookup.sparse_list) |*sa| {
                sa.* = null_bit;
            }

            return self;
        }

        pub fn deinit(self: *Self, world: anytype, comptime T: type) []u8 {
            if (comptime @hasDecl(T, "onDestroy")) deinit_items(self, world, T);
            return self.fba_buf;
        }

        fn deinit_items(self: *Self, world: anytype, comptime T: type) void {
            const member_fn_type = comptime util.isMemberFn(T, T.onDestroy);
            const args = world.initArgsForSystem(@TypeOf(T.onDestroy), if (member_fn_type != .non_member) .member_fn else .static_fn) catch {
                @panic("Failed to get args for deinit system for type `" ++ @typeName(T) ++ "`.");
            };

            if (comptime @sizeOf(T) > 0) {
                var comp_iter = self.iterator();
                while (comp_iter.nextAs(T)) |comp| @call(.auto, T.onDestroy, blk: {
                    break :blk if (comptime member_fn_type != .non_member) .{if (member_fn_type == .by_value) comp.* else comp} ++ args else args;
                });
            } else {
                for (0..self.len) |_| @call(.auto, T.onDestroy, blk: {
                    break :blk if (comptime member_fn_type != .non_member) .{T{}} ++ args else args;
                });
            }
        }

        pub fn assign(self: *Self, ent: ecs.Entity, entry: anytype) Error!void {
            if (TypeMap.uniqueTypePtr(@TypeOf(entry)) != self.component_utp) std.debug.panic("Incorrect type.", .{});
            try self.appendBytes(ent, &std.mem.toBytes(entry));
        }

        pub fn assignData(self: *Self, ent: ecs.Entity, data: *const anyopaque) Error!void {
            try self.appendBytes(ent, @ptrCast([*]const u8, data)[0..self.entry_size]);
        }

        inline fn appendBytes(self: *Self, ent: ecs.Entity, bytes: []const u8) Error!void {
            try self.id_lookup.set(ent, self.len);
            try self.components_data.appendSlice(self.alloc, bytes);
            self.len += 1;
        }

        pub fn swapRemove(self: *Self, ent: ecs.Entity) void {
            // triple swap remove time!
            // need to replace last index in packed array's result in sparse array to reflect changes in component array.
            //
            // -(X)> arrows have a number correlating with the line of code that preforms that action.
            // key: (p)acked | (s)parce | (c)omponents

            //                              packed:   sparce:    components:
            //  this will be replaced by -> [0-(1)>2] [0-(4)>?]  [X-(2)>X] <- this will be replaced by
            //                     this. -> [2-(1)> ] [ ]        [X-(2)> ] <- this.
            //                                        [1-(3)>0] <- so we need to update sparse array to reflect that

            const comp_index = self.id_lookup.lookup(ent); // looks into sparse array, gives 0 in example, so we remove 0 in comp array

            if (comp_index & null_bit != 0) return;

            self.id_lookup.remove(ent); // (1) removes index 0 of packed array in example, filled by last entry in packed array

            for (0..self.entry_size) |i| {
                _ = self.components_data.swapRemove(comp_index + (self.entry_size - i - 1)); // (2) removes 0 in comp array in example
            }

            if (self.id_lookup.written_indexes.len != 0) {
                const last_valid_index = self.id_lookup.written_indexes.get(self.id_lookup.written_indexes.len - 1); // get last entry in packed array
                self.id_lookup.remove(last_valid_index); // (1) remove to prepare for change in (3)
                self.id_lookup.set(last_valid_index, comp_index) catch unreachable; // (3) update sparse array so that packed array's entry points to the right component
            }

            // (4) "null" elements have their most significant bit set
            self.id_lookup.sparse_list[ent] |= null_bit;

            self.len -= 1;
        }

        pub fn get(self: *const Self, ent: ecs.Entity) ?*anyopaque {
            const index = self.id_lookup.lookup(ent);
            if (index == std.math.maxInt(usize)) return null;
            return self.components_data.items.ptr + (index * self.entry_size);
        }

        pub fn getAs(self: *const Self, comptime T: type, ent: ecs.Entity) ?*T {
            if (TypeMap.uniqueTypePtr(T) != self.component_utp) std.debug.panic("Incorrect type.", .{});
            var g = self.get(ent) orelse return null;
            return cast(T, g);
        }

        pub fn contains(self: *const Self, ent: ecs.Entity) bool {
            return self.id_lookup.sparse_list[ent] & null_bit == 0;
        }

        inline fn cast(comptime T: type, data: *anyopaque) *T {
            if (@alignOf(T) == 0) return @ptrCast(*T, data);
            return @ptrCast(*T, @alignCast(@alignOf(T), data));
        }

        const CompIter = struct {
            buffer: []u8,
            entry_size: usize,
            index: usize = 0,

            pub fn next(self: *CompIter) ?*anyopaque {
                if (self.index >= self.buffer.len / self.entry_size) return null;
                self.index += 1;
                return self.buffer.ptr + (self.index - 1) * self.entry_size;
            }

            pub fn nextAs(self: *CompIter, comptime T: type) ?*T {
                var n = self.next() orelse return null;
                return cast(T, n);
            }
        };

        pub fn iterator(self: *Self) CompIter {
            return .{
                .buffer = self.components_data.items,
                .entry_size = self.entry_size,
            };
        }
    };
}

const Data = struct {
    lmao: u32,
    uhh: bool = false,
};

test "simple test" {
    var arr = try ComponentArray(10).init(std.testing.allocator, u16);
    defer arr.deinit();

    try arr.assign(0, @as(u16, 10));
    try arr.assign(1, @as(u16, 10));
    try arr.assign(2, @as(u16, 10));
    try arr.assignData(3, &@as(u16, 10));

    arr.swapRemove(0);

    var arr_iter = arr.iterator();
    while (arr_iter.nextAs(u16)) |val| {
        try std.testing.expectEqual(@as(u16, 10), val.*);
    }

    try std.testing.expectEqual(@as(u16, 10), arr.getAs(u16, 2).?.*);
}

test "data" {
    var arr = try ComponentArray(10).init(std.testing.allocator, Data);
    defer arr.deinit();

    try arr.assign(2, Data{ .lmao = 100_000 });
    try arr.assignData(5, &Data{ .lmao = 20_000 });

    try std.testing.expectEqual(@as(u32, 100_000), arr.getAs(Data, 2).?.lmao);
    try std.testing.expectEqual(@as(u32, 20_000), arr.getAs(Data, 5).?.lmao);

    try std.testing.expect(arr.contains(2));
    arr.swapRemove(2);
    try std.testing.expect(!arr.contains(2));

    try std.testing.expectEqual(@as(u32, 20_000), arr.getAs(Data, 5).?.lmao);

    arr.swapRemove(5);

    try std.testing.expectEqual(@as(usize, 0), arr.len);
}
