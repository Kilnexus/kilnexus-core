const std = @import("std");
const target_mod = @import("target.zig");

pub const SysrootSource = enum {
    ZigBuiltin,
    MuslCustom,
    SystemPath,
    ExternalPath,
};

pub const SysrootSpec = struct {
    source: SysrootSource,
    path: ?[]const u8 = null,
};

pub const SysrootConfig = struct {
    root: ?[]const u8,
    include_dirs: std.ArrayList([]const u8),
    lib_dirs: std.ArrayList([]const u8),
    is_complete: bool,
    owned: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator) SysrootConfig {
        return .{
            .root = null,
            .include_dirs = .empty,
            .lib_dirs = .empty,
            .is_complete = false,
            .owned = .empty,
        };
    }

    pub fn deinit(self: *SysrootConfig, allocator: std.mem.Allocator) void {
        for (self.owned.items) |item| allocator.free(item);
        self.owned.deinit(allocator);
        self.include_dirs.deinit(allocator);
        self.lib_dirs.deinit(allocator);
    }
};

pub fn parseSysrootSpec(raw: []const u8) SysrootSpec {
    if (std.ascii.eqlIgnoreCase(raw, "zig-builtin")) {
        return .{ .source = .ZigBuiltin };
    }
    if (std.ascii.eqlIgnoreCase(raw, "musl-custom")) {
        return .{ .source = .MuslCustom };
    }
    if (std.ascii.eqlIgnoreCase(raw, "system")) {
        return .{ .source = .SystemPath };
    }
    return .{ .source = .ExternalPath, .path = raw };
}

pub fn resolveSysroot(
    allocator: std.mem.Allocator,
    target: ?target_mod.CrossTarget,
    spec: SysrootSpec,
    musl_root: ?[]const u8,
) !SysrootConfig {
    _ = target;
    var config = SysrootConfig.init(allocator);
    errdefer config.deinit(allocator);

    switch (spec.source) {
        .ZigBuiltin => {
            config.is_complete = true;
            return config;
        },
        .MuslCustom => {
            if (musl_root) |root| {
                config.root = root;
                try addDefaultDirs(allocator, &config, root);
                config.is_complete = true;
            }
            return config;
        },
        .SystemPath => {
            config.is_complete = false;
            return config;
        },
        .ExternalPath => {
            if (spec.path) |root| {
                config.root = root;
                try addDefaultDirs(allocator, &config, root);
                config.is_complete = true;
            }
            return config;
        },
    }
}

fn addDefaultDirs(allocator: std.mem.Allocator, config: *SysrootConfig, root: []const u8) !void {
    const inc = try std.fs.path.join(allocator, &[_][]const u8{ root, "include" });
    try config.owned.append(allocator, inc);
    try config.include_dirs.append(allocator, inc);

    const lib = try std.fs.path.join(allocator, &[_][]const u8{ root, "lib" });
    try config.owned.append(allocator, lib);
    try config.lib_dirs.append(allocator, lib);
}
