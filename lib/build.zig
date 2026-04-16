const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const is_android = target.result.abi == .android;
    const is_wasm = target.result.cpu.arch.isWasm();

    // ========================================================================
    // Shared library target (for Flutter FFI) - no raylib dependency
    // Usage: zig build lib [-Dtarget=aarch64-linux-android]
    // ========================================================================
    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/ffi.zig"),
        .target = target,
        .optimize = optimize,
    });
    if (!is_wasm) {
        lib_mod.link_libc = true;
    }

    const lib_linkage: std.builtin.LinkMode = if (is_wasm) .dynamic else .dynamic;
    const lib = b.addLibrary(.{
        .name = "nez_emu",
        .root_module = lib_mod,
        .linkage = lib_linkage,
    });

    const lib_install = b.addInstallArtifact(lib, .{});

    const lib_step = b.step("lib", "Build the shared library for Flutter FFI");
    lib_step.dependOn(&lib_install.step);

    // ========================================================================
    // WASM target — builds nez_emu.wasm for web
    // Usage: zig build wasm
    // ========================================================================
    const wasm_step = b.step("wasm", "Build the WASM module for web");

    const wasm_target = std.Target.Query{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    };

    const wasm_mod = b.createModule(.{
        .root_source_file = b.path("src/ffi_wasm.zig"),
        .target = b.resolveTargetQuery(wasm_target),
        .optimize = optimize,
    });

    // Build as executable — Zig produces a .wasm file when target is wasm32
    // Using executable instead of shared library avoids -fPIC relocation issues
    const wasm_exe = b.addExecutable(.{
        .name = "nez_emu",
        .root_module = wasm_mod,
    });

    // Export all nez_* functions for JS interop
    wasm_exe.rdynamic = true;
    // WASM: no entry point needed, we export functions for JS to call
    wasm_exe.entry = .disabled;

    const wasm_install = b.addInstallArtifact(wasm_exe, .{});
    wasm_step.dependOn(&wasm_install.step);

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
