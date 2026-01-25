const std = @import("std");

pub const resolver = @import("manager/resolver.zig");
pub const paths = @import("manager/paths.zig");
pub const download = @import("manager/download.zig");
pub const platform = @import("manager/platform.zig");
pub const common = @import("manager/common.zig");

pub const Toolchain = common.Toolchain;
pub const toolchainName = common.toolchainName;
pub const default_zig_version = common.default_zig_version;
pub const default_rust_version = common.default_rust_version;
pub const default_go_version = common.default_go_version;

pub fn resolveZigPath(allocator: std.mem.Allocator, cwd: std.fs.Dir) ![]const u8 {
    return resolver.resolveZigPathForVersion(allocator, cwd, default_zig_version);
}

pub fn zigRelPath(allocator: std.mem.Allocator) ![]const u8 {
    return paths.zigRelPathForVersion(allocator, default_zig_version);
}

pub fn zigGlobalPath(allocator: std.mem.Allocator) ![]const u8 {
    return paths.zigGlobalPathForVersion(allocator, default_zig_version);
}

pub fn zigInstallDirRel(allocator: std.mem.Allocator) ![]const u8 {
    return paths.zigInstallDirRelForVersion(allocator, default_zig_version);
}

pub fn zigInstallDirGlobal(allocator: std.mem.Allocator) ![]const u8 {
    return paths.zigInstallDirGlobalForVersion(allocator, default_zig_version);
}

pub fn zigArchiveName(allocator: std.mem.Allocator) ![]const u8 {
    return download.zigArchiveNameForVersion(allocator, default_zig_version);
}

pub fn zigDownloadUrl(allocator: std.mem.Allocator) ![]const u8 {
    return download.zigDownloadUrlForVersion(allocator, default_zig_version);
}

pub const resolveZigPathForVersion = resolver.resolveZigPathForVersion;
pub const resolveRustcPathForVersion = resolver.resolveRustcPathForVersion;
pub const resolveCargoPathForVersion = resolver.resolveCargoPathForVersion;
pub const resolveGoPathForVersion = resolver.resolveGoPathForVersion;

pub const zigRelPathForVersion = paths.zigRelPathForVersion;
pub const zigGlobalPathForVersion = paths.zigGlobalPathForVersion;
pub const zigInstallDirRelForVersion = paths.zigInstallDirRelForVersion;
pub const zigInstallDirGlobalForVersion = paths.zigInstallDirGlobalForVersion;
pub const rustcRelPathForVersion = paths.rustcRelPathForVersion;
pub const rustcGlobalPathForVersion = paths.rustcGlobalPathForVersion;
pub const cargoRelPathForVersion = paths.cargoRelPathForVersion;
pub const cargoGlobalPathForVersion = paths.cargoGlobalPathForVersion;
pub const rustInstallDirRelForVersion = paths.rustInstallDirRelForVersion;
pub const rustInstallDirGlobalForVersion = paths.rustInstallDirGlobalForVersion;
pub const goRelPathForVersion = paths.goRelPathForVersion;
pub const goGlobalPathForVersion = paths.goGlobalPathForVersion;
pub const goInstallDirRelForVersion = paths.goInstallDirRelForVersion;
pub const goInstallDirGlobalForVersion = paths.goInstallDirGlobalForVersion;
pub const ensureToolchainDir = paths.ensureToolchainDir;
pub const ensureToolchainDirFor = paths.ensureToolchainDirFor;
pub const ensureProjectCache = paths.ensureProjectCache;

pub const zigArchiveNameForVersion = download.zigArchiveNameForVersion;
pub const rustArchiveNameForVersion = download.rustArchiveNameForVersion;
pub const goArchiveNameForVersion = download.goArchiveNameForVersion;
pub const zigDownloadUrlForVersion = download.zigDownloadUrlForVersion;
pub const rustDownloadUrlForVersion = download.rustDownloadUrlForVersion;
pub const goDownloadUrlForVersion = download.goDownloadUrlForVersion;
pub const zigSignatureNameForVersion = download.zigSignatureNameForVersion;
pub const zigSignatureUrlForVersion = download.zigSignatureUrlForVersion;

pub const hostOsName = platform.hostOsName;
pub const hostArchName = platform.hostArchName;
