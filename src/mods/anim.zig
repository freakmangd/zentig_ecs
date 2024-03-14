const std = @import("std");
const ztg = @import("../init.zig");
const util = @import("../util.zig");

pub fn builder(
    comptime Wrapper: type,
    comptime serialize_as: []const u8,
    comptime ImageTag: type,
    comptime AnimationTag: type,
    comptime transitions: anytype,
) Builder(Wrapper, serialize_as, ImageTag, AnimationTag, transitions) {
    return .{};
}

const ImageDefault = struct {
    path: [:0]const u8,
    slice_method: ImageSliceMethod,
};

pub const ImageSliceMethod = union(enum) {
    none,
    auto_slice: struct {
        width: usize,
        height: usize,
    },
};

const Durations = union(enum) {
    single: f32,
    per_frame: []const f32,

    pub fn get(self: Durations, frame_index: usize) f32 {
        return switch (self) {
            .single => |d| d,
            .per_frame => |ds| ds[frame_index],
        };
    }
};

fn Builder(
    comptime Wrapper: type,
    comptime _serialize_as: []const u8,
    comptime _ImageTag: type,
    comptime _AnimationTag: type,
    comptime transitions: anytype,
) type {
    return struct {
        const Self = @This();
        const AnimationTag = _AnimationTag;
        const ImageTag = _ImageTag;
        pub const zentig_serialize = _serialize_as;

        image_defaults: std.EnumMap(ImageTag, ImageDefault) = .{},
        animations: std.EnumMap(AnimationTag, Animation) = .{},
        valid_transitions: std.EnumMap(AnimationTag, std.EnumSet(AnimationTag)) = blk: {
            var map = std.EnumMap(AnimationTag, std.EnumSet(AnimationTag)){};
            for (std.meta.fields(@TypeOf(transitions))) |tr_field| {
                if (std.mem.eql(u8, tr_field.name, "any")) continue;
                map.put(std.meta.stringToEnum(AnimationTag, tr_field.name) orelse
                    util.compileError("Enum literal {s} is not a part of AnimationTag set.", .{tr_field.name}), @field(transitions, tr_field.name));
            }
            break :blk map;
        },
        from_any_transitions: std.EnumSet(AnimationTag) = blk: {
            var map = std.EnumSet(AnimationTag).initEmpty();
            if (@hasField(@TypeOf(transitions), "any")) {
                for (transitions.any) |tag| map.insert(tag);
            }
            break :blk map;
        },

        pub fn setImageDefault(
            comptime self: *Self,
            img_tag: ImageTag,
            path: [:0]const u8,
            slice_method: ImageSliceMethod,
        ) void {
            self.image_defaults.put(img_tag, .{
                .path = path,
                .slice_method = slice_method,
            });
        }

        pub fn setAnimFrames(
            comptime self: *Self,
            tag: AnimationTag,
            comptime frame_groups: anytype,
            comptime durations: anytype,
        ) void {
            self.animations.put(tag, Animation.init(frame_groups, durations));
        }

        pub fn addTransition(
            comptime self: *Self,
            from: AnimationTag,
            to: AnimationTag,
        ) void {
            const vtrs: *std.EnumSet(AnimationTag) = self.valid_transitions.getPtr(from) orelse vtrs_blk: {
                self.valid_transitions.put(from, std.EnumSet(AnimationTag).initEmpty());
                break :vtrs_blk self.valid_transitions.getPtr(from).?;
            };
            vtrs.insert(to);
        }

        pub fn twoWayTransition(
            comptime self: *Self,
            from: AnimationTag,
            to: AnimationTag,
        ) void {
            self.transition(from, to);
            self.transition(to, from);
        }

        pub fn fromAnyTransition(
            comptime self: *Self,
            state: AnimationTag,
        ) void {
            self.from_any_transitions.insert(state);
        }

        pub fn allowAllTransitionsFromAny(
            comptime self: *Self,
        ) void {
            self.from_any_transitions = std.EnumSet(AnimationTag).initFull();
        }

        fn isValidTransition(comptime self: Self, from: AnimationTag, to: AnimationTag) bool {
            return self.from_any_transitions.contains(to) or
                (self.valid_transitions.get(from) orelse return false).contains(to);
        }

        pub fn Build(comptime self: Self, comptime default_anim: AnimationTag) type {
            //for (std.meta.fields(AnimationTag)) |field| {
            //    if (!self.animations.contains(@field(AnimationTag, field.name))) util.compileError("Animation data for animation {s} was never initialized", .{field.name});
            //}
            return Animator(Wrapper, Self, self, default_anim);
        }

        const Animation = struct {
            durations: Durations,
            frame_groups: []const FrameGroup,

            pub fn init(
                comptime frame_info: anytype,
                comptime durations_info: anytype,
            ) Animation {
                var frame_groups: [frame_info.len]FrameGroup = undefined;

                var current_frame: usize = 0;
                inline for (&frame_groups, frame_info) |*o, frame_group| {
                    o.* = FrameGroup.fromRaw(current_frame, frame_group);
                    current_frame += o.slice_indexes.len;
                }

                return .{
                    .frame_groups = &frame_groups,
                    .durations = blk: {
                        const ti = @typeInfo(@TypeOf(durations_info));
                        switch (ti) {
                            .Float, .ComptimeFloat, .Int, .ComptimeInt => break :blk .{ .single = durations_info },
                            else => {
                                if (ti == .Struct and ti.Struct.is_tuple) {
                                    break :blk .{ .per_frame = &durations_info };
                                } else {
                                    util.compileError("Animation expected either a number (0.4) or tuple of numbers (.{{ 0.1, 0.2, 0.6 }}) for durations, found {s}", .{@typeName(@TypeOf(durations_info))});
                                }
                            },
                        }
                    },
                };
            }
        };

        const Transition = struct {
            from: AnimationTag,
            to: AnimationTag,
        };

        const FrameGroup = struct {
            image_tag: ImageTag,
            slice_indexes: []const @Vector(2, usize),
            start_frame: usize,

            // this function expects a tuple of the form .{ .image, "0, 0", "0,1-3" }
            pub fn fromRaw(start_frame: usize, comptime raw: anytype) FrameGroup {
                var indexes = ztg.ComptimeList(@Vector(2, usize)){};

                comptime var i: usize = 1;
                while (i < raw.len) : (i += 1) {
                    var raw_str_iter = std.mem.tokenizeAny(u8, raw[i], " ,");
                    const x_str = raw_str_iter.next().?;
                    const y_str = raw_str_iter.next().?;

                    const x_is_range = std.mem.containsAtLeast(u8, x_str, 1, "-");
                    const y_is_range = std.mem.containsAtLeast(u8, y_str, 1, "-");

                    if (x_is_range and y_is_range) @compileError("Both components of frame range cannot be ranges.");

                    if (x_is_range or y_is_range) {
                        appendIndexRange(
                            &indexes,
                            if (x_is_range) x_str else y_str,
                            std.fmt.parseUnsigned(usize, if (x_is_range) y_str else x_str, 10) catch @compileError(""),
                            x_is_range,
                        );
                    } else {
                        indexes.append(.{
                            std.fmt.parseUnsigned(usize, x_str, 10) catch @compileError("Could not format x part of frame group string"),
                            std.fmt.parseUnsigned(usize, y_str, 10) catch @compileError("Could not format y part of frame group string"),
                        });
                    }
                }

                return .{
                    .image_tag = raw[0],
                    .slice_indexes = indexes.items,
                    .start_frame = start_frame,
                };
            }

            fn appendIndexRange(indexes: *ztg.ComptimeList(@Vector(2, usize)), str: []const u8, static_value: usize, x_is_range: bool) void {
                const range: [2]i32 = blk: {
                    var str_iter = std.mem.tokenizeScalar(u8, str, '-');

                    const bot = std.fmt.parseUnsigned(i32, str_iter.next().?, 10) catch @compileError("");
                    const top = std.fmt.parseUnsigned(i32, str_iter.next().?, 10) catch @compileError("");

                    break :blk .{ bot, top };
                };

                // use inclusive range
                const len = @abs(@as(i32, @intCast(range[1])) - @as(i32, @intCast(range[0]))) + 1;
                const dir = if (range[0] <= range[1]) 1 else -1;

                var i: i32 = 0;
                while (i < len) : (i += 1) {
                    if (x_is_range) {
                        indexes.append(.{ @intCast(range[0] + i * dir), static_value });
                    } else {
                        indexes.append(.{ static_value, @intCast(range[0] + i * dir) });
                    }
                }
            }
        };
    };
}

