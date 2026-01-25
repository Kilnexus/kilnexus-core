const std = @import("std");
const build = @import("build.zig");
const common = @import("common.zig");
const download = @import("download.zig");
const paths_config = @import("../../paths/config.zig");

pub const SeedSpec = struct {
    version: []const u8,
    sha256: ?[]const u8 = null,
    command: ?[]const u8 = null,
};

pub fn buildZigSeed(spec: SeedSpec) ![]const u8 {
    const allocator = std.heap.page_allocator;
    const source_root = try download.prepareSource(.Zig, spec.version, spec.sha256);
    defer allocator.free(source_root);

    const seed_root = try seedRootFor(spec.version);
    errdefer allocator.free(seed_root);
    const seed_zig = try seedZigPath(allocator, seed_root);
    errdefer allocator.free(seed_zig);
    if (common.fileExists(seed_zig)) return seed_zig;

    try common.ensureDir(seed_root);
    try runBootstrap(source_root, spec.command);

    const built_zig = try findSeedZig(allocator, source_root);
    defer allocator.free(built_zig);
    try installSeedZig(allocator, built_zig, seed_root);
    return seed_zig;
}

fn seedRootFor(version: []const u8) ![]const u8 {
    return paths_config.projectPath(std.heap.page_allocator, &[_][]const u8{
        "toolchains",
        "zig-seed",
        version,
    });
}

fn seedZigPath(allocator: std.mem.Allocator, seed_root: []const u8) ![]const u8 {
    const exe = try common.exeNameAlloc(allocator, "zig");
    defer if (exe.owned) allocator.free(exe.value);
    return std.fs.path.join(allocator, &[_][]const u8{ seed_root, "bin", exe.value });
}

fn runBootstrap(source_root: []const u8, command: ?[]const u8) !void {
    const allocator = std.heap.page_allocator;
    const cmd = try bootstrapCommand(allocator, source_root, command);
    defer allocator.free(cmd);
    const args = &[_][]const u8{ cmd };
    try build.runCommand(allocator, source_root, args);
}

fn bootstrapCommand(
    allocator: std.mem.Allocator,
    source_root: []const u8,
    command: ?[]const u8,
) ![]const u8 {
    if (command) |relative| {
        if (!isSafeRelativePath(relative)) return error.InvalidBootstrapSeedCommand;
        const path = try std.fs.path.join(allocator, &[_][]const u8{ source_root, relative });
        if (common.fileExists(path)) return path;
        allocator.free(path);
        return error.BootstrapSeedMissingScript;
    }

    const candidates = &[_][]const u8{
        "bootstrap",
        "bootstrap.sh",
        "bootstrap.bat",
    };
    for (candidates) |name| {
        const path = try std.fs.path.join(allocator, &[_][]const u8{ source_root, name });
        if (common.fileExists(path)) return path;
        allocator.free(path);
    }

    return error.BootstrapSeedMissingScript;
}

fn isSafeRelativePath(path: []const u8) bool {
    if (std.fs.path.isAbsolute(path)) return false;
    var it = std.mem.splitAny(u8, path, "/\\");
    while (it.next()) |part| {
        if (std.mem.eql(u8, part, "..")) return false;
    }
    return true;
}

fn findSeedZig(allocator: std.mem.Allocator, source_root: []const u8) ![]const u8 {
    const exe = try common.exeNameAlloc(allocator, "zig");
    defer if (exe.owned) allocator.free(exe.value);
    const stage1 = try common.exeNameAlloc(allocator, "zig-stage1");
    defer if (stage1.owned) allocator.free(stage1.value);
    const file_candidates = &[_][]const u8{
        "zig-out/bin",
    };
    for (file_candidates) |base| {
        const path = try std.fs.path.join(allocator, &[_][]const u8{ source_root, base, stage1.value });
        if (common.fileExists(path)) return path;
        allocator.free(path);
    }
    const dir_candidates = &[_][]const u8{
        "zig-out/bin",
        "zig-cache",
        "zig-cache/bin",
    };
    for (dir_candidates) |dir_name| {
        const path = try std.fs.path.join(allocator, &[_][]const u8{ source_root, dir_name, exe.value });
        if (common.fileExists(path)) return path;
        allocator.free(path);
    }
    return error.BootstrapSeedMissingBinary;
}

fn installSeedZig(allocator: std.mem.Allocator, src_path: []const u8, seed_root: []const u8) !void {
    const bin_dir = try std.fs.path.join(allocator, &[_][]const u8{ seed_root, "bin" });
    defer allocator.free(bin_dir);
    std.fs.cwd().makePath(bin_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    const exe = try common.exeNameAlloc(allocator, "zig");
    defer if (exe.owned) allocator.free(exe.value);
    const dst_path = try std.fs.path.join(allocator, &[_][]const u8{ bin_dir, exe.value });
    defer allocator.free(dst_path);
    try copyFilePath(src_path, dst_path);
}

fn copyFilePath(src_path: []const u8, dst_path: []const u8) !void {
    var src = try std.fs.cwd().openFile(src_path, .{});
    defer src.close();
    var dst = try std.fs.cwd().createFile(dst_path, .{ .truncate = true });
    defer dst.close();
    var buf: [32 * 1024]u8 = undefined;
    while (true) {
        const amt = try src.read(buf[0..]);
        if (amt == 0) break;
        try dst.writeAll(buf[0..amt]);
    }
}
