const std = @import("std");
const builtin = @import("builtin");
const core = @import("../../root.zig");
const toolchain = @import("../../cli/toolchain_resolver.zig");
const adapters = @import("../../toolchain/adapters/cmake.zig");
const adapter_common = @import("../../toolchain/adapters/common.zig");
const interception_env = @import("../../interception/env_injector.zig");
const wrapper_gen = @import("../../interception/wrapper_gen.zig");
const paths_config = @import("../../paths/config.zig");
const build_types = @import("../types.zig");

pub fn buildCmake(allocator: std.mem.Allocator, cwd: std.fs.Dir, stdout: anytype, inputs: build_types.BuildInputs) !void {
    const target = inputs.cross_target orelse hostTarget() orelse {
        try stdout.print("!! Missing target: provide TARGET or set a host-supported target.\n", .{});
        return error.MissingTarget;
    };
    const zig_path = toolchain.resolveOrBootstrapZig(
        allocator,
        cwd,
        stdout,
        inputs.zig_version,
        inputs.bootstrap_sources.zig,
        inputs.bootstrap_seed,
    ) catch return;
    defer allocator.free(zig_path);

    const source_dir = try resolveSourceDir(allocator, cwd, inputs.path);
    defer allocator.free(source_dir);
    const cmake_list = try std.fs.path.join(allocator, &[_][]const u8{ source_dir, "CMakeLists.txt" });
    defer allocator.free(cmake_list);
    if (!existsPath(cmake_list)) {
        try stdout.print("!! CMakeLists.txt not found: {s}\n", .{cmake_list});
        return error.MissingCMakeLists;
    }

    const build_dir = try paths_config.projectPath(allocator, &[_][]const u8{ "build", "cmake" });
    defer allocator.free(build_dir);
    cwd.makePath(build_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    const toolchain_ctx = adapter_common.ToolchainContext{
        .zig_path = zig_path,
        .sysroot = inputs.env.sysroot,
    };
    try adapters.adapter.validateToolchain(toolchain_ctx, target);
    var env = try adapters.adapter.prepareInterception(allocator, cwd, target, toolchain_ctx);
    defer env.deinit();

    try adapters.adapter.generateConfig(allocator, cwd, &env);
    try wrapper_gen.generate(&env);
    try interception_env.inject(&env);

    const configure_args = &[_][]const u8{ "cmake", "-S", source_dir, "-B", build_dir };
    try core.toolchain_executor.runProcessWithEnv(allocator, cwd, configure_args, &env.env_map);

    const build_args = &[_][]const u8{ "cmake", "--build", build_dir };
    try core.toolchain_executor.runProcessWithEnv(allocator, cwd, build_args, &env.env_map);
    try stdout.print(">> CMake build complete.\n", .{});
}

pub fn isCmakeProject(cwd: std.fs.Dir, path: []const u8) bool {
    if (std.mem.endsWith(u8, path, "CMakeLists.txt")) return true;
    var dir = cwd.openDir(path, .{}) catch return false;
    defer dir.close();
    dir.access("CMakeLists.txt", .{}) catch return false;
    return true;
}

fn existsPath(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

fn hostTarget() ?core.toolchain_cross.target.CrossTarget {
    const arch: core.toolchain_cross.target.Arch = switch (builtin.target.cpu.arch) {
        .x86_64 => .x86_64,
        .aarch64 => .aarch64,
        else => return null,
    };
    const os: core.toolchain_cross.target.Os = switch (builtin.target.os.tag) {
        .linux => .linux,
        .windows => .windows,
        .macos => .macos,
        else => return null,
    };
    const abi: core.toolchain_cross.target.Abi = switch (os) {
        .linux => .gnu,
        .windows => .msvc,
        .macos => .none,
        else => .none,
    };
    return .{ .arch = arch, .os = os, .abi = abi };
}

fn resolveSourceDir(allocator: std.mem.Allocator, cwd: std.fs.Dir, path: []const u8) ![]const u8 {
    if (std.mem.endsWith(u8, path, "CMakeLists.txt")) {
        const dir = std.fs.path.dirname(path) orelse ".";
        return allocator.dupe(u8, dir);
    }
    _ = cwd;
    return allocator.dupe(u8, path);
}
