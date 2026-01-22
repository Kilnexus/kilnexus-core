const std = @import("std");

pub const TargetResolution = struct {
    value: []const u8,
    owned: ?[]const u8,
};

pub fn resolveTarget(allocator: std.mem.Allocator, target: []const u8, kernel_version: ?[]const u8) !TargetResolution {
    if (kernel_version) |version| {
        if (needsKernelSuffix(target, version)) {
            const combined = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ target, version });
            return .{ .value = combined, .owned = combined };
        }
    }
    return .{ .value = target, .owned = null };
}

fn needsKernelSuffix(target: []const u8, kernel_version: []const u8) bool {
    if (std.mem.indexOf(u8, target, kernel_version) != null) return false;
    if (std.mem.indexOf(u8, target, "linux-gnu") == null) return false;
    if (std.mem.indexOf(u8, target, "linux-gnu.") != null) return false;
    return true;
}

test "resolveTarget adds kernel suffix for linux-gnu target" {
    const allocator = std.testing.allocator;
    const resolved = try resolveTarget(allocator, "x86_64-linux-gnu", "2.6.32");
    defer if (resolved.owned) |value| allocator.free(value);
    try std.testing.expectEqualStrings("x86_64-linux-gnu.2.6.32", resolved.value);
}
