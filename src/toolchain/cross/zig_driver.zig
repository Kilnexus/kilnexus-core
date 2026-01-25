const std = @import("std");
const common = @import("../common.zig");
const builder_zig = @import("../builder/zig.zig");
const executor = @import("../executor.zig");
const target_builder = @import("../builder/target.zig");

pub const RustLinkerSpec = struct {
    linker: []const u8,
    rustflags: []const u8,
    owned: std.ArrayList([]const u8),

    pub fn init() RustLinkerSpec {
        return .{ .linker = "", .rustflags = "", .owned = .empty };
    }

    pub fn deinit(self: *RustLinkerSpec, allocator: std.mem.Allocator) void {
        for (self.owned.items) |item| allocator.free(item);
        self.owned.deinit(allocator);
    }
};

pub const CargoEnv = struct {
    rustflags: []const u8,
    linker_key: ?[]const u8,
    linker_value: ?[]const u8,
    owned: std.ArrayList([]const u8),

    pub fn init() CargoEnv {
        return .{
            .rustflags = "",
            .linker_key = null,
            .linker_value = null,
            .owned = .empty,
        };
    }

    pub fn deinit(self: *CargoEnv, allocator: std.mem.Allocator) void {
        for (self.owned.items) |item| allocator.free(item);
        self.owned.deinit(allocator);
    }
};

pub const ZigDriver = struct {
    allocator: std.mem.Allocator,
    cwd: std.fs.Dir,

    pub fn init(allocator: std.mem.Allocator, cwd: std.fs.Dir) ZigDriver {
        return .{ .allocator = allocator, .cwd = cwd };
    }

    pub fn compileC(self: ZigDriver, source: []const u8, options: common.CompileOptions) !void {
        var args = try builder_zig.buildZigArgs(self.allocator, "cc", source, options);
        defer args.deinit(self.allocator);
        if (options.env_map) |env_map| {
            try executor.ensureSourceDateEpoch(env_map);
            try executor.runWithEnvMap(self.allocator, self.cwd, args.argv.items, options.env, env_map);
            return;
        }
        var env_map = try executor.getEnvMap(self.allocator);
        defer env_map.deinit();
        try executor.ensureSourceDateEpoch(&env_map);
        try executor.runWithEnvMap(self.allocator, self.cwd, args.argv.items, options.env, &env_map);
    }

    pub fn compileCpp(self: ZigDriver, source: []const u8, options: common.CompileOptions) !void {
        var args = try builder_zig.buildZigArgs(self.allocator, "c++", source, options);
        defer args.deinit(self.allocator);
        if (options.env_map) |env_map| {
            try executor.ensureSourceDateEpoch(env_map);
            try executor.runWithEnvMap(self.allocator, self.cwd, args.argv.items, options.env, env_map);
            return;
        }
        var env_map = try executor.getEnvMap(self.allocator);
        defer env_map.deinit();
        try executor.ensureSourceDateEpoch(&env_map);
        try executor.runWithEnvMap(self.allocator, self.cwd, args.argv.items, options.env, &env_map);
    }

    pub fn link(self: ZigDriver, objects: []const []const u8, options: common.CompileOptions) !void {
        var args = std.ArrayList([]const u8).empty;
        var owned = std.ArrayList([]const u8).empty;
        defer {
            for (owned.items) |item| self.allocator.free(item);
            owned.deinit(self.allocator);
            args.deinit(self.allocator);
        }

        try args.appendSlice(self.allocator, &[_][]const u8{
            options.zig_path,
            "cc",
        });
        try args.appendSlice(self.allocator, objects);
        try args.appendSlice(self.allocator, &[_][]const u8{ "-o", options.output_name });
        if (options.static) try args.append(self.allocator, "-static");

        if (options.env.target) |target| {
            const resolved = try target_builder.resolveTarget(self.allocator, target, options.env.kernel_version);
            if (resolved.owned) |value| try owned.append(self.allocator, value);
            try args.append(self.allocator, "-target");
            try args.append(self.allocator, resolved.value);
        }

        if (options.env.sysroot) |sysroot| {
            try args.append(self.allocator, "--sysroot");
            try args.append(self.allocator, sysroot);
        }

        if (options.env_map) |env_map| {
            try executor.ensureSourceDateEpoch(env_map);
            try executor.runWithEnvMap(self.allocator, self.cwd, args.items, options.env, env_map);
            return;
        }
        var env_map = try executor.getEnvMap(self.allocator);
        defer env_map.deinit();
        try executor.ensureSourceDateEpoch(&env_map);
        try executor.runWithEnvMap(self.allocator, self.cwd, args.items, options.env, &env_map);
    }

    pub fn asRustLinker(self: ZigDriver, options: common.CompileOptions) !RustLinkerSpec {
        var spec = RustLinkerSpec.init();
        errdefer spec.deinit(self.allocator);

        const rustflags = try buildRustFlags(self.allocator, options);
        try spec.owned.append(self.allocator, rustflags);
        spec.linker = options.zig_path;
        spec.rustflags = rustflags;
        return spec;
    }

    pub fn asCargoEnv(self: ZigDriver, options: common.CompileOptions, existing_rustflags: ?[]const u8) !CargoEnv {
        var env = CargoEnv.init();
        errdefer env.deinit(self.allocator);

        const rustflags = try buildRustFlags(self.allocator, options);
        try env.owned.append(self.allocator, rustflags);
        env.rustflags = rustflags;

        if (existing_rustflags) |existing| {
            const merged = try std.fmt.allocPrint(self.allocator, "{s} {s}", .{ existing, rustflags });
            try env.owned.append(self.allocator, merged);
            env.rustflags = merged;
        }

        if (options.cross_target) |target| {
            const target_value = target.toRustTarget();
            const linker_key = try cargoTargetLinkerKey(self.allocator, target_value);
            try env.owned.append(self.allocator, linker_key);
            env.linker_key = linker_key;
            env.linker_value = options.zig_path;
        } else if (options.env.target) |target_value| {
            const linker_key = try cargoTargetLinkerKey(self.allocator, target_value);
            try env.owned.append(self.allocator, linker_key);
            env.linker_key = linker_key;
            env.linker_value = options.zig_path;
        }

        return env;
    }
};

