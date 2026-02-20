const std = @import("std");
const util = @import("../util.zig");

const StorageType = enum {
    embedded,
    slice,
    const_slice,
};

pub fn Array2d(width: usize, height: usize, Elem: type, storage: StorageType) type {
    return struct {
        strides: [2]usize = .{ width, height },
        items: Items,

        pub const dimensions: [2]usize = .{ width, height };

        const Items = switch (storage) {
            .embedded => [width * height]Elem,
            .slice => []Elem,
            .const_slice => []const Elem,
        };

        pub fn initSplat(elem: Elem) @This() {
            if (storage != .embedded) @compileError("Expected 2d embedded array");
            return .{ .items = @splat(elem) };
        }

        pub fn initAlloc(gpa: std.mem.Allocator, default: Elem) !@This() {
            if (storage == .embedded) @compileError("Expected 2d slice");

            const items = try gpa.alloc(Elem, width * height);
            @memset(items, default);
            return .{ .items = items };
        }

        pub fn index(arr: *const @This(), x: usize, y: usize) usize {
            return index2d(arr.strides, x, y);
        }

        pub fn indexOrNull(arr: *const @This(), x: usize, y: usize) usize {
            return index2dOrNull(arr.strides, x, y);
        }

        pub fn position(arr: *const @This(), idx: usize) [2]usize {
            std.debug.assert(idx < arr.items.len);
            return .{ idx % arr.strides[0], (idx / arr.strides[0]) % arr.strides[1] };
        }

        pub fn positionOrNull(arr: *const @This(), idx: usize) ?[2]usize {
            if (idx >= arr.items.len) return null;
            return .{ idx % arr.strides[0], (idx / arr.strides[0]) % arr.strides[1] };
        }

        pub fn get(arr: *const @This(), x: usize, y: usize) Elem {
            return arr.items[index2d(arr.strides, x, y)];
        }

        pub fn getPtr(arr: *@This(), x: usize, y: usize) *Elem {
            return &arr.items[index2d(arr.strides, x, y)];
        }

        pub fn getPtrConst(arr: *const @This(), x: usize, y: usize) *const Elem {
            return &arr.items[index2d(arr.strides, x, y)];
        }

        pub fn set(arr: *@This(), x: usize, y: usize, val: Elem) void {
            arr.items[index2d(arr.strides, x, y)] = val;
        }

        /// with `for` loops that capture by pointer, arrays need `&arr` and slices dont
        /// using this solves that
        pub fn slice(arr: anytype) ArraySlice(@TypeOf(arr), Items) {
            return switch (@typeInfo(Items)) {
                .pointer => arr.items,
                .array => &arr.items,
                else => unreachable,
            };
        }
    };
}

pub fn Array3d(dimensions: [3]usize, Array: type) type {
    return struct {
        strides: [3]usize = dimensions,
        items: Array,

        const Elem = std.meta.Elem(Array);

        pub fn index(arr: *const @This(), x: usize, y: usize, z: usize) usize {
            return index3d(arr.strides, x, y, z);
        }

        pub fn indexOrNull(arr: *const @This(), x: usize, y: usize, z: usize) usize {
            return index3dOrNull(arr.strides, x, y, z);
        }

        pub fn position(arr: *const @This(), idx: usize) [3]usize {
            std.debug.assert(idx < arr.items.len);
            return .{ idx % arr.strides[0], (idx / arr.strides[0]) % arr.strides[1], idx / (arr.strides[0] * arr.strides[1]) };
        }

        pub fn positionOrNull(arr: *const @This(), idx: usize) ?[3]usize {
            if (idx >= arr.items.len) return null;
            return .{ idx % arr.strides[0], (idx / arr.strides[0]) % arr.strides[1], idx / (arr.strides[0] * arr.strides[1]) };
        }

        pub fn get(arr: *const @This(), x: usize, y: usize, z: usize) Elem {
            return arr.items[index3d(arr.strides[0], arr.strides[1], x, y, z)];
        }

        pub fn getPtr(arr: *@This(), x: usize, y: usize, z: usize) *Elem {
            return &arr.items[index3d(arr.strides, x, y, z)];
        }

        pub fn getPtrConst(arr: *const @This(), x: usize, y: usize, z: usize) *const Elem {
            return &arr.items[index3d(arr.strides, x, y, z)];
        }

        pub fn set(arr: *@This(), x: usize, y: usize, z: usize, val: Elem) void {
            arr.items[index3d(arr.strides, x, y, z)] = val;
        }

        /// with `for` loops that capture by pointer, arrays need `&arr` and slices dont
        /// using this solves that
        pub fn slice(arr: anytype) ArraySlice(@TypeOf(arr), Array) {
            return switch (@typeInfo(Array)) {
                .pointer => arr.items,
                .array => &arr.items,
                else => unreachable,
            };
        }
    };
}

