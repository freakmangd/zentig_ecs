pub fn Mask(BackingInt: type, NamesEnum: type) type {
    const Enum = Enum: {
        var value: BackingInt = 1;
        var values: [@typeInfo(NamesEnum).@"enum".fields.len]BackingInt = undefined;

        for (&values) |*v| {
            v.* = value;
            value <<= 1;
        }

        break :Enum @Enum(BackingInt, .exhaustive, std.meta.fieldNames(NamesEnum), &values);
    };

    return struct {
        pub const none: BackingInt = 0;
        pub const all: BackingInt = std.math.maxInt(BackingInt);

        pub fn combine(enabled: []const Enum) BackingInt {
            var out: BackingInt = 0;
            for (enabled) |e| out |= @intFromEnum(e);
            return out;
        }

        pub fn inverse(disabled: []const Enum) BackingInt {
            var out = all;
            for (disabled) |d| out &= ~@intFromEnum(d);
            return out;
        }
    };
}

const std = @import("std");
