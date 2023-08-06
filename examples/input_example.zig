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
// `getButtonReleased`, and `getAxis`. All errors from functions are passed back through `.update()`
const InputWrapper = struct {
    pub const ButtonType = Buttons;
    // there are no axes in this example
    pub const AxisType = void;

    pub fn isButtonPressed(button: ButtonType) bool {
        return input_state[@intFromEnum(button)].pressed;
    }

    pub fn isButtonDown(button: ButtonType) bool {
        return input_state[@intFromEnum(button)].down;
    }

    pub fn isButtonReleased(button: ButtonType) bool {
        return input_state[@intFromEnum(button)].released;
    }

    pub fn getAxis(axis: AxisType) f32 {
        _ = axis;
        return 0.0;
    }
};

const Input = ztg.input.Input(InputWrapper, &.{.jump}, &.{}, .{});

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

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var world = try World.init(alloc);
    defer world.deinit();

    // required to set up Input
    try world.runStage(.load);
    // required to update Input
    try world.runStage(.update);

    // `input_state[0].down` is set to `false`
    std.debug.print("Update spacebar down state to `true`\n", .{});
    changeInputState();

    // on the second run, Input catches the change and updates the controllers
    try world.runStage(.update);
}

const PLAYER_ONE = 0;

fn ini_setupInput(input: *Input) !void {
    try input.addBindings(0, .{
        .buttons = .{
            .jump = &.{Buttons.space},
        },
        .axes = .{},
    });
}

fn up_readInput(input: Input) void {
    std.debug.print("Is Jump down? {}\n", .{input.isDown(PLAYER_ONE, .jump)});
}

fn changeInputState() void {
    input_state[@intFromEnum(Buttons.space)].down = true;
}