fn Animator(
    comptime Wrapper: type,
    comptime BuilderType: type,
    comptime builder_info: anytype,
    comptime default_anim: BuilderType.AnimationTag,
) type {
    const Animation = BuilderType.Animation;

    return struct {
        const Self = @This();

        pub const AnimationTag = BuilderType.AnimationTag;
        pub const ImageTag = BuilderType.ImageTag;
        const Images = std.EnumMap(ImageTag, SlicedImage);

        const SlicedImage = struct {
            img: Wrapper.Image,
            slice_method: ImageSliceMethod,
        };

        current_anim: AnimationTag = default_anim,
        images: Images,

        current_frame: usize = 0,
        frame_group: usize = 0,
        time: f32 = 0.0,

        use_real_time: bool = false,

        pub fn init(load_image_ctx: Wrapper.LoadImageCtx) !Self {
            var images: Images = .{};

            for (std.enums.values(ImageTag)) |tag| {
                if (builder_info.image_defaults.get(tag)) |img| {
                    images.put(tag, .{
                        .img = try Wrapper.loadImage(load_image_ctx, img.path),
                        .slice_method = img.slice_method,
                    });
                }
            }

            return .{
                .current_anim = default_anim,
                .images = images,
            };
        }

        pub fn transitionTo(self: *Self, anim: AnimationTag) error{ NullAnimationData, InvalidTransition }!void {
            if (self.current_anim == anim) return;

            if (!builder_info.isValidTransition(self.current_anim, anim)) return error.InvalidTransition;

            self.current_anim = anim;
            self.frame_group = 0;
            self.current_frame = 0;
            self.time = 0;
        }

        pub fn include(comptime wb: *ztg.WorldBuilder) void {
            wb.addComponents(&.{Self});
            wb.addSystemsToStage(.update, update);
        }

        fn update(q: ztg.Query(.{ Self, Wrapper.QueryType }), time: ztg.base.Time) void {
            for (q.items(0), q.items(1)) |self, qt| {
                const anim: Animation = builder_info.animations.get(self.current_anim).?;
                const frame_group = anim.frame_groups[self.frame_group];

                self.time += if (self.use_real_time) time.real_dt else time.dt;

                if (self.time > anim.durations.get(frame_group.start_frame + self.current_frame)) {
                    self.time = 0;
                    self.current_frame += 1;

                    if (self.current_frame >= frame_group.slice_indexes.len) {
                        self.current_frame = 0;
                        self.frame_group += 1;

                        if (self.frame_group >= anim.frame_groups.len) {
                            self.frame_group = 0;
                        }
                    }
                }

                if (comptime @hasDecl(Wrapper, "onFrame")) {
                    const sliced_img: SlicedImage = self.images.get(frame_group.image_tag).?;
                    Wrapper.onFrame(
                        sliced_img.img,
                        sliced_img.slice_method,
                        frame_group.slice_indexes[self.current_frame],
                        qt,
                    );
                }
            }
        }

        pub usingnamespace if (@hasDecl(Wrapper, "mixin")) Wrapper.mixin else struct {};
    };
}

pub fn AnimTagSpace(comptime Anim: type, comptime dimensions: usize, comptime defs: anytype) type {
    return ztg.EnumValueSpace(Anim.AnimationTag, dimensions, defs);
}
