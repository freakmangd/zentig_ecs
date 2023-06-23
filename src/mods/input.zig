const std = @import("std");
const ztg = @import("../init.zig");

const Options = struct {
    max_controllers: usize = 4,
    update_stage: @TypeOf(.enum_literal) = .pre_update,
};

pub fn Input(
    comptime Wrapper: type,
    comptime button_literals: anytype,
    comptime axis_literals: anytype,
    comptime options: Options,
) type {
    const Buttons = EnumFromLiterals(button_literals);
    const Axes = EnumFromLiterals(axis_literals);
    const Controller = ControllerBuilder(Buttons, Axes, Wrapper.ButtonType, Wrapper.AxisType);

    const ButtonBindings = blk: {
        var buttons_tb = ztg.util.TypeBuilder.init(false, .Auto);
        inline for (button_literals) |b| {
            buttons_tb.addField(@tagName(b), []const Wrapper.ButtonType, @ptrCast(?*const anyopaque, &@as([]const Wrapper.ButtonType, &.{})));
        }
        break :blk buttons_tb.Build();
    };

    const AxesBindings = blk: {
        var axes_tb = ztg.util.TypeBuilder.init(false, .Auto);
        inline for (axis_literals) |a| {
            axes_tb.addField(@tagName(a), []const Wrapper.AxisType, @ptrCast(?*const anyopaque, &@as([]const Wrapper.AxisType, &.{})));
        }
        break :blk axes_tb.Build();
    };

    const AddBindings = struct {
        buttons: ButtonBindings,
        axes: AxesBindings,
    };

    return struct {
        const Self = @This();

        alloc: std.mem.Allocator = undefined,
        controllers: [options.max_controllers]Controller = undefined,

        pub fn addBindings(self: *Self, controller: usize, bindings: AddBindings) !void {
            try self.addButtonBindings(controller, bindings.buttons);
            try self.addAxisBindings(controller, bindings.axes);
        }

        pub fn addButtonBinding(self: *Self, controller: usize, button: Buttons, binding: Wrapper.ButtonType) !void {
            try self.controllers[controller].button_bindings.append(self.alloc, .{
                .index = @intFromEnum(button),
                .binding = binding,
            });
        }

        pub fn addButtonBindings(self: *Self, controller: usize, bindings: ButtonBindings) !void {
            inline for (@typeInfo(ButtonBindings).Struct.fields) |field| {
                for (@field(bindings, field.name)) |b| {
                    try self.addButtonBinding(controller, @field(Buttons, field.name), b);
                }
            }
        }

        pub fn addAxisBinding(self: *Self, controller: usize, axis: Axes, binding: Wrapper.AxisType) !void {
            try self.controllers[controller].axis_bindings.append(self.alloc, .{
                .index = @intFromEnum(axis),
                .binding = binding,
            });
        }

        pub fn addAxisBindings(self: *Self, controller: usize, bindings: AxesBindings) !void {
            inline for (@typeInfo(AxesBindings).Struct.fields) |field| {
                for (@field(bindings, field.name)) |a| {
                    try self.addAxisBinding(controller, @field(Axes, field.name), a);
                }
            }
        }

        pub inline fn isButtonDown(self: Self, controller: usize, button: Buttons) bool {
            return self.controllers[controller].buttons.isSet(@intFromEnum(button) * 3);
        }

        pub inline fn isButtonPressed(self: Self, controller: usize, button: Buttons) bool {
            return self.controllers[controller].buttons.isSet((@intFromEnum(button) * 3) + 1);
        }

        pub inline fn isButtonReleased(self: Self, controller: usize, button: Buttons) bool {
            return self.controllers[controller].buttons.isSet((@intFromEnum(button) * 3) + 2);
        }

        pub inline fn getAxis(self: Self, controller: usize, axis: Axes) f32 {
            return self.controllers[controller].axes[@intFromEnum(axis)];
        }

        pub fn include(comptime wb: *ztg.WorldBuilder) void {
            wb.addResource(Self, .{});
            wb.addSystemsToStage(.setup, .{setup_Self});
            wb.addSystemsToStage(options.update_stage, .{pru_Self});
            wb.addSystemsToStage(.cleanup, .{cleanup_Self});
        }

        fn setup_Self(self: *Self, alloc: std.mem.Allocator) void {
            for (&self.controllers) |*c| {
                c.* = Controller.init();
            }

            self.alloc = alloc;
        }

        fn pru_Self(self: *Self) void {
            for (&self.controllers) |*ct| {
                for (ct.button_bindings.items) |bb| {
                    const is_down = Wrapper.isButtonDown(bb.binding);
                    const is_pres = Wrapper.isButtonPressed(bb.binding);
                    const is_rel = Wrapper.isButtonReleased(bb.binding);
                    ct.buttons.setValue(@as(usize, bb.index) * 3, is_down);
                    ct.buttons.setValue(@as(usize, bb.index) * 3 + 1, is_pres);
                    ct.buttons.setValue(@as(usize, bb.index) * 3 + 2, is_rel);
                }
                for (ct.axis_bindings.items) |ab| {
                    const value = Wrapper.getAxis(ab.binding);
                    ct.axes[ab.index] = value;
                }
            }
        }

        fn cleanup_Self(self: *Self) void {
            for (&self.controllers) |*con| {
                con.button_bindings.deinit(self.alloc);
                con.axis_bindings.deinit(self.alloc);
            }
        }
    };
}

fn ControllerBuilder(
    comptime Buttons: type,
    comptime Axes: type,
    comptime ButtonType: type,
    comptime AxisType: type,
) type {
    const buttons_len = @typeInfo(Buttons).Enum.fields.len;
    const axes_len = @typeInfo(Axes).Enum.fields.len;

    const ButtonBinding = struct {
        index: std.math.IntFittingRange(0, buttons_len),
        binding: ButtonType,
    };

    const AxisBinding = struct {
        index: std.math.IntFittingRange(0, axes_len),
        binding: AxisType,
    };

    return struct {
        const Self = @This();

        buttons: std.StaticBitSet(buttons_len * 3),
        button_bindings: std.ArrayListUnmanaged(ButtonBinding),

        axes: [axes_len]f32,
        axis_bindings: std.ArrayListUnmanaged(AxisBinding),

        pub fn init() Self {
            var self = Self{
                .buttons = std.StaticBitSet(buttons_len * 3).initEmpty(),
                .axes = undefined,

                .button_bindings = .{},
                .axis_bindings = .{},
            };

            for (&self.axes) |*ax| {
                ax.* = 0.0;
            }

            return self;
        }
    };
}

fn EnumFromLiterals(comptime literals: anytype) type {
    return comptime blk: {
        var enum_fields: []const std.builtin.Type.EnumField = &.{};

        inline for (literals, 0..) |lit, i| {
            enum_fields = enum_fields ++ [1]std.builtin.Type.EnumField{.{
                .name = @tagName(lit),
                .value = i,
            }};
        }

        break :blk @Type(std.builtin.Type{ .Enum = .{
            .fields = enum_fields,
            .is_exhaustive = true,
            .tag_type = std.math.IntFittingRange(0, literals.len),
            .decls = &.{},
        } });
    };
}
