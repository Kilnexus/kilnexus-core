const std = @import("std");
const common = @import("common.zig");
const interception_common = @import("../../interception/common.zig");
const cargo_config = @import("../../interception/cargo/config.zig");
const cargo_wrapper = @import("../../interception/cargo/wrapper.zig");
const wrapper_gen = @import("../../interception/wrapper_gen.zig");
const paths_config = @import("../../paths/config.zig");

pub const adapter: common.BuildSystemAdapter = .{
    .prepareInterception = prepareInterception,
    .generateConfig = generateConfig,
    .wrapCommand = wrapCommand,
    .validateToolchain = validateToolchain,
};

fn prepareInterception(
    allocator: std.mem.Allocator,
    cwd: std.fs.Dir,
    target: @import("../../root.zig").toolchain_cross.target.CrossTarget,
    toolchain: common.ToolchainContext,
) !interception_common.InterceptionEnv {
    var env = interception_common.InterceptionEnv.init(allocator);
    env.env_map.deinit();
    env.env_map = try std.process.getEnvMap(allocator);
    env.target = target;
    env.zig_path = try env.storeOwned(toolchain.zig_path);
    env.rustc_path = if (toolchain.rustc_path) |path| try env.storeOwned(path) else null;
    env.cargo_path = if (toolchain.cargo_path) |path| try env.storeOwned(path) else null;
    env.sysroot = if (toolchain.sysroot) |root| try env.storeOwned(root) else null;

    const wrapper_dir = try paths_config.projectPath(allocator, &[_][]const u8{ "interception", "wrappers" });
    try env.setWrapperDir(wrapper_dir);
    allocator.free(wrapper_dir);
    _ = cwd;
    return env;
}

fn generateConfig(allocator: std.mem.Allocator, cwd: std.fs.Dir, env: *interception_common.InterceptionEnv) !void {
    if (env.target == null or env.zig_path == null) return error.MissingToolchain;
    const target = env.target.?;
    const zig_target = target.toZigTarget();

    const wrapper_dir = env.wrapper_dir orelse return error.MissingWrapperDir;
    const linker_wrapper = try wrapper_gen.generateWrapper(env, cwd, wrapper_dir, .{
        .name = "knx-linker",
        .target_path = env.zig_path.?,
        .extra_args = if (env.sysroot) |root|
            &[_][]const u8{ "cc", "-target", zig_target, "--sysroot", root }
        else
            &[_][]const u8{ "cc", "-target", zig_target },
    });
    defer env.allocator.free(linker_wrapper);

    const cargo_cfg = try cargo_config.writeConfig(allocator, cwd, .{
        .target = target,
        .linker_path = linker_wrapper,
        .rustflags = &[_][]const u8{},
    });
    defer allocator.free(cargo_cfg);

    const cargo_home = try paths_config.projectPath(allocator, &[_][]const u8{ "interception", "cargo" });
    defer allocator.free(cargo_home);
    try env.putEnv("CARGO_HOME", cargo_home);

    if (env.cargo_path) |cargo_path| {
        _ = try wrapper_gen.generateWrapper(env, cwd, wrapper_dir, .{
            .name = "cargo",
            .target_path = cargo_path,
            .extra_args = &[_][]const u8{ "--target", target.toRustTarget() },
        });
    }
    if (env.rustc_path) |rustc_path| {
        _ = try wrapper_gen.generateWrapper(env, cwd, wrapper_dir, .{
            .name = "rustc",
            .target_path = rustc_path,
            .extra_args = &[_][]const u8{ "--target", target.toRustTarget() },
        });
    }
}

fn wrapCommand(allocator: std.mem.Allocator, argv: []const []const u8, env: *interception_common.InterceptionEnv) ![]const []const u8 {
    if (env.target == null) return error.MissingTarget;
    return cargo_wrapper.wrap(allocator, argv, env.target.?.toRustTarget());
}

fn validateToolchain(toolchain: common.ToolchainContext, _: @import("../../root.zig").toolchain_cross.target.CrossTarget) !void {
    if (toolchain.rustc_path == null or toolchain.cargo_path == null) return error.MissingToolchain;
}
