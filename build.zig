pub fn build(b: *std.Build) void {
    const target_wasm = b.resolveTargetQuery(.{
        .abi = .none,
        .os_tag = .freestanding,
        .cpu_arch = .wasm32,
    });

    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .safe,
    });

    const dots_dep = b.dependency("dots", .{});
    const dots = dots_dep.module("dots");

    const wasm = b.createModule(.{
        .root_source_file = b.path("src/wasm.zig"),
    });

    const background_wasm = b.addExecutable(.{
        .name = "background",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/gfx/background.zig"),
            .target = target_wasm,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "dots", .module = dots },
                .{ .name = "wasm", .module = wasm },
            },
        }),
    });

    background_wasm.entry = .disabled;
    background_wasm.rdynamic = true;

    const install_background_wasm = b.addInstallArtifact(background_wasm, .{
        .dest_dir = .{ .override = .{ .custom = std.fs.path.dirname(
            background_wasm
                .root_module
                .root_source_file.?
                .src_path
                .sub_path["src/".len..],
        ).? } },
    });

    const install_static_files = b.addInstallDirectory(.{
        .source_dir = b.path("src"),
        .install_dir = .prefix,
        .install_subdir = "",
        .include_extensions = &.{ "html", "css", "js", "stl", "woff2", "CNAME" },
    });

    const install_step = b.getInstallStep();
    install_step.dependOn(&install_background_wasm.step);
    install_step.dependOn(&install_static_files.step);

    const target_host = b.resolveTargetQuery(.{});

    const http_server_exe = b.addExecutable(.{
        .name = "http_server",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tools/http_server.zig"),
            .target = target_host,
            .optimize = .debug,
        }),
    });

    const http_server_exe_run = b.addRunArtifact(http_server_exe);
    http_server_exe_run.step.dependOn(install_step);

    const override_serve_args_opt = b.option(bool, "overrideServeArgs", "override args provided to serve");
    if (override_serve_args_opt orelse false)
        http_server_exe_run.addPassthruArgs()
    else
        http_server_exe_run.addArgs(&.{
            "--host",
            "127.0.0.1:8080",
            "--root",
            b.pathJoin(&.{ b.root.root_dir.path.?, "zig-out" }),
        });

    const serve_step = b.step("serve", "small http server for viewing zig-out");
    serve_step.dependOn(&http_server_exe_run.step);
}

const std = @import("std");
