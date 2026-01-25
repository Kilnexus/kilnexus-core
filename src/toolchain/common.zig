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
    include_dirs: []const []const u8 = &[_][]const u8{},
    lib_dirs: []const []const u8 = &[_][]const u8{},
    link_libs: []const []const u8 = &[_][]const u8{},
    extra_sources: []const []const u8 = &[_][]const u8{},
    rust_crate_type: ?[]const u8 = null,
    rust_edition: ?[]const u8 = null,
    rust_crt_static: bool = false,
    rustflags_extra: []const []const u8 = &[_][]const u8{},
    cargo_manifest_path: ?[]const u8 = null,
    cargo_release: bool = false,
    extra_args: []const []const u8 = &[_][]const u8{},
};

comptime {
    _ = std;
}
