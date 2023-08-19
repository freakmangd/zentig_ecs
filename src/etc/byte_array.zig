const std = @import("std");

const Self = @This();

entry_size: usize,
bytes: std.ArrayListUnmanaged(u8),
len: usize = 0,

pub fn init(comptime T: type) Self {
    return .{
        .entry_size = @sizeOf(T),
        .bytes = .{},
    };
}

pub fn initCapacity(comptime T: type, alloc: std.mem.Allocator, num: usize) !Self {
    return .{
        .entry_size = @sizeOf(T),
        .bytes = try std.ArrayListUnmanaged(u8).initCapacity(alloc, @sizeOf(T) * num),
    };
}

pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
    self.bytes.deinit(alloc);
}

pub fn append(self: *Self, alloc: std.mem.Allocator, entry: anytype) !void {
    if (@sizeOf(@TypeOf(entry)) != self.entry_size) @panic("Wrong type.");
    try self.bytes.appendSlice(alloc, std.mem.asBytes(&entry));
    self.len += 1;
}

pub fn appendAssumeCapacity(self: *Self, entry: anytype) void {
    if (@sizeOf(@TypeOf(entry)) != self.entry_size) @panic("Wrong type.");
    self.bytes.appendSliceAssumeCapacity(std.mem.asBytes(&entry));
    self.len += 1;
}

pub fn appendPtr(self: *Self, alloc: std.mem.Allocator, bytes_start: *const anyopaque) !void {
    try self.bytes.appendSlice(alloc, @as([*]const u8, @ptrCast(bytes_start))[0..self.entry_size]);
    self.len += 1;
}

pub fn appendPtrAssumeCapacity(self: *Self, bytes_start: *const anyopaque) void {
    self.bytes.appendSliceAssumeCapacity(@as([*]const u8, @ptrCast(bytes_start))[0..self.entry_size]);
    self.len += 1;
}

pub fn getCapacity(self: Self) usize {
    if (self.entry_size == 0) return std.math.maxInt(usize);
    return self.bytes.capacity / self.entry_size;
}

pub fn set(self: *Self, index: usize, bytes_start: *const anyopaque) void {
    @memcpy(
        self.bytes.items[index * self.entry_size ..][0..self.entry_size],
        @as([*]const u8, @ptrCast(bytes_start))[0..self.entry_size],
    );
}

pub fn get(self: Self, index: usize) *anyopaque {
    if (self.entry_size == 0) return &.{};
    return &self.bytes.items[index * self.entry_size];
}

pub fn getAs(self: Self, comptime T: type, index: usize) *T {
    return cast(T, self.get(index));
}

pub fn getAsBytes(self: Self, index: usize) []const u8 {
    return @as([*]const u8, @ptrCast(&self.bytes.items[index * self.entry_size]))[0..self.entry_size];
}

pub fn slicedAs(self: *Self, comptime T: type) []T {
    if (@sizeOf(T) != self.entry_size) @panic("Wrong type.");
    return @as([*]T, @ptrCast(@alignCast(self.bytes.items.ptr)))[0 .. self.bytes.items.len / self.entry_size];
}

pub fn pop(self: *Self) []const u8 {
    if (self.bytes.items.len == 0) @panic("Cannot pop an empty array.");

    const out = self.getAsBytes(self.bytes.items.len / self.entry_size - 1);
    self.bytes.items.len -= self.entry_size;
    self.len -= 1;
    return out;
}

pub fn swapRemove(self: *Self, index: usize) void {
    if (self.entry_size == 0) {
        self.len -= 1;
        return;
    }

    if ((self.bytes.items.len / self.entry_size) - 1 == index) {
        _ = self.pop();
        return;
    }

    var bytes = self.pop();
    self.set(index, bytes.ptr);
}

inline fn cast(comptime T: type, data: *anyopaque) *T {
    if (@alignOf(T) == 0) return @as(*T, @ptrCast(data));
    return @ptrCast(@alignCast(data));
}

pub const ByteIterator = struct {
    buffer: []u8,
    entry_size: usize,
    index: usize = 0,

    pub fn next(self: *ByteIterator) ?*anyopaque {
        if (self.index >= self.buffer.len / self.entry_size) return null;
        self.index += 1;
        return self.buffer.ptr + (self.index - 1) * self.entry_size;
    }

    pub fn nextAs(self: *ByteIterator, comptime T: type) ?*T {
        var n = self.next() orelse return null;
        return cast(T, n);
    }
};

pub fn iterator(self: *Self) ByteIterator {
    return .{
        .buffer = self.bytes.items,
        .entry_size = self.entry_size,
    };
}

test "decls" {
    std.testing.refAllDecls(@This());
}

const Data = struct {
    lmao: u32,
    uhh: bool = false,
    xd: f32 = 100.0,
    ugh: enum { ok, bad } = .ok,
};

test "simple test" {
    const alloc = std.testing.allocator;

    var arr = Self.init(u32);
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

    var arr = Self.init(Data);
    defer arr.deinit(alloc);

    try arr.append(alloc, Data{ .lmao = 100_000 });
    try arr.append(alloc, Data{ .lmao = 20_000 });

    try std.testing.expectEqual(@as(u32, 100_000), arr.getAs(Data, 0).lmao);
    try std.testing.expectEqual(@as(u32, 20_000), arr.getAs(Data, 1).lmao);

    arr.swapRemove(0);
    try std.testing.expectEqual(@as(f32, 100.0), arr.getAs(Data, 0).xd);

    arr.swapRemove(0);
    try std.testing.expectEqual(@as(usize, 0), arr.len());
}
