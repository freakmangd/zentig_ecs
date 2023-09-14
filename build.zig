const std = @import("std");
const zmath = @import("deps/zmath/build.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zmath_pkg = zmath.package(b, target, optimize, .{});

    const zigfsm_mod = b.createModule(.{
        .source_file = std.Build.FileSource.relative("deps/zigfsm/src/main.zig"),
    });

    const zentig_mod = b.addModule("zentig", .{
        .source_file = std.Build.FileSource.relative("src/init.zig"),
        .dependencies = &[_]std.Build.ModuleDependency{
            .{ .name = "zmath", .module = zmath_pkg.zmath },
            .{ .name = "zigfsm", .module = zigfsm_mod },
        },
    });

    const autodoc_test = b.addTest(.{
        .root_source_file = std.Build.FileSource.relative("src/init.zig"),
        .target = target,
        .optimize = optimize,
    });
    autodoc_test.addModule("zentig", zentig_mod);
    autodoc_test.addModule("zmath", zmath_pkg.zmath);

    const install_docs = b.addInstallDirectory(.{
        .source_dir = autodoc_test.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "autodocs",
    });

    const docs_step = b.step("autodocs", "Build and install documentation");
    docs_step.dependOn(&install_docs.step);

    b.modules.put(b.dupe("zmath"), zmath_pkg.zmath) catch @panic("OOM");
    b.modules.put(b.dupe("zmath_options"), zmath_pkg.zmath_options) catch @panic("OOM");

    // LOCAL TESTING

    // MAKE SURE EVERYTHING WORKS
    const all_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/init.zig" },
        .target = target,
        .optimize = optimize,
    });
    all_tests.addModule("zentig", zentig_mod);
    all_tests.addModule("zmath", zmath_pkg.zmath);

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
            .root_source_file = .{ .path = ex_info[1] },
            .target = target,
            .optimize = optimize,
        });

        example.addModule("zentig", zentig_mod);

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
            .root_source_file = .{ .path = test_info[1] },
            .target = target,
            .optimize = optimize,
        });
        t.addModule("zentig", zentig_mod);
        t.addModule("zmath", zmath_pkg.zmath);

        const run_tests = b.addRunArtifact(t);

        const test_step = b.step(test_info[0], test_info[2]);
        test_step.dependOn(&run_tests.step);
    }
}

const ZentigModule = struct {
    zentig_mod: *std.Build.Module,
    zmath_mod: *std.Build.Module,
    zmath_options_mod: *std.Build.Module,

    target: std.zig.CrossTarget,
    optimize: std.builtin.OptimizeMode,

    b: *std.Build,
    exe: *std.Build.Step.Compile,
};

pub fn addAsLocalModule(settings: struct {
    name: []const u8,
    path_to_root: []const u8,
    build: *std.Build,
    exe: *std.Build.Step.Compile,
    target: std.zig.CrossTarget,
    optimize: std.builtin.OptimizeMode,
    import_zmath_as: ?[]const u8 = null,
    import_zmath_options_as: ?[]const u8 = null,
    import_zigfsm_as: ?[]const u8 = null,
}) ZentigModule {
    const zmath_pkg = zmath.package(settings.build, settings.target, settings.optimize, .{});

    const zentig_dep = settings.build.anonymousDependency(settings.path_to_root, @This(), .{
        .target = settings.target,
        .optimize = settings.optimize,
    });

    settings.exe.addModule(settings.name, zentig_dep.module("zentig"));

    if (settings.import_zmath_as) |mn|
        settings.exe.addModule(mn, zmath_pkg.zmath);

    if (settings.import_zmath_options_as) |mn|
        settings.exe.addModule(mn, zmath_pkg.zmath_options);

    return .{
        .zentig_mod = zentig_dep.module("zentig"),
        .zmath_mod = zmath_pkg.zmath,
        .zmath_options_mod = zmath_pkg.zmath_options,

        .target = settings.target,
        .optimize = settings.optimize,

        .b = settings.build,
        .exe = settings.exe,
    };
}

//pub fn addAsLocalModule2(
//    name: []const u8,
//    b: *std.Build,
//    exe: *std.build.Step.Compile,
//    target: std.zig.CrossTarget,
//    optimize: std.builtin.OptimizeMode,
//    options: struct { import_zmath_as: ?[]const u8 = null, import_zmath_options_as: ?[]const u8 = null },
//) ZentigModule {
//    const zmath_pkg = zmath.package(b, target, optimize, .{});
//
//    const mod = b.createModule(.{
//        .source_file = .{ .path = srcdir ++ "/src/init.zig" },
//        .dependencies = &.{
//            .{ .name = "zmath", .module = zmath_pkg.zmath },
//        },
//    });
//
//    if (options.import_zmath_as) |impas|
//        exe.addModule(impas, zmath_pkg.zmath);
//
//    if (options.import_zmath_options_as) |impas|
//        exe.addModule(impas, zmath_pkg.zmath_options);
//
//    exe.addModule(name, mod);
//
//    return .{
//        .zentig_mod = mod,
//        .zmath_mod = zmath_pkg.zmath,
//        .zmath_options_mod = zmath_pkg.zmath_options,
//
//        .target = target,
//        .optimize = optimize,
//
//        .b = b,
//        .exe = exe,
//    };
//}

const srcdir = struct {
    fn getSrcDir() []const u8 {
        return std.fs.path.dirname(@src().file).?;
    }
}.getSrcDir();
