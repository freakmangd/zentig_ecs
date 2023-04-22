const std = @import("std");
const zentig = @import("lib.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const examples = [_]struct { []const u8, []const u8 }{
        .{ "example", "examples/example.zig" },
        .{ "example-input", "examples/input_example.zig" },
    };

    for (examples) |ex_info| {
        const example = b.addExecutable(.{
            .name = ex_info[0],
            .root_source_file = .{ .path = ex_info[1] },
            .target = target,
            .optimize = optimize,
        });

        zentig.addAsModule("zentig", example);

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
