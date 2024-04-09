/// A query modifier asserting the entity has a component of type `T`
/// without actually collecting it in the query
pub fn With(comptime T: type) type {
    return struct {
        pub const QueryWith = T;
    };
}

/// A query modifier asserting the entity does __not__ have a component of type `T`
pub fn Without(comptime T: type) type {
    return struct {
        pub const QueryWithout = T;
    };
}
