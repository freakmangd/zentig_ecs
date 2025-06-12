pub const Entity = enum(usize) {
    _,

    pub fn toInt(ent: Entity) usize {
        return @intFromEnum(ent);
    }
};
