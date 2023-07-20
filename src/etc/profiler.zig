const std = @import("std");
const ztg = @import("../init.zig");
const builtin = @import("builtin");
const Self = @This();

const ProfilerSection = struct {
    name: []const u8,
    samples: usize = 0,
    timing_ms: i64 = 0,
    timing_ms_start: i64,
};

var report_time: f32 = 0;
var sections = std.StringHashMap(ProfilerSection).init(std.heap.c_allocator);

pub fn report(writer: anytype, dt: f32) void {
    report_time += dt;
    if (report_time >= 1) {
        writer.print("=== PROFILER ===\n", .{}) catch {};
        var iter = sections.valueIterator();
        while (iter.next()) |sec| {
            writer.print("{s} :: {d:.2} ms\n", .{ sec.name, ztg.math.divAsFloat(f32, sec.timing_ms, sec.samples) }) catch {};
        }
        sections.clearAndFree();
        report_time = 0;
    }
}

pub fn startSection(comptime name: []const u8) void {
    sections.put(name, .{
        .name = name,
        .timing_ms_start = std.time.milliTimestamp(),
    }) catch {};
}

pub fn endSection(comptime name: []const u8) void {
    if (sections.getPtr(name)) |sec| {
        sec.timing_ms += std.time.milliTimestamp() - sec.timing_ms_start;
        sec.timing_ms_start = std.time.milliTimestamp();
        sec.samples += 1;
    }
}
