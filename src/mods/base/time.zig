const ztg = @import("../../init.zig");

const Time = @This();

dt: f32 = 0.0,
real_dt: f32 = 0.0,

time_scale: f32 = 1.0,

time: f32 = 0.0,
real_time: f32 = 0.0,

/// The `frame_count` starts at 0 and is updated in `.post_update`
frame_count: usize = 0,

const frames_sample_len = 10;
var frames_sample_i: usize = 0;
var frames_sample_counter: f32 = 0.0;
var frames_sample = @Vector(frames_sample_len, usize){ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };

pub inline fn writeFpsStats(self: Time, writer: anytype) !void {
    return writer.print("FPS: {d:.0}\nAVG: {d:.1}\nMAX: {}\nMIN: {}", .{ 1.0 / if (self.real_dt == 0.0) 1.0 else self.real_dt, getAvgFps(), getMaxFps(), getMinFps() });
}

pub inline fn getFps(self: Time) usize {
    return 1.0 / if (self.real_dt == 0.0) 1.0 else self.real_dt;
}

pub inline fn getAvgFps() f32 {
    const total = @reduce(.Add, frames_sample);
    return @as(f32, @floatFromInt(total)) / @as(comptime_float, frames_sample_len);
}

pub inline fn getMinFps() usize {
    return @reduce(.Min, frames_sample);
}

pub inline fn getMaxFps() usize {
    return @reduce(.Max, frames_sample);
}

/// Used for impls of Time
pub fn update(self: *Time, real_dt: f32) void {
    self.real_dt = real_dt;
    self.dt = real_dt * self.time_scale;

    frames_sample_counter += real_dt;

    // Collect samples over one second
    if (frames_sample_counter > 1.0 / @as(comptime_float, frames_sample_len)) {
        frames_sample_counter = 0;
        frames_sample[frames_sample_i] = @intFromFloat(1.0 / if (real_dt == 0.0) 1.0 else real_dt);

        frames_sample_i += 1;
        if (frames_sample_i >= frames_sample_len) frames_sample_i = 0;
    }
}

pub fn include(comptime wb: *ztg.WorldBuilder) void {
    wb.addResource(Time, .{});
    wb.addSystemsToStage(.update, .{ztg.after(.body, pou_Time)});
}

fn pou_Time(self: *Time) void {
    self.frame_count += 1;
    self.time += self.dt;
    self.real_time += self.real_dt;
}
