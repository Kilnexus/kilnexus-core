const std = @import("std");

const paths = @import("paths.zig");
const paths_resolver = @import("../../paths/resolver.zig");

pub fn resolveZigPathForVersion(allocator: std.mem.Allocator, cwd: std.fs.Dir, version: []const u8) ![]const u8 {
    return resolveToolPathForVersion(
        allocator,
        cwd,
        paths.zigRelPathForVersion,
        paths.zigLegacyRelPathForVersion,
        paths.zigGlobalPathForVersion,
        version,
    );
}

pub fn resolveRustcPathForVersion(allocator: std.mem.Allocator, cwd: std.fs.Dir, version: []const u8) ![]const u8 {
    return resolveToolPathForVersion(
        allocator,
        cwd,
        paths.rustcRelPathForVersion,
        paths.rustcLegacyRelPathForVersion,
        paths.rustcGlobalPathForVersion,
        version,
    );
}

pub fn resolveCargoPathForVersion(allocator: std.mem.Allocator, cwd: std.fs.Dir, version: []const u8) ![]const u8 {
    return resolveToolPathForVersion(
        allocator,
        cwd,
        paths.cargoRelPathForVersion,
        paths.cargoLegacyRelPathForVersion,
        paths.cargoGlobalPathForVersion,
        version,
    );
}

pub fn resolveGoPathForVersion(allocator: std.mem.Allocator, cwd: std.fs.Dir, version: []const u8) ![]const u8 {
    return resolveToolPathForVersion(
        allocator,
        cwd,
        paths.goRelPathForVersion,
        paths.goLegacyRelPathForVersion,
        paths.goGlobalPathForVersion,
        version,
    );
}

fn resolveToolPathForVersion(
    allocator: std.mem.Allocator,
    cwd: std.fs.Dir,
    comptime rel_fn: fn (std.mem.Allocator, []const u8) anyerror![]const u8,
    comptime legacy_fn: fn (std.mem.Allocator, []const u8) anyerror![]const u8,
    comptime global_fn: fn (std.mem.Allocator, []const u8) anyerror![]const u8,
    version: []const u8,
) ![]const u8 {
    const order = try paths_resolver.toolchainSearchOrder(allocator);
    defer allocator.free(order);

    for (order) |location| {
        switch (location) {
            .Project => {
                const rel = try rel_fn(allocator, version);
                if (cwd.access(rel, .{})) |_| {
                    return rel;
                } else |_| {
                    allocator.free(rel);
                }
                const legacy = try legacy_fn(allocator, version);
                if (cwd.access(legacy, .{})) |_| {
                    return legacy;
                } else |_| {
                    allocator.free(legacy);
                }
            },
            .Global => {
                const global = try global_fn(allocator, version);
                errdefer allocator.free(global);
                std.fs.cwd().access(global, .{}) catch {
                    allocator.free(global);
                    continue;
                };
                return global;
            },
        }
    }

    return error.ToolchainMissing;
}
