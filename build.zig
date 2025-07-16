const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zmath = b.dependency("zmath", .{}).module("root");

    const zentig_mod = b.addModule("zentig", .{
        .root_source_file = b.path("src/init.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zmath", .module = zmath },
        },
    });

    const autodoc_test = b.addTest(.{ .root_module = zentig_mod });
    autodoc_test.root_module.addImport("zentig", zentig_mod);
    autodoc_test.root_module.addImport("zmath", zmath);

    const install_docs = b.addInstallDirectory(.{
        .source_dir = autodoc_test.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "autodocs",
    });

    const docs_step = b.step("autodocs", "Build and install documentation");
    docs_step.dependOn(&install_docs.step);

    b.modules.put("zmath", zmath) catch @panic("OOM");
    b.modules.put("zmath_options", zmath.import_table.get("zmath_options").?) catch @panic("OOM");

    // local testing

    const all_tests = b.addTest(.{ .root_module = zentig_mod });
    all_tests.root_module.addImport("zentig", zentig_mod);
    all_tests.root_module.addImport("zmath", zmath);

    const run_all_tests = b.addRunArtifact(all_tests);

    const all_tests_step = b.step("test", "Run all tests and try to build all examples.");
    all_tests_step.dependOn(&run_all_tests.step);

    const examples = [_]struct { []const u8, []const u8, []const u8 }{
        .{ "hello_world", "examples/hello_world.zig", "Run tutorial example" },

        .{ "example", "examples/example.zig", "Run basic example" },
        .{ "example_input", "examples/input_example.zig", "Run input example" },
    };

    for (examples) |ex_info| {
        const example = b.addExecutable(.{
            .name = ex_info[0],
            .root_module = b.createModule(.{
                .root_source_file = b.path(ex_info[1]),
                .target = target,
                .optimize = optimize,
            }),
        });

        example.root_module.addImport("zentig", zentig_mod);

        const run_example_cmd = b.addRunArtifact(example);

        const run_example_step = b.step(ex_info[0], ex_info[2]);
        run_example_step.dependOn(&run_example_cmd.step);

        all_tests_step.dependOn(&example.step);
    }

    const tests = [_]struct { []const u8, []const u8, []const u8 }{
        .{ "test_example", "examples/test_example.zig", "Run testing example" },
    };

    for (tests) |test_info| {
        const t = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(test_info[1]),
                .target = target,
                .optimize = optimize,
            }),
        });
        t.root_module.addImport("zentig", zentig_mod);
        t.root_module.addImport("zmath", zmath);

        const run_tests = b.addRunArtifact(t);

        const test_step = b.step(test_info[0], test_info[2]);
        test_step.dependOn(&run_tests.step);
    }
}
