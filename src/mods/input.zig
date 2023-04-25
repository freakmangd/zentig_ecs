const std = @import("std");
const ztg = @import("../ecs.zig");
const TypeBuilder = @import("../type_builder.zig");

fn Input(comptime input_wrapper: type, comptime Controller: type) type {
    return struct {
        const Self = @This();

        controllers: std.ArrayList(Controller),

        pub fn include(comptime wb: *ztg.WorldBuilder) !void {
            wb.addResource(Self, .{
                .controllers = undefined,
            });
            wb.addSystemsToStage(ztg.stages.pre_init, .{pri_input});
            wb.addSystemsToStage(ztg.stages.pre_update, .{pru_input});
        }

        fn pri_input(alloc: std.mem.Allocator, self: *Self) !void {
            self.controllers = std.ArrayList(Controller).init(alloc);
        }

        fn pru_input(self: *Self) anyerror!void {
            for (self.controllers.items) |*ct| {
                inline for (std.meta.fields(Controller)) |field| {
                    switch (field.type) {
                        input_wrapper.AxisBinding => try updateAxisBinding(&@field(ct, field.name)),
                        input_wrapper.ButtonBinding => try updateButtonBinding(&@field(ct, field.name)),
                        else => @compileError("Controller's fields should not contain any types other than AxisBinding and ButtonBinding"),
                    }
                }
            }
        }

        fn updateAxisBinding(axis: *input_wrapper.AxisBinding) anyerror!void {
            if (axis.bind) |bind| {
                axis.value = try input_wrapper.getAxis(bind);
            }
        }

        fn updateButtonBinding(button: *input_wrapper.ButtonBinding) anyerror!void {
            if (button.bind) |bind| {
                button.pressed = try input_wrapper.getButtonPressed(bind);
                button.down = try input_wrapper.getButtonDown(bind);
                button.released = try input_wrapper.getButtonReleased(bind);
            }
        }

        pub fn newController(self: *Self) !void {
            try self.controllers.append(.{});
        }

        pub fn importBindings(self: *Self, bindings: []const u8) !void {
            _ = bindings;
            _ = self;
            @compileError("UNIMPLEMENTED");
        }

        pub fn exportBindings(self: Self, buffer: []u8) !void {
            _ = buffer;
            _ = self;
            @compileError("UNIMPLEMENTED");
        }

        pub fn bindButton(self: *Self, controller_id: usize, comptime button_name: []const u8, binding: input_wrapper.ButtonType) void {
            @field(self.controllers.items[controller_id], button_name).bind = binding;
        }

        pub fn bindAxis(self: *Self, controller_id: usize, comptime axis_name: []const u8, binding: input_wrapper.AxisType) void {
            @field(self.controllers.items[controller_id], axis_name).bind = binding;
        }

        pub fn getAxis(self: Self, controller_id: usize, comptime axis_name: []const u8) f32 {
            return @field(self.controllers.items[controller_id], axis_name).value;
        }

        pub fn getButtonPressed(self: Self, controller_id: usize, comptime button_name: []const u8) bool {
            return @field(self.controllers.items[controller_id], button_name).pressed;
        }

        pub fn getButtonDown(self: Self, controller_id: usize, comptime button_name: []const u8) bool {
            return @field(self.controllers.items[controller_id], button_name).down;
        }

        pub fn getButtonReleased(self: Self, controller_id: usize, comptime button_name: []const u8) bool {
            return @field(self.controllers.items[controller_id], button_name).released;
        }
    };
}

pub fn ControllerBuilder(comptime input_wrapper: type) type {
    return struct {
        const Self = @This();

        const ButtonType = input_wrapper.ButtonType;
        const AxisType = input_wrapper.AxisType;

        const getAxis = input_wrapper.getAxis;
        const getButtonPressed = input_wrapper.getButtonPressed;
        const getButtonDown = input_wrapper.getButtonDown;
        const getButtonReleased = input_wrapper.getButtonReleased;

        def: TypeBuilder,

        const AxisBinding = struct {
            value: f32 = 0.0,
            bind: ?AxisType = null,
        };

        const ButtonBinding = struct {
            pressed: bool = false,
            down: bool = false,
            released: bool = false,
            bind: ?ButtonType = null,
        };

        pub fn new() Self {
            return .{
                .def = TypeBuilder.new(false, .Auto),
            };
        }

        pub fn addAxes(comptime self: *Self, comptime axes: []const []const u8) void {
            for (axes) |ax| {
                self.def = self.def.addField(ax, AxisBinding, &AxisBinding{});
            }
        }

        pub fn addButtons(comptime self: *Self, comptime buttons: []const u8) void {
            self.def = self.def.addField(buttons, ButtonBinding, &ButtonBinding{});
        }

        pub fn BuildInput(comptime self: Self) type {
            return Input(Self, self.def.Build());
        }
    };
}
