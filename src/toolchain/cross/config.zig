const std = @import("std");
const target_mod = @import("target.zig");
const sysroot_mod = @import("sysroot.zig");

pub const CrossCompileConfig = struct {
    cc: []const u8,
    cc_args: []const []const u8,
    cxx: []const u8,
    cxx_args: []const []const u8,
    linker: []const u8,
    linker_args: []const []const u8,
    ar: []const u8,
    sysroot: ?[]const u8,
    env_vars: std.process.EnvMap,
    owned: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator) CrossCompileConfig {
        return .{
            .cc = "",
            .cc_args = &[_][]const u8{},
            .cxx = "",
            .cxx_args = &[_][]const u8{},
            .linker = "",
            .linker_args = &[_][]const u8{},
            .ar = "",
            .sysroot = null,
            .env_vars = std.process.EnvMap.init(allocator),
            .owned = .empty,
        };
    }

    pub fn deinit(self: *CrossCompileConfig, allocator: std.mem.Allocator) void {
        for (self.owned.items) |item| allocator.free(item);
        self.owned.deinit(allocator);
        self.env_vars.deinit();
    }
};

pub fn buildConfig(
    allocator: std.mem.Allocator,
    target: target_mod.CrossTarget,
    zig_path: []const u8,
    sysroot_spec: ?sysroot_mod.SysrootConfig,
) !CrossCompileConfig {
    var config = CrossCompileConfig.init(allocator);
    errdefer config.deinit(allocator);

    const zig_target = target.toZigTarget();
    config.cc = zig_path;
    config.cxx = zig_path;
    config.linker = zig_path;
    config.ar = zig_path;

    config.cc_args = try buildZigArgs(allocator, "cc", zig_target, sysroot_spec);
    config.cxx_args = try buildZigArgs(allocator, "c++", zig_target, sysroot_spec);
    config.linker_args = try buildZigLinkArgs(allocator, zig_target, sysroot_spec);
    if (sysroot_spec) |sysroot| {
        config.sysroot = sysroot.root;
    }

    return config;
}

fn buildZigArgs(
    allocator: std.mem.Allocator,
    mode: []const u8,
    target: []const u8,
    sysroot: ?sysroot_mod.SysrootConfig,
) ![]const []const u8 {
    var args = std.ArrayList([]const u8).empty;
    defer args.deinit(allocator);

    try args.appendSlice(allocator, &[_][]const u8{ mode, "-target", target });
    if (sysroot) |spec| {
        if (spec.root) |root| {
            try args.appendSlice(allocator, &[_][]const u8{ "--sysroot", root });
        }
    }
    return try args.toOwnedSlice(allocator);
}

fn buildZigLinkArgs(
    allocator: std.mem.Allocator,
    target: []const u8,
    sysroot: ?sysroot_mod.SysrootConfig,
) ![]const []const u8 {
    var args = std.ArrayList([]const u8).empty;
    defer args.deinit(allocator);

    try args.appendSlice(allocator, &[_][]const u8{ "cc", "-target", target, "-static" });
    if (sysroot) |spec| {
        if (spec.root) |root| {
            try args.appendSlice(allocator, &[_][]const u8{ "--sysroot", root });
        }
    }
    return try args.toOwnedSlice(allocator);
}
