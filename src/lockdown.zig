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

pub fn lockdown_dir(dir: std.fs.Dir) !void {
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
