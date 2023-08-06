pub fn Added(comptime T: type) type {
    return struct {
        pub const QueryAdded: type = T;
    };
}

pub fn Removed(comptime T: type) type {
    return struct {
        pub const QueryRemoved: type = T;
    };
}

pub fn With(comptime T: type) type {
    return struct {
        pub const QueryWith = T;
    };
}

pub fn Without(comptime T: type) type {
    return struct {
        pub const QueryWithout = T;
    };
}
