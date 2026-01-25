const std = @import("std");
const core = @import("../root.zig");
const paths_config = @import("../paths/config.zig");

pub const UseSpec = struct {
    name: []const u8,
    version: []const u8,
    alias: ?[]const u8,
    strategy: core.protocol.UseDependency.Strategy,
};

pub const BootstrapVersions = struct {
    zig: ?[]const u8 = null,
    rust: ?[]const u8 = null,
    go: ?[]const u8 = null,
};

pub const BootstrapSourceSpec = struct {
    version: []const u8,
    sha256: ?[]const u8 = null,
};

pub const BootstrapSeedSpec = struct {
    version: []const u8,
    sha256: ?[]const u8 = null,
    command: ?[]const u8 = null,
};

pub const BootstrapSourceVersions = struct {
    zig: ?BootstrapSourceSpec = null,
    rust: ?BootstrapSourceSpec = null,
    musl: ?BootstrapSourceSpec = null,
};

pub fn exists(dir: std.fs.Dir, filename: []const u8) bool {
    dir.access(filename, .{}) catch return false;
    return true;
}

pub fn dirExists(cwd: std.fs.Dir, path: []const u8) bool {
    var dir = cwd.openDir(path, .{}) catch return false;
    dir.close();
    return true;
}

pub fn copyFile(cwd: std.fs.Dir, src_path: []const u8, dst_path: []const u8) !void {
    var src = try cwd.openFile(src_path, .{});
    defer src.close();
    var dst = try cwd.createFile(dst_path, .{ .truncate = true });
    defer dst.close();
    var buf: [32 * 1024]u8 = undefined;
    while (true) {
        const amt = try src.read(buf[0..]);
        if (amt == 0) break;
        try dst.writeAll(buf[0..amt]);
    }
}

pub fn ensureReproDir(cwd: std.fs.Dir) !void {
    const repro_dir = try paths_config.projectPath(std.heap.page_allocator, &[_][]const u8{ "repro" });
    defer std.heap.page_allocator.free(repro_dir);
    cwd.makePath(repro_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
}

pub fn containsCargoManifest(cwd: std.fs.Dir, path: []const u8) !bool {
    var dir = cwd.openDir(path, .{}) catch return false;
    defer dir.close();
    dir.access("Cargo.toml", .{}) catch return false;
    return true;
}

pub fn resolveCargoManifestPath(allocator: std.mem.Allocator, cwd: std.fs.Dir, path: []const u8) ![]const u8 {
    if (std.mem.endsWith(u8, path, "Cargo.toml")) return allocator.dupe(u8, path);
    var dir = cwd.openDir(path, .{}) catch return error.MissingCargoManifest;
    defer dir.close();
    dir.access("Cargo.toml", .{}) catch return error.MissingCargoManifest;
    return try std.fs.path.join(allocator, &[_][]const u8{ path, "Cargo.toml" });
}

pub fn getRemapPrefix(allocator: std.mem.Allocator, cwd: std.fs.Dir) !?[]const u8 {
    return cwd.realpathAlloc(allocator, ".") catch null;
}
