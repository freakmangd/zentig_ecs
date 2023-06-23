const std = @import("std");
const zentig = @import("lib.zig");

pub fn addAsModule(
    name: []const u8,
    b: *std.Build,
    exe: *std.build.Step.Compile,
) *std.build.Module {
    const mod = b.createModule(.{
        .source_file = .{ .path = srcdir ++ "/src/init.zig" },
    });
    exe.addModule(name, mod);
    return mod;
}

const srcdir = struct {
    fn getSrcDir() []const u8 {
        return std.fs.path.dirname(@src().file).?;
    }
}.getSrcDir();

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zentig_mod = b.addModule("zentig", .{
        .source_file = std.Build.FileSource.relative("src/init.zig"),
        .dependencies = &[_]std.Build.ModuleDependency{},
    });

    const examples = [_]struct { []const u8, []const u8 }{
        //.{ "example", "examples/example.zig" },
        //.{ "example-input", "examples/input_example.zig" },
    };

    for (examples) |ex_info| {
        const example = b.addExecutable(.{
            .name = ex_info[0],
            .root_source_file = .{ .path = ex_info[1] },
            .target = target,
            .optimize = optimize,
        });

        example.addModule("zentig", zentig_mod);

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