fn ArraySlice(Self: type, Array: type) type {
    const Elem = std.meta.Elem(Array);

    if (@typeInfo(Array) == .pointer)
        return []Elem;
    if (@typeInfo(Array) == .pointer and @typeInfo(Array).pointer.is_const)
        return []const Elem;
    if (@typeInfo(Self).pointer.is_const)
        return []const Elem;

    return []Elem;
}

pub fn index2d(dimensions: [2]usize, x: usize, y: usize) usize {
    std.debug.assert(inRange(2, dimensions, .{ x, y }));
    return x + y * dimensions[0];
}

pub fn index3d(dimensions: [3]usize, x: usize, y: usize, z: usize) usize {
    std.debug.assert(inRange(3, dimensions, .{ x, y, z }));
    return x + y * dimensions[0] + z * dimensions[0] * dimensions[1];
}

pub fn indexNd(dimensions: anytype, indexes: [dimensions.len]usize) usize {
    std.debug.assert(inRange(indexes));
    return indexNdRaw(dimensions, indexes);
}

pub fn index2dOrNull(dimensions: [2]usize, x: usize, y: usize) ?usize {
    if (!inRange(2, dimensions, .{ x, y })) return null;
    return x + y * dimensions[0];
}

pub fn index3dOrNull(dimensions: [3]usize, x: usize, y: usize, z: usize) ?usize {
    if (!inRange(3, dimensions, .{ x, y, z })) return null;
    return x + y * dimensions[0] + z * dimensions[0] * dimensions[1];
}

pub fn indexNdOrNull(dimensions: anytype, indexes: [dimensions.len]usize) ?usize {
    if (!inRange(indexes)) return null;
    return indexNdRaw(dimensions, indexes);
}

pub fn index2dRaw(width: usize, x: usize, y: usize) usize {
    return x + y * width;
}

pub fn index3dRaw(width: usize, height: usize, x: usize, y: usize, z: usize) usize {
    return x + y * width + z * width * height;
}

pub fn indexNdRaw(comptime len: usize, dimensions: [len]usize, indexes: [len]usize) usize {
    var idx: usize = 0;
    var mul: usize = 1;
    for (indexes, dimensions) |i, s| {
        idx += i * mul;
        mul *= s;
    }
    return idx;
}

pub fn inRange(comptime len: usize, dimensions: [len]usize, indexes: [len]usize) bool {
    for (dimensions, indexes) |dim, i| {
        if (i >= dim) return false;
    }
    return true;
}

pub fn position2d(dim: [2]usize, idx: usize) [2]usize {
    std.debug.assert(idx < dim[0] * dim[1]);
    return .{ idx % dim[0], (idx / dim[0]) % dim[1] };
}

pub fn position3d(dim: [2]usize, idx: usize) [3]usize {
    std.debug.assert(idx < dim[0] * dim[1]);
    return .{ idx % dim[0], (idx / dim[0]) % dim[1], idx / (dim[0] * dim[1]) };
}
