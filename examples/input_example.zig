const std = @import("std");
const ztg = @import("zentig");

const Buttons = enum(usize) {
    space = 0,
};

// This is a barebones version of an InputWrapper, it is not expected that you
// make your own, a raylib input wrapper comes built in.
//
// a user made wrapper must have `ButtonType`, `AxisType`, `getButtonPressed`, `getButtonDown`,
// `getButtonReleased`, and `getAxis`. All errors from functions are passed back through `.update()`
const InputWrapper = struct {
    pub const ButtonType = Buttons;
    // there are no axes in this example
    pub const AxisType = void;

    const input_state = [_][3]bool{
        .{ false, true, false }, // Buttons.space
    };

    pub fn getButtonPressed(button: ButtonType) !bool {
        return input_state[@enumToInt(button)][0];
    }

    pub fn getButtonDown(button: ButtonType) !bool {
        return input_state[@enumToInt(button)][1];
    }

    pub fn getButtonReleased(button: ButtonType) !bool {
        return input_state[@enumToInt(button)][2];
    }

    pub fn getAxis(axis: AxisType) !f32 {
        _ = axis;
        return 0.0;
    }
};

const Input = blk: {
    var cb = ztg.input.ControllerBuilder(InputWrapper).new();
    cb.addButtons("Jump");
    break :blk cb.BuildInput();
};

const World = blk: {
    var wb = ztg.WorldBuilder.new(.{
        Input,
    });
    wb.addSystemsToStage("INIT", .{setup_input});
    wb.addUpdateSystems(.{read_input});
    break :blk wb.Build();
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    var world = try World.init(alloc);
    defer world.deinit();

    // required to set up Input
    try world.runInitStages();
    // required to run PRE_INIT as that is when inputs are updated
    try world.runUpdateStages();
}

const PLAYER_ONE = 0;

fn setup_input(input: *Input) !void {
    try input.newController();
    input.bindButton(PLAYER_ONE, "Jump", Buttons.space);
}

fn read_input(input: Input) !void {
    std.debug.print("Is jump down? {}\n", .{input.getButtonDown(PLAYER_ONE, "Jump")});
}
