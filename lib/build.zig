const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const is_android = target.result.abi == .android;

    // ========================================================================
    // Shared library target (for Flutter FFI) - no raylib dependency
    // Usage: zig build lib [-Dtarget=aarch64-linux-android]
    // ========================================================================
    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/ffi.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib_mod.link_libc = true;

    const lib = b.addLibrary(.{
        .name = "nez_emu",
        .root_module = lib_mod,
        .linkage = .dynamic,
    });

    const lib_install = b.addInstallArtifact(lib, .{});

    const lib_step = b.step("lib", "Build the shared library for Flutter FFI");
    lib_step.dependOn(&lib_install.step);

    // ========================================================================
    // Executable target (original with raylib) - desktop only
    // Usage: zig build run -- [args]
    // ========================================================================
    if (!is_android) {
        const exe_mod = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        });

        const exe = b.addExecutable(.{
            .name = "nez",
            .root_module = exe_mod,
        });

        const raylib_dep = b.lazyDependency("raylib", .{
            .target = target,
            .optimize = optimize,
            .platform = .glfw,
            .config = "-DSUPPORT_CUSTOM_FRAME_CONTROL=0",
        });

        if (raylib_dep) |dep| {
            const raylib = dep.artifact("raylib");
            exe_mod.linkLibrary(raylib);
        }

        if (target.result.os.tag == .macos) {
            exe_mod.linkFramework("OpenGL", .{});
            exe_mod.linkFramework("Cocoa", .{});
            exe_mod.linkFramework("CoreAudio", .{});
            exe_mod.linkFramework("CoreVideo", .{});
        }

        b.installArtifact(exe);

        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(b.getInstallStep());

        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        const run_step = b.step("run", "Run the app");
        run_step.dependOn(&run_cmd.step);

        const exe_unit_tests = b.addTest(.{
            .root_module = exe_mod,
        });

        const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

        const test_step = b.step("test", "Run unit tests");
        test_step.dependOn(&run_exe_unit_tests.step);
    }
}
