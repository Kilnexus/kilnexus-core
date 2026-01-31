const std = @import("std");
const core = @import("../../root.zig");
const paths_config = @import("../../paths/config.zig");

pub const CargoConfigOptions = struct {
    target: core.toolchain_cross.target.CrossTarget,
    linker_path: []const u8,
    rustflags: []const []const u8 = &[_][]const u8{},
};

pub fn writeConfig(
    allocator: std.mem.Allocator,
    cwd: std.fs.Dir,
    options: CargoConfigOptions,
) ![]const u8 {
    const dir = try paths_config.projectPath(allocator, &[_][]const u8{ "interception", "cargo" });
    try cwd.makePath(dir);
    defer allocator.free(dir);

    const out_path = try std.fs.path.join(allocator, &[_][]const u8{ dir, "config.toml" });
    errdefer allocator.free(out_path);

    var file = try cwd.createFile(out_path, .{ .truncate = true });
    defer file.close();
    var buf: [16 * 1024]u8 = undefined;
    var writer = file.writer(&buf);

    const target_triple = options.target.toRustTarget();
    const linker_path = try normalizePathAlloc(allocator, options.linker_path);
    defer allocator.free(linker_path);

    try writer.interface.print("[target.{s}]\n", .{target_triple});
    try writer.interface.print("linker = \"{s}\"\n", .{linker_path});
    if (options.rustflags.len != 0) {
        try writer.interface.writeAll("rustflags = [");
        for (options.rustflags, 0..) |flag, idx| {
            if (idx != 0) try writer.interface.writeAll(", ");
            const escaped = try escapeTomlString(allocator, flag);
            defer allocator.free(escaped);
            try writer.interface.print("\"{s}\"", .{escaped});
        }
        try writer.interface.writeAll("]\n");
    }
    try writer.interface.flush();
    return out_path;
}

fn normalizePathAlloc(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    const out = try allocator.dupe(u8, path);
    std.mem.replaceScalar(u8, out, '\\', '/');
    return out;
}

fn escapeTomlString(allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    for (value) |ch| {
        switch (ch) {
            '\\' => try out.appendSlice(allocator, "\\\\"),
            '"' => try out.appendSlice(allocator, "\\\""),
            '\n' => try out.appendSlice(allocator, "\\n"),
            '\r' => try out.appendSlice(allocator, "\\r"),
            '\t' => try out.appendSlice(allocator, "\\t"),
            else => try out.append(allocator, ch),
        }
    }
    return out.toOwnedSlice(allocator);
}
