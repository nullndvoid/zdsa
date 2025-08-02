const std = @import("std");
pub fn build(b: *std.Build) void {
    //   _ = b; // stub
    const opt = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});
    const exe = b.addExecutable(.{
        .name = "dsa",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .optimize = opt,
            .target = target,
        }),
    });

    const pretty = b.dependency("pretty", .{
        .target = target,
        .optimize = opt,
    });
    exe.root_module.addImport("pretty", pretty.module("pretty"));

    b.default_step.dependOn(&exe.step);
    const installStep = b.addInstallArtifact(exe, .{ .dest_dir = .default });

    b.default_step.dependOn(&installStep.step);
}
