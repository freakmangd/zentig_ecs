//! This whole file is just... awful... but it works

const std = @import("std");
const ztg = @import("../init.zig");
const builtin = @import("builtin");
const Self = @This();

const ProfilerSection = struct {
    name: []const u8,
    timing_micro: i64 = 0,
    samples: usize = 0,
    timing_micro_start: i64,

    pub fn end(self: *ProfilerSection) void {
        self.timing_micro += std.time.microTimestamp() - self.timing_micro_start;
        self.timing_micro_start = std.time.microTimestamp();
        self.samples += 1;
    }
};

var report_time: f32 = 0;
var sections: std.AutoHashMap(*const anyopaque, ProfilerSection) = undefined;

pub fn init(alloc: std.mem.Allocator) void {
    sections = std.AutoHashMap(*const anyopaque, ProfilerSection).init(alloc);
}

pub fn deinit() void {
    sections.deinit();
}

pub fn report(writer: anytype, dt: f32) void {
    report_time += dt;
    if (report_time >= 1) {
        writer.print("=== PROFILER ===\n", .{}) catch {};
        var valueIter = sections.valueIterator();
        while (valueIter.next()) |sec| {
            const micro = @divFloor(@as(u64, @intCast(sec.timing_micro)), sec.samples);
            const secs = ztg.math.divAsFloat(f64, micro, 1000000) catch unreachable;
            writer.print("MS: {: <6.2} :: FPS: {d: <6.2} :: {s}\n", .{ @divFloor(micro, 1000), if (micro > 0) 1.0 / secs else std.math.nan(f64), sec.name }) catch {};
        }
        sections.clearRetainingCapacity();
        report_time = 0;
    }
}

pub fn startSection(comptime name: []const u8) *ProfilerSection {
    sections.put(name.ptr, .{
        .name = name,
        .timing_micro_start = std.time.microTimestamp(),
    }) catch {};
    return sections.getPtr(name.ptr).?;
}