fn buildRustFlags(allocator: std.mem.Allocator, options: common.CompileOptions) ![]const u8 {
    var parts = std.ArrayList([]const u8).empty;
    defer parts.deinit(allocator);
    var owned = std.ArrayList([]const u8).empty;
    defer {
        for (owned.items) |item| allocator.free(item);
        owned.deinit(allocator);
    }

    const linker_arg = try std.fmt.allocPrint(allocator, "-C linker={s}", .{options.zig_path});
    try owned.append(allocator, linker_arg);
    try parts.append(allocator, linker_arg);
    try parts.append(allocator, "-C link-arg=cc");

    if (options.static) try parts.append(allocator, "-C link-arg=-static");
    if (options.rust_crt_static) try parts.append(allocator, "-C target-feature=+crt-static");

    if (options.cross_target) |target| {
        const raw_target = target.toRustTarget();
        const resolved = try target_builder.resolveTarget(allocator, raw_target, options.env.kernel_version);
        if (resolved.owned) |value| try owned.append(allocator, value);
        try parts.append(allocator, "-C link-arg=-target");
        const target_arg = try std.fmt.allocPrint(allocator, "-C link-arg={s}", .{resolved.value});
        try owned.append(allocator, target_arg);
        try parts.append(allocator, target_arg);
    } else if (options.env.target) |raw_target| {
        const resolved = try target_builder.resolveTarget(allocator, raw_target, options.env.kernel_version);
        if (resolved.owned) |value| try owned.append(allocator, value);
        try parts.append(allocator, "-C link-arg=-target");
        const target_arg = try std.fmt.allocPrint(allocator, "-C link-arg={s}", .{resolved.value});
        try owned.append(allocator, target_arg);
        try parts.append(allocator, target_arg);
    }

    if (options.env.sysroot) |sysroot| {
        try parts.append(allocator, "-C link-arg=--sysroot");
        const sysroot_arg = try std.fmt.allocPrint(allocator, "-C link-arg={s}", .{sysroot});
        try owned.append(allocator, sysroot_arg);
        try parts.append(allocator, sysroot_arg);
    }

    if (options.lib_dirs.len != 0) {
        for (options.lib_dirs) |dir| {
            const lib_arg = try std.fmt.allocPrint(allocator, "-L {s}", .{dir});
            try owned.append(allocator, lib_arg);
            try parts.append(allocator, lib_arg);
        }
    }

    if (options.link_libs.len != 0) {
        for (options.link_libs) |lib| {
            const lib_arg = try std.fmt.allocPrint(allocator, "-l {s}", .{lib});
            try owned.append(allocator, lib_arg);
            try parts.append(allocator, lib_arg);
        }
    }

    if (options.rustflags_extra.len != 0) {
        for (options.rustflags_extra) |flag| {
            try parts.append(allocator, flag);
        }
    }

    return try std.mem.join(allocator, " ", parts.items);
}

fn cargoTargetLinkerKey(allocator: std.mem.Allocator, target: []const u8) ![]const u8 {
    var key = std.ArrayList(u8).empty;
    defer key.deinit(allocator);

    try key.appendSlice(allocator, "CARGO_TARGET_");
    for (target) |ch| {
        if (ch == '-' or ch == '.') {
            try key.append(allocator, '_');
        } else {
            try key.append(allocator, std.ascii.toUpper(ch));
        }
    }
    try key.appendSlice(allocator, "_LINKER");
    return try key.toOwnedSlice(allocator);
}
