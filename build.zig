const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const root_path = b.option([]const u8, "root", "root") orelse ".";
    const http_port = b.option(u32, "port", "HTTP Port") orelse 8888;
    const enable_lockdown = b.option(bool, "enable-lockdown", "lock down access to only the root directory") orelse true;
    const force_lockdown = b.option(bool, "force-lockdown", "terminate the program is lockdown cannot be initialized") orelse false;
    const fcgi_socket_path = b.option([]const u8, "fcgi-socket-path", "path to the unix socket used by the FastCGI program") orelse "/tmp/zdir.sock";

    // FreeBSD has no system layer yet
    const link_libc = if (enable_lockdown and target.result.os.tag == .freebsd)
        true
    else
        false;

    const options = b.addOptions();
    options.addOption([]const u8, "root_path", root_path);
    options.addOption(u32, "http_port", http_port);
    options.addOption(bool, "enable_lockdown", enable_lockdown);
    options.addOption(bool, "force_lockdown", force_lockdown);
    options.addOption([]const u8, "fcgi_socket_path", fcgi_socket_path);

    const mod = b.addModule("core", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    mod.addOptions("config", options);
    mod.addAnonymousImport("robots.txt", .{ .root_source_file = b.path("assets/robots.txt") });
    mod.addAnonymousImport("favicon.ico", .{ .root_source_file = b.path("assets/favicon.ico") });
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
                .{ .name = "core", .module = mod },
            },
            .link_libc = link_libc,
        }),
    });
    b.installArtifact(http_exe);

    const run_step = b.step("run", "Run the HTTP App");
    const run_cmd = b.addRunArtifact(http_exe);
    run_step.dependOn(&run_cmd.step);

    const cgi_exe = b.addExecutable(.{
        .name = "zdir-cgi",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/cgi.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "core", .module = mod },
            },
            .link_libc = link_libc,
        }),
    });
    b.installArtifact(cgi_exe);

    const cgi_run_step = b.step("run-cgi", "Run the CGI App");
    const cgi_run_cmd = b.addRunArtifact(cgi_exe);
    cgi_run_step.dependOn(&cgi_run_cmd.step);

    const fcgi_exe = b.addExecutable(.{
        .name = "zdir-fcgi",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/fcgi.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "core", .module = mod },
            },
        }),
    });
    b.installArtifact(fcgi_exe);

    const fcgi_run_step = b.step("run-fcgi", "Run the FastCGI App");
    const fcgi_run_cmd = b.addRunArtifact(fcgi_exe);
    fcgi_run_step.dependOn(&fcgi_run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());
    cgi_run_cmd.step.dependOn(b.getInstallStep());
    fcgi_run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
        cgi_run_cmd.addArgs(args);
        fcgi_run_cmd.addArgs(args);
    }

    const mod_tests = b.addTest(.{
        .root_module = mod,
        .use_llvm = true,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
}
