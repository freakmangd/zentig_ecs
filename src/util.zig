pub const Vec2 = struct {
    x: f32,
    y: f32,

    pub fn new(x: f32, y: f32) Vec2 {
        return .{ .x = x, .y = y };
    }
};

pub const Vec3 = struct {
    x: f32,
    y: f32,
    z: f32,

    pub fn new(x: f32, y: f32, z: f32) Vec3 {
        return .{ .x = x, .y = y, .z = z };
    }

    pub fn one() Vec3 {
        return .{ .x = 1, .y = 1, .z = 1 };
    }
};

pub const Quaternion = struct {
    x: f32,
    y: f32,
    z: f32,
    w: f32,

    // TODO: actually make quaternions work lmao
    pub fn identity() Quaternion {
        return .{ .x = 0, .y = 0, .z = 0, .w = 0 };
    }
};
