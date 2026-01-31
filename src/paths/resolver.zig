const std = @import("std");
const config = @import("config.zig");

pub const ToolchainLocation = enum {
    Project,
    Global,
};

pub fn toolchainSearchOrder(allocator: std.mem.Allocator) ![]ToolchainLocation {
    const use_global = try config.envBoolOrDefault(allocator, "KNX_USE_GLOBAL", true);
    if (!use_global) {
        return allocator.dupe(ToolchainLocation, &[_]ToolchainLocation{.Project});
    }

    const env_value = std.process.getEnvVarOwned(allocator, "KNX_TOOLCHAIN_PRIORITY") catch null;
    if (env_value) |value| {
        defer allocator.free(value);
        var order = std.ArrayList(ToolchainLocation).empty;
        var it = std.mem.splitAny(u8, value, ", ");
        while (it.next()) |token| {
            if (token.len == 0) continue;
            if (std.ascii.eqlIgnoreCase(token, "project")) {
                try appendUnique(allocator, &order, .Project);
            } else if (std.ascii.eqlIgnoreCase(token, "global")) {
                try appendUnique(allocator, &order, .Global);
            }
        }
        if (order.items.len == 0) {
            try order.append(allocator, .Project);
            try order.append(allocator, .Global);
        }
        return order.toOwnedSlice(allocator);
    }

    return allocator.dupe(ToolchainLocation, &[_]ToolchainLocation{ .Project, .Global });
}

fn appendUnique(allocator: std.mem.Allocator, list: *std.ArrayList(ToolchainLocation), value: ToolchainLocation) !void {
    for (list.items) |item| {
        if (item == value) return;
    }
    try list.append(allocator, value);
}
