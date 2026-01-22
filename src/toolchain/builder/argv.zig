const std = @import("std");

pub const ArgvBuild = struct {
    argv: std.ArrayList([]const u8),
    owned: std.ArrayList([]const u8),

    pub fn init() ArgvBuild {
        return .{ .argv = .empty, .owned = .empty };
    }

    pub fn deinit(self: *ArgvBuild, allocator: std.mem.Allocator) void {
        for (self.owned.items) |item| allocator.free(item);
        self.owned.deinit(allocator);
        self.argv.deinit(allocator);
    }
};
