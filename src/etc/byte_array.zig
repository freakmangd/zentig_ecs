const std = @import("std");

const ByteArray = @This();

entry_size: usize,
bytes: std.ArrayListUnmanaged(u8) = .empty,
len: usize = 0,

pub fn init(comptime T: type) ByteArray {
    return .{ .entry_size = @sizeOf(T) };
}

pub fn initCapacity(comptime T: type, alloc: std.mem.Allocator, num: usize) !ByteArray {
    return .{
        .entry_size = @sizeOf(T),
        .bytes = try .initCapacity(alloc, @sizeOf(T) * num),
    };
}

pub fn deinit(self: *ByteArray, alloc: std.mem.Allocator) void {
    self.bytes.deinit(alloc);
}

pub fn append(self: *ByteArray, alloc: std.mem.Allocator, entry: anytype) !void {
    if (@sizeOf(@TypeOf(entry)) != self.entry_size) @panic("Wrong type.");
    try self.bytes.appendSlice(alloc, std.mem.asBytes(&entry));
    self.len += 1;
}

pub fn appendAssumeCapacity(self: *ByteArray, entry: anytype) void {
    if (@sizeOf(@TypeOf(entry)) != self.entry_size) @panic("Wrong type.");
    self.bytes.appendSliceAssumeCapacity(std.mem.asBytes(&entry));
    self.len += 1;
}

pub fn appendPtr(self: *ByteArray, alloc: std.mem.Allocator, bytes_start: *const anyopaque) !*anyopaque {
    try self.bytes.appendSlice(alloc, @as([*]const u8, @ptrCast(bytes_start))[0..self.entry_size]);
    self.len += 1;
    return if (self.entry_size == 0) undefined else &self.bytes.items[(self.len - 1) * self.entry_size];
}

pub fn appendPtrAssumeCapacity(self: *ByteArray, bytes_start: *const anyopaque) void {
    self.bytes.appendSliceAssumeCapacity(@as([*]const u8, @ptrCast(bytes_start))[0..self.entry_size]);
    self.len += 1;
}

pub fn getCapacity(self: ByteArray) usize {
    if (self.entry_size == 0) return std.math.maxInt(usize);
    return self.bytes.capacity / self.entry_size;
}

pub fn set(self: *ByteArray, index: usize, bytes_start: *const anyopaque) void {
    @memcpy(
        self.bytes.items[index * self.entry_size ..][0..self.entry_size],
        @as([*]const u8, @ptrCast(bytes_start))[0..self.entry_size],
    );
}

pub fn get(self: ByteArray, index: usize) *anyopaque {
    if (self.entry_size == 0) return @ptrFromInt(std.math.maxInt(usize));
    return &self.bytes.items[index * self.entry_size];
}

pub fn getAs(self: ByteArray, comptime T: type, index: usize) *T {
    return cast(T, self.get(index));
}

pub fn getAsBytes(self: ByteArray, index: usize) []const u8 {
    return @as([*]const u8, @ptrCast(&self.bytes.items[index * self.entry_size]))[0..self.entry_size];
}

pub fn slicedAs(self: *ByteArray, comptime T: type) []T {
    if (@sizeOf(T) != self.entry_size) @panic("Wrong type.");
    return @as([*]T, @ptrCast(@alignCast(self.bytes.items.ptr)))[0 .. self.bytes.items.len / self.entry_size];
}

pub fn pop(self: *ByteArray) []const u8 {
    if (self.bytes.items.len == 0) @panic("Cannot pop an empty array.");

    const out = self.getAsBytes(self.bytes.items.len / self.entry_size - 1);
    self.bytes.items.len -= self.entry_size;
    self.len -= 1;
    return out;
}

pub fn swapRemove(self: *ByteArray, index: usize) void {
    if (self.entry_size == 0) {
        self.len -= 1;
        return;
    }

    if ((self.bytes.items.len / self.entry_size) - 1 == index) {
        _ = self.pop();
        return;
    }

    const bytes = self.pop();
    self.set(index, bytes.ptr);
}

fn cast(comptime T: type, data: *anyopaque) *T {
    if (@alignOf(T) == 0) return @as(*T, @ptrCast(data));
    return @ptrCast(@alignCast(data));
}

pub const ByteIterator = struct {
    buffer: []u8,
    entry_size: usize,
    index: usize = 0,

    pub fn next(self: *ByteIterator) ?*anyopaque {
        std.debug.assert(self.entry_size > 0);

        if (self.index >= self.buffer.len / self.entry_size) return null;
        self.index += 1;
        return self.buffer.ptr + (self.index - 1) * self.entry_size;
    }

    pub fn nextAs(self: *ByteIterator, comptime T: type) ?*T {
        const n = self.next() orelse return null;
        return cast(T, n);
    }
};

pub fn iterator(self: *ByteArray) ByteIterator {
    return .{
        .buffer = self.bytes.items,
        .entry_size = self.entry_size,
    };
}

const Data = struct {
    lmao: u32,
    uhh: bool = false,
    xd: f32 = 100.0,
    ugh: enum { ok, bad } = .ok,
};

test "simple test" {
    const alloc = std.testing.allocator;

    var arr = ByteArray.init(u32);
    defer arr.deinit(alloc);

    try arr.append(alloc, @as(u32, 1));
    try arr.append(alloc, @as(u32, 1));
    try arr.append(alloc, @as(u32, 2));

    arr.swapRemove(2);

    for (arr.slicedAs(u32)) |val| {
        try std.testing.expectEqual(@as(u32, 1), val);
    }
}

test "data" {
    const alloc = std.testing.allocator;

    var arr = ByteArray.init(Data);
    defer arr.deinit(alloc);

    try arr.append(alloc, Data{ .lmao = 100_000 });
    try arr.append(alloc, Data{ .lmao = 20_000 });

    try std.testing.expectEqual(@as(u32, 100_000), arr.getAs(Data, 0).lmao);
    try std.testing.expectEqual(@as(u32, 20_000), arr.getAs(Data, 1).lmao);

    arr.swapRemove(0);
    try std.testing.expectEqual(@as(f32, 100.0), arr.getAs(Data, 0).xd);

    arr.swapRemove(0);
    try std.testing.expectEqual(@as(usize, 0), arr.len);
}

test "iterator" {
    const alloc = std.testing.allocator;

    var arr = ByteArray.init(Data);
    defer arr.deinit(alloc);

    try arr.append(alloc, Data{ .lmao = 10 });
    try arr.append(alloc, Data{ .lmao = 20 });
    try arr.append(alloc, Data{ .lmao = 30 });
    try arr.append(alloc, Data{ .lmao = 40 });

    const expected = [_]Data{
        .{ .lmao = 10 },
        .{ .lmao = 20 },
        .{ .lmao = 30 },
        .{ .lmao = 40 },
    };

    var i: usize = 0;
    var iter = arr.iterator();
    while (iter.nextAs(Data)) |data| : (i += 1) {
        try std.testing.expectEqual(expected[i], data.*);
    }
}
