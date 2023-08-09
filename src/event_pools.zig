const std = @import("std");
const ztg = @import("init.zig");

pub fn EventPools(comptime event_tm: ztg.meta.TypeMap) type {
    const Inner = blk: {
        var tb = ztg.meta.TypeBuilder{ .is_tuple = true };
        inline for (event_tm.types) |T| {
            tb.appendTupleField(std.ArrayListUnmanaged(T), null);
        }
        break :blk tb.Build();
    };

    return struct {
        const Self = @This();

        inner: Inner,

        pub fn init() Self {
            var inner: Inner = undefined;
            inline for (std.meta.fields(Inner), event_tm.types) |field, T| {
                @field(inner, field.name) = std.ArrayListUnmanaged(T){};
            }
            return .{ .inner = inner };
        }

        pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
            inline for (std.meta.fields(Inner)) |field| {
                @field(self.inner, field.name).deinit(alloc);
            }
        }

        pub fn getPtr(self: *Self, comptime EventType: type) *std.ArrayListUnmanaged(EventType) {
            const field_name = comptime std.fmt.comptimePrint("{}", .{event_tm.indexOf(EventType) orelse @compileError("Event `" ++ @typeName(EventType) ++ "` was not registered.")});
            return &@field(self.inner, field_name);
        }

        pub fn clear(self: *Self) void {
            inline for (std.meta.fields(Inner)) |field| {
                @field(self.inner, field.name).clearRetainingCapacity();
            }
        }
    };
}
