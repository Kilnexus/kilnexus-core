const std = @import("std");
const builtin = @import("builtin");
const common = @import("common.zig");

pub const WrapperSpec = struct {
    name: []const u8,
    target_path: []const u8,
    extra_args: []const []const u8 = &[_][]const u8{},
};

pub fn generate(env: *common.InterceptionEnv) !void {
    const dir = env.wrapper_dir orelse return;
    var cwd = std.fs.cwd();
    try cwd.makePath(dir);

    if (env.toolchain_file) |toolchain_path| {
        const arg = try std.fmt.allocPrint(env.allocator, "-DCMAKE_TOOLCHAIN_FILE={s}", .{toolchain_path});
        defer env.allocator.free(arg);
        try generateWrapper(env, cwd, dir, .{
            .name = "cmake",
            .target_path = "cmake",
            .extra_args = &[_][]const u8{arg},
        });
    }
}

pub fn generateWrapper(
    env: *common.InterceptionEnv,
    cwd: std.fs.Dir,
    dir: []const u8,
    spec: WrapperSpec,
) ![]const u8 {
    const resolved_target = try resolveExecutable(env, spec.target_path);
    defer env.allocator.free(resolved_target);
    const path = try wrapperPath(env.allocator, dir, spec.name);
    errdefer env.allocator.free(path);

    var file = try cwd.createFile(path, .{ .truncate = true });
    defer file.close();
    var buf: [16 * 1024]u8 = undefined;
    var writer = file.writer(&buf);

    const extra = try formatArgs(env.allocator, spec.extra_args, builtin.target.os.tag == .windows);
    defer env.allocator.free(extra);
    if (builtin.target.os.tag == .windows) {
        try writer.interface.writeAll("@echo off\n");
        try writer.interface.print("\"{s}\"{s} %*\n", .{ resolved_target, extra });
        try writer.interface.writeAll("exit /b %errorlevel%\n");
    } else {
        try writer.interface.writeAll("#!/bin/sh\n");
        try writer.interface.print("exec \"{s}\"{s} \"$@\"\n", .{ resolved_target, extra });
    }
    try writer.interface.flush();

    if (builtin.target.os.tag != .windows) {
        try file.setPermissions(.{ .mode = 0o755 });
    }

    return path;
}

fn resolveExecutable(env: *common.InterceptionEnv, name: []const u8) ![]const u8 {
    if (std.fs.path.isAbsolute(name) or std.mem.indexOfScalar(u8, name, std.fs.path.sep) != null) {
        return env.allocator.dupe(u8, name);
    }

    const path_var = env.env_map.get("PATH") orelse return env.allocator.dupe(u8, name);
    var it = std.mem.splitScalar(u8, path_var, std.fs.path.delimiter);
    while (it.next()) |dir| {
        if (dir.len == 0) continue;
        if (try findExecutableInDir(env.allocator, dir, name)) |found| return found;
    }
    return env.allocator.dupe(u8, name);
}

fn findExecutableInDir(allocator: std.mem.Allocator, dir: []const u8, name: []const u8) !?[]const u8 {
    const base = try std.fs.path.join(allocator, &[_][]const u8{ dir, name });
    defer allocator.free(base);
    if (existsPath(base)) return allocator.dupe(u8, base);

    if (builtin.target.os.tag == .windows and std.fs.path.extension(name).len == 0) {
        const exts = &[_][]const u8{ ".exe", ".cmd", ".bat" };
        for (exts) |ext| {
            const candidate = try std.fmt.allocPrint(allocator, "{s}{s}", .{ base, ext });
            defer allocator.free(candidate);
            if (existsPath(candidate)) return allocator.dupe(u8, candidate);
        }
    }
    return null;
}

fn existsPath(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

fn wrapperPath(allocator: std.mem.Allocator, dir: []const u8, name: []const u8) ![]const u8 {
    if (builtin.target.os.tag == .windows) {
        const filename = try std.fmt.allocPrint(allocator, "{s}.cmd", .{name});
        defer allocator.free(filename);
        return std.fs.path.join(allocator, &[_][]const u8{ dir, filename });
    }
    return std.fs.path.join(allocator, &[_][]const u8{ dir, name });
}

fn formatArgs(allocator: std.mem.Allocator, args: []const []const u8, is_windows: bool) ![]const u8 {
    if (args.len == 0) return allocator.dupe(u8, "");
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    for (args, 0..) |arg, idx| {
        if (idx != 0) try out.append(allocator, ' ');
        const quoted = try quoteArg(allocator, arg, is_windows);
        defer allocator.free(quoted);
        try out.appendSlice(allocator, quoted);
    }
    return out.toOwnedSlice(allocator);
}

fn quoteArg(allocator: std.mem.Allocator, arg: []const u8, is_windows: bool) ![]const u8 {
    if (!needsQuoting(arg)) return allocator.dupe(u8, arg);
    if (is_windows) {
        var out = std.ArrayList(u8).empty;
        defer out.deinit(allocator);
        try out.append(allocator, '"');
        for (arg) |ch| {
            if (ch == '"') {
                try out.append(allocator, '\\');
            }
            try out.append(allocator, ch);
        }
        try out.append(allocator, '"');
        return out.toOwnedSlice(allocator);
    }
    return std.fmt.allocPrint(allocator, "\"{s}\"", .{arg});
}

fn needsQuoting(arg: []const u8) bool {
    for (arg) |ch| {
        if (ch == ' ' or ch == '\t' or ch == '"') return true;
    }
    return false;
}
