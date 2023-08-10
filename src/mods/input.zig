const std = @import("std");
const ztg = @import("../init.zig");
const log = std.log.scoped(.zentig_input);

const Options = struct {
    max_controllers: usize = 4,
    update_stage: struct {
        stage: @TypeOf(.enum_literal) = .update,
        label: @TypeOf(.enum_literal) = .body,
        order: ztg.SystemOrder = .during,
    } = .{},
};

pub fn Build(
    comptime Wrapper: type,
    comptime button_literals: anytype,
    comptime axis_literals: anytype,
    comptime options: Options,
) type {
    const ButtonBindings = blk: {
        var buttons_tb = ztg.meta.TypeBuilder{};
        inline for (button_literals) |b| {
            buttons_tb.addField(@tagName(b), []const Wrapper.ButtonType, @ptrCast(&@as([]const Wrapper.ButtonType, &.{})));
        }
        break :blk buttons_tb.Build();
    };

    const AxesBindings = blk: {
        var axes_tb = ztg.meta.TypeBuilder{};
        inline for (axis_literals) |a| {
            axes_tb.addField(@tagName(a), []const Wrapper.AxisType, @ptrCast(&@as([]const Wrapper.AxisType, &.{})));
        }
        break :blk axes_tb.Build();
    };

    const AddBindings = struct {
        buttons: ButtonBindings = .{},
        axes: AxesBindings = .{},
    };

    return struct {
        pub const Buttons = EnumFromLiterals(button_literals);
        pub const Axes = EnumFromLiterals(axis_literals);
        const Controller = ControllerBuilder(Buttons, Axes, Wrapper.ButtonType, Wrapper.AxisType);

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

        pub inline fn clearAllBindings(self: *Self) void {
            for (0..self.controllers.len) |c| self.clearBindings(c);
        }

        pub inline fn clearBindings(self: *Self, controller: usize) void {
            self.clearButtonBindings(controller);
            self.clearAxisBindings(controller);
        }

        pub inline fn clearButtonBindings(self: *Self, controller: usize) void {
            self.controllers[controller].button_bindings.clearRetainingCapacity();
        }

        pub inline fn clearAxisBindings(self: *Self, controller: usize) void {
            self.controllers[controller].axis_bindings.clearRetainingCapacity();
        }

        pub inline fn isDown(self: Self, controller: usize, button: Buttons) bool {
            return self.controllers[controller].buttons.isSet(@as(usize, @intCast(@intFromEnum(button))) * 3);
        }

        pub inline fn isPressed(self: Self, controller: usize, button: Buttons) bool {
            return self.controllers[controller].buttons.isSet((@as(usize, @intCast(@intFromEnum(button))) * 3) + 1);
        }

        pub inline fn isReleased(self: Self, controller: usize, button: Buttons) bool {
            return self.controllers[controller].buttons.isSet((@as(usize, @intCast(@intFromEnum(button))) * 3) + 2);
        }

        pub inline fn getAxis(self: Self, controller: usize, axis: Axes) f32 {
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
                    try writer.print("{}=", .{bb.index});
                    try Wrapper.exportButtonBinding(writer, bb.binding);
                    try writer.print("\n", .{});
                }

                try writer.print("axes:\n", .{});
                for (contr.axis_bindings.items) |ab| {
                    try writer.print("{}=", .{ab.index});
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

        inline fn importBindingsInternal(self: *Self, reader: anytype) bool {
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
                        log.err("Bad formatted bindings file, no `:` character after controller index.", .{});
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
                    const bd_eql_idx = getBindingIndexAndEqlsIndex(line) catch return false;

                    const binding_index = bd_eql_idx[0];
                    const eqls_idx = bd_eql_idx[1];
                    const binding_text = line[eqls_idx + 1 ..];

                    const ButtonIndex = std.math.IntFittingRange(0, button_literals.len);
                    const AxisIndex = std.math.IntFittingRange(0, axis_literals.len);

                    switch (read_mode) {
                        .buttons => {
                            self.controllers[current_controller].button_bindings.append(self.alloc, .{
                                .index = std.math.cast(ButtonIndex, binding_index) orelse {
                                    log.err("Index of button binding exceeded max range. Max: {}, Found {}", .{ button_literals.len, binding_index });
                                    return false;
                                },
                                .binding = Wrapper.importButtonBinding(binding_text) catch |err| {
                                    log.err("Could not import button binding due to {}", .{err});
                                    return false;
                                },
                            }) catch |err| {
                                log.err("Could not append to button bindings due to {}", .{err});
                                return false;
                            };
                        },
                        .axes => {
                            self.controllers[current_controller].axis_bindings.append(self.alloc, .{
                                .index = std.math.cast(AxisIndex, binding_index) orelse {
                                    log.err("Index of axis binding exceeded max range. Max: {}, Found: {}", .{ axis_literals.len, binding_index });
                                    return false;
                                },
                                .binding = Wrapper.importAxisBinding(binding_text) catch |err| {
                                    log.err("Could not import axis binding due to {}", .{err});
                                    return false;
                                },
                            }) catch |err| {
                                log.err("Could not append to button bindings due to {}", .{err});
                                return false;
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

        fn getBindingIndexAndEqlsIndex(line: []const u8) !struct { usize, usize } {
            const eqls_idx = std.mem.indexOf(u8, line, "=") orelse {
                log.err("Bad formatted bindings file, no `=` character on binding line.", .{});
                return error.BadFormat;
            };
            const binding_index = std.fmt.parseInt(usize, line[0..eqls_idx], 10) catch |err| {
                log.err("Could not parse controller binding index due to {}", .{err});
                return error.BadFormat;
            };

            return .{ binding_index, eqls_idx };
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
                c.* = Controller.init();
            }

            self.alloc = alloc;
        }

        fn update_Self(self: *Self) void {
            for (&self.controllers) |*ct| {
                if (comptime button_literals.len > 0) {
                    for (ct.button_bindings.items) |bb| {
                        const is_down = Wrapper.isButtonDown(bb.binding);
                        const is_pres = Wrapper.isButtonPressed(bb.binding);
                        const is_rel = Wrapper.isButtonReleased(bb.binding);
                        ct.buttons.setValue(@as(usize, bb.index) * 3, is_down);
                        ct.buttons.setValue(@as(usize, bb.index) * 3 + 1, is_pres);
                        ct.buttons.setValue(@as(usize, bb.index) * 3 + 2, is_rel);
                    }
                }
                if (comptime axis_literals.len > 0) {
                    for (ct.axis_bindings.items) |ab| {
                        const value = Wrapper.getAxis(ab.binding);
                        ct.axes[ab.index] = value;
                    }
                }
            }
        }

        fn dei_Self(self: *Self) void {
            for (&self.controllers) |*con| {
                if (comptime button_literals.len > 0) con.button_bindings.deinit(self.alloc);
                if (comptime axis_literals.len > 0) con.axis_bindings.deinit(self.alloc);
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
