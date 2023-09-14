const std = @import("std");
const ztg = @import("../../init.zig");
const util = @import("../../util.zig");

pub fn builder(comptime Parent: type, comptime Wrapper: type) Builder(Parent, Wrapper) {
    return .{};
}

fn Builder(comptime Parent: type, comptime Wrapper: type) type {
    _ = Parent;
    return struct {
        const Self = @This();

        image_names: ztg.ComptimeList(ImageDef) = .{},
        animations: ztg.ComptimeList(AnimationDef) = .{},
        transitions: ztg.ComptimeList(TransitionDef) = .{},
        events: ztg.ComptimeList(ztg.meta.EnumLiteral) = .{},

        pub fn image(
            comptime self: *Self,
            comptime name: ztg.meta.EnumLiteral,
            comptime defaults: ?ImageDef.DefaultSettings,
        ) void {
            self.image_names.append(.{
                .tag = name,
                .defaults = defaults,
            });
        }

        pub fn animation(
            comptime self: *Self,
            comptime name: ztg.meta.EnumLiteral,
            comptime def: anytype,
        ) void {
            self.animations.append(AnimationDef.init(name, def));
        }

        pub fn transition(
            comptime self: *Self,
            comptime from: ztg.meta.EnumLiteral,
            comptime to: ztg.meta.EnumLiteral,
        ) void {
            self.transitions.append(TransitionDef{
                .from = from,
                .to = to,
            });
        }

        pub fn event(comptime self: *Self, comptime name: ztg.meta.EnumLiteral) void {
            _ = name;
            _ = self;
        }

        pub fn twoWayTransition(
            comptime self: *Self,
            comptime from: ztg.meta.EnumLiteral,
            comptime to: ztg.meta.EnumLiteral,
        ) void {
            self.transition(from, to);
            self.transition(to, from);
        }

        pub fn Build(comptime self: Self, comptime default_anim: ztg.meta.EnumLiteral) type {
            return Animator(Wrapper, self, default_anim);
        }

        const ImageDef = struct {
            tag: ztg.meta.EnumLiteral,
            defaults: ?DefaultSettings,

            const DefaultSettings = struct {
                file_path: []const u8,
                slice_method: ImageSliceMethod,
            };
        };

        const AnimationDef = struct {
            tag: ztg.meta.EnumLiteral,
            frames: []const FrameGroupDef,

            pub fn init(comptime tag: ztg.meta.EnumLiteral, comptime info: anytype) AnimationDef {
                var frames: [info.len]FrameGroupDef = undefined;

                inline for (&frames, info) |*o, frame_group| {
                    o.* = FrameGroupDef.fromRaw(frame_group);
                }

                return .{
                    .tag = tag,
                    .frames = &frames,
                };
            }
        };

        const TransitionDef = struct {
            from: ztg.meta.EnumLiteral,
            to: ztg.meta.EnumLiteral,
        };

        const FrameGroupDef = struct {
            image_tag: ztg.meta.EnumLiteral,
            slice_indexes: []const @Vector(2, usize),

            pub fn fromRaw(comptime raw: anytype) FrameGroupDef {
                var indexes: [raw.len - 1]@Vector(2, usize) = undefined;

                comptime var i: usize = 1;
                while (i < raw.len) : (i += 1) {
                    const current = raw[i];

                    if (@TypeOf(current) == []const u8)
                        appendIndexesFromString(indexes[i - 1 ..], current);

                    indexes[i - 1] = .{ current[0], current[1] };
                }

                return .{
                    .image_tag = raw[0],
                    .slice_indexes = &indexes,
                };
            }

            fn appendIndexesFromString(indexes: []@Vector(2, usize), str: []const u8) usize {
                const err_msg = "Image grid positional string must be formatted like so: \"x,y\"";

                if (std.mem.count(u8, str, ",") != 1)
                    @compileError(err_msg);

                var split_iter = std.mem.splitScalar(u8, str, ',');

                const x_part_str = split_iter.next() orelse @compileError(err_msg);
                const x_part_parsed = parsePosPart(x_part_str);

                const y_part_str = split_iter.next() orelse @compileError(err_msg);
                const y_part_parsed = parseRangePart(y_part_str);

                if (x_part_parsed == .range and y_part_parsed == .range) {
                    @compileError("Both parts of grid positional string cannot be ranges");
                } else if (x_part_parsed == .single and y_part_parsed == .single) {
                    indexes[0] = .{ x_part_parsed.single, y_part_parsed.single };
                    return 1;
                }

                const range = if (x_part_parsed == .range) x_part_parsed else y_part_parsed;

                var i: usize = 0;
                const len = range.range[1] - range.range[0];

                while (i <= len) : (i += 1) {
                    if (x_part_parsed == .range) {
                        indexes[i] = .{ range.range[0] + i, y_part_parsed.single };
                    } else {
                        indexes[i] = .{ x_part_parsed.single, range.range[0] + i };
                    }
                }

                return len;
            }

            fn parsePosPart(part_str: []const u8) union(enum) {
                single: usize,
                range: @Vector(2, usize),
            } {
                const dot_count = std.mem.count(u8, part_str, ".");

                var dot_split_iter = std.mem.tokenizeScalar(u8, part_str, ".");

                return switch (dot_count) {
                    0 => .{ .single = parseRangePart(part_str) },

                    // exclusive range
                    2 => .{ .range = .{
                        parseRangePart(dot_split_iter.next()),
                        parseRangePart(dot_split_iter.next()) - 1,
                    } },

                    // inclusive range
                    3 => .{ .range = .{
                        parseRangePart(dot_split_iter.next()),
                        parseRangePart(dot_split_iter.next()),
                    } },

                    else => @compileError("Ranges for slicing must be either formatted as x, x..y, or x...y"),
                };
            }

            fn parseRangePart(range_part: []const u8) usize {
                std.fmt.parseUnsigned(usize, range_part, 10) catch |err|
                    util.compileError("Could not parse Image slice range `{s}`. Error: {}", .{ range_part, err });
            }
        };
    };
}

const ImageSliceMethod = union(enum) {
    none,
    auto_slice: struct {
        width: usize,
        height: usize,
    },
};

fn Animator(comptime Wrapper: type, comptime builder_info: anytype, comptime default_anim: ztg.meta.EnumLiteral) type {
    return struct {
        const Animation = ztg.meta.EnumFromLiterals(builder_info.animations.toEnumLiterals());
        const State = ztg.zigfsm.StateMachine(Animation, null, @as(Animation, default_anim));

        state: State,

        const SlicedImage = struct {
            tag: ztg.meta.EnumLiteral,
            img: Wrapper.Image,
            slice_method: ImageSliceMethod,
        };
    };
}
