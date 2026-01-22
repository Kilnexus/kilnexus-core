const std = @import("std");
const builtin = @import("builtin");

pub const Toolchain = enum {
    Zig,
    Rust,
    Go,
};

pub const default_zig_version = "0.15.2";
pub const default_rust_version = "1.76.0";
pub const default_go_version = "1.22.0";

pub fn toolchainName(tool: Toolchain) []const u8 {
    return switch (tool) {
        .Zig => "zig",
        .Rust => "rust",
        .Go => "go",
    };
}

pub fn resolveZigPath(allocator: std.mem.Allocator, cwd: std.fs.Dir) ![]const u8 {
    return resolveZigPathForVersion(allocator, cwd, default_zig_version);
}

pub fn resolveZigPathForVersion(allocator: std.mem.Allocator, cwd: std.fs.Dir, version: []const u8) ![]const u8 {
    return resolveToolPathForVersion(allocator, cwd, zigRelPathForVersion, zigGlobalPathForVersion, version);
}

pub fn zigRelPath(allocator: std.mem.Allocator) ![]const u8 {
    return zigRelPathForVersion(allocator, default_zig_version);
}

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

pub fn zigGlobalPath(allocator: std.mem.Allocator) ![]const u8 {
    return zigGlobalPathForVersion(allocator, default_zig_version);
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

pub fn resolveRustcPathForVersion(allocator: std.mem.Allocator, cwd: std.fs.Dir, version: []const u8) ![]const u8 {
    return resolveToolPathForVersion(allocator, cwd, rustcRelPathForVersion, rustcGlobalPathForVersion, version);
}

pub fn resolveCargoPathForVersion(allocator: std.mem.Allocator, cwd: std.fs.Dir, version: []const u8) ![]const u8 {
    return resolveToolPathForVersion(allocator, cwd, cargoRelPathForVersion, cargoGlobalPathForVersion, version);
}

pub fn resolveGoPathForVersion(allocator: std.mem.Allocator, cwd: std.fs.Dir, version: []const u8) ![]const u8 {
    return resolveToolPathForVersion(allocator, cwd, goRelPathForVersion, goGlobalPathForVersion, version);
}

pub fn zigInstallDirRel(allocator: std.mem.Allocator) ![]const u8 {
    return zigInstallDirRelForVersion(allocator, default_zig_version);
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

pub fn zigInstallDirGlobal(allocator: std.mem.Allocator) ![]const u8 {
    return zigInstallDirGlobalForVersion(allocator, default_zig_version);
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

pub fn zigArchiveName(allocator: std.mem.Allocator) ![]const u8 {
    return zigArchiveNameForVersion(allocator, default_zig_version);
}

pub fn zigArchiveNameForVersion(allocator: std.mem.Allocator, version: []const u8) ![]const u8 {
    const folder = try zigFolderName(allocator, version);
    defer allocator.free(folder);
    const ext = if (builtin.target.os.tag == .windows) ".zip" else ".tar.xz";
    return std.fmt.allocPrint(allocator, "{s}{s}", .{ folder, ext });
}

pub fn rustArchiveNameForVersion(allocator: std.mem.Allocator, version: []const u8) ![]const u8 {
    const folder = try rustFolderName(allocator, version);
    defer allocator.free(folder);
    return std.fmt.allocPrint(allocator, "{s}.tar.xz", .{folder});
}

pub fn goArchiveNameForVersion(allocator: std.mem.Allocator, version: []const u8) ![]const u8 {
    const os_part = goOsName();
    const arch_part = goArchName();
    if (std.mem.eql(u8, os_part, "unknown") or std.mem.eql(u8, arch_part, "unknown"))
        return error.UnsupportedPlatform;
    const ext = if (builtin.target.os.tag == .windows) ".zip" else ".tar.gz";
    return std.fmt.allocPrint(allocator, "go{s}.{s}-{s}{s}", .{ version, os_part, arch_part, ext });
}

pub fn zigDownloadUrl(allocator: std.mem.Allocator) ![]const u8 {
    return zigDownloadUrlForVersion(allocator, default_zig_version);
}

pub fn zigDownloadUrlForVersion(allocator: std.mem.Allocator, version: []const u8) ![]const u8 {
    const name = try zigArchiveNameForVersion(allocator, version);
    defer allocator.free(name);
    return std.fmt.allocPrint(allocator, "https://ziglang.org/download/{s}/{s}", .{ version, name });
}

pub fn rustDownloadUrlForVersion(allocator: std.mem.Allocator, version: []const u8) ![]const u8 {
    const name = try rustArchiveNameForVersion(allocator, version);
    defer allocator.free(name);
    return std.fmt.allocPrint(allocator, "https://static.rust-lang.org/dist/{s}", .{name});
}

pub fn goDownloadUrlForVersion(allocator: std.mem.Allocator, version: []const u8) ![]const u8 {
    const name = try goArchiveNameForVersion(allocator, version);
    defer allocator.free(name);
    return std.fmt.allocPrint(allocator, "https://go.dev/dl/{s}", .{name});
}

pub fn zigSignatureNameForVersion(allocator: std.mem.Allocator, version: []const u8) ![]const u8 {
    const archive = try zigArchiveNameForVersion(allocator, version);
    defer allocator.free(archive);
    return std.fmt.allocPrint(allocator, "{s}.minisig", .{archive});
}

pub fn zigSignatureUrlForVersion(allocator: std.mem.Allocator, version: []const u8) ![]const u8 {
    const name = try zigSignatureNameForVersion(allocator, version);
    defer allocator.free(name);
    return std.fmt.allocPrint(allocator, "https://ziglang.org/download/{s}/{s}", .{ version, name });
}

pub fn ensureToolchainDir(cwd: std.fs.Dir) !void {
    cwd.makePath(".kilnexus/toolchains") catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
}

pub fn ensureToolchainDirFor(cwd: std.fs.Dir, tool: Toolchain) !void {
    const base = try std.fmt.allocPrint(std.heap.page_allocator, ".kilnexus/toolchains/{s}", .{toolchainName(tool)});
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

pub fn hostOsName() []const u8 {
    return switch (builtin.target.os.tag) {
        .windows => "windows",
        .linux => "linux",
        .macos => "macos",
        else => "unknown",
    };
}

pub fn hostArchName() []const u8 {
    return switch (builtin.target.cpu.arch) {
        .x86_64 => "x86_64",
        .aarch64 => "aarch64",
        else => "unknown",
    };
}

fn goOsName() []const u8 {
    return switch (builtin.target.os.tag) {
        .windows => "windows",
        .linux => "linux",
        .macos => "darwin",
        else => "unknown",
    };
}

fn goArchName() []const u8 {
    return switch (builtin.target.cpu.arch) {
        .x86_64 => "amd64",
        .aarch64 => "arm64",
        else => "unknown",
    };
}

fn rustTargetTriple(allocator: std.mem.Allocator) ![]const u8 {
    const os_part = switch (builtin.target.os.tag) {
        .windows => "pc-windows-msvc",
        .linux => "unknown-linux-gnu",
        .macos => "apple-darwin",
        else => "unknown",
    };
    const arch_part = switch (builtin.target.cpu.arch) {
        .x86_64 => "x86_64",
        .aarch64 => "aarch64",
        else => "unknown",
    };
    if (std.mem.eql(u8, os_part, "unknown") or std.mem.eql(u8, arch_part, "unknown"))
        return error.UnsupportedPlatform;
    return std.fmt.allocPrint(allocator, "{s}-{s}", .{ arch_part, os_part });
}

fn zigFolderName(allocator: std.mem.Allocator, version: []const u8) ![]const u8 {
    const os_part = hostOsName();
    const arch_part = hostArchName();
    if (std.mem.eql(u8, os_part, "unknown") or std.mem.eql(u8, arch_part, "unknown"))
        return error.UnsupportedPlatform;
    return std.fmt.allocPrint(allocator, "zig-{s}-{s}-{s}", .{ os_part, arch_part, version });
}

fn rustFolderName(allocator: std.mem.Allocator, version: []const u8) ![]const u8 {
    const triple = try rustTargetTriple(allocator);
    defer allocator.free(triple);
    return std.fmt.allocPrint(allocator, "rust-{s}-{s}", .{ version, triple });
}

fn resolveToolPathForVersion(
    allocator: std.mem.Allocator,
    cwd: std.fs.Dir,
    comptime rel_fn: fn (std.mem.Allocator, []const u8) anyerror![]const u8,
    comptime global_fn: fn (std.mem.Allocator, []const u8) anyerror![]const u8,
    version: []const u8,
) ![]const u8 {
    const rel = try rel_fn(allocator, version);
    errdefer allocator.free(rel);

    if (cwd.access(rel, .{})) |_| {
        return rel;
    } else |_| {
        allocator.free(rel);
    }

    const global = try global_fn(allocator, version);
    errdefer allocator.free(global);
    std.fs.cwd().access(global, .{}) catch return error.ToolchainMissing;
    return global;
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
