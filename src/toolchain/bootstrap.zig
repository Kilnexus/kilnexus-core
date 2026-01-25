const std = @import("std");
const manager = @import("manager.zig");
const minisign = @import("minisign.zig");
const download = @import("bootstrap/download.zig");
const extract = @import("bootstrap/extract.zig");

pub fn bootstrapZig(allocator: std.mem.Allocator, cwd: std.fs.Dir, version: []const u8) !void {
    const zig_path = manager.zigRelPathForVersion(allocator, version) catch null;
    if (zig_path) |path| {
        defer allocator.free(path);
        if (existsRel(cwd, path)) return;
    }

    try manager.ensureToolchainDirFor(cwd, .Zig);
    const install_dir = try manager.zigInstallDirRelForVersion(allocator, version);
    defer allocator.free(install_dir);
    try cwd.makePath(install_dir);

    const archive_name = try manager.zigArchiveNameForVersion(allocator, version);
    defer allocator.free(archive_name);
    const archive_path = try std.fs.path.join(allocator, &[_][]const u8{ install_dir, archive_name });
    defer allocator.free(archive_path);

    const archive_url = try manager.zigDownloadUrlForVersion(allocator, version);
    defer allocator.free(archive_url);

    const sig_name = try manager.zigSignatureNameForVersion(allocator, version);
    defer allocator.free(sig_name);
    const sig_path = try std.fs.path.join(allocator, &[_][]const u8{ install_dir, sig_name });
    defer allocator.free(sig_path);

    const sig_url = try manager.zigSignatureUrlForVersion(allocator, version);
    defer allocator.free(sig_url);

    try download.downloadFile(allocator, archive_url, archive_path);
    try download.downloadFile(allocator, sig_url, sig_path);
    try minisign.verifyFileSignature(allocator, archive_path, sig_path);
    try extract.extractArchive(allocator, archive_path, install_dir, 1);
}

pub fn bootstrapRust(allocator: std.mem.Allocator, cwd: std.fs.Dir, version: []const u8) !void {
    const rustc_path = manager.rustcRelPathForVersion(allocator, version) catch null;
    if (rustc_path) |path| {
        defer allocator.free(path);
        if (existsRel(cwd, path)) return;
    }

    try manager.ensureToolchainDirFor(cwd, .Rust);
    const install_dir = try manager.rustInstallDirRelForVersion(allocator, version);
    defer allocator.free(install_dir);
    try cwd.makePath(install_dir);

    const archive_name = try manager.rustArchiveNameForVersion(allocator, version);
    defer allocator.free(archive_name);
    const archive_path = try std.fs.path.join(allocator, &[_][]const u8{ install_dir, archive_name });
    defer allocator.free(archive_path);

    const archive_url = try manager.rustDownloadUrlForVersion(allocator, version);
    defer allocator.free(archive_url);

    try download.downloadFile(allocator, archive_url, archive_path);
    if (minisign.getPublicKeyForTool(.Rust)) |key| {
        const sig_name = try std.fmt.allocPrint(allocator, "{s}.minisig", .{archive_name});
        defer allocator.free(sig_name);
        const sig_path = try std.fs.path.join(allocator, &[_][]const u8{ install_dir, sig_name });
        defer allocator.free(sig_path);
        const sig_url = try std.fmt.allocPrint(allocator, "{s}.minisig", .{archive_url});
        defer allocator.free(sig_url);
        try download.downloadFile(allocator, sig_url, sig_path);
        try minisign.verifyFileSignatureWithKey(allocator, archive_path, sig_path, key);
    }
    try extract.extractArchive(allocator, archive_path, install_dir, 1);
}

pub fn bootstrapGo(allocator: std.mem.Allocator, cwd: std.fs.Dir, version: []const u8) !void {
    const go_path = manager.goRelPathForVersion(allocator, version) catch null;
    if (go_path) |path| {
        defer allocator.free(path);
        if (existsRel(cwd, path)) return;
    }

    try manager.ensureToolchainDirFor(cwd, .Go);
    const install_dir = try manager.goInstallDirRelForVersion(allocator, version);
    defer allocator.free(install_dir);
    try cwd.makePath(install_dir);

    const archive_name = try manager.goArchiveNameForVersion(allocator, version);
    defer allocator.free(archive_name);
    const archive_path = try std.fs.path.join(allocator, &[_][]const u8{ install_dir, archive_name });
    defer allocator.free(archive_path);

    const archive_url = try manager.goDownloadUrlForVersion(allocator, version);
    defer allocator.free(archive_url);

    try download.downloadFile(allocator, archive_url, archive_path);
    if (minisign.getPublicKeyForTool(.Go)) |key| {
        const sig_name = try std.fmt.allocPrint(allocator, "{s}.minisig", .{archive_name});
        defer allocator.free(sig_name);
        const sig_path = try std.fs.path.join(allocator, &[_][]const u8{ install_dir, sig_name });
        defer allocator.free(sig_path);
        const sig_url = try std.fmt.allocPrint(allocator, "{s}.minisig", .{archive_url});
        defer allocator.free(sig_url);
        try download.downloadFile(allocator, sig_url, sig_path);
        try minisign.verifyFileSignatureWithKey(allocator, archive_path, sig_path, key);
    }
    try extract.extractArchive(allocator, archive_path, install_dir, 0);
}

fn existsRel(cwd: std.fs.Dir, path: []const u8) bool {
    cwd.access(path, .{}) catch return false;
    return true;
}
