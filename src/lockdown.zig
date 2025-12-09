const std = @import("std");
const builtin = @import("builtin");
const native_os = builtin.os.tag;
const log = std.log;

const landlock = @import("lockdown/landlock.zig");

const lockdown_impls = enum {
    none,
    landlock,
};

pub fn lockdown_dir(dir: std.fs.Dir) !void {
    const impl = switch (native_os) {
        .linux => .landlock,
        else => .none,
    };

    log.info("lockdown implementation: {s}", .{@tagName(impl)});

    switch (impl) {
        .landlock => try landlock.lockdown_dir(dir),
        .none => {},
        else => {},
    }
}
