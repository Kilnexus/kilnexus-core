const std = @import("std");
const target_mod = @import("../../toolchain/cross/target.zig");

pub const CrossTarget = target_mod.CrossTarget;

pub const TargetSpec = struct {
    target: CrossTarget,
};

pub const TargetSet = struct {
    targets: std.ArrayList(CrossTarget) = .empty,

    pub fn deinit(self: *TargetSet, allocator: std.mem.Allocator) void {
        self.targets.deinit(allocator);
    }

    pub fn add(self: *TargetSet, allocator: std.mem.Allocator, target: CrossTarget) !void {
        if (!self.contains(target)) {
            try self.targets.append(allocator, target);
        }
    }

    pub fn contains(self: *const TargetSet, target: CrossTarget) bool {
        for (self.targets.items) |item| {
            if (item.arch == target.arch and item.os == target.os and item.abi == target.abi) {
                return true;
            }
        }
        return false;
    }
};

pub fn parseTargets(allocator: std.mem.Allocator, input: []const u8) !TargetSet {
    var set = TargetSet{};
    errdefer set.deinit(allocator);

    var it = std.mem.tokenizeAny(u8, input, " ,\t");
    while (it.next()) |token| {
        if (token.len == 0) continue;
        const expanded = expandAlias(token);
        if (expanded.len != 0) {
            for (expanded) |target| {
                try set.add(allocator, target);
            }
            continue;
        }

        const target = target_mod.CrossTarget.parse(token) catch return error.InvalidTarget;
        try set.add(allocator, target);
    }

    if (set.targets.items.len == 0) return error.MissingTargets;
    return set;
}

pub fn expandAlias(alias: []const u8) []const CrossTarget {
    if (std.ascii.eqlIgnoreCase(alias, "linux-all")) return &linux_all;
    if (std.ascii.eqlIgnoreCase(alias, "windows-all")) return &windows_all;
    if (std.ascii.eqlIgnoreCase(alias, "tier1")) return &tier1;
    return &[_]CrossTarget{};
}

const linux_all = [_]CrossTarget{
    .{ .arch = .x86_64, .os = .linux, .abi = .musl },
    .{ .arch = .aarch64, .os = .linux, .abi = .musl },
    .{ .arch = .riscv64, .os = .linux, .abi = .gnu },
};

const windows_all = [_]CrossTarget{
    .{ .arch = .x86_64, .os = .windows, .abi = .gnu },
};

const tier1 = [_]CrossTarget{
    .{ .arch = .x86_64, .os = .linux, .abi = .musl },
    .{ .arch = .aarch64, .os = .linux, .abi = .musl },
    .{ .arch = .x86_64, .os = .windows, .abi = .gnu },
};

test "parseTargets handles csv, whitespace, and alias" {
    const allocator = std.testing.allocator;
    var set = try parseTargets(allocator, "x86_64-linux-musl, tier1");
    defer set.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 3), set.targets.items.len);
}

test "parseTargets rejects empty input" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.MissingTargets, parseTargets(allocator, "  ,\t"));
}
