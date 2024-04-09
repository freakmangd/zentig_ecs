const std = @import("std");
const ztg = @import("../init.zig");
const util = @import("../util.zig");

pub fn EnumValueSpace(comptime Enum: type, comptime dimensions: usize, comptime defs: anytype) type {
    return struct {
        var points = blk: {
            var map = std.EnumMap(Enum, ztg.ComptimeList(@Vector(dimensions, f32))){};

            for (std.meta.fields(@TypeOf(defs))) |field| {
                const tag = std.meta.stringToEnum(Enum, field.name) orelse util.compileError("Field {s} of EnumValueSpace is not a registered enum variant of enum type {}", .{ field.name, Enum });

                var ptr = map.getPtr(tag) orelse getPtr_blk: {
                    map.put(tag, .{});
                    break :getPtr_blk map.getPtr(tag).?;
                };

                const ti = @typeInfo(@TypeOf(@field(defs, field.name)[0]));
                if (ti == .Struct and ti.Struct.is_tuple) {
                    for (@field(defs, field.name)) |vec| {
                        ptr.append(vec);
                    }
                } else {
                    ptr.append(@field(defs, field.name));
                }
            }

            break :blk map;
        };

        pub fn eval(at: @Vector(dimensions, f32)) Enum {
            var shortest_sqr_dist: f32 = std.math.floatMax(f32);
            var shortest_tag: Enum = undefined;

            var iter = points.iterator();
            while (iter.next()) |entry| {
                for (entry.value.items) |pos| {
                    const sqr_dist = ztg.math.sqrDistanceVec(pos, at);
                    if (sqr_dist < shortest_sqr_dist) {
                        shortest_sqr_dist = sqr_dist;
                        shortest_tag = entry.key;
                    }
                }
            }

            return shortest_tag;
        }
    };
}
