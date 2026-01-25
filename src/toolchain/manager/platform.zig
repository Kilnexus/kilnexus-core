const std = @import("std");
const builtin = @import("builtin");

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

pub fn goOsName() []const u8 {
    return switch (builtin.target.os.tag) {
        .windows => "windows",
        .linux => "linux",
        .macos => "darwin",
        else => "unknown",
    };
}

pub fn goArchName() []const u8 {
    return switch (builtin.target.cpu.arch) {
        .x86_64 => "amd64",
        .aarch64 => "arm64",
        else => "unknown",
    };
}

pub fn rustTargetTriple(allocator: std.mem.Allocator) ![]const u8 {
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
