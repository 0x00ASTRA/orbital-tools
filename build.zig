const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const wayland: bool = b.option(bool, "wayland", "Use Wayland Linux Display Backend") orelse true;
    const x11: bool = b.option(bool, "x11", "Use X11 Linux Display Backend") orelse !wayland;

    const orbits_mod = b.addModule("orbits", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/root.zig"),
    });

    const raylib_dep = if (wayland and !x11) b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
        .linkage = .static,
        .linux_display_backend = .Wayland,
        .platform = .glfw,
    }) else b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
        .linkage = .static,
        .linux_display_backend = .X11,
        .platform = .glfw,
    });

    const raylib = raylib_dep.module("raylib"); // main raylib module
    const raygui = raylib_dep.module("raygui"); // raygui module
    const raylib_artifact = raylib_dep.artifact("raylib"); // raylib C library

    const exe_name: []const u8 = blk: {
        const os_tag = target.result.os.tag;

        break :blk switch (os_tag) {
            .linux => if (wayland and !x11)
                "OrbitalTools-Wayland"
            else
                "OrbitalTools-X11",

            else => "OrbitalTools",
        };
    };

    const exe = b.addExecutable(.{
        .name = exe_name,
        .version = .{ .major = 0, .minor = 3, .patch = 0, .build = "release" },
        .root_module = b.addModule("root_mod", .{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("src/main.zig"),
            .imports = &.{
                .{ .name = "orbits", .module = orbits_mod },
                .{ .name = "raylib", .module = raylib },
                .{ .name = "raygui", .module = raygui },
            },
        }),
    });

    exe.root_module.linkLibrary(raylib_artifact);

    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    const run_step = b.step("run", "run the program");
    run_step.dependOn(b.getInstallStep());
    run_step.dependOn(&run_exe.step);
}
