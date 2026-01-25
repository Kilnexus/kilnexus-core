pub const CrossTarget = @import("../toolchain/cross/target.zig").CrossTarget;
pub const SysrootSource = @import("../toolchain/cross/sysroot.zig").SysrootSource;
pub const SysrootSpec = @import("../toolchain/cross/sysroot.zig").SysrootSpec;

pub const DeterministicLevel = enum {
    Strict,
    Standard,
    Relaxed,
};

pub const IsolationLevel = enum {
    Full,
    Minimal,
    None,
};

pub const TargetSpec = struct {
    target: CrossTarget,
    sysroot: ?SysrootSpec = null,
};
