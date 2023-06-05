const std = @import("std");
const ztg = @import("../init.zig");
const TypeBuilder = @import("../type_builder.zig");

fn Input(comptime input_wrapper: type, comptime Controller: type) type {
    return struct {
        const Self = @This();

        controllers: std.ArrayList(Controller),

        pub fn include(comptime wb: *ztg.WorldBuilder) !void {
            wb.addResource(Self, .{
                .controllers = undefined,
            });
            wb.addSystemsToStage(.pre_init, .{pri_input});
            wb.addSystemsToStage(.pre_update, .{pru_input});
        }

        fn pri_input(alloc: std.mem.Allocator, self: *Self) !void {
            self.controllers = std.ArrayList(Controller).init(alloc);
        }

        pub fn deinit(self: *Self) void {
            for (self.controllers.items) |c| {
                input_wrapper.deinitInstance(c);
            }

            self.controllers.deinit();
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
            for (axis.binds.items) |bind| {
                axis.value = try input_wrapper.getAxis(bind);
            }
        }

        fn updateButtonBinding(button: *input_wrapper.ButtonBinding) anyerror!void {
            for (button.binds.items) |bind| {
                button.pressed = try input_wrapper.getButtonPressed(bind);
                button.down = try input_wrapper.getButtonDown(bind);
                button.released = try input_wrapper.getButtonReleased(bind);
            }
        }

        const NewControllerDefaultBindings = struct {
            axes: []const struct { []const u8, input_wrapper.AxisType } = &.{},
            buttons: []const struct { []const u8, input_wrapper.ButtonType } = &.{},
        };

        pub fn newController(self: *Self, alloc: std.mem.Allocator, comptime default_bindings: NewControllerDefaultBindings) !void {
            var c = input_wrapper.initInstance(Controller, alloc);
            inline for (default_bindings.axes) |axis| {
                try bindAxisOf(&c, axis[0], axis[1]);
            }
            inline for (default_bindings.buttons) |button| {
                try bindButtonOf(&c, button[0], button[1]);
            }
            try self.controllers.append(c);
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

        pub fn bindButtonOf(c: *Controller, comptime button_name: []const u8, binding: input_wrapper.ButtonType) !void {
            try @field(c, button_name).binds.append(binding);
        }

        pub fn bindButton(self: *Self, controller_id: usize, comptime button_name: []const u8, binding: input_wrapper.ButtonType) !void {
            try bindButtonOf(&self.controllers.items[controller_id], button_name, binding);
        }

        pub fn bindAxisOf(c: *Controller, comptime axis_name: []const u8, binding: input_wrapper.AxisType) !void {
            try @field(c, axis_name).binds.append(binding);
        }

        pub fn bindAxis(self: *Self, controller_id: usize, comptime axis_name: []const u8, binding: input_wrapper.AxisType) !void {
            try bindAxisOf(&self.controllers.items[controller_id], axis_name, binding);
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
            binds: std.ArrayList(AxisType),
        };

        const ButtonBinding = struct {
            pressed: bool = false,
            down: bool = false,
            released: bool = false,
            binds: std.ArrayList(ButtonType),
        };

        pub fn new() Self {
            return .{
                .def = TypeBuilder.new(false, .Auto),
            };
        }

        pub fn addAxes(comptime self: *Self, comptime axes: []const []const u8) void {
            for (axes) |ax| {
                self.def.addField(ax, AxisBinding, null);
            }
        }

        pub fn addButtons(comptime self: *Self, comptime buttons: []const []const u8) void {
            for (buttons) |button| {
                self.def.addField(button, ButtonBinding, null);
            }
        }

        pub fn BuildInput(comptime self: Self) type {
            return Input(Self, self.def.Build());
        }

        pub fn initInstance(comptime T: type, alloc: std.mem.Allocator) T {
            var t: T = undefined;
            inline for (std.meta.fields(T)) |field| {
                if (field.type == AxisBinding) {
                    @field(t, field.name) = AxisBinding{
                        .binds = std.ArrayList(AxisType).init(alloc),
                    };
                } else {
                    @field(t, field.name) = ButtonBinding{
                        .binds = std.ArrayList(ButtonType).init(alloc),
                    };
                }
            }
            return t;
        }

        pub fn deinitInstance(ins: anytype) void {
            inline for (std.meta.fields(@TypeOf(ins))) |field| {
                @field(ins, field.name).binds.deinit();
            }
        }
    };
}
