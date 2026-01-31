const std = @import("std");
const common = @import("common.zig");
const interception_common = @import("../../interception/common.zig");
const cmake_toolchain = @import("../../interception/cmake/toolchain.zig");
const cmake_wrapper = @import("../../interception/cmake/wrapper.zig");
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

    return env;
}

fn generateConfig(
    allocator: std.mem.Allocator,
    cwd: std.fs.Dir,
    env: *interception_common.InterceptionEnv,
) !void {
    if (env.target == null or env.zig_path == null) return error.MissingToolchain;
    const toolchain_path = try cmake_toolchain.writeToolchainFile(allocator, cwd, .{
        .target = env.target.?,
        .zig_path = env.zig_path.?,
        .sysroot = env.sysroot,
    });
    try env.setToolchainFile(toolchain_path);
    allocator.free(toolchain_path);
}

fn wrapCommand(
    allocator: std.mem.Allocator,
    argv: []const []const u8,
    env: *interception_common.InterceptionEnv,
) ![]const []const u8 {
    if (env.toolchain_file == null) return error.MissingToolchainFile;
    return cmake_wrapper.wrap(allocator, argv, env.toolchain_file.?);
}

fn validateToolchain(_: common.ToolchainContext, _: @import("../../root.zig").toolchain_cross.target.CrossTarget) !void {
    return;
}
