const std = @import("std");
const core = @import("../root.zig");

pub const InterceptionEnv = struct {
    allocator: std.mem.Allocator,
    target: ?core.toolchain_cross.target.CrossTarget = null,
    zig_path: ?[]const u8 = null,
    rustc_path: ?[]const u8 = null,
    cargo_path: ?[]const u8 = null,
    sysroot: ?[]const u8 = null,
    wrapper_dir: ?[]const u8 = null,
    toolchain_file: ?[]const u8 = null,
    env_map: std.process.EnvMap,
    owned: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator) InterceptionEnv {
        return .{
            .allocator = allocator,
            .env_map = std.process.EnvMap.init(allocator),
            .owned = .empty,
        };
    }

    pub fn deinit(self: *InterceptionEnv) void {
        for (self.owned.items) |item| self.allocator.free(item);
        self.owned.deinit(self.allocator);
        self.env_map.deinit();
    }

    pub fn storeOwned(self: *InterceptionEnv, text: []const u8) ![]const u8 {
        const copy = try self.allocator.dupe(u8, text);
        try self.owned.append(self.allocator, copy);
        return copy;
    }

    pub fn setWrapperDir(self: *InterceptionEnv, dir: []const u8) !void {
        self.wrapper_dir = try self.storeOwned(dir);
    }

    pub fn setToolchainFile(self: *InterceptionEnv, path: []const u8) !void {
        self.toolchain_file = try self.storeOwned(path);
    }

    pub fn putEnv(self: *InterceptionEnv, key: []const u8, value: []const u8) !void {
        const key_copy = try self.storeOwned(key);
        const value_copy = try self.storeOwned(value);
        try self.env_map.put(key_copy, value_copy);
    }
};
