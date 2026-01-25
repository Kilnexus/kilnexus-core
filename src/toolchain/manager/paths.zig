const std = @import("std");
const builtin = @import("builtin");

const common = @import("common.zig");
const platform = @import("platform.zig");

pub fn zigRelPathForVersion(allocator: std.mem.Allocator, version: []const u8) ![]const u8 {
    const exe_name = if (builtin.target.os.tag == .windows) "zig.exe" else "zig";
    const folder = try zigFolderName(allocator, version);
    defer allocator.free(folder);
    return std.fs.path.join(allocator, &[_][]const u8{
        ".knx",
        "toolchains",
        "zig",
        version,
        folder,
        exe_name,
    });
}

pub fn zigGlobalPathForVersion(allocator: std.mem.Allocator, version: []const u8) ![]const u8 {
    const exe_name = if (builtin.target.os.tag == .windows) "zig.exe" else "zig";
    const home = try homeDir(allocator);
    defer allocator.free(home);
    const folder = try zigFolderName(allocator, version);
    defer allocator.free(folder);
    return std.fs.path.join(allocator, &[_][]const u8{
        home,
        ".knx",
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
    return std.fs.path.join(allocator, &[_][]const u8{
        ".knx",
        "toolchains",
        "zig",
        version,
        folder,
    });
}

pub fn zigInstallDirGlobalForVersion(allocator: std.mem.Allocator, version: []const u8) ![]const u8 {
    const home = try homeDir(allocator);
    defer allocator.free(home);
    const folder = try zigFolderName(allocator, version);
    defer allocator.free(folder);
    return std.fs.path.join(allocator, &[_][]const u8{
        home,
        ".knx",
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
    return std.fs.path.join(allocator, &[_][]const u8{
        ".knx",
        "toolchains",
        "rust",
        version,
        folder,
    });
}

pub fn rustInstallDirGlobalForVersion(allocator: std.mem.Allocator, version: []const u8) ![]const u8 {
    const home = try homeDir(allocator);
    defer allocator.free(home);
    const folder = try rustFolderName(allocator, version);
    defer allocator.free(folder);
    return std.fs.path.join(allocator, &[_][]const u8{
        home,
        ".knx",
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
    return std.fs.path.join(allocator, &[_][]const u8{
        ".knx",
        "toolchains",
        "go",
        version,
    });
}

pub fn goInstallDirGlobalForVersion(allocator: std.mem.Allocator, version: []const u8) ![]const u8 {
    const home = try homeDir(allocator);
    defer allocator.free(home);
    return std.fs.path.join(allocator, &[_][]const u8{
        home,
        ".knx",
        "toolchains",
        "go",
        version,
    });
}

pub fn ensureToolchainDir(cwd: std.fs.Dir) !void {
    cwd.makePath(".kilnexus/toolchains") catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
}

pub fn ensureToolchainDirFor(cwd: std.fs.Dir, tool: common.Toolchain) !void {
    const base = try std.fmt.allocPrint(std.heap.page_allocator, ".kilnexus/toolchains/{s}", .{common.toolchainName(tool)});
    defer std.heap.page_allocator.free(base);
    cwd.makePath(base) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
}

pub fn ensureProjectCache(cwd: std.fs.Dir) !void {
    cwd.makePath(".knx") catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    cwd.makePath(".kilnexus/cache") catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
}

fn homeDir(allocator: std.mem.Allocator) ![]const u8 {
    if (builtin.target.os.tag == .windows) {
        return std.process.getEnvVarOwned(allocator, "USERPROFILE");
    }

    return std.process.getEnvVarOwned(allocator, "HOME");
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
