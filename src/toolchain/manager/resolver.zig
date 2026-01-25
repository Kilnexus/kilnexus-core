const std = @import("std");

const paths = @import("paths.zig");

pub fn resolveZigPathForVersion(allocator: std.mem.Allocator, cwd: std.fs.Dir, version: []const u8) ![]const u8 {
    return resolveToolPathForVersion(allocator, cwd, paths.zigRelPathForVersion, paths.zigGlobalPathForVersion, version);
}

pub fn resolveRustcPathForVersion(allocator: std.mem.Allocator, cwd: std.fs.Dir, version: []const u8) ![]const u8 {
    return resolveToolPathForVersion(allocator, cwd, paths.rustcRelPathForVersion, paths.rustcGlobalPathForVersion, version);
}

pub fn resolveCargoPathForVersion(allocator: std.mem.Allocator, cwd: std.fs.Dir, version: []const u8) ![]const u8 {
    return resolveToolPathForVersion(allocator, cwd, paths.cargoRelPathForVersion, paths.cargoGlobalPathForVersion, version);
}

pub fn resolveGoPathForVersion(allocator: std.mem.Allocator, cwd: std.fs.Dir, version: []const u8) ![]const u8 {
    return resolveToolPathForVersion(allocator, cwd, paths.goRelPathForVersion, paths.goGlobalPathForVersion, version);
}

fn resolveToolPathForVersion(
    allocator: std.mem.Allocator,
    cwd: std.fs.Dir,
    comptime rel_fn: fn (std.mem.Allocator, []const u8) anyerror![]const u8,
    comptime global_fn: fn (std.mem.Allocator, []const u8) anyerror![]const u8,
    version: []const u8,
) ![]const u8 {
    const rel = try rel_fn(allocator, version);

    if (cwd.access(rel, .{})) |_| {
        return rel;
    } else |_| {
        allocator.free(rel);
    }

    const global = try global_fn(allocator, version);
    errdefer allocator.free(global);
    std.fs.cwd().access(global, .{}) catch return error.ToolchainMissing;
    return global;
}
