//! Used for recording performance and execution times of blocks of code
//!
//! Example:
//! ```zig
//! my_blk: {
//!     var perf = ztg.profiler.startSection("my block");
//!     defer perf.end();
//!
//!     doVeryExpensiveThing();
//!     nextVeryExpensiveThing();
//! }
//!
//! ztg.profiler.report(std.io.getStdOut().writer());
//! ```

// This whole file is just... awful... but it works

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

var alloc: std.mem.Allocator = undefined;
var report_time: f32 = 0;
var sections: std.AutoHashMap(usize, *ProfilerSection) = undefined;

pub fn init(_alloc: std.mem.Allocator) void {
    alloc = _alloc;
    sections = std.AutoHashMap(usize, *ProfilerSection).init(alloc);
}

pub fn deinit() void {
    var value_iter = sections.valueIterator();
    while (value_iter.next()) |sec_ptr| {
        alloc.destroy(sec_ptr.*);
    }

    sections.deinit();
}

/// Reports every X seconds when called each frame
pub fn reportTimed(writer: anytype, every_x_seconds: f32, dt: f32) void {
    report_time += dt;
    if (report_time >= every_x_seconds) {
        report(writer);
        report_time = 0;
    }
}

pub fn report(writer: anytype) void {
    writer.print("=== PROFILER ===\n", .{}) catch {};
    var valueIter = sections.valueIterator();
    while (valueIter.next()) |sec_ptr| {
        const sec = sec_ptr.*;
        defer alloc.destroy(sec);

        const micro = @as(u64, @intCast(sec.timing_micro)) / sec.samples;
        const secs = ztg.math.div(f64, micro, 1000000) catch unreachable;
        writer.print("MS: {d: <6.2} :: FPS: {d: <6.2} :: {s}\n", .{ secs * std.time.ms_per_s, @min(1.0 / secs, 999), sec.name }) catch {};
    }
    sections.clearRetainingCapacity();
}

pub fn startSection(comptime name: []const u8) *ProfilerSection {
    if (sections.get(@intFromPtr(name.ptr))) |sec| {
        sec.timing_micro_start = std.time.microTimestamp();
        return sec;
    }

    const new_section = alloc.create(ProfilerSection) catch @panic("Could not allocate for profiler");
    new_section.* = .{
        .name = name,
        .timing_micro_start = std.time.microTimestamp(),
    };

    sections.put(@intFromPtr(name.ptr), new_section) catch @panic("Could not put for profiler");
    return new_section;
}
