const std = @import("std");
const ztg = @import("../init.zig");
const log = std.log.scoped(.zentig_input);

const Options = struct {
    max_controllers: usize = 4,
    update_stage: struct {
        stage: ztg.meta.EnumLiteral = .pre_update,
        label: ztg.meta.EnumLiteral = .body,
        order: ztg.SystemOrder = .during,
    } = .{},
};

pub fn Build(
    comptime Wrapper: type,
    comptime Button: type,
    comptime Axis: type,
    comptime options: Options,
) type {
    const ButtonBindings = blk: {
        var buttons_struct_fields: [std.meta.fields(Button).len]std.builtin.Type.StructField = undefined;
        for (&buttons_struct_fields, std.enums.values(Button)) |*field, a| {
            field.* = std.builtin.Type.StructField{
                .name = @tagName(a),
                .type = []const Wrapper.ButtonType,
                .alignment = @alignOf([]const Wrapper.ButtonType),
                .is_comptime = false,
                .default_value_ptr = @ptrCast(&@as([]const Wrapper.ButtonType, &.{})),
            };
        }
        break :blk @Type(.{ .@"struct" = .{
            .fields = &buttons_struct_fields,
            .decls = &.{},
            .layout = .auto,
            .is_tuple = false,
        } });
    };

    const AxesBindings = blk: {
        var axes_struct_fields: [std.meta.fields(Axis).len]std.builtin.Type.StructField = undefined;
        for (&axes_struct_fields, std.enums.values(Axis)) |*field, a| {
            field.* = std.builtin.Type.StructField{
                .name = @tagName(a),
                .type = []const Wrapper.AxisType,
                .alignment = 0,
                .is_comptime = false,
                .default_value_ptr = @ptrCast(&@as([]const Wrapper.AxisType, &.{})),
            };
        }
        break :blk @Type(.{ .@"struct" = .{
            .fields = &axes_struct_fields,
            .decls = &.{},
            .layout = .auto,
            .is_tuple = false,
        } });
    };

    const AddBindings = struct {
        buttons: ButtonBindings = .{},
        axes: AxesBindings = .{},
    };

    return struct {
        const Controller = ControllerBuilder(Button, Axis, Wrapper.ButtonType, Wrapper.AxisType);
        const Self = @This();

        pub const Buttons = Button;
        pub const Axes = Axis;

        alloc: std.mem.Allocator = undefined,
        controllers: [options.max_controllers]Controller = undefined,

        pub fn addBindings(self: *Self, controller: usize, bindings: AddBindings) !void {
            try self.addButtonBindings(controller, bindings.buttons);
            try self.addAxisBindings(controller, bindings.axes);
        }

        pub fn addButtonBinding(self: *Self, controller: usize, button: Button, binding: Wrapper.ButtonType) !void {
            try self.controllers[controller].button_bindings.append(self.alloc, .{
                .index = @intFromEnum(button),
                .binding = binding,
            });
        }

        pub fn addButtonBindings(self: *Self, controller: usize, bindings: ButtonBindings) !void {
            inline for (@typeInfo(ButtonBindings).@"struct".fields) |field| {
                for (@field(bindings, field.name)) |b| {
                    try self.addButtonBinding(controller, @field(Button, field.name), b);
                }
            }
        }

        pub fn addAxisBinding(self: *Self, controller: usize, axis: Axis, binding: Wrapper.AxisType) !void {
            try self.controllers[controller].axis_bindings.append(self.alloc, .{
                .index = @intFromEnum(axis),
                .binding = binding,
            });
        }

        pub fn addAxisBindings(self: *Self, controller: usize, bindings: AxesBindings) !void {
            inline for (@typeInfo(AxesBindings).@"struct".fields) |field| {
                for (@field(bindings, field.name)) |a| {
                    try self.addAxisBinding(controller, @field(Axis, field.name), a);
                }
            }
        }

        pub fn clearAllBindings(self: *Self) void {
            for (0..self.controllers.len) |c| self.clearBindings(c);
        }

        pub fn clearBindings(self: *Self, controller: usize) void {
            self.clearButtonBindings(controller);
            self.clearAxisBindings(controller);
        }

        pub fn clearButtonBindings(self: *Self, controller: usize) void {
            self.controllers[controller].button_bindings.clearRetainingCapacity();
        }

        pub fn clearAxisBindings(self: *Self, controller: usize) void {
            self.controllers[controller].axis_bindings.clearRetainingCapacity();
        }

        pub fn isDown(self: Self, controller: usize, button: Button) bool {
            return self.controllers[controller].buttons.isSet(@as(usize, @intCast(@intFromEnum(button))) * 3);
        }

        pub fn isPressed(self: Self, controller: usize, button: Button) bool {
            return self.controllers[controller].buttons.isSet((@as(usize, @intCast(@intFromEnum(button))) * 3) + 1);
        }

        pub fn isReleased(self: Self, controller: usize, button: Button) bool {
            return self.controllers[controller].buttons.isSet((@as(usize, @intCast(@intFromEnum(button))) * 3) + 2);
        }

        pub fn getAxis(self: Self, controller: usize, axis: Axis) f32 {
            return self.controllers[controller].axes[@intFromEnum(axis)];
        }

        /// Writes controller bindings to a file
        pub fn exportBindings(self: Self, file_name: []const u8) !void {
            var file = try std.fs.cwd().createFile(file_name, .{ .truncate = true });
            defer file.close();

            try self.writeBindings(file.writer());
        }

        pub fn writeBindings(self: Self, writer: anytype) !void {
            for (self.controllers, 0..) |contr, i| {
                try writer.print("controller {}:\n", .{i});
                for (contr.button_bindings.items) |bb| {
                    try writer.print("{s}=", .{@tagName(@as(Button, @enumFromInt(bb.index)))});
                    try Wrapper.exportButtonBinding(writer, bb.binding);
                    try writer.print("\n", .{});
                }

                try writer.print("axes:\n", .{});
                for (contr.axis_bindings.items) |ab| {
                    try writer.print("{s}=", .{@tagName(@as(Axis, @enumFromInt(ab.index)))});
                    try Wrapper.exportAxisBinding(writer, ab.binding);
                    try writer.print("\n", .{});
                }
            }
        }

        /// Tries to find the controller bindings file, returns true if it is and imported correctly.
        /// Use this to check for bindings before appending defaults.
        pub fn importBindings(self: *Self, file_name: []const u8) bool {
            var file = std.fs.cwd().openFile(file_name, .{}) catch |err| switch (err) {
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

            defer for (self.controllers) |c| {
                if (c.button_bindings.items.len + c.axis_bindings.items.len == 0)
                    log.warn("Found 0 bindings for controller {} after importing file.", .{c});
            };
            return self.readBindings(file.reader());
        }

        pub fn readBindings(self: *Self, reader: anytype) bool {
            self.clearAllBindings();
            const res = self.importBindingsInternal(reader);
            if (!res) self.clearAllBindings();
            return res;
        }

        fn importBindingsInternal(self: *Self, reader: anytype) bool {
            var current_controller: usize = 0;
            var read_mode: enum {
                buttons,
                axes,
            } = .buttons;

            const max_line_size = 200;
            var line_buf: [max_line_size]u8 = undefined;
            var file_bufferstream = std.io.fixedBufferStream(&line_buf);

            var safety: usize = 0;

            while (reader.streamUntilDelimiter(file_bufferstream.writer(), '\n', max_line_size)) : (safety += 1) {
                if (safety > 1_000) {
                    log.err("Hit loop limit for import of 1000 iterations", .{});
                    return false;
                }

                defer file_bufferstream.reset();
                const line = line_buf[0..file_bufferstream.pos];

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
                        log.warn("Malformed line in bindings file at line {}", .{safety});
                        continue;
                    };

                    const ButtonIndex = std.math.IntFittingRange(0, std.meta.fields(Button).len);
                    const AxisIndex = std.math.IntFittingRange(0, std.meta.fields(Axis).len);

                    switch (read_mode) {
                        .buttons => {
                            const binding_index = @intFromEnum(std.meta.stringToEnum(Button, binding_tag) orelse {
                                log.warn("Unrecognized button binding {s} in bindings file.", .{binding_tag});
                                continue;
                            });
                            self.controllers[current_controller].button_bindings.append(self.alloc, .{
                                .index = std.math.cast(ButtonIndex, binding_index) orelse {
                                    log.err("Index of button binding exceeded max range. Max: {}, Found {}", .{ std.meta.fields(Button).len, binding_index });
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
                            const binding_index = @intFromEnum(std.meta.stringToEnum(Axis, binding_tag) orelse {
                                log.warn("Unrecognized axis binding {s} in bindings file.", .{binding_tag});
                                continue;
                            });
                            self.controllers[current_controller].axis_bindings.append(self.alloc, .{
                                .index = std.math.cast(AxisIndex, binding_index) orelse {
                                    log.err("Index of axis binding exceeded max range. Max: {}, Found: {}", .{ std.meta.fields(Axis).len, binding_index });
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
            } else |err| switch (err) {
                error.EndOfStream => {
                    log.info("importing bindings: Hit end of stream", .{});
                },
                else => {
                    log.err("Cound not import bindings due to {}", .{err});
                    return false;
                },
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
            wb.addResource(Self, .{});
            wb.addSystems(.{
                .init = .{ini_Self},
                .deinit = .{dei_Self},
            });
            wb.addSystemsToStage(options.update_stage.stage, .{ztg.ordered(options.update_stage.label, update_Self, options.update_stage.order)});
        }

        fn ini_Self(self: *Self, alloc: std.mem.Allocator) void {
            for (&self.controllers) |*c| {
                c.* = .{};
            }

            self.alloc = alloc;
        }

        fn update_Self(self: *Self) void {
            for (&self.controllers) |*ct| {
                if (comptime std.meta.fields(Button).len > 0) {
                    ct.buttons = Controller.ButtonsBitSet.initEmpty();
                }
                if (comptime std.meta.fields(Axis).len > 0) {
                    for (ct.axis_bindings.items) |ab| ct.axes[ab.index] = 0;
                }
            }
            for (&self.controllers, 0..) |*ct, ci| {
                if (comptime std.meta.fields(Button).len > 0) {
                    for (ct.button_bindings.items) |bb| {
                        if (Wrapper.isButtonDown(ci, bb.binding)) ct.buttons.set(@as(usize, bb.index) * 3);
                        if (Wrapper.isButtonPressed(ci, bb.binding)) ct.buttons.set(@as(usize, bb.index) * 3 + 1);
                        if (Wrapper.isButtonReleased(ci, bb.binding)) ct.buttons.set(@as(usize, bb.index) * 3 + 2);
                    }
                }
                if (comptime std.meta.fields(Axis).len > 0) {
                    for (ct.axis_bindings.items) |ab| {
                        const value = Wrapper.getAxis(ci, ab.binding);
                        if (@abs(value) > @abs(ct.axes[ab.index])) ct.axes[ab.index] = value;
                    }
                }
            }
        }

        fn dei_Self(self: *Self) void {
            for (&self.controllers) |*con| {
                if (comptime std.meta.fields(Button).len > 0) con.button_bindings.deinit(self.alloc);
                if (comptime std.meta.fields(Axis).len > 0) con.axis_bindings.deinit(self.alloc);
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
    const buttons_len = @typeInfo(Buttons).@"enum".fields.len;
    const axes_len = @typeInfo(Axes).@"enum".fields.len;

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
        pub const ButtonsBitSet: type = std.StaticBitSet(buttons_len * 3);

        buttons: ButtonsBitSet = ButtonsBitSet.initEmpty(),
        button_bindings: std.ArrayListUnmanaged(ButtonBinding) = .{},

        axes: [axes_len]f32 = .{0.0} ** axes_len,
        axis_bindings: std.ArrayListUnmanaged(AxisBinding) = .{},
    };
}
