const std = @import("std");

pub fn wrap(
    allocator: std.mem.Allocator,
    argv: []const []const u8,
    zig_path: []const u8,
    target: []const u8,
    sysroot: ?[]const u8,
    use_cxx: bool,
) ![]const []const u8 {
    if (argv.len == 0) return error.EmptyCommand;
    var extra_count: usize = 3;
    if (sysroot != null) extra_count += 2;

    var out = try allocator.alloc([]const u8, argv.len + extra_count);
    out[0] = zig_path;
    out[1] = if (use_cxx) "c++" else "cc";
    out[2] = "-target";
    out[3] = target;
    var idx: usize = 4;
    if (sysroot) |root| {
        out[idx] = "--sysroot";
        out[idx + 1] = root;
        idx += 2;
    }
    if (argv.len > 1) {
        std.mem.copyForwards([]const u8, out[idx..], argv[1..]);
    }
    return out;
}
