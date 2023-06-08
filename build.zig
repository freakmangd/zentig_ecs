const std = @import("std");
const zentig = @import("lib.zig");

pub fn addAsModule(
    name: []const u8,
    exe: *std.build.Step.Compile,
    dep: *std.build.Dependency,
) *std.build.Module {
    const mod = dep.module("zentig");
    exe.addModule(name, mod);
    return mod;
}

pub const raylib = struct {
    pub fn addAsModule(
        name: []const u8,
        exe: *std.build.Step.Compile,
        dep: *std.build.Dependency,
        raylib_mod: *std.build.Module,
    ) *std.build.Module {
        var mod = dep.module("zentig-rl");
        // HACK: this kinda sucks :)
        mod.dependencies.put("raylib", raylib_mod) catch @panic("OOM");
        exe.addModule(name, mod);
        return mod;
    }
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zentig_mod = b.addModule("zentig", .{
        .source_file = std.Build.FileSource.relative("src/init.zig"),
        .dependencies = &[_]std.Build.ModuleDependency{},
    });

    const zentig_rl_mod = b.addModule("zentig-rl", .{
        .source_file = std.Build.FileSource.relative("src/mods/raylib/raylib.zig"),
        .dependencies = &[_]std.Build.ModuleDependency{
            .{ .name = "zentig", .module = zentig_mod },
        },
    });

    const examples = [_]struct { []const u8, []const u8 }{
        //.{ "example", "examples/example.zig" },
        //.{ "example-input", "examples/input_example.zig" },
        //.{ "example-raylib", "examples/raylib_example.zig" },
    };

    for (examples) |ex_info| {
        const example = b.addExecutable(.{
            .name = ex_info[0],
            .root_source_file = .{ .path = ex_info[1] },
            .target = target,
            .optimize = optimize,
        });

        example.addModule("zentig", zentig_mod);
        example.addModule("zentig-rl", zentig_rl_mod);

        const run_example_cmd = b.addRunArtifact(example);

        const run_example_step = b.step(ex_info[0], "Run the example");
        run_example_step.dependOn(&run_example_cmd.step);
    }

    const main_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/tests.zig" },
        .optimize = optimize,
    });

    const run_tests = b.addRunArtifact(main_tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_tests.step);
}
