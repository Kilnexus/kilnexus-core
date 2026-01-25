const std = @import("std");
const manifest_types = @import("manifest_types.zig");

pub fn hashSourceFile(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const digest = try sha256File(file);
    return digestHexAlloc(allocator, &digest);
}

pub fn hashSourceFiles(
    allocator: std.mem.Allocator,
    paths: []const []const u8,
) ![]manifest_types.SourceHash {
    var result = try allocator.alloc(manifest_types.SourceHash, paths.len);
    for (paths, 0..) |path, i| {
        const hash = try hashSourceFile(allocator, path);
        result[i] = .{
            .path = path,
            .sha256 = hash,
        };
    }
    return result;
}

pub fn sha256File(file: std.fs.File) ![32]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    var buf: [32 * 1024]u8 = undefined;
    var f = file;
    try f.seekTo(0);
    while (true) {
        const amt = try f.read(buf[0..]);
        if (amt == 0) break;
        hasher.update(buf[0..amt]);
    }
    return hasher.finalResult();
}

pub fn digestHexAlloc(allocator: std.mem.Allocator, digest: *const [32]u8) ![]const u8 {
    const hex_buf = std.fmt.bytesToHex(digest.*, .lower);
    return allocator.dupe(u8, hex_buf[0..]);
}
