const std = @import("std");
const core = @import("../../root.zig");
const interception_common = @import("../../interception/common.zig");

pub const ToolchainContext = struct {
    zig_path: []const u8,
    rustc_path: ?[]const u8 = null,
    cargo_path: ?[]const u8 = null,
    sysroot: ?[]const u8 = null,
};

pub const BuildSystemAdapter = struct {
    prepareInterception: *const fn (
        allocator: std.mem.Allocator,
        cwd: std.fs.Dir,
        target: core.toolchain_cross.target.CrossTarget,
        toolchain: ToolchainContext,
    ) anyerror!interception_common.InterceptionEnv,
    generateConfig: *const fn (
        allocator: std.mem.Allocator,
        cwd: std.fs.Dir,
        env: *interception_common.InterceptionEnv,
    ) anyerror!void,
    wrapCommand: *const fn (
        allocator: std.mem.Allocator,
        argv: []const []const u8,
        env: *interception_common.InterceptionEnv,
    ) anyerror![]const []const u8,
    validateToolchain: *const fn (
        toolchain: ToolchainContext,
        target: core.toolchain_cross.target.CrossTarget,
    ) anyerror!void,
};
