const std = @import("std");
const builtin = @import("builtin");

const common = @import("common.zig");
const platform = @import("platform.zig");
const paths_config = @import("../../paths/config.zig");

pub fn zigRelPathForVersion(allocator: std.mem.Allocator, version: []const u8) ![]const u8 {
    const exe_name = if (builtin.target.os.tag == .windows) "zig.exe" else "zig";
    const folder = try zigFolderName(allocator, version);
    defer allocator.free(folder);
    return paths_config.projectPath(allocator, &[_][]const u8{
        "toolchains",
        "zig",
        version,
        folder,
        exe_name,
    });
}

pub fn zigLegacyRelPathForVersion(allocator: std.mem.Allocator, version: []const u8) ![]const u8 {
    const exe_name = if (builtin.target.os.tag == .windows) "zig.exe" else "zig";
    const folder = try zigFolderName(allocator, version);
    defer allocator.free(folder);
    return paths_config.legacyProjectPath(allocator, &[_][]const u8{
        "toolchains",
        "zig",
        version,
        folder,
        exe_name,
    });
}

pub fn zigGlobalPathForVersion(allocator: std.mem.Allocator, version: []const u8) ![]const u8 {
    const exe_name = if (builtin.target.os.tag == .windows) "zig.exe" else "zig";
    const folder = try zigFolderName(allocator, version);
    defer allocator.free(folder);
    return paths_config.globalPath(allocator, &[_][]const u8{
        "toolchains",
        "zig",
        version,
        folder,
        exe_name,
    });
}

pub fn zigInstallDirRelForVersion(allocator: std.mem.Allocator, version: []const u8) ![]const u8 {
    const folder = try zigFolderName(allocator, version);
    defer allocator.free(folder);
    return paths_config.projectPath(allocator, &[_][]const u8{
        "toolchains",
        "zig",
        version,
        folder,
    });
}

pub fn zigInstallDirGlobalForVersion(allocator: std.mem.Allocator, version: []const u8) ![]const u8 {
    const folder = try zigFolderName(allocator, version);
    defer allocator.free(folder);
    return paths_config.globalPath(allocator, &[_][]const u8{
        "toolchains",
        "zig",
        version,
        folder,
    });
}

pub fn rustcRelPathForVersion(allocator: std.mem.Allocator, version: []const u8) ![]const u8 {
    const exe_name = if (builtin.target.os.tag == .windows) "rustc.exe" else "rustc";
    const install_dir = try rustInstallDirRelForVersion(allocator, version);
    defer allocator.free(install_dir);
    return std.fs.path.join(allocator, &[_][]const u8{
        install_dir,
        "rustc",
        "bin",
        exe_name,
    });
}

pub fn rustcLegacyRelPathForVersion(allocator: std.mem.Allocator, version: []const u8) ![]const u8 {
    const exe_name = if (builtin.target.os.tag == .windows) "rustc.exe" else "rustc";
    const install_dir = try rustInstallDirLegacyForVersion(allocator, version);
    defer allocator.free(install_dir);
    return std.fs.path.join(allocator, &[_][]const u8{
        install_dir,
        "rustc",
        "bin",
        exe_name,
    });
}

pub fn rustcGlobalPathForVersion(allocator: std.mem.Allocator, version: []const u8) ![]const u8 {
    const exe_name = if (builtin.target.os.tag == .windows) "rustc.exe" else "rustc";
    const install_dir = try rustInstallDirGlobalForVersion(allocator, version);
    defer allocator.free(install_dir);
    return std.fs.path.join(allocator, &[_][]const u8{
        install_dir,
        "rustc",
        "bin",
        exe_name,
    });
}

pub fn cargoRelPathForVersion(allocator: std.mem.Allocator, version: []const u8) ![]const u8 {
    const exe_name = if (builtin.target.os.tag == .windows) "cargo.exe" else "cargo";
    const install_dir = try rustInstallDirRelForVersion(allocator, version);
    defer allocator.free(install_dir);
    return std.fs.path.join(allocator, &[_][]const u8{
        install_dir,
        "cargo",
        "bin",
        exe_name,
    });
}

pub fn cargoLegacyRelPathForVersion(allocator: std.mem.Allocator, version: []const u8) ![]const u8 {
    const exe_name = if (builtin.target.os.tag == .windows) "cargo.exe" else "cargo";
    const install_dir = try rustInstallDirLegacyForVersion(allocator, version);
    defer allocator.free(install_dir);
    return std.fs.path.join(allocator, &[_][]const u8{
        install_dir,
        "cargo",
        "bin",
        exe_name,
    });
}

pub fn cargoGlobalPathForVersion(allocator: std.mem.Allocator, version: []const u8) ![]const u8 {
    const exe_name = if (builtin.target.os.tag == .windows) "cargo.exe" else "cargo";
    const install_dir = try rustInstallDirGlobalForVersion(allocator, version);
    defer allocator.free(install_dir);
    return std.fs.path.join(allocator, &[_][]const u8{
        install_dir,
        "cargo",
        "bin",
        exe_name,
    });
}

