const std = @import("std");
const config = @import("config.zig");

pub fn warnLegacyProjectDir(cwd: std.fs.Dir, stdout: anytype) !void {
    if (!legacyDirExists(cwd)) return;
    if (projectDirExists(cwd)) return;
    const project_dir = try config.projectPath(std.heap.page_allocator, &[_][]const u8{});
    defer std.heap.page_allocator.free(project_dir);
    try stdout.print(">> Found legacy {s} directory; new data will be written to {s}.\n", .{
        config.legacy_project_dir,
        project_dir,
    });
    const auto_migrate = try config.envBoolOrDefault(std.heap.page_allocator, "KNX_AUTO_MIGRATE", true);
    if (!auto_migrate) return;
    cwd.makePath(project_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
}

fn projectDirExists(cwd: std.fs.Dir) bool {
    const path = config.projectPath(std.heap.page_allocator, &[_][]const u8{}) catch return false;
    defer std.heap.page_allocator.free(path);
    var dir = cwd.openDir(path, .{}) catch return false;
    dir.close();
    return true;
}

fn legacyDirExists(cwd: std.fs.Dir) bool {
    var dir = cwd.openDir(config.legacy_project_dir, .{}) catch return false;
    dir.close();
    return true;
}
