const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const root_path = b.option([]const u8, "root", "root") orelse ".";
    blk: {
        if (!target.query.isNative())
            break :blk;

        var dir = std.fs.cwd().openDir(root_path, .{}) catch |err| {
            std.debug.print("{s} is not a directory: {s}\n", .{ root_path, @errorName(err) });
            std.process.exit(1);
        };
        dir.close();
    }

    const options = b.addOptions();
    options.addOption([]const u8, "root_path", root_path);

    const mod = b.addModule("code", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    mod.addOptions("config", options);
    mod.addAnonymousImport("head.html", .{ .root_source_file = b.path("assets/head.html") });
    mod.addAnonymousImport("body.html", .{ .root_source_file = b.path("assets/body.html") });
    mod.addAnonymousImport("root.html", .{ .root_source_file = b.path("assets/root.html") });
    mod.addAnonymousImport("style.css", .{ .root_source_file = b.path("assets/style.css") });

    const http_exe = b.addExecutable(.{
        .name = "zdir-http",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/http.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "code", .module = mod },
            },
        }),
    });
    b.installArtifact(http_exe);

    const cgi_exe = b.addExecutable(.{
        .name = "zdir-cgi",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/cgi.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "code", .module = mod },
            },
        }),
    });
    b.installArtifact(cgi_exe);

    const run_step = b.step("run", "Run the HTTP App");
    const run_cmd = b.addRunArtifact(http_exe);
    run_step.dependOn(&run_cmd.step);

    const cgi_run_step = b.step("run-cgi", "Run the CGI App");
    const cgi_run_cmd = b.addRunArtifact(cgi_exe);
    cgi_run_step.dependOn(&cgi_run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());
    cgi_run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
        cgi_run_cmd.addArgs(args);
    }

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = http_exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
