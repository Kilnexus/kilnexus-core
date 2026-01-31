const std = @import("std");
const core = @import("../root.zig");
const common = @import("../common.zig");
const paths_config = @import("../../paths/config.zig");

pub const DepResolve = struct {
    root: []const u8,
    include_dir: ?[]const u8,
    lib_dir: ?[]const u8,
    embed_dir: ?[]const u8,
};

pub fn ensureDepsDirs(cwd: std.fs.Dir) !void {
    const deps_dir = try paths_config.projectPath(std.heap.page_allocator, &[_][]const u8{"deps"});
    defer std.heap.page_allocator.free(deps_dir);
    cwd.makePath(deps_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    const gen_dir = try paths_config.projectPath(std.heap.page_allocator, &[_][]const u8{"gen"});
    defer std.heap.page_allocator.free(gen_dir);
    cwd.makePath(gen_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
}

pub fn ensureDependency(
    allocator: std.mem.Allocator,
    cwd: std.fs.Dir,
    stdout: anytype,
    dep: common.UseSpec,
    owned: *std.ArrayList([]const u8),
) !DepResolve {
    const dep_parent = try paths_config.projectPath(allocator, &[_][]const u8{ "deps", dep.name });
    try owned.append(allocator, dep_parent);
    const dep_root = try std.fs.path.join(allocator, &[_][]const u8{ dep_parent, dep.version });
    try owned.append(allocator, dep_root);

    if (!common.dirExists(cwd, dep_root)) {
        try cwd.makePath(dep_root);
        const archive_name = try std.fmt.allocPrint(allocator, "{s}.tar.gz", .{dep.version});
        try owned.append(allocator, archive_name);
        const archive_path = try std.fs.path.join(allocator, &[_][]const u8{ dep_parent, archive_name });
        try owned.append(allocator, archive_path);

        const url = try core.archive.buildRegistryUrl(allocator, dep.name, dep.version);
        defer allocator.free(url);
        try stdout.print(">> Fetching {s}:{s} from {s}\n", .{ dep.name, dep.version, url });
        try core.archive.downloadFile(allocator, url, archive_path);
        try core.archive.extractTarGz(allocator, archive_path, dep_root, 0);
        cwd.deleteFile(archive_path) catch {};
    }

    const include_dir = try resolveOptionalChild(allocator, cwd, dep_root, "include", owned);
    const lib_dir = try resolveOptionalChild(allocator, cwd, dep_root, "lib", owned);
    const embed_dir = blk: {
        if (try resolveOptionalChild(allocator, cwd, dep_root, "embed", owned)) |value| break :blk value;
        break :blk try resolveOptionalChild(allocator, cwd, dep_root, "assets", owned);
    };

    return .{
        .root = dep_root,
        .include_dir = include_dir,
        .lib_dir = lib_dir,
        .embed_dir = embed_dir,
    };
}

pub fn resolveOptionalChild(
    allocator: std.mem.Allocator,
    cwd: std.fs.Dir,
    root: []const u8,
    name: []const u8,
    owned: *std.ArrayList([]const u8),
) !?[]const u8 {
    const path = try std.fs.path.join(allocator, &[_][]const u8{ root, name });
    if (common.dirExists(cwd, path)) {
        try owned.append(allocator, path);
        return path;
    }
    allocator.free(path);
    return null;
}

pub fn extractStaticLibs(dep_dir: []const u8) ![]const []const u8 {
    return core.toolchain_static.extractStaticLibs(dep_dir);
}

pub fn freeStaticLibs(libs: []const []const u8) void {
    for (libs) |lib| std.heap.page_allocator.free(lib);
    std.heap.page_allocator.free(libs);
}
