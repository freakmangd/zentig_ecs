const std = @import("std");
const rl = @import("raylib");
const ztg = @import("zentig");

pub fn vec2(x: f32, y: f32) rl.Vector2 {
    return .{ .x = x, .y = y };
}

pub fn vec3(x: f32, y: f32, z: f32) rl.Vector3 {
    return .{ .x = x, .y = y, .z = z };
}

pub fn vec4(x: f32, y: f32, z: f32, w: f32) rl.Vector4 {
    return .{ .x = x, .y = y, .z = z, .w = w };
}

pub const Sprite = struct {
    tex: rl.Texture2D,
    color: rl.Color,

    pub fn init(file_name: []const u8, color: rl.Color) Sprite {
        return .{
            .tex = rl.LoadTexture(file_name.ptr),
            .color = color,
        };
    }
};

pub const Camera2dBundle = struct {
    cam: rl.Camera2D,

    pub fn init() Camera2dBundle {
        return .{
            .cam = rl.Camera2D{
                .offset = vec2(0, 0),
                .target = vec2(0, 0),
                .rotation = 0.0,
                .zoom = 1.0,
            },
        };
    }
};

pub fn include(comptime world: *ztg.WorldBuilder) void {
    world.include(.{
        ztg.base,
    });
    world.addComponents(.{
        rl.Camera2D,
        Sprite,
    });
    world.addSystemsToStage(.post_init, .{poi_checkCams});
    world.addSystemsToStage(.pre_update, .{pru_time});
    world.addSystemsToStage(.draw, .{dr_sprites});
}

fn poi_checkCams(cameras: ztg.Query(.{rl.Camera2D}, .{})) void {
    if (cameras.len == 0) {
        std.log.warn("No cameras detected after init stage. Try adding one with `commands.giveEntMany(ent, zrl.Camera2dBundle.init())`", .{});
    }
}

fn pru_time(time: *ztg.base.Time) void {
    time.dt = rl.GetFrameTime();
}

fn dr_sprites(cameras: ztg.Query(.{rl.Camera2D}, .{}), query: ztg.Query(.{ Sprite, ztg.base.Transform }, .{})) anyerror!void {
    var slice = query.slice();

    for (cameras.items(.a)) |cam| {
        rl.BeginMode2D(cam.*);

        for (slice.items(.a), slice.items(.b)) |spr, trn| {
            rl.DrawTexture(spr.tex, @floatToInt(c_int, trn.pos.x), @floatToInt(c_int, trn.pos.y), spr.color);
        }

        rl.EndMode2D();
    }
}

pub const InputWrapper = struct {
    pub const ButtonType = union(enum) {
        keyboard: rl.KeyboardKey,
        mouse: rl.MouseButton,
        gamepad: struct {
            gamepad_num: c_int = 0,
            button: rl.GamepadButton,
        },
    };

    pub const AxisType = union(enum) {
        keyboard: struct {
            positive: rl.KeyboardKey,
            negative: rl.KeyboardKey,
        },
        mouseX,
        mouseY,
        gamepad: struct {
            gamepad_num: c_int = 0,
            axis: c_int,
        },
    };

    pub fn getButtonPressed(button: ButtonType) !bool {
        return switch (button) {
            .keyboard => |kb| rl.IsKeyPressed(kb),
            .mouse => |ms| rl.IsMouseButtonPressed(ms),
            .gamepad => |gp| rl.IsGamepadButtonPressed(gp.gamepad_num, gp.button),
        };
    }

    pub fn getButtonDown(button: ButtonType) !bool {
        return switch (button) {
            .keyboard => |kb| rl.IsKeyDown(kb),
            .mouse => |ms| rl.IsMouseButtonDown(ms),
            .gamepad => |gp| rl.IsGamepadButtonDown(gp.gamepad_num, gp.button),
        };
    }

    pub fn getButtonReleased(button: ButtonType) !bool {
        return switch (button) {
            .keyboard => |kb| rl.IsKeyReleased(kb),
            .mouse => |ms| rl.IsMouseButtonReleased(ms),
            .gamepad => |gp| rl.IsGamepadButtonReleased(gp.gamepad_num, gp.button),
        };
    }

    pub fn getAxis(axis: AxisType) !f32 {
        return switch (axis) {
            .keyboard => |kb| blk: {
                var val: f32 = 0.0;
                if (rl.IsKeyDown(kb.positive)) val += 1.0;
                if (rl.IsKeyDown(kb.negative)) val -= 1.0;
                break :blk val;
            },
            .mouseX => rl.GetMouseDelta().x,
            .mouseY => rl.GetMouseDelta().y,
            .gamepad => |gp| rl.GetGamepadAxisMovement(gp.gamepad_num, gp.axis),
        };
    }

    /// Adds axes { "MouseX", "MouseY" } and buttons { "Mouse1", "Mouse2", "Mouse3", "Mouse4", "Mouse5" }
    /// call `.bindMouse()` in an init system to setup bindings.
    /// `cb` should be a pointer to your ControllerBuilder
    pub fn setupMouse(cb: anytype) void {
        cb.addAxes(&.{ "MouseX", "MouseY" });
        cb.addButtons(&.{ "MouseLeft", "MouseRight", "MouseMiddle", "MouseSide", "MouseExtra", "MouseForward", "MouseBack" });
    }

    /// Binds axes and buttons added in `.setupMouse()`
    pub fn bindMouse(controller: usize, input: anytype) !void {
        try input.bindAxis(controller, "MouseX", .{ .mouseX = {} });
        try input.bindAxis(controller, "MouseY", .{ .mouseY = {} });
        try input.bindButton(controller, "MouseLeft", .{ .mouse = .MOUSE_BUTTON_LEFT });
        try input.bindButton(controller, "MouseRight", .{ .mouse = .MOUSE_BUTTON_RIGHT });
        try input.bindButton(controller, "MouseMiddle", .{ .mouse = .MOUSE_BUTTON_MIDDLE });
        try input.bindButton(controller, "MouseSide", .{ .mouse = .MOUSE_BUTTON_SIDE });
        try input.bindButton(controller, "MouseExtra", .{ .mouse = .MOUSE_BUTTON_EXTRA });
        try input.bindButton(controller, "MouseForward", .{ .mouse = .MOUSE_BUTTON_FORWARD });
        try input.bindButton(controller, "MouseBack", .{ .mouse = .MOUSE_BUTTON_BACK });
    }
};
