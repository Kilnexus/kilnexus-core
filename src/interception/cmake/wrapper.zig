const std = @import("std");
const flags = @import("flags.zig");

pub fn wrap(allocator: std.mem.Allocator, argv: []const []const u8, toolchain_path: []const u8) ![]const []const u8 {
    if (argv.len == 0) return error.EmptyCommand;
    if (flags.hasToolchainFlag(argv)) {
        return try dupArgv(allocator, argv);
    }

    const toolchain_flag = try flags.toolchainFlag(allocator, toolchain_path);
    errdefer allocator.free(toolchain_flag);

    var out = try allocator.alloc([]const u8, argv.len + 1);
    out[0] = argv[0];
    out[1] = toolchain_flag;
    if (argv.len > 1) {
        std.mem.copyForwards([]const u8, out[2..], argv[1..]);
    }
    return out;
}

fn dupArgv(allocator: std.mem.Allocator, argv: []const []const u8) ![]const []const u8 {
    var out = try allocator.alloc([]const u8, argv.len);
    std.mem.copyForwards([]const u8, out, argv);
    return out;
}
