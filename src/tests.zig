const std = @import("std");

test "TestAll" {
    std.testing.refAllDeclsRecursive(@import("ecs.zig"));
}
