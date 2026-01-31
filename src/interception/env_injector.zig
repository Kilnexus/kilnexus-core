const std = @import("std");
const common = @import("common.zig");

pub fn inject(env: *common.InterceptionEnv) !void {
    const dir = env.wrapper_dir orelse return;
    const existing = env.env_map.get("PATH");
    if (existing) |value| {
        if (containsPathSegment(value, dir)) return;
        const merged = try std.fmt.allocPrint(env.allocator, "{s}{c}{s}", .{
            dir,
            std.fs.path.delimiter,
            value,
        });
        defer env.allocator.free(merged);
        try env.putEnv("PATH", merged);
        return;
    }
    try env.putEnv("PATH", dir);
}

fn containsPathSegment(list: []const u8, segment: []const u8) bool {
    var it = std.mem.splitScalar(u8, list, std.fs.path.delimiter);
    while (it.next()) |item| {
        if (std.mem.eql(u8, item, segment)) return true;
    }
    return false;
}
