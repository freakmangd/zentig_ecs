const std = @import("std");

/// Get the element type of a MultiArrayList
pub fn MultiArrayListElem(comptime T: type) type {
    return @typeInfo(@TypeOf(T.pop)).Fn.return_type.?;
}

/// Get the element type of an ArrayHashMap
pub fn ArrayHashMapElem(comptime T: type) type {
    return @typeInfo(T.KV).Struct.fields[1].type;
}
