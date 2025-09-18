const std = @import("std");
const base = @import("../mods/base/init.zig");
const meta = @import("meta.zig");

const TypeMap = @This();

types: []const type = &.{},

pub fn dereference(self: TypeMap, comptime len: usize) [len]type {
    return self.types[0..].*;
}

pub fn append(self: *TypeMap, T: type) void {
    self.types = self.types ++ &[_]type{T};
}

pub fn appendSlice(self: *TypeMap, types: []const type) void {
    const new_types_slce = self.types ++ @as([types.len]type, types[0..types.len].*);
    self.types = new_types_slce;
}

pub fn has(self: TypeMap, T: type) bool {
    return comptime has_type: {
        for (self.types) |t| {
            @setEvalBranchQuota(20_000);
            if (t == T) break :has_type true;
        }
        break :has_type false;
    };
}

pub fn indexOf(self: TypeMap, T: type) ?usize {
    return comptime index: {
        for (self.types, 0..) |t, i| {
            @setEvalBranchQuota(20_000);
            if (t == T) break :index i;
        }
        break :index null;
    };
}

test "typemap" {
    const ctx = struct {
        fn appendFromOuter(tm: *TypeMap, types: []const type) void {
            tm.appendSlice(types);
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
        var tm = TypeMap{};
        tm.append(u32);
        tm.appendSlice(&.{ i32, bool, Struct });
        ctx.appendFromOuter(&tm, &.{ Union, Enum, base.Transform });
        break :blk tm;
    };

    const expected_types = [_]type{ u32, i32, bool, Struct, Union, Enum, base.Transform };
    inline for (expected_types, typemap.dereference(typemap.types.len), 0..) |E, Actual, i| {
        _ = meta.utpOf(Actual);

        if (E != Actual) {
            @compileError("Expected " ++ @typeName(E) ++ " found " ++ @typeName(Actual));
        }

        try std.testing.expect(typemap.has(E));
        try std.testing.expectEqual(i, typemap.indexOf(E).?);
    }
}
