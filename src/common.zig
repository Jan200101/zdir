const builtin = @import("builtin");

// 30 minutes
pub const CACHE_AGE = 60 * 30;

pub const is_debug = switch (builtin.mode) {
    .Debug, .ReleaseSafe => true,
    .ReleaseFast, .ReleaseSmall => false,
};
