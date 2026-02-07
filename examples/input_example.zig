//! This test can be run with `zig build example_input`

const std = @import("std");
const ztg = @import("zentig");

var input_state = [_]struct { pressed: bool, down: bool, released: bool }{
    .{ .pressed = false, .down = false, .released = false },
};

const Buttons = enum(usize) {
    space = 0,
};

// This is a barebones version of an InputWrapper.
//
// a user made wrapper must have `ButtonType`, `AxisType`, `getButtonPressed`, `getButtonDown`,
// `getButtonReleased`, and `getAxis`. All errors from functions are passed back through input's update stage (.pre_update by default)
const InputWrapper = struct {
    pub const ButtonType = Buttons;
    // there are no axes in this example
    pub const AxisType = void;
    // the source is arbitrary arrays, usually this would look something like
    // union(enum) {
    //     keyboard,
    //     gamepad: usize,
    // }
    pub const InputSource = void;

    pub fn isButtonPressed(source: void, button: ButtonType) bool {
        _ = source;
        return input_state[@intFromEnum(button)].pressed;
    }

    pub fn isButtonDown(source: void, button: ButtonType) bool {
        _ = source;
        return input_state[@intFromEnum(button)].down;
    }

    pub fn isButtonReleased(source: void, button: ButtonType) bool {
        _ = source;
        return input_state[@intFromEnum(button)].released;
    }

    pub fn getAxis(source: void, axis: AxisType) f32 {
        _ = source;
        _ = axis;
        return 0.0;
    }
};

const Input = ztg.input.Build(InputWrapper, enum { jump }, enum {}, .{});

const World = blk: {
    var wb = ztg.WorldBuilder.init(&.{
        Input,
    });
    wb.addSystems(.{
        .init = .{ini_setupInput},
        .update = .{up_readInput},
    });
    break :blk wb.Build();
};

pub fn main(init: std.process.Init) !void {
    var world = try World.init(init.gpa, .{});
    defer world.deinit();

    // required to set up Input
    try world.runStage(.load);
    // required to update Input
    try world.runStage(.update);

    std.debug.print("Update spacebar down state to `true`\n", .{});
    changeInputState();

    // on the second run, Input catches the change and updates the controllers
    try world.runStage(.update);
}

fn ini_setupInput(input: *Input) !void {
    try input.addBindings(.{
        .buttons = .{
            .jump = &.{Buttons.space},
        },
        .axes = .{},
    });
    _ = input.receiveController({});
}

fn up_readInput(input: Input) void {
    std.debug.print("Is Jump down? {}\n", .{input.controllers[0].isDown(.jump)});
}

fn changeInputState() void {
    input_state[@intFromEnum(Buttons.space)].down = true;
}
