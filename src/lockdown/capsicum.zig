const std = @import("std");
const builtin = @import("builtin");
const posix = std.posix;

const CAP_RIGHTS_VERSION_00 = 0;
const CAP_RIGHTS_VERSION = CAP_RIGHTS_VERSION_00;

const cap_rights_t = struct {
    cr_rights: [CAP_RIGHTS_VERSION + 2]u64,
};

const capabilities = packed struct(u32) {
    reserved: u32 = 0,
};

fn cap_rights_init(rights: *const cap_rights_t, ...) void {
    _ = rights;
}

fn cap_rights_limit(fd: posix.fd_t, rights: *const cap_rights_t) !void {
    _ = fd;
    _ = rights;
}

pub extern "c" fn cap_enter() c_int;

pub fn lockdown_dir(dir: std.fs.Dir) !void {
    var setrights: cap_rights_t = undefined;

    cap_rights_init(&setrights, .{
        .READ = true,
        .FSTAT = true,
    });
    try cap_rights_limit(dir.fd, &setrights);

    try cap_enter();
}
