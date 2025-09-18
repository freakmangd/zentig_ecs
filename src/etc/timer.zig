const Timer = @This();

max: f32,
remaining: f32,

state: State = .running,
on_elapsed: OnElapsed = .reset,

const State = enum {
    running,
    stopped,
};

const OnElapsed = enum {
    reset,
    stop,
};

pub fn init(max: f32, options: struct {
    remaining: ?f32 = null,
    state: State = .running,
    on_elapsed: OnElapsed = .reset,
}) Timer {
    return .{
        .max = max,
        .remaining = options.remaining orelse max,
        .state = options.state,
        .on_elapsed = options.on_elapsed,
    };
}

/// Reduces time remaining by delta, returns whether the timer is at or has passed 0
/// Always returns false when state == .stopped
pub fn advance(self: *Timer, delta: f32) bool {
    if (self.state == .stopped) return false;

    self.remaining -= delta;
    const hit_zero = self.remaining <= 0;

    if (hit_zero) switch (self.on_elapsed) {
        .reset => self.reset(),
        .stop => self.state = .stopped,
    };

    return hit_zero;
}

pub fn reset(self: *Timer) void {
    self.remaining = self.max;
    self.state = .running;
}
