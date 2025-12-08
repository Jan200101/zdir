const std = @import("std");
const builtin = @import("builtin");
const native_arch = builtin.cpu.arch;
const posix = std.posix;
const system = posix.system;
const linux = std.os.linux;

const LANDLOCK_CREATE_RULESET_VERSION = 1 << 0;
const LANDLOCK_ACCESS_FS_READ_FILE = 1 << 2;

const LANDLOCK_RULE_PATH_BENEATH = 1;

const landlock_ruleset_attr = extern struct {
    handled_access_fs: u64 = 0,
    handled_access_net: u64 = 0,
    scoped: u64 = 0,
};

const landlock_path_beneath_attr = extern struct {
    allowed_access: u64 = 0,
    parent_fd: i32 = 0,
};

fn landlock_create_ruleset(
    attr: ?*const landlock_ruleset_attr,
    size: usize,
    flags: u32,
) !posix.fd_t {
    const rc = linux.syscall3(.landlock_create_ruleset, @intFromPtr(attr), size, flags);
    switch (posix.errno(rc)) {
        .SUCCESS => return @intCast(rc),
        .OPNOTSUPP => return error.UnsupportedFeature,
        .INVAL => unreachable,
        .@"2BIG" => return error.TooBig,
        .FAULT => @panic("invalid API usage"),
        .NOMSG => unreachable,
        else => |err| return posix.unexpectedErrno(err),
    }
}

fn landlock_add_rule(
    ruleset_fd: posix.fd_t,
    rule_type: c_uint,
    rule_attr: *const anyopaque,
    flags: u32,
) !void {
    const rc = linux.syscall4(.landlock_add_rule, @bitCast(@as(isize, ruleset_fd)), rule_type, @intFromPtr(rule_attr), flags);
    switch (posix.errno(rc)) {
        .SUCCESS => return {},
        else => |err| return posix.unexpectedErrno(err),
    }
}

fn landlock_restrict_self(
    ruleset_fd: posix.fd_t,
    flags: u32,
) !void {
    const rc = linux.syscall2(.landlock_restrict_self, @bitCast(@as(isize, ruleset_fd)), flags);
    switch (posix.errno(rc)) {
        .SUCCESS => return {},
        .INVAL => unreachable,
        .BADF => unreachable,
        .BADFD => unreachable,
        .PERM => unreachable,
        .@"2BIG" => return error.TooBig,
        else => |err| return posix.unexpectedErrno(err),
    }
}

pub fn lockdown_dir(dir: std.fs.Dir) !void {

    _ = try landlock_create_ruleset(null, 0, LANDLOCK_CREATE_RULESET_VERSION);

    var ruleset: landlock_ruleset_attr = .{
        .handled_access_fs = LANDLOCK_ACCESS_FS_READ_FILE,
    };
    const ruleset_fd = try landlock_create_ruleset(&ruleset, @sizeOf(landlock_ruleset_attr), 0);
    defer posix.close(ruleset_fd);

    var path_rule: landlock_path_beneath_attr = .{
        .allowed_access = LANDLOCK_ACCESS_FS_READ_FILE,
        .parent_fd = dir.fd,
    };
    try landlock_add_rule(ruleset_fd, LANDLOCK_RULE_PATH_BENEATH, &path_rule, 0);

    _ = try posix.prctl(.SET_NO_NEW_PRIVS, .{ 1, 0, 0, 0 });
    try landlock_restrict_self(ruleset_fd, 0);
}
