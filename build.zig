const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const jdz_allocator = b.dependency("jdz_allocator", .{
        .target = target,
        .optimize = optimize
    });
    const jdz_allocator_module = jdz_allocator.module("jdz_allocator");

    const python_c_module = b.addModule("python_c", .{
        .root_source_file = b.path("src/python_c.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true
    });
    python_c_module.addIncludePath(.{
        .cwd_relative = "/usr/include/"
    });
    python_c_module.linkSystemLibrary("python3.12", .{});

    const leviathan_module = b.addModule("leviathan", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize
    });
    leviathan_module.addImport("python_c", python_c_module);
    leviathan_module.addImport("jdz_allocator", jdz_allocator_module);

    const python_lib = b.addSharedLibrary(.{
        .name = "leviathan",
        .optimize = optimize,
        .target = target,
        .root_source_file = b.path("src/lib.zig")
    });

    const python_lib_single_thread = b.addSharedLibrary(.{
        .name = "leviathan_single_thread",
        .optimize = optimize,
        .target = target,
        .root_source_file = b.path("src/lib.zig"),
        .single_threaded = true
    });

    const python_libs = .{
        python_lib_single_thread, python_lib
    };
    inline for (&python_libs) |lib| {
        lib.linkLibC();
        lib.root_module.addImport("leviathan", leviathan_module);
        lib.root_module.addImport("python_c", python_c_module);
        lib.root_module.addImport("jdz_allocator", jdz_allocator_module);

        const compile_python_lib = b.addInstallArtifact(lib, .{});
        b.getInstallStep().dependOn(&compile_python_lib.step);
    }

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
