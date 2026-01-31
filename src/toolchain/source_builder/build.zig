const std = @import("std");
const common = @import("common.zig");

pub fn buildZig(source_root: []const u8, bootstrap_path: ?[]const u8) !void {
    const allocator = std.heap.page_allocator;
    if (bootstrap_path) |path| {
        const args = &[_][]const u8{ path, "build", "-Doptimize=ReleaseFast" };
        try runCommand(allocator, source_root, args);
        return;
    }
    const zig = try common.envOrDefault(allocator, "KILNEXUS_ZIG_BOOTSTRAP", "zig");
    defer if (zig.owned) allocator.free(zig.value);
    const args = &[_][]const u8{ zig.value, "build", "-Doptimize=ReleaseFast" };
    try runCommand(allocator, source_root, args);
}

pub fn buildRust(source_root: []const u8) !void {
    const allocator = std.heap.page_allocator;
    const python = try common.envOrDefault(allocator, "KILNEXUS_RUST_PYTHON", "python");
    defer if (python.owned) allocator.free(python.value);
    const args = &[_][]const u8{ python.value, "x.py", "build", "--stage", "3" };
    try runCommand(allocator, source_root, args);
}

pub fn buildMusl(source_root: []const u8, install_dir: []const u8) !void {
    const allocator = std.heap.page_allocator;
    const configure = &[_][]const u8{ "./configure", "--prefix", install_dir };
    try runCommand(allocator, source_root, configure);
    const make_args = &[_][]const u8{"make"};
    try runCommand(allocator, source_root, make_args);
    const install_args = &[_][]const u8{ "make", "install" };
    try runCommand(allocator, source_root, install_args);
}

pub fn runCommand(allocator: std.mem.Allocator, cwd_path: []const u8, argv: []const []const u8) !void {
    var child = std.process.Child.init(argv, allocator);
    var cwd_dir = try std.fs.cwd().openDir(cwd_path, .{});
    defer cwd_dir.close();
    child.cwd_dir = cwd_dir;
    child.stdin_behavior = .Inherit;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;
    const term = try child.spawnAndWait();
    switch (term) {
        .Exited => |code| if (code != 0) return error.CompileFailed,
        else => return error.CompileFailed,
    }
}
