# Builtin Mods

Zentig comes with these mods which you can include in your worldbuilder:

## ztg.base

#### Name : Component

A simple name component, just defined as `struct { []const u8 }`

#### Transform : Component

Used for setting/getting local position, rotation, and scale.
Parenting entities also propogates the transform into the `GlobalTransform`.

#### GlobalTransform : Component

Used for getting global position, rotation, and scale.
Affected by the entity's parent hierarchy.

#### Lifetime : Component

A component that accepts a max lifetime in seconds for an object, and counts down from there.
Once it hits zero, either destroys the attached entity or invokes a callback depending on the 
`on_death` field.

#### Time : Resource

Keeps track of delta time, elapsed time, timescale, real time, etc.

Can be integrated with `Time.update(self: *Time, real_dt: f32)`<br>
Rayib example: `time.update(rl.GetFrameTime());`

## ztg.input.Build()

Using this you can create control schemes and manage input in your systems.

There is also `exportBindings` and `importBindings` to save controller bindings to a file
and retrieve them between sessions.

Zentig-Raylib example:

Setup:
```zig
pub const Input = ztg.input.Build(
    zrl.InputWrapper,
    .{.shoot} ++ zrl.mouse_buttons,
    .{ .horiz, .vert } ++ zrl.mouse_axes,
    .{ .max_controllers = 1 },
);

const World = ztg.WorldBuilder.init(&.{
    Input,
    // ...
});
```

Default bindings:
```zig
fn load(input: *Input) !void {
    try input.addBindings(0, .{
        .axes = .{
            .horiz = &.{zrl.kbAxis(zrl.KEY_D, zrl.KEY_A)},
            .vert = &.{zrl.kbAxis(zrl.KEY_W, zrl.KEY_S)},
        },
        .buttons = .{
            .shoot = &.{zrl.msButton(zrl.MOUSE_BUTTON_LEFT)},
        },
    });
    try zrl.InputWrapper.bindMouse(0, input);
}
```

Usage:
```zig
// ... snip ...
if (inp.isDown(0, .shoot)) {
    const dir: ztg.Vec2 = tr.getPos().flatten().directionTo(ztg.Vec2.from(zrl.GetMousePosition()));
    try game.Bullet.init(com, tr.getPos(), dir, team.*);
}
// ... snip ...
```
