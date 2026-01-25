const std = @import("std");
const builtin = @import("builtin");

const platform = @import("platform.zig");

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
    const os_part = platform.goOsName();
    const arch_part = platform.goArchName();
    if (std.mem.eql(u8, os_part, "unknown") or std.mem.eql(u8, arch_part, "unknown"))
        return error.UnsupportedPlatform;
    const ext = if (builtin.target.os.tag == .windows) ".zip" else ".tar.gz";
    return std.fmt.allocPrint(allocator, "go{s}.{s}-{s}{s}", .{ version, os_part, arch_part, ext });
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
