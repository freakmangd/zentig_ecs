const std = @import("std");
const ztg = @import("init.zig");
const util = @import("util.zig");

pub fn EventPools(comptime event_types: anytype) type {
    const Inner = blk: {
        var tb = ztg.meta.TypeBuilder{ .is_tuple = true };
        inline for (event_types) |T| {
            tb.appendTupleField(std.ArrayListUnmanaged(T), null);
        }
        break :blk tb.Build();
    };

    return struct {
        const Self = @This();

        inner: Inner = blk: {
            var inner: Inner = undefined;
            for (std.meta.fields(Inner), event_types) |field, T| {
                @field(inner, field.name) = std.ArrayListUnmanaged(T){};
            }
            break :blk inner;
        },

        pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
            inline for (std.meta.fields(Inner)) |field| {
                @field(self.inner, field.name).deinit(alloc);
            }
        }

        pub fn getPtr(self: *Self, comptime EventType: type) *std.ArrayListUnmanaged(EventType) {
            const field_name = comptime std.fmt.comptimePrint("{}", .{util.indexOfType(event_types, EventType) orelse util.compileError("Event `{s}` was not registered.", .{@typeName(EventType)})});
            return &@field(self.inner, field_name);
        }

        pub fn clear(self: *Self) void {
            inline for (std.meta.fields(Inner)) |field| {
                @field(self.inner, field.name).clearRetainingCapacity();
            }
        }
    };
}
