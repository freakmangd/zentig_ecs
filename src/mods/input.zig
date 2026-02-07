const std = @import("std");
const ztg = @import("../init.zig");
const log = std.log.scoped(.zentig_input);

const Options = struct {
    max_controllers: usize = 4,
    update_stage: struct {
        stage: @EnumLiteral() = .pre_update,
        label: @EnumLiteral() = .body,
        order: ztg.SystemOrder = .during,
    } = .{},
};

pub fn Build(
    comptime Wrapper: type,
    comptime ButtonEnum: type,
    comptime AxisEnum: type,
    comptime options: Options,
) type {
    const ButtonBindings = blk: {
        break :blk @Struct(
            .auto,
            null,
            std.meta.fieldNames(ButtonEnum),
            &@splat([]const Wrapper.ButtonType),
            &@splat(.{ .default_value_ptr = @ptrCast(&@as([]const Wrapper.ButtonType, &.{})) }),
        );
    };

    const AxesBindings = blk: {
        break :blk @Struct(
            .auto,
            null,
            std.meta.fieldNames(AxisEnum),
            &@splat([]const Wrapper.AxisType),
            &@splat(.{ .default_value_ptr = @ptrCast(&@as([]const Wrapper.AxisType, &.{})) }),
        );
    };

    const AddBindings = struct {
        buttons: ButtonBindings = .{},
        axes: AxesBindings = .{},
    };

    const buttons_len = @typeInfo(ButtonEnum).@"enum".fields.len;
    const axes_len = @typeInfo(AxisEnum).@"enum".fields.len;

    const ButtonBinding = struct {
        index: std.math.IntFittingRange(0, buttons_len),
        binding: Wrapper.ButtonType,
    };

    const AxisBinding = struct {
        index: std.math.IntFittingRange(0, axes_len),
        binding: Wrapper.AxisType,
    };

    return struct {
        const Input = @This();

        pub const Controller = struct {
            source: Wrapper.InputSource,
            buttons: std.StaticBitSet(buttons_len * 3) = .initEmpty(),
            axes: [axes_len]f32 = .{0.0} ** axes_len,

            pub fn isDown(controller: *const @This(), button: ButtonEnum) bool {
                return controller.buttons.isSet(@as(usize, @intCast(@intFromEnum(button))) * 3);
            }

            pub fn isPressed(controller: *const @This(), button: ButtonEnum) bool {
                return controller.buttons.isSet((@as(usize, @intCast(@intFromEnum(button))) * 3) + 1);
            }

            pub fn isReleased(controller: *const @This(), button: ButtonEnum) bool {
                return controller.buttons.isSet((@as(usize, @intCast(@intFromEnum(button))) * 3) + 2);
            }

            pub fn getAxis(controller: *const @This(), axis: AxisEnum) f32 {
                return controller.axes[@intFromEnum(axis)];
            }

            pub fn getVector(controller: *const @This(), x_axis: AxisEnum, y_axis: AxisEnum) ztg.Vec2 {
                return .init(controller.getAxis(x_axis), controller.getAxis(y_axis));
            }
        };

        pub const Buttons = ButtonEnum;
        pub const Axes = AxisEnum;

        alloc: std.mem.Allocator,

        controllers: [options.max_controllers]Controller,
        next_controller: usize = 0,

        button_bindings: std.ArrayList(ButtonBinding) = .empty,
        axis_bindings: std.ArrayList(AxisBinding) = .empty,

        /// Returns null when max controllers have been given out
        pub fn connectController(self: *Input, source: Wrapper.InputSource) ?*Controller {
            if (self.next_controller == self.controllers.len)
                return null;

            self.controllers[self.next_controller] = .{ .source = source };

            defer self.next_controller += 1;
            return &self.controllers[self.next_controller];
        }

        pub fn addBindings(self: *Input, bindings: AddBindings) !void {
            try self.addButtonBindings(bindings.buttons);
            try self.addAxisBindings(bindings.axes);
        }

        pub fn addButtonBinding(self: *Input, button: ButtonEnum, binding: Wrapper.ButtonType) !void {
            try self.button_bindings.append(self.alloc, .{
                .index = @intFromEnum(button),
                .binding = binding,
            });
        }

        pub fn addButtonBindings(self: *Input, bindings: ButtonBindings) !void {
            inline for (@typeInfo(ButtonBindings).@"struct".fields) |field| {
                for (@field(bindings, field.name)) |b| {
                    try self.addButtonBinding(@field(ButtonEnum, field.name), b);
                }
            }
        }

        pub fn addAxisBinding(self: *Input, axis: AxisEnum, binding: Wrapper.AxisType) !void {
            try self.axis_bindings.append(self.alloc, .{
                .index = @intFromEnum(axis),
                .binding = binding,
            });
        }

        pub fn addAxisBindings(self: *Input, bindings: AxesBindings) !void {
            inline for (@typeInfo(AxesBindings).@"struct".fields) |field| {
                for (@field(bindings, field.name)) |a| {
                    try self.addAxisBinding(@field(AxisEnum, field.name), a);
                }
            }
        }

        pub fn clearBindings(self: *Input) void {
            self.clearButtonBindings();
            self.clearAxisBindings();
        }

        pub fn clearButtonBindings(self: *Input) void {
            self.button_bindings.clearRetainingCapacity();
        }

        pub fn clearAxisBindings(self: *Input) void {
            self.axis_bindings.clearRetainingCapacity();
        }

        /// Writes controller bindings to a file
        pub fn exportBindings(self: Input, file_name: []const u8) !void {
            var file = try std.fs.cwd().createFile(file_name, .{ .truncate = true });
            defer file.close();

            try self.writeBindings(file.writer());
        }

        pub fn writeBindings(self: Input, writer: *std.Io.Writer) !void {
            try writer.print("buttons:\n", .{});
            for (self.button_bindings.items) |bb| {
                try writer.print("{s}=", .{@tagName(@as(ButtonEnum, @enumFromInt(bb.index)))});
                try Wrapper.exportButtonBinding(writer, bb.binding);
                try writer.print("\n", .{});
            }

            try writer.print("axes:\n", .{});
            for (self.axis_bindings.items) |ab| {
                try writer.print("{s}=", .{@tagName(@as(AxisEnum, @enumFromInt(ab.index)))});
                try Wrapper.exportAxisBinding(writer, ab.binding);
                try writer.print("\n", .{});
            }
        }

        /// Tries to find the controller bindings file, returns true if it is and imported correctly.
        /// Use this to check for bindings before appending defaults.
        pub fn importBindings(self: *Input, io: std.Io, file_name: []const u8) bool {
            var file = std.Io.Dir.cwd().openFile(file_name, .{}) catch |err| switch (err) {
                error.FileNotFound => {
                    log.info("Could not find bindings file.", .{});
                    return false;
                },
                else => {
                    log.err("Could not open bindings file due to: {}", .{err});
                    return false;
                },
            };
            defer file.close();

            defer if (self.button_bindings.items.len + self.axis_bindings.items.len == 0) {
                log.warn("Found 0 bindings after importing file.", .{});
            };
            var buf: [1024]u8 = undefined;
            var reader = file.reader(io, &buf);
            return self.readBindings(&reader.interface);
        }

        pub fn readBindings(self: *Input, reader: *std.Io.Reader) bool {
            self.clearBindings();
            const res = self.readBindingsInternal(reader);
            if (!res) self.clearBindings();
            return res;
        }

        fn readBindingsInternal(self: *Input, reader: *std.Io.Reader) bool {
            var current_controller: usize = 0;
            var read_mode: enum {
                buttons,
                axes,
            } = .buttons;
            var line_number: usize = 0;

            while (reader.takeDelimiter('\n') catch |err| {
                log.err("Cound not import bindings due to {}", .{err});
                return false;
            }) |line| : (line_number += 1) {
                if (std.mem.startsWith(u8, line, "controller")) {
                    const end_idx = std.mem.indexOf(u8, line, ":") orelse {
                        log.err("Malformed bindings file, no `:` character after controller index.", .{});
                        return false;
                    };
                    current_controller = std.fmt.parseInt(usize, line[11..end_idx], 10) catch |err| {
                        log.err("Could not parse controller index integer due to {}", .{err});
                        return false;
                    };
                    read_mode = .buttons;
                } else if (std.mem.startsWith(u8, line, "axes:")) {
                    read_mode = .axes;
                } else {
                    const binding_tag, const binding_text = getTagAndInfo(line) catch {
                        log.warn("Malformed line in bindings file at line {}", .{line_number});
                        continue;
                    };

                    const ButtonIndex = std.math.IntFittingRange(0, std.meta.fields(ButtonEnum).len);
                    const AxisIndex = std.math.IntFittingRange(0, std.meta.fields(AxisEnum).len);

                    switch (read_mode) {
                        .buttons => {
                            const binding_index = @intFromEnum(std.meta.stringToEnum(ButtonEnum, binding_tag) orelse {
                                log.warn("Unrecognized button binding {s} in bindings file.", .{binding_tag});
                                continue;
                            });
                            self.button_bindings.append(self.alloc, .{
                                .index = std.math.cast(ButtonIndex, binding_index) orelse {
                                    log.err("Index of button binding exceeded max range. Max: {}, Found {}", .{ std.meta.fields(ButtonEnum).len, binding_index });
                                    continue;
                                },
                                .binding = Wrapper.importButtonBinding(binding_text) catch |err| {
                                    log.err("Could not import button binding due to {}", .{err});
                                    continue;
                                },
                            }) catch |err| {
                                log.err("Could not append to button bindings due to {}", .{err});
                                continue;
                            };
                        },
                        .axes => {
                            const binding_index = @intFromEnum(std.meta.stringToEnum(AxisEnum, binding_tag) orelse {
                                log.warn("Unrecognized axis binding {s} in bindings file.", .{binding_tag});
                                continue;
                            });
                            self.axis_bindings.append(self.alloc, .{
                                .index = std.math.cast(AxisIndex, binding_index) orelse {
                                    log.err("Index of axis binding exceeded max range. Max: {}, Found: {}", .{ std.meta.fields(AxisEnum).len, binding_index });
                                    continue;
                                },
                                .binding = Wrapper.importAxisBinding(binding_text) catch |err| {
                                    log.err("Could not import axis binding due to {}", .{err});
                                    continue;
                                },
                            }) catch |err| {
                                log.err("Could not append to button bindings due to {}", .{err});
                                continue;
                            };
                        },
                    }
                }
            }

            log.info("importing bindings: Finished successfully", .{});
            return true;
        }

        fn getTagAndInfo(line: []const u8) !struct { []const u8, []const u8 } {
            const eqls_idx = std.mem.indexOf(u8, line, "=") orelse {
                log.err("Bad formatted bindings file, no `=` character on binding line.", .{});
                return error.BadFormat;
            };
            return .{ line[0..eqls_idx], line[eqls_idx + 1 ..] };
        }

        pub fn include(comptime wb: *ztg.WorldBuilder) void {
            wb.addResource(Input, .{
                .alloc = undefined,
                .controllers = undefined,
            });
            wb.addSystems(.{
                .init = .{ini_Self},
                .deinit = .{dei_Self},
            });
            wb.addSystemsToStage(options.update_stage.stage, .{ztg.ordered(options.update_stage.label, update_Self, options.update_stage.order)});
        }

        fn ini_Self(self: *Input, alloc: std.mem.Allocator) void {
            self.alloc = alloc;
        }

        fn update_Self(self: *Input) void {
            for (self.controllers[0..self.next_controller]) |*ct| {
                if (comptime std.meta.fields(ButtonEnum).len > 0) {
                    ct.buttons = .initEmpty();

                    for (self.button_bindings.items) |bb| {
                        if (Wrapper.isButtonDown(ct.source, bb.binding)) ct.buttons.set(@as(usize, bb.index) * 3);
                        if (Wrapper.isButtonPressed(ct.source, bb.binding)) ct.buttons.set(@as(usize, bb.index) * 3 + 1);
                        if (Wrapper.isButtonReleased(ct.source, bb.binding)) ct.buttons.set(@as(usize, bb.index) * 3 + 2);
                    }
                }
                if (comptime std.meta.fields(AxisEnum).len > 0) {
                    for (self.axis_bindings.items) |ab| {
                        ct.axes[ab.index] = 0;

                        const value = Wrapper.getAxis(ct.source, ab.binding);
                        if (@abs(value) > @abs(ct.axes[ab.index])) ct.axes[ab.index] = value;
                    }
                }
            }
        }

        fn dei_Self(self: *Input) void {
            self.button_bindings.deinit(self.alloc);
            self.axis_bindings.deinit(self.alloc);
        }
    };
}
