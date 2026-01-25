const std = @import("std");
const manager = @import("manager.zig");

pub fn buildZigFromSource(version: []const u8) !void {
    const source_root = try sourceRootFor(.Zig, version);
    defer std.heap.page_allocator.free(source_root);
    const build_dir = try buildDirFor(.Zig, source_root, "zig-out");
    defer std.heap.page_allocator.free(build_dir);
    const install_dir = try manager.zigInstallDirRelForVersion(std.heap.page_allocator, version);
    defer std.heap.page_allocator.free(install_dir);
    try installFromBuild(build_dir, install_dir);
}

pub fn buildRustFromSource(version: []const u8) !void {
    const source_root = try sourceRootFor(.Rust, version);
    defer std.heap.page_allocator.free(source_root);
    const build_dir = try buildDirFor(.Rust, source_root, "build");
    defer std.heap.page_allocator.free(build_dir);
    const install_dir = try manager.rustInstallDirRelForVersion(std.heap.page_allocator, version);
    defer std.heap.page_allocator.free(install_dir);
    try installRustFromBuild(build_dir, install_dir);
}

pub fn buildMuslFromSource(version: []const u8) !void {
    const source_root = try sourceRootFor(.Musl, version);
    defer std.heap.page_allocator.free(source_root);
    const build_dir = try buildDirFor(.Musl, source_root, "install");
    defer std.heap.page_allocator.free(build_dir);
    const install_dir = try muslInstallDirRel(version);
    defer std.heap.page_allocator.free(install_dir);
    try installFromBuild(build_dir, install_dir);
}

const SourceTool = enum {
    Zig,
    Rust,
    Musl,
};

fn sourceRootFor(tool: SourceTool, version: []const u8) ![]const u8 {
    const env_key = switch (tool) {
        .Zig => "KILNEXUS_ZIG_SOURCE_DIR",
        .Rust => "KILNEXUS_RUST_SOURCE_DIR",
        .Musl => "KILNEXUS_MUSL_SOURCE_DIR",
    };
    if (std.process.getEnvVarOwned(std.heap.page_allocator, env_key)) |value| {
        return value;
    } else |_| {}
    return std.fs.path.join(std.heap.page_allocator, &[_][]const u8{
        ".knx",
        "sources",
        toolName(tool),
        version,
    });
}

fn buildDirFor(tool: SourceTool, source_root: []const u8, fallback: []const u8) ![]const u8 {
    const env_key = switch (tool) {
        .Zig => "KILNEXUS_ZIG_BUILD_DIR",
        .Rust => "KILNEXUS_RUST_BUILD_DIR",
        .Musl => "KILNEXUS_MUSL_BUILD_DIR",
    };
    if (std.process.getEnvVarOwned(std.heap.page_allocator, env_key)) |value| {
        return value;
    } else |_| {}
    return std.fs.path.join(std.heap.page_allocator, &[_][]const u8{ source_root, fallback });
}

fn toolName(tool: SourceTool) []const u8 {
    return switch (tool) {
        .Zig => "zig",
        .Rust => "rust",
        .Musl => "musl",
    };
}

fn muslInstallDirRel(version: []const u8) ![]const u8 {
    return std.fs.path.join(std.heap.page_allocator, &[_][]const u8{
        ".knx",
        "toolchains",
        "musl",
        version,
    });
}

fn installFromBuild(build_dir: []const u8, install_dir: []const u8) !void {
    ensureDir(install_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    var src = try std.fs.cwd().openDir(build_dir, .{ .iterate = true });
    defer src.close();
    var dst = try std.fs.cwd().openDir(install_dir, .{ .iterate = true });
    defer dst.close();
    try copyTree(std.heap.page_allocator, src, dst);
}

fn installRustFromBuild(build_dir: []const u8, install_dir: []const u8) !void {
    ensureDir(install_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    var dst = try std.fs.cwd().openDir(install_dir, .{ .iterate = true });
    defer dst.close();
    try copySubdir(std.heap.page_allocator, build_dir, "rustc", dst);
    try copySubdir(std.heap.page_allocator, build_dir, "cargo", dst);
}

fn copySubdir(allocator: std.mem.Allocator, root: []const u8, name: []const u8, dst: std.fs.Dir) !void {
    const path = try std.fs.path.join(allocator, &[_][]const u8{ root, name });
    defer allocator.free(path);
    var src = std.fs.cwd().openDir(path, .{ .iterate = true }) catch return error.SourceBuildMissing;
    defer src.close();
    try dst.makePath(name);
    var dst_sub = try dst.openDir(name, .{ .iterate = true });
    defer dst_sub.close();
    try copyTree(allocator, src, dst_sub);
}

fn copyTree(allocator: std.mem.Allocator, src: std.fs.Dir, dst: std.fs.Dir) !void {
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

fn copyFile(src: std.fs.Dir, dst: std.fs.Dir, rel_path: []const u8) !void {
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

fn ensureDir(path: []const u8) !void {
    std.fs.cwd().makePath(path);
}