pub fn rustInstallDirRelForVersion(allocator: std.mem.Allocator, version: []const u8) ![]const u8 {
    const folder = try rustFolderName(allocator, version);
    defer allocator.free(folder);
    return paths_config.projectPath(allocator, &[_][]const u8{
        "toolchains",
        "rust",
        version,
        folder,
    });
}

pub fn rustInstallDirLegacyForVersion(allocator: std.mem.Allocator, version: []const u8) ![]const u8 {
    const folder = try rustFolderName(allocator, version);
    defer allocator.free(folder);
    return paths_config.legacyProjectPath(allocator, &[_][]const u8{
        "toolchains",
        "rust",
        version,
        folder,
    });
}

pub fn rustInstallDirGlobalForVersion(allocator: std.mem.Allocator, version: []const u8) ![]const u8 {
    const folder = try rustFolderName(allocator, version);
    defer allocator.free(folder);
    return paths_config.globalPath(allocator, &[_][]const u8{
        "toolchains",
        "rust",
        version,
        folder,
    });
}

pub fn goRelPathForVersion(allocator: std.mem.Allocator, version: []const u8) ![]const u8 {
    const exe_name = if (builtin.target.os.tag == .windows) "go.exe" else "go";
    const install_dir = try goInstallDirRelForVersion(allocator, version);
    defer allocator.free(install_dir);
    return std.fs.path.join(allocator, &[_][]const u8{
        install_dir,
        "go",
        "bin",
        exe_name,
    });
}

pub fn goLegacyRelPathForVersion(allocator: std.mem.Allocator, version: []const u8) ![]const u8 {
    const exe_name = if (builtin.target.os.tag == .windows) "go.exe" else "go";
    const install_dir = try goInstallDirLegacyForVersion(allocator, version);
    defer allocator.free(install_dir);
    return std.fs.path.join(allocator, &[_][]const u8{
        install_dir,
        "go",
        "bin",
        exe_name,
    });
}

pub fn goGlobalPathForVersion(allocator: std.mem.Allocator, version: []const u8) ![]const u8 {
    const exe_name = if (builtin.target.os.tag == .windows) "go.exe" else "go";
    const install_dir = try goInstallDirGlobalForVersion(allocator, version);
    defer allocator.free(install_dir);
    return std.fs.path.join(allocator, &[_][]const u8{
        install_dir,
        "go",
        "bin",
        exe_name,
    });
}

pub fn goInstallDirRelForVersion(allocator: std.mem.Allocator, version: []const u8) ![]const u8 {
    return paths_config.projectPath(allocator, &[_][]const u8{
        "toolchains",
        "go",
        version,
    });
}

pub fn goInstallDirLegacyForVersion(allocator: std.mem.Allocator, version: []const u8) ![]const u8 {
    return paths_config.legacyProjectPath(allocator, &[_][]const u8{
        "toolchains",
        "go",
        version,
    });
}

pub fn goInstallDirGlobalForVersion(allocator: std.mem.Allocator, version: []const u8) ![]const u8 {
    return paths_config.globalPath(allocator, &[_][]const u8{
        "toolchains",
        "go",
        version,
    });
}

pub fn ensureToolchainDir(cwd: std.fs.Dir) !void {
    const path = try paths_config.projectPath(std.heap.page_allocator, &[_][]const u8{"toolchains"});
    defer std.heap.page_allocator.free(path);
    cwd.makePath(path) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
}

pub fn ensureToolchainDirFor(cwd: std.fs.Dir, tool: common.Toolchain) !void {
    const base = try paths_config.projectPath(
        std.heap.page_allocator,
        &[_][]const u8{ "toolchains", common.toolchainName(tool) },
    );
    defer std.heap.page_allocator.free(base);
    cwd.makePath(base) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
}

pub fn ensureProjectCache(cwd: std.fs.Dir) !void {
    const project_dir = try paths_config.projectPath(std.heap.page_allocator, &[_][]const u8{});
    defer std.heap.page_allocator.free(project_dir);
    cwd.makePath(project_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    const cache_dir = try paths_config.projectPath(std.heap.page_allocator, &[_][]const u8{"cache"});
    defer std.heap.page_allocator.free(cache_dir);
    cwd.makePath(cache_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
}

fn zigFolderName(allocator: std.mem.Allocator, version: []const u8) ![]const u8 {
    const os_part = platform.hostOsName();
    const arch_part = platform.hostArchName();
    if (std.mem.eql(u8, os_part, "unknown") or std.mem.eql(u8, arch_part, "unknown"))
        return error.UnsupportedPlatform;
    return std.fmt.allocPrint(allocator, "zig-{s}-{s}-{s}", .{ os_part, arch_part, version });
}

fn rustFolderName(allocator: std.mem.Allocator, version: []const u8) ![]const u8 {
    const triple = try platform.rustTargetTriple(allocator);
    defer allocator.free(triple);
    return std.fmt.allocPrint(allocator, "rust-{s}-{s}", .{ version, triple });
}
