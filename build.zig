const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const skip_vulkan = b.option(bool, "skip-vulkan", "Build without Vulkan") orelse false;
    const enable_vulkan = !skip_vulkan and findVkXml() != null;

    const build_options = b.addOptions();
    build_options.addOption(bool, "has_vulkan", enable_vulkan);

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    exe_mod.addOptions("build_options", build_options);

    if (enable_vulkan) {
        const vk_xml = findVkXml().?;
        const vulkan_dep = b.dependency("vulkan", .{
            .registry = @as(std.Build.LazyPath, .{ .cwd_relative = vk_xml }),
        });
        const vk_module = vulkan_dep.module("vulkan-zig");
        exe_mod.addImport("vulkan", vk_module);
        exe_mod.linkSystemLibrary("vulkan", .{});

        // compile GLSL to SPIR-V and embed
        const glsl_compile = b.addSystemCommand(&.{
            "glslangValidator",
            "--target-env",
            "vulkan1.2",
            "-S",
            "comp",
            "-o",
        });
        const spv_output = glsl_compile.addOutputFileArg("pathtracer.spv");
        glsl_compile.addFileArg(b.path("shaders/pathtracer.comp"));

        exe_mod.addAnonymousImport("pathtracer_spv", .{
            .root_source_file = spv_output,
        });
    }

    const exe = b.addExecutable(.{
        .name = "schism",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run schism");
    run_step.dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run unit tests");

    const test_files = [_][]const u8{
        "src/math.zig",
        "src/spectrum.zig",
        "src/fractals.zig",
        "src/camera.zig",
        "src/seed.zig",
    };

    for (test_files) |path| {
        const t = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(path),
                .target = target,
                .optimize = optimize,
            }),
        });
        const run_t = b.addRunArtifact(t);
        test_step.dependOn(&run_t.step);
    }
}

fn findVkXml() ?[]const u8 {
    const paths = [_][]const u8{
        "/opt/homebrew/share/vulkan/registry/vk.xml",
        "/usr/share/vulkan/registry/vk.xml",
        "/usr/local/share/vulkan/registry/vk.xml",
    };
    for (paths) |path| {
        std.fs.cwd().access(path, .{}) catch continue;
        return path;
    }
    return null;
}
