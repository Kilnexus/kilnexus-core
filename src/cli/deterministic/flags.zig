const std = @import("std");
const protocol_types = @import("../../protocol/types.zig");

pub const Level = protocol_types.DeterministicLevel;

pub const DeterministicFlags = struct {
    pub fn forZig(level: Level) []const []const u8 {
        return switch (level) {
            .Strict => &[_][]const u8{ "-fno-PIE", "--strip", "-fno-stack-protector" },
            .Standard => &[_][]const u8{ "--strip" },
            .Relaxed => &[_][]const u8{},
        };
    }

    pub fn forRust(level: Level) []const []const u8 {
        return switch (level) {
            .Strict => &[_][]const u8{
                "-C",
                "debuginfo=0",
                "-C",
                "opt-level=3",
                "-C",
                "codegen-units=1",
                "-C",
                "lto=fat",
                "-C",
                "embed-bitcode=no",
                "-C",
                "overflow-checks=off",
                "-C",
                "panic=abort",
                "-C",
                "strip=symbols",
            },
            .Standard => &[_][]const u8{
                "-C",
                "debuginfo=0",
                "-C",
                "codegen-units=1",
                "-C",
                "strip=symbols",
            },
            .Relaxed => &[_][]const u8{
                "-C",
                "codegen-units=1",
            },
        };
    }

    pub fn forC(level: Level) []const []const u8 {
        return switch (level) {
            .Strict => &[_][]const u8{
                "-fno-PIE",
                "-fno-stack-protector",
                "-fno-asynchronous-unwind-tables",
                "-fno-unwind-tables",
                "-fno-ident",
                "-fno-common",
                "-frandom-seed=kilnexus",
            },
            .Standard => &[_][]const u8{
                "-fno-ident",
                "-frandom-seed=kilnexus",
            },
            .Relaxed => &[_][]const u8{
                "-frandom-seed=kilnexus",
            },
        };
    }

    pub fn forLinker(level: Level) []const []const u8 {
        _ = level;
        return &[_][]const u8{};
    }

    pub fn merge(
        allocator: std.mem.Allocator,
        existing: []const []const u8,
        extra: []const []const u8,
    ) ![]const []const u8 {
        const merged = try allocator.alloc([]const u8, existing.len + extra.len);
        std.mem.copyForwards([]const u8, merged[0..existing.len], existing);
        std.mem.copyForwards([]const u8, merged[existing.len..], extra);
        return merged;
    }
};
