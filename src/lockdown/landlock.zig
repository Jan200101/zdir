const std = @import("std");
const builtin = @import("builtin");
const posix = std.posix;
const linux = std.os.linux;

const landlock_create_ruleset_flags = packed struct(u32) {
    VERSION: bool = false,
    ERRATA: bool = false,
    reserved: u30 = 0,
};

const landlock_access_fs = packed struct(u64) {
    EXECUTE: bool = false,
    WRITE_FILE: bool = false,
    READ_FILE: bool = false,
    READ_DIR: bool = false,
    REMOVE_DIR: bool = false,
    REMOVE_FILE: bool = false,
    MAKE_CHAR: bool = false,
    MAKE_DIR: bool = false,
    MAKE_REG: bool = false,
    MAKE_SOCK: bool = false,
    MAKE_FIFO: bool = false,
    MAKE_BLOCK: bool = false,
    MAKE_SYM: bool = false,
    REFER: bool = false,
    TRUNCATE: bool = false,
    IOCTL_DEV: bool = false,
    reserved: u48 = 0,

    const Self = @This();

    fn all() !Self {
        const abi = try landlock_create_ruleset(null, 0, .{ .VERSION = true });

        var fs_access: Self = .{
            .EXECUTE = true,
            .WRITE_FILE = true,
            .READ_FILE = true,
            .READ_DIR = true,
            .REMOVE_DIR = true,
            .REMOVE_FILE = true,
            .MAKE_CHAR = true,
            .MAKE_DIR = true,
            .MAKE_REG = true,
            .MAKE_SOCK = true,
            .MAKE_FIFO = true,
            .MAKE_BLOCK = true,
            .MAKE_SYM = true,
            .REFER = true,
            .TRUNCATE = true,
            .IOCTL_DEV = true,
        };

        sw: switch (abi) {
            1 => {
                fs_access.REFER = false;
                continue :sw 2;
            },
            2 => {
                fs_access.TRUNCATE = false;
                continue :sw 4;
            },
            4 => {
                fs_access.IOCTL_DEV = false;
                continue :sw 5;
            },
            5 => {
                fs_access.IOCTL_DEV = false;
            },
            else => {},
        }

        return fs_access;
    }
};

const landlock_rule_type = enum(u32) {
    NONE,
    PATH_BENEATH = 1,
    RULE_NET_PORT,
};
const LANDLOCK_RULE_PATH_BENEATH = 1;

const landlock_ruleset_attr = extern struct {
    handled_access_fs: landlock_access_fs = .{},
    handled_access_net: u64 = 0,
    scoped: u64 = 0,
};

const landlock_path_beneath_attr = extern struct {
    allowed_access: landlock_access_fs = .{},
    parent_fd: i32 = 0,
};

fn landlock_create_ruleset(
    attr: ?*const landlock_ruleset_attr,
    size: usize,
    flags: landlock_create_ruleset_flags,
) !posix.fd_t {
    const bitflags: u32 = @bitCast(flags);
    const rc = linux.syscall3(.landlock_create_ruleset, @intFromPtr(attr), size, bitflags);
    switch (posix.errno(rc)) {
        .SUCCESS => return @intCast(rc),
        .OPNOTSUPP => return error.UnsupportedFeature,
        .INVAL => unreachable,
        .@"2BIG" => return error.TooBig,
        .FAULT => @panic("invalid API usage"),
        .NOMSG => unreachable,
        .NOSYS => return error.SystemOutdated,
        else => |err| return posix.unexpectedErrno(err),
    }
}

fn landlock_add_rule(
    ruleset_fd: posix.fd_t,
    rule_type: landlock_rule_type,
    rule_attr: *const anyopaque,
    flags: u32,
) !void {
    const rc = linux.syscall4(.landlock_add_rule, @bitCast(@as(isize, ruleset_fd)), @intFromEnum(rule_type), @intFromPtr(rule_attr), flags);
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
    // for lockdown to work we need to request no new privs
    // this prevents any priviledge escalation incase of an exploit
    _ = try posix.prctl(.SET_NO_NEW_PRIVS, .{ 1, 0, 0, 0 });

    const fs_access: landlock_access_fs = try .all();

    var ruleset: landlock_ruleset_attr = .{
        .handled_access_fs = fs_access,
    };
    const ruleset_fd = try landlock_create_ruleset(&ruleset, @sizeOf(landlock_ruleset_attr), .{});
    defer posix.close(ruleset_fd);

    var path_rule: landlock_path_beneath_attr = .{
        .allowed_access = .{
            .READ_FILE = true,
            .READ_DIR = true,
        },
        .parent_fd = dir.fd,
    };
    try landlock_add_rule(ruleset_fd, .PATH_BENEATH, &path_rule, 0);

    try landlock_restrict_self(ruleset_fd, 0);
}
