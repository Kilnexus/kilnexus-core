const std = @import("std");
const common = @import("common.zig");

/// Execute a command in the given working directory.
/// Side effects: spawns a child process and may modify the filesystem.
pub fn run(
    allocator: std.mem.Allocator,
    cwd: std.fs.Dir,
    argv: []const []const u8,
    env: common.VirtualEnv,
) !void {
    var executor = Executor.init(allocator, cwd);
    try executor.run(argv, env);
}

/// Execute a command with a prebuilt environment map.
/// Side effects: spawns a child process and may modify the filesystem.
pub fn runWithEnvMap(
    allocator: std.mem.Allocator,
    cwd: std.fs.Dir,
    argv: []const []const u8,
    env: common.VirtualEnv,
    env_map: *std.process.EnvMap,
) !void {
    var executor = Executor.init(allocator, cwd);
    try executor.runWithEnvMap(argv, env, env_map);
}

/// Execute a command without virtual root support.
pub fn runProcess(
    allocator: std.mem.Allocator,
    cwd: std.fs.Dir,
    argv: []const []const u8,
) !void {
    var executor = Executor.init(allocator, cwd);
    try executor.runProcess(argv);
}

pub fn runProcessWithEnv(
    allocator: std.mem.Allocator,
    cwd: std.fs.Dir,
    argv: []const []const u8,
    env_map: *std.process.EnvMap,
) !void {
    var executor = Executor.init(allocator, cwd);
    try executor.runProcessWithEnv(argv, env_map);
}

pub fn getEnvMap(allocator: std.mem.Allocator) !std.process.EnvMap {
    return std.process.EnvMap.init(allocator);
}

pub fn ensureSourceDateEpoch(env_map: *std.process.EnvMap) !void {
    if (env_map.get("SOURCE_DATE_EPOCH") == null) {
        try env_map.put("SOURCE_DATE_EPOCH", "0");
    }
}

pub const Executor = struct {
    allocator: std.mem.Allocator,
    cwd: std.fs.Dir,

    pub fn init(allocator: std.mem.Allocator, cwd: std.fs.Dir) Executor {
        return .{ .allocator = allocator, .cwd = cwd };
    }

    pub fn run(self: Executor, argv: []const []const u8, env: common.VirtualEnv) !void {
        if (env.virtual_root) |root| {
            return self.runInVirtualRoot(argv, root);
        }
        try self.runProcess(argv);
    }

    pub fn runWithEnvMap(self: Executor, argv: []const []const u8, env: common.VirtualEnv, env_map: *std.process.EnvMap) !void {
        if (env.virtual_root) |root| {
            return self.runInVirtualRootWithEnv(argv, root, env_map);
        }
        try self.runProcessWithEnv(argv, env_map);
    }

    pub fn runProcess(self: Executor, argv: []const []const u8) !void {
        var child = std.process.Child.init(argv, self.allocator);
        child.cwd_dir = self.cwd;
        child.stdin_behavior = .Inherit;
        child.stdout_behavior = .Inherit;
        child.stderr_behavior = .Inherit;

        const term = try child.spawnAndWait();
        switch (term) {
            .Exited => |code| {
                if (code != 0) return error.CompileFailed;
            },
            else => return error.CompileFailed,
        }
    }

    pub fn runProcessWithEnv(self: Executor, argv: []const []const u8, env_map: *std.process.EnvMap) !void {
        var child = std.process.Child.init(argv, self.allocator);
        child.cwd_dir = self.cwd;
        child.stdin_behavior = .Inherit;
        child.stdout_behavior = .Inherit;
        child.stderr_behavior = .Inherit;
        child.env_map = env_map;

        const term = try child.spawnAndWait();
        switch (term) {
            .Exited => |code| {
                if (code != 0) return error.CompileFailed;
            },
            else => return error.CompileFailed,
        }
    }

    pub fn getEnvMap(self: Executor) !std.process.EnvMap {
        return std.process.EnvMap.init(self.allocator);
    }

    fn runInVirtualRoot(self: Executor, argv: []const []const u8, root: []const u8) !void {
        const builtin = @import("builtin");
        if (builtin.os.tag != .linux) return error.VirtualRootUnsupported;

        var wrapper = std.ArrayList([]const u8).empty;
        defer wrapper.deinit(self.allocator);

        try wrapper.appendSlice(self.allocator, &[_][]const u8{
            "unshare",
            "--mount",
            "--map-root-user",
            "--uts",
            "--pid",
            "--fork",
            "--mount-proc",
            "--root",
            root,
            "--",
        });
        try wrapper.appendSlice(self.allocator, argv);
        try self.runProcess(wrapper.items);
    }

    fn runInVirtualRootWithEnv(self: Executor, argv: []const []const u8, root: []const u8, env_map: *std.process.EnvMap) !void {
        const builtin = @import("builtin");
        if (builtin.os.tag != .linux) return error.VirtualRootUnsupported;

        var wrapper = std.ArrayList([]const u8).empty;
        defer wrapper.deinit(self.allocator);

        try wrapper.appendSlice(self.allocator, &[_][]const u8{
            "unshare",
            "--mount",
            "--map-root-user",
            "--uts",
            "--pid",
            "--fork",
            "--mount-proc",
            "--root",
            root,
            "--",
        });
        try wrapper.appendSlice(self.allocator, argv);
        try self.runProcessWithEnv(wrapper.items, env_map);
    }
};
