const std = @import("std");
const ecs = @import("../../ecs.zig");

pub fn Init(comptime rl: type) type {
    return struct {
        pub const Sprite = struct {
            tex: rl.Texture2D,
            color: rl.Color,
        };

        pub fn include(comptime world: *ecs.WorldBuilder) !void {
            world.include(.{
                ecs.base,
            });
            world.addComponents(.{
                Sprite,
            });
            world.addSystemsToStage("PRE_UPDATE", .{
                pre_update_time,
            });
            world.addSystemsToStage("DRAW", .{
                draw_sprites,
            });
        }

        fn pre_update_time(time: *ecs.base.Time) void {
            time.dt = rl.GetFrameTime();
        }

        pub fn draw_sprites(alloc: std.mem.Allocator, query: ecs.Query(.{ Sprite, ecs.base.Position }, .{})) anyerror!void {
            var slice = query.slice();
            defer slice.deinit(alloc);

            for (slice.items(.a), slice.items(.b)) |spr, pos| {
                rl.DrawTexture(spr.tex, @floatToInt(c_int, pos.x), @floatToInt(c_int, pos.y), spr.color);
            }
        }

        pub const InputWrapper = struct {
            pub const ButtonType = union(enum) {
                keyboard: rl.KeyboardKey,
                gamepad: struct {
                    gamepad_num: c_int = 0,
                    button: rl.KeyboardKey,
                },
            };

            pub const AxisType = union(enum) {
                keyboard: struct {
                    positive: rl.KeyboardKey,
                    negative: rl.KeyboardKey,
                },
                gamepad: struct {
                    axis: rl.KeyboardKey,
                    gamepad_num: c_int = 0,
                },
            };

            pub fn getButtonPressed(button: ButtonType) !bool {
                switch (button) {
                    .keyboard => |kb| rl.IsKeyPressed(kb.button),
                    .gamepad => |gp| rl.IsGamepadButtonPressed(gp.gamepad_num, gp.button),
                }
            }

            pub fn getButtonDown(button: ButtonType) !bool {
                return switch (button) {
                    .keyboard => |kb| rl.IsKeyDown(kb.button),
                    .gamepad => |gp| rl.IsGamepadButtonDown(gp.gamepad_num, gp.button),
                };
            }

            pub fn getButtonReleased(button: ButtonType) !bool {
                return switch (button) {
                    .keyboard => |kb| rl.IsKeyReleased(kb.button),
                    .gamepad => |gp| rl.IsGamepadButtonReleased(gp.gamepad_num, gp.button),
                };
            }

            pub fn getAxis(axis: AxisType) !f32 {
                switch (axis) {
                    .keyboard => |kb| {
                        var val: f32 = 0.0;
                        if (rl.IsKeyDown(kb.positive)) val += 1.0;
                        if (rl.IsKeyDown(kb.negative)) val -= 1.0;
                        return val;
                    },
                    .gamepad => |gp| return rl.GetGamepadAxisMovement(gp.gamepad_num, gp.axis),
                }
            }
        };
    };
}
