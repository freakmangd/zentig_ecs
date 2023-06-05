const std = @import("std");
const srcdir = getSrcDir();

fn getSrcDir() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}

pub fn addAsAnonModule(name: []const u8, to: *std.Build.CompileStep) void {
    to.addAnonymousModule(name, .{ .source_file = .{ .path = srcdir ++ "/src/init.zig" } });
}

pub const raylib = struct {
    pub fn addAsAnonModule(name: []const u8, to: *std.Build.CompileStep, zentig_mod: *std.Build.Module, raylib_mod: *std.Build.Module) void {
        to.addAnonymousModule(name, .{
            .source_file = .{ .path = srcdir ++ "/src/mods/raylib/raylib.zig" },
            .dependencies = &.{
                .{ .name = "zentig", .module = zentig_mod },
                .{ .name = "raylib", .module = raylib_mod },
            },
        });
    }
};
