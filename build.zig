const std = @import("std");
const zentig = @import("lib.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const example = b.addExecutable(.{
        .name = "Example",
        .root_source_file = .{ .path = "src/example.zig" },
        .target = target,
        .optimize = optimize,
    });

    zentig.addAsPackage("zentig", example);

    const run_example_cmd = b.addRunArtifact(example);

    const run_example_step = b.step("example", "Run the example");
    run_example_step.dependOn(&run_example_cmd.step);

    const main_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/tests.zig" },
        .optimize = optimize,
    });

    const run_tests = b.addRunArtifact(main_tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_tests.step);
}
