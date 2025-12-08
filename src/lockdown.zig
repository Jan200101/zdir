const std = @import("std");
const builtin = @import("builtin");
const native_os = builtin.os.tag;

const landlock = @import("lockdown/landlock.zig");

pub fn lockdown_dir(dir: std.fs.Dir) !void {
    switch (native_os) {
        .linux => try landlock.lockdown_dir(dir),
        else => {},
    }
}
