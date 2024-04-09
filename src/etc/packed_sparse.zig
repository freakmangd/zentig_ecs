const std = @import("std");

pub const Error = error{Overflow};

pub fn PackedSparse(comptime Sparse: type, comptime len: usize) type {
    if (len == 0) @compileError("Length of array cannot be 0.");

    return struct {
        const Self = @This();

        written_indexes: std.BoundedArray(usize, len) = .{},
        sparse_list: [len]Sparse = undefined,

        pub fn set(self: *Self, index: usize, value: Sparse) Error!void {
            try self.written_indexes.append(index);
            self.sparse_list[index] = value;
        }

        pub fn lookup(self: *const Self, index: usize) Sparse {
            return self.sparse_list[index];
        }

        pub fn lookupPtr(self: *Self, index: usize) *Sparse {
            return &self.sparse_list[index];
        }

        pub fn last(self: *const Self) Sparse {
            return self.sparse_list[self.written_indexes.get(self.written_indexes.len - 1)];
        }

        pub fn remove(self: *Self, entry: usize) bool {
            if (self.written_indexes.len == 0) return false;

            for (self.written_indexes.constSlice(), 0..) |v, i| {
                if (v == entry) {
                    _ = self.written_indexes.swapRemove(i);
                    return true;
                }
            }

            return false;
        }

        pub fn pop(self: *Self) struct { usize, *Sparse } {
            const o1 = self.written_indexes.pop();
            const o2 = &self.sparse_list[o1];
            return .{ o1, o2 };
        }

        pub fn iterator(self: *Self) PsIterator {
            return .{
                .values = &self.sparse_list,
                .indexes = self.written_indexes.slice(),
            };
        }

        const PsIterator = struct {
            values: []Sparse,
            indexes: []usize,
            current: usize = 0,

            pub fn next(self: *PsIterator) ?*Sparse {
                if (self.current >= self.indexes.len) return null;
                self.current += 1;
                return &self.values[self.indexes[self.current - 1]];
            }
        };
    };
}
