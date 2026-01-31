const std = @import("std");
const protocol_types = @import("../../../protocol/types.zig");

pub const Level = protocol_types.IsolationLevel;

pub const IsolatedEnv = struct {
    allocator: std.mem.Allocator,
    env_map: std.process.EnvMap,
    isolation_level: Level,
    owned: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator, level: Level) !IsolatedEnv {
        var env = IsolatedEnv{
            .allocator = allocator,
            .env_map = std.process.EnvMap.init(allocator),
            .isolation_level = level,
            .owned = .empty,
        };
        try env.applyLevel();
        return env;
    }

    pub fn addToolchain(self: *IsolatedEnv, path: []const u8) !void {
        const existing = self.env_map.get("PATH");
        if (existing) |value| {
            const merged = try std.fmt.allocPrint(self.allocator, "{s}{c}{s}", .{ value, std.fs.path.delimiter, path });
            defer self.allocator.free(merged);
            try self.putOwned("PATH", merged);
            return;
        }
        try self.putOwned("PATH", path);
    }

    pub fn addCustom(self: *IsolatedEnv, key: []const u8, value: []const u8) !void {
        try self.putOwned(key, value);
    }

    pub fn toEnvMap(self: *IsolatedEnv) *std.process.EnvMap {
        return &self.env_map;
    }

    pub fn deinit(self: *IsolatedEnv) void {
        for (self.owned.items) |item| self.allocator.free(item);
        self.owned.deinit(self.allocator);
        self.env_map.deinit();
    }

    fn applyLevel(self: *IsolatedEnv) !void {
        switch (self.isolation_level) {
            .None => {},
            .Minimal => try self.applyMinimal(),
            .Full => try self.applyFull(),
        }
    }

    fn applyMinimal(self: *IsolatedEnv) !void {
        if (try getEnvVarOwnedMaybe(self.allocator, "PATH")) |path| {
            defer self.allocator.free(path);
            try self.putOwned("PATH", path);
        }
        try self.putOwned("SOURCE_DATE_EPOCH", "0");
        try self.putOwned("TZ", "UTC");
        try self.putOwned("LC_ALL", "C");
        try self.putOwned("LANG", "C");
    }

    fn applyFull(self: *IsolatedEnv) !void {
        try self.putOwned("HOME", "/nonexistent");
        try self.putOwned("SOURCE_DATE_EPOCH", "0");
        try self.putOwned("TZ", "UTC");
        try self.putOwned("LC_ALL", "C");
        try self.putOwned("LANG", "C");
        try self.putOwned("TERM", "dumb");
    }

    fn putOwned(self: *IsolatedEnv, key: []const u8, value: []const u8) !void {
        const key_copy = try self.allocator.dupe(u8, key);
        const value_copy = try self.allocator.dupe(u8, value);
        try self.owned.append(self.allocator, key_copy);
        try self.owned.append(self.allocator, value_copy);
        try self.env_map.put(key_copy, value_copy);
    }
};

fn getEnvVarOwnedMaybe(allocator: std.mem.Allocator, key: []const u8) !?[]const u8 {
    const value = std.process.getEnvVarOwned(allocator, key) catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return null,
        else => return err,
    };
    return value;
}
