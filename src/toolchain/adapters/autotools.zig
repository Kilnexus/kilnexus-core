const std = @import("std");
const common = @import("common.zig");
const interception_common = @import("../../interception/common.zig");
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

    const cc_wrapper = try wrapper_gen.generateWrapper(env, cwd, wrapper_dir, .{
        .name = "cc",
        .target_path = env.zig_path.?,
        .extra_args = if (env.sysroot) |root|
            &[_][]const u8{ "cc", "-target", zig_target, "--sysroot", root }
        else
            &[_][]const u8{ "cc", "-target", zig_target },
    });
    defer env.allocator.free(cc_wrapper);
    const cxx_wrapper = try wrapper_gen.generateWrapper(env, cwd, wrapper_dir, .{
        .name = "c++",
        .target_path = env.zig_path.?,
        .extra_args = if (env.sysroot) |root|
            &[_][]const u8{ "c++", "-target", zig_target, "--sysroot", root }
        else
            &[_][]const u8{ "c++", "-target", zig_target },
    });
    defer env.allocator.free(cxx_wrapper);
    const ar_wrapper = try wrapper_gen.generateWrapper(env, cwd, wrapper_dir, .{
        .name = "ar",
        .target_path = env.zig_path.?,
        .extra_args = &[_][]const u8{"ar"},
    });
    defer env.allocator.free(ar_wrapper);
    const ld_wrapper = try wrapper_gen.generateWrapper(env, cwd, wrapper_dir, .{
        .name = "ld",
        .target_path = env.zig_path.?,
        .extra_args = if (env.sysroot) |root|
            &[_][]const u8{ "cc", "-target", zig_target, "--sysroot", root }
        else
            &[_][]const u8{ "cc", "-target", zig_target },
    });
    defer env.allocator.free(ld_wrapper);

    try env.putEnv("CC", cc_wrapper);
    try env.putEnv("CXX", cxx_wrapper);
    try env.putEnv("AR", ar_wrapper);
    try env.putEnv("LD", ld_wrapper);
}

fn wrapCommand(allocator: std.mem.Allocator, argv: []const []const u8, _: *interception_common.InterceptionEnv) ![]const []const u8 {
    var out = try allocator.alloc([]const u8, argv.len);
    std.mem.copyForwards([]const u8, out, argv);
    return out;
}

fn validateToolchain(_: common.ToolchainContext, _: @import("../../root.zig").toolchain_cross.target.CrossTarget) !void {
    return;
}
