const std = @import("std");
const ztg = @import("zentig");

var input_state = [_]struct { pressed: bool, down: bool, released: bool }{
    .{ .pressed = false, .down = true, .released = false },
};

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

    pub fn getButtonPressed(button: ButtonType) !bool {
        return input_state[@intFromEnum(button)].pressed;
    }

    pub fn getButtonDown(button: ButtonType) !bool {
        return input_state[@intFromEnum(button)].down;
    }

    pub fn getButtonReleased(button: ButtonType) !bool {
        return input_state[@intFromEnum(button)].released;
    }

    pub fn getAxis(axis: AxisType) !f32 {
        _ = axis;
        return 0.0;
    }
};

const Input = blk: {
    var cb = ztg.input.ControllerBuilder(InputWrapper).init();
    cb.addButtons(&.{"Jump"});
    break :blk cb.BuildInput();
};

const World = blk: {
    var wb = ztg.WorldBuilder.init(.{
        Input,
    });
    wb.addSystemsToStage(.init, .{ini_setupInput});
    wb.addUpdateSystems(.{up_readInput});
    break :blk wb.Build();
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var world = try World.init(alloc);
    defer world.deinit();

    // required to set up Input, specifically `.pre_init` for setup
    try world.runInitStages();
    // required to update Input, specifically `.pre_update` for reading input
    try world.runUpdateStages();

    // `input_state[0].down` is set to `false`
    changeInputState();

    // on the second run, `.pre_update` of Input catches the change and updates the controllers
    try world.runUpdateStages();
}

const PLAYER_ONE = 0;

fn ini_setupInput(alloc: std.mem.Allocator, input: *Input) !void {
    try input.newController(alloc, .{
        .buttons = &.{
            .{ "Jump", Buttons.space },
        },
    });
}

fn up_readInput(input: Input) void {
    std.debug.print("Is Jump down? {}\n", .{input.getButtonDown(PLAYER_ONE, "Jump")});
}

fn changeInputState() void {
    std.debug.print("Update spacebar down state to `false`\n", .{});
    input_state[@intFromEnum(Buttons.space)].down = false;
}
