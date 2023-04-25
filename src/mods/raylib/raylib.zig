const std = @import("std");
const ztg = @import("../../init.zig");

pub fn Init(comptime rl: type) type {
    return struct {
        pub const Sprite = struct {
            tex: rl.Texture2D,
            color: rl.Color,
            layer: usize,

            pub fn init(file_name: []const u8, color: rl.Color) Sprite {
                return .{
                    .tex = rl.LoadTexture(file_name),
                    .color = color,
                };
            }
        };

        const Cameras = struct {
            std.ArrayList(rl.Camera2D),
        };

        pub fn include(comptime world: *ztg.WorldBuilder) !void {
            world.include(.{
                ztg.base,
            });
            world.addResource(Cameras, .{undefined});
            world.addComponents(.{
                Sprite,
            });
            world.addSystemsToStage(ztg.stages.pre_init, .{
                pri_cameras,
            });
            world.addSystemsToStage(ztg.stages.pre_update, .{
                pru_time,
            });
            world.addSystemsToStage(ztg.stages.draw, .{
                dr_sprites,
            });
        }

        fn pri_cameras(alloc: std.mem.Allocator, cameras: *Cameras) !void {
            cameras.*[0] = std.ArrayList(rl.Camera2D).init(alloc);
        }

        fn pru_time(time: *ztg.base.Time) void {
            time.dt = rl.GetFrameTime();
        }

        pub fn dr_sprites(alloc: std.mem.Allocator, cameras: Cameras, query: ztg.Query(.{ Sprite, ztg.base.Transform }, .{})) anyerror!void {
            var slice = query.slice();
            defer slice.deinit(alloc);

            for (cameras[0].items) |cam| {
                rl.BeginMode2D(cam);

                for (slice.items(.a), slice.items(.b)) |spr, trn| {
                    rl.DrawTexture(spr.tex, @floatToInt(c_int, trn.pos.x), @floatToInt(c_int, trn.pos.y), spr.color);
                }

                rl.EndMode2D();
            }
        }

        pub const InputWrapper = struct {
            pub const ButtonType = union(enum) {
                keyboard: rl.KeyboardKey,
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
                gamepad: struct {
                    axis: c_int,
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
