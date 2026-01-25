const std = @import("std");

pub const default_registry = "https://registry.kilnexus.org";

pub fn registryBase(allocator: std.mem.Allocator) ![]const u8 {
    return std.process.getEnvVarOwned(allocator, "KILNEXUS_REGISTRY_URL") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => allocator.dupe(u8, default_registry),
        else => err,
    };
}

pub fn buildRegistryUrl(allocator: std.mem.Allocator, name: []const u8, version: []const u8) ![]const u8 {
    const base = try registryBase(allocator);
    defer allocator.free(base);
    return std.fmt.allocPrint(allocator, "{s}/{s}/{s}.tar.gz", .{ base, name, version });
}
