const std = @import("std");
const builtin = @import("builtin");
const native_os = builtin.os.tag;
const log = std.log;

const core = @import("core");
const landlock = @import("lockdown/landlock.zig");
const capsicum = @import("lockdown/capsicum.zig");

const lockdown_impls = enum {
    none,
    landlock,
    capsicum,
};

pub fn lockdown_dir(dir: std.fs.Dir) void {
    lockdown_dir_wrap(dir) catch |err| {
        log.err("Failed to initialize lockdown: {s}", .{@errorName(err)});

        if (core.config.force_lockdown) {
            @branchHint(.unlikely);
            @panic("Lockdown required but could not be initialized");
        }
    };
}

fn lockdown_dir_wrap(dir: std.fs.Dir) !void {
    if (!core.config.enable_lockdown)
        return;

    const impl = switch (native_os) {
        .linux => .landlock,
        .freebsd => .capsicum,
        else => .none,
    };

    log.info("lockdown implementation: {s}", .{@tagName(impl)});

    switch (impl) {
        .landlock => try landlock.lockdown_dir(dir),
        .capsicum => try capsicum.lockdown_dir(dir),
        else => {},
    }
}
