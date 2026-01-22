const std = @import("std");

/// Shared toolchain types.
pub const VirtualEnv = struct {
    target: ?[]const u8 = null,
    kernel_version: ?[]const u8 = null,
    sysroot: ?[]const u8 = null,
    virtual_root: ?[]const u8 = null,
};

/// Common compiler options used by planners and executors.
pub const CompileOptions = struct {
    output_name: []const u8 = "a.out",
    static: bool = true,
    zig_path: []const u8 = "zig",
    rustc_path: []const u8 = "rustc",
    cargo_path: []const u8 = "cargo",
    env: VirtualEnv = .{},
    rust_crate_type: ?[]const u8 = null,
    rust_edition: ?[]const u8 = null,
    cargo_manifest_path: ?[]const u8 = null,
    cargo_release: bool = false,
    extra_args: []const []const u8 = &[_][]const u8{},
};

comptime {
    _ = std;
}
