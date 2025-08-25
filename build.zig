const std = @import("std");

pub fn build(b: *std.Build) void {
    const opt = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const mod = b.addModule("zdsa", .{
        .root_source_file = b.path("src/lib.zig"),

        .target = target,
    });

    const exe = b.addExecutable(.{
        .name = "dsa",
        .root_module = b.createModule(.{ .root_source_file = b.path("src/main.zig"), .optimize = opt, .target = target, .imports = &.{
            .{ .name = "zdsa", .module = mod },
        } }),
    });

    b.default_step.dependOn(&exe.step);

    const no_bin = b.option(bool, "no-bin", "Do not emit a binary, use when checking for errors.") orelse false;

    if (no_bin) {
        b.getInstallStep().dependOn(&exe.step);
    } else {
        const install_exe = b.addInstallArtifact(exe, .{
            .dest_dir = .default,
        });
        b.getInstallStep().dependOn(&install_exe.step);
    }

    // b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
}
