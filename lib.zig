const std = @import("std");
const srcdir = getSrcDir();

fn getSrcDir() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}

pub fn addAsAnonModule(name: []const u8, to: *std.Build.CompileStep) void {
    to.addAnonymousModule(name, .{ .source_file = .{ .path = srcdir ++ "/src/init.zig" } });
}
