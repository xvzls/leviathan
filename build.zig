const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const leviathan_module = b.addModule("leviathan", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize
    });

    const python_lib = b.addSharedLibrary(.{
        .name = "leviathan",
        .optimize = optimize,
        .target = target,
        .root_source_file = b.path("src/lib.zig")
    });
    python_lib.addIncludePath(.{
        .cwd_relative = "/usr/include/"
    });
    python_lib.linkSystemLibrary("python3.12");
    python_lib.linkLibC();

    const python_lib_single_thread = b.addSharedLibrary(.{
        .name = "leviathan_single_thread",
        .optimize = optimize,
        .target = target,
        .root_source_file = b.path("src/lib.zig"),
        .single_threaded = true
    });
    python_lib_single_thread.addIncludePath(.{
        .cwd_relative = "/usr/include/"
    });
    python_lib_single_thread.linkSystemLibrary("python3.12");
    python_lib_single_thread.linkLibC();

    const compile_python_lib = b.addInstallArtifact(python_lib, .{});
    const compile_single_thread_python_lib = b.addInstallArtifact(python_lib_single_thread, .{});
    b.getInstallStep().dependOn(&compile_python_lib.step);
    b.getInstallStep().dependOn(&compile_single_thread_python_lib.step);

    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("tests/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib_unit_tests.root_module.addImport("leviathan", leviathan_module);

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    run_lib_unit_tests.has_side_effects = true;

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
