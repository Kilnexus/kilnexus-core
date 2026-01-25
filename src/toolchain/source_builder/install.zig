const std = @import("std");
const common = @import("common.zig");
const verify = @import("verify.zig");

pub fn installFromBuild(build_dir: []const u8, install_dir: []const u8) !void {
    common.ensureDir(install_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    var src = try std.fs.cwd().openDir(build_dir, .{ .iterate = true });
    defer src.close();
    var dst = try std.fs.cwd().openDir(install_dir, .{ .iterate = true });
    defer dst.close();
    try copyTree(std.heap.page_allocator, src, dst);
}

pub fn installRustFromStage(build_dir: []const u8, install_dir: []const u8) !void {
    common.ensureDir(install_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    var dst = try std.fs.cwd().openDir(install_dir, .{ .iterate = true });
    defer dst.close();
    const stage2_bin = try verify.findStageBinDir(std.heap.page_allocator, build_dir, "stage2");
    defer std.heap.page_allocator.free(stage2_bin);
    try copyStageTools(stage2_bin, dst);
}

pub fn copyStageTools(stage_bin: []const u8, dst: std.fs.Dir) !void {
    var src = std.fs.cwd().openDir(stage_bin, .{ .iterate = true }) catch return error.SourceBuildMissing;
    defer src.close();

    try dst.makePath("rustc/bin");
    try dst.makePath("cargo/bin");
    var rustc_dir = try dst.openDir("rustc/bin", .{ .iterate = true });
    defer rustc_dir.close();
    var cargo_dir = try dst.openDir("cargo/bin", .{ .iterate = true });
    defer cargo_dir.close();

    try copyIfExists(src, rustc_dir, "rustc");
    try copyIfExists(src, rustc_dir, "rustdoc");
    try copyIfExists(src, cargo_dir, "cargo");
}

pub fn copyTree(allocator: std.mem.Allocator, src: std.fs.Dir, dst: std.fs.Dir) !void {
    var walker = try src.walk(allocator);
    defer walker.deinit();
    while (try walker.next()) |entry| {
        switch (entry.kind) {
            .directory => try dst.makePath(entry.path),
            .file => try copyFile(src, dst, entry.path),
            else => {},
        }
    }
}

pub fn copyFile(src: std.fs.Dir, dst: std.fs.Dir, rel_path: []const u8) !void {
    var in_file = try src.openFile(rel_path, .{});
    defer in_file.close();
    if (std.fs.path.dirname(rel_path)) |dir_name| {
        try dst.makePath(dir_name);
    }
    var out_file = try dst.createFile(rel_path, .{ .truncate = true });
    defer out_file.close();

    var buf: [32 * 1024]u8 = undefined;
    while (true) {
        const amt = try in_file.read(buf[0..]);
        if (amt == 0) break;
        try out_file.writeAll(buf[0..amt]);
    }
}

fn copyIfExists(src: std.fs.Dir, dst: std.fs.Dir, name: []const u8) !void {
    const allocator = std.heap.page_allocator;
    const file_name = try common.exeNameAlloc(allocator, name);
    defer if (file_name.owned) allocator.free(file_name.value);
    src.access(file_name.value, .{}) catch return;
    try copyFile(src, dst, file_name.value);
}
