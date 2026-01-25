const std = @import("std");
const manager = @import("manager.zig");
const common = @import("source_builder/common.zig");
const download = @import("source_builder/download.zig");
const build = @import("source_builder/build.zig");
const bootstrap_seed = @import("source_builder/bootstrap_seed.zig");
const verify = @import("source_builder/verify.zig");
const install = @import("source_builder/install.zig");

pub const BootstrapSeedSpec = struct {
    version: []const u8,
    sha256: ?[]const u8 = null,
    command: ?[]const u8 = null,
};

pub fn buildZigFromSource(
    version: []const u8,
    sha256: ?[]const u8,
    seed_spec: ?BootstrapSeedSpec,
) !void {
    const allocator = std.heap.page_allocator;
    const source_root = try download.prepareSource(.Zig, version, sha256);
    defer allocator.free(source_root);
    const build_dir = try common.buildDirFor(.Zig, source_root, "zig-out");
    defer allocator.free(build_dir);
    var seed_path: ?[]const u8 = null;
    defer if (seed_path) |path| allocator.free(path);
    if (seed_spec) |spec| {
        seed_path = try bootstrap_seed.buildZigSeed(.{
            .version = spec.version,
            .sha256 = spec.sha256,
            .command = spec.command,
        });
    }
    try build.buildZig(source_root, seed_path);
    try verify.verifyStages(.Zig, build_dir);
    const install_dir = try manager.zigInstallDirRelForVersion(allocator, version);
    defer allocator.free(install_dir);
    try install.installFromBuild(build_dir, install_dir);
}

pub fn buildRustFromSource(version: []const u8, sha256: ?[]const u8) !void {
    const allocator = std.heap.page_allocator;
    const source_root = try download.prepareSource(.Rust, version, sha256);
    defer allocator.free(source_root);
    const build_dir = try common.buildDirFor(.Rust, source_root, "build");
    defer allocator.free(build_dir);
    try build.buildRust(source_root);
    try verify.verifyStages(.Rust, build_dir);
    const install_dir = try manager.rustInstallDirRelForVersion(allocator, version);
    defer allocator.free(install_dir);
    try install.installRustFromStage(build_dir, install_dir);
}

pub fn buildMuslFromSource(version: []const u8, sha256: ?[]const u8) !void {
    const allocator = std.heap.page_allocator;
    const source_root = try download.prepareSource(.Musl, version, sha256);
    defer allocator.free(source_root);
    const build_dir = try common.buildDirFor(.Musl, source_root, "install");
    defer allocator.free(build_dir);
    try build.buildMusl(source_root, build_dir);
    const install_dir = try common.muslInstallDirRel(version);
    defer allocator.free(install_dir);
    try install.installFromBuild(build_dir, install_dir);
}
