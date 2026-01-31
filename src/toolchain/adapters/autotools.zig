const std = @import("std");
const common = @import("common.zig");
const interception_common = @import("../../interception/common.zig");

pub const adapter: common.BuildSystemAdapter = .{
    .prepareInterception = prepareInterception,
    .generateConfig = generateConfig,
    .wrapCommand = wrapCommand,
    .validateToolchain = validateToolchain,
};

fn prepareInterception(
    allocator: std.mem.Allocator,
    _: std.fs.Dir,
    target: @import("../../root.zig").toolchain_cross.target.CrossTarget,
    toolchain: common.ToolchainContext,
) !interception_common.InterceptionEnv {
    var env = interception_common.InterceptionEnv.init(allocator);
    env.target = target;
    env.zig_path = try env.storeOwned(toolchain.zig_path);
    env.sysroot = if (toolchain.sysroot) |root| try env.storeOwned(root) else null;
    return env;
}

fn generateConfig(_: std.mem.Allocator, _: std.fs.Dir, _: *interception_common.InterceptionEnv) !void {
    return error.NotImplemented;
}

fn wrapCommand(_: std.mem.Allocator, _: []const []const u8, _: *interception_common.InterceptionEnv) ![]const []const u8 {
    return error.NotImplemented;
}

fn validateToolchain(_: common.ToolchainContext, _: @import("../../root.zig").toolchain_cross.target.CrossTarget) !void {
    return;
}
