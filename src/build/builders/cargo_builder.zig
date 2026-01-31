const std = @import("std");
const builtin = @import("builtin");
const core = @import("../../root.zig");
const toolchain = @import("../../cli/toolchain_resolver.zig");
const adapter = @import("../../toolchain/adapters/cargo.zig");
const adapter_common = @import("../../toolchain/adapters/common.zig");
const interception_env = @import("../../interception/env_injector.zig");
const wrapper_gen = @import("../../interception/wrapper_gen.zig");
const build_types = @import("../types.zig");

pub fn buildCargo(allocator: std.mem.Allocator, cwd: std.fs.Dir, stdout: anytype, inputs: build_types.BuildInputs) !void {
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
    var rust_paths = toolchain.resolveOrBootstrapRust(
        allocator,
        cwd,
        stdout,
        inputs.rust_version,
        inputs.bootstrap_sources.rust,
    ) catch return;
    defer rust_paths.deinit(allocator);

    const toolchain_ctx = adapter_common.ToolchainContext{
        .zig_path = zig_path,
        .rustc_path = rust_paths.rustc,
        .cargo_path = rust_paths.cargo,
        .sysroot = inputs.env.sysroot,
    };
    try adapter.adapter.validateToolchain(toolchain_ctx, target);
    var env = try adapter.adapter.prepareInterception(allocator, cwd, target, toolchain_ctx);
    defer env.deinit();

    try adapter.adapter.generateConfig(allocator, cwd, &env);
    try wrapper_gen.generate(&env);
    try interception_env.inject(&env);

    const source_dir = try resolveSourceDir(allocator, cwd, inputs.path);
    defer allocator.free(source_dir);
    const manifest_path = try std.fs.path.join(allocator, &[_][]const u8{ source_dir, "Cargo.toml" });
    defer allocator.free(manifest_path);
    if (!existsPath(manifest_path)) {
        try stdout.print("!! Cargo manifest not found: {s}\n", .{manifest_path});
        return error.MissingCargoManifest;
    }

    try stdout.print(">> Cargo interception: target {s}, wrappers {s}\n", .{
        target.toRustTarget(),
        env.wrapper_dir orelse "(none)",
    });

    const cargo_args = &[_][]const u8{ "cargo", "build" };
    const wrapped = try adapter.adapter.wrapCommand(allocator, cargo_args, &env);
    defer allocator.free(wrapped);

    try runInDirWithEnv(allocator, source_dir, wrapped, &env.env_map);
    try stdout.print(">> Cargo build complete.\n", .{});
}

pub fn isCargoProject(cwd: std.fs.Dir, path: []const u8) bool {
    if (std.mem.endsWith(u8, path, "Cargo.toml")) return true;
    var dir = cwd.openDir(path, .{}) catch return false;
    defer dir.close();
    dir.access("Cargo.toml", .{}) catch return false;
    return true;
}

fn resolveSourceDir(allocator: std.mem.Allocator, cwd: std.fs.Dir, path: []const u8) ![]const u8 {
    if (std.mem.endsWith(u8, path, "Cargo.toml")) {
        const dir = std.fs.path.dirname(path) orelse ".";
        return allocator.dupe(u8, dir);
    }
    _ = cwd;
    return allocator.dupe(u8, path);
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

fn existsPath(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

fn runInDirWithEnv(
    allocator: std.mem.Allocator,
    dir_path: []const u8,
    argv: []const []const u8,
    env_map: *std.process.EnvMap,
) !void {
    var cwd_dir = try std.fs.cwd().openDir(dir_path, .{});
    defer cwd_dir.close();
    var child = std.process.Child.init(argv, allocator);
    child.cwd_dir = cwd_dir;
    child.stdin_behavior = .Inherit;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;
    child.env_map = env_map;
    const term = try child.spawnAndWait();
    switch (term) {
        .Exited => |code| {
            if (code != 0) return error.CompileFailed;
        },
        else => return error.CompileFailed,
    }
}
