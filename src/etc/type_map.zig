const std = @import("std");
const ztg = @import("../init.zig");
const base = @import("../mods/base/init.zig");
const meta = @import("meta.zig");

pub fn TypeMap(comptime V: type) type {
    return struct {
        const Self = @This();

        types: []const type,
        values: []const V,

        pub const empty: Self = .{
            .types = &.{},
            .values = &.{},
        };

        pub fn dereferenceKeys(self: Self, comptime len: usize) [len]type {
            return self.types[0..].*;
        }

        pub fn dereferenceValues(self: Self, comptime len: usize) [len]V {
            return self.values[0..].*;
        }

        pub fn append(self: *Self, T: type, value: V) void {
            self.types = self.types ++ &[_]type{T};
            self.values = self.values ++ &[_]V{value};
        }

        pub fn has(self: Self, T: type) bool {
            @setEvalBranchQuota(20_000);
            return comptime has_type: {
                for (self.types) |t| {
                    if (t == T) break :has_type true;
                }
                break :has_type false;
            };
        }

        pub fn indexOf(self: Self, T: type) ?usize {
            @setEvalBranchQuota(20_000);
            return comptime index: {
                for (self.types, 0..) |t, i| {
                    if (t == T) break :index i;
                }
                break :index null;
            };
        }

        pub fn get(self: Self, T: type) ?V {
            @setEvalBranchQuota(20_000);
            return comptime value: {
                for (self.types, 0..) |t, i| {
                    if (t == T) break :value self.values[i];
                }
                break :value null;
            };
        }

        pub fn set(self: *Self, T: type, value: V) void {
            const idx = self.indexOf(T) orelse {
                self.append(T, value);
                return;
            };

            self.values = self.values[0..idx] ++ [_]V{value} ++ self.values[idx + 1 ..];
        }

        pub fn nameOfIndex(self: Self, index: usize) [:0]const u8 {
            if (@inComptime()) {
                return @typeName(self.types[index]);
            }
            inline for (self.types, 0..) |T, i| {
                if (index == i) return @typeName(T);
            }
            // this is only used for debugging, so its fine
            return "OUT_OF_BOUNDS_TYPE";
        }

        pub fn hasUtp(self: Self, utp: ztg.meta.Utp) bool {
            inline for (self.types) |T| {
                if (ztg.meta.utpOf(T) == utp) return true;
            }
            return false;
        }
    };
}

test "typemap" {
    const ctx = struct {
        fn appendFromOuter(tm: *TypeMap(u32), types: []const type) void {
            for (types, 4..) |T, i| tm.append(T, i);
        }

        fn accessAtRuntime(comptime map: TypeMap(u32)) !void {
            const b = try std.testing.allocator.alloc(bool, map.get(bool).?);
            defer std.testing.allocator.free(b);
        }
    };

    const Struct = struct {
        x: f32,
        y: f32,
    };
    const Union = union(enum) {
        a: i32,
        b: u32,
    };
    const Enum = enum { a, b, c };

    const typemap = comptime blk: {
        var tm: TypeMap(u32) = .empty;
        tm.append(u32, 0);
        tm.append(i32, 1);
        tm.append(bool, 2);
        tm.append(Struct, 3);
        ctx.appendFromOuter(&tm, &.{ Union, Enum, base.Transform });
        break :blk tm;
    };

    const expected_types = [_]type{ u32, i32, bool, Struct, Union, Enum, base.Transform };
    const expected_values = [_]u32{ 0, 1, 2, 3, 4, 5, 6 };

    inline for (
        expected_types,
        typemap.dereferenceKeys(typemap.types.len),
        expected_values,
        comptime typemap.dereferenceValues(typemap.types.len),
        0..,
    ) |E, Actual, expected, actual, i| {
        _ = meta.utpOf(Actual);

        if (E != Actual) {
            @compileError("Expected " ++ @typeName(E) ++ " found " ++ @typeName(Actual));
        }

        if (expected != actual) {
            @import("../util.zig").compileError("Expected {} found {}", .{ expected, actual });
        }

        try std.testing.expect(typemap.has(E));
        try std.testing.expectEqual(i, typemap.indexOf(E).?);
    }

    try ctx.accessAtRuntime(typemap);
}
