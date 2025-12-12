const std = @import("std");
const builtin = @import("builtin");
const posix = std.posix;
const assert = std.debug.assert;

const CAP_RIGHTS_VERSION_00 = 0;
const CAP_RIGHTS_VERSION = CAP_RIGHTS_VERSION_00;

const CAP_READ: u64 = 0x200000000000001;
const CAP_FSTAT: u64 = 0x200000000080000;

const cap_rights_t = extern struct {
    cr_rights: [CAP_RIGHTS_VERSION + 2]u64,
};

const capabilities = packed struct(u32) {
    reserved: u32 = 0,
};

extern "c" fn __cap_rights_init(version: c_int, rights: *cap_rights_t, ...) *cap_rights_t;
extern "c" fn cap_rights_limit(fd: c_int, rights: *const cap_rights_t) c_int;
extern "c" fn cap_enter() c_int;

pub fn lockdown_dir(dir: std.fs.Dir) !void {
    _ = dir;

    if (cap_enter() != 0)
        return error.InvalidResponse;
}
