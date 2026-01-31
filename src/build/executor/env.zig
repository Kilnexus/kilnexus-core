const std = @import("std");
const core = @import("../../root.zig");
const deterministic_env = @import("deterministic/env_isolate.zig");

pub const EnvHolder = struct {
    env_map: ?std.process.EnvMap = null,
    isolated: ?deterministic_env.IsolatedEnv = null,

    pub fn envMap(self: *EnvHolder) *std.process.EnvMap {
        if (self.isolated) |*isolated| return isolated.toEnvMap();
        return &self.env_map.?;
    }

    pub fn deinit(self: *EnvHolder) void {
        if (self.isolated) |*isolated| isolated.deinit();
        if (self.env_map) |*map| map.deinit();
    }
};

pub fn initEnvHolder(
    allocator: std.mem.Allocator,
    isolation_level: ?core.protocol_types.IsolationLevel,
    toolchain_paths: []const []const u8,
) !EnvHolder {
    if (isolation_level) |level| {
        if (level == .None) {
            return .{ .env_map = try core.toolchain_executor.getEnvMap(allocator) };
        }
        var isolated = try deterministic_env.IsolatedEnv.init(allocator, level);
        for (toolchain_paths) |path| {
            const dir = std.fs.path.dirname(path) orelse path;
            try isolated.addToolchain(dir);
        }
        return .{ .isolated = isolated };
    }
    return .{ .env_map = try core.toolchain_executor.getEnvMap(allocator) };
}
