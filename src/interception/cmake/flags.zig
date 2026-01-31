const std = @import("std");

pub fn toolchainFlag(allocator: std.mem.Allocator, toolchain_path: []const u8) ![]const u8 {
    const normalized = try normalizePathAlloc(allocator, toolchain_path);
    defer allocator.free(normalized);
    return std.fmt.allocPrint(allocator, "-DCMAKE_TOOLCHAIN_FILE={s}", .{normalized});
}

pub fn hasToolchainFlag(args: []const []const u8) bool {
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.startsWith(u8, arg, "-DCMAKE_TOOLCHAIN_FILE=")) return true;
        if (std.mem.eql(u8, arg, "-DCMAKE_TOOLCHAIN_FILE")) {
            return i + 1 < args.len;
        }
    }
    return false;
}

fn normalizePathAlloc(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    const out = try allocator.dupe(u8, path);
    std.mem.replaceScalar(u8, out, '\\', '/');
    return out;
}
